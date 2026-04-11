//
//  ContentView.swift
//  arena
//
//  Created by Aria Shi on 4/11/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
        Group {
            switch game.gameState.phase {
            case .lobby:
                LobbyView()
            case .selectingField:
                if game.localPlayerId == game.gameState.hostPlayerId {
                    FieldSelectionView()
                } else {
                    WaitingForHostFieldView()
                }
            case .placingCheckpoints, .playing:
                GameView()
            case .ended:
                EndGameView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GameViewModel())
}
