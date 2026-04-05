# Agent Code Tasks Round 4

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- `scripts/run_multiplayer_cli_two_player_smoke.py --scenario all`: PASS
  - `ready-start`: PASS
  - `disconnect-resume`: PASS
  - `heartbeat-guard`: PASS
- `python3 tests/test_agent/multiplayer_runner.py --all-p0 --mode fixture`
  - `MP-001 ~ MP-007`: PASS
  - `MP-008`: BLOCKED

## What Is Actually Done
- authoritative multiplayer contract Swift types exist
- shake privacy fix is in place
- room/session/reconnect in-memory coordinator exists
- CLI room ingress exists
- DEBUG `MP Lab` can drive local room create/join/ready/gameStarted/disconnect/resume flow
- stale heartbeat guards exist and are covered by CLI smoke

## Main Gaps Left
- live route in `MP Lab` still uses a local placeholder projection instead of authoritative `gameStarted + stateSnapshot(reason=gameStarted)` payload
- CLI smoke still stops at `roomState=starting` + `requiresGameBootstrap=True` and does not yet assert the paired bootstrap payload
- `MP-008` deterministic fault injection hook is still undefined
- there is still no real WebSocket/server transport path for two actual clients

## Round 4 Goal
- move from `room/session debug flow exists` to `authoritative live bootstrap is actually consumed`
- unblock `MP-008`
- prepare a minimal real transport layer spike after local debug flow is trustworthy

## Agent 1
- replace `MP Lab` live placeholder dependency with a real local bootstrap helper returning `gameStarted + stateSnapshot(reason=gameStarted)`
- expose the smallest possible UI-facing bootstrap payload for Agent 3
- lock the resync contract needed for `MP-008`

## Agent 2
- connect room `.starting -> recordGameStarted -> bootstrap fetch` into one clear local debug service flow
- decide whether `recordGameStarted` stays explicit or becomes auto-triggered after both ready flags
- define the deterministic hook for `MP-008`
  - either `dropNextGameEvent(targetSessionId, count=1)`
  - or stale `expectedStateVersion` override

## Agent 3
- replace placeholder live shell state in `MP Lab` with authoritative bootstrap consumption
- make live route state derive from actual bootstrap payload instead of local defaults
- verify reconnect overlay still behaves correctly after authoritative live bootstrap is wired

## Agent 4
- extend CLI smoke to assert `room_record_game_started` plus paired bootstrap payload when Agent 1/2 wiring lands
- convert `MP-008` from BLOCKED to executable once hook is fixed
- keep manual checklist aligned with actual in-app flow

## Exit Criteria For Round 4
- `MP Lab` live route is no longer placeholder-only for initial bootstrap
- CLI smoke asserts paired `gameStarted + stateSnapshot(reason=gameStarted)`
- `MP-008` has a locked deterministic injection hook
- next phase can focus on real transport instead of local debug gaps
