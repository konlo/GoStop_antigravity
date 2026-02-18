import Foundation
import SwiftUI

// MARK: - Root Config
struct LayoutConfigV2: Codable, Equatable {
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
struct DebugConfigV2: Codable, Equatable {
    let showGrid: Bool
    let showSafeArea: Bool
    let showElementBounds: Bool
    let player: DebugPlayerConfig?
}

struct DebugPlayerConfig: Codable, Equatable {
    let handSlotGrid: Bool
    let sortedOrderOverlay: Bool
}

// MARK: - Reference & Scaling
struct ReferenceCanvasConfig: Codable, Equatable {
    let widthPt: CGFloat
    let heightPt: CGFloat
}

struct ScalingConfig: Codable, Equatable {
    let min: CGFloat
    let max: CGFloat
}

// MARK: - Tokens
struct LayoutTokens: Codable, Equatable {
    let outerInsetPt: CGFloat
    let areaGapPt: CGFloat
    let panelPaddingPt: CGFloat
    let panelCornerRadiusPt: CGFloat
    let safeAreaTopPaddingPt: CGFloat?
    let safeAreaBottomPaddingPt: CGFloat?
}

// MARK: - Card
struct CardConfigV2: Codable, Equatable {
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

struct ShadowConfig: Codable, Equatable {
    let radiusPt: CGFloat
    let yOffsetPt: CGFloat
    let opacity: Double
}

// MARK: - Images
struct ImageConfigV2: Codable, Equatable {
    let prefix: String
}

// MARK: - Areas
struct AreasConfigV2: Codable, Equatable {
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

struct AreaSectionConfigV2: Codable, Equatable {
    let heightRatio: CGFloat
    let minHeightPt: CGFloat
    let maxHeightPt: CGFloat
    let flexWeight: CGFloat
    let background: AreaBackgroundConfigV2
    let elements: OpponentPlayerElements // Shared for Opponent/Player for now, or split if needed
}

struct CenterSectionConfigV2: Codable, Equatable {
    let heightRatio: CGFloat
    let minHeightPt: CGFloat
    let maxHeightPt: CGFloat
    let flexWeight: CGFloat
    let background: AreaBackgroundConfigV2
    let elements: CenterElements
}

struct AreaBackgroundConfigV2: Codable, Equatable {
    let color: String
    let opacity: Double
    let cornerRadiusPt: CGFloat
    let widthRatio: CGFloat
    let paddingPt: CGFloat?
    
    var colorSwiftUI: Color { Color(hex: color).opacity(opacity) }
}

// MARK: - Elements
struct OpponentPlayerElements: Codable, Equatable {
    let hand: ElementHandConfig
    let captured: ElementCapturedConfig
}

struct CenterElements: Codable, Equatable {
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

struct ElementHandConfig: Codable, LayoutElement, Equatable {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    
    // Grid Mode (Optional in V2 fixedSlots)
    let grid: HandGridConfig?
    let layoutAlignment: String?
    let leadingAnchorXRatio: CGFloat?
    
    // Fixed Slots Mode
    let mode: String?
    let fixedSlots: HandFixedSlotsConfig?
    let slotPlacementPolicy: HandSlotPlacementPolicy?
    let slotConstraints: HandSlotConstraints?
    
    let sorting: HandSortingConfig?
}

struct HandFixedSlotsConfig: Codable, Equatable {
    let count: Int
    let slotIndexing: String?
    let slots: [HandFixedSlot]
}

struct HandFixedSlot: Codable, Equatable {
    let slotIndex: Int
    let row: Int
    let col: Int
    let anchorX: CGFloat
    let anchorY: CGFloat
    let maxCardScale: CGFloat
    let occupied: Bool
    let preserveOnRemove: Bool
}

struct HandSlotPlacementPolicy: Codable, Equatable {
    let preserveEmptySlots: Bool
    let preserveSlotCoordinates: Bool
    let assignmentOnSort: String?
    let occupiedSlotSequence: [Int]?
    let fillOnDraw: String?
}

struct HandSlotConstraints: Codable, Equatable {
    let slotOverlapAllowed: Bool
    let slotMinGapRatio: CGFloat
}

struct HandSortingConfig: Codable, Equatable {
    let enabled: Bool
    let primaryKey: String?
    let secondaryKey: String?
    let typeOrder: [String]? // "bright", "animal", "ribbon", "pi"
    let stableTieBreak: String? // "drawOrder" - implies using original index
    let produceSortedIndicesMapping: Bool?
    let sortedIndicesKey: String?
}

struct ElementCapturedConfig: Codable, LayoutElement, Equatable {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    let layout: CapturedLayoutConfigV2
}

struct ElementTableConfig: Codable, LayoutElement, Equatable {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
    let grid: TableGridConfig
    let slots: [TableSlotConfig]? 
    
    let mode: String?
    let fixedSlots: TableFixedSlotsConfig?
}

struct TableFixedSlotsConfig: Codable, Equatable {
    let slots: [TableFixedSlot]
    let fillPolicy: String?
}

struct TableFixedSlot: Codable, Equatable {
    let slotIndex: Int
    let anchorX: CGFloat
    let anchorY: CGFloat
    let preserveOnRemove: Bool
}

struct TableSlotConfig: Codable, Equatable {
    let slotIndex: Int
    let anchorXRatio: CGFloat
    let anchorYRatio: CGFloat
    let anchorXOffsetPt: CGFloat
    let anchorYOffsetPt: CGFloat
    let anchorXOffsetCardWidthMul: CGFloat
    let anchorYOffsetCardHeightMul: CGFloat
}

struct ElementDeckConfig: Codable, LayoutElement, Equatable {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let zIndex: Double
}

// MARK: - Grids & Layouts
struct HandGridConfig: Codable, Equatable {
    let rows: Int
    let maxCols: Int
    let vSpacingCardRatio: CGFloat? // Optional because opponent hand has 0
    let hSpacingCardRatio: CGFloat
    let background: AreaBackgroundConfigV2? // Player hand has bg
    let overlapRatio: CGFloat? // Opponent hand uses overlap
}

struct CapturedLayoutConfigV2: Codable, Equatable {
    let groupSpacingCardRatio: CGFloat
    let cardOverlapRatio: CGFloat
}

struct TableGridConfig: Codable, Equatable {
    let rows: Int
    let cols: Int
    let vSpacingCardRatio: CGFloat
    let hSpacingCardRatio: CGFloat
    let stackOverlapRatio: CGFloat
}
