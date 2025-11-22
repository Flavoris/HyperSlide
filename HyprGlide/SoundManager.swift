//
//  SoundManager.swift
//  HyprGlide
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
    func stop()
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
    
    private static let muteDefaultsKey = "HyprGlide.SoundManager.Muted"
    
    // MARK: Stored Properties
    
    @Published private(set) var isMuted: Bool
    
    private let bundle: Bundle
    private let defaults: UserDefaults
    private let warmupQueue = DispatchQueue(label: "HyprGlide.SoundManager.AudioWarmup",
                                            qos: .userInitiated)
    
    private var players: [SoundEffect: SoundPlayer] = [:]
    private var hasPrimedAudio = false
    private let backgroundMusic: BackgroundMusicControlling
    private var sfxVolume: Float = 1.0
    private var musicVolume: Float = 1.0
    
    // MARK: Initialization
    
    init(bundle: Bundle = .main,
         defaults: UserDefaults = .standard,
         backgroundMusic: BackgroundMusicControlling = BackgroundMusicAssetEngine()) {
        self.bundle = bundle
        self.defaults = defaults
        self.backgroundMusic = backgroundMusic
        if defaults.object(forKey: Self.muteDefaultsKey) == nil {
            self.isMuted = false
            DefaultsGuard.write(on: defaults) { store in
                store.set(false, forKey: Self.muteDefaultsKey)
            }
        } else {
            self.isMuted = DefaultsGuard.read(from: defaults) { store in
                store.bool(forKey: Self.muteDefaultsKey)
            } ?? false
        }
        
        configureAudioSession()
        preloadPlayers()
        self.backgroundMusic.setUserVolume(musicVolume)
        self.backgroundMusic.setMuted(isMuted)
        self.backgroundMusic.start()
    }
    
    // MARK: Public API
    
    /// Persist and publish mute toggles.
    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        backgroundMusic.setMuted(muted)
        DefaultsGuard.write(on: defaults) { store in
            store.set(muted, forKey: Self.muteDefaultsKey)
        }
    }
    
    /// Convenience wrapper for UI bindings.
    func toggleMute() {
        setMuted(!isMuted)
    }
    
    /// Adjusts the master SFX volume (0...1) applied on top of per-effect tuning.
    func setSFXVolume(_ volume: Float) {
        let clamped = Self.clampVolume(volume)
        guard sfxVolume != clamped else { return }
        sfxVolume = clamped
        applySFXVolume()
    }
    
    /// Adjusts the background music volume (0...1) while keeping mute state intact.
    func setMusicVolume(_ volume: Float) {
        let clamped = Self.clampVolume(volume)
        guard musicVolume != clamped else { return }
        musicVolume = clamped
        backgroundMusic.setUserVolume(clamped)
    }
    
    /// Warms the audio pipeline to prevent the first playback from blocking the main thread.
    /// This should be invoked during scene/view setup, well before near-miss sounds are needed.
    func primeAudioIfNeeded(completion: (() -> Void)? = nil) {
        warmupQueue.async { [weak self] in
            guard let self else { return }
            guard !self.hasPrimedAudio else {
                completion?()
                return
            }
            self.hasPrimedAudio = true
            
            let playersSnapshot = Array(self.players.values)
            guard !playersSnapshot.isEmpty else {
                completion?()
                return
            }
            
            playersSnapshot.forEach { player in
                let originalVolume = player.volume
                player.volume = 0.0005 // practically silent yet keeps the decoder hot
                player.currentTime = 0
                _ = player.play()
                Thread.sleep(forTimeInterval: 0.05)
                player.stop()
                player.currentTime = 0
                player.volume = originalVolume
            }
            
            completion?()
        }
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
                player.volume = effect.defaultVolume * sfxVolume
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
    
    private func applySFXVolume() {
        SoundEffect.allCases.forEach { effect in
            guard let player = players[effect] else { return }
            player.volume = effect.defaultVolume * sfxVolume
        }
    }
    
    private static func clampVolume(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}


