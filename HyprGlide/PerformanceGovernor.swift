//
//  PerformanceGovernor.swift
//  HyprGlide
//
//  Tracks recent frame timings and exposes heuristics that let the scene shed load
//  (fewer particles, slower spawns) whenever the average FPS dips for a sustained window.
//

import CoreGraphics
import Foundation

final class PerformanceGovernor {
    enum Mode {
        case full
        case budget
    }
    
    private struct FrameSample {
        let timestamp: TimeInterval
        let delta: TimeInterval
    }
    
    private let sampleWindow: TimeInterval = 2.0
    private let throttleFPSThreshold: Double = 45.0
    private let recoveryFPSThreshold: Double = 53.0
    private let stallResetDelta: TimeInterval = 0.45
    
    private var samples: [FrameSample] = []
    private var accumulatedDelta: TimeInterval = 0
    
    private(set) var mode: Mode = .full
    
    var spawnIntervalMultiplier: Double {
        mode == .budget ? 1.2 : 1.0
    }
    
    var particleIntensityMultiplier: CGFloat {
        mode == .budget ? 0.55 : 1.0
    }
    
    @discardableResult
    func registerFrame(deltaTime: TimeInterval, currentTime: TimeInterval) -> Bool {
        guard deltaTime.isFinite,
              currentTime.isFinite else { return false }
        
        if deltaTime >= stallResetDelta {
            return reset()
        }
        
        samples.append(FrameSample(timestamp: currentTime, delta: deltaTime))
        accumulatedDelta += deltaTime
        purgeSamples(olderThan: currentTime - sampleWindow)
        
        guard let earliest = samples.first else { return false }
        let coverage = currentTime - earliest.timestamp
        guard coverage >= sampleWindow, accumulatedDelta > 0 else { return false }
        
        let averageDelta = accumulatedDelta / Double(samples.count)
        guard averageDelta > 0 else { return false }
        let averageFPS = 1.0 / averageDelta
        
        switch mode {
        case .full where averageFPS < throttleFPSThreshold:
            mode = .budget
            return true
        case .budget where averageFPS > recoveryFPSThreshold:
            mode = .full
            return true
        default:
            return false
        }
    }
    
    @discardableResult
    func reset() -> Bool {
        samples.removeAll()
        accumulatedDelta = 0
        let modeChanged = mode != .full
        mode = .full
        return modeChanged
    }
    
    private func purgeSamples(olderThan cutoff: TimeInterval) {
        while let first = samples.first, first.timestamp < cutoff {
            accumulatedDelta -= first.delta
            samples.removeFirst()
        }
    }
}


