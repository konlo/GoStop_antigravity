import SwiftUI

// MARK: - V2 Area Implementations
// These views consume LayoutContext directly.

// MARK: - Setting Area V2
struct SettingAreaV2: View {
    let ctx: LayoutContext
    let config: SettingSectionConfigV2?
    let onExitTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onLogTapped: () -> Void
    
    var body: some View {
        if let settingConfig = config {
            ZStack {
                // Background
                if settingConfig.background.opacity > 0 || settingConfig.background.color != "#FFFFFF" {
                    RoundedRectangle(cornerRadius: settingConfig.background.cornerRadiusPt * ctx.globalScale)
                        .fill(settingConfig.background.colorSwiftUI)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Content: Settings Icon and Exit Button (right aligned)
                HStack {
                    Spacer()
                    
                    HStack(spacing: 15) {
                        // Exit/Restart Button
                        Button(action: onExitTapped) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }

                        // Settings Menu
                        Menu {
                            Button(action: { print("화투 소개 tapped") }) {
                                Label("1. 화투 소개", systemImage: "book")
                            }
                            Button(action: onSettingsTapped) {
                                Label("2. 현재 설정 상태", systemImage: "gearshape")
                            }
                            Button(action: { print("최고 기록 tapped") }) {
                                Label("3. 최고 기록", systemImage: "trophy")
                            }
                            Button(action: onLogTapped) {
                                Label("4. 화투 Log", systemImage: "list.bullet.rectangle")
                            }
                            Button(action: { print("개발자 정보 tapped") }) {
                                Label("5. 개발자 정보", systemImage: "person.info")
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundColor(.white) // Changed to white for better visibility
                                .padding(8)
                                .background(Color.gray.opacity(0.8))
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        }
                    }
                    .padding(.trailing, 10)
                }
            }
        }
    }
}

// MARK: - Opponent Area V2
struct OpponentAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
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
                OpponentHandV2(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, handConfig: handConfig, hand: gameManager.players[1].hand)
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
                
                CapturedAreaV2(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, layoutConfig: capConfig.layout, cards: gameManager.players[1].capturedCards, scale: capConfig.scale, alignLeading: false)
                    .position(x: frame.width * capConfig.x, y: finalY)
                    .zIndex(capConfig.zIndex)
            }
            
            // Score (Opponent)
            if let scoreConfig = areaConfig.elements.score, gameManager.players.count > 1 {
                ScoreViewV2(ctx: ctx, config: scoreConfig, score: gameManager.players[1].score)
                    .position(x: frame.width * scoreConfig.x, y: frame.height * scoreConfig.y)
                    .zIndex(scoreConfig.zIndex)
            }
        }
    }
}

// MARK: - Center Area V2
struct CenterAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
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
            TableAreaV2(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, config: tableConfig, cards: gameManager.tableCards, slotManager: tableSlotManager)
                .position(x: frame.width * tableConfig.x, y: frame.height * tableConfig.y)
                .zIndex(tableConfig.zIndex)
            
            // Deck
            let deckConfig = areaConfig.elements.deck
            DeckAreaV2(ctx: ctx, animationNamespace: animationNamespace, config: deckConfig, deckCount: gameManager.deck.cards.count, gameManager: gameManager)
                .position(x: frame.width * deckConfig.x, y: frame.height * deckConfig.y)
                .zIndex(deckConfig.zIndex)
        }
    }
}

// MARK: - Player Area V2
struct PlayerAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
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
                PlayerHandV2(ctx: ctx, animationNamespace: animationNamespace, config: handConfig, gameManager: gameManager, slotManager: slotManager, hand: player.hand)
                    .position(x: frame.width * handConfig.x, y: frame.height * handConfig.y)
                    .zIndex(handConfig.zIndex)
            }
            
            // Captured (Player)
            let capConfig = areaConfig.elements.captured
            if let player = gameManager.players.first {
                CapturedAreaV2(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, layoutConfig: capConfig.layout, cards: player.capturedCards, scale: capConfig.scale, alignLeading: true)
                    .position(x: frame.width * capConfig.x, y: frame.height * capConfig.y)
                    .zIndex(capConfig.zIndex)
            }
            
            // Score (Player)
            if let scoreConfig = areaConfig.elements.score, let player = gameManager.players.first {
                ScoreViewV2(ctx: ctx, config: scoreConfig, score: player.score)
                    .position(x: frame.width * scoreConfig.x, y: frame.height * scoreConfig.y)
                    .zIndex(scoreConfig.zIndex)
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

struct ScoreViewV2: View {
    let ctx: LayoutContext
    let config: ElementScoreConfig
    let score: Int
    
    var body: some View {
        let prefix = config.textPrefix ?? "점수: "
        Text("\(prefix)\(score)")
            .font(.system(
                size: (config.typography?.fontSizePt ?? 20) * ctx.globalScale,
                weight: config.typography?.weightSwiftUI ?? .bold
            ))
            .foregroundColor(config.typography?.colorSwiftUI ?? .primary)
            .padding(.horizontal, 12 * ctx.globalScale)
            .padding(.vertical, 6 * ctx.globalScale)
            .background(Color.white.opacity(config.backgroundOpacity ?? 0.8))
            .cornerRadius(12 * ctx.globalScale)
            .shadow(radius: 2)
            .scaleEffect(config.scale)
    }
}

struct OpponentHandV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
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
                let isHidden = gameManager.currentMovingCards.contains(where: { $0.id == card.id }) || gameManager.hiddenInSourceCardIds.contains(card.id)
                let isPreplayReveal = gameManager.opponentPreplayRevealCardId == card.id
                // Opponent Hand remains source
                CardView(card: card, isFaceUp: isPreplayReveal, scale: handConfig.scale, animationNamespace: animationNamespace, isSource: true)
                    .scaleEffect(isPreplayReveal ? 1.08 : 1.0)
                    .shadow(color: isPreplayReveal ? .yellow.opacity(0.55) : .clear, radius: isPreplayReveal ? 8 : 0)
                    .offset(x: CGFloat(index) * spacing)
                    .zIndex(Double(index))
                    .opacity(isHidden ? 0 : 1)
            }
        }
        .frame(width: cardW + (CGFloat(max(0, hand.count - 1)) * spacing), height: ctx.cardSize.height * handConfig.scale)
    }
}

struct PlayerHandV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    let config: ElementHandConfig
    @ObservedObject var gameManager: GameManager
    var slotManager: PlayerHandSlotManager?
    let hand: [Card]
    
    var body: some View {
        Group {
            if config.mode == "fixedSlots10", let manager = slotManager {
                PlayerHandFixedSlotsView(ctx: ctx, animationNamespace: animationNamespace, config: config, manager: manager, gameManager: gameManager)
            } else {
                PlayerHandGridV1(ctx: ctx, animationNamespace: animationNamespace, config: config, gameManager: gameManager, hand: hand)
            }
        }
    }
}

struct PlayerHandFixedSlotsView: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    let config: ElementHandConfig
    @ObservedObject var manager: PlayerHandSlotManager
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        let currentHandIds = Set((gameManager.players.first?.hand ?? []).map { $0.id })
        
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
                         if let card = manager.card(at: slot.slotIndex), currentHandIds.contains(card.id) {
                             ZStack {
                                 let isHidden = gameManager.currentMovingCards.contains(where: { $0.id == card.id }) || gameManager.hiddenInSourceCardIds.contains(card.id)
                                 // Hand card remains source
                                 CardView(card: card, isFaceUp: true, scale: config.scale, animationNamespace: animationNamespace, isSource: true, showDebugInfo: ctx.config.debug.player?.sortedOrderOverlay == true)
                                     .onTapGesture {
                                         gameManager.playTurn(card: card)
                                     }
                                     .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                                     .opacity(isHidden ? 0 : 1)
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
    let animationNamespace: Namespace.ID?
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
                             let isHidden = gameManager.currentMovingCards.contains(where: { $0.id == card.id }) || gameManager.hiddenInSourceCardIds.contains(card.id)
                             CardView(card: card, isFaceUp: true, scale: scale, animationNamespace: animationNamespace, isSource: true)
                                 .onTapGesture {
                                     gameManager.playTurn(card: card)
                                 }
                                 .opacity(isHidden ? 0 : 1)
                         }
                    }
                }
            }
        }
    }
}

struct CapturedAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
    let layoutConfig: CapturedLayoutConfigV2
    let cards: [Card]
    let scale: CGFloat
    let alignLeading: Bool
    
    var body: some View {
        if let groups = layoutConfig.groups {
            CapturedGroupsAreaV2(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, layoutConfig: layoutConfig, groups: groups, cards: cards, scale: scale)
        } else {
            legacyScrollView
        }
    }
    
    var legacyScrollView: some View {
        let cardW = ctx.cardSize.width * scale
        let overlapRatio = layoutConfig.cardOverlapRatio
        // Negative spacing for overlap
        let startSpacing = -cardW * overlapRatio
        let capturedActsAsTarget = gameManager.currentMoveTargetZone == "captured"
        
        return ScrollView(.horizontal, showsIndicators: false) {
             HStack(spacing: startSpacing) {
                 ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                     let isHidden = capturedActsAsTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                     let isTarget = capturedActsAsTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                     CardView(card: card, isFaceUp: true, scale: scale, animationNamespace: animationNamespace, isSource: !isTarget)
                        .zIndex(Double(index))
                        .opacity(isHidden ? 0 : 1)
                 }
             }
             .padding(.horizontal, ctx.scaledTokens.panelPadding)
        }
        .frame(height: ctx.cardSize.height * scale)
    }
}

struct CapturedGroupsAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
    let layoutConfig: CapturedLayoutConfigV2
    let groups: [CapturedGroupConfigV2]
    let cards: [Card]
    let scale: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let padding = ctx.scaledTokens.panelPadding * 2
            let cardW = ctx.cardSize.width * scale
            let vSpacing = cardW * layoutConfig.groupSpacingCardRatio
            let totalSpacing = vSpacing * CGFloat(groups.count - 1)
            let baseActiveWidth = max(0, totalWidth - padding - totalSpacing)
            
            let totalWeight = groups.reduce(0) { $0 + $1.priorityWeight }
            
            HStack(alignment: .bottom, spacing: vSpacing) {
                ForEach(groups, id: \.type) { group in
                    let groupCards = cards.filter { matchCardType(card: $0, targetType: group.type) }
                    let groupWidth = totalWeight > 0 ? baseActiveWidth * (group.priorityWeight / totalWeight) : 0
                    
                    CapturedGroupSlotView(
                        ctx: ctx,
                        animationNamespace: animationNamespace,
                        gameManager: gameManager,
                        groupConfig: group,
                        layoutConfig: layoutConfig,
                        cards: groupCards,
                        scale: scale,
                        allocatedWidth: groupWidth
                    )
                }
            }
            .padding(.horizontal, ctx.scaledTokens.panelPadding)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .frame(height: ctx.cardSize.height * scale * 1.8) // Extra space for wrapped cards
    }
    
    func matchCardType(card: Card, targetType: String) -> Bool {
        // Special case: September Animal (Chrysanthemum) can switch between Animal and Pi
        if card.month == .sep && card.type == .animal {
            let role = card.selectedRole ?? {
                let defaultRoleStr = RuleLoader.shared.config?.cards.chrysanthemum_rule.default_role ?? "animal"
                return CardRole(rawValue: defaultRoleStr) ?? .animal
            }()
            
            if targetType == "animal" { return role == .animal }
            if targetType == "pi" { return role == .doublePi }
            return false
        }
        
        // Special case: November Junk is actually Double Pi
        if card.month == .nov && (card.type == .junk || card.type == .doubleJunk) {
            if targetType == "pi" { return true }
            return false
        }
        
        if targetType == "gwang" { return card.type == .bright }
        if targetType == "animal" { return card.type == .animal }
        if targetType == "ribbon" { return card.type == .ribbon }
        if targetType == "pi" { return card.type == .junk || card.type == .doubleJunk }
        return false
    }
}

struct CapturedGroupSlotView: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
    let groupConfig: CapturedGroupConfigV2
    let layoutConfig: CapturedLayoutConfigV2
    let cards: [Card]
    let scale: CGFloat
    let allocatedWidth: CGFloat
    
    var body: some View {
        let cardW = ctx.cardSize.width * scale
        let cardH = ctx.cardSize.height * scale
        
        let defaultOverlap = layoutConfig.cardOverlapRatio
        let maxCols = groupConfig.maxCols
        let maxRows = groupConfig.maxRows
        
        // Rows
        let rowCount = max(1, min(maxRows, Int(ceil(Double(max(1, cards.count)) / Double(maxCols)))))
        let rowHeight = cardH * 0.35 // Overlap rows vertically visually
        let totalHeight = cardH + (CGFloat(rowCount - 1) * rowHeight)
        
        // Limit width to allocatedWidth but ensure at least cardW
        let frameWidth = max(cardW, allocatedWidth)
        
        ZStack(alignment: .topLeading) {
            // Background
            if groupConfig.background.opacity > 0 {
                RoundedRectangle(cornerRadius: groupConfig.background.cornerRadiusPt * ctx.globalScale)
                    .fill(groupConfig.background.colorSwiftUI)
                    .frame(width: frameWidth, height: totalHeight)
            }
            
            // Cards
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let row = index / maxCols
                let col = index % maxCols
                
                let effectiveRow = min(row, maxRows - 1)
                let effectiveCol = (row >= maxRows) ? (col + ((row - maxRows + 1) * maxCols)) : col 
                
                let totalInThisRow = min(maxCols, cards.count - (effectiveRow * maxCols))
                let trueCardsInRow = (effectiveRow == maxRows - 1) ? (cards.count - (effectiveRow * maxCols)) : totalInThisRow

                let yOffset = CGFloat(effectiveRow) * rowHeight
                
                let availableW = max(0, frameWidth - cardW)
                let defaultSpacing = cardW * (1.0 - defaultOverlap)
                
                let spacing: CGFloat = {
                    if trueCardsInRow <= 1 { return 0 }
                    let neededWidth = CGFloat(trueCardsInRow - 1) * defaultSpacing
                    if neededWidth <= availableW {
                        return defaultSpacing
                    } else {
                        // Compress
                        return availableW / CGFloat(trueCardsInRow - 1)
                    }
                }()
                
                let drawCol = (effectiveRow == maxRows - 1) ? (index - (effectiveRow * maxCols)) : effectiveCol
                let xOffset = CGFloat(drawCol) * spacing
                
                ZStack {
                    let piCount: Int? = {
                        if groupConfig.type == "pi", index == cards.count - 1 {
                             if let rules = RuleLoader.shared.config {
                                 return ScoringSystem.calculatePiCount(cards: cards, rules: rules)
                             }
                             // Fallback
                             return cards.reduce(0) { total, card in
                                 if card.type == .doubleJunk { return total + 2 }
                                 if card.month == .sep && card.selectedRole == .doublePi { return total + 2 }
                                 return total + 1
                             }
                        }
                        return nil
                    }()
                    
                    let isHidden = (gameManager.currentMoveTargetZone == "captured") && gameManager.hiddenInTargetCardIds.contains(card.id)
                    let isTarget = (gameManager.currentMoveTargetZone == "captured") && gameManager.hiddenInTargetCardIds.contains(card.id)
                    CardView(card: card, isFaceUp: true, scale: scale, animationNamespace: animationNamespace, isSource: !isTarget, piCount: piCount)
                        .opacity(isHidden ? 0 : 1)
                }
                .position(x: cardW/2 + xOffset, y: cardH/2 + yOffset)
                .zIndex(Double(index))
            }
            
            // Label
            Text(groupConfig.label)
                .font(.system(size: 9 * ctx.globalScale, weight: .bold))
                .foregroundColor(.black.opacity(0.6))
                .padding(2)
                .background(Color.white.opacity(0.5))
                .cornerRadius(2)
                .offset(x: 2, y: 2)
                .zIndex(1000)
        }
        .frame(width: frameWidth, height: totalHeight)
    }
}

struct TableAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
    let config: ElementTableConfig
    let cards: [Card]
    var slotManager: TableSlotManager?
    
    var body: some View {
        Group {
            if config.mode == "fixedSlots12", let manager = slotManager {
                TableFixedSlotsView(ctx: ctx, animationNamespace: animationNamespace, gameManager: gameManager, config: config, manager: manager)
            } else {
                legacyGrid
            }
        }
    }
    
    var legacyGrid: some View {
        let groups = Dictionary(grouping: cards, by: { $0.month }).values.sorted(by: { $0.first!.month.rawValue < $1.first!.month.rawValue })
        let tableActsAsTarget = gameManager.currentMoveTargetZone == "table"
        let hideTableTarget = tableActsAsTarget && gameManager.currentMoveSourceZone == "deck"
        
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
                        let isHidden = hideTableTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                        let isTarget = tableActsAsTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                        CardView(card: card, isFaceUp: true, scale: config.scale, animationNamespace: animationNamespace, isSource: !isTarget)
                            .offset(y: CGFloat(i) * (cardH * (1.0 - config.grid.stackOverlapRatio))) 
                            .opacity(isHidden ? 0 : 1)
                    }
                }
                .frame(width: cardW, height: cardH) // Fixed frame for stack base
            }
        }
    }
}

struct TableFixedSlotsView: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    @ObservedObject var gameManager: GameManager
    let config: ElementTableConfig
    @ObservedObject var manager: TableSlotManager
    
    var body: some View {
        let cardW = ctx.cardSize.width * config.scale
        let cardH = ctx.cardSize.height * config.scale
        let currentTableIds = Set(gameManager.tableCards.map { $0.id })
        let tableActsAsTarget = gameManager.currentMoveTargetZone == "table"
        let hideTableTarget = tableActsAsTarget && gameManager.currentMoveSourceZone == "deck"
        
        ZStack {
             if let fixedSlots = config.fixedSlots {
                 ForEach(fixedSlots.slots, id: \.slotIndex) { slot in
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
                         let stack = manager.cards(at: slot.slotIndex).filter { currentTableIds.contains($0.id) }
                         if !stack.isEmpty {
                             ZStack {
                                  ForEach(Array(stack.enumerated()), id: \.element.id) { i, card in
                                      let direction = config.grid.stackDirection ?? "vertical"
                                      let overlap = config.grid.stackOverlapRatio
                                      
                                      let isHorizontal = direction == "horizontal"
                                      let isDiagonal = direction == "diagonal"
                                      
                                      let xOff = (isHorizontal || isDiagonal) ? CGFloat(i) * (cardW * (1.0 - overlap)) : 0
                                      let yOff = (!isHorizontal) ? CGFloat(i) * (cardH * (1.0 - overlap)) : 0
                                      let isHidden = hideTableTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                                      let isTarget = tableActsAsTarget && gameManager.hiddenInTargetCardIds.contains(card.id)
                                      CardView(card: card, isFaceUp: true, scale: config.scale, animationNamespace: animationNamespace, isSource: !isTarget, showDebugInfo: ctx.config.debug.player?.sortedOrderOverlay == true)
                                          .offset(x: xOff, y: yOff)
                                          .zIndex(Double(i))
                                          .opacity(isHidden ? 0 : 1)
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



// Helper Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

struct DeckAreaV2: View {
    let ctx: LayoutContext
    let animationNamespace: Namespace.ID?
    let config: ElementDeckConfig
    let deckCount: Int
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        ZStack {
            if deckCount > 0 {
                // Background stack of cards (visual only)
                ForEach(0..<min(5, deckCount - 1), id: \.self) { index in
                   CardView(card: Card(id: "deck_bg_\(index)", month: .jan, type: .junk, imageIndex: 2), isFaceUp: false, scale: config.scale, animationNamespace: nil)
                        .offset(x: CGFloat(index) * 0.5, y: CGFloat(index) * 0.5)
                }
                
                // The actual top card that will be flipped/moved
                if let topCard = gameManager.deck.cards.last {
                    CardView(card: topCard, isFaceUp: false, scale: config.scale, animationNamespace: animationNamespace)
                        .offset(x: CGFloat(min(5, deckCount - 1)) * 0.5, y: CGFloat(min(5, deckCount - 1)) * 0.5)
                        .opacity((gameManager.currentMovingCards.contains(where: { $0.id == topCard.id }) || gameManager.hiddenInSourceCardIds.contains(topCard.id)) ? 0 : 1)
                }
            } else {
                Color.clear
            }
        }
    }
}
