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
    @Published private(set) var localLevelHoldDuration: TimeInterval = 0
    @Published private(set) var localLevelAngleDegrees: Double = 0
    @Published private(set) var isHealingActive: Bool = false
    /// Transient UI: damage the local player just took (checkpoint or HP).
    @Published private(set) var incomingDamagePop: Int?
    /// Transient UI: damage the local player just dealt.
    @Published private(set) var outgoingDamagePop: Int?

    let localPlayerId: UUID

    /// What the local player would hit if they shoot right now (same rules as `buildShootEventIfPossible()`).
    enum AimTarget: Equatable {
        case enemy(PlayerState)
        case enemyCheckpoint(CheckpointState)
    }

    /// What the local player can currently heal by holding the phone level.
    enum HealTarget: Equatable {
        case teammate(PlayerState, progress: Double)
    }

    var currentAimTarget: AimTarget? {
        guard let event = buildShootEventIfPossible() else { return nil }
        if let pid = event.damagedPlayerId, let p = gameState.players.first(where: { $0.id == pid }) {
            return .enemy(p)
        }
        if let cid = event.damagedCheckpointId, let c = gameState.checkpoints.first(where: { $0.id == cid }) {
            return .enemyCheckpoint(c)
        }
        return nil
    }

    var currentHealTarget: HealTarget? {
        guard let target = healableTeammateInRange else { return nil }
        let progress = min(max(localLevelHoldDuration / GameConstants.healChannelDuration, 0), 1)
        return .teammate(target, progress: progress)
    }

    var currentHUDTarget: CurrentHUDTarget? {
        if let heal = currentHealTarget {
            switch heal {
            case let .teammate(player, progress):
                return .ally(player, progress: progress)
            }
        }

        if let aim = currentAimTarget {
            switch aim {
            case let .enemy(player):
                return .enemy(player)
            case let .enemyCheckpoint(checkpoint):
                return .enemyCheckpoint(checkpoint)
            }
        }
        return nil
    }

    enum CurrentHUDTarget: Equatable {
        case ally(PlayerState, progress: Double)
        case enemy(PlayerState)
        case enemyCheckpoint(CheckpointState)
    }

    private let session: GameSessionManager
    private let motion = MotionManager()
    private let proximity = ProximityManager()
    private var healChannelProgressByPair: [HealChannelKey: TimeInterval] = [:]
    private var lastHealingTargetId: UUID?

    private var tickCancellable: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private var gameplayInfrastructureStarted = false

    private struct HealChannelKey: Hashable {
        let healerId: UUID
        let healedPlayerId: UUID
    }

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

    func toggleHealingMode() {
        guard gameState.phase == .playing else { return }
        guard healableTeammateInRange != nil else {
            isHealingActive = false
            return
        }
        isHealingActive.toggle()
        if isHealingActive == false {
            localLevelHoldDuration = 0
        }
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
        guard code.count == 3 else { return false }
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
        localLevelHoldDuration = 0
        localLevelAngleDegrees = 0
        isHealingActive = false
        incomingDamagePop = nil
        outgoingDamagePop = nil
        lastHealingTargetId = nil
        healChannelProgressByPair.removeAll()
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
        if gameState.players.contains(where: { $0.id == GameConstants.soloTestBotPlayerId }) {
            forceLocalPlayerOntoTeamA()
        }
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

    private func triggerOutgoingShotHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
    }

    private func triggerIncomingDamageHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }

    private func flashIncomingDamage(_ amount: Int) {
        incomingDamagePop = amount
        triggerIncomingDamageHaptic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.incomingDamagePop = nil
        }
    }

    private func flashOutgoingDamage(_ amount: Int) {
        outgoingDamagePop = amount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            self?.outgoingDamagePop = nil
        }
    }

    private func forceLocalPlayerOntoTeamA() {
        guard let localIdx = gameState.players.firstIndex(where: { $0.id == localPlayerId }) else { return }
        if gameState.players[localIdx].team == .a { return }
        if let swapIdx = gameState.players.firstIndex(where: { $0.team == .a }) {
            gameState.players[swapIdx].team = .b
        }
        gameState.players[localIdx].team = .a
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

        if gameState.phase == .playing {
            if session.isHost {
                applyPassiveRegeneration()
            }
            updateHealingHeartbeat()
        }

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
            lastHealingTargetId = nil
            healChannelProgressByPair.removeAll()
            localLevelHoldDuration = 0
            localLevelAngleDegrees = 0
            isHealingActive = false
        case .ended:
            motion.stop()
            proximity.stop()
            gameplayInfrastructureStarted = false
            lastHealingTargetId = nil
            healChannelProgressByPair.removeAll()
            localLevelHoldDuration = 0
            localLevelAngleDegrees = 0
            isHealingActive = false
        default:
            break
        }
    }

    // MARK: - Proximity helpers

    private func isPlayerInRange(_ playerId: UUID, threshold: Int) -> Bool {
        if playerId == GameConstants.soloTestBotPlayerId { return true }
        if let rssi = proximity.lastRSSIByPlayerId[playerId], rssi >= threshold {
            return true
        }
        if GameConstants.proximityFallbackToAllConnectedPeers {
            return session.peerID(forPlayerId: playerId) != nil
        }
        return false
    }

    private func isEnemyPlayerInShootRange(_ enemyId: UUID) -> Bool {
        isPlayerInRange(enemyId, threshold: GameConstants.playerConflictRSSIThreshold)
    }

    private func isEnemyCheckpointInRange(ownerId: UUID) -> Bool {
        isPlayerInRange(ownerId, threshold: GameConstants.checkpointRangeRSSIThreshold)
    }

    private func isTeammateInHealRange(_ playerId: UUID) -> Bool {
        isPlayerInRange(playerId, threshold: GameConstants.playerConflictRSSIThreshold)
    }

    private var healableTeammateInRange: PlayerState? {
        guard gameState.phase == .playing else { return nil }
        guard let selfPlayer = gameState.players.first(where: { $0.id == localPlayerId }) else { return nil }
        guard selfPlayer.isDead == false else { return nil }
        let candidates = gameState.players.filter {
            $0.id != localPlayerId
                && $0.team == selfPlayer.team
                && $0.isDead == false
                && $0.health < GameConstants.playerMaxHealth
                && isTeammateInHealRange($0.id)
        }
        return candidates.min(by: { $0.health < $1.health })
    }

    private func updateHealingHeartbeat() {
        let targetId = healableTeammateInRange?.id
        let isLeveling = isHealingActive && localLevelHoldDuration > 0

        if session.isHost {
            if let targetId, isLeveling {
                if let last = lastHealingTargetId, last != targetId {
                    _ = applyHealingHeartbeat(healerId: localPlayerId, healedPlayerId: last, isLeveling: false)
                }
                if applyHealingHeartbeat(healerId: localPlayerId, healedPlayerId: targetId, isLeveling: true) {
                    objectWillChange.send()
                    session.broadcast(.fullState(gameState), reliable: true)
                }
                lastHealingTargetId = targetId
            } else if let last = lastHealingTargetId {
                if applyHealingHeartbeat(healerId: localPlayerId, healedPlayerId: last, isLeveling: false) {
                    objectWillChange.send()
                    session.broadcast(.fullState(gameState), reliable: true)
                }
                lastHealingTargetId = nil
                isHealingActive = false
            }
        } else {
            if let targetId, isLeveling {
                if let last = lastHealingTargetId, last != targetId {
                    session.sendToHost(.healEvent(healerId: localPlayerId, healedPlayerId: last, isLeveling: false), hostPlayerId: gameState.hostPlayerId)
                }
                session.sendToHost(.healEvent(healerId: localPlayerId, healedPlayerId: targetId, isLeveling: true), hostPlayerId: gameState.hostPlayerId)
                lastHealingTargetId = targetId
            } else if let last = lastHealingTargetId {
                session.sendToHost(.healEvent(healerId: localPlayerId, healedPlayerId: last, isLeveling: false), hostPlayerId: gameState.hostPlayerId)
                lastHealingTargetId = nil
                isHealingActive = false
            }
        }

        if targetId == nil {
            isHealingActive = false
        }
    }

    private func applyPassiveRegeneration() {
        guard gameState.phase == .playing else { return }
        var changed = false
        for i in gameState.players.indices {
            guard gameState.players[i].isDead == false else { continue }
            guard gameState.players[i].health < GameConstants.playerMaxHealth else { continue }
            let before = gameState.players[i].health
            gameState.players[i].health = min(GameConstants.playerMaxHealth, before + GameConstants.passiveRegenPerSecond)
            changed = changed || gameState.players[i].health != before
        }
        if changed {
            objectWillChange.send()
            session.broadcast(.fullState(gameState), reliable: true)
        }
    }

    private func applyHealingHeartbeat(healerId: UUID, healedPlayerId: UUID, isLeveling: Bool) -> Bool {
        guard let healerIdx = gameState.players.firstIndex(where: { $0.id == healerId }) else { return false }
        guard let targetIdx = gameState.players.firstIndex(where: { $0.id == healedPlayerId }) else { return false }
        guard gameState.phase == .playing else { return false }
        guard gameState.players[healerIdx].isDead == false else { return false }
        guard gameState.players[healerIdx].team == gameState.players[targetIdx].team else { return false }
        guard gameState.players[targetIdx].isDead == false else { return false }

        let key = HealChannelKey(healerId: healerId, healedPlayerId: healedPlayerId)
        if isLeveling {
            let current = healChannelProgressByPair[key] ?? 0
            let updated = min(current + 1, GameConstants.healChannelDuration)
            healChannelProgressByPair[key] = updated

            if updated >= GameConstants.healChannelDuration {
                let before = gameState.players[targetIdx].health
                gameState.players[targetIdx].health = GameConstants.playerMaxHealth
                healChannelProgressByPair.removeValue(forKey: key)
                return gameState.players[targetIdx].health != before
            }
        } else {
            healChannelProgressByPair.removeValue(forKey: key)
        }
        return false
    }

    func buildShootEventIfPossible() -> ShootEvent? {
        guard gameState.phase == .playing else { return nil }
        guard let selfPlayer = gameState.players.first(where: { $0.id == localPlayerId }) else { return nil }
        guard selfPlayer.isDead == false else { return nil }

        let enemyCPs = gameState.checkpoints.filter { $0.team != selfPlayer.team && $0.xp > 0 }
        for cp in enemyCPs {
            guard let owner = gameState.players.first(where: { $0.id == cp.ownerPlayerId }) else { continue }
            if isEnemyCheckpointInRange(ownerId: owner.id) {
                return ShootEvent(
                    shooterId: localPlayerId,
                    damagedPlayerId: nil,
                    damagedCheckpointId: cp.id,
                    playerDamage: 0,
                    checkpointDamage: GameConstants.checkpointShotDamage
                )
            }
        }

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

        return nil
    }

    private func handleShootDetected() {
        shootingIndicatorUntil = Date().addingTimeInterval(1.2)
        guard let event = buildShootEventIfPossible() else {
            statusMessage = "No target in range"
            return
        }

        let dealt = max(event.playerDamage, event.checkpointDamage)
        flashOutgoingDamage(dealt)
        triggerOutgoingShotHaptic()

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

        if currentHealth < previousHealth {
            underFireIndicatorUntil = Date().addingTimeInterval(2.5)
            flashIncomingDamage(previousHealth - currentHealth)
        }
        if currentCheckpointXP < previousCheckpointXP {
            underFireIndicatorUntil = Date().addingTimeInterval(2.5)
            flashIncomingDamage(previousCheckpointXP - currentCheckpointXP)
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

        case let .healEvent(healerId, healedPlayerId, isLeveling):
            guard session.isHost else { return }
            if applyHealingHeartbeat(healerId: healerId, healedPlayerId: healedPlayerId, isLeveling: isLeveling) {
                objectWillChange.send()
                session.broadcast(.fullState(gameState), reliable: true)
            }

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

    nonisolated func motionManager(_ manager: MotionManager, didUpdateLeveling isLeveling: Bool, heldDuration: TimeInterval, levelAngleDegrees: Double) {
        Task { @MainActor in
            self.localLevelHoldDuration = isLeveling ? heldDuration : 0
            self.localLevelAngleDegrees = levelAngleDegrees
        }
    }
}
