# Project Definition & Agent Guidelines

This document defines the project context, technical standards, agent roles, and workflow for `GoStop_antigravity`.

## 1. Project Context
**"우리가 뭘 만드는가?"**

- **Product**: iOS Go-Stop (Hwatu) game.
- **UI Direction**: SwiftUI-based gameplay UI with clear card visibility and responsive interactions.
- **Core Goal**: Rule-accurate engine behavior (turn flow, scoring, Go/Stop, penalties) with automated validation support.
- **Validation Goal**: Reproducible test-agent runs and artifact collection for debugging and regression checks.

## 2. Tech Stack
**"어떤 도구를 쓰는가?"**

- **Language**: Swift 6 (main app/game engine)
- **UI Framework**: SwiftUI
- **Architecture**: MVVM (Model-View-ViewModel) + `Core` domain logic modules
- **Dependency Management**: Swift Package Manager (SPM)
- **Test/Validation Tooling**: Python test agents + Swift CLI / simulator bridge

### Repository Mapping
- `GoStop/`: SwiftUI app, models, core gameplay engine
- `GoStopCLI/`: CLI target for engine/bridge interaction
- `GoStopTests/`: Swift test target
- `tests/test_agent/`: Python validation agents and scenarios
- `test_artifacts/`: Test outputs, logs, reports, and reproducible evidence

## 3. Agent Roles
**"누가 무엇을 하는가?"**

### Maker (개발)
- Implements features/fixes in Swift code (`GoStop/`, `GoStopCLI/`, related tests).
- Preserves MVVM boundaries and avoids mixing UI rendering with game-rule logic.
- Makes minimal, targeted changes instead of broad refactors unless explicitly requested.
- Updates tests or scenarios when behavior changes.

### Tester (검증)
- Runs scenario-based validation and checks for rule regressions.
- Verifies game state transitions, scoring, action availability, and bridge protocol consistency.
- Captures artifacts for failures (logs, reports, reproduction notes).
- Reports exact mismatch between expected and observed behavior.

## 4. Rules & Patterns
**"어떻게 짜야 하는가?"**

### Formatting / Indentation
- Use spaces, not tabs.
- Swift: 4-space indentation.
- Python: 4-space indentation.
- Keep line wrapping consistent with surrounding files instead of reformatting unrelated code.

### Architecture / Responsibility Boundaries
- **Models**: Data structures and config representations.
- **Core**: Game rules, turn progression, scoring, and engine logic.
- **Views (SwiftUI)**: Rendering and user interaction wiring only.
- **ViewModel / State Coordinators**: UI-facing state derivation and action dispatching.
- Do not move rule decisions into SwiftUI `body` or view modifiers.

### Error Handling
- Do not silently swallow invalid states or protocol mismatches.
- Swift:
  - Use explicit error propagation (`throws`, `do-catch`, `Result`) for recoverable failures.
  - Use assertions/preconditions carefully for impossible internal states in debug-oriented paths.
- Python (test agent):
  - Prefer clear assertions with context over ambiguous failures.
  - Log enough state to reproduce the issue (phase, current player, selected action/card, response payload).

### UI Declaration Rules (SwiftUI)
- Keep views declarative and composable.
- Extract helper views/functions when `body` becomes hard to read.
- Use explicit spacing/padding constants when repeated in the same view.
- Avoid hidden business logic in view layout code.
- Preserve playability: cards must remain tappable, legible, and not unintentionally clipped on iPhone screens.

### Change Scope
- Do not refactor unrelated files while fixing a local issue.
- Avoid renaming public-facing types/protocol fields unless required by the task.
- Prefer additive diagnostics/logging over invasive behavioral changes during bug triage.

## 5. Workflow
**"일은 어떤 순서로 하는가?"**

Default sequence for feature work and bug fixes:

1. **Define target**: Clarify the rule/UX behavior to implement or fix.
2. **Code (Maker)**: Implement the minimal change in the correct layer (View/Core/ViewModel/Test Agent).
3. **Test (Tester)**: Run relevant validation (Swift tests, CLI checks, Python scenarios).
4. **Artifact 저장**: Save logs/reports/repro notes under `test_artifacts/` (or an existing artifact folder used by the task).
5. **Report**: Summarize changed files, test coverage, and remaining risks.

## 6. Agent Registry (Runtime / Validation Components)

### AI Player
- **File**: `tests/test_agent/ai_player.py`
- **Role**: Strategy decision-making and automated play actions.

### Test Bridge Client
- **File**: `tests/test_agent/main.py`
- **Role**: JSON-based communication with Swift CLI/simulator bridge.

### Scenario Runner
- **File**: `tests/test_agent/test_scenarios.py`
- **Role**: Repeatable rule validation scenarios and regression checks.

### Game Core / Bridge (Swift)
- **Directory**: `GoStop/Core/`
- **Role**: Engine logic, state transitions, scoring, and simulator bridge integration.

## 7. Common Commands

```bash
swift build
swift test
python3 tests/test_agent/main.py
python3 tests/test_agent/test_scenarios.py
```

## Skills
A skill is a local instruction set in a `SKILL.md` file that can be triggered by name or by task intent.

### Available skills
- skill-creator: Guide for creating effective skills. (file: /Users/najongseong/git_repository/skills-registry/.system/skill-creator/SKILL.md)
- skill-installer: Install Codex skills from curated lists or GitHub paths. (file: /Users/najongseong/git_repository/skills-registry/.system/skill-installer/SKILL.md)
- apple_app_test_agent: Setup and run a Python-based test agent for Apple apps. (file: /Users/najongseong/git_repository/skills-registry/apple/apple-app-test-agent/SKILL.md)
- apple_app_init: Guardrails for creating a runnable iOS SwiftUI app project. (file: /Users/najongseong/git_repository/skills-registry/apple/apple_app_init/SKILL.md)
- review-issue-scenario: Add regression scenarios after issue review and fixes. (file: /Users/najongseong/git_repository/skills-registry/apple/review-issue-scenario/SKILL.md)
- add-bug-fix-scenario: Add bug-fix regression scenarios while avoiding duplicates. (file: /Users/najongseong/git_repository/skills-registry/apple/review-issue-scenario/add-bug-fix-scenario/SKILL.md)
- game_UI: UX-first game UI blueprint with logic/view separation and slot-based layout. (file: /Users/najongseong/git_repository/skills-registry/game_development/game_UI/SKILL.md)
- game_UI_iteration: Controlled UI iteration while preserving architecture invariants. (file: /Users/najongseong/git_repository/skills-registry/game_development/game_UI_iteration/SKILL.md)
- game_engine_design: Deterministic game engine design rules and boundaries. (file: /Users/najongseong/git_repository/skills-registry/game_development/game_engine_design/SKILL.md)
- game_engine_iteration: Structured post-design engine evolution with traceability. (file: /Users/najongseong/git_repository/skills-registry/game_development/game_engine_iteration/SKILL.md)
- game_planning: Core game planning workflow before implementation. (file: /Users/najongseong/git_repository/skills-registry/game_development/game_planning/SKILL.md)
- test-agent-sync: Synchronize test agents when engine/rule/state contracts change. (file: /Users/najongseong/git_repository/skills-registry/game_development/test_agent_sync/SKILL.md)
- project_logger: Record user requests and project progress in `project_progress.md`. (file: /Users/najongseong/git_repository/skills-registry/project_management/project_logger/SKILL.md)
