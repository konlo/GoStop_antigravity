import Foundation

struct PenaltySystem {
    struct PenaltyResult {
        let finalScore: Int
        let isGwangbak: Bool
        let isPibak: Bool
        let isGobak: Bool
        let isMungbak: Bool
    }
    
    static func calculatePenalties(winner: Player, loser: Player, rules: RuleConfig) -> PenaltyResult {
        var multiplier = 1
        var isGwangbak = false
        var isPibak = false
        var isGobak = false
        var isMungbak = false
        
        let winnerCards = winner.capturedCards
        let loserCards = loser.capturedCards
        
        // 1. Gwangbak
        if rules.penalties.gwangbak.enabled {
            let winnerKwangs = winnerCards.filter { $0.type == .bright }.count
            let loserKwangs = loserCards.filter { $0.type == .bright }.count
            
            if winnerKwangs >= 3 && loserKwangs <= rules.penalties.gwangbak.opponent_max_kwang {
                isGwangbak = true
                multiplier *= rules.penalties.gwangbak.multiplier
            }
        }
        
        // 2. Pibak
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winnerCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loserCards, rules: rules)
            
            if winnerPi >= 10 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                isPibak = true
                multiplier *= rules.penalties.pibak.multiplier
            }
        }
        
        // 3. Gobak
        if rules.penalties.gobak.enabled {
            if loser.goCount > 0 && winner.goCount == 0 {
                isGobak = true
                multiplier *= rules.penalties.gobak.multiplier
            }
        }

        // 4. Mungbak (Animal-bak)
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winnerCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                isMungbak = true
                multiplier *= rules.penalties.mungbak.multiplier
            }
        }
        
        // 5. Shake/Bomb Multiplier (흔듦)
        // Each shake doubles the score
        if winner.shakeCount > 0 {
            multiplier *= Int(pow(2.0, Double(winner.shakeCount)))
        }
        
        // Go Multipliers of Winner
        var goAddition = 0
        var goMultiplier = 1
        
        let goRules = rules.go_stop.go_bonuses
        if let goBonus = goRules[String(winner.goCount)] {
            goAddition = goBonus.add
            goMultiplier = goBonus.multiply
        } else if winner.goCount > 0 {
            let maxGo = goRules.keys.compactMap { Int($0) }.max() ?? 0
            if winner.goCount > maxGo, let maxBonus = goRules[String(maxGo)] {
                goAddition = maxBonus.add
                // Simple logic for unbounded Goes: Double the multiplier for each Go beyond the defined max
                goMultiplier = maxBonus.multiply * Int(pow(2.0, Double(winner.goCount - maxGo)))
            } else if maxGo == 0 {
                // Default fallback if no bonuses mapped
                 goAddition = winner.goCount
            }
        }
        
        let finalScore = (winner.score + goAddition) * multiplier * goMultiplier
        
        return PenaltyResult(finalScore: finalScore, isGwangbak: isGwangbak, isPibak: isPibak, isGobak: isGobak, isMungbak: isMungbak)
    }
}
