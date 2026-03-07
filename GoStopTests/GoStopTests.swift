import XCTest
import Combine
@testable import GoStop

final class GoStopTests: XCTestCase {
    private func withImmediateAnimations(_ body: () -> Void) {
        let originalConfig = AnimationManager.shared.config
        var immediateConfig = originalConfig
        immediateConfig.card_move_duration = 0
        immediateConfig.capture_to_player_duration = 0
        immediateConfig.play_from_hand_duration = 0
        immediateConfig.deck_to_table_duration = 0
        immediateConfig.table_to_captured_duration = 0
        immediateConfig.captured_to_captured_duration = 0
        immediateConfig.hand_to_table_motion = "instant"
        immediateConfig.deck_to_table_motion = "instant"
        immediateConfig.table_to_captured_motion = "instant"
        immediateConfig.captured_to_captured_motion = "instant"
        immediateConfig.opponent_preplay_reveal_duration = 0
        immediateConfig.match_pause_duration = 0
        immediateConfig.opponent_action_delay = 0
        AnimationManager.shared.config = immediateConfig
        defer { AnimationManager.shared.config = originalConfig }
        body()
    }

    private func makePlayableGame() -> GameManager {
        let game = GameManager()
        if game.gameState != .ended {
            return game
        }

        for seed in 1...1000 {
            game.setupGame(seed: seed)
            if game.gameState != .ended {
                return game
            }
        }

        XCTFail("Could not find a non-ended initial state within deterministic seed range.")
        return game
    }

    private func makeCard(month: Month, type: CardType = .junk, imageIndex: Int = 0) -> Card {
        Card(month: month, type: type, imageIndex: imageIndex)
    }
    
    func testDeckCount() {
        let deck = Deck()
        XCTAssertEqual(deck.cards.count, 48, "Deck should have 48 cards")
    }
    
    func testDeckShuffle() {
        var deck1 = Deck()
        var deck2 = Deck()
        // Extremely low probability of matching exactly if shuffled
        // Ideally we check if order changes, but for now just check content equality logic isn't trivial
        // Just checking counts are same
        XCTAssertEqual(deck1.cards.count, deck2.cards.count)
    }
    
    func testUniqueCards() {
        let deck = Deck()
        let uniqueIDs = Set(deck.cards.map { $0.id })
        XCTAssertEqual(uniqueIDs.count, 48, "All cards should have unique IDs")
    }
    
    func testGameManagerSetup() {
        let game = GameManager()
        XCTAssertEqual(game.gameState, .ready)
        XCTAssertEqual(game.players.count, 2)
        XCTAssertEqual(game.players[0].hand.count, 10)
        XCTAssertEqual(game.tableCards.count, 8)
        XCTAssertEqual(game.deck.cards.count, 48 - 20 - 8) // 48 - 10*2 - 8 = 20
    }
    
    func testScoringBasic() {
        let player = Player(name: "Test")
        
        // Test 3 Gwang (3 points)
        player.capturedCards = [
            Card(month: .jan, type: .bright, imageIndex: 0),
            Card(month: .mar, type: .bright, imageIndex: 0),
            Card(month: .aug, type: .bright, imageIndex: 0)
        ]
        
        let score = ScoringSystem.calculateScore(for: player)
        XCTAssertEqual(score, 3)
    }
    
    func testGodori() {
        let player = Player(name: "Test")
        
        // Godori (5 points)
        player.capturedCards = [
            Card(month: .feb, type: .animal, imageIndex: 0), // Bird
            Card(month: .apr, type: .animal, imageIndex: 0), // Bird
            Card(month: .aug, type: .animal, imageIndex: 0)  // Geese
        ]
        
        // We need to ensure these are actually recognized as birds in isBird
        let score = ScoringSystem.calculateScore(for: player)
        XCTAssertEqual(score, 5)
    }
    
    func testMatchingLogic() {
        let game = GameManager()
        game.startGame()
        let player = game.players[0]
        
        // Setup state for deterministic test
        let myCard = Card(month: .jan, type: .bright, imageIndex: 0)
        let tableCard = Card(month: .jan, type: .junk, imageIndex: 2)
        
        player.hand = [myCard]
        game.tableCards = [tableCard]
        
        // Capture initial count
        let initialCaptured = player.capturedCards.count
        
        // Play
        game.playTurn(card: myCard)
        
        // Verify capture happened
        XCTAssertGreaterThan(player.capturedCards.count, initialCaptured)
        
        // Verify specifically that the initial table card is gone
        // Card equality checks UUID, so even if another Jan Junk appears, it won't be this one.
        XCTAssertFalse(game.tableCards.contains(tableCard), "The specific table card should be captured")
    }
    
    func testAssetLoading() {
        // GameManager is a class in the main module, so Bundle(for:) should point to the main bundle (or the framework bundle if modularized)
        let bundle = Bundle(for: GameManager.self)
        let sampleCards = ["Card_jan_0", "Card_dec_3", "Card_aug_0"]
        for cardName in sampleCards {
            let image = UIImage(named: cardName, in: bundle, compatibleWith: nil)
            XCTAssertNotNil(image, "Failed to load image asset: \(cardName) from bundle: \(bundle.bundlePath)")
        }
    }

    func testGameManagerForwardsNestedPlayerCapturedChanges() {
        let game = GameManager()
        let exp = expectation(description: "GameManager should publish when Player.capturedCards changes")
        var cancellable: AnyCancellable?

        cancellable = game.objectWillChange.sink {
            exp.fulfill()
        }

        game.players[0].capture(cards: [Card(month: .jan, type: .bright, imageIndex: 0)])

        wait(for: [exp], timeout: 0.5)
        withExtendedLifetime(cancellable) {}
    }

    func testStartGameAcceptsInitialTurnOverride() {
        let game = makePlayableGame()
        game.startGame(initialTurnIndex: 1)

        XCTAssertEqual(game.gameState, .playing)
        XCTAssertEqual(game.currentTurnIndex, 1)
    }

    func testNightDayStarterDayModeUsesHigherMonth() {
        let game = GameManager()
        _ = game.deck.drainAll()
        // pushCardsOnTop appends; reverse-read makes P1 read from the last pushed card first.
        game.mockDeck(cards: [makeCard(month: .jan), makeCard(month: .dec)]) // P1=12, P2=1

        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let starter = game.resolveNightDayStarterIndex(dayStartHour: 6, dayEndHour: 18, referenceDate: noon)

        XCTAssertEqual(starter, 0, "Day mode should choose the higher month card as starter.")
    }

    func testNightDayStarterNightModeUsesLowerMonth() {
        let game = GameManager()
        _ = game.deck.drainAll()
        game.mockDeck(cards: [makeCard(month: .jan), makeCard(month: .dec)]) // P1=12, P2=1

        let lateNight = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1))!
        let starter = game.resolveNightDayStarterIndex(dayStartHour: 6, dayEndHour: 18, referenceDate: lateNight)

        XCTAssertEqual(starter, 1, "Night mode should choose the lower month card as starter.")
    }

    func testLastHandSeolsaDoesNotCountOrCreateSeolsaEatState() {
        withImmediateAnimations {
            let game = GameManager()
            let player = game.players[0]
            let opponent = game.players[1]

            _ = game.deck.drainAll()
            game.gameState = .playing
            game.currentTurnIndex = 0
            player.isComputer = false
            opponent.isComputer = false
            player.hand = [makeCard(month: .jul, type: .ribbon)]
            opponent.hand = [makeCard(month: .jul, type: .bright)]
            player.capturedCards = [makeCard(month: .nov, type: .junk)]
            opponent.capturedCards = []
            game.tableCards = [makeCard(month: .jul, type: .junk)]
            game.mockDeck(cards: [
                makeCard(month: .oct, type: .junk),
                makeCard(month: .jul, type: .animal)
            ])

            game.playTurn(card: player.hand[0])

            XCTAssertEqual(player.seolsaCount, 0, "Last-hand Seolsa should not increment seolsaCount.")
            XCTAssertEqual(player.hand.count, 0, "Acting player should have no hand cards left after the play.")
            XCTAssertEqual(game.currentTurnIndex, 1, "Turn should pass to the opponent after invalid last-hand Seolsa.")
            XCTAssertEqual(game.tableCards.filter { $0.month == .jul }.count, 3, "Ignored last-hand Seolsa should still leave the triple on the table.")
            XCTAssertFalse(game.eventLogs.contains(where: { $0.contains("SEOLSA!") }), "Last-hand Seolsa should not emit the Seolsa marker log.")
            XCTAssertFalse(game.eventLogs.contains(where: { $0.contains("triggered 뻑(Seolsa)") }), "Last-hand Seolsa should not emit a Seolsa event.")

            game.playTurn(card: opponent.hand[0])

            XCTAssertEqual(opponent.seolsaEatCount, 0, "Capturing a triple created by ignored last-hand Seolsa should not award Seolsa Eat.")
            XCTAssertEqual(opponent.capturedCards.filter { $0.month == .jul }.count, 4, "Opponent should capture the four month cards without bonus side effects.")
            XCTAssertEqual(player.capturedCards.count, 1, "Ignored last-hand Seolsa should not let the opponent steal Pi via Seolsa Eat.")
            XCTAssertFalse(game.eventLogs.contains(where: { $0.contains("triggered 뻑 먹기(Seolsa Eat)") || $0.contains("triggered 자뻑(Self Seolsa Eat)") }), "Ignored last-hand Seolsa should not produce any Seolsa Eat event later.")
        }
    }

    func testOpeningTurnTtadakAwardsBonusScoreItem() {
        withImmediateAnimations {
            let game = GameManager()
            let player = game.players[0]
            let opponent = game.players[1]

            _ = game.deck.drainAll()
            game.gameState = .playing
            game.currentTurnIndex = 0
            player.isComputer = false
            opponent.isComputer = false
            player.hand = [makeCard(month: .jan, type: .junk)]
            opponent.hand = [makeCard(month: .feb, type: .junk)]
            player.capturedCards = []
            opponent.capturedCards = []
            game.tableCards = [makeCard(month: .jan, type: .junk), makeCard(month: .jan, type: .junk)]
            game.mockDeck(cards: [
                makeCard(month: .feb, type: .junk),
                makeCard(month: .jan, type: .bright)
            ])

            game.playTurn(card: player.hand[0])

            let bonusItem = ScoringSystem.calculateScoreDetail(for: player).first { $0.name.contains("첫 따닥") }
            XCTAssertEqual(player.ttadakCount, 1, "Opening-turn Ttadak should increment ttadakCount.")
            XCTAssertEqual(player.score, 10, "Opening-turn Ttadak should add the configured 10-point bonus.")
            XCTAssertTrue(player.awardedFirstTurnTtadakBonus, "Opening-turn Ttadak bonus flag should be stored on the player.")
            XCTAssertEqual(bonusItem?.points, 10, "Opening-turn Ttadak bonus should appear as a 10-point score item.")
            XCTAssertEqual(game.currentTurnIndex, 1, "Blocked opening score claim should pass the turn to the opponent.")
            XCTAssertEqual(game.gameState, .playing, "Blocked opening score claim should not end the round.")
        }
    }

    func testOpeningTurnSeolsaAwardsBonusScoreItem() {
        withImmediateAnimations {
            let game = GameManager()
            let player = game.players[0]
            let opponent = game.players[1]

            _ = game.deck.drainAll()
            game.gameState = .playing
            game.currentTurnIndex = 0
            player.isComputer = false
            opponent.isComputer = false
            player.hand = [makeCard(month: .jul, type: .ribbon), makeCard(month: .aug, type: .junk)]
            opponent.hand = [makeCard(month: .feb, type: .junk)]
            player.capturedCards = []
            opponent.capturedCards = []
            game.tableCards = [makeCard(month: .jul, type: .junk)]
            game.mockDeck(cards: [
                makeCard(month: .feb, type: .junk),
                makeCard(month: .jul, type: .animal)
            ])

            game.playTurn(card: player.hand[0])

            let bonusItem = ScoringSystem.calculateScoreDetail(for: player).first { $0.name.contains("첫 뻑") }
            XCTAssertEqual(player.seolsaCount, 1, "Opening-turn Seolsa should increment seolsaCount.")
            XCTAssertEqual(player.score, 10, "Opening-turn Seolsa should add the configured 10-point bonus.")
            XCTAssertTrue(player.awardedFirstTurnSeolsaBonus, "Opening-turn Seolsa bonus flag should be stored on the player.")
            XCTAssertEqual(bonusItem?.points, 10, "Opening-turn Seolsa bonus should appear as a 10-point score item.")
            XCTAssertEqual(game.tableCards.filter { $0.month == .jul }.count, 3, "Opening-turn Seolsa should still leave the triple on the table.")
            XCTAssertEqual(game.currentTurnIndex, 1, "Blocked opening score claim should pass the turn to the opponent.")
            XCTAssertEqual(game.gameState, .playing, "Blocked opening score claim should not end the round.")
        }
    }

    func testCapturedCardGroupingSortedCardsUsesPreviewOrderAndSpecialRoles() {
        let febAnimal = makeCard(month: .feb, type: .animal, imageIndex: 0)
        let augAnimal = makeCard(month: .aug, type: .animal, imageIndex: 1)
        var sepDoublePi = makeCard(month: .sep, type: .animal, imageIndex: 0)
        sepDoublePi.selectedRole = .doublePi
        let novJunk = makeCard(month: .nov, type: .junk, imageIndex: 2)
        let janBright = makeCard(month: .jan, type: .bright, imageIndex: 0)

        let animals = CapturedCardGrouping.sortedCards(
            for: "animal",
            from: [augAnimal, sepDoublePi, febAnimal, janBright, novJunk]
        )
        XCTAssertEqual(animals.map(\.month), [.feb, .aug], "Animal preview should exclude September double-pi and sort by month.")

        let piCards = CapturedCardGrouping.sortedCards(
            for: "pi",
            from: [augAnimal, novJunk, sepDoublePi, febAnimal]
        )
        XCTAssertEqual(piCards.map(\.month), [.sep, .nov], "Pi preview should include September double-pi and November junk in month order.")
    }

    func testSerializeStateIncludesCapturedPreviewProbeFields() {
        let game = GameManager()
        game.updateCapturedPreviewProbe(ownerPlayerId: "player-1", groupType: "pi", cardCount: 7)

        let state = game.serializeState()

        XCTAssertEqual(state["uiActiveCapturedPreviewOwnerPlayerId"]?.value as? String, "player-1")
        XCTAssertEqual(state["uiActiveCapturedPreviewGroupType"]?.value as? String, "pi")
        XCTAssertEqual(state["uiActiveCapturedPreviewCardCount"]?.value as? Int, 7)
    }

    func testSelfSeolsaEatKeepsTwoCardTransferHistory() {
        withImmediateAnimations {
            let game = GameManager()
            let player = game.players[0]
            let opponent = game.players[1]

            _ = game.deck.drainAll()
            game.gameState = .playing
            game.currentTurnIndex = 0
            game.eventLogs = []
            game.uxEventLogs = []
            player.isComputer = false
            opponent.isComputer = false

            let playerJunk = makeCard(month: .jan, type: .junk)
            let playerBright = makeCard(month: .jan, type: .bright)
            let opponentBright = makeCard(month: .nov, type: .bright)
            let opponentAnimal = makeCard(month: .nov, type: .animal)

            player.hand = [playerJunk, playerBright]
            opponent.hand = [opponentBright, opponentAnimal]
            opponent.capturedCards = [
                makeCard(month: .feb, type: .junk),
                makeCard(month: .mar, type: .junk),
                makeCard(month: .apr, type: .junk)
            ]
            game.tableCards = [
                makeCard(month: .jan, type: .junk),
                makeCard(month: .nov, type: .junk)
            ]
            game.mockDeck(cards: [
                makeCard(month: .jun, type: .junk),
                makeCard(month: .may, type: .junk),
                makeCard(month: .jan, type: .ribbon)
            ])

            game.playTurn(card: playerJunk)
            game.playTurn(card: opponentBright)
            game.playTurn(card: playerBright)

            XCTAssertEqual(player.seolsaEatCount, 1, "Self Seolsa Eat should increment seolsaEatCount exactly once.")

            let transferLog = game.eventLogs.last(where: { $0.contains("피 이동 [자뻑(Self Seolsa Eat)]") })
            XCTAssertNotNil(transferLog, "Expected a pi-transfer event log for Self Seolsa Eat.")
            XCTAssertTrue(transferLog?.contains("(2장)") == true, "Self Seolsa Eat should record a two-card transfer in event history.")

            let transferMoveStart = game.uxEventLogs.last(where: {
                $0.type == "moveStart" &&
                $0.data["source"] == "captured" &&
                $0.data["target"] == "captured" &&
                $0.data["reason"] == "자뻑(Self Seolsa Eat)"
            })
            XCTAssertNotNil(transferMoveStart, "Expected a captured->captured moveStart UX event for Self Seolsa Eat.")

            let movedCardIds = transferMoveStart?
                .data["cardIds"]?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            XCTAssertEqual(movedCardIds.count, 2, "Self Seolsa Eat UX history should keep both transferred card IDs.")
        }
    }
}
