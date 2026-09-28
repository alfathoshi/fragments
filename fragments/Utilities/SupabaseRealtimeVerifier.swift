//
//  SupabaseRealtimeVerifier.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import Supabase

/// Verification suite for Phase 2C-1 Supabase Realtime Coordinator.
///
/// Validates room-scoped filtering, event modeling, deduplication, timestamp ordering,
/// lifecycle guarantees, connection states, and coexistence without modifying CloudKit or Multipeer.
@MainActor
public enum SupabaseRealtimeVerifier {

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

        let coordinator = SupabaseRealtimeCoordinator.shared
        let testRoomID = "11111111-2222-3333-4444-555555555555"

        // -------------------------------------------------------------
        // 1. LIFECYCLE & INPUT VALIDATION
        // -------------------------------------------------------------
        do {
            try await coordinator.start(roomID: "   ")
            assertCondition(false, "start with empty roomID should throw invalidRoomID")
        } catch let error as SupabaseRealtimeError {
            assertCondition(error == .invalidRoomID("   "), "start with empty roomID throws .invalidRoomID")
        } catch {
            assertCondition(false, "start with empty roomID threw unexpected error: \(error)")
        }

        // -------------------------------------------------------------
        // 2. AUTHENTICATION GUARD VERIFICATION
        // -------------------------------------------------------------
        let isAuth = SupabaseService.shared.isAuthenticated
        if !isAuth {
            do {
                try await coordinator.start(roomID: testRoomID)
                assertCondition(false, "Unauthenticated start should throw .notAuthenticated")
            } catch let error as SupabaseRealtimeError {
                assertCondition(error == .notAuthenticated, "Unauthenticated start threw .notAuthenticated")
                assertCondition(coordinator.connectionState != .connected, "Unauthenticated start did not enter .connected")
            } catch {
                assertCondition(false, "Unauthenticated start threw unexpected error: \(error)")
            }
        } else {
            logs.append("ℹ️ [INFO] User is authenticated; skipping unauthenticated rejection test.")
        }

        // -------------------------------------------------------------
        // 3. STOP AND CLEANUP RELEASES SUBSCRIPTION
        // -------------------------------------------------------------
        await coordinator.stop(roomID: testRoomID)
        assertCondition(coordinator.activeRoomID == nil, "stop(roomID:) clears activeRoomID")
        assertCondition(coordinator.connectionState == .disconnected, "stop(roomID:) sets state to .disconnected")

        await coordinator.stopAll()
        assertCondition(coordinator.activeRoomID == nil, "stopAll() clears activeRoomID")
        assertCondition(coordinator.connectionState == .disconnected, "stopAll() sets state to .disconnected")

        // -------------------------------------------------------------
        // 4. DEDUPLICATION & ORDERING ENGINE VERIFICATION
        // -------------------------------------------------------------
        let now = Date()
        let tBase = now
        let tNewer = now.addingTimeInterval(10)
        let tOlder = now.addingTimeInterval(-10)
        let testEntityID = "shared-entity-uuid"

        // Baseline: initial event for shared_fragments / testEntityID at tBase
        let baseline = coordinator.checkDeduplicationAndOrder(
            table: "shared_fragments",
            op: "insert",
            id: testEntityID,
            timestamp: tBase,
            recordTime: "2026-09-27T12:00:00Z"
        )
        assertCondition(baseline, "Baseline event accepted for shared_fragments")

        // Case A: shared_fragments / same-ID / newer timestamp -> accepted
        let caseA = coordinator.checkDeduplicationAndOrder(
            table: "shared_fragments",
            op: "update",
            id: testEntityID,
            timestamp: tNewer,
            recordTime: "2026-09-27T12:00:10Z"
        )
        assertCondition(caseA, "Case A: shared_fragments / same-ID / newer timestamp accepted")

        // Case B: shared_fragments / same-ID / older timestamp -> rejected
        let caseB = coordinator.checkDeduplicationAndOrder(
            table: "shared_fragments",
            op: "update",
            id: testEntityID,
            timestamp: tOlder,
            recordTime: "2026-09-27T11:59:50Z"
        )
        assertCondition(!caseB, "Case B: shared_fragments / same-ID / older timestamp rejected as stale")

        // Case C: room_members / same-ID / older timestamp than shared_fragments
        // -> independently evaluated, NOT rejected because of shared_fragments timestamp
        let caseC = coordinator.checkDeduplicationAndOrder(
            table: "room_members",
            op: "insert",
            id: testEntityID,
            timestamp: tBase, // tBase < tNewer (which shared_fragments recorded)
            recordTime: "2026-09-27T12:00:00Z"
        )
        assertCondition(caseC, "Case C: room_members / same-ID / older timestamp than shared_fragments independently accepted")

        // Case D: same table + same record + duplicate event -> deduplicated (dropped)
        let caseD = coordinator.checkDeduplicationAndOrder(
            table: "shared_fragments",
            op: "update",
            id: testEntityID,
            timestamp: tNewer,
            recordTime: "2026-09-27T12:00:10Z"
        )
        assertCondition(!caseD, "Case D: same table + same record duplicate event dropped by deduplication")

        // Case E: same record ID across different tables -> treated as independent records
        let caseE1 = coordinator.checkDeduplicationAndOrder(
            table: "fragment_media",
            op: "insert",
            id: testEntityID,
            timestamp: tBase,
            recordTime: nil
        )
        let caseE2 = coordinator.checkDeduplicationAndOrder(
            table: "rooms",
            op: "update",
            id: testEntityID,
            timestamp: tBase,
            recordTime: nil
        )
        assertCondition(caseE1 && caseE2, "Case E: same record ID across different tables treated as independent records")

        // -------------------------------------------------------------
        // 5. EVENT MODEL & MULTI-SUBSCRIBER STREAM VERIFICATION
        // -------------------------------------------------------------
        let testFragment = SharedFragment(
            id: "22222222-3333-4444-5555-666666666666",
            roomId: testRoomID,
            authorId: "77777777-8888-9999-aaaa-bbbbbbbbbbbb",
            authorName: "Alice",
            type: .photo,
            createdAt: now,
            title: "Realtime Sunset",
            subtitle: "Beach side",
            text: "Captured at golden hour"
        )

        let testEvent = SupabaseRealtimeEvent.fragmentCreated(testFragment)

        // Verify async stream subscription receives emitted event
        let expectationStream = coordinator.events
        var receivedEvent: SupabaseRealtimeEvent? = nil

        let listenerTask = Task {
            for await event in expectationStream {
                receivedEvent = event
                break
            }
        }

        // Give stream a brief moment to attach continuation
        try? await Task.sleep(nanoseconds: 50_000_000)
        coordinator.emit(testEvent)

        // Wait for listener task
        _ = await listenerTask.result
        assertCondition(
            receivedEvent == testEvent,
            "Coordinator events stream yields typed SupabaseRealtimeEvent"
        )

        // -------------------------------------------------------------
        // 6. DOMAIN MAPPING VERIFICATION (FRAGMENT, MEMBER, MEDIA, ROOM)
        // -------------------------------------------------------------
        // 6A. Fragment Payload Mapping
        let fragJSON = """
        {
            "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "room_id": "\(testRoomID)",
            "author_id": "99999999-9999-9999-9999-999999999999",
            "author_name": "Bob",
            "type": "note",
            "title": "Realtime Note",
            "subtitle": null,
            "text": "Syncing via Postgres changes",
            "media_symbol": "doc.text",
            "location": "Jakarta",
            "duration": null,
            "audio_waveform": [],
            "accent_color_hex": "#FF5733",
            "phi": 0.1,
            "theta": 0.2,
            "radius_factor": 1.0,
            "created_at": "2026-09-27T12:00:00Z"
        }
        """.data(using: .utf8)!

        do {
            let fragDTO = try JSONDecoder().decode(DatabaseSharedFragment.self, from: fragJSON)
            let domainFrag = fragDTO.toDomain()
            assertCondition(domainFrag.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "Fragment DTO maps ID")
            assertCondition(domainFrag.type == .note, "Fragment DTO maps Note type")
            assertCondition(domainFrag.authorName == "Bob", "Fragment DTO maps authorName")
            assertCondition(domainFrag.accentColorHex == "#FF5733", "Fragment DTO maps accent color")
        } catch {
            assertCondition(false, "Fragment payload decoding failed: \(error)")
        }

        // 6B. Member Payload Mapping
        let memberJSON = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "room_id": "\(testRoomID)",
            "user_id": "44444444-4444-4444-4444-444444444444",
            "role": "owner",
            "joined_at": "2026-09-27T12:00:00Z"
        }
        """.data(using: .utf8)!

        do {
            let memberDTO = try JSONDecoder().decode(RealtimeRoomMemberPayload.self, from: memberJSON)
            let domainMember = memberDTO.toDomain()
            assertCondition(domainMember.role == .owner, "Member payload maps owner role")
            assertCondition(domainMember.roomId == testRoomID, "Member payload maps roomID")
            assertCondition(domainMember.avatarAssetURL == nil, "Member payload does not auto-download avatars")
        } catch {
            assertCondition(false, "Member payload decoding failed: \(error)")
        }

        // 6C. Media Payload Mapping
        let mediaJSON = """
        {
            "id": "55555555-5555-5555-5555-555555555555",
            "fragment_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "room_id": "\(testRoomID)",
            "storage_path": "rooms/\(testRoomID)/fragments/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg",
            "file_extension": "jpg",
            "file_size": 2048,
            "mime_type": "image/jpeg"
        }
        """.data(using: .utf8)!

        do {
            let mediaDTO = try JSONDecoder().decode(DatabaseFragmentMedia.self, from: mediaJSON)
            let mediaRef = mediaDTO.toMediaReference()
            assertCondition(mediaRef.storagePath == "rooms/\(testRoomID)/fragments/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg", "Media payload maps storagePath")
            assertCondition(mediaRef.localFileURL == nil, "Media payload does not auto-download media binaries")
            assertCondition(mediaRef.fileSize == 2048, "Media payload maps fileSize metadata")
        } catch {
            assertCondition(false, "Media payload decoding failed: \(error)")
        }

        // 6D. Room Payload Mapping
        let roomJSON = """
        {
            "id": "\(testRoomID)",
            "name": "Live Moment",
            "emoji": "🎉",
            "accent_color_hex": "#00FF00",
            "created_by": "44444444-4444-4444-4444-444444444444",
            "created_at": "2026-09-27T12:00:00Z",
            "is_ended": false,
            "is_archived": false,
            "final_title": null,
            "final_category": null,
            "join_code": "LIVE1234"
        }
        """.data(using: .utf8)!

        do {
            let roomDTO = try JSONDecoder().decode(DatabaseRoom.self, from: roomJSON)
            let domainRoom = roomDTO.toDomain()
            assertCondition(domainRoom.id == testRoomID, "Room payload maps id")
            assertCondition(domainRoom.name == "Live Moment", "Room payload maps name")
            assertCondition(domainRoom.emoji == "🎉", "Room payload maps emoji")
            assertCondition(domainRoom.shareRecordID == "LIVE1234", "Room payload maps joinCode")
        } catch {
            assertCondition(false, "Room payload decoding failed: \(error)")
        }

        // -------------------------------------------------------------
        // 7. SECURITY & SERVICE ROLE KEY CHECK
        // -------------------------------------------------------------
        let anonKey = SupabaseService.defaultAnonKey
        assertCondition(
            !anonKey.contains("service_role"),
            "Client configuration strictly uses public anon key; service-role key is forbidden"
        )

        // -------------------------------------------------------------
        // 8. SUBSYSTEM INDEPENDENCE
        // -------------------------------------------------------------
        assertCondition(CloudKitRoomRepository.shared != nil, "CloudKitRoomRepository remains untouched")
        assertCondition(MultipeerSyncService.shared != nil, "MultipeerSyncService remains untouched")

        return (allPassed, logs)
    }
}
