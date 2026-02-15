import SwiftUI

struct GameView: View {
    @StateObject var gameManager = GameManager()
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.1, green: 0.5, blue: 0.2) // Felt Green
                .ignoresSafeArea()
            
            VStack {
                // Opponent Area (Top)
                opponentArea
                
                Spacer()
                
                // Table Area (Center)
                tableArea
                
                Spacer()
                
                // Player Area (Bottom)
                playerArea
            }
            .padding()
        }
    }
    
    // MARK: - Subviews
    
    var opponentArea: some View {
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
            
            // Captured Cards
            if gameManager.players.count > 1 {
                 let opponent = gameManager.players[1]
                 VStack {
                     Text("Score: \(opponent.score)")
                         .foregroundStyle(.white)
                         .font(.caption)
                     HStack(spacing: -30) {
                         ForEach(opponent.capturedCards.suffix(5)) { card in
                             CardView(card: card, isFaceUp: true)
                                 .scaleEffect(0.6)
                                 .frame(width: 30, height: 50)
                         }
                     }
                 }
            }
        }
        .frame(height: 100)
    }
    
    var tableArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .frame(maxWidth: .infinity, maxHeight: 250)
            
            VStack {
                // Deck
                HStack {
                    Spacer()
                    ZStack {
                        ForEach(0..<min(5, gameManager.deck.cards.count), id: \.self) { index in
                             CardView(card: Card(month: .jan, type: .junk), isFaceUp: false)
                                .offset(x: CGFloat(index) * 2, y: CGFloat(index) * 2)
                        }
                    }
                    .onTapGesture {
                        // Temp debug action
                        withAnimation {
                           // gameManager.flipDeckCard() // To be implemented
                        }
                    }
                    Spacer()
                }
                .frame(height: 80)
                
                // Table Cards (Display 8 cards or more logic)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 10) {
                    ForEach(gameManager.tableCards) { card in
                        CardView(card: card)
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
            .padding(.horizontal)
            
            // Hand
            ScrollView(.horizontal, showsIndicators: false) {
                if let player = gameManager.players.first {
                    HStack(spacing: -10) {
                        ForEach(player.hand) { card in
                            CardView(card: card)
                                .onTapGesture {
                                    // Debug interaction
                                    print("Tapped \(card)")
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
}

#Preview {
    GameView()
}
