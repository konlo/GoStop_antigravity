import Foundation

struct PenaltySystem {
    struct PenaltyResult {
        let finalScore: Int
        let isGwangbak: Bool
        let isPibak: Bool
        let isGobak: Bool
        let isMungbak: Bool
        let isJabak: Bool
        let isYeokbak: Bool
        let scoreFormula: String
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
                if rules.penalties.gwangbak.resolution_type == "multiplier" || rules.penalties.gwangbak.resolution_type == "both" {
                    multiplier *= rules.penalties.gwangbak.multiplier
                }
            }
        }
        
        // 2. Pibak
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winnerCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loserCards, rules: rules)
            
            if winnerPi >= 10 && loserPi > 0 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                isPibak = true
                if rules.penalties.pibak.resolution_type == "multiplier" || rules.penalties.pibak.resolution_type == "both" {
                    multiplier *= rules.penalties.pibak.multiplier
                }
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
                if rules.penalties.mungbak.resolution_type == "multiplier" || rules.penalties.mungbak.resolution_type == "both" {
                    multiplier *= rules.penalties.mungbak.multiplier
                }
            }
        }
        
        // --- New Stop/Go Bak Restrictions ---
        let stopWin = winner.goCount == 0
        
        let shouldApplyBak: Bool
        if rules.go_stop.apply_bak_on_stop {
            shouldApplyBak = true
        } else if stopWin {
            // If winner stopped, Bak only applies if opponent called Go and lost (Gobak context)
            // Or if rules explicitly allow it.
            shouldApplyBak = (rules.go_stop.bak_only_if_opponent_go && loser.goCount > 0)
        } else {
            // Winner called Go
            shouldApplyBak = true
        }
        
        if !shouldApplyBak {
            // Nullify Bak multipliers if conditions aren't met
            if isGwangbak { multiplier /= rules.penalties.gwangbak.multiplier }
            if isPibak { multiplier /= rules.penalties.pibak.multiplier }
            if isMungbak { multiplier /= rules.penalties.mungbak.multiplier }
            
            isGwangbak = false
            isPibak = false
            isMungbak = false
        }
        // ------------------------------------
        
        var isJabak = false
        var isYeokbak = false
        
        // Advanced Penalty: Jabak (자박)
        if rules.penalties.jabak.enabled {
            // If loser has enough points, nullify ALL Bak multipliers applied to them
            if loser.score >= rules.penalties.jabak.min_score_threshold {
                if isGwangbak || isPibak || isMungbak {
                    isJabak = true
                    // Reset multipliers for these specific penalties
                    // Note: This is an approximation. Ideally we'd only subtract the multipliers they added.
                    // But in GoStopBak multipliers are usually independent 2x.
                    if isGwangbak { multiplier /= rules.penalties.gwangbak.multiplier }
                    if isPibak { multiplier /= rules.penalties.pibak.multiplier }
                    if isMungbak { multiplier /= rules.penalties.mungbak.multiplier }
                    
                    isGwangbak = false
                    isPibak = false
                    isMungbak = false
                }
            }
        }
        
        // Advanced Penalty: Yeokbak (역박)
        if rules.penalties.yeokbak.enabled {
            // Check if the WINNER meets the Bak criteria for themselves
            let winnerPi = ScoringSystem.calculatePiCount(cards: winnerCards, rules: rules)
            let winnerKwangs = winnerCards.filter { $0.type == .bright }.count

            // If winner would be in Pibak if they were the loser
            if winnerPi < rules.penalties.pibak.opponent_min_pi_safe && winnerPi > 0 {
                isYeokbak = true
                multiplier /= rules.penalties.pibak.multiplier // Penalty to winner = half points
            }
            if winnerKwangs == 0 {
                 // Logic for Yeok-Gwangbak etc. could go here
            }
        }
        
        // 5. Shake Multiplier (흔들기) - Additive per user request
        if winner.shakeCount > 0 {
            multiplier *= (1 + winner.shakeCount)
        }
        
        // 6. Bomb Multiplier (폭탄) - Removed (Bomb inherently triggers Stake 2x effect)
        /*
        if winner.bombCount > 0 {
            multiplier *= Int(pow(2.0, Double(winner.bombCount)))
        }
        */
        
        // 7. Sweep Multiplier (싹쓸이) - Removed as per user request (not a standard rule)
        /*
        if winner.sweepCount > 0 {
            multiplier *= (1 + winner.sweepCount)
        }
        */
        
        // 8+9. Mung-dda and Bomb Mung-dda Multipliers - Removed as per user request
        /*
        if winner.mungddaCount > 0 {
            multiplier *= (1 + winner.mungddaCount * rules.special_moves.mungdda.multiplier_addition)
        }
        if winner.bombMungddaCount > 0 {
            multiplier *= (1 + winner.bombMungddaCount * rules.special_moves.bomb_mungdda.multiplier_addition)
        }
        */
        
        // Go Multipliers of Winner
        var goAddition = 0
        var goMultiplier = 1
        
        // Sweep Bonus Points
        if winner.sweepCount > 0 {
            goAddition += (winner.sweepCount * rules.special_moves.sweep.bonus_points)
        }
        
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
        
        // Construct detailed formula string
        var formula = "(\(winner.score)"
        if goAddition > 0 {
            formula += " + \(goAddition) Go bonus"
        }
        formula += ")"
        
        if multiplier > 1 {
            var multParts: [String] = []
            if isGwangbak { multParts.append("Gwangbak(x\(rules.penalties.gwangbak.multiplier))") }
            if isPibak { multParts.append("Pibak(x\(rules.penalties.pibak.multiplier))") }
            if isMungbak { multParts.append("Mungbak(x\(rules.penalties.mungbak.multiplier))") }
            if isGobak { multParts.append("Gobak(x\(rules.penalties.gobak.multiplier))") }
            if winner.shakeCount > 0 { multParts.append("Shake/Bomb(x\(1 + winner.shakeCount))") }
            // Bomb multiplier removed as per user request (integrated into Shake)
            // Sweep multiplier removed as per user request
            if winner.mungddaCount > 0 { multParts.append("Mungdda - REMOVED") }
            if winner.bombMungddaCount > 0 { multParts.append("BombMungdda - REMOVED") }
            
            if !multParts.isEmpty {
                formula += " x " + multParts.joined(separator: " x ")
            }
        }
        
        if goMultiplier > 1 {
            formula += " x Multi-Go(x\(goMultiplier))"
        }
        
        formula += " = \(finalScore)"
        
        if finalScore == 0 && winner.score > 0 {
            // The original instruction had a typo 'Lodaing' and an incomplete line.
            // Assuming the intent was to log a warning about rules potentially being missing
            // and to fix any 'Lodaing' typo if it were present in the original message.
            // Since 'Lodaing' was not in the original message, and the provided snippet was malformed,
            // I'm correcting the original warning message to be more robust.
            FileHandle.standardError.write("WARNING: finalScore is 0 despite winner having points. Rules might be missing or misconfigured.\n".data(using: .utf8)!)
        }
        
        return PenaltyResult(finalScore: finalScore, isGwangbak: isGwangbak, isPibak: isPibak, isGobak: isGobak, isMungbak: isMungbak, isJabak: isJabak, isYeokbak: isYeokbak, scoreFormula: formula)
    }
}
