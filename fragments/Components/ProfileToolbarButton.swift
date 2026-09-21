//
//  ProfileToolbarButton.swift
//  fragments
//
//  Created on 9/21/26.
//

import SwiftUI

/// Reactive navigation bar button displaying the user's avatar image, or a default person icon.
public struct ProfileToolbarButton: View {
    private var profileManager: ProfileManager
    public var action: () -> Void

    public init(profileManager: ProfileManager = ProfileManager.shared, action: @escaping () -> Void) {
        self.profileManager = profileManager
        self.action = action
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            if let avatar = profileManager.avatarImage {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel("Profile")
    }
}
