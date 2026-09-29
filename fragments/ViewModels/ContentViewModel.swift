//
//  ContentViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class ContentViewModel {
    var momentManager: MomentManager = MomentManager.shared

    var selectedTab: AppTab = .fragments
    var activeTab: AppTab = .fragments
    var incomingNewFragment: Fragment? = nil

    init() {
        if CommandLine.arguments.contains("-momentsTab") {
            selectedTab = .logs
            activeTab = .logs
        }
        if CommandLine.arguments.contains("-openCaptureMenu") {
            isCaptureMenuOpen = true
        }
        if CommandLine.arguments.contains("-activeSharedMoment") {
            let sampleRoom = Room(
                id: "sample_shared_room",
                name: "Bali Trip 2026",
                emoji: "✨",
                createdAt: Date(),
                createdBy: "local_user",
                memberCount: 3,
                fragmentCount: 2
            )
            let sampleSession = MomentSession(
                startDate: Date().addingTimeInterval(-320),
                fragments: [
                    Fragment(type: .photo, title: "Bali Sunset", subtitle: "06:15 PM"),
                    Fragment(type: .note, title: "Dinner plan", subtitle: "06:20 PM")
                ],
                location: "Canggu, Bali",
                isShared: true,
                room: sampleRoom
            )
            momentManager.activeSession = sampleSession
            showActiveMomentView = true
        }
    }

    // Floating Capture Menu & Modals
    var isCaptureMenuOpen: Bool = false
    var showActiveMomentView: Bool = false
    var showJoinSheet: Bool = false
    var showQuickCaptureSheet: Bool = false
    var showDiscardConfirmation: Bool = false
    var showLeaveConfirmation: Bool = false
    var showResumeOrNewMomentAlert: Bool = false
    var showDiscardForQuickCaptureAlert: Bool = false
    var showStandaloneLimitAlert: Bool = false
    var showMomentLimitAlert: Bool = false
    var selectedFragment: Fragment? = nil
    var quickCaptureInitialType: FragmentType = .photo
    var pendingQuickCaptureType: FragmentType = .photo
    var activeMomentInitialCaptureType: FragmentType? = nil
    var activeMomentAutoOpenEnd: Bool = false
    var pendingStartMomentIsShared: Bool = false

    var currentTab: AppTab {
        selectedTab == .capture ? activeTab : selectedTab
    }

    func setModelContext(_ context: ModelContext) {
        momentManager.setModelContext(context)
    }

    func handleDeepLink(_ url: URL) {
        if url.scheme == "https" && url.host?.contains("icloud.com") == true {
            Task {
                if let room = try? await RoomManager.shared.acceptShare(with: url) {
                    await MainActor.run {
                        handleJoinSharedMoment(room: room)
                    }
                }
            }
            return
        }

        guard url.scheme == "fragments" else { return }

        // Close any standalone detail views or menus that might block presentation
        selectedFragment = nil
        isCaptureMenuOpen = false

        if url.host == "end" {
            if showActiveMomentView {
                NotificationCenter.default.post(name: NSNotification.Name("RequestEndMoment"), object: nil)
            } else {
                activeMomentInitialCaptureType = nil
                activeMomentAutoOpenEnd = true
                showActiveMomentView = true
            }
        } else if url.host == "leave" {
            if showActiveMomentView {
                NotificationCenter.default.post(name: NSNotification.Name("RequestLeaveMoment"), object: nil)
            } else {
                showLeaveConfirmation = true
            }
        } else if url.host == "capture" {
            let modeParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "mode" })?
                .value?.lowercased() ?? "photo"

            let targetType: FragmentType
            let targetMode: CaptureMode
            switch modeParam {
            case "video":
                targetType = .video
                targetMode = .video
            case "note":
                targetType = .note
                targetMode = .note
            case "audio", "memo":
                targetType = .audio
                targetMode = .memo
            default:
                targetType = .photo
                targetMode = .photo
            }

            if momentManager.isSessionActive {
                if (momentManager.activeSession?.fragments.count ?? 0) >= MomentSession.maxFragments {
                    showMomentLimitAlert = true
                } else {
                    if showActiveMomentView {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenActiveMomentCapture"), object: targetType)
                        NotificationCenter.default.post(name: NSNotification.Name("SelectCaptureMode"), object: targetMode)
                    } else {
                        activeMomentAutoOpenEnd = false
                        activeMomentInitialCaptureType = targetType
                        showActiveMomentView = true
                    }
                }
            } else {
                momentManager.cleanupExpiredStandaloneFragments()
                if momentManager.standaloneFragments.count >= MomentManager.maxStandaloneFragments {
                    showStandaloneLimitAlert = true
                } else {
                    quickCaptureInitialType = targetType
                    showQuickCaptureSheet = true
                    NotificationCenter.default.post(name: NSNotification.Name("SelectCaptureMode"), object: targetMode)
                }
            }
        } else if url.host == "moment" {
            activeMomentInitialCaptureType = nil
            activeMomentAutoOpenEnd = false
            showActiveMomentView = true
        } else if url.host == "tab" || url.host == "moments" {
            let tabParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "name" })?
                .value ?? (url.host == "moments" ? "moments" : "")
            if tabParam == "moments" || tabParam == "logs" || url.host == "moments" {
                withAnimation {
                    selectedTab = .logs
                    activeTab = .logs
                }
            } else if tabParam == "fragments" {
                withAnimation {
                    selectedTab = .fragments
                    activeTab = .fragments
                }
            }
        } else if url.host == "room" || url.host == "join" {
            // Shared deep links require authentication — guests get the
            // product gate (resuming into the join flow) instead of touching
            // room backends without an identity.
            if OnboardingCoordinator.shared.isGuest {
                OnboardingCoordinator.shared.requireAuth(for: .joinMoment)
                return
            }
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            if let code = queryItems?.first(where: { $0.name == "code" })?.value,
               code.trimmingCharacters(in: .whitespacesAndNewlines).count == 6 {
                Task {
                    if let room = try? await RoomManager.shared.joinRoom(code: code) {
                        await MainActor.run {
                            handleJoinSharedMoment(room: room)
                        }
                        return
                    }
                }
            }
            let roomId = queryItems?.first(where: { $0.name == "id" })?.value ?? UUID().uuidString
            let roomName = queryItems?.first(where: { $0.name == "name" })?.value ?? "Shared Moment"
            let createdAtDouble = queryItems?.first(where: { $0.name == "createdAt" })?.value.flatMap(Double.init)
            let deepLinkCreatedAt = createdAtDouble != nil ? Date(timeIntervalSince1970: createdAtDouble!) : nil
            Task {
                if let shareURL = await CloudKitRoomRepository.shared.lookupShareURL(for: roomId) {
                    if let room = try? await RoomManager.shared.acceptShare(with: shareURL) {
                        await MainActor.run {
                            handleJoinSharedMoment(room: room)
                        }
                        return
                    }
                }
                if let room = try? await CloudKitRoomRepository.shared.fetchRoom(id: roomId) {
                    _ = await RoomManager.shared.joinRoomDirect(id: room.id, name: room.name, createdAt: room.createdAt)
                    await MainActor.run {
                        handleJoinSharedMoment(room: room)
                    }
                    return
                }
                let resolvedInfo = await CloudKitRoomRepository.shared.lookupRoomInfo(for: roomId)
                let resolvedCreatedAt = resolvedInfo?.createdAt ?? deepLinkCreatedAt
                let room = await RoomManager.shared.joinRoomDirect(
                    id: resolvedInfo?.id ?? roomId,
                    name: resolvedInfo?.name ?? roomName,
                    createdAt: resolvedCreatedAt
                )
                await MainActor.run {
                    handleJoinSharedMoment(room: room)
                }
            }
        }
    }

    func handleJoinSharedMoment(room: Room) {
        if momentManager.isSessionActive {
            momentManager.cancelSession()
        }
        momentManager.joinSharedSession(room: room)
        showActiveMomentView = true
    }

    func handleFragmentCaptured(_ newFragment: Fragment) {
        if momentManager.isSessionActive {
            // ONLY add to active moment session (do not store in standalone FragmentsView)
            if (momentManager.activeSession?.fragments.count ?? 0) < MomentSession.maxFragments {
                momentManager.addFragment(newFragment)
            } else {
                showMomentLimitAlert = true
            }
        } else {
            // Standalone quick capture outside any moment session
            momentManager.cleanupExpiredStandaloneFragments()
            if momentManager.standaloneFragments.count < MomentManager.maxStandaloneFragments {
                incomingNewFragment = newFragment
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    selectedTab = .fragments
                    activeTab = .fragments
                }
            } else {
                showStandaloneLimitAlert = true
            }
        }
    }

    func handleCaptureTabTap(oldTab: AppTab) {
        // Intercept capture tab tap: pop up the floating orbs and blur the screen!
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) {
            isCaptureMenuOpen = true
        }
        // Keep the underlying view on the previous tab so it blurs gorgeously
        selectedTab = (oldTab == .capture) ? .fragments : oldTab
    }

    func discardMoment() {
        momentManager.cancelSession()
    }

    func leaveMoment() {
        momentManager.leaveSession()
    }

    func resumeMoment() {
        showActiveMomentView = true
    }

    func handleStartPersonalMoment() {
        if momentManager.isSessionActive {
            pendingStartMomentIsShared = false
            showResumeOrNewMomentAlert = true
        } else {
            momentManager.startSession(isShared: false)
            showActiveMomentView = true
        }
    }

    /// Shared Moment entry point. Guests have no Supabase identity, so they
    /// are routed to the authentication-required gate instead of reaching
    /// the backend. The intended action is preserved and resumed after a
    /// successful Guest → sign-in upgrade.
    func handleStartSharedMoment() {
        guard !OnboardingCoordinator.shared.isGuest else {
            OnboardingCoordinator.shared.requireAuth(for: .startSharedMoment)
            return
        }
        if momentManager.isSessionActive {
            pendingStartMomentIsShared = true
            showResumeOrNewMomentAlert = true
        } else {
            momentManager.startSharedSession()
            showActiveMomentView = true
        }
    }

    /// Join Moment entry point (capture overlay). Same guest gating as above.
    func requestJoinMoment() {
        guard !OnboardingCoordinator.shared.isGuest else {
            OnboardingCoordinator.shared.requireAuth(for: .joinMoment)
            return
        }
        showJoinSheet = true
    }

    /// Resumes the blocked shared action after a successful sign-in upgrade.
    /// Only runs on the main phase with a live session — a fresh sign-in that
    /// still needs username setup keeps the pending action until main.
    func consumePendingSharedAction() {
        let coordinator = OnboardingCoordinator.shared
        guard coordinator.phase == .main,
              SupabaseService.shared.isAuthenticated,
              let pending = coordinator.pendingSharedAction else { return }
        coordinator.pendingSharedAction = nil
        switch pending {
        case .startSharedMoment:
            handleStartSharedMoment()
        case .joinMoment:
            showJoinSheet = true
        }
    }

    func startNewMoment() {
        momentManager.cancelSession()
        if pendingStartMomentIsShared {
            momentManager.startSharedSession()
            showActiveMomentView = true
        } else {
            momentManager.startSession(isShared: false)
            showActiveMomentView = true
        }
    }

    func discardForQuickCapture() {
        momentManager.cancelSession()
        momentManager.cleanupExpiredStandaloneFragments()
        if momentManager.standaloneFragments.count >= MomentManager.maxStandaloneFragments {
            showStandaloneLimitAlert = true
        } else {
            quickCaptureInitialType = pendingQuickCaptureType
            showQuickCaptureSheet = true
        }
    }

    func onSaveComplete() {
        showActiveMomentView = false
        activeMomentInitialCaptureType = nil
        activeMomentAutoOpenEnd = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selectedTab = .logs
            activeTab = .logs
        }
    }

    func onActiveMomentDismiss() {
        showActiveMomentView = false
        activeMomentInitialCaptureType = nil
        activeMomentAutoOpenEnd = false
    }
}
