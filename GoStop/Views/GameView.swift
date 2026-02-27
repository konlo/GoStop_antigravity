import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    @ObservedObject var config: ConfigManager = .shared
    @StateObject private var animationManager = AnimationManager.shared
    @State private var playerHandSlotManager: PlayerHandSlotManager?
    @State private var tableSlotManager: TableSlotManager?
    @State private var showingRestartAlert = false
    @State private var showingEventLog = false
    @State private var showingSettings = false
    
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
        .onReceive(gameManager.objectWillChange) { _ in
            // Slot managers can miss nested array mutations in long animation chains.
            // Resync from source-of-truth state on every GameManager change.
            DispatchQueue.main.async {
                self.resyncSlotManagers()
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
            
            // Unified Moving Card Overlay
            movingCardOverlay(safeArea: safeArea)
                .zIndex(210)
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
    private func gameAreas(ctx: LayoutContext, safeArea: EdgeInsets) -> some View {
        // 0. Setting Area
        if let settingFrame = ctx.areaFrames[.setting], settingFrame.height > 0 {
            SettingAreaV2(
                ctx: ctx,
                config: ctx.config.areas.setting,
                onExitTapped: { showingRestartAlert = true },
                onSettingsTapped: { showingSettings = true },
                onLogTapped: { showingEventLog.toggle() }
            )
            .frame(width: settingFrame.width, height: settingFrame.height)
            .position(x: safeArea.leading + settingFrame.midX, y: safeArea.top + settingFrame.midY)
            .zIndex(0)
        }
        
        // 1. Opponent Area
        let opponentFrame = ctx.frame(for: .opponent)
        OpponentAreaV2(ctx: ctx, animationNamespace: cardAnimationNamespace, gameManager: gameManager)
            .frame(width: opponentFrame.width, height: opponentFrame.height)
            .clipped()
            .position(x: safeArea.leading + opponentFrame.midX, y: safeArea.top + opponentFrame.midY)
            .zIndex(2)
        
        // 2. Center Area
        let centerFrame = ctx.frame(for: .center)
        CenterAreaV2(ctx: ctx, animationNamespace: cardAnimationNamespace, gameManager: gameManager, tableSlotManager: tableSlotManager)
            .frame(width: centerFrame.width, height: centerFrame.height)
            .clipped()
            .position(x: safeArea.leading + centerFrame.midX, y: safeArea.top + centerFrame.midY)
            .zIndex(1)
        
        // 3. Player Area
        let playerFrame = ctx.frame(for: .player)
        PlayerAreaV2(ctx: ctx, animationNamespace: cardAnimationNamespace, gameManager: gameManager, slotManager: playerHandSlotManager)
            .frame(width: playerFrame.width, height: playerFrame.height)
            .clipped()
            .position(x: safeArea.leading + playerFrame.midX, y: safeArea.top + playerFrame.midY)
            .zIndex(3)
    }

    private func onAppearAction() {
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        #if targetEnvironment(simulator)
        if SimulatorBridge.shared == nil {
            AnimationManager.shared.config.card_move_duration = 0
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
            playerHandSlotManager?.sync(with: hand)
        }
    }

    private func onChangeTable(_ newTableCards: [Card]) {
        AnimationManager.shared.withGameAnimation {
            tableSlotManager?.sync(with: newTableCards)
        }
    }

    private func resyncSlotManagers() {
        if let hand = gameManager.players.first?.hand {
            playerHandSlotManager?.sync(with: hand)
        }
        tableSlotManager?.sync(with: gameManager.tableCards)
    }
    
    // MARK: - Subviews

    
    @ViewBuilder
    var overlayArea: some View {
        ZStack {
            if gameManager.gameState == .ready {
                colorBackgroundOverlay(text: "Start Game", action: {
                    // Initial reload to ensure config is fresh
                    config.reloadConfig()
                    startManualGame()
                })
            } else if gameManager.gameState == .ended {
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
            } else if gameManager.gameState == .askingGoStop {
                goStopOverlay()
            } else if gameManager.gameState == .askingShake {
                shakeOverlay()
            } else if gameManager.gameState == .choosingCapture {
                captureChoiceOverlay()
            } else if gameManager.gameState == .choosingChrysanthemumRole {
                chrysanthemumChoiceOverlay()
            }
            
            if showingEventLog {
                EventLogView(eventLogs: gameManager.eventLogs, isPresented: $showingEventLog)
            }
            
            if showingSettings {
                RuleSettingsView(isPresented: $showingSettings)
            }
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

    private func startManualGame() {
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        gameManager.startGame()
    }

    private func restartManualGame() {
        gameManager.internalComputerAutomationEnabled = true
        gameManager.externalControlMode = false
        gameManager.setupGame()
        gameManager.startGame()
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


    @ViewBuilder
    func shakeOverlay() -> some View {
        if let month = gameManager.pendingShakeMonths.first {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 30) {
                    Text("\(month)월 카드가 3장 있습니다!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("흔들겠습니까? (점수 \(gameManager.players.first?.shakeCount ?? 0 + 2)배 적용)")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                    
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

extension GameView {
    @ViewBuilder
    private func movingCardOverlay(safeArea: EdgeInsets) -> some View {
        ZStack {
            ForEach(gameManager.currentMovingCards) { card in
                CardView(
                    card: card,
                    isFaceUp: true,
                    scale: gameManager.movingCardsScale,
                    animationNamespace: cardAnimationNamespace,
                    isSource: false,
                    piCount: gameManager.movingCardsPiCount,
                    showDebugInfo: gameManager.movingCardsShowDebug
                )
                .transition(.identity)
            }
        }
    }
}
