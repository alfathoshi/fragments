//
//  UsernameSetupView.swift
//  fragments
//

import SwiftUI

/// Dedicated username claim screen shown after sign-in when the authenticated
/// user has no backend username yet. Visual language follows JoinRoomSheet
/// (rounded input container, inline states, prominent bottom CTA) without
/// copying it: identity intro, normalized-username preview, live availability.
public struct UsernameSetupView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var rawText: String = ""
    @State private var checkState: CheckState = .idle
    @State private var saveError: String? = nil
    @State private var checkTask: Task<Void, Never>? = nil

    private let repository: SupabaseRoomRepository
    private let coordinator: OnboardingCoordinator

    private enum CheckState: Equatable {
        case idle
        case invalid(String)
        case checking
        case available
        case taken
        case saving
    }

    public init(
        repository: SupabaseRoomRepository = .shared,
        coordinator: OnboardingCoordinator
    ) {
        self.repository = repository
        self.coordinator = coordinator
    }

    private var normalized: String {
        UsernameValidator.normalize(rawText)
    }

    private var localFailure: String? {
        UsernameValidator.failure(for: normalized)?.errorDescription
    }

    private var isCTAEnabled: Bool {
        switch checkState {
        case .available:
            return true
        case .idle:
            // Offline/unchecked: allow the attempt; the server decides.
            return localFailure == nil && !normalized.isEmpty
        case .invalid, .checking, .taken, .saving:
            return false
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Intro
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Text("Create your username")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Choose a username so your friends know who you are in shared moments.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                // Input block
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "at")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("username", text: $rawText)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: rawText) { _, _ in
                                saveError = nil
                                scheduleAvailabilityCheck()
                            }
                            .onSubmit { saveIfPossible() }
                        if !rawText.isEmpty {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                rawText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                    // Normalized preview + hint
                    if !normalized.isEmpty, localFailure == nil {
                        Text("@\(normalized)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("3–20 characters · letters, numbers, and underscores")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    statusRow
                }

                if let saveError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                        Text(saveError)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()

                // Bottom CTA
                Button {
                    saveIfPossible()
                } label: {
                    HStack(spacing: 8) {
                        if checkState == .saving {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                        }
                        Text(checkState == .saving ? "Saving..." : "Continue")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .tint(.primary)
                .glassProminentButtonStyle()
                .clipShape(Capsule())
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .disabled(!isCTAEnabled)
                .opacity(isCTAEnabled ? 1.0 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { checkTask?.cancel() }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        switch checkState {
        case .idle:
            EmptyView()
        case .invalid(let message):
            statusLabel(icon: "exclamationmark.circle", text: message, color: .orange)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.8)
                Text("Checking availability...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .available:
            statusLabel(icon: "checkmark.circle.fill", text: "Username is available", color: .green)
        case .taken:
            statusLabel(icon: "xmark.circle.fill", text: "Username is already taken", color: .orange)
        case .saving:
            EmptyView()
        }
    }

    private func statusLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color == .green ? .green : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Availability + save

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        guard !normalized.isEmpty else {
            checkState = .idle
            return
        }
        if let message = localFailure {
            checkState = .invalid(message)
            return
        }
        checkState = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            do {
                let available = try await repository.isUsernameAvailable(normalized)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    checkState = available ? .available : .taken
                }
            } catch let error as SupabaseRoomError {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if case .validationFailure(let message) = error {
                        checkState = .invalid(message)
                    } else {
                        // Check inconclusive (offline/RPC): leave CTA enabled,
                        // the save attempt is authoritative.
                        checkState = .idle
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { checkState = .idle }
            }
        }
    }

    private func saveIfPossible() {
        guard isCTAEnabled, checkState != .saving else { return }
        if let message = localFailure {
            checkState = .invalid(message)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        checkTask?.cancel()
        checkState = .saving
        saveError = nil
        let attempt = normalized
        Task {
            do {
                let saved = try await repository.claimUsername(attempt)
                await MainActor.run {
                    checkState = .available
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Backend is now the source of truth; mirror it into the
                    // local display cache so Profile UI shows it immediately.
                    ProfileManager.shared.syncUsername(saved)
                    coordinator.completeUsername()
                }
                print("✅ [UsernameSetup] Claimed username: \(saved)")
            } catch let error as SupabaseRoomError {
                await MainActor.run {
                    switch error {
                    case .duplicate:
                        checkState = .taken
                    case .validationFailure(let message):
                        checkState = .invalid(message)
                    default:
                        // Typed text is preserved; retry keeps everything.
                        checkState = .idle
                        saveError = error.localizedDescription
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    checkState = .idle
                    saveError = error.localizedDescription
                }
            }
        }
    }
}

#if DEBUG
#Preview("Username Setup") {
    UsernameSetupView(coordinator: OnboardingCoordinator())
}
#endif
