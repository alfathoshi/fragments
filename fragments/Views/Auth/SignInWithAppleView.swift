//
//  SignInWithAppleView.swift
//  fragments
//
//  Created on 9/27/26.
//

import SwiftUI
import AuthenticationServices
import Supabase

/// Reusable SwiftUI wrapper for Apple's official `ASAuthorizationAppleIDButton`.
///
/// Triggers `AppleSignInCoordinator` to authenticate with Apple and exchange
/// the identity token with Supabase Auth.
public struct SignInWithAppleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var coordinator = AppleSignInCoordinator.shared

    public var onCompletion: ((Result<Session, Error>) -> Void)?

    public init(onCompletion: ((Result<Session, Error>) -> Void)? = nil) {
        self.onCompletion = onCompletion
    }

    public var body: some View {
        ZStack {
            ASAuthorizationAppleIDButtonRepresentable(
                type: .signIn,
                style: colorScheme == .dark ? .white : .black,
                cornerRadius: 14
            ) {
                handleSignIn()
            }
            .frame(height: 50)
            .opacity(coordinator.isSigningIn ? 0.4 : 1.0)
            .disabled(coordinator.isSigningIn)

            if coordinator.isSigningIn {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .black : .white))
            }
        }
    }

    private func handleSignIn() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                let session = try await coordinator.signIn()
                onCompletion?(.success(session))
            } catch {
                onCompletion?(.failure(error))
            }
        }
    }
}

/// UIViewRepresentable wrapper strictly adhering to Apple's native `ASAuthorizationAppleIDButton`.
public struct ASAuthorizationAppleIDButtonRepresentable: UIViewRepresentable {
    public var type: ASAuthorizationAppleIDButton.ButtonType
    public var style: ASAuthorizationAppleIDButton.Style
    public var cornerRadius: CGFloat
    public var action: () -> Void

    public init(
        type: ASAuthorizationAppleIDButton.ButtonType = .signIn,
        style: ASAuthorizationAppleIDButton.Style = .black,
        cornerRadius: CGFloat = 14,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.style = style
        self.cornerRadius = cornerRadius
        self.action = action
    }

    public func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: style)
        button.cornerRadius = cornerRadius
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTapButton), for: .touchUpInside)
        return button
    }

    public func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.cornerRadius = cornerRadius
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    public final class Coordinator: NSObject {
        private let action: () -> Void

        public init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func didTapButton() {
            action()
        }
    }
}
