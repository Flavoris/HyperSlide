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
    static let powerUp: UInt32 = 0b100   // 4
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
    private static let glowNodeName = "ObstacleGlow"
    
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
    
    /// Initialize an obstacle with specified width, height, speed, and colors
    convenience init(width: CGFloat, 
                     height: CGFloat, 
                     speedY: CGFloat,
                     coreColor: (CGFloat, CGFloat, CGFloat) = (1.0, 0.1, 0.6),
                     glowColor: (CGFloat, CGFloat, CGFloat) = (1.0, 0.35, 0.75)) {
        self.init()
        configure(width: width, height: height, speedY: speedY, coreColor: coreColor, glowColor: glowColor)
    }
    
    /// Reconfigures the node so pooled instances can be reused without reallocation.
    func configure(width: CGFloat,
                   height: CGFloat,
                   speedY: CGFloat,
                   coreColor: (CGFloat, CGFloat, CGFloat),
                   glowColor: (CGFloat, CGFloat, CGFloat)) {
        self.speedY = speedY
        hitboxSize = CGSize(width: width, height: height)
        hasTriggeredNearMiss = false
        
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        
        strokeColor = .clear
        fillColor = SKColor(red: coreColor.0, 
                            green: coreColor.1, 
                            blue: coreColor.2, 
                            alpha: 1.0)
        lineWidth = 0
        
        childNode(withName: Self.glowNodeName)?.removeFromParent()
        let glowNode = GlowEffectFactory.makeRoundedRectangleGlow(size: CGSize(width: width, height: height),
                                                                  cornerRadius: 8,
                                                                  color: SKColor(red: glowColor.0,
                                                                                 green: glowColor.1,
                                                                                 blue: glowColor.2,
                                                                                 alpha: 1.0),
                                                                  blurRadius: 14,
                                                                  alpha: 0.85,
                                                                  scale: 1.18)
        glowNode.name = Self.glowNodeName
        glowNode.zPosition = -1
        addChild(glowNode)
        
        setupPhysics(size: hitboxSize)
    }
    
    /// Prepares a recycled node for the next use.
    func prepareForReuse() {
        removeAllActions()
        physicsBody?.velocity = .zero
        zRotation = 0
        alpha = 1
        isHidden = false
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

// MARK: - Simple Obstacle Pool

final class ObstaclePool {
    private var storage: [ObstacleNode] = []
    private let maxCapacity: Int
    
    init(maximumCapacity: Int = 24) {
        self.maxCapacity = max(1, maximumCapacity)
    }
    
    func dequeue(width: CGFloat,
                 height: CGFloat,
                 speedY: CGFloat,
                 coreColor: (CGFloat, CGFloat, CGFloat),
                 glowColor: (CGFloat, CGFloat, CGFloat)) -> ObstacleNode {
        let obstacle: ObstacleNode
        if let reused = storage.popLast() {
            obstacle = reused
            obstacle.prepareForReuse()
        } else {
            obstacle = ObstacleNode()
        }
        obstacle.configure(width: width,
                           height: height,
                           speedY: speedY,
                           coreColor: coreColor,
                           glowColor: glowColor)
        return obstacle
    }
    
    func recycle(_ obstacle: ObstacleNode) {
        guard storage.count < maxCapacity else { return }
        obstacle.removeAllActions()
        obstacle.alpha = 0
        obstacle.isHidden = true
        storage.append(obstacle)
    }
    
    func drain() {
        storage.removeAll()
    }
}


