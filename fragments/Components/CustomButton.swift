//
//  CustomButton.swift
//  fragments
//
//  Created on 9/14/26.
//

import SwiftUI

// MARK: - Reusable Tactile Circular Button Component

/// A highly customizable, tactile circular button modeled after precision camera hardware.
/// Faithfully reproduces the physical depth, milled socket bezel, and chamfered keycap of Figma node 140:7191.
///
/// Features:
/// - Fully customizable **icon** (SF Symbol or custom ViewBuilder content)
/// - Fully customizable **colors** (icon color, keycap base color, bezel color)
/// - Authentic physical button depression travel (`1.6 pt` travel on press)
/// - Dual-stage mechanical haptic feedback (`.light` on press-down, `.rigid` on release)
/// - Optional tap rotation (e.g. for flip/sync/refresh)
/// - Optional `isActive` toggle state with illuminated specular feedback
public struct TactileCircularButton<Content: View>: View {
    // MARK: - Properties

    @Environment(\.colorScheme) private var colorScheme

    public var size: CGFloat
    public var keycapColor: Color?
    public var bezelColor: Color?
    public var isActive: Bool
    public var rotatesOnTap: Bool
    public var action: (() -> Void)?
    @ViewBuilder public var content: () -> Content

    // MARK: - Internal Proportional Dimensions

    private var innerSize: CGFloat {
        size * (52.2 / 62.0)
    }

    private var resolvedKeycapColor: Color {
        if let keycapColor = keycapColor {
            return keycapColor
        }
        return colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.25) : Color(red: 0.949, green: 0.949, blue: 0.969)
    }

    // MARK: - Internal Animation State

    @State private var rotationAngle: Double = 0

    // MARK: - Initializers

    /// Initializer with custom ViewBuilder content
    public init(
        size: CGFloat = 62,
        keycapColor: Color? = nil,
        bezelColor: Color? = nil,
        isActive: Bool = false,
        rotatesOnTap: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.size = size
        self.keycapColor = keycapColor
        self.bezelColor = bezelColor
        self.isActive = isActive
        self.rotatesOnTap = rotatesOnTap
        self.action = action
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // 1. Milled Outer Socket Ring Bezel (Figma Frame 25)
            outerSocketBezel

            // 2. Tactile Circular Push Button (Figma Frame 26)
            Button {
                triggerTap()
            } label: {
                innerKeycap
            }
            .buttonStyle(PhysicalButtonStyle(innerSize: innerSize))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    // MARK: - 1. Outer Socket Ring Bezel

    private var outerSocketBezel: some View {
        let isDark = colorScheme == .dark
        let baseBezel = bezelColor ?? (isDark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 0.885, green: 0.890, blue: 0.905))

        return Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: baseBezel.opacity(1.0), location: 0.0),
                        .init(color: baseBezel.opacity(0.85), location: 0.6),
                        .init(color: baseBezel.opacity(0.70), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            // Top socket cavity inner shadow
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: (isDark ? Color.black : Color(red: 0.35, green: 0.36, blue: 0.40)).opacity(isDark ? 0.85 : 0.65), location: 0.0),
                                .init(color: (isDark ? Color.black : Color(red: 0.35, green: 0.36, blue: 0.40)).opacity(isDark ? 0.40 : 0.20), location: 0.40),
                                .init(color: Color.clear, location: 0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: size * 0.045
                    )
                    .blur(radius: size * 0.025)
                    .mask(Circle())
            }
            // Specular bottom-rim chamfer highlight
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isDark ? 0.22 : 0.55), location: 0.0),
                                .init(color: Color.white.opacity(isDark ? 0.06 : 0.15), location: 0.35),
                                .init(color: Color.clear, location: 0.65),
                                .init(color: Color.white.opacity(isDark ? 0.35 : 0.75), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
    }

    // MARK: - 2. Inner Keycap Surface

    private var innerKeycap: some View {
        let isDark = colorScheme == .dark

        return ZStack {
            // Keycap Body with directional lighting
            Circle()
                .fill(resolvedKeycapColor)
                .frame(width: innerSize, height: innerSize)
                // Directional specular surface lighting overlay
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isDark ? 0.16 : 0.32), location: 0.0),
                                    .init(color: Color.clear, location: 0.45),
                                    .init(color: Color.black.opacity(isDark ? 0.30 : 0.12), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                // Elevated keycap drop shadow cast into outer socket
                .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: innerSize * 0.06, x: 0, y: 2.0)
                .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.08), radius: 1.0, x: 0, y: 1.0)
                // Precision chamfered rim highlight
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isActive ? 0.98 : (isDark ? 0.28 : 0.90)), location: 0.0),
                                    .init(color: Color.white.opacity(isDark ? 0.10 : 0.40), location: 0.40),
                                    .init(color: Color.white.opacity(isDark ? 0.04 : 0.10), location: 0.80),
                                    .init(color: Color.black.opacity(isDark ? 0.25 : 0.08), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                }

            // Custom Icon / Content
            content()
                .rotationEffect(.degrees(rotatesOnTap ? rotationAngle : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.68), value: rotationAngle)
        }
        .frame(width: innerSize, height: innerSize)
    }

    // MARK: - Action Trigger

    private func triggerTap() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)

        if rotatesOnTap {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) {
                rotationAngle += 180
            }
        }

        action?()
    }
}

// MARK: - Convenience Extension for SF Symbols

public extension TactileCircularButton where Content == AnyView {
    init(
        systemImage: String,
        iconColor: Color? = nil,
        keycapColor: Color? = nil,
        bezelColor: Color? = nil,
        size: CGFloat = 62,
        iconSize: CGFloat = 20,
        iconWeight: Font.Weight = .bold,
        isActive: Bool = false,
        rotatesOnTap: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            size: size,
            keycapColor: keycapColor,
            bezelColor: bezelColor,
            isActive: isActive,
            rotatesOnTap: rotatesOnTap,
            action: action
        ) {
            AnyView(
                TactileButtonIconView(
                    systemImage: systemImage,
                    iconColor: iconColor,
                    iconSize: iconSize,
                    iconWeight: iconWeight
                )
            )
        }
    }
}

/// Helper view to resolve adaptive `.primary` iconColor inside SF Symbol convenience button
private struct TactileButtonIconView: View {
    let systemImage: String
    let iconColor: Color?
    let iconSize: CGFloat
    let iconWeight: Font.Weight
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: iconWeight))
            .foregroundStyle(iconColor ?? (colorScheme == .dark ? Color.white : Color.black))
    }
}

// MARK: - Physical Push Button Style

private struct PhysicalButtonStyle: ButtonStyle {
    let innerSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Physical button depression travel
            .offset(y: configuration.isPressed ? 1.6 : 0.0)
            // Micro load compression under finger press
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            // Shadow flattens into socket on touch down
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
                }
            }
    }
}

// MARK: - Specialized Camera Flip Button Preset

/// A specialized preset of `TactileCircularButton` configured specifically for camera flipping (Figma node 140:7191).
public struct CameraFlipButton: View {
    public var action: (() -> Void)?
    @Binding public var isFrontCamera: Bool
    public var size: CGFloat

    public init(
        isFrontCamera: Binding<Bool>,
        size: CGFloat = 62,
        action: (() -> Void)? = nil
    ) {
        self._isFrontCamera = isFrontCamera
        self.size = size
        self.action = action
    }

    public init(
        size: CGFloat = 62,
        action: (() -> Void)? = nil
    ) {
        self._isFrontCamera = .constant(false)
        self.size = size
        self.action = action
    }

    public var body: some View {
        TactileCircularButton(
            systemImage: "arrow.triangle.2.circlepath",
            iconColor: nil,
            size: size,
            iconSize: 20,
            rotatesOnTap: true
        ) {
            isFrontCamera.toggle()
            action?()
        }
        .accessibilityLabel("Flip Camera")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to switch between front and rear cameras")
    }
}

// MARK: - Previews

#Preview("Customizable Button Gallery") {
    struct GalleryPreview: View {
        @State private var isFlashOn: Bool = false
        @State private var isFrontCamera: Bool = false
        @State private var timerSeconds: Int = 3
        @State private var isGridOn: Bool = true
        @State private var isNightMode: Bool = false

        var body: some View {
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.12)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 36) {
                        VStack(spacing: 6) {
                            Text("CUSTOM TACTILE CIRCULAR BUTTONS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.gray)
                            Text("Any Icon • Any Color • Physical Travel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 24)

                        // Row 1: Camera Flip, Flash & Record
                        HStack(spacing: 28) {
                            // 1. Camera Flip (White keycap, black icon, rotates on tap)
                            VStack(spacing: 8) {
                                CameraFlipButton(isFrontCamera: $isFrontCamera)
                                Text("Flip (Rotates)")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }

                            // 2. Flash Toggle (Yellow active state)
                            VStack(spacing: 8) {
                                TactileCircularButton(
                                    systemImage: isFlashOn ? "bolt.fill" : "bolt.slash.fill",
                                    iconColor: isFlashOn ? .yellow : .black,
                                    keycapColor: isFlashOn ? Color(red: 0.98, green: 0.97, blue: 0.90) : Color(red: 0.949, green: 0.949, blue: 0.969),
                                    isActive: isFlashOn
                                ) {
                                    isFlashOn.toggle()
                                }
                                Text(isFlashOn ? "Flash ON" : "Flash OFF")
                                    .font(.caption2)
                                    .foregroundStyle(isFlashOn ? .yellow : .gray)
                            }

                            // 3. Shutter / Record (Red Keycap)
                            VStack(spacing: 8) {
                                TactileCircularButton(
                                    systemImage: "record.circle",
                                    iconColor: .white,
                                    keycapColor: Color(red: 0.92, green: 0.26, blue: 0.21)
                                ) {
                                    print("Record tapped")
                                }
                                Text("Record (Red)")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                        }

                        // Row 2: Timer, Grid, Night Mode
                        HStack(spacing: 28) {
                            // 4. Timer (Custom Text Content ViewBuilder)
                            VStack(spacing: 8) {
                                TactileCircularButton {
                                    timerSeconds = timerSeconds == 3 ? 10 : (timerSeconds == 10 ? 0 : 3)
                                } content: {
                                    VStack(spacing: -2) {
                                        Image(systemName: "timer")
                                            .font(.system(size: 14, weight: .bold))
                                        if timerSeconds > 0 {
                                            Text("\(timerSeconds)s")
                                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                        }
                                    }
                                    .foregroundStyle(timerSeconds > 0 ? Color.orange : Color.black)
                                }
                                Text(timerSeconds > 0 ? "Timer \(timerSeconds)s" : "Timer Off")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }

                            // 5. Grid Toggle (Active Accent Color)
                            VStack(spacing: 8) {
                                TactileCircularButton(
                                    systemImage: "grid",
                                    iconColor: isGridOn ? .white : .black,
                                    keycapColor: isGridOn ? Color(red: 0.22, green: 0.45, blue: 0.98) : Color(red: 0.949, green: 0.949, blue: 0.969),
                                    isActive: isGridOn
                                ) {
                                    isGridOn.toggle()
                                }
                                Text(isGridOn ? "Grid ON" : "Grid OFF")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }

                            // 6. Night Mode (Dark Keycap)
                            VStack(spacing: 8) {
                                TactileCircularButton(
                                    systemImage: "moon.stars.fill",
                                    iconColor: isNightMode ? .yellow : Color(white: 0.7),
                                    keycapColor: Color(red: 0.20, green: 0.20, blue: 0.22),
                                    isActive: isNightMode
                                ) {
                                    isNightMode.toggle()
                                }
                                Text("Night Mode")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }
                        }

                        // Scaled Down Size Demo (e.g. size: 48 pt for compact toolbars)
                        VStack(spacing: 12) {
                            Text("Compact 48pt Variant")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            HStack(spacing: 20) {
                                TactileCircularButton(
                                    systemImage: "sparkles",
                                    iconColor: .purple,
                                    size: 48,
                                    iconSize: 17
                                )

                                TactileCircularButton(
                                    systemImage: "slider.horizontal.3",
                                    iconColor: .black,
                                    size: 48,
                                    iconSize: 17
                                )

                                TactileCircularButton(
                                    systemImage: "livephoto",
                                    iconColor: .orange,
                                    size: 48,
                                    iconSize: 17
                                )
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    return GalleryPreview()
}
