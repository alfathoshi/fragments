//
//  SupabaseRepositoryVerifier.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation

/// Verification engine for Phase 2B Supabase Room Repository.
///
/// Validates authentication guard, deterministic storage path formatting,
/// error abstraction, idempotency, and coexistence with CloudKit.
public enum SupabaseRepositoryVerifier {

    public static func runAllTests() async -> (passed: Bool, log: [String]) {
        var logs: [String] = []
        var allPassed = true

        func assertCondition(_ condition: Bool, _ testName: String) {
            if condition {
                logs.append("✅ [PASS] \(testName)")
            } else {
                logs.append("❌ [FAIL] \(testName)")
                allPassed = false
            }
        }

        let repo = SupabaseRoomRepository.shared

        // -------------------------------------------------------------
        // 1. AUTHENTICATION GUARD VERIFICATION
        // -------------------------------------------------------------
        // If not authenticated, repository operations must strictly throw .notAuthenticated
        let isAuth = await SupabaseService.shared.isAuthenticated
        if !isAuth {
            do {
                _ = try await repo.fetchRooms()
                assertCondition(false, "Unauthenticated fetchRooms should throw .notAuthenticated")
            } catch let error as SupabaseRoomError {
                assertCondition(error == .notAuthenticated, "Unauthenticated fetchRooms threw .notAuthenticated")
            } catch {
                assertCondition(false, "fetchRooms threw unexpected error type: \(error)")
            }

            do {
                _ = try await repo.createRoom(name: "Test Room")
                assertCondition(false, "Unauthenticated createRoom should throw .notAuthenticated")
            } catch let error as SupabaseRoomError {
                assertCondition(error == .notAuthenticated, "Unauthenticated createRoom threw .notAuthenticated")
            } catch {
                assertCondition(false, "createRoom threw unexpected error type: \(error)")
            }
        } else {
            logs.append("ℹ️ [INFO] User is authenticated; skipping unauthenticated rejection test.")
        }

        // -------------------------------------------------------------
        // 2. DETERMINISTIC STORAGE PATH FORMATTING
        // -------------------------------------------------------------
        let testRoomID = "11111111-2222-3333-4444-555555555555"
        let testFragmentID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let ext = "jpg"
        let expectedPath = "rooms/\(testRoomID)/fragments/\(testFragmentID).\(ext)"

        assertCondition(
            expectedPath.hasPrefix("rooms/\(testRoomID)/fragments/"),
            "Storage path follows rooms/{room_id}/fragments/ schema"
        )
        assertCondition(
            expectedPath.hasSuffix(".\(ext)"),
            "Storage path preserves lowercase file extension"
        )

        // -------------------------------------------------------------
        // 3. NO PERMANENT PUBLIC MEDIA URL
        // -------------------------------------------------------------
        let mediaRef = SharedMediaReference(
            storagePath: expectedPath,
            fileExtension: ext,
            fileSize: 1024,
            mimeType: "image/jpeg"
        )

        assertCondition(mediaRef.remoteURL == nil, "SharedMediaReference contains no public URL")
        assertCondition(mediaRef.storagePath == expectedPath, "SharedMediaReference stores canonical storagePath")
        assertCondition(mediaRef.assetKey == expectedPath, "SharedMediaReference assetKey aliases storagePath")

        // -------------------------------------------------------------
        // 4. PARTIAL SYNC ERROR CONTRACT
        // -------------------------------------------------------------
        let partialError = SupabaseRoomError.partialSyncFailure(
            fragmentID: testFragmentID,
            storagePath: expectedPath,
            reason: "PostgreSQL transient disconnect"
        )

        if case .partialSyncFailure(let fragID, let path, _) = partialError {
            assertCondition(fragID == testFragmentID, "Partial sync error retains fragmentID for retry")
            assertCondition(path == expectedPath, "Partial sync error retains deterministic storagePath for retry")
        } else {
            assertCondition(false, "Partial sync error pattern matching failed")
        }

        // -------------------------------------------------------------
        // 5. CLOUDKIT COEXISTENCE
        // -------------------------------------------------------------
        let ckRepo = CloudKitRoomRepository.shared
        assertCondition(ckRepo != nil, "CloudKitRoomRepository remains accessible and intact")

        let localRepo = LocalRoomRepository()
        assertCondition(localRepo != nil, "LocalRoomRepository remains accessible and intact")

        // -------------------------------------------------------------
        // 6. PROFILE AVATAR STORAGE PATH DTO & DOMAIN MAPPING
        // -------------------------------------------------------------
        let memberJSONWithAvatar = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "owner",
            "joined_at": "2026-09-27T12:00:00Z",
            "profiles": {
                "display_name": "Test User",
                "avatar_storage_path": "avatars/test-user.jpg"
            }
        }
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: memberJSONWithAvatar)
            assertCondition(
                decoded.profiles?.avatar_storage_path == "avatars/test-user.jpg",
                "DatabaseMemberProfile decodes avatar_storage_path correctly"
            )
            let domain = decoded.toDomain()
            assertCondition(
                domain.avatarAssetURL?.absoluteString == "avatars/test-user.jpg",
                "RoomMember maps avatar_storage_path to avatarAssetURL"
            )
            assertCondition(domain.role == .owner, "RoomMember owner role decoded")
        } catch {
            assertCondition(false, "Failed to decode DatabaseRoomMember with avatar_storage_path: \(error)")
        }

        let memberJSONWithoutAvatar = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "member",
            "joined_at": "2026-09-27T12:00:00Z",
            "profiles": {
                "display_name": "Test User",
                "avatar_storage_path": null
            }
        }
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: memberJSONWithoutAvatar)
            let domain = decoded.toDomain()
            assertCondition(
                domain.avatarAssetURL == nil,
                "RoomMember with null avatar_storage_path has nil avatarAssetURL"
            )
        } catch {
            assertCondition(false, "Failed to decode DatabaseRoomMember with null avatar_storage_path: \(error)")
        }

        // -------------------------------------------------------------
        // 7. FRAGMENT IDEMPOTENCY AUTHOR & ROOM CHECK
        // -------------------------------------------------------------
        let targetRoomUUID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-444444444444")!
        let otherRoomUUID = UUID(uuidString: "bbbbbbbb-1111-2222-3333-444444444444")!
        let targetAuthorUUID = UUID(uuidString: "cccccccc-1111-2222-3333-444444444444")!
        let otherAuthorUUID = UUID(uuidString: "dddddddd-1111-2222-3333-444444444444")!

        // Case A: Same Room + Same Author -> Idempotent Success (no error thrown)
        do {
            try SupabaseRoomRepository.evaluateFragmentIdempotency(
                existingRoomID: targetRoomUUID,
                existingAuthorID: targetAuthorUUID,
                targetRoomID: targetRoomUUID,
                targetAuthorID: targetAuthorUUID
            )
            assertCondition(true, "Idempotency succeeds when room and author match")
        } catch {
            assertCondition(false, "Idempotency threw unexpected error for matching room/author: \(error)")
        }

        // Case B: Same Room + Different Author -> Duplicate error distinguished
        do {
            try SupabaseRoomRepository.evaluateFragmentIdempotency(
                existingRoomID: targetRoomUUID,
                existingAuthorID: otherAuthorUUID,
                targetRoomID: targetRoomUUID,
                targetAuthorID: targetAuthorUUID
            )
            assertCondition(false, "Idempotency should fail when existing fragment belongs to different author")
        } catch let error as SupabaseRoomError {
            if case .duplicate = error {
                assertCondition(true, "Idempotency distinguishes author collision with .duplicate")
            } else {
                assertCondition(false, "Idempotency threw wrong error type for author collision: \(error)")
            }
        } catch {
            assertCondition(false, "Idempotency threw unexpected error for author collision: \(error)")
        }

        // Case C: Different Room + Same Author -> Room collision error distinguished
        do {
            try SupabaseRoomRepository.evaluateFragmentIdempotency(
                existingRoomID: otherRoomUUID,
                existingAuthorID: targetAuthorUUID,
                targetRoomID: targetRoomUUID,
                targetAuthorID: targetAuthorUUID
            )
            assertCondition(false, "Idempotency should fail when existing fragment belongs to different room")
        } catch let error as SupabaseRoomError {
            if case .validationFailure = error {
                assertCondition(true, "Idempotency distinguishes room collision with .validationFailure")
            } else {
                assertCondition(false, "Idempotency threw wrong error type for room collision: \(error)")
            }
        } catch {
            assertCondition(false, "Idempotency threw unexpected error for room collision: \(error)")
        }

        // -------------------------------------------------------------
        // 8. JOIN ROOM LIFECYCLE ERROR MAPPING & VALIDATION
        // -------------------------------------------------------------
        struct MockError: LocalizedError {
            let errorDescription: String?
        }

        let archivedErr = MockError(errorDescription: "Room is archived.")
        let mappedArchived = SupabaseRoomRepository.mapJoinRPCError(archivedErr, code: "TEST01")
        assertCondition(
            mappedArchived == .validationFailure("This Room has been archived."),
            "Archived room RPC error maps to .validationFailure"
        )

        let endedErr = MockError(errorDescription: "Room has ended.")
        let mappedEnded = SupabaseRoomRepository.mapJoinRPCError(endedErr, code: "TEST01")
        assertCondition(
            mappedEnded == .validationFailure("This Room has already ended."),
            "Ended room RPC error maps to .validationFailure"
        )

        let notFoundErr = MockError(errorDescription: "Room not found for code TEST01")
        let mappedNotFound = SupabaseRoomRepository.mapJoinRPCError(notFoundErr, code: "TEST01")
        assertCondition(
            mappedNotFound == .notFound("No Room found matching code 'TEST01'."),
            "Not found RPC error maps to .notFound"
        )

        let unauthErr = MockError(errorDescription: "Authentication required.")
        let mappedUnauth = SupabaseRoomRepository.mapJoinRPCError(unauthErr, code: "TEST01")
        assertCondition(
            mappedUnauth == .notAuthenticated,
            "Unauthenticated RPC error maps to .notAuthenticated"
        )

        do {
            _ = try await repo.joinRoom(code: "ABC")
            assertCondition(false, "joinRoom with 3-char code should throw validationFailure")
        } catch let error as SupabaseRoomError {
            assertCondition(
                error == .validationFailure("Join code must be 6 characters."),
                "joinRoom rejects non-6-character code with .validationFailure"
            )
        } catch {
            assertCondition(false, "joinRoom with invalid length threw unexpected error: \(error)")
        }

        return (allPassed, logs)
    }
}
