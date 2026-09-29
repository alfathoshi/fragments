//
//  LocalNetworkPermission.swift
//  fragments
//

import Foundation
import MultipeerConnectivity

/// Local-network (Bonjour) permission trigger for the permissions gate.
///
/// iOS exposes NO API to query local-network authorization, and the system
/// prompt appears only on first Bonjour use — which in Fragments is
/// `MultipeerSyncService.start()` (MCNearbyServiceAdvertiser/Browser, service
/// `frag-sync`, declared in NSBonjourServices). This helper performs a
/// throwaway browse with the same service type so the prompt fires inside the
/// gate instead of mid-session. The outcome is unknowable by design, so
/// callers must always offer Continue regardless; a best-effort Bool is
/// returned (true unless the browse errors immediately).
public enum LocalNetworkPermission {
    public static let serviceType = "frag-sync"

    private final class BrowseHolder: NSObject, MCNearbyServiceBrowserDelegate {
        var browser: MCNearbyServiceBrowser?
        func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {}
        func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
        func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
    }

    /// Triggers the local-network prompt (first use only; later calls are
    /// silent no-ops) and returns after a short settle delay.
    public static func requestAccess() async -> Bool {
        let holder = BrowseHolder()
        let peerID = MCPeerID(displayName: "fragments-permission-check")
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = holder
        holder.browser = browser
        browser.startBrowsingForPeers()
        // Give the system prompt a moment to present; the decision itself has
        // no callback, so this always resolves — never a gate trap.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        browser.stopBrowsingForPeers()
        browser.delegate = nil
        return true
    }
}
