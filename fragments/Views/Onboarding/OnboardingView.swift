//
//  OnboardingView.swift
//  fragments
//
//  Created on 9/28/26.
//

import SwiftUI
import Supabase

/// Full-screen onboarding flow with 3 swipeable pages and Sign In with Apple.
///
/// Page 1 (node 374:2119): "Some moments deserve more than a photo"
///   - Scattered fragment cards (photo, note, audio) with warm yellow glow
///
/// Page 2 (node 379:2457): "Don't let the moment pass you by"
///   - Moment capture dark panel with fragment cards and red glow
///
/// Page 3 (node 379:2499): "Moments are better when they're shared."
///   - Shared folder with memoji avatars and blue glow
struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage: Int = 0
    @State private var coordinator = AppleSignInCoordinator.shared

    var onSignInComplete: ((Result<Session, Error>) -> Void)?
    var onGuestContinue: (() -> Void)?

    init(
        onSignInComplete: ((Result<Session, Error>) -> Void)? = nil,
        onGuestContinue: (() -> Void)? = nil
    ) {
        self.onSignInComplete = onSignInComplete
        self.onGuestContinue = onGuestContinue
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Some moments deserve\nmore than a photo",
            subtitle: "Photos capture what happened.\nFragments helps you remember how it felt."
        ) {
            OnboardingPage1Illustration()
        },
        OnboardingPage(
            id: 1,
            title: "Moments are better\nwhen they're shared.",
            subtitle: "Share moments with the people who were there.\nBring them into the one that matter."
        ) {
            OnboardingPage2Illustration()
        },
        OnboardingPage(
            id: 2,
            title: "Don't let the moment\npass you by",
            subtitle: "Start a Moment and keep capturing\nwithout interrupting the experience."
        ) {
            OnboardingPage3Illustration()
        }
    ]

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Swipeable page content
                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        OnboardingPageView(page: page, isActive: currentPage == page.id)
                            .tag(page.id)

                    }
                }
                .ignoresSafeArea()
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Page indicator dots
                pageIndicator
                    .padding(.bottom, 20)

                // Authentication choice: Apple (primary) or Guest (secondary).
                // Guest Mode is a legitimate supported mode, not a skipped step.
                continueWithAppleButton
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Text("or")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 12)

                continueAsGuestButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    // MARK: - Page Indicator Dots

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == currentPage ? Color.primary : Color(uiColor: .systemGray4))
                    .frame(
                        width: index == currentPage ? 20 : 10,
                        height: 10
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }

    // MARK: - Continue with Apple Button (glassProminent style with primary tint)

    private var continueWithAppleButton: some View {
        Button {
            handleSignIn()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 17, weight: .semibold))
                Text("Continue with Apple")
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
        .opacity(coordinator.isSigningIn ? 0.5 : 1.0)
        .disabled(coordinator.isSigningIn)
        .overlay {
            if coordinator.isSigningIn {
                ProgressView()
                    .tint(colorScheme == .dark ? .black : .white)
            }
        }
    }

    // MARK: - Continue as Guest Button (secondary, always available)

    private var continueAsGuestButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onGuestContinue?()
        } label: {
            Text("Continue as Guest")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 380)
        .disabled(coordinator.isSigningIn)
        .opacity(coordinator.isSigningIn ? 0.5 : 1.0)
    }

    // MARK: - Sign In Handler

    private func handleSignIn() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                let session = try await coordinator.signIn()
                onSignInComplete?(.success(session))
            } catch {
                onSignInComplete?(.failure(error))
            }
        }
    }
}

#if DEBUG
#Preview("Onboarding Flow - Light") {
    OnboardingView()
}

#Preview("Onboarding Flow - Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
#endif

