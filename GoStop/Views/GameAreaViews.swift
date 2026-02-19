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
                // Auto-Layout Constraint: Clamp Y position to stay within bounds
                let cardHeight = ctx.cardSize.height * capConfig.scale
                let desiredY = frame.height * capConfig.y
                let halfHeight = cardHeight / 2.0
                let padding = ctx.scaledTokens.panelPadding
                
                // Ensure bottom edge (y + halfHeight) <= frame.height - padding/2
                let maxY = frame.height - halfHeight - (padding / 2)
                let finalY = min(desiredY, maxY)
                
                CapturedAreaV2(ctx: ctx, layoutConfig: capConfig.layout, cards: gameManager.players[1].capturedCards, scale: capConfig.scale, alignLeading: true)
                    .position(x: frame.width * capConfig.x, y: finalY)
                    .zIndex(capConfig.zIndex)
            }
        }
    }
}

// MARK: - Center Area V2
struct CenterAreaV2: View {
    let ctx: LayoutContext
    @ObservedObject var gameManager: GameManager
    var tableSlotManager: TableSlotManager?
    
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
            TableAreaV2(ctx: ctx, config: tableConfig, cards: gameManager.tableCards, slotManager: tableSlotManager)
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
    var slotManager: PlayerHandSlotManager?
    
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
                PlayerHandV2(ctx: ctx, config: handConfig, gameManager: gameManager, slotManager: slotManager, hand: player.hand)
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
            
            // Debug Sort Button
            if handConfig.sorting?.enabled == true && slotManager != nil {
                Button(action: {
                    slotManager?.sort()
                }) {
                    Text("Sort")
                        .font(.custom("Courier", size: 10))
                        .padding(6)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .position(x: frame.width * 0.92, y: frame.height * 0.08)
                .zIndex(100)
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
        let overlap = handConfig.grid?.overlapRatio ?? 0.0
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
    var slotManager: PlayerHandSlotManager?
    let hand: [Card]
    
    var body: some View {
        Group {
            if config.mode == "fixedSlots10", let manager = slotManager {
                PlayerHandFixedSlotsView(ctx: ctx, config: config, manager: manager, gameManager: gameManager)
            } else {
                PlayerHandGridV1(ctx: ctx, config: config, gameManager: gameManager, hand: hand)
            }
        }
    }
}

struct PlayerHandFixedSlotsView: View {
    let ctx: LayoutContext
    let config: ElementHandConfig
    @ObservedObject var manager: PlayerHandSlotManager
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        
        ZStack {
             if let fixedSlots = config.fixedSlots {
                 ForEach(fixedSlots.slots, id: \.slotIndex) { slot in
                     let absFrame = ctx.playerHandSlotFrames[slot.slotIndex] ?? .zero
                     
                     // Convert to Local Coordinates
                     let pFrame = ctx.frame(for: .player)
                     let handCenterX = pFrame.minX + (pFrame.width * config.x)
                     let handCenterY = pFrame.minY + (pFrame.height * config.y)
                     
                     let localX = absFrame.midX - handCenterX
                     let localY = absFrame.midY - handCenterY

                     Group {
                         // Debug Grid
                         if ctx.config.debug.player?.handSlotGrid == true {
                             ZStack {
                                 Rectangle()
                                     .strokeBorder(Color.red.opacity(manager.slots[slot.slotIndex]?.isOccupied == true ? 0.8 : 0.3), lineWidth: 1)
                                 Text("\(slot.slotIndex)")
                                     .font(.caption2)
                                     .foregroundColor(.red)
                             }
                             .frame(width: cardW, height: cardH)
                         }
                         
                         // Card
                         if let card = manager.card(at: slot.slotIndex) {
                             ZStack {
                                 CardView(card: card, isFaceUp: true, scale: config.scale)
                                     .onTapGesture {
                                         gameManager.playTurn(card: card)
                                     }
                                     .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                                     
                                 // Debug Sort Info
                                 if ctx.config.debug.player?.sortedOrderOverlay == true {
                                     VStack(spacing: 0) {
                                         Text("M:\(card.month.rawValue)")
                                         Text("T:\(card.type)")
                                     }
                                     .font(.system(size: 8))
                                     .padding(2)
                                     .background(Color.black.opacity(0.7))
                                     .foregroundColor(.white)
                                     .offset(y: -cardH/2 + 10)
                                 }
                             }
                         } else {
                             Color.clear.contentShape(Rectangle())
                         }
                     }
                     .frame(width: cardW, height: cardH)
                     .offset(x: localX, y: localY)
                 }
             }
        }
    }
}

struct PlayerHandGridV1: View {
    let ctx: LayoutContext
    let config: ElementHandConfig
    @ObservedObject var gameManager: GameManager
    let hand: [Card]
    
    var body: some View {
        let cardSize = ctx.cardSize
        let scale = config.scale
        let scaledW = cardSize.width * scale
        let scaledH = cardSize.height * scale
        
        let vSpacing = scaledH * (config.grid?.vSpacingCardRatio ?? 0.05)
        let hSpacing = scaledW * (config.grid?.hSpacingCardRatio ?? 0.0)
        
        ZStack {
            if let bg = config.grid?.background {
                RoundedRectangle(cornerRadius: ctx.scaledTokens.panelCornerRadius)
                    .fill(bg.colorSwiftUI)
                    .frame(width: ctx.safeArea.width * bg.widthRatio, height: (scaledH * 2) + vSpacing + (ctx.scaledTokens.panelPadding * 2))
            }
            
            VStack(spacing: vSpacing) {
                let cols = config.grid?.maxCols ?? 5
                let chunks = hand.chunked(into: cols)
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
    var slotManager: TableSlotManager?
    
    var body: some View {
        Group {
            if config.mode == "fixedSlots12", let manager = slotManager {
                TableFixedSlotsView(ctx: ctx, config: config, manager: manager)
            } else {
                legacyGrid
            }
        }
    }
    
    var legacyGrid: some View {
        let groups = Dictionary(grouping: cards, by: { $0.month }).values.sorted(by: { $0.first!.month.rawValue < $1.first!.month.rawValue })
        
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        let hSpacing = cardW * (config.grid.hSpacingCardRatio)
        let vSpacing = cardH * (config.grid.vSpacingCardRatio)
        
        let cols = config.grid.cols
        let rows = config.grid.rows
        
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: hSpacing), count: cols)
        
        return LazyVGrid(columns: columns, spacing: vSpacing) {
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

struct TableFixedSlotsView: View {
    let ctx: LayoutContext
    let config: ElementTableConfig
    @ObservedObject var manager: TableSlotManager
    
    var body: some View {
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        
        ZStack {
             if let fixedSlots = config.fixedSlots {
                 ForEach(fixedSlots.slots, id: \.slotIndex) { slot in
                     let absFrame = ctx.centerSlotFrames[slot.slotIndex] ?? .zero
                     
                     // Convert to Local Coordinates
                     let pos = calculateClampedPosition(slot: slot, ctx: ctx, config: config, manager: manager)
 
                     Group {
                         // Debug Grid
                         if ctx.config.debug.showGrid {
                             ZStack {
                                 Rectangle()
                                     .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                                 Text("\(slot.slotIndex)")
                                     .font(.caption2)
                                     .foregroundColor(.blue)
                             }
                             .frame(width: cardW, height: cardH)
                         }
                         
                         // Cards Stack
                         let stack = manager.cards(at: slot.slotIndex)
                         if !stack.isEmpty {
                             ZStack {
                                  ForEach(Array(stack.enumerated()), id: \.element.id) { i, card in
                                      let direction = config.grid.stackDirection ?? "vertical"
                                      let overlap = config.grid.stackOverlapRatio
                                      
                                      let isHorizontal = direction == "horizontal"
                                      let isDiagonal = direction == "diagonal"
                                      
                                      let xOff = (isHorizontal || isDiagonal) ? CGFloat(i) * (cardW * (1.0 - overlap)) : 0
                                      let yOff = (!isHorizontal) ? CGFloat(i) * (cardH * (1.0 - overlap)) : 0
                                      
                                      CardView(card: card, isFaceUp: true, scale: config.scale)
                                          .offset(x: xOff, y: yOff)
                                          .zIndex(Double(i))
                                  }
                             }
                         } else {
                             Color.clear.contentShape(Rectangle())
                         }
                     }
                     .frame(width: cardW, height: cardH)
                     .offset(x: pos.x, y: pos.y)
                 }
             }
        }
    }
    
    private func calculateClampedPosition(slot: TableFixedSlot, ctx: LayoutContext, config: ElementTableConfig, manager: TableSlotManager) -> CGPoint {
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        
        let absFrame = ctx.centerSlotFrames[slot.slotIndex] ?? .zero
        let cFrame = ctx.frame(for: .center)
        let tableCenterX = cFrame.minX + (cFrame.width * config.x)
        let tableCenterY = cFrame.minY + (cFrame.height * config.y)
        
        var localX = absFrame.midX - tableCenterX
        var localY = absFrame.midY - tableCenterY
        
        // Auto-Layout: Clamp Stack to Center Area Bounds
        let stack = manager.cards(at: slot.slotIndex)
        if !stack.isEmpty {
            let count = stack.count
            let direction = config.grid.stackDirection ?? "vertical"
            let overlap = config.grid.stackOverlapRatio
            let padding = ctx.scaledTokens.panelPadding
            
            let isHorizontal = direction == "horizontal" || direction == "diagonal"
            let isVertical = direction == "vertical" || direction == "diagonal"
            
            // Calculate Stack Extents relative to center
            let maxIndex = CGFloat(max(0, count - 1))
            let maxOffsetX = isHorizontal ? maxIndex * (cardW * (1.0 - overlap)) : 0
            let maxOffsetY = isVertical ? maxIndex * (cardH * (1.0 - overlap)) : 0
            
            // Calculate Edges in Local Coords
            let rightEdge = localX + (cardW / 2.0) + maxOffsetX
            let bottomEdge = localY + (cardH / 2.0) + maxOffsetY
            let leftEdge = localX - (cardW / 2.0)
            let topEdge = localY - (cardH / 2.0)
            
            // Area Bounds (Half-width/height from center 0,0)
            let boundW = (cFrame.width / 2.0) - padding
            let boundH = (cFrame.height / 2.0) - padding
            
            // Clamp X
            if rightEdge > boundW {
                localX -= (rightEdge - boundW)
            } else if leftEdge < -boundW {
                localX += (-boundW - leftEdge)
            }
            
            // Clamp Y
            if bottomEdge > boundH {
                localY -= (bottomEdge - boundH)
            } else if topEdge < -boundH {
                localY += (-boundH - topEdge)
            }
        }
        
        return CGPoint(x: localX, y: localY)
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
