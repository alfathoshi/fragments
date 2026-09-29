//
//  RequireSignInSheet.swift
//  fragments
//
//  Reusable authentication-required gate for Guest Mode. Presented whenever a
//  guest attempts an authenticated-only Shared Moment action (start/join a
//  shared moment, create/join a room, invite/collaborate).
//
//  This is an intentional product gate, not an error: lightweight copy,
//  "Continue with Apple" primary (reusing AppleSignInCoordinator — no
//  duplicate sign-in implementation), "Maybe Later" secondary.
//

import SwiftUI
import Supabase

/// Lightweight product gate shown to guests attempting shared features.
public struct RequireSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var signInCoordinator = AppleSignInCoordinator.shared
    @State private var errorMessage: String? = nil

    private let coordinator: OnboardingCoordinator

    public init(coordinator: OnboardingCoordinator = .shared) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "person.2.badge.key.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.primary)
                }

                VStack(spacing: 8) {
                    Text("Sign in to share moments")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text("An account helps keep your identity, memories, and shared moments connected")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }


                Spacer()

                Button {
                    handleSignIn()
                } label: {
                    HStack(spacing: 8) {
                        if signInCoordinator.isSigningIn {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Text(signInCoordinator.isSigningIn ? "Signing in…" : "Continue with Apple")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .tint(.primary)
                .glassProminentButtonStyle()
                .clipShape(Capsule())
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .disabled(signInCoordinator.isSigningIn)
                .opacity(signInCoordinator.isSigningIn ? 0.6 : 1.0)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    coordinator.cancelAuthRequest()
                    dismiss()
                } label: {
                    Text("Maybe Later")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .disabled(signInCoordinator.isSigningIn)
            }
            .padding(.horizontal, 20)
        }
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
    }

    private func handleSignIn() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        Task {
            do {
                // Reuses the existing Apple → Supabase flow including
                // server-side credential linking. No duplicate implementation.
                let session = try await signInCoordinator.signIn()
                coordinator.handleSignInResult(.success(session))
                // Dismiss so the pending action (or username/permissions
                // routing) takes over. Local guest data is preserved.
                coordinator.showAuthRequired = false
                dismiss()
            } catch {
                // Cancellation is silent; real errors surface inline with
                // retry — the guest stays in the app either way.
                if let appleError = error as? AppleSignInError,
                   case .userCancelled = appleError {
                    coordinator.cancelAuthRequest()
                    dismiss()
                } else {
                    errorMessage = error.localizedDescription
                    coordinator.handleSignInResult(.failure(error))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Require Sign In") {
    RequireSignInSheet(coordinator: OnboardingCoordinator())
}
#endif
