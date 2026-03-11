from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .artifacts import MultiplayerArtifactStore
from .fixtures import FIXTURE_LIBRARY
from .models import (
    AnomalyReport,
    ManifestPlayer,
    ReplayManifest,
    RunManifest,
    ScenarioDefinition,
    ScenarioResult,
    ScenarioStatus,
    SnapshotRecord,
)
from .skeletons import SCENARIO_SKELETONS, ScenarioStepKind
from .socket_transport import default_socket_derived_data, resolve_socket_binary, run_socket_scenario
from .validators import validate_fixture


REQUIRED_REPLAY_IDS = [
    "traceId",
    "roomId",
    "gameId",
    "turnId",
    "actionId",
    "playerId",
    "eventId",
    "messageId",
    "roomSequence",
    "sessionId",
    "connectionId",
]


class MultiplayerScenarioRunner:
    def __init__(
        self,
        output_root: Path,
        mode: str = "scaffold",
        save_replay: bool = False,
        binary_path: Path | None = None,
        derived_data: Path | None = None,
        skip_build: bool = False,
        socket_transport: str = "tcp",
    ):
        self.output_root = output_root
        self.mode = mode
        self.save_replay = save_replay
        self.binary_path = binary_path
        self.derived_data = derived_data or default_socket_derived_data()
        self.skip_build = skip_build
        self.socket_transport = socket_transport
        self.repo_root = Path(__file__).resolve().parents[3]
        self._resolved_socket_binary: Path | None = None

    def run(self, scenarios: list[ScenarioDefinition]) -> list[ScenarioResult]:
        return [self._run_one(scenario) for scenario in scenarios]

    def _run_one(self, scenario: ScenarioDefinition) -> ScenarioResult:
        if self.mode == "fixture":
            return self._run_fixture(scenario)
        if self.mode == "socket":
            return self._run_socket(scenario)
        skeleton = SCENARIO_SKELETONS[scenario.scenario_id]
        started_at = datetime.now().astimezone()
        run_id = f"{scenario.scenario_id.lower()}_{started_at.strftime('%Y%m%d_%H%M%S')}"
        store = MultiplayerArtifactStore(self.output_root, scenario.scenario_id, run_id)
        store.initialize_layout()

        status = ScenarioStatus.BLOCKED if scenario.contract_questions else ScenarioStatus.PENDING
        manifest = RunManifest(
            run_id=run_id,
            scenario_id=scenario.scenario_id,
            scenario_name=scenario.name,
            priority=scenario.priority,
            automation=scenario.automation,
            focus=scenario.focus,
            result=status,
            started_at=started_at.isoformat(timespec="seconds"),
            mode=self.mode,
            transport=None,
            trace_id=f"trace_{scenario.scenario_id.lower()}_placeholder",
            room_id="room_placeholder",
            game_id="game_placeholder",
            players=[
                ManifestPlayer(player_id="player_a", seat=0, connection_state="connected"),
                ManifestPlayer(player_id="player_b", seat=1, connection_state="connected"),
            ],
            contract_questions=list(scenario.contract_questions),
            notes=[
                "Scaffold-only run. No network transport or production bridge command was executed.",
                "Artifacts express the expected structure for future socket/simulator execution.",
            ],
        )
        store.write_manifest(manifest)

        store.write_log(
            "agent.log",
            [
                f"[{started_at.isoformat(timespec='seconds')}] scenario={scenario.scenario_id} mode={self.mode}",
                f"status={status.value}",
                f"focus={scenario.focus}",
            ],
        )
        store.write_log(
            "room.log",
            [
                "Placeholder room log for multiplayer harness scaffold.",
                "Expected transport ordering is recorded in timeline/events.ndjson.",
            ],
        )
        store.write_log(
            "engine.log",
            [
                "Placeholder engine log for multiplayer harness scaffold.",
                "Expected engine events are recorded as planned entries until transport binding exists.",
            ],
        )

        store.append_ndjson("timeline/steps.ndjson", skeleton.to_rows())

        store.append_ndjson(
            "timeline/commands.ndjson",
            [
                {
                    "kind": "planned_command",
                    "scenarioId": scenario.scenario_id,
                    "stepId": step.step_id,
                    "actor": step.actor,
                    "action": step.action,
                    "label": step.label,
                    "payload": step.payload,
                    "note": step.note,
                }
                for step in skeleton.steps
                if step.kind is ScenarioStepKind.COMMAND
            ],
        )
        store.append_ndjson(
            "timeline/events.ndjson",
            [
                {
                    "kind": "expected_event",
                    "scenarioId": scenario.scenario_id,
                    "stepId": step.step_id,
                    "transport": step.transport,
                    "eventName": step.label,
                    "expect": step.expect,
                    "delivery": "planned",
                }
                for step in skeleton.steps
                if step.kind is ScenarioStepKind.EXPECT
            ]
            + [
                {
                    "kind": "expected_transport",
                    "scenarioId": scenario.scenario_id,
                    "sequenceIndex": index + 1,
                    "value": item,
                }
                for index, item in enumerate(scenario.transport_sequence)
            ],
        )
        store.append_ndjson(
            "timeline/assertions.ndjson",
            [
                {
                    "kind": "planned_assertion",
                    "scenarioId": scenario.scenario_id,
                    "assertionIndex": index + 1,
                    "text": text,
                }
                for index, text in enumerate(scenario.assertions)
            ],
        )

        placeholder_timestamp = started_at.isoformat(timespec="seconds")
        store.write_snapshot(
            "player_a_initial.json",
            SnapshotRecord(
                snapshot_id=f"{scenario.scenario_id.lower()}_player_a_initial",
                source="initial",
                scope="player",
                captured_at=placeholder_timestamp,
                player_id="player_a",
                state_version=1,
                event_id="evt_placeholder_001",
                state_hash="TBD",
                payload={"status": "placeholder", "scenarioId": scenario.scenario_id},
            ),
        )
        store.write_snapshot(
            "player_b_initial.json",
            SnapshotRecord(
                snapshot_id=f"{scenario.scenario_id.lower()}_player_b_initial",
                source="initial",
                scope="player",
                captured_at=placeholder_timestamp,
                player_id="player_b",
                state_version=1,
                event_id="evt_placeholder_001",
                state_hash="TBD",
                payload={"status": "placeholder", "scenarioId": scenario.scenario_id},
            ),
        )
        store.write_snapshot(
            "latest_server.json",
            SnapshotRecord(
                snapshot_id=f"{scenario.scenario_id.lower()}_latest_server",
                source="terminal",
                scope="authority",
                captured_at=placeholder_timestamp,
                player_id=None,
                state_version=None,
                event_id=None,
                state_hash="TBD",
                payload={"status": "placeholder", "scenarioId": scenario.scenario_id},
            ),
        )

        store.write_replay_manifest(
            ReplayManifest(
                run_id=run_id,
                scenario_id=scenario.scenario_id,
                event_stream_path="replay/event_stream.ndjson",
                snapshot_reference_path="snapshots/latest_server.json",
                baseline_reason="scaffold",
                required_ids=REQUIRED_REPLAY_IDS,
                notes=[
                    "Populate from authoritative room/game transcripts once transport binding is implemented.",
                ],
            )
        )
        if self.save_replay or status != ScenarioStatus.PASS:
            store.write_replay_placeholder(
                "snapshot_reference.json",
                {
                    "snapshotPath": "snapshots/latest_server.json",
                    "scenarioId": scenario.scenario_id,
                    "status": "placeholder",
                },
            )
            store.append_ndjson(
                "replay/event_stream.ndjson",
                [
                    {
                        "kind": "placeholder",
                        "scenarioId": scenario.scenario_id,
                        "message": "Append authoritative room/game events here during live execution.",
                    }
                ],
            )
            self._write_scenario_specific_artifacts(store, scenario, status)

        store.write_text(
            "ui/README.md",
            "# UI Artifacts\n\nStore reconnect, reject, or desync screenshots here during simulator-backed multiplayer runs.\n",
        )

        checklist_lines = ["# Checklist Report", ""]
        checklist_lines.extend([f"- [ ] {item}" for item in scenario.assertions])
        store.write_checklist(checklist_lines)

        if scenario.contract_questions:
            anomaly = AnomalyReport(
                scenario_id=scenario.scenario_id,
                run_id=run_id,
                title=f"{scenario.scenario_id} Contract Blockers",
                expected_behavior="Executable multiplayer transport validation with deterministic artifacts.",
                observed_behavior="Only scaffold artifacts were generated because one or more contract decisions remain open.",
                first_bad_transition="No live transition recorded. Execution stopped at scaffold planning.",
                last_good_event_id="TBD",
                last_good_state_version="TBD",
                failure_class="TEST_HARNESS",
                reproduction_command="python3 tests/test_agent/multiplayer_runner.py --scenario "
                f"{scenario.scenario_id} --mode scaffold",
                artifact_links=[
                    "manifest.json",
                    "timeline/commands.ndjson",
                    "timeline/events.ndjson",
                    "replay/replay_manifest.json",
                ],
                open_questions=list(scenario.contract_questions),
            )
            store.write_anomaly(anomaly)

        summary = self._build_summary(scenario, manifest, status)
        store.write_summary(summary)

        return ScenarioResult(
            scenario=scenario,
            status=status,
            summary="Scaffold artifacts generated",
            run_id=run_id,
            artifact_root=str(store.run_root),
            blocking_reasons=list(scenario.contract_questions),
        )

    def _run_fixture(self, scenario: ScenarioDefinition) -> ScenarioResult:
        skeleton = SCENARIO_SKELETONS[scenario.scenario_id]
        started_at = datetime.now().astimezone()
        run_id = f"{scenario.scenario_id.lower()}_{started_at.strftime('%Y%m%d_%H%M%S')}"
        store = MultiplayerArtifactStore(self.output_root, scenario.scenario_id, run_id)
        store.initialize_layout()

        fixture = FIXTURE_LIBRARY[scenario.scenario_id]
        status, summary, blocking_reasons = validate_fixture(scenario)
        manifest = RunManifest(
            run_id=run_id,
            scenario_id=scenario.scenario_id,
            scenario_name=scenario.name,
            priority=scenario.priority,
            automation="Fixture replay",
            focus=scenario.focus,
            result=status,
            started_at=started_at.isoformat(timespec="seconds"),
            mode=self.mode,
            transport=None,
            trace_id=fixture.get("traceId"),
            room_id=fixture.get("roomId"),
            game_id=fixture.get("gameId"),
            players=[
                ManifestPlayer(
                    player_id=player["player_id"],
                    seat=player.get("seat"),
                    connection_state=player.get("connection_state"),
                )
                for player in fixture.get("players", [])
            ],
            contract_questions=list(blocking_reasons),
            notes=[
                "Fixture mode replays synthetic room/game transcripts to validate harness artifact capture.",
                fixture["summary"],
            ],
        )
        store.write_manifest(manifest)

        store.write_log(
            "agent.log",
            [
                f"[{started_at.isoformat(timespec='seconds')}] scenario={scenario.scenario_id} mode={self.mode}",
                f"status={status.value}",
                fixture["summary"],
            ],
        )
        store.write_log(
            "room.log",
            [
                "Fixture-backed room transcript.",
                f"roomId={fixture.get('roomId')} roomStateDerivedFromFrames=yes",
            ],
        )
        store.write_log(
            "engine.log",
            [
                "Fixture-backed engine transcript.",
                f"gameId={fixture.get('gameId')}",
            ],
        )

        store.append_ndjson("timeline/steps.ndjson", skeleton.to_rows())
        store.append_ndjson("timeline/commands.ndjson", fixture.get("commands", []))
        store.append_ndjson("timeline/events.ndjson", fixture.get("frames", []))
        store.append_ndjson(
            "timeline/assertions.ndjson",
            [
                {
                    "kind": "planned_assertion",
                    "scenarioId": scenario.scenario_id,
                    "assertionIndex": index + 1,
                    "text": text,
                    "status": "verified" if status is ScenarioStatus.PASS else "blocked",
                }
                for index, text in enumerate(scenario.assertions)
            ],
        )

        for filename, snapshot_payload in fixture.get("snapshots", {}).items():
            store.write_snapshot(
                f"{filename}.json",
                SnapshotRecord(
                    snapshot_id=snapshot_payload["snapshot_id"],
                    source=snapshot_payload["source"],
                    scope=snapshot_payload["scope"],
                    captured_at=started_at.isoformat(timespec="seconds"),
                    player_id=snapshot_payload.get("player_id"),
                    state_version=snapshot_payload.get("state_version"),
                    event_id=snapshot_payload.get("event_id"),
                    state_hash=snapshot_payload["state_hash"],
                    payload=snapshot_payload["payload"],
                ),
            )

        store.write_replay_manifest(
            ReplayManifest(
                run_id=run_id,
                scenario_id=scenario.scenario_id,
                event_stream_path="replay/event_stream.ndjson",
                snapshot_reference_path="snapshots/latest_server.json",
                baseline_reason="fixture",
                required_ids=REQUIRED_REPLAY_IDS,
                notes=["Fixture transcript copied into replay/event_stream.ndjson."],
            )
        )
        if self.save_replay or status != ScenarioStatus.PASS:
            store.write_replay_placeholder(
                "snapshot_reference.json",
                {
                    "snapshotPath": "snapshots/latest_server.json",
                    "scenarioId": scenario.scenario_id,
                    "status": status.value,
                },
            )
            store.append_ndjson("replay/event_stream.ndjson", fixture.get("frames", []))
            self._write_scenario_specific_artifacts(store, scenario, status, artifact_source=fixture)

        store.write_text(
            "ui/README.md",
            "# UI Artifacts\n\nFixture mode does not generate screenshots. Live simulator runs should place reconnect or reject captures here.\n",
        )

        checklist_lines = ["# Checklist Report", ""]
        checklist_lines.extend(
            [
                f"- [{'x' if status is ScenarioStatus.PASS else ' '}] {item}"
                for item in scenario.assertions
            ]
        )
        store.write_checklist(checklist_lines)

        if status in {ScenarioStatus.BLOCKED, ScenarioStatus.FAIL}:
            anomaly = AnomalyReport(
                scenario_id=scenario.scenario_id,
                run_id=run_id,
                title=f"{scenario.scenario_id} Fixture Blockers",
                expected_behavior="Fixture-backed multiplayer validation should complete without unresolved contract blockers.",
                observed_behavior=fixture["summary"],
                first_bad_transition="Validation stopped at fixture review because required contract fields are still open.",
                last_good_event_id="TBD",
                last_good_state_version="TBD",
                failure_class="TEST_HARNESS",
                reproduction_command="python3 tests/test_agent/multiplayer_runner.py --scenario "
                f"{scenario.scenario_id} --mode fixture",
                artifact_links=[
                    "manifest.json",
                    "timeline/commands.ndjson",
                    "timeline/events.ndjson",
                    "replay/replay_manifest.json",
                ],
                open_questions=list(blocking_reasons),
            )
            store.write_anomaly(anomaly)

        store.write_summary(self._build_summary(scenario, manifest, status) + f"\nFixture Summary: {summary}\n")

        return ScenarioResult(
            scenario=scenario,
            status=status,
            summary=summary,
            run_id=run_id,
            artifact_root=str(store.run_root),
            blocking_reasons=list(blocking_reasons),
        )

    def _run_socket(self, scenario: ScenarioDefinition) -> ScenarioResult:
        skeleton = SCENARIO_SKELETONS[scenario.scenario_id]
        started_at = datetime.now().astimezone()
        run_id = f"{scenario.scenario_id.lower()}_{started_at.strftime('%Y%m%d_%H%M%S')}"
        store = MultiplayerArtifactStore(self.output_root, scenario.scenario_id, run_id)
        store.initialize_layout()

        resolved_binary: Path | None = None
        try:
            resolved_binary = self._ensure_socket_binary()
            socket_result = run_socket_scenario(
                scenario,
                repo_root=self.repo_root,
                binary_path=resolved_binary,
                transport=self.socket_transport,
            )
        except Exception as error:
            socket_result = {
                "status": ScenarioStatus.FAIL,
                "summary": f"Socket transport preflight failed before scenario execution: {error}",
                "roomId": None,
                "gameId": None,
                "players": [],
                "commands": [],
                "frames": [],
                "snapshots": {},
                "logs": {
                    "agent": [
                        f"Socket transport preflight failed: {error}",
                    ],
                    "room": [],
                    "engine": [],
                },
                "blockingReasons": [str(error)],
                "transportBackend": self.socket_transport,
            }

        status = socket_result["status"]
        summary = socket_result["summary"]
        blocking_reasons = list(socket_result.get("blockingReasons", []))

        manifest_notes = [
            "Socket mode executes against GoStopCLI room_transport_* transport spike.",
            f"socketTransport={self.socket_transport}",
            summary,
        ]
        if resolved_binary is not None:
            manifest_notes.append(f"socketBinary={resolved_binary}")

        manifest = RunManifest(
            run_id=run_id,
            scenario_id=scenario.scenario_id,
            scenario_name=scenario.name,
            priority=scenario.priority,
            automation=scenario.automation,
            focus=scenario.focus,
            result=status,
            started_at=started_at.isoformat(timespec="seconds"),
            mode=self.mode,
            transport=socket_result.get("transportBackend", self.socket_transport),
            trace_id=socket_result.get("traceId"),
            room_id=socket_result.get("roomId"),
            game_id=socket_result.get("gameId"),
            players=[
                ManifestPlayer(
                    player_id=player["player_id"],
                    seat=player.get("seat"),
                    connection_state=player.get("connection_state"),
                )
                for player in socket_result.get("players", [])
            ],
            contract_questions=list(blocking_reasons),
            notes=manifest_notes,
        )
        store.write_manifest(manifest)

        logs = socket_result.get("logs", {})
        store.write_log(
            "agent.log",
            [
                f"[{started_at.isoformat(timespec='seconds')}] scenario={scenario.scenario_id} mode={self.mode}",
                f"transport={socket_result.get('transportBackend', self.socket_transport)}",
                f"status={status.value}",
                *logs.get("agent", []),
            ],
        )
        store.write_log("room.log", logs.get("room", ["No room transport frames captured."]))
        store.write_log("engine.log", logs.get("engine", ["No engine transport frames captured."]))

        store.append_ndjson("timeline/steps.ndjson", skeleton.to_rows())
        store.append_ndjson("timeline/commands.ndjson", socket_result.get("commands", []))
        store.append_ndjson("timeline/events.ndjson", socket_result.get("frames", []))
        store.append_ndjson(
            "timeline/assertions.ndjson",
            [
                {
                    "kind": "planned_assertion",
                    "scenarioId": scenario.scenario_id,
                    "assertionIndex": index + 1,
                    "text": text,
                    "status": "verified" if status is ScenarioStatus.PASS else "blocked",
                }
                for index, text in enumerate(scenario.assertions)
            ],
        )

        for filename, snapshot_payload in socket_result.get("snapshots", {}).items():
            store.write_snapshot(
                f"{filename}.json",
                SnapshotRecord(
                    snapshot_id=snapshot_payload["snapshot_id"],
                    source=snapshot_payload["source"],
                    scope=snapshot_payload["scope"],
                    captured_at=started_at.isoformat(timespec="seconds"),
                    player_id=snapshot_payload.get("player_id"),
                    state_version=snapshot_payload.get("state_version"),
                    event_id=snapshot_payload.get("event_id"),
                    state_hash=snapshot_payload["state_hash"],
                    payload=snapshot_payload["payload"],
                ),
            )

        if isinstance(socket_result.get("transportParity"), dict):
            store.write_json("transport_parity.json", socket_result["transportParity"])

        if isinstance(socket_result.get("duplicateProbe"), dict):
            store.write_json("duplicate_probe.json", socket_result["duplicateProbe"])

        store.write_replay_manifest(
            ReplayManifest(
                run_id=run_id,
                scenario_id=scenario.scenario_id,
                event_stream_path="replay/event_stream.ndjson",
                snapshot_reference_path="snapshots/latest_server.json",
                baseline_reason="socket",
                required_ids=REQUIRED_REPLAY_IDS,
                notes=[
                    "Socket transport frames are copied into replay/event_stream.ndjson on FAIL, BLOCKED, explicit replay retention, or compare-mode parity capture.",
                ],
            )
        )
        preserve_live_replay = (
            self.save_replay
            or status != ScenarioStatus.PASS
            or scenario.scenario_id in {"MP-004", "MP-008"}
            or self.socket_transport == "compare"
        )
        if preserve_live_replay:
            store.write_replay_placeholder(
                "snapshot_reference.json",
                {
                    "snapshotPath": "snapshots/latest_server.json",
                    "scenarioId": scenario.scenario_id,
                    "status": status.value,
                },
            )
            store.append_ndjson("replay/event_stream.ndjson", socket_result.get("frames", []))
            self._write_scenario_specific_artifacts(store, scenario, status, artifact_source=socket_result)

        store.write_text(
            "ui/README.md",
            "# UI Artifacts\n\nSocket mode does not capture screenshots directly. Save manual debug or simulator evidence here when a live transport run diverges.\n",
        )

        checklist_lines = ["# Checklist Report", ""]
        checklist_lines.extend(
            [
                f"- [{'x' if status is ScenarioStatus.PASS else ' '}] {item}"
                for item in scenario.assertions
            ]
        )
        store.write_checklist(checklist_lines)

        if status in {ScenarioStatus.BLOCKED, ScenarioStatus.FAIL}:
            anomaly = AnomalyReport(
                scenario_id=scenario.scenario_id,
                run_id=run_id,
                title=f"{scenario.scenario_id} Socket Blockers",
                expected_behavior="Socket-backed multiplayer validation should complete against the room_transport_* live transport spike.",
                observed_behavior=summary,
                first_bad_transition="Socket mode stopped before full scenario completion.",
                last_good_event_id="TBD",
                last_good_state_version="TBD",
                failure_class="TEST_HARNESS" if status is ScenarioStatus.BLOCKED else "RUNTIME",
                reproduction_command="python3 tests/test_agent/multiplayer_runner.py --scenario "
                f"{scenario.scenario_id} --mode socket --transport {self.socket_transport}",
                artifact_links=[
                    "manifest.json",
                    "timeline/commands.ndjson",
                    "timeline/events.ndjson",
                    "replay/replay_manifest.json",
                    "transport_parity.json",
                ],
                open_questions=list(blocking_reasons),
            )
            store.write_anomaly(anomaly)

        store.write_summary(self._build_summary(scenario, manifest, status) + f"\nSocket Summary: {summary}\n")

        return ScenarioResult(
            scenario=scenario,
            status=status,
            summary=summary,
            run_id=run_id,
            artifact_root=str(store.run_root),
            blocking_reasons=list(blocking_reasons),
        )

    def _build_summary(
        self,
        scenario: ScenarioDefinition,
        manifest: RunManifest,
        status: ScenarioStatus,
    ) -> str:
        skeleton = SCENARIO_SKELETONS[scenario.scenario_id]
        lines = [
            f"# {scenario.scenario_id} {scenario.name}",
            "",
            "## Run",
            f"- Mode: {manifest.mode}",
            f"- Transport: {manifest.transport or 'n/a'}",
            f"- Result: {status.value}",
            f"- Focus: {scenario.focus}",
            "",
            "## Description",
            scenario.description,
            "",
            "## Skeleton Purpose",
            skeleton.purpose,
            "",
            "## Planned Steps",
        ]
        lines.extend(
            [
                f"{index + 1}. [{step.kind.value}] {step.label}"
                for index, step in enumerate(skeleton.steps)
            ]
        )
        lines.extend(["", "## Observability"])
        lines.extend([f"- {item}" for item in scenario.observability])
        lines.extend(["", "## Required Artifacts"])
        lines.extend([f"- {item}" for item in scenario.required_artifacts])
        lines.extend(["", "## Contract Questions"])
        if scenario.contract_questions:
            lines.extend([f"- {item}" for item in scenario.contract_questions])
        else:
            lines.append("- None")
        lines.extend(["", "## Notes"])
        if scenario.notes:
            lines.extend([f"- {item}" for item in scenario.notes])
        else:
            lines.append("- None")
        lines.append("")
        return "\n".join(lines)

    def _write_scenario_specific_artifacts(
        self,
        store: MultiplayerArtifactStore,
        scenario: ScenarioDefinition,
        status: ScenarioStatus,
        artifact_source: dict | None = None,
    ) -> None:
        if scenario.scenario_id != "MP-008":
            return

        injection_manifest = {
            "scenarioId": scenario.scenario_id,
            "status": status.value,
            "executionReadiness": "stale-version-path-locked",
            "injectedMismatchMode": "staleExpectedStateVersion",
            "clientStateVersion": None,
            "expectedStateVersion": None,
            "authoritativeStateVersion": None,
            "authoritativeEventId": None,
            "recoverySnapshotReason": "resync",
            "recoverySnapshotId": None,
            "notes": list(scenario.notes),
        }
        mismatch_rows = [
            {
                "kind": "mismatch_placeholder",
                "scenarioId": scenario.scenario_id,
                "status": status.value,
                "injectedMismatchMode": "staleExpectedStateVersion",
                "clientStateVersion": None,
                "expectedStateVersion": None,
                "authoritativeStateVersion": None,
                "authoritativeEventId": None,
                "recoverySnapshotReason": "resync",
                "recoverySnapshotId": None,
                "message": "Populate the fixed stale-version mismatch cursor during live execution.",
            }
        ]

        if artifact_source is not None:
            injection_manifest.update(artifact_source.get("injectionPlan", {}))
            mismatch_rows = list(artifact_source.get("mismatchFrames", mismatch_rows))

        store.write_replay_placeholder("injection_manifest.json", injection_manifest)
        store.append_ndjson("timeline/mismatch.ndjson", mismatch_rows)

    def _ensure_socket_binary(self) -> Path:
        if self._resolved_socket_binary is None:
            self._resolved_socket_binary = resolve_socket_binary(
                self.repo_root,
                binary_path=self.binary_path,
                derived_data=self.derived_data,
                skip_build=self.skip_build,
            )
        return self._resolved_socket_binary
