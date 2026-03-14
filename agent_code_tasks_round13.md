# Agent Code Tasks Round 13

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP/WebSocket parity smoke `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`: PASS
- passive socket close is bound to the same disconnect tracking path as explicit disconnect
- product-facing multiplayer route wrapper is mounted at app root and gameplay transport baseline is concrete

## Remaining Gaps
- timeout completion still relies on explicit `reapExpiredState`; there is no server-owned automatic sweep/timer yet
- create/join/bootstrap is still on the websocket command boundary; cleaner split is still a placeholder
- deeper product navigation placement beyond the current root sheet is still open
- gameplay UI works, but richer card-art driven hand/table interaction and better choice visuals remain follow-up
- some message catalog entries are still missing, so visible copy still falls back to shell text
- dropped-event gap based MP-008 future extension is still only a preflight plan, not a live transport path

## Round 13 Goal
- remove manual timeout progression dependence by introducing server-owned expiry handling
- turn the current product-facing multiplayer route into a better-integrated app experience
- narrow the remaining resync/testing gaps without regressing the already-green parity suites

## Recommended Order
1. Agent 2
2. Agent 3 in parallel where transport shape is unaffected
3. Agent 4 after Agent 2 timer path stabilizes
4. Agent 1 support only if timer/resync contract drift appears

## Parallel Guidance
- Safe to start together:
  - Agent 2
  - Agent 3
  - Agent 1 support
- Start after Agent 2 reports automatic timeout path:
  - Agent 4

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round13.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- server-owned timeout sweep과 gap-based resync follow-up에서 authority contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- server-owned timeout sweep이 들어와도 terminal authority invariants가 바뀌지 않는다는 점을 문서 기준으로 확인해라.
- dropped-event gap 기반 MP-008 future extension에서 authority가 요구하는 minimum recovery contract가 변하지 않는지 점검해라.
- Agent 2/4가 timer-driven close semantics나 resync artifact ambiguity를 올리면 contract owner로서 즉시 판단해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- timer/resync contract 판단
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round13.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- timeout completion이 explicit `reapExpiredState` 호출에만 의존하지 않도록 server-owned expiry handling을 도입해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- TCP/WebSocket server runtime에서 disconnect grace/result TTL expiry를 자동으로 진행시키는 timer or sweep 경로를 추가해라.
- automatic expiry가 current same adapter path를 타서 `quit(reason=disconnectTimeout)` -> `terminalSummary` -> `roomClosed` ordering을 유지하게 해라.
- manual `reapExpiredState`는 debug/test hook으로 남기되, production/runtime semantics는 automatic path를 기준으로 문서화해라.
- create/join/bootstrap boundary가 계속 websocket command 기반인지, 다음 split placeholder가 뭔지 room protocol에 더 명확히 남겨라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 의미 변경

끝나면 보고:
- 변경 파일
- automatic timeout handling 내용
- Agent 4 검증용 exact smoke path
- 남은 transport blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round13.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- current product-facing multiplayer route를 앱 안에서 더 자연스러운 UX로 다듬고, gameplay surface를 한 단계 더 플레이 가능하게 만들어라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- current root sheet route를 기준으로 deeper tab/menu placement 또는 equivalent app-native navigation 위치를 정리해라.
- live gameplay에서 card-art driven hand/table interaction, choice presentation, actionable affordance를 더 직관적으로 다듬어라.
- product entry에서 `Create Room`, `Join Invite`, `Resume`, result dismissal이 여전히 authoritative lifecycle만 따르도록 유지해라.
- message catalog hit가 없는 구간은 계속 fallback을 쓰되, product surface에서 자주 보이는 문구는 catalog 연결이나 더 나은 fallback으로 개선해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- lab-only route만 손보고 끝내기

끝나면 보고:
- 변경 파일
- app integration/placement 진척
- gameplay UI 개선 범위
- 남은 UI/product blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round13.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- automatic timeout progression과 remaining resync gaps를 smoke와 artifact로 좁혀라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- manual `reapExpiredState` 없이도 automatic timeout progression이 live TCP/WebSocket에서 같은 terminal ordering을 유지하는지 smoke를 추가하거나 강화해라.
- websocket debug connect 경로의 stale heartbeat error envelope가 CLI ingress와 동일한 code를 유지하는지 별도 probe로 잠가라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`는 계속 green인지 재검증해라.
- dropped-event gap 기반 MP-008 future extension을 executable scenario skeleton이나 더 구체적인 artifact contract로 한 단계 더 줄여라.
- restricted 환경에서 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- automatic timeout parity 결과
- stale heartbeat code probe 결과
- MP-008 future extension 상태
- 아직 BLOCKED면 exact blocker
```
