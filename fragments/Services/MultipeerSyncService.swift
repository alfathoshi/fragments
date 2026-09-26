//
//  MultipeerSyncService.swift
//  fragments
//
//  Created on 9/27/26.
//

import Foundation
import MultipeerConnectivity
import Observation

// MARK: - Message Protocol

public enum MultipeerMessageType: String, Codable, Sendable {
    case handshake
    case fragment
    case syncRequest
    case syncResponse
    case sessionEnded
}

public struct MultipeerPacket: Codable, Sendable {
    public let type: MultipeerMessageType
    public let roomID: String
    public let member: RoomMember?
    public let fragment: SharedFragment?
    public let mediaBase64: String?
    public let mediaExtension: String?
    public let fragmentsList: [SharedFragment]?
    public let finalTitle: String?
    public let finalCategory: String?

    public init(
        type: MultipeerMessageType,
        roomID: String,
        member: RoomMember? = nil,
        fragment: SharedFragment? = nil,
        mediaBase64: String? = nil,
        mediaExtension: String? = nil,
        fragmentsList: [SharedFragment]? = nil,
        finalTitle: String? = nil,
        finalCategory: String? = nil
    ) {
        self.type = type
        self.roomID = roomID
        self.member = member
        self.fragment = fragment
        self.mediaBase64 = mediaBase64
        self.mediaExtension = mediaExtension
        self.fragmentsList = fragmentsList
        self.finalTitle = finalTitle
        self.finalCategory = finalCategory
    }
}

// MARK: - MultipeerSyncService

@Observable
public final class MultipeerSyncService: NSObject, @unchecked Sendable {
    public static let shared = MultipeerSyncService()

    /// Multipeer service identifier (must be <= 15 chars, alphanumeric + hyphens).
    public static let serviceType = "frag-sync"

    // MARK: - Observable State

    public private(set) var isRunning: Bool = false
    public private(set) var connectedPeerCount: Int = 0
    public private(set) var connectedPeerNames: [String] = []
    public private(set) var currentRoomID: String? = nil
    public private(set) var nearbyMembers: [RoomMember] = []

    public var isLiveConnected: Bool {
        connectedPeerCount > 0
    }

    // MARK: - Callbacks

    public var onFragmentReceived: ((SharedFragment) -> Void)?
    public var onMemberReceived: ((RoomMember) -> Void)?
    public var onSyncRequest: (() -> [SharedFragment])?
    public var onConnectionChange: ((Int) -> Void)?
    public var onSessionEnded: ((_ finalTitle: String) -> Void)?

    // MARK: - Internal Multipeer Objects

    public private(set) var isHost: Bool = false
    private var localPeerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var currentLocalMember: RoomMember?

    private let stateLock = NSLock()

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Starts advertising and browsing for peers participating in the specified collaborative room.
    public func start(roomID: String, localMember: RoomMember, isHost: Bool = false) {
        stop()

        stateLock.lock()
        self.currentRoomID = roomID
        self.currentLocalMember = localMember
        self.isHost = isHost
        self.isRunning = true
        stateLock.unlock()

        let sanitizedName = String(localMember.displayName.prefix(40))
        let peerID = MCPeerID(displayName: "\(sanitizedName)_\(UUID().uuidString.prefix(4))")
        self.localPeerID = peerID

        let sess = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        sess.delegate = self
        self.session = sess

        let shortCode = String(roomID.prefix(8)).uppercased()
        let discoveryInfo: [String: String] = [
            "roomID": roomID,
            "shortCode": shortCode,
            "role": isHost ? "host" : "member"
        ]

        let adv = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        adv.delegate = self
        self.advertiser = adv
        adv.startAdvertisingPeer()

        let brow = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: Self.serviceType
        )
        brow.delegate = self
        self.browser = brow
        brow.startBrowsingForPeers()

        print("📡 [MultipeerSync] Started for Room \(shortCode) as \(isHost ? "Host" : "Joiner")")
    }

    /// Stops all advertising, browsing, and disconnects active session.
    public func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        session?.disconnect()
        session?.delegate = nil
        session = nil

        localPeerID = nil
        currentRoomID = nil
        currentLocalMember = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.connectedPeerCount = 0
            self.connectedPeerNames = []
            self.nearbyMembers = []
            self.onConnectionChange?(0)
        }
    }

    // MARK: - Data Broadcasting

    /// Broadcasts a newly captured fragment to all currently connected peers.
    public func broadcastFragment(_ fragment: SharedFragment, mediaFileURL: URL? = nil) {
        guard let session = session, !session.connectedPeers.isEmpty, let roomID = currentRoomID else {
            return
        }

        var base64: String? = nil
        var fileExt: String? = nil

        let targetURL = mediaFileURL ?? fragment.mediaReference?.localFileURL
        if let targetURL = targetURL, let data = try? Data(contentsOf: targetURL) {
            base64 = data.base64EncodedString()
            fileExt = targetURL.pathExtension
        }

        let packet = MultipeerPacket(
            type: .fragment,
            roomID: roomID,
            fragment: fragment,
            mediaBase64: base64,
            mediaExtension: fileExt
        )

        self.sendPacket(packet)
    }

    /// Sends a handshake packet to a newly connected peer.
    private func sendHandshake(to peer: MCPeerID) {
        guard let member = currentLocalMember, let roomID = currentRoomID else { return }
        let packet = MultipeerPacket(
            type: .handshake,
            roomID: roomID,
            member: member
        )
        sendPacket(packet, to: [peer])
    }

    /// Requests full sync from the host or connected peers.
    public func requestSync() {
        guard let roomID = currentRoomID else { return }
        let packet = MultipeerPacket(
            type: .syncRequest,
            roomID: roomID
        )
        sendPacket(packet)
    }

    /// Sends a packet to connected peers.
    private func sendPacket(_ packet: MultipeerPacket, to peers: [MCPeerID]? = nil) {
        guard let session = session else { return }
        let targetPeers = peers ?? session.connectedPeers
        guard !targetPeers.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(packet)
            try session.send(data, toPeers: targetPeers, with: .reliable)
        } catch {
            print("⚠️ [MultipeerSync] Failed to send packet: \(error.localizedDescription)")
        }
    }

    // MARK: - Incoming Packet Handler

    private func handleReceivedPacket(_ packet: MultipeerPacket, from peer: MCPeerID) {
        guard packet.roomID == currentRoomID || packet.roomID.prefix(8) == currentRoomID?.prefix(8) else {
            return
        }

        switch packet.type {
        case .handshake:
            if let member = packet.member {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if !self.nearbyMembers.contains(where: { $0.id == member.id || $0.userId == member.userId }) {
                        self.nearbyMembers.append(member)
                    }
                    self.onMemberReceived?(member)
                }
            }

        case .fragment:
            if var frag = packet.fragment {
                // If media was transferred as Base64, write to local file in Documents
                if let base64 = packet.mediaBase64, let data = Data(base64Encoded: base64) {
                    let ext = packet.mediaExtension ?? "jpg"
                    let fileName = "Peer_\(frag.id).\(ext)"
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let fileURL = docs.appendingPathComponent(fileName)
                    try? data.write(to: fileURL)

                    var mediaRef = frag.mediaReference ?? SharedMediaReference()
                    mediaRef.localFileURL = fileURL
                    mediaRef.fileExtension = ext
                    frag.mediaReference = mediaRef
                }

                DispatchQueue.main.async { [weak self] in
                    self?.onFragmentReceived?(frag)
                }
            }

        case .syncRequest:
            if let allFragments = onSyncRequest?(), !allFragments.isEmpty, let roomID = currentRoomID {
                let response = MultipeerPacket(
                    type: .syncResponse,
                    roomID: roomID,
                    fragmentsList: allFragments
                )
                sendPacket(response, to: [peer])
            }

        case .syncResponse:
            if let list = packet.fragmentsList {
                for frag in list {
                    DispatchQueue.main.async { [weak self] in
                        self?.onFragmentReceived?(frag)
                    }
                }
            }

        case .sessionEnded:
            let title = packet.finalTitle ?? "Shared Moment"
            DispatchQueue.main.async { [weak self] in
                self?.onSessionEnded?(title)
            }
        }
    }

    /// Broadcasts sessionEnded notification to all connected peers.
    public func broadcastSessionEnded(finalTitle: String, finalCategory: String? = nil) {
        guard let roomID = currentRoomID else { return }
        let packet = MultipeerPacket(
            type: .sessionEnded,
            roomID: roomID,
            finalTitle: finalTitle,
            finalCategory: finalCategory
        )
        sendPacket(packet)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSyncService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let connectedList = session.connectedPeers
        let count = connectedList.count
        let names = connectedList.map { $0.displayName }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedPeerCount = count
            self.connectedPeerNames = names
            self.onConnectionChange?(count)
        }

        switch state {
        case .connected:
            print("🟢 [MultipeerSync] Connected to peer: \(peerID.displayName)")
            // Immediately exchange handshakes
            sendHandshake(to: peerID)
            // If we are a collaborator, request sync from host
            if !isHost {
                requestSync()
            }
        case .connecting:
            print("🟡 [MultipeerSync] Connecting to peer: \(peerID.displayName)")
        case .notConnected:
            print("🔴 [MultipeerSync] Disconnected from peer: \(peerID.displayName)")
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let packet = try JSONDecoder().decode(MultipeerPacket.self, from: data)
            handleReceivedPacket(packet, from: peerID)
        } catch {
            print("⚠️ [MultipeerSync] Could not decode incoming packet: \(error)")
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerSyncService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Accept invitation if context contains matching roomID or shortCode
        guard let session = self.session else {
            invitationHandler(false, nil)
            return
        }

        if let context = context, let contextStr = String(data: context, encoding: .utf8) {
            let short = String(currentRoomID?.prefix(8) ?? "")
            let isMatch = contextStr == currentRoomID ||
                          contextStr == short ||
                          (currentRoomID?.hasPrefix(contextStr) ?? false)
            if isMatch {
                print("🤝 [MultipeerSync] Accepting matching invitation from \(peerID.displayName)")
                invitationHandler(true, session)
                return
            }
        }

        // Accept if room is active
        if currentRoomID != nil {
            print("🤝 [MultipeerSync] Auto-accepting invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        } else {
            invitationHandler(false, nil)
        }
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("⚠️ [MultipeerSync] Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSyncService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session = self.session, let roomID = self.currentRoomID else { return }

        // Filter discovery info by roomID or shortCode
        let peerRoomID = info?["roomID"] ?? ""
        let peerShortCode = info?["shortCode"] ?? ""
        let currentShort = String(roomID.prefix(8)).uppercased()

        let isMatch = peerRoomID == roomID || peerShortCode == currentShort || (peerRoomID.hasPrefix(currentShort))

        guard isMatch else { return }

        // Already connected?
        guard !session.connectedPeers.contains(peerID) else { return }

        // Tie-breaker rule to avoid dual simultaneous invite collisions:
        // A peer only invites if its displayName is alphabetically lower than target peer,
        // OR if this device is not the host (joiner invites host).
        let shouldInvite = !isHost || (localPeerID?.displayName ?? "") < peerID.displayName
        if shouldInvite {
            print("🔍 [MultipeerSync] Inviting peer \(peerID.displayName) to Room \(currentShort)...")
            let context = roomID.data(using: .utf8)
            browser.invitePeer(peerID, to: session, withContext: context, timeout: 15)
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 [MultipeerSync] Lost peer: \(peerID.displayName)")
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("⚠️ [MultipeerSync] Failed to start browsing: \(error.localizedDescription)")
    }
}
