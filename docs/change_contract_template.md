# Change Contract Template

Copy this template into `docs/agent_tasks/active/` or the relevant contract document before implementation starts.

## Contract Header

- **Req ID**:
- **Title**:
- **Owner**:
- **Date**:
- **Risk Level**: Low / Medium / High
- **Gate Status**: Pending / Approved / Waived / Rejected
- **Related RTM Row**:

## Requirement

Describe the user-visible behavior in one or two sentences.

## Pre-State

- Phase / route:
- Current player / actor:
- Room/session state:
- Snapshot or stateVersion:
- Relevant UI state:
- Existing artifact or reproduction:

## Trigger

- Command / action:
- Accepted action:
- Snapshot / event:
- User interaction:
- Seed / setup:

## Expected Post-State

- Fields that must change:
- Fields that must not change:
- UI evidence expected:
- Artifact evidence expected:

## Non-Regression Constraints

- Engine / rule constraints:
- UI / SwiftUI constraints:
- Transport / room constraints:
- Test-agent constraints:

## Allowed Implementation Scope

- Files / directories allowed:
- Files / directories not allowed:
- Required owner review:

## Validation Plan

- Build command:
- Unit / scenario command:
- Real E2E command:
- Artifact path:
- PASS signature:
- FAIL signature:

## Loopback Plan

If validation fails, classify first:
- contract wrong
- probe wrong
- stale environment
- engine/API wrong
- UI/bridge propagation wrong
- transport/session wrong
- device/environment contract wrong

Then update `docs/loopback_log.md` before additional edits.
