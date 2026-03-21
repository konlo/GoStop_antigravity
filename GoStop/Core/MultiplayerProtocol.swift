import Foundation

/// Actions that a direct player can take in a multiplayer game.
/// These are typically serialized and sent to the authoritative server.
enum MultiplayerAction: Codable {
    case playCard(cardId: String)
    case respondToCapture(cardId: String)
    case respondToGoStop(isGo: Bool)
    case respondToShake(month: Int, didShake: Bool)
    case respondToChrysanthemumChoice(role: String) // "animal" | "doublePi"
    case chat(emojiId: String)
    
    enum CodingKeys: String, CodingKey {
        case action
        case cardId
        case isGo
        case month
        case didShake
        case role
        case emojiId
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playCard(let cardId):
            try container.encode("play_card", forKey: .action)
            try container.encode(cardId, forKey: .cardId)
        case .respondToCapture(let cardId):
            try container.encode("respond_to_capture", forKey: .action)
            try container.encode(cardId, forKey: .cardId)
        case .respondToGoStop(let isGo):
            try container.encode("respond_go_stop", forKey: .action)
            try container.encode(isGo, forKey: .isGo)
        case .respondToShake(let month, let didShake):
            try container.encode("respond_to_shake", forKey: .action)
            try container.encode(month, forKey: .month)
            try container.encode(didShake, forKey: .didShake)
        case .respondToChrysanthemumChoice(let role):
            try container.encode("respond_to_chrysanthemum_choice", forKey: .action)
            try container.encode(role, forKey: .role)
        case .chat(let emojiId):
            try container.encode("chat", forKey: .action)
            try container.encode(emojiId, forKey: .emojiId)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        
        switch action {
        case "play_card":
            let cardId = try container.decode(String.self, forKey: .cardId)
            self = .playCard(cardId: cardId)
        case "respond_to_capture":
            let cardId = try container.decode(String.self, forKey: .cardId)
            self = .respondToCapture(cardId: cardId)
        case "respond_go_stop":
            let isGo = try container.decode(Bool.self, forKey: .isGo)
            self = .respondToGoStop(isGo: isGo)
        case "respond_to_shake":
            let month = try container.decode(Int.self, forKey: .month)
            let didShake = try container.decode(Bool.self, forKey: .didShake)
            self = .respondToShake(month: month, didShake: didShake)
        case "respond_to_chrysanthemum_choice":
            let role = try container.decode(String.self, forKey: .role)
            self = .respondToChrysanthemumChoice(role: role)
        case "chat":
            let emojiId = try container.decode(String.self, forKey: .emojiId)
            self = .chat(emojiId: emojiId)
        default:
            throw DecodingError.dataCorruptedError(forKey: .action, in: container, debugDescription: "Unknown action: \(action)")
        }
    }
}
