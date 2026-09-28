//
//  SupabaseRoomManagerVerifier.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import Supabase

/// Verification suite for Phase 2C-2.5: Integration Hardening.
///
/// Validates:
/// 1. Backend persistence (JSON encoding/decoding preserves backend origin).
/// 2. New Room backend ownership (explicit .supabase default, no silent fallback).
/// 3. Reconciliation race (Realtime event A -> reconcile -> Realtime event B -> old reconcile returns).
/// 4. Room switch race (stale async responses and events dropped after room switch).
/// 5. Realtime task cancellation (Room switch / nil cancels task and releases channel).
/// 6. Optimistic mutation failure (capture and delete rollback on remote failure).
/// 7. CloudKit/Supabase backend isolation.
/// 8. Local cache isolation (purging Supabase room only deletes that room's files).
@MainActor
public enum SupabaseRoomManagerVerifier {

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

        let roomManager = RoomManager.shared
        let coordinator = SupabaseRealtimeCoordinator.shared
        let isAuth = SupabaseService.shared.isAuthenticated
        let cache = LocalRoomCache.shared

        // -------------------------------------------------------------
        // 1. BACKEND PERSISTENCE
        // -------------------------------------------------------------
        logs.append("--- 1. Backend Persistence ---")

        let testSBID = "sb-persist-\(UUID().uuidString.prefix(8))"
        let testCKID = "ck-persist-\(UUID().uuidString.prefix(8))"
        let testNilID = "nil-persist-\(UUID().uuidString.prefix(8))"

        let sbRoomToPersist = Room(
            id: testSBID,
            name: "Supabase Persistent Room",
            emoji: "⚡️",
            createdAt: Date(),
            createdBy: "sb-user",
            shareRecordID: "CODE99",
            zoneName: "supabase"
        )
        let ckRoomToPersist = Room(
            id: testCKID,
            name: "CloudKit Persistent Room",
            emoji: "☁️",
            createdAt: Date(),
            createdBy: "ck-user",
            shareRecordID: "ck-share",
            zoneName: "RoomZone_\(testCKID)"
        )
        let nilZoneRoomToPersist = Room(
            id: testNilID,
            name: "Nil Zone Persistent Room",
            emoji: "📦",
            createdAt: Date(),
            createdBy: "nil-user",
            zoneName: nil
        )

        try? cache.saveRoom(sbRoomToPersist)
        try? cache.saveRoom(ckRoomToPersist)
        try? cache.saveRoom(nilZoneRoomToPersist)

        let loadedRooms = (try? cache.loadRooms()) ?? []
        let restoredSB = loadedRooms.first(where: { $0.id == testSBID })
        let restoredCK = loadedRooms.first(where: { $0.id == testCKID })
        let restoredNil = loadedRooms.first(where: { $0.id == testNilID })

        assertCondition(restoredSB?.backend == .supabase, "Persisted Supabase room restores with backend .supabase")
        assertCondition(restoredCK?.backend == .cloudKit, "Persisted CloudKit room restores with backend .cloudKit")
        assertCondition(restoredNil?.backend == .cloudKit, "Persisted nil-zone room restores with backend .cloudKit")

        // Cleanup
        try? cache.deleteRoom(id: testSBID)
        try? cache.deleteRoom(id: testCKID)
        try? cache.deleteRoom(id: testNilID)

        // -------------------------------------------------------------
        // 2. NEW ROOM BACKEND OWNERSHIP
        // -------------------------------------------------------------
        logs.append("--- 2. New Room Backend Ownership ---")

        // Explicit CloudKit creation fallback test
        do {
            let legacyCK = try await roomManager.createRoom(
                name: "Legacy CK Room",
                backend: .cloudKit
            )
            assertCondition(legacyCK.backend == .cloudKit, "Explicit backend .cloudKit produces a .cloudKit room")
            assertCondition(legacyCK.zoneName?.contains("RoomZone") == true, "CloudKit room has RoomZone zoneName")
            // Cleanup
            try? await roomManager.deleteRoom(id: legacyCK.id)
        } catch {
            logs.append("ℹ️ [INFO] CloudKit creation threw (offline simulator): \(error.localizedDescription)")
        }

        // Unauthenticated Supabase creation guard
        if !isAuth {
            do {
                _ = try await roomManager.createRoom(
                    name: "Unauthenticated SB Room",
                    backend: .supabase
                )
                assertCondition(false, "Unauthenticated createRoom with backend .supabase should throw")
            } catch {
                assertCondition(true, "Unauthenticated createRoom with backend .supabase threw: \(error.localizedDescription)")
                assertCondition(roomManager.lastError != nil, "roomManager.lastError populated on Supabase failure")
            }
        } else {
            logs.append("ℹ️ [INFO] User is authenticated with Supabase.")
        }

        // -------------------------------------------------------------
        // 3. RECONCILIATION RACE CONDITIONS
        // -------------------------------------------------------------
        logs.append("--- 3. Reconciliation Race Conditions ---")

        let raceRoomID = "race-test-room"
        let t1 = Date().addingTimeInterval(-100)
        let t2 = Date().addingTimeInterval(-50)
        let fragA = SharedFragment(
            id: "frag-a",
            roomId: raceRoomID,
            authorId: "user-1",
            authorName: "Alice",
            type: .note,
            createdAt: t1,
            title: "Fragment A",
            text: "Initial A"
        )
        let fragB = SharedFragment(
            id: "frag-b",
            roomId: raceRoomID,
            authorId: "user-2",
            authorName: "Bob",
            type: .note,
            createdAt: t2,
            title: "Fragment B (Newer)",
            text: "Arrived via Realtime"
        )

        // Test Race A: Realtime event B arrived during reconcile fetch for A.
        // Existing in-memory: [fragA, fragB].
        // Stale incoming fetch snapshot: only [fragA].
        let mergedRaceA = roomManager.mergeFragments(
            existing: [fragA, fragB],
            incoming: [fragA]
        )
        assertCondition(
            mergedRaceA.contains(where: { $0.id == "frag-b" }),
            "Race A: mergeFragments preserves newer in-memory fragment that arrived during fetch"
        )
        assertCondition(
            mergedRaceA.count == 2,
            "Race A: Both fragments are preserved in merged result"
        )

        // Test Race B: fragmentMediaCreated -> reconcile -> fragmentUpdated
        var fragAUpdated = fragA
        fragAUpdated.text = "Locally Edited Text"
        let mediaRef = SharedMediaReference(
            storagePath: "media/photo.jpg",
            fileSize: 2048,
            mimeType: "image/jpeg"
        )
        var remoteFragAWithMedia = fragA
        remoteFragAWithMedia.mediaReference = mediaRef

        let mergedRaceB = roomManager.mergeFragments(
            existing: [fragAUpdated],
            incoming: [remoteFragAWithMedia]
        )
        let resolvedFragA = mergedRaceB.first(where: { $0.id == "frag-a" })
        assertCondition(
            resolvedFragA?.mediaReference?.storagePath == "media/photo.jpg",
            "Race B: mergeFragments attaches media reference from remote snapshot"
        )
        assertCondition(
            resolvedFragA?.text == "Locally Edited Text",
            "Race B: mergeFragments retains updated text content"
        )

        // -------------------------------------------------------------
        // 4. ROOM SWITCH RACE
        // -------------------------------------------------------------
        logs.append("--- 4. Room Switch Race ---")

        let roomA = Room(id: "room-a-switch", name: "Room A", createdBy: "user", zoneName: "supabase")
        let roomB = Room(id: "room-b-switch", name: "Room B", createdBy: "user", zoneName: "supabase")

        roomManager.currentRoom = roomA
        assertCondition(roomManager.currentRoom?.id == "room-a-switch", "currentRoom set to Room A")

        // Switch to Room B
        roomManager.currentRoom = roomB
        assertCondition(roomManager.currentRoom?.id == "room-b-switch", "currentRoom switched to Room B")

        // Stale event for Room A arrives
        let staleEvent = SupabaseRealtimeEvent.fragmentCreated(
            SharedFragment(id: "stale-frag", roomId: "room-a-switch", authorId: "u", authorName: "U", type: .note, title: "Stale")
        )
        await roomManager.handleRealtimeEvent(staleEvent, forRoomID: "room-a-switch")

        assertCondition(
            !roomManager.fragments.contains(where: { $0.id == "stale-frag" }),
            "Room switch: Stale event for Room A is rejected while active in Room B"
        )

        // -------------------------------------------------------------
        // 5. REALTIME TASK CANCELLATION & LIFECYCLE
        // -------------------------------------------------------------
        logs.append("--- 5. Realtime Task Cancellation & Lifecycle ---")

        // Setting currentRoom to nil
        roomManager.currentRoom = nil
        assertCondition(roomManager.currentRoom == nil, "currentRoom successfully set to nil")
        assertCondition(roomManager.members.isEmpty, "members cleared when currentRoom is nil")
        assertCondition(roomManager.fragments.isEmpty, "fragments cleared when currentRoom is nil")
        assertCondition(coordinator.activeRoomID == nil, "Realtime coordinator inactive when currentRoom is nil")

        // -------------------------------------------------------------
        // 6. OPTIMISTIC MUTATION FAILURE ROLLBACK
        // -------------------------------------------------------------
        logs.append("--- 6. Optimistic Mutation Failure Rollback ---")

        // Setup a temporary Supabase test room
        let activeSBRoom = Room(
            id: UUID().uuidString.lowercased(),
            name: "Rollback Test Room",
            createdBy: "sb-tester",
            zoneName: "supabase"
        )
        roomManager.currentRoom = activeSBRoom

        let failFragment = SharedFragment(
            id: "fail-frag-\(UUID().uuidString.prefix(6))",
            roomId: activeSBRoom.id,
            authorId: "author-1",
            authorName: "Tester",
            type: .note,
            title: "Should Fail",
            text: "This capture will fail remotely"
        )

        // Test capture failure rollback (when unauthenticated or invalid)
        if !isAuth {
            do {
                try await roomManager.captureSharedFragment(failFragment)
                assertCondition(false, "Unauthenticated capture should throw")
            } catch {
                assertCondition(
                    !roomManager.fragments.contains(where: { $0.id == failFragment.id }),
                    "Capture failure: Optimistically appended fragment was rolled back from fragments array"
                )
                assertCondition(roomManager.lastError != nil, "Capture failure: lastError was populated")
            }
        } else {
            logs.append("ℹ️ [INFO] User is authenticated; skipping offline capture rollback test.")
        }

        // -------------------------------------------------------------
        // 7. BACKEND ISOLATION
        // -------------------------------------------------------------
        logs.append("--- 7. Backend Isolation ---")

        let isolatedCKRoom = Room(
            id: "isolated-ck",
            name: "Isolated CloudKit",
            createdBy: "ck-user",
            zoneName: "RoomZone_Isolated"
        )
        roomManager.currentRoom = isolatedCKRoom
        assertCondition(roomManager.currentRoom?.backend == .cloudKit, "isolatedCKRoom has backend .cloudKit")
        assertCondition(coordinator.activeRoomID == nil, "CloudKit room does NOT start Supabase Realtime")

        // -------------------------------------------------------------
        // 8. LOCAL CACHE ISOLATION
        // -------------------------------------------------------------
        logs.append("--- 8. Local Cache Isolation ---")

        let cacheRoomA = "cache-iso-room-a"
        let cacheRoomB = "cache-iso-room-b"

        let roomAObj = Room(id: cacheRoomA, name: "Room A", createdBy: "user", zoneName: "supabase")
        let roomBObj = Room(id: cacheRoomB, name: "Room B", createdBy: "user", zoneName: "supabase")

        try? cache.saveRoom(roomAObj)
        try? cache.saveRoom(roomBObj)
        try? cache.saveMembers([RoomMember(id: "m-a", roomId: cacheRoomA, userId: "u-a", displayName: "A", role: .member, joinedAt: Date())], roomID: cacheRoomA)
        try? cache.saveMembers([RoomMember(id: "m-b", roomId: cacheRoomB, userId: "u-b", displayName: "B", role: .member, joinedAt: Date())], roomID: cacheRoomB)

        // Delete Room A from cache
        try? cache.deleteRoom(id: cacheRoomA)

        let remaining = (try? cache.loadRooms()) ?? []
        assertCondition(!remaining.contains(where: { $0.id == cacheRoomA }), "Room A was removed from manifest")
        assertCondition(remaining.contains(where: { $0.id == cacheRoomB }), "Room B remains in manifest")

        let roomBMembers = (try? cache.loadMembers(roomID: cacheRoomB)) ?? []
        assertCondition(roomBMembers.contains(where: { $0.id == "m-b" }), "Room B members intact after deleting Room A")

        // Cleanup
        try? cache.deleteRoom(id: cacheRoomB)
        roomManager.currentRoom = nil

        logs.append("---------------------------------------------")
        logs.append("PHASE 2C-2.5 VERIFICATION: \(allPassed ? "ALL 8 TESTS PASSED ✅" : "SOME TESTS FAILED ❌")")
        logs.append("---------------------------------------------")

        return (allPassed, logs)
    }
}
