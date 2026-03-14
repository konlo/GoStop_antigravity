# Agent Code Tasks Round 15

## Current Verified State
- `GoStopCLI` build: PASS
- `GoStop` iOS simulator build: PASS
- TCP/WebSocket parity smoke `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`: PASS
- server-owned automatic expiry is locked
- bootstrap facade alias and product-facing multiplayer route both exist

## Remaining Gaps
- actual REST/bootstrap split is still not implemented; current bootstrap surface is still a command facade alias
- dropped-event gap based MP-008 future extension is still not a live transport path
- app-wide placement beyond the current product sheet is still follow-up
- richer table-target gestures, final board composition parity, and remaining message catalog gaps are still follow-up

## Round 15 Goal
- turn bootstrap split from placeholder/facade into a more concrete boundary
- make dropped-event gap recovery executable on live transport
- push multiplayer UI from “working product route” toward “polished product route”

## Recommended Order
1. Agent 2
2. Agent 3 in parallel on UI-only polish
3. Agent 4 after Agent 2 exposes the live gap hook/bootstrap split surface
4. Agent 1 support only if bootstrap/gap contract drift appears

## Parallel Guidance
- Safe to start together:
  - Agent 2
  - Agent 3
  - Agent 1 support
- Start after Agent 2 reports live gap hook or concrete bootstrap split:
  - Agent 4

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round15.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- concrete bootstrap split과 live gap recovery hook이 들어와도 authority contract drift가 생기지 않도록 source-of-truth를 유지해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- bootstrap split이 concrete route가 되어도 canonical bootstrap pair와 snapshot source-of-truth가 바뀌지 않는다는 점을 유지해라.
- dropped-event gap live hook에서도 recovery minimum contract가 `stateSnapshot(reason=gapDetected)` 1회라는 점을 다시 잠가라.
- Agent 2/4가 live gap recovery artifact나 bootstrap ordering ambiguity를 올리면 contract owner로서 즉시 판단해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 자체 변경

끝나면 보고:
- 변경 파일
- bootstrap/gap contract 판단
- Agent 2/4 handoff
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round15.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- bootstrap facade를 더 concrete한 boundary로 만들고, dropped-event gap recovery용 live hook shape를 노출해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `room_bootstrap_*`가 future public bootstrap split placeholder를 넘어서 concrete boundary로 동작하도록 정리해라.
- gameplay websocket path와 bootstrap path의 책임 분리를 더 명확히 해라.
- dropped-event gap future extension을 위해 live transport에서 쓸 hook/flag/artifact surface를 실제로 추가하거나 최소 executable 형태로 노출해라.
- existing parity suite를 깨지 않게 유지하고, Agent 4가 바로 붙일 smoke path를 정확히 남겨라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- engine rule 의미 변경

끝나면 보고:
- 변경 파일
- bootstrap split concrete 진척
- live gap hook shape
- Agent 4 검증용 exact path
- 남은 transport blocker
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round15.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- current product route를 더 polished product experience로 끌어올려라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- current sheet baseline을 기준으로 app-wide placement 후보를 더 구체화하거나 실제 한 단계 더 올려라.
- richer table-target gestures, final board composition parity, captured zone readability를 더 다듬어라.
- message catalog miss가 잦은 주요 문구는 실제 catalog 연결이나 더 나은 fallback으로 개선해라.
- authoritative lifecycle 의존(`helloAck`, `roomSnapshot`, `leaveAcknowledged`, `roomClosed`)은 그대로 유지해라.

하지 말 것:
- transport protocol 재정의
- Python 테스트 수정
- lab-only 화면만 손보고 끝내기

끝나면 보고:
- 변경 파일
- app placement 진척
- board/UI polish 범위
- 남은 UI/product blocker
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round15.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- dropped-event gap recovery를 live smoke/artifact 수준으로 한 단계 더 executable하게 만들어라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- Agent 2 live gap hook이 나오면 MP-008 dropped-event path를 executable live scenario로 끌어올려라.
- bootstrap split concrete path가 기존 parity suite를 깨지 않는지 smoke를 보강해라.
- 기존 parity suite `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`는 계속 green인지 재검증해라.
- restricted 환경에서 cached binary reuse 우선 정책을 계속 유지해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- live gap recovery 진척
- bootstrap split smoke 결과
- 기존 parity suite 재검증 결과
- 아직 BLOCKED면 exact blocker
```
