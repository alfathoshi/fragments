//
//  MomentManager.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI
import SwiftData
import Observation
import ActivityKit

/// Lightweight snapshot of an active session stored in UserDefaults.
/// Only the metadata is persisted — fragments are in-memory and will
/// be lost on termination, but the session banner can still be restored.
private struct PersistedSessionInfo: Codable {
    let id: UUID
    let startDate: Date
    let location: String
}

private let kPersistedSessionKey = "fragments.activeSessionInfo"

/// Central observable manager for managing active Moment sessions and saved Moment collections.
@Observable
@MainActor
final class MomentManager {
    static let shared = MomentManager()

    var activeSession: MomentSession? = nil
    var collections: [FolderCollection] = []
    var standaloneFragments: [Fragment] = []
    var showEndMomentSheet: Bool = false
    var recentlySavedMoment: FolderCollection? = nil

    private var modelContext: ModelContext?
    /// Reference to the currently running Live Activity (nil when no session is active).
    private var liveActivity: Activity<MomentActivityAttributes>?

    var isSessionActive: Bool {
        activeSession != nil
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        if let context = modelContext {
            loadPersistedData(context: context)
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadPersistedData(context: context)
    }

    func loadPersistedData(context: ModelContext? = nil) {
        guard let ctx = context ?? modelContext else { return }
        
        // Load Saved Moments
        let momentDescriptor = FetchDescriptor<SDMoment>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let sdMoments = try? ctx.fetch(momentDescriptor) {
            // Remove any leftover sample data previously seeded
            var hasDeletedSample = false
            for sdMoment in sdMoments where sdMoment.name == "Sanur Beach" {
                ctx.delete(sdMoment)
                hasDeletedSample = true
            }
            if hasDeletedSample {
                try? ctx.save()
            }
            let validMoments = sdMoments.filter { $0.name != "Sanur Beach" }
            self.collections = validMoments.map { $0.toFolderCollection() }
        }
        
        // Load Standalone Fragments
        let fragmentDescriptor = FetchDescriptor<SDFragment>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let sdFragments = try? ctx.fetch(fragmentDescriptor) {
            self.standaloneFragments = sdFragments.map { $0.toFragment() }
        }

        // Restore active session if a Live Activity is still running
        // (happens when the app was terminated while a moment was recording)
        reconnectLiveActivityIfNeeded()
    }

    /// If a Live Activity for this app is still alive (e.g. after app termination),
    /// rehydrate the session from UserDefaults so the UI stays consistent.
    private func reconnectLiveActivityIfNeeded() {
        // Only reconnect if we don't already have an active session
        guard activeSession == nil else { return }

        let runningActivities = Activity<MomentActivityAttributes>.activities
        guard let existing = runningActivities.first else {
            // No live activity running — clear any stale UserDefaults entry
            UserDefaults.standard.removeObject(forKey: kPersistedSessionKey)
            return
        }

        // Reconnect the activity reference so we can still update/end it
        liveActivity = existing

        // Restore session metadata from UserDefaults
        if let data = UserDefaults.standard.data(forKey: kPersistedSessionKey),
           let info = try? JSONDecoder().decode(PersistedSessionInfo.self, from: data) {
            // Note: fragments captured before termination are lost (they were in-memory only).
            // The session banner is restored so the user can End or Continue normally.
            activeSession = MomentSession(
                id: info.id,
                startDate: info.startDate,
                fragments: [],
                location: info.location
            )
        }
    }

    /// Saves a standalone fragment to SwiftData and updates local array
    func addStandaloneFragment(_ fragment: Fragment) {
        if !standaloneFragments.contains(where: { $0.id == fragment.id }) {
            standaloneFragments.insert(fragment, at: 0)
        }
        if let ctx = modelContext {
            let sdFrag = SDFragment(from: fragment)
            ctx.insert(sdFrag)
            try? ctx.save()
        }
    }

    /// Deletes a standalone fragment from SwiftData and local array
    func deleteStandaloneFragment(id: UUID) {
        standaloneFragments.removeAll(where: { $0.id == id })
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDFragment>(predicate: #Predicate { $0.id == id })
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    ctx.delete(item)
                }
                try? ctx.save()
            }
        }
    }

    /// Clears all standalone fragments from SwiftData and local array
    func clearAllStandaloneFragments() {
        standaloneFragments.removeAll()
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDFragment>()
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    ctx.delete(item)
                }
                try? ctx.save()
            }
        }
    }

    /// Updates color for a saved Moment in local state and SwiftData
    func updateMomentColor(id: UUID, color: Color?) {
        if let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index].color = color
        }
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matching = try? ctx.fetch(descriptor).first {
                matching.colorRGBAString = color?.toRGBAString()
                try? ctx.save()
            }
        }
    }

    /// Updates items and layout order for a saved Moment in local state and SwiftData
    func updateMomentItems(id: UUID, items: [FolderItem]) {
        if let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index].items = items
        }
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matching = try? ctx.fetch(descriptor).first {
                matching.updateItems(from: items, in: ctx)
                try? ctx.save()
            }
        }
    }

    /// Deletes a saved Moment from SwiftData and local array
    func deleteMoment(id: UUID) {
        collections.removeAll(where: { $0.id == id })
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    ctx.delete(item)
                }
                try? ctx.save()
            }
        }
    }

    /// Adds a saved Moment directly
    func addCollection(_ collection: FolderCollection) {
        if !collections.contains(where: { $0.id == collection.id }) {
            collections.insert(collection, at: 0)
        }
        if let ctx = modelContext {
            let sdMoment = SDMoment(from: collection)
            ctx.insert(sdMoment)
            try? ctx.save()
        }
    }

    /// Starts a new Moment recording session
    func startSession(location: String? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let resolvedLocation = location ?? LocationManager.shared.currentLocationName ?? "Current Location"
        let newSession = MomentSession(startDate: Date(), fragments: [], location: resolvedLocation)
        activeSession = newSession
        persistSession(newSession)
        startLiveActivity(session: newSession)
    }

    /// Adds a newly captured fragment to the active session
    func addFragment(_ fragment: Fragment) {
        guard var session = activeSession else { return }
        var newFragment = fragment
        let coords = Fragment.generateScatteredCoordinates(existing: session.fragments)
        newFragment.phi = coords.phi
        newFragment.theta = coords.theta
        newFragment.radiusFactor = coords.radiusFactor

        session.fragments.append(newFragment)
        activeSession = session
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateLiveActivity(session: session)
    }

    /// Prompts the End Moment sheet to name & categorize the session
    func requestEndSession() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showEndMomentSheet = true
    }

    /// Finalizes the active session into a saved FolderCollection / Moment and persists to SwiftData
    @discardableResult
    func finishSession(
        name: String,
        category: String = "Life",
        color: Color? = nil,
        location: String? = nil
    ) -> FolderCollection? {
        guard let session = activeSession else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocation = location ?? session.location
        let finalTitle = trimmedName.isEmpty ? "\(category) Moment" : trimmedName

        let folderItems = session.createFolderItems()

        let newCollection = FolderCollection(
            id: session.id,
            name: finalTitle,
            location: resolvedLocation,
            date: session.startDate,
            items: folderItems,
            color: color
        )

        withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
            collections.insert(newCollection, at: 0)
            activeSession = nil
            showEndMomentSheet = false
            recentlySavedMoment = newCollection
        }

        if let ctx = modelContext {
            let sdMoment = SDMoment(from: newCollection)
            ctx.insert(sdMoment)
            try? ctx.save()
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        clearPersistedSession()
        endLiveActivity()
        return newCollection
    }

    /// Discards the active session without saving
    func cancelSession() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        clearPersistedSession()
        endLiveActivity()
    }

    // MARK: - Session Persistence Helpers

    /// Saves a lightweight snapshot of the session to UserDefaults so it survives app termination.
    private func persistSession(_ session: MomentSession) {
        let info = PersistedSessionInfo(
            id: session.id,
            startDate: session.startDate,
            location: session.location
        )
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: kPersistedSessionKey)
        }
    }

    /// Removes the persisted session entry from UserDefaults.
    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: kPersistedSessionKey)
    }

    // MARK: - Live Activity Helpers

    /// Requests a new Live Activity for the given session.
    private func startLiveActivity(session: MomentSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // End any stale activity before starting a new one
        endLiveActivity()

        let attributes = MomentActivityAttributes(
            startDate: session.startDate,
            sessionID: session.id.uuidString
        )
        let initialState = MomentActivityAttributes.ContentState(
            fragmentCount: session.fragmentCount,
            location: session.location
        )

        do {
            let activity = try Activity<MomentActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            liveActivity = activity
        } catch {
            print("[MomentManager] Failed to start Live Activity: \(error)")
        }
    }

    /// Pushes an updated content state to the current Live Activity.
    private func updateLiveActivity(session: MomentSession) {
        guard let activity = liveActivity else { return }
        let updatedState = MomentActivityAttributes.ContentState(
            fragmentCount: session.fragmentCount,
            location: session.location
        )
        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
    }

    /// Ends the current Live Activity immediately.
    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
}
