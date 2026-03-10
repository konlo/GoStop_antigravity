import Foundation

private struct RoomHelloCursor: Codable {
    var roomSequence: Int?
    var gameEventId: String?
    var stateVersion: Int?
}

private struct RoomHelloCLIRequest: Codable {
    var roomId: String
    var sessionId: String
    var playerId: String
    var deviceId: String
    var connectionId: String?
    var resumeToken: String
    var lastSeen: RoomHelloCursor?
}

private struct RoomSnapshotCLIRequest: Codable {
    var roomId: String
}

private struct RoomRecordMatchEndedCLIRequest: Codable {
    var roomId: String
    var roundIndex: Int?
    var quitReason: String?
    var forfeitingPlayerId: String?
    var summaryStateVersion: Int?
    var lastEventId: String?
}

private struct RoomProjectionPreviewCLIRequest: Codable {
    var roomId: String
    var viewerPlayerId: String
    var gameId: String?
    var stateVersion: Int?
    var lastEventId: String?
    var snapshotReason: String?
    var scope: String?
}

private struct RoomReapExpiredCLIRequest: Codable {
    var asOf: Date
}

private struct RoomSetMP008HookCLIRequest: Codable {
    var targetSessionId: String
    var overriddenExpectedStateVersion: Int
}

private struct RoomTransportConnectCLIRequest: Codable {
    var clientId: String
    var roomId: String
    var sessionId: String
    var playerId: String
    var deviceId: String
    var resumeToken: String
}

private struct RoomTransportSendCLIRequest: Codable {
    var clientId: String
    var action: String
    var connectionId: String?
    var ready: Bool?
    var gameId: String?
    var roundIndex: Int?
    var quitReason: String?
    var forfeitingPlayerId: String?
    var summaryStateVersion: Int?
    var lastEventId: String?
    var lastSeen: RoomHelloCursor?
}

private struct RoomTransportReceiveCLIRequest: Codable {
    var clientId: String
}

private struct RoomTransportClientState {
    var clientId: String
    var roomId: String
    var sessionId: String
    var playerId: String
    var deviceId: String
    var resumeToken: String
    var connectionId: String?
}

struct RoomAuthorityRelay {
    var fetchProjectionPreview: (RoomProjectionPreviewRequest) -> [String: Any]
    var fetchGameStartedBootstrap: (RoomGameStartedBootstrapRequest) -> [String: Any]
    var fetchTerminalSummary: (RoomTerminalSummaryRelayRequest) -> [String: Any]
}

private enum RoomCLIAdapterError: Error {
    case authorityRelayUnavailable
    case transportClientNotFound(String)
    case unsupportedTransportAction(String)
}

final class RoomCoordinatorCLIAdapter {
    private let coordinator: RoomLifecycleCoordinating
    private let configuration: RoomCoordinatorConfiguration
    private let authorityRelay: RoomAuthorityRelay?
    private let decoder: JSONDecoder
    private let iso8601Formatter: ISO8601DateFormatter
    private var deterministicFaultHook: RoomDeterministicFaultHook?
    private var transportClients: [String: RoomTransportClientState] = [:]
    private var transportMailboxes: [String: [[String: Any]]] = [:]

    init(
        configuration: RoomCoordinatorConfiguration = .phase0,
        coordinator: RoomLifecycleCoordinating? = nil,
        authorityRelay: RoomAuthorityRelay? = nil
    ) {
        self.configuration = configuration
        self.coordinator = coordinator ?? InMemoryRoomCoordinator(configuration: configuration)
        self.authorityRelay = authorityRelay

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.iso8601Formatter = formatter
    }

    func handle(request: CommandRequest) -> [String: Any]? {
        do {
            switch request.action {
            case "room_create":
                let payload = try decode(CreateRoomRequest.self, from: request.data)
                let mutation = try coordinator.createRoom(payload)
                return success(
                    action: request.action,
                    data: createOrJoinResponse(mutation: mutation, playerId: payload.hostPlayerId)
                )
            case "room_join":
                let payload = try decode(JoinRoomRequest.self, from: request.data)
                let mutation = try coordinator.joinRoom(payload)
                return success(
                    action: request.action,
                    data: createOrJoinResponse(mutation: mutation, playerId: payload.playerId)
                )
            case "room_set_ready":
                let payload = try decode(SetReadyRequest.self, from: request.data)
                let mutation = try coordinator.setReady(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_leave":
                let payload = try decode(LeaveRoomRequest.self, from: request.data)
                let mutation = try coordinator.leaveRoom(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_close":
                let payload = try decode(CloseRoomRequest.self, from: request.data)
                let mutation = try coordinator.closeRoom(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_disconnect":
                let payload = try decode(DisconnectMemberRequest.self, from: request.data)
                let mutation = try coordinator.disconnectMember(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_resume":
                let payload = try decode(ResumeSessionRequest.self, from: request.data)
                let mutation = try coordinator.resumeSession(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_heartbeat", "room_pong", "room_ack":
                let payload = try decode(RecordHeartbeatRequest.self, from: request.data)
                let mutation = try coordinator.recordHeartbeat(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_record_game_started":
                let payload = try decode(RecordGameStartedRequest.self, from: request.data)
                let mutation = try coordinator.recordGameStarted(payload)
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_record_game_started_and_prepare_bootstrap":
                let payload = try decode(RecordGameStartedRequest.self, from: request.data)
                return try handleRecordGameStartedAndPrepareBootstrap(payload, action: request.action)
            case "room_projection_preview":
                let payload = try decode(RoomProjectionPreviewCLIRequest.self, from: request.data)
                return try handleProjectionPreview(payload, action: request.action)
            case "room_record_match_ended":
                let payload = try decode(RoomRecordMatchEndedCLIRequest.self, from: request.data)
                let mutation = try coordinator.recordMatchEnded(
                    RecordMatchEndedRequest(
                        roomId: payload.roomId,
                        roundIndex: payload.roundIndex,
                        quitReason: payload.quitReason,
                        forfeitingPlayerId: payload.forfeitingPlayerId,
                        summaryStateVersion: payload.summaryStateVersion,
                        lastEventId: payload.lastEventId,
                        resultRetentionAt: nil
                    )
                )
                return success(action: request.action, data: mutationResponse(mutation))
            case "room_record_match_ended_and_fetch_terminal_summary":
                let payload = try decode(RoomRecordMatchEndedCLIRequest.self, from: request.data)
                return try handleRecordMatchEndedAndFetchTerminalSummary(payload, action: request.action)
            case "room_set_mp008_hook":
                let payload = try decode(RoomSetMP008HookCLIRequest.self, from: request.data)
                deterministicFaultHook = RoomDeterministicFaultHook(
                    kind: .staleExpectedStateVersionOverride,
                    targetSessionId: payload.targetSessionId,
                    overriddenExpectedStateVersion: payload.overriddenExpectedStateVersion
                )
                return success(
                    action: request.action,
                    data: [
                        "hook": serializeDeterministicFaultHook(deterministicFaultHook),
                    ]
                )
            case "room_get_mp008_hook":
                return success(
                    action: request.action,
                    data: [
                        "hook": serializeDeterministicFaultHook(deterministicFaultHook),
                    ]
                )
            case "room_clear_mp008_hook":
                deterministicFaultHook = nil
                return success(
                    action: request.action,
                    data: [
                        "hook": serializeDeterministicFaultHook(deterministicFaultHook),
                    ]
                )
            case "room_reap_expired":
                let payload = try decode(RoomReapExpiredCLIRequest.self, from: request.data)
                let mutations = try coordinator.reapExpiredState(asOf: payload.asOf)
                return success(
                    action: request.action,
                    data: [
                        "mutations": mutations.map(mutationResponse),
                    ]
                )
            case "room_snapshot":
                let payload = try decode(RoomSnapshotCLIRequest.self, from: request.data)
                guard let snapshot = coordinator.snapshot(for: payload.roomId) else {
                    throw RoomCoordinatorError.roomNotFound(roomId: payload.roomId)
                }
                return success(
                    action: request.action,
                    data: [
                        "snapshot": serializeSnapshot(snapshot),
                    ]
                )
            case "room_transport_connect":
                let payload = try decode(RoomTransportConnectCLIRequest.self, from: request.data)
                return success(action: request.action, data: transportConnect(payload))
            case "room_transport_send":
                let payload = try decode(RoomTransportSendCLIRequest.self, from: request.data)
                return try handleTransportSend(payload, action: request.action)
            case "room_transport_receive":
                let payload = try decode(RoomTransportReceiveCLIRequest.self, from: request.data)
                return success(action: request.action, data: transportReceive(payload))
            case "room_hello":
                let payload = try decode(RoomHelloCLIRequest.self, from: request.data)
                return try handleHello(payload, action: request.action)
            default:
                return nil
            }
        } catch let error as RoomCoordinatorError {
            return failure(action: request.action, code: errorCode(error), message: errorMessage(error))
        } catch let error as RoomCLIAdapterError {
            return failure(action: request.action, code: adapterErrorCode(error), message: adapterErrorMessage(error))
        } catch {
            return failure(action: request.action, code: "invalidPayload", message: error.localizedDescription)
        }
    }

    private func handleHello(_ payload: RoomHelloCLIRequest, action: String) throws -> [String: Any] {
        let resolution = try performRoomHello(
            coordinator: coordinator,
            roomId: payload.roomId,
            sessionId: payload.sessionId,
            playerId: payload.playerId,
            deviceId: payload.deviceId,
            connectionId: payload.connectionId,
            resumeToken: payload.resumeToken,
            lastAckedRoomSequence: payload.lastSeen?.roomSequence,
            lastAckedGameEventId: payload.lastSeen?.gameEventId,
            lastSeenStateVersion: payload.lastSeen?.stateVersion
        )
        let mutation = resolution.mutation

        let helloAck: [String: Any] = [
            "resumeMode": resolution.resumeMode.rawValue,
            "connectionId": payload.connectionId ?? NSNull(),
            "heartbeatIntervalMs": milliseconds(configuration.heartbeatInterval),
            "disconnectTimeoutMs": milliseconds(configuration.disconnectTimeout),
            "reconnectGraceMs": milliseconds(configuration.reconnectGrace),
            "resultRetentionMs": milliseconds(configuration.resultRetention),
            "resumeToken": mutation.metadata.rotatedResumeToken ?? NSNull(),
        ]

        return success(
            action: action,
            data: [
                "helloAck": helloAck,
                "snapshot": serializeSnapshot(mutation.snapshot),
                "events": mutation.events.map(serializeEvent),
                "metadata": serializeMetadata(mutation.metadata),
            ]
        )
    }

    private func handleRecordGameStartedAndPrepareBootstrap(
        _ payload: RecordGameStartedRequest,
        action: String
    ) throws -> [String: Any] {
        let authorityRelay = try requireAuthorityRelay()
        let mutation = try coordinator.recordGameStarted(payload)
        let bootstrapByPlayerId = mutation.metadata.gameStartedBootstrapPlan?.requestsByPlayerId.mapValues {
            authorityRelay.fetchGameStartedBootstrap($0)
        } ?? [:]

        return success(
            action: action,
            data: [
                "mutation": mutationResponse(mutation),
                "bootstrapByPlayerId": bootstrapByPlayerId,
            ]
        )
    }

    private func handleProjectionPreview(
        _ payload: RoomProjectionPreviewCLIRequest,
        action: String
    ) throws -> [String: Any] {
        let authorityRelay = try requireAuthorityRelay()
        guard let snapshot = coordinator.snapshot(for: payload.roomId) else {
            throw RoomCoordinatorError.roomNotFound(roomId: payload.roomId)
        }
        guard let request = makeProjectionPreviewRequest(
            from: snapshot,
            viewerPlayerId: payload.viewerPlayerId,
            gameId: payload.gameId,
            projectionScope: payload.scope ?? "player",
            snapshotReason: payload.snapshotReason ?? "localPreview",
            stateVersion: payload.stateVersion ?? 0,
            lastEventId: payload.lastEventId
        ) else {
            throw RoomCoordinatorError.invalidRoomState(
                expected: [.starting, .inGame, .ended],
                actual: snapshot.room.roomState
            )
        }

        return success(
            action: action,
            data: [
                "request": roomProjectionPreviewRequestData(from: request),
                "projection": authorityRelay.fetchProjectionPreview(request),
            ]
        )
    }

    private func handleRecordMatchEndedAndFetchTerminalSummary(
        _ payload: RoomRecordMatchEndedCLIRequest,
        action: String
    ) throws -> [String: Any] {
        let authorityRelay = try requireAuthorityRelay()
        let mutation = try coordinator.recordMatchEnded(
            RecordMatchEndedRequest(
                roomId: payload.roomId,
                roundIndex: payload.roundIndex,
                quitReason: payload.quitReason,
                forfeitingPlayerId: payload.forfeitingPlayerId,
                summaryStateVersion: payload.summaryStateVersion,
                lastEventId: payload.lastEventId,
                resultRetentionAt: nil
            )
        )
        guard let terminalRequest = mutation.metadata.terminalSummaryRelayRequest else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.ended], actual: mutation.snapshot.room.roomState)
        }

        return success(
            action: action,
            data: [
                "mutation": mutationResponse(mutation),
                "terminalSummaryRequest": roomTerminalSummaryRelayRequestData(from: terminalRequest),
                "terminalSummary": authorityRelay.fetchTerminalSummary(terminalRequest),
            ]
        )
    }

    private func transportConnect(_ payload: RoomTransportConnectCLIRequest) -> [String: Any] {
        let state = RoomTransportClientState(
            clientId: payload.clientId,
            roomId: payload.roomId,
            sessionId: payload.sessionId,
            playerId: payload.playerId,
            deviceId: payload.deviceId,
            resumeToken: payload.resumeToken,
            connectionId: nil
        )
        transportClients[payload.clientId] = state
        transportMailboxes[payload.clientId] = transportMailboxes[payload.clientId] ?? []
        return [
            "clientId": payload.clientId,
            "roomId": payload.roomId,
            "sessionId": payload.sessionId,
            "playerId": payload.playerId,
            "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
        ]
    }

    private func handleTransportSend(
        _ payload: RoomTransportSendCLIRequest,
        action: String
    ) throws -> [String: Any] {
        var client = try requireTransportClient(payload.clientId)

        switch payload.action {
        case "hello":
            let helloPayload = RoomHelloCLIRequest(
                roomId: client.roomId,
                sessionId: client.sessionId,
                playerId: client.playerId,
                deviceId: client.deviceId,
                connectionId: payload.connectionId,
                resumeToken: client.resumeToken,
                lastSeen: payload.lastSeen
            )
            let resolution = try performRoomHello(
                coordinator: coordinator,
                roomId: helloPayload.roomId,
                sessionId: helloPayload.sessionId,
                playerId: helloPayload.playerId,
                deviceId: helloPayload.deviceId,
                connectionId: helloPayload.connectionId,
                resumeToken: helloPayload.resumeToken,
                lastAckedRoomSequence: helloPayload.lastSeen?.roomSequence,
                lastAckedGameEventId: helloPayload.lastSeen?.gameEventId,
                lastSeenStateVersion: helloPayload.lastSeen?.stateVersion
            )
            let mutation = resolution.mutation
            client.connectionId = payload.connectionId
            if let rotatedResumeToken = mutation.metadata.rotatedResumeToken {
                client.resumeToken = rotatedResumeToken
            }
            transportClients[payload.clientId] = client

            enqueue(
                envelope: makeTransportEnvelope(
                    type: "helloAck",
                    roomId: client.roomId,
                    sessionId: client.sessionId,
                    roomSequence: mutation.snapshot.room.lastRoomSequence,
                    payload: [
                        "resumeMode": resolution.resumeMode.rawValue,
                        "connectionId": payload.connectionId ?? NSNull(),
                        "heartbeatIntervalMs": milliseconds(configuration.heartbeatInterval),
                        "disconnectTimeoutMs": milliseconds(configuration.disconnectTimeout),
                        "reconnectGraceMs": milliseconds(configuration.reconnectGrace),
                        "resultRetentionMs": milliseconds(configuration.resultRetention),
                        "resumeToken": mutation.metadata.rotatedResumeToken ?? client.resumeToken,
                    ]
                ),
                for: payload.clientId
            )
            enqueue(
                envelope: makeTransportEnvelope(
                    type: "roomSnapshot",
                    roomId: client.roomId,
                    sessionId: client.sessionId,
                    roomSequence: mutation.snapshot.room.lastRoomSequence,
                    payload: serializeSnapshot(mutation.snapshot)
                ),
                for: payload.clientId
            )
            broadcastRoomEvents(
                mutation.events,
                in: mutation.snapshot.room.roomId,
                prioritizingClientId: payload.clientId
            )
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                    "client": serializeTransportClient(client),
                    "metadata": serializeMetadata(mutation.metadata),
                ]
            )
        case "ack", "pong":
            let mutation = try coordinator.recordHeartbeat(
                RecordHeartbeatRequest(
                    roomId: client.roomId,
                    sessionId: client.sessionId,
                    connectionId: client.connectionId,
                    lastAckedRoomSequence: payload.lastSeen?.roomSequence,
                    lastAckedGameEventId: payload.lastSeen?.gameEventId,
                    lastSeenStateVersion: payload.lastSeen?.stateVersion
                )
            )
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "setReady":
            let mutation = try coordinator.setReady(
                SetReadyRequest(
                    roomId: client.roomId,
                    playerId: client.playerId,
                    ready: payload.ready ?? true
                )
            )
            broadcastRoomEvents(mutation.events, in: client.roomId)
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "snapshot":
            guard let snapshot = coordinator.snapshot(for: client.roomId) else {
                throw RoomCoordinatorError.roomNotFound(roomId: client.roomId)
            }
            enqueue(
                envelope: makeTransportEnvelope(
                    type: "roomSnapshot",
                    roomId: client.roomId,
                    sessionId: client.sessionId,
                    roomSequence: snapshot.room.lastRoomSequence,
                    payload: serializeSnapshot(snapshot)
                ),
                for: payload.clientId
            )
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "recordGameStartedAndPrepareBootstrap":
            let authorityRelay = try requireAuthorityRelay()
            let mutation = try coordinator.recordGameStarted(
                RecordGameStartedRequest(
                    roomId: client.roomId,
                    gameId: payload.gameId ?? "transport_game_\(client.roomId)"
                )
            )
            broadcastRoomEvents(mutation.events, in: client.roomId)
            if let bootstrapPlan = mutation.metadata.gameStartedBootstrapPlan {
                for request in bootstrapPlan.requestsByPlayerId.values {
                    guard let targetClientId = transportClientID(
                        roomId: client.roomId,
                        playerId: request.viewerPlayerId
                    ) else {
                        continue
                    }
                    let bootstrapPayload = authorityRelay.fetchGameStartedBootstrap(request)
                    if let gameStarted = bootstrapPayload["gameStarted"] {
                        enqueue(
                            envelope: makeTransportEnvelope(
                                type: "gameEvent",
                                roomId: request.roomId,
                                sessionId: transportClients[targetClientId]?.sessionId,
                                roomSequence: mutation.snapshot.room.lastRoomSequence,
                                payload: ["engineEvent": gameStarted]
                            ),
                            for: targetClientId
                        )
                    }
                    if let stateSnapshot = bootstrapPayload["stateSnapshot"] {
                        enqueue(
                            envelope: makeTransportEnvelope(
                                type: "gameEvent",
                                roomId: request.roomId,
                                sessionId: transportClients[targetClientId]?.sessionId,
                                roomSequence: mutation.snapshot.room.lastRoomSequence,
                                payload: ["engineEvent": stateSnapshot]
                            ),
                            for: targetClientId
                        )
                    }
                }
            }
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "recordMatchEndedAndFetchTerminalSummary":
            let authorityRelay = try requireAuthorityRelay()
            let mutation = try coordinator.recordMatchEnded(
                RecordMatchEndedRequest(
                    roomId: client.roomId,
                    roundIndex: payload.roundIndex,
                    quitReason: payload.quitReason,
                    forfeitingPlayerId: payload.forfeitingPlayerId,
                    summaryStateVersion: payload.summaryStateVersion,
                    lastEventId: payload.lastEventId,
                    resultRetentionAt: nil
                )
            )
            broadcastRoomEvents(mutation.events, in: client.roomId)
            if let terminalRequest = mutation.metadata.terminalSummaryRelayRequest {
                let terminalPayload = authorityRelay.fetchTerminalSummary(terminalRequest)
                broadcast(
                    envelope: makeTransportEnvelope(
                        type: "terminalSummary",
                        roomId: terminalRequest.roomId,
                        sessionId: nil,
                        roomSequence: mutation.snapshot.room.lastRoomSequence,
                        payload: terminalPayload
                    ),
                    in: client.roomId
                )
            }
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        default:
            throw RoomCLIAdapterError.unsupportedTransportAction(payload.action)
        }
    }

    private func transportReceive(_ payload: RoomTransportReceiveCLIRequest) -> [String: Any] {
        let envelopes = transportMailboxes[payload.clientId] ?? []
        transportMailboxes[payload.clientId] = []
        return [
            "clientId": payload.clientId,
            "envelopes": envelopes,
        ]
    }

    private func requireAuthorityRelay() throws -> RoomAuthorityRelay {
        guard let authorityRelay else {
            throw RoomCLIAdapterError.authorityRelayUnavailable
        }
        return authorityRelay
    }

    private func requireTransportClient(_ clientId: String) throws -> RoomTransportClientState {
        guard let client = transportClients[clientId] else {
            throw RoomCLIAdapterError.transportClientNotFound(clientId)
        }
        return client
    }

    private func transportClientID(roomId: String, playerId: String) -> String? {
        transportClients.values.first(where: { $0.roomId == roomId && $0.playerId == playerId })?.clientId
    }

    private func broadcastRoomEvents(
        _ events: [RoomCoordinatorEvent],
        in roomId: String,
        prioritizingClientId: String? = nil
    ) {
        let clientIds = connectedTransportClientIDs(in: roomId)
        let prioritized = clientIds.sorted { lhs, rhs in
            if lhs == prioritizingClientId { return true }
            if rhs == prioritizingClientId { return false }
            return lhs < rhs
        }
        for clientId in prioritized {
            guard let sessionId = transportClients[clientId]?.sessionId else { continue }
            for event in events {
                enqueue(
                    envelope: makeTransportEnvelope(
                        type: "roomEvent",
                        roomId: roomId,
                        sessionId: sessionId,
                        roomSequence: event.roomSequence,
                        payload: serializeEvent(event)
                    ),
                    for: clientId
                )
            }
        }
    }

    private func broadcast(envelope: [String: Any], in roomId: String) {
        for clientId in connectedTransportClientIDs(in: roomId) {
            enqueue(envelope: envelope, for: clientId)
        }
    }

    private func connectedTransportClientIDs(in roomId: String) -> [String] {
        transportClients.values
            .filter { $0.roomId == roomId }
            .map(\.clientId)
            .sorted()
    }

    private func enqueue(envelope: [String: Any], for clientId: String) {
        transportMailboxes[clientId, default: []].append(envelope)
    }

    private func makeTransportEnvelope(
        type: String,
        roomId: String,
        sessionId: String?,
        roomSequence: Int?,
        payload: [String: Any]
    ) -> [String: Any] {
        var envelope: [String: Any] = [
            "type": type,
            "roomId": roomId,
            "serverTime": dateString(Date()),
            "payload": payload,
        ]
        if let sessionId {
            envelope["sessionId"] = sessionId
        }
        if let roomSequence {
            envelope["roomSequence"] = roomSequence
        }
        return envelope
    }

    private func serializeTransportClient(_ client: RoomTransportClientState) -> [String: Any] {
        [
            "clientId": client.clientId,
            "roomId": client.roomId,
            "sessionId": client.sessionId,
            "playerId": client.playerId,
            "deviceId": client.deviceId,
            "resumeToken": client.resumeToken,
            "connectionId": client.connectionId ?? NSNull(),
        ]
    }

    private func createOrJoinResponse(
        mutation: RoomCoordinatorMutation,
        playerId: String
    ) -> [String: Any] {
        var data: [String: Any] = [
            "room": serializeRoom(mutation.snapshot.room),
            "websocket": transportPolicy(),
            "mutation": mutationResponse(mutation),
        ]
        if let session = mutation.snapshot.sessions.first(where: { $0.playerId == playerId }) {
            data["session"] = serializeSession(session)
        }
        return data
    }

    private func mutationResponse(_ mutation: RoomCoordinatorMutation) -> [String: Any] {
        [
            "action": mutation.action.rawValue,
            "snapshot": serializeSnapshot(mutation.snapshot),
            "events": mutation.events.map(serializeEvent),
            "metadata": serializeMetadata(mutation.metadata),
        ]
    }

    private func transportPolicy() -> [String: Any] {
        [
            "heartbeatIntervalMs": milliseconds(configuration.heartbeatInterval),
            "disconnectTimeoutMs": milliseconds(configuration.disconnectTimeout),
            "reconnectGraceMs": milliseconds(configuration.reconnectGrace),
            "resultRetentionMs": milliseconds(configuration.resultRetention),
        ]
    }

    private func serializeSnapshot(_ snapshot: RoomCoordinatorSnapshot) -> [String: Any] {
        [
            "room": serializeRoom(snapshot.room),
            "sessions": snapshot.sessions.map(serializeSession),
        ]
    }

    private func serializeRoom(_ room: Room) -> [String: Any] {
        [
            "roomId": room.roomId,
            "roomType": room.roomType.rawValue,
            "joinPolicy": room.joinPolicy.rawValue,
            "roomState": room.roomState.rawValue,
            "hostPlayerId": room.hostPlayerId,
            "activeGameId": room.activeGameId ?? NSNull(),
            "members": room.members.map(serializeMember),
            "deadlines": serializeDeadlines(room.deadlines),
            "lastRoomSequence": room.lastRoomSequence,
            "createdAt": dateString(room.createdAt),
            "closedAt": nullableDate(room.closedAt),
        ]
    }

    private func serializeMember(_ member: RoomMember) -> [String: Any] {
        [
            "playerId": member.playerId,
            "seat": member.seat,
            "role": member.role.rawValue,
            "ready": member.ready,
            "presence": member.presence.rawValue,
            "sessionId": member.sessionId,
            "connectedConnectionId": member.connectedConnectionId ?? NSNull(),
            "joinedAt": dateString(member.joinedAt),
        ]
    }

    private func serializeDeadlines(_ deadlines: RoomDeadlines) -> [String: Any] {
        [
            "joinExpiresAt": nullableDate(deadlines.joinExpiresAt),
            "readyExpiresAt": nullableDate(deadlines.readyExpiresAt),
            "resultExpiresAt": nullableDate(deadlines.resultExpiresAt),
        ]
    }

    private func serializeSession(_ session: RoomSession) -> [String: Any] {
        [
            "sessionId": session.sessionId,
            "playerId": session.playerId,
            "roomId": session.roomId,
            "deviceId": session.deviceId,
            "connectionState": session.connectionState.rawValue,
            "connectionId": session.connectionId ?? NSNull(),
            "resumeToken": session.resumeToken,
            "resumeIssuedAt": dateString(session.resumeIssuedAt),
            "graceExpiresAt": nullableDate(session.graceExpiresAt),
            "lastHeartbeatAt": dateString(session.lastHeartbeatAt),
            "lastAckedRoomSequence": session.lastAckedRoomSequence,
            "lastAckedGameEventId": session.lastAckedGameEventId ?? NSNull(),
            "lastSeenStateVersion": session.lastSeenStateVersion ?? NSNull(),
        ]
    }

    private func serializeEvent(_ event: RoomCoordinatorEvent) -> [String: Any] {
        [
            "roomId": event.roomId,
            "roomSequence": event.roomSequence,
            "occurredAt": dateString(event.occurredAt),
            "payload": serializeEventPayload(event.payload),
        ]
    }

    private func serializeEventPayload(_ payload: RoomCoordinatorEventPayload) -> [String: Any] {
        switch payload {
        case let .roomStateChanged(from, to, reason):
            return [
                "eventName": "roomStateChanged",
                "fromState": from.rawValue,
                "toState": to.rawValue,
                "reason": reason.rawValue,
            ]
        case let .memberJoined(playerId, seat, role):
            return [
                "eventName": "memberJoined",
                "playerId": playerId,
                "seat": seat,
                "role": role.rawValue,
            ]
        case let .memberLeft(playerId, reason):
            return [
                "eventName": "memberLeft",
                "playerId": playerId,
                "reason": reason.rawValue,
            ]
        case let .memberReadyChanged(playerId, ready):
            return [
                "eventName": "memberReadyChanged",
                "playerId": playerId,
                "ready": ready,
            ]
        case let .readyWindowExpired(resetPlayerIds):
            return [
                "eventName": "readyWindowExpired",
                "resetPlayerIds": resetPlayerIds,
            ]
        case let .playerDisconnected(playerId, graceExpiresAt):
            return [
                "eventName": "playerDisconnected",
                "playerId": playerId,
                "graceExpiresAt": dateString(graceExpiresAt),
            ]
        case let .playerReconnected(playerId, connectionId):
            return [
                "eventName": "playerReconnected",
                "playerId": playerId,
                "connectionId": connectionId ?? NSNull(),
            ]
        case let .playerForfeited(playerId, reason):
            return [
                "eventName": "playerForfeited",
                "playerId": playerId,
                "reason": reason.rawValue,
            ]
        case let .roomClosed(reason, closedAt):
            return [
                "eventName": "roomClosed",
                "reason": reason.rawValue,
                "closedAt": dateString(closedAt),
            ]
        }
    }

    private func serializeMetadata(_ metadata: RoomCoordinatorMutationMetadata) -> [String: Any] {
        [
            "requiresGameBootstrap": metadata.requiresGameBootstrap,
            "rotatedResumeToken": metadata.rotatedResumeToken ?? NSNull(),
            "supersededConnectionId": metadata.supersededConnectionId ?? NSNull(),
            "gameStartControlMode": metadata.gameStartControlMode?.rawValue ?? NSNull(),
            "gameStartedBootstrapPlan": serializeBootstrapPlan(metadata.gameStartedBootstrapPlan),
            "terminalSummaryRelayRequest": serializeTerminalSummaryRelayRequest(metadata.terminalSummaryRelayRequest),
        ]
    }

    private func serializeBootstrapPlan(_ plan: RoomGameStartedBootstrapPlan?) -> Any {
        guard let plan else {
            return NSNull()
        }

        return [
            "controlMode": plan.controlMode.rawValue,
            "fetchAction": plan.fetchAction,
            "requestsByPlayerId": plan.requestsByPlayerId.mapValues(serializeBootstrapRequest),
        ]
    }

    private func serializeBootstrapRequest(_ request: RoomGameStartedBootstrapRequest) -> [String: Any] {
        [
            "roomId": request.roomId,
            "gameId": request.gameId,
            "viewerPlayerId": request.viewerPlayerId,
            "projectionScope": request.projectionScope,
            "snapshotReason": request.snapshotReason,
            "stateVersionHint": request.stateVersionHint,
            "participantPresenceByPlayerId": request.participantPresenceByPlayerId.mapValues(serializeBootstrapPresence),
        ]
    }

    private func serializeBootstrapPresence(_ presence: RoomBootstrapParticipantPresence) -> [String: Any] {
        [
            "source": presence.source,
            "isConnected": presence.isConnected,
            "isReady": presence.isReady,
        ]
    }

    private func serializeTerminalSummaryRelayRequest(_ request: RoomTerminalSummaryRelayRequest?) -> Any {
        guard let request else {
            return NSNull()
        }

        return [
            "roomId": request.roomId,
            "gameId": request.gameId,
            "roundIndex": request.roundIndex,
            "quitReason": request.quitReason ?? NSNull(),
            "forfeitingPlayerId": request.forfeitingPlayerId ?? NSNull(),
            "summaryStateVersion": request.summaryStateVersion,
            "lastEventId": request.lastEventId ?? NSNull(),
            "participantPresenceByPlayerId": request.participantPresenceByPlayerId.mapValues(serializeBootstrapPresence),
        ]
    }

    private func serializeDeterministicFaultHook(_ hook: RoomDeterministicFaultHook?) -> Any {
        guard let hook else {
            return NSNull()
        }

        return [
            "kind": hook.kind.rawValue,
            "targetSessionId": hook.targetSessionId,
            "overriddenExpectedStateVersion": hook.overriddenExpectedStateVersion,
        ]
    }

    private func success(action: String, data: [String: Any]) -> [String: Any] {
        [
            "status": "ok",
            "action": action,
            "data": data,
        ]
    }

    private func failure(action: String, code: String, message: String) -> [String: Any] {
        [
            "status": "error",
            "action": action,
            "errorCode": code,
            "message": message,
        ]
    }

    private func decode<T: Decodable>(_ type: T.Type, from payload: [String: AnyCodable]?) throws -> T {
        let unboxed = TestControlSupport.unbox(payload) ?? [:]
        let data = try JSONSerialization.data(withJSONObject: unboxed, options: [])
        return try decoder.decode(type, from: data)
    }

    private func errorCode(_ error: RoomCoordinatorError) -> String {
        switch error {
        case .roomNotFound:
            return "roomNotFound"
        case .roomFull:
            return "roomFull"
        case .roomClosed:
            return "roomClosed"
        case .playerAlreadyInRoom:
            return "playerAlreadyInRoom"
        case .playerNotInRoom:
            return "playerNotInRoom"
        case .sessionNotFound:
            return "sessionNotFound"
        case .invalidRoomState:
            return "invalidRoomState"
        case .invalidResumeState:
            return "invalidResumeState"
        case .staleConnectionId:
            return "staleConnectionId"
        case .resumeTokenInvalid:
            return "resumeTokenInvalid"
        case .resumeExpired:
            return "resumeExpired"
        case .readyRequiresTwoMembers:
            return "readyRequiresTwoMembers"
        case .closeRequiresHostOrTerminalState:
            return "closeRequiresHostOrTerminalState"
        }
    }

    private func adapterErrorCode(_ error: RoomCLIAdapterError) -> String {
        switch error {
        case .authorityRelayUnavailable:
            return "authorityRelayUnavailable"
        case .transportClientNotFound:
            return "transportClientNotFound"
        case .unsupportedTransportAction:
            return "unsupportedTransportAction"
        }
    }

    private func errorMessage(_ error: RoomCoordinatorError) -> String {
        switch error {
        case let .roomNotFound(roomId):
            return "Room not found: \(roomId)"
        case let .roomFull(roomId):
            return "Room is full: \(roomId)"
        case let .roomClosed(roomId):
            return "Room is closed: \(roomId)"
        case let .playerAlreadyInRoom(playerId, roomId):
            return "Player \(playerId) is already in room \(roomId)"
        case let .playerNotInRoom(playerId, roomId):
            return "Player \(playerId) is not in room \(roomId)"
        case let .sessionNotFound(sessionId):
            return "Session not found: \(sessionId)"
        case let .invalidRoomState(expected, actual):
            return "Invalid room state. Expected \(expected.map(\.rawValue).joined(separator: ", ")), got \(actual.rawValue)"
        case let .invalidResumeState(state):
            return "Invalid session state for requested resume/attach flow: \(state.rawValue)"
        case let .staleConnectionId(expected, actual):
            return "Stale connectionId. Expected \(expected ?? "nil"), got \(actual ?? "nil")"
        case .resumeTokenInvalid:
            return "Resume token is invalid"
        case .resumeExpired:
            return "Resume token expired"
        case .readyRequiresTwoMembers:
            return "Ready flow requires exactly two members"
        case .closeRequiresHostOrTerminalState:
            return "Close requires a pregame or terminal room state"
        }
    }

    private func adapterErrorMessage(_ error: RoomCLIAdapterError) -> String {
        switch error {
        case .authorityRelayUnavailable:
            return "Authority relay is unavailable for this room command"
        case let .transportClientNotFound(clientId):
            return "Transport client not found: \(clientId)"
        case let .unsupportedTransportAction(action):
            return "Unsupported transport action: \(action)"
        }
    }

    private func dateString(_ value: Date) -> String {
        iso8601Formatter.string(from: value)
    }

    private func nullableDate(_ value: Date?) -> Any {
        value.map(dateString) ?? NSNull()
    }

    private func milliseconds(_ value: TimeInterval) -> Int {
        Int(value * 1000)
    }
}
