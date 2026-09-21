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

    public var signature: String = "Alfathoshi"
    public var avatarImage: UIImage? = nil

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
        if let savedSignature = UserDefaults.standard.string(forKey: signatureKey), !savedSignature.isEmpty {
            self.signature = savedSignature
        } else {
            self.signature = "Alfathoshi"
        }

        // Load avatar image from disk
        if FileManager.default.fileExists(atPath: avatarFileURL.path),
           let data = try? Data(contentsOf: avatarFileURL),
           let image = UIImage(data: data) {
            self.avatarImage = image
        }
    }

    public func updateSignature(_ newSignature: String) {
        let trimmed = newSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalValue = trimmed.isEmpty ? "Alfathoshi" : trimmed
        self.signature = finalValue
        UserDefaults.standard.set(finalValue, forKey: signatureKey)
    }

    public func updateAvatar(image: UIImage, data: Data) {
        self.avatarImage = image
        try? data.write(to: avatarFileURL)
    }

    public func clearAvatar() {
        self.avatarImage = nil
        try? FileManager.default.removeItem(at: avatarFileURL)
    }
}
