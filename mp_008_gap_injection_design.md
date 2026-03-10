# Dropped Game Event Gap Injection Design

## Goal
To extend `MP-008` (stateVersion mismatch) testing, we need a mechanism to simulate dropped `gameEvent` messages over the WebSocket transport, causing the client local projection to fall behind the authoritative engine without simply overriding the `expectedStateVersion` field.

## Scope
- This applies to the `socket` execution mode once real client/server transport is wired.
- It validates the `gapDetected` resync reason instead of the `staleStateVersion` reject reason.

## Mechanism

### Engine Level (`GameManager`)
The authoritative engine will ignore this simulation. The engine emits exact monotonic sequences.

### Transport Level (`RoomCoordinator` or `Socket Relay`)
We will add a deterministic hook `RoomDeterministicFaultHook.kind = .dropGameEvents`.

```swift
enum RoomDeterministicFaultHookKind: String, Codable {
    case staleExpectedStateVersionOverride // Existing
    case dropGameEvents                    // New
}

struct RoomDeterministicFaultHook: Codable {
    let kind: RoomDeterministicFaultHookKind
    let targetSessionId: String
    
    // For staleExpectedStateVersionOverride
    let overriddenExpectedStateVersion: Int?
    
    // For dropGameEvents
    let dropCount: Int?
}
```

When the `RoomCoordinator` or WebSocket layer relays an `engineEvent` (e.g., `actionAccepted` or `turnChanged`), it checks if `dropGameEvents` is active for the target session. If so, it decrements the `dropCount` and simply swallows the message instead of pushing it down the websocket.

### Client Behavior & Resync Trigger
When the client successfully submits their next `playCard`:
1. The client expects `expectedStateVersion` to be `N`.
2. Because they missed an `actionAccepted` mutation, the server actually expects `N+1`.
3. The server rejects the action with `rejectCode = staleStateVersion`.
4. The server sees the gap and initiates an authoritative resync, but since it's a transport gap masking as a stale input, the `reason` mapped to the snapshot recovery should explicitly mention the resync logic. Since the client may ALSO have missed patching commands, `stateSnapshot(reason=resync)` remains the universal recovery payload.

## Artifact Impact
The `replay/injection_manifest.json` will capture:
```json
{
  "injectedMismatchMode": "dropGameEvents",
  "dropCount": 1,
  ...
}
```

## Rollout Plan
1. Add `dropGameEvents` to Swift `RoomDeterministicFaultHook`.
2. Handle the drop logic in the actual socket transport loop (Phase 6/7).
3. Update Python assertions to look for `injectedMismatchMode=dropGameEvents` when running the network version of `MP-008`.
