# Requirement Traceability Matrix

Use this file as the top-level index from user intent to contract, implementation, validation, and evidence.

Status values:
- `Contract Pending`
- `Gate Pending`
- `Implementing`
- `Validation Pending`
- `PASS`
- `FAIL`
- `Loopback`
- `Deferred`

| Req ID | User Request / Goal | Owner | Contract / Gate | Implementation Scope | Validation Scenario / Command | Latest Evidence | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `HALO-001` | Make every meaningful change follow `RTM -> Contract Gate -> Implementation -> E2E Evidence -> Loopback Log`. | Harness / PM | `docs/runbooks/halo_operating_flow.md`, `docs/gate_checklist.md` | `docs/` harness files only | Document review; `rg` for required flow files | `docs/e2e_evidence_log.md` row `E-HALO-001` | `PASS` | Bootstrap row for the HALO operating flow itself. |
| `ORCH-001` | Create an explicit orchestrator agent layer for the HALO harness. | Orchestrator | `docs/runbooks/orchestrator_agent_flow.md`, `docs/orchestrator_prompt_template.md` | `docs/` harness files only | Document review; `rg` for orchestrator files and links | `docs/e2e_evidence_log.md` row `E-ORCH-001` | `PASS` | Converts the previous manual PM layer into an executable orchestrator prompt/runbook. |
| `HIDX-001` | Create a role-based index of all harness-related files. | Orchestrator | `docs/harness_file_index.md`, `docs/README.md` | `docs/` harness files only | Document review; `rg` for index headings and README link | `docs/e2e_evidence_log.md` row `E-HIDX-001` | `PASS` | Central file map for harness, orchestrator, contracts, skills, validation code, and evidence. |

## Row Rules

- Create a row before implementation for medium/high-risk work.
- Keep one row per user-visible requirement or regression fix.
- Link concrete files, commands, and artifact paths. Avoid vague phrases like "tested manually".
- If a requirement changes, keep the old row and add a note; do not silently rewrite history.
- If validation fails, set status to `Loopback` and add a matching row in `docs/loopback_log.md`.
