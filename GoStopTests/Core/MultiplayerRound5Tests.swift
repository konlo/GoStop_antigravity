import XCTest
@testable import GoStop

final class MultiplayerRound5Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
    }

    func testMatchEnd_ShouldIdentifyWinnerCorrectly() {
        // Arrange
        let localId = "p1"
        let opponentId = "p2"
        
        let localPlayer = Player(name: "Me", money: 10000)
        localPlayer.id = UUID(uuidString: localId) ?? UUID()
        
        let opponentPlayer = Player(name: "Opponent", money: 10000)
        opponentPlayer.id = UUID(uuidString: opponentId) ?? UUID()
        
        gameManager.players = [localPlayer, opponentPlayer]
        
        // Generate match end snapshot where LOCAL wins
        let snapshot = MockMultiplayerPayloads.generateMatchEndSnapshot(localPlayerId: localId, opponentId: opponentId, winnerId: localId)
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        XCTAssertEqual(gameManager.gameState, .ended)
        XCTAssertEqual(gameManager.gameWinner?.id.uuidString, localId)
        XCTAssertEqual(gameManager.gameWinner?.score, 7)
    }
}
