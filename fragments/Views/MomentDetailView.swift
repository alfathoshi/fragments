//
//  MomentDetailView.swift
//  fragments
//
//  Created on 9/16/26.
//

import SwiftUI
import AVFoundation

// MARK: - Moment Detail View
public struct MomentDetailView: View {
    public let collection: FolderCollection
    public var onUpdateCollection: ((FolderCollection) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Ordered items representing discrete spots (Home Screen style)
    @State private var items: [FolderItem] = []
    @State private var originalItems: [FolderItem] = []
    @State private var isSavedConfirmation: Bool = false

    // Check whether items order has changed compared to saved layout
    private var hasReordered: Bool {
        guard items.count == originalItems.count else { return false }
        return items.map(\.id) != originalItems.map(\.id)
    }

    // Drag-to-reorder state (Tap & Hold to Move)
    @State private var draggedItemID: UUID? = nil
    @State private var dragCurrentIndex: Int? = nil
    @State private var dragInitialCenter: CGPoint = .zero
    @State private var dragLiveTranslation: CGSize = .zero
    @State private var lastReorderTime: Date = .distantPast

    // Audio playback state (Voice memo)
    @State private var currentlyPlayingAudioID: UUID? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var playbackTimer: Timer? = nil
    @State private var audioProgress: [UUID: Double] = [:]

    // Video audio playback state
    @State private var unmutedVideoID: UUID? = nil

    public init(
        collection: FolderCollection,
        onUpdateCollection: ((FolderCollection) -> Void)? = nil
    ) {
        self.collection = collection
        self.onUpdateCollection = onUpdateCollection
    }

    private var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: collection.date)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // Layout Canvas with Discrete Spots
            GeometryReader { containerGeo in
                if items.isEmpty {
                    emptyStateView
                } else {
                    let canvasWidth = containerGeo.size.width
                    let horizontalMargin: CGFloat = 16.0
                    let contentWidth = max(280.0, canvasWidth - (horizontalMargin * 2.0))

                    widgetCanvasView(
                        contentWidth: contentWidth,
                        horizontalMargin: horizontalMargin,
                        canvasSize: containerGeo.size
                    )
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .accessibilityLabel("Back")
            }

            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(collection.name.isEmpty ? "Moment Detail" : collection.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text("\(items.count) \(items.count == 1 ? "fragment" : "fragments") | \(formattedDateText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasReordered {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            items = originalItems
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Reset layout")
                }

                if hasReordered || isSavedConfirmation {
                    Button {
                        saveCurrentLayout()
                    } label: {
                        if isSavedConfirmation {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .accessibilityLabel("Save layout")
                }
            }
        }
        .onAppear {
            initializeItems()
        }
        .onChange(of: collection.items) { _, _ in
            initializeItems()
        }
        .onDisappear {
            stopAudio()
            unmutedVideoID = nil
        }
    }

    private func initializeItems() {
        if let currentCollection = MomentManager.shared.collections.first(where: { $0.id == collection.id }) {
            items = currentCollection.items
            originalItems = currentCollection.items
        } else {
            items = collection.items
            originalItems = collection.items
        }
    }

    private func saveCurrentLayout() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var updated = collection
        updated.items = items
        originalItems = items

        onUpdateCollection?(updated)
        MomentManager.shared.updateMomentItems(id: collection.id, items: items)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            isSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isSavedConfirmation = false
            }
        }
    }

    // MARK: - Discrete Spot Geometry Calculation
    private func spotFrame(for index: Int, cardWidth: CGFloat, cardHeight: CGFloat, gutter: CGFloat) -> CGRect {
        let col = index % 2
        let row = index / 2
        let topOffset: CGFloat = 16.0
        let x = CGFloat(col) * (cardWidth + gutter)
        let y = topOffset + CGFloat(row) * (cardHeight + gutter)
        return CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
    }

    // MARK: - Widget Canvas View (Home Screen Grid)
    @ViewBuilder
    private func widgetCanvasView(contentWidth: CGFloat, horizontalMargin: CGFloat, canvasSize: CGSize) -> some View {
        let gutter: CGFloat = 14.0
        let cardWidth = (contentWidth - gutter) / 2.0
        let cardHeight: CGFloat = 188.0
        let totalRows = (items.count + 1) / 2
        let gridHeight = 16.0 + CGFloat(totalRows) * (cardHeight + gutter)
        let totalHeight = max(canvasSize.height + 140.0, gridHeight + 100.0)

        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isDraggingThis = (draggedItemID == item.id)
                    let baseFrame = spotFrame(for: index, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)

                    let posX: CGFloat = isDraggingThis
                        ? (dragInitialCenter.x + dragLiveTranslation.width)
                        : (horizontalMargin + baseFrame.midX)

                    let posY: CGFloat = isDraggingThis
                        ? (dragInitialCenter.y + dragLiveTranslation.height)
                        : baseFrame.midY

                    homeScreenCard(
                        item: item,
                        index: index,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        gutter: gutter,
                        horizontalMargin: horizontalMargin,
                        isDragging: isDraggingThis
                    )
                    .position(x: posX, y: posY)
                    .zIndex(isDraggingThis ? 999 : Double(items.count - index))
                }
            }
            .frame(width: canvasSize.width, height: totalHeight, alignment: .topLeading)
            .coordinateSpace(name: "WidgetCanvasGrid")
            .padding(.bottom, 60)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .scrollDisabled(draggedItemID != nil)
        .scrollBounceBehavior(.always, axes: .vertical)
    }

    // MARK: - Home Screen Card Wrapper with Tap-and-Hold Drag Reordering
    @ViewBuilder
    private func homeScreenCard(
        item: FolderItem,
        index: Int,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        horizontalMargin: CGFloat,
        isDragging: Bool
    ) -> some View {
        let tiltAngle: Angle = isDragging
            ? Angle.degrees(Double(dragLiveTranslation.width / 45.0).clamped(to: -3.5...3.5))
            : .zero

        let hasButton = (item.type == .audio || item.type == .video)

        widgetContent(item: item, width: cardWidth, height: cardHeight)
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(isDragging ? 1.045 : 1.0)
            .rotationEffect(tiltAngle)
            .shadow(
                color: Color.black.opacity(isDragging ? 0.22 : 0.05),
                radius: isDragging ? 18 : 6,
                x: 0,
                y: isDragging ? 12 : 3
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isDragging)
            .overlay(
                LongPressDragGestureModifier(
                    hasButton: hasButton,
                    onBegan: {
                        if draggedItemID == nil {
                            draggedItemID = item.id
                            dragCurrentIndex = index
                            let baseSpot = spotFrame(for: index, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
                            dragInitialCenter = CGPoint(x: horizontalMargin + baseSpot.midX, y: baseSpot.midY)
                            dragLiveTranslation = .zero
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    },
                    onChanged: { translation in
                        guard draggedItemID == item.id else { return }
                        dragLiveTranslation = translation

                        let currentCardCenter = CGPoint(
                            x: dragInitialCenter.x + translation.width,
                            y: dragInitialCenter.y + translation.height
                        )

                        handleDisplacement(
                            cardCenter: currentCardCenter,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            gutter: gutter,
                            horizontalMargin: horizontalMargin
                        )
                    },
                    onEnded: {
                        guard draggedItemID == item.id else { return }
                        endDragSnap(
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            gutter: gutter,
                            horizontalMargin: horizontalMargin
                        )
                    }
                )
            )
    }

    private func handleDisplacement(
        cardCenter: CGPoint,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        horizontalMargin: CGFloat
    ) {
        guard let currentIndex = dragCurrentIndex, items.indices.contains(currentIndex) else { return }

        // Find the spot that is closest to cardCenter
        var bestIndex = currentIndex
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0..<items.count {
            let spot = spotFrame(for: i, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
            let spotCenter = CGPoint(x: horizontalMargin + spot.midX, y: spot.midY)
            let dist = hypot(cardCenter.x - spotCenter.x, cardCenter.y - spotCenter.y)
            if dist < minDistance {
                minDistance = dist
                bestIndex = i
            }
        }

        // Hysteresis & cooldown check: Must be within 60% of card width
        // AND have a 280ms cooldown to completely eliminate back-and-forth oscillation
        if bestIndex != currentIndex && minDistance < (cardWidth * 0.60) {
            let now = Date()
            if now.timeIntervalSince(lastReorderTime) > 0.28 {
                lastReorderTime = now
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    let moved = items.remove(at: currentIndex)
                    items.insert(moved, at: bestIndex)
                    dragCurrentIndex = bestIndex
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func endDragSnap(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        horizontalMargin: CGFloat
    ) {
        guard let currentIndex = dragCurrentIndex, items.indices.contains(currentIndex) else {
            draggedItemID = nil
            dragCurrentIndex = nil
            dragLiveTranslation = .zero
            return
        }

        let targetSpot = spotFrame(for: currentIndex, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
        let targetCenter = CGPoint(x: horizontalMargin + targetSpot.midX, y: targetSpot.midY)

        let visualCenter = CGPoint(
            x: dragInitialCenter.x + dragLiveTranslation.width,
            y: dragInitialCenter.y + dragLiveTranslation.height
        )

        // Seamless re-anchoring: preserve exact visual coordinate
        dragInitialCenter = targetCenter
        dragLiveTranslation = CGSize(
            width: visualCenter.x - targetCenter.x,
            height: visualCenter.y - targetCenter.y
        )

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            dragLiveTranslation = .zero
        } completion: {
            draggedItemID = nil
            dragCurrentIndex = nil
            dragLiveTranslation = .zero
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Subtitle / Timestamp Formatting Helpers

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// Formats the widget subtitle based on the fragment timestamp vs the moment date.
    /// Returns only the time if captured on the same calendar day; otherwise includes date and time.
    private func formattedSubtitle(for item: FolderItem) -> String {
        let date = resolveItemDate(for: item)
        let timeString = Self.timeOnlyFormatter.string(from: date)

        if Calendar.current.isDate(date, inSameDayAs: collection.date) {
            return timeString
        } else {
            let isSameYear = Calendar.current.isDate(date, equalTo: collection.date, toGranularity: .year)
            let dateString = isSameYear
                ? Self.dayMonthFormatter.string(from: date)
                : Self.dayMonthYearFormatter.string(from: date)
            return "\(dateString), \(timeString)"
        }
    }

    private func resolveItemDate(for item: FolderItem) -> Date {
        if let createdAt = item.createdAt {
            return createdAt
        }

        guard let sub = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty else {
            return collection.date
        }

        let calendar = Calendar.current

        // Check if subtitle is a pure time string (e.g., "2.30 PM", "2:30 PM", "14:30")
        let timeFormats = ["h.mm a", "h:mm a", "h a", "HH:mm", "H:mm"]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        for fmt in timeFormats {
            timeFormatter.dateFormat = fmt
            if let parsedTime = timeFormatter.date(from: sub) {
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
                if let combined = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                minute: timeComponents.minute ?? 0,
                                                second: timeComponents.second ?? 0,
                                                of: collection.date) {
                    return combined
                }
            }
        }

        // Check full date & time formats
        let fullFormats = [
            "MMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm a",
            "MMM d, yyyy h:mm a",
            "MMM d, h:mm a",
            "MMM d 'at' h:mm a",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        for fmt in fullFormats {
            timeFormatter.dateFormat = fmt
            if let parsedDate = timeFormatter.date(from: sub) {
                if !fmt.contains("yyyy") {
                    let year = calendar.component(.year, from: collection.date)
                    var comps = calendar.dateComponents([.month, .day, .hour, .minute], from: parsedDate)
                    comps.year = year
                    if let withYear = calendar.date(from: comps) {
                        return withYear
                    }
                }
                return parsedDate
            }
        }

        let systemFormatter = DateFormatter()
        systemFormatter.dateStyle = .medium
        systemFormatter.timeStyle = .short
        if let parsed = systemFormatter.date(from: sub) {
            return parsed
        }

        return collection.date
    }

    // MARK: - Widget View Selector
    @ViewBuilder
    private func widgetContent(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        switch item.type ?? .photo {
        case .photo:
            photoWidget(item: item, width: width, height: height)
        case .note:
            noteWidget(item: item, width: width, height: height)
        case .audio:
            audioWidget(item: item, width: width, height: height)
        case .video:
            videoWidget(item: item, width: width, height: height)
        }
    }

    // MARK: - 1. Photo Widget
    private func photoWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            photoBackground(item: item, width: width, height: height)

            // Top gradient scrim for metadata legibility
            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Metadata: Title & Timestamp
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Photo" : item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
            }
            .padding(14)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func photoBackground(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let fragment = item.toFragment()
        if let imgName = item.imageName, let uiImage = UIImage(named: imgName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else if let videoThumb = fragment.videoThumbnail {
            Image(uiImage: videoThumb)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else if let loaded = fragment.thumbnailImage ?? fragment.loadedImage {
            Image(uiImage: loaded)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            LinearGradient(
                colors: item.resolvedGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: item.systemImage ?? (item.type == .video ? "video.fill" : "photo.fill"))
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.8))
            )
        }
    }

    // MARK: - 2. Sticky Note Widget
    private func noteWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let noteColors = item.resolvedGradientColors
        let isLight = noteColors.first?.isLightBackground ?? true

        let primaryTextColor = isLight ? Color(red: 28/255, green: 28/255, blue: 28/255) : Color.white
        let secondaryTextColor = isLight ? Color(red: 110/255, green: 100/255, blue: 90/255) : Color.white.opacity(0.8)
        let dividerColor = isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.2)

        return ZStack(alignment: .topLeading) {
            // Note Background with subtle outline
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: noteColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                // Header: Title & Time
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title.isEmpty ? "Note" : item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(formattedSubtitle(for: item))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)

                    Spacer()
                }

                // Fine hairline divider
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                // Note Body Text
                Text(item.text ?? "")
                    .font(.system(size: 11, weight: .regular))
                    .lineSpacing(3.5)
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(7)

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 3. Audio Widget (Interactive Voice Memo Player)
    private func audioWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let isPlaying = currentlyPlayingAudioID == item.id
        let progress = audioProgress[item.id] ?? 0.0
        let memoColors = item.resolvedGradientColors
        let isLight = memoColors.first?.isLightBackground ?? false

        let primaryTextColor = isLight ? Color.black : Color.white
        let secondaryTextColor = isLight ? Color.black.opacity(0.65) : Color.white.opacity(0.82)
        let playedWaveColor = isLight ? Color.black : Color.white
        let unplayedWaveColor = isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.38)
        let playBtnBgColor = isLight ? Color.black : Color.white
        let playBtnIconColor = isLight ? Color.white : (memoColors.first ?? Color.black)
        let badgeBgColor = isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.20)
        let badgeTextColor = isLight ? Color.black.opacity(0.75) : Color.white

        return VStack(alignment: .leading, spacing: 10) {
            // Header: Title + Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Voice Memo" : item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Waveform visualization in center
            let rawBars = item.audioWaveform ?? [
                0.2, 0.5, 0.85, 0.3, 0.3, 1.0, 0.85, 0.85, 0.85, 0.6,
                0.6, 0.6, 1.0, 0.2, 1.0, 1.0, 1.0, 0.6, 0.6, 0.6,
                0.6, 1.0, 0.6, 0.6, 0.3, 0.6, 0.3, 0.6, 1.0, 0.6
            ]

            HStack(spacing: 2.5) {
                ForEach(0..<min(rawBars.count, 28), id: \.self) { i in
                    let fraction = Double(i) / Double(min(rawBars.count, 28))
                    let isPlayed = isPlaying && fraction <= progress
                    let sampleVal = CGFloat(rawBars[i])
                    let barHeight = max(4.0, sampleVal * 32.0)

                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(isPlayed ? playedWaveColor : unplayedWaveColor)
                        .frame(width: 2.5, height: barHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 36, alignment: .center)

            Spacer(minLength: 0)

            // Bottom controls: Play/Pause Button & Duration Badge
            HStack(alignment: .center) {
                Button {
                    toggleAudio(for: item)
                } label: {
                    Circle()
                        .fill(playBtnBgColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(playBtnIconColor)
                                .offset(x: isPlaying ? 0 : 1)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                if let dur = item.duration, !dur.isEmpty {
                    Text(dur)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(badgeTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(badgeBgColor)
                        )
                }
            }
        }
        .padding(14)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: memoColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - 4. Video Widget (Auto-Play Looping with Audio Toggle)
    private func videoWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let videoURL = item.videoURL
        let canPlayVideo = videoURL != nil && (FileManager.default.fileExists(atPath: videoURL!.path) || videoURL!.isFileURL)
        let isVideoAudioPlaying = (unmutedVideoID == item.id)

        return ZStack(alignment: .topLeading) {
            // Base poster / thumbnail preview (guarantees a frame is always visible)
            photoBackground(item: item, width: width, height: height)

            // Looping video player overlaid on top when playable
            if canPlayVideo, let url = videoURL {
                LoopingVideoPlayerView(url: url, isMuted: !isVideoAudioPlaying)
                    .frame(width: width, height: height)
                    .clipped()
            }

            // Top gradient scrim for metadata legibility
            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Metadata: Title & Timestamp
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Video" : item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
            }
            .padding(14)

            // Bottom controls: Speaker Audio Toggle & Duration Badge
            VStack {
                Spacer()
                HStack(alignment: .center) {
                    // Audio Play / Mute Button for Video
                    Button {
                        toggleVideoAudio(for: item)
                    } label: {
                        ZStack {
                            if isVideoAudioPlaying {
                                Circle()
                                    .fill(Color.white)
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        )
                        .overlay(
                            Image(systemName: isVideoAudioPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isVideoAudioPlaying ? Color.black : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 4, y: 1.5)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    // Video Duration Badge
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .bold))
                        if let dur = item.duration, !dur.isEmpty {
                            Text(dur)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 4, y: 1)
                }
                .padding(12)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Audio Coordination (Voice Memo & Video Sound)
    private func toggleAudio(for item: FolderItem) {
        if currentlyPlayingAudioID == item.id {
            stopAudio()
        } else {
            // Mute any video audio
            unmutedVideoID = nil
            stopAudio()
            playAudio(for: item)
        }
    }

    private func toggleVideoAudio(for item: FolderItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if unmutedVideoID == item.id {
            unmutedVideoID = nil
        } else {
            // Stop any playing voice memo
            stopAudio()
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            unmutedVideoID = item.id
        }
    }

    private func playAudio(for item: FolderItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        currentlyPlayingAudioID = item.id
        audioProgress[item.id] = 0.0

        if let url = item.toFragment().mediaURL {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)

            if let player = try? AVAudioPlayer(contentsOf: url) {
                self.audioPlayer = player
                player.play()
            }
        }

        let totalDuration: Double = {
            if let durStr = item.duration {
                let parts = durStr.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    return max(1.0, m * 60.0 + s)
                } else if let val = Double(durStr) {
                    return max(1.0, val)
                }
            }
            return 4.0
        }()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let player = audioPlayer, player.duration > 0 {
                let currentProg = player.currentTime / player.duration
                audioProgress[item.id] = currentProg
                if !player.isPlaying {
                    stopAudio()
                }
            } else {
                let current = (audioProgress[item.id] ?? 0.0) + (0.05 / totalDuration)
                if current >= 1.0 {
                    stopAudio()
                } else {
                    audioProgress[item.id] = current
                }
            }
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        if let id = currentlyPlayingAudioID {
            audioProgress[id] = 0.0
        }
        currentlyPlayingAudioID = nil
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("No Fragments Yet")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("Add fragments to this moment to view them as widgets")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UIKit Long-Press Drag Gesture Modifier (Seamless Scroll Interop)

struct LongPressDragGestureModifier: UIViewRepresentable {
    var hasButton: Bool = false
    var onBegan: () -> Void
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> LongPressDragUIView {
        let view = LongPressDragUIView()
        view.hasButton = hasButton
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: LongPressDragUIView, context: Context) {
        uiView.hasButton = hasButton
        uiView.onBegan = onBegan
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }
}

final class LongPressDragUIView: UIView, UIGestureRecognizerDelegate {
    var hasButton: Bool = false
    var onBegan: (() -> Void)?
    var onChanged: ((CGSize) -> Void)?
    var onEnded: (() -> Void)?

    private var initialTouchPoint: CGPoint = .zero

    private lazy var recognizer: UILongPressGestureRecognizer = {
        let r = UILongPressGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        r.minimumPressDuration = 0.32
        r.allowableMovement = 14
        r.delegate = self
        r.cancelsTouchesInView = false
        return r
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // If this widget has a bottom-left button (play audio or mute video),
        // pass touches in that button's region (56x56 box) directly to the SwiftUI button!
        if hasButton && point.x < 56 && point.y > (bounds.height - 56) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    @objc private func handleGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let targetWindow = self.window else { return }
        let currentPoint = gesture.location(in: targetWindow)

        switch gesture.state {
        case .began:
            initialTouchPoint = currentPoint
            onBegan?()
        case .changed:
            let translation = CGSize(
                width: currentPoint.x - initialTouchPoint.x,
                height: currentPoint.y - initialTouchPoint.y
            )
            onChanged?(translation)
        case .ended, .cancelled, .failed:
            onEnded?()
        default:
            break
        }
    }
}

// MARK: - Looping Video Player (UIViewRepresentable)
struct LoopingVideoPlayerView: UIViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView(url: url, isMuted: isMuted, gravity: gravity)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.updateURL(url)
        uiView.setMuted(isMuted)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.cleanup()
    }
}

final class LoopingPlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL, isMuted: Bool = true, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        backgroundColor = .clear
        playerLayer.videoGravity = gravity
        layer.addSublayer(playerLayer)
        setupPlayer(url: url, isMuted: isMuted)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func setupPlayer(url: URL, isMuted: Bool) {
        guard currentURL != url else { return }
        cleanup()
        currentURL = url

        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .none

        self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
        self.playerLayer.player = player
        self.queuePlayer = player

        player.play()
    }

    func setMuted(_ muted: Bool) {
        queuePlayer?.isMuted = muted
    }

    func updateURL(_ url: URL) {
        if currentURL != url {
            setupPlayer(url: url, isMuted: queuePlayer?.isMuted ?? true)
        }
    }

    func cleanup() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        playerLooper = nil
        playerLayer.player = nil
        currentURL = nil
    }

    deinit {
        cleanup()
    }
}

// MARK: - Clamping Helper
private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Color Luminance Helper
private extension Color {
    var isLightBackground: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.68
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Moment Detail") {
    MomentDetailView(
        collection: FolderCollection(
            name: "Sanur Beach",
            location: "Sanur Beach, Bali",
            date: Date(),
            items: FolderItem.sampleSanurBeach
        )
    )
}
#endif


