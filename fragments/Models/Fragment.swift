//
//  Fragment.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI
import AVFoundation
import ImageIO

// MARK: - Thumbnail Cache & Image Downsampler
private let photoThumbnailCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 120
    cache.totalCostLimit = 40 * 1024 * 1024 // 40 MB max memory limit
    return cache
}()

private let fullImageCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 20
    cache.totalCostLimit = 60 * 1024 * 1024 // 60 MB max memory limit
    return cache
}()

private let videoThumbnailCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 50
    return cache
}()

/// Memory-efficient image downsampler using CoreGraphics ImageIO.
/// Bypasses full-resolution bitmap decompression in RAM.
public func downsampleImage(at url: URL, to pointSize: CGSize, scale: CGFloat = 2.0) -> UIImage? {
    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
        return nil
    }

    let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
    ]

    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
        return nil
    }

    return UIImage(cgImage: downsampledImage)
}

// MARK: - Fragment Type

public enum FragmentType: String, CaseIterable, Identifiable, Hashable {
    case photo
    case video
    case audio
    case note

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
        case .note:  return "Note"
        }
    }

    public var systemIcon: String {
        switch self {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .note:  return "text.quote"
        }
    }

    public var accentColor: Color {
        switch self {
        case .photo: return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .video: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .audio: return Color(red: 0.40, green: 0.85, blue: 0.65)
        case .note:  return Color(red: 0.85, green: 0.60, blue: 0.95)
        }
    }
}

// MARK: - Fragment Model

public struct Fragment: Identifiable, Hashable {
    public let id: UUID
    public var type: FragmentType
    public var createdAt: Date
    public var title: String
    public var subtitle: String?
    public var text: String?
    public var mediaSymbol: String?
    public var mediaResourceName: String?
    public var gradientColors: [Color]
    public var location: String?
    public var duration: String?
    public var audioWaveform: [CGFloat]
    
    // Spherical coordinates on virtual sphere
    public var phi: Double          // Latitude angle [-π/2, π/2]
    public var theta: Double        // Longitude angle [0, 2π]
    public var radiusFactor: Double // Subtle scattering variation [0.85, 1.15]
    public var baseSize: CGSize

    public init(
        id: UUID = UUID(),
        type: FragmentType,
        createdAt: Date = Date(),
        title: String,
        subtitle: String? = nil,
        text: String? = nil,
        mediaSymbol: String? = nil,
        mediaResourceName: String? = nil,
        gradientColors: [Color] = [Color.blue, Color.purple],
        location: String? = nil,
        duration: String? = nil,
        audioWaveform: [CGFloat] = [],
        phi: Double? = nil,
        theta: Double? = nil,
        radiusFactor: Double? = nil,
        baseSize: CGSize = CGSize(width: 90, height: 105)
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.mediaSymbol = mediaSymbol
        self.mediaResourceName = mediaResourceName
        self.gradientColors = gradientColors
        self.location = location
        self.duration = duration
        self.audioWaveform = audioWaveform
        
        if let p = phi, let t = theta {
            self.phi = p
            self.theta = t
            self.radiusFactor = radiusFactor ?? 1.0
        } else {
            let coords = Self.generateScatteredCoordinates()
            self.phi = coords.phi
            self.theta = coords.theta
            self.radiusFactor = radiusFactor ?? coords.radiusFactor
        }
        self.baseSize = baseSize
    }

    // MARK: - Spatial Scattering Engine
    
    /// Generates distributed spherical coordinates that avoid overlapping with existing fragments.
    public static func generateScatteredCoordinates(existing: [Fragment] = []) -> (phi: Double, theta: Double, radiusFactor: Double) {
        if existing.isEmpty {
            // First fragment lands in a prominent forward-facing spot
            return (phi: 0.08, theta: 0.35, radiusFactor: 1.02)
        }
        
        // Generate candidate positions across the visible sphere zone
        var bestCandidate = (phi: Double.random(in: -0.45...0.45), theta: Double.random(in: 0...(2.0 * .pi)), radiusFactor: Double.random(in: 0.96...1.05))
        var maxMinDistance: Double = -1.0
        
        // Sample 32 candidate directions using golden spiral distribution + jitter
        let goldenAngle = 2.39996323 // ~137.5 degrees in radians
        for i in 0..<32 {
            let candidatePhi = Double.random(in: -0.50...0.50)
            let baseTheta = Double(existing.count + i) * goldenAngle
            let rawTheta = (baseTheta + Double.random(in: -0.25...0.25)).truncatingRemainder(dividingBy: 2.0 * .pi)
            let candidateTheta = rawTheta < 0 ? rawTheta + 2.0 * .pi : rawTheta
            
            // Calculate minimum angular distance to any existing fragment
            var minDistance = Double.infinity
            for frag in existing {
                let dPhi = candidatePhi - frag.phi
                var dTheta = abs(candidateTheta - frag.theta)
                if dTheta > .pi {
                    dTheta = 2.0 * .pi - dTheta
                }
                let avgPhi = (candidatePhi + frag.phi) / 2.0
                let dist = sqrt(dPhi * dPhi + (dTheta * cos(avgPhi)) * (dTheta * cos(avgPhi)))
                if dist < minDistance {
                    minDistance = dist
                }
            }
            
            if minDistance > maxMinDistance {
                maxMinDistance = minDistance
                let rFactor = Double.random(in: 0.96...1.05)
                bestCandidate = (phi: candidatePhi, theta: candidateTheta, radiusFactor: rFactor)
            }
        }
        
        return bestCandidate
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    public var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    // Resolves media file in local documents, temporary directory, or app bundle
    public var mediaURL: URL? {
        guard let name = mediaResourceName, !name.isEmpty else { return nil }
        
        // 1. Direct file URL string or absolute path
        if name.hasPrefix("file://"), let url = URL(string: name), FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if name.hasPrefix("/"), FileManager.default.fileExists(atPath: name) {
            return URL(fileURLWithPath: name)
        }
        
        // 2. Extract last path component (handles sandbox container UUID changes across launches)
        let filename = (name as NSString).lastPathComponent
        
        // Documents directory file (captured photos / videos)
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docFile = docsURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: docFile.path) {
                return docFile
            }
        }
        
        // Temporary directory file (recorded video clips)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: tempFile.path) {
            return tempFile
        }

        // 3. App Bundle resource check
        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            return bundleURL
        }
        let nsFilename = filename as NSString
        if let bundleURL = Bundle.main.url(forResource: nsFilename.deletingPathExtension, withExtension: nsFilename.pathExtension) {
            return bundleURL
        }

        return nil
    }

    /// Downsampled thumbnail for fast 60 FPS sphere rendering (allocates < 0.2 MB RAM per image)
    public var thumbnailImage: UIImage? {
        guard type == .photo, let url = mediaURL else { return nil }
        let key = url.lastPathComponent as NSString
        if let cached = photoThumbnailCache.object(forKey: key) {
            return cached
        }
        // Downsample to card bounds (around 120 x 140 pt * 2.0 scale = 240 x 280 pixels)
        if let thumb = downsampleImage(at: url, to: CGSize(width: 120, height: 140), scale: 2.0) {
            photoThumbnailCache.setObject(thumb, forKey: key)
            return thumb
        }
        if let fallback = UIImage(contentsOfFile: url.path) {
            photoThumbnailCache.setObject(fallback, forKey: key)
            return fallback
        }
        return nil
    }

    /// Screen-fitted image for FragmentDetailView modal inspection
    public var loadedImage: UIImage? {
        guard type == .photo, let url = mediaURL else { return nil }
        let key = url.lastPathComponent as NSString
        if let cached = fullImageCache.object(forKey: key) {
            return cached
        }
        // Downsample to max modal preview dimensions (e.g. 360 x 420 pt * 2.5 scale)
        if let fitted = downsampleImage(at: url, to: CGSize(width: 360, height: 420), scale: 2.5) {
            fullImageCache.setObject(fitted, forKey: key)
            return fitted
        }
        if let fallback = UIImage(contentsOfFile: url.path) {
            fullImageCache.setObject(fallback, forKey: key)
            return fallback
        }
        return nil
    }

    public var videoThumbnail: UIImage? {
        guard type == .video, let url = mediaURL else { return nil }
        let key = url.lastPathComponent as NSString
        if let cached = videoThumbnailCache.object(forKey: key) {
            return cached
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 480)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let img = UIImage(cgImage: cgImage)
            videoThumbnailCache.setObject(img, forKey: key)
            return img
        }
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            let img = UIImage(cgImage: cgImage)
            videoThumbnailCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    // MARK: - Curated Samples
    public static var sampleFragments: [Fragment] {
        return []
    }
}

// MARK: - 3D Spatial Calculation System

public struct ProjectedFragment: Identifiable {
    public let fragment: Fragment
    public let x: CGFloat
    public let y: CGFloat
    public let depthZ: CGFloat       // [-R, R]
    public let normalizedZ: CGFloat  // [0, 1] front is 1.0, back is 0.0
    public let scale: CGFloat
    public let opacity: Double
    public let blurRadius: CGFloat
    public let zIndex: Double
    public let rotationY: Double     // degrees for subtle spatial tilt

    public var id: UUID { fragment.id }
}

public enum SpherePositionEngine {
    /// Projects a set of fragments onto a 2D screen based on a virtual 3D sphere.
    /// - Parameters:
    ///   - fragments: Array of Fragment models
    ///   - radius: Virtual sphere radius (in points)
    ///   - rotationAngle: Current horizontal rotation in radians
    ///   - tiltAngle: Subtle vertical pitch angle in radians
    ///   - time: Subtle floating time offset for breathing animation
    /// - Returns: Array of projected fragments ready for rendering
    public static func project(
        fragments: [Fragment],
        radius: CGFloat,
        rotationAngle: Double,
        tiltAngle: Double = 0.0,
        time: Double = 0.0
    ) -> [ProjectedFragment] {
        let cameraDistance: CGFloat = 650.0

        return fragments.map { fragment in
            let angleTheta = fragment.theta + rotationAngle
            let anglePhi = fragment.phi

            // Subtle organic floating bobbing
            let floatPhase = Double(fragment.id.hashValue % 1000) / 1000.0 * 2.0 * .pi
            let floatOffset = sin(time * 1.5 + floatPhase) * 6.0
            let effectiveRadius = radius * fragment.radiusFactor + floatOffset

            // Spherical coordinates to 3D Cartesian coordinates
            // X: left/right
            // Y: up/down
            // Z: towards camera (+Z) / away from camera (-Z)
            let cosPhi = cos(anglePhi)
            let sinPhi = sin(anglePhi)
            let sinTheta = sin(angleTheta)
            let cosTheta = cos(angleTheta)

            let x0 = cosPhi * sinTheta
            let y0 = -sinPhi
            let z0 = cosPhi * cosTheta

            // Apply vertical tilt (rotation around X-axis)
            let cosTilt = cos(tiltAngle)
            let sinTilt = sin(tiltAngle)
            let x1 = x0
            let y1 = y0 * cosTilt - z0 * sinTilt
            let z1 = y0 * sinTilt + z0 * cosTilt

            let worldX = CGFloat(x1) * effectiveRadius
            let worldY = CGFloat(y1) * effectiveRadius
            let worldZ = CGFloat(z1) * effectiveRadius

            // Normalized Z: 1.0 is closest to viewer, 0.0 is farthest away
            let normZ = CGFloat(max(0.0, min(1.0, (z1 + 1.0) / 2.0)))

            // Perspective factor
            let perspective = cameraDistance / max(100.0, (cameraDistance - worldZ))

            let projectedX = worldX * perspective
            let projectedY = worldY * perspective

            // Scale: foreground items are larger (0.65 to 1.15)
            let baseScale = 0.65 + 0.40 * normZ
            let finalScale = min(1.25, max(0.55, baseScale * perspective))

            // Opacity: foreground is crisp 1.0, background recedes softly to 0.30
            let opacity = 0.28 + 0.72 * pow(Double(normZ), 1.3)

            // Blur: foreground has 0 blur, far background has subtle 3.8pt blur
            let blur = (1.0 - normZ) * 3.8

            // Subtle spatial rotation: fragments slightly face tangent to sphere
            let rotY = -sinTheta * 15.0

            return ProjectedFragment(
                fragment: fragment,
                x: projectedX,
                y: projectedY,
                depthZ: worldZ,
                normalizedZ: normZ,
                scale: finalScale,
                opacity: opacity,
                blurRadius: blur,
                zIndex: Double(worldZ),
                rotationY: rotY
            )
        }
    }
}
