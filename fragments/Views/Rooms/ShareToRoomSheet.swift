//
//  ShareToRoomSheet.swift
//  fragments
//
//  Created on 9/28/26.
//

import SwiftUI

/// Sheet enabling users to publish an existing personal Fragment into an active collaborative Supabase Room.
public struct ShareToRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let fragment: Fragment
    public var onShared: ((Room) -> Void)?

    @State private var roomManager = RoomManager.shared
    @State private var isSharing: Bool = false
    @State private var sharingRoomID: String? = nil
    @State private var successRoomName: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    public init(fragment: Fragment, onShared: ((Room) -> Void)? = nil) {
        self.fragment = fragment
        self.onShared = onShared
    }

    private var eligibleRooms: [Room] {
        roomManager.eligibleSupabaseRooms
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if roomManager.isLoading && eligibleRooms.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading rooms...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else if eligibleRooms.isEmpty {
                    emptyStateView
                } else {
                    roomListView
                }

                // In-flight progress or success banner overlay
                if let successName = successRoomName {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 18, weight: .bold))

                            Text("Shared to \(successName)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 4)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: successRoomName)
                }
            }
            .navigationTitle("Share to Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSharing)
                }
            }
            .alert("Sharing Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unexpected error occurred while sharing.")
            }
            .task {
                await roomManager.refreshAllRooms()
            }
        }
    }

    // MARK: - Room List View
    private var roomListView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publish to Collaborative Room")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("A copy of this fragment and its media will be published for room participants. Your personal original remains local.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Active Rooms") {
                ForEach(eligibleRooms) { room in
                    roomRow(room)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Room Row Component
    private func roomRow(_ room: Room) -> some View {
        let isCurrentTarget = sharingRoomID == room.id

        return Button {
            guard !isSharing else { return }
            handleSelectRoom(room)
        } label: {
            HStack(spacing: 14) {
                // Room Emoji & Accent Background
                ZStack {
                    Circle()
                        .fill(
                            room.accentColorHex.flatMap { Color.fromRGBAString($0) }?.opacity(0.18)
                                ?? Color.purple.opacity(0.15)
                        )
                        .frame(width: 44, height: 44)

                    Text(room.emoji)
                        .font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(room.memberCount) \(room.memberCount == 1 ? "member" : "members")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrentTarget {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSharing ? Color.secondary.opacity(0.4) : Color.purple)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isSharing)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "door.left.hand.closed")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.purple)
            }

            VStack(spacing: 6) {
                Text("No Active Rooms")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("You don't have any active collaborative rooms yet. Create or join a room first from the Moments tab.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Share Action Execution
    private func handleSelectRoom(_ room: Room) {
        // Prevent rapid double-taps
        guard !isSharing else { return }
        isSharing = true
        sharingRoomID = room.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                _ = try await roomManager.sharePersonalFragment(fragment, to: room)

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.successRoomName = room.name
                }

                // Brief pause so user sees confirmation toast before dismissing
                try? await Task.sleep(nanoseconds: 800_000_000)

                await MainActor.run {
                    self.onShared?(room)
                    self.dismiss()
                }
            } catch let error as SupabaseRoomError {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.isSharing = false
                    self.sharingRoomID = nil
                    self.errorMessage = userFriendlyMessage(for: error)
                    self.showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.isSharing = false
                    self.sharingRoomID = nil
                    self.errorMessage = "Unable to share fragment. Please check your network connection and try again."
                    self.showErrorAlert = true
                }
            }
        }
    }

    // MARK: - Sanitized Error Mapping
    private func userFriendlyMessage(for error: SupabaseRoomError) -> String {
        switch error {
        case .notAuthenticated:
            return "Please sign in with your account to share to collaborative rooms."
        case .notFound:
            return "The selected room could not be found or has been closed."
        case .unauthorized:
            return "You are not authorized to share to this room."
        case .storageFailure:
            return "Failed to upload media. Please check your connection and try again."
        case .validationFailure(let reason):
            return reason
        default:
            return "Unable to share fragment to room. Please try again."
        }
    }
}
