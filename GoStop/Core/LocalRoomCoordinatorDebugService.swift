import Combine
import Foundation

#if DEBUG
struct LocalRoomDebugHelloAck: Equatable, Sendable {
    var resumeMode: RoomHelloResumeMode
    var connectionId: String?
    var heartbeatIntervalMs: Int
    var disconnectTimeoutMs: Int
    var reconnectGraceMs: Int
    var resultRetentionMs: Int
    var resumeToken: String?
}

struct LocalRoomDebugHelloResult: Equatable, Sendable {
    var helloAck: LocalRoomDebugHelloAck
    var mutation: RoomCoordinatorMutation
}

struct LocalRoomDebugGameStartedFlowResult: Equatable, Sendable {
    var mutation: RoomCoordinatorMutation
    var bootstrapPlan: RoomGameStartedBootstrapPlan
}

struct LocalRoomDebugBootstrapRelayResult {
    var mutation: RoomCoordinatorMutation
    var bootstrapPlan: RoomGameStartedBootstrapPlan
    var payloadsByPlayerId: [String: [String: Any]]
}

struct LocalRoomDebugTerminalRelayResult {
    var mutation: RoomCoordinatorMutation
    var terminalSummaryRequest: RoomTerminalSummaryRelayRequest
    var terminalSummaryPayload: [String: Any]
}

@MainActor
final class LocalRoomCoordinatorDebugService: ObservableObject {
    static let shared = LocalRoomCoordinatorDebugService()

    @Published private(set) var snapshotsByRoomId: [String: RoomCoordinatorSnapshot] = [:]
    @Published private(set) var lastMutation: RoomCoordinatorMutation?
    @Published private(set) var lastHelloResult: LocalRoomDebugHelloResult?
    @Published private(set) var lastGameStartedFlowResult: LocalRoomDebugGameStartedFlowResult?
    @Published private(set) var lastBootstrapRelayResult: LocalRoomDebugBootstrapRelayResult?
    @Published private(set) var lastTerminalRelayResult: LocalRoomDebugTerminalRelayResult?
    @Published private(set) var lastProjectionPreviewPayload: [String: Any]?
    @Published private(set) var deterministicFaultHook: RoomDeterministicFaultHook?

    private let configuration: RoomCoordinatorConfiguration
    private var coordinator: RoomLifecycleCoordinating

    init(
        configuration: RoomCoordinatorConfiguration = .phase0,
        coordinator: RoomLifecycleCoordinating? = nil
    ) {
        self.configuration = configuration
        self.coordinator = coordinator ?? InMemoryRoomCoordinator(configuration: configuration)
    }

    func reset() {
        coordinator = InMemoryRoomCoordinator(configuration: configuration)
        snapshotsByRoomId = [:]
        lastMutation = nil
        lastHelloResult = nil
        lastGameStartedFlowResult = nil
        lastBootstrapRelayResult = nil
        lastTerminalRelayResult = nil
        lastProjectionPreviewPayload = nil
        deterministicFaultHook = nil
    }

    @discardableResult
    func createRoom(_ request: CreateRoomRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.createRoom(request))
    }

    @discardableResult
    func joinRoom(_ request: JoinRoomRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.joinRoom(request))
    }

    @discardableResult
    func setReady(_ request: SetReadyRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.setReady(request))
    }

    @discardableResult
    func setGuestReady(roomId: String, ready: Bool = true) throws -> RoomCoordinatorMutation {
        let guestSession = try participant(roomId: roomId, role: .guest)
        return try setReady(
            SetReadyRequest(
                roomId: roomId,
                playerId: guestSession.playerId,
                ready: ready
            )
        )
    }

    @discardableResult
    func disconnect(_ request: DisconnectMemberRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.disconnectMember(request))
    }

    @discardableResult
    func resume(_ request: ResumeSessionRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.resumeSession(request))
    }

    @discardableResult
    func heartbeat(_ request: RecordHeartbeatRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.recordHeartbeat(request))
    }

    @discardableResult
    func recordGameStarted(_ request: RecordGameStartedRequest) throws -> RoomCoordinatorMutation {
        try apply(coordinator.recordGameStarted(request))
    }

    @discardableResult
    func recordGameStarted(roomId: String, gameId: String? = nil) throws -> RoomCoordinatorMutation {
        let resolvedGameID = gameId ?? defaultDebugGameID(roomId: roomId)
        return try recordGameStarted(
            RecordGameStartedRequest(
                roomId: roomId,
                gameId: resolvedGameID
            )
        )
    }

    @discardableResult
    func recordGameStartedAndPrepareBootstrap(
        _ request: RecordGameStartedRequest
    ) throws -> LocalRoomDebugGameStartedFlowResult {
        let mutation = try recordGameStarted(request)
        guard let bootstrapPlan =
            mutation.metadata.gameStartedBootstrapPlan ??
            makeGameStartedBootstrapPlan(from: mutation.snapshot) else {
            throw RoomCoordinatorError.invalidRoomState(
                expected: [.inGame],
                actual: mutation.snapshot.room.roomState
            )
        }

        let result = LocalRoomDebugGameStartedFlowResult(
            mutation: mutation,
            bootstrapPlan: bootstrapPlan
        )
        lastGameStartedFlowResult = result
        return result
    }

    @discardableResult
    func recordGameStartedAndPrepareBootstrap(
        roomId: String,
        gameId: String? = nil
    ) throws -> LocalRoomDebugGameStartedFlowResult {
        let resolvedGameID = gameId ?? defaultDebugGameID(roomId: roomId)
        return try recordGameStartedAndPrepareBootstrap(
            RecordGameStartedRequest(
                roomId: roomId,
                gameId: resolvedGameID
            )
        )
    }

    func recordGameStartedAndFetchBootstrap(
        _ request: RecordGameStartedRequest,
        using gameManager: GameManager
    ) throws -> LocalRoomDebugBootstrapRelayResult {
        let flow = try recordGameStartedAndPrepareBootstrap(request)
        let payloadsByPlayerId = Dictionary(
            uniqueKeysWithValues: flow.bootstrapPlan.requestsByPlayerId.map { playerId, bootstrapRequest in
                (
                    playerId,
                    TestControlSupport.serializedMultiplayerGameStartedBootstrapPayload(
                        from: gameManager,
                        requestData: roomGameStartedBootstrapRequestData(from: bootstrapRequest)
                    )
                )
            }
        )
        let result = LocalRoomDebugBootstrapRelayResult(
            mutation: flow.mutation,
            bootstrapPlan: flow.bootstrapPlan,
            payloadsByPlayerId: payloadsByPlayerId
        )
        lastBootstrapRelayResult = result
        return result
    }

    func recordGameStartedAndFetchBootstrap(
        roomId: String,
        gameId: String? = nil,
        using gameManager: GameManager
    ) throws -> LocalRoomDebugBootstrapRelayResult {
        let resolvedGameID = gameId ?? defaultDebugGameID(roomId: roomId)
        return try recordGameStartedAndFetchBootstrap(
            RecordGameStartedRequest(
                roomId: roomId,
                gameId: resolvedGameID
            ),
            using: gameManager
        )
    }

    func projectionPreview(
        roomId: String,
        viewerPlayerId: String,
        gameId: String? = nil,
        stateVersion: Int = 0,
        lastEventId: String? = nil,
        snapshotReason: String = "localPreview",
        scope: String = "player",
        using gameManager: GameManager
    ) throws -> [String: Any] {
        let snapshot = try requireSnapshot(roomId: roomId)
        guard let request = makeProjectionPreviewRequest(
            from: snapshot,
            viewerPlayerId: viewerPlayerId,
            gameId: gameId,
            projectionScope: scope,
            snapshotReason: snapshotReason,
            stateVersion: stateVersion,
            lastEventId: lastEventId
        ) else {
            throw RoomCoordinatorError.invalidRoomState(
                expected: [.starting, .inGame, .ended],
                actual: snapshot.room.roomState
            )
        }

        let payload = TestControlSupport.serializedMultiplayerProjectionPayload(
            from: gameManager,
            requestData: roomProjectionPreviewRequestData(from: request)
        )
        lastProjectionPreviewPayload = payload
        return payload
    }

    func recordMatchEndedAndFetchTerminalSummary(
        roomId: String,
        roundIndex: Int = 1,
        quitReason: String? = nil,
        forfeitingPlayerId: String? = nil,
        summaryStateVersion: Int = 0,
        lastEventId: String? = nil,
        using gameManager: GameManager
    ) throws -> LocalRoomDebugTerminalRelayResult {
        let mutation = try apply(
            coordinator.recordMatchEnded(
                RecordMatchEndedRequest(
                    roomId: roomId,
                    roundIndex: roundIndex,
                    quitReason: quitReason,
                    forfeitingPlayerId: forfeitingPlayerId,
                    summaryStateVersion: summaryStateVersion,
                    lastEventId: lastEventId,
                    resultRetentionAt: nil
                )
            )
        )
        guard let terminalSummaryRequest = mutation.metadata.terminalSummaryRelayRequest else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.ended], actual: mutation.snapshot.room.roomState)
        }

        let terminalSummaryPayload = TestControlSupport.serializedMultiplayerTerminalSummaryPayload(
            from: gameManager,
            requestData: roomTerminalSummaryRelayRequestData(from: terminalSummaryRequest)
        )
        let result = LocalRoomDebugTerminalRelayResult(
            mutation: mutation,
            terminalSummaryRequest: terminalSummaryRequest,
            terminalSummaryPayload: terminalSummaryPayload
        )
        lastTerminalRelayResult = result
        return result
    }

    func snapshot(roomId: String) -> RoomCoordinatorSnapshot? {
        guard let snapshot = coordinator.snapshot(for: roomId) else {
            return nil
        }
        snapshotsByRoomId[roomId] = snapshot
        return snapshot
    }

    @discardableResult
    func helloHost(
        roomId: String,
        connectionId: String?,
        lastAckedRoomSequence: Int? = nil,
        lastAckedGameEventId: String? = nil,
        lastSeenStateVersion: Int? = nil
    ) throws -> LocalRoomDebugHelloResult {
        try helloParticipant(
            roomId: roomId,
            role: .host,
            connectionId: connectionId,
            lastAckedRoomSequence: lastAckedRoomSequence,
            lastAckedGameEventId: lastAckedGameEventId,
            lastSeenStateVersion: lastSeenStateVersion
        )
    }

    @discardableResult
    func helloGuest(
        roomId: String,
        connectionId: String?,
        lastAckedRoomSequence: Int? = nil,
        lastAckedGameEventId: String? = nil,
        lastSeenStateVersion: Int? = nil
    ) throws -> LocalRoomDebugHelloResult {
        try helloParticipant(
            roomId: roomId,
            role: .guest,
            connectionId: connectionId,
            lastAckedRoomSequence: lastAckedRoomSequence,
            lastAckedGameEventId: lastAckedGameEventId,
            lastSeenStateVersion: lastSeenStateVersion
        )
    }

    @discardableResult
    func hello(
        roomId: String,
        sessionId: String,
        playerId: String,
        deviceId: String,
        connectionId: String?,
        resumeToken: String,
        lastAckedRoomSequence: Int? = nil,
        lastAckedGameEventId: String? = nil,
        lastSeenStateVersion: Int? = nil
    ) throws -> LocalRoomDebugHelloResult {
        let resolution = try performRoomHello(
            coordinator: coordinator,
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
        let mutation = apply(resolution.mutation)

        let result = LocalRoomDebugHelloResult(
            helloAck: LocalRoomDebugHelloAck(
                resumeMode: resolution.resumeMode,
                connectionId: connectionId,
                heartbeatIntervalMs: milliseconds(configuration.heartbeatInterval),
                disconnectTimeoutMs: milliseconds(configuration.disconnectTimeout),
                reconnectGraceMs: milliseconds(configuration.reconnectGrace),
                resultRetentionMs: milliseconds(configuration.resultRetention),
                resumeToken: mutation.metadata.rotatedResumeToken
            ),
            mutation: mutation
        )
        lastHelloResult = result
        return result
    }

    @discardableResult
    func setMP008StaleExpectedStateVersionHook(
        targetSessionId: String,
        overriddenExpectedStateVersion: Int
    ) -> RoomDeterministicFaultHook {
        let hook = RoomDeterministicFaultHook(
            kind: .staleExpectedStateVersionOverride,
            targetSessionId: targetSessionId,
            overriddenExpectedStateVersion: overriddenExpectedStateVersion
        )
        deterministicFaultHook = hook
        return hook
    }

    func clearDeterministicFaultHook() {
        deterministicFaultHook = nil
    }

    private func helloParticipant(
        roomId: String,
        role: RoomMemberRole,
        connectionId: String?,
        lastAckedRoomSequence: Int?,
        lastAckedGameEventId: String?,
        lastSeenStateVersion: Int?
    ) throws -> LocalRoomDebugHelloResult {
        let snapshot = try requireSnapshot(roomId: roomId)
        let session = try participant(snapshot: snapshot, role: role)
        return try hello(
            roomId: roomId,
            sessionId: session.sessionId,
            playerId: session.playerId,
            deviceId: session.deviceId,
            connectionId: connectionId,
            resumeToken: session.resumeToken,
            lastAckedRoomSequence: lastAckedRoomSequence ?? snapshot.room.lastRoomSequence,
            lastAckedGameEventId: lastAckedGameEventId,
            lastSeenStateVersion: lastSeenStateVersion
        )
    }

    private func participant(roomId: String, role: RoomMemberRole) throws -> RoomSession {
        try participant(snapshot: try requireSnapshot(roomId: roomId), role: role)
    }

    private func participant(snapshot: RoomCoordinatorSnapshot, role: RoomMemberRole) throws -> RoomSession {
        guard let member = snapshot.room.members.first(where: { $0.role == role }) else {
            throw RoomCoordinatorError.playerNotInRoom(
                playerId: role == .host ? snapshot.room.hostPlayerId : "guest",
                roomId: snapshot.room.roomId
            )
        }
        guard let session = snapshot.sessions.first(where: { $0.sessionId == member.sessionId }) else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: member.sessionId)
        }
        return session
    }

    private func requireSnapshot(roomId: String) throws -> RoomCoordinatorSnapshot {
        guard let snapshot = coordinator.snapshot(for: roomId) else {
            throw RoomCoordinatorError.roomNotFound(roomId: roomId)
        }
        return snapshot
    }

    private func defaultDebugGameID(roomId: String) -> String {
        let nextOrdinal = (coordinator.snapshot(for: roomId)?.room.lastRoomSequence ?? 0) + 1
        return "debug_game_\(roomId)_\(nextOrdinal)"
    }

    private func apply(_ mutation: RoomCoordinatorMutation) -> RoomCoordinatorMutation {
        snapshotsByRoomId[mutation.snapshot.room.roomId] = mutation.snapshot
        lastMutation = mutation
        return mutation
    }

    private func milliseconds(_ value: TimeInterval) -> Int {
        Int(value * 1000)
    }
}

@MainActor
enum MultiplayerDebugServices {
    static let roomCoordinator = LocalRoomCoordinatorDebugService.shared
}
#endif
