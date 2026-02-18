import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    var scale: CGFloat = 1.0
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
                return ctx.scaledTokens.cardShadowRadius
            }
            return config.layout.card.shadowRadius
        }()
        
        let shadowOpacity: Double = {
            if let ctx = config.layoutContext {
                return ctx.config.card.shadow.opacity
            }
            return 0.33
        }()
        
        let shadowY: CGFloat = {
            if let ctx = config.layoutContext {
                return ctx.scaledTokens.cardShadowY
            }
            return 0
        }()
        
        ZStack {
            if isFaceUp {
                frontView
            } else {
                backView(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
    
    var frontView: some View {
        Image("\(config.layout.images.prefix)\(card.month)_\(card.imageIndex)")
            .resizable()
            .background(Color.white)
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
