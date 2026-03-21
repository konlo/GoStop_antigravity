import Foundation
import Combine

class PlayerHandSlotManager: ObservableObject {
    @Published var slots: [Int: HandSlotState] = [:]
    private let config: LayoutConfigV2
    private let orderedSlotIndices: [Int]
    
    struct HandSlotState: Equatable {
        var card: Card?
        var isOccupied: Bool
    }
    
    init(config: LayoutConfigV2) {
        self.config = config
        self.orderedSlotIndices = config.areas.player.elements.hand.fixedSlots?.slots.map(\.slotIndex).sorted() ?? []
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

    private var slotIndicesInOrder: [Int] {
        orderedSlotIndices.isEmpty ? slots.keys.sorted() : orderedSlotIndices
    }
    
    func sync(with hand: [Card], compactToFront: Bool = true) {
        let sortedHand = hand.sorted(by: sortComparator)
        var nextSlots = slots
        
        if !preserveEmptySlots {
            if compactToFront {
                for key in slotIndicesInOrder {
                    if var state = nextSlots[key] {
                        state.card = nil
                        state.isOccupied = false
                        nextSlots[key] = state
                    }
                }
                
                for (i, card) in sortedHand.enumerated() where i < slotIndicesInOrder.count {
                    let idx = slotIndicesInOrder[i]
                    if var state = nextSlots[idx] {
                        state.card = card
                        state.isOccupied = true
                        nextSlots[idx] = state
                    }
                }
                assignSlotsIfNeeded(nextSlots)
                return
            }

            var existingCards: [String: Int] = [:] // CardID -> SlotIndex
            for (idx, state) in nextSlots {
                if let c = state.card {
                    existingCards[c.id] = idx
                }
            }
            
            let incomingById = Dictionary(uniqueKeysWithValues: sortedHand.map { ($0.id, $0) })
            let incomingIds = Set(incomingById.keys)
            
            // 1) Remove cards that are no longer in hand
            for (id, idx) in existingCards where !incomingIds.contains(id) {
                if var state = nextSlots[idx] {
                    state.card = nil
                    state.isOccupied = false
                    nextSlots[idx] = state
                }
            }
            
            // 2) Refresh existing cards in-place (selectedRole/type updates, etc.)
            for (id, idx) in existingCards {
                if let updated = incomingById[id], var state = nextSlots[idx] {
                    state.card = updated
                    state.isOccupied = true
                    nextSlots[idx] = state
                }
            }
            
            // 3) Place newly added cards into the first empty slots in sorted order
            for card in sortedHand where existingCards[card.id] == nil {
                if let emptyIdx = findFirstEmptySlot(in: nextSlots), var state = nextSlots[emptyIdx] {
                    state.card = card
                    state.isOccupied = true
                    nextSlots[emptyIdx] = state
                } else {
                    print("Warning: Hand Full, could not add card \(card)")
                }
            }
            assignSlotsIfNeeded(nextSlots)
            return
        }

        var existingCards: [String: Int] = [:]
        for (idx, state) in nextSlots {
            if let c = state.card {
                existingCards[c.id] = idx
            }
        }
        
        let newCardIDs = Set(hand.map { $0.id })
        
        // 1. Remove Missing Cards
        for (id, idx) in existingCards {
            if !newCardIDs.contains(id) {
                if var state = nextSlots[idx] {
                    state.card = nil
                    state.isOccupied = false
                    nextSlots[idx] = state
                }
            }
        }
        
        // 2. Add New Cards
        for card in sortedHand {
            if existingCards[card.id] == nil {
                if let emptyIdx = findFirstEmptySlot(in: nextSlots) {
                    var state = nextSlots[emptyIdx]!
                    state.card = card
                    state.isOccupied = true
                    nextSlots[emptyIdx] = state
                } else {
                    print("Warning: Hand Full, could not add card \(card)")
                }
            }
        }

        for (id, idx) in existingCards {
            if let updated = sortedHand.first(where: { $0.id == id }), var state = nextSlots[idx] {
                state.card = updated
                state.isOccupied = true
                nextSlots[idx] = state
            }
        }

        assignSlotsIfNeeded(nextSlots)
    }
    
    private func findFirstEmptySlot(in slotMap: [Int: HandSlotState]) -> Int? {
        for idx in slotIndicesInOrder {
            if let state = slotMap[idx], !state.isOccupied {
                return idx
            }
        }
        return nil
    }
    
    func card(at index: Int) -> Card? {
        return slots[index]?.card
    }
    
    func sort() {
        let cards = slots.values.compactMap { $0.card }
        
        let sortedCards = cards.sorted(by: sortComparator)
        var nextSlots = slots
        
        if !preserveEmptySlots {
            for key in slotIndicesInOrder {
                nextSlots[key]?.card = nil
                nextSlots[key]?.isOccupied = false
            }
            
            for (i, card) in sortedCards.enumerated() {
                if i < slotIndicesInOrder.count {
                    let idx = slotIndicesInOrder[i]
                    var state = nextSlots[idx]!
                    state.card = card
                    state.isOccupied = true
                    nextSlots[idx] = state
                }
            }
        } else {
            let occupiedSlots = slots.compactMap { (key, state) -> Int? in
                return state.isOccupied ? key : nil
            }.sorted()
            
            for (i, card) in sortedCards.enumerated() {
                if i < occupiedSlots.count {
                    let slotIdx = occupiedSlots[i]
                    if var state = nextSlots[slotIdx] {
                        state.card = card
                        state.isOccupied = true
                        nextSlots[slotIdx] = state
                    }
                }
            }
        }

        assignSlotsIfNeeded(nextSlots)
    }
    
    private func assignSlotsIfNeeded(_ nextSlots: [Int: HandSlotState]) {
        guard nextSlots != slots else { return }
        slots = nextSlots
    }

    private func sortComparator(_ lhs: Card, _ rhs: Card) -> Bool {
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        if lhs.type != rhs.type { return typePriority(lhs.type) < typePriority(rhs.type) }
        if lhs.imageIndex != rhs.imageIndex { return lhs.imageIndex < rhs.imageIndex }
        return lhs.id < rhs.id
    }

    private func typePriority(_ type: CardType) -> Int {
        switch type {
        case .bright: return 0
        case .animal: return 1
        case .ribbon: return 2
        case .junk, .doubleJunk: return 3
        case .dummy: return 4
        }
    }
}
