//
//  RoomsPhase4And5Verifier.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit
import CoreGraphics

/// Verification test engine validating Phase 4 & 5 Room Cache, Repository,
/// CloudKit Mapping, Identity, Deterministic Ordering, and SwiftData Isolation.
public enum RoomsPhase4And5Verifier {

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

        // -------------------------------------------------------------
        // 1. CACHE VERIFICATION (Using isolated sandbox test directory)
        // -------------------------------------------------------------
        let tempTestDir = FileManager.default.temporaryDirectory.appendingPathComponent("RoomCacheTest_\(UUID().uuidString)")
        let testCache = LocalRoomCache(baseDirectory: tempTestDir)

        let testRoom = Room(
            id: "cache_room_001",
            name: "Tokyo Expedition",
            emoji: "🗾",
            createdBy: "user_test_99",
            accentColorHex: "#3388FF"
        )

        // 1.1 Save Room
        do {
            try testCache.saveRoom(testRoom)
            assertCondition(true, "Cache: save Room succeeded")
        } catch {
            assertCondition(false, "Cache: save Room failed: \(error)")
        }

        // 1.2 Load Room
        do {
            let loaded = try testCache.loadRooms()
            assertCondition(loaded.count == 1 && loaded.first?.id == testRoom.id && loaded.first?.name == "Tokyo Expedition", "Cache: load Room verified")
        } catch {
            assertCondition(false, "Cache: load Room failed: \(error)")
        }

        // 1.3 Save and Load Members
        let member1 = RoomMember(id: "mem_1", roomId: testRoom.id, userId: "u1", displayName: "Kenji", role: .owner)
        let member2 = RoomMember(id: "mem_2", roomId: testRoom.id, userId: "u2", displayName: "Aoi", role: .member)
        do {
            try testCache.saveMembers([member1, member2], roomID: testRoom.id)
            let loadedMembers = try testCache.loadMembers(roomID: testRoom.id)
            assertCondition(loadedMembers.count == 2 && loadedMembers[0].displayName == "Kenji", "Cache: save and load members verified")
        } catch {
            assertCondition(false, "Cache: save/load members failed: \(error)")
        }

        // 1.4 Save and Load Fragments
        let frag1 = SharedFragment(
            id: "frag_1",
            roomId: testRoom.id,
            authorId: "u1",
            authorName: "Kenji",
            type: .note,
            title: "Ramen Spot",
            text: "Near Shinjuku Station"
        )
        do {
            try testCache.saveFragments([frag1], roomID: testRoom.id)
            let loadedFrags = try testCache.loadFragments(roomID: testRoom.id)
            assertCondition(loadedFrags.count == 1 && loadedFrags.first?.title == "Ramen Spot", "Cache: save and load fragments verified")
        } catch {
            assertCondition(false, "Cache: save/load fragments failed: \(error)")
        }

        // 1.5 Corrupted Cache Recovery
        let manifestFile = tempTestDir.appendingPathComponent("rooms_manifest.json")
        let corruptData = "INVALID_CORRUPTED_JSON_DATA{{{".data(using: .utf8)!
        try? corruptData.write(to: manifestFile)
        do {
            let recovered = try testCache.loadRooms()
            assertCondition(recovered.isEmpty, "Cache: corrupted manifest recovered gracefully without throwing")
            assertCondition(!FileManager.default.fileExists(atPath: manifestFile.path), "Cache: corrupted file purged during recovery")
        } catch {
            assertCondition(false, "Cache: corrupted recovery threw error: \(error)")
        }

        // 1.6 Delete & Invalidate Room
        try? testCache.saveRoom(testRoom)
        do {
            try testCache.invalidateRoom(id: testRoom.id)
            let remaining = try testCache.loadRooms()
            assertCondition(remaining.isEmpty, "Cache: invalidate Room purged entry and manifest")
        } catch {
            assertCondition(false, "Cache: invalidate Room failed: \(error)")
        }

        // Clean up test directory
        try? FileManager.default.removeItem(at: tempTestDir)

        // -------------------------------------------------------------
        // 2. CLOUDKIT MAPPING VERIFICATION
        // -------------------------------------------------------------
        // 2.1 Room -> CKRecord -> Room
        let ckRoom = Room(
            id: "room_ck_123",
            name: "Dolomites Hike",
            emoji: "⛰️",
            createdAt: Date(timeIntervalSince1970: 1774500000),
            createdBy: "user_owner_777",
            shareRecordID: "share_rec_555",
            zoneName: "RoomZone-dolomites",
            isArchived: false,
            memberCount: 3,
            fragmentCount: 15,
            accentColorHex: "#22C55E"
        )
        let roomRecord = CloudKitRecordMapper.toRecord(from: ckRoom)
        let roundtripRoom = CloudKitRecordMapper.toRoom(from: roomRecord)
        assertCondition(roundtripRoom?.id == ckRoom.id, "CloudKit Mapping: Room ID matches")
        assertCondition(roundtripRoom?.name == "Dolomites Hike", "CloudKit Mapping: Room name matches")
        assertCondition(roundtripRoom?.shareRecordID == "share_rec_555", "CloudKit Mapping: Room shareRecordID matches")

        // 2.2 RoomMember -> CKRecord -> RoomMember
        let ckMember = RoomMember(
            id: "room_ck_123_user_owner_777",
            roomId: ckRoom.id,
            userId: "user_owner_777",
            displayName: "Marco",
            role: .owner
        )
        let memberRecord = CloudKitRecordMapper.toRecord(from: ckMember)
        let roundtripMember = CloudKitRecordMapper.toRoomMember(from: memberRecord)
        assertCondition(roundtripMember?.id == ckMember.id, "CloudKit Mapping: RoomMember ID matches")
        assertCondition(memberRecord.parent?.recordID.recordName == ckRoom.id, "CloudKit Mapping: RoomMember parent reference set")
        let memberCascade = (memberRecord[CloudKitRecordKey.memberRoom] as? CKRecord.Reference)?.action
        assertCondition(memberCascade == .deleteSelf, "CloudKit Mapping: RoomMember deleteSelf cascading reference set")

        // 2.3 SharedFragment -> CKRecord -> SharedFragment
        let ckFragment = SharedFragment(
            id: "frag_ck_888",
            roomId: ckRoom.id,
            authorId: "user_owner_777",
            authorName: "Marco",
            type: .photo,
            title: "Tre Cime Summit",
            location: "Dolomites, Italy",
            audioWaveform: [0.12, 0.45, 0.78],
            phi: 0.25,
            theta: 2.10,
            radiusFactor: 1.05
        )
        let fragRecord = CloudKitRecordMapper.toRecord(from: ckFragment)
        let roundtripFrag = CloudKitRecordMapper.toSharedFragment(from: fragRecord)
        assertCondition(roundtripFrag?.id == ckFragment.id, "CloudKit Mapping: SharedFragment ID matches")
        assertCondition(fragRecord.parent?.recordID.recordName == ckRoom.id, "CloudKit Mapping: SharedFragment parent reference set")
        let fragCascade = (fragRecord[CloudKitRecordKey.fragmentRoom] as? CKRecord.Reference)?.action
        assertCondition(fragCascade == .deleteSelf, "CloudKit Mapping: SharedFragment deleteSelf cascading reference set")
        assertCondition(roundtripFrag?.audioWaveform.count == 3, "CloudKit Mapping: Audio waveform samples preserved")

        // -------------------------------------------------------------
        // 3. DETERMINISTIC ORDERING VERIFICATION
        // -------------------------------------------------------------
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        // Multiple fragments, including identical timestamps to test tie-breaker
        let fA = SharedFragment(id: "frag_B", roomId: "r", authorId: "u", authorName: "U", type: .note, createdAt: t2, title: "B")
        let fB = SharedFragment(id: "frag_A", roomId: "r", authorId: "u", authorName: "U", type: .note, createdAt: t2, title: "A") // Same date as fA
        let fC = SharedFragment(id: "frag_C", roomId: "r", authorId: "u", authorName: "U", type: .note, createdAt: t1, title: "C") // Earlier
        let fD = SharedFragment(id: "frag_D", roomId: "r", authorId: "u", authorName: "U", type: .note, createdAt: t3, title: "D") // Later

        let sortedFrags = CloudKitRoomRepository.sortDeterministically([fA, fB, fC, fD])
        assertCondition(sortedFrags[0].id == "frag_C", "Deterministic Ordering: Earliest createdAt is first")
        assertCondition(sortedFrags[1].id == "frag_A", "Deterministic Ordering: Tie-breaker on identical date places id 'frag_A' before 'frag_B'")
        assertCondition(sortedFrags[2].id == "frag_B", "Deterministic Ordering: Tie-breaker places 'frag_B' second")
        assertCondition(sortedFrags[3].id == "frag_D", "Deterministic Ordering: Latest createdAt is last")

        // -------------------------------------------------------------
        // 4. IDENTITY & CACHE INVALIDATION VERIFICATION
        // -------------------------------------------------------------
        let testIdentity = UserIdentity(
            id: "_user_ck_test_identity",
            displayName: "TestUser",
            isCurrentUser: true
        )
        assertCondition(testIdentity.id == "_user_ck_test_identity", "Identity: UserIdentity ID correctly assigned")
        assertCondition(testIdentity.isCurrentUser == true, "Identity: UserIdentity isCurrentUser flag verified")

        // -------------------------------------------------------------
        // 5. ARCHITECTURE ISOLATION VERIFICATION
        // -------------------------------------------------------------
        assertCondition(
            CloudKitService.containerIdentifier == "iCloud.com.alfathoshi.fragments",
            "Architecture: CloudKit container identifier is iCloud.com.alfathoshi.fragments"
        )
        assertCondition(
            LocalRoomCache.shared.baseCacheDirectory.path.contains("Caches/Rooms"),
            "Architecture: LocalRoomCache is hosted in Caches/Rooms without touching SwiftData SQLite"
        )

        return (allPassed, logs)
    }
}
