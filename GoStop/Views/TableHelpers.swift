import SwiftUI

// A simple custom grid that fills N rows
struct LazyNStack<Content: View, Item>: View {
    let rows: Int
    let stacks: [Item]
    let alignment: HorizontalAlignment
    let vSpacing: CGFloat
    let hSpacing: CGFloat
    let content: (Item) -> Content
    
    var body: some View {
        VStack(spacing: vSpacing) {
            ForEach(0..<rows, id: \.self) { rowIndex in
                HStack(spacing: hSpacing) {
                    if alignment == .trailing { Spacer() }
                    
                    // Filter items for this row (simple modulo or split distribution)
                    // Let's do simple distribution: 0, 1 -> Row 0; 2, 3 -> Row 1 (if 4 items, 2 rows)
                    // Logic: Distribute items evenly across rows
                    let itemsForRow = getItems(for: rowIndex)
                    
                    ForEach(Array(itemsForRow.enumerated()), id: \.offset) { index, item in
                         content(item)
                    }
                    
                    if alignment == .leading { Spacer() }
                }
            }
        }
    }
    
    func getItems(for row: Int) -> [Item] {
        // Simple distribution: Fill row 0, then row 1...
        // Wait, user wants "2 rows... centered".
        // If we have 5 items and 2 rows -> 3 top, 2 bottom?
        // Let's assume sequential fill for now.
        let total = stacks.count
        if total == 0 { return [] }
        
        let itemsPerRow = Int(ceil(Double(total) / Double(rows)))
        let start = row * itemsPerRow
        if start >= total { return [] }
        let end = min(start + itemsPerRow, total)
        return Array(stacks[start..<end])
    }
}

struct TableCardStack: View {
    let stack: [Card]
    let overlapRatio: CGFloat
    let scale: CGFloat
    @ObservedObject var config = ConfigManager.shared
    @Namespace private var nspace // dummy if needed
    
    var body: some View {
        let cardSize = config.cardSize(scale: scale)
        let overlapOffset = cardSize.height * (1.0 - overlapRatio)
        
        ZStack {
            if stack.isEmpty {
                Color.clear.frame(width: cardSize.width, height: cardSize.height)
            } else {
                ForEach(Array(stack.enumerated()), id: \.element.id) { index, card in
                    // Overlap logic:
                    
                     CardView(card: card, scale: scale)
                        .offset(y: CGFloat(index) * overlapOffset)
                        .zIndex(Double(index))
                }
            }
        }
        .frame(width: cardSize.width, 
               height: cardSize.height + (CGFloat(max(0, stack.count - 1)) * overlapOffset))
    }
}
import SwiftUI

struct AreaBackgroundModifier: ViewModifier {
    let config: AreaBackgroundConfig?
    let gameWidth: CGFloat
    
    func body(content: Content) -> some View {
        if let bg = config {
            ZStack {
                RoundedRectangle(cornerRadius: bg.cornerRadius)
                    .fill(bg.colorSwiftUI)
                    .frame(width: gameWidth * bg.widthRatio)
                
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func areaBackground(_ config: AreaBackgroundConfig?, gameWidth: CGFloat) -> some View {
        self.modifier(AreaBackgroundModifier(config: config, gameWidth: gameWidth))
    }
}
import SwiftUI

struct DebugAreaOverlay: View {
    let gameWidth: CGFloat
    let gameHeight: CGFloat
    @ObservedObject var config = ConfigManager.shared
    
    // Tooltip State
    @State private var hoveredArea: String? = nil
    @State private var hoverPosition: CGPoint = .zero
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Calculate accumulating heights
            let opponentH = gameHeight * config.layout.areas.opponent.heightRatio
            let centerH = gameHeight * config.layout.areas.center.heightRatio
            let playerH = gameHeight * config.layout.areas.player.heightRatio
            
            // 1. Opponent Area
            debugRect(
                width: gameWidth,
                height: opponentH,
                x: gameWidth / 2,
                y: opponentH / 2,
                label: "Area: Opponent",
                keys: [
                    "areas.opponent.heightRatio: \(config.layout.areas.opponent.heightRatio)",
                    "elements: hand, captured"
                ]
            )
            
            // 2. Center Area
            debugRect(
                width: gameWidth,
                height: centerH,
                x: gameWidth / 2,
                y: opponentH + centerH / 2,
                label: "Area: Center",
                keys: [
                    "areas.center.heightRatio: \(config.layout.areas.center.heightRatio)",
                    "elements: table, deck"
                ]
            )
            
            // 3. Player Area
            debugRect(
                width: gameWidth,
                height: playerH,
                x: gameWidth / 2,
                y: opponentH + centerH + playerH / 2,
                label: "Area: Player",
                keys: [
                    "areas.player.heightRatio: \(config.layout.areas.player.heightRatio)",
                    "elements: hand, captured"
                ]
            )
            
            // Tooltip
            if let hovered = hoveredArea {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hovered)
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .position(x: hoverPosition.x, y: hoverPosition.y - 40) // Offset slightly up
                .zIndex(1000)
            }
        }
    }
    
    func debugRect(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, label: String, keys: [String]) -> some View {
        Rectangle()
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
            .foregroundColor(.red.opacity(0.7))
            .frame(width: width, height: height)
            .contentShape(Rectangle()) // Make entire area hit testable
            .onHover { isHovering in
                if isHovering {
                    hoveredArea = "\(label)\n" + keys.joined(separator: "\n")
                    hoverPosition = CGPoint(x: x, y: y)
                } else {
                    if hoveredArea?.starts(with: label) == true {
                        hoveredArea = nil
                    }
                }
            }
            .position(x: x, y: y)
    }
}
