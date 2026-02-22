import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    @ObservedObject var config: ConfigManager = .shared
    @State private var playerHandSlotManager: PlayerHandSlotManager?
    @State private var tableSlotManager: TableSlotManager?
    @State private var showingRestartAlert = false
    
    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let safeSize = CGSize(
                width: geometry.size.width - safeArea.leading - safeArea.trailing,
                height: geometry.size.height - safeArea.top - safeArea.bottom
            )
            
            // Sync Game Size to Config (Use SAFE size for layout calculation)
            let _ = config.updateGameSize(safeSize)
            
            let layoutContext = config.layoutContext
            
            ZStack {
                // Global Background (Full Screen)
                RadialGradient(gradient: Gradient(colors: [Color(red: 0.15, green: 0.55, blue: 0.25), Color(red: 0.05, green: 0.35, blue: 0.15)]), center: .center, startRadius: 50, endRadius: 600)
                    .ignoresSafeArea()
                
                if let ctx = layoutContext {
                    // 0. Setting Area
                    if let settingFrame = ctx.areaFrames[.setting], settingFrame.height > 0 {
                        SettingAreaV2(ctx: ctx, config: ctx.config.areas.setting, onExitTapped: {
                            showingRestartAlert = true
                        })
                            .frame(width: settingFrame.width, height: settingFrame.height)
                            .position(x: safeArea.leading + settingFrame.midX,
                                      y: safeArea.top + settingFrame.midY)
                            .zIndex(0)
                    }
                    
                    // 1. Opponent Area
                    let opponentFrame = ctx.frame(for: .opponent)
                    OpponentAreaV2(ctx: ctx, gameManager: gameManager)
                        .frame(width: opponentFrame.width, height: opponentFrame.height)
                        .position(x: safeArea.leading + opponentFrame.midX,
                                  y: safeArea.top + opponentFrame.midY)
                        .zIndex(1)
                    
                    // 2. Center Area
                    let centerFrame = ctx.frame(for: .center)
                    CenterAreaV2(ctx: ctx, gameManager: gameManager, tableSlotManager: tableSlotManager)
                        .frame(width: centerFrame.width, height: centerFrame.height)
                        .position(x: safeArea.leading + centerFrame.midX,
                                  y: safeArea.top + centerFrame.midY)
                        .zIndex(2)
                    
                    // 3. Player Area
                    let playerFrame = ctx.frame(for: .player)
                    PlayerAreaV2(ctx: ctx, gameManager: gameManager, slotManager: playerHandSlotManager)
                        .frame(width: playerFrame.width, height: playerFrame.height)
                        .position(x: safeArea.leading + playerFrame.midX,
                                  y: safeArea.top + playerFrame.midY)
                        .zIndex(3)
                    
                    // Debug Overlay
                    if config.layoutV2?.debug.showSafeArea == true || config.layoutV2?.debug.showGrid == true {
                        DebugLayoutOverlayV2(ctx: ctx)
                            .position(x: safeArea.leading + safeSize.width/2, y: safeArea.top + safeSize.height/2) // Centered in Safe Area
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
            }
            .coordinateSpace(name: "GameSpace")
            .alert("재시작 확인", isPresented: $showingRestartAlert) {
                Button("취소", role: .cancel) {
                    // Do nothing, resume game
                }
                Button("확인", role: .destructive) {
                    // Restart logic
                    gameManager.setupGame()
                    gameManager.startGame()
                }
            } message: {
                Text("게임을 다시 시작하시겠습니까?")
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if let configV2 = config.layoutV2 {
                self.playerHandSlotManager = PlayerHandSlotManager(config: configV2)
                if let hand = gameManager.players.first?.hand {
                    self.playerHandSlotManager?.sync(with: hand)
                }
                
                self.tableSlotManager = TableSlotManager(config: configV2)
                self.tableSlotManager?.sync(with: gameManager.tableCards)
            }
        }
        .onChange(of: config.layoutV2) { newConfig in
            if let cfg = newConfig {
                 self.playerHandSlotManager = PlayerHandSlotManager(config: cfg)
                 if let hand = gameManager.players.first?.hand {
                     self.playerHandSlotManager?.sync(with: hand)
                 }
                 
                 self.tableSlotManager = TableSlotManager(config: cfg)
                 self.tableSlotManager?.sync(with: gameManager.tableCards)
            }
        }
        .onChange(of: gameManager.players.first?.hand) { newHand in
            if let hand = newHand {
                playerHandSlotManager?.sync(with: hand)
            }
        }
        .onChange(of: gameManager.tableCards) { newTableCards in
            tableSlotManager?.sync(with: newTableCards)
        }
    }
    
    // MARK: - Subviews

    
    @ViewBuilder
    var overlayArea: some View {
        if gameManager.gameState == .ready {
            colorBackgroundOverlay(text: "Start Game", action: {
                // Initial reload to ensure config is fresh
                config.reloadConfig()
                gameManager.startGame()
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
                            gameManager.setupGame()
                            gameManager.startGame()
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
                        gameManager.setupGame()
                        gameManager.startGame()
                    },
                    gameManager: gameManager
                )
            } else {
                colorBackgroundOverlay(text: "Game Over\nTap to Restart", action: {
                    gameManager.setupGame()
                    gameManager.startGame()
                })
            }
        } else if gameManager.gameState == .askingGoStop {
            goStopOverlay()
        } else if gameManager.gameState == .askingShake {
            shakeOverlay()
        } else if gameManager.gameState == .choosingCapture {
            captureChoiceOverlay()
        }
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
