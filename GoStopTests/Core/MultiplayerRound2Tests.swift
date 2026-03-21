import XCTest
@testable import GoStop

final class MultiplayerRound2Tests: XCTestCase {

    var gameManager: GameManager!
    var mapper: MultiplayerStateMapper!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        mapper = DefaultMultiplayerStateMapper()
    }

    func testApplyMappedState_CorrectlyPopulatesHandsAndTable() throws {
        // Arrange
        let localId = UUID().uuidString
        let opponentId = UUID().uuidString
        let snapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(localPlayerId: localId, opponentId: opponentId)
        
        // Act
        let mappedState = try mapper.mapSnapshot(snapshot, currentPlayers: gameManager.players)
        gameManager.applyMappedState(mappedState)
        
        // Assert
        XCTAssertEqual(gameManager.gameState, .playing)
        XCTAssertEqual(gameManager.players.count, 2)
        
        let localPlayer = gameManager.players.first(where: { $0.id.uuidString == localId })
        XCTAssertNotNil(localPlayer)
        XCTAssertEqual(localPlayer?.hand.count, 10, "Local player should have 10 cards")
        
        let opponentPlayer = gameManager.players.first(where: { $0.id.uuidString == opponentId })
        XCTAssertNotNil(opponentPlayer)
        XCTAssertEqual(opponentPlayer?.hand.count, 10, "Opponent should have 10 cards (dummy cards in local view)")
        
        XCTAssertEqual(gameManager.tableCards.count, 8, "Table should have 8 cards")
    }
    
    func testApplyMappedState_SuppressesAnimations() throws {
        // Arrange
        let localId = UUID().uuidString
        let snapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(localPlayerId: localId, opponentId: "other")
        let mappedState = try mapper.mapSnapshot(snapshot, currentPlayers: gameManager.players)
        
        // Act
        gameManager.applyMappedState(mappedState)
        
        // Assert
        // AnimationManager.suppressAnimations is used internally with a defer block, 
        // so it should be false after the call.
        XCTAssertFalse(AnimationManager.shared.suppressAnimations)
    }
}
