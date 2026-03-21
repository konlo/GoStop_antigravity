from __future__ import annotations

from .models import ScenarioDefinition
from .skeletons import SCENARIO_SKELETONS


def _p0_scenarios() -> list[ScenarioDefinition]:
    return [
        ScenarioDefinition(
            scenario_id="MP-001",
            name="Auto-start bootstrap reaches live match",
            priority="P0",
            automation="Scaffolded + CLI smoke + socket parity smoke",
            focus="room lifecycle + initial projection + ID continuity",
            description="Create room, join guest, set both players ready, and verify auto-start bootstrap into live match.",
            steps=[
                "Host creates room and persists room/session metadata.",
                "Host resolves invite through room_bootstrap_lookup_invite and preserves the concrete bootstrap boundary metadata.",
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
                "bootstrap boundaryVersion/currentBoundary/recommendedNextActions",
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
                "bootstrap_boundary_probe.json",
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
                "Socket mode validates the same paired bootstrap contract through both GoStopCLI TCP fallback and websocket transport facades.",
                "round15 smoke also locks the concrete bootstrap boundary through room_bootstrap_create/lookup_invite/join plus room_bootstrap_prepare_game_start preflight metadata, while keeping the canonical live bootstrap pair unchanged.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-002",
            name="Round completes with deterministic result summary",
            priority="P0",
            automation="Scaffolded + fixture + socket terminal parity smoke",
            focus="roundEnded/matchEnded + replay package",
            description="Play a full scripted round and persist the final summary in a replayable artifact set.",
            steps=[
                "Bootstrap a live match with deterministic inputs.",
                "Drive the terminal path and observe roundEnded/matchEnded/terminalSummary plus final roomClosed completion.",
                "Leave the ended room and verify roomClosed lifecycle completion.",
                "Persist terminal summary or the precise terminal relay failure in the replayable artifact set.",
            ],
            assertions=[
                "Exactly one terminal event is emitted for the round or match.",
                "Final summary is consistent across both player projections.",
                "Replay package contains enough data to reproduce the terminal result.",
                "Result dismissal reaches roomClosed after the final leaveRoom ack.",
            ],
            observability=[
                "last successful actionId before terminal event",
                "terminal eventId and stateVersion",
                "engine/rule version in replay manifest",
                "terminalSummary relay status and roomClosed roomSequence",
            ],
            required_events=[
                "gameEvent:actionAccepted",
                "gameEvent:statePatched",
                "gameEvent:turnChanged",
                "gameEvent:roundEnded|matchEnded",
                "terminalSummary",
                "roomEvent:roomClosed",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "replay/replay_manifest.json",
                "replay/event_stream.ndjson",
            ],
            notes=[
                "Fixture remains the source of truth for normal stop settlement consistency.",
                "Socket mode validates the actual terminal lifecycle over both TCP fallback and websocket transport, including roundEnded/matchEnded/terminalSummary fan-out and leaveRoom -> roomClosed completion.",
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
            automation="Scaffolded + socket duplicate replay smoke",
            focus="duplicate actionId + idempotent replay",
            description="Resend an identical command with the same actionId and confirm exact replay, then resend a conflicting payload and confirm conflictReject without a second mutation.",
            steps=[
                "Send one legal gameplay command with actionId act_dup_001.",
                "Resend the exact same payload with the same actionId after the first terminal result.",
                "Resend a conflicting payload with the same actionId and inspect conflict reject delivery plus stateVersion stability.",
            ],
            assertions=[
                "Duplicate resend does not create a second gameplay mutation.",
                "Exact duplicate returns the prior terminal result instead of a new mutation.",
                "Conflicting duplicate returns duplicateActionIdDisposition=conflictReject and actionRejected(code=actionIdConflict).",
                "No additional stateVersion bump occurs for the duplicate resend.",
            ],
            observability=[
                "first-seen and duplicate-seen timestamps",
                "actionId to requestId fan-out",
                "replayed eventId reuse",
                "conflict reject eventId and queuedEnvelopeCount",
            ],
            required_events=[
                "gameEvent:roundEnded|matchEnded",
                "gameEvent:actionRejected(code=actionIdConflict)",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "replay/event_stream.ndjson",
            ],
            notes=[
                "Socket smoke uses a legal quit command after bootstrap because it reaches a terminal result with stable event IDs on both TCP fallback and websocket transports.",
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
            automation="Scaffolded + fixture + socket automatic-timeout parity smoke",
            focus="passive disconnect binding + automatic expiry sweep + terminal forfeit ordering",
            description="Close the live transport connection, let the server-owned expiry sweep advance grace/retention automatically, and verify resume rejection plus terminal forfeit handling.",
            steps=[
                "Close one player's actual transport connection in starting or inGame.",
                "Advance beyond the 30 second reconnect grace without manually calling reapExpiredState.",
                "Attempt resume with the last valid session credentials.",
                "Persist resumeExpired plus synthetic quit(reason=disconnectTimeout) terminal room/game outcome.",
                "Wait for result retention expiry and verify roomClosed completion without manual transport mutations.",
            ],
            assertions=[
                "Passive close emits roomEvent(playerDisconnected) before timeout fan-out.",
                "Resume attempt is rejected after grace expiry.",
                "starting/inGame expiry leads to a forfeit path instead of silent closure.",
                "Terminal path emits actionAccepted, roundEnded, matchEnded, terminalSummary, and later roomClosed.",
                "Automatic expiry preserves the same terminal ordering on both TCP fallback and websocket transports.",
                "Terminal summary captures timeout/forfeit reason and affected actor.",
            ],
            observability=[
                "passiveCloseAt, disconnectObservedAt, terminalObservedAt, roomClosedObservedAt",
                "graceDeadlineAt, resumeAttemptAt",
                "terminal roomSequence, eventId, stateVersion",
                "resumeExpired error code and terminal summary reason",
            ],
            required_events=[
                "roomEvent:playerDisconnected",
                "error:resumeExpired",
                "gameEvent:actionAccepted",
                "gameEvent:roundEnded",
                "gameEvent:matchEnded",
                "terminalSummary",
                "roomEvent:playerForfeited",
                "roomEvent:roomClosed",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "timeout_probe.json",
                "anomaly_report.md",
            ],
            notes=[
                "Socket mode now binds actual passive socket close to the same timeout path and records the resulting disconnect/terminal/roomClosed ordering in timeout_probe.json.",
                "The locked live path is passiveClose -> playerDisconnected -> automatic expiry sweep -> actionAccepted -> roundEnded -> matchEnded -> roomEvent(playerForfeited/roomStateChanged) -> terminalSummary, then later roomClosed.",
                "manualReapUsed=false and progressionMode=automaticExpirySweep are now part of the timeout probe contract.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-008",
            name="StateVersion mismatch and gap recovery both converge on authoritative snapshots",
            priority="P0",
            automation="Scaffolded + fixture-backed stale-version resync + socket gameplay smoke",
            focus="staleStateVersion reject + gapRecoveryHint/gapDetected recovery path",
            description="Inject stale expectedStateVersion deterministically and exercise the live gap recovery hook so both resync paths converge on authoritative snapshots.",
            steps=[
                "Persist injectedMismatchMode=staleExpectedStateVersion and the fixed mismatch cursor before the command is sent.",
                "Send the next gameplay command with a stale expectedStateVersion override.",
                "Detect mismatch by actionRejected(rejectCode=staleStateVersion).",
                "Suspend input and wait for a resync snapshot.",
                "Fetch room_gap_recovery_shape and trigger the live gap recovery hook on the same transport session.",
                "Observe gapRecoveryHint followed by stateSnapshot(reason=gapDetected) and persist the recovery cursor.",
            ],
            assertions=[
                "Mismatch logs expose client/expected/authoritative versions plus authoritativeEventId.",
                "Input remains locked during resync.",
                "Resync snapshot restores hash equality before play resumes.",
                "gapRecoveryHint carries the minimum recovery fields plus inputLockRequired before gapDetected snapshot delivery.",
                "Injection manifest plus gap recovery probe are sufficient to replay the exact stale-version and gap-recovery fault paths.",
            ],
            observability=[
                "injectedMismatchMode and fixed mismatch cursor",
                "mismatch trigger reason",
                "resync latency",
                "gapRecoveryHint minimum field contract and live hint payload",
            ],
            required_events=[
                "gameEvent:actionRejected",
                "gameEvent:stateSnapshot(reason=resync)",
                "gapRecoveryHint",
                "gameEvent:stateSnapshot(reason=gapDetected)",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/assertions.ndjson",
                "timeline/events.ndjson",
                "timeline/mismatch.ndjson",
                "snapshots/latest_server.json",
                "replay/replay_manifest.json",
                "replay/injection_manifest.json",
                "replay/gap_recovery_shape.json",
                "replay/gap_recovery_probe.json",
                "replay/gap_injection_plan.json",
            ],
            notes=[
                "The locked deterministic mismatch path is stale expectedStateVersion override; live gap recovery now uses the explicit triggerGapRecovery hook.",
                "MP-008 should generate replay/injection_manifest.json plus timeline/mismatch.ndjson even when the run fails early.",
                "Socket mode now executes the live stale-version probe over TCP using a deterministic quit command after start_game warmup.",
                "Current live socket smoke asserts actionRejected(staleStateVersion) plus stateSnapshot(reason=resync), then triggerGapRecovery plus stateSnapshot(reason=gapDetected) on the same transport run.",
                "playCard mapping drift is no longer a blocker for the locked P0 quit-based resync path.",
                "round15 smoke also executes the live triggerGapRecovery hook and persists replay/gap_recovery_probe.json so the gapRecoveryHint minimum fields and stateSnapshot(reason=gapDetected) recovery envelope are no longer preflight-only.",
                "The remaining future-extension plan is deterministic dropped-event injection that records targetClientId, droppedEnvelopeCount, lastDeliveredEventId, nextAuthoritativeEventId, dropAfterEnvelopeType/gameEventName, follow-up actionId, and expected gapDetected recovery snapshot fields before any auto-detection probe is attempted.",
            ],
        ),
    ]


def _review_regression_scenarios() -> list[ScenarioDefinition]:
    return [
        ScenarioDefinition(
            scenario_id="MP-013",
            name="Shake choice hides actor-only hand data from non-actor viewers",
            priority="P1",
            automation="Fixture-backed + socket parity smoke",
            focus="askingShake privacy + viewer-scoped redaction",
            description="Trigger askingShake and verify actor projection keeps option metadata while non-actor projection is redacted.",
            steps=[
                "Drive the match into askingShake with actor player A.",
                "Persist actor and non-actor snapshots for the same choiceId.",
                "Compare viewer-scoped payloads for cards, metadata, and visibility fields.",
            ],
            assertions=[
                "Actor snapshot exposes shake options with actorOnly visibility.",
                "Non-actor snapshot keeps the same choiceId and option labels but redacts cards and hand metadata.",
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
            notes=[
                "Fixture mode remains the deterministic baseline for actorOnly shake redaction.",
                "Socket mode reuses the same actor/peer projection assertions over TCP fallback and websocket transport so the privacy regression can be replayed when app-side websocket binding lands.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-014",
            name="Stale or replaced heartbeat is rejected without session rollback",
            priority="P1",
            automation="Fixture-backed + socket parity smoke",
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
                "heartbeat_probe.json",
                "stale_heartbeat_code_probe.json",
            ],
            notes=[
                "Agent 2 locked Phase 0 heartbeat handling to explicit reject, not audit-only ignore.",
                "Socket compare smoke keeps invalidResumeState and staleConnectionId parity on both TCP fallback and websocket transports.",
                "The websocket debug-connect baseline is the same command surface used by MultiplayerWebSocketCommandNetworkingAdapter: room_transport_send(action=ack).",
                "stale_heartbeat_code_probe.json stores the raw websocket command error envelopes alongside the CLI ingress baseline codes so drift is visible immediately.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-015",
            name="Ready stays local until the room reaches waitingForReady",
            priority="P1",
            automation="Fixture-backed regression",
            focus="premature ready guard + product autoroute defer",
            description="Keep the host in waitingForPlayers until a second member joins, and verify local UI/autoroute does not send setReady early or trigger a passive disconnect.",
            steps=[
                "Host creates a room and lands on the room route with only one connected member.",
                "A local ready attempt occurs while the authoritative room is still waitingForPlayers.",
                "The shell keeps the ready action local and waits for a second member before enabling authoritative ready dispatch.",
                "Once the guest joins, the room advances to waitingForReady without any playerDisconnected side effect.",
            ],
            assertions=[
                "No authoritative setReady command is sent while the room is waitingForPlayers.",
                "No invalidRoomState error or playerDisconnected event is emitted from the premature local ready attempt.",
                "The room reaches waitingForReady with two connected members and the local member still not ready.",
            ],
            observability=[
                "local guard result for the premature ready attempt",
                "roomSnapshot roomState timeline before and after memberJoined",
                "absence of invalidRoomState and playerDisconnected around the deferred ready window",
            ],
            required_events=[
                "roomSnapshot(waitingForPlayers)",
                "roomEvent:memberJoined",
                "roomSnapshot(waitingForReady)",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
            ],
            notes=[
                "This regression specifically protects the product autoroute path from sending ready before the second seat exists.",
                "The local shell guard should fail fast before websocket transport invalidation can cascade into passive disconnect.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-016",
            name="Seeded multiplayer match finishes end-to-end while every go-stop choice selects go",
            priority="P1",
            automation="Fixture-backed regression + socket live end-to-end",
            focus="full-match gameplay progression + always-go decision policy + terminal close",
            description=(
                "Bootstrap a real multiplayer room, drive legal gameplay actions from both seats, "
                "choose go for every go-stop prompt, and verify the match still reaches terminalSummary "
                "plus final roomClosed."
            ),
            steps=[
                "Seed the authoritative board and bootstrap a two-player room into live gameplay.",
                "On each turn, send a legal playCard from the acting player's visible hand.",
                "When choicePending appears, resolve capture with the first legal table option, decline shake, choose a deterministic chrysanthemum role, and always submit go for go-stop.",
                "Continue until roundEnded/matchEnded/terminalSummary is observed, then send leaveRoom from both clients and wait for roomClosed.",
            ],
            assertions=[
                "The live match reaches terminalSummary without outOfTurn, invalidPhase, invalidCard, or invalidChoice rejects.",
                "Every chooseGoStop submission uses optionCode=go; stop is never sent.",
                "At least one go-stop prompt is encountered on the seeded path so the always-go policy is exercised.",
                "Final leaveRoom lifecycle closes the room with roomClosed and roomState=closed.",
            ],
            observability=[
                "selected deterministic seed and per-seed attempt summaries",
                "playCard / submitChoice action timeline with authoritative stateVersion",
                "go-stop optionCode history and terminalSummary matchEnded payload",
                "roomClosed labels and closed room snapshot after both clients leave",
            ],
            required_events=[
                "gameEvent:actionAccepted",
                "gameEvent:choiceRequested",
                "terminalSummary",
                "roomEvent:roomClosed",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "always_go_probe.json",
            ],
            notes=[
                "The live implementation may iterate a small deterministic seed set until it finds a match that surfaces at least one go-stop prompt; the chosen seed is recorded in always_go_probe.json.",
                "Capture and chrysanthemum choices stay deterministic by selecting the first authoritative option, while shake declines to keep the run reproducible.",
            ],
        ),
        ScenarioDefinition(
            scenario_id="MP-017",
            name="Short multiplayer UI probe keeps captured cards visible before the turn hands off",
            priority="P1",
            automation="Fixture-backed regression + simulator UI authoritative probe",
            focus="captured-zone projection parity during the first two turns per seat",
            description=(
                "Run a live two-player room for exactly two turns per player, compare simulator-rendered captured zones "
                "against authoritative room projections, and fail if a captured card only appears after the next turn begins."
            ),
            steps=[
                "Create and join a real multiplayer invite room, then auto-ready into live gameplay.",
                "Drive at most two legal playCard turns from the host and two from the guest, resolving any pending capture or role choices deterministically.",
                "After each turn, fetch authoritative room projections for both seats and compare captured totals against the simulator-rendered captured zones.",
                "Fail immediately if authoritative captured cards exist for the acting player once the turn hands off but either simulator still renders the old captured total.",
            ],
            assertions=[
                "The scenario completes exactly two playCard turns per seat without invalidPhase, invalidCard, outOfTurn, or invalidChoice rejects.",
                "At least one authoritative capture occurs during the four-turn probe so captured-zone parity is exercised.",
                "Whenever authoritative captured totals increase for the acting player, both simulator UIs show the new captured total before the turn hands off to the opponent.",
            ],
            observability=[
                "host/guest simulator live snapshots with rendered captured totals",
                "authoritative room_projection_preview snapshots for both room players",
                "per-turn probe rows recording baseline totals, authoritative capture version, and rendered visibility version",
            ],
            required_events=[
                "gameEvent:actionAccepted",
                "gameEvent:statePatched",
                "gameEvent:turnChanged",
            ],
            required_artifacts=[
                "manifest.json",
                "timeline/commands.ndjson",
                "timeline/events.ndjson",
                "snapshots/latest_server.json",
                "capture_visibility_probe.json",
            ],
            notes=[
                "The UI probe may retry a small number of fresh rooms until at least one capture occurs within the first four turns.",
                "This regression specifically guards the multiplayer shell path where statePatched previously lagged behind turnChanged and full gameSnapshot refresh.",
            ],
        ),
    ]


P0_SCENARIOS = _p0_scenarios()
REVIEW_REGRESSION_SCENARIOS = _review_regression_scenarios()
ALL_SCENARIOS = [*P0_SCENARIOS, *REVIEW_REGRESSION_SCENARIOS]
SCENARIO_REGISTRY = {scenario.scenario_id: scenario for scenario in ALL_SCENARIOS}
SMOKE_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-001", "MP-006")]
SOCKET_SMOKE_SCENARIOS = [
    SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-001", "MP-002", "MP-007", "MP-008", "MP-014")
]
SOCKET_END_TO_END_SCENARIOS = [SCENARIO_REGISTRY["MP-016"]]
SOCKET_CAPTURE_VISIBILITY_SCENARIOS = [SCENARIO_REGISTRY["MP-017"]]
SOCKET_PARITY_SCENARIOS = [
    SCENARIO_REGISTRY[scenario_id]
    for scenario_id in ("MP-001", "MP-002", "MP-004", "MP-007", "MP-008", "MP-013", "MP-014")
]
FINAL_VALIDATION_SCENARIOS = list(SOCKET_PARITY_SCENARIOS)
SOCKET_DUPLICATE_SCENARIOS = [SCENARIO_REGISTRY["MP-004"]]
SOCKET_REVIEW_FIXUP_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-013", "MP-014")]
REVIEW_FIXUP_SCENARIOS = [SCENARIO_REGISTRY[scenario_id] for scenario_id in ("MP-013", "MP-014", "MP-015", "MP-016", "MP-017")]
SCENARIO_SUITES = {
    "smoke": SMOKE_SCENARIOS,
    "socket-smoke": SOCKET_SMOKE_SCENARIOS,
    "socket-end-to-end": SOCKET_END_TO_END_SCENARIOS,
    "socket-capture-visibility": SOCKET_CAPTURE_VISIBILITY_SCENARIOS,
    "socket-parity": SOCKET_PARITY_SCENARIOS,
    "socket-duplicate": SOCKET_DUPLICATE_SCENARIOS,
    "socket-review-fixups": SOCKET_REVIEW_FIXUP_SCENARIOS,
    "review-fixups": REVIEW_FIXUP_SCENARIOS,
    "final-validation": FINAL_VALIDATION_SCENARIOS,
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
