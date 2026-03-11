# Agent Sync Board

## Purpose
- 4개 agent가 병렬 작업 중일 때 현재 상태, blocker, 계약 질문, merge 준비 상태를 한 곳에서 관리한다.
- 각 agent는 자기 섹션만 수정한다.
- 계약 변경은 이 보드만으로 확정하지 않고, 반드시 owner 문서 diff와 함께 남긴다.

## Global Rules
- Contract owner:
  - `multiplayer_contract.md` -> Agent 1
  - `room_protocol.md` -> Agent 2
  - `multiplayer_ui_flow.md` -> Agent 3
  - `multiplayer_test_scenarios.md` -> Agent 4
- Merge order:
  1. Agent 1
  2. Agent 2
  3. Agent 4
  4. Agent 3
- Contract update window:
  - 오전 1회
  - 오후 1회
- Freeze outside window:
  - Agent 1/2 contract는 window 외 변경 금지

## Global Status
- **Date**: 2026-03-11
- **Current Phase**: Phase 7 / Identity Mapping + Live Resync Lock
- **Integration Branch**: `codex/multiplayer-integration`
- **Top Goal**: authority-vs-room identity ownership, live stale recovery reason, terminal minimum relay shape를 잠가 Agent 2/4가 live transport blocker를 줄이게 한다
- **Critical Risks**:
  - shake choice payload가 상대에게 숨겨야 할 hand 정보를 노출하면 multiplayer contract가 바로 깨짐
  - engine projection이 `isConnected/isReady`를 항상 true로 채우면 room/session truth와 UI가 어긋남
  - replaced/expired session heartbeat를 허용하면 newest-wins session 정책이 깨짐
  - `dealerPlayerId`가 실제 starter 결과가 아니라 seat 0으로 고정되면 bootstrap payload 신뢰도가 떨어짐
  - `MP-008` stale-version hook이 live ingress에 노출되지 않으면 fixture PASS가 live regression으로 이어지지 못함
  - authority `playerId`와 room `playerId`가 다를 때 mapping layer가 없으면 bootstrap/result/transport payload 해석이 흔들림

## Shared IDs
- `traceId`
- `roomId`
- `gameId`
- `turnId`
- `actionId`
- `playerId`
- `choiceId`
- `eventId`
- `snapshotId`

## Review Findings

| ID | Owner | Finding | Status | Required Follow-Up |
| --- | --- | --- | --- | --- |
| `F-001` | Agent 1 | `askingShake` choice payload가 non-actor에게도 hand metadata를 노출함 | Closed | viewer-scoped redaction과 `actorOnly` visibility contract 반영 완료 |
| `F-002` | Agent 1 | engine projection이 `isConnected/isReady`를 항상 `true`로 채움 | Closed | room truth merge-aware optional fields와 `presenceSource` contract 반영 완료 |
| `F-003` | Agent 2 | `recordHeartbeat`가 replaced/expired/mismatched connection을 검증하지 않음 | Closed | coordinator guard + CLI `room_transport_send(action=ack|pong)` parity로 `staleConnectionId` / `invalidResumeState` 유지 확인 완료 |
| `F-004` | Agent 1 | `dealerPlayerId`가 실제 starter/dealer가 아니라 seat 0으로 고정됨 | Closed | actual starter selection result를 `starterPlayerId`/`dealerPlayerId`에 반영 완료 |
| `F-005` | Agent 4 | `MP-008` deterministic fault path는 계약이 잠겼고 fixture PASS다. 남은 일은 live gameplay resync smoke 연결이다 | Closed | latest `GoStopCLI` rebuild 기준 TCP socket smoke가 live `stale expectedStateVersion -> actionRejected -> stateSnapshot(reason=resync)` probe까지 PASS로 닫혔다 |
| `F-006` | Agent 3 | `GoStop` iOS target이 `MultiplayerShellViews.swift` top-level brace mismatch로 컴파일되지 않음 | Closed | result view 구조 hotfix와 함께 iOS build green 재검증 완료 |

## Contract Questions

### Open
- [ ] live duplicate `actionId` path가 TCP fallback / websocket 모두에서 exact same resend를 `duplicateActionIdDisposition=exactReplay`, conflicting reuse를 `duplicateActionIdDisposition=conflictReject` + `actionRejected(code=actionIdConflict)`로 잠그는지 Agent 2/4가 재확인 필요

### Resolved
- [x] `stateVersion`은 accepted command transaction 중 game state mutation이 발생할 때만 1 증가한다
- [x] reconnect/resync의 minimum recovery contract는 full `stateSnapshot` 1회이며, snapshot 이후 delta catch-up은 optional optimization이다
- [x] `choiceRequested`는 `choiceId`, `optionCode`, `labelKey`, `promptKey`, stable card metadata를 포함한다
- [x] local multiplayer preview entrypoint는 기존 `get_state`를 유지한 채 `get_multiplayer_projection`으로 분리한다
- [x] reconnect grace period 만료는 room layer가 Agent 1 `quit(reason=disconnectTimeout)` command로 engine에 넘긴다
- [x] live delta format은 RFC 6902 JSON Patch를 사용한다
- [x] room websocket은 room envelope를 유지하고 engine event는 `gameEvent.payload.engineEvent` nested payload로 전달한다
- [x] `gameStarted`와 `resume` 복구에는 Agent 1 `stateSnapshot`을 사용한다
- [x] fresh start bootstrap source는 paired `gameEvent(gameStarted)` + `gameEvent(stateSnapshot reason=gameStarted)`이며, state source of truth는 snapshot이다
- [x] projection의 `isConnected/isReady`는 room/session truth merge slot이며, room truth가 없으면 `null` + `presenceSource=unknown`을 사용한다
- [x] reconnecting client는 `helloAck -> roomSnapshot -> gameEvent(stateSnapshot) -> live events` 순서를 보장받고, `playerReconnected`는 해당 socket에서 snapshots 뒤에 전달한다
- [x] room layer timeout 1차 정책은 heartbeat 5초, disconnect 15초, reconnect grace 30초이며 `starting`/`inGame` grace 만료는 forfeit다
- [x] transport 비의존 room lifecycle API는 `RoomLifecycleCoordinating` + `InMemoryRoomCoordinator` + `RoomCoordinatorMutation` 형태로 정리한다
- [x] Agent 1 terminal result baseline은 `MultiplayerRoundEndedPayload` / `MultiplayerMatchEndedPayload`로 고정하며, forfeit path는 `settlementSummary = nil` + `forfeitingPlayerId`를 사용한다
- [x] local debug `.starting -> live` minimum bootstrap set은 `MultiplayerGameStartedBootstrapPayload { gameStarted, stateSnapshot }`이며 visible state source of truth는 `stateSnapshot`이다
- [x] Agent 3 UI-facing local bootstrap minimum type은 `MultiplayerLiveBootstrapPayload { activeGameId, gameStarted, stateSnapshot }`다
- [x] MP-008 P0 deterministic hook은 stale `expectedStateVersion` override이며, dropped game event hook은 future extension으로 남긴다
- [x] MP-008 artifact minimum fields는 `injectedMismatchMode`, `clientStateVersion`, `expectedStateVersion`, `authoritativeStateVersion`, `authoritativeEventId`, `recoverySnapshotReason`, `recoverySnapshotId`다
- [x] command stale reject path의 recovery snapshot reason은 `resync`, patch/event gap path의 recovery snapshot reason은 `gapDetected`다
- [x] authority replay artifact retention policy는 `privilegedDebugOnly`이며 fixture/CLI/socket/manual-debug 실패 또는 explicit export에서만 authority baseline/full stream을 저장한다
- [x] websocket-equivalent transport spike는 `room_transport_connect/send/receive`로 두고, stale heartbeat reject는 `staleConnectionId` / `invalidResumeState` parity를 유지한다
- [x] `dropGameEvents`는 다음 phase smoke hook으로 올리지 않고, stale gameplay transport resync smoke가 안정화될 때까지 future extension으로 유지한다
- [x] authority `playerId`와 room `playerId` mapping owner는 room/session layer이며, engine payload는 authority `playerId`만 유지한다
- [x] live stale `expectedStateVersion` recovery snapshot reason은 `resync` only이며 `localPreview`는 local preview helper 전용이다
- [x] duplicate `actionId` resolution은 `staleStateVersion`보다 우선하며, exact resend는 `exactReplay`, conflicting reuse는 `actionIdConflict` reject가 source-of-truth다

## Agent 1: Core Engine / Game Authority
- **Owner**: Agent 1
- **Current Task**: authority `playerId` vs room `playerId` mapping owner, live stale recovery `resync` rule, terminal minimum relay shape를 잠근다
- **Files In Scope**:
  - `GoStop/Core/`
  - `GoStopCLI/`
  - `multiplayer_contract.md`
- **Depends On**: 없음
- **Blocks**:
  - 없음
- **Ready For Merge**: `YES`
- **Validation**:
  - [x] deterministic replay 최소 계약 문서화
  - [x] invalid action reject reason 문서화
  - [x] duplicate `actionId` replay / conflict reject 분리 문서화
  - [x] `GoStopCLI` build 통과
  - [x] `GoStop` iOS build 통과
  - [x] `get_multiplayer_game_started_bootstrap` local preview smoke 통과
  - [x] `get_multiplayer_terminal_summary` local preview smoke 통과
  - [x] `askingShake` choice/options viewer-scoped 검증
  - [x] `isConnected/isReady` hardcode 제거 및 merge contract 고정
  - [x] `dealerPlayerId`가 starter/dealer result를 따르는지 검증
  - [x] `MultiplayerGameStartedBootstrapPayload` typed helper 추가 및 `get_multiplayer_game_started_bootstrap` source 통일
  - [x] `MultiplayerLiveBootstrapPayload` UI-facing helper 추가
  - [x] MP-008 `staleStateVersion -> resync` typed detail contract 추가
  - [x] `MultiplayerTerminalSummaryPayload` 및 enriched `get_multiplayer_terminal_summary` metadata 추가
  - [x] authority replay retention policy `privilegedDebugOnly` 결정
- **Latest Update**: websocket parity 단계에서 contract drift는 없다고 판단했다. duplicate `actionId`는 여전히 source-of-truth contract상 exact resend면 `exactReplay`, conflicting reuse면 `actionRejected(code=actionIdConflict)`다. 이 resolution은 `staleStateVersion`보다 먼저 일어나야 하며, live probe가 stale reject/resync로 빠지면 구현 drift다. 문서에는 websocket parity sample과 authority-vs-room identity note를 추가해 nested engine `playerId`는 authority identity를 유지하고 room identity는 `playerIdentityBindings`로만 lookup 한다는 점을 다시 명시했다.

## Agent 2: Backend / Lobby / Reconnect
- **Owner**: Agent 2
- **Current Task**: websocket path를 parity-ready transport로 올리고 Agent 4 live parity smoke를 받는다
- **Files In Scope**:
  - `GoStopCLI/`
  - `room_protocol.md`
  - `agent_sync_board.md`
- **Depends On**:
  - Agent 1 `stateSnapshot` / `gameStarted` / `matchEnded` contract
- **Blocks**:
  - live duplicate `actionId` exactReplay / conflictReject semantics가 actual gameplay transport probe에서 아직 닫히지 않았다
- **Ready For Merge**: `NO`
- **Validation**:
  - [x] room/session Swift model 타입 추가
  - [x] `InMemoryRoomCoordinator`에 create/join/ready/attach/leave/close/disconnect/resume/heartbeat/game start/end/expiry skeleton 반영
  - [x] 문서에 `RoomLifecycleCoordinating` / `RoomCoordinatorMutation` naming 매핑 추가
  - [x] shared coordinator + DEBUG app facade direct `swiftc` typecheck 통과
  - [x] shim smoke로 `room_create -> room_hello -> room_ack(ok) -> room_ack(stale)`에서 `staleConnectionId` reject 확인
  - [x] `GoStopCLI` target source inclusion 완료
  - [x] `GoStop` app target source inclusion + `LocalRoomCoordinatorDebugService` facade 추가
  - [x] CLI `room_hello`와 DEBUG `hello*`가 shared resolver를 사용하도록 정리
  - [x] DEBUG facade에 `helloGuest`, `setGuestReady`, `recordGameStarted` helper 추가
  - [x] `recordGameStarted` metadata에 `gameStartControlMode` / `gameStartedBootstrapPlan` 추가
  - [x] DEBUG facade에 `recordGameStartedAndPrepareBootstrap(...)` one-shot flow 추가
  - [x] MP-008 stale `expectedStateVersion` override hook을 CLI/debug surface에 노출
  - [x] unrestricted `xcodebuild`로 `GoStopCLI` / `GoStop` target build 재검증 통과
  - [x] `recordMatchEnded` metadata에 `terminalSummaryRelayRequest` 추가
  - [x] shared presence merge request builder를 bootstrap / projection / terminal relay에 공통 적용
  - [x] CLI `room_projection_preview`, `room_record_match_ended_and_fetch_terminal_summary` direct relay 추가
  - [x] CLI `room_transport_connect/send/receive` websocket-equivalent spike 추가
  - [x] DEBUG facade에 `recordGameStartedAndFetchBootstrap`, `projectionPreview`, `recordMatchEndedAndFetchTerminalSummary` 추가
  - [x] transport spike smoke에서 queued `gameEvent` / `terminalSummary` 확인
  - [x] `room_transport_send` gameplay action `playCard`, `submitChoice`, `quit`, `leaveRoom` 추가
  - [x] stale `expectedStateVersion` path에서 `actionRejected -> stateSnapshot(reason=resync)` queue 확인
  - [x] `quit` path에서 `actionAccepted`, `roundEnded`, `matchEnded`, `terminalSummary` fan-out 확인
  - [x] `leaveRoom` result dismissal path에서 final `roomClosed` room event 확인
  - [x] `GoStopCLI --room-transport-server` TCP binding skeleton 추가 및 localhost smoke 확인
  - [x] room seat/session lookup 기반 room `playerId -> authority playerId` mapping을 gameplay/bootstrap/projection/terminal relay에 적용
  - [x] direct/transport terminal relay에서 `roundEnded`, `matchEnded`, `terminalSummary` socket probe PASS
  - [x] socket mode `MP-008` live `stateSnapshot(reason=resync)` PASS
  - [x] `GoStopCLI --room-transport-websocket-server` websocket listener skeleton 추가 및 startup 확인
  - [x] websocket/TCP startup을 shared `RoomTransportServer` boundary로 공용화
  - [x] transport gameplay path에 duplicate `actionId` exact replay / conflict reject 노출
  - [x] websocket path에 per-connection serial frame send queue 추가
- **Latest Update**: websocket path는 same `RoomCoordinatorCLIAdapter`를 그대로 재사용하면서 per-connection serial frame send queue를 추가해 request/response ordering을 고정했다. Agent 4 compare smoke 기준 `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`는 websocket/TCP parity PASS고, stale heartbeat reject와 resume reject도 `staleConnectionId` / `invalidResumeState`로 유지된다. 남은 transport blocker는 `MP-004` live duplicate probe에서 exact resend가 `exactReplay`가 아니라 stale reject/resync로 빠지고 conflicting reuse도 `actionIdConflict` 대신 same stale reject로 귀결되는 점이다.

## Agent 3: iOS Multiplayer Client / UX
- **Owner**: Agent 3
- **Current Task**: first real websocket transport source를 app shell boundary 위에 mount하고, create/resume/result dismissal을 authoritative room lifecycle 기준으로 유지하기
- **Files In Scope**:
  - `GoStop/Views/`
  - `GoStop/ViewModels/`
  - `multiplayer_ui_flow.md`
  - `agent_sync_board.md`
- **Depends On**:
  - Agent 1 payload fields
  - Agent 2 room/websocket envelope
- **Blocks**:
  - Agent 2: invite flow가 human-readable share code를 요구하면 `inviteCode` 또는 equivalent join identifier shape 확정 필요
  - final REST bootstrap split은 아직 안 붙었다. 현재 first real source는 Agent 2 websocket command boundary(`room_create`, `room_join`, `room_transport_*`)를 사용한다
  - `match.end.*`, `match.result.leave.*`, `room.closed.*`, `match.choice.shake.actor_only_waiting` key 중 일부는 message catalog entry가 아직 없어 raw key/detail fallback이 남는다
  - product navigation mount는 아직 `MP Lab` 밖으로 올라오지 않았다
  - production source의 gameplay card / choice command send path는 아직 안 붙었다
- **Ready For Merge**: `NO`
- **Validation**:
  - [x] room 진입 흐름 문서화
  - [x] reconnect 중 input lock / overlay 해제 조건 문서화
  - [x] reject/error UX와 payload checklist 문서화
  - [x] `MultiplayerEntryView`, `MultiplayerRoomView`, `MultiplayerLiveShellView`, `MultiplayerReconnectOverlay`, `MultiplayerResultView` shell 추가
  - [x] placeholder UI state 타입 추가 및 preview/mock 렌더 경로 확보
  - [x] `MultiplayerShellStore`로 mock route transition과 reconnect/result handoff를 로컬에서 구동
  - [x] `MultiplayerShellMapper`와 room/hello UI DTO로 contract payload -> shell state 매핑 골격 추가
  - [x] `ContentView`에 debug launcher를 붙여 app 내부에서 multiplayer shell lab 진입 가능
  - [x] `MultiplayerShellStore`를 pluggable source 구조로 전환
  - [x] DEBUG `MP Lab` 첫 탭을 `LocalRoomCoordinatorDebugService` 기반 coordinator lab으로 교체
  - [x] `Create Room`, `Join Guest`, guest `hello`, `Ready`, `Guest Ready`, `Apply gameStarted`, `Disconnect`, `Resume`, `Heartbeat`를 actual local debug service 호출로 연결
  - [x] room snapshot truth가 ready/presence/banner와 reconnect overlay를 구동하도록 반영
  - [x] room `.inGame` actual mutation 이후 `showLive`로 넘어가고, disconnect/resume overlay가 live route 위에서 유지되도록 정리
  - [x] local debug entry에서 unsupported `Join Invite`를 숨겨 RF-002 경로 제거
  - [x] `GoStop` iOS target build에서 shell/state 변경 컴파일 확인
  - [x] authoritative `stateSnapshot(reason=gameStarted)` -> live shell 연결
  - [x] local debug `Apply matchEnded` -> authoritative terminal payload -> result shell 바인딩
  - [x] result dismissal이 local debug `leaveRoom -> explicit leave ack or roomClosed` authoritative signal에 맞춰 entry로 종료되는지 확인
  - [x] shake `actorOnly` redaction UI policy 최종 검증
  - [x] `MultiplayerTransportShellSource`로 persisted resume `hello resume` attach와 result `leaveRoom`의 future production entrypoint 고정
  - [x] `MultiplayerBufferedTransportAdapter`가 Agent 2 envelope(`helloAck`, `roomSnapshot`, `gameEvent`, `roomEvent`, `terminalSummary`)를 `MultiplayerShellInboundEvent`로 decode
  - [x] app shell direct entrypoint `activateTransportSource()` / `persistedResumeAttachRequest()` / `resumePersistedSessionOverTransport()` / `ingestTransportEnvelope(data,jsonObject)` / `sendAuthoritativeLeaveFromResult()` 추가
  - [x] `MultiplayerWebSocketCommandNetworkingAdapter`를 `MultiplayerShellNetworkingAdapter` concrete 구현으로 연결
  - [x] `MP Lab > Transport` 탭에서 real websocket command source mount 확인
  - [x] transport source가 actual `Create Room -> Join Guest -> Ready -> Guest Ready -> Apply gameStarted -> Apply matchEnded` flow를 Agent 2 websocket command boundary로 보냄
  - [x] result dismissal이 transport `memberLeft(local)` 또는 `roomClosed` authoritative signal에만 반응하도록 유지
  - [x] shell rendering path가 `gameText(...)`를 통해 `match.end.*`, `match.result.leave.*`, `room.closed.*`, shake actor-only waiting copy를 우선 resolve
- **Latest Update**: `MP Lab > Transport`는 now `MultiplayerWebSocketCommandNetworkingAdapter`를 통해 Agent 2 websocket command server를 실제로 소비한다. local host create는 `room_create + room_transport_connect/send(action=hello)`를 타고, peer join/ready는 secondary guest websocket client가 `room_join + room_transport_*`를 사용해 room truth를 바꾼 뒤 host store가 authoritative `roomSnapshot`/`gameEvent`만 다시 그린다. persisted resume는 real `hello resume` attach로 이어지고, result route는 transport `memberLeft(local)`를 leave completion으로 매핑하거나 final `roomClosed`를 받을 때만 entry로 닫힌다. create/join은 아직 REST split이 아니라 websocket command boundary 위에 있고, main app product route mount는 여전히 후속 작업이다.

## Agent 4: Debugging / Test Scenarios / Observability
- **Owner**: Agent 4
- **Current Task**: fixture/CLI/socket green 상태를 유지하면서 TCP fallback vs websocket parity smoke를 계속 돌리고, live duplicate `actionId` blocker를 artifact로 좁힌다
- **Files In Scope**:
  - `tests/test_agent/multiplayer_runner.py`
  - `tests/test_agent/multiplayer/`
  - `multiplayer_test_scenarios.md`
  - `agent_sync_board.md`
- **Depends On**:
  - Agent 2 duplicate `actionId` gameplay semantics가 actual transport에서 `exactReplay` / `conflictReject`로 잠겨야 live duplicate smoke가 닫힌다
- **Blocks**:
  - websocket debug connect 경로의 stale heartbeat error envelope가 CLI ingress와 같은 code를 유지하는지 확인 필요
  - `MP-004` live duplicate probe가 TCP fallback / websocket 공통으로 `exactReplay` 대신 stale reject/resync를 받고 있다
  - dropped-event gap 기반 MP-008 future extension은 아직 live transport에 연결되지 않았다
- **Ready For Merge**: `NO`
- **Validation**:
  - [x] `MP-001 ~ MP-008` 상세 draft 작성
  - [x] multiplayer runner/helper separate entrypoint 추가
  - [x] actual Python scenario step skeleton registry 추가
  - [x] manifest / replay / snapshot / anomaly artifact skeleton 코드화
  - [x] fixture transcript/validator 추가
  - [x] `MP-001/002/003/004/005/006/007` fixture mode PASS
  - [x] `MP-013/014` fixture mode PASS
  - [x] `MP-008` fixture mode PASS with stale `expectedStateVersion` override + `stateSnapshot(reason=resync)`
  - [x] artifact path layout / failure retention 기준 정리
  - [x] Agent 2 websocket envelope / reconnect ordering / 30s grace 반영
  - [x] reconnect / duplicate / invalid choice / stateVersion mismatch lens 정리
  - [x] scaffold runner scenario ID 매핑
  - [x] shake choice hidden-info leak regression 추가
  - [x] replaced/expired session heartbeat regression 추가
  - [x] CLI smoke script에 `ready-start`, `disconnect-resume`, `heartbeat-guard`, `mp008-hook-surface`, `mp008-gameplay-resync` preflight 묶음과 artifact output 추가
  - [x] CLI smoke full `guest ready -> gameStarted` paired bootstrap assertion
  - [x] local debug manual checklist를 `create/join/ready/start/live/disconnect/resume` 기준으로 구체화
  - [x] `Join Invite` unsupported/error behavior를 explicit validation point로 추가
  - [x] MP-008 `replay/injection_manifest.json` / `timeline/mismatch.ndjson` artifact skeleton 추가
  - [x] CLI `room_set/get/clear_mp008_hook` surface smoke 추가
  - [x] `--mode socket` runner entry와 `socket-smoke` suite 추가
  - [x] socket mode에서 `MP-001` paired bootstrap PASS
  - [x] socket mode에서 `MP-014` stale heartbeat reject parity PASS
  - [x] socket mode를 actual GoStopCLI `--room-transport-server` TCP facade로 승격
  - [x] stale `expectedStateVersion` override를 실제 gameplay resync probe로 연결
  - [x] socket mode에서 `MP-008` live `actionRejected(staleStateVersion)` + recovery snapshot delivery 확인
  - [x] socket runner에 `--binary` / cached derived data 우선 reuse 경로 추가
  - [x] socket terminal lifecycle probe(`MP-002`) 추가
  - [x] socket mode에서 `MP-008` live `stateSnapshot(reason=resync)` PASS
  - [x] socket mode에서 `MP-002` live `roundEnded`, `matchEnded`, `terminalSummary`, `roomClosed` PASS
  - [x] socket mode에서 `MP-013` actor/peer shake redaction PASS
  - [x] `socket-review-fixups` suite로 `MP-013/014` actual TCP facade 재검증
  - [x] GoStopCLI websocket transport parity smoke (`MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`) PASS
  - [x] socket runner `--transport tcp|websocket|compare`와 `transport_parity.json` compare artifact 추가
  - [x] `socket-duplicate` suite + `duplicate_probe.json` artifact 추가
  - [ ] `MP-004` live duplicate exactReplay / conflictReject PASS
- **Latest Update**: latest cached binary를 재사용한 compare smoke 기준 websocket/TCP parity는 `MP-001`, `MP-002`, `MP-008`, `MP-013`, `MP-014`에서 PASS다. `tests/test_agent/multiplayer_runner.py --suite socket-parity --mode socket --transport compare --skip-build`가 ordering/terminal/resync/privacy/heartbeat semantics를 같은 artifact layout으로 잠근다. 남은 live blocker는 `MP-004`: `tests/test_agent/multiplayer_runner.py --suite socket-duplicate --mode socket --transport compare --skip-build`에서 exact duplicate resend가 `duplicateActionIdDisposition=exactReplay`를 돌려주지 않고, conflicting reuse도 `actionIdConflict` 대신 `staleStateVersion` reject + `stateSnapshot(reason=resync)`로 떨어진다. offline-friendly 실행을 위해 socket runner와 CLI smoke는 계속 `--binary`와 known cached derived data reuse를 fresh build보다 우선한다.
  - latest cached root priority는 `/tmp/gostop_cli_agent4_round7_recheck`, `/tmp/gostop_cli_round7_review`를 우선 사용하도록 정리했다.

## Handoff Notes

### Agent 1
- 완료 항목:
  - `stateVersion`은 accepted mutation command 기준으로 1회 증가하도록 고정
  - `eventId`는 `gameId` 내부 monotonic ordering key로 고정
  - duplicate `actionId`는 exact replay, conflicting reuse는 `actionIdConflict` reject로 고정
  - `MultiplayerContract.swift`에 command/event/reject/choice/snapshot/projection Swift 타입 추가
  - `GameManager.multiplayerSnapshot(...)`로 player-scoped snapshot helper 추가
  - `SimulatorBridge` / `GoStopCLI`에 `get_multiplayer_projection` read-only entry point 추가
  - fresh start bootstrap source를 paired `gameStarted` + `stateSnapshot(reason=gameStarted)`로 잠금
  - `MultiplayerGameStartedPayload` 및 `get_multiplayer_game_started_bootstrap` preview entry point 추가
  - `askingShake`를 `actorOnly` visibility + non-actor redaction으로 수정
  - projection presence를 optional room-truth merge slot으로 수정하고 `presenceSource`를 추가
  - `starterPlayerId`를 추가하고 `dealerPlayerId`/bootstrap payload가 actual starter result를 따르도록 수정
  - `GameManager.multiplayerRoundEndedPayload(...)` / `multiplayerMatchEndedPayload(...)` 추가
  - `SimulatorBridge` / `GoStopCLI`에 `get_multiplayer_terminal_summary` read-only entry point 추가
  - `MultiplayerGameStartedBootstrapPayload`와 `GameManager.multiplayerGameStartedBootstrapPayload(viewerPlayerId:context:)` / `TestControlSupport.multiplayerGameStartedBootstrapPayload(from:requestData:)` 추가
  - `MultiplayerLiveBootstrapPayload`와 `GameManager.multiplayerLiveBootstrapPayload(viewerPlayerId:context:)` / `TestControlSupport.multiplayerLiveBootstrapPayload(from:requestData:)` 추가
  - `MultiplayerResyncDirective` / `MultiplayerStaleStateVersionRejectDetails` / `MultiplayerPatchGapResyncDetails` 추가
  - `MultiplayerTerminalSummaryPayload`, `matchEnded.roundIndex`, enriched `get_multiplayer_terminal_summary` metadata 추가
  - authority replay retention policy를 `privilegedDebugOnly`로 고정
  - `playCard` / `submitChoice` / `quit` `room_transport_send` relay-ready sample과 success/failure envelope sequence를 고정
  - stale `expectedStateVersion` reject 뒤 `stateSnapshot(reason=resync)` websocket recovery pair ordering을 고정
  - `dropGameEvents`를 Phase 6 smoke hook으로 올리지 않고 future extension으로 유지한다고 결정
  - authority `playerId`와 room `playerId` mapping owner를 room/session layer로 고정하고 `playerIdentityBindings { roomPlayerId, authorityPlayerId }` binding shape를 추가
  - `MultiplayerResyncDirective.snapshotReason`을 recovery-only enum으로 좁혀 live stale recovery에서 `localPreview`를 배제
  - transport terminal minimum required fields를 `roundEnded`, `matchEnded`, `terminalSummary`별로 다시 좁혀 sample payload로 고정
  - authority identity field matrix와 terminal validator mutual-condition rule(`settlementSummary` vs `forfeitingPlayerId`)를 추가
  - duplicate `actionId` precedence rule을 고정: duplicate resolution은 `staleStateVersion`보다 먼저 일어나고, exact resend는 `exactReplay`, conflicting reuse는 `actionIdConflict` reject여야 한다
- 미완료 항목:
  - actual websocket/server binding이 same `playerIdentityBindings`와 `resync` rule을 유지하는지 live parity 확인
- 리스크:
  - room layer가 `participantPresenceByPlayerId` merge를 누락하면 projection에는 `presenceSource=unknown`이 남는다
  - Agent 3는 local debug `showLive` 전환 시 Agent 2 `recordGameStarted`와 Agent 1 bootstrap payload를 같은 버튼/flow에 묶되, visible state source of truth를 항상 `stateSnapshot(reason=gameStarted)`에 두어야 한다
  - MP-008 P0는 stale command override path만 잠겼고, dropped game event 기반 gap injection은 아직 future extension이다
  - room/player identity가 분리되면 `winnerPlayerId` / `forfeitingPlayerId` / `choiceRequested.actorPlayerId` 같은 authority 필드를 room identity로 오해하지 않도록 transport mapper가 필요하다

### Agent 2
- 완료 항목:
  - room state machine을 `waitingForPlayers -> waitingForReady -> starting -> inGame -> ended -> closed`로 고정
  - websocket envelope를 `hello/helloAck/roomSnapshot/roomEvent/gameEvent/ping/pong/ack/error`로 정리
  - reconnect는 snapshot-first(`roomSnapshot` + `gameEvent(stateSnapshot)`)로 고정
  - heartbeat 5초, disconnect 15초, reconnect grace 30초, result retention 60초 초안 확정
  - `Room`, `RoomMember`, `RoomSession`, `RoomState`, `RoomLifecycleCoordinating`, `InMemoryRoomCoordinator` Swift 골격 추가
  - app/CLI가 같은 coordinator를 재사용하도록 target membership을 정리하고 `LocalRoomCoordinatorDebugService` / `MultiplayerDebugServices.roomCoordinator` DEBUG facade를 추가
  - `recordHeartbeat(_:)`가 stale/replaced/expired owner를 reject하도록 newest-wins guard를 강화
  - CLI `room_hello`와 DEBUG `hello`/`helloHost`/`helloGuest`가 shared `performRoomHello(...)` resolver를 쓰도록 정리
  - DEBUG facade에 `helloGuest`, `setGuestReady`, `recordGameStarted` convenience를 추가
  - `recordGameStarted` metadata에 `gameStartControlMode=explicitRecordGameStarted`와 `gameStartedBootstrapPlan`을 추가
  - DEBUG facade에 `recordGameStartedAndPrepareBootstrap(...)`, `lastGameStartedFlowResult`, `deterministicFaultHook` state를 추가
  - MP-008 deterministic hook을 `staleExpectedStateVersionOverride`로 고정하고 CLI `room_set/get/clear_mp008_hook`과 DEBUG service API를 추가
- 미완료 항목:
  - `forfeitingPlayerId`와 room terminal payload forwarder 연결
  - 실제 websocket/server ingress와 Agent 1 event relay 연결
  - room snapshot truth를 `participantPresenceByPlayerId`로 projection/bootstrap preview에 merge
- 리스크:
  - full Xcode build는 통과했지만 actual websocket/runtime smoke가 아직 없어 room-layer truth merge가 wire 단계에서 어긋날 수 있음
  - `participantPresenceByPlayerId` merge를 빼먹으면 game snapshot에는 `presenceSource=unknown`만 남아 UI/debug connect truth가 비게 됨

### Agent 3
- 완료 항목:
  - `multiplayer_ui_flow.md`와 shell/mapped demo/UI launcher 정리
  - entry/room/live/reconnect/result shell과 local route host 추가
  - `MultiplayerShellStore` pluggable source 구조화
  - DEBUG `MP Lab` coordinator tab에서 `LocalRoomCoordinatorDebugService` 직접 호출 wiring 완료
  - `Create Room`, `Join Guest`, guest `hello`, `Ready`, `Guest Ready`, `Apply gameStarted`, `Disconnect`, `Resume`, `Heartbeat` actual local debug action 연결
  - room snapshot truth 기반 ready/presence/banner/reconnect overlay 반영
  - room `.inGame` actual mutation 이후 `showLive` handoff와 live-route reconnect 유지 반영
  - local debug entry에서 unsupported `Join Invite` 숨김
- 미완료 항목:
  - real adapter / persistence wiring
  - `MultiplayerGameStartedBootstrapPayload`를 이용한 actual game bootstrap / result route binding
  - `actorOnly` shake choice redaction UI policy 반영
  - product leave/navigation/localization wiring
- 리스크:
  - DEBUG coordinator tab의 room lifecycle은 authoritative지만, live projection/result는 아직 actual engine payload와 직접 이어지지 않음
  - non-actor shake choice는 `cards=[]`, `metadata=null`, `visibility=actorOnly`가 정상 shape이므로 mapper가 이를 error로 취급하면 안 됨
  - `.starting -> showLive`에서는 `gameStarted` 단독이 아니라 `stateSnapshot(reason=gameStarted)`가 state source of truth라는 점을 mapper가 유지해야 함
  - local debug UI handoff minimum은 `MultiplayerLiveBootstrapPayload.activeGameId + stateSnapshot`이며, `gameStarted`는 auxiliary marker다

### Agent 4
- 완료 항목:
  - `MP-001 ~ MP-008` 상세 step/assertion/observability 초안 작성
  - multiplayer runner, skeletons, fixtures, validators, artifact store 추가
  - fixture mode로 `MP-001..MP-008`, `MP-013`, `MP-014` PASS 확인
  - `scripts/run_multiplayer_cli_two_player_smoke.py --scenario all`로 `ready-start`, `disconnect-resume`, `heartbeat-guard`, `mp008-hook-surface`, `mp008-gameplay-resync` preflight smoke 묶음 추가
  - `ready-start` smoke에 explicit `room_record_game_started` + paired `get_multiplayer_game_started_bootstrap` assert 추가
  - `tests/test_agent/multiplayer_runner.py --mode socket`와 `tests/test_agent/multiplayer/socket_transport.py`로 actual GoStopCLI `--room-transport-server` TCP smoke 경로 추가
  - socket mode `MP-001`, `MP-002`, `MP-008`, `MP-014` green smoke 유지
  - socket mode `MP-013` actor/peer shake redaction PASS 및 `socket-review-fixups` suite 추가
  - socket runner / CLI smoke에 cached binary reuse 우선 경로 추가
  - local debug manual checklist를 `create/join/ready/start/live/disconnect/resume` 단계로 재정리
  - `Join Invite` unsupported/error path를 explicit validation point로 추가
- 미완료 항목:
  - actual websocket binding으로 `room_transport_*` spike smoke를 치환
  - websocket debug connect 경로에서 `MP-013/014` parity를 다시 잠금
  - dropped-event gap 기반 MP-008 future extension live smoke 추가
- 리스크:
  - websocket debug connect 경로가 CLI ingress와 다른 stale heartbeat error envelope를 쓰면 `MP-014` 실제 transport smoke가 다시 어긋날 수 있음
  - shake privacy 회귀는 hidden-info leak이므로 actor/non-actor projection pair artifact를 항상 남겨야 안전함
  - current socket smoke는 GoStopCLI TCP facade 기준이므로, future external websocket room->engine relay path가 끼어들면 별도 parity smoke가 필요함
  - live projection이 authority `playerId`를 사용해 `playCard` path가 아직 room `playerId`와 직접 맞지 않는다
  - `Join Invite`가 unsupported인지 intended error path인지 UI/source contract가 모호하면 RF-002가 다시 숨어들 수 있음
