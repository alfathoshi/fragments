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
        location: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.fragments = fragments
        self.location = location ?? LocationManager.shared.currentLocationName ?? "Current Location"
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

    /// Converts the session's captured Fragments into FolderItems for the FolderCollection model (capped at 5 items).
    public func createFolderItems() -> [FolderItem] {
        return Array(fragments.prefix(5)).map { FolderItem(from: $0) }
    }
}
