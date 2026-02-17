import Foundation
import SwiftUI

struct LayoutConfig: Codable {
    let debug: DebugConfig?
    let card: CardConfig
    let images: ImageConfig
    let areas: AreasConfig
}

struct DebugConfig: Codable {
    let showGrid: Bool
}

struct AreasConfig: Codable {
    let opponent: AreaSectionConfig
    let center: AreaSectionConfig
    let player: AreaSectionConfig
}

struct AreaSectionConfig: Codable {
    let heightRatio: CGFloat
    let background: AreaBackgroundConfig?
    let elements: AreaElementsConfig
}

// Elements Config - Using a unified dictionary-like structure or specific optional properties
// Since JSON has different keys for different areas, we can use specific structs or a unified one.
// Let's use a unified one for simplicity where keys are optional.
struct AreaElementsConfig: Codable {
    let hand: ElementPositionConfig?
    let captured: ElementPositionConfig?
    let table: ElementPositionConfig?
    let deck: ElementPositionConfig?
}

struct ElementPositionConfig: Codable {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat?
    let grid: GridConfig?
    let layout: CapturedLayoutConfig? // Reusing for captured
}

// Reuse existing CardConfig, ImageConfig, AreaBackgroundConfig
struct CardConfig: Codable {
    let width: CGFloat
    let aspectRatio: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let backColor: String
    let backCircleColor: String
    
    var backColorSwiftUI: Color { Color(hex: backColor) }
    var backCircleColorSwiftUI: Color { Color(hex: backCircleColor) }
}

struct ImageConfig: Codable {
    let prefix: String
}

struct AreaBackgroundConfig: Codable {
    let color: String
    let opacity: CGFloat
    let cornerRadius: CGFloat
    let widthRatio: CGFloat
    
    var colorSwiftUI: Color { Color(hex: color).opacity(opacity) }
}

struct GridConfig: Codable {
    let rows: Int?
    let maxCols: Int?
    let verticalSpacing: CGFloat?
    let horizontalSpacing: CGFloat?
    let stackOverlapRatio: CGFloat? // For Table
    let background: AreaBackgroundConfig? // Nested background for grid?
}

struct CapturedLayoutConfig: Codable {
    let groupSpacing: CGFloat?
    let cardOverlap: CGFloat?
}

// Helper for Hex Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
