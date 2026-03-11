import Foundation

enum RoomType: String, Codable, CaseIterable, Sendable {
    case invite
    case quickMatch
}

enum RoomJoinPolicy: String, Codable, CaseIterable, Sendable {
    case inviteCode
    case matchmaker
}

enum RoomState: String, Codable, CaseIterable, Sendable {
    case waitingForPlayers
    case waitingForReady
    case starting
    case inGame
    case ended
    case closed
}

enum RoomMemberRole: String, Codable, CaseIterable, Sendable {
    case host
    case guest
}

enum RoomMemberPresence: String, Codable, CaseIterable, Sendable {
    case connected
    case disconnected
    case left
    case forfeitPending
}

enum RoomSessionConnectionState: String, Codable, CaseIterable, Sendable {
    case connected
    case disconnectedGrace
    case resuming
    case expired
    case replaced
}

enum RoomCloseReason: String, Codable, CaseIterable, Sendable {
    case hostLeft
    case idleExpired
    case allPlayersLeft
    case resultExpired
    case explicitClose
    case bootstrapFailed
}

enum RoomForfeitReason: String, Codable, CaseIterable, Sendable {
    case explicitLeave
    case disconnectTimeout
}

enum RoomStateTransitionReason: String, Codable, CaseIterable, Sendable {
    case roomCreated
    case guestJoined
    case readyCompleted
    case gameStarted
    case bootstrapFailed
    case matchEnded
    case guestReleased
    case hostLeft
    case forfeit
    case resultExpired
    case emptyRoomClosed
    case explicitClose
}

enum RoomCoordinatorAction: String, Codable, Sendable {
    case createRoom
    case joinRoom
    case setReady
    case attachSession
    case disconnectMember
    case leaveRoom
    case closeRoom
    case resumeSession
    case recordHeartbeat
    case recordGameStarted
    case recordMatchEnded
    case reapExpiredState
}

struct RoomDeadlines: Codable, Equatable, Sendable {
    var joinExpiresAt: Date?
    var readyExpiresAt: Date?
    var resultExpiresAt: Date?
}

struct RoomMember: Codable, Equatable, Sendable {
    var playerId: String
    var seat: Int
    var role: RoomMemberRole
    var ready: Bool
    var presence: RoomMemberPresence
    var sessionId: String
    var connectedConnectionId: String?
    var joinedAt: Date
}

struct Room: Codable, Equatable, Sendable {
    var roomId: String
    var roomType: RoomType
    var joinPolicy: RoomJoinPolicy
    var roomState: RoomState
    var hostPlayerId: String
    var activeGameId: String?
    var members: [RoomMember]
    var deadlines: RoomDeadlines
    var lastRoomSequence: Int
    var createdAt: Date
    var closedAt: Date?
}

struct RoomSession: Codable, Equatable, Sendable {
    var sessionId: String
    var playerId: String
    var roomId: String
    var deviceId: String
    var connectionState: RoomSessionConnectionState
    var connectionId: String?
    var resumeToken: String
    var resumeIssuedAt: Date
    var graceExpiresAt: Date?
    var lastHeartbeatAt: Date
    var lastAckedRoomSequence: Int
    var lastAckedGameEventId: String?
    var lastSeenStateVersion: Int?
}

struct RoomCoordinatorSnapshot: Equatable, Sendable {
    var room: Room
    var sessions: [RoomSession]
}

enum RoomHelloResumeMode: String, Codable, Equatable, Sendable {
    case fresh
    case resume
}

struct RoomHelloResolution: Equatable, Sendable {
    var resumeMode: RoomHelloResumeMode
    var mutation: RoomCoordinatorMutation
}

enum RoomGameStartControlMode: String, Codable, Equatable, Sendable {
    case explicitRecordGameStarted
}

struct RoomBootstrapParticipantPresence: Codable, Equatable, Sendable {
    var source: String
    var isConnected: Bool
    var isReady: Bool
}

struct RoomGameStartedBootstrapRequest: Codable, Equatable, Sendable {
    var roomId: String
    var gameId: String
    var viewerPlayerId: String
    var viewerSeatIndex: Int?
    var projectionScope: String
    var snapshotReason: String
    var stateVersionHint: Int
    var participantPresenceByPlayerId: [String: RoomBootstrapParticipantPresence]
    var authorityPlayerIdByRoomPlayerId: [String: String]?
}

struct RoomGameStartedBootstrapPlan: Codable, Equatable, Sendable {
    var controlMode: RoomGameStartControlMode
    var fetchAction: String
    var requestsByPlayerId: [String: RoomGameStartedBootstrapRequest]
}

struct RoomProjectionPreviewRequest: Codable, Equatable, Sendable {
    var roomId: String
    var gameId: String
    var viewerPlayerId: String
    var viewerSeatIndex: Int?
    var projectionScope: String
    var snapshotReason: String
    var stateVersion: Int
    var lastEventId: String?
    var participantPresenceByPlayerId: [String: RoomBootstrapParticipantPresence]
    var authorityPlayerIdByRoomPlayerId: [String: String]?
}

struct RoomTerminalSummaryRelayRequest: Codable, Equatable, Sendable {
    var roomId: String
    var gameId: String
    var roundIndex: Int
    var quitReason: String?
    var forfeitingPlayerId: String?
    var summaryStateVersion: Int
    var lastEventId: String?
    var participantPresenceByPlayerId: [String: RoomBootstrapParticipantPresence]
    var authorityPlayerIdByRoomPlayerId: [String: String]?
}

enum RoomDeterministicFaultHookKind: String, Codable, Equatable, Sendable {
    case staleExpectedStateVersionOverride
}

struct RoomDeterministicFaultHook: Codable, Equatable, Sendable {
    var kind: RoomDeterministicFaultHookKind
    var targetSessionId: String
    var overriddenExpectedStateVersion: Int
}

enum RoomCoordinatorEventPayload: Equatable, Sendable {
    case roomStateChanged(from: RoomState, to: RoomState, reason: RoomStateTransitionReason)
    case memberJoined(playerId: String, seat: Int, role: RoomMemberRole)
    case memberLeft(playerId: String, reason: RoomCloseReason)
    case memberReadyChanged(playerId: String, ready: Bool)
    case readyWindowExpired(resetPlayerIds: [String])
    case playerDisconnected(playerId: String, graceExpiresAt: Date)
    case playerReconnected(playerId: String, connectionId: String?)
    case playerForfeited(playerId: String, reason: RoomForfeitReason)
    case roomClosed(reason: RoomCloseReason, closedAt: Date)
}

struct RoomCoordinatorEvent: Equatable, Sendable {
    var roomId: String
    var roomSequence: Int
    var occurredAt: Date
    var payload: RoomCoordinatorEventPayload
}

struct RoomCoordinatorMutationMetadata: Equatable, Sendable {
    var requiresGameBootstrap: Bool
    var rotatedResumeToken: String?
    var supersededConnectionId: String?
    var gameStartControlMode: RoomGameStartControlMode?
    var gameStartedBootstrapPlan: RoomGameStartedBootstrapPlan?
    var terminalSummaryRelayRequest: RoomTerminalSummaryRelayRequest?
}

struct RoomCoordinatorMutation: Equatable, Sendable {
    var action: RoomCoordinatorAction
    var snapshot: RoomCoordinatorSnapshot
    var events: [RoomCoordinatorEvent]
    var metadata: RoomCoordinatorMutationMetadata
}

struct CreateRoomRequest: Codable, Equatable, Sendable {
    var hostPlayerId: String
    var deviceId: String
    var roomType: RoomType
    var joinPolicy: RoomJoinPolicy
}

struct JoinRoomRequest: Codable, Equatable, Sendable {
    var roomId: String
    var playerId: String
    var deviceId: String
}

struct SetReadyRequest: Codable, Equatable, Sendable {
    var roomId: String
    var playerId: String
    var ready: Bool
}

struct DisconnectMemberRequest: Codable, Equatable, Sendable {
    var roomId: String
    var playerId: String
}

struct LeaveRoomRequest: Codable, Equatable, Sendable {
    var roomId: String
    var playerId: String
}

struct CloseRoomRequest: Codable, Equatable, Sendable {
    var roomId: String
}

struct AttachSessionRequest: Codable, Equatable, Sendable {
    var roomId: String
    var sessionId: String
    var playerId: String
    var deviceId: String
    var connectionId: String?
    var resumeToken: String
    var lastAckedRoomSequence: Int?
    var lastAckedGameEventId: String?
    var lastSeenStateVersion: Int?
}

struct ResumeSessionRequest: Codable, Equatable, Sendable {
    var roomId: String
    var sessionId: String
    var playerId: String
    var deviceId: String
    var connectionId: String?
    var resumeToken: String
    var lastAckedRoomSequence: Int?
    var lastAckedGameEventId: String?
    var lastSeenStateVersion: Int?
}

struct RecordHeartbeatRequest: Codable, Equatable, Sendable {
    var roomId: String
    var sessionId: String
    var connectionId: String?
    var lastAckedRoomSequence: Int?
    var lastAckedGameEventId: String?
    var lastSeenStateVersion: Int?
}

struct RecordGameStartedRequest: Codable, Equatable, Sendable {
    var roomId: String
    var gameId: String
}

struct RecordMatchEndedRequest: Codable, Equatable, Sendable {
    var roomId: String
    var roundIndex: Int?
    var quitReason: String?
    var forfeitingPlayerId: String?
    var summaryStateVersion: Int?
    var lastEventId: String?
    var resultRetentionAt: Date?
}

struct RoomCoordinatorConfiguration: Equatable, Sendable {
    var joinTTL: TimeInterval
    var readyWindow: TimeInterval
    var heartbeatInterval: TimeInterval
    var disconnectTimeout: TimeInterval
    var reconnectGrace: TimeInterval
    var resultRetention: TimeInterval

    static let phase0 = RoomCoordinatorConfiguration(
        joinTTL: 300,
        readyWindow: 60,
        heartbeatInterval: 5,
        disconnectTimeout: 15,
        reconnectGrace: 30,
        resultRetention: 60
    )
}

enum RoomCoordinatorError: Error, Equatable, Sendable {
    case roomNotFound(roomId: String)
    case roomFull(roomId: String)
    case roomClosed(roomId: String)
    case playerAlreadyInRoom(playerId: String, roomId: String)
    case playerNotInRoom(playerId: String, roomId: String)
    case sessionNotFound(sessionId: String)
    case invalidRoomState(expected: [RoomState], actual: RoomState)
    case invalidResumeState(RoomSessionConnectionState)
    case staleConnectionId(expected: String?, actual: String?)
    case resumeTokenInvalid
    case resumeExpired
    case readyRequiresTwoMembers
    case closeRequiresHostOrTerminalState
}

protocol RoomLifecycleCoordinating: AnyObject {
    func createRoom(_ request: CreateRoomRequest) throws -> RoomCoordinatorMutation
    func joinRoom(_ request: JoinRoomRequest) throws -> RoomCoordinatorMutation
    func setReady(_ request: SetReadyRequest) throws -> RoomCoordinatorMutation
    func attachSession(_ request: AttachSessionRequest) throws -> RoomCoordinatorMutation
    func disconnectMember(_ request: DisconnectMemberRequest) throws -> RoomCoordinatorMutation
    func leaveRoom(_ request: LeaveRoomRequest) throws -> RoomCoordinatorMutation
    func closeRoom(_ request: CloseRoomRequest) throws -> RoomCoordinatorMutation
    func resumeSession(_ request: ResumeSessionRequest) throws -> RoomCoordinatorMutation
    func recordHeartbeat(_ request: RecordHeartbeatRequest) throws -> RoomCoordinatorMutation
    func recordGameStarted(_ request: RecordGameStartedRequest) throws -> RoomCoordinatorMutation
    func recordMatchEnded(_ request: RecordMatchEndedRequest) throws -> RoomCoordinatorMutation
    func reapExpiredState(asOf: Date) throws -> [RoomCoordinatorMutation]
    func snapshot(for roomId: String) -> RoomCoordinatorSnapshot?
}

func performRoomHello(
    coordinator: RoomLifecycleCoordinating,
    roomId: String,
    sessionId: String,
    playerId: String,
    deviceId: String,
    connectionId: String?,
    resumeToken: String,
    lastAckedRoomSequence: Int? = nil,
    lastAckedGameEventId: String? = nil,
    lastSeenStateVersion: Int? = nil
) throws -> RoomHelloResolution {
    let session = coordinator.snapshot(for: roomId)?.sessions.first(where: {
        $0.sessionId == sessionId && $0.playerId == playerId
    })

    if let session, session.connectionState == .disconnectedGrace {
        return RoomHelloResolution(
            resumeMode: .resume,
            mutation: try coordinator.resumeSession(
                ResumeSessionRequest(
                    roomId: roomId,
                    sessionId: sessionId,
                    playerId: playerId,
                    deviceId: deviceId,
                    connectionId: connectionId,
                    resumeToken: resumeToken,
                    lastAckedRoomSequence: lastAckedRoomSequence,
                    lastAckedGameEventId: lastAckedGameEventId,
                    lastSeenStateVersion: lastSeenStateVersion
                )
            )
        )
    }

    return RoomHelloResolution(
        resumeMode: .fresh,
        mutation: try coordinator.attachSession(
            AttachSessionRequest(
                roomId: roomId,
                sessionId: sessionId,
                playerId: playerId,
                deviceId: deviceId,
                connectionId: connectionId,
                resumeToken: resumeToken,
                lastAckedRoomSequence: lastAckedRoomSequence,
                lastAckedGameEventId: lastAckedGameEventId,
                lastSeenStateVersion: lastSeenStateVersion
            )
        )
    )
}

func makeGameStartedBootstrapPlan(
    from snapshot: RoomCoordinatorSnapshot,
    controlMode: RoomGameStartControlMode = .explicitRecordGameStarted
) -> RoomGameStartedBootstrapPlan? {
    guard snapshot.room.roomState == .inGame,
          let gameId = snapshot.room.activeGameId else {
        return nil
    }

    let participantPresenceByPlayerId = makeParticipantPresenceByPlayerId(from: snapshot)

    let requestsByPlayerId = Dictionary(
        uniqueKeysWithValues: snapshot.room.members.map { member in
            (
                member.playerId,
                RoomGameStartedBootstrapRequest(
                    roomId: snapshot.room.roomId,
                    gameId: gameId,
                    viewerPlayerId: member.playerId,
                    viewerSeatIndex: member.seat,
                    projectionScope: "player",
                    snapshotReason: "gameStarted",
                    stateVersionHint: 1,
                    participantPresenceByPlayerId: participantPresenceByPlayerId,
                    authorityPlayerIdByRoomPlayerId: nil
                )
            )
        }
    )

    return RoomGameStartedBootstrapPlan(
        controlMode: controlMode,
        fetchAction: "get_multiplayer_game_started_bootstrap",
        requestsByPlayerId: requestsByPlayerId
    )
}

func makeParticipantPresenceByPlayerId(
    from snapshot: RoomCoordinatorSnapshot,
    source: String = "roomSnapshot"
) -> [String: RoomBootstrapParticipantPresence] {
    Dictionary(
        uniqueKeysWithValues: snapshot.room.members.map { member in
            (
                member.playerId,
                RoomBootstrapParticipantPresence(
                    source: source,
                    isConnected: member.presence == .connected,
                    isReady: member.ready
                )
            )
        }
    )
}

func makeProjectionPreviewRequest(
    from snapshot: RoomCoordinatorSnapshot,
    viewerPlayerId: String,
    gameId: String? = nil,
    projectionScope: String = "player",
    snapshotReason: String = "localPreview",
    stateVersion: Int = 0,
    lastEventId: String? = nil
) -> RoomProjectionPreviewRequest? {
    guard let resolvedGameId = gameId ?? snapshot.room.activeGameId else {
        return nil
    }

    return RoomProjectionPreviewRequest(
        roomId: snapshot.room.roomId,
        gameId: resolvedGameId,
        viewerPlayerId: viewerPlayerId,
        viewerSeatIndex: snapshot.room.members.first(where: { $0.playerId == viewerPlayerId })?.seat,
        projectionScope: projectionScope,
        snapshotReason: snapshotReason,
        stateVersion: stateVersion,
        lastEventId: lastEventId,
        participantPresenceByPlayerId: makeParticipantPresenceByPlayerId(from: snapshot),
        authorityPlayerIdByRoomPlayerId: nil
    )
}

func makeTerminalSummaryRelayRequest(
    from snapshot: RoomCoordinatorSnapshot,
    roundIndex: Int = 1,
    quitReason: String? = nil,
    forfeitingPlayerId: String? = nil,
    summaryStateVersion: Int = 0,
    lastEventId: String? = nil
) -> RoomTerminalSummaryRelayRequest? {
    guard let gameId = snapshot.room.activeGameId else {
        return nil
    }

    return RoomTerminalSummaryRelayRequest(
        roomId: snapshot.room.roomId,
        gameId: gameId,
        roundIndex: roundIndex,
        quitReason: quitReason,
        forfeitingPlayerId: forfeitingPlayerId,
        summaryStateVersion: summaryStateVersion,
        lastEventId: lastEventId,
        participantPresenceByPlayerId: makeParticipantPresenceByPlayerId(from: snapshot),
        authorityPlayerIdByRoomPlayerId: nil
    )
}

func roomGameStartedBootstrapRequestData(
    from request: RoomGameStartedBootstrapRequest
) -> [String: Any] {
    var payload: [String: Any] = [
        "roomId": request.roomId,
        "gameId": request.gameId,
        "viewerPlayerId": mappedAuthorityPlayerId(
            for: request.viewerPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        ),
        "scope": request.projectionScope,
        "snapshotReason": request.snapshotReason,
        "reason": request.snapshotReason,
        "stateVersion": request.stateVersionHint,
        "participantPresenceByPlayerId": serializeBootstrapParticipantPresenceMap(
            request.participantPresenceByPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        ),
    ]
    if let viewerSeatIndex = request.viewerSeatIndex {
        payload["viewerIndex"] = viewerSeatIndex
    }
    return payload
}

func roomProjectionPreviewRequestData(
    from request: RoomProjectionPreviewRequest
) -> [String: Any] {
    var payload: [String: Any] = [
        "roomId": request.roomId,
        "gameId": request.gameId,
        "viewerPlayerId": mappedAuthorityPlayerId(
            for: request.viewerPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        ),
        "scope": request.projectionScope,
        "snapshotReason": request.snapshotReason,
        "reason": request.snapshotReason,
        "stateVersion": request.stateVersion,
        "participantPresenceByPlayerId": serializeBootstrapParticipantPresenceMap(
            request.participantPresenceByPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        ),
    ]
    if let viewerSeatIndex = request.viewerSeatIndex {
        payload["viewerIndex"] = viewerSeatIndex
    }
    if let lastEventId = request.lastEventId {
        payload["lastEventId"] = lastEventId
    }
    return payload
}

func roomTerminalSummaryRelayRequestData(
    from request: RoomTerminalSummaryRelayRequest
) -> [String: Any] {
    var payload: [String: Any] = [
        "roomId": request.roomId,
        "gameId": request.gameId,
        "roundIndex": request.roundIndex,
        "stateVersion": request.summaryStateVersion,
        "participantPresenceByPlayerId": serializeBootstrapParticipantPresenceMap(
            request.participantPresenceByPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        ),
    ]
    if let quitReason = request.quitReason {
        payload["quitReason"] = quitReason
    }
    if let forfeitingPlayerId = request.forfeitingPlayerId {
        payload["forfeitingPlayerId"] = mappedAuthorityPlayerId(
            for: forfeitingPlayerId,
            authorityPlayerIdByRoomPlayerId: request.authorityPlayerIdByRoomPlayerId
        )
    }
    if let lastEventId = request.lastEventId {
        payload["lastEventId"] = lastEventId
    }
    return payload
}

func mappedAuthorityPlayerId(
    for roomPlayerId: String,
    authorityPlayerIdByRoomPlayerId: [String: String]?
) -> String {
    authorityPlayerIdByRoomPlayerId?[roomPlayerId] ?? roomPlayerId
}

func serializeBootstrapParticipantPresenceMap(
    _ presenceByRoomPlayerId: [String: RoomBootstrapParticipantPresence],
    authorityPlayerIdByRoomPlayerId: [String: String]?
) -> [String: [String: Any]] {
    Dictionary(
        uniqueKeysWithValues: presenceByRoomPlayerId.map { roomPlayerId, presence in
            (
                mappedAuthorityPlayerId(
                    for: roomPlayerId,
                    authorityPlayerIdByRoomPlayerId: authorityPlayerIdByRoomPlayerId
                ),
                serializeBootstrapParticipantPresence(presence)
            )
        }
    )
}

private func serializeBootstrapParticipantPresence(
    _ presence: RoomBootstrapParticipantPresence
) -> [String: Any] {
    [
        "source": presence.source,
        "isConnected": presence.isConnected,
        "isReady": presence.isReady,
    ]
}
