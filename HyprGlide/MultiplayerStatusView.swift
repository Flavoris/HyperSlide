//
//  MultiplayerStatusView.swift
//  HyprGlide
//
//  Compact in-game HUD overlay for multiplayer status:
//  - Player list with alive/dead status and scores
//  - Slow-motion effect indicator when active
//

import SwiftUI

// MARK: - Multiplayer Status View

/// Main multiplayer status overlay shown in top-right during active matches.
/// Displays player list and any active slow-motion effects.
struct MultiplayerStatusView: View {
    @ObservedObject var multiplayerState: MultiplayerState
    @ObservedObject var gameState: GameState
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Slow-motion indicator (if active)
            if multiplayerState.isSlowMotionActive {
                SlowMotionIndicator(
                    isLocalPlayerCollector: multiplayerState.isLocalPlayerSlowMotionCollector,
                    remainingDuration: multiplayerState.slowMotionRemaining,
                    accentColor: accentColor
                )
            }
            
            // Player list
            PlayerListPanel(
                multiplayerState: multiplayerState,
                gameState: gameState,
                accentColor: accentColor
            )
        }
    }
}

// MARK: - Slow-Motion Indicator

/// Badge shown when a multiplayer slow-motion effect is active.
/// Clearly indicates who benefits from the effect.
struct SlowMotionIndicator: View {
    let isLocalPlayerCollector: Bool
    let remainingDuration: TimeInterval
    let accentColor: Color
    
    /// Collector (normal speed) gets cyan/green tint, others (slowed) get purple/red tint.
    private var indicatorColor: Color {
        isLocalPlayerCollector ? Color(red: 0.2, green: 0.9, blue: 0.6) : Color(red: 0.85, green: 0.3, blue: 0.8)
    }
    
    private var labelText: String {
        isLocalPlayerCollector ? "YOU'RE FASTER!" : "SLOWED"
    }
    
    private var iconName: String {
        isLocalPlayerCollector ? "hare.fill" : "tortoise.fill"
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
            
            Text(labelText)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
            
            // Remaining duration
            if remainingDuration > 0 {
                Text(String(format: "%.1fs", remainingDuration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(indicatorColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Capsule()
                        .stroke(indicatorColor.opacity(0.6), lineWidth: 1.5)
                )
        )
        .shadow(color: indicatorColor.opacity(0.5), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Player List Panel

/// Compact panel showing all players with alive/dead status and scores.
struct PlayerListPanel: View {
    @ObservedObject var multiplayerState: MultiplayerState
    @ObservedObject var gameState: GameState
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ForEach(sortedPlayers) { player in
                PlayerStatusRow(
                    player: player,
                    score: scoreForPlayer(player),
                    accentColor: accentColor
                )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.opacity(0.35), lineWidth: 1)
                )
        )
    }
    
    /// Sort players: local player first, then by score (descending), then alphabetically.
    private var sortedPlayers: [MultiplayerPlayer] {
        multiplayerState.players.sorted { lhs, rhs in
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal
            }
            let scoreL = lhs.finalScore ?? (lhs.isAlive ? 0 : 0)
            let scoreR = rhs.finalScore ?? (rhs.isAlive ? 0 : 0)
            if scoreL != scoreR {
                return scoreL > scoreR
            }
            return lhs.name < rhs.name
        }
    }
    
    /// Returns the display score for a player.
    /// For local player: use gameState.score. For others: use finalScore or 0.
    private func scoreForPlayer(_ player: MultiplayerPlayer) -> Int {
        if player.isLocal {
            return Int(gameState.score.rounded())
        } else {
            return Int((player.finalScore ?? 0).rounded())
        }
    }
}

// MARK: - Player Status Row

/// Individual row for a player showing name, status indicator, and score.
struct PlayerStatusRow: View {
    let player: MultiplayerPlayer
    let score: Int
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator circle
            Circle()
                .fill(player.isAlive ? Color.green : Color.red.opacity(0.7))
                .frame(width: 8, height: 8)
                .shadow(color: player.isAlive ? Color.green.opacity(0.6) : Color.red.opacity(0.4), radius: 4)
            
            // Player name
            Text(displayName)
                .font(.system(size: 12, weight: player.isLocal ? .bold : .medium, design: .rounded))
                .foregroundStyle(player.isLocal ? accentColor : .white.opacity(0.85))
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            // Score
            Text("\(score)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(player.isAlive ? .white.opacity(0.9) : .white.opacity(0.5))
            
            // Dead indicator
            if !player.isAlive {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .frame(minWidth: 120)
    }
    
    private var displayName: String {
        if player.isLocal {
            return "You"
        }
        // Truncate long names
        if player.name.count > 12 {
            return String(player.name.prefix(10)) + "…"
        }
        return player.name
    }
}

// MARK: - Preview

#Preview("Slow-Mo Active - You're Faster") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            SlowMotionIndicator(
                isLocalPlayerCollector: true,
                remainingDuration: 3.5,
                accentColor: Color.cyan
            )
            
            SlowMotionIndicator(
                isLocalPlayerCollector: false,
                remainingDuration: 2.1,
                accentColor: Color.cyan
            )
        }
    }
}

#Preview("Player List") {
    let state = MultiplayerState()
    state.players = [
        MultiplayerPlayer(id: "1", name: "You", isLocal: true, isAlive: true, currentX: 0),
        MultiplayerPlayer(id: "2", name: "PlayerTwo", isLocal: false, isAlive: true, currentX: 0),
        MultiplayerPlayer(id: "3", name: "VeryLongPlayerName", isLocal: false, isAlive: false, finalScore: 42)
    ]
    
    return ZStack {
        Color.black.ignoresSafeArea()
        
        PlayerListPanel(
            multiplayerState: state,
            gameState: GameState(),
            accentColor: Color.cyan
        )
        .padding()
    }
}

