# Online Matgo Multiplayer Draft

## Goal
- iOS 맞고를 온라인 멀티플레이로 확장해, 서로 다른 사용자가 같은 방에 접속해서 실시간으로 플레이할 수 있게 한다.
- 첫 버전은 `1 vs 1 실시간 방 기반 매치`에 집중하고, 룰 정확성과 재접속 복구를 우선한다.

## Product Scope

### First Release Scope
- 로그인한 사용자가 방 생성 / 초대 / 빠른 매칭으로 대전 시작
- 서버 권한형(authoritative) 턴 진행
- 재접속 복구
- 라운드 결과, 승패, 점수 기록

### Later Scope
- 관전
- 채팅 / 이모트
- 랭크전 / 시즌
- 친구 목록 / 초대 링크
- 대회 / 커스텀 룰

## Recommended Architecture

### 1. Server Authoritative Model
- 클라이언트는 `의도(intent)`만 전송하고, 실제 판정은 서버가 한다.
- 서버가 덱 셔플, 턴 진행, 매칭 선택지, 점수 계산, Go/Stop, 특수 이벤트를 최종 확정한다.
- 클라이언트는 서버 이벤트를 받아 UI만 반영한다.

이 구조를 추천하는 이유:
- 부정행위 방지에 유리하다.
- 두 플레이어 상태 불일치를 줄일 수 있다.
- 재접속 시 서버 snapshot 기준으로 쉽게 복구할 수 있다.

### 2. Transport Split
- `REST`:
  - 로그인
  - 유저 프로필
  - 방 생성/조회
  - 전적/리플레이 조회
- `WebSocket`:
  - 실시간 게임 이벤트
  - 턴 액션 송신
  - ping/pong heartbeat
  - reconnect/resume

### 3. Service Split
- `Auth / Player Service`
- `Lobby / Matchmaking Service`
- `Game Room Service`
- `History / Replay Service`
- `Analytics / Abuse Monitoring`

처음부터 마이크로서비스로 쪼갤 필요는 없고, 초기에는 단일 백엔드로 시작해도 된다. 다만 코드 레벨에서 책임은 분리해두는 편이 낫다.

## GoStop-Specific Design Direction

### 1. Rule Engine Reuse
- 현재 iOS 앱의 `Core` 룰 로직을 서버와 공유 가능한 형태로 분리하는 것이 가장 중요하다.
- 가능하면 `GoStop/Core`를 플랫폼 독립 Swift Package로 정리하고, 아래가 같은 엔진을 쓰게 한다.
  - iOS Client
  - GoStopCLI
  - Multiplayer Game Server

이렇게 해야:
- 싱글/멀티 규칙 차이가 줄어든다.
- 테스트 에이전트와 서버 검증 로직을 같은 규칙 기반 위에서 돌릴 수 있다.
- 룰 수정 시 한 군데만 고치면 된다.

### 2. Hidden Information Policy
- 각 플레이어는 자기 손패만 전체 정보로 보고, 상대 손패와 남은 덱 정보는 서버가 숨겨서 내려준다.
- 디버그/관전/리플레이를 제외하고는 전체 state를 클라이언트에 보내지 않는다.

### 3. Deterministic Match State
- 모든 액션은 `roomId`, `gameId`, `turnId`, `actionId`, `playerId`를 포함한다.
- 서버는 이벤트 로그를 순서대로 적재한다.
- 클라이언트는 `lastAppliedEventId`를 기억해 중복 이벤트를 무시한다.

## Real-Time Match Flow

### Recommended Flow
1. 플레이어 로그인
2. 방 생성 또는 빠른 매칭 요청
3. 두 플레이어가 모두 준비되면 서버가 게임 시작
4. 서버가 초기 패 분배 및 선공 결정
5. 현재 턴 플레이어만 액션 가능
6. 액션 결과를 서버가 판정 후 두 클라이언트에 broadcast
7. 라운드 종료 시 정산
8. 재대국 여부 확인 또는 방 종료

### Turn Handling Rules
- 현재 턴 플레이어 외 액션은 전부 거절
- 선택 분기(예: 먹을 패 선택, Go/Stop)는 반드시 서버가 생성한 선택지 중 하나만 허용
- 타임아웃 정책 필요:
  - 예: 20~30초 내 미응답 시 자동 패배, 자동 Stop, 또는 기권 처리
- 백그라운드 전환 시 grace period 필요:
  - 예: 30초 내 복귀 시 재접속 허용

## Network Protocol Considerations

### Client -> Server Commands
- `createRoom`
- `joinRoom`
- `ready`
- `startGame`
- `playCard`
- `selectCapture`
- `selectShake`
- `chooseGoStop`
- `resume`
- `leaveRoom`
- `ping`

### Server -> Client Events
- `roomUpdated`
- `playerJoined`
- `gameStarted`
- `turnChanged`
- `actionAccepted`
- `actionRejected`
- `statePatched`
- `choiceRequested`
- `roundEnded`
- `matchEnded`
- `playerDisconnected`
- `playerReconnected`

### Message Contract Rules
- 모든 메시지에 `type`, `requestId`, `serverTime`, `roomId`, `gameId` 포함
- 액션 응답에는 `accepted/rejected`, `reason`, `stateVersion` 포함
- 상태 동기화는 full snapshot + delta patch 둘 다 지원
- 클라이언트는 stateVersion이 건너뛰면 snapshot 재요청

## Reconnect / Resume

온라인 맞고에서 재접속 복구는 필수에 가깝다.

### Recommended Policy
- 연결이 끊겨도 즉시 패배 처리하지 않음
- 서버는 일정 시간 방 상태 유지
- 재접속 시 최신 snapshot과 누락 이벤트를 내려줌
- 복구 불가 상태면 라운드 무효가 아니라 명확한 몰수/패배 정책을 둠

### Needed Data
- 현재 손패
- 바닥 패
- 캡처 패
- 점수
- 현재 턴
- 현재 선택 대기 상태
- 남은 시간
- 최근 이벤트 로그

## Fairness / Anti-Cheat

### 반드시 고려할 것
- 셔플은 서버에서만 수행
- 클라이언트는 카드 결과를 임의 계산하지 못하게 함
- 허용되지 않은 액션은 서버에서 즉시 reject
- 같은 액션 재전송에 대비한 idempotency 처리
- 비정상 패킷/과도한 요청 rate limit 적용
- 리플레이/감사 로그 저장

### Avoid
- P2P 직접 동기화
- 클라이언트 전체 state 신뢰
- 턴 결과를 클라이언트 선계산 후 서버 확인만 받는 구조

## iOS Client Considerations

### App Lifecycle
- 백그라운드 진입 시 즉시 연결 상태 표시
- foreground 복귀 시 자동 재연결 시도
- reconnect 중에는 입력 UI 잠금
- 재동기화 완료 후에만 카드 탭 허용

### UX
- 상대 연결 상태 표시
- 내 턴 남은 시간 표시
- 서버 reject 사유를 사용자 친화적 메시지로 노출
- 재접속 복구 중 spinner/skeleton 표시

## Backend Data Model

### Core Entities
- `Player`
- `Session`
- `Room`
- `Match`
- `Round`
- `ActionEvent`
- `Replay`
- `Rating` 또는 `Wallet`

### Persist What Matters
- 최종 승패
- 점수 변화
- 라운드 로그
- disconnect / reconnect 이력
- 신고/제재용 최소 운영 로그

## Operations / Monitoring

### Metrics
- 매칭 성공률
- 방 생성 후 게임 시작률
- 중도 이탈률
- 평균 라운드 시간
- reconnect 성공률
- action reject 비율
- desync 복구 요청 수

### Logs
- `AUTH`
- `LOBBY`
- `ROOM`
- `GAME`
- `REJECT`
- `DISCONNECT`
- `ERROR`

문제 발생 시에는 `roomId`, `gameId`, `playerId`, `turnId`, `actionId`로 추적 가능해야 한다.

## Suggested Rollout Plan

### Phase 1
- 로컬/CLI 기준 엔진 완전 결정론화
- 서버 공용 엔진 패키지 분리
- 단일 방에서 2인 플레이 가능한 WebSocket 서버 구현

### Phase 2
- 초대 기반 비공개 방
- 재접속 복구
- 리플레이 로그 저장

### Phase 3
- 빠른 매칭
- MMR 또는 랭크 점수
- 운영 대시보드/알림

### Phase 4
- 관전
- 채팅/신고
- 시즌/이벤트

## Open Questions
- 첫 버전에서 `친구 초대`와 `빠른 매칭` 중 무엇을 먼저 열 것인가?
- 타임아웃 시 자동 처리 정책을 무엇으로 둘 것인가?
- 멀티플레이 정산 단위를 판 단위로 볼지, 세트/방 단위로 볼지?
- 리플레이를 전체 snapshot 기반으로 저장할지, event log 기반으로 저장할지?
- 서버 구현을 Swift(Vapor)로 해 현재 엔진을 재사용할지, 별도 언어로 둘지?

## Practical Recommendation

현재 저장소 기준으로는 아래 순서가 가장 현실적이다.

1. `GoStop/Core` 룰 로직을 서버 공용으로 재사용 가능하게 정리
2. `GoStopCLI` 기반으로 네트워크 없는 headless match runner를 먼저 완성
3. 그 위에 WebSocket room server를 얹어 2인 대전을 붙임
4. 마지막에 iOS UI를 실시간 room state에 연결

핵심은 "멀티플레이 UI"보다 먼저 "서버가 단일 진실 원본이 되는 엔진 구조"를 만드는 것이다.
