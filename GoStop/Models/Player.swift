import Foundation

class Player: ObservableObject, Identifiable, Codable {
    let id: UUID
    let name: String
    @Published var hand: [Card] = []
    @Published var capturedCards: [Card] = []
    @Published var score: Int = 0
    @Published var money: Int
    @Published var goCount: Int = 0
    @Published var lastGoScore: Int = 0
    @Published var shakeCount: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case id, name, hand, capturedCards, score, money, goCount, lastGoScore, shakeCount
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hand = try container.decode([Card].self, forKey: .hand)
        capturedCards = try container.decode([Card].self, forKey: .capturedCards)
        score = try container.decode(Int.self, forKey: .score)
        money = try container.decode(Int.self, forKey: .money)
        goCount = try container.decode(Int.self, forKey: .goCount)
        lastGoScore = try container.decode(Int.self, forKey: .lastGoScore)
        shakeCount = try container.decode(Int.self, forKey: .shakeCount)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(hand, forKey: .hand)
        try container.encode(capturedCards, forKey: .capturedCards)
        try container.encode(score, forKey: .score)
        try container.encode(money, forKey: .money)
        try container.encode(goCount, forKey: .goCount)
        try container.encode(lastGoScore, forKey: .lastGoScore)
        try container.encode(shakeCount, forKey: .shakeCount)
    }

    init(id: UUID = UUID(), name: String, money: Int = 10000) {
        self.id = id
        self.name = name
        self.money = money
    }
    
    func reset() {
        hand.removeAll()
        capturedCards.removeAll()
        score = 0
        goCount = 0
        lastGoScore = 0
        shakeCount = 0
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

    func serialize() -> [String: Any] {
        return [
            "id": id.uuidString,
            "name": name,
            "hand": hand,
            "capturedCards": capturedCards,
            "score": score,
            "money": money,
            "goCount": goCount,
            "lastGoScore": lastGoScore,
            "shakeCount": shakeCount
        ]
    }
}
