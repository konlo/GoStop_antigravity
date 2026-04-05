# Agent Code Tasks Round 3

## Phase
- `Phase 3 / Review Follow-Ups`

## Review Findings Driving This Round
- `RF-001`: `MultiplayerLocalDebugShellSource`는 실제 2인 ready/start/live 경로를 끝까지 못 탄다. guest ready/action path가 없고, room `.starting` 이후에도 `showLive`로 넘어가지 않는다.
- `RF-002`: entry의 `Join Invite`는 local debug source에서 기존 room 없이 `joinGuest()`를 호출해 즉시 에러로 떨어진다.
- `RF-003`: app 내부 debug flow는 guest `hello` attach와 `recordGameStarted`를 타지 않아 CLI ingress와 다른 semantics로 움직인다. 이 상태로는 in-app connect test가 실제 transport recovery 문제를 충분히 드러내지 못한다.

## Round 3 Goal
- DEBUG 앱 안에서 `create -> host hello -> guest join -> guest hello -> host ready -> guest ready -> gameStarted -> live route -> disconnect -> resume`까지 실제 coordinator/contract 기준으로 보이게 만든다.
- CLI smoke와 iOS/CLI build green 상태를 유지한다.

## Validation Baseline
- `GoStopCLI` build: PASS
- `GoStop` iOS build: PASS
- `scripts/run_multiplayer_cli_two_player_smoke.py --scenario all`: PASS

## Agent 1: Core Engine / Live Bootstrap Contract

### Objective
- room `.starting`에서 live route로 넘어갈 때 Agent 3가 임시 mock state 대신 authoritative bootstrap payload를 쓸 수 있게 최소 helper를 제공한다.

### Copy-Paste Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

이번 작업 목표:
- Agent 3가 local debug flow에서 room `.starting` -> live route 전환 시 mock live state 대신 authoritative bootstrap payload를 쓸 수 있게 helper와 contract를 정리해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/TestControlSupport.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- local debug path에서 바로 쓸 수 있는 `gameStarted + stateSnapshot(reason=gameStarted)` helper를 정리해라.
- Agent 3가 `showLive`로 넘어갈 때 필요한 최소 payload 세트를 문서와 코드 이름으로 맞춰라.
- existing multiplayer contract를 깨지 말고 iOS debug source가 바로 소비 가능한 entrypoint를 제공해라.

하지 말 것:
- room/session coordinator 구현
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- local live bootstrap helper/API
- Agent 3 handoff
- 남은 contract 리스크
```

## Agent 2: Local Debug Service / Room Truth

### Objective
- `LocalRoomCoordinatorDebugService`가 CLI ingress와 같은 semantics를 타게 보강한다.

### Copy-Paste Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

이번 작업 목표:
- app 내부 debug flow가 CLI ingress와 최대한 같은 room semantics를 타게 local debug service를 보강해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/LocalRoomCoordinatorDebugService.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- guest용 `hello` attach 경로를 local debug service에서 명시적으로 제공해라.
- room `.starting`에서 `.inGame`으로 넘길 `recordGameStarted` helper를 local debug service에 노출해라.
- 필요하면 guest ready convenience API도 추가해라.
- CLI ingress와 app debug service가 다른 semantics를 쓰지 않게 문서에 정리해라.

하지 말 것:
- 카드 룰 판정 구현
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- 추가된 local debug service API
- CLI와 맞춘 semantics
- Agent 3가 바로 호출할 메서드 목록
```

## Agent 3: MP Lab End-to-End Flow

### Objective
- review findings `RF-001`, `RF-002`를 직접 닫는다.

### Copy-Paste Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

이번 작업 목표:
- `MP Lab`이 실제로 `create -> join -> ready -> start -> live -> disconnect -> resume` 흐름을 보이게 해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellState.swift
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/MultiplayerShellViews.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- local debug source에 `Guest Ready`와 `Apply gameStarted` 또는 동등한 실제 flow control을 추가해라.
- room state가 `.inGame`으로 바뀌면 `showLive`로 넘어가고, disconnect/resume overlay도 live route 기준으로 유지되게 해라.
- entry의 `Join Invite`가 무조건 실패하지 않게 하거나, local debug source에서 unsupported면 노출 자체를 막아라.
- room/live/error 배너가 local debug semantics와 모순되지 않게 정리해라.

하지 말 것:
- 룰 판정을 UI에 넣기
- coordinator semantics 재정의
- Python 테스트 수정

끝나면 보고:
- 변경 파일
- 닫은 review finding ID
- 실제로 가능한 end-to-end flow
- 아직 mock으로 남은 부분
- 필요한 Agent 1/2 handoff
```

## Agent 4: Regression / Manual Verification

### Objective
- 이번 리뷰 findings를 다시 못 놓치게 검증 체계를 보강한다.

### Copy-Paste Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

이번 작업 목표:
- review findings `RF-001 ~ RF-003`가 다시 생기면 바로 드러나게 regression과 manual checklist를 보강해라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- CLI smoke 결과에 `guest ready -> gameStarted` expectation을 추가할 수 있는지 검토하고 필요한 TODO를 남겨라.
- in-app local debug manual checklist를 `create/join/ready/start/live/disconnect/resume` 기준으로 구체화해라.
- `Join Invite` unsupported/error behavior가 의도인지 아닌지 검증 포인트로 남겨라.
- privacy/session-hardening regression과 MP-008 unblock 상태를 같이 업데이트해라.

하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI를 임시 수정해서 테스트 맞추기

끝나면 보고:
- 변경 파일
- 추가/수정한 regression or checklist
- 실행한 smoke/fixture 결과
- 남은 blocker
```
