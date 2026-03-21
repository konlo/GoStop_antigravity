import Foundation
import Combine

class TableSlotManager: ObservableObject {
    @Published var slots: [Int: TableSlotState] = [:]
    private let config: LayoutConfigV2
    private let emptySlotPreferenceOrder: [Int]
    
    struct TableSlotState: Equatable {
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
        self.emptySlotPreferenceOrder = Self.makeEmptySlotPreferenceOrder(config: config)
        self.initializeSlots()
    }
    
    private func initializeSlots() {
        guard let fixedSlots = config.areas.center.elements.table.fixedSlots else { return }
        for slot in fixedSlots.slots {
            self.slots[slot.slotIndex] = TableSlotState()
        }
    }
    
    func sync(with tableCards: [Card]) {
        let groups = Dictionary(grouping: tableCards, by: { $0.month }).mapValues { cards in
            cards.sorted(by: sortComparator)
        }
        var nextSlots = slots
        var existingMonths: [Month: Int] = [:]
        
        for (idx, state) in nextSlots {
            if let first = state.cards.first {
                existingMonths[first.month] = idx
            }
        }
        
        for (month, idx) in existingMonths {
            if let newCards = groups[month] {
                var state = nextSlots[idx]!
                state.cards = newCards
                nextSlots[idx] = state
            } else {
                if var state = nextSlots[idx] {
                    state.cards = []
                    nextSlots[idx] = state
                }
            }
        }
        
        let presentMonths = Set(existingMonths.keys)
        let incomingMonths = Set(groups.keys)
        let newMonths = incomingMonths.subtracting(presentMonths).sorted()
        
        if !newMonths.isEmpty {
            let emptySlots = getEmptySlotsSortedByPreference(in: nextSlots)
            
            var slotCursor = 0
            for month in newMonths {
                guard let cards = groups[month] else { continue }
                
                if slotCursor < emptySlots.count {
                    let slotIdx = emptySlots[slotCursor]
                    var state = nextSlots[slotIdx]!
                    state.cards = cards
                    nextSlots[slotIdx] = state
                    slotCursor += 1
                } else {
                    print("Warning: Table full (12 slots), cannot place month \(month)")
                }
            }
        }

        assignSlotsIfNeeded(nextSlots)
    }
    
    private func getEmptySlotsSortedByPreference(in slotMap: [Int: TableSlotState]) -> [Int] {
        if !emptySlotPreferenceOrder.isEmpty {
            return emptySlotPreferenceOrder.filter { slotMap[$0]?.isOccupied == false }
        }
        return slotMap.compactMap { !$0.value.isOccupied ? $0.key : nil }.sorted()
    }
    
    func cards(at index: Int) -> [Card] {
        return slots[index]?.cards ?? []
    }

    private func assignSlotsIfNeeded(_ nextSlots: [Int: TableSlotState]) {
        guard nextSlots != slots else { return }
        slots = nextSlots
    }

    private func sortComparator(_ lhs: Card, _ rhs: Card) -> Bool {
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        if lhs.imageIndex != rhs.imageIndex { return lhs.imageIndex < rhs.imageIndex }
        if lhs.type != rhs.type { return typePriority(lhs.type) < typePriority(rhs.type) }
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

    private static func makeEmptySlotPreferenceOrder(config: LayoutConfigV2) -> [Int] {
        guard let fixedSlots = config.areas.center.elements.table.fixedSlots else { return [] }

        return fixedSlots.slots
            .map { slot in
                let dx = (slot.anchorX - 0.5) * 0.95
                let dy = (slot.anchorY - 0.5) * 0.35
                let distance = (dx * dx) + (dy * dy)
                return (slot.slotIndex, distance)
            }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) < 0.0001 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 < rhs.1
            }
            .map(\.0)
    }
}
