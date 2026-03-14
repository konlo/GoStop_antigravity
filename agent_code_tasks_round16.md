# Agent Code Tasks Round 16

## Finish Definition For 2-Turn Completion
To finish within two more rounds, the scope is frozen to the current alpha-ready multiplayer boundary:

- Ship the current command-based bootstrap boundary as the accepted Phase 0 product boundary
- Ship the current live gap recovery hook (`triggerGapRecovery -> gapRecoveryHint -> stateSnapshot(reason=gapDetected)`) as the accepted executable recovery path
- Ship the current product-facing multiplayer route on the existing root sheet baseline
- Keep TCP/WebSocket parity green for the locked suites

## Explicitly Deferred Beyond Round 17
- true public REST bootstrap split
- automatic dropped-event detection instead of explicit live gap hook
- app-wide remount beyond the current root sheet baseline
- richer final board parity beyond current captured/month-bucket polish
- full message catalog completeness

## Round 16 Goal
- freeze shipped scope so no more architecture expansion happens
- close the remaining “must-have” polish and regression gaps inside the accepted alpha boundary
- prepare Round 17 to be validation/merge-only as much as possible

## Required Outcome
- after Round 16, no open blocker should remain except final validation, merge packaging, or minor copy cleanups

## Recommended Order
1. Agent 2
2. Agent 3 in parallel
3. Agent 4 after Agent 2 reports the frozen shipped boundary
4. Agent 1 support only

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round16.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 작업 목표:
- 2턴 안 종료를 위해 authority contract를 더 넓히지 말고 현재 shipped boundary를 최종 계약으로 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- concrete bootstrap boundary와 explicit live gap recovery hook이 Phase 0 shipped contract임을 문서로 못 박아라.
- deferred scope(REST bootstrap split, automatic dropped-event detection)는 out-of-scope로 명시해라.
- Agent 2/4가 가져오는 artifact가 현재 contract와 어긋나면 즉시 drift 여부를 판정해라.

하지 말 것:
- SwiftUI 화면 수정
- Python 테스트 수정
- transport 구현 변경

끝나면 보고:
- 변경 파일
- 최종 계약으로 잠근 항목
- deferred 항목
```

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round16.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- 현재 bootstrap/gap boundary를 shipped Phase 0 boundary로 고정하고 더 이상 architecture를 벌리지 마라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `room_bootstrap_*` boundary를 final shipped Phase 0 surface로 문서와 코드에서 정리해라.
- `triggerGapRecovery` live hook, `gapRecoveryHint`, `stateSnapshot(reason=gapDetected)` path를 final accepted recovery path로 문서화하고 naming을 잠가라.
- parity suite를 깨지 않는 선에서 only bug-fix 수준 정리만 해라.
- Round 17이 validation-only가 되도록 API shape와 smoke entrypoint를 명확히 handoff로 남겨라.

하지 말 것:
- 새로운 REST layer 구현
- 새로운 transport architecture 도입
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- frozen bootstrap/gap boundary
- Agent 4 final validation path
- deferred transport work
```

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round16.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- current root-sheet product route를 shipped alpha UX로 마감해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- root sheet baseline을 shipped alpha placement로 정리하고, 더 큰 remount는 deferred로 명시해라.
- current board/captured/choice UI를 읽기 쉽고 실전 플레이 가능한 수준으로 마감해라.
- 자주 보이는 copy는 raw key 느낌이 안 나게 fallback 또는 catalog 연결을 정리해라.
- authoritative lifecycle 의존은 그대로 유지해라.

하지 말 것:
- app-wide 대규모 navigation refactor
- transport protocol 변경
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- shipped alpha UX 범위
- deferred UI work
- 남은 실제 blocker 여부
```

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_round16.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- Round 17을 final validation-only로 만들 수 있도록 executable regression path를 모두 잠가라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer_runner.py
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/multiplayer/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/

이번 턴에서 할 일:
- current frozen bootstrap boundary와 live gap recovery hook 기준으로 regression path를 정리해라.
- `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`가 final validation에서 바로 돌 수 있게 suite와 artifact 경로를 고정해라.
- Round 17에서 실행할 최종 validation checklist와 expected PASS criteria를 남겨라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 보고:
- 변경 파일
- final validation suite 목록
- expected PASS 기준
- 아직 남은 blocker
```
