//
//  ArenaRandomizerTests.swift
//  HyprGlideTests
//
//  Tests for deterministic random number generation and arena spawn events.
//  These tests verify that the multiplayer synchronization primitives
//  produce identical results across separate instances given the same seed.
//

import XCTest
@testable import HyprGlide

final class ArenaRandomizerTests: XCTestCase {
    
    // MARK: - SeededRandomNumberGenerator Tests
    
    /// Verifies two RNG instances with the same seed produce identical UInt64 sequences.
    func testSeededRNGProducesIdenticalSequences() {
        let seed: UInt64 = 12345
        var rng1 = SeededRandomNumberGenerator(seed: seed)
        var rng2 = SeededRandomNumberGenerator(seed: seed)
        
        // Generate 100 values and verify they match exactly.
        for i in 0..<100 {
            let value1 = rng1.next()
            let value2 = rng2.next()
            XCTAssertEqual(value1, value2, "RNG values must match at iteration \(i)")
        }
    }
    
    /// Verifies that different seeds produce different sequences.
    func testDifferentSeedsProduceDifferentSequences() {
        var rng1 = SeededRandomNumberGenerator(seed: 1)
        var rng2 = SeededRandomNumberGenerator(seed: 2)
        
        let value1 = rng1.next()
        let value2 = rng2.next()
        
        XCTAssertNotEqual(value1, value2, "Different seeds should produce different first values")
    }
    
    /// Verifies randomDouble() produces values in [0, 1) range.
    func testRandomDoubleRange() {
        var rng = SeededRandomNumberGenerator(seed: 42)
        
        for _ in 0..<1000 {
            let value = rng.randomDouble()
            XCTAssertGreaterThanOrEqual(value, 0.0, "randomDouble() must be >= 0")
            XCTAssertLessThan(value, 1.0, "randomDouble() must be < 1")
        }
    }
    
    /// Verifies random(in:) for Double produces values within the specified range.
    func testRandomDoubleInRange() {
        var rng = SeededRandomNumberGenerator(seed: 99)
        let range: ClosedRange<Double> = 10.0...50.0
        
        for _ in 0..<1000 {
            let value = rng.random(in: range)
            XCTAssertGreaterThanOrEqual(value, range.lowerBound)
            XCTAssertLessThanOrEqual(value, range.upperBound)
        }
    }
    
    /// Verifies random(in:) for Int produces values within the specified range.
    func testRandomIntInRange() {
        var rng = SeededRandomNumberGenerator(seed: 777)
        let range: ClosedRange<Int> = 5...10
        
        for _ in 0..<1000 {
            let value = rng.random(in: range)
            XCTAssertGreaterThanOrEqual(value, range.lowerBound)
            XCTAssertLessThanOrEqual(value, range.upperBound)
        }
    }
    
    /// Verifies randomBool() returns both true and false over many iterations.
    func testRandomBoolDistribution() {
        var rng = SeededRandomNumberGenerator(seed: 555)
        var trueCount = 0
        var falseCount = 0
        
        for _ in 0..<1000 {
            if rng.randomBool(probability: 0.5) {
                trueCount += 1
            } else {
                falseCount += 1
            }
        }
        
        // With 50% probability and 1000 samples, we should get a reasonable distribution.
        XCTAssertGreaterThan(trueCount, 400, "Should have a fair number of true values")
        XCTAssertGreaterThan(falseCount, 400, "Should have a fair number of false values")
    }
    
    // MARK: - ArenaRandomizer Obstacle Tests
    
    /// Verifies two ArenaRandomizer instances produce identical obstacle events.
    func testArenaRandomizerObstacleEventsDeterministic() {
        let seed: UInt64 = 98765
        let randomizer1 = ArenaRandomizer(seed: seed)
        let randomizer2 = ArenaRandomizer(seed: seed)
        
        // Generate 20 obstacle events and verify they match.
        for i in 0..<20 {
            let difficulty = CGFloat(i) / 20.0  // Varying difficulty 0.0 to 0.95
            let event1 = randomizer1.nextObstacleEvent(currentTime: TimeInterval(i), difficulty: difficulty)
            let event2 = randomizer2.nextObstacleEvent(currentTime: TimeInterval(i), difficulty: difficulty)
            
            XCTAssertEqual(event1, event2, "Obstacle events must match at iteration \(i)")
        }
    }
    
    /// Verifies obstacle spawn indices increment correctly.
    func testArenaRandomizerObstacleSpawnIndexIncrements() {
        let randomizer = ArenaRandomizer(seed: 111)
        
        XCTAssertEqual(randomizer.obstacleSpawnIndex, 0, "Initial spawn index should be 0")
        
        _ = randomizer.nextObstacleEvent(currentTime: 1.0, difficulty: 0.5)
        XCTAssertEqual(randomizer.obstacleSpawnIndex, 1)
        
        _ = randomizer.nextObstacleEvent(currentTime: 2.0, difficulty: 0.5)
        XCTAssertEqual(randomizer.obstacleSpawnIndex, 2)
    }
    
    /// Verifies edge-punish obstacles are generated correctly.
    func testEdgePunishObstacleGeneration() {
        let randomizer = ArenaRandomizer(seed: 222)
        
        let leftEvent = randomizer.nextObstacleEvent(
            currentTime: 1.0,
            difficulty: 0.5,
            isEdgePunish: true,
            edgeSide: .left
        )
        
        XCTAssertTrue(leftEvent.isEdgePunish, "Event should be marked as edge punish")
        XCTAssertEqual(leftEvent.edgeSide, .left, "Edge side should be left")
        XCTAssertEqual(leftEvent.normalizedX, 0.15, accuracy: 0.01, "Left edge punish should target 0.15")
        
        let rightEvent = randomizer.nextObstacleEvent(
            currentTime: 2.0,
            difficulty: 0.5,
            isEdgePunish: true,
            edgeSide: .right
        )
        
        XCTAssertTrue(rightEvent.isEdgePunish)
        XCTAssertEqual(rightEvent.edgeSide, .right)
        XCTAssertEqual(rightEvent.normalizedX, 0.85, accuracy: 0.01, "Right edge punish should target 0.85")
    }
    
    // MARK: - ArenaRandomizer Power-Up Tests
    
    /// Verifies two ArenaRandomizer instances produce identical power-up events.
    func testArenaRandomizerPowerUpEventsDeterministic() {
        let seed: UInt64 = 54321
        let randomizer1 = ArenaRandomizer(seed: seed)
        let randomizer2 = ArenaRandomizer(seed: seed)
        
        // Generate 10 power-up events and verify they match.
        for i in 0..<10 {
            let difficulty = Double(i) / 10.0
            let event1 = randomizer1.forcePowerUpEvent(currentTime: TimeInterval(i * 10), difficulty: difficulty)
            let event2 = randomizer2.forcePowerUpEvent(currentTime: TimeInterval(i * 10), difficulty: difficulty)
            
            XCTAssertEqual(event1, event2, "Power-up events must match at iteration \(i)")
        }
    }
    
    /// Verifies power-up spawn index increments correctly.
    func testArenaRandomizerPowerUpSpawnIndexIncrements() {
        let randomizer = ArenaRandomizer(seed: 333)
        
        XCTAssertEqual(randomizer.powerUpSpawnIndex, 0, "Initial power-up spawn index should be 0")
        
        _ = randomizer.forcePowerUpEvent(currentTime: 10.0, difficulty: 0.5)
        XCTAssertEqual(randomizer.powerUpSpawnIndex, 1)
        
        _ = randomizer.forcePowerUpEvent(currentTime: 20.0, difficulty: 0.5)
        XCTAssertEqual(randomizer.powerUpSpawnIndex, 2)
    }
    
    /// Verifies power-up type distribution covers all types.
    func testPowerUpTypeDistribution() {
        let randomizer = ArenaRandomizer(seed: 444)
        var typeCounts: [PowerUpSpawnEvent.PowerUpTypeEvent: Int] = [
            .slowMotion: 0,
            .invincibility: 0,
            .attackMode: 0
        ]
        
        // Generate many power-ups to ensure all types appear.
        for i in 0..<100 {
            let event = randomizer.forcePowerUpEvent(currentTime: TimeInterval(i), difficulty: 0.5)
            typeCounts[event.type, default: 0] += 1
        }
        
        // All three types should appear at least once.
        XCTAssertGreaterThan(typeCounts[.slowMotion] ?? 0, 0, "Slow motion power-ups should spawn")
        XCTAssertGreaterThan(typeCounts[.invincibility] ?? 0, 0, "Invincibility power-ups should spawn")
        XCTAssertGreaterThan(typeCounts[.attackMode] ?? 0, 0, "Attack mode power-ups should spawn")
    }
    
    // MARK: - Multiplayer Configuration Tests
    
    /// Verifies single-player mode blocks power-ups when active.
    func testSinglePlayerBlocksPowerUpWhenActive() {
        let randomizer = ArenaRandomizer.singlePlayer()
        
        // Should return nil when any power-up is active in single-player.
        let event = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 10.0,
            difficulty: 0.5,
            activePowerUpCount: 0,
            anyPowerUpActive: true
        )
        
        XCTAssertNil(event, "Single-player should not spawn power-ups when one is active")
    }
    
    /// Verifies multiplayer mode allows stacking up to the configured limit.
    func testMultiplayerAllowsPowerUpStacking() {
        let seed: UInt64 = 555
        let config = ArenaMultiplayerConfig(
            maxSimultaneousPowerUps: 2,
            minPowerUpSpawnInterval: 0.0,  // Disable interval for testing
            allowPowerUpStacking: true
        )
        let randomizer = ArenaRandomizer.multiplayer(seed: seed, config: config)
        
        // Should allow spawning when count is below max.
        let event1 = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 10.0,
            difficulty: 0.5,
            activePowerUpCount: 1,
            anyPowerUpActive: true
        )
        XCTAssertNotNil(event1, "Multiplayer should allow power-up when under max")
        
        // Should block when at max capacity.
        let event2 = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 20.0,
            difficulty: 0.5,
            activePowerUpCount: 2,
            anyPowerUpActive: true
        )
        XCTAssertNil(event2, "Multiplayer should block power-up at max capacity")
    }
    
    /// Verifies multiplayer mode respects minimum spawn interval.
    func testMultiplayerMinSpawnInterval() {
        let seed: UInt64 = 666
        let config = ArenaMultiplayerConfig(
            maxSimultaneousPowerUps: 3,
            minPowerUpSpawnInterval: 8.0,
            allowPowerUpStacking: true
        )
        let randomizer = ArenaRandomizer.multiplayer(seed: seed, config: config)
        
        // First spawn should work.
        let event1 = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 10.0,
            difficulty: 0.5,
            activePowerUpCount: 0,
            anyPowerUpActive: false
        )
        XCTAssertNotNil(event1, "First power-up should spawn")
        
        // Spawn too soon should be blocked.
        let event2 = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 15.0,  // Only 5 seconds later
            difficulty: 0.5,
            activePowerUpCount: 0,
            anyPowerUpActive: false
        )
        XCTAssertNil(event2, "Power-up should be blocked due to min interval")
        
        // Spawn after interval should work.
        let event3 = randomizer.nextPowerUpEventIfNeeded(
            currentTime: 20.0,  // 10 seconds after first (> 8s interval)
            difficulty: 0.5,
            activePowerUpCount: 0,
            anyPowerUpActive: false
        )
        XCTAssertNotNil(event3, "Power-up should spawn after min interval passed")
    }
    
    // MARK: - Reset Tests
    
    /// Verifies reset() restores the randomizer to initial state.
    func testArenaRandomizerReset() {
        let seed: UInt64 = 777
        let randomizer = ArenaRandomizer(seed: seed)
        
        // Generate some events.
        _ = randomizer.nextObstacleEvent(currentTime: 1.0, difficulty: 0.5)
        _ = randomizer.nextObstacleEvent(currentTime: 2.0, difficulty: 0.5)
        _ = randomizer.forcePowerUpEvent(currentTime: 10.0, difficulty: 0.5)
        
        // Reset.
        randomizer.reset()
        
        XCTAssertEqual(randomizer.obstacleSpawnIndex, 0, "Obstacle index should reset to 0")
        XCTAssertEqual(randomizer.powerUpSpawnIndex, 0, "Power-up index should reset to 0")
        
        // Generate same events again and compare with a fresh randomizer.
        let freshRandomizer = ArenaRandomizer(seed: seed)
        
        let event1 = randomizer.nextObstacleEvent(currentTime: 1.0, difficulty: 0.5)
        let freshEvent1 = freshRandomizer.nextObstacleEvent(currentTime: 1.0, difficulty: 0.5)
        
        XCTAssertEqual(event1, freshEvent1, "Reset randomizer should produce same events as fresh instance")
    }
    
    // MARK: - Arena Event Stream Tests
    
    /// Verifies ArenaEventStream tracks and replays events correctly.
    func testArenaEventStreamReplay() {
        var stream = ArenaEventStream(seed: 888)
        
        // Add some events.
        let obstacle1 = ObstacleSpawnEvent(
            timeOffset: 1.0, width: 100, speedY: 300,
            normalizedX: 0.5, isEdgePunish: false, edgeSide: .none
        )
        let obstacle2 = ObstacleSpawnEvent(
            timeOffset: 3.0, width: 80, speedY: 400,
            normalizedX: 0.3, isEdgePunish: false, edgeSide: .none
        )
        
        stream.appendObstacleEvent(obstacle1)
        stream.appendObstacleEvent(obstacle2)
        
        // Replay at different times.
        let event0 = stream.nextObstacleEventIfReady(currentTime: 0.5)
        XCTAssertNil(event0, "No event should be ready at t=0.5")
        
        let event1 = stream.nextObstacleEventIfReady(currentTime: 1.5)
        XCTAssertEqual(event1, obstacle1, "First obstacle should be returned at t=1.5")
        
        let event1Again = stream.nextObstacleEventIfReady(currentTime: 2.0)
        XCTAssertNil(event1Again, "First obstacle should not be returned twice")
        
        let event2 = stream.nextObstacleEventIfReady(currentTime: 3.5)
        XCTAssertEqual(event2, obstacle2, "Second obstacle should be returned at t=3.5")
    }
    
    /// Verifies ArenaEventStream resetPlayback() allows replay from start.
    func testArenaEventStreamResetPlayback() {
        var stream = ArenaEventStream(seed: 999)
        
        let powerUp = PowerUpSpawnEvent(
            timeOffset: 5.0,
            type: .slowMotion,
            normalizedX: 0.5,
            speedY: 200,
            radius: 30
        )
        stream.appendPowerUpEvent(powerUp)
        
        // Consume the event.
        let event1 = stream.nextPowerUpEventIfReady(currentTime: 6.0)
        XCTAssertNotNil(event1)
        
        // Reset playback.
        stream.resetPlayback()
        
        // Event should be available again.
        let event2 = stream.nextPowerUpEventIfReady(currentTime: 6.0)
        XCTAssertEqual(event2, powerUp, "Event should be replayable after resetPlayback()")
    }
}

