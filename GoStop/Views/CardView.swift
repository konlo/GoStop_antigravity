import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    
    var body: some View {
        ZStack {
            if isFaceUp {
                frontView
            } else {
                backView
            }
        }
        .frame(width: 50, height: 80) // Standard Hwatu ratio approx 5:8
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(radius: 2)
    }
    
    var frontView: some View {
        Image("Card_\(card.month)_\(card.imageIndex)")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .background(Color.white)
    }
    
    var backView: some View {
        ZStack {
            Color(red: 0.8, green: 0.2, blue: 0.2) // Red back
            
            // Texture Pattern (Simple Circle)
            Circle()
                .fill(Color(red: 0.6, green: 0.1, blue: 0.1))
                .frame(width: 25, height: 25)
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
