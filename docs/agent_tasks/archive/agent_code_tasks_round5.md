# Agent Code Tasks Round 5

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: FAIL
  - `GoStop/Views/MultiplayerShellViews.swift:1207`
  - `GoStop/Views/MultiplayerShellViews.swift:1271`
  - error: extraneous `}` at top level
- `python3 scripts/run_multiplayer_cli_two_player_smoke.py --binary /tmp/gostop_cli_status_check/Build/Products/Debug/GoStopCLI --scenario all`: PASS
  - `ready-start`: PASS with paired `room_record_game_started -> room_snapshot(inGame) -> get_multiplayer_game_started_bootstrap`
  - `disconnect-resume`: PASS
  - `heartbeat-guard`: PASS
  - `mp008-hook-surface`: PASS
  - `mp008-gameplay-resync`: PASS as hook-attachment preflight, not full socket gameplay resync
- `PYTHONDONTWRITEBYTECODE=1 python3 tests/test_agent/multiplayer_runner.py --all-p0 --mode fixture`: `MP-001 ~ MP-008` PASS

## Where Each Agent Stands

### Agent 1
- Done:
  - authoritative contract, bootstrap payloads, terminal payloads, stale-version resync contract
  - shake privacy redaction
  - starter/dealer truth
  - room-truth-aware presence slots
- Current status:
  - technically strongest area; no current compile/test blocker found
  - `agent_sync_board.md` still marks this lane `Ready For Merge: YES`
- Remaining:
  - replay artifact retention policy
  - transport/result phase support docs for Agent 2/3/4

### Agent 2
- Done:
  - room lifecycle/coordinator
  - CLI ingress
  - local debug service
  - heartbeat stale/replaced guard
  - explicit `recordGameStarted` + bootstrap plan
  - MP-008 stale-version hook surface
- Current status:
  - CLI path is healthy
  - websocket/server ingress and engine event relay are still not wired
- Remaining:
  - room terminal payload forwarder including `forfeitingPlayerId`
  - projection/bootstrap presence merge plumbing
  - actual transport binding surface

### Agent 3
- Done:
  - `MP Lab` can drive `create -> join -> ready -> gameStarted -> live -> disconnect -> resume`
  - authoritative bootstrap is consumed for live route entry
  - unsupported `Join Invite` is hidden in local debug mode
- Current status:
  - not merge-ready because current iOS build fails
- Remaining:
  - fix `MultiplayerShellViews.swift` brace regression
  - actual `matchEnded -> result` route binding
  - leave/roomClosed policy and persistence/real adapter follow-up
  - actor-only shake UI policy verification

### Agent 4
- Done:
  - fixture runner/scenarios/artifacts
  - CLI smoke coverage for bootstrap, reconnect, heartbeat guard, MP-008 hook surface
  - `MP-001 ~ MP-008`, `MP-013`, `MP-014` fixture baseline
- Current status:
  - fixture and CLI regression are solid
  - real socket transport smoke is still missing
- Remaining:
  - actual socket binding
  - actual gameplay resync smoke using MP-008 hook
  - websocket stale heartbeat envelope parity check

## Round 5 Goal
- restore `GoStop` app compile health
- move from local debug live-only confidence to real `matchEnded -> result` confidence
- start a minimal real transport spike so Agent 4 can stop relying only on fixture/CLI paths

## Recommended Order
1. Agent 3 hotfixes the current app compile failure first.
2. Agent 1 and Agent 2 run in parallel.
3. Agent 4 starts socket-binding groundwork against Agent 2's transport surface.
4. Agent 3 finishes result route wiring once Agent 2 terminal forwarder shape is stable.

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round5.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- result route / transport phase에서 흔들리지 않도록 terminal + replay contract를 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `matchEnded`, `roundEnded`, `get_multiplayer_terminal_summary`가 Agent 2 terminal forwarder와 Agent 3 result route에서 바로 쓸 수 있게 sample payload와 required fields를 더 명확히 고정해라.
- authority replay artifact retention policy를 결정하고 문서/board에 남겨라.
- websocket relay에서 그대로 써야 할 `stateSnapshot(reason=resync|gapDetected)` / reject detail envelope 예시를 보강해라.

하지 말 것:
- SwiftUI 화면 수정
- room/session transport 구현
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- 새로 잠근 terminal/replay contract
- Agent 2/3/4 handoff
- 남은 authority 리스크
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round5.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/socket_binding_design.md

이번 작업 목표:
- CLI/local debug에서 검증된 room semantics를 actual transport spike로 끌고 가고, result route에 필요한 terminal forwarder를 추가해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/LocalRoomCoordinatorDebugService.swift
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- room terminal payload forwarder를 추가해서 `matchEnded.forfeitingPlayerId`, winner/loser, settlement summary가 room/result consumer까지 전달되게 해라.
- `participantPresenceByPlayerId` merge가 bootstrap/projection preview와 transport relay 모두에서 빠지지 않게 entrypoint를 정리해라.
- websocket/server ingress spike 또는 equivalent transport facade를 추가해서 CLI와 같은 `invalidResumeState` / `staleConnectionId` semantics를 유지하게 해라.
- Agent 4가 socket smoke를 붙일 수 있게 최소 connect/send/receive surface를 명시해라.

하지 말 것:
- 카드 룰 판정 구현
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- 새 transport/terminal API
- Agent 4 socket smoke용 entrypoint
- 남은 relay 리스크
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round5.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- 현재 app compile regression을 먼저 고치고, local debug/result route를 실제 terminal payload 기준으로 연결해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `GoStop/Views/MultiplayerShellViews.swift`의 top-level brace mismatch를 먼저 해결해 `GoStop` iOS build를 green으로 만들어라.
- local debug 또는 mapped path에서 `matchEnded` authoritative payload를 받으면 `showResult`로 넘어가게 wiring해라.
- result 화면의 `Leave Room`은 실제 `roomClosed`/leave ack 전까지 misleading하지 않게 disabled 또는 explicit pending policy로 정리해라.
- stale한 copy나 banner가 있으면 현재 bootstrap reality에 맞게 정리해라.

하지 말 것:
- room/session transport semantics 재정의
- Python 테스트 수정
- 임시 mock으로만 문제를 숨기기

끝나면 보고:
- 변경 파일
- 닫은 build/review finding
- 실제 result route 진입 경로
- 남은 UI blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round5.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/socket_binding_design.md
- /Users/najongseong/git_repository/GoStop_antigravity/mp_008_gap_injection_design.md

이번 작업 목표:
- fixture/CLI green 상태를 유지하면서 actual socket transport smoke와 MP-008 live resync smoke 준비를 시작해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `--mode socket` 또는 equivalent live transport entry scaffold를 runner에 추가해라.
- Agent 2 transport surface가 생기면 stale heartbeat reject code parity(`invalidResumeState`, `staleConnectionId`) smoke를 붙여라.
- MP-008을 fixture-only가 아니라 actual gameplay resync smoke로 올리기 위한 scenario skeleton과 artifact assertions를 추가해라.
- current CLI smoke green 상태는 유지하고, socket smoke가 아직 preflight면 blocker를 명시해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- 추가한 socket/live smoke entry
- MP-008 live smoke 상태
- 남은 blocker
```
