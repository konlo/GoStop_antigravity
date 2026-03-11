from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


def _normalize(value: Any) -> Any:
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_normalize(item) for item in value]
    return value


class ScenarioStatus(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    PENDING = "PENDING"
    BLOCKED = "BLOCKED"
    MANUAL = "MANUAL"


@dataclass(frozen=True)
class ManifestPlayer:
    player_id: str
    seat: int | None = None
    connection_state: str | None = None


@dataclass(frozen=True)
class ScenarioDefinition:
    scenario_id: str
    name: str
    priority: str
    automation: str
    focus: str
    description: str
    steps: list[str]
    assertions: list[str]
    observability: list[str]
    required_events: list[str]
    required_artifacts: list[str]
    transport_sequence: list[str] = field(default_factory=list)
    contract_questions: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return _normalize(asdict(self))


@dataclass(frozen=True)
class RunManifest:
    run_id: str
    scenario_id: str
    scenario_name: str
    priority: str
    automation: str
    focus: str
    result: ScenarioStatus
    started_at: str
    mode: str
    transport: str | None = None
    trace_id: str | None = None
    room_id: str | None = None
    game_id: str | None = None
    players: list[ManifestPlayer] = field(default_factory=list)
    contract_questions: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return _normalize(asdict(self))


@dataclass(frozen=True)
class SnapshotRecord:
    snapshot_id: str
    source: str
    scope: str
    captured_at: str
    player_id: str | None
    state_version: int | None
    event_id: str | None
    state_hash: str
    payload: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return _normalize(asdict(self))


@dataclass(frozen=True)
class ReplayManifest:
    run_id: str
    scenario_id: str
    event_stream_path: str
    snapshot_reference_path: str
    baseline_reason: str
    required_ids: list[str]
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return _normalize(asdict(self))


@dataclass(frozen=True)
class AnomalyReport:
    scenario_id: str
    run_id: str
    title: str
    expected_behavior: str
    observed_behavior: str
    first_bad_transition: str
    last_good_event_id: str
    last_good_state_version: str
    failure_class: str
    reproduction_command: str
    artifact_links: list[str] = field(default_factory=list)
    open_questions: list[str] = field(default_factory=list)

    def to_markdown(self) -> str:
        lines = [
            f"# {self.title}",
            "",
            "## Metadata",
            f"- Scenario: {self.scenario_id}",
            f"- Run ID: {self.run_id}",
            f"- Failure Class: {self.failure_class}",
            "",
            "## Expected",
            self.expected_behavior,
            "",
            "## Observed",
            self.observed_behavior,
            "",
            "## First Bad Transition",
            self.first_bad_transition,
            "",
            "## Last Good Cursor",
            f"- eventId: {self.last_good_event_id}",
            f"- stateVersion: {self.last_good_state_version}",
            "",
            "## Reproduction",
            f"`{self.reproduction_command}`",
            "",
            "## Artifact Links",
        ]
        if self.artifact_links:
            lines.extend([f"- {item}" for item in self.artifact_links])
        else:
            lines.append("- TBD")

        lines.extend(["", "## Open Questions"])
        if self.open_questions:
            lines.extend([f"- {item}" for item in self.open_questions])
        else:
            lines.append("- None")
        lines.append("")
        return "\n".join(lines)


@dataclass(frozen=True)
class ScenarioResult:
    scenario: ScenarioDefinition
    status: ScenarioStatus
    summary: str
    run_id: str
    artifact_root: str
    blocking_reasons: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "scenarioId": self.scenario.scenario_id,
            "status": self.status.value,
            "summary": self.summary,
            "runId": self.run_id,
            "artifactRoot": self.artifact_root,
            "blockingReasons": list(self.blocking_reasons),
        }
