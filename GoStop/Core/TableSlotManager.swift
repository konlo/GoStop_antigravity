import Foundation
import Combine

class TableSlotManager: ObservableObject {
    @Published var slots: [Int: TableSlotState] = [:]
    private let config: LayoutConfigV2
    
    struct TableSlotState {
        var card: Card? // Table slots hold a stack of cards in GoStop, but for fixed layout usually the *base* card determines position? 
        // Wait, GoStop table cards stack. If I have a stack of 3 cards, do they take 1 slot? YES.
        // So `card` here should probably be a list of cards, or verify if we are slotting *stacks*.
        // The user said "짝이 맞아서 획득한 곳으로 간다고 해도 그 위치는 빈 slot으로 유지해줘야 해".
        // This implies slots hold the cards.
        // In visual terms, a slot holds a *pile*.
        // So `cards: [Card]`? 
        // But `PlayerHandSlotManager` just had `Card?`. Player hand is 1 card per slot usually.
        // Table can have multiple cards per slot (e.g. 2 cards of same month, or 3).
        // Standard GoStop: Table has 12 locations (months).
        // If 2 cards of same month are on table -> they are stacked.
        // So a slot should hold `[Card]`.
        // However, `TableAreaV2` logic was grouping by month.
        // If we use fixed slots, we are *assigning* specific months to specific slots?
        // Or just assigning stacks to slots?
        // "Fill empty slots".
        // Use case:
        // 1. Initial deal: 8 cards.
        //    - Config says "fill from center".
        //    - We take the 8 cards. Group by month.
        //    - Assign each group to a slot.
        // 2. Play:
        //    - Match: Remove cards from slot. Slot becomes empty.
        //    - No Match: Add played card to table.
        //      - Does it go to new slot? Or join existing stack?
        //      - If it matches existing month (e.g. 3rd card), it joins that slot.
        //      - If it is new month, it goes to a *new* empty slot.
        
        var cards: [Card] = []
        var isOccupied: Bool { !cards.isEmpty }
    }
    
    init(config: LayoutConfigV2) {
        self.config = config
        self.initializeSlots()
    }
    
    private func initializeSlots() {
        guard let fixedSlots = config.areas.center.elements.table.fixedSlots else { return }
        for slot in fixedSlots.slots {
            self.slots[slot.slotIndex] = TableSlotState()
        }
    }
    
    func sync(with tableCards: [Card]) {
        // Group input cards by Month
        // In GoStop, cards on table are conceptually piles.
        // We need to map [Card] -> [Month: [Card]]
        
        let groups = Dictionary(grouping: tableCards, by: { $0.month })
        
        // Snapshot current slot state
        // Map: Month -> SlotIndex
        var existingMonths: [Month: Int] = [:]
        
        for (idx, state) in slots {
            if let first = state.cards.first {
                existingMonths[first.month] = idx
            }
        }
        
        // 1. Update existing slots / Remove cleared
        for (month, idx) in existingMonths {
            if let newCards = groups[month] {
                // Update cards in this slot
                var state = slots[idx]!
                state.cards = newCards
                slots[idx] = state
            } else {
                // Month gone (captured) -> Clear slot
                if var state = slots[idx] {
                    state.cards = [] // Empty
                    // User said "그 위치는 빈 slot으로 유지해줘야 해" -> implies we just clear it, we don't shift others.
                    slots[idx] = state
                }
            }
        }
        
        // 2. Assign new months to empty slots
        // Sort new months to be deterministic?
        let presentMonths = Set(existingMonths.keys)
        let incomingMonths = Set(groups.keys)
        let newMonths = incomingMonths.subtracting(presentMonths).sorted()
        
        if !newMonths.isEmpty {
            // Find empty slots
            // Sort empty slots by "centerOutwards" preference
            let emptySlots = getEmptySlotsSortedByPreference()
            
            var slotCursor = 0
            for month in newMonths {
                guard let cards = groups[month] else { continue }
                
                if slotCursor < emptySlots.count {
                    let slotIdx = emptySlots[slotCursor]
                    var state = slots[slotIdx]!
                    state.cards = cards
                    slots[slotIdx] = state
                    slotCursor += 1
                } else {
                    print("Warning: Table full (12 slots), cannot place month \(month)")
                }
            }
        }
    }
    
    private func getEmptySlotsSortedByPreference() -> [Int] {
        // Preference: Distance to Center (0.5, 0.5)
        // Deck is at 0.5, 0.5.
        // Get all empty slots
        let emptyIndices = slots.filter { !$0.value.isOccupied }.keys
        
        guard let fixedSlots = config.areas.center.elements.table.fixedSlots else { return Array(emptyIndices).sorted() }
        
        // Helper to get anchor for index
        func getAnchor(idx: Int) -> (x: CGFloat, y: CGFloat) {
            if let slot = fixedSlots.slots.first(where: { $0.slotIndex == idx }) {
                return (slot.anchorX, slot.anchorY)
            }
            return (0,0) // Should not happen
        }
        
        return emptyIndices.sorted { idx1, idx2 in
            let p1 = getAnchor(idx: idx1)
            let p2 = getAnchor(idx: idx2)
            
            // Dist sq to (0.5, 0.5)
            // Note: Use aspect ratio? "Coordinate space 0..1".
            // Visual distance depends on width/height ratio of area.
            // Area is 0.95 width, 0.35 height.
            // visualX = x * 0.95, visualY = y * 0.35.
            // Deck center (0.5, 0.5).
            
            let dx1 = (p1.x - 0.5) * 0.95
            let dy1 = (p1.y - 0.5) * 0.35
            let d1 = (dx1 * dx1) + (dy1 * dy1)
            
            let dx2 = (p2.x - 0.5) * 0.95
            let dy2 = (p2.y - 0.5) * 0.35
            let d2 = (dx2 * dx2) + (dy2 * dy2)
            
            if abs(d1 - d2) < 0.0001 {
                return idx1 < idx2 // Tie-break
            }
            return d1 < d2
        }
    }
    
    func cards(at index: Int) -> [Card] {
        return slots[index]?.cards ?? []
    }
}
