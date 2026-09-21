//
//  FragmentsViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI

@Observable
@MainActor
final class FragmentsViewModel {
    var momentManager: MomentManager = MomentManager.shared
    var fragments: [Fragment] = []
    var selectedFilter: FragmentType? = nil
    var enteringFragment: Fragment? = nil
    var enteringStep: Int = 0 // 0: foreground float, 1: traveling to sphere, 2: settled
    var toastMessage: String? = nil
    var showQuickCaptureSheet: Bool = false
    
    init(initialFragments: [Fragment] = []) {
        self.fragments = initialFragments
    }
    
    var displayedFragments: [Fragment] {
        let active = fragments.filter { !$0.isExpired }
        if let filter = selectedFilter {
            return active.filter { $0.type == filter }
        }
        return active
    }
    
    func cleanupExpiredFragments() {
        let expired = fragments.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            fragments.removeAll { $0.isExpired }
        }
        for frag in expired {
            momentManager.deleteStandaloneFragment(id: frag.id)
        }
    }
    
    func triggerNewFragmentEntrance(_ newFragment: Fragment) {
        cleanupExpiredFragments()
        guard fragments.count < MomentManager.maxStandaloneFragments else {
            showToast("Limit reached: max 15 fragments")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        var fragmentToEnter = newFragment
        // Dynamically compute optimal scattered coordinates avoiding existing fragments on the sphere
        let coords = Fragment.generateScatteredCoordinates(existing: fragments)
        fragmentToEnter.phi = coords.phi
        fragmentToEnter.theta = coords.theta
        fragmentToEnter.radiusFactor = coords.radiusFactor

        enteringFragment = fragmentToEnter
        enteringStep = 0

        // Step 1: Appears in foreground, floats gently
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            enteringStep = 0
        }

        // Step 2: Moves toward the sphere
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeInOut(duration: 0.55)) {
                self.enteringStep = 1
            }
        }

        // Step 3: Settles naturally into the sphere collection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                self.fragments.insert(fragmentToEnter, at: 0)
                self.momentManager.addStandaloneFragment(fragmentToEnter)
                self.enteringFragment = nil
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    func handleAddToMoment(fragment: Fragment, momentName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            fragments.removeAll(where: { $0.id == fragment.id })
            momentManager.deleteStandaloneFragment(id: fragment.id)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func handleDelete(fragment: Fragment) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            fragments.removeAll(where: { $0.id == fragment.id })
            momentManager.deleteStandaloneFragment(id: fragment.id)
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if self.toastMessage == message {
                    self.toastMessage = nil
                }
            }
        }
    }

    func clearAllFragments() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            fragments.removeAll()
            momentManager.clearAllStandaloneFragments()
            selectedFilter = nil
        }
    }
    
    func loadInitialFragments() {
        momentManager.cleanupExpiredStandaloneFragments()
        if fragments.isEmpty && !momentManager.standaloneFragments.isEmpty {
            fragments = momentManager.standaloneFragments.filter { !$0.isExpired }
        }
        cleanupExpiredFragments()
    }
    
    func syncFragments(_ newFragments: [Fragment]) {
        let active = newFragments.filter { !$0.isExpired }
        if fragments != active {
            fragments = active
        }
    }
    
    func handleIncomingFragment(_ frag: Fragment) {
        triggerNewFragmentEntrance(frag)
    }
}
