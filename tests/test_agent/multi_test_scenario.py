#!/usr/bin/env python3

from __future__ import annotations

import argparse
import ast
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
SINGLE_PLAYER_SCENARIO_FILE = SCRIPT_DIR / "test_scenarios.py"
UI_SCENARIO_FILE = SCRIPT_DIR / "multiplayer_ui_auto_play.py"

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from multiplayer import ALL_SCENARIOS, P0_SCENARIOS, SCENARIO_REGISTRY, SCENARIO_SUITES  # noqa: E402
from multiplayer import MultiplayerScenarioRunner  # noqa: E402
from multiplayer_runner import _default_output_root, _write_suite_summary  # noqa: E402


@dataclass(frozen=True)
class ScenarioTrack:
    track_id: str
    name: str
    state: str
    description: str
    runner_scenarios: tuple[str, ...] = ()
    notes: tuple[str, ...] = ()


@dataclass(frozen=True)
class CoverageRecord:
    source_name: str
    track: ScenarioTrack
    classification_reason: str


@dataclass(frozen=True)
class UIScenarioSelection:
    scenario_id: str


RUNNER_TRACKS = {
    scenario.scenario_id: ScenarioTrack(
        track_id=scenario.scenario_id,
        name=scenario.name,
        state="runnable",
        description=scenario.focus,
        runner_scenarios=(scenario.scenario_id,),
        notes=tuple(scenario.notes),
    )
    for scenario in ALL_SCENARIOS
}

BACKLOG_TRACKS = {
    "MM-B01": ScenarioTrack(
        track_id="MM-B01",
        name="Scoring and terminal settlement parity backlog",
        state="planned",
        description=(
            "Migrate single-player scoring, penalties, Go/Stop settlement, and boundary "
            "score regressions into deterministic multiplayer fixture coverage."
        ),
        runner_scenarios=("MP-002",),
        notes=(
            "Use MP-002 terminal lifecycle as the anchor while extending deterministic end-state fixtures.",
        ),
    ),
    "MM-B02": ScenarioTrack(
        track_id="MM-B02",
        name="Shake and choice gameplay backlog",
        state="planned",
        description=(
            "Expand beyond privacy-only shake coverage into gameplay choices, decline/capture "
            "branches, and multiplier stacking under multiplayer authority."
        ),
        runner_scenarios=("MP-005", "MP-013"),
        notes=(
            "Current runnable coverage locks invalid choice handling and shake actor-only visibility only.",
        ),
    ),
    "MM-B03": ScenarioTrack(
        track_id="MM-B03",
        name="Special moves and pi transfer backlog",
        state="planned",
        description=(
            "Port bomb, sweep, ttadak, jjok, acquisition ordering, opponent capture, and pi "
            "transfer regressions into multiplayer-ready deterministic scenarios."
        ),
        runner_scenarios=("MP-002", "MP-005"),
        notes=(
            "This backlog is primarily gameplay-rule migration from single-player scenarios.",
        ),
    ),
    "MM-B04": ScenarioTrack(
        track_id="MM-B04",
        name="Exceptional round-end rules backlog",
        state="planned",
        description=(
            "Add multiplayer fixtures for Chongtong, Seolsa, Nagari, and other abrupt terminal "
            "paths that need authoritative round-end parity."
        ),
        runner_scenarios=("MP-002", "MP-007", "MP-008"),
        notes=(
            "Timeout/forfeit and resync transport hardening already exist; gameplay-triggered abrupt ends still need migration.",
        ),
    ),
    "MM-B05": ScenarioTrack(
        track_id="MM-B05",
        name="Chrysanthemum and conditional role backlog",
        state="planned",
        description=(
            "Migrate month-9 conditional role handling, choice persistence, and score accounting "
            "into multiplayer fixtures and later socket smoke."
        ),
        runner_scenarios=("MP-002", "MP-005"),
        notes=(
            "Choice plumbing from MP-005 is the likely reusable base for role-selection flows.",
        ),
    ),
    "MM-B06": ScenarioTrack(
        track_id="MM-B06",
        name="Multiplayer UI projection regression backlog",
        state="planned",
        description=(
            "Track authoritative projection and UI deferral regressions that must remain stable "
            "when hidden information, popup ordering, or capture visibility is involved."
        ),
        runner_scenarios=("MP-013",),
        notes=(
            "These scenarios should stay separated from single-player UI harness execution and be replayable from multiplayer artifacts.",
        ),
    ),
    "MM-B07": ScenarioTrack(
        track_id="MM-B07",
        name="Harness controls and state scaffolding backlog",
        state="planned",
        description=(
            "Maintain multiplayer-specific debug/setup surfaces that replace single-player "
            "set_condition smoke, crash probes, and low-level harness sanity checks."
        ),
        runner_scenarios=("MP-001", "MP-006", "MP-008", "MP-014"),
        notes=(
            "Keep the multiplayer harness separate from the single-player TestAgent registry while still tracing coverage intent.",
        ),
    ),
}

TRACK_REGISTRY: dict[str, ScenarioTrack] = {**RUNNER_TRACKS, **BACKLOG_TRACKS}
UI_SUPPORTED_SCENARIOS = {"MP-016", "MP-017", "MP-018", "MP-019"}

MANAGED_SUITES: dict[str, tuple[str, ...]] = {
    "managed-all-runnable": tuple(scenario.scenario_id for scenario in ALL_SCENARIOS),
    "managed-p0": tuple(scenario.scenario_id for scenario in P0_SCENARIOS),
    "managed-transport-hardening": ("MP-001", "MP-003", "MP-004", "MP-006", "MP-007", "MP-008", "MP-014"),
    "managed-choice-visibility": ("MP-005", "MP-013"),
    "managed-terminal-consistency": ("MP-002", "MP-007", "MP-008"),
    "managed-bootstrap-smoke": ("MP-001", "MP-006", "MP-014", "MP-015"),
    "managed-room-readiness-guard": ("MP-015",),
    "managed-end-to-end-always-go": ("MP-016",),
    "managed-capture-visibility-short": ("MP-017",),
}


def discover_single_player_scenarios() -> list[str]:
    tree = ast.parse(SINGLE_PLAYER_SCENARIO_FILE.read_text(encoding="utf-8"))
    names = [
        node.name
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name.startswith("scenario_")
    ]

    deduped: list[str] = []
    seen: set[str] = set()
    for name in reversed(names):
        if name in seen:
            continue
        deduped.append(name)
        seen.add(name)
    deduped.reverse()
    return deduped


def classify_single_player_scenario(name: str) -> tuple[str, str]:
    if name in {
        "scenario_verify_endgame_stats_validation",
        "scenario_verify_endgame_conditions",
        "scenario_verify_nagari_end_flow",
    }:
        return "MP-002", "directly supported by deterministic terminal summary coverage"
    if name in {"scenario_force_crash_capture"}:
        return "MM-B07", "harness/state scaffolding"
    if name in {"scenario_verify_capture_choice"}:
        return "MP-005", "directly supported by multiplayer choice-reject/pending-choice coverage"
    if name in {
        "scenario_verify_initial_shake",
        "scenario_verify_shake_decline",
        "scenario_verify_shake_then_capture",
        "scenario_verify_ai_shake",
    }:
        return "MP-013", "directly supported by shake choice visibility/projection coverage"
    if name in {"scenario_verify_card_integrity_full_game", "scenario_verify_go_bonuses"}:
        return "MP-016", "directly supported by end-to-end multiplayer always-go coverage"
    if any(
        token in name
        for token in (
            "captured_brights_visible",
            "draw_choice_trigger_bright_visible",
            "play_capture_animates_before_draw_reveal",
            "play_choice_capture_animates_before_draw_reveal",
        )
    ):
        return "MP-017", "directly supported by the short multiplayer capture-visibility probe"
    if name in {"scenario_bugfix_block_score_claim_until_opponent_captures"}:
        return "MM-B01", "scoring or terminal settlement"
    if any(token in name for token in ("end_summary", "decision_overlay")):
        return "MM-B06", "ui/projection regression"
    if any(token in name for token in ("chongtong", "seolsa", "nagari", "mungdda")):
        return "MM-B04", "exceptional round-end rule"
    if any(token in name for token in ("chrysanthemum", "conditional_double_pi", "missing_dec_card")):
        return "MM-B05", "conditional role / month-9 rule"
    if any(token in name for token in ("shake", "capture_choice")):
        return "MM-B02", "shake or choice gameplay"
    if any(
        token in name
        for token in (
            "bomb",
            "sweep",
            "ttadak",
            "jjok",
            "capture",
            "acquisition",
            "pi_transfer",
            "pi_unit",
            "opponent_",
            "special_moves",
        )
    ):
        return "MM-B03", "special move / capture flow"
    if any(
        token in name
        for token in (
            "scoring",
            "score",
            "penalties",
            "go_bonuses",
            "pibak",
            "gwangbak",
            "mungbak",
            "jabak",
            "yeokbak",
            "endgame_stats",
            "endgame_conditions",
            "exponential_multipliers",
            "samgwang",
        )
    ):
        return "MM-B01", "scoring or terminal settlement"
    if any(
        token in name
        for token in (
            "basic_launch",
            "setup_condition",
            "force_crash",
            "safety_limit",
            "configuration_yaml",
            "card_integrity",
            "monthly_pair_integrity",
            "dummy_draw_phase",
            "no_residual_cards",
        )
    ):
        return "MM-B07", "harness/state scaffolding"
    return "MM-B07", "fallback backlog triage"


def build_coverage_records() -> list[CoverageRecord]:
    records: list[CoverageRecord] = []
    for source_name in discover_single_player_scenarios():
        track_id, reason = classify_single_player_scenario(source_name)
        records.append(
            CoverageRecord(
                source_name=source_name,
                track=TRACK_REGISTRY[track_id],
                classification_reason=reason,
            )
        )
    return records


def print_track_list() -> None:
    print("\n--- Managed Multiplayer Tracks ---")
    for track_id in sorted(TRACK_REGISTRY):
        track = TRACK_REGISTRY[track_id]
        runner_ids = ", ".join(track.runner_scenarios) if track.runner_scenarios else "-"
        print(f"{track.track_id}\t{track.state}\t{runner_ids}\t{track.name}")
    print("----------------------------------\n")


def print_suite_list() -> None:
    print("\n--- Managed Suites ---")
    for suite_name, scenario_ids in sorted(MANAGED_SUITES.items()):
        print(f"{suite_name}\t{', '.join(scenario_ids)}")
    print("\n--- Raw Runner Suites ---")
    for suite_name, scenarios in sorted(SCENARIO_SUITES.items()):
        print(f"{suite_name}\t{', '.join(scenario.scenario_id for scenario in scenarios)}")
    print("------------------------\n")


def print_single_player_sources() -> None:
    print("\n--- Single-Player Source Scenarios ---")
    for index, name in enumerate(discover_single_player_scenarios(), start=1):
        print(f"[{index:02d}] {name}")
    print("--------------------------------------\n")


def print_coverage_report(records: list[CoverageRecord]) -> None:
    grouped: dict[str, list[CoverageRecord]] = defaultdict(list)
    runnable_source_count = 0
    for record in records:
        grouped[record.track.track_id].append(record)
        if record.track.state == "runnable":
            runnable_source_count += 1

    print("\n--- Multiplayer Coverage Report ---")
    print(f"single-player sources: {len(records)}")
    print(f"mapped to runnable multiplayer tracks: {runnable_source_count}")
    print(f"mapped to planned multiplayer backlog: {len(records) - runnable_source_count}")
    print("")
    for track_id in sorted(grouped):
        track = TRACK_REGISTRY[track_id]
        runner_ids = ", ".join(track.runner_scenarios) if track.runner_scenarios else "-"
        print(f"{track.track_id} [{track.state}] {track.name}")
        print(f"  runner support: {runner_ids}")
        print(f"  description: {track.description}")
        for record in grouped[track_id]:
            print(f"  - {record.source_name} ({record.classification_reason})")
        print("")
    print("-----------------------------------\n")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Managed multiplayer scenario entrypoint. Keeps multiplayer suites separate from "
            "the single-player harness while tracing source coverage from test_scenarios.py."
        )
    )
    parser.add_argument("--list", action="store_true", help="List managed multiplayer tracks.")
    parser.add_argument("--list-suites", action="store_true", help="List managed suites and raw runner suites.")
    parser.add_argument(
        "--list-single",
        action="store_true",
        help="List source scenario function names discovered from test_scenarios.py.",
    )
    parser.add_argument(
        "--coverage",
        action="store_true",
        help="Print single-player to multiplayer coverage mapping.",
    )
    parser.add_argument(
        "--suite",
        help="Managed suite name or raw multiplayer runner suite name.",
    )
    parser.add_argument(
        "--scenario",
        action="append",
        dest="scenario_ids",
        default=[],
        help="Raw multiplayer scenario ID to run. Repeatable.",
    )
    parser.add_argument(
        "--all-runnable",
        action="store_true",
        help="Run every runnable multiplayer scenario currently registered.",
    )
    parser.add_argument(
        "--all-p0",
        action="store_true",
        help="Run every registered P0 multiplayer scenario.",
    )
    parser.add_argument(
        "--mode",
        default="fixture",
        choices=["scaffold", "fixture", "socket", "ui"],
        help="Execution mode for multiplayer scenarios.",
    )
    parser.add_argument(
        "--transport",
        default="tcp",
        choices=["tcp", "websocket", "compare"],
        help="Socket transport backend.",
    )
    parser.add_argument("--output-root", help="Artifact root directory.")
    parser.add_argument("--save-replay", action="store_true", help="Always preserve replay artifacts.")
    parser.add_argument("--binary", help="Prebuilt GoStopCLI binary path for socket mode.")
    parser.add_argument("--derived-data", help="DerivedData root for socket mode.")
    parser.add_argument("--skip-build", action="store_true", help="Disable fresh builds in socket mode.")
    parser.add_argument("--host-udid", default="988B3B75-DD16-49AE-B5D7-B046B19A357C")
    parser.add_argument("--guest-udid", default="01DE5F5D-C372-4BE2-8CAB-3FF25E5AFBFD")
    parser.add_argument("--host-port", type=int, default=8080)
    parser.add_argument("--guest-port", type=int, default=8081)
    parser.add_argument("--transport-url", default="ws://127.0.0.1:9092")
    parser.add_argument("--app-path", help="Optional GoStop.app path for simulator install in ui mode.")
    parser.add_argument("--install-app", action="store_true", help="Reinstall the app on both simulators in ui mode.")
    parser.add_argument("--fast-animation", action="store_true", help="Enable fast animation env flag in ui mode.")
    parser.add_argument("--launch-timeout", type=float, default=40.0, help="Host/guest launch timeout for ui mode.")
    parser.add_argument("--scenario-timeout", type=float, default=180.0, help="Overall scenario timeout for ui mode.")
    parser.add_argument("--poll-interval", type=float, default=0.7, help="Bridge polling interval for ui mode.")
    parser.add_argument("--action-delay", type=float, default=1.1, help="Delay between automated UI actions in ui mode.")
    parser.add_argument("--max-attempts", type=int, default=5, help="Retry budget for ui mode.")
    parser.add_argument("--seed-candidates", default="1,2,3,4,5", help="Comma-separated RNG seeds for ui mode retries.")
    parser.add_argument("--per-seat-turn-limit", type=int, default=6, help="Per-seat playCard limit for draw-capture ui mode.")
    parser.add_argument("--success-hold-seconds", type=float, default=1.2, help="Seconds to keep the successful ui state visible before exiting.")
    parser.add_argument("--capture-final-screenshot", action="store_true", help="Capture final host/guest screenshots in ui mode.")
    parser.add_argument(
        "--fail-on-unmapped",
        action="store_true",
        help="Exit non-zero if any discovered single-player scenario is not explicitly covered.",
    )
    return parser.parse_args()


def _run_ui_scenarios(args: argparse.Namespace, scenarios, suite_name: str | None) -> int:
    scenario_ids = tuple(dict.fromkeys(scenario.scenario_id for scenario in scenarios))
    unsupported = [scenario_id for scenario_id in scenario_ids if scenario_id not in UI_SUPPORTED_SCENARIOS]
    if unsupported:
        raise SystemExit(
            "UI mode currently supports only scenario(s): "
            f"{', '.join(sorted(UI_SUPPORTED_SCENARIOS))}. Unsupported selection: {', '.join(unsupported)}"
        )
    if len(scenario_ids) != 1:
        raise SystemExit("UI mode currently supports exactly one scenario selection.")

    output_root = resolve_output_root(args, suite_name)
    command = [
        sys.executable,
        str(UI_SCENARIO_FILE),
        "--scenario-id",
        scenario_ids[0],
        "--output-root",
        str(output_root),
        "--host-udid",
        args.host_udid,
        "--guest-udid",
        args.guest_udid,
        "--host-port",
        str(args.host_port),
        "--guest-port",
        str(args.guest_port),
        "--transport-url",
        args.transport_url,
        "--launch-timeout",
        str(args.launch_timeout),
        "--scenario-timeout",
        str(args.scenario_timeout),
        "--poll-interval",
        str(args.poll_interval),
        "--action-delay",
        str(args.action_delay),
        "--max-attempts",
        str(args.max_attempts),
        "--seed-candidates",
        args.seed_candidates,
        "--per-seat-turn-limit",
        str(args.per_seat_turn_limit),
        "--success-hold-seconds",
        str(args.success_hold_seconds),
    ]
    if args.app_path:
        command.extend(["--app-path", args.app_path])
    if args.install_app:
        command.append("--install-app")
    if args.fast_animation:
        command.append("--fast-animation")
    if args.capture_final_screenshot:
        command.append("--capture-final-screenshot")

    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.stdout.strip():
        print(completed.stdout.rstrip())
    if completed.stderr.strip():
        print(completed.stderr.rstrip(), file=sys.stderr)

    status = "PASS" if completed.returncode == 0 else "FAIL"
    print(f"{scenario_ids[0]} {status} UI autoroute -> {output_root}")
    return completed.returncode


def resolve_runner_scenarios(args: argparse.Namespace):
    if args.all_runnable:
        return list(ALL_SCENARIOS), "managed-all-runnable", True
    if args.all_p0:
        return list(P0_SCENARIOS), "managed-p0", True
    if args.suite:
        if args.suite in MANAGED_SUITES:
            scenario_ids = MANAGED_SUITES[args.suite]
            return [SCENARIO_REGISTRY[scenario_id] for scenario_id in scenario_ids], args.suite, True
        if args.suite in SCENARIO_SUITES:
            return list(SCENARIO_SUITES[args.suite]), args.suite, True
        raise SystemExit(f"Unknown suite: {args.suite}")
    if args.scenario_ids:
        if args.mode == "ui":
            missing = [scenario_id for scenario_id in args.scenario_ids if scenario_id not in SCENARIO_REGISTRY and scenario_id not in UI_SUPPORTED_SCENARIOS]
            if missing:
                raise SystemExit(f"Unknown scenario IDs: {', '.join(missing)}")
            selections = [
                SCENARIO_REGISTRY[scenario_id] if scenario_id in SCENARIO_REGISTRY else UIScenarioSelection(scenario_id)
                for scenario_id in args.scenario_ids
            ]
            return selections, None, False
        missing = [scenario_id for scenario_id in args.scenario_ids if scenario_id not in SCENARIO_REGISTRY]
        if missing:
            raise SystemExit(f"Unknown scenario IDs: {', '.join(missing)}")
        return [SCENARIO_REGISTRY[scenario_id] for scenario_id in args.scenario_ids], None, False
    return [], None, False


def resolve_output_root(args: argparse.Namespace, suite_name: str | None) -> Path:
    if args.output_root:
        return Path(args.output_root)
    if suite_name and suite_name in SCENARIO_SUITES:
        return _default_output_root(suite_name, args.mode, args.transport)
    if suite_name:
        suffix = f"{args.mode}_{args.transport}" if args.mode == "socket" else args.mode
        return REPO_ROOT / "test_artifacts" / "multiplayer" / "managed" / suite_name / suffix
    return REPO_ROOT / "test_artifacts" / "multiplayer" / "managed" / "ad_hoc"


def run_selected_scenarios(args: argparse.Namespace) -> int:
    scenarios, suite_name, write_suite_summary = resolve_runner_scenarios(args)
    if not scenarios:
        return 0
    if args.mode == "ui":
        return _run_ui_scenarios(args, scenarios, suite_name)

    output_root = resolve_output_root(args, suite_name)
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

    if suite_name and write_suite_summary:
        _write_suite_summary(output_root, suite_name, args.mode, args.transport, results)

    return 0 if all(result.status.value == "PASS" for result in results) else 1


def main() -> int:
    args = _parse_args()
    coverage_records = build_coverage_records()
    should_run = bool(args.suite or args.scenario_ids or args.all_runnable or args.all_p0)
    should_inspect = bool(args.list or args.list_suites or args.list_single or args.coverage)

    if not should_run and not should_inspect:
        args.coverage = True
        args.list_suites = True

    if args.list:
        print_track_list()
    if args.list_suites:
        print_suite_list()
    if args.list_single:
        print_single_player_sources()
    if args.coverage:
        print_coverage_report(coverage_records)

    if args.fail_on_unmapped:
        uncovered = [record for record in coverage_records if record.classification_reason == "fallback backlog triage"]
        if uncovered:
            raise SystemExit(f"Unmapped single-player scenarios: {', '.join(record.source_name for record in uncovered)}")

    return run_selected_scenarios(args)


if __name__ == "__main__":
    raise SystemExit(main())
