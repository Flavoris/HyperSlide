//
//  ContentView.swift
//  HyperSlide
//
//  Root SwiftUI view combining SpriteKit scene with HUD overlay
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var gameState = GameState()
    @StateObject private var soundManager = SoundManager()
    @State private var gameScene: GameScene = {
        let scene = GameScene()
        scene.size = UIScreen.main.bounds.size
        scene.scaleMode = .resizeFill
        return scene
    }()
    
    var body: some View {
        ZStack {
            // SpriteKit Game Scene
            SpriteView(scene: gameScene)
                .ignoresSafeArea()
            
            // SwiftUI HUD Overlay
            HUDView(gameState: gameState,
                    soundManager: soundManager,
                    onRestart: handleRestart)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Inject game state when view appears
            gameScene.gameState = gameState
            gameScene.soundManager = soundManager
        }
    }
    
    // MARK: - Game Actions
    
    /// Handle game restart by coordinating between HUD and scene
    private func handleRestart() {
        // Record best score before resetting
        gameState.recordBest()
        
        // Reset the scene (which will also reset game state)
        gameScene.resetGame(state: gameState)
        
        // Immediately start the game again (don't show start menu)
        gameState.startGame()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

