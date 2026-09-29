//
//  SupabaseRealtimeCoordinator.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import Observation
import Supabase

/// Represents the connection state of the Supabase Realtime channel.
public enum RealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        self == .connected
    }
}

/// Strongly-typed domain events emitted by the Supabase Realtime layer.
///
/// Encapsulates persistent changes to rooms, members, fragments, and media metadata
/// without leaking Postgres or Supabase SDK details to consuming layers.
public enum SupabaseRealtimeEvent: Sendable, Equatable {
    case roomChanged(Room)
    case roomDeleted(roomID: String)
    case memberJoined(RoomMember)
    case memberChanged(RoomMember)
    case memberLeft(memberID: String, roomID: String, userID: String)
    case fragmentCreated(SharedFragment)
    case fragmentUpdated(SharedFragment)
    case fragmentDeleted(fragmentID: String, roomID: String, fragment: SharedFragment?)
    case fragmentMediaCreated(media: SharedMediaReference, fragmentID: String, roomID: String)
    case fragmentMediaDeleted(storagePath: String, fragmentID: String, roomID: String)
}

/// Errors specific to the Supabase Realtime coordinator.
public enum SupabaseRealtimeError: LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case invalidRoomID(String)
    case subscriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Authentication required to subscribe to Room Realtime."
        case .invalidRoomID(let id):
            return "Invalid room identifier: \(id)"
        case .subscriptionFailed(let msg):
            return "Realtime subscription failed: \(msg)"
        }
    }
}

/// Centralized coordinator managing scoped Supabase Realtime subscriptions for Shared Moments.
///
/// Subscribes strictly to the active room across `public.rooms`, `public.room_members`,
/// `public.shared_fragments`, and `public.fragment_media` using Postgres Changes.
/// Enforces deduplication, timestamp ordering, RLS compliance, and safe channel lifecycles.
@Observable
@MainActor
public final class SupabaseRealtimeCoordinator {
    public static let shared = SupabaseRealtimeCoordinator()

    // MARK: - Dependencies
    private let supabaseService: SupabaseService

    // MARK: - Observable State
    public private(set) var connectionState: RealtimeConnectionState = .disconnected
    public private(set) var activeRoomID: String? = nil

    // MARK: - Internal Realtime Handles
    private var channel: RealtimeChannelV2?
    private var subscriptions: [RealtimeSubscription] = []
    private var authObserverTask: Task<Void, Never>?

    /// Normalized room ID of a `start()` currently in flight.
    /// Prevents a second overlapping start for the same room from grabbing the
    /// cached channel mid-subscribe and registering its four postgres_changes
    /// callbacks after `subscribe()` (which the SDK silently drops).
    private var startingRoomID: String? = nil

    // MARK: - Multi-subscriber Event Stream
    private var continuations: [UUID: AsyncStream<SupabaseRealtimeEvent>.Continuation] = [:]

    // MARK: - Deduplication & Ordering Storage
    public struct RealtimeRecordKey: Hashable, Sendable {
        public let table: String
        public let recordID: String

        public init(table: String, recordID: String) {
            self.table = table
            self.recordID = recordID
        }
    }

    private struct DeduplicationKey: Hashable {
        let table: String
        let operation: String
        let recordID: String
        let timestamp: String
    }

    private var recentKeys = Set<DeduplicationKey>()
    private var recentKeysOrder: [DeduplicationKey] = []
    private let maxTrackedKeys = 500

    private var latestCommitTimestamps: [RealtimeRecordKey: Date] = [:]

    // MARK: - Initialization
    public init(supabaseService: SupabaseService? = nil) {
        self.supabaseService = supabaseService ?? SupabaseService.shared
        observeAuthLifecycle()
    }

    private var client: SupabaseClient {
        supabaseService.client
    }

    // MARK: - Public Event Stream
    /// Async stream of typed Realtime domain events for the active room.
    public var events: AsyncStream<SupabaseRealtimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Channel Lifecycle
    /// Starts a scoped Realtime subscription for the specified room.
    ///
    /// If already subscribed to the given room, this call is a safe no-op.
    /// If switching from another room, the existing subscription is cleanly stopped first.
    public func start(roomID: String) async throws {
        let trimmed = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SupabaseRealtimeError.invalidRoomID(roomID)
        }

        let normalizedRoomID = UUID(uuidString: trimmed)?.uuidString.lowercased() ?? trimmed.lowercased()

        print("[Realtime] Start requested: \(normalizedRoomID)")

        // 1. Prevent duplicate subscriptions to the same active room
        if activeRoomID == normalizedRoomID, channel != nil, connectionState == .connected {
            return
        }

        // 1b. Single-flight: a second overlapping start for the same room must
        // not create another channel — `client.channel()` returns the cached
        // channel, and registering on it mid-subscribe drops all four
        // postgres_changes callbacks (rooms, room_members, shared_fragments,
        // fragment_media). The in-flight start completes the subscription.
        if startingRoomID == normalizedRoomID {
            print("[Realtime] Start already in flight, skipping: \(normalizedRoomID)")
            return
        }

        // 2. Switching rooms: release any existing active channel
        if let existing = activeRoomID, existing != normalizedRoomID {
            await stop(roomID: existing)
        }

        // 3. Authenticated session guard (RLS requires auth.uid())
        guard supabaseService.isAuthenticated else {
            connectionState = .error("Authentication required")
            print("[Realtime] Start failed: \(normalizedRoomID) error=notAuthenticated")
            throw SupabaseRealtimeError.notAuthenticated
        }

        startingRoomID = normalizedRoomID
        defer {
            // Cleared on success, failure, and cancellation alike.
            if startingRoomID == normalizedRoomID {
                startingRoomID = nil
            }
        }

        activeRoomID = normalizedRoomID
        connectionState = .connecting
        resetDeduplicationState()

        // 4. Create scoped channel: "room:<room_id>"
        let channelName = "room:\(normalizedRoomID)"
        let newChannel = client.channel(channelName)

        // 5. Track channel subscription status
        let statusSub = newChannel.onStatusChange { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeRoomID == normalizedRoomID else { return }
                switch status {
                case .subscribed:
                    self.connectionState = .connected
                case .subscribing:
                    self.connectionState = .connecting
                case .unsubscribed, .unsubscribing:
                    if self.connectionState != .disconnected {
                        self.connectionState = .disconnected
                    }
                }
            }
        }
        subscriptions.append(statusSub)

        // 6. Scoped Postgres Changes: public.rooms (id = activeRoomID)
        let roomsSub = newChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "rooms",
            filter: .eq("id", value: normalizedRoomID)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleRoomsAction(action, forRoom: normalizedRoomID)
            }
        }
        subscriptions.append(roomsSub)

        // 7. Scoped Postgres Changes: public.room_members (room_id = activeRoomID)
        let membersSub = newChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "room_members",
            filter: .eq("room_id", value: normalizedRoomID)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleMembersAction(action, forRoom: normalizedRoomID)
            }
        }
        subscriptions.append(membersSub)

        // 8. Scoped Postgres Changes: public.shared_fragments (room_id = activeRoomID)
        let fragmentsSub = newChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "shared_fragments",
            filter: .eq("room_id", value: normalizedRoomID)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleFragmentsAction(action, forRoom: normalizedRoomID)
            }
        }
        subscriptions.append(fragmentsSub)

        // 9. Scoped Postgres Changes: public.fragment_media (room_id = activeRoomID)
        let mediaSub = newChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "fragment_media",
            filter: .eq("room_id", value: normalizedRoomID)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleMediaAction(action, forRoom: normalizedRoomID)
            }
        }
        subscriptions.append(mediaSub)

        self.channel = newChannel

        // 10. Subscribe asynchronously. Only this (first) start marks the
        // connection connected — an overlapping start returns via the
        // single-flight guard above and never touches connectionState.
        do {
            try await newChannel.subscribeWithError()
            self.connectionState = .connected
            print("[Realtime] Channel subscribed: \(normalizedRoomID)")
        } catch {
            self.connectionState = .error("Failed to connect: \(error.localizedDescription)")
            print("[Realtime] Start failed: \(normalizedRoomID) error=\(error)")
            throw SupabaseRealtimeError.subscriptionFailed(error.localizedDescription)
        }
    }

    /// Stops and releases the Realtime subscription for the specified room.
    public func stop(roomID: String? = nil) async {
        if let target = roomID {
            let normalized = UUID(uuidString: target)?.uuidString.lowercased() ?? target.lowercased()
            guard activeRoomID == normalized else { return }
        }

        // Cancel and clear subscriptions
        subscriptions.removeAll()

        if let ch = channel {
            self.channel = nil
            await ch.unsubscribe()
            await client.removeChannel(ch)
        }

        activeRoomID = nil
        connectionState = .disconnected
        resetDeduplicationState()
    }

    /// Unsubscribes and cleans up all active Realtime channels.
    public func stopAll() async {
        subscriptions.removeAll()
        if let ch = channel {
            self.channel = nil
            await ch.unsubscribe()
        }
        await client.removeAllChannels()
        activeRoomID = nil
        connectionState = .disconnected
        resetDeduplicationState()
    }

    // MARK: - Action Processing & Event Mapping

    private func handleRoomsAction(_ action: AnyAction, forRoom roomID: String) {
        switch action {
        case .insert(let ins):
            guard let room = try? ins.record.decode(as: DatabaseRoom.self).toDomain() else { return }
            if checkDeduplicationAndOrder(table: "rooms", op: "insert", id: room.id, timestamp: ins.commitTimestamp, recordTime: nil) {
                emit(.roomChanged(room))
            }

        case .update(let upd):
            guard let room = try? upd.record.decode(as: DatabaseRoom.self).toDomain() else { return }
            if checkDeduplicationAndOrder(table: "rooms", op: "update", id: room.id, timestamp: upd.commitTimestamp, recordTime: nil) {
                emit(.roomChanged(room))
            }

        case .delete(let del):
            let recordID = (try? del.oldRecord.decode(as: DatabaseRecordID.self))?.id.uuidString.lowercased() ?? roomID
            if checkDeduplicationAndOrder(table: "rooms", op: "delete", id: recordID, timestamp: del.commitTimestamp, recordTime: nil) {
                emit(.roomDeleted(roomID: recordID))
            }
        }
    }

    private func handleMembersAction(_ action: AnyAction, forRoom roomID: String) {
        switch action {
        case .insert(let ins):
            guard let member = try? ins.record.decode(as: RealtimeRoomMemberPayload.self).toDomain() else { return }
            if checkDeduplicationAndOrder(table: "room_members", op: "insert", id: member.id, timestamp: ins.commitTimestamp, recordTime: nil) {
                emit(.memberJoined(member))
            }

        case .update(let upd):
            guard let member = try? upd.record.decode(as: RealtimeRoomMemberPayload.self).toDomain() else { return }
            if checkDeduplicationAndOrder(table: "room_members", op: "update", id: member.id, timestamp: upd.commitTimestamp, recordTime: nil) {
                emit(.memberChanged(member))
            }

        case .delete(let del):
            let old = try? del.oldRecord.decode(as: RealtimeRoomMemberDeletePayload.self)
            let memberID = old?.id?.uuidString ?? ""
            let rID = old?.room_id?.uuidString.lowercased() ?? roomID
            let userID = old?.user_id?.uuidString ?? ""
            if checkDeduplicationAndOrder(table: "room_members", op: "delete", id: memberID, timestamp: del.commitTimestamp, recordTime: nil) {
                emit(.memberLeft(memberID: memberID, roomID: rID, userID: userID))
            }
        }
    }

    private func handleFragmentsAction(_ action: AnyAction, forRoom roomID: String) {
        switch action {
        case .insert(let ins):
            do {
                let frag = try ins.record.decode(as: DatabaseSharedFragment.self).toDomain()
                if checkDeduplicationAndOrder(table: "shared_fragments", op: "insert", id: frag.id, timestamp: ins.commitTimestamp, recordTime: ins.record["created_at"]?.stringValue) {
                    emit(.fragmentCreated(frag))
                }
            } catch {
                // Never silently drop a live fragment: a decode failure here is why
                // captures would not appear on other devices.
                print("❌ [Realtime] Dropping shared_fragments INSERT for room \(roomID): decode failed: \(error)")
            }

        case .update(let upd):
            do {
                let frag = try upd.record.decode(as: DatabaseSharedFragment.self).toDomain()
                if checkDeduplicationAndOrder(table: "shared_fragments", op: "update", id: frag.id, timestamp: upd.commitTimestamp, recordTime: upd.record["created_at"]?.stringValue) {
                    emit(.fragmentUpdated(frag))
                }
            } catch {
                print("❌ [Realtime] Dropping shared_fragments UPDATE for room \(roomID): decode failed: \(error)")
            }

        case .delete(let del):
            let oldDTO = try? del.oldRecord.decode(as: DatabaseSharedFragment.self)
            let fragID = oldDTO?.id.uuidString ?? (try? del.oldRecord.decode(as: DatabaseRecordID.self))?.id.uuidString ?? ""
            let rID = oldDTO?.room_id.uuidString.lowercased() ?? roomID
            if checkDeduplicationAndOrder(table: "shared_fragments", op: "delete", id: fragID, timestamp: del.commitTimestamp, recordTime: nil) {
                emit(.fragmentDeleted(fragmentID: fragID, roomID: rID, fragment: oldDTO?.toDomain()))
            }
        }
    }

    private func handleMediaAction(_ action: AnyAction, forRoom roomID: String) {
        switch action {
        case .insert(let ins):
            do {
                let mediaDTO = try ins.record.decode(as: DatabaseFragmentMedia.self)
                let ref = mediaDTO.toMediaReference()
                let fragID = mediaDTO.fragment_id?.uuidString ?? ""
                let rID = mediaDTO.room_id?.uuidString.lowercased() ?? roomID
                let dedupID = "\(fragID)_\(mediaDTO.storage_path)"
                if checkDeduplicationAndOrder(table: "fragment_media", op: "insert", id: dedupID, timestamp: ins.commitTimestamp, recordTime: nil) {
                    emit(.fragmentMediaCreated(media: ref, fragmentID: fragID, roomID: rID))
                }
            } catch {
                // A dropped media event leaves the fragment permanently imageless
                // on peers — log instead of swallowing.
                print("❌ [Realtime] Dropping fragment_media INSERT for room \(roomID): decode failed: \(error)")
            }

        case .update(let upd):
            do {
                let mediaDTO = try upd.record.decode(as: DatabaseFragmentMedia.self)
                let ref = mediaDTO.toMediaReference()
                let fragID = mediaDTO.fragment_id?.uuidString ?? ""
                let rID = mediaDTO.room_id?.uuidString.lowercased() ?? roomID
                let dedupID = "\(fragID)_\(mediaDTO.storage_path)"
                if checkDeduplicationAndOrder(table: "fragment_media", op: "update", id: dedupID, timestamp: upd.commitTimestamp, recordTime: nil) {
                    emit(.fragmentMediaCreated(media: ref, fragmentID: fragID, roomID: rID))
                }
            } catch {
                print("❌ [Realtime] Dropping fragment_media UPDATE for room \(roomID): decode failed: \(error)")
            }

        case .delete(let del):
            let oldDTO = try? del.oldRecord.decode(as: DatabaseFragmentMedia.self)
            let path = oldDTO?.storage_path ?? ""
            let fragID = oldDTO?.fragment_id?.uuidString ?? ""
            let rID = oldDTO?.room_id?.uuidString.lowercased() ?? roomID
            let dedupID = "\(fragID)_\(path)"
            if checkDeduplicationAndOrder(table: "fragment_media", op: "delete", id: dedupID, timestamp: del.commitTimestamp, recordTime: nil) {
                emit(.fragmentMediaDeleted(storagePath: path, fragmentID: fragID, roomID: rID))
            }
        }
    }

    // MARK: - Deduplication & Ordering Engine

    /// Validates that an event is neither a re-delivered duplicate nor a stale out-of-order frame.
    func checkDeduplicationAndOrder(
        table: String,
        op: String,
        id: String,
        timestamp: Date,
        recordTime: String?
    ) -> Bool {
        let recordKey = RealtimeRecordKey(table: table, recordID: id)

        // 1. Out-of-order check: do not process older commit timestamps for the same table record
        if let latest = latestCommitTimestamps[recordKey], timestamp < latest {
            return false
        }
        latestCommitTimestamps[recordKey] = timestamp

        // 2. Deduplication check: composite table + op + record ID + timestamp
        let timeKey = "\(timestamp.timeIntervalSince1970)_\(recordTime ?? "")"
        let key = DeduplicationKey(table: table, operation: op, recordID: id, timestamp: timeKey)

        if recentKeys.contains(key) {
            return false
        }

        recentKeys.insert(key)
        recentKeysOrder.append(key)
        if recentKeysOrder.count > maxTrackedKeys {
            let evicted = recentKeysOrder.removeFirst()
            recentKeys.remove(evicted)
        }

        return true
    }

    private func resetDeduplicationState() {
        recentKeys.removeAll()
        recentKeysOrder.removeAll()
        latestCommitTimestamps.removeAll()
    }

    // MARK: - Event Dispatcher
    public func emit(_ event: SupabaseRealtimeEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Auth Lifecycle Observation
    private func observeAuthLifecycle() {
        authObserverTask?.cancel()
        authObserverTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                guard !Task.isCancelled else { break }
                if event == .signedOut || session == nil {
                    if self.activeRoomID != nil {
                        await self.stop()
                    }
                }
            }
        }
    }
}

// MARK: - Realtime DTO Payloads

struct RealtimeRoomMemberPayload: Decodable, Sendable {
    let id: UUID
    let room_id: UUID
    let user_id: UUID
    let role: String
    let joined_at: String

    func toDomain() -> RoomMember {
        let memberRole: RoomRole = {
            switch role.lowercased() {
            case "owner": return .owner
            case "viewer": return .viewer
            default: return .member
            }
        }()

        return RoomMember(
            id: id.uuidString,
            roomId: room_id.uuidString,
            userId: user_id.uuidString,
            displayName: "Unknown",
            role: memberRole,
            joinedAt: SupabaseRoomRepository.parseISO8601(joined_at),
            avatarAssetURL: nil
        )
    }
}

struct RealtimeRoomMemberDeletePayload: Decodable, Sendable {
    let id: UUID?
    let room_id: UUID?
    let user_id: UUID?
}

struct DatabaseRecordID: Decodable, Sendable {
    let id: UUID
    let room_id: UUID?
}
