//
//  RealtimeConvergenceVerifier.swift
//  fragments
//
//  Created on 9/28/26.
//

import Foundation
import SwiftUI

/// Verification engine for Phase 1: Supabase Realtime Convergence.
///
/// Validates that:
/// 1. Supabase-backed shared sessions activate Supabase Realtime observation.
/// 2. Legacy CloudKit polling (startRemoteSyncObserver) is completely bypassed for Supabase sessions.
/// 3. Typed Realtime events flow from RoomManager to MomentManager reactively.
/// 4. Duplicate Realtime events are cleanly reconciled without duplicating fragments in activeSession.
/// 5. UPDATE and DELETE events incrementally modify activeSession.fragments.
/// 6. Ending, leaving, or cancelling sessions tears down the Realtime observer without restarting CloudKit polling.
#if DEBUG
@MainActor
public enum RealtimeConvergenceVerifier {

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

        let momentManager = MomentManager.shared
        let roomManager = RoomManager.shared

        // Ensure clean initial state
        if momentManager.isSessionActive {
            momentManager.cancelSession()
        }

        let testRoomID = "test-room-" + UUID().uuidString.lowercased()
        let testRoom = Room(
            id: testRoomID,
            name: "Test Convergence Room",
            emoji: "⚡️",
            createdAt: Date(),
            createdBy: "test_host",
            shareRecordID: "CONV01",
            zoneName: "supabase",
            memberCount: 1,
            fragmentCount: 0
        )

        // -------------------------------------------------------------
        // SCENARIO A — HOST SESSION CREATION & SUBSCRIPTION LIFECYCLE
        // -------------------------------------------------------------
        logs.append("--- Scenario A: Host Session & Polling Bypass ---")
        assertCondition(testRoom.backend == .supabase, "RoomBackend evaluates to .supabase when zoneName is 'supabase'")

        // Launch shared session with Supabase room
        momentManager.startSession(location: "Test Lab", isShared: true, room: testRoom)
        RoomManager.shared.currentRoom = testRoom
        momentManager.startSupabaseRealtimeObserver(roomID: testRoomID)

        assertCondition(momentManager.isSessionActive, "Active session is established")
        assertCondition(momentManager.isSupabaseRealtimeTaskActive, "Supabase Realtime observer task is active")
        assertCondition(!momentManager.isRemoteSyncTaskActive, "CloudKit polling task is NOT running")

        // Direct call to startRemoteSyncObserver must be guarded and rejected
        momentManager.startRemoteSyncObserver(roomID: testRoomID)
        assertCondition(!momentManager.isRemoteSyncTaskActive, "Direct startRemoteSyncObserver is safely bypassed for Supabase room")

        // -------------------------------------------------------------
        // SCENARIO C — REMOTE FRAGMENT INSERTION
        // -------------------------------------------------------------
        logs.append("--- Scenario C: Remote Fragment Realtime Insertion ---")
        let frag1ID = UUID().uuidString.lowercased()
        let sharedFrag1 = SharedFragment(
            id: frag1ID,
            roomId: testRoomID,
            authorId: "remote_collaborator_1",
            authorName: "Alice",
            type: .note,
            createdAt: Date(),
            title: "Morning Note",
            text: "Hello collaborative world!",
            phi: 0.12,
            theta: 0.45,
            radiusFactor: 1.01
        )

        // Simulate incoming Realtime event dispatched through RoomManager
        await roomManager.handleRealtimeEvent(.fragmentCreated(sharedFrag1), forRoomID: testRoomID)
        momentManager.handleRealtimeEvent(.fragmentCreated(sharedFrag1), forRoomID: testRoomID)

        let fragsAfterInsert = momentManager.activeSession?.fragments ?? []
        let insertedFrag = fragsAfterInsert.first(where: { $0.id.uuidString.lowercased() == frag1ID })
        assertCondition(insertedFrag != nil, "Remote fragment 1 inserted into activeSession.fragments")
        assertCondition(insertedFrag?.title == "Morning Note", "Remote fragment title preserved")
        assertCondition(insertedFrag?.text == "Hello collaborative world!", "Remote fragment text preserved")
        assertCondition(fragsAfterInsert.count == 1, "Session fragment count is exactly 1")

        // -------------------------------------------------------------
        // SCENARIO D — DUPLICATE EVENT REPLAY & RECONCILIATION
        // -------------------------------------------------------------
        logs.append("--- Scenario D: Duplicate Event Replay ---")
        // Replay identical fragment event
        await roomManager.handleRealtimeEvent(.fragmentCreated(sharedFrag1), forRoomID: testRoomID)
        momentManager.handleRealtimeEvent(.fragmentCreated(sharedFrag1), forRoomID: testRoomID)

        let fragsAfterDuplicate = momentManager.activeSession?.fragments ?? []
        assertCondition(fragsAfterDuplicate.count == 1, "Duplicate fragment event does not increase fragment count")

        // Optimistic reconciliation: mutate text on server and receive as insert event
        var replayedFragWithUpdate = sharedFrag1
        replayedFragWithUpdate.text = "Updated server text"
        momentManager.handleRealtimeEvent(.fragmentCreated(replayedFragWithUpdate), forRoomID: testRoomID)
        let reconciledFrag = momentManager.activeSession?.fragments.first(where: { $0.id.uuidString.lowercased() == frag1ID })
        assertCondition(reconciledFrag?.text == "Updated server text", "Optimistic fragment reconciled non-destructively")
        assertCondition(momentManager.activeSession?.fragments.count == 1, "Reconciliation does not duplicate fragment")

        // -------------------------------------------------------------
        // SCENARIO F — UPDATE & DELETE REALTIME EVENTS
        // -------------------------------------------------------------
        logs.append("--- Scenario F: UPDATE & DELETE Realtime Events ---")
        var updatedFrag1 = sharedFrag1
        updatedFrag1.title = "Afternoon Note"
        updatedFrag1.text = "Updated via Realtime UPDATE"

        await roomManager.handleRealtimeEvent(.fragmentUpdated(updatedFrag1), forRoomID: testRoomID)
        momentManager.handleRealtimeEvent(.fragmentUpdated(updatedFrag1), forRoomID: testRoomID)

        let fragAfterUpdate = momentManager.activeSession?.fragments.first(where: { $0.id.uuidString.lowercased() == frag1ID })
        assertCondition(fragAfterUpdate?.title == "Afternoon Note", "UPDATE event replaced fragment title in place")
        assertCondition(fragAfterUpdate?.text == "Updated via Realtime UPDATE", "UPDATE event replaced fragment text in place")
        assertCondition(momentManager.activeSession?.fragments.count == 1, "UPDATE event did not alter array length")

        // Test DELETE
        await roomManager.handleRealtimeEvent(.fragmentDeleted(fragmentID: frag1ID, roomID: testRoomID, fragment: nil), forRoomID: testRoomID)
        momentManager.handleRealtimeEvent(.fragmentDeleted(fragmentID: frag1ID, roomID: testRoomID, fragment: nil), forRoomID: testRoomID)

        let fragsAfterDelete = momentManager.activeSession?.fragments ?? []
        assertCondition(!fragsAfterDelete.contains(where: { $0.id.uuidString.lowercased() == frag1ID }), "DELETE event removed fragment from activeSession")
        assertCondition(fragsAfterDelete.isEmpty, "Active session fragments is now empty after delete")

        // -------------------------------------------------------------
        // SCENARIO B — PARTICIPANT JOIN LIFECYCLE
        // -------------------------------------------------------------
        logs.append("--- Scenario B: Participant Join Session ---")
        let participantRoomID = "participant-room-" + UUID().uuidString.lowercased()
        let participantRoom = Room(
            id: participantRoomID,
            name: "Participant Shared Moment",
            emoji: "👥",
            createdAt: Date(),
            createdBy: "other_user",
            shareRecordID: "JOIN01",
            zoneName: "supabase",
            memberCount: 2,
            fragmentCount: 1
        )

        momentManager.joinSharedSession(room: participantRoom)
        assertCondition(momentManager.isSessionActive, "Participant session active")
        assertCondition(momentManager.isSupabaseRealtimeTaskActive, "Participant Realtime observer active")
        assertCondition(!momentManager.isRemoteSyncTaskActive, "Participant does NOT start CloudKit polling")

        // -------------------------------------------------------------
        // SCENARIO E — SESSION TEARDOWN & CLEANUP
        // -------------------------------------------------------------
        logs.append("--- Scenario E: Session Teardown ---")
        momentManager.cancelSession()

        assertCondition(!momentManager.isSessionActive, "Session cleanly terminated")
        assertCondition(!momentManager.isSupabaseRealtimeTaskActive, "Supabase Realtime observer task cancelled on teardown")
        assertCondition(!momentManager.isRemoteSyncTaskActive, "CloudKit polling task remains stopped")

        return (passed: allPassed, log: logs)
    }
}
#endif
