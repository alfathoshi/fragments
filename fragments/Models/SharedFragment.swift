//
//  SharedFragment.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import Foundation

// MARK: - FragmentType Conformance

extension FragmentType: Codable, Sendable {}

// MARK: - Shared Media Reference

/// Reference describing media attached to a shared fragment in CloudKit and local cache.
public struct SharedMediaReference: Hashable, Sendable, Codable {
    /// The CloudKit record field key storing the CKAsset (e.g., "mediaAsset") or Supabase Storage path.
    public var assetKey: String?

    /// Canonical remote storage path identifier for Supabase Storage (aliases assetKey).
    nonisolated public var storagePath: String? {
        get { assetKey }
        set { assetKey = newValue }
    }

    /// Local file URL where the asset is downloaded or cached on the current device.
    public var localFileURL: URL?

    /// Optional remote URL if media is mirrored or streamed.
    public var remoteURL: URL?

    /// File extension of the media asset (e.g. "jpg", "mov", "m4a").
    public var fileExtension: String?

    /// Size of the media file in bytes.
    public var fileSize: Int64?

    /// Standard MIME content type (e.g. "image/jpeg", "video/quicktime", "audio/m4a").
    public var mimeType: String?

    public init(
        assetKey: String? = nil,
        storagePath: String? = nil,
        localFileURL: URL? = nil,
        remoteURL: URL? = nil,
        fileExtension: String? = nil,
        fileSize: Int64? = nil,
        mimeType: String? = nil
    ) {
        self.assetKey = assetKey ?? storagePath
        self.localFileURL = localFileURL
        self.remoteURL = remoteURL
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.mimeType = mimeType
    }
}

// MARK: - Shared Fragment Model

/// Represents a collaborative Fragment captured inside a shared Room.
public struct SharedFragment: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier of the fragment (corresponds to CloudKit CKRecord.ID.recordName).
    public let id: String

    /// Identifier of the Room this fragment belongs to.
    public let roomId: String

    /// The CloudKit user record ID of the author who captured this fragment.
    public let authorId: String

    /// Display name of the author when captured.
    public var authorName: String

    /// The type of fragment (photo, video, audio, note).
    public var type: FragmentType

    /// Timestamp when this fragment was captured.
    public var createdAt: Date

    /// Title of the fragment.
    public var title: String

    /// Optional subtitle or caption.
    public var subtitle: String?

    /// Text body for note fragments or captions.
    public var text: String?

    /// Reference to the attached media file or CloudKit asset.
    public var mediaReference: SharedMediaReference?

    /// SF Symbol icon name used for audio/note fragments.
    public var mediaSymbol: String?

    /// Optional location name where captured (e.g. "Uluwatu, Bali").
    public var location: String?

    /// Duration string for audio/video fragments (e.g. "0:42").
    public var duration: String?

    /// Normalized waveform samples for audio playback visualizations.
    public var audioWaveform: [CGFloat]

    /// Optional custom accent color serialized as an RGBA string (e.g. for Notes and Voice Memos).
    public var accentColorHex: String?

    // MARK: - Spherical Coordinates on Collaborative Canvas
    public var phi: Double          // Latitude angle [-π/2, π/2]
    public var theta: Double        // Longitude angle [0, 2π]
    public var radiusFactor: Double // Subtle scattering variation [0.85, 1.15]

    public init(
        id: String = UUID().uuidString,
        roomId: String,
        authorId: String,
        authorName: String,
        type: FragmentType,
        createdAt: Date = Date(),
        title: String,
        subtitle: String? = nil,
        text: String? = nil,
        mediaReference: SharedMediaReference? = nil,
        mediaSymbol: String? = nil,
        location: String? = nil,
        duration: String? = nil,
        audioWaveform: [CGFloat] = [],
        accentColorHex: String? = nil,
        phi: Double = 0.08,
        theta: Double = 0.35,
        radiusFactor: Double = 1.0
    ) {
        self.id = id
        self.roomId = roomId
        self.authorId = authorId
        self.authorName = authorName
        self.type = type
        self.createdAt = createdAt
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.mediaReference = mediaReference
        self.mediaSymbol = mediaSymbol
        self.location = location
        self.duration = duration
        self.audioWaveform = audioWaveform
        self.accentColorHex = accentColorHex
        self.phi = phi
        self.theta = theta
        self.radiusFactor = radiusFactor
    }

    /// Converts this SharedFragment into a standard local Fragment for 3D sphere visualization and session staging.
    public func toFragment() -> Fragment {
        let colors: [Color] = {
            if let hex = accentColorHex {
                let c = Color.fromRGBAString(hex)
                return [c, c.opacity(0.85)]
            }
            return [type.accentColor, type.accentColor.opacity(0.6)]
        }()

        let resolvedLocalPath: String? = {
            if let local = mediaReference?.localFileURL, FileManager.default.fileExists(atPath: local.path) {
                return local.path
            }
            if let storagePath = mediaReference?.storagePath, !storagePath.isEmpty {
                let preferred = mediaReference?.fileExtension.map { "\(id).\($0)" }
                if let cached = RemoteMediaService.shared.cachedMediaURL(for: storagePath, roomID: roomId, preferredFilename: preferred) {
                    return cached.path
                }
            }
            return nil
        }()

        return Fragment(
            id: UUID(uuidString: id) ?? UUID(),
            type: type,
            createdAt: createdAt,
            title: title,
            subtitle: subtitle ?? authorName,
            text: text,
            mediaSymbol: mediaSymbol,
            mediaResourceName: resolvedLocalPath,
            gradientColors: colors,
            location: location,
            duration: duration,
            audioWaveform: audioWaveform,
            phi: phi,
            theta: theta,
            radiusFactor: radiusFactor
        )
    }

    /// Indicates whether this SharedFragment was authored by the current user.
    ///
    /// Evaluates against the canonical Supabase user ID if authenticated, falling back
    /// to local/CloudKit user identifier if applicable.
    @MainActor
    public var isAuthoredByCurrentUser: Bool {
        if let currentSupabaseID = UserIdentityService.shared.collaborativeUserID {
            if authorId.lowercased() == currentSupabaseID.lowercased() {
                return true
            }
        }
        if let localID = UserIdentityService.shared.currentUserIdentity?.id {
            if authorId == localID {
                return true
            }
        }
        return false
    }
}

// MARK: - Fragment -> SharedFragment Conversion

extension Fragment {
    /// Converts a local Fragment to a collaborative SharedFragment model.
    @MainActor
    public func toSharedFragment(
        roomId: String,
        authorId: String? = nil,
        authorName: String? = nil,
        id: String? = nil
    ) -> SharedFragment {
        let resolvedAuthorId: String = {
            if let explicit = authorId, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explicit
            }
            if let collabID = UserIdentityService.shared.collaborativeUserID {
                return collabID
            }
            return UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
        }()
        let resolvedAuthorName = authorName ?? ProfileManager.shared.effectiveName

        let mediaRef: SharedMediaReference? = {
            if let resolvedURL = self.mediaURL {
                return SharedMediaReference(localFileURL: resolvedURL, fileExtension: resolvedURL.pathExtension)
            } else if let path = mediaResourceName {
                let url = URL(fileURLWithPath: path)
                return SharedMediaReference(localFileURL: url, fileExtension: url.pathExtension)
            }
            return nil
        }()

        return SharedFragment(
            id: id ?? self.id.uuidString,
            roomId: roomId,
            authorId: resolvedAuthorId,
            authorName: resolvedAuthorName,
            type: type,
            createdAt: createdAt,
            title: title,
            subtitle: subtitle,
            text: text,
            mediaReference: mediaRef,
            mediaSymbol: mediaSymbol,
            location: location,
            duration: duration,
            audioWaveform: audioWaveform,
            accentColorHex: gradientColors.first?.toRGBAString(),
            phi: phi,
            theta: theta,
            radiusFactor: radiusFactor
        )
    }

    /// Creates an independent collaborative copy of this personal Fragment with a distinct collaborative ID.
    @MainActor
    public func toCollaborativeCopy(
        forRoomId roomId: String,
        authorId: String? = nil,
        authorName: String? = nil,
        newSharedId: String = UUID().uuidString
    ) -> SharedFragment {
        toSharedFragment(
            roomId: roomId,
            authorId: authorId,
            authorName: authorName,
            id: newSharedId
        )
    }
}

