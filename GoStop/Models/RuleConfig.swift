import Foundation
import Yams

struct RuleConfig: Codable {
    let cards: CardsRule
    let scoring: ScoringRule
    let go_stop: GoStopRule
    let penalties: PenaltiesRule
    let nagari: NagariRule
}

struct CardsRule: Codable {
    let kwang: KwangRule
    let dan: DanRule
    let yul: YulRule
    let pi: PiRule
}

struct KwangRule: Codable {
    let months: [Int]
}

struct DanRule: Codable {
    let hongdan: [Int]
    let cheongdan: [Int]
    let chodan: [Int]
}

struct YulRule: Codable {
    let godori: [Int]
}

struct PiRule: Codable {
    let double_pi_months: [Int]
    let bonus_cards: Int
}

struct ScoringRule: Codable {
    let kwang: KwangScoring
    let dan: CombinationScoring
    let yul: GodoriScoring
    let pi: PiScoring
    
    enum CodingKeys: String, CodingKey {
        case kwang, dan, yul, pi
    }
}

struct KwangScoring: Codable {
    let samgwang: Int
    let bisamgwang: Int
    let sagwang: Int
    let ogwang: Int
}

struct CombinationScoring: Codable {
    let min_count: Int
    let min_score: Int
    let additional_score: Int
    let hongdan: Int
    let cheongdan: Int
    let chodan: Int
}

struct GodoriScoring: Codable {
    let min_count: Int
    let min_score: Int
    let additional_score: Int
    let godori: Int
}

struct PiScoring: Codable {
    let min_count: Int
    let min_score: Int
    let additional_score: Int
}


struct GoStopRule: Codable {
    let min_score_3_players: Int
    let min_score_2_players: Int
    let go_bonuses: [String: GoBonus]
}

struct GoBonus: Codable {
    let add: Int
    let multiply: Int
}

struct PenaltiesRule: Codable {
    let gobak: Bool
    let gwangbak: GwangbakRule
    let pibak: PibakRule
}

struct GwangbakRule: Codable {
    let enabled: Bool
    let opponent_max_kwang: Int
}

struct PibakRule: Codable {
    let enabled: Bool
    let opponent_min_pi_safe: Int
}

struct NagariRule: Codable {
    let enabled: Bool
    let next_game_multiplier: Int
}

class RuleLoader {
    static let shared = RuleLoader()
    private(set) var config: RuleConfig?
    
    private init() {
        loadRules()
    }
    
    func loadRules() {
        let filename = "rule.yaml"
        var url = Bundle.main.url(forResource: "rule", withExtension: "yaml")
        
        // If not found in bundle, try local directory (for CLI)
        if url == nil {
            let localPath = FileManager.default.currentDirectoryPath + "/" + filename
            if FileManager.default.fileExists(atPath: localPath) {
                url = URL(fileURLWithPath: localPath)
            }
        }
        
        // Try one more: adjacent to executable
        if url == nil {
            let execPath = Bundle.main.bundlePath + "/" + filename
            if FileManager.default.fileExists(atPath: execPath) {
                url = URL(fileURLWithPath: execPath)
            }
        }

        guard let targetUrl = url else {
            FileHandle.standardError.write("Failed to locate rule.yaml\n".data(using: .utf8)!)
            return
        }
        
        do {
            let data = try Data(contentsOf: targetUrl)
            if let yamlString = String(data: data, encoding: .utf8) {
                let decoder = YAMLDecoder()
                config = try decoder.decode(RuleConfig.self, from: yamlString)
            }
        } catch {
            FileHandle.standardError.write("Error parsing rule.yaml: \(error)\n".data(using: .utf8)!)
        }
    }
}
