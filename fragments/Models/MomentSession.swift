//
//  MomentSession.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI

/// Represents an ongoing or completed moment creation session.
public struct MomentSession: Identifiable, Hashable {
    public let id: UUID
    public var startDate: Date
    public var fragments: [Fragment]
    public var location: String

    public init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        fragments: [Fragment] = [],
        location: String = "Jakarta, ID"
    ) {
        self.id = id
        self.startDate = startDate
        self.fragments = fragments
        self.location = location
    }

    public var fragmentCount: Int {
        fragments.count
    }

    public var fragmentCountText: String {
        "\(fragments.count) \(fragments.count == 1 ? "fragment" : "fragments")"
    }

    public func formattedElapsed(at date: Date = Date()) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(startDate)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Converts the session's captured Fragments into FolderItems for the FolderCollection model.
    public func createFolderItems() -> [FolderItem] {
        return fragments.map { fragment in
            let tag: String
            let systemIcon: String
            switch fragment.type {
            case .photo:
                tag = "PHOTO"
                systemIcon = "photo.fill"
            case .video:
                tag = "VIDEO"
                systemIcon = "video.fill"
            case .note:
                tag = "NOTE"
                systemIcon = "text.quote"
            case .audio:
                tag = "MEMO"
                systemIcon = "waveform"
            }

            return FolderItem(
                id: fragment.id,
                title: fragment.title.isEmpty ? "\(fragment.type.displayName) Fragment" : fragment.title,
                subtitle: fragment.subtitle ?? fragment.formattedTimestamp,
                systemImage: systemIcon,
                imageName: fragment.mediaResourceName,
                gradientColors: fragment.gradientColors,
                tag: tag
            )
        }
    }
}
