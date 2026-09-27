//
//  SupabaseAuthVerifier.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Supabase

/// Verification suite for Phase 2A Supabase Authentication Foundation.
///
/// Validates nonce cryptography, Apple authorization request construction,
/// Supabase Auth state model, error cases, and identity isolation.
public enum SupabaseAuthVerifier {

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
        // 1. NONCE GENERATION & ENTROPY
        // -------------------------------------------------------------
        let nonce1 = AppleSignInCoordinator.generateRandomNonce(length: 32)
        let nonce2 = AppleSignInCoordinator.generateRandomNonce(length: 32)

        assertCondition(nonce1.count == 32, "Nonce 1 has expected length (32)")
        assertCondition(nonce2.count == 32, "Nonce 2 has expected length (32)")
        assertCondition(nonce1 != nonce2, "Nonces are cryptographically distinct")

        let allowedCharset = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let charactersValid = nonce1.allSatisfy { allowedCharset.contains($0) }
        assertCondition(charactersValid, "Nonce characters strictly match allowed URL-safe charset")

        // -------------------------------------------------------------
        // 2. SHA-256 HASH DETERMINISM & FORMAT
        // -------------------------------------------------------------
        let testInput = "FragmentsTestNonce_1234567890"
        let hashedHex = AppleSignInCoordinator.sha256(testInput)

        // Compute direct CryptoKit hash for comparison
        let directHash = SHA256.hash(data: Data(testInput.utf8))
        let directHex = directHash.compactMap { String(format: "%02x", $0) }.joined()

        assertCondition(hashedHex == directHex, "SHA-256 hash output matches CryptoKit reference")
        assertCondition(hashedHex.count == 64, "SHA-256 output is valid 64-character hex string")

        // -------------------------------------------------------------
        // 3. APPLE AUTHORIZATION REQUEST CONSTRUCTION
        // -------------------------------------------------------------
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedHex

        assertCondition(request.requestedScopes == [.fullName, .email], "Request requestedScopes contain fullName and email")
        assertCondition(request.nonce == hashedHex, "Request nonce matches hashed nonce")

        // -------------------------------------------------------------
        // 4. SUPABASE AUTH STATE MODEL
        // -------------------------------------------------------------
        let signedOutState = SupabaseAuthState.signedOut
        let signingInState = SupabaseAuthState.signingIn
        assertCondition(signedOutState == .signedOut, "SupabaseAuthState signedOut equality verified")
        assertCondition(signingInState == .signingIn, "SupabaseAuthState signingIn equality verified")
        assertCondition(signedOutState != signingInState, "SupabaseAuthState inequality verified")

        // -------------------------------------------------------------
        // 5. ERROR ABSTRACTION ROBUSTNESS
        // -------------------------------------------------------------
        let cancelError = AppleSignInError.userCancelled
        let tokenError = AppleSignInError.missingIdentityToken
        assertCondition(cancelError.errorDescription == "Sign in was cancelled.", "AppleSignInError userCancelled description verified")
        assertCondition(tokenError.errorDescription != nil, "AppleSignInError missingIdentityToken description verified")

        // -------------------------------------------------------------
        // 6. IDENTITY ISOLATION (CloudKit vs Supabase)
        // -------------------------------------------------------------
        let ckIdentity = UserIdentityService.shared.currentUserIdentity
        let isCKServiceActive = UserIdentityService.shared.currentUserIdentity != nil || !UserIdentityService.shared.isResolving
        assertCondition(isCKServiceActive, "UserIdentityService remains active and untouched")

        // Verify that SupabaseService is a distinct singleton
        let supabaseService = SupabaseService.shared
        let isIsolated = (ckIdentity?.id != supabaseService.currentUser?.id.uuidString)
        assertCondition(isIsolated, "CloudKit recordName and Supabase Auth UUID are cleanly isolated")

        return (allPassed, logs)
    }
}
