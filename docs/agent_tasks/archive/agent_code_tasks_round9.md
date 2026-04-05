# Agent Code Tasks Round 9

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- CLI smoke: PASS
- Fixture `MP-001 ~ MP-008`: PASS
- TCP socket smoke `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`: PASS

## Remaining Gaps
- actual websocket `--room-transport-websocket-server` still needs parity validation against the TCP fallback
- transport path still lacks duplicate `actionId` exact replay / conflict reject coverage
- app shell still does not consume a concrete websocket client through `MultiplayerShellNetworkingAdapter`
- create/join REST source and product navigation/leave completion are not mounted on the production source

## Round 9 Goal
- prove websocket parity with the already-green TCP transport path
- mount the first real app transport source on top of the existing shell/store boundary
- keep duplicate/reconnect/privacy regressions green while the transport layer changes

## Recommended Order
1. Agent 2
2. Agent 4 in tight loop with Agent 2
3. Agent 3
4. Agent 1 support only if contract drift appears

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round9.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- websocket parity 단계에서 contract drift가 생기지 않도록 authority envelope invariants를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- duplicate `actionId` exact replay / conflict reject가 websocket transport에서도 그대로 유지돼야 하는 contract 예시를 보강해라.
- websocket parity 중 authority `playerId` fields가 room identity와 혼동되지 않도록 sample payload와 notes를 점검해라.
- Agent 2/4가 parity mismatch를 발견하면 source-of-truth contract owner로서 문서 쪽 판단을 내려라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- contract drift 여부
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round9.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- `--room-transport-websocket-server`를 startup skeleton에서 actual parity-ready transport로 끌어올려라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- websocket server path가 TCP fallback과 동일한 `helloAck -> roomSnapshot -> roomEvent/gameEvent* -> terminalSummary` ordering을 보장하게 해라.
- stale heartbeat reject code parity(`invalidResumeState`, `staleConnectionId`)를 websocket path에서도 그대로 유지해라.
- duplicate `actionId` exact replay / conflict reject를 transport path에 노출해 Agent 4가 live regression으로 검증할 수 있게 해라.
- create/join/attach/leave lifecycle에서 app source가 바로 붙을 수 있는 최소 network API shape를 정리해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 변경

끝나면 보고:
- 변경 파일
- websocket parity 진척
- duplicate actionId transport entrypoint
- Agent 3/4가 바로 붙을 API 목록
- 남은 server blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round9.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- existing shell/store boundary 위에 첫 real transport source를 실제로 mount해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- concrete websocket client 또는 transport adapter를 `MultiplayerShellNetworkingAdapter`에 연결해라.
- create/join flow와 persisted resume attach를 production source에서 실제로 탈 수 있게 wiring해라.
- result route가 `leaveAcknowledged` / `roomClosed`를 받은 뒤 닫히는 product navigation path를 붙여라.
- localization key를 실제 UI rendering path에 연결해 placeholder copy를 줄여라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- debug-only source만 손봐서 끝내기

끝나면 보고:
- 변경 파일
- 실제 연결된 transport source 범위
- create/join/resume/result dismissal 진척
- 남은 product blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round9.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- websocket path가 TCP fallback과 실제로 같은 semantics를 유지하는지 parity smoke로 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- websocket path로 `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014` parity smoke를 추가하거나 기존 socket mode에 transport selector를 넣어라.
- duplicate `actionId` transport replay/conflict regression을 live smoke로 추가해라.
- TCP fallback과 websocket path 결과를 같은 artifact layout으로 비교 가능하게 정리해라.
- restricted 환경에서는 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- TCP vs websocket parity 결과
- duplicate actionId live regression 결과
- 아직 BLOCKED면 exact blocker
```
