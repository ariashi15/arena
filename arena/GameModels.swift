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
        case .a: return "Red"
        case .b: return "Blue"
        }
    }

    var opposite: Team {
        self == .a ? .b : .a
    }
}

enum TeamSplitAxis: String, Codable, CaseIterable, Sendable {
    case leftRight
    case topBottom

    var displayName: String {
        switch self {
        case .leftRight: return "Left / Right"
        case .topBottom: return "Top / Bottom"
        }
    }
}

enum GamePhase: String, Codable, Sendable {
    case lobby
    /// Host is choosing the play area on the venue map; other players wait.
    case selectingField
    case placingCheckpoints
    case playing
    case ended
}

/// Geographic rectangle for the play area (WGS84). Checkpoint coordinates are **field-local** 0…1:
/// west→east = X, south→north = Y. Team split orientation is stored separately in `GameState.teamSplitAxis`.
struct FieldBounds: Codable, Equatable, Sendable {
    var minLatitude: Double
    var minLongitude: Double
    var maxLatitude: Double
    var maxLongitude: Double

    /// Placeholder before the host picks a real area (Evanston-sized example).
    static let fallback = FieldBounds(
        minLatitude: 42.056,
        minLongitude: -87.680,
        maxLatitude: 42.062,
        maxLongitude: -87.668
    )

    /// Initial suggestion when a match moves to field selection (~one city block).
    static let defaultPlayArea = FieldBounds(
        minLatitude: 42.057,
        minLongitude: -87.676,
        maxLatitude: 42.060,
        maxLongitude: -87.671
    )

    /// Ensures a usable play area (minimum span, ordered min/max).
    func clampedValid(minLatDegrees: Double = 0.00008, minLonDegrees: Double = 0.00008) -> FieldBounds {
        var minLat = min(minLatitude, maxLatitude)
        var maxLat = max(minLatitude, maxLatitude)
        var minLon = min(minLongitude, maxLongitude)
        var maxLon = max(minLongitude, maxLongitude)
        if maxLat - minLat < minLatDegrees {
            let m = (minLat + maxLat) / 2
            minLat = m - minLatDegrees / 2
            maxLat = m + minLatDegrees / 2
        }
        if maxLon - minLon < minLonDegrees {
            let m = (minLon + maxLon) / 2
            minLon = m - minLonDegrees / 2
            maxLon = m + minLonDegrees / 2
        }
        return FieldBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
    }
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
    /// Field-local coordinates (0…1): X west→east, Y south→north within the host’s geographic `fieldBounds`; team half rules apply.
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
    /// Geographic play area chosen by the host; checkpoint X/Y are field-local fractions inside this box.
    var fieldBounds: FieldBounds
    /// How teams are split within the selected field.
    var teamSplitAxis: TeamSplitAxis
}

// MARK: - Networking payloads

enum WireMessage: Codable, Sendable {
    case hello(playerId: UUID, displayName: String)
    case requestFullState
    case fullState(GameState)

    case hostStartedPlacing(GameState)
    case fieldBoundsConfirmed(GameState)
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
