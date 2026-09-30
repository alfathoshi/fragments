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
    @State private var resolvedShareURL: URL? = nil
    @State private var isShowingShareSheet: Bool = false
    @State private var isPreparingShare: Bool = false
    @State private var copiedLink: Bool = false
    @State private var copiedCode: Bool = false
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
                        Image(systemName: "sparkles")
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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        handleInviteTapped()
                    } label: {
                        HStack {
                            Label("Invite via iCloud", systemImage: "person.badge.plus")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))

                            Spacer()

                            if isPreparingShare {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isPreparingShare)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        handleCopyLink()
                    } label: {
                        HStack {
                            Label(copiedLink ? "Link Copied!" : "Copy Invite Link", systemImage: copiedLink ? "checkmark.circle.fill" : "link")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(copiedLink ? .green : .primary)

                            Spacer()

                            if copiedLink {
                                Text("Copied")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        handleCopyCode()
                    } label: {
                        HStack {
                            Label(copiedCode ? "Room Code Copied!" : "Copy Room Code", systemImage: copiedCode ? "checkmark.circle.fill" : "number.square")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(copiedCode ? .green : .primary)

                            Spacer()

                            Text(room.backend == .supabase ? (room.shareRecordID ?? "—") : String(room.id.prefix(8)))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Invite & Share")
                } footer: {
                    Text("To collaborate on another device, open Fragments, tap 'Join' on the Moments tab, and paste this link or room code.")
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
                ShareSheet(activityItems: shareActivityItems)
            }
            .task {
                await loadData()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { break }
                    await loadData()
                }
            }
        }
    }

    private func memberRow(_ member: RoomMember) -> some View {
        let isCurrent: Bool = {
            if room.backend == .supabase {
                if let currentUserID = identityService.collaborativeUserID {
                    return member.userId.caseInsensitiveCompare(currentUserID) == .orderedSame
                }
                return false
            }
            let currentUserId = identityService.currentUserIdentity?.id ?? "local_user"
            let currentUserName = identityService.currentUserIdentity?.displayName ?? ProfileManager.shared.signature
            return (member.userId == currentUserId) || (member.displayName == currentUserName)
        }()

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

    private var effectiveShareURL: URL {
        if room.backend == .supabase {
            // Credential link only when a server-assigned code exists. Otherwise
            // fall back to a non-credential id link (navigation only; the id
            // path never authorizes Supabase membership — see joinRoomDirect).
            if let code = room.shareRecordID, !code.isEmpty {
                let encodedName = room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return URL(string: "fragments://room/join?code=\(code)&name=\(encodedName)") ?? URL(string: "fragments://room/join?id=\(room.id)")!
            }
            let encodedName = room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let createdTimestamp = room.createdAt.timeIntervalSince1970
            return URL(string: "fragments://room/join?id=\(room.id)&name=\(encodedName)&createdAt=\(createdTimestamp)") ?? URL(string: "fragments://room/join?id=\(room.id)")!
        }
        if let url = resolvedShareURL ?? activeShare?.url {
            return url
        }
        let encodedName = room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let createdTimestamp = room.createdAt.timeIntervalSince1970
        return URL(string: "fragments://room/join?id=\(room.id)&name=\(encodedName)&createdAt=\(createdTimestamp)") ?? URL(string: "fragments://room/join?id=\(room.id)")!
    }

    private var shareActivityItems: [Any] {
        if room.backend == .supabase {
            if let code = room.shareRecordID, !code.isEmpty {
                return ["Join my shared moment \"\(room.name)\" on Fragments using room code: \(code)\n\(effectiveShareURL.absoluteString)"]
            }
            return [effectiveShareURL]
        }
        return [effectiveShareURL]
    }

    private func handleInviteTapped() {
        if room.backend == .supabase {
            isShowingShareSheet = true
            return
        }
        if resolvedShareURL != nil || (activeShare != nil && activeShare?.url != nil) {
            isShowingShareSheet = true
            return
        }

        isPreparingShare = true
        Task {
            if let share = try? await roomRepo.getOrCreateShare(for: room) {
                await MainActor.run {
                    self.activeShare = share
                    if let url = share.url {
                        self.resolvedShareURL = url
                    }
                }
            }
            if self.resolvedShareURL == nil {
                if let lookupURL = await roomRepo.lookupShareURL(for: room.id) {
                    await MainActor.run {
                        self.resolvedShareURL = lookupURL
                    }
                }
            }
            await MainActor.run {
                self.isPreparingShare = false
                self.isShowingShareSheet = true
            }
        }
    }

    private func handleCopyLink() {
        let linkToCopy = effectiveShareURL.absoluteString
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

    private func handleCopyCode() {
        // Never derive a code from room.id. Without a server-assigned code
        // there is nothing credential-like to copy.
        let codeToCopy = room.backend == .supabase ? (room.shareRecordID ?? "—") : room.id
        UIPasteboard.general.string = codeToCopy
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedCode = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedCode = false
            }
        }
    }

    private func loadData() async {
        if members.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        if room.backend == .supabase {
            var fetched = (try? await SupabaseRoomRepository.shared.fetchMembers(roomID: room.id)) ?? []
            // Self-patch: the current user always resolves from local identity so a
            // DB-default placeholder ("Fragment Explorer"/"Member") never renders for self.
            // Mirrors the CloudKit branch below; preserves invite flows (read-only mapping).
            let localEffectiveName = ProfileManager.shared.effectiveName
            if !RoomMember.isUnresolvedDisplayName(localEffectiveName) {
                let currentSupabaseID = SupabaseService.shared.currentUserID
                let currentCloudID = identityService.currentUserIdentity?.id
                for i in fetched.indices where RoomMember.isUnresolvedDisplayName(fetched[i].displayName) {
                    let matchesSupabase = currentSupabaseID.map { fetched[i].userId.caseInsensitiveCompare($0) == .orderedSame } ?? false
                    let matchesCloud = currentCloudID.map { fetched[i].userId == $0 } ?? false
                    if matchesSupabase || matchesCloud {
                        fetched[i].displayName = localEffectiveName
                    }
                }
            }
            fetched.sort {
                if $0.role == .owner && $1.role != .owner { return true }
                if $0.role != .owner && $1.role == .owner { return false }
                return $0.joinedAt < $1.joinedAt
            }
            let resolved = fetched
            await MainActor.run {
                self.members = resolved
            }
            // One-shot backfill for remaining unresolved peers (does not alter invite/share logic).
            let pending = resolved.filter { RoomMember.isUnresolvedDisplayName($0.displayName) }
            if !pending.isEmpty {
                var backfilled = resolved
                for i in backfilled.indices where RoomMember.isUnresolvedDisplayName(backfilled[i].displayName) {
                    if let uuid = UUID(uuidString: backfilled[i].userId),
                       let profile = try? await SupabaseRoomRepository.shared.fetchUserProfile(userID: uuid),
                       !RoomMember.isUnresolvedDisplayName(profile.displayName) {
                        backfilled[i].displayName = profile.displayName
                    }
                }
                let final = backfilled
                await MainActor.run {
                    self.members = final
                }
            }
            return
        }

        // 1. Fetch live share (or provision if not yet created)
        if let share = try? await roomRepo.getOrCreateShare(for: room) {
            self.activeShare = share
            if let url = share.url {
                self.resolvedShareURL = url
            }
        }
        if self.resolvedShareURL == nil {
            if let lookupURL = await roomRepo.lookupShareURL(for: room.id) {
                self.resolvedShareURL = lookupURL
            }
        }

        // 2. Fetch members from CloudKit custom zone + public relay
        let fetched = (try? await roomRepo.fetchMembers(roomID: room.id)) ?? []

        // 3. Identify the current user
        let currentUserId = identityService.currentUserIdentity?.id ?? "local_user"
        let currentUserName = ProfileManager.shared.effectiveName
        let isCurrentHost = room.isCurrentUserOwner || (MomentManager.shared.activeSession?.isHost ?? false)

        // Collect all known CKShare participant record-names so we can cross-match
        var shareParticipantIDs: Set<String> = []
        if let participants = activeShare?.participants {
            for p in participants {
                if let rid = p.userIdentity.userRecordID?.recordName {
                    shareParticipantIDs.insert(rid)
                }
            }
        }

        // Helper: checks if a member matches the current user by userId OR displayName
        func isCurrentUser(_ m: RoomMember) -> Bool {
            m.userId == currentUserId ||
            m.displayName.localizedCaseInsensitiveCompare(currentUserName) == .orderedSame
        }

        // Helper: checks if a name is a placeholder (not a real username/signature)
        func isPlaceholderName(_ name: String) -> Bool {
            RoomMember.isUnresolvedDisplayName(name)
        }

        // 4. Start from fetched members, ensure current user is present
        var allMembers = fetched

        if let existingIdx = allMembers.firstIndex(where: { isCurrentUser($0) }) {
            // Update role if needed
            if isCurrentHost && allMembers[existingIdx].role != .owner {
                allMembers[existingIdx].role = .owner
            }
            // Ensure display name is up-to-date
            if allMembers[existingIdx].displayName != currentUserName {
                allMembers[existingIdx].displayName = currentUserName
            }
        } else {
            let selfMember = RoomMember(
                id: "member_\(currentUserId)_\(room.id)",
                roomId: room.id,
                userId: currentUserId,
                displayName: currentUserName,
                role: isCurrentHost ? .owner : .member,
                joinedAt: Date()
            )
            allMembers.append(selfMember)
            Task {
                try? await roomRepo.saveMember(selfMember)
            }
        }

        // 5. Merge participants from native CKShare if available
        //    Only add participants who are genuinely NEW (not the current user, not
        //    already represented by a fetched member, and not a placeholder duplicate).
        //    Use the signature/username stored in RoomMember records, not iCloud names.
        if let participants = activeShare?.participants {
            for participant in participants {
                let pid = participant.userIdentity.userRecordID?.recordName ?? ""

                // Skip current user — already added above.
                // Match by recordName OR by CKShare owner-role when we are the host.
                if pid == currentUserId || (participant.role == .owner && isCurrentHost) {
                    continue
                }
                // Also skip if pid is empty
                guard !pid.isEmpty else { continue }

                // Try to find this participant's signature from already-fetched members
                // (saved via saveMember which stores the user's signature as displayName)
                let storedName = fetched.first(where: { $0.userId == pid })?.displayName

                // Check if this participant already exists in allMembers
                let alreadyExists = allMembers.contains(where: { existing in
                    if existing.userId == pid { return true }
                    if let name = storedName, !isPlaceholderName(name),
                       existing.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                        return true
                    }
                    if isCurrentUser(existing) && participant.role == .owner && isCurrentHost {
                        return true
                    }
                    return false
                })

                if alreadyExists { continue }

                // Use the stored signature, or "Unknown" if no signature was saved
                let displayName: String
                if let name = storedName, !name.isEmpty, !isPlaceholderName(name) {
                    displayName = name
                } else {
                    // Don't add duplicate "Unknown" entries
                    let existingUnknowns = allMembers.filter { $0.displayName == "Unknown" && !isCurrentUser($0) }
                    if participant.role == .owner {
                        if allMembers.contains(where: { $0.role == .owner }) { continue }
                    } else {
                        let nonOwnerOthers = allMembers.filter { !isCurrentUser($0) && $0.role != .owner }
                        if !nonOwnerOthers.isEmpty { continue }
                    }
                    displayName = "Unknown"
                }

                let member = RoomMember(
                    id: "ck_\(pid)_\(room.id)",
                    roomId: room.id,
                    userId: pid,
                    displayName: displayName,
                    role: participant.role == .owner ? .owner : .member,
                    joinedAt: Date()
                )
                allMembers.append(member)
            }
        }

        // 6. Merge members discovered via local Multipeer P2P
        for peerMember in MultipeerSyncService.shared.nearbyMembers {
            if !allMembers.contains(where: {
                $0.userId == peerMember.userId ||
                $0.id == peerMember.id ||
                $0.displayName.localizedCaseInsensitiveCompare(peerMember.displayName) == .orderedSame
            }) {
                allMembers.append(peerMember)
            }
        }

        // 7. Deduplicate & Clean Up
        var uniqueMembers: [RoomMember] = []
        for m in allMembers {
            let dominated = uniqueMembers.contains(where: {
                $0.userId == m.userId ||
                $0.displayName.localizedCaseInsensitiveCompare(m.displayName) == .orderedSame
            })
            if !dominated {
                uniqueMembers.append(m)
            }
        }

        // Remove placeholder entries when real-named members exist for the same role
        let hasRealOwner = uniqueMembers.contains(where: { $0.role == .owner && !isPlaceholderName($0.displayName) })
        let hasRealNonOwners = uniqueMembers.contains(where: { $0.role != .owner && !isPlaceholderName($0.displayName) })

        if hasRealOwner {
            uniqueMembers.removeAll(where: { $0.role == .owner && isPlaceholderName($0.displayName) })
        }
        if hasRealNonOwners {
            uniqueMembers.removeAll(where: { $0.role != .owner && isPlaceholderName($0.displayName) })
        }

        // Ensure at most one owner badge
        var foundOwner = false
        for i in 0..<uniqueMembers.count {
            if uniqueMembers[i].role == .owner {
                if !foundOwner {
                    foundOwner = true
                } else {
                    uniqueMembers[i].role = .member
                }
            }
        }

        self.members = uniqueMembers.sorted { lhs, rhs in
            if lhs.role == .owner && rhs.role != .owner { return true }
            if lhs.role != .owner && rhs.role == .owner { return false }
            return lhs.joinedAt < rhs.joinedAt
        }
    }
}
