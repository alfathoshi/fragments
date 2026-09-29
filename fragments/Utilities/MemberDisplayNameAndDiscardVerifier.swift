//
//  MemberDisplayNameAndDiscardVerifier.swift
//  fragments
//
//  DEBUG self-contained regression tests for:
//  Bug 1 — member list showing DB-default "Fragment Explorer"/"Member" instead of real names.
//  Bug 2 — discarded shared moments briefly flashing in MomentsView.
//

import Foundation

/// Pure, backend-free regression tests. Safe to run in DEBUG at launch.
public enum MemberDisplayNameAndDiscardVerifier {

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

        // MARK: - Bug 1: placeholder detection

        assertCondition(
            RoomMember.isUnresolvedDisplayName("Fragment Explorer"),
            "Bug1: 'Fragment Explorer' is treated as unresolved placeholder"
        )
        assertCondition(
            RoomMember.isUnresolvedDisplayName("fragment explorer"),
            "Bug1: placeholder match is case-insensitive"
        )
        assertCondition(
            RoomMember.isUnresolvedDisplayName("Member"),
            "Bug1: 'Member' is treated as unresolved placeholder"
        )
        assertCondition(
            RoomMember.isUnresolvedDisplayName(""),
            "Bug1: empty name is unresolved"
        )
        assertCondition(
            !RoomMember.isUnresolvedDisplayName("Aoi"),
            "Bug1: real name 'Aoi' is resolved"
        )

        // MARK: - Bug 1: decode normalization (DB default must never reach UI verbatim)

        let placeholderJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "member",
            "joined_at": "2026-09-27T12:00:00Z",
            "profiles": { "display_name": "Fragment Explorer", "avatar_storage_path": null }
        }
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: placeholderJSON)
            let domain = decoded.toDomain()
            assertCondition(
                domain.displayName != "Fragment Explorer",
                "Bug1: DB default 'Fragment Explorer' is normalized before UI (got '\(domain.displayName)')"
            )
            assertCondition(
                RoomMember.isUnresolvedDisplayName(domain.displayName),
                "Bug1: normalized placeholder still flags as unresolved for repair"
            )
        } catch {
            assertCondition(false, "Bug1: placeholder member JSON decodes: \(error)")
        }

        let realNameJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "owner",
            "joined_at": "2026-09-27T12:00:00Z",
            "profiles": { "display_name": "Aoi", "avatar_storage_path": null }
        }
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: realNameJSON)
            assertCondition(
                decoded.toDomain().displayName == "Aoi",
                "Bug1: real profile name is preserved verbatim"
            )
        } catch {
            assertCondition(false, "Bug1: real-name member JSON decodes: \(error)")
        }

        // MARK: - Bug 1: central resolution helper

        assertCondition(
            SupabaseRoomRepository.resolvedMemberDisplayName(profileName: "Fragment Explorer", fallbackLocalName: "Aoi") == "Aoi",
            "Bug1: resolver prefers local name over DB placeholder"
        )
        assertCondition(
            SupabaseRoomRepository.resolvedMemberDisplayName(profileName: "Kenji", fallbackLocalName: "Aoi") == "Kenji",
            "Bug1: resolver prefers real profile name over local fallback"
        )
        assertCondition(
            SupabaseRoomRepository.resolvedMemberDisplayName(profileName: nil, fallbackLocalName: nil) == "Unknown",
            "Bug1: resolver maps total absence to 'Unknown' (no username set)"
        )
        assertCondition(
            SupabaseRoomRepository.resolvedMemberDisplayName(profileName: "Member", fallbackLocalName: "Unknown") == "Unknown",
            "Bug1: resolver never promotes one placeholder to another"
        )

        // Users without a username must read as "Unknown" end-to-end.
        let realtimeJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "member",
            "joined_at": "2026-09-27T12:00:00Z"
        }
        """.data(using: .utf8)!

        do {
            let payload = try JSONDecoder().decode(RealtimeRoomMemberPayload.self, from: realtimeJSON)
            let member = payload.toDomain()
            assertCondition(
                member.displayName == "Unknown",
                "Bug1: realtime member without profile reads as 'Unknown'"
            )
            assertCondition(
                RoomMember.isUnresolvedDisplayName(member.displayName),
                "Bug1: 'Unknown' still flags as unresolved for later repair"
            )
        } catch {
            assertCondition(false, "Bug1: realtime member JSON decodes: \(error)")
        }

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: placeholderJSON)
            assertCondition(
                decoded.toDomain().displayName == "Unknown",
                "Bug1: DB default decodes to 'Unknown', never the schema default"
            )
        } catch {
            assertCondition(false, "Bug1: placeholder member JSON decodes (unknown check): \(error)")
        }

        // MARK: - Bug 2: discard must never synthesize a visible moment

        let liveRoom = Room(
            id: "aaaaaaaa-1111-2222-3333-444444444444",
            name: "Live Session",
            createdAt: Date(),
            createdBy: "owner-1",
            shareRecordID: "ABC123",
            zoneName: "supabase",
            isEnded: false,
            isArchived: false
        )
        let endedRoom = Room(
            id: "bbbbbbbb-1111-2222-3333-444444444444",
            name: "Ended Session",
            createdAt: Date(),
            createdBy: "owner-1",
            shareRecordID: "DEF456",
            zoneName: "supabase",
            isEnded: true,
            isArchived: false,
            finalTitle: "Ended Session",
            finalCategory: "Friends"
        )

        // Active live session is excluded even without suppression.
        let activeVisible = MomentsCatalog.visibleMoments(
            savedCollections: [],
            rooms: [liveRoom],
            activeRoomID: liveRoom.id
        )
        assertCondition(
            activeVisible.isEmpty,
            "Bug2: live active room is excluded from Moments while recording"
        )

        // Discarded room: activeSession already nil, but suppression is now set
        // synchronously in cancelSession — an ended/discarded room must not appear.
        let discardedVisible = MomentsCatalog.visibleMoments(
            savedCollections: [],
            rooms: [endedRoom],
            activeRoomID: nil,
            suppressedRoomIDs: [endedRoom.id]
        )
        assertCondition(
            discardedVisible.isEmpty,
            "Bug2: synchronously suppressed room never flashes in Moments"
        )

        // Valid save/end behavior preserved: ended, non-suppressed rooms still appear.
        let savedVisible = MomentsCatalog.visibleMoments(
            savedCollections: [],
            rooms: [endedRoom],
            activeRoomID: nil,
            suppressedRoomIDs: []
        )
        assertCondition(
            savedVisible.count == 1 && savedVisible.first?.roomID == endedRoom.id,
            "Bug2: ended non-discarded room still appears as saved Moment"
        )

        // Live, non-active rooms are never personal Moments until explicitly ended.
        let liveIdleVisible = MomentsCatalog.visibleMoments(
            savedCollections: [],
            rooms: [liveRoom],
            activeRoomID: nil
        )
        assertCondition(
            liveIdleVisible.isEmpty,
            "Bug2: live room without active session is not a personal Moment"
        )

        // MARK: - Media hydration contract (receiver retry, P0-1 / P0-2)

        assertCondition(
            MomentManager.mediaHydrationDelays == [0.5, 1.0, 2.0],
            "Media: hydration uses bounded backoff 0.5s/1s/2s (4 attempts total, never indefinite)"
        )
        assertCondition(
            MomentManager.mediaHydrationDelays.count + 1 == 4,
            "Media: hydration attempt budget is exactly initial + 3 retries"
        )

        // MARK: - Sphere position stability (id-keyed, min-distance)

        assertCondition(
            FragmentSphere.overlapEpsilon == 0.06,
            "Sphere: overlap epsilon is a shared configurable constant"
        )

        let siblingA = Fragment(type: .photo, title: "A", phi: 0.1, theta: 0.4)
        let siblingB = Fragment(type: .photo, title: "B", phi: 0.12, theta: 0.42)
        // Stable coordinates far from siblings are preserved verbatim.
        let kept = Fragment.resolveCoordinates(
            phi: 1.0, theta: 2.0, radiusFactor: 1.0,
            selfID: UUID(), existing: [siblingA, siblingB],
            epsilon: FragmentSphere.overlapEpsilon
        )
        assertCondition(
            kept.phi == 1.0 && kept.theta == 2.0,
            "Sphere: non-colliding coordinates are preserved (no regen on updates)"
        )
        // The shared default spot resamples away when siblings exist.
        let resampled = Fragment.resolveCoordinates(
            phi: Fragment.defaultSpotPhi, theta: Fragment.defaultSpotTheta, radiusFactor: 1.02,
            selfID: UUID(), existing: [siblingA, siblingB],
            epsilon: FragmentSphere.overlapEpsilon
        )
        let movedAway = abs(resampled.phi - siblingA.phi) >= FragmentSphere.overlapEpsilon
            || abs(resampled.theta - siblingA.theta) >= FragmentSphere.overlapEpsilon
        assertCondition(
            movedAway,
            "Sphere: default-spot fragment is resampled away from siblings"
        )
        // Colliding newcomer resamples; lone fragment keeps the default spot.
        let colliding = Fragment.resolveCoordinates(
            phi: 0.1, theta: 0.4, radiusFactor: 1.0,
            selfID: UUID(), existing: [siblingA],
            epsilon: FragmentSphere.overlapEpsilon
        )
        assertCondition(
            abs(colliding.phi - 0.1) >= FragmentSphere.overlapEpsilon
                || abs(colliding.theta - 0.4) >= FragmentSphere.overlapEpsilon,
            "Sphere: colliding newcomer is resampled (min-distance)"
        )
        let lone = Fragment.resolveCoordinates(
            phi: Fragment.defaultSpotPhi, theta: Fragment.defaultSpotTheta, radiusFactor: 1.02,
            selfID: UUID(), existing: [],
            epsilon: FragmentSphere.overlapEpsilon
        )
        assertCondition(
            lone.phi == Fragment.defaultSpotPhi && lone.theta == Fragment.defaultSpotTheta,
            "Sphere: first fragment keeps the default spot (no churn)"
        )
        // Id-derived fallback slots are deterministic per id.
        let slotID = UUID()
        let slot1 = FragmentSphere.stableScatterSlot(id: slotID, occupied: [(0.1, 0.4)])
        let slot2 = FragmentSphere.stableScatterSlot(id: slotID, occupied: [(0.1, 0.4)])
        assertCondition(
            slot1.phi == slot2.phi && slot1.theta == slot2.theta,
            "Sphere: fallback slot is deterministic for the same id"
        )
        assertCondition(
            abs(slot1.phi - 0.1) >= FragmentSphere.overlapEpsilon
                || abs(slot1.theta - 0.4) >= FragmentSphere.overlapEpsilon,
            "Sphere: fallback slot avoids occupied positions"
        )

        // MARK: - Username validation + member preference

        assertCondition(
            UsernameValidator.normalize("  Alfathoshi ") == "alfathoshi",
            "Username: normalization trims and lowercases"
        )
        assertCondition(
            UsernameValidator.isValid("alfathoshi"),
            "Username: valid name passes"
        )
        assertCondition(
            UsernameValidator.isValid("ab") == false,
            "Username: too-short name rejected"
        )
        assertCondition(
            UsernameValidator.isValid(String(repeating: "a", count: 21)) == false,
            "Username: too-long name rejected"
        )
        assertCondition(
            UsernameValidator.isValid("no spaces") == false
                && UsernameValidator.isValid("UPPER") == false
                && UsernameValidator.isValid("a!b") == false,
            "Username: spaces/uppercase/specials rejected (normalized form)"
        )
        assertCondition(
            UsernameValidator.isValid("a1_") && UsernameValidator.isValid("abc"),
            "Username: boundary lengths + underscore accepted"
        )

        let memberWithUsernameJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "room_id": "22222222-3333-4444-5555-666666666666",
            "user_id": "33333333-4444-5555-6666-777777777777",
            "role": "member",
            "joined_at": "2026-09-27T12:00:00Z",
            "profiles": {
                "username": "alfathoshi",
                "display_name": "Alfathoshi Signature",
                "avatar_storage_path": null
            }
        }
        """.data(using: .utf8)!

        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: memberWithUsernameJSON)
            assertCondition(
                decoded.toDomain().displayName == "alfathoshi",
                "Username: member list prefers unique username over display name"
            )
        } catch {
            assertCondition(false, "Username: member JSON with username decodes: \(error)")
        }

        // Legacy rows without the username key still decode (pre-migration).
        do {
            let decoded = try JSONDecoder().decode(DatabaseRoomMember.self, from: realNameJSON)
            assertCondition(
                decoded.toDomain().displayName == "Aoi",
                "Username: legacy member JSON without username still resolves display name"
            )
        } catch {
            assertCondition(false, "Username: legacy member JSON decodes: \(error)")
        }

        return (allPassed, logs)
    }
}
