<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/apple/review-issue-scenario/add-bug-fix-scenario/SKILL.md
Source group: registry
Skill name: add-bug-fix-scenario
Original relative directory: apple/review-issue-scenario/add-bug-fix-scenario
-->

---
name: add-bug-fix-scenario
description: Add a regression test scenario when a bug is fixed, ensuring no duplicate scenarios exist.
---

# add-bug-fix-scenario.skill

## Purpose
Streamline the process of adding regression tests to the `apple-app-test-agent` framework after a bug fix.

## Usage Instructions

When a bug is fixed and a regression test is needed:

1. **Check for Existing Scenarios**: 
   - Search the project's test files (e.g., `test_scenarios.py`) for existing scenarios that cover similar logic.
   - Use `grep_search` or `find_by_name` to locate related terms.
   - If a related scenario exists, consider updating it instead of creating a new one.

2. **Identify Bug & Fix**:
   - Provide a brief description of the bug and the fix.
   - Example: "Fixed infinite loop when playing dummy cards in socket mode."

3. **Generate Scenario**:
   - Create a new function in `test_scenarios.py` using the `scenario_bugfix_[description]` naming convention.
   - Use the `TestAgent` methods (`get_all_information`, `send_user_action`, `set_condition`) to reproduce the bug state and verify the fix.

4. **Register Scenario**:
   - Add the new scenario function to the `scenarios_to_run` list in the `main` block of `test_scenarios.py`.

5. **Verify**:
   - Run the tests to ensure the new scenario passes and no regressions are introduced.

## Template

```python
def scenario_bugfix_description(agent: TestAgent):
    """
    Bug: [Description]
    Fix: [Description]
    """
    logger.info("Running bugfix scenario: description...")
    
    # 1. Setup condition if needed
    agent.set_condition({
        "key": "value"
    })
    
    # 2. Perform action
    agent.send_user_action("action_name")
    
    # 3. Verify state
    state = agent.get_all_information()
    assert state.get("key") == "expected_value", "Fix verification failed!"
```
