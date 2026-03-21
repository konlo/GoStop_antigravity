import XCTest
@testable import GoStop

final class MultiplayerRound9Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
        
        let localId = "p1"
        let player = Player(name: "Me", money: 10000)
        player.id = UUID(uuidString: localId) ?? UUID()
        gameManager.players = [player]
        gameManager.localPlayerId = localId
    }

    func testScoreboardSync_ShouldUpdateCurrentScoreboard() {
        // Arrange
        let snapshot = MockMultiplayerPayloads.generateScoreboardSnapshot(
            localPlayerId: "p1",
            opponentId: "p2",
            localScore: 10,
            opponentScore: 0,
            roundIndex: 1
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        XCTAssertNotNil(gameManager.currentScoreboard)
        XCTAssertEqual(gameManager.currentScoreboard?.roundIndex, 1)
        XCTAssertEqual(gameManager.currentScoreboard?.playerScores.first(where: { $0.playerId == "p1" })?.score, 10)
    }

    func testMatchHistory_ShouldIncrementOnRoundEnd() {
        // Arrange
        let localPlayerId = "p1"
        let opponentId = "p2"
        
        // 1. Initial State
        XCTAssertEqual(gameManager.matchHistory[localPlayerId] ?? 0, 0)
        
        // 2. Round 1 End (Local Wins)
        let round1Snapshot = MockMultiplayerPayloads.generateScoreboardSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            localScore: 15,
            opponentScore: 0,
            roundIndex: 1
        )
        
        // Act
        viewModel.mockReceiveSnapshot(round1Snapshot)
        
        // Assert
        XCTAssertEqual(gameManager.matchHistory[localPlayerId], 1, "Local player should have 1 win")
        
        // 3. Fake transition back to playing (to allow next end to trigger)
        let playingSnapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId
        )
        viewModel.mockReceiveSnapshot(playingSnapshot)
        
        // 4. Round 2 End (Local Wins again)
        let round2Snapshot = MockMultiplayerPayloads.generateScoreboardSnapshot(
            localPlayerId: localPlayerId,
            opponentId: opponentId,
            localScore: 20,
            opponentScore: 0,
            roundIndex: 2
        )
        
        viewModel.mockReceiveSnapshot(round2Snapshot)
        
        XCTAssertEqual(gameManager.matchHistory[localPlayerId], 2, "Local player should have 2 wins")
    }
}
