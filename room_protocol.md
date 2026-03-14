# Room Protocol

## Meta
- **Owner**: Agent 2
- **Primary Consumers**: Agent 1, Agent 3, Agent 4
- **Status**: Phase 0 Shipped
- **Last Updated**: 2026-03-14
- **Related Docs**:
  - `multiplayer_contract.md`
  - `multiplayer_ui_flow.md`
  - `multiplayer_test_scenarios.md`
  - `agent_sync_board.md`

## Goal
- lobby, room, session, websocket lifecycle을 정의한다.
- authoritative engine 바깥에서 필요한 orchestration 규칙을 고정한다.
- reconnect/resume, heartbeat, timeout, forfeit를 room/session 레이어 기준으로 분리한다.

## Scope
- room state machine
- room bootstrap API
- websocket transport envelope
- session / reconnect / resume
- heartbeat / timeout / forfeit
- persistence minimum

## Non-Goals
- 카드 룰 판정
- engine event payload 재설계
- iOS 화면 구조
- 테스트 시나리오 매트릭스 상세

## State Ownership
- room state는 Agent 2가 정의하는 orchestration state다.
- game phase, `stateVersion`, `eventId`, `pendingChoice` 의미는 Agent 1 authoritative engine이 소유한다.
- disconnect/reconnect는 우선 session/presence에 반영되며, room state는 필요할 때만 변한다.
- room 서버는 Agent 1 event를 소비하고 전달하지만 해석해서 새 rule state를 만들지 않는다.

## Key Decisions

| Topic | Current Decision | Owner | Status | Notes |
| --- | --- | --- | --- | --- |
| room size | 2 players fixed | Agent 2 | Locked | first release |
| admission modes | `invite`, `quickMatch`가 같은 state machine 사용 | Agent 2 | Locked | `joinPolicy`만 다름 |
| transport split | current product path는 concrete bootstrap facade `room_bootstrap_*` + gameplay websocket `room_transport_*`로 분리한다 | Agent 2 | Locked | future REST split은 current facade의 1:1 public projection |
| room start trigger | 두 플레이어가 모두 ready 되면 auto-start | Agent 2 | Locked | public `startGame` 없음 |
| `inGame` transition control | `.starting` 이후 `recordGameStarted` explicit step 유지 | Agent 2 | Locked | ready는 `.starting`까지만, bootstrap fetch context는 `recordGameStarted` metadata로 노출 |
| reconnect restore shape | `roomSnapshot` + Agent 1 `stateSnapshot(reason=resume)` | Agent 2 | Locked | delta resume는 Phase 1 이후 |
| heartbeat interval | 5s idle 기준 `ping` | Agent 2 | Locked | app traffic도 heartbeat로 인정 |
| disconnect threshold | 15s 무응답이면 disconnect 판정 | Agent 2 | Locked | grace timer 시작 |
| reconnect grace | 30s | Agent 2 | Locked | disconnect 후 session resume window, `ended`에서는 result 조회만 허용 |
| same-player multi-device | newest valid connection wins | Agent 2 | Locked | 이전 socket은 `sessionReplaced` |
| heartbeat acceptance | active, non-replaced session with matching connection only | Agent 2 | Locked | stale heartbeat는 silent ignore가 아니라 `invalidResumeState` / `staleConnectionId` reject로 유지 |
| disconnect timeout outcome | `starting`/`inGame` 중 grace 만료 시 forfeit | Agent 2 | Locked | transport는 same authority relay 위에서 synthetic `quit(reason=disconnectTimeout)`를 emit한다 |
| gameplay turn timeout ownership | Agent 1 deadline/event contract를 그대로 소비 | Agent 2 | Locked | room layer는 fallback action 생성 안 함 |
| presence merge entrypoint | bootstrap/projection/terminal relay 모두 shared request builder 사용 | Agent 2 | Locked | `participantPresenceByPlayerId` 누락 방지 |
| terminal forwarder | `recordMatchEnded` metadata에 terminal relay request를 싣고 result consumer까지 fan-out | Agent 2 | Locked | `forfeitingPlayerId`, winner/loser, settlement summary 포함 |
| authority player mapping | room seat/session lookup가 room `playerId -> authority playerId`를 internal mapping한다 | Agent 2 | Locked | room envelope는 room `playerId`, nested engine payload는 authority `playerId` 유지 |
| invite/share identifier | product-facing join/share identifier는 `inviteCode` 유지 | Agent 2 | Locked | Phase 0에서는 `inviteCode == roomId`, 별도 share token 없음 |
| public bootstrap facade | `room_bootstrap_create|lookup_invite|join|prepare_game_start`가 current public bootstrap boundary다 | Agent 2 | Locked | create/join/invite lookup/pre-bootstrap fetch는 bootstrap facade가, attach/resume/gameplay/result는 websocket transport가 담당 |
| transport spike surface | CLI `room_transport_connect/send/receive`를 websocket-equivalent spike로 사용 | Agent 2 | Locked | gameplay relay, stale heartbeat, invalid resume reject code parity 유지, passive TCP EOF / websocket close도 same adapter path 사용 |
| gameplay relay over transport | `playCard`, `submitChoice`, `quit`, `leaveRoom`를 room transport action으로 노출 | Agent 2 | Locked | app-facing adapter는 이 gameplay command surface를 직접 사용한다 |
| timeout relay over transport | explicit `disconnect`와 passive close가 same adapter disconnect path를 공유하고 server-owned sweep이 timeout completion을 자동 진행 | Agent 2 | Locked | manual `reapExpiredState`는 debug/test hook, grace expiry는 terminal fan-out, later result expiry는 `roomClosed`만 emit |
| server binding spike | `GoStopCLI --room-transport-websocket-server [--port PORT]` actual websocket path가 shared server boundary + serial frame send queue + automatic expiry sweep 위에서 same transport adapter를 재사용 | Agent 2 | Locked | create/join/bootstrap current source도 이 command boundary이며, legacy TCP `--room-transport-server`는 parity smoke용 fallback으로 유지 |
| MP-008 deterministic hook | stale `expectedStateVersion` override | Agent 2 | Locked | per-session outbound queue가 없는 현 구조에서는 `dropNextGameEvent`보다 구현/검증이 단순함 |
| gap recovery shape | `room_gap_recovery_shape` + `room_transport_send(action=triggerGapRecovery)`가 dropped-event gap recovery minimum shape를 고정 | Agent 2 | Locked | live hook은 on-demand debug path, future automatic gap detection은 follow-up |

## Phase 0 Shipped Boundary
- shipped bootstrap boundary는 `room_bootstrap_create`, `room_bootstrap_lookup_invite`, `room_bootstrap_join`, `room_bootstrap_prepare_game_start`다.
- shipped gameplay transport boundary는 `room_transport_connect`, `room_transport_send`, `room_transport_receive`다.
- shipped live gap recovery naming은 `triggerGapRecovery -> gapRecoveryHint -> stateSnapshot(reason=gapDetected)`로 고정한다.
- Phase 0 안에서는 bootstrap/gap surface를 더 넓히지 않는다. additive metadata는 허용하되, locked parity fields와 envelope ordering은 바꾸지 않는다.
- final validation baseline은 Agent 4 `final-validation` suite(`MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`)다.
- round17 fixup-only 기준 Agent 2 추가 transport blocker는 없고, 이 boundary를 shipped scope final wording으로 유지한다.

## Entities

### Room
```json
{
  "roomId": "room_001",
  "inviteCode": "room_001",
  "roomType": "invite|quickMatch",
  "joinPolicy": "inviteCode|matchmaker",
  "roomState": "waitingForPlayers|waitingForReady|starting|inGame|ended|closed",
  "hostPlayerId": "player_a",
  "activeGameId": null,
  "members": [
    {
      "playerId": "player_a",
      "seat": 0,
      "role": "host",
      "ready": false,
      "presence": "connected|disconnected|left|forfeitPending",
      "sessionId": "sess_001",
      "connectedConnectionId": null,
      "joinedAt": "2026-03-08T15:30:00+09:00"
    }
  ],
  "deadlines": {
    "joinExpiresAt": "2026-03-08T15:35:00+09:00",
    "readyExpiresAt": null,
    "resultExpiresAt": null
  },
  "lastRoomSequence": 12,
  "createdAt": "2026-03-08T15:30:00+09:00",
  "closedAt": null
}
```

### Session
```json
{
  "sessionId": "sess_001",
  "playerId": "player_a",
  "roomId": "room_001",
  "deviceId": "ios_installation_001",
  "connectionState": "connected|disconnectedGrace|resuming|expired|replaced",
  "connectionId": null,
  "resumeToken": "opaque_rotating_secret",
  "resumeIssuedAt": "2026-03-08T15:30:00+09:00",
  "graceExpiresAt": null,
  "lastHeartbeatAt": "2026-03-08T15:30:05+09:00",
  "lastAckedRoomSequence": 12,
  "lastAckedGameEventId": "evt_010",
  "lastSeenStateVersion": 23
}
```

### Session Notes
- `resumeToken`은 raw 값이 아니라 서버 저장 시 hash 처리한다.
- session은 room membership와 1:1이며, room 밖 global login session과 구분한다.
- room/session 복구는 같은 `playerId` + `roomId` + 유효한 `resumeToken`을 전제로 한다.
- `graceExpiresAt`은 `disconnectedGrace` 진입 시점에만 채워진다.
- `connectionId`와 member `connectedConnectionId`는 initial create/join 시점에는 `null`일 수 있고, attach/resume 이후 채워진다.
- `inviteCode`는 invite room의 product-facing share/join 식별자다. Phase 0에서는 canonical `roomId`와 같은 값을 쓴다.

## Swift Model Mapping

| Protocol Term | Swift Type | Notes |
| --- | --- | --- |
| room | `Room` | `GoStopCLI/RoomCoordinatorModels.swift` |
| room member | `RoomMember` | room snapshot용 seat/member projection |
| session | `RoomSession` | transport-independent session metadata |
| room state | `RoomState` | `waitingForPlayers` 등 문서 값과 동일 |
| member presence | `RoomMemberPresence` | room-level presence only |
| session connection state | `RoomSessionConnectionState` | reconnect lifecycle only |
| deadlines | `RoomDeadlines` | join/ready/result TTL |
| room lifecycle API | `RoomLifecycleCoordinating` | create/join/ready/attach/leave/close/disconnect/resume/heartbeat/game start/end/expiry |
| in-memory implementation | `InMemoryRoomCoordinator` | transport/persistence 미연결 골격 |
| CLI ingress adapter | `RoomCoordinatorCLIAdapter` | `GoStopCLI` binary에서 room REST/WS skeleton command 처리 |
| DEBUG app facade | `LocalRoomCoordinatorDebugService` | `MultiplayerDebugServices.roomCoordinator` entrypoint 제공 |
| shared `room_hello` resolver | `performRoomHello(...)` | CLI adapter와 DEBUG facade가 attach/resume 판단을 공유 |
| game-start bootstrap plan | `RoomGameStartedBootstrapPlan` | `recordGameStarted` 이후 Agent 1 bootstrap fetch request bundle |
| projection preview request | `RoomProjectionPreviewRequest` | projection preview와 transport relay 공용 request shape |
| terminal summary relay request | `RoomTerminalSummaryRelayRequest` | result route/transport relay 공용 request shape |
| MP-008 hook | `RoomDeterministicFaultHook` | Phase 0은 stale `expectedStateVersion` override만 지원 |
| mutation result | `RoomCoordinatorMutation` | snapshot + emitted events + bootstrap hints |
| room event payload | `RoomCoordinatorEventPayload` | WS envelope 전에 검증 가능한 typed event |

## Room State Machine

### State Definitions
- `waitingForPlayers`
  - room 생성 직후 상태다.
  - host만 존재하며 join 가능하다.
  - active game이 없다.
- `waitingForReady`
  - 2명 seat가 모두 채워졌지만 아직 auto-start 조건이 충족되지 않았다.
  - ready 토글과 pregame leave만 허용한다.
- `starting`
  - 두 플레이어 ready가 잠겼고 engine bootstrap 요청이 진행 중이다.
  - join 불가, pregame leave는 취소가 아니라 forfeit 경로로 본다.
- `inGame`
  - active `gameId`가 존재하고 authoritative engine event를 전달 중이다.
  - room layer는 membership/presence/reconnect만 관리한다.
- `ended`
  - Agent 1 `matchEnded` 또는 room-level forfeit 종료가 반영된 상태다.
  - 결과 확인과 짧은 reconnect는 허용하지만 재시작은 Phase 0 범위 밖이다.
- `closed`
  - join/resume 불가 최종 상태다.
  - cleanup 대상이다.

### Transition Table

| From | Trigger | To | Notes |
| --- | --- | --- | --- |
| none | `createRoom` success | `waitingForPlayers` | host seat 생성, join TTL 5분 시작 |
| `waitingForPlayers` | guest joined | `waitingForReady` | ready window 60초 시작 |
| `waitingForPlayers` | host leave | `closed` | game 미시작, result 없음 |
| `waitingForPlayers` | join TTL expired | `closed` | idle room cleanup |
| `waitingForReady` | guest leave | `waitingForPlayers` | guest seat 제거, ready reset |
| `waitingForReady` | host leave | `closed` | game 미시작 취소 |
| `waitingForReady` | ready window expired | `waitingForReady` | 두 플레이어 ready를 모두 false로 reset |
| `waitingForReady` | both players ready | `starting` | auto-start, join lock |
| `starting` | Agent 1 `gameStarted` accepted | `inGame` | 이후 live `gameEvent` 전달 시작 |
| `starting` | bootstrap failed | `waitingForReady` | ready reset, `activeGameId` clear |
| `starting` | explicit leave / reconnect grace expired | `ended` | forfeit 종료 |
| `inGame` | Agent 1 `matchEnded` | `ended` | terminal summary 저장 |
| `inGame` | explicit leave / reconnect grace expired | `ended` | disconnect/quit forfeit |
| `ended` | result TTL expired | `closed` | default 60초 |
| `ended` | both players left | `closed` | early cleanup |

### State Machine Rules
- disconnect 자체는 room state를 바꾸지 않는다. member `presence`와 session state만 바뀐다.
- `waitingForPlayers`와 `waitingForReady`는 room-level lifecycle이고, `inGame` 안의 턴/선택 상태는 Agent 1 phase로 표현한다.
- `ended` 이후 rematch는 Phase 0 범위 밖이다. 새 판은 새 room 또는 차기 contract에서 정의한다.

## Session State Machine

| From | Trigger | To | Notes |
| --- | --- | --- | --- |
| none | REST create/join 성공 | `connected` | 첫 WS `hello` 완료 후 connection binding |
| `connected` | socket close or 15s silence | `disconnectedGrace` | reconnect grace 시작 |
| `disconnectedGrace` | valid `hello` + resume | `resuming` | snapshot sync 전 단계 |
| `resuming` | snapshots delivered | `connected` | token rotate, live event 재개 |
| `disconnectedGrace` | grace expired | `expired` | pregame은 seat release, in-game은 forfeit, ended는 result-only session expiry |
| `connected` | newer valid connection accepted | `replaced` | old socket close code `4409` |
| `expired` | any resume attempt | `expired` | resume reject |
| `replaced` | old socket reconnect | `replaced` | latest token 없으면 reject |

## API Surface

### Room Actions

| Action | Method Shape | Auth | Result |
| --- | --- | --- | --- |
| `createRoom` | `POST /rooms` | required | room + host session 발급 |
| `joinRoom` | `POST /rooms/{roomId}/join` | required | guest seat + guest session 발급 |
| `setReady` | `POST /rooms/{roomId}/ready` | required | member ready flag 변경 |
| `leaveRoom` | `POST /rooms/{roomId}/leave` | required | pregame leave 또는 in-game forfeit |
| `closeRoom` | `POST /rooms/{roomId}/close` | host/server only | room cleanup |

### API Notes
- Phase 0에서는 public `startGame` API를 두지 않는다.
- Phase 0에서는 public `resumeRoom` API를 두지 않는다. resume는 WebSocket `hello`로만 수행한다.
- `setReady`는 idempotent다. 같은 값 재전송은 no-op success로 본다.

### Transport-Independent Coordinator API
- room lifecycle unit test는 REST/WS 없이 `RoomLifecycleCoordinating`로 직접 검증한다.
- primary mutators:
  - `createRoom(_:)`
  - `joinRoom(_:)`
  - `setReady(_:)`
  - `attachSession(_:)`
  - `disconnectMember(_:)`
  - `leaveRoom(_:)`
  - `closeRoom(_:)`
  - `resumeSession(_:)`
  - `recordHeartbeat(_:)`
- bridge hooks:
  - `recordGameStarted(_:)`
  - `recordMatchEnded(_:)`
  - `reapExpiredState(asOf:)`
- game-start control note:
  - `setReady(_:)`는 auto-start 조건 충족 시 room을 `.starting`으로만 올리고 `requiresGameBootstrap=true`를 낸다.
  - 실제 `.starting -> .inGame` 전이는 `recordGameStarted(_:)` explicit bridge step으로만 수행한다.
  - `recordGameStarted(_:)` metadata에는 Agent 1 `get_multiplayer_game_started_bootstrap`로 바로 넘길 `gameStartedBootstrapPlan`이 포함된다.
- coordinator auth note:
  - `closeRoom(_:)`는 host/server authorization이 끝난 뒤 호출하는 privileged mutator로 본다.
- attach note:
  - `attachSession(_:)`는 fresh `hello` 경로를 담당한다. 이미 `connected` session에 connection binding과 resume token rotation을 적용하지만 `playerReconnected` 이벤트는 만들지 않는다.
- heartbeat note:
  - `recordHeartbeat(_:)`는 `pong`/`ack` ingestion 결과를 room transport 밖에서 재현하기 위한 session mutation entry다.
  - bound owner가 아닌 stale `connectionId`, `expired`/`replaced`/`disconnectedGrace` session heartbeat는 reject한다.
- each mutation returns `RoomCoordinatorMutation`:
  - latest `RoomCoordinatorSnapshot`
  - typed `RoomCoordinatorEvent` array
  - `requiresGameBootstrap`, rotated resume token, superseded connection hint
  - `gameStartedBootstrapPlan`, `terminalSummaryRelayRequest`

### CLI Harness Ingress Skeleton
- `GoStopCLI`는 room lifecycle smoke/harness를 위해 아래 command를 제공한다.
- REST-like commands:
  - `room_create`
  - `room_join`
  - `room_set_ready`
  - `room_leave`
  - `room_close`
  - `room_disconnect`
- WS-like commands:
  - `room_hello`: session state가 `connected`면 `attachSession(_:)`, `disconnectedGrace`면 `resumeSession(_:)`로 분기
  - `room_pong` / `room_ack`: `recordHeartbeat(_:)`
- bridge/admin commands:
  - `room_record_game_started`
  - `room_record_game_started_and_prepare_bootstrap`
  - `room_record_match_ended`
  - `room_record_match_ended_and_fetch_terminal_summary`
  - `room_projection_preview`
  - `room_reap_expired`
  - `room_snapshot`
- websocket-equivalent spike commands:
  - `room_transport_connect`
  - `room_transport_send`
  - `room_transport_receive`
- CLI `room_record_game_started*` note:
  - 두 command 모두 metadata에 `gameStartControlMode=explicitRecordGameStarted`와 `gameStartedBootstrapPlan`을 포함한다.
  - `room_record_game_started_and_prepare_bootstrap`는 `bootstrapByPlayerId`까지 포함해 direct CLI smoke가 실제 Agent 1 bootstrap payload를 바로 검증할 수 있게 한다.
  - `gameStartedBootstrapPlan.fetchAction`은 `get_multiplayer_game_started_bootstrap`이고, `requestsByPlayerId`를 그대로 Agent 1 helper request data로 쓸 수 있다.
- CLI terminal/projection note:
  - `room_projection_preview`와 `room_record_match_ended_and_fetch_terminal_summary`는 shared presence merge request builder를 사용한다.
  - direct relay request는 `participantPresenceByPlayerId`, `forfeitingPlayerId`, viewer identity를 room seat 기반 room `playerId -> authority playerId` mapping으로 rewrite한 뒤 Agent 1 helper를 호출한다.
  - projection helper request는 compatibility를 위해 `snapshotReason`와 `reason`를 함께 싣고, live stale recovery에서는 `reason=resync`만 사용한다.
  - terminal path는 `terminalSummaryRelayRequest`와 actual `get_multiplayer_terminal_summary` payload를 함께 반환하며, `roundEnded` / `matchEnded` required field를 검증한 뒤 fan-out한다.
- CLI transport spike note:
  - bootstrap-only facade는 `room_bootstrap_create`, `room_bootstrap_lookup_invite`, `room_bootstrap_join`, `room_bootstrap_prepare_game_start`다. 이 4개가 current public bootstrap boundary이고, gameplay websocket path인 `room_transport_*`와 책임을 나눈다.
  - `room_transport_connect`는 logical socket mailbox를 연다.
  - `room_transport_send`는 `hello|ack|pong|disconnect|setReady|snapshot|triggerGapRecovery|reapExpiredState|playCard|submitChoice|quit|leaveRoom|recordGameStartedAndPrepareBootstrap|recordMatchEndedAndFetchTerminalSummary` action을 지원한다.
  - `room_transport_receive`는 queued envelope를 drain한다.
  - `hello`/`ack`는 기존 `performRoomHello(...)` / `recordHeartbeat(_:)`를 그대로 써서 `invalidResumeState`, `staleConnectionId` semantics를 유지한다.
  - `disconnect`는 session을 `disconnectedGrace`로 내리고, actual TCP EOF / websocket close도 마지막 successful `hello.connectionId` binding 기준으로 같은 disconnect helper를 탄다.
  - runtime semantics는 shared server-owned automatic expiry sweep이다. `reapExpiredState { asOf }`는 같은 adapter path를 타는 debug/test hook으로만 남긴다.
  - gameplay action에 `actionId`가 있으면 transport layer는 exact duplicate를 prior result replay로, conflicting reuse를 `actionRejected(code=actionIdConflict)`로 노출한다.
  - gameplay/terminal relay는 seat-based internal identity mapping을 먼저 resolve하므로 room `playerId`와 authority `playerId`가 달라도 `actionAccepted`, `actionRejected`, `roundEnded`, `matchEnded`, `terminalSummary` path가 흔들리지 않는다.

### App Source Network API Shape
- spike transport boundary:
  - request frame은 `CommandRequest { action, data }`
  - websocket은 text frame 1개당 request 1개, TCP는 newline-delimited JSON request 1개다.
  - current product bootstrap boundary는 `room_bootstrap_*` command facade다. create/join/invite lookup/pre-bootstrap fetch context는 bootstrap facade가 담당하고, live attach/resume/gameplay/result는 websocket `room_transport_*`에 남긴다.
  - 이 command facade가 shipped Phase 0 boundary다. Round 17 validation은 이 shape를 그대로 기준으로 삼는다.
  - future REST split은 current bootstrap facade의 1:1 public projection이다. public route split이 와도 bootstrap stage/action/handoff contract는 유지한다.
- public bootstrap facade:
  - `room_bootstrap_create { hostPlayerId, deviceId, roomType, joinPolicy }`
  - `room_bootstrap_lookup_invite { inviteCode }`
  - `room_bootstrap_join { roomId, playerId, deviceId }`
  - `room_bootstrap_prepare_game_start { roomId, gameId }`
  - response는 기존 payload에 `bootstrapBoundary`를 추가한다.
  - `bootstrapBoundary`는 `boundaryVersion`, `currentBoundary`, `recommendedNextActions`, `futurePublicSplit.route`, `gameplayTransportBoundary`, `gapRecovery.transportTriggerAction`를 함께 실어 current bootstrap ownership과 websocket handoff를 concrete하게 드러낸다.
- lifecycle minimum:
  - `room_create { hostPlayerId, roomType, joinPolicy, now? }`
  - `room_join { roomId, playerId, deviceId, now? }`
  - `room_transport_connect { clientId, roomId, sessionId, playerId, deviceId, resumeToken }`
  - `room_transport_send { clientId, action:\"hello\", connectionId, lastSeen? }`
  - `room_transport_send { clientId, action:\"leaveRoom\" }`
  - `room_transport_receive { clientId }`
- response minimum:
  - `room_create` / `room_join`는 `room`, `session`, `websocket`, `mutation`을 반환한다.
  - `room_bootstrap_lookup_invite`는 `inviteCode`, `roomSummary`, `websocket`, `bootstrapBoundary`를 반환한다.
  - invite room payload에는 `room.inviteCode`가 포함되고, Phase 0에서는 `room.inviteCode == room.roomId`다.
  - `room_transport_send(action=hello)`는 immediate ack payload 대신 mailbox에 `helloAck -> roomSnapshot -> roomEvent/gameEvent*`를 queue하고 command response에는 `client`, `metadata`, `queuedEnvelopeCount`만 반환한다.
  - app source는 `room_transport_receive`의 `envelopes[]`를 inbound stream source of truth로 본다.
- gameplay minimum:
  - `room_transport_send { clientId, action:\"playCard\", actionId, expectedStateVersion, commandPayload:{ cardId, source }, requestId?, traceId? }`
  - `room_transport_send { clientId, action:\"submitChoice\", actionId, expectedStateVersion, commandPayload:{ choiceId, optionCode, choiceCommandName? }, requestId?, traceId? }`
  - `room_transport_send { clientId, action:\"quit\", actionId, expectedStateVersion, commandPayload:{ reason }, requestId?, traceId? }`
  - exact duplicate `actionId`는 same result + same envelope `eventId` replay를 허용하고, conflicting reuse는 `actionRejected(code=actionIdConflict)`를 queue한다.
- gap future-extension shape:
  - `room_gap_recovery_shape`
  - `room_transport_send { clientId, action:"triggerGapRecovery", expectedStateVersion?, lastEventId?, traceId? }`
  - current mode는 `artifactOnly`
  - live transport는 `gapRecoveryHint` envelope 뒤에 `gameEvent(stateSnapshot reason=gapDetected)`를 같은 mailbox에 queue한다
  - transport flag는 `gapDetected`, artifact는 `gapRecoveryHint`
  - `gapRecoveryHint` minimum fields는 `roomId`, `sessionId`, `lastAckedGameEventId`, `lastSeenStateVersion`, `authoritativeEventId`, `authoritativeStateVersion`, `inputLockRequired`, `snapshotReason`이다

### DEBUG App Local Service
- DEBUG app code는 `MultiplayerDebugServices.roomCoordinator` singleton으로 같은 `InMemoryRoomCoordinator` 골격을 직접 호출할 수 있다.
- facade API:
  - `createRoom(_:)`
  - `joinRoom(_:)`
  - `helloHost(roomId:connectionId:...)`
  - `helloGuest(roomId:connectionId:...)`
  - `hello(...)`
  - `setReady(_:)`
  - `setGuestReady(roomId:ready:)`
  - `disconnect(_:)`
  - `leaveRoom(_:)`
  - `closeRoom(_:)`
  - `resume(_:)`
  - `heartbeat(_:)`
  - `recordGameStarted(_:)`
  - `recordGameStarted(roomId:gameId:)`
  - `recordGameStartedAndPrepareBootstrap(_:)`
  - `recordGameStartedAndPrepareBootstrap(roomId:gameId:)`
  - `recordGameStartedAndFetchBootstrap(_:, using:)`
  - `recordGameStartedAndFetchBootstrap(roomId:gameId:using:)`
  - `projectionPreview(roomId:viewerPlayerId:...using:)`
  - `recordMatchEndedAndFetchTerminalSummary(roomId:...using:)`
  - `snapshot(roomId:)`
  - `setMP008StaleExpectedStateVersionHook(targetSessionId:overriddenExpectedStateVersion:)`
  - `clearDeterministicFaultHook()`
- service는 `snapshotsByRoomId`, `lastMutation`, `lastHelloResult`를 메모리에 유지해 MP Lab 같은 DEBUG UI가 바로 consume할 수 있게 한다.
- service는 추가로 `lastGameStartedFlowResult`, `lastBootstrapRelayResult`, `lastTerminalRelayResult`, `lastProjectionPreviewPayload`, `deterministicFaultHook`를 메모리에 유지해 room start/bootstrap/result preview 및 MP-008 debug state를 바로 consume할 수 있게 한다.
- semantics note:
  - `hello(...)`, `helloHost(...)`, `helloGuest(...)`는 모두 shared `performRoomHello(...)`를 타며, session state가 `disconnectedGrace`면 resume, 그 외에는 fresh attach로 처리한다.
  - `setGuestReady(roomId:ready:)`는 guest `playerId` lookup 뒤 기존 `setReady(_:)`를 호출하는 convenience로만 동작한다.
  - `recordGameStarted(_:)`, `recordGameStarted(roomId:gameId:)`, `recordGameStartedAndPrepareBootstrap(...)`는 모두 CLI admin ingress `room_record_game_started*`와 같은 state precondition을 사용하고, room이 `.starting`일 때만 `.inGame` 전이를 허용한다.
  - one-shot flow가 필요하면 `recordGameStartedAndPrepareBootstrap(...)`를 사용한다. 이 helper는 room mutation 뒤 Agent 1 bootstrap fetch plan까지 함께 반환한다.
  - actual authority payload까지 같이 받고 싶으면 `recordGameStartedAndFetchBootstrap(..., using: gameManager)`와 `recordMatchEndedAndFetchTerminalSummary(..., using: gameManager)`를 사용한다.
  - `projectionPreview(..., using: gameManager)`도 같은 shared presence merge request builder를 사용하므로 preview/bootstrap/terminal route가 서로 다른 `participantPresenceByPlayerId` semantics를 쓰지 않는다.

### Game Started Bootstrap Flow
1. `setReady(_:)`에서 두 플레이어 ready가 모두 true가 되면 room은 `.starting`으로 전이하고 `requiresGameBootstrap=true`를 낸다.
2. room layer는 여기서 auto-trigger로 `.inGame`을 만들지 않는다. Agent 1 bootstrap source와 ordering을 숨기지 않기 위해 `recordGameStarted`는 explicit control로 남긴다.
3. `recordGameStarted(_:)` 또는 `recordGameStartedAndPrepareBootstrap(...)`가 room을 `.inGame`으로 전이한다.
4. 같은 mutation metadata의 `gameStartedBootstrapPlan.fetchAction=get_multiplayer_game_started_bootstrap`와 `requestsByPlayerId`를 사용해 Agent 1 bootstrap payload를 fetch한다.
5. visible live state source of truth는 항상 Agent 1 `stateSnapshot(reason=gameStarted)`다.

### Presence Merge Entry Points
- `makeParticipantPresenceByPlayerId(from:)`가 room snapshot 기준 `source=is roomSnapshot`, `isConnected`, `isReady`를 공통 생성한다.
- `makeGameStartedBootstrapPlan(from:)`는 위 presence map을 bootstrap `requestsByPlayerId` 전부에 복사한다.
- `makeProjectionPreviewRequest(from:viewerPlayerId:...)`는 preview fetch에서도 같은 presence map을 사용한다.
- `makeTerminalSummaryRelayRequest(from:...)`는 `recordMatchEnded` 이후 final room presence를 result relay request에 담는다.
- result path에서 forfeit가 반영되면 forfeiting member는 `presence=forfeitPending`, relay request에서는 `isConnected=false`로 내려간다.

### MP-008 Deterministic Hook
- Phase 0 결정은 `staleExpectedStateVersion` override다.
- chosen shape:
  - `RoomDeterministicFaultHook { kind=staleExpectedStateVersionOverride, targetSessionId, overriddenExpectedStateVersion }`
- rejected for now:
  - `dropNextGameEvent(targetSessionId, count=1)`는 실제 per-session outbound queue가 있어야 deterministic하게 보장되는데, 현재 local debug/CLI ingress에는 그 계층이 없다.
- exposure:
  - DEBUG app facade: `setMP008StaleExpectedStateVersionHook(...)`, `clearDeterministicFaultHook()`
  - CLI ingress: `room_set_mp008_hook`, `room_get_mp008_hook`, `room_clear_mp008_hook`

### Sample `createRoom` Response
```json
{
  "requestId": "req_001",
  "room": {
    "roomId": "room_001",
    "roomType": "invite",
    "joinPolicy": "inviteCode",
    "roomState": "waitingForPlayers",
    "hostPlayerId": "player_a",
    "members": [
      {
        "playerId": "player_a",
        "seat": 0,
        "role": "host",
        "ready": false,
        "presence": "connected"
      }
    ],
    "deadlines": {
      "joinExpiresAt": "2026-03-08T15:35:00+09:00"
    }
  },
  "session": {
    "sessionId": "sess_001",
    "resumeToken": "opaque_rotating_secret",
    "graceExpiresAt": null
  },
  "websocket": {
    "url": "/ws",
    "heartbeatIntervalMs": 5000,
    "disconnectTimeoutMs": 15000,
    "reconnectGraceMs": 30000
  }
}
```

## WebSocket Transport

### Transport Envelope
```json
{
  "type": "hello|helloAck|roomSnapshot|roomEvent|gameEvent|terminalSummary|ping|pong|ack|error",
  "messageId": "msg_001",
  "requestId": "req_001",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "sessionId": "sess_001",
  "roomSequence": 12,
  "serverTime": "2026-03-08T15:30:00+09:00",
  "payload": {}
}
```

### Envelope Rules
- `messageId`는 transport 레벨 고유 ID다.
- `roomSequence`는 room-level delivery ordering key다. room event와 snapshot delivery 순서를 보장한다.
- `traceId`는 REST create/join, WS `hello`, Agent 1 command/event를 연결하는 shared ID다.
- `gameEvent`의 authoritative ordering은 여전히 Agent 1 `eventId`와 `stateVersion` 기준이다.
- Agent 2는 `gameEvent.payload.engineEvent`에 Agent 1 envelope를 그대로 넣고, 의미를 재해석하지 않는다.
- `terminalSummary`는 Agent 1 `MultiplayerTerminalSummaryPayload` fetch 결과를 room/result consumer용으로 감싼 transport envelope다.

### Client -> Server
- `hello`
  - room reconnect/initial attach handshake
- `pong`
  - ping 응답
- `ack`
  - 마지막으로 처리한 `roomSequence`, `gameEventId`, `stateVersion` 전달
- `gameCommand`
  - Agent 1 command envelope를 그대로 전달

### Server -> Client
- `helloAck`
  - attach/resume 승인과 새 connection metadata
- `roomSnapshot`
  - room state full snapshot
- `roomEvent`
  - room/member/presence 변화
- `gameEvent`
  - Agent 1 authoritative event forward
- `terminalSummary`
  - Agent 1 terminal summary forwarder (`roundEnded` + `matchEnded`)
- `ping`
  - heartbeat
- `error`
  - resume reject, auth 실패, transport 오류

### Transport Spike Surface
- actual websocket path와 TCP fallback은 같은 CLI `room_transport_connect/send/receive` command surface를 공유한다.
- same JSON command surface는 `GoStopCLI --room-transport-websocket-server --port 9092`와 `GoStopCLI --room-transport-server --port 9091`에서 그대로 유지된다.
- connect:
  - `room_transport_connect { clientId, roomId, sessionId, playerId, deviceId, resumeToken }`
- send:
  - `room_transport_send { clientId, action, ... }`
  - `action=hello`는 `connectionId`, optional `lastSeen`을 받고 `helloAck -> roomSnapshot -> roomEvent*`를 queue한다.
  - `action=ack|pong`는 existing bound `connectionId`만 허용하며, stale/replaced/disconnected heartbeat는 `invalidResumeState` 또는 `staleConnectionId` error를 즉시 반환한다.
  - `action=disconnect`는 transport-owned session을 `disconnectedGrace`로 내리고 `roomEvent(playerDisconnected)`를 queue한다.
  - passive TCP EOF / websocket close도 same disconnect helper를 타며, current active owner는 마지막 successful `room_transport_send(action=hello)`를 보낸 physical connection 기준으로만 판정한다.
  - server runtime automatic sweep가 real clock 기준으로 timeout/result TTL mutation을 transport mailbox에 fan-out한다.
  - `action=reapExpiredState`는 `{ asOf }`를 받아 같은 adapter timeout/result TTL mutation path를 강제로 실행하는 debug/test hook이다.
  - `action=triggerGapRecovery`는 on-demand live gap hook이다. target client mailbox에 `gapRecoveryHint` envelope를 먼저 넣고, 이어서 `gameEvent(stateSnapshot reason=gapDetected)`를 queue한다.
  - gameplay action은 공통 envelope field `requestId?`, `traceId?`, `actionId`, `expectedStateVersion`, `commandPayload`를 받는다.
  - `action=playCard` payload는 `{ cardId, source }`다.
  - `action=submitChoice` payload는 `{ choiceId, optionCode, choiceCommandName? }`다.
  - `action=quit` payload는 `{ reason=voluntaryExit|disconnectTimeout|adminForfeit }`다.
  - `action=leaveRoom`은 explicit result dismissal/room exit path이며 별도 `commandPayload` 없이 room mutator를 탄다.
  - `action=recordGameStartedAndPrepareBootstrap`는 `roomEvent` 후 각 participant mailbox에 `gameEvent(gameStarted)` + `gameEvent(stateSnapshot reason=gameStarted)`를 queue한다.
  - `action=recordMatchEndedAndFetchTerminalSummary`는 `roomEvent` 후 각 participant mailbox에 `gameEvent(roundEnded)`, `gameEvent(matchEnded)`, `terminalSummary`를 queue한다.
  - exact duplicate `actionId`는 prior result와 prior mailbox delta를 caller에게 replay하고, conflicting reuse는 caller mailbox에 `gameEvent(actionRejected code=actionIdConflict)`를 queue한다.
- receive:
  - `room_transport_receive { clientId }`는 queued envelopes를 drain한다.
- parity rule:
  - bootstrap-only facade alias(`room_bootstrap_*`)는 websocket gameplay transport ordering을 바꾸지 않는다. create/join/bootstrap payload만 분리하고, attach/resume/gameplay/result lifecycle은 계속 `room_transport_*`가 담당한다.
  - bootstrap concrete boundary는 `room_bootstrap_create|lookup_invite|join|prepare_game_start`만 소유한다. transport connect/hello 이후 lifecycle은 bootstrap facade가 아니라 websocket transport 책임이다.
  - `room_transport_send(action=hello)`와 `room_hello`는 같은 `performRoomHello(...)`를 탄다.
  - `room_transport_send(action=ack|pong)`와 `room_ack|room_pong`는 같은 `recordHeartbeat(_:)`를 탄다.
  - 따라서 stale heartbeat/no-owner ack는 `staleConnectionId`, invalid resume path는 `invalidResumeState`를 유지하며 silent ignore로 바꾸지 않는다.
  - `room_transport_send(action=playCard|submitChoice|quit)`와 websocket/TCP binding은 같은 `RoomCoordinatorCLIAdapter` gameplay relay를 탄다.

### Gap Recovery Shape
- action:
  - `room_gap_recovery_shape`
- response minimum:
  - `mode=artifactOnly`
  - `transportFlag.name=gapDetected`
  - `artifact.name=gapRecoveryHint`
  - `artifact.minimumFields=roomId, sessionId, lastAckedGameEventId, lastSeenStateVersion, authoritativeEventId, authoritativeStateVersion`
  - `recoveryEnvelope=gameEvent(stateSnapshot reason=gapDetected)`
  - `liveHook.transportAction=room_transport_send(action=triggerGapRecovery)`
- intended use:
  - Agent 4 preflight/artifact contract source
  - on-demand live dropped-event gap smoke bootstrap
  - future automatic gap detection의 transport flag / artifact field naming lock

### Final Validation Entry
1. `room_bootstrap_create`
2. `room_bootstrap_lookup_invite`
3. `room_bootstrap_join`
4. `room_transport_connect`
5. `room_transport_send(action=hello)` for host and guest
6. `room_transport_send(action=setReady, ready=true)` for host and guest
7. `room_transport_send(action=recordGameStartedAndPrepareBootstrap, gameId=...)`
8. `room_transport_send(action=triggerGapRecovery, expectedStateVersion=..., lastEventId=..., traceId=...)`
9. `room_transport_receive`
10. assert `gapRecoveryHint -> gameEvent(stateSnapshot reason=gapDetected)` ordering

### Gameplay Relay Ordering
1. accepted command baseline은 `gameEvent(actionAccepted)`를 먼저 queue한다.
2. live state mutation은 `gameEvent(statePatched)`로 queue한다.
3. semantic follow-up은 phase에 따라 `turnChanged`, `choiceRequested`, `roundEnded`, `matchEnded`가 뒤따른다.
4. stale `expectedStateVersion` reject path는 `gameEvent(actionRejected code=staleStateVersion)` 뒤에 `gameEvent(stateSnapshot reason=resync)`를 queue한다.
5. `quit` baseline은 `gameEvent(actionAccepted) -> gameEvent(roundEnded) -> gameEvent(matchEnded) -> roomEvent(playerForfeited/roomStateChanged) -> terminalSummary`다.
6. reconnect grace expiry가 active match를 끝내면 transport는 server-owned automatic sweep에서 same authority relay 위의 synthetic `quit(reason=disconnectTimeout)`를 emit하고 위 `quit` baseline을 그대로 따른다.
7. timeout path의 `roomClosed`는 terminal summary보다 먼저 오지 않는다. 이후 `leaveRoom` 또는 automatic result TTL expiry에서 별도 `roomEvent(roomClosed)`로만 닫힌다.
8. result dismissal baseline은 `room_transport_send(action=leaveRoom)` 후 `roomEvent(memberLeft)`와 final `roomEvent(roomClosed)`를 authoritative close signal로 사용한다.
9. exact duplicate `actionId` replay는 prior `eventId`를 유지하고, conflicting reuse는 state mutation 없이 `gameEvent(actionRejected code=actionIdConflict)`만 추가한다.
10. on-demand gap recovery baseline은 `gapRecoveryHint -> gameEvent(stateSnapshot reason=gapDetected)`다. 이 경로는 additive debug/live hook이며 accepted gameplay ordering을 바꾸지 않는다.

### Server Binding Boundary
- startup selection:
  - `configuredRoomTransportServerMode(from:)`가 websocket 우선, 없으면 TCP fallback을 고른다.
  - `makeRoomTransportServer(mode:engine:)`가 `RoomTransportServer` boundary 뒤에서 websocket/TCP 구현을 swap한다.
- shared server rule:
  - websocket/TCP 모두 shared `RoomTransportServerRuntime`에서 같은 `CommandRequest { action, data }` decoder와 `engine.handle(request:)` path를 사용한다.
  - 따라서 stdin CLI와 같은 `CommandRequest { action, data }` payload, envelope ordering, `invalidResumeState` / `staleConnectionId` error code를 유지한다.
  - websocket은 per-connection serial frame send queue를 써서 request 처리 순서와 response frame 순서를 같게 유지한다.
  - TCP EOF / websocket close는 shared server runtime이 마지막 successful `hello.connectionId` owner만 authoritative disconnect 대상으로 삼아 same adapter `disconnectMember -> grace tracking` path로 연결한다.
  - shared server runtime은 1초 cadence automatic expiry sweep를 돌려 disconnect grace/result TTL expiry를 같은 adapter `reapExpiredState` relay path로 진행한다.
- websocket entrypoint:
  - `GoStopCLI --room-transport-websocket-server`
  - `GoStopCLI --room-transport-websocket-server --port 9092`
  - `GoStopCLI --room-transport-websocket-server=9092`
- websocket transport:
  - loopback WebSocket text frame, payload는 stdin CLI와 같은 `CommandRequest { action, data }`
  - response frame도 stdin CLI와 같은 JSON object다
  - 내부 adapter는 `room_transport_connect/send/receive` ordering과 `invalidResumeState`, `staleConnectionId` error code를 그대로 유지한다
- entrypoint:
  - `GoStopCLI --room-transport-server`
  - `GoStopCLI --room-transport-server --port 9091`
  - `GoStopCLI --room-transport-server=9091`
- transport:
  - loopback TCP, newline-delimited JSON request/response
  - request body는 stdin CLI와 같은 `CommandRequest { action, data }`
  - response body도 stdin CLI와 같은 JSON object다
- current scope:
  - websocket server는 actual handshake/listener + shared server boundary + serial frame send queue까지 올렸다
  - Agent 4 parity smoke가 끝날 때까지 TCP `--room-transport-server`는 fallback harness로 유지한다
  - ordering, error code, mailbox semantics는 same adapter + shared command handler 재사용으로 유지한다

### Sample `hello`
```json
{
  "type": "hello",
  "messageId": "msg_hello_001",
  "traceId": "trace_001",
  "roomId": "room_001",
  "sessionId": "sess_001",
  "payload": {
    "authToken": "app_auth_token",
    "resumeToken": "opaque_rotating_secret",
    "lastSeen": {
      "roomSequence": 12,
      "gameEventId": "evt_010",
      "stateVersion": 23
    },
    "client": {
      "platform": "ios",
      "appVersion": "1.0.0"
    }
  }
}
```

### Sample `helloAck`
```json
{
  "type": "helloAck",
  "messageId": "msg_hello_ack_001",
  "traceId": "trace_001",
  "roomId": "room_001",
  "sessionId": "sess_001",
  "roomSequence": 13,
  "serverTime": "2026-03-08T15:30:01+09:00",
  "payload": {
    "resumeMode": "fresh|resume",
    "connectionId": "conn_001",
    "heartbeatIntervalMs": 5000,
    "disconnectTimeoutMs": 15000,
    "reconnectGraceMs": 30000,
    "resultRetentionMs": 60000,
    "resumeToken": "rotated_resume_token"
  }
}
```

## Room-Level Events

| Transport Type | Event Name | Purpose | Required Payload |
| --- | --- | --- | --- |
| `roomSnapshot` | `roomSnapshot` | full room sync | room state, members, deadlines, `lastRoomSequence` |
| `roomEvent` | `roomStateChanged` | state transition broadcast | `fromState`, `toState`, `reason` |
| `roomEvent` | `memberJoined` | guest joined | `playerId`, `seat`, `role` |
| `roomEvent` | `memberLeft` | member left pre/post game | `playerId`, `reason` |
| `roomEvent` | `memberReadyChanged` | ready toggle | `playerId`, `ready` |
| `roomEvent` | `readyWindowExpired` | ready reset | `resetPlayerIds`, `nextReadyExpiresAt` or `null` |
| `roomEvent` | `playerDisconnected` | grace started | `playerId`, `graceExpiresAt` |
| `roomEvent` | `playerReconnected` | resume completed | `playerId`, `connectionId` |
| `roomEvent` | `playerForfeited` | disconnect or leave forfeit | `playerId`, `reason` |
| `roomEvent` | `roomClosed` | terminal cleanup | `reason`, `closedAt` |
| `gameEvent` | `stateSnapshot` | full player-scoped game sync | exact Agent 1 `stateSnapshot` envelope in `payload.engineEvent` |
| `gameEvent` | `actionAccepted|actionRejected|turnChanged|choiceRequested|statePatched|roundEnded|matchEnded` | realtime engine event forward | exact Agent 1 event envelope in `payload.engineEvent` |

## Reconnect / Resume Policy

### Resume Inputs
- client는 `roomId`, `sessionId`, `resumeToken`을 안전하게 저장한다.
- client는 마지막으로 적용한 `roomSequence`, `gameEventId`, `stateVersion`을 가능하면 함께 전송한다.
- `resumeToken`은 successful `hello`마다 rotate된다.

### Resume Acceptance Rules
- `playerId`, `roomId`, `sessionId`, `resumeToken`이 모두 일치해야 한다.
- room이 `closed`면 resume 불가다.
- session이 `expired`면 resume 불가다.
- newer connection이 이미 token rotation을 끝냈으면 이전 token resume은 reject다.

### Resume Sync Order
1. server는 `helloAck`를 먼저 보낸다.
2. reconnecting client에게 `roomSnapshot`을 보낸다.
3. room이 `starting` 또는 `inGame` 또는 `ended`면 Agent 1 `stateSnapshot(reason=resume)`을 담은 `gameEvent`를 보낸다.
4. snapshots 이후에만 reconnecting client에게 live `roomEvent` / `gameEvent` delivery를 시작한다.
5. `playerReconnected` room event는 reconnecting client 기준 snapshots 뒤에 전달한다.

### Same Player on Multiple Devices
- Phase 0 policy는 single active connection per player per room이다.
- 새 socket이 valid `hello`를 보내면 기존 socket은 `sessionReplaced` 오류와 close code `4409`를 받는다.
- replace는 room membership를 끊지 않는다. 단지 active connection ownership만 바꾼다.

### Resume Reject Reasons

| Code | Meaning | Client Action |
| --- | --- | --- |
| `resumeTokenInvalid` | token 불일치 또는 rotation 뒤 stale token 사용 | room 재진입 또는 전체 새로고침 |
| `resumeExpired` | reconnect grace 초과 | 결과 화면 또는 room exit |
| `roomClosed` | room 이미 종료됨 | room list 또는 result fallback |
| `sessionSuperseded` | 다른 device/socket이 ownership 선점 | 기존 socket 종료 |
| `stateSnapshotUnavailable` | Agent 1 snapshot 준비 실패 | retry once 후 fatal 처리 |

## Heartbeat / Timeout / Forfeit

### Timing Table

| Policy | Value | Starts At | On Expiry |
| --- | --- | --- | --- |
| WebSocket hello timeout | 10s | TCP/WS open 직후 | close `4408` |
| Heartbeat ping interval | 5s idle | 마지막 client frame 이후 | `ping` 전송 |
| Disconnect threshold | 15s silence | 마지막 client frame 이후 | session -> `disconnectedGrace` |
| Empty room TTL | 5m | `createRoom` success | room `closed` |
| Ready window | 60s | second player joined | ready flags reset |
| Reconnect grace | 30s | disconnect detection | pregame seat release or in-game forfeit |
| Result retention | 60s | room `ended` 진입 | room `closed` |

### Heartbeat Rules
- client -> server app 메시지가 오면 heartbeat로 인정한다.
- `pong`은 마지막으로 처리한 `roomSequence`, `gameEventId`, `stateVersion`을 함께 보낼 수 있다.
- heartbeat miss만으로 즉시 forfeit하지 않는다. 먼저 `disconnectedGrace`로 진입한다.

### Forfeit Rules
- `waitingForPlayers`, `waitingForReady`
  - guest leave 또는 guest reconnect grace 만료: guest seat 해제, room은 `waitingForPlayers`.
  - host leave 또는 host reconnect grace 만료: room `closed`.
- `starting`, `inGame`
  - explicit `leaveRoom`: 즉시 forfeit 처리.
  - reconnect grace 만료: disconnect forfeit 처리.
  - room layer는 forfeit 트리거를 결정하지만, 최종 `matchEnded` payload는 Agent 1 contract에 의존한다.
- `ended`
  - reconnect grace 만료는 추가 forfeit를 만들지 않는다.
  - 결과 조회만 허용하고 TTL 뒤 `closed`.

### Gameplay Timer Boundary
- turn/choice deadline 자체는 Agent 1 authoritative timer를 그대로 소비한다.
- Agent 2는 `choiceRequested` / `turnChanged`에 담긴 deadline 정보를 relay만 한다.
- Agent 2는 timeout 시 자동 카드 선택, auto-stop 같은 gameplay fallback을 생성하지 않는다.

## Persistence

### Must Persist
- room metadata: `roomId`, `roomType`, `joinPolicy`, `roomState`
- member seats, ready flags, presence summary
- `activeGameId`
- session metadata: `sessionId`, `playerId`, `resumeTokenHash`, `graceExpiresAt`, `lastHeartbeatAt`
- disconnect / reconnect timestamps와 현재 grace deadline
- `lastRoomSequence`
- final result summary와 room close reason

### Not Required in Phase 0
- room event backlog durable 저장
- delta resume buffer
- cross-process failover
- rematch history

### Persistence Assumption
- Phase 0 reconnect 목표는 짧은 모바일 네트워크 단절 복구다.
- 서버 프로세스 장애 후 seamless resume은 이 문서 범위 밖이다.

## Agent 1 Contract Dependencies

| Agent 1 Field / Event | Why Agent 2 Needs It | Current Need |
| --- | --- | --- |
| `gameStarted.payload` dealer / first player / initial projection | `starting -> inGame` 완료와 initial HUD bootstrap | Required |
| `stateSnapshot.payload` full player-scoped state | reconnect / resync / snapshot-first recovery | Required |
| `eventId` ordering semantics | reconnect 이후 duplicate/live ordering 구분 | Required |
| `stateVersion` increment semantics | Agent 4 resync 검증, stale UI 판단 | Required |
| `choiceRequested.choiceId` | reconnect 후 pending choice 동일성 보장 | Required |
| `choiceRequested.deadlineAt` | reconnect overlay, timer UX, timeout observability | Required |
| `choiceRequested.options[].optionCode` 및 metadata card IDs | UI/test agent가 선택지를 stable하게 식별 | Required |
| `actionRejected` payload shape | WS relay 시 engine reject를 room error와 분리 | Required |
| `matchEnded.endReason` | disconnect/quit forfeit를 terminal result와 연결 | Required |
| `matchEnded.winnerPlayerId` / `loserPlayerId` | room result summary와 forfeit actor 기록 | Required |
| `matchEnded.forfeitingPlayerId` | timeout/quit forfeit actor를 room result와 artifact에 연결 | Required |
| `roundEnded` / `matchEnded` score summary | result screen/test artifact minimum | Required |

### Forwarding Rule
- 위 필드는 room server가 새로 계산하지 않는다.
- Agent 2 구현은 Agent 1 authoritative payload를 transport-safe하게 감싸서 전달한다.
- payload shape가 비어 있으면 room layer는 임시 변환을 만들지 않고 `agent_sync_board.md`에 질문을 남긴다.

## Error Cases

| Case | Expected Handling | Open? |
| --- | --- | --- |
| join full room | REST reject `roomFull` | No |
| join closed room | REST reject `roomClosed` | No |
| duplicate ready toggle | idempotent success | No |
| stale resume token | WS reject `resumeTokenInvalid` | No |
| same player second device | newer valid socket wins | No |
| state snapshot unavailable | WS reject `stateSnapshotUnavailable` after one retry | Yes |
| Agent 1 forfeit result missing | room stays `ended` only after fallback room error/log | Yes |

## Validation Checklist
- [x] room state machine이 pregame / starting / inGame / ended / closed를 분리한다
- [x] websocket envelope이 room ordering과 Agent 1 forwarded event를 동시에 담는다
- [x] reconnect는 snapshot-first 복구 순서를 가진다
- [x] heartbeat / disconnect / reconnect grace / forfeit 경계를 명시한다
- [x] Agent 1 의존 필드가 별도 섹션으로 분리돼 있다
- [x] stale/replaced session heartbeat가 현재 연결 정보를 덮어쓰지 않는다
- [x] gameplay `room_transport_send`가 `playCard`, `submitChoice`, `quit`, `leaveRoom`를 받는다
- [x] stale `expectedStateVersion` path가 `actionRejected -> stateSnapshot(reason=resync)`를 queue한다
- [x] duplicate `actionId` exact resend가 `duplicateActionIdDisposition=exactReplay`, conflicting reuse가 `actionRejected(code=actionIdConflict)`로 live transport에서 분리된다
- [x] result dismissal path가 `leaveRoom -> roomClosed` authoritative room event로 드러난다
- [x] reconnect grace expiry transport path가 synthetic `quit(reason=disconnectTimeout)`와 terminal fan-out으로 이어진다
- [x] timeout terminal path에서 `roundEnded -> matchEnded -> terminalSummary`가 `roomClosed`보다 먼저 온다
- [x] invite room payload가 `inviteCode`를 노출하고, Phase 0에서는 `inviteCode == roomId`로 고정된다
- [x] passive TCP/WebSocket close가 explicit `disconnect`와 같은 authoritative disconnect helper로 연결된다
- [x] socket parity `MP-007`이 passive close timeout path에서 PASS다
- [x] shared server runtime automatic expiry sweep가 manual `reapExpiredState` 없이도 timeout completion을 진행한다
- [x] bootstrap concrete facade가 create/invite lookup/join/prepare-game-start current surface와 websocket handoff를 함께 노출한다
- [x] `room_gap_recovery_shape`가 dropped-event gap future extension의 flag/artifact minimum shape를 문서/CLI 레벨에서 고정한다
- [x] `room_transport_send(action=triggerGapRecovery)`가 live mailbox에 `gapRecoveryHint -> stateSnapshot(reason=gapDetected)`를 executable하게 노출한다

## Deferred Beyond Phase 0
- 아래 항목은 merge blocker가 아니라 accepted deferred backlog다.
- public REST bootstrap split
- automatic dropped-event detection 대신 explicit `triggerGapRecovery`를 대체하는 path
- current TCP/WebSocket command boundary를 넘어서는 새 transport architecture

## Change Log
- 2026-03-08: skeleton replaced with Phase 0 draft for room/session lifecycle, websocket envelope, reconnect, heartbeat, timeout, and Agent 1 dependency list
- 2026-03-08: Swift coordinator naming synced to `RoomLifecycleCoordinating`, `InMemoryRoomCoordinator`, `RoomCoordinatorMutation`, including `leaveRoom`, `closeRoom`, and `recordHeartbeat`
- 2026-03-08: `GoStopCLI` target now includes room coordinator files and `RoomCoordinatorCLIAdapter`; fresh `hello` is backed by `attachSession(_:)`
- 2026-03-08: app target now reuses the same coordinator via `LocalRoomCoordinatorDebugService`, and `recordHeartbeat(_:)` rejects stale/replaced/expired connection ownership
- 2026-03-10: `room_transport_send` gameplay relay now accepts `playCard`, `submitChoice`, `quit`, `leaveRoom`, queues nested engine envelopes including stale-version resync recovery, and exposes a TCP `--room-transport-server` binding skeleton
- 2026-03-11: transport relay now rewrites room `playerId` to authority `playerId` via room seat/session lookup, validates `roundEnded`/`matchEnded` terminal payloads, fixes live stale recovery `stateSnapshot(reason=resync)`, adds `--room-transport-websocket-server` websocket listener skeleton, routes TCP/websocket startup through a shared `RoomTransportServer` boundary, and exposes duplicate `actionId` replay/conflict semantics on live transport
- 2026-03-12: `MP-004` compare smoke confirmed duplicate `actionId` exact replay and conflicting reuse separation on both TCP fallback and websocket transport
- 2026-03-12: transport timeout hardening added `room_transport_send(action=disconnect|reapExpiredState)`, kept stale heartbeat as explicit reject parity, routed grace expiry through synthetic `quit(reason=disconnectTimeout)`, and exposed `inviteCode` as the Phase 0 share/join identifier
