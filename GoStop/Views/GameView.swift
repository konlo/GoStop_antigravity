import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            let gameWidth = geometry.size.width
            let gameHeight = geometry.size.height
            
            // Sync Game Size to Config for relative card sizing
            let _ = config.updateGameSize(CGSize(width: gameWidth, height: gameHeight))
            
            ZStack {
                // Global Background (Full Screen)
                RadialGradient(gradient: Gradient(colors: [Color(red: 0.15, green: 0.55, blue: 0.25), Color(red: 0.05, green: 0.35, blue: 0.15)]), center: .center, startRadius: 50, endRadius: 600)
                    .ignoresSafeArea()
                
                // Game Layout: Vertical Stack of 3 Areas
                VStack(spacing: 0) {
                    // 1. Opponent Area (Top)
                    GeometryReader { geo in
                        let areaSize = geo.size
                        let areaConfig = config.layout.areas.opponent
                        
                        ZStack {
                            // Background
                            if let bg = areaConfig.background {
                                RoundedRectangle(cornerRadius: bg.cornerRadius)
                                    .fill(bg.colorSwiftUI)
                                    .frame(width: areaSize.width * bg.widthRatio, height: areaSize.height)
                                    .position(x: areaSize.width/2, y: areaSize.height/2)
                            }
                            
                            // Hand
                            if let handConfig = areaConfig.elements.hand {
                                opponentHandSection(config: handConfig)
                                    .position(x: areaSize.width * handConfig.x, y: areaSize.height * handConfig.y)
                            }
                            
                            // Captured
                            if let capConfig = areaConfig.elements.captured {
                                opponentCapturedSection(config: capConfig)
                                    .position(x: areaSize.width * capConfig.x, y: areaSize.height * capConfig.y)
                            }
                        }
                    }
                    .frame(height: gameHeight * config.layout.areas.opponent.heightRatio)
                    .zIndex(1)

                    // 2. Center Area (Table/Deck)
                    GeometryReader { geo in
                        let areaSize = geo.size
                        let areaConfig = config.layout.areas.center
                        
                        ZStack {
                            // Background
                            if let bg = areaConfig.background {
                                RoundedRectangle(cornerRadius: bg.cornerRadius)
                                    .fill(bg.colorSwiftUI)
                                    .frame(width: areaSize.width * bg.widthRatio, height: areaSize.height)
                                    .position(x: areaSize.width/2, y: areaSize.height/2)
                            }
                            
                            // Table
                            if let tableConfig = areaConfig.elements.table {
                                tableSection(config: tableConfig)
                                    .position(x: areaSize.width * tableConfig.x, y: areaSize.height * tableConfig.y)
                            }
                            
                            // Deck
                            if let deckConfig = areaConfig.elements.deck {
                                deckView(config: deckConfig)
                                    .position(x: areaSize.width * deckConfig.x, y: areaSize.height * deckConfig.y)
                            }
                        }
                    }
                    .frame(height: gameHeight * config.layout.areas.center.heightRatio)
                    .zIndex(2)

                    // 3. Player Area (Bottom)
                    GeometryReader { geo in
                        let areaSize = geo.size
                        let areaConfig = config.layout.areas.player
                        
                        ZStack {
                            // Background
                            if let bg = areaConfig.background {
                                RoundedRectangle(cornerRadius: bg.cornerRadius)
                                    .fill(bg.colorSwiftUI)
                                    .frame(width: areaSize.width * bg.widthRatio, height: areaSize.height)
                                    .position(x: areaSize.width/2, y: areaSize.height/2)
                            }
                            
                            // Captured
                            if let capConfig = areaConfig.elements.captured {
                                playerCapturedSection(config: capConfig)
                                    .position(x: areaSize.width * capConfig.x, y: areaSize.height * capConfig.y)
                            }
                            
                            // Hand
                            if let handConfig = areaConfig.elements.hand {
                                playerHandSection(config: handConfig)
                                    .position(x: areaSize.width * handConfig.x, y: areaSize.height * handConfig.y)
                            }
                        }
                    }
                    .frame(height: gameHeight * config.layout.areas.player.heightRatio)
                    .zIndex(3)
                    

                }
                .frame(width: gameWidth, height: gameHeight)
                .clipped() // Ensure content stays within ratio
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Debug Overlay (On top of everything)
                if config.layout.debug?.showGrid == true {
                    DebugAreaOverlay(gameWidth: gameWidth, gameHeight: gameHeight)
                        .allowsHitTesting(false)
                        .zIndex(100)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                
                // Overlays (Global)
                overlayArea
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Subviews
    

    func opponentHandSection(config: ElementPositionConfig) -> some View {
        HStack(spacing: 15) {
            // Avatar
            var avatarSize: CGFloat { 60 * (config.scale ?? 1.0) }
            VStack(spacing: 5) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(Text("CPU").font(.caption).foregroundColor(.secondary))
                
                Text(gameManager.players.count > 1 ? gameManager.players[1].name : "CPU")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            // Hand (Hidden)
            if gameManager.players.count > 1 {
                let opponent = gameManager.players[1]
                let cardScale = config.scale ?? 1.0
                let spacing = self.config.horizontalSpacing(config.grid?.horizontalSpacing ?? -0.03) // Use passed grid config
                
                LazyHStack(spacing: spacing) {
                    ForEach(opponent.hand) { card in
                        CardView(card: card, isFaceUp: false, scale: cardScale)
                            .frame(width: self.config.cardSize(scale: cardScale).width, height: self.config.cardSize(scale: cardScale).height)
                    }
                }
            }
        }
    }
    
    func opponentCapturedSection(config: ElementPositionConfig) -> some View {
        Group {
            if gameManager.players.count > 1 {
                 let opponent = gameManager.players[1]
                 ScrollView(.horizontal, showsIndicators: false) {
                     CapturedAreaView(
                        capturedCards: opponent.capturedCards,
                        isOpponent: true,
                        spacing: config.layout?.groupSpacing ?? 10,
                        scale: config.scale ?? 0.8,
                        cardOverlap: config.layout?.cardOverlap ?? 30,
                        junkOverlap: 10,
                        junkXOffset: 5,
                        junkYOffset: -5
                     )
                         .frame(height: self.config.cardSize(scale: config.scale ?? 0.8).height)
                 }
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .padding(.horizontal)
            } else {
                EmptyView()
            }
        }
    }
    
    func tableSection(config: ElementPositionConfig) -> some View {
        HStack(spacing: 20) {
            // Left Side
            let stacks = groupedTableCards
            let midPoint = (stacks.count + 1) / 2 // Rough split
            let leftStacks = Array(stacks.prefix(midPoint))
            let rightStacks = Array(stacks.dropFirst(midPoint))
            
            // Grid Config
            let rows = config.grid?.rows ?? 2
            let vSpacing = self.config.verticalSpacing(config.grid?.verticalSpacing ?? 0.025)
            let hSpacing = self.config.horizontalSpacing(config.grid?.horizontalSpacing ?? 0.02)
            let overlapRatio = config.grid?.stackOverlapRatio ?? 0.6
            let scale = config.scale ?? 1.0
             
            // Left Grid
            LazyNStack(rows: rows, stacks: leftStacks, alignment: .trailing, vSpacing: vSpacing, hSpacing: hSpacing) { stack in
                TableCardStack(stack: stack, overlapRatio: overlapRatio, scale: scale)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            
            // Deck Space (Empty here, Deck is separate)
            Spacer().frame(width: 80) 
            
            // Right Grid
            LazyNStack(rows: rows, stacks: rightStacks, alignment: .leading, vSpacing: vSpacing, hSpacing: hSpacing) { stack in
                 TableCardStack(stack: stack, overlapRatio: overlapRatio, scale: scale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    func deckView(config: ElementPositionConfig) -> some View {
        ZStack {
             ForEach(0..<min(5, gameManager.deck.cards.count), id: \.self) { index in
                  CardView(card: Card(month: .jan, type: .junk, imageIndex: 2), isFaceUp: false, scale: config.scale ?? 0.9)
                     // Stack effect for deck
                     .offset(x: CGFloat(index) * 0.5, y: CGFloat(index) * 0.5)
             }
         }
         .frame(width: self.config.cardSize(scale: config.scale ?? 0.9).width, height: self.config.cardSize(scale: config.scale ?? 0.9).height)
         .zIndex(10)
    }
    
    func playerCapturedSection(config: ElementPositionConfig) -> some View {
        Group {
            if let player = gameManager.players.first {
                ScrollView(.horizontal, showsIndicators: false) {
                     CapturedAreaView(
                        capturedCards: player.capturedCards,
                        spacing: config.layout?.groupSpacing ?? 10,
                        scale: config.scale ?? 0.8,
                        cardOverlap: config.layout?.cardOverlap ?? 30,
                        junkOverlap: 10,
                        junkXOffset: 5,
                        junkYOffset: -5
                     )
                        .frame(height: self.config.cardSize(scale: config.scale ?? 0.8).height)
                        .padding(.vertical, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            } else {
                EmptyView()
            }
        }
    }
    
    func playerHandSection(config: ElementPositionConfig) -> some View {
        ZStack {
             if let player = gameManager.players.first {
                 HStack {
                     // 1. Info Area (Avatar/Score)
                     VStack(alignment: .leading, spacing: 5) {
                         Text("Player 1")
                             .font(.headline)
                             .foregroundColor(.primary)
                         
                         Text("Score: \(player.score)")
                             .font(.title2)
                             .fontWeight(.bold)
                             .foregroundColor(.blue)
                         
                         Text("Money: 1,000,000") // Placeholder
                             .font(.caption)
                             .foregroundColor(.secondary)
                     }
                     .padding(.leading)
                     
                     Spacer()
                     
                     // 2. Hand Area
                     let scale = config.scale ?? 1.1
                     let maxCols = config.grid?.maxCols ?? 5
                     let rows = chunkedHand(player.hand, size: maxCols)
                     
                     let vSpacing = self.config.verticalSpacing(config.grid?.verticalSpacing ?? 0.01)
                     let hSpacing = self.config.horizontalSpacing(config.grid?.horizontalSpacing ?? 0.05)
                     
                     VStack(spacing: vSpacing) {
                         ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowCards in
                             HStack(spacing: hSpacing) {
                                 ForEach(rowCards) { card in
                                     playerCardView(card: card, scale: scale)
                                 }
                             }
                         }
                     }
                     .padding(.trailing)
                 }
             }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(15)
    }

    func playerCardView(card: Card, scale: CGFloat) -> some View {
        CardView(card: card, isFaceUp: true, scale: scale)
            .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    gameManager.playTurn(card: card)
                }
            }
    }

    
    // Helper to group cards by month for the table
    var groupedTableCards: [[Card]] {
        let text = gameManager.tableCards
        // Grouping: We need to preserve some order or just group by month.
        // Simple map: month -> [cards]
        var groups: [Int: [Card]] = [:]
        for card in text {
            groups[card.month.rawValue, default: []].append(card)
        }
        // Return as array of arrays, sorted by month to be deterministic
        return groups.keys.sorted().map { groups[$0]! }
    }
    
    func chunkedHand(_ hand: [Card], size: Int) -> [[Card]] {
        return stride(from: 0, to: hand.count, by: size).map {
            Array(hand[$0 ..< min($0 + size, hand.count)])
        }
    }
    
    // MARK: - Overlays
    
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
