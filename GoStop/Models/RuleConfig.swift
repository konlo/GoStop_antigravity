import Foundation
import Yams

struct RuleConfig: Codable {
    var cards: CardsRule
    var scoring: ScoringRule
    var go_stop: GoStopRule
    var penalties: PenaltiesRule
    var special_moves: SpecialMovesRule
    var nagari: NagariRule
    var endgame: EndgameRule
}

struct EndgameRule: Codable {
    var max_round_score: Int
    var score_check_timing: String
    var max_go_count: Int
    var instant_end_on_bak: InstantEndOnBak
}

struct InstantEndOnBak: Codable {
    var pibak: Bool
    var gwangbak: Bool
    var mungbak: Bool
    var bomb_mungdda: Bool
}

struct SpecialMovesRule: Codable {
    var bomb: BombRule
    var shake: ShakeRule
    var sweep: SweepRule
    var ttadak: TtadakRule
    var jjok: JjokRule
    var seolsa: SeolsaRule
    var seolsaEat: SeolsaEatRule
    var mungbak_pi_threshold: Int
    var mungdda: MungDdaRule
    var bomb_mungdda: BombMungDdaRule
    var chongtong: ChongtongRule
    
    enum CodingKeys: String, CodingKey {
        case bomb, shake, sweep, ttadak, jjok, seolsa
        case seolsaEat = "seolsa_eat"
        case mungbak_pi_threshold, mungdda, bomb_mungdda, chongtong
    }
}

struct MungDdaRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var multiplier_addition: Int
    var description: String?
}

struct BombMungDdaRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var multiplier_addition: Int
    var description: String?
}

struct ChongtongRule: Codable {
    var enabled: Bool
    var resolution_type: String
    var distinguish_timing: Bool
    var initial_chongtong_score: Int
    var midgame_chongtong_score: Int
    var description: String?
}

struct TtadakRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var description: String?
}

struct JjokRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var description: String?
}

struct SeolsaRule: Codable {
    var enabled: Bool
    var penalty_pi_count: Int
    var description: String?
}

struct SeolsaEatRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var self_eat_steal_pi_count: Int
    var description: String?
}

struct SweepRule: Codable {
    var enabled: Bool
    var bonus_points: Int
    var score_multiplier_type: String?
    var steal_pi_count: Int
    var description: String?
}

struct ShakeRule: Codable {
    var enabled: Bool
    var score_multiplier_type: String?
    var description: String?
}

struct BombRule: Codable {
    var enabled: Bool
    var steal_pi_count: Int
    var score_multiplier: Int
    var dummy_card_count: Int          // How many dummy (도탄) cards the bomber receives
    var dummy_cards_disappear_on_play: Bool  // Dummy cards vanish on play, never go to table
    var description: String?
}

struct CardsRule: Codable {
    var kwang: KwangRule
    var dan: DanRule
    var yul: YulRule
    var pi: PiRule
    var chrysanthemum_rule: ChrysanthemumRule
}

struct ChrysanthemumRule: Codable {
    var enabled: Bool
    var default_role: String
    var choice_timing: String
    var allow_double_pi: Bool
}

struct KwangRule: Codable {
    var months: [Int]
}

struct DanRule: Codable {
    var hongdan: [Int]
    var cheongdan: [Int]
    var chodan: [Int]
}

struct YulRule: Codable {
    var godori: [Int]
}

struct PiRule: Codable {
    var double_pi_months: [Int]?
    var conditional_double_pi: [ConditionalPiRule]?
    var bonus_cards: Int
}

struct ConditionalPiRule: Codable {
    var month: Int
    var condition: String
    var bonus_points: Int
}

struct ScoringRule: Codable {
    var kwang: KwangScoring
    var dan: CombinationScoring
    var yul: GodoriScoring
    var pi: PiScoring
    
    enum CodingKeys: String, CodingKey {
        case kwang, dan, yul, pi
    }
}

struct KwangScoring: Codable {
    var samgwang: Int
    var bisamgwang: Int
    var sagwang: Int
    var ogwang: Int
}

struct CombinationScoring: Codable {
    var min_count: Int
    var min_score: Int
    var additional_score: Int
    var hongdan: Int
    var cheongdan: Int
    var chodan: Int
}

struct GodoriScoring: Codable {
    var min_count: Int
    var min_score: Int
    var additional_score: Int
    var godori: Int
}

struct PiScoring: Codable {
    var min_count: Int
    var min_score: Int
    var additional_score: Int
}


struct GoStopRule: Codable {
    var min_score_3_players: Int
    var min_score_2_players: Int
    var apply_bak_on_stop: Bool
    var bak_only_if_opponent_go: Bool
    var go_bonuses: [String: GoBonus]
}

struct GoBonus: Codable {
    var add: Int
    var multiply: Int
}

struct PenaltiesRule: Codable {
    var gobak: GobakRule
    var gwangbak: GwangbakRule
    var pibak: PibakRule
    var mungbak: MungbakRule
    var jabak: JabakRule
    var yeokbak: YeokbakRule
}

struct JabakRule: Codable {
    var enabled: Bool
    var min_score_threshold: Int
    var description: String?
}

struct YeokbakRule: Codable {
    var enabled: Bool
    var description: String?
}

struct GobakRule: Codable {
    var enabled: Bool
    var multiplier: Int
}

struct GwangbakRule: Codable {
    var enabled: Bool
    var resolution_type: String
    var pi_to_transfer: Int
    var opponent_max_kwang: Int
    var multiplier: Int
}

struct PibakRule: Codable {
    var enabled: Bool
    var resolution_type: String
    var pi_to_transfer: Int
    var opponent_min_pi_safe: Int
    var multiplier: Int
}

struct MungbakRule: Codable {
    var enabled: Bool
    var resolution_type: String
    var pi_to_transfer: Int
    var winner_min_animal: Int
    var multiplier: Int
    var description: String?
}

struct NagariRule: Codable {
    var enabled: Bool
    var next_game_multiplier: Int
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
