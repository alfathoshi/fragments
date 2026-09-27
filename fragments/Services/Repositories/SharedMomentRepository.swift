//
//  SharedMomentRepository.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation

/// Repository protocol defining remote operations for collaborative Shared Moments.
///
/// Implementations abstract remote synchronization (e.g. Supabase, CloudKit)
/// from RoomManager and presentation workflows.
public protocol SharedMomentRepository: Sendable {
    /// Creates a new collaborative Room with the authenticated user as owner.
    func createRoom(
        id: String?,
        name: String,
        emoji: String,
        accentColorHex: String?
    ) async throws -> Room

    /// Joins an existing collaborative Room using its join code.
    func joinRoom(code: String) async throws -> Room

    /// Fetches details for a single Room by identifier.
    func fetchRoom(id: String) async throws -> Room?

    /// Fetches all active Rooms the current authenticated user is a member of.
    func fetchRooms() async throws -> [Room]

    /// Fetches members participating in the specified Room.
    func fetchMembers(roomID: String) async throws -> [RoomMember]

    /// Fetches all collaborative fragments captured in the specified Room.
    func fetchFragments(roomID: String) async throws -> [SharedFragment]

    /// Creates and persists a shared fragment metadata record.
    func createFragment(_ fragment: SharedFragment) async throws -> SharedFragment

    /// Creates and persists a shared fragment and uploads its attached media if present.
    func createFragmentWithMedia(_ fragment: SharedFragment) async throws -> SharedFragment

    /// Uploads media for a fragment and persists its `fragment_media` record.
    func createFragmentMedia(
        fragmentID: String,
        roomID: String,
        localFileURL: URL
    ) async throws -> SharedMediaReference

    /// Generates a temporary signed URL for downloading private media from Storage.
    func createSignedMediaURL(storagePath: String, expiresIn: Int) async throws -> URL

    /// Updates mutable metadata for a collaborative Room.
    func updateRoom(_ room: Room) async throws

    /// Archives a collaborative Room.
    func archiveRoom(roomID: String) async throws

    /// Deletes a fragment and its associated media storage.
    func deleteFragment(fragmentID: String, roomID: String) async throws

    /// Leaves a collaborative Room by removing the current user's membership.
    func leaveRoom(roomID: String) async throws

    /// Permanently deletes a Room and all associated records (owner only).
    func deleteRoom(roomID: String) async throws
}

