import SwiftUI

struct ContentView: View {
#if DEBUG
    @State private var isShowingMultiplayerLab = false
#endif

    var body: some View {
#if DEBUG
        GameView()
            .overlay(alignment: .topTrailing) {
                Button {
                    isShowingMultiplayerLab = true
                } label: {
                    Label("MP Lab", systemImage: "rectangle.3.group.bubble.left.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.74))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.trailing, 14)
            }
            .sheet(isPresented: $isShowingMultiplayerLab) {
                MultiplayerShellLabView()
            }
#else
        GameView()
#endif
    }
}

#Preview {
    ContentView()
}
