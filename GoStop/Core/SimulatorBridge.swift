import Foundation
import Network

class SimulatorBridge {
    static var shared: SimulatorBridge?
    
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private let gameManager: GameManager
    private let queue = DispatchQueue(label: "com.antigravity.SimulatorBridge")
    private var pendingStateConnections: [NWConnection] = []
    private var stateSnapshotInFlight = false
    private var stateSnapshotDirty = false
    private var cachedStatePayload: Data?
    private var cachedStateTimestamp: TimeInterval = 0
    private let stateCacheTTL: TimeInterval = 0.0
    private var hasTemporaryRuleOverride = false
    private var specialEventProbeGeneration = 0
    
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
            if action != "get_state" {
                cachedStatePayload = nil
                cachedStateTimestamp = 0
                if stateSnapshotInFlight {
                    // A mutating action arrived while a snapshot was being built.
                    // Drop that snapshot result and rebuild for queued get_state callers.
                    stateSnapshotDirty = true
                }
            }
            
            if TestControlSupport.externallyControlledActions.contains(action) {
                DispatchQueue.main.async {
                    self.gameManager.externalControlMode = true
                }
            }
            
            switch action {
            case "get_state":
                enqueueStateResponse(connection: connection)
                
            case "start_game":
                DispatchQueue.main.async {
                    self.resetTemporaryRulesIfNeeded()
                    self.resetSimulatedSpecialEventProbe()
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
                let type = TestControlSupport.parseCardType(typeStr)
                
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
                let role = TestControlSupport.parseCardRole(roleStr)
                
                DispatchQueue.main.async {
                    self.gameManager.respondToChrysanthemumChoice(role: role)
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }

            case "get_persistence_probe_config":
                DispatchQueue.main.async {
                    self.sendJSONResponse(
                        payload: [
                            "status": "ok",
                            "action": action,
                            "data": TestControlSupport.persistenceProbeData()
                        ],
                        connection: connection
                    )
                }

            case "set_persistence_probe_config":
                guard let dataDict = json["data"] as? [String: Any] else {
                    sendErrorResponse(message: "Missing data for set_persistence_probe_config", connection: connection)
                    return
                }

                DispatchQueue.main.async {
                    switch TestControlSupport.updatePersistenceProbeConfig(with: dataDict) {
                    case .success(let payload):
                        self.sendJSONResponse(
                            payload: [
                                "status": "ok",
                                "action": action,
                                "data": payload
                            ],
                            connection: connection
                        )
                    case .failure(let error):
                        let message = error.localizedDescription
                        self.sendErrorResponse(message: message, connection: connection)
                    }
                }
                
            case "click_restart_button":
                DispatchQueue.main.async {
                    self.resetTemporaryRulesIfNeeded()
                    self.resetSimulatedSpecialEventProbe()
                    self.gameManager.setupGame()
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }
                
            case "click_start_button":
                DispatchQueue.main.async {
                    self.resetTemporaryRulesIfNeeded()
                    self.resetSimulatedSpecialEventProbe()
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
                    self.queue.async {
                        self.enqueueStateResponse(connection: connection)
                    }
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
                    do {
                        try TestControlSupport.applyTestCondition(
                            data,
                            to: self.gameManager,
                            applyCustomRules: { customRules in
                                try self.applyCustomRules(customRules)
                            },
                            didUpdateMockEventLogs: { eventLogs in
                                self.simulateSpecialEventProbe(for: eventLogs)
                            }
                        )
                        self.sendSimpleResponse(status: "condition set", action: action, connection: connection)
                    } catch {
                        self.sendErrorResponse(message: "Failed to apply custom_rules: \(error.localizedDescription)", connection: connection)
                    }
                }
                
            default:
                sendSimpleResponse(status: "unknown action", action: action, connection: connection)
            }
        } catch {
            gLog("SimulatorBridge: Failed to parse request: \(error)")
            sendErrorResponse(message: "Failed to parse request: \(error.localizedDescription)", connection: connection)
        }
    }
    
    private func resetTemporaryRulesIfNeeded() {
        guard hasTemporaryRuleOverride else { return }
        RuleLoader.shared.loadRules()
        hasTemporaryRuleOverride = false
    }

    private func resetSimulatedSpecialEventProbe() {
        specialEventProbeGeneration += 1
        applySimulatedSpecialEventProbe(activePopupTitle: nil, pendingQueueCount: 0)
    }

    private func simulateSpecialEventProbe(for eventLogs: [String]) {
        resetSimulatedSpecialEventProbe()
        let generation = specialEventProbeGeneration
        let popupTitles = eventLogs.compactMap { simulatedSpecialEventPopupTitle(from: $0) }

        guard !popupTitles.isEmpty else {
            return
        }

        presentSimulatedSpecialEventPopup(at: 0, titles: popupTitles, generation: generation)
    }

    private func presentSimulatedSpecialEventPopup(
        at index: Int,
        titles: [String],
        generation: Int
    ) {
        guard generation == specialEventProbeGeneration else { return }
        guard titles.indices.contains(index) else {
            applySimulatedSpecialEventProbe(activePopupTitle: nil, pendingQueueCount: 0)
            return
        }

        let pendingQueueCount = max(0, titles.count - index - 1)
        applySimulatedSpecialEventProbe(
            activePopupTitle: titles[index],
            pendingQueueCount: pendingQueueCount
        )

        let displayDuration: TimeInterval = 1.7
        let queueAdvanceDelay: TimeInterval = 0.12

        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
            guard generation == self.specialEventProbeGeneration else { return }
            self.applySimulatedSpecialEventProbe(
                activePopupTitle: nil,
                pendingQueueCount: pendingQueueCount
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + queueAdvanceDelay) {
                guard generation == self.specialEventProbeGeneration else { return }
                let nextIndex = index + 1
                if nextIndex < titles.count {
                    self.presentSimulatedSpecialEventPopup(
                        at: nextIndex,
                        titles: titles,
                        generation: generation
                    )
                } else {
                    self.applySimulatedSpecialEventProbe(activePopupTitle: nil, pendingQueueCount: 0)
                }
            }
        }
    }

    private func applySimulatedSpecialEventProbe(
        activePopupTitle: String?,
        pendingQueueCount: Int
    ) {
        let hasActiveOrPending = activePopupTitle != nil || pendingQueueCount > 0
        let isDecisionOverlayDeferred = isDecisionOverlayState(gameManager.gameState) && hasActiveOrPending
        let isEndSummaryDeferred = gameManager.gameState == .ended && hasActiveOrPending

        gameManager.updateSpecialEventOverlayProbe(
            activePopupTitle: activePopupTitle,
            pendingQueueCount: pendingQueueCount,
            isEndSummaryDeferred: isEndSummaryDeferred,
            isDecisionOverlayDeferred: isDecisionOverlayDeferred
        )
    }

    private func isDecisionOverlayState(_ gameState: GameState) -> Bool {
        switch gameState {
        case .askingGoStop, .askingShake, .choosingCapture, .choosingChrysanthemumRole:
            return true
        case .ready, .playing, .ended:
            return false
        }
    }

    private func simulatedSpecialEventPopupTitle(from log: String) -> String? {
        if log.contains("reached Triple Seolsa") {
            return "삼뻑 종료"
        }
        if log.contains("declared SHAKE for month") {
            return "흔들기"
        }
        if log.contains("triggered BOMB!") {
            return "폭탄"
        }
        if log.contains("swept the table (싹쓸이)!") {
            return "싹쓸이"
        }
        if log.contains("triggered 따닥(Ttadak)") {
            return "따닥"
        }
        if log.contains("triggered 쪽(Jjok)") {
            return "쪽"
        }
        if log.contains("triggered 청단(Cheongdan)") {
            return "청단"
        }
        if log.contains("triggered 홍단(Hongdan)") {
            return "홍단"
        }
        if log.contains("triggered 고도리(Godori)") {
            return "고도리"
        }
        if log.contains("triggered 구사(Gusa)") {
            return "구사"
        }
        if log.contains("triggered 뻑(Seolsa)") {
            return "뻑(설사)"
        }
        if log.contains("triggered 뻑 먹기(Seolsa Eat)") {
            return "뻑 먹기"
        }
        if log.contains("triggered 자뻑(Self Seolsa Eat)") {
            return "자뻑"
        }
        return nil
    }

    private func applyCustomRules(_ customRules: [String: Any]) throws {
        guard let baseRules = ConfigurationStore.shared.ruleConfig() ?? RuleLoader.shared.config else {
            throw NSError(
                domain: "SimulatorBridge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Base rule config is not loaded"]
            )
        }

        let encoder = JSONEncoder()
        let baseData = try encoder.encode(baseRules)
        guard let baseJSONObject = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            throw NSError(
                domain: "SimulatorBridge",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize base rules"]
            )
        }

        let mergedJSONObject = mergeJSONObject(baseJSONObject, with: customRules)
        let mergedData = try JSONSerialization.data(withJSONObject: mergedJSONObject, options: [])
        let decodedRules = try JSONDecoder().decode(RuleConfig.self, from: mergedData)
        RuleLoader.shared.replaceRulesTemporarily(decodedRules)
        hasTemporaryRuleOverride = true
    }

    private func mergeJSONObject(_ base: [String: Any], with overrides: [String: Any]) -> [String: Any] {
        var merged = base
        for (key, overrideValue) in overrides {
            if let overrideDict = overrideValue as? [String: Any],
               let baseDict = merged[key] as? [String: Any] {
                merged[key] = mergeJSONObject(baseDict, with: overrideDict)
            } else {
                merged[key] = overrideValue
            }
        }
        return merged
    }
    
    private func sendSimpleResponse(status: String, action: String, connection: NWConnection) {
        let resp = ["status": status, "action": action]
        if let data = try? JSONSerialization.data(withJSONObject: resp) {
            var finalData = data
            finalData.append("\n".data(using: .utf8)!)
            connection.send(content: finalData, completion: .contentProcessed({ _ in }))
        }
    }

    private func sendJSONResponse(payload: [String: Any], connection: NWConnection) {
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
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

    private func enqueueStateResponse(connection: NWConnection?) {
        if let connection {
            pendingStateConnections.append(connection)
        }
        let now = Date().timeIntervalSince1970
        if stateCacheTTL > 0,
           let cached = cachedStatePayload,
           (now - cachedStateTimestamp) <= stateCacheTTL,
           !pendingStateConnections.isEmpty {
            flushPendingStateResponses(payload: cached)
            return
        }
        guard !pendingStateConnections.isEmpty else { return }
        guard !stateSnapshotInFlight else { return }

        stateSnapshotInFlight = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let state = self.gameManager.serializeState()
            let encoder = JSONEncoder()
            var payload: Data?
            if let data = try? encoder.encode(state) {
                var message = data
                message.append("\n".data(using: .utf8)!)
                payload = message
            }
            self.queue.async {
                self.stateSnapshotInFlight = false
                guard let payload else {
                    let pending = self.pendingStateConnections
                    self.pendingStateConnections.removeAll()
                    for conn in pending {
                        self.sendErrorResponse(message: "Failed to encode state.", connection: conn)
                    }
                    return
                }

                if self.stateSnapshotDirty {
                    // Serve queued callers with a post-mutation snapshot, not stale pre-action data.
                    self.stateSnapshotDirty = false
                    self.enqueueStateResponse(connection: nil)
                    return
                }

                self.cachedStatePayload = payload
                self.cachedStateTimestamp = Date().timeIntervalSince1970
                self.flushPendingStateResponses(payload: payload)
            }
        }
    }

    private func flushPendingStateResponses(payload: Data) {
        guard !pendingStateConnections.isEmpty else { return }
        let targets = pendingStateConnections
        pendingStateConnections.removeAll()
        for conn in targets {
            conn.send(content: payload, completion: .contentProcessed({ error in
                if let error = error {
                    print("SimulatorBridge: Failed to send state: \(error)")
                }
            }))
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
