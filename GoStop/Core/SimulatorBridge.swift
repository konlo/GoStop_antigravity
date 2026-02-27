import Foundation
import Network

class SimulatorBridge {
    static var shared: SimulatorBridge?
    
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
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
        receiveBuffers[ObjectIdentifier(connection)] = Data()
        
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
                self?.appendAndHandleRequests(data, connection: connection)
            }
            
            if isComplete {
                self?.cleanup(connection: connection)
            } else if error == nil {
                self?.receive(connection: connection)
            }
        }
    }

    private func appendAndHandleRequests(_ data: Data, connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        var buffer = receiveBuffers[key] ?? Data()
        buffer.append(data)
        
        let newline = Data([0x0A]) // '\n'
        while let lineRange = buffer.range(of: newline) {
            let packet = buffer.subdata(in: 0..<lineRange.lowerBound)
            buffer.removeSubrange(0...lineRange.lowerBound)
            
            guard !packet.isEmpty else { continue }
            handleRequest(packet, connection: connection)
        }
        
        receiveBuffers[key] = buffer
    }
    
    private func handleRequest(_ data: Data, connection: NWConnection) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else {
                sendErrorResponse(message: "Invalid request payload", connection: connection)
                return
            }
            
            gLog("SimulatorBridge: Received action: \(action)")
            
            let playActions: Set<String> = ["play_card", "respond_to_go", "respond_to_capture", "decide_shake", "decide_chrysanthemum"]
            if playActions.contains(action) {
                DispatchQueue.main.async {
                    self.gameManager.externalControlMode = true
                }
            }
            
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
                    self.gameManager.startGame()
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "click_start_button":
                DispatchQueue.main.async {
                    self.gameManager.startGame()
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }

                
            case "mock_endgame_check":
                DispatchQueue.main.async {
                    if let rules = RuleLoader.shared.config {
                        let winner = self.gameManager.players[0]
                        let opponent = self.gameManager.players[1]
                        _ = self.gameManager.checkEndgameConditions(player: winner, opponent: opponent, rules: rules, isAfterGo: false)
                    }
                    self.sendState(connection: connection)
                }
                
            case "restore_state":
                guard let dataDict = json["data"] as? [String: Any],
                      let index = dataDict["index"] as? Int else {
                    sendErrorResponse(message: "Missing index", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    self.gameManager.restoreState(from: index)
                    self.sendSimpleResponse(status: "state restored", action: action, connection: connection)
                }
                
            case "get_history_entry":
                guard let dataDict = json["data"] as? [String: Any],
                      let index = dataDict["index"] as? Int else {
                    sendErrorResponse(message: "Missing index", connection: connection)
                    return
                }
                DispatchQueue.main.async {
                    if let entry = self.gameManager.getHistoryEntry(at: index) {
                        let json: [String: Any] = [
                            "status": "ok",
                            "action": action,
                            "data": entry.mapValues { $0.value }
                        ]
                        if let data = try? JSONSerialization.data(withJSONObject: json) {
                            var finalData = data
                            finalData.append("\n".data(using: .utf8)!)
                            connection.send(content: finalData, completion: .contentProcessed({ _ in }))
                        }
                    } else {
                        self.sendErrorResponse(message: "Index out of bounds", connection: connection)
                    }
                }
                
            case "step_next_turn":
                DispatchQueue.main.async {
                    self.gameManager.forceInternalComputerStep()
                    self.sendSimpleResponse(status: "step executed", action: action, connection: connection)
                }

            case "force_chongtong_check":
                let timing = (json["data"] as? [String: Any])?["timing"] as? String ?? "initial"
                DispatchQueue.main.async {
                    for player in self.gameManager.players {
                        if let month = self.gameManager.getChongtongMonth(for: player) {
                            self.gameManager.resolveChongtong(player: player, month: month, timing: timing)
                        }
                    }
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "toggle_automation":
                DispatchQueue.main.async {
                    self.gameManager.internalComputerAutomationEnabled.toggle()
                    let status = self.gameManager.internalComputerAutomationEnabled ? "enabled" : "disabled"
                    
                    if self.gameManager.internalComputerAutomationEnabled {
                        self.gameManager.externalControlMode = false
                    }
                    
                    if self.gameManager.internalComputerAutomationEnabled && self.gameManager.gameState == .ready {
                        self.gameManager.startGame()
                    } else if self.gameManager.internalComputerAutomationEnabled {
                        // Ensure action is scheduled if already playing
                        self.gameManager.maybeScheduleInternalComputerAction_ExternalWorkaround()
                    }
                    
                    self.sendSimpleResponse(status: "automation \(status)", action: action, connection: connection)
                }
                
            case "reset_busy_state":
                DispatchQueue.main.async {
                    self.gameManager.emergencyResetBusyState()
                    self.sendSimpleResponse(status: "ok", action: action, connection: connection)
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

                    if let clearDeck = data["clear_deck"] as? Bool, clearDeck {
                        _ = self.gameManager.deck.drainAll()
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
                            if let dummyCardCount = pData["dummyCardCount"] as? Int { p.dummyCardCount = dummyCardCount }
                            
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
            sendErrorResponse(message: "Failed to parse request: \(error.localizedDescription)", connection: connection)
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
        receiveBuffers.removeValue(forKey: ObjectIdentifier(connection))
    }
}

// Extension to GameManager in SimulatorBridge.swift is no longer needed as it's moved to GameManager.swift
