//
//  FragmentSphere.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public struct FragmentSphere: View {
    public let fragments: [Fragment]
    public var onSelectFragment: ((Fragment) -> Void)? = nil

    // Sphere state
    @State private var rotationAngle: Double = 0.0
    @State private var tiltAngle: Double = 0.0
    @State private var dragVelocity: Double = 0.0
    @State private var isDragging: Bool = false
    @State private var animTimer: Timer? = nil
    @State private var time: Double = 0.0

    // Stardust ambient spatial particles (deterministic)
    private struct SpatialParticle: Identifiable {
        let id = UUID()
        let phi: Double
        let theta: Double
        let radiusFactor: Double
        let size: CGFloat
        let opacity: Double
    }

    private static let particles: [SpatialParticle] = {
        var items: [SpatialParticle] = []
        for i in 0..<28 {
            let phi = sin(Double(i) * 1.8) * 0.95
            let theta = Double(i) * 0.72
            let rFactor = 0.75 + Double(i % 5) * 0.08
            let size = CGFloat(2.0 + Double(i % 3) * 1.5)
            let opacity = 0.15 + Double(i % 4) * 0.10
            items.append(SpatialParticle(phi: phi, theta: theta, radiusFactor: rFactor, size: size, opacity: opacity))
        }
        return items
    }()

    public init(
        fragments: [Fragment],
        onSelectFragment: ((Fragment) -> Void)? = nil
    ) {
        self.fragments = fragments
        self.onSelectFragment = onSelectFragment
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = min(size.width * 0.42, 170.0)
            let projected = SpherePositionEngine.project(
                fragments: fragments,
                radius: radius,
                rotationAngle: rotationAngle,
                tiltAngle: tiltAngle,
                time: time
            ).sorted(by: { $0.zIndex < $1.zIndex })

            ZStack {
                // Ethereal ambient center aura
                RadialGradient(
                    colors: [
                        Color.blue.opacity(0.08),
                        Color.purple.opacity(0.04),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: radius * 1.5
                )
                .frame(width: radius * 2.8, height: radius * 2.8)
                .allowsHitTesting(false)

                // Faint spatial stardust particles for depth grounding
                ForEach(Self.particles) { particle in
                    particleView(particle: particle, radius: radius)
                }

                // Render Fragments sorted back-to-front
                ForEach(projected) { item in
                    FragmentNode(
                        fragment: item.fragment,
                        normalizedZ: item.normalizedZ,
                        onTap: {
                            // Only allow tapping fragments in front half for intuitive spatial feel
                            if item.normalizedZ > 0.30 {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onSelectFragment?(item.fragment)
                            }
                        }
                    )
                    .scaleEffect(item.scale)
                    .opacity(item.opacity)
                    .blur(radius: item.blurRadius)
                    .rotation3DEffect(
                        .degrees(item.rotationY),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        perspective: 0.5
                    )
                    .offset(x: item.x, y: item.y)
                    .zIndex(item.zIndex)
                    .allowsHitTesting(item.normalizedZ > 0.35)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        handleDragChanged(value: value, radius: radius)
                    }
                    .onEnded { value in
                        handleDragEnded(value: value, radius: radius)
                    }
            )
        }
        .onAppear {
            startPhysicsLoop()
        }
        .onDisappear {
            stopPhysicsLoop()
        }
    }

    // MARK: - Ambient Stardust Particle
    @ViewBuilder
    private func particleView(particle: SpatialParticle, radius: CGFloat) -> some View {
        let angleTheta = particle.theta + rotationAngle
        let anglePhi = particle.phi
        let cosPhi = cos(anglePhi)
        let sinPhi = sin(anglePhi)
        let x0 = cosPhi * sin(angleTheta)
        let y0 = -sinPhi
        let z0 = cosPhi * cos(angleTheta)

        let cosTilt = cos(tiltAngle)
        let sinTilt = sin(tiltAngle)
        let y1 = y0 * cosTilt - z0 * sinTilt
        let z1 = y0 * sinTilt + z0 * cosTilt

        let effectiveR = radius * CGFloat(particle.radiusFactor)
        let worldX = CGFloat(x0) * effectiveR
        let worldY = CGFloat(y1) * effectiveR
        let normZ = max(0.0, min(1.0, (z1 + 1.0) / 2.0))

        Circle()
            .fill(Color.white)
            .frame(width: particle.size, height: particle.size)
            .opacity(particle.opacity * (0.2 + 0.8 * normZ))
            .blur(radius: (1.0 - normZ) * 1.5)
            .offset(x: worldX, y: worldY)
            .allowsHitTesting(false)
            .zIndex(Double(z1 * effectiveR))
    }

    // MARK: - Gesture Handling

    @State private var dragStartRotation: Double = 0.0
    @State private var dragStartTilt: Double = 0.0
    @State private var lastDragTranslationX: CGFloat = 0.0
    @State private var lastDragTime: Date = Date()

    private func handleDragChanged(value: DragGesture.Value, radius: CGFloat) {
        if !isDragging {
            isDragging = true
            dragVelocity = 0.0
            dragStartRotation = rotationAngle
            dragStartTilt = tiltAngle
            lastDragTranslationX = value.translation.width
            lastDragTime = Date()
        }

        // Horizontal rotation: 1 screen width = ~2π rotation
        let rotationSensitivity = 0.0075
        let tiltSensitivity = 0.003

        let deltaRotation = Double(value.translation.width) * rotationSensitivity
        rotationAngle = dragStartRotation + deltaRotation

        // Subtle vertical tilt (clamped to [-0.25, 0.25] radians ~ 14 degrees)
        let targetTilt = dragStartTilt - Double(value.translation.height) * tiltSensitivity
        tiltAngle = max(-0.25, min(0.25, targetTilt))

        // Instant velocity tracking
        let now = Date()
        let dt = now.timeIntervalSince(lastDragTime)
        if dt > 0.008 {
            let dx = value.translation.width - lastDragTranslationX
            let instantVel = (Double(dx) * rotationSensitivity) / dt
            dragVelocity = dragVelocity * 0.4 + instantVel * 0.6
            lastDragTranslationX = value.translation.width
            lastDragTime = now
        }
    }

    private func handleDragEnded(value: DragGesture.Value, radius: CGFloat) {
        isDragging = false
        // Cap max velocity for organic, pleasant feel
        dragVelocity = max(-12.0, min(12.0, dragVelocity))
    }

    // MARK: - Physics & Inertia Deceleration Loop

    private func startPhysicsLoop() {
        stopPhysicsLoop()
        let fps = 60.0
        let dt = 1.0 / fps

        animTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { _ in
            time += dt

            // Vertical tilt spring back toward 0 (subtle leveling)
            if !isDragging {
                tiltAngle += (0.0 - tiltAngle) * 0.04
            }

            if !isDragging {
                if abs(dragVelocity) > 0.01 {
                    // Apply momentum
                    rotationAngle += dragVelocity * dt
                    // Friction decay (95% retention per 1/60s = natural deceleration)
                    dragVelocity *= 0.94
                } else {
                    // Idle ambient peaceful slow rotation
                    rotationAngle += 0.0018
                    dragVelocity = 0.0
                }
            }
        }
    }

    private func stopPhysicsLoop() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

#if DEBUG
#Preview {
    FragmentSphere(fragments: Fragment.sampleFragments)
}

struct FragmentSphereView_Previews: PreviewProvider {
    static var previews: some View {
        FragmentSphere(fragments: Fragment.sampleFragments)
    }
}
#endif
