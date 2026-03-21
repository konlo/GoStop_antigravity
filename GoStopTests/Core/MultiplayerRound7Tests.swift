import XCTest
@testable import GoStop

final class MultiplayerRound7Tests: XCTestCase {

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

    func testReconnectionState_ShouldUpdateFlags() {
        // Arrange
        let snapshot = MockMultiplayerPayloads.generateReconnectingSnapshot(
            localPlayerId: gameManager.localPlayerId ?? "p1",
            opponentId: "p2",
            secondsRemaining: 45
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        XCTAssertTrue(gameManager.isMultiplayerResumable, "isMultiplayerResumable should be true")
        XCTAssertNotNil(gameManager.multiplayerGraceDeadline, "multiplayerGraceDeadline should not be nil")
        
        if let deadline = gameManager.multiplayerGraceDeadline {
            let diff = deadline.timeIntervalSinceNow
            XCTAssertTrue(diff > 40 && diff <= 45, "Deadline should be around 45 seconds from now, got \(diff)")
        }
    }
    
    func testReconnectionState_ShouldResetWhenNormalSnapshotReceived() {
        // Arrange
        // 1. Set to reconnecting state
        let reconnectSnapshot = MockMultiplayerPayloads.generateReconnectingSnapshot(
            localPlayerId: "p1",
            opponentId: "p2",
            secondsRemaining: 30
        )
        viewModel.mockReceiveSnapshot(reconnectSnapshot)
        XCTAssertTrue(gameManager.isMultiplayerResumable)
        
        // 2. Clear with normal snapshot
        let normalSnapshot = MockMultiplayerPayloads.generateInitialDealSnapshot(
            localPlayerId: "p1",
            opponentId: "p2"
        )
        
        // Act
        viewModel.mockReceiveSnapshot(normalSnapshot)
        
        // Assert
        XCTAssertFalse(gameManager.isMultiplayerResumable, "isMultiplayerResumable should be reset to false")
        XCTAssertNil(gameManager.multiplayerGraceDeadline, "multiplayerGraceDeadline should be reset to nil")
    }
}
