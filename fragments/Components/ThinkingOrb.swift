//
//  ThinkingOrb.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI

// MARK: - Thinking Orb State

public enum ThinkingOrbState: String, CaseIterable, Identifiable, Hashable {
    case working
    case searching
    case solving
    case listening
    case connecting
    case weaving
    case composing
    case breathing
    case shaping

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Thinking Orb Size Preset

public struct ThinkingOrbSize: Equatable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public let rawValue: CGFloat

    public init(_ value: CGFloat) {
        self.rawValue = value
    }

    public init(floatLiteral value: Double) {
        self.rawValue = CGFloat(value)
    }

    public init(integerLiteral value: Int) {
        self.rawValue = CGFloat(value)
    }

    /// Chat-avatar scale (64px) — hand-tuned for avatars and cards
    public static let px64 = ThinkingOrbSize(64)

    /// Inline-text scale (20px) — hand-tuned for inline indicators
    public static let px20 = ThinkingOrbSize(20)

    public var isCompact: Bool {
        rawValue <= 32
    }
}

// MARK: - Thinking Orb SwiftUI Component

/// Thought-orb loading indicator for AI interfaces with nine hand-tuned animated states on a 2D canvas.
/// Matches the Libraries.dev / thinking-orbs specification.
public struct ThinkingOrb: View {
    public var state: ThinkingOrbState
    public var size: CGFloat
    public var speed: Double
    public var dark: Bool?
    public var paused: Bool
    public var tint: Color?

    @Environment(\.colorScheme) private var colorScheme
    @State private var frozenTime: Double = 0.0

    public init(
        state: ThinkingOrbState = .working,
        size: ThinkingOrbSize = .px64,
        speed: Double = 1.0,
        dark: Bool? = nil,
        paused: Bool = false,
        tint: Color? = nil
    ) {
        self.state = state
        self.size = size.rawValue
        self.speed = speed
        self.dark = dark
        self.paused = paused
        self.tint = tint
    }

    public var body: some View {
        let isDarkMode = dark ?? (colorScheme == .dark)
        let isCompact = size <= 32

        TimelineView(.animation(paused: paused)) { timeline in
            let rawTime = timeline.date.timeIntervalSinceReferenceDate
            let effectiveTime = (paused ? frozenTime : rawTime) * speed

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let baseRadius = (min(canvasSize.width, canvasSize.height) / 2) * 0.80

                // Color configuration
                let defaultColor = isDarkMode ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.15)
                let activeTint = tint ?? defaultColor

                switch state {
                case .working:
                    renderWorking(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .searching:
                    renderSearching(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .solving:
                    renderSolving(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .listening:
                    renderListening(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .connecting:
                    renderConnecting(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .weaving:
                    renderWeaving(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .composing:
                    renderComposing(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .breathing:
                    renderBreathing(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                case .shaping:
                    renderShaping(
                        context: &context,
                        center: center,
                        radius: baseRadius,
                        time: effectiveTime,
                        tint: activeTint,
                        isDark: isDarkMode,
                        isCompact: isCompact
                    )
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }

    // MARK: - 1. WORKING: Particles on Tilted Orbits
    private func renderWorking(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        if !isCompact {
            let auraRect = CGRect(x: center.x - radius * 0.85, y: center.y - radius * 0.85, width: radius * 1.7, height: radius * 1.7)
            context.fill(Circle().path(in: auraRect), with: .color(tint.opacity(isDark ? 0.08 : 0.04)))
        }

        struct OrbitDef {
            let tiltX: Double
            let tiltZ: Double
            let count: Int
            let speed: Double
            let phase: Double
            let ecc: Double
        }

        let planes: [OrbitDef] = isCompact ? [
            OrbitDef(tiltX: 0.40, tiltZ: -0.30, count: 8, speed: 1.8, phase: 0.0, ecc: 1.0),
            OrbitDef(tiltX: -0.45, tiltZ: 0.40, count: 7, speed: -1.5, phase: 1.5, ecc: 0.95)
        ] : [
            OrbitDef(tiltX: 0.42, tiltZ: -0.35, count: 16, speed: 1.6, phase: 0.0, ecc: 1.0),
            OrbitDef(tiltX: -0.50, tiltZ: 0.45, count: 14, speed: -1.3, phase: 1.2, ecc: 0.95),
            OrbitDef(tiltX: 0.20, tiltZ: 0.70, count: 12, speed: 1.9, phase: 2.5, ecc: 0.90)
        ]

        struct P3D {
            let x: CGFloat; let y: CGFloat; let z: Double; let baseSize: CGFloat
        }

        var particles: [P3D] = []

        for p in planes {
            let currentAngle = time * p.speed + p.phase
            for i in 0..<p.count {
                let angle = currentAngle + (Double(i) / Double(p.count)) * 2.0 * .pi
                let ox = cos(angle) * Double(radius)
                let oy = sin(angle) * Double(radius) * p.ecc
                let oz = 0.0

                let cosX = cos(p.tiltX); let sinX = sin(p.tiltX)
                let cosZ = cos(p.tiltZ); let sinZ = sin(p.tiltZ)

                let y1 = oy * cosX - oz * sinX
                let z1 = oy * sinX + oz * cosX
                let x2 = ox * cosZ - y1 * sinZ
                let y2 = ox * sinZ + y1 * cosZ
                let z2 = z1

                let normZ = z2 / Double(radius)
                let px = center.x + CGFloat(x2)
                let py = center.y + CGFloat(y2)
                let dotSize = isCompact ? 1.4 : max(1.2, (radius / 32.0) * 2.2)

                particles.append(P3D(x: px, y: py, z: normZ, baseSize: dotSize))
            }
        }

        particles.sort { $0.z < $1.z }

        for pt in particles {
            let depth = (pt.z + 1.0) / 2.0
            let opacity = isCompact ? (0.35 + 0.65 * depth) : (0.20 + 0.80 * pow(depth, 1.4))
            let r = pt.baseSize * CGFloat(isCompact ? (0.8 + 0.4 * depth) : (0.65 + 0.55 * depth))
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)

            if !isCompact && depth > 0.75 {
                let glow = CGRect(x: pt.x - r * 1.8, y: pt.y - r * 1.8, width: r * 3.6, height: r * 3.6)
                context.fill(Circle().path(in: glow), with: .color(tint.opacity(opacity * 0.3)))
            }
            context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
        }
    }

    // MARK: - 2. SEARCHING: Scan Meridian Sweeps a Dotted Globe
    private func renderSearching(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let sweepAngle = (time * 2.2).truncatingRemainder(dividingBy: 2.0 * .pi)
        let latRings: [(phi: Double, count: Int)] = isCompact ? [
            (0.0, 10), (0.45, 8), (-0.45, 8)
        ] : [
            (0.0, 16), (0.35, 14), (-0.35, 14), (0.65, 10), (-0.65, 10), (0.88, 6), (-0.88, 6)
        ]

        for ring in latRings {
            let cosPhi = cos(ring.phi)
            let sinPhi = sin(ring.phi)
            let ringR = Double(radius) * cosPhi
            let ringY = -sinPhi * Double(radius)

            for i in 0..<ring.count {
                let theta = (Double(i) / Double(ring.count)) * 2.0 * .pi
                let x = center.x + CGFloat(cos(theta) * ringR)
                let y = center.y + CGFloat(ringY)

                var angleDiff = abs(theta - sweepAngle).truncatingRemainder(dividingBy: 2.0 * .pi)
                if angleDiff > .pi { angleDiff = 2.0 * .pi - angleDiff }

                let scanBeamWidth = isCompact ? 0.9 : 0.65
                let isHit = angleDiff < scanBeamWidth
                let highlight = isHit ? pow(1.0 - (angleDiff / scanBeamWidth), 2.0) : 0.0

                let baseOpacity = isCompact ? 0.28 : 0.18
                let opacity = min(1.0, baseOpacity + highlight * 0.82)
                let baseDot = isCompact ? 1.3 : max(1.1, (radius / 32.0) * 1.8)
                let r = baseDot * CGFloat(1.0 + highlight * 0.6)

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    // MARK: - 3. SOLVING: Bands Scramble and Click Back into Place
    private func renderSolving(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let cycle = 3.6
        let t = (time).truncatingRemainder(dividingBy: cycle)
        let isScrambling = t < 2.4
        let solveProgress = isScrambling ? 0.0 : min(1.0, (t - 2.4) / 0.5)

        let bands: [(yFrac: Double, speed: Double, count: Int)] = isCompact ? [
            (-0.4, 1.6, 7), (0.0, -1.9, 8), (0.4, 1.4, 7)
        ] : [
            (-0.6, 2.2, 10), (-0.25, -1.8, 12), (0.1, 2.5, 14), (0.45, -2.0, 12), (0.7, 1.7, 8)
        ]

        for (idx, b) in bands.enumerated() {
            let ringY = center.y + CGFloat(b.yFrac) * radius * 0.85
            let ringRadius = sqrt(max(0.1, 1.0 - b.yFrac * b.yFrac)) * Double(radius)

            let speedMod = isScrambling ? b.speed : (b.speed * (1.0 - solveProgress))
            let currentRot = time * speedMod

            for i in 0..<b.count {
                let baseAngle = (Double(i) / Double(b.count)) * 2.0 * .pi
                let alignedAngle = Double(i) * (2.0 * .pi / Double(b.count))
                let theta = isScrambling ? (baseAngle + currentRot) : (baseAngle + currentRot * (1.0 - solveProgress) + alignedAngle * solveProgress * 0.1)

                let z = cos(theta)
                if z < -0.1 && !isCompact { continue } // hidden back half

                let x = center.x + CGFloat(sin(theta) * ringRadius)
                let depth = (z + 1.0) / 2.0
                let opacity = 0.25 + 0.75 * depth
                let dotSize = isCompact ? 1.3 : max(1.1, (radius / 32.0) * 1.9) * CGFloat(0.75 + 0.35 * depth)

                let rect = CGRect(x: x - dotSize, y: ringY - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    // MARK: - 4. LISTENING: Waveform Rolling Through Latitude Rings
    private func renderListening(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let ringCount = isCompact ? 4 : 7
        let dotsPerRing = isCompact ? 10 : 16

        for ringIdx in 0..<ringCount {
            let normY = Double(ringIdx) / Double(ringCount - 1) * 2.0 - 1.0
            let baseY = center.y + CGFloat(normY) * radius * 0.75
            let ringR = sqrt(max(0.1, 1.0 - normY * normY)) * Double(radius)

            for dotIdx in 0..<dotsPerRing {
                let theta = (Double(dotIdx) / Double(dotsPerRing)) * 2.0 * .pi
                let x = center.x + CGFloat(cos(theta) * ringR)

                // Travelling wave
                let wave = sin(theta * 3.0 - time * 3.5 + normY * 2.0)
                let waveAmp = isCompact ? 1.5 : (radius * 0.08)
                let y = baseY + CGFloat(wave) * waveAmp

                let normWave = (wave + 1.0) / 2.0
                let opacity = 0.25 + 0.75 * normWave
                let dotSize = (isCompact ? 1.3 : max(1.1, (radius / 32.0) * 1.8)) * CGFloat(0.8 + 0.45 * normWave)

                let rect = CGRect(x: x - dotSize, y: y - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    // MARK: - 5. CONNECTING: Constellation Wiring Itself Together
    private func renderConnecting(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let nodeCount = isCompact ? 8 : 14
        struct Node { let x: CGFloat; let y: CGFloat; let z: Double; let id: Int }
        var nodes: [Node] = []

        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        for i in 0..<nodeCount {
            let phi = acos(1.0 - 2.0 * (Double(i) + 0.5) / Double(nodeCount))
            let theta = 2.0 * .pi * Double(i) / goldenRatio + time * 0.6

            let nx = cos(theta) * sin(phi)
            let ny = cos(phi)
            let nz = sin(theta) * sin(phi)

            let px = center.x + CGFloat(nx) * radius * 0.85
            let py = center.y + CGFloat(ny) * radius * 0.85
            nodes.append(Node(x: px, y: py, z: nz, id: i))
        }

        // Draw wiring links
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let n1 = nodes[i]; let n2 = nodes[j]
                let dx = n1.x - n2.x
                let dy = n1.y - n2.y
                let dist = sqrt(dx * dx + dy * dy)
                let maxDist = radius * (isCompact ? 1.0 : 0.8)

                if dist < maxDist {
                    let pulse = (sin(time * 2.5 + Double(i + j)) + 1.0) / 2.0
                    let alpha = (1.0 - (dist / maxDist)) * (0.15 + 0.45 * pulse)
                    var path = Path()
                    path.move(to: CGPoint(x: n1.x, y: n1.y))
                    path.addLine(to: CGPoint(x: n2.x, y: n2.y))
                    context.stroke(path, with: .color(tint.opacity(alpha)), lineWidth: isCompact ? 0.8 : 1.0)
                }
            }
        }

        // Draw nodes
        for n in nodes {
            let depth = (n.z + 1.0) / 2.0
            let pulse = (sin(time * 3.0 + Double(n.id)) + 1.0) / 2.0
            let opacity = 0.35 + 0.65 * depth * (0.7 + 0.3 * pulse)
            let dotSize = isCompact ? 1.4 : max(1.2, (radius / 32.0) * 2.1) * CGFloat(0.8 + 0.4 * pulse)
            let rect = CGRect(x: n.x - dotSize, y: n.y - dotSize, width: dotSize * 2, height: dotSize * 2)
            context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
        }
    }

    // MARK: - 6. WEAVING: Three Strands Plait Around the Sphere
    private func renderWeaving(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let strands = 3
        let dotsPerStrand = isCompact ? 14 : 26

        for s in 0..<strands {
            let strandOffset = Double(s) * (2.0 * .pi / Double(strands))
            for i in 0..<dotsPerStrand {
                let u = Double(i) / Double(dotsPerStrand) // 0 to 1 along strand
                let height = (u * 2.0 - 1.0) * Double(radius) * 0.82
                let ringR = sqrt(max(0.1, pow(Double(radius) * 0.85, 2.0) - height * height))

                let turns = 2.2
                let theta = u * turns * 2.0 * .pi + strandOffset + time * 1.5

                let x = center.x + CGFloat(cos(theta) * ringR)
                let y = center.y + CGFloat(height)
                let z = sin(theta)

                let depth = (z + 1.0) / 2.0
                let opacity = 0.20 + 0.80 * depth
                let dotSize = isCompact ? 1.3 : max(1.1, (radius / 32.0) * 2.0) * CGFloat(0.7 + 0.45 * depth)

                let rect = CGRect(x: x - dotSize, y: y - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    // MARK: - 7. COMPOSING: Undulating Multi-band Sash
    private func renderComposing(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let bandCount = isCompact ? 2 : 4
        let dotsCount = isCompact ? 18 : 32

        for b in 0..<bandCount {
            let bandPhase = Double(b) * 0.75
            let baseTilt = (Double(b) - Double(bandCount - 1) / 2.0) * 0.18

            for i in 0..<dotsCount {
                let theta = (Double(i) / Double(dotsCount)) * 2.0 * .pi + time * 1.2

                // Undulating harmonics
                let undulation = sin(theta * 2.0 + time * 2.0 + bandPhase) * 0.25 + cos(theta * 3.0 - time) * 0.12
                let yOffset = (baseTilt + undulation) * Double(radius) * 0.70

                let cosT = cos(theta)
                let sinT = sin(theta)
                let r = Double(radius) * 0.82

                let px = center.x + CGFloat(cosT * r)
                let py = center.y + CGFloat(yOffset + sinT * r * 0.25)
                let z = sinT

                let depth = (z + 1.0) / 2.0
                let opacity = 0.22 + 0.78 * pow(depth, 1.2)
                let dotSize = isCompact ? 1.3 : max(1.1, (radius / 32.0) * 2.0) * CGFloat(0.75 + 0.4 * depth)

                let rect = CGRect(x: px - dotSize, y: py - dotSize, width: dotSize * 2, height: dotSize * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
            }
        }
    }

    // MARK: - 8. BREATHING: Ring & Soft Core Slowly Morphing
    private func renderBreathing(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let breath = (sin(time * 1.6) + 1.0) / 2.0 // 0 to 1
        let currentRadius = radius * CGFloat(0.72 + 0.24 * breath)
        let dotCount = isCompact ? 12 : 24

        // Dotted expanding ring
        for i in 0..<dotCount {
            let angle = (Double(i) / Double(dotCount)) * 2.0 * .pi + time * 0.4
            let wobble = sin(angle * 3.0 + time * 2.0) * Double(radius) * 0.05
            let r = currentRadius + CGFloat(wobble)

            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r

            let dotOpacity = 0.35 + 0.65 * (1.0 - breath * 0.3)
            let dotSize = isCompact ? 1.4 : max(1.2, (radius / 32.0) * 2.1)

            let rect = CGRect(x: x - dotSize, y: y - dotSize, width: dotSize * 2, height: dotSize * 2)
            context.fill(Circle().path(in: rect), with: .color(tint.opacity(dotOpacity)))
        }

        // Inner glowing core
        let coreR = radius * CGFloat(0.28 + 0.12 * (1.0 - breath))
        let coreRect = CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)
        context.fill(Circle().path(in: coreRect), with: .color(tint.opacity(0.12 + 0.20 * breath)))
    }

    // MARK: - 9. SHAPING: Parametric Morphing Circle -> Triangle -> Square
    private func renderShaping(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        tint: Color,
        isDark: Bool,
        isCompact: Bool
    ) {
        let period = 3.0
        let phase = (time / period).truncatingRemainder(dividingBy: 3.0)
        let stateIdx = Int(phase)
        let progress = phase - Double(stateIdx)
        let ease = (1.0 - cos(progress * .pi)) / 2.0 // smooth ease in/out

        let dotCount = isCompact ? 12 : 24
        let baseR = radius * 0.80

        for i in 0..<dotCount {
            let angle = (Double(i) / Double(dotCount)) * 2.0 * .pi + time * 0.5

            // 1. Circle pos
            let cX = cos(angle) * Double(baseR)
            let cY = sin(angle) * Double(baseR)

            // 2. Triangle pos
            let triAngle = angle.truncatingRemainder(dividingBy: 2.0 * .pi / 3.0) - (.pi / 3.0)
            let triR = Double(baseR) * (cos(.pi / 3.0) / cos(triAngle))
            let tX = cos(angle) * min(Double(baseR) * 1.3, triR)
            let tY = sin(angle) * min(Double(baseR) * 1.3, triR)

            // 3. Square pos
            let sqAngle = (angle + .pi / 4.0).truncatingRemainder(dividingBy: .pi / 2.0) - (.pi / 4.0)
            let sqR = Double(baseR) * (cos(.pi / 4.0) / cos(sqAngle))
            let sX = cos(angle) * min(Double(baseR) * 1.25, sqR)
            let sY = sin(angle) * min(Double(baseR) * 1.25, sqR)

            var px = 0.0; var py = 0.0

            switch stateIdx {
            case 0: // Circle -> Triangle
                px = cX * (1.0 - ease) + tX * ease
                py = cY * (1.0 - ease) + tY * ease
            case 1: // Triangle -> Square
                px = tX * (1.0 - ease) + sX * ease
                py = tY * (1.0 - ease) + sY * ease
            default: // Square -> Circle
                px = sX * (1.0 - ease) + cX * ease
                py = sY * (1.0 - ease) + cY * ease
            }

            let x = center.x + CGFloat(px)
            let y = center.y + CGFloat(py)
            let dotSize = isCompact ? 1.4 : max(1.2, (radius / 32.0) * 2.1)
            let rect = CGRect(x: x - dotSize, y: y - dotSize, width: dotSize * 2, height: dotSize * 2)

            context.fill(Circle().path(in: rect), with: .color(tint.opacity(0.85)))
        }
    }
}

// MARK: - ThinkingOrb Showcase & Previews

#if DEBUG
public struct ThinkingOrbGalleryView: View {
    @State private var selectedState: ThinkingOrbState = .searching
    @State private var speed: Double = 1.0
    @State private var isPaused: Bool = false
    @State private var isDarkMode: Bool = true

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Hero Featured Orb
                    VStack(spacing: 14) {
                        ThinkingOrb(
                            state: selectedState,
                            size: .px64,
                            speed: speed,
                            dark: isDarkMode,
                            paused: isPaused
                        )
                        .frame(width: 80, height: 80)

                        Text("<ThinkingOrb state=\"\(selectedState.rawValue)\" size={64} />")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 20)

                    // Nine States Grid (64px)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ALL 9 STATES (64PX & 20PX)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(ThinkingOrbState.allCases) { orbState in
                                Button {
                                    selectedState = orbState
                                } label: {
                                    VStack(spacing: 8) {
                                        ThinkingOrb(
                                            state: orbState,
                                            size: .px64,
                                            speed: speed,
                                            dark: isDarkMode,
                                            paused: isPaused
                                        )
                                        .frame(width: 64, height: 64)

                                        HStack(spacing: 6) {
                                            ThinkingOrb(
                                                state: orbState,
                                                size: .px20,
                                                speed: speed,
                                                dark: isDarkMode,
                                                paused: isPaused
                                            )
                                            Text(orbState.displayName)
                                                .font(.system(size: 12, weight: selectedState == orbState ? .bold : .medium, design: .rounded))
                                        }
                                        .foregroundStyle(selectedState == orbState ? .primary : .secondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(selectedState == orbState ? Color.primary : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ThinkingOrbs")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}

#Preview("ThinkingOrb Gallery - Dark") {
    ThinkingOrbGalleryView()
        .preferredColorScheme(.dark)
}

#Preview("ThinkingOrb Gallery - Light") {
    ThinkingOrbGalleryView()
        .preferredColorScheme(.light)
}
#endif
