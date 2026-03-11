# Multiplayer Test Scenarios

## Meta
- **Owner**: Agent 4
- **Primary Consumers**: Agent 1, Agent 2, Agent 3
- **Status**: Draft
- **Last Updated**: 2026-03-11
- **Related Docs**:
  - `multiplayer_contract.md`
  - `room_protocol.md`
  - `multiplayer_ui_flow.md`
  - `agent_sync_board.md`

## Goal
- 온라인 맞고 멀티플레이의 핵심 회귀 시나리오, artifact 정책, observability 요구사항을 정의한다.
- 실패 시 재현 가능한 증거가 항상 남도록 한다.

## Scope
- scenario matrix
- smoke / regression / soak categories
- required artifact structure
- log and trace requirements
- anomaly classification

## Non-Goals
- 프로덕션 룰 계약 변경
- room protocol 소유권 변경
- UI 문구 상세 확정

## Test Strategy

### Layers
- engine-level deterministic validation
- room/session integration validation
- websocket protocol validation
- iOS client reconnect / UX smoke
- end-to-end multiplayer regression

### Modes
- headless local
- socket integration
- simulator UI smoke
- replay-based failure reproduction

## Harness Skeleton

### Entrypoint
- `python3 tests/test_agent/multiplayer_runner.py --list`
- `python3 tests/test_agent/multiplayer_runner.py --all-p0`
- `python3 tests/test_agent/multiplayer_runner.py --suite smoke --mode fixture`
- `python3 tests/test_agent/multiplayer_runner.py --suite socket-smoke --mode socket --binary /tmp/gostop_cli_agent4_round7_recheck/Build/Products/Debug/GoStopCLI --skip-build`
- `python3 tests/test_agent/multiplayer_runner.py --suite socket-parity --mode socket --transport compare --skip-build`
- `python3 tests/test_agent/multiplayer_runner.py --suite socket-duplicate --mode socket --transport compare --skip-build`
- `python3 tests/test_agent/multiplayer_runner.py --suite socket-review-fixups --mode socket --binary /tmp/gostop_cli_agent4_round7_recheck/Build/Products/Debug/GoStopCLI --skip-build`
- `python3 tests/test_agent/multiplayer_runner.py --suite review-fixups --mode fixture`
- `python3 tests/test_agent/multiplayer_runner.py --scenario MP-001 --output-root /tmp/gostop_multiplayer_scaffold`
- `python3 tests/test_agent/multiplayer_runner.py --all-p0 --mode fixture --output-root /tmp/gostop_multiplayer_fixture`
- `python3 tests/test_agent/multiplayer_runner.py --scenario MP-008 --mode socket --binary /tmp/gostop_cli_agent4_round7_recheck/Build/Products/Debug/GoStopCLI --skip-build --output-root /tmp/gostop_multiplayer_socket`
- `python3 scripts/run_multiplayer_cli_two_player_smoke.py --scenario all --output-root /tmp/gostop_multiplayer_cli_smoke`

### Files
- `tests/test_agent/multiplayer_runner.py`
  - thin CLI entrypoint for scenario listing and scaffold runs
- `tests/test_agent/multiplayer/models.py`
  - manifest / replay / snapshot / anomaly / scenario result dataclasses
- `tests/test_agent/multiplayer/artifacts.py`
  - artifact layout writer for `manifest.json`, `timeline/`, `snapshots/`, `replay/`, `anomaly_report.md`
- `tests/test_agent/multiplayer/scenarios.py`
  - `MP-001 ~ MP-008`, `MP-013`, `MP-014` registry와 suite mapping
- `tests/test_agent/multiplayer/skeletons.py`
  - `MP-001 ~ MP-008`, `MP-013`, `MP-014` actual Python step skeleton registry
- `tests/test_agent/multiplayer/runner.py`
  - scaffold / fixture / socket runner that materializes artifacts without touching single-player harness
- `tests/test_agent/multiplayer/socket_transport.py`
  - actual GoStopCLI `--room-transport-server` TCP fallback + `--room-transport-websocket-server` websocket binding for socket mode, with live parity smoke for `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014` and live duplicate blocker capture for `MP-004`
- `tests/test_agent/multiplayer/fixtures.py`
  - synthetic room/game transcript fixtures for `MP-001 ~ MP-008`, `MP-013`, `MP-014`
- `tests/test_agent/multiplayer/validators.py`
  - fixture validation logic for runnable P0 checks
- `scripts/run_multiplayer_cli_two_player_smoke.py`
  - GoStopCLI build/run smoke with cached binary reuse, per-scenario `summary.json`, `summary.md`, `transcript.ndjson`, explicit `room_record_game_started -> metadata.gameStartedBootstrapPlan.fetchAction` paired bootstrap assert, and MP-008 hook surface regression

### Separation Rule
- multiplayer harness는 `tests/test_agent/main.py`, `tests/test_agent/test_scenarios.py`와 분리된 별도 entrypoint를 사용한다
- single-player scenario registry와 shared global state를 재사용하지 않는다
- multiplayer artifact root 기본값은 `test_artifacts/multiplayer/`다

### Code-Level Skeletons
- `MP-001`: room create/join/ready auto-start skeleton
- `MP-002`: terminal summary / replay skeleton
- `MP-003`: out-of-turn reject skeleton
- `MP-004`: duplicate `actionId` replay skeleton
- `MP-005`: invalid choice reject skeleton
- `MP-006`: disconnect / resume snapshot-first skeleton
- `MP-007`: reconnect grace expiry / forfeit skeleton
- `MP-008`: `stateVersion` mismatch / resync skeleton
- `MP-013`: shake actor-only hidden-info redaction regression
- `MP-014`: stale/replaced heartbeat reject regression

## Scenario Matrix

| ID | Scenario | Priority | Automation | Primary Focus | Status |
| --- | --- | --- | --- | --- | --- |
| MP-001 | room 생성부터 `gameStarted` 수신까지 bootstrap 성공 | P0 | Scaffolded runner + fixture + CLI smoke + socket parity smoke | room lifecycle + initial snapshot + ID continuity | Fixture PASS / CLI PASS / TCP=websocket PASS |
| MP-002 | 정상 1판 종료 및 결과 정산 일관성 | P0 | Scaffolded runner + fixture + socket terminal parity smoke | deterministic end-of-round + final summary + roomClosed completion | Fixture PASS / TCP=websocket PASS |
| MP-003 | 현재 턴이 아닌 플레이어 action reject | P0 | Scaffolded runner + fixture | reject correlation + no gameplay mutation | Fixture PASS |
| MP-004 | duplicate `actionId` resend의 idempotency | P0 | Scaffolded runner + fixture + socket duplicate smoke | duplicate handling + single apply guarantee | Fixture PASS / TCP=websocket BLOCKED |
| MP-005 | `choiceRequested` 이후 invalid choice code reject | P0 | Scaffolded runner + fixture | invalid choice diagnostics + pending choice stability | Fixture PASS |
| MP-006 | disconnect 후 grace period 내 resume | P0 | Scaffolded runner + fixture | reconnect path + snapshot recovery + input lock | Fixture PASS |
| MP-007 | reconnect grace period 초과 처리 | P0 | Scaffolded runner + fixture | expiry behavior + reject/forfeit ordering | Fixture PASS |
| MP-008 | stateVersion mismatch 후 snapshot resync | P0 | Scaffolded runner + fixture-backed stale-version resync + socket gameplay parity smoke | drift detection + authoritative resync | Fixture PASS / TCP=websocket PASS |
| MP-009 | room ready timeout | P1 | Planned | lobby timeout policy | Draft |
| MP-010 | in-turn timeout 처리 | P1 | Planned | turn timer policy | Draft |
| MP-011 | player reconnect during pending choice | P1 | Planned | choice resume semantics | Draft |
| MP-012 | server reject 후 client UX banner 확인 | P1 | Planned | UI error mapping | Draft |
| MP-013 | shake choice hidden-info leak guard | P1 | Fixture-backed regression + socket projection parity smoke | privacy / viewer-scoped choice payload | Fixture PASS / TCP=websocket PASS |
| MP-014 | replaced or expired session heartbeat reject | P1 | Fixture-backed regression + CLI smoke + socket parity smoke | session hardening / newest-wins policy | Fixture PASS / CLI PASS / TCP=websocket PASS |

## Scenario Template

### Scenario ID
- `MP-XXX`

### Precondition
- room state
- player sessions
- engine state
- feature flags if any

### Steps
1. setup
2. command/event sequence
3. assertions

### Expected
- response / event ordering
- stateVersion behavior
- UI or protocol effect

### Artifacts
- log files
- snapshot
- replay
- anomaly report if failed

## P0 Detailed Scenarios

### MP-001: room bootstrap부터 `gameStarted`까지
- **Goal**: room create/join/ready 이후 auto-start 경로를 거쳐 두 플레이어가 같은 `roomId`와 하나의 `gameId`를 공유한 채 live match bootstrap에 진입하는지 검증한다.
- **Preconditions**:
  - player A, player B 인증 완료
  - 두 클라이언트 모두 WebSocket 연결 및 raw transcript 저장 활성화
  - active room/game 없음
- **Steps**:
  1. player A가 `createRoom`을 호출하고 `roomCreated` 수신을 확인한다.
  2. player B가 `joinRoom`을 호출하고 양쪽 모두 `playerJoined` 수신을 확인한다.
  3. 양쪽이 `setReady`를 전송하고 `memberReadyChanged` 및 `roomState=waitingForReady`를 확인한다.
  4. 두 플레이어가 모두 ready가 되면 `roomEvent.roomStateChanged(toState=starting)`를 수신한다.
  5. 이후 `roomState=inGame`, `gameEvent.engineEvent:gameStarted`, `gameEvent.engineEvent:stateSnapshot(reason=gameStarted)`를 순서대로 수집한다.
- **Assertions**:
  - room-level event와 game-level event에 동일한 `traceId`, `roomId`가 유지된다.
  - public `startGame` command 없이 ready completion만으로 auto-start가 발생한다.
  - room lifecycle은 `waitingForPlayers -> waitingForReady -> starting -> inGame` 순서를 따른다.
  - `activeGameId`가 bootstrap 과정 중 1회만 설정되고, 이후 `gameStarted.gameId`와 일치한다.
  - fresh start bootstrap은 paired `gameStarted` + `stateSnapshot(reason=gameStarted)`로 고정되고, state source of truth는 snapshot이다.
  - 양쪽 최초 projection에는 `stateVersion`, `currentPlayerId`, `turnId`가 존재하고 hidden information 규칙을 위반하지 않는다.
  - `gameStarted`가 중복 발행되지 않는다.
- **Observability Focus**:
  - `roomSequence` 기준 room state transition timeline
  - `activeGameId` 생성 시점
  - 첫 `stateVersion`과 첫 `eventId`
- **Contract Alignment**:
  - fresh start bootstrap source는 paired `gameStarted` + `stateSnapshot(reason=gameStarted)`로 잠겼고, snapshot이 authoritative source다.
- **Failure Artifacts**:
  - room/game raw transcript
  - 양 플레이어 initial snapshot
  - room lifecycle timeline

### MP-002: 정상 1판 종료 및 결과 정산
- **Goal**: 한 판이 `roundEnded` 또는 `matchEnded`까지 단일 authoritative 결과로 종료되고 replay 가능한지 검증한다.
- **Preconditions**:
  - MP-001 bootstrap 성공
  - deterministic seed, canned deck, 또는 replay baseline으로 동일 진행 재현 가능
  - command/event/snapshot 저장 활성화
- **Steps**:
  1. scripted legal command sequence를 수행해 게임을 종료 상태까지 진행한다.
  2. socket probe에서는 terminal relay sample을 호출해 `roundEnded`, `matchEnded`, `terminalSummary` fan-out 또는 정확한 blocker를 기록한다.
  3. ended room에서 host/guest가 차례로 `leaveRoom`을 보내 final `roomClosed`까지 수집한다.
  4. 저장된 snapshot + event log로 replay 입력 패키지를 생성한다.
- **Assertions**:
  - 종료 event는 한 번만 발생하고, winner/score summary가 양 플레이어 view에서 모순되지 않는다.
  - `final summary`, `scoreboard`, `lastEventId`가 replay manifest와 일치한다.
  - replay 입력으로 동일한 종료 결과를 재생성할 수 있다.
  - result dismissal path는 최종 `leaveRoom` 이후 `roomClosed`로 끝나야 한다.
- **Observability Focus**:
  - final score delta
  - 종료 직전 마지막 성공 command
  - replay 패키지의 engine/rule config version
  - `terminalSummary` relay status와 `roomClosed` roomSequence
- **Contract Alignment**:
  - terminal result baseline은 `MultiplayerRoundEndedPayload` / `MultiplayerMatchEndedPayload`를 사용하고, replay artifact는 terminal summary와 final snapshot을 기준으로 생성한다.
  - socket smoke는 `recordMatchEndedAndFetchTerminalSummary` transport path에서 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed`를 실제로 assert한다.
- **Failure Artifacts**:
  - full command/event timeline
  - final snapshot 양쪽 버전
  - replay package
  - anomaly report

### MP-003: out-of-turn action reject
- **Goal**: 현재 턴이 아닌 플레이어의 command가 명확한 reject로 끝나고 authoritative gameplay state는 변하지 않는지 검증한다.
- **Preconditions**:
  - `phase=inTurn`
  - `currentPlayerId=player_a`
  - player B가 조작 가능한 연결 상태
- **Steps**:
  1. player B가 `playCard` command를 고유한 `actionId`로 전송한다.
  2. `actionRejected` 또는 동등한 reject envelope를 수신한다.
  3. reject 직후 최신 snapshot 또는 state hash를 수집한다.
- **Assertions**:
  - reject code는 `outOfTurn`이어야 한다.
  - reject 전후 `stateVersion`은 동일해야 한다.
  - `turnId`, `currentPlayerId`, table/captured/scoreboard hash는 reject 전후 동일해야 한다.
  - 해당 `actionId`에 대응하는 `actionAccepted` 또는 gameplay mutation event가 없어야 한다.
  - reject payload는 `actionId`, `playerId`, `requestId`를 포함해야 한다.
- **Observability Focus**:
  - reject 발생 시의 `turnId`, `currentPlayerId`
  - reject 전후 state hash
  - reject code distribution
- **Failure Artifacts**:
  - reject 직전/직후 snapshot
  - offending command payload
  - reject event payload

### MP-004: duplicate `actionId` resend
- **Goal**: 동일한 `actionId`를 재전송해도 게임 상태가 한 번만 적용되는지 검증한다.
- **Preconditions**:
  - `phase=inTurn`
  - current player가 legal transport gameplay command를 보낼 수 있음
  - 네트워크 재시도 시뮬레이션을 위해 request duplication 가능
- **Steps**:
  1. current player가 legal gameplay command를 `actionId=act_dup_001`로 전송한다.
  2. 첫 응답 또는 후속 event 일부를 받은 뒤 동일한 `actionId`를 같은 payload로 다시 전송한다.
  3. 다시 같은 `actionId`로 payload를 바꿔 보내 conflict path를 연다.
  4. duplicate/conflict 직후 이벤트 스트림과 최신 snapshot을 수집한다.
- **Assertions**:
  - 최초 command는 정상 반영되더라도 duplicate resend는 second mutation을 만들면 안 된다.
  - exact same body의 duplicate resend는 `duplicateActionIdDisposition=exactReplay`와 기존 authoritative result replay로 처리돼야 한다.
  - conflicting reuse는 `duplicateActionIdDisposition=conflictReject`와 `actionRejected(code=actionIdConflict)`로 처리돼야 한다.
  - replay 시 기존 `eventId`와 동일한 `eventId` 재전달을 허용하되, consumer는 중복 적용을 하지 않아야 한다.
  - 어느 경우든 duplicate resend 자체로 새 `stateVersion` 증가나 second mutation이 생기면 안 된다.
  - observability 상 original request와 duplicate request가 같은 `actionId`로 묶여야 한다.
- **Observability Focus**:
  - first-seen vs duplicate-seen timestamp
  - `actionId`와 `requestId` 매핑
  - duplicate 이후 추가 `eventId`/`stateVersion` 발생 여부
- **Failure Artifacts**:
  - original/duplicate command pair
  - duplicate window event slice
  - duplicate 전후 snapshot diff
  - `duplicate_probe.json`
- **Current Live Status**:
  - fixture transcript는 PASS다.
  - actual TCP fallback / websocket compare smoke는 같은 blocker를 재현한다.
  - observed live blocker: duplicate resend가 `exactReplay` 대신 fresh `staleStateVersion -> stateSnapshot(reason=resync)` 경로로 빠지고, conflicting reuse도 `actionIdConflict` 대신 same stale reject로 귀결된다.

### MP-005: invalid choice code reject
- **Goal**: `choiceRequested` 이후 허용되지 않은 choice code를 보내면 reject가 충분한 진단 정보와 함께 발생하는지 검증한다.
- **Preconditions**:
  - `phase=choicePending`
  - active `choiceId`와 `options[]`를 수신 완료
  - invalid code가 현재 options에 존재하지 않음
- **Steps**:
  1. 합법적인 진행으로 `choiceRequested`를 발생시킨다.
  2. 선택지 목록에 없는 code 또는 잘못된 `choiceId`로 `selectCapture`/`selectShake`/`chooseGoStop`을 전송한다.
  3. reject 이후 pending choice 상태를 다시 읽는다.
- **Assertions**:
  - reject code는 `invalidChoice`여야 한다.
  - reject는 `choiceId`, `choiceKind`, rejected code, latest `stateVersion`를 상관관계 있게 남겨야 한다.
  - invalid choice 한 번으로 pending choice가 조기 소멸하거나 turn owner가 바뀌면 안 된다.
  - 최신 authoritative pending choice는 여전히 확인 가능해야 한다.
- **Observability Focus**:
  - `choiceRequested` payload hash
  - reject에 포함된 current choice identity
  - invalidChoice 발생 시 stale UI 여부 판단 가능성
- **Failure Artifacts**:
  - `choiceRequested` raw payload
  - invalid choice command payload
  - reject 직후 pending choice snapshot

### MP-006: disconnect 후 grace period 내 resume
- **Goal**: disconnect가 발생해도 grace period 내 reconnect/resume 시 authoritative snapshot으로 안전하게 복귀하는지 검증한다.
- **Preconditions**:
  - active game 진행 중
  - reconnect 대상 플레이어의 resume credential 보유
  - disconnect/reconnect 이벤트와 snapshot 저장 활성화
- **Steps**:
  1. player B 연결을 인위적으로 끊고 `playerDisconnected`를 확인한다.
  2. grace period가 만료되기 전에 player B가 동일 identity로 reconnect/resume을 시도한다.
  3. server가 복구 절차를 수행하는 동안 room-level event와 game snapshot 전달 순서를 기록한다.
  4. player B client가 최신 snapshot 수신 후 입력 가능 상태로 돌아오는지 확인한다.
- **Assertions**:
  - resume 성공 시 새 좌석이나 새 `playerId`가 생성되면 안 된다.
  - reconnect는 disconnect 후 30초 grace window 안에서만 성공해야 한다.
  - reconnecting client는 `helloAck -> roomSnapshot -> gameEvent(stateSnapshot reason=resume) -> live events` 순서를 따라야 한다.
  - reconnect 직후 player B는 `stateSnapshot(reason=resume)` 또는 동등한 authoritative snapshot을 반드시 수신해야 한다.
  - resync 완료 전까지 입력은 잠겨 있어야 하며, 완료 후 local state hash가 server snapshot과 일치해야 한다.
  - reconnecting client 소켓에서는 `playerReconnected`가 snapshots 뒤에 와야 하고, 다른 플레이어 관점에서도 connection state가 복구된다.
- **Observability Focus**:
  - disconnectAt / reconnectAt / recoveryCompleteAt
  - `messageId`, `roomSequence`, `eventId` ordering
  - resume latency
  - snapshot delivery order
- **Failure Artifacts**:
  - disconnect-resume timeline
  - reconnect 직후 authoritative snapshot
  - local vs server state hash 비교

### MP-007: reconnect grace period 초과
- **Goal**: reconnect가 grace deadline을 넘긴 경우 resume이 거절되고 종료 정책이 일관되게 적용되는지 검증한다.
- **Preconditions**:
  - active game 또는 resumable room 존재
  - disconnect된 player의 grace timer가 시작됨
  - wait 또는 mocked clock으로 expiry 유도 가능
- **Steps**:
  1. 특정 플레이어 연결을 끊고 `playerDisconnected`를 확인한다.
  2. 30초 reconnect grace를 초과할 때까지 대기하거나 테스트 클록을 진행한다.
  3. 동일 resume credential로 `resume` 또는 `resumeRoom`을 시도한다.
  4. reject, forfeit, room close, match end event를 순서대로 수집한다.
- **Assertions**:
  - resume 시도는 `resumeExpired` 또는 동등한 만료 사유로 거절돼야 한다.
  - `starting` 또는 `inGame`에서는 grace expiry가 room-level forfeit로 이어져야 한다.
  - 재연결 실패 후 room/match 최종 상태가 replay와 summary에 반영돼야 한다.
  - expiry 판단에 필요한 deadline 정보가 artifact에서 역추적 가능해야 한다.
- **Observability Focus**:
  - disconnectAt / graceDeadline / resumeAttemptAt
  - expiry reason code
  - expiry 이후 room/game terminal event ordering
- **Contract Alignment**:
  - grace expiry는 `quit(reason=disconnectTimeout)`로 귀결되며, terminal summary는 `endReason=disconnectTimeout`, `forfeitingPlayerId`, `settlementSummary=nil` 조합으로 설명된다.
- **Failure Artifacts**:
  - grace timeout timeline
  - expired resume request/response
  - terminal room/game snapshot

### MP-008: stateVersion mismatch 후 snapshot resync
- **Goal**: client local state가 authoritative `stateVersion`과 어긋났을 때 silent drift 없이 snapshot resync로 복구되는지 검증한다.
- **Preconditions**:
  - active game 진행 중
  - fault injection 또는 event drop으로 stale local state를 만들 수 있음
  - local snapshot hash와 authoritative snapshot hash를 비교 가능
- **Steps**:
  1. deterministic mismatch path는 stale `expectedStateVersion` override로 고정한다.
  2. mismatch 유발 전에 `injectedMismatchMode`, `clientStateVersion`, `expectedStateVersion`, `authoritativeStateVersion`, `authoritativeEventId`, `recoverySnapshotReason`, `recoverySnapshotId`를 `replay/injection_manifest.json`에 기록한다.
  3. stale local state 상태에서 다음 command를 보내 `actionRejected(rejectCode=staleStateVersion)`로 mismatch를 감지한다.
  4. `timeline/mismatch.ndjson`에 client/expected/authoritative version cursor를 남긴다.
  5. `stateSnapshot(reason=resync)`를 수신하고 local state를 authoritative snapshot으로 교체한다.
  6. resync 완료 후 동일 플레이를 계속 진행해 후속 desync가 없는지 본다.
- **Assertions**:
  - mismatch는 raw logs 기준으로 `clientStateVersion`, `expectedStateVersion`, `authoritativeStateVersion`, `authoritativeEventId`가 함께 명시돼야 한다.
  - resync 완료 전 입력은 잠겨 있어야 한다.
  - resync 후 local snapshot hash는 authoritative snapshot hash와 동일해야 한다.
  - mismatch 이후 기존 stale patch를 계속 적용해 state drift가 누적되면 안 된다.
  - run이 중간 실패해도 `replay/injection_manifest.json`과 `timeline/mismatch.ndjson`만으로 stale-version fault path를 재현 가능해야 한다.
- **Observability Focus**:
  - client/expected/authoritative version cursor
  - authoritative reject `eventId`
  - resync trigger reason
  - resync latency와 성공/실패 횟수
- **Contract Alignment**:
  - P0 deterministic path는 stale `expectedStateVersion` override다.
  - artifact minimum fields는 `injectedMismatchMode`, `clientStateVersion`, `expectedStateVersion`, `authoritativeStateVersion`, `authoritativeEventId`, `recoverySnapshotReason`, `recoverySnapshotId`다.
  - command stale reject path의 recovery snapshot reason은 `resync`다.
  - socket mode는 actual TCP `--room-transport-server`를 통해 live stale reject/recovery snapshot을 실행하며, current P0 smoke는 deterministic `quit` command를 사용한다.
  - current live socket smoke는 `actionRejected(staleStateVersion)`와 `stateSnapshot(reason=resync)`를 같은 transport run에서 잠근다.
  - dropped game event 기반 gap injection과 broader live `playCard` mismatch coverage는 다음 phase extension으로 남긴다.
- **Failure Artifacts**:
  - stale local snapshot
  - authoritative recovery snapshot
  - mismatch 직전/직후 event slice
  - `replay/injection_manifest.json`
  - `timeline/mismatch.ndjson`
  - resync transcript

## Targeted Review Regressions

### MP-009: room ready timeout
- **Goal**: 한 명의 플레이어가 ready를 지연시켜 `join expires` deadline을 넘길 때 lobby가 정상 취소되는지 검증한다.
- **Preconditions**:
  - `roomState=waitingForReady`
  - join expires 시간 단축 설정 가능
- **Steps**:
  1. player A가 `createRoom` 호출.
  2. player B가 `joinRoom` 호출 후 ready하지 않고 대기.
  3. timeout 시간이 지날 때 서버 사이드의 강제 room close 이벤트를 대기한다.
- **Assertions**:
  - `joinExpiresAt` 시점 이후 `roomClosed` 이벤트가 전파된다.
  - 양쪽 클라이언트 모두 `roomEvent.reason = readyTimeout`를 수신한다.
- **Observability Focus**:
  - `joinExpiresAt`와 실제 close 이벤트 시간차
- **Failure Artifacts**:
  - timeout 직전/직후 event stream

### MP-010: in-turn timeout 처리
- **Goal**: 플레이어가 턴 시간을 초과했을 때 자동 action(예: `playRandomCard` 또는 `autoForfeit`)이 수행되고 turn이 넘어가는지 검증한다.
- **Preconditions**:
  - `phase=inTurn`
  - turn timer deadline 존재
- **Steps**:
  1. player A의 turn이 돌아왔을 때 action을 수행하지 않고 timer deadline을 넘긴다.
  2. 시스템에 의해 자동 생성된 `actionAccepted` 및 `turnChanged` 이벤트를 확인한다.
- **Assertions**:
  - 클라이언트 입력 없이 권위 있는(authoritative) 턴 변경 이벤트가 생성된다.
  - 자동 선택된 행동(e.g., auto play)이 규칙에 맞게 state를 변경한다.
- **Observability Focus**:
  - timer expiration stamp vs system action stamp
- **Failure Artifacts**:
  - auto-action event payload 및 전후 snapshot

### MP-011: player reconnect during pending choice
- **Goal**: `choicePending` 턴을 가진 플레이어가 연결 해제 후 복귀했을 때 선택지를 정상적으로 다시 받고 응답할 수 있는지 검증한다.
- **Preconditions**:
  - `phase=choicePending`
  - player A가 선택해야 하는 상황
- **Steps**:
  1. player A의 연결을 끊고 `playerDisconnected` 확인.
  2. grace period 내 복귀하여 resume snapshot 수신.
  3. player A가 다시 똑같은 `choiceId`와 `options`를 포함한 pending choice state를 복원받는지 확인.
  4. 복원된 후 정상적으로 choice 응답(예: `selectCapture`)을 보낸다.
- **Assertions**:
  - resume snapshot 안에 `pendingChoice`가 온전히 포함된다.
  - 응답한 choice가 이전과 같은 `eventId` 혹은 올바른 turn sequence에서 `actionAccepted`로 처리된다.
- **Failure Artifacts**:
  - disconnect 직전 / resume 직후 / choice reject(실패 시) payload

### MP-012: server reject 후 client UX banner 확인
- **Goal**: 잘못된 resume 또는 join 요청 시 UI 상 에러 배너 state(`entryBanner`)가 정상 매핑되는지 검증한다.
- **Preconditions**:
  - MultiplayerEntryView에서 잘못된 resume token으로 초기화.
- **Steps**:
  1. player B가 유효하지 않은 credential로 인증/방 접속 시도.
  2. 서버로부터 `joinRejected` 또는 `resumeRejected` 반환.
  3. `MultiplayerShellState`의 `MultiplayerEntryShellState.lastError`가 세팅되는지 확인.
- **Assertions**:
  - 오류 코드(`invalidCredential`, `fullRoom` 등)에 맞게 `lastError.code`와 `messageKey`가 노출된다.
  - 배너 노출 후에도 UI loop가 멎거나 크래시나지 않고 재초기화될 수 있다.
- **Failure Artifacts**:
  - reject payload / UI state dump
  
## Targeted Review Regressions

### MP-013: shake choice hidden-info leak guard
- **Goal**: `askingShake`가 actor에게만 실제 hand metadata를 보여 주고, non-actor projection에는 redacted choice만 남기는지 검증한다.
- **Preconditions**:
  - `choiceKind=shake` pending state 진입 가능
  - actor / non-actor player-scoped snapshot 비교 가능
- **Steps**:
  1. actor player A 기준으로 `askingShake`를 발생시킨다.
  2. 같은 `choiceId`에 대한 actor snapshot과 non-actor snapshot을 각각 저장한다.
  3. `cards`, `metadata`, `options`, `visibility` 필드를 비교한다.
- **Assertions**:
  - actor snapshot에는 `visibility=actorOnly`, 실제 shake 후보 카드, option metadata가 남아야 한다.
  - non-actor snapshot은 동일 `choiceId`와 option label은 유지하되 `cards=[]`, `metadata=null`로 redaction돼야 한다.
  - raw artifact 어디에도 non-actor 관점의 hidden hand identifier가 새지 않아야 한다.
- **Contract Alignment**:
  - fixture가 deterministic baseline을 제공하고, socket parity smoke는 TCP fallback / websocket transport 모두에서 actor/peer `get_multiplayer_projection` payload를 직접 비교해 동일 redaction 규칙을 재검증한다.
- **Failure Artifacts**:
  - actor / non-actor projection pair
  - `choiceRequested` raw payload
  - payload diff note

### MP-014: stale/replaced heartbeat reject
- **Goal**: disconnectedGrace 또는 replaced connection에서 온 heartbeat가 current session ownership을 되돌리지 못하고 reject되는지 검증한다.
- **Preconditions**:
  - guest session이 한 번은 disconnect, 한 번은 resume/newest connection 교체를 거침
  - CLI ingress 또는 fixture에서 `room_heartbeat` error shape 확인 가능
- **Steps**:
  1. guest를 disconnect시킨 뒤 old connection으로 heartbeat를 보낸다.
  2. guest를 새 connection으로 resume한 뒤 old connection으로 heartbeat를 다시 보낸다.
  3. 최신 room snapshot에서 `connectedConnectionId`와 heartbeat owner가 유지되는지 확인한다.
- **Assertions**:
  - disconnectedGrace heartbeat는 `invalidResumeState`로 reject된다.
  - replaced/stale heartbeat는 `staleConnectionId`로 reject된다.
  - reject 이후에도 current `connectedConnectionId`와 session ownership은 newest connection에 남는다.
- **Failure Artifacts**:
  - heartbeat command pair
  - reject payload pair
  - post-reject room snapshot

## Smoke Suite
- `MP-001`
- `MP-006`

## Socket Smoke Suite
- `MP-001`
- `MP-002`
- `MP-008`
- `MP-014`

## Socket Parity Suite
- `MP-001`
- `MP-002`
- `MP-008`
- `MP-013`
- `MP-014`

## Socket Duplicate Suite
- `MP-004`

## Review Fixup Regression Suite
- `MP-013`
- `MP-014`

## Socket Review Fixup Regression Suite
- `MP-013`
- `MP-014`

## Core Regression Suite
- `MP-001` ~ `MP-008`

## Extended Regression Suite
- timeout / reconnect / mismatch / repeated resume / stale session cases

## Artifact Policy

### Required Per Run
- `manifest.json`
- `timeline/commands.ndjson`
- `timeline/events.ndjson`
- `timeline/assertions.ndjson`
- `snapshots/`
- `logs/agent.log`
- `summary.md`

### Suggested Path Layout
```text
test_artifacts/multiplayer/<scenario_id>/<run_id>/
  manifest.json
  logs/
    agent.log
    room.log
    engine.log
  timeline/
    commands.ndjson
    events.ndjson
    assertions.ndjson
  snapshots/
    player_a_initial.json
    player_b_initial.json
    latest_server.json
  replay/
    replay_manifest.json
    event_stream.ndjson
    snapshot_reference.json
  ui/
    reconnect.png
  anomaly_report.md
  checklist_report.md
  summary.md
```

### Minimum Manifest Fields
```json
{
  "runId": "run_001",
  "scenarioId": "MP-001",
  "roomId": "room_001",
  "gameId": "game_001",
  "players": ["player_a", "player_b"],
  "result": "PASS|FAIL|MANUAL",
  "startedAt": "2026-03-08T15:30:00+09:00"
}
```

### Failure Retention Rules
- `FAIL`은 raw command/event transcript, snapshot pair, anomaly report를 반드시 유지한다.
- `PASS`는 `manifest.json`, `summary.md`, final snapshot, condensed timeline만 남겨도 된다.
- `MANUAL` 또는 flaky 판정은 `FAIL`과 동일 수준으로 보존한다.
- reconnect, duplicate, invalid choice, resync 실패는 UI capture가 있으면 같이 저장한다.
- authority replay full stream은 `privilegedDebugOnly` 정책을 따르며, fixture/CLI/socket/manual-debug 실패 또는 explicit export 때만 유지한다.

### Mandatory Failure Artifacts
- offending command payload와 직전 마지막 성공 command
- raw event slice with `traceId`, `roomId`, `gameId`, `turnId`, `actionId`, `eventId`, `messageId`, `roomSequence`
- failure 직전 local snapshot과 authoritative snapshot
- `anomaly_report.md`
- 재실행 명령 또는 replay pointer

### Anomaly Report Minimum Sections
- scenario / run metadata
- expected vs observed behavior
- first bad transition
- last good `eventId` / `stateVersion`
- failure classification
- reproduction command
- artifact links

### Code Skeleton Status
- `tests/test_agent/multiplayer/scenarios.py`에 `MP-001 ~ MP-008`, `MP-013`, `MP-014`가 모두 등록돼 있다
- `tests/test_agent/multiplayer/skeletons.py`에 `MP-001 ~ MP-008`, `MP-013`, `MP-014` step plan이 모두 등록돼 있다
- `MP-001`, `MP-003`, `MP-006`, `MP-008`은 `room start`, `out-of-turn reject`, `disconnect/resume`, `stateVersion mismatch/resync`를 actual Python step skeleton으로 표현한다
- `MP-013`, `MP-014`는 shake privacy와 stale heartbeat hardening regressions를 actual Python fixture regression으로 표현한다
- `tests/test_agent/multiplayer/runner.py`는 scaffold / fixture / socket mode에서 scenario별 manifest/replay/snapshot/checklist/anomaly artifact를 생성한다
- `tests/test_agent/multiplayer/socket_transport.py`는 actual GoStopCLI TCP fallback + websocket transport harness를 제공하고, `--transport tcp|websocket|compare`를 지원한다
- `fixture` mode는 synthetic transcript를 사용해 `MP-001/002/003/004/005/006/007/008/013/014`를 검증한다
- `tests/test_agent/multiplayer_runner.py --suite smoke --mode fixture`는 `MP-001`, `MP-006`을 유지 smoke로 제공한다
- `tests/test_agent/multiplayer_runner.py --suite socket-smoke --mode socket`는 actual TCP transport 기준 `MP-001`, `MP-002`, `MP-008`, `MP-014`를 green smoke로 유지한다
- `tests/test_agent/multiplayer_runner.py --suite socket-parity --mode socket --transport compare`는 `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`의 TCP fallback vs websocket parity를 같은 artifact layout 아래 비교한다
- `tests/test_agent/multiplayer_runner.py --suite socket-duplicate --mode socket --transport compare`는 `MP-004` live duplicate replay/conflict blocker를 TCP fallback + websocket에서 함께 기록한다
- `tests/test_agent/multiplayer_runner.py --suite socket-review-fixups --mode socket`는 `MP-013`, `MP-014` privacy/session-hardening regressions를 current TCP facade로 재검증한다
- `tests/test_agent/multiplayer_runner.py --scenario MP-008 --mode socket`는 actual live stale reject/recovery snapshot probe를 실행하고 `stateSnapshot(reason=resync)`까지 assert한다
- `tests/test_agent/multiplayer_runner.py --scenario MP-002 --mode socket`는 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed` terminal lifecycle artifact를 생성한다
- `scripts/run_multiplayer_cli_two_player_smoke.py --scenario all`은 `ready-start`, `disconnect-resume`, `heartbeat-guard`, `mp008-hook-surface`, `mp008-gameplay-resync` scenario를 실제 CLI ingress로 확인하고 cached binary를 우선 재사용한다
- current CLI smoke는 `guest ready -> roomState=starting`과 `requiresGameBootstrap=True`를 확인한 뒤, `room_record_game_started` metadata의 `gameStartedBootstrapPlan.fetchAction`과 `requestsByPlayerId`를 그대로 따라 paired `gameStarted + stateSnapshot(reason=gameStarted)`를 assert한다
- `tests/test_agent/multiplayer/runner.py`는 `MP-008`용 `replay/injection_manifest.json`과 `timeline/mismatch.ndjson`을 생성해 stale-version resync artifact 구조를 고정한다
- compare socket run은 `transport_parity.json`, suffixed snapshots(`*_tcp.json`, `*_websocket.json`), combined `timeline/*.ndjson`로 TCP fallback vs websocket diff를 같은 run root에 남긴다
- `MP-004` live duplicate probe는 `duplicate_probe.json`을 남겨 exact replay / conflict reject mismatch를 추적한다
- `MP-013`, `MP-014` privacy/session-hardening regressions는 fixture PASS를 유지하고 socket mode에서도 PASS를 재확인했다
- CLI smoke는 `room_set_mp008_hook -> room_get_mp008_hook -> room_clear_mp008_hook`로 MP-008 deterministic hook surface도 유지 검증한다
- CLI smoke artifact root는 기본적으로 `test_artifacts/multiplayer_cli_smoke/<run_id>/`를 사용한다
- socket runner는 `--binary` 또는 known cached derived data를 fresh build보다 우선해서 offline-friendly하게 실행한다
- known cached binary priority는 최신 verified rebuild(`gostop_cli_agent4_round7_recheck`, `gostop_cli_round7_review`)를 기존 round6/status-check root보다 앞에 둔다
- actual GoStopCLI websocket transport parity smoke는 닫혔고, 남은 외부 binding 작업은 app-side websocket client / simulator capture 경로다

## Observability Requirements

### Required IDs In Logs
- `traceId`
- `roomId`
- `gameId`
- `sessionId`
- `messageId`
- `roomSequence`
- `turnId`
- `actionId`
- `playerId`
- `eventId`
- `connectionId`

### Required Fields By Stream
- command log: `requestId`, `actionId`, `playerId`, `expectedStateVersion`, command name, client send time, server ack/reject time
- room transport log: `messageId`, `roomSequence`, transport `type`, local receive time
- event log: `eventId`, `stateVersion`, `eventName`, `serverTime`, payload summary
- snapshot metadata: source (`initial|periodic|reconnect|resync|terminal`), player scope, capture time, state hash
- reconnect diagnostics: disconnect cause, grace deadline, resume token/session marker, recovery duration, `resumeMode`
- reject diagnostics: reject code, correlated `actionId`, current `turnId`, optional `choiceId`

### Log Categories
- `ROOM`
- `SESSION`
- `CMD`
- `EVENT`
- `REJECT`
- `RESUME`
- `ERROR`

### Derived Metrics
- bootstrap latency
- command round-trip latency
- duplicate action count
- reject count by code
- reconnect recovery latency
- resync count and resync success rate
- event gap count

### Debug Questions Every Failure Should Answer
- 어떤 scenario였는가?
- 마지막 성공 command는 무엇이었는가?
- 어떤 event에서 state drift가 시작됐는가?
- reconnect or timeout path가 개입했는가?
- replay로 재현 가능한가?

## Validation Lenses

### Reconnect Lens
- reconnect 시 동일 `playerId`와 seat identity가 유지되는가?
- resume 성공 전 input lock이 유지되는가?
- reconnecting client가 `helloAck -> roomSnapshot -> gameEvent(stateSnapshot) -> live events` 순서를 받는가?
- snapshot 도착 이후 local hash가 authoritative hash와 일치하는가?
- disconnect 동안 room/game event ordering이 replay로 설명 가능한가?

### Duplicate Action Lens
- 동일 `actionId`가 두 번째 gameplay mutation을 만들지 않는가?
- exact duplicate retry는 result replay이고, conflicting reuse는 reject라는 구분이 logs에 드러나는가?
- duplicate 관련 logs만으로 first apply와 retry를 구분할 수 있는가?

### Invalid Choice Lens
- reject가 `invalidChoice`와 현재 choice identity를 함께 남기는가?
- invalid choice 후 pending choice가 예기치 않게 소멸하지 않는가?
- stale UI와 malformed client를 raw artifact만으로 구분할 수 있는가?

### StateVersion Mismatch Lens
- mismatch 검출 근거가 local/auth version 또는 missing event range로 명확히 드러나는가?
- resync 동안 stale state 사용을 중단하고 input을 잠그는가?
- resync 후에도 후속 event stream이 연속성을 회복하는가?

### Shake Privacy Lens
- actor snapshot과 non-actor snapshot이 같은 `choiceId`를 공유하는가?
- non-actor projection에 `cards`, `metadata`, hidden identifier가 비어 있거나 redacted 되는가?
- privacy regression이 raw diff만으로 재현 가능하게 artifact가 남는가?

### Heartbeat Guard Lens
- disconnectedGrace heartbeat와 stale connection heartbeat가 서로 다른 reject code로 식별되는가?
- stale heartbeat 이후에도 newest `connectionId`와 `sessionId` ownership이 유지되는가?
- CLI ingress와 향후 websocket ingress가 같은 reject semantics를 따르는가?

## Debug Connect Manual Checklist

### Create
- DEBUG launcher에서 multiplayer shell lab 또는 local debug connect entry를 연다.
- host 기준 `Create Room` 직후 `roomId`, `host sessionId`, `host hello`가 생성되고 banner/error 없이 room truth가 보이는지 확인한다.

### Join
- `Join Guest` 직후 guest member가 seat 1로 붙고 host/guest의 `isConnected`, `isReady`, `connectedConnectionId`가 room snapshot truth를 따르는지 확인한다.
- `Join Invite`가 local debug source에서 미지원이면 control이 disabled 또는 explicit unsupported 설명으로 보여야 한다.
- `Join Invite`가 노출된 채 동작한다면 기존 room 없이 눌렀을 때 silent failure가 아니라 명시적 unsupported/error banner가 나오고 shell이 깨지지 않는지 확인한다.

### Ready
- host `Ready` 후 host만 ready로 보이고 guest는 unchanged인지 확인한다.
- guest `Ready` 후 두 플레이어 모두 ready가 되고 `requiresGameBootstrap=True`, `roomState=starting`이 기록되는지 확인한다.

### Start
- local debug flow가 `Apply gameStarted` 또는 동등한 start control을 제공하면 `activeGameId`가 채워지고 `roomState=inGame`으로 넘어가는지 확인한다.
- debug panel 또는 logs에서 `Apply gameStarted` 직후 `room_record_game_started`에 해당하는 room transition과 `activeGameId`가 함께 남는지 확인한다.
- current CLI smoke는 `gameStartedBootstrapPlan.fetchAction`를 따라 paired `gameStarted + stateSnapshot(reason=gameStarted)`까지 확인한다. in-app flow는 live shell이 같은 bootstrap payload를 실제로 소비할 때만 authoritative bootstrap PASS로 본다.

### Live
- live route가 아직 placeholder shell이면 그 사실이 banner/description에 분명히 드러나는지 확인하고, 이를 authoritative bootstrap PASS로 오인하지 않는다.
- live route가 authoritative bootstrap을 소비하는 빌드에서는 mock state가 아니라 bootstrap payload 기반 title/badge/turn HUD가 채워지는지 확인한다.
- shake choice가 뜨면 actor view에는 후보 카드/옵션이 보이고, non-actor view에는 redacted placeholder만 보이는지 확인한다.

### Disconnect
- guest `Disconnect` 직후 reconnect overlay, grace countdown, input lock이 즉시 나타나고 `connectedConnectionId`가 비워지는지 확인한다.
- stale/replaced heartbeat reject가 log에 남고 최신 connection ownership이 유지되는지 확인한다.

### Resume
- grace 내 `Resume` 후 `helloAck -> roomSnapshot -> stateSnapshot(reason=resume)` 순서가 log와 shell state에 드러나는지 확인한다.
- overlay는 snapshot 적용 이후 닫히고, guest `connectionId`가 새 값으로 회전하며 live route가 유지되는지 확인한다.

### Artifact Capture
- 수동 점검 실패 시 `traceId`, `roomId`, `sessionId`, `connectionId`, screenshot, raw event slice, banner text를 같은 run artifact 아래 저장한다.

## Failure Classification

| Class | Meaning | Typical Owner |
| --- | --- | --- |
| `ENGINE_RULE` | 룰 판정 또는 event ordering 오류 | Agent 1 |
| `ROOM_LIFECYCLE` | room/session/reconnect orchestration 오류 | Agent 2 |
| `CLIENT_SYNC` | UI state mapping 또는 reconnect UX 오류 | Agent 3 |
| `TEST_HARNESS` | runner/flaky setup/artifact 오류 | Agent 4 |

## Open Questions
- [ ] websocket debug connect 경로가 CLI ingress와 같은 stale heartbeat reject codes(`invalidResumeState`, `staleConnectionId`)를 유지할지
- [ ] live duplicate `actionId` path가 exact same resend에서 `duplicateActionIdDisposition=exactReplay`, conflicting reuse에서 `duplicateActionIdDisposition=conflictReject` + `actionRejected(code=actionIdConflict)`를 실제 transport에서 만족하는지

## Validation Checklist
- [x] P0 시나리오가 모두 정의돼 있다
- [x] artifact 폴더 구조가 통일돼 있다
- [x] 로그에 공통 ID가 모두 남는다
- [x] reconnect / duplicate / invalid choice / resync가 포함돼 있다
- [x] failure class가 owner agent로 연결된다
- [x] hidden-info leak regression이 별도 scenario로 포함돼 있다
- [x] stale/replaced heartbeat regression이 별도 scenario로 포함돼 있다
- [x] debug connect 수동 점검 체크리스트가 문서화돼 있다

## Next Fill-In Tasks
- [x] socket runner skeleton과 시나리오 ID 매핑
- [x] fixture transcript/validator 기반 P0 smoke path 추가
- [x] review findings용 shake privacy / stale heartbeat regression 추가
- [x] anomaly report 템플릿 파일 초안 작성
- [x] simulator smoke 최소 자동화 범위 결정
- [x] P1 timeout / pending choice reconnect 상세화
- [x] runner에 `--mode socket`과 `room_transport_*` live spike binding 추가
- [x] MP-008을 actual gameplay command + `expectedStateVersion` live resync probe로 승격
- [x] MP-008 live recovery snapshot reason을 `resync`로 잠금
- [x] GoStopCLI websocket transport를 TCP fallback과 같은 runner/artifact schema로 parity smoke화
- [ ] live dropped-event gap injection path를 actual websocket/server binding까지 확장
- [ ] websocket debug connect path에서 `MP-013/014`를 실제 transport 로그로 재검증
- [ ] live duplicate `actionId` probe를 PASS로 끌어올려 `exactReplay` / `conflictReject` semantics를 잠금

## Change Log
- 2026-03-11: `--transport tcp|websocket|compare` selector와 stdlib websocket client를 multiplayer runner/harness에 추가했다
- 2026-03-11: `socket-parity` compare suite로 `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`가 TCP fallback과 websocket에서 같은 semantics를 유지하는지 PASS로 잠갔다
- 2026-03-11: `socket-duplicate` compare suite와 `duplicate_probe.json` artifact를 추가했고, `MP-004` live duplicate path는 TCP/websocket 공통으로 `exactReplay` 대신 stale reject/resync로 빠지는 blocker를 재현했다
- 2026-03-11: `tests/test_agent/multiplayer/socket_transport.py`를 actual GoStopCLI `--room-transport-server` TCP facade 기준으로 올리고, cached build reuse 우선 경로를 추가했다
- 2026-03-11: latest `GoStopCLI` rebuild 기준 `MP-002` socket terminal smoke가 `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed`까지 PASS로 닫혔다
- 2026-03-11: latest `GoStopCLI` rebuild 기준 `MP-008` socket gameplay smoke가 `actionRejected(staleStateVersion)` + `stateSnapshot(reason=resync)` live assert까지 PASS로 닫혔다
- 2026-03-11: `MP-013`을 same TCP facade direct projection smoke로 올려 actor/peer shake redaction을 actual network path에서 재검증했다
- 2026-03-10: `tests/test_agent/multiplayer_runner.py --mode socket`과 `tests/test_agent/multiplayer/socket_transport.py`를 추가해 `room_transport_*` live spike 기반 `socket-smoke`를 열었다
- 2026-03-10: `MP-001` socket bootstrap PASS, `MP-014` stale heartbeat parity PASS, `MP-008` live bootstrap + hook attachment preflight BLOCKED 상태와 artifact 요구사항을 문서에 반영했다
- 2026-03-09: CLI smoke `ready-start`가 explicit `room_record_game_started -> get_multiplayer_game_started_bootstrap` paired bootstrap assert를 수행하도록 갱신했다
- 2026-03-09: CLI smoke에 `mp008-hook-surface`를 추가해 `room_set/get/clear_mp008_hook` surface를 regression으로 유지한다
- 2026-03-09: MP-008을 stale `expectedStateVersion` override + `actionRejected(staleStateVersion)` + `stateSnapshot(reason=resync)` 기준 fixture PASS / executable-ready path로 정리하고 `replay/injection_manifest.json`, `timeline/mismatch.ndjson`을 runner에 반영했다
- 2026-03-09: RF-001~RF-003 대응으로 local debug manual checklist를 `create/join/ready/start/live/disconnect/resume` 기준으로 재구성하고, `Join Invite` unsupported/error validation point 및 CLI smoke `gameStarted` TODO를 추가
- 2026-03-08: `MP-013` shake privacy, `MP-014` stale/replaced heartbeat regression을 fixture-backed scenario로 등록
- 2026-03-08: `tests/test_agent/multiplayer_runner.py --suite smoke|review-fixups`와 `scripts/run_multiplayer_cli_two_player_smoke.py --scenario all` 진입점 추가
- 2026-03-08: actual Python scenario step skeleton (`tests/test_agent/multiplayer/skeletons.py`) 추가
- 2026-03-08: fixture mode와 synthetic transcript validator 추가 (`MP-001/002/003/004/005/006/007/013/014` PASS, `MP-008` BLOCKED)
- 2026-03-08: multiplayer runner/helper skeleton, artifact models, P0 registry command 추가
- 2026-03-08: MP-001 ~ MP-008 상세 초안, artifact policy, observability lens 추가
- 2026-03-08: skeleton created
