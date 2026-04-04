import SwiftUI

/// Coordinator that bridges authoritative Multiplayer network state into the local GameView rendering engine.
@MainActor
class MultiplayerPlayCoordinatorViewModel: ObservableObject {
    @Published var gameManager: GameManager
    
    private static let localActionDeferralLeadTime: TimeInterval = 0.75
    private static let remoteAcceptedGraceWindow: TimeInterval = 0.6
    private let stateMapper: MultiplayerStateMapper
    private var hasBoundAuthoritativeSnapshot = false
    private var lastAppliedStateVersion: Int?
    private var authoritativeStateVersion: Int?
    private var deferredAuthoritativeSnapshot: MultiplayerSnapshot?
    private var deferredSnapshotDrainTask: Task<Void, Never>?
    private var localActionDeferralDeadline: Date?
    private var pendingAuthoritativeReplayQueue: [MultiplayerShellAcceptedActionEvent] = []
    private var processedAcceptedActionIDs: Set<String> = []
    private var recentLocalActionIDs: Set<String> = []
    private var inFlightAcceptedActionId: String?
    private var replayCompletionTask: Task<Void, Never>?
    private var forceNextSnapshotReset = false
    private var remoteAcceptedGraceStateVersion: Int?
    private var remoteAcceptedGraceDeadline: Date?
    @Published var showEmojiPicker: Bool = false
    @Published var showScoreboardSheet: Bool = false
    
    init(
        gameManager: GameManager = GameManager(),
        stateMapper: MultiplayerStateMapper = DefaultMultiplayerStateMapper(),
        initialSnapshot: MultiplayerSnapshot? = nil
    ) {
        self.gameManager = gameManager
        self.stateMapper = stateMapper
        
        // Ensure localPlayerId is set if we have players
        if let firstPlayer = gameManager.players.first {
            gameManager.localPlayerId = firstPlayer.id.uuidString
        }
        
        // Hook for local actions
        gameManager.onLocalAction = { [weak self] action in
            self?.noteLocalActionDispatch()
            self?.sendAction(action)
        }

        if let initialSnapshot {
            bindSnapshot(initialSnapshot)
        }
    }

    func applyAuthoritativeSnapshot(_ snapshot: MultiplayerSnapshot) {
        if let trackedStateVersion = authoritativeStateVersion ?? lastAppliedStateVersion,
           snapshot.state.stateVersion < trackedStateVersion {
            debugLog(
                "coordinator.snapshot.drop_stale",
                fields: [
                    "targetStateVersion": String(snapshot.state.stateVersion),
                    "trackedStateVersion": String(trackedStateVersion),
                    "reason": snapshot.reason.rawValue
                ]
            )
            return
        }
        if shouldDeferAuthoritativeSnapshot(snapshot) {
            deferredAuthoritativeSnapshot = snapshot
            debugLog(
                "coordinator.snapshot.defer",
                fields: [
                    "targetStateVersion": String(snapshot.state.stateVersion),
                    "reason": snapshot.reason.rawValue,
                    "busy": boolString(gameManager.isAutomationBusy),
                    "localDeferral": boolString(isWithinLocalActionDeferralWindow),
                    "awaitingReplay": boolString(isAwaitingAuthoritativeReplayIdle),
                    "graceActive": boolString(isWithinRemoteAcceptedGraceWindow(for: snapshot))
                ]
            )
            scheduleDeferredSnapshotDrain()
            return
        }
        clearDeferredAuthoritativeSnapshot()
        bindSnapshot(snapshot)
        maybeStartNextAuthoritativeReplay()
    }
    
    func bindSnapshot(_ snapshot: MultiplayerSnapshot) {
        do {
            clearRemoteAcceptedGrace(ifMatching: snapshot.state.stateVersion)
            seedLocalGameManagerIfNeeded(from: snapshot)
            let mappedState = try stateMapper.mapSnapshot(snapshot, currentPlayers: gameManager.players)
            if let resolvedLocalPlayerId = resolvedLocalPlayerId(from: snapshot, mappedPlayers: mappedState.players) {
                gameManager.localPlayerId = resolvedLocalPlayerId
            }
            let mode = applicationMode(for: snapshot)
            if mode == .resetAndReplace {
                forceNextSnapshotReset = false
            }
            gameManager.applyMappedState(mappedState, mode: mode)
            hasBoundAuthoritativeSnapshot = true
            lastAppliedStateVersion = mappedState.stateVersion
            authoritativeStateVersion = mappedState.stateVersion
        } catch {
            print("Failed to map multiplayer snapshot: \(error)")
        }
    }

    private func applicationMode(for snapshot: MultiplayerSnapshot) -> MultiplayerMappedStateApplicationMode {
        if forceNextSnapshotReset {
            return .resetAndReplace
        }
        guard hasBoundAuthoritativeSnapshot else {
            return .resetAndReplace
        }

        switch snapshot.reason {
        case .resume, .resync, .gapDetected:
            return .resetAndReplace
        case .gameStarted:
            break
        case .localPreview:
            break
        }

        if let lastAppliedStateVersion,
           snapshot.state.stateVersion < lastAppliedStateVersion {
            return .resetAndReplace
        }

        return .animatedInPlace
    }

    private func shouldDeferAuthoritativeSnapshot(_ snapshot: MultiplayerSnapshot) -> Bool {
        guard applicationMode(for: snapshot) == .animatedInPlace else {
            clearRemoteAcceptedGrace(ifMatching: snapshot.state.stateVersion)
            return false
        }
        if isAwaitingAuthoritativeReplayIdle || gameManager.isAutomationBusy || isWithinLocalActionDeferralWindow {
            return true
        }

        return shouldAwaitRemoteAcceptedAction(for: snapshot)
    }

    private func scheduleDeferredSnapshotDrain() {
        guard deferredSnapshotDrainTask == nil else { return }
        deferredSnapshotDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.deferredSnapshotDrainTask = nil }

            while !Task.isCancelled {
                if !self.gameManager.isAutomationBusy && !self.isWithinLocalActionDeferralWindow {
                    self.maybeStartNextAuthoritativeReplay()
                }

                let pendingSnapshot = self.deferredAuthoritativeSnapshot
                if pendingSnapshot == nil && !self.isAwaitingAuthoritativeReplayIdle {
                    return
                }

                if let pendingSnapshot,
                    !self.isAwaitingAuthoritativeReplayIdle &&
                    !self.gameManager.isAutomationBusy &&
                    !self.isWithinLocalActionDeferralWindow &&
                    !self.isWithinRemoteAcceptedGraceWindow(for: pendingSnapshot) {
                    self.deferredAuthoritativeSnapshot = nil
                    self.bindSnapshot(pendingSnapshot)
                    self.maybeStartNextAuthoritativeReplay()
                    continue
                }

                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }
    }

    private func clearDeferredAuthoritativeSnapshot() {
        deferredAuthoritativeSnapshot = nil
        deferredSnapshotDrainTask?.cancel()
        deferredSnapshotDrainTask = nil
    }

    private var isWithinLocalActionDeferralWindow: Bool {
        guard let localActionDeferralDeadline else { return false }
        return localActionDeferralDeadline.timeIntervalSinceNow > 0
    }

    private var isAwaitingAuthoritativeReplayIdle: Bool {
        inFlightAcceptedActionId != nil || !pendingAuthoritativeReplayQueue.isEmpty
    }

    private func shouldAwaitRemoteAcceptedAction(for snapshot: MultiplayerSnapshot) -> Bool {
        guard !forceNextSnapshotReset else {
            clearRemoteAcceptedGrace(ifMatching: snapshot.state.stateVersion)
            return false
        }

        guard let currentStateVersion = authoritativeStateVersion ?? lastAppliedStateVersion else {
            return false
        }

        let targetStateVersion = snapshot.state.stateVersion
        guard targetStateVersion == currentStateVersion + 1 else {
            clearRemoteAcceptedGrace(ifMatching: targetStateVersion)
            return false
        }

        if remoteAcceptedGraceStateVersion != targetStateVersion {
            remoteAcceptedGraceStateVersion = targetStateVersion
            remoteAcceptedGraceDeadline = Date().addingTimeInterval(Self.remoteAcceptedGraceWindow)
            return true
        }

        if let deadline = remoteAcceptedGraceDeadline, deadline.timeIntervalSinceNow > 0 {
            return true
        }

        clearRemoteAcceptedGrace(ifMatching: targetStateVersion)
        return false
    }

    private func isWithinRemoteAcceptedGraceWindow(for snapshot: MultiplayerSnapshot) -> Bool {
        guard remoteAcceptedGraceStateVersion == snapshot.state.stateVersion,
              let deadline = remoteAcceptedGraceDeadline else {
            return false
        }
        return deadline.timeIntervalSinceNow > 0
    }

    private func clearRemoteAcceptedGrace(ifMatching stateVersion: Int? = nil) {
        guard let trackedStateVersion = remoteAcceptedGraceStateVersion else { return }
        if let stateVersion, trackedStateVersion != stateVersion {
            return
        }
        remoteAcceptedGraceStateVersion = nil
        remoteAcceptedGraceDeadline = nil
    }

    private func noteLocalActionDispatch() {
        localActionDeferralDeadline = Date().addingTimeInterval(Self.localActionDeferralLeadTime)
    }

    private func seedLocalGameManagerIfNeeded(from snapshot: MultiplayerSnapshot) {
        guard !hasBoundAuthoritativeSnapshot,
              let rngSeed = snapshot.state.rngSeed else {
            return
        }
        guard gameManager.currentSetupSeed != rngSeed else { return }
        gameManager.setupGame(seed: rngSeed)
    }

    private func resolvedLocalPlayerId(from snapshot: MultiplayerSnapshot, mappedPlayers: [Player]) -> String? {
        if let viewerProjection = snapshot.state.players.first(where: \.isViewer),
           let mappedViewer = mappedPlayers.first(where: { $0.seatIndex == viewerProjection.seatIndex }) {
            return mappedViewer.id.uuidString
        }

        if let viewerPlayerId = snapshot.state.viewerPlayerId,
           let viewerProjection = snapshot.state.players.first(where: { $0.playerId == viewerPlayerId }),
           let mappedViewer = mappedPlayers.first(where: { $0.seatIndex == viewerProjection.seatIndex }) {
            return mappedViewer.id.uuidString
        }

        return gameManager.localPlayerId ?? mappedPlayers.first?.id.uuidString
    }

    func noteRecentLocalActionIDs(_ actionIDs: [String]) {
        recentLocalActionIDs.formUnion(actionIDs)
    }

    func ingestAcceptedActions(_ events: [MultiplayerShellAcceptedActionEvent]) {
        for event in events {
            guard processedAcceptedActionIDs.insert(event.payload.actionId).inserted else { continue }
            handleAcceptedActionEvent(event)
        }
        maybeStartNextAuthoritativeReplay()
    }

    private func handleAcceptedActionEvent(_ event: MultiplayerShellAcceptedActionEvent) {
        let accepted = event.payload
        clearRemoteAcceptedGrace(ifMatching: accepted.postStateVersion)
        let currentStateVersion = authoritativeStateVersion ?? lastAppliedStateVersion
        let isRecentLocal = recentLocalActionIDs.contains(accepted.actionId)
        debugLog(
            "coordinator.accepted.received",
            fields: [
                "actionId": accepted.actionId,
                "actorPlayerId": accepted.playerId,
                "localPlayerId": gameManager.localPlayerId,
                "commandName": accepted.commandName.rawValue,
                "preStateVersion": String(accepted.preStateVersion),
                "postStateVersion": String(accepted.postStateVersion),
                "currentStateVersion": currentStateVersion.map(String.init),
                "hasReplay": boolString(accepted.replay != nil),
                "recentLocalMatch": boolString(isRecentLocal)
            ]
        )
        if recentLocalActionIDs.contains(accepted.actionId) {
            authoritativeStateVersion = accepted.postStateVersion
            scheduleDeferredSnapshotDrain()
            debugLog(
                "coordinator.accepted.consume_local_ack",
                fields: [
                    "actionId": accepted.actionId,
                    "postStateVersion": String(accepted.postStateVersion)
                ]
            )
            return
        }

        pendingAuthoritativeReplayQueue.append(event)
        syncReplayProbeState()
        debugLog(
            "coordinator.accepted.enqueue",
            fields: [
                "actionId": accepted.actionId,
                "queueDepth": String(pendingAuthoritativeReplayQueue.count)
            ]
        )
    }

    private func maybeStartNextAuthoritativeReplay() {
        guard inFlightAcceptedActionId == nil else { return }
        guard !gameManager.isAutomationBusy, !isWithinLocalActionDeferralWindow else {
            if let pendingReplay = pendingAuthoritativeReplayQueue.first?.payload {
                debugLog(
                    "coordinator.replay.blocked",
                    fields: [
                        "actionId": pendingReplay.actionId,
                        "busy": boolString(gameManager.isAutomationBusy),
                        "localDeferral": boolString(isWithinLocalActionDeferralWindow),
                        "queueDepth": String(pendingAuthoritativeReplayQueue.count)
                    ]
                )
            }
            scheduleDeferredSnapshotDrain()
            return
        }
        guard let nextEvent = pendingAuthoritativeReplayQueue.first else {
            syncReplayProbeState()
            return
        }

        let accepted = nextEvent.payload
        guard let currentStateVersion = authoritativeStateVersion ?? lastAppliedStateVersion else {
            debugLog(
                "coordinator.replay.wait_state",
                fields: [
                    "actionId": accepted.actionId,
                    "preStateVersion": String(accepted.preStateVersion)
                ]
            )
            scheduleDeferredSnapshotDrain()
            return
        }

        if accepted.preStateVersion != currentStateVersion {
            pendingAuthoritativeReplayQueue.removeAll()
            inFlightAcceptedActionId = nil
            forceNextSnapshotReset = true
            clearRemoteAcceptedGrace()
            syncReplayProbeState()
            debugLog(
                "coordinator.replay.mismatch",
                fields: [
                    "actionId": accepted.actionId,
                    "preStateVersion": String(accepted.preStateVersion),
                    "currentStateVersion": String(currentStateVersion),
                    "queueDepth": String(pendingAuthoritativeReplayQueue.count)
                ]
            )
            scheduleDeferredSnapshotDrain()
            return
        }

        pendingAuthoritativeReplayQueue.removeFirst()
        authoritativeStateVersion = accepted.postStateVersion

        guard let replay = accepted.replay else {
            syncReplayProbeState()
            debugLog(
                "coordinator.replay.missing_payload",
                fields: [
                    "actionId": accepted.actionId,
                    "commandName": accepted.commandName.rawValue
                ]
            )
            scheduleDeferredSnapshotDrain()
            maybeStartNextAuthoritativeReplay()
            return
        }

        guard replay.actorPlayerId != gameManager.localPlayerId else {
            syncReplayProbeState()
            debugLog(
                "coordinator.replay.skip_local_actor",
                fields: [
                    "actionId": accepted.actionId,
                    "actorPlayerId": replay.actorPlayerId,
                    "localPlayerId": gameManager.localPlayerId
                ]
            )
            scheduleDeferredSnapshotDrain()
            maybeStartNextAuthoritativeReplay()
            return
        }

        inFlightAcceptedActionId = accepted.actionId
        syncReplayProbeState()
        debugLog(
            "coordinator.replay.start",
            fields: [
                "actionId": accepted.actionId,
                "actorPlayerId": replay.actorPlayerId,
                "localPlayerId": gameManager.localPlayerId,
                "preStateVersion": String(accepted.preStateVersion),
                "postStateVersion": String(accepted.postStateVersion),
                "queueDepth": String(pendingAuthoritativeReplayQueue.count)
            ]
        )
        guard gameManager.replayAuthoritativeAcceptedAction(replay) else {
            inFlightAcceptedActionId = nil
            forceNextSnapshotReset = true
            syncReplayProbeState()
            debugLog(
                "coordinator.replay.start_failed",
                fields: [
                    "actionId": accepted.actionId,
                    "actorPlayerId": replay.actorPlayerId
                ]
            )
            scheduleDeferredSnapshotDrain()
            return
        }

        replayCompletionTask?.cancel()
        replayCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.replayCompletionTask = nil }

            while !Task.isCancelled && self.gameManager.isAutomationBusy {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard !Task.isCancelled else { return }

            self.inFlightAcceptedActionId = nil
            self.syncReplayProbeState()
            self.debugLog(
                "coordinator.replay.complete",
                fields: [
                    "actionId": accepted.actionId,
                    "pendingSnapshotStateVersion": self.deferredAuthoritativeSnapshot.map {
                        String($0.state.stateVersion)
                    },
                    "queueDepth": String(self.pendingAuthoritativeReplayQueue.count)
                ]
            )
            if !self.gameManager.isAutomationBusy,
               let pendingSnapshot = self.deferredAuthoritativeSnapshot {
                self.deferredAuthoritativeSnapshot = nil
                self.bindSnapshot(pendingSnapshot)
            }
            self.maybeStartNextAuthoritativeReplay()
            self.scheduleDeferredSnapshotDrain()
        }
    }

    private func syncReplayProbeState() {
        gameManager.updateMultiplayerReplayStatus(
            queueDepth: pendingAuthoritativeReplayQueue.count,
            inFlightAcceptedActionId: inFlightAcceptedActionId
        )
    }

    private func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func debugLog(_ event: String, fields: [String: String?] = [:]) {
        var merged = fields
        merged["localPlayerId"] = merged["localPlayerId"] ?? gameManager.localPlayerId
        merged["authoritativeStateVersion"] = merged["authoritativeStateVersion"] ?? (authoritativeStateVersion.map(String.init))
        merged["lastAppliedStateVersion"] = merged["lastAppliedStateVersion"] ?? (lastAppliedStateVersion.map(String.init))
        MultiplayerShellDebugLog.append(event: event, fields: merged)
    }
    
    // Mocks receiving a network payload    
    /// Hook for debugging or bridge integration to see what actions are being sent.
    var onActionSent: ((MultiplayerAction) -> Void)?
    
    /// Sends a local player action to the authoritative server/bridge.
    func sendAction(_ action: MultiplayerAction) {
        gLog("[Multiplayer] Sending action: \(action)")
        onActionSent?(action)
        // In a real implementation, this would encode to JSON and send via NWConnection or WebSocket.
    }

    func performAutomationAction(_ action: MultiplayerAction) {
        switch action {
        case .playCard(let cardId):
            let localPlayer =
                gameManager.players.first(where: { $0.id.uuidString == gameManager.localPlayerId })
                ?? gameManager.players.first
            let localCard = localPlayer?.hand.first(where: { $0.id == cardId })
            let anyPlayerCard = gameManager.players.lazy
                .flatMap(\.hand)
                .first(where: { $0.id == cardId })
            guard let card = localCard ?? anyPlayerCard else {
                gLog("[MultiplayerAutomation] playCard fallback: missing cardId=\(cardId)")
                sendAction(action)
                return
            }
            gLog("[MultiplayerAutomation] playCard local driver: cardId=\(card.id)")
            gameManager.playTurn(card: card)
        case .respondToCapture(let cardId):
            guard let selectedCard = gameManager.pendingCaptureOptions.first(where: { $0.id == cardId }) else {
                gLog("[MultiplayerAutomation] capture fallback: missing cardId=\(cardId)")
                sendAction(action)
                return
            }
            gLog("[MultiplayerAutomation] capture local driver: cardId=\(selectedCard.id)")
            gameManager.respondToCapture(selectedCard: selectedCard)
        case .respondToGoStop(let isGo):
            gLog("[MultiplayerAutomation] goStop local driver: isGo=\(isGo)")
            gameManager.respondToGoStop(isGo: isGo)
        case .respondToShake(let month, let didShake):
            gLog("[MultiplayerAutomation] shake local driver: month=\(month) didShake=\(didShake)")
            gameManager.respondToShake(month: month, didShake: didShake)
        case .respondToChrysanthemumChoice(let role):
            guard let resolvedRole = CardRole(rawValue: role) else {
                gLog("[MultiplayerAutomation] chrys fallback: role=\(role)")
                sendAction(action)
                return
            }
            gLog("[MultiplayerAutomation] chrys local driver: role=\(resolvedRole.rawValue)")
            gameManager.respondToChrysanthemumChoice(role: resolvedRole)
        case .chat(let emojiId):
            gameManager.sendChat(emojiId: emojiId)
        }
    }
    
    func mockReceiveSnapshot(_ snapshot: MultiplayerSnapshot) {
        bindSnapshot(snapshot)
    }
}

struct MultiplayerAuthoritativeGameCoordinatorView: View {
    let snapshot: MultiplayerSnapshot
    let acceptedActions: [MultiplayerShellAcceptedActionEvent]
    let recentLocalActionIDs: [String]
    let onActionSent: (MultiplayerAction) -> Void
    let onProductRenderProbeChanged: ((MultiplayerProductRenderProbe) -> Void)?
    let onAutomationActionDriverChanged: ((UUID, ((MultiplayerAction) -> Void)?) -> Void)?

    @StateObject private var viewModel: MultiplayerPlayCoordinatorViewModel
    @State private var automationActionDriverID = UUID()
    @State private var lastSyncedSnapshotIdentity: String?

    init(
        snapshot: MultiplayerSnapshot,
        acceptedActions: [MultiplayerShellAcceptedActionEvent] = [],
        recentLocalActionIDs: [String] = [],
        onActionSent: @escaping (MultiplayerAction) -> Void,
        onProductRenderProbeChanged: ((MultiplayerProductRenderProbe) -> Void)? = nil,
        onAutomationActionDriverChanged: ((UUID, ((MultiplayerAction) -> Void)?) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.acceptedActions = acceptedActions
        self.recentLocalActionIDs = recentLocalActionIDs
        self.onActionSent = onActionSent
        self.onProductRenderProbeChanged = onProductRenderProbeChanged
        self.onAutomationActionDriverChanged = onAutomationActionDriverChanged
        let viewModel = MultiplayerPlayCoordinatorViewModel()
        viewModel.onActionSent = onActionSent
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var snapshotIdentity: String {
        "\(snapshot.snapshotId):\(snapshot.state.stateVersion)"
    }

    private var acceptedActionIdentity: String {
        acceptedActions.last.map { "\($0.payload.actionId):\($0.payload.postStateVersion)" } ?? "accepted:none"
    }

    private var localActionIdentity: String {
        recentLocalActionIDs.last ?? "local:none"
    }

    private var syncIdentity: String {
        "\(snapshotIdentity)|\(acceptedActionIdentity)|\(localActionIdentity)"
    }

    @MainActor
    private func syncCoordinatorInputs(
        applySnapshot: Bool,
        snapshot: MultiplayerSnapshot,
        acceptedActions: [MultiplayerShellAcceptedActionEvent],
        recentLocalActionIDs: [String],
        onActionSent: @escaping (MultiplayerAction) -> Void
    ) {
        MultiplayerShellDebugLog.append(
            event: "authoritativeView.syncInputs",
            fields: [
                "applySnapshot": applySnapshot ? "true" : "false",
                "snapshotStateVersion": String(snapshot.state.stateVersion),
                "acceptedCount": String(acceptedActions.count),
                "acceptedLastActionId": acceptedActions.last?.payload.actionId,
                "localActionCount": String(recentLocalActionIDs.count),
                "localLastActionId": recentLocalActionIDs.last
            ]
        )
        viewModel.onActionSent = onActionSent
        viewModel.noteRecentLocalActionIDs(recentLocalActionIDs)
        viewModel.ingestAcceptedActions(acceptedActions)
        if applySnapshot {
            viewModel.applyAuthoritativeSnapshot(snapshot)
        }
    }

    var body: some View {
        GameView(
            gameManager: viewModel.gameManager,
            onProductRenderProbeChanged: onProductRenderProbeChanged
        )
            .onAppear {
                onAutomationActionDriverChanged?(automationActionDriverID) { action in
                    viewModel.performAutomationAction(action)
                }
            }
            .task(id: syncIdentity) {
                await MainActor.run {
                    let shouldApplySnapshot = lastSyncedSnapshotIdentity != snapshotIdentity
                    syncCoordinatorInputs(
                        applySnapshot: shouldApplySnapshot,
                        snapshot: snapshot,
                        acceptedActions: acceptedActions,
                        recentLocalActionIDs: recentLocalActionIDs,
                        onActionSent: onActionSent
                    )
                    lastSyncedSnapshotIdentity = snapshotIdentity
                }
            }
            .onDisappear {
                onAutomationActionDriverChanged?(automationActionDriverID, nil)
            }
    }
}

struct MultiplayerPlayCoordinatorView: View {
    @StateObject private var viewModel: MultiplayerPlayCoordinatorViewModel
    
    @MainActor
    init(viewModel: MultiplayerPlayCoordinatorViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MultiplayerPlayCoordinatorViewModel())
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Wrap the standard GameView, injecting our hijacked GameManager
            GameView(gameManager: viewModel.gameManager)
            
            VStack(spacing: 12) {
                // Debug Trigger for Round 2 verification
                Button {
                    let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                    let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                    viewModel.gameManager.localPlayerId = localId
                    let mock = MockMultiplayerPayloads.generateInitialDealSnapshot(localPlayerId: localId, opponentId: opponentId)
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject My Turn Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                // Debug Trigger for Round 3 verification
                Button {
                    let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                    let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                    viewModel.gameManager.localPlayerId = localId
                    let mock = MockMultiplayerPayloads.generateOpponentTurnSnapshot(localPlayerId: localId, opponentId: opponentId)
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject Opponent Turn Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                // Debug Trigger for Round 5 verification
                Button {
                    let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                    let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                    viewModel.gameManager.localPlayerId = localId
                    let mock = MockMultiplayerPayloads.generateMatchEndSnapshot(localPlayerId: localId, opponentId: opponentId, winnerId: localId)
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject Match End Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                // Debug Triggers for Round 6 verification
                HStack(spacing: 8) {
                    Button {
                        let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                        let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                        let mock = MockMultiplayerPayloads.generateSpecialEventSnapshot(localPlayerId: localId, opponentId: opponentId, effect: "ppeok")
                        viewModel.mockReceiveSnapshot(mock)
                    } label: {
                        Text("Ppeok!")
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.pink)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button {
                        let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                        let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                        let mock = MockMultiplayerPayloads.generateSpecialEventSnapshot(localPlayerId: localId, opponentId: opponentId, effect: "jjok")
                        viewModel.mockReceiveSnapshot(mock)
                    } label: {
                        Text("Jjok!")
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                
                // Debug Trigger for Round 7 verification
                Button {
                    let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                    let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                    let mock = MockMultiplayerPayloads.generateReconnectingSnapshot(localPlayerId: localId, opponentId: opponentId, secondsRemaining: 30)
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject Reconnect Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                // Debug Trigger for Round 8 verification
                Button {
                    let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                    let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                    let mock = MockMultiplayerPayloads.generateChatSnapshot(localPlayerId: localId, opponentId: opponentId, playerId: opponentId, emojiId: "🔥")
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject Chat Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                // Debug Trigger for Round 9 verification
                Button {
                    let localId = viewModel.gameManager.localPlayerId ?? "p1"
                    let opponentId = viewModel.gameManager.players.first(where: { $0.id.uuidString != localId })?.id.uuidString ?? "p2"
                    let mock = MockMultiplayerPayloads.generateScoreboardSnapshot(
                        localPlayerId: localId,
                        opponentId: opponentId,
                        localScore: 15,
                        opponentScore: 0,
                        roundIndex: (viewModel.gameManager.currentScoreboard?.roundIndex ?? 0) + 1
                    )
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject End Round Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button {
                    let localId = viewModel.gameManager.localPlayerId ?? "p1"
                    let mock = MockMultiplayerPayloads.generateMatchEndSnapshot(
                        winnerId: localId,
                        reason: .stop
                    )
                    viewModel.mockReceiveSnapshot(mock)
                } label: {
                    Text("Inject Match End Mock")
                        .font(.caption.bold())
                        .padding(8)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
            
            // Top Summary Bar
            VStack {
                HStack {
                    Spacer()
                    MultiplayerScoreSummaryBar(
                        roundIndex: viewModel.gameManager.currentScoreboard?.roundIndex ?? 1,
                        matchHistory: viewModel.gameManager.matchHistory,
                        localPlayerId: viewModel.gameManager.localPlayerId ?? ""
                    )
                    .onTapGesture {
                        viewModel.showScoreboardSheet = true
                    }
                    Spacer()
                }
                .padding(.top, 50)
                Spacer()
            }
            
            // Emoji Picker Trigger (Bottom Left)
            VStack {
                Spacer()
                HStack {
                    Button {
                        viewModel.showEmojiPicker.toggle()
                    } label: {
                        Text("😀")
                            .font(.title)
                            .padding(12)
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .shadow(radius: 5)
                    }
                    .padding(20)
                    Spacer()
                }
            }
            
            // Chat Bubbles (Heuristic alignment for mock/lab)
            GeometryReader { geo in
                // Local Player Bubble (Bottom Center)
                if let localChat = viewModel.gameManager.playerChats[viewModel.gameManager.localPlayerId ?? ""] {
                    ChatBubbleView(emoji: localChat.emojiId)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.8)
                }
                
                // Opponent Player Bubble (Top Center)
                let opponentId = viewModel.gameManager.players.first(where: { $0.id.uuidString != viewModel.gameManager.localPlayerId })?.id.uuidString ?? "p2"
                if let opponentChat = viewModel.gameManager.playerChats[opponentId] {
                    ChatBubbleView(emoji: opponentChat.emojiId)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.2)
                }
            }
            .allowsHitTesting(false)
            
            if viewModel.showEmojiPicker {
                EmojiPickerOverlay(isPresented: $viewModel.showEmojiPicker) { emoji in
                    viewModel.gameManager.sendChat(emojiId: emoji)
                }
            }
            
            // Round 7: Reconnection Overlay
            if viewModel.gameManager.isMultiplayerResumable {
                MultiplayerLiveReconnectOverlay(deadline: viewModel.gameManager.multiplayerGraceDeadline)
            }
            
            // Round 5 & 10: Result Overlay
            if viewModel.gameManager.gameState == .ended {
                if viewModel.gameManager.isMatchEndedFlag {
                    FinalWinnerOverlay(
                        winnerId: viewModel.gameManager.currentScoreboard?.winnerPlayerId ?? "Unknown",
                        matchHistory: viewModel.gameManager.matchHistory,
                        onLobbyReturn: {
                            viewModel.gameManager.exitToLobby()
                        }
                    )
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                } else {
                    VStack {
                        Spacer()
                        VStack(spacing: 24) {
                            Text("Round Ended")
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundColor(.yellow)
                            
                            if let scoreboard = viewModel.gameManager.currentScoreboard {
                                VStack(spacing: 8) {
                                    ForEach(scoreboard.playerScores, id: \.playerId) { score in
                                        HStack {
                                            Text(score.playerId == "p1" ? "You" : "Opponent")
                                            Spacer()
                                            Text("\(score.score) Pts")
                                                .bold()
                                        }
                                        .foregroundColor(.white)
                                    }
                                }
                                .padding(.horizontal, 40)
                            }
                            
                            Button(action: {
                                // Temporary: just reset mock state to initial for next round simulation
                                let localId = viewModel.gameManager.players.first?.id.uuidString ?? "p1"
                                let opponentId = viewModel.gameManager.players.count > 1 ? viewModel.gameManager.players[1].id.uuidString : "p2"
                                let mock = MockMultiplayerPayloads.generateInitialDealSnapshot(localPlayerId: localId, opponentId: opponentId)
                                viewModel.mockReceiveSnapshot(mock)
                            }) {
                                Text("Next Round (Mock)")
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 40)
                        }
                        .padding(.vertical, 40)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.black.opacity(0.85))
                                .shadow(radius: 20)
                        )
                        .padding(30)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.4).ignoresSafeArea())
                    .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $viewModel.showScoreboardSheet) {
            ScoreboardDetailSheet(scoreboard: viewModel.gameManager.currentScoreboard)
        }
        .ignoresSafeArea()
    }
}

struct MultiplayerLiveReconnectOverlay: View {
    let deadline: Date?
    @State private var remainingSeconds: Int = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Waiting for Reconnection...")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                
                if remainingSeconds > 0 {
                    Text("Time remaining: \(remainingSeconds)s")
                        .font(.headline)
                        .foregroundColor(.yellow)
                } else {
                    Text("Connection lost. Waiting for server...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            updateRemaining()
        }
        .onReceive(timer) { _ in
            updateRemaining()
        }
    }
    
    private func updateRemaining() {
        guard let deadline = deadline else {
            remainingSeconds = 0
            return
        }
        let remaining = Int(deadline.timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)
    }
}


struct ChatBubbleView: View {
    let emoji: String
    
    var body: some View {
        Text(emoji)
            .font(.system(size: 40))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white)
                    .shadow(radius: 5)
            )
            .overlay(
                Image(systemName: "arrowtriangle.down.fill")
                    .foregroundColor(.white)
                    .offset(y: 28)
            )
            .transition(.scale.combined(with: .opacity))
    }
}

struct EmojiPickerOverlay: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    
    let emojis = ["😀", "😎", "🔥", "👍", "😮", "🙏", "💢", "🃏"]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
            
            VStack {
                Spacer()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            onSelect(emoji)
                            isPresented = false
                        } label: {
                            Text(emoji)
                                .font(.system(size: 40))
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .shadow(radius: 2)
                        }
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.95))
                        .shadow(radius: 10)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea()
    }
}

struct MultiplayerScoreSummaryBar: View {
    let roundIndex: Int
    let matchHistory: [String: Int]
    let localPlayerId: String
    
    var body: some View {
        HStack(spacing: 15) {
            Text("ROUND \(roundIndex)")
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundColor(.white.opacity(0.8))
            
            Divider()
                .frame(height: 15)
                .background(Color.white.opacity(0.3))
            
            let localWins = matchHistory[localPlayerId] ?? 0
            let opponentId = matchHistory.keys.first(where: { $0 != localPlayerId }) ?? "opponent"
            let opponentWins = matchHistory[opponentId] ?? 0
            
            HStack(spacing: 8) {
                Text("\(localWins)")
                    .foregroundColor(.yellow)
                    .bold()
                Text("-")
                    .foregroundColor(.white.opacity(0.6))
                Text("\(opponentWins)")
                    .foregroundColor(.white)
                    .bold()
            }
            .font(.headline)
            
            Image(systemName: "list.bullet.rectangle.portrait")
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
    }
}

struct ScoreboardDetailSheet: View {
    let scoreboard: MultiplayerScoreboard?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if let scoreboard = scoreboard {
                    Section(header: Text("Round \(scoreboard.roundIndex) Results")) {
                        ForEach(scoreboard.playerScores, id: \.playerId) { score in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(score.playerId == "p1" ? "Local Player" : "Opponent")
                                        .font(.headline)
                                    Text("Go: \(score.goCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(score.score) Pts")
                                    .font(.title3.bold())
                                    .foregroundColor(score.score > 0 ? .red : .primary)
                            }
                        }
                    }
                } else {
                    Text("No scoreboard data available yet.")
                }
            }
            .navigationTitle("Scoreboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Close") { dismiss() }
            }
        }
    }
}

struct FinalWinnerOverlay: View {
    let winnerId: String
    let matchHistory: [String: Int]
    let onLobbyReturn: () -> Void
    
    @State private var animateSrophy = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            // Celebration Background
            Circle()
                .fill(RadialGradient(colors: [.yellow.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 300))
                .scaleEffect(animateSrophy ? 1.5 : 0.8)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateSrophy)
            
            VStack(spacing: 30) {
                Text("🏆 MATCH ENDED 🏆")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.yellow)
                
                VStack(spacing: 12) {
                    Text(winnerId == "p1" ? "YOU WON!" : "OPPONENT WON")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Final Session Score")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 30) {
                        VStack {
                            Text("YOU")
                                .font(.caption.bold())
                            Text("\(matchHistory["p1"] ?? 0)")
                                .font(.system(size: 40, weight: .bold))
                        }
                        .foregroundColor(winnerId == "p1" ? .yellow : .white)
                        
                        Text(":")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.3))
                        
                        let opponentId = matchHistory.keys.first(where: { $0 != "p1" }) ?? "p2"
                        VStack {
                            Text("OPPONENT")
                                .font(.caption.bold())
                            Text("\(matchHistory[opponentId] ?? 0)")
                                .font(.system(size: 40, weight: .bold))
                        }
                        .foregroundColor(winnerId != "p1" ? .yellow : .white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Spacer().frame(height: 50)
                
                Button(action: onLobbyReturn) {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("Return to Lobby")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(30)
                    .shadow(color: .yellow.opacity(0.5), radius: 10, x: 0, y: 5)
                }
            }
        }
        .onAppear {
            animateSrophy = true
        }
    }
}
