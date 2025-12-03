//
//  LifecyclePersistenceTests.swift
//  HyprGlideTests
//
//  Regression coverage for lifecycle pause handling and score persistence.
//

import XCTest
@testable import HyprGlide

final class LifecyclePersistenceTests: XCTestCase {
    
    func testRecordBestPersistsImmediately() {
        let suiteName = "LifecyclePersistenceTests.recordBest"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite \(suiteName)")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let state = GameState(defaults: defaults)
        state.startGame()
        state.score = 128.0
        state.recordBest()
        
        let persisted = defaults.double(forKey: "HyprGlide.BestScore.normal")
        XCTAssertEqual(persisted, 128.0, accuracy: 0.0001, "Best score should be written to defaults immediately.")
    }
    
    func testPauseAndResumeGuardOnGameStatus() {
        let state = GameState()
        
        state.pauseGame()
        XCTAssertFalse(state.isPaused, "Pause requests should be ignored before the run starts.")
        
        state.startGame()
        state.pauseGame()
        XCTAssertTrue(state.isPaused, "Active runs should transition into a paused state.")
        
        state.resumeGame()
        XCTAssertFalse(state.isPaused, "Resume should clear the paused flag for active runs.")
        
        state.isGameOver = true
        state.pauseGame()
        XCTAssertFalse(state.isPaused, "Game over screens should not enter a paused state.")
    }
    
    func testSceneWillResignActiveAutoPausesActiveRun() {
        let state = GameState()
        state.startGame()
        
        let scene = GameScene()
        scene.gameState = state
        
        scene.simulateLifecyclePauseForTesting()
        
        XCTAssertTrue(state.isPaused, "Scene lifecycle transitions must auto-pause the active run.")
    }
}

