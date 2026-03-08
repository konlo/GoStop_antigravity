import Foundation

enum TestControlSupport {
    enum SupportError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    static let externallyControlledActions: Set<String> = [
        "play_card",
        "respond_go_stop",
        "respond_to_go",
        "respond_to_capture",
        "respond_to_shake",
        "decide_shake",
        "respond_to_chrysanthemum_choice",
        "decide_chrysanthemum"
    ]

    static func unbox(_ payload: [String: AnyCodable]?) -> [String: Any]? {
        payload?.mapValues { $0.value }
    }

    static func parseCardType(_ rawValue: String) -> CardType {
        switch rawValue {
        case "bright":
            return .bright
        case "animal":
            return .animal
        case "ribbon":
            return .ribbon
        case "doubleJunk":
            return .doubleJunk
        case "dummy":
            return .dummy
        default:
            return .junk
        }
    }

    static func parseCardRole(_ rawValue: String) -> CardRole {
        switch rawValue {
        case "doublePi":
            return .doublePi
        case "animal":
            return .animal
        default:
            return .animal
        }
    }

    static func parseCards(from payload: [[String: Any]]) -> [Card] {
        payload.compactMap { dict in
            guard let monthIndex = dict["month"] as? Int,
                  let typeString = dict["type"] as? String else {
                return nil
            }

            let selectedRole = (dict["selectedRole"] as? String).map(parseCardRole)
            return Card(
                id: dict["id"] as? String ?? UUID().uuidString,
                month: Month(rawValue: monthIndex) ?? .jan,
                type: parseCardType(typeString),
                imageIndex: dict["imageIndex"] as? Int ?? 0,
                selectedRole: selectedRole
            )
        }
    }

    static func serializedStatePayload(from gameManager: GameManager) -> [String: Any] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(gameManager.serializeState()),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["status": "error", "message": "Failed to serialize state"]
        }
        return payload
    }

    static func persistenceProbeData() -> [String: Any] {
        [
            "rule_dummy_card_count": RuleLoader.shared.config?.special_moves.bomb.dummy_card_count ?? -1,
            "rule_chongtong_initial_score": RuleLoader.shared.config?.special_moves.chongtong.initial_chongtong_score ?? -1,
            "rule_chongtong_midgame_score": RuleLoader.shared.config?.special_moves.chongtong.midgame_chongtong_score ?? -1,
            "animation_opponent_action_delay": AnimationManager.shared.config.opponent_action_delay,
            "first_launch_starter_applied": ConfigurationStore.shared.firstLaunchStarterApplied(),
            "configuration_path": ConfigurationStore.shared.configurationPath
        ]
    }

    static func updatePersistenceProbeConfig(with payload: [String: Any]) -> Result<[String: Any], SupportError> {
        var didChange = false

        if payload["rule_dummy_card_count"] != nil ||
            payload["rule_chongtong_initial_score"] != nil ||
            payload["rule_chongtong_midgame_score"] != nil {
            guard var rules = RuleLoader.shared.config else {
                return .failure(.message("Rule config is not loaded"))
            }

            if let dummyCardCount = payload["rule_dummy_card_count"] as? Int {
                rules.special_moves.bomb.dummy_card_count = max(0, dummyCardCount)
                didChange = true
            }
            if let initialScore = payload["rule_chongtong_initial_score"] as? Int {
                rules.special_moves.chongtong.initial_chongtong_score = max(0, initialScore)
                didChange = true
            }
            if let midgameScore = payload["rule_chongtong_midgame_score"] as? Int {
                rules.special_moves.chongtong.midgame_chongtong_score = max(0, midgameScore)
                didChange = true
            }

            if didChange {
                RuleLoader.shared.updateRules(rules)
            }
        }

        if let rawDelay = payload["animation_opponent_action_delay"] {
            let parsedDelay: Double?
            if let delay = rawDelay as? Double {
                parsedDelay = delay
            } else if let delay = rawDelay as? Int {
                parsedDelay = Double(delay)
            } else if let delay = rawDelay as? NSNumber {
                parsedDelay = delay.doubleValue
            } else {
                parsedDelay = nil
            }

            if let parsedDelay {
                var nextConfig = AnimationManager.shared.config
                nextConfig.opponent_action_delay = max(0.0, parsedDelay)
                AnimationManager.shared.config = nextConfig
                AnimationManager.shared.saveConfig()
                didChange = true
            }
        }

        if let isApplied = payload["first_launch_starter_applied"] as? Bool {
            _ = ConfigurationStore.shared.setFirstLaunchStarterApplied(isApplied)
            didChange = true
        }

        guard didChange else {
            return .failure(.message("No supported persistence probe keys provided"))
        }

        return .success(persistenceProbeData())
    }

    static func applyTestCondition(
        _ payload: [String: Any],
        to gameManager: GameManager,
        applyCustomRules: (([String: Any]) throws -> Void)? = nil,
        didUpdateSeed: ((Int) -> Void)? = nil,
        didUpdateMockEventLogs: (([String]) -> Void)? = nil
    ) throws {
        // Test-control mocks should land the engine in a deterministic idle state.
        gameManager.emergencyResetBusyState()

        if let customRules = payload["custom_rules"] as? [String: Any],
           let applyCustomRules {
            try applyCustomRules(customRules)
        }

        if let seed = payload["rng_seed"] as? Int {
            didUpdateSeed?(seed)
            gameManager.setupGame(seed: seed)
        }

        if let scenario = payload["mock_scenario"] as? String, scenario == "game_over" {
            gameManager.gameState = .ended
        }

        if let turnIndex = payload["currentTurnIndex"] as? Int {
            gameManager.currentTurnIndex = turnIndex
        }

        if let mockState = payload["mock_gameState"] as? String {
            switch mockState {
            case "ready":
                gameManager.gameState = .ready
            case "playing":
                gameManager.gameState = .playing
            case "askingGoStop":
                gameManager.gameState = .askingGoStop
            case "askingShake":
                gameManager.gameState = .askingShake
            case "ended":
                gameManager.gameState = .ended
            default:
                break
            }
        }

        if let mockEndReason = (payload["mock_game_end_reason"] as? String) ??
            (payload["mock_gameEndReason"] as? String) {
            gameManager.gameEndReason = GameEndReason(rawValue: mockEndReason)
        }

        if let mockEventLogs = payload["mock_event_logs"] as? [String] {
            gameManager.eventLogs = mockEventLogs
            didUpdateMockEventLogs?(mockEventLogs)
        }

        if let mockCaptured = payload["mock_captured_cards"] as? [[String: Any]],
           gameManager.players.indices.contains(0) {
            let player = gameManager.players[0]
            player.capturedCards = parseCards(from: mockCaptured)
            player.hasCapturedThisRound = !player.capturedCards.isEmpty
            player.score = ScoringSystem.calculateScore(for: player)
        }

        if let mockOpponentCaptured = payload["mock_opponent_captured_cards"] as? [[String: Any]],
           gameManager.players.indices.contains(1) {
            let opponent = gameManager.players[1]
            opponent.capturedCards = parseCards(from: mockOpponentCaptured)
            opponent.hasCapturedThisRound = !opponent.capturedCards.isEmpty
            opponent.score = ScoringSystem.calculateScore(for: opponent)
        }

        if let mockHand = payload["mock_hand"] as? [[String: Any]],
           gameManager.players.indices.contains(0) {
            gameManager.players[0].hand = parseCards(from: mockHand)
        }

        if let clearDeck = payload["clear_deck"] as? Bool, clearDeck {
            _ = gameManager.deck.drainAll()
        }

        if let mockDeck = payload["mock_deck"] as? [[String: Any]] {
            gameManager.mockDeck(cards: parseCards(from: mockDeck))
        }

        if let mockTable = payload["mock_table"] as? [[String: Any]] {
            gameManager.tableCards = parseCards(from: mockTable)
        }

        for index in 0..<gameManager.players.count {
            let key = "player\(index)_data"
            guard let playerData = payload[key] as? [String: Any] else { continue }
            applyPlayerData(playerData, to: gameManager.players[index])
        }

        if let mockCompletedTurnCount = payload["mock_completed_turn_count"] as? Int {
            gameManager.setCompletedTurnCountForTesting(mockCompletedTurnCount)
        }

        if let monthOwners = payload["mock_month_owners"] as? [String: Int] {
            gameManager.monthOwners = [:]
            applyMonthOwners(monthOwners.mapValues { $0 as Any }, to: gameManager)
        } else if let monthOwners = payload["mock_month_owners"] as? [String: Any] {
            gameManager.monthOwners = [:]
            applyMonthOwners(monthOwners, to: gameManager)
        }

        gameManager.emergencyResetBusyState()
    }

    private static func applyPlayerData(_ payload: [String: Any], to player: Player) {
        if let goCount = payload["goCount"] as? Int { player.goCount = goCount }
        if let lastGoScore = payload["lastGoScore"] as? Int { player.lastGoScore = lastGoScore }
        if let money = payload["money"] as? Int { player.money = money }
        if let score = payload["score"] as? Int { player.score = score }
        if let shakeCount = payload["shakeCount"] as? Int { player.shakeCount = shakeCount }
        if let bombCount = payload["bombCount"] as? Int { player.bombCount = bombCount }
        if let sweepCount = payload["sweepCount"] as? Int { player.sweepCount = sweepCount }
        if let ttadakCount = payload["ttadakCount"] as? Int { player.ttadakCount = ttadakCount }
        if let jjokCount = payload["jjokCount"] as? Int { player.jjokCount = jjokCount }
        if let seolsaCount = payload["seolsaCount"] as? Int { player.seolsaCount = seolsaCount }
        if let awardedFirstTurnTtadakBonus = payload["awardedFirstTurnTtadakBonus"] as? Bool {
            player.awardedFirstTurnTtadakBonus = awardedFirstTurnTtadakBonus
        }
        if let awardedFirstTurnSeolsaBonus = payload["awardedFirstTurnSeolsaBonus"] as? Bool {
            player.awardedFirstTurnSeolsaBonus = awardedFirstTurnSeolsaBonus
        }
        if let isPiMungbak = payload["isPiMungbak"] as? Bool { player.isPiMungbak = isPiMungbak }
        if let mungddaCount = payload["mungddaCount"] as? Int { player.mungddaCount = mungddaCount }
        if let bombMungddaCount = payload["bombMungddaCount"] as? Int { player.bombMungddaCount = bombMungddaCount }
        if let isComputer = payload["isComputer"] as? Bool { player.isComputer = isComputer }
        if let dummyCardCount = payload["dummyCardCount"] as? Int { player.dummyCardCount = dummyCardCount }

        if let hand = payload["hand"] as? [[String: Any]] {
            player.hand = parseCards(from: hand)
        }
        if let capturedCards = payload["capturedCards"] as? [[String: Any]] {
            player.capturedCards = parseCards(from: capturedCards)
            player.hasCapturedThisRound = !player.capturedCards.isEmpty
            player.score = ScoringSystem.calculateScore(for: player)
        }
        if let hasCapturedThisRound = payload["hasCapturedThisRound"] as? Bool {
            player.hasCapturedThisRound = hasCapturedThisRound
        }
    }

    private static func applyMonthOwners(_ payload: [String: Any], to gameManager: GameManager) {
        for (monthString, ownerIndexValue) in payload {
            guard let month = Int(monthString) else { continue }
            let ownerIndex: Int?
            if let intValue = ownerIndexValue as? Int {
                ownerIndex = intValue
            } else if let numberValue = ownerIndexValue as? NSNumber {
                ownerIndex = numberValue.intValue
            } else {
                ownerIndex = nil
            }
            guard let ownerIndex,
                  gameManager.players.indices.contains(ownerIndex) else {
                continue
            }
            gameManager.monthOwners[month] = gameManager.players[ownerIndex]
        }
    }
}
