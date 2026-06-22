<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/game_development/game_UI_iteration/SKILL.md
Source group: registry
Skill name: game_UI_iteration
Original relative directory: game_development/game_UI_iteration
-->

---
skill: game_UI_iteration
version: 2.0
type: ux_iteration
domain: game_development
blocking: true
runs_after:
  - game_UI
runs_before:
  - ui_implementation
  - animation_binding
requires_reference:
  - ui_design_document.md
guarantees:
  - ux_principles_preserved
  - controlled_ui_iteration
  - strict_logic_ui_separation
  - slot_integrity_maintained
  - screen_bound_invariant
---

# 🔒 game_UI_iteration — SKILL (v2.0 - General)

## Purpose

This skill enables continuous UI iteration **without breaking the architectural separation between Logic and View.**
It ensures that visual improvements do not introduce "magical" coordinate dependencies or inadvertently couple the engine to the screen size.

> **Golden Rule of Iteration:**  
> You can change *how* it looks (View), but you must never change *where* it is calculated (Logic).

---

## 🛡️ Immutable Architecture Invariants

Before any UI change, you must verify:

1.  **Logic Independence:** Does the Engine/Model still know nothing about `CGRect`, `CGPoint`, or Screen Size?
2.  **Slot Determinism:** Is the new visual element driven by a `SlotIndex` or `LayoutState`?
3.  **Responsiveness:** Does the new layout still adapt automatically to different aspect ratios?
4.  **Screen Bound Invariant:** No element may EVER have a coordinate outside the Safe Area visible bounds. (Drifting off-screen is a P0 bug).

**🚨 STOP if:**
- You are tempted to hardcode a position (e.g., `.offset(x: 30)`) to "fix" a layout bug.
- You are adding `@State` that duplicates Logic state.
- You are breaking the "Slot-Based Layout" system defined in `game_UI`.

---

## 🔄 Allowed Iteration Types

UI iteration is allowed **ONLY** within these boundaries:

### 1. Slot Configuration Tuning
- Adjusting the `ViewLayoutManager` logic to change how slots are calculated.
- *Example:* "Change the card overlap from 20% to 30% in `HandSection`."
- *Example:* "Increase padding for the `ScoreBoard` slot."

### 2. Visual Polish
- Changing colors, shadows, corner radii, or typography.
- Adding particle effects (visual only, no logic impact).

### 3. Animation Refinement
- Adjusting easing curves or duration.
- *Constraint:* Animation must still represent `Slot A → Slot B`. No mid-air detours that contradict the logical state.

### 4. Feedback Clarity
- Making active slots more obvious (Glow, Scale).
- Improving error states (Shake, Red Flash).

---

## 🚫 Forbidden Change Types (Immediate FAIL)

1.  **Coordinate Patching:** "Just add +10 pixels here to make it fit." (Fix the LayoutManager instead!)
2.  **Logic-Driven Positioning:** Asking the Engine to "move this item to the right." (The Engine only changes state; UI decides position.)
3.  **Unaccounted Overflow:** Adding items without defining how they stack or scroll in the `LayoutManager`.

---

## 📝 Iteration Proposal Process (MANDATORY)

Every UI change must be formalized to prevent "Layout Drift".

### UI Iteration Proposal Template

```markdown
### UI Iteration Request
**Target Component:** [e.g., Hand View, Score Board]
**Reason:** [e.g., Overlap is too tight on small screens]

**Proposed Change:**
- [ ] Modify `ViewLayoutManager`: [Describe formula change]
- [ ] Update `SlotConfiguration`: [New parameters]

**Architecture Check:**
- [ ] Logic remains coordinate-free? (YES)
- [ ] Resizing window still works? (YES)
```

---

## 🧪 Validation Checklist (Post-Iteration)

After applying changes, confirm:

1.  **The "Squish" Test:** Resize the window aggressively. Does the new UI adapt without breaking?
2.  **The "Flood" Test:** Add max possible items to the slot. Does the overflow strategy work?
3.  **The "Slow" Test:** Run animations at 0.1x speed. Do items travel strictly between valid slots?
4.  **The "Continuity Test (Handover)":** Verify that an item moving from Slot A (Section 1) to Slot B (Section 2) does not flicker, disappear, or teleport. (State transition must be visibly seamless).
5.  **The "Extreme" Test:** Create a `#Preview("Extreme Overflow")` with 50+ items. Confirm no crash and no off-screen drift.

---

## 📂 Required Output

This skill must update:

1.  **`ui_design_document.md`**: Update the Layout Diagrams or Slot Definitions.
2.  **`ui_iteration_log.md`**: Append the execution details.

### Log Format (Appended to ui_iteration_log.md)

```markdown
---
## [YYYY-MM-DD HH:MM] Iteration Log: [Brief Title]

**Trigger:** [Why are we changing this?]
**Scope:** [Visual Only | LayoutManager Update | Interaction Tweak]

**Changes:**
- Modified [File/Component] to [Change Description].
- Adjusted `ViewLayoutManager` formula for [Section].

**Validation:**
- [x] Logic is clean of UI code.
- [x] Tested on [Screen Sizes].
- [x] Overflow behavior verified.
```

---

## 📸 Visual Debugging via Simulator Screenshots & Recordings

When debugging complex animations or "teleporting" issues, reliance on real-time observation is insufficient.

### 1. Mandatory Frame Capture
- For P0 UI bugs (flickering, displacement), you MUST capture the sequence using the simulator's screenshot or recording tools.
- **Screenshot:** `xcrun simctl io booted screenshot <filename>.png`
- **Recording:** `xcrun simctl io booted recordVideo <filename>.mp4`
- Capture at least three states: **Pre-animation, Mid-animation, Post-animation.**

### 2. Full Flow Validation (Video)
- Use screen recordings to capture the entire transition flow. This is mandatory for debugging easing curves and multi-step animations (e.g., Board → Table → Acquisition).

### 3. Slow-Motion Validation
- Use the Simulator's "Slow Animations" feature (`Cmd + T`) while recording to identify the exact frame where continuity breaks.

---

## Final Invariant

**"Beautiful UI is temporary. Broken Architecture is forever."**
Iterate strictly within the Slot System.
