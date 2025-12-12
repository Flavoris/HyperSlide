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
    
    /// Leaderboard identifier registered in App Store Connect.
    /// TODO: Align this string with your actual leaderboard ID in App Store Connect / Game Center config.
    private let leaderboardID = "hyprglide.friends.highscore"
    
    // MARK: - Private State
    
    /// Tracks whether authentication is currently in progress to avoid duplicate calls.
    private var isAuthenticating = false
    
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
        
        // iOS 14+ API for score submission.
        GKLeaderboard.submitScore(
            intScore,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { error in
            if let error = error {
                // Log but don't surface to user—scores are best-effort.
                print("[GameCenterManager] Score submission failed: \(error.localizedDescription)")
            } else {
                print("[GameCenterManager] Score \(intScore) submitted successfully.")
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
        
        // Load the leaderboard object first.
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { [weak self] leaderboards, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let leaderboard = leaderboards?.first else {
                DispatchQueue.main.async {
                    completion(.failure(GameCenterError.leaderboardNotFound))
                }
                return
            }
            
            self?.fetchEntries(
                from: leaderboard,
                playerScope: playerScope,
                timeScope: timeScope,
                limit: limit,
                completion: completion
            )
        }
    }
    
    // MARK: - Private Helpers
    
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
