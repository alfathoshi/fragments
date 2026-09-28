//
//  Room.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation

/// Represents a collaborative Room where multiple users capture fragments together.
public struct Room: Identifiable, Hashable, Sendable, Codable {
    /// The unique identifier of the Room (corresponds to CloudKit CKRecord.ID.recordName).
    public let id: String

    /// The human-readable name of the Room (e.g. "Bali Trip 2026").
    public var name: String

    /// An emoji or icon representing the Room (e.g. "🌴").
    public var emoji: String

    /// The creation date of the Room.
    public var createdAt: Date

    /// The CloudKit user record ID of the creator/owner.
    public var createdBy: String

    /// Optional reference to the CKShare record identifier if shared with other participants.
    public var shareRecordID: String?

    /// The name of the custom CKRecordZone where room data lives.
    public var zoneName: String?

    /// Whether the Room has been ended by the host.
    public var isEnded: Bool

    /// Whether the Room is archived by the owner.
    public var isArchived: Bool

    /// Cached count of members in the Room.
    public var memberCount: Int

    /// Cached count of fragments captured in the Room.
    public var fragmentCount: Int

    /// Optional theme accent color stored as hex string (e.g. "#FF5733").
    public var accentColorHex: String?

    /// Final title given to the session when it ended.
    public var finalTitle: String?

    /// Final category assigned to the session when it ended.
    public var finalCategory: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String = "✨",
        createdAt: Date = Date(),
        createdBy: String,
        shareRecordID: String? = nil,
        zoneName: String? = nil,
        isEnded: Bool = false,
        isArchived: Bool = false,
        memberCount: Int = 1,
        fragmentCount: Int = 0,
        accentColorHex: String? = nil,
        finalTitle: String? = nil,
        finalCategory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.shareRecordID = shareRecordID
        self.zoneName = zoneName
        self.isEnded = isEnded
        self.isArchived = isArchived
        self.memberCount = memberCount
        self.fragmentCount = fragmentCount
        self.accentColorHex = accentColorHex
        self.finalTitle = finalTitle
        self.finalCategory = finalCategory
    }

    /// Identifies the remote synchronization backend responsible for this Room.
    public var backend: RoomBackend {
        if zoneName?.lowercased() == "supabase" {
            return .supabase
        }
        return .cloudKit
    }

    /// Whether the currently signed-in user is the creator/owner of this Room.
    @MainActor
    public var isCurrentUserOwner: Bool {
        if backend == .supabase {
            let createdByLower = createdBy.lowercased()
            if let sbUserId = SupabaseService.shared.currentUserID?.lowercased() {
                if createdByLower == sbUserId { return true }
            }
            let localId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
            return createdBy == localId
        } else {
            let ckUserId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
            return createdBy == ckUserId
        }
    }
}

/// Defines the remote backend origin for collaborative Rooms.
public enum RoomBackend: String, Codable, Sendable {
    case cloudKit
    case supabase
}

