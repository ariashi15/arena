//
//  GameConstants.swift
//  arena
//

import Foundation

enum GameConstants {
    /// Multipeer service identifier (≤15 chars, lowercase letters, numbers, hyphen).
    static let multipeerServiceType = "arena-mp"

    /// BLE service used for proximity beacons.
    static let proximityServiceUUIDString = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

    /// Maximum players supported by the rules (2–24).
    static let maxPlayers = 24
    static let minPlayersToStart = 2

    /// Local-only roster entry for single-device testing (not a Multipeer peer).
    static let soloTestBotPlayerId = UUID(uuidString: "A0A0A0A0-B0B0-4000-8000-000000000001")!

    /// Starting health for each player.
    static let playerMaxHealth = 100

    /// Starting XP for each checkpoint.
    static let checkpointMaxXP = 100

    /// Damage applied per successful shot to a player.
    static let playerShotDamage = 10

    /// Damage applied per successful shot to a checkpoint.
    static let checkpointShotDamage = 15

    /// Seconds before respawn after death.
    static let respawnDuration: TimeInterval = 60

    /// Debounce between motion-detected shots (one jump ≈ one shot).
    static let shotMotionDebounce: TimeInterval = 0.65

    /// RSSI threshold: values greater than or equal are considered within shoot range
    /// (RSSI is negative; closer devices have higher / less negative readings).
    /// Tune per field test; -72 is a rough “few meters” starting point.
    static let shootRSSIThreshold: Int = -72

    /// If BLE is unavailable or unauthorized, fall back to treating all connected Multipeer peers as in range (debug / demo).
    static let proximityFallbackToAllConnectedPeers = true
}
