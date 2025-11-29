# HyprGlide iOS App

An iOS game built with SwiftUI and SpriteKit for iOS 16+.

## Project Structure

```
HyprGlide/
├── HyprGlide/
│   ├── HyprGlideApp.swift          # App entry point (@main)
│   ├── ContentView.swift            # Root view combining SpriteKit + SwiftUI
│   ├── GameScene.swift              # SpriteKit game scene with update loop
│   ├── GameSceneMultiplayer.swift   # Multiplayer extensions for GameScene
│   ├── GameState.swift              # Observable game state model
│   ├── HUDView.swift                # SwiftUI overlay for score and controls
│   ├── GameCenterManager.swift      # Game Center auth and leaderboards
│   ├── MultiplayerManager.swift     # Realtime match handling
│   ├── MultiplayerModels.swift      # Multiplayer data models
│   ├── ArenaRandomizer.swift        # Deterministic RNG for shared arena
│   ├── MultiplayerStatusView.swift  # In-game player status HUD
│   ├── MultiplayerGameOverView.swift # Post-match results overlay
│   ├── FriendsLeaderboardView.swift # Friends-only high scores
│   └── Assets.xcassets/             # Asset catalog
└── HyprGlide.xcodeproj/            # Xcode project file
```

## Requirements

- **Xcode**: 14.0 or later
- **iOS Deployment Target**: 16.0 or later
- **Swift Version**: 5.0+
- **Game Center**: Required for multiplayer and friends leaderboards

## Features

- **Endless Arcade Action**: Dodge obstacles in a high-speed, neon-soaked tunnel.
- **Progressive Difficulty**: The game gets faster and more intense the longer you survive.
- **Dynamic Obstacles**: Navigate through a variety of obstacle patterns, including wide slow barriers and narrow fast projectiles.
- **Power-Ups**: Collect power-ups including Slow Motion, Invincibility, and Attack Mode.
- **Scoring System**: Earn points for survival time and "Near Miss" bonuses for risky maneuvers.
- **Themes**: Choose from multiple visual themes (Neon Blue, Neon Purple, Synthwave).
- **Haptic Feedback**: Immersive tactile feedback for collisions and interactions.
- **Game Center Multiplayer**: Compete in real-time matches with 2–4 players in a shared arena.
- **Friends Leaderboard**: Compare high scores with your Game Center friends.

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
- **Visuals**: Switch between color themes (Neon Blue, Neon Purple, Synthwave) and disable the neon glow on the player icon and falling obstacles if it causes eye strain.

## Multiplayer

HyprGlide supports real-time **Game Center multiplayer** with a **shared arena**—all players see the same obstacles and power-ups.

### Starting a Match

1. From the start menu, tap **MULTIPLAYER**.
2. Game Center matchmaking will find 2–4 players.
3. Once matched, all players enter the same arena with a synchronized start.

> **Note:** Game Center must be enabled on your device and you must be signed in. If Game Center is unavailable, the MULTIPLAYER button will be disabled or show a friendly message.

### Match Rules

- The match **ends when only one player remains alive**.
- The **winner is the player with the highest final score**, not necessarily the last survivor.
- Survival alone isn't enough—rack up points through dodging and near-miss bonuses to claim victory.

### Power-Up Behavior: Single-Player vs Multiplayer

Power-ups work differently depending on game mode:

#### Slow-Motion

| Mode | Behavior |
|------|----------|
| **Single-Player** | Slows down time for everything, giving the player breathing room. |
| **Multiplayer** | The **collector** keeps normal movement speed while **all other players are slowed** for the effect duration. This creates a strategic advantage for the collector. |

- **Stacking**: In multiplayer, slow-motion can stack (extending duration), but is capped to keep gameplay fair.

#### Other Power-Ups (Invincibility, Attack Mode)

| Aspect | Single-Player | Multiplayer |
|--------|---------------|-------------|
| **Spawning** | Only one power-up spawns at a time; new ones wait until the current effect ends. | Power-ups can spawn even while other effects are active. |
| **Stacking** | Not applicable. | Effects can stack, but a global cap (default: 2 simultaneous active power-ups) prevents chaos. |
| **Collection** | Collected by the player on contact. | **First touch wins**—only one player can collect a specific power-up. Once collected, it disappears for everyone else immediately. |

### Friends Leaderboard

Compare your best scores with Game Center friends:

1. From the start menu, tap **FRIENDS SCORES**.
2. If not authenticated, you'll be prompted to sign in to Game Center.
3. View a ranked list of friends' high scores.

### Game Center Configuration

For multiplayer and leaderboards to function:

- **Device**: Game Center must be enabled and the user signed in.
- **Leaderboard ID**: The app uses the identifier `hyprglide.friends.highscore`. This must match your App Store Connect / Game Center configuration.
- **Entitlements**: The app must have the Game Center capability enabled in Xcode.

If Game Center is unavailable or authentication fails, the app gracefully falls back to single-player mode without crashes.

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
