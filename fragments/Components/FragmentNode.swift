//
//  FragmentNode.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public struct FragmentNode: View {
    public let fragment: Fragment
    public let normalizedZ: CGFloat
    public var onTap: (() -> Void)? = nil

    @State private var isPressed = false

    public init(
        fragment: Fragment,
        normalizedZ: CGFloat = 1.0,
        onTap: (() -> Void)? = nil
    ) {
        self.fragment = fragment
        self.normalizedZ = normalizedZ
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            onTap?()
        } label: {
            contentForType
                .frame(width: fragment.baseSize.width, height: fragment.baseSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(NodeButtonStyle(isPressed: $isPressed))
    }

    // MARK: - Node Content by Type

    @ViewBuilder
    private var contentForType: some View {
        switch fragment.type {
        case .photo:
            photoNode
        case .video:
            videoNode
        case .audio:
            audioNode
        case .note:
            noteNode
        }
    }

    // MARK: - 1. Photo Node
    private var photoNode: some View {
        ZStack(alignment: .bottomLeading) {
            // Visual Photo Representation (Real image from Resources or gradient placeholder)
            if let image = fragment.loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: fragment.baseSize.width, height: fragment.baseSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: fragment.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Inner visual motif / symbol
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: fragment.mediaSymbol ?? "photo")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.40))
                            .offset(x: 8, y: 8)
                    }
                }
            }

            // Subtle dark gradient overlay for depth & readability
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Label tag (visible when reasonably close)
            if normalizedZ > 0.45 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(fragment.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 3)

                    if let subtitle = fragment.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: fragment.baseSize.width, height: fragment.baseSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(normalizedZ > 0.6 ? 0.35 : 0.15), lineWidth: 1.0)
        )
        .shadow(
            color: fragment.gradientColors.first?.opacity(Double(normalizedZ) * 0.35) ?? .clear,
            radius: 12,
            y: 6
        )
    }

    // MARK: - 2. Video Node
    private var videoNode: some View {
        ZStack {
            // Video Thumbnail Backdrop (Real thumbnail frame from Resources or gradient)
            if let thumb = fragment.videoThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: fragment.baseSize.width, height: fragment.baseSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: fragment.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Center Play Icon in frosted circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 6)

            // Duration badge in top right
            if let duration = fragment.duration, normalizedZ > 0.4 {
                VStack {
                    HStack {
                        Spacer()
                        Text(duration)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(6)
            }

            // Title in bottom
            if normalizedZ > 0.5 {
                VStack {
                    Spacer()
                    HStack {
                        Text(fragment.title)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: fragment.baseSize.width, height: fragment.baseSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(normalizedZ > 0.6 ? 0.35 : 0.15), lineWidth: 1.0)
        )
        .shadow(
            color: fragment.gradientColors.first?.opacity(Double(normalizedZ) * 0.35) ?? .clear,
            radius: 12,
            y: 6
        )
    }

    // MARK: - 3. Audio Node
    private var audioNode: some View {
        ZStack {
            // Frosted tactile capsule/card
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            fragment.gradientColors.first?.opacity(0.85) ?? Color.teal,
                            fragment.gradientColors.last?.opacity(0.95) ?? Color.teal.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text(fragment.duration ?? "0:08")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 4, height: 4)
                }

                // Waveform bars
                HStack(alignment: .center, spacing: 2.5) {
                    let bars = fragment.audioWaveform.isEmpty
                        ? [0.3, 0.7, 1.0, 0.5, 0.9, 0.4, 0.8, 0.6]
                        : fragment.audioWaveform

                    ForEach(0..<min(bars.count, 12), id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: max(5, CGFloat(bars[idx]) * 24))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if normalizedZ > 0.45 {
                    Text(fragment.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(normalizedZ > 0.6 ? 0.35 : 0.15), lineWidth: 1.0)
        )
        .shadow(
            color: (fragment.gradientColors.first ?? Color.teal).opacity(Double(normalizedZ) * 0.35),
            radius: 12,
            y: 6
        )
    }

    // MARK: - 4. Note Node
    private var noteNode: some View {
        ZStack(alignment: .topLeading) {
            // Elegant Frosted Paper Card
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            fragment.gradientColors.first?.opacity(0.92) ?? Color.orange,
                            fragment.gradientColors.last?.opacity(0.95) ?? Color.brown
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.75))

                    Spacer()

                    Text("Note")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.6))
                        .textCase(.uppercase)
                }

                if let text = fragment.text {
                    Text(text)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .foregroundStyle(.black)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(fragment.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(normalizedZ > 0.6 ? 0.35 : 0.15), lineWidth: 1.0)
        )
        .shadow(
            color: (fragment.gradientColors.first ?? Color.orange).opacity(Double(normalizedZ) * 0.35),
            radius: 12,
            y: 6
        )
    }
}

// MARK: - Custom Button Style for Gentle Tap Feedback

private struct NodeButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
