import Foundation
import Combine

class PlayerHandSlotManager: ObservableObject {
    @Published var slots: [Int: HandSlotState] = [:]
    private let config: LayoutConfigV2
    
    struct HandSlotState {
        var card: Card?
        var isOccupied: Bool
    }
    
    init(config: LayoutConfigV2) {
        self.config = config
        self.initializeSlots()
    }
    
    private func initializeSlots() {
        guard let fixedSlots = config.areas.player.elements.hand.fixedSlots else { return }
        for slot in fixedSlots.slots {
            self.slots[slot.slotIndex] = HandSlotState(card: nil, isOccupied: false)
        }
    }
    
    private var preserveEmptySlots: Bool {
        return config.areas.player.elements.hand.slotPlacementPolicy?.preserveEmptySlots ?? true
    }
    
    func sync(with hand: [Card]) {
        // Sort hand based on user criteria: Month -> Type
        let sortedHand = hand.sorted { lhs, rhs in
            if lhs.month != rhs.month { return lhs.month < rhs.month }
            return typePriority(lhs.type) < typePriority(rhs.type)
        }
        
        if !preserveEmptySlots {
            // Compaction: Fill slots 1..N sequentially
            // 1. Clear all
            for key in slots.keys {
                slots[key]?.card = nil
                slots[key]?.isOccupied = false
            }
            
            // 2. Assign Sorted Hand
            let sortedKeys = slots.keys.sorted()
            for (i, card) in sortedHand.enumerated() {
                if i < sortedKeys.count {
                    let idx = sortedKeys[i]
                    var state = slots[idx]!
                    state.card = card
                    state.isOccupied = true
                    slots[idx] = state
                }
            }
            return
        }
        
        // Snapshot current card locations
        var existingCards: [UUID: Int] = [:] // CardID -> SlotIndex
        
        for (idx, state) in slots {
            if let c = state.card {
                existingCards[c.id] = idx
            }
        }
        
        let newCardIDs = Set(hand.map { $0.id })
        
        // 1. Remove Missing Cards
        for (id, idx) in existingCards {
            if !newCardIDs.contains(id) {
                if var state = slots[idx] {
                    state.card = nil
                    state.isOccupied = false
                    slots[idx] = state
                }
            }
        }
        
        // 2. Add New Cards
        for card in hand {
            if existingCards[card.id] == nil {
                if let emptyIdx = findFirstEmptySlot() {
                    var state = slots[emptyIdx]!
                    state.card = card
                    state.isOccupied = true
                    slots[emptyIdx] = state
                } else {
                    print("Warning: Hand Full, could not add card \(card)")
                }
            }
        }
    }
    
    private func findFirstEmptySlot() -> Int? {
        let sortedKeys = slots.keys.sorted()
        for idx in sortedKeys {
            if let state = slots[idx], !state.isOccupied {
                return idx
            }
        }
        return nil
    }
    
    func card(at index: Int) -> Card? {
        return slots[index]?.card
    }
    
    func sort() {
        // Collect cards from all slots
        let cards = slots.values.compactMap { $0.card }
        
        let sortedCards = cards.sorted { lhs, rhs in
            if lhs.month != rhs.month { return lhs.month < rhs.month }
            if lhs.type != rhs.type { return typePriority(lhs.type) < typePriority(rhs.type) }
            return false 
        }
        
        if !preserveEmptySlots {
            // Compaction: Re-assign to slots 1..N
            // 1. Clear all
            for key in slots.keys {
                slots[key]?.card = nil
                slots[key]?.isOccupied = false
            }
            
            // 2. Assign
            let sortedKeys = slots.keys.sorted()
            for (i, card) in sortedCards.enumerated() {
                if i < sortedKeys.count {
                    let idx = sortedKeys[i]
                    var state = slots[idx]!
                    state.card = card
                    state.isOccupied = true
                    slots[idx] = state
                }
            }
        } else {
            // Preserve Empty: Re-assign only to originally occupied slots
            let occupiedSlots = slots.compactMap { (key, state) -> Int? in
                return state.isOccupied ? key : nil
            }.sorted()
            
            for (i, card) in sortedCards.enumerated() {
                if i < occupiedSlots.count {
                    let slotIdx = occupiedSlots[i]
                    if var state = slots[slotIdx] {
                        state.card = card
                        state.isOccupied = true
                        slots[slotIdx] = state
                    }
                }
            }
        }
    }
    
    private func typePriority(_ type: CardType) -> Int {
        switch type {
        case .bright: return 0
        case .animal: return 1
        case .ribbon: return 2
        case .junk, .doubleJunk: return 3
        }
    }
}
