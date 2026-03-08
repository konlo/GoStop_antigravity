import SwiftUI

struct GameView: View {
    private enum StarterSelectionPhase {
        case playerPick
        case resolving
        case revealAll
    }

    private struct StarterSelectionState {
        var phase: StarterSelectionPhase
        var rule: StarterRule
        var remainingCardIds: [String]
        var revealedCardIds: Set<String>
        var playerCardId: String?
        var opponentCardId: String?
        var statusText: String
    }

    private struct RewindSnapshot {
        let moveEndEventId: String
        let cards: [Card]
        let sourceZone: String
        let targetZone: String
        let sourcePlayerId: String?
        let targetPlayerId: String?
        let duration: Double
    }

    private struct CapturedPreviewState: Equatable {
        let ownerPlayerId: String
        let groupType: String
    }

    private struct CapturedPreviewGroupSummary: Identifiable {
        let type: String
        let label: String
        let accentColor: Color
        let count: Int

        var id: String { type }
    }

    private struct CapturedPreviewModel {
        let ownerTitle: String
        let selectedLabel: String
        let selectedType: String
        let cards: [Card]
        let groups: [CapturedPreviewGroupSummary]
    }

    private struct CapturedPreviewPanel: View {
        let ctx: LayoutContext
        let model: CapturedPreviewModel
        let onDismiss: () -> Void

        var body: some View {
            GeometryReader { geo in
                let outerPadding = max(12, 16 * ctx.globalScale)
                let panelPadding = max(14, 16 * ctx.globalScale)
                let panelWidth = min(geo.size.width - (outerPadding * 2), geo.size.width < 430 ? 360 : 520)
                let headerSpacing = max(8, 10 * ctx.globalScale)
                let chipSpacing = max(6, 8 * ctx.globalScale)
                let itemSpacing = max(8, 10 * ctx.globalScale)
                let columnCount = geo.size.width < 430 ? 4 : 5
                let availableCardWidth = panelWidth - (panelPadding * 2) - (CGFloat(columnCount - 1) * itemSpacing)
                let targetCardWidth = max(44, availableCardWidth / CGFloat(columnCount))
                let previewScale = max(0.66, min(0.9, targetCardWidth / ctx.cardSize.width))
                let cardHeight = ctx.cardSize.height * previewScale
                let maxScrollHeight = min(geo.size.height * 0.42, cardHeight * 3.4)
                let cornerRadius = 20 * ctx.globalScale

                ZStack {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: headerSpacing) {
                        Text(model.ownerTitle)
                            .font(.system(size: max(12, 13 * ctx.globalScale), weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.78))

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(model.selectedLabel) 확대 보기")
                                .font(.system(size: max(22, 24 * ctx.globalScale), weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Spacer(minLength: 8)
                            Text("\(model.cards.count)장")
                                .font(.system(size: max(13, 14 * ctx.globalScale), weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.72))
                        }

                        HStack(spacing: chipSpacing) {
                            ForEach(model.groups) { group in
                                let isSelected = group.type == model.selectedType
                                Text("\(group.label) \(group.count)")
                                    .font(.system(size: max(11, 12 * ctx.globalScale), weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? .black.opacity(0.85) : .white.opacity(group.count > 0 ? 0.92 : 0.55))
                                    .padding(.horizontal, 10 * ctx.globalScale)
                                    .padding(.vertical, 6 * ctx.globalScale)
                                    .background(
                                        Capsule()
                                            .fill(group.accentColor.opacity(isSelected ? 0.95 : (group.count > 0 ? 0.28 : 0.12)))
                                    )
                            }
                        }

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: itemSpacing), count: columnCount),
                                spacing: itemSpacing
                            ) {
                                ForEach(model.cards) { card in
                                    CardView(card: card, isFaceUp: true, scale: previewScale)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .frame(maxHeight: maxScrollHeight)

                        Text("길게 눌러 열고, 확대 패널을 탭하면 닫습니다")
                            .font(.system(size: max(11, 12 * ctx.globalScale), weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.66))
                    }
                    .padding(panelPadding)
                    .frame(width: panelWidth)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.38), radius: 20, x: 0, y: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
            }
        }
    }

    private struct ShakePreviewCardCell: View {
        let card: Card
        let isSelected: Bool
        let scale: CGFloat
        let compact: Bool

        var body: some View {
            let strokeColor = isSelected ? Color.orange : Color.white.opacity(0.18)
            let strokeWidth: CGFloat = isSelected ? (compact ? 3 : 4) : 1
            let cornerRadius: CGFloat = compact ? 8 : 10

            return VStack(spacing: compact ? 0 : 10) {
                CardView(card: card, scale: scale)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(strokeColor, lineWidth: strokeWidth)
                    )

                if !compact {
                    Text(captionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(captionColor)
                }
            }
        }

        private var captionText: String {
            let typeLabel: String = {
                switch card.type {
                case .bright:
                    return "광"
                case .animal:
                    return "끗"
                case .ribbon:
                    return "띠"
                case .doubleJunk:
                    return "쌍피"
                case .junk:
                    return "피"
                case .dummy:
                    return "도탄"
                }
            }()
            return isSelected ? "낼 카드 · \(typeLabel)" : typeLabel
        }

        private var captionColor: Color {
            if isSelected {
                return .orange
            }

            switch card.type {
            case .bright:
                return .yellow
            case .animal:
                return .cyan
            case .ribbon:
                return .pink
            case .doubleJunk:
                return .orange
            case .junk:
                return .white.opacity(0.9)
            case .dummy:
                return .gray
            }
        }
    }

    private struct ShakePreviewCardsPanel: View {
        let previewCards: [Card]
        let selectedShakeCardId: String?

        var body: some View {
            VStack(spacing: 14) {
                Text("현재 들고 있는 패")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                ViewThatFits {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(previewCards) { card in
                            ShakePreviewCardCell(
                                card: card,
                                isSelected: card.id == selectedShakeCardId,
                                scale: 1.25,
                                compact: false
                            )
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(previewCards) { card in
                            HStack(spacing: 14) {
                                ShakePreviewCardCell(
                                    card: card,
                                    isSelected: card.id == selectedShakeCardId,
                                    scale: 1.0,
                                    compact: true
                                )

                                Text(card.id == selectedShakeCardId ? "낼 카드" : shortTypeLabel(for: card.type))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(card.id == selectedShakeCardId ? Color.orange : Color.white.opacity(0.9))

                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }

        private func shortTypeLabel(for type: CardType) -> String {
            switch type {
            case .bright:
                return "광"
            case .animal:
                return "끗"
            case .ribbon:
                return "띠"
            case .doubleJunk:
                return "쌍피"
            case .junk:
                return "피"
            case .dummy:
                return "도탄"
            }
        }
    }

    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    @ObservedObject var config: ConfigManager = .shared
    @StateObject private var animationManager = AnimationManager.shared
    @StateObject private var specialEventPopupCoordinator = SpecialEventPopupCoordinator()
    @State private var playerHandSlotManager: PlayerHandSlotManager?
    @State private var tableSlotManager: TableSlotManager?
    @State private var tableCardCenters: [String: CGPoint] = [:]
    // Key: "playerId:groupType" (e.g. "abc123:gwang") → screen-space center of that group slot
    @State private var capturedGroupCenters: [String: CGPoint] = [:]
    // Key: "playerId:cardId" -> exact rendered card center in captured area
    @State private var capturedCardCenters: [String: CGPoint] = [:]
    // Persistent debug info: survives animation end for inspection
    @State private var persistentDebugSrc: CGPoint? = nil
    @State private var persistentDebugTgt: CGPoint? = nil
    @State private var persistentDebugIsReal: Bool = false
    @State private var persistentDebugProgress: CGFloat = 0
    @State private var showingRestartAlert = false
    @State private var showingEventLog = false
    @State private var showingSettings = false
    @State private var showingDeveloperInfo = false
    @State private var latestRewindSnapshot: RewindSnapshot? = nil
    @State private var activeRewindSnapshot: RewindSnapshot? = nil
    @State private var rewindProgress: CGFloat = 0
    @State private var rewindGeneration: Int = 0
    @State private var starterSelectionState: StarterSelectionState? = nil
    @State private var starterSelectionGeneration: Int = 0
    @State private var activeCapturedPreview: CapturedPreviewState? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let safeSize = CGSize(
                width: geometry.size.width - safeArea.leading - safeArea.trailing,
                height: geometry.size.height - safeArea.top - safeArea.bottom
            )
            
            // Sync Game Size to Config
            let _ = config.updateGameSize(safeSize)
            
            mainGameContent(safeArea: safeArea, safeSize: safeSize)
        }
        .ignoresSafeArea()
        .onAppear { onAppearAction() }
        .onChange(of: config.layoutV2) { onChangeLayout($0) }
        .onChange(of: gameManager.players.first?.hand) { onChangeHand($0) }
        .onChange(of: gameManager.tableCards) { onChangeTable($0) }
        .onChange(of: gameManager.uxEventLogs.count) { _ in
            updateLatestRewindSnapshot()
        }
        .onChange(of: gameManager.eventLogs.count) { _ in
            specialEventPopupCoordinator.process(eventLogs: gameManager.eventLogs)
        }
        .onChange(of: gameManager.gameState) { _ in
            syncSpecialEventOverlayProbe()
            if !canShowCapturedPreview {
                dismissCapturedPreview()
            }
        }
        .onChange(of: specialEventPopupCoordinator.activePopup?.id) { _ in
            syncSpecialEventOverlayProbe()
            if !canShowCapturedPreview {
                dismissCapturedPreview()
            }
        }
        .onChange(of: specialEventPopupCoordinator.pendingQueueCount) { _ in
            syncSpecialEventOverlayProbe()
            if !canShowCapturedPreview {
                dismissCapturedPreview()
            }
        }
        .onChange(of: activeCapturedPreview) { _ in
            syncCapturedPreviewProbe()
        }
        .onChange(of: showingEventLog || showingSettings || showingDeveloperInfo) { isBlockingOverlayVisible in
            if isBlockingOverlayVisible {
                dismissCapturedPreview()
            }
        }
        .onChange(of: gameManager.players.map { $0.id.uuidString }.joined(separator: ",")) { _ in
            // Player IDs can rotate on restart/condition-set; clear stale geometry keys.
            tableCardCenters.removeAll()
            // Keep captured centers to avoid transient empty-target fallback jumps.
            // CapturedGroupsAreaV2 will upsert fresh owner keys on next layout pass.
            capturedCardCenters.removeAll()
            dismissCapturedPreview(animated: false)
        }
        .onReceive(gameManager.objectWillChange) { _ in
            // Slot managers can miss nested array mutations in long animation chains.
            // Resync from source-of-truth state on every GameManager change.
            DispatchQueue.main.async {
                self.resyncSlotManagers()
                if !self.canShowCapturedPreview {
                    self.dismissCapturedPreview()
                } else if self.activeCapturedPreview != nil {
                    self.syncCapturedPreviewProbe()
                }
            }
        }
    }

    @ViewBuilder
    private func mainGameContent(safeArea: EdgeInsets, safeSize: CGSize) -> some View {
        let layoutContext = config.layoutContext
        
        ZStack {
            // Global Background
            RadialGradient(gradient: Gradient(colors: [Color(red: 0.15, green: 0.55, blue: 0.25), Color(red: 0.05, green: 0.35, blue: 0.15)]), center: .center, startRadius: 50, endRadius: 600)
                .ignoresSafeArea()
            
            if let ctx = layoutContext {
                gameAreas(ctx: ctx, safeArea: safeArea)
                
                // Debug Overlay
                if config.layoutV2?.debug.showSafeArea == true || config.layoutV2?.debug.showGrid == true {
                    DebugLayoutOverlayV2(ctx: ctx)
                        .position(x: safeArea.leading + safeSize.width/2, y: safeArea.top + safeSize.height/2)
                        .allowsHitTesting(false)
                        .zIndex(100)
                }
            } else {
                ProgressView("Loading Layout V2...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.5))
            }
            
            // Overlays (Global)
            overlayArea
                .zIndex(200)
            
            // Turn Indicator Icon (Moving)
            turnIndicatorIcon(safeArea: safeArea)
                .zIndex(205)
            
            // Unified Moving Card Overlay (시각적 전용 - 사용자 탭 불필요)
            movingCardOverlay(safeArea: safeArea)
                .allowsHitTesting(false)
                .zIndex(210)

            // Debug rewind overlay (debug mode only, 시각적 전용)
            rewindOverlay(safeArea: safeArea)
                .allowsHitTesting(false)
                .zIndex(211)

            // ── PERSISTENT COORDINATE DEBUG OVERLAY (debug mode level3) ──
            persistentCoordDebugOverlay()
                .zIndex(300)
                .allowsHitTesting(false)

            // Keep rewind HUD as the top-most interactive layer in debug mode.
            moveRouteHUD(safeArea: safeArea)
                .zIndex(1000)

            // Always-available top controls (settings/exit/log/debug) above all overlays.
            if let ctx = layoutContext {
                topControlsArea(ctx: ctx, safeArea: safeArea)
                    .zIndex(2000)
            }
        }
        .coordinateSpace(name: "GameSpace")
        .alert("재시작 확인", isPresented: $showingRestartAlert) {
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) {
                restartManualGame()
            }
        } message: {
            Text("게임을 다시 시작하시겠습니까?")
        }
    }

    @ViewBuilder
    private func topControlsArea(ctx: LayoutContext, safeArea: EdgeInsets) -> some View {
        if let settingFrame = ctx.areaFrames[.setting], settingFrame.height > 0 {
            SettingAreaV2(
                ctx: ctx,
                config: ctx.config.areas.setting,
                onExitTapped: { showingRestartAlert = true },
                showRewindButton: isLevel3DebugMode,
                canRewind: canStartRewind,
                onRewindTapped: triggerRewindPlayback,
                onSettingsTapped: { showingSettings = true },
                onLogTapped: { showingEventLog.toggle() },
                onDeveloperInfoTapped: { showingDeveloperInfo = true }
            )
            .frame(width: settingFrame.width, height: settingFrame.height)
            .position(x: safeArea.leading + settingFrame.midX, y: safeArea.top + settingFrame.midY)
        }
    }

    @ViewBuilder
    private func gameAreas(ctx: LayoutContext, safeArea: EdgeInsets) -> some View {
        let isCapturedTransfer =
            gameManager.currentMoveSourceZone == "captured" &&
            gameManager.currentMoveTargetZone == "captured"
        let isTableToCaptured =
            gameManager.currentMoveSourceZone == "table" &&
            gameManager.currentMoveTargetZone == "captured"
        let sourceOwnerId = gameManager.capturedMoveSourcePlayerId
        let targetOwnerId = gameManager.capturedMoveTargetPlayerId
        let playerOwnerId = gameManager.players.first?.id.uuidString
        let opponentOwnerId = gameManager.players.count > 1 ? gameManager.players[1].id.uuidString : nil
        let tableToOpponentCapture = isTableToCaptured && targetOwnerId == opponentOwnerId
        let tableToPlayerCapture = isTableToCaptured && targetOwnerId == playerOwnerId
        let opponentZ: Double = tableToOpponentCapture ? 8 : (isCapturedTransfer && sourceOwnerId == opponentOwnerId ? 6 : 2)
        let playerZ: Double = tableToPlayerCapture ? 8 : (isCapturedTransfer && sourceOwnerId == playerOwnerId ? 6 : 3)
        let centerZ: Double = isTableToCaptured ? 7 : 1

        // 1. Opponent Area
        let opponentFrame = ctx.frame(for: .opponent)
        if isCapturedTransfer || isTableToCaptured {
            // Allow cross-area penalty card travel to remain visible end-to-end.
            OpponentAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                capturedGroupCenters: $capturedGroupCenters,
                capturedCardCenters: $capturedCardCenters,
                onGroupPreviewRequested: showCapturedPreview,
                onGroupPreviewEnded: endCapturedPreview
            )
                .frame(width: opponentFrame.width, height: opponentFrame.height)
                .position(x: safeArea.leading + opponentFrame.midX, y: safeArea.top + opponentFrame.midY)
                .zIndex(opponentZ)
        } else {
            OpponentAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                capturedGroupCenters: $capturedGroupCenters,
                capturedCardCenters: $capturedCardCenters,
                onGroupPreviewRequested: showCapturedPreview,
                onGroupPreviewEnded: endCapturedPreview
            )
                .frame(width: opponentFrame.width, height: opponentFrame.height)
                .clipped()
                .position(x: safeArea.leading + opponentFrame.midX, y: safeArea.top + opponentFrame.midY)
                .zIndex(opponentZ)
        }
        
        // 2. Center Area
        let centerFrame = ctx.frame(for: .center)
        if isTableToCaptured {
            CenterAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                tableSlotManager: tableSlotManager,
                tableCardCenters: $tableCardCenters,
                tableCardFaceUpResolver: isStarterSelectionActive ? { card in
                    isStarterTableCardFaceUp(card)
                } : nil,
                onTableCardTapped: isStarterSelectionActive ? { card in
                    handleStarterTableCardTapped(card)
                } : nil
            )
                .frame(width: centerFrame.width, height: centerFrame.height)
                .position(x: safeArea.leading + centerFrame.midX, y: safeArea.top + centerFrame.midY)
                .zIndex(centerZ)
        } else {
            CenterAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                tableSlotManager: tableSlotManager,
                tableCardCenters: $tableCardCenters,
                tableCardFaceUpResolver: isStarterSelectionActive ? { card in
                    isStarterTableCardFaceUp(card)
                } : nil,
                onTableCardTapped: isStarterSelectionActive ? { card in
                    handleStarterTableCardTapped(card)
                } : nil
            )
                .frame(width: centerFrame.width, height: centerFrame.height)
                .clipped()
                .position(x: safeArea.leading + centerFrame.midX, y: safeArea.top + centerFrame.midY)
                .zIndex(centerZ)
        }
        
        // 3. Player Area
        let playerFrame = ctx.frame(for: .player)
        if isCapturedTransfer || isTableToCaptured {
            PlayerAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                slotManager: playerHandSlotManager,
                capturedGroupCenters: $capturedGroupCenters,
                capturedCardCenters: $capturedCardCenters,
                onGroupPreviewRequested: showCapturedPreview,
                onGroupPreviewEnded: endCapturedPreview
            )
                .frame(width: playerFrame.width, height: playerFrame.height)
                .position(x: safeArea.leading + playerFrame.midX, y: safeArea.top + playerFrame.midY)
                .zIndex(playerZ)
        } else {
            PlayerAreaV2(
                ctx: ctx,
                animationNamespace: cardAnimationNamespace,
                gameManager: gameManager,
                slotManager: playerHandSlotManager,
                capturedGroupCenters: $capturedGroupCenters,
                capturedCardCenters: $capturedCardCenters,
                onGroupPreviewRequested: showCapturedPreview,
                onGroupPreviewEnded: endCapturedPreview
            )
                .frame(width: playerFrame.width, height: playerFrame.height)
                .clipped()
                .position(x: safeArea.leading + playerFrame.midX, y: safeArea.top + playerFrame.midY)
                .zIndex(playerZ)
        }
    }

    private func onAppearAction() {
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        specialEventPopupCoordinator.markExistingLogsProcessed(gameManager.eventLogs)
        #if targetEnvironment(simulator)
        if SimulatorBridge.shared == nil {
            // Keep simulator UI behavior aligned with real device by default.
            // Enable fast animation only when explicitly requested.
            if ProcessInfo.processInfo.environment["GOSTOP_SIM_FAST_ANIMATION"] == "1" {
                AnimationManager.shared.config.card_move_duration = 0
            }
            SimulatorBridge.shared = SimulatorBridge(gameManager: gameManager)
            SimulatorBridge.shared?.start()
            print("SimulatorBridge: Started on port 8080 (GameView)")
        }
        #endif
        if let configV2 = config.layoutV2 {
            self.playerHandSlotManager = PlayerHandSlotManager(config: configV2)
            self.tableSlotManager = TableSlotManager(config: configV2)
            self.resyncSlotManagers()
        }
        syncSpecialEventOverlayProbe()
        syncCapturedPreviewProbe()
        updateLatestRewindSnapshot()
    }

    private func onChangeLayout(_ newConfig: LayoutConfigV2?) {
        AnimationManager.shared.withGameAnimation {
            if let cfg = newConfig {
                 self.playerHandSlotManager = PlayerHandSlotManager(config: cfg)
                 self.tableSlotManager = TableSlotManager(config: cfg)
                 self.resyncSlotManagers()
            }
        }
    }

    private func onChangeHand(_ newHand: [Card]?) {
        AnimationManager.shared.withGameAnimation {
            guard let hand = newHand else { return }
            playerHandSlotManager?.sync(with: hand, compactToFront: !gameManager.isAutomationBusy)
        }
    }

    private func onChangeTable(_ newTableCards: [Card]) {
        AnimationManager.shared.withGameAnimation {
            tableSlotManager?.sync(with: newTableCards)
        }
    }

    // ── PERSISTENT COORD DEBUG: Level 3 visualization ──
    @ViewBuilder
    private func persistentCoordDebugOverlay() -> some View {
        if isLevel3DebugMode {
            ZStack {
                // Green dots at each table card center
                ForEach(Array(tableCardCenters.keys.sorted()), id: \.self) { cardId in
                    if let pt = tableCardCenters[cardId] {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.7))
                                .frame(width: 8, height: 8)
                            Text("T\nY:\(Int(pt.y))")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.green.opacity(0.85))
                                .cornerRadius(3)
                                .offset(x: 18, y: 0)
                        }
                        .position(x: pt.x, y: pt.y)
                    }
                }

                // Red dots at each captured group slot center
                ForEach(Array(capturedGroupCenters.keys.sorted()), id: \.self) { key in
                    if let pt = capturedGroupCenters[key] {
                        let label = key.components(separatedBy: ":").last ?? key
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 8, height: 8)
                            Text("C\n\(label)\nY:\(Int(pt.y))")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(3)
                                .offset(x: -20, y: 0)
                        }
                        .position(x: pt.x, y: pt.y)
                    }
                }

                // Mini status box (top-right corner)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("🟢T:\(tableCardCenters.count) 🔴C:\(capturedGroupCenters.count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                }
                .position(x: UIScreen.main.bounds.width - 60, y: 60)

                // Persistent panel: keep latest SRC/TGT + progress visible after animation ends.
                VStack(alignment: .leading, spacing: 1) {
                    Text("🔍 COORD DEBUG  p(progress)=\(String(format: "%.2f", persistentDebugProgress))")
                        .foregroundColor(.yellow)
                    Text("   p: 0.00(start) -> 1.00(end)")
                        .foregroundColor(.yellow.opacity(0.9))
                    Divider().background(Color.yellow)
                    if let src = persistentDebugSrc {
                        Text("🟢 SRC  Y:\(Int(src.y))  X:\(Int(src.x))")
                            .foregroundColor(.green)
                    } else {
                        Text("🟢 SRC  -")
                            .foregroundColor(.green.opacity(0.8))
                    }
                    Text("   \(persistentDebugIsReal ? "✅ GeometryReader (real)" : "⚠️ Math fallback")")
                        .foregroundColor(persistentDebugIsReal ? .green : .orange)
                    Divider().background(Color.red)
                    if let tgt = persistentDebugTgt {
                        Text("🔴 TGT  Y:\(Int(tgt.y))  X:\(Int(tgt.x))")
                            .foregroundColor(.red)
                    } else {
                        Text("🔴 TGT  -")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    Divider().background(Color.white)
                    Text("tableCardCenters.count=\(tableCardCenters.count)")
                    Text("capturedGroupCenters.count=\(capturedGroupCenters.count)")
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.6), lineWidth: 1))
                .frame(width: 240)
                .position(x: 130, y: 300)
            }
        }
    }

    @ViewBuilder
    private func moveRouteHUD(safeArea: EdgeInsets) -> some View {
        if isLevel3DebugMode, let event = latestMoveStartEvent() {
            let route = routeText(for: event)
            VStack(alignment: .leading, spacing: 4) {
                Text("moveStart route")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(route)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, safeArea.top + 6)
            .padding(.leading, safeArea.leading + 8)
            .allowsHitTesting(false)
        }
    }

    private func latestMoveStartEvent() -> UXEvent? {
        gameManager.uxEventLogs.reversed().first { $0.type == "moveStart" }
    }

    private var isAnimationDebugMode: Bool {
        #if DEBUG
        guard let debug = config.layoutV2?.debug else { return false }
        return debug.showGrid ||
        debug.showSafeArea ||
        debug.showElementBounds ||
        (debug.player?.handSlotGrid ?? false) ||
        (debug.player?.sortedOrderOverlay ?? false)
        #else
        return false
        #endif
    }

    private var currentDebugModeLevel: Int {
        config.layoutV2?.debug.normalizedDebugMode ?? 1
    }

    private var isLevel3DebugMode: Bool {
        #if DEBUG
        return isAnimationDebugMode && currentDebugModeLevel >= 3
        #else
        return false
        #endif
    }

    private var canStartRewind: Bool {
        isLevel3DebugMode &&
        latestRewindSnapshot != nil &&
        activeRewindSnapshot == nil
    }

    private func triggerRewindPlayback() {
        guard canStartRewind, let snapshot = latestRewindSnapshot else { return }
        activeRewindSnapshot = snapshot
        rewindGeneration += 1
        let generation = rewindGeneration
        rewindProgress = 1

        let duration = max(0.35, snapshot.duration)
        withAnimation(animationManager.animation(for: duration)) {
            rewindProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) {
            guard generation == self.rewindGeneration else { return }
            self.activeRewindSnapshot = nil
            self.rewindProgress = 0
        }
    }

    private func updateLatestRewindSnapshot() {
        let logs = gameManager.uxEventLogs
        latestRewindSnapshot = latestSupportedRewindSnapshot(in: logs)
    }

    private func latestSupportedRewindSnapshot(in logs: [UXEvent]) -> RewindSnapshot? {
        for moveEnd in logs.reversed() where moveEnd.type == "moveEnd" {
            guard let moveStart = matchingMoveStart(for: moveEnd, in: logs) else { continue }

            let sourceZone = moveStart.data["source"] ?? moveEnd.data["source"] ?? ""
            let targetZone = moveStart.data["target"] ?? moveEnd.data["target"] ?? ""
            guard supportsRewind(source: sourceZone, target: targetZone) else { continue }

            let ids = cardIds(from: moveEnd).isEmpty ? cardIds(from: moveStart) : cardIds(from: moveEnd)
            let cards = ids.compactMap(resolveCardById)
            guard !cards.isEmpty else { continue }

            let sourcePlayerId = moveStart.data["sourcePlayerId"] ?? moveEnd.data["sourcePlayerId"]
            let targetPlayerId = moveStart.data["targetPlayerId"] ?? moveEnd.data["targetPlayerId"]
            let rewindDuration = durationForRoute(source: sourceZone, target: targetZone)

            return RewindSnapshot(
                moveEndEventId: moveEnd.id,
                cards: cards,
                sourceZone: sourceZone,
                targetZone: targetZone,
                sourcePlayerId: sourcePlayerId,
                targetPlayerId: targetPlayerId,
                duration: rewindDuration
            )
        }
        return nil
    }

    private func supportsRewind(source: String, target: String) -> Bool {
        (source == "table" && target == "captured") ||
        (source == "captured" && target == "captured")
    }

    private func durationForRoute(source: String, target: String) -> Double {
        let plan = animationManager.motionPlan(source: source, target: target)
        let raw = plan.delay > 0 ? plan.delay : animationManager.config.card_move_duration
        // Keep rewind visible even when runtime animation is configured as instant/very fast.
        return max(0.35, min(1.1, raw))
    }

    private func matchingMoveStart(for moveEnd: UXEvent, in logs: [UXEvent]) -> UXEvent? {
        guard let endIndex = logs.lastIndex(where: { $0.id == moveEnd.id }) else {
            return logs.reversed().first { $0.type == "moveStart" }
        }
        guard endIndex > 0 else { return nil }

        let endCardIdSet = Set(cardIds(from: moveEnd))
        for index in stride(from: endIndex - 1, through: 0, by: -1) {
            let candidate = logs[index]
            guard candidate.type == "moveStart" else { continue }
            if endCardIdSet.isEmpty {
                return candidate
            }
            let startCardIdSet = Set(cardIds(from: candidate))
            if !startCardIdSet.isEmpty && !startCardIdSet.isDisjoint(with: endCardIdSet) {
                return candidate
            }
        }
        return nil
    }

    private func cardIds(from event: UXEvent) -> [String] {
        if let raw = event.data["cardIds"], !raw.isEmpty {
            return raw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let single = event.data["cardId"], !single.isEmpty {
            return [single]
        }
        return []
    }

    private func resolveCardById(_ cardId: String) -> Card? {
        if let moving = gameManager.currentMovingCards.first(where: { $0.id == cardId }) {
            return moving
        }
        if let table = gameManager.tableCards.first(where: { $0.id == cardId }) {
            return table
        }
        if let deck = gameManager.deck.cards.first(where: { $0.id == cardId }) {
            return deck
        }
        if let out = gameManager.outOfPlayCards.first(where: { $0.id == cardId }) {
            return out
        }
        for player in gameManager.players {
            if let hand = player.hand.first(where: { $0.id == cardId }) {
                return hand
            }
            if let captured = player.capturedCards.first(where: { $0.id == cardId }) {
                return captured
            }
        }
        return nil
    }

    private func routeText(for event: UXEvent) -> String {
        let source = event.data["source"] ?? "?"
        let target = event.data["target"] ?? "?"
        var route = "\(source)->\(target)"

        if source == "captured", target == "captured" {
            let fromName = playerName(for: event.data["sourcePlayerId"])
            let toName = playerName(for: event.data["targetPlayerId"])
            if let fromName, let toName {
                route += " (\(fromName)->\(toName))"
            }
        } else if target == "captured" {
            if let toName = playerName(for: event.data["targetPlayerId"]) {
                route += " (to:\(toName))"
            }
        }

        if let reason = event.data["reason"], !reason.isEmpty {
            route += " | \(reason)"
        }
        return route
    }

    private func playerName(for playerId: String?) -> String? {
        guard let playerId else { return nil }
        return gameManager.players.first(where: { $0.id.uuidString == playerId })?.name
    }

    private func resetSpecialEventPopups() {
        specialEventPopupCoordinator.reset()
    }

    private var shouldDeferEndedOverlayForSpecialEventPopups: Bool {
        guard gameManager.gameState == .ended else { return false }
        return specialEventPopupCoordinator.hasActiveOrPendingPopups
    }

    private var isDecisionOverlayState: Bool {
        switch gameManager.gameState {
        case .askingGoStop, .askingShake, .choosingCapture, .choosingChrysanthemumRole:
            return true
        case .ready, .playing, .ended:
            return false
        }
    }

    private var shouldDeferDecisionOverlayForSpecialEventPopups: Bool {
        guard isDecisionOverlayState else { return false }
        return specialEventPopupCoordinator.hasActiveOrPendingPopups
    }

    private func syncSpecialEventOverlayProbe() {
        gameManager.updateSpecialEventOverlayProbe(
            activePopupTitle: specialEventPopupCoordinator.activePopup?.title,
            pendingQueueCount: specialEventPopupCoordinator.pendingQueueCount,
            isEndSummaryDeferred: shouldDeferEndedOverlayForSpecialEventPopups,
            isDecisionOverlayDeferred: shouldDeferDecisionOverlayForSpecialEventPopups
        )
    }

    private func resyncSlotManagers() {
        if let hand = gameManager.players.first?.hand {
            playerHandSlotManager?.sync(with: hand, compactToFront: !gameManager.isAutomationBusy)
        }
        tableSlotManager?.sync(with: gameManager.tableCards)
    }
    
    // MARK: - Subviews

    
    @ViewBuilder
    var overlayArea: some View {
        ZStack {
            if gameManager.gameState == .ready {
                if let starterSelectionState {
                    starterSelectionOverlay(state: starterSelectionState)
                } else {
                    colorBackgroundOverlay(text: "Start Game", action: {
                        // Initial reload to ensure config is fresh
                        config.reloadConfig()
                        startManualGame()
                    })
                }
            } else if gameManager.gameState == .ended {
                if shouldDeferEndedOverlayForSpecialEventPopups {
                    Color.clear
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                } else
                if gameManager.gameEndReason == .chongtong {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Text("총통! (Chongtong)")
                                .font(.system(size: 60, weight: .black, design: .rounded))
                                .foregroundColor(.yellow)
                                .shadow(color: .orange, radius: 10, x: 0, y: 5)
                            
                            if let month = gameManager.chongtongMonth {
                                Text("\(month)월 총통으로 즉시 승리!")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: {
                                restartManualGame()
                            }) {
                                Text("Restart Game")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.yellow)
                                    .foregroundColor(.black)
                                    .cornerRadius(15)
                            }
                        }
                    }
                } else if gameManager.gameEndReason == .nagari {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Text("나가리! (Nagari)")
                                .font(.system(size: 60, weight: .black, design: .rounded))
                                .foregroundColor(.yellow)
                                .shadow(color: .orange, radius: 10, x: 0, y: 5)

                            Text("무승부로 종료되었습니다.")
                                .font(.title)
                                .foregroundColor(.white)

                            Button(action: {
                                restartManualGame()
                            }) {
                                Text("Restart Game")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.yellow)
                                    .foregroundColor(.black)
                                    .cornerRadius(15)
                            }
                        }
                    }
                } else if config.layoutV2?.debug.showSafeArea == true,
                   let result = gameManager.lastPenaltyResult,
                   let reason = gameManager.gameEndReason,
                   let winner = gameManager.gameWinner,
                   let loser = gameManager.gameLoser {
                    
                    DebugEndgameSummaryView(
                        result: result,
                        reason: reason,
                        winner: winner,
                        loser: loser,
                        onRestart: {
                            restartManualGame()
                        },
                        gameManager: gameManager
                    )
                } else {
                    colorBackgroundOverlay(text: "Game Over\nTap to Restart", action: {
                        restartManualGame()
                    })
                }
            } else if shouldDeferDecisionOverlayForSpecialEventPopups {
                // Keep decision input blocked until transient event popups finish
                // so the user never sees overlapping modal surfaces.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
            } else if gameManager.gameState == .askingGoStop {
                goStopOverlay()
            } else if gameManager.gameState == .askingShake {
                shakeOverlay()
            } else if gameManager.gameState == .choosingCapture {
                captureChoiceOverlay()
            } else if gameManager.gameState == .choosingChrysanthemumRole {
                chrysanthemumChoiceOverlay()
            }

            capturedPreviewOverlay()
            
            if showingEventLog {
                EventLogView(eventLogs: gameManager.eventLogs, isPresented: $showingEventLog)
            }
            
            if showingSettings {
                RuleSettingsView(isPresented: $showingSettings)
            }

            if showingDeveloperInfo {
                DeveloperInfoView(isPresented: $showingDeveloperInfo)
            }

            specialEventPopupOverlay()
        }
        // StarterSelection 중에는 overlayArea ZStack이 테이블 카드 위에 zIndex(200)으로 올라가 있어
        // 터치를 차단한다. isStarterSelectionActive 상태에서는 hit-testing을 비활성화해
        // 터치가 아래의 테이블 카드(CenterAreaV2)까지 전달되도록 한다.
        .allowsHitTesting(!isStarterSelectionActive)
    }

    @ViewBuilder
    private func specialEventPopupOverlay() -> some View {
        if let popup = specialEventPopupCoordinator.activePopup {
            SpecialEventPopupView(popup: popup)
        }
    }

    @ViewBuilder
    private func capturedPreviewOverlay() -> some View {
        if canShowCapturedPreview,
           let preview = activeCapturedPreview,
           let ctx = config.layoutContext,
           let model = resolvedCapturedPreviewModel(for: preview) {
            CapturedPreviewPanel(ctx: ctx, model: model) {
                dismissCapturedPreview()
            }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func turnIndicatorIcon(safeArea: EdgeInsets) -> some View {
        if let ctx = config.layoutContext, gameManager.gameState == .playing {
            let isPlayerTurn = gameManager.currentTurnIndex == 0
            let targetArea: LayoutContext.AreaType = isPlayerTurn ? .player : .opponent
            let frame = ctx.frame(for: targetArea)
            
            let yOffset: CGFloat = isPlayerTurn ? -40 : 40
            
            Image(systemName: "hand.point.right.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.yellow)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.6)))
                .shadow(radius: 4)
                .rotationEffect(Angle(degrees: isPlayerTurn ? 90 : -90))
                .position(
                    x: safeArea.leading + frame.midX,
                    y: safeArea.top + frame.midY + yOffset
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: gameManager.currentTurnIndex)
        }
    }

    private var isStarterSelectionActive: Bool {
        starterSelectionState != nil
    }

    private var canShowCapturedPreview: Bool {
        guard gameManager.gameState == .playing else { return false }
        guard gameManager.currentMovingCards.isEmpty else { return false }
        guard !showingEventLog, !showingSettings, !showingDeveloperInfo else { return false }
        guard !specialEventPopupCoordinator.hasActiveOrPendingPopups else { return false }
        return true
    }

    private func showCapturedPreview(ownerPlayerId: String, groupType: String) {
        let nextState = CapturedPreviewState(ownerPlayerId: ownerPlayerId, groupType: groupType)
        guard canShowCapturedPreview else { return }
        guard resolvedCapturedPreviewModel(for: nextState) != nil else { return }
        if activeCapturedPreview == nextState { return }
        withAnimation(.easeOut(duration: 0.16)) {
            activeCapturedPreview = nextState
        }
    }

    private func endCapturedPreview(ownerPlayerId: String, groupType: String) {
        guard activeCapturedPreview == CapturedPreviewState(ownerPlayerId: ownerPlayerId, groupType: groupType) else { return }
        dismissCapturedPreview()
    }

    private func dismissCapturedPreview(animated: Bool = true) {
        guard activeCapturedPreview != nil else {
            syncCapturedPreviewProbe()
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                activeCapturedPreview = nil
            }
        } else {
            activeCapturedPreview = nil
        }
    }

    private func syncCapturedPreviewProbe() {
        guard let preview = activeCapturedPreview,
              let model = resolvedCapturedPreviewModel(for: preview) else {
            gameManager.updateCapturedPreviewProbe(ownerPlayerId: nil, groupType: nil, cardCount: 0)
            return
        }
        gameManager.updateCapturedPreviewProbe(
            ownerPlayerId: preview.ownerPlayerId,
            groupType: preview.groupType,
            cardCount: model.cards.count
        )
    }

    private func previewOwnerPlayer(for ownerPlayerId: String) -> Player? {
        gameManager.players.first { $0.id.uuidString == ownerPlayerId }
    }

    private func previewGroupConfigs(for ownerPlayerId: String) -> [CapturedGroupConfigV2] {
        guard let ctx = config.layoutContext else { return [] }
        let playerOwnerId = gameManager.players.first?.id.uuidString
        let capturedConfig = ownerPlayerId == playerOwnerId
            ? ctx.config.areas.player.elements.captured
            : ctx.config.areas.opponent.elements.captured
        return capturedConfig.layout.groups ?? []
    }

    private func resolvedCapturedPreviewModel(for preview: CapturedPreviewState) -> CapturedPreviewModel? {
        guard let owner = previewOwnerPlayer(for: preview.ownerPlayerId) else { return nil }
        let groups = previewGroupConfigs(for: preview.ownerPlayerId)
        guard !groups.isEmpty else { return nil }
        let groupedCards = CapturedCardGrouping.groupedSortedCards(from: owner.capturedCards)

        let summaries = groups.map { group in
            CapturedPreviewGroupSummary(
                type: group.type,
                label: group.label,
                accentColor: group.background.colorSwiftUI,
                count: groupedCards[group.type, default: []].count
            )
        }
        let selectedCards = groupedCards[preview.groupType, default: []]
        guard !selectedCards.isEmpty else { return nil }
        guard let selectedGroup = groups.first(where: { $0.type == preview.groupType }) else { return nil }

        let playerOwnerId = gameManager.players.first?.id.uuidString
        let ownerTitle = preview.ownerPlayerId == playerOwnerId
            ? "내 획득패"
            : "\(owner.name) 획득패"

        return CapturedPreviewModel(
            ownerTitle: ownerTitle,
            selectedLabel: selectedGroup.label,
            selectedType: selectedGroup.type,
            cards: selectedCards,
            groups: summaries
        )
    }

    private func startManualGame() {
        dismissCapturedPreview(animated: false)
        resetSpecialEventPopups()
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        // StarterSelection(밤일낮장 선 정하기)은 현재 비활성화됨.
        // rule.yaml의 starter.enabled=false가 configuration.yaml cached 설정에 의해 override되는 문제로
        // 직접 여기서 스킵 처리. 재활성화 시 아래 주석을 해제하고 이 줄을 제거.
        // if let starterRule = starterRuleForManualStart() {
        //     beginStarterSelection(rule: starterRule)
        //     return
        // }
        resetStarterSelectionState()
        gameManager.startGame()
    }

    private func restartManualGame() {
        let previousWinnerIndex = gameManager.previousRoundWinnerIndex()
        dismissCapturedPreview(animated: false)
        resetSpecialEventPopups()
        resetStarterSelectionState()
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        gameManager.setupGame()
        gameManager.startGame(initialTurnIndex: previousWinnerIndex)
    }

    private func starterRuleForManualStart() -> StarterRule? {
        guard let starterRule = RuleLoader.shared.config?.starter,
              starterRule.enabled,
              starterRule.mode == "night_day" else {
            return nil
        }
        if starterRule.first_launch_only &&
            ConfigurationStore.shared.firstLaunchStarterApplied() {
            return nil
        }
        return starterRule
    }

    private func beginStarterSelection(rule: StarterRule) {
        resetStarterSelectionState()
        let cardIds = gameManager.tableCards.map { $0.id }
        guard cardIds.count >= 2 else {
            let fallbackStarter = gameManager.resolveNightDayStarterIndex(
                dayStartHour: rule.day_start_hour,
                dayEndHour: rule.day_end_hour
            )
            finalizeStarterSelection(starterIndex: fallbackStarter, rule: rule)
            return
        }

        starterSelectionState = StarterSelectionState(
            phase: .playerPick,
            rule: rule,
            remainingCardIds: cardIds,
            revealedCardIds: [],
            playerCardId: nil,
            opponentCardId: nil,
            statusText: "\(starterModeLabel(for: rule)) 규칙: 테이블 카드에서 한 장을 선택하세요."
        )
    }

    private func resetStarterSelectionState() {
        starterSelectionGeneration += 1
        starterSelectionState = nil
    }

    private func finalizeStarterSelection(starterIndex: Int, rule: StarterRule) {
        if rule.first_launch_only {
            _ = ConfigurationStore.shared.setFirstLaunchStarterApplied(true)
        }
        resetStarterSelectionState()
        gameManager.startGame(initialTurnIndex: starterIndex)
    }

    private func isStarterTableCardFaceUp(_ card: Card) -> Bool {
        guard let state = starterSelectionState else { return true }
        if state.phase == .revealAll {
            return true
        }
        return state.revealedCardIds.contains(card.id)
    }

    private func monthForTableCard(id: String?) -> Int? {
        guard let id else { return nil }
        return gameManager.tableCards.first(where: { $0.id == id })?.month.rawValue
    }

    private func starterModeLabel(for rule: StarterRule) -> String {
        let isDaytime = gameManager.isNightDayStarterDaytime(
            dayStartHour: rule.day_start_hour,
            dayEndHour: rule.day_end_hour
        )
        return isDaytime ? "낮장" : "밤일"
    }

    private func handleStarterTableCardTapped(_ card: Card) {
        guard var state = starterSelectionState, state.phase == .playerPick else { return }
        guard state.remainingCardIds.contains(card.id) else { return }

        let opponentCandidates = state.remainingCardIds.filter { $0 != card.id }
        guard let opponentCardId = opponentCandidates.randomElement() else {
            let fallbackStarter = gameManager.resolveNightDayStarterIndex(
                dayStartHour: state.rule.day_start_hour,
                dayEndHour: state.rule.day_end_hour
            )
            finalizeStarterSelection(starterIndex: fallbackStarter, rule: state.rule)
            return
        }

        state.playerCardId = card.id
        state.opponentCardId = opponentCardId
        state.revealedCardIds = [card.id, opponentCardId]
        state.phase = .resolving

        guard let playerMonth = monthForTableCard(id: card.id),
              let opponentMonth = monthForTableCard(id: opponentCardId) else {
            let fallbackStarter = gameManager.resolveNightDayStarterIndex(
                dayStartHour: state.rule.day_start_hour,
                dayEndHour: state.rule.day_end_hour
            )
            finalizeStarterSelection(starterIndex: fallbackStarter, rule: state.rule)
            return
        }

        let modeLabel = starterModeLabel(for: state.rule)
        let winnerIndex = gameManager.resolveNightDayStarterWinner(
            playerOneMonth: playerMonth,
            playerTwoMonth: opponentMonth,
            dayStartHour: state.rule.day_start_hour,
            dayEndHour: state.rule.day_end_hour
        )

        let generation = starterSelectionGeneration
        if let winnerIndex {
            state.phase = .revealAll
            state.revealedCardIds = Set(gameManager.tableCards.map { $0.id })
            let winnerName = gameManager.players.indices.contains(winnerIndex)
                ? gameManager.players[winnerIndex].name
                : "Player \(winnerIndex + 1)"
            state.statusText = "\(modeLabel) 결과: \(winnerName) 선 (\(playerMonth)월 vs \(opponentMonth)월)"
            starterSelectionState = state

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                guard generation == starterSelectionGeneration else { return }
                finalizeStarterSelection(starterIndex: winnerIndex, rule: state.rule)
            }
            return
        }

        let usedIds = Set([card.id, opponentCardId])
        state.remainingCardIds.removeAll { usedIds.contains($0) }
        state.statusText = "\(modeLabel) 동월 무승부 (\(playerMonth)월). 다시 선택합니다."
        starterSelectionState = state

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == starterSelectionGeneration, var nextState = starterSelectionState else { return }
            if nextState.remainingCardIds.count < 2 {
                let fallbackStarter = gameManager.resolveNightDayStarterIndex(
                    dayStartHour: nextState.rule.day_start_hour,
                    dayEndHour: nextState.rule.day_end_hour
                )
                finalizeStarterSelection(starterIndex: fallbackStarter, rule: nextState.rule)
                return
            }
            nextState.phase = .playerPick
            nextState.revealedCardIds = []
            nextState.playerCardId = nil
            nextState.opponentCardId = nil
            nextState.statusText = "\(starterModeLabel(for: nextState.rule)) 규칙: 테이블 카드에서 한 장을 선택하세요."
            starterSelectionState = nextState
        }
    }

    @ViewBuilder
    private func starterSelectionOverlay(state: StarterSelectionState) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("선 정하기: \(starterModeLabel(for: state.rule))")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Text(state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                if let playerMonth = monthForTableCard(id: state.playerCardId),
                   let opponentMonth = monthForTableCard(id: state.opponentCardId) {
                    Text("내 카드 \(playerMonth)월 / 상대 카드 \(opponentMonth)월")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(12)
            .frame(maxWidth: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.72)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 8)
            .padding(.top, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    func captureChoiceOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("어느 카드를 먹을까요?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                HStack(spacing: 40) {
                    ForEach(gameManager.pendingCaptureOptions, id: \.id) { option in
                        Button(action: {
                            gameManager.respondToCapture(selectedCard: option)
                        }) {
                            VStack(spacing: 10) {
                                // Real hanafuda card image via CardView
                                CardView(card: option, scale: 1.6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                option.type == .doubleJunk ? Color.yellow :
                                                option.type == .bright     ? Color.orange :
                                                Color.white.opacity(0.4),
                                                lineWidth: 3
                                            )
                                    )
                                
                                Text(cardTypeLabel(for: option))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(cardTypeLabelColor(for: option))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(cardTypeLabelColor(for: option).opacity(0.2))
                                    )
                            }
                        }
                    }
                }
                
                Text("탭하여 선택하세요")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    func chrysanthemumChoiceOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 30) {
                Text("국진(9월 열끗)의 역할을 선택하세요")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                if let card = gameManager.pendingChrysanthemumCard {
                    HStack(spacing: 50) {
                        // Option 1: Animal
                        Button(action: {
                            gameManager.respondToChrysanthemumChoice(role: .animal)
                        }) {
                            VStack(spacing: 12) {
                                CardView(card: card, scale: 1.8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.cyan, lineWidth: 4)
                                    )
                                
                                Text("끗 (Animal)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.cyan.opacity(0.4)))
                            }
                        }
                        
                        // Option 2: Double Pi
                        Button(action: {
                            gameManager.respondToChrysanthemumChoice(role: .doublePi)
                        }) {
                            VStack(spacing: 12) {
                                CardView(card: card, scale: 1.8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.yellow, lineWidth: 4)
                                    )
                                
                                Text("쌍피 (Double Pi)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.yellow.opacity(0.4)))
                            }
                        }
                    }
                }
                
                Text("역할에 따라 점수 계산이 달라집니다")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }


    private func shakePreviewCards(for month: Int) -> [Card] {
        guard let currentPlayer = gameManager.currentPlayer else { return [] }
        return currentPlayer.hand
            .filter { $0.month.rawValue == month }
            .sorted { lhs, rhs in
                let lhsRank = shakeCardSortRank(for: lhs.type)
                let rhsRank = shakeCardSortRank(for: rhs.type)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.imageIndex != rhs.imageIndex {
                    return lhs.imageIndex < rhs.imageIndex
                }
                return lhs.id < rhs.id
            }
    }

    private func shakeCardSortRank(for type: CardType) -> Int {
        switch type {
        case .bright:
            return 0
        case .animal:
            return 1
        case .ribbon:
            return 2
        case .doubleJunk:
            return 3
        case .junk:
            return 4
        case .dummy:
            return 5
        }
    }

    private var projectedShakeMultiplier: Int {
        let projectedShakeCount = (gameManager.currentPlayer?.shakeCount ?? 0) + 1
        return 1 << projectedShakeCount
    }

    @ViewBuilder
    func shakeOverlay() -> some View {
        if let month = gameManager.pendingShakeMonths.first {
            let previewCards = shakePreviewCards(for: month)
            let selectedShakeCardId = gameManager.pendingShakeCard?.id

            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("\(month)월 흔들기")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("손패에서 같은 월 카드 \(previewCards.count)장을 확인했습니다.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))

                    if !previewCards.isEmpty {
                        ShakePreviewCardsPanel(
                            previewCards: previewCards,
                            selectedShakeCardId: selectedShakeCardId
                        )
                    }

                    Text("흔들면 점수 배수가 x\(projectedShakeMultiplier)로 올라갑니다.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.82))
                    
                    HStack(spacing: 40) {
                        Button(action: {
                            gameManager.respondToShake(month: month, didShake: true)
                        }) {
                            Text("흔들기")
                                .font(.title)
                                .bold()
                                .frame(width: 150, height: 70)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                                .shadow(radius: 5)
                        }
                        
                        Button(action: {
                            gameManager.respondToShake(month: month, didShake: false)
                        }) {
                            Text("그냥 하기")
                                .font(.title)
                                .bold()
                                .frame(width: 150, height: 70)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func goStopOverlay() -> some View {
        let currentGoCount = (gameManager.currentPlayer?.goCount ?? 0) + 1
        let goCountText = "\(currentGoCount)고"
        let playerName = gameManager.currentPlayer?.name ?? "플레이어"
        let isHuman = !(gameManager.currentPlayer?.isComputer ?? false)
        
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(goCountText)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .shadow(color: .orange, radius: 10)
                
                HStack(spacing: 8) {
                    Image(systemName: isHuman ? "person.fill" : "desktopcomputer")
                        .foregroundStyle(isHuman ? .green : .orange)
                    Text("\(playerName)이(가) 고 중입니다")
                        .fontWeight(.semibold)
                        .foregroundStyle(isHuman ? .green : .orange)
                }
                .font(.title3)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.white.opacity(0.15))
                .cornerRadius(20)
                
                Text("점수가 났습니다! 고 또는 스탑을 선택하세요.")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 40) {
                    Button(action: {
                        gameManager.respondToGoStop(isGo: true)
                    }) {
                        VStack(spacing: 4) {
                            Text("GO")
                                .font(.title)
                                .bold()
                            Text(goCountText)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(width: 130, height: 70)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                    }
                    
                    Button(action: {
                        gameManager.respondToGoStop(isGo: false)
                    }) {
                        Text("STOP")
                            .font(.title)
                            .bold()
                            .frame(width: 130, height: 70)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                }
            }
        }
    }

    
    private func cardTypeLabel(for card: Card) -> String {
        switch card.type {
        case .bright:     return "🌟 광 (3pt+)"
        case .animal:     return "🐦 끗 (+1)"
        case .ribbon:     return "🎀 띠 (+1)"
        case .doubleJunk: return "⭐️ 쌍피 (+2)"
        case .junk:       return "피 (+1)"
        default:          return card.type.rawValue
        }
    }
    
    private func cardTypeLabelColor(for card: Card) -> Color {
        switch card.type {
        case .bright:     return .orange
        case .animal:     return .cyan
        case .ribbon:     return .pink
        case .doubleJunk: return .yellow
        default:          return .white.opacity(0.9)
        }
    }

    func colorBackgroundOverlay(text: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack {
                Button(action: action) {
                    Text(text)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 15).fill(Color.blue))
                }
            }
        }
    }
}

#Preview {
    GameView()
        .ignoresSafeArea()
}

struct EventLogView: View {
    let eventLogs: [String]
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("최근 이벤트 (화투 Log)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.8))
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if eventLogs.isEmpty {
                            Text("로그가 없습니다.")
                                .foregroundColor(.white.opacity(0.5))
                                .padding()
                        } else {
                            ForEach(eventLogs.reversed(), id: \.self) { log in
                                Text(log)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle()) // Make the whole frame clickable for context menu
                                    .contextMenu {
                                        Button(action: {
                                            UIPasteboard.general.string = eventLogs.reversed().joined(separator: "\n")
                                        }) {
                                            Label("전체 Text 복사", systemImage: "doc.on.doc")
                                        }
                                        
                                        Button(action: {
                                            UIPasteboard.general.string = log
                                        }) {
                                            Label("이 라인 복사", systemImage: "doc.on.clipboard")
                                        }
                                    }
                                Divider()
                                    .background(Color.white.opacity(0.2))
                            }
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: 500, maxHeight: 600)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 20)
            .padding(40)
        }
    }
}

struct DeveloperInfoView: View {
    @Binding var isPresented: Bool

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "-"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "-"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("개발자 정보")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Antigravity GoStop")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("앱 버전")
                            .foregroundColor(.white.opacity(0.75))
                        Text(appVersionText)
                            .foregroundColor(.white)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxWidth: 420)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 20)
            .padding(40)
        }
    }
}

extension GameView {
    private func movingCardOverlay(safeArea: EdgeInsets) -> some View {
        let sourceZone = gameManager.currentMoveSourceZone
        let targetZone = gameManager.currentMoveTargetZone

        if sourceZone == "table",
           targetZone == "captured",
           let targetId = gameManager.capturedMoveTargetPlayerId {
            return AnyView(tableToCapturedOverlay(targetPlayerId: targetId, safeArea: safeArea))
        }

        if sourceZone == "captured",
           targetZone == "captured",
           let sourceId = gameManager.capturedMoveSourcePlayerId,
           let targetId = gameManager.capturedMoveTargetPlayerId {
            return AnyView(capturedToCapturedOverlay(sourceId: sourceId, targetId: targetId, safeArea: safeArea))
        }

        return AnyView(defaultMovingCardOverlay())
    }

    @ViewBuilder
    private func rewindOverlay(safeArea: EdgeInsets) -> some View {
        if isLevel3DebugMode, let snapshot = activeRewindSnapshot {
            let p = CGFloat(max(0, min(1, rewindProgress)))
            let center = CGPoint(x: safeArea.leading + config.gameSize.width / 2, y: safeArea.top + config.gameSize.height / 2)
            let movingCards = Array(snapshot.cards.enumerated())

            let trajectories: [(card: Card, position: CGPoint)] = movingCards.compactMap { index, card in
                let start = rewindAnchorPoint(
                    for: snapshot.sourceZone,
                    card: card,
                    ownerId: snapshot.sourcePlayerId,
                    safeArea: safeArea
                ) ?? center
                let end = rewindAnchorPoint(
                    for: snapshot.targetZone,
                    card: card,
                    ownerId: snapshot.targetPlayerId,
                    safeArea: safeArea
                ) ?? center

                let sourceX = start.x + (snapshot.sourceZone == "captured" ? CGFloat(index) * 6 : 0)
                let targetX = end.x + (snapshot.targetZone == "captured" ? CGFloat(index) * 6 : 0)
                let x = sourceX + (targetX - sourceX) * p
                let y = start.y + (end.y - start.y) * p
                return (card, CGPoint(x: x, y: y))
            }

            ZStack {
                ForEach(Array(trajectories.enumerated()), id: \.element.card.id) { _, entry in
                    movingOverlayCard(entry.card, namespace: nil)
                        .position(x: entry.position.x, y: entry.position.y)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func rewindAnchorPoint(for zone: String, card: Card, ownerId: String?, safeArea: EdgeInsets) -> CGPoint? {
        switch zone {
        case "table":
            return tableAnchorPoint(for: card.id, safeArea: safeArea)
        case "captured":
            guard let ownerId else { return nil }
            return capturedAnchorPoint(for: card, ownerId: ownerId, safeArea: safeArea)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func tableToCapturedOverlay(targetPlayerId: String, safeArea: EdgeInsets) -> some View {
        let p = CGFloat(max(0, min(1, gameManager.penaltyMoveProgress)))
        let movingCards = Array(gameManager.currentMovingCards.enumerated())

        // Build trajectory with debug info
        var srcPoints: [CGPoint] = []
        var tgtPoints: [CGPoint] = []
        var usedRealCoords: [Bool] = []
        let trajectories: [(card: Card, position: CGPoint)] = movingCards.compactMap { index, card in
            let usedReal = tableCardCenters[card.id] != nil
            let sourcePoint: CGPoint
            if let realSource = tableAnchorPoint(for: card.id, safeArea: safeArea) {
                sourcePoint = realSource
            } else {
                let centerFallback = CGPoint(
                    x: safeArea.leading + config.gameSize.width / 2,
                    y: safeArea.top + config.gameSize.height / 2
                )
                print("⚠️ [tableAnchorPoint] NIL for \(card.id). Using screen-center fallback -> \(centerFallback)")
                sourcePoint = centerFallback
            }
            let fallbackTargetCenter = CGPoint(x: safeArea.leading + config.gameSize.width/2, y: safeArea.top + config.gameSize.height/2)
            let targetPtObj = capturedAnchorPoint(for: card.id, ownerId: targetPlayerId, safeArea: safeArea) ?? fallbackTargetCenter
            let targetX = targetPtObj.x + CGFloat(index) * 6
            let targetY = targetPtObj.y
            srcPoints.append(sourcePoint)
            tgtPoints.append(CGPoint(x: targetX, y: targetY))
            usedRealCoords.append(usedReal)
            let x = sourcePoint.x + (targetX - sourcePoint.x) * p
            let y = sourcePoint.y + (targetY - sourcePoint.y) * p
            logMonth6TableToCapturedTrace(
                card: card,
                index: index,
                progress: p,
                sourcePoint: sourcePoint,
                targetPoint: CGPoint(x: targetX, y: targetY),
                currentPoint: CGPoint(x: x, y: y),
                usedRealSource: usedReal,
                targetPlayerId: targetPlayerId
            )
            return (card, CGPoint(x: x, y: y))
        }

        ZStack {
            // ── Actual moving cards ──
            ForEach(Array(trajectories.enumerated()), id: \.element.card.id) { _, entry in
                movingOverlayCard(entry.card, namespace: nil)
                    .position(x: entry.position.x, y: entry.position.y)
            }

            // ── DEBUG: Source dot (green) + Target dot (red) ──
            if isLevel3DebugMode {
                ForEach(0..<srcPoints.count, id: \.self) { i in
                    // Green = source position (GameAreaViews.swift updateTableCardCenters)
                    ZStack {
                        Circle().fill(Color.green.opacity(0.9)).frame(width: 12, height: 12)
                        Text("S\(i)\nY:\(Int(srcPoints[i].y))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(2)
                            .background(Color.green.opacity(0.85))
                            .cornerRadius(3)
                            .offset(x: 28, y: 0)
                    }
                    .position(x: srcPoints[i].x, y: srcPoints[i].y)
                    .allowsHitTesting(false)

                    // Red = target position (GameView.swift capturedAnchorPoint)
                    ZStack {
                        Circle().fill(Color.red.opacity(0.9)).frame(width: 12, height: 12)
                        Text("T\(i)\nY:\(Int(tgtPoints[i].y))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(3)
                            .offset(x: -28, y: 0)
                    }
                    .position(x: tgtPoints[i].x, y: tgtPoints[i].y)
                    .allowsHitTesting(false)
                }
            }

        }
    }

    @ViewBuilder
    private func capturedToCapturedOverlay(sourceId: String, targetId: String, safeArea: EdgeInsets) -> some View {
        let p = CGFloat(max(0, min(1, gameManager.penaltyMoveProgress)))
        let movingCards = Array(gameManager.currentMovingCards.enumerated())

        let trajectories: [(card: Card, position: CGPoint)] = movingCards.compactMap { index, card in
            let center = CGPoint(x: safeArea.leading + config.gameSize.width/2, y: safeArea.top + config.gameSize.height/2)
            let startP = capturedAnchorPoint(for: card.id, ownerId: sourceId, safeArea: safeArea) ?? center
            let endP = capturedAnchorPoint(for: card.id, ownerId: targetId, safeArea: safeArea) ?? center
            
            let x = startP.x + (endP.x - startP.x) * p
            let y = startP.y + (endP.y - startP.y) * p
            return (card, CGPoint(x: x, y: y))
        }

        ZStack {
            ForEach(Array(trajectories.enumerated()), id: \.element.card.id) { _, entry in
                movingOverlayCard(entry.card, namespace: nil)
                .position(x: entry.position.x, y: entry.position.y)
            }
        }
    }

    @ViewBuilder
    private func defaultMovingCardOverlay() -> some View {
        ZStack {
            ForEach(gameManager.currentMovingCards) { card in
                movingOverlayCard(card, namespace: cardAnimationNamespace)
            }
        }
    }

    private func movingOverlayCard(_ card: Card, namespace: Namespace.ID?) -> some View {
        CardView(
            card: card,
            isFaceUp: true,
            scale: gameManager.movingCardsScale,
            animationNamespace: namespace,
            isSource: false,
            piCount: gameManager.movingCardsPiCount,
            showDebugInfo: gameManager.movingCardsShowDebug
        )
        .overlay {
            if isLevel3DebugMode {
                GeometryReader { geo in
                    let pt = geo.frame(in: .named("GameSpace")).center
                    VStack {
                        Spacer()
                        Text("X:\(Int(pt.x)) Y:\(Int(pt.y))")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(3)
                            .offset(y: 20) // Place it slightly below the card
                    }
                }
            }
        }
        .transition(.identity)
    }

    private func capturedAnchorPoint(for cardId: String, ownerId: String, safeArea: EdgeInsets) -> CGPoint? {
        guard let card = capturedCardForAnchor(cardId: cardId, ownerId: ownerId) else { return nil }
        return capturedAnchorPoint(for: card, ownerId: ownerId, safeArea: safeArea)
    }

    private func capturedAnchorPoint(for card: Card, ownerId: String, safeArea: EdgeInsets) -> CGPoint? {
        let targetType = capturedGroupType(for: card)
        let key = "\(ownerId):\(targetType)"

        // Priority 0: exact card center in captured area (best for table->captured direct path)
        let exactCardKey = CapturedCardCenterKey.make(ownerPlayerId: ownerId, cardId: card.id)
        if let cardCenter = capturedCardCenters[exactCardKey] {
            return cardCenter
        }

        // Priority 1: Use real screen-space center captured by GeometryReader at render time
        if let realCenter = capturedGroupCenters[key] {
            return realCenter
        }

        // Priority 2: If owner-specific key is stale/missing, reuse closest same-group center.
        let fallbackCenter = capturedFallbackCenter(ownerId: ownerId, safeArea: safeArea)
        let suffix = ":\(targetType)"
        let sameGroupCenters = capturedGroupCenters.compactMap { entry -> CGPoint? in
            entry.key.hasSuffix(suffix) ? entry.value : nil
        }
        if !sameGroupCenters.isEmpty {
            if let fallbackCenter {
                let best = sameGroupCenters.min { a, b in
                    squaredDistance(a, fallbackCenter) < squaredDistance(b, fallbackCenter)
                }
                if let best {
                    return best
                }
            } else if let guessed = sameGroupCenters.first {
                return guessed
            }
        }

        return fallbackCenter
    }

    private func capturedFallbackCenter(ownerId: String, safeArea: EdgeInsets) -> CGPoint? {
        guard let ctx = config.layoutContext else { return nil }
        let isPlayer = gameManager.players.first?.id.uuidString == ownerId
        let frame = isPlayer ? ctx.frame(for: .player) : ctx.frame(for: .opponent)
        let capConfig = isPlayer ? ctx.config.areas.player.elements.captured : ctx.config.areas.opponent.elements.captured
        let baseCenterX = safeArea.leading + frame.minX + frame.width * capConfig.x
        let baseCenterY: CGFloat
        if isPlayer {
            baseCenterY = safeArea.top + frame.minY + frame.height * capConfig.y
        } else {
            let cardHeight = ctx.cardSize.height * capConfig.scale
            let desiredY = frame.height * capConfig.y
            let halfHeight = cardHeight / 2.0
            let padding = ctx.scaledTokens.panelPadding
            let maxY = frame.height - halfHeight - (padding / 2)
            baseCenterY = safeArea.top + frame.minY + min(desiredY, maxY)
        }
        return CGPoint(x: baseCenterX, y: baseCenterY)
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private func capturedCardForAnchor(cardId: String, ownerId: String) -> Card? {
        if let owner = gameManager.players.first(where: { $0.id.uuidString == ownerId }),
           let card = owner.capturedCards.first(where: { $0.id == cardId }) {
            return card
        }
        return gameManager.currentMovingCards.first(where: { $0.id == cardId }) ?? resolveCardById(cardId)
    }

    private func capturedGroupType(for card: Card) -> String {
        // September animal can be reassigned as double pi.
        if card.month == .sep && card.type == .animal {
            let defaultRoleStr = RuleLoader.shared.config?.cards.chrysanthemum_rule.default_role ?? "animal"
            let defaultRole = CardRole(rawValue: defaultRoleStr) ?? .animal
            let role = card.selectedRole ?? defaultRole
            return role == .doublePi ? "pi" : "animal"
        }
        // November junk is treated as pi group in captured UI.
        if card.month == .nov && (card.type == .junk || card.type == .doubleJunk) {
            return "pi"
        }
        if card.type == .bright { return "gwang" }
        if card.type == .animal { return "animal" }
        if card.type == .ribbon { return "ribbon" }
        return "pi"
    }

    private func updatePersistentCoordDebug(src: CGPoint, tgt: CGPoint, isReal: Bool, progress: CGFloat) {
        DispatchQueue.main.async {
            self.persistentDebugSrc = src
            self.persistentDebugTgt = tgt
            self.persistentDebugIsReal = isReal
            self.persistentDebugProgress = max(0, min(1, progress))
        }
    }

    private func logMonth6TableToCapturedTrace(
        card: Card,
        index: Int,
        progress: CGFloat,
        sourcePoint: CGPoint,
        targetPoint: CGPoint,
        currentPoint: CGPoint,
        usedRealSource: Bool,
        targetPlayerId: String
    ) {
        #if DEBUG
        guard card.month == .jun else { return }
        guard card.type == .junk || card.type == .doubleJunk else { return }
        guard gameManager.currentMoveSourceZone == "table", gameManager.currentMoveTargetZone == "captured" else { return }
        let targetName = playerName(for: targetPlayerId) ?? targetPlayerId
        print(
            "🧭 [JUNE_PI_PATH] " +
            "id=\(card.id) idx=\(index) month=\(card.month.rawValue) type=\(card.type.rawValue) imageIndex=\(card.imageIndex) " +
            "p=\(String(format: "%.3f", progress)) " +
            "src=(\(Int(sourcePoint.x)),\(Int(sourcePoint.y))) " +
            "tgt=(\(Int(targetPoint.x)),\(Int(targetPoint.y))) " +
            "cur=(\(Int(currentPoint.x)),\(Int(currentPoint.y))) " +
            "X=\(Int(currentPoint.x)) Y=\(Int(currentPoint.y)) " +
            "sourceReal=\(usedRealSource) target=\(targetName)"
        )
        if currentPoint.y < 130 {
            print("'130'보다 작아 졌어요. id=\(card.id) X=\(Int(currentPoint.x)) Y=\(Int(currentPoint.y)) p=\(String(format: "%.3f", progress))")
        }
        #endif
    }

    private func tableAnchorPoint(for cardId: String, safeArea: EdgeInsets) -> CGPoint? {
        // Priority 1: Use real screen-space center captured by GeometryReader at render time
        if let realCenter = tableCardCenters[cardId] {
            return realCenter
        }

        // Priority 2: Use median of existing real positions (tableCardCenters has correct Y values from GeometryReader)
        // This handles newly-played cards whose onAppear hasn't fired yet.
        if !tableCardCenters.isEmpty {
            let points = Array(tableCardCenters.values)
            let sortedY = points.map { $0.y }.sorted()
            let medianY = sortedY[sortedY.count / 2]
            let sortedX = points.map { $0.x }.sorted()
            let medianX = sortedX[sortedX.count / 2]
            let medianPt = CGPoint(x: medianX, y: medianY)
            print("📊 [tableAnchorPoint] Median fallback for \(cardId) -> \(medianPt) (from \(tableCardCenters.count) entries)")
            return medianPt
        }

        // Priority 3: Math-based slot lookup (only when tableCardCenters is completely empty)
        guard let ctx = config.layoutContext else { return nil }
        let tableConfig = ctx.config.areas.center.elements.table

        if tableConfig.mode == "fixedSlots12", let manager = tableSlotManager {
            let cardW = ctx.cardSize.width * tableConfig.scale
            let cardH = ctx.cardSize.height * tableConfig.scale
            let direction = tableConfig.grid.stackDirection ?? "vertical"
            let overlap = tableConfig.grid.stackOverlapRatio
            let isHorizontal = direction == "horizontal"
            let isDiagonal = direction == "diagonal"

            // Exact ID Match
            for (slotIndex, slotState) in manager.slots {
                guard let stackIndex = slotState.cards.firstIndex(where: { $0.id == cardId }),
                      let slotFrame = ctx.centerSlotFrames[slotIndex] else { continue }
                let xOff = (isHorizontal || isDiagonal) ? CGFloat(stackIndex) * (cardW * (1.0 - overlap)) : 0
                let yOff = (!isHorizontal) ? CGFloat(stackIndex) * (cardH * (1.0 - overlap)) : 0
                return CGPoint(x: safeArea.leading + slotFrame.midX + xOff, y: safeArea.top + slotFrame.midY + yOff)
            }
        }

        return tableFallbackAnchorPoint(safeArea: safeArea, cardId: cardId)
    }
    
    private func tableFallbackAnchorPoint(safeArea: EdgeInsets, cardId: String? = nil) -> CGPoint? {
        #if DEBUG
        if let cardId {
            print("⚠️ [tableAnchorPoint] SLOT FALLBACK for \(cardId). No real center/slot match.")
        } else {
            print("⚠️ [tableAnchorPoint] SLOT FALLBACK invoked.")
        }
        #endif
        guard let ctx = config.layoutContext else { return nil }
        let centerFrame = ctx.frame(for: .center)
        let tableConfig = ctx.config.areas.center.elements.table

        return CGPoint(
            x: safeArea.leading + centerFrame.minX + centerFrame.width * tableConfig.x,
            y: safeArea.top + centerFrame.minY + centerFrame.height * tableConfig.y
        )
    }
}
