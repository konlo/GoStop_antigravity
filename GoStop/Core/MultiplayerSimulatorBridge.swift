import Foundation
import Network

#if os(iOS)
struct MultiplayerProductRenderProbe: Encodable, Equatable {
    let route: String
    let phase: String
    let stateVersion: Int?
    let localPlayerId: String?
    let currentPlayerId: String?
    let isAutomationBusy: Bool
    let currentMoveSourceZone: String?
    let currentMoveTargetZone: String?
    let movingCardIds: [String]
    let hiddenSourceCardIds: [String]
    let hiddenTargetCardIds: [String]
    let recentUXEventTypes: [String]
    let recentUXEventCardIds: [String]
    let recentUXEventSummaries: [String]
    let sourceLocalHandCardIds: [String]
    let renderedLocalHandCardIds: [String]
    let tableCardIds: [String]
    let localCapturedCardIds: [String]
    let opponentCapturedCardIds: [String]
}

private struct MultiplayerSimulatorShellSnapshot: Encodable {
    let route: String
    let transportPlayerId: String?
    let room: MultiplayerSimulatorRoomSnapshot?
    let live: MultiplayerLiveShellState?
    let result: MultiplayerSimulatorResultSnapshot?
    let renderProbe: MultiplayerProductRenderProbe?
}

private struct MultiplayerSimulatorRoomSnapshot: Encodable {
    struct Member: Encodable {
        let playerId: String
        let seat: Int
        let role: String
        let ready: Bool
        let presence: String
        let isLocalPlayer: Bool
    }

    let roomId: String
    let roomType: String
    let joinPolicy: String
    let roomState: String
    let hostPlayerId: String
    let activeGameId: String?
    let lastRoomSequence: Int
    let inviteCode: String?
    let localPlayerId: String?
    let members: [Member]
}

private struct MultiplayerSimulatorResultSnapshot: Encodable {
    struct ScoreRow: Encodable {
        let playerId: String
        let displayName: String
        let score: Int
        let goCount: Int
        let money: Int
        let isLocalPlayer: Bool
    }

    let roundIndex: Int
    let localPlayerId: String
    let winnerPlayerId: String?
    let loserPlayerId: String?
    let endReasonCode: String
    let endReasonMessageKey: String
    let forfeitingPlayerId: String?
    let isDraw: Bool
    let leavePolicy: String
    let finalScores: [ScoreRow]
}

/// A bridge for controlling the multiplayer simulator UI from automation agents.
/// Only compiled for iOS as it depends on SwiftUI stores.
class MultiplayerSimulatorBridge {
    static var shared: MultiplayerSimulatorBridge?
    
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private let queue = DispatchQueue(label: "com.antigravity.MultiplayerSimulatorBridge")
    
    weak var store: MultiplayerShellStore?
    
    var isStarted = false
    
    init(port: UInt16) {
        do {
            self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            fatalError("Failed to create NWListener: \(error)")
        }
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("MultiplayerSimulatorBridge: Ready on port \(port)")
            case .failed(let error):
                print("MultiplayerSimulatorBridge: Failed with error: \(error)")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
    }
    
    func start() {
        guard !isStarted else { return }
        isStarted = true
        listener.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        listener.cancel()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        receiveBuffers.removeAll()
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
                print("MultiplayerSimulatorBridge: Connection error: \(error)")
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

    private func cleanup(connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
        receiveBuffers.removeValue(forKey: ObjectIdentifier(connection))
    }
    
    private func handleRequest(_ data: Data, connection: NWConnection) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else {
                sendErrorResponse(message: "Invalid request payload", connection: connection)
                return
            }
            
            gLog("MultiplayerSimulatorBridge: Received action: \(action)")
            
            switch action {
            case "get_state":
                Task { @MainActor [weak self] in
                    self?.enqueueStateResponse(connection: connection)
                }

            case "play_card_by_id":
                guard let dataDict = json["data"] as? [String: Any],
                      let cardId = dataDict["cardId"] as? String,
                      !cardId.isEmpty else {
                    sendErrorResponse(message: "Missing cardId", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self, let shell = self.store else { return }
                    shell.performGameplayActionFromAutomation(.playCard(cardId: cardId))
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }

            case "play_card":
                guard let dataDict = json["data"] as? [String: Any],
                      let monthIdx = dataDict["month"] as? Int,
                      let typeStr = dataDict["type"] as? String else {
                    sendErrorResponse(message: "Missing month or type", connection: connection)
                    return
                }
                let type = TestControlSupport.parseCardType(typeStr)
                
                Task { @MainActor [weak self] in
                    guard let self = self, let shell = self.store else { return }
                    // Use flattened shell state for automation access
                    if let card = shell.liveState.localHandCards.first(where: { $0.month == monthIdx && $0.kind == type.rawValue }) {
                        shell.performGameplayActionFromAutomation(.playCard(cardId: card.cardId))
                        self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    } else {
                        self.sendErrorResponse(message: "Card not found in hand", connection: connection)
                    }
                }
                
            case "respond_go_stop":
                guard let dataDict = json["data"] as? [String: Any],
                      let isGo = dataDict["isGo"] as? Bool else {
                    sendErrorResponse(message: "Missing isGo", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    if let store = self?.store {
                        store.performGameplayActionFromAutomation(.respondToGoStop(isGo: isGo))
                        self?.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    }
                }
                
            case "respond_to_shake":
                guard let dataDict = json["data"] as? [String: Any],
                      let didShake = dataDict["didShake"] as? Bool else {
                    sendErrorResponse(message: "Missing didShake", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    if let store = self?.store {
                        if let month = store.liveState.pendingChoice?.options
                            .flatMap(\.cards)
                            .first(where: { $0.zone == "hand" })?.month {
                            store.performGameplayActionFromAutomation(.respondToShake(month: month, didShake: didShake))
                        } else if let pendingChoice = store.liveState.pendingChoice {
                            store.submitChoiceFromLiveUI(
                                pendingChoice.choiceId,
                                optionCode: didShake ? "shake_yes" : "shake_no"
                            )
                        }
                        self?.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    }
                }
                
            case "respond_to_capture":
                guard let dataDict = json["data"] as? [String: Any],
                      let cardId = dataDict["id"] as? String else {
                    sendErrorResponse(message: "Missing id for respond_to_capture", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    if let store = self?.store {
                        store.performGameplayActionFromAutomation(.respondToCapture(cardId: cardId))
                        self?.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    }
                }

            case "respond_to_chrysanthemum_choice":
                guard let dataDict = json["data"] as? [String: Any],
                      let roleStr = dataDict["role"] as? String else {
                    sendErrorResponse(message: "Missing role", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    if let store = self?.store {
                        store.performGameplayActionFromAutomation(.respondToChrysanthemumChoice(role: roleStr))
                        self?.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    }
                }

            case "room_hello":
                guard let dataDict = json["data"] as? [String: Any],
                      let roomId = dataDict["roomId"] as? String,
                      let sessionId = dataDict["sessionId"] as? String,
                      let playerId = dataDict["playerId"] as? String,
                      let resumeToken = dataDict["resumeToken"] as? String else {
                    sendErrorResponse(message: "Missing params", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    self?.sendSimpleResponse(status: "action executed (ignored)", action: action, connection: connection)
                }

            case "click_start_button":
                Task { @MainActor [weak self] in
                    guard let self = self, let shell = self.store else { return }
                    do {
                        try await shell.setReadyUsingNetworkingAdapter(ready: true)
                        self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                    } catch {
                        self.sendErrorResponse(message: "Failed to set ready: \(error.localizedDescription)", connection: connection)
                    }
                }

            case "perform_control":
                guard let dataDict = json["data"] as? [String: Any],
                      let rawControl = dataDict["control"] as? String,
                      let control = MultiplayerShellControlAction(rawValue: rawControl) else {
                    sendErrorResponse(message: "Missing or invalid control", connection: connection)
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self, let shell = self.store else { return }
                    shell.performControl(control)
                    self.sendSimpleResponse(status: "action executed", action: action, connection: connection)
                }

            default:
                sendSimpleResponse(status: "unknown action", action: action, connection: connection)
            }
        } catch {
            gLog("MultiplayerSimulatorBridge: Failed to parse request: \(error)")
            sendErrorResponse(message: "Failed to parse request: \(error.localizedDescription)", connection: connection)
        }
    }

    @MainActor
    private func enqueueStateResponse(connection: NWConnection) {
        guard let shell = self.store else {
            sendErrorResponse(message: "No active MultiplayerShellState", connection: connection)
            return
        }

        let encoder = JSONEncoder()
        do {
            let payload = MultiplayerSimulatorShellSnapshot(
                route: shell.route.rawValue,
                transportPlayerId: shell.persistedResumeAttachRequest()?.playerId ?? shell.currentLeaveRoomRequest()?.playerId,
                room: MultiplayerSimulatorBridge.makeRoomSnapshot(shell.roomState),
                live: shell.route == .live ? shell.liveState : nil,
                result: shell.route == .result ? MultiplayerSimulatorBridge.makeResultSnapshot(shell.resultState) : nil,
                renderProbe: shell.route == .live ? shell.productRenderProbe : nil
            )
            let data = try encoder.encode(payload)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "JSON", code: 1)
            }

            let response: [String: Any] = [
                "action": "get_state",
                "status": "ok",
                "data": dict,
                "timestamp": Date().timeIntervalSince1970,
                "route": shell.route.rawValue,
                "localPlayerId": shell.liveState.localPlayerId
            ]
            self.sendJSONResponse(payload: response, connection: connection)
        } catch {
            self.sendErrorResponse(message: "Failed to encode live state: \(error.localizedDescription)", connection: connection)
        }
    }

    private static func makeRoomSnapshot(_ state: MultiplayerRoomShellState) -> MultiplayerSimulatorRoomSnapshot {
        MultiplayerSimulatorRoomSnapshot(
            roomId: state.roomId,
            roomType: state.roomType.rawValue,
            joinPolicy: state.joinPolicy.rawValue,
            roomState: state.roomState.rawValue,
            hostPlayerId: state.hostPlayerId,
            activeGameId: state.activeGameId,
            lastRoomSequence: state.lastRoomSequence,
            inviteCode: state.inviteCode,
            localPlayerId: state.members.first(where: \.isLocalPlayer)?.playerId,
            members: state.members.map {
                MultiplayerSimulatorRoomSnapshot.Member(
                    playerId: $0.playerId,
                    seat: $0.seat,
                    role: $0.role,
                    ready: $0.ready,
                    presence: $0.presence.rawValue,
                    isLocalPlayer: $0.isLocalPlayer
                )
            }
        )
    }

    private static func makeResultSnapshot(_ state: MultiplayerResultShellState) -> MultiplayerSimulatorResultSnapshot {
        MultiplayerSimulatorResultSnapshot(
            roundIndex: state.roundIndex,
            localPlayerId: state.localPlayerId,
            winnerPlayerId: state.winnerPlayerId,
            loserPlayerId: state.loserPlayerId,
            endReasonCode: state.endReasonCode,
            endReasonMessageKey: state.endReasonMessageKey,
            forfeitingPlayerId: state.forfeitingPlayerId,
            isDraw: state.isDraw,
            leavePolicy: bridgeLeavePolicyString(state.leavePolicy),
            finalScores: state.finalScores.map {
                MultiplayerSimulatorResultSnapshot.ScoreRow(
                    playerId: $0.playerId,
                    displayName: $0.displayName,
                    score: $0.score,
                    goCount: $0.goCount,
                    money: $0.money,
                    isLocalPlayer: $0.isLocalPlayer
                )
            }
        )
    }

    private static func bridgeLeavePolicyString(_ policy: MultiplayerResultLeavePolicy) -> String {
        switch policy {
        case .leaveAvailable:
            return "leaveAvailable"
        case .pendingLeaveAcknowledgement:
            return "pendingLeaveAcknowledgement"
        case .pendingRoomClosure:
            return "pendingRoomClosure"
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
}
#endif
