//
//  GameView.swift
//  arena
//

import SwiftUI

struct GameView: View {
    @EnvironmentObject private var game: GameViewModel

    @State private var placeX: Double = 0.25
    @State private var placeY: Double = 0.5
    @State private var showingExitConfirmation = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exit game", role: .destructive) {
                        showingExitConfirmation = true
                    }
                }
            }
            .alert("Exit current game?", isPresented: $showingExitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Exit", role: .destructive) {
                    game.returnToLobby()
                }
            } message: {
                Text("You will leave this match and return to the lobby.")
            }
            .onChange(of: game.gameState.phase) { _, new in
                if new == .placingCheckpoints {
                    syncPlacementFromField()
                }
            }
            .onAppear {
                if game.gameState.phase == .placingCheckpoints {
                    syncPlacementFromField()
                }
            }
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
                GroupBox("Who has locked in") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(game.gameState.players) { p in
                            HStack(spacing: 8) {
                                Image(systemName: p.hasPlacedCheckpoint ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(p.hasPlacedCheckpoint ? Color.green : Color.secondary)
                                Text(p.displayName)
                                Spacer()
                                Text(p.hasPlacedCheckpoint ? "Placed" : "Not yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text(splitInstruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("X")
                    Slider(value: $placeX, in: placementXRange)
                    Text(String(format: "%.2f", placeX))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Y")
                    Slider(value: $placeY, in: placementYRange)
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

    private var splitInstruction: String {
        if game.gameState.teamSplitAxis == .leftRight {
            return "Stay on your team’s half (A: west/left, B: east/right). X and Y are positions inside the host’s field (0-1)."
        }
        return "Stay on your team’s half (A: top/north, B: bottom/south). X and Y are positions inside the host’s field (0-1)."
    }

    /// Field-local placement: west→east is X, south→north is Y.
    private var placementYRange: ClosedRange<Double> {
        guard let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) else {
            return 0...1
        }
        let e = 1e-5
        if game.gameState.teamSplitAxis == .topBottom {
            if me.team == .a {
                return (0.5 + e)...1
            }
            return 0...(0.5 - e)
        }
        return 0...1
    }

    private var placementXRange: ClosedRange<Double> {
        guard let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) else {
            return 0...1
        }
        let e = 1e-5
        if game.gameState.teamSplitAxis == .leftRight {
            if me.team == .a {
                return 0...(0.5 - e)
            }
            return (0.5 + e)...1
        }
        return 0...1
    }

    private func syncPlacementFromField() {
        guard let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) else { return }
        let p = GameStateEngine.defaultCheckpointPosition(team: me.team, splitAxis: game.gameState.teamSplitAxis)
        placeX = p.x.clamped(to: placementXRange)
        placeY = p.y.clamped(to: placementYRange)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    GameView()
        .environmentObject(GameViewModel())
}
