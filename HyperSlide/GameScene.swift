//
//  GameScene.swift
//  HyperSlide
//
//  SpriteKit scene handling game rendering and update loop
//

import SpriteKit
import UIKit
import SwiftUI
import CoreMotion
import Foundation

class GameScene: SKScene, SKPhysicsContactDelegate {
    private static let offscreenRenderer: SKView = {
        let renderer = SKView(frame: CGRect(origin: .zero,
                                            size: CGSize(width: 64, height: 64)))
        renderer.isHidden = true
        return renderer
    }()
    
    // Reference to game state (injected via delegate pattern)
    weak var gameState: GameState?
    
    // Settings reference for difficulty, theme, and controls
    var settings: Settings?
    
    // Shared sound manager supplied by SwiftUI host.
    var soundManager: SoundManager?
    
    // Track time for delta calculations
    private var lastUpdateTime: TimeInterval = 0
    private static let maxDeltaTime: TimeInterval = 1.0 / 30.0
    
    // Bounds + safe-area context
    private let minimumMovementMargin: CGFloat = 30.0
    private var movementHorizontalMargin: CGFloat = 30.0
    private var lastKnownSafeAreaInsets: UIEdgeInsets = .zero
    private typealias HorizontalBounds = (min: CGFloat, max: CGFloat)
    
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
    private let playerRadius: CGFloat = 25.0
    private let playerVerticalPositionRatio: CGFloat = 0.22
    private var dragInputActive = false
    private var filteredTiltVelocity: CGFloat = 0
    
    // Game feel tuning
    private var lastVelocitySign: CGFloat = 0
    private var isCameraShaking = false
    private let nearMissHorizontalPadding: CGFloat = 10
    private let nearMissVerticalPadding: CGFloat = 24
    private let directionFlipVelocityThreshold: CGFloat = 60
    private let particleLayer = SKNode()
    private var nearMissEmitterFactory: NearMissEmitterFactory?
    private var shouldPrimeEmitterOnPresentation = true
    private let performanceGovernor = PerformanceGovernor()
    
    // Tilt control
    private let motionManager = CMMotionManager()
    private var motionActivityManager: CMMotionActivityManager?
    private var isDeviceMotionActive = false
    private var hasRequestedMotionPermission = false
    private let tiltDeadZone: CGFloat = 0.05
    private let baseTiltMaxSpeed: CGFloat = 1100.0
    private let baseTiltResponsiveness: CGFloat = 12.0  // higher == snappier response
    
    // MARK: - Obstacle Properties
    
    // Array of active obstacles
    private var obstacles: [ObstacleNode] = []
    private let obstaclePool = ObstaclePool(maximumCapacity: 32)
    
    // Obstacle spawning
    private var spawnTimer: TimeInterval = 0
    private var nextSpawnInterval: TimeInterval = 1.0
    private var obstacleConfig = ObstacleConfig.default
    
    // MARK: - Power-Up Properties
    
    private var powerUps: [PowerUpNode] = []
    private var powerUpSpawnTimer: TimeInterval = 0
    private var nextPowerUpSpawnInterval: TimeInterval = 12
    private let powerUpSpawnIntervalRange: ClosedRange<TimeInterval> = 12...18
    private let powerUpDifficultyThreshold: Double = 0.25
    private var slowMotionEffect = SlowMotionEffect(duration: 3.0,
                                                   speedScale: 0.4,
                                                   maxStackDuration: 6.0) // 3 second slow to 40%, stackable to 6s
    private var slowMotionOverlay: SKShapeNode?
    private let slowMotionOverlayMaxAlpha: CGFloat = 0.92
    private let slowMotionOverlayFadeInRate: CGFloat = 12.0
    private let slowMotionOverlayFadeOutRate: CGFloat = 4.0
    
    // MARK: - Scene Lifecycle
    
    override func sceneDidLoad() {
        super.sceneDidLoad()
        
        if nearMissEmitterFactory == nil {
            let renderer = view ?? GameScene.offscreenRenderer
            nearMissEmitterFactory = NearMissEmitterFactory(renderer: renderer)
        }
        
        Haptics.prewarm()
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        
        // Set pure black background color
        backgroundColor = SKColor.black
        
        // Configure scene physics and properties
        physicsWorld.gravity = CGVector(dx: 0, dy: 0)
        physicsWorld.contactDelegate = self
        scaleMode = .resizeFill
        lastKnownSafeAreaInsets = view.safeAreaInsets
        movementHorizontalMargin = computeMovementMargin(for: lastKnownSafeAreaInsets)
        
        setupScene()
        refreshSafeAreaInsets(force: true)
        setupTiltControl()
        nearMissEmitterFactory?.attachPool(to: particleLayer)
        applyCurrentPerformanceMode()
        
        if shouldPrimeEmitterOnPresentation {
            nearMissEmitterFactory?.prime(in: self)
            shouldPrimeEmitterOnPresentation = false
        }
        
        fullyWarmEmitterPipeline()
        powerUpSpawnTimer = 0
        scheduleNextPowerUpSpawn()
        updateSlowMotionOverlayGeometry()
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        handleSceneSizeChange(from: oldSize)
        updateSlowMotionOverlayGeometry()
    }
    
    // MARK: - Setup
    
    private func setupScene() {
        setupPlayer()
        
        if particleLayer.parent == nil {
            particleLayer.zPosition = 180
            addChild(particleLayer)
        }
    }
    
    private func setupPlayer() {
        // Create the player shape (glowing circle)
        player = SKShapeNode(circleOfRadius: playerRadius)
        
        // Get theme colors from settings, default to neon blue
        let colors = settings?.colorTheme.playerColor ?? 
                    (core: (0.0, 0.82, 1.0), glow: (0.0, 0.95, 1.0))
        
        // Vibrant core color from theme
        let coreColor = SKColor(red: colors.core.0, 
                               green: colors.core.1, 
                               blue: colors.core.2, 
                               alpha: 1.0)
        player.strokeColor = .clear
        player.fillColor = coreColor
        player.lineWidth = 0
        
        // Additive blurred glow that mimics the neon reference style
        let glowColor = SKColor(red: colors.glow.0, 
                               green: colors.glow.1, 
                               blue: colors.glow.2, 
                               alpha: 1.0)
        let glowNode = GlowEffectFactory.makeCircularGlow(radius: playerRadius,
                                                          color: glowColor,
                                                          blurRadius: 18,
                                                          alpha: 0.9,
                                                          scale: 1.45)
        glowNode.zPosition = -1
        player.addChild(glowNode)
        
        // Soft inner bloom keeps the center bright even when the outer glow blurs
        let innerBloom = GlowEffectFactory.makeCircularGlow(radius: playerRadius * 0.55,
                                                            color: coreColor,
                                                            blurRadius: 8,
                                                            alpha: 0.75,
                                                            scale: 1.12)
        innerBloom.zPosition = -0.5
        player.addChild(innerBloom)
        
        // Position player slightly above bottom to keep UI visible
        let playerY = size.height * playerVerticalPositionRatio
        player.position = CGPoint(x: size.width / 2, y: playerY)
        targetX = player.position.x
        
        // Setup physics body for player
        setupPlayerPhysics(radius: playerRadius)
        
        addChild(player)
    }
    
    // MARK: - Layout & Safe Area
    
    private func handleSceneSizeChange(from oldSize: CGSize) {
        let previousBounds = horizontalBounds(for: oldSize.width, margin: movementHorizontalMargin)
        refreshSafeAreaInsets(force: true, previousBounds: previousBounds)
    }
    
    private func refreshSafeAreaInsets(force: Bool = false,
                                       previousBounds: HorizontalBounds? = nil) {
        guard let currentView = view else { return }
        let safeInsets = currentView.safeAreaInsets
        if !force && safeInsets == lastKnownSafeAreaInsets {
            return
        }
        
        let referenceBounds = previousBounds ?? horizontalBounds()
        lastKnownSafeAreaInsets = safeInsets
        movementHorizontalMargin = computeMovementMargin(for: safeInsets)
        restorePlayerPosition(relativeTo: referenceBounds)
    }
    
    private func computeMovementMargin(for safeArea: UIEdgeInsets) -> CGFloat {
        guard size.width.isFinite else { return minimumMovementMargin }
        let horizontalInset = max(safeArea.left, safeArea.right)
        let radiusBuffer = playerRadius + 12
        let requestedMargin = max(minimumMovementMargin, horizontalInset + radiusBuffer)
        let halfWidth = size.width / 2
        let maxAllowedMargin = max(minimumMovementMargin, halfWidth - (playerRadius + 4))
        let sanitizedMax = max(minimumMovementMargin, maxAllowedMargin)
        return min(requestedMargin, sanitizedMax)
    }
    
    private func restorePlayerPosition(relativeTo previousBounds: HorizontalBounds) {
        guard let player = player else { return }
        let currentBounds = horizontalBounds()
        let ratio = normalizedPosition(for: player.position.x, within: previousBounds)
        let span = currentBounds.max - currentBounds.min
        let newX = currentBounds.min + ratio * span
        let clampedX = clampWithinHorizontalBounds(newX)
        player.position.x = clampedX
        targetX = clampedX
    }
    
    private func horizontalBounds(for width: CGFloat? = nil,
                                  margin: CGFloat? = nil) -> HorizontalBounds {
        let sceneWidth = width ?? size.width
        let marginValue = margin ?? movementHorizontalMargin
        guard sceneWidth.isFinite else { return (marginValue, marginValue) }
        let minX = marginValue
        let maxX = max(minX, sceneWidth - marginValue)
        return (minX, maxX)
    }
    
    private func normalizedPosition(for x: CGFloat,
                                    within bounds: HorizontalBounds) -> CGFloat {
        let span = max(bounds.max - bounds.min, .leastNonzeroMagnitude)
        let normalized = (x - bounds.min) / span
        return min(max(normalized, 0), 1)
    }
    
    private func setupPlayerPhysics(radius: CGFloat) {
        // Create circular physics body
        player.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        
        // Configure physics properties
        player.physicsBody?.isDynamic = false  // Player controlled by touch, not physics
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.powerUp
        player.physicsBody?.collisionBitMask = PhysicsCategory.none
        player.physicsBody?.affectedByGravity = false
        player.physicsBody?.usesPreciseCollisionDetection = true
    }
    
    private func setupTiltControl() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz sampling
        updateTiltControlPreference(isEnabled: settings?.tiltControlEnabled == true)
    }
    
    func updateTiltControlPreference(isEnabled: Bool) {
        if isEnabled {
            requestMotionPermissionIfNeeded()
            startDeviceMotionUpdates()
        } else {
            stopDeviceMotionUpdates()
            filteredTiltVelocity = 0
        }
    }
    
    private func requestMotionPermissionIfNeeded() {
        guard !hasRequestedMotionPermission else { return }
        hasRequestedMotionPermission = true
        
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        if #available(iOS 11.0, *) {
            let status = CMMotionActivityManager.authorizationStatus()
            guard status != .denied && status != .restricted else { return }
        }
        
        let manager = CMMotionActivityManager()
        motionActivityManager = manager
        let now = Date()
        manager.queryActivityStarting(from: now, to: now, to: OperationQueue.main) { [weak self] _, _ in
            self?.startDeviceMotionUpdates()
        }
    }
    
    private func startDeviceMotionUpdates() {
        guard !isDeviceMotionActive,
              motionManager.isDeviceMotionAvailable else { return }
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)
        isDeviceMotionActive = true
    }
    
    private func stopDeviceMotionUpdates() {
        guard isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
        isDeviceMotionActive = false
    }
    
    // MARK: - Update Loop
    
    override func update(_ currentTime: TimeInterval) {
        // Calculate delta time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let rawDeltaTime = max(0, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        let deltaTime = min(rawDeltaTime, GameScene.maxDeltaTime)
        
        refreshSafeAreaInsets()
        
        if performanceGovernor.registerFrame(deltaTime: rawDeltaTime, currentTime: currentTime) {
            applyCurrentPerformanceMode()
        }
        
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
        detectNearMisses()
        spawnObstacles(deltaTime: deltaTime)
        updatePowerUps(deltaTime: deltaTime)
        updateScore(deltaTime: deltaTime)
    }
    
    private func updateScore(deltaTime: TimeInterval) {
        // Add time-based score (10 points per second)
        gameState?.addTime(delta: deltaTime * 10)
    }
    
    private func updatePlayerMovement(deltaTime: TimeInterval) {
        guard let player = player else { return }
        
        let currentX = player.position.x
        let dt = max(CGFloat(deltaTime), 0.0001)
        
        if dragInputActive {
            let diff = targetX - currentX
            let lerpFactor = min(1.0, moveSpeed * dt)
            velocityX = diff * lerpFactor / dt
            velocityX = max(-maxSpeed, min(maxSpeed, velocityX))
            handleDirectionChangeIfNeeded()
            let newX = clampWithinHorizontalBounds(currentX + velocityX * dt)
            player.position.x = newX
        } else if settings?.tiltControlEnabled == true {
            let tiltVelocity = resolveTiltVelocity(deltaTime: deltaTime)
            velocityX = tiltVelocity
            handleDirectionChangeIfNeeded()
            let newX = clampWithinHorizontalBounds(currentX + tiltVelocity * dt)
            player.position.x = newX
            targetX = newX // Keep drag target aligned when switching back
        } else {
            filteredTiltVelocity = 0
            velocityX = 0
        }
    }
    
    private func clampWithinHorizontalBounds(_ value: CGFloat) -> CGFloat {
        guard size.width.isFinite else { return value }
        let minX = movementHorizontalMargin
        let maxX = max(minX, size.width - movementHorizontalMargin)
        return max(minX, min(maxX, value))
    }
    
    private func updateDragTarget(with touch: UITouch) {
        let location = touch.location(in: self)
        targetX = clampWithinHorizontalBounds(location.x)
    }
    
    private func currentTiltSensitivity() -> CGFloat {
        guard let multiplier = settings?.tiltSensitivity else {
            return 1.0
        }
        return CGFloat(multiplier)
    }
    
    private func resolveTiltVelocity(deltaTime: TimeInterval) -> CGFloat {
        guard isDeviceMotionActive,
              let motion = motionManager.deviceMotion else {
            filteredTiltVelocity = 0
            return 0
        }
        
        let sensitivity = currentTiltSensitivity()
        let adjustedMaxSpeed = baseTiltMaxSpeed * sensitivity
        let targetVelocity = TiltInputMapper.velocity(for: motion.gravity.x,
                                                      deadZone: tiltDeadZone,
                                                      maxSpeed: adjustedMaxSpeed)
        let response = min(1.0, CGFloat(deltaTime) * baseTiltResponsiveness * sensitivity)
        filteredTiltVelocity = lerp(filteredTiltVelocity, targetVelocity, response)
        return filteredTiltVelocity
    }
    
    private func updateObstacles(deltaTime: TimeInterval) {
        // Update each obstacle's position (freeze or reduce speed when game over)
        let gameOver = gameState?.isGameOver ?? false
        let baseMultiplier: Double = gameOver ? 0.05 : 1.0  // Slow to 5% when game over
        let slowMultiplier = Double(slowMotionEffect.speedMultiplier)
        let speedMultiplier = baseMultiplier * slowMultiplier
        
        for obstacle in obstacles {
            obstacle.update(deltaTime: deltaTime * speedMultiplier)
        }
        
        // Remove offscreen obstacles and award dodge bonus
        obstacles.removeAll { obstacle in
            if obstacle.isOffScreen(sceneHeight: size.height) {
                recycleObstacle(obstacle)
                // Award 10 points for dodging an obstacle
                gameState?.addDodge(points: 10)
                return true
            }
            return false
        }
    }
    
    private func recycleObstacle(_ obstacle: ObstacleNode) {
        obstacle.removeAllActions()
        obstacle.removeFromParent()
        obstaclePool.recycle(obstacle)
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
        
        // Get difficulty (0.0 to 1.0) and apply difficulty ramp multiplier
        let baseDifficulty = gameState?.difficulty ?? 0.0
        let difficultyMultiplier = settings?.difficultyMultiplier ?? 1.0
        let difficulty = CGFloat(min(1.0, baseDifficulty * difficultyMultiplier))
        
        // Calculate spawn interval using lerp: 1.0 -> 0.3 based on difficulty
        let spawnInterval = lerp(1.0, 0.3, difficulty)
        let intervalWithGovernor = spawnInterval * CGFloat(performanceGovernor.spawnIntervalMultiplier)
        nextSpawnInterval = TimeInterval(intervalWithGovernor)
        
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
        
        // Get theme colors for obstacles, default to hot pink
        let obstacleColors = settings?.colorTheme.obstacleColor ?? 
                            (core: (1.0, 0.1, 0.6), glow: (1.0, 0.35, 0.75))
        
        // Create and position obstacle with theme colors
        let obstacle = obstaclePool.dequeue(width: width,
                                            height: height,
                                            speedY: speedY,
                                            coreColor: obstacleColors.core,
                                            glowColor: obstacleColors.glow)
        obstacle.position = CGPoint(x: randomX, y: size.height + height)
        
        // Add to scene and tracking array
        if obstacle.parent !== self {
            addChild(obstacle)
        }
        obstacles.append(obstacle)
    }
    
    private func updatePowerUps(deltaTime: TimeInterval) {
        slowMotionEffect.update(deltaTime: deltaTime)
        updateSlowMotionOverlay(deltaTime: deltaTime)
        
        guard let state = gameState,
              state.hasStarted,
              !state.isGameOver else {
            return
        }
        
        for powerUp in powerUps {
            powerUp.update(deltaTime: deltaTime)
        }
        
        powerUps.removeAll { powerUp in
            if powerUp.isOffScreen(sceneHeight: size.height) {
                powerUp.removeFromParent()
                return true
            }
            return false
        }
        
        spawnPowerUpIfNeeded(deltaTime: deltaTime, difficulty: state.difficulty)
    }
    
    private func spawnPowerUpIfNeeded(deltaTime: TimeInterval, difficulty: Double) {
        guard difficulty >= powerUpDifficultyThreshold else {
            // Hold timer at zero until the game ramps up enough.
            powerUpSpawnTimer = 0
            return
        }
        
        guard powerUps.isEmpty else { return }
        
        powerUpSpawnTimer += deltaTime
        guard powerUpSpawnTimer >= nextPowerUpSpawnInterval else { return }
        
        powerUpSpawnTimer = 0
        scheduleNextPowerUpSpawn()
        spawnPowerUp(difficulty: difficulty)
    }
    
    private func spawnPowerUp(difficulty: Double) {
        guard size.width.isFinite, size.height.isFinite else { return }
        
        let t = CGFloat(min(max(difficulty, 0), 1))
        let radius = lerp(26, 32, t)
        let speedY = lerp(180, 260, t)
        let horizontalMargin = max(movementHorizontalMargin, radius + 24)
        let minX = horizontalMargin
        let maxX = max(horizontalMargin, size.width - horizontalMargin)
        guard maxX > minX else { return }
        
        let positionX = CGFloat.random(in: minX...maxX)
        let positionY = size.height + radius * 2
        
        let colors = powerUpThemeColors()
        
        let powerUp = PowerUpNode(radius: radius,
                                  ringWidth: 8,
                                  speedY: speedY,
                                  coreColor: colors.ring,
                                  glowColor: colors.glow)
        powerUp.position = CGPoint(x: positionX, y: positionY)
        
        addChild(powerUp)
        powerUps.append(powerUp)
    }
    
    private func scheduleNextPowerUpSpawn() {
        nextPowerUpSpawnInterval = Double.random(in: powerUpSpawnIntervalRange)
    }
    
    private func powerUpThemeColors() -> (ring: SKColor, glow: SKColor) {
        let themeColors = settings?.colorTheme.powerUpColor ??
                          (ring: (0.1, 1.0, 0.8), glow: (0.3, 1.0, 0.85))
        let ringColor = SKColor(red: themeColors.ring.0,
                                green: themeColors.ring.1,
                                blue: themeColors.ring.2,
                                alpha: 1.0)
        let glowColor = SKColor(red: themeColors.glow.0,
                                green: themeColors.glow.1,
                                blue: themeColors.glow.2,
                                alpha: 1.0)
        return (ring: ringColor, glow: glowColor)
    }
    
    private func updateSlowMotionOverlay(deltaTime: TimeInterval) {
        let dt = CGFloat(max(0, min(deltaTime, 1)))
        
        if slowMotionEffect.isActive {
            let overlay = ensureSlowMotionOverlay()
            updateSlowMotionOverlayGeometry()
            overlay.strokeColor = powerUpThemeColors().glow
            overlay.alpha = min(slowMotionOverlayMaxAlpha,
                                overlay.alpha + slowMotionOverlayFadeInRate * dt)
        } else if let overlay = slowMotionOverlay {
            overlay.alpha = max(0, overlay.alpha - slowMotionOverlayFadeOutRate * dt)
            if overlay.alpha <= 0.01 {
                clearSlowMotionOverlay()
            }
        }
    }
    
    private func activateSlowMotionOverlayImmediately() {
        let overlay = ensureSlowMotionOverlay()
        overlay.strokeColor = powerUpThemeColors().glow
        updateSlowMotionOverlayGeometry()
        overlay.alpha = slowMotionOverlayMaxAlpha
    }
    
    private func ensureSlowMotionOverlay() -> SKShapeNode {
        if let overlay = slowMotionOverlay {
            return overlay
        }
        
        let overlay = SKShapeNode()
        overlay.fillColor = .clear
        overlay.lineWidth = 8
        overlay.glowWidth = 28
        overlay.alpha = 0
        overlay.blendMode = .add
        overlay.zPosition = 500
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
        slowMotionOverlay = overlay
        return overlay
    }
    
    private func updateSlowMotionOverlayGeometry() {
        guard let overlay = slowMotionOverlay,
              size.width.isFinite,
              size.height.isFinite else { return }
        
        let inset: CGFloat = 14
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        let rect = CGRect(x: -width / 2,
                          y: -height / 2,
                          width: width,
                          height: height)
        overlay.path = CGPath(roundedRect: rect,
                              cornerWidth: 42,
                              cornerHeight: 42,
                              transform: nil)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    
    private func clearSlowMotionOverlay() {
        slowMotionOverlay?.removeFromParent()
        slowMotionOverlay = nil
    }
    
    // MARK: - Collision Handling
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Check if collision involves player and obstacle or power-up
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        if collision == PhysicsCategory.player | PhysicsCategory.obstacle {
            handleCollision()
        } else if collision == PhysicsCategory.player | PhysicsCategory.powerUp {
            if let node = (contact.bodyA.node as? PowerUpNode) ?? (contact.bodyB.node as? PowerUpNode) {
                handlePowerUpCollection(node)
            }
        }
    }
    
    private func handleCollision() {
        // Prevent multiple collision triggers
        guard let state = gameState, !state.isGameOver else { return }
        
        // Trigger game over
        state.isGameOver = true
        slowMotionEffect.reset()
        clearSlowMotionOverlay()
        performCollisionFeedback()
    }
    
    private func performCollisionFeedback() {
        flashScreen()
        startCameraShake()
        soundManager?.playCollision()
        Haptics.playCollisionImpact()
    }
    
    private func handlePowerUpCollection(_ powerUp: PowerUpNode) {
        guard let state = gameState,
              state.hasStarted,
              !state.isGameOver else { return }
        
        guard let index = powerUps.firstIndex(where: { $0 === powerUp }) else { return }
        powerUps.remove(at: index)
        
        slowMotionEffect.trigger()
        activateSlowMotionOverlayImmediately()
        Haptics.playNearMissImpact(intensity: 0.9)
        
        powerUp.playCollectionAnimation { [weak powerUp] in
            powerUp?.removeFromParent()
        }
    }
    
    private func startCameraShake(duration: TimeInterval = 0.18,
                                  amplitudeX: CGFloat = 18,
                                  amplitudeY: CGFloat = 12) {
        guard !isCameraShaking else { return }
        
        isCameraShaking = true
        position = .zero
        
        let shakeAction = SKAction.customAction(withDuration: duration) { node, elapsedTime in
            let normalizedProgress = elapsedTime / CGFloat(duration)
            let damping = max(0.0, 1.0 - normalizedProgress)
            let offsetX = CGFloat.random(in: -amplitudeX...amplitudeX) * damping
            let offsetY = CGFloat.random(in: -amplitudeY...amplitudeY) * damping
            node.position = CGPoint(x: offsetX, y: offsetY)
        }
        
        let reset = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.position = .zero
            self.isCameraShaking = false
        }
        
        run(SKAction.sequence([shakeAction, reset]), withKey: "cameraShake")
    }
    
    private func handleDirectionChangeIfNeeded() {
        let speedMagnitude = abs(velocityX)
        
        if speedMagnitude >= directionFlipVelocityThreshold {
            let newSign: CGFloat = velocityX > 0 ? 1 : -1
            if lastVelocitySign != 0 && newSign != lastVelocitySign {
                triggerDirectionChangeSquash()
            }
            lastVelocitySign = newSign
        } else if speedMagnitude < directionFlipVelocityThreshold * 0.33 {
            // Reset to zero so that the next significant push counts as a flip.
            lastVelocitySign = 0
        }
    }
    
    private func triggerDirectionChangeSquash() {
        guard let player = player else { return }
        
        let squashKey = "directionSquash"
        guard player.action(forKey: squashKey) == nil else { return }
        
        let squash = SKAction.group([
            SKAction.scaleX(to: 0.78, duration: 0.08),
            SKAction.scaleY(to: 1.16, duration: 0.08)
        ])
        squash.timingMode = .easeOut
        
        let rebound = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.18),
            SKAction.scaleY(to: 1.0, duration: 0.18)
        ])
        rebound.timingMode = .easeOut
        
        player.run(SKAction.sequence([squash, rebound]), withKey: squashKey)
    }
    
    private func detectNearMisses() {
        guard let player = player,
              let state = gameState,
              state.hasStarted,
              !state.isGameOver else { return }
        
        let playerPosition = player.position
        
        for obstacle in obstacles where !obstacle.hasTriggeredNearMiss {
            let dx = abs(obstacle.position.x - playerPosition.x)
            let dy = abs(obstacle.position.y - playerPosition.y)
            let collisionHorizontalThreshold = playerRadius + obstacle.halfWidth
            let collisionVerticalThreshold = playerRadius + obstacle.halfHeight
            
            // Skip if we're actually colliding (handled elsewhere).
            if dx <= collisionHorizontalThreshold && dy <= collisionVerticalThreshold {
                continue
            }
            
            let horizontalThreshold = playerRadius + obstacle.halfWidth + nearMissHorizontalPadding
            let verticalThreshold = playerRadius + obstacle.halfHeight + nearMissVerticalPadding
            
            if dx <= horizontalThreshold && dy <= verticalThreshold {
                obstacle.markNearMissTriggered()
                state.addNearMissBonus()
                emitNearMissParticles(at: playerPosition)
                soundManager?.playNearMiss()
                Haptics.playNearMissImpact()
            }
        }
    }
    
    private func emitNearMissParticles(at position: CGPoint) {
        guard let factory = nearMissEmitterFactory,
              let emitter = factory.makeEmitter(at: position) else { return }
        
        let cleanupSequence = SKAction.sequence([
            SKAction.wait(forDuration: factory.cleanupDelay),
            SKAction.run { [weak self, weak emitter] in
                guard let emitter = emitter else { return }
                self?.nearMissEmitterFactory?.recycle(emitter)
            }
        ])
        emitter.run(cleanupSequence)
    }
    
    private func fullyWarmEmitterPipeline() {
        guard let factory = nearMissEmitterFactory,
              let emitter = factory.makeEmitter(at: CGPoint(x: -2000, y: -2000)) else {
            return
        }
        
        let originalBirthRate = emitter.particleBirthRate
        let originalNumParticles = emitter.numParticlesToEmit
        let originalLifetime = emitter.particleLifetime
        
        emitter.numParticlesToEmit = 1
        emitter.particleBirthRate = 1
        emitter.particleLifetime = 0.1
        emitter.alpha = 0.001
        
        let restoreAndRecycle = SKAction.run { [weak self, weak emitter] in
            guard let self, let emitter else { return }
            emitter.particleBirthRate = originalBirthRate
            emitter.numParticlesToEmit = originalNumParticles
            emitter.particleLifetime = originalLifetime
            self.nearMissEmitterFactory?.recycle(emitter)
        }
        
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.2),
            restoreAndRecycle
        ]))
    }
    
    private func applyCurrentPerformanceMode() {
        nearMissEmitterFactory?.setIntensityMultiplier(performanceGovernor.particleIntensityMultiplier)
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
        if !state.hasStarted || state.isGameOver || state.isPaused {
            // Touch to start/restart will be handled by HUD buttons
            return
        }
        
        if let touch = touches.first {
            dragInputActive = true
            updateDragTarget(with: touch)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = gameState, 
              state.hasStarted,
              !state.isGameOver, 
              !state.isPaused else { return }
        
        if let touch = touches.first {
            dragInputActive = true
            updateDragTarget(with: touch)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = gameState,
              state.hasStarted, 
              !state.isGameOver, 
              !state.isPaused else { return }
        
        if let touch = touches.first {
            updateDragTarget(with: touch)
        }
        dragInputActive = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragInputActive = false
        super.touchesCancelled(touches, with: event)
    }
    
    // MARK: - Public Methods
    
    /// Update player colors based on current theme
    func updatePlayerColors() {
        guard let player = player else { return }
        
        // Get theme colors from settings, default to neon blue
        let colors = settings?.colorTheme.playerColor ?? 
                    (core: (0.0, 0.82, 1.0), glow: (0.0, 0.95, 1.0))
        
        // Update core color
        let coreColor = SKColor(red: colors.core.0, 
                               green: colors.core.1, 
                               blue: colors.core.2, 
                               alpha: 1.0)
        player.fillColor = coreColor
        
        // Update glow colors on child nodes
        let glowColor = SKColor(red: colors.glow.0, 
                               green: colors.glow.1, 
                               blue: colors.glow.2, 
                               alpha: 1.0)
        
        // Update all glow effect children
        for child in player.children {
            if let effectNode = child as? SKEffectNode {
                // Update the glow filter color if possible
                effectNode.removeFromParent()
            }
        }
        
        // Re-add glow nodes with new colors
        let glowNode = GlowEffectFactory.makeCircularGlow(radius: playerRadius,
                                                          color: glowColor,
                                                          blurRadius: 18,
                                                          alpha: 0.9,
                                                          scale: 1.45)
        glowNode.zPosition = -1
        player.addChild(glowNode)
        
        let innerBloom = GlowEffectFactory.makeCircularGlow(radius: playerRadius * 0.55,
                                                            color: coreColor,
                                                            blurRadius: 8,
                                                            alpha: 0.75,
                                                            scale: 1.12)
        innerBloom.zPosition = -0.5
        player.addChild(innerBloom)
    }
    
    /// Reset the game scene and reposition player
    func resetGame(state: GameState) {
        // Reset player position to center bottom
        if let player = player {
            let playerY = size.height * playerVerticalPositionRatio
            player.position = CGPoint(x: size.width / 2, y: playerY)
            targetX = player.position.x
            velocityX = 0
            filteredTiltVelocity = 0
            player.yScale = 1.0
            player.xScale = 1.0
            player.removeAction(forKey: "directionSquash")
        }
        
        // Clear all obstacles
        for obstacle in obstacles {
            recycleObstacle(obstacle)
        }
        obstacles.removeAll()
        
        // Clear active power-ups
        for powerUp in powerUps {
            powerUp.removeFromParent()
        }
        powerUps.removeAll()
        powerUpSpawnTimer = 0
        scheduleNextPowerUpSpawn()
        slowMotionEffect.reset()
        clearSlowMotionOverlay()
        
        // Reset spawn timer
        spawnTimer = 0
        nextSpawnInterval = 1.0
        
        // Reset game state
        state.resetGame()
        lastUpdateTime = 0
        lastVelocitySign = 0
        isCameraShaking = false
        removeAction(forKey: "cameraShake")
        position = .zero
        dragInputActive = false
        
        if performanceGovernor.reset() {
            applyCurrentPerformanceMode()
        }
    }
    
    deinit {
        // Stop motion updates when scene is deallocated
        stopDeviceMotionUpdates()
    }
}

/// Maps Core Motion gravity samples to a horizontal velocity with deadzone + clamping.
struct TiltInputMapper {
    static func velocity(for gravityX: Double,
                         deadZone: CGFloat,
                         maxSpeed: CGFloat) -> CGFloat {
        guard maxSpeed > 0 else { return 0 }
        let clamped = CGFloat(max(-1.0, min(1.0, gravityX)))
        let magnitude = abs(clamped)
        
        guard magnitude > deadZone else { return 0 }
        
        let usableRange = max(1.0 - deadZone, .leastNonzeroMagnitude)
        let normalized = (magnitude - deadZone) / usableRange
        let direction: CGFloat = clamped >= 0 ? 1 : -1
        return normalized * maxSpeed * direction
    }
}


