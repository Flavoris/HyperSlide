//
//  PowerUpNode.swift
//  HyprGlide
//
//  Visual representation of collectible power-up rings.
//

import SpriteKit

/// Defines the type of power-up effect.
enum PowerUpType {
    case slowMotion
    case invincibility
    case attackMode
}

/// Glowing collectible ring or shape that grants a temporary effect.
final class PowerUpNode: SKNode {
    
    // MARK: - Public Properties
    
    let type: PowerUpType
    
    // MARK: - Private Properties
    
    private let ringRadius: CGFloat
    private let speedY: CGFloat
    private let pulseKey = "powerUpPulse"
    private let ringNode: SKShapeNode
    
    // MARK: - Initialization
    
    init(type: PowerUpType,
         radius: CGFloat,
         ringWidth: CGFloat = 8,
         speedY: CGFloat,
         coreColor: SKColor,
         glowColor: SKColor) {
        self.type = type
        self.ringRadius = radius
        self.speedY = speedY
        
        let adjustedRadius = max(4, radius - (ringWidth / 2))
        let pathRadius = max(2, adjustedRadius)
        
        // Shape creation based on type
        let shape: SKShapeNode
        switch type {
        case .slowMotion:
            shape = SKShapeNode(circleOfRadius: pathRadius)
        case .invincibility:
            let sideLength = pathRadius * 2
            shape = SKShapeNode(rectOf: CGSize(width: sideLength, height: sideLength), cornerRadius: 4)
        case .attackMode:
            let sideLength = pathRadius * 2.2
            let trianglePath = GlowEffectFactory.trianglePath(sideLength: sideLength)
            shape = SKShapeNode(path: trianglePath)
        }
        
        shape.lineWidth = ringWidth
        shape.strokeColor = coreColor
        shape.fillColor = .clear
        shape.glowWidth = ringWidth * 0.45
        shape.blendMode = .add
        self.ringNode = shape
        
        super.init()
        
        zPosition = 160
        isUserInteractionEnabled = false
        
        addChild(shape)
        addGlow(type: type, radius: radius, color: glowColor)
        configurePhysicsBody(type: type, radius: adjustedRadius)
        runPulseAnimation()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public API
    
    /// Moves the ring downward over time.
    func update(deltaTime: TimeInterval) {
        guard deltaTime.isFinite else { return }
        position.y -= speedY * CGFloat(deltaTime)
    }
    
    /// Returns true once the power-up has fully left the visible playfield.
    func isOffScreen(sceneHeight: CGFloat) -> Bool {
        position.y < -ringRadius * 2
    }
    
    /// Plays a quick dissolve animation before removing the node.
    func playCollectionAnimation(completion: @escaping () -> Void) {
        ringNode.removeAction(forKey: pulseKey)
        physicsBody = nil
        
        let scale = SKAction.scale(to: 1.45, duration: 0.22)
        scale.timingMode = .easeOut
        
        let fade = SKAction.fadeOut(withDuration: 0.2)
        fade.timingMode = .easeIn
        
        let cleanup = SKAction.run(completion)
        run(SKAction.sequence([
            SKAction.group([scale, fade]),
            cleanup
        ]))
    }
    
    // MARK: - Private Helpers
    
    private func addGlow(type: PowerUpType, radius: CGFloat, color: SKColor) {
        let glowNode: SKEffectNode
        switch type {
        case .slowMotion:
            glowNode = GlowEffectFactory.makeCircularGlow(radius: radius,
                                                          color: color,
                                                          blurRadius: 20,
                                                          alpha: 0.85,
                                                          scale: 1.35)
        case .invincibility:
            let sideLength = radius * 2
            glowNode = GlowEffectFactory.makeRoundedRectangleGlow(size: CGSize(width: sideLength, height: sideLength),
                                                                  cornerRadius: 4,
                                                                  color: color,
                                                                  blurRadius: 20,
                                                                  alpha: 0.85,
                                                                  scale: 1.35)
        case .attackMode:
            let sideLength = radius * 2.2
            glowNode = GlowEffectFactory.makeTriangleGlow(sideLength: sideLength,
                                                          color: color,
                                                          blurRadius: 20,
                                                          alpha: 0.85,
                                                          scale: 1.35)
        }
        glowNode.zPosition = -1
        addChild(glowNode)
    }
    
    private func configurePhysicsBody(type: PowerUpType, radius: CGFloat) {
        let body: SKPhysicsBody
        switch type {
        case .slowMotion:
            body = SKPhysicsBody(circleOfRadius: radius)
        case .invincibility:
            let sideLength = radius * 2
            body = SKPhysicsBody(rectangleOf: CGSize(width: sideLength, height: sideLength))
        case .attackMode:
            let sideLength = radius * 2.2
            let trianglePath = GlowEffectFactory.trianglePath(sideLength: sideLength)
            body = SKPhysicsBody(polygonFrom: trianglePath)
        }
        
        body.isDynamic = true
        body.allowsRotation = false
        body.affectedByGravity = false
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.powerUp
        body.contactTestBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.none
        physicsBody = body
    }
    
    private func runPulseAnimation() {
        let pulseOut = SKAction.scale(to: 1.08, duration: 0.6)
        pulseOut.timingMode = .easeInEaseOut
        
        let pulseIn = SKAction.scale(to: 0.94, duration: 0.6)
        pulseIn.timingMode = .easeInEaseOut
        
        let pulseSequence = SKAction.sequence([pulseOut, pulseIn])
        ringNode.run(SKAction.repeatForever(pulseSequence), withKey: pulseKey)
    }
}
