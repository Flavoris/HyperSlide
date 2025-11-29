//
//  SpawnEventHelpers.swift
//  HyprGlide
//
//  Helper extensions for converting spawn events to scene nodes.
//  Extracted from GameScene to keep spawning logic modular and testable.
//

import SpriteKit
import CoreGraphics

// MARK: - Obstacle Spawn Event Conversion

extension ObstacleSpawnEvent {
    
    /// Converts the normalized X position to an actual screen X coordinate.
    /// - Parameters:
    ///   - sceneWidth: The width of the game scene.
    ///   - margin: The horizontal margin to respect (player movement bounds).
    /// - Returns: The absolute X position for spawning.
    func absoluteX(sceneWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let usableWidth = sceneWidth - (margin * 2) - width
        let minX = margin + (width / 2)
        
        if isEdgePunish {
            // Edge-punish obstacles use the edgeSide to determine position
            switch edgeSide {
            case .left:
                return margin + (width / 2)
            case .right:
                return sceneWidth - margin - (width / 2)
            case .none:
                return sceneWidth / 2
            }
        }
        
        // Normal obstacles use normalizedX
        return minX + (normalizedX * usableWidth)
    }
    
    /// Spawns an obstacle node from this event.
    /// - Parameters:
    ///   - pool: The obstacle pool for recycling nodes.
    ///   - sceneSize: The size of the game scene.
    ///   - margin: The horizontal margin.
    ///   - height: The obstacle height (from config).
    ///   - coreColor: The obstacle core color tuple.
    ///   - glowColor: The obstacle glow color tuple.
    /// - Returns: A configured ObstacleNode positioned for spawning.
    func spawnObstacle(
        pool: ObstaclePool,
        sceneSize: CGSize,
        margin: CGFloat,
        height: CGFloat,
        coreColor: (CGFloat, CGFloat, CGFloat),
        glowColor: (CGFloat, CGFloat, CGFloat),
        glowEnabled: Bool
    ) -> ObstacleNode {
        let positionX = absoluteX(sceneWidth: sceneSize.width, margin: margin)
        let positionY = sceneSize.height + height
        
        let obstacle = pool.dequeue(
            width: width,
            height: height,
            speedY: speedY,
            coreColor: coreColor,
            glowColor: glowColor,
            glowEnabled: glowEnabled
        )
        obstacle.position = CGPoint(x: positionX, y: positionY)
        
        return obstacle
    }
}

// MARK: - Power-Up Spawn Event Conversion

extension PowerUpSpawnEvent {
    
    /// Converts the normalized X position to an actual screen X coordinate.
    /// - Parameters:
    ///   - sceneWidth: The width of the game scene.
    ///   - margin: The horizontal margin to respect.
    /// - Returns: The absolute X position for spawning.
    func absoluteX(sceneWidth: CGFloat, margin: CGFloat) -> CGFloat {
        let usableWidth = sceneWidth - (margin * 2)
        let minX = margin
        return minX + (normalizedX * usableWidth)
    }
    
    /// Spawns a power-up node from this event.
    /// - Parameters:
    ///   - sceneSize: The size of the game scene.
    ///   - margin: The horizontal margin.
    ///   - ringColor: The ring color for the power-up.
    ///   - glowColor: The glow color for the power-up.
    /// - Returns: A configured PowerUpNode positioned for spawning.
    func spawnPowerUp(
        sceneSize: CGSize,
        margin: CGFloat,
        ringColor: SKColor,
        glowColor: SKColor
    ) -> PowerUpNode {
        let positionX = absoluteX(sceneWidth: sceneSize.width, margin: margin)
        let positionY = sceneSize.height + (radius * 2)
        
        let powerUp = PowerUpNode(
            type: type.toPowerUpType,
            radius: radius,
            ringWidth: 8,
            speedY: speedY,
            coreColor: ringColor,
            glowColor: glowColor
        )
        powerUp.position = CGPoint(x: positionX, y: positionY)
        
        return powerUp
    }
}

// MARK: - Spawning Mode Configuration

/// Represents the spawning mode for GameScene.
/// In single-player, uses local deterministic generation.
/// In multiplayer, can accept external event streams from the host.
enum SpawningMode {
    /// Single-player mode: GameScene generates events locally using its own randomizer.
    case local(randomizer: ArenaRandomizer)
    
    /// Multiplayer mode: Events come from a synchronized stream (host-generated).
    case synchronized(stream: ArenaEventStream)
    
    /// Returns whether this is multiplayer synchronized mode.
    var isMultiplayer: Bool {
        if case .synchronized = self { return true }
        return false
    }
}

// MARK: - Spawning State Tracker

/// Tracks the current spawning state for GameScene.
/// Encapsulates spawn timers and intervals for cleaner code.
final class SpawnStateTracker {
    
    // MARK: - Obstacle State
    
    /// Time accumulated since last obstacle spawn.
    var obstacleSpawnTimer: TimeInterval = 0
    
    /// Time until next obstacle spawn.
    var nextObstacleSpawnInterval: TimeInterval = 1.0
    
    // MARK: - Power-Up State
    
    /// Time accumulated since last power-up spawn.
    var powerUpSpawnTimer: TimeInterval = 0
    
    /// Time until next power-up spawn.
    var nextPowerUpSpawnInterval: TimeInterval = 12.0
    
    /// Range for randomizing power-up spawn intervals.
    let powerUpSpawnIntervalRange: ClosedRange<TimeInterval> = 12...18
    
    /// Difficulty threshold before power-ups can spawn.
    let powerUpDifficultyThreshold: Double = 0.25
    
    // MARK: - Edge-Riding Prevention
    
    /// Time the player has spent in the edge zone.
    var edgeLingerTime: TimeInterval = 0
    
    /// Which edge the player is currently near.
    var lastEdgeSide: EdgeSideTracker = .none
    
    /// Width of the edge zone in points.
    let edgeZoneWidth: CGFloat = 80
    
    /// Time before triggering edge-punish spawns.
    let edgeLingerThreshold: TimeInterval = 1.5
    
    /// Probability of spawning an edge-flush obstacle when lingering.
    let edgeFlushSpawnChance: Double = 0.7
    
    /// Edge side tracking for spawn state.
    enum EdgeSideTracker {
        case none, left, right
        
        /// Converts to the spawn event edge side.
        var toEventEdgeSide: ObstacleSpawnEvent.EdgeSideEvent {
            switch self {
            case .none: return .none
            case .left: return .left
            case .right: return .right
            }
        }
    }
    
    // MARK: - Lifecycle
    
    /// Resets all spawn timers for a new game.
    func reset() {
        obstacleSpawnTimer = 0
        nextObstacleSpawnInterval = 1.0
        powerUpSpawnTimer = 0
        nextPowerUpSpawnInterval = Double.random(in: powerUpSpawnIntervalRange)
        edgeLingerTime = 0
        lastEdgeSide = .none
    }
    
    /// Schedules the next power-up spawn with a random interval.
    func scheduleNextPowerUpSpawn() {
        nextPowerUpSpawnInterval = Double.random(in: powerUpSpawnIntervalRange)
    }
    
    /// Updates edge tracking based on player position.
    /// - Parameters:
    ///   - playerX: Current player X position.
    ///   - margin: Movement margin from settings.
    ///   - sceneWidth: Width of the scene.
    ///   - deltaTime: Time since last update.
    func updateEdgeTracking(
        playerX: CGFloat,
        margin: CGFloat,
        sceneWidth: CGFloat,
        deltaTime: TimeInterval
    ) {
        let leftEdgeBoundary = margin + edgeZoneWidth
        let rightEdgeBoundary = sceneWidth - margin - edgeZoneWidth
        
        let currentEdge: EdgeSideTracker
        if playerX <= leftEdgeBoundary {
            currentEdge = .left
        } else if playerX >= rightEdgeBoundary {
            currentEdge = .right
        } else {
            currentEdge = .none
        }
        
        if currentEdge == lastEdgeSide && currentEdge != .none {
            edgeLingerTime += deltaTime
        } else {
            edgeLingerTime = 0
            lastEdgeSide = currentEdge
        }
    }
    
    /// Determines if an edge-punish obstacle should spawn.
    /// - Parameter randomizer: The randomizer to use for probability check.
    /// - Returns: True if edge punishment should occur.
    func shouldSpawnEdgePunish(using randomizer: inout SeededRandomNumberGenerator) -> Bool {
        guard edgeLingerTime >= edgeLingerThreshold,
              lastEdgeSide != .none else {
            return false
        }
        
        let shouldPunish = randomizer.randomBool(probability: edgeFlushSpawnChance)
        if shouldPunish {
            edgeLingerTime = 0 // Reset after punishing
        }
        return shouldPunish
    }
}

// MARK: - Active Power-Up Counter

/// Counts the number of currently active power-up effects.
/// Used for multiplayer stacking limits.
struct ActivePowerUpCounter {
    var slowMotionActive: Bool = false
    var invincibilityActive: Bool = false
    var attackModeActive: Bool = false
    
    /// Total number of active power-up effects.
    var count: Int {
        var total = 0
        if slowMotionActive { total += 1 }
        if invincibilityActive { total += 1 }
        if attackModeActive { total += 1 }
        return total
    }
    
    /// Whether any power-up is currently active.
    var anyActive: Bool {
        slowMotionActive || invincibilityActive || attackModeActive
    }
}
