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
    case ready
    case guestReady
    case disconnect
    case resume
    case heartbeat
    case expireReconnect
    case applyGameStarted
    case applyMatchEnded
    case showResult
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
    private var source: MultiplayerShellSource

    init(
        baseline: MultiplayerShellPreviewShowcaseState = .mock,
        source: MultiplayerShellSource? = nil
    ) {
        let resolvedSource = source ?? MultiplayerMockShellSource(baseline: baseline)
        self.baseline = baseline
        self.route = .entry
        self.entryState = baseline.entry
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

    func handleEntryAction(_ action: MultiplayerEntryAction) {
        source.handleEntryAction(action)
        refreshSourceUI()
    }

    func performControl(_ action: MultiplayerShellControlAction) {
        source.handleControlAction(action)
        refreshSourceUI()
    }

    func reset() {
        source.reset()
        refreshSourceUI()
    }

    func replaceSource(_ newSource: MultiplayerShellSource) {
        source.detach()
        source = newSource
        sourceLabel = newSource.label
        sourceDescription = newSource.descriptionText
        newSource.attach(store: self)
        newSource.reset()
        refreshSourceUI()
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
        entryState = baseline.entry
        roomState = baseline.room
        liveState = baseline.live
        reconnectOverlay = nil
        resultState = baseline.result
        refreshSourceUI()
    }

    fileprivate var previewBaseline: MultiplayerShellPreviewShowcaseState {
        baseline
    }

    fileprivate func refreshSourceUI() {
        sourceLabel = source.label
        sourceDescription = source.descriptionText
        entryActions = source.visibleEntryActions()
        controls = source.visibleControls()
        statusItems = source.statusItems
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

#if DEBUG
@MainActor
final class MultiplayerLocalDebugShellSource: MultiplayerShellSource {
    let label = "Local Debug"
    let descriptionText = "DEBUG coordinator source. Host/guest attach, ready, gameStarted, disconnect, and resume come from LocalRoomCoordinatorDebugService. Live bootstrap and terminal summary both use Agent 1 authoritative helpers."

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
        var requestData: [String: Any] = [
            "roomId": roomId,
            "gameId": gameId,
            "viewerPlayerId": store.liveState.localPlayerId,
            "quitReason": MultiplayerQuitReason.voluntaryExit.rawValue,
            "stateVersion": 1
        ]

        if !store.liveState.turnId.isEmpty {
            requestData["turnId"] = store.liveState.turnId
        }

        guard let terminalSummary = TestControlSupport.multiplayerTerminalSummaryPayload(
            from: liveProjectionGameManager(for: gameId),
            requestData: requestData
        ) else {
            throw localDebugError("Authoritative terminal summary payload is unavailable for the current local debug context.")
        }
        let resultState = MultiplayerShellMapper.resultState(
            roundEnded: terminalSummary.roundEnded,
            matchEnded: terminalSummary.matchEnded,
            localPlayerId: store.liveState.localPlayerId,
            playerNamesById: [
                store.liveState.localPlayerId: "You",
                store.liveState.opponentPlayerId: currentGuestSession == nil ? "Opponent" : "Guest"
            ]
        )

        lastAction = "Apply matchEnded"
        roomState = .ended
        store.showResult(resultState)
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
            inviteCode: nil
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
                    detail: String(describing: error)
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
            detail: String(describing: error)
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
                    currentPlayerId: store.liveState.currentPlayerId,
                    phase: store.liveState.phase,
                    turnId: store.liveState.turnId,
                    turnDeadlineAt: store.liveState.turnDeadlineAt,
                    serverTime: store.liveState.serverTime,
                    opponentPlayerId: store.liveState.opponentPlayerId,
                    opponentHandCount: store.liveState.opponentHandCount,
                    localHandCount: store.liveState.localHandCount,
                    pendingChoice: store.liveState.pendingChoice,
                    lastReject: store.liveState.lastReject,
                    connectionBanner: banner
                ),
                overlay: store.reconnectOverlay
            )
        default:
            store.showEntry(debugEntryState(banner: banner))
        }
    }

    private func debugEntryState(banner: MultiplayerBannerState?) -> MultiplayerEntryShellState {
        MultiplayerEntryShellState(
            pendingAction: nil,
            persistedResume: context.persistedResume(lastKnownGameId: currentSnapshot?.room.activeGameId),
            lastError: banner
        )
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
            currentPlayerId: liveState.currentPlayerId,
            phase: liveState.phase,
            turnId: liveState.turnId,
            turnDeadlineAt: liveState.turnDeadlineAt,
            serverTime: liveState.serverTime,
            opponentPlayerId: liveState.opponentPlayerId,
            opponentHandCount: liveState.opponentHandCount,
            localHandCount: liveState.localHandCount,
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

    func persistedResume(lastKnownGameId: String?) -> MultiplayerPersistedSessionSummary? {
        guard let roomId, let localSessionId, let localResumeToken else { return nil }
        _ = localResumeToken
        return MultiplayerPersistedSessionSummary(
            roomId: roomId,
            sessionId: localSessionId,
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

        return MultiplayerLiveShellState(
            roomId: snapshot.state.roomId ?? "room_pending",
            gameId: snapshot.state.gameId,
            localPlayerId: localPlayer?.playerId ?? "player_local_pending",
            currentPlayerId: snapshot.state.currentPlayerId ?? localPlayer?.playerId ?? "player_turn_pending",
            phase: gamePhase(from: snapshot.state.phase),
            turnId: snapshot.state.turnId,
            turnDeadlineAt: parseDate(snapshot.state.timers.turnDeadlineAt),
            serverTime: parseDate(serverTime) ?? Date.now,
            opponentPlayerId: opponentPlayer?.playerId ?? "player_opponent_pending",
            opponentHandCount: opponentPlayer?.handCount ?? 0,
            localHandCount: localPlayer?.handCount ?? 0,
            pendingChoice: snapshot.state.pendingChoice.map(choiceState),
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
            currentPlayerId: turnChanged.currentPlayerId,
            phase: state.phase == .choicePending ? .choicePending : .inTurn,
            turnId: turnChanged.turnId,
            turnDeadlineAt: parseDate(turnChanged.turnDeadlineAt),
            serverTime: parseDate(serverTime) ?? state.serverTime,
            opponentPlayerId: state.opponentPlayerId,
            opponentHandCount: state.opponentHandCount,
            localHandCount: state.localHandCount,
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
            currentPlayerId: state.currentPlayerId,
            phase: state.phase,
            turnId: state.turnId,
            turnDeadlineAt: state.turnDeadlineAt,
            serverTime: state.serverTime,
            opponentPlayerId: state.opponentPlayerId,
            opponentHandCount: state.opponentHandCount,
            localHandCount: state.localHandCount,
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
            leavePolicy: .pendingRoomClosure,
            integrationNotes: [
                "Result display names still fall back to snapshot player names when room member names are unavailable.",
                "endReasonMessageKey is available, but UI localization wiring still has to land in the message catalog.",
                "Leave completion still needs roomClosed or leave ack before the route can dismiss authoritatively."
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
                    .joined(separator: " • ")
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

    private static func choiceState(from choice: MultiplayerChoice) -> MultiplayerChoiceShellState {
        MultiplayerChoiceShellState(
            choiceId: choice.choiceId,
            choiceKind: choiceKind(from: choice.choiceKind),
            actorPlayerId: choice.actorPlayerId,
            promptKey: choice.promptKey,
            deadlineAt: parseDate(choice.deadlineAt),
            options: choice.options.map { option in
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
                lastKnownGameId: gameId,
                graceExpiresAt: date(after: 24)
            ),
            helloAck: MultiplayerHelloAckShellPayload(
                roomId: roomId,
                resumeMode: .resumed,
                heartbeatIntervalMs: 5000,
                disconnectTimeoutMs: 15000,
                reconnectGraceMs: 30000,
                resultRetentionMs: 60000
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
                inviteCode: "GWANG-32"
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
