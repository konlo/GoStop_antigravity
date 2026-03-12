# Agent Code Tasks Round 11

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP/WebSocket parity smoke `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`: PASS
- live duplicate `actionId` smoke `MP-004`: TCP/WebSocket compare PASS
- `MP Lab` and future product-preparation route now share the same transport-backed host/store boundary

## Remaining Gaps
- reconnect grace expiry does not yet drive an end-to-end `quit(reason=disconnectTimeout)` transport completion path
- stale socket heartbeat handling policy is not fully settled as a long-term transport/audit behavior, even though current reject parity is green
- product navigation is still not mounted outside `MP Lab`
- invite room share/join identifier shape is still not finalized beyond current room-backed join handling
- production gameplay card/choice send path still lacks a concrete `MultiplayerShellGameplayNetworkingAdapter`
- some localization still depends on shell fallback copy because message catalog entries are missing
- dropped-event gap-based MP-008 future extension is still not connected to live transport

## Round 11 Goal
- harden timeout/disconnect transport behavior so reconnect grace expiry produces authoritative match closure
- move the app shell from product-preparation scaffolding toward an actual product-facing multiplayer route
- keep duplicate/reconnect/privacy parity green while new timeout and gameplay entry paths are added

## Recommended Order
1. Agent 2
2. Agent 4 in tight loop with Agent 2
3. Agent 3
4. Agent 1 support only if timeout/heartbeat contract drift appears

## Parallel Guidance
- Safe to start together:
  - Agent 2
  - Agent 1 support
- Start after Agent 2 reports timeout path/API shape:
  - Agent 4
- Start after Agent 2 transport shape is stable enough for app mounting:
  - Agent 3

## Today Focus
- Agent 2: reconnect-timeout emit path, heartbeat policy, invite/share identifier boundary
- Agent 4: timeout/heartbeat live smoke and parity locking
- Agent 3: product route mount and concrete gameplay adapter path
- Agent 1: timeout/forfeit contract arbitration only if new ambiguity appears

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round11.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- reconnect-timeout / heartbeat hardening 단계에서 authority contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- reconnect grace expiry가 engine `quit(reason=disconnectTimeout)`로 들어갈 때 required terminal payload invariants를 다시 점검해라.
- timeout forfeit에서 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed`까지 어떤 authority fields가 반드시 유지돼야 하는지 sample payload와 notes로 보강해라.
- stale heartbeat handling에서 Agent 2/4가 contract ambiguity를 올리면 reject vs audit-only 기준을 authority owner 관점에서 문서 판단해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- timeout/heartbeat contract 판단
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round11.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- reconnect timeout/heartbeat hardening을 TCP/WebSocket 공통 transport path에서 end-to-end로 닫아라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- reconnect grace expiry가 실제 `quit(reason=disconnectTimeout)` gameplay command emit으로 이어지고, terminal/result fan-out까지 transport에서 관찰되게 해라.
- timeout path에서 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed` ordering이 기존 terminal semantics와 충돌하지 않게 고정해라.
- stale socket heartbeat를 current reject parity 그대로 유지할지, silent ignore + audit log로 바꿀지 결정하고 TCP/WebSocket 공통 path와 문서에 반영해라.
- app product flow가 쓸 invite/share identifier shape를 정리해라. `inviteCode`를 유지할지, roomId와 별도 share token을 둘지 명확히 남겨라.
- Agent 3가 gameplay path를 붙일 수 있게 `playCard`, `submitChoice`, `quit`를 실제 app-facing adapter가 쓰기 쉬운 command surface로 다시 명시해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 의미 변경

끝나면 보고:
- 변경 파일
- timeout/heartbeat 결정
- invite/share identifier 결정
- Agent 3/4가 바로 붙을 API 목록
- 남은 transport blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round11.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- shared transport route host를 실제 product-facing multiplayer entry로 한 단계 올리고, gameplay send path concrete adapter를 준비해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `MultiplayerTransportRouteHostView`를 `MP Lab` 밖에서도 실제로 mount할 수 있는 product route 진입점을 만들어라.
- Agent 2가 정리한 invite/share identifier shape를 받아 `Create Room`, `Join Invite`, `Resume` 흐름을 product-facing entry 기준으로 정리해라.
- `MultiplayerShellGameplayNetworkingAdapter` concrete 구현 또는 equivalent wiring을 추가해 future live gameplay send path가 `playCard`, `submitChoice`, `quit`로 이어질 수 있게 해라.
- result dismissal은 계속 `leaveAcknowledged` 또는 `roomClosed` authoritative signal에만 반응하게 유지해라.
- message catalog hit가 없을 때 shell fallback은 유지하되, product route에서 드러나는 핵심 copy는 raw key가 안 보이게 더 정리해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- debug-only route만 손봐서 끝내기

끝나면 보고:
- 변경 파일
- product route mount 진척
- gameplay adapter concrete 범위
- 남은 UI/product blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round11.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- timeout/heartbeat hardening이 live TCP/WebSocket transport에서 실제로 유지되는지 smoke와 artifact로 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- reconnect grace expiry -> `quit(reason=disconnectTimeout)` -> `roundEnded` / `matchEnded` / `terminalSummary` / `roomClosed`를 live TCP/WebSocket smoke로 추가하거나 강화해라.
- stale heartbeat behavior가 reject인지 audit-only인지 Agent 2 결정에 맞춰 TCP/WebSocket parity smoke를 잠가라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-004`, `MP-008`, `MP-013`, `MP-014`가 계속 green인지 같이 재검증해라.
- dropped-event gap 기반 MP-008 future extension을 바로 구현하지 못하더라도 executable preflight or artifact plan으로 더 좁혀라.
- restricted 환경에서 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- timeout/heartbeat live smoke 결과
- 기존 parity suite 재검증 결과
- MP-008 future extension 상태
- 아직 BLOCKED면 exact blocker
```
