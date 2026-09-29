//
//  ProfileManager.swift
//  fragments
//
//  Created on 9/21/26.
//

import SwiftUI
import Observation

/// Central observable manager for user profile data (avatar image & signature/name).
@Observable
@MainActor
public final class ProfileManager {
    public static let shared = ProfileManager()

    public var signature: String = ""
    public var avatarImage: UIImage? = nil

    /// Effective human-readable name for collaboration and UI display.
    /// Returns the user's signature if set, otherwise "Unknown".
    public var effectiveName: String {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Unknown"
    }

    private let signatureKey = "profile_signature"
    private var avatarFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("user_profile_avatar.jpg")
    }

    public init() {
        loadSavedData()
    }

    public func loadSavedData() {
        // Load signature/name
        if let savedSignature = UserDefaults.standard.string(forKey: signatureKey) {
            // Clean up any legacy default "Alfathoshi"
            if savedSignature == "Alfathoshi" {
                self.signature = ""
                UserDefaults.standard.removeObject(forKey: signatureKey)
            } else {
                self.signature = savedSignature
            }
        } else {
            self.signature = ""
        }

        // Load avatar image from disk
        if FileManager.default.fileExists(atPath: avatarFileURL.path),
           let data = try? Data(contentsOf: avatarFileURL),
           let image = UIImage(data: data) {
            self.avatarImage = image
        }
    }

    /// One-way sync of the backend username (`public.profiles.username`)
    /// into the local display cache (`signature`).
    ///
    /// The backend row is the source of truth: callers must invoke this after
    /// `claimUsername()` succeeds and whenever `fetchOwnProfile()` returns a
    /// username (e.g. returning user, reinstall). This intentionally does NOT
    /// touch `display_name` and performs no Supabase writes — unlike
    /// `updateSignature`, which manages the legacy free-text signature.
    public func syncUsername(_ username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.signature = trimmed
        UserDefaults.standard.set(trimmed, forKey: signatureKey)
    }

    public func updateSignature(_ newSignature: String) {
        let trimmed = newSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        self.signature = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: signatureKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: signatureKey)
        }
        // Keep Supabase `profiles.display_name` in sync so room member lists
        // render the real name instead of the schema default ("Fragment Explorer").
        // Fire-and-forget: invite/member read flows are unaffected on failure.
        if !trimmed.isEmpty, !RoomMember.isUnresolvedDisplayName(trimmed) {
            Task {
                try? await SupabaseRoomRepository.shared.upsertCurrentUserProfile(displayName: trimmed)
            }
        }
    }

    public func updateAvatar(image: UIImage, data: Data) {
        self.avatarImage = image
        try? data.write(to: avatarFileURL)
    }

    /// Removes all account-specific local profile state (username/signature
    /// cache + avatar file). Used ONLY by permanent account deletion —
    /// sign-out preserves local profile data.
    public func clearAll() {
        self.signature = ""
        UserDefaults.standard.removeObject(forKey: signatureKey)
        clearAvatar()
    }

    public func clearAvatar() {
        self.avatarImage = nil
        try? FileManager.default.removeItem(at: avatarFileURL)
    }
}
