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

    public init(
        id: UUID = UUID(),
        name: String,
        location: String,
        date: Date,
        items: [FolderItem],
        color: Color? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.date = date
        self.items = items
        self.color = color
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

// MARK: - Logs View

struct MomentsView: View {
    // MARK: - State

    var momentManager: MomentManager = MomentManager.shared
    @State private var isEditing: Bool = false
    @State private var editingCollection: FolderCollection? = nil
    @State private var selectedDetailCollection: FolderCollection? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if momentManager.collections.isEmpty {
                    emptyStateView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 2-Column Grid
                            LazyVGrid(columns: columns, spacing: 24) {
                                ForEach(momentManager.collections) { collection in
                                    Button {
                                        handleMomentSelection(collection)
                                    } label: {
                                        VStack(alignment: .center, spacing: 12) {
                                            // Folder in closed resting preview state
                                            MomentFolder(
                                                items: collection.items,
                                                isOpen: .constant(false),
                                                size: CGSize(width: 168, height: 166),
                                                folderColor: collection.color,
                                                onTapFolder: {
                                                    handleMomentSelection(collection)
                                                }
                                            )
                                            .overlay(alignment: .topTrailing) {
                                                if isEditing {
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
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Moments")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                if !momentManager.collections.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isEditing.toggle()
                            }
                        } label: {
                            Text(isEditing ? "Done" : "Edit")
                                .font(.system(size: 16, weight: isEditing ? .bold : .medium))
                        }
                    }
                }
            }
            .blur(radius: editingCollection != nil ? 16 : 0)
            .animation(.easeInOut(duration: 0.28), value: editingCollection != nil)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: momentManager.collections.count)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isEditing)
            // Bottom Sheet opened when Edit mode is active and moment is picked
            .sheet(item: $editingCollection) { collection in
                FolderDetailBottomSheet(
                    collection: collection,
                    onUpdateColor: { newColor in
                        momentManager.updateMomentColor(id: collection.id, color: newColor)
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            momentManager.deleteMoment(id: collection.id)
                        }
                    }
                )
            }
            // Navigation destination pushed on moment tap (Normal mode)
            .navigationDestination(item: $selectedDetailCollection) { collection in
                let currentCollection = momentManager.collections.first(where: { $0.id == collection.id }) ?? collection
                MomentDetailView(
                    collection: currentCollection,
                    onUpdateCollection: { updated in
                        momentManager.updateMomentItems(id: updated.id, items: updated.items)
                        if let idx = momentManager.collections.firstIndex(where: { $0.id == updated.id }) {
                            momentManager.collections[idx] = updated
                        }
                    }
                )
            }
        }
    }

    private func handleMomentSelection(_ collection: FolderCollection) {
        if isEditing {
            editingCollection = collection
        } else {
            selectedDetailCollection = collection
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
                Text("No Moments Yet")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Start a moment by capturing fragments")
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
    public var onUpdateColor: ((Color?) -> Void)? = nil
    public var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var folderColor: Color?
    @State private var showColorPicker = false
    @State private var selectedFragment: FolderItem? = nil
    @State private var isFolderOpen = false
    @State private var sheetDetent: PresentationDetent = .fraction(0.38)
    @State private var showDeleteConfirmation = false

    public init(
        collection: FolderCollection,
        onUpdateColor: ((Color?) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.collection = collection
        self.onUpdateColor = onUpdateColor
        self.onDelete = onDelete
        self._folderColor = State(initialValue: collection.color)
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
                            folderColor: folderColor,
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

                        // 2. Metadata Grid (Fragments, Location, Date & Time)
                        VStack(spacing: 14) {
                            metadataRow(
                                icon: "square.stack.3d.up.fill",
                                iconColor: .blue,
                                title: "Fragments Count",
                                value: collection.fragmentCountText
                            )

                            metadataRow(
                                icon: "mappin.and.ellipse",
                                iconColor: .red,
                                title: "Location",
                                value: collection.location
                            )

                            metadataRow(
                                icon: "calendar.badge.clock",
                                iconColor: .orange,
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
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 20))
                        
                    }
                    .accessibilityLabel("Customize folder color")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20))
                    }
                    .tint(.red)
                    .accessibilityLabel("Delete moment")
                }
            }
            .alert("Delete Moment?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let onDelete = onDelete {
                        onDelete()
                    } else {
                        MomentManager.shared.deleteMoment(id: collection.id)
                    }
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(collection.name)\"? This action cannot be undone.")
            }
            .blur(radius: showColorPicker ? 16 : 0)
            .animation(.easeInOut(duration: 0.28), value: showColorPicker)
            .sheet(isPresented: $showColorPicker) {
                FolderColorPickerSheet(items: collection.items, selectedColor: $folderColor) { newColor in
                    onUpdateColor?(newColor)
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
}

// MARK: - 6-Color Palette Sheet

public struct FolderColorPickerSheet: View {
    public var items: [FolderItem] = []
    @Binding public var selectedColor: Color?
    public var onColorChanged: ((Color?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isFolderOpen = false

    public init(
        items: [FolderItem] = [],
        selectedColor: Binding<Color?>,
        onColorChanged: ((Color?) -> Void)? = nil
    ) {
        self.items = items
        self._selectedColor = selectedColor
        self.onColorChanged = onColorChanged
    }

    private var previewItems: [FolderItem] {
        items
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                // Live FolderView preview dynamically updating its background color
                MomentFolder(
                    items: previewItems,
                    isOpen: .constant(false),
                    size: CGSize(width: 156, height: 154),
                    isLocked: true,
                    folderColor: selectedColor
                )
                .padding(.top, 20)
                .padding(.bottom, 8)

                // 6 Swatches in a balanced row
                HStack(spacing: 16) {
                    ForEach(FolderThemeColor.allThemes) { theme in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                selectedColor = theme.color
                                onColorChanged?(theme.color)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: theme.swatchGradient,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                        .shadow(color: (theme.color ?? Color.gray).opacity(0.35), radius: 6, y: 3)

                                    if isSelected(theme) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.35), radius: 2)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(isSelected(theme) ? Color.primary : Color.clear, lineWidth: 2.5)
                                        .padding(-4)
                                )

                                Text(theme.name)
                                    .font(.system(size: 11, weight: isSelected(theme) ? .bold : .medium))
                                    .foregroundStyle(isSelected(theme) ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Spacer()
            }
            .navigationTitle("Folder Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func isSelected(_ theme: FolderThemeColor) -> Bool {
        if let themeColor = theme.color, let current = selectedColor {
            return themeColor == current
        }
        return theme.color == nil && selectedColor == nil
    }
}

private extension Color {
    static let roseGold = Color(red: 0.95, green: 0.65, blue: 0.70)
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
