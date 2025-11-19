//
//  SlowMotionEffect.swift
//  HyperSlide
//
//  Lightweight state container for temporary slowdown bonuses.
//

import Foundation
import CoreGraphics

/// Tracks the lifetime and strength of a slowdown effect granted by power-ups.
struct SlowMotionEffect {
    
    private(set) var remaining: TimeInterval = 0
    private let duration: TimeInterval
    private let maxStackDuration: TimeInterval?
    private let clampedSpeedScale: CGFloat
    
    /// Value multiplied with obstacle speed while the effect is active.
    var speedMultiplier: CGFloat {
        isActive ? clampedSpeedScale : 1.0
    }
    
    /// Indicates whether the slowdown should currently be applied.
    var isActive: Bool {
        remaining > 0
    }
    
    init(duration: TimeInterval,
         speedScale: CGFloat,
         maxStackDuration: TimeInterval? = nil) {
        self.duration = max(0, duration)
        self.maxStackDuration = maxStackDuration
        self.clampedSpeedScale = max(0.05, min(1.0, speedScale))
    }
    
    /// Adds another chunk of duration, optionally capped by `maxStackDuration`.
    mutating func trigger() {
        guard duration > 0 else { return }
        remaining += duration
        if let cap = maxStackDuration {
            remaining = min(remaining, cap)
        }
    }
    
    /// Advances the timer, automatically clearing the effect once depleted.
    mutating func update(deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        remaining = max(0, remaining - deltaTime)
    }
    
    /// Clears any residual slowdown time, returning to normal speed immediately.
    mutating func reset() {
        remaining = 0
    }
}


