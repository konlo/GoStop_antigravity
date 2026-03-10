# Minimum Automation Scope for UI Simulator Smoke Tests

## Objective
Establish a baseline for simulator-based UI testing that exercises the `MultiplayerShellState` integration in a deterministic test environment without relying on the full local real-time socket relay.

## Scope
1. **Entry to Room Transition:** Verifies that a generated `inviteCode` or `matchmaker` event correctly mutates `MultiplayerEntryShellState` to `MultiplayerRoomShellState`.
2. **Ready State Authority:** Verifies that pressing the "Ready" button emits a `SetReadyRequest` and the UI updates only after receiving a `roomSnapshot` update confirming `ready: true`.
3. **Bootstrap Handoff:** Asserts that when `roomState` transitions to `.inGame`, the live shell properly drops its loading overlay.
4. **Reconnect Visibility:** Confirms that a `disconnectedGrace` socket forces the `MultiplayerReconnectOverlay` to render and take input primacy over the live projection.
5. **Result Summary Routing:** Asserts that applying a `recordMatchEnded` event closes the Live route and correctly mounts `MultiplayerResultShellState` with proper score mapping.

## Not in Scope
- Full interactive live match play (requires engine logic parity with test runners).
- Socket connection failure retries from the WebSocket layer itself (this tests the Swift view behaviors given specific DTO payloads, mocking the connection).
