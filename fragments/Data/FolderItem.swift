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
    public var text: String?
    public var duration: String?
    public var audioWaveform: [CGFloat]?
    public var type: FragmentType?
    public var createdAt: Date?
    public var phi: Double?
    public var theta: Double?
    public var radiusFactor: Double?
    
    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String? = nil,
        systemImage: String? = nil,
        imageName: String? = nil,
        gradientColors: [Color] = [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
        tag: String? = nil,
        text: String? = nil,
        duration: String? = nil,
        audioWaveform: [CGFloat]? = nil,
        type: FragmentType? = nil,
        createdAt: Date? = nil,
        phi: Double? = nil,
        theta: Double? = nil,
        radiusFactor: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.imageName = imageName
        self.gradientColors = gradientColors
        self.tag = tag
        self.text = text
        self.duration = duration
        self.audioWaveform = audioWaveform
        self.type = type
        self.createdAt = createdAt
        self.phi = phi
        self.theta = theta
        self.radiusFactor = radiusFactor
    }
    
    public init(from fragment: Fragment) {
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
        
        self.init(
            id: fragment.id,
            title: fragment.title.isEmpty ? "\(fragment.type.displayName) Fragment" : fragment.title,
            subtitle: fragment.subtitle ?? fragment.formattedTimestamp,
            systemImage: systemIcon,
            imageName: fragment.mediaResourceName,
            gradientColors: fragment.gradientColors,
            tag: tag,
            text: fragment.text,
            duration: fragment.duration,
            audioWaveform: fragment.audioWaveform,
            type: fragment.type,
            createdAt: fragment.createdAt,
            phi: fragment.phi,
            theta: fragment.theta,
            radiusFactor: fragment.radiusFactor
        )
    }
    
    public func toFragment() -> Fragment {
        let resolvedType: FragmentType = {
            if let t = type { return t }
            if let tg = tag {
                switch tg.uppercased() {
                case "PHOTO": return .photo
                case "VIDEO": return .video
                case "MEMO", "AUDIO": return .audio
                case "NOTE": return .note
                default: break
                }
            }
            if let sys = systemImage {
                if sys.contains("photo") { return .photo }
                if sys.contains("video") { return .video }
                if sys.contains("wave") || sys.contains("mic") { return .audio }
                if sys.contains("text") || sys.contains("quote") || sys.contains("doc") { return .note }
            }
            return .photo
        }()
        
        return Fragment(
            id: id,
            type: resolvedType,
            createdAt: createdAt ?? Date(),
            title: title,
            subtitle: subtitle,
            text: text,
            mediaSymbol: systemImage,
            mediaResourceName: imageName,
            gradientColors: gradientColors.isEmpty ? [Color.blue, Color.purple] : gradientColors,
            duration: duration,
            audioWaveform: audioWaveform ?? [],
            phi: phi,
            theta: theta,
            radiusFactor: radiusFactor
        )
    }
    
    /// Resolves local or bundle video URL for playback
    public var videoURL: URL? {
        if let directURL = toFragment().mediaURL {
            return directURL
        }
        if let name = imageName {
            if let bundleURL = Bundle.main.url(forResource: name, withExtension: nil) {
                return bundleURL
            }
            if let bundleURL = Bundle.main.url(forResource: name, withExtension: "mp4") ?? Bundle.main.url(forResource: name, withExtension: "mov") {
                return bundleURL
            }
        }
        return nil
    }
    
    public var resolvedGradientColors: [Color] {
        if !gradientColors.isEmpty {
            return gradientColors
        }
        switch type {
        case .note:
            return [Color(red: 1.0, green: 0.859, blue: 0.576), Color(red: 0.98, green: 0.76, blue: 0.45)]
        case .audio:
            return [Color(red: 0.0, green: 0.533, blue: 1.0), Color(red: 0.10, green: 0.40, blue: 0.90)]
        case .photo:
            return [Color(red: 0.40, green: 0.40, blue: 0.85), Color(red: 0.70, green: 0.35, blue: 0.80)]
        case .video:
            return [Color(red: 0.35, green: 0.65, blue: 1.0), Color(red: 0.20, green: 0.45, blue: 0.95)]
        case nil:
            return [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
        }
    }
}

// MARK: - Moment Category

public enum MomentCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case life = "Life"
    case travel = "Travel"
    case friends = "Friends"
    case nature = "Nature"
    case creative = "Creative"
    case work = "Work"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    /// SF Symbol corresponding to each category
    public var sfSymbol: String {
        switch self {
        case .life:
            return "leaf.fill"
        case .travel:
            return "airplane.up.right"
        case .friends:
            return "figure.2.left.holdinghands"
        case .nature:
            return "sun.max.fill"
        case .creative:
            return "paintbrush.pointed.fill"
        case .work:
            return "case.fill"
        }
    }

    /// Resolves the SF Symbol name from an optional category string case-insensitively
    public static func symbol(for rawCategory: String?) -> String? {
        guard let raw = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        switch lower {
        case "life": return MomentCategory.life.sfSymbol
        case "travel": return MomentCategory.travel.sfSymbol
        case "friends": return MomentCategory.friends.sfSymbol
        case "nature": return MomentCategory.nature.sfSymbol
        case "creative": return MomentCategory.creative.sfSymbol
        case "work": return MomentCategory.work.sfSymbol
        default: return nil
        }
    }

    /// Parses string into strongly-typed MomentCategory
    public static func from(string: String?) -> MomentCategory? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch raw {
        case "life": return .life
        case "travel": return .travel
        case "friends": return .friends
        case "nature": return .nature
        case "creative": return .creative
        case "work": return .work
        default: return nil
        }
    }

    public static let allCategoryNames: [String] = MomentCategory.allCases.map { $0.rawValue }
}

// MARK: - Array Extension for 3D Spatial Distribution
extension Array where Element == FolderItem {
    /// Converts array of FolderItems to Fragments with properly scattered 3D spherical coordinates
    public func toFragments() -> [Fragment] {
        self.enumerated().map { index, item in
            var frag = item.toFragment()
            if item.phi == nil || item.theta == nil {
                let coords = FragmentSphere.fibonacciCoordinates(count: self.count, index: index)
                frag.phi = coords.phi
                frag.theta = coords.theta
                frag.radiusFactor = coords.radiusFactor
            }
            return frag
        }
    }
}

