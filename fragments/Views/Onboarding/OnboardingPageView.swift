//
//  OnboardingPageView.swift
//  fragments
//
//  Created on 9/28/26.
//

import SwiftUI
import UIKit

// MARK: - Onboarding Page Data Model

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let illustrationContent: AnyView

    init<Content: View>(
        id: Int,
        title: String,
        subtitle: String,
        @ViewBuilder illustration: () -> Content
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.illustrationContent = AnyView(illustration())
    }
}

// MARK: - Single Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    /// True when this page is the currently selected page in the onboarding
    /// pager. Illustrations gate their entrance animation on this flag so the
    /// animation only runs when the page is actually visible — TabView
    /// preloads adjacent pages off-screen, and relying on `onAppear` alone
    /// lets the animation complete before the user ever sees the page.
    var isActive: Bool = true

    var body: some View {
        GeometryReader { geo in
            // Scale the fixed 380pt illustration canvas to fit the available
            // page height. Reserving ~130pt for text + spacers, the rest is
            // illustration budget — clamped so offsets/rotations shrink
            // together instead of clipping on short screens (SE / Duo).
            let rawScale = (geo.size.height - 130) / 380
            let scale = min(1.0, max(0.58, rawScale))
            let illustrationHeight = 380 * scale

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                // Illustration area — uniformly scaled canvas
                illustration
                    .frame(height: 380)
                    .scaleEffect(scale, anchor: .center)
                    .frame(height: illustrationHeight)

                Spacer(minLength: 8)

                // Text content
                VStack(spacing: 8) {
                    Text(page.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text(page.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.id {
        case 0:
            OnboardingPage1Illustration(isActive: isActive)
        case 1:
            OnboardingPage2Illustration(isActive: isActive)
        case 2:
            OnboardingPage3Illustration(isActive: isActive)
        default:
            page.illustrationContent
        }
    }
}

// MARK: - Fragment Card Components for Illustrations

/// A photo fragment card (used in Onboarding Page 1 illustrations)
struct OnboardingFragmentPhotoCard: View {
    let title: String
    let date: String
    let color: Color
    let rotation: Double
    let imageName: String?
    let emoji: String?

    init(
        title: String,
        date: String,
        color: Color = Color(red: 1.0, green: 0.85, blue: 0.54), // #FFD989
        rotation: Double = 0,
        imageName: String? = nil,
        emoji: String? = nil
    ) {
        self.title = title
        self.date = date
        self.color = color
        self.rotation = rotation
        self.imageName = imageName
        self.emoji = emoji
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)

            // Image overlay if provided
            if let imageName = imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 128, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Text labels
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(date)
                    .font(.system(size: 7, weight: .regular, design: .rounded))
            }
            .padding(12)

            // Emoji / play button
            if let emoji = emoji {
                Text(emoji)
                    .font(.system(size: 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 128, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 4)
        .rotationEffect(.degrees(rotation))
    }
}

/// A note fragment card (used in Onboarding Page 1 illustrations)
struct OnboardingFragmentNoteCard: View {
    let title: String
    let date: String
    let noteText: String
    let color: Color
    let rotation: Double

    init(
        title: String,
        date: String,
        noteText: String,
        color: Color = Color(red: 1.0, green: 0.85, blue: 0.54),
        rotation: Double = 0
    ) {
        self.title = title
        self.date = date
        self.noteText = noteText
        self.color = color
        self.rotation = rotation
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(date)
                        .font(.system(size: 7, weight: .light, design: .rounded))
                }

                Divider()
                    .frame(width: 105)

                Text(noteText)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .frame(width: 105, alignment: .leading)
                    .lineLimit(4)
            }
            .padding(12)
        }
        .frame(width: 128, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 4)
        .rotationEffect(.degrees(rotation))
    }
}

/// An audio/memo fragment card with waveform visualization
struct OnboardingFragmentAudioCard: View {
    let title: String
    let date: String
    let color: Color
    let textColor: Color
    let rotation: Double

    init(
        title: String,
        date: String,
        color: Color = Color(red: 0.776, green: 0.529, blue: 1.0), // #C687FF
        textColor: Color = .white,
        rotation: Double = 0
    ) {
        self.title = title
        self.date = date
        self.color = color
        self.textColor = textColor
        self.rotation = rotation
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
                Text(date)
                    .font(.system(size: 7, weight: .light, design: .rounded))
                    .foregroundStyle(textColor)
            }
            .padding(12)

            // Waveform visualization
            HStack(spacing: 3) {
                ForEach(0..<48, id: \.self) { i in
                    let heights: [CGFloat] = [3, 12, 20, 14, 13, 23, 20, 20, 20, 14, 14, 14, 23, 14, 23, 23, 23, 14, 14, 14, 14, 23, 14, 14, 6, 14, 6, 14, 23, 14, 23, 3, 23, 20, 14, 14, 6, 14, 14, 6, 3, 14, 14, 14, 14, 14, 14, 14]
                    let h = i < heights.count ? heights[i] : 10.0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(uiColor: .systemGray6).opacity(0.66))
                        .frame(width: 1.5, height: h)
                }
            }
            .frame(width: 105, height: 23, alignment: .center)
            .clipped()
            .offset(x: 12, y: 55)

            // Play button emoji
            Text("▶")
                .font(.system(size: 20))
                .foregroundStyle(textColor)
                .offset(x: 12, y: 90)
        }
        .frame(width: 128, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 4)
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Page 1 Illustration: Scattered Fragment Cards

struct OnboardingPage1Illustration: View {
    var isActive: Bool = true
    @State private var showCenter = false
    @State private var showTopLeft = false
    @State private var showBottomRight = false
    @State private var showTopRight = false
    @State private var showBottomLeft = false
    @State private var showRadiant = false
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            // Background radial gradient glow (warm yellow) - blooms after all cards snap into place
            RadialGradient(
                stops: [
                    .init(color: Color(hex: "#FEC500"), location: 0.0),
                    .init(color: Color(hex: "#FFD989"), location: 0.61),
                    .init(color: Color(hex: "#FFE1A0"), location: 0.90),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 180
            )
            .frame(width: 362, height: 373)
            .blur(radius: 71)
            .scaleEffect(showRadiant ? 1.0 : 0.3)
            .opacity(showRadiant ? 1.0 : 0.0)

            // Surfing photo card (top-left, rotated -10°)
            Image(.onboardingPage1TopLeft)
                .resizable()
                .scaledToFit()
                .frame(width: 127)
                .rotationEffect(.degrees(showTopLeft ? -10 : 0))
                .scaleEffect(showTopLeft ? 1.0 : 0.85)
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                .opacity(showTopLeft ? 1.0 : 0.0)
                .offset(x: -60, y: showTopLeft ? -100 : -40)

            // Note card (top-right, rotated +15°)
            Image(.onboardingPage1TopRight)
                .resizable()
                .scaledToFit()
                .frame(width: 127)
                .rotationEffect(.degrees(showTopRight ? 15 : 0))
                .scaleEffect(showTopRight ? 1.0 : 0.85)
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                .opacity(showTopRight ? 1.0 : 0.0)
                .offset(x: 60, y: showTopRight ? -60 : 0)

            // Park photo card (center)
            Image(.onboardingPage1Center)
                .resizable()
                .scaledToFit()
                .frame(width: 127)
                .scaleEffect(showCenter ? 1.0 : 0.85)
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                .opacity(showCenter ? 1.0 : 0.0)
                .offset(x: 0, y: showCenter ? -10 : 50)

            // Audio card (bottom-left, rotated +10°)
            Image(.onboardingPage1BottomLeft)
                .resizable()
                .scaledToFit()
                .frame(width: 127)
                .rotationEffect(.degrees(showBottomLeft ? 10 : 0))
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                .scaleEffect(showBottomLeft ? 1.0 : 0.85)
                .opacity(showBottomLeft ? 1.0 : 0.0)
                .offset(x: -60, y: showBottomLeft ? 70 : 130)

            // Sunset photo card (bottom-right, rotated -15°)
            Image(.onboardingPage1BottomRight)
                .resizable()
                .scaledToFit()
                .frame(width: 127)
                .rotationEffect(.degrees(showBottomRight ? -15 : 0))
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                .scaleEffect(showBottomRight ? 1.0 : 0.85)
                .opacity(showBottomRight ? 1.0 : 0.0)
                .offset(x: 60, y: showBottomRight ? 110 : 170)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // TabView preloads adjacent pages off-screen — only animate when
            // this page is actually selected.
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        resetAnimation()
        animationTask = Task { @MainActor in
            await runAnimationSequence()
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        resetAnimation()
    }

    @MainActor
    private func runAnimationSequence() async {
        let launchHaptic = UIImpactFeedbackGenerator(style: .light)
        let snapHaptic = UIImpactFeedbackGenerator(style: .rigid)
        let bloomHaptic = UIImpactFeedbackGenerator(style: .soft)

        launchHaptic.prepare()
        snapHaptic.prepare()
        bloomHaptic.prepare()

        let spring = Animation.spring(response: 0.48, dampingFraction: 0.72)

        // Initial delay before start
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }

        // 1. Center: Launch & Snap
        launchHaptic.impactOccurred(intensity: 0.5)
        withAnimation(spring) { showCenter = true }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        snapHaptic.impactOccurred(intensity: 0.85)

        // 2. Top Left: Launch & Snap
        try? await Task.sleep(nanoseconds: 70_000_000)
        if Task.isCancelled { return }
        launchHaptic.impactOccurred(intensity: 0.5)
        withAnimation(spring) { showTopLeft = true }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        snapHaptic.impactOccurred(intensity: 0.85)

        // 3. Bottom Right: Launch & Snap
        try? await Task.sleep(nanoseconds: 70_000_000)
        if Task.isCancelled { return }
        launchHaptic.impactOccurred(intensity: 0.5)
        withAnimation(spring) { showBottomRight = true }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        snapHaptic.impactOccurred(intensity: 0.85)

        // 4. Top Right: Launch & Snap
        try? await Task.sleep(nanoseconds: 70_000_000)
        if Task.isCancelled { return }
        launchHaptic.impactOccurred(intensity: 0.5)
        withAnimation(spring) { showTopRight = true }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        snapHaptic.impactOccurred(intensity: 0.85)

        // 5. Bottom Left: Launch & Snap
        try? await Task.sleep(nanoseconds: 70_000_000)
        if Task.isCancelled { return }
        launchHaptic.impactOccurred(intensity: 0.5)
        withAnimation(spring) { showBottomLeft = true }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        snapHaptic.impactOccurred(intensity: 0.90)

        // 6. Blooming Radiant: Glow blooms behind cards
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
        bloomHaptic.impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.70, dampingFraction: 0.65)) {
            showRadiant = true
        }
    }

    private func resetAnimation() {
        showCenter = false
        showTopLeft = false
        showBottomRight = false
        showTopRight = false
        showBottomLeft = false
        showRadiant = false
    }
}

// MARK: - Page 3 Illustration: Moment Capture UI

struct OnboardingPage3Illustration: View {
    var isActive: Bool = true
    @State private var showLiveActivity = false
    @State private var showCard1 = false // memoPink
    @State private var showCard2 = false // onboardingPage1Center
    @State private var showCard3 = false // onboardingPage1TopRight
    @State private var showCard4 = false // onboardingPage1BottomLeft
    @State private var showCard5 = false // onboardingPage1BottomRight
    @State private var showCard6 = false // notePink
    @State private var showCard7 = false // onboardingPage1TopLeft
    @State private var showRadiant = false
    @State private var animationTask: Task<Void, Never>? = nil

    private func popCard(
        image: ImageResource,
        width: CGFloat = 56,
        targetAngle: Double,
        targetX: CGFloat,
        targetY: CGFloat,
        isShown: Bool
    ) -> some View {
        Image(image)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(isShown ? targetAngle : 0))
            .scaleEffect(isShown ? 1.0 : 0.1)
            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
            .opacity(isShown ? 1.0 : 0.0)
            .offset(x: isShown ? targetX : 0, y: isShown ? targetY : 10)
    }

    var body: some View {
        ZStack {
            // Background radial gradient glow (red/pink) - blooms after all cards pop out
            RadialGradient(
                stops: [
                    .init(color: Color(hex: "#FF0000"), location: 0.0),
                    .init(color: Color(hex: "#FA7680"), location: 0.61),
                    .init(color: Color(hex: "#FFBFC4"), location: 0.90),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 180
            )
            .frame(width: 362, height: 373)
            .blur(radius: 71)
            .scaleEffect(showRadiant ? 1.0 : 0.3)
            .opacity(showRadiant ? 1.0 : 0.0)

            // Scattered small fragment cards behind the dark panel - pop out from live activity (0, 10)
            Group {
                // 1. Top-left audio card (memoPink)
                popCard(image: .memoPink, targetAngle: -10, targetX: -70, targetY: -80, isShown: showCard1)

                // 2. Top-center photo card (onboardingPage1Center)
                popCard(image: .onboardingPage1Center, targetAngle: 0, targetX: 0, targetY: -85, isShown: showCard2)

                // 3. Top-right note card (onboardingPage1TopRight)
                popCard(image: .onboardingPage1TopRight, targetAngle: 10, targetX: 70, targetY: -80, isShown: showCard3)

                // 4. Bottom-left purple audio card (onboardingPage1BottomLeft)
                popCard(image: .onboardingPage1BottomLeft, targetAngle: 10, targetX: -100, targetY: 90, isShown: showCard4)

                // 5. Bottom-center sunset card (onboardingPage1BottomRight)
                popCard(image: .onboardingPage1BottomRight, targetAngle: 5, targetX: -35, targetY: 95, isShown: showCard5)

                // 6. Bottom-right note card (notePink)
                popCard(image: .notePink, targetAngle: -5, targetX: 35, targetY: 95, isShown: showCard6)

                // 7. Far-right surf card (onboardingPage1TopLeft)
                popCard(image: .onboardingPage1TopLeft, targetAngle: -10, targetX: 100, targetY: 90, isShown: showCard7)
            }

            // Dark Moment Panel (center overlay) - fades in first
            Image(.liveActivity)
                .resizable()
                .scaledToFit()
                .frame(width: 317)
                .opacity(showLiveActivity ? 1.0 : 0.0)
                .scaleEffect(showLiveActivity ? 1.0 : 0.94)
                .offset(y: 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Gated on selection: TabView instantiates/preloads page 3 while
            // it is still off-screen. Starting here unconditionally lets the
            // sequence finish before first arrival (final state visible, no
            // visible animation). Only animate when selected.
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        resetAnimation()
        animationTask = Task { @MainActor in
            await runAnimationSequence()
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        resetAnimation()
    }

    @MainActor
    private func runAnimationSequence() async {
        let liveActivityHaptic = UIImpactFeedbackGenerator(style: .light)
        let popHaptic = UIImpactFeedbackGenerator(style: .medium)
        let bloomHaptic = UIImpactFeedbackGenerator(style: .soft)

        liveActivityHaptic.prepare()
        popHaptic.prepare()
        bloomHaptic.prepare()

        let popSpring = Animation.spring(response: 0.44, dampingFraction: 0.64)

        // Step 0: Live Activity fades in first
        try? await Task.sleep(nanoseconds: 80_000_000)
        if Task.isCancelled { return }
        liveActivityHaptic.impactOccurred(intensity: 0.6)
        withAnimation(.easeOut(duration: 0.40)) {
            showLiveActivity = true
        }

        // Pause before cards start popping out from behind it
        try? await Task.sleep(nanoseconds: 280_000_000)
        if Task.isCancelled { return }

        // 1. memoPink
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard1 = true }

        // 2. onboardingPage1Center
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard2 = true }

        // 3. onboardingPage1TopRight
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard3 = true }

        // 4. onboardingPage1BottomLeft
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard4 = true }

        // 5. onboardingPage1BottomRight
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard5 = true }

        // 6. notePink
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.7)
        withAnimation(popSpring) { showCard6 = true }

        // 7. onboardingPage1TopLeft
        try? await Task.sleep(nanoseconds: 110_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.85)
        withAnimation(popSpring) { showCard7 = true }

        // 8. Blooming Radiant
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        bloomHaptic.impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.70, dampingFraction: 0.65)) {
            showRadiant = true
        }
    }

    private func resetAnimation() {
        showLiveActivity = false
        showCard1 = false
        showCard2 = false
        showCard3 = false
        showCard4 = false
        showCard5 = false
        showCard6 = false
        showCard7 = false
        showRadiant = false
    }
}

// MARK: - Page 2 Illustration: Shared Moments with Memoji Avatars

struct OnboardingPage2Illustration: View {
    var isActive: Bool = true
    @State private var isOpen: Bool = true
    @State private var showAvatar1 = false
    @State private var showAvatar2 = false
    @State private var showAvatar3 = false
    @State private var showAvatar4 = false
    @State private var showRadiant = false
    @State private var animationTask: Task<Void, Never>? = nil

    private let folderItems: [FolderItem] = [
        FolderItem(imageName: "onboarding_page1_bottomRightImage"),
        FolderItem(imageName: "onboarding_page1_bottomLeftImage"),
        FolderItem(imageName: "onboarding_page1_topLeftImage"),
        FolderItem(imageName: "onboarding_page1_topRightImage"),
        FolderItem(imageName: "onboarding_page1_centerImage")
    ]

    private func glassPersonAvatar(
        image: ImageResource,
        colorHex: String,
        x: CGFloat,
        y: CGFloat,
        isShown: Bool
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: colorHex).opacity(0.72))
                .adaptiveGlassEffect(.clear, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )

            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
        }
        .frame(width: 92, height: 92)
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
        .scaleEffect(isShown ? 1.0 : 0.001)
        .opacity(isShown ? 1.0 : 0.0)
        .offset(x: x, y: y)
    }

    var body: some View {
        ZStack {
            // Background radial gradient glow (blue) - blooms after avatars pop
            RadialGradient(
                stops: [
                    .init(color: Color(hex: "#0088FF"), location: 0.0),
                    .init(color: Color(hex: "#2196F3"), location: 0.61),
                    .init(color: Color(hex: "#90CAF9"), location: 0.90),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 180
            )
            .frame(width: 362, height: 373)
            .blur(radius: 71)
            .scaleEffect(showRadiant ? 1.0 : 0.3)
            .opacity(showRadiant ? 1.0 : 0.0)

            // Top-Left (Kuning)
            glassPersonAvatar(image: .personTopLeft, colorHex: "#FFDA8B", x: -70, y: -100, isShown: showAvatar1)

            // Top-Right (Ungu)
            glassPersonAvatar(image: .personTopRight, colorHex: "#CE95FF", x: 110, y: -80, isShown: showAvatar2)

            // Bottom-Right (Biru Muda)
            glassPersonAvatar(image: .personBottomRight, colorHex: "#B5E3F9", x: 90, y: 100, isShown: showAvatar3)

            // Central folder-like container with fragment cards
            MomentFolder(
                items: folderItems,
                isOpen: $isOpen
            )

            // Bottom-Left (Pink)
            glassPersonAvatar(image: .personBottomLeft, colorHex: "#FFB0B0", x: -80, y: 70, isShown: showAvatar4)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        resetAnimation()
        animationTask = Task { @MainActor in
            await runAnimationSequence()
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        resetAnimation()
    }

    @MainActor
    private func runAnimationSequence() async {
        let folderHaptic = UIImpactFeedbackGenerator(style: .light)
        let popHaptic = UIImpactFeedbackGenerator(style: .medium)
        let bloomHaptic = UIImpactFeedbackGenerator(style: .soft)

        folderHaptic.prepare()
        popHaptic.prepare()
        bloomHaptic.prepare()

        let popSpring = Animation.spring(response: 0.40, dampingFraction: 0.62)

        // 1. Initial pause & Folder Opens
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        folderHaptic.impactOccurred(intensity: 0.6)
        withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
            isOpen = false
        }

        // 2. Avatar 1 (Top-Left) Pops
        try? await Task.sleep(nanoseconds: 260_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.75)
        withAnimation(popSpring) {
            showAvatar1 = true
        }

        // 3. Avatar 2 (Top-Right) Pops
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.75)
        withAnimation(popSpring) {
            showAvatar2 = true
        }

        // 4. Avatar 3 (Bottom-Right) Pops
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.75)
        withAnimation(popSpring) {
            showAvatar3 = true
        }

        // 5. Avatar 4 (Bottom-Left) Pops
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        popHaptic.impactOccurred(intensity: 0.85)
        withAnimation(popSpring) {
            showAvatar4 = true
        }

        // 6. Radiant Blooms
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
        bloomHaptic.impactOccurred(intensity: 1.0)
        withAnimation(.spring(response: 0.70, dampingFraction: 0.65)) {
            showRadiant = true
        }
    }

    private func resetAnimation() {
        isOpen = true
        showAvatar1 = false
        showAvatar2 = false
        showAvatar3 = false
        showAvatar4 = false
        showRadiant = false
    }
}

#if DEBUG
#Preview("Page 1") {
    OnboardingPageView(page: OnboardingPage(
        id: 0,
        title: "Some moments deserve\nmore than a photo",
        subtitle: "Photos capture what happened.\nFragments helps you remember how it felt."
    ) {
        OnboardingPage1Illustration()
    })
}

#Preview("Page 2") {
    OnboardingPageView(page: OnboardingPage(
        id: 1,
        title: "Moments are better\nwhen they're shared.",
        subtitle: "Share moments with the people who were there.\nBring them into the one that matter."
    ) {
        OnboardingPage2Illustration()
    })
}

#Preview("Page 3") {
    OnboardingPageView(page: OnboardingPage(
        id: 2,
        title: "Don't let the moment\npass you by",
        subtitle: "Start a Moment and keep capturing\nwithout interrupting the experience."
    ) {
        OnboardingPage3Illustration()
    })
}
#endif
