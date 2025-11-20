//
//  GameState.swift
//  HyperSlide
//
//  Observable game state model for tracking score, game status, and difficulty
//

import Foundation
import Observation

@Observable
class GameState {
    // UserDefaults key for best score persistence
    private static let bestScoreKey = "HyperSlide.BestScore"
    private let defaults: UserDefaults
    
    // Current game score (time + dodge points)
    var score: Double = 0
    
    // Best score achieved across all games (persisted)
    var bestScore: Double {
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
    var isGameOver: Bool = false
    var isPaused: Bool = false
    var hasStarted: Bool = false  // Track if game has started from menu
    
    // Elapsed time in seconds
    var elapsed: TimeInterval = 0
    
    // Current difficulty level (0.0 to 1.0, computed from elapsed time)
    // Scales linearly from 0 to 1 over 90 seconds
    var difficulty: Double {
        min(1.0, elapsed / 90.0)
    }
    
    // Current level (1 to 10, derived from difficulty)
    var level: Int {
        max(1, min(10, Int((difficulty * 10).rounded()) + 1))
    }
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: GameState.bestScoreKey) == nil {
            self.bestScore = 0
            DefaultsGuard.write(on: defaults) { store in
                store.set(0, forKey: GameState.bestScoreKey)
            }
        } else {
            self.bestScore = DefaultsGuard.read(from: defaults) { store in
                store.double(forKey: GameState.bestScoreKey)
            } ?? 0
        }
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
        guard !isPaused && !isGameOver else { return }
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
    
    /// Record the current score as best if it's higher
    func recordBest() {
        if score > bestScore {
            bestScore = score
        }
    }
    
    /// Toggle pause state
    func togglePause() {
        isPaused.toggle()
    }
    
    /// Update elapsed time (difficulty is computed from elapsed)
    func updateTime(delta: TimeInterval) {
        guard !isPaused && !isGameOver else { return }
        elapsed += delta
    }
}

