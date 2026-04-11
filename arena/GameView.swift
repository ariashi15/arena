//
//  GameView.swift
//  arena
//

import CoreLocation
import MapKit
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var game: GameViewModel
    @StateObject private var location = LocationManager()
    @State private var placementCamera: MapCameraPosition = .automatic
    @State private var gameplayCamera: MapCameraPosition = .automatic
    @State private var showingExitConfirmation = false
    @State private var lastFollowedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlayingTab: PlayingTab = .overview

    var body: some View {
        NavigationStack {
            ZStack {
                playfulBackground

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
                gameplayCamera = .region(game.gameState.fieldBounds.coordinateRegion)
                updateGameplayCameraIfNeeded(force: true)
            }
            .onChange(of: game.gameState.phase) { _, phase in
                if phase == .playing {
                    updateGameplayCameraIfNeeded(force: true)
                }
                if phase == .placingCheckpoints {
                    placementCamera = .region(game.gameState.fieldBounds.coordinateRegion)
                }
            }
            .onReceive(location.$lastLocation) { _ in
                updateGameplayCameraIfNeeded()
            }
            .onDisappear {
                location.stopUpdates()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) {
                HStack(spacing: 10) {
                    Text("\(me.team.displayName) Team")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(me.team == .a ? Color.red : Color.blue, in: Capsule())

                    Text(gamePhaseTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.2), in: Capsule())

                    Spacer()
                }
            }
            if !game.statusMessage.isEmpty {
                Text(game.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Place your checkpoint", systemImage: "scope")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Squad ready check")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                ForEach(game.gameState.players) { p in
                    HStack(spacing: 8) {
                        Image(systemName: p.hasPlacedCheckpoint ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.hasPlacedCheckpoint ? Color.green : Color.white.opacity(0.65))
                        Text(p.displayName)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(p.hasPlacedCheckpoint ? "Placed" : "Not yet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            Text(splitInstruction)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))

            Map(position: $placementCamera) {
                MapPolygon(coordinates: game.gameState.fieldBounds.teamAPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                    .foregroundStyle(Color.red.opacity(0.22))
                MapPolygon(coordinates: game.gameState.fieldBounds.teamBPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                    .foregroundStyle(Color.blue.opacity(0.2))
                if let c = location.lastLocation?.coordinate {
                    Marker("You", coordinate: c)
                        .tint(.yellow)
                }
                if let checkpointCoordinate {
                    Marker("Your checkpoint", coordinate: checkpointCoordinate)
                        .tint(.green)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }

            if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Text("Location access is required to place your checkpoint at your real position.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
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
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(.black)
            .disabled(
                game.gameState.players.first(where: { $0.id == game.localPlayerId })?.hasPlacedCheckpoint == true
                    || location.lastLocation == nil
            )
            .opacity(
                (game.gameState.players.first(where: { $0.id == game.localPlayerId })?.hasPlacedCheckpoint == true
                    || location.lastLocation == nil) ? 0.55 : 1
            )
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.31, blue: 0.28).opacity(0.78), Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 8)
    }

    private var playingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Match", systemImage: "gamecontroller.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text("Jump to shoot enemies in Bluetooth range (or connected in demo fallback).")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

            Picker("Gameplay tab", selection: $selectedPlayingTab) {
                ForEach(PlayingTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedPlayingTab == .overview {
                playerIndicatorsSection
                gameStatsSection
            } else {
                playingMap
            }

            Text(game.proximitySummary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.16, blue: 0.42).opacity(0.86), Color(red: 0.16, green: 0.56, blue: 0.43).opacity(0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 8)
    }

    private var playingMap: some View {
        Map(position: $gameplayCamera) {
            MapPolygon(coordinates: game.gameState.fieldBounds.mapPolygonCoordinates)
                .foregroundStyle(Color.gray.opacity(0.2))
            MapPolygon(coordinates: game.gameState.fieldBounds.teamAPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                .foregroundStyle(Color.red.opacity(0.16))
            MapPolygon(coordinates: game.gameState.fieldBounds.teamBPolygonCoordinates(splitAxis: game.gameState.teamSplitAxis))
                .foregroundStyle(Color.blue.opacity(0.14))

            if let coordinate = location.lastLocation?.coordinate {
                Annotation("", coordinate: coordinate, anchor: .bottom) {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .padding(6)
                        .background(.thickMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        )
                        .shadow(radius: 2)
                }
            }
        }
        .frame(minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
    }

    private var playerIndicatorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Player indicators")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            indicatorRow(title: "Map side", value: currentMapSideLabel, active: true)
            indicatorRow(
                title: "In range of enemy checkpoint",
                value: isInEnemyCheckpointRange ? "Yes" : "No",
                active: isInEnemyCheckpointRange
            )
            indicatorRow(
                title: "Shooting",
                value: game.isShooting ? "Yes" : "No",
                active: game.isShooting
            )
            indicatorRow(
                title: "Getting shot at",
                value: game.isGettingShotAt ? "Yes" : "No",
                active: game.isGettingShotAt
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var gameStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game stats")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text("Alive players")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                teamAliveRow(team: .a)
                teamAliveRow(team: .b)
            }

            Divider()
                .overlay(Color.white.opacity(0.25))

            VStack(alignment: .leading, spacing: 6) {
                Text("Checkpoint XP")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                checkpointXPRows(team: .a)
                checkpointXPRows(team: .b)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func indicatorRow(title: String, value: String, active: Bool) -> some View {
        HStack {
            Image(systemName: active ? "bolt.fill" : "circle")
                .foregroundStyle(active ? Color.yellow : Color.white.opacity(0.7))
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.9))
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(active ? Color.white.opacity(0.18) : Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .font(.subheadline)
    }

    private func teamAliveRow(team: Team) -> some View {
        let alive = game.gameState.players.filter { $0.team == team && $0.isDead == false }
        let names = alive.map(\.displayName).joined(separator: ", ")
        return HStack {
            Text("\(team.displayName):")
                .fontWeight(.semibold)
                .foregroundStyle(team == .a ? Color.red : Color.blue)
            Text(names.isEmpty ? "None" : names)
                .foregroundStyle(.white.opacity(0.88))
        }
        .font(.subheadline)
    }

    private func checkpointXPRows(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let checkpoints = game.gameState.checkpoints.filter { $0.team == team }
            HStack {
                Text(team.displayName)
                    .fontWeight(.semibold)
                    .foregroundStyle(team == .a ? Color.red : Color.blue)
                Spacer()
            }
            if checkpoints.isEmpty {
                Text("No checkpoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(checkpoints) { checkpoint in
                    let ownerName = game.gameState.players.first(where: { $0.id == checkpoint.ownerPlayerId })?.displayName ?? shortUUID(checkpoint.ownerPlayerId)
                    HStack {
                        Text(ownerName)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(checkpoint.xp) XP")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var currentMapSideLabel: String {
        guard let coordinate = location.lastLocation?.coordinate else { return "Unknown" }
        guard let point = game.gameState.fieldBounds.normalizedPoint(for: coordinate) else { return "Outside field" }

        switch game.gameState.teamSplitAxis {
        case .leftRight:
            return point.x < 0.5 ? Team.a.displayName : Team.b.displayName
        case .topBottom:
            return point.y >= 0.5 ? Team.a.displayName : Team.b.displayName
        }
    }

    private var isInEnemyCheckpointRange: Bool {
        guard let me = game.gameState.players.first(where: { $0.id == game.localPlayerId }) else { return false }
        guard let userLoc = location.lastLocation else { return false }

        return game.gameState.checkpoints.contains { checkpoint in
            guard checkpoint.team != me.team, checkpoint.xp > 0 else { return false }
            let coord = game.gameState.fieldBounds.coordinate(normalizedX: checkpoint.normalizedX, normalizedY: checkpoint.normalizedY)
            let checkpointLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return userLoc.distance(from: checkpointLoc) <= GameConstants.checkpointRevealDistanceMeters
        }
    }

    private var gameplayTrackingDistanceMeters: CLLocationDistance {
        let bounds = game.gameState.fieldBounds
        let sw = CLLocation(latitude: min(bounds.minLatitude, bounds.maxLatitude), longitude: min(bounds.minLongitude, bounds.maxLongitude))
        let ne = CLLocation(latitude: max(bounds.minLatitude, bounds.maxLatitude), longitude: max(bounds.minLongitude, bounds.maxLongitude))
        let diagonal = sw.distance(from: ne)
        return min(max(diagonal * 0.35, 80), 500)
    }

    private func updateGameplayCameraIfNeeded(force: Bool = false) {
        guard game.gameState.phase == .playing else { return }
        guard let coordinate = location.lastLocation?.coordinate else {
            gameplayCamera = .region(game.gameState.fieldBounds.coordinateRegion)
            return
        }

        if force == false, let previous = lastFollowedCoordinate {
            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let movedDistance = currentLocation.distance(from: previousLocation)
            guard movedDistance >= 2 else { return }
        }

        lastFollowedCoordinate = coordinate
        gameplayCamera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: gameplayTrackingDistanceMeters,
                heading: 0,
                pitch: 0
            )
        )
    }

    private func shortUUID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private var splitInstruction: String {
        if game.gameState.teamSplitAxis == .leftRight {
            return "Move around physically, then place your checkpoint at your real location. Red must be on the west/left half and Blue on east/right."
        }
        return "Move around physically, then place your checkpoint at your real location. Red must be on the top/north half and Blue on bottom/south."
    }

    private var checkpointCoordinate: CLLocationCoordinate2D? {
        guard let checkpoint = game.gameState.checkpoints.first(where: { $0.ownerPlayerId == game.localPlayerId }) else {
            return nil
        }
        return game.gameState.fieldBounds.coordinate(normalizedX: checkpoint.normalizedX, normalizedY: checkpoint.normalizedY)
    }

    private var gamePhaseTitle: String {
        switch game.gameState.phase {
        case .lobby:
            return "Lobby"
        case .selectingField:
            return "Choosing Field"
        case .placingCheckpoints:
            return "Placing Checkpoints"
        case .playing:
            return "Battle"
        case .ended:
            return "Finished"
        }
    }

    private var playfulBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.24), Color(red: 0.14, green: 0.24, blue: 0.44), Color(red: 0.07, green: 0.40, blue: 0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.yellow.opacity(0.12))
                .frame(width: 240, height: 240)
                .offset(x: 130, y: -210)
            Circle()
                .fill(Color.pink.opacity(0.12))
                .frame(width: 190, height: 190)
                .offset(x: -140, y: 200)
        }
        .ignoresSafeArea()
    }
}

private enum PlayingTab: String, CaseIterable, Identifiable {
    case overview
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Gameplay"
        case .map: return "Map"
        }
    }
}

#Preview {
    GameView()
        .environmentObject(GameViewModel())
}
