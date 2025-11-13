//
//  HUDView.swift
//  HyperSlide
//
//  SwiftUI overlay displaying score, best score, and game controls
//

import SwiftUI

struct HUDView: View {
    @Bindable var gameState: GameState
    var onRestart: () -> Void
    
    var body: some View {
        ZStack {
            VStack {
                // Top: Score display (only during gameplay)
                if gameState.hasStarted && !gameState.isGameOver {
                    scoreDisplay
                        .padding(.top, 40)
                }
                
                Spacer()
                
                // Center: Start menu, Game Over, or Pause overlay
                if !gameState.hasStarted {
                    startMenuOverlay
                } else if gameState.isGameOver {
                    gameOverOverlay
                } else if gameState.isPaused {
                    pausedOverlay
                }
                
                Spacer()
                
                // Bottom HUD: Control buttons (always visible in corners)
                bottomBar
                    .padding(.bottom, 20)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Score Display
    
    private var scoreDisplay: some View {
        Text("\(Int(gameState.score.rounded()))")
            .font(.system(size: 60, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
    
    // MARK: - Overlays
    
    private var startMenuOverlay: some View {
        VStack(spacing: 30) {
            // Score at top (starts at 0)
            Text("\(Int(gameState.score.rounded()))")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Spacer()
            
            // Hyper Slide Title
            Text("Hyper\nSlide")
                .font(.custom("Ethnocentric", size: 68)) // Futuristic, monospaced aesthetic
                .fontWeight(.heavy)
                .foregroundStyle(.white)
                .tracking(3)
                .multilineTextAlignment(.center)
            
            // Instructions
            Text("Tap anywhere to move left or right")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // START Button
            Button {
                startGame()
            } label: {
                Text("START")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("NeonBlue"))
                    .tracking(3)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(Color("NeonBlue"), lineWidth: 3)
                    )
            }
            
            Spacer()
        }
    }
    
    private var gameOverOverlay: some View {
        VStack(spacing: 25) {
            // GAME OVER Text
            Text("GAME OVER")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                .tracking(3)
            
            // Score
            Text("\(Int(gameState.score.rounded()))")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            // Best Score
            Text("Best: \(Int(gameState.bestScore.rounded()))")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            
            // RESTART Button
            Button {
                restartGame()
            } label: {
                Text("RESTART")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.2, blue: 0.6))
                    .tracking(3)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(Color(red: 1.0, green: 0.2, blue: 0.6), lineWidth: 3)
                    )
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - Helper Methods
    
    private func startGame() {
        gameState.startGame()
    }
    
    private func restartGame() {
        // Delegate to the restart handler in ContentView
        // which coordinates scene reset and best score recording
        onRestart()
    }
    
    private var pausedOverlay: some View {
        VStack(spacing: 25) {
            Text("PAUSED")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(3)
            
            Button {
                gameState.togglePause()
            } label: {
                Text("RESUME")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("NeonBlue"))
                    .tracking(3)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(Color("NeonBlue"), lineWidth: 3)
                    )
            }
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            // Pause/Resume Button (left corner)
            if gameState.hasStarted {
                Button {
                    gameState.togglePause()
                } label: {
                    Image(systemName: gameState.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .disabled(gameState.isGameOver)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        HUDView(gameState: GameState(), onRestart: {})
    }
}

