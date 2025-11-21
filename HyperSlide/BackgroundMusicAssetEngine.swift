//
//  BackgroundMusicAssetEngine.swift
//  HyperSlide
//
//  Plays the bundled HyperSlide soundtrack on loop using AVAudioPlayer.
//

import AVFoundation
import Foundation

protocol BackgroundMusicControlling: AnyObject {
    func start()
    func stop()
    func setMuted(_ muted: Bool)
    func setUserVolume(_ volume: Float)
}

/// Lightweight wrapper around `AVAudioPlayer` that loops the shipped soundtrack
/// (`HyperSlide Music.mp3`) with gentle fade out/in at loop points.
final class BackgroundMusicAssetEngine: NSObject, BackgroundMusicControlling {
    
    private let queue = DispatchQueue(label: "HyperSlide.BackgroundMusicAssetEngine")
    private let bundle: Bundle
    private let resourceName: String
    private let resourceExtension: String
    private let baseVolume: Float
    private let fadeOutDuration: TimeInterval
    private let fadeInDuration: TimeInterval
    
    private var player: AVAudioPlayer?
    private var fadeOutTimer: DispatchSourceTimer?
    private var isMuted = false
    private var userVolume: Float = 1.0
    
    init(bundle: Bundle = .main,
         resourceName: String = "HyperSlide Music",
         resourceExtension: String = "mp3",
         baseVolume: Float = 0.32,
         fadeOutDuration: TimeInterval = 2.5,
         fadeInDuration: TimeInterval = 1.0) {
        self.bundle = bundle
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.baseVolume = baseVolume
        self.fadeOutDuration = fadeOutDuration
        self.fadeInDuration = fadeInDuration
    }
    
    deinit {
        stop()
    }
    
    // MARK: - BackgroundMusicControlling
    
    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.fadeOutTimer?.cancel()
            self.fadeOutTimer = nil
            self.player?.stop()
            self.player = nil
        }
    }
    
    func setMuted(_ muted: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isMuted != muted else { return }
            self.isMuted = muted
            self.applyEffectiveVolume()
        }
    }
    
    func setUserVolume(_ volume: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            let clamped = Self.clamp(volume)
            guard clamped != self.userVolume else { return }
            self.userVolume = clamped
            self.applyEffectiveVolume()
        }
    }
    
    // MARK: - Private Helpers
    
    private func startLocked() {
        do {
            let player = try ensurePlayer()
            guard !player.isPlaying else {
                applyEffectiveVolume()
                scheduleFadeCycle(for: player)
                return
            }
            player.currentTime = 0
            player.volume = 0
            player.play()
            player.setVolume(effectiveVolume, fadeDuration: fadeInDuration)
            scheduleFadeCycle(for: player)
        } catch {
            debugPrint("⚠️ Failed to start background track: \(error)")
        }
    }
    
    private func ensurePlayer() throws -> AVAudioPlayer {
        if let player {
            return player
        }
        
        guard let url = bundle.url(forResource: resourceName,
                                   withExtension: resourceExtension) else {
            throw BackgroundMusicError.missingResource("\(resourceName).\(resourceExtension)")
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = effectiveVolume
            player.prepareToPlay()
            self.player = player
            return player
        } catch {
            throw BackgroundMusicError.playerInitialization(error)
        }
    }
    
    private func scheduleFadeCycle(for player: AVAudioPlayer) {
        fadeOutTimer?.cancel()
        fadeOutTimer = nil
        
        guard player.duration > fadeOutDuration else { return }
        let timeUntilFade = max(0, (player.duration - fadeOutDuration) - player.currentTime)
        guard timeUntilFade > 0 else {
            performLoopFade(using: player)
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeUntilFade)
        timer.setEventHandler { [weak self] in
            self?.performLoopFade(using: player)
        }
        timer.resume()
        fadeOutTimer = timer
    }
    
    private func performLoopFade(using player: AVAudioPlayer) {
        guard self.player === player else { return }
        player.setVolume(0, fadeDuration: fadeOutDuration)
        queue.asyncAfter(deadline: .now() + fadeOutDuration) { [weak self] in
            guard let self, self.player === player else { return }
            player.stop()
            player.currentTime = 0
            player.volume = 0
            player.play()
            player.setVolume(self.effectiveVolume, fadeDuration: self.fadeInDuration)
            self.scheduleFadeCycle(for: player)
        }
    }
    
    private func applyEffectiveVolume() {
        player?.volume = effectiveVolume
    }
    
    private var effectiveVolume: Float {
        guard !isMuted else { return 0 }
        return min(1.0, baseVolume * userVolume)
    }
    
    private static func clamp(_ volume: Float) -> Float {
        min(max(volume, 0), 1)
    }
}

enum BackgroundMusicError: Error {
    case missingResource(String)
    case playerInitialization(Error)
}


