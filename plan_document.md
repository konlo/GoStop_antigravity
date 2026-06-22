# GoStop 재작성 계획서

## 1. 프로젝트 정체성

- **작업명**: GoStop / 맞고
- **장르**: iOS 카드 게임, 캐주얼 전략
- **플랫폼**: iOS 우선, SwiftUI, Swift 6, Swift Package Manager
- **1차 게임 모드**: 2인 맞고 한 판
- **구현 순서**: 로컬 싱글 플레이 + AI/test-agent 상대 -> CLI/소켓 검증 -> 온라인 멀티플레이
- **대상 사용자**: 고스톱/맞고 규칙을 알고 있거나 배우려는 사용자, 모바일에서 카드가 잘 보이고 판정이 명확한 게임을 원하는 사용자
- **North Star Metric**: 첫 판을 규칙 오류, 상태 불일치, UI 렌더 불일치 없이 끝까지 완료한 비율

## 2. 제품 비전

플레이어가 이 게임을 할 때 느껴야 하는 감각은 다음 한 문장으로 고정한다.

> 내가 낸 패가 왜 먹히고, 왜 점수가 났고, 왜 Go/Stop을 선택해야 하는지 즉시 이해하는 영리한 맞고 플레이어.

재작성 프로젝트의 우선순위는 다음 순서다.

- 시각적 장식보다 규칙 정확도
- 네트워크보다 deterministic engine
- 화려한 화면보다 카드 가독성과 탭 안정성
- 수동 확인보다 재현 가능한 테스트와 artifact
- 기능 확장보다 phase별 완료 기준

## 3. 핵심 플레이 루프

```text
플레이어가 손패와 바닥패를 본다
-> 가능한 손패 또는 선택지를 탭한다
-> 엔진이 내기, 뒤집기, 먹기, 특수 이벤트, 점수, 다음 단계를 판정한다
-> UI가 결과를 애니메이션과 점수/획득영역 변화로 보여준다
-> 플레이어가 다음 패, Go, Stop, 선택 응답을 결정한다
```

이 루프는 플레이어가 매 순간 아래 세 가지를 추측 없이 알 수 있을 때 성공이다.

- 지금 누구 차례인지
- 지금 가능한 행동이 무엇인지
- 직전 행동으로 어떤 카드/점수/상태가 바뀌었는지

## 4. 첫 30초 경험

1. 앱은 마케팅 화면이 아니라 바로 플레이 가능한 진입 화면으로 시작한다.
2. 사용자는 10초 안에 `시작` 또는 `빠른 시작`을 누른다.
3. 패가 돌려진 뒤 바닥, 더미 수, 상대 영역, 내 손패, 획득영역, 턴 배지가 즉시 보인다.
4. 낼 수 있는 손패는 탭 가능한 상태로 보이고, 불가능한 행동은 비활성화되거나 명확한 거절 메시지를 낸다.
5. 첫 패를 내면 짧은 카드 이동, 먹기 결과, 획득영역 또는 점수 변화가 바로 보인다.
6. 쪽/따닥/쓸/뻑/총통 같은 이벤트는 다음 입력 전에 짧은 이벤트 팝업으로 드러난다.

## 5. 세션 설계

- **평균 세션 길이**: 한 판 기준 3분에서 10분.
- **세션 성공 조건**: 플레이어 또는 상대가 유효한 Stop/승리 조건에 도달하고, 최종 점수와 종료 사유가 표시된다.
- **세션 실패 조건**: 상대 승리, 강제 Stop, 3뻑/총통 같은 즉시 종료, 멀티플레이 기권 또는 복구 불가 disconnect.
- **재방문 이유**: 누적 승리 점수, 규칙 숙련, 빠른 재대국, 안정적인 판정 신뢰.
- **MVP 제외**: 메타 재화, 랭킹, 소셜 기능은 첫 재작성 범위에 넣지 않는다.

## 6. 규칙 범위

### MVP 포함 규칙

현재 저장소의 `rule.yaml`과 `engine_iteration.md`를 기준으로 다음을 MVP 규칙 범위로 삼는다.

- 화투 48장 invariant: 12월, 각 4장
- 2인 맞고 점수 기준: 7점
- 점수 분류: 광, 띠, 열끗, 피
- 조합 점수: 삼광, 비삼광, 사광, 오광, 고도리, 홍단, 청단, 초단
- Go/Stop 보너스와 배율은 현재 config를 우선한다
- 국진쌍피 역할 선택은 capture time에 처리한다
- 쌍피, 보너스패, 조건부 쌍피를 명시적으로 처리한다
- 벌칙: 고박, 광박, 피박, 멍박, 자박, 역박
- 특수 이벤트: 폭탄, 흔들기, 쓸, 따닥, 쪽, 뻑, 뻑 먹기, 멍따, 폭탄 멍따, 총통
- 3뻑은 즉시 종료 + 고정 10점 승리 조건으로 유지한다
- 나가리 다음 판 배율을 config로 유지한다
- 첫 실행 선 결정은 밤일낮장 규칙을 적용한다

### 명시적 비목표

이번 재작성은 아래를 목표로 하지 않는다.

- 현금성 도박 제품
- 첫 릴리스의 3인 고스톱
- 소셜 네트워크, 랭킹, 클랜 시스템
- 로컬/CLI/socket 계약 안정화 전 production public backend
- AI 코치나 AI 해설자 중심 제품

## 7. 아키텍처 원칙

### 핵심 원칙

엔진이 판정권을 갖는다. SwiftUI는 절대 규칙을 결정하지 않는다.

```text
Input Action
-> Action Guard
-> Rule Resolver
-> State Transition
-> Engine Events
-> UI Projection / CLI Response / Multiplayer Event
```

### 모듈 경계

- `Core`: 카드, 덱, 상태, 점수, 벌칙, 턴 진행, seed 기반 난수, rule config
- `ViewModel / App State`: UI가 소비할 상태 변환과 action dispatch
- `Views`: SwiftUI 렌더링, 탭 연결, 애니메이션, overlay
- `GoStopCLI`: UI 없는 엔진 실행과 테스트 브리지
- `tests/test_agent`: Python 검증 agent, scenario runner, artifact 생성
- `Multiplayer`: room/session, transport, authoritative snapshot, player-scoped projection

### 엔진 상태 머신

싱글/로컬 엔진은 명시적인 phase와 turn step을 가져야 한다.

```text
setup
-> dealing
-> playing
   -> selectHandCard
   -> matchHandCard
   -> drawCard
   -> matchDrawnCard
   -> decision
   -> turnComplete
-> scoring
-> gameOver
```

멀티플레이 room/session 상태는 게임 룰 상태와 분리한다.

```text
waitingForPlayers
-> waitingForReady
-> starting
-> inGame
-> ended
-> closed
```

### EngineResult 계약

모든 command는 구조화된 결과를 반환한다.

- `status`: `ok` 또는 `error`
- `state`: 현재 상태 snapshot
- `events`: UI가 표시할 semantic event 목록
- `errorCode`: invalid command용 stable code
- `traceId`: command 추적 id
- `timingMs`: 처리 시간
- `stateVersion`: accepted mutation이 있을 때만 증가
- `eventId`: 게임 내 event 단조 증가 id

invalid action은 명시적으로 reject 해야 하며, state를 바꾸면 안 된다.

## 8. UI 계획

### UI 원칙

- 바닥패와 내 손패가 항상 1차 시선 대상이다.
- 상대/내 점수, Go 수, 획득영역, 더미 수, 현재 턴 힌트는 작지만 항상 읽을 수 있어야 한다.
- 모든 카드 위치는 logical slot으로 표현한다. 게임 로직은 좌표를 모른다.
- 애니메이션은 상태 변화를 설명할 뿐, 규칙 타이밍을 결정하지 않는다.
- reconnect, pause, replay overlay는 입력을 잠그되 마지막 authoritative board를 유지한다.

### 화면 영역

- 상대 영역: 이름, 점수, Go 수, 획득 카드, 손패 수
- 바닥 영역: 월별 bucket, 더미 수, 현재 focus 카드
- 내 영역: 손패, 선택 카드, 획득 카드, 점수
- 행동 영역: 현재 단계 힌트, Go/Stop/선택 버튼
- overlay 영역: 특수 이벤트, 게임 종료, reconnect, reject/error
- debug 영역: DEBUG build 또는 test-agent run에서만 표시

### 행동별 피드백

| 행동 | 피드백 | 목표 시간 |
| --- | --- | --- |
| 카드 선택 | highlight 또는 작은 scale | 150ms 이하 |
| 손패 내기 | hand -> table 이동 | 300ms 이하 |
| 카드 먹기 | table -> captured 이동 | 300ms 이하 |
| invalid action | 짧은 blocked feedback + 메시지 | 200ms 이하 |
| 특수 이벤트 | 다음 prompt 전 event popup | 짧고 비차단 |
| Go/Stop | 명확한 결정 sheet 또는 버튼 | 즉시 |

## 9. 멀티플레이 계획

멀티플레이는 로컬 엔진, CLI bridge, scenario 검증이 안정화된 뒤 붙인다.

### Authority 계약

- 서버 쪽 엔진이 source of truth다.
- client는 command를 보낼 뿐 choice를 재계산하지 않는다.
- player-scoped projection은 상대 손패 identity와 deck order를 숨긴다.
- `stateVersion`은 accepted mutation마다 정확히 1 증가한다.
- `eventId`는 game 내부에서 단조 증가한다.
- 같은 `actionId` + 같은 body 재전송은 기존 결과 replay다.
- 같은 `actionId` + 다른 body 재사용은 `actionIdConflict` reject다.
- stale `expectedStateVersion`은 reject와 `stateSnapshot(reason=resync)`를 반환한다.

### Room/Session 계약

초기 멀티플레이 범위는 다음으로 제한한다.

- 2인 고정
- invite와 quick match는 같은 state machine 사용
- 두 플레이어 ready 완료 시 auto-start
- idle 5초 heartbeat
- 15초 무응답 disconnect
- reconnect grace 30초
- 같은 플레이어의 multi-device 접속은 newest valid connection wins
- `starting` 또는 `inGame` 중 grace 만료는 forfeit

### 멀티플레이 UI 흐름

```text
Entry
-> Room
-> Live Match
-> Reconnect Overlay, 필요 시
-> Result
```

Phase 0에서는 현재 작성해 둔 websocket command boundary를 유지하고, public REST split은 product path가 안정화된 뒤 후속으로 둔다.

## 10. 테스트와 검증 전략

### 검증 계층

1. Swift unit test: 카드, 덱, 점수, 벌칙, 상태 전이
2. CLI bridge test: `start`, `state`, `play`, `select`, `go`, `stop`, `validateDeck`, `logs`, `replayExport`, `debugDiff`
3. Python single-player scenario: `tests/test_agent/test_scenarios.py`
4. multiplayer fixture test: 계약과 event ordering 검증
5. socket test: `GoStopCLI` 기준 authoritative transport 검증
6. two-simulator UI test: 실제 product render parity 검증

### 기본 검증 명령

```bash
swift build
swift test
python3 tests/test_agent/test_scenarios.py
python3 tests/test_agent/multi_test_scenario.py --suite managed-all-runnable --mode fixture
python3 tests/test_agent/multiplayer_runner.py --suite socket-end-to-end --mode socket
```

UI hardening 단계에서는 아래 시나리오를 기준 gate로 둔다.

```bash
python3 tests/test_agent/multi_test_scenario.py --suite managed-end-to-end-always-go --mode ui
python3 tests/test_agent/multi_test_scenario.py --suite managed-capture-visibility-short --mode ui
```

### Artifact 정책

의미 있는 실패는 항상 `test_artifacts/` 아래에 증거를 남긴다.

- command timeline
- action 전후 state snapshot
- replay package
- anomaly report
- UI run의 host/guest screenshot
- screen parity result

## 11. 재작성 Phase

### Phase 0: 범위 고정과 새 프로젝트 skeleton

산출물:

- 새 iOS SwiftUI App target
- Swift package 또는 명확한 `Core` 모듈 경계
- `rule.yaml`, `message.yaml`, layout config, card assets resource 이동
- `plan_document.md`를 1차 source of truth로 확정
- 최소 build/test command checklist

완료 기준:

- 새 프로젝트가 build 된다
- card assets가 load 된다
- `Core`가 SwiftUI import 없이 compile 된다

### Phase 1: Deterministic Core Engine

산출물:

- `Card`, `Deck`, `PlayerState`, `GameState`, `RuleConfig`
- seed 기반 shuffle
- deck invariant validation
- scoring system
- penalty system
- 명시적 phase와 turn step
- action guard와 engine result schema

완료 기준:

- deck validation이 통과한다
- scoring fixture가 통과한다
- invalid action이 state mutation 없이 reject 된다
- 같은 seed와 같은 action sequence가 같은 결과를 만든다

### Phase 2: Headless CLI와 Test Agent

산출물:

- newline-delimited JSON CLI/socket bridge
- actions: `hello`, `state`, `start`, `play`, `select`, `go`, `stop`, `pause`, `resume`, `quit`, `validateDeck`, `help`, `logs`, `replayExport`, `debugDiff`
- trace id, timing, error code, state hash, state diff 출력
- 기존 Python scenario runner 이식

완료 기준:

- single-player scenario suite가 green이다
- replay artifact로 실패 turn을 재현할 수 있다
- anomaly report만 보고도 phase, current player, selected action, response payload를 알 수 있다

### Phase 3: 싱글 플레이 SwiftUI

산출물:

- slot 기반 table, hand, captured zones
- step 기반 hint와 action availability
- 카드 이동 animation route
- special event popup queue
- game-ended summary
- 누적 승리 점수 표시와 persistence

완료 기준:

- iPhone simulator에서 카드가 탭 가능하고 잘리지 않는다
- SwiftUI `body`에 rule decision이 없다
- simulator bridge가 현재 보이는 상태를 관측할 수 있다

### Phase 4: 규칙 edge hardening

산출물:

- 폭탄, 흔들기, 쓸, 따닥, 쪽, 뻑, 뻑 먹기, 총통, 멍따 처리
- 3뻑 종료 popup gating
- empty-hand forced stop
- 최종 배율과 박 규칙을 config에 고정
- 수정된 bug마다 targeted regression scenario 추가

완료 기준:

- 전체 single-player rule scenario가 통과한다
- 모든 특수 이벤트에 최소 1개 regression scenario가 있다
- rule 변경은 `rule.yaml`과 test를 함께 바꾼다

### Phase 5: Multiplayer Contract와 Room Layer

산출물:

- authoritative multiplayer snapshot/event contract
- hidden information을 지키는 player-scoped projection
- room/session coordinator
- websocket transport command boundary
- reconnect, heartbeat, resume, timeout, forfeit
- duplicate action과 stale state 처리

완료 기준:

- `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`가 fixture와 socket mode에서 통과한다
- TCP/WebSocket 두 transport를 유지한다면 parity가 green이다

### Phase 6: Multiplayer Product UI

산출물:

- entry, room, live match, reconnect overlay, result route
- UI에서 authoritative gameplay command 전송
- 상대 턴 replay도 local play와 같은 animation path 사용
- hand/captured/table parity render probe
- 2 simulator autoroute harness

완료 기준:

- `MP-016` full-match always-go UI run이 통과한다
- `MP-017` same-turn captured-zone visibility UI run이 통과한다
- host/guest screenshot과 authoritative projection이 일치한다

### Phase 7: Polish, Persistence, Release Gate

산출물:

- rule settings와 rule 설명
- gameplay loop 안정화 이후 sound/haptic
- 결과 기록과 누적 점수
- artifact cleanup script
- release checklist와 known-risk 문서

완료 기준:

- release build가 성공한다
- production에서 debug overlay가 꺼져 있다
- 최신 검증 artifact가 progress/evidence 문서에 연결된다

## 12. 기존 작성물 재사용 계획

다음 파일은 새 프로젝트에 직접 복사하거나 구현 기준으로 사용한다.

- `rule.yaml`, `GoStop/Resources/rule.yaml`
- `GoStop/Assets.xcassets/` 카드 이미지와 앱 아이콘
- `GoStop/Resources/message.yaml`
- `GoStop/Resources/layout_hwatu.json`
- `GoStop/Core/ScoringSystem.swift`
- `GoStop/Core/PenaltySystem.swift`
- `GoStop/Core/GameManager.swift`는 동작 기준으로만 보고 blind copy 하지 않는다
- `GoStop/Core/SimulatorBridge.swift`
- `GoStop/Core/MultiplayerContract.swift`
- `GoStop/Core/InMemoryRoomCoordinator.swift`
- `GoStopCLI/main.swift`
- `tests/test_agent/test_scenarios.py`
- `tests/test_agent/multi_test_scenario.py`
- `tests/test_agent/multiplayer/`
- `tests/test_agent/multiplayer_ui_auto_play.py`
- `multiplayer_contract.md`
- `room_protocol.md`
- `multiplayer_ui_flow.md`
- `multiplayer_test_scenarios.md`
- `multiplayer_test_scenario_runbook.md`
- `design_checklist.md`
- `engine_iteration.md`

재작성의 원칙은 "자산과 계약은 먼저 재사용하고, 구현 코드는 새 모듈 경계가 선 뒤에 필요한 부분만 가져온다"이다.

## 13. Risk Register

| 위험 | 영향 | 대응 |
| --- | --- | --- |
| 엔진 안정화 전에 규칙 범위가 커짐 | 높음 | MVP 규칙을 고정하고 특수 규칙별 scenario를 둔다 |
| UI가 규칙을 결정하기 시작함 | 높음 | Core-only rule resolution, UI는 projection만 소비 |
| 멀티플레이 desync | 높음 | `stateVersion`, `eventId`, replay, socket scenario를 gate로 둔다 |
| hidden information leak | 높음 | player-scoped projection test를 둔다 |
| 애니메이션 race로 카드가 늦게 보이거나 사라짐 | 중간 | slot layout, render probe, `MP-017` 검증 |
| artifact가 너무 많아 추적이 어려움 | 중간 | 표준 artifact root와 cleanup script 유지 |
| 이전 복잡도를 그대로 가져옴 | 중간 | phase gate 전에는 구현 코드 blind copy 금지 |

## 14. 바로 다음 작업

1. 새 SwiftUI iOS App skeleton을 만들고 build를 확인한다.
2. 먼저 assets, config, 이 계획서만 새 프로젝트로 옮긴다.
3. UI 없이 `Core`의 `Card`, `Deck`, `RuleConfig`, seeded shuffle, deck invariant validation을 구현한다.
4. 복잡한 UI보다 CLI/test bridge를 먼저 연결한다.
5. single-player Python scenario를 이식해 첫 hard gate로 삼는다.
6. 로컬 엔진과 headless validation이 green이 된 뒤 멀티플레이를 붙인다.

