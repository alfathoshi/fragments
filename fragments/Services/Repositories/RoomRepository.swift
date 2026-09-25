//
//  RoomRepository.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation

/// Repository protocol defining local persistence operations for collaborative Rooms.
///
/// Implementations must be independent from CloudKit network synchronization.
public protocol RoomRepository: Sendable {
    func loadRooms() async throws -> [Room]
    func saveRoom(_ room: Room) async throws
    func saveRooms(_ rooms: [Room]) async throws
    func deleteRoom(id: String) async throws
    func loadMembers(roomID: String) async throws -> [RoomMember]
    func saveMembers(_ members: [RoomMember], roomID: String) async throws
    func loadFragments(roomID: String) async throws -> [SharedFragment]
    func saveFragments(_ fragments: [SharedFragment], roomID: String) async throws
    func invalidateRoom(id: String) async throws
    func clearAll() async throws
}

/// Concrete implementation of `RoomRepository` backed by `LocalRoomCache`.
public final class LocalRoomRepository: RoomRepository {
    private let cache: LocalRoomCache

    public init(cache: LocalRoomCache = .shared) {
        self.cache = cache
    }

    public func loadRooms() async throws -> [Room] {
        try cache.loadRooms()
    }

    public func saveRoom(_ room: Room) async throws {
        try cache.saveRoom(room)
    }

    public func saveRooms(_ rooms: [Room]) async throws {
        try cache.saveRooms(rooms)
    }

    public func deleteRoom(id: String) async throws {
        try cache.deleteRoom(id: id)
    }

    public func loadMembers(roomID: String) async throws -> [RoomMember] {
        try cache.loadMembers(roomID: roomID)
    }

    public func saveMembers(_ members: [RoomMember], roomID: String) async throws {
        try cache.saveMembers(members, roomID: roomID)
    }

    public func loadFragments(roomID: String) async throws -> [SharedFragment] {
        try cache.loadFragments(roomID: roomID)
    }

    public func saveFragments(_ fragments: [SharedFragment], roomID: String) async throws {
        try cache.saveFragments(fragments, roomID: roomID)
    }

    public func invalidateRoom(id: String) async throws {
        try cache.invalidateRoom(id: id)
    }

    public func clearAll() async throws {
        try cache.clearAll()
    }
}
