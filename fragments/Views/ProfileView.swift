//
//  ProfileView.swift
//  fragments
//
//  Created on 9/21/26.
//

import SwiftUI
import PhotosUI
import Supabase

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
    @State private var showCloudKitDebug = false
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var isSigningOut = false
    @State private var deleteAccountError: String? = nil
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true
    @AppStorage("hasCompletedPermissions") private var hasCompletedPermissions: Bool = true
    @State private var supabaseService = SupabaseService.shared

    public init(profileManager: ProfileManager = ProfileManager.shared) {
        self.profileManager = profileManager
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var isAccountBusy: Bool {
        isDeletingAccount || isSigningOut
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // 1. Profile Picture & Signature Card
                    profileHeaderView
                        .padding(.top, 16)

                    // 3. Sections: Rate Us, Contact Us, Privacy Policy
                    actionsSectionView
                    
                    accountSectionView

                    // 4. Bottom: Made by Alfathoshi, App Icon, App Name & Copyright
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
            .confirmationDialog("Sign Out", isPresented: $showSignOutAlert, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    handleSignOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out of Fragments?")
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteAccountAlert, titleVisibility: .visible) {
                Button(isDeletingAccount ? "Deleting…" : "Delete Account", role: .destructive) {
                    handleDeleteAccount()
                }
                .disabled(isDeletingAccount || isSigningOut)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Deleting your account permanently removes your account, username, Rooms you own, shared content in those Rooms, uploaded media, and local data. This action cannot be undone.")
            }
            .alert(
                "Account Deletion Failed",
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteAccountError ?? "An unknown error occurred. Your account and data were kept intact — please try again.")
            }
            .sheet(isPresented: $isEditingProfile) {
                editProfileSheet
            }
            #if DEBUG
            .sheet(isPresented: $showCloudKitDebug) {
                CloudKitDebugView()
            }
            #endif
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
            .overlay {
                // Covers the full async lifecycle (server deletion → Apple
                // revoke → local cleanup → sign out → onboarding reset). The
                // confirmation dialog dismisses immediately on tap, so without
                // this the UI would look idle while deletion is still running.
                // Blocks repeated taps; restored on failure via the error alert.
                if isDeletingAccount || isSigningOut {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(isDeletingAccount ? "Deleting account…" : "Signing out…")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
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
            Button {
                editSignatureText = profileManager.signature
                isEditingProfile = true
            } label: {
                HStack(spacing: 8) {
                    Text(profileManager.signature.isEmpty ? "Add Signature" : profileManager.signature)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(profileManager.signature.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(profileManager.signature.isEmpty ? "Add Signature" : "Edit Signature: \(profileManager.signature)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }


    // MARK: - 2. Actions (Rate Us, Contact Us, Privacy Policy)
    private var actionsSectionView: some View {
        VStack(spacing: 0) {
            // Rate Us
            actionRow(
                icon: "star.fill",
                iconColor: .primary,
                title: "Rate Us",
                disclosureIcon: "arrow.up.forward"
            ) {
                triggerHaptic()
                if let url = URL(string: "https://apps.apple.com/app/id6812455792?action=write-review") {
                    openURL(url)
                }
            }

            Divider()
                .padding(.leading, 64)

            // Contact Us
            actionRow(
                icon: "envelope.fill",
                iconColor: .primary,
                title: "Contact Us",
                subtitle: "fraqmentsapp@gmail.com",
                disclosureIcon: "arrow.up.forward"
            ) {
                triggerHaptic()
                openContactEmail()
            }

            Divider()
                .padding(.leading, 64)

            // Privacy Policy
            actionRow(
                icon: "hand.raised.fill",
                iconColor: .primary,
                title: "Privacy Policy",
                disclosureIcon: "arrow.up.forward"
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

    // MARK: - 3. Account (Delete Account, Sign Out)
    private var accountSectionView: some View {
        VStack(spacing: 0) {
            // Delete Account
            actionRow(
                iconColor: Color.red,
                title: "Delete Account",
                disclosureIcon: nil,
                isDestructive: true,
                isLoading: isDeletingAccount
            ) {
                guard !isAccountBusy else { return }
                triggerHaptic()
                showDeleteAccountAlert = true
            }
            .disabled(isAccountBusy)

            Divider()

            // Sign Out
            actionRow(
                iconColor: Color(red: 0.95, green: 0.40, blue: 0.40),
                title: "Sign Out",
                disclosureIcon: nil,
                isDestructive: true,
                isLoading: isSigningOut
            ) {
                guard !isAccountBusy else { return }
                triggerHaptic()
                showSignOutAlert = true
            }
            .disabled(isAccountBusy)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // Row Helper
    private func actionRow(
        icon: String? = nil,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        disclosureIcon: String? = "arrow.up.forward",
        isDestructive: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon Box with filled background color
                if let icon = icon {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(iconColor == .primary ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
                        )
                }
                

                // Title and Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(isDestructive ? Color.red : Color.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if isLoading {
                        Text(title == "Delete Account" ? "Deleting…" : "Signing out…")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                } else {
                    // Optional Badge
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    if let disclosure = disclosureIcon {
                        Image(systemName: disclosure)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressButtonStyle())
        .disabled(isLoading)
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
                        UserIdentityService.shared.syncDisplayNameWithProfile()
                        isEditingProfile = false
                        triggerHaptic()
                    }
                    .glassProminentButtonStyle()
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

    private func handleSignOut() {
        // Prevent duplicate taps — semantics unchanged, just guarded.
        guard !isSigningOut, !isDeletingAccount else { return }
        triggerHaptic()
        isSigningOut = true
        Task {
            // Existing semantics: attempt sign-out (failures swallowed via
            // try?), then reset launch gating and dismiss into onboarding.
            try? await supabaseService.signOut()
            hasCompletedOnboarding = false
            hasCompletedPermissions = false
            // Reset the shared launch coordinator (phase → .onboarding) so a
            // subsequent sign-in re-resolves username → permissions → main
            // instead of reusing stale in-memory gating state.
            OnboardingCoordinator.shared.handleSignOut()
            isSigningOut = false
            dismiss()
        }
    }

    private func handleDeleteAccount() {
        // Never run twice; never swallow the real deletion in `try?`.
        // Also blocked while a sign-out is in flight.
        guard !isDeletingAccount, !isSigningOut else { return }
        triggerHaptic()
        isDeletingAccount = true
        deleteAccountError = nil
        Task {
            do {
                // Capture identity BEFORE deletion (session is still valid).
                let deletedUserID = supabaseService.currentUserID
                // 1. Server-side permanent deletion. Throws on ANY failure —
                //    account stays authenticated and local data stays intact.
                let result = try await supabaseService.deleteAccount()
                // 2. Local wipe, only after the server confirms success.
                performLocalAccountWipe(deletedUserID: deletedUserID)
                if let apple = result.apple, !apple.revoked {
                    print("ℹ️ [ProfileView] Apple authorization revocation status: \(apple.reason)")
                }
            } catch {
                // Failure: keep everything, surface the error, allow retry.
                isDeletingAccount = false
                deleteAccountError = error.localizedDescription
            }
        }
    }

    /// Wipes ALL account-local state after server-confirmed deletion, then
    /// signs out the (now inert) session and returns to onboarding.
    private func performLocalAccountWipe(deletedUserID: String?) {
        // Stop live/collaborative state first (no remote calls inside resets).
        MomentManager.shared.resetForAccountDeletion()
        RoomManager.shared.resetForAccountDeletion()
        try? LocalRoomCache.shared.clearAll()
        sweepLocalMediaFiles()

        // Identity + profile caches.
        profileManager.clearAll()
        CachedUsernameStore.clear(for: deletedUserID)
        UserIdentityService.shared.clearIdentityCache()

        Task {
            // The server already deleted everything; the remaining local JWT
            // is inert (its user no longer exists). Still attempt a clean
            // sign-out, but never block onboarding on it.
            do {
                try await supabaseService.signOut()
            } catch {
                print("⚠️ [ProfileView] Post-deletion sign-out failed (session is inert): \(error.localizedDescription)")
            }
            hasCompletedOnboarding = false
            hasCompletedPermissions = false
            OnboardingCoordinator.shared.handleSignOut()
            isDeletingAccount = false
            dismiss()
        }
    }

    /// Best-effort removal of locally captured media (captured photos,
    /// peer-received files, memo recordings). Server objects are handled
    /// by the Edge Function; this covers device-only copies.
    private func sweepLocalMediaFiles() {
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
           let items = try? fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in items where url.lastPathComponent.hasPrefix("IMG_")
                || url.lastPathComponent.hasPrefix("Peer_") {
                try? fileManager.removeItem(at: url)
            }
        }
        let tmp = fileManager.temporaryDirectory
        if let items = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in items where url.lastPathComponent.hasPrefix("memo_") {
                try? fileManager.removeItem(at: url)
            }
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
