//
//  GameSessionManager.swift
//  arena
//

import Foundation
import MultipeerConnectivity

protocol GameSessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: GameSessionManager, didReceive message: WireMessage, from peer: MCPeerID)
    func sessionManager(_ manager: GameSessionManager, peer peerID: MCPeerID, didChange state: MCSessionState)
    func sessionManager(_ manager: GameSessionManager, didConnect peer: MCPeerID)
    func sessionManager(_ manager: GameSessionManager, didDisconnect peer: MCPeerID)
}

final class GameSessionManager: NSObject {
    weak var delegate: GameSessionManagerDelegate?

    private(set) var localPlayerId: UUID
    private(set) var displayName: String

    private let serviceType = GameConstants.multipeerServiceType
    private var session: MCSession!
    private var peerID: MCPeerID!

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var currentJoinCode: String?

    private(set) var isHost: Bool = false

    /// MCPeerID string -> player UUID (from hello / roster).
    private var peerToPlayer: [String: UUID] = [:]

    var connectedPeerIDs: [MCPeerID] {
        session?.connectedPeers ?? []
    }

    init(localPlayerId: UUID, displayName: String) {
        self.localPlayerId = localPlayerId
        self.displayName = displayName
        super.init()
        self.peerID = MCPeerID(displayName: localPlayerId.uuidString)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .optional)
        self.session.delegate = self
    }

    func updateIdentity(displayName: String) {
        self.displayName = displayName
    }

    // MARK: - Host / guest

    func startHosting() {
        stopNetworking()
        isHost = true
        currentJoinCode = Self.makeJoinCode()
        let info = ["role": "host"]
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func startBrowsingForHost(joinCode: String) {
        stopNetworking()
        isHost = false
        currentJoinCode = Self.normalizeJoinCode(joinCode)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopNetworking() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func disconnectAll() {
        stopNetworking()
        session.disconnect()
        peerToPlayer.removeAll()
        currentJoinCode = nil
    }

    /// Host peer when joining (clients only).
    private var discoveredHost: MCPeerID?

    func inviteDiscoveredHostIfNeeded() {
        guard !isHost, let host = discoveredHost else { return }
        guard session.connectedPeers.contains(host) == false else { return }
        browser?.invitePeer(host, to: session, withContext: currentJoinCode?.data(using: .utf8), timeout: 30)
    }

    // MARK: - Mapping

    func registerPeer(_ peer: MCPeerID, playerId: UUID) {
        peerToPlayer[peer.displayName] = playerId
    }

    func playerId(for peer: MCPeerID) -> UUID? {
        peerToPlayer[peer.displayName]
    }

    func peerID(forPlayerId playerId: UUID) -> MCPeerID? {
        session.connectedPeers.first { peerToPlayer[$0.displayName] == playerId }
    }

    // MARK: - Send

    /// Sends to every connected peer (host only in star topology has the full mesh to all clients).
    func broadcast(_ message: WireMessage, reliable: Bool = true) {
        send(message, to: session.connectedPeers, reliable: reliable)
    }

    /// Clients send to the host; the host should rebroadcast to everyone else.
    /// - Important: In a multi-peer `MCSession`, peers form a mesh — `connectedPeers` order is undefined.
    ///   Never use `connectedPeers.first`; resolve the host by `hostPlayerId` from game state.
    func sendToHost(_ message: WireMessage, hostPlayerId: UUID) {
        guard !isHost else { return }
        let peers = session.connectedPeers
        guard peers.isEmpty == false else { return }

        if let hostPeer = peerID(forPlayerId: hostPlayerId) {
            send(message, to: [hostPeer], reliable: true)
            return
        }
        if peers.count == 1, let only = peers.first {
            send(message, to: [only], reliable: true)
            return
        }
        if let h = discoveredHost, peers.contains(h) {
            send(message, to: [h], reliable: true)
            return
        }
        #if DEBUG
        print("sendToHost: could not resolve host (hostPlayerId \(hostPlayerId)) among \(peers.count) peers")
        #endif
    }

    /// Delivers to all participants: host multicasts; guests forward to the host first.
    /// - Parameter hostPlayerId: Authoritative host player id from `GameState.hostPlayerId` (required for guests).
    func deliverToEveryone(_ message: WireMessage, reliable: Bool = true, hostPlayerId: UUID) {
        if isHost {
            broadcast(message, reliable: reliable)
        } else {
            sendToHost(message, hostPlayerId: hostPlayerId)
        }
    }

    func send(_ message: WireMessage, to peers: [MCPeerID], reliable: Bool = true) {
        guard peers.isEmpty == false else { return }
        do {
            let data = try JSONEncoder().encode(message)
            let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
            try session.send(data, toPeers: peers, with: mode)
        } catch {
            #if DEBUG
            print("GameSessionManager send error: \(error)")
            #endif
        }
    }

    private func handleIncoming(data: Data, from peer: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(WireMessage.self, from: data)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.sessionManager(self, didReceive: message, from: peer)
            }
        } catch {
            #if DEBUG
            print("GameSessionManager decode error: \(error)")
            #endif
        }
    }

    private static func makeJoinCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func normalizeJoinCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

extension GameSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.sessionManager(self, peer: peerID, didChange: state)
            switch state {
            case .connected:
                self.delegate?.sessionManager(self, didConnect: peerID)
            case .notConnected:
                self.delegate?.sessionManager(self, didDisconnect: peerID)
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleIncoming(data: data, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension GameSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        #if DEBUG
        print("Advertiser error: \(error)")
        #endif
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let expected = currentJoinCode?.data(using: .utf8)
        guard let expected, context == expected else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }
}

extension GameSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Only hosts advertise `serviceType`; joiners browse. Do not require discoveryInfo —
            // it is often nil on first callback, which previously prevented any invite.
            if let role = info?["role"], role != "host" { return }
            self.discoveredHost = peerID
            self.inviteDiscoveredHostIfNeeded()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if peerID == self.discoveredHost {
                self.discoveredHost = nil
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        #if DEBUG
        print("Browser error: \(error)")
        #endif
    }
}
