//
//  FloatingCaptureOverlay.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public enum CaptureMenuStage {
    case primary      // 2 options: Start a Moment, Quick Capture
    case suboptions   // 4 options: Photo, Video, Note, Audio
}

public struct FloatingCaptureOverlay: View {
    @Binding public var isOpen: Bool
    @State private var stage: CaptureMenuStage = .primary
    @State private var isExpanded: Bool = false

    public var onSelectStartMoment: () -> Void
    public var onSelectQuickCaptureType: (FragmentType) -> Void

    public init(
        isOpen: Binding<Bool>,
        onSelectStartMoment: @escaping () -> Void,
        onSelectQuickCaptureType: @escaping (FragmentType) -> Void
    ) {
        self._isOpen = isOpen
        self.onSelectStartMoment = onSelectStartMoment
        self.onSelectQuickCaptureType = onSelectQuickCaptureType
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Tap outside to dismiss background
            Button {
                dismissMenu()
            } label: {
                Color.black.opacity(isExpanded ? 0.32 : 0.0)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isExpanded)

            // Floating Orbs Stack (Expands directly above the bottom-right capture button)
            VStack(alignment: .trailing, spacing: 18) {
                switch stage {
                case .primary:
                    primaryOrbs
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 12)),
                            removal: .scale(scale: 0.6, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        ))

                case .suboptions:
                    suboptionsOrbs
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 12)),
                            removal: .scale(scale: 0.6, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        ))
                }
            }
            .scaleEffect(isExpanded ? 1.0 : 0.05, anchor: .bottomTrailing)
            .offset(x: isExpanded ? 0 : 15, y: isExpanded ? 0 : 25)
            .opacity(isExpanded ? 1.0 : 0.0)
            .padding(.trailing, 27)
            .padding(.bottom, 72) // Positioned directly over the trailing tab button
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.70), value: isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: stage)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) {
                isExpanded = true
            }
        }
    }

    // MARK: - 1. Primary Orbs (2 Options)
    private var primaryOrbs: some View {
        VStack(alignment: .trailing, spacing: 18) {
            // Option 1: Start a Moment
            orbRow(
                title: "Start a Moment",
                icon: "sparkles.rectangle.stack.fill",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                dismissMenu {
                    onSelectStartMoment()
                }
            }

            // Option 2: Quick Capture (Expands into 4 options)
            orbRow(
                title: "Quick Capture",
                icon: "bolt.fill",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    stage = .suboptions
                }
            }
        }
    }

    // MARK: - 2. Sub-options Orbs (4 Types)
    private var suboptionsOrbs: some View {
        VStack(alignment: .trailing, spacing: 16) {

            // 1. Photo
            orbRow(
                title: "Photo",
                icon: "photo.fill",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                dismissMenu {
                    onSelectQuickCaptureType(.photo)
                }
            }

            // 2. Video
            orbRow(
                title: "Video",
                icon: "video.fill",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                dismissMenu {
                    onSelectQuickCaptureType(.video)
                }
            }

            // 3. Note
            orbRow(
                title: "Note",
                icon: "text.quote",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                dismissMenu {
                    onSelectQuickCaptureType(.note)
                }
            }

            // 4. Audio
            orbRow(
                title: "Memo",
                icon: "waveform",
                gradient: [.white, .black],
                shadowColor: Color.white
            ) {
                dismissMenu {
                    onSelectQuickCaptureType(.audio)
                }
            }
        }
    }

    // MARK: - Helper Row with 3D Orb & Label
    private func orbRow(
        title: String,
        icon: String,
        gradient: [Color],
        shadowColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Glassmorphic label pill on the left of orb
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                // 3D Glass Sphere / Orb
                GlassOrb(icon: icon, gradient: gradient, shadowColor: shadowColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbScaleButtonStyle())
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            isOpen = false
            completion?()
        }
    }
}

// MARK: - 3D Glass Orb Component (Matching Reference Design)
public struct GlassOrb: View {
    public let icon: String
    public let gradient: [Color]
    public let shadowColor: Color
    public var size: CGFloat = 54

    public init(icon: String, gradient: [Color], shadowColor: Color, size: CGFloat = 54) {
        self.icon = icon
        self.gradient = gradient
        self.shadowColor = shadowColor
        self.size = size
    }

    public var body: some View {
        ZStack {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
                .frame(width: size, height: size)
                .adaptiveGlassEffect(.clear, in: Circle())
        }
        
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

// MARK: - Button Press Feedback Style
private struct OrbScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingCaptureOverlay(
            isOpen: .constant(true),
            onSelectStartMoment: {},
            onSelectQuickCaptureType: { _ in }
        )
    }
}

struct FloatingCaptureOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FloatingCaptureOverlay(
                isOpen: .constant(true),
                onSelectStartMoment: {},
                onSelectQuickCaptureType: { _ in }
            )
        }
    }
}
#endif
