import Foundation

enum GameState {
    case ready
    case playing
    case askingGoStop
    case ended
}

class GameManager: ObservableObject {
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
        setupGame()
    }
    
    func setupGame() {
        self.players = [
            Player(name: "Player 1", money: 10000),
            Player(name: "Computer", money: 10000)
        ]
        self.deck.reset()
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
        guard let playedCard = player.play(card: card) else { return }
        
        var captures: [Card] = []
        
        // 1. Play Card Phase
        captures.append(contentsOf: match(card: playedCard))
        
        // 2. Draw Card Phase
        if let drawnCard = deck.draw() {
             // For UI/Anim, we should expose drawnCard state, but for now just process logic
             // Ideally: self.drawnCard = drawnCard -> Timer -> match(drawnCard)
             // Simplified synchronous logic:
             captures.append(contentsOf: match(card: drawnCard))
        }
        
        // 3. Capture & Score
        if !captures.isEmpty {
            player.capture(cards: captures)
            player.score = ScoringSystem.calculateScore(for: player)
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
                print("\(player.name) reached \(player.score) points, but has no cards left. Forced STOP.")
                executeStop(player: player, rules: rules)
            } else {
                // Ask Go or Stop
                gameState = .askingGoStop
                print("\(player.name) reached \(player.score) points. Asking Go/Stop...")
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
            print("\(player.name) calls GO! (Count: \(player.goCount))")
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
        print("\(player.name) calls STOP and wins! Base: \(player.score), Final Score: \(result.finalScore)")
        
        if result.isGwangbak { print("Gwangbak applied!") }
        if result.isPibak { print("Pibak applied!") }
        if result.isGobak { print("Gobak applied!") }
        
        opponent.money -= result.finalScore * 100
        player.money += result.finalScore * 100
        
        gameState = .ended
    }
    
    private func fallbackEndTurn(player: Player) {
        if player.score >= 7 {
            print("\(player.name) Wins with score \(player.score)! (Fallback)")
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
            print("Game Ended in Nagari!")
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
}
