import Foundation

enum GameState {
    case ready
    case playing
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
        if player.score >= 7 {
            // In real game: Ask Go/Stop. For now: Win immediately for MVP/Testing
            print("\(player.name) Wins with score \(player.score)!")
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
            gameState = .ended // Nagari check needed
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
