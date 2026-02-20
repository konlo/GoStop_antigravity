import Foundation

struct ScoringSystem {
    
    static func calculateScore(for player: Player) -> Int {
        guard let rules = RuleLoader.shared.config else {
            return calculateLegacyScore(for: player)
        }
        
        var score = 0
        let cards = player.capturedCards
        
        score += calculateKwangScore(cards: cards, rules: rules)
        score += calculateYulScore(cards: cards, rules: rules)
        score += calculateDanScore(cards: cards, rules: rules)
        score += calculatePiScore(cards: cards, rules: rules)
        
        return score
    }
    
    private static func calculateKwangScore(cards: [Card], rules: RuleConfig) -> Int {
        let kwangs = cards.filter { $0.type == .bright }
        let count = kwangs.count
        let s = rules.scoring.kwang
        
        if count == 5 { return s.ogwang }
        if count == 4 { return s.sagwang }
        if count == 3 {
            let hasBiGwang = kwangs.contains { $0.month.rawValue == 12 } // 12 represents December (Rain)
            return hasBiGwang ? s.bisamgwang : s.samgwang
        }
        return 0
    }
    
    private static func calculateYulScore(cards: [Card], rules: RuleConfig) -> Int {
        var score = 0
        let yuls = cards.filter { $0.type == .animal }
        let count = yuls.count
        let s = rules.scoring.yul
        
        if count >= s.min_count {
            score += s.min_score + (count - s.min_count) * s.additional_score
        }
        
        let godoriMonths = rules.cards.yul.godori
        let godoriCards = yuls.filter { godoriMonths.contains($0.month.rawValue) }
        if godoriCards.count == 3 {
            score += s.godori
        }
        
        return score
    }
    
    private static func calculateDanScore(cards: [Card], rules: RuleConfig) -> Int {
        var score = 0
        let dans = cards.filter { $0.type == .ribbon }
        let count = dans.count
        let s = rules.scoring.dan
        
        if count >= s.min_count {
            score += s.min_score + (count - s.min_count) * s.additional_score
        }
        
        let danRules = rules.cards.dan
        let hongdan = dans.filter { danRules.hongdan.contains($0.month.rawValue) }.count
        if hongdan == 3 { score += s.hongdan }
        
        let cheongdan = dans.filter { danRules.cheongdan.contains($0.month.rawValue) }.count
        if cheongdan == 3 { score += s.cheongdan }
        
        let chodan = dans.filter { danRules.chodan.contains($0.month.rawValue) }.count
        if chodan == 3 { score += s.chodan }
        
        return score
    }
    
    static func calculatePiCount(cards: [Card], rules: RuleConfig) -> Int {
        var piCount = 0
        let piRules = rules.cards.pi
        
        for card in cards {
            if card.type == .doubleJunk {
                piCount += 2
            } else if card.type == .junk {
                if piRules.double_pi_months.contains(card.month.rawValue) {
                    piCount += 2
                } else {
                    piCount += 1
                }
            }
        }
        return piCount
    }
    
    private static func calculatePiScore(cards: [Card], rules: RuleConfig) -> Int {
        var score = 0
        let piCount = calculatePiCount(cards: cards, rules: rules)
        
        let s = rules.scoring.pi
        if piCount >= s.min_count {
            score += s.min_score + (piCount - s.min_count) * s.additional_score
        }
        
        return score
    }
    
    private static func calculateLegacyScore(for player: Player) -> Int {
        var score = 0
        let cards = player.capturedCards
        
        let brights = cards.filter { $0.type == .bright }
        let brightCount = brights.count
        if brightCount == 5 { score += 15 }
        else if brightCount == 4 { score += 4 }
        else if brightCount == 3 {
            let hasRainGwang = brights.contains { $0.month == .dec }
            score += hasRainGwang ? 2 : 3
        }
        
        let animals = cards.filter { $0.type == .animal }
        let animalCount = animals.count
        if animalCount >= 5 {
            score += (animalCount - 4)
        }
        
        let godoriCount = animals.filter { $0.month == .feb || $0.month == .apr || $0.month == .aug }.count
        if godoriCount == 3 { score += 5 }
        
        let ribbons = cards.filter { $0.type == .ribbon }
        let ribbonCount = ribbons.count
        if ribbonCount >= 5 {
            score += (ribbonCount - 4)
        }
        
        let redPoetry = ribbons.filter { $0.month == .jan || $0.month == .feb || $0.month == .mar }.count
        if redPoetry == 3 { score += 3 }
        
        let blueRibbons = ribbons.filter { $0.month == .jun || $0.month == .sep || $0.month == .oct }.count
        if blueRibbons == 3 { score += 3 }
        
        let redGrass = ribbons.filter { $0.month == .apr || $0.month == .may || $0.month == .jul }.count
        if redGrass == 3 { score += 3 }
        
        var junkCount = 0
        for card in cards {
            if card.type == .junk { junkCount += 1 }
            else if card.type == .doubleJunk { junkCount += 2 }
        }
        
        if junkCount >= 10 {
            score += (junkCount - 9)
        }
        
        return score
    }
}
