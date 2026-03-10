# Socket Transport Binding Design for Scaffold Runner

## Overview
The `scaffold runner` currently relies on `fixture` modes and CLI-based stateless runs. To execute scenarios live against the actual game server, we need a WebSocket binding layer that translates scenario steps into real network payloads and validates responses asynchronously.

## Core Components
1. **`SocketClient` wrapper**
   - Manages the WebSocket lifecycle (connect, authenticate, message loop, disconnect).
   - Translates synchronous scaffold steps (e.g., `send_action(actionId)`) into async JSON payloads over the network.
2. **`EventCollector`**
   - Listens to incoming server messages (`roomSnapshot`, `gameEvent`, `actionRejected`, etc.).
   - Buffers messages into a strict sequence for the validator to assert against.
3. **`Synchronizer`**
   - Allows scenario blocks to `await_event(type="gameStarted", timeout=5.0)` to bridge the async network reality with the linear test script structure.

## Integration Path
1. Update `tests/test_agent/multiplayer/runner.py` to support `--mode socket`.
2. Introduce `SocketMultiplayerScenarioRunner(ScaffoldRunner)` that instantiates two `SocketClient`s (Host and Guest).
3. Map `test_scenarios.py` standard skeletons (`send(createRoom)`, `send(joinRoom)`) to invoke `host_socket.send()` and `guest_socket.send()`.
4. Artifact generation (`manifest.json`, `events.ndjson`) will listen to the `EventCollector` buffers and write them out identically to the `fixture` mode.

## Example Flow
```python
# During MP-001 (Room Bootstrap)
host.connect()
host.send_command("createRoom")
room_created = host.await_event("roomCreated", timeout=2.0)
room_id = room_created.payload.roomId

guest.connect()
guest.send_command("joinRoom", roomId=room_id)
guest.await_event("playerJoined")

host.send_command("setReady")
guest.send_command("setReady")

# Both await authoritative bootstrap
host.await_event("gameStarted", timeout=5.0)
host.await_event("stateSnapshot", reason="gameStarted", timeout=1.0)
```
