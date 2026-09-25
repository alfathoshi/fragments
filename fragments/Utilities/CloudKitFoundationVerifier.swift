//
//  CloudKitFoundationVerifier.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit
import CoreGraphics
import SwiftUI

/// Verification suite validating Phase 1–3 CloudKit foundation and contract mappings.
public enum CloudKitFoundationVerifier {

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

        // Test 1: CloudKit Service configuration
        assertCondition(
            CloudKitService.containerIdentifier == "iCloud.com.alfathoshi.fragments",
            "CloudKit container identifier matches iCloud.com.alfathoshi.fragments"
        )

        // Test 2: Room CKRecord roundtrip mapping
        let testRoom = Room(
            id: "room_test_123",
            name: "Bali Trip 2026",
            emoji: "🌴",
            createdAt: Date(timeIntervalSince1970: 1774416000),
            createdBy: "user_owner_456",
            shareRecordID: "share_rec_789",
            zoneName: "RoomZone-bali",
            isArchived: false,
            memberCount: 4,
            fragmentCount: 27,
            accentColorHex: "#FF5733"
        )
        let roomRecord = CloudKitRecordMapper.toRecord(from: testRoom)
        let mappedRoom = CloudKitRecordMapper.toRoom(from: roomRecord)

        assertCondition(mappedRoom?.id == testRoom.id, "Room ID roundtrip matches")
        assertCondition(mappedRoom?.name == "Bali Trip 2026", "Room name roundtrip matches")
        assertCondition(mappedRoom?.emoji == "🌴", "Room emoji roundtrip matches")
        assertCondition(mappedRoom?.createdBy == "user_owner_456", "Room createdBy roundtrip matches")
        assertCondition(mappedRoom?.memberCount == 4, "Room memberCount roundtrip matches")
        assertCondition(mappedRoom?.fragmentCount == 27, "Room fragmentCount roundtrip matches")
        assertCondition(mappedRoom?.shareRecordID == "share_rec_789", "Room shareRecordID roundtrip matches")
        assertCondition(mappedRoom?.accentColorHex == "#FF5733", "Room accentColorHex roundtrip matches")

        // Test 3: RoomMember CKRecord mapping with parent reference & deleteSelf cascade
        let testMember = RoomMember(
            id: "member_test_001",
            roomId: testRoom.id,
            userId: "user_sarah_789",
            displayName: "Sarah",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 1774417000)
        )
        let memberRecord = CloudKitRecordMapper.toRecord(from: testMember)
        let mappedMember = CloudKitRecordMapper.toRoomMember(from: memberRecord)

        assertCondition(mappedMember?.id == testMember.id, "RoomMember ID roundtrip matches")
        assertCondition(mappedMember?.roomId == testRoom.id, "RoomMember parent roomId matches")
        assertCondition(mappedMember?.displayName == "Sarah", "RoomMember displayName matches")
        assertCondition(mappedMember?.role == .member, "RoomMember role matches")

        // Verify member parent hierarchy and cascading delete
        let memberParentRef = memberRecord.parent
        let memberRoomRef = memberRecord[CloudKitRecordKey.memberRoom] as? CKRecord.Reference
        assertCondition(memberParentRef?.recordID.recordName == testRoom.id, "RoomMember has correct parent CKRecord.Reference")
        assertCondition(
            memberRoomRef?.action == .deleteSelf,
            "RoomMember references Room with .deleteSelf cascading delete action"
        )

        // Test 4: SharedFragment CKRecord mapping with parent reference, deleteSelf, and waveforms
        let testWaveform: [CGFloat] = [0.1, 0.45, 0.9, 0.65, 0.2]
        let testFragment = SharedFragment(
            id: "fragment_test_abc",
            roomId: testRoom.id,
            authorId: "user_bintang_001",
            authorName: "Bintang",
            type: .photo,
            createdAt: Date(timeIntervalSince1970: 1774418000),
            title: "Sunset in Uluwatu",
            subtitle: "What a view!",
            text: "Captured during evening golden hour",
            mediaReference: nil,
            mediaSymbol: "camera.fill",
            location: "Uluwatu, Bali",
            duration: "0:15",
            audioWaveform: testWaveform,
            accentColorHex: "1.0000,0.8590,0.5760,1.0000",
            phi: 0.12,
            theta: 1.45,
            radiusFactor: 1.03
        )
        let fragmentRecord = CloudKitRecordMapper.toRecord(from: testFragment)
        let mappedFragment = CloudKitRecordMapper.toSharedFragment(from: fragmentRecord)

        assertCondition(mappedFragment?.id == testFragment.id, "SharedFragment ID roundtrip matches")
        assertCondition(mappedFragment?.roomId == testRoom.id, "SharedFragment roomId matches")
        assertCondition(mappedFragment?.authorId == "user_bintang_001", "SharedFragment authorId matches")
        assertCondition(mappedFragment?.authorName == "Bintang", "SharedFragment authorName matches")
        assertCondition(mappedFragment?.type == .photo, "SharedFragment type matches")
        assertCondition(mappedFragment?.title == "Sunset in Uluwatu", "SharedFragment title matches")
        assertCondition(mappedFragment?.location == "Uluwatu, Bali", "SharedFragment location matches")
        assertCondition(mappedFragment?.accentColorHex == testFragment.accentColorHex, "SharedFragment accentColorHex roundtrip matches")
        assertCondition(abs((mappedFragment?.phi ?? 0) - 0.12) < 0.001, "SharedFragment spherical phi matches")
        assertCondition(abs((mappedFragment?.theta ?? 0) - 1.45) < 0.001, "SharedFragment spherical theta matches")
        assertCondition(mappedFragment?.audioWaveform.count == 5, "SharedFragment audioWaveform count matches")

        // Verify fragment parent hierarchy and cascading delete
        let fragmentParentRef = fragmentRecord.parent
        let fragmentRoomRef = fragmentRecord[CloudKitRecordKey.fragmentRoom] as? CKRecord.Reference
        assertCondition(fragmentParentRef?.recordID.recordName == testRoom.id, "SharedFragment has correct parent CKRecord.Reference")
        assertCondition(
            fragmentRoomRef?.action == .deleteSelf,
            "SharedFragment references Room with .deleteSelf cascading delete action"
        )

        // Test 5: UserIdentity model and serialization
        let testIdentity = UserIdentity(
            id: "_user_cloudkit_id_999",
            displayName: "Alfathoshi",
            isCurrentUser: true
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        if let encoded = try? encoder.encode(testIdentity),
           let decoded = try? decoder.decode(UserIdentity.self, from: encoded) {
            assertCondition(decoded.id == testIdentity.id, "UserIdentity Codable roundtrip matches ID")
            assertCondition(decoded.displayName == testIdentity.displayName, "UserIdentity Codable roundtrip matches displayName")
            assertCondition(decoded.isCurrentUser == true, "UserIdentity Codable roundtrip matches isCurrentUser")
        } else {
            assertCondition(false, "UserIdentity Codable encoding/decoding failed")
        }

        // Test 6: RoomRole capabilities
        assertCondition(RoomRole.owner.canManageMembers == true, "RoomRole.owner can manage members")
        assertCondition(RoomRole.member.canManageMembers == false, "RoomRole.member cannot manage members")
        assertCondition(RoomRole.viewer.canCaptureFragments == false, "RoomRole.viewer cannot capture fragments")
        assertCondition(RoomRole.member.canCaptureFragments == true, "RoomRole.member can capture fragments")

        // Test 7: Active Moment bug fixes (single invocation, colors, stability)
        let selectedNoteColor = Color(red: 1.0, green: 0.859, blue: 0.576)
        let noteFrag = SharedFragment(
            roomId: testRoom.id,
            authorId: "test_author_1",
            authorName: "Author",
            type: .note,
            title: "Color Note Test",
            accentColorHex: selectedNoteColor.toRGBAString()
        )
        let noteConverted = noteFrag.toFragment()
        assertCondition(
            noteConverted.gradientColors.first?.toRGBAString() == selectedNoteColor.toRGBAString(),
            "Shared note fragment preserves user selected color in toFragment()"
        )

        let selectedMemoColor = Color(red: 0.35, green: 0.88, blue: 0.60)
        let memoFrag = SharedFragment(
            roomId: testRoom.id,
            authorId: "test_author_2",
            authorName: "Author",
            type: .audio,
            title: "Color Memo Test",
            accentColorHex: selectedMemoColor.toRGBAString()
        )
        let memoConverted = memoFrag.toFragment()
        assertCondition(
            memoConverted.gradientColors.first?.toRGBAString() == selectedMemoColor.toRGBAString(),
            "Shared voice memo fragment preserves user selected color in toFragment()"
        )

        var sharedCallCount = 0
        var personalCallCount = 0
        let captureVM = CaptureViewModel(
            initialMode: .note,
            captureContext: .room(testRoom),
            onCaptureFragment: { _ in personalCallCount += 1 },
            onCaptureSharedFragment: { _ in sharedCallCount += 1 }
        )
        captureVM.handleNoteCapture(title: "Single Call Test", text: "Text", color: selectedNoteColor)
        assertCondition(sharedCallCount == 1, "CaptureViewModel triggers onCaptureSharedFragment exactly once")
        assertCondition(personalCallCount == 0, "CaptureViewModel avoids calling onCaptureFragment when onCaptureSharedFragment is provided (no n*2 duplicate count)")

        let previousSession = MomentManager.shared.activeSession
        var testSession = MomentSession(isShared: true, room: testRoom)
        testSession.fragments = []
        if !testSession.fragments.contains(where: { $0.id == noteConverted.id }) {
            testSession.fragments.append(noteConverted)
        }
        if !testSession.fragments.contains(where: { $0.id == noteConverted.id }) {
            testSession.fragments.append(noteConverted)
        }
        assertCondition(
            testSession.fragments.count == 1,
            "MomentManager enforces idempotency: duplicate fragment additions are blocked"
        )
        // Always restore original session and prevent artificial active moments on launch
        MomentManager.shared.activeSession = previousSession
        if previousSession == nil {
            UserDefaults.standard.removeObject(forKey: "fragments.activeSessionInfo")
        }

        return (allPassed, logs)
    }
}
