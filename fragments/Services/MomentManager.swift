//
//  MomentManager.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI
import SwiftData
import Observation

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
            self.collections = sdMoments.map { $0.toFolderCollection() }
        }
        
        // Load Standalone Fragments
        let fragmentDescriptor = FetchDescriptor<SDFragment>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let sdFragments = try? ctx.fetch(fragmentDescriptor) {
            self.standaloneFragments = sdFragments.map { $0.toFragment() }
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

    /// Starts a new Moment recording session
    func startSession(location: String = "Jakarta, ID") {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeSession = MomentSession(startDate: Date(), fragments: [], location: location)
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
        return newCollection
    }

    /// Discards the active session without saving
    func cancelSession() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
    }
}
