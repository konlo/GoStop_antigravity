import Foundation

enum GameState: String, Codable {
    case ready
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
    
    var currentPlayer: Player? {
        guard players.indices.contains(currentTurnIndex) else { return nil }
        return players[currentTurnIndex]
    }
    
    init() {
        GameManager.shared = self
        setupGame()
    }
    
    func setupGame(seed: Int? = nil) {
        self.players = [
            Player(name: "Player 1", money: 10000),
            Player(name: "Computer", money: 10000)
        ]
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
    
    func startGame() {
        gameState = .playing
        currentTurnIndex = 0 // Player 1 starts
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
        
        if let rules = RuleLoader.shared.config, rules.special_moves.bomb.enabled,
           handMatches.count == 3, tableMatches.count == 1 {
            // Bomb triggered!
            isBomb = true
            gLog("\(player.name) triggered BOMB (폭탄) for month \(month)!")
            
            // 1. Play all 3 cards from hand
            for mCard in handMatches {
                if let played = player.play(card: mCard) {
                    captures.append(played)
                }
            }
            
            // 2. Capture the 1 card on table
            if let target = tableMatches.first, let index = tableCards.firstIndex(of: target) {
                tableCards.remove(at: index)
                captures.append(target)
            }
            
            // 3. Shake count (for score multiplier)
            player.shakeCount += 1
            
            // 4. Steal Pi (will do after draw phase to match standard flow, or now?)
            // Let's do it after the draw phase matches just in case.
        } else {
            // Normal play
            guard let playedCard = player.play(card: card) else { return }
            captures.append(contentsOf: match(card: playedCard))
        }
        
        // 2. Draw Card Phase
        if let drawnCard = deck.draw() {
             captures.append(contentsOf: match(card: drawnCard))
        }
        
        // 3. Capture & Score
        if !captures.isEmpty {
            player.capture(cards: captures)
            player.score = ScoringSystem.calculateScore(for: player)
        }
        
        // Post-Capture Special Moves (Steal Pi)
        if isBomb, let rules = RuleLoader.shared.config {
            let opponentIndex = (currentTurnIndex + 1) % players.count
            stealPi(from: players[opponentIndex], to: player, count: rules.special_moves.bomb.steal_pi_count)
        }
        
        // 4. End Turn Logic
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
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
        guard gameState == .askingGoStop, let player = currentPlayer else { return }
        
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if isGo {
            player.goCount += 1
            player.lastGoScore = player.score
            gLog("\(player.name) calls GO! (Count: \(player.goCount))")
            gameState = .playing
            endTurn()
        } else {
            executeStop(player: player, rules: rules)
        }
    }
    
    private func executeStop(player: Player, rules: RuleConfig) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        
        let result = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        gLog("\(player.name) calls STOP and wins! Base: \(player.score), Final Score: \(result.finalScore)")
        
        if result.isGwangbak { gLog("Gwangbak applied!") }
        if result.isPibak { gLog("Pibak applied!") }
        if result.isGobak { gLog("Gobak applied!") }
        if result.isMungbak { gLog("Mungbak applied!") }
        
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
        if currentPlayer?.name == "Computer" && gameState == .playing {
            // Delay or immediate? Immediate for logic test
            if let aiCard = currentPlayer?.hand.first {
                playTurn(card: aiCard)
            }
        }
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
