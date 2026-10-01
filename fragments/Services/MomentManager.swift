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

    /// Active background task observing Supabase Realtime domain events from RoomManager.
    private var supabaseRealtimeTask: Task<Void, Never>? = nil

    /// In-flight media metadata received before the corresponding fragment row arrived via Realtime.
    private var pendingRemoteMedia: [String: (media: SharedMediaReference, roomID: String)] = [:]

    /// Bounded retry schedule for receiver-side media hydration (P0-1/P0-2).
    /// A fragment row is visible seconds before its media row, and downloads
    /// can fail transiently — so lookups/downloads retry on this schedule,
    /// then stop. Never retried indefinitely.
    static let mediaHydrationDelays: [TimeInterval] = [0.5, 1.0, 2.0]

    /// Hydration tasks in flight, keyed by "roomID/fragmentID".
    /// Single choke point for media downloads: if the fragment and media
    /// realtime handlers race on the same fragment, only one download runs.
    private var mediaHydrationTasks: [String: Task<Void, Never>] = [:]

    /// Fragments whose remote media has been successfully attached this session.
    private var hydratedMediaFragmentIDs: Set<String> = []

    private var modelContext: ModelContext?
    /// Reference to the currently running Live Activity (nil when no session is active).
    private var liveActivity: Activity<MomentActivityAttributes>?

    var isSessionActive: Bool {
        activeSession != nil
    }

    var isRemoteSyncTaskActive: Bool {
        remoteSyncTask != nil
    }
    var isSupabaseRealtimeTaskActive: Bool {
        supabaseRealtimeTask != nil
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        setupMultipeerCallbacks()
        observeRoomMetadataChanges()
        if let context = modelContext {
            loadPersistedData(context: context)
        }
    }

    deinit {
        if let observer = roomMetadataObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Room metadata (name/category/color) for shared moments arrives via
    /// RoomManager; this observes it to update saved collections + SwiftData.
    /// Nonisolated storage so `deinit` can deregister (singleton never deinits
    /// in practice; assignment always happens on the main actor).
    nonisolated(unsafe) private var roomMetadataObserver: NSObjectProtocol?

    private func observeRoomMetadataChanges() {
        roomMetadataObserver = NotificationCenter.default.addObserver(
            forName: .fragmentsRoomMetadataChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let roomID = note.object as? String,
                   let room = RoomManager.shared.rooms.first(where: { $0.id == roomID }) {
                    self.applySharedRoomMetadata(room)
                } else {
                    self.reconcileSharedMetadataFromRooms()
                }
            }
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

        // Repair saved shared moments against known room metadata (covers
        // relaunch when SwiftData is stale but the room cache is fresh).
        reconcileSharedMetadataFromRooms()

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
            let cached = info.room != nil ? ((try? LocalRoomCache.shared.loadFragments(roomID: info.room!.id))?.map { $0.toFragment() } ?? []) : []
            let restored = MomentSession(
                id: info.id,
                startDate: info.startDate,
                fragments: cached,
                location: info.location,
                isShared: info.isShared ?? false,
                room: info.room,
                isHost: info.isHost ?? true
            )
            activeSession = restored
            if restored.isShared, let room = restored.room {
                if room.backend == .supabase {
                    RoomManager.shared.currentRoom = room
                    startSupabaseRealtimeObserver(roomID: room.id)
                } else {
                    startRemoteSyncObserver(roomID: room.id)
                }
            }
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

    /// Updates name/category/color for a saved Moment in local state, SwiftData,
    /// and the shared Room (which receivers reconcile via room metadata).
    ///
    /// Powers Edit Moment (FolderDetailBottomSheet Save). Name falls back to the
    /// existing name when blank; empty category keeps the existing category.
    /// Fragments and media are never touched — metadata-only update, so no
    /// duplicates and no re-uploads.
    func updateMomentMetadata(id: UUID, roomID: String? = nil, name: String, category: String, color: Color?) {
        var targetRoomID: String? = roomID
        var fallbackName: String? = nil
        var fallbackCategory: String? = nil

        if let index = collections.firstIndex(where: { $0.id == id }) {
            if targetRoomID == nil { targetRoomID = collections[index].roomID }
            fallbackName = collections[index].name
            fallbackCategory = collections[index].category
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { collections[index].name = trimmedName }
            if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                collections[index].category = category
            }
            collections[index].color = color
        }

        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matching = try? ctx.fetch(descriptor).first {
                if targetRoomID == nil { targetRoomID = matching.roomID }
                if fallbackName == nil { fallbackName = matching.name }
                if fallbackCategory == nil { fallbackCategory = matching.category }
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty { matching.name = trimmedName }
                if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    matching.category = category
                }
                matching.colorRGBAString = color?.toRGBAString()
                try? ctx.save()
            }
        }

        // Sync with RoomManager if it's a collaborative Room (receivers apply
        // name ← finalTitle, category ← finalCategory, color ← accentColorHex).
        let resolvedRoomID = targetRoomID ?? (RoomManager.shared.rooms.contains(where: { $0.id == id.uuidString }) ? id.uuidString : nil)
        if let rID = resolvedRoomID,
           var room = RoomManager.shared.rooms.first(where: { $0.id == rID })
               ?? (RoomManager.shared.currentRoom?.id == rID ? RoomManager.shared.currentRoom : nil) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? (fallbackName ?? room.finalTitle ?? room.name) : trimmedName
            room.name = finalName
            room.finalTitle = finalName
            let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
            room.finalCategory = trimmedCategory.isEmpty ? (fallbackCategory ?? room.finalCategory) : trimmedCategory
            room.accentColorHex = color?.toRGBAString()
            Task {
                try? await RoomManager.shared.updateRoom(room)
            }
        }
    }

    /// Applies authoritative shared-room metadata to locally saved collections
    /// + SwiftData. Receiver-side half of metadata sync (and relaunch repair):
    /// only explicit values overwrite — name requires `finalTitle`, category
    /// requires `finalCategory` (legacy rows carry nil and must not clobber
    /// good local values); color follows `accentColorHex` (nil = Default theme).
    /// Returns whether anything changed. Fragments/media untouched.
    @discardableResult
    func applySharedRoomMetadata(_ room: Room) -> Bool {
        var changed = false
        for i in collections.indices where collections[i].roomID == room.id {
            if let finalTitle = room.finalTitle, !finalTitle.isEmpty, collections[i].name != finalTitle {
                collections[i].name = finalTitle
                changed = true
            }
            if let finalCategory = room.finalCategory, !finalCategory.isEmpty, collections[i].category != finalCategory {
                collections[i].category = finalCategory
                changed = true
            }
            let newColor = room.accentColorHex.map { Color.fromRGBAString($0) }
            if collections[i].color != newColor {
                collections[i].color = newColor
                changed = true
            }
        }
        guard changed else { return false }
        if let ctx = modelContext {
            for collection in collections where collection.roomID == room.id {
                let cid = collection.id
                if let matching = try? ctx.fetch(FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == cid })).first {
                    if let finalTitle = room.finalTitle, !finalTitle.isEmpty { matching.name = finalTitle }
                    if let finalCategory = room.finalCategory, !finalCategory.isEmpty { matching.category = finalCategory }
                    matching.colorRGBAString = room.accentColorHex
                }
            }
            try? ctx.save()
        }
        return true
    }

    /// Reconciles all locally saved shared moments against known rooms.
    /// Called on launch (repairs stale SwiftData after relaunch) and whenever
    /// room metadata may have changed (realtime/refresh notification).
    func reconcileSharedMetadataFromRooms() {
        for room in RoomManager.shared.rooms {
            applySharedRoomMetadata(room)
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
        if let rID = targetRoomID {
            collections.removeAll(where: { $0.roomID == rID })
        }

        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    if targetRoomID == nil { targetRoomID = item.roomID }
                    ctx.delete(item)
                }
            }
            if let rID = targetRoomID {
                let rDescriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.roomID == rID })
                if let rMatchings = try? ctx.fetch(rDescriptor) {
                    for item in rMatchings {
                        ctx.delete(item)
                    }
                }
            }
            try? ctx.save()
        }

        // Also purge from RoomManager and remote backend (Supabase / CloudKit) if it's a Room!
        let resolvedRoomID = targetRoomID ?? (RoomManager.shared.rooms.contains(where: { $0.id == id.uuidString }) ? id.uuidString : nil)
        if let rID = resolvedRoomID {
            Task {
                try? await RoomManager.shared.deleteRoom(id: rID)
            }
        }
    }

    /// Leaves a shared Moment without deleting the underlying room for the owner.
    /// Removes from local collections, SwiftData, and RoomManager's local list,
    /// and invokes remote leave (deleting membership in Supabase).
    func leaveMoment(id: UUID, roomID: String? = nil) {
        var targetRoomID: String? = roomID

        if let index = collections.firstIndex(where: { $0.id == id }) {
            if targetRoomID == nil { targetRoomID = collections[index].roomID }
            collections.remove(at: index)
        }
        if let rID = targetRoomID {
            collections.removeAll(where: { $0.roomID == rID })
        }

        if let ctx = modelContext {
            let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == id })
            if let matchings = try? ctx.fetch(descriptor) {
                for item in matchings {
                    if targetRoomID == nil { targetRoomID = item.roomID }
                    ctx.delete(item)
                }
            }
            if let rID = targetRoomID {
                let rDescriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.roomID == rID })
                if let rMatchings = try? ctx.fetch(rDescriptor) {
                    for item in rMatchings {
                        ctx.delete(item)
                    }
                }
            }
            try? ctx.save()
        }

        // Remove from RoomManager's local list and cache, and leave remotely on backend
        let resolvedRoomID = targetRoomID ?? (RoomManager.shared.rooms.contains(where: { $0.id == id.uuidString }) ? id.uuidString : nil)
        if let rID = resolvedRoomID {
            Task {
                await RoomManager.shared.leaveRoom(id: rID)
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
        let sessionStartDate = room?.createdAt ?? Date()
        let newSession = MomentSession(
            startDate: sessionStartDate,
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
        // Guest Mode backstop: guests have no identity, so a shared session
        // must never be created optimistically nor provisioned remotely. The
        // UI gates first (auth-required sheet); this prevents any other path
        // from reaching the backend.
        guard !OnboardingCoordinator.shared.isGuest else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let resolvedLocation = location ?? LocationManager.shared.currentLocationName ?? "Current Location"
        let roomName = "Moment in \(resolvedLocation)"
        let roomId = UUID().uuidString
        let sessionStartDate = Date()

        // NOTE (join-code security): the join credential is a server-generated
        // CSPRNG value returned by create_room_with_owner. It is NEVER derived
        // from roomId client-side. The optimistic room therefore carries no
        // code until provisioning completes and swaps in the provisioned room.
        let creatorId: String = {
            if SupabaseService.shared.isAuthenticated, let sbUserId = SupabaseService.shared.currentUserID {
                return sbUserId
            }
            return UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        }()
        let optimisticRoom = Room(
            id: roomId,
            name: roomName,
            emoji: "✨",
            createdAt: sessionStartDate,
            createdBy: creatorId,
            shareRecordID: nil,
            zoneName: SupabaseService.shared.isAuthenticated ? "supabase" : nil
        )

        // 1. Immediately launch the active session so UI transitions with 0ms latency
        startSession(location: resolvedLocation, isShared: true, room: optimisticRoom)

        // 2. Start zero-config local P2P sync as Host with the shared session start date
        let currentId = UserIdentityService.shared.collaborativeUserID ?? UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        let currentName = ProfileManager.shared.effectiveName
        let hostMember = RoomMember(
            roomId: roomId,
            userId: currentId,
            displayName: currentName,
            role: .owner,
            joinedAt: Date()
        )
        MultipeerSyncService.shared.start(roomID: roomId, localMember: hostMember, isHost: true, sessionStartDate: sessionStartDate)

        // 3. Setup remote sync: Supabase Realtime vs Legacy CloudKit
        if optimisticRoom.backend == .supabase {
            RoomManager.shared.currentRoom = optimisticRoom
            startSupabaseRealtimeObserver(roomID: roomId)

            // Asynchronously provision the Room in Supabase in background
            Task {
                if let provisionedRoom = try? await RoomManager.shared.createRoom(
                    id: roomId,
                    name: roomName,
                    emoji: "✨",
                    createdAt: sessionStartDate,
                    backend: .supabase
                ) {
                    await MainActor.run {
                        // Discard guard: if the session was cancelled while provisioning,
                        // do not re-attach a ghost room (suppression is synchronous in cancelSession).
                        guard !RoomManager.shared.locallyRemovedRoomIDs.contains(roomId.lowercased()) else { return }
                        if var current = self.activeSession, current.isShared, current.room?.id == roomId {
                            current.room = provisionedRoom
                            self.activeSession = current
                            self.persistSession(current)
                        }
                    }
                }
            }
        } else {
            // Legacy CloudKit path
            Task {
                if let provisionedRoom = try? await RoomManager.shared.createRoom(
                    id: roomId,
                    name: roomName,
                    emoji: "✨",
                    createdAt: sessionStartDate,
                    backend: .cloudKit
                ) {
                    await MainActor.run {
                        guard !RoomManager.shared.locallyRemovedRoomIDs.contains(roomId.lowercased()) else { return }
                        if var current = self.activeSession, current.isShared, current.room?.id == roomId {
                            current.room = provisionedRoom
                            self.activeSession = current
                            self.persistSession(current)
                        }
                    }
                }
            }

            // Start continuous remote live sync across internet / different networks
            startRemoteSyncObserver(roomID: roomId)
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

        // 1. Start zero-config local P2P sync as Joiner
        let currentId = UserIdentityService.shared.collaborativeUserID ?? UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        let currentName = ProfileManager.shared.effectiveName
        let member = RoomMember(
            roomId: room.id,
            userId: currentId,
            displayName: currentName,
            role: room.isCurrentUserOwner ? .owner : .member,
            joinedAt: Date()
        )
        MultipeerSyncService.shared.start(roomID: room.id, localMember: member, isHost: false, sessionStartDate: room.createdAt)

        if room.backend == .supabase {
            // 2. Supabase Realtime path: set currentRoom and observe typed Realtime domain events
            RoomManager.shared.currentRoom = room
            startSupabaseRealtimeObserver(roomID: room.id)

            // Reconcile preexisting fragments from RoomManager / Supabase
            Task {
                await RoomManager.shared.loadRoomDetails(roomID: room.id)
                await MainActor.run {
                    guard var current = self.activeSession, current.isShared, current.room?.id == room.id else { return }
                    let rmFragments = RoomManager.shared.fragments.map { $0.toFragment() }
                    var updated = current.fragments
                    var hasNew = false
                    for frag in rmFragments {
                        if !updated.contains(where: { $0.id == frag.id }) {
                            var placed = frag
                            let resolved = Fragment.resolveCoordinates(
                                phi: placed.phi,
                                theta: placed.theta,
                                radiusFactor: placed.radiusFactor,
                                selfID: placed.id,
                                existing: updated,
                                epsilon: FragmentSphere.overlapEpsilon
                            )
                            placed.phi = resolved.phi
                            placed.theta = resolved.theta
                            placed.radiusFactor = resolved.radiusFactor
                            updated.append(placed)
                            hasNew = true
                        }
                    }
                    if hasNew {
                        current.fragments = updated
                        self.activeSession = current
                        self.persistSession(current)
                        self.updateLiveActivity(session: current)
                        print("📥 [MomentManager] Reconciled \(rmFragments.count) fragments from Supabase into active session")
                    }
                    // Fetched rows carry remote storage paths but no local files;
                    // trigger downloads so joiners see media, not blank cards.
                    self.backfillMissingSessionMedia()
                }
            }
        } else {
            // 2. Legacy CloudKit path: continuous polling and record fetching
            startRemoteSyncObserver(roomID: room.id)

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
    }

    /// Adds a newly captured fragment to the active session (capped at 15 items)
    func addFragment(_ fragment: Fragment) {
        // TEMPORARY trace (no behavior change).
        print("[PhotoTrace] MOMENT_MANAGER_ADD_FRAGMENT_CALLED id=\(fragment.id) type=\(fragment.type.rawValue)")
        guard var session = activeSession else { return }
        guard session.fragments.count < MomentSession.maxFragments || session.isShared else { return }
        guard !session.fragments.contains(where: { $0.id == fragment.id }) else { return }
        var newFragment = fragment
        // Stable placement: keep stored coordinates unless unset, default, or
        // colliding — only genuinely new/colliding fragments are (re)sampled.
        let resolved = Fragment.resolveCoordinates(
            phi: newFragment.phi,
            theta: newFragment.theta,
            radiusFactor: newFragment.radiusFactor,
            selfID: newFragment.id,
            existing: session.fragments,
            epsilon: FragmentSphere.overlapEpsilon
        )
        newFragment.phi = resolved.phi
        newFragment.theta = resolved.theta
        newFragment.radiusFactor = resolved.radiusFactor

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
            if !RoomManager.shared.fragments.contains(where: { $0.id.lowercased() == newFragment.id.uuidString.lowercased() }) {
                Task {
                    try? await RoomManager.shared.captureSharedFragment(sharedFrag)
                }
            }
        }
    }

    /// Converts session `Fragment`s back to `SharedFragment`s without losing authorship.
    ///
    /// `Fragment` (sphere/session UI) drops `authorId`/`authorName` at conversion
    /// time, so a naive `toSharedFragment(roomId:)` re-stamps every fragment with
    /// the current user — making "Captured by" show my username on someone else's
    /// fragment once the poisoned rows reach `LocalRoomCache`.
    /// This helper restores the authoritative author from `RoomManager.fragments`
    /// first (Supabase fetch / Realtime, correct by construction), then from the
    /// existing disk cache, and only falls back to the current user for genuinely
    /// new local fragments. `knownAuthors` lets callers inject authorship that is
    /// not yet in either store (e.g. a just-received Multipeer fragment).
    func sharedFragmentsPreservingAuthorship(
        from fragments: [Fragment],
        roomId: String,
        knownAuthors: [String: (authorId: String, authorName: String)] = [:]
    ) -> [SharedFragment] {
        var authoritative: [String: (authorId: String, authorName: String)] = [:]
        for shared in RoomManager.shared.fragments where shared.roomId == roomId {
            authoritative[shared.id.lowercased()] = (shared.authorId, shared.authorName)
        }
        let cachedLookup: [String: (authorId: String, authorName: String)] = {
            guard let cached = try? LocalRoomCache.shared.loadFragments(roomID: roomId) else { return [:] }
            var map: [String: (authorId: String, authorName: String)] = [:]
            for shared in cached {
                map[shared.id.lowercased()] = (shared.authorId, shared.authorName)
            }
            return map
        }()
        let knownLowercased: [String: (authorId: String, authorName: String)] = Dictionary(
            uniqueKeysWithValues: knownAuthors.map { ($0.key.lowercased(), $0.value) }
        )
        return fragments.map { frag in
            let key = frag.id.uuidString.lowercased()
            if let known = knownLowercased[key] {
                return frag.toSharedFragment(roomId: roomId, authorId: known.authorId, authorName: known.authorName)
            }
            if let auth = authoritative[key] {
                return frag.toSharedFragment(roomId: roomId, authorId: auth.authorId, authorName: auth.authorName)
            }
            if let cached = cachedLookup[key] {
                return frag.toSharedFragment(roomId: roomId, authorId: cached.authorId, authorName: cached.authorName)
            }
            return frag.toSharedFragment(roomId: roomId)
        }
    }

    /// Persists session fragments to the room disk cache without clobbering authorship.
    func persistSessionFragmentsPreservingAuthorship(
        _ fragments: [Fragment],
        roomId: String,
        knownAuthors: [String: (authorId: String, authorName: String)] = [:]
    ) {
        let shared = sharedFragmentsPreservingAuthorship(from: fragments, roomId: roomId, knownAuthors: knownAuthors)
        try? LocalRoomCache.shared.saveFragments(shared, roomID: roomId)
    }

    // MARK: - Multipeer Connectivity Integration

    private func setupMultipeerCallbacks() {
        MultipeerSyncService.shared.onFragmentReceived = { [weak self] sharedFrag in
            guard let self = self, var current = self.activeSession, current.isShared else { return }
            var frag = sharedFrag.toFragment()
            if !current.fragments.contains(where: { $0.id == frag.id }) {
                let resolved = Fragment.resolveCoordinates(
                    phi: frag.phi,
                    theta: frag.theta,
                    radiusFactor: frag.radiusFactor,
                    selfID: frag.id,
                    existing: current.fragments,
                    epsilon: FragmentSphere.overlapEpsilon
                )
                frag.phi = resolved.phi
                frag.theta = resolved.theta
                frag.radiusFactor = resolved.radiusFactor
                current.fragments.append(frag)
                self.activeSession = current
                self.persistSession(current)
                self.updateLiveActivity(session: current)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let room = current.room {
                    let known = [sharedFrag.id: (authorId: sharedFrag.authorId, authorName: sharedFrag.authorName)]
                    self.persistSessionFragmentsPreservingAuthorship(current.fragments, roomId: room.id, knownAuthors: known)
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
            return self.sharedFragmentsPreservingAuthorship(from: session.fragments, roomId: room.id)
        }

        MultipeerSyncService.shared.onSessionEnded = { [weak self] finalTitle, finalCategory in
            guard let self = self, !self.hasLeftSession, let session = self.activeSession, !session.isHost else { return }
            self.finishSessionAsMember(finalTitle: finalTitle, category: finalCategory ?? "Life")
        }

        MultipeerSyncService.shared.onSessionStartDateReceived = { [weak self] hostStartDate in
            guard let self = self else { return }
            self.updateSessionStartDate(hostStartDate)
        }
    }

    /// Synchronizes the shared moment start date across members to match the owner
    func updateSessionStartDate(_ newStartDate: Date) {
        guard var current = activeSession, current.isShared, !current.isHost else { return }
        guard abs(current.startDate.timeIntervalSince(newStartDate)) > 0.5 else { return }
        print("⏱️ [MomentManager] Synchronized start date to owner: \(newStartDate)")
        current.startDate = newStartDate
        if var r = current.room {
            r.createdAt = newStartDate
            current.room = r
            try? LocalRoomCache.shared.saveRoom(r)
        }
        self.activeSession = current
        self.persistSession(current)
        self.startLiveActivity(session: current)
    }

    // MARK: - Remote Background Synchronization Engine
    private var remoteSyncTask: Task<Void, Never>? = nil

    /// Starts a continuous background sync engine that keeps active shared moments updated
    /// over the internet / cellular networks regardless of which screen or view is currently open.
    ///
    /// - Note: Bypasses execution when the active room uses the Supabase backend, as Supabase
    /// Realtime provides reactive push updates and eliminates the need for CloudKit polling.
    func startRemoteSyncObserver(roomID: String) {
        guard let current = activeSession, current.room?.backend != .supabase else {
            print("ℹ️ [MomentManager] startRemoteSyncObserver bypassed for Supabase room: \(roomID)")
            return
        }

        stopRemoteSyncObserver()
        remoteSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, let current = self.activeSession, current.isShared, current.room?.id == roomID, current.room?.backend != .supabase else {
                    break
                }

                // 1. If we are a member, check if host ended the session remotely
                if !current.isHost {
                    let (isEnded, finalTitle) = await CloudKitRoomRepository.shared.checkRoomEndedPublicRelay(roomID: roomID)
                    if isEnded {
                        await MainActor.run {
                            guard !self.hasLeftSession, self.activeSession != nil else { return }
                            self.finishSessionAsMember(finalTitle: finalTitle ?? "Shared Moment")
                        }
                        break
                    }

                    // 2. Sync room creation / start date if host provisioned it
                    if let cloudRoom = try? await CloudKitRoomRepository.shared.fetchRoom(id: roomID) {
                        await MainActor.run {
                            self.updateSessionStartDate(cloudRoom.createdAt)
                        }
                    }
                }

                // 3. Fetch remote fragments from CloudKit / Public Relay
                if let liveFragments = try? await CloudKitRoomRepository.shared.fetchFragments(roomID: roomID) {
                    let domainFragments = liveFragments.map { $0.toFragment() }
                    await MainActor.run {
                        guard var session = self.activeSession, session.isShared, session.room?.id == roomID else { return }
                        var updated = session.fragments
                        var hasNew = false
                        for frag in domainFragments {
                            if !updated.contains(where: { $0.id == frag.id }) {
                                updated.append(frag)
                                hasNew = true
                            }
                        }
                        if hasNew {
                            session.fragments = updated
                            self.activeSession = session
                            self.persistSession(session)
                            self.updateLiveActivity(session: session)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if let room = session.room {
                                self.persistSessionFragmentsPreservingAuthorship(session.fragments, roomId: room.id)
                            }
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Stops the remote background synchronization engine.
    func stopRemoteSyncObserver() {
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
    }

    // MARK: - Supabase Realtime Collaborative Engine

    /// Starts observation of typed Supabase Realtime domain events forwarded by RoomManager.
    func startSupabaseRealtimeObserver(roomID: String) {
        stopSupabaseRealtimeObserver()

        print("📡 [MomentManager] Starting Supabase Realtime observation for room: \(roomID)")
        supabaseRealtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in RoomManager.shared.realtimeEvents {
                guard !Task.isCancelled else { break }
                guard let current = self.activeSession, current.isShared, current.room?.id == roomID else {
                    print("🛑 [MomentManager] Active session ended or mismatch; stopping Realtime observation for room: \(roomID)")
                    break
                }
                self.handleRealtimeEvent(event, forRoomID: roomID)
            }
        }
    }

    /// Stops observation of Supabase Realtime events for active shared sessions.
    func stopSupabaseRealtimeObserver() {
        if supabaseRealtimeTask != nil {
            print("🛑 [MomentManager] Stopping Supabase Realtime observer")
            supabaseRealtimeTask?.cancel()
            supabaseRealtimeTask = nil
        }
    }

    /// Reconciles typed Realtime events from RoomManager into the active MomentSession.
    func handleRealtimeEvent(_ event: SupabaseRealtimeEvent, forRoomID roomID: String) {
        guard let current = activeSession, current.isShared, current.room?.id == roomID else { return }

        switch event {
        case .fragmentCreated(let sharedFrag):
            guard sharedFrag.roomId == roomID else { return }
            handleRealtimeFragmentCreated(sharedFrag)

        case .fragmentUpdated(let sharedFrag):
            guard sharedFrag.roomId == roomID else { return }
            handleRealtimeFragmentUpdated(sharedFrag)

        case .fragmentDeleted(let fragmentID, let rID, _):
            guard rID == roomID else { return }
            handleRealtimeFragmentDeleted(fragmentID: fragmentID, roomID: roomID)

        case .fragmentMediaCreated(let media, let fragmentID, let rID):
            guard rID == roomID else { return }
            handleRealtimeMediaCreated(media: media, fragmentID: fragmentID, roomID: roomID)

        case .fragmentMediaDeleted(let storagePath, let fragmentID, let rID):
            guard rID == roomID else { return }
            handleRealtimeMediaDeleted(storagePath: storagePath, fragmentID: fragmentID, roomID: roomID)

        case .roomChanged(let updatedRoom):
            guard updatedRoom.id == roomID else { return }
            handleRealtimeRoomChanged(updatedRoom)

        case .roomDeleted(let deletedID):
            guard deletedID == roomID else { return }
            handleRealtimeRoomDeleted(roomID: deletedID)

        case .memberJoined(let member):
            guard member.roomId == roomID else { return }
            handleRealtimeMemberJoined(member)

        case .memberChanged(let member):
            guard member.roomId == roomID else { return }
            handleRealtimeMemberChanged(member)

        case .memberLeft(let memberID, let rID, let userID):
            guard rID == roomID else { return }
            handleRealtimeMemberLeft(memberID: memberID, userID: userID)
        }
    }

    private func attachLocalMedia(localURL: URL, fragmentID: String, roomID: String) {
        // TEMPORARY diagnostic (no behavior change).
        print("[MediaDebug] Attaching local media")
        print("[MediaDebug] fragmentID: \(fragmentID)")
        print("[MediaDebug] localPath: \(localURL.path)")
        guard var current = activeSession, current.isShared else { return }
        guard let targetUUID = UUID(uuidString: fragmentID) else { return }

        guard let idx = current.fragments.firstIndex(where: { $0.id == targetUUID }) else {
            print("[MediaDebug] attach SKIPPED: fragment not in session: \(fragmentID)")
            return
        }

        print("🖼️ [MomentManager] Attaching local media path: \(localURL.path) to fragment: \(fragmentID)")
        current.fragments[idx].mediaResourceName = localURL.path
        self.activeSession = current
        self.persistSession(current)
        print("[Media] UI state updated: \(fragmentID)")
        print("[MediaDebug] Local media attached")
        print("[MediaDebug] fragmentID: \(fragmentID)")
        print("[MediaDebug] mediaResourceName: \(localURL.path)")
        print("[MediaDebug] UI state published")
        print("[MediaDebug] fragmentID: \(fragmentID)")
    }

    /// Downloads remote media for session fragments that reference a remote
    /// storage path but have no local file yet.
    ///
    /// Root-cause fix for "media not live on other devices" for joiners: rows
    /// reconciled mid-session via fetch (`joinSharedSession`, `loadRoomDetails`)
    /// arrive with `mediaReference.storagePath` but `toFragment()` can only use
    /// the disk cache — no download is ever triggered on that path, unlike the
    /// realtime path. This pass closes the gap; it no-ops when nothing is missing.
    func backfillMissingSessionMedia() {
        guard let current = activeSession, current.isShared, let room = current.room else { return }
        let roomID = room.id
        let remoteByID = Dictionary(
            uniqueKeysWithValues: RoomManager.shared.fragments.compactMap { shared -> (String, SharedMediaReference)? in
                guard let ref = shared.mediaReference,
                      let path = ref.storagePath, !path.isEmpty else { return nil }
                return (shared.id, ref)
            }
        )
        let missing = current.fragments.filter { frag in
            guard remoteByID[frag.id.uuidString] != nil else { return false }
            guard let local = frag.mediaResourceName, !local.isEmpty,
                  FileManager.default.fileExists(atPath: local) else { return true }
            return false
        }
        guard !missing.isEmpty else { return }
        print("🖼️ [MomentManager] Backfilling media for \(missing.count) fragment(s) in room: \(roomID)")
        for frag in missing {
            hydrateFragmentMedia(fragmentID: frag.id.uuidString, roomID: roomID)
        }
    }

    // MARK: - Receiver-Side Media Hydration (P0-1 / P0-2 / P0-3)

    /// Single choke point for hydrating remote media of one fragment.
    ///
    /// Works regardless of arrival order (P0-3): when the fragment event wins,
    /// `knownMedia` is nil and the `fragment_media` row is looked up with
    /// bounded backoff; when the media event wins, its reference is passed in
    /// and used directly. Either way the same task key ("roomID/fragmentID")
    /// guarantees only one download executes — a second caller while hydration
    /// is in flight, or after success, is a no-op (idempotent).
    ///
    /// Text/note fragments never need hydration; callers must not invoke this
    /// for them. Uses only the existing fetch → signed-URL → download →
    /// attach pipeline. Never retries indefinitely.
    func hydrateFragmentMedia(fragmentID: String, roomID: String, knownMedia: SharedMediaReference? = nil) {
        let key = "\(roomID)/\(fragmentID)"
        guard !hydratedMediaFragmentIDs.contains(key) else { return }
        guard mediaHydrationTasks[key] == nil else { return }

        print("[Media] Looking up fragment_media: \(fragmentID)")
        mediaHydrationTasks[key] = Task { [weak self] in
            defer { self?.mediaHydrationTasks[key] = nil }
            guard let self else { return }

            // TEMPORARY diagnostic (no behavior change): auth/session/realtime
            // snapshot to discriminate Xcode-attached vs standalone failures.
            // Never prints tokens — only presence booleans and the uid RLS uses.
            let debugUID = SupabaseService.shared.currentUserID
            print("[MediaDebug] Hydration start fragmentID: \(fragmentID) roomID: \(roomID)")
            print("[MediaDebug] auth user present: \(debugUID != nil)")
            print("[MediaDebug] auth uid: \(debugUID ?? "nil")")
            print("[MediaDebug] supabase session present: \(SupabaseService.shared.session != nil)")
            print("[MediaDebug] Supabase client initialized: true")
            print("[MediaDebug] realtime connected: \(SupabaseRealtimeCoordinator.shared.connectionState == .connected)")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                print("[MediaDebug] app version: \(version) build: \(build)")
            }

            // Hydration targets the Supabase path only; other backends keep
            // their own sync engines.
            let isSupabaseRoom: Bool = await MainActor.run {
                self.activeSession?.room?.backend == .supabase
            }
            guard isSupabaseRoom else { return }

            var ref = knownMedia
            var lastError: Error?
            let delays = Self.mediaHydrationDelays

            // Attempt 0 runs immediately, then one attempt per backoff delay.
            for attempt in 0...delays.count {
                if Task.isCancelled { return }
                if attempt > 0 {
                    let wait = delays[attempt - 1]
                    print("[Media] Retrying in \(wait)s: \(fragmentID) (attempt \(attempt + 1)/\(delays.count + 1))")
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    if Task.isCancelled { return }
                }

                // 1. Resolve the media reference.
                // TEMPORARY diagnostic: keep lookup errors distinct from empty
                // results — an RLS/auth failure must NOT look like NOT FOUND.
                if ref == nil {
                    print("[MediaDebug] Looking up fragment_media")
                    print("[MediaDebug] fragmentID: \(fragmentID)")
                    print("[MediaDebug] roomID: \(roomID)")
                    do {
                        if let found = try await SupabaseRoomRepository.shared.fetchFragmentMedia(fragmentID: fragmentID, roomID: roomID) {
                            print("[Media] fragment_media FOUND: \(found.storagePath ?? "?")")
                            print("[MediaDebug] FOUND storagePath: \(found.storagePath ?? "nil")")
                            ref = found
                        } else {
                            print("[Media] fragment_media NOT FOUND: \(fragmentID)")
                            print("[MediaDebug] fragment_media NOT FOUND")
                        }
                    } catch {
                        print("[Media] fragment_media lookup FAILED: \(fragmentID): \(error)")
                        print("[MediaDebug] fragment_media LOOKUP FAILED")
                        print("[MediaDebug] error: \(error)")
                        lastError = error
                    }
                }
                guard let mediaRef = ref, mediaRef.storagePath != nil else { continue }

                // 2. Skip work already completed by another path. A nil result
                // means the fragment row hasn't arrived in-session yet — end
                // quietly WITHOUT marking done; the fragment-side handler will
                // hydrate on arrival (P0-3, either order works).
                let alreadyLocal: Bool? = await MainActor.run {
                    guard let session = self.activeSession, session.isShared,
                          let uuid = UUID(uuidString: fragmentID),
                          session.fragments.contains(where: { $0.id == uuid }) else { return nil }
                    guard let frag = session.fragments.first(where: { $0.id == uuid }) else { return nil }
                    if let local = frag.mediaResourceName, !local.isEmpty,
                       FileManager.default.fileExists(atPath: local) { return true }
                    if let cached = RemoteMediaService.shared.cachedMediaURL(for: mediaRef, roomID: roomID) {
                        self.attachLocalMedia(localURL: cached, fragmentID: fragmentID, roomID: roomID)
                        return true
                    }
                    return false
                }
                guard let done = alreadyLocal else { return }
                if done {
                    await MainActor.run { self.hydratedMediaFragmentIDs.insert(key) }
                    return
                }

                // 3. Download via the existing signed-URL pipeline.
                // TEMPORARY diagnostic (no behavior change).
                print("[Media] Downloading: \(mediaRef.storagePath ?? "?")")
                print("[MediaDebug] Creating signed URL")
                print("[MediaDebug] bucket: moment-media")
                print("[MediaDebug] path: \(mediaRef.storagePath ?? "nil")")
                print("[MediaDebug] fragmentID: \(fragmentID)")
                print("[MediaDebug] roomID: \(roomID)")
                do {
                    let downloadedURL = try await RemoteMediaService.shared.localMediaURL(for: mediaRef, roomID: roomID)
                    let bytes = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int) ?? -1
                    print("[Media] Download success: \(bytes) bytes")
                    await MainActor.run {
                        self.attachLocalMedia(localURL: downloadedURL, fragmentID: fragmentID, roomID: roomID)
                        self.hydratedMediaFragmentIDs.insert(key)
                    }
                    return
                } catch {
                    print("[Media] Download FAILED: \(error)")
                    lastError = error
                }
            }

            print("[Media] Download FAILED: fragment \(fragmentID) room \(roomID) path \(ref?.storagePath ?? "unknown") error \(lastError?.localizedDescription ?? "media row never appeared") — giving up after \(delays.count + 1) attempts")
        }
    }

    /// Cancels all in-flight hydration and resets completion marks.
    /// Called whenever the active session ends so a rejoined session rehydrates
    /// cleanly and no task outlives its session.
    private func cancelMediaHydration() {
        for task in mediaHydrationTasks.values { task.cancel() }
        mediaHydrationTasks.removeAll()
        hydratedMediaFragmentIDs.removeAll()
    }

    private func handleRealtimeFragmentCreated(_ sharedFrag: SharedFragment) {
        print("[Realtime] Received fragment: \(sharedFrag.id) type: \(sharedFrag.type.rawValue)")
        // TEMPORARY diagnostic (no behavior change): expose the receive stage.
        print("[MediaDebug] Fragment received")
        print("[MediaDebug] fragmentID: \(sharedFrag.id)")
        print("[MediaDebug] roomID: \(sharedFrag.roomId)")
        print("[MediaDebug] fragmentType: \(sharedFrag.type.rawValue)")
        print("[MediaDebug] mediaReference: \(sharedFrag.mediaReference?.storagePath ?? "nil")")
        guard var current = activeSession, current.isShared else { return }
        guard let targetUUID = UUID(uuidString: sharedFrag.id) else { return }

        var domainFrag = sharedFrag.toFragment()

        // Stable placement for incoming remote fragments: resample only when
        // unset/default/colliding. Stored positions of survivors never change.
        let createdResolved = Fragment.resolveCoordinates(
            phi: domainFrag.phi,
            theta: domainFrag.theta,
            radiusFactor: domainFrag.radiusFactor,
            selfID: domainFrag.id,
            existing: current.fragments,
            epsilon: FragmentSphere.overlapEpsilon
        )
        domainFrag.phi = createdResolved.phi
        domainFrag.theta = createdResolved.theta
        domainFrag.radiusFactor = createdResolved.radiusFactor

        // Synchronous cache fast paths only. All downloading flows through
        // hydrateFragmentMedia below (bounded retry, deduplicated), so no
        // parallel fire-once download is started here.
        if domainFrag.mediaResourceName == nil {
            if let pending = pendingRemoteMedia[sharedFrag.id] {
                if let cached = RemoteMediaService.shared.cachedMediaURL(for: pending.media, roomID: pending.roomID) {
                    domainFrag.mediaResourceName = cached.path
                }
            } else if let mediaRef = sharedFrag.mediaReference {
                if let cached = RemoteMediaService.shared.cachedMediaURL(for: mediaRef, roomID: sharedFrag.roomId) {
                    domainFrag.mediaResourceName = cached.path
                }
            }
        }

        if let existingIdx = current.fragments.firstIndex(where: { $0.id == targetUUID }) {
            // Deduplicate & reconcile optimistic state
            print("🔄 [MomentManager] Reconciled optimistic fragment: \(sharedFrag.id) in room: \(sharedFrag.roomId)")
            var existing = current.fragments[existingIdx]
            existing.title = domainFrag.title
            if domainFrag.subtitle != nil { existing.subtitle = domainFrag.subtitle }
            if domainFrag.text != nil { existing.text = domainFrag.text }
            if domainFrag.location != nil { existing.location = domainFrag.location }
            if domainFrag.duration != nil { existing.duration = domainFrag.duration }
            if !domainFrag.audioWaveform.isEmpty { existing.audioWaveform = domainFrag.audioWaveform }
            if existing.mediaResourceName == nil && domainFrag.mediaResourceName != nil {
                existing.mediaResourceName = domainFrag.mediaResourceName
            }
            current.fragments[existingIdx] = existing
        } else {
            // Incoming remote fragment from another peer/participant
            print("📥 [MomentManager] Realtime INSERT: Appended remote fragment: \(sharedFrag.id) (type: \(sharedFrag.type.rawValue)) in room: \(sharedFrag.roomId)")
            current.fragments.append(domainFrag)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        self.activeSession = current
        self.persistSession(current)
        self.updateLiveActivity(session: current)

        // P0-1: realtime rows carry no embedded fragment_media. If this
        // non-note fragment is still media-less, hydrate via fragment_media
        // lookup with bounded backoff (deduped against a media-side task).
        // Notes legitimately have no media — never look them up.
        if sharedFrag.type != .note {
            let stillMissing: Bool = {
                guard let frag = current.fragments.first(where: { $0.id == targetUUID }) else { return false }
                guard let local = frag.mediaResourceName, !local.isEmpty else { return true }
                return !FileManager.default.fileExists(atPath: local)
            }()
            if stillMissing {
                hydrateFragmentMedia(fragmentID: sharedFrag.id, roomID: sharedFrag.roomId)
            }
        }

        if let room = current.room {
            self.persistSessionFragmentsPreservingAuthorship(current.fragments, roomId: room.id, knownAuthors: [sharedFrag.id: (authorId: sharedFrag.authorId, authorName: sharedFrag.authorName)])
        }
    }

    private func handleRealtimeFragmentUpdated(_ sharedFrag: SharedFragment) {
        guard var current = activeSession, current.isShared else { return }
        guard let targetUUID = UUID(uuidString: sharedFrag.id) else { return }

        var domainFrag = sharedFrag.toFragment()

        if let existingIdx = current.fragments.firstIndex(where: { $0.id == targetUUID }) {
            print("✏️ [MomentManager] Realtime UPDATE: Updated existing fragment: \(sharedFrag.id) in room: \(sharedFrag.roomId)")
            var existing = current.fragments[existingIdx]
            existing.title = domainFrag.title
            existing.subtitle = domainFrag.subtitle
            existing.text = domainFrag.text
            existing.location = domainFrag.location
            existing.duration = domainFrag.duration
            if !domainFrag.audioWaveform.isEmpty { existing.audioWaveform = domainFrag.audioWaveform }
            // Positions are session-stable: remote updates never move nodes.
            existing.gradientColors = domainFrag.gradientColors
            if existing.mediaResourceName == nil && domainFrag.mediaResourceName != nil {
                existing.mediaResourceName = domainFrag.mediaResourceName
            }
            current.fragments[existingIdx] = existing
        } else {
            print("📥 [MomentManager] Realtime UPDATE: Inserted missing fragment: \(sharedFrag.id) in room: \(sharedFrag.roomId)")
            let resolved = Fragment.resolveCoordinates(
                phi: domainFrag.phi,
                theta: domainFrag.theta,
                radiusFactor: domainFrag.radiusFactor,
                selfID: domainFrag.id,
                existing: current.fragments,
                epsilon: FragmentSphere.overlapEpsilon
            )
            domainFrag.phi = resolved.phi
            domainFrag.theta = resolved.theta
            domainFrag.radiusFactor = resolved.radiusFactor
            current.fragments.append(domainFrag)
        }

        self.activeSession = current
        self.persistSession(current)
        self.updateLiveActivity(session: current)

        if let room = current.room {
            self.persistSessionFragmentsPreservingAuthorship(current.fragments, roomId: room.id, knownAuthors: [sharedFrag.id: (authorId: sharedFrag.authorId, authorName: sharedFrag.authorName)])
        }
    }

    private func handleRealtimeFragmentDeleted(fragmentID: String, roomID: String) {
        guard var current = activeSession, current.isShared else { return }
        guard let targetUUID = UUID(uuidString: fragmentID) else { return }

        pendingRemoteMedia.removeValue(forKey: fragmentID)
        // Stop any in-flight hydration for the deleted fragment.
        let hydrationSuffix = "/\(fragmentID)"
        for key in mediaHydrationTasks.keys where key.hasSuffix(hydrationSuffix) {
            mediaHydrationTasks[key]?.cancel()
            mediaHydrationTasks[key] = nil
            hydratedMediaFragmentIDs.remove(key)
        }

        let initialCount = current.fragments.count
        current.fragments.removeAll(where: { $0.id == targetUUID })

        if current.fragments.count < initialCount {
            print("🗑️ [MomentManager] Realtime DELETE: Removed fragment: \(fragmentID) from room: \(roomID)")
            self.activeSession = current
            self.persistSession(current)
            self.updateLiveActivity(session: current)

            if let room = current.room {
                self.persistSessionFragmentsPreservingAuthorship(current.fragments, roomId: room.id)
            }
        }
    }

    private func handleRealtimeMediaCreated(media: SharedMediaReference, fragmentID: String, roomID: String) {
        pendingRemoteMedia[fragmentID] = (media, roomID)
        // P0-2/P0-3: route through the single hydration choke point so a
        // concurrent fragment-side lookup never double-downloads, and failures
        // retry with bounded backoff instead of being swallowed.
        hydrateFragmentMedia(fragmentID: fragmentID, roomID: roomID, knownMedia: media)
    }

    private func handleRealtimeMediaDeleted(storagePath: String, fragmentID: String, roomID: String) {
        guard var current = activeSession, current.isShared else { return }
        guard let targetUUID = UUID(uuidString: fragmentID) else { return }

        if let idx = current.fragments.firstIndex(where: { $0.id == targetUUID }) {
            if current.fragments[idx].mediaResourceName == storagePath {
                current.fragments[idx].mediaResourceName = nil
                self.activeSession = current
                self.persistSession(current)
            }
        }
    }

    private func handleRealtimeRoomChanged(_ updatedRoom: Room) {
        guard var current = activeSession, current.isShared, current.room?.id == updatedRoom.id else { return }

        print("🏠 [MomentManager] Room metadata updated via Realtime for room: \(updatedRoom.id)")

        if (updatedRoom.isArchived || updatedRoom.isEnded) && !current.isHost && !hasLeftSession {
            print("🏁 [MomentManager] Room was archived/ended remotely by host. Finalizing session as member.")
            let title = updatedRoom.finalTitle ?? updatedRoom.name
            let category = updatedRoom.finalCategory ?? "Life"
            finishSessionAsMember(finalTitle: title, category: category)
            return
        }

        current.room = updatedRoom
        self.activeSession = current
        self.persistSession(current)
    }

    private func handleRealtimeRoomDeleted(roomID: String) {
        guard let current = activeSession, current.isShared, current.room?.id == roomID else { return }
        print("🚨 [MomentManager] Room was deleted remotely: \(roomID). Leaving active session.")
        if !hasLeftSession {
            leaveSession()
        }
    }

    private func handleRealtimeMemberJoined(_ member: RoomMember) {
        guard var current = activeSession, current.isShared, var r = current.room else { return }
        r.memberCount = RoomManager.shared.members.count
        current.room = r
        self.activeSession = current
        self.persistSession(current)
    }

    private func handleRealtimeMemberChanged(_ member: RoomMember) {
        // Preserved for Identity phase
    }

    private func handleRealtimeMemberLeft(memberID: String, userID: String) {
        guard var current = activeSession, current.isShared, var r = current.room else { return }
        r.memberCount = RoomManager.shared.members.count
        current.room = r
        self.activeSession = current
        self.persistSession(current)
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
            roomID: session.room?.id,
            category: category
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
            room.isEnded = true
            room.finalTitle = finalTitle
            room.finalCategory = category

            // 1. Broadcast sessionEnded via local Multipeer
            MultipeerSyncService.shared.broadcastSessionEnded(finalTitle: finalTitle, finalCategory: category)

            // 2. Mark in Public Cloud Relay and update room
            Task {
                if room.backend != .supabase {
                    await CloudKitRoomRepository.shared.markRoomEndedPublicRelay(roomID: room.id, finalTitle: finalTitle)
                }
                try? await RoomManager.shared.updateRoom(room)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        clearPersistedSession()
        endLiveActivity()
        stopRemoteSyncObserver()
        stopSupabaseRealtimeObserver()
        cancelMediaHydration()
        if session.isShared, let room = session.room, room.backend == .supabase {
            RoomManager.shared.stopRealtime(roomID: room.id)
            if RoomManager.shared.currentRoom?.id == room.id {
                RoomManager.shared.currentRoom = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MultipeerSyncService.shared.stop()
        }
        return newCollection
    }

    /// Leaves an active shared moment session as a participant without deleting the room for others.
    func leaveSession() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        hasLeftSession = true

        let roomIDToLeave = activeSession?.room?.id
        let sessionIDToLeave = activeSession?.id

        // Clear Multipeer callbacks to prevent delayed auto-save
        MultipeerSyncService.shared.onSessionEnded = nil
        MultipeerSyncService.shared.onFragmentReceived = nil
        MultipeerSyncService.shared.onSessionStartDateReceived = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        clearPersistedSession()
        endLiveActivity()
        stopRemoteSyncObserver()
        stopSupabaseRealtimeObserver()
        cancelMediaHydration()
        MultipeerSyncService.shared.stop()

        // 1. Remove from local collections if it was ever added
        if let sessionID = sessionIDToLeave {
            collections.removeAll { $0.id == sessionID || (roomIDToLeave != nil && $0.roomID == roomIDToLeave) }
        } else if let rID = roomIDToLeave {
            collections.removeAll { $0.roomID == rID }
        }

        // 2. Remove from SwiftData if present
        if let ctx = modelContext {
            if let sessionID = sessionIDToLeave {
                let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.id == sessionID })
                if let matchings = try? ctx.fetch(descriptor) {
                    for item in matchings { ctx.delete(item) }
                }
            }
            if let rID = roomIDToLeave {
                let descriptor = FetchDescriptor<SDMoment>(predicate: #Predicate { $0.roomID == rID })
                if let matchings = try? ctx.fetch(descriptor) {
                    for item in matchings { ctx.delete(item) }
                }
            }
            try? ctx.save()
        }

        // 3. Remove room from RoomManager and local cache, and notify remote backend (Supabase / CloudKit)
        if let rID = roomIDToLeave {
            Task {
                await RoomManager.shared.leaveRoom(id: rID)
            }
        }
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
            roomID: session.room?.id,
            category: category
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
        stopRemoteSyncObserver()
        stopSupabaseRealtimeObserver()
        cancelMediaHydration()
        if session.isShared, let room = session.room, room.backend == .supabase {
            RoomManager.shared.stopRealtime(roomID: room.id)
            if RoomManager.shared.currentRoom?.id == room.id {
                RoomManager.shared.currentRoom = nil
            }
        }
        MultipeerSyncService.shared.stop()
        return newCollection
    }

    /// Discards the active session without saving
    func cancelSession() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let sessionToCancel = activeSession
        // Synchronously suppress the discarded room BEFORE publishing
        // `activeSession = nil`. MomentsView synthesizes visible moments from
        // (collections + rooms − activeRoomID − suppressed). Previously the room
        // was removed only inside an async `deleteRoom` Task, so the frame where
        // activeSession was already nil but `rooms` still contained the room let
        // a discarded moment flash in MomentsView. Suppression first closes that window.
        // Never inserts into `collections`/SwiftData here — discard must not save.
        if let session = sessionToCancel, session.isShared, let room = session.room {
            if room.isCurrentUserOwner {
                RoomManager.shared.removeRoomFromLocalState(id: room.id)
            } else if RoomManager.shared.currentRoom?.id == room.id {
                RoomManager.shared.currentRoom = nil
            }
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        clearPersistedSession()
        endLiveActivity()
        stopRemoteSyncObserver()
        stopSupabaseRealtimeObserver()
        cancelMediaHydration()
        MultipeerSyncService.shared.stop()

        if let session = sessionToCancel, session.isShared, let room = session.room {
            if room.backend == .supabase {
                RoomManager.shared.stopRealtime(roomID: room.id)
                if RoomManager.shared.currentRoom?.id == room.id {
                    RoomManager.shared.currentRoom = nil
                }
            }
            if room.isCurrentUserOwner {
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

    /// Resets ALL local Moment state for permanent account deletion.
    /// Local-only: performs no remote calls (the server already deleted
    /// everything). Purges SwiftData moments/fragments when a model context
    /// is available. Sign-out must NOT call this.
    func resetForAccountDeletion() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            activeSession = nil
            showEndMomentSheet = false
        }
        collections = []
        standaloneFragments = []
        recentlySavedMoment = nil
        hasLeftSession = false
        clearPersistedSession()
        endLiveActivity()
        stopRemoteSyncObserver()
        stopSupabaseRealtimeObserver()
        cancelMediaHydration()
        MultipeerSyncService.shared.stop()
        MultipeerSyncService.shared.onFragmentReceived = nil
        MultipeerSyncService.shared.onMemberReceived = nil
        MultipeerSyncService.shared.onSyncRequest = nil
        MultipeerSyncService.shared.onSessionEnded = nil
        MultipeerSyncService.shared.onSessionStartDateReceived = nil
        purgeSwiftData()
    }

    /// Deletes every locally stored moment and fragment (SDMoment cascades
    /// to SDMomentItem via its delete rule).
    private func purgeSwiftData() {
        guard let ctx = modelContext else { return }
        do {
            for moment in try ctx.fetch(FetchDescriptor<SDMoment>()) {
                ctx.delete(moment)
            }
            for fragment in try ctx.fetch(FetchDescriptor<SDFragment>()) {
                ctx.delete(fragment)
            }
            try ctx.save()
        } catch {
            print("⚠️ [MomentManager] Local data purge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Live Activity Helpers

    /// Requests a new Live Activity for the given session.
    private func startLiveActivity(session: MomentSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // End any stale activity before starting a new one
        endLiveActivity()

        let attributes = MomentActivityAttributes(
            startDate: session.startDate,
            sessionID: session.id.uuidString,
            isOwner: session.isHost
        )
        let initialState = MomentActivityAttributes.ContentState(
            fragmentCount: session.fragmentCount,
            location: session.location,
            isOwner: session.isHost
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
            location: session.location,
            isOwner: session.isHost
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
