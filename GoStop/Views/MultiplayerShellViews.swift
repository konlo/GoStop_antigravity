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
            return "Join a private room with the shared inviteCode."
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
    case disconnectedGrace
    case resuming
    case expired
    case replaced

    var label: String {
        switch self {
        case .connected:
            return "Connected"
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

enum MultiplayerGamePhase: String {
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

enum MultiplayerChoiceKind: String {
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

enum MultiplayerBannerStyle {
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

struct MultiplayerBannerState: Identifiable {
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

struct MultiplayerChoiceOptionShellState: Identifiable {
    let optionCode: String
    let labelKey: String
    let cardIds: [String]
    let scoreDeltaPreviewSelf: Int
    let scoreDeltaPreviewOpponent: Int

    var id: String { optionCode }
}

struct MultiplayerChoiceShellState {
    let choiceId: String
    let choiceKind: MultiplayerChoiceKind
    let actorPlayerId: String
    let promptKey: String
    let deadlineAt: Date?
    let isRedactedForViewer: Bool
    let redactionMessageKey: String?
    let options: [MultiplayerChoiceOptionShellState]
}

struct MultiplayerRejectDetailRow: Identifiable {
    let key: String
    let value: String

    var id: String { "\(key):\(value)" }
}

struct MultiplayerRejectShellState {
    let code: String
    let messageKey: String
    let detailRows: [MultiplayerRejectDetailRow]
}

struct MultiplayerLiveShellState {
    let roomId: String
    let gameId: String
    let localPlayerId: String
    let stateVersion: Int
    let currentPlayerId: String
    let phase: MultiplayerGamePhase
    let turnId: String
    let turnDeadlineAt: Date?
    let serverTime: Date
    let opponentPlayerId: String
    let opponentHandCount: Int
    let localHandCount: Int
    let localPlayableCardIds: [String]
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
                detail: "Phase 0 uses `inviteCode` as the share identifier, and it currently aliases the roomId."
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
            inviteCode: "room_001",
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
            stateVersion: 13,
            currentPlayerId: "player_a",
            phase: .choicePending,
            turnId: "turn_0007",
            turnDeadlineAt: Date.now.addingTimeInterval(14),
            serverTime: Date.now,
            opponentPlayerId: "player_b",
            opponentHandCount: 7,
            localHandCount: 6,
            localPlayableCardIds: ["card_03_ribbon_red_poem", "card_04_junk_a"],
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
                        cardIds: ["card_03_ribbon_red_poem", "card_03_junk_a"],
                        scoreDeltaPreviewSelf: 0,
                        scoreDeltaPreviewOpponent: 0
                    ),
                    MultiplayerChoiceOptionShellState(
                        optionCode: "capture_pair_right",
                        labelKey: "match.choice.capture.take_pair",
                        cardIds: ["card_03_ribbon_red_poem", "card_03_junk_b"],
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
                "The main app currently mounts multiplayer as a root sheet. Deeper tab or menu placement is still follow-up work.",
                "Gameplay transport is wired for playCard, submitChoice, and quit, but the live action area still renders cardId chips instead of final card art."
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
        localMember?.presence == .connected
    }

    private var localReadyTitle: String {
        (localMember?.ready ?? false) ? "Unready" : "Ready"
    }

    private var localReadySubtitle: String {
        if !canToggleReady {
            return "Reconnect first. Room snapshot still owns the ready truth."
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
                    Text("Invite code is not on this snapshot yet. Product invite join now expects `room.inviteCode`, and Phase 0 treats it as the roomId alias.")
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
        MultiplayerShellSurface(title: "Live Match", subtitle: "The board stays projection-only, but transport-backed play, choice, and quit actions now run from this screen.") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    MultiplayerStatusBadge(
                        title: state.phase.label,
                        accentColor: state.currentPlayerId == state.localPlayerId ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.95, green: 0.65, blue: 0.20)
                    )
                    MultiplayerStatPill(label: "Turn", value: shortIdentifier(state.turnId))
                    MultiplayerStatPill(label: "Timer", value: countdownText(to: state.turnDeadlineAt, reference: state.serverTime))
                    MultiplayerStatPill(label: "State", value: "\(state.stateVersion)")
                    Spacer(minLength: 0)
                    MultiplayerStatPill(label: "Game", value: shortIdentifier(state.gameId))
                }

                if let connectionBanner = state.connectionBanner {
                    MultiplayerBannerView(state: connectionBanner)
                }

                HStack(spacing: 16) {
                    MultiplayerBoardZoneCard(
                        title: "Opponent Projection",
                        accentColor: Color(red: 0.25, green: 0.77, blue: 0.98),
                        rows: [
                            ("Player", shortIdentifier(state.opponentPlayerId)),
                            ("Hand Count", "\(state.opponentHandCount)"),
                            ("Turn Owner", state.currentPlayerId == state.opponentPlayerId ? "Yes" : "No")
                        ]
                    )

                    MultiplayerBoardZoneCard(
                        title: "Table Projection",
                        accentColor: Color(red: 0.93, green: 0.73, blue: 0.20),
                        rows: [
                            ("Room", shortIdentifier(state.roomId)),
                            ("Phase", state.phase.label),
                            ("Input", inputModeLabel),
                            ("Actor", state.currentPlayerId == state.localPlayerId ? "You" : "Opponent")
                        ]
                    )

                    MultiplayerBoardZoneCard(
                        title: "My Projection",
                        accentColor: Color(red: 0.32, green: 0.82, blue: 0.52),
                        rows: [
                            ("Player", shortIdentifier(state.localPlayerId)),
                            ("Hand Count", "\(state.localHandCount)"),
                            ("Turn Owner", state.currentPlayerId == state.localPlayerId ? "Yes" : "No")
                        ]
                    )
                }

                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            MultiplayerGlyphBadge(
                                systemName: "hand.tap.fill",
                                accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text("My Hand")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(handActionSubtitle)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                            }

                            Spacer(minLength: 0)

                            MultiplayerStatusBadge(
                                title: canPlayHandCard ? "Playable" : "Locked",
                                accentColor: canPlayHandCard ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.49, green: 0.53, blue: 0.58)
                            )
                        }

                        if state.localPlayableCardIds.isEmpty {
                            Text("No authoritative hand card ids are available for local play yet.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.60))
                        } else {
                            LazyVGrid(columns: handColumns, alignment: .leading, spacing: 10) {
                                ForEach(state.localPlayableCardIds, id: \.self) { cardId in
                                    handCardButton(cardId)
                                }
                            }
                        }

                        MultiplayerPrimaryButton(
                            title: selectedCardId == nil ? "Select A Card" : "Play Selected Card",
                            subtitle: selectedCardId.map { "Send \($0) through the authoritative playCard transport command." } ?? handActionSubtitle,
                            isBusy: false,
                            accentColor: Color(red: 0.32, green: 0.82, blue: 0.52)
                        ) {
                            guard let selectedCardId else { return }
                            onPlayCard?(selectedCardId)
                        }
                        .disabled(selectedCardId == nil || !canPlayHandCard)
                    }
                }

                if let pendingChoice = state.pendingChoice {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Text(pendingChoice.choiceKind.label)
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                MultiplayerStatusBadge(
                                    title: pendingChoice.actorPlayerId == state.localPlayerId ? "Local Choice" : "Remote Choice",
                                    accentColor: pendingChoice.actorPlayerId == state.localPlayerId ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color(red: 0.95, green: 0.65, blue: 0.20)
                                )
                            }

                            Text(localizedShellText(pendingChoice.promptKey, fallback: choicePromptFallback(for: pendingChoice)))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))

                            Text("choiceId \(pendingChoice.choiceId) expires \(countdownText(to: pendingChoice.deadlineAt, reference: state.serverTime))")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))

                            VStack(spacing: 10) {
                                if pendingChoice.isRedactedForViewer {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(
                                                localizedShellText(
                                                    pendingChoice.redactionMessageKey ?? "",
                                                    fallback: "Opponent is deciding whether to shake."
                                                )
                                            )
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.8))
                                            if let localizedRedaction = localizedShellText(pendingChoice.redactionMessageKey) {
                                                Text(localizedRedaction)
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(.white.opacity(0.56))
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                } else {
                                    ForEach(pendingChoice.options) { option in
                                        choiceOptionCard(pendingChoice: pendingChoice, option: option)
                                    }
                                }
                            }
                        }
                    }
                }

                MultiplayerPanelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            MultiplayerGlyphBadge(
                                systemName: "flag.slash.fill",
                                accentColor: Color(red: 0.88, green: 0.30, blue: 0.24)
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quit Match")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("This sends the authoritative multiplayer quit command. The route still waits for matchEnded and room lifecycle completion.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        MultiplayerSecondaryButton(
                            title: "Send Quit Command",
                            subtitle: canQuitMatch
                                ? "Quit the live match over the same transport path used for playCard and submitChoice."
                                : "Quit is locked until the authoritative live transport is ready again.",
                            accentColor: Color(red: 0.88, green: 0.30, blue: 0.24),
                            isEnabled: canQuitMatch,
                            action: { onQuitTapped?() }
                        )
                    }
                }

                if let lastReject = state.lastReject {
                    MultiplayerPanelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last Reject: \(lastReject.code)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.99, green: 0.62, blue: 0.28))
                            Text(localizedShellText(lastReject.messageKey, fallback: lastReject.messageKey))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))

                            ForEach(lastReject.detailRows) { row in
                                HStack(spacing: 10) {
                                    Text(row.key)
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
    }

    private var handColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading)]
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

    private var canPlayHandCard: Bool {
        onPlayCard != nil &&
        state.currentPlayerId == state.localPlayerId &&
        !state.localPlayableCardIds.isEmpty &&
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
        if canPlayHandCard {
            return "Tap a card id below, then send it through the transport-backed playCard command."
        }
        if state.currentPlayerId != state.localPlayerId {
            return "Hand play is locked because the authoritative turn owner is the opponent."
        }
        return "Hand play is waiting for authoritative card ids or reconnect recovery."
    }

    private func handCardButton(_ cardId: String) -> some View {
        Button {
            selectedCardId = selectedCardId == cardId ? nil : cardId
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(cardDisplayTitle(cardId))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(cardId)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedCardId == cardId ? Color(red: 0.32, green: 0.82, blue: 0.52).opacity(0.24) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedCardId == cardId ? Color(red: 0.32, green: 0.82, blue: 0.52) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .disabled(!canPlayHandCard)
        .buttonStyle(.plain)
        .opacity(canPlayHandCard ? 1 : 0.72)
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
                    if !option.cardIds.isEmpty {
                        Text(option.cardIds.joined(separator: "\n"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Preview \(option.scoreDeltaPreviewSelf)/\(option.scoreDeltaPreviewOpponent)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.93, green: 0.73, blue: 0.20))
                }
            }

            MultiplayerSecondaryButton(
                title: "Submit Option",
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
            return
        }
        guard let selectedCardId else {
            self.selectedCardId = state.localPlayableCardIds.first
            return
        }
        if !state.localPlayableCardIds.contains(selectedCardId) {
            self.selectedCardId = state.localPlayableCardIds.first
        }
    }

    private func cardDisplayTitle(_ cardId: String) -> String {
        let fragments = cardId
            .split(separator: "_")
            .dropFirst()
            .prefix(3)
            .map { $0.capitalized }
        return fragments.isEmpty ? "Hand Card" : fragments.joined(separator: " ")
    }

    private func choicePromptFallback(for pendingChoice: MultiplayerChoiceShellState) -> String {
        switch pendingChoice.choiceKind {
        case .capture:
            return "Choose which capture line to resolve."
        case .shake:
            return "Decide whether to shake before continuing."
        case .goStop:
            return "Choose whether to continue with Go or end with Stop."
        case .chrysanthemumRole:
            return "Choose how to score the chrysanthemum card."
        }
    }

    private func optionFallback(for option: MultiplayerChoiceOptionShellState) -> String {
        option.optionCode
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
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
                            MultiplayerStatPill(label: "Reason", value: state.endReasonCode)
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
        _inviteCodeInput = State(initialValue: configuration.mode.pendingInviteCode ?? "")
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

                                    Text("Create Room, Join Invite, and Resume all stay on authoritative helloAck -> roomSnapshot attach. Phase 0 uses `inviteCode`, and the current server keeps `inviteCode == roomId`.")
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
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)
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
                                MultiplayerStatPill(label: "Phase 0", value: "inviteCode == roomId")
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
        let trimmed = inviteCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MultiplayerProductMultiplayerRouteView: View {
    @Environment(\.dismiss) private var dismiss
    let initialInviteCode: String?

    init(initialInviteCode: String? = nil) {
        self.initialInviteCode = initialInviteCode
    }

    var body: some View {
        NavigationStack {
            MultiplayerTransportRouteHostView(
                configuration: .productPreparation(inviteCode: initialInviteCode)
            )
            .navigationTitle("Multiplayer")
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

    @MainActor
    init() {
        _store = StateObject(wrappedValue: MultiplayerShellStore())
    }

    @MainActor
    init(store: MultiplayerShellStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack {
            MultiplayerShellBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
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
                            Text(
                                store.route == .live && store.isGameplayTransportReady
                                ? "Transport diagnostics are idle. Live commands now run from the hand and choice action area below."
                                : "No source-specific actions are available for the current route."
                            )
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
                    case .result:
                        MultiplayerResultView(
                            state: store.resultState,
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
