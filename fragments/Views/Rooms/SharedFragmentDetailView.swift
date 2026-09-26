//
//  SharedFragmentDetailView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import AVKit

/// Detail inspection view for a shared fragment with author attribution.
public struct SharedFragmentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let fragment: SharedFragment

    public init(fragment: SharedFragment) {
        self.fragment = fragment
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Media or Content Canvas
                    contentHeaderCanvas

                    // Author Attribution Pill
                    let displayName = fragment.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.18))
                                .frame(width: 34, height: 34)

                            if displayName.isEmpty {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.purple)
                            } else {
                                Text(displayName.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.purple)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName.isEmpty ? "Shared Fragment" : "Captured by \(displayName)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Fragment Type Badge
                        Label(fragment.type.displayName, systemImage: fragment.type.systemIcon)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(fragment.type.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(fragment.type.accentColor.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)

                    // Title & Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fragment.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let subtitle = fragment.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        if let text = fragment.text, !text.isEmpty {
                            Text(text)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.primary.opacity(0.85))
                                .padding(.top, 4)
                        }

                        if let location = fragment.location, !location.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)

                                Text(location)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
                .padding(.top, 10)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var contentHeaderCanvas: some View {
        if let localURL = fragment.mediaReference?.localFileURL,
           FileManager.default.fileExists(atPath: localURL.path),
           fragment.type == .photo,
           let uiImage = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 20)
        } else {
            // Ethereal card presentation for notes, audio, or preview
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                fragment.type.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.20),
                                fragment.type.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)

                VStack(spacing: 12) {
                    Image(systemName: fragment.type.systemIcon)
                        .font(.system(size: 44))
                        .foregroundStyle(fragment.type.accentColor)

                    if fragment.type == .audio, let duration = fragment.duration {
                        Text(duration)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
