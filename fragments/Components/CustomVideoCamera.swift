//
//  CustomVideoCamera.swift
//  fragments
//
//  Created on 9/14/26.
//

import SwiftUI

// MARK: - Custom Video Camera View

/// A specialized video recording camera card matching the tactile design aesthetic of Figma node 140:7189.
/// Configured specifically for video capture:
/// - Top control bar: Camera Flip Button + 2-Button Zoom Switch (1x / 2x)
/// - Large viewfinder viewport with live recording duration timer, recording border glow, and tap-to-focus
/// - Bottom tactile control bar:
///   1. Balanced left spacer (timer removed for video mode, keeping record button dead-center)
///   2. Tactical Record Button (74 pt, transitions from red circle to red square stop icon)
///   3. Video Torch Light Button (62 pt, illuminated yellow active state)
public struct CustomVideoCamera: View {
    // MARK: - Callbacks & Bindings

    public var onStartRecording: (() -> Void)?
    public var onStopRecording: ((TimeInterval) -> Void)?
    public var onCapturedVideo: ((URL?, TimeInterval) -> Void)?
    public var onClose: (() -> Void)?
    public var onZoomChanged: ((RockerSwitchOption) -> Void)?
    public var onFlipCamera: ((Bool) -> Void)?

    // MARK: - Video Camera State

    public var isActive: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraService = CameraService(isForVideo: true)
    @State private var zoomLevel: RockerSwitchOption = .oneX
    @State private var isFrontCamera: Bool = false
    @State private var isTorchOn: Bool = false
    @State private var isRecording: Bool = false
    @State private var elapsedTime: Double = 0.0
    @State private var recordingTimer: Timer? = nil
    private let maxRecordingDuration: Double = 5.0

    @State private var focusPoint: CGPoint? = nil
    @State private var isFocusing: Bool = false
    @State private var recordedClipsCount: Int = 0

    // MARK: - Dimensions (Figma card specs)

    private let cardCornerRadius: CGFloat = 47
    private let viewportCornerRadius: CGFloat = 31

    // MARK: - Initializer

    public init(
        isActive: Bool = true,
        onStartRecording: (() -> Void)? = nil,
        onStopRecording: ((TimeInterval) -> Void)? = nil,
        onCapturedVideo: ((URL?, TimeInterval) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onZoomChanged: ((RockerSwitchOption) -> Void)? = nil,
        onFlipCamera: ((Bool) -> Void)? = nil
    ) {
        self.isActive = isActive
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCapturedVideo = onCapturedVideo
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

                // 2. Viewfinder Viewport (Figma Node 140:7190 with Video Overlays)
                viewfinderViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 3. Bottom Camera Controls Bar (Record Button + Torch Light)
                bottomControlsBar
                    .frame(height: 74)
                    .padding(.bottom, 2)
            }
            .padding(16)
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
                cameraService.configureForVideo()
                cameraService.startSession()
            }
        }
        .onDisappear {
            cameraService.stopSession()
        }
        .onChange(of: isActive) { _, active in
            if active {
                cameraService.configureForVideo()
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

    // MARK: - 2. Viewfinder Viewport (Video Mode)

    private var viewfinderViewport: some View {
        GeometryReader { proxy in
            ZStack {
                // Live Hardware Camera Feed OR Fallback Canvas
                if cameraService.isSessionRunning && !cameraService.isUnavailable {
                    CameraPreviewView(session: cameraService.captureSession)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    // Viewfinder Backdrop (#8E8E93 / Video Feed Canvas)
                    RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                        .fill(Color(red: 0.557, green: 0.557, blue: 0.576)) // #8E8E93

                    // Viewfinder Simulated Visual Content
                    viewfinderSimulatedContent
                        .scaleEffect(zoomLevel == .twoX ? 1.45 : 1.0)
                        .rotation3DEffect(
                            .degrees(isFrontCamera ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .animation(.spring(response: 0.38, dampingFraction: 0.76), value: zoomLevel)
                        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isFrontCamera)
                }

                // 5-Second Active Recording Progress Border Surrounding the Video Frame
                if isRecording {
                    // Subtle background track channel along the video frame perimeter
                    RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 4.0)

                    // Glowing red progress stroke traveling around the video frame perimeter
                    RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                        .trim(from: 0.0, to: min(CGFloat(elapsedTime / maxRecordingDuration), 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.22, blue: 0.20),
                                    Color(red: 1.0, green: 0.45, blue: 0.35),
                                    Color(red: 1.0, green: 0.22, blue: 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4.0, lineCap: .round)
                        )
                        .shadow(color: Color.red.opacity(0.65), radius: 6)
                        .animation(.linear(duration: 0.05), value: elapsedTime)
                }

                // Video HUD Overlay
                VStack {
                    // Top HUD Bar: Close Button, Live Recording Timer Pill, Front/Rear Tag
                    HStack {

                        Spacer()


                        // Torch Status Badge
                        if isTorchOn {
                            HStack(spacing: 3) {
                                Image(systemName: "flashlight.on.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("TORCH")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.40), in: Capsule())
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

                    Spacer()

                    // Bottom Viewfinder Overlay (Zoom readout, Video tag, Recorded count)
                    HStack {
                        Text("\(zoomLevel.rawValue.uppercased())")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.30), in: Capsule())

                        Spacer()

                        if recordedClipsCount > 0 {
                            Text("\(recordedClipsCount) Clips")
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

    // MARK: - 3. Bottom Controls Bar (Timer Removed, Record Centered)

    private var bottomControlsBar: some View {
        HStack(spacing: 0) {
            // Left: Balancing Spacer (62 pt - perfectly balances right Torch button so Record stays centered)
            Color.clear
                .frame(width: 62, height: 62)

            Spacer(minLength: 0)

            // Center: Tactical Record Button (74 pt, transitions from red dot to red stop square)
            TactileCircularButton(
                size: 74,
                keycapColor: nil,
                isActive: isRecording
            ) {
                toggleRecording()
            } content: {
                ZStack {
                    if isRecording {
                        // Red Rounded Stop Square
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.22, blue: 0.20))
                            .frame(width: 24, height: 24)
                            .shadow(color: Color.red.opacity(0.35), radius: 4)
                            .transition(.scale)
                    } else {
                        // Red Record Circle
                        Circle()
                            .fill(Color(red: 0.95, green: 0.22, blue: 0.20))
                            .frame(width: 28, height: 28)
                            .shadow(color: Color.red.opacity(0.35), radius: 4)
                            .transition(.scale)
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isRecording)
            }
            

            Spacer(minLength: 0)

            // Right: Video Torch / Light Button (62 pt)
            TactileCircularButton(
                systemImage: isTorchOn ? "bolt.fill" : "bolt.slash.fill",
                iconColor: isTorchOn ? Color.yellow : (colorScheme == .dark ? .white : .black),
                keycapColor: isTorchOn ? (colorScheme == .dark ? Color(red: 0.32, green: 0.30, blue: 0.14) : Color(red: 0.98, green: 0.97, blue: 0.90)) : nil,
                size: 62,
                iconSize: 22,
                iconWeight: .bold,
                isActive: isTorchOn
            ) {
                toggleTorch()
            }
            .accessibilityLabel(isTorchOn ? "Video Torch On" : "Video Torch Off")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Recording Actions

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        elapsedTime = 0.0
        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
            isRecording = true
        }

        // Hardware video recording via AVFoundation
        cameraService.startVideoRecording()

        // 5-Second Precision Tick Timer
        recordingTimer?.invalidate()
        let startTime = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let currentElapsed = Date().timeIntervalSince(startTime)
            if currentElapsed >= maxRecordingDuration {
                elapsedTime = maxRecordingDuration
                stopRecording()
            } else {
                elapsedTime = currentElapsed
            }
        }

        onStartRecording?()
    }

    private func stopRecording() {
        guard isRecording else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordedClipsCount += 1

        let duration = min(elapsedTime, maxRecordingDuration)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
            isRecording = false
        }

        // Stop AVFoundation recording and pass captured URL
        cameraService.stopVideoRecording { url, clipDuration in
            let finalDuration = clipDuration > 0 ? min(clipDuration, maxRecordingDuration) : duration
            onCapturedVideo?(url, finalDuration)
        }

        onStopRecording?(duration)
    }

    private func toggleTorch() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            isTorchOn.toggle()
        }
        cameraService.setTorch(on: isTorchOn)
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

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

#Preview("CustomVideoCamera - Interactive") {
    ZStack {
        Color(red: 0.09, green: 0.09, blue: 0.10)
            .ignoresSafeArea()

        CustomVideoCamera(
            onStartRecording: {
                print("Video recording started")
            },
            onStopRecording: { duration in
                print("Video recording stopped. Duration: \(duration)s")
            },
            onClose: {
                print("Close video camera")
            }
        )
    }
}

#Preview("CustomVideoCamera - Fullscreen") {
    ZStack {
        Color.black.ignoresSafeArea()

        CustomVideoCamera()
            .padding(.vertical, 20)
    }
}
