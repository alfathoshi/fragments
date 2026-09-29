//
//  SharedFragmentDetailView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import AVKit
import AVFoundation

/// Detail inspection view for a shared fragment with author attribution.
public struct SharedFragmentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let fragment: SharedFragment

    @State private var resolvedLocalURL: URL? = nil
    @State private var isLoadingMedia: Bool = false
    @State private var downloadFailed: Bool = false

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
                    let isCurrentUser = fragment.isAuthoredByCurrentUser
                    let displayName = fragment.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let attributionTitle = isCurrentUser ? "Captured by you" : (displayName.isEmpty ? "Shared Fragment" : "Captured by \(displayName)")
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.18))
                                .frame(width: 34, height: 34)

                            if isCurrentUser || displayName.isEmpty {
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
                            Text(attributionTitle)
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
        .task(id: fragment.mediaReference?.storagePath) {
            await loadMediaIfNeeded()
        }
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
    private var contentHeaderCanvas: some View {
        if let localURL = effectiveLocalURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            switch fragment.type {
            case .photo:
                if isDecodableImageFile(localURL), let uiImage = UIImage(contentsOfFile: localURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 20)
                } else {
                    etherealCard
                }
            case .video:
                SharedVideoPlayerView(url: localURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 20)
            case .audio:
                SharedAudioPlayerCard(fragment: fragment, url: localURL)
                    .padding(.horizontal, 20)
            case .note:
                etherealCard
            }
        } else if isLoadingMedia {
            ZStack {
                etherealCard
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(fragment.type.accentColor)
                    Text("Loading media...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } else if downloadFailed {
            ZStack {
                etherealCard
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(fragment.type.accentColor)
                    Text("Unable to load media")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Button {
                        Task { await loadMediaIfNeeded() }
                    } label: {
                        Text("Tap to retry")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(fragment.type.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(fragment.type.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
        } else {
            etherealCard
        }
    }

    private var etherealCard: some View {
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

    private func loadMediaIfNeeded() async {
        // 1. Guard local optimistic media (Requirement 11: preserve local capture)
        if let local = fragment.mediaReference?.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return
        }

        // 2. Check disk cache hit first (Requirement 5)
        if let cached = RemoteMediaService.shared.cachedMediaURL(for: fragment) {
            resolvedLocalURL = cached
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
            }
        } catch {
            if Task.isCancelled { return }
            await MainActor.run {
                self.isLoadingMedia = false
                self.downloadFailed = true
            }
        }
    }
}

// MARK: - Video & Audio Subviews

private struct SharedVideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                Color.black.opacity(0.15)
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct SharedAudioPlayerCard: View {
    let fragment: SharedFragment
    let url: URL
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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

            VStack(spacing: 14) {
                Button {
                    togglePlayPause()
                } label: {
                    Circle()
                        .fill(fragment.type.accentColor)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying ? 0 : 2)
                        )
                        .shadow(color: fragment.type.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }

                if let duration = fragment.duration {
                    Text(duration)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .onDisappear {
            audioPlayer?.stop()
            audioPlayer = nil
            isPlaying = false
        }
    }

    private func togglePlayPause() {
        if audioPlayer == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}
