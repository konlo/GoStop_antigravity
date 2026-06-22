<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/apple/review-issue-scenario/SKILL.md
Source group: registry
Skill name: review-issue-scenario
Original relative directory: apple/review-issue-scenario
-->

---
name: review-issue-scenario
description: Add a regression test scenario when issues are identified during content review and fixed.
---

# review-issue-scenario.skill

## Purpose
Ensure that content quality is maintained by adding automated regression tests whenever an issue is found and fixed during a content review process.

## Usage Instructions

When content is reviewed and an issue is identified/fixed:

1. **Check for Existing Scenarios**: 
   - Before creating a new scenario, search existing test files (e.g., `test_scenarios.py`) for scenarios covering the same content or logic.
   - Use `grep_search` to find related keywords.
   - If a relevant scenario exists, update it to include the new validation logic instead of creating a duplicate.

2. **Identify Review Issue & Fix**:
   - Document the specific issue found during review (e.g., "Incorrect animation timing for 'Go' button").
   - Document the fix or improvement made.

3. **Generate/Update Scenario**:
   - Create a new function in `test_scenarios.py` with the prefix `scenario_review_[description]`.
   - Use `TestAgent` to navigate to the relevant content and verify the fix.
   - Ensure the scenario is deterministic and captures the specific issue found.

4. **Register Scenario**:
   - Add the scenario to the `scenarios_to_run` list.

5. **Verify**:
   - Run the test suite to ensure the review-related fix is working as expected and doesn't break other features.

## Template

```python
def scenario_review_content_name(agent: TestAgent):
    """
    Review Issue: [Description of issue found during review]
    Resolution: [How it was fixed or improved]
    """
    logger.info("Verifying content review fix: content_name...")
    
    # 1. Navigate to the content
    # agent.send_user_action("open_content_view")
    
    # 2. Trigger the logic that had the issue
    # agent.send_user_action("trigger_feature")
    
    # 3. Verify the resolution
    state = agent.get_all_information()
    assert state.get("property") == "correct_value", "Review issue resolution verification failed!"
```
