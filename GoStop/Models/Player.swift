import Foundation

class Player: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    @Published var hand: [Card] = []
    @Published var capturedCards: [Card] = []
    @Published var score: Int = 0
    @Published var money: Int
    @Published var goCount: Int = 0
    @Published var lastGoScore: Int = 0
    
    init(name: String, money: Int = 10000) {
        self.name = name
        self.money = money
    }
    
    func reset() {
        hand.removeAll()
        capturedCards.removeAll()
        score = 0
        goCount = 0
        lastGoScore = 0
    }
    
    func receive(cards: [Card]) {
        hand.append(contentsOf: cards)
    }
    
    func play(card: Card) -> Card? {
        guard let index = hand.firstIndex(of: card) else { return nil }
        return hand.remove(at: index)
    }
    
    func capture(cards: [Card]) {
        capturedCards.append(contentsOf: cards)
        calculateScore()
    }
    
    func calculateScore() {
        // Placeholder for scoring logic
        // Will be implemented in the next phase
    }
}
