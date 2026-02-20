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
}

class CLIEngine {
    let gameManager = GameManager()
    var currentSeed: Int? = nil
    
    func handle(request: CommandRequest) -> [String: Any] {
        switch request.action {
        case "get_state":
            return dumpState()
            
        case "set_condition":
            if let data = request.data {
                if let scenario = data["mock_scenario"]?.value as? String, scenario == "game_over" {
                    gameManager.gameState = .ended
                    if let p1Score = data["player1_score"]?.value as? Int {
                        gameManager.players[0].score = p1Score
                    }
                    if let p2Score = data["player2_score"]?.value as? Int {
                        gameManager.players[1].score = p2Score
                    }
                }
                
                if let seed = data["rng_seed"]?.value as? Int {
                    self.currentSeed = seed
                    gameManager.setupGame(seed: seed)
                }

                if let mockCaptured = data["mock_captured_cards"]?.value as? [[String: Any]] {
                     let player = gameManager.players[0]
                     player.capturedCards = mockCaptured.compactMap { dict -> Card? in
                         guard let m = dict["month"] as? Int,
                               let tStr = dict["type"] as? String else { return nil }
                         let type: CardType
                         switch tStr {
                         case "bright": type = .bright
                         case "animal": type = .animal
                         case "ribbon": type = .ribbon
                         case "doubleJunk": type = .doubleJunk
                         default: type = .junk
                         }
                         return Card(month: Month(rawValue: m) ?? .jan, type: type, imageIndex: 0)
                     }
                     // Force score recalculation
                     player.score = ScoringSystem.calculateScore(for: player)
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
    
    private func dumpState() -> [String: Any] {
        let dump = GameStateDump(
            status: "ok",
            gameState: "\(gameManager.gameState)",
            players: gameManager.players,
            currentTurnIndex: gameManager.currentTurnIndex,
            tableCards: gameManager.tableCards,
            deckCount: gameManager.deck.cards.count
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
