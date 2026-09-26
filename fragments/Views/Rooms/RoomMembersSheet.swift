//
//  RoomMembersSheet.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import CloudKit

/// Lightweight, private members presentation sheet for a collaborative Room.
public struct RoomMembersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let room: Room

    @State private var members: [RoomMember] = []
    @State private var activeShare: CKShare? = nil
    @State private var isShowingShareSheet: Bool = false
    @State private var isShowingFallbackShareSheet: Bool = false
    @State private var isPreparingShare: Bool = false
    @State private var copiedLink: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private let roomManager = RoomManager.shared
    private let roomRepo = CloudKitRoomRepository.shared
    private let identityService = UserIdentityService.shared

    public init(room: Room) {
        self.room = room
    }

    public var body: some View {
        NavigationStack {
            List {
                // Room info header section
                Section {
                    HStack(spacing: 14) {
                        Text(room.emoji)
                            .font(.system(size: 32))
                            .frame(width: 52, height: 52)
                            .background(Color.primary.opacity(0.06), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("\(members.count) \(members.count == 1 ? "participant" : "participants") in this moment")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Members List
                Section("People") {
                    if isLoading && members.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else if members.isEmpty {
                        Text("No member details loaded.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            memberRow(member)
                        }
                    }
                }

                // Invitation Section
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isShowingFallbackShareSheet = true
                    } label: {
                        HStack {
                            Label("Share Link via...", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Invite & Share")
                } footer: {
                    Text("Share the invite link to collaborate in real-time.")
                        .font(.system(size: 12))
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let share = activeShare {
                    CloudSharingSheet(share: share) {
                        Task { await loadData() }
                    }
                }
            }
            .sheet(isPresented: $isShowingFallbackShareSheet) {
                let shareText = activeShare?.url?.absoluteString ?? "fragments://room/join?id=\(room.id)&name=\(room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                ShareSheet(activityItems: [shareText])
            }
            .task {
                await loadData()
            }
        }
    }

    private func memberRow(_ member: RoomMember) -> some View {
        let isCurrent = member.userId == identityService.currentUserIdentity?.id

        return HStack(spacing: 12) {
            // Avatar Circle
            ZStack {
                Circle()
                    .fill(.primary.opacity(0.15))
                    .frame(width: 38, height: 38)

                Text(member.displayName.prefix(1).uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if isCurrent {
                        Text("(You)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Joined \(member.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Role Badge
            Text(member.role.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(member.role == .owner ? Color.blue : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(member.role == .owner ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                )
        }
        .padding(.vertical, 3)
    }

    private func handleInviteTapped() {
        if let share = activeShare, share.url != nil {
            isShowingShareSheet = true
            return
        }

        isPreparingShare = true
        Task {
            let share = try? await roomRepo.getOrCreateShare(for: room)
            await MainActor.run {
                self.isPreparingShare = false
                if let share = share, share.url != nil {
                    self.activeShare = share
                    self.isShowingShareSheet = true
                } else {
                    // CloudKit share URL not yet generated (e.g. unauthenticated simulator)
                    // Fallback to presenting the system share sheet with direct room URL
                    self.activeShare = share
                    self.isShowingFallbackShareSheet = true
                }
            }
        }
    }

    private func handleCopyLink() {
        let linkToCopy: String
        if let url = activeShare?.url?.absoluteString {
            linkToCopy = url
        } else {
            linkToCopy = "fragments://room/join?id=\(room.id)&name=\(room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        UIPasteboard.general.string = linkToCopy
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedLink = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedLink = false
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Fetch live share (or provision if not yet created)
        if let share = try? await roomRepo.getOrCreateShare(for: room) {
            self.activeShare = share
        }

        // 2. Fetch members
        let fetched = (try? await roomRepo.fetchMembers(roomID: room.id)) ?? []
        if !fetched.isEmpty {
            self.members = fetched
        } else {
            // Fallback to local cache
            let cached = (try? LocalRoomCache.shared.loadMembers(roomID: room.id)) ?? []
            if !cached.isEmpty {
                self.members = cached
            } else {
                // Ensure owner is at least displayed
                let currentId = identityService.currentUserIdentity?.id ?? "local_user"
                let currentName = identityService.currentUserIdentity?.displayName ?? ProfileManager.shared.signature
                self.members = [
                    RoomMember(
                        id: "owner_\(room.id)",
                        roomId: room.id,
                        userId: currentId,
                        displayName: currentName,
                        role: .owner,
                        joinedAt: room.createdAt
                    )
                ]
            }
        }
    }
}
