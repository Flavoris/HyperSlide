//
//  InvincibilityEffect.swift
//  HyprGlide
//
//  Lightweight state container for temporary invincibility bonuses.
//

import Foundation
import CoreGraphics

/// Tracks the lifetime of an invincibility effect granted by power-ups.
struct InvincibilityEffect {
    
    private(set) var remaining: TimeInterval = 0
    private let duration: TimeInterval
    private let maxStackDuration: TimeInterval?
    
    /// Indicates whether invincibility is currently active.
    var isActive: Bool {
        remaining > 0
    }
    
    init(duration: TimeInterval,
         maxStackDuration: TimeInterval? = nil) {
        self.duration = max(0, duration)
        self.maxStackDuration = maxStackDuration
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
    
    /// Clears any residual invincibility time.
    mutating func reset() {
        remaining = 0
    }
}
