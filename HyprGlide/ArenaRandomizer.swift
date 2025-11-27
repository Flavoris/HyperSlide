//
//  ArenaRandomizer.swift
//  HyprGlide
//
//  Deterministic arena event generation for multiplayer synchronization.
//  Provides seeded random number generation and spawn event structs
//  that can be shared across clients for identical arena behavior.
//

import Foundation
import CoreGraphics

// MARK: - Seeded Random Number Generator

/// A Linear Congruential Generator (LCG) that produces deterministic random values
/// given an initial seed. This allows multiple clients to generate identical
/// "random" sequences for multiplayer synchronization.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    // LCG parameters (same as glibc)
    private static let multiplier: UInt64 = 6364136223846793005
    private static let increment: UInt64 = 1442695040888963407
    
    private var state: UInt64
    
    /// Initialize with a specific seed for deterministic output.
    init(seed: UInt64) {
        self.state = seed
    }
    
    /// Generates the next random UInt64 value.
    mutating func next() -> UInt64 {
        state = state &* Self.multiplier &+ Self.increment
        return state
    }
    
    /// Generates a random Double in the range [0, 1).
    mutating func randomDouble() -> Double {
        let value = next()
        return Double(value) / Double(UInt64.max)
    }
    
    /// Generates a random Double in the specified range.
    mutating func random(in range: ClosedRange<Double>) -> Double {
        let normalized = randomDouble()
        return range.lowerBound + normalized * (range.upperBound - range.lowerBound)
    }
    
    /// Generates a random CGFloat in the specified range.
    mutating func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(random(in: Double(range.lowerBound)...Double(range.upperBound)))
    }
    
    /// Generates a random Int in the specified range.
    mutating func random(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        guard span > 0 else { return range.lowerBound }
        let randomValue = next() % span
        return range.lowerBound + Int(randomValue)
    }
    
    /// Generates a random Bool with the specified probability of being true.
    mutating func randomBool(probability: Double = 0.5) -> Bool {
        randomDouble() < probability
    }
}

// MARK: - Spawn Event Structs

/// Describes a single obstacle spawn event that can be serialized and replayed.
struct ObstacleSpawnEvent: Codable, Equatable {
    /// Time offset from match start when this obstacle should spawn.
    let timeOffset: TimeInterval
    
    /// Obstacle width in points.
    let width: CGFloat
    
    /// Vertical speed in points per second.
    let speedY: CGFloat
    
    /// Horizontal spawn position (normalized 0...1, converted to screen coords by consumer).
    let normalizedX: CGFloat
    
    /// Whether this is an edge-punishing obstacle spawned to counter edge-riding.
    let isEdgePunish: Bool
    
    /// Which edge side the obstacle targets (for edge-punish obstacles).
    let edgeSide: EdgeSideEvent
    
    /// Edge side representation for Codable support.
    enum EdgeSideEvent: Int, Codable {
        case none = 0
        case left = 1
        case right = 2
    }
}

/// Describes a single power-up spawn event that can be serialized and replayed.
struct PowerUpSpawnEvent: Codable, Equatable {
    /// Time offset from match start when this power-up should spawn.
    let timeOffset: TimeInterval
    
    /// The type of power-up to spawn.
    let type: PowerUpTypeEvent
    
    /// Horizontal spawn position (normalized 0...1).
    let normalizedX: CGFloat
    
    /// Vertical speed in points per second.
    let speedY: CGFloat
    
    /// Radius of the power-up node.
    let radius: CGFloat
    
    /// Power-up type for Codable support.
    enum PowerUpTypeEvent: Int, Codable {
        case slowMotion = 0
        case invincibility = 1
        case attackMode = 2
        
        /// Convert to the game's PowerUpType enum.
        var toPowerUpType: PowerUpType {
            switch self {
            case .slowMotion: return .slowMotion
            case .invincibility: return .invincibility
            case .attackMode: return .attackMode
            }
        }
        
        /// Create from the game's PowerUpType enum.
        static func from(_ type: PowerUpType) -> PowerUpTypeEvent {
            switch type {
            case .slowMotion: return .slowMotion
            case .invincibility: return .invincibility
            case .attackMode: return .attackMode
            }
        }
    }
}

// MARK: - Arena Configuration

/// Configuration for multiplayer-specific spawning behavior.
struct ArenaMultiplayerConfig {
    /// Maximum number of power-ups that can be active simultaneously in multiplayer.
    let maxSimultaneousPowerUps: Int
    
    /// Minimum time between power-up spawns in multiplayer (prevents flooding).
    let minPowerUpSpawnInterval: TimeInterval
    
    /// Whether power-up effects can stack while others are active.
    let allowPowerUpStacking: Bool
    
    /// Default multiplayer configuration.
    static let `default` = ArenaMultiplayerConfig(
        maxSimultaneousPowerUps: 2,
        minPowerUpSpawnInterval: 8.0,
        allowPowerUpStacking: true
    )
    
    /// More chaotic configuration for special modes.
    static let chaos = ArenaMultiplayerConfig(
        maxSimultaneousPowerUps: 3,
        minPowerUpSpawnInterval: 5.0,
        allowPowerUpStacking: true
    )
}

// MARK: - Arena Randomizer

/// Generates deterministic spawn events for obstacles and power-ups.
/// Given the same seed and difficulty progression, produces identical
/// spawn sequences across all clients.
final class ArenaRandomizer {
    
    // MARK: - Properties
    
    private var rng: SeededRandomNumberGenerator
    
    /// The seed used to initialize this randomizer.
    /// Can be shared with other clients for synchronized spawning.
    let seed: UInt64
    
    private let multiplayerConfig: ArenaMultiplayerConfig?
    
    /// Current spawn index for obstacles (used for replay verification).
    private(set) var obstacleSpawnIndex: Int = 0
    
    /// Current spawn index for power-ups (used for replay verification).
    private(set) var powerUpSpawnIndex: Int = 0
    
    /// Tracks the last power-up spawn time to enforce minimum intervals.
    private var lastPowerUpSpawnTime: TimeInterval = 0
    
    /// Whether this randomizer is configured for multiplayer mode.
    var isMultiplayer: Bool { multiplayerConfig != nil }
    
    // MARK: - Initialization
    
    /// Initialize with a seed for deterministic generation.
    /// - Parameters:
    ///   - seed: The random seed (should be shared across all clients in multiplayer).
    ///   - multiplayerConfig: Optional config for multiplayer-specific behavior.
    init(seed: UInt64, multiplayerConfig: ArenaMultiplayerConfig? = nil) {
        self.seed = seed
        self.rng = SeededRandomNumberGenerator(seed: seed)
        self.multiplayerConfig = multiplayerConfig
    }
    
    /// Creates a single-player randomizer using a random seed.
    static func singlePlayer() -> ArenaRandomizer {
        let randomSeed = UInt64.random(in: 0...UInt64.max)
        return ArenaRandomizer(seed: randomSeed, multiplayerConfig: nil)
    }
    
    /// Creates a multiplayer randomizer with the specified shared seed.
    static func multiplayer(seed: UInt64, config: ArenaMultiplayerConfig = .default) -> ArenaRandomizer {
        return ArenaRandomizer(seed: seed, multiplayerConfig: config)
    }
    
    /// Resets the randomizer to its initial state (for game restart).
    func reset() {
        rng = SeededRandomNumberGenerator(seed: seed)
        obstacleSpawnIndex = 0
        powerUpSpawnIndex = 0
        lastPowerUpSpawnTime = 0
    }
    
    // MARK: - Obstacle Spawning
    
    /// Generates parameters for the next obstacle spawn.
    /// - Parameters:
    ///   - currentTime: Current elapsed game time.
    ///   - difficulty: Current difficulty (0.0 to 1.0).
    ///   - isEdgePunish: Whether this should be an edge-punishing obstacle.
    ///   - edgeSide: Which edge to punish (if applicable).
    /// - Returns: An ObstacleSpawnEvent with deterministic parameters.
    func nextObstacleEvent(
        currentTime: TimeInterval,
        difficulty: CGFloat,
        isEdgePunish: Bool = false,
        edgeSide: ObstacleSpawnEvent.EdgeSideEvent = .none
    ) -> ObstacleSpawnEvent {
        obstacleSpawnIndex += 1
        
        if isEdgePunish {
            return generateEdgePunishObstacle(
                currentTime: currentTime,
                difficulty: difficulty,
                edgeSide: edgeSide
            )
        }
        
        return generateStandardObstacle(currentTime: currentTime, difficulty: difficulty)
    }
    
    private func generateStandardObstacle(
        currentTime: TimeInterval,
        difficulty: CGFloat
    ) -> ObstacleSpawnEvent {
        // Probability of narrow fast variant increases with difficulty
        let narrowProbability = Double(difficulty * 0.4 + 0.3) // 0.3 to 0.7
        let isNarrowVariant = rng.randomBool(probability: narrowProbability)
        
        let width: CGFloat
        let speedMultiplier: CGFloat
        
        if isNarrowVariant {
            width = rng.random(in: 50...80)
            speedMultiplier = 1.2
        } else {
            width = rng.random(in: 100...150)
            speedMultiplier = 0.9
        }
        
        // Base speed scales with difficulty: 240 -> 700
        let baseSpeedY = lerp(240, 700, difficulty)
        let speedY = baseSpeedY * speedMultiplier
        
        // Horizontal position: bias toward edges as difficulty increases
        let normalizedX = generateObstacleNormalizedX(difficulty: difficulty)
        
        return ObstacleSpawnEvent(
            timeOffset: currentTime,
            width: width,
            speedY: speedY,
            normalizedX: normalizedX,
            isEdgePunish: false,
            edgeSide: .none
        )
    }
    
    private func generateEdgePunishObstacle(
        currentTime: TimeInterval,
        difficulty: CGFloat,
        edgeSide: ObstacleSpawnEvent.EdgeSideEvent
    ) -> ObstacleSpawnEvent {
        // Edge-punish obstacles are wider and slightly faster
        let baseSpeedY = lerp(240, 700, difficulty)
        let speedY = baseSpeedY * 1.1
        
        // Position based on which edge to punish
        let normalizedX: CGFloat
        switch edgeSide {
        case .left:
            normalizedX = 0.15 // Near left edge
        case .right:
            normalizedX = 0.85 // Near right edge
        case .none:
            normalizedX = 0.5
        }
        
        return ObstacleSpawnEvent(
            timeOffset: currentTime,
            width: 140, // Wide enough to force movement
            speedY: speedY,
            normalizedX: normalizedX,
            isEdgePunish: true,
            edgeSide: edgeSide
        )
    }
    
    private func generateObstacleNormalizedX(difficulty: CGFloat) -> CGFloat {
        // Edge spawn chance increases with difficulty: 15% to 45%
        let edgeSpawnChance = Double(difficulty * 0.3 + 0.15)
        
        if rng.randomBool(probability: edgeSpawnChance) {
            // Spawn near left or right edge
            return rng.randomBool() ? rng.random(in: 0.05...0.15) : rng.random(in: 0.85...0.95)
        }
        
        // Normal random spawn across the full width
        return rng.random(in: 0.1...0.9)
    }
    
    // MARK: - Power-Up Spawning
    
    /// Determines if a power-up should spawn and generates its parameters.
    /// - Parameters:
    ///   - currentTime: Current elapsed game time.
    ///   - difficulty: Current difficulty (0.0 to 1.0).
    ///   - activePowerUpCount: Number of power-ups currently active (for multiplayer cap).
    ///   - anyPowerUpActive: Whether any power-up effect is currently active.
    /// - Returns: A PowerUpSpawnEvent if one should spawn, nil otherwise.
    func nextPowerUpEventIfNeeded(
        currentTime: TimeInterval,
        difficulty: Double,
        activePowerUpCount: Int,
        anyPowerUpActive: Bool
    ) -> PowerUpSpawnEvent? {
        // In single-player, don't spawn if any power-up is active
        if !isMultiplayer && anyPowerUpActive {
            return nil
        }
        
        // In multiplayer, respect the simultaneous cap
        if isMultiplayer {
            let maxActive = multiplayerConfig?.maxSimultaneousPowerUps ?? 2
            if activePowerUpCount >= maxActive {
                return nil
            }
            
            // Enforce minimum spawn interval
            let minInterval = multiplayerConfig?.minPowerUpSpawnInterval ?? 8.0
            if currentTime - lastPowerUpSpawnTime < minInterval {
                return nil
            }
        }
        
        powerUpSpawnIndex += 1
        lastPowerUpSpawnTime = currentTime
        
        return generatePowerUpEvent(currentTime: currentTime, difficulty: difficulty)
    }
    
    /// Forces generation of a power-up event (for external event replay).
    func forcePowerUpEvent(
        currentTime: TimeInterval,
        difficulty: Double
    ) -> PowerUpSpawnEvent {
        powerUpSpawnIndex += 1
        lastPowerUpSpawnTime = currentTime
        return generatePowerUpEvent(currentTime: currentTime, difficulty: difficulty)
    }
    
    private func generatePowerUpEvent(
        currentTime: TimeInterval,
        difficulty: Double
    ) -> PowerUpSpawnEvent {
        let t = CGFloat(min(max(difficulty, 0), 1))
        let radius = lerp(26, 32, t)
        let speedY = lerp(180, 260, t)
        
        // Random horizontal position
        let normalizedX = rng.random(in: 0.15...0.85)
        
        // Random power-up type
        let typeRoll = rng.random(in: 0...2)
        let type: PowerUpSpawnEvent.PowerUpTypeEvent
        switch typeRoll {
        case 0: type = .slowMotion
        case 1: type = .invincibility
        default: type = .attackMode
        }
        
        return PowerUpSpawnEvent(
            timeOffset: currentTime,
            type: type,
            normalizedX: normalizedX,
            speedY: speedY,
            radius: radius
        )
    }
    
    // MARK: - Spawn Interval Generation
    
    /// Generates the next obstacle spawn interval based on difficulty.
    func nextObstacleSpawnInterval(difficulty: CGFloat) -> TimeInterval {
        // Base interval: 1.0s at difficulty 0, 0.3s at difficulty 1
        let baseInterval = lerp(1.0, 0.3, difficulty)
        
        // Add small random variation (±15%)
        let variation = rng.random(in: 0.85...1.15)
        return TimeInterval(baseInterval * variation)
    }
    
    /// Generates the next power-up spawn interval.
    func nextPowerUpSpawnInterval() -> TimeInterval {
        rng.random(in: 12.0...18.0)
    }
    
    // MARK: - Helpers
    
    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * t
    }
}

// MARK: - Arena Event Stream

/// Represents a stream of spawn events that can be replayed deterministically.
/// Used for multiplayer where the host generates events and broadcasts them.
struct ArenaEventStream: Codable {
    /// The seed used to generate this stream.
    let seed: UInt64
    
    /// Obstacle spawn events in chronological order.
    var obstacleEvents: [ObstacleSpawnEvent]
    
    /// Power-up spawn events in chronological order.
    var powerUpEvents: [PowerUpSpawnEvent]
    
    /// Index of the next obstacle event to consume.
    var nextObstacleIndex: Int = 0
    
    /// Index of the next power-up event to consume.
    var nextPowerUpIndex: Int = 0
    
    init(seed: UInt64) {
        self.seed = seed
        self.obstacleEvents = []
        self.powerUpEvents = []
    }
    
    /// Returns the next obstacle event if its time has come.
    mutating func nextObstacleEventIfReady(currentTime: TimeInterval) -> ObstacleSpawnEvent? {
        guard nextObstacleIndex < obstacleEvents.count else { return nil }
        let event = obstacleEvents[nextObstacleIndex]
        if currentTime >= event.timeOffset {
            nextObstacleIndex += 1
            return event
        }
        return nil
    }
    
    /// Returns the next power-up event if its time has come.
    mutating func nextPowerUpEventIfReady(currentTime: TimeInterval) -> PowerUpSpawnEvent? {
        guard nextPowerUpIndex < powerUpEvents.count else { return nil }
        let event = powerUpEvents[nextPowerUpIndex]
        if currentTime >= event.timeOffset {
            nextPowerUpIndex += 1
            return event
        }
        return nil
    }
    
    /// Adds an obstacle event to the stream.
    mutating func appendObstacleEvent(_ event: ObstacleSpawnEvent) {
        obstacleEvents.append(event)
    }
    
    /// Adds a power-up event to the stream.
    mutating func appendPowerUpEvent(_ event: PowerUpSpawnEvent) {
        powerUpEvents.append(event)
    }
    
    /// Resets playback indices for replay.
    mutating func resetPlayback() {
        nextObstacleIndex = 0
        nextPowerUpIndex = 0
    }
}

