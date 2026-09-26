//
//  CloudKitRoomRepository.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit

/// Error types specific to CloudKit Room collaborative infrastructure.
public enum CloudKitRoomError: LocalizedError, Sendable {
    case unauthenticated
    case roomNotFound(String)
    case shareNotFound(String)
    case offline
    case operationFailed(String)
    case unauthorizedRole

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "No active iCloud account found. Please sign in to iCloud."
        case .roomNotFound(let id):
            return "Room '\(id)' could not be found."
        case .shareNotFound(let id):
            return "No CKShare record found for room '\(id)'."
        case .offline:
            return "Network unavailable. CloudKit operation could not be completed."
        case .operationFailed(let reason):
            return "CloudKit operation failed: \(reason)"
        case .unauthorizedRole:
            return "User role does not permit this action."
        }
    }
}

/// CloudKit infrastructure coordinating remote collaborative Room operations, zone management,
/// Apple native `CKShare` creation, and deterministic fragment queries.
public final class CloudKitRoomRepository: Sendable {
    public static let shared = CloudKitRoomRepository()

    private let cloudKitService: CloudKitService

    public init(cloudKitService: CloudKitService = .shared) {
        self.cloudKitService = cloudKitService
    }

    private var privateDB: CKDatabase? {
        cloudKitService.privateDatabase
    }

    private var sharedDB: CKDatabase? {
        cloudKitService.sharedDatabase
    }

    private var publicDB: CKDatabase? {
        cloudKitService.publicDatabase
    }

    private var container: CKContainer? {
        cloudKitService.container
    }

    // MARK: - Zone Identification & Dynamic Resolution

    // Cache for resolved zones to eliminate repetitive zone queries and ensure instant access
    private var resolvedZonesCache: [String: (zoneID: CKRecordZone.ID, database: CKDatabase)] = [:]
    private let cacheLock = NSLock()

    private func getCachedZone(for roomID: String) -> (zoneID: CKRecordZone.ID, database: CKDatabase)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return resolvedZonesCache[roomID]
    }

    private func setCachedZone(_ value: (zoneID: CKRecordZone.ID, database: CKDatabase), for roomID: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        resolvedZonesCache[roomID] = value
    }

    /// Creates a deterministic custom `CKRecordZone.ID` for a Room in private database.
    public func zoneID(for roomID: String, ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "RoomZone_\(roomID)", ownerName: ownerName)
    }

    /// Dynamically resolves the zone ID and database for a room.
    /// - For the owner: returns the custom zone in `privateDatabase`.
    /// - For a collaborator: finds the mounted zone in `sharedDatabase` (with host's ownerName).
    public func resolveZone(for roomID: String) async -> (zoneID: CKRecordZone.ID, database: CKDatabase)? {
        if let cached = getCachedZone(for: roomID) {
            return cached
        }

        guard let privateDB, let sharedDB else { return nil }

        let defaultZoneID = zoneID(for: roomID)

        // 1. Check if zone is owned by current user in private database
        if let privateZones = try? await privateDB.allRecordZones(),
           privateZones.contains(where: { $0.zoneID == defaultZoneID }) {
            let res = (defaultZoneID, privateDB)
            setCachedZone(res, for: roomID)
            return res
        }

        // 2. Look for mounted shared zone in sharedDatabase (with host's ownerName)
        let expectedName = "RoomZone_\(roomID)"
        if let sharedZones = try? await sharedDB.allRecordZones(),
           let matching = sharedZones.first(where: { $0.zoneID.zoneName == expectedName }) {
            let res = (matching.zoneID, sharedDB)
            setCachedZone(res, for: roomID)
            return res
        }

        // 3. Fallback: default to privateDB (owner fallback or offline)
        let fallback = (defaultZoneID, privateDB)
        return fallback
    }

    // MARK: - Public Room Share Lookup (Join by Code)

    /// Publishes a mapping from `roomID` to `shareURL` in the public database,
    /// enabling participants to join seamlessly by entering just the Room Code.
    public func publishShareLookup(roomID: String, shareURL: URL, name: String) async {
        guard let publicDB else { return }
        let shortCode = String(roomID.prefix(8)).uppercased()

        // 1. Save with full room ID
        let recordID = CKRecord.ID(recordName: "Lookup_\(roomID)")
        let record = CKRecord(recordType: "RoomLookup", recordID: recordID)
        record["shareURL"] = shareURL.absoluteString as CKRecordValue
        record["roomName"] = name as CKRecordValue
        record["roomID"] = roomID as CKRecordValue
        record["shortCode"] = shortCode as CKRecordValue
        _ = try? await publicDB.save(record)

        // 2. Also save by shortCode directly as recordName so NO query index is ever needed
        let shortRecordID = CKRecord.ID(recordName: "Lookup_Short_\(shortCode)")
        let shortRecord = CKRecord(recordType: "RoomLookup", recordID: shortRecordID)
        shortRecord["shareURL"] = shareURL.absoluteString as CKRecordValue
        shortRecord["roomName"] = name as CKRecordValue
        shortRecord["roomID"] = roomID as CKRecordValue
        shortRecord["shortCode"] = shortCode as CKRecordValue
        _ = try? await publicDB.save(shortRecord)
    }

    /// Looks up the `CKShare` URL for a given Room Code from the public database.
    public func lookupShareURL(for code: String) async -> URL? {
        guard let publicDB else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try direct fetch by full room ID (works with 0 query indexes)
        let recordID = CKRecord.ID(recordName: "Lookup_\(trimmed)")
        if let record = try? await publicDB.record(for: recordID),
           let urlString = record["shareURL"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // 2. Try direct fetch by shortCode record name (works with 0 query indexes)
        let shortCode = String(trimmed.prefix(8)).uppercased()
        let shortRecordID = CKRecord.ID(recordName: "Lookup_Short_\(shortCode)")
        if let record = try? await publicDB.record(for: shortRecordID),
           let urlString = record["shareURL"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        // 3. Fallback query by shortCode if index exists
        let predicate = NSPredicate(format: "shortCode == %@", shortCode)
        let query = CKQuery(recordType: "RoomLookup", predicate: predicate)
        if let (results, _) = try? await publicDB.records(matching: query),
           let firstMatch = results.first {
            if case .success(let record) = firstMatch.1,
               let urlString = record["shareURL"] as? String,
               let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }

    /// Resolves full room ID and room name from the public database using a room code,
    /// enabling fallback collaboration to link directly to the correct room.
    public func lookupRoomInfo(for code: String) async -> (id: String, name: String)? {
        guard let publicDB else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortCode = String(trimmed.prefix(8)).uppercased()

        // 1. Try Lookup_Short_<shortCode>
        let shortRecordID = CKRecord.ID(recordName: "Lookup_Short_\(shortCode)")
        if let record = try? await publicDB.record(for: shortRecordID) {
            let rID = (record["roomID"] as? String) ?? trimmed
            let rName = (record["roomName"] as? String) ?? "Shared Moment"
            return (rID, rName)
        }

        // 2. Try Lookup_<trimmed>
        let fullRecordID = CKRecord.ID(recordName: "Lookup_\(trimmed)")
        if let record = try? await publicDB.record(for: fullRecordID) {
            let rID = (record["roomID"] as? String) ?? trimmed
            let rName = (record["roomName"] as? String) ?? "Shared Moment"
            return (rID, rName)
        }

        return nil
    }

    /// Ensures the custom `CKRecordZone` exists in the owner's private database.
    public func ensureZoneExists(zoneID: CKRecordZone.ID) async throws {
        guard let privateDB else {
            throw CloudKitRoomError.offline
        }
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDB.save(zone)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // Zone already exists
            return
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw CloudKitRoomError.offline
        } catch {
            // If zone already exists, save returns an error or succeeds
            // Check if it's already there
            let zones = (try? await privateDB.allRecordZones()) ?? []
            if zones.contains(where: { $0.zoneID == zoneID }) {
                return
            }
            throw CloudKitRoomError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - Room CRUD

    /// Creates a new collaborative Room in a dedicated custom `CKRecordZone`, creates the root `CKRecord`,
    /// creates the initial `CKShare`, and registers the creator as `.owner`.
    /// - Parameters:
    ///   - name: The name of the room.
    ///   - emoji: An emoji representing the room.
    ///   - id: Optional predetermined room ID (used for optimistic room provisioning).
    ///   - name: The human-readable name of the room.
    ///   - emoji: An emoji representing the room.
    ///   - accentColorHex: Optional theme color hex.
    /// - Returns: A tuple containing the created `Room` and initialized `CKShare`.
    public func createRoom(
        id: String? = nil,
        name: String,
        emoji: String = "✨",
        accentColorHex: String? = nil
    ) async throws -> (Room, CKShare) {
        guard let currentIdentity = await UserIdentityService.shared.currentUserIdentity else {
            throw CloudKitRoomError.unauthenticated
        }

        let roomID = id ?? UUID().uuidString
        let roomZoneID = zoneID(for: roomID)

        // 1. Ensure dedicated custom zone exists in owner's private database
        try await ensureZoneExists(zoneID: roomZoneID)

        // 2. Prepare domain Room model
        var room = Room(
            id: roomID,
            name: name,
            emoji: emoji,
            createdAt: Date(),
            createdBy: currentIdentity.id,
            shareRecordID: nil,
            zoneName: roomZoneID.zoneName,
            isArchived: false,
            memberCount: 1,
            fragmentCount: 0,
            accentColorHex: accentColorHex
        )

        // 3. Map Room to CKRecord
        let roomRecord = CloudKitRecordMapper.toRecord(from: room, in: roomZoneID)

        // 4. Create native CKShare with roomRecord as root
        let share = CKShare(rootRecord: roomRecord)
        share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.alfathoshi.fragments.room" as CKRecordValue
        share.publicPermission = .readWrite // Allow anyone with link to collaborate

        // 5. Create initial RoomMember record for owner
        let ownerMember = RoomMember(
            roomId: roomID,
            userId: currentIdentity.id,
            displayName: currentIdentity.displayName,
            role: .owner,
            joinedAt: Date()
        )
        let ownerMemberRecord = CloudKitRecordMapper.toRecord(from: ownerMember, in: roomZoneID)

        guard let privateDB else {
            throw CloudKitRoomError.offline
        }

        // 6. Save roomRecord, share, and memberRecord atomically
        var savedShare = share
        let operation = CKModifyRecordsOperation(recordsToSave: [roomRecord, share, ownerMemberRecord], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.isAtomic = true

        operation.perRecordSaveBlock = { _, result in
            if case .success(let record) = result, let serverShare = record as? CKShare {
                savedShare = serverShare
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
            privateDB.add(operation)
        }

        // 7. Update room with share record identifier
        room.shareRecordID = savedShare.recordID.recordName

        setCachedZone((roomZoneID, privateDB), for: roomID)

        if let url = savedShare.url {
            Task {
                await self.publishShareLookup(roomID: roomID, shareURL: url, name: name)
            }
        }

        return (room, savedShare)
    }

    /// Fetches a Room record by its ID, checking `privateDatabase` first, then `sharedDatabase`.
    public func fetchRoom(id: String) async throws -> Room? {
        guard let privateDB, let sharedDB else {
            return nil
        }

        let privateZoneID = zoneID(for: id)
        let privateRecordID = CKRecord.ID(recordName: id, zoneID: privateZoneID)

        // 1. Try private database (owned rooms)
        do {
            let record = try await privateDB.record(for: privateRecordID)
            return CloudKitRecordMapper.toRoom(from: record)
        } catch let ckError as CKError where ckError.code == .unknownItem || ckError.code == .zoneNotFound {
            // Not in private database; proceed to search shared database
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw CloudKitRoomError.offline
        } catch {
            // Fallthrough to check shared database
        }

        // 2. Try shared database (accepted shared rooms)
        let sharedZones = (try? await sharedDB.allRecordZones()) ?? []
        for zone in sharedZones where zone.zoneID.zoneName.contains(id) {
            let sharedRecordID = CKRecord.ID(recordName: id, zoneID: zone.zoneID)
            if let record = try? await sharedDB.record(for: sharedRecordID) {
                return CloudKitRecordMapper.toRoom(from: record)
            }
        }

        return nil
    }

    /// Fetches all active rooms owned by the current user from `privateDatabase`.
    public func fetchOwnedRooms() async throws -> [Room] {
        guard let privateDB else {
            return []
        }

        let zones: [CKRecordZone]
        do {
            zones = try await privateDB.allRecordZones()
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw CloudKitRoomError.offline
        } catch {
            return []
        }

        var rooms: [Room] = []
        for zone in zones where zone.zoneID.zoneName.hasPrefix("RoomZone_") {
            let roomID = zone.zoneID.zoneName.replacingOccurrences(of: "RoomZone_", with: "")
            let recordID = CKRecord.ID(recordName: roomID, zoneID: zone.zoneID)
            if let record = try? await privateDB.record(for: recordID),
               let room = CloudKitRecordMapper.toRoom(from: record) {
                rooms.append(room)
            }
        }

        return rooms
    }

    /// Fetches all shared rooms accepted by the current user from `sharedDatabase`.
    public func fetchSharedRooms() async throws -> [Room] {
        guard let sharedDB else {
            return []
        }

        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw CloudKitRoomError.offline
        } catch {
            return []
        }

        var rooms: [Room] = []
        for zone in zones where zone.zoneID.zoneName.hasPrefix("RoomZone_") {
            let roomID = zone.zoneID.zoneName.replacingOccurrences(of: "RoomZone_", with: "")
            let recordID = CKRecord.ID(recordName: roomID, zoneID: zone.zoneID)
            if let record = try? await sharedDB.record(for: recordID),
               let room = CloudKitRecordMapper.toRoom(from: record) {
                rooms.append(room)
            }
        }

        return rooms
    }

    /// Fetches all rooms (owned and shared combined).
    public func fetchAllRooms() async throws -> [Room] {
        let owned = (try? await fetchOwnedRooms()) ?? []
        let shared = (try? await fetchSharedRooms()) ?? []

        // Deduplicate by room ID
        var seenIDs = Set<String>()
        var combined: [Room] = []

        for room in (owned + shared) {
            if !seenIDs.contains(room.id) {
                seenIDs.insert(room.id)
                combined.append(room)
            }
        }

        return combined
    }

    /// Updates mutable metadata of an existing Room in CloudKit.
    public func updateRoom(_ room: Room) async throws {
        guard let (zone, targetDB) = await resolveZone(for: room.id) else {
            throw CloudKitRoomError.offline
        }

        let recordID = CKRecord.ID(recordName: room.id, zoneID: zone)
        guard let existingRecord = try? await targetDB.record(for: recordID) else {
            throw CloudKitRoomError.roomNotFound(room.id)
        }

        let updatedRecord = CloudKitRecordMapper.toRecord(from: room, in: zone, existingRecord: existingRecord)
        _ = try await targetDB.save(updatedRecord)
    }

    /// Archives a room in CloudKit.
    public func archiveRoom(id: String) async throws {
        guard var room = try await fetchRoom(id: id) else {
            throw CloudKitRoomError.roomNotFound(id)
        }
        room.isArchived = true
        try await updateRoom(room)
    }

    /// Permanently deletes a Room and all associated data by deleting its dedicated `CKRecordZone`.
    public func deleteRoom(id: String) async throws {
        guard let privateDB else {
            throw CloudKitRoomError.offline
        }
        let zone = zoneID(for: id)
        _ = try await privateDB.deleteRecordZone(withID: zone)
    }

    // MARK: - Room Sharing (CKShare)

    /// Retrieves an existing `CKShare` for a Room.
    public func fetchShare(for room: Room) async throws -> CKShare? {
        guard let (zone, targetDB) = await resolveZone(for: room.id) else {
            return nil
        }

        guard let shareName = room.shareRecordID else {
            // Check if share exists on the room record
            let roomRecordID = CKRecord.ID(recordName: room.id, zoneID: zone)
            if let record = try? await targetDB.record(for: roomRecordID),
               let shareRef = record.share {
                return try? await targetDB.record(for: shareRef.recordID) as? CKShare
            }
            return nil
        }

        let shareRecordID = CKRecord.ID(recordName: shareName, zoneID: zone)
        return try? await targetDB.record(for: shareRecordID) as? CKShare
    }

    /// Retrieves an existing `CKShare` for a Room, or attempts to provision it if not yet created.
    public func getOrCreateShare(for room: Room) async throws -> CKShare? {
        if let existing = try await fetchShare(for: room) {
            if let url = existing.url {
                Task {
                    await self.publishShareLookup(roomID: room.id, shareURL: url, name: room.name)
                }
            }
            return existing
        }

        // If not found yet (e.g. background provisioning still in flight), try creating the room/share
        do {
            let (_, share) = try await createRoom(
                id: room.id,
                name: room.name,
                emoji: room.emoji,
                accentColorHex: room.accentColorHex
            )
            return share
        } catch {
            // Re-check once in case background task created it concurrently
            let recheck = try? await fetchShare(for: room)
            if let url = recheck?.url {
                Task {
                    await self.publishShareLookup(roomID: room.id, shareURL: url, name: room.name)
                }
            }
            return recheck
        }
    }

    /// Fetches the live list of CKShare participants (the cryptographic source of truth for authorization).
    public func fetchShareParticipants(for room: Room) async throws -> [CKShare.Participant] {
        guard let share = try await fetchShare(for: room) else {
            return []
        }
        return share.participants
    }

    /// Fetches metadata for an iCloud share invitation URL.
    public func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        guard let container else {
            throw CloudKitRoomError.offline
        }
        do {
            return try await container.shareMetadata(for: url)
        } catch let ckError as CKError where ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            throw CloudKitRoomError.offline
        } catch {
            throw CloudKitRoomError.operationFailed("Could not fetch share metadata: \(error.localizedDescription)")
        }
    }

    /// Accepts a CloudKit share invitation using its metadata.
    public func acceptShare(metadata: CKShare.Metadata) async throws -> CKShare {
        guard let container else {
            throw CloudKitRoomError.offline
        }
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var acceptedShare: CKShare?
            operation.perShareResultBlock = { _, result in
                switch result {
                case .success(let share):
                    acceptedShare = share
                case .failure:
                    break
                }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    if let share = acceptedShare {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: CloudKitRoomError.operationFailed("Share accepted, but CKShare object was missing."))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// Accepts a share invitation URL, adds the shared zone to sharedCloudDatabase, and resolves the Room.
    public func acceptShare(with url: URL) async throws -> (Room, CKShare) {
        guard let sharedDB else {
            throw CloudKitRoomError.offline
        }

        let metadata = try await fetchShareMetadata(for: url)
        let share = try await acceptShare(metadata: metadata)

        let rootRecordID = metadata.rootRecordID
        // Cache the shared zone ID immediately so queries hit the correct host-owned zone!
        setCachedZone((rootRecordID.zoneID, sharedDB), for: rootRecordID.recordName)

        guard let roomRecord = try? await sharedDB.record(for: rootRecordID),
              let room = CloudKitRecordMapper.toRoom(from: roomRecord) else {
            throw CloudKitRoomError.roomNotFound(rootRecordID.recordName)
        }

        return (room, share)
    }

    // MARK: - Members CRUD

    /// Saves a `RoomMember` record to CloudKit.
    public func saveMember(_ member: RoomMember) async throws {
        // 1. Dual-write to Public Cloud Relay
        Task {
            await self.publishMemberPublicRelay(member)
        }

        guard let (zone, targetDB) = await resolveZone(for: member.roomId) else {
            throw CloudKitRoomError.offline
        }

        let recordID = CKRecord.ID(recordName: member.id, zoneID: zone)
        let existingRecord = try? await targetDB.record(for: recordID)
        let record = CloudKitRecordMapper.toRecord(from: member, in: zone, existingRecord: existingRecord)
        _ = try await targetDB.save(record)
    }

    /// Fetches all members in a room across custom zone and public relay.
    public func fetchMembers(roomID: String) async throws -> [RoomMember] {
        var membersByID: [String: RoomMember] = [:]

        // 1. Fetch from custom zone (if mounted/available)
        if let (zone, targetDB) = await resolveZone(for: roomID) {
            let query = CKQuery(recordType: CloudKitRecordType.roomMember, predicate: NSPredicate(value: true))
            if let (matchResults, _) = try? await targetDB.records(matching: query, inZoneWith: zone) {
                for (_, result) in matchResults {
                    if case .success(let record) = result,
                       let member = CloudKitRecordMapper.toRoomMember(from: record) {
                        if member.roomId == roomID {
                            membersByID[member.id] = member
                        }
                    }
                }
            }
        }

        // 2. Fetch from Public Cloud Relay (cross-account and development fallback)
        let relayMembers = await fetchMembersPublicRelay(roomID: roomID)
        for member in relayMembers {
            if membersByID[member.id] == nil {
                membersByID[member.id] = member
            }
        }

        return Array(membersByID.values).sorted { $0.joinedAt < $1.joinedAt }
    }

    // MARK: - SharedFragment CRUD with Deterministic Ordering

    /// Saves a `SharedFragment` record to CloudKit in the room's custom zone and public relay.
    public func saveFragment(_ fragment: SharedFragment) async throws {
        // 1. Dual-write to Public Cloud Relay for instant cross-device delivery
        Task {
            await self.publishFragmentPublicRelay(fragment)
        }

        guard let (zone, targetDB) = await resolveZone(for: fragment.roomId) else {
            throw CloudKitRoomError.offline
        }

        let recordID = CKRecord.ID(recordName: fragment.id, zoneID: zone)
        let existingRecord = try? await targetDB.record(for: recordID)
        let record = CloudKitRecordMapper.toRecord(from: fragment, in: zone, existingRecord: existingRecord)
        _ = try await targetDB.save(record)
    }

    /// Fetches fragments for a room across custom zone and public relay, enforcing deterministic ordering.
    public func fetchFragments(roomID: String) async throws -> [SharedFragment] {
        var fragmentsByID: [String: SharedFragment] = [:]

        // 1. Fetch from custom zone (if available)
        if let (zone, targetDB) = await resolveZone(for: roomID) {
            let query = CKQuery(recordType: CloudKitRecordType.sharedFragment, predicate: NSPredicate(value: true))
            if let (matchResults, _) = try? await targetDB.records(matching: query, inZoneWith: zone) {
                for (_, result) in matchResults {
                    if case .success(let record) = result,
                       let fragment = CloudKitRecordMapper.toSharedFragment(from: record) {
                        if fragment.roomId == roomID {
                            fragmentsByID[fragment.id] = fragment
                        }
                    }
                }
            }
        }

        // 2. Fetch from Public Cloud Relay (universal cross-account fallback)
        let relayFragments = await fetchFragmentsPublicRelay(roomID: roomID)
        for frag in relayFragments {
            if fragmentsByID[frag.id] == nil {
                fragmentsByID[frag.id] = frag
            }
        }

        return Self.sortDeterministically(Array(fragmentsByID.values))
    }

    // MARK: - Public Cloud Relay Implementation

    /// Publishes a fragment to the CloudKit public database relay using a direct manifest record,
    /// enabling real-time collaboration across devices with identical or unauthenticated accounts.
    public func publishFragmentPublicRelay(_ fragment: SharedFragment, assetURL: URL? = nil) async {
        guard let publicDB else { return }

        // 1. Save media asset if present to PublicMedia_<id>
        if let assetURL = assetURL ?? fragment.mediaReference?.localFileURL,
           FileManager.default.fileExists(atPath: assetURL.path) {
            let mediaRecordID = CKRecord.ID(recordName: "PublicMedia_\(fragment.id)")
            let mediaRecord = CKRecord(recordType: "PublicMedia", recordID: mediaRecordID)
            mediaRecord["mediaAsset"] = CKAsset(fileURL: assetURL)
            mediaRecord["fileExtension"] = assetURL.pathExtension as CKRecordValue
            mediaRecord["fragmentID"] = fragment.id as CKRecordValue
            _ = try? await publicDB.save(mediaRecord)
        }

        // 2. Fetch or create RoomManifest_<roomID>
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(fragment.roomId)")
        let manifestRecord = (try? await publicDB.record(for: manifestID)) ?? CKRecord(recordType: "RoomManifest", recordID: manifestID)

        var existingJSONs = (manifestRecord["fragmentJSONs"] as? [String]) ?? []
        var existingIDs = (manifestRecord["fragmentIDs"] as? [String]) ?? []

        if !existingIDs.contains(fragment.id) {
            if let data = try? JSONEncoder().encode(fragment),
               let jsonStr = String(data: data, encoding: .utf8) {
                existingIDs.append(fragment.id)
                existingJSONs.append(jsonStr)

                manifestRecord["fragmentIDs"] = existingIDs as CKRecordValue
                manifestRecord["fragmentJSONs"] = existingJSONs as CKRecordValue
                manifestRecord["updatedAt"] = Date() as CKRecordValue
                _ = try? await publicDB.save(manifestRecord)
            }
        }
    }

    /// Fetches all fragments published to the public relay for a room without requiring any query indexes.
    public func fetchFragmentsPublicRelay(roomID: String) async -> [SharedFragment] {
        guard let publicDB else { return [] }
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(roomID)")

        guard let record = try? await publicDB.record(for: manifestID),
              let jsonStrings = record["fragmentJSONs"] as? [String] else {
            return []
        }

        var results: [SharedFragment] = []
        for jsonStr in jsonStrings {
            if let data = jsonStr.data(using: .utf8),
               var frag = try? JSONDecoder().decode(SharedFragment.self, from: data) {
                // If media was not resolved yet, check PublicMedia
                if frag.mediaReference?.localFileURL == nil && (frag.type == .photo || frag.type == .video || frag.type == .audio) {
                    let mediaRecordID = CKRecord.ID(recordName: "PublicMedia_\(frag.id)")
                    if let mediaRecord = try? await publicDB.record(for: mediaRecordID),
                       let asset = mediaRecord["mediaAsset"] as? CKAsset,
                       let assetURL = asset.fileURL {
                        var ref = frag.mediaReference ?? SharedMediaReference()
                        ref.localFileURL = assetURL
                        frag.mediaReference = ref
                    }
                }
                results.append(frag)
            }
        }
        return results
    }

    /// Publishes a member to the public relay for a room.
    public func publishMemberPublicRelay(_ member: RoomMember) async {
        guard let publicDB else { return }
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(member.roomId)")
        let manifestRecord = (try? await publicDB.record(for: manifestID)) ?? CKRecord(recordType: "RoomManifest", recordID: manifestID)

        var existingJSONs = (manifestRecord["memberJSONs"] as? [String]) ?? []
        var existingIDs = (manifestRecord["memberIDs"] as? [String]) ?? []

        if !existingIDs.contains(member.id) {
            if let data = try? JSONEncoder().encode(member),
               let jsonStr = String(data: data, encoding: .utf8) {
                existingIDs.append(member.id)
                existingJSONs.append(jsonStr)

                manifestRecord["memberIDs"] = existingIDs as CKRecordValue
                manifestRecord["memberJSONs"] = existingJSONs as CKRecordValue
                manifestRecord["updatedAt"] = Date() as CKRecordValue
                _ = try? await publicDB.save(manifestRecord)
            }
        }
    }

    /// Fetches all members published to the public relay for a room.
    public func fetchMembersPublicRelay(roomID: String) async -> [RoomMember] {
        guard let publicDB else { return [] }
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(roomID)")

        guard let record = try? await publicDB.record(for: manifestID),
              let jsonStrings = record["memberJSONs"] as? [String] else {
            return []
        }

        var results: [RoomMember] = []
        for jsonStr in jsonStrings {
            if let data = jsonStr.data(using: .utf8),
               let member = try? JSONDecoder().decode(RoomMember.self, from: data) {
                results.append(member)
            }
        }
        return results
    }

    /// Deletes a shared fragment from CloudKit.
    public func deleteFragment(id: String, roomID: String) async throws {
        guard let (zone, targetDB) = await resolveZone(for: roomID) else {
            throw CloudKitRoomError.offline
        }

        let recordID = CKRecord.ID(recordName: id, zoneID: zone)
        _ = try await targetDB.deleteRecord(withID: recordID)
    }

    /// Marks a room as ended in the Public Cloud Relay so collaborators learn immediately that the session concluded.
    public func markRoomEndedPublicRelay(roomID: String, finalTitle: String) async {
        guard let publicDB else { return }
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(roomID)")
        let manifestRecord = (try? await publicDB.record(for: manifestID)) ?? CKRecord(recordType: "RoomManifest", recordID: manifestID)
        manifestRecord["isEnded"] = 1 as CKRecordValue
        manifestRecord["finalTitle"] = finalTitle as CKRecordValue
        manifestRecord["updatedAt"] = Date() as CKRecordValue
        _ = try? await publicDB.save(manifestRecord)
    }

    /// Checks if a room has been marked as ended in Public Cloud Relay.
    public func checkRoomEndedPublicRelay(roomID: String) async -> (isEnded: Bool, finalTitle: String?) {
        guard let publicDB else { return (false, nil) }
        let manifestID = CKRecord.ID(recordName: "RoomManifest_\(roomID)")
        guard let manifestRecord = try? await publicDB.record(for: manifestID) else {
            return (false, nil)
        }
        let isEnded = (manifestRecord["isEnded"] as? Int64 ?? 0) == 1 || (manifestRecord["isEnded"] as? Int ?? 0) == 1
        let title = manifestRecord["finalTitle"] as? String
        return (isEnded, title)
    }

    // MARK: - Deterministic Sorting Utility

    /// Sorts an array of SharedFragments deterministically:
    /// Primary key: `createdAt` ASC.
    /// Tie-breaker key: `id` ASC.
    public static func sortDeterministically(_ fragments: [SharedFragment]) -> [SharedFragment] {
        fragments.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
