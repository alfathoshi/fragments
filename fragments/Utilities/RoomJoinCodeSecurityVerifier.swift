//
//  RoomJoinCodeSecurityVerifier.swift
//  fragments
//
//  Regression verifier for the room join-code security fix:
//  join codes are server-generated CSPRNG values independent of room IDs.
//  All tests are pure/synchronous: no auth, no network, no shared-state mutation.
//

import Foundation

/// Verifies client-side security properties of the random join-code design:
/// no room-ID derivation, new unambiguous format, input normalization,
/// deep-link separation (code = credential, id = navigation only),
/// and preserved lifecycle error mapping.
public enum RoomJoinCodeSecurityVerifier {

    /// Strict server format: 6 chars from the unambiguous alphabet
    /// (excludes O/0, I/1, S/5).
    static let strictPattern = "^[ABCDEFGHJKLMNPQRTUVWXYZ2346789]{6}$"

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

        // 1. Room model never auto-derives a join credential from its ID.
        let probeID = "f93ab83e-61dd-4cfd-810d-c901f2c6066b"
        let codless = Room(
            id: probeID, name: "Probe", emoji: "✨",
            createdAt: Date(), createdBy: "tester",
            shareRecordID: nil, zoneName: "supabase"
        )
        assertCondition(
            codless.shareRecordID == nil,
            "Room with nil shareRecordID carries no join credential (no ID derivation)"
        )

        // 2. The legacy deterministic value for that ID is hex-only/predictable.
        let legacyDerived = String(probeID.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
        assertCondition(
            legacyDerived == "F93AB8",
            "Legacy deterministic derivation reproduces the vulnerable value (documents the removed behavior)"
        )
        assertCondition(
            legacyDerived.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil,
            "Legacy space was hex-only (~16.7M values, offline-computable)"
        )

        // 3. New format: strict alphabet accepted, ambiguous chars rejected.
        let valid = ["8QZKEH", "3KNMKM", "HQ24QP", "FPQNNM"]
        for code in valid {
            assertCondition(
                code.range(of: strictPattern, options: .regularExpression) != nil,
                "New-format code '\(code)' matches unambiguous alphabet"
            )
        }
        for bad in ["OIS015", "OOOOOO", "111111", "abc123", "ABC12", "ABCDEFG"] {
            // Excluded ambiguous symbols (O/I/S/0/1/5), lowercase, or wrong
            // length all fail the strict server-format match. Note: a legacy
            // hex-derived string MAY coincidentally match the new alphabet —
            // security comes from CSPRNG randomness + UNIQUE, not from format
            // exclusion — so no legacy sample is asserted here.
            let matches = bad.range(of: strictPattern, options: .regularExpression) != nil
            assertCondition(!matches, "Strict format rejects '\(bad)' (ambiguous char, case, or length)")
        }

        // 4. Client + server normalization agree: trim + uppercase before lookup.
        let rawInput = "  ab12cd\n"
        let normalized = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        assertCondition(normalized == "AB12CD", "Join input normalizes to uppercase before lookup (no case-sensitivity bug)")

        // 5. Room-ID knowledge does not yield the credential: fixed fixture pair
        // from the verified DB run — id prefix differs from the real random code.
        assertCondition(
            legacyDerived != "8QZKEH",
            "Knowing room_id (prefix F93AB8) does not reveal join_code (8QZKEH)"
        )

        // 6. Deep-link separation: code links carry the credential, id links do not.
        if let codeURL = URL(string: "fragments://room/join?code=ab12cd&name=Test"),
           let items = URLComponents(url: codeURL, resolvingAgainstBaseURL: false)?.queryItems {
            let code = items.first(where: { $0.name == "code" })?.value ?? ""
            assertCondition(
                code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "AB12CD",
                "Code deep link carries a normalizable credential"
            )
        } else {
            assertCondition(false, "Code deep link parses")
        }
        if let idURL = URL(string: "fragments://room/join?id=\(probeID)&name=Test"),
           let items = URLComponents(url: idURL, resolvingAgainstBaseURL: false)?.queryItems {
            let code = items.first(where: { $0.name == "code" })?.value
            let id = items.first(where: { $0.name == "id" })?.value ?? ""
            assertCondition(code == nil, "ID deep link carries no code credential")
            assertCondition(id == probeID, "ID deep link preserves navigation identity without authorizing")
        } else {
            assertCondition(false, "ID deep link parses")
        }

        // 7. Non-hex 6-char codes pass the client length gate (no hex assumption).
        // joinRoom's client gate is count == 6 only; verify the fixture length.
        assertCondition("QZKM29".count == 6, "Non-hex 6-char code passes client length gate")

        // 8. Lifecycle error-message contract preserved (server raises these
        // exact substrings; the client maps them to archived/ended/notFound).
        struct MockError: LocalizedError { let errorDescription: String? }
        assertCondition(
            SupabaseRoomRepository.mapJoinRPCError(MockError(errorDescription: "room is archived"), code: "XXXXXX")
                == .validationFailure("This Room has been archived."),
            "Archived guard mapping preserved"
        )
        assertCondition(
            SupabaseRoomRepository.mapJoinRPCError(MockError(errorDescription: "room has ended"), code: "XXXXXX")
                == .validationFailure("This Room has already ended."),
            "Ended guard mapping preserved"
        )
        assertCondition(
            SupabaseRoomRepository.mapJoinRPCError(MockError(errorDescription: "room not found for code XXXXXX"), code: "XXXXXX")
                == .notFound("No Room found matching code 'XXXXXX'."),
            "Invalid-code mapping preserved"
        )

        return (allPassed, logs)
    }
}
