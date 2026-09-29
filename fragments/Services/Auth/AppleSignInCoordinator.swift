//
//  AppleSignInCoordinator.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import Supabase

/// Strongly-typed errors that can occur during Apple Sign-In and Supabase authentication.
public enum AppleSignInError: LocalizedError, Equatable {
    case missingCredential
    case missingIdentityToken
    case invalidIdentityToken
    case missingAuthorizationCode
    case missingNonceState
    case userCancelled
    case authorizationFailed(String)
    case supabaseAuthFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Apple Sign In returned an unsupported credential type."
        case .missingIdentityToken:
            return "Apple Sign In did not return an identity token."
        case .invalidIdentityToken:
            return "Apple identity token could not be parsed as a UTF-8 string."
        case .missingAuthorizationCode:
            return "Apple Sign In did not return an authorization code."
        case .missingNonceState:
            return "Authentication state was lost. Please try again."
        case .userCancelled:
            return "Sign in was cancelled."
        case .authorizationFailed(let message):
            return "Apple authorization failed: \(message)"
        case .supabaseAuthFailed(let message):
            return "Supabase authentication failed: \(message)"
        }
    }
}

/// Coordinates native Sign in with Apple, cryptographic nonce generation,
/// and delegates authentication to `SupabaseService`.
///
/// NOTE: To prevent credential leakage, this coordinator never logs identity tokens,
/// authorization codes, raw nonces, or user credentials.
@Observable
@MainActor
public final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    public static let shared = AppleSignInCoordinator()

    // MARK: - Observable State
    public private(set) var isSigningIn: Bool = false
    public private(set) var lastError: String? = nil

    // MARK: - Internal State
    private var currentNonce: String?
    private var continuation: CheckedContinuation<Session, Error>?
    private weak var presentationWindow: UIWindow?

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Initiates the native Apple Sign-In flow asynchronously.
    ///
    /// - Parameter presentationAnchor: Optional window to anchor the Apple dialog. If nil, resolves the active key window.
    /// - Returns: The authenticated Supabase `Session`.
    @discardableResult
    public func signIn(presentationAnchor: UIWindow? = nil) async throws -> Session {
        guard !isSigningIn else {
            throw AppleSignInError.authorizationFailed("Sign in is already in progress.")
        }

        isSigningIn = true
        lastError = nil
        presentationWindow = presentationAnchor

        let rawNonce = Self.generateRandomNonce()
        self.currentNonce = rawNonce
        let hashedNonce = Self.sha256(rawNonce)

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            authorizationController.performRequests()
        }
    }

    // MARK: - Nonce Generation & Hashing

    /// Generates a cryptographically secure random string with 32 bytes of entropy.
    public static func generateRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce: SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    /// Computes the SHA-256 hash of the input string, returned as a lowercased hex string.
    public static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = presentationWindow {
            return window
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window
            }
        }
        return ASPresentationAnchor()
    }

    // MARK: - ASAuthorizationControllerDelegate

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleSignInError.missingCredential))
            return
        }

        guard let rawNonce = currentNonce else {
            finish(with: .failure(AppleSignInError.missingNonceState))
            return
        }

        guard let idTokenData = appleIDCredential.identityToken else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        guard let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            finish(with: .failure(AppleSignInError.invalidIdentityToken))
            return
        }

        // The authorization code is short-lived and single-use. It is NOT a
        // session credential: it is forwarded (once, fire-and-forget) so the
        // server can exchange it for an Apple refresh token used ONLY at
        // account-deletion time for authorization revocation. It is never
        // persisted on device and never logged.
        let authorizationCodeString: String? = appleIDCredential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await SupabaseService.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: rawNonce
                )
                // Best-effort credential linking; must never fail sign-in.
                if let code = authorizationCodeString, !code.isEmpty {
                    await SupabaseService.shared.linkAppleAuthorizationCode(code)
                }
                self.finish(with: .success(session))
            } catch {
                self.finish(with: .failure(AppleSignInError.supabaseAuthFailed(error.localizedDescription)))
            }
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(with: .failure(AppleSignInError.userCancelled))
        } else {
            finish(with: .failure(AppleSignInError.authorizationFailed(error.localizedDescription)))
        }
    }

    // MARK: - Private Completion Dispatcher

    private func finish(with result: Result<Session, Error>) {
        currentNonce = nil
        presentationWindow = nil
        isSigningIn = false

        switch result {
        case .success(let session):
            lastError = nil
            continuation?.resume(returning: session)
        case .failure(let error):
            if case AppleSignInError.userCancelled = error {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
