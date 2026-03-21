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
            command("c01", "Host creates room through bootstrap facade", "player_a", "room_bootstrap_create", {"roomType": "invite", "joinPolicy": "inviteCode"}),
            expect("e01", "Room snapshot seeds waitingForPlayers", "roomSnapshot", {"roomState": "waitingForPlayers"}),
            command("c02", "Host resolves invite through concrete bootstrap lookup", "player_a", "room_bootstrap_lookup_invite", {}),
            command("c03", "Guest joins room through bootstrap facade", "player_b", "room_bootstrap_join", {}),
            expect("e02", "Guest join is broadcast", "roomEvent.memberJoined", {"playerId": "player_b"}),
            command("c04", "Host attaches socket", "player_a", "hello", {"resumeMode": "fresh"}),
            command("c05", "Guest attaches socket", "player_b", "hello", {"resumeMode": "fresh"}),
            command("c06", "Host marks ready", "player_a", "setReady", {"ready": True}),
            command("c07", "Guest marks ready", "player_b", "setReady", {"ready": True}),
            expect("e03", "Ready update is emitted", "roomEvent.memberReadyChanged", {"ready": True}),
            expect("e04", "Room enters starting", "roomEvent.roomStateChanged", {"toState": "starting"}),
            expect("e05", "Game bootstrap event arrives", "gameEvent.engineEvent:gameStarted", {}),
            expect("e06", "Authoritative bootstrap snapshot arrives", "gameEvent.engineEvent:stateSnapshot", {"reason": "gameStarted"}),
            snapshot("s01", "Capture player A initial projection", "initial", "player", actor="player_a"),
            snapshot("s02", "Capture player B initial projection", "initial", "player", actor="player_b"),
            artifact("a01", "Persist bootstrap split boundary probe", "bootstrap_boundary_probe.json"),
            artifact("a02", "Persist replay manifest", "replay/replay_manifest.json"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/player_a_initial.json",
            "snapshots/player_b_initial.json",
            "bootstrap_boundary_probe.json",
            "replay/replay_manifest.json",
        ],
    )


def _mp002() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-002",
        purpose="Terminal lifecycle reaches roundEnded/matchEnded/terminalSummary and closes cleanly after the final leaveRoom.",
        steps=[
            command("c01", "Bootstrap deterministic live match", "system", "bootstrapMatch", {"seed": 42}),
            command("c02", "Drive terminal relay path", "player_a", "recordMatchEndedAndFetchTerminalSummary", {"roundIndex": 1}),
            expect("e01", "Terminal event is emitted", "gameEvent.engineEvent:roundEnded|matchEnded", {}),
            expect("e02", "terminalSummary is delivered", "terminalSummary", {}),
            command("c03", "Host leaves the ended room", "player_a", "leaveRoom", {}),
            command("c04", "Guest leaves the ended room", "player_b", "leaveRoom", {}),
            expect("e03", "roomClosed is emitted for the final departure", "roomEvent.roomClosed", {}),
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
        purpose="Reconnect grace expires through automatic timeout progression and room transitions into a terminal forfeit outcome.",
        steps=[
            command("c01", "Bootstrap live match", "system", "bootstrapLiveMatch", {"seed": 42}),
            command("c02", "Passively close player B transport", "player_b", "disconnectMember", {"mode": "passiveClose"}),
            expect("e01", "Grace countdown starts", "roomEvent.playerDisconnected", {"playerId": "player_b"}),
            wait("w01", "Allow automatic reconnect grace expiry", 31000, note="No manual reapExpiredState call is allowed in the locked live path."),
            expect("e02", "Automatic timeout drives terminal match end", "gameEvent.engineEvent:actionAccepted|roundEnded|matchEnded", {}),
            command("c03", "Attempt stale resume", "player_b", "hello", {"resumeMode": "resume"}),
            expect("e03", "resumeExpired is emitted", "error", {"errorCode": "resumeExpired"}),
            expect("e04", "Terminal forfeit signal is emitted", "roomEvent.playerForfeited|terminalSummary", {}),
            wait("w02", "Allow automatic result retention expiry", 61000),
            expect("e05", "roomClosed is emitted after retention", "roomEvent.roomClosed", {}),
            snapshot("s01", "Capture terminal authority state", "terminal", "authority"),
            artifact("a01", "Persist timeout parity probe", "timeout_probe.json"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "timeout_probe.json",
            "anomaly_report.md",
        ],
    )


def _mp008() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-008",
        purpose="Stale expectedStateVersion and explicit gap recovery hook both converge on authoritative snapshot-based recovery.",
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
            command("c02b", "Fetch dropped-event gap recovery shape preflight", "system", "room_gap_recovery_shape", {}),
            command("c03", "Send next gameplay command with stale expectedStateVersion", "player_a", "playCard|quit", {"expectedStateVersion": 14}),
            expect("e01", "staleStateVersion reject arrives", "gameEvent.engineEvent:actionRejected", {"rejectCode": "staleStateVersion"}),
            expect("e02", "Authoritative resync snapshot arrives", "gameEvent.engineEvent:stateSnapshot", {"reason": "resync"}),
            command("c03b", "Trigger live gap recovery hook on the same transport", "player_a", "triggerGapRecovery", {"expectedStateVersion": 13}),
            expect("e02b", "gapRecoveryHint is emitted before recovery snapshot", "gapRecoveryHint", {"inputLockRequired": True}),
            expect("e02c", "gapDetected recovery snapshot arrives", "gameEvent.engineEvent:stateSnapshot", {"reason": "gapDetected"}),
            artifact("a02", "Persist mismatch timeline", "timeline/mismatch.ndjson"),
            artifact("a03", "Persist gap recovery shape contract", "replay/gap_recovery_shape.json"),
            artifact("a04", "Persist live gap recovery probe", "replay/gap_recovery_probe.json"),
            artifact("a05", "Persist gap-injection future-extension plan", "replay/gap_injection_plan.json"),
            snapshot("s01", "Capture post-resync authority state", "resync", "authority"),
            artifact("a06", "Persist replay manifest", "replay/replay_manifest.json"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/assertions.ndjson",
            "timeline/events.ndjson",
            "timeline/mismatch.ndjson",
            "snapshots/latest_server.json",
            "replay/injection_manifest.json",
            "replay/gap_recovery_shape.json",
            "replay/gap_recovery_probe.json",
            "replay/gap_injection_plan.json",
            "replay/replay_manifest.json",
        ],
        notes=[
            "The locked P0 path is stale expectedStateVersion override followed by actionRejected(staleStateVersion) and stateSnapshot(reason=resync).",
            "timeline/mismatch.ndjson and replay/injection_manifest.json are mandatory even on early reject or partial resync.",
            "Socket mode now executes the live stale-version probe with a deterministic quit command after start_game warmup.",
            "playCard remains a separate live mapping probe because the projection still exposes authority playerId values.",
            "gap_recovery_shape.json locks the current gapRecoveryHint minimum fields plus the stateSnapshot(reason=gapDetected) recovery envelope shape.",
            "gap_recovery_probe.json records the executable triggerGapRecovery -> gapRecoveryHint -> stateSnapshot(reason=gapDetected) live hook result.",
            "gap_injection_plan.json now narrows the remaining future dropped-event probe down to a concrete drop point, follow-up actionId, and expected gapDetected recovery cursor set.",
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
            "heartbeat_probe.json",
            "stale_heartbeat_code_probe.json",
        ],
    )


def _mp015() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-015",
        purpose="Local room UI and autoroute defer ready until the authoritative room reaches waitingForReady with two members.",
        steps=[
            command("c01", "Host lands in a solo room snapshot", "player_a", "bootstrapRoomSession", {"roomState": "waitingForPlayers", "memberCount": 1}),
            command("c02", "Local ready attempt is guarded before transport send", "player_a", "setReady", {"dispatch": "localGuard", "guardReason": "waitingForPlayers"}),
            expect("e01", "Guest joins before authoritative ready is allowed", "roomEvent", {"eventName": "memberJoined"}),
            expect("e02", "Room reaches waitingForReady without disconnect churn", "roomSnapshot", {"roomState": "waitingForReady", "memberCount": 2}),
            snapshot("s01", "Capture guarded waitingForReady snapshot", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
        ],
    )


def _mp016() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-016",
        purpose="A seeded multiplayer room runs from bootstrap to terminal close while every go-stop choice submits go.",
        steps=[
            command("c01", "Seed the authoritative board before live bootstrap", "system", "setCondition", {"rngSeed": 7}),
            command("c02", "Bootstrap attached live room session", "system", "bootstrapRoomSession", {"seeded": True}),
            command("c03", "Drive legal playCard turns from both players", "system", "playCard", {"policy": "viewerFirstLegalCard"}),
            expect("e01", "choiceRequested appears when a live choice is needed", "gameEvent.engineEvent:choiceRequested", {}),
            command("c04", "Resolve live go-stop by always submitting go", "system", "submitChoice", {"choiceKind": "goStop", "optionCode": "go"}),
            expect("e02", "terminalSummary arrives after the seeded end-to-end run", "terminalSummary", {}),
            command("c05", "Both clients leave the ended room", "system", "leaveRoom", {"participants": ["player_a", "player_b"]}),
            expect("e03", "Room closes after the final leaveRoom", "roomEvent.roomClosed", {}),
            artifact("a01", "Persist per-seed always-go probe", "always_go_probe.json"),
            snapshot("s01", "Capture closed authority room snapshot", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "always_go_probe.json",
        ],
    )


def _mp017() -> ScenarioSkeleton:
    return ScenarioSkeleton(
        scenario_id="MP-017",
        purpose="Two turns per player keep captured cards visible in the UI before the authoritative turn handoff completes.",
        steps=[
            command("c01", "Create and join a live invite room", "system", "bootstrapRoomSession", {"uiMode": True}),
            command("c02", "Drive exactly two playCard turns from each player", "system", "playCard", {"turnLimitPerPlayer": 2}),
            expect("e01", "Authoritative capture appears during the short probe", "gameEvent.engineEvent:statePatched", {"capturesVisible": True}),
            expect("e02", "Rendered captured totals catch up before turnChanged completes", "gameEvent.engineEvent:turnChanged", {"capturedLag": False}),
            artifact("a01", "Persist the short-turn captured-zone parity probe", "capture_visibility_probe.json"),
            snapshot("s01", "Capture the latest authority snapshot after the short probe", "terminal", "authority"),
        ],
        required_artifacts=[
            "manifest.json",
            "timeline/steps.ndjson",
            "timeline/commands.ndjson",
            "timeline/events.ndjson",
            "snapshots/latest_server.json",
            "capture_visibility_probe.json",
        ],
    )


def _build_skeletons() -> dict[str, ScenarioSkeleton]:
    builders = [_mp001, _mp002, _mp003, _mp004, _mp005, _mp006, _mp007, _mp008, _mp013, _mp014, _mp015, _mp016, _mp017]
    return {skeleton.scenario_id: skeleton for skeleton in (builder() for builder in builders)}


SCENARIO_SKELETONS = _build_skeletons()
