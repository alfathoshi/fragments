//
//  RoomCardView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI

/// Visually rich card representing a collaborative Room in `RoomsListView`.
public struct RoomCardView: View {
    public let room: Room
    public var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(room: Room, onTap: @escaping () -> Void) {
        self.room = room
        self.onTap = onTap
    }

    private var accentColor: Color {
        if let hex = room.accentColorHex {
            return Color.fromRGBAString(hex)
        }
        return Color.purple
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Top Row: Emoji badge & status
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12))
                            .frame(width: 48, height: 48)

                        Text(room.emoji)
                            .font(.system(size: 24))
                    }

                    Spacer()

                    if room.isArchived {
                        Text("Archived")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }

                // Middle: Room Name
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(room.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .opacity(0.5)

                // Bottom: People & Fragments metadata
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)

                        Text("\(room.memberCount) \(room.memberCount == 1 ? "person" : "people")")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 10))

                    HStack(spacing: 5) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("\(room.fragmentCount) \(room.fragmentCount == 1 ? "fragment" : "fragments")")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
