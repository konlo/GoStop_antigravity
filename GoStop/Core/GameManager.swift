import Foundation
import SwiftUI
import Combine

enum GameState: String, Codable {
    case ready
    case askingShake
    case playing
    case askingGoStop
    case choosingCapture  // Waiting for player to pick which table card to capture (junk vs doubleJunk)
    case choosingChrysanthemumRole // Waiting for player to decide if Sep Animal is Animal or Double Pi
    case ended
}

enum GameEndReason: String, Codable {
    case stop
    case maxScore
    case nagari
    case chongtong
    case threeSeolsa
}

struct UXEvent: Codable {
    let id: String
    let type: String // "animationStart", "animationEnd", "stateTransition"
    let timestamp: TimeInterval
    let data: [String: String] // cardId, source, target, etc.
}


func gLog(_ message: String) {
    #if DEBUG
    fputs("\(message)\n", stderr)
    #else
    print(message)
    #endif
    
    // Also record to event logs for AI/Simulator inspection - MUST be on main thread
    if Thread.isMainThread {
        GameManager.shared?.addEvent(message)
    } else {
        DispatchQueue.main.async {
            GameManager.shared?.addEvent(message)
        }
    }
}

private struct CumulativeWinScoreSnapshot: Codable {
    let version: Int
    let totals: [String: Int]
}

private final class CumulativeWinScoreStore {
    static let shared = CumulativeWinScoreStore()

    private let fileManager: FileManager
    private let fileURL: URL
    private var totals: [String: Int] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = Self.resolveFileURL(fileManager: fileManager)
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.loadFromDisk()
    }

    func snapshot() -> [String: Int] {
        totals
    }

    @discardableResult
    func add(points: Int, to playerName: String) -> Int {
        guard points > 0 else { return totals[playerName, default: 0] }
        let updatedTotal = totals[playerName, default: 0] + points
        totals[playerName] = updatedTotal
        persistToDisk()
        return updatedTotal
    }

    private static func resolveFileURL(fileManager: FileManager) -> URL {
        let baseURL =
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if !fileManager.fileExists(atPath: baseURL.path) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
        return baseURL.appendingPathComponent("gostop_cumulative_win_scores.json")
    }

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            totals = [:]
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(CumulativeWinScoreSnapshot.self, from: data)
            totals = snapshot.totals
        } catch {
            // Keep gameplay running even if score file is malformed.
            totals = [:]
        }
    }

    private func persistToDisk() {
        let snapshot = CumulativeWinScoreSnapshot(version: 1, totals: totals)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failure should not block gameplay.
        }
    }
}

class GameManager: ObservableObject {
    static var shared: GameManager?
    
    @Published var gameState: GameState = .ready
    @Published var players: [Player] = []
    @Published var deck = Deck()
    
    /// Hook for multiplayer coordinators to intercept local player actions.
    var onLocalAction: ((MultiplayerAction) -> Void)?
    
    @Published var isMultiplayerResumable: Bool = false
    @Published var multiplayerGraceDeadline: Date? = nil
    
    @Published var currentTurnIndex: Int = 0
    @Published private(set) var currentRoundStarterIndex: Int? = nil
    @Published var tableCards: [Card] = []
    @Published var outOfPlayCards: [Card] = []
    
    @Published var playerChats: [String: MultiplayerChatPresence] = [:]
    
    @Published var currentScoreboard: MultiplayerScoreboard? = nil
    @Published var matchHistory: [String: Int] = [:]
    
    @Published var isMatchEndedFlag: Bool = false
    
    func sendChat(emojiId: String) {
        let action = MultiplayerAction.chat(emojiId: emojiId)
        self.relayLocalMultiplayerAction(action)
        
        // Optimistically show locally if desired, or wait for server reflection.
        // For Go-Stop, waiting for server reflection is safer for sync.
    }
    
    func exitToLobby() {
        // Reset multiplayer session state
        self.matchHistory = [:]
        self.playerChats = [:]
        self.currentScoreboard = nil
        self.isMatchEndedFlag = false
        
        // Reset general game state to trigger shell transition back to lobby/room
        self.gameState = .ready
    }
    
    // Unified Animation Tracking
    @Published var currentMovingCards: [Card] = []
    @Published var movingCardsScale: CGFloat = 1.0
    @Published var movingCardsPiCount: Int? = nil
    @Published var hiddenInSourceCardIds: Set<String> = []
    @Published var hiddenInTargetCardIds: Set<String> = []
    @Published var currentMoveSourceZone: String? = nil
    @Published var currentMoveTargetZone: String? = nil
    @Published var capturedMoveSourcePlayerId: String? = nil
    @Published var capturedMoveTargetPlayerId: String? = nil
    @Published var penaltyMoveProgress: Double = 0
    @Published var sourceCueCardIds: Set<String> = []
    @Published var targetCueCardIds: Set<String> = []
    @Published var opponentPreplayRevealCardId: String? = nil
    @Published var movingCardsShowDebug: Bool = false
    @Published private(set) var pendingAutomationDelays: Int = 0
    private var automationDelayGeneration: Int = 0
    
    // For shake (흔들기) handling
    @Published var pendingShakeMonths: [Int] = []
    var pendingShakeCard: Card? = nil
    var pendingShakeMonth: Int? = nil
    
    // For Seolsa (뻑/설사) tracking
    @Published var monthOwners: [Int: Player] = [:]
    @Published var seolsaMonths: [Int: Player] = [:] // Tracks which months are in a "뻑" state and who made it
    private var invalidLastHandSeolsaMonths: Set<Int> = [] // Triple left by last-hand Seolsa should not grant Seolsa Eat.
    
    // For capture card selection (테이블 2장 중 선택)
    @Published var pendingCapturePlayedCard: Card? = nil
    @Published var pendingCaptureDrawnCard: Card? = nil
    @Published var pendingCaptureOptions: [Card] = []
    
    // For September Chrysanthemum (국화) choice
    @Published var pendingChrysanthemumCard: Card? = nil
    
    // Captured flags for current turn processing
    private var isSeolsaEatFlag = false
    private var isSelfSeolsaEatFlag = false
    
    // Turn State (persists across pauses like choosingCapture or choosingChrysanthemumRole)
    private var turnIsBomb = false
    private var turnIsTtadak = false
    private var turnIsJjok = false
    private var turnIsSeolsa = false
    private var turnPlayPhaseCaptured: [Card] = []
    private var turnDrawPhaseCaptured: [Card] = []
    private var turnPlayedCard: Card? = nil
    private var turnTableWasNotEmpty = false
    private var turnWasOpeningTurn = false
    private var completedTurnCount = 0
    // Logical table after resolving play-phase capture (used for draw-phase rules).
    // Visual table can still keep pending play captures until draw is revealed.
    private var turnPlayPhaseResultingTable: [Card]? = nil
    // Track whether play-phase capture already completed its table->captured animation.
    private var turnPlayPhaseCaptureCommitted = false
    // Base logical table for draw-choice resolution when draw capture requires user selection.
    private var turnDrawPhaseBaseTable: [Card]? = nil
    
    // Endgame state tracking
    @Published var gameEndReason: GameEndReason?
    @Published var lastPenaltyResult: PenaltySystem.PenaltyResult?
    @Published var gameWinner: Player?
    @Published var gameLoser: Player?
    
    // Chongtong state
    @Published var chongtongMonth: Int? = nil
    @Published var chongtongTiming: String? = nil // "initial" or "midgame"
    
    // Persistent cumulative winning scores (loaded from file).
    @Published private(set) var cumulativeWinScores: [String: Int] = [:]
    
    // Event Logs for inspection
    @Published var eventLogs: [String] = []
    @Published var uxEventLogs: [UXEvent] = []
    @Published var uiActiveSpecialEventPopupTitle: String? = nil
    @Published var uiPendingSpecialEventPopupCount: Int = 0
    @Published var uiIsEndSummaryDeferredBySpecialEvents: Bool = false
    @Published var uiIsDecisionOverlayDeferredBySpecialEvents: Bool = false
    @Published var uiActiveCapturedPreviewOwnerPlayerId: String? = nil
    @Published var uiActiveCapturedPreviewGroupType: String? = nil
    @Published var uiActiveCapturedPreviewCardCount: Int = 0
    private var stateHistory: [[String: AnyCodable]] = []
    private var scoreEventKindsByPlayer: [String: Set<String>] = [:]
    
    private var playerChangeCancellables: [AnyCancellable] = []
    private let cumulativeWinScoreStore = CumulativeWinScoreStore.shared

    
    // Manual UI uses internal computer automation. External agents should disable it.
    var internalComputerAutomationEnabled = false
    var externalControlMode = false
    @Published var localPlayerId: String? = nil
    private var internalComputerActionScheduled = false
    private var suppressExternalActionRelay = false

    var isLocalTurn: Bool {
        guard externalControlMode else { return true }
        guard let localId = localPlayerId else { return true }
        return currentPlayer?.id.uuidString == localId
    }

    var isAutomationBusy: Bool {
        pendingAutomationDelays > 0 ||
        !currentMovingCards.isEmpty ||
        !hiddenInSourceCardIds.isEmpty ||
        !hiddenInTargetCardIds.isEmpty
    }
    
    var currentPlayer: Player? {
        guard players.indices.contains(currentTurnIndex) else { return nil }
        return players[currentTurnIndex]
    }

    private func relayLocalMultiplayerAction(_ action: MultiplayerAction) {
        guard !suppressExternalActionRelay else { return }
        onLocalAction?(action)
    }

    private func withSuppressedExternalActionRelay(_ action: () -> Void) {
        let previous = suppressExternalActionRelay
        suppressExternalActionRelay = true
        defer { suppressExternalActionRelay = previous }
        action()
    }

    private func gameEndReasonText(_ reason: GameEndReason) -> String {
        switch reason {
        case .stop:
            return gameText("penalty.reason.stop")
        case .maxScore:
            return gameText("penalty.reason.max_score")
        case .nagari:
            return gameText("penalty.reason.nagari")
        case .chongtong:
            return gameText("penalty.reason.chongtong")
        case .threeSeolsa:
            return gameText("penalty.reason.three_seolsa")
        }
    }

    private func piTransferReasonSuffix(_ reason: String) -> String {
        reason.isEmpty ? "" : " [\(reason)]"
    }

    private func setMoveContext(
        source: String,
        target: String,
        capturedSourcePlayerId: String? = nil,
        capturedTargetPlayerId: String? = nil
    ) {
        currentMoveSourceZone = source
        currentMoveTargetZone = target
        self.capturedMoveSourcePlayerId = capturedSourcePlayerId
        self.capturedMoveTargetPlayerId = capturedTargetPlayerId
    }

    private func clearMoveContext() {
        currentMoveSourceZone = nil
        currentMoveTargetZone = nil
        capturedMoveSourcePlayerId = nil
        capturedMoveTargetPlayerId = nil
    }
    
    init() {
        GameManager.shared = self
        cumulativeWinScores = cumulativeWinScoreStore.snapshot()
        setupGame()
    }

    func refreshPlayerChangeForwarding() {
        playerChangeCancellables = players.map { player in
            player.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }
    }
    
    func addEvent(_ message: String) {
        self.eventLogs.append(message)
        if self.eventLogs.count > 100 {
            self.eventLogs.removeFirst()
        }
    }
    
    func addUXEvent(type: String, data: [String: String]) {
        let event = UXEvent(id: UUID().uuidString, type: type, timestamp: Date().timeIntervalSince1970, data: data)
        self.uxEventLogs.append(event)
        if self.uxEventLogs.count > 200 {
            self.uxEventLogs.removeFirst()
        }
    }

    func updateSpecialEventOverlayProbe(
        activePopupTitle: String?,
        pendingQueueCount: Int,
        isEndSummaryDeferred: Bool,
        isDecisionOverlayDeferred: Bool
    ) {
        uiActiveSpecialEventPopupTitle = activePopupTitle
        uiPendingSpecialEventPopupCount = max(0, pendingQueueCount)
        uiIsEndSummaryDeferredBySpecialEvents = isEndSummaryDeferred
        uiIsDecisionOverlayDeferredBySpecialEvents = isDecisionOverlayDeferred
    }

    func updateCapturedPreviewProbe(ownerPlayerId: String?, groupType: String?, cardCount: Int) {
        let safeCount = max(0, cardCount)
        if uiActiveCapturedPreviewOwnerPlayerId != ownerPlayerId ||
           uiActiveCapturedPreviewGroupType != groupType ||
           uiActiveCapturedPreviewCardCount != safeCount {
            uiActiveCapturedPreviewOwnerPlayerId = ownerPlayerId
            uiActiveCapturedPreviewGroupType = groupType
            uiActiveCapturedPreviewCardCount = safeCount
        }
    }

    private func updateScoreAndEmitScoreEvents(for player: Player) {
        let scoreItems = ScoringSystem.calculateScoreDetail(for: player)
        player.score = scoreItems.reduce(0) { $0 + $1.points }
        emitScoreEventsIfNeeded(for: player, scoreItems: scoreItems)
    }

    private func emitScoreEventsIfNeeded(for player: Player, scoreItems: [ScoreItem]) {
        let playerKey = player.id.uuidString
        let currentKinds = detectedScoreEventKinds(from: scoreItems)
        let previousKinds = scoreEventKindsByPlayer[playerKey] ?? []
        let newlyAdded = currentKinds.subtracting(previousKinds)

        let orderedKinds = ["cheongdan", "hongdan", "godori", "gusa"]
        for kind in orderedKinds where newlyAdded.contains(kind) {
            switch kind {
            case "cheongdan":
                gLog(gameText("log.event.score_cheongdan", ["player": player.name]))
            case "hongdan":
                gLog(gameText("log.event.score_hongdan", ["player": player.name]))
            case "godori":
                gLog(gameText("log.event.score_godori", ["player": player.name]))
            case "gusa":
                gLog(gameText("log.event.score_gusa", ["player": player.name]))
            default:
                break
            }
        }

        scoreEventKindsByPlayer[playerKey] = currentKinds
    }

    private func detectedScoreEventKinds(from scoreItems: [ScoreItem]) -> Set<String> {
        var kinds: Set<String> = []
        for item in scoreItems {
            let name = item.name
            if name.contains("청단") || name.contains("Blue Ribbons") {
                kinds.insert("cheongdan")
            }
            if name.contains("홍단") || name.contains("Red Ribbons") {
                kinds.insert("hongdan")
            }
            if name.contains("고도리") || name.contains("Godori") {
                kinds.insert("godori")
            }
            if (name.contains("열끗") || name.contains("Animals")), let count = item.count, count >= 9 {
                kinds.insert("gusa")
            }
        }
        return kinds
    }

    func cumulativeWinScore(for player: Player) -> Int {
        cumulativeWinScores[player.name, default: 0]
    }

    private func recordWinScore(points: Int, for player: Player) {
        let updated = cumulativeWinScoreStore.add(points: points, to: player.name)
        cumulativeWinScores[player.name] = updated
    }
    
    func getHistoryEntry(at index: Int) -> [String: AnyCodable]? {
        guard index >= 0 && index < stateHistory.count else { return nil }
        return stateHistory[index]
    }

    private var lastSnapshotTime: TimeInterval = 0
    func takeSnapshot() {
        // Simple throttle to avoid flooding snapshots in extremely tight loops (e.g. concurrent animations)
        let now = Date().timeIntervalSince1970
        if now - lastSnapshotTime < 0.05 { return } 
        lastSnapshotTime = now
        
        let snapshot = self.serializeState()
        self.stateHistory.append(snapshot)
        if self.stateHistory.count > 50 {
            self.stateHistory.removeFirst()
        }
    }

    
    func setupGame(seed: Int? = nil) {
        automationDelayGeneration += 1
        externalControlMode = false
        let player1 = Player(name: gameText("players.default.player_one"), money: 10000)
        let computer = Player(name: gameText("players.default.computer"), money: 10000)
        computer.isComputer = true
        self.players = [player1, computer]
        refreshPlayerChangeForwarding()
        self.currentTurnIndex = 0
        self.currentRoundStarterIndex = nil
        self.outOfPlayCards = []
        self.gameEndReason = nil
        self.lastPenaltyResult = nil
        self.gameWinner = nil
        self.gameLoser = nil
        self.chongtongMonth = nil
        self.chongtongTiming = nil
        self.eventLogs = []
        self.uxEventLogs.removeAll()
        self.uiActiveSpecialEventPopupTitle = nil
        self.uiPendingSpecialEventPopupCount = 0
        self.uiIsEndSummaryDeferredBySpecialEvents = false
        self.uiIsDecisionOverlayDeferredBySpecialEvents = false
        self.uiActiveCapturedPreviewOwnerPlayerId = nil
        self.uiActiveCapturedPreviewGroupType = nil
        self.uiActiveCapturedPreviewCardCount = 0
        self.stateHistory = []
        self.scoreEventKindsByPlayer = [:]
        self.deck.reset(seed: seed)
        self.monthOwners = [:]
        self.seolsaMonths = [:]
        self.invalidLastHandSeolsaMonths = []
        self.currentMovingCards = []
        self.penaltyMoveProgress = 0
        self.sourceCueCardIds = []
        self.targetCueCardIds = []
        self.movingCardsScale = 1.0
        self.movingCardsPiCount = nil
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.currentMoveSourceZone = nil
        self.currentMoveTargetZone = nil
        self.capturedMoveSourcePlayerId = nil
        self.capturedMoveTargetPlayerId = nil
        self.opponentPreplayRevealCardId = nil
        self.movingCardsShowDebug = false
        self.pendingAutomationDelays = 0
        self.pendingShakeMonths = []
        self.pendingShakeCard = nil
        self.pendingShakeMonth = nil
        self.pendingCapturePlayedCard = nil
        self.pendingCaptureDrawnCard = nil
        self.pendingCaptureOptions = []
        self.pendingChrysanthemumCard = nil
        self.isSeolsaEatFlag = false
        self.isSelfSeolsaEatFlag = false
        self.turnIsBomb = false
        self.turnIsTtadak = false
        self.turnIsJjok = false
        self.turnIsSeolsa = false
        self.turnPlayPhaseCaptured = []
        self.turnDrawPhaseCaptured = []
        self.turnPlayedCard = nil
        self.turnTableWasNotEmpty = false
        self.turnWasOpeningTurn = false
        self.completedTurnCount = 0
        self.turnPlayPhaseResultingTable = nil
        self.turnPlayPhaseCaptureCommitted = false
        self.turnDrawPhaseBaseTable = nil
        self.internalComputerActionScheduled = false
        self.gameState = .ready
        self.dealCards()
        self.takeSnapshot()
    }

    func resetPresentationStateForExternalSnapshot() {
        self.automationDelayGeneration += 1
        self.pendingAutomationDelays = 0
        self.currentMovingCards = []
        self.penaltyMoveProgress = 0
        self.sourceCueCardIds = []
        self.targetCueCardIds = []
        self.movingCardsScale = 1.0
        self.movingCardsPiCount = nil
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.currentMoveSourceZone = nil
        self.currentMoveTargetZone = nil
        self.capturedMoveSourcePlayerId = nil
        self.capturedMoveTargetPlayerId = nil
        self.opponentPreplayRevealCardId = nil
        self.movingCardsShowDebug = false
        self.internalComputerActionScheduled = false
    }

    
    func dealCards() {
        // Standard 2-player deal: 10 cards each, 8 on table
        gLog(gameText("log.event.deal_cards"))
        for player in players {
            player.hand = deck.draw(count: 10)
        }
        tableCards = deck.draw(count: 8)
        
        // Initial Table 4-card Nagari check
        var tableMonthCounts: [Int: Int] = [:]
        for card in tableCards {
            tableMonthCounts[card.month.rawValue, default: 0] += 1
        }
        
        if let monthIdx = tableMonthCounts.first(where: { $0.value == 4 })?.key {
            let month = Month(rawValue: monthIdx) ?? .none
            gLog(gameText("log.event.initial_table_nagari", ["month": String(describing: month)]))
            self.gameState = .ended
            self.gameEndReason = .nagari
            return
        }

        // Initial Chongtong check
        if let rules = RuleLoader.shared.config, rules.special_moves.chongtong.enabled {
            for player in players {
                if let month = getChongtongMonth(for: player) {
                    gLog(gameText("log.event.initial_chongtong", ["player": player.name, "month": month]))
                    resolveChongtong(player: player, month: month, timing: "initial")
                    return
                }
            }
        }
    }
    
    func mockDeck(cards: [Card]) {
        deck.pushCardsOnTop(cards)
    }
    
    func startGame(initialTurnIndex: Int? = nil) {
        if gameState == .ended {
            gLog(gameText("log.event.skip_start_game_already_ended"))
            return
        }
        // 이전 게임의 이동 애니메이션이 stuck 상태로 남아있을 수 있음.
        // generation을 증가시켜 이전 in-flight 딜레이 콜백을 무효화하고
        // move context를 초기화하여 tableToCapturedOverlay 무한 루프를 방지.
        self.automationDelayGeneration += 1
        self.currentMovingCards = []
        self.pendingAutomationDelays = 0
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.sourceCueCardIds = []
        self.targetCueCardIds = []
        self.clearMoveContext()
        self.internalComputerActionScheduled = false

        let startingTurnIndex: Int
        if let initialTurnIndex, players.indices.contains(initialTurnIndex) {
            startingTurnIndex = initialTurnIndex
        } else {
            startingTurnIndex = 0
        }
        let starterName = players.indices.contains(startingTurnIndex)
            ? players[startingTurnIndex].name
            : gameText("players.default.player_one")
        gLog(gameText("log.event.game_started", ["starter": starterName]))
        self.uxEventLogs.removeAll() // Ensure HUD is correctly reset for test agent loops
        currentRoundStarterIndex = players.indices.contains(startingTurnIndex) ? startingTurnIndex : nil
        currentTurnIndex = startingTurnIndex
        gameState = .playing
        maybeScheduleInternalComputerAction()
    }

    func setCompletedTurnCountForTesting(_ count: Int) {
        completedTurnCount = max(0, count)
        turnWasOpeningTurn = completedTurnCount == 0
    }

    func setCurrentRoundStarterIndexForTesting(_ index: Int?) {
        guard let index else {
            currentRoundStarterIndex = nil
            return
        }
        currentRoundStarterIndex = players.indices.contains(index) ? index : nil
    }

    /// Returns the current round winner index (0-based) so the next round can start from winner.
    /// Returns nil when there is no winner (e.g., nagari) or winner is not in current players list.
    func previousRoundWinnerIndex() -> Int? {
        guard let winner = gameWinner else { return nil }
        return players.firstIndex(where: { $0.id == winner.id })
    }

    func isNightDayStarterDaytime(dayStartHour: Int, dayEndHour: Int, referenceDate: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: referenceDate)
        let normalizedDayStart = ((dayStartHour % 24) + 24) % 24
        let normalizedDayEnd = ((dayEndHour % 24) + 24) % 24
        if normalizedDayStart == normalizedDayEnd {
            return true
        }
        if normalizedDayStart < normalizedDayEnd {
            return hour >= normalizedDayStart && hour < normalizedDayEnd
        }
        // Wrap-around window (e.g., day starts at 22 and ends at 06).
        return hour >= normalizedDayStart || hour < normalizedDayEnd
    }

    /// Returns starter index based on 밤일낮장 comparison.
    /// - Returns: `0` for player one, `1` for player two, `nil` when tied.
    func resolveNightDayStarterWinner(
        playerOneMonth: Int,
        playerTwoMonth: Int,
        dayStartHour: Int,
        dayEndHour: Int,
        referenceDate: Date = Date()
    ) -> Int? {
        guard playerOneMonth != playerTwoMonth else { return nil }
        let isDaytime = isNightDayStarterDaytime(
            dayStartHour: dayStartHour,
            dayEndHour: dayEndHour,
            referenceDate: referenceDate
        )
        let playerOneStarts = isDaytime
            ? (playerOneMonth > playerTwoMonth)
            : (playerOneMonth < playerTwoMonth)
        return playerOneStarts ? 0 : 1
    }

    func resolveNightDayStarterIndex(dayStartHour: Int, dayEndHour: Int, referenceDate: Date = Date()) -> Int {
        let isDaytime = isNightDayStarterDaytime(
            dayStartHour: dayStartHour,
            dayEndHour: dayEndHour,
            referenceDate: referenceDate
        )

        let drawMonths = deck.cards.reversed().map { $0.month.rawValue }
        var drawIndex = 0
        while drawIndex + 1 < drawMonths.count {
            let playerOneMonth = drawMonths[drawIndex]
            let playerTwoMonth = drawMonths[drawIndex + 1]
            if let winnerIndex = resolveNightDayStarterWinner(
                playerOneMonth: playerOneMonth,
                playerTwoMonth: playerTwoMonth,
                dayStartHour: dayStartHour,
                dayEndHour: dayEndHour,
                referenceDate: referenceDate
            ) {
                let modeLabel = isDaytime ? gameText("starter.mode.day") : gameText("starter.mode.night")
                gLog(
                    gameText(
                        "log.event.first_launch_starter_decided",
                        [
                            "mode": modeLabel,
                            "playerOneMonth": playerOneMonth,
                            "playerTwoMonth": playerTwoMonth,
                            "winnerIndex": winnerIndex
                        ]
                    )
                )
                return winnerIndex
            }
            drawIndex += 2
        }

        gLog(gameText("log.event.starter_tie_fallback"))
        return 0
    }
    
    private func getMonthsWithThreePlus(in hand: [Card]) -> [Int] {
        var counts: [Int: Int] = [:]
        for card in hand {
            counts[card.month.rawValue, default: 0] += 1
        }
        return counts.filter { $0.value >= 3 }.map { $0.key }.sorted()
    }
    
    // Chongtong helpers
    func getChongtongMonth(for player: Player) -> Int? {
        var counts: [Int: Int] = [:]
        for card in player.hand {
            if card.month != .none {
                counts[card.month.rawValue, default: 0] += 1
            }
        }
        return counts.filter { $0.value == 4 }.map { $0.key }.first
    }
    
    func resolveChongtong(player: Player, month: Int, timing: String) {
        guard let rules = RuleLoader.shared.config else { return }
        
        self.chongtongMonth = month
        self.chongtongTiming = timing
        self.gameWinner = player
        self.gameLoser = players.first { $0 !== player }
        self.gameEndReason = .chongtong
        
        let score = (timing == "initial") ? 
            rules.special_moves.chongtong.initial_chongtong_score : 
            rules.special_moves.chongtong.midgame_chongtong_score
            
        player.score = score
        self.lastPenaltyResult = PenaltySystem.PenaltyResult(
            finalScore: score,
            isGwangbak: false,
            isPibak: false,
            isGobak: false,
            isMungbak: false,
            isJabak: false,
            isYeokbak: false,
            scoreFormula: gameText("penalty.formula.chongtong_rule", ["timing": timing, "score": score])
        )
        recordWinScore(points: score, for: player)
        
        self.gameState = .ended
        gLog(gameText("log.event.game_ended_chongtong", ["player": player.name, "score": score]))
    }
    
    func respondToShake(month: Int, didShake: Bool) {
        guard gameState == .askingShake, let player = currentPlayer else { return }
        if externalControlMode {
            relayLocalMultiplayerAction(.respondToShake(month: month, didShake: didShake))
        }
        
        if didShake {
            player.shakeCount += 1
            player.shakenMonths.append(month)
            gLog(gameText("log.event.shake_declared", ["player": player.name, "month": month]))
        } else {
            if !player.shakenMonths.contains(month) {
                player.shakenMonths.append(month)
            }
        }
        
        pendingShakeMonths.removeAll { $0 == month }
        
        if pendingShakeMonths.isEmpty {
            gameState = .playing
            gLog(gameText("log.event.shake_resolved"))
            if let card = pendingShakeCard {
                pendingShakeCard = nil
                pendingShakeMonth = nil
                if externalControlMode {
                    withSuppressedExternalActionRelay {
                        playTurn(card: card)
                    }
                } else {
                    playTurn(card: card)
                }
            } else {
                maybeScheduleInternalComputerAction()
            }
        } else {
            gLog(gameText("log.event.shake_more_pending", ["months": String(describing: pendingShakeMonths)]))
            maybeScheduleInternalComputerAction()
        }
    }
    
    func respondToChrysanthemumChoice(role: CardRole) {
        guard (gameState == .choosingChrysanthemumRole || (currentPlayer?.isComputer == true && gameState == .playing)),
              let player = currentPlayer,
              let card = pendingChrysanthemumCard else { return }
        if externalControlMode {
            relayLocalMultiplayerAction(.respondToChrysanthemumChoice(role: role.rawValue))
        }
        
        gLog(gameText("log.event.chrysanthemum_role_chosen", ["player": player.name, "role": role.rawValue]))
        
        player.objectWillChange.send()
        var updatedCard = card
        updatedCard.selectedRole = role
        
        player.capture(cards: [updatedCard])
        gLog(gameText("log.event.chrysanthemum_capture_success", ["role": role.rawValue]))
        
        pendingChrysanthemumCard = nil
        gameState = .playing
        
        updateScoreAndEmitScoreEvents(for: player)
        
        finalizeTurnAfterCapture(player: player)
    }

    private func isValidJjokTurn(for player: Player) -> Bool {
        // House rule: a Jjok created by the last hand card is invalid.
        turnIsJjok && !player.hand.isEmpty
    }

    private func finalizeTurnAfterCapture(player: Player) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }

        // One-turn flags: consume once at turn finalization and clear immediately
        // so they never leak into the next turn.
        let didSeolsaEat = isSeolsaEatFlag
        let didSelfSeolsaEat = isSelfSeolsaEatFlag
        let isValidJjok = isValidJjokTurn(for: player)
        isSeolsaEatFlag = false
        isSelfSeolsaEatFlag = false
        
        if turnIsBomb {
            gLog(gameText("log.event.bomb_triggered", ["player": player.name]))
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.bomb.steal_pi_count,
                reason: gameText("log.reason.bomb")
            )
        }
        if turnIsTtadak && rules.special_moves.ttadak.enabled {
            player.ttadakCount += 1
            gLog(gameText("log.event.ttadak_triggered", ["player": player.name]))
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.ttadak.steal_pi_count,
                reason: gameText("log.reason.ttadak")
            )
            maybeAwardOpeningTurnBonus(
                to: player,
                alreadyAwarded: player.awardedFirstTurnTtadakBonus,
                setAwarded: { player.awardedFirstTurnTtadakBonus = true },
                points: rules.special_moves.ttadak.first_turn_bonus_score ?? 0,
                label: gameText("log.label.opening_ttadak")
            )
        }
        if turnIsJjok && !isValidJjok {
            gLog(gameText("log.event.jjok_last_hand_ignored", ["player": player.name]))
        }
        if isValidJjok && rules.special_moves.jjok.enabled {
            player.jjokCount += 1
            gLog(gameText("log.event.jjok_triggered", ["player": player.name]))
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.jjok.steal_pi_count,
                reason: gameText("log.reason.jjok")
            )
        }
        if turnIsSeolsa && rules.special_moves.seolsa.enabled && turnPlayPhaseCaptured.isEmpty {
            let month = turnPlayedCard?.month.rawValue ?? 0
            let invalidOnLastHand = rules.special_moves.seolsa.invalid_on_last_hand ?? true
            let isInvalidLastHandSeolsa = invalidOnLastHand && player.hand.isEmpty

            if isInvalidLastHandSeolsa {
                invalidLastHandSeolsaMonths.insert(month)
            } else {
                player.seolsaCount += 1
                gLog(gameText("log.event.seolsa_triggered", ["player": player.name, "month": month]))
                let seolsaPenaltyPi = rules.special_moves.seolsa.penalty_pi_count
                if seolsaPenaltyPi > 0 {
                    stealPi(
                        from: player,
                        to: opponent,
                        count: seolsaPenaltyPi,
                        reason: gameText("log.reason.seolsa_penalty")
                    )
                }
                seolsaMonths[month] = player
                maybeAwardOpeningTurnBonus(
                    to: player,
                    alreadyAwarded: player.awardedFirstTurnSeolsaBonus,
                    setAwarded: { player.awardedFirstTurnSeolsaBonus = true },
                    points: rules.special_moves.seolsa.first_turn_bonus_score ?? 0,
                    label: gameText("log.label.opening_seolsa")
                )
            }
        }
        if didSeolsaEat && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            gLog(gameText("log.event.seolsa_eat_triggered", ["player": player.name]))
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.seolsaEat.steal_pi_count,
                reason: gameText("log.reason.seolsa_eat")
            )
        }
        if didSelfSeolsaEat && rules.special_moves.seolsaEat.enabled {
            player.seolsaEatCount += 1
            gLog(gameText("log.event.self_seolsa_eat_triggered", ["player": player.name]))
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.seolsaEat.self_eat_steal_pi_count,
                reason: gameText("log.reason.self_seolsa_eat")
            )
        }
        
        let allowEmptyStartJjokSweep =
            rules.special_moves.sweep.allow_empty_start_via_jjok &&
            isValidJjok &&
            !turnTableWasNotEmpty
        if rules.special_moves.sweep.enabled,
           (turnTableWasNotEmpty || allowEmptyStartJjokSweep),
           tableCards.isEmpty,
           !player.hand.isEmpty {
            gLog(gameText("log.event.sweep_triggered", ["player": player.name]))
            player.sweepCount += 1
            stealPi(
                from: opponent,
                to: player,
                count: rules.special_moves.sweep.steal_pi_count,
                reason: gameText("log.reason.sweep")
            )
        }
        
        if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: false) {
            return
        }

        let minScore = players.count == 3 ? rules.go_stop.min_score_3_players : rules.go_stop.min_score_2_players
        if player.score >= minScore && player.score > player.lastGoScore {
            if isScoreClaimBlocked(winner: player, loser: opponent, rules: rules) {
                gLog(
                    gameText(
                        "log.event.score_claim_blocked",
                        ["player": player.name, "score": player.score, "opponent": opponent.name]
                    )
                )
                endTurn()
            } else if player.hand.count == 0 {
                gLog(gameText("log.event.forced_stop_no_cards", ["player": player.name, "score": player.score]))
                executeStop(player: player, rules: rules)
            } else {
                gameState = .askingGoStop
                maybeScheduleInternalComputerAction()
            }
        } else {
            endTurn()
        }
    }

    private func maybeAwardOpeningTurnBonus(
        to player: Player,
        alreadyAwarded: Bool,
        setAwarded: () -> Void,
        points: Int,
        label: String
    ) {
        let isOpeningTurnContext = turnWasOpeningTurn || completedTurnCount == 0
        guard isOpeningTurnContext, !alreadyAwarded, points > 0 else { return }
        setAwarded()
        gLog(gameText("log.event.opening_bonus", ["player": player.name, "label": label, "points": points]))
        updateScoreAndEmitScoreEvents(for: player)
    }

    func respondToCapture(selectedCard: Card) {
        guard let player = currentPlayer else { return }
        if externalControlMode {
            relayLocalMultiplayerAction(.respondToCapture(cardId: selectedCard.id))
        }
        let playedCard = pendingCapturePlayedCard
        let drawnCard = pendingCaptureDrawnCard
        
        gLog(
            gameText(
                "log.event.capture_choice",
                [
                    "player": player.name,
                    "type": selectedCard.type.rawValue,
                    "month": String(describing: selectedCard.month)
                ]
            )
        )

        let triggerCard = playedCard ?? drawnCard
        guard let trigger = triggerCard else {
            gLog(gameText("log.error.respond_capture_missing_trigger"))
            return
        }

        guard let rules = RuleLoader.shared.config else {
            endTurn()
            return
        }

        // Choice while resolving the play-phase capture.
        if playedCard != nil {
            let captured = [trigger, selectedCard]
            let capturedIds = Set(captured.map { $0.id })
            turnPlayPhaseCaptured = captured
            turnPlayPhaseResultingTable = tableCards.filter { !capturedIds.contains($0.id) }
            turnPlayPhaseCaptureCommitted = false
            turnDrawPhaseBaseTable = nil
            monthOwners.removeValue(forKey: selectedCard.month.rawValue)

            pendingCapturePlayedCard = nil
            pendingCaptureDrawnCard = nil
            pendingCaptureOptions = []
            gameState = .playing

            gLog(gameText("log.event.capture_locked", ["player": player.name, "count": captured.count]))
            continueAfterPlayPhaseCapture(player: player, rules: rules)
            return
        }

        // Choice while resolving the draw-phase capture.
        let captured = [trigger, selectedCard]
        turnDrawPhaseCaptured = captured

        let baseTable = turnDrawPhaseBaseTable ?? (turnPlayPhaseResultingTable ?? tableCards.filter { $0.id != trigger.id })
        var resultingTable = baseTable
        if let idx = resultingTable.firstIndex(where: { $0.id == selectedCard.id }) {
            resultingTable.remove(at: idx)
        } else {
            gLog(gameText("log.error.draw_choice_card_missing"))
        }
        turnDrawPhaseBaseTable = nil

        handleDrawCaptured(drawnCard: trigger, player: player)

        pendingCapturePlayedCard = nil
        pendingCaptureDrawnCard = nil
        pendingCaptureOptions = []
        gameState = .playing

        gLog(gameText("log.event.capture_finalized", ["player": player.name, "count": captured.count]))

        let commit: () -> Void = {
            self.commitResolvedCapturesAndFinalize(
                player: player,
                rules: rules,
                finalTable: resultingTable,
                drawnCard: trigger
            )
        }
        let matchPause = AnimationManager.shared.config.match_pause_duration
        if matchPause > 0 {
            runAfterAnimationDelay(matchPause) {
                commit()
            }
        } else {
            commit()
        }
    }

    private func animateTableToCaptured(
        cards captured: [Card],
        player: Player,
        completion: @escaping () -> Void
    ) {
        guard !captured.isEmpty else {
            completion()
            return
        }

        let movePlan = AnimationManager.shared.motionPlan(source: "table", target: "captured")
        let moveDelay = movePlan.delay
        let capturedIds = Set(captured.map { $0.id })
        let filtered = captured.filter { !($0.month == .sep && $0.type == .animal) }
        let filteredIds = Set(filtered.map { $0.id })

        currentMovingCards = []
        movingCardsPiCount = nil
        movingCardsShowDebug = false
        penaltyMoveProgress = 0
        for c in captured {
            hiddenInSourceCardIds.remove(c.id)
            hiddenInTargetCardIds.remove(c.id)
        }
        // Hide source+target during overlay flight so trajectory is driven only by movingCardOverlay.
        for c in filtered {
            hiddenInSourceCardIds.insert(c.id)
            hiddenInTargetCardIds.insert(c.id)
        }

        if filtered.isEmpty {
            if let moveAnimation = movePlan.animation {
                withAnimation(moveAnimation) {
                    tableCards.removeAll { capturedIds.contains($0.id) }
                }
            } else {
                tableCards.removeAll { capturedIds.contains($0.id) }
            }
            runAfterAnimationDelay(moveDelay) {
                completion()
            }
            return
        }

        let targetPlayerId = player.id.uuidString
        setMoveContext(
            source: "table",
            target: "captured",
            capturedTargetPlayerId: targetPlayerId
        )
        if !filtered.isEmpty {
            // Mount target hidden under the correct move context so it never flashes visible.
            let cardIds = filtered.map { $0.id }
            self.hiddenInSourceCardIds.formUnion(cardIds)
            self.hiddenInTargetCardIds.formUnion(cardIds)

            player.capture(cards: filtered)
            updateScoreAndEmitScoreEvents(for: player)
        }
        currentMovingCards = filtered
        movingCardsScale = 0.86
        movingCardsPiCount = nil
        movingCardsShowDebug = false
        showSourceCue(for: filtered, holdBeforeMove: false)
        let cardIds = filtered.map { $0.id }.joined(separator: ",")
        addUXEvent(
            type: "moveStart",
            data: [
                "cardIds": cardIds,
                "source": "table",
                "target": "captured",
                "targetPlayerId": targetPlayerId
            ]
        )
        takeSnapshot()

        let runMove: () -> Void = {
            self.penaltyMoveProgress = 1
        }

        if let moveAnimation = movePlan.animation {
            withAnimation(moveAnimation) {
                runMove()
            }
        } else {
            runMove()
        }

        runAfterAnimationDelay(moveDelay) {
            self.tableCards.removeAll { capturedIds.contains($0.id) }
            let cardIds = filtered.map { $0.id }.joined(separator: ",")
            self.addUXEvent(
                type: "moveEnd",
                data: [
                    "cardIds": cardIds,
                    "target": "captured",
                    "targetPlayerId": targetPlayerId
                ]
            )
            self.hiddenInSourceCardIds.subtract(filteredIds)
            self.hiddenInTargetCardIds.subtract(filteredIds)
            self.currentMovingCards = []
            self.penaltyMoveProgress = 0
            let captureCueHold = self.capturedTargetCueDuration
            self.showTargetCue(for: filtered, durationOverride: captureCueHold)
            self.movingCardsPiCount = nil
            self.clearMoveContextAfterCue(
                expectedSource: "table",
                expectedTarget: "captured",
                expectedCapturedTargetPlayerId: targetPlayerId,
                delayOverride: captureCueHold
            )
            completion()
        }
    }

    private func commitResolvedCapturesAndFinalize(
        player: Player,
        rules: RuleConfig,
        finalTable: [Card],
        drawnCard: Card?
    ) {
        let playCaptured = turnPlayPhaseCaptureCommitted ? [] : turnPlayPhaseCaptured
        let drawCaptured = turnDrawPhaseCaptured

        currentMovingCards = []
        penaltyMoveProgress = 0
        if let drawnCard {
            hiddenInSourceCardIds.remove(drawnCard.id)
            hiddenInTargetCardIds.remove(drawnCard.id)
        }
        clearMoveContext()

        animateTableToCaptured(cards: playCaptured, player: player) {
            self.animateTableToCaptured(cards: drawCaptured, player: player) {
                self.tableCards = finalTable
                self.turnPlayPhaseResultingTable = nil
                self.turnPlayPhaseCaptureCommitted = false
                self.turnDrawPhaseBaseTable = nil
                self.finalizeTurnState(player: player, rules: rules)
            }
        }
    }

    private func continueAfterPlayPhaseCapture(player: Player, rules: RuleConfig) {
        let animateCapture: () -> Void = {
            self.animateTableToCaptured(cards: self.turnPlayPhaseCaptured, player: player) {
                self.turnPlayPhaseCaptureCommitted = true
                self.proceedToDrawPhase(player: player, rules: rules)
            }
        }

        let matchPause = AnimationManager.shared.config.match_pause_duration
        if matchPause > 0 {
            runAfterAnimationDelay(matchPause) {
                animateCapture()
            }
        } else {
            animateCapture()
        }
    }

    func playTurn(card: Card) {
        guard !externalControlMode || isLocalTurn else {
            gLog(gameText("log.event.playturn_blocked_not_your_turn"))
            return
        }
        guard let rules = RuleLoader.shared.config else {
            gLog(gameText("log.event.playturn_blocked_rules_nil"))
            return
        }
        guard gameState == .playing else {
            gLog(gameText("log.event.playturn_blocked_game_state", ["state": gameState.rawValue]))
            return
        }
        guard !isAutomationBusy else {
            gLog(
                gameText(
                    "log.event.playturn_blocked_busy",
                    [
                        "pendingDelays": pendingAutomationDelays,
                        "movingCards": currentMovingCards.count,
                        "hiddenSrc": hiddenInSourceCardIds.count,
                        "hiddenTgt": hiddenInTargetCardIds.count
                    ]
                )
            )
            return
        }
        guard let player = currentPlayer else {
            gLog(gameText("log.event.playturn_blocked_no_player"))
            return
        }

        // Notify multiplayer coordinator of the local action
        relayLocalMultiplayerAction(.playCard(cardId: card.id))


        self.uxEventLogs.removeAll() // Clear stale logs from previous turn

        // Mid-game shake check (bomb takes priority).
        if card.type != .dummy, rules.special_moves.shake.enabled {
            let sameMonthCount = player.hand.filter { $0.month == card.month }.count
            let tableMatchCount = tableCards.filter { $0.month == card.month }.count
            let alreadyShaken = player.shakenMonths.contains(card.month.rawValue)
            let isBombCondition = rules.special_moves.bomb.enabled && sameMonthCount >= 3 && tableMatchCount == 1

            if sameMonthCount >= 3 && !alreadyShaken && !isBombCondition {
                pendingShakeCard = card
                pendingShakeMonth = card.month.rawValue
                pendingShakeMonths = [card.month.rawValue]
                gameState = .askingShake
                gLog(gameText("log.event.can_shake", ["player": player.name, "month": String(describing: card.month)]))
                maybeScheduleInternalComputerAction()
                return
            }
        }
        
        // Reset turn state
        turnIsBomb = false
        turnIsTtadak = false
        turnIsJjok = false
        turnIsSeolsa = false
        isSeolsaEatFlag = false
        isSelfSeolsaEatFlag = false
        turnPlayPhaseCaptured = []
        turnDrawPhaseCaptured = []
        turnPlayedCard = nil
        turnTableWasNotEmpty = !tableCards.isEmpty
        turnWasOpeningTurn = completedTurnCount == 0
        turnPlayPhaseResultingTable = nil
        turnPlayPhaseCaptureCommitted = false
        turnDrawPhaseBaseTable = nil
        
        // Phase 1: Hand Play
        if card.type == .dummy {
            gLog(gameText("log.event.played_dummy", ["player": player.name]))
            player.dummyCardCount -= 1
            if let idx = player.hand.firstIndex(where: { $0.id == card.id }) {
                player.hand.remove(at: idx)
            }
            // Dummy cards vanish on play, but the turn still continues with deck draw/capture.
            proceedToDrawPhase(player: player, rules: rules)
        } else {
            // Check for Bomb/Shake first
            let month = card.month
            let handMatches = player.hand.filter { $0.month == month }
            let tableMatches = tableCards.filter { $0.month == month }
            
            if rules.special_moves.bomb.enabled, handMatches.count == 3, tableMatches.count == 1 {
                handleBombPlay(player: player, month: month, handMatches: handMatches, tableMatches: tableMatches, rules: rules)
            } else {
                if let idx = player.hand.firstIndex(where: { $0.id == card.id }),
                   let pCard = player.play(card: card) {
                    turnPlayedCard = pCard
                    
                    // We also keep it in Hand virtually (hidden) so matchedGeometryEffect has a source
                    // Important: Insert back at SAME index to avoid layout jump
                    player.hand.insert(pCard, at: idx)
                    let handToTableMotion = AnimationManager.shared.motionPlan(source: "hand", target: "table")
                    let finalizeHandToTable: () -> Void = {
                        self.runAfterAnimationDelay(handToTableMotion.delay) {
                            
                            // Check capture logically
                            self.addUXEvent(type: "moveEnd", data: ["cardId": pCard.id, "target": "table"])
                            let captureResolution = self.performTableCaptureLogical(for: pCard, player: player)
                            let isMatchAtTable: Bool = {
                                guard let captureResolution = captureResolution else { return true }
                                return !captureResolution.captured.isEmpty
                            }()
                            self.showTargetCue(for: [pCard], tableImpactMatched: isMatchAtTable)

                            if let captureResolution = captureResolution {
                                let captured = captureResolution.captured
                                let resultingTable = captureResolution.resultingTable
                                self.turnPlayPhaseCaptured = captured
                                self.turnPlayPhaseCaptureCommitted = false
                                self.hiddenInTargetCardIds.remove(pCard.id)
                                self.clearMoveContextAfterCue(expectedSource: "hand", expectedTarget: "table")
                                
                                if captured.isEmpty {
                                    self.tableCards = resultingTable
                                    // Just staying on table
                                    self.monthOwners[pCard.month.rawValue] = player
                                    self.proceedToDrawPhase(player: player, rules: rules)
                                } else {
                                    self.turnPlayPhaseResultingTable = resultingTable
                                    self.monthOwners.removeValue(forKey: pCard.month.rawValue)
                                    self.continueAfterPlayPhaseCapture(player: player, rules: rules)
                                }
                            } else {
                                // Choice needed
                                self.hiddenInTargetCardIds.remove(pCard.id)
                                self.clearMoveContextAfterCue(expectedSource: "hand", expectedTarget: "table")
                                
                                let options = self.tableCards.filter { $0.month == pCard.month && $0.id != pCard.id }
                                self.pendingCapturePlayedCard = pCard
                                self.pendingCaptureOptions = options
                                self.gameState = .choosingCapture
                                self.maybeScheduleInternalComputerAction()
                            }
                        }
                    }
                    
                    let startHandToTableMove: () -> Void = {
                        if let moveAnimation = handToTableMotion.animation {
                            // Animated mode: mount hidden target first for matched-geometry transition.
                            self.tableCards.append(pCard)
                            self.hiddenInTargetCardIds.insert(pCard.id) // Target is Table
                            self.setMoveContext(source: "hand", target: "table")
                            self.showSourceCue(for: [pCard], holdBeforeMove: false)
                            
                            self.addUXEvent(type: "moveStart", data: ["cardId": pCard.id, "source": "hand", "target": "table"])
                            self.takeSnapshot()
                            
                            withAnimation(moveAnimation) {
                                player.hand.removeAll { $0.id == pCard.id }
                            }
                            finalizeHandToTable()
                        } else {
                            // Instant mode: briefly cue selected card before instant relocation.
                            self.setMoveContext(source: "hand", target: "table")
                            self.showSourceCue(for: [pCard], holdBeforeMove: true) {
                                player.hand.removeAll { $0.id == pCard.id }
                                self.tableCards.append(pCard)
                                self.addUXEvent(type: "moveStart", data: ["cardId": pCard.id, "source": "hand", "target": "table"])
                                self.takeSnapshot()
                                finalizeHandToTable()
                            }
                        }
                    }
                    
                    // Briefly reveal the opponent's selected card before throw for readability.
                    let revealDelay = player.isComputer ? AnimationManager.shared.config.opponent_preplay_reveal_duration : 0
                    self.opponentPreplayRevealCardId = player.isComputer ? pCard.id : nil
                    if revealDelay > 0 {
                        self.runAfterAnimationDelay(revealDelay) {
                            self.opponentPreplayRevealCardId = nil
                            startHandToTableMove()
                        }
                    } else {
                        self.opponentPreplayRevealCardId = nil
                        startHandToTableMove()
                    }
                }
            }
        }
    }

    private func handleBombPlay(player: Player, month: Month, handMatches: [Card], tableMatches: [Card], rules: RuleConfig) {
        turnIsBomb = true
        gLog(gameText("log.event.bomb_triggered_upper", ["player": player.name]))
        guard let tableTarget = tableMatches.first else {
            gLog(gameText("log.error.bomb_missing_target"))
            proceedToDrawPhase(player: player, rules: rules)
            return
        }

        let bombHandCards = handMatches
        let bombHandCardIds = Set(bombHandCards.map { $0.id })
        let bombHandCardIdsJoined = bombHandCards.map { $0.id }.joined(separator: ",")
        let bombCapturedCards = bombHandCards + [tableTarget]
        turnPlayPhaseCaptured = bombCapturedCards
        turnPlayPhaseResultingTable = nil
        turnDrawPhaseBaseTable = nil
        monthOwners.removeValue(forKey: month.rawValue)
        seolsaMonths.removeValue(forKey: month.rawValue)
        invalidLastHandSeolsaMonths.remove(month.rawValue)

        player.bombCount += 1
        // Rule: Bomb counts as a shake event for multiplier tracking via shakeCount.
        player.shakeCount += 1
        
        for _ in 0..<rules.special_moves.bomb.dummy_card_count {
            let dummy = Card(month: .none, type: .dummy, imageIndex: 0)
            player.hand.append(dummy)
            player.dummyCardCount += 1
        }

        let handToTableMotion = AnimationManager.shared.motionPlan(source: "hand", target: "table")

        let finalizeBombHandToTable: () -> Void = {
            self.runAfterAnimationDelay(handToTableMotion.delay) {
                self.addUXEvent(
                    type: "moveEnd",
                    data: [
                        "cardIds": bombHandCardIdsJoined,
                        "target": "table"
                    ]
                )
                self.hiddenInTargetCardIds.subtract(bombHandCardIds)
                self.showTargetCue(for: bombHandCards, tableImpactMatched: true)
                self.clearMoveContextAfterCue(expectedSource: "hand", expectedTarget: "table")

                let animateBombCapture: () -> Void = {
                    self.animateTableToCaptured(cards: bombCapturedCards, player: player) {
                        // Bomb play captures are already committed through animated table->captured path.
                        // Keep only deferred special cards (e.g. Chrysanthemum) for end-of-turn choice flow.
                        self.turnPlayPhaseCaptured = bombCapturedCards.filter { $0.month == .sep && $0.type == .animal }
                        self.proceedToDrawPhase(player: player, rules: rules)
                    }
                }

                let matchPause = AnimationManager.shared.config.match_pause_duration
                if matchPause > 0 {
                    self.runAfterAnimationDelay(matchPause) {
                        animateBombCapture()
                    }
                } else {
                    animateBombCapture()
                }
            }
        }

        let startBombHandToTableMove: () -> Void = {
            if let moveAnimation = handToTableMotion.animation {
                // Animated mode: mount hidden target cards first for matched-geometry transition.
                for bombCard in bombHandCards where !self.tableCards.contains(where: { $0.id == bombCard.id }) {
                    self.tableCards.append(bombCard)
                }
                self.hiddenInTargetCardIds.formUnion(bombHandCardIds)
                self.setMoveContext(source: "hand", target: "table")
                self.showSourceCue(for: bombHandCards, holdBeforeMove: false)

                self.addUXEvent(
                    type: "moveStart",
                    data: [
                        "cardIds": bombHandCardIdsJoined,
                        "source": "hand",
                        "target": "table"
                    ]
                )
                self.takeSnapshot()

                withAnimation(moveAnimation) {
                    player.hand.removeAll { bombHandCardIds.contains($0.id) }
                }
                finalizeBombHandToTable()
            } else {
                // Instant mode: briefly cue selected cards before instant relocation.
                self.setMoveContext(source: "hand", target: "table")
                self.showSourceCue(for: bombHandCards, holdBeforeMove: true) {
                    player.hand.removeAll { bombHandCardIds.contains($0.id) }
                    for bombCard in bombHandCards where !self.tableCards.contains(where: { $0.id == bombCard.id }) {
                        self.tableCards.append(bombCard)
                    }
                    self.addUXEvent(
                        type: "moveStart",
                        data: [
                            "cardIds": bombHandCardIdsJoined,
                            "source": "hand",
                            "target": "table"
                        ]
                    )
                    self.takeSnapshot()
                    finalizeBombHandToTable()
                }
            }
        }

        // Briefly reveal one of opponent's bomb cards before throw for readability.
        let revealDelay = player.isComputer ? AnimationManager.shared.config.opponent_preplay_reveal_duration : 0
        self.opponentPreplayRevealCardId = player.isComputer ? bombHandCards.first?.id : nil
        if revealDelay > 0 {
            self.runAfterAnimationDelay(revealDelay) {
                self.opponentPreplayRevealCardId = nil
                startBombHandToTableMove()
            }
        } else {
            self.opponentPreplayRevealCardId = nil
            startBombHandToTableMove()
        }
    }

    private func proceedToDrawPhase(player: Player, rules: RuleConfig) {
        let drawDelay = AnimationManager.shared.config.card_move_duration
        runAfterAnimationDelay(drawDelay) {
            let logicalTableBeforeDraw = self.turnPlayPhaseResultingTable ?? self.tableCards
            guard let drawnCard = self.deck.draw() else {
                let finalTable = self.turnPlayPhaseResultingTable ?? self.tableCards
                if !self.turnPlayPhaseCaptured.isEmpty {
                    self.commitResolvedCapturesAndFinalize(
                        player: player,
                        rules: rules,
                        finalTable: finalTable,
                        drawnCard: nil
                    )
                } else {
                    self.turnPlayPhaseResultingTable = nil
                    self.turnDrawPhaseBaseTable = nil
                    self.tableCards = finalTable
                    self.finalizeTurnState(player: player, rules: rules)
                }
                return
            }

            gLog(
                gameText(
                    "log.event.drawn_card",
                    [
                        "month": String(describing: drawnCard.month),
                        "type": drawnCard.type.rawValue
                    ]
                )
            )

            self.tableCards.append(drawnCard)
            self.deck.pushCardsOnTop([drawnCard])
            let deckToTableMotion = AnimationManager.shared.motionPlan(source: "deck", target: "table")
            self.hiddenInTargetCardIds.insert(drawnCard.id)
            self.setMoveContext(source: "deck", target: "table")

            let finalizeDeckToTable: () -> Void = {
                self.runAfterAnimationDelay(deckToTableMotion.delay) {
                    self.addUXEvent(type: "moveEnd", data: ["cardId": drawnCard.id, "target": "table"])
                    self.currentMovingCards = []
                    self.penaltyMoveProgress = 0
                    self.hiddenInSourceCardIds.remove(drawnCard.id)
                    self.hiddenInTargetCardIds.remove(drawnCard.id)
                    self.clearMoveContextAfterCue(expectedSource: "deck", expectedTarget: "table")

                    let sameMonthInLogicalTable = logicalTableBeforeDraw.filter { $0.month == drawnCard.month }
                    let isSeolsa = self.turnPlayPhaseCaptured.count == 2 &&
                        self.turnPlayPhaseCaptured[0].month == drawnCard.month &&
                        sameMonthInLogicalTable.isEmpty

                    if isSeolsa {
                        let invalidOnLastHand = rules.special_moves.seolsa.invalid_on_last_hand ?? true
                        self.showTargetCue(for: [drawnCard], tableImpactMatched: false)
                        self.turnIsSeolsa = true
                        if invalidOnLastHand && player.hand.isEmpty {
                            gLog(
                                gameText(
                                    "log.event.seolsa_last_hand_ignored",
                                    ["player": player.name, "month": drawnCard.month.rawValue]
                                )
                            )
                        } else {
                            gLog(gameText("log.event.seolsa_marker"))
                        }
                        self.turnPlayPhaseCaptured = []
                        self.turnDrawPhaseCaptured = []
                        self.turnPlayPhaseResultingTable = nil
                        self.turnDrawPhaseBaseTable = nil
                        self.finalizeTurnState(player: player, rules: rules)
                        return
                    }

                    var drawLogicalTable = logicalTableBeforeDraw
                    let drawCapture = self.performTableCapture(for: drawnCard, on: &drawLogicalTable, player: player)
                    let isMatchAtTable: Bool = {
                        guard let drawCapture = drawCapture else { return true }
                        return !drawCapture.isEmpty
                    }()
                    self.showTargetCue(for: [drawnCard], tableImpactMatched: isMatchAtTable)

                    if let captured = drawCapture {
                        self.turnDrawPhaseCaptured = captured
                        self.handleDrawCaptured(drawnCard: drawnCard, player: player)
                        self.turnDrawPhaseBaseTable = nil

                        let finalTable = drawLogicalTable
                        let commit: () -> Void = {
                            self.commitResolvedCapturesAndFinalize(
                                player: player,
                                rules: rules,
                                finalTable: finalTable,
                                drawnCard: drawnCard
                            )
                        }

                        let hasAnyCapture = !self.turnPlayPhaseCaptured.isEmpty || !captured.isEmpty
                        let matchPause = AnimationManager.shared.config.match_pause_duration
                        if hasAnyCapture && matchPause > 0 {
                            self.runAfterAnimationDelay(matchPause) {
                                commit()
                            }
                        } else {
                            commit()
                        }
                    } else {
                        // Draw capture needs user selection. Keep draw card visible and wait for choice.
                        self.turnDrawPhaseBaseTable = drawLogicalTable
                        self.pendingCaptureDrawnCard = drawnCard
                        self.pendingCaptureOptions = drawLogicalTable.filter { $0.month == drawnCard.month }
                        self.gameState = .choosingCapture
                        self.updateScoreAndEmitScoreEvents(for: player)
                        self.maybeScheduleInternalComputerAction()
                    }
                }
            }

            let startDeckToTableMove: () -> Void = {
                self.hiddenInSourceCardIds.insert(drawnCard.id)
                self.addUXEvent(type: "moveStart", data: ["cardId": drawnCard.id, "source": "deck", "target": "table"])
                self.takeSnapshot()

                self.movingCardsScale = 0.7
                self.movingCardsShowDebug = false
                self.currentMovingCards = [drawnCard]

                if let moveAnimation = deckToTableMotion.animation {
                    withAnimation(moveAnimation) {
                        self.deck.remove(card: drawnCard)
                    }
                } else {
                    self.deck.remove(card: drawnCard)
                }
                finalizeDeckToTable()
            }

            if deckToTableMotion.animation == nil {
                self.showSourceCue(for: [drawnCard], holdBeforeMove: true) {
                    startDeckToTableMove()
                }
            } else {
                self.showSourceCue(for: [drawnCard], holdBeforeMove: false)
                startDeckToTableMove()
            }
        }
    }

    private func handleDrawCaptured(drawnCard: Card, player: Player) {
        if !turnDrawPhaseCaptured.isEmpty {
            if let pCard = turnPlayedCard, turnDrawPhaseCaptured.contains(where: { $0.month == pCard.month }) {
                if !turnPlayPhaseCaptured.isEmpty { turnIsTtadak = true } 
                else { turnIsJjok = true }
            }
            for captured in turnDrawPhaseCaptured {
                monthOwners.removeValue(forKey: captured.month.rawValue)
                seolsaMonths.removeValue(forKey: captured.month.rawValue)
                invalidLastHandSeolsaMonths.remove(captured.month.rawValue)
            }
        } else {
            monthOwners[drawnCard.month.rawValue] = player
        }
    }

    private func finalizeTurnState(player: Player, rules: RuleConfig) {
        let finalCaptures = turnPlayPhaseCaptured + turnDrawPhaseCaptured
        if !finalCaptures.isEmpty {
            // Note: Capture and score already handled in phased animations
            if checkAndHandleChrysanthemumRole(capturedCards: finalCaptures, player: player, rules: rules) {
                return
            }
        }
        finalizeTurnAfterCapture(player: player)
    }

    private func checkAndHandleChrysanthemumRole(capturedCards: [Card], player: Player, rules: RuleConfig) -> Bool {
        let chrysRule = rules.cards.chrysanthemum_rule
        if chrysRule.enabled, chrysRule.choice_timing == "capture_time" {
            if let chrysCard = capturedCards.first(where: { $0.month == .sep && $0.type == .animal }) {
                if player.isComputer {
                    let defaultRole = CardRole(rawValue: chrysRule.default_role) ?? .animal
                    var updatedCard = chrysCard
                    updatedCard.selectedRole = defaultRole
                    player.capture(cards: [updatedCard])
                    updateScoreAndEmitScoreEvents(for: player)
                } else {
                    pendingChrysanthemumCard = chrysCard
                    gameState = .choosingChrysanthemumRole
                    return true
                }
            }
        }
        return false
    }

    func respondToGoStop(isGo: Bool) {
        guard gameState == .askingGoStop, let player = currentPlayer else { return }
        if externalControlMode {
            relayLocalMultiplayerAction(.respondToGoStop(isGo: isGo))
        }
        guard let rules = RuleLoader.shared.config else {
            fallbackEndTurn(player: player)
            return
        }
        
        if isGo {
            player.goCount += 1
            player.lastGoScore = player.score
            gLog(gameText("log.event.go_called", ["player": player.name, "count": player.goCount]))
            let opponentIndex = (currentTurnIndex + 1) % players.count
            let opponent = players[opponentIndex]
            gameState = .playing
            if checkEndgameConditions(player: player, opponent: opponent, rules: rules, isAfterGo: true) { return }
            endTurn()
        } else {
            let opponentIndex = (currentTurnIndex + 1) % players.count
            let opponent = players[opponentIndex]
            if isScoreClaimBlocked(winner: player, loser: opponent, rules: rules) {
                gLog(
                    gameText(
                        "log.event.stop_blocked",
                        ["player": player.name, "score": player.score, "opponent": opponent.name]
                    )
                )
                gameState = .playing
                endTurn()
                return
            }
            executeStop(player: player, rules: rules)
        }
    }
    
    private func executeStop(player: Player, rules: RuleConfig, reason: GameEndReason = .stop) {
        let opponentIndex = (currentTurnIndex + 1) % players.count
        let opponent = players[opponentIndex]
        resolveBakPiTransfers(winner: player, loser: opponent, rules: rules)
        updateScoreAndEmitScoreEvents(for: player)
        updateScoreAndEmitScoreEvents(for: opponent)
        let result = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        gLog(
            gameText(
                "log.event.stop_called",
                [
                    "player": player.name,
                    "reason": gameEndReasonText(reason),
                    "score": result.finalScore
                ]
            )
        )
        opponent.money -= result.finalScore * 100
        player.money += result.finalScore * 100
        recordWinScore(points: result.finalScore, for: player)
        self.gameEndReason = reason
        self.lastPenaltyResult = result
        self.gameWinner = player
        self.gameLoser = opponent
        settleResidualCardsIfHandsEmpty()
        gameState = .ended
    }

    private func resolveThreeSeolsaWin(player: Player, opponent: Player, requiredCount: Int, score: Int) {
        let winScore = max(score, 0)
        player.score = winScore
        updateScoreAndEmitScoreEvents(for: opponent)

        opponent.money -= winScore * 100
        player.money += winScore * 100
        recordWinScore(points: winScore, for: player)

        self.gameEndReason = .threeSeolsa
        self.lastPenaltyResult = PenaltySystem.PenaltyResult(
            finalScore: winScore,
            isGwangbak: false,
            isPibak: false,
            isGobak: false,
            isMungbak: false,
            isJabak: false,
            isYeokbak: false,
            scoreFormula: gameText(
                "penalty.formula.three_seolsa_rule",
                ["count": requiredCount, "score": winScore]
            )
        )
        self.gameWinner = player
        self.gameLoser = opponent
        settleResidualCardsIfHandsEmpty()
        gameState = .ended
    }
    
    private func fallbackEndTurn(player: Player) {
        if player.score >= 7 {
            recordWinScore(points: player.score, for: player)
            self.gameEndReason = .stop
            self.gameWinner = player
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
        } else {
            endTurn()
        }
    }
    
    private func endTurn() {
        completedTurnCount += 1
        turnWasOpeningTurn = false
        let allHandsEmpty = players.allSatisfy { $0.hand.isEmpty }
        if deck.cards.isEmpty || allHandsEmpty {
            self.gameEndReason = .nagari
            self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                finalScore: 0, isGwangbak: false, isPibak: false, isGobak: false,
                isMungbak: false, isJabak: false, isYeokbak: false, scoreFormula: gameText("penalty.formula.nagari")
            )
            self.gameWinner = nil
            self.gameLoser = nil
            settleResidualCardsIfHandsEmpty()
            gameState = .ended
            gLog(gameText("log.event.nagari_ended"))
            return
        }
        currentTurnIndex = (currentTurnIndex + 1) % players.count
        if gameState == .playing {
            var skips = 0
            while let player = currentPlayer, player.hand.isEmpty, skips < players.count {
                gLog(gameText("log.event.skip_empty_hand_turn", ["player": player.name]))
                currentTurnIndex = (currentTurnIndex + 1) % players.count
                skips += 1
            }
            if players.allSatisfy({ $0.hand.isEmpty }) {
                self.gameEndReason = .nagari
                self.lastPenaltyResult = PenaltySystem.PenaltyResult(
                    finalScore: 0, isGwangbak: false, isPibak: false, isGobak: false,
                    isMungbak: false, isJabak: false, isYeokbak: false, scoreFormula: gameText("penalty.formula.nagari")
                )
                self.gameWinner = nil
                self.gameLoser = nil
                settleResidualCardsIfHandsEmpty()
                gameState = .ended
                gLog(gameText("log.event.nagari_hand_empty"))
                return
            }
        }
        maybeScheduleInternalComputerAction()
    }
    
    func checkEndgameConditions(player: Player, opponent: Player, rules: RuleConfig, isAfterGo: Bool) -> Bool {
        let endgame = rules.endgame
        let bak = PenaltySystem.calculatePenalties(winner: player, loser: opponent, rules: rules)
        let seolsaRule = rules.special_moves.seolsa
        let scoreClaimBlocked = isScoreClaimBlocked(winner: player, loser: opponent, rules: rules)

        // 0. Triple Seolsa (3뻑) Instant Win
        let seolsaInstantWinCount = seolsaRule.instant_win_count ?? 0
        if seolsaRule.enabled, seolsaInstantWinCount > 0, player.seolsaCount >= seolsaInstantWinCount {
            let seolsaInstantWinScore = seolsaRule.instant_win_score ?? 10
            gLog(
                gameText(
                    "log.event.triple_seolsa",
                    [
                        "player": player.name,
                        "count": player.seolsaCount,
                        "score": seolsaInstantWinScore
                    ]
                )
            )
            resolveThreeSeolsaWin(
                player: player,
                opponent: opponent,
                requiredCount: seolsaInstantWinCount,
                score: seolsaInstantWinScore
            )
            return true
        }

        // 1. Instant End on Bak Check if enabled
        let instantEnd = endgame.instant_end_on_bak
        if (instantEnd.pibak && bak.isPibak) || 
           (instantEnd.gwangbak && bak.isGwangbak) || 
           (instantEnd.mungbak && bak.isMungbak) {
            if scoreClaimBlocked {
                gLog(gameText("log.event.instant_bak_blocked", ["opponent": opponent.name]))
                return false
            }
            gLog(gameText("log.event.instant_bak_met"))
            executeStop(player: player, rules: rules)
            return true
        }

        // 2. Max Score Check (pre/post multiplier based on rule)
        let scoreForThreshold = (endgame.score_check_timing == "post_multiplier") ? bak.finalScore : player.score
        if scoreForThreshold >= endgame.max_round_score {
            if scoreClaimBlocked {
                gLog(gameText("log.event.max_score_blocked", ["player": player.name, "opponent": opponent.name]))
                return false
            }
            gLog(
                gameText(
                    "log.event.max_score_reached",
                    ["player": player.name, "maxScore": endgame.max_round_score, "score": scoreForThreshold]
                )
            )
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }

        // 3. Max Go Count
        if player.goCount >= endgame.max_go_count {
            if scoreClaimBlocked {
                gLog(gameText("log.event.max_go_blocked", ["player": player.name, "opponent": opponent.name]))
                return false
            }
            gLog(gameText("log.event.max_go_reached", ["player": player.name, "maxGoCount": endgame.max_go_count]))
            executeStop(player: player, rules: rules, reason: .maxScore)
            return true
        }
        
        return false
    }

    private func isScoreClaimBlocked(winner: Player, loser: Player, rules: RuleConfig) -> Bool {
        guard rules.go_stop.require_opponent_capture_for_scoring else { return false }
        guard winner.score > 0 else { return false }
        return !loser.hasCapturedThisRound
    }

    private func resolveBakPiTransfers(winner: Player, loser: Player, rules: RuleConfig) {
        let stopWin = winner.goCount == 0
        let applyBakBecauseStop = rules.go_stop.apply_bak_on_stop || !stopWin
        let applyBakBecauseOpponentGo = !rules.go_stop.bak_only_if_opponent_go || loser.goCount > 0

        guard applyBakBecauseStop && applyBakBecauseOpponentGo else { return }

        // Gwangbak Pi Transfer
        if rules.penalties.gwangbak.enabled {
            let winnerKwangs = winner.capturedCards.filter { $0.type == .bright }.count
            let loserKwangs = loser.capturedCards.filter { $0.type == .bright }.count
            if winnerKwangs >= 3 && loserKwangs <= rules.penalties.gwangbak.opponent_max_kwang {
                if rules.penalties.gwangbak.resolution_type == "pi_transfer" || rules.penalties.gwangbak.resolution_type == "both" {
                    let count = rules.penalties.gwangbak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: gameText("log.reason.gwangbak_transfer"))
                }
            }
        }
        
        // Pibak Pi Transfer
        if rules.penalties.pibak.enabled {
            let winnerPi = ScoringSystem.calculatePiCount(cards: winner.capturedCards, rules: rules)
            let loserPi = ScoringSystem.calculatePiCount(cards: loser.capturedCards, rules: rules)
            if winnerPi >= 10 && loserPi > 0 && loserPi < rules.penalties.pibak.opponent_min_pi_safe {
                if rules.penalties.pibak.resolution_type == "pi_transfer" || rules.penalties.pibak.resolution_type == "both" {
                    let count = rules.penalties.pibak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: gameText("log.reason.pibak_transfer"))
                }
            }
        }

        // Mungbak Pi Transfer
        if rules.penalties.mungbak.enabled {
            let winnerAnimals = winner.capturedCards.filter { $0.type == .animal }.count
            if winnerAnimals >= rules.penalties.mungbak.winner_min_animal {
                if rules.penalties.mungbak.resolution_type == "pi_transfer" || rules.penalties.mungbak.resolution_type == "both" {
                    let count = rules.penalties.mungbak.pi_to_transfer
                    stealPi(from: loser, to: winner, count: count, reason: gameText("log.reason.mungbak_transfer"))
                }
            }
        }
    }
    
    private struct TableCaptureResolution {
        let captured: [Card]
        let resultingTable: [Card]
    }

    private func performTableCaptureLogical(for monthCard: Card, player: Player) -> TableCaptureResolution? {
        var tableCopy = self.tableCards
        // The card is already in the table for animation targeting. 
        // Remove it from the logic copy to let performTableCapture decide where it really goes.
        tableCopy.removeAll { $0.id == monthCard.id }
        
        if let captured = performTableCapture(for: monthCard, on: &tableCopy, player: player) {
            return TableCaptureResolution(captured: captured, resultingTable: tableCopy)
        }
        return nil
    }
    
    func maybeScheduleInternalComputerAction_ExternalWorkaround() {
        self.maybeScheduleInternalComputerAction()
    }
    
    func emergencyResetBusyState() {
        self.automationDelayGeneration += 1
        self.pendingAutomationDelays = 0
        self.currentMovingCards = []
        self.penaltyMoveProgress = 0
        self.sourceCueCardIds = []
        self.targetCueCardIds = []
        self.hiddenInSourceCardIds = []
        self.hiddenInTargetCardIds = []
        self.clearMoveContext()
        self.opponentPreplayRevealCardId = nil
        self.internalComputerActionScheduled = false
        self.uxEventLogs.removeAll()
        gLog(gameText("log.event.emergency_busy_reset"))
    }

    private var moveCueDuration: Double {
        let base = AnimationManager.shared.config.match_pause_duration
        guard base > 0 else { return 0 }
        return max(0.08, min(0.14, base * 0.4))
    }

    private var capturedTargetCueDuration: Double {
        max(moveCueDuration, 0.20)
    }

    private func runCueDelay(_ delay: Double, generation: Int, _ block: @escaping () -> Void) {
        if delay <= 0 {
            block()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.automationDelayGeneration == generation else { return }
            block()
        }
    }

    private func showSourceCue(for cards: [Card], holdBeforeMove: Bool, completion: @escaping () -> Void = {}) {
        let ids = Set(cards.map { $0.id })
        guard !ids.isEmpty else {
            completion()
            return
        }
        let generation = automationDelayGeneration
        sourceCueCardIds.formUnion(ids)

        if holdBeforeMove {
            runCueDelay(moveCueDuration, generation: generation) { [weak self] in
                guard let self = self else { return }
                self.sourceCueCardIds.subtract(ids)
                completion()
            }
        } else {
            completion()
            runCueDelay(moveCueDuration, generation: generation) { [weak self] in
                self?.sourceCueCardIds.subtract(ids)
            }
        }
    }

    private func showTargetCue(for cards: [Card], durationOverride: Double? = nil, tableImpactMatched: Bool? = nil) {
        let ids = Set(cards.map { $0.id })
        guard !ids.isEmpty else { return }
        let shouldPlayTableImpactSound =
            currentMoveTargetZone == "table" &&
            (currentMoveSourceZone == "hand" || currentMoveSourceZone == "deck")
        if shouldPlayTableImpactSound {
            AudioManager.shared.playHwatuTableImpactEffect(isMatch: tableImpactMatched ?? true)
        }
        let generation = automationDelayGeneration
        let holdDuration = max(0, durationOverride ?? moveCueDuration)
        targetCueCardIds.formUnion(ids)
        runCueDelay(holdDuration, generation: generation) { [weak self] in
            self?.targetCueCardIds.subtract(ids)
        }
    }

    private func clearMoveContextAfterCue(
        expectedSource: String,
        expectedTarget: String,
        expectedCapturedSourcePlayerId: String? = nil,
        expectedCapturedTargetPlayerId: String? = nil,
        delayOverride: Double? = nil
    ) {
        let generation = automationDelayGeneration
        let holdDuration = max(0, delayOverride ?? moveCueDuration)
        runCueDelay(holdDuration, generation: generation) { [weak self] in
            guard let self = self else { return }
            guard self.currentMoveSourceZone == expectedSource,
                  self.currentMoveTargetZone == expectedTarget,
                  self.capturedMoveSourcePlayerId == expectedCapturedSourcePlayerId,
                  self.capturedMoveTargetPlayerId == expectedCapturedTargetPlayerId else { return }

            // If another motion has started, keep the latest context.
            guard self.currentMovingCards.isEmpty,
                  self.hiddenInSourceCardIds.isEmpty,
                  self.hiddenInTargetCardIds.isEmpty else { return }

            self.clearMoveContext()
        }
    }
    
    private func maybeScheduleInternalComputerAction() {
        guard internalComputerAutomationEnabled, !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        switch gameState {
        case .playing, .askingShake, .askingGoStop, .choosingCapture, .choosingChrysanthemumRole:
            break
        case .ready, .ended:
            return
        }
        
        guard !internalComputerActionScheduled else { return }
        internalComputerActionScheduled = true
        let generation = automationDelayGeneration
        
        let delay = AnimationManager.shared.config.opponent_action_delay
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.internalComputerActionScheduled = false
            guard self.automationDelayGeneration == generation else { return }
            self.performInternalComputerAction()
        }
    }
    
    func performInternalComputerAction() {
        guard internalComputerAutomationEnabled, !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        // For in-app autoplay, wait until the full matched-geometry animation state is idle.
        guard !isAutomationBusy else {
            maybeScheduleInternalComputerAction()
            return
        }
        
        self.performInternalComputerActionLogic()
    }
    
    func forceInternalComputerStep() {
        guard !externalControlMode else { return }
        guard let player = currentPlayer, player.isComputer else { return }
        
        // Skip automationBusy check? No, we still want to wait for animations to finish before starting a NEW turn step.
        guard !isAutomationBusy else { return }
        
        // Call the internal logic directly without the automation flag guard.
        self.performInternalComputerActionLogic()
    }
    
    private func performInternalComputerActionLogic() {
        guard let player = currentPlayer, player.isComputer else { return }
        
        switch gameState {
        case .playing:
            guard let card = chooseComputerPlayCard(from: player.hand) else { return }
            gLog(
                gameText(
                    "log.event.automation_play",
                    ["player": player.name, "month": card.month.rawValue, "type": card.type.rawValue]
                )
            )
            playTurn(card: card)
            
        case .askingShake:
            if let month = pendingShakeMonths.first ?? pendingShakeMonth {
                gLog(gameText("log.event.automation_decline_shake", ["month": month]))
                respondToShake(month: month, didShake: false)
            }
            
        case .askingGoStop:
            let shouldGo = player.goCount == 0 && player.hand.count > 1
            gLog(
                gameText(
                    "log.event.automation_go_stop",
                    ["decision": shouldGo ? gameText("common.button.go") : gameText("common.button.stop")]
                )
            )
            respondToGoStop(isGo: shouldGo)
            
        case .choosingCapture:
            if let selected = chooseComputerCaptureOption(from: pendingCaptureOptions) {
                gLog(
                    gameText(
                        "log.event.automation_select_capture",
                        ["month": selected.month.rawValue, "type": selected.type.rawValue]
                    )
                )
                respondToCapture(selectedCard: selected)
            }
            
        case .choosingChrysanthemumRole:
            let defaultRole = RuleLoader.shared.config
                .flatMap { CardRole(rawValue: $0.cards.chrysanthemum_rule.default_role) } ?? .animal
            gLog(gameText("log.event.automation_chrysanthemum_role", ["role": defaultRole.rawValue]))
            respondToChrysanthemumChoice(role: defaultRole)
            
        case .ready, .ended:
            break
        }
    }
    
    private func chooseComputerPlayCard(from hand: [Card]) -> Card? {
        guard !hand.isEmpty else { return nil }
        let tableMonths = Set(tableCards.map { $0.month.rawValue })
        
        if let matching = hand.first(where: { $0.type != .dummy && tableMonths.contains($0.month.rawValue) }) {
            return matching
        }
        if let nonDummy = hand.first(where: { $0.type != .dummy }) {
            return nonDummy
        }
        return hand.first
    }
    
    private func chooseComputerCaptureOption(from options: [Card]) -> Card? {
        if let doubleJunk = options.first(where: { $0.type == .doubleJunk }) {
            return doubleJunk
        }
        return options.first
    }

    private func runAfterAnimationDelay(_ delay: Double, _ block: @escaping () -> Void) {
        if delay <= 0 {
            block()
        } else {
            let generation = automationDelayGeneration
            pendingAutomationDelays += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { 
                    block() 
                    return 
                }
                
                let generationMatches = (self.automationDelayGeneration == generation)
                if generationMatches {
                    self.pendingAutomationDelays = max(0, self.pendingAutomationDelays - 1)
                    block()
                }
                // If generation doesn't match, we omit block() because the game has been reset.
                // setupGame() already cleared pendingAutomationDelays, currentMovingCards, etc.
            }
        }
    }

    private func performTableCapture(for monthCard: Card, on table: inout [Card], player: Player) -> [Card]? {
        let m = table.filter { $0.month == monthCard.month }
        if m.isEmpty {
            table.append(monthCard)
            return []
        } else if m.count == 3 {
            let allFour = [monthCard] + m
            table.removeAll { $0.month == monthCard.month }

            let month = monthCard.month.rawValue
            let isInvalidLastHandSeolsa = invalidLastHandSeolsaMonths.contains(month)
            if let puckCreator = seolsaMonths[month] {
                if puckCreator.id == player.id {
                    isSelfSeolsaEatFlag = true
                } else {
                    isSeolsaEatFlag = true
                }
                seolsaMonths.removeValue(forKey: month)
            } else if !isInvalidLastHandSeolsa {
                isSeolsaEatFlag = true
            }
            invalidLastHandSeolsaMonths.remove(month)
            return allFour
        } else if m.count == 2 {
            let typesDistinct = m[0].type != m[1].type
            if typesDistinct {
                if player.isComputer {
                    let bestOption = m.first { $0.type == .doubleJunk } ?? m[0]
                    if let idx = table.firstIndex(where: { $0.id == bestOption.id }) {
                        table.remove(at: idx)
                    }
                    return [monthCard, bestOption]
                } else {
                    return nil
                }
            } else {
                if let target = m.first, let idx = table.firstIndex(where: { $0.id == target.id }) {
                    table.remove(at: idx)
                    return [monthCard, target]
                }
                table.append(monthCard)
                return []
            }
        } else {
            if let target = m.first, let idx = table.firstIndex(where: { $0.id == target.id }) {
                table.remove(at: idx)
                return [monthCard, target]
            }
            table.append(monthCard)
            return []
        }
    }
    
    private func animatePenaltyPiTransfer(cards: [Card], from: Player, to: Player, reason: String) {
        guard !cards.isEmpty else { return }

        let sourcePlayerId = from.id.uuidString
        let targetPlayerId = to.id.uuidString
        let cardIds = cards.map { $0.id }
        let cardIdSet = Set(cardIds)
        let cardIdsJoined = cardIds.joined(separator: ",")
        let motion = AnimationManager.shared.motionPlan(source: "captured", target: "captured")

        // Apply ownership atomically first so model state never contains duplicate IDs.
        from.capturedCards.removeAll { cardIdSet.contains($0.id) }
        for movedCard in cards {
            if !to.capturedCards.contains(where: { $0.id == movedCard.id }) {
                to.capturedCards.append(movedCard)
            }
            to.hasCapturedThisRound = true
            hiddenInTargetCardIds.insert(movedCard.id)
            hiddenInSourceCardIds.remove(movedCard.id)
        }

        currentMovingCards = cards
        movingCardsScale = 0.86
        movingCardsPiCount = nil
        movingCardsShowDebug = false
        penaltyMoveProgress = 0

        setMoveContext(
            source: "captured",
            target: "captured",
            capturedSourcePlayerId: sourcePlayerId,
            capturedTargetPlayerId: targetPlayerId
        )

        let performTransfer: () -> Void = {
            self.addUXEvent(
                type: "moveStart",
                data: [
                    "cardIds": cardIdsJoined,
                    "source": "captured",
                    "target": "captured",
                    "sourcePlayerId": sourcePlayerId,
                    "targetPlayerId": targetPlayerId,
                    "reason": reason
                ]
            )
            self.takeSnapshot()

            if let moveAnimation = motion.animation {
                withAnimation(moveAnimation) {
                    self.penaltyMoveProgress = 1
                }
            } else {
                self.penaltyMoveProgress = 1
            }

            self.runAfterAnimationDelay(motion.delay) {
                self.addUXEvent(
                    type: "moveEnd",
                    data: [
                        "cardIds": cardIdsJoined,
                        "source": "captured",
                        "target": "captured",
                        "sourcePlayerId": sourcePlayerId,
                        "targetPlayerId": targetPlayerId,
                        "reason": reason
                    ]
                )
                for id in cardIds {
                    self.hiddenInSourceCardIds.remove(id)
                    self.hiddenInTargetCardIds.remove(id)
                }
                self.showTargetCue(for: cards)
                self.currentMovingCards = []
                self.penaltyMoveProgress = 0
                self.clearMoveContextAfterCue(
                    expectedSource: "captured",
                    expectedTarget: "captured",
                    expectedCapturedSourcePlayerId: sourcePlayerId,
                    expectedCapturedTargetPlayerId: targetPlayerId
                )
                self.takeSnapshot()
            }
        }

        // Delay pi transfer start to prevent visual overlap with the preceding
        // table->captured animation in animated UI mode.
        // In CLI validation mode (all move/match delays are forced to 0),
        // keep this at 0 so busy flags do not remain pending on async timers.
        let matchPause = AnimationManager.shared.config.match_pause_duration
        let isInstantPipeline = motion.delay <= 0 && matchPause <= 0
        let delayBeforeTransfer = isInstantPipeline ? 0 : max(0.2, matchPause * 1.5)
        
        self.runAfterAnimationDelay(delayBeforeTransfer) {
            performTransfer()
        }
    }

    private struct PiTransferCandidate {
        let card: Card
        let piValue: Int
    }

    private func shouldPreferPiTransferCombo(
        _ candidate: [PiTransferCandidate],
        over existing: [PiTransferCandidate]?
    ) -> Bool {
        guard let existing else { return true }
        return candidate.count < existing.count
    }

    private func selectPiCardsForTransfer(from cards: [Card], targetPiCount: Int, rules: RuleConfig) -> [Card] {
        guard targetPiCount > 0 else { return [] }

        let candidates = cards.reversed().compactMap { card -> PiTransferCandidate? in
            let piValue = ScoringSystem.piValue(for: card, in: cards, rules: rules)
            guard piValue > 0 else { return nil }
            return PiTransferCandidate(card: card, piValue: piValue)
        }
        guard !candidates.isEmpty else { return [] }

        var bestCombosBySum: [Int: [PiTransferCandidate]] = [0: []]
        for candidate in candidates {
            let snapshot = bestCombosBySum
            for (sum, combo) in snapshot {
                let newSum = sum + candidate.piValue
                var newCombo = combo
                newCombo.append(candidate)
                if shouldPreferPiTransferCombo(newCombo, over: bestCombosBySum[newSum]) {
                    bestCombosBySum[newSum] = newCombo
                }
            }
        }

        let sortedSums = bestCombosBySum.keys.sorted()
        if let selectedSum = sortedSums.first(where: { $0 >= targetPiCount }) {
            return bestCombosBySum[selectedSum]?.map(\.card) ?? []
        }
        guard let maxAvailableSum = sortedSums.last else { return [] }
        return bestCombosBySum[maxAvailableSum]?.map(\.card) ?? []
    }

    private func stealPi(from: Player, to: Player, count: Int, reason: String = "") {
        guard let rules = RuleLoader.shared.config else { return }

        // `count` represents requested Pi units, not a raw card count.
        let selectedCards = selectPiCardsForTransfer(from: from.capturedCards, targetPiCount: count, rules: rules)

        if !selectedCards.isEmpty {
            animatePenaltyPiTransfer(cards: selectedCards, from: from, to: to, reason: reason)
            updateScoreAndEmitScoreEvents(for: from)
            updateScoreAndEmitScoreEvents(for: to)
            let stolenCardsText = selectedCards.map { card in
                let typeText = card.type == .doubleJunk ? gameText("card.type.short.double_junk") : gameText("card.type.short.junk")
                return "\(card.month.rawValue)월 \(typeText)"
            }.joined(separator: ", ")
            gLog(
                gameText(
                    "log.event.pi_transfer",
                    [
                        "reasonSuffix": piTransferReasonSuffix(reason),
                        "from": from.name,
                        "to": to.name,
                        "cards": stolenCardsText,
                        "count": selectedCards.count
                    ]
                )
            )
        } else {
            gLog(
                gameText(
                    "log.event.pi_transfer_failed",
                    [
                        "reasonSuffix": piTransferReasonSuffix(reason),
                        "from": from.name
                    ]
                )
            )
        }
    }

    private func settleResidualCardsIfHandsEmpty() {
        guard players.allSatisfy({ $0.hand.isEmpty }) else { return }

        var movedCount = 0
        if !tableCards.isEmpty {
            movedCount += tableCards.count
            outOfPlayCards.append(contentsOf: tableCards)
            tableCards.removeAll()
        }

        let remainingDeckCards = deck.drainAll()
        if !remainingDeckCards.isEmpty {
            movedCount += remainingDeckCards.count
            outOfPlayCards.append(contentsOf: remainingDeckCards)
        }
    }
}

// Extension to GameManager to provide serializable state
extension GameManager {
    func serializeState() -> [String: AnyCodable] {
        var state: [String: AnyCodable] = [:]
        state["gameState"] = AnyCodable(gameState.rawValue)
        state["deckCount"] = AnyCodable(deck.cards.count)
        state["tableCards"] = AnyCodable(tableCards)
        state["deckCards"] = AnyCodable(deck.cards)
        state["outOfPlayCount"] = AnyCodable(outOfPlayCards.count)
        state["outOfPlayCards"] = AnyCodable(outOfPlayCards)
        state["currentTurnIndex"] = AnyCodable(currentTurnIndex)
        state["isAutomationBusy"] = AnyCodable(isAutomationBusy)
        state["pendingAutomationDelays"] = AnyCodable(pendingAutomationDelays)
        state["currentMovingCardIds"] = AnyCodable(currentMovingCards.map { $0.id })
        state["hiddenInSourceCardIds"] = AnyCodable(Array(hiddenInSourceCardIds).sorted())
        state["hiddenInTargetCardIds"] = AnyCodable(Array(hiddenInTargetCardIds).sorted())
        state["sourceCueCardIds"] = AnyCodable(Array(sourceCueCardIds).sorted())
        state["targetCueCardIds"] = AnyCodable(Array(targetCueCardIds).sorted())
        state["currentMoveSourceZone"] = AnyCodable(currentMoveSourceZone as Any)
        state["currentMoveTargetZone"] = AnyCodable(currentMoveTargetZone as Any)
        state["penaltyMoveProgress"] = AnyCodable(penaltyMoveProgress)
        state["capturedMoveSourcePlayerId"] = AnyCodable(capturedMoveSourcePlayerId as Any)
        state["capturedMoveTargetPlayerId"] = AnyCodable(capturedMoveTargetPlayerId as Any)
        state["opponentPreplayRevealCardId"] = AnyCodable(opponentPreplayRevealCardId as Any)
        state["uiActiveSpecialEventPopupTitle"] = AnyCodable(uiActiveSpecialEventPopupTitle as Any)
        state["uiPendingSpecialEventPopupCount"] = AnyCodable(uiPendingSpecialEventPopupCount)
        state["uiIsEndSummaryDeferredBySpecialEvents"] = AnyCodable(uiIsEndSummaryDeferredBySpecialEvents)
        state["uiIsDecisionOverlayDeferredBySpecialEvents"] = AnyCodable(uiIsDecisionOverlayDeferredBySpecialEvents)
        state["uiActiveCapturedPreviewOwnerPlayerId"] = AnyCodable(uiActiveCapturedPreviewOwnerPlayerId as Any)
        state["uiActiveCapturedPreviewGroupType"] = AnyCodable(uiActiveCapturedPreviewGroupType as Any)
        state["uiActiveCapturedPreviewCardCount"] = AnyCodable(uiActiveCapturedPreviewCardCount)
        state["players"] = AnyCodable(players.map { player in
            var playerDict = player.serialize()
            playerDict["scoreItems"] = AnyCodable(ScoringSystem.calculateScoreDetail(for: player))
            return playerDict
        })
        state["eventLogs"] = AnyCodable(eventLogs)
        state["uxEventLogs"] = AnyCodable(uxEventLogs)
        state["historyCount"] = AnyCodable(stateHistory.count)
        
        if let playedCard = pendingCapturePlayedCard {
            state["pendingCapturePlayedCard"] = AnyCodable(playedCard)
        }
        if let drawnCard = pendingCaptureDrawnCard {
            state["pendingCaptureDrawnCard"] = AnyCodable(drawnCard)
        }
        
        if gameState == .choosingCapture {
            state["pendingCaptureOptions"] = AnyCodable(pendingCaptureOptions)
        }
        
        if gameState == .choosingChrysanthemumRole {
            if let chrysCard = pendingChrysanthemumCard {
                state["pendingChrysanthemumCard"] = AnyCodable(chrysCard)
            }
        }
        
        if gameState == .askingShake {
            state["pendingShakeMonths"] = AnyCodable(pendingShakeMonths)
        }
        
        if let month = chongtongMonth {
            state["chongtongMonth"] = AnyCodable(month)
        }
        if let timing = chongtongTiming {
            state["chongtongTiming"] = AnyCodable(timing)
        }
        
        if gameState == .ended {
            if let reason = gameEndReason {
                state["gameEndReason"] = AnyCodable(reason.rawValue)
            }
            if let lastResult = lastPenaltyResult {
                state["penaltyResult"] = AnyCodable([
                    "finalScore": AnyCodable(lastResult.finalScore),
                    "isGwangbak": AnyCodable(lastResult.isGwangbak),
                    "isPibak": AnyCodable(lastResult.isPibak),
                    "isGobak": AnyCodable(lastResult.isGobak),
                    "isMungbak": AnyCodable(lastResult.isMungbak),
                    "isJabak": AnyCodable(lastResult.isJabak),
                    "isYeokbak": AnyCodable(lastResult.isYeokbak),
                    "scoreFormula": AnyCodable(lastResult.scoreFormula)
                ])
            } else if gameEndReason == .nagari {
                state["penaltyResult"] = AnyCodable([
                    "finalScore": AnyCodable(0),
                    "isGwangbak": AnyCodable(false),
                    "isPibak": AnyCodable(false),
                    "isGobak": AnyCodable(false),
                    "isMungbak": AnyCodable(false),
                    "isJabak": AnyCodable(false),
                    "isYeokbak": AnyCodable(false),
                    "scoreFormula": AnyCodable(gameText("penalty.formula.nagari_draw"))
                ])
            } else if let rules = RuleLoader.shared.config {
                // Keep socket/state serialization behavior aligned with CLI dumpState fallback.
                // Some test scenarios force ended state without setting lastPenaltyResult.
                let winner = players[0].score >= players[1].score ? players[0] : players[1]
                let loser = winner === players[0] ? players[1] : players[0]
                let penalty = PenaltySystem.calculatePenalties(winner: winner, loser: loser, rules: rules)
                state["penaltyResult"] = AnyCodable([
                    "finalScore": AnyCodable(penalty.finalScore),
                    "isGwangbak": AnyCodable(penalty.isGwangbak),
                    "isPibak": AnyCodable(penalty.isPibak),
                    "isGobak": AnyCodable(penalty.isGobak),
                    "isMungbak": AnyCodable(penalty.isMungbak),
                    "isJabak": AnyCodable(penalty.isJabak),
                    "isYeokbak": AnyCodable(penalty.isYeokbak),
                    "scoreFormula": AnyCodable(penalty.scoreFormula)
                ])
            }
        }
        
        state["status"] = AnyCodable("ok")
        return state
    }

    func resolveMultiplayerViewerPlayerId(
        preferredPlayerId: String? = nil,
        preferredPlayerIndex: Int? = nil
    ) -> String? {
        if let preferredPlayerId,
           players.contains(where: { $0.id.uuidString == preferredPlayerId }) {
            return preferredPlayerId
        }

        if let preferredPlayerIndex,
           players.indices.contains(preferredPlayerIndex) {
            return players[preferredPlayerIndex].id.uuidString
        }

        if let currentPlayer {
            return currentPlayer.id.uuidString
        }

        if let firstHuman = players.first(where: { !$0.isComputer }) {
            return firstHuman.id.uuidString
        }

        return players.first?.id.uuidString
    }

    func makeMultiplayerProjectionContext(
        viewerPlayerId: String? = nil,
        traceId: String? = nil,
        roomId: String? = nil,
        gameId: String = "local_game",
        stateVersion: Int = 0,
        lastEventId: String? = nil,
        snapshotId: String? = nil,
        turnId: String? = nil,
        serverTime: String? = nil,
        snapshotReason: MultiplayerSnapshotReason = .localPreview,
        scope: MultiplayerProjectionScope = .player,
        participantPresenceByPlayerId: [String: MultiplayerParticipantPresence]? = nil,
        engineVersion: String? = nil,
        ruleConfigVersion: String? = nil
    ) -> MultiplayerProjectionContext {
        let resolvedViewerPlayerId = resolveMultiplayerViewerPlayerId(preferredPlayerId: viewerPlayerId)
        let resolvedTurnId = turnId ?? String(format: "turn_%04d", max(1, completedTurnCount + 1))
        let resolvedSnapshotId = snapshotId
            ?? "snap_\(max(0, stateVersion))_\(resolvedViewerPlayerId ?? scope.rawValue)"

        return MultiplayerProjectionContext(
            traceId: traceId,
            roomId: roomId,
            gameId: gameId,
            stateVersion: stateVersion,
            lastEventId: lastEventId,
            turnId: resolvedTurnId,
            snapshotId: resolvedSnapshotId,
            serverTime: serverTime ?? Self.multiplayerTimestamp(),
            snapshotReason: snapshotReason,
            scope: scope,
            participantPresenceByPlayerId: participantPresenceByPlayerId,
            engineVersion: engineVersion ?? Self.multiplayerEngineVersion(),
            ruleConfigVersion: ruleConfigVersion ?? Self.multiplayerRuleConfigVersion()
        )
    }

    func multiplayerSnapshot(
        viewerPlayerId: String? = nil,
        context: MultiplayerProjectionContext? = nil
    ) -> MultiplayerSnapshot {
        let resolvedViewerPlayerId = resolveMultiplayerViewerPlayerId(preferredPlayerId: viewerPlayerId)
        let resolvedContext = context ?? makeMultiplayerProjectionContext(viewerPlayerId: resolvedViewerPlayerId)
        let effectiveViewerPlayerId = resolvedContext.scope == .authority
            ? resolvedViewerPlayerId
            : resolveMultiplayerViewerPlayerId(preferredPlayerId: resolvedViewerPlayerId)
        let pendingChoice = multiplayerPendingChoice(
            viewerPlayerId: effectiveViewerPlayerId,
            stateVersion: resolvedContext.stateVersion,
            scope: resolvedContext.scope
        )
        let choiceDeadlineAt = pendingChoice?.deadlineAt
        let starterPlayerId = multiplayerStarterPlayerId()

        let state = MultiplayerMatchSnapshot(
            traceId: resolvedContext.traceId,
            roomId: resolvedContext.roomId,
            gameId: resolvedContext.gameId,
            viewerPlayerId: effectiveViewerPlayerId,
            engineVersion: resolvedContext.engineVersion,
            ruleConfigVersion: resolvedContext.ruleConfigVersion,
            stateVersion: resolvedContext.stateVersion,
            lastEventId: resolvedContext.lastEventId,
            phase: multiplayerPhase,
            turnId: resolvedContext.turnId,
            currentPlayerId: currentPlayer?.id.uuidString,
            dealerPlayerId: starterPlayerId,
            starterPlayerId: starterPlayerId,
            players: players.enumerated().map { seatIndex, player in
                multiplayerPlayerProjection(
                    player,
                    seatIndex: seatIndex,
                    viewerPlayerId: effectiveViewerPlayerId,
                    scope: resolvedContext.scope,
                    participantPresence: resolvedContext.participantPresenceByPlayerId?[player.id.uuidString]
                )
            },
            table: multiplayerTableSnapshot(),
            deck: MultiplayerDeckSnapshot(remainingCount: deck.cards.count),
            pendingChoice: pendingChoice,
            scoreboard: multiplayerScoreboard(),
            timers: MultiplayerTimers(
                turnDeadlineAt: nil,
                choiceDeadlineAt: choiceDeadlineAt
            ),
            resume: MultiplayerResumeState(
                isResumable: false,
                graceDeadlineAt: nil
            )
        )

        return MultiplayerSnapshot(
            snapshotId: resolvedContext.snapshotId,
            reason: resolvedContext.snapshotReason,
            scope: resolvedContext.scope,
            snapshotStateVersion: resolvedContext.stateVersion,
            lastIncludedEventId: resolvedContext.lastEventId,
            state: state
        )
    }

    func multiplayerGameStartedPayload(
        context: MultiplayerProjectionContext
    ) -> MultiplayerGameStartedPayload {
        let starterPlayerId = multiplayerStarterPlayerId()
        return MultiplayerGameStartedPayload(
            roundIndex: 1,
            dealerPlayerId: starterPlayerId,
            starterPlayerId: starterPlayerId,
            firstPlayerId: starterPlayerId,
            snapshotId: context.snapshotId,
            snapshotStateVersion: context.stateVersion
        )
    }

    func multiplayerGameStartedBootstrapPayload(
        viewerPlayerId: String? = nil,
        context: MultiplayerProjectionContext
    ) -> MultiplayerGameStartedBootstrapPayload {
        let gameStarted = multiplayerGameStartedPayload(context: context)
        let stateSnapshot = multiplayerSnapshot(
            viewerPlayerId: viewerPlayerId,
            context: context
        )

        return MultiplayerGameStartedBootstrapPayload(
            gameStarted: gameStarted,
            stateSnapshot: stateSnapshot
        )
    }

    func multiplayerLiveBootstrapPayload(
        viewerPlayerId: String? = nil,
        context: MultiplayerProjectionContext
    ) -> MultiplayerLiveBootstrapPayload {
        let bootstrap = multiplayerGameStartedBootstrapPayload(
            viewerPlayerId: viewerPlayerId,
            context: context
        )

        return MultiplayerLiveBootstrapPayload(
            activeGameId: context.gameId,
            gameStarted: bootstrap.gameStarted,
            stateSnapshot: bootstrap.stateSnapshot
        )
    }

    func multiplayerRoundEndedPayload(
        roundIndex: Int = 1,
        quitReason: MultiplayerQuitReason? = nil,
        forfeitingPlayerId: String? = nil
    ) -> MultiplayerRoundEndedPayload? {
        guard let summary = multiplayerRoundSummary(
            roundIndex: roundIndex,
            quitReason: quitReason,
            forfeitingPlayerId: forfeitingPlayerId
        ) else {
            return nil
        }

        return MultiplayerRoundEndedPayload(
            roundIndex: roundIndex,
            summary: summary
        )
    }

    func multiplayerMatchEndedPayload(
        quitReason: MultiplayerQuitReason? = nil,
        forfeitingPlayerId: String? = nil
    ) -> MultiplayerMatchEndedPayload? {
        guard let summary = multiplayerRoundSummary(
            roundIndex: 1,
            quitReason: quitReason,
            forfeitingPlayerId: forfeitingPlayerId
        ) else {
            return nil
        }

        return MultiplayerMatchEndedPayload(
            roundIndex: summary.roundIndex,
            winnerPlayerId: summary.winnerPlayerId,
            loserPlayerId: summary.loserPlayerId,
            finalScores: summary.finalScores,
            settlementSummary: summary.settlementSummary,
            endReason: summary.endReason,
            endReasonMessageKey: summary.endReasonMessageKey,
            forfeitingPlayerId: summary.forfeitingPlayerId,
            isDraw: summary.isDraw
        )
    }

    func multiplayerTerminalSummaryPayload(
        context: MultiplayerProjectionContext,
        roundIndex: Int = 1,
        quitReason: MultiplayerQuitReason? = nil,
        forfeitingPlayerId: String? = nil
    ) -> MultiplayerTerminalSummaryPayload? {
        guard let roundEnded = multiplayerRoundEndedPayload(
                roundIndex: roundIndex,
                quitReason: quitReason,
                forfeitingPlayerId: forfeitingPlayerId
        ),
        let matchEnded = multiplayerMatchEndedPayload(
            quitReason: quitReason,
            forfeitingPlayerId: forfeitingPlayerId
        ) else {
            return nil
        }

        return MultiplayerTerminalSummaryPayload(
            roomId: context.roomId,
            gameId: context.gameId,
            summaryStateVersion: context.stateVersion,
            lastEventId: context.lastEventId,
            roundEnded: roundEnded,
            matchEnded: matchEnded
        )
    }
    
    func restoreState(from historyIndex: Int) {
        guard stateHistory.indices.contains(historyIndex) else { return }
        let snapshot = stateHistory[historyIndex]
        restoreFromSnapshot(snapshot)
    }
    
    func restoreFromSnapshot(_ snapshot: [String: AnyCodable]) {
        // Implementation for restoring basic properties
        if let gameStateStr = snapshot["gameState"]?.value as? String,
           let state = GameState(rawValue: gameStateStr) {
            self.gameState = state
        }
        
        if let turnIndex = snapshot["currentTurnIndex"]?.value as? Int {
            self.currentTurnIndex = turnIndex
        }
        
        // Complex objects would need deeper restoration if we want full fidelity.
        // For UX monitoring, we primarily need the visual state: cards on table, in hands, etc.
        // This is a simplified restore for now.
    }

    private var multiplayerPhase: MultiplayerPhase {
        switch gameState {
        case .ready:
            return .waiting
        case .playing:
            return .inTurn
        case .askingShake, .askingGoStop, .choosingCapture, .choosingChrysanthemumRole:
            return .choicePending
        case .ended:
            return .matchEnded
        }
    }

    private func multiplayerPlayerProjection(
        _ player: Player,
        seatIndex: Int,
        viewerPlayerId: String?,
        scope: MultiplayerProjectionScope,
        participantPresence: MultiplayerParticipantPresence?
    ) -> MultiplayerPlayerProjection {
        let playerId = player.id.uuidString
        let isViewer = playerId == viewerPlayerId
        let shouldRevealHand = scope == .authority || isViewer

        return MultiplayerPlayerProjection(
            playerId: playerId,
            seatIndex: seatIndex,
            name: player.name,
            hand: shouldRevealHand ? player.hand.map(multiplayerCardSummary(from:)) : nil,
            handCount: player.hand.count,
            captured: multiplayerCapturedCards(for: player),
            score: player.score,
            money: player.money,
            goCount: player.goCount,
            shakeCount: player.shakeCount,
            isConnected: participantPresence?.isConnected,
            isReady: participantPresence?.isReady,
            presenceSource: participantPresence?.source ?? .unknown,
            isViewer: isViewer
        )
    }

    private func multiplayerCapturedCards(for player: Player) -> MultiplayerCapturedCards {
        let summaries = player.capturedCards.map(multiplayerCardSummary(from:))
        return MultiplayerCapturedCards(
            bright: summaries.filter { $0.kind == CardType.bright.rawValue },
            animal: summaries.filter { $0.kind == CardType.animal.rawValue },
            ribbon: summaries.filter { $0.kind == CardType.ribbon.rawValue },
            junk: summaries.filter {
                $0.kind == CardType.junk.rawValue ||
                $0.kind == CardType.doubleJunk.rawValue ||
                $0.kind == CardType.dummy.rawValue
            }
        )
    }

    private func multiplayerTableSnapshot() -> MultiplayerTableSnapshot {
        let summaries = tableCards.map(multiplayerCardSummary(from:))
        let buckets = Dictionary(grouping: summaries, by: { String($0.month) })
        return MultiplayerTableSnapshot(cards: summaries, monthBuckets: buckets)
    }

    private func multiplayerScoreboard() -> MultiplayerScoreboard {
        MultiplayerScoreboard(
            roundIndex: 1,
            playerScores: multiplayerPlayerScores(),
            winnerPlayerId: gameWinner?.id.uuidString
        )
    }

    private func multiplayerStarterPlayerId() -> String? {
        if let currentRoundStarterIndex,
           players.indices.contains(currentRoundStarterIndex) {
            return players[currentRoundStarterIndex].id.uuidString
        }

        if gameState == .playing || gameState == .askingShake || gameState == .askingGoStop ||
            gameState == .choosingCapture || gameState == .choosingChrysanthemumRole ||
            gameState == .ended {
            guard players.indices.contains(currentTurnIndex) else { return nil }
            return players[currentTurnIndex].id.uuidString
        }

        return nil
    }

    private func multiplayerPlayerScores() -> [MultiplayerPlayerScore] {
        players.map { player in
            MultiplayerPlayerScore(
                playerId: player.id.uuidString,
                score: player.score,
                goCount: player.goCount,
                money: player.money
            )
        }
    }

    private func multiplayerRoundSummary(
        roundIndex: Int,
        quitReason: MultiplayerQuitReason?,
        forfeitingPlayerId: String?
    ) -> MultiplayerRoundSummary? {
        guard let endReason = multiplayerMatchEndReason(quitReason: quitReason) else {
            return nil
        }

        if multiplayerIsForfeitEndReason(endReason) {
            guard let forfeitingPlayerId,
                  players.contains(where: { $0.id.uuidString == forfeitingPlayerId }) else {
                return nil
            }
        }

        let participants = multiplayerTerminalParticipants(
            endReason: endReason,
            forfeitingPlayerId: forfeitingPlayerId
        )

        return MultiplayerRoundSummary(
            roundIndex: roundIndex,
            winnerPlayerId: participants.winner?.id.uuidString,
            loserPlayerId: participants.loser?.id.uuidString,
            finalScores: multiplayerPlayerScores(),
            settlementSummary: multiplayerSettlementSummary(
                endReason: endReason,
                winner: participants.winner,
                loser: participants.loser
            ),
            endReason: endReason,
            endReasonMessageKey: multiplayerEndReasonMessageKey(endReason),
            forfeitingPlayerId: forfeitingPlayerId,
            isDraw: participants.isDraw
        )
    }

    private func multiplayerPendingChoice(
        viewerPlayerId: String?,
        stateVersion: Int,
        scope: MultiplayerProjectionScope
    ) -> MultiplayerChoice? {
        guard let actor = currentPlayer else { return nil }
        let actorId = actor.id.uuidString

        switch gameState {
        case .choosingCapture:
            let choiceId = "choice_capture_\(stateVersion)_\(actorId)"
            let sharedCards = [
                pendingCapturePlayedCard.map { multiplayerChoiceCard(from: $0, zone: "played") },
                pendingCaptureDrawnCard.map { multiplayerChoiceCard(from: $0, zone: "drawn") }
            ].compactMap { $0 }

            let options = pendingCaptureOptions.map { option in
                MultiplayerChoiceOption(
                    optionCode: option.id,
                    labelKey: "match.choice.capture.take_pair",
                    cards: sharedCards + [multiplayerChoiceCard(from: option, zone: "table")],
                    effectTags: ["capture"],
                    scoreDeltaPreview: nil,
                    metadata: multiplayerMetadata([
                        "selectedTableCardId": option.id
                    ])
                )
            }

            return MultiplayerChoice(
                choiceId: choiceId,
                choiceKind: MultiplayerContractChoiceKind.capture,
                visibility: .allParticipants,
                actorPlayerId: actorId,
                promptKey: "match.choice.capture",
                requestedAt: nil,
                deadlineAt: nil,
                expiresAtStateVersion: stateVersion,
                options: options
            )

        case .askingShake:
            let month = pendingShakeMonth ?? pendingShakeMonths.first
            guard let month else { return nil }

            let shouldRevealShakeCards = scope == .authority || viewerPlayerId == actorId
            let relatedCards = shouldRevealShakeCards
                ? actor.hand
                    .filter { $0.month.rawValue == month }
                    .map { multiplayerChoiceCard(from: $0, zone: "hand") }
                : []
            let choiceId = "choice_shake_\(stateVersion)_\(actorId)_\(month)"
            let metadata = shouldRevealShakeCards ? multiplayerMetadata(["month": month]) : nil

            return MultiplayerChoice(
                choiceId: choiceId,
                choiceKind: MultiplayerContractChoiceKind.shake,
                visibility: .actorOnly,
                actorPlayerId: actorId,
                promptKey: "match.choice.shake",
                requestedAt: nil,
                deadlineAt: nil,
                expiresAtStateVersion: stateVersion,
                options: [
                    MultiplayerChoiceOption(
                        optionCode: "shake_yes",
                        labelKey: "match.choice.shake.yes",
                        cards: relatedCards,
                        effectTags: ["shake"],
                        scoreDeltaPreview: nil,
                        metadata: metadata
                    ),
                    MultiplayerChoiceOption(
                        optionCode: "shake_no",
                        labelKey: "match.choice.shake.no",
                        cards: relatedCards,
                        effectTags: ["shake"],
                        scoreDeltaPreview: nil,
                        metadata: metadata
                    )
                ]
            )

        case .askingGoStop:
            let choiceId = "choice_gostop_\(stateVersion)_\(actorId)"
            return MultiplayerChoice(
                choiceId: choiceId,
                choiceKind: MultiplayerContractChoiceKind.goStop,
                visibility: .allParticipants,
                actorPlayerId: actorId,
                promptKey: "match.choice.go_stop",
                requestedAt: nil,
                deadlineAt: nil,
                expiresAtStateVersion: stateVersion,
                options: [
                    MultiplayerChoiceOption(
                        optionCode: "go",
                        labelKey: "match.choice.go_stop.go",
                        cards: [],
                        effectTags: ["go"],
                        scoreDeltaPreview: nil,
                        metadata: multiplayerMetadata(["playerId": actorId])
                    ),
                    MultiplayerChoiceOption(
                        optionCode: "stop",
                        labelKey: "match.choice.go_stop.stop",
                        cards: [],
                        effectTags: ["stop"],
                        scoreDeltaPreview: nil,
                        metadata: multiplayerMetadata(["playerId": actorId])
                    )
                ]
            )

        case .choosingChrysanthemumRole:
            guard let chrysanthemumCard = pendingChrysanthemumCard else { return nil }
            let choiceId = "choice_chrysanthemum_\(stateVersion)_\(actorId)"
            let card = multiplayerChoiceCard(from: chrysanthemumCard, zone: "pendingCapture")
            return MultiplayerChoice(
                choiceId: choiceId,
                choiceKind: MultiplayerContractChoiceKind.chrysanthemumRole,
                visibility: .allParticipants,
                actorPlayerId: actorId,
                promptKey: "match.choice.chrysanthemum_role",
                requestedAt: nil,
                deadlineAt: nil,
                expiresAtStateVersion: stateVersion,
                options: [
                    MultiplayerChoiceOption(
                        optionCode: CardRole.animal.rawValue,
                        labelKey: "match.choice.chrysanthemum_role.animal",
                        cards: [card],
                        effectTags: ["chrysanthemumRole"],
                        scoreDeltaPreview: nil,
                        metadata: multiplayerMetadata(["selectedRole": CardRole.animal.rawValue])
                    ),
                    MultiplayerChoiceOption(
                        optionCode: CardRole.doublePi.rawValue,
                        labelKey: "match.choice.chrysanthemum_role.double_pi",
                        cards: [card],
                        effectTags: ["chrysanthemumRole"],
                        scoreDeltaPreview: nil,
                        metadata: multiplayerMetadata(["selectedRole": CardRole.doublePi.rawValue])
                    )
                ]
            )

        case .ready, .playing, .ended:
            return nil
        }
    }

    private func multiplayerCardSummary(from card: Card) -> MultiplayerCardSummary {
        MultiplayerCardSummary(
            cardId: card.id,
            month: card.month.rawValue,
            kind: card.type.rawValue,
            imageIndex: card.imageIndex,
            selectedRole: card.selectedRole?.rawValue
        )
    }

    private func multiplayerChoiceCard(from card: Card, zone: String) -> MultiplayerChoiceCard {
        MultiplayerChoiceCard(
            cardId: card.id,
            zone: zone,
            month: card.month.rawValue,
            kind: card.type.rawValue,
            imageIndex: card.imageIndex,
            selectedRole: card.selectedRole?.rawValue
        )
    }

    private func multiplayerMetadata(_ raw: [String: Any?]) -> [String: AnyCodable]? {
        var metadata: [String: AnyCodable] = [:]
        for (key, value) in raw {
            guard let value else { continue }
            metadata[key] = AnyCodable(value)
        }
        return metadata.isEmpty ? nil : metadata
    }

    private static func multiplayerTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func multiplayerEngineVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "gostop-core@\(version)"
        }
        return "gostop-core@local-preview"
    }

    private static func multiplayerRuleConfigVersion() -> String {
        URL(fileURLWithPath: ConfigurationStore.shared.configurationPath).lastPathComponent
    }

    private func multiplayerMatchEndReason(
        quitReason: MultiplayerQuitReason?
    ) -> MultiplayerMatchEndReason? {
        if let quitReason {
            switch quitReason {
            case .voluntaryExit:
                return .voluntaryQuit
            case .disconnectTimeout:
                return .disconnectTimeout
            case .adminForfeit:
                return .adminForfeit
            }
        }

        guard gameState == .ended, let gameEndReason else {
            return nil
        }

        switch gameEndReason {
        case .stop:
            return .stop
        case .maxScore:
            return .maxScore
        case .nagari:
            return .nagari
        case .chongtong:
            return .chongtong
        case .threeSeolsa:
            return .threeSeolsa
        }
    }

    private func multiplayerTerminalParticipants(
        endReason: MultiplayerMatchEndReason,
        forfeitingPlayerId: String?
    ) -> (winner: Player?, loser: Player?, isDraw: Bool) {
        if endReason == .nagari {
            return (winner: nil, loser: nil, isDraw: true)
        }

        if let forfeitingPlayerId,
           let forfeitingPlayer = players.first(where: { $0.id.uuidString == forfeitingPlayerId }) {
            let winner = gameWinner ?? players.first(where: { $0 !== forfeitingPlayer })
            return (winner: winner, loser: forfeitingPlayer, isDraw: false)
        }

        if let winner = gameWinner {
            let loser = gameLoser ?? players.first(where: { $0 !== winner })
            return (winner: winner, loser: loser, isDraw: false)
        }

        if let loser = gameLoser {
            let winner = players.first(where: { $0 !== loser })
            return (winner: winner, loser: loser, isDraw: false)
        }

        guard players.count >= 2 else {
            return (winner: players.first, loser: nil, isDraw: false)
        }

        let rankedPlayers = players.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return (
            winner: rankedPlayers.first,
            loser: rankedPlayers.dropFirst().first,
            isDraw: false
        )
    }

    private func multiplayerSettlementSummary(
        endReason: MultiplayerMatchEndReason,
        winner: Player?,
        loser: Player?
    ) -> MultiplayerSettlementSummary? {
        if multiplayerIsForfeitEndReason(endReason) {
            return nil
        }

        if let lastPenaltyResult {
            return multiplayerSettlementSummary(from: lastPenaltyResult, isDraw: endReason == .nagari)
        }

        if endReason == .nagari {
            return MultiplayerSettlementSummary(
                finalScore: 0,
                scoreFormula: gameText("penalty.formula.nagari_draw"),
                isDraw: true,
                isGwangbak: false,
                isPibak: false,
                isGobak: false,
                isMungbak: false,
                isJabak: false,
                isYeokbak: false
            )
        }

        guard let winner, let loser, let rules = RuleLoader.shared.config else {
            return nil
        }

        let penalty = PenaltySystem.calculatePenalties(winner: winner, loser: loser, rules: rules)
        return multiplayerSettlementSummary(from: penalty, isDraw: false)
    }

    private func multiplayerSettlementSummary(
        from penalty: PenaltySystem.PenaltyResult,
        isDraw: Bool
    ) -> MultiplayerSettlementSummary {
        MultiplayerSettlementSummary(
            finalScore: penalty.finalScore,
            scoreFormula: penalty.scoreFormula,
            isDraw: isDraw,
            isGwangbak: penalty.isGwangbak,
            isPibak: penalty.isPibak,
            isGobak: penalty.isGobak,
            isMungbak: penalty.isMungbak,
            isJabak: penalty.isJabak,
            isYeokbak: penalty.isYeokbak
        )
    }

    private func multiplayerIsForfeitEndReason(_ endReason: MultiplayerMatchEndReason) -> Bool {
        switch endReason {
        case .voluntaryQuit, .disconnectTimeout, .adminForfeit:
            return true
        case .stop, .maxScore, .nagari, .chongtong, .threeSeolsa:
            return false
        }
    }

    private func multiplayerEndReasonMessageKey(_ endReason: MultiplayerMatchEndReason) -> String {
        switch endReason {
        case .stop:
            return "match.end.stop"
        case .maxScore:
            return "match.end.max_score"
        case .nagari:
            return "match.end.nagari"
        case .chongtong:
            return "match.end.chongtong"
        case .threeSeolsa:
            return "match.end.three_seolsa"
        case .voluntaryQuit:
            return "match.end.voluntary_quit"
        case .disconnectTimeout:
            return "match.end.disconnect_timeout"
        case .adminForfeit:
            return "match.end.admin_forfeit"
        }
    }
}

// Helper for type-erased Codable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let codableValue = value as? Encodable {
            try codableValue.encode(to: encoder)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        } else {
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
