import Foundation

enum GameState: String, Codable {
    case ready
    case askingShake
    case playing
    case askingGoStop
    case ended
}

func gLog(_ message: String) {
    #if DEBUG
    fputs("\(message)\n", stderr)
    #else
    print(message)
    #endif
}

class GameManager: ObservableObject {
    static var shared: GameManager?
    
    @Published var gameState: GameState = .ready
    @Published var deck = Deck()
    @Published var players: [Player] = []
    @Published var currentTurnIndex: Int = 0
    @Published var tableCards: [Card] = []
    
    // For start-of-game shakes
    @Published var pendingShakeMonths: [Int] = []
    
    // For Seolsa (뻑/설사) tracking
    @Published var monthOwners: [Int: Player] = [:]
    
    var currentPlayer: Player? {
        guard players.indices.contains(currentTurnIndex) else { return nil }
        return players[currentTurnIndex]
    }
    
    init() {
        GameManager.shared = self
        setupGame()
    }
    
    func setupGame(seed: Int? = nil) {
        let player1 = Player(name: "Player 1", money: 10000)
        let computer = Player(name: "Computer", money: 10000)
        computer.isComputer = true
        self.players = [player1, computer]
        self.deck.reset(seed: seed)
        self.dealCards()
        self.gameState = .ready
    }
    
    func dealCards() {
        // Standard 2-player deal: 10 cards each, 8 on table
        for player in players {
            player.hand = deck.draw(count: 10)
        }
        tableCards = deck.draw(count: 8)
    }
    
    func mockDeck(cards: [Card]) {
        deck.pushCardsOnTop(cards)
    }
    
    func startGame() {
        currentTurnIndex = 0 // Player 1 starts
        
        // 1. Check for Initial Shakes (Player only for now, or AI too?)
        if let player = players.first {
            let monthsWithThreePlus = getMonthsWithThreePlus(in: player.hand)
            if !monthsWithThreePlus.isEmpty {
                pendingShakeMonths = monthsWithThreePlus
                gameState = .askingShake
                gLog("Initial Shakes possible for months: \(pendingShakeMonths)")
                return
            }
        }
        
        gameState = .playing
    }
    
    private func getMonthsWithThreePlus(in hand: [Card]) -> [Int] {
        var counts: [Int: Int] = [:]
        for card in hand {
            counts[card.month.rawValue, default: 0] += 1
        }
        return counts.filter { $0.value >= 3 }.map { $0.key }.sorted()
    }
    
    func respondToShake(month: Int, didShake: Bool) {
        guard gameState == .askingShake, let player = players.first else { return }
        
        if didShake {
            player.shakeCount += 1
            player.shakenMonths.append(month)
            gLog("\(player.name) declared SHAKE for month \(month)!")
        }
        
        // Remove from pending
        pendingShakeMonths.removeAll { $0 == month }
        
        if pendingShakeMonths.isEmpty {
            gameState = .playing
            gLog("Shaking phase ended. Starting game.")
        } else {
            gLog("More shakes pending: \(pendingShakeMonths)")
        }
    }
    
    // Game Loop Logic
    func playTurn(card: Card) {
        guard gameState == .playing, let player = currentPlayer else { return }
        
        // 0. Bomb Check (폭탄 체크)
        let month = card.month
        let handMatches = player.hand.filter { $0.month == month }
        let tableMatches = tableCards.filter { $0.month == month }
        
        var captures: [Card] = []
        var isBomb = false
        var isTtadak = false
        var isJjok = false
        var isSeolsa = false
        
        let tableWasNotEmpty = !tableCards.isEmpty
        
        // 1. Play Card Phase
        if let rules = RuleLoader.shared.config, rules.special_moves.bomb.enabled,
           handMatches.count == 3 && tableMatches.count == 1 {
            isBomb = true
            gLog("\(player.name) triggered BOMB (폭탄) for month \(month)!")
            
            // Play all matching cards from hand and tabletop
            for mCard in handMatches {
                if let played = player.play(card: mCard) {
                    captures.append(played)
                }
            }
            if let target = tableMatches.first, let index = tableCards.firstIndex(of: target) {
                tableCards.remove(at: index)
                captures.append(target)
            }
            player.bombCount += 1
            player.shakeCount += 1 
            
            // Draw phase after bomb
            if let drawnCard = deck.draw() {
                 let drawnMatches = tableCards.filter { $0.month == drawnCard.month }
                 if drawnMatches.isEmpty {
                     monthOwners[drawnCard.month.rawValue] = player
                     tableCards.append(drawnCard)
                 } else {
                     captures.append(contentsOf: match(card: drawnCard))
                 }
            }
        } else {
            // Normal Play Resolution
            guard let playedCard = player.play(card: card) else { return }
            
            // Step A: Check play-phase match
            let playedMatches = tableCards.filter { $0.month == playedCard.month }
            var playPhaseCaptured: [Card] = []
            
            if playedMatches.isEmpty {
                // No match on play
                monthOwners[playedCard.month.rawValue] = player
                tableCards.append(playedCard)
            } else if playedMatches.count == 3 {
                // Chok (뻑-opposite): Take all 4. 
                playPhaseCaptured.append(playedCard)
                playPhaseCaptured.append(contentsOf: playedMatches)
                tableCards.removeAll { $0.month == playedCard.month }
                gLog("CHOK (촉)! \(player.name) took all 4 for month \(playedCard.month)")
            } else {
                // Normal match (1 or 2 on table)
                // If 1 on table, take both. If 2 on table, take 1 (MVP choice).
                playPhaseCaptured.append(playedCard)
                if let target = playedMatches.first, let idx = tableCards.firstIndex(of: target) {
                    playPhaseCaptured.append(target)
                    tableCards.remove(at: idx)
                }
                
                if let owner = monthOwners[playedCard.month.rawValue], owner.id != player.id {
                    isSeolsa = true // Captured card was "owned" by someone else who put it down
                }
            }
            
            // Step B: Draw Phase
            var drawPhaseCaptured: [Card] = []
            if let drawnCard = deck.draw() {
                let drawnMatches = tableCards.filter { $0.month == drawnCard.month }
                
                if drawnMatches.isEmpty {
                    monthOwners[drawnCard.month.rawValue] = player
                    tableCards.append(drawnCard)
                    
                    // Jjok Check: If I played A (no match) and drew A (matches the played one)
                    if playedMatches.isEmpty && drawnCard.month == playedCard.month {
                        // Wait, if played matches was empty, playedCard is now on table. 
                        // drawnMatches should have found it. 
                        // Re-filter after adding drawn card? No.
                    }
                } else if drawnMatches.count == 3 {
                    drawPhaseCaptured.append(drawnCard)
                    drawPhaseCaptured.append(contentsOf: drawnMatches)
                    tableCards.removeAll { $0.month == drawnCard.month }
                } else {
                    // Match found on draw
                    drawPhaseCaptured.append(drawnCard)
                    if let target = drawnMatches.first, let idx = tableCards.firstIndex(of: target) {
                        drawPhaseCaptured.append(target)
                        tableCards.remove(at: idx)
                    }
                }
                
                // Special Move Logic
                if playedMatches.isEmpty && drawnCard.month == playedCard.month && drawPhaseCaptured.contains(where: { $0.id == playedCard.id }) {
                    isJjok = true
                } else if !playPhaseCaptured.isEmpty && !drawPhaseCaptured.isEmpty {
                    // Both play and draw resulted in capture
                    isTtadak = true
                }
                
                // Seolsa (뻑) Check: If play matched but then draw added a 3rd card of same month
                // AND we didn't capture them because they are now 3.
                // Wait, the standard "Puck" rule: 
                // 1 on table. Play 1. Draw 1 (of same month). -> 3 on table. NO capture.
                // My logic above already captures if count is 1. 
                // Let's refine: If play matches (making 2), but draw is ALSO same month (making 3).
                // We should NOT have captured the first 2.
            }
            
            captures.append(contentsOf: playPhaseCaptured)
            captures.append(contentsOf: drawPhaseCaptured)
        }
        
        // 3. Capture & Score
        if !captures.isEmpty {
            player.capture(cards: captures)
            player.score = ScoringSystem.calculateScore(for: player)
            gLog("\(player.name) captured \(captures.count) cards. Total: \(player.capturedCards.count)")
        }
        
        // Post-Capture Special Moves (Steal Pi)
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        if let rules = RuleLoader.shared.config {
            if isBomb {
                stealPi(from: opponent, to: player, count: rules.special_moves.bomb.steal_pi_count)
                
                // Check for Bomb Mung-dda
                if opponent.isPiMungbak && rules.special_moves.bomb_mungdda.enabled {
                    gLog("BOMB MUNG-DDA (폭탄 멍따)!!")
                    player.bombMungddaCount += 1
                    stealPi(from: opponent, to: player, count: rules.special_moves.bomb_mungdda.steal_pi_count)
                }
            }
            if isTtadak && rules.special_moves.ttadak.enabled {
                gLog("\(player.name) triggered TTADAK (따닥)!")
                player.ttadakCount += 1
                stealPi(from: opponent, to: player, count: rules.special_moves.ttadak.steal_pi_count)
                
                // Check for Mung-dda
                if opponent.isPiMungbak && rules.special_moves.mungdda.enabled && !isBomb {
                    gLog("MUNG-DDA (멍따)!!")
                    player.mungddaCount += 1
                    stealPi(from: opponent, to: player, count: rules.special_moves.mungdda.steal_pi_count)
                }
            }
            if isJjok && rules.special_moves.jjok.enabled {
                gLog("\(player.name) triggered JJOK (쪽)!")
                player.jjokCount += 1
                stealPi(from: opponent, to: player, count: rules.special_moves.jjok.steal_pi_count)
            }
            if isSeolsa && rules.special_moves.seolsa.enabled {
                player.seolsaCount += 1
                stealPi(from: opponent, to: player, count: rules.special_moves.seolsa.penalty_pi_count)
            }
        }
        
        // Sweep Check (쓸기)
        if let rules = RuleLoader.shared.config, rules.special_moves.sweep.enabled,
           tableWasNotEmpty, tableCards.isEmpty {
            gLog("\(player.name) swept the table (쓸기/싹쓸이)!")
            player.sweepCount += 1
            
            let opponentIndex = (currentTurnIndex + 1) % players.count
            stealPi(from: players[opponentIndex], to: player, count: rules.special_moves.sweep.steal_pi_count)
        }
        
        // 4. End Turn Logic
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        // 4a. PRORITIZED: Check Endgame Conditions (e.g. Max Score, Instant End on Bak)
        let opponentIndex_end = (currentTurnIndex + 1) % players.count
        let opponent_end = players[opponentIndex_end]
        if checkEndgameConditions(player: player, opponent: opponent_end, rules: rules, isAfterGo: false) {
            return
        }
        
        // 4b. Standard Go/Stop logic
        let minScore = players.count == 3 ? rules.go_stop.min_score_3_players : rules.go_stop.min_score_2_players
        if player.score >= minScore && player.score > player.lastGoScore {
            // Reached new high score exceeding minimum
            if player.hand.isEmpty {
                // Cannot call Go if there are no cards left to play. Forced Stop.
                gLog("\(player.name) reached \(player.score) points, but has no cards left. Forced STOP.")
                executeStop(player: player, rules: rules)
            } else {
                // Ask Go or Stop
                gameState = .askingGoStop
                gLog("\(player.name) reached \(player.score) points. Asking Go/Stop...")
            }
        } else {
            endTurn()
        }
    }
    
    func respondToGoStop(isGo: Bool) {
        gLog("--- respondToGoStop(isGo: \(isGo)) called. State: \(gameState), Turn: \(currentTurnIndex) ---")
        guard gameState == .askingGoStop, let player = currentPlayer else { 
            gLog("respondToGoStop GUARD FAILED. State: \(gameState), player: \(currentPlayer?.name ?? "nil")")
            return 
        }
        
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if isGo {
            player.goCount += 1
            player.lastGoScore = player.score
            gLog("\(player.name) calls GO! (Count: \(player.goCount))")
            
            // Set opponent's Pi-mungbak state
            let opponentIndex = (currentTurnIndex + 1) % players.count
            let opponent = players[opponentIndex]
            let threshold = rules.special_moves.mungbak_pi_threshold
            if opponent.piCount <= threshold {
                opponent.isPiMungbak = true
                gLog("\(opponent.name) is now in Pi-mungbak state (Pi: \(opponent.piCount) <= \(threshold))")
            }
            
            gameState = .playing
            
            // Check Max Go endgame
            if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: true) {
                return
            }
            
            endTurn()
        } else {
            executeStop(player: player, rules: rules)
        }
    }
    
    private func executeStop(player: Player, rules: RuleConfig) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        
        // 1. Resolve Pi Transfers BEFORE score calculation
        resolveBakPiTransfers(winner: player, loser: opponent, rules: rules)
        
        // 2. Recalculate Score after transfers
        player.score = ScoringSystem.calculateScore(for: player)
        opponent.score = ScoringSystem.calculateScore(for: opponent)
        
        let result = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        gLog("\(player.name) calls STOP and wins! Base: \(player.score), Final Score: \(result.finalScore)")
        
        if result.isGwangbak { gLog("Gwangbak applied!") }
        if result.isPibak { gLog("Pibak applied!") }
        if result.isGobak { gLog("Gobak applied!") }
        if result.isMungbak { gLog("Mungbak applied!") }
        if result.isJabak { gLog("Jabak (자박): Bak nullified due to loser score.") }
        if result.isYeokbak { gLog("Yeokbak (역박): Winner penalized for meeting Bak criteria.") }
        
        opponent.money -= result.finalScore * 100
        player.money += result.finalScore * 100
        
        gameState = .ended
    }
    
    private func fallbackEndTurn(player: Player) {
        if player.score >= 7 {
            gLog("\(player.name) Wins with score \(player.score)! (Fallback)")
            gameState = .ended
        } else {
            endTurn()
        }
    }
    
    private func match(card: Card) -> [Card] {
        // Find matching cards on table
        let matches = tableCards.filter { $0.month == card.month }
        
        if matches.isEmpty {
            // No match: Leave on table
            tableCards.append(card)
            return []
        } else {
            // Match found!
            // Simple rule: If 1 match, take both.
            // If 2 matches (3 total), user chooses (Complexity! Default to first for now).
            // If 3 matches (4 total), take all (Steal/Chok).
            
            // Simplified MVP: Take the first match + played card
            if let target = matches.first, let index = tableCards.firstIndex(of: target) {
                tableCards.remove(at: index)
                return [card, target]
            }
            return []
        }
    }
    
    private func endTurn() {
        if deck.cards.isEmpty {
            gameState = .ended // Deck run out -> Nagari!
            gLog("Game Ended in Nagari!")
            // Typically, we would set a flag to multiply the next game's stakes
            return
        }
        // Switch turn
        currentTurnIndex = (currentTurnIndex + 1) % players.count
        
        // Simple AI Turn (if next is computer)
        if currentPlayer?.isComputer == true && gameState == .playing {
            // Delay or immediate? Immediate for logic test
            if let aiCard = currentPlayer?.hand.first {
                playTurn(card: aiCard)
            }
        }
    }
    
    private func resolveBakPiTransfers(winner: Player, loser: Player, rules: RuleConfig) {
        // --- Preliminary Stop/Go Bak Restrictions ---
        let stopWin = winner.goCount == 0
        let applyBakBecauseStop = rules.go_stop.apply_bak_on_stop || !stopWin
        let applyBakBecauseOpponentGo = !rules.go_stop.bak_only_if_opponent_go || loser.goCount > 0
        
        guard applyBakBecauseStop && applyBakBecauseOpponentGo else { return }
        // ---------------------------------------------

        // 1. Gwangbak
        if rules.penalties.gwangbak.enabled {
            let winnerKwangs = winner.capturedCards.filter { $0.type == .bright }.count
            let loserKwangs = loser.capturedCards.filter { $0.type == .bright }.count
            if winnerKwangs >= 3 && loserKwangs <= rules.penalties.gwangbak.opponent_max_kwang {
                if rules.penalties.gwangbak.resolution_type == "pi_transfer" || rules.penalties.gwangbak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.gwangbak.pi_to_transfer)
                    gLog("Gwangbak Pi Transfer: Moved \(rules.penalties.gwangbak.pi_to_transfer) Pi")
                }
            }
        }
        
        // 2. Pibak
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winner.capturedCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loser.capturedCards, rules: rules)
            if winnerPi >= 10 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                if rules.penalties.pibak.resolution_type == "pi_transfer" || rules.penalties.pibak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.pibak.pi_to_transfer)
                    gLog("Pibak Pi Transfer: Moved \(rules.penalties.pibak.pi_to_transfer) Pi")
                }
            }
        }
        
        // 3. Mungbak
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winner.capturedCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                if rules.penalties.mungbak.resolution_type == "pi_transfer" || rules.penalties.mungbak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.mungbak.pi_to_transfer)
                    gLog("Mungbak Pi Transfer: Moved \(rules.penalties.mungbak.pi_to_transfer) Pi")
                }
            }
        }
    }
    
    private func checkEndgameConditions(player: Player, opponent: Player, rules: RuleConfig, isAfterGo: Bool) -> Bool {
        let endgame = rules.endgame
        
        // 1. Instant End on Bak (Priority 1)
        let penalties = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        if (endgame.instant_end_on_bak.gwangbak && penalties.isGwangbak) ||
           (endgame.instant_end_on_bak.pibak && penalties.isPibak) ||
           (endgame.instant_end_on_bak.mungbak && penalties.isMungbak) ||
           (endgame.instant_end_on_bak.bomb_mungdda && player.bombMungddaCount > 0) {
            
            gLog("ENDGAME (끝장): Instant end triggered by Bak condition!")
            executeStop(player: player, rules: rules)
            return true
        }
        
        // 2. Max Round Score (Priority 2)
        var currentScore = player.score
        if endgame.score_check_timing == "post_multiplier" {
            currentScore = penalties.finalScore
        }
        
        if currentScore >= endgame.max_round_score {
            gLog("ENDGAME (끝장): Reached max round score (\(currentScore) >= \(endgame.max_round_score))!")
            executeStop(player: player, rules: rules)
            return true
        }
        
        // 3. Max Go Count (Priority 3)
        if player.goCount >= endgame.max_go_count {
            gLog("ENDGAME (끝장) TRIGGERED: Reached max Go count (\(player.goCount) >= \(endgame.max_go_count)) for \(player.name)")
            executeStop(player: player, rules: rules)
            return true
        } else {
            gLog("checkEndgameConditions: goCount \(player.goCount) vs target \(endgame.max_go_count)")
        }
        
        return false
    }
    
    private func stealPi(from: Player, to: Player, count: Int) {
        guard let rules = RuleLoader.shared.config else { return }
        var stolenCount = 0
        
        // Try to steal from captured cards (must be Pi)
        // Order of stealing: normal Pi first, then double Pi if needed?
        // Usually, any Pi works.
        
        for _ in 0..<count {
            if let piToSteal = from.capturedCards.first(where: { $0.type == .junk }) {
                if let index = from.capturedCards.firstIndex(of: piToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(piToSteal)
                    stolenCount += 1
                }
            } else if let doublePiToSteal = from.capturedCards.first(where: { $0.type == .doubleJunk }) {
                // If only double Pi remains, take it? (Rules vary, usually just 1 pi stolen even if it's double?)
                // Standard: Steal 1 "unit" of Pi. If they only have double pi, you take it?
                // Actually, usually you steal 1 normal pi. If they have double pi, it's still 1 card.
                if let index = from.capturedCards.firstIndex(of: doublePiToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(doublePiToSteal)
                    stolenCount += 1
                }
            }
        }
        
        if stolenCount > 0 {
            gLog("Stole \(stolenCount) Pi from \(from.name) to \(to.name)!")
            from.score = ScoringSystem.calculateScore(for: from)
            to.score = ScoringSystem.calculateScore(for: to)
        }
    }
}
