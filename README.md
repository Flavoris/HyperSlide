# HyprGlide iOS App

An iOS game built with SwiftUI and SpriteKit for iOS 16+.

## Project Structure

```
HyprGlide/
├── HyprGlide/
│   ├── HyprGlideApp.swift          # App entry point (@main)
│   ├── ContentView.swift            # Root view combining SpriteKit + SwiftUI
│   ├── GameScene.swift              # SpriteKit game scene with update loop
│   ├── GameState.swift              # Observable game state model
│   ├── HUDView.swift                # SwiftUI overlay for score and controls
│   └── Assets.xcassets/             # Asset catalog
└── HyprGlide.xcodeproj/            # Xcode project file
```

## Requirements

- **Xcode**: 14.0 or later
- **iOS Deployment Target**: 16.0 or later
- **Swift Version**: 5.0+

## Features

- **Endless Arcade Action**: Dodge obstacles in a high-speed, neon-soaked tunnel.
- **Progressive Difficulty**: The game gets faster and more intense the longer you survive.
- **Dynamic Obstacles**: Navigate through a variety of obstacle patterns, including wide slow barriers and narrow fast projectiles.
- **Power-Ups**: Collect "Slow Motion" power-ups to briefly slow down time and navigate tight squeezes.
- **Scoring System**: Earn points for survival time and "Near Miss" bonuses for risky maneuvers.
- **Themes**: Choose from multiple visual themes (Neon Blue, Neon Purple, Synthwave).
- **Haptic Feedback**: Immersive tactile feedback for collisions and interactions.

## Controls

HyprGlide supports two control schemes:

1. **Tilt Control (Default)**:
   - Tilt your device left or right to steer the player.
   - Adjust sensitivity in Settings.
   - *Requires "Motion Usage" permission.*

2. **Touch Control**:
   - Drag your finger anywhere on the screen to move the player horizontally.
   - Touch control overrides tilt when active.

## Settings

Access the settings menu from the main screen or pause menu to configure:

- **Controls**: Toggle Tilt Control on/off and adjust Tilt Sensitivity.
- **Difficulty**: Choose between "Normal" and "Fast" difficulty ramps.
- **Audio**: Adjust Music and Sound Effects volume independently.
- **Visuals**: Switch between color themes (Neon Blue, Neon Purple, Synthwave).

## Known Limitations

- **Landscape Mode**: Not supported in v1. The app requires full-screen portrait mode.
- **iPad Support**: Runs in portrait compatibility mode.

## Building the Project

### From Xcode
1. Open `HyprGlide.xcodeproj` in Xcode.
2. Select an iOS Simulator or device.
3. Press `Cmd + R` to build and run.

### From Command Line
```bash
xcodebuild -project HyprGlide.xcodeproj \
  -scheme HyprGlide \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## License

Created for HyprGlide game development.
