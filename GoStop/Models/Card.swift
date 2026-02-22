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
enum CardType: String, Codable {
    case bright          // 광
    case animal          // 끗
    case ribbon          // 띠
    case junk            // 피
    case doubleJunk      // 쌍피
    case dummy           // Dummy card for Bomb (폭탄용 더미)
}

/// Represents the selected role of a card (for flexible cards like Sep Animal)
enum CardRole: String, Codable {
    case animal
    case doublePi
}

/// Represents a single Hwatu card
struct Card: Identifiable, Equatable, CustomStringConvertible, Codable {
    let id: String
    let month: Month
    let type: CardType
    let imageIndex: Int
    var selectedRole: CardRole?
    
    init(id: String = UUID().uuidString, month: Month, type: CardType, imageIndex: Int, selectedRole: CardRole? = nil) {
        self.id = id
        self.month = month
        self.type = type
        self.imageIndex = imageIndex
        self.selectedRole = selectedRole
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
        var dict: [String: Any] = [
            "id": id,
            "month": month.rawValue,
            "type": type.rawValue,
            "imageIndex": imageIndex
        ]
        if let selectedRole = selectedRole {
            dict["selectedRole"] = selectedRole.rawValue
        }
        return dict
    }
}
