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
                        HStack {
                            Text(isSessionActive ? "Game Lobby" : "Arena Lobby")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.top, 20)
                        }

                        if isSessionActive {
                            sessionLobbyContent
                        } else {
                            landingSessionContent
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var landingSessionContent: some View {
        Group {
            lobbyCard(title: "Username", icon: "person.crop.circle") {
                TextField("Display name", text: $game.displayName)
                    .textInputAutocapitalization(.words)
                    .padding(10)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }

            lobbyCard(title: "Session", icon: "antenna.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Host a new game:")
                        .foregroundStyle(.white)
                        .bold()

                    lobbyActionButton("Create game", icon: "crown.fill") {
                        game.hostGame()
                    }

                    Text("Join existing game:")
                        .foregroundStyle(.white)
                        .bold()
                        .padding(.top, 10)

                    HStack(spacing: 10) {
                        TextField("Enter game code", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)

                        lobbyActionButton("Join", icon: "person.badge.plus") {
                            game.joinGame(joinCode: joinCode)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    private var sessionLobbyContent: some View {
        Group {
            if let joinCode = game.currentJoinCode {
                lobbyCard(title: "Join code", icon: "number") {
                    HStack {
                        Spacer()
                        Text(joinCode)
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
            }

            lobbyCard(title: "Players (\(game.gameState.players.count))", icon: "person.3.fill") {
                ForEach(game.gameState.players) { p in
                    HStack {
                        Text(p.id == game.localPlayerId ? "\(p.displayName) (You)" : p.displayName)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
            }

            lobbyCard(title: "", icon: "antenna.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 8) {
                    if game.isHost {
                        lobbyActionButton("Start match!", icon: "play.fill") {
                            game.startMatchFromLobby()
                        }
                        .disabled(game.gameState.players.count < GameConstants.minPlayersToStart)

                        lobbyActionButton("Disconnect", icon: "xmark.circle.fill", destructive: true) {
                            game.returnToLobby()
                        }
                    } else {
                        Text("Waiting for host to start...")
                            .foregroundStyle(.white)
                            .font(.headline)

                        lobbyActionButton("Disconnect", icon: "xmark.circle.fill", destructive: true) {
                            game.returnToLobby()
                        }
                    }
                }
            }

            if game.isHost {
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
            if title.isEmpty == false {
                Label(title, systemImage: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .background(
            destructive ? Color.red.opacity(0.78) : themeYellow,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var themeYellow: Color {
        Color(red: 0.9, green: 0.75, blue: 0.4)
    }

    private var isSessionActive: Bool {
        game.isHost || game.currentJoinCode != nil || game.gameState.phase != .lobby
    }
}

#Preview {
    LobbyView()
        .environmentObject(GameViewModel())
}
