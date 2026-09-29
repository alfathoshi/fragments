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
    case schemaMismatch(String)

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
        case .schemaMismatch(let reason):
            return "Backend schema mismatch: \(reason)"
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
            return try await fetchRoomMemberRows(roomUUID: roomUUID).map { $0.toDomain() }
        } catch {
            throw mapError(error)
        }
    }

    /// Member-list select that prefers `profiles.username` and falls back to
    /// the legacy column set when the backend predates the username migration.
    private func fetchRoomMemberRows(roomUUID: UUID) async throws -> [DatabaseRoomMember] {
        let modern = "id, room_id, user_id, role, joined_at, profiles(username, display_name, avatar_storage_path)"
        let legacy = "id, room_id, user_id, role, joined_at, profiles(display_name, avatar_storage_path)"
        let columns = Self.isUsernameColumnSupported ? modern : legacy
        do {
            return try await client
                .from("room_members")
                .select(columns)
                .eq("room_id", value: roomUUID)
                .order("joined_at", ascending: true)
                .execute()
                .value
        } catch {
            guard Self.isUsernameColumnSupported, Self.isMissingUsernameColumn(error) else {
                throw error
            }
            Self.isUsernameColumnSupported = false
            return try await client
                .from("room_members")
                .select(legacy)
                .eq("room_id", value: roomUUID)
                .order("joined_at", ascending: true)
                .execute()
                .value
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
    /// Prefers the unique `username` when the backend supports it.
    public func fetchUserProfile(userID: UUID) async throws -> (displayName: String, avatarStoragePath: String?) {
        _ = try await currentAuthenticatedUser()
        do {
            let columns = Self.isUsernameColumnSupported
                ? "username, display_name, avatar_storage_path"
                : "display_name, avatar_storage_path"
            let result: [DatabaseMemberProfile] = try await client
                .from("profiles")
                .select(columns)
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value

            if let first = result.first {
                let name = Self.resolvedMemberDisplayName(profileName: first.username)
                if !isUnresolvedName(name) {
                    return (name, first.avatar_storage_path)
                }
                if let fallback = first.display_name, !fallback.isEmpty {
                    return (fallback, first.avatar_storage_path)
                }
            }
            return ("Unknown", nil)
        } catch {
            if Self.isUsernameColumnSupported, Self.isMissingUsernameColumn(error) {
                Self.isUsernameColumnSupported = false
                return try await fetchUserProfile(userID: userID)
            }
            throw mapError(error)
        }
    }

    private func isUnresolvedName(_ name: String) -> Bool {
        RoomMember.isUnresolvedDisplayName(name)
    }

    // MARK: - Username (unique backend identity)

    private static let usernameFlagLock = NSLock()
    private static var _isUsernameColumnSupported: Bool = true

    /// Whether the backend `profiles` table has the `username` column.
    /// Auto-detected: the first missing-column error flips it off so legacy
    /// backends keep working on `display_name` alone.
    static var isUsernameColumnSupported: Bool {
        get { usernameFlagLock.withLock { _isUsernameColumnSupported } }
        set { usernameFlagLock.withLock { _isUsernameColumnSupported = newValue } }
    }

    /// Detects PostgREST "unknown column" failures for `username`
    /// (PGRST204 schema-cache errors), as opposed to real query failures.
    static func isMissingUsernameColumn(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        guard desc.contains("username") else { return false }
        return desc.contains("pgrst204")
            || desc.contains("could not find")
            || desc.contains("column")
            || desc.contains("schema cache")
    }

    /// Fetches the current user's own profile row (username + display name).
    /// Throws `.schemaMismatch` when the backend predates the username migration.
    public func fetchOwnProfile() async throws -> DatabaseOwnProfile {
        let user = try await currentAuthenticatedUser()
        do {
            let rows: [DatabaseOwnProfile] = try await client
                .from("profiles")
                .select("id, username, display_name")
                .eq("id", value: user.id)
                .limit(1)
                .execute()
                .value
            if let first = rows.first {
                return first
            }
            return DatabaseOwnProfile(id: user.id, username: nil, display_name: nil)
        } catch {
            if Self.isMissingUsernameColumn(error) {
                Self.isUsernameColumnSupported = false
                throw SupabaseRoomError.schemaMismatch("profiles.username is unavailable; run the username migration.")
            }
            throw mapError(error)
        }
    }

    /// UX-only availability hint. Returns true when the name appears free OR
    /// when the check itself cannot run (the authoritative decision always
    /// happens server-side at save time via the unique constraint).
    public func isUsernameAvailable(_ normalized: String) async throws -> Bool {
        _ = try await currentAuthenticatedUser()
        guard UsernameValidator.isValid(normalized) else {
            throw SupabaseRoomError.validationFailure(UsernameValidator.friendlyMessage(for: normalized))
        }
        struct AvailabilityParams: Encodable, Sendable {
            let p_username: String
        }
        do {
            let available: Bool = try await client
                .rpc("is_username_available", params: AvailabilityParams(p_username: normalized))
                .execute()
                .value
            return available
        } catch {
            // RPC missing (pre-migration backend): fall back to a direct lookup.
            // If even that fails (e.g. RLS), return true and let the save decide.
            if let rows: [DatabaseOwnProfile] = try? await client
                .from("profiles")
                .select("id")
                .eq("username", value: normalized)
                .limit(1)
                .execute()
                .value {
                return rows.isEmpty
            }
            return true
        }
    }

    /// Claims a username for the current user. Normalizes + validates locally,
    /// then upserts `{ id, username }`. A conflicting upsert surfaces HTTP 409
    /// from the unique index and is mapped to `.duplicate` — nobody is ever
    /// overwritten. Returns the normalized username. Caches it per user.
    @discardableResult
    public func claimUsername(_ raw: String) async throws -> String {
        let user = try await currentAuthenticatedUser()
        let normalized = UsernameValidator.normalize(raw)
        guard UsernameValidator.isValid(normalized) else {
            throw SupabaseRoomError.validationFailure(UsernameValidator.friendlyMessage(for: raw))
        }
        struct ClaimUsernameDTO: Encodable, Sendable {
            let id: UUID
            let username: String
        }
        do {
            try await client
                .from("profiles")
                .upsert(ClaimUsernameDTO(id: user.id, username: normalized))
                .execute()
            CachedUsernameStore.save(normalized, for: user.id.uuidString)
            return normalized
        } catch {
            if isDuplicateKeyError(error) || isConflictError(error) {
                throw SupabaseRoomError.duplicate("Username is already taken.")
            }
            if Self.isMissingUsernameColumn(error) {
                Self.isUsernameColumnSupported = false
                throw SupabaseRoomError.schemaMismatch("profiles.username is unavailable; run the username migration.")
            }
            throw mapError(error)
        }
    }

    /// Detects HTTP 409 / unique-violation failures that message sniffing misses.
    private func isConflictError(_ error: Error) -> Bool {
        let desc = error.localizedDescription
        if desc.contains("409") || desc.lowercased().contains("conflict") {
            return true
        }
        if let postgrestError = error as? PostgrestError {
            let code = postgrestError.code ?? ""
            return code == "409" || code == "23505"
        }
        return false
    }

    // MARK: - Fragment Media Lookup (receiver hydration)

    /// Fetches the media metadata row for a single fragment, if present.
    ///
    /// Used by the realtime receiver path: a `shared_fragments` INSERT arrives
    /// without the embedded `fragment_media` join, and the media row is written
    /// seconds later by the sender — so the receiver looks it up (with retry at
    /// the call site) instead of assuming absence. Returns nil on miss.
    public func fetchFragmentMedia(fragmentID: String, roomID: String) async throws -> SharedMediaReference? {
        _ = try await currentAuthenticatedUser()

        guard let fragmentUUID = UUID(uuidString: fragmentID),
              let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Fragment or Room UUID format.")
        }

        do {
            let rows: [DatabaseFragmentMedia] = try await client
                .from("fragment_media")
                .select()
                .eq("fragment_id", value: fragmentUUID)
                .eq("room_id", value: roomUUID)
                .limit(1)
                .execute()
                .value

            return rows.first?.toMediaReference()
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
    ///
    /// Valid write order (FK (fragment_id, room_id) → shared_fragments(id, room_id)):
    /// 1. Upload media bytes to Storage (no DB writes).
    /// 2. INSERT the parent `shared_fragments` row.
    /// 3. INSERT the child `fragment_media` row.
    /// A received fragment row therefore always implies its media metadata and
    /// object already exist. Rollback is preserved at every step: parent-insert
    /// failure removes the storage object; child-insert failure deletes the
    /// parent row (CASCADE removes any partial child row) and the object.
    /// Duplicate/collision outcomes mean the conflicting row is not ours and
    /// are rethrown without touching remote state.
    public func createFragmentWithMedia(_ fragment: SharedFragment) async throws -> SharedFragment {
        // TEMPORARY trace (no behavior change; no image data logged).
        print("[PhotoTrace] REPOSITORY_CREATE_FRAGMENT_WITH_MEDIA_CALLED id=\(fragment.id) type=\(fragment.type.rawValue) hasLocalURL=\(fragment.mediaReference?.localFileURL != nil)")
        // P1: photo/video/audio require a local media file. Notes legitimately
        // have none. A nil localURL previously returned silent success,
        // producing server fragment rows with no possible media.
        if fragment.type != .note, fragment.mediaReference?.localFileURL == nil {
            throw SupabaseRoomError.validationFailure(
                "Fragment of type '\(fragment.type.rawValue)' requires a local media file, but none was provided."
            )
        }

        guard let localURL = fragment.mediaReference?.localFileURL else {
            return try await createFragment(fragment)
        }

        // 1. Upload bytes first (no DB writes yet).
        let upload = try await uploadMediaObject(
            fragmentID: fragment.id,
            roomID: fragment.roomId,
            localFileURL: localURL
        )

        // 2. INSERT the parent shared_fragments row.
        let created: SharedFragment
        do {
            created = try await createFragment(fragment)
        } catch {
            if case SupabaseRoomError.duplicate = error {
                throw error
            }
            if case SupabaseRoomError.validationFailure = error {
                throw error
            }
            // Genuine parent-insert failure: no rows exist yet, so only the
            // storage object needs cleanup (best effort).
            _ = try? await client.storage
                .from(Self.mediaBucketName)
                .remove(paths: [upload.storagePath])
            throw error
        }

        // 3. INSERT the child fragment_media row (parent now exists).
        do {
            let mediaRef = try await insertFragmentMediaRow(
                fragmentID: fragment.id,
                roomID: fragment.roomId,
                localFileURL: localURL,
                storagePath: upload.storagePath,
                resolvedExt: upload.resolvedExt,
                mimeType: upload.mimeType,
                byteCount: upload.byteCount
            )
            var updated = created
            updated.mediaReference = mediaRef
            return updated
        } catch {
            if case SupabaseRoomError.duplicate = error {
                throw error
            }
            if case SupabaseRoomError.validationFailure = error {
                throw error
            }
            // Genuine child-insert failure: delete the parent row we just
            // created (ON DELETE CASCADE removes any partial child row) and
            // the storage object, then propagate.
            try? await deleteFragment(fragmentID: fragment.id, roomID: fragment.roomId)
            _ = try? await client.storage
                .from(Self.mediaBucketName)
                .remove(paths: [upload.storagePath])
            throw error
        }
    }

    // MARK: - Media Upload

    /// Uploads raw media bytes to the private bucket and returns the resolved
    /// storage coordinates. Performs NO database writes, so it is safe to run
    /// before any table INSERT (in particular before the parent
    /// `shared_fragments` row that `fragment_media` references via
    /// FK (fragment_id, room_id)).
    private func uploadMediaObject(
        fragmentID: String,
        roomID: String,
        localFileURL: URL
    ) async throws -> (storagePath: String, resolvedExt: String, mimeType: String, byteCount: Int) {
        _ = try await currentAuthenticatedUser()

        guard UUID(uuidString: fragmentID) != nil, UUID(uuidString: roomID) != nil else {
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

        return (deterministicPath, resolvedExt, mimeType, fileData.count)
    }

    /// Inserts the `fragment_media` child row. The parent `shared_fragments`
    /// row MUST already exist (FK (fragment_id, room_id)). Duplicate inserts
    /// for the same deterministic path resolve idempotently to the existing
    /// row. Throws without side effects on failure — the caller owns rollback.
    private func insertFragmentMediaRow(
        fragmentID: String,
        roomID: String,
        localFileURL: URL,
        storagePath: String,
        resolvedExt: String,
        mimeType: String,
        byteCount: Int
    ) async throws -> SharedMediaReference {
        _ = try await currentAuthenticatedUser()

        guard let fragmentUUID = UUID(uuidString: fragmentID),
              let roomUUID = UUID(uuidString: roomID) else {
            throw SupabaseRoomError.validationFailure("Invalid Fragment or Room UUID format.")
        }

        let mediaDTO = InsertFragmentMediaDTO(
            id: UUID(),
            fragment_id: fragmentUUID,
            room_id: roomUUID,
            storage_path: storagePath,
            file_extension: resolvedExt,
            file_size: Int64(byteCount),
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

                if let first = existing.first, first.room_id == roomUUID, first.storage_path == storagePath {
                    return first.toMediaReference(localURL: localFileURL)
                }
            }
            throw error
        }

        return SharedMediaReference(
            assetKey: storagePath,
            storagePath: storagePath,
            localFileURL: localFileURL,
            remoteURL: nil,
            fileExtension: resolvedExt,
            fileSize: Int64(byteCount),
            mimeType: mimeType
        )
    }

    public func createFragmentMedia(
        fragmentID: String,
        roomID: String,
        localFileURL: URL
    ) async throws -> SharedMediaReference {
        let upload = try await uploadMediaObject(
            fragmentID: fragmentID,
            roomID: roomID,
            localFileURL: localFileURL
        )
        do {
            return try await insertFragmentMediaRow(
                fragmentID: fragmentID,
                roomID: roomID,
                localFileURL: localFileURL,
                storagePath: upload.storagePath,
                resolvedExt: upload.resolvedExt,
                mimeType: upload.mimeType,
                byteCount: upload.byteCount
            )
        } catch {
            // Cleanup uploaded storage binary to avoid leaving orphaned files
            _ = try? await client.storage
                .from(Self.mediaBucketName)
                .remove(paths: [upload.storagePath])
            throw error
        }
    }

    public func createSignedMediaURL(storagePath: String, expiresIn: Int = 3600) async throws -> URL {
        _ = try await currentAuthenticatedUser()

        do {
            // TEMPORARY diagnostic: confirm creation without printing the URL
            // itself (it embeds a credential/token).
            let signedURL = try await client.storage
                .from(Self.mediaBucketName)
                .createSignedURL(path: storagePath, expiresIn: expiresIn)
            print("[MediaDebug] Signed URL CREATED")
            return signedURL
        } catch {
            print("[MediaDebug] SIGNED URL FAILED")
            print("[MediaDebug] error: \(error)")
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
    let username: String?
    let display_name: String?
    let avatar_storage_path: String?
}

/// Own-profile row: stable unique `username` plus legacy free-text `display_name`.
/// USERNAME (unique, backend-persisted) is the collaborative identity;
/// DISPLAY NAME (free text) remains optional profile metadata and coexists.
public struct DatabaseOwnProfile: Decodable, Sendable {
    public let id: UUID
    public let username: String?
    public let display_name: String?
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
            displayName: SupabaseRoomRepository.resolvedMemberDisplayName(
                profileName: profiles?.username,
                fallbackLocalName: profiles?.display_name
            ),
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
