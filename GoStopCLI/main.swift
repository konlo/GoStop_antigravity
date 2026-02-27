import Foundation
import Combine

// A CLI for Test Agent interaction.
// This reads lines of JSON from standard input, acts on the game engine, and prints JSON responses.

struct CommandRequest: Codable {
    let action: String
    let data: [String: AnyCodable]?
}


struct GameStateDump: Codable {
    let status: String
    let gameState: String
    let players: [Player]
    let currentTurnIndex: Int
    let tableCards: [Card]
    let deckCount: Int
    let deckCards: [Card]
    let outOfPlayCount: Int
    let outOfPlayCards: [Card]
    let pendingChrysanthemumCard: Card?
}

class CLIEngine {
    let gameManager = GameManager()
    var currentSeed: Int? = nil
    
    func handle(request: CommandRequest) -> [String: Any] {
        switch request.action {
        case "get_state":
            return dumpState()
            
        case "start_game":
            gameManager.startGame()
            return ["status": "action executed", "action": "start_game"]
            
        case "play_card":
            guard let data = request.data,
                  let monthIdx = data["month"]?.value as? Int,
                  let typeStr = data["type"]?.value as? String else {
                return ["status": "error", "message": "Missing month or type for play_card"]
            }
            
            let type: CardType
            switch typeStr {
            case "bright": type = .bright
            case "animal": type = .animal
            case "ribbon": type = .ribbon
            case "doubleJunk": type = .doubleJunk
            case "dummy": type = .dummy
            default: type = .junk
            }
            
            // Find card in hand
            guard let player = gameManager.currentPlayer,
                  let card = player.hand.first(where: { $0.month.rawValue == monthIdx && $0.type == type }) else {
                // print("CLI DEBUG: Card \(monthIdx) \(type) NOT found in \(gameManager.currentPlayer?.name ?? "nil")'s hand.")
                return ["status": "error", "message": "Card not found in hand"]
            }
            
            // print("CLI DEBUG: Found card \(card.month) \(card.type). Calling gameManager.playTurn.")
            
            gameManager.playTurn(card: card)
            return ["status": "action executed", "action": "play_card"]
            
        case "respond_go_stop":
            guard let data = request.data,
                  let isGo = data["isGo"]?.value as? Bool else {
                return ["status": "error", "message": "Missing isGo for respond_go_stop"]
            }
            gameManager.respondToGoStop(isGo: isGo)
            return ["status": "action executed", "action": "respond_go_stop"]
            
        case "respond_to_shake":
            guard let data = request.data,
                  let monthIdx = data["month"]?.value as? Int,
                  let didShake = data["didShake"]?.value as? Bool else {
                return ["status": "error", "message": "Missing month or didShake for respond_to_shake"]
            }
            gameManager.respondToShake(month: monthIdx, didShake: didShake)
            return ["status": "action executed", "action": "respond_to_shake"]

        case "respond_to_capture":
            guard let data = request.data,
                  let cardId = data["id"]?.value as? String else {
                return ["status": "error", "message": "Missing id for respond_to_capture"]
            }
            guard let tableCard = gameManager.tableCards.first(where: { $0.id == cardId }) else {
                return ["status": "error", "message": "Card with ID \(cardId) not found on table"]
            }
            gameManager.respondToCapture(selectedCard: tableCard)
            return ["status": "action executed", "action": "respond_to_capture"]
            
        case "respond_to_chrysanthemum_choice":
            guard let data = request.data,
                  let roleStr = data["role"]?.value as? String else {
                return ["status": "error", "message": "Missing role for respond_to_chrysanthemum_choice"]
            }
            let role: CardRole = roleStr == "doublePi" ? .doublePi : .animal
            gameManager.respondToChrysanthemumChoice(role: role)
            return ["status": "action executed", "action": "respond_to_chrysanthemum_choice"]

        case "set_condition":
            if let data = request.data {
                if let scenario = data["mock_scenario"]?.value as? String, scenario == "game_over" {
                    gameManager.gameState = .ended
                }
                
                if let seed = data["rng_seed"]?.value as? Int {
                    self.currentSeed = seed
                    gameManager.setupGame(seed: seed)
                }
                
                if let mockState = data["mock_gameState"]?.value as? String {
                    switch mockState {
                    case "ready": gameManager.gameState = .ready
                    case "playing": gameManager.gameState = .playing
                    case "askingGoStop": gameManager.gameState = .askingGoStop
                    case "askingShake": gameManager.gameState = .askingShake
                    case "ended": gameManager.gameState = .ended
                    default: break
                    }
                }

                if let mockCaptured = data["mock_captured_cards"]?.value as? [[String: Any]] {
                     let player = gameManager.players[0]
                     player.capturedCards = parseCards(mockCaptured)
                     player.score = ScoringSystem.calculateScore(for: player)
                }
                
                if let mockOpponentCaptured = data["mock_opponent_captured_cards"]?.value as? [[String: Any]] {
                     let opponent = gameManager.players[1]
                     opponent.capturedCards = parseCards(mockOpponentCaptured)
                     opponent.score = ScoringSystem.calculateScore(for: opponent)
                }

                if let mockHand = data["mock_hand"]?.value as? [[String: Any]] {
                     gameManager.players[0].hand = parseCards(mockHand)
                }
                
                if let clearDeck = data["clear_deck"]?.value as? Bool, clearDeck {
                    _ = gameManager.deck.drainAll()
                }

                if let mockDeckArr = data["mock_deck"]?.value as? [[String: Any]] {
                    gameManager.mockDeck(cards: parseCards(mockDeckArr))
                }
                
                if let mockTable = data["mock_table"]?.value as? [[String: Any]] {
                     gameManager.tableCards = parseCards(mockTable)
                }
                
                // Advanced player mocking
                for i in 0..<gameManager.players.count {
                    let key = "player\(i)_data"
                    if let pData = data[key]?.value as? [String: Any] {
                        let p = gameManager.players[i]
                        if let goCount = pData["goCount"] as? Int { p.goCount = goCount }
                        if let lastGoScore = pData["lastGoScore"] as? Int { p.lastGoScore = lastGoScore }
                        if let money = pData["money"] as? Int { p.money = money }
                        if let score = pData["score"] as? Int { p.score = score }
                        if let shakeCount = pData["shakeCount"] as? Int { p.shakeCount = shakeCount }
                        if let bombCount = pData["bombCount"] as? Int { p.bombCount = bombCount }
                        if let captured = pData["capturedCards"] as? [[String: Any]] {
                            p.capturedCards = self.parseCards(captured)
                            p.score = ScoringSystem.calculateScore(for: p)
                        }
                        if let hand = pData["hand"] as? [[String: Any]] {
                            p.hand = self.parseCards(hand)
                        }
                        if let sweepCount = pData["sweepCount"] as? Int { p.sweepCount = sweepCount }
                        if let ttadakCount = pData["ttadakCount"] as? Int { p.ttadakCount = ttadakCount }
                        if let jjokCount = pData["jjokCount"] as? Int { p.jjokCount = jjokCount }
                        if let seolsaCount = pData["seolsaCount"] as? Int { p.seolsaCount = seolsaCount }
                        if let isPiMungbak = pData["isPiMungbak"] as? Bool { p.isPiMungbak = isPiMungbak }
                        if let mungddaCount = pData["mungddaCount"] as? Int { p.mungddaCount = mungddaCount }
                        if let bombMungddaCount = pData["bombMungddaCount"] as? Int { p.bombMungddaCount = bombMungddaCount }
                        if let isComputer = pData["isComputer"] as? Bool { p.isComputer = isComputer }
                        if let dummyCardCount = pData["dummyCardCount"] as? Int { p.dummyCardCount = dummyCardCount }
                    }
                }
                
                // Allow tests to directly force the active player
                if let turnIdx = data["currentTurnIndex"]?.value as? Int,
                   gameManager.players.indices.contains(turnIdx) {
                    gameManager.currentTurnIndex = turnIdx
                }
                
                // Allow tests to pre-set month ownership (for Seolsa testing)
                // Format: {"mock_month_owners": {7: 1}} means month 7 is 'owned' by players[1]
                if let monthOwners = data["mock_month_owners"]?.value as? [String: Any] {
                    for (monthStr, ownerIdx) in monthOwners {
                        if let m = Int(monthStr), let idx = ownerIdx as? Int,
                           gameManager.players.indices.contains(idx) {
                            gameManager.monthOwners[m] = gameManager.players[idx]
                        }
                    }
                }
                if let mockEndReason = data["mock_gameEndReason"]?.value as? String {
                    gameManager.gameEndReason = GameEndReason(rawValue: mockEndReason)
                }
            }
            return ["status": "ok", "message": "Condition set"]
            
        case "click_restart_button":
            gameManager.setupGame(seed: currentSeed)
            return ["status": "action executed", "action": "click_restart_button"]
            
        case "mock_endgame_check":
            if let rules = RuleLoader.shared.config {
                let winner = gameManager.players[0]
                let opponent = gameManager.players[1]
                _ = gameManager.checkEndgameConditions(player: winner, opponent: opponent, rules: rules, isAfterGo: false)
            }
            return ["status": "action executed", "action": "mock_endgame_check"]
            
        case "force_chongtong_check":
            let timing = (request.data?["timing"]?.value as? String) ?? "initial"
            for player in gameManager.players {
                if let month = gameManager.getChongtongMonth(for: player) {
                    gameManager.resolveChongtong(player: player, month: month, timing: timing)
                }
            }
            return ["status": "action executed", "action": "force_chongtong_check"]
            
        case "invalid_action_triggering_crash":
            fatalError("Simulated App Crash for Testing")
            
        case "debug_test_dec_bug":
            gameManager.setupGame(seed: 42)
            gameManager.players[1].isComputer = true
            gameManager.tableCards = [
                Card(month: .dec, type: .bright, imageIndex: 0),
                Card(month: .dec, type: .doubleJunk, imageIndex: 3)
            ]
            let pCard = Card(month: .dec, type: .animal, imageIndex: 1)
            gameManager.players[1].hand = [pCard]
            gameManager.mockDeck(cards: [Card(month: .may, type: .junk, imageIndex: 0)])
            gameManager.currentTurnIndex = 1
            gameManager.gameState = .playing
            
            gLog("DEBUG START: Table: \(gameManager.tableCards.map{$0.type})")
            
            gameManager.playTurn(card: pCard)
            
            gLog("DEBUG AFTER PLAY: Table: \(gameManager.tableCards.map{$0.type})")
            gLog("DEBUG CAPTURED: \(gameManager.players[1].capturedCards.map{$0.type})")
            
            return ["status": "action executed", "action": request.action]
            
        default:
            return ["status": "action executed", "action": request.action]
        }
    }
    private func parseCards(_ array: [[String: Any]]) -> [Card] {
        return array.compactMap { dict -> Card? in
            guard let m = dict["month"] as? Int,
                  let tStr = dict["type"] as? String else { return nil }
            let type = parseType(tStr)
            let id = dict["id"] as? String ?? UUID().uuidString
            var card = Card(id: id, month: Month(rawValue: m) ?? .jan, type: type, imageIndex: 0)
            if let rStr = dict["selectedRole"] as? String {
                card.selectedRole = parseRole(rStr)
            }
            return card
        }
    }
    
    private func parseRole(_ rStr: String) -> CardRole {
        switch rStr {
        case "doublePi": return .doublePi
        case "animal": return .animal
        default: return .animal
        }
    }
    
    private func parseType(_ tStr: String) -> CardType {
        switch tStr {
        case "bright": return .bright
        case "animal": return .animal
        case "ribbon": return .ribbon
        case "doubleJunk": return .doubleJunk
        case "dummy": return .dummy
        default: return .junk
        }
    }
    
    private func dumpState() -> [String: Any] {
        let dump = GameStateDump(
            status: "ok",
            gameState: "\(gameManager.gameState)",
            players: gameManager.players,
            currentTurnIndex: gameManager.currentTurnIndex,
            tableCards: gameManager.tableCards,
            deckCount: gameManager.deck.cards.count,
            deckCards: gameManager.deck.cards,
            outOfPlayCount: gameManager.outOfPlayCards.count,
            outOfPlayCards: gameManager.outOfPlayCards,
            pendingChrysanthemumCard: gameManager.pendingChrysanthemumCard
        )
        
        guard let data = try? JSONEncoder().encode(dump),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "error", "message": "Failed to serialize state"]
        }
        
        // Inject score items for each player
        if var playersArray = dict["players"] as? [[String: Any]] {
            for i in 0..<gameManager.players.count {
                let items = ScoringSystem.calculateScoreDetail(for: gameManager.players[i])
                if let itemsData = try? JSONEncoder().encode(items),
                   let itemsArray = try? JSONSerialization.jsonObject(with: itemsData) as? [[String: Any]] {
                    playersArray[i]["scoreItems"] = itemsArray
                }
            }
            dict["players"] = playersArray
        }
        
        dict["eventLogs"] = gameManager.eventLogs
        
        if let playedCard = gameManager.pendingCapturePlayedCard,
           let cardData = try? JSONEncoder().encode(playedCard),
           let dictVal = try? JSONSerialization.jsonObject(with: cardData) {
            dict["pendingCapturePlayedCard"] = dictVal
        }
        if let drawnCard = gameManager.pendingCaptureDrawnCard,
           let cardData = try? JSONEncoder().encode(drawnCard),
           let dictVal = try? JSONSerialization.jsonObject(with: cardData) {
            dict["pendingCaptureDrawnCard"] = dictVal
        }
        
        if gameManager.gameState == .choosingCapture {
            if let optionsData = try? JSONEncoder().encode(gameManager.pendingCaptureOptions),
               let optionsArray = try? JSONSerialization.jsonObject(with: optionsData) as? [[String: Any]] {
                dict["pendingCaptureOptions"] = optionsArray
            }
        }
        
        // Inject pending shakes if in askingShake state
        if gameManager.gameState == .askingShake {
            dict["pendingShakeMonths"] = gameManager.pendingShakeMonths
        }
        
        if let month = gameManager.chongtongMonth {
            dict["chongtongMonth"] = month
        }
        if let timing = gameManager.chongtongTiming {
            dict["chongtongTiming"] = timing
        }
        
        // Inject penalty result if game ended
        if gameManager.gameState == .ended {
            if let lastResult = gameManager.lastPenaltyResult {
                dict["penaltyResult"] = [
                    "finalScore": lastResult.finalScore,
                    "isGwangbak": lastResult.isGwangbak,
                    "isPibak": lastResult.isPibak,
                    "isGobak": lastResult.isGobak,
                    "isMungbak": lastResult.isMungbak,
                    "isJabak": lastResult.isJabak,
                    "isYeokbak": lastResult.isYeokbak,
                    "scoreFormula": lastResult.scoreFormula
                ]
            } else if gameManager.gameEndReason == .nagari {
                dict["penaltyResult"] = [
                    "finalScore": 0,
                    "isGwangbak": false,
                    "isPibak": false,
                    "isGobak": false,
                    "isMungbak": false,
                    "isJabak": false,
                    "isYeokbak": false,
                    "scoreFormula": "Nagari (Draw)"
                ]
            } else if let rules = RuleLoader.shared.config {
                // Fallback for cases where lastPenaltyResult might not be set (legacy or specific edge cases)
                let winner = gameManager.players[0].score >= gameManager.players[1].score ? gameManager.players[0] : gameManager.players[1]
                let loser = winner === gameManager.players[0] ? gameManager.players[1] : gameManager.players[0]
                
                let penalty = PenaltySystem.calculatePenalties(winner: winner, loser: loser, rules: rules)
                dict["penaltyResult"] = [
                    "finalScore": penalty.finalScore,
                    "isGwangbak": penalty.isGwangbak,
                    "isPibak": penalty.isPibak,
                    "isGobak": penalty.isGobak,
                    "isMungbak": penalty.isMungbak,
                    "isJabak": penalty.isJabak,
                    "isYeokbak": penalty.isYeokbak,
                    "scoreFormula": penalty.scoreFormula
                ]
            }

            if let reason = gameManager.gameEndReason {
                dict["gameEndReason"] = reason.rawValue
            }
        }
        
        return dict
    }
}

func main() {
    // Explicitly load rules at startup
    RuleLoader.shared.loadRules()

    // CLI is used by automated scenarios; run turn logic synchronously to avoid
    // animation-delay race conditions during state assertions.
    AnimationManager.shared.config.card_move_duration = 0
    
    let engine = CLIEngine()
    
    // Standard input reading loop
    while let line = readLine() {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { continue }
        
        do {
            guard let cmdData = trimmedLine.data(using: .utf8) else { continue }
            let request = try JSONDecoder().decode(CommandRequest.self, from: cmdData)
            
            let responseDict = engine.handle(request: request)
            
            let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
            
        } catch {
            let errResponse = ["status": "error", "error": error.localizedDescription]
            if let jsonData = try? JSONSerialization.data(withJSONObject: errResponse, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                fflush(stdout)
            }
        }
    }
}

main()
