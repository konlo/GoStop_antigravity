# Agent Code Tasks Round 17

## Finalization Rule
Round 17 is reserved for finish-only work.

Allowed:
- final bug fixes found by validation
- final documentation sync
- final build/test pass
- release/merge handoff notes

Not allowed:
- new architecture
- new UX surfaces
- new transport concepts
- new future-extension design beyond tiny doc notes

## Round 17 Goal
- produce a green final validation set
- leave only explicitly deferred backlog items
- make the branch merge-ready

## Required Outcome
- build green
- agreed parity suites green
- shipped scope and deferred scope clearly documented
- no unresolved blocker on the sync board

## Recommended Order
1. Agent 4
2. Agent 2 and Agent 3 only for fixups discovered by validation
3. Agent 1 final contract sign-off

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

이번 턴은 final sign-off 턴이다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round17.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 턴에서 할 일:
- final validation 결과를 보고 authority contract drift가 없는지 sign-off해라.
- shipped scope / deferred scope를 문서상 final wording으로 정리해라.

하지 말 것:
- 새로운 엔진 기능 추가

끝나면 보고:
- final contract sign-off 여부
- deferred backlog 정리
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

이번 턴은 fixup-only 턴이다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round17.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 턴에서 할 일:
- Agent 4 validation에서 드러난 transport/blocker fix만 처리해라.
- sync board와 room protocol을 final shipped scope 기준으로 정리해라.

하지 말 것:
- 새로운 transport architecture 추가

끝나면 보고:
- fixup 내용
- 남은 blocker 여부
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

이번 턴은 fixup-only 턴이다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round17.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 턴에서 할 일:
- Agent 4 validation에서 드러난 UI/blocker fix만 처리해라.
- shipped alpha UX 범위와 deferred UX 범위를 final wording으로 정리해라.

하지 말 것:
- 새로운 UX surface 추가

끝나면 보고:
- fixup 내용
- final UX sign-off 여부
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

이번 턴은 final validation 턴이다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round17.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 턴에서 할 일:
- final build/test/smoke matrix를 실행해라.
- `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014` 결과를 최종 보고해라.
- artifacts와 final validation summary를 정리해라.

하지 말 것:
- production 코드 수정

끝나면 보고:
- final PASS/FAIL matrix
- blocking issue 여부
- merge-ready 판단
```
