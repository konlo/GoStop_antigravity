# E2E Evidence Log

Use this file to record proof that a requirement passed in the relevant real environment.

| Evidence ID | Req ID | Scenario / Command | Environment | Artifact Path | PASS Signature | Reviewer | Date | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `E-HALO-001` | `HALO-001` | Document structure verification | Local repo docs | `docs/runbooks/halo_operating_flow.md`, `docs/rtm.md`, `docs/gate_checklist.md`, `docs/e2e_evidence_log.md`, `docs/loopback_log.md` | Required HALO flow files exist and are linked from docs | Codex | 2026-06-14 | Doc-only harness reinforcement; no app runtime E2E required. |
| `E-ORCH-001` | `ORCH-001` | Orchestrator harness document verification | Local repo docs | `docs/runbooks/orchestrator_agent_flow.md`, `docs/orchestrator_prompt_template.md`, `docs/orchestrator_board.md`, `docs/README.md` | Orchestrator runbook, prompt template, board, RTM row, gate row, and evidence row exist | Codex | 2026-06-19 | Doc-only orchestrator layer; no app runtime E2E required. |
| `E-HIDX-001` | `HIDX-001` | Harness file index verification | Local repo docs | `docs/harness_file_index.md`, `docs/README.md` | Harness index exists and is linked from docs README | Codex | 2026-06-19 | Doc-only index; no app runtime E2E required. |

## Evidence Rules

- Prefer artifact paths over prose.
- For UI and multiplayer, include both host and guest evidence when relevant.
- For simulator/device behavior, record device IDs, app build, ports, and transport URL.
- For failed runs, do not overwrite the evidence row; add a loopback entry.
- Terminal `PASS` without artifacts is weak evidence and should be marked as such.
