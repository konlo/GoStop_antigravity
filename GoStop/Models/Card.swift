import Foundation

/// Represents the 12 months of Hwatu
enum Month: Int, CaseIterable, Comparable, Codable {
    case jan = 1, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
    case none = 0
    
    static func < (lhs: Month, rhs: Month) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Represents the type of Hwatu card for scoring
enum CardType: String, Equatable, Codable, CaseIterable {
    case bright         // Gwang (광)
    case animal         // Yul (열)
    case ribbon         // Tti (띠)
    case junk           // Pi (피)
    case doubleJunk     // SsangPi (쌍피)
    case dummy          // Dummy card for Bomb (폭탄용 더미)
}

/// Represents a single Hwatu card
struct Card: Identifiable, Equatable, CustomStringConvertible, Codable {
    let id: String
    let month: Month
    let type: CardType
    let imageIndex: Int
    
    init(id: String = UUID().uuidString, month: Month, type: CardType, imageIndex: Int) {
        self.id = id
        self.month = month
        self.type = type
        self.imageIndex = imageIndex
    }
    
    static func == (lhs: Card, rhs: Card) -> Bool {
        return lhs.id == rhs.id
    }
    
    var isBird: Bool {
        // February (Nightingale), April (Cuckoo), August (Geese)
        guard type == .animal else { return false }
        return month == .feb || month == .apr || month == .aug
    }
    
    var description: String {
        return "\(month) - \(type)"
    }
    
    func serialize() -> [String: Any] {
        return [
            "id": id,
            "month": month.rawValue,
            "type": type.rawValue,
            "imageIndex": imageIndex
        ]
    }
}
