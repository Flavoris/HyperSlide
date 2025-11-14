//
//  Obstacle.swift
//  HyperSlide
//
//  Obstacle configuration and node implementation for falling obstacles
//

import SpriteKit

// MARK: - Physics Categories

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 0b1      // 1
    static let obstacle: UInt32 = 0b10   // 2
}

// MARK: - Obstacle Configuration

/// Configuration struct for obstacle spawning and behavior
struct ObstacleConfig {
    /// Range for random obstacle widths
    let widthRange: ClosedRange<CGFloat>
    
    /// Fixed height for all obstacles
    let height: CGFloat
    
    /// Range for random vertical speeds (pixels per second)
    let speedYRange: ClosedRange<CGFloat>
    
    /// Range for random spawn intervals (seconds)
    let spawnIntervalRange: ClosedRange<Double>
    
    /// Default configuration with gentle starting values
    static let `default` = ObstacleConfig(
        widthRange: 80...150,
        height: 30,
        speedYRange: 150...250,
        spawnIntervalRange: 0.8...1.2
    )
    
    /// Creates a scaled configuration based on difficulty multiplier
    func scaled(by difficulty: Double) -> ObstacleConfig {
        return ObstacleConfig(
            widthRange: widthRange,
            height: height,
            speedYRange: (speedYRange.lowerBound * CGFloat(difficulty))...(speedYRange.upperBound * CGFloat(difficulty)),
            spawnIntervalRange: (spawnIntervalRange.lowerBound / difficulty)...(spawnIntervalRange.upperBound / difficulty)
        )
    }
}

// MARK: - Obstacle Node

/// Obstacle node that falls vertically down the screen
class ObstacleNode: SKShapeNode {
    /// Vertical speed (negative value for downward movement)
    var speedY: CGFloat = 0
    
    /// Flag ensuring we only trigger the near-miss bonus once per obstacle
    private(set) var hasTriggeredNearMiss: Bool = false
    
    /// Cached size of the hitbox used for near-miss calculations.
    private(set) var hitboxSize: CGSize = .zero
    
    /// Half-width helper for distance calculations.
    var halfWidth: CGFloat { hitboxSize.width / 2 }
    
    /// Half-height helper for distance calculations.
    var halfHeight: CGFloat { hitboxSize.height / 2 }
    
    /// Initialize an obstacle with specified width, height, and speed
    convenience init(width: CGFloat, height: CGFloat, speedY: CGFloat) {
        self.init()
        
        // Store speed
        self.speedY = speedY
        self.hitboxSize = CGSize(width: width, height: height)
        
        // Create rounded rectangle path
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        self.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        
        // Hot pink/magenta styling with glow (vibrant neon)
        let coreColor = SKColor(red: 1.0, green: 0.1, blue: 0.6, alpha: 1.0)
        self.strokeColor = .clear
        self.fillColor = coreColor
        self.lineWidth = 0
        
        // Add neon bloom similar to arcade obstacles
        let glowColor = SKColor(red: 1.0, green: 0.35, blue: 0.75, alpha: 1.0)
        let glowNode = GlowEffectFactory.makeRoundedRectangleGlow(size: CGSize(width: width, height: height),
                                                                  cornerRadius: 8,
                                                                  color: glowColor,
                                                                  blurRadius: 14,
                                                                  alpha: 0.85,
                                                                  scale: 1.18)
        glowNode.zPosition = -1
        addChild(glowNode)
        
        // Setup physics body
        setupPhysics(size: CGSize(width: width, height: height))
    }
    
    /// Marks the near-miss as consumed so we do not award multiple bonuses.
    func markNearMissTriggered() {
        hasTriggeredNearMiss = true
    }
    
    /// Configure physics body for collision detection
    private func setupPhysics(size: CGSize) {
        // Create rectangular physics body
        physicsBody = SKPhysicsBody(rectangleOf: size)
        
        // Configure physics properties
        // Must be dynamic for contact detection to work, but won't respond to forces
        physicsBody?.isDynamic = true
        physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        physicsBody?.contactTestBitMask = PhysicsCategory.player
        physicsBody?.collisionBitMask = PhysicsCategory.none
        physicsBody?.affectedByGravity = false
        physicsBody?.allowsRotation = false
        physicsBody?.usesPreciseCollisionDetection = true
    }
    
    /// Update obstacle position based on speed and delta time
    func update(deltaTime: TimeInterval) {
        // Move downward
        position.y -= speedY * CGFloat(deltaTime)
    }
    
    /// Check if obstacle is completely off screen
    func isOffScreen(sceneHeight: CGFloat) -> Bool {
        return position.y < -50  // 50 point margin below screen
    }
}

