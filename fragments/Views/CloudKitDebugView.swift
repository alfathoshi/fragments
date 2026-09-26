//
//  CloudKitDebugView.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import CloudKit

/// Temporary developer test harness to validate end-to-end multi-user CloudKit collaboration
/// across Owner, Participant, Permission, Account Isolation, and Cache flows.
public struct CloudKitDebugView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State Properties
    @State private var accountStatusText: String = "Checking..."
    @State private var currentUserIDText: String = "Loading..."
    @State private var activeRoom: Room? = nil
    @State private var activeShare: CKShare? = nil
    @State private var isShowingShareSheet: Bool = false

    @State private var newRoomName: String = "New Shared Room"
    @State private var newRoomEmoji: String = "🌴"
    @State private var invitationURLText: String = ""

    @State private var testFragmentTitle: String = "Sunset in Uluwatu"
    @State private var testFragmentText: String = "Shared CloudKit test from Participant"

    @State private var consoleLogs: [String] = []
    @State private var isExecuting: Bool = false

    private let cloudKitService = CloudKitService.shared
    private let identityService = UserIdentityService.shared
    private let roomRepository = CloudKitRoomRepository.shared
    private let localCache = LocalRoomCache.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                accountSection
                ownerSection
                participantSection
                diagnosticsSection
                consoleSection
            }
            .navigationTitle("CloudKit Debug Flow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        consoleLogs.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let share = activeShare {
                    CloudSharingSheet(share: share) {
                        log("Share sheet dismissed.")
                    }
                }
            }
            .task {
                await refreshAccountInfo()
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("1. iCloud Account & Identity") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(accountStatusText)
                        .foregroundStyle(accountStatusText.contains("connected") ? .green : .orange)
                }
                HStack {
                    Text("User ID:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(currentUserIDText)
                        .font(.caption)
                        .monospaced()
                        .lineLimit(1)
                }
                HStack {
                    Text("Container:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("iCloud.com.alfathoshi.fragments")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            Button {
                Task { await refreshAccountInfo() }
            } label: {
                Label("Re-verify Account Status", systemImage: "arrow.clockwise")
            }
            .disabled(isExecuting)
        }
    }

    private var ownerSection: some View {
        Section("2. Owner Flow (Account A)") {
            HStack {
                TextField("Room Name", text: $newRoomName)
                TextField("Emoji", text: $newRoomEmoji)
                    .frame(width: 50)
            }

            Button {
                Task { await createTestRoom() }
            } label: {
                Label("Create Room & CKShare", systemImage: "plus.circle.fill")
            }
            .disabled(isExecuting)

            if let room = activeRoom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Room: \(room.emoji) \(room.name)")
                        .fontWeight(.bold)
                    Text("ID: \(room.id)")
                        .font(.caption2).monospaced()
                    Text("Zone: \(room.zoneName ?? "N/A")")
                        .font(.caption2).monospaced()
                    if let shareID = room.shareRecordID {
                        Text("Share ID: \(shareID)")
                            .font(.caption2).monospaced().foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    isShowingShareSheet = true
                } label: {
                    Label("Present Native Share Sheet", systemImage: "square.and.arrow.up")
                }
                .disabled(activeShare == nil)

                Button {
                    Task { await fetchRoomFragments(roomID: room.id) }
                } label: {
                    Label("Fetch Room's Fragments", systemImage: "photo.stack")
                }
            }
        }
    }

    private var participantSection: some View {
        Section("3. Participant Flow (Account B)") {
            TextField("Paste iCloud Share URL", text: $invitationURLText)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            Button {
                Task { await acceptShareFromURL() }
            } label: {
                Label("Accept Share From URL", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(isExecuting || invitationURLText.isEmpty)

            Button {
                Task { await discoverSharedRooms() }
            } label: {
                Label("Discover Shared Rooms in Shared DB", systemImage: "magnifyingglass")
            }
            .disabled(isExecuting)

            if let room = activeRoom {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Fragment Title", text: $testFragmentTitle)
                    TextField("Fragment Text", text: $testFragmentText)

                    Button {
                        Task { await writeTestFragment(roomID: room.id) }
                    } label: {
                        Label("Write Fragment as Participant", systemImage: "square.and.pencil")
                    }
                    .disabled(isExecuting)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("4. Verification & Diagnostics") {
            Button {
                Task { await inspectMembersAndParticipants() }
            } label: {
                Label("Inspect Members & CKShare.participants", systemImage: "person.3")
            }
            .disabled(isExecuting || activeRoom == nil)

            Button {
                Task { await testOfflineCacheRead() }
            } label: {
                Label("Test Offline Cache Read-Through", systemImage: "internaldrive")
            }

            Button {
                Task { await runFullAutomatedTest() }
            } label: {
                Label("Run Full Automated Validation Suite", systemImage: "checkmark.seal.fill")
            }
            .foregroundStyle(.purple)
        }
    }

    private var consoleSection: some View {
        Section("Live Diagnostics Log") {
            if consoleLogs.isEmpty {
                Text("No operations logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(consoleLogs.indices.reversed(), id: \.self) { idx in
                    Text(consoleLogs[idx])
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Actions

    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        consoleLogs.append("[\(timestamp)] \(message)")
    }

    private func refreshAccountInfo() async {
        let status = await cloudKitService.checkAccountStatus()
        accountStatusText = status.localizedDescription

        let identity = await identityService.resolveUserIdentity()
        if let id = identity?.id {
            currentUserIDText = id
            log("Account active: \(id) (\(identity?.displayName ?? "Unknown"))")
        } else {
            currentUserIDText = "Unavailable (Offline or no iCloud account)"
            log("Warning: No iCloud identity resolved.")
        }
    }

    private func createTestRoom() async {
        isExecuting = true
        defer { isExecuting = false }

        log("Creating Room '\(newRoomName)' with dedicated CKRecordZone...")
        do {
            let (room, share) = try await roomRepository.createRoom(
                name: newRoomName,
                emoji: newRoomEmoji,
                accentColorHex: "#FF5733"
            )
            self.activeRoom = room
            self.activeShare = share

            // Cache locally
            try? localCache.saveRoom(room)

            log("✅ Room created successfully! ID: \(room.id)")
            log("✅ Dedicated zone: \(room.zoneName ?? "N/A")")
            log("✅ CKShare record: \(share.recordID.recordName), publicPermission: \(share.publicPermission == .none ? ".none" : "public")")
        } catch {
            log("❌ Room creation failed: \(error.localizedDescription)")
        }
    }

    private func fetchRoomFragments(roomID: String) async {
        isExecuting = true
        defer { isExecuting = false }

        log("Fetching SharedFragments for Room '\(roomID)'...")
        do {
            let frags = try await roomRepository.fetchFragments(roomID: roomID)
            log("✅ Retrieved \(frags.count) fragment(s):")
            for f in frags {
                log("  • [\(f.type.displayName)] '\(f.title)' by '\(f.authorName)' (id: \(f.id))")
            }
        } catch {
            log("❌ Fetch fragments failed: \(error.localizedDescription)")
        }
    }

    private func acceptShareFromURL() async {
        guard let url = URL(string: invitationURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            log("❌ Invalid URL format.")
            return
        }

        isExecuting = true
        defer { isExecuting = false }

        log("Accepting CloudKit share from URL: \(url.absoluteString)...")
        do {
            let (room, share) = try await roomRepository.acceptShare(with: url)
            self.activeRoom = room
            self.activeShare = share
            try? localCache.saveRoom(room)
            log("✅ Share accepted successfully! Room: \(room.emoji) \(room.name)")
        } catch {
            log("❌ Share acceptance failed: \(error.localizedDescription)")
        }
    }

    private func discoverSharedRooms() async {
        isExecuting = true
        defer { isExecuting = false }

        log("Discovering shared rooms in sharedCloudDatabase...")
        do {
            let sharedRooms = try await roomRepository.fetchSharedRooms()
            log("✅ Found \(sharedRooms.count) shared room(s) in sharedCloudDatabase:")
            for r in sharedRooms {
                log("  • \(r.emoji) \(r.name) (ID: \(r.id))")
            }
            if let first = sharedRooms.first {
                self.activeRoom = first
            }
        } catch {
            log("❌ Discovery failed: \(error.localizedDescription)")
        }
    }

    private func writeTestFragment(roomID: String) async {
        isExecuting = true
        defer { isExecuting = false }

        guard let identity = identityService.currentUserIdentity else {
            log("❌ Cannot write fragment: No user identity found.")
            return
        }

        let fragment = SharedFragment(
            id: UUID().uuidString,
            roomId: roomID,
            authorId: identity.id,
            authorName: identity.displayName,
            type: .note,
            title: testFragmentTitle,
            text: testFragmentText,
            location: "Uluwatu, Bali"
        )

        log("Writing SharedFragment '\(fragment.title)' as author '\(fragment.authorName)'...")
        do {
            try await roomRepository.saveFragment(fragment)
            log("✅ Fragment written successfully! ID: \(fragment.id)")
        } catch {
            log("❌ Write fragment failed: \(error.localizedDescription)")
        }
    }

    private func inspectMembersAndParticipants() async {
        guard let room = activeRoom else { return }

        isExecuting = true
        defer { isExecuting = false }

        log("Inspecting members for Room '\(room.name)'...")

        // 1. CKShare.participants (Source of truth for permissions)
        do {
            let participants = try await roomRepository.fetchShareParticipants(for: room)
            log("• CKShare.participants (\(participants.count) total):")
            for p in participants {
                let roleDesc = p.role == .owner ? "Owner" : "User"
                let permDesc = p.permission == .readWrite ? "Read/Write" : "Read-Only"
                let statusDesc: String
                switch p.acceptanceStatus {
                case .accepted: statusDesc = "Accepted"
                case .pending: statusDesc = "Pending"
                case .removed: statusDesc = "Removed"
                @unknown default: statusDesc = "Unknown"
                }
                log("   - [\(roleDesc)] Status: \(statusDesc), Permission: \(permDesc)")
            }
        } catch {
            log("• Could not fetch CKShare.participants: \(error.localizedDescription)")
        }

        // 2. Application RoomMember records
        do {
            let members = try await roomRepository.fetchMembers(roomID: room.id)
            log("• App-level RoomMember records (\(members.count) total):")
            for m in members {
                log("   - \(m.displayName) (Role: \(m.role.rawValue), ID: \(m.userId))")
            }
        } catch {
            log("• Could not fetch RoomMember records: \(error.localizedDescription)")
        }
    }

    private func testOfflineCacheRead() async {
        log("Testing offline cache read-through...")
        do {
            let cached = try localCache.loadRooms()
            log("✅ LocalRoomCache loaded \(cached.count) room(s) offline:")
            for r in cached {
                log("   - \(r.emoji) \(r.name) (ID: \(r.id))")
            }
        } catch {
            log("❌ Cache read failed: \(error.localizedDescription)")
        }
    }

    private func runFullAutomatedTest() async {
        isExecuting = true
        defer { isExecuting = false }

        log("=== Starting Automated Verification Suite ===")
        let (passed1, logs1) = CloudKitFoundationVerifier.runAllTests()
        for l in logs1 { log(l) }
        log("Phase 1–3 Result: \(passed1 ? "ALL PASSED ✅" : "FAILED ❌")")

        let (passed2, logs2) = RoomsPhase4And5Verifier.runAllTests()
        for l in logs2 { log(l) }
        log("Phase 4–5 Result: \(passed2 ? "ALL PASSED ✅" : "FAILED ❌")")

        let (passed3, logs3) = CloudKitCollaborationValidator.runAllTests()
        for l in logs3 { log(l) }
        log("Phase 6 Result: \(passed3 ? "ALL PASSED ✅" : "FAILED ❌")")

        log("=== Automated Verification Complete ===")
    }
}
