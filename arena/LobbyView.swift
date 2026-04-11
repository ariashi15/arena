//
//  LobbyView.swift
//  arena
//

import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Display name", text: $game.displayName)
                        .textInputAutocapitalization(.words)
                }

                Section("Session") {
                    Button("Host game") {
                        game.hostGame()
                    }
                    Button("Join game") {
                        game.joinGame()
                    }
                    Button("Disconnect", role: .destructive) {
                        game.disconnect()
                    }
                }

                if game.isHost {
                    Section("Host") {
                        Button("Start match (random teams)") {
                            game.startMatchFromLobby()
                        }
                        .disabled(game.gameState.players.count < GameConstants.minPlayersToStart)
                    }
                }

                Section("Players (\(game.gameState.players.count))") {
                    ForEach(game.gameState.players) { p in
                        HStack {
                            Text(p.displayName)
                            Spacer()
                            if p.id == game.localPlayerId {
                                Text("You").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !game.statusMessage.isEmpty {
                    Section("Status") {
                        Text(game.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Arena Lobby")
        }
    }
}

#Preview {
    LobbyView()
        .environmentObject(GameViewModel())
}
