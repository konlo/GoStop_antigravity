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
- **Date**: 2026-03-10
- **Current Phase**: Phase 5 / Result Route + Transport Spike
- **Integration Branch**: `codex/multiplayer-integration`
- **Top Goal**: local debug bootstrap/resync baseline은 잠겼으므로, merge 전에 app compile 회귀를 제거하고 result route + transport spike로 넘어간다
- **Critical Risks**:
  - shake choice payload가 상대에게 숨겨야 할 hand 정보를 노출하면 multiplayer contract가 바로 깨짐
  - engine projection이 `isConnected/isReady`를 항상 true로 채우면 room/session truth와 UI가 어긋남
  - replaced/expired session heartbeat를 허용하면 newest-wins session 정책이 깨짐
  - `dealerPlayerId`가 실제 starter 결과가 아니라 seat 0으로 고정되면 bootstrap payload 신뢰도가 떨어짐
  - `MP-008` stale-version hook이 live ingress에 노출되지 않으면 fixture PASS가 live regression으로 이어지지 못함

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
| `F-005` | Agent 4 | `MP-008` deterministic fault path는 계약이 잠겼고 fixture PASS다. 남은 일은 live gameplay resync smoke 연결이다 | Open | `room_transport_*` preflight는 붙었고, 이제 gameplay command + `expectedStateVersion` transport surface가 필요하다 |
| `F-006` | Agent 3 | `GoStop` iOS target이 `MultiplayerShellViews.swift` top-level brace mismatch로 컴파일되지 않음 | Closed | result view 구조 hotfix와 함께 iOS build green 재검증 완료 |

## Contract Questions

### Open
- [ ] actual websocket server binding이 CLI `room_transport_connect/send/receive`와 같은 envelope ordering(`helloAck -> roomSnapshot -> roomEvent/gameEvent*`)과 `terminalSummary` fan-out을 유지할지 최종 확인 필요

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

## Agent 1: Core Engine / Game Authority
- **Owner**: Agent 1
- **Current Task**: terminal/result route와 transport relay가 흔들리지 않도록 terminal summary / replay retention / relay-ready resync envelope contract를 잠근다
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
- **Latest Update**: terminal/result consumer가 `roundEnded`와 `matchEnded`를 별도 추정 없이 쓰도록 `MultiplayerTerminalSummaryPayload { roomId, gameId, summaryStateVersion, lastEventId, roundEnded, matchEnded }`를 추가했고, `matchEnded.roundIndex`도 required field로 올렸다. `get_multiplayer_terminal_summary`는 같은 metadata를 함께 반환하고, replay retention policy는 `privilegedDebugOnly`로 잠갔다. websocket relay에서는 stale reject / `stateSnapshot(reason=resync|gapDetected)` engine envelope를 그대로 nested해 쓰면 된다.

## Agent 2: Backend / Lobby / Reconnect
- **Owner**: Agent 2
- **Current Task**: CLI/local debug에서 validated room semantics를 actual transport spike와 terminal/result relay까지 끌어올린다
- **Files In Scope**:
  - `GoStopCLI/`
  - `room_protocol.md`
  - `agent_sync_board.md`
- **Depends On**:
  - Agent 1 `stateSnapshot` / `gameStarted` / `matchEnded` contract
- **Blocks**:
  - actual websocket/server ingress는 아직 `room_transport_*` spike를 production socket layer로 치환하지 못했다
  - authority playerId와 room playerId를 다르게 두면 terminal/bootstrap preview payload가 viewer/presence merge를 의미 있게 못 쓴다
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
- **Latest Update**: terminal/result route는 이제 room metadata plan에서 멈추지 않는다. `recordMatchEnded`는 `terminalSummaryRelayRequest`를 만들고, CLI direct relay와 `room_transport_send(action=recordMatchEndedAndFetchTerminalSummary)`가 실제 `get_multiplayer_terminal_summary` payload를 consumer mailbox까지 전달한다. bootstrap/projection/terminal preview는 모두 shared `participantPresenceByPlayerId` builder를 쓰도록 맞췄고, Agent 4는 `room_transport_connect -> room_transport_send(hello/setReady/recordGameStartedAndPrepareBootstrap/recordMatchEndedAndFetchTerminalSummary) -> room_transport_receive` 순서로 socket smoke를 붙이면 된다.

## Agent 3: iOS Multiplayer Client / UX
- **Owner**: Agent 3
- **Current Task**: DEBUG `MP Lab`의 live/result route를 authoritative helper 기반으로 유지하면서, 실제 room/websocket relay 전 blocker를 줄이기
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
  - networking adapter와 persisted session storage가 아직 `Multiplayer*ShellState`로 연결되지 않음
  - `match.end.*` localization key와 leave completion 정책이 result shell/navigation에 아직 연결되지 않음
  - coordinator tab result는 authoritative terminal helper까지 연결됐지만, actual room/websocket `matchEnded` relay와 `roomClosed` completion path는 아직 미연결
  - product `Leave Room`은 아직 lab reset으로 대체되어 있고 실제 `leaveRoom`/`roomClosed` UX policy가 잠기지 않음
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
  - [ ] shake `actorOnly` redaction UI policy 최종 검증
- **Latest Update**: DEBUG `MP Lab`은 여전히 `create -> host hello -> guest join -> guest hello -> host ready -> guest ready -> gameStarted -> live -> disconnect -> resume`를 실제 room/session mutation 기준으로 보여준다. 이번 턴에서는 `MultiplayerShellViews.swift` result 섹션 brace hotfix로 iOS compile regression을 닫았고, `MultiplayerLocalDebugShellSource`가 stable transient `GameManager`를 재사용하면서 `Apply matchEnded` control에서 `TestControlSupport.multiplayerTerminalSummaryPayload`를 생성해 `showResult`로 진입하도록 연결했다. result CTA는 actual `roomClosed`/leave ack 전까지 disabled `Leave Room Pending` 정책으로 표시한다.

## Agent 4: Debugging / Test Scenarios / Observability
- **Owner**: Agent 4
- **Current Task**: fixture/CLI green 상태를 유지하면서 `--mode socket` live spike를 키우고, MP-008을 gameplay resync smoke로 올릴 준비를 계속한다
- **Files In Scope**:
  - `tests/test_agent/multiplayer_runner.py`
  - `tests/test_agent/multiplayer/`
  - `multiplayer_test_scenarios.md`
  - `agent_sync_board.md`
- **Depends On**:
  - Agent 2가 `room_transport_send` 또는 equivalent live surface에 gameplay command + `expectedStateVersion`를 실어 보낼 수 있어야 MP-008 end-to-end smoke가 닫힌다
- **Blocks**:
  - websocket debug connect 경로의 stale heartbeat error envelope가 CLI ingress와 같은 code를 유지하는지 확인 필요
  - `room_transport_*` spike 기반 socket smoke는 붙었지만, actual websocket room->engine relay smoke는 아직 없다
  - `room_transport_send`가 gameplay command + `expectedStateVersion`를 아직 지원하지 않아 MP-008 live resync는 preflight BLOCKED다
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
  - [x] socket mode에서 `MP-008` hook attachment preflight + mismatch artifact generation
  - [ ] stale `expectedStateVersion` override를 실제 gameplay resync smoke로 연결
  - [ ] actual websocket room->engine relay smoke
- **Latest Update**: multiplayer harness는 `MP-001/002/003/004/005/006/007/008/013/014` fixture PASS 상태를 유지한다. CLI smoke `ready-start`는 explicit `room_record_game_started -> room_snapshot(inGame) -> get_multiplayer_game_started_bootstrap` 순서로 paired bootstrap을 assert하고, `mp008-gameplay-resync`는 현재 hook attachment preflight까지 유지한다. 새 `--mode socket` runner는 GoStopCLI `room_transport_connect/send/receive` spike에 붙어 `MP-001` bootstrap PASS와 `MP-014` stale heartbeat parity PASS를 확인한다. `MP-008`은 stale `expectedStateVersion` override hook을 live bootstrap 뒤에 부착하는 preflight artifact까지는 올라왔고, gameplay command transport surface가 없어 end-to-end resync는 아직 BLOCKED다.

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
- 미완료 항목:
  - dropped game event 기반 gap injection을 P1 future extension으로 둘지 별도 smoke hook으로 올릴지 후속 합의
- 리스크:
  - room layer가 `participantPresenceByPlayerId` merge를 누락하면 projection에는 `presenceSource=unknown`이 남는다
  - Agent 3는 local debug `showLive` 전환 시 Agent 2 `recordGameStarted`와 Agent 1 bootstrap payload를 같은 버튼/flow에 묶되, visible state source of truth를 항상 `stateSnapshot(reason=gameStarted)`에 두어야 한다
  - MP-008 P0는 stale command override path만 잠겼고, dropped game event 기반 gap injection은 아직 future extension이다

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
  - `tests/test_agent/multiplayer_runner.py --mode socket`와 `tests/test_agent/multiplayer/socket_transport.py`로 live transport spike smoke 경로 추가
  - socket mode `MP-001` bootstrap PASS, `MP-014` stale heartbeat parity PASS 확인
  - local debug manual checklist를 `create/join/ready/start/live/disconnect/resume` 단계로 재정리
  - `Join Invite` unsupported/error path를 explicit validation point로 추가
- 미완료 항목:
  - stale `expectedStateVersion` override를 actual gameplay resync smoke로 연결
  - actual websocket binding으로 `room_transport_*` spike smoke를 치환
- 리스크:
  - websocket debug connect 경로가 CLI ingress와 다른 stale heartbeat error envelope를 쓰면 `MP-014` 실제 transport smoke가 다시 어긋날 수 있음
  - shake privacy 회귀는 hidden-info leak이므로 actor/non-actor projection pair artifact를 항상 남겨야 안전함
  - current socket smoke는 GoStopCLI `room_transport_*` spike 기준이므로, future external websocket room->engine relay path가 끼어들면 별도 transport smoke가 필요함
  - `Join Invite`가 unsupported인지 intended error path인지 UI/source contract가 모호하면 RF-002가 다시 숨어들 수 있음
