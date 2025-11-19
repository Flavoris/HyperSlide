//
//  GameFeelTests.swift
//  HyperSlideTests
//
//  Lightweight regression tests covering new game feel bonuses.
//

import XCTest
@testable import HyperSlide

final class GameFeelTests: XCTestCase {
    
    private let tiltSensitivityDefaultsKey = "HyperSlide.TiltSensitivity"
    
    func testNearMissAwardsBonusDuringActivePlay() {
        let state = GameState()
        state.startGame()
        
        let baseline = state.score
        state.addNearMissBonus()
        
        XCTAssertEqual(state.score, baseline + 2, accuracy: .ulpOfOne, "Near miss should grant a +2 bonus.")
    }
    
    func testNearMissIgnoredAfterGameOver() {
        let state = GameState()
        state.startGame()
        state.isGameOver = true
        
        let baseline = state.score
        state.addNearMissBonus()
        
        XCTAssertEqual(state.score, baseline, accuracy: .ulpOfOne, "Near miss bonus must not apply once the game is over.")
    }
    
    func testTiltInputHonorsDeadZone() {
        let velocity = TiltInputMapper.velocity(for: 0.02,
                                                deadZone: 0.05,
                                                maxSpeed: 900)
        XCTAssertEqual(velocity, 0, accuracy: 0.0001, "Motion inside the deadzone should not move the player.")
    }
    
    func testTiltInputProducesBidirectionalSpeeds() {
        let positive = TiltInputMapper.velocity(for: 0.5,
                                                deadZone: 0.05,
                                                maxSpeed: 900)
        let negative = TiltInputMapper.velocity(for: -0.5,
                                                deadZone: 0.05,
                                                maxSpeed: 900)
        
        XCTAssertGreaterThan(positive, 0)
        XCTAssertLessThan(negative, 0)
        XCTAssertEqual(abs(positive), abs(negative), accuracy: 0.01, "Positive and negative tilts should be symmetric.")
    }
    
    func testTiltInputClampsAtMaxSpeed() {
        let velocity = TiltInputMapper.velocity(for: 3.0,
                                                deadZone: 0.05,
                                                maxSpeed: 750)
        XCTAssertEqual(velocity, 750, accuracy: 0.0001, "Velocity should clamp to the configured max speed.")
    }
    
    func testTiltSensitivityDefaultsToBaseline() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: tiltSensitivityDefaultsKey)
        
        let settings = Settings()
        XCTAssertEqual(settings.tiltSensitivity, 1.0, accuracy: 0.0001, "Baseline tilt sensitivity should initialize at 1.0.")
        
        defaults.removeObject(forKey: tiltSensitivityDefaultsKey)
    }
    
    func testTiltSensitivityPersistsAcrossInstances() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: tiltSensitivityDefaultsKey)
        
        let firstSession = Settings()
        firstSession.tiltSensitivity = 1.25
        
        let secondSession = Settings()
        XCTAssertEqual(secondSession.tiltSensitivity, 1.25, accuracy: 0.0001, "Tilt sensitivity should persist via UserDefaults.")
        
        defaults.removeObject(forKey: tiltSensitivityDefaultsKey)
    }
}


