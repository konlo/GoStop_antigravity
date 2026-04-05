# Agent Code Tasks Round 8

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- CLI smoke: PASS
- Fixture `MP-001 ~ MP-008`: PASS
- Socket TCP smoke `MP-001`, `MP-014`: PASS

## Carry-Over Blockers
- transport terminal path still blocks on `invalidAuthorityPayload(roundEnded)`
- live `MP-008` recovery snapshot reason is still `localPreview`, not `resync`
- authority `playerId` vs room `playerId` mapping is still open
- actual websocket/server binding is not finished; current live path is still the TCP `--room-transport-server` facade

## Round 8 Goal
- close the remaining transport terminal/resync blockers
- lock `playerId` mapping so live gameplay transport is stable
- move the app shell from debug-only boundaries toward the production adapter path

## Recommended Order
1. Agent 2
2. Agent 1 in parallel
3. Agent 4
4. Agent 3

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round8.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- Agent 2가 transport terminal/resync blocker를 닫을 수 있게 authority contract를 최종 고정해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- live stale-version recovery snapshot reason은 `resync`만 허용하는지 계약으로 못 박아라.
- authority `playerId`와 room `playerId`가 다를 때 어떤 필드가 authority identity를 유지하고, 어떤 레이어가 room identity lookup을 담당하는지 명시해라.
- `roundEnded`, `matchEnded`, `terminalSummary` transport relay에서 필수 field를 다시 좁혀 Agent 2가 `invalidAuthorityPayload(roundEnded)`를 닫을 수 있게 해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- 잠근 contract 결정
- Agent 2/4 handoff
- 남은 authority risk
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round8.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- Round 7 carry-over blocker를 실제 transport code에서 닫아라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/LocalRoomCoordinatorDebugService.swift
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `recordMatchEndedAndFetchTerminalSummary` transport path가 더 이상 `invalidAuthorityPayload(roundEnded)`로 막히지 않게 고쳐라.
- live stale-version gameplay path에서 recovery snapshot reason이 `localPreview`가 아니라 `resync`로 내려가게 고쳐라.
- authority `playerId` ↔ room `playerId` mapping layer 또는 transport guard를 실제 gameplay path에 넣어라.
- current TCP `--room-transport-server` facade를 actual websocket/server binding으로 치환할 첫 진입점을 추가하거나, 최소한 swap 가능한 server boundary를 만들어라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 변경

끝나면 보고:
- 변경 파일
- 닫은 blocker
- websocket/server binding 진척
- Agent 4 검증용 exact command sequence
- 남은 relay blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round8.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- store/app shell이 Agent 2의 production transport shape를 바로 소비할 수 있도록 boundary를 실제 코드로 정리해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `helloAck`, `roomSnapshot`, `gameEvent`, `matchEnded`, `leaveAcknowledged`, `roomClosed`를 store inbound event path에 production adapter로 꽂을 수 있게 boundary를 정리해라.
- persisted resume(`playerId`, `deviceId`, `resumeToken`)가 actual `hello resume` attach 요청으로 이어지게 wiring entrypoint를 구체화해라.
- result dismissal이 `leave ack` 또는 `roomClosed` authoritative signal에만 반응하도록 유지하고, debug-only path 의존을 줄여라.
- `match.end.*`, `match.result.leave.*`, `room.closed.*` localization 연결 포인트를 실제 UI state 기준으로 정리해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- local debug mock만 손봐서 넘기기

끝나면 보고:
- 변경 파일
- production adapter boundary 진척
- resume attach wiring 진척
- result dismissal authoritative 조건
- 남은 UI blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round8.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- Agent 2 수정 후 live transport blocker를 실제 smoke로 닫아라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- Agent 2 수정 후 `MP-002` socket terminal probe를 PASS로 끌어올려 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed`를 실제 transport 로그에서 assert해라.
- Agent 2 수정 후 `MP-008` live socket smoke에서 recovery snapshot reason이 정확히 `resync`인지 assert해라.
- `MP-013/014`를 current TCP facade 기준 actual transport 로그로 유지하고, websocket binding이 생기면 같은 assertion을 재사용할 수 있게 정리해라.
- restricted 환경에서도 깨지지 않게 socket runner의 cached binary reuse 우선 정책을 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트를 맞추기

끝나면 보고:
- 변경 파일
- MP-002 / MP-008 결과
- websocket reusable smoke 목록
- 아직 BLOCKED면 exact blocker
```
