//
//  HUDView.swift
//  HyperSlide
//
//  SwiftUI overlay displaying score, best score, and game controls
//

import SwiftUI

struct HUDView: View {
    @Bindable var gameState: GameState
    @Bindable var settings: Settings
    @ObservedObject var soundManager: SoundManager
    var onRestart: () -> Void
    
    @State private var showSettings = false
    
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
            .font(.system(size: 72, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .accessibilityLabel("Score: \(Int(gameState.score.rounded()))")
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
                .neonGlow(color: settings.colorTheme.primaryColor, radius: 22, intensity: 0.85)
            
            // Instructions
            Text("Dodge the falling objects")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // START Button
            Button {
                startGame()
            } label: {
                Text("START")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(settings.colorTheme.primaryColor)
                    .tracking(3)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(settings.colorTheme.primaryColor, lineWidth: 3)
                    )
            }
            .accessibilityLabel("Start game")
            
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
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
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
            .accessibilityLabel("Restart game")
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
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(3)
            
            Button {
                gameState.togglePause()
            } label: {
                Text("RESUME")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(settings.colorTheme.primaryColor)
                    .tracking(3)
                    .padding(.horizontal, 50)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(settings.colorTheme.primaryColor, lineWidth: 3)
                    )
            }
            .accessibilityLabel("Resume game")
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            // Pause/Resume Button (left corner)
            if gameState.hasStarted && !gameState.isGameOver {
                Button {
                    gameState.togglePause()
                } label: {
                    Image(systemName: gameState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .accessibilityLabel(gameState.isPaused ? "Resume game" : "Pause game")
            }
            
            Spacer()
            
            // Settings and Mute buttons
            HStack(spacing: 12) {
                if gameState.isPaused || !gameState.hasStarted {
                    settingsButton
                }
                
                if gameState.isPaused {
                    muteButton
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
                .presentationBackground(.clear)
                .presentationCornerRadius(0)
                .presentationBackgroundInteraction(.enabled)
        }
    }
    
    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
    }
    
    private var muteButton: some View {
        Button {
            soundManager.toggleMute()
        } label: {
            Image(systemName: soundManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(soundManager.isMuted ? "Unmute sound effects" : "Mute sound effects")
        .accessibilityHint("Toggles HyperSlide's sound effects.")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        HUDView(gameState: GameState(),
                settings: Settings(),
                soundManager: SoundManager(),
                onRestart: {})
    }
}

// MARK: - Neon Glow Effect

private struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let intensity: Double
    
    func body(content: Content) -> some View {
        content
            // Primary glow bloom
            .shadow(color: color.opacity(intensity), radius: radius)
            // Secondary halo for a diffused aura
            .shadow(color: color.opacity(intensity * 0.6), radius: radius * 1.6)
            // Subtle inner glow to keep text readable while illuminated
            .overlay {
                content
                    .foregroundStyle(color.opacity(intensity * 0.55))
                    .blur(radius: radius / 2.8)
                    .blendMode(.screen)
            }
    }
}

private extension View {
    /// Applies a neon-style glow using additive shadows and a blurred overlay.
    /// - Parameters:
    ///   - color: Glow color, typically a vivid neon hue.
    ///   - radius: Base blur radius for the glow bloom.
    ///   - intensity: Opacity multiplier controlling glow brightness.
    func neonGlow(color: Color,
                  radius: CGFloat = 18,
                  intensity: Double = 0.8) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius, intensity: intensity))
    }
}

