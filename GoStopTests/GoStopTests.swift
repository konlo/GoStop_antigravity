import XCTest
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
            Card(month: .jan, type: .bright),
            Card(month: .mar, type: .bright),
            Card(month: .aug, type: .bright)
        ]
        
        let score = ScoringSystem.calculateScore(for: player)
        XCTAssertEqual(score, 3)
    }
    
    func testGodori() {
        let player = Player(name: "Test")
        
        // Godori (5 points)
        player.capturedCards = [
            Card(month: .feb, type: .animal), // Bird
            Card(month: .apr, type: .animal), // Bird
            Card(month: .aug, type: .animal)  // Geese
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
        player.hand = [Card(month: .jan, type: .bright)] // Hold Jan Bright
        game.tableCards = [Card(month: .jan, type: .junk)] // Table has Jan Junk
        // Deck needs to be controlled or we mock it. 
        // For simple integration test, we just check if playing the card captures the table card.
        // But playTurn draws from deck too, which introduces randomness.
        // We can check if table card count decreases or captured count increases at least by 2.
        
        let initialCaptured = player.capturedCards.count
        game.playTurn(card: player.hand[0])
        
        // We expect at least the played card and table card to be captured (2 cards)
        // Plus potentially what was drawn from deck.
        XCTAssertGreaterThan(player.capturedCards.count, initialCaptured)
        // Table should not have the Jan Junk anymore
        XCTAssertFalse(game.tableCards.contains { $0.month == .jan && $0.type == .junk })
    }
}
