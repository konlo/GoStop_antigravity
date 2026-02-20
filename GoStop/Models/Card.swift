import Foundation

/// Represents the 12 months of Hwatu
enum Month: Int, CaseIterable, Comparable, Codable {
    case jan = 1, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
    
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
}

/// Represents a single Hwatu card
struct Card: Identifiable, Equatable, CustomStringConvertible, Codable {
    let id: UUID
    let month: Month
    let type: CardType
    let imageIndex: Int
    
    init(id: UUID = UUID(), month: Month, type: CardType, imageIndex: Int) {
        self.id = id
        self.month = month
        self.type = type
        self.imageIndex = imageIndex
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
            "id": id.uuidString,
            "month": month.rawValue,
            "type": type.rawValue,
            "imageIndex": imageIndex
        ]
    }
}
