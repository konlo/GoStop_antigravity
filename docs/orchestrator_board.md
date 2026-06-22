# Orchestrator Board

This board tracks the orchestrator's current queue and decisions.

For multi-agent implementation state, continue using `agent_sync_board.md`. This file is for HALO orchestration decisions before and after specialist work.

## Current State

- **Date**: 2026-06-19
- **Mode**: Orchestrator layer bootstrap
- **Active Req ID**: `ORCH-001`
- **Current State**: `PASS`
- **Primary Runbook**: `docs/runbooks/orchestrator_agent_flow.md`

## Queue

| Req ID | Request | Risk | Owner Lane | Current State | Next Action |
| --- | --- | --- | --- | --- | --- |
| `ORCH-001` | Create an explicit orchestrator agent harness. | Low | Orchestrator | `PASS` | Use `docs/orchestrator_prompt_template.md` for future orchestrator sessions. |

## Decision Log

| Date | Req ID | Decision | Reason | Evidence |
| --- | --- | --- | --- | --- |
| 2026-06-19 | `ORCH-001` | Add runbook, prompt template, and board instead of production code. | User asked for orchestrator agent behavior; current need is harness orchestration, not app runtime behavior. | `docs/runbooks/orchestrator_agent_flow.md`, `docs/orchestrator_prompt_template.md` |

## Open Contract Questions

- None.

## Handoff Notes

- Future orchestrator sessions should start from `docs/orchestrator_prompt_template.md`.
- Medium/high-risk product changes should not skip `docs/rtm.md`, `docs/change_contract_template.md`, `docs/gate_checklist.md`, and evidence/loopback logs.
