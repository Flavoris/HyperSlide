//
//  Settings.swift
//  HyprGlide
//
//  User preferences and game settings model
//

import Foundation
import Combine
import SwiftUI

class Settings: ObservableObject {
    // UserDefaults keys
    private static let difficultyRampKey = "HyprGlide.DifficultyRamp"
    private static let tiltControlKey = "HyprGlide.TiltControl"
    private static let tiltSensitivityKey = "HyprGlide.TiltSensitivity"
    private static let colorThemeKey = "HyprGlide.ColorTheme"
    private static let musicVolumeKey = "HyprGlide.MusicVolume"
    private static let sfxVolumeKey = "HyprGlide.SFXVolume"
    private static let glowEffectsEnabledKey = "HyprGlide.GlowEffectsEnabled"
    private static let hasSeenTutorialKey = "HyprGlide.HasSeenTutorial"
    
    static let tiltSensitivityRange: ClosedRange<Double> = 0.6...1.4
    static let audioVolumeRange: ClosedRange<Double> = 0.0...1.0
    
    private let defaults: UserDefaults
    
    // MARK: - Settings Properties
    
    /// Difficulty ramp speed multiplier
    @Published var difficultyRamp: DifficultyRamp {
        didSet {
            guard difficultyRamp != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(difficultyRamp.rawValue, forKey: Settings.difficultyRampKey)
            }
        }
    }
    
    /// Tilt control enabled/disabled
    @Published var tiltControlEnabled: Bool {
        didSet {
            guard tiltControlEnabled != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(tiltControlEnabled, forKey: Settings.tiltControlKey)
            }
        }
    }
    
    /// User-adjustable multiplier applied to base tilt responsiveness/speed
    @Published var tiltSensitivity: Double {
        didSet {
            let clamped = Settings.clampTiltSensitivity(tiltSensitivity)
            if tiltSensitivity != clamped {
                tiltSensitivity = clamped
                return
            }
            guard tiltSensitivity != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(tiltSensitivity, forKey: Settings.tiltSensitivityKey)
            }
        }
    }
    
    /// Color theme selection
    @Published var colorTheme: ColorTheme {
        didSet {
            guard colorTheme != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(colorTheme.rawValue, forKey: Settings.colorThemeKey)
            }
        }
    }
    
    /// Background music volume (0...1)
    @Published var musicVolume: Double {
        didSet {
            let clamped = Settings.clampAudioVolume(musicVolume)
            if clamped != musicVolume {
                musicVolume = clamped
                return
            }
            guard musicVolume != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(musicVolume, forKey: Settings.musicVolumeKey)
            }
        }
    }
    
    /// Sound effects volume (0...1)
    @Published var sfxVolume: Double {
        didSet {
            let clamped = Settings.clampAudioVolume(sfxVolume)
            if clamped != sfxVolume {
                sfxVolume = clamped
                return
            }
            guard sfxVolume != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(sfxVolume, forKey: Settings.sfxVolumeKey)
            }
        }
    }
    
    /// Whether neon glow effects are shown on the player orb and obstacles.
    @Published var glowEffectsEnabled: Bool {
        didSet {
            guard glowEffectsEnabled != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(glowEffectsEnabled, forKey: Settings.glowEffectsEnabledKey)
            }
        }
    }
    
    /// Tracks if the player has completed the onboarding tutorial.
    @Published var hasSeenTutorial: Bool {
        didSet {
            guard hasSeenTutorial != oldValue else { return }
            DefaultsGuard.write(on: defaults) { store in
                store.set(hasSeenTutorial, forKey: Settings.hasSeenTutorialKey)
            }
        }
    }
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        // Initialize properties before assigning to self
        
        // Difficulty
        if defaults.object(forKey: Settings.difficultyRampKey) == nil {
            self.difficultyRamp = .normal
            DefaultsGuard.write(on: defaults) { store in
                store.set(DifficultyRamp.normal.rawValue, forKey: Settings.difficultyRampKey)
            }
        } else if let ramp = DefaultsGuard.read(from: defaults, { store -> DifficultyRamp in
            guard let savedRamp = store.string(forKey: Settings.difficultyRampKey),
                  let parsed = DifficultyRamp(rawValue: savedRamp) else {
                throw DefaultsGuardError.invalidValue(key: Settings.difficultyRampKey)
            }
            return parsed
        }) {
            self.difficultyRamp = ramp
        } else {
            self.difficultyRamp = .normal
        }
        
        // Tilt Control
        if defaults.object(forKey: Settings.tiltControlKey) == nil {
            self.tiltControlEnabled = true
            DefaultsGuard.write(on: defaults) { store in
                store.set(true, forKey: Settings.tiltControlKey)
            }
        } else {
            self.tiltControlEnabled = DefaultsGuard.read(from: defaults) { store in
                store.bool(forKey: Settings.tiltControlKey)
            } ?? true
        }
        
        // Tilt Sensitivity
        if defaults.object(forKey: Settings.tiltSensitivityKey) == nil {
            self.tiltSensitivity = 1.0
            DefaultsGuard.write(on: defaults) { store in
                store.set(1.0, forKey: Settings.tiltSensitivityKey)
            }
        } else {
            let storedValue = DefaultsGuard.read(from: defaults) { store in
                store.double(forKey: Settings.tiltSensitivityKey)
            } ?? 1.0
            self.tiltSensitivity = Settings.clampTiltSensitivity(storedValue)
        }
        
        // Color Theme
        if defaults.object(forKey: Settings.colorThemeKey) == nil {
            self.colorTheme = .neonBlue
            DefaultsGuard.write(on: defaults) { store in
                store.set(ColorTheme.neonBlue.rawValue, forKey: Settings.colorThemeKey)
            }
        } else if let theme = DefaultsGuard.read(from: defaults, { store -> ColorTheme in
            guard let raw = store.string(forKey: Settings.colorThemeKey),
                  let parsed = ColorTheme(rawValue: raw) else {
                throw DefaultsGuardError.invalidValue(key: Settings.colorThemeKey)
            }
            return parsed
        }) {
            self.colorTheme = theme
        } else {
            self.colorTheme = .neonBlue
        }
        
        // Music Volume
        if defaults.object(forKey: Settings.musicVolumeKey) == nil {
            self.musicVolume = 0.85
            DefaultsGuard.write(on: defaults) { store in
                store.set(0.85, forKey: Settings.musicVolumeKey)
            }
        } else {
            let storedValue = DefaultsGuard.read(from: defaults) { store in
                store.double(forKey: Settings.musicVolumeKey)
            } ?? 0.85
            self.musicVolume = Settings.clampAudioVolume(storedValue)
        }
        
        // SFX Volume
        if defaults.object(forKey: Settings.sfxVolumeKey) == nil {
            self.sfxVolume = 1.0
            DefaultsGuard.write(on: defaults) { store in
                store.set(1.0, forKey: Settings.sfxVolumeKey)
            }
        } else {
            let storedValue = DefaultsGuard.read(from: defaults) { store in
                store.double(forKey: Settings.sfxVolumeKey)
            } ?? 1.0
            self.sfxVolume = Settings.clampAudioVolume(storedValue)
        }
        
        // Glow Effects
        if defaults.object(forKey: Settings.glowEffectsEnabledKey) == nil {
            self.glowEffectsEnabled = true
            DefaultsGuard.write(on: defaults) { store in
                store.set(true, forKey: Settings.glowEffectsEnabledKey)
            }
        } else {
            self.glowEffectsEnabled = DefaultsGuard.read(from: defaults) { store in
                store.bool(forKey: Settings.glowEffectsEnabledKey)
            } ?? true
        }
        
        // Tutorial completion flag
        if defaults.object(forKey: Settings.hasSeenTutorialKey) == nil {
            self.hasSeenTutorial = false
            DefaultsGuard.write(on: defaults) { store in
                store.set(false, forKey: Settings.hasSeenTutorialKey)
            }
        } else {
            self.hasSeenTutorial = DefaultsGuard.read(from: defaults) { store in
                store.bool(forKey: Settings.hasSeenTutorialKey)
            } ?? false
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
    
    private static func clampAudioVolume(_ value: Double) -> Double {
        min(max(value, audioVolumeRange.lowerBound), audioVolumeRange.upperBound)
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
    
    /// Power-up color palette (ring + glow) for Slow Motion.
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
    
    /// Power-up color palette (ring + glow) for Invincibility.
    var invincibilityColor: (ring: (CGFloat, CGFloat, CGFloat),
                             glow: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .neonBlue:
            // White/Gold
            return (ring: (1.0, 0.95, 0.8), glow: (1.0, 1.0, 0.9))
        case .neonPurple:
            // Bright Lime Green
            return (ring: (0.4, 1.0, 0.2), glow: (0.5, 1.0, 0.3))
        case .synthwave:
            // Electric Blue/White
            return (ring: (0.8, 0.9, 1.0), glow: (0.9, 0.95, 1.0))
        }
    }
    
    /// Power-up color palette (ring + glow) for Attack Mode.
    var attackModeColor: (ring: (CGFloat, CGFloat, CGFloat),
                          glow: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .neonBlue:
            // Fiery Orange/Red
            return (ring: (1.0, 0.4, 0.1), glow: (1.0, 0.5, 0.2))
        case .neonPurple:
            // Hot Pink/Magenta
            return (ring: (1.0, 0.2, 0.6), glow: (1.0, 0.35, 0.7))
        case .synthwave:
            // Bright Green/Lime
            return (ring: (0.3, 1.0, 0.3), glow: (0.4, 1.0, 0.4))
        }
    }
}
