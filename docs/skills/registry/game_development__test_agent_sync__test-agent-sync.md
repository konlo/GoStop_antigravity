<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/game_development/test_agent_sync/SKILL.md
Source group: registry
Skill name: test-agent-sync
Original relative directory: game_development/test_agent_sync
-->

---
name: test-agent-sync
description: Synchronize test agents automatically when game engine, rules, or state contracts change.
---

# test-agent-sync.skill

## Purpose
The purpose of this skill is to ensure that all existing test agents (scoring agent, go/stop agent, ui flow agent, etc.) are automatically updated and kept consistent whenever game code (engine, rules, state contracts) is modified. It automates the "Code Change -> Impact Analysis -> Test Agent Sync -> Validation -> Reporting" cycle.

## 1. Trigger Conditions
This skill is automatically triggered in the following scenarios:
1. **Engine Code Modification**: Changes to `GameEngine`, `RuleEvaluator`, or core logic.
2. **Rule Definition Changes**: Updates to `rules.yml` or declarative rule files.
3. **State Contract Updates**: Modifications to `GameState`, API protocols, or data structures.
4. **Iteration Records**: New entries in `engine_iteration.md` indicating a new development cycle.

## 2. Core Responsibilities

### 2.1 Change Analysis
Analyze the `git diff` or change request to classify the modifications:
- `engine_logic`: Procedural changes in how the game runs.
- `rule_definition`: Declarative changes in game rules (points, thresholds, etc.).
- `state_contract`: Structural changes in data schemas or interfaces.

### 2.2 Impact Mapping
Identify which test agents are affected based on their "watch" types:
- **Scoring Agent**: Watches `rule_definition` and `engine_logic`.
- **Go/Stop Agent**: Watches `rule_definition` and `state_contract`.
- **UI Flow Agent**: Watches `state_contract`.
- *Exclude agents that do not match the change type.*

### 2.3 Auto Patch Instruction Generation
Generate natural language instructions for each affected agent to update itself.
- **Example**: "Update the `calculate_score` threshold for 'Chongtong' from 7 to 10 points in alignment with the new `rules.yml`."
- Instructions must be specific enough for an agent or tool to apply the code update reliably.

### 2.4 Test Agent Synchronization
Apply the generated patches to the test agents.
- **Rules**: Reload schemas, update thresholds.
- **Engines**: Update mocks, adjust expectation values.
- **Scenarios**: Regenerate test data or update scenario flows if the state contract changed.

### 2.5 Validation
Run the updated test agents against the modified engine/rules.
- Check for consistency between code and test logic.
- Verify rule checksums or expected outcomes.
- **Failure**: If validation fails (e.g., mismatching results), report as `FAIL` and stop.

### 2.6 Reporting
Generate a `test-agent-sync` report including:
- List of updated test agents.
- Classified change types reflected.
- Validation status (PASS/FAIL).

## 3. Outputs
- **Updated Code**: Test agent source files updated with new logic/rules.
- **Sync Report**: `artifacts/test-agent-sync-report.md`.
- **Iteration Log**: Summary appended to `engine_iteration.md`.

## 4. Design Principles
- **Source of Truth**: The engine code (How) and rule files (What) are the absolute source of truth.
- **Auto-Evolution**: Tests must evolve at the same pace as the code without manual intervention.
- **Declarative Alignment**: Prefer declarative rule alignment over hardcoded logic in test agents.

## 5. Components in this Skill
- `scripts/sync_engine.py`: (Planned) Logic for diff-based impact mapping.
- `templates/sync_report.md`: Structure for the final synchronization report.
