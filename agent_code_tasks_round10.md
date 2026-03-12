# Agent Code Tasks Round 10

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP socket smoke `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`: PASS
- WebSocket parity smoke `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`: PASS
- `MP Lab > Transport` consumes the real websocket command boundary

## Remaining Gaps
- live duplicate `actionId` path still does not honor the locked contract on TCP/WebSocket
- exact resend should be `duplicateActionIdDisposition=exactReplay`, but live transport still falls into stale reject/resync
- conflicting reuse should be `actionRejected(code=actionIdConflict)`, but live transport still falls into the same stale reject path
- create/join still rides the websocket command boundary instead of a cleaner product-facing split
- product navigation is still mounted in `MP Lab`, not the main app route
- some multiplayer localization keys still fall back to raw key/detail text

## Round 10 Goal
- close `MP-004` live duplicate `actionId` semantics on both TCP and WebSocket
- keep existing parity suites green while Agent 2 changes transport behavior
- move the app shell one step closer to a product-facing multiplayer entry, without regressing authoritative lifecycle handling

## Recommended Order
1. Agent 2
2. Agent 4 in tight loop with Agent 2
3. Agent 3
4. Agent 1 support only if duplicate contract drift appears

## Today Focus
- Agent 2: fix transport duplicate-action resolution so it happens before stale-state rejection
- Agent 4: prove the fix in live TCP/WebSocket smoke and artifact comparison
- Agent 3: reduce `MP Lab`-only wiring and prepare the product path on top of the now-stable transport shape
- Agent 1: arbitrate contract only if Agent 2/4 surface ambiguity

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round10.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- duplicate `actionId` live transport semantics에서 contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- duplicate `actionId` resolution이 `staleStateVersion`보다 먼저 일어나야 한다는 rule을 sample payload와 note로 다시 잠가라.
- exact resend는 `duplicateActionIdDisposition=exactReplay`, conflicting reuse는 `actionRejected(code=actionIdConflict)`라는 source-of-truth를 다시 명시해라.
- Agent 2/4가 live parity mismatch artifact를 가져오면 contract owner로서 문서 판단을 바로 내려라.

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
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round10.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- `MP-004` live duplicate `actionId` blocker를 TCP/WebSocket 공통 transport path에서 닫아라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- gameplay transport에서 duplicate `actionId` 판정을 `staleStateVersion` reject보다 먼저 수행하게 고쳐라.
- exact resend일 때 이전 accepted/replayed envelope를 그대로 재전달해 `duplicateActionIdDisposition=exactReplay`가 live probe에 드러나게 해라.
- conflicting reuse일 때 `actionRejected(code=actionIdConflict)`를 반환하게 고쳐 stale reject/resync와 분리해라.
- TCP fallback과 websocket server가 같은 duplicate-action resolution path를 타도록 shared boundary를 유지해라.
- Agent 3가 후속으로 붙일 수 있게 create/join/attach/leave network API shape에 변화가 있으면 문서와 보고서에 명시해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 변경

끝나면 보고:
- 변경 파일
- 닫은 blocker
- duplicate actionId transport entrypoint 요약
- Agent 4 검증용 exact command sequence
- 남은 server blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round10.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- stable transport shape 위에서 `MP Lab` 전용 경계를 줄이고 product-facing multiplayer route 준비를 진행해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- current websocket command transport source를 `MP Lab` 전용이 아니라 future product entry에서도 mount 가능한 구조로 정리해라.
- create/join/resume/result dismissal path가 authoritative `helloAck`, `roomSnapshot`, `leaveAcknowledged`, `roomClosed`에만 반응하도록 유지하면서 product route 진입점 또는 TODO boundary를 코드로 남겨라.
- raw key/detail fallback이 남는 `match.end.*`, `match.result.leave.*`, `room.closed.*` 계열 localization 연결을 더 줄여라.
- Agent 2 duplicate-action fix 이후 live gameplay send path를 붙일 때 어떤 adapter 확장이 필요한지 명시해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- debug-only source만 손봐서 끝내기

끝나면 보고:
- 변경 파일
- product-facing route 준비 진척
- localization cleanup 범위
- 남은 UI blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round10.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- `MP-004` live duplicate `actionId` semantics를 TCP/WebSocket parity smoke로 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- TCP와 websocket 양쪽에서 `MP-004` live smoke를 PASS로 끌어올려라.
- exact resend는 `duplicateActionIdDisposition=exactReplay`, conflicting reuse는 `actionRejected(code=actionIdConflict)`를 실제 transport artifact에서 assert해라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`는 계속 green인지 같이 확인해라.
- TCP fallback과 websocket 결과를 같은 artifact layout에서 비교 가능하게 유지해라.
- restricted 환경에서 계속 재실행 가능하게 cached binary reuse 우선 정책을 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- MP-004 TCP/WebSocket 결과
- 기존 parity suite 재검증 결과
- 아직 BLOCKED면 exact blocker
```
