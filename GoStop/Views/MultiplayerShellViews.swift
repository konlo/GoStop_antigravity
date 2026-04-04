import SwiftUI

enum MultiplayerEntryAction: String, CaseIterable, Identifiable {
    case quickMatch
    case createInvite
    case joinInvite
    case resume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickMatch:
            return "Quick Match"
        case .createInvite:
            return "Create Invite"
        case .joinInvite:
            return "Join Invite"
        case .resume:
            return "Resume Match"
        }
    }

    var subtitle: String {
        switch self {
        case .quickMatch:
            return "Queue into the shared matchmaker and attach to the first ready room."
        case .createInvite:
            return "Create a private room and wait for another player."
        case .joinInvite:
            return "Join a private room with the shared numeric invite code."
        case .resume:
            return "Reconnect with the last persisted room and session."
        }
    }

    var symbolName: String {
        switch self {
        case .quickMatch:
            return "bolt.fill"
        case .createInvite:
            return "plus.circle.fill"
        case .joinInvite:
            return "person.crop.circle.badge.plus"
        case .resume:
            return "arrow.clockwise.circle.fill"
        }
    }
}

enum MultiplayerRoomType: String {
    case invite
    case quickMatch

    var label: String {
        switch self {
        case .invite:
            return "Invite"
        case .quickMatch:
            return "Quick Match"
        }
    }
}

enum MultiplayerJoinPolicy: String {
    case inviteCode
    case matchmaker

    var label: String {
        switch self {
        case .inviteCode:
            return "Invite Code"
        case .matchmaker:
            return "Matchmaker"
        }
    }
}

enum MultiplayerRoomLifecycle: String {
    case waitingForPlayers
    case waitingForReady
    case starting
    case inGame
    case ended
    case closed

    var label: String {
        switch self {
        case .waitingForPlayers:
            return "Waiting For Players"
        case .waitingForReady:
            return "Waiting For Ready"
        case .starting:
            return "Starting"
        case .inGame:
            return "In Game"
        case .ended:
            return "Ended"
        case .closed:
            return "Closed"
        }
    }

    var accentColor: Color {
        switch self {
        case .waitingForPlayers:
            return Color(red: 0.92, green: 0.72, blue: 0.20)
        case .waitingForReady:
            return Color(red: 0.99, green: 0.57, blue: 0.25)
        case .starting:
            return Color(red: 0.24, green: 0.72, blue: 0.96)
        case .inGame:
            return Color(red: 0.31, green: 0.82, blue: 0.53)
        case .ended:
            return Color(red: 0.75, green: 0.40, blue: 0.22)
        case .closed:
            return Color(red: 0.49, green: 0.53, blue: 0.58)
        }
    }
}

enum MultiplayerMemberPresence: String {
    case connected
    case disconnected
    case disconnectedGrace
    case resuming
    case expired
    case replaced

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .disconnectedGrace:
            return "Reconnecting"
        case .resuming:
            return "Resyncing"
        case .expired:
            return "Expired"
        case .replaced:
            return "Replaced"
        }
    }

    var accentColor: Color {
        switch self {
        case .connected:
            return Color(red: 0.32, green: 0.81, blue: 0.52)
        case .disconnected:
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .disconnectedGrace:
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .resuming:
            return Color(red: 0.28, green: 0.74, blue: 0.98)
        case .expired:
            return Color(red: 0.88, green: 0.30, blue: 0.24)
        case .replaced:
            return Color(red: 0.57, green: 0.55, blue: 0.84)
        }
    }
}

enum MultiplayerGamePhase: String, Codable {
    case waiting
    case dealing
    case inTurn
    case choicePending
    case roundEnded
    case matchEnded
    case paused

    var label: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .dealing:
            return "Dealing"
        case .inTurn:
            return "In Turn"
        case .choicePending:
            return "Choice Pending"
        case .roundEnded:
            return "Round Ended"
        case .matchEnded:
            return "Match Ended"
        case .paused:
            return "Paused"
        }
    }
}

enum MultiplayerChoiceKind: String, Codable {
    case capture
    case shake
    case goStop
    case chrysanthemumRole

    var label: String {
        switch self {
        case .capture:
            return "Capture"
        case .shake:
            return "Shake"
        case .goStop:
            return "Go / Stop"
        case .chrysanthemumRole:
            return "Role Choice"
        }
    }
}

enum MultiplayerReconnectPhase {
    case reconnecting
    case resyncing
    case expired

    var title: String {
        switch self {
        case .reconnecting:
            return "Reconnecting Socket"
        case .resyncing:
            return "Applying Fresh Snapshot"
        case .expired:
            return "Reconnect Window Expired"
        }
    }

    var detail: String {
        switch self {
        case .reconnecting:
            return "The client has locked input and is waiting for a valid hello handshake."
        case .resyncing:
            return "The socket is back. Room and game snapshots still need to land before input can unlock."
        case .expired:
            return "The reconnect grace has elapsed. The player needs a terminal result or a safe exit."
        }
    }

    var symbolName: String {
        switch self {
        case .reconnecting:
            return "dot.radiowaves.left.and.right"
        case .resyncing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .expired:
            return "exclamationmark.lock.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .reconnecting:
            return Color(red: 0.92, green: 0.64, blue: 0.19)
        case .resyncing:
            return Color(red: 0.25, green: 0.77, blue: 0.98)
        case .expired:
            return Color(red: 0.88, green: 0.27, blue: 0.22)
        }
    }
}

enum MultiplayerBannerStyle: String, Codable {
    case info
    case success
    case warning
    case error

    var accentColor: Color {
        switch self {
        case .info:
            return Color(red: 0.24, green: 0.72, blue: 0.96)
        case .success:
            return Color(red: 0.31, green: 0.82, blue: 0.53)
        case .warning:
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .error:
            return Color(red: 0.88, green: 0.30, blue: 0.24)
        }
    }
}

struct MultiplayerBannerState: Identifiable, Codable {
    let id: String
    let style: MultiplayerBannerStyle
    let title: String
    let detail: String
    let messageKey: String?

    init(
        id: String = UUID().uuidString,
        style: MultiplayerBannerStyle,
        title: String,
        detail: String,
        messageKey: String? = nil
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.detail = detail
        self.messageKey = messageKey
    }
}

struct MultiplayerPersistedSessionSummary: Codable, Equatable {
    let roomId: String
    let sessionId: String
    let playerId: String?
    let deviceId: String?
    let resumeToken: String?
    let lastKnownGameId: String?
    let graceExpiresAt: Date?

    var isAttachReady: Bool {
        playerId != nil && deviceId != nil && resumeToken != nil
    }
}

struct MultiplayerEntryShellState {
    let pendingAction: MultiplayerEntryAction?
    let persistedResume: MultiplayerPersistedSessionSummary?
    let lastError: MultiplayerBannerState?
}

struct MultiplayerRoomMemberShellState: Identifiable {
    let playerId: String
    let seat: Int
    let role: String
    let ready: Bool
    let presence: MultiplayerMemberPresence
    let isLocalPlayer: Bool

    var id: String { playerId }
}

struct MultiplayerRoomDeadlinesState {
    let joinExpiresAt: Date?
    let readyExpiresAt: Date?
}

struct MultiplayerRoomShellState {
    let roomId: String
    let roomType: MultiplayerRoomType
    let joinPolicy: MultiplayerJoinPolicy
    let roomState: MultiplayerRoomLifecycle
    let hostPlayerId: String
    let members: [MultiplayerRoomMemberShellState]
    let activeGameId: String?
    let deadlines: MultiplayerRoomDeadlinesState
    let lastRoomSequence: Int
    let inviteCode: String?
    let banner: MultiplayerBannerState?
}

struct MultiplayerRenderableCardShellState: Identifiable, Equatable, Codable {
    let cardId: String
    let month: Int
    let kind: String
    let imageIndex: Int
    let selectedRole: String?
    let zone: String?

    var id: String { cardId }
}

struct MultiplayerTableMonthBucketShellState: Identifiable, Codable {
    let month: Int
    let cards: [MultiplayerRenderableCardShellState]

    var id: Int { month }
}

struct MultiplayerCapturedGroupShellState: Identifiable, Codable {
    let kind: String
    let title: String
    let cards: [MultiplayerRenderableCardShellState]

    var id: String { kind }
}

struct MultiplayerCapturedZoneShellState: Identifiable, Codable {
    let playerId: String
    let isLocalPlayer: Bool
    let groups: [MultiplayerCapturedGroupShellState]

    var id: String { playerId }
}

struct MultiplayerChoiceOptionShellState: Identifiable, Codable {
    let optionCode: String
    let labelKey: String
    let cards: [MultiplayerRenderableCardShellState]
    let scoreDeltaPreviewSelf: Int
    let scoreDeltaPreviewOpponent: Int

    var id: String { optionCode }

    var cardIds: [String] {
        cards.map(\.cardId)
    }
}

struct MultiplayerChoiceShellState: Codable {
    let choiceId: String
    let choiceKind: MultiplayerChoiceKind
    let actorPlayerId: String
    let promptKey: String
    let deadlineAt: Date?
    let isRedactedForViewer: Bool
    let redactionMessageKey: String?
    let options: [MultiplayerChoiceOptionShellState]
}

struct MultiplayerRejectDetailRow: Identifiable, Codable {
    let key: String
    let value: String

    var id: String { "\(key):\(value)" }
}

struct MultiplayerRejectShellState: Codable {
    let code: String
    let messageKey: String
    let detailRows: [MultiplayerRejectDetailRow]
}

struct MultiplayerLiveShellState: Codable {
    let roomId: String
    let gameId: String
    let localPlayerId: String
    let localPlayerDisplayName: String
    let stateVersion: Int
    let currentPlayerId: String
    let phase: MultiplayerGamePhase
    let turnId: String
    let turnDeadlineAt: Date?
    let serverTime: Date
    let opponentPlayerId: String
    let opponentPlayerDisplayName: String
    let opponentHandCount: Int
    let localHandCount: Int
    let localScore: Int
    let opponentScore: Int
    let localGoCount: Int
    let opponentGoCount: Int
    let deckRemainingCount: Int
    let localPlayableCardIds: [String]
    let localHandCards: [MultiplayerRenderableCardShellState]
    let tableCards: [MultiplayerRenderableCardShellState]
    let tableMonthBuckets: [MultiplayerTableMonthBucketShellState]
    let localCapturedZone: MultiplayerCapturedZoneShellState
    let opponentCapturedZone: MultiplayerCapturedZoneShellState
    let pendingChoice: MultiplayerChoiceShellState?
    let lastReject: MultiplayerRejectShellState?
    let connectionBanner: MultiplayerBannerState?
}

struct MultiplayerReconnectOverlayState {
    let phase: MultiplayerReconnectPhase
    let roomId: String
    let heartbeatIntervalMs: Int
    let disconnectTimeoutMs: Int
    let reconnectGraceMs: Int
    let graceExpiresAt: Date?
    let lastRoomSequence: Int
    let lastAppliedStateVersion: Int?
    let lastSnapshotId: String?
}

struct MultiplayerResultScoreRowState: Identifiable {
    let playerId: String
    let displayName: String
    let score: Int
    let goCount: Int
    let money: Int
    let isLocalPlayer: Bool

    var id: String { playerId }
}

struct MultiplayerResultSettlementFlagState: Identifiable {
    let label: String
    let isActive: Bool

    var id: String { label }
}

struct MultiplayerResultSettlementState {
    let finalScore: Int
    let scoreFormula: String
    let flags: [MultiplayerResultSettlementFlagState]
}

enum MultiplayerResultLeavePolicy {
    case leaveAvailable
    case pendingLeaveAcknowledgement
    case pendingRoomClosure

    var title: String {
        switch self {
        case .leaveAvailable:
            return "Leave Result"
        case .pendingLeaveAcknowledgement:
            return "Waiting For Leave Ack"
        case .pendingRoomClosure:
            return "Waiting For Room Closure"
        }
    }

    var subtitle: String {
        switch self {
        case .leaveAvailable:
            return "Send leaveRoom when finished reading. Dismiss only after leave ack or roomClosed lands."
        case .pendingLeaveAcknowledgement:
            return "leaveRoom was sent. The client is waiting for the authoritative completion signal."
        case .pendingRoomClosure:
            return "The local session already left. Final dismissal is waiting for roomClosed."
        }
    }

    var isEnabled: Bool {
        switch self {
        case .leaveAvailable:
            return true
        case .pendingLeaveAcknowledgement, .pendingRoomClosure:
            return false
        }
    }

    var messageKey: String {
        switch self {
        case .leaveAvailable:
            return "match.result.leave.ready"
        case .pendingLeaveAcknowledgement:
            return "match.result.leave.pending"
        case .pendingRoomClosure:
            return "match.result.leave.wait_room_closed"
        }
    }

    var showsProgress: Bool {
        switch self {
        case .pendingLeaveAcknowledgement, .pendingRoomClosure:
            return true
        case .leaveAvailable:
            return false
        }
    }
}

struct MultiplayerResultShellState {
    let roundIndex: Int
    let localPlayerId: String
    let winnerPlayerId: String?
    let loserPlayerId: String?
    let finalScores: [MultiplayerResultScoreRowState]
    let settlementSummary: MultiplayerResultSettlementState?
    let endReasonCode: String
    let endReasonMessageKey: String
    let forfeitingPlayerId: String?
    let isDraw: Bool
    let leavePolicy: MultiplayerResultLeavePolicy
    let integrationNotes: [String]
}

struct MultiplayerShellPreviewShowcaseState {
    let entry: MultiplayerEntryShellState
    let room: MultiplayerRoomShellState
    let live: MultiplayerLiveShellState
    let reconnect: MultiplayerReconnectOverlayState
    let result: MultiplayerResultShellState

    static let mock = MultiplayerShellPreviewShowcaseState(
        entry: MultiplayerEntryShellState(
            pendingAction: .resume,
            persistedResume: MultiplayerPersistedSessionSummary(
                roomId: "room_001",
                sessionId: "sess_001",
                playerId: "player_a",
                deviceId: "debug-ios-host",
                resumeToken: "resume_tok_001",
                lastKnownGameId: "game_001",
                graceExpiresAt: Date.now.addingTimeInterval(22)
            ),
                lastError: MultiplayerBannerState(
                style: .info,
                title: "Invite Code Ready",
                detail: "Phase 0 uses a numeric invite code as the share identifier and resolves it to the room id during bootstrap."
            )
        ),
        room: MultiplayerRoomShellState(
            roomId: "room_001",
            roomType: .invite,
            joinPolicy: .inviteCode,
            roomState: .waitingForReady,
            hostPlayerId: "player_a",
            members: [
                MultiplayerRoomMemberShellState(
                    playerId: "player_a",
                    seat: 0,
                    role: "host",
                    ready: true,
                    presence: .connected,
                    isLocalPlayer: true
                ),
                MultiplayerRoomMemberShellState(
                    playerId: "player_b",
                    seat: 1,
                    role: "guest",
                    ready: false,
                    presence: .disconnectedGrace,
                    isLocalPlayer: false
                )
            ],
            activeGameId: nil,
            deadlines: MultiplayerRoomDeadlinesState(
                joinExpiresAt: Date.now.addingTimeInterval(210),
                readyExpiresAt: Date.now.addingTimeInterval(42)
            ),
            lastRoomSequence: 18,
            inviteCode: "0001",
            banner: MultiplayerBannerState(
                style: .warning,
                title: "Guest Reconnecting",
                detail: "The seat is still owned, but the guest socket is inside reconnect grace."
            )
        ),
        live: MultiplayerLiveShellState(
            roomId: "room_001",
            gameId: "game_001",
            localPlayerId: "player_a",
            localPlayerDisplayName: "You",
            stateVersion: 13,
            currentPlayerId: "player_a",
            phase: .choicePending,
            turnId: "turn_0007",
            turnDeadlineAt: Date.now.addingTimeInterval(14),
            serverTime: Date.now,
            opponentPlayerId: "player_b",
            opponentPlayerDisplayName: "Guest",
            opponentHandCount: 7,
            localHandCount: 6,
            localScore: 5,
            opponentScore: 2,
            localGoCount: 1,
            opponentGoCount: 0,
            deckRemainingCount: 18,
            localPlayableCardIds: ["card_03_ribbon_red_poem", "card_04_junk_a"],
            localHandCards: [
                MultiplayerRenderableCardShellState(
                    cardId: "card_03_ribbon_red_poem",
                    month: 3,
                    kind: "ribbon",
                    imageIndex: 9,
                    selectedRole: nil,
                    zone: "hand"
                ),
                MultiplayerRenderableCardShellState(
                    cardId: "card_04_junk_a",
                    month: 4,
                    kind: "junk",
                    imageIndex: 11,
                    selectedRole: nil,
                    zone: "hand"
                )
            ],
            tableCards: [
                MultiplayerRenderableCardShellState(
                    cardId: "card_03_junk_a",
                    month: 3,
                    kind: "junk",
                    imageIndex: 11,
                    selectedRole: nil,
                    zone: "table"
                ),
                MultiplayerRenderableCardShellState(
                    cardId: "card_03_junk_b",
                    month: 3,
                    kind: "junk",
                    imageIndex: 10,
                    selectedRole: nil,
                    zone: "table"
                ),
                MultiplayerRenderableCardShellState(
                    cardId: "card_08_animal_geese",
                    month: 8,
                    kind: "animal",
                    imageIndex: 3,
                    selectedRole: nil,
                    zone: "table"
                )
            ],
            tableMonthBuckets: [
                MultiplayerTableMonthBucketShellState(
                    month: 3,
                    cards: [
                        MultiplayerRenderableCardShellState(
                            cardId: "card_03_junk_a",
                            month: 3,
                            kind: "junk",
                            imageIndex: 11,
                            selectedRole: nil,
                            zone: "table"
                        ),
                        MultiplayerRenderableCardShellState(
                            cardId: "card_03_junk_b",
                            month: 3,
                            kind: "junk",
                            imageIndex: 10,
                            selectedRole: nil,
                            zone: "table"
                        )
                    ]
                ),
                MultiplayerTableMonthBucketShellState(
                    month: 8,
                    cards: [
                        MultiplayerRenderableCardShellState(
                            cardId: "card_08_animal_geese",
                            month: 8,
                            kind: "animal",
                            imageIndex: 3,
                            selectedRole: nil,
                            zone: "table"
                        )
                    ]
                )
            ],
            localCapturedZone: MultiplayerCapturedZoneShellState(
                playerId: "player_a",
                isLocalPlayer: true,
                groups: [
                    MultiplayerCapturedGroupShellState(kind: "bright", title: "Bright", cards: []),
                    MultiplayerCapturedGroupShellState(kind: "animal", title: "Animal", cards: []),
                    MultiplayerCapturedGroupShellState(
                        kind: "ribbon",
                        title: "Ribbon",
                        cards: [
                            MultiplayerRenderableCardShellState(
                                cardId: "card_01_ribbon_red",
                                month: 1,
                                kind: "ribbon",
                                imageIndex: 2,
                                selectedRole: nil,
                                zone: "captured"
                            )
                        ]
                    ),
                    MultiplayerCapturedGroupShellState(
                        kind: "junk",
                        title: "Junk",
                        cards: [
                            MultiplayerRenderableCardShellState(
                                cardId: "card_02_junk_a",
                                month: 2,
                                kind: "junk",
                                imageIndex: 11,
                                selectedRole: nil,
                                zone: "captured"
                            ),
                            MultiplayerRenderableCardShellState(
                                cardId: "card_05_junk_a",
                                month: 5,
                                kind: "junk",
                                imageIndex: 11,
                                selectedRole: nil,
                                zone: "captured"
                            )
                        ]
                    )
                ]
            ),
            opponentCapturedZone: MultiplayerCapturedZoneShellState(
                playerId: "player_b",
                isLocalPlayer: false,
                groups: [
                    MultiplayerCapturedGroupShellState(kind: "bright", title: "Bright", cards: []),
                    MultiplayerCapturedGroupShellState(
                        kind: "animal",
                        title: "Animal",
                        cards: [
                            MultiplayerRenderableCardShellState(
                                cardId: "card_08_animal_geese",
                                month: 8,
                                kind: "animal",
                                imageIndex: 3,
                                selectedRole: nil,
                                zone: "captured"
                            )
                        ]
                    ),
                    MultiplayerCapturedGroupShellState(kind: "ribbon", title: "Ribbon", cards: []),
                    MultiplayerCapturedGroupShellState(kind: "junk", title: "Junk", cards: [])
                ]
            ),
            pendingChoice: MultiplayerChoiceShellState(
                choiceId: "choice_0007",
                choiceKind: .capture,
                actorPlayerId: "player_a",
                promptKey: "match.choice.capture",
                deadlineAt: Date.now.addingTimeInterval(14),
                isRedactedForViewer: false,
                redactionMessageKey: nil,
                options: [
                    MultiplayerChoiceOptionShellState(
                        optionCode: "capture_pair_left",
                        labelKey: "match.choice.capture.take_pair",
                        cards: [
                            MultiplayerRenderableCardShellState(
                                cardId: "card_03_ribbon_red_poem",
                                month: 3,
                                kind: "ribbon",
                                imageIndex: 9,
                                selectedRole: nil,
                                zone: "hand"
                            ),
                            MultiplayerRenderableCardShellState(
                                cardId: "card_03_junk_a",
                                month: 3,
                                kind: "junk",
                                imageIndex: 11,
                                selectedRole: nil,
                                zone: "table"
                            )
                        ],
                        scoreDeltaPreviewSelf: 0,
                        scoreDeltaPreviewOpponent: 0
                    ),
                    MultiplayerChoiceOptionShellState(
                        optionCode: "capture_pair_right",
                        labelKey: "match.choice.capture.take_pair",
                        cards: [
                            MultiplayerRenderableCardShellState(
                                cardId: "card_03_ribbon_red_poem",
                                month: 3,
                                kind: "ribbon",
                                imageIndex: 9,
                                selectedRole: nil,
                                zone: "hand"
                            ),
                            MultiplayerRenderableCardShellState(
                                cardId: "card_03_junk_b",
                                month: 3,
                                kind: "junk",
                                imageIndex: 10,
                                selectedRole: nil,
                                zone: "table"
                            )
                        ],
                        scoreDeltaPreviewSelf: 0,
                        scoreDeltaPreviewOpponent: 0
                    )
                ]
            ),
            lastReject: MultiplayerRejectShellState(
                code: "staleStateVersion",
                messageKey: "match.reject.stale_state_version",
                detailRows: [
                    MultiplayerRejectDetailRow(key: "latestStateVersion", value: "13"),
                    MultiplayerRejectDetailRow(key: "turnId", value: "turn_0007")
                ]
            ),
            connectionBanner: MultiplayerBannerState(
                style: .info,
                title: "Authoritative Snapshot First",
                detail: "The live shell is still mock data, but it mirrors Agent 1 snapshot and patch ownership."
            )
        ),
        reconnect: MultiplayerReconnectOverlayState(
            phase: .resyncing,
            roomId: "room_001",
            heartbeatIntervalMs: 5000,
            disconnectTimeoutMs: 15000,
            reconnectGraceMs: 30000,
            graceExpiresAt: Date.now.addingTimeInterval(18),
            lastRoomSequence: 21,
            lastAppliedStateVersion: 13,
            lastSnapshotId: "snap_000013_player_a"
        ),
        result: MultiplayerResultShellState(
            roundIndex: 1,
            localPlayerId: "player_a",
            winnerPlayerId: "player_a",
            loserPlayerId: "player_b",
            finalScores: [
                MultiplayerResultScoreRowState(
                    playerId: "player_a",
                    displayName: "You",
                    score: 5,
                    goCount: 1,
                    money: 12000,
                    isLocalPlayer: true
                ),
                MultiplayerResultScoreRowState(
                    playerId: "player_b",
                    displayName: "Guest",
                    score: 2,
                    goCount: 0,
                    money: 8000,
                    isLocalPlayer: false
                )
            ],
            settlementSummary: MultiplayerResultSettlementState(
                finalScore: 5,
                scoreFormula: "5 points + pi-bak",
                flags: [
                    MultiplayerResultSettlementFlagState(label: "Draw", isActive: false),
                    MultiplayerResultSettlementFlagState(label: "Gwangbak", isActive: false),
                    MultiplayerResultSettlementFlagState(label: "Pibak", isActive: true),
                    MultiplayerResultSettlementFlagState(label: "Gobak", isActive: false),
                    MultiplayerResultSettlementFlagState(label: "Mungbak", isActive: false),
                    MultiplayerResultSettlementFlagState(label: "Jabak", isActive: false),
                    MultiplayerResultSettlementFlagState(label: "Yeokbak", isActive: false)
                ]
            ),
            endReasonCode: "disconnectTimeout",
            endReasonMessageKey: "match.end.disconnect_timeout",
            forfeitingPlayerId: "player_b",
            isDraw: false,
            leavePolicy: .leaveAvailable,
            integrationNotes: [
                "Player display names still need mapping from room member payload.",
                "The product route now uses an in-sheet Home / Play / Session split, but the main app still presents it from a root sheet launcher.",
                "Gameplay transport is wired for playCard, submitChoice, and quit, and the live surface now renders snapshot-backed card art, captured zones, and month-bucket board focus. Direct table-target gestures and fuller board parity are still follow-up."
            ]
        )
    )
}

private func localizedShellText(_ key: String, fallback: String) -> String {
    multiplayerShellText(key, fallback: fallback)
}

private func localizedShellText(_ key: String?) -> String? {
    multiplayerShellText(key)
}

struct MultiplayerEntryView: View {
    let state: MultiplayerEntryShellState
    let availableActions: [MultiplayerEntryAction]
    let onAction: (MultiplayerEntryAction) -> Void

    var body: some View {
        MultiplayerShellSurface(title: "Multiplayer Entry", subtitle: "Room attach and reconnect start here.") {
            VStack(alignment: .leading, spacing: 18) {
                if let persistedResume = state.persistedResume {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: MultiplayerEntryAction.resume.symbolName,
                                    accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Persisted Session Found")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text(
                                        persistedResume.isAttachReady
                                        ? "Room \(persistedResume.roomId) is eligible for reconnect if the next hello handshake succeeds."
                                        : "Room \(persistedResume.roomId) is still cached locally, but resume attach is blocked until playerId, deviceId, and resumeToken are available."
                                    )
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }

                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Session", value: shortIdentifier(persistedResume.sessionId))
                                MultiplayerStatPill(label: "Game", value: shortIdentifier(persistedResume.lastKnownGameId ?? "none"))
                                MultiplayerStatPill(label: "Attach", value: persistedResume.isAttachReady ? "Ready" : "Incomplete")
                                MultiplayerStatPill(
                                    label: "Grace",
                                    value: countdownText(to: persistedResume.graceExpiresAt, reference: Date.now)
                                )
                            }

                            MultiplayerPrimaryButton(
                                title: MultiplayerEntryAction.resume.title,
                                subtitle: MultiplayerEntryAction.resume.subtitle,
                                isBusy: state.pendingAction == .resume,
                                accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                            ) {
                                onAction(.resume)
                            }
                            .disabled(state.pendingAction == .resume || !persistedResume.isAttachReady)
                        }
                    }
                }

                if let lastError = state.lastError {
                    MultiplayerBannerView(state: lastError)
                }

                Text("Attach Paths")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                ViewThatFits {
                    HStack(spacing: 16) {
                        ForEach(availableActions) { action in
                            entryActionCard(action)
                        }
                    }

                    VStack(spacing: 14) {
                        ForEach(availableActions) { action in
                            entryActionCard(action)
                        }
                    }
                }
            }
        }
    }

    private func entryActionCard(_ action: MultiplayerEntryAction) -> some View {
        MultiplayerActionCard(
            title: action.title,
            subtitle: action.subtitle,
            symbolName: action.symbolName,
            isBusy: state.pendingAction == action,
            accentColor: accentColor(for: action)
        ) {
            onAction(action)
        }
    }

    private func accentColor(for action: MultiplayerEntryAction) -> Color {
        switch action {
        case .quickMatch:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .createInvite:
            return Color(red: 0.98, green: 0.59, blue: 0.25)
        case .joinInvite:
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        case .resume:
            return Color(red: 0.93, green: 0.73, blue: 0.20)
        }
    }
}

struct MultiplayerRoomView: View {
    let state: MultiplayerRoomShellState
    let onReadyTapped: () -> Void
    let onLeaveTapped: () -> Void

    var body: some View {
        MultiplayerShellSurface(title: "Room Shell", subtitle: "Room snapshot and room events only.") {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if let banner = state.banner {
                    MultiplayerBannerView(state: banner)
                }

                VStack(spacing: 14) {
                    ForEach(state.members) { member in
                        MultiplayerRoomSeatCard(member: member, hostPlayerId: state.hostPlayerId)
                    }
                }

                HStack(spacing: 12) {
                    MultiplayerStatPill(label: "Join Policy", value: state.joinPolicy.label)
                    MultiplayerStatPill(label: "Sequence", value: "\(state.lastRoomSequence)")
                    MultiplayerStatPill(
                        label: "Ready Window",
                        value: countdownText(to: state.deadlines.readyExpiresAt, reference: Date.now)
                    )
                }

                HStack(spacing: 14) {
                    MultiplayerPrimaryButton(
                        title: localReadyTitle,
                        subtitle: localReadySubtitle,
                        isBusy: state.roomState == .starting,
                        accentColor: state.roomState.accentColor
                    ) {
                        onReadyTapped()
                    }
                    .disabled(state.roomState == .starting || !canToggleReady)

                    MultiplayerSecondaryButton(
                        title: "Leave Room",
                        subtitle: "Send leaveRoom and wait for the authoritative room lifecycle completion before dismissing.",
                        accentColor: Color(red: 0.80, green: 0.29, blue: 0.23)
                    ) {
                        onLeaveTapped()
                    }
                    .disabled(state.roomState == .starting)
                }
            }
        }
    }

    private var localMember: MultiplayerRoomMemberShellState? {
        state.members.first(where: \.isLocalPlayer)
    }

    private var canToggleReady: Bool {
        guard localMember?.presence == .connected else {
            return false
        }
        return state.roomState == .waitingForReady && state.members.count == 2
    }

    private var localReadyTitle: String {
        (localMember?.ready ?? false) ? "Unready" : "Ready"
    }

    private var localReadySubtitle: String {
        if localMember?.presence != .connected {
            return "Reconnect first. Room snapshot still owns the ready truth."
        }
        if state.members.count < 2 || state.roomState == .waitingForPlayers {
            return "Wait for the other player before sending ready."
        }
        return "Only flips after `memberReadyChanged` returns."
    }

    private var headerCard: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(state.roomType.label)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            MultiplayerStatusBadge(title: state.roomState.label, accentColor: state.roomState.accentColor)
                        }

                        Text("Room \(state.roomId)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    if state.roomState == .starting {
                        ProgressView()
                            .tint(.white)
                    }
                }

                HStack(spacing: 12) {
                    MultiplayerStatPill(label: "Host", value: shortIdentifier(state.hostPlayerId))
                    MultiplayerStatPill(label: "Game", value: shortIdentifier(state.activeGameId ?? "pending"))
                    MultiplayerStatPill(label: "Join TTL", value: countdownText(to: state.deadlines.joinExpiresAt, reference: Date.now))
                }

                if let inviteCode = state.inviteCode {
                    Text("Invite code: \(inviteCode)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.80, blue: 0.32))
                } else {
                    Text("Invite code is not on this snapshot yet. Product invite join expects `room.inviteCode`, and Phase 0 resolves that numeric code to the room id during bootstrap.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
        }
    }
}

struct MultiplayerLiveShellView: View {
    let state: MultiplayerLiveShellState
    let onPlayCard: ((String) -> Void)?
    let onSubmitChoice: ((String, String, String?) -> Void)?
    let onQuitTapped: (() -> Void)?

    @State private var selectedCardId: String?
    @State private var selectedTableCardId: String?
    @State private var inspectedMonth: Int?

    init(
        state: MultiplayerLiveShellState,
        onPlayCard: ((String) -> Void)? = nil,
        onSubmitChoice: ((String, String, String?) -> Void)? = nil,
        onQuitTapped: (() -> Void)? = nil
    ) {
        self.state = state
        self.onPlayCard = onPlayCard
        self.onSubmitChoice = onSubmitChoice
        self.onQuitTapped = onQuitTapped
    }

    var body: some View {
        MultiplayerShellSurface(
            title: "Hwatu Board",
            subtitle: "The live route now mirrors the normal go-stop flow: opponent shelf, central table, and your hand stay front and center while transport remains authoritative."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                liveOverviewCard

                if let connectionBanner = state.connectionBanner {
                    MultiplayerBannerView(state: connectionBanner)
                }

                liveBoardScene
                actionTray

                if let lastReject = state.lastReject {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last Reject: \(friendlyShellIdentifier(lastReject.code))")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.99, green: 0.62, blue: 0.28))
                            Text(localizedShellText(lastReject.messageKey, fallback: lastReject.messageKey))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                            Text("Code \(lastReject.code)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.50))

                            ForEach(lastReject.detailRows) { row in
                                HStack(spacing: 10) {
                                    Text(friendlyShellIdentifier(row.key))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.62))
                                    Spacer(minLength: 0)
                                    Text(row.value)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            syncSelectedCardIfNeeded()
        }
        .onChange(of: state.turnId) { _ in
            syncSelectedCardIfNeeded(reset: true)
        }
        .onChange(of: state.pendingChoice?.choiceId) { _ in
            syncSelectedCardIfNeeded()
        }
        .onChange(of: state.localPlayableCardIds.joined(separator: "|")) { _ in
            syncSelectedCardIfNeeded()
        }
        .onChange(of: state.tableCards.map(\.cardId).joined(separator: "|")) { _ in
            syncFocusedTableCardIfNeeded()
        }
    }

    private var liveOverviewCard: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: actionableChoice != nil ? "sparkles.rectangle.stack.fill" : "suit.club.fill",
                        accentColor: liveHeadlineAccent
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(liveHeadline)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(liveHeadlineDetail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    MultiplayerStatusBadge(title: state.phase.label, accentColor: liveHeadlineAccent)
                }

                ViewThatFits {
                    HStack(spacing: 10) {
                        MultiplayerStatPill(label: "Turn", value: currentTurnDisplayName)
                        MultiplayerStatPill(label: "Timer", value: countdownText(to: state.turnDeadlineAt, reference: state.serverTime))
                        MultiplayerStatPill(label: "Deck", value: "\(state.deckRemainingCount)")
                        MultiplayerStatPill(label: "Game", value: shortIdentifier(state.gameId))
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            MultiplayerStatPill(label: "Turn", value: currentTurnDisplayName)
                            MultiplayerStatPill(label: "Timer", value: countdownText(to: state.turnDeadlineAt, reference: state.serverTime))
                        }
                        HStack(spacing: 10) {
                            MultiplayerStatPill(label: "Deck", value: "\(state.deckRemainingCount)")
                            MultiplayerStatPill(label: "Game", value: shortIdentifier(state.gameId))
                        }
                    }
                }
            }
        }
    }

    private var liveBoardScene: some View {
        MultiplayerPanelCard {
            VStack(spacing: 16) {
                playerLane(
                    title: state.opponentPlayerDisplayName,
                    caption: "Opponent",
                    score: state.opponentScore,
                    goCount: state.opponentGoCount,
                    handCount: state.opponentHandCount,
                    accentColor: Color(red: 0.25, green: 0.77, blue: 0.98),
                    isCurrentTurn: !isLocalTurn,
                    zone: state.opponentCapturedZone
                ) {
                    opponentHandFan
                }

                tableLane

                playerLane(
                    title: state.localPlayerDisplayName,
                    caption: "My Hand",
                    score: state.localScore,
                    goCount: state.localGoCount,
                    handCount: state.localHandCount,
                    accentColor: Color(red: 0.32, green: 0.82, blue: 0.52),
                    isCurrentTurn: isLocalTurn,
                    zone: state.localCapturedZone
                ) {
                    localHandFan
                }
            }
        }
    }

    private var actionTray: some View {
        Group {
            if let actionableChoice {
                activeChoicePanel(actionableChoice)
            } else if let pendingChoice = state.pendingChoice, pendingChoice.isRedactedForViewer {
                waitingChoicePanel(pendingChoice)
            } else {
                playActionPanel
            }
        }
    }

    private var playActionPanel: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: canPlayHandCard ? "hand.tap.fill" : "hourglass.bottomhalf.filled",
                        accentColor: canPlayHandCard ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.95, green: 0.65, blue: 0.20)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(canPlayHandCard ? "Direct Hand Play" : inputModeLabel)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(handActionSubtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    MultiplayerStatusBadge(
                        title: canPlayHandCard ? "Ready" : "Locked",
                        accentColor: canPlayHandCard ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.49, green: 0.53, blue: 0.58)
                    )
                }

                ViewThatFits {
                    HStack(alignment: .center, spacing: 16) {
                        selectedCardSummary
                        directTapAndQuitButtons
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        selectedCardSummary
                        directTapAndQuitButtons
                    }
                }
            }
        }
    }

    private func activeChoicePanel(_ pendingChoice: MultiplayerChoiceShellState) -> some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: pendingChoice.choiceKind == .shake ? "sparkles" : "list.bullet.rectangle.portrait.fill",
                        accentColor: Color(red: 0.96, green: 0.70, blue: 0.22)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(pendingChoice.choiceKind.label) Required")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(localizedShellText(pendingChoice.promptKey, fallback: choicePromptFallback(for: pendingChoice)))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                    }

                    Spacer(minLength: 0)

                    MultiplayerStatusBadge(
                        title: countdownText(to: pendingChoice.deadlineAt, reference: state.serverTime),
                        accentColor: Color(red: 0.96, green: 0.70, blue: 0.22)
                    )
                }

                ForEach(pendingChoice.options) { option in
                    choiceOptionRow(pendingChoice: pendingChoice, option: option)
                }

                MultiplayerSecondaryButton(
                    title: "Quit Match",
                    subtitle: quitButtonSubtitle,
                    accentColor: Color(red: 0.88, green: 0.30, blue: 0.24),
                    isEnabled: canQuitMatch,
                    action: { onQuitTapped?() }
                )
            }
        }
    }

    private func waitingChoicePanel(_ pendingChoice: MultiplayerChoiceShellState) -> some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: "eye.slash.fill",
                        accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Opponent Choice In Progress")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(
                            localizedShellText(
                                pendingChoice.redactionMessageKey ?? "",
                                fallback: "The authoritative match is waiting for the opponent to resolve a private choice."
                            )
                        )
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                    }

                    Spacer(minLength: 0)

                    MultiplayerStatusBadge(
                        title: countdownText(to: pendingChoice.deadlineAt, reference: state.serverTime),
                        accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                    )
                }

                MultiplayerSecondaryButton(
                    title: "Quit Match",
                    subtitle: quitButtonSubtitle,
                    accentColor: Color(red: 0.88, green: 0.30, blue: 0.24),
                    isEnabled: canQuitMatch,
                    action: { onQuitTapped?() }
                )
            }
        }
    }

    private var selectedCardSummary: some View {
        HStack(spacing: 14) {
            if let selectedHandCard {
                MultiplayerLiveBoardCard(
                    card: selectedHandCard,
                    scale: 0.60,
                    emphasis: .selected
                )
                .frame(width: 92, height: 128)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .frame(width: 92, height: 128)
                    .overlay(
                        Text("Pick\nCard")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedHandCard.map(cardDisplayTitle) ?? "Tap Any Card")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(selectedHandActionSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                if hasBoardFocus {
                    Button("Clear Focus") {
                        clearBoardFocus()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.77, blue: 0.98))
                }
            }
        }
    }

    private var directTapAndQuitButtons: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(canPlayHandCard ? "Tap A Card To Play" : inputModeLabel)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(handActionSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.black.opacity(0.84))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.32, green: 0.82, blue: 0.52))
            )
            .opacity(canPlayHandCard ? 1 : 0.72)

            MultiplayerSecondaryButton(
                title: "Quit Match",
                subtitle: quitButtonSubtitle,
                accentColor: Color(red: 0.88, green: 0.30, blue: 0.24),
                isEnabled: canQuitMatch,
                action: { onQuitTapped?() }
            )
        }
    }

    private func playerLane<Content: View>(
        title: String,
        caption: String,
        score: Int,
        goCount: Int,
        handCount: Int,
        accentColor: Color,
        isCurrentTurn: Bool,
        zone: MultiplayerCapturedZoneShellState,
        @ViewBuilder handContent: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        MultiplayerStatusBadge(
                            title: isCurrentTurn ? "Turn" : caption,
                            accentColor: isCurrentTurn ? accentColor : accentColor.opacity(0.72)
                        )
                    }

                    Text(caption)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    MultiplayerStatPill(label: "Score", value: "\(score)")
                    MultiplayerStatPill(label: "Go", value: "\(goCount)")
                    MultiplayerStatPill(label: "Hand", value: "\(handCount)")
                }
            }

            capturedShelf(zone: zone, accentColor: accentColor)
            handContent()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isCurrentTurn ? accentColor : Color.white.opacity(0.08), lineWidth: isCurrentTurn ? 1.4 : 1)
        )
    }

    private func capturedShelf(zone: MultiplayerCapturedZoneShellState, accentColor: Color) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(zone.groups) { group in
                capturedGroupTile(group, accentColor: accentColor)
            }
        }
    }

    private func capturedGroupTile(
        _ group: MultiplayerCapturedGroupShellState,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(capturedGroupDisplayTitle(group))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(group.cards.count)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.84))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(capturedAccentColor(for: group.kind))
                    )
            }

            if group.cards.isEmpty {
                Text("Empty")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            } else {
                HStack(alignment: .bottom, spacing: -16) {
                    ForEach(Array(group.cards.prefix(3))) { card in
                        MultiplayerLiveBoardCard(
                            card: card,
                            scale: 0.28,
                            emphasis: focusedTableMonth == card.month ? .highlighted : .subtle
                        )
                    }
                    Spacer(minLength: 0)
                    if group.cards.count > 3 {
                        Text("+\(group.cards.count - 3)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }
                .frame(minHeight: 54, alignment: .bottomLeading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var opponentHandFan: some View {
        HStack(alignment: .bottom, spacing: -20) {
            ForEach(0..<max(1, min(state.opponentHandCount, 6)), id: \.self) { index in
                CardView(
                    card: multiplayerCardBack(id: "opponent_back_\(index)"),
                    isFaceUp: false,
                    scale: 0.52
                )
                .rotationEffect(.degrees(Double(index - 2) * 2.5))
            }

            if state.opponentHandCount > 6 {
                Text("+\(state.opponentHandCount - 6)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                    )
                    .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var localHandFan: some View {
        Group {
            if state.localHandCards.isEmpty {
                Text("No authoritative hand cards are available yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: -28) {
                        ForEach(state.localHandCards) { card in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    inspectedMonth = nil
                                    selectedTableCardId = nil
                                    selectedCardId = card.cardId
                                }
                                guard canPlayHandCard else { return }
                                onPlayCard?(card.cardId)
                            } label: {
                                MultiplayerLiveBoardCard(
                                    card: card,
                                    scale: 0.58,
                                    emphasis: selectedCardId == card.cardId
                                        ? .selected
                                        : (focusedTableMonth == card.month ? .highlighted : .subtle)
                                )
                                .offset(y: selectedCardId == card.cardId ? -10 : 0)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canPlayHandCard)
                            .opacity(canPlayHandCard || selectedCardId == card.cardId ? 1 : 0.72)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                }
                .frame(height: 138)
            }
        }
    }

    private var tableLane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Table")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        MultiplayerStatusBadge(
                            title: boardFocusStatusTitle,
                            accentColor: focusedTableMonth == nil ? Color(red: 0.93, green: 0.73, blue: 0.20) : Color(red: 0.32, green: 0.82, blue: 0.52)
                        )
                    }

                    Text(tableActionSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    MultiplayerStatPill(label: "Deck", value: "\(state.deckRemainingCount)")
                    MultiplayerStatPill(label: "Buckets", value: "\(renderedTableMonthBuckets.count)")
                }
            }

            if hasBoardFocus {
                HStack(spacing: 10) {
                    Text(boardFocusDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                    Spacer(minLength: 0)
                    Button("Clear Focus") {
                        clearBoardFocus()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.77, blue: 0.98))
                }
            }

            if renderedTableMonthBuckets.isEmpty {
                Text("No table cards are projected yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
                    ForEach(renderedTableMonthBuckets) { bucket in
                        tableBucketTile(bucket)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func tableBucketTile(_ bucket: MultiplayerTableMonthBucketShellState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    focusMonth(bucket.month)
                } label: {
                    Text("Month \(String(format: "%02d", bucket.month))")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if let bucketBadgeTitle = bucketBadgeTitle(for: bucket) {
                    MultiplayerStatusBadge(
                        title: bucketBadgeTitle,
                        accentColor: selectedHandCard?.month == bucket.month
                            ? Color(red: 0.32, green: 0.82, blue: 0.52)
                            : Color(red: 0.25, green: 0.77, blue: 0.98)
                    )
                }

                Spacer(minLength: 0)
                Text("\(bucket.cards.count)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
            }

            HStack(alignment: .bottom, spacing: -18) {
                ForEach(bucket.cards) { card in
                    Button {
                        handleTableCardTap(card)
                    } label: {
                        MultiplayerLiveBoardCard(
                            card: card,
                            scale: 0.42,
                            emphasis: emphasis(forTableCard: card)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 96, alignment: .bottomLeading)

            Text(monthBucketSubtitle(for: bucket))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(focusedTableMonth == bucket.month ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    focusedTableMonth == bucket.month
                        ? Color(red: 0.32, green: 0.82, blue: 0.52)
                        : Color.white.opacity(0.08),
                    lineWidth: focusedTableMonth == bucket.month ? 1.4 : 1
                )
        )
    }

    private func choiceOptionRow(
        pendingChoice: MultiplayerChoiceShellState,
        option: MultiplayerChoiceOptionShellState
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(localizedShellText(option.labelKey, fallback: optionFallback(for: option)))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                if option.scoreDeltaPreviewSelf != 0 || option.scoreDeltaPreviewOpponent != 0 {
                    MultiplayerStatusBadge(
                        title: "\(option.scoreDeltaPreviewSelf) / \(option.scoreDeltaPreviewOpponent)",
                        accentColor: Color(red: 0.96, green: 0.70, blue: 0.22)
                    )
                }

                Spacer(minLength: 0)
            }

            if !option.cards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: -14) {
                        ForEach(option.cards) { card in
                            Button {
                                handleChoicePreviewTap(pendingChoice: pendingChoice, option: option, card: card)
                            } label: {
                                MultiplayerLiveBoardCard(
                                    card: card,
                                    scale: 0.38,
                                    emphasis: optionCardEmphasis(for: card)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
                .frame(height: 92)
            }

            if pendingChoice.choiceKind == .capture {
                Text(captureChoiceInteractionSubtitle(for: option))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }

            MultiplayerSecondaryButton(
                title: localizedShellText(option.labelKey, fallback: optionFallback(for: option)),
                subtitle: optionMatchesCurrentFocus(option)
                    ? optionFocusDetail(option)
                    : "Confirm this authoritative choice and continue the turn.",
                accentColor: Color(red: 0.24, green: 0.72, blue: 0.96),
                isEnabled: actionableChoice != nil,
                action: {
                    onSubmitChoice?(pendingChoice.choiceId, option.optionCode, nil)
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var isLocalTurn: Bool {
        state.currentPlayerId == state.localPlayerId
    }

    private var currentTurnDisplayName: String {
        isLocalTurn ? "You" : state.opponentPlayerDisplayName
    }

    private var liveHeadline: String {
        if let pendingChoice = state.pendingChoice {
            return pendingChoice.actorPlayerId == state.localPlayerId ? "Choice Required" : "Opponent Resolving Choice"
        }
        if isLocalTurn && state.phase == .inTurn {
            return "Your Turn"
        }
        if state.phase == .waiting || state.phase == .dealing {
            return "Opening Hand"
        }
        return "Opponent Turn"
    }

    private var liveHeadlineAccent: Color {
        if actionableChoice != nil {
            return Color(red: 0.96, green: 0.70, blue: 0.22)
        }
        if isLocalTurn && state.phase == .inTurn {
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        }
        return Color(red: 0.95, green: 0.65, blue: 0.20)
    }

    private var liveHeadlineDetail: String {
        if let pendingChoice = state.pendingChoice {
            if pendingChoice.actorPlayerId == state.localPlayerId {
                if pendingChoice.choiceKind == .capture {
                    return "Tap the matching table card or the highlighted preview stack to resolve the capture line."
                }
                return "Resolve the highlighted choice before the next hwatu card can move."
            }
            return "The board is waiting on the opponent's authoritative choice result."
        }
        if isLocalTurn && state.phase == .inTurn {
            return "Tap a hwatu card from your hand to send playCard immediately. Table focus stays local and only helps you read the month match."
        }
        if state.phase == .waiting || state.phase == .dealing {
            return "The live projection is still opening. Input will unlock once the first turn is authoritative."
        }
        return "The opponent owns the turn. Watch the board and wait for the next snapshot."
    }

    private var quitButtonSubtitle: String {
        canQuitMatch
            ? "Send the live quit command over the authoritative transport."
            : "Quit is locked until the authoritative live transport is ready again."
    }

    private func bucketBadgeTitle(for bucket: MultiplayerTableMonthBucketShellState) -> String? {
        if selectedHandCard?.month == bucket.month {
            return "Match"
        }
        if selectedTableCard?.month == bucket.month {
            return "Focus"
        }
        if inspectedMonth == bucket.month {
            return "Inspect"
        }
        return nil
    }

    private func capturedAccentColor(for kind: String) -> Color {
        switch kind {
        case "bright":
            return Color(red: 0.97, green: 0.82, blue: 0.28)
        case "animal":
            return Color(red: 0.31, green: 0.82, blue: 0.53)
        case "ribbon":
            return Color(red: 0.96, green: 0.47, blue: 0.53)
        case "junk":
            return Color(red: 0.32, green: 0.74, blue: 0.98)
        default:
            return Color.white.opacity(0.22)
        }
    }

    private func multiplayerCardBack(id: String) -> Card {
        Card(id: id, month: .jan, type: .junk, imageIndex: 0)
    }

    private var handColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: 10, alignment: .leading)]
    }

    private var actionableChoice: MultiplayerChoiceShellState? {
        guard let pendingChoice = state.pendingChoice,
              pendingChoice.actorPlayerId == state.localPlayerId,
              !pendingChoice.isRedactedForViewer,
              !pendingChoice.options.isEmpty,
              onSubmitChoice != nil else {
            return nil
        }
        return pendingChoice
    }

    private var selectedHandCard: MultiplayerRenderableCardShellState? {
        guard let selectedCardId else { return nil }
        return state.localHandCards.first(where: { $0.cardId == selectedCardId })
    }

    private var selectedTableCard: MultiplayerRenderableCardShellState? {
        guard let selectedTableCardId else { return nil }
        return state.tableCards.first(where: { $0.cardId == selectedTableCardId })
    }

    private var focusedTableMonth: Int? {
        selectedHandCard?.month ?? selectedTableCard?.month ?? inspectedMonth
    }

    private var matchedTableCards: Set<String> {
        guard let selectedHandCard else { return [] }
        return Set(
            state.tableCards
                .filter { $0.month == selectedHandCard.month }
                .map(\.cardId)
        )
    }

    private var focusedTableCardIds: Set<String> {
        if let selectedTableCardId {
            return [selectedTableCardId]
        }
        guard let focusedTableMonth else { return [] }
        return Set(
            state.tableCards
                .filter { $0.month == focusedTableMonth }
                .map(\.cardId)
        )
    }

    private var renderedTableMonthBuckets: [MultiplayerTableMonthBucketShellState] {
        if !state.tableMonthBuckets.isEmpty {
            return state.tableMonthBuckets
        }

        let grouped = Dictionary(grouping: state.tableCards, by: \.month)
        return grouped
            .map { bucket in
                MultiplayerTableMonthBucketShellState(
                    month: bucket.key,
                    cards: bucket.value
                )
            }
            .sorted(by: { $0.month < $1.month })
    }

    private var canPlayHandCard: Bool {
        onPlayCard != nil &&
        state.phase == .inTurn &&
        state.currentPlayerId == state.localPlayerId &&
        !state.localHandCards.isEmpty &&
        actionableChoice == nil
    }

    private var canQuitMatch: Bool {
        onQuitTapped != nil && state.currentPlayerId == state.localPlayerId
    }

    private var inputModeLabel: String {
        if actionableChoice != nil {
            return "Choice Pending"
        }
        if canPlayHandCard {
            return "Playable"
        }
        return "Waiting"
    }

    private var handActionSubtitle: String {
        if actionableChoice != nil {
            return "Choice resolution is blocking hand play. Finish the authoritative choice first."
        }
        if state.phase == .waiting || state.phase == .dealing {
            return "Hand play is locked until the authoritative live phase finishes opening and reaches your turn."
        }
        if canPlayHandCard {
            return "Tap a hand card to send playCard immediately. Table focus stays local and only helps you inspect matching months."
        }
        if state.currentPlayerId != state.localPlayerId {
            return "Hand play is locked because the authoritative turn owner is the opponent."
        }
        return "Hand play is waiting for authoritative card ids or reconnect recovery."
    }

    private var selectedHandActionSubtitle: String {
        guard let selectedHandCard else { return handActionSubtitle }
        if matchedTableCards.isEmpty {
            return "Last tapped: \(cardDisplayTitle(selectedHandCard)). The authoritative server will resolve the unmatched line."
        }
        return "Last tapped: \(cardDisplayTitle(selectedHandCard)). \(matchedTableCards.count) same-month table card(s) are visible on the board."
    }

    private var tableActionSubtitle: String {
        if let selectedTableCard {
            if actionableChoice?.choiceKind == .capture,
               let captureOption = captureChoiceOption(matchingTableCardId: selectedTableCard.cardId) {
                return "Tap \(cardDisplayTitle(selectedTableCard)) again or tap its preview stack to submit \(captureOption.optionCode)."
            }
            if let selectedHandCard, selectedHandCard.month == selectedTableCard.month {
                return "Targeting \(cardDisplayTitle(selectedTableCard)) against \(cardDisplayTitle(selectedHandCard)). The authoritative server still resolves the final legal line."
            }
            return "Inspecting \(cardDisplayTitle(selectedTableCard)) on the table. This focus is local-only and does not send a command."
        }
        guard let selectedHandCard else {
            if let inspectedMonth {
                return "Inspecting month \(String(format: "%02d", inspectedMonth)) while waiting for a playable hand tap."
            }
            return "Tap a hand card to send playCard. Table focus only highlights matching month cards locally."
        }
        if matchedTableCards.isEmpty {
            return "\(cardDisplayTitle(selectedHandCard)) has no visible same-month table card. The server will resolve the resulting line."
        }
        return "\(cardDisplayTitle(selectedHandCard)) currently matches \(matchedTableCards.count) table card(s)."
    }

    private var boardCompositionCard: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: "square.grid.3x2.fill",
                        accentColor: Color(red: 0.93, green: 0.73, blue: 0.20)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Board Composition")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(tableActionSubtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    MultiplayerStatusBadge(
                        title: boardFocusStatusTitle,
                        accentColor: focusedTableMonth == nil ? Color(red: 0.93, green: 0.73, blue: 0.20) : Color(red: 0.32, green: 0.82, blue: 0.52)
                    )
                }

                HStack(spacing: 12) {
                    MultiplayerStatPill(label: state.opponentPlayerDisplayName, value: "\(state.opponentScore)P / Go \(state.opponentGoCount)")
                    MultiplayerStatPill(label: "Deck", value: "\(state.deckRemainingCount)")
                    MultiplayerStatPill(label: state.localPlayerDisplayName, value: "\(state.localScore)P / Go \(state.localGoCount)")
                }

                if hasBoardFocus {
                    HStack(alignment: .center, spacing: 10) {
                        MultiplayerStatusBadge(
                            title: "Local Focus",
                            accentColor: Color(red: 0.25, green: 0.77, blue: 0.98)
                        )
                        Text(boardFocusDetail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.76))
                        Spacer(minLength: 0)
                        Button("Clear Focus") {
                            clearBoardFocus()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.77, blue: 0.98))
                    }
                }

                capturedZoneSection(
                    title: "Opponent Captured",
                    subtitle: "Score categories stay visible while you inspect table lines and wait for the next authoritative update.",
                    zone: state.opponentCapturedZone,
                    accentColor: Color(red: 0.25, green: 0.77, blue: 0.98)
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Table Month Buckets")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        MultiplayerStatusBadge(
                            title: focusedTableMonth.map { "Month \(String(format: "%02d", $0))" } ?? "\(state.tableCards.count) Table Cards",
                            accentColor: focusedTableMonth == nil ? Color.white.opacity(0.18) : Color(red: 0.32, green: 0.82, blue: 0.52)
                        )
                        Spacer(minLength: 0)
                    }

                    Text("Tap a month bucket to inspect it. This only changes board focus; it never sends a gameplay command.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))

                    if let selectedTableCard {
                        HStack(spacing: 10) {
                            MultiplayerStatusBadge(
                                title: "Focused Card",
                                accentColor: Color(red: 0.25, green: 0.77, blue: 0.98)
                            )
                            Text(cardDisplayTitle(selectedTableCard))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                    }

                    if renderedTableMonthBuckets.isEmpty {
                        Text("No table month buckets are available yet. The next authoritative snapshot should fill this board surface.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.60))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(renderedTableMonthBuckets) { bucket in
                                monthBucketButton(bucket)
                            }
                        }
                    }
                }

                capturedZoneSection(
                    title: "My Captured",
                    subtitle: "Review what is already banked before committing the next playCard or choice submit.",
                    zone: state.localCapturedZone,
                    accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                )
            }
        }
    }

    private func handCardButton(_ card: MultiplayerRenderableCardShellState) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                inspectedMonth = nil
                selectedTableCardId = nil
                selectedCardId = card.cardId
            }
            guard canPlayHandCard else { return }
            onPlayCard?(card.cardId)
        } label: {
            MultiplayerGameplayCardTile(
                card: card,
                scale: 0.56,
                emphasis: selectedCardId == card.cardId ? .selected : .subtle,
                showsZoneBadge: false
            )
        }
        .disabled(!canPlayHandCard)
        .buttonStyle(.plain)
        .opacity(canPlayHandCard ? 1 : 0.72)
    }

    private func monthBucketButton(_ bucket: MultiplayerTableMonthBucketShellState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    focusMonth(bucket.month)
                } label: {
                    Text("Month \(String(format: "%02d", bucket.month))")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                MultiplayerStatPill(label: "Cards", value: "\(bucket.cards.count)")
                if selectedHandCard?.month == bucket.month {
                    MultiplayerStatusBadge(
                        title: "Hand Match",
                        accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                    )
                } else if selectedTableCard?.month == bucket.month {
                    MultiplayerStatusBadge(
                        title: "Card Focus",
                        accentColor: Color(red: 0.25, green: 0.77, blue: 0.98)
                    )
                } else if inspectedMonth == bucket.month {
                    MultiplayerStatusBadge(
                        title: "Inspecting",
                        accentColor: Color(red: 0.25, green: 0.77, blue: 0.98)
                    )
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(bucket.cards) { card in
                        Button {
                            focusTableCard(card)
                        } label: {
                            MultiplayerGameplayCardTile(
                                card: card,
                                scale: 0.44,
                                emphasis: emphasis(forTableCard: card),
                                showsZoneBadge: true
                            )
                            .frame(width: 108)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Text(monthBucketSubtitle(for: bucket))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(focusedTableMonth == bucket.month ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    focusedTableMonth == bucket.month
                        ? Color(red: 0.32, green: 0.82, blue: 0.52)
                        : Color.white.opacity(0.08),
                    lineWidth: focusedTableMonth == bucket.month ? 1.4 : 1
                )
        )
    }

    private func capturedZoneSection(
        title: String,
        subtitle: String,
        zone: MultiplayerCapturedZoneShellState,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                MultiplayerStatusBadge(
                    title: "\(capturedCardCount(in: zone)) Captured",
                    accentColor: accentColor
                )
                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(zone.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(capturedGroupDisplayTitle(group))
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            MultiplayerStatPill(label: "Count", value: "\(group.cards.count)")
                            Spacer(minLength: 0)
                        }

                        if group.cards.isEmpty {
                            Text("No captured cards yet.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.46))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(group.cards) { card in
                                        MultiplayerGameplayCardTile(
                                            card: card,
                                            scale: 0.36,
                                            emphasis: focusedTableCardIds.contains(card.cardId) ? .selected : (focusedTableMonth == card.month ? .highlighted : .subtle),
                                            showsZoneBadge: false
                                        )
                                        .frame(width: 92)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func choiceOptionCard(
        pendingChoice: MultiplayerChoiceShellState,
        option: MultiplayerChoiceOptionShellState
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedShellText(option.labelKey, fallback: optionFallback(for: option)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("optionCode \(option.optionCode)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if !option.cards.isEmpty {
                        Text("\(option.cards.count) Card Preview")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Text("Preview \(option.scoreDeltaPreviewSelf)/\(option.scoreDeltaPreviewOpponent)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.93, green: 0.73, blue: 0.20))
                }
            }

            if !option.cards.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                    ForEach(option.cards) { card in
                        MultiplayerGameplayCardTile(
                            card: card,
                            scale: 0.44,
                            emphasis: optionCardEmphasis(for: card),
                            showsZoneBadge: true
                        )
                    }
                }
            }

            if optionMatchesCurrentFocus(option) {
                Text(optionFocusDetail(option))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.93, green: 0.73, blue: 0.20))
            }

            MultiplayerSecondaryButton(
                title: localizedShellText(option.labelKey, fallback: optionFallback(for: option)),
                subtitle: "Send \(option.optionCode) for choice \(shortIdentifier(pendingChoice.choiceId)).",
                accentColor: Color(red: 0.24, green: 0.72, blue: 0.96),
                isEnabled: actionableChoice != nil,
                action: {
                    onSubmitChoice?(pendingChoice.choiceId, option.optionCode, nil)
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func syncSelectedCardIfNeeded(reset: Bool = false) {
        if reset {
            selectedCardId = nil
            selectedTableCardId = nil
            inspectedMonth = nil
            return
        }
        guard let selectedCardId else { return }
        let stillExists = state.localHandCards.contains(where: { $0.cardId == selectedCardId }) || state.localPlayableCardIds.contains(selectedCardId)
        if !stillExists {
            self.selectedCardId = nil
        }
    }

    private func syncFocusedTableCardIfNeeded() {
        guard let selectedTableCardId else { return }
        if !state.tableCards.contains(where: { $0.cardId == selectedTableCardId }) {
            self.selectedTableCardId = nil
        }
    }

    private func handleTableCardTap(_ card: MultiplayerRenderableCardShellState) {
        focusTableCard(card)
        guard let captureOption = captureChoiceOption(matchingTableCardId: card.cardId) else { return }
        submitChoiceOption(captureOption)
    }

    private func handleChoicePreviewTap(
        pendingChoice: MultiplayerChoiceShellState,
        option: MultiplayerChoiceOptionShellState,
        card: MultiplayerRenderableCardShellState
    ) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if card.zone == "table" {
                selectedTableCardId = card.cardId
                inspectedMonth = card.month
            } else {
                selectedCardId = card.cardId
            }
        }
        guard pendingChoice.choiceKind == .capture else { return }
        submitChoiceOption(option)
    }

    private func submitChoiceOption(_ option: MultiplayerChoiceOptionShellState) {
        guard let pendingChoice = actionableChoice else { return }
        onSubmitChoice?(pendingChoice.choiceId, option.optionCode, nil)
    }

    private func captureChoiceOption(matchingTableCardId tableCardId: String) -> MultiplayerChoiceOptionShellState? {
        guard let pendingChoice = actionableChoice, pendingChoice.choiceKind == .capture else {
            return nil
        }
        let matchingOptions = pendingChoice.options.filter { option in
            option.cardIds.contains(tableCardId) &&
            (selectedHandCard == nil || option.cardIds.contains(selectedHandCard?.cardId ?? ""))
        }
        guard matchingOptions.count == 1 else { return nil }
        return matchingOptions.first
    }

    private func cardDisplayTitle(_ card: MultiplayerRenderableCardShellState) -> String {
        let kindTitle = card.kind
            .replacingOccurrences(of: "double", with: "double ")
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
        let monthTitle = card.month > 0 ? String(format: "%02d", card.month) : "--"
        if let selectedRole = card.selectedRole {
            return "Month \(monthTitle) \(kindTitle) \(selectedRole.capitalized)"
        }
        return "Month \(monthTitle) \(kindTitle)"
    }

    private func choicePromptFallback(for pendingChoice: MultiplayerChoiceShellState) -> String {
        switch pendingChoice.choiceKind {
        case .capture:
            return "Tap the matching preview or board card to resolve the capture line."
        case .shake:
            return "Decide whether to shake before continuing."
        case .goStop:
            return "Choose whether to continue with Go or end with Stop."
        case .chrysanthemumRole:
            return "Choose how to score the chrysanthemum card."
        }
    }

    private func optionFallback(for option: MultiplayerChoiceOptionShellState) -> String {
        if option.optionCode.hasPrefix("capture_pair") {
            return "Take This Pair"
        }
        return option.optionCode
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var boardFocusStatusTitle: String {
        if let selectedTableCard {
            return cardDisplayTitle(selectedTableCard)
        }
        if selectedHandCard != nil {
            return "\(matchedTableCards.count) Match"
        }
        if let focusedTableMonth {
            return "Month \(String(format: "%02d", focusedTableMonth)) Focus"
        }
        return "Board Open"
    }

    private func monthBucketSubtitle(for bucket: MultiplayerTableMonthBucketShellState) -> String {
        if let selectedTableCard, selectedTableCard.month == bucket.month {
            return "\(cardDisplayTitle(selectedTableCard)) is locally focused. Tap another table card or a hand card to change focus."
        }
        if let selectedHandCard, selectedHandCard.month == bucket.month {
            if bucket.cards.count == 1 {
                return "\(cardDisplayTitle(selectedHandCard)) lines up with one visible table target."
            }
            return "\(cardDisplayTitle(selectedHandCard)) lines up with \(bucket.cards.count) same-month table targets."
        }
        if inspectedMonth == bucket.month {
            return "Inspection only. Tap a hand card afterward to send the authoritative playCard command."
        }
        return "Inspect this month bucket without changing transport state."
    }

    private func capturedCardCount(in zone: MultiplayerCapturedZoneShellState) -> Int {
        zone.groups.reduce(0) { partial, group in
            partial + group.cards.count
        }
    }

    private var opponentProjectionRows: [(String, String)] {
        [
            ("Player", state.opponentPlayerDisplayName),
            ("Score", "\(state.opponentScore)"),
            ("Go", "\(state.opponentGoCount)"),
            ("Hand", "\(state.opponentHandCount)")
        ]
    }

    private var tableProjectionRows: [(String, String)] {
        [
            ("Deck", "\(state.deckRemainingCount)"),
            ("Buckets", "\(renderedTableMonthBuckets.count)"),
            ("Focus", focusedTableProjectionLabel),
            ("Actor", state.currentPlayerId == state.localPlayerId ? "You" : state.opponentPlayerDisplayName)
        ]
    }

    private var localProjectionRows: [(String, String)] {
        [
            ("Player", state.localPlayerDisplayName),
            ("Score", "\(state.localScore)"),
            ("Go", "\(state.localGoCount)"),
            ("Hand", "\(state.localHandCount)")
        ]
    }

    private var focusedTableProjectionLabel: String {
        if let selectedTableCard {
            return String(format: "%02d", selectedTableCard.month)
        }
        if let focusedTableMonth {
            return String(format: "%02d", focusedTableMonth)
        }
        return "Open"
    }

    private func projectionSummaryCard(
        title: String,
        accentColor: Color,
        rows: [(String, String)]
    ) -> some View {
        MultiplayerBoardZoneCard(title: title, accentColor: accentColor, rows: rows)
    }

    private func focusMonth(_ month: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTableCardId = nil
            if let selectedHandCard, selectedHandCard.month == month {
                inspectedMonth = nil
                return
            }
            if inspectedMonth == month && selectedHandCard == nil {
                inspectedMonth = nil
                return
            }
            if actionableChoice?.choiceKind != .capture {
                selectedCardId = nil
            }
            inspectedMonth = month
        }
    }

    private func focusTableCard(_ card: MultiplayerRenderableCardShellState) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if selectedTableCardId == card.cardId {
                selectedTableCardId = nil
                if selectedHandCard == nil {
                    inspectedMonth = card.month
                }
                return
            }
            if let selectedHandCard, selectedHandCard.month != card.month {
                if actionableChoice?.choiceKind != .capture {
                    selectedCardId = nil
                }
            }
            inspectedMonth = card.month
            selectedTableCardId = card.cardId
        }
    }

    private func emphasis(forTableCard card: MultiplayerRenderableCardShellState) -> MultiplayerGameplayCardEmphasis {
        if selectedTableCardId == card.cardId {
            return .selected
        }
        if focusedTableMonth == card.month {
            return .highlighted
        }
        return .subtle
    }

    private func optionCardEmphasis(for card: MultiplayerRenderableCardShellState) -> MultiplayerGameplayCardEmphasis {
        if selectedHandCard?.cardId == card.cardId || selectedTableCardId == card.cardId {
            return .selected
        }
        if focusedTableMonth == card.month {
            return .highlighted
        }
        return card.zone == "hand" ? .highlighted : .subtle
    }

    private func capturedGroupDisplayTitle(_ group: MultiplayerCapturedGroupShellState) -> String {
        switch group.kind {
        case "bright":
            return "Bright · 광"
        case "animal":
            return "Animal · 10끗"
        case "ribbon":
            return "Ribbon · 5끗"
        case "junk":
            return "Junk · 피"
        default:
            return group.title
        }
    }

    private var hasBoardFocus: Bool {
        selectedHandCard != nil || selectedTableCard != nil || inspectedMonth != nil
    }

    private var boardFocusDetail: String {
        if let selectedHandCard, let selectedTableCard, selectedHandCard.month == selectedTableCard.month {
            return "\(cardDisplayTitle(selectedHandCard)) + \(cardDisplayTitle(selectedTableCard)) are locally aligned."
        }
        if let selectedTableCard {
            return "\(cardDisplayTitle(selectedTableCard)) is focused for local inspection."
        }
        if let selectedHandCard {
            return "\(cardDisplayTitle(selectedHandCard)) was the latest locally tapped hand card."
        }
        if let inspectedMonth {
            return "Month \(String(format: "%02d", inspectedMonth)) is focused for local inspection."
        }
        return "No local focus is active."
    }

    private func clearBoardFocus() {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedCardId = nil
            selectedTableCardId = nil
            inspectedMonth = nil
        }
    }

    private func optionMatchesCurrentFocus(_ option: MultiplayerChoiceOptionShellState) -> Bool {
        if let selectedTableCardId, option.cardIds.contains(selectedTableCardId) {
            return true
        }
        if let selectedHandCard, option.cardIds.contains(selectedHandCard.cardId) {
            return true
        }
        return false
    }

    private func optionFocusDetail(_ option: MultiplayerChoiceOptionShellState) -> String {
        if let selectedHandCard, let selectedTableCardId, option.cardIds.contains(selectedHandCard.cardId), option.cardIds.contains(selectedTableCardId) {
            return "Focused hand and table cards are both part of this option."
        }
        if let selectedHandCard, option.cardIds.contains(selectedHandCard.cardId) {
            return "Focused hand card is part of this option."
        }
        return "Focused table target is part of this option."
    }

    private func captureChoiceInteractionSubtitle(for option: MultiplayerChoiceOptionShellState) -> String {
        if optionMatchesCurrentFocus(option) {
            return "Tap the highlighted preview stack to submit this capture line immediately."
        }
        return "Tap any card in this preview stack to choose this capture line."
    }
}

private enum MultiplayerGameplayCardEmphasis: Equatable {
    case subtle
    case highlighted
    case selected

    var accentColor: Color {
        switch self {
        case .subtle:
            return Color.white.opacity(0.12)
        case .highlighted:
            return Color(red: 0.93, green: 0.73, blue: 0.20)
        case .selected:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .subtle:
            return 0.06
        case .highlighted:
            return 0.12
        case .selected:
            return 0.18
        }
    }
}

private struct MultiplayerGameplayCardTile: View {
    let card: MultiplayerRenderableCardShellState
    let scale: CGFloat
    let emphasis: MultiplayerGameplayCardEmphasis
    let showsZoneBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if showsZoneBadge, let zoneLabel {
                    MultiplayerStatusBadge(
                        title: zoneLabel,
                        accentColor: emphasis.accentColor
                    )
                }
                Spacer(minLength: 0)
                Text(card.month > 0 ? String(format: "%02d", card.month) : "--")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }

            cardArtwork
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.cardId)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(emphasis.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(emphasis.accentColor, lineWidth: emphasis == .subtle ? 1 : 1.4)
        )
    }

    private var cardArtwork: some View {
        Group {
            if let resolvedCard {
                CardView(card: resolvedCard, scale: scale)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.89, blue: 0.78))
                    .frame(width: 64, height: 96)
                    .overlay(
                        VStack(spacing: 6) {
                            Text(card.month > 0 ? String(format: "%02d", card.month) : "--")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(0.78))
                            Text(kindLabel)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.black.opacity(0.66))
                                .multilineTextAlignment(.center)
                        }
                        .padding(8)
                    )
            }
        }
    }

    private var kindLabel: String {
        let base = card.kind
            .replacingOccurrences(of: "doubleJunk", with: "Double Junk")
            .replacingOccurrences(of: "doublePi", with: "Double Pi")
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
        guard let selectedRole = card.selectedRole else {
            return base
        }
        return "\(base) \(selectedRole.capitalized)"
    }

    private var zoneLabel: String? {
        switch card.zone {
        case "hand":
            return "Hand"
        case "table":
            return "Table"
        case "captured":
            return "Captured"
        default:
            return nil
        }
    }

    private var resolvedCard: Card? {
        guard let month = Month(rawValue: card.month),
              let cardType = resolvedCardType else {
            return nil
        }
        return Card(
            id: card.cardId,
            month: month,
            type: cardType,
            imageIndex: card.imageIndex,
            selectedRole: resolvedRole
        )
    }

    private var resolvedCardType: CardType? {
        switch card.kind {
        case "bright":
            return .bright
        case "animal":
            return .animal
        case "ribbon":
            return .ribbon
        case "junk":
            return .junk
        case "doubleJunk", "doublePi":
            return .doubleJunk
        default:
            return nil
        }
    }

    private var resolvedRole: CardRole? {
        switch card.selectedRole {
        case "animal":
            return .animal
        case "doublePi", "double_pi":
            return .doublePi
        default:
            return nil
        }
    }
}

private struct MultiplayerLiveBoardCard: View {
    let card: MultiplayerRenderableCardShellState
    let scale: CGFloat
    let emphasis: MultiplayerGameplayCardEmphasis
    
    var body: some View {
        MultiplayerGameplayCardTile(
            card: card,
            scale: scale,
            emphasis: emphasis,
            showsZoneBadge: false
        )
    }
}

struct MultiplayerReconnectOverlay: View {
    let state: MultiplayerReconnectOverlayState
    let onLeaveTapped: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    MultiplayerGlyphBadge(
                        systemName: state.phase.symbolName,
                        accentColor: state.phase.accentColor
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.phase.title)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(state.phase.detail)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                    }

                    Spacer(minLength: 0)

                    if state.phase != .expired {
                        ProgressView()
                            .tint(.white)
                    }
                }

                HStack(spacing: 12) {
                    MultiplayerStatPill(label: "Room", value: shortIdentifier(state.roomId))
                    MultiplayerStatPill(label: "Heartbeat", value: "\(state.heartbeatIntervalMs / 1000)s")
                    MultiplayerStatPill(label: "Timeout", value: "\(state.disconnectTimeoutMs / 1000)s")
                    MultiplayerStatPill(label: "Grace", value: countdownText(to: state.graceExpiresAt, reference: Date.now))
                }

                VStack(alignment: .leading, spacing: 10) {
                    reconnectStep("1", title: "helloAck", detail: "Resume mode and timing policy have to land first.")
                    reconnectStep("2", title: "roomSnapshot", detail: "Room members, presence, and room sequence re-seed the route.")
                    reconnectStep("3", title: "gameSnapshot", detail: "The live projection unlocks only after the fresh game snapshot applies.")
                }

                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last Applied State")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        HStack(spacing: 12) {
                            MultiplayerStatPill(label: "Room Seq", value: "\(state.lastRoomSequence)")
                            MultiplayerStatPill(label: "State Version", value: "\(state.lastAppliedStateVersion ?? 0)")
                            MultiplayerStatPill(label: "Snapshot", value: shortIdentifier(state.lastSnapshotId ?? "pending"))
                        }
                    }
                }

                if state.phase == .expired {
                    MultiplayerSecondaryButton(
                        title: "Leave Multiplayer",
                        subtitle: "Terminal recovery only. Input stays locked.",
                        accentColor: state.phase.accentColor
                    ) {
                        onLeaveTapped()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.13, blue: 0.15).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .padding(24)
        }
    }

    private func reconnectStep(_ step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .frame(width: 28, height: 28)
                .background(Circle().fill(state.phase.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
            }

            Spacer(minLength: 0)
        }
    }
}

struct MultiplayerResultView: View {
    let state: MultiplayerResultShellState
    let onLeaveTapped: () -> Void
    let showsIntegrationNotes: Bool

    init(
        state: MultiplayerResultShellState,
        showsIntegrationNotes: Bool = true,
        onLeaveTapped: @escaping () -> Void
    ) {
        self.state = state
        self.onLeaveTapped = onLeaveTapped
        self.showsIntegrationNotes = showsIntegrationNotes
    }

    var body: some View {
        MultiplayerShellSurface(title: "Match Result", subtitle: "Rendered only after an authoritative terminal summary payload is available. Dismissal waits for room lifecycle completion.") {
            VStack(alignment: .leading, spacing: 18) {
                MultiplayerBannerView(state: lifecycleBanner)

                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            MultiplayerGlyphBadge(
                                systemName: state.isDraw ? "equal.circle.fill" : (didLocalPlayerWin ? "trophy.fill" : "flag.slash.fill"),
                                accentColor: headlineAccentColor
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(headlineTitle)
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(headlineDetail)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.74))
                            }

                            Spacer(minLength: 0)

                            MultiplayerStatusBadge(
                                title: "Round \(state.roundIndex)",
                                accentColor: headlineAccentColor
                            )
                        }

                        HStack(spacing: 12) {
                            MultiplayerStatPill(label: "Reason", value: friendlyShellIdentifier(state.endReasonCode))
                            MultiplayerStatPill(
                                label: "Reason Text",
                                value: localizedShellText(
                                    state.endReasonMessageKey,
                                    fallback: multiplayerShellFallbackText(for: state.endReasonMessageKey) ?? state.endReasonCode
                                )
                            )
                            MultiplayerStatPill(label: "Leave State", value: state.leavePolicy.title)
                            MultiplayerStatPill(
                                label: "Leave Text",
                                value: localizedShellText(
                                    state.leavePolicy.messageKey,
                                    fallback: state.leavePolicy.subtitle
                                )
                            )
                            if let forfeitingPlayerId = state.forfeitingPlayerId {
                                MultiplayerStatPill(label: "Forfeit", value: shortIdentifier(forfeitingPlayerId))
                            }
                        }
                    }
                }

                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Final Scores")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        ForEach(state.finalScores) { row in
                            resultScoreRow(row)
                        }
                    }
                }

                if let settlementSummary = state.settlementSummary {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Settlement Summary")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Final Score", value: "\(settlementSummary.finalScore)")
                                MultiplayerStatPill(label: "Formula", value: settlementSummary.scoreFormula)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                                ForEach(settlementSummary.flags) { flag in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(flag.isActive ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color.white.opacity(0.18))
                                            .frame(width: 8, height: 8)
                                        Text(flag.label)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(flag.isActive ? .white : .white.opacity(0.50))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(flag.isActive ? 0.12 : 0.05))
                                    )
                                }
                            }
                        }
                    }
                }

                if showsIntegrationNotes {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Integration Notes")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            ForEach(state.integrationNotes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color(red: 0.95, green: 0.65, blue: 0.20))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    Text(multiplayerShellRenderableNote(note))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.78))
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }

                MultiplayerSecondaryButton(
                    title: state.leavePolicy.title,
                    subtitle: state.leavePolicy.subtitle,
                    accentColor: Color(red: 0.88, green: 0.30, blue: 0.24),
                    isEnabled: state.leavePolicy.isEnabled,
                    showsProgress: state.leavePolicy.showsProgress
                ) {
                    onLeaveTapped()
                }
            }
        }
    }

    private var didLocalPlayerWin: Bool {
        state.winnerPlayerId == state.localPlayerId
    }

    private var headlineTitle: String {
        if state.isDraw {
            return "Draw"
        }
        return didLocalPlayerWin ? "Victory" : "Defeat"
    }

    private var headlineDetail: String {
        if state.isDraw {
            return "The round ended without a winner. Settlement stayed neutral."
        }
        if let forfeitingPlayerId = state.forfeitingPlayerId {
            let forfeitingLabel = forfeitingPlayerId == state.localPlayerId ? "You" : "The opponent"
            return "\(forfeitingLabel) forfeited before the room closed."
        }
        return didLocalPlayerWin ? "The authoritative result marks the local player as winner." : "The authoritative result marks the opponent as winner."
    }

    private var headlineAccentColor: Color {
        if state.isDraw {
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        }
        return didLocalPlayerWin ? Color(red: 0.93, green: 0.73, blue: 0.20) : Color(red: 0.88, green: 0.30, blue: 0.24)
    }

    private var lifecycleBanner: MultiplayerBannerState {
        switch state.leavePolicy {
        case .leaveAvailable:
            return MultiplayerBannerState(
                style: .info,
                title: "Result Retained",
                detail: localizedShellText(
                    state.leavePolicy.messageKey,
                    fallback: "The terminal summary is final. Keep the route open until the player explicitly sends leaveRoom."
                ),
                messageKey: state.leavePolicy.messageKey
            )
        case .pendingLeaveAcknowledgement:
            return MultiplayerBannerState(
                style: .warning,
                title: "Leave Pending",
                detail: localizedShellText(
                    state.leavePolicy.messageKey,
                    fallback: "The local session already sent leaveRoom. The route stays here until the authoritative leave ack or roomClosed signal arrives."
                ),
                messageKey: state.leavePolicy.messageKey
            )
        case .pendingRoomClosure:
            return MultiplayerBannerState(
                style: .info,
                title: "Waiting For roomClosed",
                detail: localizedShellText(
                    state.leavePolicy.messageKey,
                    fallback: "The local seat already left. Only the final roomClosed signal is still pending."
                ),
                messageKey: state.leavePolicy.messageKey
            )
        }
    }

    private func resultScoreRow(_ row: MultiplayerResultScoreRowState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.displayName)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    if row.isLocalPlayer {
                        MultiplayerStatusBadge(
                            title: "You",
                            accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                        )
                    }
                }
                Text(shortIdentifier(row.playerId))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                MultiplayerStatPill(label: "Score", value: "\(row.score)")
                MultiplayerStatPill(label: "Go", value: "\(row.goCount)")
                MultiplayerStatPill(label: "Money", value: "\(row.money)")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(row.isLocalPlayer ? 0.10 : 0.06))
        )
    }
}

private enum MultiplayerMappedRoute: String, CaseIterable, Identifiable {
    case entry
    case room
    case live
    case reconnect
    case result

    var id: String { rawValue }

    var label: String {
        switch self {
        case .entry:
            return "Entry"
        case .room:
            return "Room"
        case .live:
            return "Live"
        case .reconnect:
            return "Reconnect"
        case .result:
            return "Result"
        }
    }
}

struct MultiplayerMappedPayloadDemoView: View {
    @State private var route: MultiplayerMappedRoute = .entry

    private let mapped = MultiplayerShellMappedPreview.demo

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text("Mapped Contract Demo")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            MultiplayerStatusBadge(
                                title: route.label,
                                accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                            )
                            Spacer(minLength: 0)
                        }

                        Text("This route is seeded by UI-facing mapper functions that consume Agent 1 contract payloads plus local room/hello DTOs. It stays separate from the coordinator-backed debug tab.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(MultiplayerMappedRoute.allCases) { item in
                                    let isSelected = route == item
                                    mockControlButton(
                                        item.label,
                                        accentColor: isSelected
                                            ? Color(red: 0.31, green: 0.74, blue: 0.97)
                                            : Color.white.opacity(0.18),
                                        isSelected: isSelected
                                    ) {
                                        route = item
                                    }
                                }
                            }
                        }
                    }
                }

                switch route {
                case .entry:
                    MultiplayerEntryView(
                        state: mapped.entry,
                        availableActions: [.quickMatch, .createInvite, .joinInvite]
                    ) { _ in }
                case .room:
                    MultiplayerRoomView(
                        state: mapped.room,
                        onReadyTapped: {},
                        onLeaveTapped: {}
                    )
                case .live:
                    MultiplayerLiveShellView(state: mapped.live)
                case .reconnect:
                    ZStack {
                        MultiplayerLiveShellView(state: mapped.live)
                        MultiplayerReconnectOverlay(state: mapped.reconnect, onLeaveTapped: {})
                    }
                case .result:
                    MultiplayerResultView(state: mapped.result, onLeaveTapped: {})
                }
            }
            .padding(20)
        }
    }

    private func mockControlButton(
        _ title: String,
        accentColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? .black.opacity(0.82) : .white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(accentColor)
                )
        }
        .buttonStyle(.plain)
    }
}

struct MultiplayerTransportRouteHostView: View {
    @StateObject private var store: MultiplayerShellStore
    @State private var inviteCodeInput: String
    private let configuration: MultiplayerTransportRouteConfiguration

    @MainActor
    init(configuration: MultiplayerTransportRouteConfiguration = .productPreparation()) {
        self.configuration = configuration
        _store = StateObject(
            wrappedValue: MultiplayerShellStore.transportBacked(configuration: configuration)
        )
        _inviteCodeInput = State(initialValue: multiplayerNormalizedInviteCodeValue(configuration.mode.pendingInviteCode) ?? "")
    }

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if showsProductEntryPrelude {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "person.crop.circle.badge.plus",
                                    accentColor: Color(red: 0.98, green: 0.59, blue: 0.25)
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Multiplayer Product Entry")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("Create Room, Join Invite, and Resume all stay on authoritative helloAck -> roomSnapshot attach. Phase 0 uses numeric `inviteCode` values and resolves them to room ids at the bootstrap boundary.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }

                                Spacer(minLength: 0)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invite Code")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.84))

                                TextField("Enter invite code", text: $inviteCodeInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.black.opacity(0.22))
                                    )
                            }

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Join Invite", value: normalizedInviteCode == nil ? "Hidden" : "Ready")
                                MultiplayerStatPill(label: "Share Shape", value: "inviteCode")
                                MultiplayerStatPill(label: "Phase 0", value: "numeric inviteCode")
                            }
                        }
                    }
                }

                MultiplayerShellShowcaseView(store: store)
            }
            .padding(20)
        }
        .onAppear {
            store.updateEntryJoinIdentifier(normalizedInviteCode)
        }
        .onChange(of: normalizedInviteCode) { newValue in
            store.updateEntryJoinIdentifier(newValue)
        }
    }

    private var showsProductEntryPrelude: Bool {
        if case .productPreparation = configuration.mode {
            return true
        }
        return false
    }

    private var normalizedInviteCode: String? {
        multiplayerNormalizedInviteCodeValue(inviteCodeInput)
    }
}

struct MultiplayerProductMultiplayerRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: MultiplayerShellStore
    @State private var selectedTab: MultiplayerProductRouteTab = .home
    @State private var inviteCodeInput: String
    @State private var automationHasStarted = false
    @State private var automationStep: MultiplayerProductRouteAutomationStep = .idle
    let initialInviteCode: String?
    private let automation: MultiplayerProductRouteAutomationConfig

    @MainActor
    init(initialInviteCode: String? = nil) {
        self.initialInviteCode = initialInviteCode
        self.automation = MultiplayerProductRouteAutomationConfig.current
        let configuration = MultiplayerTransportRouteConfiguration.productPreparation(inviteCode: initialInviteCode)
        _store = StateObject(
            wrappedValue: MultiplayerShellStore.transportBacked(configuration: configuration)
        )
        _inviteCodeInput = State(initialValue: multiplayerNormalizedInviteCodeValue(initialInviteCode) ?? "")
    }

    var body: some View {
        Group {
            if let liveSnapshot = store.authoritativeLiveSnapshot, store.route == .live {
                MultiplayerProductLiveGameView(
                    store: store,
                    snapshot: liveSnapshot
                )
            } else {
                NavigationStack {
                    TabView(selection: $selectedTab) {
                        MultiplayerProductHomeView(
                            store: store,
                            inviteCodeInput: $inviteCodeInput,
                            selectedTab: $selectedTab
                        )
                        .tag(MultiplayerProductRouteTab.home)
                        .tabItem {
                            Label("Home", systemImage: "house.fill")
                        }

                        MultiplayerProductPlayView(
                            store: store,
                            inviteCodeInput: $inviteCodeInput
                        )
                        .tag(MultiplayerProductRouteTab.play)
                        .tabItem {
                            Label("Play", systemImage: "suit.heart.fill")
                        }

                        MultiplayerProductSessionView(
                            store: store,
                            inviteCodeInput: $inviteCodeInput
                        )
                        .tag(MultiplayerProductRouteTab.session)
                        .tabItem {
                            Label("Session", systemImage: "rectangle.stack.person.crop.fill")
                        }
                    }
                    .navigationTitle(selectedTab.title)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            store.updateEntryJoinIdentifier(normalizedInviteCode)
            runAutomationIfNeeded()
        }
        .onChange(of: normalizedInviteCode) { newValue in
            store.updateEntryJoinIdentifier(newValue)
        }
        .onChange(of: store.route) { newValue in
            selectedTab = newValue == .entry ? .home : .play
            continueAutomationIfNeeded(for: newValue)
        }
        .onChange(of: store.roomState.roomState) { _ in
            continueAutomationIfNeeded(for: store.route)
        }
        .onChange(of: localMemberIsReady) { _ in
            continueAutomationIfNeeded(for: store.route)
        }
    }

    private var normalizedInviteCode: String? {
        multiplayerNormalizedInviteCodeValue(inviteCodeInput)
    }

    private var localMemberIsReady: Bool {
        store.roomState.members.first(where: \.isLocalPlayer)?.ready ?? false
    }

    private var localMemberCanAutoReady: Bool {
        guard let localMember = store.roomState.members.first(where: \.isLocalPlayer) else {
            return false
        }
        return localMember.presence == .connected
            && !localMember.ready
            && store.roomState.members.count == 2
            && store.roomState.roomState == .waitingForReady
    }

    private func runAutomationIfNeeded() {
        guard automation.isEnabled, !automationHasStarted else { return }
        automationHasStarted = true
        automationStep = .bootstrapping
        inviteCodeInput = automation.inviteCode ?? inviteCodeInput
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: automation.initialDelayNanoseconds)
            switch automation.role {
            case .host:
                guard store.route == .entry else { return }
                automationStep = .creatingRoom
                store.handleEntryAction(.createInvite)
            case .guest:
                guard store.route == .entry else { return }
                automationStep = .joiningRoom
                store.updateEntryJoinIdentifier(normalizedInviteCode)
                store.handleEntryAction(.joinInvite)
            case .disabled:
                break
            }
        }
    }

    private func continueAutomationIfNeeded(for route: MultiplayerShellRoute) {
        guard automation.isEnabled, automationHasStarted else { return }
        switch route {
        case .room:
            if localMemberCanAutoReady,
               automationStep == .creatingRoom || automationStep == .joiningRoom || automationStep == .bootstrapping {
                automationStep = .waitingForReadyAck
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: automation.readyDelayNanoseconds)
                    store.performControl(.ready)
                }
            }
        case .live:
            if automationStep != .completed {
                automationStep = .completed
            }
        case .entry, .result:
            break
        }
    }
}

private enum MultiplayerProductRouteAutomationStep: String {
    case idle
    case bootstrapping
    case creatingRoom
    case joiningRoom
    case waitingForReadyAck
    case completed
}

private struct MultiplayerProductRouteAutomationConfig {
    enum Role: String {
        case disabled
        case host
        case guest
    }

    let role: Role
    let inviteCode: String?
    let initialDelayNanoseconds: UInt64
    let readyDelayNanoseconds: UInt64

    static var current: MultiplayerProductRouteAutomationConfig {
        let environment = ProcessInfo.processInfo.environment
        let role = Role(rawValue: environment["GOSTOP_MP_AUTOROLE"] ?? "") ?? .disabled
        let inviteCode = multiplayerNormalizedInviteCodeValue(environment["GOSTOP_MP_AUTOINVITE"])
        let initialDelay = Self.nanoseconds(
            milliseconds: environment["GOSTOP_MP_AUTODELAY_MS"],
            fallback: role == .guest ? 1800 : 900
        )
        let readyDelay = Self.nanoseconds(
            milliseconds: environment["GOSTOP_MP_AUTOREADY_DELAY_MS"],
            fallback: role == .guest ? 1200 : 900
        )
        return MultiplayerProductRouteAutomationConfig(
            role: role,
            inviteCode: inviteCode,
            initialDelayNanoseconds: initialDelay,
            readyDelayNanoseconds: readyDelay
        )
    }

    var isEnabled: Bool {
        role != .disabled
    }

    private static func nanoseconds(milliseconds rawValue: String?, fallback: Int) -> UInt64 {
        let parsedValue = rawValue.flatMap(Int.init) ?? fallback
        let clamped = max(0, parsedValue)
        return UInt64(clamped) * 1_000_000
    }
}

private struct MultiplayerProductLiveGameView: View {
    @ObservedObject var store: MultiplayerShellStore
    let snapshot: MultiplayerSnapshot

    var body: some View {
        ZStack {
            MultiplayerAuthoritativeGameCoordinatorView(
                snapshot: snapshot,
                onActionSent: { action in
                    store.handleGameplayActionFromGameView(action)
                },
                onProductRenderProbeChanged: { probe in
                    store.updateProductRenderProbe(probe)
                },
                onAutomationActionDriverChanged: { sourceID, driver in
                    store.updateProductGameplayActionDriver(driver, sourceID: sourceID)
                }
            )

            if let reconnectOverlay = store.reconnectOverlay {
                MultiplayerReconnectOverlay(
                    state: reconnectOverlay,
                    onLeaveTapped: { store.reset() }
                )
            }
        }
        .ignoresSafeArea()
    }
}

private enum MultiplayerProductRouteTab: String, CaseIterable, Identifiable {
    case home
    case play
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Multiplayer Home"
        case .play:
            return "Multiplayer"
        case .session:
            return "Session"
        }
    }
}

private struct MultiplayerProductHomeView: View {
    @ObservedObject var store: MultiplayerShellStore
    @Binding var inviteCodeInput: String
    @Binding var selectedTab: MultiplayerProductRouteTab

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "house.fill",
                                    accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Multiplayer Home")
                                        .font(.system(size: 22, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("This is the shipped alpha launcher inside the current root-sheet route. Create Room, Join Invite, Resume, reconnect, and result dismissal still follow the same authoritative lifecycle.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }

                                Spacer(minLength: 0)

                                MultiplayerStatusBadge(
                                    title: store.route.label,
                                    accentColor: routeAccentColor
                                )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invite Code")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.84))

                                TextField("Enter invite code", text: $inviteCodeInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.black.opacity(0.22))
                                    )
                            }

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Join Invite", value: normalizedInviteCode == nil ? "Hidden" : "Ready")
                                MultiplayerStatPill(label: "Resume", value: store.entryState.persistedResume?.isAttachReady == true ? "Ready" : "Missing")
                                MultiplayerStatPill(label: "Placement", value: "Home Launcher")
                            }
                        }
                    }

                    if store.route == .entry {
                        MultiplayerShellShowcaseView(
                            store: store,
                            chrome: .product,
                            showsBackground: false
                        )
                    } else {
                        MultiplayerPanelCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    MultiplayerGlyphBadge(
                                        systemName: "arrowshape.turn.up.right.fill",
                                        accentColor: routeAccentColor
                                    )

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(activeRouteTitle)
                                            .font(.system(size: 20, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text(activeRouteDetail)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.74))
                                    }
                                    Spacer(minLength: 0)
                                }

                                HStack(spacing: 12) {
                                    MultiplayerStatPill(label: "Route", value: store.route.label)
                                    MultiplayerStatPill(label: "Transport", value: store.sourceLabel)
                                    MultiplayerStatPill(label: "Invite", value: normalizedInviteCode ?? "Unset")
                                }

                                MultiplayerPrimaryButton(
                                    title: "Open Play Surface",
                                    subtitle: "Switch to the board-focused tab without changing any lifecycle state.",
                                    isBusy: false,
                                    accentColor: routeAccentColor
                                ) {
                                    selectedTab = .play
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var normalizedInviteCode: String? {
        multiplayerNormalizedInviteCodeValue(inviteCodeInput)
    }

    private var routeAccentColor: Color {
        switch store.route {
        case .entry:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .room:
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        case .live:
            return Color(red: 0.93, green: 0.73, blue: 0.20)
        case .result:
            return Color(red: 0.88, green: 0.30, blue: 0.24)
        }
    }

    private var activeRouteTitle: String {
        switch store.route {
        case .entry:
            return "Ready To Launch"
        case .room:
            return "Room In Progress"
        case .live:
            return "Live Match Active"
        case .result:
            return "Result Retained"
        }
    }

    private var activeRouteDetail: String {
        switch store.route {
        case .entry:
            return "Use the entry actions below. The route only advances after helloAck plus roomSnapshot."
        case .room:
            return "The room is already attached. Move to Play to see ready, presence, and start-state changes."
        case .live:
            return "A live board is active. Move to Play for hand, table, captured, and authoritative gameplay actions."
        case .result:
            return "The terminal summary is retained. Leave still waits for leaveAcknowledged or roomClosed."
        }
    }
}

private enum MultiplayerProductPlacementCandidate: String, CaseIterable, Identifiable {
    case homeLaunch
    case modeTab
    case quickAccessMenu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homeLaunch:
            return "Home Launcher"
        case .modeTab:
            return "Mode Tab"
        case .quickAccessMenu:
            return "Quick Access"
        }
    }

    var symbolName: String {
        switch self {
        case .homeLaunch:
            return "house.fill"
        case .modeTab:
            return "square.grid.2x2.fill"
        case .quickAccessMenu:
            return "ellipsis.circle.fill"
        }
    }

    var badgeTitle: String {
        switch self {
        case .homeLaunch:
            return "Deferred Remount"
        case .modeTab:
            return "Deferred IA"
        case .quickAccessMenu:
            return "Deferred Shortcut"
        }
    }

    var accentColor: Color {
        switch self {
        case .homeLaunch:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .modeTab:
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        case .quickAccessMenu:
            return Color(red: 0.95, green: 0.65, blue: 0.20)
        }
    }

    var summary: String {
        switch self {
        case .homeLaunch:
            return "Replace the shipped alpha root-sheet launcher with a clearer multiplayer tile on the main home surface."
        case .modeTab:
            return "Promote multiplayer to a first-class mode once app-level navigation grows beyond a single launcher."
        case .quickAccessMenu:
            return "Keep a lightweight resume or invite entry in a toolbar/menu for returning players."
        }
    }

    var detail: String {
        switch self {
        case .homeLaunch:
            return "Best next step for discovery without changing transport or lifecycle rules. Create, Join Invite, and Resume can all stay inside the same product route."
        case .modeTab:
            return "Works when the app gains a stable game-mode split. Until then it risks over-weighting multiplayer before surrounding IA is ready."
        case .quickAccessMenu:
            return "Useful after the main placement lands, but too hidden to be the only entry because invite creation and first-time join need stronger visibility."
        }
    }
}

private struct MultiplayerProductPlayView: View {
    @ObservedObject var store: MultiplayerShellStore
    @Binding var inviteCodeInput: String

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            if store.route == .live {
                MultiplayerShellShowcaseView(
                    store: store,
                    chrome: .product,
                    showsBackground: false
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "suit.heart.fill",
                                    accentColor: routeAccentColor
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Current Route")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Home handles alpha entry. This tab keeps room, live, reconnect, and result surfaces front and center without bypassing any authoritative lifecycle step.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }

                                Spacer(minLength: 0)

                                MultiplayerStatusBadge(
                                    title: store.route.label,
                                    accentColor: routeAccentColor
                                )
                            }

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Invite", value: normalizedInviteCode ?? "Unset")
                                MultiplayerStatPill(label: "Transport", value: store.sourceLabel)
                                MultiplayerStatPill(label: "Result Leave", value: store.route == .result ? "Ack / roomClosed" : "Idle")
                            }
                        }
                    }

                    MultiplayerShellShowcaseView(
                        store: store,
                        chrome: .product,
                        showsBackground: false
                    )
                }
                .padding(.top, 20)
            }
        }
    }

    private var normalizedInviteCode: String? {
        multiplayerNormalizedInviteCodeValue(inviteCodeInput)
    }

    private var routeAccentColor: Color {
        switch store.route {
        case .entry:
            return Color(red: 0.93, green: 0.73, blue: 0.20)
        case .room:
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        case .live:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .result:
            return Color(red: 0.88, green: 0.30, blue: 0.24)
        }
    }
}

private struct MultiplayerProductSessionView: View {
    @ObservedObject var store: MultiplayerShellStore
    @Binding var inviteCodeInput: String

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "shield.lefthalf.filled",
                                    accentColor: Color(red: 0.31, green: 0.74, blue: 0.97)
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Session Lifecycle")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("This tab keeps the shipped alpha lifecycle promises visible while the play tab stays focused on the current route.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                                Spacer(minLength: 0)
                            }

                            sessionRule("Create / Join / Resume", detail: "Entry only advances after helloAck plus roomSnapshot land.")
                            sessionRule("Reconnect", detail: "Overlay stays blocking until roomSnapshot and gameSnapshot finish applying.")
                            sessionRule("Result Dismissal", detail: "Leave closes only after leaveAcknowledged or roomClosed arrives.")
                        }
                    }

                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "square.grid.2x2.fill",
                                    accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Shipped Alpha Placement")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Phase 0 ships on the existing root-sheet baseline. Inside the sheet, `Home / Play / Session` is the accepted alpha information architecture.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Shipped", value: "Root Sheet")
                                MultiplayerStatPill(label: "Inside", value: "Home / Play / Session")
                                MultiplayerStatPill(label: "Lifecycle", value: "Locked")
                            }
                        }
                    }

                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                MultiplayerGlyphBadge(
                                    systemName: "arrow.right.circle.fill",
                                    accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Deferred After Alpha")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("These are real next steps, but they are explicitly deferred beyond the shipped alpha boundary.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                                Spacer(minLength: 0)
                            }

                            VStack(spacing: 10) {
                                ForEach(MultiplayerProductPlacementCandidate.allCases) { candidate in
                                    placementCandidateCard(candidate)
                                }
                            }
                        }
                    }

                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Current Session")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            HStack(spacing: 12) {
                                MultiplayerStatPill(label: "Invite", value: normalizedInviteCode ?? "Unset")
                                MultiplayerStatPill(label: "Route", value: store.route.label)
                                MultiplayerStatPill(label: "Transport", value: store.sourceLabel)
                            }

                            if !store.statusItems.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                    ForEach(store.statusItems) { item in
                                        MultiplayerStatPill(label: item.label, value: item.value)
                                    }
                                }
                            }

                            if let persisted = store.entryState.persistedResume {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Persisted Resume")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("room \(persisted.roomId) • session \(persisted.sessionId)")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.72))
                                    Text(persisted.isAttachReady ? "resumeToken, playerId, and deviceId are ready for authoritative hello resume." : "Resume is still incomplete and stays disabled on the entry surface.")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                        }
                    }

                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Route Notes")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text(store.sourceDescription)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.76))

                            MultiplayerSecondaryButton(
                                title: "Reset Route",
                                subtitle: "Return to the entry shell without bypassing authoritative lifecycle rules.",
                                accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                            ) {
                                store.reset()
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var normalizedInviteCode: String? {
        multiplayerNormalizedInviteCodeValue(inviteCodeInput)
    }

    private func sessionRule(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 0.31, green: 0.74, blue: 0.97))
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
    }

    private func placementCandidateCard(_ candidate: MultiplayerProductPlacementCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MultiplayerGlyphBadge(
                systemName: candidate.symbolName,
                accentColor: candidate.accentColor
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(candidate.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    MultiplayerStatusBadge(
                        title: candidate.badgeTitle,
                        accentColor: candidate.accentColor
                    )
                }

                Text(candidate.summary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))

                Text(candidate.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct MultiplayerShellLabView: View {
    @Environment(\.dismiss) private var dismiss
#if DEBUG
    @StateObject private var localDebugStore: MultiplayerShellStore

    @MainActor
    init() {
        _localDebugStore = StateObject(
            wrappedValue: MultiplayerShellStore(source: MultiplayerLocalDebugShellSource())
        )
    }
#else
    init() {}
#endif

    var body: some View {
        NavigationStack {
            TabView {
                interactiveTab
                    .tabItem {
                        Label("Coordinator", systemImage: "dot.radiowaves.left.and.right")
                    }

                MultiplayerPlayCoordinatorView()
                    .tabItem {
                        Label("Rich UI", systemImage: "gamecontroller.fill")
                    }

                transportTab
                    .tabItem {
                        Label("Transport", systemImage: "network")
                    }

                MultiplayerMappedPayloadDemoView()
                    .tabItem {
                        Label("Mapped", systemImage: "square.stack.3d.forward.dottedline.fill")
                    }
            }
            .navigationTitle("Multiplayer Lab")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var interactiveTab: some View {
#if DEBUG
        MultiplayerShellShowcaseView(store: localDebugStore)
#else
        MultiplayerShellShowcaseView()
#endif
    }

    @ViewBuilder
    private var transportTab: some View {
        MultiplayerTransportRouteHostView(configuration: .lab)
    }
}

struct MultiplayerShellShowcaseView: View {
    @StateObject private var store: MultiplayerShellStore
    private let chrome: MultiplayerShellChrome
    private let showsBackground: Bool

    @MainActor
    init() {
        _store = StateObject(wrappedValue: MultiplayerShellStore())
        self.chrome = .diagnostic
        self.showsBackground = true
    }

    @MainActor
    fileprivate init(
        store: MultiplayerShellStore,
        chrome: MultiplayerShellChrome = .diagnostic,
        showsBackground: Bool = true
    ) {
        _store = StateObject(wrappedValue: store)
        self.chrome = chrome
        self.showsBackground = showsBackground
    }

    var body: some View {
        ZStack {
            if showsBackground {
                MultiplayerShellBackground()
                    .ignoresSafeArea()
            }

            VStack(spacing: 16) {
                if chrome.showsDiagnosticsPanel {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Text(store.sourceLabel)
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                MultiplayerStatusBadge(title: store.route.label, accentColor: routeAccentColor)
                                if let reconnectOverlay = store.reconnectOverlay {
                                    MultiplayerStatusBadge(title: reconnectOverlay.phase.title, accentColor: reconnectOverlay.phase.accentColor)
                                }
                                Spacer(minLength: 0)
                                MultiplayerSecondaryButton(
                                    title: "Reset",
                                    subtitle: "Return to the entry shell.",
                                    accentColor: Color(red: 0.95, green: 0.65, blue: 0.20)
                                ) {
                                    store.reset()
                                }
                                .frame(maxWidth: 220)
                            }

                            Text(store.sourceDescription)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))

                            if !store.statusItems.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(store.statusItems) { item in
                                            MultiplayerStatPill(label: item.label, value: item.value)
                                        }
                                    }
                                }
                            }

                            if store.controls.isEmpty {
                                Text(chrome.emptyControlsMessage(for: store))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.56))
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(store.controls) { control in
                                            mockControlButton(control.title, accentColor: control.accentColor) {
                                                store.performControl(control.action)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ZStack {
                    switch store.route {
                    case .entry:
                        MultiplayerEntryView(
                            state: store.entryState,
                            availableActions: store.entryActions
                        ) { action in
                            store.handleEntryAction(action)
                        }
                    case .room:
                        MultiplayerRoomView(
                            state: store.roomState,
                            onReadyTapped: { store.performControl(.ready) },
                            onLeaveTapped: { store.performControl(.leaveRoom) }
                        )
                    case .live:
                        liveRouteView
                    case .result:
                        MultiplayerResultView(
                            state: store.resultState,
                            showsIntegrationNotes: chrome.showsResultIntegrationNotes,
                            onLeaveTapped: { store.performControl(.leaveRoom) }
                        )
                    }

                    if let reconnectOverlay = store.reconnectOverlay {
                        MultiplayerReconnectOverlay(
                            state: reconnectOverlay,
                            onLeaveTapped: { store.reset() }
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var liveRouteView: some View {
        if chrome == .product, let snapshot = store.authoritativeLiveSnapshot {
            MultiplayerAuthoritativeGameCoordinatorView(
                snapshot: snapshot,
                onActionSent: { action in
                    store.handleGameplayActionFromGameView(action)
                },
                onProductRenderProbeChanged: { probe in
                    store.updateProductRenderProbe(probe)
                },
                onAutomationActionDriverChanged: { sourceID, driver in
                    store.updateProductGameplayActionDriver(driver, sourceID: sourceID)
                }
            )
        } else {
            MultiplayerLiveShellView(
                state: store.liveState,
                onPlayCard: store.isGameplayTransportReady ? { cardId in
                    store.playCardFromLiveUI(cardId)
                } : nil,
                onSubmitChoice: store.isGameplayTransportReady ? { choiceId, optionCode, choiceCommandName in
                    store.submitChoiceFromLiveUI(
                        choiceId,
                        optionCode: optionCode,
                        choiceCommandName: choiceCommandName
                    )
                } : nil,
                onQuitTapped: store.isGameplayTransportReady ? {
                    store.quitMatchFromLiveUI()
                } : nil
            )
        }
    }

    private var routeAccentColor: Color {
        switch store.route {
        case .entry:
            return Color(red: 0.93, green: 0.73, blue: 0.20)
        case .room:
            return Color(red: 0.31, green: 0.74, blue: 0.97)
        case .live:
            return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .result:
            return Color(red: 0.88, green: 0.30, blue: 0.24)
        }
    }

    private func mockControlButton(_ title: String, accentColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(accentColor)
                )
        }
        .buttonStyle(.plain)
    }
}

fileprivate enum MultiplayerShellChrome {
    case diagnostic
    case product

    var showsDiagnosticsPanel: Bool {
        switch self {
        case .diagnostic:
            return true
        case .product:
            return false
        }
    }

    var showsResultIntegrationNotes: Bool {
        switch self {
        case .diagnostic:
            return true
        case .product:
            return false
        }
    }

    @MainActor
    func emptyControlsMessage(for store: MultiplayerShellStore) -> String {
        if store.route == .live && store.isGameplayTransportReady {
            return "Transport diagnostics are idle. Live commands now run from the hand and choice action area below."
        }
        return "No source-specific actions are available for the current route."
    }
}

private struct MultiplayerShellSurface<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                }

                content
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(MultiplayerShellBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct MultiplayerPanelCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MultiplayerShellBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.21, blue: 0.18),
                    Color(red: 0.12, green: 0.29, blue: 0.23),
                    Color(red: 0.07, green: 0.17, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear,
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                ForEach(0..<14, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.02))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct MultiplayerActionCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isBusy: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MultiplayerPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        MultiplayerGlyphBadge(systemName: symbolName, accentColor: accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.70))
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Text(isBusy ? "Attaching..." : "Mock Action")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.82))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(accentColor)
                            )
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.white.opacity(0.76))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MultiplayerPrimaryButton: View {
    let title: String
    let subtitle: String
    let isBusy: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.black.opacity(0.8))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.black.opacity(0.84))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MultiplayerSecondaryButton: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let isEnabled: Bool
    let showsProgress: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        accentColor: Color,
        isEnabled: Bool = true,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accentColor = accentColor
        self.isEnabled = isEnabled
        self.showsProgress = showsProgress
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    if showsProgress {
                        ProgressView()
                            .scaleEffect(0.82)
                            .tint(.white.opacity(0.7))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isEnabled ? .white.opacity(0.92) : .white.opacity(0.46))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(isEnabled ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accentColor.opacity(isEnabled ? 0.65 : 0.28), lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.88)
        .buttonStyle(.plain)
    }
}

private struct MultiplayerStatusBadge: View {
    let title: String
    let accentColor: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(accentColor)
            )
    }
}

private struct MultiplayerStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.94))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }
}

private struct MultiplayerGlyphBadge: View {
    let systemName: String
    let accentColor: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(.black.opacity(0.82))
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor)
            )
    }
}

private struct MultiplayerBannerView: View {
    let state: MultiplayerBannerState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(state.style.accentColor)
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(state.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                if let localizedMessage = localizedShellText(state.messageKey),
                   localizedMessage != state.detail {
                    Text(localizedMessage)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }
}

private struct MultiplayerRoomSeatCard: View {
    let member: MultiplayerRoomMemberShellState
    let hostPlayerId: String

    var body: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("Seat \(member.seat + 1)")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            MultiplayerStatusBadge(title: member.ready ? "Ready" : "Not Ready", accentColor: member.ready ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.95, green: 0.65, blue: 0.20))
                        }

                        Text(shortIdentifier(member.playerId))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.70))
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        MultiplayerStatusBadge(title: member.presence.label, accentColor: member.presence.accentColor)
                        if member.playerId == hostPlayerId {
                            MultiplayerStatusBadge(title: member.role.uppercased(), accentColor: Color(red: 0.93, green: 0.73, blue: 0.20))
                        }
                    }
                }

                if member.isLocalPlayer {
                    Text("Local player shell state")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.93, green: 0.73, blue: 0.20))
                }
            }
        }
    }
}

private struct MultiplayerBoardZoneCard: View {
    let title: String
    let accentColor: Color
    let rows: [(String, String)]

    var body: some View {
        MultiplayerPanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 10) {
                        Text(row.0)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))
                        Spacer(minLength: 0)
                        Text(row.1)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func shortIdentifier(_ identifier: String) -> String {
    guard identifier.count > 14 else { return identifier }
    return "\(identifier.prefix(6))...\(identifier.suffix(4))"
}

private func friendlyShellIdentifier(_ identifier: String) -> String {
    identifier
        .reduce(into: "") { partial, character in
            if character == "." || character == "_" {
                partial.append(" ")
            } else if character.isUppercase {
                if let last = partial.last, last != " " {
                    partial.append(" ")
                }
                partial.append(character.lowercased())
            } else {
                partial.append(character)
            }
        }
        .split(separator: " ")
        .map { token in
            let lowercased = token.lowercased()
            switch lowercased {
            case "id":
                return "ID"
            case "ttl":
                return "TTL"
            default:
                return lowercased.capitalized
            }
        }
        .joined(separator: " ")
}

private func countdownText(to date: Date?, reference: Date) -> String {
    guard let date else { return "n/a" }
    let remainingSeconds = max(0, Int(date.timeIntervalSince(reference)))
    let minutes = remainingSeconds / 60
    let seconds = remainingSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

#Preview("Multiplayer Shell Showcase") {
    MultiplayerShellShowcaseView()
}

#Preview("Multiplayer Entry") {
    MultiplayerEntryView(
        state: MultiplayerShellPreviewShowcaseState.mock.entry,
        availableActions: [.quickMatch, .createInvite, .joinInvite]
    ) { _ in }
}

#Preview("Multiplayer Room") {
    MultiplayerRoomView(
        state: MultiplayerShellPreviewShowcaseState.mock.room,
        onReadyTapped: {},
        onLeaveTapped: {}
    )
}

#Preview("Multiplayer Live With Overlay") {
    ZStack {
        MultiplayerLiveShellView(state: MultiplayerShellPreviewShowcaseState.mock.live)
        MultiplayerReconnectOverlay(
            state: MultiplayerShellPreviewShowcaseState.mock.reconnect,
            onLeaveTapped: {}
        )
    }
}

#Preview("Multiplayer Mapped Payload Demo") {
    MultiplayerMappedPayloadDemoView()
}

#Preview("Multiplayer Result") {
    MultiplayerResultView(state: MultiplayerShellPreviewShowcaseState.mock.result, onLeaveTapped: {})
}
