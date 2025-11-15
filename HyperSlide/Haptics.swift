//
//  Haptics.swift
//  HyperSlide
//
//  Centralized haptics utilities for consistent tactile feedback triggers.
//

import Foundation

#if canImport(UIKit)
import UIKit
typealias HapticNotificationType = UINotificationFeedbackGenerator.FeedbackType
#else
typealias HapticNotificationType = Int
#endif

enum Haptics {
#if canImport(UIKit)
    /// Shared notification feedback generator (used for success/error events).
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    
    /// Light impact for subtle bumps (e.g., near misses).
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    /// Medium impact for noticeable collisions.
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    /// Play a light impact for near-miss moments.
    static func playNearMissImpact(intensity: CGFloat = 0.7) {
        performOnMainThread {
            lightImpactGenerator.prepare()
            lightImpactGenerator.impactOccurred(intensity: max(0.0, min(1.0, intensity)))
        }
    }
    
    /// Play a medium impact for collisions or other heavy feedback events.
    static func playCollisionImpact(intensity: CGFloat = 1.0) {
        performOnMainThread {
            mediumImpactGenerator.prepare()
            mediumImpactGenerator.impactOccurred(intensity: max(0.0, min(1.0, intensity)))
        }
    }
    
    /// Emit a notification-type haptic (success, warning, error).
    static func playNotification(_ type: HapticNotificationType) {
        performOnMainThread {
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
        }
    }
    
    /// Prepare feedback generators early to reduce first-use latency.
    static func prewarm() {
        performOnMainThread {
            notificationGenerator.prepare()
            lightImpactGenerator.prepare()
            mediumImpactGenerator.prepare()
        }
    }
    
    /// Ensures all haptic triggers are executed on the main thread.
    private static func performOnMainThread(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async {
                action()
            }
        }
    }
#else
    static func playNearMissImpact(intensity: CGFloat = 0.7) {}
    static func playCollisionImpact(intensity: CGFloat = 1.0) {}
    static func playNotification(_ type: HapticNotificationType) {}
    static func prewarm() {}
#endif
}


