//
//  ActiveMomentViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI

@Observable
@MainActor
final class ActiveMomentViewModel {
    var momentManager: MomentManager
    
    var selectedFragment: Fragment? = nil
    var showCaptureSheet: Bool = false
    var showEndMomentSheet: Bool = false
    var captureInitialType: FragmentType = .photo
    var orbPulse: Bool = false
    
    var initialCaptureType: FragmentType?
    var autoOpenEnd: Bool
    
    init(
        momentManager: MomentManager = MomentManager.shared,
        initialCaptureType: FragmentType? = nil,
        autoOpenEnd: Bool = false
    ) {
        self.momentManager = momentManager
        self.initialCaptureType = initialCaptureType
        self.autoOpenEnd = autoOpenEnd
        
        if let initType = initialCaptureType {
            self.showCaptureSheet = true
            self.captureInitialType = initType
        } else if autoOpenEnd {
            self.showEndMomentSheet = true
        }
    }
    
    var session: MomentSession? {
        momentManager.activeSession
    }
    
    func deleteFragmentFromSession(_ fragment: Fragment) {
        if let idx = momentManager.activeSession?.fragments.firstIndex(where: { $0.id == fragment.id }) {
            momentManager.activeSession?.fragments.remove(at: idx)
        }
        selectedFragment = nil
    }
    
    func dismissSelectedFragment() {
        selectedFragment = nil
    }
    
    func openCaptureSheet(type: FragmentType) {
        captureInitialType = type
        showCaptureSheet = true
    }
    
    func handleCapturedFragment(_ newFragment: Fragment) {
        momentManager.addFragment(newFragment)
        showCaptureSheet = false
    }
}
