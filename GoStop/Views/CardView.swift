import SwiftUI

struct CardView: View {
    let card: Card
    var isFaceUp: Bool = true
    
    var body: some View {
        ZStack {
            // Card Background
            RoundedRectangle(cornerRadius: 6)
                .fill(isFaceUp ? Color.white : Color(red: 0.8, green: 0.2, blue: 0.2)) // Red back for Hwatu
                .shadow(radius: 2, y: 1)
            
            // Border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 1)
            
            if isFaceUp {
                VStack(spacing: 0) {
                    // Month Number (Top Left) (Optional, for debug/learning)
                    HStack {
                        Text("\(card.month.rawValue)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    contentView
                        .padding(.bottom, 5)
                    
                    Spacer()
                }
            } else {
                // Back Design (Simple Circle)
                Circle()
                    .fill(Color(red: 0.6, green: 0.1, blue: 0.1))
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 45, height: 70) // Slightly adjusted standard ratio
    }
    
    @ViewBuilder
    var contentView: some View {
        switch card.type {
        case .bright:
            VStack(spacing: 2) {
                Image(systemName: "sun.max.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundStyle(.red)
                Text("광")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.red))
            }
        case .animal:
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.brown)
            if card.isBird {
                 Image(systemName: "bird.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.gray)
            }
        case .ribbon:
            Image(systemName: "ribbon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.blue) // Need to differ by color later
        case .junk:
            EmptyView() // Just the flower/month art usually
            Text("피")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        case .doubleJunk:
             Text("쌍피")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    HStack {
        CardView(card: Card(month: .jan, type: .bright))
        CardView(card: Card(month: .feb, type: .animal))
        CardView(card: Card(month: .mar, type: .ribbon), isFaceUp: false)
    }
    .padding()
    .background(Color.green)
}
