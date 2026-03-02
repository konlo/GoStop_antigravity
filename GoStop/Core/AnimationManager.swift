import Foundation
import SwiftUI
import Yams

/// Configuration for card animations, loaded from animation.yaml
struct AnimationConfig: Codable {
    var card_move_duration: Double = 0.4
    var card_move_delay_per_item: Double = 0.05
    var background_music_enabled: Bool = true
    var animation_style: String = "spring"
    var spring_response: Double = 0.4
    var spring_damping: Double = 0.75
    var spring_blend_duration: Double = 0
    var deal_from_deck_duration: Double = 0.5
    var capture_to_player_duration: Double = 0.4
    var play_from_hand_duration: Double = 0.3
    var hand_to_table_motion: String = "instant"   // instant | throw | styled | linear
    // Route-level overrides. If duration is nil or <= 0, fallback duration is used.
    var deck_to_table_duration: Double? = nil
    var table_to_captured_duration: Double? = nil
    var captured_to_captured_duration: Double? = nil
    // Route-level motion mode. Use "hand" to inherit hand_to_table_motion.
    var deck_to_table_motion: String = "styled"
    var table_to_captured_motion: String = "styled"
    var captured_to_captured_motion: String = "hand"
    var opponent_preplay_reveal_duration: Double = 0.14
    var match_pause_duration: Double = 0.18
    var show_trail: Bool = false
    var card_rotation_enabled: Bool = true
    var max_rotation_angle: Double = 15.0
    var turn_change_delay: Double = 0.3
    var turn_indicator_duration: Double = 0.6
    var opponent_action_delay: Double = 1.0     // Delay before AI makes an action to make it visible
}

/// Manages UI animations for the Go-Stop game.
/// This class is separated from the game logic and is driven by animation.yaml.
class AnimationManager: ObservableObject {
    static let shared = AnimationManager()
    
    @Published var config = AnimationConfig()
    private var lastLoadedPath: String?

    struct CardMovePlan {
        let animation: Animation?
        let delay: Double
    }

    typealias HandToTableMotionPlan = CardMovePlan

    
    private init() {
        loadConfig()
    }
    
    /// Loads animation configuration from animation.yaml
    func loadConfig() {
        let paths = [
            Bundle.main.path(forResource: "animation", ofType: "yaml"),
            FileManager.default.currentDirectoryPath + "/animation.yaml",
            "/Users/najongseong/git_repository/GoStop_antigravity/animation.yaml"
        ]
        
        for path in paths {
            if let path = path, let data = try? String(contentsOfFile: path) {
                let decoder = YAMLDecoder()
                if let decoded = try? decoder.decode(AnimationConfig.self, from: data) {
                    self.config = decoded
                    self.lastLoadedPath = path
                    fputs("AnimationManager: Loaded config from \(path)\n", stderr)
                    return

                }
            }
        }
        fputs("AnimationManager: Using default configuration.\n", stderr)
    }
    
    /// Saves current configuration back to the file it was loaded from
    func saveConfig() {
        let encoder = YAMLEncoder()
        do {
            let encoded = try encoder.encode(self.config)
            let path = lastLoadedPath ?? (FileManager.default.currentDirectoryPath + "/animation.yaml")
            try encoded.write(toFile: path, atomically: true, encoding: .utf8)
            fputs("AnimationManager: Saved config to \(path)\n", stderr)
        } catch {
            fputs("AnimationManager: Error saving config: \(error)\n", stderr)
        }
    }

    
    /// Returns the SwiftUI Animation based on current YAML configuration
    var moveAnimation: Animation {
        if config.animation_style == "spring" {
            return .spring(
                response: config.spring_response,
                dampingFraction: config.spring_damping,
                blendDuration: config.spring_blend_duration
            )
        } else if config.animation_style == "linear" {
            return .linear(duration: config.card_move_duration)
        } else {
            return .easeInOut(duration: config.card_move_duration)
        }
    }

    /// Returns animation style with the provided duration.
    /// Used to keep different move phases (e.g. hand->table) under one YAML setting.
    func animation(for duration: Double) -> Animation {
        let d = max(0.01, duration)
        if config.animation_style == "spring" {
            return .spring(
                response: d,
                dampingFraction: config.spring_damping,
                blendDuration: config.spring_blend_duration
            )
        } else if config.animation_style == "linear" {
            return .linear(duration: d)
        } else {
            return .easeInOut(duration: d)
        }
    }

    /// Fast, accelerating throw motion for hand -> table.
    /// This keeps card flight snappy while match_pause_duration provides impact readability.
    func throwAnimation(for duration: Double) -> Animation {
        let d = max(0.05, duration)
        // Quick launch + short settle to feel like a thrown card.
        return .timingCurve(0.12, 0.9, 0.22, 1.0, duration: d)
    }

    /// Centralized policy for hand -> table motion.
    /// Update `animation.yaml: hand_to_table_motion` to apply globally.
    func handToTableMotionPlan() -> HandToTableMotionPlan {
        motionPlan(source: "hand", target: "table")
    }

    /// Unified motion planning engine for all card routes.
    /// Route differences are controlled by `animation.yaml`.
    func motionPlan(source: String, target: String) -> CardMovePlan {
        let route = "\(source.lowercased())->\(target.lowercased())"
        switch route {
        case "hand->table":
            return motionPlan(mode: config.hand_to_table_motion, duration: config.play_from_hand_duration)
        case "deck->table":
            return motionPlan(
                mode: config.deck_to_table_motion,
                duration: resolvedDuration(config.deck_to_table_duration, fallback: config.card_move_duration)
            )
        case "table->captured":
            return motionPlan(
                mode: config.table_to_captured_motion,
                duration: resolvedDuration(config.table_to_captured_duration, fallback: config.capture_to_player_duration)
            )
        case "captured->captured":
            return motionPlan(
                mode: config.captured_to_captured_motion,
                duration: resolvedDuration(config.captured_to_captured_duration, fallback: config.play_from_hand_duration)
            )
        default:
            return motionPlan(mode: "styled", duration: config.card_move_duration)
        }
    }

    private func resolvedDuration(_ override: Double?, fallback: Double) -> Double {
        if let override, override > 0 {
            return override
        }
        return fallback
    }

    private func motionPlan(mode: String, duration: Double) -> CardMovePlan {
        let normalizedMode = mode.lowercased()
        let d = max(0.01, duration)

        switch normalizedMode {
        case "hand", "inherit", "inherit_hand_to_table":
            let inheritedMode = config.hand_to_table_motion.lowercased()
            if inheritedMode == "hand" || inheritedMode == "inherit" || inheritedMode == "inherit_hand_to_table" {
                return CardMovePlan(animation: animation(for: max(0.01, config.play_from_hand_duration)), delay: max(0.01, config.play_from_hand_duration))
            }
            return motionPlan(mode: inheritedMode, duration: config.play_from_hand_duration)
        case "instant":
            return CardMovePlan(animation: nil, delay: 0)
        case "throw":
            return CardMovePlan(animation: throwAnimation(for: d), delay: d)
        case "linear":
            return CardMovePlan(animation: .linear(duration: d), delay: d)
        case "styled":
            return CardMovePlan(animation: animation(for: d), delay: d)
        default:
            return CardMovePlan(animation: nil, delay: 0)
        }
    }

    /// Helper to run a block with the configured animation
    func withGameAnimation(_ action: @escaping () -> Void) {
        withAnimation(moveAnimation) {
            action()
        }
    }
}
