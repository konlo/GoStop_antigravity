from __future__ import annotations

from .models import ScenarioDefinition
from .skeletons import SCENARIO_SKELETONS


def _p0_scenarios() -> list[ScenarioDefinition]:
    return [
        ScenarioDefinition(
            scenario_id="MP-001",
            name="Auto-start bootstrap reaches live match",
            priority="P0",
            automation="Scaffolded + CLI smoke + socket smoke",
            focus="room lifecycle + initial projection + ID continuity",
            description="Create room, join guest, set both players ready, and verify auto-start bootstrap into live match.",
            steps=[
                "Host creates room and persists room/session metadata.",
                "Guest joins room and both clients attach via hello/helloAck.",
                "Both players call setReady and observe memberReadyChanged.",
                "Room transitions waitingForPlayers -> waitingForReady -> starting -> inGame.",
                "Clients consume paired gameStarted and stateSnapshot(reason=gameStarted).",
            ],
            assertions=[
                "Auto-start occurs without a public startGame command.",
                "activeGameId is assigned once and matches the gameStarted payload.",
                "stateSnapshot(reason=gameStarted) is the source of truth for the initial projection.",
                "Initial projection includes stateVersion, turnId, and currentPlayerId.",
                "traceId, roomId, and gameId stay stable across room and game events.",
            ],
            observability=[
                "roomSequence timeline for roomStateChanged",
                "first eventId and stateVersion",
                "initial snapshot hash per player scope",
            ],
            required_events=[
                "roomSnapshot",
                "roomEvent:memberJoined",
                "roomEvent:memberReadyChanged",
                "roomEvent:roomStateChanged",
                "gameEvent:gameStarted",
                "gameEvent:stateSnapshot",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/events.ndjson",
                "snapshots/player_a_initial.json",
                "snapshots/player_b_initial.json",
                "replay/replay_manifest.json",
            ],
            transport_sequence=[
                "helloAck",
                "roomSnapshot",
                "roomEvent.memberReadyChanged",
                "roomEvent.roomStateChanged(starting)",
                "gameEvent.engineEvent:gameStarted",
                "gameEvent.engineEvent:stateSnapshot(reason=gameStarted)",
            ],
            notes=[
                "CLI smoke explicitly drives room_record_game_started and then fetches get_multiplayer_game_started_bootstrap to assert the paired bootstrap payload.",
                "Socket mode now validates the same paired bootstrap contract through room_transport_connect/send/receive, but it still does not prove a future external websocket server binding.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-002",
            name="Round completes with deterministic result summary",
            priority="P0",
            automation="Scaffolded",
            focus="roundEnded/matchEnded + replay package",
            description="Play a full scripted round and persist the final summary in a replayable artifact set.",
            steps=[
                "Bootstrap a live match with deterministic inputs.",
                "Send only legal commands until roundEnded or matchEnded.",
                "Persist terminal summary, final snapshots, and replay manifest.",
            ],
            assertions=[
                "Exactly one terminal event is emitted for the round or match.",
                "Final summary is consistent across both player projections.",
                "Replay package contains enough data to reproduce the terminal result.",
            ],
            observability=[
                "last successful actionId before terminal event",
                "terminal eventId and stateVersion",
                "engine/rule version in replay manifest",
            ],
            required_events=[
                "gameEvent:actionAccepted",
                "gameEvent:statePatched",
                "gameEvent:turnChanged",
                "gameEvent:roundEnded|matchEnded",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "replay/replay_manifest.json",
                "replay/event_stream.ndjson",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-003",
            name="Out-of-turn action is rejected without state mutation",
            priority="P0",
            automation="Scaffolded",
            focus="actionRejected correlation + no mutation guarantee",
            description="Attempt a playCard from the non-turn owner and verify a pure reject path.",
            steps=[
                "Reach a stable inTurn state with currentPlayerId owned by player A.",
                "Player B sends playCard with a fresh actionId.",
                "Record reject payload and post-reject snapshot hash.",
            ],
            assertions=[
                "Reject code is outOfTurn.",
                "stateVersion is unchanged across the reject.",
                "No actionAccepted or gameplay mutation event is correlated to the rejected actionId.",
            ],
            observability=[
                "turnId and currentPlayerId at reject time",
                "pre/post reject state hash",
                "reject code distribution",
            ],
            required_events=[
                "gameEvent:actionRejected",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-004",
            name="Exact duplicate actionId replays prior terminal result",
            priority="P0",
            automation="Scaffolded",
            focus="duplicate actionId + idempotent replay",
            description="Resend an identical command with the same actionId and confirm replay without a second mutation.",
            steps=[
                "Send one legal playCard with actionId act_dup_001.",
                "Resend the exact same payload with the same actionId after the first terminal result.",
                "Inspect eventId reuse and stateVersion stability.",
            ],
            assertions=[
                "Duplicate resend does not create a second gameplay mutation.",
                "Exact duplicate returns the prior terminal result instead of a new mutation.",
                "No additional stateVersion bump occurs for the duplicate resend.",
            ],
            observability=[
                "first-seen and duplicate-seen timestamps",
                "actionId to requestId fan-out",
                "replayed eventId reuse",
            ],
            required_events=[
                "gameEvent:actionAccepted",
                "gameEvent:statePatched|stateSnapshot",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "replay/event_stream.ndjson",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-005",
            name="Invalid choice code is rejected while choice remains pending",
            priority="P0",
            automation="Scaffolded",
            focus="choice mismatch + pendingChoice stability",
            description="Trigger choiceRequested, send an invalid optionCode or stale choiceId, and validate invalidChoice handling.",
            steps=[
                "Drive the game into choicePending.",
                "Persist the authoritative choiceRequested payload.",
                "Send a malformed or stale choice submission.",
                "Confirm invalidChoice reject and intact pending choice.",
            ],
            assertions=[
                "Reject code is invalidChoice.",
                "Reject payload carries choiceId, choiceKind, rejected code, and latest stateVersion.",
                "Pending choice is not consumed or replaced by the invalid submission alone.",
            ],
            observability=[
                "choiceRequested payload hash",
                "reject payload correlation fields",
                "pending choice snapshot after reject",
            ],
            required_events=[
                "gameEvent:choiceRequested",
                "gameEvent:actionRejected",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-006",
            name="Reconnect succeeds inside 30 second grace window",
            priority="P0",
            automation="Scaffolded",
            focus="snapshot-first resume + input lock release",
            description="Disconnect one player, reconnect inside the grace window, and verify snapshot-first recovery ordering.",
            steps=[
                "Reach a live match and drop player B transport.",
                "Observe roomEvent.playerDisconnected with grace deadline.",
                "Reconnect with hello/helloAck inside 30 seconds.",
                "Consume roomSnapshot then gameEvent(stateSnapshot reason=resume) before live traffic resumes.",
            ],
            assertions=[
                "Resume succeeds only within the 30 second grace window.",
                "Reconnecting client sees helloAck -> roomSnapshot -> gameEvent(stateSnapshot) -> live events.",
                "playerReconnected is delivered after snapshots on the reconnecting socket.",
                "Local snapshot hash matches the authoritative resume snapshot before input unlock.",
            ],
            observability=[
                "disconnectAt, reconnectAt, recoveryCompleteAt",
                "messageId, roomSequence, eventId ordering",
                "resume latency",
            ],
            required_events=[
                "roomEvent:playerDisconnected",
                "roomSnapshot",
                "gameEvent:stateSnapshot",
                "roomEvent:playerReconnected",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "ui/reconnect.png",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-007",
            name="Reconnect expiry triggers forfeit path",
            priority="P0",
            automation="Scaffolded",
            focus="resumeExpired + terminal forfeit ordering",
            description="Let reconnect grace expire and verify resume rejection plus terminal forfeit handling.",
            steps=[
                "Disconnect a player in starting or inGame.",
                "Advance beyond the 30 second reconnect grace.",
                "Attempt resume with the last valid session credentials.",
                "Persist resumeExpired and terminal room/game outcome.",
            ],
            assertions=[
                "Resume attempt is rejected after grace expiry.",
                "starting/inGame expiry leads to a forfeit path instead of silent closure.",
                "Terminal summary captures timeout/forfeit reason and affected actor.",
            ],
            observability=[
                "disconnectAt, graceDeadlineAt, resumeAttemptAt",
                "terminal roomSequence, eventId, stateVersion",
                "resumeExpired error code and terminal summary reason",
            ],
            required_events=[
                "roomEvent:playerDisconnected",
                "error:resumeExpired",
                "roomEvent:playerForfeited|roomEvent:roomClosed",
                "gameEvent:matchEnded",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "anomaly_report.md",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-008",
            name="StateVersion mismatch recovers through authoritative snapshot",
            priority="P0",
            automation="Scaffolded + fixture-backed stale-version resync + socket preflight",
            focus="staleStateVersion reject + authoritative resync snapshot path",
            description="Inject stale expectedStateVersion deterministically and recover via stateSnapshot(reason=resync).",
            steps=[
                "Persist injectedMismatchMode=staleExpectedStateVersion and the fixed mismatch cursor before the command is sent.",
                "Send the next command with a stale expectedStateVersion override.",
                "Detect mismatch by actionRejected(rejectCode=staleStateVersion).",
                "Suspend input and wait for a resync snapshot.",
                "Resume live play after the snapshot hash matches the server hash.",
            ],
            assertions=[
                "Mismatch logs expose client/expected/authoritative versions plus authoritativeEventId.",
                "Input remains locked during resync.",
                "Resync snapshot restores hash equality before play resumes.",
                "Injection manifest is sufficient to replay the exact stale-version fault path.",
            ],
            observability=[
                "injectedMismatchMode and fixed mismatch cursor",
                "mismatch trigger reason",
                "resync latency",
            ],
            required_events=[
                "gameEvent:actionRejected",
                "gameEvent:stateSnapshot",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/assertions.ndjson",
                "timeline/events.ndjson",
                "timeline/mismatch.ndjson",
                "snapshots/latest_server.json",
                "replay/replay_manifest.json",
                "replay/injection_manifest.json",
            ],
            notes=[
                "The locked deterministic path is stale expectedStateVersion override; dropped event gap remains a future extension.",
                "MP-008 should generate replay/injection_manifest.json plus timeline/mismatch.ndjson even when the run fails early.",
                "Socket mode can now prove live bootstrap + hook attachment, but full gameplay resync stays blocked until room_transport_send exposes gameplay commands with expectedStateVersion.",
            ],
        ),
    ]


def _review_regression_scenarios() -> list[ScenarioDefinition]:
    return [
        ScenarioDefinition(
            scenario_id="MP-013",
            name="Shake choice hides actor-only hand data from non-actor viewers",
            priority="P1",
            automation="Fixture-backed",
            focus="askingShake privacy + viewer-scoped redaction",
            description="Trigger askingShake and verify actor projection keeps option metadata while non-actor projection is redacted.",
            steps=[
                "Drive the match into askingShake with actor player A.",
                "Persist actor and non-actor snapshots for the same choiceId.",
                "Compare viewer-scoped payloads for cards, metadata, and visibility fields.",
            ],
            assertions=[
                "Actor snapshot exposes shake options with actorOnly visibility.",
                "Non-actor snapshot keeps the same choiceId but redacts cards and hand metadata.",
                "No hidden hand identifier leaks through summary, metadata, or option payloads.",
            ],
            observability=[
                "choiceId and visibility per viewer scope",
                "actor vs peer choice payload hash",
                "redacted field list for non-actor projection",
            ],
            required_events=[
                "gameEvent:choiceRequested",
                "gameEvent:stateSnapshot",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/events.ndjson",
                "snapshots/player_a_initial.json",
                "snapshots/player_b_initial.json",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-014",
            name="Stale or replaced heartbeat is rejected without session rollback",
            priority="P1",
            automation="Fixture-backed + socket smoke",
            focus="newest-wins heartbeat guard + stale connection rejection",
            description="Send heartbeat from disconnected or replaced connection ownership and verify error surfacing plus stable current session binding.",
            steps=[
                "Disconnect or replace one player's active connection.",
                "Send heartbeat from the stale session state and stale connectionId.",
                "Verify the current connection binding and last heartbeat cursor stay owned by the newest valid connection.",
            ],
            assertions=[
                "Heartbeat from disconnectedGrace session is rejected with invalidResumeState.",
                "Heartbeat from replaced connectionId is rejected with staleConnectionId.",
                "Current session ownership and connectedConnectionId remain bound to the newest connection after both rejects.",
            ],
            observability=[
                "sessionId, old connectionId, new connectionId",
                "heartbeat reject errorCode distribution",
                "post-reject connectedConnectionId and lastAckedRoomSequence",
            ],
            required_events=[
                "error:invalidResumeState",
                "helloAck",
                "error:staleConnectionId",
                "roomSnapshot",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
            ],
        ),
    ]


P0_SCENARIOS = _p0_scenarios()
REVIEW_REGRESSION_SCENARIOS = _review_regression_scenarios()
ALL_SCENARIOS = [*P0_SCENARIOS, *REVIEW_REGRESSION_SCENARIOS]
SCENARIO_REGISTRY = {scenario.scenario_id: scenario for scenario in ALL_SCENARIOS}
SMOKE_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-001", "MP-006")]
SOCKET_SMOKE_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-001", "MP-014")]
REVIEW_FIXUP_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-013", "MP-014")]
SCENARIO_SUITES = {
    "smoke": SMOKE_SCENARIOS,
    "socket-smoke": SOCKET_SMOKE_SCENARIOS,
    "review-fixups": REVIEW_FIXUP_SCENARIOS,
    "all": ALL_SCENARIOS,
}

if set(SCENARIO_REGISTRY) != set(SCENARIO_SKELETONS):
    missing_in_skeletons = sorted(set(SCENARIO_REGISTRY) - set(SCENARIO_SKELETONS))
    missing_in_registry = sorted(set(SCENARIO_SKELETONS) - set(SCENARIO_REGISTRY))
    raise RuntimeError(
        "Scenario registry and skeleton registry diverged. "
        f"missing_in_skeletons={missing_in_skeletons} "
        f"missing_in_registry={missing_in_registry}"
    )
