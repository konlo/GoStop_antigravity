import Foundation

enum MultiplayerPhase: String, Codable {
    case waiting
    case dealing
    case inTurn
    case choicePending
    case roundEnded
    case matchEnded
    case paused
}

enum MultiplayerCommandName: String, Codable {
    case playCard
    case selectCapture
    case selectShake
    case chooseGoStop
    case chooseChrysanthemumRole
    case resume
    case quit
}

enum MultiplayerEventName: String, Codable {
    case gameStarted
    case actionAccepted
    case actionRejected
    case turnChanged
    case choiceRequested
    case statePatched
    case stateSnapshot
    case roundEnded
    case matchEnded
}

enum MultiplayerContractChoiceKind: String, Codable {
    case capture
    case shake
    case goStop
    case chrysanthemumRole
}

enum MultiplayerChoiceVisibility: String, Codable {
    case allParticipants
    case actorOnly
}

enum MultiplayerRejectCode: String, Codable {
    case outOfTurn
    case invalidPhase
    case staleStateVersion
    case invalidCard
    case invalidChoice
    case choiceExpired
    case choiceOwnerMismatch
    case actionIdConflict
    case notParticipant
    case resumeExpired
    case gameNotResumable
    case invalidState
}

enum MultiplayerDuplicateActionIdDisposition: String, Codable {
    case exactReplay
    case conflictReject
}

enum MultiplayerProjectionScope: String, Codable {
    case player
    case authority
}

enum MultiplayerPresenceSource: String, Codable {
    case roomSnapshot
    case localPreview
    case unknown
}

enum MultiplayerSnapshotReason: String, Codable {
    case gameStarted
    case resume
    case resync
    case gapDetected
    case localPreview
}

enum MultiplayerRecoverySnapshotReason: String, Codable {
    case resync
    case gapDetected
}

enum MultiplayerResyncTrigger: String, Codable {
    case staleStateVersionReject
    case patchBaseMismatch
    case gameEventGap
}

enum MultiplayerPatchFormat: String, Codable {
    case jsonPatch = "json-patch"
}

enum MultiplayerQuitReason: String, Codable {
    case voluntaryExit
    case disconnectTimeout
    case adminForfeit
}

enum MultiplayerMatchEndReason: String, Codable {
    case stop
    case maxScore
    case nagari
    case chongtong
    case threeSeolsa
    case voluntaryQuit
    case disconnectTimeout
    case adminForfeit
}

enum MultiplayerReplayRetentionPolicy: String, Codable {
    case privilegedDebugOnly
}

struct MultiplayerCommand: Codable {
    let name: MultiplayerCommandName
    let payload: [String: AnyCodable]
}

struct MultiplayerCommandEnvelope: Codable {
    let type: String
    let traceId: String?
    let requestId: String
    let roomId: String?
    let gameId: String
    let playerId: String
    let actionId: String
    let expectedStateVersion: Int
    let sentAt: String?
    let command: MultiplayerCommand

    init(
        traceId: String?,
        requestId: String,
        roomId: String?,
        gameId: String,
        playerId: String,
        actionId: String,
        expectedStateVersion: Int,
        sentAt: String?,
        command: MultiplayerCommand
    ) {
        self.type = "command"
        self.traceId = traceId
        self.requestId = requestId
        self.roomId = roomId
        self.gameId = gameId
        self.playerId = playerId
        self.actionId = actionId
        self.expectedStateVersion = expectedStateVersion
        self.sentAt = sentAt
        self.command = command
    }
}

struct MultiplayerPlayCardPayload: Codable {
    let cardId: String
    let source: String
}

struct MultiplayerChoiceCommandPayload: Codable {
    let choiceId: String
    let optionCode: String
}

struct MultiplayerResumePayload: Codable {
    let resumeToken: String
    let lastKnownEventId: String?
    let lastKnownStateVersion: Int
}

struct MultiplayerQuitPayload: Codable {
    let reason: MultiplayerQuitReason
}

struct MultiplayerEventEnvelope<Payload: Codable>: Codable {
    let type: String
    let traceId: String?
    let roomId: String?
    let gameId: String
    let eventId: String
    let stateVersion: Int
    let causedByActionId: String?
    let serverTime: String?
    let eventName: MultiplayerEventName
    let payload: Payload

    init(
        traceId: String?,
        roomId: String?,
        gameId: String,
        eventId: String,
        stateVersion: Int,
        causedByActionId: String?,
        serverTime: String?,
        eventName: MultiplayerEventName,
        payload: Payload
    ) {
        self.type = "event"
        self.traceId = traceId
        self.roomId = roomId
        self.gameId = gameId
        self.eventId = eventId
        self.stateVersion = stateVersion
        self.causedByActionId = causedByActionId
        self.serverTime = serverTime
        self.eventName = eventName
        self.payload = payload
    }
}

struct MultiplayerRejectReason: Codable {
    let code: MultiplayerRejectCode
    let retryable: Bool
    let messageKey: String
    let details: [String: AnyCodable]?
}

struct MultiplayerResyncDirective: Codable {
    let trigger: MultiplayerResyncTrigger
    let snapshotReason: MultiplayerRecoverySnapshotReason
    let clientStateVersion: Int?
    let expectedStateVersion: Int?
    let authoritativeStateVersion: Int
    let clientEventId: String?
    let authoritativeEventId: String?
    let shouldLockInput: Bool
}

struct MultiplayerStaleStateVersionRejectDetails: Codable {
    let expectedStateVersion: Int
    let authoritativeStateVersion: Int
    let authoritativeEventId: String?
    let resync: MultiplayerResyncDirective
}

struct MultiplayerPatchGapResyncDetails: Codable {
    let localStateVersion: Int
    let patchBaseStateVersion: Int
    let patchTargetStateVersion: Int
    let authoritativeEventId: String?
    let resync: MultiplayerResyncDirective
}

struct MultiplayerActionAcceptedPayload: Codable {
    let requestId: String?
    let actionId: String
    let playerId: String
    let commandName: MultiplayerCommandName
    let result: [String: AnyCodable]?
}

struct MultiplayerActionRejectedPayload: Codable {
    let requestId: String?
    let actionId: String
    let playerId: String
    let commandName: MultiplayerCommandName
    let rejectReason: MultiplayerRejectReason
}

struct MultiplayerTurnChangedPayload: Codable {
    let turnId: String
    let currentPlayerId: String
    let turnDeadlineAt: String?
}

struct MultiplayerGameStartedPayload: Codable {
    let roundIndex: Int
    let dealerPlayerId: String?
    let starterPlayerId: String?
    let firstPlayerId: String?
    let snapshotId: String
    let snapshotStateVersion: Int

    init(
        roundIndex: Int,
        dealerPlayerId: String?,
        starterPlayerId: String? = nil,
        firstPlayerId: String?,
        snapshotId: String,
        snapshotStateVersion: Int
    ) {
        self.roundIndex = roundIndex
        self.dealerPlayerId = dealerPlayerId
        self.starterPlayerId = starterPlayerId
        self.firstPlayerId = firstPlayerId
        self.snapshotId = snapshotId
        self.snapshotStateVersion = snapshotStateVersion
    }
}

struct MultiplayerGameStartedBootstrapPayload: Codable {
    let gameStarted: MultiplayerGameStartedPayload
    let stateSnapshot: MultiplayerSnapshot
}

struct MultiplayerLiveBootstrapPayload: Codable {
    let activeGameId: String
    let gameStarted: MultiplayerGameStartedPayload
    let stateSnapshot: MultiplayerSnapshot
}

struct MultiplayerRoundEndedPayload: Codable {
    let roundIndex: Int
    let summary: MultiplayerRoundSummary
}

struct MultiplayerMatchEndedPayload: Codable {
    let roundIndex: Int
    let winnerPlayerId: String?
    let loserPlayerId: String?
    let finalScores: [MultiplayerPlayerScore]
    let settlementSummary: MultiplayerSettlementSummary?
    let endReason: MultiplayerMatchEndReason
    let endReasonMessageKey: String
    let forfeitingPlayerId: String?
    let isDraw: Bool

    init(
        roundIndex: Int = 1,
        winnerPlayerId: String?,
        loserPlayerId: String?,
        finalScores: [MultiplayerPlayerScore],
        settlementSummary: MultiplayerSettlementSummary?,
        endReason: MultiplayerMatchEndReason,
        endReasonMessageKey: String,
        forfeitingPlayerId: String?,
        isDraw: Bool
    ) {
        self.roundIndex = roundIndex
        self.winnerPlayerId = winnerPlayerId
        self.loserPlayerId = loserPlayerId
        self.finalScores = finalScores
        self.settlementSummary = settlementSummary
        self.endReason = endReason
        self.endReasonMessageKey = endReasonMessageKey
        self.forfeitingPlayerId = forfeitingPlayerId
        self.isDraw = isDraw
    }
}

struct MultiplayerTerminalSummaryPayload: Codable {
    let roomId: String?
    let gameId: String
    let summaryStateVersion: Int
    let lastEventId: String?
    let roundEnded: MultiplayerRoundEndedPayload
    let matchEnded: MultiplayerMatchEndedPayload
}

struct MultiplayerChoice: Codable {
    let choiceId: String
    let choiceKind: MultiplayerContractChoiceKind
    let visibility: MultiplayerChoiceVisibility
    let actorPlayerId: String
    let promptKey: String
    let requestedAt: String?
    let deadlineAt: String?
    let expiresAtStateVersion: Int
    let options: [MultiplayerChoiceOption]

    init(
        choiceId: String,
        choiceKind: MultiplayerContractChoiceKind,
        visibility: MultiplayerChoiceVisibility = .allParticipants,
        actorPlayerId: String,
        promptKey: String,
        requestedAt: String?,
        deadlineAt: String?,
        expiresAtStateVersion: Int,
        options: [MultiplayerChoiceOption]
    ) {
        self.choiceId = choiceId
        self.choiceKind = choiceKind
        self.visibility = visibility
        self.actorPlayerId = actorPlayerId
        self.promptKey = promptKey
        self.requestedAt = requestedAt
        self.deadlineAt = deadlineAt
        self.expiresAtStateVersion = expiresAtStateVersion
        self.options = options
    }
}

struct MultiplayerChoiceOption: Codable {
    let optionCode: String
    let labelKey: String
    let cards: [MultiplayerChoiceCard]
    let effectTags: [String]
    let scoreDeltaPreview: MultiplayerScoreDeltaPreview?
    let metadata: [String: AnyCodable]?
}

struct MultiplayerChoiceCard: Codable {
    let cardId: String
    let zone: String
    let month: Int
    let kind: String
    let imageIndex: Int
    let selectedRole: String?
}

struct MultiplayerScoreDeltaPreview: Codable {
    let selfDelta: Int
    let opponentDelta: Int

    enum CodingKeys: String, CodingKey {
        case selfDelta = "self"
        case opponentDelta = "opponent"
    }
}

struct MultiplayerJSONPatchOperation: Codable {
    let op: String
    let path: String
    let value: AnyCodable?

    init(op: String, path: String, value: AnyCodable? = nil) {
        self.op = op
        self.path = path
        self.value = value
    }
}

struct MultiplayerPatch: Codable {
    let patchFormat: MultiplayerPatchFormat
    let baseStateVersion: Int
    let targetStateVersion: Int
    let ops: [MultiplayerJSONPatchOperation]
}

struct MultiplayerParticipantPresence: Codable {
    let source: MultiplayerPresenceSource
    let isConnected: Bool?
    let isReady: Bool?
}

struct MultiplayerPlayerIdentityBinding: Codable {
    let roomPlayerId: String
    let authorityPlayerId: String
}

struct MultiplayerProjectionContext: Codable {
    let traceId: String?
    let roomId: String?
    let gameId: String
    let stateVersion: Int
    let lastEventId: String?
    let turnId: String
    let snapshotId: String
    let serverTime: String?
    let snapshotReason: MultiplayerSnapshotReason
    let scope: MultiplayerProjectionScope
    let participantPresenceByPlayerId: [String: MultiplayerParticipantPresence]?
    let engineVersion: String
    let ruleConfigVersion: String

    init(
        traceId: String?,
        roomId: String?,
        gameId: String,
        stateVersion: Int,
        lastEventId: String?,
        turnId: String,
        snapshotId: String,
        serverTime: String?,
        snapshotReason: MultiplayerSnapshotReason,
        scope: MultiplayerProjectionScope,
        participantPresenceByPlayerId: [String: MultiplayerParticipantPresence]? = nil,
        engineVersion: String,
        ruleConfigVersion: String
    ) {
        self.traceId = traceId
        self.roomId = roomId
        self.gameId = gameId
        self.stateVersion = stateVersion
        self.lastEventId = lastEventId
        self.turnId = turnId
        self.snapshotId = snapshotId
        self.serverTime = serverTime
        self.snapshotReason = snapshotReason
        self.scope = scope
        self.participantPresenceByPlayerId = participantPresenceByPlayerId
        self.engineVersion = engineVersion
        self.ruleConfigVersion = ruleConfigVersion
    }
}

struct MultiplayerSnapshot: Codable {
    let snapshotId: String
    let reason: MultiplayerSnapshotReason
    let scope: MultiplayerProjectionScope
    let snapshotStateVersion: Int
    let lastIncludedEventId: String?
    let state: MultiplayerMatchSnapshot
}

struct MultiplayerMatchSnapshot: Codable {
    let traceId: String?
    let roomId: String?
    let gameId: String
    let viewerPlayerId: String?
    let engineVersion: String
    let ruleConfigVersion: String
    let stateVersion: Int
    let lastEventId: String?
    let phase: MultiplayerPhase
    let turnId: String
    let currentPlayerId: String?
    let dealerPlayerId: String?
    let starterPlayerId: String?
    let players: [MultiplayerPlayerProjection]
    let table: MultiplayerTableSnapshot
    let deck: MultiplayerDeckSnapshot
    let rngSeed: Int?
    let pendingChoice: MultiplayerChoice?
    let scoreboard: MultiplayerScoreboard
    let timers: MultiplayerTimers
    let resume: MultiplayerResumeState
    let lastActionEffect: String?
    let lastChat: MultiplayerChatPresence?

    init(
        traceId: String?,
        roomId: String?,
        gameId: String,
        viewerPlayerId: String?,
        engineVersion: String,
        ruleConfigVersion: String,
        stateVersion: Int,
        lastEventId: String?,
        phase: MultiplayerPhase,
        turnId: String,
        currentPlayerId: String?,
        dealerPlayerId: String?,
        starterPlayerId: String? = nil,
        players: [MultiplayerPlayerProjection],
        table: MultiplayerTableSnapshot,
        deck: MultiplayerDeckSnapshot,
        rngSeed: Int? = nil,
        pendingChoice: MultiplayerChoice?,
        scoreboard: MultiplayerScoreboard,
        timers: MultiplayerTimers,
        resume: MultiplayerResumeState,
        lastActionEffect: String? = nil,
        lastChat: MultiplayerChatPresence? = nil
    ) {
        self.traceId = traceId
        self.roomId = roomId
        self.gameId = gameId
        self.viewerPlayerId = viewerPlayerId
        self.engineVersion = engineVersion
        self.ruleConfigVersion = ruleConfigVersion
        self.stateVersion = stateVersion
        self.lastEventId = lastEventId
        self.phase = phase
        self.turnId = turnId
        self.currentPlayerId = currentPlayerId
        self.dealerPlayerId = dealerPlayerId
        self.starterPlayerId = starterPlayerId
        self.players = players
        self.table = table
        self.deck = deck
        self.rngSeed = rngSeed
        self.pendingChoice = pendingChoice
        self.scoreboard = scoreboard
        self.timers = timers
        self.resume = resume
        self.lastActionEffect = lastActionEffect
        self.lastChat = lastChat
    }
}

struct MultiplayerPlayerProjection: Codable {
    let playerId: String
    let seatIndex: Int
    let name: String
    let hand: [MultiplayerCardSummary]?
    let handCount: Int
    let captured: MultiplayerCapturedCards
    let score: Int
    let money: Int
    let goCount: Int
    let shakeCount: Int
    let isConnected: Bool?
    let isReady: Bool?
    let presenceSource: MultiplayerPresenceSource
    let isViewer: Bool

    init(
        playerId: String,
        seatIndex: Int,
        name: String,
        hand: [MultiplayerCardSummary]?,
        handCount: Int,
        captured: MultiplayerCapturedCards,
        score: Int,
        money: Int,
        goCount: Int,
        shakeCount: Int,
        isConnected: Bool?,
        isReady: Bool?,
        presenceSource: MultiplayerPresenceSource = .unknown,
        isViewer: Bool
    ) {
        self.playerId = playerId
        self.seatIndex = seatIndex
        self.name = name
        self.hand = hand
        self.handCount = handCount
        self.captured = captured
        self.score = score
        self.money = money
        self.goCount = goCount
        self.shakeCount = shakeCount
        self.isConnected = isConnected
        self.isReady = isReady
        self.presenceSource = presenceSource
        self.isViewer = isViewer
    }
}

struct MultiplayerCapturedCards: Codable {
    let bright: [MultiplayerCardSummary]
    let animal: [MultiplayerCardSummary]
    let ribbon: [MultiplayerCardSummary]
    let junk: [MultiplayerCardSummary]
}

struct MultiplayerCardSummary: Codable {
    let cardId: String
    let month: Int
    let kind: String
    let imageIndex: Int
    let selectedRole: String?
}

struct MultiplayerTableSnapshot: Codable {
    let cards: [MultiplayerCardSummary]
    let monthBuckets: [String: [MultiplayerCardSummary]]
}

struct MultiplayerDeckSnapshot: Codable {
    let remainingCount: Int
}

struct MultiplayerScoreboard: Codable {
    let roundIndex: Int
    let playerScores: [MultiplayerPlayerScore]
    let winnerPlayerId: String?
}

struct MultiplayerRoundSummary: Codable {
    let roundIndex: Int
    let winnerPlayerId: String?
    let loserPlayerId: String?
    let finalScores: [MultiplayerPlayerScore]
    let settlementSummary: MultiplayerSettlementSummary?
    let endReason: MultiplayerMatchEndReason
    let endReasonMessageKey: String
    let forfeitingPlayerId: String?
    let isDraw: Bool
}

struct MultiplayerSettlementSummary: Codable {
    let finalScore: Int
    let scoreFormula: String
    let isDraw: Bool
    let isGwangbak: Bool
    let isPibak: Bool
    let isGobak: Bool
    let isMungbak: Bool
    let isJabak: Bool
    let isYeokbak: Bool
}

struct MultiplayerPlayerScore: Codable {
    let playerId: String
    let score: Int
    let goCount: Int
    let money: Int
}

struct MultiplayerTimers: Codable {
    let turnDeadlineAt: String?
    let choiceDeadlineAt: String?
}

struct MultiplayerResumeState: Codable {
    let isResumable: Bool
    let graceDeadlineAt: String?
}

struct MultiplayerChatPresence: Codable {
    let playerId: String
    let emojiId: String
    let text: String?
    let sentAt: String?
}

struct MultiplayerAuthorityReplayManifest: Codable {
    let replayId: String
    let roomId: String?
    let gameId: String
    let retentionPolicy: MultiplayerReplayRetentionPolicy
    let engineVersion: String
    let ruleConfigVersion: String
    let baselineSnapshotId: String
    let baselineStateVersion: Int
    let firstEventId: String
    let lastEventId: String
    let finalStateVersion: Int
    let finalStateHash: String
}
