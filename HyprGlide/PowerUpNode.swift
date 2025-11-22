//
//  PowerUpNode.swift
//  HyprGlide
//
//  Visual representation of collectible power-up rings.
//

import SpriteKit

/// Glowing collectible ring that grants a temporary slowdown effect.
final class PowerUpNode: SKNode {
    
    // MARK: - Private Properties
    
    private let ringRadius: CGFloat
    private let speedY: CGFloat
    private let pulseKey = "powerUpPulse"
    private let ringNode: SKShapeNode
    
    // MARK: - Initialization
    
    init(radius: CGFloat,
         ringWidth: CGFloat = 8,
         speedY: CGFloat,
         coreColor: SKColor,
         glowColor: SKColor) {
        self.ringRadius = radius
        self.speedY = speedY
        
        let adjustedRadius = max(4, radius - (ringWidth / 2))
        let pathRadius = max(2, adjustedRadius)
        let ring = SKShapeNode(circleOfRadius: pathRadius)
        ring.lineWidth = ringWidth
        ring.strokeColor = coreColor
        ring.fillColor = .clear
        ring.glowWidth = ringWidth * 0.45
        ring.blendMode = .add
        self.ringNode = ring
        
        super.init()
        
        zPosition = 160
        isUserInteractionEnabled = false
        
        addChild(ring)
        addGlow(radius: radius, color: glowColor)
        configurePhysicsBody(radius: adjustedRadius)
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
    
    private func addGlow(radius: CGFloat, color: SKColor) {
        let glowNode = GlowEffectFactory.makeCircularGlow(radius: radius,
                                                          color: color,
                                                          blurRadius: 20,
                                                          alpha: 0.85,
                                                          scale: 1.35)
        glowNode.zPosition = -1
        addChild(glowNode)
    }
    
    private func configurePhysicsBody(radius: CGFloat) {
        let body = SKPhysicsBody(circleOfRadius: radius)
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


