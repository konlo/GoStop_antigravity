import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    var scale: CGFloat = 1.0
    @ObservedObject var config = ConfigManager.shared
    
    var body: some View {
        let size = config.cardSize(scale: scale)
        
        ZStack {
            if isFaceUp {
                frontView
            } else {
                backView(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width * config.layout.card.cornerRadius)) // Relative corner radius
        .shadow(radius: config.layout.card.shadowRadius)
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
