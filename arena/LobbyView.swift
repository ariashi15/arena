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
            ZStack {
                lobbyBackground

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        lobbyCard(title: "Player", icon: "person.crop.circle") {
                            TextField("Display name", text: $game.displayName)
                                .textInputAutocapitalization(.words)
                                .padding(10)
                                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }

                        lobbyCard(title: "Session", icon: "antenna.radiowaves.left.and.right") {
                            VStack(alignment: .leading, spacing: 8) {
                                lobbyActionButton("Host game", icon: "dot.radiowaves.left.and.right") {
                                    game.hostGame()
                                }

                                TextField("Join code", text: $joinCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(.white)

                                lobbyActionButton("Join game", icon: "person.badge.plus") {
                                    game.joinGame(joinCode: joinCode)
                                }

                                lobbyActionButton("Disconnect", icon: "xmark.circle.fill", destructive: true) {
                                    game.disconnect()
                                }
                            }
                        }

                        if game.isHost {
                            lobbyCard(title: "Host controls", icon: "crown.fill") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let joinCode = game.currentJoinCode {
                                        Text("Join code: \(joinCode)")
                                            .font(.headline)
                                            .foregroundStyle(.yellow)
                                    }
                                    lobbyActionButton("Start match (random teams)", icon: "play.fill") {
                                        game.startMatchFromLobby()
                                    }
                                    .disabled(game.gameState.players.count < GameConstants.minPlayersToStart)
                                }
                            }

                            lobbyCard(title: "Pending requests", icon: "person.crop.circle.badge.questionmark") {
                                if game.pendingJoinRequests.isEmpty {
                                    Text("No pending join requests")
                                        .foregroundStyle(.white.opacity(0.75))
                                } else {
                                    ForEach(game.pendingJoinRequests) { request in
                                        HStack {
                                            Text(request.displayName)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Button("Allow") {
                                                game.approveJoinRequest(playerId: request.playerId)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            Button("Deny", role: .destructive) {
                                                game.rejectJoinRequest(playerId: request.playerId)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }

                            lobbyCard(title: "Solo testing", icon: "wrench.and.screwdriver.fill") {
                                VStack(alignment: .leading, spacing: 8) {
                                    lobbyActionButton("Bypass to gameplay view (instant)", icon: "bolt.fill") {
                                        game.startGameplayBypassFromLobby()
                                    }
                                    .disabled(game.gameState.phase != .lobby)

                                    lobbyActionButton("Start solo test match (1 device)", icon: "person.2.fill") {
                                        game.startSoloTestMatchFromLobby()
                                    }
                                    .disabled(game.gameState.phase != .lobby)

                                    lobbyActionButton("Add solo test opponent", icon: "plus.circle.fill") {
                                        game.addSoloTestOpponent()
                                    }
                                    .disabled(game.gameState.phase != .lobby)

                                    if game.gameState.players.contains(where: { $0.id == GameConstants.soloTestBotPlayerId }) {
                                        lobbyActionButton("Remove solo test opponent", icon: "minus.circle.fill", destructive: true) {
                                            game.removeSoloTestOpponent()
                                        }
                                        .disabled(game.gameState.phase != .lobby)
                                    }
                                }
                            }
                        }

                        lobbyCard(title: "Players (\(game.gameState.players.count))", icon: "person.3.fill") {
                            ForEach(game.gameState.players) { p in
                                HStack {
                                    Text(p.displayName)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if p.id == game.localPlayerId {
                                        Text("You")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.yellow, in: Capsule())
                                            .foregroundStyle(.black)
                                    }
                                }
                            }
                        }

                        if !game.statusMessage.isEmpty {
                            lobbyCard(title: "Status", icon: "bubble.left.and.bubble.right.fill") {
                                Text(game.statusMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Arena Lobby")
        }
    }

    private var lobbyBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.10, green: 0.46, blue: 0.50)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func lobbyCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            content()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func lobbyActionButton(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .foregroundStyle(destructive ? Color.white : Color.black)
        .background(
            destructive ? Color.red.opacity(0.78) : Color.yellow,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

#Preview {
    LobbyView()
        .environmentObject(GameViewModel())
}
