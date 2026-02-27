import Foundation
import SwiftUI
import Combine

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

struct UXEvent: Codable {
    let id: String
    let type: String // "animationStart", "animationEnd", "stateTransition"
    let timestamp: TimeInterval
    let data: [String: String] // cardId, source, target, etc.
}


func gLog(_ message: String) {
    #if DEBUG
    fputs("\(message)\n", stderr)
    #else
    print(message)
    #endif
    
    // Also record to event logs for AI/Simulator inspection - MUST be on main thread
    if Thread.isMainThread {
        GameManager.shared?.addEvent(message)
    } else {
        DispatchQueue.main.async {
            GameManager.shared?.addEvent(message)
        }
    }
}

class GameManager: ObservableObject {
    static var shared: GameManager?
    
    @Published var gameState: GameState = .ready
    @Published var deck = Deck()
    @Published var players: [Player] = []
    @Published var currentTurnIndex: Int = 0
    @Published var tableCards: [Card] = []
    @Published var outOfPlayCards: [Card] = []
    
    // Unified Animation Tracking
    @Published var currentMovingCards: [Card] = []
    @Published var movingCardsScale: CGFloat = 1.0
    @Published var movingCardsPiCount: Int? = nil
    @Published var hiddenInSourceCardIds: Set<String> = []
    @Published var hiddenInTargetCardIds: Set<String> = []
    @Published var movingCardsShowDebug: Bool = false
    @Published private(set) var pendingAutomationDelays: Int = 0
    private var automationDelayGeneration: Int = 0
    
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
    @Published var uxEventLogs: [UXEvent] = []
    private var stateHistory: [[String: AnyCodable]] = []
    
    private var playerChangeCancellables: [AnyCancellable] = []

    
    // Manual UI uses internal computer automation. External agents should disable it.
    var internalComputerAutomationEnabled = false
    var externalControlMode = false
    private var internalComputerActionScheduled = false

    var isAutomationBusy: Bool {
        pendingAutomationDelays > 0 ||
        !currentMovingCards.isEmpty ||
        !hiddenInSourceCardIds.isEmpty ||
        !hiddenInTargetCardIds.isEmpty
    }
    
    var currentPlayer: Player? {
        guard players.indices.contains(currentTurnIndex) else { return nil }
        return players[currentTurnIndex]
    }
    
    init() {
        GameManager.shared = self
        setupGame()
    }

    private func bindPlayerChangeForwarding() {
        playerChangeCancellables = players.map { player in
            player.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }
    }
    
    func addEvent(_ message: String) {
        self.eventLogs.append(message)
        if self.eventLogs.count > 100 {
            self.eventLogs.removeFirst()
        }
    }
    
    func addUXEvent(type: String, data: [String: String]) {
        let event = UXEvent(id: UUID().uuidString, type: type, timestamp: Date().timeIntervalSince1970, data: data)
        self.uxEventLogs.append(event)
        if self.uxEventLogs.count > 200 {
            self.uxEventLogs.removeFirst()
        }
    }
    
    func getHistoryEntry(at index: Int) -> [String: AnyCodable]? {
        guard index >= 0 && index < stateHistory.count else { return nil }
        return stateHistory[index]
    }

    private var lastSnapshotTime: TimeInterval = 0
    func takeSnapshot() {
        // Simple throttle to avoid flooding snapshots in extremely tight loops (e.g. concurrent animations)
        let now = Date().timeIntervalSince1970
        if now - lastSnapshotTime < 0.05 { return } 
        lastSnapshotTime = now
        
        let snapshot = self.serializeState()
        self.stateHistory.append(snapshot)
        if self.stateHistory.count > 50 {
            self.stateHistory.removeFirst()
        }
    }

    
    func setupGame(seed: Int? = nil) {
        automationDelayGeneration += 1
        externalControlMode = false
        let player1 = Player(name: "Player 1", money: 10000)
        let computer = Player(name: "Computer", money: 10000)
        computer.isComputer = true
        self.players = [player1, computer]
        bindPlayerChangeForwarding()
        self.currentTurnIndex = 0
        self.outOfPlayCards = []
        self.gameEndReason = nil
        self.lastPenaltyResult = nil
        self.gameWinner = nil
        self.gameLoser = nil
        self.chongtongMonth = nil
        self.chongtongTiming = nil
        self.eventLogs = []
        self.stateHistory = []
        self.deck.reset(seed: seed)
        self.monthOwners = [:]
        self.seolsaMonths = [:]
        self.currentMovingCards = []
        self.movingCardsScale = 1.0
        self.movingCardsPiCount = nil
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.movingCardsShowDebug = false
        self.pendingAutomationDelays = 0
        self.pendingShakeMonths = []
        self.pendingShakeCard = nil
        self.pendingShakeMonth = nil
        self.pendingCapturePlayedCard = nil
        self.pendingCaptureDrawnCard = nil
        self.pendingCaptureOptions = []
        self.pendingChrysanthemumCard = nil
        self.isSeolsaEatFlag = false
        self.isSelfSeolsaEatFlag = false
        self.turnIsBomb = false
        self.turnIsTtadak = false
        self.turnIsJjok = false
        self.turnIsSeolsa = false
        self.turnPlayPhaseCaptured = []
        self.turnDrawPhaseCaptured = []
        self.turnPlayedCard = nil
        self.turnTableWasNotEmpty = false
        self.internalComputerActionScheduled = false
        self.gameState = .ready
        self.dealCards()
        self.takeSnapshot()
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
        maybeScheduleInternalComputerAction()
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
            if !player.shakenMonths.contains(month) {
                player.shakenMonths.append(month)
            }
        }
        
        pendingShakeMonths.removeAll { $0 == month }
        
        if pendingShakeMonths.isEmpty {
            gameState = .playing
            gLog("Shake phase resolved. Resuming turn.")
            if let card = pendingShakeCard {
                pendingShakeCard = nil
                pendingShakeMonth = nil
                playTurn(card: card)
            } else {
                maybeScheduleInternalComputerAction()
            }
        } else {
            gLog("More shakes pending: \(pendingShakeMonths)")
            maybeScheduleInternalComputerAction()
        }
    }
    
    func respondToChrysanthemumChoice(role: CardRole) {
        guard (gameState == .choosingChrysanthemumRole || (currentPlayer?.isComputer == true && gameState == .playing)),
              let player = currentPlayer,
              let card = pendingChrysanthemumCard else { return }
        
        gLog("\(player.name) chose role \(role.rawValue) for Chrysanthemum card.")
        
        player.objectWillChange.send()
        var updatedCard = card
        updatedCard.selectedRole = role
        
        player.capture(cards: [updatedCard])
        gLog("Successfully captured Chrysanthemum with role \(role.rawValue).")
        
        pendingChrysanthemumCard = nil
        gameState = .playing
        
        player.score = ScoringSystem.calculateScore(for: player)
        
        finalizeTurnAfterCapture(player: player)
    }

    private func finalizeTurnAfterCapture(player: Player) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if turnIsBomb {
            gLog("\(player.name) triggered 폭탄(Bomb)")
            stealPi(from: opponent, to: player, count: rules.special_moves.bomb.steal_pi_count, reason: "폭탄(Bomb)")
        }
        if turnIsTtadak && rules.special_moves.ttadak.enabled {
            player.ttadakCount += 1
            gLog("\(player.name) triggered 따닥(Ttadak)")
            stealPi(from: opponent, to: player, count: rules.special_moves.ttadak.steal_pi_count, reason: "따닥(Ttadak)")
        }
        if turnIsJjok && rules.special_moves.jjok.enabled {
            player.jjokCount += 1
            gLog("\(player.name) triggered 쪽(Jjok)")
            stealPi(from: opponent, to: player, count: rules.special_moves.jjok.steal_pi_count, reason: "쪽(Jjok)")
        }
        if turnIsSeolsa && rules.special_moves.seolsa.enabled && turnPlayPhaseCaptured.isEmpty {
             let month = turnPlayedCard?.month.rawValue ?? 0
             player.seolsaCount += 1
             gLog("\(player.name) triggered 뻑(Seolsa) for month \(month)")
             let seolsaPenaltyPi = rules.special_moves.seolsa.penalty_pi_count
             if seolsaPenaltyPi > 0 {
                 stealPi(from: player, to: opponent, count: seolsaPenaltyPi, reason: "뻑(Seolsa) 패널티")
             }
             seolsaMonths[month] = player
        }
        if isSeolsaEatFlag && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            gLog("\(player.name) triggered 뻑 먹기(Seolsa Eat)")
            stealPi(from: opponent, to: player, count: rules.special_moves.seolsaEat.steal_pi_count, reason: "뻑 먹기(Seolsa Eat)")
        }
        if isSelfSeolsaEatFlag && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            gLog("\(player.name) triggered 자뻑(Self Seolsa Eat)")
            stealPi(from: opponent, to: player, count: rules.special_moves.seolsaEat.self_eat_steal_pi_count, reason: "자뻑(Self Seolsa Eat)")
        }
        
        if rules.special_moves.sweep.enabled, turnTableWasNotEmpty, tableCards.isEmpty, !player.hand.isEmpty {
            gLog("\(player.name) swept the table (싹쓸이)!")
            player.sweepCount += 1
            stealPi(from: opponent, to: player, count: rules.special_moves.sweep.steal_pi_count, reason: "싹쓸이(Sweep)")
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
                maybeScheduleInternalComputerAction()
            }
        } else {
            endTurn()
        }
    }
    func respondToCapture(selectedCard: Card) {
        guard let player = currentPlayer else { return }
        
        let playedCard = pendingCapturePlayedCard
        let drawnCard = pendingCaptureDrawnCard
        
        gLog("\(player.name) chose \(selectedCard.type) for month \(selectedCard.month) capture")
        
        if let idx = tableCards.firstIndex(where: { $0.id == selectedCard.id }) {
            tableCards.remove(at: idx)
        }
        
        let triggerCard = playedCard ?? drawnCard
        guard let pCard = triggerCard else {
            gLog("ERROR: respondToCapture called but no trigger card found.")
            return
        }

        // In choosingCapture, the trigger card remains on the table as a visible placeholder.
        // Remove it now that the choice is committed so it doesn't persist as a duplicate.
        tableCards.removeAll { $0.id == pCard.id }
        
        let captured = [pCard, selectedCard]
        let finalCaptures = captured.filter { !($0.month == .sep && $0.type == .animal) }
        if !finalCaptures.isEmpty {
            player.capture(cards: finalCaptures)
        }
        
        player.score = ScoringSystem.calculateScore(for: player)
        monthOwners.removeValue(forKey: selectedCard.month.rawValue)
        
        if playedCard != nil {
            turnPlayPhaseCaptured = captured
        } else if drawnCard != nil {
            turnDrawPhaseCaptured = captured
        }
        
        gLog("\(player.name) captured \(captured.count) cards (choice). Total: \(player.capturedCards.count)")
        
        pendingCapturePlayedCard = nil
        pendingCaptureDrawnCard = nil
        pendingCaptureOptions = []
        gameState = .playing
        
        guard let rules = RuleLoader.shared.config else {
            endTurn()
            return
        }

        if playedCard != nil {
            if let drawn = deck.draw() {
                gLog("Drawn after play-choice: \(drawn.month) (\(drawn.type))")
                
                let remainingOnTable = tableCards.first(where: { $0.month == drawn.month })
                
                if captured[0].month == drawn.month && remainingOnTable == nil {
                    turnIsSeolsa = true
                    gLog("SEOLSA (뻑) via choice! Play match followed by draw match for month \(drawn.month)")
                    
                    tableCards.append(contentsOf: captured)
                    tableCards.append(drawn)
                    player.capturedCards.removeAll { c in finalCaptures.contains(where: { $0.id == c.id }) }
                    turnPlayPhaseCaptured = []
                } else {
                    if let dCaptured = performTableCapture(for: drawn, on: &tableCards, player: player) {
                        turnDrawPhaseCaptured = dCaptured
                        if !turnDrawPhaseCaptured.isEmpty {
                            let finalDCaptures = turnDrawPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
                            if !finalDCaptures.isEmpty {
                                player.capture(cards: finalDCaptures)
                            }
                            if turnDrawPhaseCaptured.contains(where: { $0.month == pCard.month }) {
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
                        gLog("Secondary choice needed for Draw Phase!")
                        pendingCaptureDrawnCard = drawn
                        pendingCaptureOptions = tableCards.filter { $0.month == drawn.month }
                        gameState = .choosingCapture
                        player.score = ScoringSystem.calculateScore(for: player)
                        return
                    }
                }
            }
        }
        
        let allNewCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
        if checkAndHandleChrysanthemumRole(capturedCards: allNewCaptures, player: player, rules: rules) {
            return
        }

        finalizeTurnAfterCapture(player: player)
    }

    func playTurn(card: Card) {
        guard let rules = RuleLoader.shared.config else { return }
        guard gameState == .playing, !isAutomationBusy, let player = currentPlayer else { return }

        // Mid-game shake check (bomb takes priority).
        if card.type != .dummy, rules.special_moves.shake.enabled {
            let sameMonthCount = player.hand.filter { $0.month == card.month }.count
            let tableMatchCount = tableCards.filter { $0.month == card.month }.count
            let alreadyShaken = player.shakenMonths.contains(card.month.rawValue)
            let isBombCondition = rules.special_moves.bomb.enabled && sameMonthCount >= 3 && tableMatchCount == 1

            if sameMonthCount >= 3 && !alreadyShaken && !isBombCondition {
                pendingShakeCard = card
                pendingShakeMonth = card.month.rawValue
                pendingShakeMonths = [card.month.rawValue]
                gameState = .askingShake
                gLog("\(player.name) can SHAKE for month \(card.month)! Asking...")
                maybeScheduleInternalComputerAction()
                return
            }
        }
        
        // Reset turn state
        turnIsBomb = false
        turnIsTtadak = false
        turnIsJjok = false
        turnIsSeolsa = false
        turnPlayPhaseCaptured = []
        turnDrawPhaseCaptured = []
        turnPlayedCard = nil
        turnTableWasNotEmpty = !tableCards.isEmpty
        
        // Phase 1: Hand Play
        if card.type == .dummy {
            gLog("\(player.name) played a DUMMY card.")
            player.dummyCardCount -= 1
            if let idx = player.hand.firstIndex(where: { $0.id == card.id }) {
                player.hand.remove(at: idx)
            }
            // Dummy cards vanish on play and do not trigger a draw phase.
            finalizeTurnState(player: player, rules: rules)
        } else {
            // Check for Bomb/Shake first
            let month = card.month
            let handMatches = player.hand.filter { $0.month == month }
            let tableMatches = tableCards.filter { $0.month == month }
            
            if rules.special_moves.bomb.enabled, handMatches.count == 3, tableMatches.count == 1 {
                handleBombPlay(player: player, month: month, handMatches: handMatches, tableMatches: tableMatches, rules: rules)
            } else {
                if let idx = player.hand.firstIndex(where: { $0.id == card.id }),
                   let pCard = player.play(card: card) {
                    turnPlayedCard = pCard
                    
                    // Phase 1 Start: Move to Table
                    // Add to table immediately so matchedGeometryEffect has a destination target
                    self.tableCards.append(pCard)
                    
                    // We also keep it in Hand virtually (hidden) so matchedGeometryEffect has a source
                    // Important: Insert back at SAME index to avoid layout jump
                    player.hand.insert(pCard, at: idx)
                    self.hiddenInSourceCardIds.insert(pCard.id)
                    self.hiddenInTargetCardIds.insert(pCard.id) // Target is Table
                    
                    self.addUXEvent(type: "moveStart", data: ["cardId": pCard.id, "source": "hand", "target": "table"])
                    self.takeSnapshot()
                    
                    let sourceScale: CGFloat = player.isComputer ? 0.2 : 0.9
                    self.movingCardsScale = sourceScale

                    
                    let showDebug: Bool = {
                        guard let context = ConfigManager.shared.layoutContext else { return false }
                        return context.config.debug.player?.sortedOrderOverlay == true
                    }()
                    self.movingCardsShowDebug = showDebug
                    self.currentMovingCards = [pCard]
                    
                    withAnimation {
                         self.movingCardsScale = 0.7 // Table Scale
                    }
                    
                    let delay = AnimationManager.shared.config.card_move_duration
                    self.runAfterAnimationDelay(delay) {
                        
                        // Check capture logically
                        if let captured = self.performTableCaptureLogical(for: pCard, player: player) {
                            self.addUXEvent(type: "moveEnd", data: ["cardId": pCard.id, "target": "table"])
                            self.turnPlayPhaseCaptured = captured

                            
                            if captured.isEmpty {
                                // Just staying on table
                                self.currentMovingCards = [] 
                                self.hiddenInSourceCardIds.remove(pCard.id)
                                self.hiddenInTargetCardIds.remove(pCard.id)
                                // Actually remove from hand now
                                player.hand.removeAll { $0.id == pCard.id }
                                self.monthOwners[pCard.month.rawValue] = player
                                self.proceedToDrawPhase(player: player, rules: rules)
                            } else {
                                self.monthOwners.removeValue(forKey: pCard.month.rawValue)
                                
                                // Phase 2 Start: Move to Captured Area
                                // Add to captured area immediately so matchedGeometryEffect has a destination target
                                let filtered = captured.filter { !($0.month == .sep && $0.type == .animal) }
                                player.capture(cards: filtered)
                                player.score = ScoringSystem.calculateScore(for: player)
                                
                                // Keep on Table (hidden) during flight to Captured Area
                                // (pCard and captured cards are already in tableCards)
                                for c in captured {
                                    self.hiddenInSourceCardIds.insert(c.id)
                                    self.hiddenInTargetCardIds.insert(c.id) // Target is Captured
                                }
                                
                                // Calculate Pi Count for the moving card badge
                                let currentPiCount = player.piCount
                                self.movingCardsPiCount = currentPiCount > 0 ? currentPiCount : nil
                                
                                let cardIds = filtered.map { $0.id }.joined(separator: ",")
                                self.addUXEvent(type: "moveStart", data: ["cardIds": cardIds, "source": "table", "target": "captured"])
                                self.takeSnapshot()
                                
                                self.movingCardsScale = 0.7 // From Table

                                self.movingCardsShowDebug = false
                                
                                withAnimation {
                                    let targetScale: CGFloat = player.isComputer ? 0.45 : 0.5
                                    self.movingCardsScale = targetScale
                                    self.currentMovingCards = filtered
                                }
                                
                                self.runAfterAnimationDelay(delay) {
                                    let cardIds = filtered.map { $0.id }.joined(separator: ",")
                                    self.addUXEvent(type: "moveEnd", data: ["cardIds": cardIds, "target": "captured"])
                                    self.currentMovingCards = []
                                    self.movingCardsPiCount = nil
                                    // Cleanup sources
                                    for c in captured {
                                        self.hiddenInSourceCardIds.remove(c.id)
                                        self.hiddenInTargetCardIds.remove(c.id)
                                        self.tableCards.removeAll { $0.id == c.id }
                                    }
                                    player.hand.removeAll { $0.id == pCard.id }
                                    
                                    self.proceedToDrawPhase(player: player, rules: rules)
                                }
                            }
                        } else {
                            // Choice needed
                            self.currentMovingCards = []
                            self.hiddenInSourceCardIds.remove(pCard.id)
                            self.hiddenInTargetCardIds.remove(pCard.id)
                            player.hand.removeAll { $0.id == pCard.id }
                            
                            let options = self.tableCards.filter { $0.month == pCard.month && $0.id != pCard.id }
                            self.pendingCapturePlayedCard = pCard
                            self.pendingCaptureOptions = options
                            self.gameState = .choosingCapture
                            self.maybeScheduleInternalComputerAction()
                        }
                    }
                }
            }
        }
    }

    private func handleBombPlay(player: Player, month: Month, handMatches: [Card], tableMatches: [Card], rules: RuleConfig) {
        turnIsBomb = true
        gLog("\(player.name) triggered BOMB!")
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
        
        for _ in 0..<rules.special_moves.bomb.dummy_card_count {
            let dummy = Card(month: .none, type: .dummy, imageIndex: 0)
            player.hand.append(dummy)
            player.dummyCardCount += 1
        }

        // Bomb captures bypass the animated capture path, so commit them immediately.
        let committedBombCaptures = turnPlayPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
        if !committedBombCaptures.isEmpty {
            player.capture(cards: committedBombCaptures)
            player.score = ScoringSystem.calculateScore(for: player)
        }
        
        proceedToDrawPhase(player: player, rules: rules)
    }

    private func proceedToDrawPhase(player: Player, rules: RuleConfig) {
        let drawDelay = AnimationManager.shared.config.card_move_duration
        runAfterAnimationDelay(drawDelay) {
            if let drawnCard = self.deck.draw() {
                gLog("Drawn: \(drawnCard.month) (\(drawnCard.type))")
                
                self.tableCards.append(drawnCard)
                self.deck.pushCardsOnTop([drawnCard])
                self.hiddenInSourceCardIds.insert(drawnCard.id)
                self.hiddenInTargetCardIds.insert(drawnCard.id)
                
                self.addUXEvent(type: "moveStart", data: ["cardId": drawnCard.id, "source": "deck", "target": "table"])
                self.takeSnapshot()
                
                self.movingCardsScale = 0.7

                self.movingCardsShowDebug = false
                self.currentMovingCards = [drawnCard]
                
                withAnimation { }
                
                self.deck.remove(card: drawnCard)
                
                let remainingOnTable = self.tableCards.filter { $0.month == drawnCard.month && $0.id != drawnCard.id }.first
                let moveDelay = AnimationManager.shared.config.card_move_duration
                
                self.runAfterAnimationDelay(moveDelay) {
                    self.addUXEvent(type: "moveEnd", data: ["cardId": drawnCard.id, "target": "table"])
                    if !self.turnPlayPhaseCaptured.isEmpty && self.turnPlayPhaseCaptured.count == 2 && 
                       self.turnPlayPhaseCaptured[0].month == drawnCard.month && remainingOnTable == nil {
                        self.currentMovingCards = []
                        self.hiddenInSourceCardIds.remove(drawnCard.id)
                        self.hiddenInTargetCardIds.remove(drawnCard.id)
                        self.turnIsSeolsa = true
                        gLog("SEOLSA!")

                        // Revert the play-phase capture commit: Seolsa leaves all 3 cards on the table.
                        let revertedPlayCaptures = self.turnPlayPhaseCaptured.filter { !($0.month == .sep && $0.type == .animal) }
                        if !revertedPlayCaptures.isEmpty {
                            player.capturedCards.removeAll { captured in
                                revertedPlayCaptures.contains(where: { $0.id == captured.id })
                            }
                            player.score = ScoringSystem.calculateScore(for: player)
                        }

                        self.tableCards.append(contentsOf: self.turnPlayPhaseCaptured)
                        self.turnPlayPhaseCaptured = []
                        self.turnDrawPhaseCaptured = []
                        self.finalizeTurnState(player: player, rules: rules)
                    } else {
                        if let captured = self.performTableCaptureLogical(for: drawnCard, player: player) {
                            self.turnDrawPhaseCaptured = captured
                            self.handleDrawCaptured(drawnCard: drawnCard, player: player)
                            
                            if captured.isEmpty {
                                self.currentMovingCards = []
                                self.hiddenInSourceCardIds.remove(drawnCard.id)
                                self.hiddenInTargetCardIds.remove(drawnCard.id)
                                self.finalizeTurnState(player: player, rules: rules)
                            } else {
                                let currentPiCount = player.piCount
                                self.movingCardsPiCount = currentPiCount > 0 ? currentPiCount : nil
                                
                                let filtered = captured.filter { !($0.month == .sep && $0.type == .animal) }
                                player.capture(cards: filtered)
                                player.score = ScoringSystem.calculateScore(for: player)
                                
                                for c in captured {
                                    self.hiddenInSourceCardIds.insert(c.id)
                                    self.hiddenInTargetCardIds.insert(c.id)
                                }
                                let cardIds = filtered.map { $0.id }.joined(separator: ",")
                                self.addUXEvent(type: "moveStart", data: ["cardIds": cardIds, "source": "table", "target": "captured"])
                                self.takeSnapshot()
                                
                                self.movingCardsScale = 0.7
                                self.movingCardsShowDebug = false
                                
                                withAnimation {
                                    let targetScale: CGFloat = player.isComputer ? 0.45 : 0.5
                                    self.movingCardsScale = targetScale
                                    self.currentMovingCards = filtered
                                }
                                
                                self.runAfterAnimationDelay(moveDelay) {
                                    let cardIds = filtered.map { $0.id }.joined(separator: ",")
                                    self.addUXEvent(type: "moveEnd", data: ["cardIds": cardIds, "target": "captured"])
                                    self.currentMovingCards = []
                                    self.movingCardsPiCount = nil
                                    for c in captured {
                                        self.hiddenInSourceCardIds.remove(c.id)
                                        self.hiddenInTargetCardIds.remove(c.id)
                                        self.tableCards.removeAll { $0.id == c.id }
                                    }
                                    self.finalizeTurnState(player: player, rules: rules)
                                }
                            }
                        } else {
                            self.currentMovingCards = []
                            self.hiddenInSourceCardIds.remove(drawnCard.id)
                            self.hiddenInTargetCardIds.remove(drawnCard.id)
                            self.pendingCaptureDrawnCard = drawnCard
                            self.pendingCaptureOptions = self.tableCards.filter { $0.month == drawnCard.month && $0.id != drawnCard.id }
                            self.gameState = .choosingCapture
                            player.score = ScoringSystem.calculateScore(for: player)
                            self.maybeScheduleInternalComputerAction()
                        }
                    }
                }
            } else {
                self.finalizeTurnState(player: player, rules: rules)
            }
        }
    }

    private func handleDrawCaptured(drawnCard: Card, player: Player) {
        if !turnDrawPhaseCaptured.isEmpty {
            if let pCard = turnPlayedCard, turnDrawPhaseCaptured.contains(where: { $0.month == pCard.month }) {
                if !turnPlayPhaseCaptured.isEmpty { turnIsTtadak = true } 
                else { turnIsJjok = true }
            }
            for captured in turnDrawPhaseCaptured {
                monthOwners.removeValue(forKey: captured.month.rawValue)
                seolsaMonths.removeValue(forKey: captured.month.rawValue)
            }
        } else {
            monthOwners[drawnCard.month.rawValue] = player
        }
    }

    private func finalizeTurnState(player: Player, rules: RuleConfig) {
        let finalCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
        if !finalCaptures.isEmpty {
            // Note: Capture and score already handled in phased animations
            if checkAndHandleChrysanthemumRole(capturedCards: finalCaptures, player: player, rules: rules) {
                return
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
                    var updatedCard = chrysCard
                    updatedCard.selectedRole = defaultRole
                    player.capture(cards: [updatedCard])
                    player.score = ScoringSystem.calculateScore(for: player)
                } else {
                    pendingChrysanthemumCard = chrysCard
                    gameState = .choosingChrysanthemumRole
                    return true
                }
            }
        }
        return false
    }

    func respondToGoStop(isGo: Bool) {
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
            gameState = .playing
            if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: true) { return }
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
            self.gameEndReason = .stop
            self.gameWinner = player
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
        } else {
            endTurn()
        }
    }
    
    private func endTurn() {
        let allHandsEmpty = players.allSatisfy { $0.hand.isEmpty }
        if deck.cards.isEmpty || allHandsEmpty {
            self.gameEndReason = .nagari
            self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                finalScore: 0, isGwangbak: false, isPibak: false, isGobak: false,
                isMungbak: false, isJabak: false, isYeokbak: false, scoreFormula: "Nagari"
            )
            self.gameWinner = nil
            self.gameLoser = nil
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
            gLog("Game Ended in Nagari!")
            return
        }
        currentTurnIndex = (currentTurnIndex + 1) % players.count
        if gameState == .playing {
            var skips = 0
            while let player = currentPlayer, player.hand.isEmpty, skips < players.count {
                gLog("Skipping \(player.name) turn: no cards in hand.")
                currentTurnIndex = (currentTurnIndex + 1) % players.count
                skips += 1
            }
            if players.allSatisfy({ $0.hand.isEmpty }) {
                self.gameEndReason = .nagari
                self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                    finalScore: 0, isGwangbak: false, isPibak: false, isGobak: false,
                    isMungbak: false, isJabak: false, isYeokbak: false, scoreFormula: "Nagari"
                )
                self.gameWinner = nil
                self.gameLoser = nil
                settleResidualCardsIfHandsEmpty()
                gameState = .ended
                gLog("Game Ended in Nagari (Hand Empty)!")
                return
            }
        }
        maybeScheduleInternalComputerAction()
    }
    
    func checkEndgameConditions(player: Player, opponent: Player, rules: RuleConfig, isAfterGo: Bool) -> Bool {
        let endgame = rules.endgame
        let bak = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)

        // 1. Instant End on Bak Check if enabled
        let instantEnd = endgame.instant_end_on_bak
        if (instantEnd.pibak && bak.isPibak) || 
           (instantEnd.gwangbak && bak.isGwangbak) || 
           (instantEnd.mungbak && bak.isMungbak) {
            gLog("Instant End Condition met via Bak!")
            executeStop(player: player, rules: rules)
            return true
        }

        // 2. Max Score Check (pre/post multiplier based on rule)
        let scoreForThreshold = (endgame.score_check_timing == "post_multiplier") ? bak.finalScore : player.score
        if scoreForThreshold >= endgame.max_round_score {
            gLog("\(player.name) reached Max Score (\(endgame.max_round_score))! score=\(scoreForThreshold)")
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }

        // 3. Max Go Count
        if player.goCount >= endgame.max_go_count {
            gLog("\(player.name) reached Max Go Count (\(endgame.max_go_count))!")
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }
        
        return false
    }

    private func resolveBakPiTransfers(winner: Player, loser: Player, rules: RuleConfig) {
        let stopWin = winner.goCount == 0
        let applyBakBecauseStop = rules.go_stop.apply_bak_on_stop || !stopWin
        let applyBakBecauseOpponentGo = !rules.go_stop.bak_only_if_opponent_go || loser.goCount > 0

        guard applyBakBecauseStop && applyBakBecauseOpponentGo else { return }

        // Gwangbak Pi Transfer
        if rules.penalties.gwangbak.enabled {
            let winnerKwangs = winner.capturedCards.filter { $0.type == .bright }.count
            let loserKwangs = loser.capturedCards.filter { $0.type == .bright }.count
            if winnerKwangs >= 3 && loserKwangs <= rules.penalties.gwangbak.opponent_max_kwang {
                if rules.penalties.gwangbak.resolution_type == "pi_transfer" || rules.penalties.gwangbak.resolution_type == "both" {
                    let count = rules.penalties.gwangbak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: "광박(Gwangbak) 피 이동")
                }
            }
        }
        
        // Pibak Pi Transfer
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winner.capturedCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loser.capturedCards, rules: rules)
            if winnerPi >= 10 && loserPi > 0 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                if rules.penalties.pibak.resolution_type == "pi_transfer" || rules.penalties.pibak.resolution_type == "both" {
                    let count = rules.penalties.pibak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: "피박(Pibak) 피 이동")
                }
            }
        }

        // Mungbak Pi Transfer
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winner.capturedCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                if rules.penalties.mungbak.resolution_type == "pi_transfer" || rules.penalties.mungbak.resolution_type == "both" {
                    let count = rules.penalties.mungbak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: "멍박(Mungbak) 피 이동")
                }
            }
        }
    }
    
    private func performTableCaptureLogical(for monthCard: Card, player: Player) -> [Card]? {
        var tableCopy = self.tableCards
        // The card is already in the table for animation targeting. 
        // Remove it from the logic copy to let performTableCapture decide where it really goes.
        tableCopy.removeAll { $0.id == monthCard.id }
        
        if let captured = performTableCapture(for: monthCard, on: &tableCopy, player: player) {
            self.tableCards = tableCopy
            return captured
        }
        return nil
    }
    
    func maybeScheduleInternalComputerAction_ExternalWorkaround() {
        self.maybeScheduleInternalComputerAction()
    }
    
    func emergencyResetBusyState() {
        self.automationDelayGeneration += 1
        self.pendingAutomationDelays = 0
        self.currentMovingCards = []
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.internalComputerActionScheduled = false
        gLog("Emergency Busy State Reset triggered via SimulatorBridge.")
    }
    
    private func maybeScheduleInternalComputerAction() {
        guard internalComputerAutomationEnabled, !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        switch gameState {
        case .playing, .askingShake, .askingGoStop, .choosingCapture, .choosingChrysanthemumRole:
            break
        case .ready, .ended:
            return
        }
        
        guard !internalComputerActionScheduled else { return }
        internalComputerActionScheduled = true
        let generation = automationDelayGeneration
        
        let delay = AnimationManager.shared.config.opponent_action_delay
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.internalComputerActionScheduled = false
            guard self.automationDelayGeneration == generation else { return }
            self.performInternalComputerAction()
        }
    }
    
    func performInternalComputerAction() {
        guard internalComputerAutomationEnabled, !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        // For in-app autoplay, wait until the full matched-geometry animation state is idle.
        guard !isAutomationBusy else {
            maybeScheduleInternalComputerAction()
            return
        }
        
        self.performInternalComputerActionLogic()
    }
    
    func forceInternalComputerStep() {
        guard !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        // Skip automationBusy check? No, we still want to wait for animations to finish before starting a NEW turn step.
        guard !isAutomationBusy else { return }
        
        // Call the internal logic directly without the automation flag guard.
        self.performInternalComputerActionLogic()
    }
    
    private func performInternalComputerActionLogic() {
        guard let player = currentPlayer, player.isComputer else { return }
        
        switch gameState {
        case .playing:
            guard let card = chooseComputerPlayCard(from: player.hand) else { return }
            gLog("Internal computer automation: \(player.name) plays \(card.month.rawValue) \(card.type.rawValue)")
            playTurn(card: card)
            
        case .askingShake:
            if let month = pendingShakeMonths.first ?? pendingShakeMonth {
                gLog("Internal computer automation: auto-decline shake for month \(month)")
                respondToShake(month: month, didShake: false)
            }
            
        case .askingGoStop:
            let shouldGo = player.goCount == 0 && player.hand.count > 1
            gLog("Internal computer automation: \(shouldGo ? "GO" : "STOP")")
            respondToGoStop(isGo: shouldGo)
            
        case .choosingCapture:
            if let selected = chooseComputerCaptureOption(from: pendingCaptureOptions) {
                gLog("Internal computer automation: selecting capture \(selected.month.rawValue) \(selected.type.rawValue)")
                respondToCapture(selectedCard: selected)
            }
            
        case .choosingChrysanthemumRole:
            let defaultRole = RuleLoader.shared.config
                .flatMap { CardRole(rawValue: $0.cards.chrysanthemum_rule.default_role) } ?? .animal
            gLog("Internal computer automation: Chrysanthemum role \(defaultRole.rawValue)")
            respondToChrysanthemumChoice(role: defaultRole)
            
        case .ready, .ended:
            break
        }
    }
    
    private func chooseComputerPlayCard(from hand: [Card]) -> Card? {
        guard !hand.isEmpty else { return nil }
        let tableMonths = Set(tableCards.map { $0.month.rawValue })
        
        if let matching = hand.first(where: { $0.type != .dummy && tableMonths.contains($0.month.rawValue) }) {
            return matching
        }
        if let nonDummy = hand.first(where: { $0.type != .dummy }) {
            return nonDummy
        }
        return hand.first
    }
    
    private func chooseComputerCaptureOption(from options: [Card]) -> Card? {
        if let doubleJunk = options.first(where: { $0.type == .doubleJunk }) {
            return doubleJunk
        }
        return options.first
    }

    private func runAfterAnimationDelay(_ delay: Double, _ block: @escaping () -> Void) {
        if delay <= 0 {
            block()
        } else {
            let generation = automationDelayGeneration
            pendingAutomationDelays += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { 
                    block() 
                    return 
                }
                
                let generationMatches = (self.automationDelayGeneration == generation)
                if generationMatches {
                    self.pendingAutomationDelays = max(0, self.pendingAutomationDelays - 1)
                    block()
                }
                // If generation doesn't match, we omit block() because the game has been reset.
                // setupGame() already cleared pendingAutomationDelays, currentMovingCards, etc.
            }
        }
    }

    private func performTableCapture(for monthCard: Card, on table: inout [Card], player: Player) -> [Card]? {
        let m = table.filter { $0.month == monthCard.month }
        if m.isEmpty {
            table.append(monthCard)
            return []
        } else if m.count == 3 {
            let allFour = [monthCard] + m
            table.removeAll { $0.month == monthCard.month }
            
            if let puckCreator = seolsaMonths[monthCard.month.rawValue] {
                if puckCreator.id == player.id {
                    isSelfSeolsaEatFlag = true
                } else {
                    isSeolsaEatFlag = true
                }
                seolsaMonths.removeValue(forKey: monthCard.month.rawValue)
            } else {
                isSeolsaEatFlag = true
            }
            
            return allFour
        } else if m.count == 2 {
            let typesDistinct = m[0].type != m[1].type
            if typesDistinct {
                if player.isComputer {
                    let bestOption = m.first { $0.type == .doubleJunk } ?? m[0]
                    if let idx = table.firstIndex(where: { $0.id == bestOption.id }) {
                        table.remove(at: idx)
                    }
                    return [monthCard, bestOption]
                } else {
                    return nil
                }
            } else {
                if let target = m.first, let idx = table.firstIndex(where: { $0.id == target.id }) {
                    table.remove(at: idx)
                    return [monthCard, target]
                }
                table.append(monthCard)
                return []
            }
        } else {
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
    }
}

// Extension to GameManager to provide serializable state
extension GameManager {
    func serializeState() -> [String: AnyCodable] {
        var state: [String: AnyCodable] = [:]
        state["gameState"] = AnyCodable(gameState.rawValue)
        state["deckCount"] = AnyCodable(deck.cards.count)
        state["tableCards"] = AnyCodable(tableCards)
        state["deckCards"] = AnyCodable(deck.cards)
        state["outOfPlayCount"] = AnyCodable(outOfPlayCards.count)
        state["outOfPlayCards"] = AnyCodable(outOfPlayCards)
        state["currentTurnIndex"] = AnyCodable(currentTurnIndex)
        state["isAutomationBusy"] = AnyCodable(isAutomationBusy)
        state["pendingAutomationDelays"] = AnyCodable(pendingAutomationDelays)
        state["currentMovingCardIds"] = AnyCodable(currentMovingCards.map { $0.id })
        state["hiddenInSourceCardIds"] = AnyCodable(Array(hiddenInSourceCardIds).sorted())
        state["hiddenInTargetCardIds"] = AnyCodable(Array(hiddenInTargetCardIds).sorted())
        state["players"] = AnyCodable(players.map { player in
            var playerDict = player.serialize()
            playerDict["scoreItems"] = AnyCodable(ScoringSystem.calculateScoreDetail(for: player))
            return playerDict
        })
        state["eventLogs"] = AnyCodable(eventLogs)
        state["uxEventLogs"] = AnyCodable(uxEventLogs)
        state["historyCount"] = AnyCodable(stateHistory.count)
        
        if let playedCard = pendingCapturePlayedCard {
            state["pendingCapturePlayedCard"] = AnyCodable(playedCard)
        }
        if let drawnCard = pendingCaptureDrawnCard {
            state["pendingCaptureDrawnCard"] = AnyCodable(drawnCard)
        }
        
        if gameState == .choosingCapture {
            state["pendingCaptureOptions"] = AnyCodable(pendingCaptureOptions)
        }
        
        if gameState == .choosingChrysanthemumRole {
            if let chrysCard = pendingChrysanthemumCard {
                state["pendingChrysanthemumCard"] = AnyCodable(chrysCard)
            }
        }
        
        if gameState == .askingShake {
            state["pendingShakeMonths"] = AnyCodable(pendingShakeMonths)
        }
        
        if let month = chongtongMonth {
            state["chongtongMonth"] = AnyCodable(month)
        }
        if let timing = chongtongTiming {
            state["chongtongTiming"] = AnyCodable(timing)
        }
        
        if gameState == .ended {
            if let reason = gameEndReason {
                state["gameEndReason"] = AnyCodable(reason.rawValue)
            }
            if let lastResult = lastPenaltyResult {
                state["penaltyResult"] = AnyCodable([
                    "finalScore": AnyCodable(lastResult.finalScore),
                    "isGwangbak": AnyCodable(lastResult.isGwangbak),
                    "isPibak": AnyCodable(lastResult.isPibak),
                    "isGobak": AnyCodable(lastResult.isGobak),
                    "isMungbak": AnyCodable(lastResult.isMungbak),
                    "isJabak": AnyCodable(lastResult.isJabak),
                    "isYeokbak": AnyCodable(lastResult.isYeokbak),
                    "scoreFormula": AnyCodable(lastResult.scoreFormula)
                ])
            } else if gameEndReason == .nagari {
                state["penaltyResult"] = AnyCodable([
                    "finalScore": AnyCodable(0),
                    "isGwangbak": AnyCodable(false),
                    "isPibak": AnyCodable(false),
                    "isGobak": AnyCodable(false),
                    "isMungbak": AnyCodable(false),
                    "isJabak": AnyCodable(false),
                    "isYeokbak": AnyCodable(false),
                    "scoreFormula": AnyCodable("Nagari (Draw)")
                ])
            }
        }
        
        state["status"] = AnyCodable("ok")
        return state
    }
    
    func restoreState(from historyIndex: Int) {
        guard stateHistory.indices.contains(historyIndex) else { return }
        let snapshot = stateHistory[historyIndex]
        restoreFromSnapshot(snapshot)
    }
    
    func restoreFromSnapshot(_ snapshot: [String: AnyCodable]) {
        // Implementation for restoring basic properties
        if let gameStateStr = snapshot["gameState"]?.value as? String,
           let state = GameState(rawValue: gameStateStr) {
            self.gameState = state
        }
        
        if let turnIndex = snapshot["currentTurnIndex"]?.value as? Int {
            self.currentTurnIndex = turnIndex
        }
        
        // Complex objects would need deeper restoration if we want full fidelity.
        // For UX monitoring, we primarily need the visual state: cards on table, in hands, etc.
        // This is a simplified restore for now.
    }
}

// Helper for type-erased Codable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let codableValue = value as? Encodable {
            try codableValue.encode(to: encoder)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        } else {
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}

