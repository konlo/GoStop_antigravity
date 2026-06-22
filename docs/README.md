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

## HALO Operating Files

Medium/high-risk work should follow this flow:

```text
RTM -> Contract Gate -> Implementation -> E2E Evidence -> Loopback Log
```

- `docs/runbooks/halo_operating_flow.md`: required operating loop and done criteria.
- `docs/runbooks/orchestrator_agent_flow.md`: orchestrator agent duties, states, delegation rules, and stop conditions.
- `docs/orchestrator_prompt_template.md`: copyable prompt for starting an orchestrator session.
- `docs/orchestrator_board.md`: current orchestrator queue and decisions.
- `docs/harness_file_index.md`: role-based index of harness, orchestrator, contract, skill, validation, and artifact files.
- `docs/rtm.md`: requirement traceability matrix.
- `docs/change_contract_template.md`: copyable contract template for work starts.
- `docs/gate_checklist.md`: approval and waiver record.
- `docs/e2e_evidence_log.md`: artifact-backed PASS evidence index.
- `docs/loopback_log.md`: failure classification and return-phase decisions.

## Root File Rule

Keep only these document types at the repository root:

- long-lived repository entry points such as `README.md`
- project workflow files such as `AGENTS.md` / `agents.md`
- current session tracker files such as `project_progress.md`
- a single active plan file when a task is still ongoing

Move generated or completed work documents into `docs/` once they are no longer active.
