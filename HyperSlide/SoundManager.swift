//
//  SoundManager.swift
//  HyperSlide
//
//  Centralised audio controller responsible for preloading and playing
//  short sound effects with mute state persistence.
//

import AVFoundation
import Foundation

// MARK: - Internal Abstractions

/// Lightweight protocol abstraction that lets us inject mock players in tests
/// while relying on `AVAudioPlayer` at runtime.
protocol SoundPlayer: AnyObject {
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }
    
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
}

extension AVAudioPlayer: SoundPlayer {}

// MARK: - Sound Manager

final class SoundManager: ObservableObject {
    
    // MARK: Nested Types
    
    /// Supported short sound effects within the game.
    enum SoundEffect: CaseIterable {
        case nearMissWhoosh
        case collisionThud
        
        /// Resource file name without extension.
        var fileName: String {
            switch self {
            case .nearMissWhoosh:
                return "whoosh"
            case .collisionThud:
                return "thud"
            }
        }
        
        /// All effects currently ship as `.wav`.
        var fileExtension: String { "wav" }
        
        /// Gentle per-effect volume tuning to keep the mix balanced.
        var defaultVolume: Float {
            switch self {
            case .nearMissWhoosh:
                return 0.55
            case .collisionThud:
                return 0.75
            }
        }
    }
    
    // MARK: Constants
    
    private static let muteDefaultsKey = "HyperSlide.SoundManager.Muted"
    
    // MARK: Stored Properties
    
    @Published private(set) var isMuted: Bool
    
    private let bundle: Bundle
    private let defaults: UserDefaults
    
    private var players: [SoundEffect: SoundPlayer] = [:]
    
    // MARK: Initialization
    
    init(bundle: Bundle = .main,
         defaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.defaults = defaults
        self.isMuted = defaults.bool(forKey: Self.muteDefaultsKey)
        
        configureAudioSession()
        preloadPlayers()
    }
    
    // MARK: Public API
    
    /// Persist and publish mute toggles.
    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        defaults.set(muted, forKey: Self.muteDefaultsKey)
    }
    
    /// Convenience wrapper for UI bindings.
    func toggleMute() {
        setMuted(!isMuted)
    }
    
    /// Plays the near miss whoosh.
    @discardableResult
    func playNearMiss() -> Bool {
        play(.nearMissWhoosh)
    }
    
    /// Plays the collision thud.
    @discardableResult
    func playCollision() -> Bool {
        play(.collisionThud)
    }
    
    // MARK: Internal (Testing) Helpers
    
    /// Overrides the player for a specific effect (used in unit tests).
    func setPlayer(_ player: SoundPlayer, for effect: SoundEffect) {
        players[effect] = player
    }
    
    // MARK: Private Helpers
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            debugPrint("⚠️ Failed to configure audio session: \(error)")
        }
    }
    
    private func preloadPlayers() {
        SoundEffect.allCases.forEach { effect in
            guard let url = bundle.url(forResource: effect.fileName,
                                       withExtension: effect.fileExtension) else {
                debugPrint("⚠️ Missing sound resource: \(effect.fileName).\(effect.fileExtension)")
                return
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = effect.defaultVolume
                player.prepareToPlay()
                players[effect] = player
            } catch {
                debugPrint("⚠️ Failed to preload \(effect.fileName): \(error)")
            }
        }
    }
    
    @discardableResult
    private func play(_ effect: SoundEffect) -> Bool {
        guard !isMuted else { return false }
        guard let player = players[effect] else {
            return false
        }
        
        player.currentTime = 0
        return player.play()
    }
}


