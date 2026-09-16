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
        createdAt: Date? = nil
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
            createdAt: fragment.createdAt
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
            audioWaveform: audioWaveform ?? []
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

