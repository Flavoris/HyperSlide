//
//  GameScene.swift
//  HyperSlide
//
//  SpriteKit scene handling game rendering and update loop
//

import SpriteKit
import SwiftUI

class GameScene: SKScene, SKPhysicsContactDelegate {
    // Reference to game state (injected via delegate pattern)
    weak var gameState: GameState?
    
    // Track time for delta calculations
    private var lastUpdateTime: TimeInterval = 0
    
    // MARK: - Helper Functions
    
    /// Linear interpolation between two values
    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        return start + (end - start) * t
    }
    
    // MARK: - Player Properties
    
    // Player node (glow circle)
    private var player: SKShapeNode!
    
    // Player movement properties
    private var moveSpeed: CGFloat = 12.0  // Speed of LERP interpolation
    private var maxSpeed: CGFloat = 800.0  // Maximum velocity cap
    private var targetX: CGFloat = 0       // Target X position from touch input
    private var velocityX: CGFloat = 0     // Current X velocity
    // MARK: - Obstacle Properties
    
    // Array of active obstacles
    private var obstacles: [ObstacleNode] = []
    
    // Obstacle spawning
    private var spawnTimer: TimeInterval = 0
    private var nextSpawnInterval: TimeInterval = 1.0
    private var obstacleConfig = ObstacleConfig.default
    
    // MARK: - Scene Lifecycle
    
    override func didMove(to view: SKView) {
        // Set pure black background color
        backgroundColor = SKColor.black
        
        // Configure scene physics and properties
        physicsWorld.gravity = CGVector(dx: 0, dy: 0)
        physicsWorld.contactDelegate = self
        scaleMode = .resizeFill
        
        setupScene()
    }
    
    // MARK: - Setup
    
    private func setupScene() {
        setupPlayer()
    }
    
    private func setupPlayer() {
        // Create the player shape (glowing circle)
        let radius: CGFloat = 25.0
        player = SKShapeNode(circleOfRadius: radius)
        
        // Vibrant cyan core
        let coreColor = SKColor(red: 0.0, green: 0.82, blue: 1.0, alpha: 1.0)
        player.strokeColor = .clear
        player.fillColor = coreColor
        player.lineWidth = 0
        
        // Additive blurred glow that mimics the neon reference style
        let glowColor = SKColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0)
        let glowNode = GlowEffectFactory.makeCircularGlow(radius: radius,
                                                          color: glowColor,
                                                          blurRadius: 18,
                                                          alpha: 0.9,
                                                          scale: 1.45)
        glowNode.zPosition = -1
        player.addChild(glowNode)
        
        // Soft inner bloom keeps the center bright even when the outer glow blurs
        let innerBloom = GlowEffectFactory.makeCircularGlow(radius: radius * 0.55,
                                                            color: coreColor,
                                                            blurRadius: 8,
                                                            alpha: 0.75,
                                                            scale: 1.12)
        innerBloom.zPosition = -0.5
        player.addChild(innerBloom)
        
        // Position player near bottom (10% up from bottom)
        let playerY = size.height * 0.15
        player.position = CGPoint(x: size.width / 2, y: playerY)
        targetX = player.position.x
        
        // Setup physics body for player
        setupPlayerPhysics(radius: radius)
        
        addChild(player)
    }
    
    private func setupPlayerPhysics(radius: CGFloat) {
        // Create circular physics body
        player.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        
        // Configure physics properties
        player.physicsBody?.isDynamic = false  // Player controlled by touch, not physics
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle
        player.physicsBody?.collisionBitMask = PhysicsCategory.none
        player.physicsBody?.affectedByGravity = false
        player.physicsBody?.usesPreciseCollisionDetection = true
    }
    // MARK: - Update Loop
    
    override func update(_ currentTime: TimeInterval) {
        // Calculate delta time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // Update game state time and difficulty
        gameState?.updateTime(delta: deltaTime)
        
        // Skip update if game hasn't started, is paused, or is over
        guard let state = gameState,
              state.hasStarted,
              !state.isPaused,
              !state.isGameOver else {
            return
        }
        
        // Game logic updates will be added here
        updateGameLogic(deltaTime: deltaTime)
    }
    
    // MARK: - Game Logic
    
    private func updateGameLogic(deltaTime: TimeInterval) {
        updatePlayerMovement(deltaTime: deltaTime)
        updateObstacles(deltaTime: deltaTime)
        spawnObstacles(deltaTime: deltaTime)
        updateScore(deltaTime: deltaTime)
    }
    
    private func updateScore(deltaTime: TimeInterval) {
        // Add time-based score (10 points per second)
        gameState?.addTime(delta: deltaTime * 10)
    }
    
    private func updatePlayerMovement(deltaTime: TimeInterval) {
        guard player != nil else { return }
        
        // Smooth LERP toward targetX with easing
        let currentX = player.position.x
        let diff = targetX - currentX
        
        // Apply LERP interpolation
        let lerpFactor = min(1.0, moveSpeed * CGFloat(deltaTime))
        velocityX = diff * lerpFactor / CGFloat(deltaTime)
        
        // Clamp velocity to max speed
        velocityX = max(-maxSpeed, min(maxSpeed, velocityX))
        
        // Update position
        var newX = currentX + velocityX * CGFloat(deltaTime)
        
        // Clamp within scene bounds (with margins)
        let margin: CGFloat = 30.0
        newX = max(margin, min(size.width - margin, newX))
        
        player.position.x = newX
    }
    
    private func updateObstacles(deltaTime: TimeInterval) {
        // Update each obstacle's position (freeze or reduce speed when game over)
        let gameOver = gameState?.isGameOver ?? false
        let speedMultiplier = gameOver ? 0.05 : 1.0  // Slow to 5% when game over
        
        for obstacle in obstacles {
            obstacle.update(deltaTime: deltaTime * speedMultiplier)
        }
        
        // Remove offscreen obstacles and award dodge bonus
        obstacles.removeAll { obstacle in
            if obstacle.isOffScreen(sceneHeight: size.height) {
                obstacle.removeFromParent()
                // Award 10 points for dodging an obstacle
                gameState?.addDodge(points: 10)
                return true
            }
            return false
        }
    }
    
    private func spawnObstacles(deltaTime: TimeInterval) {
        // Stop spawning if game is over
        guard !(gameState?.isGameOver ?? true) else { return }
        
        // Increment spawn timer
        spawnTimer += deltaTime
        
        // Check if it's time to spawn a new obstacle
        guard spawnTimer >= nextSpawnInterval else { return }
        
        // Reset timer
        spawnTimer = 0
        
        // Get difficulty (0.0 to 1.0)
        let difficulty = CGFloat(gameState?.difficulty ?? 0.0)
        
        // Calculate spawn interval using lerp: 1.0 -> 0.3 based on difficulty
        let spawnInterval = lerp(1.0, 0.3, difficulty)
        nextSpawnInterval = TimeInterval(spawnInterval)
        
        // Calculate base obstacle speed using lerp: 240 -> 700 based on difficulty
        let baseSpeedY = lerp(240, 700, difficulty)
        
        // Determine obstacle variant with probability weighted by difficulty
        // At d=0: mostly wide slow (70% wide, 30% narrow)
        // At d=1: mostly narrow fast (30% wide, 70% narrow)
        let narrowProbability = Double(difficulty * 0.4 + 0.3) // 0.3 to 0.7
        let isNarrowVariant = Double.random(in: 0...1) < narrowProbability
        
        // Set width and speed based on variant
        let width: CGFloat
        let speedY: CGFloat
        
        if isNarrowVariant {
            // Narrow fast: 50-80 pixels wide, +20% speed
            width = CGFloat.random(in: 50...80)
            speedY = baseSpeedY * 1.2
        } else {
            // Wide slow: 100-150 pixels wide, -10% speed
            width = CGFloat.random(in: 100...150)
            speedY = baseSpeedY * 0.9
        }
        
        let height = obstacleConfig.height
        
        // Calculate safe spawn position (with margins)
        let margin: CGFloat = 50.0
        let minX = margin + width / 2
        let maxX = size.width - margin - width / 2
        let randomX = CGFloat.random(in: minX...maxX)
        
        // Create and position obstacle
        let obstacle = ObstacleNode(width: width, height: height, speedY: speedY)
        obstacle.position = CGPoint(x: randomX, y: size.height + height)
        
        // Add to scene and tracking array
        addChild(obstacle)
        obstacles.append(obstacle)
    }
    
    // MARK: - Collision Handling
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Check if collision involves player and obstacle
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        if collision == PhysicsCategory.player | PhysicsCategory.obstacle {
            handleCollision()
        }
    }
    
    private func handleCollision() {
        // Prevent multiple collision triggers
        guard let state = gameState, !state.isGameOver else { return }
        
        // Trigger game over
        state.isGameOver = true
        
        // Visual and audio feedback
        flashScreen()
        playCrashSound()
    }
    
    private func playCrashSound() {
        // Placeholder for crash sound effect
        // TODO: Add actual sound file and play it here
        // Example: run(SKAction.playSoundFileNamed("crash.wav", waitForCompletion: false))
        print("🔊 Crash sound placeholder - Add sound file to play crash SFX")
    }
    
    private func flashScreen() {
        // Create a brief red flash overlay for collision feedback
        let flash = SKShapeNode(rect: frame)
        flash.fillColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.3)
        flash.strokeColor = .clear
        flash.zPosition = 1000
        addChild(flash)
        
        // Fade out and remove
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let remove = SKAction.removeFromParent()
        flash.run(SKAction.sequence([fadeOut, remove]))
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = gameState else { return }
        
        // Handle touches based on game state
        if !state.hasStarted || state.isGameOver {
            // Touch to start/restart will be handled by HUD buttons
            return
        }
        
        // Set target position for player movement
        if let touch = touches.first {
            let location = touch.location(in: self)
            targetX = location.x
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = gameState, 
              state.hasStarted,
              !state.isGameOver, 
              !state.isPaused else { return }
        
        // Update target position as user drags
        if let touch = touches.first {
            let location = touch.location(in: self)
            targetX = location.x
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = gameState,
              state.hasStarted, 
              !state.isGameOver, 
              !state.isPaused else { return }
        
        // Update target position on touch release
        if let touch = touches.first {
            let location = touch.location(in: self)
            targetX = location.x
        }
    }
    
    // MARK: - Public Methods
    
    /// Reset the game scene and reposition player
    func resetGame(state: GameState) {
        // Reset player position to center bottom
        if player != nil {
            let playerY = size.height * 0.15
            player.position = CGPoint(x: size.width / 2, y: playerY)
            targetX = player.position.x
            velocityX = 0
        }
        
        // Clear all obstacles
        for obstacle in obstacles {
            obstacle.removeFromParent()
        }
        obstacles.removeAll()
        
        // Reset spawn timer
        spawnTimer = 0
        nextSpawnInterval = 1.0
        
        // Reset game state
        state.resetGame()
        lastUpdateTime = 0
    }
}

