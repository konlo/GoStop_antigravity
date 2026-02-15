import Foundation

/// Represents the 12 months of Hwatu
enum Month: Int, CaseIterable, Comparable {
    case jan = 1, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
    
    static func < (lhs: Month, rhs: Month) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Represents the type of Hwatu card for scoring
enum CardType: Equatable {
    case bright         // Gwang (광)
    case animal         // Yul (열)
    case ribbon         // Tti (띠)
    case junk           // Pi (피)
    case doubleJunk     // SsangPi (쌍피)
}

/// Represents a single Hwatu card
struct Card: Identifiable, Equatable, CustomStringConvertible {
    let id = UUID()
    let month: Month
    let type: CardType
    
    // Helper to identify specific special cards
    var isBird: Bool {
        // February (Nightingale), April (Cuckoo), August (Geese)
        guard type == .animal else { return false }
        return month == .feb || month == .apr || month == .aug
    }
    
    var description: String {
        return "\(month) - \(type)"
    }
}
