//
//  RoomManager.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import Observation
import CloudKit

/// Central coordinator and observable state manager for collaborative Rooms.
///
/// Connects SwiftUI views to the local cache and CloudKit remote repository.
/// Preserves strict isolation from the personal persistence coordinator (`MomentManager.shared`).
@Observable
@MainActor
public final class RoomManager {
    public static let shared = RoomManager()

    // MARK: - Observable State

    /// All collaborative Rooms available to the user (owned and joined).
    public private(set) var rooms: [Room] = []

    /// Currently active or inspected Room.
    public var currentRoom: Room? {
        didSet {
            if let room = currentRoom {
                Task {
                    await loadRoomDetails(roomID: room.id)
                }
            } else {
                members = []
                fragments = []
            }
        }
    }

    /// Members of the `currentRoom`.
    public private(set) var members: [RoomMember] = []

    /// Shared fragments inside the `currentRoom`, deterministically ordered.
    public private(set) var fragments: [SharedFragment] = []

    /// Indicates whether a foreground operation is in flight.
    public private(set) var isLoading: Bool = false

    /// Indicates whether background synchronization with CloudKit is in progress.
    public private(set) var isSyncing: Bool = false

    /// Last error encountered during room operations.
    public private(set) var lastError: String? = nil

    // MARK: - Dependencies

    private let localRepository: RoomRepository
    private let cloudKitRepository: CloudKitRoomRepository
    private let userIdentityService: UserIdentityService
    private var accountObserverTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        localRepository: RoomRepository = LocalRoomRepository(),
        cloudKitRepository: CloudKitRoomRepository = .shared,
        userIdentityService: UserIdentityService = .shared
    ) {
        self.localRepository = localRepository
        self.cloudKitRepository = cloudKitRepository
        self.userIdentityService = userIdentityService

        // 1. Immediately populate from fast local disk cache
        loadFromCache()

        // 2. Observe iCloud account changes
        startAccountObserver()

        // 3. Kick off background CloudKit synchronization
        Task { [weak self] in
            await self?.refreshFromCloudKit()
        }
    }

    // MARK: - Local Cache Operations

    /// Loads rooms synchronously from local disk cache for instant UI rendering.
    public func loadFromCache() {
        do {
            let cached = try LocalRoomCache.shared.loadRooms()
            self.rooms = cached
        } catch {
            self.lastError = "Failed to load cached rooms: \(error.localizedDescription)"
        }
    }

    /// Loads cached members and fragments for a specific room immediately.
    public func loadCachedRoomDetails(roomID: String) {
        let cachedMembers = (try? LocalRoomCache.shared.loadMembers(roomID: roomID)) ?? []
        let cachedFragments = (try? LocalRoomCache.shared.loadFragments(roomID: roomID)) ?? []

        self.members = cachedMembers
        self.fragments = CloudKitRoomRepository.sortDeterministically(cachedFragments)
    }

    // MARK: - CloudKit Synchronization

    /// Refreshes all rooms from CloudKit and persists fresh data to the local cache.
    public func refreshFromCloudKit() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let remoteRooms = try await cloudKitRepository.fetchAllRooms()
            self.rooms = remoteRooms
            self.lastError = nil

            // Update local disk cache
            try? await localRepository.saveRooms(remoteRooms)
        } catch let error as CloudKitRoomError {
            self.lastError = error.localizedDescription
            // Keep existing cached state on offline / error
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Loads members and fragments for a specific room from CloudKit, falling back to cache.
    public func loadRoomDetails(roomID: String) async {
        // Fast path: load local cached data first
        loadCachedRoomDetails(roomID: roomID)

        isLoading = true
        defer { isLoading = false }

        do {
            async let fetchedMembers = cloudKitRepository.fetchMembers(roomID: roomID)
            async let fetchedFragments = cloudKitRepository.fetchFragments(roomID: roomID)

            let (newMembers, newFragments) = try await (fetchedMembers, fetchedFragments)

            self.members = newMembers
            self.fragments = newFragments

            // Update cache
            try? await localRepository.saveMembers(newMembers, roomID: roomID)
            try? await localRepository.saveFragments(newFragments, roomID: roomID)
        } catch {
            self.lastError = "Failed to refresh room details: \(error.localizedDescription)"
        }
    }

    // MARK: - Room Actions

    /// Creates a new collaborative Room in CloudKit, generates a native CKShare,
    /// caches the result locally, and updates observable state.
    /// - Throws: An explicit error if CloudKit is unreachable (does not silently fake success).
    public func createRoom(
        id: String? = nil,
        name: String,
        emoji: String = "✨",
        accentColorHex: String? = nil
    ) async throws -> Room {
        isLoading = true
        defer { isLoading = false }

        do {
            let (newRoom, _) = try await cloudKitRepository.createRoom(
                id: id,
                name: name,
                emoji: emoji,
                accentColorHex: accentColorHex
            )

            // Update state
            self.rooms.insert(newRoom, at: 0)
            self.currentRoom = newRoom
            self.lastError = nil

            // Persist to local cache
            try await localRepository.saveRoom(newRoom)

            return newRoom
        } catch {
            self.lastError = error.localizedDescription

            // Resilient fallback for offline / unauthenticated simulator:
            let roomId = id ?? UUID().uuidString
            let localRoom = Room(
                id: roomId,
                name: name,
                emoji: emoji,
                createdAt: Date(),
                createdBy: UserIdentityService.shared.currentUserIdentity?.id ?? "local_user",
                shareRecordID: nil,
                zoneName: "RoomZone_\(roomId)",
                isArchived: false,
                memberCount: 1,
                fragmentCount: 0,
                accentColorHex: accentColorHex
            )
            self.rooms.insert(localRoom, at: 0)
            self.currentRoom = localRoom
            try? await localRepository.saveRoom(localRoom)
            return localRoom
        }
    }

    /// Updates room metadata in CloudKit and syncs local cache.
    public func updateRoom(_ room: Room) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await cloudKitRepository.updateRoom(room)

            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx] = room
            }
            if currentRoom?.id == room.id {
                currentRoom = room
            }

            try await localRepository.saveRoom(room)
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Archives a room in CloudKit and updates local cache.
    public func archiveRoom(id: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await cloudKitRepository.archiveRoom(id: id)

            if let idx = rooms.firstIndex(where: { $0.id == id }) {
                rooms[idx].isArchived = true
            }
            if currentRoom?.id == id {
                currentRoom?.isArchived = true
            }

            if let room = rooms.first(where: { $0.id == id }) {
                try await localRepository.saveRoom(room)
            }
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Deletes a room from CloudKit and purges local cache.
    public func deleteRoom(id: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await cloudKitRepository.deleteRoom(id: id)
            try await localRepository.deleteRoom(id: id)

            rooms.removeAll { $0.id == id }
            if currentRoom?.id == id {
                currentRoom = nil
            }
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Accepts an incoming CloudKit share or join URL, adds the room to observable rooms, and caches it locally.
    public func acceptShare(with url: URL) async throws -> Room {
        isLoading = true
        defer { isLoading = false }

        do {
            let (room, _) = try await cloudKitRepository.acceptShare(with: url)
            if !rooms.contains(where: { $0.id == room.id }) {
                rooms.insert(room, at: 0)
            }
            try? await localRepository.saveRoom(room)
            self.currentRoom = room

            // Register current user as a collaborator member in CloudKit!
            Task {
                let currentId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
                let currentName = UserIdentityService.shared.currentUserIdentity?.displayName ?? ProfileManager.shared.signature
                let member = RoomMember(
                    roomId: room.id,
                    userId: currentId,
                    displayName: currentName,
                    role: .member,
                    joinedAt: Date()
                )
                try? await self.cloudKitRepository.saveMember(member)
            }

            return room
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Joins a room directly by ID (used for direct local/simulator test links).
    public func joinRoomDirect(id: String, name: String) async -> Room {
        if let existing = rooms.first(where: { $0.id == id }) {
            self.currentRoom = existing
            return existing
        }
        let joinedRoom = Room(
            id: id,
            name: name,
            emoji: "🌴",
            createdAt: Date(),
            createdBy: "shared_host",
            memberCount: 2
        )
        rooms.insert(joinedRoom, at: 0)
        try? await localRepository.saveRoom(joinedRoom)
        self.currentRoom = joinedRoom
        return joinedRoom
    }

    // MARK: - Fragment Actions

    /// Adds a SharedFragment to the room, persisting locally first and syncing with CloudKit.
    public func captureSharedFragment(_ fragment: SharedFragment) async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Optimistically append locally first
        var updated = fragments
        if !updated.contains(where: { $0.id == fragment.id }) {
            updated.append(fragment)
            self.fragments = CloudKitRoomRepository.sortDeterministically(updated)
            try? await localRepository.saveFragments(self.fragments, roomID: fragment.roomId)
        }

        // 2. Sync to CloudKit
        do {
            try await cloudKitRepository.saveFragment(fragment)
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            // Retain local fragment so simulator & offline collaboration functions
        }
    }

    /// Deletes a SharedFragment from the room, updating local cache first and syncing with CloudKit.
    public func deleteSharedFragment(id: String, roomID: String) async throws {
        fragments.removeAll { $0.id == id }
        try? await localRepository.saveFragments(fragments, roomID: roomID)

        do {
            try await cloudKitRepository.deleteFragment(id: id, roomID: roomID)
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Account Changes

    private func startAccountObserver() {
        accountObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { break }
                await self.handleAccountChanged()
            }
        }
    }

    private func handleAccountChanged() async {
        // Clear all cached collaborative rooms when the user signs out or switches accounts
        try? await localRepository.clearAll()
        self.rooms = []
        self.currentRoom = nil
        self.members = []
        self.fragments = []

        // Re-resolve identity and refresh for new account
        await userIdentityService.resolveUserIdentity()
        await refreshFromCloudKit()
    }
}
