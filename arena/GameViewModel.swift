//
//  GameViewModel.swift
//  arena
//

import Combine
import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit

@MainActor
final class GameViewModel: ObservableObject {
    @Published var gameState: GameState
    @Published var displayName: String
    @Published var statusMessage: String = ""

    let localPlayerId: UUID

    private let session: GameSessionManager
    private let motion = MotionManager()
    private let proximity = ProximityManager()

    private var tickCancellable: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private var gameplayInfrastructureStarted = false

    var proximitySummary: String {
        let n = proximity.lastRSSIByPlayerId.count
        return "BLE samples: \(n). Shoot threshold ≥ \(GameConstants.shootRSSIThreshold) dBm. BT: \(String(describing: proximity.bluetoothState))."
    }

    init(localPlayerId: UUID = UUID(), displayName: String = UIDevice.current.name) {
        self.localPlayerId = localPlayerId
        self.displayName = displayName
        self.gameState = GameStateEngine.makeLobby(hostPlayerId: localPlayerId, displayName: displayName)
        self.session = GameSessionManager(localPlayerId: localPlayerId, displayName: displayName)
        self.session.delegate = self
        self.motion.delegate = self
        self.proximity.configure(playerId: localPlayerId)

        proximity.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }

    var isHost: Bool { session.isHost }

    func hostGame() {
        session.disconnectAll()
        gameplayInfrastructureStarted = false
        session.updateIdentity(displayName: displayName)
        gameState = GameStateEngine.makeLobby(hostPlayerId: localPlayerId, displayName: displayName)
        session.startHosting()
        statusMessage = "Hosting — waiting for players"
    }

    func joinGame() {
        session.disconnectAll()
        gameplayInfrastructureStarted = false
        session.updateIdentity(displayName: displayName)
        gameState = GameState(
            phase: .lobby,
            players: [
                PlayerState(
                    id: localPlayerId,
                    displayName: displayName,
                    team: .a,
                    health: GameConstants.playerMaxHealth,
                    isDead: false,
                    respawnAt: nil,
                    hasPlacedCheckpoint: false
                )
            ],
            checkpoints: [],
            winningTeam: nil,
            hostPlayerId: localPlayerId
        )
        session.startBrowsingForHost()
        statusMessage = "Looking for a host…"
    }

    func disconnect() {
        tickCancellable?.cancel()
        tickCancellable = nil
        gameplayInfrastructureStarted = false
        motion.stop()
        proximity.stop()
        session.disconnectAll()
        statusMessage = "Disconnected"
    }

    func returnToLobby() {
        disconnect()
        gameState = GameStateEngine.makeLobby(hostPlayerId: localPlayerId, displayName: displayName)
    }

    func startMatchFromLobby() {
        guard session.isHost else { return }
        guard gameState.players.count >= GameConstants.minPlayersToStart else { return }
        guard gameState.players.count <= GameConstants.maxPlayers else { return }

        GameStateEngine.assignTeamsRandomly(&gameState)
        objectWillChange.send()
        session.broadcast(.hostStartedPlacing(gameState), reliable: true)
        statusMessage = "Place your checkpoint"
    }

    func placeCheckpoint(normalizedX: Double, normalizedY: Double) {
        guard let me = gameState.players.first(where: { $0.id == localPlayerId }) else { return }
        guard gameState.phase == .placingCheckpoints else { return }
        guard me.hasPlacedCheckpoint == false else { return }
        guard GameStateEngine.normalizedCheckpointIsValid(team: me.team, x: normalizedX, y: normalizedY) else {
            statusMessage = "Stay on your side of the field (A: left, B: right)."
            return
        }

        let checkpoint = CheckpointState(
            id: UUID(),
            ownerPlayerId: me.id,
            team: me.team,
            xp: GameConstants.checkpointMaxXP,
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )

        if let idx = gameState.players.firstIndex(where: { $0.id == localPlayerId }) {
            gameState.players[idx].hasPlacedCheckpoint = true
        }

        mergeCheckpoint(checkpoint)
        session.deliverToEveryone(.checkpointPlaced(playerId: localPlayerId, checkpoint: checkpoint))

        if session.isHost {
            tryAdvancePlacingHost()
        }
    }

    func beginPlayingIfReady() {
        guard session.isHost else { return }
        tryAdvancePlacingHost()
    }

    private func tryAdvancePlacingHost() {
        guard session.isHost else { return }
        guard gameState.phase == .placingCheckpoints else { return }
        guard GameStateEngine.allCheckpointsPlaced(gameState) else { return }

        gameState.phase = .playing
        objectWillChange.send()
        session.broadcast(.allCheckpointsReady(gameState), reliable: true)
        startGameplayInfrastructure()
        statusMessage = "Game on — jump to shoot"
    }

    private func startGameplayInfrastructure() {
        guard gameplayInfrastructureStarted == false else { return }
        gameplayInfrastructureStarted = true
        motion.start()
        proximity.start()
        tickCancellable?.cancel()
        tickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTick()
            }
    }

    private func handleTick() {
        GameStateEngine.tickRespawns(&gameState, now: Date())
        objectWillChange.send()
        guard gameState.phase == .playing else { return }
        guard session.isHost else { return }
        if let winner = GameStateEngine.winnerIfAny(gameState) {
            gameState.phase = .ended
            gameState.winningTeam = winner
            objectWillChange.send()
            session.broadcast(.gameOver(winningTeam: winner, state: gameState), reliable: true)
            motion.stop()
            proximity.stop()
            gameplayInfrastructureStarted = false
        }
    }

    private func mergeCheckpoint(_ checkpoint: CheckpointState) {
        if let i = gameState.checkpoints.firstIndex(where: { $0.ownerPlayerId == checkpoint.ownerPlayerId }) {
            gameState.checkpoints[i] = checkpoint
        } else {
            gameState.checkpoints.append(checkpoint)
        }
        objectWillChange.send()
    }

    private func replaceState(_ newValue: GameState) {
        gameState = newValue
        switch newValue.phase {
        case .playing:
            startGameplayInfrastructure()
        case .lobby:
            gameplayInfrastructureStarted = false
        case .ended:
            motion.stop()
            proximity.stop()
            gameplayInfrastructureStarted = false
        default:
            break
        }
    }

    // MARK: - Proximity helpers

    private func isEnemyPlayerInShootRange(_ enemyId: UUID) -> Bool {
        if proximity.isPlayerInShootRange(enemyId) { return true }
        if GameConstants.proximityFallbackToAllConnectedPeers {
            return session.peerID(forPlayerId: enemyId) != nil
        }
        return false
    }

    func buildShootEventIfPossible() -> ShootEvent? {
        guard gameState.phase == .playing else { return nil }
        guard let selfPlayer = gameState.players.first(where: { $0.id == localPlayerId }) else { return nil }
        guard selfPlayer.isDead == false else { return nil }

        let enemies = gameState.players.filter { $0.team != selfPlayer.team && $0.isDead == false }
        if let hit = enemies.first(where: { isEnemyPlayerInShootRange($0.id) }) {
            return ShootEvent(
                shooterId: localPlayerId,
                damagedPlayerId: hit.id,
                damagedCheckpointId: nil,
                playerDamage: GameConstants.playerShotDamage,
                checkpointDamage: 0
            )
        }

        let enemyCPs = gameState.checkpoints.filter { $0.team != selfPlayer.team && $0.xp > 0 }
        for cp in enemyCPs {
            guard let owner = gameState.players.first(where: { $0.id == cp.ownerPlayerId }) else { continue }
            if isEnemyPlayerInShootRange(owner.id) {
                return ShootEvent(
                    shooterId: localPlayerId,
                    damagedPlayerId: nil,
                    damagedCheckpointId: cp.id,
                    playerDamage: 0,
                    checkpointDamage: GameConstants.checkpointShotDamage
                )
            }
        }

        return nil
    }

    private func handleShootDetected() {
        guard let event = buildShootEventIfPossible() else {
            statusMessage = "No target in range"
            return
        }

        if session.isHost {
            GameStateEngine.applyShoot(&gameState, event: event)
            objectWillChange.send()
            session.broadcast(.fullState(gameState), reliable: true)
            if gameState.phase == .ended, let winner = gameState.winningTeam {
                session.broadcast(.gameOver(winningTeam: winner, state: gameState), reliable: true)
                motion.stop()
                proximity.stop()
                gameplayInfrastructureStarted = false
            }
        } else {
            session.sendToHost(.shootEvent(event))
        }
    }

    private func upsertPlayerFromHello(id: UUID, name: String) {
        if let idx = gameState.players.firstIndex(where: { $0.id == id }) {
            gameState.players[idx].displayName = name
        } else {
            let p = PlayerState(
                id: id,
                displayName: name,
                team: .a,
                health: GameConstants.playerMaxHealth,
                isDead: false,
                respawnAt: nil,
                hasPlacedCheckpoint: false
            )
            gameState.players.append(p)
        }
        objectWillChange.send()
    }

    private func sendHello() {
        session.deliverToEveryone(.hello(playerId: localPlayerId, displayName: displayName), reliable: true)
    }
}

extension GameViewModel: GameSessionManagerDelegate {
    nonisolated func sessionManager(_ manager: GameSessionManager, didReceive message: WireMessage, from peer: MCPeerID) {
        Task { @MainActor in
            self.handleWireMessage(message, peer: peer)
        }
    }

    nonisolated func sessionManager(_ manager: GameSessionManager, peer peerID: MCPeerID, didChange state: MCSessionState) {}

    nonisolated func sessionManager(_ manager: GameSessionManager, didConnect peer: MCPeerID) {
        Task { @MainActor in
            self.sendHello()
            if self.session.isHost == false {
                self.session.sendToHost(.requestFullState)
            }
        }
    }

    nonisolated func sessionManager(_ manager: GameSessionManager, didDisconnect _: MCPeerID) {}

    private func handleWireMessage(_ message: WireMessage, peer: MCPeerID) {
        switch message {
        case let .hello(playerId, name):
            session.registerPeer(peer, playerId: playerId)
            if session.isHost {
                upsertPlayerFromHello(id: playerId, name: name)
                session.broadcast(.fullState(gameState), reliable: true)
            } else {
                upsertPlayerFromHello(id: playerId, name: name)
            }

        case .requestFullState:
            if session.isHost {
                session.broadcast(.fullState(gameState), reliable: true)
            }

        case let .fullState(state):
            if session.isHost == false {
                replaceState(state)
            }

        case let .hostStartedPlacing(state):
            replaceState(state)
            statusMessage = "Place your checkpoint"

        case let .checkpointPlaced(pid, checkpoint):
            if pid == localPlayerId { return }
            if let idx = gameState.players.firstIndex(where: { $0.id == pid }) {
                gameState.players[idx].hasPlacedCheckpoint = true
            }
            mergeCheckpoint(checkpoint)
            if session.isHost {
                session.broadcast(.checkpointPlaced(playerId: pid, checkpoint: checkpoint), reliable: true)
                tryAdvancePlacingHost()
            }

        case let .allCheckpointsReady(state):
            replaceState(state)
            statusMessage = "Game on — jump to shoot"

        case let .shootEvent(event):
            guard session.isHost else { return }
            GameStateEngine.applyShoot(&gameState, event: event)
            objectWillChange.send()
            session.broadcast(.fullState(gameState), reliable: true)
            if gameState.phase == .ended, let winner = gameState.winningTeam {
                session.broadcast(.gameOver(winningTeam: winner, state: gameState), reliable: true)
                motion.stop()
                proximity.stop()
                gameplayInfrastructureStarted = false
            }

        case let .gameOver(_, state):
            replaceState(state)
            statusMessage = "Game over"
        }
    }
}

extension GameViewModel: MotionManagerDelegate {
    nonisolated func motionManagerDidDetectShot(_ manager: MotionManager) {
        Task { @MainActor in
            self.handleShootDetected()
        }
    }
}
