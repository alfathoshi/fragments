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

    private var container: CKContainer? {
        cloudKitService.container
    }

    // MARK: - Zone Identification

    /// Creates a deterministic custom `CKRecordZone.ID` for a Room.
    /// In Apple's sharing model, each collaborative Room lives in its own custom zone.
    public func zoneID(for roomID: String, ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "RoomZone_\(roomID)", ownerName: ownerName)
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
        guard let privateDB, let sharedDB else {
            throw CloudKitRoomError.offline
        }

        let zone = zoneID(for: room.id)
        let recordID = CKRecord.ID(recordName: room.id, zoneID: zone)

        // Determine if target database is private or shared
        let isOwned = (try? await privateDB.record(for: recordID)) != nil
        let targetDB = isOwned ? privateDB : sharedDB

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
        guard let privateDB else {
            return nil
        }

        let zone = zoneID(for: room.id)
        guard let shareName = room.shareRecordID else {
            // Check if share exists on the room record
            let roomRecordID = CKRecord.ID(recordName: room.id, zoneID: zone)
            if let record = try? await privateDB.record(for: roomRecordID),
               let shareRef = record.share {
                return try? await privateDB.record(for: shareRef.recordID) as? CKShare
            }
            return nil
        }

        let shareRecordID = CKRecord.ID(recordName: shareName, zoneID: zone)
        return try? await privateDB.record(for: shareRecordID) as? CKShare
    }

    /// Retrieves an existing `CKShare` for a Room, or attempts to provision it if not yet created.
    public func getOrCreateShare(for room: Room) async throws -> CKShare? {
        if let existing = try await fetchShare(for: room) {
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
            return try? await fetchShare(for: room)
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
        guard let roomRecord = try? await sharedDB.record(for: rootRecordID),
              let room = CloudKitRecordMapper.toRoom(from: roomRecord) else {
            throw CloudKitRoomError.roomNotFound(rootRecordID.recordName)
        }

        return (room, share)
    }

    // MARK: - Members CRUD

    /// Saves a `RoomMember` record to CloudKit.
    public func saveMember(_ member: RoomMember) async throws {
        guard let privateDB, let sharedDB else {
            throw CloudKitRoomError.offline
        }

        let zone = zoneID(for: member.roomId)
        let recordID = CKRecord.ID(recordName: member.id, zoneID: zone)

        let isOwned = (try? await privateDB.allRecordZones())?
            .contains(where: { $0.zoneID == zone }) ?? false
        let targetDB = isOwned ? privateDB : sharedDB

        let existingRecord = try? await targetDB.record(for: recordID)
        let record = CloudKitRecordMapper.toRecord(from: member, in: zone, existingRecord: existingRecord)
        _ = try await targetDB.save(record)
    }

    /// Fetches all members in a room.
    public func fetchMembers(roomID: String) async throws -> [RoomMember] {
        guard let privateDB, let sharedDB else {
            return []
        }

        let zone = zoneID(for: roomID)
        let isOwned = (try? await privateDB.allRecordZones())?
            .contains(where: { $0.zoneID == zone }) ?? false
        let targetDB = isOwned ? privateDB : sharedDB

        let predicate = NSPredicate(format: "\(CloudKitRecordKey.memberRoomId) == %@", roomID)
        let query = CKQuery(recordType: CloudKitRecordType.roomMember, predicate: predicate)

        do {
            let (matchResults, _) = try await targetDB.records(matching: query, inZoneWith: zone)
            var members: [RoomMember] = []
            for (_, result) in matchResults {
                if case .success(let record) = result,
                   let member = CloudKitRecordMapper.toRoomMember(from: record) {
                    members.append(member)
                }
            }
            return members.sorted { $0.joinedAt < $1.joinedAt }
        } catch {
            return []
        }
    }

    // MARK: - SharedFragment CRUD with Deterministic Ordering

    /// Saves a `SharedFragment` record to CloudKit in the room's custom zone.
    public func saveFragment(_ fragment: SharedFragment) async throws {
        guard let privateDB, let sharedDB else {
            throw CloudKitRoomError.offline
        }

        let zone = zoneID(for: fragment.roomId)
        let recordID = CKRecord.ID(recordName: fragment.id, zoneID: zone)

        let isOwned = (try? await privateDB.allRecordZones())?
            .contains(where: { $0.zoneID == zone }) ?? false
        let targetDB = isOwned ? privateDB : sharedDB

        let existingRecord = try? await targetDB.record(for: recordID)
        let record = CloudKitRecordMapper.toRecord(from: fragment, in: zone, existingRecord: existingRecord)
        _ = try await targetDB.save(record)
    }

    /// Fetches fragments for a room and enforces deterministic ordering:
    /// `createdAt ASC` with `id ASC` as tie-breaker.
    public func fetchFragments(roomID: String) async throws -> [SharedFragment] {
        guard let privateDB, let sharedDB else {
            return []
        }

        let zone = zoneID(for: roomID)
        let isOwned = (try? await privateDB.allRecordZones())?
            .contains(where: { $0.zoneID == zone }) ?? false
        let targetDB = isOwned ? privateDB : sharedDB

        let predicate = NSPredicate(format: "\(CloudKitRecordKey.fragmentRoomId) == %@", roomID)
        let query = CKQuery(recordType: CloudKitRecordType.sharedFragment, predicate: predicate)

        do {
            let (matchResults, _) = try await targetDB.records(matching: query, inZoneWith: zone)
            var fragments: [SharedFragment] = []
            for (_, result) in matchResults {
                if case .success(let record) = result,
                   let fragment = CloudKitRecordMapper.toSharedFragment(from: record) {
                    fragments.append(fragment)
                }
            }

            // Enforce deterministic collaborative ordering across all devices:
            // Primary sort: createdAt ASC; Secondary sort (tie-breaker): id ASC
            return Self.sortDeterministically(fragments)
        } catch {
            return []
        }
    }

    /// Deletes a shared fragment from CloudKit.
    public func deleteFragment(id: String, roomID: String) async throws {
        guard let privateDB, let sharedDB else {
            throw CloudKitRoomError.offline
        }

        let zone = zoneID(for: roomID)
        let recordID = CKRecord.ID(recordName: id, zoneID: zone)

        let isOwned = (try? await privateDB.allRecordZones())?
            .contains(where: { $0.zoneID == zone }) ?? false
        let targetDB = isOwned ? privateDB : sharedDB

        _ = try await targetDB.deleteRecord(withID: recordID)
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
