//
//  SharedFragmentNode.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import AVFoundation

/// Visual card component representing a `SharedFragment` inside a collaborative Room.
public struct SharedFragmentNode: View {
    public let fragment: SharedFragment
    public var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false
    @State private var resolvedLocalURL: URL? = nil
    @State private var isLoadingMedia: Bool = false
    @State private var downloadFailed: Bool = false
    @State private var videoThumbnail: UIImage? = nil

    private static let nodeThumbnailCache = NSCache<NSString, UIImage>()

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
                    let authorDisplayName: String = fragment.isAuthoredByCurrentUser ? "You" : fragment.authorName
                    if !authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundStyle(resolvedColor)
                                .font(.system(size: 12, weight: .bold))

                            Text(authorDisplayName)
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
        .task(id: fragment.mediaReference?.storagePath) {
            await loadMediaIfNeeded()
        }
        .onChange(of: effectiveLocalURL) { _, newURL in
            if let newURL = newURL, fragment.type == .video {
                loadVideoThumbnail(from: newURL)
            }
        }
    }

    private var resolvedColor: Color {
        if let hex = fragment.accentColorHex {
            return Color.fromRGBAString(hex)
        }
        return fragment.type.accentColor
    }

    /// Resolves local media URL with precedence:
    /// 1. Optimistic localFileURL (author capture)
    /// 2. In-memory resolved local URL
    /// 3. Fast synchronous cache lookup in `Library/Caches/Rooms/{roomID}/media/`
    private var effectiveLocalURL: URL? {
        if let local = fragment.mediaReference?.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        if let resolved = resolvedLocalURL, FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }
        return RemoteMediaService.shared.cachedMediaURL(for: fragment)
    }

    @ViewBuilder
    private var nodeVisualHeader: some View {
        if let localURL = effectiveLocalURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            if fragment.type == .photo, isDecodableImageFile(localURL), let uiImage = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if fragment.type == .video {
                if let thumb = videoThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderHeader
                        .onAppear {
                            loadVideoThumbnail(from: localURL)
                        }
                }
            } else {
                placeholderHeader
            }
        } else if isLoadingMedia {
            ZStack {
                placeholderHeader
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
            }
        } else if downloadFailed {
            ZStack {
                placeholderHeader
                VStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Retry")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        } else {
            placeholderHeader
        }
    }

    @ViewBuilder
    private var placeholderHeader: some View {
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

    private func loadMediaIfNeeded() async {
        // 1. Guard local optimistic media (Requirement 11: preserve local capture)
        if let local = fragment.mediaReference?.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            if fragment.type == .video {
                loadVideoThumbnail(from: local)
            }
            return
        }

        // 2. Check disk cache hit first (Requirement 5)
        if let cached = RemoteMediaService.shared.cachedMediaURL(for: fragment) {
            resolvedLocalURL = cached
            if fragment.type == .video {
                loadVideoThumbnail(from: cached)
            }
            return
        }

        // 3. Storage path check
        guard let storagePath = fragment.mediaReference?.storagePath, !storagePath.isEmpty else {
            return
        }

        // 4. Download remote media
        isLoadingMedia = true
        downloadFailed = false

        do {
            let downloadedURL = try await RemoteMediaService.shared.localMediaURL(for: fragment)
            await MainActor.run {
                self.resolvedLocalURL = downloadedURL
                self.isLoadingMedia = false
                self.downloadFailed = false
                if self.fragment.type == .video {
                    self.loadVideoThumbnail(from: downloadedURL)
                }
            }
        } catch {
            if Task.isCancelled { return }
            await MainActor.run {
                self.isLoadingMedia = false
                self.downloadFailed = true
            }
        }
    }

    private func loadVideoThumbnail(from url: URL) {
        let key = url.lastPathComponent as NSString
        if let cached = Self.nodeThumbnailCache.object(forKey: key) {
            self.videoThumbnail = cached
            return
        }

        Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 300, height: 300)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let img = UIImage(cgImage: cgImage)
                Self.nodeThumbnailCache.setObject(img, forKey: key)
                await MainActor.run {
                    self.videoThumbnail = img
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
