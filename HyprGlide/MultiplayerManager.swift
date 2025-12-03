//
//  MultiplayerManager.swift
//  HyprGlide
//
//  Responsible for all Game Center real-time match handling and high-level
//  multiplayer orchestration. Does NOT contain SpriteKit rendering code.
//
//  Key Responsibilities:
//  - GameKit match lifecycle (GKMatch, GKMatchmaker, GKMatchDelegate)
//  - Networking: encode/decode multiplayer messages
//  - Coordinate between GameCenter and local state (GameState, MultiplayerState, GameScene hooks)
//

import Foundation
import GameKit
import Combine
import UIKit

// MARK: - Multiplayer Message Protocol

/// Identifies the type of multiplayer message for decoding.
enum MultiplayerMessageType: Int, Codable {
    case matchSetup = 0
    case playerStateUpdate = 1
    case obstacleSpawn = 2
    case powerUpSpawn = 3
    case playerDied = 4
    case matchEnd = 5
    case powerUpCollected = 6
    case slowMotionActivated = 7
    case rematchRequest = 8
}

/// Wrapper for all multiplayer messages. The `type` field determines how to decode `payload`.
struct MultiplayerMessage: Codable {
    let type: MultiplayerMessageType
    let payload: Data
    let senderId: String
    let timestamp: TimeInterval
    
    init(type: MultiplayerMessageType, payload: Data, senderId: String) {
        self.type = type
        self.payload = payload
        self.senderId = senderId
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Message Payloads

/// Sent by host at match start to synchronize all players.
struct MatchSetupPayload: Codable {
    let hostId: String
    let arenaSeed: UInt64
    let matchStartTime: TimeInterval
    let players: [MultiplayerPlayerSummary]
    let matchId: String
    let minPlayers: Int
    let maxPlayers: Int
    /// True when this setup was triggered from a rematch opt-in flow.
    let isRematch: Bool?
}

/// Sent frequently by each player to sync position and score.
struct PlayerStateUpdatePayload: Codable {
    let playerId: String
    let positionX: CGFloat
    let velocityX: CGFloat
    let score: Double
    let isAlive: Bool
    let timestamp: TimeInterval
}

/// Sent by host when spawning an obstacle.
struct ObstacleSpawnPayload: Codable {
    let event: ObstacleSpawnEvent
    let spawnIndex: Int
}

/// Sent by host when spawning a power-up.
struct PowerUpSpawnPayload: Codable {
    let event: PowerUpSpawnEvent
    let spawnIndex: Int
    let powerUpId: String  // Unique ID for exclusivity tracking
}

/// Sent when a player dies.
struct PlayerDiedPayload: Codable {
    let playerId: String
    let finalScore: Double
    let eliminationTime: TimeInterval
}

/// Sent by host when match concludes.
struct MatchEndPayload: Codable {
    /// Ordered list of players by final score (descending).
    let rankedPlayers: [PlayerRanking]
    /// The highest-scoring player (winner).
    let winnerId: String
    
    struct PlayerRanking: Codable {
        let playerId: String
        let displayName: String
        let finalScore: Double
        let rank: Int
    }
}

/// Sent when a player collects a power-up (for exclusivity).
struct PowerUpCollectedPayload: Codable {
    let powerUpId: String
    let collectorId: String
    let collectionTime: TimeInterval
}

/// Sent when slow-motion is activated by any player.
struct SlowMotionActivatedPayload: Codable {
    let collectorId: String
    let duration: TimeInterval
    let stackedDuration: TimeInterval  // Total remaining after stacking
    let activationTime: TimeInterval
}

/// Sent by non-host players to ask the host to start a rematch.
struct RematchRequestPayload: Codable {
    let requesterId: String
    let requestedAt: TimeInterval
}

// MARK: - Scene Delegate Protocol

/// Protocol for GameScene to receive multiplayer events from MultiplayerManager.
/// Avoids direct SpriteKit dependencies in the manager.
protocol MultiplayerSceneDelegate: AnyObject {
    /// Configure scene for multiplayer with shared seed.
    func configureForMultiplayer(seed: UInt64, startTime: TimeInterval)
    
    /// Process an obstacle spawn event from the host.
    func processExternalObstacleEvent(_ event: ObstacleSpawnEvent)
    
    /// Process a power-up spawn event from the host.
    func processExternalPowerUpEvent(_ event: PowerUpSpawnEvent, powerUpId: String)
    
    /// Update a remote player's position.
    func updateRemotePlayerPosition(playerId: String, x: CGFloat, velocityX: CGFloat)
    
    /// Mark a power-up as collected (remove from scene).
    func markPowerUpCollected(powerUpId: String)
    
    /// Apply slow-motion effect where the collector keeps normal speed, others slow down.
    func applyMultiplayerSlowMotion(collectorId: String, duration: TimeInterval, isLocalPlayerCollector: Bool)
    
    /// Mark a remote player as eliminated for scene presentation (fade out, etc.).
    func markRemotePlayerDead(playerId: String)
    
    /// Clean up any multiplayer-specific state and visuals when leaving a match.
    func cleanupMultiplayerArena()
    
    /// Get the current player X position for state updates.
    var localPlayerPositionX: CGFloat { get }
    
    /// Get the current player X velocity for state updates.
    var localPlayerVelocityX: CGFloat { get }
    
    /// Configure the full multiplayer arena with players and synchronized start time.
    func configureMultiplayerArena(
        players: [MultiplayerPlayerSummary],
        localPlayerId: String,
        seed: UInt64,
        startTime: TimeInterval,
        manager: MultiplayerManager
    )
}

// MARK: - MultiplayerManager

/// Central manager for Game Center real-time multiplayer.
/// Handles matchmaking, message routing, host election, and synchronization.
final class MultiplayerManager: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    /// Current connection status for UI display.
    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected
    
    /// Whether we are currently searching for a match.
    @Published private(set) var isMatchmaking: Bool = false
    
    /// Error message if something went wrong.
    @Published private(set) var lastError: String?
    
    /// Status enumeration for connection state.
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case matchInProgress
    }
    
    /// Lobby warmup duration before obstacles spawn.
    private let lobbyWarmupDuration: TimeInterval = 8
    private let fullLobbyFastStartDuration: TimeInterval = 3
    
    /// Minimum/maximum supported players per match (mirrors GKMatchRequest).
    private let minPlayersPerMatch = 2
    private let maxPlayersPerMatch = 4
    
    // MARK: - Dependencies (Weak References)
    
    /// Game state reference for mode and score updates.
    weak var gameState: GameState?
    
    /// Multiplayer state for player tracking.
    weak var multiplayerState: MultiplayerState?
    
    /// Scene delegate for pushing events to GameScene.
    weak var sceneDelegate: MultiplayerSceneDelegate?
    
    // MARK: - Match State
    
    /// The active Game Center match.
    private var currentMatch: GKMatch?
    
    /// The local player's Game Center ID.
    private var localPlayerId: String {
        GKLocalPlayer.local.gamePlayerID
    }
    
    /// Whether this device is the match host.
    private(set) var isHost: Bool = false
    
    /// The host's player ID.
    private var hostId: String?
    
    /// Shared seed for deterministic arena generation.
    private var arenaSeed: UInt64?
    
    /// Match start time (absolute timestamp).
    private var matchStartTime: TimeInterval?
    
    /// Timer for sending player state updates.
    private var stateUpdateTimer: Timer?
    
    /// Frequency of player state updates (Hz).
    private let stateUpdateFrequency: TimeInterval = 1.0 / 15.0  // 15 Hz
    
    /// Tracks which power-ups have been collected (for exclusivity).
    private var collectedPowerUpIds: Set<String> = []
    
    /// Tracks alive players for host to determine match end.
    private var alivePlayerIds: Set<String> = []
    
    /// Arena randomizer for host-generated spawn events.
    private var arenaRandomizer: ArenaRandomizer?
    
    /// Player IDs that have explicitly opted into a rematch after the last round.
    private var rematchOptInPlayerIds: Set<String> = []
    
    /// Whether the local player has opted into the next rematch.
    private var localRequestedRematch: Bool = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Public API: Matchmaking
    
    /// Convenience to start a quick match using the top-most presenter.
    func startQuickMatch() {
        guard let presenter = resolvePresenter() else {
            lastError = "Unable to start matchmaking: no active window."
            return
        }
        startQuickMatch(from: presenter)
    }
    
    /// Convenience to start a friends-focused lobby using invites.
    func startFriendsMatch() {
        guard let presenter = resolvePresenter() else {
            lastError = "Unable to start matchmaking: no active window."
            return
        }
        startFriendsMatch(from: presenter)
    }
    
    /// Starts a quick match with 2-4 players.
    /// - Parameter viewController: The presenting view controller for Game Center UI.
    func startQuickMatch(from viewController: UIViewController) {
        // Ensure Game Center is authenticated first.
        guard GameCenterManager.shared.isAuthenticated else {
            GameCenterManager.shared.authenticateIfNeeded(presentingFrom: viewController)
            // Wait a moment and retry, or let caller handle re-attempt.
            lastError = "Please sign in to Game Center first."
            return
        }
        
        multiplayerState?.beginSearching(queue: .quickMatch)
        isMatchmaking = true
        connectionStatus = .connecting
        lastError = nil
        
        // Configure match request for 2-4 players.
        let request = GKMatchRequest()
        request.minPlayers = minPlayersPerMatch
        request.maxPlayers = maxPlayersPerMatch
        request.inviteMessage = "Join my HyprGlide match!"
        
        // Use the matchmaker view controller for user-friendly matchmaking UI.
        guard let matchmakerVC = GKMatchmakerViewController(matchRequest: request) else {
            lastError = "Failed to create matchmaker."
            isMatchmaking = false
            connectionStatus = .disconnected
            multiplayerState?.endSearching()
            return
        }
        
        matchmakerVC.matchmakerDelegate = self
        viewController.present(matchmakerVC, animated: true)
    }
    
    /// Starts a friends lobby where the user can invite people directly.
    func startFriendsMatch(from viewController: UIViewController) {
        guard GameCenterManager.shared.isAuthenticated else {
            GameCenterManager.shared.authenticateIfNeeded(presentingFrom: viewController)
            lastError = "Please sign in to Game Center first."
            return
        }
        
        multiplayerState?.beginSearching(queue: .friends)
        isMatchmaking = true
        connectionStatus = .connecting
        lastError = nil
        
        let request = GKMatchRequest()
        request.minPlayers = minPlayersPerMatch
        request.maxPlayers = maxPlayersPerMatch
        request.inviteMessage = "Play HyprGlide with me!"
        
        guard let matchmakerVC = GKMatchmakerViewController(matchRequest: request) else {
            lastError = "Failed to create matchmaker."
            isMatchmaking = false
            connectionStatus = .disconnected
            multiplayerState?.endSearching()
            return
        }
        
        matchmakerVC.matchmakerDelegate = self
        viewController.present(matchmakerVC, animated: true)
    }
    
    /// Cancels any in-progress matchmaking.
    func cancelMatchmaking() {
        GKMatchmaker.shared().cancel()
        multiplayerState?.endSearching()
        isMatchmaking = false
        connectionStatus = .disconnected
    }
    
    /// Disconnects from the current match.
    func disconnect() {
        stopStateUpdateTimer()
        currentMatch?.disconnect()
        currentMatch = nil
        
        // Ensure the scene clears any lingering remote player nodes when leaving a match.
        DispatchQueue.main.async { [weak self] in
            self?.sceneDelegate?.cleanupMultiplayerArena()
        }
        
        resetMatchState()
        connectionStatus = .disconnected
    }
    
    // MARK: - Public API: Rematch
    
    /// Requests a new match using the existing Game Center connection.
    /// Hosts immediately schedule a new lobby; non-hosts ask the host to start one.
    func requestRematch() {
        guard let match = currentMatch else {
            lastError = "Rematch unavailable: not connected to a match."
            return
        }
        
        // Don't interrupt an active round.
        guard multiplayerState?.isMatchActive == false else { return }
        
        localRequestedRematch = true
        
        if isHost {
            recordRematchOptIn(playerId: localPlayerId)
        } else {
            let payload = RematchRequestPayload(
                requesterId: localPlayerId,
                requestedAt: Date().timeIntervalSince1970
            )
            sendMessage(type: .rematchRequest, payload: payload, mode: .reliable)
        }
    }
    
    // MARK: - Public API: Game Events (called by GameScene)
    
    /// Called by GameScene when the local player dies.
    /// - Parameters:
    ///   - finalScore: The player's final score.
    ///   - eliminationTime: Time since match start when eliminated.
    func localPlayerDied(finalScore: Double, eliminationTime: TimeInterval) {
        guard currentMatch != nil else { return }
        
        let payload = PlayerDiedPayload(
            playerId: localPlayerId,
            finalScore: finalScore,
            eliminationTime: eliminationTime
        )
        
        sendMessage(type: .playerDied, payload: payload, mode: .reliable)
        
        // Update local state.
        multiplayerState?.eliminatePlayer(
            playerId: localPlayerId,
            finalScore: finalScore,
            eliminationTime: eliminationTime
        )
        
        // Host tracks alive players and determines match end.
        if isHost {
            alivePlayerIds.remove(localPlayerId)
            checkForMatchEnd()
        }
    }
    
    /// Called by GameScene when the local player collects a power-up.
    /// Returns true if this player is the authoritative collector, false if someone else got it first.
    /// - Parameters:
    ///   - powerUpId: Unique identifier for the power-up.
    ///   - type: The type of power-up collected.
    /// - Returns: True if collection is authorized.
    func tryCollectPowerUp(powerUpId: String, type: PowerUpType) -> Bool {
        // Check if already collected.
        if collectedPowerUpIds.contains(powerUpId) {
            return false
        }
        
        // Mark as collected locally.
        collectedPowerUpIds.insert(powerUpId)
        
        // Broadcast collection to all peers.
        let payload = PowerUpCollectedPayload(
            powerUpId: powerUpId,
            collectorId: localPlayerId,
            collectionTime: elapsedMatchTime
        )
        sendMessage(type: .powerUpCollected, payload: payload, mode: .reliable)
        
        return true
    }
    
    /// Called by GameScene when slow-motion power-up is activated locally.
    /// - Parameters:
    ///   - duration: Base duration of the effect.
    ///   - stackedDuration: Total duration after stacking.
    func localPlayerActivatedSlowMotion(duration: TimeInterval, stackedDuration: TimeInterval) {
        let payload = SlowMotionActivatedPayload(
            collectorId: localPlayerId,
            duration: duration,
            stackedDuration: stackedDuration,
            activationTime: elapsedMatchTime
        )
        
        // Update MultiplayerState for HUD display (local player is collector)
        multiplayerState?.activateSlowMotion(isLocalCollector: true, duration: stackedDuration)
        
        sendMessage(type: .slowMotionActivated, payload: payload, mode: .reliable)
    }
    
    /// Immediately send a player state update and ensure the heartbeat timer is running.
    /// Helps other clients recover quickly after this player pauses/resumes.
    func sendImmediatePlayerStateUpdate() {
        guard currentMatch != nil,
              multiplayerState?.isMatchActive == true else { return }
        
        if stateUpdateTimer == nil {
            startStateUpdateTimer()
        }
        
        sendPlayerStateUpdate()
    }
    
    // MARK: - Public API: Host Spawning
    
    /// Called by GameScene (on host) to broadcast an obstacle spawn event.
    func broadcastObstacleSpawn(_ event: ObstacleSpawnEvent, spawnIndex: Int) {
        guard isHost else { return }
        
        let payload = ObstacleSpawnPayload(event: event, spawnIndex: spawnIndex)
        sendMessage(type: .obstacleSpawn, payload: payload, mode: .reliable)
    }
    
    /// Called by GameScene (on host) to broadcast a power-up spawn event.
    func broadcastPowerUpSpawn(_ event: PowerUpSpawnEvent, spawnIndex: Int, powerUpId: String) {
        guard isHost else { return }
        
        let payload = PowerUpSpawnPayload(event: event, spawnIndex: spawnIndex, powerUpId: powerUpId)
        sendMessage(type: .powerUpSpawn, payload: payload, mode: .reliable)
    }
    
    // MARK: - Private: Match Setup
    
    /// Called when a match is successfully established.
    private func handleMatchConnected(_ match: GKMatch) {
        currentMatch = match
        match.delegate = self
        
        connectionStatus = .connected
        isMatchmaking = false
        multiplayerState?.endSearching()
        
        // Elect host (lexicographically smallest player ID).
        electHost(match: match)
        
        // If we are the host, generate seed and broadcast match setup.
        if isHost {
            performHostSetup(match: match)
        }
        // Otherwise, wait for MatchSetup message from host.
    }
    
    /// Elects the host deterministically using lexicographic comparison of player IDs.
    private func electHost(match: GKMatch) {
        var allPlayerIds = [localPlayerId]
        for player in match.players {
            allPlayerIds.append(player.gamePlayerID)
        }
        allPlayerIds.sort()
        
        hostId = allPlayerIds.first
        isHost = (hostId == localPlayerId)
        
        print("[MultiplayerManager] Host elected: \(hostId ?? "none"), isLocal: \(isHost)")
    }
    
    /// Starts a fresh lobby using the existing connected players who opted in.
    private func startRematch(match: GKMatch) {
        // Require the host to opt in.
        guard rematchOptInPlayerIds.contains(localPlayerId) else {
            return
        }
        
        // Only include players who opted in and are still part of the match.
        let participantIds: [String] = rematchOptInPlayerIds.filter { id in
            id == localPlayerId || match.players.contains(where: { $0.gamePlayerID == id })
        }.sorted()
        
        guard participantIds.count >= minPlayersPerMatch else {
            lastError = "Need at least \(minPlayersPerMatch) players for a rematch."
            return
        }
        
        // Clear round-specific state so the new lobby is clean.
        collectedPowerUpIds.removeAll()
        multiplayerState?.winner = nil
        multiplayerState?.setFinalRankings([])
        multiplayerState?.deactivateSlowMotion()
        
        // Build player summaries using the previous state for names where possible.
        let summaries = buildPlayerSummaries(for: participantIds, match: match)
        
        performHostSetup(match: match, playersOverride: summaries, isRematch: true)
    }
    
    /// Host generates seed, match start time, and broadcasts MatchSetup to all peers.
    private func performHostSetup(match: GKMatch,
                                  playersOverride: [MultiplayerPlayerSummary]? = nil,
                                  isRematch: Bool = false) {
        // Generate deterministic seed.
        let seed = UInt64.random(in: 0...UInt64.max)
        arenaSeed = seed
        
        // Build player list.
        var players: [MultiplayerPlayerSummary]
        if let override = playersOverride {
            players = override
        } else {
            players = []
            players.append(MultiplayerPlayerSummary(
                id: localPlayerId,
                displayName: GKLocalPlayer.local.displayName,
                isLocal: true
            ))
            for player in match.players {
                players.append(MultiplayerPlayerSummary(
                    id: player.gamePlayerID,
                    displayName: player.displayName,
                    isLocal: false
                ))
            }
        }
        
        // Track alive players.
        alivePlayerIds = Set(players.map { $0.id })
        
        // Schedule match start to give players a warmup lobby.
        let warmupDuration = players.count >= maxPlayersPerMatch ? fullLobbyFastStartDuration : lobbyWarmupDuration
        let startTime = Date().timeIntervalSince1970 + warmupDuration
        matchStartTime = startTime
        
        // Create and broadcast setup payload.
        let matchId = UUID().uuidString
        let payload = MatchSetupPayload(
            hostId: localPlayerId,
            arenaSeed: seed,
            matchStartTime: startTime,
            players: players,
            matchId: matchId,
            minPlayers: minPlayersPerMatch,
            maxPlayers: maxPlayersPerMatch,
            isRematch: isRematch
        )
        
        sendMessage(type: .matchSetup, payload: payload, mode: .reliable)
        
        // Apply setup locally as well.
        applyMatchSetup(payload)
        
        // Reset rematch opt-ins now that the new round is scheduled.
        rematchOptInPlayerIds.removeAll()
        localRequestedRematch = false
    }
    
    /// Applies the match setup configuration locally.
    private func applyMatchSetup(_ setup: MatchSetupPayload) {
        let isRematch = setup.isRematch ?? false
        // Only auto-join rematches if the local player explicitly opted in.
        if isRematch && !localRequestedRematch {
            print("[MultiplayerManager] Ignoring rematch setup because local player did not opt in.")
            return
        }
        
        // Clear rematch intent once we're committing to the new match.
        localRequestedRematch = false
        rematchOptInPlayerIds.removeAll()
        
        arenaSeed = setup.arenaSeed
        matchStartTime = setup.matchStartTime
        hostId = setup.hostId
        isHost = (setup.hostId == localPlayerId)
        collectedPowerUpIds.removeAll()
        multiplayerState?.winner = nil
        multiplayerState?.setFinalRankings([])
        multiplayerState?.deactivateSlowMotion()
        
        // Track alive players.
        alivePlayerIds = Set(setup.players.map { $0.id })
        
        // Update GameState mode.
        gameState?.mode = .multiplayer(
            matchId: setup.matchId,
            localPlayerId: localPlayerId,
            players: setup.players
        )
        
        if let scene = sceneDelegate as? GameScene, let gs = gameState {
            scene.resetGame(state: gs)
            gs.startGame()
        } else {
            gameState?.resetGame()
            gameState?.startGame()
        }
        
        // Initialize MultiplayerState with players.
        let mpPlayers = setup.players.map { summary in
            MultiplayerPlayer(
                id: summary.id,
                name: summary.displayName,
                isLocal: summary.id == localPlayerId
            )
        }
        multiplayerState?.players = mpPlayers
        multiplayerState?.isMatchActive = true
        multiplayerState?.matchSeed = setup.arenaSeed
        multiplayerState?.beginLobby(startTime: setup.matchStartTime,
                                     minPlayers: setup.minPlayers,
                                     maxPlayers: setup.maxPlayers)
        
        // Configure GameScene for multiplayer.
        sceneDelegate?.configureMultiplayerArena(
            players: setup.players,
            localPlayerId: localPlayerId,
            seed: setup.arenaSeed,
            startTime: setup.matchStartTime,
            manager: self
        )
        
        // Start state update timer.
        startStateUpdateTimer()
        
        connectionStatus = .matchInProgress
        
        print("[MultiplayerManager] Match setup applied. Seed: \(setup.arenaSeed), Host: \(setup.hostId)")
    }
    
    // MARK: - Private: State Updates
    
    /// Starts the timer for sending periodic player state updates.
    private func startStateUpdateTimer() {
        stopStateUpdateTimer()
        
        stateUpdateTimer = Timer.scheduledTimer(withTimeInterval: stateUpdateFrequency, repeats: true) { [weak self] _ in
            self?.sendPlayerStateUpdate()
        }
    }
    
    /// Stops the state update timer.
    private func stopStateUpdateTimer() {
        stateUpdateTimer?.invalidate()
        stateUpdateTimer = nil
    }
    
    /// Sends the local player's current state to all peers.
    private func sendPlayerStateUpdate() {
        guard let sceneDelegate = sceneDelegate,
              let gameState = gameState,
              !gameState.isGameOver else { return }
        
        let payload = PlayerStateUpdatePayload(
            playerId: localPlayerId,
            positionX: sceneDelegate.localPlayerPositionX,
            velocityX: sceneDelegate.localPlayerVelocityX,
            score: gameState.score,
            isAlive: !gameState.isGameOver,
            timestamp: elapsedMatchTime
        )
        
        // Use unreliable mode for high-frequency updates (acceptable to drop some).
        sendMessage(type: .playerStateUpdate, payload: payload, mode: .unreliable)
    }
    
    /// Elapsed time since match start.
    private var elapsedMatchTime: TimeInterval {
        guard let startTime = matchStartTime else { return 0 }
        return max(0, Date().timeIntervalSince1970 - startTime)
    }
    
    // MARK: - Private: Message Handling
    
    /// Handles an incoming message from a remote player.
    private func handleIncomingMessage(_ message: MultiplayerMessage, from sender: GKPlayer) {
        switch message.type {
        case .matchSetup:
            handleMatchSetupMessage(message)
            
        case .playerStateUpdate:
            handlePlayerStateUpdateMessage(message)
            
        case .obstacleSpawn:
            handleObstacleSpawnMessage(message)
            
        case .powerUpSpawn:
            handlePowerUpSpawnMessage(message)
            
        case .playerDied:
            handlePlayerDiedMessage(message)
            
        case .matchEnd:
            handleMatchEndMessage(message)
            
        case .powerUpCollected:
            handlePowerUpCollectedMessage(message)
            
        case .slowMotionActivated:
            handleSlowMotionActivatedMessage(message)
            
        case .rematchRequest:
            handleRematchRequestMessage(message)
        }
    }
    
    private func handleMatchSetupMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(MatchSetupPayload.self, from: message.payload) else {
            print("[MultiplayerManager] Failed to decode MatchSetup payload.")
            return
        }
        
        applyMatchSetup(payload)
    }
    
    private func handlePlayerStateUpdateMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(PlayerStateUpdatePayload.self, from: message.payload) else {
            return
        }
        
        // Update MultiplayerState.
        multiplayerState?.updatePlayerState(
            playerId: payload.playerId,
            x: payload.positionX,
            velocityX: payload.velocityX,
            score: payload.score,
            isAlive: payload.isAlive
        )
        
        // Notify scene to update remote player node.
        sceneDelegate?.updateRemotePlayerPosition(
            playerId: payload.playerId,
            x: payload.positionX,
            velocityX: payload.velocityX
        )
    }
    
    private func handleObstacleSpawnMessage(_ message: MultiplayerMessage) {
        // Only non-hosts process external obstacle events.
        guard !isHost else { return }
        
        guard let payload = try? JSONDecoder().decode(ObstacleSpawnPayload.self, from: message.payload) else {
            return
        }
        
        sceneDelegate?.processExternalObstacleEvent(payload.event)
    }
    
    private func handlePowerUpSpawnMessage(_ message: MultiplayerMessage) {
        // Only non-hosts process external power-up events.
        guard !isHost else { return }
        
        guard let payload = try? JSONDecoder().decode(PowerUpSpawnPayload.self, from: message.payload) else {
            return
        }
        
        sceneDelegate?.processExternalPowerUpEvent(payload.event, powerUpId: payload.powerUpId)
    }
    
    private func handlePlayerDiedMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(PlayerDiedPayload.self, from: message.payload) else {
            return
        }
        
        // Update multiplayer state.
        multiplayerState?.eliminatePlayer(
            playerId: payload.playerId,
            finalScore: payload.finalScore,
            eliminationTime: payload.eliminationTime
        )
        
        // Update scene visuals for eliminated remote players.
        if payload.playerId != localPlayerId {
            sceneDelegate?.markRemotePlayerDead(playerId: payload.playerId)
        }
        
        // Host tracks alive players.
        if isHost {
            alivePlayerIds.remove(payload.playerId)
            checkForMatchEnd()
        }
    }
    
    private func handleMatchEndMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(MatchEndPayload.self, from: message.payload) else {
            return
        }
        
        applyMatchEnd(payload)
    }
    
    private func handlePowerUpCollectedMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(PowerUpCollectedPayload.self, from: message.payload) else {
            return
        }
        
        // Mark power-up as collected.
        collectedPowerUpIds.insert(payload.powerUpId)
        
        // Notify scene to remove the power-up if it hasn't been collected locally.
        if payload.collectorId != localPlayerId {
            sceneDelegate?.markPowerUpCollected(powerUpId: payload.powerUpId)
        }
    }
    
    private func handleSlowMotionActivatedMessage(_ message: MultiplayerMessage) {
        guard let payload = try? JSONDecoder().decode(SlowMotionActivatedPayload.self, from: message.payload) else {
            return
        }
        
        // Apply slow-motion effect: collector keeps normal speed, others slow down.
        let isLocalCollector = (payload.collectorId == localPlayerId)
        
        // Update MultiplayerState for HUD display
        multiplayerState?.activateSlowMotion(isLocalCollector: isLocalCollector, duration: payload.stackedDuration)
        
        sceneDelegate?.applyMultiplayerSlowMotion(
            collectorId: payload.collectorId,
            duration: payload.stackedDuration,
            isLocalPlayerCollector: isLocalCollector
        )
    }
    
    private func handleRematchRequestMessage(_ message: MultiplayerMessage) {
        guard isHost else { return }
        guard let match = currentMatch else { return }
        
        guard let payload = try? JSONDecoder().decode(RematchRequestPayload.self, from: message.payload) else {
            return
        }
        
        // Only restart after a completed round.
        guard multiplayerState?.isMatchActive == false else { return }
        
        print("[MultiplayerManager] Rematch requested by \(payload.requesterId). Recording opt-in.")
        recordRematchOptIn(playerId: payload.requesterId)
    }
    
    /// Adds an opt-in to the rematch list and starts a new lobby when conditions are met.
    private func recordRematchOptIn(playerId: String) {
        rematchOptInPlayerIds.insert(playerId)
        
        guard isHost, let match = currentMatch else { return }
        guard rematchOptInPlayerIds.contains(localPlayerId) else { return }
        guard rematchOptInPlayerIds.count >= minPlayersPerMatch else { return }
        
        startRematch(match: match)
    }
    
    /// Builds player summaries for a given subset of participant IDs.
    private func buildPlayerSummaries(for participantIds: [String], match: GKMatch) -> [MultiplayerPlayerSummary] {
        var nameLookup: [String: String] = [:]
        if let players = multiplayerState?.players {
            for player in players {
                nameLookup[player.id] = player.name
            }
        }
        
        // Helper to resolve display name with fallbacks.
        func displayName(for id: String) -> String {
            if let name = nameLookup[id] { return name }
            if id == localPlayerId { return GKLocalPlayer.local.displayName }
            if let matchPlayer = match.players.first(where: { $0.gamePlayerID == id }) {
                return matchPlayer.displayName
            }
            return "Player"
        }
        
        return participantIds.map { id in
            MultiplayerPlayerSummary(
                id: id,
                displayName: displayName(for: id),
                isLocal: id == localPlayerId
            )
        }
    }
    
    // MARK: - Private: Match End Logic
    
    /// Host checks if only one player remains alive and ends the match.
    private func checkForMatchEnd() {
        guard isHost else { return }
        
        // Match ends when only one player (or zero) remains alive.
        guard alivePlayerIds.count <= 1 else { return }
        
        // Compute final rankings by score (not just survival).
        var rankings: [MatchEndPayload.PlayerRanking] = []
        
        if let mpState = multiplayerState {
            // Sort players by final score descending.
            let sortedPlayers = mpState.players.sorted { p1, p2 in
                let score1 = p1.finalScore ?? (p1.isAlive ? gameState?.score ?? 0 : 0)
                let score2 = p2.finalScore ?? (p2.isAlive ? gameState?.score ?? 0 : 0)
                return score1 > score2
            }
            
            for (index, player) in sortedPlayers.enumerated() {
                let score = player.finalScore ?? (player.isAlive ? gameState?.score ?? 0 : 0)
                rankings.append(MatchEndPayload.PlayerRanking(
                    playerId: player.id,
                    displayName: player.name,
                    finalScore: score,
                    rank: index + 1
                ))
            }
        }
        
        // Winner is the highest-scoring player.
        let winnerId = rankings.first?.playerId ?? ""
        
        let payload = MatchEndPayload(rankedPlayers: rankings, winnerId: winnerId)
        
        // Broadcast match end to all players.
        sendMessage(type: .matchEnd, payload: payload, mode: .reliable)
        
        // Apply locally.
        applyMatchEnd(payload)
    }
    
    /// Applies the match end state locally.
    private func applyMatchEnd(_ payload: MatchEndPayload) {
        stopStateUpdateTimer()
        localRequestedRematch = false
        rematchOptInPlayerIds.removeAll()
        
        guard let mpState = multiplayerState else { return }
        
        // Find the winner player.
        if let winnerPlayer = mpState.players.first(where: { $0.id == payload.winnerId }) {
            mpState.winner = winnerPlayer
        }
        
        // Convert rankings to UI-friendly format
        let rankings = payload.rankedPlayers.map { ranking in
            PlayerRanking(
                id: ranking.playerId,
                displayName: ranking.displayName,
                finalScore: ranking.finalScore,
                rank: ranking.rank,
                isLocal: ranking.playerId == localPlayerId,
                survivalTime: mpState.players.first(where: { $0.id == ranking.playerId })?.eliminationTime
            )
        }
        mpState.setFinalRankings(rankings)
        
        mpState.isMatchActive = false
        mpState.deactivateSlowMotion()  // Clear any active slow-motion
        connectionStatus = .connected  // Still connected, but match is over.
        
        // Stop the local gameplay loop so HUD can surface match results/rematch.
        gameState?.isGameOver = true
        gameState?.recordBest(for: .normal)
        
        print("[MultiplayerManager] Match ended. Winner: \(payload.winnerId)")
    }
    
    // MARK: - Private: Networking
    
    /// Encodes and sends a message to all players in the match.
    private func sendMessage<T: Codable>(type: MultiplayerMessageType, payload: T, mode: GKMatch.SendDataMode) {
        guard let match = currentMatch else { return }
        
        do {
            let payloadData = try JSONEncoder().encode(payload)
            let message = MultiplayerMessage(type: type, payload: payloadData, senderId: localPlayerId)
            let messageData = try JSONEncoder().encode(message)
            
            try match.sendData(toAllPlayers: messageData, with: mode)
        } catch {
            print("[MultiplayerManager] Failed to send message: \(error.localizedDescription)")
        }
    }
    
    /// Resets all match-related state.
    private func resetMatchState() {
        isHost = false
        hostId = nil
        arenaSeed = nil
        matchStartTime = nil
        collectedPowerUpIds.removeAll()
        alivePlayerIds.removeAll()
        arenaRandomizer = nil
        rematchOptInPlayerIds.removeAll()
        localRequestedRematch = false
        
        multiplayerState?.reset()
        gameState?.mode = .singlePlayer
    }
    
    /// Attempts to find the topmost presented view controller for presenting Game Center UI.
    private func resolvePresenter() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }
        
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - GKMatchmakerViewControllerDelegate

extension MultiplayerManager: GKMatchmakerViewControllerDelegate {
    
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
        isMatchmaking = false
        connectionStatus = .disconnected
        multiplayerState?.endSearching()
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        viewController.dismiss(animated: true)
        lastError = error.localizedDescription
        isMatchmaking = false
        connectionStatus = .disconnected
        multiplayerState?.endSearching()
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(animated: true)
        handleMatchConnected(match)
    }
}

// MARK: - GKMatchDelegate

extension MultiplayerManager: GKMatchDelegate {
    
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        do {
            let message = try JSONDecoder().decode(MultiplayerMessage.self, from: data)
            
            // Process on main thread for UI/state updates.
            DispatchQueue.main.async { [weak self] in
                self?.handleIncomingMessage(message, from: player)
            }
        } catch {
            print("[MultiplayerManager] Failed to decode message: \(error.localizedDescription)")
        }
    }
    
    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                print("[MultiplayerManager] Player connected: \(player.displayName)")
                // If all expected players are connected and we're host, initiate setup.
                if let self = self, self.isHost, match.expectedPlayerCount == 0 {
                    // All players connected—host should have already sent setup,
                    // but we can re-send if a late joiner needs it.
                }
                
            case .disconnected:
                print("[MultiplayerManager] Player disconnected: \(player.displayName)")
                // Handle gracefully: mark player as dead and continue.
                self?.handlePlayerDisconnect(player: player)
                
            case .unknown:
                print("[MultiplayerManager] Player state unknown: \(player.displayName)")
                
            @unknown default:
                break
            }
        }
    }
    
    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error?.localizedDescription ?? "Match failed."
            self?.disconnect()
        }
    }
    
    /// Handles a player disconnecting mid-match.
    private func handlePlayerDisconnect(player: GKPlayer) {
        // Mark player as eliminated.
        let disconnectedId = player.gamePlayerID
        
        if let mpState = multiplayerState {
            // Find their current score (or 0 if unknown).
            let finalScore = mpState.players.first(where: { $0.id == disconnectedId })?.finalScore ?? 0
            mpState.eliminatePlayer(
                playerId: disconnectedId,
                finalScore: finalScore,
                eliminationTime: elapsedMatchTime
            )
        }
        
        // Remove their visual representation from the scene.
        sceneDelegate?.markRemotePlayerDead(playerId: disconnectedId)
        
        // Host tracks alive players.
        if isHost {
            alivePlayerIds.remove(disconnectedId)
            checkForMatchEnd()
        }
    }
}

// MARK: - Convenience Extension for Unique Power-Up IDs

extension MultiplayerManager {
    
    /// Generates a unique power-up ID combining spawn index and timestamp.
    static func generatePowerUpId(spawnIndex: Int) -> String {
        return "powerup_\(spawnIndex)_\(Int(Date().timeIntervalSince1970 * 1000))"
    }
}
