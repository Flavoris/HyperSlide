//
//  GameCenterManager.swift
//  HyprGlide
//
//  Singleton manager for Game Center authentication, score submission,
//  and friends-only leaderboard access. Does NOT handle matchmaking—
//  that responsibility belongs to MultiplayerMatchManager (Phase 4).
//

import Foundation
import GameKit
import Combine
import UIKit

// MARK: - GameCenterManager

/// Central hub for Game Center integration.
///
/// **When to call authentication:**
/// - Call `authenticateIfNeeded(presentingFrom:)` once early in the app lifecycle,
///   typically in your `@main` App struct's `.onAppear` or in the root view controller
///   after the window is available. iOS may present its own sign-in UI, so the host
///   app should be prepared to hand control to GameKit briefly.
///
/// **Thread safety:**
/// - All `@Published` property updates dispatch to the main actor.
/// - Callbacks from GameKit may arrive on arbitrary queues.
final class GameCenterManager: ObservableObject {
    
    // MARK: - Shared Instance
    
    /// Singleton accessor for app-wide use.
    static let shared = GameCenterManager()
    
    // MARK: - Published State
    
    /// `true` once the local player has successfully authenticated with Game Center.
    @Published private(set) var isAuthenticated: Bool = false
    
    /// Display name of the authenticated player, or `nil` if not yet authenticated.
    @Published private(set) var localPlayerName: String?
    
    // MARK: - Constants
    
    /// Info.plist key used to optionally override the Game Center leaderboard ID.
    ///
    /// If missing/empty, `fallbackLeaderboardID` is used.
    private static let leaderboardIDInfoPlistKey = "HyprGlideLeaderboardID"
    
    /// Fallback leaderboard identifier (used when no override is provided).
    private let fallbackLeaderboardID = "hyprglide.friends.highscore"
    
    // MARK: - Private State
    
    /// Tracks whether authentication is currently in progress to avoid duplicate calls.
    private var isAuthenticating = false
    
    /// Cache the resolved leaderboard ID once we successfully load one.
    private var resolvedLeaderboardID: String?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Authentication
    
    /// Triggers Game Center authentication if not already authenticated.
    ///
    /// - Parameter presentingViewController: Optional view controller used to present
    ///   the Game Center sign-in UI when required. Pass `nil` if you're calling from
    ///   a context without a readily available VC—GameKit will attempt to find one.
    ///
    /// **Usage:**
    /// ```swift
    /// // In your App's root view (SwiftUI)
    /// .onAppear {
    ///     GameCenterManager.shared.authenticateIfNeeded(presentingFrom: nil)
    /// }
    /// ```
    ///
    /// **Behavior:**
    /// - If the player is already authenticated, this updates published state and returns.
    /// - If GameKit provides a view controller, it is presented for the user to sign in.
    /// - If authentication fails or is cancelled, `isAuthenticated` remains `false`.
    func authenticateIfNeeded(presentingFrom presenter: UIViewController? = nil) {
        // Prevent overlapping authentication attempts.
        guard !isAuthenticating else { return }
        
        let localPlayer = GKLocalPlayer.local
        
        // Already authenticated—sync state and exit.
        if localPlayer.isAuthenticated {
            updatePublishedState(from: localPlayer)
            return
        }
        
        isAuthenticating = true
        
        localPlayer.authenticateHandler = { [weak self] viewController, error in
            defer { self?.isAuthenticating = false }
            
            if let vc = viewController {
                // GameKit requires presenting its sign-in UI.
                self?.presentSignInViewController(vc, from: presenter)
                return
            }
            
            if let error = error {
                // Authentication failed or was cancelled by the user.
                self?.handleAuthenticationError(error)
                return
            }
            
            // Success—player is now authenticated.
            self?.updatePublishedState(from: localPlayer)
        }
    }
    
    // MARK: - Score Submission
    
    /// Submits the given score to the friends leaderboard if Game Center is available.
    ///
    /// - Parameter score: The player's score as a `Double`. It will be rounded to `Int`.
    ///
    /// **Behavior:**
    /// - Silently returns without error if the player is not authenticated.
    /// - Uses the modern `GKLeaderboard.submitScore` API (iOS 14+).
    func submitBestScoreIfGameCenterAvailable(score: Double) {
        guard isAuthenticated else {
            // Not authenticated—fail silently as per spec.
            return
        }
        
        let intScore = Int(score.rounded())
        
        let configuredID = configuredLeaderboardID
        
        loadLeaderboard { result in
            let leaderboardIDs: [String]
            switch result {
            case .success(let leaderboard):
                leaderboardIDs = [leaderboard.baseLeaderboardID]
            case .failure(let error):
                // Best-effort: if we can't resolve a leaderboard, try the configured ID anyway.
                print("[GameCenterManager] Leaderboard resolution failed: \(error.localizedDescription)")
                leaderboardIDs = [configuredID]
            }
            
            // iOS 14+ API for score submission.
            GKLeaderboard.submitScore(
                intScore,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: leaderboardIDs
            ) { error in
                if let error = error {
                    // Log but don't surface to user—scores are best-effort.
                    print("[GameCenterManager] Score submission failed: \(error.localizedDescription)")
                } else {
                    print("[GameCenterManager] Score \(intScore) submitted successfully.")
                }
            }
        }
    }
    
    // MARK: - Friends Leaderboard
    
    /// Represents a single leaderboard entry for display purposes.
    struct LeaderboardEntry: Identifiable {
        let id: String          // Player's gamePlayerID
        let displayName: String
        let score: Int
        let rank: Int
    }
    
    /// Loads the top scores from the friends-only leaderboard.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of entries to return (capped at 100 by GameKit).
    ///   - completion: Closure receiving either an array of `LeaderboardEntry` or an `Error`.
    ///
    /// **API Notes:**
    /// - iOS 14+ uses `GKLeaderboard.loadLeaderboards(IDs:)` combined with `loadEntries`.
    /// - The `.friends` player scope restricts results to the authenticated player's friends.
    /// - If the player has no friends or none have scores, the array will be empty.
    ///
    /// **Version Considerations:**
    /// - Prior to iOS 14, you would use the deprecated `GKLeaderboard(identifier:)` initializer
    ///   with `playerScope = .friends`. This implementation targets iOS 14+.
    func loadFriendsLeaderboardTop(
        limit: Int = 25,
        completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void
    ) {
        loadLeaderboardTop(
            playerScope: .friends,
            timeScope: .allTime,
            limit: limit,
            completion: completion
        )
    }
    
    /// Loads leaderboard entries for the specified player scope (friends/global).
    /// GameKit automatically limits the friends scope to bi-directional friends who opted-in,
    /// so no additional filtering is needed on our side.
    func loadLeaderboardTop(
        playerScope: GKLeaderboard.PlayerScope,
        timeScope: GKLeaderboard.TimeScope = .allTime,
        limit: Int = 25,
        completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void
    ) {
        guard isAuthenticated else {
            completion(.failure(GameCenterError.notAuthenticated))
            return
        }
        
        loadLeaderboard { [weak self] result in
            switch result {
            case .success(let leaderboard):
                self?.fetchEntries(
                    from: leaderboard,
                    playerScope: playerScope,
                    timeScope: timeScope,
                    limit: limit,
                    completion: completion
                )
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Returns the leaderboard ID configured for this build.
    /// If `HyprGlideLeaderboardID` is not present in Info.plist, falls back to `fallbackLeaderboardID`.
    private var configuredLeaderboardID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: Self.leaderboardIDInfoPlistKey) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : fallbackLeaderboardID
    }
    
    /// Loads a `GKLeaderboard` for use by score submission and leaderboard UI.
    ///
    /// We first try the configured/resolved leaderboard ID. If it's missing/mismatched,
    /// we fall back to loading all leaderboards for the game and selecting a reasonable default.
    private func loadLeaderboard(completion: @escaping (Result<GKLeaderboard, Error>) -> Void) {
        let configuredID = configuredLeaderboardID
        let preferredID = resolvedLeaderboardID ?? configuredID
        
        GKLeaderboard.loadLeaderboards(IDs: [preferredID]) { [weak self] leaderboards, error in
            if let leaderboard = leaderboards?.first {
                self?.resolvedLeaderboardID = leaderboard.baseLeaderboardID
                DispatchQueue.main.async {
                    completion(.success(leaderboard))
                }
                return
            }
            
            // Fallback: load all leaderboards for the game and pick the configured one (or the first).
            GKLeaderboard.loadLeaderboards(IDs: nil) { [weak self] allLeaderboards, fallbackError in
                let selected = allLeaderboards?.first(where: { $0.baseLeaderboardID == configuredID }) ?? allLeaderboards?.first
                
                if let leaderboard = selected {
                    self?.resolvedLeaderboardID = leaderboard.baseLeaderboardID
                    DispatchQueue.main.async {
                        completion(.success(leaderboard))
                    }
                    return
                }
                
                let finalError = error ?? fallbackError ?? GameCenterError.leaderboardNotFound
                DispatchQueue.main.async {
                    completion(.failure(finalError))
                }
            }
        }
    }
    
    /// Presents the Game Center sign-in view controller.
    private func presentSignInViewController(_ vc: UIViewController, from presenter: UIViewController?) {
        DispatchQueue.main.async {
            // Attempt to find a presenter if none was provided.
            let hostVC = presenter ?? Self.topViewController()
            hostVC?.present(vc, animated: true)
        }
    }
    
    /// Updates published state on the main thread after successful authentication.
    private func updatePublishedState(from player: GKLocalPlayer) {
        DispatchQueue.main.async { [weak self] in
            self?.isAuthenticated = player.isAuthenticated
            self?.localPlayerName = player.isAuthenticated ? player.displayName : nil
            
            if player.isAuthenticated {
                print("[GameCenterManager] Authenticated as \(player.displayName)")
            }
        }
    }
    
    /// Handles authentication errors by resetting published state.
    private func handleAuthenticationError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isAuthenticated = false
            self?.localPlayerName = nil
            self?.resolvedLeaderboardID = nil
            print("[GameCenterManager] Authentication failed: \(error.localizedDescription)")
        }
    }
    
    /// Fetches leaderboard entries from the given leaderboard.
    private func fetchEntries(
        from leaderboard: GKLeaderboard,
        playerScope: GKLeaderboard.PlayerScope,
        timeScope: GKLeaderboard.TimeScope,
        limit: Int,
        completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void
    ) {
        // Use player scope to restrict results to friends/global.
        // NSRange starts at 1 (1-indexed ranks in GameKit).
        let range = NSRange(location: 1, length: min(limit, 100))
        
        leaderboard.loadEntries(for: playerScope, timeScope: timeScope, range: range) { localEntry, entries, count, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Map GKLeaderboard.Entry to our LeaderboardEntry struct.
                var results: [LeaderboardEntry] = []
                
                if let entries = entries {
                    results = entries.map { entry in
                        LeaderboardEntry(
                            id: entry.player.gamePlayerID,
                            displayName: entry.player.displayName,
                            score: entry.score,
                            rank: entry.rank
                        )
                    }
                }
                
                // Include local player's entry if not already present.
                if let localEntry = localEntry,
                   !results.contains(where: { $0.id == localEntry.player.gamePlayerID }) {
                    results.append(LeaderboardEntry(
                        id: localEntry.player.gamePlayerID,
                        displayName: localEntry.player.displayName,
                        score: localEntry.score,
                        rank: localEntry.rank
                    ))
                }
                
                // Sort by rank ascending.
                results.sort { $0.rank < $1.rank }
                
                completion(.success(results))
            }
        }
    }
    
    /// Attempts to find the topmost presented view controller for presenting Game Center UI.
    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }
        
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - GameCenterError

/// Errors specific to GameCenterManager operations.
enum GameCenterError: LocalizedError {
    case notAuthenticated
    case leaderboardNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Player is not authenticated with Game Center."
        case .leaderboardNotFound:
            return "The requested leaderboard could not be found."
        }
    }
}

#if !compiler(>=7.0)
extension GKLeaderboard.PlayerScope {
    /// Temporary shim so we can call `.friends` while GameKit still exposes `.friendsOnly`.
    /// Remove once the native Swift API surfaces the `friends` case directly.
    static var friends: GKLeaderboard.PlayerScope { .friendsOnly }
}
#endif
