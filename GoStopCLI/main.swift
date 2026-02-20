import Foundation
import Combine

// A CLI for Test Agent interaction.
// This reads lines of JSON from standard input, acts on the game engine, and prints JSON responses.

struct CommandRequest: Codable {
    let action: String
    let data: [String: AnyCodable]?
}

struct AnyCodable: Codable {
    var value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let dictVal as [String: Any]:
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        case let arrayVal as [Any]:
            try container.encode(arrayVal.map { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
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
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "error", "message": "Failed to serialize state"]
        }
        return dict
    }
}

func main() {
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
