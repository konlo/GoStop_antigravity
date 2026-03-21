import XCTest
@testable import GoStop

final class MultiplayerRound3Tests: XCTestCase {

    var gameManager: GameManager!
    var mapper: MultiplayerStateMapper!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        mapper = DefaultMultiplayerStateMapper()
    }

    func testPlayTurn_WhenNotLocalTurn_ShouldBeBlocked() throws {
        // Arrange
        let localId = "player_me"
        let opponentId = "player_them"
        
        // 1. Give snapshot where it's opponent's turn
        let snapshot = MockMultiplayerPayloads.generateOpponentTurnSnapshot(localPlayerId: localId, opponentId: opponentId)
        let mappedState = try mapper.mapSnapshot(snapshot, currentPlayers: [])
        
        gameManager.applyMappedState(mappedState)
        gameManager.localPlayerId = localId
        
        XCTAssertTrue(gameManager.externalControlMode)
        XCTAssertFalse(gameManager.isLocalTurn)
        
        let initialHandCount = gameManager.players.first?.hand.count ?? 0
        let initialTableCount = gameManager.tableCards.count
        
        // Act
        if let card = gameManager.players.first?.hand.first {
            gameManager.playTurn(card: card)
        }
        
        // Assert
        XCTAssertEqual(gameManager.players.first?.hand.count, initialHandCount, "Hand count should not change when blocked")
        XCTAssertEqual(gameManager.tableCards.count, initialTableCount, "Table cards should not change when blocked")
    }
    
    func testPlayTurn_WhenIsLocalTurn_ShouldBeAllowed() throws {
        // Arrange
        let localId = "player_me"
        let opponentId = "player_them"
        
        // 1. My turn
        let snapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(localPlayerId: localId, opponentId: opponentId)
        let mappedState = try mapper.mapSnapshot(snapshot, currentPlayers: [])
        
        gameManager.applyMappedState(mappedState)
        gameManager.localPlayerId = localId
        
        XCTAssertTrue(gameManager.isLocalTurn)
        
        let initialHandCount = gameManager.players.first?.hand.count ?? 0
        
        // Act
        if let card = gameManager.players.first?.hand.first {
            gameManager.playTurn(card: card)
        }
        
        // Assert
        XCTAssertEqual(gameManager.players.first?.hand.count, initialHandCount - 1, "Hand count should decrease when allowed")
    }
}
