from __future__ import annotations

from .fixtures import FIXTURE_LIBRARY
from .models import ScenarioDefinition, ScenarioStatus


def validate_fixture(scenario: ScenarioDefinition) -> tuple[ScenarioStatus, str, list[str]]:
    fixture = FIXTURE_LIBRARY[scenario.scenario_id]
    status = ScenarioStatus(fixture["status"])
    if status is not ScenarioStatus.PASS:
        return status, fixture["summary"], list(fixture.get("blockingReasons", scenario.contract_questions))

    validator = _PASS_VALIDATORS.get(scenario.scenario_id)
    if validator is None:
        return ScenarioStatus.PASS, fixture["summary"], []

    validator(fixture)
    return ScenarioStatus.PASS, fixture["summary"], []


def _pass_frames(fixture: dict) -> list[dict]:
    return list(fixture["frames"])


def _pass_snapshots(fixture: dict) -> dict:
    return dict(fixture["snapshots"])


def _validate_mp_003(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    rejected = [frame for frame in frames if frame.get("engineEventName") == "actionRejected"]
    assert len(rejected) == 1, "Expected exactly one actionRejected frame."
    reject = rejected[0]
    assert reject.get("rejectCode") == "outOfTurn", "Expected outOfTurn reject."
    assert reject.get("stateVersion") == 11, "Expected unchanged stateVersion 11."
    assert not any(frame.get("engineEventName") == "actionAccepted" for frame in frames), "Unexpected actionAccepted frame."
    latest = _pass_snapshots(fixture)["latest_server"]
    assert latest["state_version"] == 11, "Latest authority snapshot should keep stateVersion 11."


def _validate_mp_001(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    game_started = next(frame for frame in frames if frame.get("engineEventName") == "gameStarted")
    state_snapshot = next(frame for frame in frames if frame.get("engineEventName") == "stateSnapshot")
    assert game_started["snapshotId"] == state_snapshot["snapshotId"], "gameStarted should correlate to the paired snapshot."
    assert state_snapshot["reason"] == "gameStarted", "Fresh start should use stateSnapshot(reason=gameStarted)."
    latest = _pass_snapshots(fixture)["latest_server"]
    assert state_snapshot["stateHash"] == latest["state_hash"], "Snapshot should remain the state source of truth."


def _validate_mp_002(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    round_ended = next(frame for frame in frames if frame.get("engineEventName") == "roundEnded")
    match_ended = next(frame for frame in frames if frame.get("engineEventName") == "matchEnded")
    assert round_ended["winnerPlayerId"] == match_ended["winnerPlayerId"] == "player_a", "Winner should be stable."
    assert round_ended["loserPlayerId"] == match_ended["loserPlayerId"] == "player_b", "Loser should be stable."
    assert round_ended["settlementSummary"] == match_ended["settlementSummary"], "Settlement summary should be shared."
    latest = _pass_snapshots(fixture)["latest_server"]["payload"]
    assert latest["endReason"] == "stop", "Expected normal stop terminal reason."
    assert latest["forfeitingPlayerId"] is None, "Normal stop should not assign a forfeiting player."


def _validate_mp_004(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    accepted = [frame for frame in frames if frame.get("engineEventName") == "actionAccepted"]
    patched = [frame for frame in frames if frame.get("engineEventName") == "statePatched"]
    assert len(accepted) == 2 and len(patched) == 2, "Expected original + replay event pairs."
    assert accepted[0]["eventId"] == accepted[1]["eventId"], "Duplicate replay should reuse actionAccepted eventId."
    assert patched[0]["eventId"] == patched[1]["eventId"], "Duplicate replay should reuse statePatched eventId."
    assert {frame["stateVersion"] for frame in frames} == {21}, "Duplicate replay must not create a second stateVersion."


def _validate_mp_005(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    choice = next(frame for frame in frames if frame.get("engineEventName") == "choiceRequested")
    reject = next(frame for frame in frames if frame.get("engineEventName") == "actionRejected")
    assert reject.get("rejectCode") == "invalidChoice", "Expected invalidChoice reject."
    assert reject.get("choiceId") == choice.get("choiceId"), "Reject must point at the active choice."
    latest = _pass_snapshots(fixture)["latest_server"]
    assert latest["payload"]["pendingChoice"]["choiceId"] == choice.get("choiceId"), "Pending choice should remain active."


def _validate_mp_006(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    sequence = [
        (
            frame["transportType"],
            frame.get("eventName") or frame.get("engineEventName"),
        )
        for frame in frames
    ]
    expected = [
        ("roomEvent", "playerDisconnected"),
        ("helloAck", None),
        ("roomSnapshot", None),
        ("gameEvent", "stateSnapshot"),
        ("roomEvent", "playerReconnected"),
        ("gameEvent", "turnChanged"),
    ]
    assert sequence == expected, f"Unexpected reconnect sequence: {sequence}"
    state_snapshot = next(frame for frame in frames if frame.get("engineEventName") == "stateSnapshot")
    latest = _pass_snapshots(fixture)["latest_server"]
    assert state_snapshot.get("reason") == "resume", "Expected resume snapshot."
    assert state_snapshot.get("stateHash") == latest["state_hash"], "Resume hash must match authority snapshot."


def _validate_mp_007(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    resume_expired = next(frame for frame in frames if frame.get("transportType") == "error")
    forfeited = next(frame for frame in frames if frame.get("eventName") == "playerForfeited")
    match_ended = next(frame for frame in frames if frame.get("engineEventName") == "matchEnded")
    assert resume_expired["errorCode"] == "resumeExpired", "Expected resumeExpired error."
    assert forfeited["reason"] == "disconnectTimeout", "Forfeit should use disconnectTimeout reason."
    assert match_ended["endReason"] == "disconnectTimeout", "Terminal summary should surface disconnectTimeout."
    assert match_ended["forfeitingPlayerId"] == "player_b", "Terminal summary should identify the forfeiting player."
    assert match_ended["settlementSummary"] is None, "Forfeit path should keep settlementSummary null."


def _validate_mp_008(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    reject = next(frame for frame in frames if frame.get("engineEventName") == "actionRejected")
    recovery = next(frame for frame in frames if frame.get("engineEventName") == "stateSnapshot")
    plan = fixture["injectionPlan"]
    latest = _pass_snapshots(fixture)["latest_server"]

    assert plan["injectedMismatchMode"] == "staleExpectedStateVersion", "MP-008 should use stale expectedStateVersion in P0."
    assert plan["clientStateVersion"] == 14, "Client stateVersion should be captured in the injection plan."
    assert plan["expectedStateVersion"] == 14, "Expected stateVersion should be captured in the injection plan."
    assert reject["rejectCode"] == "staleStateVersion", "Mismatch should surface as staleStateVersion reject."
    assert reject["authoritativeStateVersion"] == plan["authoritativeStateVersion"] == 15, "Authoritative version should align across reject and manifest."
    assert reject["eventId"] == plan["authoritativeEventId"], "Injection manifest should point at the authoritative reject event."
    assert recovery["reason"] == plan["recoverySnapshotReason"] == "resync", "Recovery should use stateSnapshot(reason=resync)."
    assert recovery["snapshotId"] == plan["recoverySnapshotId"], "Recovery snapshot id should be preserved in the injection plan."
    assert recovery["stateHash"] == latest["state_hash"], "Recovery snapshot hash should match the authority snapshot."


def _validate_mp_013(fixture: dict) -> None:
    choice = next(frame for frame in _pass_frames(fixture) if frame.get("engineEventName") == "choiceRequested")
    assert choice["choiceKind"] == "shake", "Expected shake choice fixture."
    assert choice["visibility"] == "actorOnly", "Shake visibility should be actorOnly."

    snapshots = _pass_snapshots(fixture)
    actor_choice = snapshots["player_a_initial"]["payload"]["pendingChoice"]
    peer_choice = snapshots["player_b_initial"]["payload"]["pendingChoice"]
    assert actor_choice["choiceId"] == peer_choice["choiceId"], "Both viewers should correlate the same choiceId."
    assert actor_choice["cards"], "Actor should keep visible shake cards."
    assert actor_choice["metadata"] is not None, "Actor should retain shake metadata."
    assert peer_choice["cards"] == [], "Peer view must redact shake cards."
    assert peer_choice["metadata"] is None, "Peer view must redact shake metadata."
    assert peer_choice["options"] == [], "Peer view must not receive actor-only options."


def _validate_mp_014(fixture: dict) -> None:
    frames = _pass_frames(fixture)
    errors = [frame for frame in frames if frame.get("transportType") == "error"]
    assert [frame["errorCode"] for frame in errors] == ["invalidResumeState", "staleConnectionId"], "Expected disconnected then stale heartbeat rejects."
    hello_ack = next(frame for frame in frames if frame.get("transportType") == "helloAck")
    assert hello_ack["connectionId"] == "conn_mp014_new", "Resume should bind the new connection."

    latest = _pass_snapshots(fixture)["latest_server"]["payload"]
    assert latest["currentConnectionId"] == "conn_mp014_new", "Newest connection ownership must remain stable."
    assert latest["heartbeatOwnerStable"] is True, "Stale heartbeat must not roll back session ownership."


def _validate_mp_015(fixture: dict) -> None:
    commands = list(fixture["commands"])
    guarded_ready = next(command for command in commands if command.get("commandName") == "setReady")
    assert guarded_ready["dispatch"] == "localGuard", "Premature ready should be intercepted locally."
    assert guarded_ready["guardResult"] == "skipped", "Premature ready should be skipped, not sent."
    assert guarded_ready["guardReason"] == "waitingForPlayers", "Guard reason should reflect the solo-room state."

    frames = _pass_frames(fixture)
    snapshots = [frame for frame in frames if frame.get("transportType") == "roomSnapshot"]
    assert [frame["roomState"] for frame in snapshots] == ["waitingForPlayers", "waitingForReady"], "Room should advance only after guest join."
    assert not any(frame.get("eventName") == "playerDisconnected" for frame in frames), "Premature ready must not disconnect the host."
    assert not any(frame.get("errorCode") == "invalidRoomState" for frame in frames), "Premature ready must not hit transport invalidRoomState."

    latest = _pass_snapshots(fixture)["latest_server"]["payload"]
    assert latest["roomState"] == "waitingForReady", "Authority snapshot should stop at waitingForReady."
    assert latest["localReady"] is False, "Local member should remain unready until the guarded state clears."
    assert latest["playerDisconnectedObserved"] is False, "Passive disconnect churn must remain absent."


def _validate_mp_016(fixture: dict) -> None:
    commands = list(fixture["commands"])
    go_stop_commands = [command for command in commands if command.get("choiceKind") == "goStop"]
    assert go_stop_commands, "The always-go fixture must exercise at least one goStop choice."
    assert all(command.get("optionCode") == "go" for command in go_stop_commands), "Every goStop submission must choose go."

    frames = _pass_frames(fixture)
    assert any(frame.get("engineEventName") == "choiceRequested" and frame.get("choiceKind") == "goStop" for frame in frames), "goStop choiceRequested should be present."
    assert any(frame.get("transportType") == "terminalSummary" for frame in frames), "terminalSummary must be emitted."
    assert any(frame.get("eventName") == "roomClosed" for frame in frames), "roomClosed must complete the leave lifecycle."

    latest = _pass_snapshots(fixture)["latest_server"]["payload"]
    assert latest["goStopChoiceCount"] == len(go_stop_commands), "Probe goStop count should match the command transcript."
    assert latest["goStopOptionCodes"] == ["go", "go"], "Probe should record only go submissions."
    assert latest["roomClosedSeen"] is True, "Room close completion must be captured."
    assert latest["closedRoomState"] == "closed", "Closed room snapshot should remain authoritative."


def _validate_mp_017(fixture: dict) -> None:
    commands = list(fixture["commands"])
    play_commands = [command for command in commands if command.get("commandName") == "playCard"]
    assert len(play_commands) == 4, "The short multiplayer probe should drive exactly four playCard actions."
    assert [command.get("playerId") for command in play_commands] == ["player_a", "player_b", "player_a", "player_b"], "The short probe should alternate two turns per player."

    frames = _pass_frames(fixture)
    patched = next(frame for frame in frames if frame.get("engineEventName") == "statePatched")
    turn_changed = next(frame for frame in frames if frame.get("engineEventName") == "turnChanged")
    assert patched.get("capturedDelta") == 2, "Fixture should include an authoritative capture delta."
    assert patched.get("stateVersion") == turn_changed.get("stateVersion"), "Capture projection should settle before the same turn handoff version."

    latest = _pass_snapshots(fixture)["latest_server"]["payload"]
    assert latest["captureProbeSuccessCount"] >= 1, "The short probe must record at least one successful capture parity check."
    assert latest["captureProbeFailures"] == [], "The short probe must not record captured-zone lag failures."
    assert latest["probes"][0]["renderedCaptureStateVersion"] == latest["probes"][0]["turnPassedStateVersion"], "Rendered capture visibility should land by the same turn handoff version."


_PASS_VALIDATORS = {
    "MP-001": _validate_mp_001,
    "MP-002": _validate_mp_002,
    "MP-003": _validate_mp_003,
    "MP-004": _validate_mp_004,
    "MP-005": _validate_mp_005,
    "MP-006": _validate_mp_006,
    "MP-007": _validate_mp_007,
    "MP-008": _validate_mp_008,
    "MP-013": _validate_mp_013,
    "MP-014": _validate_mp_014,
    "MP-015": _validate_mp_015,
    "MP-016": _validate_mp_016,
    "MP-017": _validate_mp_017,
}
