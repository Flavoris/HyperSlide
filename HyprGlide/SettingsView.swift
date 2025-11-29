//
//  SettingsView.swift
//  HyprGlide
//
//  Settings panel for configuring game preferences
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Solid backdrop for settings sheet
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with done button
                HStack {
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                // Settings Title
                Text("Settings")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Difficulty Section
                        settingsCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Difficulty")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Picker("Difficulty Ramp Speed", selection: $settings.difficultyRamp) {
                                    ForEach(DifficultyRamp.allCases, id: \.self) { ramp in
                                        Text(ramp.displayName).tag(ramp)
                                    }
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Fast mode increases difficulty ramp by 50%")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        
                        // Controls Section
                        settingsCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Controls")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Toggle(isOn: $settings.tiltControlEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Tilt Control")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        Text("Use device tilt to control player movement")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .tint(settings.colorTheme.primaryColor)
                                
                                tiltSensitivityControl
                            }
                        }
                        
                        // Audio Section
                        settingsCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Audio")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                audioSlider(title: "Music Volume",
                                            value: $settings.musicVolume)
                                
                                audioSlider(title: "SFX Volume",
                                            value: $settings.sfxVolume)
                                
                                Text("Dial in the mix between soundtrack and effects.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        
                        // Theme Section
                        settingsCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Theme")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                VStack(spacing: 12) {
                                    ForEach(ColorTheme.allCases, id: \.self) { theme in
                                        Button {
                                            settings.colorTheme = theme
                                        } label: {
                                            HStack(spacing: 16) {
                                                // Theme name
                                                Text(theme.displayName)
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                
                                                Spacer()
                                                
                                                // Color preview circles
                                                HStack(spacing: 8) {
                                                    Circle()
                                                        .fill(theme.primaryColor)
                                                        .frame(width: 28, height: 28)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                                        )
                                                    
                                                    Circle()
                                                        .fill(theme.secondaryColor)
                                                        .frame(width: 28, height: 28)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                                        )
                                                }
                                                
                                                // Checkmark for selected theme
                                                if settings.colorTheme == theme {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(theme.primaryColor)
                                                        .font(.system(size: 24, weight: .bold))
                                                } else {
                                                    Circle()
                                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                                                        .frame(width: 24, height: 24)
                                                }
                                            }
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if theme != ColorTheme.allCases.last {
                                            Divider()
                                                .background(Color.white.opacity(0.1))
                                        }
                                    }
                                }
                                
                                Text("Theme changes apply immediately")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .padding(.top, 6)
                                
                                Toggle(isOn: $settings.glowEffectsEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Neon Glow")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.white)
                                        
                                        Text("Control glow effect.")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .tint(settings.colorTheme.primaryColor)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
    
    // Helper to create consistent card styling
    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                    )
            )
    }
    
    private var tiltSensitivityControl: some View {
        let percentage = Int((settings.tiltSensitivity * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tilt Sensitivity")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(percentage)%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityLabel("Tilt sensitivity \(percentage) percent")
            }
            
            Slider(value: $settings.tiltSensitivity,
                   in: Settings.tiltSensitivityRange,
                   step: 0.05) {
                Text("Tilt Sensitivity Slider")
            }
                   .tint(settings.colorTheme.primaryColor)
                   .accessibilityValue("\(percentage) percent")
        }
        .padding(.top, 6)
        .opacity(settings.tiltControlEnabled ? 1 : 0.35)
        .allowsHitTesting(settings.tiltControlEnabled)
        .animation(.easeInOut(duration: 0.2), value: settings.tiltControlEnabled)
    }
    
    private func audioSlider(title: String,
                             value: Binding<Double>) -> some View {
        let percentage = Int((value.wrappedValue * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(percentage)%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityLabel("\(title) \(percentage) percent")
            }
            
            Slider(value: value,
                   in: Settings.audioVolumeRange,
                   step: 0.01) {
                Text(title)
            }
                   .tint(settings.colorTheme.primaryColor)
                   .accessibilityValue("\(percentage) percent")
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView(settings: Settings())
}
