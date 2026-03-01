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

    struct HandToTableMotionPlan {
        let animation: Animation?
        let delay: Double
    }

    
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
        let mode = config.hand_to_table_motion.lowercased()
        let duration = max(0.01, config.play_from_hand_duration)
        
        switch mode {
        case "instant":
            return HandToTableMotionPlan(animation: nil, delay: 0)
        case "throw":
            return HandToTableMotionPlan(animation: throwAnimation(for: duration), delay: duration)
        case "linear":
            return HandToTableMotionPlan(animation: .linear(duration: duration), delay: duration)
        case "styled":
            return HandToTableMotionPlan(animation: animation(for: duration), delay: duration)
        default:
            return HandToTableMotionPlan(animation: nil, delay: 0)
        }
    }

    /// Helper to run a block with the configured animation
    func withGameAnimation(_ action: @escaping () -> Void) {
        withAnimation(moveAnimation) {
            action()
        }
    }
}
