//
//  FolderItem.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/13/26.
//

import SwiftUI

/// Data model representing a preview item tucked inside the folder.
public struct FolderItem: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var subtitle: String?
    public var systemImage: String?
    public var imageName: String?
    public var gradientColors: [Color]
    public var tag: String?

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String? = nil,
        systemImage: String? = nil,
        imageName: String? = nil,
        gradientColors: [Color] = [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
        tag: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.imageName = imageName
        self.gradientColors = gradientColors
        self.tag = tag
    }

    /// Sample items for previews and testing
    public static var samplePhotos: [FolderItem] {
        [
            FolderItem(
                title: "Sunset Glow",
                subtitle: "Golden hour capture",
                systemImage: "sun.max.fill",
                gradientColors: [Color(red: 1.0, green: 0.55, blue: 0.45), Color(red: 0.95, green: 0.25, blue: 0.50)],
                tag: "PHOTO"
            ),
            FolderItem(
                title: "Emerald Woods",
                subtitle: "Morning trail run",
                systemImage: "leaf.fill",
                gradientColors: [Color(red: 0.22, green: 0.75, blue: 0.55), Color(red: 0.12, green: 0.45, blue: 0.38)],
                tag: "NATURE"
            ),
            FolderItem(
                title: "Ocean Whisper",
                subtitle: "Canggu beachfront",
                systemImage: "water.waves",
                gradientColors: [Color(red: 0.25, green: 0.65, blue: 0.95), Color(red: 0.20, green: 0.35, blue: 0.75)],
                tag: "TRAVEL"
            )
        ]
    }

    public static var sampleDocuments: [FolderItem] {
        [
            FolderItem(
                title: "Project Pitch",
                subtitle: "Keynote 2026",
                systemImage: "doc.richtext.fill",
                gradientColors: [Color(red: 0.98, green: 0.70, blue: 0.25), Color(red: 0.92, green: 0.45, blue: 0.20)],
                tag: "DECK"
            ),
            FolderItem(
                title: "Design System",
                subtitle: "Figma tokens v2.4",
                systemImage: "paintpalette.fill",
                gradientColors: [Color(red: 0.65, green: 0.45, blue: 0.95), Color(red: 0.40, green: 0.25, blue: 0.85)],
                tag: "FIGMA"
            ),
            FolderItem(
                title: "Architecture Spec",
                subtitle: "Core Engine v1",
                systemImage: "cpu.fill",
                gradientColors: [Color(red: 0.30, green: 0.80, blue: 0.85), Color(red: 0.15, green: 0.45, blue: 0.65)],
                tag: "CODE"
            )
        ]
    }
}
