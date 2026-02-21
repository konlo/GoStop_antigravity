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
    @Published var shakenMonths: [Int] = []
    @Published var bombCount: Int = 0
    @Published var sweepCount: Int = 0
    @Published var ttadakCount: Int = 0
    @Published var jjokCount: Int = 0
    @Published var seolsaCount: Int = 0
    @Published var isPiMungbak: Bool = false
    @Published var mungddaCount: Int = 0
    @Published var bombMungddaCount: Int = 0
    @Published var isComputer: Bool = false
    @Published var dummyCardCount: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case id, name, hand, capturedCards, score, money, goCount, lastGoScore, shakeCount, shakenMonths, bombCount, sweepCount, ttadakCount, jjokCount, seolsaCount, isPiMungbak, mungddaCount, bombMungddaCount, isComputer, dummyCardCount
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
        shakenMonths = try container.decode([Int].self, forKey: .shakenMonths)
        bombCount = try container.decode(Int.self, forKey: .bombCount)
        sweepCount = try container.decode(Int.self, forKey: .sweepCount)
        ttadakCount = try container.decode(Int.self, forKey: .ttadakCount)
        jjokCount = try container.decode(Int.self, forKey: .jjokCount)
        seolsaCount = try container.decode(Int.self, forKey: .seolsaCount)
        isPiMungbak = try container.decode(Bool.self, forKey: .isPiMungbak)
        mungddaCount = try container.decode(Int.self, forKey: .mungddaCount)
        bombMungddaCount = try container.decode(Int.self, forKey: .bombMungddaCount)
        isComputer = try container.decode(Bool.self, forKey: .isComputer)
        dummyCardCount = try container.decodeIfPresent(Int.self, forKey: .dummyCardCount) ?? 0
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
        try container.encode(shakenMonths, forKey: .shakenMonths)
        try container.encode(bombCount, forKey: .bombCount)
        try container.encode(sweepCount, forKey: .sweepCount)
        try container.encode(ttadakCount, forKey: .ttadakCount)
        try container.encode(jjokCount, forKey: .jjokCount)
        try container.encode(seolsaCount, forKey: .seolsaCount)
        try container.encode(isPiMungbak, forKey: .isPiMungbak)
        try container.encode(mungddaCount, forKey: .mungddaCount)
        try container.encode(bombMungddaCount, forKey: .bombMungddaCount)
        try container.encode(isComputer, forKey: .isComputer)
        try container.encode(dummyCardCount, forKey: .dummyCardCount)
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
        shakenMonths.removeAll()
        bombCount = 0
        sweepCount = 0
        ttadakCount = 0
        jjokCount = 0
        seolsaCount = 0
        isPiMungbak = false
        mungddaCount = 0
        bombMungddaCount = 0
        isComputer = false // reset will be called by startGame, which sets computer state again
        dummyCardCount = 0
    }
    
    func receive(cards: [Card]) {
        hand.append(contentsOf: cards)
    }
    
    var piCount: Int {
        var count = 0
        for card in capturedCards {
            if card.type == .junk { count += 1 }
            else if card.type == .doubleJunk { count += 2 }
        }
        return count
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
            "shakeCount": shakeCount,
            "shakenMonths": shakenMonths,
            "bombCount": bombCount,
            "sweepCount": sweepCount,
            "ttadakCount": ttadakCount,
            "jjokCount": jjokCount,
            "seolsaCount": seolsaCount,
            "isPiMungbak": isPiMungbak,
            "mungddaCount": mungddaCount,
            "bombMungddaCount": bombMungddaCount,
            "isComputer": isComputer,
            "dummyCardCount": dummyCardCount
        ]
    }
}
