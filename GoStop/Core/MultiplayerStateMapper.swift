import Foundation
import Combine

enum MultiplayerStateMapperError: Error, LocalizedError {
    case playerNotFound(String)
    case unsupportedPhase(String)
    case invalidCardData(String)

    var errorDescription: String? {
        switch self {
        case .playerNotFound(let id):
            return "Player with id \(id) not found in local state."
        case .unsupportedPhase(let phase):
            return "Phase \(phase) is not supported by local engine."
        case .invalidCardData(let detail):
            return "Invalid card data: \(detail)."
        }
    }
}

/// Represents the mapped properties from the authoritative MultiplayerSnapshot
/// that GameManager needs in order to render the game state.
struct MultiplayerMappedState {
    let stateVersion: Int
    let phase: GameState
    let currentTurnIndex: Int
    
    // Extracted player models with updated scores and hands
    let players: [Player]
    let tableCards: [Card]
    
    // Pending choice states
    let pendingCaptureOptions: [Card]
    let pendingCapturePlayedCard: Card?
    let pendingCaptureDrawnCard: Card?
    
    let pendingShakeMonths: [Int]
    let pendingShakeCard: Card?
    let pendingShakeMonth: Int?
    
    let pendingChrysanthemumCard: Card?
    
    // Endgame state
    let gameEndReason: GameEndReason?
    let gameWinnerPlayerId: String?
    
    // Special Effects
    let lastActionEffect: String?
    
    // Reconnection
    let isResumable: Bool
    let graceDeadlineAt: Date?
    
    // Quick Chat
    let lastChat: MultiplayerChatPresence?
    
    // Scoreboard
    let lastScoreboard: MultiplayerScoreboard?
}

/// A protocol to map authoritative server snapshots to GameManager view-models.
protocol MultiplayerStateMapper {
    func mapSnapshot(_ snapshot: MultiplayerSnapshot, currentPlayers: [Player]?) throws -> MultiplayerMappedState
}

final class DefaultMultiplayerStateMapper: MultiplayerStateMapper {
    
    func mapSnapshot(_ snapshot: MultiplayerSnapshot, currentPlayers: [Player]?) throws -> MultiplayerMappedState {
        let viewerAuthorityPlayerId =
            snapshot.state.players.first(where: \.isViewer)?.playerId ??
            snapshot.state.viewerPlayerId
        let viewerSeatIndex =
            snapshot.state.players.first(where: { $0.playerId == viewerAuthorityPlayerId })?.seatIndex
        let players = try mapPlayers(
            from: snapshot.state.players,
            existingPlayers: currentPlayers,
            viewerSeatIndex: viewerSeatIndex
        )
        let mappedPhase = try mapPhase(snapshot.state.phase.rawValue, pendingChoice: snapshot.state.pendingChoice)
        let currentTurnIndex = currentTurnIndex(from: snapshot, players: players)
        
        // Map Table
        let tableCards = mapCards(from: snapshot.state.table.cards)
        
        // Match choices
        var captureOptions: [Card] = []
        var capturePlayed: Card? = nil
        var captureDrawn: Card? = nil
        var shakeMonths: [Int] = []
        var shakeCard: Card? = nil
        var shakeMonth: Int? = nil
        var chrysCard: Card? = nil
        
        if let choice = snapshot.state.pendingChoice {
            switch choice.choiceKind {
            case .capture:
                captureOptions = choice.options.compactMap { option in
                    option.cards.first(where: { $0.zone == "table" }).flatMap(mapChoiceCard)
                }
                capturePlayed = choice.options
                    .flatMap(\.cards)
                    .first(where: { $0.zone == "played" })
                    .flatMap(mapChoiceCard)
                captureDrawn = choice.options
                    .flatMap(\.cards)
                    .first(where: { $0.zone == "drawn" })
                    .flatMap(mapChoiceCard)
            case .shake:
                let relatedCards = choice.options
                    .flatMap(\.cards)
                    .filter { $0.zone == "hand" }
                    .compactMap(mapChoiceCard)
                shakeCard = relatedCards.first
                let metadataMonth = choice.options
                    .compactMap { $0.metadata?["month"]?.value as? Int }
                    .first
                let derivedMonth = metadataMonth ?? relatedCards.first?.month.rawValue
                shakeMonth = derivedMonth
                shakeMonths = derivedMonth.map { [$0] } ?? []
            case .chrysanthemumRole:
                chrysCard = choice.options
                    .flatMap(\.cards)
                    .first
                    .flatMap(mapChoiceCard)
            case .goStop:
                break
            }
        }
        
        // Endgame mapping
        let endReason: GameEndReason? = nil
        var winnerId: String?
        
        if snapshot.state.phase == .matchEnded {
            if let winnerProjection = projection(forAuthorityId: snapshot.state.scoreboard.winnerPlayerId, in: snapshot.state.players) {
                winnerId = players.first(where: { $0.seatIndex == winnerProjection.seatIndex })?.id.uuidString
            }
        }
        
        return MultiplayerMappedState(
            stateVersion: snapshot.state.stateVersion,
            phase: mappedPhase,
            currentTurnIndex: currentTurnIndex,
            players: players,
            tableCards: tableCards,
            pendingCaptureOptions: captureOptions,
            pendingCapturePlayedCard: capturePlayed,
            pendingCaptureDrawnCard: captureDrawn,
            pendingShakeMonths: shakeMonths,
            pendingShakeCard: shakeCard,
            pendingShakeMonth: shakeMonth,
            pendingChrysanthemumCard: chrysCard,
            gameEndReason: endReason,
            gameWinnerPlayerId: winnerId,
            lastActionEffect: snapshot.state.lastActionEffect,
            isResumable: snapshot.state.resume.isResumable,
            graceDeadlineAt: snapshot.state.resume.graceDeadlineAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            lastChat: snapshot.state.lastChat,
            lastScoreboard: snapshot.state.scoreboard
        )
    }
    
    private func mapPhase(_ phase: String, pendingChoice: MultiplayerChoice?) throws -> GameState {
        switch phase {
        case "waiting", "dealing":
            return .ready
        case "inTurn":
            return .playing
        case "choicePending":
            switch pendingChoice?.choiceKind {
            case .capture:
                return .choosingCapture
            case .shake:
                return .askingShake
            case .goStop:
                return .askingGoStop
            case .chrysanthemumRole:
                return .choosingChrysanthemumRole
            case .none:
                return .playing
            }
        case "roundEnded", "matchEnded":
            return .ended
        case "paused":
            return .ready
        default:
            throw MultiplayerStateMapperError.unsupportedPhase(phase)
        }
    }
    
    private func mapPlayers(
        from projections: [MultiplayerPlayerProjection],
        existingPlayers: [Player]?,
        viewerSeatIndex: Int?
    ) throws -> [Player] {
        var players: [Player] = []
        var usedPlayerIds = Set<UUID>()
        
        for proj in projections {
            let existingMatch: Player?
            if let existing = existingPlayers?.first(where: { $0.id.uuidString == proj.playerId && !usedPlayerIds.contains($0.id) }) {
                existingMatch = existing
            } else if let existingBySeat = existingPlayers?.first(where: { $0.seatIndex == proj.seatIndex && !usedPlayerIds.contains($0.id) }) {
                existingMatch = existingBySeat
            } else if let existingByOrder = existingPlayers?
                .enumerated()
                .first(where: { $0.offset == proj.seatIndex && !usedPlayerIds.contains($0.element.id) })?
                .element {
                existingMatch = existingByOrder
            } else {
                existingMatch = nil
            }

            let player = Player(id: existingMatch?.id ?? UUID(), name: proj.name, money: proj.money)
            usedPlayerIds.insert(player.id)
            
            player.score = proj.score
            player.money = proj.money
            player.goCount = proj.goCount
            player.shakeCount = proj.shakeCount
            player.seatIndex = proj.seatIndex
            player.isComputer = false
            
            // Map hand
            if let handProjs = proj.hand {
                player.hand = mapCards(from: handProjs)
                player.dummyCardCount = 0
            } else {
                // If it's a non-actor player, generate dummy cards up to handCount
                player.hand = (0..<proj.handCount).map { _ in Card(month: .none, type: .junk, imageIndex: 0) }
                player.dummyCardCount = proj.handCount
            }
            
            // Map captured
            let brights = mapCards(from: proj.captured.bright)
            let animals = mapCards(from: proj.captured.animal)
            let ribbons = mapCards(from: proj.captured.ribbon)
            let junks = mapCards(from: proj.captured.junk)
            
            player.capturedCards = brights + animals + ribbons + junks
            
            players.append(player)
        }
        
        let sorted = players.sorted(by: { $0.seatIndex < $1.seatIndex })
        guard let viewerSeatIndex,
              let viewerIndex = sorted.firstIndex(where: { $0.seatIndex == viewerSeatIndex }) else {
            return sorted
        }

        return Array(sorted[viewerIndex...] + sorted[..<viewerIndex])
    }

    private func currentTurnIndex(from snapshot: MultiplayerSnapshot, players: [Player]) -> Int {
        if let currentProjection = projection(forAuthorityId: snapshot.state.currentPlayerId, in: snapshot.state.players),
           let currentIndex = players.firstIndex(where: { $0.seatIndex == currentProjection.seatIndex }) {
            return currentIndex
        }
        return 0
    }

    private func projection(forAuthorityId authorityId: String?, in projections: [MultiplayerPlayerProjection]) -> MultiplayerPlayerProjection? {
        guard let authorityId else { return nil }
        return projections.first(where: { $0.playerId == authorityId })
    }
    
    private func mapCards(from summaries: [MultiplayerCardSummary]) -> [Card] {
        return summaries.compactMap { summary -> Card? in
            guard let month = Month(rawValue: summary.month),
                  let type = mapCardType(summary.kind) else {
                return nil
            }
            
            var card = Card(month: month, type: type, imageIndex: summary.imageIndex)
            card.id = summary.cardId // Sync ID with server
            
            if let roleStr = summary.selectedRole {
                if roleStr == "animal" {
                    card.selectedRole = .animal
                } else if roleStr == "doublePi" {
                    card.selectedRole = .doublePi
                }
            }
            return card
        }
    }

    private func mapChoiceCard(_ choiceCard: MultiplayerChoiceCard) -> Card? {
        guard let month = Month(rawValue: choiceCard.month),
              let type = mapCardType(choiceCard.kind) else {
            return nil
        }

        var card = Card(month: month, type: type, imageIndex: choiceCard.imageIndex)
        card.id = choiceCard.cardId

        if let roleStr = choiceCard.selectedRole {
            if roleStr == "animal" {
                card.selectedRole = .animal
            } else if roleStr == "doublePi" {
                card.selectedRole = .doublePi
            }
        }

        return card
    }
    
    private func mapCardType(_ typeString: String) -> CardType? {
        switch typeString {
        case "bright": return .bright
        case "animal": return .animal
        case "ribbon": return .ribbon
        case "junk": return .junk
        case "doubleJunk": return .doubleJunk
        case "dummy": return .dummy
        default: return nil
        }
    }
}
