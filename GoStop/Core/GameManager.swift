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
    
    // For shake (흔들기) handling
    @Published var pendingShakeMonths: [Int] = []
    var pendingShakeCard: Card? = nil
    var pendingShakeMonth: Int? = nil
    
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
        guard gameState == .askingShake, let player = currentPlayer else { return }
        
        if didShake {
            player.shakeCount += 1
            player.shakenMonths.append(month)
            gLog("\(player.name) declared SHAKE for month \(month)!")
        }
        
        // Remove from pending
        // Always track the month as "answered" so we don't re-prompt on the same playTurn
        if !player.shakenMonths.contains(month) {
            player.shakenMonths.append(month)
        }
        
        pendingShakeMonths.removeAll { $0 == month }
        
        if pendingShakeMonths.isEmpty {
            gameState = .playing
            gLog("Shake phase resolved. Resuming turn.")
            // Resume the turn with the card the player originally tried to play
            if let card = pendingShakeCard {
                pendingShakeCard = nil
                pendingShakeMonth = nil
                playTurn(card: card)
            }
        } else {
            gLog("More shakes pending: \(pendingShakeMonths)")
        }
    }
    
    // Game Loop Logic
    func playTurn(card: Card) {
        guard gameState == .playing, let player = currentPlayer else { 
            gLog("playTurn aborted: gameState \(gameState), player \(currentPlayer?.name ?? "unknown")")
            return 
        }
        gLog("--- playTurn start: \(player.name) plays \(card.month) (\(card.type)). Hand: \(player.hand.count), Table: \(tableCards.count) ---")
        
        // Mid-game shake check: if player has 3 cards of same month and hasn't shaken for this month yet.
        // NOTE: Bomb (폭탄) takes priority: if 3 in hand + 1 on table, skip shake and let bomb fire.
        if card.type != .dummy {
            let sameMonthCount = player.hand.filter { $0.month == card.month }.count
            let tableMatchCount = tableCards.filter { $0.month == card.month }.count
            let alreadyShaken = player.shakenMonths.contains(card.month.rawValue)
            let isBombCondition = sameMonthCount >= 3 && tableMatchCount == 1
            if let rules = RuleLoader.shared.config, rules.special_moves.shake.enabled,
               sameMonthCount >= 3 && !alreadyShaken && !isBombCondition {
                gLog("\(player.name) can SHAKE for month \(card.month)! Asking...")
                pendingShakeCard = card
                pendingShakeMonth = card.month.rawValue
                pendingShakeMonths = [card.month.rawValue]
                gameState = .askingShake
                return
            }
        }
        
        let month = card.month
        let handMatches = player.hand.filter { $0.month == month }
        let tableMatches = tableCards.filter { $0.month == month }
        
        var isBomb = false
        var isTtadak = false
        var isJjok = false
        var isSeolsa = false
        var playedCard: Card? = nil
        var playPhaseCaptured: [Card] = []
        var drawPhaseCaptured: [Card] = []
        
        let tableWasNotEmpty = !tableCards.isEmpty
        
        // Helper to perform a capture on table
        func performTableCapture(for monthCard: Card, on table: inout [Card]) -> [Card] {
            let m = table.filter { $0.month == monthCard.month }
            if m.isEmpty {
                table.append(monthCard)
                return []
            } else if m.count == 3 {
                let allFour = [monthCard] + m
                table.removeAll { $0.month == monthCard.month }
                gLog("CHOK! Captured all 4 of month \(monthCard.month)")
                return allFour
            } else {
                if let target = m.first, let idx = table.firstIndex(of: target) {
                    table.remove(at: idx)
                    return [monthCard, target]
                }
                table.append(monthCard)
                return []
            }
        }
        
        // 1. Play Card Phase
        if let rules = RuleLoader.shared.config, rules.special_moves.bomb.enabled,
           handMatches.count == 3 && tableMatches.count == 1 {
            isBomb = true
            gLog("\(player.name) triggered BOMB (폭탄) for month \(month)!")
            
            for mCard in handMatches {
                if let played = player.play(card: mCard) {
                    playPhaseCaptured.append(played)
                }
            }
            if let target = tableMatches.first, let index = tableCards.firstIndex(of: target) {
                tableCards.remove(at: index)
                playPhaseCaptured.append(target)
            }
            player.bombCount += 1
            player.shakeCount += 1 
            
            for _ in 0..<2 {
                let dummy = Card(month: .none, type: .dummy, imageIndex: 0)
                player.hand.append(dummy)
                player.dummyCardCount += 1
            }
            playedCard = nil
            
            // Draw Phase
            if let drawnCard = deck.draw() {
                gLog("Bomb Draw: \(drawnCard.month) (\(drawnCard.type))")
                drawPhaseCaptured = performTableCapture(for: drawnCard, on: &tableCards)
            }
            
            // Finalize Bomb captures
            let bombCaptures = playPhaseCaptured + drawPhaseCaptured
            if !bombCaptures.isEmpty {
                player.capture(cards: bombCaptures)
                player.score = ScoringSystem.calculateScore(for: player)
                gLog("\(player.name) captured \(bombCaptures.count) cards via BOMB. Total: \(player.capturedCards.count)")
                // Clear to prevent double processing later
                playPhaseCaptured = []
                drawPhaseCaptured = []
            }
        } else {
            if card.type == .dummy {
                gLog("\(player.name) played a DUMMY card.")
                player.dummyCardCount -= 1
                if let pCard = player.play(card: card) {
                    tableCards.append(pCard)
                }
            } else {
                if let pCard = player.play(card: card) {
                    playedCard = pCard
                    if let owner = monthOwners[pCard.month.rawValue], owner.id != player.id {
                        isSeolsa = true 
                        gLog("Seolsa (뻑) match check triggered for month \(pCard.month)")
                    }
                    playPhaseCaptured = performTableCapture(for: pCard, on: &tableCards)
                    if playPhaseCaptured.isEmpty {
                        monthOwners[pCard.month.rawValue] = player
                    }
                } else {
                    gLog("ERROR: Card NOT found in hand! Card: \(card.month) \(card.type)")
                    endTurn()
                    return
                }
            }
        }
        
        // 2. Draw Phase
        if !isBomb, let drawnCard = deck.draw() {
            gLog("Drawn: \(drawnCard.month) (\(drawnCard.type))")
            drawPhaseCaptured = performTableCapture(for: drawnCard, on: &tableCards)
            
            if !drawPhaseCaptured.isEmpty {
                if !playPhaseCaptured.isEmpty && !isBomb && card.type != .dummy {
                    isTtadak = true
                }
                if let pCard = playedCard, playPhaseCaptured.isEmpty {
                    if drawPhaseCaptured.contains(where: { $0.id == pCard.id }) {
                        isJjok = true
                    }
                }
            } else {
                monthOwners[drawnCard.month.rawValue] = player
            }
        }
        
        // 3. Capture & Score Consolidation
        let finalCaptures = playPhaseCaptured + drawPhaseCaptured
        
        if !finalCaptures.isEmpty {
            player.capture(cards: finalCaptures)
            player.score = ScoringSystem.calculateScore(for: player)
            gLog("\(player.name) captured \(finalCaptures.count) cards. Total: \(player.capturedCards.count)")
        }
        
        // Post-Capture Special Moves (Steal Pi)
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        if let rules = RuleLoader.shared.config {
            if isBomb {
                stealPi(from: opponent, to: player, count: rules.special_moves.bomb.steal_pi_count)
                if opponent.isPiMungbak && rules.special_moves.bomb_mungdda.enabled {
                    player.bombMungddaCount += 1
                    stealPi(from: opponent, to: player, count: rules.special_moves.bomb_mungdda.steal_pi_count)
                }
            }
            if isTtadak && rules.special_moves.ttadak.enabled {
                player.ttadakCount += 1
                stealPi(from: opponent, to: player, count: rules.special_moves.ttadak.steal_pi_count)
                if opponent.isPiMungbak && rules.special_moves.mungdda.enabled && !isBomb {
                    player.mungddaCount += 1
                    stealPi(from: opponent, to: player, count: rules.special_moves.mungdda.steal_pi_count)
                }
            }
            if isJjok && rules.special_moves.jjok.enabled {
                player.jjokCount += 1
                stealPi(from: opponent, to: player, count: rules.special_moves.jjok.steal_pi_count)
            }
            if isSeolsa && rules.special_moves.seolsa.enabled && !playPhaseCaptured.isEmpty {
                 player.seolsaCount += 1
                 stealPi(from: opponent, to: player, count: rules.special_moves.seolsa.penalty_pi_count)
            }
        }
        
        // Sweep Check (쓸기)
        if let rules = RuleLoader.shared.config, rules.special_moves.sweep.enabled,
           tableWasNotEmpty, tableCards.isEmpty {
            gLog("\(player.name) swept the table (싹쓸이)!")
            player.sweepCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.sweep.steal_pi_count)
        }
        
        // 4. End Turn Logic
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: false) {
            return
        }
        
        let minScore = players.count == 3 ? rules.go_stop.min_score_3_players : rules.go_stop.min_score_2_players
        if player.score >= minScore && player.score > player.lastGoScore {
            if player.hand.count == 0 {
                gLog("\(player.name) reached \(player.score) points, but has no cards left. Forced STOP.")
                executeStop(player: player, rules: rules)
            } else {
                gameState = .askingGoStop
            }
        } else {
            endTurn()
        }
    }
    
    func respondToGoStop(isGo: Bool) {
        gLog("--- respondToGoStop(isGo: \(isGo)) called. State: \(gameState), Turn: \(currentTurnIndex) ---")
        guard gameState == .askingGoStop, let player = currentPlayer else { return }
        
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if isGo {
            player.goCount += 1
            player.lastGoScore = player.score
            gLog("\(player.name) calls GO! (Count: \(player.goCount))")
            
            let opponentIndex = (currentTurnIndex + 1) % players.count
            let opponent = players[opponentIndex]
            let threshold = rules.special_moves.mungbak_pi_threshold
            if opponent.piCount <= threshold {
                opponent.isPiMungbak = true
            }
            
            gameState = .playing
            
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
        
        resolveBakPiTransfers(winner: player, loser: opponent, rules: rules)
        
        player.score = ScoringSystem.calculateScore(for: player)
        opponent.score = ScoringSystem.calculateScore(for: opponent)
        
        let result = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        gLog("\(player.name) calls STOP and wins! Final Score: \(result.finalScore)")
        
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
    
    private func endTurn() {
        if deck.cards.isEmpty {
            gameState = .ended
            gLog("Game Ended in Nagari!")
            return
        }
        currentTurnIndex = (currentTurnIndex + 1) % players.count
        
        if currentPlayer?.isComputer == true && gameState == .playing {
            if let aiCard = currentPlayer?.hand.first {
                playTurn(card: aiCard)
                // If playTurn triggered a shake prompt, AI auto-responds: always shake (beneficial)
                if gameState == .askingShake, let month = pendingShakeMonth {
                    gLog("AI auto-responds to shake for month \(month): YES")
                    respondToShake(month: month, didShake: true)
                }
            }
        }
    }
    
    private func resolveBakPiTransfers(winner: Player, loser: Player, rules: RuleConfig) {
        let stopWin = winner.goCount == 0
        let applyBakBecauseStop = rules.go_stop.apply_bak_on_stop || !stopWin
        let applyBakBecauseOpponentGo = !rules.go_stop.bak_only_if_opponent_go || loser.goCount > 0
        
        guard applyBakBecauseStop && applyBakBecauseOpponentGo else { return }

        if rules.penalties.gwangbak.enabled {
            let winnerKwangs = winner.capturedCards.filter { $0.type == .bright }.count
            let loserKwangs = loser.capturedCards.filter { $0.type == .bright }.count
            if winnerKwangs >= 3 && loserKwangs <= rules.penalties.gwangbak.opponent_max_kwang {
                if rules.penalties.gwangbak.resolution_type == "pi_transfer" || rules.penalties.gwangbak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.gwangbak.pi_to_transfer)
                }
            }
        }
        
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winner.capturedCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loser.capturedCards, rules: rules)
            if winnerPi >= 10 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                if rules.penalties.pibak.resolution_type == "pi_transfer" || rules.penalties.pibak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.pibak.pi_to_transfer)
                }
            }
        }
        
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winner.capturedCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                if rules.penalties.mungbak.resolution_type == "pi_transfer" || rules.penalties.mungbak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.mungbak.pi_to_transfer)
                }
            }
        }
    }
    
    private func checkEndgameConditions(player: Player, opponent: Player, rules: RuleConfig, isAfterGo: Bool) -> Bool {
        let endgame = rules.endgame
        let penalties = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        
        if (endgame.instant_end_on_bak.gwangbak && penalties.isGwangbak) ||
           (endgame.instant_end_on_bak.pibak && penalties.isPibak) ||
           (endgame.instant_end_on_bak.mungbak && penalties.isMungbak) ||
           (endgame.instant_end_on_bak.bomb_mungdda && player.bombMungddaCount > 0) {
            executeStop(player: player, rules: rules)
            return true
        }
        
        var currentScore = player.score
        if endgame.score_check_timing == "post_multiplier" {
            currentScore = penalties.finalScore
        }
        
        if currentScore >= endgame.max_round_score {
            executeStop(player: player, rules: rules)
            return true
        }
        
        if player.goCount >= endgame.max_go_count {
            executeStop(player: player, rules: rules)
            return true
        }
        
        return false
    }
    
    private func stealPi(from: Player, to: Player, count: Int) {
        guard RuleLoader.shared.config != nil else { return }
        var stolenCount = 0
        for _ in 0..<count {
            if let piToSteal = from.capturedCards.first(where: { $0.type == .junk }) {
                if let index = from.capturedCards.firstIndex(of: piToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(piToSteal)
                    stolenCount += 1
                }
            } else if let doublePiToSteal = from.capturedCards.first(where: { $0.type == .doubleJunk }) {
                if let index = from.capturedCards.firstIndex(of: doublePiToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(doublePiToSteal)
                    stolenCount += 1
                }
            }
        }
        if stolenCount > 0 {
            from.score = ScoringSystem.calculateScore(for: from)
            to.score = ScoringSystem.calculateScore(for: to)
        }
    }
}
