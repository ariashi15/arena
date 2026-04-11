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
    @State private var showMapMode = false

    var body: some View {
        NavigationStack {
            Group {
                if game.gameState.phase == .playing {
                    playingBattleLayer
                } else {
                    ZStack {
                        playfulBackground
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                if game.gameState.phase == .placingCheckpoints {
                                    placingCard
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle(game.gameState.phase == .playing ? "" : "Arena")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                if phase != .playing {
                    showMapMode = false
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

    // MARK: - Playing (gamified HUD)

    private var playingBattleLayer: some View {
        ZStack {
            playingFieldBackground
                .ignoresSafeArea()

            if showMapMode {
                fullScreenGameplayMap
                    .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 0) {
                    teamCheckpointXPBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    Spacer(minLength: 0)

                    combatCirclesSection

                    Spacer(minLength: 0)
                }

                damagePopOverlay
            }

            mapModeToggleButton
        }
    }

    private var playingFieldBackground: some View {
        let engaged = game.buildShootEventIfPossible() != nil || game.isGettingShotAt
        let fill: Color = {
            if !engaged { return Color(white: 0.93) }
            guard let side = mapSideTeam else { return Color(white: 0.93) }
            return side == .a
                ? Color(red: 0.95, green: 0.45, blue: 0.42)
                : Color(red: 0.42, green: 0.62, blue: 0.98)
        }()
        return fill
    }

    private var mapSideTeam: Team? {
        guard let coordinate = location.lastLocation?.coordinate else { return nil }
        guard let point = game.gameState.fieldBounds.normalizedPoint(for: coordinate) else { return nil }
        switch game.gameState.teamSplitAxis {
        case .leftRight:
            return point.x < 0.5 ? .a : .b
        case .topBottom:
            return point.y >= 0.5 ? .a : .b
        }
    }

    private var teamCheckpointXPBar: some View {
        let redTotal = totalCheckpointXP(for: .a)
        let blueTotal = totalCheckpointXP(for: .b)
        let sum = max(redTotal + blueTotal, 1)
        let redFrac = CGFloat(redTotal) / CGFloat(sum)

        return VStack(spacing: 6) {
            GeometryReader { geo in
                checkpointBarRow(
                    width: geo.size.width,
                    redTotal: redTotal,
                    blueTotal: blueTotal,
                    redFraction: redFrac
                )
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            HStack {
                Text("Red")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red.opacity(0.9))
                Spacer()
                Text("Blue")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue.opacity(0.9))
            }
            .padding(.horizontal, 4)
        }
    }

    private func totalCheckpointXP(for team: Team) -> Int {
        game.gameState.checkpoints.filter { $0.team == team }.reduce(0) { $0 + $1.xp }
    }

    private func checkpointBarRow(width: CGFloat, redTotal: Int, blueTotal: Int, redFraction: CGFloat) -> some View {
        let redW = max(width * redFraction, 1)
        let blueW = max(width - redW, 1)
        return HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.92))
                Text("\(redTotal)")
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
            }
            .frame(width: redW)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.92))
                Text("\(blueTotal)")
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
            }
            .frame(width: blueW)
        }
    }

    private var combatCirclesSection: some View {
        let target = game.currentAimTarget
        let hasTarget = target != nil
        let selfPlayer = game.gameState.players.first(where: { $0.id == game.localPlayerId })
        let maxHP = CGFloat(GameConstants.playerMaxHealth)

        return VStack(spacing: hasTarget ? 18 : 0) {
            if let selfPlayer {
                healthCircle(
                    fraction: CGFloat(selfPlayer.health) / maxHP,
                    fill: selfPlayer.team == .a ? Color.red : Color.blue,
                    icon: "heart.fill",
                    size: hasTarget ? 118 : 140,
                    label: "You"
                )
                .scaleEffect(hasTarget ? 0.88 : 1)
                .offset(y: hasTarget ? -12 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: hasTarget)
            }

            if let target {
                switch target {
                case let .enemy(p):
                    healthCircle(
                        fraction: CGFloat(p.health) / maxHP,
                        fill: p.team == .a ? Color.red : Color.blue,
                        icon: "person.fill",
                        size: 104,
                        label: "Opponent"
                    )
                    .transition(.scale.combined(with: .opacity))
                case let .enemyCheckpoint(c):
                    let frac = CGFloat(c.xp) / CGFloat(GameConstants.checkpointMaxXP)
                    healthCircle(
                        fraction: frac,
                        fill: c.team == .a ? Color.red : Color.blue,
                        icon: "building.columns.fill",
                        size: 104,
                        label: "Checkpoint"
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 88)
    }

    private func healthCircle(
        fraction: CGFloat,
        fill: Color,
        icon: String,
        size: CGFloat,
        label: String
    ) -> some View {
        let clamped = min(max(fraction, 0), 1)

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: clamped * 0.999)
                    .fill(fill)
                    .frame(width: size * 0.92, height: size * 0.92)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 3)
                    .frame(width: size, height: size)

                Image(systemName: icon)
                    .font(.system(size: size * 0.26, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary.opacity(0.65))
        }
    }

    private var damagePopOverlay: some View {
        ZStack {
            if let incoming = game.incomingDamagePop {
                Text("-\(incoming)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                    .offset(y: -140)
                    .transition(.scale(scale: 1.2).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: incoming)
            }

            if let outgoing = game.outgoingDamagePop {
                Text("-\(outgoing)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .shadow(color: .orange.opacity(0.6), radius: 4, x: 0, y: 0)
                    .offset(x: 90, y: -40)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.28, dampingFraction: 0.62), value: outgoing)
            }
        }
        .allowsHitTesting(false)
    }

    private var mapModeToggleButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showMapMode.toggle()
                } label: {
                    Image(systemName: showMapMode ? "heart.fill" : "map.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 58, height: 58)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private var fullScreenGameplayMap: some View {
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
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
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

#Preview {
    GameView()
        .environmentObject(GameViewModel())
}
