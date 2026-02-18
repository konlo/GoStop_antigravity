import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    @ObservedObject var config: ConfigManager = .shared
    
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
                    // 1. Opponent Area
                    let opponentFrame = ctx.frame(for: .opponent)
                    OpponentAreaV2(ctx: ctx, gameManager: gameManager)
                        .frame(width: opponentFrame.width, height: opponentFrame.height)
                        .position(x: safeArea.leading + opponentFrame.midX,
                                  y: safeArea.top + opponentFrame.midY)
                        .zIndex(1)
                    
                    // 2. Center Area
                    let centerFrame = ctx.frame(for: .center)
                    CenterAreaV2(ctx: ctx, gameManager: gameManager)
                        .frame(width: centerFrame.width, height: centerFrame.height)
                        .position(x: safeArea.leading + centerFrame.midX,
                                  y: safeArea.top + centerFrame.midY)
                        .zIndex(2)
                    
                    // 3. Player Area
                    let playerFrame = ctx.frame(for: .player)
                    PlayerAreaV2(ctx: ctx, gameManager: gameManager)
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
            }
            .coordinateSpace(name: "GameSpace")
        }
        .ignoresSafeArea()
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
