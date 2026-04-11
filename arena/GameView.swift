//
//  GameView.swift
//  arena
//

import SwiftUI

struct GameView: View {
    @EnvironmentObject private var game: GameViewModel

    @State private var placeX: Double = 0.25
    @State private var placeY: Double = 0.5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if game.gameState.phase == .placingCheckpoints {
                        placingCard
                    }
                    if game.gameState.phase == .playing {
                        playingCard
                    }
                }
                .padding()
            }
            .navigationTitle("Arena")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) {
                Text("Team: \(me.team.displayName)")
                    .font(.title2.weight(.semibold))
                Text("Phase: \(String(describing: game.gameState.phase))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !game.statusMessage.isEmpty {
                Text(game.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placingCard: some View {
        GroupBox("Place your checkpoint") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Team A uses the left half of the field, Team B the right. Drag to pick a spot (normalized 0–1).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("X")
                    Slider(value: $placeX, in: 0...1)
                    Text(String(format: "%.2f", placeX))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Y")
                    Slider(value: $placeY, in: 0...1)
                    Text(String(format: "%.2f", placeY))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Button("Confirm checkpoint") {
                    game.placeCheckpoint(normalizedX: placeX, normalizedY: placeY)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    game.gameState.players.first(where: { $0.id == game.localPlayerId })?.hasPlacedCheckpoint == true
                )
            }
        }
    }

    private var playingCard: some View {
        GroupBox("Match") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Jump to shoot enemies in Bluetooth range (or connected in demo fallback).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(game.gameState.players) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.displayName)
                            Text("\(p.team.displayName) · HP \(p.health)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.isDead {
                            Text("Dead")
                                .foregroundStyle(.red)
                        } else {
                            Text("Alive")
                                .foregroundStyle(.green)
                        }
                    }
                }

                Divider()

                Text("Checkpoints")
                    .font(.headline)
                if game.gameState.checkpoints.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(game.gameState.checkpoints) { c in
                        HStack {
                            Text(shortUUID(c.id))
                            Spacer()
                            Text("\(c.team.displayName) · \(c.xp) XP")
                        }
                        .font(.caption)
                    }
                }

                Divider()

                Text(game.proximitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortUUID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

#Preview {
    GameView()
        .environmentObject(GameViewModel())
}
