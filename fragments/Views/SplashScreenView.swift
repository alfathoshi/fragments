//
//  SplashScreenView.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/16/26.
//

import SwiftUI
import AVFoundation

public struct SplashScreenView: View {
    public var onFinished: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.0
    @State private var statusText: String = "Initializing..."
    @State private var showPermissionPills: Bool = false
    @State private var isCameraGranted: Bool = false
    @State private var isMicGranted: Bool = false
    @State private var isLocationGranted: Bool = false

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
                        Text("Fragments")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Capture a moments")
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

            Task {
                await requestAllPermissions()
            }
        }
    }

    private func permissionBadge(title: String, icon: String, isGranted: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isGranted ? Color.green : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (isGranted ? Color.green.opacity(0.14) : Color.primary.opacity(0.06)),
            in: Capsule()
        )
    }

    @MainActor
    private func requestAllPermissions() async {
        try? await Task.sleep(nanoseconds: 350_000_000)

        withAnimation(.easeInOut(duration: 0.25)) {
            showPermissionPills = true
            statusText = "Checking permissions..."
        }

        // 1. Camera Permission
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camStatus == .authorized {
            isCameraGranted = true
        } else if camStatus == .notDetermined {
            statusText = "Requesting Camera Access..."
            isCameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        // 2. Microphone Permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .authorized {
            isMicGranted = true
        } else if micStatus == .notDetermined {
            statusText = "Requesting Microphone Access..."
            isMicGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        // 3. Location Permission
        statusText = "Requesting Location Access..."
        LocationManager.shared.requestLocation()
        let locStatus = LocationManager.shared.authorizationStatus
        isLocationGranted = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)

        withAnimation {
            statusText = "Ready!"
        }

        try? await Task.sleep(nanoseconds: 400_000_000)

        onFinished?()
    }
}

#if DEBUG
#Preview {
    SplashScreenView()
}
#endif
