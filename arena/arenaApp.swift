//
//  arenaApp.swift
//  arena
//
//  Created by Aria Shi on 4/11/26.
//

import SwiftUI

@main
struct arenaApp: App {
    @StateObject private var gameViewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameViewModel)
        }
    }
}
