//
//  SoundManagerTests.swift
//  HyperSlideTests
//
//  Regression coverage for the audio controller.
//

import XCTest
@testable import HyperSlide

@MainActor
final class SoundManagerTests: XCTestCase {
    
    func testMutePreferencePersistsAcrossInstances() {
        let suiteName = "SoundManagerTests.MutePersistence"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let manager = SoundManager(defaults: defaults)
        XCTAssertFalse(manager.isMuted, "Manager should default to unmuted.")
        
        manager.setMuted(true)
        XCTAssertTrue(manager.isMuted, "Manager should update its published mute state.")
        XCTAssertTrue(defaults.bool(forKey: "HyperSlide.SoundManager.Muted"),
                      "Mute preference must persist in UserDefaults.")
        
        let rehydrated = SoundManager(defaults: defaults)
        XCTAssertTrue(rehydrated.isMuted, "Reloaded manager should respect stored mute preference.")
    }
    
    func testMuteTogglePreventsPlayback() {
        let suiteName = "SoundManagerTests.MuteToggle"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let manager = SoundManager(defaults: defaults)
        let player = MockSoundPlayer()
        manager.setPlayer(player, for: .nearMissWhoosh)
        
        XCTAssertTrue(manager.playNearMiss(), "Playback should occur when unmuted.")
        XCTAssertEqual(player.playCallCount, 1)
        
        manager.setMuted(true)
        XCTAssertFalse(manager.playNearMiss(), "Playback should be suppressed while muted.")
        XCTAssertEqual(player.playCallCount, 1)
        
        manager.setMuted(false)
        XCTAssertTrue(manager.playNearMiss(), "Playback should resume after unmuting.")
        XCTAssertEqual(player.playCallCount, 2)
    }
}

// MARK: - Test Doubles

private final class MockSoundPlayer: SoundPlayer {
    var currentTime: TimeInterval = 0
    var volume: Float = 1.0
    private(set) var playCallCount = 0
    
    func prepareToPlay() -> Bool { true }
    
    func play() -> Bool {
        playCallCount += 1
        return true
    }
}


