import SwiftUI

struct DebugLayoutOverlayV2: View {
    let ctx: LayoutContext
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Safe Area Boundary
            if ctx.config.debug.showSafeArea {
                Rectangle()
                    .strokeBorder(Color.green, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .frame(width: ctx.safeArea.width, height: ctx.safeArea.height)
                    .overlay(Text("Safe Area").foregroundColor(.green).font(.caption).padding(2), alignment: .topLeading)
            }
            
            // 2. Area Frames
            if ctx.config.debug.showGrid {
                ForEach([LayoutContext.AreaType.opponent, .center, .player], id: \.self) { area in
                    let frame = ctx.frame(for: area)
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .strokeBorder(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2]))
                        Text("\(area)")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(2)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            
            // 3. Element Bounds
            if ctx.config.debug.showElementBounds {
                // Opponent Elements
                let opponentArea = ctx.frame(for: .opponent)
                let oppConfig = ctx.config.areas.opponent.elements
                
                debugElement(x: oppConfig.hand.x, y: oppConfig.hand.y, label: "OppHand", in: opponentArea)
                debugElement(x: oppConfig.captured.x, y: oppConfig.captured.y, label: "OppCap", in: opponentArea)
                
                // Center Elements
                let centerArea = ctx.frame(for: .center)
                let centerConfig = ctx.config.areas.center.elements
                
                debugElement(x: centerConfig.table.x, y: centerConfig.table.y, label: "Table", in: centerArea)
                debugElement(x: centerConfig.deck.x, y: centerConfig.deck.y, label: "Deck", in: centerArea)
                
                // Player Elements
                let playerArea = ctx.frame(for: .player)
                let playerConfig = ctx.config.areas.player.elements
                
                debugElement(x: playerConfig.hand.x, y: playerConfig.hand.y, label: "PlayHand", in: playerArea)
                debugElement(x: playerConfig.captured.x, y: playerConfig.captured.y, label: "PlayCap", in: playerArea)
            }
        }
        .frame(width: ctx.safeArea.width, height: ctx.safeArea.height)
        .allowsHitTesting(false) // Pass touches through
    }
    
    func debugElement(x ratioX: CGFloat, y ratioY: CGFloat, label: String, in areaFrame: CGRect) -> some View {
        let posX = areaFrame.minX + (areaFrame.width * ratioX)
        let posY = areaFrame.minY + (areaFrame.height * ratioY)
        
        return Circle()
            .fill(Color.blue)
            .frame(width: 6, height: 6)
            .overlay(Text(label).font(.system(size: 8)).foregroundColor(.blue).offset(y: -10))
            .position(x: posX, y: posY)
    }
}

// Helper to make AreaType Hashable for ForEach
extension LayoutContext.AreaType: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .setting: hasher.combine(0)
        case .opponent: hasher.combine(1)
        case .center: hasher.combine(2)
        case .player: hasher.combine(3)
        }
    }
}
