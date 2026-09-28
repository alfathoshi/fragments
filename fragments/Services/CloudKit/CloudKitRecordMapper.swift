//
//  CloudKitRecordMapper.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit
import CoreGraphics

// MARK: - CloudKit Record Types

public enum CloudKitRecordType {
    public static let room = "Room"
    public static let roomMember = "RoomMember"
    public static let sharedFragment = "SharedFragment"
}

// MARK: - CloudKit Record Keys

public enum CloudKitRecordKey {
    // Room Keys
    public static let roomName = "name"
    public static let roomEmoji = "emoji"
    public static let roomCreatedAt = "createdAt"
    public static let roomCreatedBy = "createdBy"
    public static let roomShareRecordID = "shareRecordID"
    public static let roomZoneName = "zoneName"
    public static let roomIsArchived = "isArchived"
    public static let roomMemberCount = "memberCount"
    public static let roomFragmentCount = "fragmentCount"
    public static let roomAccentColorHex = "accentColorHex"

    // RoomMember Keys
    public static let memberRoom = "roomReference"
    public static let memberRoomId = "roomId"
    public static let memberUserId = "userId"
    public static let memberDisplayName = "displayName"
    public static let memberRole = "role"
    public static let memberJoinedAt = "joinedAt"
    public static let memberAvatarAsset = "avatarAsset"

    // SharedFragment Keys
    public static let fragmentRoom = "roomReference"
    public static let fragmentRoomId = "roomId"
    public static let fragmentAuthorId = "authorId"
    public static let fragmentAuthorName = "authorName"
    public static let fragmentType = "type"
    public static let fragmentCreatedAt = "createdAt"
    public static let fragmentTitle = "title"
    public static let fragmentSubtitle = "subtitle"
    public static let fragmentText = "text"
    public static let fragmentMediaAsset = "mediaAsset"
    public static let fragmentMediaSymbol = "mediaSymbol"
    public static let fragmentLocation = "location"
    public static let fragmentDuration = "duration"
    public static let fragmentWaveform = "waveform"
    public static let fragmentAccentColorHex = "accentColorHex"
    public static let fragmentPhi = "phi"
    public static let fragmentTheta = "theta"
    public static let fragmentRadiusFactor = "radiusFactor"
}

// MARK: - CloudKitRecordMapper

/// Pure mapper converting between domain models (Room, RoomMember, SharedFragment) and native `CKRecord` objects.
public struct CloudKitRecordMapper {

    // MARK: - Room Mapping

    /// Converts a `Room` domain model to a `CKRecord`.
    /// - Parameters:
    ///   - room: The room model to convert.
    ///   - zoneID: Optional target `CKRecordZone.ID` (defaults to default zone).
    ///   - existingRecord: Optional existing record to update in-place preserving system fields/change tags.
    /// - Returns: A configured `CKRecord`.
    public static func toRecord(
        from room: Room,
        in zoneID: CKRecordZone.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordID: CKRecord.ID
        if let existing = existingRecord {
            recordID = existing.recordID
        } else if let zoneID = zoneID {
            recordID = CKRecord.ID(recordName: room.id, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: room.id)
        }

        let record = existingRecord ?? CKRecord(recordType: CloudKitRecordType.room, recordID: recordID)

        record[CloudKitRecordKey.roomName] = room.name as CKRecordValue
        record[CloudKitRecordKey.roomEmoji] = room.emoji as CKRecordValue
        record[CloudKitRecordKey.roomCreatedAt] = room.createdAt as CKRecordValue
        record[CloudKitRecordKey.roomCreatedBy] = room.createdBy as CKRecordValue
        record[CloudKitRecordKey.roomIsArchived] = (room.isArchived ? 1 : 0) as CKRecordValue
        record[CloudKitRecordKey.roomMemberCount] = room.memberCount as CKRecordValue
        record[CloudKitRecordKey.roomFragmentCount] = room.fragmentCount as CKRecordValue

        if let shareID = room.shareRecordID {
            record[CloudKitRecordKey.roomShareRecordID] = shareID as CKRecordValue
        } else {
            record[CloudKitRecordKey.roomShareRecordID] = nil
        }

        if let zoneName = room.zoneName {
            record[CloudKitRecordKey.roomZoneName] = zoneName as CKRecordValue
        } else {
            record[CloudKitRecordKey.roomZoneName] = nil
        }

        if let accentHex = room.accentColorHex {
            record[CloudKitRecordKey.roomAccentColorHex] = accentHex as CKRecordValue
        } else {
            record[CloudKitRecordKey.roomAccentColorHex] = nil
        }

        return record
    }

    /// Converts a `CKRecord` into a `Room` domain model.
    /// - Parameter record: The CloudKit record.
    /// - Returns: A decoded `Room`, or `nil` if essential fields are missing.
    public static func toRoom(from record: CKRecord) -> Room? {
        guard let name = record[CloudKitRecordKey.roomName] as? String,
              let createdBy = record[CloudKitRecordKey.roomCreatedBy] as? String else {
            return nil
        }

        let id = record.recordID.recordName
        let emoji = (record[CloudKitRecordKey.roomEmoji] as? String) ?? "✨"
        let createdAt = (record[CloudKitRecordKey.roomCreatedAt] as? Date) ?? record.creationDate ?? Date()
        let shareRecordID = record[CloudKitRecordKey.roomShareRecordID] as? String
        let zoneName = (record[CloudKitRecordKey.roomZoneName] as? String) ?? record.recordID.zoneID.zoneName
        let isArchived = ((record[CloudKitRecordKey.roomIsArchived] as? Int64) ?? 0) != 0
        let memberCount = Int((record[CloudKitRecordKey.roomMemberCount] as? Int64) ?? 1)
        let fragmentCount = Int((record[CloudKitRecordKey.roomFragmentCount] as? Int64) ?? 0)
        let accentColorHex = record[CloudKitRecordKey.roomAccentColorHex] as? String

        return Room(
            id: id,
            name: name,
            emoji: emoji,
            createdAt: createdAt,
            createdBy: createdBy,
            shareRecordID: shareRecordID,
            zoneName: zoneName,
            isArchived: isArchived,
            memberCount: memberCount,
            fragmentCount: fragmentCount,
            accentColorHex: accentColorHex
        )
    }

    // MARK: - RoomMember Mapping

    /// Converts a `RoomMember` domain model to a `CKRecord`.
    /// Establishes parent reference and cascading deletion (`.deleteSelf`) tied to the parent `Room`.
    /// - Parameters:
    ///   - member: The room member model.
    ///   - zoneID: Optional target `CKRecordZone.ID`.
    ///   - existingRecord: Optional existing record to update in-place.
    /// - Returns: A configured `CKRecord`.
    public static func toRecord(
        from member: RoomMember,
        in zoneID: CKRecordZone.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordID: CKRecord.ID
        if let existing = existingRecord {
            recordID = existing.recordID
        } else if let zoneID = zoneID {
            recordID = CKRecord.ID(recordName: member.id, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: member.id)
        }

        let record = existingRecord ?? CKRecord(recordType: CloudKitRecordType.roomMember, recordID: recordID)

        let roomRecordID: CKRecord.ID
        if let zoneID = zoneID {
            roomRecordID = CKRecord.ID(recordName: member.roomId, zoneID: zoneID)
        } else {
            roomRecordID = CKRecord.ID(recordName: member.roomId)
        }

        // Establish CloudKit parent-child hierarchy for sharing & cascade deletion
        record.parent = CKRecord.Reference(recordID: roomRecordID, action: .none)
        record[CloudKitRecordKey.memberRoom] = CKRecord.Reference(recordID: roomRecordID, action: .deleteSelf)
        record[CloudKitRecordKey.memberRoomId] = member.roomId as CKRecordValue
        record[CloudKitRecordKey.memberUserId] = member.userId as CKRecordValue
        record[CloudKitRecordKey.memberDisplayName] = member.displayName as CKRecordValue
        record[CloudKitRecordKey.memberRole] = member.role.rawValue as CKRecordValue
        record[CloudKitRecordKey.memberJoinedAt] = member.joinedAt as CKRecordValue

        if let avatarURL = member.avatarAssetURL, FileManager.default.fileExists(atPath: avatarURL.path) {
            record[CloudKitRecordKey.memberAvatarAsset] = CKAsset(fileURL: avatarURL)
        }

        return record
    }

    /// Converts a `CKRecord` into a `RoomMember` domain model.
    /// - Parameter record: The CloudKit record.
    /// - Returns: A decoded `RoomMember`, or `nil` if essential fields are missing.
    public static func toRoomMember(from record: CKRecord) -> RoomMember? {
        let roomId: String
        if let roomRef = record[CloudKitRecordKey.memberRoom] as? CKRecord.Reference {
            roomId = roomRef.recordID.recordName
        } else if let directRoomId = record[CloudKitRecordKey.memberRoomId] as? String {
            roomId = directRoomId
        } else {
            return nil
        }

        guard let userId = record[CloudKitRecordKey.memberUserId] as? String,
              let displayName = record[CloudKitRecordKey.memberDisplayName] as? String else {
            return nil
        }

        let id = record.recordID.recordName
        let roleRaw = (record[CloudKitRecordKey.memberRole] as? String) ?? RoomRole.member.rawValue
        let role = RoomRole(rawValue: roleRaw) ?? .member
        let joinedAt = (record[CloudKitRecordKey.memberJoinedAt] as? Date) ?? record.creationDate ?? Date()

        let avatarAsset = record[CloudKitRecordKey.memberAvatarAsset] as? CKAsset
        let avatarURL = avatarAsset?.fileURL

        return RoomMember(
            id: id,
            roomId: roomId,
            userId: userId,
            displayName: displayName,
            role: role,
            joinedAt: joinedAt,
            avatarAssetURL: avatarURL
        )
    }

    // MARK: - SharedFragment Mapping

    /// Converts a `SharedFragment` domain model to a `CKRecord`.
    /// Sets parent reference and cascading deletion (`.deleteSelf`) tied to the parent `Room`.
    /// - Parameters:
    ///   - fragment: The shared fragment model.
    ///   - zoneID: Optional target `CKRecordZone.ID`.
    ///   - assetFileURL: Optional local file URL for media to attach as a `CKAsset`.
    ///   - existingRecord: Optional existing record to update in-place.
    /// - Returns: A configured `CKRecord`.
    public static func toRecord(
        from fragment: SharedFragment,
        in zoneID: CKRecordZone.ID? = nil,
        assetFileURL: URL? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordID: CKRecord.ID
        if let existing = existingRecord {
            recordID = existing.recordID
        } else if let zoneID = zoneID {
            recordID = CKRecord.ID(recordName: fragment.id, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: fragment.id)
        }

        let record = existingRecord ?? CKRecord(recordType: CloudKitRecordType.sharedFragment, recordID: recordID)

        let roomRecordID: CKRecord.ID
        if let zoneID = zoneID {
            roomRecordID = CKRecord.ID(recordName: fragment.roomId, zoneID: zoneID)
        } else {
            roomRecordID = CKRecord.ID(recordName: fragment.roomId)
        }

        // Establish parent-child hierarchy for sharing & cascade deletion
        record.parent = CKRecord.Reference(recordID: roomRecordID, action: .none)
        record[CloudKitRecordKey.fragmentRoom] = CKRecord.Reference(recordID: roomRecordID, action: .deleteSelf)
        record[CloudKitRecordKey.fragmentRoomId] = fragment.roomId as CKRecordValue
        record[CloudKitRecordKey.fragmentAuthorId] = fragment.authorId as CKRecordValue
        record[CloudKitRecordKey.fragmentAuthorName] = fragment.authorName as CKRecordValue
        record[CloudKitRecordKey.fragmentType] = fragment.type.rawValue as CKRecordValue
        record[CloudKitRecordKey.fragmentCreatedAt] = fragment.createdAt as CKRecordValue
        record[CloudKitRecordKey.fragmentTitle] = fragment.title as CKRecordValue

        if let subtitle = fragment.subtitle {
            record[CloudKitRecordKey.fragmentSubtitle] = subtitle as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentSubtitle] = nil
        }

        if let text = fragment.text {
            record[CloudKitRecordKey.fragmentText] = text as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentText] = nil
        }

        if let symbol = fragment.mediaSymbol {
            record[CloudKitRecordKey.fragmentMediaSymbol] = symbol as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentMediaSymbol] = nil
        }

        if let location = fragment.location {
            record[CloudKitRecordKey.fragmentLocation] = location as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentLocation] = nil
        }

        if let duration = fragment.duration {
            record[CloudKitRecordKey.fragmentDuration] = duration as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentDuration] = nil
        }

        // Spherical Coordinates
        record[CloudKitRecordKey.fragmentPhi] = fragment.phi as CKRecordValue
        record[CloudKitRecordKey.fragmentTheta] = fragment.theta as CKRecordValue
        record[CloudKitRecordKey.fragmentRadiusFactor] = fragment.radiusFactor as CKRecordValue

        // Accent Color
        if let accentHex = fragment.accentColorHex {
            record[CloudKitRecordKey.fragmentAccentColorHex] = accentHex as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentAccentColorHex] = nil
        }

        // Waveform samples
        if !fragment.audioWaveform.isEmpty {
            let doubleValues = fragment.audioWaveform.map { Double($0) }
            record[CloudKitRecordKey.fragmentWaveform] = doubleValues as CKRecordValue
        } else {
            record[CloudKitRecordKey.fragmentWaveform] = nil
        }

        // Attach Media CKAsset if available
        let fileURLToAttach = assetFileURL ?? fragment.mediaReference?.localFileURL
        if let fileURL = fileURLToAttach, FileManager.default.fileExists(atPath: fileURL.path) {
            record[CloudKitRecordKey.fragmentMediaAsset] = CKAsset(fileURL: fileURL)
        }

        return record
    }

    /// Converts a `CKRecord` into a `SharedFragment` domain model.
    /// - Parameter record: The CloudKit record.
    /// - Returns: A decoded `SharedFragment`, or `nil` if essential fields are missing.
    public static func toSharedFragment(from record: CKRecord) -> SharedFragment? {
        let roomId: String
        if let roomRef = record[CloudKitRecordKey.fragmentRoom] as? CKRecord.Reference {
            roomId = roomRef.recordID.recordName
        } else if let directRoomId = record[CloudKitRecordKey.fragmentRoomId] as? String {
            roomId = directRoomId
        } else {
            return nil
        }

        guard let authorId = record[CloudKitRecordKey.fragmentAuthorId] as? String,
              let authorName = record[CloudKitRecordKey.fragmentAuthorName] as? String,
              let typeRaw = record[CloudKitRecordKey.fragmentType] as? String,
              let type = FragmentType(rawValue: typeRaw),
              let title = record[CloudKitRecordKey.fragmentTitle] as? String else {
            return nil
        }

        let id = record.recordID.recordName
        let createdAt = (record[CloudKitRecordKey.fragmentCreatedAt] as? Date) ?? record.creationDate ?? Date()
        let subtitle = record[CloudKitRecordKey.fragmentSubtitle] as? String
        let text = record[CloudKitRecordKey.fragmentText] as? String
        let mediaSymbol = record[CloudKitRecordKey.fragmentMediaSymbol] as? String
        let location = record[CloudKitRecordKey.fragmentLocation] as? String
        let duration = record[CloudKitRecordKey.fragmentDuration] as? String
        let accentColorHex = record[CloudKitRecordKey.fragmentAccentColorHex] as? String

        let phi = (record[CloudKitRecordKey.fragmentPhi] as? Double) ?? 0.08
        let theta = (record[CloudKitRecordKey.fragmentTheta] as? Double) ?? 0.35
        let radiusFactor = (record[CloudKitRecordKey.fragmentRadiusFactor] as? Double) ?? 1.0

        // Parse waveform
        var audioWaveform: [CGFloat] = []
        if let doubleWaveform = record[CloudKitRecordKey.fragmentWaveform] as? [Double] {
            audioWaveform = doubleWaveform.map { CGFloat($0) }
        }

        // Parse CKAsset
        var mediaReference: SharedMediaReference? = nil
        if let asset = record[CloudKitRecordKey.fragmentMediaAsset] as? CKAsset, let fileURL = asset.fileURL {
            let ext = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension
            mediaReference = SharedMediaReference(
                assetKey: CloudKitRecordKey.fragmentMediaAsset,
                localFileURL: fileURL,
                remoteURL: nil,
                fileExtension: ext,
                fileSize: nil,
                mimeType: nil
            )
        }

        return SharedFragment(
            id: id,
            roomId: roomId,
            authorId: authorId,
            authorName: authorName,
            type: type,
            createdAt: createdAt,
            title: title,
            subtitle: subtitle,
            text: text,
            mediaReference: mediaReference,
            mediaSymbol: mediaSymbol,
            location: location,
            duration: duration,
            audioWaveform: audioWaveform,
            accentColorHex: accentColorHex,
            phi: phi,
            theta: theta,
            radiusFactor: radiusFactor
        )
    }
}
