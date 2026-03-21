import XCTest
@testable import GoStop

final class MultiplayerStateMapperTests: XCTestCase {

    var mapper: MultiplayerStateMapper!

    override func setUp() {
        super.setUp()
        mapper = DefaultMultiplayerStateMapper()
    }

    func testMapSnapshotSucceedsWithValidData() throws {
        // Arrange
        let mockPlayer = MultiplayerPlayerProjection(
            playerId: "player_a",
            name: "Test User",
            score: 10,
            money: 1000,
            goCount: 1,
            shakeCount: 0,
            handCount: 3,
            hand: nil, // Opponent view
            captured: MultiplayerCapturedCardsSummary(bright: [], animal: [], ribbon: [], junk: [])
        )
        
        let mockTable = MultiplayerTableSummary(
            cards: [
                MultiplayerCardSummary(cardId: "c1", month: 1, kind: "bright", imageIndex: 0, selectedRole: nil),
                MultiplayerCardSummary(cardId: "c2", month: 2, kind: "junk", imageIndex: 1, selectedRole: nil)
            ],
            monthBuckets: [:]
        )
        
        let snapshot = MultiplayerSnapshot(
            stateVersion: 1,
            phase: "inTurn",
            currentPlayerId: "player_a",
            players: [mockPlayer],
            table: mockTable,
            pendingChoice: nil,
            scoreboard: nil
        )
        
        // Act
        let mappedState = try mapper.mapSnapshot(snapshot, currentPlayers: nil)
        
        // Assert
        XCTAssertEqual(mappedState.phase, .playing)
        XCTAssertEqual(mappedState.players.count, 1)
        XCTAssertEqual(mappedState.players[0].name, "Test User")
        XCTAssertEqual(mappedState.players[0].score, 10)
        XCTAssertEqual(mappedState.tableCards.count, 2)
        XCTAssertEqual(mappedState.tableCards[0].month, .january)
        XCTAssertEqual(mappedState.tableCards[0].type, .bright)
    }
}

// Minimal stub for MultiplayerPlayerProjection / Snapshot since we haven't seen the exact struct defined yet.
// In reality, this relies on Agent 2's Swift codegen of the network protocol.
struct MultiplayerSnapshot {
    let stateVersion: Int
    let phase: String
    let currentPlayerId: String
    let players: [MultiplayerPlayerProjection]
    let table: MultiplayerTableSummary
    let pendingChoice: MultiplayerChoiceStub?
    let scoreboard: MultiplayerScoreboardStub?
}

struct MultiplayerPlayerProjection {
    let playerId: String
    let name: String
    let score: Int
    let money: Int
    let goCount: Int
    let shakeCount: Int
    let handCount: Int
    let hand: [MultiplayerCardSummary]?
    let captured: MultiplayerCapturedCardsSummary
}

struct MultiplayerTableSummary {
    let cards: [MultiplayerCardSummary]
    let monthBuckets: [Int: [MultiplayerCardSummary]]
}

struct MultiplayerCardSummary {
    let cardId: String
    let month: Int?
    let kind: String?
    let imageIndex: Int?
    let selectedRole: String?
}

struct MultiplayerCapturedCardsSummary {
    let bright: [MultiplayerCardSummary]
    let animal: [MultiplayerCardSummary]
    let ribbon: [MultiplayerCardSummary]
    let junk: [MultiplayerCardSummary]
}

struct MultiplayerChoiceStub {
    enum Kind {
        case capture, shake, chrysanthemumRole, goStop, unknown
    }
    let choiceKind: Kind
}

struct MultiplayerScoreboardStub {
    let winnerPlayerId: String
}
