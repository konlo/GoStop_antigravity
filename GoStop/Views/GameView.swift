import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    @Namespace private var cardAnimationNamespace
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RadialGradient(gradient: Gradient(colors: [Color(red: 0.15, green: 0.55, blue: 0.25), Color(red: 0.05, green: 0.35, blue: 0.15)]), center: .center, startRadius: 50, endRadius: 600)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Opponent Area (Top) - ~22% (Increased for Vertical Layout)
                    opponentArea
                        .frame(height: geometry.size.height * 0.22)
                        .zIndex(1)
                    
                    // Table Area (Center) - ~38% (Reduced)
                    tableArea
                        .frame(height: geometry.size.height * 0.38)
                        .zIndex(0)
                    
                    // Player Area (Bottom) - ~40%
                    playerArea
                        .frame(height: geometry.size.height * 0.40)
                        .zIndex(2)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .padding(.horizontal) // Fix for rounded corners clipping content
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Strict centering to fix safe area shift
                //.padding(.bottom, 20) // Removed safety padding that might cause issues with full bleed
                
                // Overlays
                overlayArea
            }
        }
        .ignoresSafeArea() // Critical fix: GeometryReader now starts at (0,0) screen coordinates
    }
    
    // MARK: - Subviews
    
    var opponentArea: some View {
        VStack(spacing: 5) {
            // Row 1: Info & Hand
            HStack {
                // Avatar / Info
                VStack {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                    Text("Computer")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Hand (Face Down)
                if gameManager.players.count > 1 {
                    let opponent = gameManager.players[1]
                    HStack(spacing: -20) {
                        ForEach(opponent.hand) { card in
                            CardView(card: card, isFaceUp: false)
                        }
                    }
                }
                
                Spacer()
                
                // Score Label
                if gameManager.players.count > 1 {
                     let opponent = gameManager.players[1]
                     Text("Score: \(opponent.score)")
                         .foregroundStyle(.white)
                         .font(.caption)
                         .bold()
                }
            }
            .padding(.horizontal)
            
            // Row 2: Captured Cards
            if gameManager.players.count > 1 {
                 let opponent = gameManager.players[1]
                 // Use wider spacing now that we have full width
                 ScrollView(.horizontal, showsIndicators: false) {
                     CapturedAreaView(capturedCards: opponent.capturedCards, isOpponent: true, spacing: 20)
                         .scaleEffect(0.8) // Consistent scale with player
                         .frame(height: 50)
                 }
                 .frame(maxWidth: .infinity, alignment: .leading) // Ensure it aligns start
            }
            
            Spacer(minLength: 0)
        }
        .padding(.top, 10) // Internal top padding
        .background(Color.black.opacity(0.1)) // Subtle background to see area
    }
    
    var tableArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                // Deck
                HStack {
                    Spacer()
                    ZStack {
                        ForEach(0..<min(5, gameManager.deck.cards.count), id: \.self) { index in
                             CardView(card: Card(month: .jan, type: .junk, imageIndex: 2), isFaceUp: false)
                                .offset(x: CGFloat(index) * 2, y: CGFloat(index) * 2)
                        }
                    }
                    Spacer()
                }
                .frame(height: 80)
                
                // Table Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 10) {
                    ForEach(gameManager.tableCards) { card in
                        CardView(card: card)
                            .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
                    }
                }
                .padding()
            }
        }
    }
    
    var playerArea: some View {
        VStack {
            // Player Info
            HStack {
                Text("Player 1")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let player = gameManager.players.first {
                     Text("Score: \(player.score)")
                        .foregroundStyle(.yellow)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Material.thinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom, 5)
            
            // Captured Cards
            if let player = gameManager.players.first {
                ScrollView(.horizontal, showsIndicators: false) {
                     CapturedAreaView(capturedCards: player.capturedCards, spacing: 30)
                        .scaleEffect(0.8)
                        .frame(height: 60)
                        .padding(.bottom, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Hand
            ScrollView(.horizontal, showsIndicators: false) {
                if let player = gameManager.players.first {
                    HStack(spacing: -10) {
                        ForEach(player.hand) { card in
                            CardView(card: card)
                                .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                        gameManager.playTurn(card: card)
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(15)
    }
    
    // MARK: - Overlays
    
    @ViewBuilder
    var overlayArea: some View {
        if gameManager.gameState == .ready {
            colorBackgroundOverlay(text: "Start Game", action: {
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
