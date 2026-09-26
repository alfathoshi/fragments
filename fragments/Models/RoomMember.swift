//
//  RoomMember.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation

/// Defines access and participation roles within a collaborative Room.
public enum RoomRole: String, Codable, Sendable, CaseIterable {
    case owner
    case member
    case viewer

    /// Alias for member
    public static let editor: RoomRole = .member

    public var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .member: return "Member"
        case .viewer: return "Viewer"
        }
    }

    public var canCaptureFragments: Bool {
        switch self {
        case .owner, .member: return true
        case .viewer: return false
        }
    }

    public var canManageMembers: Bool {
        self == .owner
    }
}

/// Represents a member participating in a collaborative Room.
public struct RoomMember: Identifiable, Hashable, Sendable, Codable {
    /// The unique identifier of this membership record (corresponds to CloudKit CKRecord.ID.recordName).
    public let id: String

    /// The identifier of the Room this member belongs to.
    public let roomId: String

    /// The CloudKit user record ID of this member.
    public let userId: String

    /// The user's display name inside the Room.
    public var displayName: String

    /// The member's role in the Room.
    public var role: RoomRole

    /// When the member joined the Room.
    public var joinedAt: Date

    /// Optional local or cached URL for the member's profile avatar.
    public var avatarAssetURL: URL?

    public init(
        id: String? = nil,
        roomId: String,
        userId: String,
        displayName: String,
        role: RoomRole = .member,
        joinedAt: Date = Date(),
        avatarAssetURL: URL? = nil
    ) {
        // By default, create a deterministic or unique membership record ID
        self.id = id ?? "\(roomId)_\(userId)"
        self.roomId = roomId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
        self.avatarAssetURL = avatarAssetURL
    }
}
