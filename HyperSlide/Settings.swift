//
//  Settings.swift
//  HyperSlide
//
//  User preferences and game settings model
//

import Foundation
import Observation
import SwiftUI

@Observable
class Settings {
    // UserDefaults keys
    private static let difficultyRampKey = "HyperSlide.DifficultyRamp"
    private static let tiltControlKey = "HyperSlide.TiltControl"
    private static let tiltSensitivityKey = "HyperSlide.TiltSensitivity"
    private static let colorThemeKey = "HyperSlide.ColorTheme"
    
    static let tiltSensitivityRange: ClosedRange<Double> = 0.6...1.4
    
    // MARK: - Settings Properties
    
    /// Difficulty ramp speed multiplier
    var difficultyRamp: DifficultyRamp {
        didSet {
            UserDefaults.standard.set(difficultyRamp.rawValue, forKey: Settings.difficultyRampKey)
        }
    }
    
    /// Tilt control enabled/disabled
    var tiltControlEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tiltControlEnabled, forKey: Settings.tiltControlKey)
        }
    }
    
    /// User-adjustable multiplier applied to base tilt responsiveness/speed
    var tiltSensitivity: Double {
        didSet {
            let clamped = Settings.clampTiltSensitivity(tiltSensitivity)
            if tiltSensitivity != clamped {
                tiltSensitivity = clamped
                return
            }
            UserDefaults.standard.set(tiltSensitivity, forKey: Settings.tiltSensitivityKey)
        }
    }
    
    /// Color theme selection
    var colorTheme: ColorTheme {
        didSet {
            UserDefaults.standard.set(colorTheme.rawValue, forKey: Settings.colorThemeKey)
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Load settings from UserDefaults
        if let savedRamp = UserDefaults.standard.string(forKey: Settings.difficultyRampKey),
           let ramp = DifficultyRamp(rawValue: savedRamp) {
            self.difficultyRamp = ramp
        } else {
            self.difficultyRamp = .normal
        }
        
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Settings.tiltControlKey) == nil {
            self.tiltControlEnabled = true
            defaults.set(true, forKey: Settings.tiltControlKey)
        } else {
            self.tiltControlEnabled = defaults.bool(forKey: Settings.tiltControlKey)
        }
        
        if defaults.object(forKey: Settings.tiltSensitivityKey) == nil {
            self.tiltSensitivity = 1.0
            defaults.set(1.0, forKey: Settings.tiltSensitivityKey)
        } else {
            let storedValue = defaults.double(forKey: Settings.tiltSensitivityKey)
            self.tiltSensitivity = Settings.clampTiltSensitivity(storedValue)
        }
        
        if let savedTheme = UserDefaults.standard.string(forKey: Settings.colorThemeKey),
           let theme = ColorTheme(rawValue: savedTheme) {
            self.colorTheme = theme
        } else {
            self.colorTheme = .neonBlue
        }
    }
    
    // MARK: - Computed Properties
    
    /// Get the difficulty ramp multiplier (1.0 for normal, 1.5 for fast)
    var difficultyMultiplier: Double {
        difficultyRamp.multiplier
    }
    
    // MARK: - Helpers
    
    private static func clampTiltSensitivity(_ value: Double) -> Double {
        min(max(value, tiltSensitivityRange.lowerBound), tiltSensitivityRange.upperBound)
    }
}

// MARK: - Enums

enum DifficultyRamp: String, CaseIterable {
    case normal = "normal"
    case fast = "fast"
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
    
    var multiplier: Double {
        switch self {
        case .normal: return 1.0
        case .fast: return 1.5
        }
    }
}

enum ColorTheme: String, CaseIterable {
    case neonBlue = "neonBlue"
    case neonPurple = "neonPurple"
    case synthwave = "synthwave"
    
    var displayName: String {
        switch self {
        case .neonBlue: return "Neon Blue"
        case .neonPurple: return "Neon Purple"
        case .synthwave: return "Synthwave"
        }
    }
    
    /// Primary accent color for the theme
    var primaryColor: Color {
        switch self {
        case .neonBlue:
            return Color("NeonBlue")
        case .neonPurple:
            return Color("NeonPurple")
        case .synthwave:
            return Color(red: 1.0, green: 0.2, blue: 0.6) // Hot pink
        }
    }
    
    /// Secondary accent color for the theme
    var secondaryColor: Color {
        switch self {
        case .neonBlue:
            return Color(red: 0.0, green: 0.82, blue: 1.0)
        case .neonPurple:
            return Color(red: 0.7, green: 0.3, blue: 1.0)
        case .synthwave:
            return Color(red: 1.0, green: 0.6, blue: 0.0) // Orange
        }
    }
    
    /// Player color (SKColor for SpriteKit)
    var playerColor: (core: (CGFloat, CGFloat, CGFloat),
                      glow: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .neonBlue:
            return (core: (0.0, 0.82, 1.0), glow: (0.0, 0.95, 1.0))
        case .neonPurple:
            return (core: (0.7, 0.3, 1.0), glow: (0.8, 0.4, 1.0))
        case .synthwave:
            return (core: (1.0, 0.2, 0.6), glow: (1.0, 0.3, 0.7))
        }
    }
    
    /// Obstacle color (SKColor for SpriteKit) - complementary to player color
    var obstacleColor: (core: (CGFloat, CGFloat, CGFloat),
                        glow: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .neonBlue:
            // Hot pink/magenta - complementary to cyan
            return (core: (1.0, 0.1, 0.6), glow: (1.0, 0.35, 0.75))
        case .neonPurple:
            // Orange/amber - complementary to purple
            return (core: (1.0, 0.5, 0.0), glow: (1.0, 0.65, 0.2))
        case .synthwave:
            // Cyan/turquoise - complementary to hot pink
            return (core: (0.0, 0.9, 1.0), glow: (0.2, 0.95, 1.0))
        }
    }
    
    /// Power-up color palette (ring + glow) to keep collectibles on-theme.
    var powerUpColor: (ring: (CGFloat, CGFloat, CGFloat),
                       glow: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .neonBlue:
            return (ring: (0.1, 1.0, 0.8), glow: (0.3, 1.0, 0.85))
        case .neonPurple:
            return (ring: (0.2, 0.95, 1.0), glow: (0.4, 1.0, 1.0))
        case .synthwave:
            return (ring: (1.0, 0.85, 0.25), glow: (1.0, 0.7, 0.2))
        }
    }
}

