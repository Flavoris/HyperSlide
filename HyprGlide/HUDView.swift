//
//  HUDView.swift
//  HyprGlide
//
//  SwiftUI overlay displaying score, best score, and game controls
//

import SwiftUI

struct HUDView: View {
    @ObservedObject var gameState: GameState
    @ObservedObject var settings: Settings
    var onRestart: () -> Void
    
    /// Accent color for the Game Over title and button, using a deeper neon red for better contrast.
    private let gameOverAccentColor = Color(red: 0.78, green: 0.02, blue: 0.12)
    
    @State private var showSettings = false
    @State private var showMovementHint = false
    @State private var hintDismissTask: Task<Void, Never>?
    
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
        .overlay(alignment: .bottom) {
            if showMovementHint {
                MovementHintChip(accentColor: settings.colorTheme.primaryColor)
                    .padding(.bottom, 120)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: gameState.hasStarted) { hasStarted in
            handleGameStartChange(hasStarted)
        }
        .onChange(of: gameState.isGameOver) { isGameOver in
            if isGameOver {
                hideMovementHint()
            }
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
            
            // Hypr Glide Title
            Text("Hypr\nGlide")
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
                .foregroundStyle(gameOverAccentColor)
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
                .foregroundStyle(gameOverAccentColor)
                .tracking(3)
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 50)
                        .strokeBorder(gameOverAccentColor, lineWidth: 3)
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
                gameState.resumeGame()
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
    
    // MARK: - Movement Hint
    
    private func handleGameStartChange(_ hasStarted: Bool) {
        if hasStarted && !gameState.isGameOver {
            showMovementHintForNewRun()
        } else {
            hideMovementHint()
        }
    }
    
    private func showMovementHintForNewRun() {
        hintDismissTask?.cancel()
        hintDismissTask = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            showMovementHint = true
        }
        
        hintDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            hideMovementHint()
        }
    }
    
    private func hideMovementHint() {
        hintDismissTask?.cancel()
        hintDismissTask = nil
        guard showMovementHint else { return }
        withAnimation(.easeOut(duration: 0.45)) {
            showMovementHint = false
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            // Pause/Resume Button (left corner)
            if gameState.hasStarted && !gameState.isGameOver {
                Button {
                    if gameState.isPaused {
                        gameState.resumeGame()
                    } else {
                        gameState.pauseGame()
                    }
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
                
            }
        }
        .sheet(isPresented: $showSettings) {
            if #available(iOS 16.4, *) {
                SettingsView(settings: settings)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(0)
                    .presentationBackgroundInteraction(.enabled)
            } else {
                // Fallback for iOS 16.0 - 16.3 (or earlier if supported)
                SettingsView(settings: settings)
                    // .presentationDetents([.large]) // Optional: if you want to control sheet size
            }
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
    
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        HUDView(gameState: GameState(),
                settings: Settings(),
                onRestart: {})
    }
}

// MARK: - Neon Glow Effect

private struct MovementHintChip: View {
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 14, weight: .semibold))
            
            Text("Drag or tilt to move")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.68))
                .overlay(
                    Capsule()
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.4), radius: 16, x: 0, y: 8)
        .accessibilityLabel("Hint: Drag or tilt to move")
    }
}

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
