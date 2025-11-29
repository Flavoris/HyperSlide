# HyprGlide Multiplayer Architecture Plan

## Current Architecture Summary

### `GameScene.swift` (~1,705 lines)
The main SpriteKit scene handling all game rendering and update logic:
- **Player control**: Drag-to-move and tilt-based controls via CoreMotion
- **Obstacles**: Dynamic spawning with difficulty scaling, uses an `ObstaclePool` for recycling
- **Power-ups**: Three types (`slowMotion`, `invincibility`, `attackMode`) with screen-edge overlays
- **Collision**: `SKPhysicsContactDelegate` handles player-obstacle and player-power-up contacts
- **Game feel**: Edge squish/bounce, camera shake, near-miss detection, haptics
- **Lifecycle**: Observes `UIScene.willDeactivateNotification` to auto-pause
- Holds weak references to `GameState`, `Settings`, `SoundManager`

### `GameState.swift` (~143 lines)
An `ObservableObject` tracking:
- `score`, `bestScore` (persisted to UserDefaults)
- Flags: `isGameOver`, `isPaused`, `hasStarted`
- `elapsed` time → `difficulty` (0→1 over 300s) and `level` (1–20)
- Actions: `startGame()`, `resetGame()`, `pauseGame()`, `resumeGame()`, `addDodge()`, `addNearMissBonus()`, etc.

### `ContentView.swift` (~78 lines)
Root SwiftUI view that:
- Owns `GameState`, `Settings`, `SoundManager` as `@StateObject`
- Creates and injects dependencies into `GameScene`
- Composes `SpriteView` + `HUDView` in a `ZStack`
- Reacts to settings changes (theme, tilt, volume)

### `HUDView.swift` (~379 lines)
SwiftUI overlay presenting:
- Score display (during gameplay)
- Start menu (title + START button)
- Game Over overlay (score, best, RESTART)
- Pause overlay (RESUME)
- Bottom bar with Pause/Resume button and Settings gear

---

## Proposed Multiplayer Architecture

### New Files & Responsibilities

| File | Purpose |
|------|---------|
| **`GameCenterManager.swift`** ✅ | Singleton handling all `GKLocalPlayer` authentication, access control, and `GKAccessPoint` configuration. Publishes `isAuthenticated` for reactive UI gating. |
| **`FriendsLeaderboardManager.swift`** | Fetches friends-only leaderboard entries via `GKLeaderboard.loadEntries(for:timeScope:)`. Exposes an observable `[LeaderboardEntry]` array for SwiftUI. *(integrated into GameCenterManager.swift)* |
| **`MultiplayerModels.swift`** ✅ | Framework-agnostic data models: `GameMode` enum, `MultiplayerPlayerSummary`, `MultiplayerPlayer` struct, `PlayerRanking`, and `MultiplayerState` ObservableObject with slow-motion tracking. |
| **`MultiplayerManager.swift`** ✅ | Wraps `GKMatchmaker` / `GKMatch`. Handles match finding, `GKMatchDelegate` callbacks, host election, message routing, and reliable/unreliable packet dispatch. |
| **`ArenaRandomizer.swift`** ✅ | Deterministic RNG (`SeededRandomNumberGenerator`) + spawn event structs (`ObstacleSpawnEvent`, `PowerUpSpawnEvent`). Generates identical spawn sequences from a shared seed. |
| **`SpawnEventHelpers.swift`** ✅ | Helper extensions for converting spawn events to scene nodes, plus `SpawnStateTracker` and `ActivePowerUpCounter` utilities. |
| **`MultiplayerStatusView.swift`** ✅ | Compact in-game HUD overlay showing player list with scores, alive/dead status, and slow-motion effect indicator. |
| **`MultiplayerGameOverView.swift`** ✅ | Post-match overlay showing winner, rankings by score, and rematch/menu options. |
| **`FriendsLeaderboardView.swift`** ✅ | SwiftUI sheet showing friends-only high scores with loading/error/empty states. Accessible from start menu. |

---

## Data Flow & Message Types

```
┌─────────────────────────────────────────────────────────────────┐
│                        ContentView                              │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐   │
│  │ GameState    │   │ Settings     │   │ MultiplayerState   │   │
│  └──────────────┘   └──────────────┘   └────────────────────┘   │
│          ▲                                      ▲               │
│          │                                      │               │
│    ┌─────┴────────────────────────────┐         │               │
│    │           GameScene              │◄────────┘               │
│    │  (local player + remote ghosts)  │                         │
│    └──────────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
 PlayerUpdate      ArenaEvent         MatchControl
 (position,score)  (spawn seed,       (pause, game over,
                    power-up ID)        rematch request)
```

### Message Structs (Codable)

| Message | Fields | Purpose |
|---------|--------|---------|
| `PlayerUpdate` | `positionX`, `score`, `isAlive`, `timestamp` | Sync player state at ~20Hz |
| `ArenaEvent` | `type`, `seed`, `spawnIndex` | Deterministic obstacle/power-up spawns |
| `MatchControl` | `action` (pause, gameOver, requestRematch) | Match lifecycle coordination |

---

## Extending Existing Files

### GameScene Extensions
- Add optional `multiplayerState: MultiplayerState?` property (nil = solo mode)
- In `update(_:)`, if multiplayer:
  - Send `PlayerUpdate` every ~3 frames via `MultiplayerMatchManager.send(data:mode:)`
  - Apply received `PlayerUpdate`s to ghost player nodes
- Replace local `random()` calls for spawning with `MultiplayerArenaSync.nextSpawnEvent(for: spawnIndex)` when in multiplayer mode
- On collision, broadcast `MatchControl.gameOver` so peers know you died

### GameState Extensions
- Add optional `multiplayerState: MultiplayerState?`
- Add computed `allPlayersGameOver` for determining match end
- Existing `recordBest()` optionally submits to Game Center leaderboard

### HUDView / ContentView Extensions

| Location | Addition |
|----------|----------|
| **Start Menu** | "Multiplayer" button → opens matchmaking sheet |
| **Start Menu** | "Friends Scores" button → opens `FriendsLeaderboardView` |
| **In-game HUD** | If multiplayer, show mini-indicators for other players (position + alive/dead) |
| **Game Over** | Show final standings for all players, "Rematch" button |
| **Settings** | Toggle to enable/disable Game Center, link to leaderboard |

---

## Game Center Integration Points

| Feature | API |
|---------|-----|
| Authentication | `GKLocalPlayer.local.authenticateHandler` |
| Friends-only leaderboard | `GKLeaderboard.loadEntries(for: .friends, timeScope:)` |
| Submit score | `GKLeaderboard.submitScore(_:context:player:)` |
| Realtime matchmaking | `GKMatchmaker.shared().findMatch(for:)` |
| Match communication | `GKMatch.send(_:to:dataMode:)` |

---

## Deterministic Arena Sync Strategy

**Implemented in `ArenaRandomizer.swift` and `SpawnEventHelpers.swift`:**

1. When match starts, host generates a random `UInt64` seed and broadcasts it
2. All clients call `GameScene.configureForMultiplayer(seed:config:)` with the shared seed
3. `ArenaRandomizer.nextObstacleEvent(...)` returns identical `ObstacleSpawnEvent` params on every device
4. Power-up spawns use `ArenaRandomizer.nextPowerUpEventIfNeeded(...)` with the same deterministic generator
5. For client-side replay, use `GameScene.processExternalObstacleEvent(_:)` and `processExternalPowerUpEvent(_:)`

**Multiplayer Power-Up Behavior (via `ArenaMultiplayerConfig`):**
- Power-ups can spawn even when other effects are active (stacking allowed)
- Maximum simultaneous active power-ups is capped (default: 2, configurable up to 3)
- Minimum spawn interval enforced to prevent flooding (default: 8 seconds)
- In single-player, classic behavior preserved (no stacking, spawn blocked while active)

---

## Implementation Phases

### Phase 1 – Game Center Foundation
- [x] Create `GameCenterManager.swift` with `authenticateLocalPlayer()`, published `isAuthenticated`
- [ ] Add authentication call in `HyprGlideApp.swift` on launch
- [x] Create `FriendsLeaderboardManager.swift` to fetch/expose friends scores *(integrated into `GameCenterManager.swift`)*
- [x] Create `FriendsLeaderboardView.swift` (SwiftUI list with player avatars, scores)
- [x] Wire "Friends Scores" button in `HUDView` start menu

### Phase 2 – Leaderboard Submission
- [x] Extend `GameState.recordBest()` to submit to `GKLeaderboard` when authenticated
- [ ] Define leaderboard ID in Info.plist / App Store Connect *(placeholder ID set in code: `hyprglide.friends.highscore`)*

### Phase 3 – Multiplayer Data Models
- [x] Create `MultiplayerPlayer.swift` (id, name, position, score, isAlive) *(implemented in `MultiplayerModels.swift`)*
- [x] Create `MultiplayerState.swift` (`ObservableObject` with `players`, `connectionStatus`, `matchSeed`) *(implemented in `MultiplayerModels.swift`)*
- [x] Add `GameMode` enum to branch single-player vs multiplayer *(in `MultiplayerModels.swift`)*
- [x] Add `@Published var mode: GameMode` to `GameState.swift`
- [x] Create `ArenaRandomizer.swift` with `SeededRandomNumberGenerator`, spawn event structs *(replaces planned MultiplayerArenaSync.swift)*
- [x] Create `SpawnEventHelpers.swift` with spawn event conversion and state tracking utilities
- [x] Define `ObstacleSpawnEvent`, `PowerUpSpawnEvent`, `ArenaEventStream` Codable message types
- [x] Define `PlayerUpdate`, `MatchControl` Codable message types *(implemented in `MultiplayerManager.swift` as `PlayerStateUpdatePayload`, `MatchEndPayload`, etc.)*

### Phase 4 – Match Management
- [x] Create `MultiplayerManager.swift` wrapping `GKMatchmaker` and `GKMatchDelegate`
- [x] Implement `startQuickMatch()`, `cancelMatchmaking()`, `sendMessage(type:payload:mode:)`
- [x] Handle `match(_:didReceive:fromRemotePlayer:)` to parse and dispatch messages
- [x] Implement host election (lexicographically smallest player ID)
- [x] Implement `MatchSetup` broadcast with shared seed and match start time
- [x] Implement power-up collection exclusivity via `PowerUpCollectedPayload`
- [x] Implement multiplayer slow-motion effect via `SlowMotionActivatedPayload`

### Phase 5 – GameScene Multiplayer Support
- [x] Add optional `multiplayerState` property *(implemented via `playerNodes` dictionary and `multiplayerManager` reference)*
- [x] Add ghost-player rendering (semi-transparent duplicates of player orb) *(implemented via `createRemotePlayerNode()` with 0.8 alpha)*
- [x] In `update()`, broadcast `PlayerUpdate` at throttled rate *(handled by MultiplayerManager's state update timer)*
- [x] Replace spawn randomness with seeded generator *(ArenaRandomizer integrated into GameScene)*
- [x] Add public methods for multiplayer configuration: `configureForMultiplayer(seed:config:)`, `configureWithEventStream(_:)`, `configureForSinglePlayer()`
- [x] Add external event processing: `processExternalObstacleEvent(_:)`, `processExternalPowerUpEvent(_:)`
- [x] Implement multiplayer power-up stacking with configurable limits via `ArenaMultiplayerConfig`
- [x] Broadcast `MatchControl.gameOver` on collision *(via MultiplayerManager.localPlayerDied())*
- [x] Define `MultiplayerSceneDelegate` protocol for scene-manager communication
- [x] Add `configureMultiplayerArena(players:localPlayerId:seed:startTime:manager:)` for full multiplayer setup
- [x] Implement `PlayerNodeContext` struct for tracking player nodes *(in GameSceneMultiplayer.swift)*
- [x] Implement `updateRemotePlayerPosition(playerId:x:velocityX:)` with smooth interpolation
- [x] Implement `MultiplayerSlowMotionTracker` where collector keeps normal speed, others slow down
- [x] Implement `PowerUpTracker` for multiplayer power-up collection exclusivity
- [x] Add visual death effect for remote players (`markRemotePlayerDead()`)

### Phase 6 – UI Integration
- [x] Integrate `MultiplayerState` into `ContentView` as `@StateObject`
- [x] Pass `multiplayerState` to `HUDView` (added `@ObservedObject` parameter)
- [x] Add "Multiplayer" button in `HUDView` start menu (placeholder — logs TODO, sets game mode)
- [x] Add `MultiplayerPlayerListView` component showing players with alive/dead status in HUDView *(upgraded to `MultiplayerStatusView.swift`)*
- [x] Create `MultiplayerStatusView.swift` (compact player list with scores and slow-mo indicator)
- [x] Wire actual Game Center matchmaking to MULTIPLAYER button *(via MultiplayerManager.startQuickMatch())*
- [x] Show in-game opponent indicators (ghost orbs in scene) *(implemented via remote player nodes with distinct colors)*
- [x] Post-match scoreboard with "Rematch" option *(implemented in `MultiplayerGameOverView.swift`)*
- [x] Slow-motion effect HUD indicator showing who benefits (collector vs others)

### Phase 7 – Polish & Edge Cases
- [x] Handle player disconnect gracefully (mark as dead, continue match) *(implemented in MultiplayerManager.handlePlayerDisconnect())*
- [ ] Implement reconnection logic if supported
- [ ] Add host migration if needed (or designate first player as authority)
- [x] Write unit tests for `SeededRandomGenerator`, message encoding/decoding *(implemented in `ArenaRandomizerTests.swift` and `MultiplayerMessageTests.swift`)*

### Phase 8 – Documentation
- [x] Update README.md with multiplayer documentation (features, rules, power-up behavior, Game Center setup)

---

## Summary

This plan adds **~11 new files** (✅ 9 completed: `GameCenterManager.swift`, `MultiplayerModels.swift`, `ArenaRandomizer.swift`, `SpawnEventHelpers.swift`, `MultiplayerManager.swift`, `GameSceneMultiplayer.swift`, `MultiplayerStatusView.swift`, `MultiplayerGameOverView.swift`, `FriendsLeaderboardView.swift`) plus **2 test files** (`ArenaRandomizerTests.swift`, `MultiplayerMessageTests.swift`), keeps each under 300 lines, and touches `GameScene`, `GameState`, `ContentView`, and `HUDView` with targeted extensions rather than rewrites.

**✅ README.md** has been updated to document all multiplayer features, power-up behaviors, and Game Center requirements.

**Key design principles:**
- Solo mode remains unchanged (multiplayer state is optional/nil)
- Deterministic RNG ensures all clients see identical arena events
- Message-based sync keeps network traffic minimal
- UI additions are additive, not disruptive to existing flows

---

## Runtime Interaction: MultiplayerManager ↔ GameScene

In multiplayer mode, the interaction between `MultiplayerManager` and `GameScene` follows this flow:

### Match Setup
1. **User initiates matchmaking** → `MultiplayerManager.startQuickMatch()` shows Game Center UI
2. **Match connected** → Manager elects host, host generates seed and broadcasts `MatchSetup`
3. **All clients receive setup** → Manager calls `GameScene.configureMultiplayerArena(players:localPlayerId:seed:startTime:manager:)`
4. **Scene creates player nodes** → One node per player with distinct colors; local player uses existing `player` property

### During Gameplay
5. **Local player movement** → Existing input code (drag/tilt) moves local player normally
6. **State broadcast** → `MultiplayerManager`'s timer calls scene delegate to get position, broadcasts `PlayerStateUpdate`
7. **Remote updates received** → Manager parses message, calls `GameScene.updateRemotePlayerPosition(playerId:x:velocityX:)`
8. **Obstacle/power-up spawning** → Host generates events via `ArenaRandomizer`, broadcasts to clients who call `processExternalObstacleEvent()`/`processExternalPowerUpEvent()`

### Power-Up Collection (Exclusivity)
9. **Local collision detected** → Scene checks `PowerUpTracker.isCollected()`, calls `MultiplayerManager.tryCollectPowerUp()`
10. **If authorized** → Apply effect locally, manager broadcasts `PowerUpCollectedPayload`
11. **Remote collection received** → Manager calls `GameScene.markPowerUpCollected(powerUpId:)` to remove power-up

### Slow-Motion (Collector Advantage)
12. **Local player collects slow-mo** → Scene activates `MultiplayerSlowMotionTracker` with local player as collector
13. **Broadcast activation** → Manager sends `SlowMotionActivatedPayload` to all peers
14. **Remote activation received** → Manager calls `GameScene.applyMultiplayerSlowMotion(collectorId:duration:isLocalPlayerCollector:)`
15. **Effect applied** → Collector moves at 100% speed, all others at 40% speed via `MultiplayerSlowMotionTracker.speedMultiplier(for:)`

### Death & Match End
16. **Local collision (fatal)** → Scene sets `isGameOver`, calls `MultiplayerManager.localPlayerDied(finalScore:eliminationTime:)`
17. **Remote death received** → Manager calls `MultiplayerState.eliminatePlayer()` and scene's `markRemotePlayerDead(playerId:)`
18. **Match ends** → Host broadcasts `MatchEnd` with rankings; manager updates state, scene can cleanup via `cleanupMultiplayerArena()`
