# Multi-Agent Operating Guide

## Goal
- 4개의 agent를 실제로 동시에 돌리되, 같은 저장소에서 충돌 없이 병렬 작업이 가능하도록 운영 규칙을 고정한다.
- 기준 대상은 아래 4개 agent다.
  - Agent 1: Core Engine / Game Authority
  - Agent 2: Backend / Lobby / Reconnect
  - Agent 3: iOS Multiplayer Client / UX
  - Agent 4: Debugging / Test Scenarios / Observability

## Short Answer
- 가장 좋은 방법은 `agent별 git worktree + agent별 Codex 세션 + 공통 계약 문서 + 정해진 merge 순서`로 운영하는 것이다.
- 한 작업 디렉터리에서 4개 agent가 동시에 같은 파일을 만지게 하면 거의 반드시 충돌한다.

## Recommended Setup

### 1. Separate Worktrees
- agent마다 독립 worktree를 하나씩 만든다.
- branch도 agent별로 분리한다.

예시:

```bash
git worktree add ../GoStop_agent1_core -b codex/agent1-core
git worktree add ../GoStop_agent2_backend -b codex/agent2-backend
git worktree add ../GoStop_agent3_ios -b codex/agent3-ios
git worktree add ../GoStop_agent4_test -b codex/agent4-test
```

이렇게 해야 하는 이유:
- 각 agent가 독립 파일 상태를 가진다.
- 서로 다른 빌드/로그/임시 파일이 섞이지 않는다.
- merge 전에 diff를 agent 단위로 검토할 수 있다.

### 2. One Codex Session Per Agent
- 각 worktree마다 Codex 세션을 별도로 연다.
- 각 세션 첫 메시지에서 역할, 범위, 금지사항, 산출물을 명시한다.

예시 원칙:
- Agent 1 세션은 `GoStop/Core`, `GoStopCLI`, 계약 문서만 수정
- Agent 2 세션은 서버/room/protocol만 수정
- Agent 3 세션은 iOS UI/ViewModel만 수정
- Agent 4 세션은 `tests/test_agent`, `test_artifacts`, 검증 문서만 수정

### 3. Shared Contract Files
- 아래 파일은 모든 agent가 읽되, owner만 수정한다.

권장:
- `multiplayer_contract.md` : Agent 1 소유
- `room_protocol.md` : Agent 2 소유
- `multiplayer_ui_flow.md` : Agent 3 소유
- `multiplayer_test_scenarios.md` : Agent 4 소유
- `agent_sync_board.md` : PM/통합용 공용 보드

## How To Run In Parallel

### Phase 0: Contract Lock First
- 병렬 시작 전에 먼저 계약부터 잠근다.
- 완전히 오래 걸리는 구현 전에 최소 계약 문서를 먼저 만든다.

순서:
1. Agent 1이 `game state`, `command`, `event`, `reject reason` 초안 작성
2. Agent 2가 `room/session/websocket envelope` 초안 작성
3. Agent 3가 필요한 payload 필드 코멘트 작성
4. Agent 4가 위 계약 기준으로 scenario matrix 작성

이 Phase가 끝나기 전에는 큰 코드 구현을 시작하지 않는 편이 낫다.

### Phase 1: Independent Build Tracks
- 계약이 잠기면 4개 agent를 동시에 돌린다.

병렬 작업 방식:
- Agent 1: 공용 엔진/headless session 구현
- Agent 2: room server/websocket/reconnect 구현
- Agent 3: UI wireframe/view model skeleton 구현
- Agent 4: test runner/scenario/artifact 체계 구현

핵심은 각 agent가 서로 다른 레이어를 맡되, 계약 문서만 기준으로 맞추는 것이다.

## Merge Strategy

### Recommended Merge Order
1. Agent 1
2. Agent 2
3. Agent 4
4. Agent 3

이 순서를 추천하는 이유:
- Agent 1이 state contract를 만든다.
- Agent 2는 그 contract 위에 네트워크를 붙인다.
- Agent 4는 contract와 server behavior를 검증한다.
- Agent 3는 가장 마지막에 안정된 payload에 UI를 맞추는 편이 재작업이 적다.

### Integration Rule
- 각 agent branch를 바로 `main`에 합치지 않는다.
- `codex/multiplayer-integration` 같은 통합 branch를 하나 둔다.
- 통합 branch에서 순서대로 merge하고 smoke test를 돈다.

## Daily Operating Loop

### 1. Start-of-Day
- 10분 이내로 오늘 목표를 고정한다.
- 각 agent는 아래 4가지만 쓴다.
  - 오늘 목표
  - 수정 파일 범위
  - 의존 계약
  - 완료 기준

### 2. Midday Sync
- 60~90분 단위로 짧게 sync 한다.
- 공유 내용은 아래만 허용한다.
  - 계약 변경 여부
  - blocker
  - 예상 merge 시점
  - 테스트 결과

### 3. End-of-Day
- 각 agent는 handoff note를 남긴다.
- 내용:
  - 완료 항목
  - 미완료 항목
  - 변경 파일
  - 실행한 검증
  - 다음 agent가 알아야 할 리스크

## What To Ask Each Agent

### Agent 1 Prompt Template
```text
너는 Agent 1이다. 역할은 Core Engine / Game Authority다.
수정 범위는 GoStop/Core, GoStopCLI, multiplayer_contract 문서로 제한한다.
목표는 authoritative game state, command validation, event schema를 고정하는 것이다.
UI, 서버 room lifecycle, test runner 구현은 하지 마라.
모든 결과는 deterministic해야 하고 reject reason/stateVersion을 명시해야 한다.
작업 전후로 변경 파일, 계약 변경점, 검증 결과를 요약해라.
```

### Agent 2 Prompt Template
```text
너는 Agent 2이다. 역할은 Backend / Lobby / Reconnect다.
수정 범위는 서버 디렉터리, room protocol, session lifecycle로 제한한다.
Agent 1의 contract를 소비하되 재해석하지 마라.
목표는 room, websocket, reconnect, timeout, forfeit 흐름을 구현하는 것이다.
룰 판정은 엔진에 위임하고, 서버는 orchestration만 담당해라.
작업 전후로 API/event 변화와 검증 결과를 남겨라.
```

### Agent 3 Prompt Template
```text
너는 Agent 3이다. 역할은 iOS Multiplayer Client / UX다.
수정 범위는 SwiftUI view, view model, networking adapter UI layer로 제한한다.
룰 판정 로직을 UI에 넣지 마라.
목표는 room 진입, live match, reconnect overlay, reject/error UX를 구현하는 것이다.
Agent 1/2 계약에 맞는 payload만 소비하고, 필요한 필드가 없으면 문서로 요청해라.
작업 전후로 화면 흐름과 검증 결과를 남겨라.
```

### Agent 4 Prompt Template
```text
너는 Agent 4이다. 역할은 Debugging / Test Scenarios / Observability다.
수정 범위는 tests/test_agent, test_artifacts, test scenario 문서로 제한한다.
목표는 reconnect, invalid action, duplicate action, stateVersion mismatch 등 핵심 회귀 시나리오를 자동화하는 것이다.
production 로직에 테스트용 우회 코드를 넣지 마라.
실패 시 replay, snapshot, log artifact가 남도록 구성해라.
작업 전후로 추가 시나리오와 검증 결과를 남겨라.
```

## Communication Rules

### Use One Shared Sync Board
- `agent_sync_board.md`를 공용 board로 쓴다.
- 각 agent는 자기 섹션만 수정한다.

권장 섹션:
- Current Task
- Blockers
- Contract Questions
- Ready For Merge
- Validation Result

### No Verbal-Only Contract Changes
- 중요한 계약 변경은 채팅으로만 합의하지 않는다.
- 반드시 문서 diff 또는 sample payload로 남긴다.

## Conflict Prevention

### File Ownership
- 한 파일에 owner agent를 정한다.
- owner가 아닌 agent는 그 파일을 바꾸지 않는다.

### Interface Freeze Windows
- Agent 1/2 계약이 자주 바뀌면 Agent 3/4가 계속 깨진다.
- 하루에 1~2번만 contract update window를 열고, 그 외 시간에는 freeze한다.

### Artifact Isolation
- agent별 artifact 경로를 나눈다.

예시:
- `test_artifacts/agent1/`
- `test_artifacts/agent2/`
- `test_artifacts/agent3/`
- `test_artifacts/agent4/`

## Minimum Evidence Before Merge

### Agent 1
- deterministic replay 확인
- invalid action reject 확인

### Agent 2
- room create/join/start 확인
- disconnect/resume 확인

### Agent 3
- reconnect overlay 및 input lock 확인
- reject/error UX 확인

### Agent 4
- 핵심 8개 회귀 시나리오 결과
- 실패 artifact 저장 확인

## Best Practical Pattern

가장 안정적인 방식은 아래다.

1. Agent 1이 오전에 계약을 먼저 고정
2. Agent 2와 Agent 4가 같은 계약 위에서 병렬 구현
3. Agent 3는 stub payload로 UI를 먼저 맞추되, 실제 연결은 오후 통합 시점에 수행
4. 통합 branch에서 Agent 1 -> 2 -> 4 -> 3 순서로 merge
5. 마지막으로 Agent 4가 end-to-end 회귀를 다시 돌린다

## Recommendation

지금 바로 시작한다면 다음 구성이 가장 좋다.

- Agent 1: `authoritative match state + event schema`
- Agent 2: `room state machine + websocket envelope`
- Agent 3: `multiplayer flow wireframe + reconnect UX skeleton`
- Agent 4: `scenario matrix + artifact policy + socket runner skeleton`

즉, 첫날 목표는 "기능 완성"이 아니라 "계약 고정 + 병렬 작업 가능 상태 만들기"여야 한다.
