<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/game_development/game_planning/SKILL.md
Source group: registry
Skill name: game_planning
Original relative directory: game_development/game_planning
-->

---
skill: game_planning
version: 1.0
type: planning
domain: game_development
blocking: true
runs_after:
  - apple_app_init
runs_before:
  - game_engine_design
  - ui_design
  - ai_design
  - monetization_design
guarantees:
  - clear_game_vision
  - validated_core_loop
  - documented_game_plan
---

# 🎮 game_planning — SKILL

## Purpose

This skill defines the **core design blueprint** of a game before any implementation begins.

It exists to prevent:
- Feature creep
- Direction changes mid-development
- “We’ll figure it out later” syndrome
- Games that are technically complete but not fun

> **Rule:**  
> If the game is not clearly designed, no code may be written.

---

## Design Philosophy (from real killer apps)

- Players don’t play features — they play **loops**
- Simplicity wins early, depth wins long-term
- A game must be **fun in 30 seconds**
- Everything that is not in the core loop is optional

---

## Required Information to Collect (MANDATORY)

This skill must actively ask and document answers to the following.

### 1. Game Identity

- Game title (working title OK)
- Genre (e.g. card, casual, strategy)
- Platform (iOS only? iOS first?)
- Target audience (age, casual vs hardcore)

---

### 2. Core Player Fantasy

> “When the player plays this game, who do they feel like?”

Examples:
- A clever card strategist
- A relaxed traditional game player
- A competitive mind-gamer

This must be **one sentence**.

---

### 3. Core Loop (Most Important)

The assistant must define:



Player Action
→ Game Response
→ Reward
→ Motivation to Repeat


If this loop is not crystal clear → FAIL.

---

### 4. Session Design

- Average session length (30s / 3m / 10m?)
- One-session success condition
- One-session failure condition

---

### 5. Game Rules Scope

- What rules are included at launch
- What rules are intentionally excluded (important!)

---

## 6. Progression & Retention

- Why does the player come back tomorrow?
- Is progression skill-based, unlock-based, or both?

---

### 7. AI Role (if any)

- Is AI an opponent, helper, narrator, or spectator?
- Does AI make decisions or only suggestions?

---

### 8. Success Metric (North Star)

- What single metric defines success for this game?
  - e.g. average session count per day
  - e.g. completion rate of one full match
  - e.g. time to first fun (TTFF)

> **Constraint:** You must choose ONE metric.

---

### 9. First 30 Seconds Experience

- What does the player see first?
- What action do they take within 10 seconds?
- What feedback confirms “this is fun”?

> **Constraint:** Must describe the exact sequence from app launch to first dopamine hit.

---

### 10. Non-Goals (Explicitly Out of Scope)

This game will NOT attempt to be:
- e.g. A competitive esport
- e.g. A social network
- e.g. A real-money gambling product

> **Constraint:** List at least 3 things this game is NOT.

---

## Required Output

This skill **must generate and save** a design document:



plan_document.md


The document must be:
- Human-readable
- Structured
- Implementation-ready
- Used as the single source of truth for all next skills
- **Next Step**: Proceed to `agent_orchestration` to delegate work.

---

## Success Criteria

This skill is considered **PASSED** only if:

- Core loop is defined in one clear diagram
- Game scope is intentionally limited
- The design can be explained in under 2 minutes

---

## Failure Policy

If the design is vague or contradictory:
- Ask clarifying questions
- Do NOT proceed to implementation
- Do NOT invent features silently

---

## Final Invariant

> **A well-designed simple game beats a poorly-designed complex one.**
