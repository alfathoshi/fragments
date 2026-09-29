//
//  MomentDetailView.swift
//  fragments
//
//  Created on 9/16/26.
//

import SwiftUI
import AVFoundation

// MARK: - Moment Detail View Mode
public enum MomentDetailViewMode: String, CaseIterable, Identifiable {
    case grid
    case sphere

    public var id: String { rawValue }
}

// MARK: - Moment Detail View
public struct MomentDetailView: View {
    public let collection: FolderCollection
    public var onUpdateCollection: ((FolderCollection) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: MomentDetailViewModel
    @State private var viewMode: MomentDetailViewMode = .grid
    @State private var selectedFragment: Fragment? = nil
    @State private var sphereRotation: Double = 0.0
    @State private var sphereTilt: Double = 0.0
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet: Bool = false
    @State private var showScreenshotFlash: Bool = false
    @State private var showMembersSheet: Bool = false

    public init(
        collection: FolderCollection,
        onUpdateCollection: ((FolderCollection) -> Void)? = nil
    ) {
        self.collection = collection
        self.onUpdateCollection = onUpdateCollection
        self._viewModel = State(wrappedValue: MomentDetailViewModel(collection: collection, onUpdateCollection: onUpdateCollection))
    }

    private var resolvedRoom: Room {
        if let roomID = collection.roomID, let found = RoomManager.shared.rooms.first(where: { $0.id == roomID }) ?? RoomManager.shared.currentRoom {
            if found.id == roomID {
                return found
            }
        }
        if let roomID = collection.roomID, let cached = try? LocalRoomCache.shared.loadRoom(id: roomID) {
            return cached
        }
        let creatorId: String = {
            if SupabaseService.shared.isAuthenticated, let sbUserId = SupabaseService.shared.currentUserID {
                return sbUserId
            }
            return UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        }()
        return Room(
            id: collection.roomID ?? collection.id.uuidString,
            name: collection.name,
            emoji: "👥",
            createdAt: collection.date,
            createdBy: creatorId,
            zoneName: SupabaseService.shared.isAuthenticated ? "supabase" : nil
        )
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

            switch viewMode {
            case .grid:
                // Layout Canvas with Discrete Spots
                GeometryReader { containerGeo in
                    if viewModel.items.isEmpty {
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
                .transition(.opacity)

            case .sphere:
                ZStack {
                    if viewModel.items.isEmpty {
                        emptyStateView
                    } else {
                        FragmentSphere(
                            fragments: viewModel.items.toFragments(),
                            rotationAngle: $sphereRotation,
                            tiltAngle: $sphereTilt,
                            onSelectFragment: { fragment in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    selectedFragment = fragment
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            // Visual feedback flash on screenshot capture
            if showScreenshotFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.65)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Fragment Detail modal inspection
            if let fragment = selectedFragment {
                FragmentDetailView(
                    fragment: fragment,
//                    onDelete: collection.isShared ? nil : { _ in
//                        // Remove from local moment
//                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
//                            selectedFragment = nil
//                        }
//                        viewModel.deleteItem(withID: fragment.id)
//                    },
                    isSavedToMoment: true,
                    authorName: collection.isShared
                        ? RoomManager.shared.authorName(
                            forFragmentID: fragment.id.uuidString,
                            roomID: collection.roomID
                        )
                        : nil,
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            selectedFragment = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(100)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name.isEmpty ? "Moment Detail" : collection.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "fragment" : "fragments") | \(formattedDateText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if collection.isShared {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showMembersSheet = true
                    } label: {
                        Image(systemName: "person.2")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Room Members")
                }

                if !viewModel.hasReordered && !viewModel.isSavedConfirmation {
                    // Switch mode button (Grid <-> Sphere)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if viewMode == .grid {
                            viewModel.stopAudio()
                            viewModel.unmutedVideoID = nil
                        }
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            viewMode = (viewMode == .grid ? .sphere : .grid)
                        }
                    } label: {
                        Image(systemName: viewMode == .grid ? "circle.hexagongrid" : "square.grid.2x2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel(viewMode == .grid ? "Switch to Sphere View" : "Switch to Grid View")

                    // Share button: 9:16 screenshot without toolbar chrome
//                    Button {
//                        takeShareScreenshot()
//                    } label: {
//                        Image(systemName: "square.and.arrow.up")
//                            .font(.system(size: 15, weight: .semibold))
//                            .foregroundStyle(Color.primary)
//                    }
//                    .accessibilityLabel("Share Moment")
                }

                if viewModel.hasReordered {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            viewModel.items = viewModel.originalItems
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Reset layout")
                }

                if viewModel.hasReordered || viewModel.isSavedConfirmation {
                    Button {
                        viewModel.saveCurrentLayout()
                    } label: {
                        if viewModel.isSavedConfirmation {
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
        .sheet(isPresented: $showMembersSheet) {
            RoomMembersSheet(room: resolvedRoom)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
        .onAppear {
            viewModel.initializeItems()
        }
        .onChange(of: collection.items) { _, _ in
            viewModel.initializeItems()
        }
        .onDisappear {
            viewModel.stopAudio()
            viewModel.unmutedVideoID = nil
        }
    }

    // MARK: - Screenshot & Share in 9:16 Mode
    private func takeShareScreenshot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeOut(duration: 0.12)) {
            showScreenshotFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.22)) {
                showScreenshotFlash = false
            }
        }

        if let image = renderShareImage() {
            self.shareImage = image
            self.showShareSheet = true
        }
    }

    @MainActor
    private func renderShareImage() -> UIImage? {
        let cardView = MomentShareCardView(
            collection: collection,
            items: viewModel.items,
            viewMode: viewMode,
            formattedDateText: formattedDateText,
            sphereRotation: sphereRotation,
            sphereTilt: sphereTilt
        )
        .environment(\.colorScheme, colorScheme)

        let targetSize = CGSize(width: 360, height: 640)
        let renderer = ImageRenderer(content: cardView)
        renderer.proposedSize = ProposedViewSize(targetSize)
        renderer.scale = 3.0

        if let uiImage = renderer.uiImage {
            return uiImage
        }

        // Fallback using UIHostingController
        let hostingController = UIHostingController(rootView: cardView)
        guard let hostingView = hostingController.view else { return nil }
        hostingView.bounds = CGRect(origin: .zero, size: targetSize)
        hostingView.backgroundColor = .clear

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        let uigraphicsRenderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return uigraphicsRenderer.image { _ in
            hostingView.drawHierarchy(in: CGRect(origin: .zero, size: targetSize), afterScreenUpdates: true)
        }
    }

    // MARK: - Discrete Spot Geometry Calculation
    private func spotFrame(for index: Int, cardWidth: CGFloat, cardHeight: CGFloat, gutter: CGFloat) -> CGRect {
        viewModel.spotFrame(for: index, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
    }

    // MARK: - Widget Canvas View (Home Screen Grid)
    @ViewBuilder
    private func widgetCanvasView(contentWidth: CGFloat, horizontalMargin: CGFloat, canvasSize: CGSize) -> some View {
        let gutter: CGFloat = 14.0
        let cardWidth = (contentWidth - gutter) / 2.0
        let cardHeight: CGFloat = 188.0
        let totalRows = (viewModel.items.count + 1) / 2
        let gridHeight = 16.0 + CGFloat(totalRows) * (cardHeight + gutter)
        let totalHeight = max(canvasSize.height + 140.0, gridHeight + 100.0)

        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    let isDraggingThis = (viewModel.draggedItemID == item.id)
                    let baseFrame = spotFrame(for: index, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)

                    let posX: CGFloat = isDraggingThis
                        ? (viewModel.dragInitialCenter.x + viewModel.dragLiveTranslation.width)
                        : (horizontalMargin + baseFrame.midX)

                    let posY: CGFloat = isDraggingThis
                        ? (viewModel.dragInitialCenter.y + viewModel.dragLiveTranslation.height)
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
                    .zIndex(isDraggingThis ? 999 : Double(viewModel.items.count - index))
                }
            }
            .frame(width: canvasSize.width, height: totalHeight, alignment: .topLeading)
            .coordinateSpace(name: "WidgetCanvasGrid")
            .padding(.bottom, 60)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .scrollDisabled(viewModel.draggedItemID != nil)
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
            ? Angle.degrees(Double(viewModel.dragLiveTranslation.width / 45.0).clamped(to: -3.5...3.5))
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
                        if viewModel.draggedItemID == nil {
                            viewModel.draggedItemID = item.id
                            viewModel.dragCurrentIndex = index
                            let baseSpot = spotFrame(for: index, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
                            viewModel.dragInitialCenter = CGPoint(x: horizontalMargin + baseSpot.midX, y: baseSpot.midY)
                            viewModel.dragLiveTranslation = .zero
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    },
                    onChanged: { translation in
                        guard viewModel.draggedItemID == item.id else { return }
                        viewModel.dragLiveTranslation = translation

                        let currentCardCenter = CGPoint(
                            x: viewModel.dragInitialCenter.x + translation.width,
                            y: viewModel.dragInitialCenter.y + translation.height
                        )

                        viewModel.handleDisplacement(
                            cardCenter: currentCardCenter,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            gutter: gutter,
                            horizontalMargin: horizontalMargin
                        )
                    },
                    onEnded: {
                        guard viewModel.draggedItemID == item.id else { return }
                        viewModel.endDragSnap(
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            gutter: gutter,
                            horizontalMargin: horizontalMargin
                        )
                    },
                    onTap: {
                        guard viewModel.draggedItemID == nil else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.stopAudio()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            selectedFragment = item.toFragment()
                        }
                    }
                )
            )
    }

    // MARK: - Subtitle / Timestamp Formatting Helper
    private func formattedSubtitle(for item: FolderItem) -> String {
        viewModel.formattedSubtitle(for: item)
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
            Self.photoBackground(item: item, width: width, height: height)

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
    public static func photoBackground(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
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
        let isPlaying = viewModel.currentlyPlayingAudioID == item.id
        let progress = viewModel.audioProgress[item.id] ?? 0.0
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
                    viewModel.toggleAudio(for: item)
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
        let isVideoAudioPlaying = (viewModel.unmutedVideoID == item.id)

        return ZStack(alignment: .topLeading) {
            // Base poster / thumbnail preview (guarantees a frame is always visible)
            Self.photoBackground(item: item, width: width, height: height)

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
                        viewModel.toggleVideoAudio(for: item)
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

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("No fragments yet")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("Add fragments to this moment")
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
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> LongPressDragUIView {
        let view = LongPressDragUIView()
        view.hasButton = hasButton
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: LongPressDragUIView, context: Context) {
        uiView.hasButton = hasButton
        uiView.onBegan = onBegan
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
        uiView.onTap = onTap
    }
}

final class LongPressDragUIView: UIView, UIGestureRecognizerDelegate {
    var hasButton: Bool = false
    var onBegan: (() -> Void)?
    var onChanged: ((CGSize) -> Void)?
    var onEnded: (() -> Void)?
    var onTap: (() -> Void)?

    private var initialTouchPoint: CGPoint = .zero

    private lazy var recognizer: UILongPressGestureRecognizer = {
        let r = UILongPressGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        r.minimumPressDuration = 0.32
        r.allowableMovement = 14
        r.delegate = self
        r.cancelsTouchesInView = false
        return r
    }()

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let r = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        r.delegate = self
        r.cancelsTouchesInView = false
        return r
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        addGestureRecognizer(recognizer)
        addGestureRecognizer(tapRecognizer)
        tapRecognizer.require(toFail: recognizer)
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
        if gestureRecognizer == tapRecognizer {
            return false
        }
        return true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            onTap?()
        }
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

// MARK: - 9:16 Share Card View (Clean Screenshot Export)
public struct MomentShareCardView: View {
    public let collection: FolderCollection
    public let items: [FolderItem]
    public let viewMode: MomentDetailViewMode
    public let formattedDateText: String
    public var sphereRotation: Double = 0.0
    public var sphereTilt: Double = 0.0

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: ONLY Title and Subtitle (Toolbar icons removed)
                VStack(spacing: 4) {
                    Text(collection.name.isEmpty ? "Moment Detail" : collection.name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text("\(items.count) \(items.count == 1 ? "fragment" : "fragments") | \(formattedDateText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 36)
                .padding(.horizontal, 24)

                Spacer(minLength: 12)

                // Main Content
                Group {
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.dashed")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                            Text("No fragments yet")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primary)
                        }
                    } else {
                        switch viewMode {
                        case .sphere:
                            FragmentSphere(
                                fragments: items.toFragments(),
                                rotationAngle: .constant(sphereRotation),
                                tiltAngle: .constant(sphereTilt),
                                isInteractive: false
                            )
                            .frame(width: 360, height: 490)

                        case .grid:
                            gridShareContent
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 12)
            }
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var gridShareContent: some View {
        let gutter: CGFloat = 12.0
        let cardWidth: CGFloat = 154.0
        let cardHeight: CGFloat = 168.0
        let totalRows = (items.count + 1) / 2
        let naturalGridHeight = CGFloat(totalRows) * cardHeight + CGFloat(max(0, totalRows - 1)) * gutter
        let availableHeight: CGFloat = 490.0
        let scaleFactor = min(1.0, availableHeight / max(1.0, naturalGridHeight))

        return VStack(spacing: gutter) {
            ForEach(0..<totalRows, id: \.self) { row in
                HStack(spacing: gutter) {
                    let firstIndex = row * 2
                    if firstIndex < items.count {
                        shareCard(item: items[firstIndex], width: cardWidth, height: cardHeight)
                    }

                    let secondIndex = firstIndex + 1
                    if secondIndex < items.count {
                        shareCard(item: items[secondIndex], width: cardWidth, height: cardHeight)
                    } else if firstIndex < items.count {
                        Spacer()
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
            }
        }
        .scaleEffect(scaleFactor, anchor: .center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func shareCard(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        switch item.type ?? .photo {
        case .photo:
            sharePhotoWidget(item: item, width: width, height: height)
        case .note:
            shareNoteWidget(item: item, width: width, height: height)
        case .audio:
            shareAudioWidget(item: item, width: width, height: height)
        case .video:
            shareVideoWidget(item: item, width: width, height: height)
        }
    }

    private func sharePhotoWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MomentDetailView.photoBackground(item: item, width: width, height: height)

            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Photo" : item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func shareNoteWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let noteColors = item.resolvedGradientColors
        let isLight = noteColors.first?.isLightBackground ?? true

        let primaryTextColor = isLight ? Color(red: 28/255, green: 28/255, blue: 28/255) : Color.white
        let secondaryTextColor = isLight ? Color(red: 110/255, green: 100/255, blue: 90/255) : Color.white.opacity(0.8)
        let dividerColor = isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.2)

        return ZStack(alignment: .topLeading) {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title.isEmpty ? "Note" : item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(formattedSubtitle(for: item))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)

                    Spacer()
                }

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                Text(item.text ?? "")
                    .font(.system(size: 10, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(primaryTextColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shareAudioWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        let memoColors = item.resolvedGradientColors
        let isLight = memoColors.first?.isLightBackground ?? false

        let primaryTextColor = isLight ? Color.black : Color.white
        let secondaryTextColor = isLight ? Color.black.opacity(0.65) : Color.white.opacity(0.82)
        let unplayedWaveColor = isLight ? Color.black.opacity(0.4) : Color.white.opacity(0.6)
        let playBtnBgColor = isLight ? Color.black : Color.white
        let playBtnIconColor = isLight ? Color.white : (memoColors.first ?? Color.black)
        let badgeBgColor = isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.20)
        let badgeTextColor = isLight ? Color.black.opacity(0.75) : Color.white

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Voice Memo" : item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            let rawBars = item.audioWaveform ?? [
                0.2, 0.5, 0.85, 0.3, 0.3, 1.0, 0.85, 0.85, 0.85, 0.6,
                0.6, 0.6, 1.0, 0.2, 1.0, 1.0, 1.0, 0.6, 0.6, 0.6,
                0.6, 1.0, 0.6, 0.6, 0.3, 0.6, 0.3, 0.6, 1.0, 0.6
            ]

            HStack(spacing: 2.5) {
                ForEach(0..<min(rawBars.count, 24), id: \.self) { i in
                    let sampleVal = CGFloat(rawBars[i])
                    let barHeight = max(4.0, sampleVal * 28.0)

                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(unplayedWaveColor)
                        .frame(width: 2.5, height: barHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .center)

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Circle()
                    .fill(playBtnBgColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(playBtnIconColor)
                            .offset(x: 1)
                    )

                Spacer()

                if let dur = item.duration, !dur.isEmpty {
                    Text(dur)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(badgeTextColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(badgeBgColor)
                        )
                }
            }
        }
        .padding(12)
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

    private func shareVideoWidget(item: FolderItem, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MomentDetailView.photoBackground(item: item, width: width, height: height)

            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Video" : item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(formattedSubtitle(for: item))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
            }
            .padding(12)

            VStack {
                Spacer()
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .bold))
                        if let dur = item.duration, !dur.isEmpty {
                            Text(dur)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
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

                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func formattedSubtitle(for item: FolderItem) -> String {
        let date = item.createdAt ?? collection.date
        let timeString = MomentDetailViewModel.timeOnlyFormatter.string(from: date)
        if Calendar.current.isDate(date, inSameDayAs: collection.date) {
            return timeString
        } else {
            let isSameYear = Calendar.current.isDate(date, equalTo: collection.date, toGranularity: .year)
            let dateString = isSameYear
                ? MomentDetailViewModel.dayMonthFormatter.string(from: date)
                : MomentDetailViewModel.dayMonthYearFormatter.string(from: date)
            return "\(dateString), \(timeString)"
        }
    }
}


