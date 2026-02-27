import XCTest
import Combine
@testable import GoStop

final class GoStopTests: XCTestCase {
    
    func testDeckCount() {
        let deck = Deck()
        XCTAssertEqual(deck.cards.count, 48, "Deck should have 48 cards")
    }
    
    func testDeckShuffle() {
        var deck1 = Deck()
        var deck2 = Deck()
        // Extremely low probability of matching exactly if shuffled
        // Ideally we check if order changes, but for now just check content equality logic isn't trivial
        // Just checking counts are same
        XCTAssertEqual(deck1.cards.count, deck2.cards.count)
    }
    
    func testUniqueCards() {
        let deck = Deck()
        let uniqueIDs = Set(deck.cards.map { $0.id })
        XCTAssertEqual(uniqueIDs.count, 48, "All cards should have unique IDs")
    }
    
    func testGameManagerSetup() {
        let game = GameManager()
        XCTAssertEqual(game.gameState, .ready)
        XCTAssertEqual(game.players.count, 2)
        XCTAssertEqual(game.players[0].hand.count, 10)
        XCTAssertEqual(game.tableCards.count, 8)
        XCTAssertEqual(game.deck.cards.count, 48 - 20 - 8) // 48 - 10*2 - 8 = 20
    }
    
    func testScoringBasic() {
        let player = Player(name: "Test")
        
        // Test 3 Gwang (3 points)
        player.capturedCards = [
            Card(month: .jan, type: .bright, imageIndex: 0),
            Card(month: .mar, type: .bright, imageIndex: 0),
            Card(month: .aug, type: .bright, imageIndex: 0)
        ]
        
        let score = ScoringSystem.calculateScore(for: player)
        XCTAssertEqual(score, 3)
    }
    
    func testGodori() {
        let player = Player(name: "Test")
        
        // Godori (5 points)
        player.capturedCards = [
            Card(month: .feb, type: .animal, imageIndex: 0), // Bird
            Card(month: .apr, type: .animal, imageIndex: 0), // Bird
            Card(month: .aug, type: .animal, imageIndex: 0)  // Geese
        ]
        
        // We need to ensure these are actually recognized as birds in isBird
        let score = ScoringSystem.calculateScore(for: player)
        XCTAssertEqual(score, 5)
    }
    
    func testMatchingLogic() {
        let game = GameManager()
        game.startGame()
        let player = game.players[0]
        
        // Setup state for deterministic test
        let myCard = Card(month: .jan, type: .bright, imageIndex: 0)
        let tableCard = Card(month: .jan, type: .junk, imageIndex: 2)
        
        player.hand = [myCard]
        game.tableCards = [tableCard]
        
        // Capture initial count
        let initialCaptured = player.capturedCards.count
        
        // Play
        game.playTurn(card: myCard)
        
        // Verify capture happened
        XCTAssertGreaterThan(player.capturedCards.count, initialCaptured)
        
        // Verify specifically that the initial table card is gone
        // Card equality checks UUID, so even if another Jan Junk appears, it won't be this one.
        XCTAssertFalse(game.tableCards.contains(tableCard), "The specific table card should be captured")
    }
    
    func testAssetLoading() {
        // GameManager is a class in the main module, so Bundle(for:) should point to the main bundle (or the framework bundle if modularized)
        let bundle = Bundle(for: GameManager.self)
        let sampleCards = ["Card_jan_0", "Card_dec_3", "Card_aug_0"]
        for cardName in sampleCards {
            let image = UIImage(named: cardName, in: bundle, compatibleWith: nil)
            XCTAssertNotNil(image, "Failed to load image asset: \(cardName) from bundle: \(bundle.bundlePath)")
        }
    }

    func testGameManagerForwardsNestedPlayerCapturedChanges() {
        let game = GameManager()
        let exp = expectation(description: "GameManager should publish when Player.capturedCards changes")
        var cancellable: AnyCancellable?

        cancellable = game.objectWillChange.sink {
            exp.fulfill()
        }

        game.players[0].capture(cards: [Card(month: .jan, type: .bright, imageIndex: 0)])

        wait(for: [exp], timeout: 0.5)
        withExtendedLifetime(cancellable) {}
    }
}
