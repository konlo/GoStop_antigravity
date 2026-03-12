import SwiftUI

private enum MultiplayerShellDateFormatting {
    static let full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum MultiplayerShellRoute: String {
    case entry
    case room
    case live
    case result

    var label: String {
        switch self {
        case .entry:
            return "Entry"
        case .room:
            return "Room"
        case .live:
            return "Live"
        case .result:
            return "Result"
        }
    }
}

enum MultiplayerShellControlAction: String {
    case createRoom
    case joinGuest
    case leaveRoom
    case ready
    case guestReady
    case disconnect
    case resume
    case heartbeat
    case expireReconnect
    case applyGameStarted
    case applyMatchEnded
    case showResult
    case playFirstCard
    case submitFirstChoice
    case quitMatch
}

struct MultiplayerShellControl: Identifiable {
    let action: MultiplayerShellControlAction
    let title: String
    let accentColor: Color

    var id: String { action.rawValue + ":" + title }
}

struct MultiplayerShellStatusItem: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

@MainActor
protocol MultiplayerShellSource: AnyObject {
    var label: String { get }
    var descriptionText: String { get }
    var statusItems: [MultiplayerShellStatusItem] { get }

    func visibleEntryActions() -> [MultiplayerEntryAction]
    func attach(store: MultiplayerShellStore)
    func detach()
    func reset()
    func handleEntryAction(_ action: MultiplayerEntryAction)
    func handleControlAction(_ action: MultiplayerShellControlAction)
    func visibleControls() -> [MultiplayerShellControl]
    func updateEntryJoinIdentifier(_ joinIdentifier: String?)
}

extension MultiplayerShellSource {
    func updateEntryJoinIdentifier(_ joinIdentifier: String?) {}
}

struct MultiplayerRoomClosedPayload {
    let roomId: String
    let reasonCode: String
    let messageKey: String
    let closedAt: String?
}

struct MultiplayerLeaveAcknowledgementPayload {
    let roomId: String
    let playerId: String
    let roomState: MultiplayerRoomLifecycle
    let messageKey: String
    let roomClosed: MultiplayerRoomClosedPayload?
}

struct MultiplayerShellAttachRequest {
    let roomId: String
    let sessionId: String
    let playerId: String
    let deviceId: String
    let resumeToken: String
    let connectionId: String?
}

struct MultiplayerShellLeaveRoomRequest {
    let roomId: String
    let playerId: String
}

struct MultiplayerShellCreateRoomRequest {
    let hostPlayerId: String
    let deviceId: String
    let roomType: MultiplayerRoomType
    let joinPolicy: MultiplayerJoinPolicy
}

struct MultiplayerShellJoinRoomRequest {
    let roomId: String
    let playerId: String
    let deviceId: String
}

struct MultiplayerShellReadyRequest {
    let roomId: String
    let playerId: String
    let ready: Bool
}

enum MultiplayerShellInboundEvent {
    case helloAck(MultiplayerHelloAckShellPayload)
    case roomSnapshot(MultiplayerRoomSnapshotPayload)
    case gameSnapshot(MultiplayerSnapshot, serverTime: String?)
    case turnChanged(MultiplayerTurnChangedPayload, serverTime: String?)
    case actionRejected(MultiplayerActionRejectedPayload)
    case matchEnded(roundEnded: MultiplayerRoundEndedPayload?, matchEnded: MultiplayerMatchEndedPayload)
    case roomClosed(MultiplayerRoomClosedPayload)
    case leaveAcknowledged(MultiplayerLeaveAcknowledgementPayload)
}

enum MultiplayerShellRuntimeError: LocalizedError {
    case notImplemented(String)
    case invalidBoundaryState(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let capability):
            return "\(capability) is not wired into the app shell yet."
        case .invalidBoundaryState(let detail):
            return detail
        }
    }
}

func multiplayerShellFallbackText(for key: String) -> String? {
    switch key {
    case "entry.action.unavailable":
        return "This multiplayer entry action is not available in the current transport route."
    case "entry.resume.transport_unavailable":
        return "The transport source is not ready to create, join, or resume right now."
    case "match.end.disconnect_timeout":
        return "Reconnect grace expired, so the match ended on disconnect timeout."
    case "match.result.leave.ready":
        return "Leave the retained result room when you are finished reading."
    case "match.result.leave.pending":
        return "leaveRoom was sent. Waiting for the authoritative completion signal."
    case "match.result.leave.wait_room_closed":
        return "The local session already left. Waiting for the final roomClosed signal."
    case "match.result.leave.acknowledged":
        return "The room lifecycle acknowledged the local leave request."
    case "match.result.leave.completed_by_room_closed":
        return "The leave completed because the room closed immediately afterward."
    case "match.result.leave.transport_error":
        return "The leave request could not complete over the current transport source."
    case "room.closed.hostLeft":
        return "The host left after result delivery, so the room closed."
    case "room.closed.allPlayersLeft":
        return "All players left the retained result room, so the room closed."
    case "room.closed.resultExpired":
        return "Result retention expired and the room closed."
    case "room.closed.explicitClose":
        return "The room was explicitly closed after result delivery."
    case "room.closed.idleExpired":
        return "The room expired after staying idle too long."
    case "room.closed.bootstrapFailed":
        return "The room closed because bootstrap completion failed."
    case "match.choice.shake.actor_only_waiting":
        return "The opponent is deciding whether to shake."
    case "match.reject.stale_state_version":
        return "The action targeted an older board version. Wait for the authoritative resync."
    case "match.reject.action_id_conflict":
        return "That actionId was reused with different command data and was rejected."
    default:
        if key.hasPrefix("match.end.") {
            return "The match ended for an authoritative server reason."
        }
        if key.hasPrefix("match.result.leave.") {
            return "Result dismissal is waiting on authoritative leave lifecycle completion."
        }
        if key.hasPrefix("room.closed.") {
            return "The room closed after the authoritative lifecycle finished."
        }
        if key.hasPrefix("match.reject.") {
            return "The authoritative server rejected the action."
        }
        return nil
    }
}

func multiplayerShellText(_ key: String, fallback: String) -> String {
    let resolved = gameText(key)
    if resolved != key {
        return resolved
    }
    return multiplayerShellFallbackText(for: key) ?? fallback
}

func multiplayerShellText(_ key: String?) -> String? {
    guard let key else { return nil }
    let resolved = gameText(key)
    if resolved != key {
        return resolved
    }
    return multiplayerShellFallbackText(for: key)
}

func multiplayerShellRenderableNote(_ note: String) -> String {
    let resolved = gameText(note)
    if resolved != note {
        return resolved
    }
    return multiplayerShellFallbackText(for: note) ?? note
}

protocol MultiplayerSessionPersisting: AnyObject {
    var label: String { get }
    func loadPersistedSession() -> MultiplayerPersistedSessionSummary?
    func savePersistedSession(_ summary: MultiplayerPersistedSessionSummary)
    func clearPersistedSession()
}

final class MultiplayerUserDefaultsSessionPersistence: MultiplayerSessionPersisting {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "multiplayer.shell.persisted-session"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    var label: String { "UserDefaults" }

    func loadPersistedSession() -> MultiplayerPersistedSessionSummary? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MultiplayerPersistedSessionSummary.self, from: data)
    }

    func savePersistedSession(_ summary: MultiplayerPersistedSessionSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clearPersistedSession() {
        defaults.removeObject(forKey: storageKey)
    }
}

protocol MultiplayerShellNetworkingAdapter: AnyObject {
    var label: String { get }
    func connect(using request: MultiplayerShellAttachRequest) async throws
    func resume(using request: MultiplayerShellAttachRequest) async throws
    func sendLeaveRoom(_ request: MultiplayerShellLeaveRoomRequest) async throws
    func nextBufferedEvent() async throws -> MultiplayerShellInboundEvent?
}

protocol MultiplayerShellRoomLifecycleNetworkingAdapter: MultiplayerShellNetworkingAdapter {
    func createRoomBootstrap(_ request: MultiplayerShellCreateRoomRequest) async throws -> MultiplayerShellAttachRequest
    func joinRoomBootstrap(_ request: MultiplayerShellJoinRoomRequest) async throws -> MultiplayerShellAttachRequest
    func setReady(_ request: MultiplayerShellReadyRequest) async throws
    func requestRoomSnapshot(roomId: String) async throws
    func recordGameStarted(roomId: String, gameId: String?) async throws
    func recordMatchEnded(
        roomId: String,
        roundIndex: Int?,
        quitReason: String?,
        forfeitingPlayerId: String?
    ) async throws
}

struct MultiplayerShellGameplayCommandContext {
    let roomId: String
    let gameId: String
    let playerId: String
    let actionId: String
    let expectedStateVersion: Int
    let requestId: String?
    let traceId: String?
}

struct MultiplayerShellPlayCardRequest {
    let context: MultiplayerShellGameplayCommandContext
    let cardId: String
    let source: String
}

struct MultiplayerShellSubmitChoiceRequest {
    let context: MultiplayerShellGameplayCommandContext
    let choiceId: String
    let optionCode: String
    let choiceCommandName: String?
}

struct MultiplayerShellQuitRequest {
    let context: MultiplayerShellGameplayCommandContext
    let reasonCode: String
}

// Future live gameplay commands must reuse the same inbound event path so exact replay
// and actionId conflict handling stay aligned with Agent 2 transport semantics.
protocol MultiplayerShellGameplayNetworkingAdapter: MultiplayerShellNetworkingAdapter {
    func playCard(_ request: MultiplayerShellPlayCardRequest) async throws
    func submitChoice(_ request: MultiplayerShellSubmitChoiceRequest) async throws
    func quit(_ request: MultiplayerShellQuitRequest) async throws
}

protocol MultiplayerShellResettableNetworkingAdapter: AnyObject {
    func resetTransportState() async
}

protocol MultiplayerShellTransportEnvelopeIngesting: AnyObject {
    func ingestTransportEnvelope(data: Data) throws
    func ingestTransportEnvelope(jsonObject: [String: Any]) throws
}

final class MultiplayerNoopNetworkingAdapter: MultiplayerShellNetworkingAdapter {
    var label: String { "TODO" }

    func connect(using request: MultiplayerShellAttachRequest) async throws {
        throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellNetworkingAdapter.connect")
    }

    func resume(using request: MultiplayerShellAttachRequest) async throws {
        throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellNetworkingAdapter.resume")
    }

    func sendLeaveRoom(_ request: MultiplayerShellLeaveRoomRequest) async throws {
        throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellNetworkingAdapter.sendLeaveRoom")
    }

    func nextBufferedEvent() async throws -> MultiplayerShellInboundEvent? {
        nil
    }
}

struct MultiplayerShellTransportOptions {
    let endpointURL: URL

    static let labDefault = MultiplayerShellTransportOptions(
        endpointURL: defaultEndpointURL()
    )

    static let productDefault = MultiplayerShellTransportOptions(
        endpointURL: defaultEndpointURL()
    )

    static func defaultEndpointURL() -> URL {
        if let rawValue = ProcessInfo.processInfo.environment["GOSTOP_MP_TRANSPORT_URL"],
           let url = URL(string: rawValue) {
            return url
        }
        return URL(string: "ws://127.0.0.1:9092")!
    }

    var endpointLabel: String {
        let host = endpointURL.host ?? endpointURL.absoluteString
        if let port = endpointURL.port {
            return "\(host):\(port)"
        }
        return host
    }
}

enum MultiplayerTransportMountMode: Equatable {
    case labPreview
    case productPreparation(inviteCode: String? = nil)

    var statusLabel: String {
        switch self {
        case .labPreview:
            return "Lab"
        case .productPreparation:
            return "Product Route"
        }
    }

    var exposesPeerDebugControls: Bool {
        switch self {
        case .labPreview:
            return true
        case .productPreparation:
            return false
        }
    }

    var pendingInviteCode: String? {
        switch self {
        case .labPreview:
            return nil
        case .productPreparation(let inviteCode):
            return inviteCode
        }
    }

    func descriptionText(endpointURL: URL) -> String {
        switch self {
        case .labPreview:
            return "Transport-backed shell route mounted on Agent 2 websocket command frames. MP Lab uses this same boundary, but the source itself is no longer lab-only. Endpoint: \(endpointURL.absoluteString)."
        case .productPreparation(let inviteCode):
            if let inviteCode {
                return "Future product entry can mount this transport route directly. Create, join, resume, and authoritative result dismissal all stay on helloAck, roomSnapshot, leaveAcknowledged, and roomClosed. Pending inviteCode: \(inviteCode). Phase 0 keeps inviteCode == roomId. Endpoint: \(endpointURL.absoluteString)."
            }
            return "Future product entry can mount this transport route directly. Create, resume, and authoritative result dismissal already stay on helloAck, roomSnapshot, leaveAcknowledged, and roomClosed. Join Invite remains hidden until an outer route or local product entry input provides inviteCode. Endpoint: \(endpointURL.absoluteString)."
        }
    }

    var resetBannerTitle: String {
        switch self {
        case .labPreview:
            return "Transport Boundary Ready"
        case .productPreparation:
            return "Product Transport Route Ready"
        }
    }

    var resetBannerDetail: String {
        switch self {
        case .labPreview:
            return "Create Room will hit the Agent 2 websocket command server, then attach through helloAck -> roomSnapshot. `GOSTOP_MP_TRANSPORT_URL` overrides the default endpoint."
        case .productPreparation(let inviteCode):
            if let inviteCode {
                return "This route is ready for product create/join/resume wiring. Join Invite will use inviteCode \(inviteCode), which Phase 0 resolves as the roomId alias, and still wait for helloAck -> roomSnapshot before entering the room."
            }
            return "This route is ready for product create/resume wiring. Join Invite stays hidden until the outer app route or entry input supplies inviteCode."
        }
    }
}

struct MultiplayerTransportRouteConfiguration {
    let mode: MultiplayerTransportMountMode
    let transportOptions: MultiplayerShellTransportOptions
    let persistenceStorageKey: String
    let hostClientId: String

    static let lab = MultiplayerTransportRouteConfiguration(
        mode: .labPreview,
        transportOptions: .labDefault,
        persistenceStorageKey: "multiplayer.shell.transport.persisted-session",
        hostClientId: "ios_transport_lab_host"
    )

    static func productPreparation(inviteCode: String? = nil) -> MultiplayerTransportRouteConfiguration {
        MultiplayerTransportRouteConfiguration(
            mode: .productPreparation(inviteCode: inviteCode),
            transportOptions: .productDefault,
            persistenceStorageKey: "multiplayer.shell.product.persisted-session",
            hostClientId: "ios_transport_product_route"
        )
    }
}

private struct MultiplayerShellTransportCursor {
    var roomSequence: Int?
    var gameEventId: String?
    var stateVersion: Int?

    var payload: [String: Any]? {
        guard roomSequence != nil || gameEventId != nil || stateVersion != nil else {
            return nil
        }
        var payload: [String: Any] = [:]
        if let roomSequence {
            payload["roomSequence"] = roomSequence
        }
        if let gameEventId {
            payload["gameEventId"] = gameEventId
        }
        if let stateVersion {
            payload["stateVersion"] = stateVersion
        }
        return payload
    }

    mutating func update(from envelope: [String: Any]) {
        if let roomSequence = envelope["roomSequence"] as? Int {
            self.roomSequence = max(self.roomSequence ?? roomSequence, roomSequence)
        } else if let roomSequence = envelope["roomSequence"] as? NSNumber {
            self.roomSequence = max(self.roomSequence ?? roomSequence.intValue, roomSequence.intValue)
        }

        guard let type = envelope["type"] as? String else {
            return
        }
        switch type {
        case "gameEvent":
            guard let payload = envelope["payload"] as? [String: Any],
                  let engineEvent = payload["engineEvent"] as? [String: Any] else {
                return
            }
            if let eventId = engineEvent["eventId"] as? String {
                gameEventId = eventId
            }
            if let stateVersion = engineEvent["stateVersion"] as? Int {
                self.stateVersion = max(self.stateVersion ?? stateVersion, stateVersion)
            } else if let stateVersion = engineEvent["stateVersion"] as? NSNumber {
                let value = stateVersion.intValue
                self.stateVersion = max(self.stateVersion ?? value, value)
            }
        case "terminalSummary":
            guard let payload = envelope["payload"] as? [String: Any],
                  let matchEnded = payload["matchEnded"] as? [String: Any] else {
                return
            }
            if let stateVersion = matchEnded["summaryStateVersion"] as? Int {
                self.stateVersion = max(self.stateVersion ?? stateVersion, stateVersion)
            } else if let stateVersion = matchEnded["summaryStateVersion"] as? NSNumber {
                let value = stateVersion.intValue
                self.stateVersion = max(self.stateVersion ?? value, value)
            }
        default:
            return
        }
    }
}

private struct MultiplayerShellTransportCommandError: LocalizedError {
    let action: String
    let code: String
    let message: String

    var errorDescription: String? {
        "\(action) failed (\(code)): \(message)"
    }
}

private actor MultiplayerCommandFrameWebSocketClient {
    private let endpointURL: URL
    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?

    init(endpointURL: URL) {
        self.endpointURL = endpointURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    func invalidate() {
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
    }

    func sendCommand(action: String, data: [String: Any]) async throws -> [String: Any] {
        let socketTask = makeSocketTask()
        let payload: [String: Any] = [
            "action": action,
            "data": data
        ]
        let rawData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let rawString = String(data: rawData, encoding: .utf8) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Failed to encode websocket command \(action).")
        }

        do {
            try await socketTask.send(.string(rawString))
            return try await receiveCommandResponse(from: socketTask, action: action)
        } catch {
            invalidate()
            throw error
        }
    }

    private func makeSocketTask() -> URLSessionWebSocketTask {
        if let socketTask {
            return socketTask
        }
        let socketTask = session.webSocketTask(with: endpointURL)
        socketTask.resume()
        self.socketTask = socketTask
        return socketTask
    }

    private func receiveCommandResponse(
        from socketTask: URLSessionWebSocketTask,
        action: String
    ) async throws -> [String: Any] {
        let message = try await socketTask.receive()
        let data: Data
        switch message {
        case .string(let string):
            data = Data(string.utf8)
        case .data(let rawData):
            data = rawData
        @unknown default:
            throw MultiplayerShellRuntimeError.invalidBoundaryState(
                "Unsupported websocket response while waiting for \(action)."
            )
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let response = jsonObject as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState(
                "Websocket response for \(action) must be an object."
            )
        }
        let status = response["status"] as? String ?? "error"
        guard status == "ok" else {
            throw MultiplayerShellTransportCommandError(
                action: action,
                code: response["errorCode"] as? String ?? "transportError",
                message: response["message"] as? String ?? "Unknown websocket command failure."
            )
        }
        guard let data = response["data"] as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState(
                "Websocket response for \(action) is missing a data object."
            )
        }
        return data
    }
}

final class MultiplayerWebSocketCommandNetworkingAdapter:
    MultiplayerShellRoomLifecycleNetworkingAdapter,
    MultiplayerShellGameplayNetworkingAdapter,
    MultiplayerShellTransportEnvelopeIngesting,
    MultiplayerShellResettableNetworkingAdapter {

    let label: String

    private let options: MultiplayerShellTransportOptions
    private let clientId: String
    private let webSocketClient: MultiplayerCommandFrameWebSocketClient
    private var latestAttachRequest: MultiplayerShellAttachRequest?
    private var bufferedEvents: [MultiplayerShellInboundEvent] = []
    private var cursor = MultiplayerShellTransportCursor()

    init(
        options: MultiplayerShellTransportOptions = .labDefault,
        clientId: String = "ios_shell_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    ) {
        self.options = options
        self.clientId = clientId
        self.webSocketClient = MultiplayerCommandFrameWebSocketClient(endpointURL: options.endpointURL)
        self.label = "WS \(options.endpointLabel)"
    }

    func createRoomBootstrap(_ request: MultiplayerShellCreateRoomRequest) async throws -> MultiplayerShellAttachRequest {
        cursor = MultiplayerShellTransportCursor()
        latestAttachRequest = nil
        let payload = try await webSocketClient.sendCommand(
            action: "room_create",
            data: [
                "hostPlayerId": request.hostPlayerId,
                "deviceId": request.deviceId,
                "roomType": request.roomType.rawValue,
                "joinPolicy": request.joinPolicy.rawValue
            ]
        )
        return try attachRequest(
            fromBootstrapResponse: payload,
            requestedPlayerId: request.hostPlayerId,
            requestedDeviceId: request.deviceId
        )
    }

    func joinRoomBootstrap(_ request: MultiplayerShellJoinRoomRequest) async throws -> MultiplayerShellAttachRequest {
        cursor = MultiplayerShellTransportCursor()
        latestAttachRequest = nil
        let payload = try await webSocketClient.sendCommand(
            action: "room_join",
            data: [
                "roomId": request.roomId,
                "playerId": request.playerId,
                "deviceId": request.deviceId
            ]
        )
        return try attachRequest(
            fromBootstrapResponse: payload,
            requestedPlayerId: request.playerId,
            requestedDeviceId: request.deviceId
        )
    }

    func connect(using request: MultiplayerShellAttachRequest) async throws {
        latestAttachRequest = request
        let connectionId = request.connectionId ?? "conn_\(clientId.prefix(12))"
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_connect",
            data: [
                "clientId": clientId,
                "roomId": request.roomId,
                "sessionId": request.sessionId,
                "playerId": request.playerId,
                "deviceId": request.deviceId,
                "resumeToken": request.resumeToken
            ]
        )
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(
                action: "hello",
                connectionId: connectionId
            )
        )
        try await pullMailbox()
    }

    func resume(using request: MultiplayerShellAttachRequest) async throws {
        try await connect(using: request)
    }

    func sendLeaveRoom(_ request: MultiplayerShellLeaveRoomRequest) async throws {
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(action: "leaveRoom")
        )
        try await pullMailbox()
    }

    func setReady(_ request: MultiplayerShellReadyRequest) async throws {
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(
                action: "setReady",
                extra: ["ready": request.ready]
            )
        )
        try await pullMailbox()
    }

    func requestRoomSnapshot(roomId: String) async throws {
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(action: "snapshot")
        )
        try await pullMailbox()
    }

    func recordGameStarted(roomId: String, gameId: String?) async throws {
        var extra: [String: Any] = [:]
        if let gameId {
            extra["gameId"] = gameId
        }
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(
                action: "recordGameStartedAndPrepareBootstrap",
                extra: extra
            )
        )
        try await pullMailbox()
    }

    func recordMatchEnded(
        roomId: String,
        roundIndex: Int?,
        quitReason: String?,
        forfeitingPlayerId: String?
    ) async throws {
        var extra: [String: Any] = [:]
        if let roundIndex {
            extra["roundIndex"] = roundIndex
        }
        if let quitReason {
            extra["quitReason"] = quitReason
        }
        if let forfeitingPlayerId {
            extra["forfeitingPlayerId"] = forfeitingPlayerId
        }
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(
                action: "recordMatchEndedAndFetchTerminalSummary",
                extra: extra
            )
        )
        try await pullMailbox()
    }

    func playCard(_ request: MultiplayerShellPlayCardRequest) async throws {
        try await sendGameplayCommand(
            action: "playCard",
            context: request.context,
            commandPayload: [
                "cardId": request.cardId,
                "source": request.source
            ]
        )
    }

    func submitChoice(_ request: MultiplayerShellSubmitChoiceRequest) async throws {
        var commandPayload: [String: Any] = [
            "choiceId": request.choiceId,
            "optionCode": request.optionCode
        ]
        if let choiceCommandName = request.choiceCommandName {
            commandPayload["choiceCommandName"] = choiceCommandName
        }
        try await sendGameplayCommand(
            action: "submitChoice",
            context: request.context,
            commandPayload: commandPayload
        )
    }

    func quit(_ request: MultiplayerShellQuitRequest) async throws {
        try await sendGameplayCommand(
            action: "quit",
            context: request.context,
            commandPayload: ["reason": request.reasonCode]
        )
    }

    func nextBufferedEvent() async throws -> MultiplayerShellInboundEvent? {
        guard !bufferedEvents.isEmpty else { return nil }
        return bufferedEvents.removeFirst()
    }

    func ingestTransportEnvelope(data: Data) throws {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport envelope must decode to a top-level object.")
        }
        try ingestTransportEnvelope(jsonObject: dictionary)
    }

    func ingestTransportEnvelope(jsonObject: [String: Any]) throws {
        bufferedEvents.append(
            contentsOf: try MultiplayerShellTransportEnvelopeMapper.inboundEvents(
                from: jsonObject,
                attachRequest: latestAttachRequest
            )
        )
    }

    func resetTransportState() async {
        await webSocketClient.invalidate()
        latestAttachRequest = nil
        bufferedEvents.removeAll()
    }

    private func pullMailbox() async throws {
        let response = try await webSocketClient.sendCommand(
            action: "room_transport_receive",
            data: ["clientId": clientId]
        )
        let rawEnvelopes = try requireArray("envelopes", in: response)
        for rawEnvelope in rawEnvelopes {
            let envelope = try requireDictionary(rawEnvelope, context: "room_transport_receive.envelopes[]")
            cursor.update(from: envelope)
            try ingestTransportEnvelope(jsonObject: envelope)
        }
    }

    private func sendGameplayCommand(
        action: String,
        context: MultiplayerShellGameplayCommandContext,
        commandPayload: [String: Any]
    ) async throws {
        var extra: [String: Any] = [
            "actionId": context.actionId,
            "expectedStateVersion": context.expectedStateVersion,
            "commandPayload": commandPayload
        ]
        if let requestId = context.requestId {
            extra["requestId"] = requestId
        }
        if let traceId = context.traceId {
            extra["traceId"] = traceId
        }
        _ = try await webSocketClient.sendCommand(
            action: "room_transport_send",
            data: transportSendPayload(
                action: action,
                extra: extra
            )
        )
        try await pullMailbox()
    }

    private func transportSendPayload(
        action: String,
        connectionId: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "clientId": clientId,
            "action": action,
        ]
        if let connectionId {
            payload["connectionId"] = connectionId
        }
        if let lastSeen = cursor.payload {
            payload["lastSeen"] = lastSeen
        }
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    private func attachRequest(
        fromBootstrapResponse payload: [String: Any],
        requestedPlayerId: String,
        requestedDeviceId: String
    ) throws -> MultiplayerShellAttachRequest {
        let room = try requireDictionary("room", in: payload)
        let session = try requireDictionary("session", in: payload)
        return MultiplayerShellAttachRequest(
            roomId: try requireString("roomId", in: room),
            sessionId: try requireString("sessionId", in: session),
            playerId: optionalString("playerId", in: session) ?? requestedPlayerId,
            deviceId: optionalString("deviceId", in: session) ?? requestedDeviceId,
            resumeToken: try requireString("resumeToken", in: session),
            connectionId: nil
        )
    }

    private func requireDictionary(_ key: String, in object: [String: Any]) throws -> [String: Any] {
        guard let value = object[key], !(value is NSNull) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Missing transport object for key \(key).")
        }
        return try requireDictionary(value, context: key)
    }

    private func requireDictionary(_ value: Any, context: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(context) is not an object.")
        }
        return dictionary
    }

    private func requireArray(_ key: String, in object: [String: Any]) throws -> [Any] {
        guard let value = object[key] as? [Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not an array.")
        }
        return value
    }

    private func requireString(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = optionalString(key, in: object) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not a string.")
        }
        return value
    }

    private func optionalString(_ key: String, in object: [String: Any]) -> String? {
        guard let value = object[key], !(value is NSNull) else {
            return nil
        }
        return value as? String
    }
}

struct MultiplayerShellTransportOutboundHooks {
    let connect: (MultiplayerShellAttachRequest) async throws -> Void
    let resume: (MultiplayerShellAttachRequest) async throws -> Void
    let sendLeaveRoom: (MultiplayerShellLeaveRoomRequest) async throws -> Void

    static let notImplemented = MultiplayerShellTransportOutboundHooks(
        connect: { _ in
            throw MultiplayerShellRuntimeError.notImplemented("Multiplayer transport connect")
        },
        resume: { _ in
            throw MultiplayerShellRuntimeError.notImplemented("Multiplayer transport resume")
        },
        sendLeaveRoom: { _ in
            throw MultiplayerShellRuntimeError.notImplemented("Multiplayer transport leaveRoom")
        }
    )
}

final class MultiplayerBufferedTransportAdapter: MultiplayerShellNetworkingAdapter, MultiplayerShellTransportEnvelopeIngesting {
    let label: String

    private let outboundHooks: MultiplayerShellTransportOutboundHooks
    private var bufferedEvents: [MultiplayerShellInboundEvent] = []
    private var latestAttachRequest: MultiplayerShellAttachRequest?

    init(
        label: String = "Buffered Envelope Adapter",
        outboundHooks: MultiplayerShellTransportOutboundHooks = .notImplemented
    ) {
        self.label = label
        self.outboundHooks = outboundHooks
    }

    func connect(using request: MultiplayerShellAttachRequest) async throws {
        latestAttachRequest = request
        try await outboundHooks.connect(request)
    }

    func resume(using request: MultiplayerShellAttachRequest) async throws {
        latestAttachRequest = request
        try await outboundHooks.resume(request)
    }

    func sendLeaveRoom(_ request: MultiplayerShellLeaveRoomRequest) async throws {
        try await outboundHooks.sendLeaveRoom(request)
    }

    func nextBufferedEvent() async throws -> MultiplayerShellInboundEvent? {
        guard !bufferedEvents.isEmpty else { return nil }
        return bufferedEvents.removeFirst()
    }

    func ingestTransportEnvelope(data: Data) throws {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport envelope must decode to a top-level object.")
        }
        try ingestTransportEnvelope(jsonObject: dictionary)
    }

    func ingestTransportEnvelope(jsonObject: [String: Any]) throws {
        bufferedEvents.append(
            contentsOf: try MultiplayerShellTransportEnvelopeMapper.inboundEvents(
                from: jsonObject,
                attachRequest: latestAttachRequest
            )
        )
    }
}

private enum MultiplayerShellTransportEnvelopeMapper {
    static func inboundEvents(
        from envelope: [String: Any],
        attachRequest: MultiplayerShellAttachRequest?
    ) throws -> [MultiplayerShellInboundEvent] {
        switch try requireString("type", in: envelope) {
        case "helloAck":
            return [.helloAck(try helloAckPayload(from: envelope))]
        case "roomSnapshot":
            return [.roomSnapshot(try roomSnapshotPayload(from: envelope, attachRequest: attachRequest))]
        case "gameEvent":
            return try gameEvents(from: envelope)
        case "roomEvent":
            return try roomEvents(from: envelope, attachRequest: attachRequest)
        case "terminalSummary":
            return try terminalSummaryEvents(from: envelope)
        case "matchEnded":
            return try terminalSummaryEvents(from: envelope)
        case "leaveAcknowledged":
            return [.leaveAcknowledged(try leaveAcknowledgementPayload(from: envelope))]
        case "roomClosed":
            return [
                .roomClosed(
                    try topLevelRoomClosedPayload(from: envelope)
                )
            ]
        default:
            return []
        }
    }

    private static func helloAckPayload(from envelope: [String: Any]) throws -> MultiplayerHelloAckShellPayload {
        let payload = try requireDictionary("payload", in: envelope)
        return MultiplayerHelloAckShellPayload(
            roomId: optionalString("roomId", in: envelope),
            resumeMode: try requireEnum("resumeMode", in: payload, as: MultiplayerHelloResumeMode.self),
            heartbeatIntervalMs: try requireInt("heartbeatIntervalMs", in: payload),
            disconnectTimeoutMs: try requireInt("disconnectTimeoutMs", in: payload),
            reconnectGraceMs: try requireInt("reconnectGraceMs", in: payload),
            resultRetentionMs: try requireInt("resultRetentionMs", in: payload),
            resumeToken: optionalString("resumeToken", in: payload)
        )
    }

    private static func roomSnapshotPayload(
        from envelope: [String: Any],
        attachRequest: MultiplayerShellAttachRequest?
    ) throws -> MultiplayerRoomSnapshotPayload {
        let payload = try requireDictionary("payload", in: envelope)
        let room = try requireDictionary("room", in: payload)
        let sessions = try requireArray("sessions", in: payload)
        let localSession = resolveLocalSession(in: sessions, envelope: envelope, attachRequest: attachRequest)
        let localPlayerId = (localSession?["playerId"] as? String) ?? attachRequest?.playerId
        let persistedResume: MultiplayerPersistedSessionSummary?
        if let localSession {
            persistedResume = MultiplayerPersistedSessionSummary(
                roomId: try requireString("roomId", in: localSession),
                sessionId: try requireString("sessionId", in: localSession),
                playerId: optionalString("playerId", in: localSession),
                deviceId: optionalString("deviceId", in: localSession),
                resumeToken: optionalString("resumeToken", in: localSession),
                lastKnownGameId: optionalString("activeGameId", in: room),
                graceExpiresAt: parseDate(optionalString("graceExpiresAt", in: localSession))
            )
        } else {
            persistedResume = nil
        }

        let members = try requireArray("members", in: room).map { rawMember -> MultiplayerRoomMemberPayload in
            let member = try requireDictionary(rawMember, context: "room.members[]")
            return MultiplayerRoomMemberPayload(
                playerId: try requireString("playerId", in: member),
                seat: try requireInt("seat", in: member),
                role: try requireString("role", in: member),
                ready: try requireBool("ready", in: member),
                presence: try requireEnum("presence", in: member, as: MultiplayerRoomMemberPresencePayload.self),
                isLocalPlayer: optionalString("playerId", in: member) == localPlayerId
            )
        }

        return MultiplayerRoomSnapshotPayload(
            roomId: try requireString("roomId", in: room),
            roomType: try requireEnum("roomType", in: room, as: MultiplayerRoomType.self),
            joinPolicy: try requireEnum("joinPolicy", in: room, as: MultiplayerJoinPolicy.self),
            roomState: try requireEnum("roomState", in: room, as: MultiplayerRoomLifecycle.self),
            hostPlayerId: try requireString("hostPlayerId", in: room),
            members: members,
            activeGameId: optionalString("activeGameId", in: room),
            deadlines: MultiplayerRoomDeadlinesPayload(
                joinExpiresAt: optionalString("joinExpiresAt", in: try requireDictionary("deadlines", in: room)),
                readyExpiresAt: optionalString("readyExpiresAt", in: try requireDictionary("deadlines", in: room))
            ),
            lastRoomSequence: try requireInt("lastRoomSequence", in: room),
            inviteCode: optionalString("inviteCode", in: room),
            persistedResume: persistedResume
        )
    }

    private static func gameEvents(from envelope: [String: Any]) throws -> [MultiplayerShellInboundEvent] {
        let payload = try requireDictionary("payload", in: envelope)
        let engineEvent = try requireDictionary("engineEvent", in: payload)
        let serverTime = optionalString("serverTime", in: engineEvent) ?? optionalString("serverTime", in: envelope)

        switch try requireString("eventName", in: engineEvent) {
        case MultiplayerEventName.stateSnapshot.rawValue:
            let snapshotPayload = try requireDictionary("payload", in: engineEvent)
            return [.gameSnapshot(try decodeJSON(MultiplayerSnapshot.self, from: snapshotPayload), serverTime: serverTime)]
        case MultiplayerEventName.turnChanged.rawValue:
            let turnChangedPayload = try requireDictionary("payload", in: engineEvent)
            return [.turnChanged(try decodeJSON(MultiplayerTurnChangedPayload.self, from: turnChangedPayload), serverTime: serverTime)]
        case MultiplayerEventName.actionRejected.rawValue:
            let rejectedPayload = try requireDictionary("payload", in: engineEvent)
            return [.actionRejected(try decodeJSON(MultiplayerActionRejectedPayload.self, from: rejectedPayload))]
        case MultiplayerEventName.matchEnded.rawValue:
            let matchEndedPayload = try requireDictionary("payload", in: engineEvent)
            return [.matchEnded(roundEnded: nil, matchEnded: try decodeJSON(MultiplayerMatchEndedPayload.self, from: matchEndedPayload))]
        default:
            return []
        }
    }

    private static func roomEvents(
        from envelope: [String: Any],
        attachRequest: MultiplayerShellAttachRequest?
    ) throws -> [MultiplayerShellInboundEvent] {
        let payload = try requireDictionary("payload", in: envelope)
        switch try requireString("eventName", in: payload) {
        case "roomClosed":
            return [
                .roomClosed(
                    MultiplayerRoomClosedPayload(
                        roomId: try requireString("roomId", in: envelope),
                        reasonCode: try requireString("reason", in: payload),
                        messageKey: "room.closed.\(try requireString("reason", in: payload))",
                        closedAt: optionalString("closedAt", in: payload)
                    )
                )
            ]
        case "memberLeft":
            guard let attachRequest,
                  optionalString("playerId", in: payload) == attachRequest.playerId else {
                return []
            }
            return [
                .leaveAcknowledged(
                    MultiplayerLeaveAcknowledgementPayload(
                        roomId: try requireString("roomId", in: envelope),
                        playerId: attachRequest.playerId,
                        roomState: .ended,
                        messageKey: "match.result.leave.acknowledged",
                        roomClosed: nil
                    )
                )
            ]
        case "leaveAcknowledged":
            return [.leaveAcknowledged(try leaveAcknowledgementPayload(from: envelope))]
        default:
            return []
        }
    }

    private static func terminalSummaryEvents(from envelope: [String: Any]) throws -> [MultiplayerShellInboundEvent] {
        let payload = try requireDictionary("payload", in: envelope)
        if let directMatchEnded = payload["winnerPlayerId"] as? String {
            _ = directMatchEnded
            return [
                .matchEnded(
                    roundEnded: nil,
                    matchEnded: try decodeJSON(MultiplayerMatchEndedPayload.self, from: payload)
                )
            ]
        }
        return [
            .matchEnded(
                roundEnded: try decodeOptionalJSON(MultiplayerRoundEndedPayload.self, from: payload["roundEnded"]),
                matchEnded: try decodeJSON(MultiplayerMatchEndedPayload.self, from: try requireDictionary("matchEnded", in: payload))
            )
        ]
    }

    private static func leaveAcknowledgementPayload(from envelope: [String: Any]) throws -> MultiplayerLeaveAcknowledgementPayload {
        let payload = try requireDictionary("payload", in: envelope)
        return MultiplayerLeaveAcknowledgementPayload(
            roomId: try requireString("roomId", in: envelope),
            playerId: try requireString("playerId", in: payload),
            roomState: try requireEnum("roomState", in: payload, as: MultiplayerRoomLifecycle.self),
            messageKey: try requireString("messageKey", in: payload),
            roomClosed: try decodeOptionalRoomClosed(from: payload["roomClosed"], roomId: try requireString("roomId", in: envelope))
        )
    }

    private static func topLevelRoomClosedPayload(from envelope: [String: Any]) throws -> MultiplayerRoomClosedPayload {
        let payload = try requireDictionary("payload", in: envelope)
        let reasonCode: String
        if let explicitReasonCode = optionalString("reasonCode", in: payload) {
            reasonCode = explicitReasonCode
        } else {
            reasonCode = try requireString("reason", in: payload)
        }
        let roomId: String
        if let explicitRoomId = optionalString("roomId", in: payload) {
            roomId = explicitRoomId
        } else {
            roomId = try requireString("roomId", in: envelope)
        }
        return MultiplayerRoomClosedPayload(
            roomId: roomId,
            reasonCode: reasonCode,
            messageKey: optionalString("messageKey", in: payload) ?? "room.closed.\(reasonCode)",
            closedAt: optionalString("closedAt", in: payload)
        )
    }

    private static func resolveLocalSession(
        in sessions: [Any],
        envelope: [String: Any],
        attachRequest: MultiplayerShellAttachRequest?
    ) -> [String: Any]? {
        let sessionId = attachRequest?.sessionId ?? optionalString("sessionId", in: envelope)
        return sessions
            .compactMap { try? requireDictionary($0, context: "sessions[]") }
            .first {
                if let sessionId {
                    return optionalString("sessionId", in: $0) == sessionId
                }
                return optionalString("playerId", in: $0) == attachRequest?.playerId
            }
    }

    private static func decodeOptionalRoomClosed(
        from rawValue: Any?,
        roomId: String
    ) throws -> MultiplayerRoomClosedPayload? {
        guard let rawValue, !(rawValue is NSNull) else {
            return nil
        }
        let payload = try requireDictionary(rawValue, context: "leaveAcknowledged.roomClosed")
        let reasonCode = try requireString("reasonCode", in: payload)
        return MultiplayerRoomClosedPayload(
            roomId: optionalString("roomId", in: payload) ?? roomId,
            reasonCode: reasonCode,
            messageKey: optionalString("messageKey", in: payload) ?? "room.closed.\(reasonCode)",
            closedAt: optionalString("closedAt", in: payload)
        )
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from payload: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: sanitize(payload), options: [.sortedKeys])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeOptionalJSON<T: Decodable>(_ type: T.Type, from rawValue: Any?) throws -> T? {
        guard let rawValue, !(rawValue is NSNull) else {
            return nil
        }
        return try decodeJSON(type, from: try requireDictionary(rawValue, context: "optionalPayload"))
    }

    private static func sanitize(_ value: Any) -> Any {
        if value is NSNull {
            return NSNull()
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(sanitize)
        }
        if let array = value as? [Any] {
            return array.map(sanitize)
        }
        return value
    }

    private static func requireDictionary(_ key: String, in object: [String: Any]) throws -> [String: Any] {
        guard let value = object[key], !(value is NSNull) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Missing transport object for key \(key).")
        }
        return try requireDictionary(value, context: key)
    }

    private static func requireDictionary(_ value: Any, context: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(context) is not an object.")
        }
        return dictionary
    }

    private static func requireArray(_ key: String, in object: [String: Any]) throws -> [Any] {
        guard let value = object[key] as? [Any] else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not an array.")
        }
        return value
    }

    private static func requireString(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = optionalString(key, in: object) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not a string.")
        }
        return value
    }

    private static func optionalString(_ key: String, in object: [String: Any]) -> String? {
        guard let value = object[key], !(value is NSNull) else {
            return nil
        }
        return value as? String
    }

    private static func requireInt(_ key: String, in object: [String: Any]) throws -> Int {
        if let value = object[key] as? Int {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.intValue
        }
        throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not an int.")
    }

    private static func requireBool(_ key: String, in object: [String: Any]) throws -> Bool {
        if let value = object[key] as? Bool {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.boolValue
        }
        throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key) is not a bool.")
    }

    private static func requireEnum<T: RawRepresentable>(
        _ key: String,
        in object: [String: Any],
        as type: T.Type
    ) throws -> T where T.RawValue == String {
        let rawValue = try requireString(key, in: object)
        guard let value = T(rawValue: rawValue) else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Transport value \(key)=\(rawValue) is unsupported.")
        }
        return value
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return MultiplayerShellMapper.parseTransportDate(value)
    }
}

struct MultiplayerShellEnvironment {
    let sessionPersistence: any MultiplayerSessionPersisting
    let networkingAdapter: any MultiplayerShellNetworkingAdapter
    let transportSourceFactory: @MainActor () -> MultiplayerShellSource

    static let `default` = MultiplayerShellEnvironment(
        sessionPersistence: MultiplayerUserDefaultsSessionPersistence(),
        networkingAdapter: MultiplayerNoopNetworkingAdapter(),
        transportSourceFactory: {
            MultiplayerTransportShellSource(mode: .productPreparation())
        }
    )
}

@MainActor
final class MultiplayerShellStore: ObservableObject {
    @Published var route: MultiplayerShellRoute
    @Published var entryState: MultiplayerEntryShellState
    @Published var roomState: MultiplayerRoomShellState
    @Published var liveState: MultiplayerLiveShellState
    @Published var reconnectOverlay: MultiplayerReconnectOverlayState?
    @Published var resultState: MultiplayerResultShellState
    @Published private(set) var sourceLabel: String
    @Published private(set) var sourceDescription: String
    @Published private(set) var entryActions: [MultiplayerEntryAction]
    @Published private(set) var controls: [MultiplayerShellControl]
    @Published private(set) var statusItems: [MultiplayerShellStatusItem]

    private let baseline: MultiplayerShellPreviewShowcaseState
    private let environment: MultiplayerShellEnvironment
    private var source: MultiplayerShellSource

    init(
        baseline: MultiplayerShellPreviewShowcaseState = .mock,
        source: MultiplayerShellSource? = nil,
        environment: MultiplayerShellEnvironment = .default
    ) {
        let resolvedSource = source ?? MultiplayerMockShellSource(baseline: baseline)
        let initialPersistedResume = environment.sessionPersistence.loadPersistedSession() ?? baseline.entry.persistedResume
        self.baseline = baseline
        self.environment = environment
        self.route = .entry
        self.entryState = MultiplayerEntryShellState(
            pendingAction: baseline.entry.pendingAction,
            persistedResume: initialPersistedResume,
            lastError: baseline.entry.lastError
        )
        self.roomState = baseline.room
        self.liveState = baseline.live
        self.reconnectOverlay = nil
        self.resultState = baseline.result
        self.sourceLabel = resolvedSource.label
        self.sourceDescription = resolvedSource.descriptionText
        self.entryActions = resolvedSource.visibleEntryActions()
        self.controls = []
        self.statusItems = []
        self.source = resolvedSource
        resolvedSource.attach(store: self)
        resolvedSource.reset()
    }

    static func transportBacked(
        configuration: MultiplayerTransportRouteConfiguration = .productPreparation()
    ) -> MultiplayerShellStore {
        let environment = MultiplayerShellEnvironment(
            sessionPersistence: MultiplayerUserDefaultsSessionPersistence(
                storageKey: configuration.persistenceStorageKey
            ),
            networkingAdapter: MultiplayerWebSocketCommandNetworkingAdapter(
                options: configuration.transportOptions,
                clientId: configuration.hostClientId
            ),
            transportSourceFactory: {
                MultiplayerTransportShellSource(
                    options: configuration.transportOptions,
                    mode: configuration.mode
                )
            }
        )
        return MultiplayerShellStore(
            source: environment.transportSourceFactory(),
            environment: environment
        )
    }

    func handleEntryAction(_ action: MultiplayerEntryAction) {
        source.handleEntryAction(action)
        refreshSourceUI()
    }

    func performControl(_ action: MultiplayerShellControlAction) {
        source.handleControlAction(action)
        refreshSourceUI()
    }

    func updateEntryJoinIdentifier(_ joinIdentifier: String?) {
        source.updateEntryJoinIdentifier(joinIdentifier)
        refreshSourceUI()
    }

    var isGameplayTransportReady: Bool {
        gameplayNetworkingAdapter != nil && route == .live && reconnectOverlay == nil
    }

    func playCardFromLiveUI(_ cardId: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sendPlayCardUsingNetworkingAdapter(cardId: cardId)
            } catch {
                self.presentLiveTransportFailure(
                    title: "Card Send Failed",
                    fallbackDetail: "The selected hand card could not be sent over the current multiplayer transport.",
                    error: error
                )
            }
        }
    }

    func submitChoiceFromLiveUI(_ choiceId: String, optionCode: String, choiceCommandName: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sendChoiceUsingNetworkingAdapter(
                    choiceId: choiceId,
                    optionCode: optionCode,
                    choiceCommandName: choiceCommandName
                )
            } catch {
                self.presentLiveTransportFailure(
                    title: "Choice Send Failed",
                    fallbackDetail: "The selected option could not be submitted over the authoritative multiplayer transport.",
                    error: error
                )
            }
        }
    }

    func quitMatchFromLiveUI(reasonCode: String = MultiplayerQuitReason.voluntaryExit.rawValue) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.sendQuitUsingNetworkingAdapter(reasonCode: reasonCode)
            } catch {
                self.presentLiveTransportFailure(
                    title: "Quit Failed",
                    fallbackDetail: "The quit command could not be delivered. The live route stays open until an authoritative signal lands.",
                    error: error
                )
            }
        }
    }

    func reset() {
        source.reset()
        refreshSourceUI()
    }

    func replaceSource(_ newSource: MultiplayerShellSource, reset: Bool = true) {
        source.detach()
        source = newSource
        sourceLabel = newSource.label
        sourceDescription = newSource.descriptionText
        newSource.attach(store: self)
        if reset {
            newSource.reset()
        } else {
            refreshSourceUI()
        }
        refreshSourceUI()
    }

    func activateTransportSource() {
        if source is MultiplayerTransportShellSource {
            refreshSourceUI()
            return
        }
        replaceSource(environment.transportSourceFactory(), reset: false)
    }

    func persistedResumeAttachRequest() -> MultiplayerShellAttachRequest? {
        persistedAttachRequestCandidate()
    }

    func currentLeaveRoomRequest() -> MultiplayerShellLeaveRoomRequest? {
        leaveRoomRequestCandidate()
    }

    func resumePersistedSessionOverTransport() async throws {
        activateTransportSource()
        try await resumeUsingNetworkingAdapter()
    }

    func sendAuthoritativeLeaveFromResult() async throws {
        activateTransportSource()
        try await sendLeaveRoomUsingNetworkingAdapter()
    }

    func ingestTransportEnvelope(data: Data) async throws {
        activateTransportSource()
        guard let ingestor = environment.networkingAdapter as? any MultiplayerShellTransportEnvelopeIngesting else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellTransportEnvelopeIngesting")
        }
        try ingestor.ingestTransportEnvelope(data: data)
        try await drainBufferedNetworkingEvents()
    }

    func ingestTransportEnvelope(jsonObject: [String: Any]) async throws {
        activateTransportSource()
        guard let ingestor = environment.networkingAdapter as? any MultiplayerShellTransportEnvelopeIngesting else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellTransportEnvelopeIngesting")
        }
        try ingestor.ingestTransportEnvelope(jsonObject: jsonObject)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func showEntry(_ state: MultiplayerEntryShellState) {
        route = .entry
        entryState = state
        reconnectOverlay = nil
        refreshSourceUI()
    }

    fileprivate func showRoom(
        _ state: MultiplayerRoomShellState,
        overlay: MultiplayerReconnectOverlayState? = nil,
        persistedResume: MultiplayerPersistedSessionSummary? = nil,
        entryBanner: MultiplayerBannerState? = nil
    ) {
        route = .room
        roomState = state
        reconnectOverlay = overlay
        if let persistedResume {
            environment.sessionPersistence.savePersistedSession(persistedResume)
            entryState = MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: persistedResume,
                lastError: entryBanner
            )
        }
        refreshSourceUI()
    }

    fileprivate func cacheRoom(
        _ state: MultiplayerRoomShellState,
        persistedResume: MultiplayerPersistedSessionSummary? = nil,
        entryBanner: MultiplayerBannerState? = nil
    ) {
        roomState = state
        if let persistedResume {
            environment.sessionPersistence.savePersistedSession(persistedResume)
            entryState = MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: persistedResume,
                lastError: entryBanner
            )
        }
        refreshSourceUI()
    }

    fileprivate func showLive(
        _ state: MultiplayerLiveShellState,
        overlay: MultiplayerReconnectOverlayState? = nil
    ) {
        route = .live
        liveState = state
        reconnectOverlay = overlay
        refreshSourceUI()
    }

    fileprivate func showResult(_ state: MultiplayerResultShellState) {
        route = .result
        resultState = state
        reconnectOverlay = nil
        refreshSourceUI()
    }

    fileprivate func updateOverlay(_ overlay: MultiplayerReconnectOverlayState?) {
        reconnectOverlay = overlay
        refreshSourceUI()
    }

    fileprivate func restoreBaselineEntry() {
        route = .entry
        entryState = MultiplayerEntryShellState(
            pendingAction: baseline.entry.pendingAction,
            persistedResume: environment.sessionPersistence.loadPersistedSession() ?? baseline.entry.persistedResume,
            lastError: baseline.entry.lastError
        )
        roomState = baseline.room
        liveState = baseline.live
        reconnectOverlay = nil
        resultState = baseline.result
        refreshSourceUI()
    }

    fileprivate var previewBaseline: MultiplayerShellPreviewShowcaseState {
        baseline
    }

    fileprivate var environmentStatusItems: [MultiplayerShellStatusItem] {
        [
            MultiplayerShellStatusItem(label: "Persist", value: environment.sessionPersistence.label),
            MultiplayerShellStatusItem(label: "Net", value: environment.networkingAdapter.label),
            MultiplayerShellStatusItem(label: "Resume Req", value: persistedAttachRequestCandidate() == nil ? "Missing" : "Ready"),
            MultiplayerShellStatusItem(label: "Leave Req", value: leaveRoomRequestCandidate() == nil ? "Missing" : "Ready")
        ]
    }

    fileprivate func persistedResumeCandidate() -> MultiplayerPersistedSessionSummary? {
        environment.sessionPersistence.loadPersistedSession() ?? entryState.persistedResume
    }

    fileprivate func savePersistedResumeSummary(_ summary: MultiplayerPersistedSessionSummary) {
        environment.sessionPersistence.savePersistedSession(summary)
        entryState = MultiplayerEntryShellState(
            pendingAction: nil,
            persistedResume: summary,
            lastError: entryState.lastError
        )
    }

    fileprivate var roomLifecycleNetworkingAdapter: (any MultiplayerShellRoomLifecycleNetworkingAdapter)? {
        environment.networkingAdapter as? any MultiplayerShellRoomLifecycleNetworkingAdapter
    }

    fileprivate var gameplayNetworkingAdapter: (any MultiplayerShellGameplayNetworkingAdapter)? {
        environment.networkingAdapter as? any MultiplayerShellGameplayNetworkingAdapter
    }

    fileprivate func resetNetworkingAdapterTransportState() async {
        guard let resettable = environment.networkingAdapter as? any MultiplayerShellResettableNetworkingAdapter else {
            return
        }
        await resettable.resetTransportState()
    }

    fileprivate func primePersistedResume(
        from request: MultiplayerShellAttachRequest,
        lastKnownGameId: String? = nil,
        graceExpiresAt: Date? = nil
    ) {
        savePersistedResumeSummary(
            MultiplayerPersistedSessionSummary(
                roomId: request.roomId,
                sessionId: request.sessionId,
                playerId: request.playerId,
                deviceId: request.deviceId,
                resumeToken: request.resumeToken,
                lastKnownGameId: lastKnownGameId ?? persistedResumeCandidate()?.lastKnownGameId,
                graceExpiresAt: graceExpiresAt ?? persistedResumeCandidate()?.graceExpiresAt
            )
        )
    }

    fileprivate func persistedAttachRequestCandidate() -> MultiplayerShellAttachRequest? {
        guard let persistedResume = persistedResumeCandidate(),
              let playerId = persistedResume.playerId,
              let deviceId = persistedResume.deviceId,
              let resumeToken = persistedResume.resumeToken else {
            return nil
        }

        return MultiplayerShellAttachRequest(
            roomId: persistedResume.roomId,
            sessionId: persistedResume.sessionId,
            playerId: playerId,
            deviceId: deviceId,
            resumeToken: resumeToken,
            connectionId: nil
        )
    }

    fileprivate func leaveRoomRequestCandidate() -> MultiplayerShellLeaveRoomRequest? {
        switch route {
        case .room:
            guard let localPlayer = roomState.members.first(where: \.isLocalPlayer)?.playerId else {
                return nil
            }
            return MultiplayerShellLeaveRoomRequest(roomId: roomState.roomId, playerId: localPlayer)
        case .live:
            return MultiplayerShellLeaveRoomRequest(roomId: liveState.roomId, playerId: liveState.localPlayerId)
        case .result:
            return roomState.members.first(where: \.isLocalPlayer).map {
                MultiplayerShellLeaveRoomRequest(roomId: roomState.roomId, playerId: $0.playerId)
            }
        case .entry:
            return nil
        }
    }

    fileprivate func clearPersistedResume() {
        environment.sessionPersistence.clearPersistedSession()
    }

    fileprivate func createRoomUsingNetworkingAdapter(
        roomType: MultiplayerRoomType,
        joinPolicy: MultiplayerJoinPolicy,
        playerId: String,
        deviceId: String
    ) async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.createRoomBootstrap")
        }
        let attachRequest = try await adapter.createRoomBootstrap(
            MultiplayerShellCreateRoomRequest(
                hostPlayerId: playerId,
                deviceId: deviceId,
                roomType: roomType,
                joinPolicy: joinPolicy
            )
        )
        try await connectUsingNetworkingAdapter(attachRequest)
    }

    fileprivate func joinRoomUsingNetworkingAdapter(
        roomId: String,
        playerId: String,
        deviceId: String
    ) async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.joinRoomBootstrap")
        }
        let attachRequest = try await adapter.joinRoomBootstrap(
            MultiplayerShellJoinRoomRequest(
                roomId: roomId,
                playerId: playerId,
                deviceId: deviceId
            )
        )
        try await connectUsingNetworkingAdapter(attachRequest)
    }

    fileprivate func setReadyUsingNetworkingAdapter(ready: Bool) async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.setReady")
        }
        guard let localPlayerId = roomState.members.first(where: \.isLocalPlayer)?.playerId else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Room ready cannot be sent before the local room member exists.")
        }
        try await adapter.setReady(
            MultiplayerShellReadyRequest(
                roomId: roomState.roomId,
                playerId: localPlayerId,
                ready: ready
            )
        )
        try await adapter.requestRoomSnapshot(roomId: roomState.roomId)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func requestRoomSnapshotUsingNetworkingAdapter() async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.requestRoomSnapshot")
        }
        let resolvedRoomId: String
        switch route {
        case .entry:
            guard let persistedRoomId = persistedResumeCandidate()?.roomId else {
                throw MultiplayerShellRuntimeError.invalidBoundaryState("No active room exists for snapshot refresh.")
            }
            resolvedRoomId = persistedRoomId
        case .room, .result:
            resolvedRoomId = roomState.roomId
        case .live:
            resolvedRoomId = liveState.roomId
        }
        try await adapter.requestRoomSnapshot(roomId: resolvedRoomId)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func recordGameStartedUsingNetworkingAdapter(gameId: String?) async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.recordGameStarted")
        }
        try await adapter.recordGameStarted(roomId: roomState.roomId, gameId: gameId)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func recordMatchEndedUsingNetworkingAdapter(
        roundIndex: Int?,
        quitReason: String?,
        forfeitingPlayerId: String?
    ) async throws {
        guard let adapter = roomLifecycleNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellRoomLifecycleNetworkingAdapter.recordMatchEnded")
        }
        let resolvedRoomId = route == .live ? liveState.roomId : roomState.roomId
        try await adapter.recordMatchEnded(
            roomId: resolvedRoomId,
            roundIndex: roundIndex,
            quitReason: quitReason,
            forfeitingPlayerId: forfeitingPlayerId
        )
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func sendPlayCardUsingNetworkingAdapter(cardId: String, source: String = "hand") async throws {
        guard let adapter = gameplayNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellGameplayNetworkingAdapter.playCard")
        }
        try await adapter.playCard(
            MultiplayerShellPlayCardRequest(
                context: try gameplayCommandContext(actionName: "playCard"),
                cardId: cardId,
                source: source
            )
        )
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func sendChoiceUsingNetworkingAdapter(
        choiceId: String,
        optionCode: String,
        choiceCommandName: String? = nil
    ) async throws {
        guard let adapter = gameplayNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellGameplayNetworkingAdapter.submitChoice")
        }
        try await adapter.submitChoice(
            MultiplayerShellSubmitChoiceRequest(
                context: try gameplayCommandContext(actionName: "submitChoice"),
                choiceId: choiceId,
                optionCode: optionCode,
                choiceCommandName: choiceCommandName
            )
        )
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func sendQuitUsingNetworkingAdapter(reasonCode: String) async throws {
        guard let adapter = gameplayNetworkingAdapter else {
            throw MultiplayerShellRuntimeError.notImplemented("MultiplayerShellGameplayNetworkingAdapter.quit")
        }
        try await adapter.quit(
            MultiplayerShellQuitRequest(
                context: try gameplayCommandContext(actionName: "quit"),
                reasonCode: reasonCode
            )
        )
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func connectUsingNetworkingAdapter(_ request: MultiplayerShellAttachRequest) async throws {
        primePersistedResume(from: request)
        try await environment.networkingAdapter.connect(using: request)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func resumeUsingNetworkingAdapter(_ request: MultiplayerShellAttachRequest? = nil) async throws {
        guard let resolvedRequest = request ?? persistedAttachRequestCandidate() else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState(
                "Persisted session exists, but playerId/deviceId/resumeToken is missing for resume attach."
            )
        }
        primePersistedResume(from: resolvedRequest)
        try await environment.networkingAdapter.resume(using: resolvedRequest)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func sendLeaveRoomUsingNetworkingAdapter(_ request: MultiplayerShellLeaveRoomRequest? = nil) async throws {
        guard let resolvedRequest = request ?? leaveRoomRequestCandidate() else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState(
                "The current shell route cannot build an authoritative leaveRoom request yet."
            )
        }
        if route == .result {
            updateResultLeavePolicy(.pendingLeaveAcknowledgement)
        }
        try await environment.networkingAdapter.sendLeaveRoom(resolvedRequest)
        try await drainBufferedNetworkingEvents()
    }

    fileprivate func drainBufferedNetworkingEvents(maxEvents: Int = 16) async throws {
        for _ in 0..<maxEvents {
            guard let nextEvent = try await environment.networkingAdapter.nextBufferedEvent() else {
                return
            }
            handleInboundEvent(nextEvent)
        }
    }

    fileprivate func updateResultLeavePolicy(_ policy: MultiplayerResultLeavePolicy) {
        resultState = resultState.with(leavePolicy: policy)
        refreshSourceUI()
    }

    fileprivate func handleInboundEvent(_ event: MultiplayerShellInboundEvent) {
        switch event {
        case .helloAck(let payload):
            if let persistedResume = persistedResumeCandidate() {
                savePersistedResumeSummary(
                    MultiplayerPersistedSessionSummary(
                        roomId: payload.roomId ?? persistedResume.roomId,
                        sessionId: persistedResume.sessionId,
                        playerId: persistedResume.playerId,
                        deviceId: persistedResume.deviceId,
                        resumeToken: payload.resumeToken ?? persistedResume.resumeToken,
                        lastKnownGameId: persistedResume.lastKnownGameId,
                        graceExpiresAt: persistedResume.graceExpiresAt
                    )
                )
            }
            let mappedEntry = MultiplayerShellMapper.entryState(
                persistedResume: persistedResumeCandidate(),
                helloAck: payload
            )
            entryState = mappedEntry
            if let reconnectOverlay {
                updateOverlay(
                    MultiplayerReconnectOverlayState(
                        phase: .resyncing,
                        roomId: reconnectOverlay.roomId,
                        heartbeatIntervalMs: payload.heartbeatIntervalMs,
                        disconnectTimeoutMs: payload.disconnectTimeoutMs,
                        reconnectGraceMs: payload.reconnectGraceMs,
                        graceExpiresAt: reconnectOverlay.graceExpiresAt,
                        lastRoomSequence: reconnectOverlay.lastRoomSequence,
                        lastAppliedStateVersion: reconnectOverlay.lastAppliedStateVersion,
                        lastSnapshotId: reconnectOverlay.lastSnapshotId
                    )
                )
            } else {
                refreshSourceUI()
            }
        case .roomSnapshot(let payload):
            let mappedRoom = MultiplayerShellMapper.roomState(from: payload)
            let persistedResume = payload.persistedResume ?? persistedResumeCandidate()

            if route == .result {
                roomState = mappedRoom
                if let persistedResume {
                    savePersistedResumeSummary(persistedResume)
                }
                refreshSourceUI()
                return
            }

            if route == .live {
                cacheRoom(mappedRoom, persistedResume: persistedResume)
                if let reconnectOverlay {
                    let resyncOverlay = MultiplayerReconnectOverlayState(
                        phase: .resyncing,
                        roomId: payload.roomId,
                        heartbeatIntervalMs: reconnectOverlay.heartbeatIntervalMs,
                        disconnectTimeoutMs: reconnectOverlay.disconnectTimeoutMs,
                        reconnectGraceMs: reconnectOverlay.reconnectGraceMs,
                        graceExpiresAt: reconnectOverlay.graceExpiresAt,
                        lastRoomSequence: payload.lastRoomSequence,
                        lastAppliedStateVersion: reconnectOverlay.lastAppliedStateVersion,
                        lastSnapshotId: reconnectOverlay.lastSnapshotId
                    )
                    updateOverlay(resyncOverlay)
                }
                return
            }

            if let reconnectOverlay {
                let resyncOverlay = MultiplayerReconnectOverlayState(
                    phase: .resyncing,
                    roomId: payload.roomId,
                    heartbeatIntervalMs: reconnectOverlay.heartbeatIntervalMs,
                    disconnectTimeoutMs: reconnectOverlay.disconnectTimeoutMs,
                    reconnectGraceMs: reconnectOverlay.reconnectGraceMs,
                    graceExpiresAt: reconnectOverlay.graceExpiresAt,
                    lastRoomSequence: payload.lastRoomSequence,
                    lastAppliedStateVersion: reconnectOverlay.lastAppliedStateVersion,
                    lastSnapshotId: reconnectOverlay.lastSnapshotId
                )
                cacheRoom(mappedRoom, persistedResume: persistedResume)
                updateOverlay(resyncOverlay)
                return
            }

            showRoom(mappedRoom, persistedResume: persistedResume)
        case let .gameSnapshot(snapshot, serverTime):
            showLive(
                MultiplayerShellMapper.liveState(from: snapshot, serverTime: serverTime),
                overlay: nil
            )
        case let .turnChanged(turnChanged, serverTime):
            guard route == .live else { return }
            showLive(
                MultiplayerShellMapper.applying(turnChanged: turnChanged, serverTime: serverTime, to: liveState),
                overlay: reconnectOverlay
            )
        case .actionRejected(let actionRejected):
            guard route == .live else { return }
            showLive(
                MultiplayerShellMapper.applying(actionRejected: actionRejected, to: liveState),
                overlay: reconnectOverlay
            )
        case let .matchEnded(roundEnded, matchEnded):
            let preservedLeavePolicy = route == .result ? resultState.leavePolicy : MultiplayerResultLeavePolicy.leaveAvailable
            showResult(
                MultiplayerShellMapper.resultState(
                    roundEnded: roundEnded,
                    matchEnded: matchEnded,
                    localPlayerId: liveState.localPlayerId,
                    playerNamesById: resultPlayerNamesById()
                ).with(leavePolicy: preservedLeavePolicy)
            )
        case .roomClosed(let payload):
            handleRoomClosed(payload)
        case .leaveAcknowledged(let payload):
            handleLeaveAcknowledged(payload)
        }
    }

    fileprivate func handleLeaveAcknowledged(_ payload: MultiplayerLeaveAcknowledgementPayload) {
        if let roomClosed = payload.roomClosed {
            handleRoomClosed(roomClosed)
            return
        }

        clearPersistedResume()
        showEntry(
            MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: nil,
                lastError: MultiplayerBannerState(
                    style: .success,
                    title: "Leave Confirmed",
                    detail: leaveAcknowledgementDetail(for: payload),
                    messageKey: payload.messageKey
                )
            )
        )
    }

    fileprivate func handleRoomClosed(_ payload: MultiplayerRoomClosedPayload) {
        clearPersistedResume()
        showEntry(
            MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: nil,
                lastError: MultiplayerBannerState(
                    style: .info,
                    title: "Room Closed",
                    detail: roomClosedDetail(for: payload),
                    messageKey: payload.messageKey
                )
            )
        )
    }

    fileprivate func refreshSourceUI() {
        sourceLabel = source.label
        sourceDescription = source.descriptionText
        entryActions = source.visibleEntryActions()
        controls = source.visibleControls()
        statusItems = source.statusItems
    }

    private func roomClosedDetail(for payload: MultiplayerRoomClosedPayload) -> String {
        let fallback: String
        switch payload.reasonCode {
        case RoomCloseReason.hostLeft.rawValue:
            fallback = "The host left, so the room closed after the terminal summary was delivered."
        case RoomCloseReason.allPlayersLeft.rawValue:
            fallback = "Every participant has left the result room. The local route can safely dismiss."
        case RoomCloseReason.resultExpired.rawValue:
            fallback = "Result retention expired and the room closed."
        case RoomCloseReason.explicitClose.rawValue:
            fallback = "The room was explicitly closed after result delivery."
        case RoomCloseReason.idleExpired.rawValue:
            fallback = "The room expired before another authoritative lifecycle event arrived."
        case RoomCloseReason.bootstrapFailed.rawValue:
            fallback = "The room closed because bootstrap completion failed."
        default:
            fallback = "The room emitted an authoritative roomClosed signal."
        }
        return multiplayerShellText(payload.messageKey, fallback: fallback)
    }

    private func leaveAcknowledgementDetail(for payload: MultiplayerLeaveAcknowledgementPayload) -> String {
        let fallback: String
        switch payload.roomState {
        case .ended:
            fallback = "The authoritative leave acknowledgement landed. The local session left the retained result room and can dismiss now."
        case .closed:
            fallback = "The authoritative leave acknowledgement landed after the room already closed."
        default:
            fallback = "The authoritative leave acknowledgement landed and the local session can return to entry."
        }
        return multiplayerShellText(payload.messageKey, fallback: fallback)
    }

    private func resultPlayerNamesById() -> [String: String] {
        var names: [String: String] = [:]
        for member in roomState.members {
            names[member.playerId] = member.isLocalPlayer ? "You" : "Opponent"
        }
        names[liveState.localPlayerId] = "You"
        if names[liveState.opponentPlayerId] == nil {
            names[liveState.opponentPlayerId] = "Opponent"
        }
        return names
    }

    private func presentLiveTransportFailure(
        title: String,
        fallbackDetail: String,
        error: Error
    ) {
        let detail: String
        let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if localizedDescription.isEmpty {
            detail = fallbackDetail
        } else if localizedDescription == fallbackDetail {
            detail = localizedDescription
        } else {
            detail = "\(fallbackDetail) \(localizedDescription)"
        }
        showLive(
            liveState.with(
                connectionBanner: MultiplayerBannerState(
                    style: .error,
                    title: title,
                    detail: detail
                )
            ),
            overlay: reconnectOverlay
        )
    }

    private func gameplayCommandContext(actionName: String) throws -> MultiplayerShellGameplayCommandContext {
        guard route == .live else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Gameplay transport commands require the live route.")
        }
        guard liveState.stateVersion > 0 else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Gameplay transport commands require an authoritative live stateVersion.")
        }
        let actionId = "ios_\(actionName)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        return MultiplayerShellGameplayCommandContext(
            roomId: liveState.roomId,
            gameId: liveState.gameId,
            playerId: liveState.localPlayerId,
            actionId: actionId,
            expectedStateVersion: liveState.stateVersion,
            requestId: actionId,
            traceId: nil
        )
    }
}

@MainActor
final class MultiplayerMockShellSource: MultiplayerShellSource {
    let label = "Mock"
    let descriptionText = "Preview-only route host. Shell state mutates locally without coordinator truth."
    var statusItems: [MultiplayerShellStatusItem] {
        guard let store else { return [] }
        return [
            MultiplayerShellStatusItem(label: "Route", value: store.route.label),
            MultiplayerShellStatusItem(label: "Members", value: "\(store.roomState.members.count)"),
            MultiplayerShellStatusItem(label: "Overlay", value: store.reconnectOverlay == nil ? "None" : "Active")
        ]
    }

    private weak var store: MultiplayerShellStore?
    private let baseline: MultiplayerShellPreviewShowcaseState

    init(baseline: MultiplayerShellPreviewShowcaseState) {
        self.baseline = baseline
    }

    func visibleEntryActions() -> [MultiplayerEntryAction] {
        [.quickMatch, .createInvite, .joinInvite]
    }

    func attach(store: MultiplayerShellStore) {
        self.store = store
    }

    func detach() {
        store = nil
    }

    func reset() {
        store?.restoreBaselineEntry()
    }

    func handleEntryAction(_ action: MultiplayerEntryAction) {
        guard let store else { return }

        let busyEntry = MultiplayerEntryShellState(
            pendingAction: action,
            persistedResume: baseline.entry.persistedResume,
            lastError: baseline.entry.lastError
        )
        store.showEntry(busyEntry)

        switch action {
        case .quickMatch:
            store.showRoom(makeRoomState(roomType: .quickMatch, joinPolicy: .matchmaker, includeGuest: true))
        case .createInvite:
            store.showRoom(makeRoomState(roomType: .invite, joinPolicy: .inviteCode, includeGuest: false))
        case .joinInvite:
            store.showRoom(makeRoomState(roomType: .invite, joinPolicy: .inviteCode, includeGuest: true))
        case .resume:
            store.showLive(baseline.live, overlay: baseline.reconnect)
        }
    }

    func handleControlAction(_ action: MultiplayerShellControlAction) {
        switch action {
        case .joinGuest:
            simulateGuestJoin()
        case .leaveRoom:
            store?.restoreBaselineEntry()
        case .guestReady:
            simulateGuestReady()
        case .applyGameStarted:
            finishAutoStart()
        case .disconnect:
            triggerReconnect()
        case .resume:
            advanceReconnect()
        case .expireReconnect:
            expireReconnect()
        case .showResult:
            store?.showResult(baseline.result)
        default:
            break
        }
    }

    func visibleControls() -> [MultiplayerShellControl] {
        guard let store else { return [] }

        if let reconnectOverlay = store.reconnectOverlay {
            switch reconnectOverlay.phase {
            case .reconnecting:
                return [
                    MultiplayerShellControl(
                        action: .resume,
                        title: "Receive helloAck",
                        accentColor: reconnectOverlay.phase.accentColor
                    ),
                    MultiplayerShellControl(
                        action: .expireReconnect,
                        title: "Expire Grace",
                        accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                    )
                ]
            case .resyncing:
                return [
                    MultiplayerShellControl(
                        action: .resume,
                        title: "Apply Snapshot",
                        accentColor: reconnectOverlay.phase.accentColor
                    ),
                    MultiplayerShellControl(
                        action: .expireReconnect,
                        title: "Expire Grace",
                        accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                    )
                ]
            case .expired:
                return []
            }
        }

        switch store.route {
        case .entry:
            return []
        case .room:
            var controls: [MultiplayerShellControl] = []
            if store.roomState.members.count < 2 {
                controls.append(
                    MultiplayerShellControl(
                        action: .joinGuest,
                        title: "Guest Join",
                        accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                    )
                )
            } else if store.roomState.members.contains(where: { !$0.isLocalPlayer && !$0.ready }) {
                controls.append(
                    MultiplayerShellControl(
                        action: .guestReady,
                        title: "Guest Ready",
                        accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                    )
                )
            }
            if store.roomState.roomState == .starting {
                controls.append(
                    MultiplayerShellControl(
                        action: .applyGameStarted,
                        title: "Apply gameStarted",
                        accentColor: Color(red: 0.24, green: 0.72, blue: 0.96)
                    )
                )
            }
            return controls
        case .live:
            return [
                MultiplayerShellControl(
                    action: .disconnect,
                    title: "Trigger Reconnect",
                    accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                ),
                MultiplayerShellControl(
                    action: .showResult,
                    title: "Show Result",
                    accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                )
            ]
        case .result:
            return []
        }
    }

    private func simulateGuestJoin() {
        guard let store else { return }
        guard store.route == .room, store.roomState.members.count < 2 else { return }

        var members = store.roomState.members
        members.append(guestMember(ready: false, presence: .connected))
        store.showRoom(roomStateWith(roomState: .waitingForReady, members: members, activeGameId: nil, banner: roomBanner(for: members)))
    }

    private func simulateGuestReady() {
        guard let store else { return }
        guard store.route == .room,
              let guestIndex = store.roomState.members.firstIndex(where: { !$0.isLocalPlayer }) else {
            return
        }

        var members = store.roomState.members
        let guest = members[guestIndex]
        members[guestIndex] = MultiplayerRoomMemberShellState(
            playerId: guest.playerId,
            seat: guest.seat,
            role: guest.role,
            ready: true,
            presence: .connected,
            isLocalPlayer: false
        )
        store.showRoom(
            roomStateWith(
                roomState: lifecycle(for: members),
                members: members,
                activeGameId: nil,
                banner: roomBanner(for: members)
            )
        )
    }

    private func finishAutoStart() {
        guard let store else { return }
        guard store.route == .room, store.roomState.roomState == .starting else { return }

        let nextRoom = roomStateWith(
            roomState: .inGame,
            members: store.roomState.members,
            activeGameId: baseline.live.gameId,
            banner: MultiplayerBannerState(
                style: .info,
                title: "Initial Projection Ready",
                detail: "The room shell has handed off to the live shell using a mock game projection."
            )
        )
        store.showRoom(nextRoom)
        store.showLive(baseline.live)
    }

    private func triggerReconnect() {
        guard let store else { return }
        guard store.route == .live else { return }

        store.updateOverlay(
            MultiplayerReconnectOverlayState(
                phase: .reconnecting,
                roomId: baseline.reconnect.roomId,
                heartbeatIntervalMs: baseline.reconnect.heartbeatIntervalMs,
                disconnectTimeoutMs: baseline.reconnect.disconnectTimeoutMs,
                reconnectGraceMs: baseline.reconnect.reconnectGraceMs,
                graceExpiresAt: Date.now.addingTimeInterval(25),
                lastRoomSequence: baseline.reconnect.lastRoomSequence,
                lastAppliedStateVersion: baseline.reconnect.lastAppliedStateVersion,
                lastSnapshotId: nil
            )
        )
    }

    private func advanceReconnect() {
        guard let store, let reconnectOverlay = store.reconnectOverlay else { return }

        switch reconnectOverlay.phase {
        case .reconnecting:
            store.updateOverlay(
                MultiplayerReconnectOverlayState(
                    phase: .resyncing,
                    roomId: reconnectOverlay.roomId,
                    heartbeatIntervalMs: reconnectOverlay.heartbeatIntervalMs,
                    disconnectTimeoutMs: reconnectOverlay.disconnectTimeoutMs,
                    reconnectGraceMs: reconnectOverlay.reconnectGraceMs,
                    graceExpiresAt: reconnectOverlay.graceExpiresAt,
                    lastRoomSequence: reconnectOverlay.lastRoomSequence + 1,
                    lastAppliedStateVersion: reconnectOverlay.lastAppliedStateVersion,
                    lastSnapshotId: reconnectOverlay.lastSnapshotId
                )
            )
        case .resyncing:
            store.updateOverlay(nil)
        case .expired:
            store.restoreBaselineEntry()
        }
    }

    private func expireReconnect() {
        guard let store, let reconnectOverlay = store.reconnectOverlay else { return }
        store.updateOverlay(
            MultiplayerReconnectOverlayState(
                phase: .expired,
                roomId: reconnectOverlay.roomId,
                heartbeatIntervalMs: reconnectOverlay.heartbeatIntervalMs,
                disconnectTimeoutMs: reconnectOverlay.disconnectTimeoutMs,
                reconnectGraceMs: reconnectOverlay.reconnectGraceMs,
                graceExpiresAt: Date.now,
                lastRoomSequence: reconnectOverlay.lastRoomSequence,
                lastAppliedStateVersion: reconnectOverlay.lastAppliedStateVersion,
                lastSnapshotId: reconnectOverlay.lastSnapshotId
            )
        )
    }

    private func lifecycle(for members: [MultiplayerRoomMemberShellState]) -> MultiplayerRoomLifecycle {
        guard members.count == 2 else { return .waitingForPlayers }
        return members.allSatisfy(\.ready) ? .starting : .waitingForReady
    }

    private func roomBanner(for members: [MultiplayerRoomMemberShellState]) -> MultiplayerBannerState? {
        guard members.count == 2 else {
            return MultiplayerBannerState(
                style: .info,
                title: "Waiting For Guest",
                detail: "The room only has the local seat. A second member is still required."
            )
        }

        if members.allSatisfy(\.ready) {
            return MultiplayerBannerState(
                style: .success,
                title: "Auto-Start Armed",
                detail: "Both ready flags are set. The next step is fresh game projection handoff."
            )
        }

        return MultiplayerBannerState(
            style: .warning,
            title: "Waiting For Ready",
            detail: "The room exists, but both ready flags are not locked yet."
        )
    }

    private func roomStateWith(
        roomState lifecycle: MultiplayerRoomLifecycle,
        members: [MultiplayerRoomMemberShellState],
        activeGameId: String?,
        banner: MultiplayerBannerState?
    ) -> MultiplayerRoomShellState {
        guard let store else { return baseline.room }
        return MultiplayerRoomShellState(
            roomId: store.roomState.roomId,
            roomType: store.roomState.roomType,
            joinPolicy: store.roomState.joinPolicy,
            roomState: lifecycle,
            hostPlayerId: store.roomState.hostPlayerId,
            members: members,
            activeGameId: activeGameId,
            deadlines: store.roomState.deadlines,
            lastRoomSequence: store.roomState.lastRoomSequence + 1,
            inviteCode: store.roomState.inviteCode,
            banner: banner
        )
    }

    private func makeRoomState(
        roomType: MultiplayerRoomType,
        joinPolicy: MultiplayerJoinPolicy,
        includeGuest: Bool
    ) -> MultiplayerRoomShellState {
        var members = [localMember(ready: false)]
        if includeGuest {
            members.append(guestMember(ready: false, presence: .connected))
        }

        return MultiplayerRoomShellState(
            roomId: baseline.room.roomId,
            roomType: roomType,
            joinPolicy: joinPolicy,
            roomState: includeGuest ? .waitingForReady : .waitingForPlayers,
            hostPlayerId: baseline.room.hostPlayerId,
            members: members,
            activeGameId: nil,
            deadlines: baseline.room.deadlines,
            lastRoomSequence: baseline.room.lastRoomSequence + 1,
            inviteCode: nil,
            banner: roomBanner(for: members)
        )
    }

    private func localMember(ready: Bool) -> MultiplayerRoomMemberShellState {
        MultiplayerRoomMemberShellState(
            playerId: baseline.room.hostPlayerId,
            seat: 0,
            role: "host",
            ready: ready,
            presence: .connected,
            isLocalPlayer: true
        )
    }

    private func guestMember(ready: Bool, presence: MultiplayerMemberPresence) -> MultiplayerRoomMemberShellState {
        MultiplayerRoomMemberShellState(
            playerId: baseline.live.opponentPlayerId,
            seat: 1,
            role: "guest",
            ready: ready,
            presence: presence,
            isLocalPlayer: false
        )
    }
}

private struct MultiplayerTransportParticipantIdentity {
    let playerId: String
    let deviceId: String

    static func local(seed: String) -> MultiplayerTransportParticipantIdentity {
        MultiplayerTransportParticipantIdentity(
            playerId: "ios_local_\(seed)",
            deviceId: "ios_local_device_\(seed)"
        )
    }

    static func peer(seed: String) -> MultiplayerTransportParticipantIdentity {
        MultiplayerTransportParticipantIdentity(
            playerId: "ios_peer_\(seed)",
            deviceId: "ios_peer_device_\(seed)"
        )
    }
}

@MainActor
private final class MultiplayerTransportPeerDriver {
    private let options: MultiplayerShellTransportOptions
    private var adapter: MultiplayerWebSocketCommandNetworkingAdapter
    private(set) var identity: MultiplayerTransportParticipantIdentity
    private(set) var attachRequest: MultiplayerShellAttachRequest?

    init(options: MultiplayerShellTransportOptions, identity: MultiplayerTransportParticipantIdentity) {
        self.options = options
        self.identity = identity
        self.adapter = MultiplayerWebSocketCommandNetworkingAdapter(
            options: options,
            clientId: "guest_\(identity.playerId)"
        )
    }

    func reset(identity: MultiplayerTransportParticipantIdentity) async {
        await adapter.resetTransportState()
        self.identity = identity
        self.attachRequest = nil
        self.adapter = MultiplayerWebSocketCommandNetworkingAdapter(
            options: options,
            clientId: "guest_\(identity.playerId)"
        )
    }

    func joinRoom(_ roomId: String) async throws {
        let attachRequest = try await adapter.joinRoomBootstrap(
            MultiplayerShellJoinRoomRequest(
                roomId: roomId,
                playerId: identity.playerId,
                deviceId: identity.deviceId
            )
        )
        self.attachRequest = attachRequest
        try await adapter.connect(using: attachRequest)
        try await discardBufferedEvents()
    }

    func setReady(_ ready: Bool) async throws {
        guard let attachRequest else {
            throw MultiplayerShellRuntimeError.invalidBoundaryState("Guest transport session is not attached yet.")
        }
        try await adapter.setReady(
            MultiplayerShellReadyRequest(
                roomId: attachRequest.roomId,
                playerId: attachRequest.playerId,
                ready: ready
            )
        )
        try await discardBufferedEvents()
    }

    private func discardBufferedEvents() async throws {
        while try await adapter.nextBufferedEvent() != nil {}
    }
}

@MainActor
final class MultiplayerTransportShellSource: MultiplayerShellSource {
    let label = "Transport Route"

    var descriptionText: String {
        mode.descriptionText(endpointURL: options.endpointURL)
    }

    var statusItems: [MultiplayerShellStatusItem] {
        guard let store else { return [] }
        var items = [
            MultiplayerShellStatusItem(label: "Mount", value: mode.statusLabel),
            MultiplayerShellStatusItem(label: "Action", value: lastAction),
            MultiplayerShellStatusItem(label: "Route", value: store.route.label),
            MultiplayerShellStatusItem(label: "Local", value: short(localIdentity.playerId)),
            MultiplayerShellStatusItem(label: "Guest", value: short(peerDriver.attachRequest?.playerId ?? guestIdentity.playerId)),
            MultiplayerShellStatusItem(label: "Peer", value: peerDriver.attachRequest == nil ? "Not Joined" : "Joined"),
            MultiplayerShellStatusItem(label: "Result", value: store.route == .result ? store.resultState.leavePolicy.title : "Idle"),
            MultiplayerShellStatusItem(label: "Gameplay", value: store.gameplayNetworkingAdapter == nil ? "TODO" : "Ready"),
        ]
        if let pendingInviteCode = resolvedInviteCode {
            items.append(MultiplayerShellStatusItem(label: "Invite", value: short(pendingInviteCode)))
        }
        items.append(contentsOf: store.environmentStatusItems)
        return items
    }

    private weak var store: MultiplayerShellStore?
    private let options: MultiplayerShellTransportOptions
    private let mode: MultiplayerTransportMountMode
    private var lastAction = "Idle"
    private var entryInviteCode: String?
    private var localIdentity: MultiplayerTransportParticipantIdentity
    private var guestIdentity: MultiplayerTransportParticipantIdentity
    private let peerDriver: MultiplayerTransportPeerDriver

    init(
        options: MultiplayerShellTransportOptions = .productDefault,
        mode: MultiplayerTransportMountMode = .productPreparation()
    ) {
        self.options = options
        self.mode = mode
        self.entryInviteCode = mode.pendingInviteCode
        let seed = MultiplayerTransportShellSource.identitySeed()
        let localIdentity = MultiplayerTransportParticipantIdentity.local(seed: seed)
        let guestIdentity = MultiplayerTransportParticipantIdentity.peer(seed: seed)
        self.localIdentity = localIdentity
        self.guestIdentity = guestIdentity
        self.peerDriver = MultiplayerTransportPeerDriver(options: options, identity: guestIdentity)
    }

    func visibleEntryActions() -> [MultiplayerEntryAction] {
        guard let store else { return [] }
        var actions: [MultiplayerEntryAction] = []
        if store.roomLifecycleNetworkingAdapter != nil {
            actions.append(contentsOf: [.quickMatch, .createInvite])
            if resolvedInviteCode != nil {
                actions.append(.joinInvite)
            }
        }
        if store.persistedAttachRequestCandidate() != nil {
            actions.append(.resume)
        }
        return actions
    }

    func attach(store: MultiplayerShellStore) {
        self.store = store
    }

    func detach() {
        store = nil
    }

    func updateEntryJoinIdentifier(_ joinIdentifier: String?) {
        guard !mode.exposesPeerDebugControls else { return }
        entryInviteCode = normalizedInviteCode(joinIdentifier)
    }

    func reset() {
        let seed = MultiplayerTransportShellSource.identitySeed()
        entryInviteCode = mode.pendingInviteCode
        localIdentity = MultiplayerTransportParticipantIdentity.local(seed: seed)
        guestIdentity = MultiplayerTransportParticipantIdentity.peer(seed: seed)
        lastAction = "Reset"
        Task { [peerDriver, guestIdentity] in
            await peerDriver.reset(identity: guestIdentity)
        }
        Task { @MainActor [weak store] in
            await store?.resetNetworkingAdapterTransportState()
        }

        store?.showEntry(
            MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: store?.persistedResumeCandidate(),
                lastError: MultiplayerBannerState(
                    style: .info,
                    title: mode.resetBannerTitle,
                    detail: mode.resetBannerDetail
                )
            )
        )
    }

    func handleEntryAction(_ action: MultiplayerEntryAction) {
        switch action {
        case .quickMatch:
            createRoom(roomType: .quickMatch, joinPolicy: .matchmaker, pendingAction: .quickMatch)
        case .createInvite:
            createRoom(roomType: .invite, joinPolicy: .inviteCode, pendingAction: .createInvite)
        case .resume:
            resumePersistedSession()
        case .joinInvite:
            if let pendingInviteCode = resolvedInviteCode {
                joinRoom(pendingInviteCode)
            } else {
                applyEntryFailure(
                    code: "entryActionUnavailable",
                    messageKey: "entry.action.unavailable",
                    error: MultiplayerShellRuntimeError.invalidBoundaryState(
                        "Join Invite needs inviteCode from the outer product route or product entry input before this transport source can send room_join."
                    )
                )
            }
        }
    }

    func handleControlAction(_ action: MultiplayerShellControlAction) {
        switch action {
        case .joinGuest:
            guard mode.exposesPeerDebugControls else { return }
            joinGuest()
        case .ready:
            toggleLocalReady()
        case .guestReady:
            guard mode.exposesPeerDebugControls else { return }
            toggleGuestReady()
        case .applyGameStarted:
            guard mode.exposesPeerDebugControls else { return }
            applyGameStarted()
        case .applyMatchEnded:
            guard mode.exposesPeerDebugControls else { return }
            applyMatchEnded()
        case .resume:
            resumePersistedSession()
        case .leaveRoom:
            leaveCurrentRoom()
        case .playFirstCard:
            playFirstCard()
        case .submitFirstChoice:
            submitFirstChoice()
        case .quitMatch:
            quitMatch()
        default:
            break
        }
    }

    func visibleControls() -> [MultiplayerShellControl] {
        guard let store else { return [] }
        if store.reconnectOverlay != nil, store.persistedAttachRequestCandidate() != nil {
            return [
                MultiplayerShellControl(
                    action: .resume,
                    title: "Resume Transport",
                    accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                )
            ]
        }

        switch store.route {
        case .entry:
            return []
        case .room:
            guard mode.exposesPeerDebugControls else { return [] }
            var controls: [MultiplayerShellControl] = []
            if store.roomState.members.count < 2 {
                controls.append(
                    MultiplayerShellControl(
                        action: .joinGuest,
                        title: "Join Guest",
                        accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                    )
                )
            } else {
                let guestReady = store.roomState.members.first(where: { !$0.isLocalPlayer })?.ready ?? false
                controls.append(
                    MultiplayerShellControl(
                        action: .guestReady,
                        title: guestReady ? "Guest Unready" : "Guest Ready",
                        accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                    )
                )
            }
            if store.roomState.roomState == .starting {
                controls.append(
                    MultiplayerShellControl(
                        action: .applyGameStarted,
                        title: "Apply gameStarted",
                        accentColor: Color(red: 0.24, green: 0.72, blue: 0.96)
                    )
                )
            }
            return controls
        case .live:
            var controls: [MultiplayerShellControl] = []
            if mode.exposesPeerDebugControls {
                controls.append(
                    MultiplayerShellControl(
                        action: .applyMatchEnded,
                        title: "Apply matchEnded",
                        accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                    )
                )
            }
            return controls
        case .result:
            return []
        }
    }

    private func createRoom(
        roomType: MultiplayerRoomType,
        joinPolicy: MultiplayerJoinPolicy,
        pendingAction: MultiplayerEntryAction
    ) {
        guard let store else { return }
        lastAction = pendingAction.title
        store.showEntry(
            MultiplayerShellMapper.entryState(
                persistedResume: store.persistedResumeCandidate(),
                pendingAction: pendingAction
            )
        )

        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                await self.peerDriver.reset(identity: self.guestIdentity)
                try await store.createRoomUsingNetworkingAdapter(
                    roomType: roomType,
                    joinPolicy: joinPolicy,
                    playerId: self.localIdentity.playerId,
                    deviceId: self.localIdentity.deviceId
                )
                self.lastAction = "\(pendingAction.title) Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "\(pendingAction.title) Failed"
                self.applyEntryFailure(
                    code: "roomCreateFailed",
                    messageKey: "entry.resume.transport_unavailable",
                    error: error
                )
            }
        }
    }

    private func joinRoom(_ roomId: String) {
        guard let store else { return }
        lastAction = "Join Invite"
        store.showEntry(
            MultiplayerShellMapper.entryState(
                persistedResume: store.persistedResumeCandidate(),
                pendingAction: .joinInvite
            )
        )

        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.joinRoomUsingNetworkingAdapter(
                    roomId: roomId,
                    playerId: self.localIdentity.playerId,
                    deviceId: self.localIdentity.deviceId
                )
                self.lastAction = "Join Invite Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Join Invite Failed"
                self.applyEntryFailure(
                    code: "roomJoinFailed",
                    messageKey: "entry.resume.transport_unavailable",
                    error: error
                )
            }
        }
    }

    private func playFirstCard() {
        guard let store,
              let cardId = store.liveState.localPlayableCardIds.first else { return }
        lastAction = "Play First Card"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.sendPlayCardUsingNetworkingAdapter(cardId: cardId)
                self.lastAction = "playCard Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "playCard Failed"
                self.applyRouteFailure(title: "playCard Failed", error: error)
            }
        }
    }

    private func submitFirstChoice() {
        guard let store,
              let pendingChoice = store.liveState.pendingChoice,
              let option = pendingChoice.options.first else { return }
        lastAction = "Submit First Choice"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.sendChoiceUsingNetworkingAdapter(
                    choiceId: pendingChoice.choiceId,
                    optionCode: option.optionCode
                )
                self.lastAction = "submitChoice Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "submitChoice Failed"
                self.applyRouteFailure(title: "submitChoice Failed", error: error)
            }
        }
    }

    private func quitMatch() {
        guard let store else { return }
        lastAction = "Quit Match"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.sendQuitUsingNetworkingAdapter(reasonCode: MultiplayerQuitReason.voluntaryExit.rawValue)
                self.lastAction = "quit Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "quit Failed"
                self.applyRouteFailure(title: "quit Failed", error: error)
            }
        }
    }

    private func resumePersistedSession() {
        guard let store else { return }
        lastAction = "Resume"
        store.showEntry(
            MultiplayerShellMapper.entryState(
                persistedResume: store.persistedResumeCandidate(),
                pendingAction: .resume
            )
        )

        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                await self.peerDriver.reset(identity: self.guestIdentity)
                try await store.resumePersistedSessionOverTransport()
                self.lastAction = "Resume Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Resume Failed"
                self.applyEntryFailure(
                    code: "resumeTransportUnavailable",
                    messageKey: "entry.resume.transport_unavailable",
                    error: error
                )
            }
        }
    }

    private func joinGuest() {
        guard let store else { return }
        lastAction = "Join Guest"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await self.peerDriver.joinRoom(store.roomState.roomId)
                try await store.requestRoomSnapshotUsingNetworkingAdapter()
                self.lastAction = "Guest Joined"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Join Guest Failed"
                self.applyRouteFailure(title: "Guest Join Failed", error: error)
            }
        }
    }

    private func toggleLocalReady() {
        guard let store else { return }
        let nextReady = !(store.roomState.members.first(where: \.isLocalPlayer)?.ready ?? false)
        lastAction = nextReady ? "Ready" : "Unready"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.setReadyUsingNetworkingAdapter(ready: nextReady)
                self.lastAction = nextReady ? "Ready Sent" : "Unready Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Ready Failed"
                self.applyRouteFailure(title: "Ready Failed", error: error)
            }
        }
    }

    private func toggleGuestReady() {
        guard let store else { return }
        let nextReady = !(store.roomState.members.first(where: { !$0.isLocalPlayer })?.ready ?? false)
        lastAction = nextReady ? "Guest Ready" : "Guest Unready"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await self.peerDriver.setReady(nextReady)
                try await store.requestRoomSnapshotUsingNetworkingAdapter()
                self.lastAction = nextReady ? "Guest Ready Sent" : "Guest Unready Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Guest Ready Failed"
                self.applyRouteFailure(title: "Guest Ready Failed", error: error)
            }
        }
    }

    private func applyGameStarted() {
        guard let store else { return }
        lastAction = "Apply gameStarted"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.recordGameStartedUsingNetworkingAdapter(
                    gameId: "transport_game_\(store.roomState.roomId)"
                )
                self.lastAction = "gameStarted Applied"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "gameStarted Failed"
                self.applyRouteFailure(title: "gameStarted Failed", error: error)
            }
        }
    }

    private func applyMatchEnded() {
        guard let store else { return }
        lastAction = "Apply matchEnded"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.recordMatchEndedUsingNetworkingAdapter(
                    roundIndex: store.resultState.roundIndex,
                    quitReason: "disconnectTimeout",
                    forfeitingPlayerId: self.guestIdentity.playerId
                )
                self.lastAction = "matchEnded Applied"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "matchEnded Failed"
                self.applyRouteFailure(title: "matchEnded Failed", error: error)
            }
        }
    }

    private func leaveCurrentRoom() {
        guard let store else { return }
        lastAction = "Leave Room"
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            do {
                try await store.sendLeaveRoomUsingNetworkingAdapter()
                await self.peerDriver.reset(identity: self.guestIdentity)
                self.lastAction = "Leave Sent"
                store.refreshSourceUI()
            } catch {
                self.lastAction = "Leave Failed"
                if store.route == .result {
                    store.showResult(
                        store.resultState.with(
                            leavePolicy: .leaveAvailable,
                            integrationNotes: [
                                "match.result.leave.transport_error",
                                error.localizedDescription,
                            ] + store.resultState.integrationNotes
                        )
                    )
                } else {
                    self.applyRouteFailure(title: "Leave Failed", error: error)
                }
            }
        }
    }

    private func applyEntryFailure(
        code: String,
        messageKey: String,
        error: Error
    ) {
        guard let store else { return }
        store.showEntry(
            MultiplayerShellMapper.entryState(
                persistedResume: store.persistedResumeCandidate(),
                lastError: MultiplayerEntryErrorPayload(
                    code: code,
                    messageKey: messageKey,
                    detail: error.localizedDescription
                )
            )
        )
    }

    private func applyRouteFailure(title: String, error: Error) {
        guard let store else { return }
        let banner = MultiplayerBannerState(
            style: .error,
            title: title,
            detail: error.localizedDescription
        )
        switch store.route {
        case .entry:
            applyEntryFailure(
                code: "transportActionFailed",
                messageKey: "entry.resume.transport_unavailable",
                error: error
            )
        case .room:
            store.showRoom(
                store.roomState.with(banner: banner),
                persistedResume: store.persistedResumeCandidate()
            )
        case .live:
            store.showLive(
                store.liveState.with(connectionBanner: banner),
                overlay: store.reconnectOverlay
            )
        case .result:
            store.showResult(
                store.resultState.with(
                    integrationNotes: [error.localizedDescription] + store.resultState.integrationNotes
                )
            )
        }
    }

    private func short(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "-"
        }
        if value.count <= 12 {
            return value
        }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    private static func identitySeed() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    private var resolvedInviteCode: String? {
        normalizedInviteCode(entryInviteCode ?? mode.pendingInviteCode)
    }

    private func normalizedInviteCode(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
@MainActor
final class MultiplayerLocalDebugShellSource: MultiplayerShellSource {
    let label = "Local Debug"
    let descriptionText = "DEBUG coordinator source. Host/guest attach, ready, gameStarted, disconnect, resume, matchEnded, and leaveRoom come from LocalRoomCoordinatorDebugService. Persisted session and network adapter boundaries are injected through MultiplayerShellStore."

    var statusItems: [MultiplayerShellStatusItem] {
        var items: [MultiplayerShellStatusItem] = [
            MultiplayerShellStatusItem(label: "Action", value: lastAction),
            MultiplayerShellStatusItem(label: "Room", value: short(context.roomId)),
            MultiplayerShellStatusItem(label: "Session", value: short(context.localSessionId)),
            MultiplayerShellStatusItem(label: "Resume", value: short(context.localResumeToken)),
            MultiplayerShellStatusItem(label: "Conn", value: short(context.localConnectionId))
        ]
        if let gameId = effectiveGameId {
            items.append(MultiplayerShellStatusItem(label: "Game", value: short(gameId)))
        }
        if let roomState {
            items.append(MultiplayerShellStatusItem(label: "State", value: roomState.label))
        }
        if let presence {
            items.append(MultiplayerShellStatusItem(label: "Presence", value: presence.label))
        }
        if let store {
            items.append(contentsOf: store.environmentStatusItems)
        }
        return items
    }

    private weak var store: MultiplayerShellStore?
    private let service: LocalRoomCoordinatorDebugService
    private var context = MultiplayerLocalDebugContext()
    private var lastAction = "Idle"
    private var roomState: MultiplayerRoomLifecycle?
    private var presence: MultiplayerMemberPresence?
    private var projectionGameManager: GameManager?
    private var projectionGameId: String?

    init(service: LocalRoomCoordinatorDebugService) {
        self.service = service
    }

    convenience init() {
        self.init(service: MultiplayerDebugServices.roomCoordinator)
    }

    func visibleEntryActions() -> [MultiplayerEntryAction] {
        [.quickMatch, .createInvite]
    }

    func attach(store: MultiplayerShellStore) {
        self.store = store
    }

    func detach() {
        store = nil
    }

    func reset() {
        service.reset()
        context = MultiplayerLocalDebugContext()
        roomState = nil
        presence = nil
        projectionGameManager = nil
        projectionGameId = nil
        lastAction = "Reset"
        store?.showEntry(debugEntryState(banner: MultiplayerBannerState(
            style: .info,
            title: "Local Debug Idle",
            detail: "Create Room starts the local coordinator flow and performs the first hello attach."
        )))
    }

    func handleEntryAction(_ action: MultiplayerEntryAction) {
        do {
            switch action {
            case .quickMatch:
                try createRoom(roomType: .quickMatch, joinPolicy: .matchmaker, actionLabel: "Create Quick Match")
            case .createInvite:
                try createRoom(roomType: .invite, joinPolicy: .inviteCode, actionLabel: "Create Invite")
            case .joinInvite:
                if context.roomId == nil {
                    try createRoom(roomType: .invite, joinPolicy: .inviteCode, actionLabel: "Create Invite")
                } else {
                    try joinGuest()
                }
            case .resume:
                try resume()
            }
        } catch {
            applyErrorBanner(for: action, error: error)
        }
    }

    func handleControlAction(_ action: MultiplayerShellControlAction) {
        do {
            switch action {
            case .createRoom:
                try createRoom()
            case .joinGuest:
                try joinGuest()
            case .leaveRoom:
                try leaveRoom()
            case .ready:
                try toggleReady()
            case .guestReady:
                try toggleGuestReady()
            case .disconnect:
                try disconnect()
            case .resume:
                try resume()
            case .heartbeat:
                try heartbeat()
            case .applyGameStarted:
                try applyGameStarted()
            case .applyMatchEnded:
                try applyMatchEnded()
            default:
                break
            }
        } catch {
            applyErrorBanner(for: action, error: error)
        }
    }

    func visibleControls() -> [MultiplayerShellControl] {
        if context.roomId == nil {
            return [
                MultiplayerShellControl(
                    action: .createRoom,
                    title: "Create Room",
                    accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                )
            ]
        }

        if currentLocalSession?.connectionState == .disconnectedGrace {
            return [
                MultiplayerShellControl(
                    action: .resume,
                    title: "Resume",
                    accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                )
            ]
        }

        switch currentLocalSession?.connectionState {
        case .resuming, .expired, .replaced:
            return []
        default:
            break
        }

        var controls: [MultiplayerShellControl] = []
        if context.guestSessionId == nil {
            controls.append(
                MultiplayerShellControl(
                    action: .joinGuest,
                    title: "Join Guest",
                    accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                )
            )
        }
        if let guestMember = currentGuestMember, !guestMember.ready, effectiveRoomLifecycle != .inGame {
            controls.append(
                MultiplayerShellControl(
                    action: .guestReady,
                    title: "Guest Ready",
                    accentColor: Color(red: 0.24, green: 0.72, blue: 0.96)
                )
            )
        }
        if effectiveRoomLifecycle == .starting {
            controls.append(
                MultiplayerShellControl(
                    action: .applyGameStarted,
                    title: "Apply gameStarted",
                    accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                )
            )
        }
        switch currentLocalSession?.connectionState {
        case .connected:
            controls.append(
                MultiplayerShellControl(
                    action: .disconnect,
                    title: "Disconnect",
                    accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                )
            )
            controls.append(
                MultiplayerShellControl(
                    action: .heartbeat,
                    title: "Heartbeat",
                    accentColor: Color(red: 0.24, green: 0.72, blue: 0.96)
                )
            )
            if effectiveRoomLifecycle == .inGame {
                controls.append(
                    MultiplayerShellControl(
                        action: .applyMatchEnded,
                        title: "Apply matchEnded",
                        accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                    )
                )
            }
        default:
            break
        }
        return controls
    }

    private var currentSnapshot: RoomCoordinatorSnapshot? {
        guard let roomId = context.roomId else { return nil }
        return service.snapshot(roomId: roomId)
    }

    private var currentLocalSession: RoomSession? {
        currentSnapshot?.sessions.first(where: { $0.playerId == context.localPlayerId })
    }

    private var currentLocalMember: RoomMember? {
        currentSnapshot?.room.members.first(where: { $0.playerId == context.localPlayerId })
    }

    private var currentGuestSession: RoomSession? {
        currentSnapshot?.sessions.first(where: { $0.playerId == context.guestPlayerId })
    }

    private var currentGuestMember: RoomMember? {
        currentSnapshot?.room.members.first(where: { $0.playerId == context.guestPlayerId })
    }

    private var effectiveGameId: String? {
        currentSnapshot?.room.activeGameId ?? context.debugGameId
    }

    private var effectiveRoomLifecycle: MultiplayerRoomLifecycle {
        guard let snapshot = currentSnapshot else { return roomState ?? .waitingForPlayers }
        return effectiveRoomLifecycle(from: snapshot)
    }

    private func createRoom(
        roomType: RoomType = .invite,
        joinPolicy: RoomJoinPolicy = .inviteCode,
        actionLabel: String = "Create Room"
    ) throws {
        let mutation = try service.createRoom(
            CreateRoomRequest(
                hostPlayerId: context.localPlayerId,
                deviceId: context.localDeviceId,
                roomType: roomType,
                joinPolicy: joinPolicy
            )
        )
        let hello = try service.helloHost(
            roomId: mutation.snapshot.room.roomId,
            connectionId: nextConnectionId(),
            lastAckedRoomSequence: mutation.snapshot.room.lastRoomSequence
        )
        lastAction = actionLabel
        applySnapshot(hello.mutation.snapshot, helloAck: hello.helloAck)
    }

    private func joinGuest() throws {
        guard let roomId = context.roomId else {
            throw localDebugError("Create Room first before joining a guest seat.")
        }
        let mutation = try service.joinRoom(
            JoinRoomRequest(
                roomId: roomId,
                playerId: context.guestPlayerId,
                deviceId: context.guestDeviceId
            )
        )
        let hello = try service.helloGuest(
            roomId: roomId,
            connectionId: nextConnectionId(),
            lastAckedRoomSequence: mutation.snapshot.room.lastRoomSequence
        )
        lastAction = "Join Guest"
        applySnapshot(hello.mutation.snapshot, helloAck: hello.helloAck)
    }

    private func toggleReady() throws {
        guard let roomId = context.roomId,
              let localMember = currentLocalMember else {
            throw localDebugError("No local room member is attached yet.")
        }
        let mutation = try service.setReady(
            SetReadyRequest(
                roomId: roomId,
                playerId: context.localPlayerId,
                ready: !localMember.ready
            )
        )
        lastAction = localMember.ready ? "Unready" : "Ready"
        applySnapshot(mutation.snapshot)
    }

    private func toggleGuestReady() throws {
        guard let roomId = context.roomId,
              let guestMember = currentGuestMember else {
            throw localDebugError("Guest seat is not attached yet.")
        }
        let mutation = try service.setGuestReady(roomId: roomId, ready: !guestMember.ready)
        lastAction = guestMember.ready ? "Guest Unready" : "Guest Ready"
        applySnapshot(mutation.snapshot)
    }

    private func applyGameStarted() throws {
        guard let snapshot = currentSnapshot,
              let roomId = context.roomId else {
            throw localDebugError("Room snapshot is unavailable.")
        }
        guard effectiveRoomLifecycle(from: snapshot) == .starting else {
            throw localDebugError("Apply gameStarted is only valid after both players are ready.")
        }
        let mutation = try service.recordGameStarted(roomId: roomId)
        lastAction = "Apply gameStarted"
        applySnapshot(mutation.snapshot)
    }

    private func disconnect() throws {
        guard let roomId = context.roomId else {
            throw localDebugError("Create Room first before disconnecting.")
        }
        let mutation = try service.disconnect(
            DisconnectMemberRequest(
                roomId: roomId,
                playerId: context.localPlayerId
            )
        )
        lastAction = "Disconnect"
        applySnapshot(mutation.snapshot)
    }

    private func resume() throws {
        guard let roomId = context.roomId,
              let session = currentLocalSession else {
            throw localDebugError("No disconnected local session is available to resume.")
        }
        let hello = try service.hello(
            roomId: roomId,
            sessionId: session.sessionId,
            playerId: context.localPlayerId,
            deviceId: context.localDeviceId,
            connectionId: nextConnectionId(),
            resumeToken: context.localResumeToken ?? session.resumeToken,
            lastAckedRoomSequence: currentSnapshot?.room.lastRoomSequence,
            lastSeenStateVersion: nil
        )
        lastAction = "Resume"
        applySnapshot(hello.mutation.snapshot, helloAck: hello.helloAck)
    }

    private func heartbeat() throws {
        guard let roomId = context.roomId,
              let session = currentLocalSession else {
            throw localDebugError("No active local session is available for heartbeat.")
        }
        let mutation = try service.heartbeat(
            RecordHeartbeatRequest(
                roomId: roomId,
                sessionId: session.sessionId,
                connectionId: context.localConnectionId,
                lastAckedRoomSequence: currentSnapshot?.room.lastRoomSequence,
                lastAckedGameEventId: nil,
                lastSeenStateVersion: nil
            )
        )
        lastAction = "Heartbeat"
        applySnapshot(mutation.snapshot)
    }

    private func applyMatchEnded() throws {
        guard let store else { return }
        guard store.route == .live else {
            throw localDebugError("Apply matchEnded is only valid from the live route.")
        }
        guard let roomId = context.roomId else {
            throw localDebugError("Room identity is unavailable for terminal summary generation.")
        }

        let gameId = store.liveState.gameId
        let gameManager = liveProjectionGameManager(for: gameId)
        let relayResult = try service.recordMatchEndedAndFetchTerminalSummary(
            roomId: roomId,
            roundIndex: 1,
            quitReason: MultiplayerQuitReason.voluntaryExit.rawValue,
            forfeitingPlayerId: nil,
            summaryStateVersion: 1,
            lastEventId: store.liveState.turnId,
            using: gameManager
        )
        applySnapshot(relayResult.mutation.snapshot)
        guard let terminalSummary = TestControlSupport.multiplayerTerminalSummaryPayload(
            from: gameManager,
            requestData: roomTerminalSummaryRelayRequestData(from: relayResult.terminalSummaryRequest)
        ) else {
            throw localDebugError("Authoritative terminal summary payload is unavailable for the current local debug context.")
        }
        lastAction = "Apply matchEnded"
        roomState = .ended
        store.handleInboundEvent(
            .matchEnded(
                roundEnded: terminalSummary.roundEnded,
                matchEnded: terminalSummary.matchEnded
            )
        )
    }

    private func leaveRoom() throws {
        guard let store else { return }
        guard let roomId = context.roomId else {
            throw localDebugError("No active room exists for leaveRoom.")
        }

        if store.route == .result {
            store.updateResultLeavePolicy(.pendingLeaveAcknowledgement)
        }

        let mutation = try service.leaveRoom(
            LeaveRoomRequest(
                roomId: roomId,
                playerId: context.localPlayerId
            )
        )
        lastAction = "Leave Room"

        let acknowledgement = leaveAcknowledgement(from: mutation)
        context.clearLocalMembership()
        roomState = lifecycle(from: mutation.snapshot.room.roomState)
        presence = nil

        switch store.route {
        case .result:
            store.handleInboundEvent(.leaveAcknowledged(acknowledgement))
        case .room:
            if let roomClosed = acknowledgement.roomClosed {
                store.handleInboundEvent(.roomClosed(roomClosed))
            } else {
                applySnapshot(mutation.snapshot)
            }
        default:
            store.handleInboundEvent(.leaveAcknowledged(acknowledgement))
        }
    }

    private func applySnapshot(
        _ snapshot: RoomCoordinatorSnapshot,
        helloAck: LocalRoomDebugHelloAck? = nil
    ) {
        guard let store else { return }

        let localSession = snapshot.sessions.first(where: { $0.playerId == context.localPlayerId })
        context.update(from: snapshot, helloAck: helloAck)
        let payload = MultiplayerRoomSnapshotPayload(
            roomId: snapshot.room.roomId,
            roomType: roomType(from: snapshot.room.roomType),
            joinPolicy: joinPolicy(from: snapshot.room.joinPolicy),
            roomState: effectiveRoomLifecycle(from: snapshot),
            hostPlayerId: snapshot.room.hostPlayerId,
            members: snapshot.room.members
                .sorted(by: { $0.seat < $1.seat })
                .map { member in
                    MultiplayerRoomMemberPayload(
                        playerId: member.playerId,
                        seat: member.seat,
                        role: member.role.rawValue,
                        ready: member.ready,
                        presence: presencePayload(member: member, snapshot: snapshot),
                        isLocalPlayer: member.playerId == context.localPlayerId
                    )
                },
            activeGameId: effectiveGameId(from: snapshot),
            deadlines: MultiplayerRoomDeadlinesPayload(
                joinExpiresAt: formatDate(snapshot.room.deadlines.joinExpiresAt),
                readyExpiresAt: formatDate(snapshot.room.deadlines.readyExpiresAt)
            ),
            lastRoomSequence: snapshot.room.lastRoomSequence,
            inviteCode: nil,
            persistedResume: context.persistedResume(lastKnownGameId: effectiveGameId(from: snapshot))
        )
        let mappedRoom = MultiplayerShellMapper.roomState(from: payload)
        roomState = mappedRoom.roomState
        presence = mappedRoom.members.first(where: \.isLocalPlayer)?.presence

        if mappedRoom.activeGameId == nil, mappedRoom.roomState != .inGame {
            projectionGameManager = nil
            projectionGameId = nil
        }

        let overlay: MultiplayerReconnectOverlayState?
        if let localSession,
           localSession.connectionState == .disconnectedGrace {
            overlay = MultiplayerShellMapper.reconnectOverlay(
                phase: .reconnecting,
                context: MultiplayerReconnectContextPayload(
                    roomId: snapshot.room.roomId,
                    heartbeatIntervalMs: milliseconds(RoomCoordinatorConfiguration.phase0.heartbeatInterval),
                    disconnectTimeoutMs: milliseconds(RoomCoordinatorConfiguration.phase0.disconnectTimeout),
                    reconnectGraceMs: milliseconds(RoomCoordinatorConfiguration.phase0.reconnectGrace),
                    graceExpiresAt: formatDate(localSession.graceExpiresAt),
                    lastRoomSequence: snapshot.room.lastRoomSequence,
                    lastAppliedStateVersion: nil,
                    lastSnapshotId: nil
                )
            )
        } else {
            overlay = nil
        }

        let persistedResume = context.persistedResume(lastKnownGameId: effectiveGameId(from: snapshot))
        let entryBanner = helloAck.map(helloAckBanner)

        if mappedRoom.roomState == .inGame {
            store.cacheRoom(
                mappedRoom,
                persistedResume: persistedResume,
                entryBanner: entryBanner
            )
            store.showLive(
                makeLiveState(
                    from: mappedRoom,
                    helloAck: helloAck
                ),
                overlay: overlay
            )
            return
        }

        store.showRoom(
            mappedRoom,
            overlay: overlay,
            persistedResume: persistedResume,
            entryBanner: entryBanner
        )
    }

    private func applyErrorBanner(for action: MultiplayerEntryAction, error: Error) {
        lastAction = "\(action.rawValue): failed"
        guard let store else { return }
        store.showEntry(
            MultiplayerEntryShellState(
                pendingAction: nil,
                persistedResume: context.persistedResume(lastKnownGameId: currentSnapshot?.room.activeGameId),
                lastError: MultiplayerBannerState(
                    style: .warning,
                    title: "Local Debug Error",
                    detail: String(describing: error),
                    messageKey: "local.debug.error"
                )
            )
        )
    }

    private func applyErrorBanner(for action: MultiplayerShellControlAction, error: Error) {
        lastAction = "\(action.rawValue): failed"
        guard let store else { return }
        let banner = MultiplayerBannerState(
            style: .warning,
            title: "Local Debug Error",
            detail: String(describing: error),
            messageKey: "local.debug.error"
        )
        switch store.route {
        case .entry:
            store.showEntry(debugEntryState(banner: banner))
        case .room:
            store.showRoom(
                MultiplayerRoomShellState(
                    roomId: store.roomState.roomId,
                    roomType: store.roomState.roomType,
                    joinPolicy: store.roomState.joinPolicy,
                    roomState: store.roomState.roomState,
                    hostPlayerId: store.roomState.hostPlayerId,
                    members: store.roomState.members,
                    activeGameId: store.roomState.activeGameId,
                    deadlines: store.roomState.deadlines,
                    lastRoomSequence: store.roomState.lastRoomSequence,
                    inviteCode: store.roomState.inviteCode,
                    banner: banner
                ),
                overlay: store.reconnectOverlay,
                persistedResume: store.entryState.persistedResume,
                entryBanner: banner
            )
        case .live:
            store.showLive(
                MultiplayerLiveShellState(
                    roomId: store.liveState.roomId,
                    gameId: store.liveState.gameId,
                    localPlayerId: store.liveState.localPlayerId,
                    stateVersion: store.liveState.stateVersion,
                    currentPlayerId: store.liveState.currentPlayerId,
                    phase: store.liveState.phase,
                    turnId: store.liveState.turnId,
                    turnDeadlineAt: store.liveState.turnDeadlineAt,
                    serverTime: store.liveState.serverTime,
                    opponentPlayerId: store.liveState.opponentPlayerId,
                    opponentHandCount: store.liveState.opponentHandCount,
                    localHandCount: store.liveState.localHandCount,
                    localPlayableCardIds: store.liveState.localPlayableCardIds,
                    pendingChoice: store.liveState.pendingChoice,
                    lastReject: store.liveState.lastReject,
                    connectionBanner: banner
                ),
                overlay: store.reconnectOverlay
            )
        case .result:
            store.showResult(
                store.resultState.with(
                    leavePolicy: .leaveAvailable,
                    integrationNotes: [banner.detail] + store.resultState.integrationNotes
                )
            )
        }
    }

    private func debugEntryState(banner: MultiplayerBannerState?) -> MultiplayerEntryShellState {
        MultiplayerEntryShellState(
            pendingAction: nil,
            persistedResume: context.persistedResume(lastKnownGameId: currentSnapshot?.room.activeGameId)
                ?? store?.persistedResumeCandidate(),
            lastError: banner
        )
    }

    private func leaveAcknowledgement(
        from mutation: RoomCoordinatorMutation
    ) -> MultiplayerLeaveAcknowledgementPayload {
        let roomClosed = mutation.events.compactMap(roomClosedPayload).first
        return MultiplayerLeaveAcknowledgementPayload(
            roomId: mutation.snapshot.room.roomId,
            playerId: context.localPlayerId,
            roomState: lifecycle(from: mutation.snapshot.room.roomState),
            messageKey: roomClosed == nil ? "match.result.leave.acknowledged" : "match.result.leave.completed_by_room_closed",
            roomClosed: roomClosed
        )
    }

    private func roomClosedPayload(
        from event: RoomCoordinatorEvent
    ) -> MultiplayerRoomClosedPayload? {
        switch event.payload {
        case let .roomClosed(reason, closedAt):
            return MultiplayerRoomClosedPayload(
                roomId: event.roomId,
                reasonCode: reason.rawValue,
                messageKey: "room.closed.\(reason.rawValue)",
                closedAt: formatDate(closedAt)
            )
        default:
            return nil
        }
    }

    private func helloAckBanner(_ helloAck: LocalRoomDebugHelloAck) -> MultiplayerBannerState {
        MultiplayerBannerState(
            style: helloAck.resumeMode == .resume ? .success : .info,
            title: helloAck.resumeMode == .resume ? "Resume Accepted" : "Fresh Attach",
            detail: "Local debug helloAck rotated the resume token and refreshed connection state."
        )
    }

    private func makeLiveState(
        from roomState: MultiplayerRoomShellState,
        helloAck: LocalRoomDebugHelloAck?
    ) -> MultiplayerLiveShellState {
        let localPlayerId = roomState.members.first(where: \.isLocalPlayer)?.playerId ?? context.localPlayerId
        let activeGameId = roomState.activeGameId ?? context.debugGameId ?? "game_pending"
        let bootstrapPayload = TestControlSupport.multiplayerLiveBootstrapPayload(
            from: liveProjectionGameManager(for: activeGameId),
            requestData: [
                "roomId": roomState.roomId,
                "gameId": activeGameId,
                "viewerPlayerId": localPlayerId,
                "participantPresenceByPlayerId": participantPresencePayload(from: roomState.members)
            ]
        )

        let liveState = MultiplayerShellMapper.liveState(
            from: bootstrapPayload.stateSnapshot,
            serverTime: nil
        )
        return MultiplayerLiveShellState(
            roomId: liveState.roomId,
            gameId: liveState.gameId,
            localPlayerId: liveState.localPlayerId,
            stateVersion: liveState.stateVersion,
            currentPlayerId: liveState.currentPlayerId,
            phase: liveState.phase,
            turnId: liveState.turnId,
            turnDeadlineAt: liveState.turnDeadlineAt,
            serverTime: liveState.serverTime,
            opponentPlayerId: liveState.opponentPlayerId,
            opponentHandCount: liveState.opponentHandCount,
            localHandCount: liveState.localHandCount,
            localPlayableCardIds: liveState.localPlayableCardIds,
            pendingChoice: liveState.pendingChoice,
            lastReject: liveState.lastReject,
            connectionBanner: liveBanner(roomState: roomState, helloAck: helloAck)
        )
    }

    private func liveBanner(
        roomState: MultiplayerRoomShellState,
        helloAck: LocalRoomDebugHelloAck?
    ) -> MultiplayerBannerState? {
        if let localMember = roomState.members.first(where: \.isLocalPlayer),
           localMember.presence == .disconnectedGrace || localMember.presence == .resuming {
            return MultiplayerBannerState(
                style: .warning,
                title: "Local Session Interrupted",
                detail: "Reconnect overlay is driven by room truth while the live shell keeps the last debug projection visible."
            )
        }

        if let opponentMember = roomState.members.first(where: { !$0.isLocalPlayer }),
           opponentMember.presence == .disconnectedGrace || opponentMember.presence == .resuming {
            return MultiplayerBannerState(
                style: .warning,
                title: "Guest Reconnecting",
                detail: "The guest seat is still owned. Live projection stays visible until room truth settles."
            )
        }

        if helloAck?.resumeMode == .resume {
            return MultiplayerBannerState(
                style: .success,
                title: "Resume Applied",
                detail: "Room/session recovery is real. Live projection successfully resumed from authoritative state."
            )
        }

        return MultiplayerBannerState(
            style: .success,
            title: "Live Payload Active",
            detail: "Room transitions and live state projections are fully assembled from GameManager authoritative bootstrap payload."
        )
    }

    private func presencePayload(member: RoomMember, snapshot: RoomCoordinatorSnapshot) -> MultiplayerRoomMemberPresencePayload {
        if let session = snapshot.sessions.first(where: { $0.sessionId == member.sessionId }) {
            switch session.connectionState {
            case .connected:
                return .connected
            case .disconnectedGrace:
                return .disconnectedGrace
            case .resuming:
                return .resuming
            case .expired:
                return .expired
            case .replaced:
                return .replaced
            }
        }
        return member.presence == .left ? .expired : .connected
    }

    private func roomType(from type: RoomType) -> MultiplayerRoomType {
        type == .invite ? .invite : .quickMatch
    }

    private func joinPolicy(from policy: RoomJoinPolicy) -> MultiplayerJoinPolicy {
        policy == .inviteCode ? .inviteCode : .matchmaker
    }

    private func lifecycle(from state: RoomState) -> MultiplayerRoomLifecycle {
        switch state {
        case .waitingForPlayers:
            return .waitingForPlayers
        case .waitingForReady:
            return .waitingForReady
        case .starting:
            return .starting
        case .inGame:
            return .inGame
        case .ended:
            return .ended
        case .closed:
            return .closed
        }
    }

    private func effectiveRoomLifecycle(from snapshot: RoomCoordinatorSnapshot) -> MultiplayerRoomLifecycle {
        lifecycle(from: snapshot.room.roomState)
    }

    private func effectiveGameId(from snapshot: RoomCoordinatorSnapshot) -> String? {
        snapshot.room.activeGameId ?? context.debugGameId
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return MultiplayerShellDateFormatting.full.string(from: date)
    }

    private func localDebugError(_ detail: String) -> NSError {
        NSError(domain: "LocalDebug", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }

    private func milliseconds(_ value: TimeInterval) -> Int {
        Int(value * 1000)
    }

    private func participantPresencePayload(
        from members: [MultiplayerRoomMemberShellState]
    ) -> [String: Any] {
        var presenceMap: [String: Any] = [:]
        for member in members {
            presenceMap[member.playerId] = [
                "isConnected": member.presence == .connected,
                "isReady": member.ready,
                "source": "roomSnapshot"
            ]
        }
        return presenceMap
    }

    private func liveProjectionGameManager(for gameId: String) -> GameManager {
        if projectionGameId != gameId || projectionGameManager == nil {
            projectionGameId = gameId
            projectionGameManager = GameManager()
        }
        guard let projectionGameManager else {
            let fallback = GameManager()
            self.projectionGameManager = fallback
            self.projectionGameId = gameId
            return fallback
        }
        return projectionGameManager
    }

    private func nextConnectionId() -> String {
        context.connectionCounter += 1
        return "conn_\(context.connectionCounter)"
    }

    private func short(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return String(value.prefix(8))
    }
}

private struct MultiplayerLocalDebugContext {
    let localPlayerId = "debug_host"
    let localDeviceId = "debug-ios-host"
    let guestPlayerId = "debug_guest"
    let guestDeviceId = "debug-ios-guest"
    var roomId: String?
    var localSessionId: String?
    var guestSessionId: String?
    var localResumeToken: String?
    var guestResumeToken: String?
    var localConnectionId: String?
    var localGraceExpiresAt: Date?
    var debugGameId: String?
    var debugTurnId: String?
    var debugTurnDeadlineAt: Date?
    var connectionCounter: Int = 0

    mutating func update(from snapshot: RoomCoordinatorSnapshot, helloAck: LocalRoomDebugHelloAck?) {
        roomId = snapshot.room.roomId
        localSessionId = snapshot.sessions.first(where: { $0.playerId == localPlayerId })?.sessionId
        guestSessionId = snapshot.sessions.first(where: { $0.playerId == guestPlayerId })?.sessionId
        localResumeToken = helloAck?.resumeToken ?? snapshot.sessions.first(where: { $0.playerId == localPlayerId })?.resumeToken
        guestResumeToken = snapshot.sessions.first(where: { $0.playerId == guestPlayerId })?.resumeToken
        localConnectionId = helloAck?.connectionId ?? snapshot.sessions.first(where: { $0.playerId == localPlayerId })?.connectionId
        localGraceExpiresAt = snapshot.sessions.first(where: { $0.playerId == localPlayerId })?.graceExpiresAt
        if let activeGameId = snapshot.room.activeGameId {
            debugGameId = activeGameId
        } else if snapshot.room.roomState != .starting && snapshot.room.roomState != .inGame {
            debugGameId = nil
            debugTurnId = nil
            debugTurnDeadlineAt = nil
        }
    }

    mutating func clearLocalMembership() {
        roomId = nil
        localSessionId = nil
        guestSessionId = nil
        localResumeToken = nil
        guestResumeToken = nil
        localConnectionId = nil
        localGraceExpiresAt = nil
        debugGameId = nil
        debugTurnId = nil
        debugTurnDeadlineAt = nil
    }

    func persistedResume(lastKnownGameId: String?) -> MultiplayerPersistedSessionSummary? {
        guard let roomId, let localSessionId, let localResumeToken else { return nil }
        _ = localResumeToken
        return MultiplayerPersistedSessionSummary(
            roomId: roomId,
            sessionId: localSessionId,
            playerId: localPlayerId,
            deviceId: localDeviceId,
            resumeToken: localResumeToken,
            lastKnownGameId: lastKnownGameId,
            graceExpiresAt: localGraceExpiresAt
        )
    }
}
#endif

enum MultiplayerHelloResumeMode: String {
    case freshAttach
    case resumed
    case resumeRejected
}

struct MultiplayerEntryErrorPayload {
    let code: String
    let messageKey: String
    let detail: String?
}

struct MultiplayerHelloAckShellPayload {
    let roomId: String?
    let resumeMode: MultiplayerHelloResumeMode
    let heartbeatIntervalMs: Int
    let disconnectTimeoutMs: Int
    let reconnectGraceMs: Int
    let resultRetentionMs: Int
    let resumeToken: String?
}

enum MultiplayerRoomMemberPresencePayload: String {
    case connected
    case disconnectedGrace
    case resuming
    case expired
    case replaced
}

struct MultiplayerRoomMemberPayload {
    let playerId: String
    let seat: Int
    let role: String
    let ready: Bool
    let presence: MultiplayerRoomMemberPresencePayload
    let isLocalPlayer: Bool
}

struct MultiplayerRoomDeadlinesPayload {
    let joinExpiresAt: String?
    let readyExpiresAt: String?
}

struct MultiplayerRoomSnapshotPayload {
    let roomId: String
    let roomType: MultiplayerRoomType
    let joinPolicy: MultiplayerJoinPolicy
    let roomState: MultiplayerRoomLifecycle
    let hostPlayerId: String
    let members: [MultiplayerRoomMemberPayload]
    let activeGameId: String?
    let deadlines: MultiplayerRoomDeadlinesPayload
    let lastRoomSequence: Int
    let inviteCode: String?
    let persistedResume: MultiplayerPersistedSessionSummary?
}

struct MultiplayerReconnectContextPayload {
    let roomId: String
    let heartbeatIntervalMs: Int
    let disconnectTimeoutMs: Int
    let reconnectGraceMs: Int
    let graceExpiresAt: String?
    let lastRoomSequence: Int
    let lastAppliedStateVersion: Int?
    let lastSnapshotId: String?
}

struct MultiplayerShellMappedPreview {
    let entry: MultiplayerEntryShellState
    let room: MultiplayerRoomShellState
    let live: MultiplayerLiveShellState
    let reconnect: MultiplayerReconnectOverlayState
    let result: MultiplayerResultShellState

    static let demo: MultiplayerShellMappedPreview = {
        let fixture = MultiplayerShellContractFixture.demo
        let entryState = MultiplayerShellMapper.entryState(
            persistedResume: fixture.persistedResume,
            helloAck: fixture.helloAck,
            lastError: nil
        )
        let roomState = MultiplayerShellMapper.roomState(from: fixture.roomSnapshot)
        let baseLiveState = MultiplayerShellMapper.liveState(
            from: fixture.gameSnapshot,
            serverTime: fixture.gameSnapshotServerTime
        )
        let liveWithTurn = MultiplayerShellMapper.applying(
            turnChanged: fixture.turnChanged,
            serverTime: fixture.turnChangedServerTime,
            to: baseLiveState
        )
        let liveState = MultiplayerShellMapper.applying(
            actionRejected: fixture.actionRejected,
            to: liveWithTurn
        )
        let resultState = MultiplayerShellMapper.resultState(
            roundEnded: fixture.roundEnded,
            matchEnded: fixture.matchEnded,
            localPlayerId: fixture.localPlayerId,
            playerNamesById: fixture.playerNamesById
        )
        let reconnectState = MultiplayerShellMapper.reconnectOverlay(
            phase: .resyncing,
            context: fixture.reconnectContext
        )

        return MultiplayerShellMappedPreview(
            entry: entryState,
            room: roomState,
            live: liveState,
            reconnect: reconnectState,
            result: resultState
        )
    }()
}

enum MultiplayerShellMapper {
    static func entryState(
        persistedResume: MultiplayerPersistedSessionSummary?,
        pendingAction: MultiplayerEntryAction? = nil,
        helloAck: MultiplayerHelloAckShellPayload? = nil,
        lastError: MultiplayerEntryErrorPayload? = nil
    ) -> MultiplayerEntryShellState {
        MultiplayerEntryShellState(
            pendingAction: pendingAction,
            persistedResume: persistedResume,
            lastError: entryBanner(helloAck: helloAck, lastError: lastError)
        )
    }

    static func roomState(from payload: MultiplayerRoomSnapshotPayload) -> MultiplayerRoomShellState {
        let members = payload.members
            .sorted(by: { $0.seat < $1.seat })
            .map { member in
                MultiplayerRoomMemberShellState(
                    playerId: member.playerId,
                    seat: member.seat,
                    role: member.role,
                    ready: member.ready,
                    presence: presence(from: member.presence),
                    isLocalPlayer: member.isLocalPlayer
                )
            }

        return MultiplayerRoomShellState(
            roomId: payload.roomId,
            roomType: payload.roomType,
            joinPolicy: payload.joinPolicy,
            roomState: payload.roomState,
            hostPlayerId: payload.hostPlayerId,
            members: members,
            activeGameId: payload.activeGameId,
            deadlines: MultiplayerRoomDeadlinesState(
                joinExpiresAt: parseDate(payload.deadlines.joinExpiresAt),
                readyExpiresAt: parseDate(payload.deadlines.readyExpiresAt)
            ),
            lastRoomSequence: payload.lastRoomSequence,
            inviteCode: payload.inviteCode,
            banner: roomBanner(for: payload.roomState, members: members, inviteCode: payload.inviteCode)
        )
    }

    static func liveState(from snapshot: MultiplayerSnapshot, serverTime: String?) -> MultiplayerLiveShellState {
        let localPlayer = localPlayer(in: snapshot.state)
        let opponentPlayer = opponentPlayer(in: snapshot.state, localPlayerId: localPlayer?.playerId)
        let localPlayerId = localPlayer?.playerId ?? snapshot.state.viewerPlayerId

        return MultiplayerLiveShellState(
            roomId: snapshot.state.roomId ?? "room_pending",
            gameId: snapshot.state.gameId,
            localPlayerId: localPlayerId ?? "player_local_pending",
            stateVersion: snapshot.state.stateVersion,
            currentPlayerId: snapshot.state.currentPlayerId ?? localPlayerId ?? "player_turn_pending",
            phase: gamePhase(from: snapshot.state.phase),
            turnId: snapshot.state.turnId,
            turnDeadlineAt: parseDate(snapshot.state.timers.turnDeadlineAt),
            serverTime: parseDate(serverTime) ?? Date.now,
            opponentPlayerId: opponentPlayer?.playerId ?? "player_opponent_pending",
            opponentHandCount: opponentPlayer?.handCount ?? 0,
            localHandCount: localPlayer?.handCount ?? 0,
            localPlayableCardIds: localPlayer?.hand?.map(\.cardId) ?? [],
            pendingChoice: snapshot.state.pendingChoice.map { choiceState(from: $0, localPlayerId: localPlayerId) },
            lastReject: nil,
            connectionBanner: liveBanner(snapshot: snapshot, localPlayer: localPlayer, opponentPlayer: opponentPlayer)
        )
    }

    static func applying(
        turnChanged: MultiplayerTurnChangedPayload,
        serverTime: String?,
        to state: MultiplayerLiveShellState
    ) -> MultiplayerLiveShellState {
        MultiplayerLiveShellState(
            roomId: state.roomId,
            gameId: state.gameId,
            localPlayerId: state.localPlayerId,
            stateVersion: state.stateVersion,
            currentPlayerId: turnChanged.currentPlayerId,
            phase: state.phase == .choicePending ? .choicePending : .inTurn,
            turnId: turnChanged.turnId,
            turnDeadlineAt: parseDate(turnChanged.turnDeadlineAt),
            serverTime: parseDate(serverTime) ?? state.serverTime,
            opponentPlayerId: state.opponentPlayerId,
            opponentHandCount: state.opponentHandCount,
            localHandCount: state.localHandCount,
            localPlayableCardIds: state.localPlayableCardIds,
            pendingChoice: state.pendingChoice,
            lastReject: state.lastReject,
            connectionBanner: state.connectionBanner
        )
    }

    static func applying(actionRejected: MultiplayerActionRejectedPayload, to state: MultiplayerLiveShellState) -> MultiplayerLiveShellState {
        MultiplayerLiveShellState(
            roomId: state.roomId,
            gameId: state.gameId,
            localPlayerId: state.localPlayerId,
            stateVersion: state.stateVersion,
            currentPlayerId: state.currentPlayerId,
            phase: state.phase,
            turnId: state.turnId,
            turnDeadlineAt: state.turnDeadlineAt,
            serverTime: state.serverTime,
            opponentPlayerId: state.opponentPlayerId,
            opponentHandCount: state.opponentHandCount,
            localHandCount: state.localHandCount,
            localPlayableCardIds: state.localPlayableCardIds,
            pendingChoice: state.pendingChoice,
            lastReject: rejectState(from: actionRejected.rejectReason),
            connectionBanner: state.connectionBanner
        )
    }

    static func reconnectOverlay(
        phase: MultiplayerReconnectPhase,
        context: MultiplayerReconnectContextPayload
    ) -> MultiplayerReconnectOverlayState {
        MultiplayerReconnectOverlayState(
            phase: phase,
            roomId: context.roomId,
            heartbeatIntervalMs: context.heartbeatIntervalMs,
            disconnectTimeoutMs: context.disconnectTimeoutMs,
            reconnectGraceMs: context.reconnectGraceMs,
            graceExpiresAt: parseDate(context.graceExpiresAt),
            lastRoomSequence: context.lastRoomSequence,
            lastAppliedStateVersion: context.lastAppliedStateVersion,
            lastSnapshotId: context.lastSnapshotId
        )
    }

    static func resultState(
        roundEnded: MultiplayerRoundEndedPayload?,
        matchEnded: MultiplayerMatchEndedPayload,
        localPlayerId: String,
        playerNamesById: [String: String]
    ) -> MultiplayerResultShellState {
        let settlement = matchEnded.settlementSummary ?? roundEnded?.summary.settlementSummary

        return MultiplayerResultShellState(
            roundIndex: roundEnded?.summary.roundIndex ?? roundEnded?.roundIndex ?? 1,
            localPlayerId: localPlayerId,
            winnerPlayerId: matchEnded.winnerPlayerId,
            loserPlayerId: matchEnded.loserPlayerId,
            finalScores: matchEnded.finalScores.map { row in
                MultiplayerResultScoreRowState(
                    playerId: row.playerId,
                    displayName: playerNamesById[row.playerId] ?? fallbackName(for: row.playerId),
                    score: row.score,
                    goCount: row.goCount,
                    money: row.money,
                    isLocalPlayer: row.playerId == localPlayerId
                )
            },
            settlementSummary: settlement.map(settlementState),
            endReasonCode: matchEnded.endReason.rawValue,
            endReasonMessageKey: matchEnded.endReasonMessageKey,
            forfeitingPlayerId: matchEnded.forfeitingPlayerId,
            isDraw: matchEnded.isDraw,
            leavePolicy: .leaveAvailable,
            integrationNotes: [
                "Result display names still fall back to snapshot player names when room member names are unavailable.",
                "endReasonMessageKey is available, but UI localization wiring still has to land in the message catalog.",
                "Leave completion now waits for leaveRoom acknowledgement or roomClosed from the room lifecycle layer."
            ]
        )
    }

    private static func entryBanner(
        helloAck: MultiplayerHelloAckShellPayload?,
        lastError: MultiplayerEntryErrorPayload?
    ) -> MultiplayerBannerState? {
        if let lastError {
            return MultiplayerBannerState(
                style: .warning,
                title: lastError.code,
                detail: [lastError.messageKey, lastError.detail]
                    .compactMap { $0 }
                    .joined(separator: " • "),
                messageKey: lastError.messageKey
            )
        }

        guard let helloAck else { return nil }

        switch helloAck.resumeMode {
        case .freshAttach:
            return MultiplayerBannerState(
                style: .info,
                title: "Fresh Attach",
                detail: "The next route can move only after roomSnapshot is applied."
            )
        case .resumed:
            return MultiplayerBannerState(
                style: .success,
                title: "Resume Accepted",
                detail: "The session passed helloAck and can wait for roomSnapshot plus stateSnapshot."
            )
        case .resumeRejected:
            return MultiplayerBannerState(
                style: .warning,
                title: "Resume Rejected",
                detail: "The persisted session exists locally, but the server refused resume."
            )
        }
    }

    private static func roomBanner(
        for lifecycle: MultiplayerRoomLifecycle,
        members: [MultiplayerRoomMemberShellState],
        inviteCode: String?
    ) -> MultiplayerBannerState? {
        if members.contains(where: { $0.presence == .disconnectedGrace || $0.presence == .resuming }) {
            return MultiplayerBannerState(
                style: .warning,
                title: "Member Reconnecting",
                detail: "Room membership is intact, but at least one seat is still inside reconnect recovery."
            )
        }

        switch lifecycle {
        case .waitingForPlayers:
            let detail = inviteCode == nil
                ? "The room exists, but a second seat has not joined yet."
                : "Share code \(inviteCode ?? "") is ready. A second seat has not joined yet."
            return MultiplayerBannerState(style: .info, title: "Waiting For Players", detail: detail)
        case .waitingForReady:
            return MultiplayerBannerState(
                style: .warning,
                title: "Waiting For Ready",
                detail: "Both players are present, but the ready handshake is not complete."
            )
        case .starting:
            return MultiplayerBannerState(
                style: .info,
                title: "Auto-Start Pending",
                detail: "The room is locked and is waiting for the fresh game projection handoff."
            )
        case .inGame:
            return MultiplayerBannerState(
                style: .success,
                title: "Room In Game",
                detail: "The room has active game ownership and is waiting for live projection."
            )
        case .ended:
            return MultiplayerBannerState(
                style: .warning,
                title: "Room Ended",
                detail: "The match ended and the room is inside retention."
            )
        case .closed:
            return MultiplayerBannerState(
                style: .warning,
                title: "Room Closed",
                detail: "The room is terminal and should route back to entry."
            )
        }
    }

    private static func liveBanner(
        snapshot: MultiplayerSnapshot,
        localPlayer: MultiplayerPlayerProjection?,
        opponentPlayer: MultiplayerPlayerProjection?
    ) -> MultiplayerBannerState? {
        if snapshot.reason == .resume || snapshot.reason == .resync {
            return MultiplayerBannerState(
                style: .info,
                title: "Snapshot Restored",
                detail: "Live input stays locked until the fresh \(snapshot.reason.rawValue) snapshot finishes applying."
            )
        }

        if let opponentPlayer, opponentPlayer.isConnected == false {
            return MultiplayerBannerState(
                style: .warning,
                title: "Opponent Reconnecting",
                detail: "\(opponentPlayer.name) is disconnected. The local player should keep seeing the last authoritative frame."
            )
        }

        if let localPlayer, localPlayer.isConnected == false {
            return MultiplayerBannerState(
                style: .warning,
                title: "Local Session Interrupted",
                detail: "Reconnect overlay should take over before local input can resume."
            )
        }

        return nil
    }

    private static func choiceState(
        from choice: MultiplayerChoice,
        localPlayerId: String?
    ) -> MultiplayerChoiceShellState {
        let isRedactedForViewer =
            choice.choiceKind == .shake &&
            choice.visibility == .actorOnly &&
            choice.actorPlayerId != localPlayerId

        return MultiplayerChoiceShellState(
            choiceId: choice.choiceId,
            choiceKind: choiceKind(from: choice.choiceKind),
            actorPlayerId: choice.actorPlayerId,
            promptKey: choice.promptKey,
            deadlineAt: parseDate(choice.deadlineAt),
            isRedactedForViewer: isRedactedForViewer,
            redactionMessageKey: isRedactedForViewer ? "match.choice.shake.actor_only_waiting" : nil,
            options: isRedactedForViewer ? [] : choice.options.map { option in
                MultiplayerChoiceOptionShellState(
                    optionCode: option.optionCode,
                    labelKey: option.labelKey,
                    cardIds: option.cards.map(\.cardId),
                    scoreDeltaPreviewSelf: option.scoreDeltaPreview?.selfDelta ?? 0,
                    scoreDeltaPreviewOpponent: option.scoreDeltaPreview?.opponentDelta ?? 0
                )
            }
        )
    }

    private static func rejectState(from reason: MultiplayerRejectReason) -> MultiplayerRejectShellState {
        let detailRows = reason.details?
            .sorted(by: { $0.key < $1.key })
            .map { MultiplayerRejectDetailRow(key: $0.key, value: stringValue($0.value.value)) } ?? []

        return MultiplayerRejectShellState(
            code: reason.code.rawValue,
            messageKey: reason.messageKey,
            detailRows: detailRows
        )
    }

    private static func settlementState(from settlement: MultiplayerSettlementSummary) -> MultiplayerResultSettlementState {
        MultiplayerResultSettlementState(
            finalScore: settlement.finalScore,
            scoreFormula: settlement.scoreFormula,
            flags: [
                MultiplayerResultSettlementFlagState(label: "Draw", isActive: settlement.isDraw),
                MultiplayerResultSettlementFlagState(label: "Gwangbak", isActive: settlement.isGwangbak),
                MultiplayerResultSettlementFlagState(label: "Pibak", isActive: settlement.isPibak),
                MultiplayerResultSettlementFlagState(label: "Gobak", isActive: settlement.isGobak),
                MultiplayerResultSettlementFlagState(label: "Mungbak", isActive: settlement.isMungbak),
                MultiplayerResultSettlementFlagState(label: "Jabak", isActive: settlement.isJabak),
                MultiplayerResultSettlementFlagState(label: "Yeokbak", isActive: settlement.isYeokbak)
            ]
        )
    }

    private static func localPlayer(in snapshot: MultiplayerMatchSnapshot) -> MultiplayerPlayerProjection? {
        if let viewerPlayerId = snapshot.viewerPlayerId,
           let viewer = snapshot.players.first(where: { $0.playerId == viewerPlayerId }) {
            return viewer
        }
        return snapshot.players.first(where: \.isViewer) ?? snapshot.players.first
    }

    private static func opponentPlayer(
        in snapshot: MultiplayerMatchSnapshot,
        localPlayerId: String?
    ) -> MultiplayerPlayerProjection? {
        snapshot.players.first(where: { $0.playerId != localPlayerId })
    }

    private static func gamePhase(from phase: MultiplayerPhase) -> MultiplayerGamePhase {
        switch phase {
        case .waiting:
            return .waiting
        case .dealing:
            return .dealing
        case .inTurn:
            return .inTurn
        case .choicePending:
            return .choicePending
        case .roundEnded:
            return .roundEnded
        case .matchEnded:
            return .matchEnded
        case .paused:
            return .paused
        }
    }

    private static func choiceKind(from kind: MultiplayerContractChoiceKind) -> MultiplayerChoiceKind {
        switch kind {
        case .capture:
            return .capture
        case .shake:
            return .shake
        case .goStop:
            return .goStop
        case .chrysanthemumRole:
            return .chrysanthemumRole
        }
    }

    private static func presence(from presence: MultiplayerRoomMemberPresencePayload) -> MultiplayerMemberPresence {
        switch presence {
        case .connected:
            return .connected
        case .disconnectedGrace:
            return .disconnectedGrace
        case .resuming:
            return .resuming
        case .expired:
            return .expired
        case .replaced:
            return .replaced
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter.date(from: value) ?? relaxedDateFormatter.date(from: value)
    }

    static func parseTransportDate(_ value: String) -> Date? {
        parseDate(value)
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as Int:
            return String(number)
        case let number as Double:
            return String(number)
        case let flag as Bool:
            return flag ? "true" : "false"
        case let array as [Any]:
            return array.map(stringValue).joined(separator: ", ")
        case let dictionary as [String: Any]:
            return dictionary
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(stringValue($0.value))" }
                .joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    private static func fallbackName(for playerId: String) -> String {
        "Player \(playerId.suffix(4))"
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relaxedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension MultiplayerResultShellState {
    func with(
        leavePolicy: MultiplayerResultLeavePolicy? = nil,
        integrationNotes: [String]? = nil
    ) -> MultiplayerResultShellState {
        MultiplayerResultShellState(
            roundIndex: roundIndex,
            localPlayerId: localPlayerId,
            winnerPlayerId: winnerPlayerId,
            loserPlayerId: loserPlayerId,
            finalScores: finalScores,
            settlementSummary: settlementSummary,
            endReasonCode: endReasonCode,
            endReasonMessageKey: endReasonMessageKey,
            forfeitingPlayerId: forfeitingPlayerId,
            isDraw: isDraw,
            leavePolicy: leavePolicy ?? self.leavePolicy,
            integrationNotes: integrationNotes ?? self.integrationNotes
        )
    }
}

private extension MultiplayerRoomShellState {
    func with(banner: MultiplayerBannerState?) -> MultiplayerRoomShellState {
        MultiplayerRoomShellState(
            roomId: roomId,
            roomType: roomType,
            joinPolicy: joinPolicy,
            roomState: roomState,
            hostPlayerId: hostPlayerId,
            members: members,
            activeGameId: activeGameId,
            deadlines: deadlines,
            lastRoomSequence: lastRoomSequence,
            inviteCode: inviteCode,
            banner: banner
        )
    }
}

private extension MultiplayerLiveShellState {
    func with(connectionBanner: MultiplayerBannerState?) -> MultiplayerLiveShellState {
        MultiplayerLiveShellState(
            roomId: roomId,
            gameId: gameId,
            localPlayerId: localPlayerId,
            stateVersion: stateVersion,
            currentPlayerId: currentPlayerId,
            phase: phase,
            turnId: turnId,
            turnDeadlineAt: turnDeadlineAt,
            serverTime: serverTime,
            opponentPlayerId: opponentPlayerId,
            opponentHandCount: opponentHandCount,
            localHandCount: localHandCount,
            localPlayableCardIds: localPlayableCardIds,
            pendingChoice: pendingChoice,
            lastReject: lastReject,
            connectionBanner: connectionBanner
        )
    }
}

private struct MultiplayerShellContractFixture {
    let persistedResume: MultiplayerPersistedSessionSummary
    let helloAck: MultiplayerHelloAckShellPayload
    let roomSnapshot: MultiplayerRoomSnapshotPayload
    let reconnectContext: MultiplayerReconnectContextPayload
    let gameSnapshot: MultiplayerSnapshot
    let gameSnapshotServerTime: String
    let turnChanged: MultiplayerTurnChangedPayload
    let turnChangedServerTime: String
    let actionRejected: MultiplayerActionRejectedPayload
    let roundEnded: MultiplayerRoundEndedPayload
    let matchEnded: MultiplayerMatchEndedPayload
    let localPlayerId: String
    let playerNamesById: [String: String]

    static let demo: MultiplayerShellContractFixture = {
        let localPlayerId = "player_a"
        let opponentPlayerId = "player_b"
        let roomId = "room_001"
        let gameId = "game_001"
        let readyDeadline = isoString(after: 42)
        let reconnectDeadline = isoString(after: 24)
        let gameSnapshotServerTime = isoString(after: 0)
        let turnChangedServerTime = isoString(after: 2)
        let turnDeadline = isoString(after: 14)
        let choiceDeadline = isoString(after: 12)

        let choice = MultiplayerChoice(
            choiceId: "choice_0007",
            choiceKind: .capture,
            actorPlayerId: localPlayerId,
            promptKey: "match.choice.capture",
            requestedAt: gameSnapshotServerTime,
            deadlineAt: choiceDeadline,
            expiresAtStateVersion: 13,
            options: [
                MultiplayerChoiceOption(
                    optionCode: "capture_pair_left",
                    labelKey: "match.choice.capture.take_pair",
                    cards: [
                        MultiplayerChoiceCard(
                            cardId: "card_03_ribbon_red_poem",
                            zone: "hand",
                            month: 3,
                            kind: "ribbon",
                            imageIndex: 9,
                            selectedRole: nil
                        ),
                        MultiplayerChoiceCard(
                            cardId: "card_03_junk_a",
                            zone: "table",
                            month: 3,
                            kind: "junk",
                            imageIndex: 11,
                            selectedRole: nil
                        )
                    ],
                    effectTags: ["capture"],
                    scoreDeltaPreview: MultiplayerScoreDeltaPreview(selfDelta: 0, opponentDelta: 0),
                    metadata: nil
                ),
                MultiplayerChoiceOption(
                    optionCode: "capture_pair_right",
                    labelKey: "match.choice.capture.take_pair",
                    cards: [
                        MultiplayerChoiceCard(
                            cardId: "card_03_ribbon_red_poem",
                            zone: "hand",
                            month: 3,
                            kind: "ribbon",
                            imageIndex: 9,
                            selectedRole: nil
                        ),
                        MultiplayerChoiceCard(
                            cardId: "card_03_junk_b",
                            zone: "table",
                            month: 3,
                            kind: "junk",
                            imageIndex: 10,
                            selectedRole: nil
                        )
                    ],
                    effectTags: ["capture"],
                    scoreDeltaPreview: MultiplayerScoreDeltaPreview(selfDelta: 0, opponentDelta: 0),
                    metadata: nil
                )
            ]
        )

        let gameSnapshot = MultiplayerSnapshot(
            snapshotId: "snap_000013_player_a",
            reason: .resume,
            scope: .player,
            snapshotStateVersion: 13,
            lastIncludedEventId: "evt_000113",
            state: MultiplayerMatchSnapshot(
                traceId: "trace_001",
                roomId: roomId,
                gameId: gameId,
                viewerPlayerId: localPlayerId,
                engineVersion: "phase0",
                ruleConfigVersion: "default",
                stateVersion: 13,
                lastEventId: "evt_000113",
                phase: .choicePending,
                turnId: "turn_0007",
                currentPlayerId: localPlayerId,
                dealerPlayerId: localPlayerId,
                players: [
                    MultiplayerPlayerProjection(
                        playerId: localPlayerId,
                        seatIndex: 0,
                        name: "You",
                        hand: nil,
                        handCount: 6,
                        captured: MultiplayerCapturedCards(bright: [], animal: [], ribbon: [], junk: []),
                        score: 5,
                        money: 12000,
                        goCount: 1,
                        shakeCount: 0,
                        isConnected: true,
                        isReady: true,
                        isViewer: true
                    ),
                    MultiplayerPlayerProjection(
                        playerId: opponentPlayerId,
                        seatIndex: 1,
                        name: "Guest",
                        hand: nil,
                        handCount: 7,
                        captured: MultiplayerCapturedCards(bright: [], animal: [], ribbon: [], junk: []),
                        score: 2,
                        money: 8000,
                        goCount: 0,
                        shakeCount: 0,
                        isConnected: false,
                        isReady: true,
                        isViewer: false
                    )
                ],
                table: MultiplayerTableSnapshot(cards: [], monthBuckets: [:]),
                deck: MultiplayerDeckSnapshot(remainingCount: 18),
                pendingChoice: choice,
                scoreboard: MultiplayerScoreboard(
                    roundIndex: 1,
                    playerScores: [
                        MultiplayerPlayerScore(playerId: localPlayerId, score: 5, goCount: 1, money: 12000),
                        MultiplayerPlayerScore(playerId: opponentPlayerId, score: 2, goCount: 0, money: 8000)
                    ],
                    winnerPlayerId: localPlayerId
                ),
                timers: MultiplayerTimers(turnDeadlineAt: turnDeadline, choiceDeadlineAt: choiceDeadline),
                resume: MultiplayerResumeState(isResumable: true, graceDeadlineAt: reconnectDeadline)
            )
        )

        return MultiplayerShellContractFixture(
            persistedResume: MultiplayerPersistedSessionSummary(
                roomId: roomId,
                sessionId: "sess_001",
                playerId: localPlayerId,
                deviceId: "fixture-ios-host",
                resumeToken: "resume_tok_fixture",
                lastKnownGameId: gameId,
                graceExpiresAt: date(after: 24)
            ),
            helloAck: MultiplayerHelloAckShellPayload(
                roomId: roomId,
                resumeMode: .resumed,
                heartbeatIntervalMs: 5000,
                disconnectTimeoutMs: 15000,
                reconnectGraceMs: 30000,
                resultRetentionMs: 60000,
                resumeToken: "resume_tok_fixture"
            ),
            roomSnapshot: MultiplayerRoomSnapshotPayload(
                roomId: roomId,
                roomType: .invite,
                joinPolicy: .inviteCode,
                roomState: .starting,
                hostPlayerId: localPlayerId,
                members: [
                    MultiplayerRoomMemberPayload(
                        playerId: localPlayerId,
                        seat: 0,
                        role: "host",
                        ready: true,
                        presence: .connected,
                        isLocalPlayer: true
                    ),
                    MultiplayerRoomMemberPayload(
                        playerId: opponentPlayerId,
                        seat: 1,
                        role: "guest",
                        ready: true,
                        presence: .resuming,
                        isLocalPlayer: false
                    )
                ],
                activeGameId: gameId,
                deadlines: MultiplayerRoomDeadlinesPayload(
                    joinExpiresAt: isoString(after: 210),
                    readyExpiresAt: readyDeadline
                ),
                lastRoomSequence: 21,
                inviteCode: "GWANG-32",
                persistedResume: MultiplayerPersistedSessionSummary(
                    roomId: roomId,
                    sessionId: "sess_001",
                    playerId: localPlayerId,
                    deviceId: "fixture-ios-host",
                    resumeToken: "resume_tok_fixture",
                    lastKnownGameId: gameId,
                    graceExpiresAt: date(after: 24)
                )
            ),
            reconnectContext: MultiplayerReconnectContextPayload(
                roomId: roomId,
                heartbeatIntervalMs: 5000,
                disconnectTimeoutMs: 15000,
                reconnectGraceMs: 30000,
                graceExpiresAt: reconnectDeadline,
                lastRoomSequence: 21,
                lastAppliedStateVersion: 13,
                lastSnapshotId: "snap_000013_player_a"
            ),
            gameSnapshot: gameSnapshot,
            gameSnapshotServerTime: gameSnapshotServerTime,
            turnChanged: MultiplayerTurnChangedPayload(
                turnId: "turn_0008",
                currentPlayerId: localPlayerId,
                turnDeadlineAt: isoString(after: 11)
            ),
            turnChangedServerTime: turnChangedServerTime,
            actionRejected: MultiplayerActionRejectedPayload(
                requestId: "req_0008",
                actionId: "act_0008",
                playerId: localPlayerId,
                commandName: .playCard,
                rejectReason: MultiplayerRejectReason(
                    code: .staleStateVersion,
                    retryable: true,
                    messageKey: "match.reject.stale_state_version",
                    details: [
                        "latestStateVersion": AnyCodable(13),
                        "turnId": AnyCodable("turn_0008")
                    ]
                )
            ),
            roundEnded: MultiplayerRoundEndedPayload(
                roundIndex: 1,
                summary: MultiplayerRoundSummary(
                    roundIndex: 1,
                    winnerPlayerId: localPlayerId,
                    loserPlayerId: opponentPlayerId,
                    finalScores: [
                        MultiplayerPlayerScore(playerId: localPlayerId, score: 5, goCount: 1, money: 12000),
                        MultiplayerPlayerScore(playerId: opponentPlayerId, score: 2, goCount: 0, money: 8000)
                    ],
                    settlementSummary: MultiplayerSettlementSummary(
                        finalScore: 5,
                        scoreFormula: "5 points + pi-bak",
                        isDraw: false,
                        isGwangbak: false,
                        isPibak: true,
                        isGobak: false,
                        isMungbak: false,
                        isJabak: false,
                        isYeokbak: false
                    ),
                    endReason: .disconnectTimeout,
                    endReasonMessageKey: "match.end.disconnect_timeout",
                    forfeitingPlayerId: opponentPlayerId,
                    isDraw: false
                )
            ),
            matchEnded: MultiplayerMatchEndedPayload(
                winnerPlayerId: localPlayerId,
                loserPlayerId: opponentPlayerId,
                finalScores: [
                    MultiplayerPlayerScore(playerId: localPlayerId, score: 5, goCount: 1, money: 12000),
                    MultiplayerPlayerScore(playerId: opponentPlayerId, score: 2, goCount: 0, money: 8000)
                ],
                settlementSummary: MultiplayerSettlementSummary(
                    finalScore: 5,
                    scoreFormula: "5 points + pi-bak",
                    isDraw: false,
                    isGwangbak: false,
                    isPibak: true,
                    isGobak: false,
                    isMungbak: false,
                    isJabak: false,
                    isYeokbak: false
                ),
                endReason: .disconnectTimeout,
                endReasonMessageKey: "match.end.disconnect_timeout",
                forfeitingPlayerId: opponentPlayerId,
                isDraw: false
            ),
            localPlayerId: localPlayerId,
            playerNamesById: [
                localPlayerId: "You",
                opponentPlayerId: "Guest"
            ]
        )
    }()

    private static func isoString(after secondsFromNow: TimeInterval) -> String {
        fixtureDateFormatter.string(from: Date.now.addingTimeInterval(secondsFromNow))
    }

    private static func date(after secondsFromNow: TimeInterval) -> Date {
        Date.now.addingTimeInterval(secondsFromNow)
    }

    private static let fixtureDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
