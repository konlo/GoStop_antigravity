# Multiplayer UI Flow

## Meta
- **Owner**: Agent 3
- **Primary Consumers**: Agent 1, Agent 2, Agent 4
- **Status**: Draft
- **Last Updated**: 2026-03-12
- **Related Docs**:
  - `multiplayer_contract.md`
  - `room_protocol.md`
  - `multiplayer_test_scenarios.md`
  - `agent_sync_board.md`

## Goal
- iOS 앱에서 멀티플레이 진입부터 결과 화면까지의 사용자 흐름과 UI 상태를 정의한다.
- UI는 authoritative server state를 소비하는 thin client 원칙을 따른다.
- 아직 계약에 없는 필드는 UI가 임의 생성하지 않고 payload request로 명시한다.

## Scope
- `entry -> room -> live match -> reconnect overlay -> result` 흐름
- room / game / reconnect event를 view model route와 overlay state로 매핑
- loading / reject / error / timeout UX
- UI가 실제로 필요한 payload checklist와 blocker 정리

## Non-Goals
- 룰 판정 구현
- 서버 room lifecycle 구현
- test scenario automation 구현
- `room_protocol.md` 또는 `multiplayer_contract.md` 직접 수정

## Product Principles
- 룰 결정은 UI가 하지 않는다.
- route 전환은 authoritative event 또는 snapshot 기준으로만 한다.
- reconnect 중에는 입력을 잠그고 마지막 authoritative frame만 보여준다.
- 상대 연결 상태와 내 턴 상태를 항상 분리해서 보여준다.
- reject는 서버 code 기준으로만 번역하며, client guessed rule message를 만들지 않는다.

## End-to-End Flow

### Flow A. Entry -> Room
1. 사용자가 멀티플레이 입구에 진입하면 먼저 로컬에 저장된 `roomId`, `sessionId`, `playerId`, `deviceId`, `resumeToken`이 있는지 확인한다.
2. persisted resume candidate가 있으면 상단에 `이어하기` CTA를 노출하고, 실제 유효성 검사는 WebSocket `hello` 결과로만 확정한다.
3. `quick match`, `create invite`, `join invite`, `resume` 중 하나를 누르면 해당 CTA만 loading 처리하고 나머지 CTA는 잠근다.
4. Phase 0 create/join은 Agent 2 websocket command bootstrap(`room_create`, `room_join`) 응답의 room/session/websocket metadata를 저장하고 socket attach를 시작한다. 최종 REST split은 후속 작업이다.
5. room route 진입은 `helloAck`와 최초 `roomSnapshot` 수신 후에만 허용한다.
6. resume reject나 join/create reject는 entry에서 처리하고, terminal reject면 저장된 resume candidate를 정리한다.
7. room 진입 전 reject가 발생해도 live match route로 먼저 이동하지 않는다.

### Flow B. Room -> Live Match
1. room screen은 room snapshot과 room websocket event만으로 그린다.
2. 두 플레이어 슬롯에는 `joined`, `ready`, `connected` 상태를 동시에 표시한다.
3. ready 버튼은 탭 즉시 optimistic success로 바꾸지 않고, 서버의 `memberReadyChanged` 반영 후 상태를 갱신한다.
4. `roomState=starting`이 되면 ready/leave 관련 입력을 잠그고 시작 스피너를 보여준다.
5. Phase 0 room start는 auto-start다. host 전용 `start` 버튼은 노출하지 않는다.
6. live match 전환은 `roomState=inGame`만으로 하지 않고, Agent 1의 fresh initial game projection을 받은 뒤에만 수행한다.
7. room screen에서 상대가 나가거나 room이 닫히면 terminal dialog를 띄운 뒤 entry로 되돌린다.

### Flow C. Live Match
1. `gameEvent(gameStarted)` 뒤에 paired `gameEvent(stateSnapshot reason=gameStarted)`가 오며, live match의 최초 projection source of truth는 fresh snapshot이다.
2. 이후 `turnChanged`, `choiceRequested`, `statePatched`, `roundEnded`, `matchEnded`, room-level connection event를 조합해 같은 route 안에서 UI를 갱신한다.
3. 입력 활성 조건은 `connectionState=connected`, blocking overlay 없음, 그리고 내가 현재 행동 가능한 actor인 경우로 제한한다.
4. 선택 UI는 `phase=choicePending`이며 `choiceRequested.choiceId`와 `actorPlayerId`가 나를 가리킬 때만 노출한다.
5. 상대 disconnect는 non-blocking banner로 표시하고, 내 disconnect는 blocking reconnect overlay로 처리한다.
6. `roundEnded`는 round summary sheet를 띄우는 이벤트이고, `matchEnded`는 최종 result route 진입 이벤트다.

### Flow D. Live Match -> Reconnect Overlay -> Live Match / Result
1. 소켓 끊김이 감지되면 현재 route 위에 reconnect overlay를 띄우고 즉시 입력을 잠근다.
2. overlay 동안 마지막 authoritative board를 dim 처리한 채 유지하고, 모든 tap / drag / command 전송을 잠근다.
3. reconnect overlay의 내부 상태는 아래 3단계로 구분한다.
   - `reconnecting`: transport 재연결 대기
   - `resyncing`: `helloAck`는 성공했지만 `roomSnapshot -> gameSnapshot` 적용 대기
   - `expired`: grace period 초과 또는 resume 불가
4. reconnect success path는 `helloAck -> roomSnapshot -> gameSnapshot -> live roomEvent/gameEvent` 순서를 전제로 한다.
5. self reconnect 성공 후에도 overlay는 즉시 닫지 않고, `gameSnapshot` 적용이 끝난 뒤에만 해제한다.
6. reconnect 중 `matchEnded`가 확정되면 live match로 돌아가지 않고 result route로 바로 이동한다.
7. reconnect 실패 시 final summary가 있으면 result route로, 없으면 terminal dialog 후 entry route로 이동한다.

### Flow E. Result
1. result route는 `matchEnded` authoritative payload에서만 진입한다.
2. 최종 승패, 최종 점수, 정산 요약, 종료 사유를 보여준다.
3. Phase 0에서 rematch는 범위 밖이다. result 화면에는 `나가기`만 둔다.
4. result는 room `ended` retention 동안 재접속 조회가 가능하므로, TTL 안에서는 summary를 유지해 읽을 수 있어야 한다.
5. result 화면에서 entry로 돌아갈 때 room/session 정리 결과를 기다리지 않고 로컬 route를 먼저 닫지 않는다. authoritative `leaveAcknowledged` 또는 `roomClosed` signal을 확인한 뒤 종료한다.

## Screen Map

### 1. Multiplayer Entry
- 목적:
  - quick match / invite / resume 진입점 제공
  - persisted local session이 있으면 `이어하기` CTA 제공
  - 지난 실패 상태나 reconnect 종료 이유를 사용자 친화적으로 설명
- 주요 UI:
  - quick match CTA
  - invite room 생성 / 코드 입력 진입
  - resumable match 카드
  - last error banner 또는 dialog
- 화면 이탈 조건:
  - `helloAck` + `roomSnapshot` 수신
  - room created / joined 성공 후 room subscription 완료

### 2. Room Screen
- 목적:
  - 상대 입장 / ready / 연결 상태 확인
  - auto-start 직전 bootstrap 대기
- 주요 UI:
  - room status header
  - 2 player slots
  - ready CTA
  - leave CTA
  - start pending indicator
- 화면 이탈 조건:
  - fresh initial game projection 수신 후 live match 진입
  - `roomClosed` 또는 terminal room error 발생

### 3. Live Match Screen
- 목적:
  - player-scoped projection 렌더
  - current turn / timer / pending choice / opponent connection 상태 표시
- 주요 UI:
  - top status bar: 상대 상태, 내/상대 turn 배지, timer
  - board projection
  - bottom action area: hand, choice tray, reject toast anchor
  - non-blocking opponent disconnect banner
- 화면 이탈 조건:
  - `matchEnded`
  - fatal resume failure with no result summary

### 4. Reconnect Overlay
- 목적:
  - transport/session 재연결 진행 상황을 blocking overlay로 표시
  - 입력 잠금 및 stale input 방지
- 주요 UI:
  - dimmed board snapshot
  - spinner
  - reconnect status text
  - grace countdown
  - `나가기` 또는 `확인` CTA (`expired` 상태에서만)
- overlay 해제 조건:
  - `gameSnapshot` 적용 완료
  - terminal failure 처리 완료

### 5. Result Screen
- 목적:
  - match 종료 결과와 정산 표시
  - room 종료 제공
- 주요 UI:
  - winner/loser summary
  - final score / payout summary
  - ended reason
  - leave CTA

## Current Shell Implementation

### Implemented Placeholder Views
- `MultiplayerEntryView`
  - consumes `MultiplayerEntryShellState`
  - renders persisted resume CTA, entry action cards, entry banner
- `MultiplayerRoomView`
  - consumes `MultiplayerRoomShellState`
  - renders room header, member seats, ready/leave controls, deadline pills
- `MultiplayerLiveShellView`
  - consumes `MultiplayerLiveShellState`
  - renders top status, projection summary, hand-targeted play surface, pending choice submit tray, quit action, reject panel
- `MultiplayerReconnectOverlay`
  - consumes `MultiplayerReconnectOverlayState`
  - renders full-screen blocking reconnect status with snapshot-first sync steps
- `MultiplayerResultView`
  - consumes `MultiplayerResultShellState`
  - renders terminal summary, score rows, settlement flags, remaining integration notes
- `MultiplayerShellShowcaseView`
  - consumes `MultiplayerShellStore`
  - renders the active source route plus source-specific status pills and control buttons
- `MultiplayerMappedPayloadDemoView`
  - consumes `MultiplayerShellMappedPreview`
  - renders the same shells from Agent 1 contract payloads plus local room/hello DTO mapping
- `MultiplayerShellLabView`
  - mounts the coordinator-backed lab on the first tab and the mapped contract demo on the second tab

### Placeholder State Surface
- entry:
  - `pendingAction`
  - persisted local `roomId/sessionId/playerId/deviceId/resumeToken` summary
  - last entry banner
- room:
  - `roomId`, `roomType`, `joinPolicy`, `roomState`, `hostPlayerId`
  - `members[].{playerId, seat, role, ready, presence}`
  - `activeGameId`, deadlines, `lastRoomSequence`, optional `inviteCode`
- live:
  - `roomId`, `gameId`, `localPlayerId`, `currentPlayerId`, `phase`, `turnId`
  - `stateVersion`, `turnDeadlineAt`, `serverTime`
  - `opponentHandCount`, `localHandCount`
  - `localPlayableCardIds`
  - `pendingChoice.{isRedactedForViewer, redactionMessageKey}` plus option rows
  - `actionRejected.rejectReason` shell
- reconnect:
  - `heartbeatIntervalMs`, `disconnectTimeoutMs`, `reconnectGraceMs`
  - `graceExpiresAt`, `lastRoomSequence`, `lastAppliedStateVersion`, `lastSnapshotId`
- result:
  - `roundIndex`, `winnerPlayerId`, `loserPlayerId`, `finalScores[]`
  - `settlementSummary.{finalScore, scoreFormula, flags[]}`
  - `endReasonCode`, `endReasonMessageKey`, `forfeitingPlayerId`, `isDraw`
  - `leavePolicy.{messageKey, isEnabled}` and integration notes for unresolved adapter/localization glue

### Source-Pluggable Shell Coordinator
- `MultiplayerShellStore`
  - owns route, shell state, reconnect overlay state, and source-specific status/control metadata
  - delegates mutations to a pluggable `MultiplayerShellSource`
- `MultiplayerMockShellSource`
  - keeps preview/mock route transitions interactive without coordinator truth
  - still simulates guest join, guest ready, `gameStarted`, reconnect recovery, and result handoff for shell-only inspection
- `MultiplayerLocalDebugShellSource`
  - calls `LocalRoomCoordinatorDebugService` for `Create Room`, `Join Guest`, guest `hello` attach, `Ready`, `Guest Ready`, `Apply gameStarted`, `Disconnect`, `Resume`, and `Heartbeat`
  - derives room ready/presence/banner from `roomSnapshot` truth instead of local optimistic state
  - hides unsupported `Join Invite` in the local debug entry screen
  - uses actual `recordGameStarted` room mutation to move `starting -> inGame -> live`
  - uses a stable transient `GameManager` plus `recordMatchEndedAndFetchTerminalSummary` / `TestControlSupport.multiplayerTerminalSummaryPayload` so local debug `Apply matchEnded` enters result via authoritative terminal payload types instead of shell-only mocks
  - keeps reconnect overlay on top of the live route once the local debug flow has entered in-game mode
  - opens reconnect overlay only when the local `RoomSession.connectionState == disconnectedGrace`
  - clears reconnect overlay only after resumed room truth is applied
- `MultiplayerTransportShellSource`
  - is now a transport-backed source that can be mounted from `MP Lab > Transport` or a future product route
  - supports `MultiplayerTransportMountMode.labPreview` and `MultiplayerTransportMountMode.productPreparation(inviteCode:)`
  - `productPreparation(inviteCode:)` exposes actual `Create Room`, optional `Join Invite`, `Resume`, and authoritative `Leave` without reintroducing lab-only guest controls
  - product entry semantics now follow Agent 2 `inviteCode`; Phase 0 keeps `inviteCode == roomId`, but the UI boundary no longer advertises raw `roomId` as the user-facing join input
  - `labPreview` keeps peer `Join Guest`, local/guest `Ready`, `Apply gameStarted`, and `Apply matchEnded` controls so the websocket command path can still be exercised end-to-end
  - keeps the host store thin: peer mutations land through the server, then the host UI refreshes from authoritative `roomSnapshot` / `gameEvent` payloads only
  - routes result dismissal through `MultiplayerShellStore.sendAuthoritativeLeaveFromResult()`, and the route closes only after `leaveAcknowledged` or `roomClosed`

### Persistence and Networking Boundary
- `MultiplayerShellEnvironment`
  - injects session persistence, networking adapter, and the transport source factory into `MultiplayerShellStore`
- `MultiplayerUserDefaultsSessionPersistence`
  - persists resume metadata as UI-facing `MultiplayerPersistedSessionSummary`
  - current stored shape includes `playerId`, `deviceId`, `resumeToken`, so a future adapter source can build a real resume attach request without inventing client state
- `MultiplayerShellNetworkingAdapter`
  - defines `connect`, `resume`, `sendLeaveRoom`, `nextBufferedEvent`
  - current app shell can already build `MultiplayerShellAttachRequest` / `MultiplayerShellLeaveRoomRequest`, prime persisted resume from attach inputs, drain buffered inbound events, and route `helloAck`, `roomSnapshot`, `gameSnapshot`, `matchEnded`, `leaveAcknowledged`, `roomClosed`
  - `MultiplayerBufferedTransportAdapter` accepts Agent 2 transport envelope shape (`helloAck`, `roomSnapshot`, `gameEvent`, `roomEvent`, `terminalSummary`) and converts it into `MultiplayerShellInboundEvent`
- `MultiplayerWebSocketCommandNetworkingAdapter` is the first concrete implementation. It uses `URLSessionWebSocketTask` against `GOSTOP_MP_TRANSPORT_URL` (default `ws://127.0.0.1:9092`) and drives Agent 2 spike commands `room_create`, `room_join`, `room_transport_connect`, `room_transport_send`, `room_transport_receive`
- current create/join is intentionally mounted on the websocket command boundary first. The final REST bootstrap split is still a separate follow-up
  - `MultiplayerShellGameplayNetworkingAdapter` is now concrete on the websocket adapter and carries `playCard`, `submitChoice`, `quit` with `actionId` + `expectedStateVersion`, while still reusing the same inbound event path so duplicate replay / conflict reject semantics stay authoritative
- `MultiplayerShellStore` production entrypoints
  - `transportBacked(configuration:)` builds a store that future product navigation can mount without redoing `MP Lab`-specific wiring
  - `activateTransportSource()` switches to the production transport source without resetting the visible route
  - `persistedResumeAttachRequest()` exposes the exact `hello resume` request candidate derived from persisted metadata
  - `resumePersistedSessionOverTransport()` sends the authoritative `hello resume` attach over the adapter
  - `ingestTransportEnvelope(data/jsonObject)` lets the app shell feed Agent 2 transport envelopes straight into the store boundary
  - `sendAuthoritativeLeaveFromResult()` keeps result dismissal on the real leave lifecycle path instead of debug-only resets
  - `playCardFromLiveUI()`, `submitChoiceFromLiveUI()`, `quitMatchFromLiveUI()` let the live screen send authoritative gameplay commands without going back through debug-only control pills
  - `createRoomUsingNetworkingAdapter()`, `joinRoomUsingNetworkingAdapter()`, `setReadyUsingNetworkingAdapter()`, `recordGameStartedUsingNetworkingAdapter()`, `recordMatchEndedUsingNetworkingAdapter()` provide the app-shell lifecycle boundary that the transport source now consumes
  - room-event mapping now accepts top-level `matchEnded` / `roomClosed`, and treats local `memberLeft` as leave completion so result dismissal no longer depends on the local debug-only leave ack shim

### UI-Facing Mapper Layer
- `MultiplayerShellMapper`
  - maps Agent 1 `MultiplayerSnapshot`, `MultiplayerTurnChangedPayload`, `MultiplayerActionRejectedPayload`, `MultiplayerMatchEndedPayload`
  - maps UI-local room/session DTOs: `MultiplayerHelloAckShellPayload`, `MultiplayerRoomSnapshotPayload`, `MultiplayerReconnectContextPayload`
- `MultiplayerShellMappedPreview`
  - builds a contract-backed demo state bundle so shell rendering can be inspected without networking

### Temporary App Route Mount
- `ContentView`
  - now mounts `MultiplayerProductMultiplayerRouteView` from the main app root as a sheet, so multiplayer entry is no longer trapped inside `MP Lab`
  - still keeps `MP Lab` as a separate DEBUG-only sheet for coordinator/transport/mapped inspection
- `MultiplayerTransportRouteHostView`
  - is the product-facing host boundary for the websocket-command transport route
  - defaults to `MultiplayerTransportRouteConfiguration.productPreparation()`
  - future product navigation can mount it directly, and optionally pass a resolved `inviteCode` via `productPreparation(inviteCode:)`
- `MultiplayerProductMultiplayerRouteView`
  - is the first product-facing multiplayer entry wrapper for the shared transport host
  - accepts optional `initialInviteCode` and keeps create/join/resume on the same authoritative attach lifecycle as the lab transport route
- `MultiplayerShellLabView`
  - now exposes three tabs: `Coordinator`, `Transport`, `Mapped`
  - `Transport` now mounts the same `MultiplayerTransportRouteHostView(configuration: .lab)` that product code can reuse with a different configuration, instead of hand-building a lab-only store

### Not Implemented Yet
- final REST bootstrap split separate from the websocket command boundary
- deeper product navigation policy beyond the current root-sheet launcher
- full card-art driven hand/table interaction beyond the current `cardId` chip action surface
- missing catalog entries for `match.end.*`, `match.reject.*`, `match.result.leave.*`, `room.closed.*`, `match.choice.shake.actor_only_waiting` still use shell fallback copy when `gameText(...)` has no catalog match

## Route and Overlay State

### High-Level View State
```json
{
  "route": "entry|room|liveMatch|result",
  "overlay": "none|entryLoading|roomBlockingError|reconnectBlocking|roundSummary",
  "connectionState": "connected|reconnecting|resyncing|expired",
  "pendingEntryAction": "none|quickMatch|createInvite|joinInvite|resume",
  "inputLockReason": "none|waitingServerAck|outOfTurn|choicePendingOtherPlayer|reconnecting|resultTransition",
  "roomState": null,
  "gameState": null,
  "lastReject": null
}
```

### Input Lock Rules
- `route=entry`:
  - create/join/attach/resume pending 동안 모든 entry CTA 잠금
- `route=room`:
  - `roomState=starting` 또는 reconnect overlay 동안 ready/leave 잠금
- `route=liveMatch`:
  - 내 턴이 아니면 hand tap과 command CTA 잠금
  - `phase=choicePending`이지만 choice owner가 내가 아니면 choice tray 숨김
  - reconnect overlay가 뜨면 모든 입력 잠금
- `route=result`:
  - leave 중복 탭 방지를 위해 버튼 1회 처리 후 잠금

## Server Event -> UI Mapping

| Event | UI Effect | Route / Overlay Rule |
| --- | --- | --- |
| `helloAck` | heartbeat / reconnect policy와 resume mode 저장 | entry 유지 또는 reconnect 단계 전환 |
| `roomSnapshot` | room route seed, members/deadlines/presence 초기화 | entry -> room 가능 |
| `roomEvent.memberJoined` | room 슬롯 갱신 | room 유지 |
| `roomEvent.memberLeft` | 상대 퇴장 배너 또는 terminal dialog | room/live/result에서 처리 |
| `roomEvent.memberReadyChanged` | ready badge / CTA 상태 갱신 | room 유지 |
| `roomEvent.readyWindowExpired` | ready reset 안내 | room 유지 |
| `roomEvent.roomStateChanged` | starting / ended state 반영 | room 유지 |
| `roomEvent.playerDisconnected` | 상대면 banner, 나면 reconnect countdown state 갱신 | room/live에서 처리 |
| `roomEvent.playerReconnected` | 상대면 banner 제거, 나면 reconnect 완료 직전 상태 | overlay 자동 해제 금지 |
| `roomEvent.playerForfeited` | forfeited banner 또는 result reason 보조 정보 | live/result에서 처리 |
| `roomEvent.roomClosed` | terminal dialog 표시 후 entry 복귀 | room/result에서 처리 |
| `gameSnapshot` | full player-scoped game sync 적용 | room/live/reconnect에서 사용 |
| `gameEvent.engineEvent:gameStarted` | 최초 projection 생성 | room -> liveMatch |
| `gameEvent.engineEvent:turnChanged` | turn badge / timer / actionable state 갱신 | liveMatch 유지 |
| `gameEvent.engineEvent:choiceRequested` | choice tray 또는 modal 표시 | liveMatch 유지 |
| `gameEvent.engineEvent:actionAccepted` | 로컬 pending spinner 해제 | liveMatch 유지 |
| `gameEvent.engineEvent:actionRejected` | reject toast/dialog 표시 | route 유지 |
| `gameEvent.engineEvent:statePatched` | board projection 갱신 | liveMatch 유지 |
| `gameEvent.engineEvent:roundEnded` | round summary sheet 표시 | overlay=`roundSummary` |
| `gameEvent.engineEvent:matchEnded` | result model 생성 | liveMatch/reconnect -> result |

## Reject / Error / Reconnect UX Rules

### Command Reject Rules
| Reject Code | UX Treatment | Navigation | Notes |
| --- | --- | --- | --- |
| `outOfTurn` | 짧은 toast: "상대 턴입니다" | 없음 | action control은 계속 disabled 상태 유지 |
| `invalidPhase` | toast + stale state 안내 | 없음 | 다음 patch/snapshot 반영 대기 |
| `staleStateVersion` | toast + sync 대기 안내 | 없음 | patch 또는 snapshot을 우선 적용 |
| `invalidCard` | toast + 최신 상태 확인 안내 | 없음 | client drift 가능성 |
| `invalidChoice` | toast + choice UI 닫기 | 없음 | 새 `pendingChoice`가 오면 다시 연다 |
| `choiceExpired` | toast + countdown 종료 처리 | 없음 | stale timer 대응 |
| `choiceOwnerMismatch` | toast: "현재 선택 권한이 없습니다" | 없음 | input lock bug 감지 포인트 |
| `actionIdConflict` | generic error toast + local error log | 없음 | UI action id 재사용 버그 |
| `resumeExpired` | blocking dialog | result 또는 entry | final summary 유무에 따라 분기 |
| `gameNotResumable` | blocking dialog | result 또는 entry | ended/closed 상태와 결합 필요 |

### Room / Entry Error Rules
| Case | UX Treatment | Needed Owner |
| --- | --- | --- |
| invalid invite code | entry form inline error | Agent 2 |
| `roomFull` | entry blocking dialog | Agent 2 |
| `roomClosed` | entry blocking dialog 또는 result fallback | Agent 2 |
| `resumeTokenInvalid` | entry dialog 후 stored resume candidate 제거 | Agent 2 |
| `sessionSuperseded` | 기존 화면 종료 후 안내 dialog | Agent 2 |
| `gameSnapshotUnavailable` | retry 1회 후 fatal dialog | Agent 2 |

### Reconnect Rules
- reconnect overlay는 full-screen blocking modal로 취급한다.
- reconnect 중에는 turn timer를 authoritative countdown으로만 표시하고, local countdown 단독 추정으로 행동 가능 여부를 바꾸지 않는다.
- reconnect overlay 텍스트는 local socket 상태와 `helloAck` / `roomSnapshot` / `gameSnapshot` 진행 단계 기반으로만 바뀐다.
- 상대 disconnect는 게임을 가리지 않는다. 내 disconnect만 blocking overlay를 연다.
- overlay 해제는 `transport reconnected`가 아니라 `gameSnapshot` 적용 완료 기준이다.
- reconnect grace 만료 시 사용자가 탭하기 전에 자동 dismiss 하지 않는다. 종료 사유를 읽을 수 있게 terminal state를 유지한다.

## Payload Needs Checklist

### Entry / Resume
| Field | Why UI Needs It | Current Source | Status | Owner |
| --- | --- | --- | --- | --- |
| persisted local `roomId` / `sessionId` / `playerId` / `deviceId` / `resumeToken` | entry resume CTA와 real adapter `hello` resume 시도 | client persistence | Available Local | Agent 3 |
| `createRoom/joinRoom.room.{roomId, roomType, joinPolicy}` | room 진입 준비 및 invite/quick-match 분기 | `room_protocol.md` | Available | Agent 2 |
| `createRoom/joinRoom.session.{sessionId, resumeToken, graceExpiresAt}` | local resume candidate 저장 | `room_protocol.md` | Available | Agent 2 |
| `createRoom/joinRoom.websocket.{url, heartbeatIntervalMs, disconnectTimeoutMs, reconnectGraceMs}` | 최초 socket attach 준비 | `room_protocol.md` | Available | Agent 2 |
| `helloAck.payload.resumeMode` | fresh attach vs resume UX 구분 | `room_protocol.md` | Available | Agent 2 |
| `error.code` (`resumeTokenInvalid`, `resumeExpired`, `roomClosed`, `sessionSuperseded`) | entry terminal dialog 분기 | `room_protocol.md` | Available | Agent 2 |
| `room.inviteCode` | invite room 공유 UX와 product-facing join input | `room_protocol.md` | Available | Agent 2 |

### Room
| Field | Why UI Needs It | Current Source | Status | Owner |
| --- | --- | --- | --- | --- |
| `room.roomId` | room 화면 anchor | `room_protocol.md` | Available | Agent 2 |
| `room.roomState` | waitingForPlayers/waitingForReady/starting/inGame 분기 | `room_protocol.md` | Available | Agent 2 |
| `room.hostPlayerId` | host marker 표시 | `room_protocol.md` | Available | Agent 2 |
| `room.members[].playerId` | 내 슬롯/상대 슬롯 식별 | `room_protocol.md` | Available | Agent 2 |
| `room.members[].seat` | 좌우 슬롯 고정 배치 | `room_protocol.md` | Available | Agent 2 |
| `room.members[].role` | host/guest 배지 | `room_protocol.md` | Available | Agent 2 |
| `room.members[].ready` | ready badge 표시 | `room_protocol.md` | Available | Agent 2 |
| `room.members[].presence` | room에서도 연결 상태 표시 | `room_protocol.md` | Available | Agent 2 |
| room-layer `presence/ready` is source of truth | engine placeholder truth와 분리해 잘못된 badge를 막기 위함 | review finding `F-002` | Follow-Up | Agent 3 |
| `room.activeGameId` | room -> live match bridge | `room_protocol.md` | Available | Agent 2 |
| `room.deadlines.joinExpiresAt` / `nextReadyExpiresAt` | waiting state countdown 표시 | `room_protocol.md` | Available | Agent 2 |
| `lastRoomSequence` | room-level dedupe 및 reconnect 복원 | `room_protocol.md` | Available | Agent 2 |

### Live Match
| Field | Why UI Needs It | Current Source | Status | Owner |
| --- | --- | --- | --- | --- |
| `gameId` | route-scoped state key | `multiplayer_contract.md` | Available | Agent 1 |
| `gameStarted.initialProjection` | fresh start 직후 live match 최초 렌더 | `multiplayer_contract.md` | Available | Agent 1 |
| paired `stateSnapshot(reason=gameStarted)` | fresh start bootstrap source of truth | `multiplayer_contract.md` + `agent_sync_board.md` | Available | Agent 1 |
| `stateVersion` | resync / stale state 감지 | `multiplayer_contract.md` | Available | Agent 1 |
| `phase` | hand/choice UI 노출 규칙 | `multiplayer_contract.md` | Available | Agent 1 |
| `turnId` | turn-change animation / dedupe | `multiplayer_contract.md` | Available | Agent 1 |
| `currentPlayerId` | 내 턴/상대 턴 표시 | `multiplayer_contract.md` | Available | Agent 1 |
| `players[].hand` (self only) | 내 hand 렌더 | `multiplayer_contract.md` | Available | Agent 1 |
| `players[].handCount` | 상대 hand count UI | `multiplayer_contract.md` | Available | Agent 1 |
| viewer-scoped `pendingChoice.options[]` | non-actor에게 hidden hand metadata가 보이지 않아야 함 | review finding `F-001` | Follow-Up | Agent 1 / 3 |
| `turnChanged.turnDeadlineAt` + envelope `serverTime` | drift 없는 timer 표시 | `multiplayer_contract.md` | Available | Agent 1 |
| `pendingChoice.choiceId` | choice lifecycle 식별 | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.choiceKind` | choice surface 선택 | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.actorPlayerId` | choice owner lock | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.promptKey` | choice prompt localization | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.options[].optionCode` | submit payload | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.options[].labelKey` | 버튼 문구 localization | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.options[].cards[]` | highlight / preview 렌더 | `multiplayer_contract.md` | Available | Agent 1 |
| `choiceRequested.options[].scoreDeltaPreview` | choice 보조 힌트 | `multiplayer_contract.md` | Available | Agent 1 |
| `statePatched.patchFormat` / `baseStateVersion` / `targetStateVersion` | UI adapter 적용 전략 | `multiplayer_contract.md` | Available | Agent 1 |
| `actionRejected.rejectReason.{code, messageKey, details}` | reject toast 번역 및 stale sync 판단 | `multiplayer_contract.md` | Available | Agent 1 |

### Reconnect
| Field | Why UI Needs It | Current Source | Status | Owner |
| --- | --- | --- | --- | --- |
| socket close / open local state | overlay 1차 진입 트리거 | client transport layer | Required Local | Agent 3 |
| `helloAck.payload.{resumeMode, heartbeatIntervalMs, disconnectTimeoutMs, reconnectGraceMs, resultRetentionMs}` | reconnect overlay 문구와 timer baseline | `room_protocol.md` | Available | Agent 2 |
| `roomSnapshot` | room-level 복구 상태 적용 | `room_protocol.md` | Available | Agent 2 |
| `gameSnapshot` (`stateSnapshot`) | live match authoritative 복구 상태 적용 | `room_protocol.md` + `multiplayer_contract.md` | Available | Agent 1/2 |
| `playerDisconnected.{playerId, graceExpiresAt}` | 상대/나 disconnect 구분 및 countdown 표시 | `room_protocol.md` | Available | Agent 2 |
| `playerReconnected.{playerId, connectionId}` | banner 제거 / self resync 단계 이동 | `room_protocol.md` | Available | Agent 2 |
| `roomClosed.reason` | reconnect 실패 후 terminal dialog 문구 | `room_protocol.md` | Available | Agent 2 |
| `error.code` (`resumeExpired`, `resumeTokenInvalid`, `sessionSuperseded`, `gameSnapshotUnavailable`) | reconnect 실패 분기 | `room_protocol.md` | Available | Agent 2 |

### Result
| Field | Why UI Needs It | Current Source | Status | Owner |
| --- | --- | --- | --- | --- |
| `roundEnded.summary` | round summary sheet | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.winnerPlayerId` / `loserPlayerId` | 승패 표시 | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.finalScores[]` | 최종 점수 표시 | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.settlementSummary` | 정산 표시 | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.endReason` / `endReasonMessageKey` | timeout/disconnect/normal end 문구 | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.forfeitingPlayerId` | forfeited actor 강조 | `multiplayer_contract.md` | Available | Agent 1 |
| `matchEnded.isDraw` | draw 분기 / 문구 | `multiplayer_contract.md` | Available | Agent 1 |
| `leaveAcknowledged.messageKey` or `roomClosed.messageKey` | result dismissal 완료 copy / localization 연결 | `room_protocol.md` | Available | Agent 2 |

## Screen-Level Acceptance

### Entry
- [ ] persisted local resume candidate가 있으면 `이어하기` CTA가 보인다.
- [ ] invite / room lifecycle reject가 같은 스타일의 terminal feedback으로 정리된다.

### Room
- [ ] 상대 입장 / ready / 연결 상태가 실시간 반영된다.
- [ ] `starting` 상태에서 ready/leave control이 잠긴다.
- [ ] Phase 0에서 manual start button을 노출하지 않는다.
- [ ] live match 전환은 fresh initial game projection 기준으로만 일어난다.

### Live Match
- [ ] 내 턴 / 상대 턴 / 선택 대기 상태가 동시에 헷갈리지 않게 표시된다.
- [ ] reject toast가 route를 깨지 않는다.
- [ ] 상대 disconnect는 banner, 내 disconnect는 overlay로 구분된다.

### Reconnect Overlay
- [ ] reconnect 중 모든 입력이 잠긴다.
- [ ] overlay는 state sync 완료 후에만 닫힌다.
- [ ] grace 만료 시 종료 사유와 다음 행동이 명확하다.

### Result
- [ ] final winner / final scores / payout summary가 한 화면에서 확인된다.
- [ ] Phase 0에서 rematch CTA를 노출하지 않는다.
- [ ] result dismissal은 explicit leave ack 또는 `roomClosed` 이후에만 일어난다.

## Agent 1 / 2 Payload Requests Summary

### Agent 1
- 추가 Phase 0 payload blocker는 없다. fresh start source는 paired `gameEvent(gameStarted)` + `gameEvent(stateSnapshot reason=gameStarted)`로 잠겼다.
- coordinator tab은 이제 actual `recordGameStarted` room mutation 뒤 live route에 들어간다. 다음 단계는 그 직후 fresh live bootstrap payload를 어떤 debug/local ingress로 받을지 최종 연결하는 일이다.

### Agent 2
- invite room을 사용자에게 공유할 human-readable identifier가 필요하면 `inviteCode` shape를 정해야 한다.
- product `Leave Room`을 lab reset 대신 실제로 연결하려면 `leaveRoom`/`roomClosed` UX에 맞는 app-facing debug API 사용 순서를 잠가야 한다.

## Integration Blockers
- actual websocket client는 아직 `MultiplayerShellNetworkingAdapter`에 붙지 않았지만, adapter boundary 자체는 Agent 2 transport envelope를 `MultiplayerShellInboundEvent`로 decode할 수 있다.
- UserDefaults-backed persisted resume 저장/복구와 `hello resume` attach entrypoint는 wired 됐다. 남은 일은 product source mount와 actual socket client 연결이다.
- `ContentView`에는 debug launcher가 붙었지만, 실제 product entry/navigation policy는 아직 없다.
- coordinator tab은 `create -> guest hello -> ready -> guest ready -> gameStarted -> live -> disconnect -> resume`까지 실제 room mutation 기준으로 보이며, live bootstrap 구간 또한 transient GameManager를 통해 authoritative state를 렌더링한다.
- result dismissal policy는 now source-agnostic이다. local debug와 future transport source 모두 `leaveAcknowledged` 또는 `roomClosed` authoritative signal 기준으로만 entry로 닫힌다.
- `match.end.*`, `match.result.leave.*`, `room.closed.*`, `match.choice.shake.actor_only_waiting` localization key가 UI catalog에 아직 연결되지 않았다. 현재 UI state는 `MultiplayerResultShellState.endReasonMessageKey`, `MultiplayerResultLeavePolicy.messageKey`, `MultiplayerBannerState.messageKey`로 연결 포인트를 유지한다.

## Open Questions
- [ ] invite room share UX에서 `inviteCode`가 roomId와 다른 별도 문자열인지
- [ ] reconnect 실패 후 final summary가 없을 때 entry로 바로 보낼지 terminal intermediate screen을 둘지

## Change Log
- 2026-03-08: `entry -> room -> live match -> reconnect overlay -> result` 흐름, payload checklist, reject/error/reconnect UX rules 초안 확장
- 2026-03-08: `MultiplayerShellStore` 기반 interactive mock route host와 `MultiplayerResultView` placeholder shell을 반영하고, result payload rows를 Agent 1 terminal summary contract 기준으로 갱신
- 2026-03-08: `MultiplayerShellMapper`와 room/hello UI DTO, `MultiplayerMappedPayloadDemoView`, `ContentView` debug launcher를 추가해 contract-backed shell inspection 경로를 열었다
- 2026-03-08: `MultiplayerShellStore` 기반 interactive mock route host와 `MultiplayerResultView` placeholder shell을 반영하고, result payload rows를 Agent 1 terminal summary contract 기준으로 갱신
- 2026-03-08: Agent 1/2 최신 contract를 반영해 snapshot-first reconnect, auto-start, no-rematch, resolved payload 항목으로 재정리
- 2026-03-08: mock-friendly SwiftUI shell(`MultiplayerEntryView`, `MultiplayerRoomView`, `MultiplayerLiveShellView`, `MultiplayerReconnectOverlay`)과 placeholder state surface를 코드 기준으로 반영
- 2026-03-09: `MultiplayerShellStore`를 pluggable source로 정리하고, DEBUG `MP Lab` 첫 탭을 `LocalRoomCoordinatorDebugService` 기반 coordinator lab으로 교체했다. `Create Room`, `Join Guest`, `Ready`, `Disconnect`, `Resume`, `Heartbeat`는 실제 local debug service를 호출하며, ready/presence/banner/reconnect overlay는 room snapshot truth를 기준으로 갱신된다.
- 2026-03-09: local debug source에 guest `hello` attach, `Guest Ready`, actual `recordGameStarted` flow를 추가해 `create -> join -> ready -> start -> live -> disconnect -> resume`를 MP Lab 안에서 확인할 수 있게 했다. `Join Invite`는 local debug entry에서 숨겼고, live reconnect overlay는 actual room `.inGame` truth를 기준으로 유지된다.
- 2026-03-09: `MultiplayerLocalDebugShellSource`의 `makeLiveState`가 transient GameManager를 통한 `TestControlSupport.multiplayerLiveBootstrapPayload`를 직접 소비하도록 변경하여, live route 진입 시 mock default 대신 authoritative UI projection이 그려지도록 개선했다.
- 2026-03-10: `MultiplayerResultView`의 stale placeholder copy와 leave CTA policy를 정리하고, DEBUG coordinator lab에서 `Apply matchEnded` control이 `TestControlSupport.multiplayerTerminalSummaryPayload` 기반 authoritative terminal payload를 생성해 `showResult`로 진입하도록 연결했다.
- 2026-03-11: `MultiplayerShellStore`에 UserDefaults persistence + networking adapter boundary를 정리하고, `matchEnded -> result -> leaveRoom -> explicit leave ack or roomClosed -> entry` lifecycle를 store-level inbound event로 통일했다. shake `actorOnly` choice는 non-actor에서 option/error 대신 redacted waiting state로만 렌더되도록 mapper/UI 정책을 유지한다.
- 2026-03-11: `MultiplayerTransportShellSource`와 `MultiplayerBufferedTransportAdapter`를 추가해 persisted resume가 future source에서 실제 `hello resume` attach로 이어질 code path를 고정했다. Agent 2 transport envelope(`helloAck`, `roomSnapshot`, `gameEvent`, `roomEvent`, `terminalSummary`)는 now shell inbound path로 decode 가능하다.
- 2026-03-11: `MultiplayerWebSocketCommandNetworkingAdapter`를 추가해 `MP Lab > Transport`가 Agent 2 websocket command server를 실제로 사용하게 했다. create / peer join / ready / gameStarted / matchEnded / resume / leave는 now `room_create`, `room_join`, `room_transport_connect/send/receive`를 타고, result dismissal은 local `memberLeft` 또는 `roomClosed` authoritative signal에만 반응한다. message key rendering은 `gameText(...)` fallback을 통과한다.
- 2026-03-11: store에 `activateTransportSource()`, `persistedResumeAttachRequest()`, `resumePersistedSessionOverTransport()`, `ingestTransportEnvelope(data/jsonObject)`, `sendAuthoritativeLeaveFromResult()`를 추가해 app shell이 adapter instance 세부사항 없이 production transport 경계를 직접 사용할 수 있게 했다. `room.closed.*`와 `match.result.leave.*`는 `MultiplayerBannerState.messageKey`와 `MultiplayerResultLeavePolicy.messageKey`로 남긴다.
