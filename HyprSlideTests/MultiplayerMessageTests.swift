//
//  MultiplayerMessageTests.swift
//  HyprGlideTests
//
//  Tests for multiplayer message encoding and decoding.
//  Verifies that all message types round-trip correctly through
//  JSON serialization without data loss or crashes.
//

import XCTest
@testable import HyprGlide

final class MultiplayerMessageTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Encodes and decodes a payload, returning the decoded result.
    /// Fails the test if encoding or decoding throws.
    /// This version is for Equatable types where we want to verify equality.
    private func roundTrip<T: Codable & Equatable>(_ payload: T, file: StaticString = #file, line: UInt = #line) -> T? {
        do {
            let encoded = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            return decoded
        } catch {
            XCTFail("Round-trip failed: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }
    
    /// Encodes and decodes a Codable payload (without Equatable constraint).
    /// Returns the decoded result for manual property verification.
    private func roundTripCodable<T: Codable>(_ payload: T, file: StaticString = #file, line: UInt = #line) -> T? {
        do {
            let encoded = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            return decoded
        } catch {
            XCTFail("Round-trip failed: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }
    
    /// Wraps a payload in a MultiplayerMessage and round-trips the entire message.
    private func roundTripMessage<T: Codable>(
        type: MultiplayerMessageType,
        payload: T,
        file: StaticString = #file,
        line: UInt = #line
    ) -> (message: MultiplayerMessage, payloadData: Data)? {
        do {
            // Encode the payload.
            let payloadData = try JSONEncoder().encode(payload)
            
            // Create the message.
            let message = MultiplayerMessage(
                type: type,
                payload: payloadData,
                senderId: "test-player-id"
            )
            
            // Encode and decode the message.
            let encodedMessage = try JSONEncoder().encode(message)
            let decodedMessage = try JSONDecoder().decode(MultiplayerMessage.self, from: encodedMessage)
            
            return (decodedMessage, decodedMessage.payload)
        } catch {
            XCTFail("Message round-trip failed: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }
    
    // MARK: - Message Type Tests
    
    /// Verifies MultiplayerMessageType round-trips correctly.
    func testMessageTypeRoundTrip() {
        let allTypes: [MultiplayerMessageType] = [
            .matchSetup,
            .playerStateUpdate,
            .obstacleSpawn,
            .powerUpSpawn,
            .playerDied,
            .matchEnd,
            .powerUpCollected,
            .slowMotionActivated
        ]
        
        for messageType in allTypes {
            guard let decoded = roundTrip(messageType) else { continue }
            XCTAssertEqual(decoded, messageType, "Message type \(messageType) should round-trip correctly")
        }
    }
    
    // MARK: - MatchSetupPayload Tests
    
    /// Verifies MatchSetupPayload round-trips correctly.
    func testMatchSetupPayloadRoundTrip() {
        let players = [
            MultiplayerPlayerSummary(id: "player-1", displayName: "Alice", isLocal: true),
            MultiplayerPlayerSummary(id: "player-2", displayName: "Bob", isLocal: false),
            MultiplayerPlayerSummary(id: "player-3", displayName: "Charlie", isLocal: false)
        ]
        
        let payload = MatchSetupPayload(
            hostId: "player-1",
            arenaSeed: 12345678901234,
            matchStartTime: 1700000000.0,
            players: players,
            matchId: "match-uuid-12345"
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.hostId, payload.hostId)
        XCTAssertEqual(decoded.arenaSeed, payload.arenaSeed)
        XCTAssertEqual(decoded.matchStartTime, payload.matchStartTime, accuracy: 0.001)
        XCTAssertEqual(decoded.matchId, payload.matchId)
        XCTAssertEqual(decoded.players.count, 3)
        XCTAssertEqual(decoded.players[0].displayName, "Alice")
        XCTAssertTrue(decoded.players[0].isLocal)
    }
    
    /// Verifies MatchSetupPayload works in a full message wrapper.
    func testMatchSetupPayloadInMessage() {
        let payload = MatchSetupPayload(
            hostId: "host-id",
            arenaSeed: 999,
            matchStartTime: 1000.0,
            players: [],
            matchId: "test-match"
        )
        
        guard let result = roundTripMessage(type: .matchSetup, payload: payload) else { return }
        
        XCTAssertEqual(result.message.type, .matchSetup)
        XCTAssertEqual(result.message.senderId, "test-player-id")
        XCTAssertGreaterThan(result.message.timestamp, 0)
        
        // Verify we can decode the payload from the message.
        let decodedPayload = try? JSONDecoder().decode(MatchSetupPayload.self, from: result.payloadData)
        XCTAssertNotNil(decodedPayload)
        XCTAssertEqual(decodedPayload?.hostId, "host-id")
    }
    
    // MARK: - PlayerStateUpdatePayload Tests
    
    /// Verifies PlayerStateUpdatePayload round-trips correctly.
    func testPlayerStateUpdatePayloadRoundTrip() {
        let payload = PlayerStateUpdatePayload(
            playerId: "player-abc",
            positionX: 150.5,
            velocityX: -25.3,
            score: 1234.5,
            isAlive: true,
            timestamp: 45.678
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.playerId, payload.playerId)
        XCTAssertEqual(decoded.positionX, payload.positionX, accuracy: 0.001)
        XCTAssertEqual(decoded.velocityX, payload.velocityX, accuracy: 0.001)
        XCTAssertEqual(decoded.score, payload.score, accuracy: 0.001)
        XCTAssertEqual(decoded.isAlive, payload.isAlive)
        XCTAssertEqual(decoded.timestamp, payload.timestamp, accuracy: 0.001)
    }
    
    /// Verifies PlayerStateUpdatePayload with extreme values doesn't crash.
    func testPlayerStateUpdatePayloadExtremeValues() {
        let payload = PlayerStateUpdatePayload(
            playerId: String(repeating: "x", count: 100),  // Long ID
            positionX: CGFloat.greatestFiniteMagnitude,
            velocityX: -CGFloat.greatestFiniteMagnitude,
            score: Double.greatestFiniteMagnitude,
            isAlive: false,
            timestamp: 0.0
        )
        
        // Just verify it doesn't crash.
        let decoded = roundTripCodable(payload)
        XCTAssertNotNil(decoded, "Extreme values should not crash encoding")
    }
    
    // MARK: - ObstacleSpawnPayload Tests
    
    /// Verifies ObstacleSpawnPayload round-trips correctly.
    func testObstacleSpawnPayloadRoundTrip() {
        let event = ObstacleSpawnEvent(
            timeOffset: 10.5,
            width: 120,
            speedY: 450,
            normalizedX: 0.75,
            isEdgePunish: true,
            edgeSide: .right
        )
        
        let payload = ObstacleSpawnPayload(event: event, spawnIndex: 42)
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.spawnIndex, 42)
        XCTAssertEqual(decoded.event.timeOffset, 10.5, accuracy: 0.001)
        XCTAssertEqual(decoded.event.width, 120, accuracy: 0.001)
        XCTAssertEqual(decoded.event.speedY, 450, accuracy: 0.001)
        XCTAssertEqual(decoded.event.normalizedX, 0.75, accuracy: 0.001)
        XCTAssertTrue(decoded.event.isEdgePunish)
        XCTAssertEqual(decoded.event.edgeSide, ObstacleSpawnEvent.EdgeSideEvent.right)
    }
    
    /// Verifies all ObstacleSpawnEvent.EdgeSideEvent values round-trip.
    func testObstacleEdgeSideRoundTrip() {
        let edgeSides: [ObstacleSpawnEvent.EdgeSideEvent] = [.none, .left, .right]
        
        for edgeSide in edgeSides {
            guard let decoded = roundTrip(edgeSide) else { continue }
            XCTAssertEqual(decoded, edgeSide, "EdgeSide \(edgeSide) should round-trip correctly")
        }
    }
    
    // MARK: - PowerUpSpawnPayload Tests
    
    /// Verifies PowerUpSpawnPayload round-trips correctly.
    func testPowerUpSpawnPayloadRoundTrip() {
        let event = PowerUpSpawnEvent(
            timeOffset: 25.0,
            type: .invincibility,
            normalizedX: 0.33,
            speedY: 200,
            radius: 28
        )
        
        let payload = PowerUpSpawnPayload(
            event: event,
            spawnIndex: 7,
            powerUpId: "powerup_7_1700000000"
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.spawnIndex, 7)
        XCTAssertEqual(decoded.powerUpId, "powerup_7_1700000000")
        XCTAssertEqual(decoded.event.type, PowerUpSpawnEvent.PowerUpTypeEvent.invincibility)
        XCTAssertEqual(decoded.event.normalizedX, 0.33, accuracy: 0.001)
    }
    
    /// Verifies all PowerUpSpawnEvent.PowerUpTypeEvent values round-trip.
    func testPowerUpTypeRoundTrip() {
        let types: [PowerUpSpawnEvent.PowerUpTypeEvent] = [.slowMotion, .invincibility, .attackMode]
        
        for powerUpType in types {
            guard let decoded = roundTrip(powerUpType) else { continue }
            XCTAssertEqual(decoded, powerUpType, "PowerUpType \(powerUpType) should round-trip correctly")
        }
    }
    
    // MARK: - PlayerDiedPayload Tests
    
    /// Verifies PlayerDiedPayload round-trips correctly.
    func testPlayerDiedPayloadRoundTrip() {
        let payload = PlayerDiedPayload(
            playerId: "eliminated-player",
            finalScore: 9876.5,
            eliminationTime: 63.25
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.playerId, "eliminated-player")
        XCTAssertEqual(decoded.finalScore, 9876.5, accuracy: 0.001)
        XCTAssertEqual(decoded.eliminationTime, 63.25, accuracy: 0.001)
    }
    
    // MARK: - MatchEndPayload Tests
    
    /// Verifies MatchEndPayload round-trips correctly.
    func testMatchEndPayloadRoundTrip() {
        let rankings = [
            MatchEndPayload.PlayerRanking(playerId: "p1", displayName: "Winner", finalScore: 5000, rank: 1),
            MatchEndPayload.PlayerRanking(playerId: "p2", displayName: "Second", finalScore: 3000, rank: 2),
            MatchEndPayload.PlayerRanking(playerId: "p3", displayName: "Third", finalScore: 1000, rank: 3)
        ]
        
        let payload = MatchEndPayload(rankedPlayers: rankings, winnerId: "p1")
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.winnerId, "p1")
        XCTAssertEqual(decoded.rankedPlayers.count, 3)
        XCTAssertEqual(decoded.rankedPlayers[0].displayName, "Winner")
        XCTAssertEqual(decoded.rankedPlayers[0].finalScore, 5000, accuracy: 0.001)
        XCTAssertEqual(decoded.rankedPlayers[1].rank, 2)
    }
    
    /// Verifies MatchEndPayload works in a full message wrapper.
    func testMatchEndPayloadInMessage() {
        let payload = MatchEndPayload(
            rankedPlayers: [],
            winnerId: "winner-id"
        )
        
        guard let result = roundTripMessage(type: .matchEnd, payload: payload) else { return }
        
        XCTAssertEqual(result.message.type, .matchEnd)
        
        let decodedPayload = try? JSONDecoder().decode(MatchEndPayload.self, from: result.payloadData)
        XCTAssertNotNil(decodedPayload)
        XCTAssertEqual(decodedPayload?.winnerId, "winner-id")
    }
    
    // MARK: - PowerUpCollectedPayload Tests
    
    /// Verifies PowerUpCollectedPayload round-trips correctly.
    func testPowerUpCollectedPayloadRoundTrip() {
        let payload = PowerUpCollectedPayload(
            powerUpId: "powerup_15_1700000500",
            collectorId: "fast-collector",
            collectionTime: 45.123
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.powerUpId, "powerup_15_1700000500")
        XCTAssertEqual(decoded.collectorId, "fast-collector")
        XCTAssertEqual(decoded.collectionTime, 45.123, accuracy: 0.001)
    }
    
    // MARK: - SlowMotionActivatedPayload Tests
    
    /// Verifies SlowMotionActivatedPayload round-trips correctly.
    func testSlowMotionActivatedPayloadRoundTrip() {
        let payload = SlowMotionActivatedPayload(
            collectorId: "slow-mo-collector",
            duration: 5.0,
            stackedDuration: 7.5,
            activationTime: 30.0
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.collectorId, "slow-mo-collector")
        XCTAssertEqual(decoded.duration, 5.0, accuracy: 0.001)
        XCTAssertEqual(decoded.stackedDuration, 7.5, accuracy: 0.001)
        XCTAssertEqual(decoded.activationTime, 30.0, accuracy: 0.001)
    }
    
    // MARK: - Full Message Round-Trip Tests
    
    /// Verifies the complete MultiplayerMessage wrapper round-trips correctly.
    func testMultiplayerMessageWrapperRoundTrip() {
        let innerPayload = PlayerDiedPayload(
            playerId: "test",
            finalScore: 100,
            eliminationTime: 10
        )
        
        do {
            let payloadData = try JSONEncoder().encode(innerPayload)
            let originalMessage = MultiplayerMessage(
                type: .playerDied,
                payload: payloadData,
                senderId: "sender-123"
            )
            
            let encoded = try JSONEncoder().encode(originalMessage)
            let decoded = try JSONDecoder().decode(MultiplayerMessage.self, from: encoded)
            
            XCTAssertEqual(decoded.type, .playerDied)
            XCTAssertEqual(decoded.senderId, "sender-123")
            XCTAssertEqual(decoded.payload, payloadData, "Payload data should be preserved exactly")
            XCTAssertGreaterThan(decoded.timestamp, 0, "Timestamp should be set")
            
        } catch {
            XCTFail("Full message round-trip failed: \(error)")
        }
    }
    
    // MARK: - MultiplayerPlayerSummary Tests
    
    /// Verifies MultiplayerPlayerSummary round-trips correctly.
    func testMultiplayerPlayerSummaryRoundTrip() {
        let summary = MultiplayerPlayerSummary(
            id: "player-summary-id",
            displayName: "Test Player Name",
            isLocal: true
        )
        
        guard let decoded = roundTrip(summary) else { return }
        
        XCTAssertEqual(decoded.id, "player-summary-id")
        XCTAssertEqual(decoded.displayName, "Test Player Name")
        XCTAssertTrue(decoded.isLocal)
    }
    
    // MARK: - ArenaEventStream Tests
    
    /// Verifies ArenaEventStream round-trips correctly.
    func testArenaEventStreamRoundTrip() {
        var stream = ArenaEventStream(seed: 12345)
        
        stream.appendObstacleEvent(ObstacleSpawnEvent(
            timeOffset: 1.0,
            width: 100,
            speedY: 300,
            normalizedX: 0.5,
            isEdgePunish: false,
            edgeSide: .none
        ))
        
        stream.appendPowerUpEvent(PowerUpSpawnEvent(
            timeOffset: 5.0,
            type: .attackMode,
            normalizedX: 0.3,
            speedY: 200,
            radius: 25
        ))
        
        guard let decoded = roundTripCodable(stream) else { return }
        
        XCTAssertEqual(decoded.seed, 12345)
        XCTAssertEqual(decoded.obstacleEvents.count, 1)
        XCTAssertEqual(decoded.powerUpEvents.count, 1)
        XCTAssertEqual(decoded.obstacleEvents[0].width, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.powerUpEvents[0].type, PowerUpSpawnEvent.PowerUpTypeEvent.attackMode)
    }
    
    // MARK: - Error Handling Tests
    
    /// Verifies that malformed JSON doesn't crash the decoder.
    func testMalformedJSONDoesNotCrash() {
        let malformedData = Data("{ invalid json }".utf8)
        
        // Attempt to decode each payload type with malformed data.
        XCTAssertNil(try? JSONDecoder().decode(MatchSetupPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(PlayerStateUpdatePayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(ObstacleSpawnPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(PowerUpSpawnPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(PlayerDiedPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(MatchEndPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(PowerUpCollectedPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(SlowMotionActivatedPayload.self, from: malformedData))
        XCTAssertNil(try? JSONDecoder().decode(MultiplayerMessage.self, from: malformedData))
    }
    
    /// Verifies that empty JSON object doesn't crash (should fail gracefully).
    func testEmptyJSONObjectDoesNotCrash() {
        let emptyObject = Data("{}".utf8)
        
        // These should fail to decode but not crash.
        XCTAssertNil(try? JSONDecoder().decode(MatchSetupPayload.self, from: emptyObject))
        XCTAssertNil(try? JSONDecoder().decode(MultiplayerMessage.self, from: emptyObject))
    }
    
    // MARK: - Unicode and Special Characters Tests
    
    /// Verifies payloads with Unicode characters round-trip correctly.
    func testUnicodeCharactersInPayloads() {
        let players = [
            MultiplayerPlayerSummary(id: "player-1", displayName: "日本語名前", isLocal: true),
            MultiplayerPlayerSummary(id: "player-2", displayName: "Émile 🎮", isLocal: false),
            MultiplayerPlayerSummary(id: "player-3", displayName: "مرحبا", isLocal: false)
        ]
        
        let payload = MatchSetupPayload(
            hostId: "player-1",
            arenaSeed: 42,
            matchStartTime: 1000.0,
            players: players,
            matchId: "match-🎯"
        )
        
        guard let decoded = roundTripCodable(payload) else { return }
        
        XCTAssertEqual(decoded.players[0].displayName, "日本語名前")
        XCTAssertEqual(decoded.players[1].displayName, "Émile 🎮")
        XCTAssertEqual(decoded.players[2].displayName, "مرحبا")
        XCTAssertEqual(decoded.matchId, "match-🎯")
    }
}

