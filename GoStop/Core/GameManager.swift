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
    
    // Placeholder for game loop logic
    func playTurn(cardIndex: Int) {
        guard gameState == .playing, let player = currentPlayer else { return }
        
        // 1. Play card from hand
        // 2. Flip from deck
        // 3. Match logic...
    }
}
