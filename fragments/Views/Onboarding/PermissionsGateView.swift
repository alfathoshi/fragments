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
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var locationManager = LocationManager.shared
    @State private var localNetworkRequested = false
    @State private var isFinishing = false

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
                    Text("Fragments works best with camera, microphone, local network, and location access. You can skip anything — nothing here will trap you.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    permissionRow(
                        icon: "camera.fill",
                        title: "Camera",
                        subtitle: "Capture photo and video fragments",
                        state: rowState(for: cameraStatus)
                    ) {
                        await requestCamera()
                    }
                    permissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        subtitle: "Record voice memos and video sound",
                        state: rowState(for: micStatus)
                    ) {
                        await requestMic()
                    }
                    permissionRow(
                        icon: "wifi",
                        title: "Local Network",
                        subtitle: localNetworkRequested
                            ? "Nearby sharing enabled — change anytime in Settings"
                            : "Find nearby devices for instant sharing",
                        state: localNetworkRequested ? .granted : .pending
                    ) {
                        await requestLocalNetwork()
                    }
                    permissionRow(
                        icon: "mappin.and.ellipse",
                        title: "Location",
                        subtitle: "Tag moments with where they happened",
                        state: locationGranted ? .granted : (locationDecided ? .denied : .pending)
                    ) {
                        await requestLocation()
                    }
                }

                Spacer()

                Button {
                    finish()
                } label: {
                    HStack(spacing: 8) {
                        if isFinishing {
                            ProgressView()
                        }
                        Text(allResolved ? "Continue" : "Continue anyway")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .tint(.primary)
                .glassProminentButtonStyle()
                .clipShape(Capsule())
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .disabled(isFinishing)
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
            case .pending:
                Button("Enable") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await onEnable() }
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(uiColor: .systemBackground))
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
        #if targetEnvironment(simulator)
        cameraStatus = .authorized
        #else
        cameraStatus = await AVCaptureDevice.requestAccess(for: .video)
            ? .authorized
            : AVCaptureDevice.authorizationStatus(for: .video)
        #endif
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allResolved { finish() }
    }

    private func requestMic() async {
        #if targetEnvironment(simulator)
        micStatus = .authorized
        #else
        micStatus = await AVCaptureDevice.requestAccess(for: .audio)
            ? .authorized
            : AVCaptureDevice.authorizationStatus(for: .audio)
        #endif
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if allResolved { finish() }
    }

    private func requestLocation() async {
        locationManager.requestLocation()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Advancement happens via authorizationStatus onChange when decided.
    }

    /// Fires the one-time system local-network prompt via a throwaway browse.
    /// iOS offers no authorization-status API and no decision callback, so the
    /// step always resolves — it never traps the user.
    private func requestLocalNetwork() async {
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
        coordinator.completePermissions()
    }
}

#if DEBUG
#Preview("Permissions Gate") {
    PermissionsGateView(coordinator: OnboardingCoordinator())
}
#endif
