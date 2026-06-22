# Gate Checklist

Use this file to record human or maintainer decisions before expensive or risky steps.

Gate status values:
- `Pending`
- `Approved`
- `Waived`
- `Rejected`

| Gate ID | Req ID | Gate | Decision | Decider | Date | Evidence / Contract | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `G-HALO-001` | `HALO-001` | Create HALO operating flow docs | Approved | User request | 2026-06-14 | `docs/runbooks/halo_operating_flow.md` | User asked to reinforce the next-stage workflow. |
| `G-ORCH-001` | `ORCH-001` | Create explicit orchestrator agent harness docs | Approved | User request | 2026-06-19 | `docs/runbooks/orchestrator_agent_flow.md` | User asked to make it an orchestrator agent. |
| `G-HIDX-001` | `HIDX-001` | Create harness file index | Approved | User request | 2026-06-19 | `docs/harness_file_index.md` | User asked to organize all harness-related files. |

## Required Gates

Use these gates for medium/high-risk work:

- **Requirement Contract Approval**: before implementation starts.
- **Contract Change Approval**: before changing public protocol, state, event, or UI contract.
- **Real E2E Waiver Approval**: before skipping simulator/device/transport validation for user-visible behavior.
- **Merge / Finish Approval**: before declaring a multi-phase change complete.

## Gate Rules

- A missing gate is not approval.
- A waived gate must include the reason and residual risk.
- A rejected gate must stop implementation until the contract is revised.
- For small low-risk doc-only changes, the user request itself can be recorded as approval.
