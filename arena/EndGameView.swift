//
//  EndGameView.swift
//  arena
//

import SwiftUI

struct EndGameView: View {
    @EnvironmentObject private var game: GameViewModel

    private var sortedPlayers: [PlayerState] {
        game.gameState.players.sorted {
            if $0.kills != $1.kills { return $0.kills > $1.kills }
            if $0.damageDone != $1.damageDone { return $0.damageDone > $1.damageDone }
            return $0.deaths < $1.deaths
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.05, blue: 0.25),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    leaderboard
                    Button {
                        game.returnToLobby()
                    } label: {
                        Text("Back to Lobby")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("GAME OVER")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, Color(red: 1.0, green: 0.85, blue: 0.2), .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .yellow.opacity(0.6), radius: 18)

            if let winner = game.gameState.winningTeam {
                Text("\(winner.displayName) Team Wins!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(teamColor(winner))
                    .shadow(color: teamColor(winner).opacity(0.6), radius: 10)
            } else {
                Text("It's a Draw")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 8)
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Leaderboard")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                ForEach(Array(sortedPlayers.enumerated()), id: \.element.id) { idx, player in
                    row(rank: idx + 1, player: player)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
        )
    }

    private func row(rank: Int, player: PlayerState) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.yellow)
                            .shadow(color: .yellow.opacity(0.8), radius: 6)
                    }
                    Text(rankBadge(rank))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 68, alignment: .leading)

                Circle()
                    .fill(teamColor(player.team))
                    .frame(width: 16, height: 16)
                    .shadow(color: teamColor(player.team), radius: 6)

                Text(player.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()
            }

            HStack(spacing: 0) {
                statCell(label: "Kills", value: player.kills, color: .yellow)
                Divider().frame(height: 36).background(Color.white.opacity(0.2))
                statCell(label: "Damage", value: player.damageDone, color: .orange)
                Divider().frame(height: 36).background(Color.white.opacity(0.2))
                statCell(label: "Deaths", value: player.deaths, color: .white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(rank == 1
                    ? LinearGradient(colors: [.yellow.opacity(0.25), .orange.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rank == 1 ? Color.yellow.opacity(0.6) : Color.white.opacity(0.12), lineWidth: rank == 1 ? 2 : 1)
        )
    }

    private func statCell(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func rankBadge(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }

    private func teamColor(_ team: Team) -> Color {
        switch team {
        case .a: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .b: return Color(red: 0.35, green: 0.55, blue: 1.0)
        }
    }
}

#Preview {
    EndGameView()
        .environmentObject(GameViewModel())
}
