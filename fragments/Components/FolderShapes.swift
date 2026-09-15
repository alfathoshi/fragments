//
//  FolderShapes.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/13/26.
//

import SwiftUI

// MARK: - 1. Folder Back / Body Shape

/// Native SwiftUI Shape for the Folder Back / Body layer.
///
/// Recreates the 172 × 171 silhouette with smooth continuous rounded corners
/// and responsive scaling for any frame size.
public struct FolderBackShape: Shape {
    /// Corner radius ratio relative to the smallest dimension (default: 20.0%)
    public var cornerRadiusRatio: CGFloat

    public init(cornerRadiusRatio: CGFloat = 0.20) {
        self.cornerRadiusRatio = cornerRadiusRatio
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0 && rect.height > 0 else { return Path() }
        let maxCorner = min(rect.width, rect.height) / 2
        let nominalRadius = min(rect.width, rect.height) * cornerRadiusRatio
        let radius = min(nominalRadius, maxCorner)
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}

// MARK: - 2. Folder Front Cover Shape

/// Native SwiftUI Shape for the Folder Front Cover layer.
///
/// Recreates the front cover silhouette preserving the distinctive folder-tab profile:
/// - Rounded top-left corner on the tab
/// - Raised horizontal tab section
/// - Smooth S-curve transition from the tab into the main body
/// - Flat horizontal body top edge
/// - Rounded top-right corner
/// - Rounded bottom corners matching the back folder silhouette
public struct FolderCoverShape: Shape {
    /// Ratio of the raised tab width relative to total width (default: 20.0%)
    public var tabWidthRatio: CGFloat
    /// Ratio of the S-curve transition width relative to total width (default: 15.0%)
    public var sCurveWidthRatio: CGFloat
    /// Ratio of the tab drop distance relative to total height (default: 20.0%)
    public var tabDropRatio: CGFloat
    /// Ratio of the top-left tab corner radius relative to total height (default: 20.0%)
    public var tabTopLeftRadiusRatio: CGFloat
    /// Ratio of the top-right corner radius relative to total height (default: 32.0%)
    public var topRightRadiusRatio: CGFloat
    /// Ratio of the bottom corner radii relative to total height (default: 32.0%)
    public var bottomRadiusRatio: CGFloat

    public init(
        tabWidthRatio: CGFloat = 0.20,
        sCurveWidthRatio: CGFloat = 0.15,
        tabDropRatio: CGFloat = 0.20,
        tabTopLeftRadiusRatio: CGFloat = 0.20,
        topRightRadiusRatio: CGFloat = 0.32,
        bottomRadiusRatio: CGFloat = 0.32
    ) {
        self.tabWidthRatio = tabWidthRatio
        self.sCurveWidthRatio = sCurveWidthRatio
        self.tabDropRatio = tabDropRatio
        self.tabTopLeftRadiusRatio = tabTopLeftRadiusRatio
        self.topRightRadiusRatio = topRightRadiusRatio
        self.bottomRadiusRatio = bottomRadiusRatio
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 && rect.height > 0 else { return path }

        // Proportional geometric parameters based on frame dimensions
        let tabWidth = rect.width * tabWidthRatio
        let sCurveWidth = rect.width * sCurveWidthRatio
        let tabDrop = rect.height * tabDropRatio
        let rTabTopLeft = min(rect.height * tabTopLeftRadiusRatio, min(tabWidth, rect.height * 0.45))
        let rTopRight = min(rect.height * topRightRadiusRatio, min(rect.width - tabWidth - sCurveWidth, (rect.height - tabDrop) * 0.9))
        let rBottom = min(rect.height * bottomRadiusRatio, min(rect.width * 0.45, rect.height * 0.45))

        // 1. Start on the left edge just below the top-left rounded corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rTabTopLeft))

        // 2. Top-left corner of the tab
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + rTabTopLeft, y: rect.minY),
            radius: rTabTopLeft
        )

        // 3. Tab horizontal top edge
        path.addLine(to: CGPoint(x: rect.minX + tabWidth, y: rect.minY))

        // 4. Smooth S-curve (cubic Bézier) transition into the main body top edge
        let tabTransitionEnd = CGPoint(x: rect.minX + tabWidth + sCurveWidth, y: rect.minY + tabDrop)
        let cp1 = CGPoint(x: rect.minX + tabWidth + (sCurveWidth * 0.5), y: rect.minY)
        let cp2 = CGPoint(x: rect.minX + tabWidth + (sCurveWidth * 0.5), y: rect.minY + tabDrop)
        path.addCurve(to: tabTransitionEnd, control1: cp1, control2: cp2)

        // 5. Main body top edge across to the top-right corner
        let bodyRightEdgeStart = CGPoint(x: rect.maxX - rTopRight, y: rect.minY + tabDrop)
        path.addLine(to: bodyRightEdgeStart)

        // 6. Top-right corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY + tabDrop),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tabDrop + rTopRight),
            radius: rTopRight
        )

        // 7. Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rBottom))

        // 8. Bottom-right corner
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - rBottom, y: rect.maxY),
            radius: rBottom
        )

        // 9. Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + rBottom, y: rect.maxY))

        // 10. Bottom-left corner
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - rBottom),
            radius: rBottom
        )

        // 11. Left edge back up to start
        path.closeSubpath()

        return path
    }
}

// MARK: - 3. Interactive Shape Preview & Tuning Canvas

#if DEBUG
#Preview("Folder Shapes Tuning") {
    FolderShapes_Previews.FolderShapesTuningPreview()
}

struct FolderShapes_Previews: PreviewProvider {
    static var previews: some View {
        FolderShapesTuningPreview()
    }

    struct FolderShapesTuningPreview: View {
        // Tunable parameters
        @State private var tabWidthRatio: CGFloat = 0.20
        @State private var tabDropRatio: CGFloat = 0.20
        @State private var sCurveWidthRatio: CGFloat = 0.25
        @State private var tabTopLeftRadiusRatio: CGFloat = 0.20
        @State private var topRightRadiusRatio: CGFloat = 0.32
        @State private var bottomRadiusRatio: CGFloat = 0.32
        @State private var backCornerRatio: CGFloat = 0.20

        // Display modes
        @State private var showWireframe: Bool = false
        @State private var showCombined: Bool = true
        @State private var shapeScale: CGFloat = 1.2

        private var coverShape: FolderCoverShape {
            FolderCoverShape(
                tabWidthRatio: tabWidthRatio,
                sCurveWidthRatio: sCurveWidthRatio,
                tabDropRatio: tabDropRatio,
                tabTopLeftRadiusRatio: tabTopLeftRadiusRatio,
                topRightRadiusRatio: topRightRadiusRatio,
                bottomRadiusRatio: bottomRadiusRatio
            )
        }

        private var backShape: FolderBackShape {
            FolderBackShape(cornerRadiusRatio: backCornerRatio)
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 28) {
                        // Interactive Preview Stage
                        previewStage
                            .padding(.top, 16)

                        // Mode Selector Toggles
                        HStack(spacing: 12) {
                            Button {
                                showCombined.toggle()
                            } label: {
                                Label(showCombined ? "Combined View" : "Separated View", systemImage: showCombined ? "square.stack.3d.up.fill" : "square.split.2x1")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }

                            Button {
                                showWireframe.toggle()
                            } label: {
                                Label(showWireframe ? "Wireframe" : "Glass Shading", systemImage: showWireframe ? "circle.grid.cross.fill" : "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }

                            Button("Reset") {
                                tabWidthRatio = 0.20
                                tabDropRatio = 0.20
                                sCurveWidthRatio = 0.15
                                tabTopLeftRadiusRatio = 0.20
                                topRightRadiusRatio = 0.32
                                bottomRadiusRatio = 0.32
                                backCornerRatio = 0.20
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Tuning Sliders
                        tuningSlidersSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .background(Color(white: 0.10).ignoresSafeArea())
                .navigationTitle("Folder Shapes Tuning")
                .navigationBarTitleDisplayMode(.inline)
            }
        }

        // MARK: - Visual Stage

        private var previewStage: some View {
            ZStack {
                // Background grid pattern
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(white: 0.14))
                    .frame(height: 320)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if showCombined {
                    combinedFolderView
                } else {
                    separatedShapesView
                }
            }
            .frame(height: 320)
        }

        // MARK: - Combined Layer View

        private var combinedFolderView: some View {
            let baseW: CGFloat = 172 * shapeScale
            let baseH: CGFloat = 171 * shapeScale
            let coverH: CGFloat = 99 * shapeScale

            return ZStack(alignment: .bottom) {
                // 1. Back Body
                Group {
                    if showWireframe {
                        backShape
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    } else {
                        backShape
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.85).opacity(0.35), Color(red: 0.20, green: 0.26, blue: 0.32).opacity(0.40)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .background(backShape.fill(.ultraThinMaterial))
                            .overlay(backShape.stroke(Color.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                    }
                }
                .frame(width: baseW, height: baseH)

                // Dummy card tucked inside
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: baseW * 0.77, height: baseH * 0.74)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -4, y: -baseH * 0.12)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                // 2. Front Cover
                Group {
                    if showWireframe {
                        coverShape
                            .stroke(Color.yellow, lineWidth: 2)
                    } else {
                        coverShape
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color(white: 0.88).opacity(0.3), Color(red: 0.22, green: 0.28, blue: 0.34).opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .background(coverShape.fill(.ultraThinMaterial))
                            .overlay(
                                coverShape.stroke(
                                    LinearGradient(
                                        stops: [.init(color: .white.opacity(0.7), location: 0), .init(color: .white.opacity(0.2), location: 1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    }
                }
                .frame(width: baseW, height: coverH)
            }
        }

        // MARK: - Separated Shapes View

        private var separatedShapesView: some View {
            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Group {
                        if showWireframe {
                            backShape.stroke(Color.cyan, lineWidth: 2)
                        } else {
                            backShape
                                .fill(LinearGradient(colors: [.cyan.opacity(0.4), .blue.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                                .overlay(backShape.stroke(Color.white.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .frame(width: 120, height: 119)

                    Text("Back: 172 × 171")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    Group {
                        if showWireframe {
                            coverShape.stroke(Color.yellow, lineWidth: 2)
                        } else {
                            coverShape
                                .fill(LinearGradient(colors: [.yellow.opacity(0.4), .orange.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                                .overlay(coverShape.stroke(Color.white.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .frame(width: 120, height: 69)

                    Text("Cover: 172 × 99")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }

        // MARK: - Sliders Section

        private var tuningSlidersSection: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shape Geometry Tuning")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                sliderRow(
                    title: "Tab Width Ratio",
                    value: $tabWidthRatio,
                    range: 0.15...0.60,
                    formatted: String(format: "%.1f%%", tabWidthRatio * 100)
                )

                sliderRow(
                    title: "Tab Drop (Step Depth)",
                    value: $tabDropRatio,
                    range: 0.05...0.40,
                    formatted: String(format: "%.1f%%", tabDropRatio * 100)
                )

                sliderRow(
                    title: "S-Curve Transition Width",
                    value: $sCurveWidthRatio,
                    range: 0.01...0.25,
                    formatted: String(format: "%.1f%%", sCurveWidthRatio * 100)
                )

                sliderRow(
                    title: "Tab Top-Left Radius",
                    value: $tabTopLeftRadiusRatio,
                    range: 0.0...0.30,
                    formatted: String(format: "%.1f%%", tabTopLeftRadiusRatio * 100)
                )

                sliderRow(
                    title: "Top-Right Corner Radius",
                    value: $topRightRadiusRatio,
                    range: 0.0...0.40,
                    formatted: String(format: "%.1f%%", topRightRadiusRatio * 100)
                )

                sliderRow(
                    title: "Cover Bottom Radius",
                    value: $bottomRadiusRatio,
                    range: 0.05...0.45,
                    formatted: String(format: "%.1f%%", bottomRadiusRatio * 100)
                )

                sliderRow(
                    title: "Back Body Corner Radius",
                    value: $backCornerRatio,
                    range: 0.05...0.35,
                    formatted: String(format: "%.1f%%", backCornerRatio * 100)
                )

                sliderRow(
                    title: "Preview Scale",
                    value: $shapeScale,
                    range: 0.8...1.6,
                    formatted: String(format: "%.2fx", shapeScale)
                )
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.14)))
        }

        private func sliderRow(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, formatted: String) -> some View {
            VStack(spacing: 4) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(formatted)
                        .font(.caption.monospaced())
                        .foregroundStyle(.cyan)
                }
                Slider(value: value, in: range)
                    .tint(.cyan)
            }
        }
    }
}
#endif
