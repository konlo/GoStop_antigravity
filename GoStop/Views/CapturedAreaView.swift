import SwiftUI

struct CapturedAreaView: View {
    let capturedCards: [Card]
    let isOpponent: Bool
    let spacing: CGFloat 
    let scale: CGFloat
    // New params for internal layout
    let cardOverlap: CGFloat
    let junkOverlap: CGFloat
    let junkXOffset: CGFloat
    let junkYOffset: CGFloat
    
    @ObservedObject var config = ConfigManager.shared
    
    init(capturedCards: [Card], isOpponent: Bool = false, spacing: CGFloat = 10, scale: CGFloat = 0.8, cardOverlap: CGFloat = 30, junkOverlap: CGFloat = 10, junkXOffset: CGFloat = 5, junkYOffset: CGFloat = -5) {
        self.capturedCards = capturedCards
        self.isOpponent = isOpponent
        self.spacing = spacing
        self.scale = scale
        self.cardOverlap = cardOverlap
        self.junkOverlap = junkOverlap
        self.junkXOffset = junkXOffset
        self.junkYOffset = junkYOffset
    }

    var brights: [Card] {
        capturedCards.filter { $0.type == .bright }
            .sorted { $0.month < $1.month }
    }
    
    var animals: [Card] {
        capturedCards.filter { $0.type == .animal }
            .sorted { $0.month < $1.month }
    }
    
    var ribbons: [Card] {
        capturedCards.filter { $0.type == .ribbon }
            .sorted { $0.month < $1.month }
    }
    
    var junk: [Card] {
        capturedCards.filter { $0.type == .junk || $0.type == .doubleJunk }
            .sorted { $0.month < $1.month }
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            // Group 1: Brights
            if brights.isEmpty {
                PlaceholderSlot(icon: "sun.max.fill", color: .yellow, scale: scale)
            } else {
                OverlappingStack(cards: brights, overlap: cardOverlap, scale: scale)
            }
            
            // Group 2: Animals
            if animals.isEmpty {
                PlaceholderSlot(icon: "bird.fill", color: .orange, scale: scale)
            } else {
                OverlappingStack(cards: animals, overlap: cardOverlap, scale: scale)
            }
            
            // Group 3: Ribbons
            if ribbons.isEmpty {
                 PlaceholderSlot(icon: "ribbon", color: .red, scale: scale)
            } else {
                OverlappingStack(cards: ribbons, overlap: cardOverlap, scale: scale)
            }
            
            // Group 4: Junk (Smart Stacking)
            if junk.isEmpty {
                PlaceholderSlot(icon: "leaf.fill", color: .green, scale: scale)
            } else {
                JunkPileView(cards: junk, overlap: junkOverlap, xOffset: junkXOffset, yOffset: junkYOffset, scale: scale)
            }
        }
        .padding(.horizontal, 5)
    }
}

struct PlaceholderSlot: View {
    let icon: String
    let color: Color
    let scale: CGFloat
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6 * scale)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .background(Color.black.opacity(0.1))
                .frame(width: config.cardSize(scale: scale).width, height: config.cardSize(scale: scale).height)
            
            Image(systemName: icon)
                .font(.system(size: 10 * scale))
                .foregroundColor(color.opacity(0.5))
        }
    }
}

struct OverlappingStack: View {
    let cards: [Card]
    let overlap: CGFloat
    let scale: CGFloat
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        ZStack(alignment: .leading) {
             ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                 CardView(card: card, scale: scale)
                     .offset(x: CGFloat(index) * overlap)
                     .zIndex(Double(index))
             }
        }
        .frame(width: (config.cardSize(scale: scale).width) + (CGFloat(max(0, cards.count - 1)) * overlap), height: config.cardSize(scale: scale).height)
    }
}

struct JunkPileView: View {
    let cards: [Card]
    let cardsPerStack = 5
    let overlap: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
    let scale: CGFloat
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Calculate number of stacks needed
            let chunks = chunkedCards()
            
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                OverlappingStack(cards: chunk, overlap: overlap, scale: scale)
                    .offset(x: CGFloat(index) * xOffset, y: CGFloat(index) * yOffset)
                    .zIndex(Double(index))
            }
        }
        .frame(minWidth: config.cardSize(scale: scale).width, minHeight: config.cardSize(scale: scale).height) 
    }
    
    func chunkedCards() -> [[Card]] {
        return stride(from: 0, to: cards.count, by: cardsPerStack).map {
            Array(cards[$0 ..< min($0 + cardsPerStack, cards.count)])
        }
    }
}

struct CapturedAreaView_Previews: PreviewProvider {
    static var previews: some View {
        CapturedAreaView(capturedCards: [
            Card(month: .jan, type: .bright, imageIndex: 0),
            Card(month: .feb, type: .animal, imageIndex: 0),
            Card(month: .jan, type: .ribbon, imageIndex: 1),
            Card(month: .sep, type: .junk, imageIndex: 2),
            Card(month: .oct, type: .junk, imageIndex: 2),
            Card(month: .nov, type: .doubleJunk, imageIndex: 1)
        ], spacing: 30) // Preview override
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.green)
    }
}
