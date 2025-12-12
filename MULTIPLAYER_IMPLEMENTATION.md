## HyprGlide Multiplayer Implementation Prompts (Game Center + Shared Arena)

This file contains **ready-to-use prompts** you can paste into Cursor’s chat (in Agent mode) to implement **Game Center-based multiplayer with a shared arena** for HyprGlide.

Each step is small and focused. Work through them in order. Do not skip ahead unless you know why.

> All prompts assume the workspace root is `/Users/flavorisbelue/Desktop/HyprGlide` and should respect your existing style:
> - Modular files, clear separation of concerns.
> - Descriptive naming, concise comments for non-obvious logic.
> - Keep files under ~300 lines where practical.

---

### Step 1 — Scan the project and establish the multiplayer architecture plan

Paste this into Cursor:

```text
You are an AI coding agent working on an iOS SpriteKit/SwiftUI game called HyprGlide.

Goal: Add Game Center–based multiplayer with a shared arena (all players in one obstacle field), plus friends-only high-score comparison. Before writing any code, scan the project and propose a concrete file-level architecture and data-flow plan.

Constraints and context:
- Workspace root: /Users/flavorisbelue/Desktop/HyprGlide
- Main game code lives in the HyprGlide/ directory (e.g. GameScene.swift, GameState.swift, ContentView.swift, HUDView.swift).
- Respect my project rules:
  - Keep code modular and well-factored with clear separation of concerns.
  - Prefer multiple smaller files over a few huge ones (ideally < 300 lines per file).
  - Use descriptive, intention-revealing names.
  - Add concise comments for non-obvious logic.
  - Follow Swift and project styling conventions already in the code.

Tasks:
1. Read these files and summarize how they work today (no edits yet):
   - /Users/flavorisbelue/Desktop/HyprGlide/HyprGlide/GameScene.swift
   - /Users/flavorisbelue/Desktop/HyprGlide/HyprGlide/GameState.swift
   - /Users/flavorisbelue/Desktop/HyprGlide/HyprGlide/ContentView.swift
   - /Users/flavorisbelue/Desktop/HyprGlide/HyprGlide/HUDView.swift
2. Propose a high-level multiplayer architecture that fits the existing structure, including:
   - Game Center integration for:
     - Authentication
     - Friends-only leaderboard (high scores)
     - Realtime matches (shared arena)
   - New types and files you intend to create (names + responsibilities), e.g.:
     - GameCenterManager
     - MultiplayerManager
     - MultiplayerState / MultiplayerPlayer models
     - Deterministic RNG / arena event structs if needed
   - How GameScene and GameState should be extended (not rewritten) to support multiplayer.
   - How HUDView/ContentView should surface:
     - A “Friends High Scores” view
     - A “Multiplayer” entry point
3. Output:
   - A concise but concrete plan (bulleted) that I can approve before you touch any code.
   - Do NOT modify any files in this step; this step is planning only.
```

---

### Step 2 — Create `GameCenterManager` (auth + friends leaderboard + score submission)

After approving Step 1’s plan, paste:

```text
Implement the Game Center integration layer as planned, focusing only on authentication, score submission, and friends-only leaderboard access.

Constraints:
- Create a new Swift file named GameCenterManager.swift under HyprGlide/.
- Keep the file under ~250–300 lines.
- Keep responsibilities narrow: no matchmaking in this file.
- Code should compile under current iOS + Xcode defaults for this project.

Requirements:
1. Implement a singleton-style, ObservableObject class: GameCenterManager.
   - Expose @Published properties for:
     - isAuthenticated: Bool
     - localPlayerName: String?
   - Provide a shared static instance for easy access.
2. Implement authentication:
   - Method: authenticateIfNeeded(presentingFrom: UIViewController?)
   - Wrap GKLocalPlayer.local.authenticateHandler.
   - Handle both:
     - Case where a view controller must be presented.
     - Case where authentication is already completed.
   - Update isAuthenticated and localPlayerName appropriately.
   - Add concise comments about when/where the host app should call this.
3. Score submission:
   - Method: submitBestScoreIfGameCenterAvailable(score: Double).
   - Convert score to Int64 (rounded).
   - Use a constant leaderboard identifier (e.g. "hyprglide.friends.highscore") and leave a clear TODO comment to align this with the App Store/Game Center config.
   - Silently ignore if not authenticated.
4. Friends-only leaderboard loading:
   - Add a method like loadFriendsLeaderboardTop(limit: Int, completion: @escaping (Result<[GKScore], Error>) -> Void).
   - Use GKLeaderboard with:
     - scope limited to friends-only / social group if API supports it (comment API variances by iOS version).
     - Provide a simple, well-commented implementation that callers can use to render a friends high-score list.
5. Integration hooks (no UI changes yet):
   - In GameState.recordBest(), add a call to GameCenterManager.shared.submitBestScoreIfGameCenterAvailable(score: score).
6. After coding:
   - Run a quick lints check (or whatever project tooling is present).
   - Do not add any UI for Game Center yet; that will come later.
   - Summarize key APIs you added so I can wire up UI in later steps.
```

---

### Step 3 — Add multiplayer data models and game mode

Once GameCenterManager exists, paste:

```text
Introduce explicit multiplayer models and a game mode concept to keep single-player and multiplayer logic cleanly separated.

Constraints:
- Create a new Swift file HyprGlide/MultiplayerModels.swift.
- Keep the file small and purely model-focused (no GameKit or UIKit here).
- Use descriptive, documented types.

Requirements:
1. Define an enum GameMode:
   - case singlePlayer
   - case multiplayer(matchId: String, localPlayerId: String, players: [MultiplayerPlayerSummary])
   - Keep it Equatable and Codable if that’s straightforward.
2. Define a struct MultiplayerPlayerSummary:
   - id: String          // Game Center player ID or similar
   - displayName: String
   - Optionally: isLocal: Bool (for convenience).
3. Define a richer multiplayer in-memory model for the current match:
   - final class MultiplayerState: ObservableObject
     - @Published players: [MultiplayerPlayer]       // detailed per-player state
     - @Published isMatchActive: Bool
     - @Published winner: MultiplayerPlayer?
   - struct MultiplayerPlayer: Identifiable, Codable
     - id: String
     - name: String
     - isLocal: Bool
     - isAlive: Bool
     - currentX: CGFloat        // latest known X position in arena
     - velocityX: CGFloat       // optional, for smoothing animation
     - finalScore: Double?
     - eliminationTime: TimeInterval?
   - Keep comments tight but clear about what each property is for.
4. Update GameState.swift to include:
   - @Published var mode: GameMode = .singlePlayer
   - Do NOT tangle GameKit into GameState; it should stay framework-agnostic.
5. Do not yet change GameScene or HUD logic in this step beyond any minimal wiring needed to compile.
6. When done, summarize:
   - The new types.
   - How GameState.mode will be used later to branch between single-player and multiplayer behavior.
```

---

### Step 4 — Wire `MultiplayerState` and `GameMode` into `ContentView` and `HUDView`

After Step 3 compiles:

```text
Integrate MultiplayerState and GameMode into the SwiftUI layer so we can later hook up Game Center matchmaking and shared-arena logic.

Constraints:
- Keep UI changes minimal and behind clean abstractions.
- Do not start Game Center matchmaking yet; this step is just wiring and some basic UI entry points.

Requirements:
1. In ContentView.swift:
   - Add @StateObject private var multiplayerState = MultiplayerState().
   - Pass multiplayerState into HUDView (by adding a new parameter) or into a new specialized overlay view that HUDView composes.
   - Ensure existing behavior for single-player remains unchanged when GameState.mode == .singlePlayer.
2. Update HUDView.swift:
   - Add an @ObservedObject var multiplayerState: MultiplayerState parameter (or similar) with minimal changes to call sites.
   - In the start menu overlay:
     - Keep the existing START (single-player) button as-is.
     - Add a new button labeled MULTIPLAYER that will eventually trigger Game Center matchmaking.
     - For now, when MULTIPLAYER is tapped, just set GameState.mode to .multiplayer with a placeholder matchId and no players, and log/print a TODO about starting matchmaking.
   - Add a small, non-intrusive section that, when in multiplayer mode and a match is active, shows:
     - A simple list of players with an indicator (alive/dead).
     - The local player clearly highlighted.
3. Keep layout visually clean and in the style of the existing HUD (fonts, neon-ish accents).
4. Ensure the app still runs and behaves identical to before when GameState.mode == .singlePlayer.
5. Summarize the new UI surfaces that we will connect to GameCenterManager and MultiplayerManager in later steps.
```

---

### Step 5 — Implement deterministic arena RNG and spawn events (with multiplayer power-up rules)

For a full shared arena, all players should see the same obstacles and power-ups. After the UI wiring is done, paste:

```text
Refactor obstacle and power-up spawning so that a single stream of deterministic "arena events" can drive all clients in a multiplayer match, while also encoding the special multiplayer power-up rules.

Constraints:
- Avoid making GameScene.swift even larger if possible: prefer extracting helper logic into a new file.
- Preserve single-player behavior and feel; multiplayer should be a strict extension.

Requirements:
1. Create a new file HyprGlide/ArenaRandomizer.swift (or similarly named) that defines:
   - A SeededRandomNumberGenerator (e.g. wrapping GKARC4RandomSource or a simple LCG) that:
     - Is initialized with a UInt64 seed.
     - Exposes deterministic random(in:) helpers for Double and CGFloat.
   - Lightweight structs describing spawn events, e.g.:
     - struct ObstacleSpawnEvent: Codable { timeOffset: TimeInterval, width: CGFloat, speedY: CGFloat, x: CGFloat, isEdgePunish: Bool }
     - struct PowerUpSpawnEvent: Codable { timeOffset: TimeInterval, type: PowerUpType, x: CGFloat, speedY: CGFloat }
   - A simple API like ArenaRandomizer that, given difficulty progression + seed, can be advanced step-by-step to produce the next spawn event.
   - Explicitly support:
     - Multiplayer mode where power-ups **can spawn even if other power-ups are active**, but still with reasonable spacing so it “doesn’t overdo it”.
     - A configurable max number of *simultaneously active* power-ups (e.g. 2–3) in multiplayer to prevent chaos.
2. Update GameScene:
   - Introduce a mode where obstacle and power-up spawning can be driven by an external stream of spawn events (for multiplayer).
   - In single-player mode, keep using the current logic but internally route through the new deterministic generator so that behavior is consistent.
   - In multiplayer mode:
     - Allow power-up spawn events to occur even when another power-up is already active, and allow stacking of effects.
     - Keep stacking “reasonable” by:
       - Enforcing the same global cap on simultaneous active power-ups mentioned above.
       - Keeping spawn intervals bounded so you don’t flood the arena.
   - Extract as much spawning logic as possible into small helpers to keep GameScene manageable.
3. Keep GameState unaware of the RNG implementation details.
4. After refactoring, verify:
   - Obstacles and power-ups still appear as before in single-player mode.
   - It’s possible (conceptually) for a single host to generate spawn events and broadcast them, and for clients to replay them to see the same arena.
5. Summarize:
   - New types and APIs for deterministic spawning.
   - How GameScene will later accept externally provided spawn events for multiplayer matches.
   - How the multiplayer-specific power-up behavior differs from single-player (stacking allowed, but globally capped).
```

---

### Step 6 — Create `MultiplayerManager` for Game Center realtime matches

Once deterministic spawning is in place, paste:

```text
Implement a MultiplayerManager responsible for all Game Center realtime match handling and high-level multiplayer orchestration (but not rendering).

Constraints:
- New file: HyprGlide/MultiplayerManager.swift.
- Keep responsibilities well-scoped:
  - GameKit match lifecycle
  - Networking (encode/decode messages)
  - Coordination between GameCenter and local state (GameState + MultiplayerState + GameScene hooks).
- No SpriteKit rendering code here.

Requirements:
1. Define a final class MultiplayerManager: NSObject, ObservableObject:
   - Uses GameKit (GKMatch, GKMatchmaker, etc.).
   - Holds weak references or callbacks to:
     - GameState
     - MultiplayerState
     - GameScene (or a protocol it conforms to) for pushing arena events + remote player updates.
2. Matchmaking:
   - Provide a method startQuickMatch(from viewController: UIViewController) that:
     - Ensures GameCenterManager is authenticated (calling authenticateIfNeeded if needed).
     - Uses GKMatchmaker to create/join a small match (e.g. 2–4 players).
     - On success, stores the GKMatch and sets itself as GKMatchDelegate.
3. Host election and match setup:
   - Decide a deterministic host (e.g. player with lexicographically smallest playerID).
   - Host:
     - Generates a UInt64 arenaSeed and a matchStartTime some small delta in the future.
     - Collects a list of players as MultiplayerPlayerSummary.
     - Broadcasts a MatchSetup message to all peers.
   - All peers (including host) upon receiving MatchSetup:
     - Set GameState.mode = .multiplayer(...)
     - Initialize MultiplayerState.players with the provided players.
     - Configure GameScene for multiplayer with the shared seed and start time.
4. Message protocol:
   - Define Codable message types in a small nested namespace or a separate model file, e.g.:
     - enum MultiplayerMessageType { case matchSetup, playerStateUpdate, obstacleSpawn, powerUpSpawn, playerDied, matchEnd }
     - struct MultiplayerMessage { type: MultiplayerMessageType, payload: Data }
   - Implement encoding/decoding helpers.
   - Use GKMatch.sendData(toAllPlayers:with:) with reliable/unreliable modes depending on message type (e.g. playerStateUpdate can be unreliable).
5. Runtime updates:
   - Player state updates:
     - At a modest frequency (e.g. 10–20 Hz), the local player sends its current X position (and velocity if helpful).
     - On receipt, MultiplayerManager updates MultiplayerState for that player and notifies GameScene to update remote player nodes.
   - Arena spawn events:
     - Host uses the deterministic RNG to generate spawn events and sends them out.
     - All clients, including host, feed those events into their GameScene instance so everyone sees the same obstacles/power-ups.
6. Death and match end:
   - When a local player dies, GameScene notifies MultiplayerManager.
   - MultiplayerManager:
     - Updates MultiplayerState to mark that player dead.
     - Broadcasts a playerDied message (reliable).
   - Host:
     - Tracks alive vs. dead players.
     - When only one player remains alive, declares the match over.
     - Computes **final rankings by score**, not just survival:
       - The “match end” condition is “only one player left alive”.
       - The actual **winner is the player with the highest score**, even if they died earlier than the last survivor.
       - Include in MatchEnd payload both:
         - The ordered list of players by final score (descending).
         - The id of the highest-scoring winner.
     - Sends a matchEnd message with this full ranking information.
   - Clients:
     - Update MultiplayerState.winner and set isMatchActive to false.
7. Slow-motion multiplayer effect:
   - Ensure that when **any player** collects a slow-motion power-up in multiplayer:
     - MultiplayerManager determines a single **authoritative collector** for that power-up (see also the exclusivity rules below).
     - MultiplayerManager broadcasts a message describing the slow-motion activation (collector id, type, duration, stack info).
     - All clients apply a global slow-motion effect that:
       - **Slows down every player except the collector**, so the collector keeps normal speed while others move slower.
       - Also slows obstacle/power-up movement as needed to keep game feel consistent, while still giving the collector an advantage.
     - Respect stacking rules from Step 5:
       - Allow multiple slow-motion activations to extend/stack duration.
       - But clamp the total effective slow-motion duration or intensity to prevent it from becoming extreme/abusive.
8. Power-up collection exclusivity:
   - Implement logic so that **only one player can collect a given power-up**:
     - When multiple players are near a power-up, whichever player’s collection event is processed first (host-authoritative or via a tie-break rule) becomes the sole collector.
     - After a power-up is collected:
       - It is removed from the arena on all clients.
       - Further collisions with that power-up are ignored.
   - Encode this clearly in the power-up collection messages (e.g. include power-up id and collector id).
9. Keep code well-commented where the control flow is non-obvious (host vs peers, message handling, slow-motion propagation, power-up exclusivity).
10. Run lints/compile after changes and summarize:
   - Public APIs on MultiplayerManager that GameScene and HUDView/ContentView should call.
```

---

### Step 7 — Update `GameScene` for shared-arena multiplayer (multiple players rendered)

After MultiplayerManager compiles, paste:

```text
Extend GameScene so that it can render and update multiple players in a shared arena, using MultiplayerManager for networking.

Constraints:
- Minimize disruption to existing single-player code.
- Keep changes to GameScene logically grouped and well-commented.
- If it gets too large, consider extracting small helper types or extensions to new files.

Requirements:
1. Player representation:
   - Introduce a new internal model to track multiple player nodes, e.g.:
     - struct PlayerNodeContext { id: String; isLocal: Bool; node: SKShapeNode }
   - Maintain a dictionary [String: PlayerNodeContext] keyed by playerId.
   - The existing single 'player' property should become the local player’s node; add clear comments to avoid confusion.
2. Multiplayer configuration:
   - Add a method configureMultiplayerArena(players: [MultiplayerPlayerSummary], localPlayerId: String, seed: UInt64, startTime: TimeInterval, manager: MultiplayerManager).
     - Create SKShapeNode players for each participant (distinct colors or subtle variations if possible).
     - Position all players at appropriate starting positions in the lane (e.g. spread slightly horizontally).
     - Initialize the deterministic RNG / arena spawner with the shared seed.
   - Ensure this method does NOT run in single-player mode.
3. Game loop integration:
   - When in multiplayer mode:
     - Use externally provided spawn events from MultiplayerManager instead of the internal spawn timer.
     - Still reuse as much of the obstacle/power-up update code as possible.
   - For the local player:
     - Keep using existing input + movement code.
     - Periodically (e.g. every N frames or based on time) report current X/velocity to MultiplayerManager so it can broadcast.
   - For remote players:
     - Provide an API (e.g. updateRemotePlayerPosition(playerId:x:velocity:) called by MultiplayerManager) that:
       - Smoothly interpolates their SKNodes to the latest X position.
4. Collision and death:
   - Local collision logic remains authoritative for the local player:
     - On collision, mark GameState.isGameOver, reset power-ups, etc. as today.
     - Additionally, notify MultiplayerManager that the local player died with elapsed + score.
   - Remote players’ deaths are driven by MultiplayerManager via a callback, which should:
     - Mark them visually as dead (e.g. fade out, tint red, or explode).
5. Multiplayer slow-motion behavior:
   - When in multiplayer mode and a slow-motion power-up is activated by **any** player:
     - Treat that player as the **collector** and keep their movement at normal speed.
     - Apply the slow-motion effect to:
       - All **other players' movement** (local or remote).
       - Obstacle and power-up movement as appropriate so that the net effect is: the collector feels relatively faster/more agile than opponents.
     - Ensure stacking behavior:
       - Multiple overlapping slow-motion activations extend total duration and/or intensify the effect within reasonable caps.
       - Follow the stacking and cap rules defined in Steps 5 and 6 so you “don’t overdo it”.
6. Power-up exclusivity in GameScene:
   - Ensure that only one player can collect any given power-up instance:
     - Implement local collision handling that prevents double-collection of the same PowerUpNode.
     - Coordinate with MultiplayerManager so that once a power-up is marked collected by a specific player, other clients immediately remove/ignore it.
   - Document how ties or near-simultaneous collisions are resolved (e.g. host wins ties, first message received, etc.).
7. Visual clarity:
   - Ensure that multiple players are clearly distinguishable:
     - Either via color, glow variation, or outlines.
   - Keep the existing neon aesthetic.
8. Preserve single-player behavior:
   - When GameState.mode == .singlePlayer, behavior and visuals should be as close as possible to current.
9. After coding:
   - Verify everything compiles.
   - Briefly describe how MultiplayerManager and GameScene now interact at runtime in multiplayer mode (who calls what).
```

---

### Step 8 — Enhance HUD for multiplayer status and friends-only leaderboard UI

Once GameScene multiplayer behavior is in place, paste:

```text
Finish the multiplayer UX by:
1) Surfacing clear multiplayer status in the HUD, and
2) Adding a friends-only leaderboard view using GameCenterManager.

Constraints:
- Maintain the existing visual style.
- Keep HUDView.swift from becoming too large; consider small subviews where appropriate.

Requirements:
1. Multiplayer status HUD:
   - In HUDView (or a dedicated subview), when GameState.mode is multiplayer and MultiplayerState.isMatchActive is true:
     - Show a compact horizontal or vertical stack listing:
       - Each player’s name, an alive/dead indicator, and possibly their current score.
       - Highlight the local player.
   - After the match ends:
     - Show a variant of the Game Over overlay that:
       - Displays the **winner’s name**, defined as the player with the highest final score (per Step 6), even if they were not the last survivor.
       - Shows a simple ranking of players ordered by **final score (descending)**; survival time can be shown as secondary information.
2. Indicate slow-motion effects visually in multiplayer:
   - When a multiplayer slow-motion effect is active:
     - Clearly show this in the HUD (e.g. a small “SLOW-MO ACTIVE” badge or icon).
     - Make it clear that the effect is **benefiting the collector** (e.g. labeling “You’re faster!” for the local collector vs “Slowed” for others).
     - Optionally show stacked intensity or remaining duration in a compact way.
3. Friends-only leaderboard UI:
   - Add a button in the start menu overlay labeled HIGH SCORES.
   - Tapping it should:
     - Trigger GameCenterManager.authenticateIfNeeded if not already authenticated.
     - Then present either:
       - A custom SwiftUI sheet pulling data via GameCenterManager.loadFriendsLeaderboardTop, or
       - A GKGameCenterViewController configured for the friends-only leaderboard.
   - If you choose a custom SwiftUI sheet:
     - Build a simple list view that:
       - Shows rank, display name, and score.
       - Handles basic loading/error/empty states.
4. Make sure the new UI states degrade gracefully:
   - If Game Center is unavailable or the user is not authenticated, show a friendly message instead of crashing.
5. Keep the code modular:
   - If necessary, create small SwiftUI views like MultiplayerStatusView and FriendsLeaderboardView in separate files.
6. Confirm:
   - Single-player flow is unaffected.
   - Multiplayer flow shows clear state from lobby → active match → winner/results.
```

---

### Step 9 — Add focused tests for deterministic RNG and message encoding

Finally, once everything works manually, paste:

```text
Add lightweight tests to guard the most fragile multiplayer pieces: deterministic RNG and message encoding/decoding.

Constraints:
- Reuse the existing HyprSlideTests target if appropriate, or create a focused test file under it.
- Keep tests small, fast, and focused on correctness of logic (not UI).

Requirements:
1. Deterministic RNG tests:
   - Add a test file (e.g. ArenaRandomizerTests.swift) that:
     - Creates two instances of the seeded RNG with the same seed and verifies they produce identical sequences of values.
     - Verifies that obstacle/power-up spawn events match across instances when advanced with the same calls.
2. Multiplayer message encoding tests:
   - Add tests to verify that:
     - Each message type (matchSetup, playerStateUpdate, obstacleSpawn, playerDied, matchEnd) round-trips correctly through your encoding/decoding pipeline.
     - No unexpected crashes or data loss for typical payloads.
3. Keep tests well-named and documented so future changes to multiplayer see clear failures when invariants break.
4. Run the full test suite and report any issues that seem related to the new code.
```

---

### Step 10 — Update the README with multiplayer information

After all multiplayer features are working, paste:

```text
Update README.md to document the new multiplayer features and behaviors.

Constraints:
- Keep the README concise but informative for new contributors and players.
- Follow the existing style and structure of README.md as much as possible.

Requirements:
1. Add a new "Multiplayer" section that covers:
   - That the game supports Game Center multiplayer with a shared arena (all players see the same obstacles and power-ups).
   - How to start a multiplayer match from within the app (which menu/button).
   - The rule that the **match ends when only one player is left alive, but the winner is the player with the highest final score**, not necessarily the last survivor.
2. Document power-up behavior in multiplayer vs single-player:
   - Slow-motion power-ups:
     - In single-player: affect only the local player’s run as currently implemented.
     - In multiplayer: when any player collects slow-motion:
       - That player (the **collector**) keeps normal movement speed.
       - All **other players** are slowed for the effect duration, making it harder for them.
     - Stacking rules: slow-motion can stack in multiplayer (extending duration and/or effect) but is capped to keep gameplay fair.
   - Other power-ups:
     - Note that in multiplayer, power-ups are allowed to spawn even while others are active and can stack, but there is a global cap to prevent excessive stacking.
     - Clarify that **only one player can collect a specific power-up instance** (“first touch wins”), and the power-up disappears for everyone else immediately after collection.
3. Briefly describe Game Center dependencies:
   - Mention that Game Center must be enabled on the device and that the Game Center configuration (leaderboard id, etc.) must match the identifiers used in GameCenterManager.
4. If present, update any "Features" or "Roadmap" sections to reflect that multiplayer and friends-only high scores are now implemented features rather than planned ones.
5. Ensure the README remains accurate with respect to:
   - Single-player behavior.
   - Multiplayer behavior and edge cases (e.g., what happens if Game Center is unavailable).
```

---

You can now work through these prompts one by one in Cursor to gradually implement **Game Center multiplayer with a shared arena and friends-only high scores** while keeping your codebase clean and modular, with the additional multiplayer rules you requested (global slow-motion, stacking power-ups with caps, and score-based winner selection).
