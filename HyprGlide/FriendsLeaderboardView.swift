//
//  FriendsLeaderboardView.swift
//  HyprGlide
//
//  SwiftUI sheet displaying the friends-only Game Center leaderboard.
//  Handles loading, error, and empty states gracefully.
//

import SwiftUI
import GameKit

// MARK: - Friends Leaderboard View

/// Sheet view showing friends' high scores from Game Center.
struct FriendsLeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var gameCenterManager = GameCenterManager.shared
    
    /// Accent color from the app's theme.
    let accentColor: Color
    
    /// Loading state for the leaderboard data.
    @State private var loadingState: LoadingState = .idle
    
    /// Fetched leaderboard entries.
    @State private var entries: [GameCenterManager.LeaderboardEntry] = []
    
    /// Error message if loading fails.
    @State private var errorMessage: String?
    
    /// Currently selected leaderboard scope (friends/global).
    @State private var currentScope: LeaderboardScope = .friends
    
    /// Gold color for 1st place.
    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0)
    
    /// Silver for 2nd place.
    private let silverColor = Color(red: 0.75, green: 0.75, blue: 0.78)
    
    /// Bronze for 3rd place.
    private let bronzeColor = Color(red: 0.8, green: 0.5, blue: 0.2)
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Content based on state
                    contentView
                }
            }
            .navigationTitle("High Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(accentColor)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        loadLeaderboard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(accentColor)
                    }
                    .disabled(loadingState == .loading)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            authenticateAndLoad()
        }
        .onChange(of: currentScope) { _ in
            guard gameCenterManager.isAuthenticated else { return }
            loadLeaderboard()
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        switch loadingState {
        case .idle, .loading:
            loadingView
            
        case .loaded:
            if entries.isEmpty {
                emptyStateView
            } else {
                leaderboardList
            }
            
        case .error:
            errorView
            
        case .notAuthenticated:
            notAuthenticatedView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(accentColor)
            
            Text("Loading \(currentScope.displayName.lowercased()) scores...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundStyle(accentColor.opacity(0.5))
            
            Text(emptyStateTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(emptyStateMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if currentScope == .friends {
                Button("Show Global Scores") {
                    currentScope = .global
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(accentColor)
                .clipShape(Capsule())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange.opacity(0.7))
            
            Text("Unable to Load Scores")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("Try Again") {
                loadLeaderboard()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notAuthenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 50))
                .foregroundStyle(accentColor.opacity(0.5))
            
            Text("Sign in to Game Center")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Connect to Game Center to see high scores and compete on the leaderboard.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Sign In") {
                GameCenterManager.shared.authenticateIfNeeded()
                // Wait a moment and retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if gameCenterManager.isAuthenticated {
                        loadLeaderboard()
                    }
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(accentColor)
            .clipShape(Capsule())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var leaderboardList: some View {
        VStack(spacing: 12) {
            scopePicker
            
            Text("Only Game Center friends who mutually share activity will appear here.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries) { entry in
                        LeaderboardEntryRow(
                            entry: entry,
                            medalColor: medalColor(for: entry.rank),
                            accentColor: accentColor,
                            isLocalPlayer: entry.id == GKLocalPlayer.local.gamePlayerID
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helpers
    
    private func medalColor(for rank: Int) -> Color? {
        switch rank {
        case 1: return goldColor
        case 2: return silverColor
        case 3: return bronzeColor
        default: return nil
        }
    }
    
    private func authenticateAndLoad() {
        if !gameCenterManager.isAuthenticated {
            loadingState = .notAuthenticated
            return
        }
        
        loadLeaderboard()
    }
    
    private func loadLeaderboard() {
        guard gameCenterManager.isAuthenticated else {
            loadingState = .notAuthenticated
            return
        }
        
        loadingState = .loading
        errorMessage = nil
        let scopeAtRequest = currentScope
        
        gameCenterManager.loadLeaderboardTop(
            playerScope: scopeAtRequest.playerScope,
            timeScope: scopeAtRequest.timeScope,
            limit: 25
        ) { result in
            guard scopeAtRequest == currentScope else { return }
            switch result {
            case .success(let fetchedEntries):
                entries = fetchedEntries
                loadingState = .loaded
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                loadingState = .error
            }
        }
    }
    
    private var emptyStateTitle: String {
        currentScope == .friends ? "No Friends Found" : "No Scores Yet"
    }
    
    private var emptyStateMessage: String {
        if currentScope == .friends {
            return "Add friends on Game Center to see their scores here."
        }
        return "Be the first to post a score and climb the global leaderboard."
    }
    
    private var scopePicker: some View {
        Picker("Scope", selection: $currentScope) {
            ForEach(LeaderboardScope.allCases) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

// MARK: - Loading State

private extension FriendsLeaderboardView {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error
        case notAuthenticated
    }
    
    enum LeaderboardScope: String, CaseIterable, Identifiable {
        case friends
        case global
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .friends: return "Friends"
            case .global: return "Global"
            }
        }
        
        var playerScope: GKLeaderboard.PlayerScope {
            switch self {
            case .friends: return .friends
            case .global: return .global
            }
        }
        
        var timeScope: GKLeaderboard.TimeScope {
            switch self {
            case .friends: return .allTime
            case .global: return .allTime
            }
        }
    }
}

// MARK: - Leaderboard Entry Row

/// Individual row showing a friend's rank, name, and score.
struct LeaderboardEntryRow: View {
    let entry: GameCenterManager.LeaderboardEntry
    let medalColor: Color?
    let accentColor: Color
    let isLocalPlayer: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            // Rank badge
            ZStack {
                if let medal = medalColor {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [medal.opacity(0.4), medal.opacity(0.15)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 18
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(medal.opacity(0.6), lineWidth: 1.5)
                        )
                    
                    Text("\(entry.rank)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(medal)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    Text("\(entry.rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 36, height: 36)
            
            // Player info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 16, weight: isLocalPlayer ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isLocalPlayer ? accentColor : .white)
                        .lineLimit(1)
                    
                    if isLocalPlayer {
                        Text("You")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(accentColor.opacity(0.15))
                            )
                    }
                }
            }
            
            Spacer()
            
            // Score
            Text("\(entry.score)")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(medalColor ?? .white.opacity(0.9))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isLocalPlayer ? accentColor.opacity(0.1) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isLocalPlayer ? accentColor.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Preview

#Preview("Friends Leaderboard - Loaded") {
    FriendsLeaderboardView(accentColor: .cyan)
}

#Preview("Entry Row - Gold") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 8) {
            LeaderboardEntryRow(
                entry: GameCenterManager.LeaderboardEntry(
                    id: "1",
                    displayName: "ProGamer99",
                    score: 1250,
                    rank: 1
                ),
                medalColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                accentColor: .cyan,
                isLocalPlayer: false
            )
            
            LeaderboardEntryRow(
                entry: GameCenterManager.LeaderboardEntry(
                    id: "2",
                    displayName: "You",
                    score: 980,
                    rank: 2
                ),
                medalColor: Color(red: 0.75, green: 0.75, blue: 0.78),
                accentColor: .cyan,
                isLocalPlayer: true
            )
            
            LeaderboardEntryRow(
                entry: GameCenterManager.LeaderboardEntry(
                    id: "3",
                    displayName: "CasualPlayer",
                    score: 650,
                    rank: 3
                ),
                medalColor: Color(red: 0.8, green: 0.5, blue: 0.2),
                accentColor: .cyan,
                isLocalPlayer: false
            )
        }
        .padding()
    }
}
