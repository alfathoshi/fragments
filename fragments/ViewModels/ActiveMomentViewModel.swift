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
    var showAddPeopleSheet: Bool = false
    var showLimitAlert: Bool = false
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
            if !(momentManager.activeSession?.isShared ?? false) && (momentManager.activeSession?.fragments.count ?? 0) >= MomentSession.maxFragments {
                self.showLimitAlert = true
            } else {
                self.showCaptureSheet = true
                self.captureInitialType = initType
            }
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
        if let session = momentManager.activeSession, session.isShared, let room = session.room {
            Task {
                try? await RoomManager.shared.deleteSharedFragment(id: fragment.id.uuidString, roomID: room.id)
            }
        }
        selectedFragment = nil
    }
    
    func dismissSelectedFragment() {
        selectedFragment = nil
    }
    
    func openCaptureSheet(type: FragmentType) {
        if !(session?.isShared ?? false) && (session?.fragments.count ?? 0) >= MomentSession.maxFragments {
            showLimitAlert = true
            return
        }
        captureInitialType = type
        showCaptureSheet = true
    }
    
    func handleCapturedFragment(_ newFragment: Fragment) {
        guard !(session?.fragments.contains(where: { $0.id == newFragment.id }) ?? false) else {
            showCaptureSheet = false
            return
        }
        if (session?.isShared ?? false) || (session?.fragments.count ?? 0) < MomentSession.maxFragments {
            momentManager.addFragment(newFragment)
        } else {
            showLimitAlert = true
        }
        showCaptureSheet = false
    }

    func handleCapturedSharedFragment(_ sharedFragment: SharedFragment) {
        let frag = sharedFragment.toFragment()
        handleCapturedFragment(frag)
    }

    var isHost: Bool {
        session?.isHost ?? true
    }

    func leaveSession() {
        momentManager.leaveSession()
    }

    // MARK: - Collaborative Live Sync

    func startSyncObserver() {
        guard let session = session, session.isShared, let room = session.room else { return }
        // Ensure central background synchronization engine in MomentManager is active for appropriate backend
        if room.backend == .supabase {
            momentManager.startSupabaseRealtimeObserver(roomID: room.id)
        } else {
            momentManager.startRemoteSyncObserver(roomID: room.id)
        }
        // Retry any missing remote media each time the live view appears.
        momentManager.backfillMissingSessionMedia()
    }

    func stopSyncObserver() {
        // Continuous remote sync is maintained by MomentManager across all views
    }
}
