import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    var scale: CGFloat = 1.0
    var animationNamespace: Namespace.ID? = nil
    var isSource: Bool = true
    var piCount: Int? = nil
    var showDebugInfo: Bool = false
    var isMoveSourceCue: Bool = false
    var isMoveTargetCue: Bool = false
    var isCapturedAreaCard: Bool = false
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        let size = config.cardSize(scale: scale)
        
        // V2 Layout Values
        let cornerRadius: CGFloat = {
            if let ctx = config.layoutContext {
                return size.width * ctx.config.card.cornerRadiusRatio
            }
            return size.width * config.layout.card.cornerRadius
        }()
        
        let shadowRadius: CGFloat = {
            if let ctx = config.layoutContext {
                return ctx.scaledTokens.cardShadowRadius * scale
            }
            return config.layout.card.shadowRadius * scale
        }()
        
        let shadowOpacity: Double = {
            if let ctx = config.layoutContext {
                return ctx.config.card.shadow.opacity
            }
            return 0.33
        }()
        
        let shadowY: CGFloat = {
            if let ctx = config.layoutContext {
                return ctx.scaledTokens.cardShadowY * scale
            }
            return 0
        }()
        
        let cueActive = isMoveSourceCue || isMoveTargetCue
        let isCapturedTargetCue = isCapturedAreaCard && isMoveTargetCue && !isMoveSourceCue
        let cueColor: Color = isMoveSourceCue ? .yellow : (isCapturedTargetCue ? .orange : .white)
        let cueScale: CGFloat = isMoveSourceCue ? 1.06 : (isCapturedTargetCue ? 1.07 : (isMoveTargetCue ? 1.03 : 1.0))
        let cueLineWidth: CGFloat = {
            guard cueActive else { return 0 }
            if isCapturedTargetCue { return max(2.8, 4.2 * scale) }
            return max(2, 3 * scale)
        }()
        let cueGlowOpacity: Double = cueActive ? (isCapturedTargetCue ? 0.95 : 0.75) : 0
        let cueGlowRadius: CGFloat = {
            guard cueActive else { return 0 }
            if isCapturedTargetCue { return max(10, 16 * scale) }
            return max(6, 10 * scale)
        }()
        
        ZStack {
            if isFaceUp {
                frontView
            } else {
                backView(size: size)
            }
            
            // Integrated Debug Info
            if showDebugInfo {
                VStack(spacing: 0) {
                    Text("M:\(card.month.rawValue)")
                    Text("T:\(card.type)")
                }
                .font(.system(size: 8 * scale * (config.layoutContext?.globalScale ?? 1.0)))
                .padding(2)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .offset(y: -size.height/2 + (10 * scale))
            }
            
            // Integrated Pi Count Badge
            if let count = piCount {
                Text("\(count)")
                    .font(.system(size: 11 * (config.layoutContext?.globalScale ?? 1.0) * scale, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4 * (config.layoutContext?.globalScale ?? 1.0) * scale)
                    .padding(.vertical, 2 * (config.layoutContext?.globalScale ?? 1.0) * scale)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                    .offset(x: size.width * 0.35, y: size.height * 0.35)
                    .shadow(radius: 1 * scale)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(config.layout.card.backColorSwiftUI) // Ensure background fills
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(cueColor.opacity(cueActive ? 0.98 : 0.0), lineWidth: cueLineWidth)
        )
        .scaleEffect(cueScale)
        .shadow(color: cueColor.opacity(cueGlowOpacity), radius: cueGlowRadius, x: 0, y: 0)
        .animation(.easeOut(duration: 0.09), value: isMoveSourceCue)
        .animation(.easeOut(duration: 0.09), value: isMoveTargetCue)
        .ifLet(animationNamespace) { view, ns in
            view.matchedGeometryEffect(id: card.id, in: ns, isSource: isSource)
        }
    }
    
    @ViewBuilder
    var frontView: some View {
        if card.month == .none {
            // Dummy (도탄) card – no image asset exists for month .none
            ZStack {
                Color.gray.opacity(0.25)
                VStack(spacing: 2) {
                    Text("도탄")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                }
            }
        } else {
            Image("\(config.layout.images.prefix)\(card.month)_\(card.imageIndex)")
                .resizable()
                .scaledToFit()
                .background(Color.white)
        }
    }
    
    func backView(size: CGSize) -> some View {
        ZStack {
            config.layout.card.backColorSwiftUI
            
            // Texture Pattern (Simple Circle)
            Circle()
                .fill(config.layout.card.backCircleColorSwiftUI)
                .frame(width: size.width * 0.5, height: size.width * 0.5)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.2), lineWidth: 1)
                )
            
            if card.type == .dummy {
                Text("D")
                    .font(.system(size: size.width * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// Helper extension for conditional view modifiers
extension View {
    @ViewBuilder
    func ifLet<V, Transform: View>(_ value: V?, transform: (Self, V) -> Transform) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

#Preview {
    HStack {
        // Updated Preview with imageIndex
        CardView(card: Card(month: .jan, type: .bright, imageIndex: 0))
        CardView(card: Card(month: .feb, type: .animal, imageIndex: 0))
        CardView(card: Card(month: .mar, type: .ribbon, imageIndex: 1), isFaceUp: false)
    }
    .padding()
    .background(Color.green)
}
