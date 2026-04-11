//
//  GameStateEngine.swift
//  arena
//

import Foundation

enum GameStateEngine {
    static func makeLobby(hostPlayerId: UUID, displayName: String) -> GameState {
        let host = PlayerState(
            id: hostPlayerId,
            displayName: displayName,
            team: .a,
            health: GameConstants.playerMaxHealth,
            isDead: false,
            respawnAt: nil,
            hasPlacedCheckpoint: false
        )
        return GameState(
            phase: .lobby,
            players: [host],
            checkpoints: [],
            winningTeam: nil,
            hostPlayerId: hostPlayerId,
            fieldBounds: .fallback,
            teamSplitAxis: .leftRight
        )
    }

    static func assignTeamsRandomly(_ state: inout GameState) {
        guard state.players.count >= GameConstants.minPlayersToStart else { return }
        var players = state.players.shuffled()
        let firstTeamCount = (players.count + 1) / 2
        for i in players.indices {
            players[i].team = i < firstTeamCount ? .a : .b
            players[i].health = GameConstants.playerMaxHealth
            players[i].isDead = false
            players[i].respawnAt = nil
            players[i].hasPlacedCheckpoint = false
            players[i].kills = 0
            players[i].damageDone = 0
            players[i].deaths = 0
        }
        state.players = players
        state.checkpoints.removeAll()
        state.winningTeam = nil
        state.fieldBounds = .defaultPlayArea
        state.teamSplitAxis = .leftRight
        state.phase = .selectingField
    }

    static func applyShoot(_ state: inout GameState, event: ShootEvent) {
        guard state.phase == .playing else { return }

        let shooterIdx = state.players.firstIndex(where: { $0.id == event.shooterId })

        if let pid = event.damagedPlayerId,
           let i = state.players.firstIndex(where: { $0.id == pid }) {
            if state.players[i].isDead { return }
            let dealt = min(event.playerDamage, state.players[i].health)
            state.players[i].health -= event.playerDamage
            if let si = shooterIdx { state.players[si].damageDone += dealt }
            if state.players[i].health <= 0 {
                state.players[i].health = 0
                state.players[i].isDead = true
                state.players[i].deaths += 1
                state.players[i].respawnAt = Date().addingTimeInterval(GameConstants.respawnDuration)
                if let si = shooterIdx { state.players[si].kills += 1 }
            }
        }

        if let cid = event.damagedCheckpointId,
           let i = state.checkpoints.firstIndex(where: { $0.id == cid }) {
            let dealt = min(event.checkpointDamage, state.checkpoints[i].xp)
            state.checkpoints[i].xp -= event.checkpointDamage
            if state.checkpoints[i].xp < 0 {
                state.checkpoints[i].xp = 0
            }
            if let si = shooterIdx { state.players[si].damageDone += max(0, dealt) }
        }

        if let winner = winnerIfAny(state) {
            state.phase = .ended
            state.winningTeam = winner
        }
    }

    static func tickRespawns(_ state: inout GameState, now: Date) {
        for i in state.players.indices {
            guard state.players[i].isDead, let until = state.players[i].respawnAt, now >= until else { continue }
            state.players[i].isDead = false
            state.players[i].health = GameConstants.playerMaxHealth
            state.players[i].respawnAt = nil
        }
    }

    /// Returns winning team when all enemy checkpoints have 0 XP.
    static func winnerIfAny(_ state: GameState) -> Team? {
        let teamAXp = state.checkpoints.filter { $0.team == .a }.reduce(0) { $0 + max(0, $1.xp) }
        let teamBXp = state.checkpoints.filter { $0.team == .b }.reduce(0) { $0 + max(0, $1.xp) }

        if teamAXp <= 0, teamBXp > 0 { return .b }
        if teamBXp <= 0, teamAXp > 0 { return .a }
        if teamAXp <= 0, teamBXp <= 0 { return nil }
        return nil
    }

    static func allCheckpointsPlaced(_ state: GameState) -> Bool {
        guard state.players.isEmpty == false else { return false }
        return state.players.allSatisfy(\.hasPlacedCheckpoint)
    }

    /// `x` and `y` are field-local 0…1 (west→east, south→north).
    static func normalizedCheckpointIsValid(team: Team, x: Double, y: Double, splitAxis: TeamSplitAxis) -> Bool {
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return false }
        switch splitAxis {
        case .leftRight:
            switch team {
            case .a: return x < 0.5
            case .b: return x >= 0.5
            }
        case .topBottom:
            switch team {
            case .a: return y >= 0.5
            case .b: return y < 0.5
            }
        }
    }

    /// Default checkpoint in field-local space (center of each team’s half).
    static func defaultCheckpointPosition(team: Team, splitAxis: TeamSplitAxis) -> (x: Double, y: Double) {
        switch splitAxis {
        case .leftRight:
            let x = team == .a ? 0.25 : 0.75
            return (x, 0.5)
        case .topBottom:
            let y = team == .a ? 0.75 : 0.25
            return (0.5, y)
        }
    }
}
