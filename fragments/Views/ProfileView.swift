//
//  ProfileView.swift
//  fragments
//
//  Created on 9/21/26.
//

import SwiftUI
import PhotosUI

public struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    // MARK: - Central Profile Manager
    private var profileManager: ProfileManager

    // MARK: - Avatar State
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    // MARK: - Interactive State
    @State private var isEditingProfile = false
    @State private var editSignatureText = ""
    @State private var showContactFallbackAlert = false
    @State private var showCopiedNotification = false

    public init(profileManager: ProfileManager = ProfileManager.shared) {
        self.profileManager = profileManager
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // 1. Profile Picture & Signature Card
                    profileHeaderView
                        .padding(.top, 16)

                    // 2. Sections: Rate Us, Contact Us, Privacy Policy
                    actionsSectionView

                    // 3. Bottom: Made by Alfathoshi, App Icon, App Name & Copyright
                    bottomAppIconView
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                }
            }
            .alert("Email Client Not Found", isPresented: $showContactFallbackAlert) {
                Button("Copy Email Address") {
                    UIPasteboard.general.string = "alfathbintangmuhammad@gmail.com"
                    triggerHaptic()
                    withAnimation {
                        showCopiedNotification = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            showCopiedNotification = false
                        }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Could not launch Mail app. You can copy alfathbintangmuhammad@gmail.com to your clipboard.")
            }
            .sheet(isPresented: $isEditingProfile) {
                editProfileSheet
            }
            .overlay(alignment: .top) {
                if showCopiedNotification {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Email copied to clipboard")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
        }
    }

    // MARK: - 1. Profile Header Card
    private var profileHeaderView: some View {
        VStack(spacing: 16) {
            // Profile Picture with Camera Badge
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let avatar = profileManager.avatarImage {
                            Image(uiImage: avatar)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color(red: 0.22, green: 0.23, blue: 0.28), Color(red: 0.14, green: 0.14, blue: 0.17)]
                                            : [Color(red: 0.88, green: 0.90, blue: 0.94), Color(red: 0.78, green: 0.81, blue: 0.87)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 46, weight: .medium))
                                        .foregroundStyle(Color.primary.opacity(0.55))
                                }
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 6)

                    // Edit camera badge
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Change Profile Picture")

            // Signature (Username) - Single Field
            HStack(spacing: 8) {
                Text(profileManager.signature)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Button {
                    editSignatureText = profileManager.signature
                    isEditingProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Edit Signature")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - 2. Action Section (Rate Us, Contact Us, Privacy Policy)
    private var actionsSectionView: some View {
        VStack(spacing: 0) {
            // Rate Us
            actionRow(
                icon: "star.fill",
                iconColor: Color.orange,
                title: "Rate Us",
                showDisclosure: true
            ) {
                triggerHaptic()
                if let url = URL(string: "https://apps.apple.com/app/id6812455792?action=write-review") {
                    openURL(url)
                }
            }

            Divider()
                .padding(.leading, 56)

            // Contact Us
            actionRow(
                icon: "envelope.fill",
                iconColor: Color.blue,
                title: "Contact Us",
                subtitle: "alfathbintangmuhammad@gmail.com",
                showDisclosure: true
            ) {
                triggerHaptic()
                openContactEmail()
            }

            Divider()
                .padding(.leading, 56)

            // Privacy Policy
            actionRow(
                icon: "hand.raised.fill",
                iconColor: Color.green,
                title: "Privacy Policy",
                showDisclosure: true
            ) {
                triggerHaptic()
                if let url = URL(string: "https://alfathoshi.vercel.app/privacy/fragments") {
                    openURL(url)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // Row Helper
    private func actionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        showDisclosure: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon Box
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.background)
                    )

                // Title and Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Optional Badge
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                if showDisclosure {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressButtonStyle())
    }

    // MARK: - 3. Bottom: Made by Alfathoshi, App Icon, Name & Copyright
    private var bottomAppIconView: some View {
        VStack(spacing: 14) {
            // Made by Alfathoshi placed before the app icon
            Text("Made by Alfathoshi")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            // App Icon
            Image(colorScheme == .dark ? "AppIconDark" : "AppIconLight")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 5)

            // App Name & Version & Copyright
            VStack(spacing: 3) {
                Text(appVersionString)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)

                Text("Copyright @ 2026 Fragments")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit Profile Sheet (Single Field for Signature/Username)
    private var editProfileSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Signature (Username)")) {
                    TextField("Enter your signature / name", text: $editSignatureText)
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .navigationTitle("Edit Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditingProfile = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profileManager.updateSignature(editSignatureText)
                        isEditingProfile = false
                        triggerHaptic()
                    }
                    .buttonStyle(.glassProminent)
                    .font(.body.weight(.semibold))
                    .tint(.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(28)
    }

    // MARK: - Actions & Helpers
    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openContactEmail() {
        let email = "alfathbintangmuhammad@gmail.com"
        let subject = "Fragments App Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let mailtoURL = URL(string: "mailto:\(email)?subject=\(subject)") {
            if UIApplication.shared.canOpenURL(mailtoURL) {
                UIApplication.shared.open(mailtoURL)
            } else {
                showContactFallbackAlert = true
            }
        } else {
            showContactFallbackAlert = true
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileManager.updateAvatar(image: image, data: data)
                    triggerHaptic()
                }
            }
        }
    }
}

// MARK: - Row Press Button Style
private struct RowPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.05) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("ProfileView - Light") {
    ProfileView()
}

#Preview("ProfileView - Dark") {
    ProfileView()
        .preferredColorScheme(.dark)
}
#endif
