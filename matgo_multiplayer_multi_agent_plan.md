# Online Matgo Multiplayer 4-Agent Plan

## Goal
- 온라인 맞고 멀티플레이 개발을 4개의 독립 workstream으로 나눠 병렬 진행한다.
- 각 agent가 자기 책임과 산출물을 명확히 가지도록 해서, 충돌 없이 동시에 일할 수 있게 한다.
- 특히 `debugging`과 `test scenario`를 별도 agent로 분리해 후반부에 QA가 몰리지 않게 한다.

## Why 4 Agents
- 멀티플레이는 `룰 엔진`, `네트워크/서버`, `클라이언트 UX`, `디버깅/검증`이 서로 다른 속도로 움직인다.
- 이 4개를 한 agent가 다 맡으면 병목이 생기고, 반대로 너무 잘게 쪼개면 계약 관리 비용이 커진다.
- 현재 저장소 구조 기준으로는 4개가 가장 현실적인 분할이다.

## Shared Principles
- 서버가 최종 판정권을 갖는 `authoritative` 구조를 유지한다.
- 룰 판정은 공용 엔진에서만 수행하고, iOS UI는 렌더링과 입력 전달만 담당한다.
- 모든 agent는 stable contract를 문서화하고, 계약 없는 추측 구현을 하지 않는다.
- 모든 주요 변경은 재현 가능한 test scenario 또는 artifact와 함께 제출한다.

## Agent 1: Core Engine / Game Authority

### Mission
- 멀티플레이의 단일 진실 원본이 되는 공용 게임 엔진과 상태 머신을 만든다.

### Scope
- `GoStop/Core` 룰 로직을 서버 재사용 가능 구조로 분리
- authoritative game state 설계
- turn/phase/choice/stateVersion/eventId 계약 정의
- invalid action reject 정책 정의
- headless match runner 또는 server-side game session 구현

### Main Deliverables
- 공용 엔진 패키지 초안
- `game state schema`
- `command -> validation -> state transition -> event` 흐름 정의
- `errorCode`, `rejectReason`, `stateVersion` 규약
- deterministic replayable event log 포맷

### Interfaces Owned
- `playCard`
- `selectCapture`
- `selectShake`
- `chooseGoStop`
- `resume`
- `quit/leave`

### Done Criteria
- 같은 입력 이벤트 로그로 항상 같은 결과가 나온다.
- 현재 턴이 아닌 액션, 잘못된 선택지, 중복 액션을 정확히 reject 한다.
- snapshot + replay log로 상태를 복원할 수 있다.

## Agent 2: Backend / Lobby / Reconnect

### Mission
- 유저가 실제로 방에 들어와 대전하고, 끊겼다가 다시 붙을 수 있는 서버 환경을 만든다.

### Scope
- auth/session 연결
- room/lobby lifecycle
- quick match 또는 invite room
- WebSocket 연결 관리
- reconnect/resume/session expiry
- 최소 persistence와 match history 저장

### Main Deliverables
- room 생성/입장/준비 API
- WebSocket gateway
- reconnect token 또는 session resume 정책
- room/match DB schema
- disconnect timeout / forfeit 정책

### Interfaces Owned
- `createRoom`, `joinRoom`, `ready`, `startGame`
- connection lifecycle
- room membership state
- heartbeat / ping / timeout

### Done Criteria
- 두 사용자가 같은 방에서 game session을 시작할 수 있다.
- 일시 disconnect 후 같은 room/game로 복귀할 수 있다.
- room/member/game 상태가 서버에서 일관되게 유지된다.

## Agent 3: iOS Multiplayer Client / UX

### Mission
- iOS 앱에서 멀티플레이 룸, 실시간 대국, reconnect UX를 사용자 입장에서 자연스럽게 만든다.

### Scope
- room list / invite / ready UI
- WebSocket client adapter
- server event -> view model state 반영
- input lock / reconnect overlay / reject message 처리
- 턴 타이머, 상대 연결 상태, round end summary

### Main Deliverables
- multiplayer entry flow UI
- room screen
- live match binding layer
- reconnect/recover UX
- client-side local cache for session resume

### Interfaces Owned
- `MultiplayerViewModel`
- networking client abstraction
- UI state mapping
- reconnect/loading/error presentation

### Done Criteria
- 유저가 방 생성부터 대국 시작까지 앱 내에서 완료할 수 있다.
- reconnect 중 잘못된 입력이 막힌다.
- 서버 reject, timeout, disconnect 상태가 UI에서 이해 가능하게 보인다.

## Agent 4: Debugging / Test Scenarios / Observability

### Mission
- 멀티플레이 기능이 실제로 믿을 수 있게 동작하는지 검증하고, 문제 발생 시 바로 재현 가능한 형태로 남긴다.

### Scope
- multiplayer scenario matrix 작성
- headless / socket 기반 test agent 설계
- reconnect, race, invalid action, timeout 회귀 시나리오 작성
- replay export / anomaly report / debug artifact 정책 수립
- 운영 로그 키와 지표 정의

### Main Deliverables
- `multiplayer_test_scenarios.md`
- 자동 시나리오 runner 초안
- artifact 폴더 구조
- anomaly / checklist report template
- observability spec (`traceId`, `roomId`, `gameId`, `actionId`)

### Scenarios Owned
- 정상 2인 게임 1판 완료
- disconnect 후 resume
- 현재 턴이 아닌 플레이어 액션 reject
- 중복 action resend
- stateVersion mismatch 후 snapshot resync
- 타임아웃/기권 처리
- reconnect grace period 초과
- 서버/클라이언트 간 choice mismatch

### Done Criteria
- 핵심 시나리오가 자동화되어 반복 실행 가능하다.
- 실패 시 로그, state snapshot, replay artifact가 남는다.
- 운영 중 desync나 reject 증가를 지표로 감지할 수 있다.

## Dependency Structure

### Agent 1 -> Agent 2
- 공용 game state contract
- command validation rules
- event/replay schema

### Agent 1 -> Agent 3
- authoritative state 모델
- UI에 필요한 choice/turn/timer payload

### Agent 1 + Agent 2 -> Agent 4
- 실제 protocol과 room lifecycle contract
- reconnect/timeout/error 정책

### Agent 2 -> Agent 3
- auth/session/room API
- WebSocket event envelope

### Agent 4 -> All Agents
- 회귀 시나리오 요구사항
- debug artifact 요구사항
- 실패 재현 정보

## Work Order

### Phase 0: Contract Lock
- Agent 1: game state / command / event 초안 작성
- Agent 2: room/session envelope 초안 작성
- Agent 4: scenario matrix 초안 작성
- Agent 3: 필요한 client payload 필드 검토

### Phase 1: Headless End-to-End
- Agent 1: headless game session 완성
- Agent 2: in-memory room + WebSocket 연결 완성
- Agent 4: CLI/socket 시나리오 5~8개 자동화
- Agent 3: UI 없이 networking stub로 연결 확인

### Phase 2: iOS Integration
- Agent 3: room/match UI 연결
- Agent 2: reconnect/session 안정화
- Agent 1: reject/recovery edge case 보강
- Agent 4: reconnect/race 회귀 시나리오 확장

### Phase 3: Hardening
- Agent 2: persistence/metrics 추가
- Agent 3: UX polish
- Agent 1: replay/export 안정화
- Agent 4: anomaly report + 운영 대시보드 기준선 정리

## Management Rules

### 1. Single Owner Per Contract
- 상태 스키마와 룰 판정 계약은 Agent 1 소유
- room/session/network envelope는 Agent 2 소유
- 앱 화면/입력 경험은 Agent 3 소유
- test scenario, artifact, observability는 Agent 4 소유

### 2. No Cross-Layer Hidden Logic
- Agent 3는 룰 판정을 구현하지 않는다.
- Agent 2는 카드 룰을 재해석하지 않는다.
- Agent 4는 임시 검증용 우회 로직을 production flow에 넣지 않는다.

### 3. Every Handoff Needs Evidence
- 코드 handoff 시 필요한 문서:
  - contract 문서 링크
  - sample payload
  - known limitation
  - verification result

### 4. Shared IDs
- 모든 agent는 아래 ID를 공통 사용한다.
  - `traceId`
  - `roomId`
  - `gameId`
  - `turnId`
  - `actionId`
  - `playerId`

## Suggested File Ownership
- Agent 1:
  - `GoStop/Core/`
  - `GoStopCLI/`
  - `multiplayer_contract.md`
- Agent 2:
  - `Server/` 또는 향후 서버 디렉터리
  - `room_protocol.md`
- Agent 3:
  - `GoStop/Views/`
  - `GoStop/ViewModels/` 또는 UI state layer
  - `multiplayer_ui_flow.md`
- Agent 4:
  - `tests/test_agent/`
  - `test_artifacts/`
  - `multiplayer_test_scenarios.md`

## Recommended First Tasks Per Agent

### Agent 1 First Task
- 현재 `GoStop/Core` 상태 중 멀티플레이 서버가 꼭 알아야 하는 필드만 추려 `authoritative match state` 문서를 만든다.

### Agent 2 First Task
- `roomCreated -> joined -> ready -> gameStarted -> disconnected -> resumed` 흐름을 기준으로 room state machine을 정의한다.

### Agent 3 First Task
- iOS에서 필요한 multiplayer 화면 흐름을 `entry -> room -> live match -> reconnect overlay -> result`로 와이어프레임 수준에서 정리한다.

### Agent 4 First Task
- 아래 8개를 최소 회귀 세트로 고정한다.
  - 정상 시작
  - 정상 1판 종료
  - 현재 턴 외 액션 reject
  - 중복 action
  - choice mismatch
  - disconnect 후 resume
  - grace period 초과
  - snapshot resync

## Practical PM View

이 4-agent 구조에서 실제 우선순위는 아래가 맞다.

1. Agent 1이 계약과 엔진을 먼저 고정
2. Agent 2가 room/server lifecycle을 붙임
3. Agent 4가 같은 시점에 자동 시나리오와 artifact 체계를 만든다
4. Agent 3가 가장 늦게 UI를 얹되, 초기에 필요한 payload 요구사항은 먼저 제시한다

즉, 구현 순서는 `1 -> 2 + 4 -> 3`에 가깝고, 운영 관리는 4개 agent가 병렬로 움직이는 형태가 가장 안정적이다.
