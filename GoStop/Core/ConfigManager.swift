import Foundation
import Yams

struct AppRuntimeConfiguration: Codable {
    var first_launch_starter_applied: Bool = false
    var language: String = "ko"

    init(
        first_launch_starter_applied: Bool = false,
        language: String = "ko"
    ) {
        self.first_launch_starter_applied = first_launch_starter_applied
        self.language = Self.normalizedLanguageCode(language)
    }

    enum CodingKeys: String, CodingKey {
        case first_launch_starter_applied
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        first_launch_starter_applied = try container.decodeIfPresent(Bool.self, forKey: .first_launch_starter_applied) ?? false
        language = Self.normalizedLanguageCode(
            try container.decodeIfPresent(String.self, forKey: .language) ?? "ko"
        )
    }

    static func normalizedLanguageCode(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        if normalized.hasPrefix("en") {
            return "en"
        }
        return "ko"
    }
}

struct AppConfiguration: Codable {
    var version: Int = 1
    var rule: RuleConfig?
    var animation: AnimationConfig?
    var app: AppRuntimeConfiguration = AppRuntimeConfiguration()
}

final class ConfigurationStore {
    static let shared = ConfigurationStore()

    private static let fileName = "configuration.yaml"
    private let fileManager: FileManager
    private let encoder = YAMLEncoder()
    private let decoder = YAMLDecoder()
    private let fileURL: URL
    private var cachedConfiguration: AppConfiguration

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = Self.resolveFileURL(fileManager: fileManager)
        self.cachedConfiguration = AppConfiguration()
        self.cachedConfiguration = loadFromDisk()
    }

    var configurationPath: String {
        fileURL.path
    }

    func ruleConfig() -> RuleConfig? {
        cachedConfiguration.rule
    }

    @discardableResult
    func setRuleConfig(_ config: RuleConfig) -> Bool {
        cachedConfiguration.rule = config
        return persistToDisk()
    }

    func animationConfig() -> AnimationConfig? {
        cachedConfiguration.animation
    }

    @discardableResult
    func setAnimationConfig(_ config: AnimationConfig) -> Bool {
        cachedConfiguration.animation = config
        return persistToDisk()
    }

    func firstLaunchStarterApplied() -> Bool {
        cachedConfiguration.app.first_launch_starter_applied
    }

    func appLanguage() -> String {
        cachedConfiguration.app.language
    }

    @discardableResult
    func setFirstLaunchStarterApplied(_ isApplied: Bool) -> Bool {
        cachedConfiguration.app.first_launch_starter_applied = isApplied
        return persistToDisk()
    }

    @discardableResult
    func setAppLanguage(_ language: String) -> Bool {
        cachedConfiguration.app.language = AppRuntimeConfiguration.normalizedLanguageCode(language)
        return persistToDisk()
    }

    private func loadFromDisk() -> AppConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AppConfiguration()
        }

        do {
            let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
            if yamlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AppConfiguration()
            }
            return try decoder.decode(AppConfiguration.self, from: yamlString)
        } catch {
            fputs("ConfigurationStore: Failed to parse \(fileURL.path): \(error)\n", stderr)
            return AppConfiguration()
        }
    }

    @discardableResult
    private func persistToDisk() -> Bool {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            let yamlString = try encoder.encode(cachedConfiguration)
            try yamlString.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            fputs("ConfigurationStore: Failed to persist \(fileURL.path): \(error)\n", stderr)
            return false
        }
    }

    private static func resolveFileURL(fileManager: FileManager) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["GOSTOP_CONFIGURATION_PATH"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let currentDirectoryFileURL = currentDirectoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: currentDirectoryFileURL.path) ||
            fileManager.isWritableFile(atPath: currentDirectoryURL.path) {
            return currentDirectoryFileURL
        }

        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsDirectory.appendingPathComponent(fileName)
        }

        return currentDirectoryFileURL
    }
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    private static let layoutDebugEnvKey = "GOSTOP_LAYOUT_DEBUG"
    private static var layoutDebugEnabled: Bool {
        // Default ON for active UI debugging sessions.
        // Set GOSTOP_LAYOUT_DEBUG=0 to force-disable.
        ProcessInfo.processInfo.environment[layoutDebugEnvKey] != "0"
    }
    
    // V2 System
    @Published var layoutV2: LayoutConfigV2?
    @Published var layoutContext: LayoutContext?
    
    // Legacy System (Deprecated - Kept for compilation until full migration)
    @Published var layout: LayoutConfig
    
    @Published var gameSize: CGSize = CGSize(width: 393, height: 852) // Default to iPhone 15 size
    
    // Rules System
    @Published var ruleConfig: RuleConfig?
    @Published var appLanguage: String
    
    // Helper to calculate constant card size based on current layout and game size
    func cardSize(scale: CGFloat = 1.0) -> CGSize {
        // V2 Adapter: Use Context if available
        if let ctx = layoutContext {
            return CGSize(width: ctx.cardSize.width * scale, height: ctx.cardSize.height * scale)
        }
        // Fallback to Legacy
        let width = gameSize.width * layout.card.width * scale
        let height = width * layout.card.aspectRatio
        return CGSize(width: width, height: height)
    }
    
    func updateGameSize(_ size: CGSize) {
        // Prevent infinite loops by only updating if changed significantly
        if abs(size.width - gameSize.width) > 1 || abs(size.height - gameSize.height) > 1 {
            if Self.layoutDebugEnabled {
                fputs("Updating Game Size: \(size)\n", stderr)
            }
            DispatchQueue.main.async {
                self.gameSize = size
                self.updateLayoutContext()
            }
        }
    }
    
    private func updateLayoutContext() {
        guard let v2 = layoutV2 else { return }
        self.layoutContext = LayoutContext(config: v2, safeAreaSize: self.gameSize)
        if Self.layoutDebugEnabled {
            fputs("LayoutContext Updated [GlobalScale: \(self.layoutContext?.globalScale ?? 0)]\n", stderr)
        }
    }
    
    // Helper for vertical spacing ratio
    func verticalSpacing(_ ratio: CGFloat) -> CGFloat {
        if let _ = layoutContext {
            // In V2, most spacing is handled inside Context or Token, but helper might be useful
             return gameSize.height * ratio // Logic remains similar for simple ratio
        }
        return gameSize.height * ratio
    }
    
    // Helper for horizontal spacing ratio
    func horizontalSpacing(_ ratio: CGFloat) -> CGFloat {
        return gameSize.width * ratio
    }

    private init() {
        self.appLanguage = ConfigurationStore.shared.appLanguage()
        // Load V2
        self.layoutV2 = ConfigManager.loadLayoutV2()
        
        // Initialize Legacy with Default (since JSON is V2, V1 decode will fail)
        self.layout = ConfigManager.defaultLegacyLayout()
        
        // Initial Context
        self.updateLayoutContext()
        
        // Load Rules
        self.ruleConfig = RuleLoader.shared.config
    }

    @discardableResult
    func saveAppLanguage() -> Bool {
        let normalized = AppRuntimeConfiguration.normalizedLanguageCode(appLanguage)
        appLanguage = normalized
        return ConfigurationStore.shared.setAppLanguage(normalized)
    }
    
    static func loadLayoutV2() -> LayoutConfigV2? {
        guard let url = Bundle.main.url(forResource: "layout_hwatu", withExtension: "json") else {
            fputs("Layout config file not found.\n", stderr)
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(LayoutConfigV2.self, from: data)
            if layoutDebugEnabled {
                return decoded
            }
            return decoded.disablingDebugOverlays()
        } catch {
            fputs("Error decoding Layout V2: \(error)\n", stderr)
            return nil
        }
    }
    
    // Legacy Loader (Removed, replaced with default generator)
    static func defaultLegacyLayout() -> LayoutConfig {
         return LayoutConfig(
            debug: DebugConfig(showGrid: false),
            card: CardConfig(width: 0.15, aspectRatio: 1.6, cornerRadius: 0.1, shadowRadius: 2, backColor: "#CC3333", backCircleColor: "#991A1A"),
            images: ImageConfig(prefix: "Card_"),
            areas: AreasConfig(
                opponent: AreaSectionConfig(
                    heightRatio: 0.25,
                    background: AreaBackgroundConfig(color: "#FFEEEE", opacity: 0.1, cornerRadius: 0, widthRatio: 1.0),
                    elements: AreaElementsConfig(
                        hand: ElementPositionConfig(x: 0.5, y: 0.3, scale: 0.8, grid: GridConfig(rows: 1, maxCols: 10, verticalSpacing: 0, horizontalSpacing: 0.03, stackOverlapRatio: nil, background: nil), layout: nil),
                        captured: ElementPositionConfig(x: 0.5, y: 0.8, scale: 0.85, grid: nil, layout: CapturedLayoutConfig(groupSpacing: 10, cardOverlap: 30)),
                        table: nil, deck: nil
                    )
                ),
                center: AreaSectionConfig(
                    heightRatio: 0.40,
                    background: AreaBackgroundConfig(color: "#000000", opacity: 0.2, cornerRadius: 20, widthRatio: 0.95),
                    elements: AreaElementsConfig(
                        hand: nil, captured: nil,
                        table: ElementPositionConfig(x: 0.5, y: 0.5, scale: 1.0, grid: GridConfig(rows: 2, maxCols: nil, verticalSpacing: 0.025, horizontalSpacing: 0.02, stackOverlapRatio: 0.6, background: nil), layout: nil),
                        deck: ElementPositionConfig(x: 0.5, y: 0.5, scale: 0.9, grid: nil, layout: nil)
                    )
                ),
                player: AreaSectionConfig(
                    heightRatio: 0.35,
                    background: AreaBackgroundConfig(color: "#EEFFEE", opacity: 0.1, cornerRadius: 0, widthRatio: 1.0),
                    elements: AreaElementsConfig(
                        hand: ElementPositionConfig(x: 0.5, y: 0.75, scale: 1.1, grid: GridConfig(rows: 2, maxCols: 5, verticalSpacing: 0.01, horizontalSpacing: 0.05, stackOverlapRatio: nil, background: AreaBackgroundConfig(color: "#FFFFFF", opacity: 0.1, cornerRadius: 15, widthRatio: 0.9)), layout: nil),
                        captured: ElementPositionConfig(x: 0.5, y: 0.25, scale: 0.85, grid: nil, layout: CapturedLayoutConfig(groupSpacing: 10, cardOverlap: 30)),
                        table: nil, deck: nil
                    )
                )
            )
        )
    }
    
    func reloadConfig() {
        self.layoutV2 = ConfigManager.loadLayoutV2()
        self.updateLayoutContext()
    }
}
