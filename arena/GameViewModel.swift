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
    @Published var pendingJoinRequests: [JoinRequest] = []
    @Published private(set) var shootingIndicatorUntil: Date = .distantPast
    @Published private(set) var underFireIndicatorUntil: Date = .distantPast

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

    var isShooting: Bool {
        Date() < shootingIndicatorUntil
    }

    var isGettingShotAt: Bool {
        Date() < underFireIndicatorUntil
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

    var currentJoinCode: String? { session.currentJoinCode }

    struct JoinRequest: Identifiable, Equatable {
        let playerId: UUID
        let displayName: String

        var id: UUID { playerId }
    }

    func hostGame() {
        session.disconnectAll()
        gameplayInfrastructureStarted = false
        pendingJoinRequests.removeAll()
        session.updateIdentity(displayName: displayName)
        gameState = GameStateEngine.makeLobby(hostPlayerId: localPlayerId, displayName: displayName)
        session.startHosting()
        statusMessage = "Hosting — share code \(session.currentJoinCode ?? "------")"
    }

    func joinGame(joinCode: String) {
        let normalizedJoinCode = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidJoinCode(normalizedJoinCode) else {
            statusMessage = "Enter the host’s join code"
            return
        }
        session.disconnectAll()
        gameplayInfrastructureStarted = false
        session.updateIdentity(displayName: displayName)
        gameState = GameState(
            phase: .lobby,
            players: [],
            checkpoints: [],
            winningTeam: nil,
            hostPlayerId: localPlayerId,
            fieldBounds: .fallback,
            teamSplitAxis: .leftRight
        )
        session.startBrowsingForHost(joinCode: normalizedJoinCode)
        statusMessage = "Looking for a host with code \(normalizedJoinCode.uppercased())…"
    }

    private static func isValidJoinCode(_ code: String) -> Bool {
        guard code.count == 6 else { return false }
        return code.allSatisfy(\.isNumber)
    }

    func disconnect() {
        tickCancellable?.cancel()
        tickCancellable = nil
        gameplayInfrastructureStarted = false
        pendingJoinRequests.removeAll()
        motion.stop()
        proximity.stop()
        session.disconnectAll()
        statusMessage = "Disconnected"
        shootingIndicatorUntil = .distantPast
        underFireIndicatorUntil = .distantPast
    }

    func returnToLobby() {
        disconnect()
        gameState = GameStateEngine.makeLobby(hostPlayerId: localPlayerId, displayName: displayName)
    }

    func approveJoinRequest(playerId: UUID) {
        guard session.isHost else { return }
        guard let index = pendingJoinRequests.firstIndex(where: { $0.playerId == playerId }) else { return }
        let request = pendingJoinRequests.remove(at: index)
        upsertPlayerFromHello(id: request.playerId, name: request.displayName)
        objectWillChange.send()
        session.broadcast(.fullState(gameState), reliable: true)
        statusMessage = "Approved \(request.displayName)"
    }

    func rejectJoinRequest(playerId: UUID) {
        guard session.isHost else { return }
        guard let index = pendingJoinRequests.firstIndex(where: { $0.playerId == playerId }) else { return }
        let request = pendingJoinRequests.remove(at: index)
        objectWillChange.send()
        statusMessage = "Rejected \(request.displayName)"
    }

    func startMatchFromLobby() {
        guard session.isHost else { return }
        guard gameState.players.count >= GameConstants.minPlayersToStart else { return }
        guard gameState.players.count <= GameConstants.maxPlayers else { return }

        GameStateEngine.assignTeamsRandomly(&gameState)
        objectWillChange.send()
        session.broadcast(.hostStartedPlacing(gameState), reliable: true)
        statusMessage = "Choose the play area on the map"
    }

    /// Host confirms the field after `selectingField`; everyone moves to checkpoint placement.
    func confirmFieldBounds(_ bounds: FieldBounds, splitAxis: TeamSplitAxis) {
        guard session.isHost else { return }
        guard gameState.phase == .selectingField else { return }
        gameState.fieldBounds = bounds.clampedValid()
        gameState.teamSplitAxis = splitAxis
        gameState.phase = .placingCheckpoints
        objectWillChange.send()
        session.broadcast(.fieldBoundsConfirmed(gameState), reliable: true)
        statusMessage = "Place your checkpoint"
    }

    /// Adds a dummy second player so you can start a match on one device (host only, lobby).
    func addSoloTestOpponent() {
        guard session.isHost else { return }
        guard gameState.phase == .lobby else { return }
        guard gameState.players.contains(where: { $0.id == GameConstants.soloTestBotPlayerId }) == false else {
            statusMessage = "Solo test opponent already in roster"
            return
        }
        guard gameState.players.count < GameConstants.maxPlayers else { return }

        let bot = PlayerState(
            id: GameConstants.soloTestBotPlayerId,
            displayName: "Solo test (dummy)",
            team: .a,
            health: GameConstants.playerMaxHealth,
            isDead: false,
            respawnAt: nil,
            hasPlacedCheckpoint: false
        )
        gameState.players.append(bot)
        objectWillChange.send()
        session.broadcast(.fullState(gameState), reliable: true)
        statusMessage = "Added solo test opponent — you can start the match"
    }

    func removeSoloTestOpponent() {
        guard session.isHost else { return }
        guard gameState.phase == .lobby else { return }
        let before = gameState.players.count
        gameState.players.removeAll { $0.id == GameConstants.soloTestBotPlayerId }
        guard gameState.players.count != before else { return }
        objectWillChange.send()
        session.broadcast(.fullState(gameState), reliable: true)
        statusMessage = "Removed solo test opponent"
    }

    /// Adds the dummy opponent if needed, then starts the match (host, lobby).
    func startSoloTestMatchFromLobby() {
        guard session.isHost else { return }
        guard gameState.phase == .lobby else { return }
        if gameState.players.count < GameConstants.minPlayersToStart {
            addSoloTestOpponent()
        }
        startMatchFromLobby()
    }

    /// Host-only bypass for quickly testing `GameView` on one device.
    /// Skips field selection/checkpoint placement and enters `.playing` immediately.
    func startGameplayBypassFromLobby() {
        guard session.isHost else { return }
        guard gameState.phase == .lobby else { return }

        if gameState.players.contains(where: { $0.id == GameConstants.soloTestBotPlayerId }) == false {
            let bot = PlayerState(
                id: GameConstants.soloTestBotPlayerId,
                displayName: "Solo test (dummy)",
                team: .b,
                health: GameConstants.playerMaxHealth,
                isDead: false,
                respawnAt: nil,
                hasPlacedCheckpoint: false
            )
            gameState.players.append(bot)
        }

        for i in gameState.players.indices {
            gameState.players[i].health = GameConstants.playerMaxHealth
            gameState.players[i].isDead = false
            gameState.players[i].respawnAt = nil
            gameState.players[i].hasPlacedCheckpoint = true
            gameState.players[i].team = gameState.players[i].id == localPlayerId ? .a : .b
        }

        gameState.fieldBounds = .defaultPlayArea
        gameState.teamSplitAxis = .leftRight
        gameState.winningTeam = nil

        gameState.checkpoints = gameState.players.map { player in
            let pos = GameStateEngine.defaultCheckpointPosition(team: player.team, splitAxis: gameState.teamSplitAxis)
            return CheckpointState(
                id: UUID(),
                ownerPlayerId: player.id,
                team: player.team,
                xp: GameConstants.checkpointMaxXP,
                normalizedX: pos.x,
                normalizedY: pos.y
            )
        }

        gameState.phase = .playing
        objectWillChange.send()
        session.broadcast(.fullState(gameState), reliable: true)
        startGameplayInfrastructure()
        statusMessage = "Gameplay bypass active — testing in solo mode"
    }

    func placeCheckpoint(normalizedX: Double, normalizedY: Double) {
        guard let me = gameState.players.first(where: { $0.id == localPlayerId }) else { return }
        guard gameState.phase == .placingCheckpoints else { return }
        guard me.hasPlacedCheckpoint == false else { return }
        guard GameStateEngine.normalizedCheckpointIsValid(team: me.team, x: normalizedX, y: normalizedY, splitAxis: gameState.teamSplitAxis) else {
            statusMessage = gameState.teamSplitAxis == .leftRight
                ? "Stay on your side of the field (Red: left, Blue: right)."
                : "Stay on your side of the field (Red: top, Blue: bottom)."
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
        session.deliverToEveryone(.checkpointPlaced(playerId: localPlayerId, checkpoint: checkpoint), hostPlayerId: gameState.hostPlayerId)

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
        ensureSoloTestBotCheckpointPlacedIfNeeded()
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

    /// Places a default checkpoint for the local solo-test dummy so one device can finish the placing phase.
    private func ensureSoloTestBotCheckpointPlacedIfNeeded() {
        guard let idx = gameState.players.firstIndex(where: { $0.id == GameConstants.soloTestBotPlayerId }) else { return }
        guard gameState.players[idx].hasPlacedCheckpoint == false else { return }

        let team = gameState.players[idx].team
        let pos = GameStateEngine.defaultCheckpointPosition(team: team, splitAxis: gameState.teamSplitAxis)

        let checkpoint = CheckpointState(
            id: UUID(),
            ownerPlayerId: GameConstants.soloTestBotPlayerId,
            team: team,
            xp: GameConstants.checkpointMaxXP,
            normalizedX: pos.x,
            normalizedY: pos.y
        )
        gameState.players[idx].hasPlacedCheckpoint = true
        mergeCheckpoint(checkpoint)
        session.deliverToEveryone(.checkpointPlaced(playerId: GameConstants.soloTestBotPlayerId, checkpoint: checkpoint), hostPlayerId: gameState.hostPlayerId)
        if gameState.phase == .placingCheckpoints {
            session.broadcast(.fullState(gameState), reliable: true)
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
        let previousState = gameState
        gameState = newValue
        updateUnderFireIndicator(previous: previousState, current: newValue)
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
        shootingIndicatorUntil = Date().addingTimeInterval(1.2)
        guard let event = buildShootEventIfPossible() else {
            statusMessage = "No target in range"
            return
        }

        if session.isHost {
            let previousState = gameState
            GameStateEngine.applyShoot(&gameState, event: event)
            updateUnderFireIndicator(previous: previousState, current: gameState)
            objectWillChange.send()
            session.broadcast(.fullState(gameState), reliable: true)
            if gameState.phase == .ended, let winner = gameState.winningTeam {
                session.broadcast(.gameOver(winningTeam: winner, state: gameState), reliable: true)
                motion.stop()
                proximity.stop()
                gameplayInfrastructureStarted = false
            }
        } else {
            session.sendToHost(.shootEvent(event), hostPlayerId: gameState.hostPlayerId)
        }
    }

    private func updateUnderFireIndicator(previous: GameState, current: GameState) {
        let previousHealth = previous.players.first(where: { $0.id == localPlayerId })?.health ?? GameConstants.playerMaxHealth
        let currentHealth = current.players.first(where: { $0.id == localPlayerId })?.health ?? GameConstants.playerMaxHealth

        let previousCheckpointXP = previous.checkpoints
            .filter { $0.ownerPlayerId == localPlayerId }
            .reduce(0) { $0 + $1.xp }
        let currentCheckpointXP = current.checkpoints
            .filter { $0.ownerPlayerId == localPlayerId }
            .reduce(0) { $0 + $1.xp }

        if currentHealth < previousHealth || currentCheckpointXP < previousCheckpointXP {
            underFireIndicatorUntil = Date().addingTimeInterval(2.5)
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
        session.deliverToEveryone(.hello(playerId: localPlayerId, displayName: displayName), reliable: true, hostPlayerId: gameState.hostPlayerId)
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
                self.session.sendToHost(.requestFullState, hostPlayerId: self.gameState.hostPlayerId)
                self.statusMessage = "Waiting for host approval…"
            }
        }
    }

    nonisolated func sessionManager(_ manager: GameSessionManager, didDisconnect _: MCPeerID) {}

    private func handleWireMessage(_ message: WireMessage, peer: MCPeerID) {
        switch message {
        case let .hello(playerId, name):
            session.registerPeer(peer, playerId: playerId)
            if session.isHost {
                if pendingJoinRequests.contains(where: { $0.playerId == playerId }) == false,
                   gameState.players.contains(where: { $0.id == playerId }) == false {
                    pendingJoinRequests.append(JoinRequest(playerId: playerId, displayName: name))
                    statusMessage = "Join request from \(name)"
                }
                objectWillChange.send()
            } else {
                statusMessage = "Waiting for host approval…"
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
            if state.phase == .selectingField {
                statusMessage = session.isHost ? "Choose the play area on the map" : "Waiting for host to set the field…"
            } else {
                statusMessage = "Place your checkpoint"
            }

        case let .fieldBoundsConfirmed(state):
            if session.isHost == false {
                replaceState(state)
            }
            statusMessage = "Place your checkpoint"

        case let .checkpointPlaced(pid, checkpoint):
            if pid == localPlayerId { return }
            // Prefer wire `pid`; fall back to checkpoint.ownerPlayerId if roster lookup ever diverges.
            if let idx = gameState.players.firstIndex(where: { $0.id == pid }) {
                gameState.players[idx].hasPlacedCheckpoint = true
            } else if let idx = gameState.players.firstIndex(where: { $0.id == checkpoint.ownerPlayerId }) {
                gameState.players[idx].hasPlacedCheckpoint = true
            }
            mergeCheckpoint(checkpoint)
            if session.isHost {
                session.broadcast(.checkpointPlaced(playerId: pid, checkpoint: checkpoint), reliable: true)
                tryAdvancePlacingHost()
                // Authoritative snapshot so clients that missed a packet still get flags + checkpoints in sync.
                if gameState.phase == .placingCheckpoints {
                    session.broadcast(.fullState(gameState), reliable: true)
                }
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
