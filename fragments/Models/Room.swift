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

    /// Whether the Room is archived by the owner.
    public var isArchived: Bool

    /// Cached count of members in the Room.
    public var memberCount: Int

    /// Cached count of fragments captured in the Room.
    public var fragmentCount: Int

    /// Optional theme accent color stored as hex string (e.g. "#FF5733").
    public var accentColorHex: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String = "✨",
        createdAt: Date = Date(),
        createdBy: String,
        shareRecordID: String? = nil,
        zoneName: String? = nil,
        isArchived: Bool = false,
        memberCount: Int = 1,
        fragmentCount: Int = 0,
        accentColorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.shareRecordID = shareRecordID
        self.zoneName = zoneName
        self.isArchived = isArchived
        self.memberCount = memberCount
        self.fragmentCount = fragmentCount
        self.accentColorHex = accentColorHex
    }
}
