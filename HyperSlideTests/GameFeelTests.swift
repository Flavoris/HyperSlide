//
//  GameFeelTests.swift
//  HyperSlideTests
//
//  Lightweight regression tests covering new game feel bonuses.
//

import XCTest
@testable import HyperSlide

final class GameFeelTests: XCTestCase {
    
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
}


