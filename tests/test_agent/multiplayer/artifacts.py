from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .models import AnomalyReport, ReplayManifest, RunManifest, SnapshotRecord


class MultiplayerArtifactStore:
    def __init__(self, output_root: Path, scenario_id: str, run_id: str):
        self.output_root = output_root
        self.scenario_id = scenario_id
        self.run_id = run_id
        self.run_root = output_root / scenario_id / run_id
        self.logs_dir = self.run_root / "logs"
        self.timeline_dir = self.run_root / "timeline"
        self.snapshots_dir = self.run_root / "snapshots"
        self.replay_dir = self.run_root / "replay"
        self.ui_dir = self.run_root / "ui"

    def initialize_layout(self) -> None:
        for directory in (
            self.logs_dir,
            self.timeline_dir,
            self.snapshots_dir,
            self.replay_dir,
            self.ui_dir,
        ):
            directory.mkdir(parents=True, exist_ok=True)

    def write_manifest(self, manifest: RunManifest) -> Path:
        return self._write_json(self.run_root / "manifest.json", manifest.to_dict())

    def write_snapshot(self, filename: str, snapshot: SnapshotRecord) -> Path:
        return self._write_json(self.snapshots_dir / filename, snapshot.to_dict())

    def write_replay_manifest(self, replay: ReplayManifest) -> Path:
        return self._write_json(self.replay_dir / "replay_manifest.json", replay.to_dict())

    def write_replay_placeholder(self, name: str, payload: dict[str, Any]) -> Path:
        return self._write_json(self.replay_dir / name, payload)

    def write_anomaly(self, report: AnomalyReport) -> Path:
        path = self.run_root / "anomaly_report.md"
        path.write_text(report.to_markdown(), encoding="utf-8")
        return path

    def write_summary(self, content: str) -> Path:
        path = self.run_root / "summary.md"
        path.write_text(content, encoding="utf-8")
        return path

    def write_text(self, relative_path: str, content: str) -> Path:
        path = self.run_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def write_checklist(self, lines: list[str]) -> Path:
        path = self.run_root / "checklist_report.md"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def write_log(self, filename: str, lines: list[str]) -> Path:
        path = self.logs_dir / filename
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def append_ndjson(self, relative_path: str, rows: list[dict[str, Any]]) -> Path:
        path = self.run_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True))
                handle.write("\n")
        return path

    def relative_to_run_root(self, path: Path) -> str:
        return str(path.relative_to(self.run_root))

    def _write_json(self, path: Path, payload: dict[str, Any]) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return path
