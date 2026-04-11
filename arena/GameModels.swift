//
//  GameModels.swift
//  arena
//

import Foundation
import CoreGraphics

enum Team: String, Codable, CaseIterable, Sendable {
    case a
    case b

    var displayName: String {
        switch self {
        case .a: return "Team A"
        case .b: return "Team B"
        }
    }

    var opposite: Team {
        self == .a ? .b : .a
    }
}

enum GamePhase: String, Codable, Sendable {
    case lobby
    case placingCheckpoints
    case playing
    case ended
}

struct PlayerState: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var team: Team
    var health: Int
    var isDead: Bool
    /// When `isDead`, respawn becomes available after this instant.
    var respawnAt: Date?
    var hasPlacedCheckpoint: Bool
}

struct CheckpointState: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var ownerPlayerId: UUID
    var team: Team
    var xp: Int
    /// Normalized field coordinates (0...1). Team A uses x in [0, 0.5), Team B uses [0.5, 1].
    var normalizedX: Double
    var normalizedY: Double
}

struct GameState: Codable, Equatable, Sendable {
    var phase: GamePhase
    var players: [PlayerState]
    var checkpoints: [CheckpointState]
    var winningTeam: Team?
    /// Stable id for the session host’s player (authoritative for lobby transitions).
    var hostPlayerId: UUID
}

// MARK: - Networking payloads

enum WireMessage: Codable, Sendable {
    case hello(playerId: UUID, displayName: String)
    case requestFullState
    case fullState(GameState)

    case hostStartedPlacing(GameState)
    case checkpointPlaced(playerId: UUID, checkpoint: CheckpointState)
    case allCheckpointsReady(GameState)

    case shootEvent(ShootEvent)

    case gameOver(winningTeam: Team, state: GameState)
}

struct ShootEvent: Codable, Equatable, Sendable {
    var shooterId: UUID
    var damagedPlayerId: UUID?
    var damagedCheckpointId: UUID?
    var playerDamage: Int
    var checkpointDamage: Int
}
