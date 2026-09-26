//
//  SharedFragmentNode.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI

/// Visual card component representing a `SharedFragment` inside a collaborative Room.
public struct SharedFragmentNode: View {
    public let fragment: SharedFragment
    public var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false

    public init(fragment: SharedFragment, onTap: @escaping () -> Void) {
        self.fragment = fragment
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                // Media / Icon Top Area
                ZStack(alignment: .topTrailing) {
                    nodeVisualHeader
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Type Badge
                    Image(systemName: fragment.type.systemIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }

                // Title & Author Attribution
                VStack(alignment: .leading, spacing: 3) {
                    Text(fragment.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Subtle Author Attribution
                    if !fragment.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundStyle(resolvedColor)
                                .font(.system(size: 12, weight: .bold))

                            Text(fragment.authorName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 8, x: 0, y: 2)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isPressed)
        }
        .buttonStyle(SharedNodeButtonStyle(isPressed: $isPressed))
    }

    private var resolvedColor: Color {
        if let hex = fragment.accentColorHex {
            return Color.fromRGBAString(hex)
        }
        return fragment.type.accentColor
    }

    @ViewBuilder
    private var nodeVisualHeader: some View {
        if let localURL = fragment.mediaReference?.localFileURL,
           FileManager.default.fileExists(atPath: localURL.path),
           fragment.type == .photo,
           let uiImage = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        resolvedColor.opacity(colorScheme == .dark ? 0.40 : 0.22),
                        resolvedColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if fragment.type == .note, let text = fragment.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(4)
                        .padding(10)
                } else {
                    Image(systemName: fragment.type.systemIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(resolvedColor)
                }
            }
        }
    }
}

private struct SharedNodeButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
