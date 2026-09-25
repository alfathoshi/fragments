//
//  FragmentDetailView.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI
import AVKit
import AVFoundation

public struct FragmentDetailView: View {
    public let fragment: Fragment
    public var onAddToMoment: ((Fragment, String) -> Void)? = nil
    public var onDelete: ((Fragment) -> Void)? = nil
    public var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var preloadedImage: UIImage? = nil
    @State private var isPlayingAudio: Bool = false
    @State private var isPlayingVideo: Bool = false
    @State private var audioPlaybackProgress: Double = 0.0
    @State private var playbackTimer: Timer? = nil
    @State private var showShareSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    // Real Media Players
    @State private var avPlayer: AVPlayer? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil

    public init(
        fragment: Fragment,
        onAddToMoment: ((Fragment, String) -> Void)? = nil,
        onDelete: ((Fragment) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.fragment = fragment
        self.onAddToMoment = onAddToMoment
        self.onDelete = onDelete
        self.onDismiss = onDismiss

        if fragment.type == .photo {
            self._preloadedImage = State(initialValue: fragment.loadedImage)
        }

        if fragment.type == .video, let url = fragment.mediaURL {
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            self._avPlayer = State(initialValue: player)
            self._isPlayingVideo = State(initialValue: true)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Tap outside background scrim
            Color.black.opacity(colorScheme == .dark ? 0.001 : 0.001)
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Center: Floating Media View (Smooth spring scale pop-in & fade)
            VStack {
                Spacer(minLength: 40)
                floatingFragmentSection
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .scale(scale: 0.90).combined(with: .opacity)
                )
            )

            // Bottom: Bottom Description & Actions Dock (Smooth slide-up & fade)
            bottomDescriptionCard
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [fragment.title, fragment.text ?? ""])
        }
        .alert("Delete Fragment?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?(fragment)
                onDismiss()
            }
        } message: {
            Text("Are you sure you want to remove this fragment from your floating space?")
        }
        .onAppear {
            if fragment.type == .video {
                setupAutoPlayVideo()
            }
        }
        .onDisappear {
            avPlayer?.pause()
            avPlayer = nil
            audioPlayer?.stop()
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }

    private func setupAutoPlayVideo() {
        guard fragment.type == .video, let url = fragment.mediaURL else { return }

        let player = avPlayer ?? AVPlayer(url: url)
        player.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        self.avPlayer = player
        self.isPlayingVideo = true
        player.play()
    }

    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack {
            // Type Pill
            HStack(spacing: 6) {
                Image(systemName: fragment.type.systemIcon)
                    .font(.system(size: 12, weight: .bold))
                Text(fragment.type.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.8 : 0.9))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(.primary.opacity(0.3), lineWidth: 1)
            )

            Spacer()

            // Close Button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .glassCircleButtonStyle()
        }
    }

    // MARK: - Floating Fragment Section
    @ViewBuilder
    private var floatingFragmentSection: some View {
        Group {
            switch fragment.type {
            case .photo:
                floatingPhotoCard

            case .video:
                floatingVideoCard

            case .audio:
                floatingAudioCard

            case .note:
                stickyNoteCard(note: fragment)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Absorb taps on media so tapping controls/media doesn't dismiss view
        }
    }

    // MARK: - Aspect Ratio & Sizing Calculation
    private func calculateFittedMediaSize(aspect: CGFloat, maxBoundingWidth: CGFloat = 340, maxBoundingHeight: CGFloat = 380) -> CGSize {
        guard aspect > 0 else {
            return CGSize(width: maxBoundingWidth, height: 260)
        }
        let boundingAspect = maxBoundingWidth / maxBoundingHeight
        if aspect > boundingAspect {
            // Wider than bounding box (e.g. landscape 16:9 or 4:3)
            let width = maxBoundingWidth
            let height = max(140, min(maxBoundingHeight, width / aspect))
            return CGSize(width: width, height: height)
        } else {
            // Taller than bounding box (e.g. portrait 9:16 or 3:4)
            let height = maxBoundingHeight
            let width = max(140, min(maxBoundingWidth, height * aspect))
            return CGSize(width: width, height: height)
        }
    }

    // MARK: - Floating Photo Card
    private var floatingPhotoCard: some View {
        Group {
            if let img = preloadedImage ?? fragment.loadedImage {
                let imgAspect = (img.size.width > 0 && img.size.height > 0) ? (img.size.width / img.size.height) : 1.0
                let fittedSize = calculateFittedMediaSize(aspect: imgAspect, maxBoundingWidth: 340, maxBoundingHeight: 380)

                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: fragment.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 260)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: fragment.mediaSymbol ?? "photo.fill")
                                .font(.system(size: 64, weight: .thin))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
            }
        }
    }

    // MARK: - Floating Video Card
    private var floatingVideoCard: some View {
        Group {
            if let url = fragment.mediaURL {
                let thumb = fragment.videoThumbnail
                let aspect: CGFloat = {
                    if let t = thumb, t.size.width > 0, t.size.height > 0 {
                        return t.size.width / t.size.height
                    }
                    return 9.0 / 16.0
                }()
                let fittedSize = calculateFittedMediaSize(aspect: aspect, maxBoundingWidth: 340, maxBoundingHeight: 380)

                ZStack {
                    if let player = avPlayer {
                        VideoPlayer(player: player)
                            .frame(width: fittedSize.width, height: fittedSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                        if !isPlayingVideo {
                            Button {
                                player.play()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isPlayingVideo = true
                                }
                            } label: {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundStyle(.white)
                                            .offset(x: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 12)
                            }
                        }
                    } else {
                        ZStack {
                            if let thumb = thumb {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: fittedSize.width, height: fittedSize.height)
                                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: fragment.gradientColors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: fittedSize.width, height: fittedSize.height)
                            }

                            // Play Button
                            Button {
                                setupAutoPlayVideo()
                            } label: {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundStyle(.white)
                                            .offset(x: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 12)
                            }
                        }
                    }
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 12)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: fragment.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 260)
                    .overlay(
                        Image(systemName: fragment.mediaSymbol ?? "video.fill")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(.white.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 12)
            }
        }
    }

    // MARK: - Floating Audio Card
    private var floatingAudioCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Memo")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(fragment.duration ?? "0:05")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Button {
                    toggleAudioPlayback()
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: isPlayingAudio ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(fragment.gradientColors.first ?? Color.teal)
                                .offset(x: isPlayingAudio ? 0 : 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Dynamic Waveform with Traveling Playhead (matching CustomMemoView)
            let rawBars = fragment.audioWaveform.isEmpty
                ? [0.2, 0.45, 0.85, 0.35, 0.6, 1.0, 0.75, 0.4, 0.8, 0.5, 0.9, 0.3, 0.6, 0.7, 0.4, 0.8, 0.5, 0.35, 0.9, 0.65, 0.4, 0.75, 0.55, 0.3]
                : fragment.audioWaveform

            ZStack(alignment: .leading) {
                // Stationary bars: FIXED X POSITIONS, NO JIGGLE
                HStack(spacing: 3.5) {
                    ForEach(0..<rawBars.count, id: \.self) { idx in
                        let barHeight = max(6.0, CGFloat(rawBars[idx]) * 44.0)
                        let isPlayed = isPlayingAudio && (Double(idx) / Double(max(1, rawBars.count - 1))) <= audioPlaybackProgress

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(
                                isPlayed
                                    ? Color.white
                                    : Color.white.opacity(0.35)
                            )
                            .frame(width: 3.0, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Playhead indicator traveling across waveform
                if isPlayingAudio {
                    GeometryReader { geo in
                        let playheadX = geo.size.width * CGFloat(audioPlaybackProgress)

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2.0, height: 48)
                            .shadow(color: Color.white.opacity(0.8), radius: 4)
                            .position(x: max(2, min(playheadX, geo.size.width - 2)), y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 20)

            if let text = fragment.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            } else {
                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: 340)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: fragment.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }

    // MARK: - Sticky Note Card (matching CustomNoteView / Figma Node 178:3051)
    private func stickyNoteCard(note: Fragment) -> some View {
        let noteColor = note.gradientColors.first ?? Color(red: 1.0, green: 0.859, blue: 0.576) // #FFDB93 Butterscotch Yellow

        return ZStack(alignment: .topLeading) {
            // Background Paper: with 4pt solid white border and 24pt corner radius
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(noteColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 4)
                )
                .shadow(
                    color: Color.black.opacity(0.16),
                    radius: 20,
                    x: 0,
                    y: 10
                )
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: 5,
                    x: 0,
                    y: 2
                )

            // Content: Title field + Scrollable Body Text + Date indicator
            VStack(alignment: .leading, spacing: 6) {
                // Title Row
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.black)

                    Text(note.title.isEmpty ? "Note" : note.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Divider()
                    .overlay(Color.black.opacity(0.12))
                    .padding(.horizontal, 16)

                // Body Text
                ScrollView {
                    Text(note.text ?? note.title)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                .frame(maxHeight: .infinity)

                // Small bottom-right date indicator
                HStack {
                    Spacer()
                    Text(note.formattedTimestamp)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: 330, maxHeight: 260)
        .rotationEffect(.degrees(1.5))
        .environment(\.colorScheme, .light)
    }

    // MARK: - Bottom Description & Metadata Dock
    private var bottomDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            topHeaderBar
            
            // Title & optional caption
            VStack(alignment: .leading, spacing: 4) {
                Text(fragment.title.isEmpty ? fragment.type.displayName : fragment.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if fragment.type != .note, let text = fragment.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Metadata Row (Timestamp, 24h Expiration, & Location)
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text(fragment.formattedTimestamp)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11))
                    Text(fragment.timeRemainingText)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)

                if let loc = fragment.location, !loc.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                        Text(loc)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Secondary Actions (Share & Delete)
            HStack(spacing: 12) {
                Button {
                    showShareSheet = true
                } label: {
                    secondaryButtonLabel(icon: "square.and.arrow.up", title: "Share")
                }

                if onDelete != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        secondaryButtonLabel(icon: "trash", title: "Delete", isDestructive: true)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .onTapGesture {
            // Absorb taps on bottom card so it doesn't dismiss
        }
        .adaptiveGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func secondaryButtonLabel(icon: String, title: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDestructive ? Color.red.opacity(0.08) : Color.primary.opacity(0.06))
        )
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
    }

    private func toggleAudioPlayback() {
        if isPlayingAudio {
            audioPlayer?.pause()
            isPlayingAudio = false
            playbackTimer?.invalidate()
            playbackTimer = nil
        } else {
            startAudioPlayback()
        }
    }

    private func startAudioPlayback() {
        if let url = fragment.mediaURL {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)
                } catch {
                    print("Detail audio session note: \(error)")
                }
            }

            if audioPlayer == nil {
                audioPlayer = try? AVAudioPlayer(contentsOf: url)
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
            }

            if audioPlaybackProgress >= 1.0 {
                audioPlayer?.currentTime = 0
                audioPlaybackProgress = 0.0
            }

            let started = audioPlayer?.play() ?? false
            if started {
                isPlayingAudio = true
                startPlaybackTimer()
            }
        } else {
            if audioPlaybackProgress >= 1.0 {
                audioPlaybackProgress = 0.0
            }
            isPlayingAudio = true
            startPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
            if let player = audioPlayer {
                if player.duration > 0 {
                    audioPlaybackProgress = min(1.0, player.currentTime / player.duration)
                }
                if !player.isPlaying {
                    isPlayingAudio = false
                    audioPlaybackProgress = 0.0
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                }
            } else {
                audioPlaybackProgress += 0.025 / 5.0
                if audioPlaybackProgress >= 1.0 {
                    isPlayingAudio = false
                    audioPlaybackProgress = 0.0
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                }
            }
        }
    }
}

// MARK: - Share Sheet Helper

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview("Photo Fragment") {
    FragmentDetailView(
        fragment: Fragment(type: .photo, title: "Golden Sunset", location: "Big Sur, CA"),
        onDismiss: {}
    )
}

#Preview("Note Fragment") {
    FragmentDetailView(
        fragment: Fragment(type: .note, title: "Ideas for Design", text: "1. Tactile buttons\n2. Spatial floating cards\n3. Glassmorphic details"),
        onDismiss: {}
    )
}
#endif
