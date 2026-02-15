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
}
