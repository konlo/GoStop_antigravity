import Foundation
import Yams

struct RuleConfig: Codable {
    let cards: CardsRule
    let scoring: ScoringRule
    let go_stop: GoStopRule
    let penalties: PenaltiesRule
    let special_moves: SpecialMovesRule
    let nagari: NagariRule
    let endgame: EndgameRule
}

struct EndgameRule: Codable {
    let max_round_score: Int
    let score_check_timing: String
    let max_go_count: Int
    let instant_end_on_bak: InstantEndOnBak
}

struct InstantEndOnBak: Codable {
    let pibak: Bool
    let gwangbak: Bool
    let mungbak: Bool
    let bomb_mungdda: Bool
}

struct SpecialMovesRule: Codable {
    let bomb: BombRule
    let shake: ShakeRule
    let sweep: SweepRule
    let ttadak: TtadakRule
    let jjok: JjokRule
    let seolsa: SeolsaRule
    let seolsaEat: SeolsaEatRule
    let mungbak_pi_threshold: Int
    let mungdda: MungDdaRule
    let bomb_mungdda: BombMungDdaRule
    let chongtong: ChongtongRule
    
    enum CodingKeys: String, CodingKey {
        case bomb, shake, sweep, ttadak, jjok, seolsa
        case seolsaEat = "seolsa_eat"
        case mungbak_pi_threshold, mungdda, bomb_mungdda, chongtong
    }
}

struct MungDdaRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let multiplier_addition: Int
    let description: String?
}

struct BombMungDdaRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let multiplier_addition: Int
    let description: String?
}

struct ChongtongRule: Codable {
    let enabled: Bool
    let resolution_type: String
    let distinguish_timing: Bool
    let initial_chongtong_score: Int
    let midgame_chongtong_score: Int
    let description: String?
}

struct TtadakRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let description: String?
}

struct JjokRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let description: String?
}

struct SeolsaRule: Codable {
    let enabled: Bool
    let penalty_pi_count: Int
    let description: String?
}

struct SeolsaEatRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let self_eat_steal_pi_count: Int
    let description: String?
}

struct SweepRule: Codable {
    let enabled: Bool
    let bonus_points: Int
    let score_multiplier_type: String?
    let steal_pi_count: Int
    let description: String?
}

struct ShakeRule: Codable {
    let enabled: Bool
    let score_multiplier_type: String?
    let description: String?
}

struct BombRule: Codable {
    let enabled: Bool
    let steal_pi_count: Int
    let score_multiplier: Int
    let dummy_card_count: Int          // How many dummy (도탄) cards the bomber receives
    let dummy_cards_disappear_on_play: Bool  // Dummy cards vanish on play, never go to table
    let description: String?
}

struct CardsRule: Codable {
    let kwang: KwangRule
    let dan: DanRule
    let yul: YulRule
    let pi: PiRule
    let chrysanthemum_rule: ChrysanthemumRule
}

struct ChrysanthemumRule: Codable {
    let enabled: Bool
    let default_role: String
    let choice_timing: String
    let allow_double_pi: Bool
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
    let double_pi_months: [Int]?
    let conditional_double_pi: [ConditionalPiRule]?
    let bonus_cards: Int
}

struct ConditionalPiRule: Codable {
    let month: Int
    let condition: String
    let bonus_points: Int
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
    let apply_bak_on_stop: Bool
    let bak_only_if_opponent_go: Bool
    let go_bonuses: [String: GoBonus]
}

struct GoBonus: Codable {
    let add: Int
    let multiply: Int
}

struct PenaltiesRule: Codable {
    let gobak: GobakRule
    let gwangbak: GwangbakRule
    let pibak: PibakRule
    let mungbak: MungbakRule
    let jabak: JabakRule
    let yeokbak: YeokbakRule
}

struct JabakRule: Codable {
    let enabled: Bool
    let min_score_threshold: Int
    let description: String?
}

struct YeokbakRule: Codable {
    let enabled: Bool
    let description: String?
}

struct GobakRule: Codable {
    let enabled: Bool
    let multiplier: Int
}

struct GwangbakRule: Codable {
    let enabled: Bool
    let resolution_type: String
    let pi_to_transfer: Int
    let opponent_max_kwang: Int
    let multiplier: Int
}

struct PibakRule: Codable {
    let enabled: Bool
    let resolution_type: String
    let pi_to_transfer: Int
    let opponent_min_pi_safe: Int
    let multiplier: Int
}

struct MungbakRule: Codable {
    let enabled: Bool
    let resolution_type: String
    let pi_to_transfer: Int
    let winner_min_animal: Int
    let multiplier: Int
    let description: String?
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
            let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let executableDir = executableURL.deletingLastPathComponent()
            let adjacentPath = executableDir.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: adjacentPath) {
                url = URL(fileURLWithPath: adjacentPath)
            }
        }

        guard let targetUrl = url else {
            let workingDir = FileManager.default.currentDirectoryPath
            FileHandle.standardError.write("FAILED to locate rule.yaml. Checked bundle, currentDir(\(workingDir)), and execDir. Executable was: \(CommandLine.arguments[0])\n".data(using: .utf8)!)
            return
        }
        
        FileHandle.standardError.write("Loading rules from: \(targetUrl.path)\n".data(using: .utf8)!)
        
        do {
            let data = try Data(contentsOf: targetUrl)
            if let yamlString = String(data: data, encoding: .utf8) {
                let decoder = YAMLDecoder()
                config = try decoder.decode(RuleConfig.self, from: yamlString)
                gLog("Successfully loaded RuleConfig.")
            }
        } catch {
            let errMsg = "Error parsing rule.yaml: \(error)"
            FileHandle.standardError.write("\(errMsg)\n".data(using: .utf8)!)
            gLog("CRITICAL: \(errMsg)")
        }
    }
}
