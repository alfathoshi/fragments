//
//  GlassCompatibility.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI

/// Glass effect style options that map to native iOS 26+ `Glass` configurations,
/// with graceful fallback on earlier iOS versions (iOS 18+).
public enum AppGlassStyle {
    case regular
    case clear
}

/// Adaptive prominent capsule button style for iOS 18 fallback.
/// Renders pure black in light mode, pure white in dark mode with tactile spring animation.
public struct AdaptiveGlassProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Adaptive floating dock / island button style for iOS 18 fallback.
/// Renders a pure white (or secondarySystemGroupedBackground in dark mode) capsule
/// with a subtle 1pt border stroke and floating drop shadow, matching the iOS 26 glass pill appearance.
public struct AdaptiveFloatingDockButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                radius: 10,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Adaptive circular glass button style for iOS 18 fallback.
/// Renders a pure white (or secondarySystemGroupedBackground in dark mode) circle
/// with a subtle 1pt border stroke and floating drop shadow, matching the iOS 26 glass circle appearance.
public struct AdaptiveGlassCircleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white)
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 1)
            )
            .clipShape(Circle())
            .contentShape(Circle())
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06),
                radius: 4,
                y: 1.5
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Applies `.buttonStyle(.glass)` on iOS 26+, or falls back to `.buttonStyle(.bordered)` with primary tint on iOS 18.
    @ViewBuilder
    public func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
                .tint(Color.primary)
        }
    }

    /// Applies `.buttonStyle(.glass).buttonBorderShape(.circle)` on iOS 26+,
    /// or falls back to `AdaptiveGlassCircleButtonStyle` (white, bordered circle) on iOS 18.
    @ViewBuilder
    public func glassCircleButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .clipShape(Circle())
        } else {
            self.buttonStyle(AdaptiveGlassCircleButtonStyle())
        }
    }

    /// Applies `.buttonStyle(.glass).buttonBorderShape(.capsule)` on iOS 26+,
    /// or falls back to `AdaptiveFloatingDockButtonStyle` (white, bordered capsule) on iOS 18.
    @ViewBuilder
    public func floatingDockButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            self.buttonStyle(AdaptiveFloatingDockButtonStyle())
        }
    }

    /// Applies `.buttonStyle(.glassProminent)` on iOS 26+, or falls back to `AdaptiveGlassProminentButtonStyle` on iOS 18.
    @ViewBuilder
    public func glassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(AdaptiveGlassProminentButtonStyle())
        }
    }

    /// Applies `.glassEffect(...)` on iOS 26+, or falls back to `.background(.ultraThinMaterial, in: shape)` on iOS 18.
    @ViewBuilder
    public func adaptiveGlassEffect<S: Shape>(_ style: AppGlassStyle = .regular, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .regular:
                self.glassEffect(.regular, in: shape)
            case .clear:
                self.glassEffect(.clear, in: shape)
            }
        } else {
            switch style {
            case .regular:
                self.background(.ultraThinMaterial, in: shape)
            case .clear:
                self.background(.ultraThinMaterial.opacity(0.6), in: shape)
            }
        }
    }
}
