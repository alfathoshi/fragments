//
//  RoomDetailView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import CloudKit

/// The collaborative shared memory space for a private Room.
public struct RoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let room: Room

    @State private var roomManager = RoomManager.shared
    @State private var selectedFragment: SharedFragment? = nil
    @State private var showMembersSheet: Bool = false
    @State private var showCaptureSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var activeShare: CKShare? = nil
    @State private var resolvedShareURL: URL? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init(room: Room) {
        self.room = room
    }

    private var accentColor: Color {
        if let hex = room.accentColorHex {
            return Color.fromRGBAString(hex)
        }
        return Color.purple
    }

    private var effectiveShareURL: URL {
        if let url = resolvedShareURL ?? activeShare?.url {
            return url
        }
        if let code = room.shareRecordID, !code.isEmpty {
            return URL(string: "fragments://room/join?code=\(code)") ?? URL(string: "fragments://room/join?id=\(room.id)")!
        }
        let encodedName = room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let createdTimestamp = room.createdAt.timeIntervalSince1970
        return URL(string: "fragments://room/join?id=\(room.id)&name=\(encodedName)&createdAt=\(createdTimestamp)") ?? URL(string: "fragments://room/join?id=\(room.id)")!
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // Room Meta Banner
                    roomMetaHeader

                    // Offline / Stale Warning if any
                    if let error = roomManager.lastError, !error.isEmpty {
                        offlineBanner(message: error)
                    }

                    // Content Canvas
                    if roomManager.isLoading && roomManager.fragments.isEmpty {
                        loadingStateView
                    } else if roomManager.fragments.isEmpty {
                        emptyRoomStateView
                    } else {
                        fragmentsGridView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // Padding for floating capture button
            }
            .refreshable {
                await roomManager.loadRoomDetails(roomID: room.id)
            }

            // Floating Bottom Bar with + Capture button
            floatingCaptureBar
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(room.emoji)
                        .font(.system(size: 16))
                    Text(room.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Members button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showMembersSheet = true
                    } label: {
                        Image(systemName: "person.2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    // Share / Invite button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                }
            }
        }
        .sheet(item: $selectedFragment) { fragment in
            SharedFragmentDetailView(fragment: fragment)
        }
        .sheet(isPresented: $showMembersSheet) {
            RoomMembersSheet(room: room)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [effectiveShareURL])
        }
        .fullScreenCover(isPresented: $showCaptureSheet) {
            // Reusing existing CaptureView with .room(room) context!
            CaptureView(
                isActive: true,
                captureContext: .room(room),
                onClose: {
                    showCaptureSheet = false
                }
            )
        }
        .task {
            roomManager.currentRoom = room
            await roomManager.loadRoomDetails(roomID: room.id)
            if room.backend != .supabase {
                if let share = try? await CloudKitRoomRepository.shared.getOrCreateShare(for: room) {
                    self.activeShare = share
                    if let url = share.url {
                        self.resolvedShareURL = url
                    }
                }
                if self.resolvedShareURL == nil {
                    if let lookupURL = await CloudKitRoomRepository.shared.lookupShareURL(for: room.id) {
                        self.resolvedShareURL = lookupURL
                    }
                }
            }
        }
        .onDisappear {
            if roomManager.currentRoom?.id == room.id && MomentManager.shared.activeSession?.room?.id != room.id {
                roomManager.stopRealtime(roomID: room.id)
                roomManager.currentRoom = nil
            }
        }
    }

    // MARK: - Header
    private var roomMetaHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 48, height: 48)

                Text(room.emoji)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text("\(max(room.memberCount, roomManager.members.count)) people")
                    Text("•")
                    Text("\(roomManager.fragments.count) fragments")
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showMembersSheet = true
            } label: {
                Text("People")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.top, 6)
    }

    // MARK: - Offline / Stale Banner
    private func offlineBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Viewing cached state. Offline.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Loading View
    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(accentColor)
                .padding(.top, 60)

            Text("Loading shared space...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State
    private var emptyRoomStateView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)

                Text(room.emoji)
                    .font(.system(size: 40))
            }

            VStack(spacing: 6) {
                Text("Nothing here yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Capture the first moment and let everyone add theirs.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCaptureSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Capture Moment")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(accentColor, in: Capsule())
                .shadow(color: accentColor.opacity(0.35), radius: 8, y: 3)
            }
            .padding(.top, 8)

            Spacer(minLength: 60)
        }
    }

    // MARK: - Fragments Grid View
    private var fragmentsGridView: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(roomManager.fragments) { fragment in
                SharedFragmentNode(fragment: fragment) {
                    selectedFragment = fragment
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Floating Bottom Bar
    private var floatingCaptureBar: some View {
        HStack {
            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCaptureSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Capture")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(accentColor, in: Capsule())
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 12, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }
}
