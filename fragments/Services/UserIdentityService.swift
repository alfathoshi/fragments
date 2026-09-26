//
//  UserIdentityService.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit
import Observation

/// Represents a participant's identity in collaborative Rooms.
public struct UserIdentity: Identifiable, Codable, Hashable, Sendable {
    /// The unique CloudKit recordName corresponding to the user's CKRecord.ID.
    public let id: String
    
    /// The human-readable name of the user (e.g. from local profile signature).
    public var displayName: String
    
    /// Indicates whether this identity represents the local device's user.
    public var isCurrentUser: Bool
    
    /// The timestamp when this identity was last resolved from CloudKit or local cache.
    public var lastResolvedAt: Date

    public init(
        id: String,
        displayName: String,
        isCurrentUser: Bool = false,
        lastResolvedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.isCurrentUser = isCurrentUser
        self.lastResolvedAt = lastResolvedAt
    }
}

/// Service managing user identity discovery, caching, and synchronization for collaborative Rooms.
///
/// Discovers identity using native CloudKit `fetchUserRecordID()` without requiring Sign in with Apple.
/// Caches the resolved identifier locally in `UserDefaults` for offline resilience.
@Observable
@MainActor
public final class UserIdentityService {
    public static let shared = UserIdentityService()

    // MARK: - Cache Keys
    private let cachedUserRecordIDKey = "fragments_cached_user_record_id"
    private let cachedUserDisplayNameKey = "fragments_cached_user_display_name"

    // MARK: - State Properties

    /// The currently resolved user identity for this device.
    public private(set) var currentUserIdentity: UserIdentity?

    /// Indicates whether identity resolution is currently active.
    public private(set) var isResolving: Bool = false

    /// The last error message encountered during identity resolution, if any.
    public private(set) var lastError: String? = nil

    /// Reference to the underlying CloudKit service.
    private let cloudKitService: CloudKitService

    /// Task observing `.CKAccountChanged` system notifications.
    private var accountObserverTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initializes the UserIdentityService.
    /// Restores any previously cached identity immediately for instant offline availability.
    public init(cloudKitService: CloudKitService = .shared) {
        self.cloudKitService = cloudKitService
        restoreCachedIdentity()
        startAccountObserver()
        Task { [weak self] in
            await self?.resolveUserIdentity()
        }
    }

    // MARK: - Identity Resolution

    /// Resolves the current user's CloudKit identity asynchronously.
    /// If successful, caches the identifier and updates `currentUserIdentity`.
    /// If network is unavailable, retains the locally cached identity if present.
    /// - Returns: The resolved `UserIdentity`, or cached identity if offline.
    @discardableResult
    public func resolveUserIdentity() async -> UserIdentity? {
        isResolving = true
        defer { isResolving = false }

        guard let container = cloudKitService.container else {
            // Container unavailable (e.g. unprovisioned simulator): maintain cached or local identity
            if let current = currentUserIdentity {
                return current
            }
            let profileName = ProfileManager.shared.signature
            let localID = UserDefaults.standard.string(forKey: cachedUserRecordIDKey) ?? "_local_device_user"
            let identity = UserIdentity(
                id: localID,
                displayName: profileName,
                isCurrentUser: true,
                lastResolvedAt: Date()
            )
            self.currentUserIdentity = identity
            return identity
        }

        do {
            let recordID = try await container.userRecordID()
            let recordName = recordID.recordName
            let displayName = ProfileManager.shared.signature

            // Check if identity changed (e.g., switched iCloud accounts)
            if let existing = currentUserIdentity, existing.id != recordName {
                clearIdentityCache()
            }

            let identity = UserIdentity(
                id: recordName,
                displayName: displayName,
                isCurrentUser: true,
                lastResolvedAt: Date()
            )

            self.currentUserIdentity = identity
            self.lastError = nil

            // Persist to local cache for instant offline retrieval
            UserDefaults.standard.set(recordName, forKey: cachedUserRecordIDKey)
            UserDefaults.standard.set(displayName, forKey: cachedUserDisplayNameKey)

            return identity
        } catch {
            self.lastError = error.localizedDescription

            // Offline/unauthenticated fallback: retain existing or create local device identity
            if let current = currentUserIdentity {
                return current
            }

            let profileName = ProfileManager.shared.signature
            let localID = UserDefaults.standard.string(forKey: cachedUserRecordIDKey) ?? "_local_device_user"
            let fallbackIdentity = UserIdentity(
                id: localID,
                displayName: profileName,
                isCurrentUser: true,
                lastResolvedAt: Date()
            )
            self.currentUserIdentity = fallbackIdentity
            return fallbackIdentity
        }
    }

    /// Synchronizes the current user's display name with `ProfileManager.shared.signature`.
    public func syncDisplayNameWithProfile() {
        guard var current = currentUserIdentity else { return }
        let currentProfileSignature = ProfileManager.shared.signature
        if current.displayName != currentProfileSignature {
            current.displayName = currentProfileSignature
            self.currentUserIdentity = current
            UserDefaults.standard.set(currentProfileSignature, forKey: cachedUserDisplayNameKey)
        }
    }

    /// Clears the cached identity data (useful when account switches or user signs out).
    public func clearIdentityCache() {
        UserDefaults.standard.removeObject(forKey: cachedUserRecordIDKey)
        UserDefaults.standard.removeObject(forKey: cachedUserDisplayNameKey)
        self.currentUserIdentity = nil
        self.lastError = nil
    }

    // MARK: - Private Helpers

    /// Restores cached identity from UserDefaults synchronously on startup.
    private func restoreCachedIdentity() {
        guard let cachedID = UserDefaults.standard.string(forKey: cachedUserRecordIDKey),
              !cachedID.isEmpty else {
            return
        }

        var cachedDisplayName = UserDefaults.standard.string(forKey: cachedUserDisplayNameKey)
            ?? ProfileManager.shared.signature

        if cachedDisplayName == "Alfathoshi" {
            cachedDisplayName = ProfileManager.shared.signature
            if ProfileManager.shared.signature.isEmpty {
                UserDefaults.standard.removeObject(forKey: cachedUserDisplayNameKey)
            }
        }

        self.currentUserIdentity = UserIdentity(
            id: cachedID,
            displayName: cachedDisplayName,
            isCurrentUser: true,
            lastResolvedAt: Date()
        )
    }

    /// Starts observing iCloud account changes.
    private func startAccountObserver() {
        accountObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { break }
                await self.handleAccountChanged()
            }
        }
    }

    /// Handles system iCloud account change notification.
    private func handleAccountChanged() async {
        // Re-check account status & re-resolve identity
        await cloudKitService.checkAccountStatus()
        await resolveUserIdentity()
    }
}
