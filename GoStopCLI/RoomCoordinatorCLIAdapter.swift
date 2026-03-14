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

private struct RoomBootstrapLookupCLIRequest: Codable {
    var inviteCode: String
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
    var requestId: String?
    var traceId: String?
    var actionId: String?
    var expectedStateVersion: Int?
    var commandPayload: [String: AnyCodable]?
    var connectionId: String?
    var ready: Bool?
    var gameId: String?
    var roundIndex: Int?
    var quitReason: String?
    var forfeitingPlayerId: String?
    var summaryStateVersion: Int?
    var lastEventId: String?
    var lastSeen: RoomHelloCursor?
    var asOf: Date?
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

private struct RoomTransportGameState {
    var roomId: String
    var gameId: String
    var stateVersion: Int
    var lastEventOrdinal: Int
    var lastEventId: String?
    var lastTurnId: String?
}

private struct RoomTransportActionRecordKey: Hashable {
    var roomId: String
    var playerId: String
    var actionId: String
}

private struct RoomTransportActionRecordContext {
    var key: RoomTransportActionRecordKey
    var fingerprint: String
    var mailboxCursor: [String: Int]
}

private struct RoomTransportActionRecord {
    var fingerprint: String
    var response: [String: Any]
    var replayEnvelopesByClientId: [String: [[String: Any]]]
}

private enum RoomTransportDuplicateActionResolution {
    case fresh(RoomTransportActionRecordContext?)
    case replay([String: Any])
}

private struct RoomTransportResolvedGameplayCommand {
    var requestId: String
    var traceId: String?
    var actionId: String
    var roomPlayerId: String
    var authorityPlayerId: String
    var expectedStateVersion: Int
    var commandName: MultiplayerCommandName
    var commandPayload: [String: Any]
}

private struct RoomTransportDisconnectResolution {
    var client: RoomTransportClientState
    var mutation: RoomCoordinatorMutation
}

struct RoomAuthorityGameplayExecutionRequest {
    var playerId: String
    var commandName: MultiplayerCommandName
    var commandPayload: [String: Any]
}

struct RoomAuthorityGameplayExecutionResult {
    var result: [String: Any]
}

struct RoomAuthorityGameplayRejection: Error {
    var code: MultiplayerRejectCode
    var retryable: Bool
    var messageKey: String
}

struct RoomAuthorityRelay {
    var fetchProjectionPreview: (RoomProjectionPreviewRequest) -> [String: Any]
    var fetchGameStartedBootstrap: (RoomGameStartedBootstrapRequest) -> [String: Any]
    var fetchTerminalSummary: (RoomTerminalSummaryRelayRequest) -> [String: Any]
    var executeGameplayCommand: (RoomAuthorityGameplayExecutionRequest) throws -> RoomAuthorityGameplayExecutionResult
}

private enum RoomCLIAdapterError: Error {
    case authorityRelayUnavailable
    case transportClientNotFound(String)
    case unsupportedTransportAction(String)
    case transportGameNotStarted(String)
    case invalidAuthorityPayload(String)
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
    private var transportGameStates: [String: RoomTransportGameState] = [:]
    private var transportActionRecords: [RoomTransportActionRecordKey: RoomTransportActionRecord] = [:]
    private var authorityPlayerIdByRoomId: [String: [String: String]] = [:]

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
            case "room_create", "room_bootstrap_create":
                let payload = try decode(CreateRoomRequest.self, from: request.data)
                let mutation = try coordinator.createRoom(payload)
                return success(
                    action: request.action,
                    data: bootstrapScopedData(
                        createOrJoinResponse(mutation: mutation, playerId: payload.hostPlayerId),
                        stage: "createRoom",
                        currentAction: request.action,
                        futurePublicRoute: "POST /api/multiplayer/rooms"
                    )
                )
            case "room_join", "room_bootstrap_join":
                let payload = try decode(JoinRoomRequest.self, from: request.data)
                let mutation = try coordinator.joinRoom(payload)
                return success(
                    action: request.action,
                    data: bootstrapScopedData(
                        createOrJoinResponse(mutation: mutation, playerId: payload.playerId),
                        stage: "joinRoom",
                        currentAction: request.action,
                        futurePublicRoute: "POST /api/multiplayer/rooms/{roomId}/join"
                    )
                )
            case "room_bootstrap_lookup_invite":
                let payload = try decode(RoomBootstrapLookupCLIRequest.self, from: request.data)
                return try handleBootstrapLookupInvite(payload, action: request.action)
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
            case "room_record_game_started_and_prepare_bootstrap", "room_bootstrap_prepare_game_start":
                let payload = try decode(RecordGameStartedRequest.self, from: request.data)
                return try handleRecordGameStartedAndPrepareBootstrap(payload, action: request.action)
            case "room_gap_recovery_shape":
                return success(
                    action: request.action,
                    data: gapRecoveryShape()
                )
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
        let bootstrapByPlayerId = try mutation.metadata.gameStartedBootstrapPlan.map { plan in
            try fetchBootstrapPayloadsByPlayerId(
                bootstrapPlan: plan,
                roomSnapshot: mutation.snapshot,
                authorityRelay: authorityRelay
            )
        } ?? [:]

        return success(
            action: action,
            data: [
                "mutation": mutationResponse(mutation),
                "bootstrapByPlayerId": bootstrapByPlayerId,
                "bootstrapBoundary": bootstrapBoundary(
                    stage: "prepareGameStart",
                    currentAction: action,
                    futurePublicRoute: "POST /api/multiplayer/rooms/{roomId}/bootstrap/game-start"
                ),
            ]
        )
    }

    private func handleBootstrapLookupInvite(
        _ payload: RoomBootstrapLookupCLIRequest,
        action: String
    ) throws -> [String: Any] {
        // Phase 0 ships invite lookup as part of the bootstrap facade.
        guard let snapshot = coordinator.snapshot(for: payload.inviteCode) else {
            throw RoomCoordinatorError.roomNotFound(roomId: payload.inviteCode)
        }

        let room = snapshot.room
        let inviteCode = serializedInviteCode(for: room) ?? room.roomId
        let availableSeatCount = max(0, 2 - room.members.count)
        let roomIsJoinable = room.roomState == .waitingForPlayers || room.roomState == .waitingForReady
        return success(
            action: action,
            data: [
                "inviteCode": inviteCode,
                "roomSummary": [
                    "roomId": room.roomId,
                    "inviteCode": inviteCode,
                    "roomType": room.roomType.rawValue,
                    "joinPolicy": room.joinPolicy.rawValue,
                    "roomState": room.roomState.rawValue,
                    "hostPlayerId": room.hostPlayerId,
                    "memberCount": room.members.count,
                    "availableSeatCount": availableSeatCount,
                    "canJoin": roomIsJoinable && availableSeatCount > 0,
                    "activeGameId": room.activeGameId ?? NSNull(),
                    "members": room.members
                        .sorted(by: { $0.seat < $1.seat })
                        .map { member in
                            [
                                "playerId": member.playerId,
                                "seat": member.seat,
                                "role": member.role.rawValue,
                                "ready": member.ready,
                                "presence": member.presence.rawValue,
                            ]
                        },
                ],
                "websocket": transportPolicy(),
                "bootstrapBoundary": bootstrapBoundary(
                    stage: "lookupInvite",
                    currentAction: action,
                    futurePublicRoute: "GET /api/multiplayer/invites/{inviteCode}"
                ),
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
        let gameId = payload.gameId ?? snapshot.room.activeGameId ?? "game_\(payload.roomId)"
        let gameState = resolveTransportGameState(
            roomId: payload.roomId,
            gameId: gameId,
            fallbackStateVersion: payload.stateVersion ?? 0
        )
        guard var request = makeProjectionPreviewRequest(
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
        request = try mappedProjectionPreviewRequest(
            request,
            roomSnapshot: snapshot,
            gameState: gameState,
            authorityRelay: authorityRelay,
            preferredRoomPlayerId: payload.viewerPlayerId
        )

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
        let (mappedTerminalRequest, terminalPayload) = try fetchTerminalSummaryPayload(
            authorityRelay: authorityRelay,
            roomSnapshot: mutation.snapshot,
            terminalRequest: terminalRequest
        )

        return success(
            action: action,
            data: [
                "mutation": mutationResponse(mutation),
                "terminalSummaryRequest": roomTerminalSummaryRelayRequestData(from: mappedTerminalRequest),
                "terminalSummary": terminalPayload,
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
            try enqueueResumeSnapshotIfNeeded(
                resolution: resolution,
                client: client,
                payload: payload
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
        case "disconnect":
            let resolution = try disconnectTransportClient(
                clientId: payload.clientId,
                expectedConnectionId: client.connectionId,
                requireExpectedConnectionId: false
            )
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": resolution.map { mutationResponse($0.mutation) } ?? NSNull(),
                    "noop": resolution == nil,
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "leaveRoom":
            let mutation = try coordinator.leaveRoom(
                LeaveRoomRequest(
                    roomId: client.roomId,
                    playerId: client.playerId
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
        case "triggerGapRecovery":
            return try handleTransportGapRecovery(
                payload,
                client: client,
                action: action
            )
        case "reapExpiredState":
            let mutations = try handleTransportExpirySweep(
                asOf: payload.asOf ?? Date(),
                initiatedByClientId: payload.clientId,
                traceId: payload.traceId
            )
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutations": mutations.map(mutationResponse),
                    "authoritativeStateVersion": transportGameStates[client.roomId]?.stateVersion ?? NSNull(),
                    "authoritativeEventId": transportGameStates[client.roomId]?.lastEventId ?? NSNull(),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        case "playCard", "submitChoice", "quit":
            return try handleTransportGameplay(
                payload,
                client: client,
                action: action
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
                try enqueueBootstrapEnvelopes(
                    bootstrapPlan: bootstrapPlan,
                    mutation: mutation,
                    authorityRelay: authorityRelay
                )
            }
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "authoritativeStateVersion": transportGameStates[client.roomId]?.stateVersion ?? NSNull(),
                    "authoritativeEventId": transportGameStates[client.roomId]?.lastEventId ?? NSNull(),
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
                let (_, terminalPayload) = try fetchTerminalSummaryPayload(
                    authorityRelay: authorityRelay,
                    roomSnapshot: mutation.snapshot,
                    terminalRequest: terminalRequest
                )
                try enqueueTerminalSummaryEnvelopes(
                    terminalPayload: terminalPayload,
                    terminalRequest: terminalRequest,
                    mutation: mutation
                )
            }
            return success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "mutation": mutationResponse(mutation),
                    "authoritativeStateVersion": transportGameStates[client.roomId]?.stateVersion ?? NSNull(),
                    "authoritativeEventId": transportGameStates[client.roomId]?.lastEventId ?? NSNull(),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
        default:
            throw RoomCLIAdapterError.unsupportedTransportAction(payload.action)
        }
    }

    @discardableResult
    func handleTransportExpirySweep(
        asOf: Date,
        initiatedByClientId: String? = nil,
        traceId: String? = nil
    ) throws -> [RoomCoordinatorMutation] {
        let mutations = try coordinator.reapExpiredState(asOf: asOf)
        try relayExpiredTransportMutations(
            mutations,
            initiatedByClientId: initiatedByClientId,
            traceId: traceId
        )
        return mutations
    }

    @discardableResult
    func handlePassiveTransportTeardown(
        clientId: String,
        expectedConnectionId: String?
    ) -> [String: Any]? {
        guard let resolution = try? disconnectTransportClient(
            clientId: clientId,
            expectedConnectionId: expectedConnectionId,
            requireExpectedConnectionId: true
        ) else {
            return nil
        }
        return [
            "client": serializeTransportClient(resolution.client),
            "mutation": mutationResponse(resolution.mutation),
        ]
    }

    private func enqueueResumeSnapshotIfNeeded(
        resolution: RoomHelloResolution,
        client: RoomTransportClientState,
        payload: RoomTransportSendCLIRequest
    ) throws {
        guard resolution.resumeMode == .resume else {
            return
        }
        let snapshot = resolution.mutation.snapshot
        guard [.starting, .inGame, .ended].contains(snapshot.room.roomState),
              let gameId = snapshot.room.activeGameId else {
            return
        }

        let authorityRelay = try requireAuthorityRelay()
        let currentGameState = resolveTransportGameState(
            roomId: snapshot.room.roomId,
            gameId: gameId,
            fallbackStateVersion: payload.lastSeen?.stateVersion ?? 0
        )
        let stateSnapshot = try fetchProjectionSnapshot(
            authorityRelay: authorityRelay,
            roomSnapshot: snapshot,
            viewerPlayerId: client.playerId,
            gameState: currentGameState,
            snapshotReason: .resume
        )
        let eventId = nextGameEventID(for: snapshot.room.roomId)
        let engineEvent = makeEngineEventEnvelope(
            traceId: payload.traceId,
            roomId: snapshot.room.roomId,
            gameId: gameId,
            eventId: eventId,
            stateVersion: stateSnapshot.snapshotStateVersion,
            causedByActionId: payload.actionId,
            eventName: .stateSnapshot,
            payload: try requireJSONObject(from: stateSnapshot)
        )
        enqueueGameEvent(
            engineEvent: engineEvent,
            roomId: snapshot.room.roomId,
            clientId: client.clientId,
            roomSequence: snapshot.room.lastRoomSequence
        )

        var nextState = currentGameState
        nextState.stateVersion = max(currentGameState.stateVersion, stateSnapshot.snapshotStateVersion)
        nextState.lastEventId = eventId
        nextState.lastTurnId = stateSnapshot.state.turnId
        transportGameStates[snapshot.room.roomId] = nextState
    }

    private func enqueueBootstrapEnvelopes(
        bootstrapPlan: RoomGameStartedBootstrapPlan,
        mutation: RoomCoordinatorMutation,
        authorityRelay: RoomAuthorityRelay
    ) throws {
        let roomId = mutation.snapshot.room.roomId
        let roomSequence = mutation.snapshot.room.lastRoomSequence
        let bootstrapPayloadsByPlayerId = try fetchBootstrapPayloadsByPlayerId(
            bootstrapPlan: bootstrapPlan,
            roomSnapshot: mutation.snapshot,
            authorityRelay: authorityRelay
        )
        var resolvedSnapshotsByPlayerId: [String: MultiplayerSnapshot] = [:]
        var resolvedGameStartedByPlayerId: [String: [String: Any]] = [:]

        for request in bootstrapPlan.requestsByPlayerId.values.sorted(by: { $0.viewerPlayerId < $1.viewerPlayerId }) {
            guard let bootstrapPayload = bootstrapPayloadsByPlayerId[request.viewerPlayerId] else {
                continue
            }
            guard let gameStartedPayload = bootstrapPayload["gameStarted"] as? [String: Any] else {
                throw RoomCLIAdapterError.invalidAuthorityPayload("gameStarted")
            }
            guard let stateSnapshotPayload = bootstrapPayload["stateSnapshot"] as? [String: Any] else {
                throw RoomCLIAdapterError.invalidAuthorityPayload("stateSnapshot")
            }
            resolvedGameStartedByPlayerId[request.viewerPlayerId] = gameStartedPayload
            resolvedSnapshotsByPlayerId[request.viewerPlayerId] = try decodeJSONObject(
                MultiplayerSnapshot.self,
                from: stateSnapshotPayload
            )
        }

        guard let sampleSnapshot = resolvedSnapshotsByPlayerId.values.first else {
            return
        }

        let gameStartedEventId = nextGameEventID(for: roomId)
        let stateSnapshotEventId = nextGameEventID(for: roomId)
        for request in bootstrapPlan.requestsByPlayerId.values.sorted(by: { $0.viewerPlayerId < $1.viewerPlayerId }) {
            guard let targetClientId = transportClientID(roomId: roomId, playerId: request.viewerPlayerId),
                  let gameStartedPayload = resolvedGameStartedByPlayerId[request.viewerPlayerId],
                  let stateSnapshot = resolvedSnapshotsByPlayerId[request.viewerPlayerId] else {
                continue
            }
            enqueueGameEvent(
                engineEvent: makeEngineEventEnvelope(
                    traceId: nil,
                    roomId: roomId,
                    gameId: request.gameId,
                    eventId: gameStartedEventId,
                    stateVersion: stateSnapshot.snapshotStateVersion,
                    causedByActionId: nil,
                    eventName: .gameStarted,
                    payload: gameStartedPayload
                ),
                roomId: roomId,
                clientId: targetClientId,
                roomSequence: roomSequence
            )
            enqueueGameEvent(
                engineEvent: makeEngineEventEnvelope(
                    traceId: nil,
                    roomId: roomId,
                    gameId: request.gameId,
                    eventId: stateSnapshotEventId,
                    stateVersion: stateSnapshot.snapshotStateVersion,
                    causedByActionId: nil,
                    eventName: .stateSnapshot,
                    payload: try requireJSONObject(from: stateSnapshot)
                ),
                roomId: roomId,
                clientId: targetClientId,
                roomSequence: roomSequence
            )
        }

        transportGameStates[roomId] = RoomTransportGameState(
            roomId: roomId,
            gameId: sampleSnapshot.state.gameId,
            stateVersion: sampleSnapshot.snapshotStateVersion,
            lastEventOrdinal: parseEventOrdinal(from: stateSnapshotEventId),
            lastEventId: stateSnapshotEventId,
            lastTurnId: sampleSnapshot.state.turnId
        )
    }

    private func enqueueTerminalSummaryEnvelopes(
        terminalPayload: [String: Any],
        terminalRequest: RoomTerminalSummaryRelayRequest,
        mutation: RoomCoordinatorMutation
    ) throws {
        try validateTerminalSummaryPayload(terminalPayload)
        let roundEndedPayload = try requireDictionary("roundEnded", in: terminalPayload)
        let matchEndedPayload = try requireDictionary("matchEnded", in: terminalPayload)
        let roomId = terminalRequest.roomId
        let roundEndedEventId = nextGameEventID(for: roomId)
        let matchEndedEventId = nextGameEventID(for: roomId)
        let roomSequence = mutation.snapshot.room.lastRoomSequence

        broadcastGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: nil,
                roomId: roomId,
                gameId: terminalRequest.gameId,
                eventId: roundEndedEventId,
                stateVersion: terminalRequest.summaryStateVersion,
                causedByActionId: nil,
                eventName: .roundEnded,
                payload: roundEndedPayload
            ),
            roomId: roomId,
            roomSequence: roomSequence
        )
        broadcastGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: nil,
                roomId: roomId,
                gameId: terminalRequest.gameId,
                eventId: matchEndedEventId,
                stateVersion: terminalRequest.summaryStateVersion,
                causedByActionId: nil,
                eventName: .matchEnded,
                payload: matchEndedPayload
            ),
            roomId: roomId,
            roomSequence: roomSequence
        )
        broadcast(
            envelope: makeTransportEnvelope(
                type: "terminalSummary",
                roomId: roomId,
                sessionId: nil,
                roomSequence: roomSequence,
                payload: terminalPayload
            ),
            in: roomId
        )

        transportGameStates[roomId] = RoomTransportGameState(
            roomId: roomId,
            gameId: terminalRequest.gameId,
            stateVersion: terminalRequest.summaryStateVersion,
            lastEventOrdinal: parseEventOrdinal(from: matchEndedEventId),
            lastEventId: matchEndedEventId,
            lastTurnId: transportGameStates[roomId]?.lastTurnId
        )
    }

    private func handleTransportGameplay(
        _ payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        action: String
    ) throws -> [String: Any] {
        let authorityRelay = try requireAuthorityRelay()
        let roomSnapshot = try requireRoomSnapshot(client.roomId)
        guard roomSnapshot.room.roomState == .inGame || roomSnapshot.room.roomState == .ended,
              let gameId = roomSnapshot.room.activeGameId ?? payload.gameId else {
            throw RoomCLIAdapterError.transportGameNotStarted(client.roomId)
        }

        let currentGameState = resolveTransportGameState(
            roomId: client.roomId,
            gameId: gameId,
            fallbackStateVersion: payload.expectedStateVersion ?? 0
        )
        let authorityPlayerMapping = try resolveAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authorityRelay: authorityRelay,
            gameId: gameId,
            fallbackStateVersion: currentGameState.stateVersion,
            lastEventId: currentGameState.lastEventId,
            preferredRoomPlayerId: client.playerId
        )
        let authorityPlayerId = mappedAuthorityPlayerId(
            for: client.playerId,
            authorityPlayerIdByRoomPlayerId: authorityPlayerMapping
        )
        let clientStateVersion = payload.expectedStateVersion ?? currentGameState.stateVersion
        let effectiveExpectedStateVersion = resolvedExpectedStateVersion(
            client: client,
            requestedStateVersion: clientStateVersion
        )
        let fallbackResolvedCommand = provisionalTransportGameplayCommand(
            payload: payload,
            roomPlayerId: client.playerId,
            authorityPlayerId: authorityPlayerId,
            expectedStateVersion: effectiveExpectedStateVersion
        )
        let duplicateActionResolution = try resolveDuplicateTransportAction(
            payload: payload,
            client: client,
            effectiveExpectedStateVersion: effectiveExpectedStateVersion,
            authoritativeStateVersion: currentGameState.stateVersion,
            authoritativeEventId: currentGameState.lastEventId,
            fallbackResolvedCommand: fallbackResolvedCommand,
            action: action
        )
        switch duplicateActionResolution {
        case let .replay(response):
            return response
        case let .fresh(recordContext):
            return try handleFreshTransportGameplay(
                payload,
                client: client,
                action: action,
                roomSnapshot: roomSnapshot,
                authorityRelay: authorityRelay,
                currentGameState: currentGameState,
                clientStateVersion: clientStateVersion,
                effectiveExpectedStateVersion: effectiveExpectedStateVersion,
                authorityPlayerId: authorityPlayerId,
                fallbackResolvedCommand: fallbackResolvedCommand,
                recordContext: recordContext
            )
        }
    }

    private func handleFreshTransportGameplay(
        _ payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        action: String,
        roomSnapshot: RoomCoordinatorSnapshot,
        authorityRelay: RoomAuthorityRelay,
        currentGameState: RoomTransportGameState,
        clientStateVersion: Int,
        effectiveExpectedStateVersion: Int,
        authorityPlayerId: String,
        fallbackResolvedCommand: RoomTransportResolvedGameplayCommand,
        recordContext: RoomTransportActionRecordContext?
    ) throws -> [String: Any] {
        let gameId = roomSnapshot.room.activeGameId ?? payload.gameId ?? currentGameState.gameId
        let resolvedCommand: RoomTransportResolvedGameplayCommand
        do {
            resolvedCommand = try resolveTransportGameplayCommand(
                payload: payload,
                client: client,
                gameState: currentGameState,
                authorityRelay: authorityRelay,
                roomSnapshot: roomSnapshot,
                authorityPlayerId: authorityPlayerId,
                expectedStateVersion: effectiveExpectedStateVersion
            )
        } catch let rejection as RoomAuthorityGameplayRejection {
            let response = try rejectTransportGameplay(
                resolvedCommand: fallbackResolvedCommand,
                client: client,
                rejection: rejection,
                authoritativeStateVersion: currentGameState.stateVersion,
                authoritativeEventId: currentGameState.lastEventId,
                action: action
            )
            return recordedTransportActionResponse(
                response,
                context: recordContext
            )
        }

        if effectiveExpectedStateVersion != currentGameState.stateVersion {
            let response = try rejectTransportGameplayForStaleState(
                resolvedCommand: resolvedCommand,
                client: client,
                roomSnapshot: roomSnapshot,
                authorityRelay: authorityRelay,
                currentGameState: currentGameState,
                clientStateVersion: clientStateVersion,
                effectiveExpectedStateVersion: effectiveExpectedStateVersion,
                action: action
            )
            return recordedTransportActionResponse(
                response,
                context: recordContext
            )
        }

        do {
            if resolvedCommand.commandName == .quit {
                let response = try handleTransportQuitCommand(
                    resolvedCommand,
                    client: client,
                    roomSnapshot: roomSnapshot,
                    currentGameState: currentGameState,
                    authorityRelay: authorityRelay,
                    action: action
                )
                return recordedTransportActionResponse(
                    response,
                    context: recordContext
                )
            }

            let beforeSnapshotsByPlayerId = try fetchProjectionSnapshotsByPlayerId(
                authorityRelay: authorityRelay,
                roomSnapshot: roomSnapshot,
                gameState: currentGameState,
                snapshotReason: .localPreview
            )
            let execution = try authorityRelay.executeGameplayCommand(
                RoomAuthorityGameplayExecutionRequest(
                    playerId: resolvedCommand.authorityPlayerId,
                    commandName: resolvedCommand.commandName,
                    commandPayload: resolvedCommand.commandPayload
                )
            )

            var nextGameState = currentGameState
            nextGameState.stateVersion = currentGameState.stateVersion + 1
            let afterRoomSnapshot = try requireRoomSnapshot(client.roomId)
            let afterSnapshotsByPlayerId = try fetchProjectionSnapshotsByPlayerId(
                authorityRelay: authorityRelay,
                roomSnapshot: afterRoomSnapshot,
                gameState: nextGameState,
                snapshotReason: .localPreview
            )

            let actionAcceptedEventId = nextGameEventID(for: client.roomId)
            broadcastGameEvent(
                engineEvent: makeEngineEventEnvelope(
                    traceId: resolvedCommand.traceId,
                    roomId: client.roomId,
                    gameId: gameId,
                    eventId: actionAcceptedEventId,
                    stateVersion: nextGameState.stateVersion,
                    causedByActionId: resolvedCommand.actionId,
                    eventName: .actionAccepted,
                    payload: try requireJSONObject(
                        from: MultiplayerActionAcceptedPayload(
                            requestId: resolvedCommand.requestId,
                            actionId: resolvedCommand.actionId,
                            playerId: resolvedCommand.authorityPlayerId,
                            commandName: resolvedCommand.commandName,
                            result: execution.result.mapValues(AnyCodable.init)
                        )
                    )
                ),
                roomId: client.roomId,
                roomSequence: afterRoomSnapshot.room.lastRoomSequence
            )

            let statePatchedEventId = nextGameEventID(for: client.roomId)
            for member in afterRoomSnapshot.room.members.sorted(by: { $0.seat < $1.seat }) {
                guard let targetClientId = transportClientID(roomId: client.roomId, playerId: member.playerId),
                      let beforeSnapshot = beforeSnapshotsByPlayerId[member.playerId],
                      let afterSnapshot = afterSnapshotsByPlayerId[member.playerId] else {
                    continue
                }
                let patchPayload = try makeStatePatchPayload(
                    from: beforeSnapshot.state,
                    to: afterSnapshot.state,
                    baseStateVersion: currentGameState.stateVersion,
                    targetStateVersion: nextGameState.stateVersion
                )
                enqueueGameEvent(
                    engineEvent: makeEngineEventEnvelope(
                        traceId: resolvedCommand.traceId,
                        roomId: client.roomId,
                        gameId: gameId,
                        eventId: statePatchedEventId,
                        stateVersion: nextGameState.stateVersion,
                        causedByActionId: resolvedCommand.actionId,
                        eventName: .statePatched,
                        payload: patchPayload
                    ),
                    roomId: client.roomId,
                    clientId: targetClientId,
                    roomSequence: afterRoomSnapshot.room.lastRoomSequence
                )
            }

            var lastEventId = statePatchedEventId
            let sampleAfterSnapshot = afterSnapshotsByPlayerId[client.playerId] ?? afterSnapshotsByPlayerId.values.first
            if let sampleAfterSnapshot,
               sampleAfterSnapshot.state.phase == .matchEnded {
                let roundEndedEventId = nextGameEventID(for: client.roomId)
                let matchEndedEventId = nextGameEventID(for: client.roomId)
                let matchEndedMutation = try coordinator.recordMatchEnded(
                    RecordMatchEndedRequest(
                        roomId: client.roomId,
                        roundIndex: sampleAfterSnapshot.state.scoreboard.roundIndex,
                        quitReason: nil,
                        forfeitingPlayerId: nil,
                        summaryStateVersion: nextGameState.stateVersion,
                        lastEventId: matchEndedEventId,
                        resultRetentionAt: nil
                    )
                )
                let terminalRequest =
                    matchEndedMutation.metadata.terminalSummaryRelayRequest ??
                    makeTerminalSummaryRelayRequest(
                        from: matchEndedMutation.snapshot,
                        roundIndex: sampleAfterSnapshot.state.scoreboard.roundIndex,
                        quitReason: nil,
                        forfeitingPlayerId: nil,
                        summaryStateVersion: nextGameState.stateVersion,
                        lastEventId: matchEndedEventId
                    )
                guard let terminalRequest else {
                    throw RoomCLIAdapterError.invalidAuthorityPayload("terminalSummaryRelayRequest")
                }
                let (_, terminalPayload) = try fetchTerminalSummaryPayload(
                    authorityRelay: authorityRelay,
                    roomSnapshot: matchEndedMutation.snapshot,
                    terminalRequest: terminalRequest
                )
                let roundEndedPayload = try requireDictionary("roundEnded", in: terminalPayload)
                let matchEndedPayload = try requireDictionary("matchEnded", in: terminalPayload)

                broadcastGameEvent(
                    engineEvent: makeEngineEventEnvelope(
                        traceId: resolvedCommand.traceId,
                        roomId: client.roomId,
                        gameId: gameId,
                        eventId: roundEndedEventId,
                        stateVersion: nextGameState.stateVersion,
                        causedByActionId: resolvedCommand.actionId,
                        eventName: .roundEnded,
                        payload: roundEndedPayload
                    ),
                    roomId: client.roomId,
                    roomSequence: afterRoomSnapshot.room.lastRoomSequence
                )
                broadcastGameEvent(
                    engineEvent: makeEngineEventEnvelope(
                        traceId: resolvedCommand.traceId,
                        roomId: client.roomId,
                        gameId: gameId,
                        eventId: matchEndedEventId,
                        stateVersion: nextGameState.stateVersion,
                        causedByActionId: resolvedCommand.actionId,
                        eventName: .matchEnded,
                        payload: matchEndedPayload
                    ),
                    roomId: client.roomId,
                    roomSequence: afterRoomSnapshot.room.lastRoomSequence
                )
                broadcastRoomEvents(matchEndedMutation.events, in: client.roomId)
                broadcast(
                    envelope: makeTransportEnvelope(
                        type: "terminalSummary",
                        roomId: client.roomId,
                        sessionId: nil,
                        roomSequence: matchEndedMutation.snapshot.room.lastRoomSequence,
                        payload: terminalPayload
                    ),
                    in: client.roomId
                )
                lastEventId = matchEndedEventId
            } else {
                let turnChangedPayload = makeTurnChangedPayload(
                    before: beforeSnapshotsByPlayerId[client.playerId],
                    after: afterSnapshotsByPlayerId[client.playerId]
                )
                if let turnChangedPayload {
                    let turnChangedEventId = nextGameEventID(for: client.roomId)
                    broadcastGameEvent(
                        engineEvent: makeEngineEventEnvelope(
                            traceId: resolvedCommand.traceId,
                            roomId: client.roomId,
                            gameId: gameId,
                            eventId: turnChangedEventId,
                            stateVersion: nextGameState.stateVersion,
                            causedByActionId: resolvedCommand.actionId,
                            eventName: .turnChanged,
                            payload: turnChangedPayload
                        ),
                        roomId: client.roomId,
                        roomSequence: afterRoomSnapshot.room.lastRoomSequence
                    )
                    lastEventId = turnChangedEventId
                }

                if afterSnapshotsByPlayerId.values.contains(where: { $0.state.pendingChoice != nil }) {
                    let choiceRequestedEventId = nextGameEventID(for: client.roomId)
                    for member in afterRoomSnapshot.room.members.sorted(by: { $0.seat < $1.seat }) {
                        guard let targetClientId = transportClientID(roomId: client.roomId, playerId: member.playerId),
                              let choice = afterSnapshotsByPlayerId[member.playerId]?.state.pendingChoice else {
                            continue
                        }
                        enqueueGameEvent(
                            engineEvent: makeEngineEventEnvelope(
                                traceId: resolvedCommand.traceId,
                                roomId: client.roomId,
                                gameId: gameId,
                                eventId: choiceRequestedEventId,
                                stateVersion: nextGameState.stateVersion,
                                causedByActionId: resolvedCommand.actionId,
                                eventName: .choiceRequested,
                                payload: try requireJSONObject(from: choice)
                            ),
                            roomId: client.roomId,
                            clientId: targetClientId,
                            roomSequence: afterRoomSnapshot.room.lastRoomSequence
                        )
                    }
                    lastEventId = choiceRequestedEventId
                }
            }

            nextGameState.lastEventId = lastEventId
            nextGameState.lastTurnId = sampleAfterSnapshot?.state.turnId
            transportGameStates[client.roomId] = nextGameState

            let response = success(
                action: action,
                data: [
                    "transportAction": payload.action,
                    "requestId": resolvedCommand.requestId,
                    "actionId": resolvedCommand.actionId,
                    "commandName": resolvedCommand.commandName.rawValue,
                    "authoritativeStateVersion": nextGameState.stateVersion,
                    "authoritativeEventId": nextGameState.lastEventId ?? NSNull(),
                    "queuedEnvelopeCount": transportMailboxes[payload.clientId]?.count ?? 0,
                ]
            )
            return recordedTransportActionResponse(
                response,
                context: recordContext
            )
        } catch let rejection as RoomAuthorityGameplayRejection {
            let response = try rejectTransportGameplay(
                resolvedCommand: resolvedCommand,
                client: client,
                rejection: rejection,
                authoritativeStateVersion: currentGameState.stateVersion,
                authoritativeEventId: currentGameState.lastEventId,
                action: action
            )
            return recordedTransportActionResponse(
                response,
                context: recordContext
            )
        }
    }

    private func handleTransportQuitCommand(
        _ resolvedCommand: RoomTransportResolvedGameplayCommand,
        client: RoomTransportClientState,
        roomSnapshot: RoomCoordinatorSnapshot,
        currentGameState: RoomTransportGameState,
        authorityRelay: RoomAuthorityRelay,
        action: String
    ) throws -> [String: Any] {
        let quitReasonRaw = (resolvedCommand.commandPayload["reason"] as? String) ?? MultiplayerQuitReason.voluntaryExit.rawValue
        let mutation = try coordinator.recordMatchEnded(
            RecordMatchEndedRequest(
                roomId: client.roomId,
                roundIndex: 1,
                quitReason: quitReasonRaw,
                forfeitingPlayerId: client.playerId,
                summaryStateVersion: currentGameState.stateVersion + 1,
                lastEventId: currentGameState.lastEventId,
                resultRetentionAt: nil
            )
        )
        let relayResult = try relayTransportQuitCommand(
            resolvedCommand: resolvedCommand,
            currentGameState: currentGameState,
            authorityRelay: authorityRelay,
            mutation: mutation
        )

        return success(
            action: action,
            data: [
                "transportAction": "quit",
                "requestId": resolvedCommand.requestId,
                "actionId": resolvedCommand.actionId,
                "commandName": MultiplayerCommandName.quit.rawValue,
                "mutation": mutationResponse(relayResult.mutation),
                "authoritativeStateVersion": relayResult.nextGameState.stateVersion,
                "authoritativeEventId": relayResult.nextGameState.lastEventId ?? NSNull(),
                "queuedEnvelopeCount": transportMailboxes[client.clientId]?.count ?? 0,
            ]
        )
    }

    private func relayExpiredTransportMutations(
        _ mutations: [RoomCoordinatorMutation],
        initiatedByClientId: String?,
        traceId: String?
    ) throws {
        let authorityRelay = self.authorityRelay
        for mutation in mutations {
            if let timedOutPlayerId = disconnectTimeoutForfeitingPlayerId(in: mutation),
               let authorityRelay {
                try relayDisconnectTimeoutMutation(
                    mutation,
                    forfeitingPlayerId: timedOutPlayerId,
                    traceId: traceId,
                    authorityRelay: authorityRelay
                )
                continue
            }
            broadcastRoomEvents(mutation.events, in: mutation.snapshot.room.roomId)
        }
        if let initiatedByClientId,
           transportMailboxes[initiatedByClientId] == nil {
            transportMailboxes[initiatedByClientId] = []
        }
    }

    private func handleTransportGapRecovery(
        _ payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        action: String
    ) throws -> [String: Any] {
        // Shipped Phase 0 live recovery path: gapRecoveryHint -> stateSnapshot(reason=gapDetected).
        let authorityRelay = try requireAuthorityRelay()
        let roomSnapshot = try requireRoomSnapshot(client.roomId)
        guard let session = roomSnapshot.sessions.first(where: { $0.sessionId == client.sessionId }) else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("roomSession")
        }
        guard let gameId = roomSnapshot.room.activeGameId ?? transportGameStates[client.roomId]?.gameId else {
            throw RoomCLIAdapterError.transportGameNotStarted(client.roomId)
        }

        let currentGameState = resolveTransportGameState(
            roomId: client.roomId,
            gameId: gameId,
            fallbackStateVersion: max(session.lastSeenStateVersion ?? 0, payload.expectedStateVersion ?? 0)
        )
        let gapSnapshot = try fetchProjectionSnapshot(
            authorityRelay: authorityRelay,
            roomSnapshot: roomSnapshot,
            viewerPlayerId: client.playerId,
            gameState: currentGameState,
            snapshotReason: .gapDetected
        )
        let snapshotEventId = nextGameEventID(for: client.roomId)
        let lastAckedGameEventId = payload.lastEventId
            ?? payload.lastSeen?.gameEventId
            ?? session.lastAckedGameEventId
        let lastSeenStateVersion = payload.expectedStateVersion
            ?? payload.lastSeen?.stateVersion
            ?? session.lastSeenStateVersion
            ?? currentGameState.stateVersion
        let gapRecoveryHint = makeGapRecoveryHintPayload(
            client: client,
            session: session,
            snapshotEventId: snapshotEventId,
            authoritativeStateVersion: gapSnapshot.snapshotStateVersion,
            lastAckedGameEventId: lastAckedGameEventId,
            lastSeenStateVersion: lastSeenStateVersion
        )

        enqueue(
            envelope: makeTransportEnvelope(
                type: "gapRecoveryHint",
                roomId: client.roomId,
                sessionId: client.sessionId,
                roomSequence: roomSnapshot.room.lastRoomSequence,
                payload: gapRecoveryHint
            ),
            for: client.clientId
        )
        enqueueGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: payload.traceId,
                roomId: client.roomId,
                gameId: gameId,
                eventId: snapshotEventId,
                stateVersion: gapSnapshot.snapshotStateVersion,
                causedByActionId: payload.actionId,
                eventName: .stateSnapshot,
                payload: try requireJSONObject(from: gapSnapshot)
            ),
            roomId: client.roomId,
            clientId: client.clientId,
            roomSequence: roomSnapshot.room.lastRoomSequence
        )

        transportGameStates[client.roomId] = RoomTransportGameState(
            roomId: client.roomId,
            gameId: gameId,
            stateVersion: gapSnapshot.snapshotStateVersion,
            lastEventOrdinal: parseEventOrdinal(from: snapshotEventId),
            lastEventId: snapshotEventId,
            lastTurnId: gapSnapshot.state.turnId
        )

        return success(
            action: action,
            data: [
                "transportAction": payload.action,
                "gapRecoveryHint": gapRecoveryHint,
                "authoritativeStateVersion": gapSnapshot.snapshotStateVersion,
                "authoritativeEventId": snapshotEventId,
                "queuedEnvelopeCount": transportMailboxes[client.clientId]?.count ?? 0,
            ]
        )
    }

    private func disconnectTimeoutForfeitingPlayerId(
        in mutation: RoomCoordinatorMutation
    ) -> String? {
        for event in mutation.events {
            if case let .playerForfeited(playerId, reason) = event.payload,
               reason == .disconnectTimeout {
                return playerId
            }
        }
        return nil
    }

    private func relayDisconnectTimeoutMutation(
        _ mutation: RoomCoordinatorMutation,
        forfeitingPlayerId: String,
        traceId: String?,
        authorityRelay: RoomAuthorityRelay
    ) throws {
        guard let gameId = mutation.snapshot.room.activeGameId ?? transportGameStates[mutation.snapshot.room.roomId]?.gameId else {
            broadcastRoomEvents(mutation.events, in: mutation.snapshot.room.roomId)
            return
        }

        let currentGameState = resolveTransportGameState(
            roomId: mutation.snapshot.room.roomId,
            gameId: gameId,
            fallbackStateVersion: transportGameStates[mutation.snapshot.room.roomId]?.stateVersion ?? 0
        )
        let mapping = try resolveAuthorityPlayerIdMapping(
            roomSnapshot: mutation.snapshot,
            authorityRelay: authorityRelay,
            gameId: gameId,
            fallbackStateVersion: currentGameState.stateVersion,
            lastEventId: currentGameState.lastEventId,
            preferredRoomPlayerId: forfeitingPlayerId
        )
        let authorityPlayerId = mappedAuthorityPlayerId(
            for: forfeitingPlayerId,
            authorityPlayerIdByRoomPlayerId: mapping
        )
        let nextOrdinal = currentGameState.lastEventOrdinal + 1
        let resolvedCommand = RoomTransportResolvedGameplayCommand(
            requestId: "req_timeout_\(mutation.snapshot.room.roomId)_\(forfeitingPlayerId)_\(nextOrdinal)",
            traceId: traceId,
            actionId: "act_timeout_\(mutation.snapshot.room.roomId)_\(forfeitingPlayerId)_\(nextOrdinal)",
            roomPlayerId: forfeitingPlayerId,
            authorityPlayerId: authorityPlayerId,
            expectedStateVersion: currentGameState.stateVersion,
            commandName: .quit,
            commandPayload: ["reason": MultiplayerQuitReason.disconnectTimeout.rawValue]
        )
        _ = try relayTransportQuitCommand(
            resolvedCommand: resolvedCommand,
            currentGameState: currentGameState,
            authorityRelay: authorityRelay,
            mutation: mutation
        )
    }

    private struct RelayedTransportQuitResult {
        var mutation: RoomCoordinatorMutation
        var nextGameState: RoomTransportGameState
        var executionResult: [String: Any]
    }

    private func relayTransportQuitCommand(
        resolvedCommand: RoomTransportResolvedGameplayCommand,
        currentGameState: RoomTransportGameState,
        authorityRelay: RoomAuthorityRelay,
        mutation: RoomCoordinatorMutation
    ) throws -> RelayedTransportQuitResult {
        let roomId = mutation.snapshot.room.roomId
        let gameId = mutation.snapshot.room.activeGameId ?? currentGameState.gameId
        let nextStateVersion = currentGameState.stateVersion + 1
        let actionAcceptedEventId = nextGameEventID(for: roomId)
        let roundEndedEventId = nextGameEventID(for: roomId)
        let matchEndedEventId = nextGameEventID(for: roomId)
        let quitReasonRaw = (resolvedCommand.commandPayload["reason"] as? String) ?? MultiplayerQuitReason.voluntaryExit.rawValue

        let execution = try authorityRelay.executeGameplayCommand(
            RoomAuthorityGameplayExecutionRequest(
                playerId: resolvedCommand.authorityPlayerId,
                commandName: .quit,
                commandPayload: resolvedCommand.commandPayload
            )
        )

        let terminalRequest =
            mutation.metadata.terminalSummaryRelayRequest ??
            makeTerminalSummaryRelayRequest(
                from: mutation.snapshot,
                roundIndex: 1,
                quitReason: quitReasonRaw,
                forfeitingPlayerId: resolvedCommand.roomPlayerId,
                summaryStateVersion: nextStateVersion,
                lastEventId: matchEndedEventId
            )
        guard let terminalRequest else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("terminalSummaryRelayRequest")
        }
        let (_, terminalPayload) = try fetchTerminalSummaryPayload(
            authorityRelay: authorityRelay,
            roomSnapshot: mutation.snapshot,
            terminalRequest: terminalRequest
        )
        let roundEndedPayload = try requireDictionary("roundEnded", in: terminalPayload)
        let matchEndedPayload = try requireDictionary("matchEnded", in: terminalPayload)

        broadcastGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: resolvedCommand.traceId,
                roomId: roomId,
                gameId: gameId,
                eventId: actionAcceptedEventId,
                stateVersion: nextStateVersion,
                causedByActionId: resolvedCommand.actionId,
                eventName: .actionAccepted,
                payload: try requireJSONObject(
                    from: MultiplayerActionAcceptedPayload(
                        requestId: resolvedCommand.requestId,
                        actionId: resolvedCommand.actionId,
                        playerId: resolvedCommand.authorityPlayerId,
                        commandName: .quit,
                        result: execution.result.mapValues(AnyCodable.init)
                    )
                )
            ),
            roomId: roomId,
            roomSequence: mutation.snapshot.room.lastRoomSequence
        )
        broadcastGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: resolvedCommand.traceId,
                roomId: roomId,
                gameId: gameId,
                eventId: roundEndedEventId,
                stateVersion: nextStateVersion,
                causedByActionId: resolvedCommand.actionId,
                eventName: .roundEnded,
                payload: roundEndedPayload
            ),
            roomId: roomId,
            roomSequence: mutation.snapshot.room.lastRoomSequence
        )
        broadcastGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: resolvedCommand.traceId,
                roomId: roomId,
                gameId: gameId,
                eventId: matchEndedEventId,
                stateVersion: nextStateVersion,
                causedByActionId: resolvedCommand.actionId,
                eventName: .matchEnded,
                payload: matchEndedPayload
            ),
            roomId: roomId,
            roomSequence: mutation.snapshot.room.lastRoomSequence
        )
        broadcastRoomEvents(mutation.events, in: roomId)
        broadcast(
            envelope: makeTransportEnvelope(
                type: "terminalSummary",
                roomId: roomId,
                sessionId: nil,
                roomSequence: mutation.snapshot.room.lastRoomSequence,
                payload: terminalPayload
            ),
            in: roomId
        )

        let nextGameState = RoomTransportGameState(
            roomId: roomId,
            gameId: gameId,
            stateVersion: nextStateVersion,
            lastEventOrdinal: parseEventOrdinal(from: matchEndedEventId),
            lastEventId: matchEndedEventId,
            lastTurnId: currentGameState.lastTurnId
        )
        transportGameStates[roomId] = nextGameState
        return RelayedTransportQuitResult(
            mutation: mutation,
            nextGameState: nextGameState,
            executionResult: execution.result
        )
    }

    private func rejectTransportGameplay(
        resolvedCommand: RoomTransportResolvedGameplayCommand,
        client: RoomTransportClientState,
        rejection: RoomAuthorityGameplayRejection,
        authoritativeStateVersion: Int,
        authoritativeEventId: String?,
        action: String
    ) throws -> [String: Any] {
        let rejectEventId = nextGameEventID(for: client.roomId)
        let engineEvent = makeEngineEventEnvelope(
            traceId: resolvedCommand.traceId,
            roomId: client.roomId,
            gameId: transportGameStates[client.roomId]?.gameId,
            eventId: rejectEventId,
            stateVersion: authoritativeStateVersion,
            causedByActionId: resolvedCommand.actionId,
            eventName: .actionRejected,
            payload: try requireJSONObject(
                from: MultiplayerActionRejectedPayload(
                    requestId: resolvedCommand.requestId,
                    actionId: resolvedCommand.actionId,
                    playerId: resolvedCommand.authorityPlayerId,
                    commandName: resolvedCommand.commandName,
                    rejectReason: MultiplayerRejectReason(
                        code: rejection.code,
                        retryable: rejection.retryable,
                        messageKey: rejection.messageKey,
                        details: rejectionDetails(
                            code: rejection.code,
                            authoritativeStateVersion: authoritativeStateVersion,
                            authoritativeEventId: authoritativeEventId,
                            clientStateVersion: resolvedCommand.expectedStateVersion,
                            effectiveExpectedStateVersion: resolvedCommand.expectedStateVersion,
                            injectedMismatchMode: nil,
                            recoverySnapshotId: nil
                        )
                    )
                )
            )
        )
        enqueueGameEvent(
            engineEvent: engineEvent,
            roomId: client.roomId,
            clientId: client.clientId,
            roomSequence: coordinator.snapshot(for: client.roomId)?.room.lastRoomSequence
        )

        if var gameState = transportGameStates[client.roomId] {
            gameState.lastEventId = rejectEventId
            gameState.lastEventOrdinal = parseEventOrdinal(from: rejectEventId)
            transportGameStates[client.roomId] = gameState
        }

        return success(
            action: action,
            data: [
                "transportAction": resolvedCommand.commandName.rawValue,
                "requestId": resolvedCommand.requestId,
                "actionId": resolvedCommand.actionId,
                "commandName": resolvedCommand.commandName.rawValue,
                "authoritativeStateVersion": authoritativeStateVersion,
                "authoritativeEventId": rejectEventId,
                "queuedEnvelopeCount": transportMailboxes[client.clientId]?.count ?? 0,
            ]
        )
    }

    private func rejectTransportGameplayForStaleState(
        resolvedCommand: RoomTransportResolvedGameplayCommand,
        client: RoomTransportClientState,
        roomSnapshot: RoomCoordinatorSnapshot,
        authorityRelay: RoomAuthorityRelay,
        currentGameState: RoomTransportGameState,
        clientStateVersion: Int,
        effectiveExpectedStateVersion: Int,
        action: String
    ) throws -> [String: Any] {
        let rejectEventId = nextGameEventID(for: client.roomId)
        let injectedMismatchMode = deterministicFaultHook?.targetSessionId == client.sessionId
            ? deterministicFaultHook?.kind.rawValue
            : nil
        let resyncSnapshot = try fetchProjectionSnapshot(
            authorityRelay: authorityRelay,
            roomSnapshot: roomSnapshot,
            viewerPlayerId: client.playerId,
            gameState: currentGameState,
            snapshotReason: .resync,
            lastEventIdOverride: rejectEventId
        )
        let rejectPayload = MultiplayerActionRejectedPayload(
            requestId: resolvedCommand.requestId,
            actionId: resolvedCommand.actionId,
            playerId: resolvedCommand.authorityPlayerId,
            commandName: resolvedCommand.commandName,
            rejectReason: MultiplayerRejectReason(
                code: .staleStateVersion,
                retryable: true,
                messageKey: "multiplayer.reject.stale_state_version",
                details: rejectionDetails(
                    code: .staleStateVersion,
                    authoritativeStateVersion: currentGameState.stateVersion,
                    authoritativeEventId: currentGameState.lastEventId,
                    clientStateVersion: clientStateVersion,
                    effectiveExpectedStateVersion: effectiveExpectedStateVersion,
                    injectedMismatchMode: injectedMismatchMode,
                    recoverySnapshotId: resyncSnapshot.snapshotId
                )
            )
        )
        enqueueGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: resolvedCommand.traceId,
                roomId: client.roomId,
                gameId: currentGameState.gameId,
                eventId: rejectEventId,
                stateVersion: currentGameState.stateVersion,
                causedByActionId: resolvedCommand.actionId,
                eventName: .actionRejected,
                payload: try requireJSONObject(from: rejectPayload)
            ),
            roomId: client.roomId,
            clientId: client.clientId,
            roomSequence: roomSnapshot.room.lastRoomSequence
        )

        let snapshotEventId = nextGameEventID(for: client.roomId)
        enqueueGameEvent(
            engineEvent: makeEngineEventEnvelope(
                traceId: resolvedCommand.traceId,
                roomId: client.roomId,
                gameId: currentGameState.gameId,
                eventId: snapshotEventId,
                stateVersion: currentGameState.stateVersion,
                causedByActionId: resolvedCommand.actionId,
                eventName: .stateSnapshot,
                payload: try requireJSONObject(from: resyncSnapshot)
            ),
            roomId: client.roomId,
            clientId: client.clientId,
            roomSequence: roomSnapshot.room.lastRoomSequence
        )

        var nextState = currentGameState
        nextState.lastEventId = snapshotEventId
        nextState.lastEventOrdinal = parseEventOrdinal(from: snapshotEventId)
        nextState.lastTurnId = resyncSnapshot.state.turnId
        transportGameStates[client.roomId] = nextState

        return success(
            action: action,
            data: [
                "transportAction": payloadName(for: resolvedCommand.commandName),
                "requestId": resolvedCommand.requestId,
                "actionId": resolvedCommand.actionId,
                "commandName": resolvedCommand.commandName.rawValue,
                "authoritativeStateVersion": currentGameState.stateVersion,
                "authoritativeEventId": snapshotEventId,
                "queuedEnvelopeCount": transportMailboxes[client.clientId]?.count ?? 0,
            ]
        )
    }

    private func resolveTransportGameplayCommand(
        payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        gameState: RoomTransportGameState,
        authorityRelay: RoomAuthorityRelay,
        roomSnapshot: RoomCoordinatorSnapshot,
        authorityPlayerId: String,
        expectedStateVersion: Int
    ) throws -> RoomTransportResolvedGameplayCommand {
        let commandPayload = TestControlSupport.unbox(payload.commandPayload) ?? [:]
        let requestId = payload.requestId ?? "req_\(payload.action)_\(gameState.stateVersion)_\(client.playerId)"
        let actionId = payload.actionId ?? "act_\(payload.action)_\(gameState.stateVersion)_\(client.playerId)"

        let snapshot = try fetchProjectionSnapshot(
            authorityRelay: authorityRelay,
            roomSnapshot: roomSnapshot,
            viewerPlayerId: client.playerId,
            gameState: gameState,
            snapshotReason: .localPreview
        )

        switch payload.action {
        case "playCard":
            guard snapshot.state.phase == .inTurn else {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidPhase,
                    retryable: true,
                    messageKey: "multiplayer.reject.invalid_phase"
                )
            }
            guard snapshot.state.currentPlayerId == authorityPlayerId else {
                throw RoomAuthorityGameplayRejection(
                    code: .outOfTurn,
                    retryable: true,
                    messageKey: "multiplayer.reject.out_of_turn"
                )
            }
            guard let cardId = commandPayload["cardId"] as? String,
                  let player = snapshot.state.players.first(where: { $0.playerId == authorityPlayerId }),
                  player.hand?.contains(where: { $0.cardId == cardId }) == true else {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidCard,
                    retryable: true,
                    messageKey: "multiplayer.reject.invalid_card"
                )
            }
            return RoomTransportResolvedGameplayCommand(
                requestId: requestId,
                traceId: payload.traceId,
                actionId: actionId,
                roomPlayerId: client.playerId,
                authorityPlayerId: authorityPlayerId,
                expectedStateVersion: expectedStateVersion,
                commandName: .playCard,
                commandPayload: [
                    "cardId": cardId,
                    "source": commandPayload["source"] as? String ?? "hand",
                ]
            )
        case "submitChoice":
            guard snapshot.state.phase == .choicePending,
                  let pendingChoice = snapshot.state.pendingChoice else {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidPhase,
                    retryable: true,
                    messageKey: "multiplayer.reject.invalid_phase"
                )
            }
            guard pendingChoice.actorPlayerId == authorityPlayerId else {
                throw RoomAuthorityGameplayRejection(
                    code: .choiceOwnerMismatch,
                    retryable: true,
                    messageKey: "multiplayer.reject.choice_owner_mismatch"
                )
            }
            guard let choiceId = commandPayload["choiceId"] as? String,
                  choiceId == pendingChoice.choiceId,
                  let optionCode = commandPayload["optionCode"] as? String,
                  let option = pendingChoice.options.first(where: { $0.optionCode == optionCode }) else {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidChoice,
                    retryable: true,
                    messageKey: "multiplayer.reject.invalid_choice"
                )
            }

            let resolvedName = choiceCommandName(for: pendingChoice.choiceKind)
            if let requestedCommandName = (commandPayload["choiceCommandName"] as? String)
                .flatMap(MultiplayerCommandName.init(rawValue:)),
               requestedCommandName != resolvedName {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidChoice,
                    retryable: false,
                    messageKey: "multiplayer.reject.invalid_choice"
                )
            }

            var executionPayload: [String: Any] = [
                "choiceId": choiceId,
                "optionCode": optionCode,
            ]
            if resolvedName == .selectCapture {
                executionPayload["cardId"] = optionCode
            }
            if resolvedName == .selectShake,
               let month = option.metadata?["month"]?.value as? Int {
                executionPayload["month"] = month
            }
            return RoomTransportResolvedGameplayCommand(
                requestId: requestId,
                traceId: payload.traceId,
                actionId: actionId,
                roomPlayerId: client.playerId,
                authorityPlayerId: authorityPlayerId,
                expectedStateVersion: expectedStateVersion,
                commandName: resolvedName,
                commandPayload: executionPayload
            )
        case "quit":
            let quitReason = (commandPayload["reason"] as? String) ?? MultiplayerQuitReason.voluntaryExit.rawValue
            guard MultiplayerQuitReason(rawValue: quitReason) != nil else {
                throw RoomAuthorityGameplayRejection(
                    code: .invalidState,
                    retryable: false,
                    messageKey: "multiplayer.reject.invalid_state"
                )
            }
            return RoomTransportResolvedGameplayCommand(
                requestId: requestId,
                traceId: payload.traceId,
                actionId: actionId,
                roomPlayerId: client.playerId,
                authorityPlayerId: authorityPlayerId,
                expectedStateVersion: expectedStateVersion,
                commandName: .quit,
                commandPayload: ["reason": quitReason]
            )
        default:
            throw RoomCLIAdapterError.unsupportedTransportAction(payload.action)
        }
    }

    private func fetchProjectionSnapshotsByPlayerId(
        authorityRelay: RoomAuthorityRelay,
        roomSnapshot: RoomCoordinatorSnapshot,
        gameState: RoomTransportGameState,
        snapshotReason: MultiplayerSnapshotReason
    ) throws -> [String: MultiplayerSnapshot] {
        var snapshotsByPlayerId: [String: MultiplayerSnapshot] = [:]
        for member in roomSnapshot.room.members {
            snapshotsByPlayerId[member.playerId] = try fetchProjectionSnapshot(
                authorityRelay: authorityRelay,
                roomSnapshot: roomSnapshot,
                viewerPlayerId: member.playerId,
                gameState: gameState,
                snapshotReason: snapshotReason
            )
        }
        return snapshotsByPlayerId
    }

    private func fetchBootstrapPayloadsByPlayerId(
        bootstrapPlan: RoomGameStartedBootstrapPlan,
        roomSnapshot: RoomCoordinatorSnapshot,
        authorityRelay: RoomAuthorityRelay
    ) throws -> [String: [String: Any]] {
        guard let seedRequest = bootstrapPlan.requestsByPlayerId.values.sorted(by: { $0.viewerPlayerId < $1.viewerPlayerId }).first else {
            return [:]
        }
        let mapping = try resolveAuthorityPlayerIdMappingForBootstrap(
            roomSnapshot: roomSnapshot,
            bootstrapRequest: seedRequest,
            authorityRelay: authorityRelay
        )

        return try Dictionary(
            uniqueKeysWithValues: bootstrapPlan.requestsByPlayerId.values.map { request in
                var mappedRequest = request
                mappedRequest.authorityPlayerIdByRoomPlayerId = mapping
                let payload = authorityRelay.fetchGameStartedBootstrap(mappedRequest)
                if let stateSnapshotPayload = payload["stateSnapshot"] as? [String: Any] {
                    let snapshot = try decodeJSONObject(MultiplayerSnapshot.self, from: stateSnapshotPayload)
                    try refreshAuthorityPlayerIdMapping(roomSnapshot: roomSnapshot, authoritySnapshot: snapshot)
                }
                return (request.viewerPlayerId, payload)
            }
        )
    }

    private func resolveAuthorityPlayerIdMappingForBootstrap(
        roomSnapshot: RoomCoordinatorSnapshot,
        bootstrapRequest: RoomGameStartedBootstrapRequest,
        authorityRelay: RoomAuthorityRelay
    ) throws -> [String: String] {
        if let existing = authorityPlayerIdByRoomId[roomSnapshot.room.roomId],
           mapping(existing, covers: roomSnapshot) {
            return existing
        }

        var probeRequest = bootstrapRequest
        probeRequest.authorityPlayerIdByRoomPlayerId = nil
        let payload = authorityRelay.fetchGameStartedBootstrap(probeRequest)
        guard let stateSnapshotPayload = payload["stateSnapshot"] as? [String: Any] else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("stateSnapshot")
        }
        let authoritySnapshot = try decodeJSONObject(MultiplayerSnapshot.self, from: stateSnapshotPayload)
        return try refreshAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authoritySnapshot: authoritySnapshot
        )
    }

    private func mappedProjectionPreviewRequest(
        _ request: RoomProjectionPreviewRequest,
        roomSnapshot: RoomCoordinatorSnapshot,
        gameState: RoomTransportGameState,
        authorityRelay: RoomAuthorityRelay,
        preferredRoomPlayerId: String
    ) throws -> RoomProjectionPreviewRequest {
        let mapping = try resolveAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authorityRelay: authorityRelay,
            gameId: gameState.gameId,
            fallbackStateVersion: gameState.stateVersion,
            lastEventId: gameState.lastEventId,
            preferredRoomPlayerId: preferredRoomPlayerId
        )
        var mappedRequest = request
        mappedRequest.authorityPlayerIdByRoomPlayerId = mapping
        return mappedRequest
    }

    private func fetchTerminalSummaryPayload(
        authorityRelay: RoomAuthorityRelay,
        roomSnapshot: RoomCoordinatorSnapshot,
        terminalRequest: RoomTerminalSummaryRelayRequest
    ) throws -> (RoomTerminalSummaryRelayRequest, [String: Any]) {
        let mapping = try resolveAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authorityRelay: authorityRelay,
            gameId: terminalRequest.gameId,
            fallbackStateVersion: terminalRequest.summaryStateVersion,
            lastEventId: terminalRequest.lastEventId,
            preferredRoomPlayerId: terminalRequest.forfeitingPlayerId ?? roomSnapshot.room.members.first?.playerId
        )
        var mappedRequest = terminalRequest
        mappedRequest.authorityPlayerIdByRoomPlayerId = mapping
        let terminalPayload = authorityRelay.fetchTerminalSummary(mappedRequest)
        try validateTerminalSummaryPayload(terminalPayload)
        return (mappedRequest, terminalPayload)
    }

    private func validateTerminalSummaryPayload(_ terminalPayload: [String: Any]) throws {
        _ = try requireDictionary("roundEnded", in: terminalPayload)
        _ = try requireDictionary("matchEnded", in: terminalPayload)
    }

    private func resolveAuthorityPlayerIdMapping(
        roomSnapshot: RoomCoordinatorSnapshot,
        authorityRelay: RoomAuthorityRelay,
        gameId: String,
        fallbackStateVersion: Int,
        lastEventId: String?,
        preferredRoomPlayerId: String?
    ) throws -> [String: String] {
        if let existing = authorityPlayerIdByRoomId[roomSnapshot.room.roomId],
           mapping(existing, covers: roomSnapshot) {
            return existing
        }

        let probeMember =
            roomSnapshot.room.members.first(where: { $0.playerId == preferredRoomPlayerId })
            ?? roomSnapshot.room.members.sorted(by: { $0.seat < $1.seat }).first
        guard let probeMember,
              let probeRequest = makeProjectionPreviewRequest(
                from: roomSnapshot,
                viewerPlayerId: probeMember.playerId,
                gameId: gameId,
                projectionScope: "player",
                snapshotReason: MultiplayerSnapshotReason.localPreview.rawValue,
                stateVersion: fallbackStateVersion,
                lastEventId: lastEventId
              ) else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("projectionRequest")
        }

        let probePayload = authorityRelay.fetchProjectionPreview(probeRequest)
        guard let snapshotPayload = probePayload["snapshot"] as? [String: Any] else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("projectionSnapshot")
        }
        let authoritySnapshot = try decodeJSONObject(MultiplayerSnapshot.self, from: snapshotPayload)
        return try refreshAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authoritySnapshot: authoritySnapshot
        )
    }

    @discardableResult
    private func refreshAuthorityPlayerIdMapping(
        roomSnapshot: RoomCoordinatorSnapshot,
        authoritySnapshot: MultiplayerSnapshot
    ) throws -> [String: String] {
        let roomPlayerIdBySeat = Dictionary(
            uniqueKeysWithValues: roomSnapshot.room.members.map { ($0.seat, $0.playerId) }
        )
        var authorityMapping: [String: String] = [:]
        for authorityPlayer in authoritySnapshot.state.players {
            guard let roomPlayerId = roomPlayerIdBySeat[authorityPlayer.seatIndex] else {
                continue
            }
            authorityMapping[roomPlayerId] = authorityPlayer.playerId
        }
        guard mapping(authorityMapping, covers: roomSnapshot) else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("playerIdMapping")
        }
        authorityPlayerIdByRoomId[roomSnapshot.room.roomId] = authorityMapping
        return authorityMapping
    }

    private func mapping(
        _ authorityPlayerIdByRoomPlayerId: [String: String],
        covers snapshot: RoomCoordinatorSnapshot
    ) -> Bool {
        Set(snapshot.room.members.map(\.playerId)).isSubset(of: Set(authorityPlayerIdByRoomPlayerId.keys))
    }

    private func fetchProjectionSnapshot(
        authorityRelay: RoomAuthorityRelay,
        roomSnapshot: RoomCoordinatorSnapshot,
        viewerPlayerId: String,
        gameState: RoomTransportGameState,
        snapshotReason: MultiplayerSnapshotReason,
        lastEventIdOverride: String? = nil
    ) throws -> MultiplayerSnapshot {
        guard let request = makeProjectionPreviewRequest(
            from: roomSnapshot,
            viewerPlayerId: viewerPlayerId,
            gameId: gameState.gameId,
            projectionScope: "player",
            snapshotReason: snapshotReason.rawValue,
            stateVersion: gameState.stateVersion,
            lastEventId: lastEventIdOverride ?? gameState.lastEventId
        ) else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("projectionRequest")
        }
        let mappedRequest = try mappedProjectionPreviewRequest(
            request,
            roomSnapshot: roomSnapshot,
            gameState: gameState,
            authorityRelay: authorityRelay,
            preferredRoomPlayerId: viewerPlayerId
        )
        let payload = authorityRelay.fetchProjectionPreview(mappedRequest)
        guard let snapshotPayload = payload["snapshot"] as? [String: Any] else {
            throw RoomCLIAdapterError.invalidAuthorityPayload("projectionSnapshot")
        }
        let snapshot = try decodeJSONObject(MultiplayerSnapshot.self, from: snapshotPayload)
        try refreshAuthorityPlayerIdMapping(
            roomSnapshot: roomSnapshot,
            authoritySnapshot: snapshot
        )
        return snapshot
    }

    private func resolveTransportGameState(
        roomId: String,
        gameId: String,
        fallbackStateVersion: Int
    ) -> RoomTransportGameState {
        transportGameStates[roomId] ?? RoomTransportGameState(
            roomId: roomId,
            gameId: gameId,
            stateVersion: fallbackStateVersion,
            lastEventOrdinal: 0,
            lastEventId: nil,
            lastTurnId: nil
        )
    }

    private func resolvedExpectedStateVersion(
        client: RoomTransportClientState,
        requestedStateVersion: Int
    ) -> Int {
        guard let deterministicFaultHook,
              deterministicFaultHook.kind == .staleExpectedStateVersionOverride,
              deterministicFaultHook.targetSessionId == client.sessionId else {
            return requestedStateVersion
        }
        return deterministicFaultHook.overriddenExpectedStateVersion
    }

    private func resolveDuplicateTransportAction(
        payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        effectiveExpectedStateVersion: Int,
        authoritativeStateVersion: Int,
        authoritativeEventId: String?,
        fallbackResolvedCommand: RoomTransportResolvedGameplayCommand,
        action: String
    ) throws -> RoomTransportDuplicateActionResolution {
        guard let actionId = payload.actionId,
              !actionId.isEmpty else {
            return .fresh(nil)
        }

        let key = RoomTransportActionRecordKey(
            roomId: client.roomId,
            playerId: client.playerId,
            actionId: actionId
        )
        let fingerprint = try transportActionFingerprint(
            payload: payload,
            client: client,
            effectiveExpectedStateVersion: effectiveExpectedStateVersion
        )

        if let existing = transportActionRecords[key] {
            if existing.fingerprint == fingerprint {
                replayRecordedTransportAction(existing, for: client.clientId)
                let response = responseWithDuplicateDisposition(
                    existing.response,
                    disposition: "exactReplay",
                    clientId: client.clientId
                )
                return .replay(response)
            }

            let conflictResponse = try rejectTransportGameplay(
                resolvedCommand: fallbackResolvedCommand,
                client: client,
                rejection: RoomAuthorityGameplayRejection(
                    code: .actionIdConflict,
                    retryable: false,
                    messageKey: "multiplayer.reject.action_id_conflict"
                ),
                authoritativeStateVersion: authoritativeStateVersion,
                authoritativeEventId: authoritativeEventId,
                action: action
            )
            return .replay(
                responseWithDuplicateDisposition(
                    conflictResponse,
                    disposition: "conflictReject",
                    clientId: client.clientId
                )
            )
        }

        return .fresh(
            RoomTransportActionRecordContext(
                key: key,
                fingerprint: fingerprint,
                mailboxCursor: transportMailboxCursor(roomId: client.roomId, including: client.clientId)
            )
        )
    }

    private func transportActionFingerprint(
        payload: RoomTransportSendCLIRequest,
        client: RoomTransportClientState,
        effectiveExpectedStateVersion: Int
    ) throws -> String {
        let fingerprintPayload: [String: Any] = [
            "roomId": client.roomId,
            "playerId": client.playerId,
            "action": payload.action,
            "expectedStateVersion": effectiveExpectedStateVersion,
            "commandPayload": sanitizeJSONValue(TestControlSupport.unbox(payload.commandPayload) ?? [:]),
        ]
        let data = try JSONSerialization.data(withJSONObject: fingerprintPayload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func recordedTransportActionResponse(
        _ response: [String: Any],
        context: RoomTransportActionRecordContext?
    ) -> [String: Any] {
        guard let context else {
            return response
        }

        transportActionRecords[context.key] = RoomTransportActionRecord(
            fingerprint: context.fingerprint,
            response: response,
            replayEnvelopesByClientId: transportMailboxDelta(since: context.mailboxCursor)
        )
        return response
    }

    private func replayRecordedTransportAction(
        _ record: RoomTransportActionRecord,
        for clientId: String
    ) {
        for envelope in record.replayEnvelopesByClientId[clientId] ?? [] {
            enqueue(envelope: envelope, for: clientId)
        }
    }

    private func responseWithDuplicateDisposition(
        _ response: [String: Any],
        disposition: String,
        clientId: String
    ) -> [String: Any] {
        guard var data = response["data"] as? [String: Any] else {
            return response
        }
        data["duplicateActionIdDisposition"] = disposition
        if let queuedEnvelopeCount = transportMailboxes[clientId]?.count {
            data["queuedEnvelopeCount"] = queuedEnvelopeCount
        } else if data["queuedEnvelopeCount"] == nil {
            data["queuedEnvelopeCount"] = 0
        }
        var nextResponse = response
        nextResponse["data"] = data
        return nextResponse
    }

    private func transportMailboxCursor(
        roomId: String,
        including clientId: String
    ) -> [String: Int] {
        var clientIds = Set(connectedTransportClientIDs(in: roomId))
        clientIds.insert(clientId)
        return Dictionary(
            uniqueKeysWithValues: clientIds.map { clientId in
                (clientId, transportMailboxes[clientId]?.count ?? 0)
            }
        )
    }

    private func transportMailboxDelta(
        since cursor: [String: Int]
    ) -> [String: [[String: Any]]] {
        Dictionary(
            uniqueKeysWithValues: cursor.map { clientId, startIndex in
                let mailbox = transportMailboxes[clientId] ?? []
                let clampedStartIndex = min(startIndex, mailbox.count)
                return (clientId, Array(mailbox.dropFirst(clampedStartIndex)))
            }
        )
    }

    private func nextGameEventID(for roomId: String) -> String {
        var state = transportGameStates[roomId] ?? RoomTransportGameState(
            roomId: roomId,
            gameId: coordinator.snapshot(for: roomId)?.room.activeGameId ?? "game_\(roomId)",
            stateVersion: 0,
            lastEventOrdinal: 0,
            lastEventId: nil,
            lastTurnId: nil
        )
        state.lastEventOrdinal += 1
        let eventId = String(format: "evt_%06d", state.lastEventOrdinal)
        state.lastEventId = eventId
        transportGameStates[roomId] = state
        return eventId
    }

    private func parseEventOrdinal(from eventId: String) -> Int {
        Int(eventId.split(separator: "_").last ?? "") ?? 0
    }

    private func payloadName(for commandName: MultiplayerCommandName) -> String {
        switch commandName {
        case .playCard:
            return "playCard"
        case .selectCapture, .selectShake, .chooseGoStop, .chooseChrysanthemumRole:
            return "submitChoice"
        case .resume:
            return "resume"
        case .quit:
            return "quit"
        }
    }

    private func choiceCommandName(
        for choiceKind: MultiplayerContractChoiceKind
    ) -> MultiplayerCommandName {
        switch choiceKind {
        case .capture:
            return .selectCapture
        case .shake:
            return .selectShake
        case .goStop:
            return .chooseGoStop
        case .chrysanthemumRole:
            return .chooseChrysanthemumRole
        }
    }

    private func provisionalTransportGameplayCommand(
        payload: RoomTransportSendCLIRequest,
        roomPlayerId: String,
        authorityPlayerId: String,
        expectedStateVersion: Int
    ) -> RoomTransportResolvedGameplayCommand {
        let commandPayload = TestControlSupport.unbox(payload.commandPayload) ?? [:]
        let commandName: MultiplayerCommandName
        switch payload.action {
        case "submitChoice":
            commandName = (commandPayload["choiceCommandName"] as? String)
                .flatMap(MultiplayerCommandName.init(rawValue:))
                ?? .selectCapture
        case "quit":
            commandName = .quit
        default:
            commandName = .playCard
        }

        return RoomTransportResolvedGameplayCommand(
            requestId: payload.requestId ?? "req_\(payload.action)_\(roomPlayerId)",
            traceId: payload.traceId,
            actionId: payload.actionId ?? "act_\(payload.action)_\(roomPlayerId)",
            roomPlayerId: roomPlayerId,
            authorityPlayerId: authorityPlayerId,
            expectedStateVersion: expectedStateVersion,
            commandName: commandName,
            commandPayload: commandPayload
        )
    }

    private func makeTurnChangedPayload(
        before: MultiplayerSnapshot?,
        after: MultiplayerSnapshot?
    ) -> [String: Any]? {
        guard let after,
              let currentPlayerId = after.state.currentPlayerId else {
            return nil
        }
        guard before?.state.turnId != after.state.turnId ||
                before?.state.currentPlayerId != after.state.currentPlayerId else {
            return nil
        }
        let payload = MultiplayerTurnChangedPayload(
            turnId: after.state.turnId,
            currentPlayerId: currentPlayerId,
            turnDeadlineAt: after.state.timers.turnDeadlineAt
        )
        return try? requireJSONObject(from: payload)
    }

    private func makeStatePatchPayload(
        from beforeState: MultiplayerMatchSnapshot,
        to afterState: MultiplayerMatchSnapshot,
        baseStateVersion: Int,
        targetStateVersion: Int
    ) throws -> [String: Any] {
        let beforeObject = try requireJSONObject(from: beforeState)
        let afterObject = try requireJSONObject(from: afterState)
        let keys = Set(beforeObject.keys).union(afterObject.keys).sorted()
        var ops: [MultiplayerJSONPatchOperation] = []

        for key in keys {
            let beforeValue = beforeObject[key]
            let afterValue = afterObject[key]
            switch (beforeValue, afterValue) {
            case (.none, let value?):
                ops.append(MultiplayerJSONPatchOperation(op: "add", path: "/\(key)", value: AnyCodable(value)))
            case (let value?, .none):
                _ = value
                ops.append(MultiplayerJSONPatchOperation(op: "remove", path: "/\(key)"))
            case (let lhs?, let rhs?):
                if !jsonValuesEqual(lhs, rhs) {
                    ops.append(MultiplayerJSONPatchOperation(op: "replace", path: "/\(key)", value: AnyCodable(rhs)))
                }
            case (.none, .none):
                break
            }
        }

        let patch = MultiplayerPatch(
            patchFormat: .jsonPatch,
            baseStateVersion: baseStateVersion,
            targetStateVersion: targetStateVersion,
            ops: ops
        )
        return try requireJSONObject(from: patch)
    }

    private func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        let lhsWrapped = ["value": sanitizeJSONValue(lhs)]
        let rhsWrapped = ["value": sanitizeJSONValue(rhs)]
        guard let lhsData = try? JSONSerialization.data(withJSONObject: lhsWrapped, options: [.sortedKeys]),
              let rhsData = try? JSONSerialization.data(withJSONObject: rhsWrapped, options: [.sortedKeys]) else {
            return false
        }
        return lhsData == rhsData
    }

    private func sanitizeJSONValue(_ value: Any) -> Any {
        if let value = value as? NSNull {
            return value
        }
        if let value = value as? [String: Any] {
            return value.mapValues(sanitizeJSONValue)
        }
        if let value = value as? [Any] {
            return value.map(sanitizeJSONValue)
        }
        return value
    }

    private func enqueueGameEvent(
        engineEvent: [String: Any],
        roomId: String,
        clientId: String,
        roomSequence: Int?
    ) {
        enqueue(
            envelope: makeTransportEnvelope(
                type: "gameEvent",
                roomId: roomId,
                sessionId: transportClients[clientId]?.sessionId,
                roomSequence: roomSequence,
                payload: ["engineEvent": engineEvent]
            ),
            for: clientId
        )
    }

    private func broadcastGameEvent(
        engineEvent: [String: Any],
        roomId: String,
        roomSequence: Int?
    ) {
        for clientId in connectedTransportClientIDs(in: roomId) {
            enqueueGameEvent(
                engineEvent: engineEvent,
                roomId: roomId,
                clientId: clientId,
                roomSequence: roomSequence
            )
        }
    }

    private func makeEngineEventEnvelope(
        traceId: String?,
        roomId: String?,
        gameId: String?,
        eventId: String,
        stateVersion: Int,
        causedByActionId: String?,
        eventName: MultiplayerEventName,
        payload: [String: Any]
    ) -> [String: Any] {
        var envelope: [String: Any] = [
            "type": "event",
            "eventId": eventId,
            "stateVersion": stateVersion,
            "serverTime": dateString(Date()),
            "eventName": eventName.rawValue,
            "payload": payload,
        ]
        if let traceId {
            envelope["traceId"] = traceId
        }
        if let roomId {
            envelope["roomId"] = roomId
        }
        if let gameId {
            envelope["gameId"] = gameId
        }
        if let causedByActionId {
            envelope["causedByActionId"] = causedByActionId
        }
        return envelope
    }

    private func rejectionDetails(
        code: MultiplayerRejectCode,
        authoritativeStateVersion: Int,
        authoritativeEventId: String?,
        clientStateVersion: Int,
        effectiveExpectedStateVersion: Int,
        injectedMismatchMode: String?,
        recoverySnapshotId: String?
    ) -> [String: AnyCodable]? {
        guard code == .staleStateVersion else {
            return nil
        }

        let resync = MultiplayerResyncDirective(
            trigger: .staleStateVersionReject,
            snapshotReason: .resync,
            clientStateVersion: clientStateVersion,
            expectedStateVersion: effectiveExpectedStateVersion,
            authoritativeStateVersion: authoritativeStateVersion,
            clientEventId: nil,
            authoritativeEventId: authoritativeEventId,
            shouldLockInput: true
        )
        let resyncPayload = (try? requireJSONObject(from: resync)) ?? [:]
        var details: [String: AnyCodable] = [
            "expectedStateVersion": AnyCodable(effectiveExpectedStateVersion),
            "authoritativeStateVersion": AnyCodable(authoritativeStateVersion),
            "clientStateVersion": AnyCodable(clientStateVersion),
            "resync": AnyCodable(resyncPayload),
            "recoverySnapshotReason": AnyCodable(MultiplayerSnapshotReason.resync.rawValue),
        ]
        if let authoritativeEventId {
            details["authoritativeEventId"] = AnyCodable(authoritativeEventId)
        }
        if let recoverySnapshotId {
            details["recoverySnapshotId"] = AnyCodable(recoverySnapshotId)
        }
        if let injectedMismatchMode {
            details["injectedMismatchMode"] = AnyCodable(injectedMismatchMode)
        }
        return details
    }

    private func requireRoomSnapshot(_ roomId: String) throws -> RoomCoordinatorSnapshot {
        guard let snapshot = coordinator.snapshot(for: roomId) else {
            throw RoomCoordinatorError.roomNotFound(roomId: roomId)
        }
        return snapshot
    }

    private func requireDictionary(_ key: String, in payload: [String: Any]) throws -> [String: Any] {
        guard let dictionary = payload[key] as? [String: Any] else {
            throw RoomCLIAdapterError.invalidAuthorityPayload(key)
        }
        return dictionary
    }

    private func decodeJSONObject<T: Decodable>(_ type: T.Type, from payload: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try decoder.decode(type, from: data)
    }

    private func requireJSONObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RoomCLIAdapterError.invalidAuthorityPayload(String(describing: T.self))
        }
        return object
    }

    private func transportReceive(_ payload: RoomTransportReceiveCLIRequest) -> [String: Any] {
        let envelopes = transportMailboxes[payload.clientId] ?? []
        transportMailboxes[payload.clientId] = []
        return [
            "clientId": payload.clientId,
            "envelopes": envelopes,
        ]
    }

    private func disconnectTransportClient(
        clientId: String,
        expectedConnectionId: String?,
        requireExpectedConnectionId: Bool
    ) throws -> RoomTransportDisconnectResolution? {
        guard var client = transportClients[clientId],
              let snapshot = coordinator.snapshot(for: client.roomId),
              let session = snapshot.sessions.first(where: { $0.sessionId == client.sessionId }),
              session.connectionState == .connected else {
            return nil
        }

        if requireExpectedConnectionId {
            guard let expectedConnectionId,
                  let currentConnectionId = client.connectionId,
                  session.connectionId == expectedConnectionId,
                  currentConnectionId == expectedConnectionId else {
                return nil
            }
        }

        let mutation = try coordinator.disconnectMember(
            DisconnectMemberRequest(
                roomId: client.roomId,
                playerId: client.playerId
            )
        )
        client.connectionId = nil
        transportClients[clientId] = client
        broadcastRoomEvents(mutation.events, in: client.roomId)
        return RoomTransportDisconnectResolution(
            client: client,
            mutation: mutation
        )
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

    private func bootstrapScopedData(
        _ data: [String: Any],
        stage: String,
        currentAction: String,
        futurePublicRoute: String
    ) -> [String: Any] {
        var scoped = data
        scoped["bootstrapBoundary"] = bootstrapBoundary(
            stage: stage,
            currentAction: currentAction,
            futurePublicRoute: futurePublicRoute
        )
        return scoped
    }

    private func bootstrapBoundary(
        stage: String,
        currentAction: String,
        futurePublicRoute: String
    ) -> [String: Any] {
        // Keep locked parity fields stable; add freeze metadata only outside the locked nested objects.
        [
            "surfaceKind": "publicBootstrapFacade",
            "boundaryVersion": "room-bootstrap.v1",
            "stage": stage,
            "currentBoundary": [
                "mode": "concreteCommandFacade",
                "createAction": "room_bootstrap_create",
                "lookupInviteAction": "room_bootstrap_lookup_invite",
                "joinAction": "room_bootstrap_join",
                "prepareGameStartAction": "room_bootstrap_prepare_game_start",
            ],
            "currentCommandAction": currentAction,
            "futurePublicSplit": [
                "status": "placeholder",
                "route": futurePublicRoute,
            ],
            "recommendedNextActions": bootstrapRecommendedNextActions(for: stage),
            "gameplayTransportBoundary": [
                "connectAction": "room_transport_connect",
                "sendAction": "room_transport_send",
                "receiveAction": "room_transport_receive",
                "helloAction": "hello",
            ],
            "gapRecoveryShapeAction": "room_gap_recovery_shape",
            "gapRecovery": [
                "shapeAction": "room_gap_recovery_shape",
                "transportTriggerAction": "triggerGapRecovery",
            ],
        ]
    }

    private func gapRecoveryShape() -> [String: Any] {
        // Keep the preflight shape backward compatible; live-hook details stay additive.
        [
            "mode": "artifactOnly",
            "transportFlag": [
                "name": "gapDetected",
                "status": "placeholder",
                "currentEmission": false,
                "futureTrigger": "missingGameEventOrStateVersionGap",
            ],
            "artifact": [
                "name": "gapRecoveryHint",
                "inputLockRequired": true,
                "snapshotReason": "gapDetected",
                "minimumFields": [
                    "roomId",
                    "sessionId",
                    "lastAckedGameEventId",
                    "lastSeenStateVersion",
                    "authoritativeEventId",
                    "authoritativeStateVersion",
                ],
            ],
            "recoveryEnvelope": [
                "type": "gameEvent",
                "eventName": "stateSnapshot",
                "reason": "gapDetected",
            ],
            "relatedActions": [
                "bootstrapPrepareAction": "room_bootstrap_prepare_game_start",
                "debugStaleHookAction": "room_set_mp008_hook",
            ],
            "liveHook": [
                "transportAction": "room_transport_send(action=triggerGapRecovery)",
                "recoveryEnvelopeType": "gapRecoveryHint",
            ],
        ]
    }

    private func bootstrapRecommendedNextActions(for stage: String) -> [String] {
        switch stage {
        case "createRoom":
            return ["room_transport_connect", "room_transport_send(action=hello)"]
        case "lookupInvite":
            return ["room_bootstrap_join"]
        case "joinRoom":
            return ["room_transport_connect", "room_transport_send(action=hello)", "room_set_ready"]
        case "prepareGameStart":
            return ["room_transport_receive"]
        default:
            return []
        }
    }

    private func makeGapRecoveryHintPayload(
        client: RoomTransportClientState,
        session: RoomSession,
        snapshotEventId: String,
        authoritativeStateVersion: Int,
        lastAckedGameEventId: String?,
        lastSeenStateVersion: Int
    ) -> [String: Any] {
        [
            "artifactVersion": "gapRecoveryHint.v1",
            "transportFlag": [
                "name": "gapDetected",
                "value": true,
            ],
            "inputLockRequired": true,
            "roomId": client.roomId,
            "sessionId": session.sessionId,
            "targetClientId": client.clientId,
            "lastAckedGameEventId": lastAckedGameEventId ?? NSNull(),
            "lastSeenStateVersion": lastSeenStateVersion,
            "authoritativeEventId": snapshotEventId,
            "authoritativeStateVersion": authoritativeStateVersion,
            "snapshotReason": MultiplayerSnapshotReason.gapDetected.rawValue,
            "recoveryEnvelope": [
                "type": "gameEvent",
                "eventName": "stateSnapshot",
                "reason": MultiplayerSnapshotReason.gapDetected.rawValue,
            ],
        ]
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
            "inviteCode": serializedInviteCode(for: room) ?? NSNull(),
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

    private func serializedInviteCode(for room: Room) -> String? {
        guard room.joinPolicy == .inviteCode else {
            return nil
        }
        return room.roomId
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
        case .transportGameNotStarted:
            return "transportGameNotStarted"
        case .invalidAuthorityPayload:
            return "invalidAuthorityPayload"
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
        case let .transportGameNotStarted(roomId):
            return "Transport gameplay requires an active game for room \(roomId)"
        case let .invalidAuthorityPayload(payloadName):
            return "Authority payload is missing required field: \(payloadName)"
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
