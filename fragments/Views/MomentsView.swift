//
//  MomentsView.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/12/26.
//

import SwiftUI

// MARK: - Folder Collection Model

public struct FolderCollection: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var location: String
    public var date: Date
    public var items: [FolderItem]
    public var color: Color?
    public var isShared: Bool
    public var roomID: String?
    public var category: String

    public init(
        id: UUID = UUID(),
        name: String,
        location: String,
        date: Date,
        items: [FolderItem],
        color: Color? = nil,
        isShared: Bool = false,
        roomID: String? = nil,
        category: String = "Life"
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.date = date
        self.items = items
        self.color = color
        self.isShared = isShared
        self.roomID = roomID
        self.category = category
    }

    public var fragmentCountText: String {
        "\(items.count) \(items.count == 1 ? "fragment" : "fragments")"
    }

    public var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Builds the Moments tab list from saved collections plus completed shared rooms.
/// In-progress rooms are excluded so discarding a live session never flashes as a saved Moment.
enum MomentsCatalog {
    static func visibleMoments(
        savedCollections: [FolderCollection],
        rooms: [Room],
        activeRoomID: String?,
        suppressedRoomIDs: Set<String> = []
    ) -> [FolderCollection] {
        var result = savedCollections
        let existingRoomIDs = Set(result.compactMap(\.roomID))
        let suppressed = Set(suppressedRoomIDs.map { $0.lowercased() })
        let activeID = activeRoomID?.lowercased()

        for room in rooms {
            let roomKey = room.id.lowercased()
            if suppressed.contains(roomKey) { continue }
            if let activeID, roomKey == activeID { continue }
            if existingRoomIDs.contains(room.id) { continue }
            // Live collaborative sessions are not personal Moments until explicitly saved/ended.
            guard room.isEnded || room.isArchived else { continue }

            let cachedFragments = (try? LocalRoomCache.shared.loadFragments(roomID: room.id)) ?? []
            let items = cachedFragments.map { FolderItem(from: $0.toFragment()) }
            let color = room.accentColorHex.map { Color.fromRGBAString($0) }
            let stableUUID = UUID(uuidString: room.id) ?? UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", abs(room.id.hashValue)))") ?? UUID()
            result.append(
                FolderCollection(
                    id: stableUUID,
                    name: room.finalTitle ?? room.name,
                    location: "Shared",
                    date: room.createdAt,
                    items: items,
                    color: color,
                    isShared: true,
                    roomID: room.id,
                    category: room.finalCategory ?? "Friends"
                )
            )
        }

        return result.sorted { $0.date > $1.date }
    }
}

// MARK: - Moments View (Unified Personal & Shared Moments)

struct MomentsView: View {
    // MARK: - State

    @State private var viewModel: MomentsViewModel
    @State private var showProfileSheet = false
    @State private var revealedFolderID: UUID? = nil

    init(momentManager: MomentManager = MomentManager.shared) {
        _viewModel = State(wrappedValue: MomentsViewModel(momentManager: momentManager))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    /// Unified list of all moments (both personal and collaborative rooms)
    private var allMoments: [FolderCollection] {
        MomentsCatalog.visibleMoments(
            savedCollections: viewModel.momentManager.collections,
            rooms: RoomManager.shared.rooms,
            activeRoomID: viewModel.momentManager.activeSession?.room?.id,
            suppressedRoomIDs: RoomManager.shared.locallyRemovedRoomIDs
        )
    }

    var body: some View {
        NavigationStack {
            momentsContent
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                .navigationTitle("Moments")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {

                    if !allMoments.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.toggleEditing()
                            } label: {
                                Text(viewModel.isEditing ? "Done" : "Edit")
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileToolbarButton {
                            showProfileSheet = true
                        }
                    }
                }
                .sheet(isPresented: $showProfileSheet) {
                    ProfileView()
                }
                .blur(radius: viewModel.editingCollection != nil ? 16 : 0)
                .animation(.easeInOut(duration: 0.28), value: viewModel.editingCollection != nil)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: allMoments.count)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.isEditing)
                // Bottom Sheet opened when Edit mode is active and moment is picked
                .sheet(item: $viewModel.editingCollection) { collection in
                    FolderDetailBottomSheet(
                        collection: collection,
                        onSaveMetadata: { name, category, color in
                            viewModel.momentManager.updateMomentMetadata(id: collection.id, roomID: collection.roomID, name: name, category: category, color: color)
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                viewModel.momentManager.deleteMoment(id: collection.id, roomID: collection.roomID)
                            }
                        },
                        onLeave: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                viewModel.momentManager.leaveMoment(id: collection.id, roomID: collection.roomID)
                            }
                        }
                    )
                }
                // Navigation destination pushed on moment tap (Normal mode)
                .navigationDestination(item: $viewModel.selectedDetailCollection) { collection in
                    let currentCollection = allMoments.first(where: { $0.id == collection.id }) ?? collection
                    MomentDetailView(
                        collection: currentCollection,
                        onUpdateCollection: { updated in
                            viewModel.momentManager.updateMomentItems(id: updated.id, items: updated.items)
                            if let idx = viewModel.momentManager.collections.firstIndex(where: { $0.id == updated.id }) {
                                viewModel.momentManager.collections[idx] = updated
                            }
                        }
                    )
                }
        }
    }

    // MARK: - Moments Grid Content

    @ViewBuilder
    private var momentsContent: some View {
        if allMoments.isEmpty {
            emptyStateView
                .transition(.opacity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(allMoments) { collection in
                        VStack(alignment: .center, spacing: 12) {
                            MomentFolder(
                                items: collection.items,
                                isOpen: Binding(
                                    get: { revealedFolderID == collection.id },
                                    set: { isRevealed in
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                                            if isRevealed {
                                                revealedFolderID = collection.id
                                            } else if revealedFolderID == collection.id {
                                                revealedFolderID = nil
                                            }
                                        }
                                    }
                                ),
                                size: CGSize(width: 168, height: 166),
                                isShared: collection.isShared,
                                folderColor: collection.color,
                                category: collection.category,
                                onTapFolder: {
                                    viewModel.handleMomentSelection(collection)
                                },
                                onTapItem: { _ in
                                    viewModel.handleMomentSelection(collection)
                                }
                            )
                            .overlay(alignment: .topTrailing) {
                                if viewModel.isEditing {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                        )
                                        .overlay(
                                            Image(systemName: "pencil")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(Color.primary)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
                                        .offset(x: 6, y: -6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }

                            // Folder metadata text under card
                            VStack(spacing: 3) {
                                Text(collection.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 10))
                                    Text(collection.fragmentCountText)
                                        .font(.system(size: 12, weight: .regular))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.handleMomentSelection(collection)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .transition(.opacity)
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-revealFirstFolder") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                            revealedFolderID = allMoments.first?.id
                        }
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Faint Folder & Orbital Background Guide
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                    .frame(width: 200, height: 200)

                Circle()
                    .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 8]))
                    .frame(width: 260, height: 260)

                // Glassy Folder Icon
                
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    
                    
            }

            // Copy
            VStack(spacing: 8) {
                Text("No moments yet")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Start your moment")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Folder Detail Bottom Sheet

// MARK: - Folder Detail Bottom Sheet

public struct FolderDetailBottomSheet: View {
    public let collection: FolderCollection
    public var onSaveMetadata: ((String, String, Color?) -> Void)? = nil
    public var onDelete: (() -> Void)? = nil
    public var onLeave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showColorPicker = false
    @State private var selectedFragment: FolderItem? = nil
    @State private var isFolderOpen = false
    @State private var sheetDetent: PresentationDetent = .fraction(0.38)
    @State private var showDeleteConfirmation = false
    @State private var showLeaveConfirmation = false

    /// Whether this shared moment is owned by someone else (user should "Leave" instead of "Delete")
    private var isSharedByOthers: Bool {
        guard collection.isShared, let roomID = collection.roomID else { return false }
        if let room = RoomManager.shared.rooms.first(where: { $0.id == roomID })
            ?? RoomManager.shared.currentRoom
            ?? (MomentManager.shared.activeSession?.room?.id == roomID ? MomentManager.shared.activeSession?.room : nil) {
            if room.id == roomID {
                return !room.isCurrentUserOwner
            }
        }
        if let cachedRoom = try? LocalRoomCache.shared.loadRoom(id: roomID) {
            return !cachedRoom.isCurrentUserOwner
        }
        return false
    }

    public init(
        collection: FolderCollection,
        onSaveMetadata: ((String, String, Color?) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onLeave: (() -> Void)? = nil
    ) {
        self.collection = collection
        self.onSaveMetadata = onSaveMetadata
        self.onDelete = onDelete
        self.onLeave = onLeave
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // TOP OF SHEET: Interactive 3D FolderView (Smoothly animates open when sheet appears)
                    VStack(spacing: 8) {
                        MomentFolder(
                            items: collection.items,
                            isOpen: $isFolderOpen,
                            size: CGSize(width: 180, height: 178),
                            isLocked: true,
                            isShared: collection.isShared,
                            folderColor: collection.color,
                            category: collection.category,
                            onTapItem: { item in
                                selectedFragment = item
                            }
                        )
                        .padding(.top, 80)
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)

                    // METADATA & INFORMATION SECTION
                    VStack(alignment: .leading, spacing: 18) {

                        // 2. Metadata Grid (Fragments, Location, Date & Time, Category)
                        VStack(spacing: 14) {
                            if let symbol = MomentCategory.symbol(for: collection.category) {
                                metadataRow(
                                    icon: symbol,
                                    iconColor: .primary,
                                    title: "Category",
                                    value: collection.category
                                )
                            }

                            metadataRow(
                                icon: "square.stack.3d.up.fill",
                                iconColor: .primary,
                                title: "Fragments Count",
                                value: collection.fragmentCountText
                            )

                            metadataRow(
                                icon: "mappin.and.ellipse",
                                iconColor: .primary,
                                title: "Location",
                                value: collection.location
                            )

                            metadataRow(
                                icon: "calendar.badge.clock",
                                iconColor: .primary,
                                title: "Time & Date",
                                value: collection.formattedDateTime
                            )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(collection.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showColorPicker = true
                    } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 16))

                    }
                    .accessibilityLabel("Customize folder color")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSharedByOthers {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showLeaveConfirmation = true
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                .font(.system(size: 20))
                        }
                        .tint(.red)
                        .accessibilityLabel("Leave moment")
                    } else {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16))
                        }
                        .tint(.red)
                        .accessibilityLabel("Delete moment")
                    }
                }
            }
            .alert("Delete Moment?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let onDelete = onDelete {
                        onDelete()
                    } else {
                        MomentManager.shared.deleteMoment(id: collection.id, roomID: collection.roomID)
                    }
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(collection.name)\"? This action cannot be undone.")
            }
            .alert("Leave Moment?", isPresented: $showLeaveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let onLeave = onLeave {
                        onLeave()
                    } else {
                        MomentManager.shared.leaveMoment(id: collection.id, roomID: collection.roomID)
                    }
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to leave \"\(collection.name)\"? The moment will be removed from your device but will remain for the owner.")
            }
            .blur(radius: showColorPicker ? 16 : 0)
            .animation(.easeInOut(duration: 0.28), value: showColorPicker)
            .sheet(isPresented: $showColorPicker) {
                FolderColorPickerSheet(
                    items: collection.items,
                    initialName: collection.name,
                    initialCategory: collection.category,
                    initialColor: collection.color
                ) { name, category, color in
                    onSaveMetadata?(name, category, color)
                    dismiss()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
            .presentationDetents([.medium, .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .scrollIndicators(.hidden)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                        isFolderOpen = true
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func metadataRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
    }

    private func fragmentCardRow(item: FolderItem) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Group {
                        if let sysImg = item.systemImage {
                            Image(systemName: sysImg)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Fragment" : item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let tag = item.tag {
                Text(tag)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}

// MARK: - 6 Curated Folder Colors (Including Default)

public struct FolderThemeColor: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let color: Color?
    public let swatchGradient: [Color]

    public static let defaultTheme = FolderThemeColor(
        id: "default",
        name: "Default",
        color: nil,
        swatchGradient: [
            Color.white,
            Color(red: 0.15, green: 0.15, blue: 0.15)
        ]
    )

    public static let allThemes: [FolderThemeColor] = [
        defaultTheme,
        FolderThemeColor(
            id: "amber",
            name: "Amber",
            color: Color(red: 1.0, green: 0.58, blue: 0.20),
            swatchGradient: [Color.orange, Color(red: 1.0, green: 0.40, blue: 0.20)]
        ),
        FolderThemeColor(
            id: "ocean",
            name: "Ocean",
            color: Color(red: 0.15, green: 0.55, blue: 0.98),
            swatchGradient: [Color.cyan, Color.blue]
        ),
        FolderThemeColor(
            id: "emerald",
            name: "Emerald",
            color: Color(red: 0.20, green: 0.76, blue: 0.55),
            swatchGradient: [Color.mint, Color.teal]
        ),
        FolderThemeColor(
            id: "violet",
            name: "Violet",
            color: Color(red: 0.65, green: 0.40, blue: 0.92),
            swatchGradient: [Color.purple, Color.indigo]
        ),
        FolderThemeColor(
            id: "rose",
            name: "Rose",
            color: Color(red: 1.0, green: 0.35, blue: 0.55),
            swatchGradient: [Color(red: 1.0, green: 0.45, blue: 0.65), Color.pink]
        )
    ]

    /// Resolves the theme matching a saved color (nil = Default theme).
    public static func theme(for color: Color?) -> FolderThemeColor {
        allThemes.first(where: { $0.color == color }) ?? defaultTheme
    }
}

// MARK: - Edit Moment Sheet (name + category + color, Complete-Sheet style)

/// Edit Moment form presented from a moment's detail sheet. Mirrors the
/// Complete Moment Sheet sections (MOMENT NAME / CATEGORY / FOLDER COLOR)
/// with values pre-populated from the saved moment. Save persists via
/// `onSave`; drafts never touch the manager until then.
public struct FolderColorPickerSheet: View {
    public var items: [FolderItem] = []
    public var initialName: String = ""
    public var initialCategory: String = "Life"
    public var onSave: ((String, String, Color?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var editName: String
    @State private var selectedCategory: String
    @State private var selectedTheme: FolderThemeColor

    public init(
        items: [FolderItem] = [],
        initialName: String = "",
        initialCategory: String = "Life",
        initialColor: Color? = nil,
        onSave: ((String, String, Color?) -> Void)? = nil
    ) {
        self.items = items
        self.initialName = initialName
        self.initialCategory = initialCategory
        self.onSave = onSave
        self._editName = State(initialValue: initialName)
        self._selectedCategory = State(initialValue: initialCategory)
        self._selectedTheme = State(initialValue: FolderThemeColor.theme(for: initialColor))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Live preview reflecting the draft color
                    MomentFolder(
                        items: items,
                        isOpen: .constant(false),
                        size: CGSize(width: 156, height: 154),
                        isLocked: true,
                        folderColor: selectedTheme.color
                    )
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    // Moment Title Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MOMENT NAME")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        TextField(initialName.isEmpty ? "Moment name" : initialName, text: $editName)
                            .font(.system(size: 16, weight: .medium))
                            .padding(14)
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)

                    // Category / Vibe Pills
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CATEGORY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MomentCategory.allCategoryNames, id: \.self) { cat in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedCategory = cat
                                    } label: {
                                        HStack(spacing: 6) {
                                            if let symbol = MomentCategory.symbol(for: cat) {
                                                Image(systemName: symbol)
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            Text(cat)
                                                .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .medium, design: .rounded))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedCategory == cat
                                            ? AnyShapeStyle(Color.primary)
                                            : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(
                                            selectedCategory == cat
                                            ? Color(uiColor: .systemBackground) : .primary
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Theme Color Palette
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOLDER COLOR")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 24) {
                            ForEach(FolderThemeColor.allThemes) { theme in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedTheme = theme
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: theme.swatchGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 38, height: 38)
                                            .shadow(color: (theme.color ?? Color.gray).opacity(0.3), radius: 4, y: 2)

                                        if selectedTheme.id == theme.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(selectedTheme.id == theme.id ? Color.primary : Color.clear, lineWidth: 2)
                                            .padding(-3)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Edit Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave?(trimmed.isEmpty ? initialName : trimmed, selectedCategory, selectedTheme.color)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .glassProminentButtonStyle()
                    .tint(.blue)
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}

private extension Color {
    static let roseGold = Color(red: 0.95, green: 0.65, blue: 0.70)
}

// MARK: - Pressable Feedback Modifier

private struct PressableFeedbackModifier: ViewModifier {
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: .infinity)
                    .updating($isPressed) { currentState, gestureState, _ in
                        gestureState = currentState
                    }
            )
    }
}

extension View {
    func pressableFeedback() -> some View {
        modifier(PressableFeedbackModifier())
    }
}


// MARK: - Previews

#if DEBUG
#Preview("Logs View") {
    MomentsView()
}

struct MomentsView_Previews: PreviewProvider {
    static var previews: some View {
        MomentsView()
    }
}
#endif
