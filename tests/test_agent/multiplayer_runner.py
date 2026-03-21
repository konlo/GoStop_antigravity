from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from multiplayer.runner import MultiplayerScenarioRunner
from multiplayer.scenarios import ALL_SCENARIOS, P0_SCENARIOS, SCENARIO_REGISTRY, SCENARIO_SUITES


def _base_output_root() -> Path:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    return repo_root / "test_artifacts" / "multiplayer"


def _default_output_root(suite: str | None, mode: str, transport: str) -> Path:
    root = _base_output_root()
    if suite != "final-validation":
        return root

    if mode == "socket":
        bucket = "socket_compare" if transport == "compare" else f"socket_{transport}"
    elif mode == "fixture":
        bucket = "fixture"
    else:
        bucket = "scaffold"
    return root / "round17_final_validation" / bucket


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Multiplayer GoStop test harness scaffold")
    parser.add_argument("--list", action="store_true", help="List registered multiplayer scenarios")
    parser.add_argument(
        "--suite",
        choices=sorted(SCENARIO_SUITES),
        help="Run a predefined suite (`smoke`, `socket-smoke`, `socket-end-to-end`, `socket-parity`, `socket-duplicate`, `socket-review-fixups`, `review-fixups`, `final-validation`, `all`).",
    )
    parser.add_argument(
        "--scenario",
        action="append",
        dest="scenario_ids",
        default=[],
        help="Scenario ID to scaffold. Repeatable.",
    )
    parser.add_argument(
        "--all-p0",
        action="store_true",
        help="Scaffold every registered P0 multiplayer scenario",
    )
    parser.add_argument(
        "--mode",
        default="scaffold",
        choices=["scaffold", "fixture", "socket"],
        help="Execution mode. scaffold creates empty skeletons, fixture validates synthetic transcripts, socket drives the GoStopCLI room transport facades.",
    )
    parser.add_argument(
        "--transport",
        default="tcp",
        choices=["tcp", "websocket", "compare"],
        help="Socket mode transport backend. `compare` runs TCP fallback and websocket path under one artifact root.",
    )
    parser.add_argument(
        "--output-root",
        help="Artifact root directory. `final-validation` defaults to test_artifacts/multiplayer/round17_final_validation/<mode>[_<transport>].",
    )
    parser.add_argument(
        "--save-replay",
        action="store_true",
        help="Always preserve authoritative replay artifacts (replay/), even on PASS.",
    )
    parser.add_argument(
        "--binary",
        help="Prebuilt GoStopCLI binary path for socket mode.",
    )
    parser.add_argument(
        "--derived-data",
        help="DerivedData root used to build or locate GoStopCLI for socket mode.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Disable fresh builds and require --binary or a cached GoStopCLI build for socket mode.",
    )
    return parser.parse_args()


def _selected_scenarios(args: argparse.Namespace):
    if args.all_p0:
        return list(P0_SCENARIOS)
    if args.suite:
        return list(SCENARIO_SUITES[args.suite])
    if args.scenario_ids:
        missing = [scenario_id for scenario_id in args.scenario_ids if scenario_id not in SCENARIO_REGISTRY]
        if missing:
            raise SystemExit(f"Unknown scenario IDs: {', '.join(missing)}")
        return [SCENARIO_REGISTRY[scenario_id] for scenario_id in args.scenario_ids]
    raise SystemExit("Specify --list, --all-p0, --suite, or at least one --scenario.")


def _resolved_output_root(args: argparse.Namespace) -> Path:
    if args.output_root:
        return Path(args.output_root)
    return _default_output_root(args.suite, args.mode, args.transport)


def _write_suite_summary(
    output_root: Path,
    suite_name: str,
    mode: str,
    transport: str,
    results,
) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    payload = {
        "suite": suite_name,
        "mode": mode,
        "transport": transport,
        "scenarioIds": [result.scenario.scenario_id for result in results],
        "results": [result.to_dict() for result in results],
    }
    if suite_name == "final-validation":
        payload["expectedPassCriteria"] = {
            "allStatuses": "PASS",
            "requiredScenarios": ["MP-001", "MP-002", "MP-004", "MP-007", "MP-008", "MP-013", "MP-014"],
            "requiredArtifacts": {
                "MP-001": ["bootstrap_boundary_probe.json", "transport_parity.json"],
                "MP-002": ["transport_parity.json", "replay/replay_manifest.json"],
                "MP-004": ["duplicate_probe.json", "transport_parity.json"],
                "MP-007": ["timeout_probe.json", "transport_parity.json"],
                "MP-008": [
                    "replay/injection_manifest.json",
                    "replay/gap_recovery_shape.json",
                    "replay/gap_recovery_probe.json",
                    "replay/gap_injection_plan.json",
                ],
                "MP-013": ["transport_parity.json", "snapshots/player_a_initial.json", "snapshots/player_b_initial.json"],
                "MP-014": ["heartbeat_probe.json", "stale_heartbeat_code_probe.json", "transport_parity.json"],
            },
        }

    (output_root / "suite_summary.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        f"# {suite_name} Suite Summary",
        "",
        f"- Mode: {mode}",
        f"- Transport: {transport}",
        f"- Scenario Count: {len(results)}",
        "",
        "## Results",
    ]
    for result in results:
        lines.extend(
            [
                f"- {result.scenario.scenario_id}: {result.status.value}",
                f"  artifactRoot: {result.artifact_root}",
                f"  summary: {result.summary}",
            ]
        )
        for blocker in result.blocking_reasons:
            lines.append(f"  blocker: {blocker}")
    if suite_name == "final-validation":
        lines.extend(
            [
                "",
                "## Expected PASS Criteria",
                "- MP-001: bootstrap_boundary_probe.json locks boundaryVersion/currentBoundary/recommendedNextActions and paired gameStarted/stateSnapshot(reason=gameStarted).",
                "- MP-002: terminal lifecycle reaches roundEnded, matchEnded, terminalSummary, roomClosed on both transports.",
                "- MP-004: duplicate_probe.json shows exactReplay for exact resend and actionIdConflict for conflicting reuse.",
                "- MP-007: timeout_probe.json shows passiveClose + manualReapUsed=false + progressionMode=automaticExpirySweep.",
                "- MP-008: injection_manifest, gap_recovery_shape, gap_recovery_probe, and gap_injection_plan all exist and live recovery reaches stateSnapshot(reason=resync|gapDetected) as expected.",
                "- MP-013: actor/non-actor projection artifacts preserve shake redaction.",
                "- MP-014: heartbeat_probe.json and stale_heartbeat_code_probe.json preserve invalidResumeState/staleConnectionId parity.",
            ]
        )
    (output_root / "suite_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = _parse_args()
    if args.list:
        for scenario in ALL_SCENARIOS:
            print(f"{scenario.scenario_id}\t{scenario.priority}\t{scenario.name}")
        return 0

    scenarios = _selected_scenarios(args)
    output_root = _resolved_output_root(args)
    runner = MultiplayerScenarioRunner(
        output_root=output_root,
        mode=args.mode,
        save_replay=args.save_replay,
        binary_path=Path(args.binary) if args.binary else None,
        derived_data=Path(args.derived_data) if args.derived_data else None,
        skip_build=args.skip_build,
        socket_transport=args.transport,
    )
    results = runner.run(scenarios)
    for result in results:
        print(
            f"{result.scenario.scenario_id} {result.status.value} "
            f"{result.summary} -> {result.artifact_root}"
        )
        for blocker in result.blocking_reasons:
            print(f"  blocker: {blocker}")
    if args.suite:
        _write_suite_summary(output_root, args.suite, args.mode, args.transport, results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
