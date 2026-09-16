//
//  CustomNoteView.swift
//  fragments
//
//  Created on 9/14/26.
//  Faithfully implements Figma Node 178:3051 (Memo / Sticky Note Card)
//

import SwiftUI

public struct CustomNoteView: View {
    // MARK: - Callbacks & Inputs

    public var onSaveNote: ((String, String, Color) -> Void)? = nil
    public var onClose: (() -> Void)? = nil

    // MARK: - State

    @Environment(\.colorScheme) private var colorScheme
    @State private var noteTitle: String = ""
    @State private var memoText: String = ""
    @State private var selectedColorIndex: Int = 0
    @FocusState private var isTextFocused: Bool
    @FocusState private var isTitleFocused: Bool
    @State private var isSuccessFlash: Bool = false
    @State private var keyboardHeight: CGFloat = 0

    private var isEditing: Bool {
        isTextFocused || isTitleFocused
    }

    // MARK: - Color Palette (Default: Figma Node 178:3051 #FFDB93)

    public struct NoteColorOption: Identifiable {
        public let id = UUID()
        public let name: String
        public let color: Color
        public let hex: String
        public let gradient: [Color]
    }

    private let colorOptions: [NoteColorOption] = [
        // 1. Figma Node 178:3051 Butterscotch Yellow (#FFDB93)
        NoteColorOption(
            name: "Butterscotch",
            color: Color(red: 1.0, green: 0.859, blue: 0.576), // #FFDB93
            hex: "#FFDB93",
            gradient: [Color(red: 1.0, green: 0.859, blue: 0.576), Color(red: 0.98, green: 0.76, blue: 0.45)]
        ),
        // 2. Soft Mint
        NoteColorOption(
            name: "Mint",
            color: Color(red: 0.776, green: 0.965, blue: 0.835),
            hex: "#C6F6D5",
            gradient: [Color(red: 0.776, green: 0.965, blue: 0.835), Color(red: 0.65, green: 0.92, blue: 0.75)]
        ),
        // 3. Pastel Sky
        NoteColorOption(
            name: "Sky",
            color: Color(red: 0.745, green: 0.890, blue: 0.973),
            hex: "#BEE3F8",
            gradient: [Color(red: 0.745, green: 0.890, blue: 0.973), Color(red: 0.60, green: 0.82, blue: 0.95)]
        ),
        // 4. Lavender
        NoteColorOption(
            name: "Lavender",
            color: Color(red: 0.914, green: 0.847, blue: 0.992),
            hex: "#E9D8FD",
            gradient: [Color(red: 0.914, green: 0.847, blue: 0.992), Color(red: 0.84, green: 0.74, blue: 0.96)]
        ),
        // 5. Blush Coral
        NoteColorOption(
            name: "Blush",
            color: Color(red: 0.996, green: 0.843, blue: 0.843),
            hex: "#FED7D7",
            gradient: [Color(red: 0.996, green: 0.843, blue: 0.843), Color(red: 0.98, green: 0.72, blue: 0.72)]
        )
    ]

    private var activeColor: NoteColorOption {
        colorOptions[selectedColorIndex]
    }

    // MARK: - Dimensions (matching CustomCamera chassis)

    private let cardCornerRadius: CGFloat = 47
    private let viewportCornerRadius: CGFloat = 31

    // MARK: - Initializer

    public init(
        onSaveNote: ((String, String, Color) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.onSaveNote = onSaveNote
        self.onClose = onClose
    }

    public init(
        onSaveNote: ((String, Color) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        if let legacy = onSaveNote {
            self.onSaveNote = { _, text, color in
                legacy(text, color)
            }
        } else {
            self.onSaveNote = nil
        }
        self.onClose = onClose
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Card Chassis Background
            (colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)

            // Main Card Layout: Top Bar + Viewfinder Canvas + Bottom Bar
            VStack(spacing: 16) {

                // 2. Viewfinder Canvas hosting Figma Sticky Note
                memoCanvasViewport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                topControlsBar
                    .frame(height: 74)
                    .opacity(isEditing ? 0.0 : 1.0)
                    .allowsHitTesting(!isEditing)
                    .animation(.easeInOut(duration: 0.22), value: isEditing)

                // 3. Bottom Controls Bar: Clear + Save Tactile Button
                bottomControlsBar
                    .frame(height: 74)
                    .padding(.bottom, 2)
                    .opacity(isEditing ? 0.0 : 1.0)
                    .allowsHitTesting(!isEditing)
                    .animation(.easeInOut(duration: 0.22), value: isEditing)
            }
            .padding(16)

            // Flash overlay on save
            Color.white
                .opacity(isSuccessFlash ? 0.8 : 0.0)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 386, maxHeight: 804)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 8, x: 0, y: 3.5)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 2, x: 0, y: 1.0)
        .overlay {
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: isDark ? [
                            .init(color: Color.white.opacity(0.20), location: 0.0),
                            .init(color: Color.white.opacity(0.06), location: 0.25),
                            .init(color: Color.white.opacity(0.02), location: 0.85),
                            .init(color: Color.black.opacity(0.30), location: 1.0)
                        ] : [
                            .init(color: Color.white.opacity(0.95), location: 0.0),
                            .init(color: Color(red: 0.90, green: 0.90, blue: 0.92), location: 0.25),
                            .init(color: Color(red: 0.85, green: 0.85, blue: 0.88), location: 0.85),
                            .init(color: Color.black.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let userInfo = notification.userInfo,
                  let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            let isShowing = endFrame.minY < screenHeight
            let newHeight = isShowing ? endFrame.height : 0
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                keyboardHeight = newHeight
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
    }

    // MARK: - 1. Top Controls Bar

    private var topControlsBar: some View {
        let isDark = colorScheme == .dark

        return HStack(spacing: 12) {
            // Left: Color Palette Switcher
            HStack(spacing: 6) {
                ForEach(0..<colorOptions.count, id: \.self) { idx in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            selectedColorIndex = idx
                        }
                    } label: {
                        Circle()
                            .fill(colorOptions[idx].color)
                            .frame(width: selectedColorIndex == idx ? 22 : 16, height: selectedColorIndex == idx ? 22 : 16)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isDark ? Color(red: 0.18, green: 0.18, blue: 0.20) : Color(red: 0.949, green: 0.949, blue: 0.969), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Unattached Note Geometry Calculation

    private func calculateOffsetY(containerHeight: CGFloat, noteSize: CGFloat) -> CGFloat {
        guard isEditing else { return 0 }
        let bottomDistance: CGFloat = 214
        let effectiveKeyboardHeight: CGFloat = keyboardHeight > 0 ? keyboardHeight : 336
        let keyboardOverlap = max(0, effectiveKeyboardHeight - bottomDistance)
        let visibleHeight = max(noteSize + 32, containerHeight - keyboardOverlap)
        let targetCenterY = visibleHeight / 2
        let defaultCenterY = containerHeight / 2
        return targetCenterY - defaultCenterY
    }

    // MARK: - 2. Viewfinder Canvas hosting Figma Sticky Note (Node 178:3051)

    private var memoCanvasViewport: some View {
        let isDark = colorScheme == .dark

        return GeometryReader { proxy in
            let noteSize: CGFloat = min(proxy.size.width - 36, 286)
            let offsetY = calculateOffsetY(containerHeight: proxy.size.height, noteSize: noteSize)

            ZStack {
                // 1. Tactile canvas backdrop (clipped to viewport corner radius)
                ZStack {
                    RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                        .fill(isDark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(red: 0.93, green: 0.93, blue: 0.95))

                    // Subtle grid / canvas lines
                    Canvas { context, size in
                        let strokeColor = isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
                        let step: CGFloat = 24
                        for x in stride(from: 0, to: size.width, by: step) {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(path, with: .color(strokeColor), lineWidth: 0.5)
                        }
                        for y in stride(from: 0, to: size.height, by: step) {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(path, with: .color(strokeColor), lineWidth: 0.5)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous))

                // 2. Ghost Imprint (Where the note unattached from on the desk)
                if isEditing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(
                                        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                                    )
                            )

                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down.and.sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Memo in hand")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.22))
                    }
                    .frame(width: noteSize, height: noteSize)
                    .rotationEffect(.degrees(2.9))
                    .transition(.opacity)
                }

                // 3. Ambient Focus Dimming Backdrop (Tap outside to dismiss)
                if isEditing {
                    Color.black.opacity(isDark ? 0.20 : 0.08)
                        .clipShape(RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous))
                        .transition(.opacity)
                        .onTapGesture {
                            dismissKeyboard()
                        }
                }

                // 4. Sticky Note Card (Physical Unattached Floating Note)
                stickyNoteCard(in: proxy.size)
                    .offset(y: offsetY)
                    .scaleEffect(isEditing ? 1.02 : 1.0)
                    .rotationEffect(.degrees(isEditing ? 0.0 : 2.9))
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: isEditing)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: keyboardHeight)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditing {
                    dismissKeyboard()
                }
            }
        }
    }

    // MARK: - Sticky Note (Figma Node 178:3051)

    private func stickyNoteCard(in containerSize: CGSize) -> some View {
        let noteSize: CGFloat = min(containerSize.width - 36, 286)

        return ZStack(alignment: .topLeading) {
            // Background Paper: #FFDB93 with 4pt solid white border and 24pt corner radius
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(activeColor.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 4)
                )
                // Dynamic tactile drop shadow: elevates when unattached!
                .shadow(
                    color: Color.black.opacity(isEditing ? (colorScheme == .dark ? 0.40 : 0.20) : 0.12),
                    radius: isEditing ? 26 : 14,
                    x: 0,
                    y: isEditing ? 16 : 7
                )
                .shadow(
                    color: Color.black.opacity(isEditing ? 0.12 : 0.06),
                    radius: isEditing ? 8 : 3,
                    x: 0,
                    y: isEditing ? 4 : 1.5
                )

            // Content: Title field + Interactive TextEditor
            VStack(alignment: .leading, spacing: 6) {
                // Title Field
                HStack {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                    
                    TextField(
                        "Note Title",
                        text: $noteTitle,
                        prompt: Text("Note Title").foregroundStyle(Color.black.opacity(0.40))
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .tint(Color.black)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        dismissKeyboard()
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                
                
                Divider()
                    .padding(.horizontal, 16)

                // Body TextEditor with native-like prompt placeholder
                ZStack(alignment: .topLeading) {
                    if memoText.isEmpty {
                        Text("Write your memo...")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.black.opacity(0.40))
                            .padding(.horizontal, 17)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $memoText)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .tint(Color.black)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                }

                // Small bottom-right date indicator
                HStack {
                    Spacer()
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
            .frame(width: noteSize, height: noteSize)
        }
        .frame(width: noteSize, height: noteSize)
        .animation(.easeInOut(duration: 0.22), value: selectedColorIndex)
        .environment(\.colorScheme, .light)
    }

    // MARK: - 3. Bottom Controls Bar

    private var bottomControlsBar: some View {
        HStack(spacing: 0) {
            // Left: Clear / Erase Text Button (62 pt)
            TactileCircularButton(
                systemImage: "trash",
                iconColor: (memoText.isEmpty && noteTitle.isEmpty) ? Color.gray.opacity(0.4) : Color.red.opacity(0.85),
                keycapColor: nil,
                size: 62,
                iconSize: 20,
                iconWeight: .medium
            ) {
                if !memoText.isEmpty || !noteTitle.isEmpty {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        memoText = ""
                        noteTitle = ""
                    }
                }
            }
            .disabled(memoText.isEmpty && noteTitle.isEmpty)
            .accessibilityLabel("Clear Memo")

            Spacer(minLength: 0)

            // Center: Tactile Save / Plus Button (74 pt - matches Shutter / Record)
            TactileCircularButton(
                size: 74,
                keycapColor: nil,
                isActive: !memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                handleSaveNote()
            } content: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel("Save Memo Fragment")

            Spacer(minLength: 0)

            // Right: Empty balancing placeholder (62 pt - leaves right side empty while keeping Plus button centered)
            Color.clear
                .frame(width: 62, height: 62)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Keyboard Action

    private func dismissKeyboard() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isTextFocused = false
        isTitleFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Save Action

    private func handleSaveNote() {
        dismissKeyboard()
        let titleContent = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyContent = memoText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToSave = bodyContent.isEmpty ? "Write your memo..." : bodyContent

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeInOut(duration: 0.15)) {
            isSuccessFlash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isSuccessFlash = false
            }
            onSaveNote?(titleContent, textToSave, activeColor.color)
        }
    }
}


