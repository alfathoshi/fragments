//
//  CustomCamera.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/14/26.
//

import SwiftUI

// MARK: - Custom Camera View

/// A high-precision camera capture card component matching Figma node 140:7189.
/// Integrates:
/// - Milled outer card chassis (386 × 804 pt) with Figma-spec drop shadow and inner specular bevels
/// - Top control bar: Camera Flip Button + 2-Button Zoom Switch (1x / 2x)
/// - Large viewfinder viewport (corner radius 31 pt) with tap-to-focus, countdown overlay, and shutter flash
/// - Bottom tactile control bar:
///   1. Timer Button (62 pt, cycles Off -> 3s -> 10s with dynamic badge)
///   2. Tactical Capture (+) Button (74 pt, countdown or instant shutter trigger)
///   3. Flash Toggle Button (62 pt, illuminated yellow active state)
public struct CustomCamera: View {
    // MARK: - Callbacks & Bindings

    public var onCapture: (() -> Void)?
    public var onCapturedPhoto: ((UIImage?, URL?) -> Void)?
    public var onClose: (() -> Void)?
    public var onZoomChanged: ((RockerSwitchOption) -> Void)?
    public var onFlipCamera: ((Bool) -> Void)?

    // MARK: - Camera State

    public var isActive: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraService = CameraService(isForVideo: false)
    @State private var zoomLevel: RockerSwitchOption = .oneX
    @State private var isFrontCamera: Bool = false
    @State private var isFlashOn: Bool = false
    @State private var timerSeconds: Int = 0 // 0 = off, 3 = 3s, 10 = 10s
    @State private var countdownRemaining: Int? = nil
    @State private var countdownTask: Task<Void, Never>? = nil

    @State private var flashOpacity: Double = 0.0
    @State private var focusPoint: CGPoint? = nil
    @State private var isFocusing: Bool = false
    @State private var captureCount: Int = 0

    // MARK: - Dimensions (Figma specs)

    private let cardCornerRadius: CGFloat = 47
    private let viewportCornerRadius: CGFloat = 31

    // MARK: - Initializer

    public init(
        isActive: Bool = true,
        onCapture: (() -> Void)? = nil,
        onCapturedPhoto: ((UIImage?, URL?) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onZoomChanged: ((RockerSwitchOption) -> Void)? = nil,
        onFlipCamera: ((Bool) -> Void)? = nil
    ) {
        self.isActive = isActive
        self.onCapture = onCapture
        self.onCapturedPhoto = onCapturedPhoto
        self.onClose = onClose
        self.onZoomChanged = onZoomChanged
        self.onFlipCamera = onFlipCamera
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Card Chassis Background
            (colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)

            // Main Card Layout: Top Bar + Viewfinder + Bottom Bar
            VStack(spacing: 16) {
                // 1. Top Controls Bar (Flip Button & Zoom Rocker Switch)
                topControlsBar
                    .frame(height: 74)

                // 2. Viewfinder Viewport (Figma Node 140:7190)
                viewfinderViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 3. Bottom Camera Controls Bar (Timer + Capture (+) + Flash)
                bottomControlsBar
                    .frame(height: 74)
                    .padding(.bottom, 2)
            }
            .padding(16)

            // Shutter Flash Overlay
            Color.white
                .opacity(flashOpacity)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 386, maxHeight: 804)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        // Figma Drop Shadow: drop-shadow-[0px_2.897px_5.432px_rgba(0,0,0,0.15)]
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 8, x: 0, y: 3.5)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 2, x: 0, y: 1.0)
        // Specular Inner Bevel / Rim Highlight
        .overlay {
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: isDark ? [
                            .init(color: Color.white.opacity(0.20), location: 0.0),
                            .init(color: Color.white.opacity(0.06), location: 0.25),
                            .init(color: Color.white.opacity(0.02), location: 0.85),
                            .init(color: Color.black.opacity(0.30), location: 1.0)
                        ] : [
                            .init(color: Color.white.opacity(0.95), location: 0.0),
                            .init(color: Color(red: 0.90, green: 0.90, blue: 0.92), location: 0.25),
                            .init(color: Color(red: 0.85, green: 0.85, blue: 0.88), location: 0.85),
                            .init(color: Color.black.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
        .onAppear {
            if isActive {
                cameraService.configureForPhoto()
                cameraService.startSession()
            }
        }
        .onDisappear {
            cameraService.stopSession()
        }
        .onChange(of: isActive) { _, active in
            if active {
                cameraService.configureForPhoto()
                cameraService.startSession()
            } else {
                cameraService.stopSession()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isActive {
                cameraService.startSession()
            } else {
                cameraService.stopSession()
            }
        }
    }

    // MARK: - 1. Top Controls Bar

    private var topControlsBar: some View {
        HStack(spacing: 0) {
            // Left: Camera Flip Button (62 pt, rotating SF Symbol arrow.triangle.2.circlepath)
            CameraFlipButton(isFrontCamera: $isFrontCamera) {
                cameraService.flipCamera()
                onFlipCamera?(isFrontCamera)
            }

            Spacer(minLength: 0)

            // Right: 2-Button Zoom Switch (115 × 48 pt, 1x / 2x selection)
            RockerSwitch(
                selection: $zoomLevel,
                onSelectionChanged: { newZoom in
                    cameraService.setZoom(factor: newZoom == .twoX ? 2.0 : 1.0)
                    onZoomChanged?(newZoom)
                }
            )
        }
        .padding(.horizontal, 8)
    }

    // MARK: - 2. Viewfinder Viewport (Figma Node 140:7190)

    private var viewfinderViewport: some View {
        GeometryReader { proxy in
            ZStack {
                // Live Hardware Camera Feed OR Fallback Canvas
                if cameraService.isSessionRunning && !cameraService.isUnavailable {
                    CameraPreviewView(session: cameraService.captureSession)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    // Viewfinder Backdrop (#8E8E93 / Camera Feed Simulation)
                    RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                        .fill(Color(red: 0.557, green: 0.557, blue: 0.576)) // #8E8E93

                    // Viewfinder Visual Content (Simulated Camera Canvas)
                    viewfinderSimulatedContent
                        .scaleEffect(zoomLevel == .twoX ? 1.45 : 1.0)
                        .rotation3DEffect(
                            .degrees(isFrontCamera ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.76), value: zoomLevel)
                        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isFrontCamera)
                }

                // Top Viewfinder HUD Overlay (Close button, Front/Rear tag, Active Badges)
                VStack {
                    HStack {

                        Spacer()

                        // Status badges (Flash & Timer indicators)
                        HStack(spacing: 8) {
                            if isFlashOn {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("FLASH")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.40), in: Capsule())
                            }

                            if timerSeconds > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(timerSeconds)s")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.40), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    // Center Focus Reticle
                    if let point = focusPoint, isFocusing {
                        FocusReticleView()
                            .position(point)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Large Timer Countdown Display
                    if let countdown = countdownRemaining {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.48))
                                .frame(width: 96, height: 96)

                            Text("\(countdown)")
                                .font(.system(size: 54, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    // Viewfinder Bottom Overlay (Zoom readout & Capture counter)
                    HStack {
                        Text("\(zoomLevel.rawValue.uppercased())")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.30), in: Capsule())

                        Spacer()

                        if captureCount > 0 {
                            Text("\(captureCount) Captured")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.30), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous))
            .onTapGesture { location in
                handleTapToFocus(at: location, in: proxy.size)
            }
        }
    }

    // MARK: - Viewfinder Simulated Content

    private var viewfinderSimulatedContent: some View {
        ZStack {
            // Rule of thirds lines
            Canvas { context, size in
                let strokeColor = Color.white.opacity(0.12)
                let x1 = size.width / 3
                let x2 = size.width * 2 / 3
                let y1 = size.height / 3
                let y2 = size.height * 2 / 3

                var path = Path()
                path.move(to: CGPoint(x: x1, y: 0))
                path.addLine(to: CGPoint(x: x1, y: size.height))
                path.move(to: CGPoint(x: x2, y: 0))
                path.addLine(to: CGPoint(x: x2, y: size.height))

                path.move(to: CGPoint(x: 0, y: y1))
                path.addLine(to: CGPoint(x: size.width, y: y1))
                path.move(to: CGPoint(x: 0, y: y2))
                path.addLine(to: CGPoint(x: size.width, y: y2))

                context.stroke(path, with: .color(strokeColor), lineWidth: 0.75)
            }

            // Center Crosshair Reticle
            Image(systemName: "viewfinder")
                .font(.system(size: 54, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.22))
        }
    }

    // MARK: - 3. Bottom Controls Bar

    private var bottomControlsBar: some View {
        HStack(spacing: 0) {
            // Left: Timer Button (62 pt, cycles Off -> 3s -> 10s)
            TactileCircularButton(
                size: 62,
                keycapColor: timerSeconds > 0 ? (colorScheme == .dark ? Color(red: 0.35, green: 0.22, blue: 0.12) : Color(red: 0.99, green: 0.96, blue: 0.91)) : nil,
                isActive: timerSeconds > 0
            ) {
                cycleTimer()
            } content: {
                VStack(spacing: -1) {
                    Image(systemName: "timer")
                        .font(.system(size: timerSeconds > 0 ? 15 : 20, weight: .bold))
                    if timerSeconds > 0 {
                        Text("\(timerSeconds)s")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                }
                .foregroundStyle(timerSeconds > 0 ? Color.orange : (colorScheme == .dark ? Color.white : Color.black))
            }
            .accessibilityLabel(timerSeconds > 0 ? "Timer \(timerSeconds) seconds" : "Timer Off")

            Spacer(minLength: 0)

            // Center: Large Capture (+) Button (74 pt, tactile circular push button)
            TactileCircularButton(
                systemImage: countdownRemaining != nil ? "xmark" : "plus",
                iconColor: countdownRemaining != nil ? .red : (colorScheme == .dark ? .white : .black),
                size: 74,
                iconSize: 26,
                iconWeight: .bold
            ) {
                handleCaptureButtonTap()
            }
            .accessibilityLabel(countdownRemaining != nil ? "Cancel Timer" : "Take Photo")

            Spacer(minLength: 0)

            // Right: Flash Button (62 pt, illuminated yellow active state)
            TactileCircularButton(
                systemImage: isFlashOn ? "bolt.fill" : "bolt.slash.fill",
                iconColor: isFlashOn ? Color.yellow : (colorScheme == .dark ? .white : .black),
                keycapColor: isFlashOn ? (colorScheme == .dark ? Color(red: 0.32, green: 0.30, blue: 0.14) : Color(red: 0.98, green: 0.97, blue: 0.90)) : nil,
                size: 62,
                iconSize: 22,
                iconWeight: .bold,
                isActive: isFlashOn
            ) {
                toggleFlash()
            }
            .accessibilityLabel(isFlashOn ? "Flash On" : "Flash Off")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Action Handlers

    private func cycleTimer() {
        cancelCountdown()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            switch timerSeconds {
            case 0:  timerSeconds = 3
            case 3:  timerSeconds = 10
            default: timerSeconds = 0
            }
        }
    }

    private func toggleFlash() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            isFlashOn.toggle()
        }
    }

    private func handleCaptureButtonTap() {
        // If countdown is already running, cancel it
        if countdownTask != nil {
            cancelCountdown()
            return
        }

        // If timer is configured, initiate countdown
        if timerSeconds > 0 {
            startCountdown()
        } else {
            executeShutterCapture()
        }
    }

    private func startCountdown() {
        countdownRemaining = timerSeconds
        countdownTask = Task {
            for sec in (1...timerSeconds).reversed() {
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                        countdownRemaining = sec
                    }
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation {
                    countdownRemaining = nil
                    countdownTask = nil
                }
                executeShutterCapture()
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation {
            countdownRemaining = nil
        }
    }

    private func executeShutterCapture() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        captureCount += 1

        // White Shutter Flash Animation (brighter when flash is ON)
        withAnimation(.easeIn(duration: 0.08)) {
            flashOpacity = isFlashOn ? 0.95 : 0.75
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.22)) {
                flashOpacity = 0.0
            }
        }

        // Hardware photo capture via AVFoundation
        cameraService.capturePhoto(isFlashOn: isFlashOn) { image, url in
            onCapturedPhoto?(image, url)
        }

        onCapture?()
    }

    private func handleTapToFocus(at location: CGPoint, in size: CGSize) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        focusPoint = location
        isFocusing = true
        cameraService.focus(at: location, in: CGRect(origin: .zero, size: size))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                isFocusing = false
            }
        }
    }
}

// MARK: - Focus Reticle View

private struct FocusReticleView: View {
    @State private var scale: CGFloat = 1.25

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.yellow, lineWidth: 1.5)
                .frame(width: 60, height: 60)

            Circle()
                .fill(Color.yellow)
                .frame(width: 4, height: 4)
        }
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Previews

#Preview("CustomCamera - Interactive (Top & Bottom Controls)") {
    ZStack {
        Color(red: 0.09, green: 0.09, blue: 0.10)
            .ignoresSafeArea()

        CustomCamera(
            onCapture: {
                print("Photo captured!")
            },
            onClose: {
                print("Close camera tapped")
            }
        )
    }
}

#Preview("CustomCamera - In Fullscreen Sheet") {
    ZStack {
        Color.black.ignoresSafeArea()

        CustomCamera()
            .padding(.vertical, 20)
    }
}
