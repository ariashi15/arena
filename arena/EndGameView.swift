//
//  EndGameView.swift
//  arena
//

import SwiftUI

struct EndGameView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Game Over")
                .font(.largeTitle.weight(.bold))
            if let winner = game.gameState.winningTeam {
                Text("\(winner.displayName) wins")
                    .font(.title2)
            } else {
                Text("Draw")
                    .font(.title2)
            }
            Button("Back to lobby") {
                game.returnToLobby()
            }
            .buttonStyle(.borderedProminent)
            Text("Disconnect or host a new session from the lobby when you leave this screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    EndGameView()
        .environmentObject(GameViewModel())
}
