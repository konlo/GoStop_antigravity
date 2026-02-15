import Foundation

struct Deck {
    private(set) var cards: [Card] = []
    
    init() {
        self.reset()
    }
    
    mutating func reset() {
        self.cards = Deck.createStandardDeck()
        self.shuffle()
    }
    
    mutating func shuffle() {
        cards.shuffle()
    }
    
    mutating func draw() -> Card? {
        guard !cards.isEmpty else { return nil }
        return cards.removeLast()
    }
    
    mutating func draw(count: Int) -> [Card] {
        var drawnCards: [Card] = []
        for _ in 0..<count {
            if let card = draw() {
                drawnCards.append(card)
            }
        }
        return drawnCards
    }
    
    // MARK: - Standard Deck Generation
    static func createStandardDeck() -> [Card] {
        var deck: [Card] = []
        
        // January (Pine)
        deck.append(Card(month: .jan, type: .bright, imageIndex: 0))
        deck.append(Card(month: .jan, type: .ribbon, imageIndex: 1)) // Red Poetry
        deck.append(Card(month: .jan, type: .junk, imageIndex: 2))
        deck.append(Card(month: .jan, type: .junk, imageIndex: 3))
        
        // February (Plum Blossom)
        deck.append(Card(month: .feb, type: .animal, imageIndex: 0)) // Bird
        deck.append(Card(month: .feb, type: .ribbon, imageIndex: 1)) // Red Poetry
        deck.append(Card(month: .feb, type: .junk, imageIndex: 2))
        deck.append(Card(month: .feb, type: .junk, imageIndex: 3))
        
        // March (Cherry Blossom)
        deck.append(Card(month: .mar, type: .bright, imageIndex: 0))
        deck.append(Card(month: .mar, type: .ribbon, imageIndex: 1)) // Red Poetry
        deck.append(Card(month: .mar, type: .junk, imageIndex: 2))
        deck.append(Card(month: .mar, type: .junk, imageIndex: 3))
        
        // April (Wisteria)
        deck.append(Card(month: .apr, type: .animal, imageIndex: 0)) // Bird
        deck.append(Card(month: .apr, type: .ribbon, imageIndex: 1)) // Red Grass
        deck.append(Card(month: .apr, type: .junk, imageIndex: 2))
        deck.append(Card(month: .apr, type: .junk, imageIndex: 3))
        
        // May (Iris)
        deck.append(Card(month: .may, type: .animal, imageIndex: 0))
        deck.append(Card(month: .may, type: .ribbon, imageIndex: 1)) // Red Grass
        deck.append(Card(month: .may, type: .junk, imageIndex: 2))
        deck.append(Card(month: .may, type: .junk, imageIndex: 3))
        
        // June (Peony)
        deck.append(Card(month: .jun, type: .animal, imageIndex: 0)) // Butterfly
        deck.append(Card(month: .jun, type: .ribbon, imageIndex: 1)) // Blue
        deck.append(Card(month: .jun, type: .junk, imageIndex: 2))
        deck.append(Card(month: .jun, type: .junk, imageIndex: 3))
        
        // July (Bush Clover)
        deck.append(Card(month: .jul, type: .animal, imageIndex: 0)) // Boar
        deck.append(Card(month: .jul, type: .ribbon, imageIndex: 1)) // Red Grass
        deck.append(Card(month: .jul, type: .junk, imageIndex: 2))
        deck.append(Card(month: .jul, type: .junk, imageIndex: 3))
        
        // August (Moon/Susuk)
        deck.append(Card(month: .aug, type: .bright, imageIndex: 0)) // Moon
        deck.append(Card(month: .aug, type: .animal, imageIndex: 1)) // Geese
        deck.append(Card(month: .aug, type: .junk, imageIndex: 2))
        deck.append(Card(month: .aug, type: .junk, imageIndex: 3))
        
        // September (Chrysanthemum)
        deck.append(Card(month: .sep, type: .animal, imageIndex: 0)) // Sake Cup
        deck.append(Card(month: .sep, type: .ribbon, imageIndex: 1)) // Blue
        deck.append(Card(month: .sep, type: .junk, imageIndex: 2))
        deck.append(Card(month: .sep, type: .junk, imageIndex: 3))
        
        // October (Maple)
        deck.append(Card(month: .oct, type: .animal, imageIndex: 0)) // Deer
        deck.append(Card(month: .oct, type: .ribbon, imageIndex: 1)) // Blue
        deck.append(Card(month: .oct, type: .junk, imageIndex: 2))
        deck.append(Card(month: .oct, type: .junk, imageIndex: 3))
        
        // November (Paulownia)
        deck.append(Card(month: .nov, type: .bright, imageIndex: 0)) // Phoenix
        deck.append(Card(month: .nov, type: .doubleJunk, imageIndex: 1)) // Colored
        deck.append(Card(month: .nov, type: .junk, imageIndex: 2))
        deck.append(Card(month: .nov, type: .junk, imageIndex: 3))
        
        // December (Rain)
        deck.append(Card(month: .dec, type: .bright, imageIndex: 0)) // Rain Man
        deck.append(Card(month: .dec, type: .animal, imageIndex: 1)) // Bird
        deck.append(Card(month: .dec, type: .ribbon, imageIndex: 2)) // Red
        deck.append(Card(month: .dec, type: .doubleJunk, imageIndex: 3)) // Double Junk
        
        return deck
    }
}
