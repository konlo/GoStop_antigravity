<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/game_development/game_engine_design/SKILL.md
Source group: registry
Skill name: game_engine_design
Original relative directory: game_development/game_engine_design
-->

---
skill: game_engine_design
version: 1.0
type: engine_design
domain: game_development
blocking: true
runs_after:
  - game_planning
runs_after_optional:
  - game_UI
runs_before:
  - engine_implementation
  - ai_decision_design
  - ui_interaction_binding
guarantees:
  - deterministic_gameplay
  - testable_game_engine
  - ui_engine_separation
---

# ⚙️ game_engine_design — SKILL

## Purpose

This skill defines the **deterministic core game engine**.

It ensures that:
- Game rules are applied consistently
- The same input always produces the same result
- UI and animations never affect game logic
- The engine can be tested **without UI**

> **Rule:**  
> If the engine is not deterministic, the game is not debuggable.

Core Engine Philosophy (Real-world lessons)

The engine does not know UI exists

The engine does not play animations

The engine does not ask the player questions

The engine only:

Accepts actions

Validates them

Produces results

UI reacts to the engine — never the opposite.

Engine Responsibility Boundary
Engine MUST handle

Game state

Rule validation

Turn progression

Score calculation

Win / Lose conditions

Engine MUST NOT handle

Touch events

Animations

Delays / timers

Sounds

AI personality

Required Engine Inputs

The engine must accept explicit actions only.

PlayerAction
AIAction
SystemAction


Examples:

PlayCard(cardId)

ChooseGo

ChooseStop

DrawCard

No implicit behavior allowed.

State Machine Design (CRITICAL)

The engine must be representable as a finite state machine.

Required States (example)
Idle
Dealing
PlayerTurn
AITurn
ResolveAction
CheckScore
GameEnd


Each state must define:

Allowed actions

Forbidden actions

Next possible states

If a state allows “anything” → FAIL.

Action → Result Contract

Every action must return:

EngineResult


Containing:

State changes

Score changes

Events to display

Next expected state

The engine never mutates state silently.

Event-Based Output (UI Contract)

The engine outputs events, not commands.

Examples:

CardPlayed

ScoreUpdated

TurnChanged

GameEnded

UI interprets events into animations.

Determinism Rules

No randomness inside engine without seed

All shuffles must be seed-based

No system time access

No async behavior

Same seed + same actions = same game.

Error Handling Rules

Invalid actions are rejected explicitly

Engine never crashes on invalid input

Errors are returned as results

Example:

InvalidAction(reason: "Not your turn")

Engine Testing Requirements

This skill fails if:

Engine cannot run headless

Rules cannot be unit-tested

State transitions are implicit

Required Tests

Single turn progression

Edge case rule tests

Full game simulation

AI Integration Boundary

AI:

Consumes engine state

Produces actions

Never mutates engine directly

Engine:

Treats AI actions same as player actions

Required Output Artifacts

This skill must produce:

State machine diagram

Action list

Engine result schema

Saved as:

engine_design_document.md

Non-Goals

This skill does NOT:

Optimize performance

Implement AI strategy

Handle UX concerns

Play animations

Final Invariant

If UI disappears, the game must still fully function.


---


## 🛡️ Safety & Bounds (New Requirement)

To prevent "infinite" UI expansion, the Engine MUST define hard limits for all collections.

- **Max Hand Size:** e.g., 20 cards (even if rules say unlimited).
- **Max Captured Count:** e.g., 48 cards (deck size).
- **Max Score:** e.g., 999,999,999.

> **Rule:** The Engine must reject or cap actions that would exceed these bounds, protecting the UI from "impossible" states.

---

## 🔥 왜 이 SKILL이 중요한가 (진짜 핵심)

- 버그의 80%는 **엔진-UI 결합**에서 발생
- AI는 엔진이 안정적일 때만 의미 있음
- 테스트 가능한 엔진 = 빠른 iteration

지금 네 구조는:



Planning → UI → Engine → AI → Binding


👉 **이건 상업 게임 팀의 정석 구조**야.

---
