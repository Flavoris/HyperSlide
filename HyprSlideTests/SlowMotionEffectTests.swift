//
//  SlowMotionEffectTests.swift
//  HyprGlideTests
//
//  Regression tests covering the slowdown timer granted by power-ups.
//

import XCTest
@testable import HyprGlide

final class SlowMotionEffectTests: XCTestCase {
    
    func testSlowMotionEffectActivatesAndExpires() {
        var effect = SlowMotionEffect(duration: 3.0, speedScale: 0.4)
        
        XCTAssertFalse(effect.isActive, "Effect should start inactive.")
        XCTAssertEqual(effect.speedMultiplier, 1.0, accuracy: 0.0001, "Speed multiplier must be neutral before activation.")
        
        effect.trigger()
        XCTAssertTrue(effect.isActive, "Triggering the effect should activate it immediately.")
        XCTAssertEqual(effect.speedMultiplier, 0.4, accuracy: 0.0001, "Active effect should lower the multiplier.")
        
        effect.update(deltaTime: 1.0)
        XCTAssertTrue(effect.isActive, "Effect should still be active while time remains.")
        
        effect.update(deltaTime: 2.5)
        XCTAssertFalse(effect.isActive, "Effect should expire after consuming all time.")
        XCTAssertEqual(effect.speedMultiplier, 1.0, accuracy: 0.0001, "Multiplier should reset once the timer elapses.")
    }
    
    func testSlowMotionEffectRespectsStackCap() {
        var effect = SlowMotionEffect(duration: 2.0,
                                      speedScale: 0.35,
                                      maxStackDuration: 4.0)
        
        effect.trigger()
        XCTAssertEqual(effect.remaining, 2.0, accuracy: 0.0001, "Initial trigger should add one chunk of time.")
        
        effect.trigger()
        XCTAssertEqual(effect.remaining, 4.0, accuracy: 0.0001, "Second trigger should stack up to the cap.")
        
        effect.trigger()
        XCTAssertEqual(effect.remaining, 4.0, accuracy: 0.0001, "Stacking beyond the cap must clamp to the maximum.")
        
        effect.update(deltaTime: 1.5)
        XCTAssertEqual(effect.remaining, 2.5, accuracy: 0.0001, "Timer should count down by the elapsed delta.")
    }
}


