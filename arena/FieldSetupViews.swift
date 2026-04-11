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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Pan and zoom Apple Maps. The colored overlay matches the current map view—set the area you want, then confirm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Map(position: $camera) {
                    MapPolygon(coordinates: draft.teamAPolygonCoordinates)
                        .foregroundStyle(Color.cyan.opacity(0.28))
                    MapPolygon(coordinates: draft.teamBPolygonCoordinates)
                        .foregroundStyle(Color.pink.opacity(0.24))
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
                    camera = .region(draft.coordinateRegion)
                }
                .onDisappear {
                    location.stopUpdates()
                }
                .onMapCameraChange(frequency: .continuous) { ctx in
                    draft = FieldBounds(region: ctx.region)
                }

                VStack(spacing: 12) {
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
                        game.confirmFieldBounds(draft.clampedValid())
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Choose field")
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
