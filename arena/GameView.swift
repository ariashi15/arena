//
//  GameView.swift
//  arena
//

import MapKit
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var game: GameViewModel
    @StateObject private var location = LocationManager()
    @State private var placementCamera: MapCameraPosition = .automatic
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
            .onAppear {
                location.requestAuthorizationIfNeeded()
                location.startUpdates()
                placementCamera = .region(game.gameState.fieldBounds.coordinateRegion)
            }
            .onDisappear {
                location.stopUpdates()
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

                Map(position: $placementCamera) {
                    MapPolygon(coordinates: game.gameState.fieldBounds.teamAPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                        .foregroundStyle(Color.cyan.opacity(0.24))
                    MapPolygon(coordinates: game.gameState.fieldBounds.teamBPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                        .foregroundStyle(Color.pink.opacity(0.2))
                    if let c = location.lastLocation?.coordinate {
                        Marker("You", coordinate: c)
                            .tint(.blue)
                    }
                    if let checkpointCoordinate {
                        Marker("Your checkpoint", coordinate: checkpointCoordinate)
                            .tint(.green)
                    }
                }
                .frame(height: 260)
                .mapStyle(.standard(elevation: .flat))
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                }

                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                    Text("Location access is required to place your checkpoint at your real position.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Place checkpoint at my current location") {
                    guard let currentCoordinate = location.lastLocation?.coordinate else {
                        game.statusMessage = "Waiting for your GPS location..."
                        return
                    }
                    guard let point = game.gameState.fieldBounds.normalizedPoint(for: currentCoordinate) else {
                        game.statusMessage = "You are outside the selected field. Move inside the play area to place your checkpoint."
                        return
                    }
                    game.placeCheckpoint(normalizedX: point.x, normalizedY: point.y)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    game.gameState.players.first(where: { $0.id == game.localPlayerId })?.hasPlacedCheckpoint == true
                        || location.lastLocation == nil
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
            return "Move around physically, then place your checkpoint at your real location. Team A must be on the west/left half and Team B on east/right."
        }
        return "Move around physically, then place your checkpoint at your real location. Team A must be on the top/north half and Team B on bottom/south."
    }

    private var checkpointCoordinate: CLLocationCoordinate2D? {
        guard let checkpoint = game.gameState.checkpoints.first(where: { $0.ownerPlayerId == game.localPlayerId }) else {
            return nil
        }
        return game.gameState.fieldBounds.coordinate(normalizedX: checkpoint.normalizedX, normalizedY: checkpoint.normalizedY)
    }
}

#Preview {
    GameView()
        .environmentObject(GameViewModel())
}
