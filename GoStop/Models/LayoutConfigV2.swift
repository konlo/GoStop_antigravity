import Foundation
import SwiftUI

// MARK: - Root Config
struct LayoutConfigV2: Codable {
    let version: Int
    let debug: DebugConfigV2
    let referenceCanvas: ReferenceCanvasConfig
    let scaling: ScalingConfig
    let tokens: LayoutTokens
    let card: CardConfigV2
    let images: ImageConfigV2
    let areas: AreasConfigV2
}

// MARK: - Debug
struct DebugConfigV2: Codable {
    let showGrid: Bool
    let showSafeArea: Bool
    let showElementBounds: Bool
}

// MARK: - Reference & Scaling
struct ReferenceCanvasConfig: Codable {
    let widthPt: CGFloat
    let heightPt: CGFloat
}

struct ScalingConfig: Codable {
    let min: CGFloat
    let max: CGFloat
}

// MARK: - Tokens
struct LayoutTokens: Codable {
    let outerInsetPt: CGFloat
    let areaGapPt: CGFloat
    let panelPaddingPt: CGFloat
    let panelCornerRadiusPt: CGFloat
}

// MARK: - Card
struct CardConfigV2: Codable {
    let baseWidthRatio: CGFloat
    let minWidthPt: CGFloat
    let maxWidthPt: CGFloat
    let aspectRatio: CGFloat
    let cornerRadiusRatio: CGFloat
    let shadow: ShadowConfig
    let backColor: String
    let backCircleColor: String
    
    var backColorSwiftUI: Color { Color(hex: backColor) }
    var backCircleColorSwiftUI: Color { Color(hex: backCircleColor) }
}

struct ShadowConfig: Codable {
    let radiusPt: CGFloat
    let yOffsetPt: CGFloat
    let opacity: Double
}

// MARK: - Images
struct ImageConfigV2: Codable {
    let prefix: String
}

// MARK: - Areas
struct AreasConfigV2: Codable {
    let opponent: AreaSectionConfigV2
    let center: CenterSectionConfigV2 // Center area might differ slightly (no captured/hand)
    let player: AreaSectionConfigV2
}

// Use a generic config for Opponent/Player since they are very similar, 
// but Center has slightly different elements. 
// However, looking at JSON, they all have 'elements' dict.
// We can use a unified AreaSection structure and generic 'elements'
// OR specific structures per area. The JSON shows specific 'elements' structure for each.
// Let's use specific Element structs but shared AreaSection parent where possible?
// The 'elements' is a dictionary in JSON, but keys differ.
// Let's use specific structs for strict typing.

struct AreaSectionConfigV2: Codable {
    let heightRatio: CGFloat
    let minHeightPt: CGFloat
    let maxHeightPt: CGFloat
    let flexWeight: CGFloat
    let background: AreaBackgroundConfigV2
    let elements: OpponentPlayerElements // Shared for Opponent/Player for now, or split if needed
}

struct CenterSectionConfigV2: Codable {
    let heightRatio: CGFloat
    let minHeightPt: CGFloat
    let maxHeightPt: CGFloat
    let flexWeight: CGFloat
    let background: AreaBackgroundConfigV2
    let elements: CenterElements
}

struct AreaBackgroundConfigV2: Codable {
    let color: String
    let opacity: Double
    let cornerRadiusPt: CGFloat
    let widthRatio: CGFloat
    
    var colorSwiftUI: Color { Color(hex: color).opacity(opacity) }
}

// MARK: - Elements
struct OpponentPlayerElements: Codable {
    let hand: ElementHandConfig
    let captured: ElementCapturedConfig
}

struct CenterElements: Codable {
    let table: ElementTableConfig
    let deck: ElementDeckConfig
}

// Common Element Properties
protocol LayoutElement {
    var x: CGFloat { get }
    var y: CGFloat { get }
    var scale: CGFloat { get }
    var zIndex: Double { get }
}

struct ElementHandConfig: Codable, LayoutElement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    let grid: HandGridConfig
}

struct ElementCapturedConfig: Codable, LayoutElement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    let layout: CapturedLayoutConfigV2
}

struct ElementTableConfig: Codable, LayoutElement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    let grid: TableGridConfig
}

struct ElementDeckConfig: Codable, LayoutElement {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
}

// MARK: - Grids & Layouts
struct HandGridConfig: Codable {
    let rows: Int
    let maxCols: Int
    let vSpacingCardRatio: CGFloat? // Optional because opponent hand has 0
    let hSpacingCardRatio: CGFloat
    let background: AreaBackgroundConfigV2? // Player hand has bg
    let overlapRatio: CGFloat? // Opponent hand uses overlap
}

struct CapturedLayoutConfigV2: Codable {
    let groupSpacingCardRatio: CGFloat
    let cardOverlapRatio: CGFloat
}

struct TableGridConfig: Codable {
    let rows: Int
    let cols: Int
    let vSpacingCardRatio: CGFloat
    let hSpacingCardRatio: CGFloat
    let stackOverlapRatio: CGFloat
}
