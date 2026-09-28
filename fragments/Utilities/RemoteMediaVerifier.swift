//
//  RemoteMediaVerifier.swift
//  fragments
//
//  Created on 9/28/26.
//

import Foundation
import UIKit

/// Mock URLProtocol used exclusively for hermetic local testing of `RemoteMediaService`.
private final class MockRemoteMediaURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requestCount: Int = 0
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        lock.lock()
        requestCount = 0
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        let currentHandler = Self.handler
        Self.lock.unlock()

        guard let handler = currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Verification engine for Phase 2: Remote Media Download & Local Cache.
///
/// Validates:
/// - Test A: Cache miss (download from signed URL, save to cache, verify bytes)
/// - Test B: Cache hit (subsequent request returns cached file with 0 network calls)
/// - Test C: Concurrent request deduplication (3 concurrent calls -> 1 download task)
/// - Test D: Missing media handling (nil/empty storagePath fails gracefully)
/// - Test E: Error handling & partial file cleanup (500 error leaves no corrupt file)
/// - Test F: Local optimistic media preservation (localFileURL != nil never downloads)
/// - Test G: Bucket name verification (verifies "moment-media" bucket)
public enum RemoteMediaVerifier {

    public static func runAllTests() async -> (passed: Bool, log: [String]) {
        var logs: [String] = []
        var allPassed = true

        func assertCondition(_ condition: Bool, _ testName: String) {
            if condition {
                logs.append("✅ [PASS] \(testName)")
            } else {
                logs.append("❌ [FAIL] \(testName)")
                allPassed = false
            }
        }

        let fileManager = FileManager.default
        let tempBase = fileManager.temporaryDirectory.appendingPathComponent("TestRooms-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempBase)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRemoteMediaURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let testRoomID = "room-" + UUID().uuidString.lowercased()
        let testSampleData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x42, 0x13, 0x37])

        // -------------------------------------------------------------
        // TEST G: BUCKET NAME AUDIT
        // -------------------------------------------------------------
        logs.append("--- Test G: Bucket Name Audit ---")
        let bucketName = SupabaseRoomRepository.mediaBucketName
        assertCondition(bucketName == "moment-media", "Bucket name matches live Supabase configuration: 'moment-media' (found '\(bucketName)')")

        // -------------------------------------------------------------
        // TEST A: CACHE MISS
        // -------------------------------------------------------------
        logs.append("--- Test A: Cache Miss ---")
        MockRemoteMediaURLProtocol.reset()
        MockRemoteMediaURLProtocol.handler = { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (res, testSampleData)
        }

        let testService = RemoteMediaService(
            fileManager: fileManager,
            urlSession: mockSession,
            baseCacheDirectory: tempBase,
            signedURLResolver: { path, _ in
                URL(string: "https://mock.supabase.co/storage/v1/object/sign/moment-media/\(path)?token=test")!
            }
        )

        let testPathA = "rooms/\(testRoomID)/fragments/frag-a.jpg"
        let expectedURLA = await testService.destinationURL(for: testPathA, roomID: testRoomID, preferredFilename: "frag-a.jpg")

        assertCondition(!fileManager.fileExists(atPath: expectedURLA.path), "Target file does NOT exist before download")

        do {
            let localURL = try await testService.localMediaURL(for: testPathA, roomID: testRoomID, preferredFilename: "frag-a.jpg")
            assertCondition(fileManager.fileExists(atPath: localURL.path), "Local file exists after download")
            let savedData = try? Data(contentsOf: localURL)
            assertCondition(savedData == testSampleData, "Saved file content matches downloaded binary data")
            assertCondition(localURL.path.contains("Rooms/\(testRoomID)/media/frag-a.jpg"), "Cache path matches Library/Caches/Rooms/{roomID}/media/{filename}")
            assertCondition(MockRemoteMediaURLProtocol.requestCount == 1, "Exactly 1 network request was executed on cache miss")
        } catch {
            assertCondition(false, "Cache miss download threw unexpected error: \(error.localizedDescription)")
        }

        // -------------------------------------------------------------
        // TEST B: CACHE HIT
        // -------------------------------------------------------------
        logs.append("--- Test B: Cache Hit ---")
        let requestCountBeforeB = MockRemoteMediaURLProtocol.requestCount

        do {
            let cachedURL = try await testService.localMediaURL(for: testPathA, roomID: testRoomID, preferredFilename: "frag-a.jpg")
            assertCondition(cachedURL == expectedURLA, "Cache hit returns identical local file URL")
            assertCondition(MockRemoteMediaURLProtocol.requestCount == requestCountBeforeB, "0 network requests were initiated on cache hit")
        } catch {
            assertCondition(false, "Cache hit check threw unexpected error: \(error.localizedDescription)")
        }

        // -------------------------------------------------------------
        // TEST C: CONCURRENT REQUEST DEDUPLICATION
        // -------------------------------------------------------------
        logs.append("--- Test C: Concurrent Deduplication ---")
        MockRemoteMediaURLProtocol.reset()
        MockRemoteMediaURLProtocol.handler = { req in
            // Small artificial latency to ensure simultaneous overlap
            Thread.sleep(forTimeInterval: 0.05)
            let res = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (res, testSampleData)
        }

        let testPathC = "rooms/\(testRoomID)/fragments/frag-c.jpg"

        do {
            async let call1 = testService.localMediaURL(for: testPathC, roomID: testRoomID, preferredFilename: "frag-c.jpg")
            async let call2 = testService.localMediaURL(for: testPathC, roomID: testRoomID, preferredFilename: "frag-c.jpg")
            async let call3 = testService.localMediaURL(for: testPathC, roomID: testRoomID, preferredFilename: "frag-c.jpg")

            let (res1, res2, res3) = try await (call1, call2, call3)
            assertCondition(res1 == res2 && res2 == res3, "All 3 concurrent callers received identical local URL")
            assertCondition(MockRemoteMediaURLProtocol.requestCount == 1, "Only 1 network download was performed for 3 concurrent requests (requestCount: \(MockRemoteMediaURLProtocol.requestCount))")
            assertCondition(fileManager.fileExists(atPath: res1.path), "Deduplicated file exists and is intact on disk")
        } catch {
            assertCondition(false, "Concurrent deduplication threw unexpected error: \(error.localizedDescription)")
        }

        // -------------------------------------------------------------
        // TEST D: MISSING MEDIA / NIL STORAGE PATH
        // -------------------------------------------------------------
        logs.append("--- Test D: Missing Media Handling ---")
        let emptyFragment = SharedFragment(
            id: UUID().uuidString,
            roomId: testRoomID,
            authorId: "user_test",
            authorName: "Tester",
            type: .note,
            title: "Text Only Note",
            mediaReference: nil
        )

        do {
            _ = try await testService.localMediaURL(for: emptyFragment)
            assertCondition(false, "localMediaURL(for:) should throw when mediaReference is missing")
        } catch let err as RemoteMediaError {
            assertCondition(err == .missingStoragePath, "Throws RemoteMediaError.missingStoragePath when storagePath is nil")
        } catch {
            assertCondition(false, "Unexpected error type: \(error)")
        }

        // -------------------------------------------------------------
        // TEST E: NETWORK FAILURE & CORRUPT FILE CLEANUP
        // -------------------------------------------------------------
        logs.append("--- Test E: Error Handling & Partial File Cleanup ---")
        MockRemoteMediaURLProtocol.reset()
        MockRemoteMediaURLProtocol.handler = { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (res, Data("Internal Server Error".utf8))
        }

        let testPathE = "rooms/\(testRoomID)/fragments/frag-fail.jpg"
        let expectedURLE = await testService.destinationURL(for: testPathE, roomID: testRoomID, preferredFilename: "frag-fail.jpg")

        do {
            _ = try await testService.localMediaURL(for: testPathE, roomID: testRoomID, preferredFilename: "frag-fail.jpg")
            assertCondition(false, "Should have thrown on HTTP 500 response")
        } catch {
            assertCondition(true, "Download threw expected error on HTTP failure")
            assertCondition(!fileManager.fileExists(atPath: expectedURLE.path), "No corrupt destination file was written on failure")
            // Verify no dangling temp files remain in media directory
            let mediaDir = await testService.mediaDirectory(for: testRoomID)
            let contents = (try? fileManager.contentsOfDirectory(atPath: mediaDir.path)) ?? []
            let tempFiles = contents.filter { $0.hasSuffix(".tmp") }
            assertCondition(tempFiles.isEmpty, "No dangling temporary .tmp files left in cache directory")
        }

        // -------------------------------------------------------------
        // TEST F: LOCAL OPTIMISTIC MEDIA PRESERVATION
        // -------------------------------------------------------------
        logs.append("--- Test F: Local Optimistic Media Preservation ---")
        MockRemoteMediaURLProtocol.reset()

        let localDummyFile = tempBase.appendingPathComponent("local-optimistic.jpg")
        try? testSampleData.write(to: localDummyFile)

        let optimisticFragment = SharedFragment(
            id: UUID().uuidString,
            roomId: testRoomID,
            authorId: "local_author",
            authorName: "Me",
            type: .photo,
            title: "Optimistic Capture",
            mediaReference: SharedMediaReference(
                storagePath: "rooms/\(testRoomID)/fragments/remote-placeholder.jpg",
                localFileURL: localDummyFile
            )
        )

        do {
            let resultURL = try await testService.localMediaURL(for: optimisticFragment)
            assertCondition(resultURL == localDummyFile, "Returns localFileURL directly without downloading")
            assertCondition(MockRemoteMediaURLProtocol.requestCount == 0, "0 network requests made when localFileURL is valid")
        } catch {
            assertCondition(false, "Local optimistic check threw unexpected error: \(error.localizedDescription)")
        }

        return (allPassed, logs)
    }
}
