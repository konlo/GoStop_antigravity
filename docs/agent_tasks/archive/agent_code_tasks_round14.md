# Agent Code Tasks Round 14

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP/WebSocket parity smoke `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`: PASS
- server-owned automatic expiry is now the runtime source-of-truth for timeout completion
- app root already mounts a product-facing multiplayer route and gameplay transport is concrete

## Remaining Gaps
- create/join/bootstrap is still on the websocket command boundary; the cleaner public bootstrap split is still only a placeholder
- app-wide placement beyond the current root sheet is still open
- gameplay UI is usable, but captured zone, richer table targeting, and final board composition still need work
- some message catalog entries are still missing, so visible copy still falls back to shell text
- dropped-event gap based MP-008 future extension is still only a planned artifact, not an executable live path

## Round 14 Goal
- separate product bootstrap concerns from the websocket gameplay transport boundary
- improve product-facing multiplayer UX quality beyond the current working baseline
- turn the remaining gap-based resync work into a narrower executable target

## Recommended Order
1. Agent 2
2. Agent 3 in parallel on UI-only improvements
3. Agent 4 after Agent 2 exposes the next bootstrap/gap hook shape
4. Agent 1 support only if bootstrap/resync contract drift appears

## Parallel Guidance
- Safe to start together:
  - Agent 2
  - Agent 3
  - Agent 1 support
- Start after Agent 2 reports bootstrap split or gap-hook shape:
  - Agent 4

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round14.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- bootstrap split과 dropped-event gap follow-up에서도 authority contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- bootstrap split이 들어와도 authority event ordering과 snapshot source-of-truth가 바뀌지 않는다는 점을 문서 기준으로 확인해라.
- dropped-event gap 기반 future extension에서 `stateSnapshot(reason=gapDetected)` minimum recovery contract가 유지되는지 더 구체적으로 정리해라.
- Agent 2/4가 bootstrap/resync ambiguity를 올리면 contract owner로서 즉시 판단해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- bootstrap/resync contract 판단
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round14.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- current websocket command boundary에서 product bootstrap concerns를 더 명확히 분리해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- create/join/bootstrap current surface와 future public bootstrap split boundary를 protocol/API 레벨에서 더 명확히 분리해라.
- 가능하면 bootstrap-only entrypoint or facade를 추가해 gameplay websocket path와 책임을 나눠라.
- existing websocket gameplay transport semantics는 그대로 유지해 Agent 3/4가 regressions 없이 붙을 수 있게 해라.
- dropped-event gap future extension에서 transport가 어떤 hook/flag/artifact를 제공할 수 있는지 최소 shape를 정의해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 의미 변경

끝나면 보고:
- 변경 파일
- bootstrap split 진척
- gap-hook shape
- Agent 3/4가 바로 쓸 API 목록
- 남은 transport blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round14.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- working multiplayer route를 더 product-quality UX로 끌어올려라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- current root sheet baseline에서 더 app-wide tab/menu/home placement 후보를 코드와 문서로 정리해라.
- captured zone, richer table targeting, final board composition을 더 읽기 좋고 플레이하기 쉬운 방향으로 다듬어라.
- gameplay controls는 계속 authoritative transport lifecycle만 따르게 유지해라.
- product route에서 자주 보이는 문구는 message catalog 연결 또는 더 자연스러운 fallback으로 개선해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- lab-only 화면만 손보고 끝내기

끝나면 보고:
- 변경 파일
- app placement 진척
- gameplay UI polish 범위
- 남은 UI/product blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round14.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- bootstrap split 변화와 dropped-event gap follow-up을 smoke/artifact 관점에서 더 executable하게 만들어라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- Agent 2 bootstrap split/facade가 나오면 기존 parity suite가 깨지지 않는지 smoke를 추가하거나 강화해라.
- dropped-event gap 기반 MP-008 future extension을 executable scenario skeleton, preflight, or stricter artifact contract로 한 단계 더 줄여라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`는 계속 green인지 재검증해라.
- restricted 환경에서 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- bootstrap split 관련 smoke 결과
- MP-008 gap extension 진척
- 기존 parity suite 재검증 결과
- 아직 BLOCKED면 exact blocker
```
