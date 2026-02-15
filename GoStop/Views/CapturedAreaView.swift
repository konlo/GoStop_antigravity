import SwiftUI

struct CapturedAreaView: View {
    let capturedCards: [Card]
    let isOpponent: Bool
    let spacing: CGFloat
    
    init(capturedCards: [Card], isOpponent: Bool = false, spacing: CGFloat = 10) {
        self.capturedCards = capturedCards
        self.isOpponent = isOpponent
        self.spacing = spacing
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
                PlaceholderSlot(icon: "sun.max.fill", color: .yellow)
            } else {
                OverlappingStack(cards: brights, overlap: 30) // Wide overlap for visibility
            }
            
            // Group 2: Animals
            if animals.isEmpty {
                PlaceholderSlot(icon: "bird.fill", color: .orange)
            } else {
                OverlappingStack(cards: animals, overlap: 30)
            }
            
            // Group 3: Ribbons
            if ribbons.isEmpty {
                 PlaceholderSlot(icon: "ribbon", color: .red)
            } else {
                OverlappingStack(cards: ribbons, overlap: 25)
            }
            
            // Group 4: Junk (Smart Stacking)
            if junk.isEmpty {
                PlaceholderSlot(icon: "leaf.fill", color: .green)
            } else {
                JunkPileView(cards: junk)
            }
        }
        .padding(.horizontal, 5)
    }
}

struct PlaceholderSlot: View {
    let icon: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .background(Color.black.opacity(0.1))
                .frame(width: 40, height: 64)
            
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color.opacity(0.5))
        }
    }
}

struct OverlappingStack: View {
    let cards: [Card]
    let overlap: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
             ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                 CardView(card: card)
                     .frame(width: 40, height: 64) // Smaller size for captured area
                     .offset(x: CGFloat(index) * overlap)
                     .zIndex(Double(index))
             }
        }
        .frame(width: 40 + (CGFloat(max(0, cards.count - 1)) * overlap), height: 64)
    }
}

struct JunkPileView: View {
    let cards: [Card]
    let cardsPerStack = 5
    let xOffset: CGFloat = 15 // Increased stack separation
    let yOffset: CGFloat = -18 // Increased vertical visibility
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Calculate number of stacks needed
            let chunks = chunkedCards()
            
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                OverlappingStack(cards: chunk, overlap: 20) // Increased overlap (was 15) -> 50% visible (40 width)
                    .offset(x: CGFloat(index) * xOffset, y: CGFloat(index) * yOffset)
                    .zIndex(Double(index))
            }
        }
        // Frame calculation based on content
        .frame(minWidth: 50, minHeight: 64) 
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
        ], spacing: 30)
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.green)
    }
}
