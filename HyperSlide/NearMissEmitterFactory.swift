//
//  NearMissEmitterFactory.swift
//  HyperSlide
//
//  Builds and reuses the near-miss particle burst to avoid runtime stalls.
//

import SpriteKit

/// Factory responsible for pre-building the near-miss particle burst emitter.
/// Creating emitters on the fly was causing frame hitches; we now cache the
/// texture and reuse a prototype that can be copied cheaply at runtime.
final class NearMissEmitterFactory {
    /// Delay used to remove emitters once the burst has finished animating.
    let cleanupDelay: TimeInterval = 0.5
    
    private let prototypeEmitter: SKEmitterNode
    private let maxPoolSize: Int
    private var availableEmitters: [SKEmitterNode] = []
    private weak var poolParent: SKNode?
    private var hasPrimedEmitter = false
    
    init?(renderer: SKView, poolSize: Int = 8) {
        guard let particleTexture = Self.buildParticleTexture(using: renderer) else {
            return nil
        }
        
        prototypeEmitter = Self.buildEmitter(using: particleTexture)
        maxPoolSize = max(1, poolSize)
        
        // Pre-build a small pool so the first burst does not clone at runtime.
        availableEmitters = (0..<maxPoolSize).compactMap { _ in
            prototypeEmitter.copy() as? SKEmitterNode
        }
        availableEmitters.forEach { emitter in
            emitter.isHidden = true
            emitter.alpha = 0
            emitter.resetSimulation()
        }
    }
    
    /// Ensures the pooled emitters are attached to a shared parent node.
    func attachPool(to parent: SKNode) {
        poolParent = parent
        
        for emitter in availableEmitters {
            if emitter.parent !== parent {
                parent.addChild(emitter)
            }
            
            emitter.alpha = 0
            emitter.isHidden = true
            emitter.resetSimulation()
        }
    }
    
    /// Returns a configured emitter positioned for the burst.
    func makeEmitter(at position: CGPoint) -> SKEmitterNode? {
        let emitter: SKEmitterNode
        if let pooled = availableEmitters.popLast() {
            emitter = pooled
        } else if let copy = prototypeEmitter.copy() as? SKEmitterNode {
            emitter = copy
        } else {
            return nil
        }
        
        if emitter.parent == nil, let parent = poolParent {
            parent.addChild(emitter)
        }
        
        emitter.alpha = 1
        emitter.position = position
        emitter.isHidden = false
        emitter.resetSimulation()
        return emitter
    }
    
    /// Returns the emitter to the pool once its cleanup action has completed.
    func recycle(_ emitter: SKEmitterNode) {
        emitter.alpha = 0
        emitter.removeAllActions()
        emitter.resetSimulation()
        emitter.isHidden = true
        
        if availableEmitters.count < maxPoolSize {
            availableEmitters.append(emitter)
        }
    }
    
    /// Runs a hidden burst immediately so the render pipeline is warmed up.
    func prime(in scene: SKNode) {
        guard !hasPrimedEmitter else { return }
        
        if poolParent == nil {
            attachPool(to: scene)
        }
        
        guard let emitter = makeEmitter(at: CGPoint(x: -5000, y: -5000)) else {
            return
        }
        
        hasPrimedEmitter = true
        emitter.alpha = 0
        
        let recycleAction = SKAction.run { [weak self, weak emitter] in
            guard let self, let emitter else { return }
            emitter.alpha = 0
            self.recycle(emitter)
        }
        
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: cleanupDelay),
            recycleAction
        ]))
    }
}

// MARK: - Private Builders

private extension NearMissEmitterFactory {
    static func buildParticleTexture(using renderer: SKView) -> SKTexture? {
        // Draw a simple circle without expensive glow effects for optimal performance.
        // The glow will be achieved through additive blending and alpha properties.
        let particleShape = SKShapeNode(circleOfRadius: 5)
        particleShape.fillColor = SKColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0)
        particleShape.strokeColor = .clear
        particleShape.lineWidth = 0
        
        let texture = renderer.texture(from: particleShape)
        texture?.filteringMode = .linear
        return texture
    }
    
    static func buildEmitter(using texture: SKTexture) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.particleColor = SKColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0)
        emitter.particleColorBlendFactor = 1.0
        
        // Use additive blending for better performance and more vibrant glow effect
        emitter.particleBlendMode = .add
        
        // Reduced particle count for smoother performance while maintaining visual impact
        emitter.particleBirthRate = 200
        emitter.numParticlesToEmit = 12
        emitter.particleLifetime = 0.35
        emitter.particleLifetimeRange = 0.1
        
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 320
        emitter.particleSpeedRange = 120
        
        emitter.particleAlpha = 0.85
        emitter.particleAlphaRange = 0.15
        emitter.particleAlphaSpeed = -2.8
        
        emitter.particleScale = 0.4
        emitter.particleScaleRange = 0.14
        emitter.particleScaleSpeed = -1.2
        emitter.particlePositionRange = CGVector(dx: 8, dy: 8)
        
        emitter.zPosition = 200
        emitter.isUserInteractionEnabled = false
        
        // Shader-based rendering optimization
        emitter.particleRenderOrder = .oldestLast
        
        return emitter
    }
}

