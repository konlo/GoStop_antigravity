# Anomaly Report Template

## Match Identification
- **Room ID:**
- **Game ID:**
- **Occurrence Time (UTC):**
- **Trigger Scenario / Phase:** (e.g., Bootstrap, Live Resync, Reconnect, Ended)

## Observed Symptoms
- **Reported By:** (e.g., Host Agent, Guest Agent, Test Scaffold)
- **High-Level Symptom:** (e.g., Client stuck in choicePending, Desync detected, Bootstrap timeout)

## State Evidence
### Host State Context
- Last Acked Sequence:
- Expected State Version:

### Guest State Context
- Last Acked Sequence:
- Expected State Version:

### Discrepancy Description
- **Authority Snapshot vs Render Snapshot:**
- **Missing Event IDs:**
- **Patch Application Error:**

## Required Replay Artifacts
- [ ] `engine-<GameID>-dump.json`
- [ ] `multiplayer-events-<RoomID>-host.json`
- [ ] `multiplayer-events-<RoomID>-guest.json`
- [ ] `snapshot-<RoomID>-<Version>.json` (if applicable)

## Reproduction Steps
1. 
2. 
3. 

## Initial Triage / Mitigation Notes
- *Suspected Component (RoomCoordinator / Relay / GameManager):*
- *Temporary Workaround:*
