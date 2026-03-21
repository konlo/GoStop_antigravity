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
        let card = Card(month: .january, type: .bright, imageIndex: 0)
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
        let card = Card(month: .january, type: .bright, imageIndex: 0)
        player.hand = [card]
        gameManager.players = [player]
        gameManager.gameState = .playing
        
        // Act
        gameManager.playTurn(card: card)
        
        // Assert
        // The card should be in currentMovingCards while animation is scheduled
        XCTAssertTrue(gameManager.currentMovingCards.contains(card.id), "Card should be in moving queue for optimistic UI")
    }
}
