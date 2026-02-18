import SwiftUI

// MARK: - V2 Area Implementations
// These views consume LayoutContext directly.

// MARK: - Opponent Area V2
struct OpponentAreaV2: View {
    let ctx: LayoutContext
    @ObservedObject var gameManager: GameManager // Assuming shared state or passing environment
    
    var body: some View {
        let areaConfig = ctx.config.areas.opponent
        let frame = ctx.frame(for: .opponent)
        
        ZStack {
            // Background
            if areaConfig.background.opacity > 0 {
                RoundedRectangle(cornerRadius: ctx.scaledTokens.panelCornerRadius)
                    .fill(areaConfig.background.colorSwiftUI)
                    .frame(width: frame.width * areaConfig.background.widthRatio, height: frame.height)
            }
            
            // Hand (Opponent)
            // JSON: "scale: 0.45", "grid": { ... }
            let handConfig = areaConfig.elements.hand
            if gameManager.players.count > 1 {
                OpponentHandV2(ctx: ctx, handConfig: handConfig, hand: gameManager.players[1].hand)
                    .position(x: frame.width * handConfig.x, y: frame.height * handConfig.y)
                    .zIndex(handConfig.zIndex)
            }
            
            // Captured (Opponent)
            let capConfig = areaConfig.elements.captured
            if gameManager.players.count > 1 {
                CapturedAreaV2(ctx: ctx, layoutConfig: capConfig.layout, cards: gameManager.players[1].capturedCards, scale: capConfig.scale, alignLeading: true)
                    .position(x: frame.width * capConfig.x, y: frame.height * capConfig.y)
                    .zIndex(capConfig.zIndex)
            }
        }
    }
}

// MARK: - Center Area V2
struct CenterAreaV2: View {
    let ctx: LayoutContext
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        let areaConfig = ctx.config.areas.center
        let frame = ctx.frame(for: .center)
        
        ZStack {
            // Background
            if areaConfig.background.opacity > 0 {
                RoundedRectangle(cornerRadius: ctx.scaledTokens.panelCornerRadius)
                    .fill(areaConfig.background.colorSwiftUI)
                    .frame(width: frame.width * areaConfig.background.widthRatio, height: frame.height)
            }
            
            // Table
            let tableConfig = areaConfig.elements.table
            TableAreaV2(ctx: ctx, config: tableConfig, cards: gameManager.tableCards)
                .position(x: frame.width * tableConfig.x, y: frame.height * tableConfig.y)
                .zIndex(tableConfig.zIndex)
            
            // Deck
            let deckConfig = areaConfig.elements.deck
            DeckAreaV2(ctx: ctx, config: deckConfig, deckCount: gameManager.deck.cards.count)
                .position(x: frame.width * deckConfig.x, y: frame.height * deckConfig.y)
                .zIndex(deckConfig.zIndex)
        }
    }
}

// MARK: - Player Area V2
struct PlayerAreaV2: View {
    let ctx: LayoutContext
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        let areaConfig = ctx.config.areas.player
        let frame = ctx.frame(for: .player)
        
        ZStack {
            // Background
            if areaConfig.background.opacity > 0 {
                RoundedRectangle(cornerRadius: ctx.scaledTokens.panelCornerRadius)
                    .fill(areaConfig.background.colorSwiftUI)
                    .frame(width: frame.width * areaConfig.background.widthRatio, height: frame.height)
            }
            
            // Hand (Player)
            let handConfig = areaConfig.elements.hand
            if let player = gameManager.players.first {
                PlayerHandV2(ctx: ctx, config: handConfig, gameManager: gameManager, hand: player.hand)
                    .position(x: frame.width * handConfig.x, y: frame.height * handConfig.y)
                    .zIndex(handConfig.zIndex)
            }
            
            // Captured (Player)
            let capConfig = areaConfig.elements.captured
            if let player = gameManager.players.first {
                CapturedAreaV2(ctx: ctx, layoutConfig: capConfig.layout, cards: player.capturedCards, scale: capConfig.scale, alignLeading: true)
                    .position(x: frame.width * capConfig.x, y: frame.height * capConfig.y)
                    .zIndex(capConfig.zIndex)
            }
        }
    }
}

// MARK: - Sub Components

struct OpponentHandV2: View {
    let ctx: LayoutContext
    let handConfig: ElementHandConfig
    let hand: [Card]
    
    var body: some View {
        // Opponent hand uses overlapRatio.
        // HStack with negative spacing? Or ZStack with offset?
        // JSON: "hSpacingCardRatio": 0.04 (positive spacing?)
        // Wait, JSON comment says "overlapRatio: 0.62".
        // If overlapRatio is present, it overrides spacing usually.
        // Let's check logic:
        // "overlapRatio: 0.62 = 62% overlap" -> spacing = cardW * (1 - 0.62) = cardW * 0.38
        
        let cardW = ctx.cardSize.width * handConfig.scale
        let overlap = handConfig.grid.overlapRatio ?? 0.0
        let spacing = cardW * (1.0 - overlap)
        // If overlap is 0, use hSpacingCardRatio?
        // JSON has both: "hSpacingCardRatio": 0.04, "overlapRatio": 0.62.
        // Usually overlap implies negative spacing in HStack or manual offset in ZStack.
        // Let's use ZStack for overlap control.
        
        ZStack {
            ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                CardView(card: card, isFaceUp: false, scale: handConfig.scale)
                    .offset(x: CGFloat(index) * spacing)
                    .zIndex(Double(index))
            }
        }
        .frame(width: cardW + (CGFloat(max(0, hand.count - 1)) * spacing), height: ctx.cardSize.height * handConfig.scale)
    }
}

struct PlayerHandV2: View {
    let ctx: LayoutContext
    let config: ElementHandConfig
    @ObservedObject var gameManager: GameManager
    let hand: [Card]
    @Namespace private var nspace // Animation namespace needs to be passed or accessed via Environment
    // For now assuming implicit animation or no matched geometry for layout test
    // To support matchedGeometry, we need to pass namespace from GameView
    
    var body: some View {
        // Grid: 2 rows, 5 cols
        // Spacing: vSpacingCardRatio, hSpacingCardRatio
        let cardSize = ctx.cardSize
        let scale = config.scale // Should be 1.0 or close
        let scaledW = cardSize.width * scale
        let scaledH = cardSize.height * scale
        
        let vSpacing = scaledH * (config.grid.vSpacingCardRatio ?? 0.05)
        let hSpacing = scaledW * config.grid.hSpacingCardRatio
        
        // Background for hand grid
        ZStack {
            if let bg = config.grid.background {
                RoundedRectangle(cornerRadius: ctx.scaledTokens.panelCornerRadius) // Or specific radius in Tokens?
                    .fill(bg.colorSwiftUI)
                    .frame(width: ctx.safeArea.width * bg.widthRatio, height: (scaledH * 2) + vSpacing + (ctx.scaledTokens.panelPadding * 2))
            }
            
            // 2 Rows
            VStack(spacing: vSpacing) {
                let chunks = hand.chunked(into: config.grid.maxCols)
                ForEach(0..<chunks.count, id: \.self) { rowIndex in
                    HStack(spacing: hSpacing) {
                         ForEach(chunks[rowIndex]) { card in
                             CardView(card: card, isFaceUp: true, scale: scale)
                                 .onTapGesture {
                                     gameManager.playTurn(card: card)
                                 }
                         }
                    }
                }
            }
        }
    }
}

struct CapturedAreaV2: View {
    let ctx: LayoutContext
    let layoutConfig: CapturedLayoutConfigV2
    let cards: [Card]
    let scale: CGFloat
    let alignLeading: Bool
    
    var body: some View {
        let cardW = ctx.cardSize.width * scale
        let overlapRatio = layoutConfig.cardOverlapRatio
        // Negative spacing for overlap
        let startSpacing = -cardW * overlapRatio
        
        let groupSpacing = cardW * layoutConfig.groupSpacingCardRatio
        
        ScrollView(.horizontal, showsIndicators: false) {
             HStack(spacing: startSpacing) {
                 ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                     CardView(card: card, isFaceUp: true, scale: scale)
                        .zIndex(Double(index))
                 }
             }
             .padding(.horizontal, ctx.scaledTokens.panelPadding)
        }
        .frame(height: ctx.cardSize.height * scale)
    }
}

struct TableAreaV2: View {
    let ctx: LayoutContext
    let config: ElementTableConfig
    let cards: [Card]
    
    var body: some View {
        // Grid of stacks (12 months = 12 stacks max, or less if empty)
        // Usually 2 rows.
        // Group cards by month.
        let groups = Dictionary(grouping: cards, by: { $0.month }).values.sorted(by: { $0.first!.month.rawValue < $1.first!.month.rawValue })
        
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        let hSpacing = cardW * config.grid.hSpacingCardRatio
        let vSpacing = cardH * config.grid.vSpacingCardRatio
        
        let cols = config.grid.cols
        let rows = config.grid.rows
        
        // Simple Grid Layout
        // We can use LazyVGrid or LazyHGrid?
        // Or manual VStack/HStack.
        
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: hSpacing), count: cols)
        
        LazyVGrid(columns: columns, spacing: vSpacing) {
            ForEach(0..<min(groups.count, rows * cols), id: \.self) { index in
                let stack = groups[index]
                ZStack {
                    ForEach(Array(stack.enumerated()), id: \.element.id) { i, card in
                        CardView(card: card, isFaceUp: true, scale: config.scale)
                            .offset(y: CGFloat(i) * (cardH * (1.0 - config.grid.stackOverlapRatio))) 
                    }
                }
                .frame(width: cardW, height: cardH) // Fixed frame for stack base
            }
        }
    }
}

struct DeckAreaV2: View {
    let ctx: LayoutContext
    let config: ElementDeckConfig
    let deckCount: Int
    
    var body: some View {
        ZStack {
            if deckCount > 0 {
                ForEach(0..<min(5, deckCount), id: \.self) { index in
                    // Junk card back as placeholder
                   CardView(card: Card(month: .jan, type: .junk, imageIndex: 2), isFaceUp: false, scale: config.scale)
                        .offset(x: CGFloat(index) * 0.5, y: CGFloat(index) * 0.5)
                }
            } else {
                Color.clear
            }
        }
    }
}

// Helper Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
