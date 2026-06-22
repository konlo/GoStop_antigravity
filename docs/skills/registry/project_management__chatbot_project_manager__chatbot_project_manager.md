<!--
Copied skill source for documentation.
Original path: /Users/najongseong/git_repository/skills-registry/project_management/chatbot_project_manager/SKILL.md
Source group: registry
Skill name: chatbot_project_manager
Original relative directory: project_management/chatbot_project_manager
-->

---
name: chatbot_project_manager
description: Manage chatbot application projects end-to-end, especially agent routing, tool-calling, parsing failures, Streamlit or web UI validation, table context training/profile storage, regression scenarios, work logs, and release-ready verification. Use when a user asks to plan, debug, harden, review, or document a chatbot project or agent workflow.
---

# Chatbot Project Manager

## Purpose
Guide chatbot project work from request intake through diagnosis, implementation planning, validation, and persistent project logging. This skill is optimized for projects with LLM agents, tool calling, structured output parsers, routing/chaining, UI flows, and regression tests.

## When To Use
Use this skill for chatbot or agentic app work involving:

- Agent routing, chaining, orchestration, or handoff bugs.
- Tool-calling or structured-output parsing failures.
- Streamlit, web, or local UI validation for chatbot flows.
- Table/schema context training, profiling, or stateful data management for SQL/EDA chatbots.
- Regression scenarios for prompts, malformed model output, or state transitions.
- Project progress logging, work summaries, or handoff notes.
- Reliability hardening before a commit, PR, or release.

## Core Workflow

### 1. Ground The Current State
- Inspect `AGENTS.md`, project logs, and recent diffs before making assumptions.
- Identify the chatbot entrypoint, agent construction, prompt templates, tool registry, state/session handling, and tests.
- Preserve unrelated local changes. Do not revert files you did not intentionally modify.

### 2. Record The Request
- If a project logger is configured, update the project log before major work.
- Prefer a concise entry with request, actions, artifact updates, decisions, and outcome.
- If no logger exists, propose adding one only when persistent tracking would help the project.

### 3. Diagnose Agent Workflow Bugs
For agent or chatbot failures, check these surfaces in order:

1. User prompt and intent classification.
2. Router output and selected agent sequence.
3. Session state before and after rerun/retry.
4. Agent executor settings such as iteration limits, parsing error handling, and timeouts.
5. Prompt format instructions and examples.
6. Tool-call intermediate steps and tool observations.
7. Final answer rendering and artifact attachment.
8. Tests or scenario scripts that can reproduce the issue without external services.

### 4. Design Robust Fixes
Prefer structural guardrails over prompt-only fixes:

- Add bounded retry or iteration limits for agent loops.
- Detect repeated parser or tool errors and stop deterministically.
- Add a narrow fallback for common, safe cases.
- Keep fallbacks explicit, logged, and easy to test.
- Avoid broad behavior changes to unrelated agents.
- For visualization flows, verify a figure or artifact is actually produced, not just described.

### 5. Update System Prompts Safely
When changing a chatbot system prompt, treat the existing prompt as an active contract, not disposable text:

1. Locate every prompt layer that can affect the behavior: system prompt, developer or framework prompt, tool-format instructions, router prompt, examples, fallback messages, and parser guidance.
2. Compare the proposed prompt change against the current prompt before editing. Identify duplicate, contradictory, stale, or ambiguous instructions.
3. Remove or rewrite conflicting text in the existing prompt instead of appending another rule that competes with it.
4. Keep output-format instructions single-source and exact. Do not maintain multiple incompatible examples for the same schema.
5. Check that new instructions do not weaken tool-use requirements, safety checks, stop conditions, data assumptions, or user-facing language requirements.
6. Add or update regression tests for the exact prompt behavior being changed, including at least one negative case where valid behavior must still pass.
7. After editing, inspect the final rendered prompt or prompt template when practical to verify escaping, placeholders, and examples are valid.
8. Record the prompt decision and the removed or resolved conflict in the project log or handoff summary.

Do not apply a system prompt update if unresolved conflicts remain. First make the conflict explicit, choose the winning instruction, update the prompt, and then verify with tests or a dry-run scenario.

### 6. Manage Table Context Training
When adding or changing a `%table training`-style feature, treat the training file as a safe table profile contract, not a data dump. The goal is to help routing, SQL generation, EDA validation, and prompt construction understand the selected table without storing raw rows.

### 6A. Keep Data And Code Separate
For chatbot projects, data-related knowledge must be managed as external, loadable context rather than embedded in application code or static prompts. This applies to table schemas, column names, aliases, semantic labels, profile statistics, sample-derived insights, prompt examples tied to a dataset, domain mappings, saved SQL patterns, and runtime dataframe metadata.

Required structure:

- Store data context in separate files or managed stores, such as TableContext JSON, manifest files, override files, vector/doc stores, or other explicit context artifacts.
- Load the needed data context at runtime based on the selected table, dataset, tenant, workspace, or user session.
- Keep code responsible for generic orchestration, validation, parsing, loading, and execution only.
- Never hardcode dataset-specific columns, aliases, values, business meanings, or example rows into planner code, prompt templates, tests that represent production behavior, or routing logic.
- Treat static prompts as behavior contracts; inject data-specific summaries only after loading the relevant external context.
- If context is missing, stale, or for the wrong selected table, fail clearly or request training/reload instead of guessing from code.

Implementation rules:

- Maintain a clear boundary between `DataContext`/`TableContext` artifacts and executable code.
- Use canonical IDs and manifests to match a selected table or dataset to its context file before planning SQL, EDA, or visualization.
- Persist only safe, bounded metadata needed for behavior. Do not persist raw rows, unrestricted value lists, credentials, tokens, secrets, or user-private prompt history as data context.
- Add regression tests proving that a request succeeds only when the matching external context is loaded, and fails or reloads when the context is absent, schema-only, stale, or from another table.
- Include at least one static check or negative test that prevents reintroducing hardcoded dataset-specific column names or aliases into production planner/prompt code.

Store these fields:

- **Table identity**: canonical `table_fqn`, `catalog`, `schema`, `table`, `version`, `training_status`, `source`, `trained_at`, and optional `row_count`.
- **Column identity**: `name`, `dtype`, `semantic_type`, and optional `aliases` or domain labels.
- **Column quality/profile**: `nullable`, `null_count`, `distinct_count`, capped `top_values`, `min_value`, and `max_value`.
- **Operational metadata**: profile query count or method, profile limits, context source path, and enough manifest data to match a selected table back to its context file.
- **Validation hints**: whether each column is suitable for numeric distribution, categorical counts, datetime trend, boolean split, or text handling.

Do not store:

- Raw sample rows, full dataframe content, arbitrary user prompt history, credentials, tokens, connection strings, API keys, secrets, or unrestricted high-cardinality value lists.
- Values that can reveal sensitive data unless they are explicitly capped, aggregated, and needed for schema/profile behavior.

Use a canonical table key:

```text
canonical_table_key = catalog.schema.table
```

Normalize table identity before save and load so `bank_loan`, `default.bank_loan`, and `workspace.default.bank_loan` do not accidentally create incompatible profiles when catalog/schema are known. If canonicalization is impossible, fail clearly or create only a schema-only context.

Training implementation rules:

- Prefer bulk profile queries over per-column query loops.
- Keep top-values capped and skip or limit high-cardinality columns.
- Keep TableContext separate from the current query result dataframe state. A SQL result like `SELECT education, COUNT(*)...` must not replace the source table's trained context.
- Load the active table context when the selected table changes; if no trained file exists, create a schema-only context from preview/schema.
- Pass a compressed schema/profile summary into SQL and EDA prompts. Do not pass the full JSON unless needed.
- In prompts, explicitly tell the LLM to use only columns present in the active table context.

Regression tests should cover:

- Training file absence creates schema-only context.
- `%table training` uses the currently selected table.
- Raw/sample rows are not persisted.
- Column resolution uses TableContext rather than hardcoded column lists.
- Switching tables does not reuse another table's context.
- Aggregate SQL result data does not overwrite the source table context.
- Training SQL is bulk/capped, not one Databricks query per column.
- Canonical table matching works across short and fully-qualified table names when catalog/schema are available.

### 7. Test And Verify
At minimum, add or update tests for:

- The exact user prompt or malformed model output that triggered the bug.
- The state transition that previously failed.
- A negative case showing normal output is not incorrectly blocked.
- Any deterministic fallback path.

Use lightweight static tests when LLM, database, or UI dependencies are unavailable. When UI behavior matters and a browser skill/tool is available, validate the local app screen as a separate step.

### 8. Handoff Clearly
End with:

- Files changed.
- Behavior changed.
- Tests run and results.
- Anything not run and why.
- Remaining manual validation steps.

## Chatbot Project Checklist

- [ ] Request logged or logging decision recorded.
- [ ] Current routing/state/prompt/tool path inspected.
- [ ] System prompt changes were checked against existing prompt text for conflicts or ambiguity.
- [ ] Fix has an explicit stop condition for loops or retries.
- [ ] Fallbacks are narrow and observable.
- [ ] Exact prompt or failure transcript is captured in tests.
- [ ] Static tests can run without external LLM services where practical.
- [ ] UI validation path is documented when user-facing behavior changes.

## Common Artifacts

- `AGENTS.md`: project-level agent and skill instructions.
- `project_progress.md`: persistent request and progress log.
- `WORK_HISTORY.md`: historical bug notes and decisions.
- `test_scenario.py`: prompt routing, state transition, and regression scenarios.
- Prompt files: model-facing format, behavior rules, and conflict-resolved system prompt contracts.
- Agent executor files: retry, timeout, parser, and tool settings.

## Output Style
Keep updates direct and implementation-oriented. For reviews, lead with risks and file/line references. For implementation work, summarize the changed behavior and verification rather than restating the whole plan.
