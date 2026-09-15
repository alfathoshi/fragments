//
//  RockerSwitch.swift
//  fragments
//
//  Created on 9/14/26.
//

import SwiftUI

// MARK: - Option Enum

public enum RockerSwitchOption: String, CaseIterable, Identifiable, Sendable {
    case point5X = "0.5x"
    case oneX = "1x"
    case twoX = "2x"

    public var id: String { rawValue }
}

public typealias TactileDualButtonOption = RockerSwitchOption

// MARK: - Tactile Dual Button Component

/// A precision physical hardware dual-button control faithful to Figma node 185:2206.
/// Features two distinct physical buttons in a single milled housing where only one
/// can be active at a time:
/// - Independent physical button travel (press-down depression & spring rebound)
/// - Directional chamfered bevels and specular edge reflections
/// - Ambient cavity shadows and contact floor drop shadows
/// - Authentic dual-stage haptic response (press down + click release)
/// - Mutually exclusive selection
public struct RockerSwitch: View {
    // MARK: - Properties

    @Environment(\.colorScheme) private var colorScheme
    @Binding public var selection: RockerSwitchOption

    public var leftLabel: String
    public var rightLabel: String
    public var onSelectionChanged: ((RockerSwitchOption) -> Void)?

    // MARK: - Figma Dimensions (115 x 48 pt outer, 97 x 30 pt trench)

    private let outerWidth: CGFloat = 115
    private let outerHeight: CGFloat = 48
    private let trenchWidth: CGFloat = 97
    private let trenchHeight: CGFloat = 30
    private let buttonWidth: CGFloat = 45.5
    private let buttonHeight: CGFloat = 28

    // MARK: - Initializers

    public init(
        selection: Binding<RockerSwitchOption>,
        leftLabel: String = "1x",
        rightLabel: String = "2x",
        onSelectionChanged: ((RockerSwitchOption) -> Void)? = nil
    ) {
        self._selection = selection
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
        self.onSelectionChanged = onSelectionChanged
    }

    public init(
        initialOption: RockerSwitchOption = .oneX,
        leftLabel: String = "1x",
        rightLabel: String = "2x",
        onSelectionChanged: ((RockerSwitchOption) -> Void)? = nil
    ) {
        self._selection = .constant(initialOption)
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
        self.onSelectionChanged = onSelectionChanged
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // 1. Heavy Outer Bezel Housing
            outerBezel

            // 2. Milled Cavity Trench
            innerTrench

            // 3. Center Axle / Divider Slot
//            centerDivider

            // 4. Two Independent Physical Buttons
            HStack(spacing: 2) {
                // Button 1 (Left / 1x)
                Button {
                    select(.oneX)
                } label: {
                    buttonSurface(
                        label: leftLabel,
                        isSelected: selection == .oneX,
                        isLeft: true
                    )
                }
                .buttonStyle(PhysicalPushButtonStyle(isSelected: selection == .oneX, isLeft: true))

                // Button 2 (Right / 2x)
                Button {
                    select(.twoX)
                } label: {
                    buttonSurface(
                        label: rightLabel,
                        isSelected: selection == .twoX,
                        isLeft: false
                    )
                }
                .buttonStyle(PhysicalPushButtonStyle(isSelected: selection == .twoX, isLeft: false))
            }
            .frame(width: trenchWidth - 4, height: trenchHeight)
        }
        .frame(width: outerWidth, height: outerHeight)
        .contentShape(Capsule())
        // Accessibility
        .accessibilityElement(children: .contain)
    }

    // MARK: - 1. Outer Housing Bezel

    private var outerBezel: some View {
        let isDark = colorScheme == .dark

        return Capsule()
            // High-grade satin matte finish (#E3E4E8 or dark hardware in dark mode)
            .fill(
                LinearGradient(
                    stops: isDark ? [
                        .init(color: Color(red: 0.22, green: 0.22, blue: 0.24), location: 0.0),
                        .init(color: Color(red: 0.17, green: 0.17, blue: 0.19), location: 0.7),
                        .init(color: Color(red: 0.14, green: 0.14, blue: 0.16), location: 1.0)
                    ] : [
                        .init(color: Color(red: 0.905, green: 0.910, blue: 0.925), location: 0.0),
                        .init(color: Color(red: 0.885, green: 0.890, blue: 0.905), location: 0.7),
                        .init(color: Color(red: 0.865, green: 0.870, blue: 0.885), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Deep socket top inner shadow (inset 0px 3px 6.7px rgba(97,99,109,0.61))
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: (isDark ? Color.black : Color(red: 0.35, green: 0.36, blue: 0.40)).opacity(isDark ? 0.90 : 0.70), location: 0.0),
                                .init(color: (isDark ? Color.black : Color(red: 0.35, green: 0.36, blue: 0.40)).opacity(isDark ? 0.45 : 0.25), location: 0.35),
                                .init(color: Color.clear, location: 0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3.2
                    )
                    .blur(radius: 2.0)
                    .mask(Capsule())
            }
            // Crisp bottom specular chamfer highlight (light hitting bottom rim)
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.clear, location: 0.35),
                                .init(color: Color.white.opacity(isDark ? 0.15 : 0.45), location: 0.80),
                                .init(color: Color.white.opacity(isDark ? 0.30 : 0.85), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
    }

    // MARK: - 2. Milled Trench Cavity

    private var innerTrench: some View {
        let isDark = colorScheme == .dark

        return Capsule()
            // Recessed trench floor (#F0F0F2 or sunken obsidian)
            .fill(
                LinearGradient(
                    stops: isDark ? [
                        .init(color: Color(red: 0.09, green: 0.09, blue: 0.11), location: 0.0),
                        .init(color: Color(red: 0.11, green: 0.11, blue: 0.13), location: 0.5),
                        .init(color: Color(red: 0.10, green: 0.10, blue: 0.12), location: 1.0)
                    ] : [
                        .init(color: Color(red: 0.925, green: 0.925, blue: 0.935), location: 0.0),
                        .init(color: Color(red: 0.945, green: 0.945, blue: 0.952), location: 0.5),
                        .init(color: Color(red: 0.935, green: 0.935, blue: 0.942), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: trenchWidth, height: trenchHeight)
            // Trench edge bevel & bottom lip shadow (inset 0px -5px 7.1px rgba(0,0,0,0.17))
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(isDark ? 0.55 : 0.24), location: 0.0),
                                .init(color: Color.clear, location: 0.30),
                                .init(color: Color.clear, location: 0.65),
                                .init(color: Color.black.opacity(isDark ? 0.45 : 0.18), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.6
                    )
                    .blur(radius: 1.2)
                    .mask(Capsule())
            }
    }

    // MARK: - 3. Center Divider Slot

    private var centerDivider: some View {
        ZStack {
            // Milled dark slot / physical gap (#4A4A4D)
            Capsule()
                .fill(Color(red: 0.55, green: 0.55, blue: 0.58))
                .frame(width: 0.8, height: 22)

            // Specular reflection crest on the illuminated ridge
            Capsule()
                .fill(Color.white.opacity(0.70))
                .frame(width: 0.5, height: 21)
                .offset(x: 0.4)
        }
    }

    // MARK: - 4. Button Surface

    private func buttonSurface(label: String, isSelected: Bool, isLeft: Bool) -> some View {
        let isDark = colorScheme == .dark

        return ZStack {
            // Base Button Shape
            if isSelected {
                // Active Raised Keycap (white ceramic/plastic or dark hardware)
                activeKeycapShape(isLeft: isLeft)
            } else {
                // Inactive Resting Keycap (recessed satin metallic)
                inactiveKeycapShape(isLeft: isLeft)
            }

            // Button Label Text
            ZStack {
                // Subtle highlight shadow under active text
                if isSelected {
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.6))
                        .offset(y: 0.5)
                }

                Text(label)
                    .font(.system(size: 16, weight: .bold ))
                    .foregroundStyle(
                        isDark
                            ? (isSelected ? Color(white: 0.45) : Color.white)
                            : (isSelected ? Color(red: 0.608, green: 0.608, blue: 0.608) : Color(red: 0.106, green: 0.106, blue: 0.106))
                    )
            }
        }
        .frame(width: buttonWidth, height: buttonHeight)
        .contentShape(
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 14 : 3,
                bottomLeadingRadius: isLeft ? 14 : 3,
                bottomTrailingRadius: isLeft ? 3 : 14,
                topTrailingRadius: isLeft ? 3 : 14,
                style: .continuous
            )
        )
    }

    // Active Keycap Appearance
    private func inactiveKeycapShape(isLeft: Bool) -> some View {
        let isDark = colorScheme == .dark

        return UnevenRoundedRectangle(
            topLeadingRadius: isLeft ? 14 : 3,
            bottomLeadingRadius: isLeft ? 14 : 3,
            bottomTrailingRadius: isLeft ? 3 : 14,
            topTrailingRadius: isLeft ? 3 : 14,
            style: .continuous
        )
        .fill(
            LinearGradient(
                stops: isDark ? [
                    .init(color: Color(red: 0.30, green: 0.30, blue: 0.33), location: 0.0),
                    .init(color: Color(red: 0.25, green: 0.25, blue: 0.28), location: 0.50),
                    .init(color: Color(red: 0.21, green: 0.21, blue: 0.24), location: 0.85),
                    .init(color: Color(red: 0.18, green: 0.18, blue: 0.21), location: 1.0)
                ] : [
                    .init(color: Color.white, location: 0.0),
                    .init(color: Color(red: 0.985, green: 0.985, blue: 0.990), location: 0.50),
                    .init(color: Color(red: 0.950, green: 0.952, blue: 0.960), location: 0.85),
                    .init(color: Color(red: 0.925, green: 0.930, blue: 0.940), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Physical elevation drop shadow onto the trench
        .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 3.5, x: isLeft ? -1 : 1, y: 2.0)
        .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.08), radius: 1.0, x: 0, y: 1.0)
        .overlay {
            // Chamfered top highlight rim
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 14 : 3,
                bottomLeadingRadius: isLeft ? 14 : 3,
                bottomTrailingRadius: isLeft ? 3 : 14,
                topTrailingRadius: isLeft ? 3 : 14,
                style: .continuous
            )
            .strokeBorder(
                LinearGradient(
                    stops: isDark ? [
                        .init(color: Color.white.opacity(0.35), location: 0.0),
                        .init(color: Color.white.opacity(0.12), location: 0.40),
                        .init(color: Color.white.opacity(0.04), location: 0.80),
                        .init(color: Color.black.opacity(0.30), location: 1.0)
                    ] : [
                        .init(color: Color.white, location: 0.0),
                        .init(color: Color.white.opacity(0.65), location: 0.40),
                        .init(color: Color.white.opacity(0.20), location: 0.80),
                        .init(color: Color.black.opacity(0.06), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.0
            )
        }
    }

    // Inactive Keycap Appearance
    private func activeKeycapShape(isLeft: Bool) -> some View {
        let isDark = colorScheme == .dark

        return UnevenRoundedRectangle(
            topLeadingRadius: isLeft ? 14 : 3,
            bottomLeadingRadius: isLeft ? 14 : 3,
            bottomTrailingRadius: isLeft ? 3 : 14,
            topTrailingRadius: isLeft ? 3 : 14,
            style: .continuous
        )
        .fill(
            LinearGradient(
                stops: isDark ? [
                    .init(color: Color(red: 0.13, green: 0.13, blue: 0.15), location: 0.0),
                    .init(color: Color(red: 0.15, green: 0.15, blue: 0.17), location: 0.50),
                    .init(color: Color(red: 0.13, green: 0.13, blue: 0.15), location: 1.0)
                ] : [
                    .init(color: Color(red: 0.880, green: 0.885, blue: 0.898), location: 0.0),
                    .init(color: Color(red: 0.895, green: 0.900, blue: 0.912), location: 0.50),
                    .init(color: Color(red: 0.875, green: 0.880, blue: 0.892), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Sunken ambient shadow along the top edge
        .overlay {
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(isDark ? 0.35 : 0.14), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5)

                Spacer()
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: isLeft ? 14 : 3,
                    bottomLeadingRadius: isLeft ? 14 : 3,
                    bottomTrailingRadius: isLeft ? 3 : 14,
                    topTrailingRadius: isLeft ? 3 : 14,
                    style: .continuous
                )
            )
        }
    }

    // MARK: - Selection Handler

    private func select(_ option: RockerSwitchOption) {
        guard selection != option else {
            // Already active: light tactile tap rebound
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            return
        }

        // Mechanical switch click
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
            selection = option
        }
        onSelectionChanged?(option)
    }
}

// MARK: - Physical Push Button Style (Authentic Mechanical Travel)

private struct PhysicalPushButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isLeft: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Physical button travel depression
            .offset(y: configuration.isPressed ? 1.4 : 0.0)
            // Micro load compression under finger press
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            // Shadow compresses down onto floor when pressed
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.75), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    // Soft contact haptic on finger touch-down
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                }
            }
    }
}

// MARK: - Previews

#Preview("Interactive 2-Button Demo") {
    struct DualButtonPreview: View {
        @State private var activeZoom: RockerSwitchOption = .oneX

        var body: some View {
            ZStack {
                // Camera dark viewfinder canvas
                Color(red: 0.11, green: 0.11, blue: 0.12)
                    .ignoresSafeArea()

                VStack(spacing: 36) {
                    VStack(spacing: 8) {
                        Text("TACTILE DUAL-BUTTON CONTROL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.gray)
                        Text("Active Button: \(activeZoom.rawValue)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Each button depresses physically on press. Tap either button to select.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // The 2-Button Component
                    RockerSwitch(selection: $activeZoom)

                    HStack(spacing: 16) {
                        Button("Tap 1x") {
                            withAnimation { activeZoom = .oneX }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button("Tap 2x") {
                            withAnimation { activeZoom = .twoX }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
            }
        }
    }

    return DualButtonPreview()
}

#Preview("Both Button States (Figma Spec)") {
    ZStack {
        Color(red: 0.11, green: 0.11, blue: 0.12)
            .ignoresSafeArea()

        VStack(spacing: 40) {
            VStack(spacing: 10) {
                Text("Left Button (1x) Active")
                    .font(.caption)
                    .foregroundStyle(.gray)
                RockerSwitch(initialOption: .oneX)
            }

            VStack(spacing: 10) {
                Text("Right Button (2x) Active")
                    .font(.caption)
                    .foregroundStyle(.gray)
                RockerSwitch(initialOption: .twoX)
            }
        }
    }
}

#Preview("Camera Viewfinder Context") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            // Viewfinder Top Bar
            HStack {
                Image(systemName: "bolt.fill")
                Spacer()
                Text("PHOTO")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.yellow)
                Spacer()
                Image(systemName: "timer")
            }
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            // Viewfinder Focus Area
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(height: 380)
                .padding(.horizontal, 16)
                .overlay {
                    VStack {
                        Spacer()
                        // 2-Button Physical Zoom Control
                        RockerSwitch(initialOption: .oneX)
                            .padding(.bottom, 24)
                    }
                }

            Spacer()

            // Shutter
            Circle()
                .strokeBorder(Color.white, lineWidth: 4)
                .background(Circle().fill(Color.white))
                .frame(width: 72, height: 72)
                .padding(.bottom, 36)
        }
    }
}
