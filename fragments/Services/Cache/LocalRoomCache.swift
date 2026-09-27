//
//  LocalRoomCache.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation

/// Lightweight, file-backed local disk cache for collaborative Room metadata.
///
/// Stores room configurations, member rosters, and fragment metadata in `Library/Caches/Rooms/`
/// using atomic writes. Operates independently from personal SwiftData SQLite.
public final class LocalRoomCache: Sendable {
    public static let shared = LocalRoomCache()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Root directory URL for Room caches: `Library/Caches/Rooms/`
    public let baseCacheDirectory: URL

    // MARK: - Initialization

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory = baseDirectory {
            self.baseCacheDirectory = baseDirectory
        } else {
            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseCacheDirectory = cachesURL.appendingPathComponent("Rooms", isDirectory: true)
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        ensureBaseDirectoryExists()
    }

    // MARK: - Directory Helpers

    private func ensureBaseDirectoryExists() {
        if !fileManager.fileExists(atPath: baseCacheDirectory.path) {
            try? fileManager.createDirectory(at: baseCacheDirectory, withIntermediateDirectories: true)
        }
    }

    private func roomDirectory(for roomID: String) -> URL {
        baseCacheDirectory.appendingPathComponent(roomID, isDirectory: true)
    }

    private var manifestURL: URL {
        baseCacheDirectory.appendingPathComponent("rooms_manifest.json")
    }

    private func ensureRoomDirectoryExists(for roomID: String) throws {
        let dir = roomDirectory(for: roomID)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Manifest (Rooms)

    /// Loads the list of cached rooms from `rooms_manifest.json`.
    /// Recovers gracefully if file is corrupted.
    public func loadRooms() throws -> [Room] {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let rooms = try decoder.decode([Room].self, from: data)
            return rooms
        } catch {
            // Corrupted cache recovery: quarantine or remove corrupt manifest
            try? fileManager.removeItem(at: manifestURL)
            return []
        }
    }

    /// Loads a single room by its ID from its individual cached directory or manifest.
    public func loadRoom(id: String) throws -> Room? {
        let roomURL = roomDirectory(for: id).appendingPathComponent("room.json")
        if fileManager.fileExists(atPath: roomURL.path) {
            if let data = try? Data(contentsOf: roomURL),
               let room = try? decoder.decode(Room.self, from: data) {
                return room
            }
        }
        return try loadRooms().first(where: { $0.id == id })
    }

    /// Saves a single room into the manifest and updates its individual `room.json`.
    public func saveRoom(_ room: Room) throws {
        ensureBaseDirectoryExists()
        var existing = (try? loadRooms()) ?? []
        if let index = existing.firstIndex(where: { $0.id == room.id }) {
            existing[index] = room
        } else {
            existing.append(room)
        }

        // Atomic write to manifest
        let manifestData = try encoder.encode(existing)
        try manifestData.write(to: manifestURL, options: .atomic)

        // Write individual room.json inside its folder
        try ensureRoomDirectoryExists(for: room.id)
        let roomURL = roomDirectory(for: room.id).appendingPathComponent("room.json")
        let roomData = try encoder.encode(room)
        try roomData.write(to: roomURL, options: .atomic)
    }

    /// Saves the full array of rooms into the manifest atomically.
    public func saveRooms(_ rooms: [Room]) throws {
        ensureBaseDirectoryExists()
        let manifestData = try encoder.encode(rooms)
        try manifestData.write(to: manifestURL, options: .atomic)

        for room in rooms {
            try? ensureRoomDirectoryExists(for: room.id)
            let roomURL = roomDirectory(for: room.id).appendingPathComponent("room.json")
            if let roomData = try? encoder.encode(room) {
                try? roomData.write(to: roomURL, options: .atomic)
            }
        }
    }

    /// Deletes a room from the manifest and purges its cached directory.
    public func deleteRoom(id: String) throws {
        var existing = (try? loadRooms()) ?? []
        existing.removeAll { $0.id == id }

        let manifestData = try encoder.encode(existing)
        try manifestData.write(to: manifestURL, options: .atomic)

        let dir = roomDirectory(for: id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    // MARK: - Members

    /// Loads cached members for a specific room.
    public func loadMembers(roomID: String) throws -> [RoomMember] {
        let membersURL = roomDirectory(for: roomID).appendingPathComponent("members.json")
        guard fileManager.fileExists(atPath: membersURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: membersURL)
            let members = try decoder.decode([RoomMember].self, from: data)
            return members
        } catch {
            // Corrupted cache recovery
            try? fileManager.removeItem(at: membersURL)
            return []
        }
    }

    /// Saves members for a room atomically to `{roomID}/members.json`.
    public func saveMembers(_ members: [RoomMember], roomID: String) throws {
        try ensureRoomDirectoryExists(for: roomID)
        let membersURL = roomDirectory(for: roomID).appendingPathComponent("members.json")
        let data = try encoder.encode(members)
        try data.write(to: membersURL, options: .atomic)
    }

    // MARK: - Shared Fragments

    /// Loads cached shared fragments for a room.
    public func loadFragments(roomID: String) throws -> [SharedFragment] {
        let fragmentsURL = roomDirectory(for: roomID).appendingPathComponent("fragments.json")
        guard fileManager.fileExists(atPath: fragmentsURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fragmentsURL)
            let fragments = try decoder.decode([SharedFragment].self, from: data)
            return fragments
        } catch {
            // Corrupted cache recovery
            try? fileManager.removeItem(at: fragmentsURL)
            return []
        }
    }

    /// Saves shared fragments for a room atomically to `{roomID}/fragments.json`.
    public func saveFragments(_ fragments: [SharedFragment], roomID: String) throws {
        try ensureRoomDirectoryExists(for: roomID)
        let fragmentsURL = roomDirectory(for: roomID).appendingPathComponent("fragments.json")
        let data = try encoder.encode(fragments)
        try data.write(to: fragmentsURL, options: .atomic)
    }

    // MARK: - Invalidation & Cleanup

    /// Invalidates and deletes all cached files for a specific room.
    public func invalidateRoom(id: String) throws {
        try deleteRoom(id: id)
    }

    /// Clears the entire Room cache directory.
    public func clearAll() throws {
        if fileManager.fileExists(atPath: baseCacheDirectory.path) {
            try fileManager.removeItem(at: baseCacheDirectory)
        }
        ensureBaseDirectoryExists()
    }
}
