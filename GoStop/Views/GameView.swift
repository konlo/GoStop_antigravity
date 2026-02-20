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
            colorBackgroundOverlay(text: "Game Over\nTap to Restart", action: {
                gameManager.setupGame()
                gameManager.startGame()
            })
        } else if gameManager.gameState == .askingGoStop {
            goStopOverlay()
        }
    }
    
    @ViewBuilder
    func goStopOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 30) {
                Text("점수가 났습니다!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                HStack(spacing: 40) {
                    Button(action: {
                        gameManager.respondToGoStop(isGo: true)
                    }) {
                        Text("GO")
                            .font(.title)
                            .bold()
                            .frame(width: 120, height: 60)
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
                            .frame(width: 120, height: 60)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                }
            }
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
