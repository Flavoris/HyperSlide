//
//  GameSceneMultiplayer.swift
//  HyprGlide
//
//  Extension for GameScene providing multiplayer support.
//  Handles remote player rendering, position interpolation, and multiplayer-specific logic.
//

import SpriteKit
import CoreGraphics

// MARK: - Player Node Context

/// Tracks an individual player's node and state in a multiplayer match.
struct PlayerNodeContext {
    /// Unique player identifier (matches Game Center player ID).
    let id: String
    
    /// Whether this is the local player on this device.
    let isLocal: Bool
    
    /// The visual node representing this player in the scene.
    let node: SKShapeNode
    
    /// Display name for UI purposes.
    let displayName: String
    
    /// Current target X position for interpolation (remote players only).
    var targetX: CGFloat = 0
    
    /// Current velocity X for interpolation (remote players only).
    var velocityX: CGFloat = 0
    
    /// Whether this player is still alive in the match.
    var isAlive: Bool = true
    
    /// Player color hue offset (0-1) for distinguishing players.
    let colorHueOffset: CGFloat
    
    /// Color palette currently applied to this player's node.
    var colors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))
    
    init(id: String,
         isLocal: Bool,
         node: SKShapeNode,
         displayName: String,
         colorHueOffset: CGFloat,
         colors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))) {
        self.id = id
        self.isLocal = isLocal
        self.node = node
        self.displayName = displayName
        self.colorHueOffset = colorHueOffset
        self.colors = colors
        self.targetX = node.position.x
    }
}

// MARK: - Multiplayer Player Colors

/// Predefined color schemes for multiplayer players to ensure visual distinction.
struct MultiplayerPlayerColors {
    /// Color tuples: (coreR, coreG, coreB), (glowR, glowG, glowB)
    static let playerColors: [(core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))] = [
        // Blue (local player default - matches single-player)
        (core: (0.0, 0.82, 1.0), glow: (0.0, 0.95, 1.0)),
        // Magenta/Pink
        (core: (1.0, 0.3, 0.85), glow: (1.0, 0.5, 0.95)),
        // Green
        (core: (0.2, 1.0, 0.5), glow: (0.4, 1.0, 0.7)),
        // Orange
        (core: (1.0, 0.6, 0.1), glow: (1.0, 0.75, 0.3))
    ]
    
    /// Returns a color scheme for the given player index.
    static func colorsForPlayer(index: Int) -> (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat)) {
        let safeIndex = index % playerColors.count
        return playerColors[safeIndex]
    }
}

// MARK: - Multiplayer Slow-Motion Tracker

/// Tracks multiplayer slow-motion state where collectors move at normal speed.
struct MultiplayerSlowMotionTracker {
    /// The player ID who collected the slow-motion power-up (moves at normal speed).
    private(set) var collectorId: String?
    
    /// Remaining duration of the multiplayer slow-motion effect.
    private(set) var remaining: TimeInterval = 0
    
    /// Whether a multiplayer slow-motion effect is currently active.
    var isActive: Bool { remaining > 0 }
    
    /// The speed multiplier for non-collectors (0.4 = 40% speed).
    let slowSpeedScale: CGFloat = 0.4
    
    /// Maximum stacked duration for multiplayer slow-motion.
    let maxStackDuration: TimeInterval = 12.0
    
    /// Activates or stacks slow-motion for the specified collector.
    mutating func activate(collectorId: String, duration: TimeInterval) {
        if self.collectorId == collectorId {
            // Same collector: stack duration
            remaining = min(remaining + duration, maxStackDuration)
        } else if !isActive {
            // New activation
            self.collectorId = collectorId
            remaining = min(duration, maxStackDuration)
        } else {
            // Different collector while active: extend duration, update collector
            // The new collector now has the speed advantage
            self.collectorId = collectorId
            remaining = min(remaining + duration, maxStackDuration)
        }
    }
    
    /// Updates the tracker, counting down the remaining duration.
    mutating func update(deltaTime: TimeInterval) {
        guard deltaTime > 0, deltaTime.isFinite else { return }
        remaining = max(0, remaining - deltaTime)
        if remaining <= 0 {
            collectorId = nil
        }
    }
    
    /// Returns the speed multiplier for a given player.
    /// - Parameter playerId: The player to check.
    /// - Returns: 1.0 if the player is the collector (normal speed), slowSpeedScale otherwise.
    func speedMultiplier(for playerId: String) -> CGFloat {
        guard isActive else { return 1.0 }
        return playerId == collectorId ? 1.0 : slowSpeedScale
    }
    
    /// Resets the tracker.
    mutating func reset() {
        collectorId = nil
        remaining = 0
    }
}

// MARK: - Power-Up Tracking for Exclusivity

/// Tracks power-ups for multiplayer exclusivity.
struct PowerUpTracker {
    /// Maps power-up instance IDs to their nodes for quick lookup.
    private var powerUpNodes: [String: PowerUpNode] = [:]
    
    /// Reverse mapping: node object identifier to power-up ID.
    private var nodeToId: [ObjectIdentifier: String] = [:]
    
    /// Set of power-up IDs that have been collected (prevents double-collection).
    private var collectedIds: Set<String> = []
    
    /// Registers a power-up node with its unique ID.
    mutating func register(powerUp: PowerUpNode, id: String) {
        powerUpNodes[id] = powerUp
        nodeToId[ObjectIdentifier(powerUp)] = id
    }
    
    /// Finds the ID for a given power-up node.
    func findId(for powerUp: PowerUpNode) -> String? {
        nodeToId[ObjectIdentifier(powerUp)]
    }
    
    /// Marks a power-up as collected.
    /// - Returns: The node if it exists and wasn't already collected, nil otherwise.
    mutating func markCollected(id: String) -> PowerUpNode? {
        guard !collectedIds.contains(id) else { return nil }
        collectedIds.insert(id)
        if let node = powerUpNodes.removeValue(forKey: id) {
            nodeToId.removeValue(forKey: ObjectIdentifier(node))
            return node
        }
        return nil
    }
    
    /// Checks if a power-up has already been collected.
    func isCollected(id: String) -> Bool {
        collectedIds.contains(id)
    }
    
    /// Removes a power-up from tracking (went off-screen).
    mutating func remove(id: String) {
        if let node = powerUpNodes.removeValue(forKey: id) {
            nodeToId.removeValue(forKey: ObjectIdentifier(node))
        }
    }
    
    /// Resets all tracking.
    mutating func reset() {
        powerUpNodes.removeAll()
        nodeToId.removeAll()
        collectedIds.removeAll()
    }
    
    /// Returns all registered power-up IDs.
    var registeredIds: [String] {
        Array(powerUpNodes.keys)
    }
}

// MARK: - GameScene Multiplayer Extension

extension GameScene {
    
    // MARK: - Multiplayer Scene Delegate Conformance
    
    /// Conform to MultiplayerSceneDelegate by implementing the required methods.
    /// This extension provides the implementation; the main class must declare conformance.
}

// MARK: - Remote Player Interpolation Settings

/// Configuration for smooth remote player movement interpolation.
struct RemotePlayerInterpolation {
    /// How quickly to interpolate to the target position (higher = snappier).
    static let lerpRate: CGFloat = 12.0
    
    /// Maximum allowed position difference before snapping instead of interpolating.
    static let snapThreshold: CGFloat = 200.0
    
    /// Velocity decay rate when no updates are received.
    static let velocityDecay: CGFloat = 0.85
}

// MARK: - Tie Resolution Documentation

/*
 POWER-UP COLLECTION TIE RESOLUTION:
 
 When two players attempt to collect the same power-up near-simultaneously:
 
 1. LOCAL FIRST: Each client processes collisions locally first. If the local
    player touches a power-up, they immediately:
    - Call MultiplayerManager.tryCollectPowerUp()
    - If authorized (power-up not already marked collected), apply the effect
    - The manager broadcasts PowerUpCollectedPayload to all peers
 
 2. NETWORK MESSAGE ORDERING: The first PowerUpCollectedPayload received by
    each client determines the authoritative collector. This follows a
    "first message received wins" policy.
 
 3. RACE CONDITION HANDLING:
    - If a client processes a remote collection message after locally collecting,
      the local collection stands (they already got the effect).
    - If a client receives a remote collection message before processing local
      collision, the power-up is removed and the local player doesn't get it.
 
 4. HOST AUTHORITY (future enhancement):
    - In a stricter implementation, the host could arbitrate all collections.
    - For now, we use optimistic local-first with conflict resolution.
 
 This approach minimizes latency for the collecting player while maintaining
 consistency across clients within the network round-trip time.
*/
