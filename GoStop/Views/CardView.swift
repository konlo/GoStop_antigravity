import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    var scale: CGFloat = 1.0
    var animationNamespace: Namespace.ID? = nil
    var isSource: Bool = true
    var piCount: Int? = nil
    var showDebugInfo: Bool = false
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
