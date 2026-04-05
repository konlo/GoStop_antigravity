# UI Integration Round 1: 상태 매핑 아키텍처 및 어댑터 설계

## Current Verified State
- `MultiplayerLiveShellView`는 현재 정적인 요소를 렌더링하고 있음며 기존의 `GameView`와 구조적으로 분리되어 있음.
- `GameView`는 싱글플레이용 풍부한 인터랙션과 애니메이션을 보유하고 있음.
- 백엔드 룸 세션과 관련 코어 게임 이벤트 모델들이 프로토콜화되어 있음 (`MultiplayerLiveShellState`).

## Round 1 Goal
- 기존의 임시 화면인 `MultiplayerLiveShellView`를 폐기하고, 본 화면(`GameView` 및 `AnimationManager` 등)을 서버 권한형 멀티플레이 상태와 연동하기 위한 아키텍처 및 어댑터 초안 설계.
- Agent 1: `StateMapper` 인터페이스 및 초안 구현.
- Agent 2: 초기 상태 부트스트랩 및 델타 이벤트 페이로드 명세 확정.
- Agent 3: `GameView`에 주입할 `MultiplayerPlayCoordinator` 작성.
- Agent 4: 상태 변환 로직에 대한 검증 코드 작성.

## Recommended Order
1. Agent 1 (계약 기반 상태 변환 설계)
2. Agent 2 (프로토콜과 이벤트 전달 확정)
3. Agent 3 (iOS View Mount 구조 작성)
4. Agent 4 (유닛 테스트 및 시나리오)

---

## Agent 1 Prompt
```text
너는 Agent 1이다. Core Engine / Game Authority 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_mp_ui_round1.md
- /Users/najongseong/git_repository/GoStop_antigravity/agent_sync_board.md

이번 작업 목표:
- `MultiplayerLiveShellState` 또는 서버로부터 수신되는 스냅샷을 기존 `GameManager` 및 `GameView`가 소화할 수 있는 로컬 엔진 상태로 변환하는 `StateMapper` 초안을 작성하라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Core/ (Mapper 로직)
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_contract.md

이번 턴에서 할 일:
- 단방향 상태 변환을 보장할 `MultiplayerStateMapper`의 프로토콜과 인터페이스 정의.
- `GameManager` 내의 카드, 슬롯, 점수를 조작할 수 있도록 헬퍼 계층 마련.
- 변환 중 발생하는 불일치 리포팅 양식 마련.

하지 말 것:
- SwiftUI 화면의 실제 렌더링 변경.
- 백엔드 프로토콜이나 웹소켓 구현 수정.

끝나면 보고:
- 추가 혹은 수정된 파일
- `StateMapper` 의 동작 흐름 요약
- Agent 2 및 Agent 3로의 Handoff 명세서
```

---

## Agent 2 Prompt
```text
너는 Agent 2이다. Backend / Lobby / Reconnect 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_mp_ui_round1.md
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 작업 목표:
- Agent 1의 상태 변환기와 Agent 3의 뷰가 요구하는 초기 부트스트랩 스냅샷 및 델타 이벤트 페이로드 명세를 확정하라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopCLI/
- /Users/najongseong/git_repository/GoStop_antigravity/room_protocol.md

이번 턴에서 할 일:
- 게임 진입 시의 `bootstrap payload` 형태 및 크기 정의.
- 이벤트 스트리밍 시 전달될 델타 이벤트(예: 턴 변경, 획득 이벤트 등)의 구조 세분화 및 문서화.
- 상태 갱신 과정에서 패킷 로스 방지를 위한 Sequence number 등 처리 방안 확립.

하지 말 것:
- `GameManager` 등 코어 엔진 룰 수정.
- 클라이언트 화면(SwiftUI) 관련 렌더링 수정.

끝나면 보고:
- 수정된 `room_protocol` 및 프로토콜 요소
- 부트스트랩 및 델타 업데이트의 Handoff 데이터 형태 샘플
```

---

## Agent 3 Prompt
```text
너는 Agent 3이다. iOS Multiplayer Client / UX 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_mp_ui_round1.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 작업 목표:
- 풍부한 렌더링을 담당하는 `GameView`에 멀티플레이 상태를 주입하고 제어할 `MultiplayerPlayCoordinator` 초안을 작성하라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/GoStop/Views/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_ui_flow.md

이번 턴에서 할 일:
- `MultiplayerLiveShellView`를 완전히 대체할 수 있도록 기존 `GameView`를 감싸는 코디네이터 패턴 작성.
- 코디네이터를 통해 상태(예: Agent 1에서 매핑된 `GameManager` 상태)를 바인딩할 파이프라인 준비.
- 추후 턴 잠금 및 인터랙션 제한(Round 3/4)을 위한 ViewModifier 또는 환경 변수(Environment) 설계.

하지 말 것:
- 카드 애니메이션 실제 로직 수정 (`AnimationManager` 등).
- 상태 매핑 로직 자체의 구현 변경.

끝나면 보고:
- 코디네이터 구현 방향 및 추가된 파일 구조.
- 클라이언트 마운트 경로 준비 상황.
```

---

## Agent 4 Prompt
```text
너는 Agent 4이다. Debugging / Test Scenarios / Observability 역할을 맡는다.

먼저 아래 파일을 다시 읽어라:
- /Users/najongseong/git_repository/GoStop_antigravity/agent_code_tasks_mp_ui_round1.md
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 작업 목표:
- 이번 라운드에 Agent 1이 설계하는 상태 변환기(Mapper)의 정확성을 검증할 데이터 주도 단위 테스트 및 스냅샷 구조를 추가하라.

수정 범위:
- /Users/najongseong/git_repository/GoStop_antigravity/tests/test_agent/
- /Users/najongseong/git_repository/GoStop_antigravity/GoStopTests/
- /Users/najongseong/git_repository/GoStop_antigravity/multiplayer_test_scenarios.md

이번 턴에서 할 일:
- 서버 스냅샷 JSON(`MultiplayerLiveShellState` 형태)이 Agent 1의 상태 변환기를 거친 후 `GameManager` 모델과 어떤 차이가 있는지 검증하는 Unit Test 작성 (Swift).
- 잘못된 데이터 수신 시의 파싱 실패나 무효 처리를 검증하는 Edge Case 추가.
- 검증에 활용할 더미 JSON 픽스쳐 및 매핑 에러 감지 로직 구체화.

하지 말 것:
- 프로덕션 코드 또는 매퍼 자체 구현 수정.
- UI 요소에 대한 UI Test 작성 (이번 라운드는 데이터 변환 검증에 집중).

끝나면 보고:
- 추가된 검증 시나리오 목록.
- 단위 테스트 실행 결과 및 리포트 포맷.
```
