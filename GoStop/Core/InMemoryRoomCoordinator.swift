import Foundation

final class InMemoryRoomCoordinator: RoomLifecycleCoordinating {
    private let configuration: RoomCoordinatorConfiguration
    private let now: () -> Date

    private var rooms: [String: Room] = [:]
    private var sessions: [String: RoomSession] = [:]
    private var counters: [String: Int] = [:]

    init(
        configuration: RoomCoordinatorConfiguration = .phase0,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.now = now
    }

    func createRoom(_ request: CreateRoomRequest) throws -> RoomCoordinatorMutation {
        let createdAt = now()
        let roomId = nextID(prefix: "room")
        let sessionId = nextID(prefix: "sess")
        let resumeToken = nextID(prefix: "resume")
        let initialSequence = 0

        let hostMember = RoomMember(
            playerId: request.hostPlayerId,
            seat: 0,
            role: .host,
            ready: false,
            presence: .connected,
            sessionId: sessionId,
            connectedConnectionId: nil,
            joinedAt: createdAt
        )
        let room = Room(
            roomId: roomId,
            roomType: request.roomType,
            joinPolicy: request.joinPolicy,
            roomState: .waitingForPlayers,
            hostPlayerId: request.hostPlayerId,
            activeGameId: nil,
            members: [hostMember],
            deadlines: RoomDeadlines(
                joinExpiresAt: createdAt.addingTimeInterval(configuration.joinTTL),
                readyExpiresAt: nil,
                resultExpiresAt: nil
            ),
            lastRoomSequence: initialSequence,
            createdAt: createdAt,
            closedAt: nil
        )
        let session = RoomSession(
            sessionId: sessionId,
            playerId: request.hostPlayerId,
            roomId: roomId,
            deviceId: request.deviceId,
            connectionState: .connected,
            connectionId: nil,
            resumeToken: resumeToken,
            resumeIssuedAt: createdAt,
            graceExpiresAt: nil,
            lastHeartbeatAt: createdAt,
            lastAckedRoomSequence: initialSequence,
            lastAckedGameEventId: nil,
            lastSeenStateVersion: nil
        )

        rooms[roomId] = room
        sessions[sessionId] = session

        return mutation(
            action: .createRoom,
            room: room,
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: resumeToken,
                supersededConnectionId: nil,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func joinRoom(_ request: JoinRoomRequest) throws -> RoomCoordinatorMutation {
        let joinedAt = now()
        var room = try requireRoom(request.roomId)
        try ensureRoomOpenForJoin(room)
        if room.members.contains(where: { $0.playerId == request.playerId }) {
            throw RoomCoordinatorError.playerAlreadyInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        let guestSeats = room.members.count
        guard guestSeats < 2 else {
            throw RoomCoordinatorError.roomFull(roomId: request.roomId)
        }

        let previousState = room.roomState
        let sessionId = nextID(prefix: "sess")
        let resumeToken = nextID(prefix: "resume")
        let guestMember = RoomMember(
            playerId: request.playerId,
            seat: guestSeats,
            role: .guest,
            ready: false,
            presence: .connected,
            sessionId: sessionId,
            connectedConnectionId: nil,
            joinedAt: joinedAt
        )
        room.members.append(guestMember)
        room.deadlines.joinExpiresAt = nil
        room.deadlines.readyExpiresAt = joinedAt.addingTimeInterval(configuration.readyWindow)
        room.roomState = .waitingForReady

        let session = RoomSession(
            sessionId: sessionId,
            playerId: request.playerId,
            roomId: request.roomId,
            deviceId: request.deviceId,
            connectionState: .connected,
            connectionId: nil,
            resumeToken: resumeToken,
            resumeIssuedAt: joinedAt,
            graceExpiresAt: nil,
            lastHeartbeatAt: joinedAt,
            lastAckedRoomSequence: room.lastRoomSequence,
            lastAckedGameEventId: nil,
            lastSeenStateVersion: nil
        )
        sessions[sessionId] = session

        var events = [RoomCoordinatorEvent]()
        events.append(makeEvent(for: &room, at: joinedAt, payload: .memberJoined(playerId: request.playerId, seat: guestSeats, role: .guest)))
        if previousState != room.roomState {
            events.append(makeEvent(for: &room, at: joinedAt, payload: .roomStateChanged(from: previousState, to: room.roomState, reason: .guestJoined)))
        }

        rooms[room.roomId] = room
        return mutation(
            action: .joinRoom,
            room: room,
            events: events,
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: resumeToken,
                supersededConnectionId: nil,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func setReady(_ request: SetReadyRequest) throws -> RoomCoordinatorMutation {
        let changedAt = now()
        var room = try requireRoom(request.roomId)
        guard room.roomState == .waitingForReady else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.waitingForReady], actual: room.roomState)
        }
        guard room.members.count == 2 else {
            throw RoomCoordinatorError.readyRequiresTwoMembers
        }

        guard let memberIndex = room.members.firstIndex(where: { $0.playerId == request.playerId }) else {
            throw RoomCoordinatorError.playerNotInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        if room.members[memberIndex].ready == request.ready {
            rooms[room.roomId] = room
            return mutation(action: .setReady, room: room)
        }

        let previousState = room.roomState
        room.members[memberIndex].ready = request.ready

        var events = [RoomCoordinatorEvent]()
        events.append(makeEvent(for: &room, at: changedAt, payload: .memberReadyChanged(playerId: request.playerId, ready: request.ready)))

        let allReady = room.members.count == 2 && room.members.allSatisfy(\.ready)
        var requiresGameBootstrap = false
        if allReady {
            room.roomState = .starting
            room.deadlines.readyExpiresAt = nil
            requiresGameBootstrap = true
            events.append(makeEvent(for: &room, at: changedAt, payload: .roomStateChanged(from: previousState, to: .starting, reason: .readyCompleted)))
        }

        rooms[room.roomId] = room
        return mutation(
            action: .setReady,
            room: room,
            events: events,
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: requiresGameBootstrap,
                rotatedResumeToken: nil,
                supersededConnectionId: nil,
                gameStartControlMode: requiresGameBootstrap ? .explicitRecordGameStarted : nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func attachSession(_ request: AttachSessionRequest) throws -> RoomCoordinatorMutation {
        let attachedAt = now()
        var room = try requireRoom(request.roomId)
        guard let memberIndex = room.members.firstIndex(where: { $0.playerId == request.playerId }) else {
            throw RoomCoordinatorError.playerNotInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        guard var session = sessions[request.sessionId] else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: request.sessionId)
        }
        guard session.roomId == request.roomId, session.playerId == request.playerId else {
            throw RoomCoordinatorError.resumeTokenInvalid
        }
        guard session.resumeToken == request.resumeToken else {
            throw RoomCoordinatorError.resumeTokenInvalid
        }
        guard session.connectionState != .expired else {
            throw RoomCoordinatorError.resumeExpired
        }
        guard session.connectionState != .disconnectedGrace else {
            throw RoomCoordinatorError.invalidResumeState(session.connectionState)
        }

        let previousConnectionId = session.connectionId
        let rotatedToken = nextID(prefix: "resume")

        session.connectionState = .connected
        session.deviceId = request.deviceId
        session.connectionId = request.connectionId
        session.resumeToken = rotatedToken
        session.resumeIssuedAt = attachedAt
        session.graceExpiresAt = nil
        session.lastHeartbeatAt = attachedAt
        session.lastAckedRoomSequence = request.lastAckedRoomSequence ?? session.lastAckedRoomSequence
        session.lastAckedGameEventId = request.lastAckedGameEventId ?? session.lastAckedGameEventId
        session.lastSeenStateVersion = request.lastSeenStateVersion ?? session.lastSeenStateVersion
        sessions[session.sessionId] = session

        room.members[memberIndex].presence = .connected
        room.members[memberIndex].connectedConnectionId = request.connectionId
        rooms[room.roomId] = room

        return mutation(
            action: .attachSession,
            room: room,
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: rotatedToken,
                supersededConnectionId: previousConnectionId == request.connectionId ? nil : previousConnectionId,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func disconnectMember(_ request: DisconnectMemberRequest) throws -> RoomCoordinatorMutation {
        let disconnectedAt = now()
        var room = try requireRoom(request.roomId)

        guard let memberIndex = room.members.firstIndex(where: { $0.playerId == request.playerId }) else {
            throw RoomCoordinatorError.playerNotInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        let sessionId = room.members[memberIndex].sessionId
        guard var session = sessions[sessionId] else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: sessionId)
        }

        session.connectionState = .disconnectedGrace
        session.connectionId = nil
        session.graceExpiresAt = disconnectedAt.addingTimeInterval(configuration.reconnectGrace)
        session.lastHeartbeatAt = disconnectedAt
        sessions[sessionId] = session

        room.members[memberIndex].presence = .disconnected
        room.members[memberIndex].connectedConnectionId = nil

        let event = makeEvent(
            for: &room,
            at: disconnectedAt,
            payload: .playerDisconnected(
                playerId: request.playerId,
                graceExpiresAt: session.graceExpiresAt ?? disconnectedAt
            )
        )
        rooms[room.roomId] = room
        return mutation(action: .disconnectMember, room: room, events: [event])
    }

    func leaveRoom(_ request: LeaveRoomRequest) throws -> RoomCoordinatorMutation {
        let leftAt = now()
        var room = try requireRoom(request.roomId)

        guard let memberIndex = room.members.firstIndex(where: { $0.playerId == request.playerId }) else {
            throw RoomCoordinatorError.playerNotInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        let previousState = room.roomState
        let sessionId = room.members[memberIndex].sessionId
        if var session = sessions[sessionId] {
            session.connectionState = .expired
            session.connectionId = nil
            session.graceExpiresAt = nil
            session.lastHeartbeatAt = leftAt
            sessions[sessionId] = session
        }

        var events: [RoomCoordinatorEvent] = []
        let playerId = room.members[memberIndex].playerId

        switch room.roomState {
        case .waitingForPlayers:
            room.members[memberIndex].presence = .left
            room.roomState = .closed
            room.closedAt = leftAt
            events.append(makeEvent(for: &room, at: leftAt, payload: .memberLeft(playerId: playerId, reason: .hostLeft)))
            events.append(makeEvent(for: &room, at: leftAt, payload: .roomClosed(reason: .hostLeft, closedAt: leftAt)))
        case .waitingForReady:
            if room.members[memberIndex].role == .host {
                room.members[memberIndex].presence = .left
                room.roomState = .closed
                room.closedAt = leftAt
                events.append(makeEvent(for: &room, at: leftAt, payload: .memberLeft(playerId: playerId, reason: .hostLeft)))
                events.append(makeEvent(for: &room, at: leftAt, payload: .roomClosed(reason: .hostLeft, closedAt: leftAt)))
            } else {
                room.members.remove(at: memberIndex)
                room.roomState = .waitingForPlayers
                room.deadlines.readyExpiresAt = nil
                room.deadlines.joinExpiresAt = leftAt.addingTimeInterval(configuration.joinTTL)
                events.append(makeEvent(for: &room, at: leftAt, payload: .memberLeft(playerId: playerId, reason: .explicitClose)))
                events.append(makeEvent(for: &room, at: leftAt, payload: .roomStateChanged(from: previousState, to: .waitingForPlayers, reason: .guestReleased)))
            }
        case .starting, .inGame:
            room.members[memberIndex].presence = .forfeitPending
            room.roomState = .ended
            room.deadlines.resultExpiresAt = leftAt.addingTimeInterval(configuration.resultRetention)
            events.append(makeEvent(for: &room, at: leftAt, payload: .playerForfeited(playerId: playerId, reason: .explicitLeave)))
            events.append(makeEvent(for: &room, at: leftAt, payload: .roomStateChanged(from: previousState, to: .ended, reason: .forfeit)))
        case .ended:
            room.members[memberIndex].presence = .left
            events.append(makeEvent(for: &room, at: leftAt, payload: .memberLeft(playerId: playerId, reason: .explicitClose)))
            if room.members.allSatisfy({ $0.playerId == playerId ? true : $0.presence == .left }) {
                room.roomState = .closed
                room.closedAt = leftAt
                room.deadlines.resultExpiresAt = nil
                events.append(makeEvent(for: &room, at: leftAt, payload: .roomClosed(reason: .allPlayersLeft, closedAt: leftAt)))
            }
        case .closed:
            throw RoomCoordinatorError.roomClosed(roomId: room.roomId)
        }

        rooms[room.roomId] = room
        return mutation(action: .leaveRoom, room: room, events: events)
    }

    func closeRoom(_ request: CloseRoomRequest) throws -> RoomCoordinatorMutation {
        let closedAt = now()
        var room = try requireRoom(request.roomId)
        guard room.roomState == .waitingForPlayers || room.roomState == .waitingForReady || room.roomState == .ended else {
            throw RoomCoordinatorError.closeRequiresHostOrTerminalState
        }

        room.roomState = .closed
        room.closedAt = closedAt
        room.deadlines.joinExpiresAt = nil
        room.deadlines.readyExpiresAt = nil
        room.deadlines.resultExpiresAt = nil

        let event = makeEvent(for: &room, at: closedAt, payload: .roomClosed(reason: .explicitClose, closedAt: closedAt))
        rooms[room.roomId] = room
        return mutation(action: .closeRoom, room: room, events: [event])
    }

    func resumeSession(_ request: ResumeSessionRequest) throws -> RoomCoordinatorMutation {
        let resumedAt = now()
        var room = try requireRoom(request.roomId)
        guard let memberIndex = room.members.firstIndex(where: { $0.playerId == request.playerId }) else {
            throw RoomCoordinatorError.playerNotInRoom(playerId: request.playerId, roomId: request.roomId)
        }

        guard var session = sessions[request.sessionId] else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: request.sessionId)
        }
        guard session.roomId == request.roomId, session.playerId == request.playerId else {
            throw RoomCoordinatorError.resumeTokenInvalid
        }
        guard session.resumeToken == request.resumeToken else {
            throw RoomCoordinatorError.resumeTokenInvalid
        }
        if let graceExpiresAt = session.graceExpiresAt, graceExpiresAt < resumedAt {
            session.connectionState = .expired
            sessions[session.sessionId] = session
            throw RoomCoordinatorError.resumeExpired
        }
        guard session.connectionState != .expired else {
            throw RoomCoordinatorError.resumeExpired
        }
        guard session.connectionState == .disconnectedGrace else {
            throw RoomCoordinatorError.invalidResumeState(session.connectionState)
        }

        let previousConnectionId = session.connectionId
        let rotatedToken = nextID(prefix: "resume")

        session.connectionState = .connected
        session.deviceId = request.deviceId
        session.connectionId = request.connectionId
        session.resumeToken = rotatedToken
        session.resumeIssuedAt = resumedAt
        session.graceExpiresAt = nil
        session.lastHeartbeatAt = resumedAt
        session.lastAckedRoomSequence = request.lastAckedRoomSequence ?? session.lastAckedRoomSequence
        session.lastAckedGameEventId = request.lastAckedGameEventId ?? session.lastAckedGameEventId
        session.lastSeenStateVersion = request.lastSeenStateVersion ?? session.lastSeenStateVersion
        sessions[session.sessionId] = session

        room.members[memberIndex].presence = .connected
        room.members[memberIndex].connectedConnectionId = request.connectionId

        let event = makeEvent(
            for: &room,
            at: resumedAt,
            payload: .playerReconnected(playerId: request.playerId, connectionId: request.connectionId)
        )
        rooms[room.roomId] = room

        return mutation(
            action: .resumeSession,
            room: room,
            events: [event],
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: rotatedToken,
                supersededConnectionId: previousConnectionId == request.connectionId ? nil : previousConnectionId,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func recordHeartbeat(_ request: RecordHeartbeatRequest) throws -> RoomCoordinatorMutation {
        let heartbeatAt = now()
        var room = try requireRoom(request.roomId)
        guard var session = sessions[request.sessionId] else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: request.sessionId)
        }
        guard session.roomId == request.roomId else {
            throw RoomCoordinatorError.sessionNotFound(sessionId: request.sessionId)
        }
        guard session.connectionState == .connected else {
            throw RoomCoordinatorError.invalidResumeState(session.connectionState)
        }
        guard let currentConnectionId = session.connectionId else {
            throw RoomCoordinatorError.staleConnectionId(expected: nil, actual: request.connectionId)
        }
        guard request.connectionId == currentConnectionId else {
            throw RoomCoordinatorError.staleConnectionId(expected: currentConnectionId, actual: request.connectionId)
        }

        session.lastHeartbeatAt = heartbeatAt
        session.lastAckedRoomSequence = request.lastAckedRoomSequence ?? session.lastAckedRoomSequence
        session.lastAckedGameEventId = request.lastAckedGameEventId ?? session.lastAckedGameEventId
        session.lastSeenStateVersion = request.lastSeenStateVersion ?? session.lastSeenStateVersion
        sessions[session.sessionId] = session

        if let memberIndex = room.members.firstIndex(where: { $0.sessionId == request.sessionId }) {
            room.members[memberIndex].connectedConnectionId = currentConnectionId
            rooms[room.roomId] = room
        }

        return mutation(action: .recordHeartbeat, room: room)
    }

    func recordGameStarted(_ request: RecordGameStartedRequest) throws -> RoomCoordinatorMutation {
        let startedAt = now()
        var room = try requireRoom(request.roomId)
        guard room.roomState == .starting else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.starting], actual: room.roomState)
        }

        let previousState = room.roomState
        room.roomState = .inGame
        room.activeGameId = request.gameId

        let event = makeEvent(
            for: &room,
            at: startedAt,
            payload: .roomStateChanged(from: previousState, to: .inGame, reason: .gameStarted)
        )
        rooms[room.roomId] = room
        let snapshot = RoomCoordinatorSnapshot(room: room, sessions: sessionsForRoom(room))
        return RoomCoordinatorMutation(
            action: .recordGameStarted,
            snapshot: snapshot,
            events: [event],
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: nil,
                supersededConnectionId: nil,
                gameStartControlMode: .explicitRecordGameStarted,
                gameStartedBootstrapPlan: makeGameStartedBootstrapPlan(from: snapshot),
                terminalSummaryRelayRequest: nil
            )
        )
    }

    func recordMatchEnded(_ request: RecordMatchEndedRequest) throws -> RoomCoordinatorMutation {
        let endedAt = now()
        var room = try requireRoom(request.roomId)
        guard room.roomState == .starting || room.roomState == .inGame else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.starting, .inGame], actual: room.roomState)
        }

        let previousState = room.roomState
        room.roomState = .ended
        room.deadlines.resultExpiresAt = request.resultRetentionAt ?? endedAt.addingTimeInterval(configuration.resultRetention)

        var events: [RoomCoordinatorEvent] = []
        if let forfeitingPlayerId = request.forfeitingPlayerId {
            if let memberIndex = room.members.firstIndex(where: { $0.playerId == forfeitingPlayerId }) {
                room.members[memberIndex].presence = .forfeitPending
                events.append(makeEvent(for: &room, at: endedAt, payload: .playerForfeited(playerId: forfeitingPlayerId, reason: .explicitLeave)))
            }
        }

        events.append(
            makeEvent(
                for: &room,
                at: endedAt,
                payload: .roomStateChanged(from: previousState, to: .ended, reason: .matchEnded)
            )
        )
        rooms[room.roomId] = room
        let snapshot = RoomCoordinatorSnapshot(room: room, sessions: sessionsForRoom(room))
        return RoomCoordinatorMutation(
            action: .recordMatchEnded,
            snapshot: snapshot,
            events: events,
            metadata: RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: nil,
                supersededConnectionId: nil,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: makeTerminalSummaryRelayRequest(
                    from: snapshot,
                    roundIndex: request.roundIndex ?? 1,
                    quitReason: request.quitReason,
                    forfeitingPlayerId: request.forfeitingPlayerId,
                    summaryStateVersion: request.summaryStateVersion ?? 0,
                    lastEventId: request.lastEventId
                )
            )
        )
    }

    func reapExpiredState(asOf: Date) throws -> [RoomCoordinatorMutation] {
        var mutations: [RoomCoordinatorMutation] = []
        let roomIDs = Array(rooms.keys).sorted()

        for roomId in roomIDs {
            guard var room = rooms[roomId] else { continue }
            var events: [RoomCoordinatorEvent] = []
            let metadata = RoomCoordinatorMutationMetadata(
                requiresGameBootstrap: false,
                rotatedResumeToken: nil,
                supersededConnectionId: nil,
                gameStartControlMode: nil,
                gameStartedBootstrapPlan: nil,
                terminalSummaryRelayRequest: nil
            )

            if room.roomState == .waitingForPlayers,
               let joinExpiresAt = room.deadlines.joinExpiresAt,
               joinExpiresAt <= asOf {
                room.roomState = .closed
                room.closedAt = asOf
                room.deadlines.joinExpiresAt = nil
                events.append(makeEvent(for: &room, at: asOf, payload: .roomClosed(reason: .idleExpired, closedAt: asOf)))
            }

            if room.roomState == .waitingForReady,
               let readyExpiresAt = room.deadlines.readyExpiresAt,
               readyExpiresAt <= asOf {
                let resetPlayerIds = room.members.map(\.playerId)
                for index in room.members.indices {
                    room.members[index].ready = false
                }
                room.deadlines.readyExpiresAt = asOf.addingTimeInterval(configuration.readyWindow)
                events.append(makeEvent(for: &room, at: asOf, payload: .readyWindowExpired(resetPlayerIds: resetPlayerIds)))
            }

            let sessionIDs = room.members.map(\.sessionId)
            for sessionId in sessionIDs {
                guard var session = sessions[sessionId], session.connectionState == .disconnectedGrace else {
                    continue
                }
                guard let graceExpiresAt = session.graceExpiresAt, graceExpiresAt <= asOf else {
                    continue
                }
                session.connectionState = .expired
                session.graceExpiresAt = nil
                sessions[sessionId] = session

                guard let memberIndex = room.members.firstIndex(where: { $0.sessionId == sessionId }) else {
                    continue
                }

                switch room.roomState {
                case .waitingForPlayers:
                    if room.members[memberIndex].role == .host {
                        room.roomState = .closed
                        room.closedAt = asOf
                        events.append(makeEvent(for: &room, at: asOf, payload: .roomClosed(reason: .hostLeft, closedAt: asOf)))
                    }
                case .waitingForReady:
                    if room.members[memberIndex].role == .guest {
                        room.members.remove(at: memberIndex)
                        room.roomState = .waitingForPlayers
                        room.deadlines.readyExpiresAt = nil
                        room.deadlines.joinExpiresAt = asOf.addingTimeInterval(configuration.joinTTL)
                        events.append(makeEvent(for: &room, at: asOf, payload: .roomStateChanged(from: .waitingForReady, to: .waitingForPlayers, reason: .guestReleased)))
                    } else {
                        room.roomState = .closed
                        room.closedAt = asOf
                        events.append(makeEvent(for: &room, at: asOf, payload: .roomClosed(reason: .hostLeft, closedAt: asOf)))
                    }
                case .starting, .inGame:
                    let playerId = room.members[memberIndex].playerId
                    room.members[memberIndex].presence = .forfeitPending
                    let previousState = room.roomState
                    room.roomState = .ended
                    room.deadlines.resultExpiresAt = asOf.addingTimeInterval(configuration.resultRetention)
                    events.append(makeEvent(for: &room, at: asOf, payload: .playerForfeited(playerId: playerId, reason: .disconnectTimeout)))
                    events.append(makeEvent(for: &room, at: asOf, payload: .roomStateChanged(from: previousState, to: .ended, reason: .forfeit)))
                case .ended:
                    break
                case .closed:
                    break
                }
            }

            if room.roomState == .ended,
               let resultExpiresAt = room.deadlines.resultExpiresAt,
               resultExpiresAt <= asOf {
                room.roomState = .closed
                room.closedAt = asOf
                room.deadlines.resultExpiresAt = nil
                events.append(makeEvent(for: &room, at: asOf, payload: .roomClosed(reason: .resultExpired, closedAt: asOf)))
            }

            rooms[room.roomId] = room
            if !events.isEmpty {
                mutations.append(
                    mutation(
                        action: .reapExpiredState,
                        room: room,
                        events: events,
                        metadata: metadata
                    )
                )
            }
        }

        return mutations
    }

    func snapshot(for roomId: String) -> RoomCoordinatorSnapshot? {
        guard let room = rooms[roomId] else {
            return nil
        }
        return RoomCoordinatorSnapshot(room: room, sessions: sessionsForRoom(room))
    }

    private func mutation(
        action: RoomCoordinatorAction,
        room: Room,
        events: [RoomCoordinatorEvent] = [],
        metadata: RoomCoordinatorMutationMetadata = RoomCoordinatorMutationMetadata(
            requiresGameBootstrap: false,
            rotatedResumeToken: nil,
            supersededConnectionId: nil,
            gameStartControlMode: nil,
            gameStartedBootstrapPlan: nil,
            terminalSummaryRelayRequest: nil
        )
    ) -> RoomCoordinatorMutation {
        RoomCoordinatorMutation(
            action: action,
            snapshot: RoomCoordinatorSnapshot(room: room, sessions: sessionsForRoom(room)),
            events: events,
            metadata: metadata
        )
    }

    private func requireRoom(_ roomId: String) throws -> Room {
        guard let room = rooms[roomId] else {
            throw RoomCoordinatorError.roomNotFound(roomId: roomId)
        }
        return room
    }

    private func ensureRoomOpenForJoin(_ room: Room) throws {
        if room.roomState == .closed {
            throw RoomCoordinatorError.roomClosed(roomId: room.roomId)
        }
        guard room.roomState == .waitingForPlayers || room.roomState == .waitingForReady else {
            throw RoomCoordinatorError.invalidRoomState(expected: [.waitingForPlayers, .waitingForReady], actual: room.roomState)
        }
    }

    private func sessionsForRoom(_ room: Room) -> [RoomSession] {
        let activeSessionIDs = Set(room.members.map(\.sessionId))
        return sessions.values
            .filter { activeSessionIDs.contains($0.sessionId) }
            .sorted { lhs, rhs in
                if lhs.playerId == rhs.playerId {
                    return lhs.sessionId < rhs.sessionId
                }
                return lhs.playerId < rhs.playerId
            }
    }

    private func makeEvent(
        for room: inout Room,
        at occurredAt: Date,
        payload: RoomCoordinatorEventPayload
    ) -> RoomCoordinatorEvent {
        room.lastRoomSequence += 1
        return RoomCoordinatorEvent(
            roomId: room.roomId,
            roomSequence: room.lastRoomSequence,
            occurredAt: occurredAt,
            payload: payload
        )
    }

    private func nextID(prefix: String) -> String {
        let nextValue = (counters[prefix] ?? 0) + 1
        counters[prefix] = nextValue
        return "\(prefix)_\(String(format: "%04d", nextValue))"
    }
}
