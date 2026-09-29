//
//  SupabaseRoomRepository.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import Supabase
import Storage

/// Error types specific to Supabase-backed collaborative Rooms.
public enum SupabaseRoomError: LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case networkFailure(String)
    case unauthorized(String)
    case notFound(String)
    case validationFailure(String)
    case duplicate(String)
    case storageFailure(String)
    case databaseFailure(String)
    case partialSyncFailure(fragmentID: String, storagePath: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Authentication required. Please sign in with Apple to access collaborative Rooms."
        case .networkFailure(let reason):
            return "Network connection issue: \(reason)"
        case .unauthorized(let reason):
            return "Unauthorized action: \(reason)"
        case .notFound(let item):
            return "\(item) could not be found."
        case .validationFailure(let reason):
            return "Validation failed: \(reason)"
        case .duplicate(let item):
            return "\(item) already exists."
        case .storageFailure(let reason):
            return "Media storage error: \(reason)"
        case .databaseFailure(let reason):
            return "Database operation error: \(reason)"
        case .partialSyncFailure(let fragmentID, _, let reason):
            return "Partial sync failure for fragment \(fragmentID): \(reason)"
        }
    }
}

/// Supabase implementation of `SharedMomentRepository`.
///
/// Encapsulates all PostgREST RPC, table CRUD, and private Storage operations
/// for collaborative Shared Moments. Exclusively uses the active Supabase Auth
/// user identity and respects PostgreSQL Row-Level Security (RLS).
public final class SupabaseRoomRepository: SharedMomentRepository, Sendable {
    public static let shared = SupabaseRoomRepository()

    public static let mediaBucketName = "moment-media"

    private let supabaseService: SupabaseService

    public init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    private var client: SupabaseClient {
        supabaseService.client
    }

    // MARK: - Authentication Guard

    /// Resolves the canonical authenticated Supabase user.
    ///
    /// Throws `SupabaseRoomError.notAuthenticated` if no valid session exists.
    private func currentAuthenticatedUser() async throws -> User {
        guard let user = await supabaseService.getCurrentUser() else {
            throw SupabaseRoomError.notAuthenticated
        }
        return user
    }

    // MARK: - Room Creation

    public func createRoom(
        id: String? = nil,
        name: String,
        emoji: String = "✨",
        accentColorHex: String? = nil
    ) async throws -> Room {
        let user = try await currentAuthenticatedUser()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SupabaseRoomError.validationFailure("Room name cannot be empty.")
        }

        let roomUUID = id.flatMap { UUID(uuidString: $0) } ?? UUID()
        let createdAtISO = ISO8601DateFormatter().string(from: Date())

        struct CreateRoomRPCParams: Encodable, Sendable {
            let p_id: UUID
            let p_name: String
            let p_emoji: String
            let p_accent_color_hex: String?
            let p_created_at: String
        }

        let params = CreateRoomRPCParams(
            p_id: roomUUID,
            p_name: trimmedName,
            p_emoji: emoji.isEmpty ? "✨" : emoji,
            p_accent_color_hex: accentColorHex,
            p_created_at: createdAtISO
        )

        do {
            let dbRoom: DatabaseRoom = try await client
                .rpc("create_room_with_owner", params: params)
                .execute()
                .value

            return dbRoom.toDomain(memberCount: 1, fragmentCount: 0)
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Join Room

    public func joinRoom(code: String) async throws -> Room {
        _ = try await currentAuthenticatedUser()

        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.count == 6 else {
            throw SupabaseRoomError.validationFailure("Join code must be 6 characters.")
        }

        struct JoinRoomRPCParams: Encodable, Sendable {
            let p_code: String
        }

        do {
            let dbRoom: DatabaseRoom = try await client
                .rpc("join_room_by_code", params: JoinRoomRPCParams(p_code: normalizedCode))
                .execute()
                .value

            if dbRoom.is_archived {
                throw SupabaseRoomError.validationFailure("This Room has been archived.")
            }
            if dbRoom.is_ended {
                throw SupabaseRoomError.validationFailure("This Room has already ended.")
            }

            return dbRoom.toDomain()
        } catch {
            if let roomError = error as? SupabaseRoomError {
                throw roomError
            }
            throw Self.mapJoinRPCError(error, code: normalizedCode)
        }
    }

    static func mapJoinRPCError(_ error: Error, code: String) -> SupabaseRoomError {
        let desc = (error as? PostgrestError)?.message ?? error.localizedDescription
        let lower = desc.lowercased()
        if lower.contains("room not found") {
            return .notFound("No Room found matching code '\(code)'.")
        }
        if lower.contains("archived") {
            return .validationFailure("This Room has been archived.")
        }
        if lower.contains("ended") {
            return .validationFailure("This Room has already ended.")
        }
        if lower.contains("jwt") || lower.contains("authentication required") || lower.contains("unauthenticated") {
            return .notAuthenticated
        }
        if lower.contains("permission denied") || lower.contains("violates row-level security") || lower.contains("403") {
            return .unauthorized(desc)
        }
        return .databaseFailure(desc)
    }

    // MARK: - Room Reads

    public func fetchRoom(id: String) async throws -> Room? {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: id) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        do {
            let rooms: [DatabaseRoom] = try await client
                .from("rooms")
                .select()
                .eq("id", value: roomUUID)
                .execute()
                .value

            guard let first = rooms.first else {
                return nil
            }
            return first.toDomain()
        } catch {
            throw mapError(error)
        }
    }

    public func fetchRooms() async throws -> [Room] {
        _ = try await currentAuthenticatedUser()

        do {
            let rooms: [DatabaseRoom] = try await client
                .from("rooms")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            return rooms.map { $0.toDomain() }
        } catch {
            throw mapError(error)
        }
    }

    public func fetchMembers(roomID: String) async throws -> [RoomMember] {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        do {
            let members: [DatabaseRoomMember] = try await client
                .from("room_members")
                .select("id, room_id, user_id, role, joined_at, profiles(display_name, avatar_storage_path)")
                .eq("room_id", value: roomUUID)
                .order("joined_at", ascending: true)
                .execute()
                .value

            return members.map { $0.toDomain() }
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - User Profile Reads

    /// Upserts the current authenticated user's profile row so Supabase
    /// `profiles.display_name` reflects the local signature (ProfileManager).
    ///
    /// Root-cause fix for member lists rendering the schema default
    /// ("Fragment Explorer") / "Member": nothing previously wrote the local
    /// identity to Supabase, so reads faithfully propagated the placeholder.
    /// Callers should pass `ProfileManager.shared.effectiveName`; unresolved
    /// or empty names are ignored so we never overwrite a real name with a placeholder.
    @discardableResult
    public func upsertCurrentUserProfile(displayName: String, avatarStoragePath: String? = nil) async throws -> Bool {
        let user = try await currentAuthenticatedUser()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !RoomMember.isUnresolvedDisplayName(trimmed) else {
            return false
        }
        struct UpsertProfileDTO: Encodable, Sendable {
            let id: UUID
            let display_name: String
            let avatar_storage_path: String?
        }
        do {
            try await client
                .from("profiles")
                .upsert(UpsertProfileDTO(id: user.id, display_name: trimmed, avatar_storage_path: avatarStoragePath))
                .execute()
            return true
        } catch {
            throw mapError(error)
        }
    }

    /// Central display-name resolution: prefers a real profile name, falls back
    /// to a local identity name. Users who have not set a username resolve to
    /// "Unknown" (never a schema default) so downstream repair paths can
    /// replace it once a real name exists.
    public static func resolvedMemberDisplayName(profileName: String?, fallbackLocalName: String? = nil) -> String {
        if let raw = profileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty, !RoomMember.isUnresolvedDisplayName(raw) {
            return raw
        }
        if let fallback = fallbackLocalName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty, !RoomMember.isUnresolvedDisplayName(fallback) {
            return fallback
        }
        return "Unknown"
    }

    /// Fetches the profile display name and avatar path for a specific user ID.
    public func fetchUserProfile(userID: UUID) async throws -> (displayName: String, avatarStoragePath: String?) {
        _ = try await currentAuthenticatedUser()
        do {
            let result: [DatabaseMemberProfile] = try await client
                .from("profiles")
                .select("display_name, avatar_storage_path")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value

            if let first = result.first, let name = first.display_name, !name.isEmpty {
                return (name, first.avatar_storage_path)
            }
            return ("Unknown", nil)
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Fragment Reads

    public func fetchFragments(roomID: String) async throws -> [SharedFragment] {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        do {
            let fragments: [DatabaseSharedFragment] = try await client
                .from("shared_fragments")
                .select("*, fragment_media(*)")
                .eq("room_id", value: roomUUID)
                .order("created_at", ascending: true)
                .execute()
                .value

            return fragments.map { $0.toDomain() }
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Fragment Creation

    /// Evaluates whether an existing fragment row represents an idempotent duplicate, or a room/author conflict.
    static func evaluateFragmentIdempotency(
        existingRoomID: UUID,
        existingAuthorID: UUID?,
        targetRoomID: UUID,
        targetAuthorID: UUID
    ) throws {
        guard existingRoomID == targetRoomID else {
            throw SupabaseRoomError.validationFailure("Fragment ID collision with a different room.")
        }
        guard existingAuthorID == targetAuthorID else {
            throw SupabaseRoomError.duplicate("Fragment ID collision with another user.")
        }
    }

    public func createFragment(_ fragment: SharedFragment) async throws -> SharedFragment {
        let user = try await currentAuthenticatedUser()

        guard let fragmentUUID = UUID(uuidString: fragment.id),
              let roomUUID = UUID(uuidString: fragment.roomId) else {
            throw SupabaseRoomError.validationFailure("Invalid Fragment or Room UUID format.")
        }

        // Canonical Collaborative Identity Validation:
        // Ensure fragment.authorId is a valid UUID and strictly matches the authenticated user's ID
        guard let fragmentAuthorUUID = UUID(uuidString: fragment.authorId) else {
            throw SupabaseRoomError.validationFailure("Fragment author ID '\(fragment.authorId)' is not a valid UUID format.")
        }

        guard fragmentAuthorUUID == user.id else {
            throw SupabaseRoomError.validationFailure("Author identity mismatch: Fragment author '\(fragment.authorId)' does not match authenticated user '\(user.id.uuidString)'.")
        }

        let dto = InsertSharedFragmentDTO(
            id: fragmentUUID,
            room_id: roomUUID,
            author_id: user.id,
            author_name: fragment.authorName.isEmpty ? "Author" : fragment.authorName,
            type: fragment.type.rawValue,
            title: fragment.title,
            subtitle: fragment.subtitle,
            text: fragment.text,
            media_symbol: fragment.mediaSymbol,
            location: fragment.location,
            duration: fragment.duration,
            audio_waveform: fragment.audioWaveform.map { Double($0) },
            accent_color_hex: fragment.accentColorHex,
            phi: fragment.phi,
            theta: fragment.theta,
            radius_factor: fragment.radiusFactor,
            created_at: ISO8601DateFormatter().string(from: fragment.createdAt)
        )

        do {
            try await client
                .from("shared_fragments")
                .insert(dto)
                .execute()

            return fragment
        } catch {
            if isDuplicateKeyError(error) {
                // Idempotency check: verify whether this row was authored by the same user in the same room
                let existing: [DatabaseSharedFragment] = try await client
                    .from("shared_fragments")
                    .select("id, room_id, author_id")
                    .eq("id", value: fragmentUUID)
                    .execute()
                    .value

                guard let first = existing.first else {
                    throw mapError(error)
                }

                try Self.evaluateFragmentIdempotency(
                    existingRoomID: first.room_id,
                    existingAuthorID: first.author_id,
                    targetRoomID: roomUUID,
                    targetAuthorID: user.id
                )

                return fragment
            }
            throw mapError(error)
        }
    }

    /// High-level orchestration for creating a fragment and attaching its media if present.
    public func createFragmentWithMedia(_ fragment: SharedFragment) async throws -> SharedFragment {
        let created = try await createFragment(fragment)
        if let localURL = fragment.mediaReference?.localFileURL {
            do {
                let mediaRef = try await createFragmentMedia(
                    fragmentID: fragment.id,
                    roomID: fragment.roomId,
                    localFileURL: localURL
                )
                var updated = created
                updated.mediaReference = mediaRef
                return updated
            } catch {
                // Media upload or metadata attachment failed. Rollback the created shared_fragments row
                // to prevent leaving an orphaned fragment record with broken media references.
                try? await deleteFragment(fragmentID: fragment.id, roomID: fragment.roomId)
                throw error
            }
        }
        return created
    }

    // MARK: - Media Upload

    public func createFragmentMedia(
        fragmentID: String,
        roomID: String,
        localFileURL: URL
    ) async throws -> SharedMediaReference {
        _ = try await currentAuthenticatedUser()

        guard let fragmentUUID = UUID(uuidString: fragmentID),
              let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Fragment or Room UUID format.")
        }

        guard FileManager.default.fileExists(atPath: localFileURL.path) else {
            throw SupabaseRoomError.validationFailure("Local media file does not exist at path: \(localFileURL.path)")
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: localFileURL)
        } catch {
            throw SupabaseRoomError.storageFailure("Could not read local media file: \(error.localizedDescription)")
        }

        let ext = localFileURL.pathExtension.lowercased()
        let resolvedExt = ext.isEmpty ? "bin" : ext
        let mimeType = mimeTypeForExtension(resolvedExt)
        let deterministicPath = "rooms/\(roomID)/fragments/\(fragmentID).\(resolvedExt)"

        // 1. Upload media binary to private bucket using deterministic path
        do {
            _ = try await client.storage
                .from(Self.mediaBucketName)
                .upload(
                    deterministicPath,
                    data: fileData,
                    options: FileOptions(contentType: mimeType, upsert: true)
                )
        } catch {
            throw SupabaseRoomError.storageFailure("Storage upload failed: \(error.localizedDescription)")
        }

        // 2. Persist media metadata in PostgreSQL fragment_media table
        let mediaDTO = InsertFragmentMediaDTO(
            id: UUID(),
            fragment_id: fragmentUUID,
            room_id: roomUUID,
            storage_path: deterministicPath,
            file_extension: resolvedExt,
            file_size: Int64(fileData.count),
            mime_type: mimeType,
            created_at: ISO8601DateFormatter().string(from: Date())
        )

        do {
            try await client
                .from("fragment_media")
                .insert(mediaDTO)
                .execute()
        } catch {
            if isDuplicateKeyError(error) {
                // Idempotency check: verify matching metadata exists
                let existing: [DatabaseFragmentMedia] = try await client
                    .from("fragment_media")
                    .select()
                    .eq("fragment_id", value: fragmentUUID)
                    .execute()
                    .value

                if let first = existing.first, first.room_id == roomUUID, first.storage_path == deterministicPath {
                    return first.toMediaReference(localURL: localFileURL)
                }
            }

            // Cleanup uploaded storage binary to avoid leaving orphaned files
            _ = try? await client.storage
                .from(Self.mediaBucketName)
                .remove(paths: [deterministicPath])

            // Media exists in storage but DB metadata failed -> partial sync error for deterministic retry
            throw SupabaseRoomError.partialSyncFailure(
                fragmentID: fragmentID,
                storagePath: deterministicPath,
                reason: error.localizedDescription
            )
        }

        return SharedMediaReference(
            assetKey: deterministicPath,
            storagePath: deterministicPath,
            localFileURL: localFileURL,
            remoteURL: nil,
            fileExtension: resolvedExt,
            fileSize: Int64(fileData.count),
            mimeType: mimeType
        )
    }

    public func createSignedMediaURL(storagePath: String, expiresIn: Int = 3600) async throws -> URL {
        _ = try await currentAuthenticatedUser()

        do {
            return try await client.storage
                .from(Self.mediaBucketName)
                .createSignedURL(path: storagePath, expiresIn: expiresIn)
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Delete Fragment

    /// Deletes a fragment and its remote media storage.
    ///
    /// Sequencing Rationale:
    /// We delete the database record first. PostgreSQL's `ON DELETE CASCADE` removes `fragment_media`
    /// atomically and hides the item from all room participants immediately, eliminating 404 race conditions.
    /// Storage binary removal is performed secondly.
    public func deleteFragment(fragmentID: String, roomID: String) async throws {
        _ = try await currentAuthenticatedUser()

        guard let fragmentUUID = UUID(uuidString: fragmentID),
              let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Fragment or Room UUID format.")
        }

        // Query storage path before deletion if media exists
        var targetStoragePath: String? = nil
        if let mediaRecords: [DatabaseFragmentMedia] = try? await client
            .from("fragment_media")
            .select("storage_path")
            .eq("fragment_id", value: fragmentUUID)
            .execute()
            .value {
            targetStoragePath = mediaRecords.first?.storage_path
        }

        // 1. Delete database record (cascades to fragment_media)
        do {
            try await client
                .from("shared_fragments")
                .delete()
                .eq("id", value: fragmentUUID)
                .eq("room_id", value: roomUUID)
                .execute()
        } catch {
            throw mapError(error)
        }

        // 2. Cleanup Storage object if present
        if let storagePath = targetStoragePath {
            _ = try? await client.storage
                .from(Self.mediaBucketName)
                .remove(paths: [storagePath])
        }
    }

    // MARK: - Leave & Delete Room

    public func leaveRoom(roomID: String) async throws {
        let user = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        do {
            try await client
                .from("room_members")
                .delete()
                .eq("room_id", value: roomUUID)
                .eq("user_id", value: user.id)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    public func updateRoom(_ room: Room) async throws {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: room.id) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        struct UpdateRoomDTO: Encodable, Sendable {
            let name: String
            let emoji: String
            let accent_color_hex: String?
            let is_ended: Bool
            let is_archived: Bool
            let final_title: String?
            let final_category: String?
        }

        let dto = UpdateRoomDTO(
            name: room.name,
            emoji: room.emoji,
            accent_color_hex: room.accentColorHex,
            is_ended: room.isEnded,
            is_archived: room.isArchived,
            final_title: room.finalTitle,
            final_category: room.finalCategory
        )

        do {
            try await client
                .from("rooms")
                .update(dto)
                .eq("id", value: roomUUID)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    public func archiveRoom(roomID: String) async throws {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        struct ArchiveRoomDTO: Encodable, Sendable {
            let is_archived: Bool
        }

        do {
            try await client
                .from("rooms")
                .update(ArchiveRoomDTO(is_archived: true))
                .eq("id", value: roomUUID)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    public func deleteRoom(roomID: String) async throws {
        _ = try await currentAuthenticatedUser()

        guard let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Room UUID format.")
        }

        do {
            try await client
                .from("rooms")
                .delete()
                .eq("id", value: roomUUID)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Internal Helpers & Error Mapping

    private func isDuplicateKeyError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("duplicate") || msg.contains("unique constraint") || msg.contains("23505")
    }

    private func mapError(_ error: Error) -> SupabaseRoomError {
        if let roomError = error as? SupabaseRoomError {
            return roomError
        }

        let desc = error.localizedDescription
        let lower = desc.lowercased()

        if lower.contains("offline") || lower.contains("network") || lower.contains("connection") || (error as? URLError) != nil {
            return .networkFailure(desc)
        }
        if lower.contains("jwt") || lower.contains("authentication required") || lower.contains("unauthenticated") {
            return .notAuthenticated
        }
        if lower.contains("permission denied") || lower.contains("violates row-level security") || lower.contains("403") {
            return .unauthorized(desc)
        }
        if lower.contains("not found") || lower.contains("404") {
            return .notFound(desc)
        }
        if isDuplicateKeyError(error) {
            return .duplicate(desc)
        }

        return .databaseFailure(desc)
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "m4a": return "audio/m4a"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }

    static func parseISO8601(_ string: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string) ?? Date()
    }
}

// MARK: - Database DTOs

struct DatabaseRoom: Decodable, Sendable {
    let id: UUID
    let name: String
    let emoji: String
    let accent_color_hex: String?
    let created_by: UUID
    let created_at: String
    let is_ended: Bool
    let is_archived: Bool
    let final_title: String?
    let final_category: String?
    let join_code: String

    func toDomain(memberCount: Int = 1, fragmentCount: Int = 0) -> Room {
        Room(
            id: id.uuidString,
            name: name,
            emoji: emoji,
            createdAt: SupabaseRoomRepository.parseISO8601(created_at),
            createdBy: created_by.uuidString,
            shareRecordID: join_code,
            zoneName: "supabase",
            isEnded: is_ended,
            isArchived: is_archived,
            memberCount: memberCount,
            fragmentCount: fragmentCount,
            accentColorHex: accent_color_hex,
            finalTitle: final_title,
            finalCategory: final_category
        )
    }
}

struct DatabaseMemberProfile: Decodable, Sendable {
    let display_name: String?
    let avatar_storage_path: String?
}

struct DatabaseRoomMember: Decodable, Sendable {
    let id: UUID
    let room_id: UUID
    let user_id: UUID
    let role: String
    let joined_at: String
    let profiles: DatabaseMemberProfile?

    func toDomain() -> RoomMember {
        let memberRole: RoomRole = {
            switch role.lowercased() {
            case "owner": return .owner
            case "viewer": return .viewer
            default: return .member
            }
        }()

        let avatarURL: URL? = {
            if let str = profiles?.avatar_storage_path, let url = URL(string: str) {
                return url
            }
            return nil
        }()

        return RoomMember(
            id: id.uuidString,
            roomId: room_id.uuidString,
            userId: user_id.uuidString,
            displayName: SupabaseRoomRepository.resolvedMemberDisplayName(profileName: profiles?.display_name),
            role: memberRole,
            joinedAt: SupabaseRoomRepository.parseISO8601(joined_at),
            avatarAssetURL: avatarURL
        )
    }
}

struct DatabaseFragmentMedia: Decodable, Sendable {
    let id: UUID?
    let fragment_id: UUID?
    let room_id: UUID?
    let storage_path: String
    let file_extension: String
    let file_size: Int64?
    let mime_type: String?

    func toMediaReference(localURL: URL? = nil) -> SharedMediaReference {
        SharedMediaReference(
            assetKey: storage_path,
            storagePath: storage_path,
            localFileURL: localURL,
            remoteURL: nil,
            fileExtension: file_extension,
            fileSize: file_size,
            mimeType: mime_type
        )
    }
}

struct DatabaseSharedFragment: Decodable, Sendable {
    let id: UUID
    let room_id: UUID
    let author_id: UUID?
    let author_name: String?
    let type: String?
    let title: String?
    let subtitle: String?
    let text: String?
    let media_symbol: String?
    let location: String?
    let duration: String?
    let audio_waveform: [Double]?
    let accent_color_hex: String?
    let phi: Double?
    let theta: Double?
    let radius_factor: Double?
    let created_at: String?
    let fragment_media: [DatabaseFragmentMedia]?

    func toDomain() -> SharedFragment {
        let fragType: FragmentType = {
            switch type?.lowercased() {
            case "photo": return .photo
            case "video": return .video
            case "audio": return .audio
            case "note": return .note
            default: return .photo
            }
        }()

        let mediaRef = fragment_media?.first?.toMediaReference()

        return SharedFragment(
            id: id.uuidString,
            roomId: room_id.uuidString,
            authorId: author_id?.uuidString ?? "",
            authorName: author_name ?? "Author",
            type: fragType,
            createdAt: created_at.map { SupabaseRoomRepository.parseISO8601($0) } ?? Date(),
            title: title ?? "Untitled",
            subtitle: subtitle,
            text: text,
            mediaReference: mediaRef,
            mediaSymbol: media_symbol,
            location: location,
            duration: duration,
            audioWaveform: (audio_waveform ?? []).map { CGFloat($0) },
            accentColorHex: accent_color_hex,
            phi: phi ?? 0.08,
            theta: theta ?? 0.35,
            radiusFactor: radius_factor ?? 1.0
        )
    }
}

private struct InsertSharedFragmentDTO: Encodable, Sendable {
    let id: UUID
    let room_id: UUID
    let author_id: UUID
    let author_name: String
    let type: String
    let title: String
    let subtitle: String?
    let text: String?
    let media_symbol: String?
    let location: String?
    let duration: String?
    let audio_waveform: [Double]
    let accent_color_hex: String?
    let phi: Double
    let theta: Double
    let radius_factor: Double
    let created_at: String
}

private struct InsertFragmentMediaDTO: Encodable, Sendable {
    let id: UUID
    let fragment_id: UUID
    let room_id: UUID
    let storage_path: String
    let file_extension: String
    let file_size: Int64?
    let mime_type: String?
    let created_at: String
}
