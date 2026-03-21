import XCTest
@testable import GoStop

final class MultiplayerRound6Tests: XCTestCase {

    var gameManager: GameManager!
    var viewModel: MultiplayerPlayCoordinatorViewModel!

    override func setUp() {
        super.setUp()
        gameManager = GameManager()
        viewModel = MultiplayerPlayCoordinatorViewModel(gameManager: gameManager)
        
        // Ensure local player info is set
        let localId = "p1"
        let player = Player(name: "Me", money: 10000)
        player.id = UUID(uuidString: localId) ?? UUID()
        gameManager.players = [player]
        gameManager.localPlayerId = localId
    }

    func testSpecialEvent_Ppeok_ShouldTriggerLog() {
        // Arrange
        let snapshot = MockMultiplayerPayloads.generateSpecialEventSnapshot(
            localPlayerId: gameManager.localPlayerId ?? "p1",
            opponentId: "p2",
            effect: "ppeok"
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        // The log should contain the seolsa marker
        let marker = gameText("log.marker.seolsa")
        let logExists = gameManager.uxEventLogs.contains { event in
             // Depending on how gLog is implemented, it might be in eventLogs or uxEventLogs
             // In this project gLog calls GameManager.shared?.addEvent which adds to eventLogs
             return false
        }
        
        // Let's check eventLogs directly if accessible via reflection or public API
        let eventLogs = gameManager.eventLogs
        XCTAssertTrue(eventLogs.contains { $0.contains(marker) }, "Ppeok log marker should be present in event logs")
    }
    
    func testSpecialEvent_Jjok_ShouldTriggerLog() {
        // Arrange
        let snapshot = MockMultiplayerPayloads.generateSpecialEventSnapshot(
            localPlayerId: gameManager.localPlayerId ?? "p1",
            opponentId: "p2",
            effect: "jjok"
        )
        
        // Act
        viewModel.mockReceiveSnapshot(snapshot)
        
        // Assert
        let marker = gameText("log.marker.jjok")
        let eventLogs = gameManager.eventLogs
        XCTAssertTrue(eventLogs.contains { $0.contains(marker) }, "Jjok log marker should be present in event logs")
    }
}
