struct ScoreItem: Codable {
    let name: String
    let points: Int
    let count: Int?
}

struct ScoringSystem {
    
    static func calculateScoreDetail(for player: Player) -> [ScoreItem] {
        guard let rules = RuleLoader.shared.config else {
            return [] // For now, only support detailed score with RuleConfig
        }
        
        var items: [ScoreItem] = []
        let cards = player.capturedCards
        
        items.append(contentsOf: getKwangDetails(cards: cards, rules: rules))
        items.append(contentsOf: getYulDetails(cards: cards, rules: rules))
        items.append(contentsOf: getDanDetails(cards: cards, rules: rules))
        items.append(contentsOf: getPiDetails(cards: cards, rules: rules))
        
        return items
    }
    
    static func calculateScore(for player: Player) -> Int {
        return calculateScoreDetail(for: player).reduce(0) { $0 + $1.points }
    }
    
    private static func getKwangDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        let kwangs = cards.filter { $0.type == .bright }
        let count = kwangs.count
        let s = rules.scoring.kwang
        
        if count == 5 { return [ScoreItem(name: "오광 (5 Brights)", points: s.ogwang, count: 5)] }
        if count == 4 { return [ScoreItem(name: "사광 (4 Brights)", points: s.sagwang, count: 4)] }
        if count == 3 {
            let hasBiGwang = kwangs.contains { $0.month.rawValue == 12 }
            return [ScoreItem(name: hasBiGwang ? "비삼광 (3 Brights incl. Rain)" : "삼광 (3 Brights)", points: hasBiGwang ? s.bisamgwang : s.samgwang, count: 3)]
        }
        return []
    }
    
    private static func getYulDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        var items: [ScoreItem] = []
        let yuls = cards.filter { $0.type == .animal }
        let count = yuls.count
        let s = rules.scoring.yul
        
        if count >= s.min_count {
            let pts = s.min_score + (count - s.min_count) * s.additional_score
            items.append(ScoreItem(name: "열끗 (\(count) Animals)", points: pts, count: count))
        }
        
        let godoriMonths = rules.cards.yul.godori
        let godoriCards = yuls.filter { godoriMonths.contains($0.month.rawValue) }
        if godoriCards.count == 3 {
            items.append(ScoreItem(name: "고도리 (Godori)", points: s.godori, count: 3))
        }
        
        return items
    }
    
    private static func getDanDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        var items: [ScoreItem] = []
        let dans = cards.filter { $0.type == .ribbon }
        let count = dans.count
        let s = rules.scoring.dan
        
        if count >= s.min_count {
            let pts = s.min_score + (count - s.min_count) * s.additional_score
            items.append(ScoreItem(name: "띠 (\(count) Ribbons)", points: pts, count: count))
        }
        
        let danRules = rules.cards.dan
        if dans.filter({ danRules.hongdan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: "홍단 (Red Ribbons)", points: s.hongdan, count: 3))
        }
        if dans.filter({ danRules.cheongdan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: "청단 (Blue Ribbons)", points: s.cheongdan, count: 3))
        }
        if dans.filter({ danRules.chodan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: "초단 (Grass Ribbons)", points: s.chodan, count: 3))
        }
        
        return items
    }
    
    private static func getPiDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        let piCount = calculatePiCount(cards: cards, rules: rules)
        let s = rules.scoring.pi
        if piCount >= s.min_count {
            let pts = s.min_score + (piCount - s.min_count) * s.additional_score
            return [ScoreItem(name: "피 (\(piCount) Junk)", points: pts, count: piCount)]
        }
        return []
    }
    
    static func calculatePiCount(cards: [Card], rules: RuleConfig) -> Int {
        var piCount = 0
        
        // Check for conditions
        let danRules = rules.cards.dan
        let hasCheongdan = cards.filter { $0.type == .ribbon && danRules.cheongdan.contains($0.month.rawValue) }.count == 3
        
        for card in cards {
            if card.type == .doubleJunk {
                piCount += 2
            } else if card.type == .junk {
                var currentVal = 1
                
                // Check if this junk card is a conditional double pi
                for condRule in rules.cards.pi.conditional_double_pi {
                    if card.month.rawValue == condRule.month {
                        if condRule.condition == "has_cheongdan" && hasCheongdan {
                            currentVal += condRule.bonus_points
                        }
                    }
                }
                piCount += currentVal
            }
        }
        return piCount
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
