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

                            Text("\(members.count) \(members.count == 1 ? "participant" : "participants") in this private space")
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

                // Native Invitation Section
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isShowingShareSheet = true
                    } label: {
                        HStack {
                            Label("Invite People", systemImage: "person.badge.plus")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.purple)

                            Spacer()

                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(activeShare == nil)
                } footer: {
                    Text("Invitations use Apple's native private iCloud sharing. Only people you invite can view or capture fragments.")
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
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 38, height: 38)

                Text(member.displayName.prefix(1).uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.purple)
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
                .foregroundStyle(member.role == .owner ? Color.purple : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(member.role == .owner ? Color.purple.opacity(0.12) : Color.primary.opacity(0.06))
                )
        }
        .padding(.vertical, 3)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Fetch live share
        if let share = try? await roomRepo.fetchShare(for: room) {
            self.activeShare = share
        }

        // 2. Fetch members
        let fetched = (try? await roomRepo.fetchMembers(roomID: room.id)) ?? []
        if !fetched.isEmpty {
            self.members = fetched
        } else {
            // Fallback to local cache
            self.members = (try? LocalRoomCache.shared.loadMembers(roomID: room.id)) ?? []
        }
    }
}
