//
//  LobbyView.swift
//  arena
//

import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var game: GameViewModel
    @State private var joinCode: String = ""

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
                    TextField("Join code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button("Join game") {
                        game.joinGame(joinCode: joinCode)
                    }
                    Button("Disconnect", role: .destructive) {
                        game.disconnect()
                    }
                }

                if game.isHost {
                    Section("Host") {
                        if let joinCode = game.currentJoinCode {
                            Text("Join code: \(joinCode)")
                                .font(.headline)
                        }
                        Button("Start match (random teams)") {
                            game.startMatchFromLobby()
                        }
                        .disabled(game.gameState.players.count < GameConstants.minPlayersToStart)
                    }

                    Section("Solo testing") {
                        Button("Start solo test match (1 device)") {
                            game.startSoloTestMatchFromLobby()
                        }
                        .disabled(game.gameState.phase != .lobby)

                        Button("Add solo test opponent") {
                            game.addSoloTestOpponent()
                        }
                        .disabled(game.gameState.phase != .lobby)

                        if game.gameState.players.contains(where: { $0.id == GameConstants.soloTestBotPlayerId }) {
                            Button("Remove solo test opponent", role: .destructive) {
                                game.removeSoloTestOpponent()
                            }
                            .disabled(game.gameState.phase != .lobby)
                        }
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
