import Foundation
import Network

class SimulatorBridge {
    static var shared: SimulatorBridge?
    
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private let gameManager: GameManager
    private let queue = DispatchQueue(label: "com.antigravity.SimulatorBridge")
    
    init(gameManager: GameManager, port: UInt16 = 8080) {
        self.gameManager = gameManager
        
        do {
            self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            fatalError("Failed to create NWListener: \(error)")
        }
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("SimulatorBridge: Ready on port \(port)")
            case .failed(let error):
                print("SimulatorBridge: Failed with error: \(error)")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
    }
    
    func start() {
        listener.start(queue: queue)
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connections.append(connection)
        
        receive(connection: connection)
    }
    
    private func receive(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, context, isComplete, error in
            if let error = error {
                print("SimulatorBridge: Connection error: \(error)")
                self?.cleanup(connection: connection)
                return
            }
            
            if let data = content, !data.isEmpty {
                self?.handleRequest(data, connection: connection)
            }
            
            if isComplete {
                self?.cleanup(connection: connection)
            } else if error == nil {
                self?.receive(connection: connection)
            }
        }
    }
    
    private func handleRequest(_ data: Data, connection: NWConnection) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else {
                return
            }
            
            gLog("SimulatorBridge: Received action: \(action)")
            
            switch action {
            case "get_state":
                sendState(connection: connection)
                
            case "start_game":
                DispatchQueue.main.async {
                    self.gameManager.startGame()
                }
                sendSimpleResponse(status: "ok", action: action, connection: connection)
                
            case "play_card":
                guard let dataDict = json["data"] as? [String: Any],
                      let monthIdx = dataDict["month"] as? Int,
                      let typeStr = dataDict["type"] as? String else {
                    sendErrorResponse(message: "Missing month or type", connection: connection)
                    return
                }
                
                let type: CardType
                switch typeStr {
                case "bright": type = .bright
                case "animal": type = .animal
                case "ribbon": type = .ribbon
                case "doubleJunk": type = .doubleJunk
                default: type = .junk
                }
                
                DispatchQueue.main.async {
                    if let player = self.gameManager.currentPlayer,
                       let card = player.hand.first(where: { $0.month.rawValue == monthIdx && $0.type == type }) {
                        self.gameManager.playTurn(card: card)
                    }
                }
                sendSimpleResponse(status: "action executed", action: action, connection: connection)
                
            case "respond_go_stop":
                guard let dataDict = json["data"] as? [String: Any],
                      let isGo = dataDict["isGo"] as? Bool else {
                    sendErrorResponse(message: "Missing isGo", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    self.gameManager.respondToGoStop(isGo: isGo)
                }
                sendSimpleResponse(status: "action executed", action: action, connection: connection)
                
            case "respond_to_shake":
                guard let dataDict = json["data"] as? [String: Any],
                      let monthIdx = dataDict["month"] as? Int,
                      let didShake = dataDict["didShake"] as? Bool else {
                    sendErrorResponse(message: "Missing month or didShake", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    self.gameManager.respondToShake(month: monthIdx, didShake: didShake)
                }
                sendSimpleResponse(status: "action executed", action: action, connection: connection)
                
            case "click_restart_button":
                DispatchQueue.main.async {
                    self.gameManager.setupGame()
                }
                sendSimpleResponse(status: "action executed", action: action, connection: connection)
                
            default:
                sendSimpleResponse(status: "unknown action", action: action, connection: connection)
            }
            
        } catch {
            gLog("SimulatorBridge: Failed to parse request: \(error)")
        }
    }
    
    private func sendSimpleResponse(status: String, action: String, connection: NWConnection) {
        let resp = ["status": status, "action": action]
        if let data = try? JSONSerialization.data(withJSONObject: resp) {
            var finalData = data
            finalData.append("\n".data(using: .utf8)!)
            connection.send(content: finalData, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func sendErrorResponse(message: String, connection: NWConnection) {
        let resp = ["status": "error", "message": message]
        if let data = try? JSONSerialization.data(withJSONObject: resp) {
            var finalData = data
            finalData.append("\n".data(using: .utf8)!)
            connection.send(content: finalData, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func sendState(connection: NWConnection) {
        let state = gameManager.serializeState()
        
        // We need to encode this to JSON data
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(state)
            // Add a newline because our Python agent expects it
            var messageData = data
            messageData.append("\n".data(using: .utf8)!)
            
            connection.send(content: messageData, completion: .contentProcessed({ error in
                if let error = error {
                    print("SimulatorBridge: Failed to send state: \(error)")
                }
            }))
        } catch {
            print("SimulatorBridge: Failed to encode state: \(error)")
        }
    }
    
    private func cleanup(connection: NWConnection) {
        connection.cancel()
        if let index = connections.firstIndex(where: { $0 === connection }) {
            connections.remove(at: index)
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
        state["players"] = AnyCodable(players.map { player in
            var playerDict = player.serialize()
            playerDict["scoreItems"] = AnyCodable(ScoringSystem.calculateScoreDetail(for: player))
            return playerDict
        })
        state["status"] = AnyCodable("ok")
        return state
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
