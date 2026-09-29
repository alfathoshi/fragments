//
//  JoinRoomSheet.swift
//  fragments
//
//  Created on 9/27/26.
//

import SwiftUI

/// Sheet enabling users to join a collaborative Room via direct invite link, iCloud share link, or Room ID.
public struct JoinRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public var onJoined: ((Room) -> Void)? = nil

    @State private var inputCode: String = ""
    @State private var isJoining: Bool = false
    @State private var errorMessage: String? = nil

    private let roomManager = RoomManager.shared

    public init(onJoined: ((Room) -> Void)? = nil) {
        self.onJoined = onJoined
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                // Input Box with Paste Button
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "link")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)

                        TextField("Paste link or enter room code...", text: $inputCode)
                            .font(.system(size: 15, design: .rounded))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !inputCode.isEmpty {
                            Button {
                                inputCode = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                    // Quick Paste from Clipboard button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let pasted = UIPasteboard.general.string {
                            inputCode = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Paste from Clipboard")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                }

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                // Join Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    handleJoin()
                } label: {
                    HStack(spacing: 8) {
                        if isJoining {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                        }
                        Text(isJoining ? "Joining..." : "Join Moment")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassProminentButtonStyle()
                .tint(.primary)
                .disabled(inputCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Join with Code")
        }
    }

    private func handleJoin() {
        let trimmed = inputCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isJoining = true
        errorMessage = nil

        Task {
            // Case 1: Extract any iCloud share URL from the input (supports raw URL or pasted message)
            let icloudURL: URL? = {
                if let url = URL(string: trimmed),
                   let host = url.host?.lowercased(),
                   host.contains("icloud.com"),
                   url.path.lowercased().contains("/share") {
                    return url
                }
                if let match = trimmed.range(of: #"https?://www\.icloud\.com/share/[^\s]+"#, options: .regularExpression) {
                    return URL(string: String(trimmed[match]))
                }
                return nil
            }()

            if let shareURL = icloudURL {
                do {
                    let room = try await roomManager.acceptShare(with: shareURL)
                    await MainActor.run {
                        isJoining = false
                        onJoined?(room)
                        dismiss()
                    }
                    return
                } catch {
                    await MainActor.run {
                        isJoining = false
                        errorMessage = "Could not join via iCloud: \(error.localizedDescription)"
                    }
                    return
                }
            }

            // Case 2: Deep Link (fragments://room/join?id=...&name=...)
            if let url = URL(string: trimmed), url.scheme == "fragments" {
                let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                let roomId = queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                let roomName = queryItems?.first(where: { $0.name == "name" })?.value ?? "Shared Moment"
                let createdAtDouble = queryItems?.first(where: { $0.name == "createdAt" })?.value.flatMap(Double.init)
                let deepLinkCreatedAt = createdAtDouble != nil ? Date(timeIntervalSince1970: createdAtDouble!) : nil

                if !roomId.isEmpty {
                    // Try looking up public CKShare URL first to mount CloudKit zone
                    if let shareURL = await CloudKitRoomRepository.shared.lookupShareURL(for: roomId) {
                        do {
                            let room = try await roomManager.acceptShare(with: shareURL)
                            await MainActor.run {
                                isJoining = false
                                onJoined?(room)
                                dismiss()
                            }
                            return
                        } catch {
                            print("⚠️ Failed to accept share via resolved URL: \(error.localizedDescription)")
                        }
                    }

                    // Try fetching the room directly from CloudKit
                    if let room = try? await CloudKitRoomRepository.shared.fetchRoom(id: roomId) {
                        _ = await roomManager.joinRoomDirect(id: room.id, name: room.name, createdAt: room.createdAt)
                        await MainActor.run {
                            isJoining = false
                            onJoined?(room)
                            dismiss()
                        }
                        return
                    }

                    // Fallback: resolve from Public Cloud Relay or direct deep link with owner's start timestamp
                    let resolvedInfo = await CloudKitRoomRepository.shared.lookupRoomInfo(for: roomId)
                    let resolvedCreatedAt = resolvedInfo?.createdAt ?? deepLinkCreatedAt
                    let room = await roomManager.joinRoomDirect(
                        id: resolvedInfo?.id ?? roomId,
                        name: resolvedInfo?.name ?? roomName,
                        createdAt: resolvedCreatedAt
                    )
                    await MainActor.run {
                        isJoining = false
                        onJoined?(room)
                        dismiss()
                    }
                    return
                }

                // Room not found via deep link
                await MainActor.run {
                    isJoining = false
                    errorMessage = "No room found with that link. Please check and try again."
                }
                return
            }

            // Case 3: 6-Character Supabase Room Code
            if trimmed.count == 6 && !trimmed.contains("/") && !trimmed.contains(".") {
                do {
                    let room = try await roomManager.joinRoom(code: trimmed)
                    await MainActor.run {
                        isJoining = false
                        onJoined?(room)
                        dismiss()
                    }
                    return
                } catch {
                    if let sbError = error as? SupabaseRoomError {
                        switch sbError {
                        case .validationFailure(let msg):
                            await MainActor.run {
                                isJoining = false
                                errorMessage = msg
                            }
                            return
                        default:
                            break
                        }
                    }
                }
            }

            // Case 4: Legacy CloudKit Room Code / UUID / short code
            // 1. Try public lookup to resolve native CKShare URL (with automatic retry for newly created rooms)
            var resolvedShareURL = await CloudKitRoomRepository.shared.lookupShareURL(for: trimmed)
            if resolvedShareURL == nil {
                try? await Task.sleep(nanoseconds: 600_000_000)
                resolvedShareURL = await CloudKitRoomRepository.shared.lookupShareURL(for: trimmed)
            }

            if let shareURL = resolvedShareURL {
                do {
                    let room = try await roomManager.acceptShare(with: shareURL)
                    await MainActor.run {
                        isJoining = false
                        onJoined?(room)
                        dismiss()
                    }
                    return
                } catch {
                    print("⚠️ Failed to accept share via resolved URL: \(error.localizedDescription)")
                }
            }

            // 2. Try fetching room directly from CloudKit if already accepted or accessible
            if let room = try? await CloudKitRoomRepository.shared.fetchRoom(id: trimmed) {
                _ = await roomManager.joinRoomDirect(id: room.id, name: room.name, createdAt: room.createdAt)
                await MainActor.run {
                    isJoining = false
                    onJoined?(room)
                    dismiss()
                }
                return
            }

            // 3. Fallback: Lookup exact room ID and name from Public Cloud Relay
            let resolvedInfo = await CloudKitRoomRepository.shared.lookupRoomInfo(for: trimmed)

            guard let resolvedInfo else {
                await MainActor.run {
                    isJoining = false
                    errorMessage = "No room found with that code. Please check and try again."
                }
                return
            }

            let room = await roomManager.joinRoomDirect(id: resolvedInfo.id, name: resolvedInfo.name, createdAt: resolvedInfo.createdAt)
            await MainActor.run {
                isJoining = false
                onJoined?(room)
                dismiss()
            }
        }
    }
}
