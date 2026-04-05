# Agent Code Tasks Round 2

## Phase
- `Phase 2 / In-App Debug Connect`

## Goal
- 사용자가 `게임 화면 안에서 멀티플레이 접속 흐름`을 직접 눌러볼 수 있게 한다.
- 이번 라운드의 목표는 `실제 인터넷 서버 완성`이 아니라, `DEBUG 앱 내부에서 room create/join/ready/disconnect/resume` 흐름이 실제 coordinator를 타고 움직이는 것`이다.
- 현재 `MP Lab`은 mock shell이고, 실제 room/session ingress는 `GoStopCLI`에서만 동작한다. 이번 라운드는 그 간극을 줄이는 데 집중한다.

## Non-Goals
- 실제 WebSocket 서버 배포
- production matchmaking 완성
- 인증/계정 시스템 추가
- full persistence/DB 추가

## Shared Rules
- Agent 1은 hidden-info/privacy와 authoritative payload truth를 먼저 잠근다.
- Agent 2는 room/session coordinator를 앱에서도 쓸 수 있게 분리하거나 공유 surface를 만든다.
- Agent 3는 mock-only transition을 줄이고, DEBUG `MP Lab`을 실제 local debug coordinator에 연결한다.
- Agent 4는 새 debug connect 흐름이 깨지지 않게 regression과 smoke를 추가한다.

## Round 2 Acceptance
- DEBUG 앱에서 `MP Lab` 또는 동등한 진입점으로 들어가 room create/join/ready/disconnect/resume 흐름을 실제 state source로 확인할 수 있다.
- `GoStopCLI` 경로는 기존처럼 계속 동작한다.
- shake privacy, stale heartbeat, starter/dealer payload 관련 review issue가 줄어든다.
- 테스트/스크립트가 새 흐름을 재현 가능하게 남는다.

## Agent 1: Core Engine / Authority Contract

### Objective
- authoritative payload를 실제 UI/debug adapter가 믿고 사용할 수 있게 정리한다.
- review findings `F-001`, `F-002`, `F-004`를 우선 닫는다.

### Files To Touch
- `GoStop/Core/`
- 필요 시 `GoStopCLI/`
- `multiplayer_contract.md`
- `agent_sync_board.md`

### Concrete Tasks
- `askingShake` choice payload가 non-actor에게 raw hand metadata를 주지 않게 viewer-scoped로 수정
- projection의 `isConnected/isReady` hardcode를 제거하거나, room truth merge contract를 문서/타입으로 명확히 고정
- `dealerPlayerId` 또는 equivalent starter field가 실제 starter selection 결과를 따르게 수정
- Agent 3가 room/game snapshot을 안전하게 합칠 수 있게 truth ownership을 `multiplayer_contract.md`에 분명히 적기

### Acceptance
- shake privacy leak이 payload shape 수준에서 막힌다
- starter/dealer field가 seat 0 고정이 아니다
- UI가 engine truth와 room truth를 헷갈리지 않게 contract가 정리된다

### Copy-Paste Prompt
```text
너는 Agent 1이다. [agent_prompts/agent1_core_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent1_core_prompt.md)의 역할을 따른다.

이번 작업은 Round 2 / In-App Debug Connect이다.
1차 목표는 authoritative payload review fixup을 끝내서 Agent 2/3가 앱 안 debug connect 흐름을 실제 state로 붙일 수 있게 만드는 것이다.

이번 턴의 수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `askingShake` choice payload를 viewer-scoped로 고쳐 non-actor에게 raw hand metadata가 가지 않게 해라.
- projection의 `isConnected/isReady` hardcode를 제거하거나 room truth merge contract를 타입/문서로 고정해라.
- `dealerPlayerId` 또는 equivalent starter field가 실제 starter selection 결과를 따르도록 수정해라.
- Agent 3가 room snapshot + game snapshot을 merge할 때 truth ownership을 헷갈리지 않게 문서에 남겨라.

이번 턴에서 하지 말 것:
- room/session coordinator 대규모 구현
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면 아래 형식으로 보고해라:
- 변경 파일
- 닫은 review finding ID
- payload/contract 변경점
- Agent 2/3/4 handoff
- 남은 리스크
```

## Agent 2: Backend / Local Debug Coordinator

### Objective
- room/session/reconnect coordinator를 `GoStopCLI` 전용 골격에서 끝내지 말고, DEBUG 앱에서도 쓸 수 있는 local debug service로 노출한다.
- 게임 화면 내부 접속 테스트의 기반을 만든다.

### Files To Touch
- `GoStopCLI/`
- 필요 시 `GoStop/` shared layer 또는 공용 Swift 파일
- `room_protocol.md`
- `agent_sync_board.md`

### Concrete Tasks
- `RoomCoordinatorModels` / `InMemoryRoomCoordinator`를 앱 target에서도 재사용 가능하게 분리 또는 target 편입 정리
- DEBUG 앱이 직접 호출할 수 있는 local debug service/store API를 정의
- `create/join/hello/ready/disconnect/resume/heartbeat/snapshot`를 UI-friendly method surface로 감싼다
- `recordHeartbeat`에서 replaced/expired/stale `connectionId` guard를 강화한다
- CLI ingress는 깨지지 않게 유지한다

### Acceptance
- DEBUG 앱 코드에서 room coordinator를 직접 사용할 수 있다
- stale heartbeat가 최신 세션을 덮어쓰지 않는다
- CLI 경로와 app debug 경로가 같은 coordinator truth를 사용한다

### Copy-Paste Prompt
```text
너는 Agent 2이다. [agent_prompts/agent2_backend_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent2_backend_prompt.md)의 역할을 따른다.

이번 작업은 Round 2 / In-App Debug Connect이다.
1차 목표는 room/session coordinator를 DEBUG 앱 내부에서도 쓸 수 있게 local debug service 형태로 노출하는 것이다.

이번 턴의 수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `RoomCoordinatorModels` / `InMemoryRoomCoordinator`를 app target에서도 재사용 가능하게 분리하거나 target membership을 정리해라.
- DEBUG 앱이 직접 호출할 수 있는 local debug service 또는 facade를 만들어 `create/join/hello/ready/disconnect/resume/heartbeat/snapshot` API를 제공해라.
- `recordHeartbeat`에서 replaced/expired/stale `connectionId` guard를 강화해 newest-wins 정책을 유지해라.
- 기존 `GoStopCLI` ingress는 깨지지 않게 유지해라.

이번 턴에서 하지 말 것:
- 카드 룰 판정 구현
- SwiftUI 화면 대규모 수정
- Python 테스트 수정

끝나면 아래 형식으로 보고해라:
- 변경 파일
- 새 local debug service/API 목록
- 닫은 review finding ID
- Agent 3가 바로 호출할 entrypoint
- 남은 blocker
```

## Agent 3: iOS MP Lab Wiring

### Objective
- `MP Lab`을 mock-only host에서 벗어나게 해서, 실제 local debug coordinator를 눌러가며 room connect 흐름을 볼 수 있게 만든다.

### Files To Touch
- `GoStop/Views/`
- 필요 시 `GoStop/ViewModels/` 또는 UI state layer
- `multiplayer_ui_flow.md`
- `agent_sync_board.md`

### Concrete Tasks
- `MultiplayerShellStore`를 pluggable source 구조로 정리
- DEBUG `MP Lab`에서 `Create Room`, `Join Guest`, `Ready`, `Disconnect`, `Resume`, `Heartbeat`를 실제 local debug service에 연결
- room snapshot이 바뀌면 ready/presence/banners를 실제 snapshot 기준으로 갱신
- mock reconnect 연출만 하던 부분을 실제 room state 변화와 맞춘다
- payload가 비어 있는 부분은 임의 필드 생성 대신 blocker로 남긴다

### Acceptance
- DEBUG 앱 안에서 버튼을 눌러 room state가 실제 coordinator state로 움직인다
- presence/ready가 mock truth가 아니라 room snapshot truth를 따른다
- shake choice/privacy 전제를 깨는 UI 의존이 없다

### Copy-Paste Prompt
```text
너는 Agent 3이다. [agent_prompts/agent3_ios_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent3_ios_prompt.md)의 역할을 따른다.

이번 작업은 Round 2 / In-App Debug Connect이다.
1차 목표는 DEBUG `MP Lab`을 local mock host에서 실제 local debug coordinator를 타는 연결 테스트 화면으로 바꾸는 것이다.

이번 턴의 수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/ViewModels/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `MultiplayerShellStore`를 pluggable source 구조로 정리해 mock 전용 흐름에서 벗어나게 해라.
- DEBUG `MP Lab`에서 `Create Room`, `Join Guest`, `Ready`, `Disconnect`, `Resume`, `Heartbeat`를 실제 local debug service 호출로 연결해라.
- room snapshot truth를 기준으로 ready/presence/banner가 바뀌게 해라.
- reconnect 연출이 실제 room state 변화와 모순되지 않게 정리해라.
- payload가 비어 있으면 임의 필드를 만들지 말고 blocker를 문서와 sync board에 남겨라.

이번 턴에서 하지 말 것:
- 룰 판정을 UI에 넣기
- server/session lifecycle 재정의
- Python 테스트 수정

끝나면 아래 형식으로 보고해라:
- 변경 파일
- 실제 연결된 UI action 목록
- 아직 mock으로 남은 부분
- Agent 1/2에 필요한 payload or API 요청
- 남은 UX 리스크
```

## Agent 4: Regression / Smoke / Manual Checklist

### Objective
- 새 debug connect 흐름과 기존 CLI ingress를 함께 검증한다.
- review findings와 reconnect 경로가 다시 깨지지 않도록 regression을 보강한다.

### Files To Touch
- `tests/test_agent/`
- `scripts/`
- `multiplayer_test_scenarios.md`
- `agent_sync_board.md`

### Concrete Tasks
- `run_multiplayer_cli_two_player_smoke.py`를 기반으로 assert 강화 또는 companion regression 추가
- shake privacy leak regression 추가
- stale/replaced heartbeat regression 추가
- `MP-008` fault injection unblock 질문을 더 좁힌다
- 앱 내부 debug connect 수동 점검 체크리스트를 문서에 추가한다

### Acceptance
- CLI smoke가 `ready-start`와 `disconnect-resume`를 계속 보장한다
- privacy/session-hardening regression이 코드에 등록된다
- 수동 앱 검증 체크리스트가 남는다

### Copy-Paste Prompt
```text
너는 Agent 4이다. [agent_prompts/agent4_test_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent4_test_prompt.md)의 역할을 따른다.

이번 작업은 Round 2 / In-App Debug Connect이다.
1차 목표는 새 debug connect 흐름과 기존 CLI ingress를 계속 검증할 regression/smoke를 보강하는 것이다.

이번 턴의 수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/
- /Users/najongseong/git_repository/GoStop_antigravity/scripts/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- 기존 multiplayer runner 또는 smoke를 보강해서 `ready-start`와 `disconnect-resume` 흐름 검증을 유지해라.
- shake choice hidden-info leak regression을 추가해라.
- stale/replaced heartbeat regression을 추가해라.
- `MP-008` fault injection unblock 질문을 더 좁혀라.
- 앱 내부 debug connect 수동 점검 체크리스트를 문서에 추가해라.

이번 턴에서 하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 임시 수정으로 테스트 맞추기

끝나면 아래 형식으로 보고해라:
- 변경 파일
- 추가/강화한 regression 목록
- smoke 실행 결과
- 수동 점검 체크리스트
- 필요한 contract 질문
```
