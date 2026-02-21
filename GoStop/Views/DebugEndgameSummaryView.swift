import SwiftUI

struct DebugEndgameSummaryView: View {
    let result: PenaltySystem.PenaltyResult
    let reason: GameEndReason
    let winner: Player
    let loser: Player
    let onRestart: () -> Void
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack {
                Text("Endgame Debug Summary")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top)
                
                Text(terminationText)
                    .font(.title3)
                    .foregroundColor(.yellow)
                    .padding(.bottom, 5)
                
                ScrollView {
                    VStack(spacing: 20) {
                        playerSection(title: "Winner: \(winner.name) (Score: \(result.finalScore))", player: winner, isWinner: true)
                        playerSection(title: "Loser: \(loser.name)", player: loser, isWinner: false)
                        penaltySection()
                    }
                    .padding()
                }
                
                Button(action: onRestart) {
                    Text("Close & Restart")
                        .font(.title2)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
        }
    }
    
    var terminationText: String {
        switch reason {
        case .stop: return "Game Ended By STOP call"
        case .maxScore: return "Game Ended Due to Max Round Score Reached"
        case .nagari: return "Game Ended in Nagari (Deck Empty)"
        case .chongtong: return "Game Ended by Chongtong (4 of a Month)"
        }
    }
    
    @ViewBuilder
    func playerSection(title: String, player: Player, isWinner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
                .foregroundColor(isWinner ? .green : .red)
            
            Group {
                Text("Cards in Hand: \(player.hand.count)")
                Text("Pi Count: \(player.piCount)")
                Text("Go Count: \(player.goCount)")
                Text("Shakes: \(player.shakeCount)")
                Text("Bombs (폭탄): \(player.bombCount)")
                Text("Sweeps (싹쓸이): \(player.sweepCount)")
                Text("Ttadak (따닥): \(player.ttadakCount)")
                Text("Jjok (쪽): \(player.jjokCount)")
                Text("Seolsa/Bbeuk (뻑/설사): \(player.seolsaCount)")
                Text("Mung-dda (멍따): \(player.mungddaCount)")
                Text("Bomb Mung-dda (폭탄 멍따): \(player.bombMungddaCount)")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
            
            if isWinner, RuleLoader.shared.config != nil {
                let details = ScoringSystem.calculateScoreDetail(for: player)
                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Base Score Breakdown:")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.top, 5)
                        ForEach(details, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text("\(item.points) pts")
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    func penaltySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Penalties Applied")
                .font(.title2)
                .bold()
                .foregroundColor(.orange)
            
            Group {
                Text("Gwangbak: \(result.isGwangbak ? "Yes" : "No")")
                Text("Pibak: \(result.isPibak ? "Yes" : "No")")
                Text("Gobak: \(result.isGobak ? "Yes" : "No")")
                Text("Mungbak: \(result.isMungbak ? "Yes" : "No")")
                Text("Jabak: \(result.isJabak ? "Yes" : "No")")
                Text("Yeokbak: \(result.isYeokbak ? "Yes" : "No")")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    let gm = GameManager()
    let p1 = Player(name: "Player 1")
    let p2 = Player(name: "Computer")
    let res = PenaltySystem.PenaltyResult(finalScore: 56, isGwangbak: true, isPibak: true, isGobak: false, isMungbak: false, isJabak: false, isYeokbak: false)
    DebugEndgameSummaryView(result: res, reason: .maxScore, winner: p1, loser: p2, onRestart: {}, gameManager: gm)
}
