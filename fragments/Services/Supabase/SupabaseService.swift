//
//  SupabaseService.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import Observation
import Supabase

/// Represents the observable authentication lifecycle states for Supabase Auth.
public enum SupabaseAuthState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(User)

    public static func == (lhs: SupabaseAuthState, rhs: SupabaseAuthState) -> Bool {
        switch (lhs, rhs) {
        case (.signedOut, .signedOut):
            return true
        case (.signingIn, .signingIn):
            return true
        case (.signedIn(let u1), .signedIn(let u2)):
            return u1.id == u2.id
        default:
            return false
        }
    }
}

/// Central coordinator managing the Supabase client, configuration, and Auth session lifecycle.
///
/// NOTE: This service exclusively uses the public/anon key. Service-role credentials are never
/// bundled or accessed in client-side iOS code.
@Observable
@MainActor
public final class SupabaseService {
    public static let shared = SupabaseService()

    // MARK: - Configuration Defaults
    public nonisolated static let defaultProjectURL = URL(string: "https://etskagauiplcdyhcgptd.supabase.co")!
    public nonisolated static let defaultAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV0c2thZ2F1aXBsY2R5aGNncHRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA1MDQxOTcsImV4cCI6MjEwNjA4MDE5N30._ZDlaza9H2ZpWfDOKH-XHuHFCzBpxiTT8g39bwcizQI"

    // MARK: - Underlying Client
    public let client: SupabaseClient

    // MARK: - Observable State
    public private(set) var authState: SupabaseAuthState = .signedOut
    public private(set) var session: Session? = nil
    public private(set) var currentUser: User? = nil
    public private(set) var isAuthenticated: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String? = nil

    /// Canonical UUID string for the active Supabase user, if authenticated.
    public var currentUserID: String? {
        currentUser?.id.uuidString ?? session?.user.id.uuidString
    }

    /// Canonical native UUID for the active Supabase user, if authenticated.
    public var currentUserUUID: UUID? {
        currentUser?.id ?? session?.user.id
    }

    private var authObserverTask: Task<Void, Never>?

    // MARK: - Initialization
    public init(
        projectURL: URL? = nil,
        anonKey: String? = nil
    ) {
        let resolvedURL = projectURL ?? Self.resolveProjectURL()
        let resolvedKey = anonKey ?? Self.resolveAnonKey()

        self.client = SupabaseClient(
            supabaseURL: resolvedURL,
            supabaseKey: resolvedKey
        )

        startAuthObserver()
        Task { [weak self] in
            await self?.refreshSession()
        }
    }

    // MARK: - Configuration Resolvers
    public nonisolated static func resolveProjectURL() -> URL {
        if let plistPath = Bundle.main.path(forResource: "SupabaseConfig", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: plistPath),
           let urlString = dict["SUPABASE_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        if let infoURL = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           let url = URL(string: infoURL) {
            return url
        }
        return defaultProjectURL
    }

    public nonisolated static func resolveAnonKey() -> String {
        if let plistPath = Bundle.main.path(forResource: "SupabaseConfig", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: plistPath),
           let key = dict["SUPABASE_ANON_KEY"] as? String, !key.isEmpty {
            return key
        }
        if let infoKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !infoKey.isEmpty {
            return infoKey
        }
        return defaultAnonKey
    }

    // MARK: - Auth Session Access & Observation
    private func startAuthObserver() {
        authObserverTask?.cancel()
        let auth = client.auth
        authObserverTask = Task { [weak self] in
            for await (_, session) in auth.authStateChanges {
                guard let self else { break }
                self.applySession(session)
            }
        }
    }

    /// Refreshes and updates the active session asynchronously.
    @discardableResult
    public func refreshSession() async -> Session? {
        do {
            let session = try await client.auth.session
            self.applySession(session)
            self.lastError = nil
            return session
        } catch {
            self.applySession(nil)
            return nil
        }
    }

    /// Applies session state changes consistently across all properties.
    private func applySession(_ session: Session?) {
        self.session = session
        self.currentUser = session?.user
        self.isAuthenticated = session != nil
        if let user = session?.user {
            self.authState = .signedIn(user)
            // Ensure the Supabase profile row carries the local display name so
            // member lists resolve instead of showing the DB default placeholder.
            let localName = ProfileManager.shared.effectiveName
            if !RoomMember.isUnresolvedDisplayName(localName) {
                Task {
                    try? await SupabaseRoomRepository.shared.upsertCurrentUserProfile(displayName: localName)
                }
            }
        } else if isLoading {
            self.authState = .signingIn
        } else {
            self.authState = .signedOut
        }
    }

    /// Clean async API for retrieving the current authenticated user.
    public func getCurrentUser() async -> User? {
        if let user = currentUser {
            return user
        }
        if let session = await refreshSession() {
            return session.user
        }
        return nil
    }

    // MARK: - Sign in with Apple
    /// Signs in with Apple using the identity token and raw nonce.
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        isLoading = true
        authState = .signingIn
        defer { isLoading = false }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            applySession(session)
            self.lastError = nil
            return session
        } catch {
            applySession(nil)
            self.lastError = error.localizedDescription
            throw error
        }
    }

    /// Signs the user out of their Supabase Auth session.
    public func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.signOut()
            applySession(nil)
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            throw error
        }
    }
}
