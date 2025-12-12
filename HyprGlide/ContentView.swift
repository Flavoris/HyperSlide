//
//  ContentView.swift
//  HyprGlide
//
//  Root SwiftUI view combining SpriteKit scene with HUD overlay
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @StateObject private var settings = Settings()
    @StateObject private var soundManager = SoundManager()
    @StateObject private var multiplayerState = MultiplayerState()
    @StateObject private var multiplayerManager = MultiplayerManager()
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
                    settings: settings,
                    multiplayerState: multiplayerState,
                    multiplayerManager: multiplayerManager,
                    onRestart: handleRestart,
                    onExitToMainMenu: handleExitToMainMenu)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Inject game state and settings when view appears
            gameScene.gameState = gameState
            gameScene.settings = settings
            gameScene.soundManager = soundManager
            soundManager.primeAudioIfNeeded()
            soundManager.setMusicVolume(Float(settings.musicVolume))
            soundManager.setSFXVolume(Float(settings.sfxVolume))
            gameScene.updateTiltControlPreference(isEnabled: settings.tiltControlEnabled)
            gameScene.multiplayerManager = multiplayerManager
            gameScene.multiplayerState = multiplayerState
            multiplayerManager.gameState = gameState
            multiplayerManager.multiplayerState = multiplayerState
            multiplayerManager.sceneDelegate = gameScene
            gameScene.updateGlowPreference(isEnabled: settings.glowEffectsEnabled)
            gameState.setActiveDifficultyRamp(settings.difficultyRamp)
        }
        .onChange(of: settings.difficultyRamp) { newValue in
            gameState.setActiveDifficultyRamp(newValue)
        }
        .onChange(of: settings.colorTheme) { _ in
            // Update player colors when theme changes
            gameScene.updatePlayerColors()
        }
        .onChange(of: settings.tiltControlEnabled) { newValue in
            gameScene.updateTiltControlPreference(isEnabled: newValue)
        }
        .onChange(of: settings.musicVolume) { newValue in
            soundManager.setMusicVolume(Float(newValue))
        }
        .onChange(of: settings.sfxVolume) { newValue in
            soundManager.setSFXVolume(Float(newValue))
        }
        .onChange(of: settings.glowEffectsEnabled) { newValue in
            gameScene.updateGlowPreference(isEnabled: newValue)
        }
    }
    
    // MARK: - Game Actions
    
    /// Handle game restart by coordinating between HUD and scene
    private func handleRestart() {
        // Record best score before resetting
        gameState.recordBest(for: difficultyRampForCurrentRun())
        
        if gameState.mode.isMultiplayer {
            multiplayerManager.requestRematch()
            return
        }
        
        // Reset the scene (which will also reset game state)
        gameScene.resetGame(state: gameState)
        
        // Immediately start the game again (don't show start menu)
        gameState.startGame()
    }
    
    /// Handle exit to main menu by resetting scene and returning to start screen
    private func handleExitToMainMenu() {
        // Record best score before resetting
        gameState.recordBest(for: difficultyRampForCurrentRun())
        
        // Reset multiplayer state if in multiplayer mode
        if gameState.mode.isMultiplayer {
            multiplayerManager.disconnect()
            multiplayerState.reset()
        }
        
        // Always clear multiplayer visuals so remote orbs don't linger on the menu
        gameScene.cleanupMultiplayerArena()
        
        // Reset the scene (clears obstacles, resets player position, etc.)
        gameScene.resetGame(state: gameState)
        
        // Reset game state to show start menu (don't start the game)
        gameState.resetGame()
        
        // Set mode back to single player
        gameState.mode = .singlePlayer
    }
    
    /// Determines which difficulty ramp should be used for best score tracking for the current run.
    private func difficultyRampForCurrentRun() -> DifficultyRamp {
        gameState.mode.isMultiplayer ? .normal : settings.difficultyRamp
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
