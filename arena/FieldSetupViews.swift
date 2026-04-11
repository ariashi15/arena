//
//  FieldSetupViews.swift
//  arena
//

import MapKit
import SwiftUI

struct FieldSelectionView: View {
    @EnvironmentObject private var game: GameViewModel
    @StateObject private var location = LocationManager()
    @State private var camera: MapCameraPosition = .automatic
    @State private var draft = FieldBounds.fallback
    @State private var firstCorner: CLLocationCoordinate2D?
    @State private var secondCorner: CLLocationCoordinate2D?
    @State private var splitAxis: TeamSplitAxis = .leftRight

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Tap 2 corners on the map to define the play area. Pan/zoom is only for navigation and no longer changes the field.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                MapReader { proxy in
                    Map(position: $camera) {
                        MapPolygon(coordinates: draft.teamAPolygonCoordinates(splitAxis: splitAxis))
                            .foregroundStyle(Color.cyan.opacity(0.28))
                        MapPolygon(coordinates: draft.teamBPolygonCoordinates(splitAxis: splitAxis))
                            .foregroundStyle(Color.pink.opacity(0.24))
                        if let firstCorner {
                            Marker("Corner 1", coordinate: firstCorner)
                        }
                        if let secondCorner {
                            Marker("Corner 2", coordinate: secondCorner)
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                                applyCornerTap(coordinate)
                            }
                    )
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onAppear {
                    location.requestAuthorizationIfNeeded()
                    location.startUpdates()
                    draft = game.gameState.fieldBounds
                    splitAxis = game.gameState.teamSplitAxis
                    camera = .region(draft.coordinateRegion)
                }
                .onDisappear {
                    location.stopUpdates()
                }

                VStack(spacing: 12) {
                    Picker("Team split", selection: $splitAxis) {
                        Text("Left / Right").tag(TeamSplitAxis.leftRight)
                        Text("Top / Bottom").tag(TeamSplitAxis.topBottom)
                    }
                    .pickerStyle(.segmented)

                    Button("Reset selected corners") {
                        firstCorner = nil
                        secondCorner = nil
                    }
                    .buttonStyle(.bordered)

                    if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                        Text("Location is off—you can still drag the map to choose the field.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        if let c = location.lastLocation?.coordinate {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                camera = .region(
                                    MKCoordinateRegion(
                                        center: c,
                                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                                    )
                                )
                            }
                        }
                    } label: {
                        Label("Center on my location", systemImage: "location.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(location.lastLocation == nil)

                    Button("Confirm play area") {
                        game.confirmFieldBounds(draft.clampedValid(), splitAxis: splitAxis)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Choose field")
        }
    }

    private func applyCornerTap(_ coordinate: CLLocationCoordinate2D) {
        if firstCorner == nil || (firstCorner != nil && secondCorner != nil) {
            firstCorner = coordinate
            secondCorner = nil
            return
        }

        secondCorner = coordinate
        if let firstCorner {
            draft = FieldBounds(cornerA: firstCorner, cornerB: coordinate).clampedValid()
        }
    }
}

struct WaitingForHostFieldView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("Waiting for host")
                    .font(.title2.weight(.semibold))
                Text("The host is choosing the play area on the map. Hang tight.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if !game.statusMessage.isEmpty {
                    Text(game.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Arena")
        }
    }
}

#Preview("Host field") {
    FieldSelectionView()
        .environmentObject(GameViewModel())
}

#Preview("Waiting") {
    WaitingForHostFieldView()
        .environmentObject(GameViewModel())
}
