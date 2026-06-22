<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/apple/apple-app-test-agent/SKILL.md
Source group: registry
Skill name: apple_app_test_agent
Original relative directory: apple/apple-app-test-agent
-->

---
name: apple_app_test_agent
description: Setup and run a Python-based test agent to interact with, test, and manipulate an Apple App.
---

# apple_app_test_agent.skill

## Purpose
Provide a standardized Python test agent to communicate with an Apple App (via CLI, Socket, or HTTP), run automated test scenarios, log everything, and capture state on crashes or exceptions.

## 1. Skill Scope
This skill provides the structure and template to:
1. Initialize a `test_agent_python` directory in the project.
2. Provide a flexible `test_agent.py` capable of sending actions, reading all information from the app, and setting specific conditions (mocking/state manipulation).
3. Provide a `test_scenarios.py` to write repeatable, continuous test cases.
4. Auto-generate crash logs and debug states on exceptions.

## 2. Usage Instructions

When a user requests to "create a test agent" or "test the app using python", the AI should:

1. **Copy the Templates**: Copy the contents of the `test_agent_python` folder from this skill into the user's project directory (e.g., `tests/test_agent`).
2. **Adapt the Communication Layer**: Modify the `AppConnection` class in `test_agent.py` to match how the Apple app is tested (e.g., Subprocess CLI, HTTP Server, WebSockets). The app must be able to receive JSON commands and return JSON responses.
3. **Implement Scenarios**: Modify `test_scenarios.py` to add the specific test flow for the app.
4. **Run the Tests**: Instruct the user to run `python test_scenarios.py` (or run it via a command if appropriate).

## 3. Required Capabilities of the App

For this test agent to work, the target Apple App (or its CLI target) **MUST** support the following interface (e.g., via JSON):
- **Read State**: An endpoint/command to retrieve the entire current state of the app (all information).
- **Send Action**: An endpoint/command to trigger a user action (e.g., tap button, play card).
- **Set Condition/Mock**: An endpoint/command to force the app into a specific state or scenario (e.g., set scores to a specific value, load a specific save file).

## 4. App State Contract (Required)

The app SHOULD expose a deterministic JSON state with:
- `version`: Protocol or app version
- `timestamp` / `tick`: Game time or turn number
- `game_phase`: Current phase of the game
- `player_states`: Data for each player
- `board_state`: Shared game state
- `rng_seed`: (If applicable) The current random seed

## 5. Simulator Bridge (New)

The app SHOULD include a `SimulatorBridge` (a mini network server, e.g., using `GCDWebServer` or lightweight Sockets) to allow real-time synchronization between the Python agent and the UI running in the Simulator.
- **Protocol**: HTTP/JSON or WebSockets
- **Port**: Default to a configurable port (e.g., 8080)
- **Environment**: Should only be active in `DEBUG` or `SIMULATOR` builds.

## 6. Real-time UI Synchronization (Strongly Recommended)

To ensure the test agent reflects the visual state of the Simulator:
- The `SimulatorBridge` should notify the agent of state changes OR respond to polling with the latest `GameManager` data.
- User actions sent via the agent should be immediately reflected in the SwiftUI views.

## 7. Determinism & Replay (Recommended)

To ensure reproducible test results, the target app SHOULD support:
- Setting a fixed RNG seed
- Exporting and importing action sequences
- Replaying a scenario deterministically

This allows crash reproduction and regression testing.

## 8. Visual Verification via Screenshots & Recordings (New)

For UI-heavy test scenarios (e.g., card animations, menu transitions), the agent SHOULD programmatically capture screenshots or videos to verify visual state.
- **Automation**: Use `xcrun simctl io booted screenshot` or `xcrun simctl io booted recordVideo` within the Python agent's `AppConnection` or scenario logic.
- **Artifacts**: Store these in `artifacts/screenshots/` or `artifacts/recordings/` and include them in the `walkthrough.md` for visual proof of success.
- **Comparison**: (Optional) Use video artifacts to identify exactly where an animation sequence diverges from the expected path.

## 9. Safety & Execution Limits

The test agent MUST enforce:
- Max steps per scenario
- Timeout per action
- Protection against infinite loops
- Graceful abort with state dump

## 9. Test Artifacts

Each test run SHOULD generate:
- Full action log (in `artifacts/logs/`)
- State snapshots pre/post action (in `artifacts/state_snapshots/`)
- Crash dump on failure (in `artifacts/crash_dumps/`)
- Reproduction steps in JSON (in `artifacts/repro_steps.json`)

## 10. CI Integration (Optional)

The test agent SHOULD be runnable:
- Headless
- Without UI
- In CI environments (GitHub Actions, Jenkins, etc.)

## 11. Components in this Skill

- `test_agent_python/main.py`: The core agent class. Handles logging, repeating tests, exception catching, artifacts generation, and the protocol to talk to the app.
- `test_agent_python/test_scenarios.py`: Example test suites defining the scenarios to run repetitively.

