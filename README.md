# HyperSlide iOS App

An iOS game built with SwiftUI and SpriteKit for iOS 17+.

## Project Structure

```
HyperSlide/
├── HyperSlide/
│   ├── HyperSlideApp.swift          # App entry point (@main)
│   ├── ContentView.swift            # Root view combining SpriteKit + SwiftUI
│   ├── GameScene.swift              # SpriteKit game scene with update loop
│   ├── GameState.swift              # Observable game state model
│   ├── HUDView.swift                # SwiftUI overlay for score and controls
│   └── Assets.xcassets/             # Asset catalog
│       ├── AppIcon.appiconset/      # App icon
│       ├── NeonBlue.colorset/       # Custom blue color
│       ├── NeonPurple.colorset/     # Custom purple color
│       └── DarkBG.colorset/         # Dark background color
└── HyperSlide.xcodeproj/            # Xcode project file
```

## Requirements

- **Xcode**: 15.0 or later
- **iOS Deployment Target**: 17.0 or later
- **Swift Version**: 5.9+

## Features

### Architecture
- **SwiftUI + SpriteKit Hybrid**: ContentView uses ZStack to overlay SwiftUI HUD on SpriteKit game scene
- **Observable Pattern**: GameState uses `@Observable` macro for reactive state management
- **Delegate Pattern**: GameState injected into GameScene for seamless communication

### Game State Management
- Score tracking with best score persistence
- Game status (playing, paused, game over)
- Elapsed time tracking
- Progressive difficulty system (increases 10% every 30 seconds)

### UI Components
- **Top Bar**: Displays current score and best score
- **Game Scene**: Near-black background (RGB: 0.05, 0.05, 0.08)
- **Control Buttons**: Pause/Resume and Restart functionality
- **Overlays**: Full-screen overlays for pause and game over states

## Building the Project

### From Xcode
1. Open `HyperSlide.xcodeproj` in Xcode
2. Select an iOS Simulator or device
3. Press `Cmd + R` to build and run

### From Command Line
```bash
cd /Users/flavorisbelue/Desktop/HyperSlide

# Build for iOS Simulator
xcodebuild -project HyperSlide.xcodeproj \
  -scheme HyperSlide \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build \
  CODE_SIGNING_ALLOWED=NO
```

## Build Status

✅ **BUILD SUCCEEDED**

The app compiles successfully with no errors or warnings (except metadata extraction which is optional).

## Current State

The app currently displays:
- Near-black game scene background
- HUD overlay showing "Score: 0  Best: 0"
- Pause button (bottom left)
- Restart button (bottom right)
- Responsive pause and game over overlays

## Next Steps

To extend the game functionality, consider adding:
1. Player character with touch controls
2. Obstacles and collision detection
3. Score increment logic
4. Power-ups and special effects
5. Sound effects and background music
6. Leaderboards and achievements

## Code Quality

The codebase follows best practices:
- ✅ Modular architecture with clear separation of concerns
- ✅ Descriptive naming conventions
- ✅ Inline documentation for complex logic
- ✅ All files under 300 lines of code
- ✅ Proper error handling patterns
- ✅ iOS coding standards compliance

## Testing

To test the app:
1. Build and run in iOS Simulator
2. Verify the HUD displays correctly
3. Test pause/resume functionality
4. Test restart functionality
5. Verify the game scene renders properly

## License

Created for HyperSlide game development.

