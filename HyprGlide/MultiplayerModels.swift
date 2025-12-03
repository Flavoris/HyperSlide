//
//  MultiplayerModels.swift
//  HyprGlide
//
//  Multiplayer data models — framework-agnostic types for representing
//  game modes and multiplayer state. No GameKit or UIKit dependencies.
//

import Foundation
import SwiftUI

// MARK: - Game Mode

/// Represents the current game mode.
/// Used to branch behavior between single-player and multiplayer throughout the codebase.
enum GameMode: Equatable, Codable {
    /// Classic solo gameplay — no network sync required.
    case singlePlayer
    
    /// Real-time multiplayer match with other players.
    /// - Parameters:
    ///   - matchId: Unique identifier for this match session (from Game Center).
    ///   - localPlayerId: The local player's Game Center ID.
    ///   - players: Summary of all players in the match.
    case multiplayer(matchId: String, localPlayerId: String, players: [MultiplayerPlayerSummary])
    
    /// Convenience check for multiplayer mode.
    var isMultiplayer: Bool {
        if case .multiplayer = self { return true }
        return false
    }
    
    /// Returns the match ID if in multiplayer mode, nil otherwise.
    var matchId: String? {
        if case .multiplayer(let id, _, _) = self { return id }
        return nil
    }
    
    /// Returns the local player ID if in multiplayer mode, nil otherwise.
    var localPlayerId: String? {
        if case .multiplayer(_, let localId, _) = self { return localId }
        return nil
    }
}

// MARK: - Multiplayer Queue + Lobby

/// Describes how the player entered matchmaking.
enum MultiplayerQueue: String, Codable {
    case quickMatch
    case friends
    
    var displayName: String {
        switch self {
        case .quickMatch: return "Quick Match"
        case .friends: return "Friends"
        }
    }
}

/// Tracks lobby state before the actual match begins.
struct MultiplayerLobbyState: Equatable {
    /// The absolute timestamp when the match should begin.
    let startTime: TimeInterval
    
    /// Minimum players required before starting (used with countdown safeguard).
    let minPlayers: Int
    
    /// Maximum players allowed in the lobby.
    let maxPlayers: Int
    
    /// Remaining seconds until the host-started countdown hits zero.
    var remaining: TimeInterval
    
    /// Updates the countdown while clamping to zero.
    func updatingRemaining(now: TimeInterval) -> MultiplayerLobbyState {
        let newRemaining = max(0, startTime - now)
        return MultiplayerLobbyState(startTime: startTime,
                                     minPlayers: minPlayers,
                                     maxPlayers: maxPlayers,
                                     remaining: newRemaining)
    }
}

// MARK: - Multiplayer Player Summary

/// Lightweight summary of a player in a multiplayer match.
/// Used in `GameMode.multiplayer` to identify participants.
struct MultiplayerPlayerSummary: Identifiable, Equatable, Codable {
    /// Unique player identifier (Game Center player ID or similar).
    let id: String
    
    /// Human-readable display name.
    let displayName: String
    
    /// True if this player is the local device's player.
    let isLocal: Bool
    
    init(id: String, displayName: String, isLocal: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isLocal = isLocal
    }
}

// MARK: - Player Ranking

/// Represents a player's final ranking after a match ends.
struct PlayerRanking: Identifiable, Equatable {
    let id: String
    let displayName: String
    let finalScore: Double
    let rank: Int
    let isLocal: Bool
    let survivalTime: TimeInterval?
}

// MARK: - Multiplayer Player (Detailed State)

/// Detailed per-player state used during an active multiplayer match.
/// Tracks position, score, and elimination status for rendering and sync.
struct MultiplayerPlayer: Identifiable, Codable, Equatable {
    /// Unique player identifier (same as in `MultiplayerPlayerSummary`).
    let id: String
    
    /// Human-readable display name.
    let name: String
    
    /// True if this player is on the local device.
    let isLocal: Bool
    
    /// Whether the player is still alive in the current match.
    var isAlive: Bool
    
    /// Current horizontal position in the arena (normalized or in points).
    var currentX: CGFloat
    
    /// Current horizontal velocity — used for smoothing remote player animations.
    var velocityX: CGFloat
    
    /// Real-time score reported from the player's device.
    /// Updated constantly for opponents so HUD reflects live progress.
    var currentScore: Double
    
    /// Final score if the player has been eliminated or the match ended.
    var finalScore: Double?
    
    /// Timestamp when the player was eliminated (seconds since match start), nil if still alive.
    var eliminationTime: TimeInterval?
    
    init(
        id: String,
        name: String,
        isLocal: Bool,
        isAlive: Bool = true,
        currentX: CGFloat = 0,
        velocityX: CGFloat = 0,
        currentScore: Double = 0,
        finalScore: Double? = nil,
        eliminationTime: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
        self.isAlive = isAlive
        self.currentX = currentX
        self.velocityX = velocityX
        self.currentScore = currentScore
        self.finalScore = finalScore
        self.eliminationTime = eliminationTime
    }
}

// MARK: - Multiplayer State (Observable)

/// Observable in-memory state for an active multiplayer match.
/// Published properties allow SwiftUI views and GameScene to react to changes.
final class MultiplayerState: ObservableObject {
    /// All players in the current match with their detailed state.
    @Published var players: [MultiplayerPlayer]
    
    /// Whether a match is currently in progress.
    @Published var isMatchActive: Bool
    
    /// The winning player once the match concludes, nil if match is ongoing or no winner yet.
    @Published var winner: MultiplayerPlayer?
    
    /// Shared RNG seed for deterministic arena events (obstacles, power-ups).
    @Published var matchSeed: UInt64?
    
    // MARK: - Slow-Motion State (for HUD display)
    
    /// Whether a multiplayer slow-motion effect is currently active.
    @Published var isSlowMotionActive: Bool = false
    
    /// Whether the local player is the one who collected the slow-motion power-up.
    /// True = local player moves at normal speed, others slowed.
    /// False = local player is slowed, collector moves at normal speed.
    @Published var isLocalPlayerSlowMotionCollector: Bool = false
    
    /// Remaining duration of the slow-motion effect in seconds.
    @Published var slowMotionRemaining: TimeInterval = 0
    
    /// Player rankings after match ends, sorted by score descending.
    @Published var finalRankings: [PlayerRanking] = []
    
    /// How the user queued into multiplayer.
    @Published var currentQueue: MultiplayerQueue?
    
    /// True while we are actively searching for a match.
    @Published var isSearching: Bool = false
    
    /// Active lobby countdown/limits before the match begins.
    @Published var lobbyState: MultiplayerLobbyState?

    init(
        players: [MultiplayerPlayer] = [],
        isMatchActive: Bool = false,
        winner: MultiplayerPlayer? = nil,
        matchSeed: UInt64? = nil
    ) {
        self.players = players
        self.isMatchActive = isMatchActive
        self.winner = winner
        self.matchSeed = matchSeed
    }
    
    // MARK: - Slow-Motion Updates
    
    /// Activates slow-motion effect for HUD display.
    /// - Parameters:
    ///   - isLocalCollector: True if local player collected the power-up.
    ///   - duration: Total duration of the effect.
    func activateSlowMotion(isLocalCollector: Bool, duration: TimeInterval) {
        isSlowMotionActive = true
        isLocalPlayerSlowMotionCollector = isLocalCollector
        slowMotionRemaining = duration
    }
    
    /// Updates the remaining slow-motion duration.
    func updateSlowMotionRemaining(_ remaining: TimeInterval) {
        slowMotionRemaining = max(0, remaining)
        if slowMotionRemaining <= 0 {
            isSlowMotionActive = false
        }
    }
    
    /// Deactivates slow-motion effect.
    func deactivateSlowMotion() {
        isSlowMotionActive = false
        slowMotionRemaining = 0
    }
    
    // MARK: - Convenience Accessors
    
    /// Returns the local player if present.
    var localPlayer: MultiplayerPlayer? {
        players.first { $0.isLocal }
    }
    
    /// Returns all remote (non-local) players.
    var remotePlayers: [MultiplayerPlayer] {
        players.filter { !$0.isLocal }
    }
    
    /// Returns all players still alive.
    var alivePlayers: [MultiplayerPlayer] {
        players.filter { $0.isAlive }
    }
    
    /// True if all players have been eliminated (match is over).
    var allPlayersEliminated: Bool {
        !players.isEmpty && players.allSatisfy { !$0.isAlive }
    }
    
    /// True if exactly one player remains alive.
    var hasWinner: Bool {
        alivePlayers.count == 1
    }
    
    // MARK: - State Updates
    
    /// Update a specific player's position, velocity, live score, and alive status.
    func updatePlayerState(playerId: String, x: CGFloat, velocityX: CGFloat, score: Double, isAlive: Bool) {
        guard let index = players.firstIndex(where: { $0.id == playerId }) else { return }
        players[index].currentX = x
        players[index].velocityX = velocityX
        players[index].currentScore = score
        players[index].isAlive = isAlive
    }
    
    /// Mark a player as eliminated with their final score and elimination time.
    func eliminatePlayer(playerId: String, finalScore: Double, eliminationTime: TimeInterval) {
        guard let index = players.firstIndex(where: { $0.id == playerId }) else { return }
        players[index].isAlive = false
        players[index].finalScore = finalScore
        players[index].eliminationTime = eliminationTime
        
        // Check for winner after elimination
        if hasWinner, let lastStanding = alivePlayers.first {
            winner = lastStanding
        }
    }
    
    /// Reset state for a new match.
    func reset() {
        players = []
        isMatchActive = false
        winner = nil
        matchSeed = nil
        isSlowMotionActive = false
        isLocalPlayerSlowMotionCollector = false
        slowMotionRemaining = 0
        finalRankings = []
        currentQueue = nil
        isSearching = false
        lobbyState = nil
    }
    
    /// Sets final rankings after match end.
    func setFinalRankings(_ rankings: [PlayerRanking]) {
        finalRankings = rankings
    }
    
    /// Mark that matchmaking has begun for the given queue.
    func beginSearching(queue: MultiplayerQueue) {
        currentQueue = queue
        isSearching = true
        lobbyState = nil
    }
    
    /// Stop showing a searching state (on success or cancel).
    func endSearching() {
        isSearching = false
    }
    
    /// Activate the lobby countdown once players are known.
    func beginLobby(startTime: TimeInterval, minPlayers: Int, maxPlayers: Int) {
        lobbyState = MultiplayerLobbyState(startTime: startTime,
                                           minPlayers: minPlayers,
                                           maxPlayers: maxPlayers,
                                           remaining: max(0, startTime - Date().timeIntervalSince1970))
        isSearching = false
    }
    
    /// Update the lobby countdown based on the current time.
    func updateLobbyCountdown(now: TimeInterval = Date().timeIntervalSince1970) {
        guard let lobby = lobbyState else { return }
        lobbyState = lobby.updatingRemaining(now: now)
    }
    
    /// Clear lobby state when the live match begins.
    func clearLobby() {
        lobbyState = nil
    }
}
