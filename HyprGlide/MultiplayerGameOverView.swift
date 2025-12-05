//
//  MultiplayerGameOverView.swift
//  HyprGlide
//
//  Game Over overlay for multiplayer matches displaying:
//  - Winner's name (highest final score)
//  - Rankings of all players by score
//  - Restart and menu options
//

import SwiftUI

// MARK: - Multiplayer Game Over View

/// Full-screen overlay shown when a multiplayer match ends.
/// Displays winner, rankings, and action buttons.
struct MultiplayerGameOverView: View {
    @ObservedObject var multiplayerState: MultiplayerState
    @ObservedObject var gameState: GameState
    let accentColor: Color
    let onRestart: () -> Void
    let onMainMenu: () -> Void
    
    /// Gold color for the winner crown.
    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0)
    
    /// Silver for 2nd place.
    private let silverColor = Color(red: 0.75, green: 0.75, blue: 0.78)
    
    /// Bronze for 3rd place.
    private let bronzeColor = Color(red: 0.8, green: 0.5, blue: 0.2)
    
    var body: some View {
        let isWaitingForRematch = multiplayerState.rematchState == .waitingForPlayers
        
        VStack(spacing: 20) {
            // Match Complete Header
            Text("MATCH COMPLETE")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)
                .tracking(3)
            
            // Winner Section
            if let winner = multiplayerState.winner {
                WinnerBanner(
                    winner: winner,
                    goldColor: goldColor,
                    isLocalPlayer: winner.isLocal
                )
            }
            
            // Rankings List
            RankingsList(
                rankings: buildRankings(),
                accentColor: accentColor,
                goldColor: goldColor,
                silverColor: silverColor,
                bronzeColor: bronzeColor
            )
            .frame(maxHeight: 200)
            
            // Your Score (if local player participated)
            if let localRanking = buildRankings().first(where: { $0.isLocal }) {
                LocalPlayerResult(
                    ranking: localRanking,
                    isWinner: multiplayerState.winner?.isLocal ?? false,
                    accentColor: accentColor
                )
            }
            
            // Action Buttons
            VStack(spacing: 14) {
                // Rematch Button
                Button(action: onRestart) {
                    HStack(spacing: 10) {
                        if isWaitingForRematch {
                            ProgressView()
                                .tint(accentColor)
                        }
                        Text(isWaitingForRematch ? "WAITING..." : "REMATCH")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(accentColor)
                            .tracking(2)
                    }
                    .padding(.horizontal, 45)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 50)
                            .strokeBorder(accentColor, lineWidth: 2.5)
                    )
                }
                .accessibilityLabel("Play another match")
                .disabled(isWaitingForRematch)
                
                // Main Menu Button
                Button(action: onMainMenu) {
                    Text("MAIN MENU")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .tracking(1)
                }
                .accessibilityLabel("Return to main menu")
            }
            .padding(.top, 10)
            
            if isWaitingForRematch {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(accentColor)
                    Text("Waiting for other players to confirm rematch...")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: accentColor.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    /// Builds rankings from MultiplayerState players, sorted by final score descending.
    private func buildRankings() -> [PlayerRanking] {
        // If we already have final rankings set, use those
        if !multiplayerState.finalRankings.isEmpty {
            return multiplayerState.finalRankings
        }
        
        // Otherwise, build from players
        let sorted = multiplayerState.players.sorted { p1, p2 in
            let score1 = p1.finalScore ?? (p1.isLocal ? gameState.score : 0)
            let score2 = p2.finalScore ?? (p2.isLocal ? gameState.score : 0)
            return score1 > score2
        }
        
        return sorted.enumerated().map { index, player in
            let score = player.finalScore ?? (player.isLocal ? gameState.score : 0)
            return PlayerRanking(
                id: player.id,
                displayName: player.name,
                finalScore: score,
                rank: index + 1,
                isLocal: player.isLocal,
                survivalTime: player.eliminationTime
            )
        }
    }
}

// MARK: - Winner Banner

/// Prominent banner displaying the match winner.
struct WinnerBanner: View {
    let winner: MultiplayerPlayer
    let goldColor: Color
    let isLocalPlayer: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Crown icon
            Image(systemName: "crown.fill")
                .font(.system(size: 36))
                .foregroundStyle(goldColor)
                .shadow(color: goldColor.opacity(0.6), radius: 12)
            
            // Winner text
            Text(isLocalPlayer ? "YOU WIN!" : "WINNER")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(goldColor.opacity(0.8))
                .tracking(2)
            
            // Winner name
            Text(isLocalPlayer ? "🎉" : winner.name)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [goldColor.opacity(0.15), goldColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(goldColor.opacity(0.4), lineWidth: 1.5)
                )
        )
    }
}

// MARK: - Rankings List

/// Scrollable list of all player rankings.
struct RankingsList: View {
    let rankings: [PlayerRanking]
    let accentColor: Color
    let goldColor: Color
    let silverColor: Color
    let bronzeColor: Color
    
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(rankings) { ranking in
                    RankingRow(
                        ranking: ranking,
                        medalColor: medalColor(for: ranking.rank),
                        accentColor: accentColor
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    private func medalColor(for rank: Int) -> Color? {
        switch rank {
        case 1: return goldColor
        case 2: return silverColor
        case 3: return bronzeColor
        default: return nil
        }
    }
}

// MARK: - Ranking Row

/// Individual row showing player rank, name, and score.
struct RankingRow: View {
    let ranking: PlayerRanking
    let medalColor: Color?
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank indicator (medal or number)
            ZStack {
                if let medal = medalColor {
                    Circle()
                        .fill(medal.opacity(0.2))
                        .overlay(
                            Circle()
                                .stroke(medal.opacity(0.5), lineWidth: 1)
                        )
                    
                    Text("\(ranking.rank)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(medal)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                    
                    Text("\(ranking.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 28, height: 28)
            
            // Player name
            Text(displayName)
                .font(.system(size: 14, weight: ranking.isLocal ? .bold : .medium, design: .rounded))
                .foregroundStyle(ranking.isLocal ? accentColor : .white.opacity(0.85))
                .lineLimit(1)
            
            if ranking.isLocal {
                Text("(You)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.6))
            }
            
            Spacer()
            
            // Score
            Text("\(Int(ranking.finalScore.rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ranking.isLocal ? accentColor.opacity(0.1) : Color.white.opacity(0.05))
        )
    }
    
    private var displayName: String {
        if ranking.isLocal {
            return "You"
        }
        if ranking.displayName.count > 14 {
            return String(ranking.displayName.prefix(12)) + "…"
        }
        return ranking.displayName
    }
}

// MARK: - Local Player Result

/// Summary of the local player's result in the match.
struct LocalPlayerResult: View {
    let ranking: PlayerRanking
    let isWinner: Bool
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("YOUR SCORE")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1)
            
            Text("\(Int(ranking.finalScore.rounded()))")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(isWinner ? Color(red: 1.0, green: 0.84, blue: 0.0) : .white)
            
            Text("Rank #\(ranking.rank)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor.opacity(0.8))
        }
    }
}

// MARK: - Preview

#Preview("Multiplayer Game Over - Winner") {
    let state = MultiplayerState()
    state.players = [
        MultiplayerPlayer(id: "1", name: "You", isLocal: true, isAlive: false, finalScore: 156),
        MultiplayerPlayer(id: "2", name: "ProGamer99", isLocal: false, isAlive: false, finalScore: 203),
        MultiplayerPlayer(id: "3", name: "CasualPlayer", isLocal: false, isAlive: false, finalScore: 89)
    ]
    state.winner = state.players[1]  // ProGamer99 wins
    
    return ZStack {
        Color.black.ignoresSafeArea()
        
        MultiplayerGameOverView(
            multiplayerState: state,
            gameState: GameState(),
            accentColor: Color.cyan,
            onRestart: {},
            onMainMenu: {}
        )
        .padding()
    }
}

#Preview("Multiplayer Game Over - You Win") {
    let state = MultiplayerState()
    state.players = [
        MultiplayerPlayer(id: "1", name: "You", isLocal: true, isAlive: false, finalScore: 256),
        MultiplayerPlayer(id: "2", name: "Opponent", isLocal: false, isAlive: false, finalScore: 120)
    ]
    state.winner = state.players[0]  // You win
    
    return ZStack {
        Color.black.ignoresSafeArea()
        
        MultiplayerGameOverView(
            multiplayerState: state,
            gameState: GameState(),
            accentColor: Color.cyan,
            onRestart: {},
            onMainMenu: {}
        )
        .padding()
    }
}
