//
//  RoomManager.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import Observation
import CloudKit
import Supabase

/// Central coordinator and observable state manager for collaborative Rooms.
///
/// Dynamically routes room operations to either CloudKit (legacy) or Supabase (new)
/// based on each Room's backend origin (`RoomBackend`).
/// Manages scoped Supabase Realtime event streams, local disk caching, and deterministic ordering.
@Observable
@MainActor
public final class RoomManager {
    public static let shared = RoomManager()

    // MARK: - Observable State

    /// All collaborative Rooms available to the user (owned and joined, across backends).
    public private(set) var rooms: [Room] = []

    /// Currently active or inspected Room.
    public var currentRoom: Room? {
        didSet {
            handleCurrentRoomChanged(oldRoom: oldValue, newRoom: currentRoom)
        }
    }

    /// Members of the `currentRoom`.
    public private(set) var members: [RoomMember] = []

    /// Shared fragments inside the `currentRoom`, deterministically ordered.
    public private(set) var fragments: [SharedFragment] = []

    /// Indicates whether a foreground operation is in flight.
    public private(set) var isLoading: Bool = false

    /// Indicates whether background synchronization is in progress.
    public private(set) var isSyncing: Bool = false

    /// Last error encountered during room operations.
    public private(set) var lastError: String? = nil

    /// Active collaborative Supabase Rooms eligible for publishing personal fragments.
    public var eligibleSupabaseRooms: [Room] {
        rooms.filter { room in
            room.backend == .supabase && !room.isEnded && !room.isArchived
        }
    }

    // MARK: - Dependencies & Lifecycle

    private let localRepository: RoomRepository
    private let cloudKitRepository: CloudKitRoomRepository
    private let supabaseRepository: SharedMomentRepository
    private let realtimeCoordinator: SupabaseRealtimeCoordinator
    private let supabaseService: SupabaseService
    private let userIdentityService: UserIdentityService

    private var accountObserverTask: Task<Void, Never>?
    private var supabaseAuthObserverTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var currentDetailsTask: Task<Void, Never>?

    /// Monotonically increasing generation token used to discard stale async fetch responses across room switches.
    private var activeRoomGeneration: UInt64 = 0

    // MARK: - Realtime Domain Event Stream
    private var realtimeContinuations: [UUID: AsyncStream<SupabaseRealtimeEvent>.Continuation] = [:]

    /// Async stream of typed Realtime domain events processed and verified by RoomManager.
    public var realtimeEvents: AsyncStream<SupabaseRealtimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            realtimeContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.realtimeContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func broadcastRealtimeEvent(_ event: SupabaseRealtimeEvent) {
        for continuation in realtimeContinuations.values {
            continuation.yield(event)
        }
    }

    /// In-memory cache of user profiles (display name & avatar) to avoid N+1 requests during Realtime member joins.
    private var profileCache: [String: (displayName: String, avatarURL: URL?)] = [:]

    // MARK: - Initialization

    public init(
        localRepository: RoomRepository = LocalRoomRepository(),
        cloudKitRepository: CloudKitRoomRepository = .shared,
        supabaseRepository: SharedMomentRepository = SupabaseRoomRepository.shared,
        realtimeCoordinator: SupabaseRealtimeCoordinator = .shared,
        supabaseService: SupabaseService = .shared,
        userIdentityService: UserIdentityService = .shared
    ) {
        self.localRepository = localRepository
        self.cloudKitRepository = cloudKitRepository
        self.supabaseRepository = supabaseRepository
        self.realtimeCoordinator = realtimeCoordinator
        self.supabaseService = supabaseService
        self.userIdentityService = userIdentityService

        // 1. Immediately populate from fast local disk cache
        loadFromCache()

        // 2. Observe iCloud and Supabase account changes
        startAccountObservers()

        // 3. Kick off background synchronization
        Task { [weak self] in
            await self?.refreshAllRooms()
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

    // MARK: - Remote Synchronization

    /// Refreshes all collaborative rooms from both CloudKit and Supabase (if authenticated),
    /// merging results and persisting to local cache.
    public func refreshAllRooms() async {
        isSyncing = true
        defer { isSyncing = false }

        var allRemoteRooms: [Room] = []

        var ckSuccess = false
        var sbSuccess = false

        // 1. Fetch from CloudKit
        do {
            let ckRooms = try await cloudKitRepository.fetchAllRooms()
            allRemoteRooms.append(contentsOf: ckRooms)
            ckSuccess = true
        } catch let error as CloudKitRoomError {
            self.lastError = error.localizedDescription
        } catch {
            self.lastError = error.localizedDescription
        }

        // 2. Fetch from Supabase if authenticated
        if supabaseService.isAuthenticated {
            do {
                let sbRooms = try await supabaseRepository.fetchRooms()
                allRemoteRooms.append(contentsOf: sbRooms)
                sbSuccess = true
            } catch {
                self.lastError = error.localizedDescription
            }
        }

        // Update self.rooms if at least one remote backend successfully responded
        if ckSuccess || sbSuccess {
            // Deduplicate rooms by ID (prefer newer or remote)
            var seen = Set<String>()
            var merged: [Room] = []
            for room in allRemoteRooms {
                if !seen.contains(room.id) {
                    seen.insert(room.id)
                    merged.append(room)
                }
            }
            // Sort by createdAt descending
            merged.sort { $0.createdAt > $1.createdAt }
            self.rooms = merged
            self.lastError = nil

            // Persist to local disk cache
            try? await localRepository.saveRooms(merged)
        }
    }

    /// Backwards-compatible alias for refreshing rooms.
    public func refreshFromCloudKit() async {
        await refreshAllRooms()
    }

    /// Loads members and fragments for a specific room from its corresponding backend, falling back to cache.
    public func loadRoomDetails(roomID: String) async {
        // Fast path: load local cached data first
        loadCachedRoomDetails(roomID: roomID)

        let targetBackend = rooms.first(where: { $0.id == roomID })?.backend
            ?? (currentRoom?.id == roomID ? currentRoom?.backend : nil)
            ?? .cloudKit

        let generation = activeRoomGeneration

        isLoading = true
        defer { isLoading = false }

        if targetBackend == .supabase {
            // Ensure Realtime is connected for this room if it is current
            if currentRoom?.id == roomID && realtimeTask == nil {
                await startRealtime(for: roomID)
            }

            do {
                async let fetchedMembers = supabaseRepository.fetchMembers(roomID: roomID)
                async let fetchedFragments = supabaseRepository.fetchFragments(roomID: roomID)

                let (newMembers, newFragments) = try await (fetchedMembers, fetchedFragments)

                // Discard stale response if user switched rooms during the fetch
                guard self.activeRoomGeneration == generation && self.currentRoom?.id == roomID else { return }

                self.members = newMembers
                for member in newMembers {
                    if !member.displayName.isEmpty && member.displayName != "Member" {
                        self.profileCache[member.userId] = (member.displayName, member.avatarAssetURL)
                    }
                }
                // Safely reconcile with existing in-memory fragments so newer Realtime events are not lost
                self.fragments = self.mergeFragments(existing: self.fragments, incoming: newFragments)

                // Update cache
                try? await localRepository.saveMembers(newMembers, roomID: roomID)
                try? await localRepository.saveFragments(self.fragments, roomID: roomID)
            } catch {
                self.lastError = "Failed to refresh room details: \(error.localizedDescription)"
            }
        } else {
            do {
                async let fetchedMembers = cloudKitRepository.fetchMembers(roomID: roomID)
                async let fetchedFragments = cloudKitRepository.fetchFragments(roomID: roomID)

                let (newMembers, newFragments) = try await (fetchedMembers, fetchedFragments)

                guard self.activeRoomGeneration == generation && self.currentRoom?.id == roomID else { return }

                self.members = newMembers
                self.fragments = newFragments

                // Update cache
                try? await localRepository.saveMembers(newMembers, roomID: roomID)
                try? await localRepository.saveFragments(newFragments, roomID: roomID)
            } catch {
                self.lastError = "Failed to refresh room details: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Room Actions

    /// Creates a new collaborative Room, explicitly defaulting to Supabase.
    /// Legacy CloudKit creation is available by explicitly specifying `backend: .cloudKit`.
    ///
    /// - Important: Does not silently fall back to CloudKit when Supabase fails or is unauthenticated.
    public func createRoom(
        id: String? = nil,
        name: String,
        emoji: String = "✨",
        accentColorHex: String? = nil,
        createdAt: Date? = nil,
        backend: RoomBackend = .supabase
    ) async throws -> Room {
        isLoading = true
        defer { isLoading = false }

        if backend == .supabase {
            do {
                let newRoom = try await supabaseRepository.createRoom(
                    id: id,
                    name: name,
                    emoji: emoji,
                    accentColorHex: accentColorHex
                )

                if let idx = self.rooms.firstIndex(where: { $0.id == newRoom.id }) {
                    self.rooms[idx] = newRoom
                } else {
                    self.rooms.insert(newRoom, at: 0)
                }
                self.currentRoom = newRoom
                self.lastError = nil

                try await localRepository.saveRoom(newRoom)
                return newRoom
            } catch {
                self.lastError = error.localizedDescription
                throw error
            }
        } else {
            do {
                let (newRoom, _) = try await cloudKitRepository.createRoom(
                    id: id,
                    name: name,
                    emoji: emoji,
                    accentColorHex: accentColorHex,
                    createdAt: createdAt
                )

                self.rooms.insert(newRoom, at: 0)
                self.currentRoom = newRoom
                self.lastError = nil

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
                    createdAt: createdAt ?? Date(),
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
    }

    /// Joins an existing Supabase collaborative Room by join code.
    public func joinRoom(code: String) async throws -> Room {
        isLoading = true
        defer { isLoading = false }

        do {
            let joinedRoom = try await supabaseRepository.joinRoom(code: code)

            if let idx = rooms.firstIndex(where: { $0.id == joinedRoom.id }) {
                rooms[idx] = joinedRoom
            } else {
                rooms.insert(joinedRoom, at: 0)
            }
            self.currentRoom = joinedRoom
            self.lastError = nil

            try await localRepository.saveRoom(joinedRoom)
            return joinedRoom
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Updates room metadata in the appropriate backend and syncs local cache upon remote success.
    public func updateRoom(_ room: Room) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            if room.backend == .supabase {
                try await supabaseRepository.updateRoom(room)
            } else {
                try await cloudKitRepository.updateRoom(room)
            }

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

    /// Archives a room in the appropriate backend and updates local cache upon remote success.
    public func archiveRoom(id: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let targetBackend = rooms.first(where: { $0.id == id })?.backend
            ?? (currentRoom?.id == id ? currentRoom?.backend : nil)
            ?? .cloudKit

        do {
            if targetBackend == .supabase {
                try await supabaseRepository.archiveRoom(roomID: id)
            } else {
                try await cloudKitRepository.archiveRoom(id: id)
            }

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

    /// Deletes a room from the appropriate backend and purges local cache upon remote success.
    public func deleteRoom(id: String) async throws {
        isLoading = true
        defer { isLoading = false }

        var targetBackend = rooms.first(where: { $0.id == id })?.backend
            ?? (currentRoom?.id == id ? currentRoom?.backend : nil)
        if targetBackend == nil {
            targetBackend = (try? await localRepository.loadRoom(id: id))?.backend
        }
        let resolvedBackend = targetBackend ?? .cloudKit

        do {
            if resolvedBackend == .supabase {
                try await supabaseRepository.deleteRoom(roomID: id)
            } else {
                try await cloudKitRepository.deleteRoom(id: id)
            }

            try await localRepository.deleteRoom(id: id)

            rooms.removeAll { $0.id == id }
            if currentRoom?.id == id {
                stopRealtime(roomID: id)
                currentRoom = nil
            }
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Removes a room from the local device only, notifying remote backend if Supabase.
    public func leaveRoom(id: String) async {
        var targetBackend = rooms.first(where: { $0.id == id })?.backend
            ?? (currentRoom?.id == id ? currentRoom?.backend : nil)
        if targetBackend == nil {
            targetBackend = (try? await localRepository.loadRoom(id: id))?.backend
        }
        let resolvedBackend = targetBackend ?? .cloudKit

        if resolvedBackend == .supabase {
            do {
                try await supabaseRepository.leaveRoom(roomID: id)
            } catch {
                self.lastError = "Failed to leave room remotely: \(error.localizedDescription)"
            }
        }

        if currentRoom?.id == id {
            stopRealtime(roomID: id)
            currentRoom = nil
        }
        rooms.removeAll { $0.id == id }
        try? await localRepository.deleteRoom(id: id)
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
    public func joinRoomDirect(id: String, name: String, createdAt: Date? = nil) async -> Room {
        if let existing = rooms.first(where: { $0.id == id }) {
            if let createdAt = createdAt, abs(existing.createdAt.timeIntervalSince(createdAt)) > 0.5 {
                var updated = existing
                updated.createdAt = createdAt
                if let idx = rooms.firstIndex(where: { $0.id == id }) {
                    rooms[idx] = updated
                }
                self.currentRoom = updated
                try? await localRepository.saveRoom(updated)
                return updated
            }
            self.currentRoom = existing
            return existing
        }
        let joinedRoom = Room(
            id: id,
            name: name,
            emoji: "✨",
            createdAt: createdAt ?? Date(),
            createdBy: "shared_host",
            memberCount: 2
        )
        rooms.insert(joinedRoom, at: 0)
        try? await localRepository.saveRoom(joinedRoom)
        self.currentRoom = joinedRoom
        return joinedRoom
    }

    // MARK: - Fragment Actions

    /// Adds a SharedFragment to the room, persisting locally first and syncing with the appropriate backend.
    /// Rolls back optimistic local state if remote synchronization fails.
    public func captureSharedFragment(_ fragment: SharedFragment) async throws {
        isLoading = true
        defer { isLoading = false }

        let targetBackend = rooms.first(where: { $0.id == fragment.roomId })?.backend
            ?? (currentRoom?.id == fragment.roomId ? currentRoom?.backend : nil)
            ?? .cloudKit

        // 1. Optimistically append locally first
        if currentRoom?.id == fragment.roomId {
            var updated = fragments
            if !updated.contains(where: { $0.id == fragment.id }) {
                updated.append(fragment)
                self.fragments = CloudKitRoomRepository.sortDeterministically(updated)
                try? await localRepository.saveFragments(self.fragments, roomID: fragment.roomId)
            }
        } else {
            var cached = (try? await localRepository.loadFragments(roomID: fragment.roomId)) ?? []
            if !cached.contains(where: { $0.id == fragment.id }) {
                cached.append(fragment)
                try? await localRepository.saveFragments(cached, roomID: fragment.roomId)
            }
        }

        // 2. Sync to appropriate backend
        if targetBackend == .supabase {
            do {
                _ = try await supabaseRepository.createFragmentWithMedia(fragment)
                self.lastError = nil
            } catch {
                // Rollback optimistic append on Supabase failure
                if currentRoom?.id == fragment.roomId {
                    self.fragments.removeAll { $0.id == fragment.id }
                    try? await localRepository.saveFragments(self.fragments, roomID: fragment.roomId)
                } else {
                    var cached = (try? await localRepository.loadFragments(roomID: fragment.roomId)) ?? []
                    cached.removeAll { $0.id == fragment.id }
                    try? await localRepository.saveFragments(cached, roomID: fragment.roomId)
                }
                self.lastError = error.localizedDescription
                throw error
            }
        } else {
            // CloudKit path
            do {
                try await cloudKitRepository.saveFragment(fragment)
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
                // Retain local fragment so simulator & offline collaboration functions
            }
        }
    }

    /// Publishes an existing personal Fragment into an active collaborative Supabase Room.
    ///
    /// Validates authentication, room eligibility, local media accessibility, converts the fragment
    /// to an independent collaborative copy with a new ID, and publishes to Supabase.
    /// The original personal Fragment remains completely untouched in local SwiftData storage.
    @discardableResult
    public func sharePersonalFragment(_ fragment: Fragment, to room: Room) async throws -> SharedFragment {
        // 1. Authentication Check
        guard supabaseService.isAuthenticated,
              let authorId = userIdentityService.collaborativeUserID,
              let _ = UUID(uuidString: authorId) else {
            throw SupabaseRoomError.notAuthenticated
        }

        // 2. Room Eligibility Check
        guard room.backend == .supabase else {
            throw SupabaseRoomError.validationFailure("Collaborative sharing is only supported for Supabase rooms.")
        }
        guard !room.isEnded else {
            throw SupabaseRoomError.validationFailure("This room has ended and is closed to new fragments.")
        }
        guard !room.isArchived else {
            throw SupabaseRoomError.validationFailure("This room is archived and cannot receive new fragments.")
        }

        // 3. Media Existence Check (for non-text fragments)
        if fragment.type != .note {
            guard let mediaURL = fragment.mediaURL, FileManager.default.fileExists(atPath: mediaURL.path) else {
                throw SupabaseRoomError.validationFailure("The original media file is missing or inaccessible on this device.")
            }
        }

        // 4. Convert to independent collaborative copy (new ID ensures personal ID != shared ID)
        let authorName = ProfileManager.shared.effectiveName
        let sharedFragment = fragment.toCollaborativeCopy(
            forRoomId: room.id,
            authorId: authorId,
            authorName: authorName
        )

        // 5. Publish to room via existing captureSharedFragment pipeline
        try await captureSharedFragment(sharedFragment)

        return sharedFragment
    }

    /// Deletes a SharedFragment from the room, updating local cache first and syncing with the backend.
    /// Rolls back optimistic removal if remote synchronization fails.
    public func deleteSharedFragment(id: String, roomID: String) async throws {
        let targetBackend = rooms.first(where: { $0.id == roomID })?.backend
            ?? (currentRoom?.id == roomID ? currentRoom?.backend : nil)
            ?? .cloudKit

        let rollbackFragments = fragments
        fragments.removeAll { $0.id == id }
        try? await localRepository.saveFragments(fragments, roomID: roomID)

        if targetBackend == .supabase {
            do {
                try await supabaseRepository.deleteFragment(fragmentID: id, roomID: roomID)
                self.lastError = nil
            } catch {
                // Rollback optimistic removal on Supabase failure
                self.fragments = rollbackFragments
                try? await localRepository.saveFragments(rollbackFragments, roomID: roomID)
                self.lastError = error.localizedDescription
                throw error
            }
        } else {
            do {
                try await cloudKitRepository.deleteFragment(id: id, roomID: roomID)
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Realtime Coordination & Event Handling

    private func handleCurrentRoomChanged(oldRoom: Room?, newRoom: Room?) {
        // If unchanged, do not tear down or re-subscribe
        if oldRoom?.id == newRoom?.id && oldRoom?.backend == newRoom?.backend {
            return
        }

        activeRoomGeneration &+= 1
        currentDetailsTask?.cancel()
        currentDetailsTask = nil

        // 1. Clean up previous Realtime subscription if old room was Supabase
        if oldRoom?.backend == .supabase {
            stopRealtime(roomID: oldRoom?.id)
        }

        guard let room = newRoom else {
            members = []
            fragments = []
            return
        }

        // 2. Fast-path load cached details
        loadCachedRoomDetails(roomID: room.id)

        // 3. Launch background sync and Realtime subscription with generation guard
        let generation = activeRoomGeneration
        currentDetailsTask = Task { [weak self] in
            guard let self else { return }

            if room.backend == .supabase {
                await self.startRealtime(for: room.id)
            }

            guard !Task.isCancelled && self.activeRoomGeneration == generation else { return }
            await self.loadRoomDetails(roomID: room.id)
        }
    }

    public func startRealtime(for roomID: String) async {
        if realtimeTask != nil && realtimeCoordinator.activeRoomID == roomID && realtimeCoordinator.connectionState == .connected {
            return
        }
        realtimeTask?.cancel()
        realtimeTask = nil

        print("📡 [RoomManager] Starting Realtime connection for room: \(roomID)")
        do {
            try await realtimeCoordinator.start(roomID: roomID)
            print("🟢 [RoomManager] Realtime connected for room: \(roomID)")

            realtimeTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.realtimeCoordinator.events {
                    guard !Task.isCancelled else { break }
                    guard self.currentRoom?.id == roomID else { break }
                    await self.handleRealtimeEvent(event, forRoomID: roomID)
                }
            }
        } catch {
            self.lastError = "Realtime connection failed: \(error.localizedDescription)"
            print("❌ [RoomManager] Realtime connection failed for room \(roomID): \(error.localizedDescription)")
        }
    }

    public func stopRealtime(roomID: String? = nil) {
        let targetID = roomID ?? currentRoom?.id
        print("🛑 [RoomManager] Teardown Realtime subscription for room: \(targetID ?? "unknown")")
        realtimeTask?.cancel()
        realtimeTask = nil

        Task { [weak self] in
            await self?.realtimeCoordinator.stop(roomID: targetID)
        }
    }

    /// Handles a typed Realtime event from Supabase, updating observable state and reconciling if needed.
    public func handleRealtimeEvent(_ event: SupabaseRealtimeEvent, forRoomID roomID: String) async {
        guard currentRoom?.id == roomID else { return }

        switch event {
        case .roomChanged(let updatedRoom):
            if currentRoom?.id == updatedRoom.id {
                currentRoom = updatedRoom
            }
            if let idx = rooms.firstIndex(where: { $0.id == updatedRoom.id }) {
                rooms[idx] = updatedRoom
            } else {
                rooms.insert(updatedRoom, at: 0)
            }
            try? await localRepository.saveRoom(updatedRoom)

        case .roomDeleted(let deletedID):
            if currentRoom?.id == deletedID {
                stopRealtime(roomID: deletedID)
                currentRoom = nil
                members = []
                fragments = []
            }
            rooms.removeAll { $0.id == deletedID }
            try? await localRepository.deleteRoom(id: deletedID)

        case .memberJoined(var member):
            guard member.roomId == roomID else { return }
            if member.displayName == "Member" || member.displayName.isEmpty {
                if let cached = profileCache[member.userId] {
                    member.displayName = cached.displayName
                    member.avatarAssetURL = cached.avatarURL
                } else if let userUUID = UUID(uuidString: member.userId) {
                    if let repo = supabaseRepository as? SupabaseRoomRepository {
                        if let profile = try? await repo.fetchUserProfile(userID: userUUID) {
                            member.displayName = profile.displayName
                            let avatarURL: URL? = profile.avatarStoragePath.flatMap { URL(string: $0) }
                            member.avatarAssetURL = avatarURL
                            profileCache[member.userId] = (profile.displayName, avatarURL)
                        }
                    }
                }
            }
            if let idx = members.firstIndex(where: { $0.id == member.id || ($0.userId == member.userId && $0.roomId == member.roomId) }) {
                members[idx] = member
            } else {
                members.append(member)
            }
            try? await localRepository.saveMembers(members, roomID: roomID)

        case .memberChanged(var member):
            guard member.roomId == roomID else { return }
            if member.displayName == "Member" || member.displayName.isEmpty {
                if let cached = profileCache[member.userId] {
                    member.displayName = cached.displayName
                    member.avatarAssetURL = cached.avatarURL
                } else if let userUUID = UUID(uuidString: member.userId) {
                    if let repo = supabaseRepository as? SupabaseRoomRepository {
                        if let profile = try? await repo.fetchUserProfile(userID: userUUID) {
                            member.displayName = profile.displayName
                            let avatarURL: URL? = profile.avatarStoragePath.flatMap { URL(string: $0) }
                            member.avatarAssetURL = avatarURL
                            profileCache[member.userId] = (profile.displayName, avatarURL)
                        }
                    }
                }
            }
            if let idx = members.firstIndex(where: { $0.id == member.id || ($0.userId == member.userId && $0.roomId == member.roomId) }) {
                members[idx] = member
            } else {
                members.append(member)
            }
            try? await localRepository.saveMembers(members, roomID: roomID)

        case .memberLeft(let memberID, let rID, let userID):
            guard rID == roomID else { return }
            members.removeAll { $0.id == memberID || ($0.userId == userID && $0.roomId == rID) }
            try? await localRepository.saveMembers(members, roomID: roomID)

        case .fragmentCreated(let newFragment):
            guard newFragment.roomId == roomID else { return }
            if !fragments.contains(where: { $0.id == newFragment.id }) {
                var updated = fragments
                updated.append(newFragment)
                fragments = CloudKitRoomRepository.sortDeterministically(updated)
                try? await localRepository.saveFragments(fragments, roomID: roomID)
            }

        case .fragmentUpdated(let updatedFragment):
            guard updatedFragment.roomId == roomID else { return }
            if let idx = fragments.firstIndex(where: { $0.id == updatedFragment.id }) {
                fragments[idx] = updatedFragment
            } else {
                fragments.append(updatedFragment)
            }
            fragments = CloudKitRoomRepository.sortDeterministically(fragments)
            try? await localRepository.saveFragments(fragments, roomID: roomID)

        case .fragmentDeleted(let fragmentID, let rID, _):
            guard rID == roomID else { return }
            fragments.removeAll { $0.id == fragmentID }
            try? await localRepository.saveFragments(fragments, roomID: roomID)

        case .fragmentMediaCreated(let media, let fragmentID, let rID):
            guard rID == roomID else { return }
            if let idx = fragments.firstIndex(where: { $0.id == fragmentID }) {
                var fragment = fragments[idx]
                fragment.mediaReference = media
                fragments[idx] = fragment
                try? await localRepository.saveFragments(fragments, roomID: roomID)
            } else {
                // Dependency missing: fragment record isn't in memory yet!
                // Trigger scoped reconciliation fetch
                await reconcileFragments(roomID: roomID)
            }

        case .fragmentMediaDeleted(let storagePath, let fragmentID, let rID):
            guard rID == roomID else { return }
            if let idx = fragments.firstIndex(where: { $0.id == fragmentID }) {
                var fragment = fragments[idx]
                if fragment.mediaReference?.storagePath == storagePath || fragment.mediaReference?.assetKey == storagePath {
                    fragment.mediaReference = nil
                    fragments[idx] = fragment
                    try? await localRepository.saveFragments(fragments, roomID: roomID)
                    try? await RemoteMediaService.shared.removeMedia(for: storagePath, roomID: rID)
                }
            }
        }

        // Forward typed domain event to subscribers (e.g. MomentManager)
        broadcastRealtimeEvent(event)
    }

    /// Performs an authoritative scoped refetch of fragments from the remote database to reconcile state.
    /// Employs generation checks and non-destructive merging to prevent race conditions with active Realtime streams.
    public func reconcileFragments(roomID: String) async {
        guard currentRoom?.id == roomID else { return }
        let targetBackend = currentRoom?.backend ?? .cloudKit
        let generation = activeRoomGeneration

        if targetBackend == .supabase {
            do {
                let fetched = try await supabaseRepository.fetchFragments(roomID: roomID)
                guard self.activeRoomGeneration == generation && self.currentRoom?.id == roomID else { return }

                self.fragments = self.mergeFragments(existing: self.fragments, incoming: fetched)
                try? await localRepository.saveFragments(self.fragments, roomID: roomID)
            } catch {
                self.lastError = "Reconcile fragments failed: \(error.localizedDescription)"
            }
        }
    }

    /// Reconciles an incoming remote snapshot of fragments with existing in-memory fragments,
    /// ensuring that newer realtime events and local modifications are never lost.
    public func mergeFragments(existing: [SharedFragment], incoming: [SharedFragment]) -> [SharedFragment] {
        var mergedMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for remoteFrag in incoming {
            if let localFrag = mergedMap[remoteFrag.id] {
                var resolved = localFrag
                if resolved.mediaReference == nil && remoteFrag.mediaReference != nil {
                    resolved.mediaReference = remoteFrag.mediaReference
                }
                if remoteFrag.createdAt >= localFrag.createdAt {
                    if let newText = remoteFrag.text { resolved.text = newText }
                    if !remoteFrag.title.isEmpty { resolved.title = remoteFrag.title }
                }
                mergedMap[remoteFrag.id] = resolved
            } else {
                mergedMap[remoteFrag.id] = remoteFrag
            }
        }
        return CloudKitRoomRepository.sortDeterministically(Array(mergedMap.values))
    }

    // MARK: - Account Observers

    private func startAccountObservers() {
        // 1. iCloud Account Changes
        accountObserverTask?.cancel()
        accountObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { break }
                await self.handleCloudKitAccountChanged()
            }
        }

        // 2. Supabase Auth Changes
        supabaseAuthObserverTask?.cancel()
        let auth = supabaseService.client.auth
        supabaseAuthObserverTask = Task { [weak self] in
            for await (event, _) in auth.authStateChanges {
                guard let self else { break }
                guard !Task.isCancelled else { break }
                if event == .signedOut {
                    await self.handleSupabaseSignedOut()
                } else if event == .signedIn {
                    await self.refreshAllRooms()
                }
            }
        }
    }

    private func handleCloudKitAccountChanged() async {
        // Clear all cached collaborative rooms when the iCloud user signs out or switches accounts
        try? await localRepository.clearAll()
        self.rooms = []
        self.currentRoom = nil
        self.members = []
        self.fragments = []

        // Re-resolve identity and refresh
        await userIdentityService.resolveUserIdentity()
        await refreshAllRooms()
    }

    private func handleSupabaseSignedOut() async {
        if currentRoom?.backend == .supabase {
            stopRealtime(roomID: currentRoom?.id)
            self.currentRoom = nil
            self.members = []
            self.fragments = []
        }
        self.rooms.removeAll { $0.backend == .supabase }
        try? await localRepository.saveRooms(self.rooms)
    }
}
