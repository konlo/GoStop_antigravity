<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/gostop-game-builder/SKILL.md
Source group: installed
Skill name: gostop-game-builder
Original relative directory: gostop-game-builder
-->

---
name: gostop-game-builder
description: Build Korean GoStop (Hwatu) games end-to-end with Swift and SwiftUI plus test-agent and debugging tooling. Use when users ask for "고스톱 게임을 만들어줘", request GoStop rule implementation, simulator-ready gameplay UI, test-agent interfaces, action-guard diagnostics, replay and log artifacts, or runtime anomaly triage.
---

# GoStop Game Builder

## Quick Start

1. Confirm target runtime and platforms (iOS simulator only vs iOS plus macOS).
2. Implement engine safety first (phase, step, player, pause, replay guards).
3. Expose test-agent bridge with stable command and response contracts.
4. Emit reproducible debug artifacts (logs, diff, replay, anomaly checklist).
5. Finish UI interaction flow with clear step-based guidance.

## Workflow

### 1) Model and state safety

- Keep `GamePhase` and `TurnStep` explicit in state.
- Reject invalid commands with stable error codes and clear messages.
- Guard actions by `gamePhase`, `turnStep`, `currentPlayerIndex`, `isPaused`, and `isReplayMode`.
- Add recovery commands: `setup/gameOver -> start`, `paused -> resume`, `replay -> quit`.
- Preserve deck invariants: 48 cards, month 1..12 each has 4 cards, slots per month are unique.

### 2) Rule implementation

- Implement Matgo baseline scoring and go multipliers (`3go x2`, `4go x3`, `5go x4`).
- Implement special events (`jjok`, `dadak`, `ppeok`, `3 ppeok lose`).
- Keep edge rules in engine logic, not UI conditionals (example: empty hand forces stop).

### 3) Test-agent bridge

- Support actions: `hello/state/start/play/select/go/stop/pause/resume/quit/validateDeck/help/logs/replayExport/debugDiff`.
- Return `traceId`, `timingMs`, `errorCode`, and `state` on every response.
- Use newline-delimited JSON framing on loopback socket.

### 4) Debug and reliability

- Record before and after state hash for each command.
- Persist state diffs with changed field paths.
- Export artifacts under `.artifacts/debug/<runId>/`.
- Keep log categories: `CMD`, `ACTION`, `ENGINE`, `REJECT`, `ERROR`.
- Write anomaly and checklist reports with enough detail to reproduce failures.

### 5) UI implementation

- Drive interactions from turn step (`selectHandCard`, `match*`, `decision`).
- Use tap-safe controls for interactive cards in simulator environments.
- Show explicit hints when a user action is blocked by current step.
- Add sound and haptic feedback after gameplay loop stability is confirmed.

## References

- Read `references/gostop-spec.md` before implementing a new GoStop app or major refactor.
- Read `references/test-agent-v2-contract.md` when implementing or debugging bridge APIs.
