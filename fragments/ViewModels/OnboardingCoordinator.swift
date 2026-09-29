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
/// Auth modes:
/// - Authenticated: Supabase session present. Full access incl. Shared Moments.
/// - Guest (`isGuestMode`): first-class local-only mode, NO Supabase identity.
///   Guests use Quick Capture, Personal Moments, and the local profile only.
///   Guest completion persists across launches via `guestKey`, so relaunch
///   must NOT confuse "guest with no session" with "signed out".
///
/// State resolution:
/// - Authenticated → username → permissions → main (unchanged).
/// - Guest → permissions → main (username screen skipped; no backend profile).
/// - Neither → onboarding (Apple or Guest choice).
/// - A stale `hasCompletedOnboarding` flag NEVER routes to main on its own.
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

    /// Shared Moment action the guest was blocked from. Preserved across the
    /// Guest → Apple Sign In transition so the app can resume the intended
    /// action instead of dumping the user on the home screen.
    public enum PendingSharedAction: Equatable {
        case startSharedMoment
        case joinMoment
    }

    public var phase: Phase = .splash

    /// When true, the authentication-required sheet should be presented.
    public var showAuthRequired: Bool = false

    /// The blocked action to resume after a successful Guest → sign-in upgrade.
    /// Cleared when consumed or when the user taps "Maybe Later".
    public var pendingSharedAction: PendingSharedAction? = nil

    static let onboardingKey = "hasCompletedOnboarding"
    static let permissionsKey = "hasCompletedPermissions"
    static let guestKey = "isGuestMode"

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

    /// First-class Guest Mode flag. Persisted so relaunch keeps the guest in
    /// the app instead of bouncing them to onboarding. NEVER represents a
    /// Supabase identity — guests have no session, no `auth.users` row, and
    /// no `profiles` row.
    public var isGuestMode: Bool {
        didSet {
            UserDefaults.standard.set(isGuestMode, forKey: Self.guestKey)
        }
    }

    /// True when the current user is a guest: guest mode completed AND no
    /// Supabase session. Becomes false the moment sign-in succeeds.
    public var isGuest: Bool {
        isGuestMode && !supabaseService.isAuthenticated
    }

    public var isAuthenticated: Bool {
        supabaseService.isAuthenticated
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
        self.isGuestMode = UserDefaults.standard.bool(forKey: Self.guestKey)
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
        } else if isGuestMode {
            // Guest with no session is a legitimate completed state — NOT a
            // signed-out user. Resume directly; never show auth onboarding.
            // Local personal data and profile are untouched.
            phase = hasCompletedPermissions ? .main : .permissions
        } else {
            // Unauthenticated always returns to onboarding for re-auth.
            // A stale `hasCompletedOnboarding` flag must NEVER route to main
            // on its own — otherwise username + permissions are skipped.
            phase = .onboarding
        }
    }

    /// Guest Mode entry: an intentional completed auth choice, not a skip.
    /// Routes straight to the shared Permission Gate (username is local-only
    /// for guests, so the backend username screen is skipped entirely).
    public func continueAsGuest() {
        isGuestMode = true
        hasCompletedOnboarding = true
        pendingSharedAction = nil
        showAuthRequired = false
        phase = hasCompletedPermissions ? .main : .permissions
    }

    /// Records that the guest attempted an authenticated-only action. The UI
    /// presents the authentication-required sheet; on successful sign-in the
    /// pending action is resumed instead of dropping the user on home.
    public func requireAuth(for action: PendingSharedAction) {
        guard !supabaseService.isAuthenticated else { return }
        pendingSharedAction = action
        showAuthRequired = true
    }

    /// Dismisses the authentication-required sheet without signing in.
    /// Clears the pending action so a later unrelated sign-in does not
    /// unexpectedly resume a stale intent.
    public func cancelAuthRequest() {
        pendingSharedAction = nil
        showAuthRequired = false
    }

    /// Called with the OnboardingView sign-in result. Success marks onboarding
    /// complete (historical flag semantics) and resolves the next phase.
    func handleSignInResult(_ result: Result<Session, Error>) {
        switch result {
        case .success:
            // Leaving Guest Mode (if in it): local SwiftData moments,
            // fragments, profile, and avatar are preserved — only the mode
            // flag flips. The pending shared action (if any) is kept so the
            // intended flow resumes after username/permissions resolve.
            isGuestMode = false
            hasCompletedOnboarding = true
            Task { await resolveAuthenticated() }
        case .failure:
            // A guest whose upgrade sign-in fails/cancels stays a guest in
            // the app — never kick them back to onboarding.
            if !isGuestMode {
                phase = .onboarding
            }
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
    /// Sign-out never auto-converts to guest and never deletes local personal
    /// data — the user returns to the Apple-or-Guest choice.
    func handleSignOut() {
        hasCompletedOnboarding = false
        hasCompletedPermissions = false
        isGuestMode = false
        pendingSharedAction = nil
        showAuthRequired = false
        phase = .onboarding
    }
}
