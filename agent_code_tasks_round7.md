# Agent Code Tasks Round 7

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- `python3 scripts/run_multiplayer_cli_two_player_smoke.py --binary /tmp/gostop_cli_round7_review/Build/Products/Debug/GoStopCLI --scenario all`: PASS
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/test_agent/multiplayer_runner.py --all-p0 --mode fixture`: `MP-001 ~ MP-008` PASS
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/test_agent/multiplayer_runner.py --suite socket-smoke --mode socket --binary /tmp/gostop_cli_round7_review/Build/Products/Debug/GoStopCLI --skip-build`: `MP-001`, `MP-014` PASS

## Carry-Over Items From Yesterday
- Agent 2 / Agent 4 terminal path is still incomplete:
  - `recordMatchEndedAndFetchTerminalSummary` transport path still blocks with `invalidAuthorityPayload(roundEnded)` in the socket terminal probe.
- Agent 2 / Agent 4 resync path is still incomplete:
  - live `MP-008` reaches `actionRejected(staleStateVersion)` and recovery snapshot delivery, but the snapshot reason is still `localPreview`, not `resync`.
- Agent 2 / Agent 3 production path is still incomplete:
  - actual websocket/server binding is not finished; current live path is still the TCP `--room-transport-server` facade.
- Agent 1 / Agent 2 mapping contract is still open:
  - authority `playerId` vs room `playerId` mapping is not fully locked, and this still affects live gameplay command interpretation.

## Highest Priority Remaining Gaps
1. Fix transport terminal relay so `roundEnded`, `matchEnded`, and `terminalSummary` fan-out cleanly on the live socket path.
2. Fix recovery snapshot reason on live stale-version flow to `resync`.
3. Lock the authority-playerId <-> room-playerId mapping layer.
4. Replace the current TCP facade with the actual websocket/server binding.

## Next Tasks By Agent

### Agent 1
- Lock the contract for authority `playerId` vs room `playerId` mapping.
- Clarify whether transport-level recovery snapshots are ever allowed to use `localPreview`; if not, make `resync` the only valid reason for live stale-version recovery.
- Review terminal summary dependencies so Agent 2 knows exactly which `roundEnded` / `matchEnded` fields are mandatory on the transport path.

### Agent 2
- Fix `recordMatchEndedAndFetchTerminalSummary` so the live terminal socket path no longer fails with `invalidAuthorityPayload(roundEnded)`.
- Fix the live stale-version recovery path so the transport emits `stateSnapshot(reason=resync)` instead of `localPreview`.
- Implement the mapping layer or guard between room `playerId` and authority `playerId` so live gameplay commands are not dependent on local preview IDs.
- Continue replacing `--room-transport-server` TCP facade with the real websocket/server binding while preserving current envelope ordering and error parity.

### Agent 3
- Keep the app shell aligned with the production path instead of the debug-only path.
- Wire the future real networking adapter into the existing store boundary and persisted session resume flow.
- Finish authoritative result dismissal using `leave ack` / `roomClosed` from the real transport path.
- Finish localization hookup for `match.end.*`, `match.result.leave.*`, `room.closed.*`, and shake actor-only waiting copy.

### Agent 4
- Re-run and harden the socket terminal probe (`MP-002`) after Agent 2 fixes the `terminalSummary` blocker.
- Re-run and harden `MP-008` live socket smoke once the recovery snapshot reason is fixed to `resync`.
- Add actual transport regression coverage for `MP-013/014` on the TCP facade first, then on the real websocket binding.
- Keep socket runner execution reliable in restricted environments by continuing to prefer cached binary reuse over fresh builds.

## Recommended Order
1. Agent 2
2. Agent 1 in parallel for contract decisions
3. Agent 4 immediately after Agent 2 lands the transport fixes
4. Agent 3 after Agent 2 transport shape is stable enough for the real app adapter
