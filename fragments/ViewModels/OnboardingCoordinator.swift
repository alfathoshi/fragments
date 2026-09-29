//
//  OnboardingCoordinator.swift
//  fragments
//

import SwiftUI
import Observation
import Supabase

/// Launch state machine: splash → onboarding → username → permissions → main.
///
/// Single source of truth for first-launch navigation. `fragmentsApp` observes
/// this shared coordinator directly — there is no parallel `@AppStorage`
/// onboarding flag at the app root. Username gating is backend-derived
/// (`profiles.username`); there is deliberately no persisted
/// `hasCompletedUsername` flag so a server-side username change is honored on
/// next launch.
///
/// State resolution:
/// - Unauthenticated → onboarding (sign-in lives there, unchanged). A stale
///   `hasCompletedOnboarding` flag NEVER routes to main on its own.
/// - Authenticated + backend username present → skip setup.
/// - Authenticated + missing username → username setup (offline: form still
///   opens; typed text is preserved and save retries per §12).
/// - Pre-migration backend (no `username` column) → setup is SKIPPED, since a
///   username could never persist there (backward compatibility, §13).
/// - `hasCompletedPermissions` persists the permissions gate; the gate view
///   itself skips already-granted and never traps on denial.
@Observable
@MainActor
public final class OnboardingCoordinator {
    public static let shared = OnboardingCoordinator()
    public enum Phase: Equatable {
        case splash
        case onboarding
        case username
        case permissions
        case main
    }

    public var phase: Phase = .splash

    static let onboardingKey = "hasCompletedOnboarding"
    static let permissionsKey = "hasCompletedPermissions"

    public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey)
        }
    }
    public var hasCompletedPermissions: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedPermissions, forKey: Self.permissionsKey)
        }
    }

    private let supabaseService: SupabaseService
    private let repository: SupabaseRoomRepository

    init(
        supabaseService: SupabaseService = .shared,
        repository: SupabaseRoomRepository = .shared
    ) {
        self.supabaseService = supabaseService
        self.repository = repository
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        self.hasCompletedPermissions = UserDefaults.standard.bool(forKey: Self.permissionsKey)
    }

    // MARK: - Entry points

    /// Called when the splash screen finishes its branding delay.
    public func splashFinished() {
        Task { await resolveAfterSplash() }
    }

    public func resolveAfterSplash() async {
        if supabaseService.isAuthenticated {
            await resolveAuthenticated()
            return
        }
        // Refresh once: a valid refresh means a returning session.
        _ = await supabaseService.refreshSession()
        if supabaseService.isAuthenticated {
            await resolveAuthenticated()
        } else {
            // Unauthenticated always returns to onboarding for re-auth.
            // A stale `hasCompletedOnboarding` flag must NEVER route to main
            // on its own — otherwise username + permissions are skipped.
            phase = .onboarding
        }
    }

    /// Called with the OnboardingView sign-in result. Success marks onboarding
    /// complete (historical flag semantics) and resolves the next phase.
    func handleSignInResult(_ result: Result<Session, Error>) {
        switch result {
        case .success:
            hasCompletedOnboarding = true
            Task { await resolveAuthenticated() }
        case .failure:
            phase = .onboarding
        }
    }

    /// Resolves username → permissions → main for an authenticated user.
    ///
    /// Username source of truth is `profiles.username` (nullable, unique).
    /// A missing/empty username routes to the username stage — never past it.
    /// Backend/schema failures are NEVER treated as completion; without a
    /// cached identity they open the username form (which retries), and a
    /// cached identity advances only because the user previously completed
    /// the claim on this device.
    func resolveAuthenticated() async {
        guard supabaseService.isAuthenticated else {
            phase = .onboarding
            return
        }
        do {
            let profile = try await repository.fetchOwnProfile()
            if let username = profile.username,
               !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CachedUsernameStore.save(username, for: supabaseService.currentUserID ?? "")
                // Returning user / reinstall: re-sync the local display cache
                // from the backend source of truth.
                ProfileManager.shared.syncUsername(username)
                advanceAfterUsername()
                return
            }
            // Authenticated but no username (NULL or blank): the user must
            // claim one. Local display name is NOT a substitute.
            phase = .username
        } catch let error as SupabaseRoomError {
            switch error {
            case .schemaMismatch:
                // Username state is UNKNOWN (e.g. migration not applied) —
                // that is not completion. Open the username stage so the
                // requirement cannot be silently skipped; the claim surfaces
                // the backend error with retry until the schema is fixed.
                phase = .username
            case .notAuthenticated:
                phase = .onboarding
            default:
                // Offline/transient: fall back to the local cache; without a
                // cache entry, still open setup (typing + validation work
                // offline and save retries).
                if let cached = CachedUsernameStore.load(for: supabaseService.currentUserID),
                   !cached.isEmpty {
                    advanceAfterUsername()
                } else {
                    phase = .username
                }
            }
        } catch {
            if let cached = CachedUsernameStore.load(for: supabaseService.currentUserID),
               !cached.isEmpty {
                advanceAfterUsername()
            } else {
                phase = .username
            }
        }
    }

    /// Called after a username is confirmed (freshly claimed or pre-existing).
    func completeUsername() {
        advanceAfterUsername()
    }

    private func advanceAfterUsername() {
        phase = hasCompletedPermissions ? .main : .permissions
    }

    /// Called when the permissions gate finishes (granted, denied, or skipped).
    func completePermissions() {
        hasCompletedPermissions = true
        phase = .main
    }

    /// Resets launch gating on sign-out (called alongside the existing flag reset).
    func handleSignOut() {
        hasCompletedOnboarding = false
        hasCompletedPermissions = false
        phase = .onboarding
    }
}
