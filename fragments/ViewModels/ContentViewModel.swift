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

    // Floating Capture Menu & Modals
    var isCaptureMenuOpen: Bool = false
    var showActiveMomentView: Bool = false
    var showQuickCaptureSheet: Bool = false
    var showDiscardConfirmation: Bool = false
    var showResumeOrNewMomentAlert: Bool = false
    var showDiscardForQuickCaptureAlert: Bool = false
    var selectedFragment: Fragment? = nil
    var quickCaptureInitialType: FragmentType = .photo
    var pendingQuickCaptureType: FragmentType = .photo
    var activeMomentInitialCaptureType: FragmentType? = nil
    var activeMomentAutoOpenEnd: Bool = false

    var currentTab: AppTab {
        selectedTab == .capture ? activeTab : selectedTab
    }

    func setModelContext(_ context: ModelContext) {
        momentManager.setModelContext(context)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "fragments" else { return }

        // Close any standalone detail views or menus that might block presentation
        selectedFragment = nil
        isCaptureMenuOpen = false

        if url.host == "end" {
            // Dismiss any existing active moment cover first so we can cleanly open end sheet
            showActiveMomentView = false
            activeMomentInitialCaptureType = nil
            activeMomentAutoOpenEnd = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showActiveMomentView = true
            }
        } else if url.host == "capture" {
            let modeParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "mode" })?
                .value ?? "photo"

            let targetType: FragmentType
            switch modeParam {
            case "video": targetType = .video
            case "note":  targetType = .note
            case "audio", "memo": targetType = .audio
            default:      targetType = .photo
            }

            showActiveMomentView = false
            activeMomentAutoOpenEnd = false
            activeMomentInitialCaptureType = targetType
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showActiveMomentView = true
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
        }
    }

    func handleFragmentCaptured(_ newFragment: Fragment) {
        if momentManager.isSessionActive {
            // ONLY add to active moment session (do not store in standalone FragmentsView)
            momentManager.addFragment(newFragment)
        } else {
            // Standalone quick capture outside any moment session
            incomingNewFragment = newFragment
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = .fragments
                activeTab = .fragments
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

    func resumeMoment() {
        showActiveMomentView = true
    }

    func startNewMoment() {
        momentManager.cancelSession()
        momentManager.startSession()
        showActiveMomentView = true
    }

    func discardForQuickCapture() {
        momentManager.cancelSession()
        quickCaptureInitialType = pendingQuickCaptureType
        showQuickCaptureSheet = true
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
