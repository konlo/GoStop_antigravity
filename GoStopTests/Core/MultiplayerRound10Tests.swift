import XCTest
@testable import GoStop

final class MultiplayerRound10Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
        
        let localId = "p1"
        let player = Player(name: "Me", money: 10000)
        player.id = UUID(uuidString: localId) ?? UUID()
        gameManager.players = [player]
        gameManager.localPlayerId = localId
    }

    func testMatchEnd_ShouldSetFlag() {
        // Arrange
        let snapshot = MockMultiplayerPayloads.generateMatchEndSnapshot(
            winnerId: "p1",
            reason: .normal
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        XCTAssertTrue(gameManager.isMatchEndedFlag, "Match ended flag should be true after receiving end snapshot")
    }

    func testExitToLobby_ShouldClearAllSessionState() {
        // Arrange - Setup some session state
        gameManager.matchHistory = ["p1": 5, "p2": 3]
        gameManager.playerChats = ["p2": MultiplayerChatPresence(playerId: "p2", emojiId: "🔥", text: nil, sentAt: Date())]
        gameManager.isMatchEndedFlag = true
        gameManager.gameState = .ended
        
        // Act
        gameManager.exitToLobby()
        
        // Assert
        XCTAssertTrue(gameManager.matchHistory.isEmpty, "Match history should be cleared")
        XCTAssertTrue(gameManager.playerChats.isEmpty, "Player chats should be cleared")
        XCTAssertFalse(gameManager.isMatchEndedFlag, "Match ended flag should be reset")
        XCTAssertNil(gameManager.currentScoreboard, "Scoreboard should be cleared")
        XCTAssertEqual(gameManager.gameState, .ready, "Game state should return to ready (lobby)")
    }
}
