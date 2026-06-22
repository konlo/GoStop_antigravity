# HALO Operating Flow

This runbook turns the GoStop harness into a mandatory operating loop.

```text
RTM -> Contract Gate -> Implementation -> E2E Evidence -> Loopback Log
```

Do not treat these as optional documentation. For medium or high-risk changes, each step should produce or update a file before the next step starts.

For multi-agent or cross-layer work, run the orchestrator agent flow first:

- `docs/runbooks/orchestrator_agent_flow.md`
- `docs/orchestrator_prompt_template.md`
- `docs/orchestrator_board.md`

## 1. RTM

Use `docs/rtm.md` as the single requirement trace table.

Before implementation:
- assign or reuse a requirement ID
- link the owner contract document
- link the planned validation scenario
- name the required artifact path or artifact class
- set status to `Contract Pending`

## 2. Contract Gate

Use `docs/change_contract_template.md` before editing code.

The contract must define:
- pre-state
- trigger
- expected post-state
- non-regression constraints
- evidence required for PASS
- exact validation command
- loopback target for likely failures

For large changes, user approval is required before implementation starts. Record approval in `docs/gate_checklist.md`.

## 3. Implementation

Implement only inside the layer allowed by the contract.

If the implementation needs a contract change:
- stop coding
- update the contract document
- update `docs/rtm.md`
- reopen the gate in `docs/gate_checklist.md`

## 4. E2E Evidence

Use `docs/e2e_evidence_log.md` after validation.

Terminal success alone is not enough for UI, multiplayer, bridge, device, or transport behavior. Record artifact paths such as:
- `summary.md`
- `timeline.jsonl`
- `action_log.jsonl`
- screenshots or recordings
- `anomaly_report.md`
- `transport_parity.json`

If real E2E is skipped, record the reason and risk explicitly.

## 5. Loopback Log

Use `docs/loopback_log.md` whenever validation fails.

Classify the first failing transition before another code edit:
- contract wrong
- probe wrong
- stale environment
- engine/API wrong
- UI/bridge propagation wrong
- transport/session wrong
- device/environment contract wrong

Do not make more than two consecutive edits in the same layer without recording a loopback decision.

## Done Criteria

A medium/high-risk change is not done until:
- `docs/rtm.md` has a row for it
- a change contract exists or is referenced
- gate status is approved or explicitly waived
- E2E evidence is recorded
- any failed run has a loopback entry
- `project_progress.md` summarizes the outcome
