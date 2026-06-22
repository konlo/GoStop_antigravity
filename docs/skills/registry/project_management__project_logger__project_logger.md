<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/project_management/project_logger/SKILL.md
Source group: registry
Skill name: project_logger
Original relative directory: project_management/project_logger
-->

---
name: project_logger
description: Automatically record all user requests and project progress into a single log file.
---

# project_logger.skill

## Purpose
Ensure every user interaction, request, and project advancement is meticulously documented in a single `project_progress.md` file. This provides a clear audit trail and helps maintain context across sessions.

## 1. Skill Scope
This skill provides instructions for:
1. Initializing the `project_progress.md` file.
2. Logging every user request with a timestamp.
3. Documenting the agent's actions, decisions, and outcomes.
4. Keeping a persistent record of the project's journey.
5. Performing a "Daily Wrap-up" to summarize key issues and outline next steps for future sessions.

## 2. Usage Instructions

When this skill is active, the agent MUST follow these steps for **EVERY** request:

1. **Check for Log File**: Look for `project_progress.md` in the project root. If it doesn't exist, create it using the template provided below.
2. **Log the Request**: Before performing any major task, append the user's request to the log file.
25:    - Use the format: `## [YYYY-MM-DD HH:MM:SS] [Agent: <ID>] User Request: <Request Content>`
26: 3. **Log the Process & Artifacts**: During and after the task, document the steps taken and any artifact updates.
27:    - Use the format: `- **Action** [Agent: <ID>]: <Description of what was done>`
28:    - Use the format: `- **Artifact Update**: <Summary of changes in implementation_plan.md, task.md, etc.>`
29:    - Use the format: `- **Outcome**: <Result of the action>`
30: 4. **Update Status**: If the overall project status changes, update the "Current Status" section at the top of the file.
5. **Daily Wrap-up (End of Day/Session)**: When the user indicates the end of a session (e.g., "wrap up", "summarize today's work"):
   - Review all activities logged for the current date.
   - Provide a structured summary of the user requests, actions, and outcomes.
   - Summarize the **Key Accomplishments** and **Major Issues Encountered**.
   - Create or update the **Next Action Items** section with pending tasks, unresolved issues, or notes for the next development session.
   - Update the "Current Status" section to reflect the end-of-day state.

## 3. Log File Template (`project_progress.md`)

```markdown
# Project Progress Log

## Current Status
- **Last Updated**: [YYYY-MM-DD]
- **Status**: [In Progress / On Hold / Completed]
- **Summary**: [Brief summary of the current state]
- **Next Session Focus**: [Brief description of what needs to be done next]

---

## Next Action Items (Pending tasks for the next session)
- [ ] List specific, actionable tasks to pick up next.
- [ ] Note any unresolved issues here.

---

## Daily Wrap-ups

### [YYYY-MM-DD] Daily Summary
- **Key Accomplishments**: 
  - Log completed tasks.
- **Major Issues Encountered**: 
  - Log any blockers or significant issues, and how they were resolved or if they remain.

---

## Log Entries

### [2026-02-27 20:30:00] User Request: Create a Project Logger Skill
- **Action**: Created `project_management/project_logger/SKILL.md`.
- **Outcome**: Skill established to automate project logging.
```

## 4. Best Practices
- **Be Concise**: Write clear and actionable logs.
- **Stay Consistent**: Always use the same format for timestamps and headers.
- **Record Decisions**: If a significant design choice is made, document the rationale.
- **Link Resources**: Link to relevant artifacts or important code files in the log.
