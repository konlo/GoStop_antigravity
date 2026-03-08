import Foundation

// A CLI for Test Agent interaction.
// This reads lines of JSON from standard input, acts on the game engine, and prints JSON responses.

struct CommandRequest: Codable {
    let action: String
    let data: [String: AnyCodable]?
}

class CLIEngine {
    let gameManager = GameManager()
    var currentSeed: Int? = nil
    
    func handle(request: CommandRequest) -> [String: Any] {
        switch request.action {
        case "get_state":
            return TestControlSupport.serializedStatePayload(from: gameManager)
            
        case "start_game":
            gameManager.startGame()
            return ["status": "action executed", "action": "start_game"]
            
        case "play_card":
            guard let data = TestControlSupport.unbox(request.data),
                  let monthIdx = data["month"] as? Int,
                  let typeStr = data["type"] as? String else {
                return ["status": "error", "message": "Missing month or type for play_card"]
            }
            
            let type = TestControlSupport.parseCardType(typeStr)
            
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
            guard let data = TestControlSupport.unbox(request.data),
                  let isGo = data["isGo"] as? Bool else {
                return ["status": "error", "message": "Missing isGo for respond_go_stop"]
            }
            gameManager.respondToGoStop(isGo: isGo)
            return ["status": "action executed", "action": "respond_go_stop"]
            
        case "respond_to_shake":
            guard let data = TestControlSupport.unbox(request.data),
                  let monthIdx = data["month"] as? Int,
                  let didShake = data["didShake"] as? Bool else {
                return ["status": "error", "message": "Missing month or didShake for respond_to_shake"]
            }
            gameManager.respondToShake(month: monthIdx, didShake: didShake)
            return ["status": "action executed", "action": "respond_to_shake"]

        case "respond_to_capture":
            guard let data = TestControlSupport.unbox(request.data),
                  let cardId = data["id"] as? String else {
                return ["status": "error", "message": "Missing id for respond_to_capture"]
            }
            guard let tableCard = gameManager.tableCards.first(where: { $0.id == cardId }) else {
                return ["status": "error", "message": "Card with ID \(cardId) not found on table"]
            }
            gameManager.respondToCapture(selectedCard: tableCard)
            return ["status": "action executed", "action": "respond_to_capture"]
            
        case "respond_to_chrysanthemum_choice":
            guard let data = TestControlSupport.unbox(request.data),
                  let roleStr = data["role"] as? String else {
                return ["status": "error", "message": "Missing role for respond_to_chrysanthemum_choice"]
            }
            let role = TestControlSupport.parseCardRole(roleStr)
            gameManager.respondToChrysanthemumChoice(role: role)
            return ["status": "action executed", "action": "respond_to_chrysanthemum_choice"]

        case "get_persistence_probe_config":
            return [
                "status": "ok",
                "action": request.action,
                "data": TestControlSupport.persistenceProbeData()
            ]

        case "set_persistence_probe_config":
            guard let data = TestControlSupport.unbox(request.data) else {
                return ["status": "error", "message": "Missing data for set_persistence_probe_config"]
            }
            switch TestControlSupport.updatePersistenceProbeConfig(with: data) {
            case .success(let payload):
                return [
                    "status": "ok",
                    "action": request.action,
                    "data": payload
                ]
            case .failure(let error):
                let message = error.localizedDescription
                return ["status": "error", "message": message]
            }

        case "set_condition":
            if let data = TestControlSupport.unbox(request.data) {
                do {
                    try TestControlSupport.applyTestCondition(
                        data,
                        to: gameManager,
                        didUpdateSeed: { [weak self] seed in
                            self?.currentSeed = seed
                        }
                    )
                } catch {
                    return ["status": "error", "message": "Failed to apply custom_rules: \(error.localizedDescription)"]
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

        case "reset_busy_state":
            gameManager.emergencyResetBusyState()
            return ["status": "ok", "action": "reset_busy_state"]
            
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
}

func main() {
    // Explicitly load rules at startup
    RuleLoader.shared.loadRules()

    // CLI is used by automated scenarios; run turn logic synchronously to avoid
    // animation-delay race conditions during state assertions.
    AnimationManager.shared.config.card_move_duration = 0
    AnimationManager.shared.config.capture_to_player_duration = 0
    AnimationManager.shared.config.deck_to_table_duration = 0
    AnimationManager.shared.config.table_to_captured_duration = 0
    AnimationManager.shared.config.captured_to_captured_duration = 0
    AnimationManager.shared.config.deck_to_table_motion = "instant"
    AnimationManager.shared.config.table_to_captured_motion = "instant"
    AnimationManager.shared.config.captured_to_captured_motion = "instant"
    AnimationManager.shared.config.match_pause_duration = 0
    AnimationManager.shared.config.opponent_preplay_reveal_duration = 0
    AnimationManager.shared.config.opponent_action_delay = 0
    
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
