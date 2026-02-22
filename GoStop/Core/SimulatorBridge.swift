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
                    self.sendSimpleResponse(status: "ok", action: action, connection: connection)
                }
                
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
                case "dummy": type = .dummy
                default: type = .junk
                }
                
                DispatchQueue.main.async {
                    if let player = self.gameManager.currentPlayer,
                       let card = player.hand.first(where: { $0.month.rawValue == monthIdx && $0.type == type }) {
                        self.gameManager.playTurn(card: card)
                    }
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "respond_go_stop":
                guard let dataDict = json["data"] as? [String: Any],
                      let isGo = dataDict["isGo"] as? Bool else {
                    sendErrorResponse(message: "Missing isGo", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    self.gameManager.respondToGoStop(isGo: isGo)
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "respond_to_shake":
                guard let dataDict = json["data"] as? [String: Any],
                      let monthIdx = dataDict["month"] as? Int,
                      let didShake = dataDict["didShake"] as? Bool else {
                    sendErrorResponse(message: "Missing month or didShake", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    self.gameManager.respondToShake(month: monthIdx, didShake: didShake)
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "respond_to_capture":
                guard let dataDict = json["data"] as? [String: Any],
                      let cardId = dataDict["id"] as? String else {
                    sendErrorResponse(message: "Missing id for respond_to_capture", connection: connection)
                    return
                }
                
                DispatchQueue.main.async {
                    if let tableCard = self.gameManager.tableCards.first(where: { $0.id == cardId }) {
                        self.gameManager.respondToCapture(selectedCard: tableCard)
                    } else {
                        self.sendErrorResponse(message: "Card with ID \(cardId) not found on table", connection: connection)
                        return
                    }
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }

            case "respond_to_chrysanthemum_choice":
                guard let dataDict = json["data"] as? [String: Any],
                      let roleStr = dataDict["role"] as? String else {
                    sendErrorResponse(message: "Missing role", connection: connection)
                    return
                }
                
                let role: CardRole = roleStr == "doublePi" ? .doublePi : .animal
                
                DispatchQueue.main.async {
                    self.gameManager.respondToChrysanthemumChoice(role: role)
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "click_restart_button":
                DispatchQueue.main.async {
                    self.gameManager.setupGame()
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "mock_endgame_check":
                DispatchQueue.main.async {
                    if let rules = RuleLoader.shared.config {
                        let winner = self.gameManager.players[0]
                        let opponent = self.gameManager.players[1]
                        _ = self.gameManager.checkEndgameConditions(player: winner, opponent: opponent, rules: rules)
                    }
                    self.sendState(connection: connection)
                }
                
            case "set_condition":
                guard let data = json["data"] as? [String: Any] else {
                    sendErrorResponse(message: "Missing data for set_condition", connection: connection)
                    return
                }
                
                DispatchQueue.main.async {
                    if let seed = data["rng_seed"] as? Int {
                        self.gameManager.setupGame(seed: seed)
                    }
                    
                    if let scenario = data["mock_scenario"] as? String, scenario == "game_over" {
                        self.gameManager.gameState = .ended
                    }
                    
                    if let turnIndex = data["currentTurnIndex"] as? Int {
                        self.gameManager.currentTurnIndex = turnIndex
                    }
                    
                    if let mockState = data["mock_gameState"] as? String {
                        switch mockState {
                        case "ready": self.gameManager.gameState = .ready
                        case "playing": self.gameManager.gameState = .playing
                        case "askingGoStop": self.gameManager.gameState = .askingGoStop
                        case "askingShake": self.gameManager.gameState = .askingShake
                        case "ended": self.gameManager.gameState = .ended
                        default: break
                        }
                    }
                    
                    if let mockCaptured = data["mock_captured_cards"] as? [[String: Any]] {
                         let player = self.gameManager.players[0]
                         player.capturedCards = self.parseCards(mockCaptured)
                         player.score = ScoringSystem.calculateScore(for: player)
                    }
                    
                    if let mockOpponentCaptured = data["mock_opponent_captured_cards"] as? [[String: Any]] {
                         let opponent = self.gameManager.players[1]
                         opponent.capturedCards = self.parseCards(mockOpponentCaptured)
                         opponent.score = ScoringSystem.calculateScore(for: opponent)
                    }
                    
                    if let mockHand = data["mock_hand"] as? [[String: Any]] {
                         self.gameManager.players[0].hand = self.parseCards(mockHand)
                    }
                    
                    if let mockDeckArr = data["mock_deck"] as? [[String: Any]] {
                        self.gameManager.mockDeck(cards: self.parseCards(mockDeckArr))
                    }
                    
                    if let mockTable = data["mock_table"] as? [[String: Any]] {
                         self.gameManager.tableCards = self.parseCards(mockTable)
                    }
                    
                    // Advanced player mocking
                    for i in 0..<self.gameManager.players.count {
                        let key = "player\(i)_data"
                        if let pData = data[key] as? [String: Any] {
                            let p = self.gameManager.players[i]
                            if let goCount = pData["goCount"] as? Int { p.goCount = goCount }
                            if let lastGoScore = pData["lastGoScore"] as? Int { p.lastGoScore = lastGoScore }
                            if let money = pData["money"] as? Int { p.money = money }
                            if let score = pData["score"] as? Int { p.score = score }
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
                            
                            if let h = pData["hand"] as? [[String: Any]] {
                                p.hand = self.parseCards(h)
                            }
                            if let c = pData["capturedCards"] as? [[String: Any]] {
                                p.capturedCards = self.parseCards(c)
                                p.score = ScoringSystem.calculateScore(for: p)
                            }
                        }
                    }
                    
                    // Mock month owners for Seolsa testing
                    if let ownersDict = data["mock_month_owners"] as? [String: Int] {
                        self.gameManager.monthOwners = [:]
                        for (monthStr, playerIdx) in ownersDict {
                            if let monthInt = Int(monthStr),
                               let month = Month(rawValue: monthInt),
                               self.gameManager.players.indices.contains(playerIdx) {
                                self.gameManager.monthOwners[month.rawValue] = self.gameManager.players[playerIdx]
                            }
                        }
                    }
                    
                    self.sendSimpleResponse(status: "condition set", action: action, connection: connection)
                }
                
            default:
                sendSimpleResponse(status: "unknown action", action: action, connection: connection)
            }
        } catch {
            gLog("SimulatorBridge: Failed to parse request: \(error)")
        }
    }
    
    // Helper to parse card list from JSON dictionary
    private func parseCards(_ dictList: [[String: Any]]) -> [Card] {
        var cards: [Card] = []
        for dict in dictList {
            if let monthIdx = dict["month"] as? Int,
               let typeStr = dict["type"] as? String {
                let month = Month(rawValue: monthIdx) ?? .jan
                var type: CardType = .junk
                switch typeStr {
                case "bright": type = .bright
                case "animal": type = .animal
                case "ribbon": type = .ribbon
                case "doubleJunk": type = .doubleJunk
                case "dummy": type = .dummy
                default: type = .junk
                }
                let imageIndex = dict["imageIndex"] as? Int ?? 0
                var card = Card(month: month, type: type, imageIndex: imageIndex)
                if let roleStr = dict["selectedRole"] as? String {
                    card.selectedRole = CardRole(rawValue: roleStr)
                }
                cards.append(card)
            }
        }
        return cards
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
        DispatchQueue.main.async {
            let state = self.gameManager.serializeState()
            
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
        state["deckCards"] = AnyCodable(deck.cards)
        state["outOfPlayCount"] = AnyCodable(outOfPlayCards.count)
        state["outOfPlayCards"] = AnyCodable(outOfPlayCards)
        state["currentTurnIndex"] = AnyCodable(currentTurnIndex)
        state["players"] = AnyCodable(players.map { player in
            var playerDict = player.serialize()
            playerDict["scoreItems"] = AnyCodable(ScoringSystem.calculateScoreDetail(for: player))
            return playerDict
        })
        state["eventLogs"] = AnyCodable(eventLogs)
        
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
            if let rules = RuleLoader.shared.config {
                let winner = players[0].score >= players[1].score ? players[0] : players[1]
                let loser = winner === players[0] ? players[1] : players[0]
                let penalty = PenaltySystem.calculatePenalties(winner: winner, loser: loser, rules: rules)
                state["penaltyResult"] = AnyCodable([
                    "finalScore": penalty.finalScore,
                    "isGwangbak": penalty.isGwangbak,
                    "isPibak": penalty.isPibak,
                    "isGobak": penalty.isGobak,
                    "isMungbak": penalty.isMungbak,
                    "isJabak": penalty.isJabak,
                    "isYeokbak": penalty.isYeokbak,
                    "scoreFormula": penalty.scoreFormula
                ])
            }
        }
        
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
