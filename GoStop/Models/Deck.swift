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
        deck.append(Card(month: .jan, type: .bright))
        deck.append(Card(month: .jan, type: .ribbon)) // Red Poetry
        deck.append(Card(month: .jan, type: .junk))
        deck.append(Card(month: .jan, type: .junk))
        
        // February (Plum Blossom)
        deck.append(Card(month: .feb, type: .animal)) // Bird
        deck.append(Card(month: .feb, type: .ribbon)) // Red Poetry
        deck.append(Card(month: .feb, type: .junk))
        deck.append(Card(month: .feb, type: .junk))
        
        // March (Cherry Blossom)
        deck.append(Card(month: .mar, type: .bright))
        deck.append(Card(month: .mar, type: .ribbon)) // Red Poetry
        deck.append(Card(month: .mar, type: .junk))
        deck.append(Card(month: .mar, type: .junk))
        
        // April (Wisteria)
        deck.append(Card(month: .apr, type: .animal)) // Bird
        deck.append(Card(month: .apr, type: .ribbon)) // Red Grass
        deck.append(Card(month: .apr, type: .junk))
        deck.append(Card(month: .apr, type: .junk))
        
        // May (Iris)
        deck.append(Card(month: .may, type: .animal))
        deck.append(Card(month: .may, type: .ribbon)) // Red Grass
        deck.append(Card(month: .may, type: .junk))
        deck.append(Card(month: .may, type: .junk))
        
        // June (Peony)
        deck.append(Card(month: .jun, type: .animal)) // Butterfly
        deck.append(Card(month: .jun, type: .ribbon)) // Blue
        deck.append(Card(month: .jun, type: .junk))
        deck.append(Card(month: .jun, type: .junk))
        
        // July (Bush Clover)
        deck.append(Card(month: .jul, type: .animal)) // Boar
        deck.append(Card(month: .jul, type: .ribbon)) // Red Grass
        deck.append(Card(month: .jul, type: .junk))
        deck.append(Card(month: .jul, type: .junk))
        
        // August (Moon/Susuk)
        deck.append(Card(month: .aug, type: .bright)) // Moon
        deck.append(Card(month: .aug, type: .animal)) // Geese
        deck.append(Card(month: .aug, type: .junk))
        deck.append(Card(month: .aug, type: .junk))
        
        // September (Chrysanthemum)
        deck.append(Card(month: .sep, type: .animal)) // Sake Cup
        deck.append(Card(month: .sep, type: .ribbon)) // Blue
        deck.append(Card(month: .sep, type: .junk))
        deck.append(Card(month: .sep, type: .junk))
        
        // October (Maple)
        deck.append(Card(month: .oct, type: .animal)) // Deer
        deck.append(Card(month: .oct, type: .ribbon)) // Blue
        deck.append(Card(month: .oct, type: .junk))
        deck.append(Card(month: .oct, type: .junk))
        
        // November (Paulownia)
        deck.append(Card(month: .nov, type: .bright)) // Phoenix
        deck.append(Card(month: .nov, type: .doubleJunk)) // Colored
        deck.append(Card(month: .nov, type: .junk))
        deck.append(Card(month: .nov, type: .junk))
        
        // December (Rain)
        deck.append(Card(month: .dec, type: .bright)) // Rain Man
        deck.append(Card(month: .dec, type: .animal)) // Bird
        deck.append(Card(month: .dec, type: .ribbon)) // Red
        deck.append(Card(month: .dec, type: .doubleJunk)) // Double Junk
        
        return deck
    }
}
