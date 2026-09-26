//
//  CreateRoomSheet.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI

/// Streamlined sheet for creating a new private collaborative Room.
public struct CreateRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public var onRoomCreated: (Room) -> Void

    @State private var name: String = ""
    @State private var selectedEmoji: String = "🌴"
    @State private var selectedColorHex: String = "#A855F7" // Soft Purple
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    private let presetEmojis = ["🌴", "🎓", "🍕", "🏔️", "✨", "☕️", "🌊", "📸", "🎸", "🏕️", "✈️", "🎉"]
    private let presetColors: [(name: String, hex: String, color: Color)] = [
        ("Purple", "#A855F7", Color(red: 0.66, green: 0.33, blue: 0.97)),
        ("Coral", "#FB923C", Color(red: 0.98, green: 0.57, blue: 0.24)),
        ("Ocean", "#38BDF8", Color(red: 0.22, green: 0.74, blue: 0.97)),
        ("Emerald", "#34D399", Color(red: 0.20, green: 0.83, blue: 0.60)),
        ("Rose", "#F43F5E", Color(red: 0.96, green: 0.25, blue: 0.37))
    ]

    public init(onRoomCreated: @escaping (Room) -> Void) {
        self.onRoomCreated = onRoomCreated
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    // Header prompt
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's this moment about?")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Create a private space to capture fragments together with people you invite.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Emoji Preview & Name Input
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.fromRGBAString(selectedColorHex).opacity(0.18))
                                .frame(width: 58, height: 58)

                            Text(selectedEmoji)
                                .font(.system(size: 30))
                        }

                        TextField("Room Name (e.g. Summer Vacation)", text: $name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), lineWidth: 1)
                            )
                    }

                    // Emoji Selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose an Icon")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(presetEmojis, id: \.self) { emoji in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedEmoji = emoji
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 24))
                                            .frame(width: 46, height: 46)
                                            .background(
                                                Circle()
                                                    .fill(selectedEmoji == emoji ? Color.primary.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                                            )
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(selectedEmoji == emoji ? Color.primary.opacity(0.3) : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    // Accent Color Palette
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent Color")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 14) {
                            ForEach(presetColors, id: \.hex) { item in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedColorHex = item.color.toRGBAString()
                                } label: {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: selectedColorHex == item.color.toRGBAString() ? 3 : 0)
                                        )
                                        .shadow(color: item.color.opacity(0.4), radius: 6, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 30)

                    // Create Button
                    Button {
                        Task { await handleCreateRoom() }
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create Room")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.3)
                                : Color.fromRGBAString(selectedColorHex)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Could Not Create Room", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unexpected CloudKit error occurred. Please check your internet connection.")
            }
        }
    }

    private func handleCreateRoom() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let room = try await RoomManager.shared.createRoom(
                name: trimmed,
                emoji: selectedEmoji,
                accentColorHex: selectedColorHex
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onRoomCreated(room)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
}
