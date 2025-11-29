//
//  GameState.swift
//  HyprGlide
//
//  Observable game state model for tracking score, game status, and difficulty
//

import Foundation
import Combine

class GameState: ObservableObject {
    // UserDefaults key for best score persistence
    private static let bestScoreKey = "HyprGlide.BestScore"
    // Total seconds for the difficulty ramp to reach max (longer ramp = longer levels)
    private static let difficultyRampDuration: TimeInterval = 300
    static let maxLevel = 20
    private let defaults: UserDefaults
    
    // Current game score (time + dodge points)
    @Published var score: Double = 0
    
    // Best score achieved across all games (persisted)
    @Published var bestScore: Double {
        didSet {
            guard bestScore != oldValue else { return }
            let sanitizedScore = max(0, bestScore)
            if sanitizedScore != bestScore {
                bestScore = sanitizedScore
                return
            }
            DefaultsGuard.write(on: defaults) { store in
                store.set(sanitizedScore, forKey: GameState.bestScoreKey)
            }
        }
    }
    
    // Game status flags
    @Published var isGameOver: Bool = false
    @Published var isPaused: Bool = false
    @Published var hasStarted: Bool = false  // Track if game has started from menu
    
    // Current game mode (singlePlayer or multiplayer).
    // GameState remains framework-agnostic; GameKit logic lives in GameCenterManager.
    @Published var mode: GameMode = .singlePlayer
    
    // Elapsed time in seconds
    @Published var elapsed: TimeInterval = 0
    
    // Current difficulty level (0.0 to 1.0, computed from elapsed time)
    // Scales linearly from 0 to 1 over 300 seconds (~15 seconds per level across 20 levels)
    var difficulty: Double {
        min(1.0, elapsed / GameState.difficultyRampDuration)
    }
    
    // Current level (1 to 20, derived from difficulty)
    var level: Int {
        let normalizedDifficulty = min(max(difficulty, 0), 1)
        return Int((normalizedDifficulty * Double(GameState.maxLevel - 1)).rounded()) + 1
    }
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Need to initialize stored properties before 'self' is used
        let initialBestScore: Double
        if defaults.object(forKey: GameState.bestScoreKey) == nil {
            initialBestScore = 0
            DefaultsGuard.write(on: defaults) { store in
                store.set(0, forKey: GameState.bestScoreKey)
            }
        } else {
            initialBestScore = DefaultsGuard.read(from: defaults) { store in
                store.double(forKey: GameState.bestScoreKey)
            } ?? 0
        }
        self.bestScore = initialBestScore
    }
    
    // MARK: - Game Actions
    
    /// Reset the game state for a new game
    func resetGame() {
        score = 0
        isGameOver = false
        isPaused = false
        hasStarted = false
        elapsed = 0
    }
    
    /// Start the game from the menu
    func startGame() {
        hasStarted = true
        score = 0
        isGameOver = false
        isPaused = false
        elapsed = 0
    }
    
    /// Add time-based score increment
    func addTime(delta: Double) {
        // In multiplayer, keep time/score progression running even if pause UI is shown.
        guard (!isPaused || mode.isMultiplayer) && !isGameOver else { return }
        score += delta
    }
    
    /// Add dodge bonus points
    func addDodge(points: Double) {
        guard !isGameOver else { return }
        score += points
    }
    
    /// Award a small bonus for narrowly avoiding an obstacle.
    func addNearMissBonus(points: Double = 2) {
        guard !isGameOver else { return }
        score += points
    }
    
    /// Record the current score as best if it's higher, and submit to Game Center.
    func recordBest() {
        if score > bestScore {
            bestScore = score
            // Submit new high score to Game Center leaderboard (silent no-op if not authenticated).
            GameCenterManager.shared.submitBestScoreIfGameCenterAvailable(score: score)
        }
    }
    
    /// Force the game into a paused state if an active run is in progress.
    func pauseGame() {
        guard hasStarted, !isGameOver, !isPaused else { return }
        isPaused = true
    }
    
    /// Resume gameplay if the user previously paused the active run.
    func resumeGame() {
        guard hasStarted, !isGameOver, isPaused else { return }
        isPaused = false
    }
    
    /// Toggle pause state
    func togglePause() {
        if isPaused {
            resumeGame()
        } else {
            pauseGame()
        }
    }
    
    /// Update elapsed time (difficulty is computed from elapsed)
    func updateTime(delta: TimeInterval) {
        // In multiplayer, keep elapsed time moving to avoid desync with peers.
        guard (!isPaused || mode.isMultiplayer) && !isGameOver else { return }
        elapsed += delta
    }
}
