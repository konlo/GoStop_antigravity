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
                Text(gameText("summary.title"))
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
                        playerSection(
                            title: gameText("summary.winner_title", ["name": winner.name, "score": result.finalScore]),
                            player: winner,
                            isWinner: true
                        )
                        playerSection(
                            title: gameText("summary.loser_title", ["name": loser.name]),
                            player: loser,
                            isWinner: false
                        )
                        penaltySection()
                    }
                    .padding()
                }
                
                Button(action: onRestart) {
                    Text(gameText("common.button.close_restart"))
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
        case .stop: return gameText("summary.termination.stop")
        case .maxScore: return gameText("summary.termination.max_score")
        case .nagari: return gameText("summary.termination.nagari")
        case .chongtong: return gameText("summary.termination.chongtong")
        case .threeSeolsa: return gameText("summary.termination.three_seolsa")
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
                Text(gameText("summary.stat.cards_in_hand", ["count": player.hand.count]))
                Text(gameText("summary.stat.pi_count", ["count": player.piCount]))
                Text(gameText("summary.stat.go_count", ["count": player.goCount]))
                Text(gameText("summary.stat.shakes", ["count": player.shakeCount]))
                Text(gameText("summary.stat.bombs", ["count": player.bombCount]))
                Text(gameText("summary.stat.sweeps", ["count": player.sweepCount]))
                Text(gameText("summary.stat.ttadak", ["count": player.ttadakCount]))
                Text(gameText("summary.stat.jjok", ["count": player.jjokCount]))
                Text(gameText("summary.stat.seolsa", ["count": player.seolsaCount]))
                Text(gameText("summary.stat.mungdda", ["count": player.mungddaCount]))
                Text(gameText("summary.stat.bomb_mungdda", ["count": player.bombMungddaCount]))
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
            
            if isWinner, RuleLoader.shared.config != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text(gameText("summary.score_formula_title"))
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .padding(.top, 5)
                    
                    Text(result.scoreFormula)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(5)
                }
                
                let details = ScoringSystem.calculateScoreDetail(for: player)
                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(gameText("summary.base_score_breakdown_title"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.top, 5)
                        ForEach(details, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(gameText("common.label.score_points", ["points": item.points]))
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
            Text(gameText("summary.penalties_applied_title"))
                .font(.title2)
                .bold()
                .foregroundColor(.orange)
            
            Group {
                Text(gameText("summary.penalty_flag.gwangbak", ["value": result.isGwangbak ? gameText("common.value.yes") : gameText("common.value.no")]))
                Text(gameText("summary.penalty_flag.pibak", ["value": result.isPibak ? gameText("common.value.yes") : gameText("common.value.no")]))
                Text(gameText("summary.penalty_flag.gobak", ["value": result.isGobak ? gameText("common.value.yes") : gameText("common.value.no")]))
                Text(gameText("summary.penalty_flag.mungbak", ["value": result.isMungbak ? gameText("common.value.yes") : gameText("common.value.no")]))
                Text(gameText("summary.penalty_flag.jabak", ["value": result.isJabak ? gameText("common.value.yes") : gameText("common.value.no")]))
                Text(gameText("summary.penalty_flag.yeokbak", ["value": result.isYeokbak ? gameText("common.value.yes") : gameText("common.value.no")]))
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
    let res = PenaltySystem.PenaltyResult(finalScore: 56, isGwangbak: true, isPibak: true, isGobak: false, isMungbak: false, isJabak: false, isYeokbak: false, scoreFormula: "(15) x Pibak(x2) = 30")
    DebugEndgameSummaryView(result: res, reason: .maxScore, winner: p1, loser: p2, onRestart: {}, gameManager: gm)
}
