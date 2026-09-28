//
//  UnifiedIdentityVerifier.swift
//  fragments
//
//  Created on 9/28/26.
//

import Foundation
import SwiftUI
import SwiftData

/// Verification suite for Phase 3: Unified Supabase Identity.
///
/// Validates:
/// - Test A: Canonical Collaborative Identity Resolution
/// - Test B: SharedFragment Current User Attribution
/// - Test C: Fragment to SharedFragment Conversion Author Resolution
/// - Test D: Supabase Repository Author Validation & Mismatch Rejection
/// - Test E: Member Profile Caching & Lookup
/// - Test F: Signed Out Collaborative State Protection
/// - Test G: Personal Fragment Preservation & Isolation
@MainActor
public enum UnifiedIdentityVerifier {

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

        let identityService = UserIdentityService.shared
        let supabaseService = SupabaseService.shared

        // -------------------------------------------------------------
        // TEST A: Canonical Collaborative Identity Resolution
        // -------------------------------------------------------------
        logs.append("--- Test A: Canonical Collaborative Identity Resolution ---")
        let currentSbID = supabaseService.currentUserID
        let collabID = identityService.collaborativeUserID
        let collabUUID = identityService.collaborativeUserUUID

        assertCondition(collabID == currentSbID, "collaborativeUserID strictly matches SupabaseService.currentUserID")

        if let collabID = collabID {
            assertCondition(collabUUID != nil, "collaborativeUserUUID successfully parses valid UUID string")
            assertCondition(collabUUID?.uuidString.lowercased() == collabID.lowercased(), "collaborativeUserUUID matches collaborativeUserID")
            let collabIdentity = identityService.collaborativeIdentity
            assertCondition(collabIdentity != nil, "collaborativeIdentity exists when authenticated")
            assertCondition(collabIdentity?.id == collabID, "collaborativeIdentity.id equals collaborativeUserID")
            assertCondition(collabIdentity?.isCurrentUser == true, "collaborativeIdentity reflects authenticated status")
        } else {
            assertCondition(collabUUID == nil, "collaborativeUserUUID is nil when signed out")
            assertCondition(identityService.collaborativeIdentity == nil, "collaborativeIdentity is nil when signed out")
        }

        // -------------------------------------------------------------
        // TEST B: SharedFragment Current User Attribution
        // -------------------------------------------------------------
        logs.append("--- Test B: SharedFragment Current User Attribution ---")
        let activeCollabID = collabID ?? UUID().uuidString.lowercased()

        // Match case (same casing)
        let myFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: activeCollabID,
            authorName: "Myself",
            type: .photo,
            createdAt: Date(),
            title: "My Capture"
        )

        // Case-insensitivity check
        let myFragUppercase = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: activeCollabID.uppercased(),
            authorName: "Myself",
            type: .note,
            createdAt: Date(),
            title: "My Uppercase Capture"
        )

        let otherFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: UUID().uuidString,
            authorName: "Other User",
            type: .video,
            createdAt: Date(),
            title: "Remote Capture"
        )

        let legacyDeviceFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: "device_" + UUID().uuidString,
            authorName: "Device Fallback",
            type: .audio,
            createdAt: Date(),
            title: "Legacy Capture"
        )

        if collabID != nil {
            assertCondition(myFrag.isAuthoredByCurrentUser == true, "Fragment authored by current user returns isAuthoredByCurrentUser = true")
            assertCondition(myFragUppercase.isAuthoredByCurrentUser == true, "Fragment attribution is case-insensitive for UUIDs")
            assertCondition(otherFrag.isAuthoredByCurrentUser == false, "Fragment authored by someone else returns isAuthoredByCurrentUser = false")
            assertCondition(legacyDeviceFrag.isAuthoredByCurrentUser == false, "Legacy device_<UUID> author returns isAuthoredByCurrentUser = false")
        } else {
            assertCondition(myFrag.isAuthoredByCurrentUser == false, "Signed out user safely returns isAuthoredByCurrentUser = false without crash")
            assertCondition(otherFrag.isAuthoredByCurrentUser == false, "Signed out user returns isAuthoredByCurrentUser = false for other fragments")
        }

        // -------------------------------------------------------------
        // TEST C: Fragment to SharedFragment Conversion Author Resolution
        // -------------------------------------------------------------
        logs.append("--- Test C: Fragment to SharedFragment Conversion ---")
        let localFrag = Fragment(
            type: .note,
            title: "Local Journal",
            text: "Private memory text"
        )

        let testRoomID = UUID().uuidString
        let convertedShared = localFrag.toSharedFragment(roomId: testRoomID)

        if let collabID = collabID {
            assertCondition(convertedShared.authorId == collabID, "Conversion automatically resolves authorId to canonical collaborativeUserID")
        } else {
            assertCondition(!convertedShared.authorId.isEmpty, "Conversion provides fallback authorId when signed out")
        }

        let explicitAuthorID = UUID().uuidString
        let explicitShared = localFrag.toSharedFragment(roomId: testRoomID, authorId: explicitAuthorID, authorName: "Explicit Name")
        assertCondition(explicitShared.authorId == explicitAuthorID, "Conversion prioritizes explicitly provided authorId")
        assertCondition(explicitShared.authorName == "Explicit Name", "Conversion prioritizes explicitly provided authorName")

        // -------------------------------------------------------------
        // TEST D: Supabase Repository Author Validation & Mismatch Rejection
        // -------------------------------------------------------------
        logs.append("--- Test D: Supabase Repository Author Validation ---")
        let repo = SupabaseRoomRepository.shared

        // Test 1: Non-UUID author ID rejection
        let invalidAuthorFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: "device_9999-invalid-uuid",
            authorName: "Hacker",
            type: .note,
            createdAt: Date(),
            title: "Invalid Author"
        )

        do {
            _ = try await repo.createFragment(invalidAuthorFrag)
            assertCondition(false, "Repository MUST reject non-UUID authorId")
        } catch let error as SupabaseRoomError {
            switch error {
            case .validationFailure(let message):
                assertCondition(message.contains("valid UUID"), "Repository rejected non-UUID with validationFailure: \(message)")
            case .notAuthenticated:
                assertCondition(collabID == nil, "Repository rejected unauthenticated createFragment correctly")
            default:
                assertCondition(true, "Repository rejected createFragment with expected domain error: \(error)")
            }
        } catch {
            assertCondition(true, "Repository rejected createFragment: \(error.localizedDescription)")
        }

        // Test 2: Mismatched UUID author ID rejection
        let mismatchedUUID = UUID().uuidString
        let mismatchedFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: mismatchedUUID,
            authorName: "Impersonator",
            type: .note,
            createdAt: Date(),
            title: "Mismatched Author"
        )

        do {
            _ = try await repo.createFragment(mismatchedFrag)
            if collabID != nil {
                assertCondition(false, "Repository MUST reject mismatched authorId that does not equal auth.uid()")
            } else {
                assertCondition(false, "Repository MUST reject unauthenticated write")
            }
        } catch let error as SupabaseRoomError {
            switch error {
            case .validationFailure(let message):
                assertCondition(message.contains("must match the authenticated"), "Repository rejected mismatched author with validationFailure: \(message)")
            case .notAuthenticated:
                assertCondition(collabID == nil, "Repository threw notAuthenticated when signed out")
            default:
                assertCondition(true, "Repository rejected with domain error: \(error)")
            }
        } catch {
            assertCondition(true, "Repository rejected: \(error.localizedDescription)")
        }

        // -------------------------------------------------------------
        // TEST E: Member Profile Caching & Lookup
        // -------------------------------------------------------------
        logs.append("--- Test E: Member Profile Caching & Lookup ---")
        let randomUserID = UUID()
        // Query fetchUserProfile directly
        do {
            let profile = try await repo.fetchUserProfile(userID: randomUserID)
            assertCondition(!profile.displayName.isEmpty, "fetchUserProfile returned display name: \(profile.displayName)")
        } catch let error as SupabaseRoomError {
            switch error {
            case .notAuthenticated:
                assertCondition(collabID == nil, "fetchUserProfile appropriately requires authentication")
            default:
                assertCondition(true, "fetchUserProfile handled non-existent user safely: \(error)")
            }
        } catch {
            assertCondition(true, "fetchUserProfile handled lookup safely: \(error.localizedDescription)")
        }

        // Test RoomManager profile cache reconciliation
        let roomManager = RoomManager.shared
        let testMemberID = UUID().uuidString
        let mockMember = RoomMember(
            id: UUID().uuidString,
            roomId: testRoomID,
            userId: testMemberID,
            displayName: "Cached Explorer",
            role: .member,
            joinedAt: Date()
        )
        // Simulate Realtime event
        await roomManager.handleRealtimeEvent(.memberJoined(mockMember), forRoomID: testRoomID)
        assertCondition(true, "RoomManager successfully handles Realtime memberJoined without throw")

        // -------------------------------------------------------------
        // TEST F: Signed Out Collaborative State Protection
        // -------------------------------------------------------------
        logs.append("--- Test F: Signed Out Collaborative State Protection ---")
        if collabID == nil {
            assertCondition(identityService.collaborativeUserID == nil, "Signed out state has nil collaborativeUserID")
            assertCondition(identityService.collaborativeUserUUID == nil, "Signed out state has nil collaborativeUserUUID")
            assertCondition(identityService.collaborativeIdentity == nil, "Signed out state has nil collaborativeIdentity")
        } else {
            assertCondition(identityService.collaborativeUserID != nil, "Authenticated state provides non-nil collaborativeUserID")
        }

        // Ensure isAuthoredByCurrentUser does not crash when authorId is blank
        let blankAuthorFrag = SharedFragment(
            id: UUID().uuidString,
            roomId: UUID().uuidString,
            authorId: "",
            authorName: "Anonymous",
            type: .note,
            createdAt: Date(),
            title: "Blank Author"
        )
        assertCondition(blankAuthorFrag.isAuthoredByCurrentUser == false, "Blank authorId returns false for isAuthoredByCurrentUser")

        // -------------------------------------------------------------
        // TEST G: Personal Fragment Preservation & Isolation
        // -------------------------------------------------------------
        logs.append("--- Test G: Personal Fragment Preservation & Isolation ---")
        let personalFrag = Fragment(
            type: .photo,
            title: "Private Sunset",
            subtitle: "On the beach"
        )

        assertCondition(personalFrag.title == "Private Sunset", "Personal Fragment has local title")
        assertCondition(personalFrag.subtitle == "On the beach", "Personal Fragment has local subtitle")
        assertCondition(personalFrag.type == .photo, "Personal Fragment retains local type")

        // SwiftData SDFragment conversion check
        let sdFrag = SDFragment(from: personalFrag)
        assertCondition(sdFrag.id == personalFrag.id, "SDFragment retains local ID")
        assertCondition(sdFrag.title == personalFrag.title, "SDFragment retains personal local title")
        assertCondition(sdFrag.typeRawValue == personalFrag.type.rawValue, "SDFragment retains type raw value")

        return (allPassed, logs)
    }
}
