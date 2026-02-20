import Foundation
import SwiftUI
import Combine

class LayoutContext: ObservableObject {
    let config: LayoutConfigV2
    let globalScale: CGFloat
    let safeArea: CGRect
    
    // Calculated Properties
    let cardSize: CGSize
    let areaFrames: [AreaType: CGRect]
    let centerSlotFrames: [Int: CGRect]
    let playerHandSlotFrames: [Int: CGRect]
    let scaledTokens: ScaledTokens
    
    enum AreaType {
        case setting, opponent, center, player
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
        
        // 2. Pre-calculate Token Values
        let outerInset = config.tokens.outerInsetPt * gScale
        let areaGap = config.tokens.areaGapPt * gScale
        let panelPadding = config.tokens.panelPaddingPt * gScale
        let panelRadius = config.tokens.panelCornerRadiusPt * gScale
        let cardShadowR = config.card.shadow.radiusPt * gScale
        let cardShadowY = config.card.shadow.yOffsetPt * gScale
        let topPadding = (config.tokens.safeAreaTopPaddingPt ?? 0) * gScale
        let bottomPadding = (config.tokens.safeAreaBottomPaddingPt ?? 0) * gScale
        
        // 3. Calculate Area Frames (Heights)
        let hasSetting = config.areas.setting != nil
        let numGaps = hasSetting ? 3 : 2
        let totalGap = areaGap * CGFloat(numGaps)
        let availableHeight = safeAreaSize.height - (outerInset * 2) - totalGap - topPadding - bottomPadding
        
        func calculateHeight(_ ratio: CGFloat, _ minPt: CGFloat, _ maxPt: CGFloat) -> CGFloat {
            return max(minPt * gScale, min(availableHeight * ratio, maxPt * gScale))
        }
        
        var finalSettingH: CGFloat = 0
        if let settingConfig = config.areas.setting {
            finalSettingH = calculateHeight(settingConfig.heightRatio, settingConfig.minHeightPt, settingConfig.maxHeightPt)
        }
        var finalOpponentH = calculateHeight(config.areas.opponent.heightRatio, config.areas.opponent.minHeightPt, config.areas.opponent.maxHeightPt)
        var finalCenterH = calculateHeight(config.areas.center.heightRatio, config.areas.center.minHeightPt, config.areas.center.maxHeightPt)
        var finalPlayerH = calculateHeight(config.areas.player.heightRatio, config.areas.player.minHeightPt, config.areas.player.maxHeightPt)
        
        // Distribute Remaining (Flex)
        let currentTotal = finalSettingH + finalOpponentH + finalCenterH + finalPlayerH
        let diff = availableHeight - currentTotal
        if abs(diff) > 1 {
            let setFlex = config.areas.setting?.flexWeight ?? 0
            let oppFlex = config.areas.opponent.flexWeight
            let cenFlex = config.areas.center.flexWeight
            let plaFlex = config.areas.player.flexWeight
            let totalFlex = setFlex + oppFlex + cenFlex + plaFlex
            
            if totalFlex > 0 {
                finalSettingH += diff * (setFlex / totalFlex)
                finalOpponentH += diff * (oppFlex / totalFlex)
                finalCenterH += diff * (cenFlex / totalFlex)
                finalPlayerH += diff * (plaFlex / totalFlex)
            }
        }
        
        let x = outerInset
        var currentY = outerInset + topPadding
        let w = safeAreaSize.width - (outerInset * 2)
        
        var areaDict = [AreaType: CGRect]()
        
        if finalSettingH > 0 {
            let setFrame = CGRect(x: x, y: currentY, width: w, height: finalSettingH)
            areaDict[.setting] = setFrame
            currentY += finalSettingH + areaGap
        }
        
        let oppFrame = CGRect(x: x, y: currentY, width: w, height: finalOpponentH)
        areaDict[.opponent] = oppFrame
        currentY += finalOpponentH + areaGap
        
        let cenFrame = CGRect(x: x, y: currentY, width: w, height: finalCenterH)
        areaDict[.center] = cenFrame
        currentY += finalCenterH + areaGap
        
        let plaFrame = CGRect(x: x, y: currentY, width: w, height: finalPlayerH)
        areaDict[.player] = plaFrame
        
        self.areaFrames = areaDict
        
        // 4. Calculate Card Size
        let baseWidth = safeAreaSize.width * config.card.baseWidthRatio
        // Logic for max width
        let hSpacingRatio = config.areas.player.elements.hand.grid?.hSpacingCardRatio ?? 0.08
        let sidePadding = panelPadding * 2
        let outerMargins = outerInset * 2
        let availableWidth = safeAreaSize.width - outerMargins - sidePadding
        let widthFactor = 5.0 + (4.0 * hSpacingRatio)
        let maxHandFitWidth = availableWidth / widthFactor
        
        let minPt = config.card.minWidthPt * gScale
        let maxPt = config.card.maxWidthPt * gScale
        var finalWidth = max(minPt, min(baseWidth, maxHandFitWidth))
        finalWidth = min(finalWidth, maxPt)
        
        self.cardSize = CGSize(width: finalWidth, height: finalWidth * config.card.aspectRatio)
        
        // 5. Final Tokens
        self.scaledTokens = ScaledTokens(
            outerInset: outerInset, areaGap: areaGap, panelPadding: panelPadding,
            panelCornerRadius: panelRadius, cardCornerRadius: finalWidth * config.card.cornerRadiusRatio,
            cardShadowRadius: cardShadowR, cardShadowY: cardShadowY
        )
        
        // 6. Calculate Center Slot Frames
        var centerSlots: [Int: CGRect] = [:]
        let tableConfig = config.areas.center.elements.table
        
        if let fixedSlots = tableConfig.fixedSlots {
             let cardW = self.cardSize.width * tableConfig.scale
             let cardH = self.cardSize.height * tableConfig.scale
             
             // Fixed slots are relative to Center Area Frame
             for slot in fixedSlots.slots {
                 let sX = cenFrame.minX + (cenFrame.width * slot.anchorX)
                 let sY = cenFrame.minY + (cenFrame.height * slot.anchorY)
                 centerSlots[slot.slotIndex] = CGRect(x: sX - cardW/2, y: sY - cardH/2, width: cardW, height: cardH)
             }
        } else if let slots = tableConfig.slots {
            let curCW = self.cardSize.width
            let curCH = self.cardSize.height
            for slot in slots {
                // Priority logic from JSON desc
                let offX = slot.anchorXOffsetCardWidthMul != 0 ? slot.anchorXOffsetCardWidthMul * curCW : slot.anchorXOffsetPt * gScale
                let offY = slot.anchorYOffsetCardHeightMul != 0 ? slot.anchorYOffsetCardHeightMul * curCH : slot.anchorYOffsetPt * gScale
                
                let localX = cenFrame.width * slot.anchorXRatio + offX
                let localY = cenFrame.height * slot.anchorYRatio + offY
                
                centerSlots[slot.slotIndex] = CGRect(x: cenFrame.minX + localX - (curCW/2), y: cenFrame.minY + localY - (curCH/2), width: curCW, height: curCH)
            }
        }
        self.centerSlotFrames = centerSlots
        
        // 7. Calculate Player Hand Slot Frames (V2 Fixed)
        var handSlots: [Int: CGRect] = [:]
        let pHand = config.areas.player.elements.hand
        if pHand.mode == "fixedSlots10", let fSlots = pHand.fixedSlots {
             // Container Calculation
             let bgRatio = pHand.grid?.background?.widthRatio ?? 0.94
             let containerW = plaFrame.width * bgRatio
             
             let cardW = self.cardSize.width * pHand.scale
             let cardH = self.cardSize.height * pHand.scale
             let rows = pHand.grid?.rows ?? 2 // Default 2
             let vSpace = cardH * (pHand.grid?.vSpacingCardRatio ?? 0.08)
             let padding = (pHand.grid?.background?.paddingPt ?? 10) * gScale
             
             let contentH = (CGFloat(rows) * cardH) + (CGFloat(max(0, rows - 1)) * vSpace)
             let containerH = contentH + (padding * 2)
             
             // Center Container in Player Frame
             let cX = plaFrame.minX + (plaFrame.width * pHand.x)
             let cY = plaFrame.minY + (plaFrame.height * pHand.y)
             
             let containerRect = CGRect(
                x: cX - containerW/2,
                y: cY - containerH/2,
                width: containerW,
                height: containerH
             )
             
             for slot in fSlots.slots {
                 let sX = containerRect.minX + (containerRect.width * slot.anchorX)
                 let sY = containerRect.minY + (containerRect.height * slot.anchorY)
                 
                 handSlots[slot.slotIndex] = CGRect(x: sX - cardW/2, y: sY - cardH/2, width: cardW, height: cardH)
             }
        }
        self.playerHandSlotFrames = handSlots
    }
    
    func frame(for area: AreaType) -> CGRect {
        return areaFrames[area] ?? .zero
    }
}


