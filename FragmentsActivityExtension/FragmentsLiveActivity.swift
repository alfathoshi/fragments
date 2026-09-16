//
//  FragmentsLiveActivity.swift
//  FragmentsActivityExtension
//
//  Live Activity UI matching the Figma design.
//  Fix 1: AppIcon replaced with programmatic icon (no asset dependency)
//  Fix 2: Title/timer moved to .bottom region so they clear the Dynamic Island camera pill
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct FragmentsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MomentActivityAttributes.self) { context in
            // ─────────────────────────────────────────────
            // LOCK SCREEN / STANDBY BANNER
            // ─────────────────────────────────────────────
            LockScreenBannerView(
                startDate: context.attributes.startDate,
                fragmentCount: context.state.fragmentCount,
                location: context.state.location
            )
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // ─────────────────────────────────────────────
                // EXPANDED — top regions kept minimal so they
                // don't collide with the camera pill
                // ─────────────────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        FragmentsAppIcon(size: 16)
                        Text("Moment")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.leading, 10)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 10)
                }

                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }

                // ─────────────────────────────────────────────
                // BOTTOM — title + buttons safely below the pill
                // ─────────────────────────────────────────────
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Title row

                            HStack() {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 40)
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.black)
                                }
                                HStack(spacing: 4) {
                                    Text("\(context.state.fragmentCount)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .contentTransition(.numericText())
                                    
                                    Text("Fragment\(context.state.fragmentCount > 1 ? "s" : "")")
                                        . font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                }
                            }
                        
                       

                        // 5 circular action buttons
                        HStack(spacing: 12) {
                            HStack(spacing: 16) {
                                Link(destination: URL(string: "fragments://capture?mode=photo")!) {
                                    IslandCircleButton(icon: "photo", color: Color(white: 0.18))
                                }
                                Link(destination: URL(string: "fragments://capture?mode=video")!) {
                                    IslandCircleButton(icon: "video.fill", color: Color(white: 0.18))
                                }
                                Link(destination: URL(string: "fragments://capture?mode=note")!) {
                                    IslandCircleButton(icon: "text.quote", color: Color(white: 0.18))
                                }
                                Link(destination: URL(string: "fragments://capture?mode=audio")!) {
                                    IslandCircleButton(icon: "waveform", color: Color(white: 0.18))
                                }
                            }
                            Link(destination: URL(string: "fragments://end")!) {
                                Text("End")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                }

            } compactLeading: {
                // ─────────────────────────────────────────────
                // COMPACT LEADING — circular app icon
                // ─────────────────────────────────────────────
                FragmentsAppIcon(size: 24, isCircle: true)

            } compactTrailing: {
                // ─────────────────────────────────────────────
                // COMPACT TRAILING — just the fragment count number
                // ─────────────────────────────────────────────
                HStack(spacing: 2) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(context.state.fragmentCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }

            } minimal: {
                // ─────────────────────────────────────────────
                // MINIMAL — red recording dot
                // ─────────────────────────────────────────────
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(context.state.fragmentCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .widgetURL(URL(string: "fragments://moment"))
            .keylineTint(.red)
        }
    }
}

// MARK: - Fragments App Icon (programmatic — no asset dependency)

/// Draws the fragments app icon style: dark rounded square with a sparkle symbol.
/// Works in both the main app and widget extension without needing a shared asset.
private struct FragmentsAppIcon: View {
    let size: CGFloat
    var isCircle: Bool = false

    var body: some View {
        ZStack {
            if isCircle {
                Circle()
                    .fill(Color(white: 0.15))
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(white: 0.15))
                    .frame(width: size, height: size)
            }
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Circular Action Button (Expanded Island)

private struct IslandCircleButton: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Lock Screen Banner View

private struct LockScreenBannerView: View {
    let startDate: Date
    let fragmentCount: Int
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top: icon + title + timer
            HStack() {
                HStack {
                    FragmentsAppIcon(size: 16)
                    Text("Moment")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                
                Spacer()
                
                Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
            }
            
            HStack() {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 40)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.black)
                }
                HStack(spacing: 4) {
                    Text("\(fragmentCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    
                    Text("Fragment\(fragmentCount > 1 ? "s" : "")")
                        . font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                }
            }

            // Bottom: 5 circular shortcut buttons
            HStack(spacing: 12) {
                HStack(spacing: 16) {
                    Link(destination: URL(string: "fragments://capture?mode=photo")!) {
                        IslandCircleButton(icon: "photo", color: Color(white: 0.18))
                    }
                    Link(destination: URL(string: "fragments://capture?mode=video")!) {
                        IslandCircleButton(icon: "video.fill", color: Color(white: 0.18))
                    }
                    Link(destination: URL(string: "fragments://capture?mode=note")!) {
                        IslandCircleButton(icon: "text.quote", color: Color(white: 0.18))
                    }
                    Link(destination: URL(string: "fragments://capture?mode=audio")!) {
                        IslandCircleButton(icon: "waveform", color: Color(white: 0.18))
                    }
                }
                Link(destination: URL(string: "fragments://end")!) {
                    Text("End")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct LockScreenCircleButton: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 50, height: 50)
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Previews

private extension MomentActivityAttributes {
    static let preview = MomentActivityAttributes(
        startDate: Date(),
        sessionID: UUID().uuidString
    )
}

private extension MomentActivityAttributes.ContentState {
    static let sample = MomentActivityAttributes.ContentState(
        fragmentCount: 13,
        location: "Jakarta, ID"
    )
    static let empty = MomentActivityAttributes.ContentState(
        fragmentCount: 0,
        location: "Current Location"
    )
}

// Lock Screen / StandBy banner
#Preview("Lock Screen", as: .content, using: MomentActivityAttributes.preview) {
    FragmentsLiveActivity()
} contentStates: {
    MomentActivityAttributes.ContentState.empty
    MomentActivityAttributes.ContentState.sample
}

// Dynamic Island — expanded pill
#Preview("Dynamic Island (Expanded)", as: .dynamicIsland(.expanded), using: MomentActivityAttributes.preview) {
    FragmentsLiveActivity()
} contentStates: {
    MomentActivityAttributes.ContentState.empty
    MomentActivityAttributes.ContentState.sample
}

// Dynamic Island — compact bar
#Preview("Dynamic Island (Compact)", as: .dynamicIsland(.compact), using: MomentActivityAttributes.preview) {
    FragmentsLiveActivity()
} contentStates: {
    MomentActivityAttributes.ContentState.empty
    MomentActivityAttributes.ContentState.sample
}

// Dynamic Island — minimal dot
#Preview("Dynamic Island (Minimal)", as: .dynamicIsland(.minimal), using: MomentActivityAttributes.preview) {
    FragmentsLiveActivity()
} contentStates: {
    MomentActivityAttributes.ContentState.empty
    MomentActivityAttributes.ContentState.sample
}
