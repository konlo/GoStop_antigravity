import Foundation

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var layout: LayoutConfig
    @Published var gameSize: CGSize = CGSize(width: 393, height: 852) // Default to iPhone 15 size to avoid 0
    
    // Helper to calculate constant card size based on current layout and game size
    func cardSize(scale: CGFloat = 1.0) -> CGSize {
        let width = gameSize.width * layout.card.width * scale
        let height = width * layout.card.aspectRatio
        return CGSize(width: width, height: height)
    }
    
    func updateGameSize(_ size: CGSize) {
        // Prevent infinite loops by only updating if changed significantly
        if abs(size.width - gameSize.width) > 1 || abs(size.height - gameSize.height) > 1 {
            print("Updating Game Size: \(size)")
            DispatchQueue.main.async {
                self.gameSize = size
            }
        }
    }
    
    // Helper for vertical spacing ratio
    func verticalSpacing(_ ratio: CGFloat) -> CGFloat {
        return gameSize.height * ratio
    }
    
    // Helper for horizontal spacing ratio
    func horizontalSpacing(_ ratio: CGFloat) -> CGFloat {
        return gameSize.width * ratio
    }

    private init() {
        self.layout = ConfigManager.loadLayoutConfig()
    }
    
    static func loadLayoutConfig() -> LayoutConfig {
        guard let url = Bundle.main.url(forResource: "layout_hwatu", withExtension: "json") else {
            print("Layout config file not found, using default values.")
            return LayoutConfig(
                debug: DebugConfig(showGrid: true),
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
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(LayoutConfig.self, from: data)
        } catch {
            print("Error decoding layout config: \(error)")
            // Fallback default
             return LayoutConfig(
                debug: DebugConfig(showGrid: true),
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
    }
    
    func reloadConfig() {
        self.layout = ConfigManager.loadLayoutConfig()
    }
}
