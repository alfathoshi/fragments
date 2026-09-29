//
//  PermissionsGateView.swift
//  fragments
//

import SwiftUI
import AVFoundation
import CoreLocation

/// Sequential post-username permission gate: camera → microphone → location.
///
/// Rules: never auto-stacks system prompts (each fires only from its own
/// Enable tap); already-granted permissions are skipped; denials never trap
/// the user (Continue is always available, with a Settings hint); simulator
/// short-circuits to granted. Completing (or skipping) records
/// `hasCompletedPermissions` via the coordinator.
public struct PermissionsGateView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var locationManager = LocationManager.shared
    @State private var localNetworkRequested = false
    @State private var isFinishing = false
    /// In-flight permission requests by key ("camera", "mic", "localNetwork",
    /// "location"). Guards against double taps / duplicate system prompts and
    /// drives per-row spinners. Continue is disabled while non-empty.
    @State private var busyPermissions: Set<String> = []

    private let coordinator: OnboardingCoordinator

    public init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
    }

    private var locationGranted: Bool {
        let s = locationManager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    private var locationDecided: Bool {
        locationManager.authorizationStatus != .notDetermined
    }

    private var isRequestingPermission: Bool {
        !busyPermissions.isEmpty
    }

    private var allResolved: Bool {
        cameraStatus == .authorized
            && micStatus == .authorized
            && localNetworkRequested
            && locationGranted
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Text("Enable what you need")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Fragments works best with camera, microphone, local network, and location access. You can skip anything, nothing here will trap you.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    permissionRow(
                        icon: "camera.fill",
                        title: "Camera",
                        subtitle: "Capture photo and video fragments",
                        state: rowState(for: cameraStatus),
                        isBusy: busyPermissions.contains("camera")
                    ) {
                        await requestCamera()
                    }
                    permissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        subtitle: "Record voice memos and video sound",
                        state: rowState(for: micStatus),
                        isBusy: busyPermissions.contains("mic")
                    ) {
                        await requestMic()
                    }
                    permissionRow(
                        icon: "wifi",
                        title: "Local Network",
                        subtitle: "Find nearby devices for instant sharing",
                        state: localNetworkRequested ? .granted : .pending,
                        isBusy: busyPermissions.contains("localNetwork")
                    ) {
                        await requestLocalNetwork()
                    }
                    permissionRow(
                        icon: "mappin.and.ellipse",
                        title: "Location",
                        subtitle: "Tag moments with where they happened",
                        state: locationGranted ? .granted : (locationDecided ? .denied : .pending),
                        isBusy: busyPermissions.contains("location")
                    ) {
                        await requestLocation()
                    }
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    finish()
                } label: {
                    HStack(spacing: 8) {
                        if isFinishing {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                            Text("Continuing…")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        } else {
                            Text(allResolved ? "Continue" : "Continue anyway")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
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
                .disabled(isFinishing || isRequestingPermission)
                .opacity((isFinishing || isRequestingPermission) ? 0.6 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshStatuses()
            #if targetEnvironment(simulator)
            localNetworkRequested = true
            finish()
            #else
            if allResolved { finish() }
            #endif
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            // Location request resolved (granted or denied) — clear its
            // processing state. Advancement itself stays via allResolved.
            busyPermissions.remove("location")
            if allResolved { finish() }
        }
    }

    // MARK: - Rows

    private enum RowState {
        case granted
        case denied
        case pending
    }

    private func rowState(for status: AVAuthorizationStatus) -> RowState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .pending
        @unknown default: return .pending
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        state: RowState,
        isBusy: Bool = false,
        onEnable: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(state == .denied ? "Denied — enable anytime in Settings" : subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.green)
            case .denied:
                Button("Settings") { openSettings() }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .disabled(isFinishing)
                    .opacity(isFinishing ? 0.5 : 1.0)
            case .pending:
                if isBusy {
                    ProgressView()
                        .frame(width: 80, height: 32)
                } else {
                    Button("Enable") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await onEnable() }
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary, in: Capsule())
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .disabled(isFinishing || isRequestingPermission)
                    .opacity((isFinishing || isRequestingPermission) ? 0.5 : 1.0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Requests (each fires only from its own Enable tap)

    private func refreshStatuses() {
        #if targetEnvironment(simulator)
        cameraStatus = .authorized
        micStatus = .authorized
        #else
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        #endif
    }

    private func requestCamera() async {
        guard !busyPermissions.contains("camera"), !isFinishing else { return }
        #if targetEnvironment(simulator)
        cameraStatus = .authorized
        #else
        busyPermissions.insert("camera")
        defer { busyPermissions.remove("camera") }
        cameraStatus = await AVCaptureDevice.requestAccess(for: .video)
            ? .authorized
            : AVCaptureDevice.authorizationStatus(for: .video)
        #endif
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allResolved { finish() }
    }

    private func requestMic() async {
        guard !busyPermissions.contains("mic"), !isFinishing else { return }
        #if targetEnvironment(simulator)
        micStatus = .authorized
        #else
        busyPermissions.insert("mic")
        defer { busyPermissions.remove("mic") }
        micStatus = await AVCaptureDevice.requestAccess(for: .audio)
            ? .authorized
            : AVCaptureDevice.authorizationStatus(for: .audio)
        #endif
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allResolved { finish() }
    }

    private func requestLocation() async {
        guard !busyPermissions.contains("location"), !isFinishing else { return }
        #if targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #else
        // If already decided, no system prompt will appear — resolve
        // immediately without entering a lingering processing state.
        if locationManager.authorizationStatus != .notDetermined {
            locationManager.requestLocation()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        // Not determined: stay in processing state until the
        // authorizationStatus onChange resolves (granted or denied).
        busyPermissions.insert("location")
        locationManager.requestLocation()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Advancement happens via authorizationStatus onChange when decided.
        #endif
    }

    /// Fires the one-time system local-network prompt via a throwaway browse.
    /// iOS offers no authorization-status API and no decision callback, so the
    /// step always resolves — it never traps the user. Fires ONLY from the
    /// explicit Enable tap here, never automatically.
    private func requestLocalNetwork() async {
        guard !busyPermissions.contains("localNetwork"), !isFinishing else { return }
        guard !localNetworkRequested else { return }
        busyPermissions.insert("localNetwork")
        defer { busyPermissions.remove("localNetwork") }
        _ = await LocalNetworkPermission.requestAccess()
        localNetworkRequested = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allResolved { finish() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            // completePermissions() flips phase synchronously, which tears
            // this view down immediately — the spinner would never get a frame
            // to paint. Yield once so isFinishing renders, then hold a minimum
            // feedback duration so the tap is visibly acknowledged.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            coordinator.completePermissions()
        }
    }
}

#if DEBUG
#Preview("Permissions Gate") {
    PermissionsGateView(coordinator: OnboardingCoordinator())
}
#endif
