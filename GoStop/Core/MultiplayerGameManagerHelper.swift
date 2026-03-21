import Foundation
import Combine

protocol MultiplayerGameManagerHelper {
    var isMappedState: Bool { get }
    
    func applyMappedState(_ mappedState: MultiplayerMappedState)
    func reportMismatch(expectedVersion: Int, actualVersion: Int, message: String)
}

extension GameManager: MultiplayerGameManagerHelper {
    
    var isMappedState: Bool {
        return externalControlMode
    }
    
    func applyMappedState(_ mappedState: MultiplayerMappedState) {
        // Halt any internal computer actions
        self.internalComputerAutomationEnabled = false
        self.externalControlMode = true
        self.resetPresentationStateForExternalSnapshot()
        
        // Suppress animations for the initial sync/resync
        AnimationManager.shared.suppressAnimations = true
        defer { AnimationManager.shared.suppressAnimations = false }

        let oldPhase = self.gameState

        // Sync State
        self.gameState = mappedState.phase
        if mappedState.phase == .ended {
            self.emergencyResetBusyState()
        }
        self.currentTurnIndex = mappedState.currentTurnIndex

        // Sync table
        self.tableCards = mappedState.tableCards

        // Sync players
        self.players = mappedState.players

        // Sync choices
        self.pendingCaptureOptions = mappedState.pendingCaptureOptions
        self.pendingCapturePlayedCard = mappedState.pendingCapturePlayedCard
        self.pendingCaptureDrawnCard = mappedState.pendingCaptureDrawnCard

        self.pendingShakeMonths = mappedState.pendingShakeMonths
        self.pendingShakeCard = mappedState.pendingShakeCard
        self.pendingShakeMonth = mappedState.pendingShakeMonth

        self.pendingChrysanthemumCard = mappedState.pendingChrysanthemumCard

        // Sync endgame
        if let reason = mappedState.gameEndReason {
            self.gameEndReason = reason

            if let winnerId = mappedState.gameWinnerPlayerId {
                self.gameWinner = self.players.first(where: { $0.id.uuidString == winnerId })
            }
        }

        // Trigger Special Action Effects (Ppeok, Jjok, etc.)
        if let effect = mappedState.lastActionEffect {
            self.triggerMultiplayerSpecialEffect(effect)
        }

        self.isMultiplayerResumable = mappedState.isResumable
        self.multiplayerGraceDeadline = mappedState.graceDeadlineAt

        if let chat = mappedState.lastChat {
            self.playerChats[chat.playerId] = chat

            // Auto-clear after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                // Only clear if it's still the same chat (by timestamp or just being present)
                if self?.playerChats[chat.playerId]?.sentAt == chat.sentAt {
                    self?.playerChats.removeValue(forKey: chat.playerId)
                }
            }
        }

        // Round 9: Scoreboard & Win Counts
        self.currentScoreboard = mappedState.lastScoreboard

        if mappedState.phase == .ended && oldPhase != .ended {
            if let winnerId = mappedState.gameWinnerPlayerId {
                let currentWins = self.matchHistory[winnerId] ?? 0
                self.matchHistory[winnerId] = currentWins + 1
            }
        }

        // Round 10: Match End Detection
        if mappedState.phase == .ended {
            if mappedState.lastScoreboard?.winnerPlayerId != nil {
                self.isMatchEndedFlag = true
            }
        }

        self.takeSnapshot()
    }
    
    private func triggerMultiplayerSpecialEffect(_ effect: String) {
        // Map effect string to localized log markers to trigger SpecialEventPopupCoordinator
        let logMarker: String?
        switch effect.lowercased() {
        case "ppeok", "seolsa":
            logMarker = gameText("log.marker.seolsa")
            AudioManager.shared.playHwatuBlanketPuckEffect()
        case "jjok":
            logMarker = gameText("log.marker.jjok")
            AudioManager.shared.playHwatuCardHitEffect()
        case "ttadak":
            logMarker = gameText("log.marker.ttadak")
            AudioManager.shared.playHwatuCardHitEffect()
        case "sweep":
            logMarker = gameText("log.marker.sweep")
            AudioManager.shared.playHwatuCardHitEffect()
        default:
            logMarker = nil
        }
        
        if let marker = logMarker {
            // SpecialEventPopupMapper expects "PlayerName LogMarker"
            let actorName = gameText("players.default.anonymous") // Simplified for now
            gLog("\(actorName) \(marker)")
        }
    }
    
    func reportMismatch(expectedVersion: Int, actualVersion: Int, message: String) {
        gLog("[StateMapper Mismatch] Expected: \(expectedVersion), Actual: \(actualVersion). \(message)")
    }
}
