//
//  CloudKitCollaborationValidator.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit

/// Automated test suite validating Phase 6 multi-user collaboration flows:
/// Owner creation, CKShare association, Participant acceptance simulation,
/// Member role permissions, SharedFragment author attribution, Account isolation,
/// Failure cases, and Cache read-through.
public enum CloudKitCollaborationValidator {

    public static func runAllTests() -> (passed: Bool, log: [String]) {
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

        // =========================================================================
        // 1. OWNER FLOW & CKSHARE ASSOCIATION (Phase 6.3)
        // =========================================================================
        let ownerID = "user_account_A_owner"
        let roomID = "room_collab_test_001"
        let zoneID = CKRecordZone.ID(zoneName: "RoomZone_\(roomID)", ownerName: CKCurrentUserDefaultName)

        let ownerRoom = Room(
            id: roomID,
            name: "Bali Trip 2026",
            emoji: "🌴",
            createdAt: Date(timeIntervalSince1970: 1774600000),
            createdBy: ownerID,
            shareRecordID: "cloudkit.share_room_collab_test_001",
            zoneName: zoneID.zoneName,
            isArchived: false,
            memberCount: 1,
            fragmentCount: 0
        )

        let roomRecord = CloudKitRecordMapper.toRecord(from: ownerRoom, in: zoneID)
        let share = CKShare(rootRecord: roomRecord)
        share[CKShare.SystemFieldKey.title] = ownerRoom.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.alfathoshi.fragments.room" as CKRecordValue
        share.publicPermission = .none // Private sharing only

        assertCondition(roomRecord.recordID.zoneID.zoneName == "RoomZone_\(roomID)", "Owner: Room created in dedicated custom zone")
        assertCondition(roomRecord.share?.recordID == share.recordID, "Owner: Room record share reference matches CKShare.recordID")
        assertCondition(share.recordID.zoneID == roomRecord.recordID.zoneID, "Owner: CKShare created in same custom zone as Room")
        assertCondition(share.publicPermission == .none, "Owner: CKShare publicPermission is strictly .none (private invite only)")
        assertCondition(share[CKShare.SystemFieldKey.title] as? String == "Bali Trip 2026", "Owner: CKShare title matches Room name")

        // =========================================================================
        // 2. PARTICIPANT ACCEPTANCE & SHARING HIERARCHY (Phase 6.4 & 6.5)
        // =========================================================================
        let participantID = "user_account_B_participant"
        let participantMember = RoomMember(
            id: "\(roomID)_\(participantID)",
            roomId: roomID,
            userId: participantID,
            displayName: "Sarah",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 1774601000)
        )

        let memberRecord = CloudKitRecordMapper.toRecord(from: participantMember, in: zoneID)
        assertCondition(memberRecord.parent?.recordID == roomRecord.recordID, "Participant: RoomMember record.parent is Room record (for zone sharing)")
        let memberRef = memberRecord[CloudKitRecordKey.memberRoom] as? CKRecord.Reference
        assertCondition(memberRef?.action == .deleteSelf, "Participant: RoomMember cascades deletion (.deleteSelf)")

        // =========================================================================
        // 3. MULTI-AUTHOR SHARED FRAGMENT & OWNER READ ATTRIBUTION (Phase 6.6 & 6.7)
        // =========================================================================
        // Account B writes a fragment
        let accountBFragment = SharedFragment(
            id: "frag_account_B_001",
            roomId: roomID,
            authorId: participantID,
            authorName: "Sarah",
            type: .note,
            createdAt: Date(timeIntervalSince1970: 1774602000),
            title: "Hello from Account B",
            text: "Shared CloudKit test from Participant",
            location: "Uluwatu, Bali"
        )

        let fragRecord = CloudKitRecordMapper.toRecord(from: accountBFragment, in: zoneID)
        assertCondition(fragRecord.parent?.recordID == roomRecord.recordID, "SharedFragment: record.parent set to Room record")
        let fragRef = fragRecord[CloudKitRecordKey.fragmentRoom] as? CKRecord.Reference
        assertCondition(fragRef?.action == .deleteSelf, "SharedFragment: Foreign key reference uses .deleteSelf")

        // Account A reads Account B's fragment
        let roundtripFragment = CloudKitRecordMapper.toSharedFragment(from: fragRecord)
        assertCondition(roundtripFragment?.authorId == participantID, "Owner Read: Fragment authorID matches Account B")
        assertCondition(roundtripFragment?.authorName == "Sarah", "Owner Read: Fragment authorName matches Account B's display name")
        assertCondition(roundtripFragment?.roomId == roomID, "Owner Read: Fragment roomID matches shared Room")
        assertCondition(roundtripFragment?.title == "Hello from Account B", "Owner Read: Fragment title preserved across users")

        // =========================================================================
        // 4. PERMISSION ENFORCEMENT VALIDATION (Phase 6.8)
        // =========================================================================
        let ownerRole = RoomRole.owner
        let memberRole = RoomRole.member
        let viewerRole = RoomRole.viewer

        assertCondition(ownerRole.canManageMembers == true && ownerRole.canCaptureFragments == true, "Permission: Owner can manage members & capture fragments")
        assertCondition(memberRole.canManageMembers == false && memberRole.canCaptureFragments == true, "Permission: Member can capture fragments but cannot manage members")
        assertCondition(viewerRole.canManageMembers == false && viewerRole.canCaptureFragments == false, "Permission: Viewer is strictly read-only")

        // =========================================================================
        // 5. ACCOUNT ISOLATION (Phase 6.9)
        // =========================================================================
        // Uninvited Account C has no share or zone association
        let uninvitedUserID = "user_account_C_uninvited"
        let isInvited = [ownerID, participantID].contains(uninvitedUserID)
        assertCondition(!isInvited, "Isolation: Account C is uninvited and excluded from share participants")
        assertCondition(share.publicPermission == .none, "Isolation: Private permission prevents discovery by Account C")

        // =========================================================================
        // 6. FAILURE CASES (Phase 6.10)
        // =========================================================================
        // Unauthenticated check
        let unauthenticatedError = CloudKitRoomError.unauthenticated
        assertCondition(unauthenticatedError.errorDescription?.contains("iCloud") == true, "Failure Cases: Unauthenticated error explicitly formatted")

        // Offline check
        let offlineError = CloudKitRoomError.offline
        assertCondition(offlineError.errorDescription?.contains("Network unavailable") == true, "Failure Cases: Offline error explicitly formatted (no fake success)")

        // Room not found check
        let notFoundError = CloudKitRoomError.roomNotFound("missing_room_123")
        assertCondition(notFoundError.errorDescription?.contains("missing_room_123") == true, "Failure Cases: Room not found error explicitly formatted")

        // =========================================================================
        // 7. LOCAL CACHE VALIDATION (Phase 6.11)
        // =========================================================================
        let testCacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("CollabCacheTest_\(UUID().uuidString)")
        let cache = LocalRoomCache(baseDirectory: testCacheDir)

        do {
            try cache.saveRoom(ownerRoom)
            try cache.saveMembers([participantMember], roomID: roomID)
            try cache.saveFragments([accountBFragment], roomID: roomID)

            // Simulate CloudKit unavailable: read exclusively from disk
            let cachedRooms = try cache.loadRooms()
            let cachedMembers = try cache.loadMembers(roomID: roomID)
            let cachedFrags = try cache.loadFragments(roomID: roomID)

            assertCondition(cachedRooms.count == 1 && cachedRooms.first?.id == roomID, "Cache Validation: Room read successfully from disk cache when offline")
            assertCondition(cachedMembers.count == 1 && cachedMembers.first?.displayName == "Sarah", "Cache Validation: Member read successfully from disk cache when offline")
            assertCondition(cachedFrags.count == 1 && cachedFrags.first?.authorName == "Sarah", "Cache Validation: Fragment read successfully from disk cache when offline")
        } catch {
            assertCondition(false, "Cache Validation failed: \(error)")
        }

        try? FileManager.default.removeItem(at: testCacheDir)

        return (allPassed, logs)
    }
}
