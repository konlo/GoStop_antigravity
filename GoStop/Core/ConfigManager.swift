import Foundation

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    private static let layoutDebugEnvKey = "GOSTOP_LAYOUT_DEBUG"
    private static var layoutDebugEnabled: Bool {
        ProcessInfo.processInfo.environment[layoutDebugEnvKey] == "1"
    }
    
    // V2 System
    @Published var layoutV2: LayoutConfigV2?
    @Published var layoutContext: LayoutContext?
    
    // Legacy System (Deprecated - Kept for compilation until full migration)
    @Published var layout: LayoutConfig
    
    @Published var gameSize: CGSize = CGSize(width: 393, height: 852) // Default to iPhone 15 size
    
    // Rules System
    @Published var ruleConfig: RuleConfig?
    
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
        // Load V2
        self.layoutV2 = ConfigManager.loadLayoutV2()
        
        // Initialize Legacy with Default (since JSON is V2, V1 decode will fail)
        self.layout = ConfigManager.defaultLegacyLayout()
        
        // Initial Context
        self.updateLayoutContext()
        
        // Load Rules
        self.ruleConfig = RuleLoader.shared.config
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
