import Foundation
import Combine

// A CLI for Test Agent interaction.
// This reads lines of JSON from standard input, acts on the game engine, and prints JSON responses.

struct CommandRequest: Codable {
    let action: String
    let data: [String: AnyCodable]?
}


struct GameStateDump: Codable {
    let status: String
    let gameState: String
    let players: [Player]
    let currentTurnIndex: Int
    let tableCards: [Card]
    let deckCount: Int
    let deckCards: [Card]
}

class CLIEngine {
    let gameManager = GameManager()
    var currentSeed: Int? = nil
    
    func handle(request: CommandRequest) -> [String: Any] {
        switch request.action {
        case "get_state":
            return dumpState()
            
        case "start_game":
            gameManager.startGame()
            return ["status": "action executed", "action": "start_game"]
            
        case "play_card":
            guard let data = request.data,
                  let monthIdx = data["month"]?.value as? Int,
                  let typeStr = data["type"]?.value as? String else {
                return ["status": "error", "message": "Missing month or type for play_card"]
            }
            
            let type: CardType
            switch typeStr {
            case "bright": type = .bright
            case "animal": type = .animal
            case "ribbon": type = .ribbon
            case "doubleJunk": type = .doubleJunk
            case "dummy": type = .dummy
            default: type = .junk
            }
            
            // Find card in hand
            guard let player = gameManager.currentPlayer,
                  let card = player.hand.first(where: { $0.month.rawValue == monthIdx && $0.type == type }) else {
                // print("CLI DEBUG: Card \(monthIdx) \(type) NOT found in \(gameManager.currentPlayer?.name ?? "nil")'s hand.")
                return ["status": "error", "message": "Card not found in hand"]
            }
            
            // print("CLI DEBUG: Found card \(card.month) \(card.type). Calling gameManager.playTurn.")
            
            gameManager.playTurn(card: card)
            return ["status": "action executed", "action": "play_card"]
            
        case "respond_go_stop":
            guard let data = request.data,
                  let isGo = data["isGo"]?.value as? Bool else {
                return ["status": "error", "message": "Missing isGo for respond_go_stop"]
            }
            gameManager.respondToGoStop(isGo: isGo)
            return ["status": "action executed", "action": "respond_go_stop"]
            
        case "respond_to_shake":
            guard let data = request.data,
                  let monthIdx = data["month"]?.value as? Int,
                  let didShake = data["didShake"]?.value as? Bool else {
                return ["status": "error", "message": "Missing month or didShake for respond_to_shake"]
            }
            gameManager.respondToShake(month: monthIdx, didShake: didShake)
            return ["status": "action executed", "action": "respond_to_shake"]

        case "set_condition":
            if let data = request.data {
                if let scenario = data["mock_scenario"]?.value as? String, scenario == "game_over" {
                    gameManager.gameState = .ended
                }
                
                if let seed = data["rng_seed"]?.value as? Int {
                    self.currentSeed = seed
                    gameManager.setupGame(seed: seed)
                }
                
                if let mockState = data["mock_gameState"]?.value as? String {
                    switch mockState {
                    case "ready": gameManager.gameState = .ready
                    case "playing": gameManager.gameState = .playing
                    case "askingGoStop": gameManager.gameState = .askingGoStop
                    case "askingShake": gameManager.gameState = .askingShake
                    case "ended": gameManager.gameState = .ended
                    default: break
                    }
                }

                if let mockCaptured = data["mock_captured_cards"]?.value as? [[String: Any]] {
                     let player = gameManager.players[0]
                     player.capturedCards = parseCards(mockCaptured)
                     player.score = ScoringSystem.calculateScore(for: player)
                }
                
                if let mockOpponentCaptured = data["mock_opponent_captured_cards"]?.value as? [[String: Any]] {
                     let opponent = gameManager.players[1]
                     opponent.capturedCards = parseCards(mockOpponentCaptured)
                     opponent.score = ScoringSystem.calculateScore(for: opponent)
                }

                if let mockHand = data["mock_hand"]?.value as? [[String: Any]] {
                     gameManager.players[0].hand = parseCards(mockHand)
                }
                
                if let mockDeckArr = data["mock_deck"]?.value as? [[String: Any]] {
                    gameManager.mockDeck(cards: parseCards(mockDeckArr))
                }
                
                if let mockTable = data["mock_table"]?.value as? [[String: Any]] {
                     gameManager.tableCards = parseCards(mockTable)
                }
                
                // Advanced player mocking
                for i in 0..<gameManager.players.count {
                    let key = "player\(i)_data"
                    if let pData = data[key]?.value as? [String: Any] {
                        let p = gameManager.players[i]
                        if let goCount = pData["goCount"] as? Int { p.goCount = goCount }
                        if let money = pData["money"] as? Int { p.money = money }
                        if let shakeCount = pData["shakeCount"] as? Int { p.shakeCount = shakeCount }
                        if let bombCount = pData["bombCount"] as? Int { p.bombCount = bombCount }
                        if let sweepCount = pData["sweepCount"] as? Int { p.sweepCount = sweepCount }
                        if let ttadakCount = pData["ttadakCount"] as? Int { p.ttadakCount = ttadakCount }
                        if let jjokCount = pData["jjokCount"] as? Int { p.jjokCount = jjokCount }
                        if let seolsaCount = pData["seolsaCount"] as? Int { p.seolsaCount = seolsaCount }
                        if let isPiMungbak = pData["isPiMungbak"] as? Bool { p.isPiMungbak = isPiMungbak }
                        if let mungddaCount = pData["mungddaCount"] as? Int { p.mungddaCount = mungddaCount }
                        if let bombMungddaCount = pData["bombMungddaCount"] as? Int { p.bombMungddaCount = bombMungddaCount }
                        if let isComputer = pData["isComputer"] as? Bool { p.isComputer = isComputer }
                        if let dummyCardCount = pData["dummyCardCount"] as? Int { p.dummyCardCount = dummyCardCount }
                    }
                }
                
                // Allow tests to directly force the active player
                if let turnIdx = data["currentTurnIndex"]?.value as? Int,
                   gameManager.players.indices.contains(turnIdx) {
                    gameManager.currentTurnIndex = turnIdx
                }
            }
            return ["status": "ok", "message": "Condition set"]
            
        case "click_restart_button":
            gameManager.setupGame(seed: currentSeed)
            return ["status": "action executed", "action": "click_restart_button"]
            
        case "invalid_action_triggering_crash":
            fatalError("Simulated App Crash for Testing")
            
        default:
            return ["status": "action executed", "action": request.action]
        }
    }
    
    private func parseCards(_ array: [[String: Any]]) -> [Card] {
        return array.compactMap { dict -> Card? in
            guard let m = dict["month"] as? Int,
                  let tStr = dict["type"] as? String else { return nil }
            let type = parseType(tStr)
            return Card(month: Month(rawValue: m) ?? .jan, type: type, imageIndex: 0)
        }
    }
    
    private func parseType(_ tStr: String) -> CardType {
        switch tStr {
        case "bright": return .bright
        case "animal": return .animal
        case "ribbon": return .ribbon
        case "doubleJunk": return .doubleJunk
        case "dummy": return .dummy
        default: return .junk
        }
    }
    
    private func dumpState() -> [String: Any] {
        let dump = GameStateDump(
            status: "ok",
            gameState: "\(gameManager.gameState)",
            players: gameManager.players,
            currentTurnIndex: gameManager.currentTurnIndex,
            tableCards: gameManager.tableCards,
            deckCount: gameManager.deck.cards.count,
            deckCards: gameManager.deck.cards
        )
        
        guard let data = try? JSONEncoder().encode(dump),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "error", "message": "Failed to serialize state"]
        }
        
        // Inject score items for each player
        if var playersArray = dict["players"] as? [[String: Any]] {
            for i in 0..<gameManager.players.count {
                let items = ScoringSystem.calculateScoreDetail(for: gameManager.players[i])
                if let itemsData = try? JSONEncoder().encode(items),
                   let itemsArray = try? JSONSerialization.jsonObject(with: itemsData) as? [[String: Any]] {
                    playersArray[i]["scoreItems"] = itemsArray
                }
            }
            dict["players"] = playersArray
        }
        
        // Inject pending shakes if in askingShake state
        if gameManager.gameState == .askingShake {
            dict["pendingShakeMonths"] = gameManager.pendingShakeMonths
        }
        
        // Inject penalty result if game ended
        if gameManager.gameState == .ended, 
           let rules = RuleLoader.shared.config {
            // Assume player 0 is the winner for penalty testing purposes if score > 0
            let winner = gameManager.players[0].score >= gameManager.players[1].score ? gameManager.players[0] : gameManager.players[1]
            let loser = winner === gameManager.players[0] ? gameManager.players[1] : gameManager.players[0]
            
            let penalty = PenaltySystem.calculatePenalties(winner: winner, loser: loser, rules: rules)
            dict["penaltyResult"] = [
                "finalScore": penalty.finalScore,
                "isGwangbak": penalty.isGwangbak,
                "isPibak": penalty.isPibak,
                "isGobak": penalty.isGobak,
                "isMungbak": penalty.isMungbak,
                "isJabak": penalty.isJabak,
                "isYeokbak": penalty.isYeokbak
            ]
        }
        
        return dict
    }
}

func main() {
    // Explicitly load rules at startup
    RuleLoader.shared.loadRules()
    
    let engine = CLIEngine()
    
    // Standard input reading loop
    while let line = readLine() {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { continue }
        
        do {
            guard let cmdData = trimmedLine.data(using: .utf8) else { continue }
            let request = try JSONDecoder().decode(CommandRequest.self, from: cmdData)
            
            let responseDict = engine.handle(request: request)
            
            let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
            
        } catch {
            let errResponse = ["status": "error", "error": error.localizedDescription]
            if let jsonData = try? JSONSerialization.data(withJSONObject: errResponse, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
        }
    }
}

main()
