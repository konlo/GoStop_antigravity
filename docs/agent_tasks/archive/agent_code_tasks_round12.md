# Agent Code Tasks Round 12

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP/WebSocket parity smoke `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`: PASS
- reconnect-timeout terminal invariants and stale heartbeat explicit-reject policy are locked
- product-facing multiplayer transport host wrapper exists and gameplay transport baseline is concrete

## Remaining Gaps
- actual TCP/WebSocket connection close is still not automatically wired to `disconnectMember` without explicit `room_transport_send(action=disconnect)`
- main app navigation still does not mount the multiplayer product route outside `MP Lab`
- create/join still rides the websocket command boundary; no cleaner product bootstrap split yet
- gameplay transport exists, but richer hand-targeted controls and choice UI are still follow-up work
- some message catalog entries are missing, so product-facing copy still relies on shell fallback text
- dropped-event gap based MP-008 future extension is still not connected to live transport

## Round 12 Goal
- make passive socket close behave like authoritative disconnect in live transport
- move multiplayer from product-preparation wrapper to actual main app route usage
- improve player-facing gameplay controls while keeping transport parity green

## Recommended Order
1. Agent 2
2. Agent 4 in tight loop with Agent 2
3. Agent 3
4. Agent 1 support only if passive-disconnect contract drift appears

## Parallel Guidance
- Safe to start together:
  - Agent 2
  - Agent 1 support
- Start after Agent 2 reports passive-disconnect binding shape:
  - Agent 4
- Start after Agent 2 transport shape is stable enough for the app route:
  - Agent 3

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round12.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- passive socket close -> disconnectTimeout hardening 단계에서 authority contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- passive socket close가 결국 same authority `quit(reason=disconnectTimeout)` terminal invariants로 수렴해야 한다는 점을 다시 확인해라.
- room cleanup signal과 authority terminal payload의 correlation fields가 passive disconnect path에서도 유지되는지 sample note를 보강해라.
- Agent 2/4가 close semantics나 timeout correlation에서 ambiguity를 올리면 contract owner로서 바로 판단을 내려라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- passive-disconnect contract 판단
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round12.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- actual TCP/WebSocket connection close를 explicit `disconnect` command 없이도 authoritative disconnect 흐름으로 연결해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- 실제 TCP/WebSocket socket close 또는 equivalent transport teardown이 자동으로 `disconnectMember` / grace tracking으로 들어가게 binding을 추가해라.
- passive close 이후 `reapExpiredState` 또는 equivalent lifecycle이 same transport path에서 `quit(reason=disconnectTimeout)` -> terminal fan-out -> `roomClosed`로 이어지는지 정리해라.
- explicit `disconnect`와 passive close가 서로 다른 semantics를 만들지 않게 공통 path를 유지해라.
- app이 계속 쓸 create/join/bootstrap surface가 websocket command boundary인지, 이후 REST split placeholder인지 문서에 boundary를 더 명확히 남겨라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 의미 변경

끝나면 보고:
- 변경 파일
- passive close binding 내용
- Agent 4 검증용 exact smoke path
- 남은 transport blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round12.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- multiplayer product route를 실제 main app navigation에 올리고, gameplay UI를 조금 더 실제 플레이 가능한 수준으로 끌어올려라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `MultiplayerProductMultiplayerRouteView` 또는 equivalent product-facing entry를 main app navigation에 실제로 mount해라.
- current gameplay transport path 위에서 hand-targeted `playCard`, choice submit, quit UX를 더 실제 플레이 가능한 흐름으로 다듬어라.
- result dismissal은 계속 `leaveAcknowledged` 또는 `roomClosed` authoritative signal에만 반응하게 유지해라.
- shell fallback copy는 유지하되, product route에서 바로 보이는 주요 메시지는 message catalog 우선 사용 또는 더 자연스러운 fallback으로 정리해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- lab-only route만 손보고 끝내기

끝나면 보고:
- 변경 파일
- main app mount 진척
- gameplay UI 개선 범위
- 남은 product/UI blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round12.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- passive socket close가 live TCP/WebSocket transport에서 explicit disconnect와 같은 timeout semantics를 유지하는지 smoke로 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- explicit `disconnect`가 아니라 actual connection close 기반 `MP-007` live parity smoke를 추가하거나 강화해라.
- passive close 이후 `actionAccepted -> roundEnded -> matchEnded -> terminalSummary -> roomClosed` ordering이 TCP/WebSocket에서 같은지 artifact로 남겨라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`는 계속 green인지 재검증해라.
- dropped-event gap 기반 MP-008 future extension을 executable probe 또는 tighter artifact plan으로 더 좁혀라.
- restricted 환경에서 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- passive close timeout parity 결과
- 기존 parity suite 재검증 결과
- MP-008 future extension 상태
- 아직 BLOCKED면 exact blocker
```
