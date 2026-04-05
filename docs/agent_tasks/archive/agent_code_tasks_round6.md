# Agent Code Tasks Round 6

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- `python3 scripts/run_multiplayer_cli_two_player_smoke.py --binary /tmp/gostop_cli_round6_review/Build/Products/Debug/GoStopCLI --scenario all`: PASS
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/test_agent/multiplayer_runner.py --all-p0 --mode fixture`: `MP-001 ~ MP-008` PASS
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/test_agent/multiplayer_runner.py --suite socket-smoke --mode socket --binary /tmp/gostop_cli_round6_review/Build/Products/Debug/GoStopCLI --skip-build`: PASS

## Review Summary
- No new blocking correctness regressions were found in the current local debug / CLI / socket-spike flow.
- The remaining work is mostly feature completion and productionization:
  - gameplay commands are not yet exposed through `room_transport_send`, so `MP-008` live gameplay resync is still blocked
  - `room_transport_*` is still a CLI spike, not a real websocket server binding
  - result dismissal still waits on a real `roomClosed` / leave-ack path
  - persisted session storage and real networking adapter are still not wired into the app shell

## Highest Priority Remaining Gaps
1. `room_transport_send` needs gameplay command support carrying `actionId` and `expectedStateVersion`.
2. actual websocket/server binding must preserve the same envelope ordering as the CLI transport spike.
3. app result route must finish the real `matchEnded -> roomClosed/leave ack -> dismiss` lifecycle.
4. socket runner should be resilient in offline/restricted environments by reusing a built binary or cached derived data.

## Next Tasks By Agent

### Agent 1
- Keep the contract lane stable and support transport completion work.
- Add relay-ready gameplay command examples for `playCard`, `submitChoice`, and `quit` over room transport.
- Decide whether dropped-event gap injection stays future work or becomes a Phase 6 extension after stale-version gameplay smoke lands.
- Verify `authority playerId` and room `playerId` mapping assumptions remain explicit in docs and sample payloads.

### Agent 2
- Extend `room_transport_send` to accept gameplay commands that carry `actionId`, `expectedStateVersion`, and command payload.
- Relay real Agent 1 engine envelopes (`actionAccepted`, `actionRejected`, `choiceRequested`, `statePatched`, `stateSnapshot`) through the transport spike.
- Add a real `leaveRoom` / `roomClosed` completion path so Agent 3 can close result flow authoritatively.
- Start replacing `room_transport_*` with an actual websocket/server binding while preserving current ordering and error codes.

### Agent 3
- Replace local debug-only result completion with actual `roomEvent.roomClosed` or explicit leave-ack handling.
- Wire persisted session storage and real networking adapter into `MultiplayerShellStore`.
- Verify `actorOnly` shake payload handling in the mapper/UI so redacted non-actor payloads never surface as errors.
- Finish localization and product copy for `matchEnded` and leave-completion states.

### Agent 4
- Promote `MP-008` from hook-attachment preflight to full socket gameplay resync smoke once Agent 2 exposes gameplay commands.
- Add socket smoke for `matchEnded -> terminalSummary -> roomClosed/leave ack`.
- Make socket runner offline-friendly by preferring `--binary` / cached build reuse before trying a fresh build.
- Keep fixture, CLI smoke, and socket-smoke green while transport implementation evolves.

## Recommended Order
1. Agent 2 starts first.
2. Agent 1 supports Agent 2 contract questions in parallel.
3. Agent 4 follows as soon as gameplay transport commands exist.
4. Agent 3 finishes real result dismissal and persistence wiring once Agent 2 event relay shape is stable.
