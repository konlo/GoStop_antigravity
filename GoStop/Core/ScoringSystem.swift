import Foundation

struct ScoringSystem {
    
    static func calculateScore(for player: Player) -> Int {
        var score = 0
        let cards = player.capturedCards
        
        // 1. Brights (Gwang)
        let brights = cards.filter { $0.type == .bright }
        let brightCount = brights.count
        
        if brightCount == 5 {
            score += 15 // 5 Gwang
        } else if brightCount == 4 {
            score += 4 // 4 Gwang
        } else if brightCount == 3 {
            // Check for Rain Gwang (December)
            let hasRainGwang = brights.contains { $0.month == .dec }
            if hasRainGwang {
                score += 2 // 2 Gwang + Rain (Bi-Gwang) -> 2pts
            } else {
                score += 3 // 3 Gwang (No Rain) -> 3pts
            }
        }
        
        // 2. Animals (Yul)
        let animals = cards.filter { $0.type == .animal }
        let animalCount = animals.count
        
        if animalCount >= 5 {
            score += (animalCount - 4) // 5->1pt, 6->2pts...
        }
        
        // Godori (5 Birds)
        let godoriCards = animals.filter { $0.isBird } 
        // Note: isBird in Card.swift handles Feb, Apr, Aug. 
        // We need to ensure we have exactly the 3 specific birds for Godori (Feb, Apr, Aug).
        // Let's verify Card.swift implementation or handle it here.
        // Assuming Card.swift isBird is correct for Godori components.
        let godoriCount = godoriCards.filter { $0.month == .feb || $0.month == .apr || $0.month == .aug }.count
        if godoriCount == 3 {
             score += 5
        }
        
        // 3. Ribbons (Tti)
        let ribbons = cards.filter { $0.type == .ribbon }
        let ribbonCount = ribbons.count
        
        if ribbonCount >= 5 {
            score += (ribbonCount - 4) // 5->1pt, 6->2pts...
        }
        
        // Specific Ribbons
        let redPoetry = ribbons.filter { $0.month == .jan || $0.month == .feb || $0.month == .mar }.count
        if redPoetry == 3 { score += 3 } // Hongdan
        
        let blueRibbons = ribbons.filter { $0.month == .jun || $0.month == .sep || $0.month == .oct }.count
        if blueRibbons == 3 { score += 3 } // Chongdan
        
        let redGrass = ribbons.filter { $0.month == .apr || $0.month == .may || $0.month == .jul }.count
        if redGrass == 3 { score += 3 } // Chodan
        
        // 4. Junk (Pi)
        var junkCount = 0
        for card in cards {
            if card.type == .junk {
                junkCount += 1
            } else if card.type == .doubleJunk {
                junkCount += 2
            }
        }
        
        if junkCount >= 10 {
            score += (junkCount - 9) // 10->1pt, 11->2pts...
        }
        
        return score
    }
}
