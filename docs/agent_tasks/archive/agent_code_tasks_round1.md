# Agent Code Tasks Round 1

## Goal
- 문서 초안 단계에서 멈추지 않고, Agent 1~4가 실제 코드 작업을 바로 시작할 수 있게 첫 구현 라운드 범위를 끊는다.
- 이번 라운드는 "멀티플레이 전체 완성"이 아니라 `병렬 개발 가능한 코드 골격`을 만드는 데 집중한다.

## Why This Split
- 현재 저장소에는 이미 `GameManager`, `SimulatorBridge`, `GoStopCLI/main.swift`, `tests/test_agent/`가 있어 single-process/single-session 제어 기반은 존재한다.
- 반면 room/session, authoritative contract types, UI multiplayer shell, multiplayer-specific test harness는 아직 분리돼 있지 않다.
- 따라서 Round 1은 각 agent가 서로 다른 파일 범위를 건드리면서 다음 라운드의 실제 연결 작업을 가능하게 만드는 단계로 잡는 편이 낫다.

## Round 1 Rules
- Agent 1과 Agent 2는 같은 파일을 동시에 수정하지 않는다.
- Agent 3는 실제 네트워크 연결보다 UI shell과 state adapter 골격에 집중한다.
- Agent 4는 production flow를 바꾸지 않고 test harness/artifact 쪽만 확장한다.
- 이번 라운드 끝에서 필요한 것은 "작동하는 전체 멀티플레이"가 아니라 "연결 가능한 골격 + 검증 가능한 계약"이다.

## Current Review Fixups
- Agent 1:
  - `askingShake` choice payload에서 non-actor에게 hand metadata가 노출되지 않게 수정
  - projection의 `isConnected/isReady`를 room-layer truth 기준으로 정리하거나 최소한 hardcode를 제거
  - `dealerPlayerId`가 실제 starter/dealer 결과를 따르도록 수정
- Agent 2:
  - `recordHeartbeat`가 replaced/expired session 또는 stale `connectionId`를 허용하지 않게 수정
  - same-player multi-device에서 newest-wins 정책이 reconnect/heartbeat 이후에도 유지되는지 검증
- Agent 3:
  - UI mapper가 room-layer presence/ready를 truth source로 소비하도록 준비
  - shake choice UX가 상대 손패 metadata를 필요로 하지 않도록 blocker/assumption 정리
- Agent 4:
  - shake choice hidden-info leak regression 추가
  - stale/replaced heartbeat regression 추가
  - `MP-008` fault injection unblock question 정리

## Agent 1: Core Engine / Authority Contract

### Objective
- 현재 `GameManager`/`SimulatorBridge`/`GoStopCLI`가 공통으로 사용할 multiplayer contract 타입과 authoritative snapshot projection helper를 만든다.

### Files To Touch
- `GoStop/Core/` 아래 새 Swift 파일 1~2개
- 필요 시 `GoStopCLI/main.swift`
- 필요 시 `GoStop/Core/SimulatorBridge.swift`
- `multiplayer_contract.md`
- `agent_sync_board.md`

### Suggested New Files
- `GoStop/Core/MultiplayerContract.swift`
- `GoStop/Core/MultiplayerProjection.swift`

### Concrete Tasks
- `Codable` 기반 command / event / reject / choice / snapshot Swift 타입 정의
- `GameManager`에서 player-scoped multiplayer snapshot을 뽑는 projection helper 추가
- 기존 `get_state` payload와 별개로 multiplayer-friendly serialized shape를 만드는 entry point 추가
- `multiplayer_contract.md`와 실제 타입 이름을 맞춘다
- `askingShake`에서 non-actor에게 hidden hand metadata가 새지 않도록 choice payload를 viewer-scoped로 보정
- projection의 `isConnected/isReady` hardcode를 제거하거나 room-layer merge contract를 명시
- `dealerPlayerId` / starter 관련 payload가 실제 starter selection 결과를 따르도록 정리

### Acceptance
- Swift 타입 이름과 문서 계약이 1:1로 대응된다
- projection helper가 hidden-information 규칙을 반영한다
- CLI/bridge가 새 multiplayer snapshot builder를 호출할 준비가 된다
- shake choice payload가 non-actor에게 hidden hand 정보를 노출하지 않는다
- projection이 room/session truth와 모순되는 `isConnected/isReady=true` 하드코딩을 남기지 않는다

### First Coding Prompt
```text
너는 Agent 1이다. [agent_prompts/agent1_core_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent1_core_prompt.md)의 역할을 따른다.

이번 코딩 라운드 목표는 authoritative multiplayer contract Swift 타입과 projection helper를 만드는 것이다.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/main.swift
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `MultiplayerContract.swift` 또는 유사한 새 파일을 만들어 command/event/reject/choice/snapshot 타입을 정의해라.
- `GameManager` 기준 player-scoped snapshot projection helper를 추가해라.
- 기존 single-agent `get_state`를 깨지 않으면서 multiplayer용 projection 진입점을 만들 준비를 해라.
- 문서와 실제 타입 이름을 맞추고, Agent 2/3/4가 소비할 핵심 필드를 handoff로 남겨라.

이번 턴에서 하지 말 것:
- room/session lifecycle 구현
- SwiftUI 화면 구현
- Python test harness 수정

끝나면:
- 변경 파일
- 새 타입 목록
- projection 규칙
- Agent 2/3/4에 필요한 handoff
```

## Agent 2: Backend / Room / Session Skeleton

### Objective
- 실제 서버가 아직 없어도, room/session/reconnect를 표현하는 Swift 골격 타입과 in-memory coordinator를 만든다.

### Files To Touch
- `GoStopCLI/` 아래 새 Swift 파일
- 필요 시 `GoStopCLI/main.swift`
- `room_protocol.md`
- `agent_sync_board.md`

### Suggested New Files
- `GoStopCLI/RoomProtocolModels.swift`
- `GoStopCLI/InMemoryRoomCoordinator.swift`

### Concrete Tasks
- room/session/member/state enum 정의
- room state transition helper 작성
- in-memory room coordinator 스켈레톤 추가
- websocket/transport와 무관하게 room lifecycle을 돌릴 수 있는 API shape 정의
- `room_protocol.md` 문서와 코드 모델 이름을 맞춘다
- `recordHeartbeat`가 replaced/expired session과 stale `connectionId`를 허용하지 않도록 guard 추가
- newest-wins multi-device 정책이 `attachSession` / `resumeSession` / heartbeat 이후에도 유지되도록 보강

### Acceptance
- room lifecycle state enum과 transition API가 코드로 존재한다
- reconnect/session 상태를 표현하는 모델이 있다
- 나중에 socket layer를 얹을 수 있는 coordinator 골격이 있다
- stale socket heartbeat가 최신 연결을 덮어쓰지 않는다

### First Coding Prompt
```text
너는 Agent 2이다. [agent_prompts/agent2_backend_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent2_backend_prompt.md)의 역할을 따른다.

이번 코딩 라운드 목표는 room/session/reconnect Swift 골격과 in-memory coordinator를 만드는 것이다.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- room/member/session/state enum과 모델 타입을 새 Swift 파일로 정의해라.
- in-memory room coordinator 골격을 만들어 create/join/ready/disconnect/resume transition을 표현해라.
- transport 의존 없이 room lifecycle을 테스트 가능하게 API shape를 정리해라.
- 문서와 코드 모델 이름을 맞추고 open question을 정리해라.

이번 턴에서 하지 말 것:
- 카드 룰 판정 구현
- GameManager 수정
- SwiftUI 화면 수정
- Python 테스트 수정

끝나면:
- 변경 파일
- room/session 타입 목록
- transition API 요약
- Agent 1/3/4가 알아야 할 handoff
```

## Agent 3: iOS Multiplayer UI Shell

### Objective
- 실제 소켓 연결 전 단계로, 멀티플레이 입구/룸/재접속 오버레이용 SwiftUI shell과 view model placeholder를 만든다.

### Files To Touch
- `GoStop/Views/` 아래 새 SwiftUI 파일
- 필요 시 새 view model 파일
- `multiplayer_ui_flow.md`
- `agent_sync_board.md`

### Suggested New Files
- `GoStop/Views/MultiplayerEntryView.swift`
- `GoStop/Views/MultiplayerRoomView.swift`
- `GoStop/Views/MultiplayerReconnectOverlay.swift`

### Concrete Tasks
- entry / room / reconnect overlay 뷰 shell 추가
- preview 또는 mock state로 렌더 가능한 최소 view model/state struct 정의
- 기존 `GameView`를 건드리지 않거나, 건드리더라도 integration point만 최소로 남김
- `multiplayer_ui_flow.md`의 payload needs를 코드 placeholder와 맞춤
- room-layer presence/ready를 truth source로 소비할 수 있게 state mapper/blocker를 정리
- shake choice UX가 상대 손패 metadata 없이도 성립하는 전제로 문서와 placeholder를 맞춤

### Acceptance
- 새 SwiftUI shell 파일이 존재한다
- reconnect / room / entry UI 상태를 렌더링할 최소 상태 모델이 있다
- 실제 socket 연결이 없어도 preview 또는 mock state로 확인 가능하다
- room-layer presence/ready truth를 받을 자리와 blocker가 명확하다

### First Coding Prompt
```text
너는 Agent 3이다. [agent_prompts/agent3_ios_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent3_ios_prompt.md)의 역할을 따른다.

이번 코딩 라운드 목표는 multiplayer UI shell과 placeholder state를 만드는 것이다.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/
- 필요 시 UI-facing state 파일
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- `MultiplayerEntryView`, `MultiplayerRoomView`, `MultiplayerReconnectOverlay` 또는 동등한 새 SwiftUI shell을 만들어라.
- 실제 네트워크 없이 preview/mock state로 렌더되게 해라.
- 필요한 payload를 placeholder state 타입으로 드러내라.
- 현재 payload blocker를 문서와 sync board에 남겨라.

이번 턴에서 하지 말 것:
- 룰 판정 추가
- room/session 서버 구현
- Python 테스트 수정
- GameView 대규모 개편

끝나면:
- 변경 파일
- 새 UI shell 목록
- 필요한 payload 목록
- 남은 integration blocker
```

## Agent 4: Multiplayer Test Harness Skeleton

### Objective
- 현재 single-session test agent 위에 multiplayer scenario/artifact 골격을 얹는다.

### Files To Touch
- `tests/test_agent/`
- `multiplayer_test_scenarios.md`
- `agent_sync_board.md`

### Suggested New Files
- `tests/test_agent/multiplayer_runner.py`
- `tests/test_agent/multiplayer_protocol.py`

### Concrete Tasks
- multiplayer scenario ID/manifest/artifact helper 추가
- reconnect/duplicate action/stateVersion mismatch용 scenario skeleton 추가
- `/tmp/gostop_test_artifacts` 아래 multiplayer artifact 하위 구조 추가
- 기존 `test_scenarios.py`와 공존 가능한 helper 구조로 분리
- `tests/test_agent/multiplayer_runner.py` 또는 동등 파일을 실제로 생성
- 최소 4개 P0 scenario skeleton을 코드 레벨에 등록
- shake choice hidden-info leak regression 추가
- replaced/expired session heartbeat reject regression 추가

### Acceptance
- multiplayer용 manifest/artifact writer가 있다
- P0 시나리오 skeleton이 코드 레벨에서 등록돼 있다
- traceId/roomId/gameId/actionId를 담는 artifact shape가 존재한다
- privacy/session-hardening regression이 다음 라운드에 바로 확장 가능하다

### First Coding Prompt
```text
너는 Agent 4이다. [agent_prompts/agent4_test_prompt.md](/Users/najongseong/git_repository/GoStop_antigravity/agent_prompts/agent4_test_prompt.md)의 역할을 따른다.

이번 코딩 라운드 목표는 multiplayer test harness와 artifact skeleton을 만드는 것이다.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 턴에서 할 일:
- multiplayer scenario runner/helper 새 파일을 만들어라.
- manifest, replay, snapshot, anomaly artifact 구조를 코드로 표현해라.
- `MP-001 ~ MP-008` 중 최소 P0 skeleton을 코드 레벨에 등록해라.
- 최소한 `room start`, `out-of-turn reject`, `disconnect/resume`, `stateVersion mismatch/resync`는 실제 Python scenario skeleton으로 추가해라.
- 기존 single-player 시나리오와 충돌하지 않게 helper를 분리해라.
- `multiplayer_test_scenarios.md`에는 코드에 추가한 scenario ID와 목적을 맞춰라.

이번 턴에서 하지 말 것:
- production Swift 코드 수정
- room protocol 재정의
- UI 코드 수정

끝나면:
- 변경 파일
- 새 runner/helper 목록
- 코드에 등록한 scenario ID 목록
- artifact 구조
- Agent 1/2에 필요한 contract 질문
```

## Recommended Launch Order
1. Agent 1 시작
2. 거의 동시에 Agent 2, Agent 4 시작
3. Agent 3 시작

## Merge Order
1. Agent 1
2. Agent 2
3. Agent 4
4. Agent 3

## Definition Of Round 1 Done
- Agent 1: multiplayer contract Swift 타입 + projection helper 존재
- Agent 2: in-memory room/session coordinator 존재
- Agent 3: multiplayer UI shell과 placeholder state 존재
- Agent 4: multiplayer runner/artifact skeleton 존재
- `agent_sync_board.md`에 blocker와 open question이 반영돼 있음
