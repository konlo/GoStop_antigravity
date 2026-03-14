# Multiplayer Contract

## Meta
- **Owner**: Agent 1
- **Primary Consumers**: Agent 2, Agent 3, Agent 4
- **Status**: Phase 0 Final Sign-Off
- **Last Updated**: 2026-03-14
- **Related Docs**:
  - `room_protocol.md`
  - `multiplayer_ui_flow.md`
  - `multiplayer_test_scenarios.md`
  - `agent_sync_board.md`

## Goal
- 온라인 맞고 멀티플레이에서 authoritative engine이 보장해야 하는 state, command, event 계약을 고정한다.
- 룰 판정은 이 문서를 기준으로 단일 구현을 유지한다.

## Scope
- match/game state schema
- command validation rules
- event schema
- choice payload contract
- reject reason/error code
- stateVersion / event ordering
- snapshot / replay contract

## Non-Goals
- room/lobby/session lifecycle 상세
- iOS 화면 레이아웃
- test runner 구현 상세

## Phase 0 Shipped Boundary
- shipped bootstrap boundary:
  - `room_bootstrap_create`
  - `room_bootstrap_lookup_invite`
  - `room_bootstrap_join`
  - `room_bootstrap_prepare_game_start`
- shipped bootstrap authority source:
  - canonical pair `gameStarted` + paired `stateSnapshot(reason=gameStarted)`
  - typed baseline `MultiplayerGameStartedBootstrapPayload`
- shipped live gap recovery boundary:
  - `triggerGapRecovery -> gapRecoveryHint -> gameEvent(stateSnapshot reason=gapDetected)`
- shipped boundary drift ruling:
  - Agent 2/4 artifact가 위 shipped boundary와 다르면 contract ambiguity가 아니라 implementation drift로 본다.

## Deferred Backlog Beyond Phase 0
- true public REST bootstrap split
- automatic dropped-event detection instead of explicit live gap hook

## Final Sign-Off
- round17 final-validation locked set(`MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`)이 green이고, shipped Phase 0 boundary 안에서 authority contract drift는 관찰되지 않았다.
- final sign-off 기준 artifact root는 `test_artifacts/multiplayer/round17_final_validation/socket_compare/`이며, TCP/WebSocket compare parity와 CLI smoke가 모두 shipped boundary 판단과 일치해야 한다.
- shipped scope 바깥 요구사항이 artifact에 나타나면 blocker가 아니라 deferred backlog 또는 implementation drift로 분류한다.

## Key Decisions

| Topic | Current Decision | Owner | Status | Notes |
| --- | --- | --- | --- | --- |
| authoritative source | Server-side engine | Agent 1 | Locked | Client is render-only for rule decisions |
| `stateVersion` increment unit | accepted command transaction that mutates game state | Agent 1 | Locked | one accepted mutation = one version bump |
| `eventId` ordering | monotonic per `gameId`, unique per emitted event | Agent 1 | Locked | ordering is `eventId`, grouping is via `causedByActionId` |
| duplicate `actionId` policy | exact duplicate replays prior result, conflicting reuse rejects | Agent 1 | Locked | avoids double-apply on retry |
| choice command shape | server issues `choiceId` + `optionCode`; client echoes them back | Agent 1 | Locked | client must not recompute rule options |
| choice visibility | `pendingChoice` options are viewer-scoped and must not leak hidden hand info to non-actor clients | Agent 1 | Locked | `askingShake` is `actorOnly` and redacted for non-actor viewers |
| sync transport | full player-scoped snapshot + RFC 6902 JSON Patch delta | Agent 1 | Locked | snapshot on start/resume/resync, patch during live play |
| replay baseline | authority-scope snapshot + ordered authoritative event stream | Agent 1 | Locked | player-scoped payload is not sufficient for replay |
| hidden information policy | player-scoped projection | Agent 1 | Locked | opponent hand / deck hidden from normal clients |
| presence/ready ownership | `isConnected` / `isReady` truth belongs to room/session layer, not hardcoded engine defaults | Agent 1 | Locked | engine snapshot accepts optional room-truth merge and otherwise returns `null` + `presenceSource=unknown` |
| starter/dealer payload | bootstrap/snapshot starter-related fields must reflect actual starter selection result | Agent 1 | Locked | `starterPlayerId` is explicit and `dealerPlayerId` follows the same starter result in current engine |
| `playerId` ownership | engine/game payloads use authority `playerId` only; room/session layer owns room-to-authority mapping | Agent 1 | Locked | room transport must resolve ingress identity and expose binding metadata to clients |
| live stale recovery reason | stale `expectedStateVersion` recovery snapshot reason is always `resync` | Agent 1 | Locked | `localPreview` is local helper-only and must not appear on live transport recovery |

## Swift Type Mapping

| Contract Concept | Swift Type |
| --- | --- |
| command envelope | `MultiplayerCommandEnvelope` |
| command body | `MultiplayerCommand` |
| event envelope | `MultiplayerEventEnvelope<Payload>` |
| game-started payload | `MultiplayerGameStartedPayload` |
| reject reason | `MultiplayerRejectReason` |
| choice payload | `MultiplayerChoice` |
| choice kind | `MultiplayerContractChoiceKind` |
| choice visibility | `MultiplayerChoiceVisibility` |
| quit reason | `MultiplayerQuitReason` |
| duplicate `actionId` disposition | `MultiplayerDuplicateActionIdDisposition` |
| patch payload | `MultiplayerPatch` |
| snapshot payload | `MultiplayerSnapshot` |
| recovery snapshot reason | `MultiplayerRecoverySnapshotReason` |
| projection context | `MultiplayerProjectionContext` |
| participant presence merge | `MultiplayerParticipantPresence` |
| player identity binding | `MultiplayerPlayerIdentityBinding` |
| presence source | `MultiplayerPresenceSource` |
| match snapshot | `MultiplayerMatchSnapshot` |
| player projection | `MultiplayerPlayerProjection` |
| card summary | `MultiplayerCardSummary` |
| round-ended payload | `MultiplayerRoundEndedPayload` |
| round summary | `MultiplayerRoundSummary` |
| match-ended payload | `MultiplayerMatchEndedPayload` |
| match end reason | `MultiplayerMatchEndReason` |
| settlement summary | `MultiplayerSettlementSummary` |

## Engine Invariants
- 룰 판정은 엔진에서만 수행한다.
- 같은 authority snapshot + 같은 accepted command sequence는 항상 같은 결과를 낸다.
- 현재 턴이 아닌 플레이어 액션은 reject 한다.
- 허용되지 않은 choice code는 reject 한다.
- 동일 `actionId`는 절대 두 번 mutate 되지 않는다.
- player-scoped projection은 hidden information 규칙을 절대 깨지 않는다.

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

## Ordering And Idempotency

### `stateVersion`
- `stateVersion`은 authoritative game state의 client-visible mutation version이다.
- accepted command 중 실제 game state를 바꾸는 경우에만 정확히 1 증가한다.
- 한 command가 여러 event를 발생시켜도 그 event들은 동일한 `stateVersion`을 공유한다.
- `actionRejected`, duplicate replay, resume sync 자체는 `stateVersion`을 증가시키지 않는다.
- 최초 deal이 완료되어 client가 게임을 볼 수 있게 되는 시점의 snapshot을 `stateVersion = 1`로 본다.

### `eventId`
- `eventId`는 `gameId` 내부에서 단조 증가하는 서버 발급 ID다.
- emitted game event마다 새 `eventId`가 발급된다.
- ordering 비교는 `(gameId, eventId)`로 충분해야 한다.
- 같은 `eventId`를 다시 받으면 consumer는 중복 delivery로 간주하고 무시해야 한다.

### Duplicate `actionId`
- 같은 `actionId` + 같은 `playerId` + 같은 command body가 재전송되면, 서버는 기존 terminal result를 replay 한다.
- replay 시 기존에 발급된 `eventId`들을 그대로 재전송할 수 있다. consumer는 `eventId` idempotency로 중복 적용을 막아야 한다.
- 같은 `actionId`를 다른 command body로 재사용하면 `actionIdConflict` reject를 반환한다.
- duplicate `actionId` resolution은 `staleStateVersion` 판단보다 먼저 일어난다. exact duplicate resend는 current authoritative head가 더 앞서 있어도 `exactReplay`여야 하고, `staleStateVersion` + `stateSnapshot(reason=resync)`로 downgrade되면 안 된다.
- conflicting reuse는 `actionIdConflict` reject여야 한다. conflicting reuse가 `staleStateVersion` reject나 `resync` recovery path로 빠지면 implementation drift다.
- contract owner artifact ruling:
  - exact resend artifact가 `duplicateActionIdDisposition=exactReplay` + prior authoritative `eventId` replay가 아니면 implementation drift다
  - conflicting reuse artifact가 `actionRejected(code=actionIdConflict)`가 아니면 implementation drift다

## Match State Model

### Top-Level State
```json
{
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "engineVersion": "gostop-core@2026.03.08",
  "ruleConfigVersion": "rules_2026_03_08",
  "stateVersion": 12,
  "lastEventId": "evt_000124",
  "phase": "inTurn",
  "turnId": "turn_0007",
  "currentPlayerId": "player_a",
  "dealerPlayerId": "player_b",
  "starterPlayerId": "player_b",
  "players": [],
  "table": {
    "cards": [],
    "monthBuckets": {}
  },
  "deck": {
    "remainingCount": 18
  },
  "pendingChoice": null,
  "scoreboard": {
    "roundIndex": 1,
    "playerScores": [],
    "winnerPlayerId": null
  },
  "timers": {
    "turnDeadlineAt": "2026-03-08T15:30:16+09:00",
    "choiceDeadlineAt": null
  },
  "resume": {
    "isResumable": true,
    "graceDeadlineAt": "2026-03-08T15:35:16+09:00"
  }
}
```

### Player Projection
```json
{
  "playerId": "player_a",
  "seatIndex": 0,
  "name": "Player 1",
  "hand": [
    {
      "cardId": "card_03_ribbon_red_poem",
      "month": 3,
      "kind": "ribbon",
      "imageIndex": 0,
      "selectedRole": null
    }
  ],
  "handCount": 7,
  "captured": {
    "bright": [],
    "animal": [],
    "ribbon": [],
    "junk": []
  },
  "score": 6,
  "money": 10600,
  "goCount": 1,
  "shakeCount": 0,
  "isConnected": true,
  "isReady": true,
  "presenceSource": "roomSnapshot",
  "isViewer": true
}
```

### Hidden Information Rules
- 플레이어 본인 `hand`만 full payload로 전달한다.
- 상대 hand는 `handCount`만 전달하고 card identity는 숨긴다.
- `askingShake`는 non-actor viewer에게 raw hand card metadata를 절대 보내지 않는다.
- deck ordering과 next draw identity는 normal client에 절대 노출하지 않는다.
- replay / debug artifact는 `authority` scope에서만 full state를 허용한다.

### Presence Merge Rules
- `isConnected` / `isReady`는 engine이 authoritative truth를 갖지 않는다.
- room/session layer가 truth source이며, engine projection은 optional merge slot만 제공한다.
- room truth가 merge되지 않은 projection에서는 `isConnected = null`, `isReady = null`, `presenceSource = "unknown"`을 사용한다.
- room truth를 merge한 projection에서는 `presenceSource = "roomSnapshot"`을 사용한다.

## Lifecycle Phases
- `waiting`
- `dealing`
- `inTurn`
- `choicePending`
- `roundEnded`
- `matchEnded`
- `paused`

## Command Contract

### Envelope
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000041",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000041",
  "expectedStateVersion": 12,
  "sentAt": "2026-03-08T15:30:01+09:00",
  "command": {
    "name": "playCard",
    "payload": {}
  }
}
```

### Command Rules
- `expectedStateVersion`은 client가 알고 있는 latest state를 보낸다. 서버는 reject payload에 latest version을 포함해 drift를 드러낸다.
- `playCard`만 card identity를 직접 보낸다.
- `selectCapture`, `selectShake`, `chooseGoStop`, `chooseChrysanthemumRole`는 반드시 server-issued `choiceId`와 `optionCode`를 보낸다.
- `resume`은 sync command이며, game state를 mutate하지 않아도 된다.
- command success는 direct response보다 event stream이 source of truth다. transport layer ack shape는 Agent 2가 감싼다.

### Transport Relay Rules
- room/websocket transport layer는 gameplay relay command로 `playCard`, `submitChoice`, `quit`를 받을 수 있다.
- `submitChoice`는 transport convenience alias이며 engine command가 아니다. transport layer는 `choiceCommandName`을 보고 이를 `selectCapture`, `selectShake`, `chooseGoStop`, `chooseChrysanthemumRole` 중 하나로 확정해서 engine에 넘겨야 한다.
- `submitChoice.payload` minimum fields는 `choiceCommandName`, `choiceId`, `optionCode`다.
- transport relay는 `actionId`, `expectedStateVersion`, `playerId`, `gameId`, command payload를 engine command envelope로 손실 없이 전달해야 한다.
- room transport ingress identity source of truth는 client payload의 `playerId`가 아니라 authenticated room session과 `playerIdentityBindings`다. room layer는 client-supplied `playerId`를 그대로 신뢰하지 않고, room `playerId -> authority playerId` mapping을 거친 뒤 engine command envelope를 만들어야 한다.
- `MultiplayerCommandEnvelope.playerId`는 room lookup이 끝난 뒤의 authority `playerId`다. room-owned session/member identity field는 engine contract 바깥에 있고, transport layer가 별도로 관리한다.
- relay success/failure source of truth는 room ack가 아니라 nested engine event(`gameEvent.payload.engineEvent`)다.
- accepted gameplay relay baseline은 `actionAccepted -> statePatched|stateSnapshot -> semantic follow-up` ordered engine events다.
- stale `expectedStateVersion` reject path는 `actionRejected(code=staleStateVersion)` 뒤에 같은 websocket stream에서 `stateSnapshot(reason=resync)` recovery pair를 이어서 받아야 한다.
- live stale-version recovery snapshot reason은 `resync`만 허용된다. `localPreview`는 local bridge / debug preview helper에서만 허용되며 live room/game transport에서는 사용할 수 없다.
- passive socket close / transport teardown은 engine command가 아니라 room-owned disconnect signal이다. passive close 감지 자체는 engine `actionAccepted` / `actionRejected` / `stateSnapshot`을 만들지 않고, room layer disconnect tracking으로만 들어가야 한다.
- explicit `room_transport_send(action=disconnect)`와 passive socket close는 disconnect tracking 이후 동일한 downstream authority path를 공유해야 한다. reconnect grace expiry가 실제 terminal closure를 만들 때는 두 path 모두 `quit(reason=disconnectTimeout)` same authority transaction으로 수렴해야 한다.
- server-owned timeout sweep / automatic expiry timer도 동일한 room-owned trigger다. manual `reapExpiredState`, passive close grace expiry, runtime timer sweep 중 어떤 경로가 timeout completion을 시작하더라도 engine-visible terminal transaction은 같은 `quit(reason=disconnectTimeout)` authority path여야 한다.
- stale heartbeat / pong / ack는 engine command가 아니라 room-owned liveness signal이다. replaced/expired/mismatched connection에서 온 stale heartbeat는 explicit room-level reject(`staleConnectionId` 또는 `invalidResumeState`)가 source-of-truth고, audit log는 additive-only다.
- stale heartbeat handling은 `actionRejected`, `stateSnapshot`, `roundEnded`, `matchEnded` 같은 engine envelope를 emit하거나 `stateVersion`을 바꾸면 안 된다. silent audit-only로 내려버리는 것도 contract drift다.

### Commands
| Command | Actor | Preconditions | Success Output | Common Rejects |
| --- | --- | --- | --- | --- |
| `playCard` | current player | `phase=inTurn`, actor is turn owner, `cardId` in actor hand | `actionAccepted` + `statePatched` or `stateSnapshot` + follow-up semantic events | `outOfTurn`, `invalidPhase`, `invalidCard`, `staleStateVersion`, `actionIdConflict` |
| `selectCapture` | choice owner | `phase=choicePending`, `choiceKind=capture` | accepted choice + patch + turn/score follow-up | `invalidChoice`, `choiceExpired`, `choiceOwnerMismatch`, `staleStateVersion`, `actionIdConflict` |
| `selectShake` | choice owner | `phase=choicePending`, `choiceKind=shake` | accepted choice + patch + turn/score follow-up | `invalidChoice`, `choiceExpired`, `choiceOwnerMismatch`, `staleStateVersion`, `actionIdConflict` |
| `chooseGoStop` | choice owner | `phase=choicePending`, `choiceKind=goStop` | accepted choice + patch + round/match follow-up | `invalidChoice`, `choiceExpired`, `choiceOwnerMismatch`, `staleStateVersion`, `actionIdConflict` |
| `chooseChrysanthemumRole` | choice owner | `phase=choicePending`, `choiceKind=chrysanthemumRole` | accepted choice + patch + capture/score follow-up | `invalidChoice`, `choiceExpired`, `choiceOwnerMismatch`, `staleStateVersion`, `actionIdConflict` |
| `resume` | disconnected player | resumable game exists, valid resume context | `stateSnapshot` with current projection and sync metadata | `resumeExpired`, `gameNotResumable`, `notParticipant` |
| `quit` | room member or active participant | room/game permits leave | `matchEnded` or room-level leave handoff | `invalidState`, `notParticipant`, `actionIdConflict` |

### `quit.reason`
- `voluntaryExit`
- `disconnectTimeout`
- `adminForfeit`
- reconnect grace expiry는 별도 admin-forfeit command를 만들지 않고 room layer가 `quit(reason=disconnectTimeout)`를 authoritative engine command로 전달한다.

### Command Sample Payloads

#### `playCard`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000041",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000041",
  "expectedStateVersion": 12,
  "command": {
    "name": "playCard",
    "payload": {
      "cardId": "card_03_ribbon_red_poem",
      "source": "hand"
    }
  }
}
```

#### `selectCapture`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000042",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000042",
  "expectedStateVersion": 13,
  "command": {
    "name": "selectCapture",
    "payload": {
      "choiceId": "choice_0007",
      "optionCode": "capture_pair_left"
    }
  }
}
```

#### `selectShake`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000043",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000043",
  "expectedStateVersion": 18,
  "command": {
    "name": "selectShake",
    "payload": {
      "choiceId": "choice_0010",
      "optionCode": "shake_yes"
    }
  }
}
```

#### `chooseGoStop`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000044",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000044",
  "expectedStateVersion": 23,
  "command": {
    "name": "chooseGoStop",
    "payload": {
      "choiceId": "choice_0014",
      "optionCode": "go"
    }
  }
}
```

#### `resume`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000045",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_resume_0001",
  "expectedStateVersion": 23,
  "command": {
    "name": "resume",
    "payload": {
      "resumeToken": "resume_tok_abc123",
      "lastKnownEventId": "evt_000210",
      "lastKnownStateVersion": 23
    }
  }
}
```

#### `quit`
```json
{
  "type": "command",
  "traceId": "trace_001",
  "requestId": "req_000046",
  "roomId": "room_001",
  "gameId": "game_001",
  "playerId": "player_a",
  "actionId": "act_000046",
  "expectedStateVersion": 23,
  "command": {
    "name": "quit",
    "payload": {
      "reason": "voluntaryExit"
    }
  }
}
```

### Relay-Ready Gameplay Samples

#### `playCard` via `room_transport_send`
Request:
```json
{
  "action": "room_transport_send",
  "payload": {
    "roomId": "room_001",
    "connectionId": "conn_host_001",
    "message": {
      "type": "command",
      "traceId": "trace_001",
      "requestId": "req_000041",
      "roomId": "room_001",
      "gameId": "game_001",
      "playerId": "player_a",
      "actionId": "act_000041",
      "expectedStateVersion": 12,
      "command": {
        "name": "playCard",
        "payload": {
          "cardId": "card_03_ribbon_red_poem",
          "source": "hand"
        }
      }
    }
  }
}
```
Success relay sequence:
```json
[
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 41,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionAccepted",
        "eventId": "evt_000211",
        "stateVersion": 13,
        "causedByActionId": "act_000041",
        "payload": {
          "requestId": "req_000041",
          "actionId": "act_000041",
          "playerId": "player_a",
          "commandName": "playCard",
          "result": {
            "playedCardId": "card_03_ribbon_red_poem",
            "pendingChoiceCreated": true,
            "turnContinues": true
          }
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 42,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "statePatched",
        "eventId": "evt_000212",
        "stateVersion": 13,
        "causedByActionId": "act_000041",
        "payload": {
          "patchFormat": "json-patch",
          "baseStateVersion": 12,
          "targetStateVersion": 13,
          "ops": [
            {
              "op": "replace",
              "path": "/pendingChoice",
              "value": {
                "choiceId": "choice_0007",
                "choiceKind": "capture"
              }
            }
          ]
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 43,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "choiceRequested",
        "eventId": "evt_000213",
        "stateVersion": 13,
        "causedByActionId": "act_000041",
        "payload": {
          "choiceId": "choice_0007",
          "choiceKind": "capture",
          "actorPlayerId": "player_a"
        }
      }
    }
  }
]
```
Failure relay:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 41,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "actionRejected",
      "eventId": "evt_000212",
      "stateVersion": 12,
      "causedByActionId": "act_000041",
      "payload": {
        "requestId": "req_000041",
        "actionId": "act_000041",
        "playerId": "player_a",
        "commandName": "playCard",
        "rejectReason": {
          "code": "outOfTurn",
          "retryable": false,
          "messageKey": "match.reject.out_of_turn",
          "details": {
            "currentPlayerId": "player_b",
            "phase": "inTurn",
            "turnId": "turn_0008",
            "latestStateVersion": 12
          }
        }
      }
    }
  }
}
```

#### `submitChoice` via `room_transport_send`
Request:
```json
{
  "action": "room_transport_send",
  "payload": {
    "roomId": "room_001",
    "connectionId": "conn_host_001",
    "message": {
      "type": "command",
      "traceId": "trace_001",
      "requestId": "req_000042",
      "roomId": "room_001",
      "gameId": "game_001",
      "playerId": "player_a",
      "actionId": "act_000042",
      "expectedStateVersion": 13,
      "command": {
        "name": "submitChoice",
        "payload": {
          "choiceCommandName": "selectCapture",
          "choiceId": "choice_0007",
          "optionCode": "capture_pair_left"
        }
      }
    }
  }
}
```
Success relay sequence:
```json
[
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 44,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionAccepted",
        "eventId": "evt_000214",
        "stateVersion": 14,
        "causedByActionId": "act_000042",
        "payload": {
          "requestId": "req_000042",
          "actionId": "act_000042",
          "playerId": "player_a",
          "commandName": "selectCapture"
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 45,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "statePatched",
        "eventId": "evt_000215",
        "stateVersion": 14,
        "causedByActionId": "act_000042",
        "payload": {
          "patchFormat": "json-patch",
          "baseStateVersion": 13,
          "targetStateVersion": 14,
          "ops": [
            {
              "op": "replace",
              "path": "/pendingChoice",
              "value": null
            },
            {
              "op": "replace",
              "path": "/currentPlayerId",
              "value": "player_b"
            }
          ]
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 46,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "turnChanged",
        "eventId": "evt_000216",
        "stateVersion": 14,
        "causedByActionId": "act_000042",
        "payload": {
          "turnId": "turn_0008",
          "currentPlayerId": "player_b",
          "turnDeadlineAt": "2026-03-08T15:30:31+09:00"
        }
      }
    }
  }
]
```
Failure relay:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 44,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "actionRejected",
      "eventId": "evt_000217",
      "stateVersion": 13,
      "causedByActionId": "act_000042",
      "payload": {
        "requestId": "req_000042",
        "actionId": "act_000042",
        "playerId": "player_a",
        "commandName": "selectCapture",
        "rejectReason": {
          "code": "choiceOwnerMismatch",
          "retryable": false,
          "messageKey": "match.reject.choice_owner_mismatch",
          "details": {
            "choiceId": "choice_0007",
            "actorPlayerId": "player_b",
            "latestStateVersion": 13
          }
        }
      }
    }
  }
}
```

#### `quit` via `room_transport_send`
Request:
```json
{
  "action": "room_transport_send",
  "payload": {
    "roomId": "room_001",
    "connectionId": "conn_host_001",
    "message": {
      "type": "command",
      "traceId": "trace_001",
      "requestId": "req_000046",
      "roomId": "room_001",
      "gameId": "game_001",
      "playerId": "player_a",
      "actionId": "act_000046",
      "expectedStateVersion": 23,
      "command": {
        "name": "quit",
        "payload": {
          "reason": "voluntaryExit"
        }
      }
    }
  }
}
```
Success relay sequence:
```json
[
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 57,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionAccepted",
        "eventId": "evt_000217",
        "stateVersion": 24,
        "causedByActionId": "act_000046",
        "payload": {
          "requestId": "req_000046",
          "actionId": "act_000046",
          "playerId": "player_a",
          "commandName": "quit"
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 58,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "matchEnded",
        "eventId": "evt_000218",
        "stateVersion": 24,
        "causedByActionId": "act_000046",
        "payload": {
          "roundIndex": 1,
          "winnerPlayerId": "player_b",
          "loserPlayerId": "player_a",
          "finalScores": [
            {
              "playerId": "player_b",
              "score": 5,
              "goCount": 0,
              "money": 10000
            },
            {
              "playerId": "player_a",
              "score": 2,
              "goCount": 0,
              "money": 10000
            }
          ],
          "settlementSummary": null,
          "endReason": "voluntaryQuit",
          "endReasonMessageKey": "match.end.voluntary_quit",
          "forfeitingPlayerId": "player_a",
          "isDraw": false
        }
      }
    }
  }
]
```
Failure relay:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 57,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "actionRejected",
      "eventId": "evt_000219",
      "stateVersion": 23,
      "causedByActionId": "act_000046",
      "payload": {
        "requestId": "req_000046",
        "actionId": "act_000046",
        "playerId": "player_a",
        "commandName": "quit",
        "rejectReason": {
          "code": "invalidState",
          "retryable": false,
          "messageKey": "match.reject.invalid_state",
          "details": {
            "phase": "matchEnded",
            "latestStateVersion": 23
          }
        }
      }
    }
  }
}
```
- terminal consumer baseline은 success sequence 중 `matchEnded`다. room layer는 같은 terminal transaction에서 별도 `terminalSummary`를 fan-out할 수 있지만, result route의 game-engine source of truth는 `matchEnded`다.
- reconnect grace expiry는 same authority path의 `quit(reason=disconnectTimeout)`로 처리한다. room layer가 이 command를 synthetic emit 하더라도, engine-visible actor와 terminal authority fields는 모두 forfeiting authority `playerId`를 유지해야 한다.

### Duplicate `actionId` Websocket Parity Samples

#### Exact Duplicate Resend (`duplicateActionIdDisposition=exactReplay`)
Request:
```json
{
  "action": "room_transport_send",
  "payload": {
    "roomId": "room_001",
    "connectionId": "conn_host_001",
    "message": {
      "type": "command",
      "traceId": "trace_001",
      "requestId": "req_000041_retry",
      "roomId": "room_001",
      "gameId": "game_001",
      "playerId": "room_host_001",
      "actionId": "act_000041",
      "expectedStateVersion": 15,
      "command": {
        "name": "playCard",
        "payload": {
          "cardId": "card_03_ribbon_red_poem",
          "source": "hand"
        }
      }
    }
  }
}
```
Transport diagnostic:
```json
{
  "type": "ack",
  "roomId": "room_001",
  "payload": {
    "requestId": "req_000041_retry",
    "actionId": "act_000041",
    "duplicateActionIdDisposition": "exactReplay"
  }
}
```
Authoritative replay sequence:
```json
[
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 41,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionAccepted",
        "eventId": "evt_000211",
        "stateVersion": 13,
        "causedByActionId": "act_000041",
        "payload": {
          "requestId": "req_000041",
          "actionId": "act_000041",
          "playerId": "player_a",
          "commandName": "playCard"
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 42,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "statePatched",
        "eventId": "evt_000212",
        "stateVersion": 13,
        "causedByActionId": "act_000041",
        "payload": {
          "patchFormat": "json-patch",
          "baseStateVersion": 12,
          "targetStateVersion": 13
        }
      }
    }
  }
]
```
- room/client가 보내는 `playerId` echo는 room identity일 수 있지만, replayed nested engine payload의 `playerId`는 authority identity를 유지한다. client는 `playerIdentityBindings`로 이 둘을 연결해야 한다.

#### Conflicting Reuse (`duplicateActionIdDisposition=conflictReject`)
Request:
```json
{
  "action": "room_transport_send",
  "payload": {
    "roomId": "room_001",
    "connectionId": "conn_host_001",
    "message": {
      "type": "command",
      "traceId": "trace_001",
      "requestId": "req_000041_conflict",
      "roomId": "room_001",
      "gameId": "game_001",
      "playerId": "room_host_001",
      "actionId": "act_000041",
      "expectedStateVersion": 15,
      "command": {
        "name": "playCard",
        "payload": {
          "cardId": "card_08_bright_fullmoon",
          "source": "hand"
        }
      }
    }
  }
}
```
Transport diagnostic:
```json
{
  "type": "ack",
  "roomId": "room_001",
  "payload": {
    "requestId": "req_000041_conflict",
    "actionId": "act_000041",
    "duplicateActionIdDisposition": "conflictReject"
  }
}
```
Authoritative reject:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 44,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "actionRejected",
      "eventId": "evt_000214",
      "stateVersion": 15,
      "causedByActionId": "act_000041",
      "payload": {
        "requestId": "req_000041_conflict",
        "actionId": "act_000041",
        "playerId": "player_a",
        "commandName": "playCard",
        "rejectReason": {
          "code": "actionIdConflict",
          "retryable": false,
          "messageKey": "match.reject.action_id_conflict",
          "details": {
            "latestStateVersion": 15,
            "originalCommandName": "playCard"
          }
        }
      }
    }
  }
}
```
- conflict reject 뒤에는 `stateSnapshot(reason=resync)` recovery pair가 오지 않는다. `staleStateVersion`/`resync`로 떨어지면 contract drift다.
- Agent 2/4가 live parity artifact를 가져오면 above two cases를 source-of-truth로 판정한다. TCP/WebSocket 차이와 무관하게 이 분류가 우선이다.

## Reject Reason Contract

### Shape
```json
{
  "rejectReason": {
    "code": "invalidChoice",
    "retryable": false,
    "messageKey": "match.reject.invalid_choice",
    "details": {
      "phase": "choicePending",
      "choiceId": "choice_0007",
      "receivedOptionCode": "capture_pair_right",
      "latestStateVersion": 13
    }
  }
}
```

### Codes
| Code | Meaning | Retryable | Notes |
| --- | --- | --- | --- |
| `outOfTurn` | 현재 턴 플레이어가 아님 | No | includes current owner in details |
| `invalidPhase` | 현재 phase에서 허용되지 않음 | No | stale UI or wrong command route |
| `staleStateVersion` | client expected version이 최신 상태와 다름 | Yes | client should request or wait for sync |
| `invalidCard` | actor hand 기준 유효하지 않은 카드 | No | likely state drift or malformed request |
| `invalidChoice` | `choiceId` 또는 `optionCode`가 현재 pending choice와 맞지 않음 | No | client must not compute choices locally |
| `choiceExpired` | pending choice가 이미 해소되었거나 만료됨 | No | newer state already applied |
| `choiceOwnerMismatch` | choice owner가 아닌 플레이어가 응답함 | No | input lock bug or malicious request |
| `actionIdConflict` | 이미 사용한 `actionId`를 다른 body로 재사용함 | No | protocol violation |
| `notParticipant` | 현재 room/game participant가 아님 | No | stale session |
| `resumeExpired` | reconnect grace period 초과 | No | forfeit policy is room-layer concern |
| `gameNotResumable` | resume 가능한 active game이 아님 | No | game ended or room closed |
| `invalidState` | quit/resume 등 lifecycle command가 현재 상태와 맞지 않음 | No | room/game lifecycle mismatch |

### Typed Reject / Resync Details
- `staleStateVersion` reject details baseline type은 `MultiplayerStaleStateVersionRejectDetails`다.
- `MultiplayerResyncDirective.snapshotReason` type은 `MultiplayerRecoverySnapshotReason`이며 allowed value set은 `resync | gapDetected`로 제한한다.
- required fields:
  - `expectedStateVersion`
  - `authoritativeStateVersion`
  - `authoritativeEventId`
  - `resync.trigger`
  - `resync.snapshotReason`
  - `resync.shouldLockInput`
- `resync.snapshotReason`은 command stale reject path에서는 `resync`로 고정한다.
- `localPreview`는 `MultiplayerSnapshot.reason`에서는 local helper 용도로 허용되지만, reject/recovery detail의 `resync.snapshotReason`에는 절대 쓰지 않는다.
- `gapDetected`는 client가 patch base mismatch 또는 missing game event를 감지한 transport/local recovery path에만 사용한다. command stale reject의 recovery reason으로는 쓰지 않는다.
- MP-008 P0 deterministic hook은 transport drop이 아니라 stale `expectedStateVersion` override를 사용한다.
- MP-008 artifact minimum fields는 `injectedMismatchMode`, `clientStateVersion`, `expectedStateVersion`, `authoritativeStateVersion`, `authoritativeEventId`, `recoverySnapshotReason`, `recoverySnapshotId`다.

## Event Contract

### Envelope
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000124",
  "stateVersion": 13,
  "causedByActionId": "act_000041",
  "serverTime": "2026-03-08T15:30:01+09:00",
  "eventName": "statePatched",
  "payload": {}
}
```

### Event Ordering
- accepted mutation command의 canonical emission order:
  1. `actionAccepted`
  2. `statePatched` 또는 `stateSnapshot`
  3. semantic follow-up event 0개 이상 (`choiceRequested`, `turnChanged`, `roundEnded`, `matchEnded`)
- reject command는 `actionRejected`만 emit 하며 `stateVersion`은 유지된다.
- `resume` success는 `stateSnapshot`을 최소 1개 emit 한다.
- fresh start canonical bootstrap emission order:
  1. `gameStarted`
  2. paired `stateSnapshot(reason=gameStarted)`
  3. optional semantic follow-up (`turnChanged`, `choiceRequested`)

### Core Events
| Event | Trigger | Required Fields | Consumers |
| --- | --- | --- | --- |
| `gameStarted` | initial deal complete | dealer/starter, first player, `snapshotId`, `snapshotStateVersion` | Agent 2, 3, 4 |
| `actionAccepted` | valid command applied | `actionId`, `playerId`, `commandName`, result summary | Agent 2, 3, 4 |
| `actionRejected` | invalid command | `requestId`, `actionId`, `commandName`, `rejectReason` | Agent 2, 3, 4 |
| `turnChanged` | turn owner changed | `turnId`, `currentPlayerId`, `turnDeadlineAt` | Agent 3, 4 |
| `choiceRequested` | branch decision required | `choiceId`, `choiceKind`, `actorPlayerId`, options, deadline | Agent 3, 4 |
| `statePatched` | delta delivery | `patchFormat`, `baseStateVersion`, `targetStateVersion`, patch body | Agent 2, 3, 4 |
| `stateSnapshot` | full state delivery | `snapshotId`, reason, scope, full state | Agent 2, 3, 4 |
| `roundEnded` | scoring locked | winner, score delta, round summary | Agent 2, 3, 4 |
| `matchEnded` | room match complete | final result, settlement summary | Agent 2, 3, 4 |

### Bootstrap Rules
- Phase 0 shipped bootstrap boundary는 current concrete command facade(`room_bootstrap_create`, `room_bootstrap_lookup_invite`, `room_bootstrap_join`, `room_bootstrap_prepare_game_start`)다.
- fresh start bootstrap source of truth는 `stateSnapshot(reason=gameStarted)`다.
- `gameStarted`는 semantic marker이며, client는 visible state를 `gameStarted` payload만으로 구성하지 않는다.
- `gameStarted` payload는 paired snapshot을 가리키는 correlation metadata만 담는다.
- Agent 2 room layer는 fresh start에서 `gameEvent(gameStarted)`와 `gameEvent(stateSnapshot reason=gameStarted)`를 둘 다 전달해야 한다.
- future public bootstrap split / REST facade가 들어와도 canonical authority bootstrap order는 바뀌지 않는다. room layer가 bootstrap transport를 gameplay websocket과 분리하더라도 authoritative pair는 여전히 `gameStarted` + paired `stateSnapshot(reason=gameStarted)`다.
- split bootstrap response는 custom room DTO만으로 visible game state를 대체하면 안 된다. bootstrap-only facade를 만들더라도 authority payload baseline은 `MultiplayerGameStartedBootstrapPayload` 또는 same-field wrapper여야 하고, `gameStarted.snapshotId == stateSnapshot.snapshotId`, `gameStarted.snapshotStateVersion == stateSnapshot.snapshotStateVersion` correlation을 유지해야 한다.
- concrete bootstrap route/facade 이름(`room_bootstrap_create`, `room_bootstrap_join`, `room_bootstrap_prepare_game_start`, future public REST bootstrap endpoint 등)은 room-owned surface일 뿐이다. route 이름이나 bootstrap boundary metadata가 concrete해져도 authority bootstrap payload baseline과 chronology는 바뀌지 않는다.
- true public REST bootstrap split은 deferred scope다. Phase 0 shipped contract는 current command facade boundary를 기준으로 본다.
- Agent 3/4 consumer는 bootstrap state를 snapshot에서 읽고, `gameStarted`는 timeline/analytics/UX trigger 용도로만 사용한다.
- local debug/in-process bootstrap minimum set은 `MultiplayerGameStartedBootstrapPayload`이며, shape는 `{ gameStarted: MultiplayerGameStartedPayload, stateSnapshot: MultiplayerSnapshot }`다.
- Agent 3 `showLive` handoff minimum type은 `MultiplayerLiveBootstrapPayload`이며, shape는 `{ activeGameId, gameStarted, stateSnapshot }`다.
- `MultiplayerLiveBootstrapPayload`는 UI-facing convenience wrapper이고, underlying authority source는 그대로 `MultiplayerGameStartedBootstrapPayload`다.
- live shell state는 `stateSnapshot`에서 만들고, `gameStarted`는 correlation/banner trigger로만 소비한다.

### Terminal Summary Rules
- 현재 engine projection baseline은 single-round match다. 따라서 `roundEnded.summary`와 `matchEnded`는 같은 terminal result fields를 공유하고 `roundIndex`는 현재 `1`로 고정된다.
- normal scoring end(`stop`, `maxScore`, `nagari`, `chongtong`, `threeSeolsa`)에서는 `settlementSummary`를 포함한다.
- forfeit end(`voluntaryQuit`, `disconnectTimeout`, `adminForfeit`)에서는 `settlementSummary = null`을 기본값으로 하고, room layer는 `forfeitingPlayerId`를 반드시 채운다.
- `endReasonMessageKey`는 `match.end.*` namespace를 사용한다.
- Agent 2 transport terminal relay minimum required fields는 아래처럼 좁힌다.
  - `roundEnded`: `roundIndex`, `summary`
  - `roundEnded.summary`: `roundIndex`, `winnerPlayerId`, `loserPlayerId`, `finalScores[]`, `endReason`, `endReasonMessageKey`, `isDraw`
  - `matchEnded`: `roundIndex`, `winnerPlayerId`, `loserPlayerId`, `finalScores[]`, `endReason`, `endReasonMessageKey`, `isDraw`
  - conditional fields:
    - scoring end에서는 `settlementSummary` required, `forfeitingPlayerId = null`
    - forfeit end에서는 `settlementSummary = null`, `forfeitingPlayerId` required
  - `terminalSummary`: `roomId`, `gameId`, `summaryStateVersion`, `lastEventId`, `roundEnded`, `matchEnded`
- `matchEnded`는 `roundIndex`를 포함해야 하며, consumer는 `roundEnded`가 늦거나 생략되더라도 `matchEnded` 단독으로 result shell을 구성할 수 있어야 한다.
- `get_multiplayer_terminal_summary` response baseline type은 `MultiplayerTerminalSummaryPayload`이며, top-level metadata는 `roomId`, `gameId`, `summaryStateVersion`, `lastEventId`, `roundEnded`, `matchEnded`다.
- room transport layer는 `gameEvent(roundEnded).payload`, `gameEvent(matchEnded).payload`, `terminalSummary.payload.roundEnded`, `terminalSummary.payload.matchEnded`를 서로 다른 shape로 재합성하지 않는다. terminalSummary는 same authority payload object를 fan-out하는 view여야 한다.
- Agent 2 validator는 `roundEnded.summary`에서 `settlementSummary`와 `forfeitingPlayerId`를 동시에 required로 간주하면 안 된다. 둘은 `endReason`에 따라 mutually conditioned field다.
- reconnect grace expiry -> `quit(reason=disconnectTimeout)` terminal invariants:
  - `actionAccepted.payload.playerId == roundEnded.summary.forfeitingPlayerId == matchEnded.forfeitingPlayerId`
  - `roundEnded.summary.endReason == matchEnded.endReason == "disconnectTimeout"`
  - `roundEnded.summary.endReasonMessageKey == matchEnded.endReasonMessageKey == "match.end.disconnect_timeout"`
  - `roundEnded.stateVersion == matchEnded.stateVersion == terminalSummary.summaryStateVersion`
  - `matchEnded.eventId == terminalSummary.lastEventId`
  - `winnerPlayerId`, `loserPlayerId`, `finalScores[]`, `roundIndex`, `isDraw`는 `roundEnded.summary`, `matchEnded`, `terminalSummary.payload.roundEnded.summary`, `terminalSummary.payload.matchEnded`에서 동일해야 한다
- passive socket close -> timeout expiry path에서도 위 invariants는 그대로 유지된다. close detection mechanism이 TCP/WebSocket/passive teardown인지 여부는 authority payload shape를 바꾸지 못한다.
- server-owned automatic expiry sweep path에서도 위 invariants는 그대로 유지된다. timer cadence, sweep owner, manual debug hook 여부는 authority terminal payload shape나 correlation fields를 바꾸지 못한다.
- `roomClosed`는 room-owned cleanup signal이며 authority result source가 아니다. room layer가 timeout cleanup 후 terminal correlation metadata를 싣는다면 최소 `gameId`, `lastTerminalEventId`, `summaryStateVersion`, `endReason`, `forfeitingPlayerId`를 prior terminal authority payload와 일치시켜야 한다. `winnerPlayerId` / `loserPlayerId` / `finalScores[]`를 복사한다면 `matchEnded`와 byte-for-byte 같은 값이어야 하고, 아니면 생략하는 편이 낫다.
- passive disconnect cleanup에서도 `roomClosed` correlation fields는 동일하다. passive close 때문에 `gameId`, `summaryStateVersion`, `lastTerminalEventId`, `endReason`, `forfeitingPlayerId` naming이나 값이 달라지면 contract drift다.

### Event Sample Payloads

#### `gameStarted`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000001",
  "stateVersion": 1,
  "causedByActionId": "act_start_0001",
  "serverTime": "2026-03-08T15:29:59+09:00",
  "eventName": "gameStarted",
  "payload": {
    "roundIndex": 1,
    "dealerPlayerId": "player_b",
    "starterPlayerId": "player_b",
    "firstPlayerId": "player_b",
    "snapshotId": "snap_000001_player_a",
    "snapshotStateVersion": 1
  }
}
```

#### `actionAccepted`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000211",
  "stateVersion": 13,
  "causedByActionId": "act_000041",
  "serverTime": "2026-03-08T15:30:01+09:00",
  "eventName": "actionAccepted",
  "payload": {
    "requestId": "req_000041",
    "actionId": "act_000041",
    "playerId": "player_a",
    "commandName": "playCard",
    "result": {
      "playedCardId": "card_03_ribbon_red_poem",
      "pendingChoiceCreated": true,
      "turnContinues": true
    }
  }
}
```

#### `actionRejected`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000212",
  "stateVersion": 13,
  "causedByActionId": "act_000099",
  "serverTime": "2026-03-08T15:30:02+09:00",
  "eventName": "actionRejected",
  "payload": {
    "requestId": "req_000099",
    "actionId": "act_000099",
    "playerId": "player_b",
    "commandName": "playCard",
    "rejectReason": {
      "code": "outOfTurn",
      "retryable": false,
      "messageKey": "match.reject.out_of_turn",
      "details": {
        "currentPlayerId": "player_a",
        "phase": "inTurn",
        "turnId": "turn_0007",
        "latestStateVersion": 13
      }
    }
  }
}
```

#### `actionRejected` (`staleStateVersion`)
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000301",
  "stateVersion": 15,
  "causedByActionId": "act_000121",
  "serverTime": "2026-03-08T15:32:08+09:00",
  "eventName": "actionRejected",
  "payload": {
    "requestId": "req_000121",
    "actionId": "act_000121",
    "playerId": "player_a",
    "commandName": "playCard",
    "rejectReason": {
      "code": "staleStateVersion",
      "retryable": true,
      "messageKey": "match.reject.stale_state_version",
      "details": {
        "expectedStateVersion": 14,
        "authoritativeStateVersion": 15,
        "authoritativeEventId": "evt_000300",
        "resync": {
          "trigger": "staleStateVersionReject",
          "snapshotReason": "resync",
          "clientStateVersion": 14,
          "expectedStateVersion": 14,
          "authoritativeStateVersion": 15,
          "clientEventId": "evt_000298",
          "authoritativeEventId": "evt_000300",
          "shouldLockInput": true
        }
      }
    }
  }
}
```

#### `choiceRequested`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000213",
  "stateVersion": 13,
  "causedByActionId": "act_000041",
  "serverTime": "2026-03-08T15:30:01+09:00",
  "eventName": "choiceRequested",
  "payload": {
    "choiceId": "choice_0007",
    "choiceKind": "capture",
    "actorPlayerId": "player_a",
    "promptKey": "match.choice.capture",
    "requestedAt": "2026-03-08T15:30:01+09:00",
    "deadlineAt": "2026-03-08T15:30:16+09:00",
    "expiresAtStateVersion": 13,
    "options": [
      {
        "optionCode": "capture_pair_left",
        "labelKey": "match.choice.capture.take_pair",
        "cards": [
          {
            "cardId": "card_03_ribbon_red_poem",
            "zone": "played"
          },
          {
            "cardId": "card_03_junk_a",
            "zone": "table"
          }
        ],
        "effectTags": ["capture"],
        "scoreDeltaPreview": {
          "self": 0,
          "opponent": 0
        }
      },
      {
        "optionCode": "capture_pair_right",
        "labelKey": "match.choice.capture.take_pair",
        "cards": [
          {
            "cardId": "card_03_ribbon_red_poem",
            "zone": "played"
          },
          {
            "cardId": "card_03_junk_b",
            "zone": "table"
          }
        ],
        "effectTags": ["capture"],
        "scoreDeltaPreview": {
          "self": 0,
          "opponent": 0
        }
      }
    ]
  }
}
```

#### `statePatched`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000214",
  "stateVersion": 13,
  "causedByActionId": "act_000041",
  "serverTime": "2026-03-08T15:30:01+09:00",
  "eventName": "statePatched",
  "payload": {
    "patchFormat": "json-patch",
    "baseStateVersion": 12,
    "targetStateVersion": 13,
    "ops": [
      {
        "op": "remove",
        "path": "/players/0/hand/3"
      },
      {
        "op": "add",
        "path": "/table/cards/5",
        "value": {
          "cardId": "card_03_ribbon_red_poem",
          "month": 3,
          "kind": "ribbon"
        }
      },
      {
        "op": "replace",
        "path": "/pendingChoice",
        "value": {
          "choiceId": "choice_0007",
          "choiceKind": "capture"
        }
      }
    ]
  }
}
```

#### `stateSnapshot`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000215",
  "stateVersion": 13,
  "causedByActionId": "act_resume_0001",
  "serverTime": "2026-03-08T15:31:20+09:00",
  "eventName": "stateSnapshot",
  "payload": {
    "snapshotId": "snap_000013_player_a",
    "reason": "resume",
    "scope": "player",
    "snapshotStateVersion": 13,
    "lastIncludedEventId": "evt_000214",
    "state": {
      "gameId": "game_001",
      "stateVersion": 13,
      "phase": "choicePending",
      "currentPlayerId": "player_a",
      "pendingChoice": {
        "choiceId": "choice_0007",
        "choiceKind": "capture"
      }
    }
  }
}
```

#### `stateSnapshot` (`resync`)
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000302",
  "stateVersion": 15,
  "causedByActionId": null,
  "serverTime": "2026-03-08T15:32:08+09:00",
  "eventName": "stateSnapshot",
  "payload": {
    "snapshotId": "snap_000015_player_a",
    "reason": "resync",
    "scope": "player",
    "snapshotStateVersion": 15,
    "lastIncludedEventId": "evt_000300",
    "state": {
      "gameId": "game_001",
      "stateVersion": 15,
      "phase": "inTurn",
      "currentPlayerId": "player_b",
      "turnId": "turn_0008"
    }
  }
}
```

#### `roundEnded`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000216",
  "stateVersion": 24,
  "causedByActionId": "act_000044",
  "serverTime": "2026-03-08T15:31:21+09:00",
  "eventName": "roundEnded",
  "payload": {
    "roundIndex": 1,
    "summary": {
      "roundIndex": 1,
      "winnerPlayerId": "player_a",
      "loserPlayerId": "player_b",
      "finalScores": [
        {
          "playerId": "player_a",
          "score": 7,
          "goCount": 1,
          "money": 11200
        },
        {
          "playerId": "player_b",
          "score": 4,
          "goCount": 0,
          "money": 8800
        }
      ],
      "settlementSummary": {
        "finalScore": 12,
        "scoreFormula": "(7 + go bonus 1) x gobak 2",
        "isDraw": false,
        "isGwangbak": false,
        "isPibak": false,
        "isGobak": true,
        "isMungbak": false,
        "isJabak": false,
        "isYeokbak": false
      },
      "endReason": "stop",
      "endReasonMessageKey": "match.end.stop",
      "forfeitingPlayerId": null,
      "isDraw": false
    }
  }
}
```

#### `matchEnded`
```json
{
  "type": "event",
  "traceId": "trace_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "eventId": "evt_000217",
  "stateVersion": 24,
  "causedByActionId": "act_000046",
  "serverTime": "2026-03-08T15:31:22+09:00",
  "eventName": "matchEnded",
  "payload": {
    "roundIndex": 1,
    "winnerPlayerId": "player_a",
    "loserPlayerId": "player_b",
    "finalScores": [
      {
        "playerId": "player_a",
        "score": 5,
        "goCount": 0,
        "money": 10000
      },
      {
        "playerId": "player_b",
        "score": 2,
        "goCount": 0,
        "money": 10000
      }
    ],
    "settlementSummary": null,
    "endReason": "disconnectTimeout",
    "endReasonMessageKey": "match.end.disconnect_timeout",
    "forfeitingPlayerId": "player_b",
    "isDraw": false
  }
}
```

#### `get_multiplayer_terminal_summary`
```json
{
  "status": "ok",
  "action": "get_multiplayer_terminal_summary",
  "roomId": "room_001",
  "gameId": "game_001",
  "summaryStateVersion": 24,
  "lastEventId": "evt_000217",
  "roundEnded": {
    "roundIndex": 1,
    "summary": {
      "roundIndex": 1,
      "winnerPlayerId": "player_a",
      "loserPlayerId": "player_b",
      "finalScores": [
        {
          "playerId": "player_a",
          "score": 7,
          "goCount": 1,
          "money": 11200
        },
        {
          "playerId": "player_b",
          "score": 4,
          "goCount": 0,
          "money": 8800
        }
      ],
      "settlementSummary": {
        "finalScore": 12,
        "scoreFormula": "(7 + go bonus 1) x gobak 2",
        "isDraw": false,
        "isGwangbak": false,
        "isPibak": false,
        "isGobak": true,
        "isMungbak": false,
        "isJabak": false,
        "isYeokbak": false
      },
      "endReason": "stop",
      "endReasonMessageKey": "match.end.stop",
      "forfeitingPlayerId": null,
      "isDraw": false
    }
  },
  "matchEnded": {
    "roundIndex": 1,
    "winnerPlayerId": "player_a",
    "loserPlayerId": "player_b",
    "finalScores": [
      {
        "playerId": "player_a",
        "score": 7,
        "goCount": 1,
        "money": 11200
      },
      {
        "playerId": "player_b",
        "score": 4,
        "goCount": 0,
        "money": 8800
      }
    ],
    "settlementSummary": {
      "finalScore": 12,
      "scoreFormula": "(7 + go bonus 1) x gobak 2",
      "isDraw": false,
      "isGwangbak": false,
      "isPibak": false,
      "isGobak": true,
      "isMungbak": false,
      "isJabak": false,
      "isYeokbak": false
    },
    "endReason": "stop",
    "endReasonMessageKey": "match.end.stop",
    "forfeitingPlayerId": null,
    "isDraw": false
  }
}
```

#### Transport Terminal Minimum Relay Payload
```json
{
  "type": "terminalSummary",
  "roomId": "room_001",
  "roomSequence": 59,
  "payload": {
    "roomId": "room_001",
    "gameId": "game_001",
    "summaryStateVersion": 24,
    "lastEventId": "evt_000218",
    "roundEnded": {
      "roundIndex": 1,
      "summary": {
        "roundIndex": 1,
        "winnerPlayerId": "player_a",
        "loserPlayerId": "player_b",
        "finalScores": [
          {
            "playerId": "player_a",
            "score": 7,
            "goCount": 1,
            "money": 11200
          },
          {
            "playerId": "player_b",
            "score": 4,
            "goCount": 0,
            "money": 8800
          }
        ],
        "settlementSummary": {
          "finalScore": 12,
          "scoreFormula": "(7 + go bonus 1) x gobak 2",
          "isDraw": false,
          "isGwangbak": false,
          "isPibak": false,
          "isGobak": true,
          "isMungbak": false,
          "isJabak": false,
          "isYeokbak": false
        },
        "endReason": "stop",
        "endReasonMessageKey": "match.end.stop",
        "forfeitingPlayerId": null,
        "isDraw": false
      }
    },
    "matchEnded": {
      "roundIndex": 1,
      "winnerPlayerId": "player_a",
      "loserPlayerId": "player_b",
      "finalScores": [
        {
          "playerId": "player_a",
          "score": 7,
          "goCount": 1,
          "money": 11200
        },
        {
          "playerId": "player_b",
          "score": 4,
          "goCount": 0,
          "money": 8800
        }
      ],
      "settlementSummary": {
        "finalScore": 12,
        "scoreFormula": "(7 + go bonus 1) x gobak 2",
        "isDraw": false,
        "isGwangbak": false,
        "isPibak": false,
        "isGobak": true,
        "isMungbak": false,
        "isJabak": false,
        "isYeokbak": false
      },
      "endReason": "stop",
      "endReasonMessageKey": "match.end.stop",
      "forfeitingPlayerId": null,
      "isDraw": false
    }
  }
}
```
- disconnect timeout / voluntary quit / admin forfeit relay에서는 위 sample에서 `settlementSummary = null`, `forfeitingPlayerId = authority playerId`로 바뀌는 것만 mandatory 차이다.

#### Timeout Forfeit Relay Sequence (`disconnectTimeout`)
```json
[
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 70,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionAccepted",
        "eventId": "evt_000316",
        "stateVersion": 24,
        "causedByActionId": "act_timeout_001",
        "payload": {
          "requestId": "req_timeout_001",
          "actionId": "act_timeout_001",
          "playerId": "player_b",
          "commandName": "quit"
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 71,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "roundEnded",
        "eventId": "evt_000317",
        "stateVersion": 24,
        "causedByActionId": "act_timeout_001",
        "payload": {
          "roundIndex": 1,
          "summary": {
            "roundIndex": 1,
            "winnerPlayerId": "player_a",
            "loserPlayerId": "player_b",
            "finalScores": [
              {
                "playerId": "player_a",
                "score": 5,
                "goCount": 0,
                "money": 10000
              },
              {
                "playerId": "player_b",
                "score": 2,
                "goCount": 0,
                "money": 10000
              }
            ],
            "settlementSummary": null,
            "endReason": "disconnectTimeout",
            "endReasonMessageKey": "match.end.disconnect_timeout",
            "forfeitingPlayerId": "player_b",
            "isDraw": false
          }
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 72,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "matchEnded",
        "eventId": "evt_000318",
        "stateVersion": 24,
        "causedByActionId": "act_timeout_001",
        "payload": {
          "roundIndex": 1,
          "winnerPlayerId": "player_a",
          "loserPlayerId": "player_b",
          "finalScores": [
            {
              "playerId": "player_a",
              "score": 5,
              "goCount": 0,
              "money": 10000
            },
            {
              "playerId": "player_b",
              "score": 2,
              "goCount": 0,
              "money": 10000
            }
          ],
          "settlementSummary": null,
          "endReason": "disconnectTimeout",
          "endReasonMessageKey": "match.end.disconnect_timeout",
          "forfeitingPlayerId": "player_b",
          "isDraw": false
        }
      }
    }
  },
  {
    "type": "terminalSummary",
    "roomId": "room_001",
    "roomSequence": 73,
    "payload": {
      "roomId": "room_001",
      "gameId": "game_001",
      "summaryStateVersion": 24,
      "lastEventId": "evt_000318",
      "roundEnded": {
        "roundIndex": 1,
        "summary": {
          "roundIndex": 1,
          "winnerPlayerId": "player_a",
          "loserPlayerId": "player_b",
          "finalScores": [
            {
              "playerId": "player_a",
              "score": 5,
              "goCount": 0,
              "money": 10000
            },
            {
              "playerId": "player_b",
              "score": 2,
              "goCount": 0,
              "money": 10000
            }
          ],
          "settlementSummary": null,
          "endReason": "disconnectTimeout",
          "endReasonMessageKey": "match.end.disconnect_timeout",
          "forfeitingPlayerId": "player_b",
          "isDraw": false
        }
      },
      "matchEnded": {
        "roundIndex": 1,
        "winnerPlayerId": "player_a",
        "loserPlayerId": "player_b",
        "finalScores": [
          {
            "playerId": "player_a",
            "score": 5,
            "goCount": 0,
            "money": 10000
          },
          {
            "playerId": "player_b",
            "score": 2,
            "goCount": 0,
            "money": 10000
          }
        ],
        "settlementSummary": null,
        "endReason": "disconnectTimeout",
        "endReasonMessageKey": "match.end.disconnect_timeout",
        "forfeitingPlayerId": "player_b",
        "isDraw": false
      }
    }
  },
  {
    "type": "roomEvent",
    "roomId": "room_001",
    "roomSequence": 74,
    "eventName": "roomClosed",
    "payload": {
      "reason": "resultExpired",
      "gameId": "game_001",
      "summaryStateVersion": 24,
      "lastTerminalEventId": "evt_000318",
      "endReason": "disconnectTimeout",
      "forfeitingPlayerId": "player_b"
    }
  }
]
```
- 위 `roomClosed` example은 authority carry-through reference만 보여준다. `roomClosed` full envelope ownership은 Agent 2 문서에 있지만, timeout cleanup path에서 terminal correlation fields를 싣는다면 위 sample처럼 prior `matchEnded`와 충돌하지 않아야 한다.
- passive socket close path는 위 sequence 앞단에 room-owned disconnect detection signal(`playerDisconnected`, connection teardown audit, grace-start marker 등)을 추가할 수 있다. 하지만 grace expiry 뒤 authoritative tail은 여전히 `actionAccepted -> roundEnded -> matchEnded -> terminalSummary`, 이후 cleanup `roomClosed`로 이어져야 하며, 위 authority fields와 correlation fields를 바꾸면 안 된다.

## Choice Contract

### Shape
```json
{
  "choiceId": "choice_0007",
  "choiceKind": "capture|shake|goStop|chrysanthemumRole",
  "visibility": "allParticipants|actorOnly",
  "actorPlayerId": "player_a",
  "promptKey": "match.choice.capture",
  "requestedAt": "2026-03-08T15:30:01+09:00",
  "deadlineAt": "2026-03-08T15:30:16+09:00",
  "expiresAtStateVersion": 13,
  "options": [
    {
      "optionCode": "capture_pair_left",
      "labelKey": "match.choice.capture.take_pair",
      "cards": [],
      "effectTags": [],
      "scoreDeltaPreview": {
        "self": 0,
        "opponent": 0
      },
      "metadata": {}
    }
  ]
}
```

### Choice Rules
- UI는 `labelKey`/`promptKey`를 기준으로 문구를 localize 한다. 서버가 raw localized text를 보내는 것은 계약상 필수 아니다.
- `cards[]`는 rule-critical preview를 위해 stable `cardId`를 포함한다.
- `scoreDeltaPreview`는 best-effort hint이며 authoritative score settlement는 아니다.
- choice command는 반드시 해당 `choiceId`와 `optionCode`를 echo 해야 한다.
- current engine에는 `chrysanthemumRole` special choice가 있으므로 core enum은 `MultiplayerContractChoiceKind`를 사용한다. Agent 3 shell type과 이름이 다를 수 있다.
- `askingShake`는 `visibility = actorOnly`다. actor 또는 `authority` scope만 raw `cards[]`와 shake metadata를 받고, non-actor participant는 같은 `choiceId`/`optionCode`를 보더라도 `cards=[]`, `metadata=null`인 redacted payload를 받는다.

## State Sync Policy

### Snapshot
- snapshot은 full player-scoped state 전달이다.
- 사용 시점:
  - `gameStarted`
  - `resume`
  - stateVersion gap recovery
  - patch apply failure recovery
- snapshot reason enum:
  - `gameStarted`
  - `resume`
  - `resync`
  - `gapDetected`

### Patch
- 정상 실시간 플레이 중 기본 전송 방식은 JSON Patch다.
- `statePatched.payload.baseStateVersion`은 client local version과 같아야 한다.
- patch apply 후 local `stateVersion`은 `targetStateVersion`과 같아야 한다.
- gap 또는 apply failure가 나면 client는 patch 적용을 중단하고 snapshot을 기다리거나 요청해야 한다.

### Snapshot/Patch Compatibility Rules
- resume의 minimum contract는 `stateSnapshot` 1회로 충분하다.
- missed event catch-up after snapshot은 optimization이며 engine contract의 필수는 아니다.
- live client는 snapshot-only recovery path를 반드시 지원해야 한다.
- `stateVersion`이 같고 `eventId`만 앞서는 event를 받는 경우 semantic event만 처리하고 state patch 중복 적용은 피한다.
- command stale reject path에서는 `actionRejected(code=staleStateVersion)` 뒤에 `stateSnapshot(reason=resync)`가 recovery baseline이다.
- patch base mismatch 또는 dropped game event를 client가 감지한 path에서는 input을 잠그고 `stateSnapshot(reason=gapDetected)`를 기다리는 것이 baseline이다.
- Phase 0 shipped live gap recovery path는 explicit hook `triggerGapRecovery -> gapRecoveryHint -> stateSnapshot(reason=gapDetected)`다.
- MP-008 P0 deterministic validation은 stale `expectedStateVersion` override만 사용한다. dropped game event hook은 future extension으로 남긴다.
- `dropGameEvents`는 다음 phase smoke hook으로 올리지 않는다. stale gameplay transport resync smoke가 안정화될 때까지 future extension으로 유지한다.
- dropped-event gap 기반 future extension이 추가되더라도 authority minimum recovery contract는 바뀌지 않는다. baseline은 계속 input lock + full `stateSnapshot(reason=gapDetected)` 1회이며, partial replay-only recovery나 patch-only recovery는 필수 contract가 아니다.
- gap-based future extension이 executable hook으로 올라와도 authority가 요구하는 minimum ambiguity-free cursor set은 `lastDeliveredEventId`, `nextAuthoritativeEventId`, recovery snapshot의 `lastIncludedEventId`, `snapshotStateVersion`이다. room/test artifact는 여기에 `plannedTargetClientId`, `plannedDropCount`, `plannedDropAfterEventName`, `plannedFollowUpActionId`를 additive로 붙일 수 있지만 engine recovery payload shape는 바꾸지 않는다.
- gapDetected recovery completion 기준은 client가 input lock 상태에서 authoritative `stateSnapshot(reason=gapDetected)`를 적용하고, 그 snapshot의 `lastIncludedEventId`가 first missing authoritative cursor 이상임을 확인하는 것이다. 그 전에는 patch replay나 later semantic event만으로 recovery 완료로 간주하면 안 된다.
- concrete live gap hook surface(`room_gap_recovery_shape`, `gapRecoveryHint`, `gapDetected` transport flag 등)는 room/test hint일 뿐이다. 이 metadata가 먼저 노출되더라도 recovery start/completion source-of-truth는 여전히 live `gameEvent(stateSnapshot reason=gapDetected)`다.
- automatic dropped-event detection은 deferred scope다. Phase 0에서는 explicit live gap hook이 없는데도 spontaneous `gapDetected` recovery가 시작되기를 요구하지 않는다.
- stale reject recovery pair에서는 `rejectReason.details.authoritativeStateVersion`과 뒤이은 `stateSnapshot.payload.snapshotStateVersion`이 같아야 하고, `rejectReason.details.authoritativeEventId`와 `stateSnapshot.payload.lastIncludedEventId`가 같은 authoritative head를 가리켜야 한다.
- live transport stale-version recovery snapshot은 `stateSnapshot.reason = resync`만 허용한다. `localPreview`는 preview/helper contract 전용이며 `gameEvent(stateSnapshot)` live relay에서는 invalid다.

### Relay-Ready Engine Envelope Samples
- room websocket은 `gameEvent.payload.engineEvent` 안에 Agent 1 engine envelope를 nested해서 relay 한다.
- stale-version reject relay sample:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 44,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "actionRejected",
      "eventId": "evt_000301",
      "stateVersion": 15,
      "payload": {
        "actionId": "act_000121",
        "commandName": "playCard",
        "rejectReason": {
          "code": "staleStateVersion",
          "details": {
            "expectedStateVersion": 14,
            "authoritativeStateVersion": 15,
            "authoritativeEventId": "evt_000300",
            "resync": {
              "trigger": "staleStateVersionReject",
              "snapshotReason": "resync",
              "shouldLockInput": true
            }
          }
        }
      }
    }
  }
}
```
- `stateSnapshot(reason=resync)` relay sample:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 45,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "stateSnapshot",
      "eventId": "evt_000302",
      "stateVersion": 15,
      "payload": {
        "snapshotId": "snap_000015_player_a",
        "reason": "resync",
        "snapshotStateVersion": 15,
        "lastIncludedEventId": "evt_000300"
      }
    }
  }
}
```
- stale `expectedStateVersion` reject + `stateSnapshot(reason=resync)` recovery pair:
```json
[
  {
    "action": "room_transport_send",
    "payload": {
      "roomId": "room_001",
      "connectionId": "conn_host_001",
      "message": {
        "type": "command",
        "traceId": "trace_001",
        "requestId": "req_000121",
        "roomId": "room_001",
        "gameId": "game_001",
        "playerId": "player_a",
        "actionId": "act_000121",
        "expectedStateVersion": 14,
        "command": {
          "name": "playCard",
          "payload": {
            "cardId": "card_02_animal_nightingale",
            "source": "hand"
          }
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 44,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "actionRejected",
        "eventId": "evt_000301",
        "stateVersion": 15,
        "causedByActionId": "act_000121",
        "payload": {
          "actionId": "act_000121",
          "commandName": "playCard",
          "rejectReason": {
            "code": "staleStateVersion",
            "details": {
              "expectedStateVersion": 14,
              "authoritativeStateVersion": 15,
              "authoritativeEventId": "evt_000300",
              "resync": {
                "trigger": "staleStateVersionReject",
                "snapshotReason": "resync",
                "shouldLockInput": true
              }
            }
          }
        }
      }
    }
  },
  {
    "type": "gameEvent",
    "roomId": "room_001",
    "roomSequence": 45,
    "payload": {
      "engineEvent": {
        "type": "event",
        "eventName": "stateSnapshot",
        "eventId": "evt_000302",
        "stateVersion": 15,
        "payload": {
          "snapshotId": "snap_000015_player_a",
          "reason": "resync",
          "snapshotStateVersion": 15,
          "lastIncludedEventId": "evt_000300",
          "scope": "player"
        }
      }
    }
  }
]
```
- websocket relay baseline은 stale reject와 paired resync snapshot 사이에 다른 game event를 끼우지 않는 것이다. room ack/transport ack는 있어도 되지만, authoritative recovery ordering은 위 두 `gameEvent` sequence로 보장해야 한다.
- `stateSnapshot(reason=gapDetected)` relay sample:
```json
{
  "type": "gameEvent",
  "roomId": "room_001",
  "roomSequence": 46,
  "payload": {
    "engineEvent": {
      "type": "event",
      "eventName": "stateSnapshot",
      "eventId": "evt_000401",
      "stateVersion": 18,
      "payload": {
        "snapshotId": "snap_000018_player_a",
        "reason": "gapDetected",
        "snapshotStateVersion": 18,
        "lastIncludedEventId": "evt_000399"
      }
    }
  }
}
```
- dropped-event gap future extension에서도 위 `stateSnapshot(reason=gapDetected)`가 recovery baseline이다. future artifact나 timer-driven transport change가 들어와도 minimum required fields는 `snapshotId`, `reason=gapDetected`, `snapshotStateVersion`, `lastIncludedEventId`, `scope`, full player-scoped `state`로 유지된다.
- gapDetected path는 stale command reject처럼 paired `actionRejected`를 필수로 요구하지 않는다. client는 input을 잠그고 위 snapshot을 authoritative recovery source로 적용하면 된다.
- bootstrap split이나 room-owned preflight hook이 추가돼도 gapDetected recovery는 live `gameEvent(stateSnapshot)` authority payload를 기준으로 판정한다. room artifact는 cursor/debug metadata를 덧붙일 수 있지만 `stateSnapshot(reason=gapDetected)`를 대체할 수 없다.

## Player Identity Mapping Contract
- engine authority payload는 room `playerId`를 알지 못하며, `playerId`/`currentPlayerId`/`winnerPlayerId`/`forfeitingPlayerId` 등 game payload의 identity field는 모두 authority `playerId`다.
- mapping owner는 room/session layer다. engine은 authority ID만 emit 하고 room ID로 translate 하지 않는다.
- ingress rule:
  - client transport session은 room member identity를 가진다.
  - room layer는 authenticated room session과 `playerIdentityBindings`를 사용해 `roomPlayerId -> authorityPlayerId`를 resolve한 뒤 `MultiplayerCommandEnvelope.playerId`를 채운다.
  - client가 authority `playerId`를 직접 보내더라도 advisory echo로만 다루고, session mapping과 다르면 reject 또는 overwrite 한다.
- egress rule:
  - nested engine payload(`gameStarted`, `stateSnapshot`, `choiceRequested`, `roundEnded`, `matchEnded`, `terminalSummary`)는 authority `playerId`를 유지한다.
  - room layer는 client가 authority ID를 해석할 수 있도록 stable binding metadata를 room-owned envelope에 붙인다.
- room-owned binding shape baseline은 `MultiplayerPlayerIdentityBinding { roomPlayerId, authorityPlayerId }`다.
- `playerIdentityBindings`는 최소 `helloAck`와 `roomSnapshot`에서 제공하고, room membership이 바뀌지 않는 한 같은 room lifetime 동안 stable해야 한다.
- mapping이 필요한 surface:
  - bootstrap/projection: `viewerPlayerId`, `players[].playerId`, `participantPresenceByPlayerId`
  - transport relay: ingress command actor, `actionAccepted.playerId`, `actionRejected.playerId`, `choiceRequested.actorPlayerId`
  - terminal/result: `winnerPlayerId`, `loserPlayerId`, `finalScores[].playerId`, `forfeitingPlayerId`

### Authority Identity Field Matrix
- authority `playerId`를 유지하는 engine payload fields:
  - command/reject/accept: `MultiplayerCommandEnvelope.playerId`, `actionAccepted.playerId`, `actionRejected.playerId`
  - live state: `viewerPlayerId`, `currentPlayerId`, `dealerPlayerId`, `starterPlayerId`, `players[].playerId`, `participantPresenceByPlayerId` key
  - turn/choice: `turnChanged.currentPlayerId`, `choiceRequested.actorPlayerId`
  - terminal: `winnerPlayerId`, `loserPlayerId`, `finalScores[].playerId`, `forfeitingPlayerId`
- room identity lookup owner:
  - ingress gameplay/resume/quit command actor resolution은 room transport + authenticated session/member layer
  - bootstrap/projection/result에서 authority ID를 room-facing badge/name/seat로 바꾸는 lookup은 room snapshot/hello metadata consumer layer
- engine은 room identity를 다시 emit 하지 않는다. room-facing UX label이 필요하면 room envelope metadata를 기준으로 lookup 해야 한다.

### Room-Owned Binding Sample
```json
{
  "playerIdentityBindings": [
    {
      "roomPlayerId": "room_host_001",
      "authorityPlayerId": "player_a"
    },
    {
      "roomPlayerId": "room_guest_001",
      "authorityPlayerId": "player_b"
    }
  ]
}
```

## Local Projection Entry Point
- existing single-agent `get_state`는 유지한다.
- game-start bootstrap preview 진입점은 `GameManager.multiplayerGameStartedBootstrapPayload(viewerPlayerId:context:)`다.
- UI-facing live bootstrap preview 진입점은 `GameManager.multiplayerLiveBootstrapPayload(viewerPlayerId:context:)`다.
- multiplayer preview 진입점은 `GameManager.multiplayerSnapshot(viewerPlayerId:context:)`다.
- terminal result preview 진입점은 `GameManager.multiplayerRoundEndedPayload(...)` / `GameManager.multiplayerMatchEndedPayload(...)`다.
- bridge/CLI helper는 `TestControlSupport.serializedMultiplayerProjectionPayload(from:requestData:)`를 사용한다.
- local bridge action 이름은 `get_multiplayer_projection`이며, `snapshot` payload에 player-scoped projection을 담아 반환한다.
- local preview request는 `participantPresenceByPlayerId[playerId] = { isConnected, isReady, source }` shape로 room truth를 merge할 수 있다.
- in-process typed helper는 `TestControlSupport.multiplayerGameStartedBootstrapPayload(from:requestData:)`를 사용한다.
- Agent 3 local debug helper는 `TestControlSupport.multiplayerLiveBootstrapPayload(from:requestData:)`를 사용한다.
- game-start bootstrap preview JSON helper는 `TestControlSupport.serializedMultiplayerGameStartedBootstrapPayload(from:requestData:)`를 사용한다.
- local bridge action `get_multiplayer_game_started_bootstrap`는 `MultiplayerGameStartedBootstrapPayload`를 JSON으로 직렬화한 `gameStarted` + paired `stateSnapshot(reason=gameStarted)`를 반환한다.
- terminal preview helper는 `TestControlSupport.serializedMultiplayerTerminalSummaryPayload(from:requestData:)`를 사용한다.
- local bridge action `get_multiplayer_terminal_summary`는 `MultiplayerTerminalSummaryPayload` metadata(`roomId`, `gameId`, `summaryStateVersion`, `lastEventId`)와 함께 `roundEnded` / `matchEnded`를 반환한다.
- in-process terminal helper는 `TestControlSupport.multiplayerTerminalSummaryPayload(from:requestData:)`를 사용한다.
- `get_multiplayer_terminal_summary`에서 `quitReason` override를 쓰는 경우 `forfeitingPlayerId`도 함께 보내야 한다.

## Replay Contract

### Purpose
- deterministic restore
- failure reproduction
- authoritative audit

### Required Replay Artifacts
- authority-scope baseline snapshot
- ordered authoritative event stream
- engine version
- rule config version
- final state hash or summary
- retention policy

### Retention Policy
- authority replay artifact retention policy는 `privilegedDebugOnly`로 고정한다.
- required retention cases:
  - fixture / CLI smoke / socket smoke / manual debug run
  - failing run or anomaly capture
  - explicit privileged debug export 요청
- default no-retention cases:
  - 일반 production transport session
  - privileged flag 없는 정상 사용자 매치
- player-scoped transcript는 일반 artifact로 남길 수 있지만, authority replay baseline/full stream은 privileged debug surface에서만 저장/노출한다.

### Authority Replay Manifest Sample
```json
{
  "replayId": "replay_game_001",
  "roomId": "room_001",
  "gameId": "game_001",
  "retentionPolicy": "privilegedDebugOnly",
  "engineVersion": "gostop-core@2026.03.08",
  "ruleConfigVersion": "rules_2026_03_08",
  "baselineSnapshotId": "auth_snap_round1_start",
  "baselineStateVersion": 1,
  "firstEventId": "evt_000001",
  "lastEventId": "evt_000214",
  "finalStateVersion": 13,
  "finalStateHash": "sha256:6f0f8f5c..."
}
```

### Replay Rules
- replay baseline은 player scope가 아니라 `authority` scope여야 한다.
- event stream은 emitted order 그대로 보존해야 한다.
- 같은 `engineVersion` + 같은 `ruleConfigVersion` + 같은 baseline + 같은 event stream이면 같은 final state hash가 나와야 한다.
- replay artifact는 `privilegedDebugOnly` 정책을 따르며 production client에 직접 노출하지 않는다.
- player-facing delivery payload와 authority replay payload는 visibility scope가 다를 수 있다.

## Validation Checklist
- [ ] state projection이 player visibility rules를 지킨다
- [ ] out-of-turn / invalid choice / stale version / duplicate `actionId` policy가 정의돼 있다
- [ ] `choiceRequested`에 UI와 test runner가 필요한 필드가 있다
- [ ] reconnect / resync를 위해 snapshot policy가 명시돼 있다
- [ ] fresh start bootstrap이 `gameStarted` + paired `stateSnapshot(reason=gameStarted)`로 명시돼 있다
- [ ] `askingShake`가 non-actor에게 raw hand metadata를 노출하지 않는다
- [ ] projection의 `isConnected/isReady`가 room/session merge contract와 모순되지 않는다
- [ ] starter/dealer related payload가 실제 starter selection 결과를 따른다
- [ ] replay 최소 데이터와 visibility scope가 정의돼 있다
- [ ] `pendingChoice`가 non-actor에게 hidden hand metadata를 노출하지 않는다
- [ ] projection의 `isConnected/isReady`가 room/session truth와 모순되지 않는다
- [ ] starter/dealer related payload가 실제 starter selection 결과를 따른다

## Open Questions By Consumer

### Agent 2
- [ ] room websocket이 engine event envelope를 그대로 forwarding 할지, room envelope 내부에 nested payload로 감쌀지 최종 결정 필요
- [ ] `playerReconnected` room event와 `stateSnapshot(reason=resume)`의 순서를 transport level에서 어떻게 보장할지 결정 필요

### Agent 3
- [ ] `labelKey` / `promptKey` / `messageKey` 문자열 카탈로그 naming convention을 UI 쪽에서 그대로 사용할지 확인 필요
- [ ] `choiceRequested.options[].cards[]`가 actor/non-actor visibility가 달라질 때도 choice tray 렌더가 충분한지 확인 필요
- [ ] turn/choice deadline UX에 `deadlineAt` + `serverTime` 조합이면 충분한지, 추가 drift correction 필드가 필요한지 확인 필요
- [ ] local debug `.starting -> showLive` handoff에서 `MultiplayerLiveBootstrapPayload.stateSnapshot`을 live source of truth로 쓰고, `gameStarted`는 auxiliary marker로만 유지하는 mapper 연결 필요

### Agent 4
- [ ] live websocket/TCP duplicate probe가 exact resend에서는 `duplicateActionIdDisposition=exactReplay`, conflicting reuse에서는 `duplicateActionIdDisposition=conflictReject` + `actionRejected(code=actionIdConflict)`를 실제로 유지하는지 parity 확인 필요

## Change Log
- 2026-03-08: `stateVersion`, `eventId`, reject reason, choice payload, snapshot/patch, replay contract, sample command/event payload 초안 구체화
- 2026-03-08: `MultiplayerContract.swift` 타입 매핑, `chrysanthemumRole` choice 확장, `get_multiplayer_projection` local preview entry point 반영
- 2026-03-08: `MultiplayerRoundEndedPayload` / `MultiplayerMatchEndedPayload` / terminal summary helper 추가, reconnect grace expiry를 `quit(reason=disconnectTimeout)` 경로로 고정
- 2026-03-08: fresh start bootstrap source를 paired `stateSnapshot(reason=gameStarted)`로 고정하고, `MultiplayerGameStartedPayload` / `get_multiplayer_game_started_bootstrap` preview helper를 추가
- 2026-03-08: `askingShake`를 viewer-scoped redaction으로 고치고, presence merge contract 및 actual starter/dealer payload 규칙을 반영
- 2026-03-09: local debug live bootstrap minimum set을 `MultiplayerGameStartedBootstrapPayload`로 고정하고, `GameManager` / `TestControlSupport` typed helper naming을 맞춤
- 2026-03-09: `MultiplayerLiveBootstrapPayload` UI-facing helper와 MP-008 `staleStateVersion -> stateSnapshot(reason=resync)` typed resync contract를 추가
- 2026-03-10: `MultiplayerTerminalSummaryPayload`, `matchEnded.roundIndex`, replay retention policy `privilegedDebugOnly`, relay-ready resync/reject envelope 예시를 추가
- 2026-03-10: `playCard` / `submitChoice` / `quit` transport relay-ready sample과 `dropGameEvents` future-extension 결정, authority-vs-room `playerId` mapping risk를 추가
- 2026-03-11: authority `playerId` vs room `playerId` mapping owner를 room/session layer로 고정하고, live stale recovery snapshot reason을 `resync` only로 제한했으며, transport terminal minimum payload를 다시 좁혀 sample로 남김
- 2026-03-11: authority identity field matrix와 terminal validator mutual-condition rule(`settlementSummary` vs `forfeitingPlayerId`)를 추가해 Agent 2 relay validator 해석 여지를 줄임
- 2026-03-11: websocket parity용 duplicate `actionId` exact replay / conflict reject sample과 precedence rule(`duplicate` resolution before `staleStateVersion`)을 추가
- 2026-03-12: duplicate `actionId` live parity artifact ruling을 추가해 exact resend/conflicting reuse의 source-of-truth 판정을 다시 명시
- 2026-03-12: reconnect-timeout terminal invariants, `roomClosed` terminal correlation carry-through rule, stale heartbeat explicit-reject owner ruling을 추가
- 2026-03-12: passive socket close도 same `quit(reason=disconnectTimeout)` terminal invariants와 cleanup correlation rule로 수렴해야 한다는 owner ruling을 추가
- 2026-03-14: server-owned timeout sweep도 same `quit(reason=disconnectTimeout)` terminal invariants로 수렴하고, dropped-event gap future extension도 same `stateSnapshot(reason=gapDetected)` minimum recovery contract를 유지한다는 owner ruling을 추가
- 2026-03-14: bootstrap split이 들어와도 authoritative bootstrap pair와 snapshot source-of-truth는 유지되고, gap future extension cursor metadata는 additive-only라는 owner ruling을 추가
- 2026-03-14: concrete bootstrap facade와 live gap hook surface가 생겨도 room-owned metadata일 뿐이며 authority pair/recovery payload는 대체할 수 없다는 owner ruling을 추가
- 2026-03-14: current concrete bootstrap facade와 explicit live gap recovery hook을 Phase 0 shipped boundary로 잠그고, REST bootstrap split / automatic dropped-event detection을 deferred scope로 명시
