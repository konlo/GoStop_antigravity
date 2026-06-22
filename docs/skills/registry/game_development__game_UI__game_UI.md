<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/game_development/game_UI/SKILL.md
Source group: registry
Skill name: game_UI
Original relative directory: game_development/game_UI
-->

---
skill: game_UI
version: 3.0
type: ux_design
domain: game_development
blocking: true
runs_after:
  - game_planning
runs_before:
  - ui_implementation
  - animation_design
  - interaction_binding
guarantees:
  - action_focused_ui
  - fast_iteration_ux
  - non_intrusive_game_experience
  - strict_logic_ui_separation
  - slot_based_layout
---

# 🎮 game_UI — SKILL (v3.0 - General)

## Purpose

This skill defines the **UX-first UI blueprint** for any interactive game or application. It strictly enforces the separation of **Logical State (Engine/Model)** and **Visual Representation (View/UI)** to prevent layout bugs, off-screen elements, and resolution dependency.

It ensures that:
- UI adapts to any screen size or aspect ratio automatically.
- Every state change triggers a deterministic visual update.
- Animations clarify intent (State A → State B) without "magic numbers."
- UI/UX can be iterated **without rebuilding core logic.**

> **Rule:**  
> The Logic Model calculates *what* happens; the UI Layer calculates *where* it happens.

---

## 🛑 Critical Architecture Rule: Slot-Based Layout

To prevent elements from drifting, overlapping, or breaking on different devices, the following rule is absolute:

> **The Game/App Logic must NEVER know about screen coordinates (x, y).**
> **The UI must NEVER calculate game state.**

### ❌ The Old (Broken) Way
1. Logic says: "Move item to (300, 500)"
2. UI animates to (300, 500)
3. Screen resizes or Safe Area changes → Item is now floating in void 💥

### ✅ The New (Robust) Way: Slot System
1. **Logic Model** assigns a **Logical Slot Index** to the entity.
   - `state: equipped`
   - `owner: player_1`
   - `slotIndex: 5`
2. **UI Layer** (LayoutManager) maps logical index to screen geometry.
   - `slotIndex(5) → CGRect(x: 50, y: 100, w: 60, h: 60)`
3. **Animation** moves from `Old Slot → New Slot`.
4. If screen resizes, `LayoutManager` recalculates the rects. The entity snaps to the new valid position.

---

## 🏗 Mandatory Structural Components

### 1. View Layout Manager (UI Side)

You MUST implement a dedicated manager for calculating slot positions. Feature code should never calculate frames manually.

```swift
struct LayoutSlot {
    let index: Int
    let section: SectionID // e.g., Inventory, Board, Hand
    let rect: CGRect       // Calculated based on current SafeArea & Screen Size
}

// Global or Environment Object
class ViewLayoutManager {
    func rectForSlot(index: Int, section: SectionID, screenSize: CGSize) -> CGRect {
        // ... centralized layout logic ...
        // e.g., return grid calculation
    }
}
```

### 2. Logic Data Structure

The model's representation of an entity must be purely logical.

```swift
struct EntityState {
    let id: EntityID
    let ownerID: PlayerID?
    let section: SectionID   // e.g., Deck, Field, Discard
    let slotIndex: Int?      // 0..N (The only positional data logic knows)
}
```

---

## 🎨 Animation & Layout Rules

### 1. No "Mid-Air" Correction
- Animations are simply transitions between two valid states (Slot A → Slot B).
- Do not add "fudge factors" or manual offsets during animation.
- If the destination changes (e.g., re-layout), the animation target updates to the new slot rect.

### 2. Constraint & Padding Enforcement
- **Safe Area:** All slots must be calculated within the Safe Area.
- **Padding:** A minimum padding from the screen edge is mandatory.
- **Overflow Strategy:** Define explicit rules for when slots exceed available space:
    - **Stacking:** Overlap items by X%.
    - **Scaling:** Shrink items to fit.
    - **Scroll:** Add a scroll view or pagination.
    - **Wrap:** Move to next row/column.

*Do not leave overflow behavior undefined.*

### 3. Coordinate Calculation
- **ONLY** in `ViewLayoutManager` (or `LayoutPass`).
- **NEVER** in View `body` or `init`.
- **NEVER** in Business Logic.

---

## 🔄 Visual Handover & Animation Continuity

To prevent "teleporting" or "flickering" (where an item disappears and reappears at a new location), the following rules apply:

### 1. The Handover Rule
When an entity moves between two logical sections (e.g., Board → Player Area):
- The **Visual Component** must not be destroyed and recreated.
- The **Animation's Start Position** MUST be the exact current visual coordinate of the entity *before* the logic update.
- If the section change involves a parent view switch, use a **Global Overlay** or `matchedGeometryEffect` to maintain visual continuity.

### 2. Start-Position Integrity
- Never assume an item starts at `(0,0)` of a new slot.
- Always capture the `rect` of the **Source Slot** before beginning the transition to the **Destination Slot**.
- The transition must be a single, uninterrupted path from `Source.rect.center` to `Destination.rect.center`.

### 3. State-Animation Sync
- If a state change occurs *during* an existing animation, the new animation must start from the **Current Mid-Air Position**, not the original start or the previous target.

---

## Required UX Questions (MANDATORY)

This skill must explicitly answer and document:

### 1. Primary User Actions
- What is the most common interaction? (e.g., Tap, Drag, Swipe)
- What interaction ends a session or turn?
👉 UI must be optimized for these specific actions.

### 2. Visual Focus Hierarchy
- **Primary Focus:** What must always be visible? (e.g., The Board, The Avatar)
- **Secondary Focus:** Contextual info? (e.g., Hand, Score)
- **Tertiary UI:** Meta info? (e.g., Settings, Chat)

### 3. Action → Feedback Mapping (CRITICAL)
Define the feedback for every state change.

| Action | Visual Feedback | Animation Duration |
| :--- | :--- | :--- |
| Item Selection | Highlight/Scale Up | ≤ 150ms |
| State Transition | Move to new Slot | ≤ 300ms |
| Error/Invalid | Shake/Red Flash | ≤ 200ms |

---

## 🧪 UX & Architecture Validation

This skill **FAILS** if any of the following are true:

### 🔍 Architecture Checks
1. [ ] Does the Business Logic import UI frameworks or use geometric types (`CGPoint`/`CGRect`)?
2. [ ] Can you resize the window/screen and have all elements snap to valid positions instantly?
3. [ ] Is there any code that hardcodes positions like `x: 300`?
4. [ ] Does every visualized entity have a deterministic `slotIndex`?

### 🔍 UX Checks
1. [ ] Do elements ever touch the absolute edge of the screen? (Fail if yes)
2. [ ] If you add 50 items, do they handle overflow gracefully?
3. [ ] Are animations fluid (≤ 300ms) and interruptible?
4. [ ] UI requires logic execution to preview? (Must support Previews/Mock Data)

---

## Required Visual Artifacts

The `ui_design_document.md` must include:
1. **Layout Diagram:** A visual map of sections and slot grids.
2. **Overflow Rules:** Documentation of how the UI handles capacity limits.
3. **Z-Index Strategy:** Structuring of layers (Background, Content, Overlay, HUD).
4. Preview state list.

## Final Invariant

**"Logic owns the WHAT. UI owns the WHERE."**
The interface should feel instantaneous and responsive.
