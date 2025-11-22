//
//  SoundManagerTests.swift
//  HyprGlideTests
//
//  Regression coverage for the audio controller.
//

import XCTest
@testable import HyprGlide

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
        
        let background = MockBackgroundMusicController()
        let manager = SoundManager(defaults: defaults,
                                   backgroundMusic: background)
        XCTAssertFalse(manager.isMuted, "Manager should default to unmuted.")
        
        manager.setMuted(true)
        XCTAssertTrue(manager.isMuted, "Manager should update its published mute state.")
        XCTAssertTrue(defaults.bool(forKey: "HyprGlide.SoundManager.Muted"),
                      "Mute preference must persist in UserDefaults.")
        XCTAssertTrue(background.lastMuteState, "Background engine should receive updated mute state.")
        
        let rehydratedBackground = MockBackgroundMusicController()
        let rehydrated = SoundManager(defaults: defaults,
                                      backgroundMusic: rehydratedBackground)
        XCTAssertTrue(rehydrated.isMuted, "Reloaded manager should respect stored mute preference.")
        XCTAssertTrue(rehydratedBackground.lastMuteState,
                      "Background engine should inherit persisted mute state.")
    }
    
    func testMuteTogglePreventsPlayback() {
        let suiteName = "SoundManagerTests.MuteToggle"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let manager = SoundManager(defaults: defaults,
                                   backgroundMusic: MockBackgroundMusicController())
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
    
    func testPrimeAudioRunsOnlyOnce() {
        let suiteName = "SoundManagerTests.PrimeAudio"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let manager = SoundManager(defaults: defaults,
                                   backgroundMusic: MockBackgroundMusicController())
        let whooshPlayer = MockSoundPlayer()
        let collisionPlayer = MockSoundPlayer()
        manager.setPlayer(whooshPlayer, for: .nearMissWhoosh)
        manager.setPlayer(collisionPlayer, for: .collisionThud)
        
        let firstExpectation = expectation(description: "Audio warmup completes")
        manager.primeAudioIfNeeded {
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 1.5)
        
        XCTAssertEqual(whooshPlayer.playCallCount, 1)
        XCTAssertEqual(collisionPlayer.playCallCount, 1)
        
        let secondExpectation = expectation(description: "Second prime returns immediately")
        manager.primeAudioIfNeeded {
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 0.2)
        
        XCTAssertEqual(whooshPlayer.playCallCount, 1)
        XCTAssertEqual(collisionPlayer.playCallCount, 1)
    }
    
    func testAdjustingSFXVolumeRescalesPlayers() {
        let suiteName = "SoundManagerTests.SFXVolume"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let background = MockBackgroundMusicController()
        let manager = SoundManager(defaults: defaults,
                                   backgroundMusic: background)
        let mockPlayer = MockSoundPlayer()
        manager.setPlayer(mockPlayer, for: .nearMissWhoosh)
        
        manager.setSFXVolume(0.5)
        
        XCTAssertEqual(mockPlayer.volume,
                       SoundManager.SoundEffect.nearMissWhoosh.defaultVolume * 0.5,
                       accuracy: 0.0001)
    }
    
    func testSetMusicVolumePassesThroughToBackgroundEngine() {
        let suiteName = "SoundManagerTests.MusicVolume"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite for testing.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        let background = MockBackgroundMusicController()
        let manager = SoundManager(defaults: defaults,
                                   backgroundMusic: background)
        
        manager.setMusicVolume(0.3)
        
        XCTAssertEqual(background.lastUserVolume, 0.3, accuracy: 0.0001)
        XCTAssertEqual(background.setUserVolumeCallCount, 1)
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
    
    func stop() {}
}

private final class MockBackgroundMusicController: BackgroundMusicControlling {
    private(set) var startCallCount = 0
    private(set) var setMutedCallCount = 0
    private(set) var lastMuteState = false
    private(set) var setUserVolumeCallCount = 0
    private(set) var lastUserVolume: Float = 1.0
    
    func start() {
        startCallCount += 1
    }
    
    func stop() {}
    
    func setMuted(_ muted: Bool) {
        lastMuteState = muted
        setMutedCallCount += 1
    }
    
    func setUserVolume(_ volume: Float) {
        lastUserVolume = volume
        setUserVolumeCallCount += 1
    }
}


