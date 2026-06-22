<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/gostop-ui-playability/SKILL.md
Source group: installed
Skill name: gostop-ui-playability
Original relative directory: gostop-ui-playability
-->

---
name: gostop-ui-playability
description: Improve GoStop and card-game UI playability in SwiftUI. Use when requests mention simulator live-screen UX, cards being too small or clipped, scrolling during gameplay, card overlap/layout tuning, captured-card grouping (광/10끗/5끗/피), unclear turn/card movement animation, single-vs-multiplayer animation parity, render-probe evidence, or external-agent-driven UI validation that needs a requirement-to-contract gate before code changes.
---

# GoStop UI Playability

## Quick Start

1. Convert the request into a UI contract before editing:
- target screen/state
- exact visual behavior
- expected render-probe or screenshot evidence
- affected single/multiplayer path
- validation command and artifact path
2. Run baseline checks with `scripts/run_ui_smoke.sh <repo-path>`.
3. Capture before-state screenshots or snapshots for comparison.
4. Fix layout first, then readability, then animation.
5. Validate with `references/playability-checklist.md`.
6. If requested, run external-agent flow in `references/simulator-agent-flow.md`.

## Workflow

### 0) UI contract gate

- Do not start SwiftUI edits until the visible behavior has a measurable success condition.
- For card animation requests, define:
  - source zone and target zone (`hand`, `deck`, `table`, `captured`)
  - actor (`local`, `remote`, `host`, `guest`)
  - expected UX event or render-probe field
  - required client parity (`host`, `guest`, or both)
  - screenshot/video/action-log artifact to inspect
- For multiplayer UI, explicitly state whether the fix must reuse the single-player `GameManager`/animation path or can be multiplayer-specific.
- If the user asks for "same as single", verify the shared execution path before changing visual code.

### 1) Establish baseline

- Identify active surface areas: top/status, opponent, table, user hand, captured.
- Confirm current pain points from user wording before coding.
- Prefer reproducible states (fixed seed, same device/orientation) during iteration.
- Record the build/app under test; stale simulator installs are treated as invalid evidence.

### 2) Layout for no-scroll gameplay

- Keep core gameplay fully visible without scrolling.
- Reserve fixed regions for `opponent`, `table`, `user hand`, and `captured` sections.
- Keep all card sizes uniform across zones unless user explicitly requests otherwise.
- Prefer multi-row hands over shrinking cards too aggressively.
- Allow overlap only between cards when density is high; never overlap major UI panels.

### 3) Readability priorities

- Keep user-hand cards largest readable size first.
- Show opponent hand as face-down cards plus count label.
- Keep table cards easy to target for selection.
- Group captured cards by kind in this order:
  - `bright` (광)
  - `animal` (10끗)
  - `ribbon` (5끗)
  - `junk` (피)
- Within each group, keep stable order (month then slot).

### 4) Motion and interaction

- Animate card movement between zones so turn flow is visually clear.
- Use local animations for card moves, selectable highlights, and banners.
- Avoid broad/global animation wrappers that cause unnecessary rerender.
- Keep interaction responsive during overlays (`decision`, `gameOver`) and avoid input lockups.
- For agent-driven demo mode, show explicit connection/turn state in UI.
- For multiplayer animation parity, prove that accepted actions, actor IDs, snapshot stateVersion, and render-probe state all advance coherently.
- Do not mask a missing engine/coordinator transition with cosmetic animation.

### 5) Asset and fallback handling

- Verify all `Month{month}_{slot}` assets exist before claiming UI is complete.
- Keep robust fallback rendering when image assets are missing.
- Cache image lookup results to avoid repeated bundle/path checks in render path.

### 6) Validation and reporting

- Execute smoke checks via `scripts/run_ui_smoke.sh`.
- Run checklist in `references/playability-checklist.md` and mark pass/fail.
- For simulator tasks, validate at least one compact size and one regular size.
- For multiplayer UI changes, run a real host/guest scenario or explain why it could not be run.
- Inspect artifacts, not just terminal PASS:
  - `summary.md`
  - `timeline.jsonl`
  - `action_log.jsonl`
  - final/failure screenshots
- Report results with:
  - changed files
  - what improved for UX/playability
  - exact artifact evidence
  - remaining risks and next fix candidates

## References

- Read `references/playability-checklist.md` before sign-off.
- Read `references/simulator-agent-flow.md` when testing with external agent commands.
