import Foundation
import SwiftUI

class LayoutContext: ObservableObject {
    let config: LayoutConfigV2
    let globalScale: CGFloat
    let safeArea: CGRect
    
    // Calculated Properties
    let cardSize: CGSize
    let areaFrames: [AreaType: CGRect]
    let scaledTokens: ScaledTokens
    
    enum AreaType {
        case opponent, center, player
    }
    
    struct ScaledTokens {
        let outerInset: CGFloat
        let areaGap: CGFloat
        let panelPadding: CGFloat
        let panelCornerRadius: CGFloat
        let cardCornerRadius: CGFloat
        let cardShadowRadius: CGFloat
        let cardShadowY: CGFloat
    }
    
    init(config: LayoutConfigV2, safeAreaSize: CGSize) {
        self.config = config
        
        // 1. Calculate Global Scale
        let refW = config.referenceCanvas.widthPt
        let refH = config.referenceCanvas.heightPt
        
        let scaleW = safeAreaSize.width / refW
        let scaleH = safeAreaSize.height / refH
        let rawScale = min(scaleW, scaleH)
        
        let gScale = min(max(rawScale, config.scaling.min), config.scaling.max)
        self.globalScale = gScale
        self.safeArea = CGRect(origin: .zero, size: safeAreaSize)
        
        // 2. Pre-calculate Token Values (Locals)
        let outerInset = config.tokens.outerInsetPt * gScale
        let areaGap = config.tokens.areaGapPt * gScale
        let panelPadding = config.tokens.panelPaddingPt * gScale
        let panelRadius = config.tokens.panelCornerRadiusPt * gScale
        let cardShadowR = config.card.shadow.radiusPt * gScale
        let cardShadowY = config.card.shadow.yOffsetPt * gScale
        let topPadding = (config.tokens.safeAreaTopPaddingPt ?? 0) * gScale
        let bottomPadding = (config.tokens.safeAreaBottomPaddingPt ?? 0) * gScale
        
        // 3. Calculate Card Size (Hand-Fit Logic)
        let baseWidth = safeAreaSize.width * config.card.baseWidthRatio
        
        let hSpacingRatio = config.areas.player.elements.hand.grid.hSpacingCardRatio
        let sidePadding = panelPadding * 2
        let outerMargins = outerInset * 2
        
        let availableWidth = safeAreaSize.width - outerMargins - sidePadding
        let widthFactor = 5.0 + (4.0 * hSpacingRatio)
        
        let maxHandFitWidth = availableWidth / widthFactor
        
        // Min/Max Pt Constraints
        let minPt = config.card.minWidthPt * gScale
        let maxPt = config.card.maxWidthPt * gScale
        
        // Final Width
        var finalWidth = min(baseWidth, maxHandFitWidth)
        finalWidth = max(minPt, min(finalWidth, maxPt))
        
        self.cardSize = CGSize(width: finalWidth, height: finalWidth * config.card.aspectRatio)
        
        // 4. Final Tokens Assignment
        self.scaledTokens = ScaledTokens(
            outerInset: outerInset,
            areaGap: areaGap,
            panelPadding: panelPadding,
            panelCornerRadius: panelRadius,
            cardCornerRadius: finalWidth * config.card.cornerRadiusRatio,
            cardShadowRadius: cardShadowR,
            cardShadowY: cardShadowY
        )
        
        // 5. Calculate Area Frames (Vertical Distribution)
        let totalGap = areaGap * 2
        // Available height must account for top padding extra shift
        let availableHeight = safeAreaSize.height - (outerInset * 2) - totalGap - topPadding - bottomPadding
        
        // Calculate Target Heights
        let opponentH = availableHeight * config.areas.opponent.heightRatio
        let centerH = availableHeight * config.areas.center.heightRatio
        let playerH = availableHeight * config.areas.player.heightRatio
        
        // Clamp Closure
        let clampHeight = { (h: CGFloat, minPt: CGFloat, maxPt: CGFloat) -> CGFloat in
            return max(minPt * gScale, min(h, maxPt * gScale))
        }
        
        var finalOpponentH = clampHeight(opponentH, config.areas.opponent.minHeightPt, config.areas.opponent.maxHeightPt)
        var finalCenterH = clampHeight(centerH, config.areas.center.minHeightPt, config.areas.center.maxHeightPt)
        var finalPlayerH = clampHeight(playerH, config.areas.player.minHeightPt, config.areas.player.maxHeightPt)
        
        // Distribute Remaining Space (Flex)
        let currentTotal = finalOpponentH + finalCenterH + finalPlayerH
        let diff = availableHeight - currentTotal
        
        if abs(diff) > 1 {
            let totalFlex = config.areas.opponent.flexWeight + config.areas.center.flexWeight + config.areas.player.flexWeight
            if totalFlex > 0 {
                finalOpponentH += diff * (config.areas.opponent.flexWeight / totalFlex)
                finalCenterH += diff * (config.areas.center.flexWeight / totalFlex)
                finalPlayerH += diff * (config.areas.player.flexWeight / totalFlex)
            }
        }
        
        // Assign Frames
        let x = outerInset
        // Start Y is shifted down by topPadding
        let yStart = outerInset + topPadding
        let w = safeAreaSize.width - (outerInset * 2)
        
        self.areaFrames = [
            .opponent: CGRect(x: x, y: yStart, width: w, height: finalOpponentH),
            .center: CGRect(x: x, y: yStart + finalOpponentH + areaGap, width: w, height: finalCenterH),
            .player: CGRect(x: x, y: yStart + finalOpponentH + areaGap + finalCenterH + areaGap, width: w, height: finalPlayerH)
        ]
    }
    
    // Helper to get frame for any area
    func frame(for area: AreaType) -> CGRect {
        return areaFrames[area] ?? .zero
    }
}
