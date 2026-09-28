//
//  CloudKitService.swift
//  fragments
//
//  Created on 9/25/26.
//

import Foundation
import CloudKit
import Observation

/// Represents the iCloud account status of the current device.
public enum CloudKitAccountStatus: String, Sendable, CaseIterable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable

    public var isAvailable: Bool {
        self == .available
    }

    public var localizedDescription: String {
        switch self {
        case .available:
            return "iCloud account is connected and active."
        case .noAccount:
            return "No iCloud account found. Please sign in to iCloud in iOS Settings."
        case .restricted:
            return "iCloud access is restricted (e.g. Parental Controls or MDM profile)."
        case .couldNotDetermine:
            return "Could not determine iCloud account status. Please check network connection."
        case .temporarilyUnavailable:
            return "iCloud service is temporarily unavailable. Please try again later."
        }
    }
}

/// Low-level CloudKit coordinator providing decoupled database access and account monitoring.
///
/// NOTE: This service is strictly used for collaborative Private Rooms.
/// Personal user fragments and moments remain exclusively stored in local SwiftData
/// SQLite (`cloudKitDatabase: .none`).
@Observable
@MainActor
public final class CloudKitService {
    public static let shared = CloudKitService()

    /// The default CloudKit container identifier for Fragments collaborative features.
    public static let containerIdentifier = "iCloud.com.alfathoshi.fragments"

    /// The active CloudKit container, or nil if running in an unprovisioned simulator environment.
    public let container: CKContainer?

    /// Current iCloud account availability status.
    public private(set) var accountStatus: CloudKitAccountStatus = .couldNotDetermine

    /// The timestamp when account status was last verified with Apple servers.
    public private(set) var lastCheckedAt: Date? = nil

    /// Whether an account check or network operation is actively in flight.
    public private(set) var isCheckingStatus: Bool = false

    /// Task observing `.CKAccountChanged` system notifications.
    private var accountObserverTask: Task<Void, Never>?

    /// Convenient accessor to the user's private CloudKit database.
    public var privateDatabase: CKDatabase? {
        container?.privateCloudDatabase
    }

    /// Convenient accessor to the collaborative shared CloudKit database.
    public var sharedDatabase: CKDatabase? {
        container?.sharedCloudDatabase
    }

    /// Convenient accessor to the public CloudKit database for room code lookups.
    public var publicDatabase: CKDatabase? {
        container?.publicCloudDatabase
    }

    // MARK: - Initialization

    /// Resolves the default CKContainer.
    public nonisolated static func makeDefaultContainer() -> CKContainer? {
        return CKContainer(identifier: containerIdentifier)
    }

    /// Initializes the CloudKitService with the specified container identifier or custom container.
    /// - Parameter container: The `CKContainer` to manage. Defaults to the resolved default container.
    public init(container: CKContainer? = CloudKitService.makeDefaultContainer()) {
        self.container = container
        if container != nil {
            startAccountObserver()
            Task { [weak self] in
                await self?.checkAccountStatus()
            }
        } else {
            self.accountStatus = .noAccount
        }
    }

    // MARK: - Account Status Management

    /// Checks the current iCloud account status asynchronously and updates `accountStatus`.
    /// - Returns: The resolved `CloudKitAccountStatus`.
    @discardableResult
    public func checkAccountStatus() async -> CloudKitAccountStatus {
        guard let container else {
            self.accountStatus = .noAccount
            self.lastCheckedAt = Date()
            return .noAccount
        }

        isCheckingStatus = true
        defer { isCheckingStatus = false }

        do {
            let status = try await container.accountStatus()
            let mappedStatus = Self.mapStatus(status)
            self.accountStatus = mappedStatus
            self.lastCheckedAt = Date()
            return mappedStatus
        } catch {
            self.accountStatus = .couldNotDetermine
            self.lastCheckedAt = Date()
            return .couldNotDetermine
        }
    }

    /// Starts observing system-wide iCloud account changes (e.g., user signs in or out in iOS Settings).
    private func startAccountObserver() {
        accountObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { break }
                await self.checkAccountStatus()
            }
        }
    }

    /// Maps native `CKAccountStatus` to domain `CloudKitAccountStatus`.
    private static func mapStatus(_ status: CKAccountStatus) -> CloudKitAccountStatus {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .couldNotDetermine
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .couldNotDetermine
        }
    }
}
