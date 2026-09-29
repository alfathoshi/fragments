//
//  SplashScreenView.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/16/26.
//

import SwiftUI

public struct SplashScreenView: View {
    public var onFinished: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.0

    public init(onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {

                VStack(spacing: 20) {
                    Image(colorScheme == .dark ? "AppIconDark" : "AppIconLight")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 136, height: 136)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 16, y: 8)

                    VStack(spacing: 6) {
                        Text("Fraqments")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Capture a Moment")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .scaleEffect(scale)
                .opacity(opacity)

            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                scale = 1.0
                opacity = 1.0
            }

            // Branding delay only. Permission prompts were removed from launch:
            // they now run sequentially in PermissionsGateView after username
            // setup. No system prompt may fire before that gate.
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                onFinished?()
            }
        }
    }
}

#if DEBUG
#Preview {
    SplashScreenView()
}
#endif
