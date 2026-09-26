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
    var isShared: Bool?
    var room: Room?
    var isHost: Bool?
}

private let kPersistedSessionKey = "fragments.activeSessionInfo"

/// Central observable manager for managing active Moment sessions and saved Moment collections.
@Observable
@MainActor
final class MomentManager {
    static let shared = MomentManager()
    public static let maxStandaloneFragments: Int = 15

    var activeSession: MomentSession? = nil
    var collections: [FolderCollection] = []
    var standaloneFragments: [Fragment] = []
    var showEndMomentSheet: Bool = false
    var recentlySavedMoment: FolderCollection? = nil

    /// Tracks whether the current user explicitly left a shared session.
    /// When true, prevents any auto-save (Multipeer or CloudKit relay) from persisting the moment.
    private(set) var hasLeftSession: Bool = false

    private var modelContext: ModelContext?
    /// Reference to the currently running Live Activity (nil when no session is active).
    private var liveActivity: Activity<MomentActivityAttributes>?

    var isSessionActive: Bool {
        activeSession != nil
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        setupMultipeerCallbacks()
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
            for sdMoment in sdMoments where sdMoment.name == "Sanur Beach" || sdMoment.name == "Bali Trip 2026" {
                ctx.delete(sdMoment)
                hasDeletedSample = true
            }
            if hasDeletedSample {
                try? ctx.save()
            }
            let validMoments = sdMoments.filter { $0.name != "Sanur Beach" && $0.name != "Bali Trip 2026" }
            self.collections = validMoments.map { $0.toFolderCollection() }
        }
        
        // Load Standalone Fragments (automatically purge fragments older than 24 hours)
        let fragmentDescriptor = FetchDescriptor<SDFragment>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let sdFragments = try? ctx.fetch(fragmentDescriptor) {
            let expirationThreshold = Date().addingTimeInterval(-Fragment.expirationDuration)
            var validFragments: [Fragment] = []
            var hasDeletedExpired = false
            for sdFrag in sdFragments {
                if sdFrag.createdAt < expirationThreshold {
                    ctx.delete(sdFrag)
                    hasDeletedExpired = true
                } else {
                    validFragments.append(sdFrag.toFragment())
                }
            }
            if hasDeletedExpired {
                try? ctx.save()
            }
            self.standaloneFragments = Array(validFragments.prefix(Self.maxStandaloneFragments))
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
                location: info.location,
                isShared: info.isShared ?? false,
                room: info.room,
                isHost: info.isHost ?? true
            )
        }
    }

    /// Removes standalone fragments older than 24 hours from SwiftData and local array
    func cleanupExpiredStandaloneFragments() {
        let expirationThreshold = Date().addingTimeInterval(-Fragment.expirationDuration)
        let expiredIDs = standaloneFragments.filter { $0.createdAt < expirationThreshold }.map { $0.id }
        guard !expiredIDs.isEmpty else { return }

        standaloneFragments.removeAll { $0.createdAt < expirationThreshold }
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDFragment>()
            if let allSD = try? ctx.fetch(descriptor) {
                var hasDeleted = false
                for sdFrag in allSD where sdFrag.createdAt < expirationThreshold {
                    ctx.delete(sdFrag)
                    hasDeleted = true
                }
                if hasDeleted {
                    try? ctx.save()
                }
            }
        }
    }

    /// Saves a standalone fragment to SwiftData and updates local array (capped at 15 items)
    func addStandaloneFragment(_ fragment: Fragment) {
        cleanupExpiredStandaloneFragments()
        guard standaloneFragments.count < Self.maxStandaloneFragments else { return }
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

    /// Updates color for a saved Moment in local state, SwiftData, and RoomManager if shared
    func updateMomentColor(id: UUID, roomID: String? = nil, color: Color?) {
        var targetRoomID: String? = roomID

        if let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index].color = color
            if targetRoomID == nil { targetRoomID = collections[index].roomID }
        }

        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matching = try? ctx.fetch(descriptor).first {
                matching.colorRGBAString = color?.toRGBAString()
                if targetRoomID == nil { targetRoomID = matching.roomID }
                try? ctx.save()
            }
        }

        // Sync with RoomManager if it's a collaborative Room!
        let resolvedRoomID = targetRoomID ?? (RoomManager.shared.rooms.contains(where: { $0.id == id.uuidString }) ? id.uuidString : nil)
        if let rID = resolvedRoomID, var room = RoomManager.shared.rooms.first(where: { $0.id == rID }) {
            room.accentColorHex = color?.toRGBAString()
            Task {
                try? await RoomManager.shared.updateRoom(room)
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

    /// Deletes a saved Moment from SwiftData, local array, and RoomManager if shared
    func deleteMoment(id: UUID, roomID: String? = nil) {
        var targetRoomID: String? = roomID

        if let index = collections.firstIndex(where: { $0.id == id }) {
            if targetRoomID == nil { targetRoomID = collections[index].roomID }
            collections.remove(at: index)
        }

        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    if targetRoomID == nil { targetRoomID = item.roomID }
                    ctx.delete(item)
                }
                try? ctx.save()
            }
        }

        // Also purge from RoomManager and CloudKit if it's a Room!
        let resolvedRoomID = targetRoomID ?? (RoomManager.shared.rooms.contains(where: { $0.id == id.uuidString }) ? id.uuidString : nil)
        if let rID = resolvedRoomID, RoomManager.shared.rooms.contains(where: { $0.id == rID }) {
            Task {
                try? await RoomManager.shared.deleteRoom(id: rID)
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
    func startSession(location: String? = nil, isShared: Bool = false, room: Room? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        hasLeftSession = false
        let resolvedLocation = location ?? LocationManager.shared.currentLocationName ?? "Current Location"
        let newSession = MomentSession(
            startDate: Date(),
            fragments: [],
            location: resolvedLocation,
            isShared: isShared,
            room: room
        )
        activeSession = newSession
        persistSession(newSession)
        startLiveActivity(session: newSession)
    }

    /// Starts a new collaborative Shared Moment session instantly with optimistic UI navigation,
    /// and provisions the CloudKit Room asynchronously in the background.
    func startSharedSession(location: String? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let resolvedLocation = location ?? LocationManager.shared.currentLocationName ?? "Current Location"
        let roomName = "Moment in \(resolvedLocation)"
        let roomId = UUID().uuidString

        let optimisticRoom = Room(
            id: roomId,
            name: roomName,
            emoji: "🌴",
            createdAt: Date(),
            createdBy: UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        )

        // 1. Immediately launch the active session so UI transitions with 0ms latency
        startSession(location: resolvedLocation, isShared: true, room: optimisticRoom)

        // 2. Start zero-config local P2P sync as Host
        let currentId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        let currentName = UserIdentityService.shared.currentUserIdentity?.displayName ?? ProfileManager.shared.signature
        let hostMember = RoomMember(
            roomId: roomId,
            userId: currentId,
            displayName: currentName,
            role: .owner,
            joinedAt: Date()
        )
        MultipeerSyncService.shared.start(roomID: roomId, localMember: hostMember, isHost: true)

        // 3. Asynchronously provision the Room in CloudKit in the background
        Task {
            if let provisionedRoom = try? await RoomManager.shared.createRoom(
                id: roomId,
                name: roomName,
                emoji: "🌴"
            ) {
                await MainActor.run {
                    if var current = self.activeSession, current.isShared, current.room?.id == roomId {
                        current.room = provisionedRoom
                        self.activeSession = current
                        self.persistSession(current)
                    }
                }
            }
        }
    }

    /// Joins an existing collaborative Shared Moment session in progress
    func joinSharedSession(room: Room) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        hasLeftSession = false

        let cached = (try? LocalRoomCache.shared.loadFragments(roomID: room.id))?.map { $0.toFragment() } ?? []
        let resolvedLocation = room.name.replacingOccurrences(of: "Moment in ", with: "")

        let session = MomentSession(
            startDate: room.createdAt,
            fragments: cached,
            location: resolvedLocation.isEmpty ? "Shared Location" : resolvedLocation,
            isShared: true,
            room: room,
            isHost: false
        )
        activeSession = session
        persistSession(session)
        startLiveActivity(session: session)

        // Start zero-config local P2P sync as Joiner
        let currentId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        let currentName = UserIdentityService.shared.currentUserIdentity?.displayName ?? ProfileManager.shared.signature
        let member = RoomMember(
            roomId: room.id,
            userId: currentId,
            displayName: currentName,
            role: room.createdBy == currentId ? .owner : .member,
            joinedAt: Date()
        )
        MultipeerSyncService.shared.start(roomID: room.id, localMember: member, isHost: false)

        // Asynchronously pull remote fragments from CloudKit in background
        Task {
            if let liveFragments = try? await CloudKitRoomRepository.shared.fetchFragments(roomID: room.id) {
                let domainFragments = liveFragments.map { $0.toFragment() }
                await MainActor.run {
                    if var current = self.activeSession, current.isShared, current.room?.id == room.id {
                        var combined = current.fragments
                        for frag in domainFragments {
                            if !combined.contains(where: { $0.id == frag.id }) {
                                combined.append(frag)
                            }
                        }
                        current.fragments = combined
                        self.activeSession = current
                        self.persistSession(current)
                    }
                }
            }
        }

        // Register current user as a participant member in CloudKit
        Task {
            try? await CloudKitRoomRepository.shared.saveMember(member)
        }
    }

    /// Adds a newly captured fragment to the active session (capped at 15 items)
    func addFragment(_ fragment: Fragment) {
        guard var session = activeSession else { return }
        guard session.fragments.count < MomentSession.maxFragments || session.isShared else { return }
        guard !session.fragments.contains(where: { $0.id == fragment.id }) else { return }
        var newFragment = fragment
        if newFragment.phi == 0.0 && newFragment.theta == 0.0 {
            let coords = Fragment.generateScatteredCoordinates(existing: session.fragments)
            newFragment.phi = coords.phi
            newFragment.theta = coords.theta
            newFragment.radiusFactor = coords.radiusFactor
        }

        session.fragments.append(newFragment)
        activeSession = session
        persistSession(session)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateLiveActivity(session: session)

        // Automatically sync to CloudKit and Multipeer if in a collaborative Shared Moment!
        if session.isShared, let room = session.room {
            let sharedFrag = newFragment.toSharedFragment(roomId: room.id)

            // 1. Instant local peer-to-peer broadcast (<50ms latency)
            MultipeerSyncService.shared.broadcastFragment(sharedFrag)

            // 2. Dual-sync to CloudKit & Public Cloud Relay
            if !RoomManager.shared.fragments.contains(where: { $0.id == newFragment.id.uuidString }) {
                Task {
                    try? await RoomManager.shared.captureSharedFragment(sharedFrag)
                }
            }
        }
    }

    // MARK: - Multipeer Connectivity Integration

    private func setupMultipeerCallbacks() {
        MultipeerSyncService.shared.onFragmentReceived = { [weak self] sharedFrag in
            guard let self = self, var current = self.activeSession, current.isShared else { return }
            let frag = sharedFrag.toFragment()
            if !current.fragments.contains(where: { $0.id == frag.id }) {
                current.fragments.append(frag)
                self.activeSession = current
                self.persistSession(current)
                self.updateLiveActivity(session: current)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let room = current.room {
                    try? LocalRoomCache.shared.saveFragments(current.fragments.map { $0.toSharedFragment(roomId: room.id) }, roomID: room.id)
                }
            }
        }

        MultipeerSyncService.shared.onMemberReceived = { [weak self] member in
            guard let self = self, var current = self.activeSession, current.isShared else { return }
            if var r = current.room {
                r.memberCount = max(r.memberCount, MultipeerSyncService.shared.connectedPeerCount + 1)
                current.room = r
                self.activeSession = current
                self.persistSession(current)
            }
        }

        MultipeerSyncService.shared.onSyncRequest = { [weak self] in
            guard let self = self, let session = self.activeSession, let room = session.room else { return [] }
            return session.fragments.map { $0.toSharedFragment(roomId: room.id) }
        }

        MultipeerSyncService.shared.onSessionEnded = { [weak self] finalTitle in
            guard let self = self, !self.hasLeftSession, let session = self.activeSession, !session.isHost else { return }
            self.finishSessionAsMember(finalTitle: finalTitle)
        }
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
            color: color,
            isShared: session.isShared,
            roomID: session.room?.id
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

        // If session was shared, also update/save the Room in RoomManager & broadcast sessionEnded!
        if session.isShared, var room = session.room {
            room.name = finalTitle
            room.accentColorHex = color?.toRGBAString()
            room.fragmentCount = session.fragments.count

            // 1. Broadcast sessionEnded via local Multipeer
            MultipeerSyncService.shared.broadcastSessionEnded(finalTitle: finalTitle, finalCategory: category)

            // 2. Mark in Public Cloud Relay and update room
            Task {
                await CloudKitRoomRepository.shared.markRoomEndedPublicRelay(roomID: room.id, finalTitle: finalTitle)
                try? await RoomManager.shared.updateRoom(room)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        clearPersistedSession()
        endLiveActivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MultipeerSyncService.shared.stop()
        }
        return newCollection
    }

    /// Leaves an active shared moment session as a participant without deleting the room for others.
    func leaveSession() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        hasLeftSession = true
        // Clear Multipeer callbacks to prevent delayed auto-save
        MultipeerSyncService.shared.onSessionEnded = nil
        MultipeerSyncService.shared.onFragmentReceived = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        clearPersistedSession()
        endLiveActivity()
        MultipeerSyncService.shared.stop()
    }

    /// Finalizes and saves the shared moment collection into the member's device when the host saves the session.
    @discardableResult
    func finishSessionAsMember(
        finalTitle: String,
        category: String = "Life",
        color: Color? = nil
    ) -> FolderCollection? {
        // If the user explicitly left the session, do not auto-save
        guard !hasLeftSession else { return nil }
        guard let session = activeSession else { return nil }

        let folderItems = session.createFolderItems()
        let newCollection = FolderCollection(
            id: session.id,
            name: finalTitle.isEmpty ? session.location : finalTitle,
            location: session.location,
            date: session.startDate,
            items: folderItems,
            color: color,
            isShared: true,
            roomID: session.room?.id
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
        MultipeerSyncService.shared.stop()
        return newCollection
    }

    /// Discards the active session without saving
    func cancelSession() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let sessionToCancel = activeSession
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        clearPersistedSession()
        endLiveActivity()
        MultipeerSyncService.shared.stop()

        if let session = sessionToCancel, session.isShared, let room = session.room {
            let currentUserId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
            if room.createdBy == currentUserId {
                Task {
                    try? await RoomManager.shared.deleteRoom(id: room.id)
                }
            }
        }
    }

    /// Updates the active session fragments from an external source (e.g. collaborative live sync)
    func updateActiveSessionFragments(_ fragments: [Fragment]) {
        guard var current = activeSession else { return }
        current.fragments = fragments
        activeSession = current
        persistSession(current)
    }

    // MARK: - Session Persistence Helpers

    /// Saves a lightweight snapshot of the session to UserDefaults so it survives app termination.
    func persistSession(_ session: MomentSession) {
        let info = PersistedSessionInfo(
            id: session.id,
            startDate: session.startDate,
            location: session.location,
            isShared: session.isShared,
            room: session.room,
            isHost: session.isHost
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
