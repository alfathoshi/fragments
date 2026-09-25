//
//  RoomsListView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI

/// Main listing view for the user's private collaborative Rooms.
public struct RoomsListView: View {
    @State private var roomManager = RoomManager.shared
    @State private var selectedRoom: Room? = nil
    @State private var showCreateSheet: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if roomManager.rooms.isEmpty && !roomManager.isLoading {
                emptyRoomsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(roomManager.rooms) { room in
                            RoomCardView(room: room) {
                                selectedRoom = room
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await roomManager.refreshFromCloudKit()
                }
            }
        }
        .navigationDestination(item: $selectedRoom) { room in
            RoomDetailView(room: room)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateRoomSheet { newRoom in
                // Immediate navigation to newly created room
                selectedRoom = newRoom
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .task {
            await roomManager.refreshFromCloudKit()
        }
    }

    // MARK: - Empty State View
    private var emptyRoomsView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.purple)
            }

            VStack(spacing: 8) {
                Text("No Shared Rooms Yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Create a private Room to capture fragments together with people you invite.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCreateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Create Room")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.purple, in: Capsule())
                .shadow(color: Color.purple.opacity(0.35), radius: 8, y: 3)
            }
            .padding(.top, 8)

            Spacer(minLength: 80)
        }
    }
}
