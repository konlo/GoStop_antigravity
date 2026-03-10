from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class ScenarioStepKind(str, Enum):
    COMMAND = "command"
    EXPECT = "expect"
    SNAPSHOT = "snapshot"
    ARTIFACT = "artifact"
    WAIT = "wait"


@dataclass(frozen=True)
class ScenarioStep:
    step_id: str
    kind: ScenarioStepKind
    label: str
    actor: str | None = None
    transport: str | None = None
    action: str | None = None
    payload: dict[str, Any] = field(default_factory=dict)
    expect: dict[str, Any] = field(default_factory=dict)
    note: str = ""

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["kind"] = self.kind.value
        return data


@dataclass(frozen=True)
class ScenarioSkeleton:
    scenario_id: str
    purpose: str
    steps: list[ScenarioStep]
    required_artifacts: list[str]
    contract_questions: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_rows(self) -> list[dict[str, Any]]:
        return [step.to_dict() for step in self.steps]


def command(
    step_id: str,
    label: str,
    actor: str,
    action: str,
    payload: dict[str, Any] | None = None,
    note: str = "",
) -> ScenarioStep:
    return ScenarioStep(
        step_id=step_id,
        kind=ScenarioStepKind.COMMAND,
        label=label,
        actor=actor,
        action=action,
        payload=payload or {},
        note=note,
    )


def expect(
    step_id: str,
    label: str,
    transport: str,
    expect_fields: dict[str, Any] | None = None,
    note: str = "",
) -> ScenarioStep:
    return ScenarioStep(
        step_id=step_id,
        kind=ScenarioStepKind.EXPECT,
        label=label,
        transport=transport,
        expect=expect_fields or {},
        note=note,
    )


def snapshot(
    step_id: str,
    label: str,
    source: str,
    scope: str,
    actor: str | None = None,
    note: str = "",
) -> ScenarioStep:
    return ScenarioStep(
        step_id=step_id,
        kind=ScenarioStepKind.SNAPSHOT,
        label=label,
        actor=actor,
        payload={"source": source, "scope": scope},
        note=note,
    )


def artifact(step_id: str, label: str, relative_path: str, note: str = "") -> ScenarioStep:
    return ScenarioStep(
        step_id=step_id,
        kind=ScenarioStepKind.ARTIFACT,
        label=label,
        payload={"path": relative_path},
        note=note,
    )


def wait(step_id: str, label: str, duration_ms: int, note: str = "") -> ScenarioStep:
    return ScenarioStep(
        step_id=step_id,
        kind=ScenarioStepKind.WAIT,
        label=label,
        payload={"durationMs": duration_ms},
        note=note,
    )


def _mp001() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-001",
        purpose="Room create/join/ready auto-start path reaches live bootstrap without a public start command.",
        steps=[
            command("c01", "Host creates room", "player_a", "createRoom", {"roomType": "invite", "joinPolicy": "inviteCode"}),
            expect("e01", "Room snapshot seeds waitingForPlayers", "roomSnapshot", {"roomState": "waitingForPlayers"}),
            command("c02", "Guest joins room", "player_b", "joinRoom", {}),
            expect("e02", "Guest join is broadcast", "roomEvent.memberJoined", {"playerId": "player_b"}),
            command("c03", "Host attaches socket", "player_a", "hello", {"resumeMode": "fresh"}),
            command("c04", "Guest attaches socket", "player_b", "hello", {"resumeMode": "fresh"}),
            command("c05", "Host marks ready", "player_a", "setReady", {"ready": True}),
            command("c06", "Guest marks ready", "player_b", "setReady", {"ready": True}),
            expect("e03", "Ready update is emitted", "roomEvent.memberReadyChanged", {"ready": True}),
            expect("e04", "Room enters starting", "roomEvent.roomStateChanged", {"toState": "starting"}),
            expect("e05", "Game bootstrap event arrives", "gameEvent.engineEvent:gameStarted", {}),
            expect("e06", "Authoritative bootstrap snapshot arrives", "gameEvent.engineEvent:stateSnapshot", {"reason": "gameStarted"}),
            snapshot("s01", "Capture player A initial projection", "initial", "player", actor="player_a"),
            snapshot("s02", "Capture player B initial projection", "initial", "player", actor="player_b"),
            artifact("a01", "Persist replay manifest", "replay/replay_manifest.json"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/player_a_initial.json",
            "snapshots/player_b_initial.json",
            "replay/replay_manifest.json",
        ],
    )


def _mp002() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-002",
        purpose="One full round completes with deterministic terminal summary and replay artifacts.",
        steps=[
            command("c01", "Bootstrap deterministic live match", "system", "bootstrapMatch", {"seed": 42}),
            command("c02", "Drive legal scripted commands until terminal event", "system", "playScriptedRound", {"scriptId": "mp002_terminal_round"}),
            expect("e01", "Terminal event is emitted", "gameEvent.engineEvent:roundEnded|matchEnded", {}),
            snapshot("s01", "Capture authority terminal snapshot", "terminal", "authority"),
            artifact("a01", "Persist replay stream", "replay/event_stream.ndjson"),
            artifact("a02", "Persist summary", "summary.md"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "replay/event_stream.ndjson",
        ],
    )


def _mp003() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-003",
        purpose="Non-turn owner sends playCard and receives a pure out-of-turn reject without state mutation.",
        steps=[
            command("c01", "Bootstrap inTurn state with player A as actor", "system", "bootstrapTurn", {"currentPlayerId": "player_a"}),
            snapshot("s01", "Capture pre-reject authority state", "initial", "authority"),
            command("c02", "Player B sends out-of-turn playCard", "player_b", "playCard", {"actionId": "act_mp003_001"}),
            expect("e01", "Reject is emitted", "gameEvent.engineEvent:actionRejected", {"rejectCode": "outOfTurn"}),
            snapshot("s02", "Capture post-reject authority state", "terminal", "authority"),
            artifact("a01", "Persist reject timeline", "timeline/events.ndjson"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
        ],
    )


def _mp004() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-004",
        purpose="Exact duplicate actionId is replayed idempotently with no second mutation.",
        steps=[
            command("c01", "Bootstrap playable inTurn state", "system", "bootstrapTurn", {"currentPlayerId": "player_a"}),
            command("c02", "Player A sends original playCard", "player_a", "playCard", {"actionId": "act_dup_001"}),
            expect("e01", "Original actionAccepted is emitted", "gameEvent.engineEvent:actionAccepted", {"actionId": "act_dup_001"}),
            command("c03", "Player A resends identical playCard", "player_a", "playCard", {"actionId": "act_dup_001"}),
            expect("e02", "Replay uses prior event ids", "gameEvent.engineEvent:actionAccepted", {"actionId": "act_dup_001"}),
            artifact("a01", "Persist replay event stream", "replay/event_stream.ndjson"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "replay/event_stream.ndjson",
        ],
    )


def _mp005() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-005",
        purpose="Invalid choice submission is rejected while authoritative pending choice remains active.",
        steps=[
            command("c01", "Drive game into choicePending", "system", "bootstrapChoice", {"choiceKind": "capture"}),
            expect("e01", "choiceRequested is emitted", "gameEvent.engineEvent:choiceRequested", {"choiceKind": "capture"}),
            command("c02", "Submit invalid optionCode", "player_a", "selectCapture", {"choiceId": "choice_invalid", "optionCode": "invalid"}),
            expect("e02", "invalidChoice reject is emitted", "gameEvent.engineEvent:actionRejected", {"rejectCode": "invalidChoice"}),
            snapshot("s01", "Capture pending choice after reject", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
        ],
    )


def _mp006() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-006",
        purpose="Disconnect inside live match and resume within 30 seconds using snapshot-first ordering.",
        steps=[
            command("c01", "Bootstrap live match", "system", "bootstrapLiveMatch", {"seed": 42}),
            command("c02", "Drop player B transport", "player_b", "disconnectMember", {}),
            expect("e01", "Grace countdown starts", "roomEvent.playerDisconnected", {"playerId": "player_b"}),
            wait("w01", "Wait briefly before reconnect", 500),
            command("c03", "Player B resumes session", "player_b", "hello", {"resumeMode": "resume"}),
            expect("e02", "helloAck confirms resume", "helloAck", {"resumeMode": "resume"}),
            expect("e03", "Room snapshot lands before live traffic", "roomSnapshot", {"roomState": "inGame"}),
            expect("e04", "Authoritative stateSnapshot(reason=resume) lands", "gameEvent.engineEvent:stateSnapshot", {"reason": "resume"}),
            snapshot("s01", "Capture resumed player projection", "resume", "player", actor="player_b"),
            expect("e05", "playerReconnected is emitted after snapshots", "roomEvent.playerReconnected", {"playerId": "player_b"}),
            artifact("a01", "Store reconnect screenshot placeholder", "ui/reconnect.png"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "ui/reconnect.png",
        ],
    )


def _mp007() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-007",
        purpose="Reconnect grace expires and room transitions into a terminal forfeit outcome.",
        steps=[
            command("c01", "Bootstrap live match", "system", "bootstrapLiveMatch", {"seed": 42}),
            command("c02", "Drop player B transport", "player_b", "disconnectMember", {}),
            expect("e01", "Grace countdown starts", "roomEvent.playerDisconnected", {"playerId": "player_b"}),
            wait("w01", "Advance beyond reconnect grace", 31000),
            command("c03", "Attempt stale resume", "player_b", "hello", {"resumeMode": "resume"}),
            expect("e02", "resumeExpired is emitted", "error", {"errorCode": "resumeExpired"}),
            expect("e03", "Terminal forfeit signal is emitted", "roomEvent.playerForfeited|gameEvent.engineEvent:matchEnded", {}),
            snapshot("s01", "Capture terminal authority state", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "anomaly_report.md",
        ],
    )


def _mp008() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-008",
        purpose="Stale expectedStateVersion deterministically triggers actionRejected and resync through authoritative snapshot.",
        steps=[
            command("c01", "Bootstrap live match at known stateVersion", "system", "bootstrapLiveMatch", {"seed": 42}),
            command(
                "c02",
                "Persist stale expectedStateVersion mismatch cursor",
                "system",
                "injectMismatch",
                {"injectedMismatchMode": "staleExpectedStateVersion", "expectedStateVersion": 14},
            ),
            artifact("a01", "Persist injection manifest", "replay/injection_manifest.json"),
            command("c03", "Send next command with stale expectedStateVersion", "player_a", "playCard", {"expectedStateVersion": 14}),
            expect("e01", "staleStateVersion reject arrives", "gameEvent.engineEvent:actionRejected", {"rejectCode": "staleStateVersion"}),
            expect("e02", "Authoritative resync snapshot arrives", "gameEvent.engineEvent:stateSnapshot", {"reason": "resync"}),
            artifact("a02", "Persist mismatch timeline", "timeline/mismatch.ndjson"),
            snapshot("s01", "Capture post-resync authority state", "resync", "authority"),
            artifact("a03", "Persist replay manifest", "replay/replay_manifest.json"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/assertions.ndjson",
            "timeline/events.ndjson",
            "timeline/mismatch.ndjson",
            "snapshots/latest_server.json",
            "replay/injection_manifest.json",
            "replay/replay_manifest.json",
        ],
        notes=[
            "The locked P0 path is stale expectedStateVersion override followed by actionRejected(staleStateVersion) and stateSnapshot(reason=resync).",
            "timeline/mismatch.ndjson and replay/injection_manifest.json are mandatory even on early reject or partial resync.",
            "Socket mode currently reaches live bootstrap + hook attachment preflight only; the full gameplay resync step waits for room_transport_send to expose gameplay commands with expectedStateVersion.",
        ],
    )


def _mp013() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-013",
        purpose="askingShake choice stays actor-only and does not leak hidden hand information to the peer view.",
        steps=[
            command("c01", "Bootstrap shake-pending state", "system", "bootstrapChoice", {"choiceKind": "shake", "actorPlayerId": "player_a"}),
            expect("e01", "choiceRequested is emitted for actor", "gameEvent.engineEvent:choiceRequested", {"choiceKind": "shake", "visibility": "actorOnly"}),
            snapshot("s01", "Capture actor shake projection", "initial", "player", actor="player_a"),
            snapshot("s02", "Capture non-actor shake projection", "initial", "player", actor="player_b"),
            artifact("a01", "Persist projection comparison notes", "summary.md"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/player_a_initial.json",
            "snapshots/player_b_initial.json",
        ],
    )


def _mp014() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-014",
        purpose="Disconnected or replaced session heartbeats are rejected and cannot reclaim ownership from the newest connection.",
        steps=[
            command("c01", "Bootstrap attached room session", "system", "bootstrapRoomSession", {"playerId": "player_b"}),
            command("c02", "Drop player B into disconnectedGrace", "player_b", "disconnectMember", {}),
            expect("e01", "Disconnected heartbeat is rejected", "error", {"errorCode": "invalidResumeState"}),
            command("c03", "Resume player B on a new connection", "player_b", "hello", {"resumeMode": "resume", "connectionId": "conn_b_new"}),
            expect("e02", "Resume helloAck confirms new owner", "helloAck", {"resumeMode": "resume"}),
            command("c04", "Send heartbeat from stale connection", "player_b", "heartbeat", {"connectionId": "conn_b_old"}),
            expect("e03", "Stale heartbeat is rejected", "error", {"errorCode": "staleConnectionId"}),
            snapshot("s01", "Capture post-reject room snapshot", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
        ],
    )


def _build_skeletons() -> dict[str, ScenarioSkeleton]:
    builders = [_mp001, _mp002, _mp003, _mp004, _mp005, _mp006, _mp007, _mp008, _mp013, _mp014]
    return {skeleton.scenario_id: skeleton for skeleton in (builder() for builder in builders)}


SCENARIO_SKELETONS = _build_skeletons()
