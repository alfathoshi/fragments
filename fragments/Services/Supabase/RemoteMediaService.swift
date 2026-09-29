//
//  RemoteMediaService.swift
//  fragments
//
//  Created on 9/28/26.
//

import Foundation
import UIKit

/// Error types encountered during remote media operations.
public enum RemoteMediaError: LocalizedError, Sendable, Equatable {
    case missingStoragePath
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyData
    case diskWriteFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingStoragePath:
            return "No remote storage path was provided for this media asset."
        case .invalidResponse:
            return "Invalid response received from remote media server."
        case .httpError(let code):
            return "Remote media server returned HTTP status \(code)."
        case .emptyData:
            return "Downloaded media asset was empty (0 bytes)."
        case .diskWriteFailed(let reason):
            return "Failed to save downloaded media to cache: \(reason)"
        case .cancelled:
            return "Media download was cancelled."
        }
    }
}

/// Actor responsible for resolving signed URLs, downloading binaries, deduplicating
/// in-flight tasks, and atomically caching media under `Library/Caches/Rooms/{roomID}/media/`.
public actor RemoteMediaService {

    // MARK: - Singleton & Configuration

    public static let shared = RemoteMediaService()

    private let repository: SupabaseRoomRepository
    private let fileManager: FileManager
    private let urlSession: URLSession

    public typealias SignedURLResolver = @Sendable (String, Int) async throws -> URL
    private let customSignedURLResolver: SignedURLResolver?

    /// Root directory for room cache files: `Library/Caches/Rooms/`
    public let baseCacheDirectory: URL

    /// In-flight download task registry mapped by `storagePath` to ensure concurrent callers share a single download task.
    private var inFlightTasks: [String: Task<URL, Error>] = [:]

    // MARK: - Initialization

    public init(
        repository: SupabaseRoomRepository? = nil,
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared,
        baseCacheDirectory: URL? = nil,
        signedURLResolver: SignedURLResolver? = nil
    ) {
        self.repository = repository ?? MainActor.assumeIsolated { SupabaseRoomRepository.shared }
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.customSignedURLResolver = signedURLResolver

        if let baseCacheDirectory = baseCacheDirectory {
            self.baseCacheDirectory = baseCacheDirectory
        } else {
            let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.baseCacheDirectory = cachesURL.appendingPathComponent("Rooms", isDirectory: true)
        }
    }

    // MARK: - Deterministic Path & Directory Resolution

    /// Returns the directory URL for media belonging to a specific Room:
    /// `Library/Caches/Rooms/{roomID}/media/`
    nonisolated public func mediaDirectory(for roomID: String) -> URL {
        baseCacheDirectory
            .appendingPathComponent(roomID, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
    }

    /// Determines the local cache destination URL for a given storagePath and roomID.
    nonisolated public func destinationURL(for storagePath: String, roomID: String, preferredFilename: String? = nil) -> URL {
        let dir = mediaDirectory(for: roomID)
        let filename = resolveFilename(storagePath: storagePath, preferredFilename: preferredFilename)
        return dir.appendingPathComponent(filename)
    }

    /// Extracts or synthesizes a clean, deterministic filename for the cache item.
    nonisolated private func resolveFilename(storagePath: String, preferredFilename: String?) -> String {
        if let preferred = preferredFilename, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferred
        }
        let lastComponent = (storagePath as NSString).lastPathComponent
        if !lastComponent.isEmpty && lastComponent != "/" {
            return lastComponent
        }
        let sanitized = storagePath.replacingOccurrences(of: "/", with: "_")
        return sanitized.isEmpty ? "\(UUID().uuidString).bin" : sanitized
    }

    // MARK: - Fast Synchronous Disk Cache Query

    /// Checks if a non-empty, valid cached file already exists on disk.
    nonisolated public func cachedMediaURL(for storagePath: String, roomID: String, preferredFilename: String? = nil) -> URL? {
        let target = destinationURL(for: storagePath, roomID: roomID, preferredFilename: preferredFilename)
        if isValidFile(at: target) {
            return target
        }
        return nil
    }

    /// Checks if the media for a SharedFragment already exists on disk.
    nonisolated public func cachedMediaURL(for fragment: SharedFragment) -> URL? {
        if let local = fragment.mediaReference?.localFileURL, isValidFile(at: local) {
            return local
        }
        guard let storagePath = fragment.mediaReference?.storagePath, !storagePath.isEmpty else {
            return nil
        }
        let preferred = preferredFilename(for: fragment)
        return cachedMediaURL(for: storagePath, roomID: fragment.roomId, preferredFilename: preferred)
    }

    nonisolated private func preferredFilename(for fragment: SharedFragment) -> String? {
        if let ext = fragment.mediaReference?.fileExtension, !ext.isEmpty {
            return "\(fragment.id).\(ext)"
        }
        return nil
    }

    nonisolated private func isValidFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 0 else {
            return false
        }
        return true
    }

    /// Checks if the media for a SharedMediaReference already exists on disk.
    nonisolated public func cachedMediaURL(for mediaReference: SharedMediaReference, roomID: String) -> URL? {
        if let local = mediaReference.localFileURL, isValidFile(at: local) {
            return local
        }
        guard let storagePath = mediaReference.storagePath, !storagePath.isEmpty else {
            return nil
        }
        let preferred = (storagePath as NSString).lastPathComponent
        return cachedMediaURL(for: storagePath, roomID: roomID, preferredFilename: preferred)
    }

    // MARK: - Main Media Retrieval Pipeline

    /// Resolves, downloads, and caches the remote media file for a given SharedFragment.
    ///
    /// Preserves local optimistic media if `localFileURL` is already valid on disk.
    public func localMediaURL(for fragment: SharedFragment) async throws -> URL {
        // 1. Guard local optimistic media (Requirement 11: preserve local capture)
        if let local = fragment.mediaReference?.localFileURL, isValidFile(at: local) {
            return local
        }

        // 2. Storage path validation
        guard let storagePath = fragment.mediaReference?.storagePath,
              !storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteMediaError.missingStoragePath
        }

        let preferred = preferredFilename(for: fragment)
        return try await localMediaURL(for: storagePath, roomID: fragment.roomId, preferredFilename: preferred)
    }

    /// Resolves, downloads, and caches the remote media file for a given SharedMediaReference.
    public func localMediaURL(for mediaReference: SharedMediaReference, roomID: String) async throws -> URL {
        if let local = mediaReference.localFileURL, isValidFile(at: local) {
            return local
        }
        guard let storagePath = mediaReference.storagePath,
              !storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteMediaError.missingStoragePath
        }
        let preferred = (storagePath as NSString).lastPathComponent
        return try await localMediaURL(for: storagePath, roomID: roomID, preferredFilename: preferred)
    }

    /// Convenience overload for UUID room identifiers.
    public func localMediaURL(for storagePath: String, roomID: UUID, preferredFilename: String? = nil) async throws -> URL {
        try await localMediaURL(for: storagePath, roomID: roomID.uuidString, preferredFilename: preferredFilename)
    }

    /// Retrieves the local file URL for a given remote storagePath in a room.
    ///
    /// Pipeline:
    /// 1. Fast Cache Hit Check -> Return existing file immediately (0 network calls).
    /// 2. In-Flight Task Deduplication -> Join running task if another caller is downloading the same path.
    /// 3. Download Execution -> Resolve signed URL via SupabaseRoomRepository -> Fetch data via URLSession -> Atomically write to cache.
    public func localMediaURL(
        for storagePath: String,
        roomID: String,
        preferredFilename: String? = nil
    ) async throws -> URL {
        let destURL = destinationURL(for: storagePath, roomID: roomID, preferredFilename: preferredFilename)

        // Step 1: Cache Hit Check
        if isValidFile(at: destURL) {
            print("🎯 [RemoteMediaService] Cache HIT for \(storagePath) (room: \(roomID))")
            return destURL
        }

        // Step 2: Concurrency & Deduplication
        if let inFlight = inFlightTasks[storagePath] {
            print("⏳ [RemoteMediaService] Deduplication: Awaiting existing download for \(storagePath)")
            return try await inFlight.value
        }

        // Step 3: Launch new download task
        let downloadTask = Task<URL, Error> {
            try await self.performDownloadWithRetry(
                storagePath: storagePath,
                roomID: roomID,
                destinationURL: destURL
            )
        }

        inFlightTasks[storagePath] = downloadTask

        do {
            let localURL = try await downloadTask.value
            inFlightTasks.removeValue(forKey: storagePath)
            return localURL
        } catch {
            inFlightTasks.removeValue(forKey: storagePath)
            throw error
        }
    }

    // MARK: - Download Execution & Transient Retry

    private func performDownloadWithRetry(
        storagePath: String,
        roomID: String,
        destinationURL: URL
    ) async throws -> URL {
        var lastError: Error?

        for attempt in 1...2 {
            do {
                return try await executeDownloadPipeline(
                    storagePath: storagePath,
                    roomID: roomID,
                    destinationURL: destinationURL
                )
            } catch {
                lastError = error
                if attempt == 1 && isTransientError(error) {
                    print("⚠️ [RemoteMediaService] Transient download error on attempt 1 for \(storagePath): \(error.localizedDescription). Retrying once...")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms backoff
                    continue
                } else {
                    break
                }
            }
        }

        throw lastError ?? RemoteMediaError.invalidResponse
    }

    private func executeDownloadPipeline(
        storagePath: String,
        roomID: String,
        destinationURL: URL
    ) async throws -> URL {
        print("⬇️ [RemoteMediaService] Download START for \(storagePath) (room: \(roomID))")

        // 1. Resolve signed URL via existing repository layer (or test resolver)
        let signedURL: URL
        if let customResolver = customSignedURLResolver {
            signedURL = try await customResolver(storagePath, 3600)
        } else {
            signedURL = try await repository.createSignedMediaURL(storagePath: storagePath, expiresIn: 3600)
        }
        print("🔑 [RemoteMediaService] Resolved signed URL for \(storagePath)")

        // 2. Fetch binary via URLSession
        // TEMPORARY diagnostic (no behavior change; never logs URLs/tokens).
        print("[MediaDebug] Starting Storage download")
        print("[MediaDebug] path: \(storagePath)")
        let data: Data
        let httpStatus: Int
        do {
            let (fetchedData, response) = try await urlSession.data(from: signedURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[MediaDebug] Storage download FAILED")
                print("[MediaDebug] error: non-HTTP response")
                throw RemoteMediaError.invalidResponse
            }
            httpStatus = httpResponse.statusCode
            guard (200...299).contains(httpStatus) else {
                print("[MediaDebug] Storage download FAILED")
                print("[MediaDebug] error: HTTP \(httpStatus)")
                print("[MediaDebug] statusCode: \(httpStatus)")
                throw RemoteMediaError.httpError(statusCode: httpStatus)
            }
            data = fetchedData
        } catch {
            if error is RemoteMediaError { throw error } // Already logged above.
            print("[MediaDebug] Storage download FAILED")
            print("[MediaDebug] error: \(error)")
            throw error
        }

        guard !data.isEmpty else {
            print("❌ [RemoteMediaService] Download failed: Received empty data for \(storagePath)")
            print("[MediaDebug] Storage download FAILED")
            print("[MediaDebug] error: empty data (0 bytes)")
            print("[MediaDebug] statusCode: \(httpStatus)")
            throw RemoteMediaError.emptyData
        }

        print("[MediaDebug] Storage download SUCCESS")
        print("[MediaDebug] httpStatus: \(httpStatus)")
        print("[MediaDebug] bytes: \(data.count)")

        // 3. Atomically write to cache (temp file -> move)
        let mediaDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: mediaDir.path) {
            try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        }

        let tempURL = mediaDir.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        } catch {
            print("❌ [RemoteMediaService] Disk write failed for \(destinationURL.lastPathComponent): \(error.localizedDescription)")
            print("[MediaDebug] Local media save FAILED")
            print("[MediaDebug] error: \(error)")
            throw RemoteMediaError.diskWriteFailed(error.localizedDescription)
        }

        print("✅ [RemoteMediaService] Download SUCCESS: Cached \(data.count) bytes at \(destinationURL.lastPathComponent)")
        print("[MediaDebug] Local media saved")
        print("[MediaDebug] localPath: \(destinationURL.path)")
        print("[MediaDebug] bytes: \(data.count)")
        return destinationURL
    }

    private func isTransientError(_ error: Error) -> Bool {
        if let remoteErr = error as? RemoteMediaError {
            switch remoteErr {
            case .httpError(let code):
                return code >= 500
            default:
                return false
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotConnectToHost:
                return true
            default:
                return false
            }
        }
        return false
    }

    // MARK: - Cache Eviction / Cleanup Helpers

    /// Clears media cached for a specific room.
    public func clearCache(for roomID: String) throws {
        let dir = mediaDirectory(for: roomID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
            print("🗑️ [RemoteMediaService] Purged media cache for room: \(roomID)")
        }
    }

    /// Removes an individual media file from the local cache.
    public func removeMedia(for storagePath: String, roomID: String, preferredFilename: String? = nil) throws {
        let dest = destinationURL(for: storagePath, roomID: roomID, preferredFilename: preferredFilename)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
            print("🗑️ [RemoteMediaService] Removed cached media: \(dest.lastPathComponent)")
        }
    }
}
