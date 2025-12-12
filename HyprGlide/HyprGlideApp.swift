//
//  HyprGlideApp.swift
//  HyprGlide
//
//  SwiftUI main entry point for the HyprGlide game
//

import SwiftUI

@main
struct HyprGlideApp: App {
    @StateObject private var gameCenterManager = GameCenterManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameCenterManager)
                .task {
                    gameCenterManager.authenticateIfNeeded()
                }
        }
    }
}
