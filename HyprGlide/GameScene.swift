//
//  GameScene.swift
//  HyprGlide
//
//  SpriteKit scene handling game rendering and update loop
//

import SpriteKit
import UIKit
import SwiftUI
import CoreMotion
import Foundation

class GameScene: SKScene, SKPhysicsContactDelegate, MultiplayerSceneDelegate {
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
    
    private let fallbackPlayerColors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat)) =
        (core: (0.0, 0.82, 1.0), glow: (0.0, 0.95, 1.0))
    private let fallbackObstacleColors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat)) =
        (core: (1.0, 0.1, 0.6), glow: (1.0, 0.35, 0.75))
    
    private var glowEffectsEnabledCache: Bool = true
    
    // Shared sound manager supplied by SwiftUI host.
    var soundManager: SoundManager?
    
    // MARK: - Multiplayer Properties
    
    /// Reference to the multiplayer manager (nil in single-player mode).
    weak var multiplayerManager: MultiplayerManager?
    
    /// Observable multiplayer state for lobby/countdown awareness.
    weak var multiplayerState: MultiplayerState?
    
    /// Dictionary of all players in a multiplayer match, keyed by player ID.
    /// In single-player mode, this is empty. The `player` property is used directly.
    private(set) var playerNodes: [String: PlayerNodeContext] = [:]
    
    /// The local player's ID in multiplayer mode.
    private var localPlayerId: String?
    
    /// Match start time for multiplayer synchronization.
    private var matchStartTime: TimeInterval?
    
    /// Tracks multiplayer slow-motion where the collector moves at normal speed.
    private var multiplayerSlowMotion = MultiplayerSlowMotionTracker()
    
    /// Tracks power-up instances for multiplayer exclusivity.
    private var powerUpTracker = PowerUpTracker()
    
    /// Whether we're currently in multiplayer mode.
    var isMultiplayerMode: Bool {
        gameState?.mode.isMultiplayer ?? false
    }
    
    /// Frame counter for throttled state broadcasts.
    private var multiplayerFrameCounter: Int = 0
    
    /// How often to send position updates (every N frames).
    private let positionUpdateFrameInterval: Int = 3
    
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
    
    private func currentPlayerColors() -> (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat)) {
        if isMultiplayerMode,
           let localId = localPlayerId,
           let context = playerNodes[localId] {
            return context.colors
        }
        return settings?.colorTheme.playerColor ?? fallbackPlayerColors
    }
    
    private func currentObstacleColors() -> (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat)) {
        return settings?.colorTheme.obstacleColor ?? fallbackObstacleColors
    }
    
    private func removeGlowNodes(from node: SKNode) {
        for child in node.children where child is SKEffectNode {
            child.removeFromParent()
        }
    }
    
    private func applyGlowStateToPlayer() {
        guard let player = player else { return }
        
        let colors = currentPlayerColors()
        let coreColor = SKColor(red: colors.core.0,
                                green: colors.core.1,
                                blue: colors.core.2,
                                alpha: 1.0)
        player.fillColor = coreColor
        removeGlowNodes(from: player)
        guard glowEffectsEnabledCache else { return }
        
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
        
        let innerBloom = GlowEffectFactory.makeCircularGlow(radius: playerRadius * 0.55,
                                                            color: coreColor,
                                                            blurRadius: 8,
                                                            alpha: 0.75,
                                                            scale: 1.12)
        innerBloom.zPosition = -0.5
        player.addChild(innerBloom)
    }
    
    private func applyGlowStateToRemotePlayers() {
        guard isMultiplayerMode else { return }
        for (_, context) in playerNodes where !context.isLocal {
            removeGlowNodes(from: context.node)
            guard glowEffectsEnabledCache else { continue }
            
            let glowColor = SKColor(red: context.colors.glow.0,
                                    green: context.colors.glow.1,
                                    blue: context.colors.glow.2,
                                    alpha: 1.0)
            let glowNode = GlowEffectFactory.makeCircularGlow(
                radius: playerRadius,
                color: glowColor,
                blurRadius: 14,
                alpha: 0.7,
                scale: 1.35
            )
            glowNode.zPosition = -1
            context.node.addChild(glowNode)
        }
    }
    
    private func applyGlowStateToObstacles() {
        let glowColor = currentObstacleColors().glow
        for obstacle in obstacles {
            obstacle.updateGlow(enabled: glowEffectsEnabledCache, glowColor: glowColor)
        }
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
    private var dragMomentumVelocity: CGFloat = 0  // Residual velocity after releasing a drag or tilt
    private var glidePrimed = false                // Set after first user movement so we keep drifting
    private let glideMinimumSpeed: CGFloat = 80.0  // Minimum drift once primed
    private let dragMomentumDecayRate: CGFloat = 2.2  // Higher = quicker slowdown
    private let dragMomentumStopThreshold: CGFloat = 8.0  // Cutoff to avoid micro-drifting
    private var filteredTiltVelocity: CGFloat = 0
    private var lastDragTouchX: CGFloat?
    private var lastDragTouchTime: TimeInterval?
    private var recentDragVelocity: CGFloat = 0
    
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
    
    // Edge squish effect properties
    private var currentEdgeSquish: CGFloat = 0  // 0 = no squish, 1 = max squish
    private let edgeSquishMaxScale: CGFloat = 0.72  // How flat the orb gets at max squish
    private let edgeSquishStretchScale: CGFloat = 1.22  // How tall the orb gets at max squish
    private let edgeSquishVelocityThreshold: CGFloat = 150  // Velocity needed for noticeable squish
    private let edgeSquishMaxVelocity: CGFloat = 800  // Velocity at which max squish occurs
    private let edgeSquishSmoothRate: CGFloat = 18.0  // How fast squish responds
    private let edgeSquishRecoverRate: CGFloat = 12.0  // How fast it recovers
    
    // Edge bounce-back properties
    private var edgeBounceVelocity: CGFloat = 0  // Current bounce-back velocity
    private var lastEdgeHitSide: EdgeSide = .none  // Which edge we hit
    private var edgeBounceActive = false  // Whether a bounce is in progress
    private let edgeBounceStrength: CGFloat = 0.25  // Fraction of impact velocity reflected
    private let edgeBounceDamping: CGFloat = 8.0  // How quickly bounce velocity decays
    private let edgeBounceMinVelocity: CGFloat = 20  // Minimum velocity to keep bouncing
    
    private enum LifecyclePauseTrigger {
        case sceneWillResignActive
        case applicationWillResignActive
    }
    
    private var lifecycleObservers: [NSObjectProtocol] = []
    
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
    
    // Obstacle configuration
    private var obstacleConfig = ObstacleConfig.default
    
    // MARK: - Deterministic Spawning
    
    /// Arena randomizer for deterministic spawn generation.
    /// In single-player, uses a random seed. In multiplayer, uses a shared seed.
    private var arenaRandomizer: ArenaRandomizer = ArenaRandomizer.singlePlayer()
    
    /// Tracks spawn timers, edge-riding, and intervals.
    private let spawnState = SpawnStateTracker()
    
    /// Optional external event stream for multiplayer synchronized spawning.
    /// When set, the scene replays events from the stream instead of generating locally.
    private var externalEventStream: ArenaEventStream?
    
    /// Configuration for multiplayer power-up behavior.
    private var multiplayerConfig: ArenaMultiplayerConfig?
    
    private enum EdgeSide {
        case none, left, right
    }
    
    // MARK: - Power-Up Properties
    
    private var powerUps: [PowerUpNode] = []
    private var slowMotionEffect = SlowMotionEffect(duration: 6.0,
                                                   speedScale: 0.4,
                                                   maxStackDuration: 12.0) // 6 second slow to 40%, stackable to 12s
    private var slowMotionOverlay: SKShapeNode?
    private let slowMotionOverlayMaxAlpha: CGFloat = 0.92
    private let slowMotionOverlayFadeInRate: CGFloat = 12.0
    private let slowMotionOverlayFadeOutRate: CGFloat = 4.0
    
    // Power-up expiry warning settings
    private let powerUpWarningThreshold: TimeInterval = 1.5  // Start warning at 1.5 seconds remaining
    private var powerUpPulsePhase: CGFloat = 0  // Tracks pulse animation phase

    private var invincibilityEffect = InvincibilityEffect(duration: 6.0,
                                                          maxStackDuration: 12.0)
    private var invincibilityOverlay: SKShapeNode?

    private var attackModeEffect = AttackModeEffect(duration: 6.0,
                                                    maxStackDuration: 12.0)
    private var attackModeOverlay: SKShapeNode?
    private let attackModeDestroyPoints: Double = 25  // Points for destroying an obstacle
    
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
        spawnState.reset()
        spawnState.scheduleNextPowerUpSpawn()
        updateSlowMotionOverlayGeometry()
        registerLifecycleNotifications()
    }
    
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        unregisterLifecycleNotifications()
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
        player.strokeColor = .clear
        player.lineWidth = 0
        applyGlowStateToPlayer()
        
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
    
    // MARK: - Lifecycle Handling
    
    private func registerLifecycleNotifications() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let sceneWillDeactivate = center.addObserver(forName: UIScene.willDeactivateNotification,
                                                     object: nil,
                                                     queue: .main) { [weak self] _ in
            self?.handleLifecyclePause(trigger: .sceneWillResignActive)
        }
        let appWillResign = center.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.handleLifecyclePause(trigger: .applicationWillResignActive)
        }
        lifecycleObservers.append(sceneWillDeactivate)
        lifecycleObservers.append(appWillResign)
    }
    
    private func unregisterLifecycleNotifications() {
        guard !lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers.forEach { center.removeObserver($0) }
        lifecycleObservers.removeAll()
    }
    
    private func handleLifecyclePause(trigger _: LifecyclePauseTrigger) {
        guard let state = gameState,
              state.hasStarted,
              !state.isGameOver,
              !state.isPaused else {
            return
        }
        dragInputActive = false
        glidePrimed = false
        dragMomentumVelocity = 0
        lastDragTouchX = nil
        lastDragTouchTime = nil
        state.pauseGame()
        
        // Let peers know our current state before the app fully pauses.
        multiplayerManager?.sendImmediatePlayerStateUpdate()
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
        
        guard let state = gameState else { return }
        let isLobby = lobbyWarmupActive()
        
        // Update game state time unless we're idling in a multiplayer lobby.
        if state.hasStarted && !state.isPaused && !state.isGameOver {
            if !isLobby {
                state.updateTime(delta: deltaTime)
            } else {
                multiplayerState?.updateLobbyCountdown()
            }
        }
        
        // Skip update if game hasn't started, is paused, or is over
        guard state.hasStarted,
              !state.isPaused,
              !state.isGameOver else {
            return
        }
        
        updateGameLogic(deltaTime: deltaTime, isLobby: isLobby)
    }
    
    // MARK: - Game Logic
    
    /// Returns true when we're idling in a multiplayer lobby prior to the official start time.
    private func lobbyWarmupActive() -> Bool {
        guard let state = gameState,
              state.mode.isMultiplayer,
              let startTime = matchStartTime,
              multiplayerState?.lobbyState != nil else {
            return false
        }
        
        let now = Date().timeIntervalSince1970
        if now >= startTime {
            multiplayerState?.clearLobby()
            return false
        }
        
        multiplayerState?.updateLobbyCountdown(now: now)
        return true
    }
    
    private func updateGameLogic(deltaTime: TimeInterval, isLobby: Bool) {
        updatePlayerMovement(deltaTime: deltaTime)
        
        // Update multiplayer-specific logic
        if isMultiplayerMode {
            updateRemotePlayers(deltaTime: deltaTime)
            multiplayerSlowMotion.update(deltaTime: deltaTime)
            broadcastLocalPlayerState()
        }
        
        // While in the lobby, allow free movement but skip spawning/scoring.
        if isLobby {
            return
        }
        
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
        var dt = max(CGFloat(deltaTime), 0.0001)
        
        // In multiplayer, apply slow-motion to the local player if they're NOT the collector
        if isMultiplayerMode && multiplayerSlowMotion.isActive {
            if let localId = localPlayerId {
                let speedMult = multiplayerSlowMotion.speedMultiplier(for: localId)
                if speedMult < 1.0 {
                    // Slow down the player's effective movement speed (not time, but responsiveness)
                    // This makes the slowed player feel sluggish compared to the collector
                    dt *= speedMult
                }
            }
        }
        
        func applyMomentumMovement() -> Bool {
            guard glidePrimed, dragMomentumVelocity != 0 else { return false }
            let decay = exp(-dragMomentumDecayRate * dt)
            let decayedVelocity = dragMomentumVelocity * decay
            let preservedMagnitude = max(abs(decayedVelocity), glideMinimumSpeed)
            let direction: CGFloat = decayedVelocity >= 0 ? 1 : -1
            let preservedVelocity = max(-maxSpeed, min(maxSpeed, preservedMagnitude * direction))
            dragMomentumVelocity = preservedVelocity
            velocityX = preservedVelocity
            handleDirectionChangeIfNeeded()
            let newX = clampWithinHorizontalBounds(player.position.x + preservedVelocity * dt)
            player.position.x = newX
            targetX = newX // Keep drag target aligned when switching back to input
            return true
        }
        
        if dragInputActive {
            let diff = targetX - currentX
            let lerpFactor = min(1.0, moveSpeed * dt)
            velocityX = diff * lerpFactor / dt
            velocityX = max(-maxSpeed, min(maxSpeed, velocityX))
            // Blend toward the finger's measured velocity so release momentum matches the drag feel.
            let blendedVelocity = (velocityX * 0.45) + (recentDragVelocity * 0.55)
            dragMomentumVelocity = max(-maxSpeed, min(maxSpeed, blendedVelocity))
            glidePrimed = glidePrimed || abs(velocityX) > 0
            handleDirectionChangeIfNeeded()
            let newX = clampWithinHorizontalBounds(currentX + velocityX * dt)
            player.position.x = newX
        } else if settings?.tiltControlEnabled == true {
            let tiltVelocity = resolveTiltVelocity(deltaTime: deltaTime)
            if abs(tiltVelocity) > dragMomentumStopThreshold {
                velocityX = tiltVelocity
                dragMomentumVelocity = tiltVelocity
                glidePrimed = true
                handleDirectionChangeIfNeeded()
                let newX = clampWithinHorizontalBounds(currentX + tiltVelocity * dt)
                player.position.x = newX
                targetX = newX // Keep drag target aligned when switching back
            } else if !applyMomentumMovement() {
                filteredTiltVelocity = 0
                velocityX = 0
                dragMomentumVelocity = 0
                glidePrimed = false
            }
        } else if !applyMomentumMovement() {
            filteredTiltVelocity = 0
            velocityX = 0
            dragMomentumVelocity = 0
            glidePrimed = false
        }
        
        // Apply edge squish effect when hitting screen bounds
        updateEdgeSquish(deltaTime: deltaTime)
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
        
        // In multiplayer, obstacles slow down when any player has slow-motion active
        // In single-player, use the local slow-motion effect
        let slowMultiplier: Double
        if isMultiplayerMode && multiplayerSlowMotion.isActive {
            // Obstacles always slow down during multiplayer slow-motion
            slowMultiplier = Double(multiplayerSlowMotion.slowSpeedScale)
        } else {
            slowMultiplier = Double(slowMotionEffect.speedMultiplier)
        }
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
        
        // Track edge-riding behavior
        updateEdgeLingerTracking(deltaTime: deltaTime)
        
        // Increment spawn timer
        spawnState.obstacleSpawnTimer += deltaTime
        
        // Check if it's time to spawn a new obstacle
        guard spawnState.obstacleSpawnTimer >= spawnState.nextObstacleSpawnInterval else { return }
        
        // Reset timer
        spawnState.obstacleSpawnTimer = 0
        
        // Get difficulty (0.0 to 1.0) and apply difficulty ramp multiplier
        let baseDifficulty = gameState?.difficulty ?? 0.0
        let difficultyMultiplier = settings?.difficultyMultiplier ?? 1.0
        let difficulty = CGFloat(min(1.0, baseDifficulty * difficultyMultiplier))
        let currentTime = gameState?.elapsed ?? 0
        
        // Update next spawn interval using randomizer
        let baseInterval = arenaRandomizer.nextObstacleSpawnInterval(difficulty: difficulty)
        let intervalWithGovernor = baseInterval * performanceGovernor.spawnIntervalMultiplier
        spawnState.nextObstacleSpawnInterval = intervalWithGovernor
        
        // Determine if we should spawn an edge-punishing obstacle
        var tempRng = arenaRandomizer.isMultiplayer 
            ? SeededRandomNumberGenerator(seed: UInt64(currentTime * 1000))
            : SeededRandomNumberGenerator(seed: UInt64.random(in: 0...UInt64.max))
        let shouldPunishEdge = spawnState.shouldSpawnEdgePunish(using: &tempRng)
        
        // Generate spawn event using ArenaRandomizer
        let event: ObstacleSpawnEvent
        if shouldPunishEdge {
            event = arenaRandomizer.nextObstacleEvent(
                currentTime: currentTime,
                difficulty: difficulty,
                isEdgePunish: true,
                edgeSide: spawnState.lastEdgeSide.toEventEdgeSide
            )
        } else {
            event = arenaRandomizer.nextObstacleEvent(
                currentTime: currentTime,
                difficulty: difficulty
            )
        }
        
        // Spawn the obstacle from the event
        spawnObstacleFromEvent(event)
    }
    
    /// Spawns an obstacle from a spawn event (used for both local and multiplayer sync).
    private func spawnObstacleFromEvent(_ event: ObstacleSpawnEvent) {
        let height = obstacleConfig.height
        
        // Get theme colors for obstacles, default to hot pink
        let obstacleColors = settings?.colorTheme.obstacleColor ?? 
                            (core: (1.0, 0.1, 0.6), glow: (1.0, 0.35, 0.75))
        
        let obstacle = event.spawnObstacle(
            pool: obstaclePool,
            sceneSize: size,
            margin: 20.0,
            height: height,
            coreColor: obstacleColors.core,
            glowColor: obstacleColors.glow,
            glowEnabled: glowEffectsEnabledCache
        )
        
        // Add to scene and tracking array
        if obstacle.parent !== self {
            addChild(obstacle)
        }
        obstacles.append(obstacle)
    }
    
    // MARK: - Edge-Riding Prevention
    
    private func updateEdgeLingerTracking(deltaTime: TimeInterval) {
        guard let player = player else {
            spawnState.edgeLingerTime = 0
            spawnState.lastEdgeSide = .none
            return
        }
        
        spawnState.updateEdgeTracking(
            playerX: player.position.x,
            margin: movementHorizontalMargin,
            sceneWidth: size.width,
            deltaTime: deltaTime
        )
    }
    
    
    private func updatePowerUps(deltaTime: TimeInterval) {
        // Update pulse phase for expiry warning animation
        updatePowerUpPulsePhase(deltaTime: deltaTime)
        
        slowMotionEffect.update(deltaTime: deltaTime)
        updateSlowMotionOverlay(deltaTime: deltaTime)
        
        invincibilityEffect.update(deltaTime: deltaTime)
        updateInvincibilityOverlay(deltaTime: deltaTime)
        
        attackModeEffect.update(deltaTime: deltaTime)
        updateAttackModeOverlay(deltaTime: deltaTime)
        
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
        let isMultiplayer = arenaRandomizer.isMultiplayer
        
        // Build active power-up counter
        let activePowerUpCount = ActivePowerUpCounter(
            slowMotionActive: slowMotionEffect.isActive,
            invincibilityActive: invincibilityEffect.isActive,
            attackModeActive: attackModeEffect.isActive
        )
        
        // In single-player: don't spawn if any power-up is active
        // In multiplayer: allow stacking up to the configured limit
        if !isMultiplayer {
            guard !activePowerUpCount.anyActive else {
                spawnState.powerUpSpawnTimer = 0
                return
            }
        }
        
        guard difficulty >= spawnState.powerUpDifficultyThreshold else {
            // Hold timer at zero until the game ramps up enough.
            spawnState.powerUpSpawnTimer = 0
            return
        }
        
        guard powerUps.isEmpty else { return }
        
        spawnState.powerUpSpawnTimer += deltaTime
        guard spawnState.powerUpSpawnTimer >= spawnState.nextPowerUpSpawnInterval else { return }
        
        // Check if we can spawn using the randomizer
        let currentTime = gameState?.elapsed ?? 0
        guard let event = arenaRandomizer.nextPowerUpEventIfNeeded(
            currentTime: currentTime,
            difficulty: difficulty,
            activePowerUpCount: activePowerUpCount.count,
            anyPowerUpActive: activePowerUpCount.anyActive
        ) else {
            return
        }
        
        spawnState.powerUpSpawnTimer = 0
        spawnState.scheduleNextPowerUpSpawn()
        spawnPowerUpFromEvent(event)
    }
    
    /// Spawns a power-up from a spawn event (used for both local and multiplayer sync).
    private func spawnPowerUpFromEvent(_ event: PowerUpSpawnEvent) {
        guard size.width.isFinite, size.height.isFinite else { return }
        
        let horizontalMargin = max(movementHorizontalMargin, event.radius + 24)
        let colors = powerUpThemeColors(for: event.type.toPowerUpType)
        
        let powerUp = event.spawnPowerUp(
            sceneSize: size,
            margin: horizontalMargin,
            ringColor: colors.ring,
            glowColor: colors.glow
        )
        
        addChild(powerUp)
        powerUps.append(powerUp)
    }
    
    private func powerUpThemeColors(for type: PowerUpType) -> (ring: SKColor, glow: SKColor) {
        let theme = settings?.colorTheme
        let themeColors: (ring: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))
        
        switch type {
        case .slowMotion:
            themeColors = theme?.powerUpColor ?? (ring: (0.1, 1.0, 0.8), glow: (0.3, 1.0, 0.85))
        case .invincibility:
            themeColors = theme?.invincibilityColor ?? (ring: (1.0, 0.95, 0.8), glow: (1.0, 1.0, 0.9))
        case .attackMode:
            themeColors = theme?.attackModeColor ?? (ring: (1.0, 0.4, 0.1), glow: (1.0, 0.5, 0.2))
        }

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
            overlay.strokeColor = powerUpThemeColors(for: .slowMotion).glow
            
            // Apply warning pulse if about to expire
            let targetAlpha = calculateOverlayAlpha(remaining: slowMotionEffect.remaining)
            overlay.alpha = min(targetAlpha, overlay.alpha + slowMotionOverlayFadeInRate * dt)
        } else if let overlay = slowMotionOverlay {
            overlay.alpha = max(0, overlay.alpha - slowMotionOverlayFadeOutRate * dt)
            if overlay.alpha <= 0.01 {
                clearSlowMotionOverlay()
            }
        }
    }
    
    private func activateSlowMotionOverlayImmediately() {
        let overlay = ensureSlowMotionOverlay()
        overlay.strokeColor = powerUpThemeColors(for: .slowMotion).glow
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

    private func updateInvincibilityOverlay(deltaTime: TimeInterval) {
        let dt = CGFloat(max(0, min(deltaTime, 1)))
        
        if invincibilityEffect.isActive {
            let overlay = ensureInvincibilityOverlay()
            updateInvincibilityOverlayGeometry()
            overlay.strokeColor = powerUpThemeColors(for: .invincibility).glow
            
            // Apply warning pulse if about to expire
            let targetAlpha = calculateOverlayAlpha(remaining: invincibilityEffect.remaining)
            overlay.alpha = min(targetAlpha, overlay.alpha + slowMotionOverlayFadeInRate * dt)
        } else if let overlay = invincibilityOverlay {
            overlay.alpha = max(0, overlay.alpha - slowMotionOverlayFadeOutRate * dt)
            if overlay.alpha <= 0.01 {
                clearInvincibilityOverlay()
            }
        }
    }
    
    private func activateInvincibilityOverlayImmediately() {
        let overlay = ensureInvincibilityOverlay()
        overlay.strokeColor = powerUpThemeColors(for: .invincibility).glow
        updateInvincibilityOverlayGeometry()
        overlay.alpha = slowMotionOverlayMaxAlpha
    }
    
    private func ensureInvincibilityOverlay() -> SKShapeNode {
        if let overlay = invincibilityOverlay {
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
        invincibilityOverlay = overlay
        return overlay
    }
    
    private func updateInvincibilityOverlayGeometry() {
        guard let overlay = invincibilityOverlay,
              size.width.isFinite,
              size.height.isFinite else { return }
        
        let inset: CGFloat = 14
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        let rect = CGRect(x: -width / 2,
                          y: -height / 2,
                          width: width,
                          height: height)
        // Use same corner radius as slow motion overlay for consistency
        overlay.path = CGPath(roundedRect: rect,
                              cornerWidth: 42,
                              cornerHeight: 42,
                              transform: nil)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    
    private func clearInvincibilityOverlay() {
        invincibilityOverlay?.removeFromParent()
        invincibilityOverlay = nil
    }

    private func updateAttackModeOverlay(deltaTime: TimeInterval) {
        let dt = CGFloat(max(0, min(deltaTime, 1)))
        
        if attackModeEffect.isActive {
            let overlay = ensureAttackModeOverlay()
            updateAttackModeOverlayGeometry()
            overlay.strokeColor = powerUpThemeColors(for: .attackMode).glow
            
            // Apply warning pulse if about to expire
            let targetAlpha = calculateOverlayAlpha(remaining: attackModeEffect.remaining)
            overlay.alpha = min(targetAlpha, overlay.alpha + slowMotionOverlayFadeInRate * dt)
        } else if let overlay = attackModeOverlay {
            overlay.alpha = max(0, overlay.alpha - slowMotionOverlayFadeOutRate * dt)
            if overlay.alpha <= 0.01 {
                clearAttackModeOverlay()
            }
        }
    }
    
    private func activateAttackModeOverlayImmediately() {
        let overlay = ensureAttackModeOverlay()
        overlay.strokeColor = powerUpThemeColors(for: .attackMode).glow
        updateAttackModeOverlayGeometry()
        overlay.alpha = slowMotionOverlayMaxAlpha
    }
    
    private func ensureAttackModeOverlay() -> SKShapeNode {
        if let overlay = attackModeOverlay {
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
        attackModeOverlay = overlay
        return overlay
    }
    
    private func updateAttackModeOverlayGeometry() {
        guard let overlay = attackModeOverlay,
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
    
    private func clearAttackModeOverlay() {
        attackModeOverlay?.removeFromParent()
        attackModeOverlay = nil
    }
    
    /// Calculates overlay alpha with pulsing effect when power-up is about to expire.
    private func calculateOverlayAlpha(remaining: TimeInterval) -> CGFloat {
        guard remaining <= powerUpWarningThreshold else {
            return slowMotionOverlayMaxAlpha
        }
        
        // Pulse faster as time runs out (3Hz to 6Hz)
        let urgency = 1.0 - (remaining / powerUpWarningThreshold)
        let pulseSpeed: CGFloat = 3.0 + CGFloat(urgency) * 3.0
        
        // Use sine wave for smooth pulsing between 0.4 and max alpha
        let pulseValue = sin(powerUpPulsePhase * pulseSpeed * 2 * .pi)
        let minAlpha: CGFloat = 0.4
        let alphaRange = slowMotionOverlayMaxAlpha - minAlpha
        
        return minAlpha + alphaRange * ((pulseValue + 1.0) / 2.0)
    }
    
    private func updatePowerUpPulsePhase(deltaTime: TimeInterval) {
        // Advance pulse phase (wraps around every second)
        powerUpPulsePhase += CGFloat(deltaTime)
        if powerUpPulsePhase > 1.0 {
            powerUpPulsePhase -= 1.0
        }
    }
    
    // MARK: - Collision Handling
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Check if collision involves player and obstacle or power-up
        let collision = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        if collision == PhysicsCategory.player | PhysicsCategory.obstacle {
            let obstacleNode = (contact.bodyA.node as? ObstacleNode) ?? (contact.bodyB.node as? ObstacleNode)
            handleCollision(with: obstacleNode)
        } else if collision == PhysicsCategory.player | PhysicsCategory.powerUp {
            if let node = (contact.bodyA.node as? PowerUpNode) ?? (contact.bodyB.node as? PowerUpNode) {
                handlePowerUpCollection(node)
            }
        }
    }
    
    private func handleCollision(with obstacle: ObstacleNode?) {
        // Prevent multiple collision triggers
        guard let state = gameState, !state.isGameOver else { return }
        
        // If invincible, ignore collision
        if invincibilityEffect.isActive {
            return
        }
        
        // If attack mode is active, destroy the obstacle and award points
        if attackModeEffect.isActive, let obstacle = obstacle {
            destroyObstacle(obstacle)
            state.addDodge(points: attackModeDestroyPoints)
            return
        }
        
        // Trigger game over
        state.isGameOver = true
        state.recordBest()
        slowMotionEffect.reset()
        invincibilityEffect.reset()
        attackModeEffect.reset()
        multiplayerSlowMotion.reset()
        clearSlowMotionOverlay()
        clearInvincibilityOverlay()
        clearAttackModeOverlay()
        performCollisionFeedback()
        
        // Notify MultiplayerManager if in multiplayer mode
        if isMultiplayerMode {
            let eliminationTime = state.elapsed
            multiplayerManager?.localPlayerDied(
                finalScore: state.score,
                eliminationTime: eliminationTime
            )
        }
    }
    
    private func destroyObstacle(_ obstacle: ObstacleNode) {
        guard let index = obstacles.firstIndex(where: { $0 === obstacle }) else { return }
        obstacles.remove(at: index)
        
        // Play destruction animation
        obstacle.physicsBody = nil
        let scale = SKAction.scale(to: 1.3, duration: 0.12)
        scale.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 0.1)
        fade.timingMode = .easeIn
        let cleanup = SKAction.run { [weak obstacle] in
            obstacle?.removeFromParent()
        }
        obstacle.run(SKAction.sequence([
            SKAction.group([scale, fade]),
            cleanup
        ]))
        
        // Feedback
        Haptics.playNearMissImpact(intensity: 0.7)
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
        
        // In multiplayer, check for exclusivity before collecting
        if isMultiplayerMode {
            // Find the power-up ID from our tracker
            let powerUpId = findPowerUpId(for: powerUp)
            
            // Check if already collected by another player
            if let id = powerUpId, powerUpTracker.isCollected(id: id) {
                // Already collected by someone else - don't process
                return
            }
            
            // Try to claim the power-up
            if let id = powerUpId,
               let manager = multiplayerManager,
               !manager.tryCollectPowerUp(powerUpId: id, type: powerUp.type) {
                // Someone else got it first - don't process
                return
            }
            
            // Mark as collected in our tracker
            if let id = powerUpId {
                _ = powerUpTracker.markCollected(id: id)
            }
        }
        
        powerUps.remove(at: index)
        
        switch powerUp.type {
        case .slowMotion:
            if isMultiplayerMode {
                // In multiplayer, use multiplayer slow-motion where collector keeps normal speed
                if let localId = localPlayerId {
                    multiplayerSlowMotion.activate(collectorId: localId, duration: slowMotionEffect.remaining > 0 ? slowMotionEffect.remaining + 6.0 : 6.0)
                    // Notify other players
                    multiplayerManager?.localPlayerActivatedSlowMotion(
                        duration: 6.0,
                        stackedDuration: multiplayerSlowMotion.remaining
                    )
                }
            } else {
                slowMotionEffect.trigger()
            }
            activateSlowMotionOverlayImmediately()
            showPowerUpLabel("Slow-Motion", type: .slowMotion)
            
        case .invincibility:
            invincibilityEffect.trigger()
            activateInvincibilityOverlayImmediately()
            showPowerUpLabel("Invincibility", type: .invincibility)
            
        case .attackMode:
            attackModeEffect.trigger()
            activateAttackModeOverlayImmediately()
            showPowerUpLabel("Attack", type: .attackMode)
        }
        
        Haptics.playNearMissImpact(intensity: 0.9)
        
        powerUp.playCollectionAnimation { [weak powerUp] in
            powerUp?.removeFromParent()
        }
    }
    
    /// Finds the power-up ID for a given node by checking registered power-ups.
    private func findPowerUpId(for powerUp: PowerUpNode) -> String? {
        // Use the tracker's reverse lookup
        if let id = powerUpTracker.findId(for: powerUp) {
            return id
        }
        // Fallback: generate an ID based on position and type
        // This ensures single-player mode still works
        return "powerup_\(Int(powerUp.position.x))_\(Int(powerUp.position.y))_\(powerUp.type)"
    }
    
    // MARK: - Power-Up Label
    
    private func showPowerUpLabel(_ text: String, type: PowerUpType) {
        guard let player = player else { return }
        
        // Remove any existing power-up label
        childNode(withName: "powerUpLabel")?.removeFromParent()
        
        // Get the color for this power-up type
        let colors = powerUpThemeColors(for: type)
        
        // Create the label
        let label = SKLabelNode(text: text)
        label.name = "powerUpLabel"
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 24
        label.fontColor = colors.glow
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 600
        
        // Position above the player
        let labelY = player.position.y + playerRadius + 50
        label.position = CGPoint(x: player.position.x, y: labelY)
        
        // Start invisible and scaled down
        label.alpha = 0
        label.setScale(0.5)
        
        addChild(label)
        
        // Animate in: scale up and fade in
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.2)
        scaleUp.timingMode = .easeOut
        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let appearGroup = SKAction.group([scaleUp, fadeIn])
        
        // Float upward slightly while visible
        let floatUp = SKAction.moveBy(x: 0, y: 20, duration: 1.8)
        floatUp.timingMode = .easeOut
        
        // Hold visible
        let hold = SKAction.wait(forDuration: 1.5)
        
        // Fade out
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        fadeOut.timingMode = .easeIn
        
        // Clean up
        let remove = SKAction.removeFromParent()
        
        // Run the sequence
        let sequence = SKAction.sequence([
            appearGroup,
            SKAction.group([hold, floatUp]),
            fadeOut,
            remove
        ])
        
        label.run(sequence)
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
    
    // MARK: - Edge Squish Effect
    
    private func updateEdgeSquish(deltaTime: TimeInterval) {
        guard let player = player else { return }
        
        // Skip if a direction squash animation is actively playing
        if player.action(forKey: "directionSquash") != nil {
            currentEdgeSquish = 0
            edgeBounceActive = false
            edgeBounceVelocity = 0
            return
        }
        
        let dt = CGFloat(max(0.0001, deltaTime))
        let playerX = player.position.x
        let bounds = horizontalBounds()
        let edgeTolerance: CGFloat = 2.0  // Consider "at edge" within 2 points
        
        let atLeftEdge = playerX <= bounds.min + edgeTolerance
        let atRightEdge = playerX >= bounds.max - edgeTolerance
        
        // Check for new edge collision (hitting the edge with velocity)
        var justHitEdge = false
        var impactVelocity: CGFloat = 0
        
        if atLeftEdge && velocityX < -edgeSquishVelocityThreshold && lastEdgeHitSide != .left {
            // Just hit left edge
            justHitEdge = true
            impactVelocity = abs(velocityX)
            lastEdgeHitSide = .left
        } else if atRightEdge && velocityX > edgeSquishVelocityThreshold && lastEdgeHitSide != .right {
            // Just hit right edge
            justHitEdge = true
            impactVelocity = abs(velocityX)
            lastEdgeHitSide = .right
        } else if !atLeftEdge && !atRightEdge {
            // Moved away from edges
            lastEdgeHitSide = .none
        }
        
        // Trigger bounce-back when hitting an edge
        if justHitEdge {
            let normalizedImpact = min(1.0, (impactVelocity - edgeSquishVelocityThreshold) /
                                       (edgeSquishMaxVelocity - edgeSquishVelocityThreshold))
            // Set squish to peak immediately on impact
            currentEdgeSquish = normalizedImpact
            // Calculate bounce velocity (opposite to impact direction)
            let bounceDirection: CGFloat = lastEdgeHitSide == .left ? 1.0 : -1.0
            edgeBounceVelocity = impactVelocity * edgeBounceStrength * bounceDirection
            edgeBounceActive = true
            
            // Haptic feedback: lighter impact for wall hits, scaled by velocity
            // Range: 0.6 (gentle bump) to 1.0 (hard slam)
            let hapticIntensity = 0.6 + (normalizedImpact * 0.4)
            Haptics.playNearMissImpact(intensity: hapticIntensity)
        }
        
        // Apply bounce-back movement
        if edgeBounceActive {
            // Apply bounce velocity to player position
            let bounceMovement = edgeBounceVelocity * dt
            let newX = clampWithinHorizontalBounds(player.position.x + bounceMovement)
            player.position.x = newX
            targetX = newX  // Update target so drag doesn't fight the bounce
            dragMomentumVelocity = edgeBounceVelocity
            glidePrimed = glidePrimed || abs(edgeBounceVelocity) > 0
            
            // Decay the bounce velocity
            let decayFactor = exp(-edgeBounceDamping * dt)
            edgeBounceVelocity *= decayFactor
            
            // End bounce when velocity is negligible
            if abs(edgeBounceVelocity) < edgeBounceMinVelocity {
                edgeBounceVelocity = 0
                edgeBounceActive = false
            }
        }
        
        // Smoothly recover squish (always decay toward 0 now)
        let targetSquish: CGFloat = 0
        let recoveryLerpFactor = min(1.0, edgeSquishRecoverRate * dt)
        currentEdgeSquish = lerp(currentEdgeSquish, targetSquish, recoveryLerpFactor)
        
        // Clamp very small values to 0
        if currentEdgeSquish < 0.01 {
            currentEdgeSquish = 0
        }
        
        // Apply the squish effect to scale
        // When squished: X gets smaller, Y gets taller (like squishing against a wall)
        let scaleX = lerp(1.0, edgeSquishMaxScale, currentEdgeSquish)
        let scaleY = lerp(1.0, edgeSquishStretchScale, currentEdgeSquish)
        
        player.xScale = scaleX
        player.yScale = scaleY
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
            let location = touch.location(in: self)
            lastDragTouchX = location.x
            lastDragTouchTime = touch.timestamp
            recentDragVelocity = 0
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
            let location = touch.location(in: self)
            if let lastX = lastDragTouchX, let lastTime = lastDragTouchTime {
                let dt = max(touch.timestamp - lastTime, 0.0001)
                let dx = location.x - lastX
                recentDragVelocity = dx / CGFloat(dt)
            }
            lastDragTouchX = location.x
            lastDragTouchTime = touch.timestamp
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
        // Prefer touch-driven velocity so release feels true to finger speed.
        let releaseVelocity = abs(recentDragVelocity) > abs(velocityX) ? recentDragVelocity : velocityX
        dragMomentumVelocity = releaseVelocity
        glidePrimed = glidePrimed || abs(releaseVelocity) > 0
        dragInputActive = false
        lastDragTouchX = nil
        lastDragTouchTime = nil
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragInputActive = false
        glidePrimed = false
        dragMomentumVelocity = 0
        lastDragTouchX = nil
        lastDragTouchTime = nil
        super.touchesCancelled(touches, with: event)
    }
    
    // MARK: - Public Methods
    
    // MARK: Multiplayer Spawning Configuration
    
    /// Configures the scene for multiplayer with a shared seed.
    /// - Parameters:
    ///   - seed: The shared RNG seed for deterministic spawning.
    ///   - config: The multiplayer power-up configuration.
    func configureForMultiplayer(seed: UInt64, config: ArenaMultiplayerConfig = .default) {
        arenaRandomizer = ArenaRandomizer.multiplayer(seed: seed, config: config)
        multiplayerConfig = config
        externalEventStream = nil
    }
    
    /// Configures the scene to replay events from an external stream (client mode).
    /// - Parameter stream: The event stream provided by the host.
    func configureWithEventStream(_ stream: ArenaEventStream) {
        externalEventStream = stream
        arenaRandomizer = ArenaRandomizer.multiplayer(seed: stream.seed)
    }
    
    /// Resets the scene to single-player mode with a new random seed.
    func configureForSinglePlayer() {
        arenaRandomizer = ArenaRandomizer.singlePlayer()
        multiplayerConfig = nil
        externalEventStream = nil
    }
    
    /// Processes an externally received obstacle spawn event (for multiplayer clients).
    /// - Parameter event: The obstacle event to process.
    func processExternalObstacleEvent(_ event: ObstacleSpawnEvent) {
        spawnObstacleFromEvent(event)
    }
    
    /// Processes an externally received power-up spawn event (for multiplayer clients).
    /// - Parameter event: The power-up event to process.
    func processExternalPowerUpEvent(_ event: PowerUpSpawnEvent) {
        spawnPowerUpFromEvent(event)
    }
    
    /// Returns the current arena randomizer's seed (for host to broadcast).
    var currentArenaSeed: UInt64 {
        arenaRandomizer.seed
    }
    
    // MARK: - Multiplayer Arena Configuration
    
    /// Configures the scene for a multiplayer match with multiple players.
    /// Creates player nodes for all participants and initializes the deterministic arena.
    ///
    /// - Parameters:
    ///   - players: Summary of all players in the match.
    ///   - localPlayerId: The local player's unique identifier.
    ///   - seed: Shared RNG seed for deterministic spawning.
    ///   - startTime: Match start time for synchronization.
    ///   - manager: The multiplayer manager for communication.
    func configureMultiplayerArena(
        players: [MultiplayerPlayerSummary],
        localPlayerId: String,
        seed: UInt64,
        startTime: TimeInterval,
        manager: MultiplayerManager
    ) {
        guard !players.isEmpty else { return }
        
        self.localPlayerId = localPlayerId
        self.matchStartTime = startTime
        self.multiplayerManager = manager
        
        // Configure deterministic arena with shared seed
        configureForMultiplayer(seed: seed)
        
        // Clear any existing multiplayer player nodes
        for (_, context) in playerNodes {
            if !context.isLocal {
                context.node.removeFromParent()
            }
        }
        playerNodes.removeAll()
        
        // Reset multiplayer state
        multiplayerSlowMotion.reset()
        powerUpTracker.reset()
        multiplayerFrameCounter = 0
        
        // Calculate starting positions - spread players horizontally
        let playerCount = players.count
        let usableWidth = size.width - (movementHorizontalMargin * 2)
        let spacing = usableWidth / CGFloat(playerCount + 1)
        let playerY = size.height * playerVerticalPositionRatio
        
        // Create nodes for all players
        for (index, playerSummary) in players.enumerated() {
            let isLocal = playerSummary.id == localPlayerId
            let startX = movementHorizontalMargin + spacing * CGFloat(index + 1)
            let colors = MultiplayerPlayerColors.colorsForPlayer(index: index)
            
            let playerNode: SKShapeNode
            if isLocal {
                // Use the existing player node for the local player
                if let existingPlayer = player {
                    playerNode = existingPlayer
                    // Update colors to match multiplayer scheme
                    updatePlayerNodeColors(playerNode, colors: colors)
                } else {
                    playerNode = createPlayerNode(colors: colors)
                    player = playerNode
                    addChild(playerNode)
                }
                playerNode.position = CGPoint(x: startX, y: playerY)
                targetX = startX
            } else {
                // Create a new node for remote players
                playerNode = createRemotePlayerNode(colors: colors)
                playerNode.position = CGPoint(x: startX, y: playerY)
                addChild(playerNode)
            }
            
            let context = PlayerNodeContext(
                id: playerSummary.id,
                isLocal: isLocal,
                node: playerNode,
                displayName: playerSummary.displayName,
                colorHueOffset: CGFloat(index) / CGFloat(playerCount),
                colors: colors
            )
            playerNodes[playerSummary.id] = context
        }
    }
    
    /// Creates a player node with the specified colors.
    private func createPlayerNode(colors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: playerRadius)
        
        let coreColor = SKColor(red: colors.core.0, green: colors.core.1, blue: colors.core.2, alpha: 1.0)
        node.strokeColor = .clear
        node.fillColor = coreColor
        node.lineWidth = 0
        
        if glowEffectsEnabledCache {
            let glowColor = SKColor(red: colors.glow.0, green: colors.glow.1, blue: colors.glow.2, alpha: 1.0)
            let glowNode = GlowEffectFactory.makeCircularGlow(
                radius: playerRadius,
                color: glowColor,
                blurRadius: 18,
                alpha: 0.9,
                scale: 1.45
            )
            glowNode.zPosition = -1
            node.addChild(glowNode)
            
            let innerBloom = GlowEffectFactory.makeCircularGlow(
                radius: playerRadius * 0.55,
                color: coreColor,
                blurRadius: 8,
                alpha: 0.75,
                scale: 1.12
            )
            innerBloom.zPosition = -0.5
            node.addChild(innerBloom)
        }
        
        setupPlayerPhysics(radius: playerRadius)
        return node
    }
    
    /// Creates a remote player node (slightly transparent to distinguish from local).
    private func createRemotePlayerNode(colors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: playerRadius)
        
        let coreColor = SKColor(red: colors.core.0, green: colors.core.1, blue: colors.core.2, alpha: 0.85)
        node.strokeColor = .clear
        node.fillColor = coreColor
        node.lineWidth = 0
        node.alpha = 0.8 // Slightly transparent for remote players
        node.zPosition = 90 // Behind local player
        
        if glowEffectsEnabledCache {
            let glowColor = SKColor(red: colors.glow.0, green: colors.glow.1, blue: colors.glow.2, alpha: 1.0)
            let glowNode = GlowEffectFactory.makeCircularGlow(
                radius: playerRadius,
                color: glowColor,
                blurRadius: 14,
                alpha: 0.7,
                scale: 1.35
            )
            glowNode.zPosition = -1
            node.addChild(glowNode)
        }
        
        // No physics body for remote players - they're just visual representations
        return node
    }
    
    /// Updates an existing player node's colors.
    private func updatePlayerNodeColors(_ node: SKShapeNode, colors: (core: (CGFloat, CGFloat, CGFloat), glow: (CGFloat, CGFloat, CGFloat))) {
        let coreColor = SKColor(red: colors.core.0, green: colors.core.1, blue: colors.core.2, alpha: 1.0)
        node.fillColor = coreColor
        
        removeGlowNodes(from: node)
        guard glowEffectsEnabledCache else { return }
        
        let glowColor = SKColor(red: colors.glow.0, green: colors.glow.1, blue: colors.glow.2, alpha: 1.0)
        let glowNode = GlowEffectFactory.makeCircularGlow(
            radius: playerRadius,
            color: glowColor,
            blurRadius: 18,
            alpha: 0.9,
            scale: 1.45
        )
        glowNode.zPosition = -1
        node.addChild(glowNode)
        
        let innerBloom = GlowEffectFactory.makeCircularGlow(
            radius: playerRadius * 0.55,
            color: coreColor,
            blurRadius: 8,
            alpha: 0.75,
            scale: 1.12
        )
        innerBloom.zPosition = -0.5
        node.addChild(innerBloom)
    }
    
    // MARK: - MultiplayerSceneDelegate Implementation
    
    /// Configure scene for multiplayer with shared seed.
    func configureForMultiplayer(seed: UInt64, startTime: TimeInterval) {
        matchStartTime = startTime
        configureForMultiplayer(seed: seed)
    }
    
    /// Update a remote player's position with smooth interpolation.
    func updateRemotePlayerPosition(playerId: String, x: CGFloat, velocityX: CGFloat) {
        guard var context = playerNodes[playerId], !context.isLocal else { return }
        context.targetX = x
        context.velocityX = velocityX
        playerNodes[playerId] = context
    }
    
    /// Mark a power-up as collected and remove it from the scene.
    func markPowerUpCollected(powerUpId: String) {
        if let powerUpNode = powerUpTracker.markCollected(id: powerUpId) {
            // Remove from our tracking array
            if let index = powerUps.firstIndex(where: { $0 === powerUpNode }) {
                powerUps.remove(at: index)
            }
            // Animate removal
            powerUpNode.playCollectionAnimation { [weak powerUpNode] in
                powerUpNode?.removeFromParent()
            }
        }
    }
    
    /// Apply multiplayer slow-motion where the collector keeps normal speed.
    func applyMultiplayerSlowMotion(collectorId: String, duration: TimeInterval, isLocalPlayerCollector: Bool) {
        multiplayerSlowMotion.activate(collectorId: collectorId, duration: duration)
        
        // If local player is the collector, they see the standard slow-mo overlay
        // If not, show a different visual indicator that someone else got it
        if isLocalPlayerCollector {
            activateSlowMotionOverlayImmediately()
        }
    }
    
    /// Process an external power-up spawn event with tracking ID.
    func processExternalPowerUpEvent(_ event: PowerUpSpawnEvent, powerUpId: String) {
        spawnPowerUpFromEvent(event)
        
        // Register the newly spawned power-up with its ID for exclusivity tracking
        if let lastPowerUp = powerUps.last {
            powerUpTracker.register(powerUp: lastPowerUp, id: powerUpId)
        }
    }
    
    /// The local player's current X position for state updates.
    var localPlayerPositionX: CGFloat {
        player?.position.x ?? size.width / 2
    }
    
    /// The local player's current X velocity for state updates.
    var localPlayerVelocityX: CGFloat {
        velocityX
    }
    
    // MARK: - Multiplayer Update Helpers
    
    /// Updates remote player positions with interpolation.
    /// Called each frame during multiplayer gameplay.
    func updateRemotePlayers(deltaTime: TimeInterval) {
        guard isMultiplayerMode else { return }
        
        let dt = CGFloat(deltaTime)
        
        for (playerId, context) in playerNodes {
            guard !context.isLocal, context.isAlive else { continue }
            
            let node = context.node
            let currentX = node.position.x
            let targetX = context.targetX
            let diff = targetX - currentX
            
            // Check if we should snap or interpolate
            if abs(diff) > RemotePlayerInterpolation.snapThreshold {
                // Snap to target position (large discrepancy)
                node.position.x = targetX
            } else {
                // Smooth interpolation
                let lerpFactor = min(1.0, RemotePlayerInterpolation.lerpRate * dt)
                node.position.x = currentX + diff * lerpFactor
            }
            
            // Note: We don't need to update playerNodes here since context is read-only
            // and the node position update is done directly on the SKShapeNode reference.
            // The context.targetX/velocityX are updated by updateRemotePlayerPosition().
            _ = playerId // Silence unused variable warning (kept for clarity)
        }
    }
    
    /// Broadcasts the local player's state to other players.
    /// Called periodically during multiplayer gameplay.
    func broadcastLocalPlayerState() {
        guard isMultiplayerMode,
              multiplayerManager != nil,
              let state = gameState,
              !state.isGameOver else { return }
        
        multiplayerFrameCounter += 1
        guard multiplayerFrameCounter >= positionUpdateFrameInterval else { return }
        multiplayerFrameCounter = 0
        
        // The manager handles the actual broadcast via its state update timer
        // This is here as a hook if we need frame-synchronized updates
    }
    
    /// Marks a remote player as dead with a visual effect.
    func markRemotePlayerDead(playerId: String) {
        guard var context = playerNodes[playerId], !context.isLocal else { return }
        context.isAlive = false
        playerNodes[playerId] = context
        
        // Visual death effect: fade out and tint red
        let node = context.node
        let tintRed = SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.2)
        let fadeOut = SKAction.fadeAlpha(to: 0.3, duration: 0.5)
        let scaleDown = SKAction.scale(to: 0.7, duration: 0.5)
        
        node.run(SKAction.group([tintRed, fadeOut, scaleDown]))
    }
    
    /// Cleans up multiplayer state when leaving a match.
    func cleanupMultiplayerArena() {
        // Remove remote player nodes
        for (_, context) in playerNodes {
            if !context.isLocal {
                context.node.removeFromParent()
            }
        }
        playerNodes.removeAll()
        
        // Reset multiplayer state
        localPlayerId = nil
        matchStartTime = nil
        multiplayerManager = nil
        multiplayerSlowMotion.reset()
        powerUpTracker.reset()
        multiplayerFrameCounter = 0
        
        // Restore single-player arena
        configureForSinglePlayer()
    }
    
    // MARK: Theme Updates
    
    /// Update glow nodes after the accessibility toggle changes.
    func updateGlowPreference(isEnabled: Bool) {
        guard glowEffectsEnabledCache != isEnabled else { return }
        glowEffectsEnabledCache = isEnabled
        applyGlowStateToPlayer()
        applyGlowStateToRemotePlayers()
        applyGlowStateToObstacles()
    }
    
    /// Update player colors based on current theme
    func updatePlayerColors() {
        guard let player = player else { return }
        
        // Get theme colors from settings, default to neon blue
        let colors = settings?.colorTheme.playerColor ?? fallbackPlayerColors
        
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
        
        removeGlowNodes(from: player)
        guard glowEffectsEnabledCache else { return }
        
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
            dragMomentumVelocity = 0
            glidePrimed = false
            currentEdgeSquish = 0
            edgeBounceVelocity = 0
            edgeBounceActive = false
            lastEdgeHitSide = .none
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
        slowMotionEffect.reset()
        invincibilityEffect.reset()
        attackModeEffect.reset()
        clearSlowMotionOverlay()
        clearInvincibilityOverlay()
        clearAttackModeOverlay()
        
        // Reset multiplayer state if applicable
        multiplayerSlowMotion.reset()
        powerUpTracker.reset()
        multiplayerFrameCounter = 0
        
        // Reset remote player nodes (keep them but reset state)
        for (playerId, var context) in playerNodes {
            if !context.isLocal {
                context.isAlive = true
                context.node.alpha = 0.8
                context.node.xScale = 1.0
                context.node.yScale = 1.0
                context.node.removeAllActions()
                // Reset position to starting position
                let playerY = size.height * playerVerticalPositionRatio
                context.node.position.y = playerY
                playerNodes[playerId] = context
            }
        }
        
        // Reset spawn state and randomizer
        spawnState.reset()
        arenaRandomizer.reset()
        
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
        unregisterLifecycleNotifications()
        stopDeviceMotionUpdates()
    }
}

// MARK: - Testing Hooks

extension GameScene {
    /// Exposes lifecycle pause logic to unit tests without depending on iOS notifications.
    func simulateLifecyclePauseForTesting() {
        handleLifecyclePause(trigger: .sceneWillResignActive)
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
