import XCTest
@testable import GoStop

final class MultiplayerRound8Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
        
        let localId = "p1"
        let player = Player(name: "Me", money: 10000)
        player.id = UUID(uuidString: localId) ?? UUID()
        gameManager.players = [player]
        gameManager.localPlayerId = localId
    }

    func testSendChat_ShouldTriggerLocalAction() {
        // Arrange
        let expectation = self.expectation(description: "onLocalAction should be called")
        gameManager.onLocalAction = { action in
            if case .chat(let emojiId) = action {
                XCTAssertEqual(emojiId, "🔥")
                expectation.fulfill()
            }
        }
        
        // Act
        gameManager.sendChat(emojiId: "🔥")
        
        // Assert
        waitForExpectations(timeout: 1)
    }

    func testReceiveChat_ShouldUpdatePlayerChats() {
        // Arrange
        let opponentId = "p2"
        let snapshot = MockMultiplayerPayloads.generateChatSnapshot(
            localPlayerId: "p1",
            opponentId: opponentId,
            playerId: opponentId,
            emojiId: "😎"
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        XCTAssertNotNil(gameManager.playerChats[opponentId], "Opponent chat should be registered")
        XCTAssertEqual(gameManager.playerChats[opponentId]?.emojiId, "😎")
    }
    
    func testChat_ShouldAutoClearAfterTimeout() {
        // Arrange
        let opponentId = "p2"
        let snapshot = MockMultiplayerPayloads.generateChatSnapshot(
            localPlayerId: "p1",
            opponentId: opponentId,
            playerId: opponentId,
            emojiId: "😀"
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        XCTAssertNotNil(gameManager.playerChats[opponentId])
        
        // Assert
        let expectation = self.expectation(description: "Chat should be cleared")
        
        // We know it clears in 4 seconds. Let's wait 4.5 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if self.gameManager.playerChats[opponentId] == nil {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 6)
    }
}
