# Docs Layout

This repository keeps only active, high-signal documents at the root.
Generated work products, archived task prompts, and reports should live under `docs/`.

## Directories

- `docs/agent_tasks/active/`: current task prompts or temporary working notes that are still in play.
- `docs/agent_tasks/archive/`: completed round/task prompt files such as `agent_code_tasks*.md`.
- `docs/reports/`: issue investigation summaries and generated reports such as `anomaly_report.md`.
- `docs/logs/`: generated logs that should not live at the repository root.
- `docs/runbooks/`: operator-facing runbooks and repeatable procedures.
- `docs/decisions/`: durable design decisions or ADR-style notes.

## Root File Rule

Keep only these document types at the repository root:

- long-lived repository entry points such as `README.md`
- project workflow files such as `AGENTS.md` / `agents.md`
- current session tracker files such as `project_progress.md`
- a single active plan file when a task is still ongoing

Move generated or completed work documents into `docs/` once they are no longer active.
