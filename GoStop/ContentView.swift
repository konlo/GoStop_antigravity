import SwiftUI

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @State private var isShowingMultiplayerRoute = false
#if DEBUG
    @State private var isShowingMultiplayerLab = false
#endif
    
    private var shouldAutoPresentMultiplayerRoute: Bool {
        ProcessInfo.processInfo.environment["GOSTOP_MP_AUTOROUTE"] == "1"
    }

    var body: some View {
        GameView(gameManager: gameManager)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        isShowingMultiplayerRoute = true
                    } label: {
                        Label("Multiplayer", systemImage: "person.2.fill")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.12, green: 0.40, blue: 0.30).opacity(0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

#if DEBUG
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
#endif
                }
                .padding(.top, 10)
                .padding(.trailing, 14)
            }
            .fullScreenCover(isPresented: $isShowingMultiplayerRoute) {
                MultiplayerProductMultiplayerRouteView()
            }
#if DEBUG
            .sheet(isPresented: $isShowingMultiplayerLab) {
                MultiplayerShellLabView()
            }
#endif
            .onAppear {
                if shouldAutoPresentMultiplayerRoute {
                    isShowingMultiplayerRoute = true
                }
            }
    }
}

#Preview {
    ContentView()
}
