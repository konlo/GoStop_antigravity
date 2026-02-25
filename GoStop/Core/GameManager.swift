import Foundation

enum GameState: String, Codable {
    case ready
    case askingShake
    case playing
    case askingGoStop
    case choosingCapture  // Waiting for player to pick which table card to capture (junk vs doubleJunk)
    case choosingChrysanthemumRole // Waiting for player to decide if Sep Animal is Animal or Double Pi
    case ended
}

enum GameEndReason: String, Codable {
    case stop
    case maxScore
    case nagari
    case chongtong
}


func gLog(_ message: String) {
    #if DEBUG
    fputs("\(message)\n", stderr)
    #else
    print(message)
    #endif
    
    // Also record to event logs for AI/Simulator inspection
    GameManager.shared?.addEvent(message)
}

class GameManager: ObservableObject {
    static var shared: GameManager?
    
    @Published var gameState: GameState = .ready
    @Published var deck = Deck()
    @Published var players: [Player] = []
    @Published var currentTurnIndex: Int = 0
    @Published var tableCards: [Card] = []
    @Published var outOfPlayCards: [Card] = []
    
    // For shake (흔들기) handling
    @Published var pendingShakeMonths: [Int] = []
    var pendingShakeCard: Card? = nil
    var pendingShakeMonth: Int? = nil
    
    // For Seolsa (뻑/설사) tracking
    @Published var monthOwners: [Int: Player] = [:]
    @Published var seolsaMonths: [Int: Player] = [:] // Tracks which months are in a "뻑" state and who made it
    
    // For capture card selection (테이블 2장 중 선택)
    @Published var pendingCapturePlayedCard: Card? = nil
    @Published var pendingCaptureDrawnCard: Card? = nil
    @Published var pendingCaptureOptions: [Card] = []
    
    // For September Chrysanthemum (국화) choice
    @Published var pendingChrysanthemumCard: Card? = nil
    
    // Captured flags for current turn processing
    private var isSeolsaEatFlag = false
    private var isSelfSeolsaEatFlag = false
    
    // Turn State (persists across pauses like choosingCapture or choosingChrysanthemumRole)
    private var turnIsBomb = false
    private var turnIsTtadak = false
    private var turnIsJjok = false
    private var turnIsSeolsa = false
    private var turnPlayPhaseCaptured: [Card] = []
    private var turnDrawPhaseCaptured: [Card] = []
    private var turnPlayedCard: Card? = nil
    private var turnTableWasNotEmpty = false
    
    // Endgame state tracking
    @Published var gameEndReason: GameEndReason?
    @Published var lastPenaltyResult: PenaltySystem.PenaltyResult?
    @Published var gameWinner: Player?
    @Published var gameLoser: Player?
    
    // Chongtong state
    @Published var chongtongMonth: Int? = nil
    @Published var chongtongTiming: String? = nil // "initial" or "midgame"
    
    // Event Logs for inspection
    @Published var eventLogs: [String] = []
    
    var currentPlayer: Player? {
        guard players.indices.contains(currentTurnIndex) else { return nil }
        return players[currentTurnIndex]
    }
    
    init() {
        GameManager.shared = self
        setupGame()
    }
    
    func addEvent(_ message: String) {
        self.eventLogs.append(message)
        if self.eventLogs.count > 100 {
            self.eventLogs.removeFirst()
        }
    }
    
    func setupGame(seed: Int? = nil) {
        let player1 = Player(name: "Player 1", money: 10000)
        let computer = Player(name: "Computer", money: 10000)
        computer.isComputer = true
        self.players = [player1, computer]
        self.outOfPlayCards = []
        self.gameEndReason = nil
        self.lastPenaltyResult = nil
        self.gameWinner = nil
        self.gameLoser = nil
        self.chongtongMonth = nil
        self.chongtongTiming = nil
        self.eventLogs = []
        self.deck.reset(seed: seed)
        self.monthOwners = [:]          // ← 이전 게임 뻑 추적 초기화
        self.seolsaMonths = [:]         // ← 뻑 상태 월 초기화
        self.eventLogs = []             // ← 로그 초기화
        self.pendingCapturePlayedCard = nil
        self.pendingCaptureOptions = []
        self.gameState = .ready      // Reset state BEFORE dealing; dealCards may override to .ended if Chongtong
        self.dealCards()
    }
    
    func dealCards() {
        // Standard 2-player deal: 10 cards each, 8 on table
        gLog("Dealing cards: 10 to each player, 8 to table")
        for player in players {
            player.hand = deck.draw(count: 10)
        }
        tableCards = deck.draw(count: 8)
        
        // Initial Table 4-card Nagari check
        var tableMonthCounts: [Int: Int] = [:]
        for card in tableCards {
            tableMonthCounts[card.month.rawValue, default: 0] += 1
        }
        
        if let monthIdx = tableMonthCounts.first(where: { $0.value == 4 })?.key {
            let month = Month(rawValue: monthIdx) ?? .none
            gLog("Initial Table Nagari (4 cards of month \(month)) detected!")
            self.gameState = .ended
            self.gameEndReason = .nagari
            return
        }

        // Initial Chongtong check
        if let rules = RuleLoader.shared.config, rules.special_moves.chongtong.enabled {
            for player in players {
                if let month = getChongtongMonth(for: player) {
                    gLog("Initial Chongtong detected for \(player.name) in month \(month)!")
                    resolveChongtong(player: player, month: month, timing: "initial")
                    return
                }
            }
        }
    }
    
    func mockDeck(cards: [Card]) {
        deck.pushCardsOnTop(cards)
    }
    
    func startGame() {
        if gameState == .ended {
            gLog("Game already ended (e.g. initial Chongtong). Skipping startGame playing state.")
            return
        }
        gLog("Game started. Player 1 turn.")
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
    
    // Chongtong helpers
    func getChongtongMonth(for player: Player) -> Int? {
        var counts: [Int: Int] = [:]
        for card in player.hand {
            if card.month != .none {
                counts[card.month.rawValue, default: 0] += 1
            }
        }
        return counts.filter { $0.value == 4 }.map { $0.key }.first
    }
    
    func resolveChongtong(player: Player, month: Int, timing: String) {
        guard let rules = RuleLoader.shared.config else { return }
        
        self.chongtongMonth = month
        self.chongtongTiming = timing
        self.gameWinner = player
        self.gameLoser = players.first { $0 !== player }
        self.gameEndReason = .chongtong
        
        let score = (timing == "initial") ? 
            rules.special_moves.chongtong.initial_chongtong_score : 
            rules.special_moves.chongtong.midgame_chongtong_score
            
        player.score = score
        // For Chongtong, we skip complex multiplier rules as it's an instant win
        self.lastPenaltyResult = PenaltySystem.PenaltyResult(
            finalScore: score,
            isGwangbak: false,
            isPibak: false,
            isGobak: false,
            isMungbak: false,
            isJabak: false,
            isYeokbak: false,
            scoreFormula: "Chongtong Rule (\(timing)) = \(score)"
        )
        
        self.gameState = .ended
        gLog("Game ended via CHONGTONG! Winner: \(player.name), Score: \(score)")
    }
    
    func respondToShake(month: Int, didShake: Bool) {
        guard gameState == .askingShake, let player = currentPlayer else { return }
        
        if didShake {
            player.shakeCount += 1
            player.shakenMonths.append(month)
            gLog("\(player.name) declared SHAKE for month \(month)!")
        } else {
            // Declined shake – still mark as answered to avoid re-prompting
            if !player.shakenMonths.contains(month) {
                player.shakenMonths.append(month)
            }
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
    
    func respondToChrysanthemumChoice(role: CardRole) {
        guard (gameState == .choosingChrysanthemumRole || (currentPlayer?.isComputer == true && gameState == .playing)),
              let player = currentPlayer,
              let card = pendingChrysanthemumCard else { return }
        
        gLog("\(player.name) chose role \(role.rawValue) for Chrysanthemum card.")
        
        // Finalize capture of the deferred Chrysanthemum card
        player.objectWillChange.send()
        var updatedCard = card
        updatedCard.selectedRole = role
        
        // Formally capture it now
        player.capture(cards: [updatedCard])
        gLog("Successfully captured Chrysanthemum with role \(role.rawValue).")
        
        pendingChrysanthemumCard = nil
        gameState = .playing
        
        // Recalculate score after role change
        player.score = ScoringSystem.calculateScore(for: player)
        
        finalizeTurnAfterCapture(player: player)
    }

    /// Resumes the turn logic after all captures and choices are finalized
    private func finalizeTurnAfterCapture(player: Player) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        // Post-Capture Special Moves (Steal Pi)
        if turnIsBomb {
            stealPi(from: opponent, to: player, count: rules.special_moves.bomb.steal_pi_count, reason: "폭탄(Bomb)")
        }
        if turnIsTtadak && rules.special_moves.ttadak.enabled {
            player.ttadakCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.ttadak.steal_pi_count, reason: "따닥(Ttadak)")
        }
        if turnIsJjok && rules.special_moves.jjok.enabled {
            player.jjokCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.jjok.steal_pi_count, reason: "쪽(Jjok)")
        }
        if turnIsSeolsa && rules.special_moves.seolsa.enabled && turnPlayPhaseCaptured.isEmpty {
             let month = turnPlayedCard?.month.rawValue ?? 0
             player.seolsaCount += 1
             let seolsaPenaltyPi = rules.special_moves.seolsa.penalty_pi_count
             if seolsaPenaltyPi > 0 {
                 stealPi(from: player, to: opponent, count: seolsaPenaltyPi, reason: "뻑(Seolsa) 패널티")
             }
             seolsaMonths[month] = player
        }
        if isSeolsaEatFlag && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.seolsaEat.steal_pi_count, reason: "뻑 먹기(Seolsa Eat)")
        }
        if isSelfSeolsaEatFlag && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.seolsaEat.self_eat_steal_pi_count, reason: "자뻑(Self Seolsa Eat)")
        }
        
        gLog("DEBUG: Sweep Check - enabled: \(rules.special_moves.sweep.enabled), turnTableWasNotEmpty: \(turnTableWasNotEmpty), tableCount: \(tableCards.count), handCount: \(player.hand.count)")
        if !tableCards.isEmpty {
            gLog("DEBUG: Table is NOT empty. Cards: \(tableCards.map { "\($0.month.rawValue)\($0.type.rawValue)" })")
        }
        if rules.special_moves.sweep.enabled, turnTableWasNotEmpty, tableCards.isEmpty, !player.hand.isEmpty {
            gLog("\(player.name) swept the table (싹쓸이)!")
            player.sweepCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.sweep.steal_pi_count, reason: "싹쓸이(Sweep)")
        }
        
        // 4. End Turn Logic
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
    /// Called when the user selects which of the 2 table cards (of same month, different type) to capture.
    func respondToCapture(selectedCard: Card) {
        guard let player = currentPlayer else { return }
        
        let playedCard = pendingCapturePlayedCard
        let drawnCard = pendingCaptureDrawnCard
        
        gLog("\(player.name) chose \(selectedCard.type) for month \(selectedCard.month) capture")
        
        // Remove the chosen card from the table
        if let idx = tableCards.firstIndex(where: { $0.id == selectedCard.id }) {
            tableCards.remove(at: idx)
        }
        
        // Identify which phase we are resuming from
        let triggerCard = playedCard ?? drawnCard
        guard let pCard = triggerCard else {
            gLog("ERROR: respondToCapture called but no trigger card found.")
            return
        }
        
        // Capture: trigger card + chosen table card
        let captured = [pCard, selectedCard]
        // Exclude deferred September card from immediate formal capture
        let finalCaptures = captured.filter { !($0.month == .sep && $0.type == .animal) }
        if !finalCaptures.isEmpty {
            player.capture(cards: finalCaptures)
        }
        
        player.score = ScoringSystem.calculateScore(for: player)
        monthOwners.removeValue(forKey: selectedCard.month.rawValue)
        
        // Track for turn state (so Chrysanthemum role selection and other turn-end checks work)
        if playedCard != nil {
            turnPlayPhaseCaptured = captured
        } else if drawnCard != nil {
            turnDrawPhaseCaptured = captured
        }
        
        gLog("\(player.name) captured \(captured.count) cards (choice). Total: \(player.capturedCards.count)")
        
        // Clear pending states
        pendingCapturePlayedCard = nil
        pendingCaptureDrawnCard = nil
        pendingCaptureOptions = []
        gameState = .playing
        
        guard let rules = RuleLoader.shared.config else {
            endTurn()
            return
        }

        // If this was a PLAY choice, we MUST continue to the DRAW phase
        if playedCard != nil {
            if let drawn = deck.draw() {
                gLog("Drawn after play-choice: \(drawn.month) (\(drawn.type))")
                
                // Seolsa (뻑) creation check:
                // If drawn matches the capture, but ANOTHER card of same month is on table, it's Ttadak (4 cards total).
                // If NO card of same month is on table, it's Seolsa (3 cards total).
                let remainingOnTable = tableCards.first(where: { $0.month == drawn.month })
                
                if captured[0].month == drawn.month && remainingOnTable == nil {
                    turnIsSeolsa = true
                    gLog("SEOLSA (뻑) via choice! Play match followed by draw match for month \(drawn.month)")
                    
                    // VOID the capture: put them back on table, plus the drawn card
                    tableCards.append(contentsOf: captured)
                    tableCards.append(drawn)
                    player.capturedCards.removeAll { c in finalCaptures.contains(where: { $0.id == c.id }) }
                    turnPlayPhaseCaptured = []
                } else {
                    if let dCaptured = performTableCapture(for: drawn, on: &tableCards, player: player) {
                        turnDrawPhaseCaptured = dCaptured
                        if !turnDrawPhaseCaptured.isEmpty {
                            // Defer September card capture
                            let finalDCaptures = turnDrawPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
                            if !finalDCaptures.isEmpty {
                                player.capture(cards: finalDCaptures)
                            }
                            if turnDrawPhaseCaptured.contains(where: { $0.month == pCard.month }) {
                                // Ttadak and Jjok are mutually exclusive:
                                // - Ttadak: play phase captured same-month card(s), then draw phase captures same month again
                                // - Jjok: play phase captured nothing, then draw phase captures the played card back
                                if !turnPlayPhaseCaptured.isEmpty {
                                    turnIsTtadak = true
                                } else {
                                    turnIsJjok = true
                                }
                            }
                            for c in turnDrawPhaseCaptured {
                                monthOwners.removeValue(forKey: c.month.rawValue)
                                seolsaMonths.removeValue(forKey: c.month.rawValue)
                            }
                        } else {
                            monthOwners[drawn.month.rawValue] = player
                        }
                    } else {
                        // Choice needed for Draw Phase too!
                        gLog("Secondary choice needed for Draw Phase!")
                        pendingCaptureDrawnCard = drawn
                        pendingCaptureOptions = tableCards.filter { $0.month == drawn.month }
                        gameState = .choosingCapture
                        player.score = ScoringSystem.calculateScore(for: player)
                        return // Wait again
                    }
                }
            }
        }
        
        // Final Chrysanthemum Check for the whole turn's new captures
        let allNewCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
        if checkAndHandleChrysanthemumRole(capturedCards: allNewCaptures, player: player, rules: rules) {
            return // PAUSE - finalizeTurnAfterCapture will be called from respondToChrysanthemumChoice
        }

        finalizeTurnAfterCapture(player: player)
    }

    
    func playTurn(card: Card) {
        guard let rules = RuleLoader.shared.config else {
            gLog("CRITICAL: playTurn aborted - RuleConfig is nil. Check rule.yaml loading.")
            return
        }
        guard gameState == .playing, let player = currentPlayer else { 
            gLog("playTurn aborted: gameState \(gameState), player \(currentPlayer?.name ?? "unknown")")
            return 
        }
        gLog("--- playTurn start (v2026.02.23_2155): \(player.name) plays \(card.month) (\(card.type)). Hand: \(player.hand.count), Table: \(tableCards.count) ---")
        
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
        
        // Reset Turn State
        turnIsBomb = false
        turnIsTtadak = false
        turnIsJjok = false
        turnIsSeolsa = false
        turnPlayPhaseCaptured = []
        turnDrawPhaseCaptured = []
        turnPlayedCard = nil
        turnTableWasNotEmpty = !tableCards.isEmpty
        gLog("DEBUG: turnTableWasNotEmpty set to \(turnTableWasNotEmpty). Table count: \(tableCards.count)")
        
        // Helper: does the play phase need player capture choice?
        func needsCaptureChoice(for monthCard: Card, in table: [Card]) -> Bool {
            let m = table.filter { $0.month == monthCard.month }
            return m.count == 2 && m[0].type != m[1].type
        }

        // Reset flags
        isSeolsaEatFlag = false
        isSelfSeolsaEatFlag = false

        
        // 1. Play Card Phase
        if let rules = RuleLoader.shared.config, rules.special_moves.bomb.enabled,
           handMatches.count == 3 && tableMatches.count == 1 {
            turnIsBomb = true
            gLog("\(player.name) triggered BOMB (폭탄) for month \(month)!")
            
            for mCard in handMatches {
                if let played = player.play(card: mCard) {
                    turnPlayPhaseCaptured.append(played)
                }
            }
            if let target = tableMatches.first, let index = tableCards.firstIndex(of: target) {
                tableCards.remove(at: index)
                turnPlayPhaseCaptured.append(target)
            }
            player.bombCount += 1
            player.shakeCount += 1
            
            // Add dummy (도탄) cards as defined by rule:
            // dummy_card_count from rule.yaml, dummy_cards_disappear_on_play = true (never go to table)
            let dummyCount = rules.special_moves.bomb.dummy_card_count
            for _ in 0..<dummyCount {
                let dummy = Card(month: .none, type: .dummy, imageIndex: 0)
                player.hand.append(dummy)
                player.dummyCardCount += 1
            }
            gLog("\(player.name) received \(dummyCount) dummy (도탄) card(s). They vanish when played.")
            turnPlayedCard = nil
            
            // Draw Phase
            if let drawnCard = deck.draw() {
                gLog("Bomb Draw: \(drawnCard.month) (\(drawnCard.type))")
                
                // CRITICAL FIX: If drawn card matches bomb month, it MUST be captured even if table is empty.
                // performTableCapture would normally just put it on the table if it's empty.
                if drawnCard.month.rawValue == month.rawValue {
                     turnDrawPhaseCaptured = [drawnCard]
                     gLog("Bomb Draw capture: month \(drawnCard.month.rawValue) matched bomb month \(month.rawValue). Captured.")
                } else if let captured = performTableCapture(for: drawnCard, on: &tableCards, player: player) {
                    turnDrawPhaseCaptured = captured
                } else {
                    // Human choice needed during Bomb draw
                    let options = tableCards.filter { $0.month == drawnCard.month }
                    gLog("Player must choose which card to capture for BOMB drawn month \(drawnCard.month). Options: \(options.map { $0.type })")
                    pendingCaptureDrawnCard = drawnCard
                    pendingCaptureOptions = options
                    gameState = .choosingCapture
                    
                    // Capture turnPlayPhaseCaptured cards (bomb cards + table match) before pausing
                    if !turnPlayPhaseCaptured.isEmpty {
                        let finalPlayCaptures = turnPlayPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
                        if !finalPlayCaptures.isEmpty {
                            player.capture(cards: finalPlayCaptures)
                        }
                        player.score = ScoringSystem.calculateScore(for: player)
                        gLog("\(player.name) captured \(finalPlayCaptures.count) (bomb play phase) before pausing for bomb draw choice.")
                    }
                    return // Pause
                }
            }
            
            // Finalize Bomb captures (Deferred September check)
            let bombCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
            if !bombCaptures.isEmpty {
                let finalBCaptures = bombCaptures.filter { !($0.month == .sep && $0.type == .animal) }
                if !finalBCaptures.isEmpty {
                    player.capture(cards: finalBCaptures)
                }
                player.score = ScoringSystem.calculateScore(for: player)
                gLog("\(player.name) captured \(finalBCaptures.count) cards via BOMB. Total: \(player.capturedCards.count)")
                
                if checkAndHandleChrysanthemumRole(capturedCards: bombCaptures, player: player, rules: rules) {
                    return 
                }
                
                finalizeTurnAfterCapture(player: player)
                return
            }
        } else {
            if card.type == .dummy {
                gLog("\(player.name) played a DUMMY card. (\(player.dummyCardCount - 1) remaining)")
                player.dummyCardCount -= 1
                // Per rule: dummy_cards_disappear_on_play = true
                // Dummy (도탄) cards vanish on play — they are NOT placed on the table/floor
                if let idx = player.hand.firstIndex(where: { $0.id == card.id }) {
                    player.hand.remove(at: idx)
                }
                gLog("\(player.name) dummy play complete. Hand: \(player.hand.count)")
                // Continue to draw phase
                turnPlayedCard = nil 
            } else {
                if let pCard = player.play(card: card) {
                    turnPlayedCard = pCard
                    if let owner = monthOwners[pCard.month.rawValue], owner.id != player.id {
                        // This identifies a candidate for Seolsa (following someone else's card)
                        gLog("Seolsa candidate: \(player.name) may follow \(owner.name)'s missed card for month \(pCard.month)")
                    }
                    
                    if let captured = performTableCapture(for: pCard, on: &tableCards, player: player) {
                        turnPlayPhaseCaptured = captured
                        if turnPlayPhaseCaptured.isEmpty {
                            // Card went to table (no capture) – record who left it there
                            monthOwners[pCard.month.rawValue] = player
                        } else {
                            // Capture happened – clear the monthOwners chain for this month
                            monthOwners.removeValue(forKey: pCard.month.rawValue)
                        }
                    } else if let pCard = turnPlayedCard {
                        // Human player must choose - pause turn
                        let options = tableCards.filter { $0.month == pCard.month }
                        gLog("Player must choose which card to capture for month \(pCard.month). Options: \(options.map { $0.type })")
                        pendingCapturePlayedCard = pCard
                        pendingCaptureOptions = options
                        gameState = .choosingCapture
                        return  // Pause - will resume via respondToCapture()
                    }
                }
                else {
                    gLog("ERROR: Card NOT found in hand! Card: \(card.month) \(card.type)")
                    endTurn()
                    return
                }
            }
        }
        
        // 2. Draw Phase (skip for bomb - it already drew; skip for dummy - no draw)
        if !turnIsBomb, card.type != .dummy, let drawnCard = deck.draw() {
            gLog("Drawn: \(drawnCard.month) (\(drawnCard.type))")
            
            // Seolsa (뻑) creation check:
            // Condition: play phase captured 2 cards (matched 1 on floor), and drawn card is same month.
            // Check table for 4th card (Ttadak case)
            let remainingOnTable = tableCards.first(where: { $0.month == drawnCard.month })

            if !turnPlayPhaseCaptured.isEmpty && turnPlayPhaseCaptured.count == 2 && 
               turnPlayPhaseCaptured[0].month == drawnCard.month && remainingOnTable == nil {
                turnIsSeolsa = true
                gLog("SEOLSA (뻑)! Play match followed by draw match for month \(drawnCard.month)")
                
                // VOID the play capture: put them back on table, plus the drawn card
                tableCards.append(contentsOf: turnPlayPhaseCaptured)
                tableCards.append(drawnCard)
                turnPlayPhaseCaptured = []
                turnDrawPhaseCaptured = []
            } else {
                if let captured = performTableCapture(for: drawnCard, on: &tableCards, player: player) {
                    turnDrawPhaseCaptured = captured
                    if !turnDrawPhaseCaptured.isEmpty {
                        if let pCard = turnPlayedCard,
                           turnDrawPhaseCaptured.contains(where: { $0.month == pCard.month }) {
                            // Ttadak and Jjok are mutually exclusive.
                            if !turnPlayPhaseCaptured.isEmpty {
                                turnIsTtadak = true
                            } else {
                                turnIsJjok = true
                            }
                        }
                        // Clear monthOwners/seolsaMonths for draw-phase captured months
                        for captured in turnDrawPhaseCaptured {
                            monthOwners.removeValue(forKey: captured.month.rawValue)
                            seolsaMonths.removeValue(forKey: captured.month.rawValue)
                        }
                    } else {
                        monthOwners[drawnCard.month.rawValue] = player
                    }
                } else {
                    // Human player must choose for DRAW phase - pause turn
                    let options = tableCards.filter { $0.month == drawnCard.month }
                    gLog("Player must choose which card to capture for drawn month \(drawnCard.month). Options: \(options.map { $0.type })")
                    pendingCaptureDrawnCard = drawnCard
                    pendingCaptureOptions = options
                    gameState = .choosingCapture
                    
                    // We must capture the turnPlayPhaseCaptured cards now before pausing
                    if !turnPlayPhaseCaptured.isEmpty {
                        let finalPlayCaptures = turnPlayPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
                        if !finalPlayCaptures.isEmpty {
                            player.capture(cards: finalPlayCaptures)
                        }
                        player.score = ScoringSystem.calculateScore(for: player)
                        gLog("\(player.name) captured \(finalPlayCaptures.count) (play phase) before pausing for draw choice.")
                    }
                    return // Pause - will resume via respondToCapture()
                }
            }
        }
        
        // 3. Capture & Score Consolidation
        let finalCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
        
        if !finalCaptures.isEmpty {
            // Exclude deferred September card from immediate formal capture
            let finalCapturesToProcess = finalCaptures.filter { !($0.month == .sep && $0.type == .animal) }
            if !finalCapturesToProcess.isEmpty {
                player.capture(cards: finalCapturesToProcess)
            }
            
            player.score = ScoringSystem.calculateScore(for: player)
            gLog("\(player.name) captured \(finalCapturesToProcess.count) cards. Total: \(player.capturedCards.count)")
            
            // September Chrysanthemum Choice Check
            if checkAndHandleChrysanthemumRole(capturedCards: finalCaptures, player: player, rules: rules) {
                return // PAUSE - finalizeTurnAfterCapture will be called from respondToChrysanthemumChoice
            }
        }
        finalizeTurnAfterCapture(player: player)
    }

    private func checkAndHandleChrysanthemumRole(capturedCards: [Card], player: Player, rules: RuleConfig) -> Bool {
        let chrysRule = rules.cards.chrysanthemum_rule
        if chrysRule.enabled, chrysRule.choice_timing == "capture_time" {
            if let chrysCard = capturedCards.first(where: { $0.month == .sep && $0.type == .animal }) {
                if player.isComputer {
                    let defaultRole = CardRole(rawValue: chrysRule.default_role) ?? .animal
                    gLog("Computer auto-selecting default role \(defaultRole) for Chrysanthemum.")
                    
                    var updatedCard = chrysCard
                    updatedCard.selectedRole = defaultRole
                    player.capture(cards: [updatedCard])
                    
                    player.score = ScoringSystem.calculateScore(for: player)
                } else {
                    gLog("Pausing turn for Chrysanthemum role selection.")
                    pendingChrysanthemumCard = chrysCard
                    gameState = .choosingChrysanthemumRole
                    return true // PAUSED
                }
            }
        }
        return false
    }

    func respondGoStop(isGo: Bool) {
        guard let rules = RuleLoader.shared.config,
              let player = currentPlayer else { return }
        
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        
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
            // isPiMungbak tracking removed as part of Mungdda rule removal
            
            gameState = .playing
            
            if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: true) {
                return
            }
            
            endTurn()
        } else {
            executeStop(player: player, rules: rules)
        }
    }
    
    private func executeStop(player: Player, rules: RuleConfig, reason: GameEndReason = .stop) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        
        resolveBakPiTransfers(winner: player, loser: opponent, rules: rules)
        
        player.score = ScoringSystem.calculateScore(for: player)
        opponent.score = ScoringSystem.calculateScore(for: opponent)
        
        let result = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        gLog("\(player.name) calls STOP (\(reason)) and wins! Final Score: \(result.finalScore)")
        
        opponent.money -= result.finalScore * 100
        player.money += result.finalScore * 100

        self.gameEndReason = reason
        self.lastPenaltyResult = result
        self.gameWinner = player
        self.gameLoser = opponent
        
        settleResidualCardsIfHandsEmpty()
        gameState = .ended
    }
    
    private func fallbackEndTurn(player: Player) {
        if player.score >= 7 {
            gLog("\(player.name) Wins with score \(player.score)! (Fallback)")
            self.gameEndReason = .stop
            self.gameWinner = player
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
        } else {
            endTurn()
        }
    }
    
    private func endTurn() {
        for p in players {
            gLog("DEBUG: \(p.name) hand: \(p.hand.count)")
        }
        let allHandsEmpty = players.allSatisfy { $0.hand.isEmpty }
        if deck.cards.isEmpty || allHandsEmpty {
            self.gameEndReason = .nagari
            // Populate lastPenaltyResult for Nagari so summary can be shown
            self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                finalScore: 0,
                isGwangbak: false,
                isPibak: false,
                isGobak: false,
                isMungbak: false,
                isJabak: false,
                isYeokbak: false,
                scoreFormula: "Nagari (Draw) - No winner"
            )
            self.gameWinner = nil
            self.gameLoser = nil
            
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
            gLog("Game Ended in Nagari!")
            return
        }
        currentTurnIndex = (currentTurnIndex + 1) % players.count

        // Dummy-card turns can leave one player with no hand while others still have cards.
        // Skip empty-hand turns so the round can continue until Nagari/all-hands-empty.
        if gameState == .playing {
            var skips = 0
            while let player = currentPlayer, player.hand.isEmpty, skips < players.count {
                gLog("Skipping \(player.name) turn: no cards in hand.")
                currentTurnIndex = (currentTurnIndex + 1) % players.count
                skips += 1
            }

            let noPlayableHands = players.allSatisfy { $0.hand.isEmpty }
            if noPlayableHands {
                self.gameEndReason = .nagari
                self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                    finalScore: 0,
                    isGwangbak: false,
                    isPibak: false,
                    isGobak: false,
                    isMungbak: false,
                    isJabak: false,
                    isYeokbak: false,
                    scoreFormula: "Nagari (Draw) - No playable hands"
                )
                settleResidualCardsIfHandsEmpty()
                gameState = .ended
                gLog("Game Ended in Nagari! (no playable hands)")
                return
            }
        }
        
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
                    stealPi(from: loser, to: winner, count: rules.penalties.gwangbak.pi_to_transfer, reason: "광박(Gwangbak) 피이전")
                }
            }
        }
        
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winner.capturedCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loser.capturedCards, rules: rules)
            // loserPi > 0: exclude 0-Pi players (matches calculatePenalties condition)
            if winnerPi >= 10 && loserPi > 0 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                if rules.penalties.pibak.resolution_type == "pi_transfer" || rules.penalties.pibak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.pibak.pi_to_transfer, reason: "피박(Pibak) 피이전")
                }
            }
        }
        
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winner.capturedCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                if rules.penalties.mungbak.resolution_type == "pi_transfer" || rules.penalties.mungbak.resolution_type == "both" {
                    stealPi(from: loser, to: winner, count: rules.penalties.mungbak.pi_to_transfer, reason: "멍박(Mungbak) 피이전")
                }
            }
        }
    }
    
    func checkEndgameConditions(player: Player, opponent: Player, rules: RuleConfig, isAfterGo: Bool = false) -> Bool {
        let endgame = rules.endgame
        let penalties = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        
        if (endgame.instant_end_on_bak.gwangbak && penalties.isGwangbak) ||
           (endgame.instant_end_on_bak.pibak && penalties.isPibak) ||
           (endgame.instant_end_on_bak.mungbak && penalties.isMungbak) {
            // Note: bomb_mungdda removed as non-standard rule
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }
        
        var currentScore = player.score
        if endgame.score_check_timing == "post_multiplier" {
            currentScore = penalties.finalScore
        }
        
        if currentScore >= endgame.max_round_score {
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }
        
        if player.goCount >= endgame.max_go_count {
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }
        
        return false
    }
    
    private func performTableCapture(for monthCard: Card, on table: inout [Card], player: Player) -> [Card]? {
        let m = table.filter { $0.month == monthCard.month }
        if m.isEmpty {
            table.append(monthCard)
            return []
        } else if m.count == 3 {
            let allFour = [monthCard] + m
            table.removeAll { $0.month == monthCard.month }
            gLog("CHOK! Captured all 4 of month \(monthCard.month)")
            
            // Seolsa Eat (뻑 먹기) bonus detection
            if let puckCreator = seolsaMonths[monthCard.month.rawValue] {
                if puckCreator.id == player.id {
                    isSelfSeolsaEatFlag = true
                } else {
                    isSeolsaEatFlag = true
                }
                seolsaMonths.removeValue(forKey: monthCard.month.rawValue)
            } else {
                // Initial Seolsa (바닥 뻑) capture gives normal Seolsa Eat bonus (1 pi)
                isSeolsaEatFlag = true
            }
            
            return allFour
        } else if m.count == 2 {
            gLog("DEBUG: performTableCapture 2 matches - types: \(m[0].type) vs \(m[1].type)")
            // 2 matches on table: if they differ in type (e.g. junk vs doubleJunk), player must choose
            let typesDistinct = m[0].type != m[1].type
            if typesDistinct {
                if player.isComputer {
                    // AI auto-selects: prefer doubleJunk for maximum points
                    let bestOption = m.first { $0.type == .doubleJunk } ?? m[0]
                    gLog("AI auto-selects \(bestOption.type) for month \(monthCard.month) capture")
                    if let idx = table.firstIndex(where: { $0.id == bestOption.id }) {
                        table.remove(at: idx)
                    }
                    return [monthCard, bestOption]
                } else {
                    // Human player must choose - return nil to indicate "Pause for Choice"
                    // IMPORTANT: We do NOT append monthCard to table yet; it's held in pending state
                    return nil
                }
            } else {
                // Same type – just take the first one
                if let target = m.first, let idx = table.firstIndex(where: { $0.id == target.id }) {
                    table.remove(at: idx)
                    return [monthCard, target]
                }
                table.append(monthCard)
                return []
            }
        } else {
            // 1 match
            if let target = m.first, let idx = table.firstIndex(where: { $0.id == target.id }) {
                table.remove(at: idx)
                return [monthCard, target]
            }
            table.append(monthCard)
            return []
        }
    }
    
    private func stealPi(from: Player, to: Player, count: Int, reason: String = "") {
        guard RuleLoader.shared.config != nil else { return }
        var stolenCount = 0
        var stolenCards: [String] = []
        for _ in 0..<count {
            if let piToSteal = from.capturedCards.first(where: { $0.type == .junk }) {
                if let index = from.capturedCards.firstIndex(of: piToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(piToSteal)
                    stolenCards.append("\(piToSteal.month.rawValue)월 피")
                    stolenCount += 1
                }
            } else if let doublePiToSteal = from.capturedCards.first(where: { $0.type == .doubleJunk }) {
                if let index = from.capturedCards.firstIndex(of: doublePiToSteal) {
                    from.capturedCards.remove(at: index)
                    to.capturedCards.append(doublePiToSteal)
                    stolenCards.append("\(doublePiToSteal.month.rawValue)월 쌍피")
                    stolenCount += 1
                }
            }
        }
        if stolenCount > 0 {
            from.score = ScoringSystem.calculateScore(for: from)
            to.score = ScoringSystem.calculateScore(for: to)
            let cardList = stolenCards.joined(separator: ", ")
            let reasonStr = reason.isEmpty ? "" : " [\(reason)]"
            gLog("피 이동\(reasonStr): \(from.name) → \(to.name) | \(cardList) (\(stolenCount)장)")
        } else {
            let reasonStr = reason.isEmpty ? "" : " [\(reason)]"
            gLog("피 이동 실패\(reasonStr): \(from.name) 에게 피가 없음")
        }
    }

    private func settleResidualCardsIfHandsEmpty() {
        guard players.allSatisfy({ $0.hand.isEmpty }) else { return }

        var movedCount = 0
        if !tableCards.isEmpty {
            movedCount += tableCards.count
            outOfPlayCards.append(contentsOf: tableCards)
            tableCards.removeAll()
        }

        let remainingDeckCards = deck.drainAll()
        if !remainingDeckCards.isEmpty {
            movedCount += remainingDeckCards.count
            outOfPlayCards.append(contentsOf: remainingDeckCards)
        }

        if movedCount > 0 {
            gLog("Terminal cleanup: moved \(movedCount) residual card(s) out of table/deck.")
        }
    }
}
