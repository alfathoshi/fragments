//
//  MomentFolder.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/13/26.
//

import SwiftUI

public struct MomentFolder<CardContent: View>: View {
    // MARK: - Properties

    public let items: [FolderItem]
    @Binding public var isOpen: Bool
    public var size: CGSize
    public var isLocked: Bool
    public var folderColor: Color?
    public var onTapFolder: (() -> Void)?
    public var onTapItem: ((FolderItem) -> Void)?
    public var cardBuilder: ((FolderItem, Int) -> CardContent)?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Internal Gesture & Interaction State

    @GestureState private var dragOffset: CGFloat = 0
    @State private var hoveredIndex: Int? = nil

    // MARK: - Initializers

    /// Initializer with custom card view builder
    public init(
        items: [FolderItem],
        isOpen: Binding<Bool>,
        size: CGSize = CGSize(width: 172, height: 171),
        isLocked: Bool = false,
        folderColor: Color? = nil,
        onTapFolder: (() -> Void)? = nil,
        onTapItem: ((FolderItem) -> Void)? = nil,
        @ViewBuilder cardBuilder: @escaping (FolderItem, Int) -> CardContent
    ) {
        self.items = items
        self._isOpen = isOpen
        self.size = size
        self.isLocked = isLocked
        self.folderColor = folderColor
        self.onTapFolder = onTapFolder
        self.onTapItem = onTapItem
        self.cardBuilder = cardBuilder
    }

    /// Default initializer using standard glass/gradient cards
    public init(
        items: [FolderItem],
        isOpen: Binding<Bool>,
        size: CGSize = CGSize(width: 172, height: 171),
        isLocked: Bool = false,
        folderColor: Color? = nil,
        onTapFolder: (() -> Void)? = nil,
        onTapItem: ((FolderItem) -> Void)? = nil
    ) where CardContent == DefaultFolderCardView {
        self.items = items
        self._isOpen = isOpen
        self.size = size
        self.isLocked = isLocked
        self.folderColor = folderColor
        self.onTapFolder = onTapFolder
        self.onTapItem = onTapItem
        self.cardBuilder = { item, index in
            DefaultFolderCardView(item: item, index: index, size: CGSize(width: size.width * 0.77, height: size.height * 0.74))
        }
    }

    // MARK: - Dynamic Sizing & Geometry

    private var cardWidth: CGFloat { size.width * 0.77 }
    private var cardHeight: CGFloat { size.height * 0.74 }
    private var coverHeight: CGFloat { size.height * 0.575 }

    /// Drag progress normalized between 0.0 (closed) and 1.0 (open)
    private var currentProgress: CGFloat {
        if isLocked {
            return isOpen ? 1.0 : 0.0
        }
        let base: CGFloat = isOpen ? 1.0 : 0.0
        let dragFactor = -dragOffset / (size.height * 0.5)
        return min(max(base + dragFactor, 0.0), 1.25)
    }

    private var isExpanded: Bool {
        currentProgress > 0.4
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if isLocked {
                folderZStack
            } else {
                folderZStack
                    .onTapGesture {
                        if let customAction = onTapFolder {
                            customAction()
                        } else {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0)) {
                                isOpen.toggle()
                            }
                        }
                    }
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                let predictedEnd = value.predictedEndTranslation.height
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0)) {
                                    if predictedEnd < -30 {
                                        isOpen = true
                                    } else if predictedEnd > 30 {
                                        isOpen = false
                                    } else {
                                        isOpen = currentProgress > 0.5
                                    }
                                }
                            }
                    )
            }
        }
    }

    private var folderZStack: some View {
        ZStack(alignment: .bottom) {
            // LAYER 1: Back / Folder Body
            backFolderLayer

            // LAYER 2: Preview Content Cards (Behind front cover, above folder body)
            previewContentLayer

            // LAYER 3: Front / Folder Cover (Visually occludes lower portions of cards)
            frontCoverLayer
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    // MARK: - Layer 1: Back Folder Layer

    private var backFolderLayer: some View {
        FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
            // 1. BACKGROUND BLUR: progressive, start 0, end 40
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.35),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .background(
                FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                    .fill(.thinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.20),
                                .init(color: .black.opacity(0.80), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            // 2. FILL (20%): linear top to bottom FFFFFF to 000000, or changes based on color options
            .overlay {
                if let color = folderColor {
                    FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(0.35),
                                    color.opacity(0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white, location: 0.0),
                                    .init(color: Color.black, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.20)
                }
            }
            // 3. NOISE: x 0.64, density 69%, 6C6C6C 10%
            .overlay(
                FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                    .fill(ImagePaint(image: Image(uiImage: NoiseTexture.coverNoiseImage), scale: 0.64))
                    .opacity(0.10)
            )
            // 4. INNER SHADOW: y 0.8, blur 3, FFFFFF 25%
            .overlay(
                FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                    .stroke(Color.white.opacity(0.25), lineWidth: 2.0)
                    .blur(radius: 3.0)
                    .offset(y: 0.8)
                    .mask(FolderBackShape(cornerRadiusRatio: 32.0 / 171.0))
            )
            // 5. SPECULAR STROKE
            .overlay(
                FolderBackShape(cornerRadiusRatio: 32.0 / 171.0)
                    .stroke(
                        LinearGradient(
                            stops: colorScheme == .dark ? [
                                .init(color: Color.white.opacity(0.25), location: 0.0),
                                .init(color: Color.white.opacity(0.10), location: 0.4),
                                .init(color: Color.white.opacity(0.02), location: 1.0)
                            ] : [
                                .init(color: Color.white.opacity(0.38), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.4),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            )
            // 3D perspective: subtly tilts back and scales on open
            .rotation3DEffect(
                .degrees(isExpanded ? -5.0 * currentProgress : 0),
                axis: (x: 1.0, y: 0.0, z: 0.0),
                anchor: .bottom,
                perspective: 0.6
            )
            .scaleEffect(isExpanded ? 1.0 - (0.02 * currentProgress) : 1.0)
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Layer 2: Preview Content Layer

    private var displayItems: [FolderItem] {
        Array(items.prefix(5))
    }

    private var previewContentLayer: some View {
        ZStack {
            ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                cardItemView(item: item, index: index, totalCount: displayItems.count)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        // Center the card stack vertically relative to the folder body
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func cardItemView(item: FolderItem, index: Int, totalCount: Int) -> some View {
        let total = CGFloat(max(totalCount, 1))
        // Normalized index centered around 0 (e.g. -1, 0, 1 for 3 items)
        let normalizedIndex: CGFloat = total > 1 ? (CGFloat(index) - (total - 1) / 2.0) : 0

        // Closed state resting parameters
        let closedRotation: CGFloat = closedAngle(for: index, total: totalCount)
        let closedX: CGFloat = closedOffsetX(for: index, total: totalCount)
        let closedY: CGFloat = closedOffsetY(for: index, total: totalCount)

        // Open state fanned parameters
        let openRotation: CGFloat = normalizedIndex * 9.5
        let openX: CGFloat = normalizedIndex * (cardWidth * 0.28)
        let openY: CGFloat = -size.height * 0.38 - (abs(normalizedIndex) * 5.0)
        let open3DrotY: CGFloat = normalizedIndex * 6.5
        let open3DrotX: CGFloat = -4.0

        // Interpolated transform values based on currentProgress
        let currentRotation = closedRotation + (openRotation - closedRotation) * currentProgress
        let currentX = closedX + (openX - closedX) * currentProgress
        let currentY = closedY + (openY - closedY) * currentProgress
        let current3DrotY = open3DrotY * currentProgress
        let current3DrotX = open3DrotX * currentProgress

        let isHovered = hoveredIndex == index

        Group {
            if let customBuilder = cardBuilder {
                customBuilder(item, index)
            } else {
                DefaultFolderCardView(item: item, index: index, size: CGSize(width: cardWidth, height: cardHeight))
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.32 : 0.20),
            radius: isExpanded ? 8 : 4,
            x: isExpanded ? (normalizedIndex * 2) : -1.5,
            y: isExpanded ? 6 : 3
        )
        .rotation3DEffect(
            .degrees(current3DrotY),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .rotation3DEffect(
            .degrees(current3DrotX),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.5
        )
        .rotationEffect(.degrees(currentRotation))
        .offset(x: currentX, y: currentY)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .zIndex(Double(index))
        .onTapGesture {
            if isExpanded {
                onTapItem?(item)
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0)) {
                    isOpen = true
                }
            }
        }
    }

    // MARK: - Layer 3: Front Folder Cover

    private var frontCoverLayer: some View {
        FolderCoverShape()
            // 1. BACKGROUND BLUR: progressive, start 0, end 40
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.35),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .background(
                FolderCoverShape()
                    .fill(.thinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.20),
                                .init(color: .black.opacity(0.80), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            // 2. FILL: linear top to bottom (adaptive smoked acrylic in dark mode vs Figma frosted white in light mode)
            .overlay(
                FolderCoverShape()
                    .fill(
                        LinearGradient(
                            stops: colorScheme == .dark ? [
                                .init(color: Color(white: 0.32), location: 0.0),
                                .init(color: Color(white: 0.20), location: 0.66),
                                .init(color: Color(white: 0.16), location: 1.0)
                            ] : [
                                .init(color: Color(red: 230/255, green: 230/255, blue: 230/255), location: 0.0),
                                .init(color: Color.white, location: 0.66),
                                .init(color: Color.white, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(colorScheme == .dark ? 0.45 : 0.60)
            )
            // 3. NOISE: x 0.64, density 69%, 6C6C6C 10%
            .overlay(
                FolderCoverShape()
                    .fill(ImagePaint(image: Image(uiImage: NoiseTexture.coverNoiseImage), scale: 0.64))
                    .opacity(0.10)
            )
            // 5. INNER SHADOW: y 0.8, blur 3
            .overlay(
                FolderCoverShape()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.25), lineWidth: 2.0)
                    .blur(radius: 3.0)
                    .offset(y: 0.8)
                    .mask(FolderCoverShape())
            )
            // 6. SPECULAR STROKE
            .overlay(
                FolderCoverShape()
                    .stroke(
                        LinearGradient(
                            stops: colorScheme == .dark ? [
                                .init(color: Color.white.opacity(0.40), location: 0.0),
                                .init(color: Color.white.opacity(0.18), location: 0.35),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ] : [
                                .init(color: Color.white.opacity(0.75), location: 0.0),
                                .init(color: Color.white.opacity(0.35), location: 0.35),
                                .init(color: Color.white.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
            )
            
            // 3D perspective: subtly tilts forward on open to expose the pocket interior
            .rotation3DEffect(
                .degrees(isExpanded ? -30.0 * currentProgress : 0),
                axis: (x: 1.0, y: 0.0, z: 0.0),
                anchor: .bottom,
                perspective: 0.6
            )
            .offset(y: isExpanded ? (size.height * 0.025 * currentProgress) : 0)
            .frame(width: size.width, height: coverHeight)
    }

    // MARK: - Helper Closed Coordinates

    private func closedAngle(for index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0 }
        switch index % 3 {
        case 0: return -7.0
        case 1: return 0.0
        default: return 1.5
        }
    }

    private func closedOffsetX(for index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0 }
        switch index % 3 {
        case 0: return -4.0
        case 1: return 0.0
        default: return 4.5
        }
    }

    private func closedOffsetY(for index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0 }
        switch index % 3 {
        case 0: return 4.0
        case 1: return 0.0
        default: return 2.0
        }
    }
}

// MARK: - Default Folder Card View

/// Beautiful translucent preview card with rounded corners, subtle rim highlight,
/// and support for SF Symbols, images, and vibrant Apple-style gradients.
public struct DefaultFolderCardView: View {
    public let item: FolderItem
    public let index: Int
    public var size: CGSize

    public init(item: FolderItem, index: Int = 0, size: CGSize = CGSize(width: 133, height: 126)) {
        self.item = item
        self.index = index
        self.size = size
    }

    public var body: some View {
        let fragment = item.toFragment()
        let resolvedImage: UIImage? = {
            if let imageName = item.imageName, let uiImage = UIImage(named: imageName) {
                return uiImage
            }
            if fragment.type == .video {
                return fragment.videoThumbnail
            }
            return fragment.thumbnailImage ?? fragment.loadedImage
        }()

        ZStack {
            // Card background: image or gradient
            if let uiImage = resolvedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: item.resolvedGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    // Subtle geometric accent shine
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .blur(radius: 12)
                        .offset(x: -size.width * 0.2, y: -size.height * 0.2)
                )

                // Content inside card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        if let tag = item.tag {
                            Text(tag)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.ultraThinMaterial))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    Spacer()

                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 0.75)
        )
    }
}

// MARK: - Procedural Noise Texture (Figma Seed: 4517)

public enum NoiseTexture {
    public static let image: UIImage = {
        let width = 128
        let height = 128
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // Deterministic pseudo-random sequence matching Figma's noise seed 4517
        var seed: UInt64 = 4517
        func nextRandom() -> UInt8 {
            seed = (seed &* 6364136223846793005) &+ 1442695040888963407
            return UInt8((seed >> 32) & 0xFF)
        }

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let gray = nextRandom()
            let alpha = UInt8(CGFloat(nextRandom()) * 0.15) // subtle tactile grain
            pixels[i] = gray     // R
            pixels[i + 1] = gray // G
            pixels[i + 2] = gray // B
            pixels[i + 3] = alpha // A
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return UIImage()
        }

        return UIImage(cgImage: cgImage)
    }()

    /// Dedicated cover noise: seed 4517, density 69%, #6C6C6C (opacity 10% in SwiftUI)
    public static let coverNoiseImage: UIImage = {
        let width = 128
        let height = 128
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        var seed: UInt64 = 4517
        func nextRandom() -> UInt8 {
            seed = (seed &* 6364136223846793005) &+ 1442695040888963407
            return UInt8((seed >> 32) & 0xFF)
        }

        let gray: UInt8 = 0x6C // #6C6C6C

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let randDensity = nextRandom()
            // Density 69%: ~69% probability (176 / 255 ≈ 0.69)
            if randDensity < 176 {
                pixels[i] = gray     // R
                pixels[i + 1] = gray // G
                pixels[i + 2] = gray // B
                pixels[i + 3] = 255  // Solid pixel (10% opacity applied in SwiftUI)
            } else {
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return UIImage()
        }

        return UIImage(cgImage: cgImage)
    }()
}
