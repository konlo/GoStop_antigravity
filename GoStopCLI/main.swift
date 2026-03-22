import Foundation
import Network

// A CLI for Test Agent interaction.
// This reads lines of JSON from standard input, acts on the game engine, and prints JSON responses.

struct CommandRequest: Codable {
    let action: String
    let data: [String: AnyCodable]?
}

class CLIEngine {
    let gameManager = GameManager()
    lazy var roomCLIAdapter: RoomCoordinatorCLIAdapter = {
        RoomCoordinatorCLIAdapter(
            authorityRelay: RoomAuthorityRelay(
                fetchProjectionPreview: { [unowned self] request in
                    TestControlSupport.serializedMultiplayerProjectionPayload(
                        from: self.gameManager,
                        requestData: roomProjectionPreviewRequestData(from: request)
                    )
                },
                fetchGameStartedBootstrap: { [unowned self] request in
                    TestControlSupport.serializedMultiplayerGameStartedBootstrapPayload(
                        from: self.gameManager,
                        requestData: roomGameStartedBootstrapRequestData(from: request)
                    )
                },
                fetchTerminalSummary: { [unowned self] request in
                    TestControlSupport.serializedMultiplayerTerminalSummaryPayload(
                        from: self.gameManager,
                        requestData: roomTerminalSummaryRelayRequestData(from: request)
                    )
                },
                executeGameplayCommand: { [unowned self] request in
                    try self.executeRoomGameplayCommand(request)
                },
                startGameIfNeeded: { [unowned self] in
                    // Fresh room bootstrap must not reuse prior authoritative match state.
                    self.gameManager.setupGame(seed: self.currentSeed)
                    self.gameManager.startGame()
                }
            )
        )
    }()
    var currentSeed: Int? = nil
    
    func handle(request: CommandRequest) -> [String: Any] {
        if let roomResponse = roomCLIAdapter.handle(request: request) {
            return roomResponse
        }

        switch request.action {
        case "get_state":
            return TestControlSupport.serializedStatePayload(from: gameManager)

        case "get_multiplayer_projection":
            return TestControlSupport.serializedMultiplayerProjectionPayload(
                from: gameManager,
                requestData: TestControlSupport.unbox(request.data)
            )

        case "get_multiplayer_game_started_bootstrap":
            return TestControlSupport.serializedMultiplayerGameStartedBootstrapPayload(
                from: gameManager,
                requestData: TestControlSupport.unbox(request.data)
            )

        case "get_multiplayer_terminal_summary":
            return TestControlSupport.serializedMultiplayerTerminalSummaryPayload(
                from: gameManager,
                requestData: TestControlSupport.unbox(request.data)
            )
            
        case "start_game":
            gameManager.startGame()
            return ["status": "action executed", "action": "start_game"]
            
        case "play_card":
            guard let data = TestControlSupport.unbox(request.data),
                  let monthIdx = data["month"] as? Int,
                  let typeStr = data["type"] as? String else {
                return ["status": "error", "message": "Missing month or type for play_card"]
            }
            
            let type = TestControlSupport.parseCardType(typeStr)
            
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
            guard let data = TestControlSupport.unbox(request.data),
                  let isGo = data["isGo"] as? Bool else {
                return ["status": "error", "message": "Missing isGo for respond_go_stop"]
            }
            gameManager.respondToGoStop(isGo: isGo)
            return ["status": "action executed", "action": "respond_go_stop"]
            
        case "respond_to_shake":
            guard let data = TestControlSupport.unbox(request.data),
                  let monthIdx = data["month"] as? Int,
                  let didShake = data["didShake"] as? Bool else {
                return ["status": "error", "message": "Missing month or didShake for respond_to_shake"]
            }
            gameManager.respondToShake(month: monthIdx, didShake: didShake)
            return ["status": "action executed", "action": "respond_to_shake"]

        case "respond_to_capture":
            guard let data = TestControlSupport.unbox(request.data),
                  let cardId = data["id"] as? String else {
                return ["status": "error", "message": "Missing id for respond_to_capture"]
            }
            guard let tableCard = gameManager.tableCards.first(where: { $0.id == cardId }) else {
                return ["status": "error", "message": "Card with ID \(cardId) not found on table"]
            }
            gameManager.respondToCapture(selectedCard: tableCard)
            return ["status": "action executed", "action": "respond_to_capture"]
            
        case "respond_to_chrysanthemum_choice":
            guard let data = TestControlSupport.unbox(request.data),
                  let roleStr = data["role"] as? String else {
                return ["status": "error", "message": "Missing role for respond_to_chrysanthemum_choice"]
            }
            let role = TestControlSupport.parseCardRole(roleStr)
            gameManager.respondToChrysanthemumChoice(role: role)
            return ["status": "action executed", "action": "respond_to_chrysanthemum_choice"]

        case "get_persistence_probe_config":
            return [
                "status": "ok",
                "action": request.action,
                "data": TestControlSupport.persistenceProbeData()
            ]

        case "set_persistence_probe_config":
            guard let data = TestControlSupport.unbox(request.data) else {
                return ["status": "error", "message": "Missing data for set_persistence_probe_config"]
            }
            switch TestControlSupport.updatePersistenceProbeConfig(with: data) {
            case .success(let payload):
                return [
                    "status": "ok",
                    "action": request.action,
                    "data": payload
                ]
            case .failure(let error):
                let message = error.localizedDescription
                return ["status": "error", "message": message]
            }

        case "set_condition":
            if let data = TestControlSupport.unbox(request.data) {
                do {
                    try TestControlSupport.applyTestCondition(
                        data,
                        to: gameManager,
                        didUpdateSeed: { [weak self] seed in
                            self?.currentSeed = seed
                        }
                    )
                } catch {
                    return ["status": "error", "message": "Failed to apply custom_rules: \(error.localizedDescription)"]
                }
            }
            return ["status": "ok", "message": "Condition set"]
            
        case "click_restart_button":
            gameManager.setupGame(seed: currentSeed)
            return ["status": "action executed", "action": "click_restart_button"]
            
        case "mock_endgame_check":
            if let rules = RuleLoader.shared.config {
                let winner = gameManager.players[0]
                let opponent = gameManager.players[1]
                _ = gameManager.checkEndgameConditions(player: winner, opponent: opponent, rules: rules, isAfterGo: false)
            }
            return ["status": "action executed", "action": "mock_endgame_check"]

        case "reset_busy_state":
            gameManager.emergencyResetBusyState()
            return ["status": "ok", "action": "reset_busy_state"]
            
        case "force_chongtong_check":
            let timing = (request.data?["timing"]?.value as? String) ?? "initial"
            for player in gameManager.players {
                if let month = gameManager.getChongtongMonth(for: player) {
                    gameManager.resolveChongtong(player: player, month: month, timing: timing)
                }
            }
            return ["status": "action executed", "action": "force_chongtong_check"]
            
        case "invalid_action_triggering_crash":
            fatalError("Simulated App Crash for Testing")
            
        case "debug_test_dec_bug":
            gameManager.setupGame(seed: 42)
            gameManager.players[1].isComputer = true
            gameManager.tableCards = [
                Card(month: .dec, type: .bright, imageIndex: 0),
                Card(month: .dec, type: .doubleJunk, imageIndex: 3)
            ]
            let pCard = Card(month: .dec, type: .animal, imageIndex: 1)
            gameManager.players[1].hand = [pCard]
            gameManager.mockDeck(cards: [Card(month: .may, type: .junk, imageIndex: 0)])
            gameManager.currentTurnIndex = 1
            gameManager.gameState = .playing
            
            gLog("DEBUG START: Table: \(gameManager.tableCards.map{$0.type})")
            
            gameManager.playTurn(card: pCard)
            
            gLog("DEBUG AFTER PLAY: Table: \(gameManager.tableCards.map{$0.type})")
            gLog("DEBUG CAPTURED: \(gameManager.players[1].capturedCards.map{$0.type})")
            
            return ["status": "action executed", "action": request.action]
            
        default:
            return ["status": "action executed", "action": request.action]
        }
    }

    func executeRoomGameplayCommand(
        _ request: RoomAuthorityGameplayExecutionRequest
    ) throws -> RoomAuthorityGameplayExecutionResult {
        switch request.commandName {
        case .playCard:
            guard let cardId = request.commandPayload["cardId"] as? String else {
                throw roomGameplayRejection(.invalidCard, "multiplayer.reject.invalid_card")
            }
            guard let currentPlayer = gameManager.currentPlayer else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            guard currentPlayer.id.uuidString == request.playerId else {
                throw roomGameplayRejection(.outOfTurn, "multiplayer.reject.out_of_turn")
            }
            guard let card = currentPlayer.hand.first(where: { $0.id == cardId }) else {
                throw roomGameplayRejection(.invalidCard, "multiplayer.reject.invalid_card")
            }
            gameManager.playTurn(card: card)
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "cardId": cardId,
                    "source": request.commandPayload["source"] as? String ?? "hand",
                ]
            )

        case .selectCapture:
            guard let optionCode = request.commandPayload["optionCode"] as? String else {
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            guard let currentPlayer = gameManager.currentPlayer else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            guard currentPlayer.id.uuidString == request.playerId else {
                throw roomGameplayRejection(.choiceOwnerMismatch, "multiplayer.reject.choice_owner_mismatch")
            }
            guard let tableCard = gameManager.tableCards.first(where: { $0.id == optionCode }) else {
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            gameManager.respondToCapture(selectedCard: tableCard)
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "choiceId": request.commandPayload["choiceId"] as? String ?? "",
                    "optionCode": optionCode,
                ]
            )

        case .selectShake:
            guard let optionCode = request.commandPayload["optionCode"] as? String,
                  let month = request.commandPayload["month"] as? Int else {
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            guard let currentPlayer = gameManager.currentPlayer else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            guard currentPlayer.id.uuidString == request.playerId else {
                throw roomGameplayRejection(.choiceOwnerMismatch, "multiplayer.reject.choice_owner_mismatch")
            }
            let didShake = optionCode == "shake_yes"
            gameManager.respondToShake(month: month, didShake: didShake)
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "choiceId": request.commandPayload["choiceId"] as? String ?? "",
                    "optionCode": optionCode,
                ]
            )

        case .chooseGoStop:
            guard let optionCode = request.commandPayload["optionCode"] as? String else {
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            guard let currentPlayer = gameManager.currentPlayer else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            guard currentPlayer.id.uuidString == request.playerId else {
                throw roomGameplayRejection(.choiceOwnerMismatch, "multiplayer.reject.choice_owner_mismatch")
            }
            switch optionCode {
            case "go":
                gameManager.respondToGoStop(isGo: true)
            case "stop":
                gameManager.respondToGoStop(isGo: false)
            default:
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "choiceId": request.commandPayload["choiceId"] as? String ?? "",
                    "optionCode": optionCode,
                ]
            )

        case .chooseChrysanthemumRole:
            guard let optionCode = request.commandPayload["optionCode"] as? String else {
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            guard let currentPlayer = gameManager.currentPlayer else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            guard currentPlayer.id.uuidString == request.playerId else {
                throw roomGameplayRejection(.choiceOwnerMismatch, "multiplayer.reject.choice_owner_mismatch")
            }
            switch optionCode {
            case CardRole.animal.rawValue:
                gameManager.respondToChrysanthemumChoice(role: .animal)
            case CardRole.doublePi.rawValue:
                gameManager.respondToChrysanthemumChoice(role: .doublePi)
            default:
                throw roomGameplayRejection(.invalidChoice, "multiplayer.reject.invalid_choice")
            }
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "choiceId": request.commandPayload["choiceId"] as? String ?? "",
                    "optionCode": optionCode,
                ]
            )

        case .resume:
            throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")

        case .quit:
            let quitReasonRaw = (request.commandPayload["reason"] as? String) ?? MultiplayerQuitReason.voluntaryExit.rawValue
            guard let quitReason = MultiplayerQuitReason(rawValue: quitReasonRaw) else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state", retryable: false)
            }
            guard gameManager.players.contains(where: { $0.id.uuidString == request.playerId }),
                  gameManager.multiplayerMatchEndedPayload(
                    quitReason: quitReason,
                    forfeitingPlayerId: request.playerId
                  ) != nil else {
                throw roomGameplayRejection(.invalidState, "multiplayer.reject.invalid_state")
            }
            return RoomAuthorityGameplayExecutionResult(
                result: [
                    "quitReason": quitReason.rawValue,
                ]
            )
        }
    }

    private func roomGameplayRejection(
        _ code: MultiplayerRejectCode,
        _ messageKey: String,
        retryable: Bool = true
    ) -> RoomAuthorityGameplayRejection {
        RoomAuthorityGameplayRejection(
            code: code,
            retryable: retryable,
            messageKey: messageKey
        )
    }

    func handlePassiveTransportTeardown(
        clientId: String,
        expectedConnectionId: String?
    ) -> [String: Any]? {
        roomCLIAdapter.handlePassiveTransportTeardown(
            clientId: clientId,
            expectedConnectionId: expectedConnectionId
        )
    }

    func handleAutomaticTransportExpirySweep(asOf: Date) throws -> Int {
        try roomCLIAdapter.handleTransportExpirySweep(asOf: asOf).count
    }
}

private struct RoomTransportServerBindingUpdate {
    var clientId: String
    var logicalConnectionId: String?
}

private final class RoomTransportServerRuntime {
    private let engine: CLIEngine
    private let decoder = JSONDecoder()
    private var clientIDsByConnection: [ObjectIdentifier: Set<String>] = [:]
    private var activeConnectionKeyByClientID: [String: ObjectIdentifier] = [:]
    private var activeLogicalConnectionIDByClientID: [String: String] = [:]
    private var automaticExpiryTimer: DispatchSourceTimer?

    init(engine: CLIEngine) {
        self.engine = engine
    }

    func startAutomaticExpirySweep(on queue: DispatchQueue) {
        guard automaticExpiryTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.runAutomaticExpirySweep()
        }
        automaticExpiryTimer = timer
        timer.resume()
    }

    func handlePacket(_ data: Data, on connection: NWConnection) -> [String: Any] {
        do {
            let request = try decoder.decode(CommandRequest.self, from: data)
            let response = engine.handle(request: request)
            if isSuccessful(response),
               let binding = bindingUpdate(from: request) {
                register(binding: binding, for: ObjectIdentifier(connection))
            }
            return response
        } catch {
            return [
                "status": "error",
                "errorCode": "invalidPayload",
                "message": error.localizedDescription,
            ]
        }
    }

    func handleConnectionClosed(_ connection: NWConnection) {
        let connectionKey = ObjectIdentifier(connection)
        let clientIDs = Array(clientIDsByConnection[connectionKey] ?? []).sorted()
        for clientID in clientIDs {
            if activeConnectionKeyByClientID[clientID] == connectionKey {
                _ = engine.handlePassiveTransportTeardown(
                    clientId: clientID,
                    expectedConnectionId: activeLogicalConnectionIDByClientID[clientID]
                )
                activeConnectionKeyByClientID.removeValue(forKey: clientID)
                activeLogicalConnectionIDByClientID.removeValue(forKey: clientID)
            }
        }
        clientIDsByConnection.removeValue(forKey: connectionKey)
    }

    private func register(
        binding: RoomTransportServerBindingUpdate,
        for connectionKey: ObjectIdentifier
    ) {
        clientIDsByConnection[connectionKey, default: []].insert(binding.clientId)
        if let logicalConnectionId = binding.logicalConnectionId {
            activeConnectionKeyByClientID[binding.clientId] = connectionKey
            activeLogicalConnectionIDByClientID[binding.clientId] = logicalConnectionId
        }
    }

    private func bindingUpdate(from request: CommandRequest) -> RoomTransportServerBindingUpdate? {
        switch request.action {
        case "room_transport_connect":
            guard let clientId = stringValue(for: "clientId", in: request.data) else {
                return nil
            }
            return RoomTransportServerBindingUpdate(
                clientId: clientId,
                logicalConnectionId: nil
            )
        case "room_transport_send":
            guard let clientId = stringValue(for: "clientId", in: request.data) else {
                return nil
            }
            let transportAction = stringValue(for: "action", in: request.data)
            let logicalConnectionId = transportAction == "hello"
                ? stringValue(for: "connectionId", in: request.data)
                : nil
            return RoomTransportServerBindingUpdate(
                clientId: clientId,
                logicalConnectionId: logicalConnectionId
            )
        case "room_transport_receive":
            guard let clientId = stringValue(for: "clientId", in: request.data) else {
                return nil
            }
            return RoomTransportServerBindingUpdate(
                clientId: clientId,
                logicalConnectionId: nil
            )
        default:
            return nil
        }
    }

    private func stringValue(
        for key: String,
        in data: [String: AnyCodable]?
    ) -> String? {
        data?[key]?.value as? String
    }

    private func isSuccessful(_ response: [String: Any]) -> Bool {
        (response["status"] as? String) != "error"
    }

    private func runAutomaticExpirySweep() {
        do {
            let mutationCount = try engine.handleAutomaticTransportExpirySweep(asOf: Date())
            if mutationCount > 0 {
                writeStderr("RoomTransportServerRuntime automatic expiry applied mutations=\(mutationCount)\n")
            }
        } catch {
            writeStderr("RoomTransportServerRuntime automatic expiry failed: \(error)\n")
        }
    }
}

final class RoomTransportTCPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.antigravity.GoStopCLI.RoomTransportTCPServer")
    private let runtime: RoomTransportServerRuntime
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]

    init(engine: CLIEngine, port: UInt16) throws {
        self.runtime = RoomTransportServerRuntime(engine: engine)
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "RoomTransportTCPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }
        self.listener = try NWListener(using: .tcp, on: port)
    }

    func start() {
        runtime.startAutomaticExpirySweep(on: queue)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                writeStderr("RoomTransportTCPServer ready\n")
            case .failed(let error):
                writeStderr("RoomTransportTCPServer failed: \(error)\n")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.start(queue: queue)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveBuffers[ObjectIdentifier(connection)] = Data()
        receive(connection: connection)
    }

    private func receive(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.cleanup(connection: connection)
                writeStderr("RoomTransportTCPServer connection error: \(error)\n")
                return
            }
            if let content, !content.isEmpty {
                self.appendAndHandleRequests(content, connection: connection)
            }
            if isComplete {
                self.cleanup(connection: connection)
            } else {
                self.receive(connection: connection)
            }
        }
    }

    private func appendAndHandleRequests(_ data: Data, connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        var buffer = receiveBuffers[key] ?? Data()
        buffer.append(data)

        let newline = Data([0x0A])
        while let lineRange = buffer.range(of: newline) {
            let packet = buffer.subdata(in: 0..<lineRange.lowerBound)
            buffer.removeSubrange(0...lineRange.lowerBound)
            guard !packet.isEmpty else { continue }
            handlePacket(packet, connection: connection)
        }

        receiveBuffers[key] = buffer
    }

    private func handlePacket(_ data: Data, connection: NWConnection) {
        let payload = runtime.handlePacket(data, on: connection)
        send(payload: payload, connection: connection)
    }

    private func send(payload: [String: Any], connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let newlineData = "\n".data(using: .utf8) else {
            return
        }
        connection.send(content: jsonData + newlineData, completion: .contentProcessed { _ in })
    }

    private func cleanup(connection: NWConnection) {
        runtime.handleConnectionClosed(connection)
        receiveBuffers.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }
}

protocol RoomTransportServer {
    func start()
}

extension RoomTransportTCPServer: RoomTransportServer {}

final class RoomTransportWebSocketServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.antigravity.GoStopCLI.RoomTransportWebSocketServer")
    private let runtime: RoomTransportServerRuntime
    private var pendingPayloadsByConnection: [ObjectIdentifier: [Data]] = [:]
    private var sendingConnections: Set<ObjectIdentifier> = []

    init(engine: CLIEngine, port: UInt16) throws {
        writeStderr("RoomTransportWebSocketServer initializing on port \(port)...\n")
        self.runtime = RoomTransportServerRuntime(engine: engine)
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "RoomTransportWebSocketServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
        parameters.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: parameters, on: port)
        writeStderr("RoomTransportWebSocketServer listener created.\n")
    }

    func start() {
        writeStderr("RoomTransportWebSocketServer starting queue and listener...\n")
        runtime.startAutomaticExpirySweep(on: queue)
        listener.stateUpdateHandler = { state in
            writeStderr("RoomTransportWebSocketServer state changed to: \(state)\n")
            switch state {
            case .ready:
                writeStderr("RoomTransportWebSocketServer ready and listening.\n")
            case .failed(let error):
                writeStderr("RoomTransportWebSocketServer failed: \(error)\n")
            case .waiting(let error):
                writeStderr("RoomTransportWebSocketServer waiting: \(error)\n")
            case .setup:
                writeStderr("RoomTransportWebSocketServer in setup.\n")
            case .cancelled:
                writeStderr("RoomTransportWebSocketServer cancelled.\n")
            @unknown default:
                writeStderr("RoomTransportWebSocketServer unknown state.\n")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            writeStderr("RoomTransportWebSocketServer new connection received.\n")
            self?.handleNewConnection(connection)
        }
        listener.start(queue: queue)
        writeStderr("RoomTransportWebSocketServer listener.start() called.\n")
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                writeStderr("RoomTransportWebSocketServer connection failed: \(error)\n")
            }
        }
        connection.start(queue: queue)
        pendingPayloadsByConnection[ObjectIdentifier(connection)] = []
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            if let error {
                self.cleanup(connection: connection)
                writeStderr("RoomTransportWebSocketServer connection error: \(error)\n")
                return
            }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                self.cleanup(connection: connection)
                return
            }

            if let content, !content.isEmpty {
                let payload = self.runtime.handlePacket(content, on: connection)
                self.enqueue(payload: payload, connection: connection)
            }
            self.receiveMessage(on: connection)
        }
    }

    private func enqueue(payload: [String: Any], connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        let key = ObjectIdentifier(connection)
        pendingPayloadsByConnection[key, default: []].append(jsonData)
        flushPendingPayloads(for: connection)
    }

    private func flushPendingPayloads(for connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        guard !sendingConnections.contains(key),
              let nextPayload = pendingPayloadsByConnection[key]?.first else {
            return
        }
        sendingConnections.insert(key)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "roomTransport", metadata: [metadata])
        connection.send(content: nextPayload, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.sendingConnections.remove(key)
            self.pendingPayloadsByConnection[key]?.removeFirst()
            if let error {
                writeStderr("RoomTransportWebSocketServer send error: \(error)\n")
                self.cleanup(connection: connection)
                return
            }
            self.flushPendingPayloads(for: connection)
        })
    }

    private func cleanup(connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        runtime.handleConnectionClosed(connection)
        pendingPayloadsByConnection.removeValue(forKey: key)
        sendingConnections.remove(key)
        connection.cancel()
    }
}

extension RoomTransportWebSocketServer: RoomTransportServer {}

enum RoomTransportServerMode {
    case websocket(UInt16)
    case tcp(UInt16)
}

func main() {
    // Explicitly load rules at startup
    RuleLoader.shared.loadRules()

    // CLI is used by automated scenarios; run turn logic synchronously to avoid
    // animation-delay race conditions during state assertions.
    AnimationManager.shared.config.card_move_duration = 0
    AnimationManager.shared.config.capture_to_player_duration = 0
    AnimationManager.shared.config.deck_to_table_duration = 0
    AnimationManager.shared.config.table_to_captured_duration = 0
    AnimationManager.shared.config.captured_to_captured_duration = 0
    AnimationManager.shared.config.deck_to_table_motion = "instant"
    AnimationManager.shared.config.table_to_captured_motion = "instant"
    AnimationManager.shared.config.captured_to_captured_motion = "instant"
    AnimationManager.shared.config.match_pause_duration = 0
    AnimationManager.shared.config.opponent_preplay_reveal_duration = 0
    AnimationManager.shared.config.opponent_action_delay = 0
    
    writeStderr("Initializing CLIEngine...\n")
    let engine = CLIEngine()
    writeStderr("CLIEngine initialized.\n")
    let args = CommandLine.arguments
    if let mode = configuredRoomTransportServerMode(from: args) {
        do {
            writeStderr("Creating room transport server...\n")
            let server = try makeRoomTransportServer(mode: mode, engine: engine)
            writeStderr("Starting room transport server...\n")
            server.start()
            writeStderr("Entering main RunLoop...\n")
            RunLoop.main.run()
            return
        } catch {
            writeStderr("Failed to start room transport server: \(error)\n")
            exit(1)
        }
    }
    
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

private func configuredRoomTransportServerMode(from arguments: [String]) -> RoomTransportServerMode? {
    if let port = transportWebSocketServerPort(from: arguments) {
        return .websocket(port)
    }
    if let port = transportServerPort(from: arguments) {
        return .tcp(port)
    }
    return nil
}

private func makeRoomTransportServer(
    mode: RoomTransportServerMode,
    engine: CLIEngine
) throws -> RoomTransportServer {
    switch mode {
    case .websocket(let port):
        return try RoomTransportWebSocketServer(engine: engine, port: port)
    case .tcp(let port):
        return try RoomTransportTCPServer(engine: engine, port: port)
    }
}

private func transportWebSocketServerPort(from arguments: [String]) -> UInt16? {
    if let inlineArgument = arguments.first(where: { $0.hasPrefix("--room-transport-websocket-server=") }) {
        return UInt16(inlineArgument.split(separator: "=").last ?? "")
    }
    guard arguments.contains("--room-transport-websocket-server") else {
        return nil
    }
    if let portIndex = arguments.firstIndex(of: "--port"),
       arguments.indices.contains(portIndex + 1),
       let port = UInt16(arguments[portIndex + 1]) {
        return port
    }
    return 9092
}

private func transportServerPort(from arguments: [String]) -> UInt16? {
    if let inlineArgument = arguments.first(where: { $0.hasPrefix("--room-transport-server=") }) {
        return UInt16(inlineArgument.split(separator: "=").last ?? "")
    }
    guard arguments.contains("--room-transport-server") else {
        return nil
    }
    if let portIndex = arguments.firstIndex(of: "--port"),
       arguments.indices.contains(portIndex + 1),
       let port = UInt16(arguments[portIndex + 1]) {
        return port
    }
    return 9091
}

private func handleCommandPacket(_ data: Data, engine: CLIEngine) -> [String: Any] {
    do {
        let request = try JSONDecoder().decode(CommandRequest.self, from: data)
        return engine.handle(request: request)
    } catch {
        return [
            "status": "error",
            "errorCode": "invalidPayload",
            "message": error.localizedDescription,
        ]
    }
}

private func writeStderr(_ message: String) {
    guard let data = message.data(using: .utf8) else {
        return
    }
    FileHandle.standardError.write(data)
}

main()
