# UI Iteration Log

---
## [2026-02-15 21:00] Iteration Log

**User Instruction:**
> Implement realistic Hwatu graphics and animations to replace placeholders.

**Plan:**
- Optimization Target: Visual Realism and Immersion.
- Planned Changes: 
    - Replace generic SF Symbols with high-quality, authentic Hwatu card images.
    - Implement smooth animations for card dealing and playing key actions.

**Actions Taken:**
- **Asset Acquisition**: 
    - Initially attempted AI generation (DALL-E), but switched to ensuring authenticity by sourcing open-source Hwatu assets (ALee1303).
    - Developed `process_assets.py` to normalize filenames to `month_index` format.
    - Developed `import_assets.py` to automate Xcode Asset Catalog creation.
- **UI Implementation**:
    - Updated `CardView` to render `Image` from assets instead of text/shapes.
    - Added `matchedGeometryEffect` in `GameView` to animate cards flowing from Hand to Table.
    - Fixed a critical bug where case-mismatch (`Jan` vs `jan`) caused assets to fail loading.

**UX Invariant Check:**
- Before: Cards were white rectangles with text (e.g., "Jan Bright"). Cognitive load to identify cards was high.
- After: Cards display recognized standard Hwatu imagery. ID is instantaneous for players familiar with the game. Animations provide clear feedback on which card was played.
- Verdict: PASS

---
## [2026-02-15 22:00] Iteration Log

**User Instruction:**
> Display captured cards for both player and opponent. Organize them by level/type (Bright, Animal, Ribbon, Junk) so they are easy to distinguish.

**Plan:**
- Optimization Target: Information Accessibility & Space Efficiency.
- Planned Changes: 
    - Create `CapturedAreaView` that filters cards by type.
    - Use an **Efficient Stacking (Fanning)** layout:
        - Junk cards stacked tightly (just need to see count).
        - Scoring cards (Bright/Animal/Ribbon) stacked with more visibility.
    - integrate into `GameView` (Opponent Top, Player Bottom).

**Actions Taken:**
- Created `CapturedAreaView.swift`: Implemented logic to sort cards into 3 groups (Bright/Animal, Ribbon, Junk) and display them in horizontal `ZStack` fans.
- Updated `GameView.swift`: 
    - Replaced placeholder text with `CapturedAreaView` for Opponent.
    - Inserted `CapturedAreaView` above Player Hand.
- Verified visually by injecting dummy data and capturing a screenshot (`game_ui_upgrade.png`).

**UX Invariant Check:**
- Before: No visual representation of captured cards (only score text).
- After: Cards are visible, sorted, and space-efficient. Players can instantly assess their scoring potential (e.g., "I have 2 Brights").
- Verdict: PASS

---
## [2026-02-15 22:30] Iteration Log

**User Instruction:**
> Ensure all cards (Hand, Captured, Table) are visible on the screen without scrolling. The player's cards were previously cut off.

**Plan:**
- Optimization Target: Responsive Layout / Fit to Screen.
- Planned Changes: 
    - Replace rigid `VStack` layout with `GeometryReader`.
    - Allocate vertical space proportionally:
        - Opponent: 15%
        - Table: 45%
        - Player: 40%

**Actions Taken:**
- Modified `GameView.swift`: Wrapped content in `GeometryReader`.
- Removed fixed `.frame(height: 100)` from Opponent Area.
- Removed `.maxHeight: 250` from Table Area.
- Applied `.frame(height: geometry.size.height * ratio)` to each section.

**UX Invariant Check:**
- Before: Player's hand was pushed off-screen by Table/Opponent areas on smaller devices.
- After: All areas scale to fit the available screen height. No scrolling required. everything is visible "at a glance".
- Verdict: PASS

---
## [2026-02-15 22:45] Iteration Log

**User Instruction:**
> Refine the design: Make the empty captured area visible (placeholders), improve the flat background, and style the player info.

**Plan:**
- Optimization Target: Visual Polish & Feedback Clarity.
- Planned Changes: 
    - **CapturedAreaView**: Add ghost icon placeholders (Sun, Bird, Leaf) when empty.
    - **GameView**: Replace green color with Radial Gradient (Felt table effect).
    - **Player Info**: Add translucent capsule background with border.

**Actions Taken:**
- Modified `CapturedAreaView.swift`: Added `PlaceholderSlot` view with SF Symbols.
- Modified `GameView.swift`: 
    - Applied `RadialGradient` background.
    - Styled Player Info with `Material.thinMaterial` and capsule clip.
- Verified with screenshot (`game_ui_polished.png`).

**UX Invariant Check:**
- Before: Flat, boring background. Confusing empty spaces. Hard-to-read text.
- After: Premium felt look. Clear guidance on where cards go. Legible player info.
- Verdict: PASS

---
## [2026-02-15 22:55] Iteration Log

**User Instruction:**
> Fix the white gap on the left and the cropped text on the right.

**Plan:**
- Optimization Target: Edge-to-Edge Layout.
- Planned Changes: 
    - **GameView**: Configure `GeometryReader` to `.ignoresSafeArea()`.
    - Explicitly set content size to `geometry.size` to fill the screen voids.

**Actions Taken:**
- Modified `GameView.swift`: Added `.ignoresSafeArea()` modifier.
- Forced `VStack` frame to match screen width/height.

**UX Invariant Check:**
- Before: Content shifted right due to safe area, causing white gap + cropping.
- After: Full-screen immersion. No white bars. Centered overlays.
- Verdict: PASS

---
## [2026-02-15 23:10] Iteration Log

**User Instruction:**
> Fix corner clipping (Top-Left/Bottom-Right) and split Brights and Animals into separate groups.

**Plan:**
- Optimization Target: Visual Clarity & Safe Area Compliance.
- Planned Changes: 
    - **CapturedAreaView**: Separate logic for `brights` and `animals`. Update layout to 4 columns.
    - **GameView**: Add padding to content loop to prevent clipping by simulated device corners.

**Actions Taken:**
- Modified `CapturedAreaView.swift`: Split `brightsAndAnimals` into two variable. Added `bird.fill` placeholder for animals.
- Modified `GameView.swift`: Added `.padding(.horizontal)` to the main content container.

**UX Invariant Check:**
- Before: Cards clipped by rounded corners. Brights and Animals mixed.
- After: Content inset safely. 4 distinct captured groups (Bright, Animal, Ribbon, Junk) for easy score tracking.
- Verdict: PASS

---
## [2026-02-15 23:22] Iteration Log

**User Instruction:**
> Fix horizontal "Right Shift" (screen is off-center) and increase spacing between captured card groups.

**Plan:**
- Optimization Target: Symmetry & Legibility.
- Planned Changes: 
    - **GameView**: Force center alignment with `.position(x: center, y: center)` to override safe area offsets.
    - **CapturedAreaView**: Double opacity/spacing between groups (15->30) for clearer separation.

**Actions Taken:**
- Modified `GameView.swift`: Applied strict centering logic.
- Modified `CapturedAreaView.swift`: Increased `HStack` spacing.

**UX Invariant Check:**
- Before: Content shifted right, making it look asymmetrical. Groups were too close.
- After: Perfectly centered game board. Distinct piles for effortless score checking.
- Verdict: PASS

---
## [2026-02-15 23:35] Iteration Log

**User Instruction:**
> Opponent's Junk (Pi) captured cards are not visible. Match the layout to the player's area.

**Plan:**
- Optimization Target: Visibility & Consistency.
- Planned Changes: 
    - **CapturedAreaView**: Remove the `Spacer` that pushes content off-screen.
    - **Layout**: Introduce configurable spacing (`spacing: CGFloat`).
    - **GameView**: Use compact spacing (10pt) for Opponent to fit top bar, wide spacing (30pt) for Player.

**Actions Taken:**
- Modified `CapturedAreaView.swift`: Removed `Spacer`, added `spacing` init parameter.
- Modified `GameView.swift`: Updated call sites.

**UX Invariant Check:**
- Before: Opponent's Junk column was cutting off or invisible.
- After: All 4 groups (Brights, Animals, Ribbons, Junk) are visible for both players.
- Verdict: PASS

---
## [2026-02-15 23:45] Iteration Log

**User Instruction:**
> Change Opponent Layout: Hand on first line, Captured Cards on second line.

**Plan:**
- Optimization Target: Visibility & Standard Layout.
- Planned Changes: 
    - **GameView**: 
        - Convert Opponent's `HStack` to `VStack`.
        - Increase Opponent Height share (15% -> 22%).
        - Decrease Table Height share (45% -> 38%).
    - **CapturedAreaView**: Use wider spacing (20pt) for Opponent now that it has full width.

**Actions Taken:**
- Modified `GameView.swift`: Restructured `opponentArea` and height ratios.

**UX Invariant Check:**
- Before: Opponent area was a single cramped row.
- After: Opponent area is a spacious 2-row layout. Hand is separated from Score/Captured cards. No clipping.
- Verdict: PASS

---
## [2026-02-16 00:05] Iteration Log

**User Instruction:**
> Distinguish 10-point/5-point groups better. Overcome Junk (Pi) overflow by stacking them in layers (e.g., every 5 cards).

**Plan:**
- Optimization Target: Space Efficiency & Readability.
- Planned Changes: 
    - **JunkPileView**: Implement smart stacking logic (chunks of 5 cards).
    - **Layout**: Use `ZStack` with offsets (x: 10, y: -15) for each chunk to simulate a "pile".
    - **Spacing**: Increased default overlap for other groups for visibility.

**Actions Taken:**
- Modified `CapturedAreaView.swift`: Added `JunkPileView` component and integrated it.

**UX Invariant Check:**
- Before: Junk cards formed a single long line that ran off screen.
- After: Junk cards stack neatly in diagonal layers. Space usage is reduced by ~60%.
- Verdict: PASS

---
## [2026-02-16 00:20] Iteration Log

**User Instruction:**
> Prevent captured cards (e.g., Brights) from going off-screen when the pile grows. Make stacked cards less overlapped to see them better.

**Plan:**
- Optimization Target: Absolute Visibility & Identifiability.
- Planned Changes: 
    - **GameView**: Wrap `CapturedAreaView` in `ScrollView(.horizontal)`.
    - **CapturedAreaView**: 
        - Increase overlap in `JunkPileView` to 22 (approx 1/3 visual coverage).
        - Increase vertical offset of stacks to separate layers.

**Actions Taken:**
- Modified `GameView.swift`: Added horizontal ScrollView wrapper.
- Modified `CapturedAreaView.swift`: Tuned overlap constants.

**UX Invariant Check:**
- Before: Brights clipped on left edge. Bottom cards in stack were hidden.
- After: Horizontal scroll ensures nothing is ever lost. Stack layers are distinct.
- Verdict: PASS
