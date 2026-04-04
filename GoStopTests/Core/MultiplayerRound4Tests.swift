import XCTest
@testable import GoStop

final class MultiplayerRound4Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
    }

    func testPlayTurn_ShouldTriggerOnLocalAction() {
        // Arrange
        let localId = "p1"
        gameManager.localPlayerId = localId
        
        let player = Player(name: "Me", money: 1000)
        player.id = UUID(uuidString: localId) ?? UUID()
        let card = Card(month: .jan, type: .bright, imageIndex: 0)
        player.hand = [card]
        gameManager.players = [player]
        gameManager.gameState = .playing
        
        var receivedAction: MultiplayerAction?
        gameManager.onLocalAction = { action in
            receivedAction = action
        }
        
        // Act
        gameManager.playTurn(card: card)
        
        // Assert
        XCTAssertNotNil(receivedAction)
        if case .playCard(let cardId) = receivedAction {
            XCTAssertEqual(cardId, card.id)
        } else {
            XCTFail("Expected .playCard action")
        }
    }
    
    func testPlayTurn_ShouldUpdateMovingCardsQueue() {
        // Arrange
        let localId = "p1"
        gameManager.localPlayerId = localId
        
        let player = Player(name: "Me", money: 1000)
        player.id = UUID(uuidString: localId) ?? UUID()
        let card = Card(month: .jan, type: .bright, imageIndex: 0)
        player.hand = [card]
        gameManager.players = [player]
        gameManager.gameState = .playing
        
        // Act
        gameManager.playTurn(card: card)
        
        // Assert
        // The card should be in currentMovingCards while animation is scheduled
        XCTAssertTrue(gameManager.currentMovingCards.contains(card.id), "Card should be in moving queue for optimistic UI")
    }

    func testAnyCodable_RoundTripsFoundationBooleanWithoutIntCoercion() throws {
        let foundationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"flag":true}"#.utf8)) as? [String: Any]
        )
        let foundationBool = try XCTUnwrap(foundationObject["flag"])

        let encoded = try JSONEncoder().encode(AnyCodable(foundationBool))
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

        XCTAssertEqual(decoded.value as? Bool, true)
        XCTAssertNil(decoded.value as? Int)
    }

    func testAnyCodable_RoundTripsFoundationIntegerWithoutBoolCoercion() throws {
        let foundationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"seatIndex":0,"imageIndex":1}"#.utf8)) as? [String: Any]
        )

        for key in ["seatIndex", "imageIndex"] {
            let foundationNumber = try XCTUnwrap(foundationObject[key])
            let encoded = try JSONEncoder().encode(AnyCodable(foundationNumber))
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            XCTAssertTrue(decoded.value is Int, "\(key) should remain an Int after AnyCodable round-trip")
            XCTAssertFalse(decoded.value is Bool, "\(key) must not be coerced into Bool during patch transport encoding")
        }
    }

    @MainActor
    func testAutomationDriverRegistration_IgnoresStaleClearFromOlderCoordinator() {
        let store = MultiplayerShellStore()
        let firstDriverID = UUID()
        let secondDriverID = UUID()
        var driverHits: [String] = []

        store.updateProductGameplayActionDriver({ _ in
            driverHits.append("first")
        }, sourceID: firstDriverID)
        store.updateProductGameplayActionDriver({ _ in
            driverHits.append("second")
        }, sourceID: secondDriverID)
        store.updateProductGameplayActionDriver(nil, sourceID: firstDriverID)

        store.performGameplayActionFromAutomation(.chat(emojiId: "🔥"))

        XCTAssertEqual(driverHits, ["second"])
    }

    func testIsAutomationBusy_IncludesCuePresentationState() {
        let cueCard = Card(month: .jan, type: .bright, imageIndex: 0)

        XCTAssertFalse(gameManager.isAutomationBusy)

        gameManager.currentMoveSourceZone = "hand"
        gameManager.currentMoveTargetZone = "table"
        gameManager.sourceCueCardIds = [cueCard.id]

        XCTAssertTrue(
            gameManager.isAutomationBusy,
            "Cue-only presentation state must keep authoritative multiplayer snapshots deferred until the shared single-play animation pipeline finishes."
        )

        gameManager.currentMoveSourceZone = nil
        gameManager.currentMoveTargetZone = nil
        gameManager.sourceCueCardIds = []

        XCTAssertFalse(gameManager.isAutomationBusy)
    }

    func testPerformAutomationAction_PlayCardUsesSharedPresentationFlow() {
        let localId = "p1"
        gameManager.localPlayerId = localId

        let player = Player(name: "Me", money: 1000)
        player.id = UUID(uuidString: localId) ?? UUID()
        let card = Card(month: .jan, type: .bright, imageIndex: 0)
        player.hand = [card]
        gameManager.players = [player]
        gameManager.gameState = .playing

        var receivedAction: MultiplayerAction?
        viewModel.onActionSent = { action in
            receivedAction = action
        }

        viewModel.performAutomationAction(.playCard(cardId: card.id))

        XCTAssertTrue(
            gameManager.isAutomationBusy,
            "Simulator bridge automation should drive the same shared single-play presentation flow as a real UI tap."
        )
        if case .playCard(let relayedCardId) = receivedAction {
            XCTAssertEqual(relayedCardId, card.id)
        } else {
            XCTFail("Expected .playCard action relay from automation driver")
        }
    }

    @MainActor
    func testApplyAuthoritativeSnapshot_DefersWhileSharedAnimationBusy() async throws {
        let localId = "player_me"
        let opponentId = "player_them"
        let initialSnapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )
        let opponentTurnSnapshot = MockMultiplayerPayloads.generateOpponentTurnSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )

        viewModel.applyAuthoritativeSnapshot(initialSnapshot)
        XCTAssertTrue(gameManager.isLocalTurn)

        gameManager.currentMovingCards = [Card(month: .jan, type: .bright, imageIndex: 0)]

        viewModel.applyAuthoritativeSnapshot(opponentTurnSnapshot)
        XCTAssertTrue(
            gameManager.isLocalTurn,
            "Authoritative in-place snapshots should wait until the shared single-play animation module is idle."
        )

        gameManager.currentMovingCards = []
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(gameManager.isLocalTurn)
    }

    @MainActor
    func testApplyAuthoritativeSnapshot_AppliesLatestDeferredSnapshotOnly() async throws {
        let localId = "player_me"
        let opponentId = "player_them"
        let initialSnapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )
        let opponentTurnSnapshot = MockMultiplayerPayloads.generateOpponentTurnSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )
        let matchEndedSnapshot = MockMultiplayerPayloads.generateMatchEndSnapshot(
            localPlayerId: localId,
            opponentId: opponentId,
            winnerId: opponentId
        )

        viewModel.applyAuthoritativeSnapshot(initialSnapshot)
        gameManager.currentMovingCards = [Card(month: .jan, type: .bright, imageIndex: 0)]

        viewModel.applyAuthoritativeSnapshot(opponentTurnSnapshot)
        viewModel.applyAuthoritativeSnapshot(matchEndedSnapshot)

        gameManager.currentMovingCards = []
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(gameManager.gameState, .ended)
        XCTAssertFalse(gameManager.isLocalTurn)
    }

    @MainActor
    func testApplyAuthoritativeSnapshot_DefersWhileCuePresentationBusy() async throws {
        let localId = "player_me"
        let opponentId = "player_them"
        let initialSnapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )
        let opponentTurnSnapshot = MockMultiplayerPayloads.generateOpponentTurnSnapshot(
            localPlayerId: localId,
            opponentId: opponentId
        )

        viewModel.applyAuthoritativeSnapshot(initialSnapshot)
        XCTAssertTrue(gameManager.isLocalTurn)

        let cueCard = Card(month: .jan, type: .bright, imageIndex: 0)
        gameManager.currentMoveSourceZone = "hand"
        gameManager.currentMoveTargetZone = "table"
        gameManager.sourceCueCardIds = [cueCard.id]

        viewModel.applyAuthoritativeSnapshot(opponentTurnSnapshot)
        XCTAssertTrue(
            gameManager.isLocalTurn,
            "Cue-only hand->table presentation must keep authoritative snapshots deferred so multiplayer reuses the same single-play animation lifecycle."
        )

        gameManager.sourceCueCardIds = []
        gameManager.currentMoveSourceZone = nil
        gameManager.currentMoveTargetZone = nil
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(gameManager.isLocalTurn)
    }
}
