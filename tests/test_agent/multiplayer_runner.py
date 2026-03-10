from __future__ import annotations

import argparse
import sys
from pathlib import Path

from multiplayer.runner import MultiplayerScenarioRunner
from multiplayer.scenarios import ALL_SCENARIOS, P0_SCENARIOS, SCENARIO_REGISTRY, SCENARIO_SUITES


def _default_output_root() -> Path:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    return repo_root / "test_artifacts" / "multiplayer"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Multiplayer GoStop test harness scaffold")
    parser.add_argument("--list", action="store_true", help="List registered multiplayer scenarios")
    parser.add_argument(
        "--suite",
        choices=sorted(SCENARIO_SUITES),
        help="Run a predefined suite (`smoke`, `socket-smoke`, `review-fixups`, `all`).",
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
        help="Execution mode. scaffold creates empty skeletons, fixture validates synthetic transcripts, socket drives the room_transport_* live spike.",
    )
    parser.add_argument(
        "--output-root",
        default=str(_default_output_root()),
        help="Artifact root directory",
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
        help="Reuse an existing GoStopCLI binary under --derived-data instead of rebuilding for socket mode.",
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


def main() -> int:
    args = _parse_args()
    if args.list:
        for scenario in ALL_SCENARIOS:
            print(f"{scenario.scenario_id}\t{scenario.priority}\t{scenario.name}")
        return 0

    scenarios = _selected_scenarios(args)
    runner = MultiplayerScenarioRunner(
        output_root=Path(args.output_root),
        mode=args.mode,
        save_replay=args.save_replay,
        binary_path=Path(args.binary) if args.binary else None,
        derived_data=Path(args.derived_data) if args.derived_data else None,
        skip_build=args.skip_build,
    )
    results = runner.run(scenarios)
    for result in results:
        print(
            f"{result.scenario.scenario_id} {result.status.value} "
            f"{result.summary} -> {result.artifact_root}"
        )
        for blocker in result.blocking_reasons:
            print(f"  blocker: {blocker}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
