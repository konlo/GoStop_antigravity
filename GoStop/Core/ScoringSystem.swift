struct ScoreItem: Codable {
    let name: String
    let points: Int
    let count: Int?
    
    func serialize() -> [String: Any] {
        var dict: [String: Any] = ["name": name, "points": points]
        if let count = count { dict["count"] = count }
        return dict
    }
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
        items.append(contentsOf: getSpecialMoveBonusDetails(for: player, rules: rules))
        
        return items
    }
    
    static func calculateScore(for player: Player) -> Int {
        return calculateScoreDetail(for: player).reduce(0) { $0 + $1.points }
    }
    
    private static func getKwangDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        let kwangs = cards.filter { $0.type == .bright }
        let count = kwangs.count
        let s = rules.scoring.kwang
        
        if count == 5 { return [ScoreItem(name: gameText("score.item.ogwang"), points: s.ogwang, count: 5)] }
        if count == 4 { return [ScoreItem(name: gameText("score.item.sagwang"), points: s.sagwang, count: 4)] }
        if count == 3 {
            let hasBiGwang = kwangs.contains { $0.month.rawValue == 12 }
            return [
                ScoreItem(
                    name: gameText(hasBiGwang ? "score.item.bisamgwang" : "score.item.samgwang"),
                    points: hasBiGwang ? s.bisamgwang : s.samgwang,
                    count: 3
                )
            ]
        }
        return []
    }
    
    private static func getYulDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        var items: [ScoreItem] = []
        // Filter out Sep Animal if its role is doublePi
        let yuls = cards.filter { $0.type == .animal }
        let activeYuls = yuls.filter { card in
            if card.month == Month.sep {
                let defaultRole = rules.cards.chrysanthemum_rule.default_role
                return (card.selectedRole == CardRole.animal) || (card.selectedRole == nil && defaultRole == "animal")
            }
            return true
        }
        let count = activeYuls.count
        let s = rules.scoring.yul
        
        if count >= s.min_count {
            let pts = s.min_score + (count - s.min_count) * s.additional_score
            items.append(
                ScoreItem(
                    name: gameText("score.item.yul", ["count": count]),
                    points: pts,
                    count: count
                )
            )
        }
        
        let godoriMonths = rules.cards.yul.godori
        let godoriCards = activeYuls.filter { card in
            godoriMonths.contains(card.month.rawValue) && (card.selectedRole == CardRole.animal || card.selectedRole == nil)
        }
        if godoriCards.count == 3 {
            items.append(ScoreItem(name: gameText("score.item.godori"), points: s.godori, count: 3))
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
            items.append(
                ScoreItem(
                    name: gameText("score.item.dan", ["count": count]),
                    points: pts,
                    count: count
                )
            )
        }
        
        let danRules = rules.cards.dan
        if dans.filter({ danRules.hongdan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: gameText("score.item.hongdan"), points: s.hongdan, count: 3))
        }
        if dans.filter({ danRules.cheongdan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: gameText("score.item.cheongdan"), points: s.cheongdan, count: 3))
        }
        if dans.filter({ danRules.chodan.contains($0.month.rawValue) }).count == 3 {
            items.append(ScoreItem(name: gameText("score.item.chodan"), points: s.chodan, count: 3))
        }
        
        return items
    }
    
    private static func getPiDetails(cards: [Card], rules: RuleConfig) -> [ScoreItem] {
        let piCount = calculatePiCount(cards: cards, rules: rules)
        let s = rules.scoring.pi
        if piCount >= s.min_count {
            let pts = s.min_score + (piCount - s.min_count) * s.additional_score
            return [
                ScoreItem(
                    name: gameText("score.item.pi", ["count": piCount]),
                    points: pts,
                    count: piCount
                )
            ]
        }
        return []
    }

    private static func getSpecialMoveBonusDetails(for player: Player, rules: RuleConfig) -> [ScoreItem] {
        var items: [ScoreItem] = []

        if player.awardedFirstTurnTtadakBonus {
            let points = rules.special_moves.ttadak.first_turn_bonus_score ?? 0
            if points > 0 {
                items.append(ScoreItem(name: gameText("score.item.opening_ttadak"), points: points, count: nil))
            }
        }

        if player.awardedFirstTurnSeolsaBonus {
            let points = rules.special_moves.seolsa.first_turn_bonus_score ?? 0
            if points > 0 {
                items.append(ScoreItem(name: gameText("score.item.opening_seolsa"), points: points, count: nil))
            }
        }

        return items
    }
    
    static func calculatePiCount(cards: [Card], rules: RuleConfig) -> Int {
        let hasCheongdan = hasCompleteCheongdan(in: cards, rules: rules)
        return cards.reduce(0) { total, card in
            total + piValue(for: card, rules: rules, hasCheongdan: hasCheongdan)
        }
    }

    static func piValue(for card: Card, in cards: [Card], rules: RuleConfig) -> Int {
        let hasCheongdan = hasCompleteCheongdan(in: cards, rules: rules)
        return piValue(for: card, rules: rules, hasCheongdan: hasCheongdan)
    }

    private static func hasCompleteCheongdan(in cards: [Card], rules: RuleConfig) -> Bool {
        let danRules = rules.cards.dan
        return cards.filter { $0.type == .ribbon && danRules.cheongdan.contains($0.month.rawValue) }.count == 3
    }

    private static func piValue(for card: Card, rules: RuleConfig, hasCheongdan: Bool) -> Int {
        if let role = card.selectedRole {
            if role == .doublePi {
                return 2
            }
            if role == .animal {
                return 0
            }
        }

        if card.type == .doubleJunk {
            return 2
        }

        if card.type == .junk {
            var currentValue = 1
            for condRule in rules.cards.pi.conditional_double_pi ?? [] {
                if card.month.rawValue == condRule.month,
                   condRule.condition == "has_cheongdan",
                   hasCheongdan {
                    currentValue += condRule.bonus_points
                }
            }
            return currentValue
        }

        if card.month == .sep && card.type == .animal {
            let defaultRole = rules.cards.chrysanthemum_rule.default_role
            if defaultRole == "double_pi" {
                return 2
            }
        }

        return 0
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
