#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from multiplayer.socket_transport import JSONLineSocketClient, WebSocketTextClient


DEFAULT_HOST_UDID = "988B3B75-DD16-49AE-B5D7-B046B19A357C"
DEFAULT_GUEST_UDID = "01DE5F5D-C372-4BE2-8CAB-3FF25E5AFBFD"
DEFAULT_BUNDLE_ID = "com.antigravity.GoStop"


class GameplayNotExercisedError(RuntimeError):
    pass


class BridgeConnection:
    def __init__(self, host: str, port: int, label: str) -> None:
        self.host = host
        self.port = port
        self.label = label
        self.sock: socket.socket | None = None

    def connect(self, timeout_seconds: float = 40.0) -> None:
        deadline = time.time() + timeout_seconds
        last_error: Exception | None = None
        while time.time() < deadline:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(3.0)
                sock.connect((self.host, self.port))
                self.sock = sock
                print(f"[{self.label}] bridge connected on {self.host}:{self.port}")
                return
            except Exception as error:  # noqa: BLE001
                last_error = error
                time.sleep(0.5)
        raise RuntimeError(f"[{self.label}] failed to connect to bridge port {self.port}: {last_error}")

    def close(self) -> None:
        if self.sock is None:
            return
        try:
            self.sock.close()
        finally:
            self.sock = None

    def send_action(self, action: str, data: dict | None = None) -> dict:
        if self.sock is None:
            raise RuntimeError(f"[{self.label}] bridge socket is not connected")
        payload = {"action": action}
        if data is not None:
            payload["data"] = data
        message = json.dumps(payload) + "\n"
        self.sock.sendall(message.encode("utf-8"))

        buffer = ""
        while True:
            chunk = self.sock.recv(65536).decode("utf-8")
            if not chunk:
                raise RuntimeError(f"[{self.label}] bridge closed while waiting for {action}")
            buffer += chunk
            if "\n" not in buffer:
                continue
            line, remainder = buffer.split("\n", 1)
            if remainder:
                buffer = remainder
            response = json.loads(line)
            if response.get("status") == "error":
                raise RuntimeError(f"[{self.label}] {action} failed: {response.get('message')}")
            return response

    def get_state(self) -> dict:
        response = self.send_action("get_state")
        data = response.get("data")
        if not isinstance(data, dict):
            raise RuntimeError(f"[{self.label}] get_state returned unexpected payload: {response}")
        return data

    def play_card(self, card_id: str) -> None:
        self.send_action("play_card_by_id", {"cardId": card_id})

    def click_ready(self) -> None:
        self.send_action("click_start_button")

    def perform_control(self, control: str) -> None:
        self.send_action("perform_control", {"control": control})


class AuthoritativeTransportClient:
    def __init__(self, transport_url: str) -> None:
        parsed = urlparse(transport_url)
        host = parsed.hostname or "127.0.0.1"
        if parsed.port is not None:
            port = parsed.port
        elif parsed.scheme in {"ws", "wss"}:
            port = 443 if parsed.scheme == "wss" else 80
        else:
            port = 9091
        if parsed.scheme in {"ws", "wss"}:
            self.client = WebSocketTextClient(host, port)
        else:
            self.client = JSONLineSocketClient(host, port)

    def close(self) -> None:
        self.client.close()

    def send(self, action: str, data: dict | None = None) -> dict:
        response = self.client.send(action, data)
        if response.get("status") == "error":
            raise RuntimeError(f"{action} failed: {response}")
        return response

    def set_rng_seed(self, seed: int) -> dict:
        return self.send("set_condition", {"rng_seed": seed})

    def fetch_projection(self, room_id: str, room_player_id: str) -> dict:
        response = self.send(
            "room_projection_preview",
            {
                "roomId": room_id,
                "viewerPlayerId": room_player_id,
                "snapshotReason": "uiCaptureProbe",
            },
        )
        if response.get("status") != "ok":
            raise RuntimeError(f"room_projection_preview failed: {response}")
        data = response.get("data")
        if not isinstance(data, dict):
            raise RuntimeError(f"room_projection_preview returned unexpected payload: {response}")
        projection = data.get("projection")
        if not isinstance(projection, dict):
            raise RuntimeError(f"room_projection_preview is missing projection: {response}")
        snapshot = projection.get("snapshot")
        if isinstance(snapshot, dict):
            return snapshot
        return projection


class MultiplayerUIScenarioRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.scenario_id = args.scenario_id
        self.seed_candidates = self.parse_seed_candidates(args.seed_candidates)
        self.selected_seed: int | None = None
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        default_root = Path("test_artifacts") / "multiplayer_ui" / self.scenario_slug / timestamp
        self.output_root = Path(args.output_root) if args.output_root else default_root
        self.output_root.mkdir(parents=True, exist_ok=True)
        self.host_conn = BridgeConnection("127.0.0.1", args.host_port, "host")
        self.guest_conn = BridgeConnection("127.0.0.1", args.guest_port, "guest")
        self.authority_conn: AuthoritativeTransportClient | None = None
        self.timeline_path = self.output_root / "timeline.jsonl"
        self.summary_path = self.output_root / "summary.md"
        self.summary_json_path = self.output_root / "summary.json"
        self.action_log_path = self.output_root / "action_log.jsonl"
        self.screen_checks_path = self.output_root / "screen_checks.json"
        self.action_screenshot_root = self.output_root / "action_screens"
        self.action_screenshot_root.mkdir(parents=True, exist_ok=True)
        for path in (
            self.timeline_path,
            self.summary_path,
            self.summary_json_path,
            self.action_log_path,
            self.screen_checks_path,
        ):
            if path.exists():
                path.unlink()
        self.current_attempt = 0
        self.attempts: list[dict] = []
        self.reset_attempt_state()

    def reset_attempt_state(self) -> None:
        self.state_cache: dict[str, dict] = {}
        self.latest_authoritative_state: dict | None = None
        self.terminal_seen = {"host": False, "guest": False}
        self.leave_sent = {"host": False, "guest": False}
        self.live_capture_saved = False
        self.terminal_capture_saved = False
        self.action_counts = {
            "host": {"playCard": 0, "choice": 0, "leaveRoom": 0},
            "guest": {"playCard": 0, "choice": 0, "leaveRoom": 0},
        }
        self.active_capture_probe: dict | None = None
        self.completed_capture_probes: list[dict] = []
        self.capture_probe_failures: list[dict] = []
        self.capture_probe_success_count = 0
        self.action_sequence = 0
        self.pending_screen_check: dict | None = None
        self.completed_screen_checks: list[dict] = []
        self.screen_check_failures: list[dict] = []
        self.active_draw_capture_probe: dict | None = None
        self.completed_draw_capture_probes: list[dict] = []
        self.draw_capture_probe_failures: list[dict] = []
        self.draw_capture_probe_success_count = 0

    @property
    def scenario_slug(self) -> str:
        slugs = {
            "MP-016": "always_go",
            "MP-017": "capture_visibility_short",
            "MP-018": "draw_capture_animation_watch",
        }
        return slugs[self.scenario_id]

    @property
    def scenario_title(self) -> str:
        titles = {
            "MP-016": "Always-Go",
            "MP-017": "Capture Visibility Short",
            "MP-018": "Draw-Capture Animation Watch",
        }
        return titles[self.scenario_id]

    @staticmethod
    def parse_seed_candidates(raw_value: str) -> list[int]:
        candidates: list[int] = []
        for token in raw_value.split(","):
            stripped = token.strip()
            if not stripped:
                continue
            try:
                candidates.append(int(stripped))
            except ValueError as exc:
                raise RuntimeError(f"Invalid seed candidate: {stripped}") from exc
        return candidates or [1, 2, 3, 4, 5]

    def seed_for_attempt(self, attempt: int) -> int:
        index = (attempt - 1) % len(self.seed_candidates)
        return self.seed_candidates[index]

    def prepare_attempt_seed(self, attempt: int) -> None:
        if self.scenario_id != "MP-018":
            self.selected_seed = None
            return
        seed = self.seed_for_attempt(attempt)
        authority = self.ensure_authority_conn()
        authority.set_rng_seed(seed)
        self.selected_seed = seed
        self.record_event("attempt.seed_selected", {"attempt": attempt, "seed": seed})

    def run(self) -> int:
        try:
            if self.args.install_app:
                self.install_app()

            last_error: Exception | None = None
            for attempt in range(1, self.args.max_attempts + 1):
                invite_code = None
                self.current_attempt = attempt
                self.reset_attempt_state()
                self.prepare_attempt_seed(attempt)
                self.record_event("attempt.begin", {"attempt": attempt})
                try:
                    self.launch_host()
                    self.host_conn.connect()
                    host_snapshot = self.wait_for_snapshot(
                        self.host_conn,
                        lambda snapshot: snapshot.get("route") == "room" and ((snapshot.get("room") or {}).get("inviteCode")),
                        timeout_seconds=self.args.launch_timeout,
                    )
                    invite_code = (host_snapshot.get("room") or {}).get("inviteCode")
                    if not invite_code:
                        raise RuntimeError("Host room did not expose an invite code.")
                    self.record_event("invite.ready", {"inviteCode": invite_code})

                    self.launch_guest(invite_code)
                    self.guest_conn.connect()

                    success = self.drive_match()
                    self.attempts.append(self.current_attempt_summary(invite_code, success=success))
                    self.write_summary(success=success, invite_code=invite_code)
                    if self.args.capture_final_screenshot:
                        self.capture_pair("final")
                    return 0 if success else 1
                except GameplayNotExercisedError as exc:
                    last_error = exc
                    self.attempts.append(self.current_attempt_summary(invite_code, success=False, error_message=str(exc)))
                    self.capture_pair("failure")
                    self.record_event("attempt.retry", {"attempt": attempt, "error": str(exc)})
                    if attempt == self.args.max_attempts:
                        raise
                except Exception as exc:  # noqa: BLE001
                    last_error = exc
                    self.attempts.append(self.current_attempt_summary(invite_code, success=False, error_message=str(exc)))
                    self.capture_pair("failure")
                    raise
                finally:
                    self.host_conn.close()
                    self.guest_conn.close()
                    self.close_authority_conn()

            if last_error is not None:
                raise last_error
            raise RuntimeError("UI scenario exited without a final result.")
        except Exception as exc:  # noqa: BLE001
            print(f"[error] {exc}", file=sys.stderr)
            self.write_summary(success=False, invite_code=None, error_message=str(exc))
            return 1

    def install_app(self) -> None:
        if not self.args.app_path:
            raise RuntimeError("--install-app requires --app-path")
        app_path = Path(self.args.app_path).resolve()
        if not app_path.exists():
            raise RuntimeError(f"App path does not exist: {app_path}")
        for udid in (self.args.host_udid, self.args.guest_udid):
            self.run_command(
                ["xcrun", "simctl", "uninstall", udid, self.args.bundle_id],
                allow_failure=True,
            )
            self.run_command(["xcrun", "simctl", "install", udid, str(app_path)])
            self.record_event("app.installed", {"udid": udid, "appPath": str(app_path)})

    def launch_host(self) -> None:
        launch_env = {
            "GOSTOP_MP_AUTOROUTE": "1",
            "GOSTOP_MP_AUTOROLE": "host",
            "SIMULATOR_BRIDGE_PORT": str(self.args.host_port),
            "GOSTOP_MP_TRANSPORT_URL": self.args.transport_url,
        }
        if self.args.fast_animation:
            launch_env["GOSTOP_SIM_FAST_ANIMATION"] = "1"
        self.launch_app(self.args.host_udid, launch_env)
        self.record_event("host.launch", {"udid": self.args.host_udid, "port": str(self.args.host_port)})

    def launch_guest(self, invite_code: str) -> None:
        launch_env = {
            "GOSTOP_MP_AUTOROUTE": "1",
            "GOSTOP_MP_AUTOROLE": "guest",
            "GOSTOP_MP_AUTOINVITE": invite_code,
            "SIMULATOR_BRIDGE_PORT": str(self.args.guest_port),
            "GOSTOP_MP_TRANSPORT_URL": self.args.transport_url,
        }
        if self.args.fast_animation:
            launch_env["GOSTOP_SIM_FAST_ANIMATION"] = "1"
        self.launch_app(self.args.guest_udid, launch_env)
        self.record_event(
            "guest.launch",
            {"udid": self.args.guest_udid, "port": str(self.args.guest_port), "inviteCode": invite_code},
        )

    def launch_app(self, udid: str, launch_env: dict[str, str]) -> None:
        self.run_command(
            ["xcrun", "simctl", "terminate", udid, self.args.bundle_id],
            allow_failure=True,
        )
        env = os.environ.copy()
        for key, value in launch_env.items():
            env[f"SIMCTL_CHILD_{key}"] = value
        self.run_command(["xcrun", "simctl", "launch", udid, self.args.bundle_id], env=env)

    def drive_match(self) -> bool:
        if self.scenario_id == "MP-017":
            return self.drive_short_capture_probe()
        if self.scenario_id == "MP-018":
            return self.drive_draw_capture_animation_probe()

        deadline = time.time() + self.args.scenario_timeout
        while time.time() < deadline:
            host_snapshot = self.host_conn.get_state()
            guest_snapshot = self.guest_conn.get_state()
            self.track_transition("host", host_snapshot)
            self.track_transition("guest", guest_snapshot)

            if host_snapshot.get("route") == "live" and guest_snapshot.get("route") == "live":
                self.latest_authoritative_state = self.fetch_authoritative_live_state(host_snapshot, guest_snapshot)

            self.observe_pending_screen_check(host_snapshot, guest_snapshot)
            if self.pending_screen_check is not None:
                time.sleep(self.pending_screen_poll_interval)
                continue

            if (
                not self.live_capture_saved
                and host_snapshot.get("route") == "live"
                and guest_snapshot.get("route") == "live"
            ):
                self.capture_pair("live")
                self.live_capture_saved = True

            acted = False
            for label, conn, snapshot, peer_snapshot in (
                ("host", self.host_conn, host_snapshot, guest_snapshot),
                ("guest", self.guest_conn, guest_snapshot, host_snapshot),
            ):
                if self.drive_snapshot(label, conn, snapshot, peer_snapshot=peer_snapshot):
                    acted = True
                    self.settle_after_action()
                    break

            if (
                not self.terminal_capture_saved
                and self.terminal_seen["host"]
                and self.terminal_seen["guest"]
            ):
                self.capture_pair("terminal")
                self.terminal_capture_saved = True

            if (
                self.terminal_seen["host"]
                and self.terminal_seen["guest"]
                and host_snapshot.get("route") == "entry"
                and guest_snapshot.get("route") == "entry"
            ):
                return True

            if not acted:
                time.sleep(self.args.poll_interval)

        raise RuntimeError("Timed out before both simulator clients completed the full room -> live -> result -> entry cycle.")

    def drive_short_capture_probe(self) -> bool:
        deadline = time.time() + self.args.scenario_timeout
        while time.time() < deadline:
            host_snapshot = self.host_conn.get_state()
            guest_snapshot = self.guest_conn.get_state()
            self.track_transition("host", host_snapshot)
            self.track_transition("guest", guest_snapshot)

            if host_snapshot.get("route") == "live" and guest_snapshot.get("route") == "live":
                self.latest_authoritative_state = self.fetch_authoritative_live_state(host_snapshot, guest_snapshot)
                self.observe_capture_probe(host_snapshot, guest_snapshot)

            self.observe_pending_screen_check(host_snapshot, guest_snapshot)
            if self.pending_screen_check is not None:
                time.sleep(self.pending_screen_poll_interval)
                continue

            if self.short_capture_probe_complete(host_snapshot, guest_snapshot):
                self.finalize_capture_probe("scenario_complete")
                if self.capture_probe_success_count == 0:
                    raise GameplayNotExercisedError(
                        "The short multiplayer run completed four turns without an authoritative capture to verify."
                    )
                return True

            acted = False
            for label, conn, snapshot, peer_snapshot in (
                ("host", self.host_conn, host_snapshot, guest_snapshot),
                ("guest", self.guest_conn, guest_snapshot, host_snapshot),
            ):
                if self.pending_screen_check is not None:
                    break
                if self.drive_snapshot(label, conn, snapshot, peer_snapshot=peer_snapshot):
                    acted = True
                    self.settle_after_action()
                    break

            if not acted:
                time.sleep(self.args.poll_interval)

        raise RuntimeError("Timed out before the short multiplayer capture probe completed two turns per player.")

    def drive_draw_capture_animation_probe(self) -> bool:
        deadline = time.time() + self.args.scenario_timeout
        while time.time() < deadline:
            host_snapshot = self.host_conn.get_state()
            guest_snapshot = self.guest_conn.get_state()
            self.track_transition("host", host_snapshot)
            self.track_transition("guest", guest_snapshot)

            if host_snapshot.get("route") == "live" and guest_snapshot.get("route") == "live":
                self.latest_authoritative_state = self.fetch_authoritative_live_state(host_snapshot, guest_snapshot)
                if self.observe_draw_capture_probe(host_snapshot, guest_snapshot):
                    self.finalize_draw_capture_probe("scenario_complete")
                    time.sleep(max(0.0, self.args.success_hold_seconds))
                    return True

            self.observe_pending_screen_check(host_snapshot, guest_snapshot)
            if self.pending_screen_check is not None:
                time.sleep(self.pending_screen_poll_interval)
                continue

            if self.draw_capture_probe_exhausted():
                raise GameplayNotExercisedError(
                    "No multiplayer draw-capture animation was observed within the configured turn budget. "
                    f"seed={self.selected_seed} turnLimitPerSeat={self.args.per_seat_turn_limit}"
                )

            acted = False
            for label, conn, snapshot, peer_snapshot in (
                ("host", self.host_conn, host_snapshot, guest_snapshot),
                ("guest", self.guest_conn, guest_snapshot, host_snapshot),
            ):
                if self.drive_draw_capture_snapshot(label, conn, snapshot, peer_snapshot=peer_snapshot):
                    acted = True
                    self.settle_after_action()
                    break

            if not acted:
                time.sleep(self.args.poll_interval)

        raise RuntimeError("Timed out before the multiplayer draw-capture animation probe observed a qualifying turn.")

    def drive_snapshot(
        self,
        label: str,
        conn: BridgeConnection,
        snapshot: dict,
        *,
        peer_snapshot: dict | None,
    ) -> bool:
        if self.scenario_id == "MP-017":
            return self.drive_short_snapshot(label, conn, snapshot, peer_snapshot=peer_snapshot)

        route = snapshot.get("route")
        if route == "room":
            room = snapshot.get("room") or {}
            local_member = next((member for member in room.get("members", []) if member.get("isLocalPlayer")), None)
            can_ready = (
                room.get("roomState") == "waitingForReady"
                and len(room.get("members", [])) == 2
                and isinstance(local_member, dict)
                and local_member.get("presence") == "connected"
                and not local_member.get("ready")
            )
            if can_ready:
                conn.click_ready()
                self.record_event("room.ready.click", {"player": label, "roomId": room.get("roomId")})
                return True
            return False

        if route == "live":
            live = snapshot.get("live") or {}
            local_player_id = live.get("localPlayerId")
            if live.get("phase") == "matchEnded":
                if self.total_gameplay_actions == 0:
                    raise GameplayNotExercisedError(
                        "Match reached matchEnded before any gameplay actions were observed. "
                        "The simulator scenario did not exercise the intended end-to-end flow."
                    )
                self.terminal_seen[label] = True
                if not self.leave_sent[label]:
                    conn.perform_control("leaveRoom")
                    self.leave_sent[label] = True
                    self.action_counts[label]["leaveRoom"] += 1
                    self.record_event(
                        "live.leave_after_match_end",
                        {
                            "player": label,
                            "roomId": live.get("roomId"),
                            "gameId": live.get("gameId"),
                            "stateVersion": live.get("stateVersion"),
                        },
                    )
                    return True
                return False

            pending_choice = live.get("pendingChoice")
            if (
                isinstance(pending_choice, dict)
                and pending_choice.get("actorPlayerId") == local_player_id
            ):
                option_code = self.pick_choice_option(pending_choice)
                if option_code:
                    if peer_snapshot is not None:
                        self.register_screen_check(
                            label,
                            "choiceSubmit",
                            {
                                "choiceId": pending_choice.get("choiceId"),
                                "choiceKind": pending_choice.get("choiceKind"),
                                "optionCode": option_code,
                            },
                            actor_snapshot=snapshot,
                            peer_snapshot=peer_snapshot,
                        )
                    self.submit_choice(conn, pending_choice, option_code)
                    self.action_counts[label]["choice"] += 1
                    self.record_event(
                        "choice.submit",
                        {
                            "player": label,
                            "choiceId": pending_choice.get("choiceId"),
                            "choiceKind": pending_choice.get("choiceKind"),
                            "optionCode": option_code,
                        },
                    )
                    return True

            if live.get("currentPlayerId") == local_player_id and live.get("phase") == "inTurn":
                card = self.select_play_card(live)
                if card:
                    if peer_snapshot is not None:
                        self.register_screen_check(
                            label,
                            "playCard",
                            {
                                "cardId": card.get("cardId"),
                                "month": str(card.get("month")),
                                "kind": card.get("kind"),
                                "turnCount": self.action_counts[label]["playCard"] + 1,
                            },
                            actor_snapshot=snapshot,
                            peer_snapshot=peer_snapshot,
                        )
                    conn.play_card(card["cardId"])
                    self.action_counts[label]["playCard"] += 1
                    self.record_event(
                        "play_card",
                        {
                            "player": label,
                            "cardId": card.get("cardId"),
                            "month": str(card.get("month")),
                            "kind": card.get("kind"),
                        },
                    )
                    return True
            return False

        if route == "result":
            self.terminal_seen[label] = True
            result = snapshot.get("result") or {}
            if result.get("leavePolicy") == "leaveAvailable" and not self.leave_sent[label]:
                conn.perform_control("leaveRoom")
                self.leave_sent[label] = True
                self.action_counts[label]["leaveRoom"] += 1
                self.record_event(
                    "result.leave",
                    {
                        "player": label,
                        "endReasonCode": result.get("endReasonCode"),
                        "winnerPlayerId": result.get("winnerPlayerId"),
                    },
                )
                return True
            return False

        return False

    def drive_short_snapshot(
        self,
        label: str,
        conn: BridgeConnection,
        snapshot: dict,
        *,
        peer_snapshot: dict | None,
    ) -> bool:
        route = snapshot.get("route")
        if route == "room":
            room = snapshot.get("room") or {}
            local_member = next((member for member in room.get("members", []) if member.get("isLocalPlayer")), None)
            can_ready = (
                room.get("roomState") == "waitingForReady"
                and len(room.get("members", [])) == 2
                and isinstance(local_member, dict)
                and local_member.get("presence") == "connected"
                and not local_member.get("ready")
            )
            if can_ready:
                conn.click_ready()
                self.record_event("room.ready.click", {"player": label, "roomId": room.get("roomId")})
                return True
            return False

        if route != "live":
            return False

        live = snapshot.get("live") or {}
        local_player_id = live.get("localPlayerId")
        if live.get("phase") == "matchEnded":
            raise GameplayNotExercisedError("The short multiplayer capture probe ended before completing two turns per player.")

        pending_choice = live.get("pendingChoice")
        if (
            isinstance(pending_choice, dict)
            and pending_choice.get("actorPlayerId") == local_player_id
        ):
            option_code = self.pick_choice_option(pending_choice)
            if option_code:
                if peer_snapshot is not None:
                    self.register_screen_check(
                        label,
                        "choiceSubmit",
                        {
                            "choiceId": pending_choice.get("choiceId"),
                            "choiceKind": pending_choice.get("choiceKind"),
                            "optionCode": option_code,
                        },
                        actor_snapshot=snapshot,
                        peer_snapshot=peer_snapshot,
                    )
                self.submit_choice(conn, pending_choice, option_code)
                self.action_counts[label]["choice"] += 1
                self.record_event(
                    "choice.submit",
                    {
                        "player": label,
                        "choiceId": pending_choice.get("choiceId"),
                        "choiceKind": pending_choice.get("choiceKind"),
                        "optionCode": option_code,
                    },
                )
                return True

        if live.get("currentPlayerId") == local_player_id and live.get("phase") == "inTurn":
            if self.action_counts[label]["playCard"] >= 2:
                return False
            card = self.select_play_card(live)
            if card:
                self.start_capture_probe(label, snapshot)
                if peer_snapshot is not None:
                    self.register_screen_check(
                        label,
                        "playCard",
                        {
                            "cardId": card.get("cardId"),
                            "month": str(card.get("month")),
                            "kind": card.get("kind"),
                            "turnCount": self.action_counts[label]["playCard"] + 1,
                        },
                        actor_snapshot=snapshot,
                        peer_snapshot=peer_snapshot,
                    )
                conn.play_card(card["cardId"])
                self.action_counts[label]["playCard"] += 1
                self.record_event(
                    "play_card",
                    {
                        "player": label,
                        "cardId": card.get("cardId"),
                        "month": str(card.get("month")),
                        "kind": card.get("kind"),
                        "turnCount": self.action_counts[label]["playCard"],
                    },
                )
                return True
        return False

    def drive_draw_capture_snapshot(
        self,
        label: str,
        conn: BridgeConnection,
        snapshot: dict,
        *,
        peer_snapshot: dict | None,
    ) -> bool:
        route = snapshot.get("route")
        if route == "room":
            room = snapshot.get("room") or {}
            local_member = next((member for member in room.get("members", []) if member.get("isLocalPlayer")), None)
            can_ready = (
                room.get("roomState") == "waitingForReady"
                and len(room.get("members", [])) == 2
                and isinstance(local_member, dict)
                and local_member.get("presence") == "connected"
                and not local_member.get("ready")
            )
            if can_ready:
                conn.click_ready()
                self.record_event("room.ready.click", {"player": label, "roomId": room.get("roomId")})
                return True
            return False

        if route != "live":
            return False

        live = snapshot.get("live") or {}
        local_player_id = live.get("localPlayerId")
        if live.get("phase") == "matchEnded":
            raise GameplayNotExercisedError(
                "The multiplayer draw-capture animation probe reached matchEnded before a qualifying draw capture was observed."
            )

        pending_choice = live.get("pendingChoice")
        if (
            isinstance(pending_choice, dict)
            and pending_choice.get("actorPlayerId") == local_player_id
        ):
            option_code = self.pick_choice_option(pending_choice)
            if option_code:
                if peer_snapshot is not None:
                    self.register_screen_check(
                        label,
                        "choiceSubmit",
                        {
                            "choiceId": pending_choice.get("choiceId"),
                            "choiceKind": pending_choice.get("choiceKind"),
                            "optionCode": option_code,
                        },
                        actor_snapshot=snapshot,
                        peer_snapshot=peer_snapshot,
                    )
                self.submit_choice(conn, pending_choice, option_code)
                self.action_counts[label]["choice"] += 1
                self.record_event(
                    "choice.submit",
                    {
                        "player": label,
                        "choiceId": pending_choice.get("choiceId"),
                        "choiceKind": pending_choice.get("choiceKind"),
                        "optionCode": option_code,
                    },
                )
                return True

        if live.get("currentPlayerId") == local_player_id and live.get("phase") == "inTurn":
            if self.action_counts[label]["playCard"] >= self.args.per_seat_turn_limit:
                return False
            card = self.select_play_card(live)
            if card:
                self.start_draw_capture_probe(label, snapshot)
                if peer_snapshot is not None:
                    self.register_screen_check(
                        label,
                        "playCard",
                        {
                            "cardId": card.get("cardId"),
                            "month": str(card.get("month")),
                            "kind": card.get("kind"),
                            "turnCount": self.action_counts[label]["playCard"] + 1,
                        },
                        actor_snapshot=snapshot,
                        peer_snapshot=peer_snapshot,
                    )
                conn.play_card(card["cardId"])
                self.action_counts[label]["playCard"] += 1
                self.record_event(
                    "play_card",
                    {
                        "player": label,
                        "cardId": card.get("cardId"),
                        "month": str(card.get("month")),
                        "kind": card.get("kind"),
                        "turnCount": self.action_counts[label]["playCard"],
                        "seed": self.selected_seed,
                    },
                )
                return True
        return False

    def register_screen_check(
        self,
        label: str,
        action_type: str,
        payload: dict,
        *,
        actor_snapshot: dict,
        peer_snapshot: dict,
    ) -> None:
        if self.pending_screen_check is not None:
            raise RuntimeError("Attempted to register a new screen check before the previous one completed.")
        self.action_sequence += 1
        self.pending_screen_check = {
            "attempt": self.current_attempt,
            "actionIndex": self.action_sequence,
            "actorLabel": label,
            "actionType": action_type,
            "payload": payload,
            "startedAt": datetime.now().isoformat(timespec="seconds"),
            "deadlineMonotonic": time.time() + max(self.args.action_delay + 3.0, 8.0),
            "before": {
                "actor": self.snapshot_screen_summary(actor_snapshot),
                "peer": self.snapshot_screen_summary(peer_snapshot),
                "authoritative": self.summarize_authoritative_state(self.latest_authoritative_state),
            },
        }
        if action_type == "playCard":
            self.pending_screen_check["animationObserved"] = False
            self.pending_screen_check["animationObservation"] = None
        self.record_event(
            "action.logged",
            {
                "actionIndex": self.action_sequence,
                "actorLabel": label,
                "actionType": action_type,
                **payload,
            },
        )

    def observe_pending_screen_check(self, host_snapshot: dict, guest_snapshot: dict) -> None:
        check = self.pending_screen_check
        if check is None:
            return

        actor_snapshot, peer_snapshot = (
            (host_snapshot, guest_snapshot)
            if check["actorLabel"] == "host"
            else (guest_snapshot, host_snapshot)
        )
        self.observe_play_card_animation(check, actor_snapshot, peer_snapshot)
        checks = self.evaluate_screen_check(check, actor_snapshot, peer_snapshot)
        if not all(item["ok"] for item in checks):
            if time.time() <= check["deadlineMonotonic"]:
                return
            failure = {
                "attempt": self.current_attempt,
                "actionIndex": check["actionIndex"],
                "actorLabel": check["actorLabel"],
                "actionType": check["actionType"],
                "payload": check["payload"],
                "before": check["before"],
                "after": {
                    "actor": self.snapshot_screen_summary(actor_snapshot),
                    "peer": self.snapshot_screen_summary(peer_snapshot),
                    "authoritative": self.summarize_authoritative_state(self.latest_authoritative_state),
                },
                "checks": checks,
                "animationObservation": check.get("animationObservation"),
            }
            self.screen_check_failures.append(failure)
            self.append_action_log({**failure, "status": "fail"})
            self.record_event(
                "screen.check.fail",
                {
                    "actionIndex": check["actionIndex"],
                    "actorLabel": check["actorLabel"],
                    "actionType": check["actionType"],
                },
            )
            self.pending_screen_check = None
            raise RuntimeError(
                "Screen state did not catch up to the logged multiplayer action in time. "
                f"actionIndex={check['actionIndex']} actor={check['actorLabel']} actionType={check['actionType']}"
            )

        screenshots = self.capture_action_pair(check["actionIndex"], check["actionType"])
        result = {
            "attempt": self.current_attempt,
            "actionIndex": check["actionIndex"],
            "actorLabel": check["actorLabel"],
            "actionType": check["actionType"],
            "payload": check["payload"],
            "status": "pass",
            "before": check["before"],
            "after": {
                "actor": self.snapshot_screen_summary(actor_snapshot),
                "peer": self.snapshot_screen_summary(peer_snapshot),
                "authoritative": self.summarize_authoritative_state(self.latest_authoritative_state),
            },
            "checks": checks,
            "animationObservation": check.get("animationObservation"),
            "screenshots": screenshots,
            "completedAt": datetime.now().isoformat(timespec="seconds"),
        }
        self.completed_screen_checks.append(result)
        self.append_action_log(result)
        self.record_event(
            "screen.check.pass",
            {
                "actionIndex": check["actionIndex"],
                "actorLabel": check["actorLabel"],
                "actionType": check["actionType"],
            },
        )
        self.pending_screen_check = None

    def evaluate_screen_check(self, check: dict, actor_snapshot: dict, peer_snapshot: dict) -> list[dict]:
        actor_summary = self.snapshot_screen_summary(actor_snapshot)
        peer_summary = self.snapshot_screen_summary(peer_snapshot)
        before_actor = check["before"]["actor"]
        action_type = check["actionType"]
        payload = check["payload"]

        if action_type == "playCard":
            actor_live = actor_snapshot.get("live") or {}
            actor_card_ids = {card.get("cardId") for card in actor_live.get("localHandCards") or [] if isinstance(card, dict)}
            rendered_hand_ids = actor_summary.get("renderedLocalHandCardIds")
            source_hand_ids = actor_summary.get("sourceLocalHandCardIds")
            render_probe_available = isinstance(rendered_hand_ids, list) and isinstance(source_hand_ids, list)
            terminal_transition = (
                actor_summary.get("route") in {"result", "entry"}
                and peer_summary.get("route") in {"result", "entry"}
            )
            deferred_play_choice = (
                actor_summary.get("pendingChoiceId") != before_actor.get("pendingChoiceId")
                and actor_summary.get("pendingChoiceKind") == "shake"
                and payload.get("cardId") in actor_card_ids
            )
            checks = [
                {
                    "name": "routes_live",
                    "ok": terminal_transition or (
                        actor_summary.get("route") == "live" and peer_summary.get("route") == "live"
                    ),
                    "details": {
                        "actorRoute": actor_summary.get("route"),
                        "peerRoute": peer_summary.get("route"),
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "state_version_synced",
                    "ok": actor_summary.get("stateVersion") == peer_summary.get("stateVersion"),
                    "details": {
                        "actorStateVersion": actor_summary.get("stateVersion"),
                        "peerStateVersion": peer_summary.get("stateVersion"),
                    },
                },
                {
                    "name": "played_card_removed_from_actor_hand",
                    "ok": payload.get("cardId") not in actor_card_ids or deferred_play_choice or terminal_transition,
                    "details": {
                        "cardId": payload.get("cardId"),
                        "actorHandCount": actor_summary.get("localHandCount"),
                        "deferredPlayChoice": deferred_play_choice,
                        "pendingChoiceKind": actor_summary.get("pendingChoiceKind"),
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "render_probe_available",
                    "ok": render_probe_available or terminal_transition,
                    "details": {
                        "actorRenderProbePresent": render_probe_available,
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "played_card_removed_from_rendered_hand",
                    "ok": terminal_transition or (
                        render_probe_available and (
                        payload.get("cardId") not in rendered_hand_ids or deferred_play_choice
                        )
                    ),
                    "details": {
                        "cardId": payload.get("cardId"),
                        "renderedHandCount": actor_summary.get("renderedLocalHandCount"),
                        "deferredPlayChoice": deferred_play_choice,
                        "pendingChoiceKind": actor_summary.get("pendingChoiceKind"),
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "rendered_hand_matches_source_hand",
                    "ok": terminal_transition or (
                        render_probe_available and sorted(rendered_hand_ids) == sorted(source_hand_ids)
                    ),
                    "details": {
                        "renderedHandCount": actor_summary.get("renderedLocalHandCount"),
                        "sourceHandCount": actor_summary.get("sourceLocalHandCount"),
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "rendered_captured_matches_source_captured",
                    "ok": terminal_transition or (
                        actor_summary.get("renderedLocalCapturedTotal") is not None
                        and actor_summary.get("renderedLocalCapturedTotal") == actor_summary.get("localCapturedTotal")
                    ),
                    "details": {
                        "renderedLocalCapturedTotal": actor_summary.get("renderedLocalCapturedTotal"),
                        "sourceLocalCapturedTotal": actor_summary.get("localCapturedTotal"),
                        "terminalTransition": terminal_transition,
                    },
                },
                {
                    "name": "screen_progressed_after_action",
                    "ok": (
                        (actor_summary.get("stateVersion") or 0) > (before_actor.get("stateVersion") or 0)
                        or actor_summary.get("pendingChoiceId") != before_actor.get("pendingChoiceId")
                        or actor_summary.get("currentPlayerId") != before_actor.get("currentPlayerId")
                    ),
                    "details": {
                        "beforeStateVersion": before_actor.get("stateVersion"),
                        "afterStateVersion": actor_summary.get("stateVersion"),
                        "beforeCurrentPlayerId": before_actor.get("currentPlayerId"),
                        "afterCurrentPlayerId": actor_summary.get("currentPlayerId"),
                        "beforePendingChoiceId": before_actor.get("pendingChoiceId"),
                        "afterPendingChoiceId": actor_summary.get("pendingChoiceId"),
                    },
                },
                {
                    "name": "shared_animation_observed",
                    "ok": bool(check.get("animationObserved")) or deferred_play_choice or terminal_transition,
                    "details": check.get("animationObservation")
                    or {
                        "deferredPlayChoice": deferred_play_choice,
                        "pendingChoiceKind": actor_summary.get("pendingChoiceKind"),
                        "terminalTransition": terminal_transition,
                    },
                },
            ]
            return checks

        if action_type == "choiceSubmit":
            route_ok = actor_summary.get("route") in {"live", "result", "entry"} and peer_summary.get("route") in {
                "live",
                "result",
                "entry",
            }
            state_synced = True
            if actor_summary.get("route") == "live" and peer_summary.get("route") == "live":
                state_synced = actor_summary.get("stateVersion") == peer_summary.get("stateVersion")
            checks = [
                {
                    "name": "routes_progressed",
                    "ok": route_ok,
                    "details": {
                        "actorRoute": actor_summary.get("route"),
                        "peerRoute": peer_summary.get("route"),
                    },
                },
                {
                    "name": "state_version_synced",
                    "ok": state_synced,
                    "details": {
                        "actorStateVersion": actor_summary.get("stateVersion"),
                        "peerStateVersion": peer_summary.get("stateVersion"),
                    },
                },
                {
                    "name": "pending_choice_cleared_or_changed",
                    "ok": actor_summary.get("pendingChoiceId") != payload.get("choiceId"),
                    "details": {
                        "choiceId": payload.get("choiceId"),
                        "afterPendingChoiceId": actor_summary.get("pendingChoiceId"),
                    },
                },
            ]
            return checks

        raise RuntimeError(f"Unsupported screen-check action type: {action_type}")

    def append_action_log(self, row: dict) -> None:
        with self.action_log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    def capture_action_pair(self, action_index: int, action_type: str) -> dict[str, str]:
        suffix = f"action_{action_index:02d}_{action_type.lower()}"
        host_path = self.action_screenshot_root / f"{suffix}_host.png"
        guest_path = self.action_screenshot_root / f"{suffix}_guest.png"
        self.capture_screenshot(self.args.host_udid, host_path)
        self.capture_screenshot(self.args.guest_udid, guest_path)
        return {"host": str(host_path), "guest": str(guest_path)}

    def snapshot_screen_summary(self, snapshot: dict) -> dict:
        route = snapshot.get("route")
        render_probe = snapshot.get("renderProbe") or {}
        if route == "live":
            live = snapshot.get("live") or {}
            pending_choice = live.get("pendingChoice") or {}
            return {
                "route": route,
                "phase": live.get("phase"),
                "stateVersion": live.get("stateVersion"),
                "currentPlayerId": live.get("currentPlayerId"),
                "localPlayerId": live.get("localPlayerId"),
                "opponentPlayerId": live.get("opponentPlayerId"),
                "pendingChoiceId": pending_choice.get("choiceId"),
                "pendingChoiceKind": pending_choice.get("choiceKind"),
                "localHandCount": len(live.get("localHandCards") or []),
                "localPlayableCount": len(live.get("localPlayableCardIds") or []),
                "tableCount": len(live.get("tableCards") or []),
                "localCapturedTotal": self.captured_zone_total(live.get("localCapturedZone") or {}),
                "opponentCapturedTotal": self.captured_zone_total(live.get("opponentCapturedZone") or {}),
                "renderedLocalHandCount": len(render_probe.get("renderedLocalHandCardIds") or []),
                "sourceLocalHandCount": len(render_probe.get("sourceLocalHandCardIds") or []),
                "renderedLocalHandCardIds": render_probe.get("renderedLocalHandCardIds"),
                "sourceLocalHandCardIds": render_probe.get("sourceLocalHandCardIds"),
                "renderedLocalCapturedTotal": len(render_probe.get("localCapturedCardIds") or []),
                "renderedOpponentCapturedTotal": len(render_probe.get("opponentCapturedCardIds") or []),
                "isAutomationBusy": bool(render_probe.get("isAutomationBusy")),
                "currentMoveSourceZone": render_probe.get("currentMoveSourceZone"),
                "currentMoveTargetZone": render_probe.get("currentMoveTargetZone"),
                "movingCardIds": render_probe.get("movingCardIds") or [],
                "hiddenSourceCardIds": render_probe.get("hiddenSourceCardIds") or [],
                "hiddenTargetCardIds": render_probe.get("hiddenTargetCardIds") or [],
                "recentUXEventTypes": render_probe.get("recentUXEventTypes") or [],
                "recentUXEventCardIds": render_probe.get("recentUXEventCardIds") or [],
                "recentUXEventSummaries": render_probe.get("recentUXEventSummaries") or [],
            }
        if route == "room":
            room = snapshot.get("room") or {}
            local_member = next((member for member in room.get("members", []) if member.get("isLocalPlayer")), None)
            return {
                "route": route,
                "roomId": room.get("roomId"),
                "roomState": room.get("roomState"),
                "inviteCode": room.get("inviteCode"),
                "memberCount": len(room.get("members", [])),
                "localReady": local_member.get("ready") if isinstance(local_member, dict) else None,
            }
        if route == "result":
            result = snapshot.get("result") or {}
            return {
                "route": route,
                "winnerPlayerId": result.get("winnerPlayerId"),
                "endReasonCode": result.get("endReasonCode"),
                "leavePolicy": result.get("leavePolicy"),
            }
        return {"route": route}

    @staticmethod
    def summarize_authoritative_state(authoritative: dict | None) -> dict | None:
        if authoritative is None:
            return None
        return {
            "roomId": authoritative.get("roomId"),
            "stateVersion": authoritative.get("stateVersion"),
            "currentPlayerId": authoritative.get("currentPlayerId"),
            "capturedTotals": authoritative.get("capturedTotals"),
        }

    @property
    def pending_screen_poll_interval(self) -> float:
        return min(self.args.poll_interval, 0.12)

    def settle_after_action(self) -> None:
        if self.pending_screen_check is None:
            time.sleep(self.args.action_delay)
            return

        settle_deadline = time.time() + max(self.args.action_delay, 1.2)
        while self.pending_screen_check is not None and time.time() < settle_deadline:
            host_snapshot = self.host_conn.get_state()
            guest_snapshot = self.guest_conn.get_state()
            self.track_transition("host", host_snapshot)
            self.track_transition("guest", guest_snapshot)

            if host_snapshot.get("route") == "live" and guest_snapshot.get("route") == "live":
                self.latest_authoritative_state = self.fetch_authoritative_live_state(host_snapshot, guest_snapshot)
                if self.scenario_id == "MP-017":
                    self.observe_capture_probe(host_snapshot, guest_snapshot)
                if self.scenario_id == "MP-018" and self.observe_draw_capture_probe(host_snapshot, guest_snapshot):
                    self.finalize_draw_capture_probe("settle_loop_complete")
                    self.pending_screen_check = None
                    return

            self.observe_pending_screen_check(host_snapshot, guest_snapshot)
            if self.pending_screen_check is None:
                return
            time.sleep(self.pending_screen_poll_interval)

    def observe_play_card_animation(self, check: dict, actor_snapshot: dict, peer_snapshot: dict) -> None:
        if check.get("actionType") != "playCard" or check.get("animationObserved"):
            return

        actor_summary = self.snapshot_screen_summary(actor_snapshot)
        peer_summary = self.snapshot_screen_summary(peer_snapshot)
        card_id = check["payload"].get("cardId")

        actor_hidden_source_ids = set(actor_summary.get("hiddenSourceCardIds") or [])
        actor_hidden_target_ids = set(actor_summary.get("hiddenTargetCardIds") or [])
        actor_moving_ids = set(actor_summary.get("movingCardIds") or [])
        peer_hidden_source_ids = set(peer_summary.get("hiddenSourceCardIds") or [])
        peer_hidden_target_ids = set(peer_summary.get("hiddenTargetCardIds") or [])
        peer_moving_ids = set(peer_summary.get("movingCardIds") or [])
        actor_recent_event_card_ids = set(actor_summary.get("recentUXEventCardIds") or [])
        peer_recent_event_card_ids = set(peer_summary.get("recentUXEventCardIds") or [])

        actor_card_observed = (
            card_id in actor_hidden_source_ids
            or card_id in actor_hidden_target_ids
            or card_id in actor_moving_ids
            or card_id in actor_recent_event_card_ids
        )
        peer_card_observed = (
            card_id in peer_hidden_source_ids
            or card_id in peer_hidden_target_ids
            or card_id in peer_moving_ids
            or card_id in peer_recent_event_card_ids
        )
        actor_busy = bool(actor_summary.get("isAutomationBusy"))
        peer_busy = bool(peer_summary.get("isAutomationBusy"))

        if not (actor_card_observed or peer_card_observed or actor_busy or peer_busy):
            return

        observation = {
            "cardId": card_id,
            "actorStateVersion": actor_summary.get("stateVersion"),
            "peerStateVersion": peer_summary.get("stateVersion"),
            "actorBusy": actor_busy,
            "peerBusy": peer_busy,
            "actorCardObserved": actor_card_observed,
            "peerCardObserved": peer_card_observed,
            "actorMovingCardIds": actor_summary.get("movingCardIds") or [],
            "peerMovingCardIds": peer_summary.get("movingCardIds") or [],
            "actorHiddenSourceCardIds": actor_summary.get("hiddenSourceCardIds") or [],
            "actorHiddenTargetCardIds": actor_summary.get("hiddenTargetCardIds") or [],
            "peerHiddenSourceCardIds": peer_summary.get("hiddenSourceCardIds") or [],
            "peerHiddenTargetCardIds": peer_summary.get("hiddenTargetCardIds") or [],
            "actorRecentUXEventTypes": actor_summary.get("recentUXEventTypes") or [],
            "peerRecentUXEventTypes": peer_summary.get("recentUXEventTypes") or [],
            "actorRecentUXEventCardIds": actor_summary.get("recentUXEventCardIds") or [],
            "peerRecentUXEventCardIds": peer_summary.get("recentUXEventCardIds") or [],
        }
        check["animationObserved"] = True
        check["animationObservation"] = observation
        self.record_event(
            "animation.observed",
            {
                "actionIndex": check["actionIndex"],
                "actorLabel": check["actorLabel"],
                **observation,
            },
        )

    def fetch_authoritative_live_state(self, host_snapshot: dict, guest_snapshot: dict) -> dict:
        host_live = host_snapshot.get("live") or {}
        guest_live = guest_snapshot.get("live") or {}
        room_id = host_live.get("roomId") or guest_live.get("roomId")
        host_room_player_id = host_snapshot.get("transportPlayerId")
        guest_room_player_id = guest_snapshot.get("transportPlayerId")
        if not isinstance(room_id, str) or not room_id:
            raise RuntimeError("Live UI probe is missing roomId for authoritative projection fetch.")
        if not isinstance(host_room_player_id, str) or not host_room_player_id:
            raise RuntimeError("Host simulator state is missing transportPlayerId.")
        if not isinstance(guest_room_player_id, str) or not guest_room_player_id:
            raise RuntimeError("Guest simulator state is missing transportPlayerId.")

        authority = self.ensure_authority_conn()
        host_projection = authority.fetch_projection(room_id, host_room_player_id)
        guest_projection = authority.fetch_projection(room_id, guest_room_player_id)
        host_state = self.projection_state(host_projection)
        guest_state = self.projection_state(guest_projection)
        state_version = host_projection.get("snapshotStateVersion")
        guest_state_version = guest_projection.get("snapshotStateVersion")
        if state_version is None:
            state_version = host_state.get("stateVersion")
        if guest_state_version is None:
            guest_state_version = guest_state.get("stateVersion")
        if state_version != guest_state_version:
            raise RuntimeError(
                "Authoritative projection stateVersion diverged between host and guest probes. "
                f"host={state_version} guest={guest_state_version}"
            )
        return {
            "roomId": room_id,
            "hostProjection": host_projection,
            "guestProjection": guest_projection,
            "stateVersion": state_version,
            "currentPlayerId": host_state.get("currentPlayerId"),
            "capturedTotals": self.authoritative_captured_totals(host_projection),
        }

    def observe_capture_probe(self, host_snapshot: dict, guest_snapshot: dict) -> None:
        probe = self.active_capture_probe
        authoritative = self.latest_authoritative_state
        if probe is None or authoritative is None:
            return

        actor_player_id = probe["actorPlayerId"]
        authoritative_total = authoritative["capturedTotals"].get(actor_player_id, probe["baselineAuthoritativeCaptured"])
        host_rendered_total = self.rendered_captured_totals(host_snapshot).get(actor_player_id, 0)
        guest_rendered_total = self.rendered_captured_totals(guest_snapshot).get(actor_player_id, 0)
        rendered_state_version = max(
            (host_snapshot.get("live") or {}).get("stateVersion") or 0,
            (guest_snapshot.get("live") or {}).get("stateVersion") or 0,
        )
        current_player_id = authoritative.get("currentPlayerId")

        if authoritative_total > probe["baselineAuthoritativeCaptured"] and probe["expectedCapturedTotal"] is None:
            probe["expectedCapturedTotal"] = authoritative_total
            probe["authoritativeCaptureStateVersion"] = authoritative.get("stateVersion")
            self.record_event(
                "capture.authoritative_visible",
                {
                    "actorPlayerId": actor_player_id,
                    "turnIndex": probe["turnIndex"],
                    "stateVersion": authoritative.get("stateVersion"),
                    "capturedTotal": authoritative_total,
                },
            )

        if current_player_id != actor_player_id and probe["turnPassedStateVersion"] is None:
            probe["turnPassedStateVersion"] = authoritative.get("stateVersion")
            self.record_event(
                "capture.turn_passed",
                {
                    "actorPlayerId": actor_player_id,
                    "turnIndex": probe["turnIndex"],
                    "stateVersion": authoritative.get("stateVersion"),
                    "nextPlayerId": current_player_id,
                },
            )

        expected_total = probe["expectedCapturedTotal"]
        if expected_total is None:
            return

        if host_rendered_total >= expected_total and guest_rendered_total >= expected_total:
            if probe["renderedCaptureStateVersion"] is None:
                probe["renderedCaptureStateVersion"] = rendered_state_version
                self.record_event(
                    "capture.rendered_visible",
                    {
                        "actorPlayerId": actor_player_id,
                        "turnIndex": probe["turnIndex"],
                        "stateVersion": rendered_state_version,
                        "capturedTotal": expected_total,
                    },
                )
            return

        if probe["turnPassedStateVersion"] is not None:
            failure = {
                "actorPlayerId": actor_player_id,
                "actorLabel": probe["actorLabel"],
                "turnIndex": probe["turnIndex"],
                "expectedCapturedTotal": expected_total,
                "hostRenderedCapturedTotal": host_rendered_total,
                "guestRenderedCapturedTotal": guest_rendered_total,
                "authoritativeCaptureStateVersion": probe["authoritativeCaptureStateVersion"],
                "turnPassedStateVersion": probe["turnPassedStateVersion"],
                "renderedStateVersion": rendered_state_version,
            }
            self.capture_probe_failures.append(failure)
            self.record_event("capture.lag_failure", failure)
            raise RuntimeError(
                "Rendered captured zone lagged behind the authoritative multiplayer turn handoff. "
                f"actor={probe['actorLabel']} expectedCapturedTotal={expected_total} "
                f"hostRendered={host_rendered_total} guestRendered={guest_rendered_total}"
            )

    def start_draw_capture_probe(self, label: str, snapshot: dict) -> None:
        self.finalize_draw_capture_probe("next_turn_started")
        live = snapshot.get("live") or {}
        actor_player_id = live.get("localPlayerId")
        if not isinstance(actor_player_id, str) or not actor_player_id:
            raise RuntimeError("Live UI snapshot is missing localPlayerId before play_card.")
        self.active_draw_capture_probe = {
            "actorLabel": label,
            "actorPlayerId": actor_player_id,
            "turnIndex": self.action_counts[label]["playCard"] + 1,
            "seed": self.selected_seed,
            "drawnCardId": None,
            "matchedCaptureCardIds": [],
            "actorInFlightObserved": False,
            "peerInFlightObserved": False,
            "renderedStateVersion": None,
            "screenshots": None,
        }

    def finalize_draw_capture_probe(self, reason: str) -> None:
        probe = self.active_draw_capture_probe
        if probe is None:
            return
        finalized = {**probe, "finalizeReason": reason}
        if finalized.get("drawnCardId") and (
            finalized.get("actorInFlightObserved") or finalized.get("peerInFlightObserved")
        ):
            self.draw_capture_probe_success_count += 1
        self.completed_draw_capture_probes.append(finalized)
        self.active_draw_capture_probe = None

    def draw_capture_probe_exhausted(self) -> bool:
        return all(
            self.action_counts[label]["playCard"] >= self.args.per_seat_turn_limit
            for label in ("host", "guest")
        )

    def observe_draw_capture_probe(self, host_snapshot: dict, guest_snapshot: dict) -> bool:
        probe = self.active_draw_capture_probe
        if probe is None:
            return False

        actor_snapshot, peer_snapshot = (
            (host_snapshot, guest_snapshot)
            if probe["actorLabel"] == "host"
            else (guest_snapshot, host_snapshot)
        )
        actor_summary = self.snapshot_screen_summary(actor_snapshot)
        peer_summary = self.snapshot_screen_summary(peer_snapshot)

        signal = (
            self.find_draw_capture_signal(actor_summary.get("recentUXEventSummaries") or [])
            or self.find_draw_capture_signal(peer_summary.get("recentUXEventSummaries") or [])
        )
        if signal is None:
            return False

        probe["drawnCardId"] = signal["drawnCardId"]
        probe["matchedCaptureCardIds"] = signal["capturedCardIds"]
        probe["actorInFlightObserved"] = self.draw_capture_in_flight(actor_summary, signal["drawnCardId"])
        probe["peerInFlightObserved"] = self.draw_capture_in_flight(peer_summary, signal["drawnCardId"])
        probe["renderedStateVersion"] = max(
            actor_summary.get("stateVersion") or 0,
            peer_summary.get("stateVersion") or 0,
        )
        probe["screenshots"] = self.capture_action_pair(
            self.action_sequence + 1,
            "draw_capture_animation",
        )
        self.record_event(
            "draw_capture.animation_observed",
            {
                "actorLabel": probe["actorLabel"],
                "turnIndex": probe["turnIndex"],
                "seed": probe["seed"],
                "drawnCardId": probe["drawnCardId"],
                "capturedCardIds": probe["matchedCaptureCardIds"],
                "actorInFlightObserved": probe["actorInFlightObserved"],
                "peerInFlightObserved": probe["peerInFlightObserved"],
                "renderedStateVersion": probe["renderedStateVersion"],
            },
        )
        if probe["actorInFlightObserved"] or probe["peerInFlightObserved"]:
            return True

        failure = {
            "actorLabel": probe["actorLabel"],
            "turnIndex": probe["turnIndex"],
            "seed": probe["seed"],
            "drawnCardId": probe["drawnCardId"],
            "capturedCardIds": probe["matchedCaptureCardIds"],
            "actorSummary": actor_summary,
            "peerSummary": peer_summary,
        }
        self.draw_capture_probe_failures.append(failure)
        self.record_event("draw_capture.animation_missing_in_flight", failure)
        raise RuntimeError(
            "A multiplayer draw-capture turn was detected, but the table->captured in-flight animation state was not observed. "
            f"seed={probe['seed']} actor={probe['actorLabel']} turnIndex={probe['turnIndex']}"
        )

    @staticmethod
    def parse_recent_event_summary(summary: str) -> dict | None:
        parts = summary.split("|", 3)
        if len(parts) != 4:
            return None
        event_type, source, target, card_token = parts
        card_ids = [] if card_token == "-" else [token for token in card_token.split(",") if token]
        return {
            "type": event_type,
            "source": source,
            "target": target,
            "cardIds": card_ids,
        }

    def find_draw_capture_signal(self, recent_summaries: list[str]) -> dict | None:
        events = [event for summary in recent_summaries if (event := self.parse_recent_event_summary(summary)) is not None]
        for index, event in enumerate(events):
            if (
                event["type"] == "moveStart"
                and event["source"] == "deck"
                and event["target"] == "table"
                and len(event["cardIds"]) == 1
            ):
                drawn_card_id = event["cardIds"][0]
                for later_event in events[index + 1:]:
                    if later_event["type"] != "moveStart":
                        continue
                    if later_event["source"] != "table" or later_event["target"] != "captured":
                        continue
                    if drawn_card_id in later_event["cardIds"]:
                        return {
                            "drawnCardId": drawn_card_id,
                            "capturedCardIds": later_event["cardIds"],
                        }
        return None

    @staticmethod
    def draw_capture_in_flight(summary: dict, drawn_card_id: str) -> bool:
        if summary.get("currentMoveSourceZone") != "table" or summary.get("currentMoveTargetZone") != "captured":
            return False
        card_sets = (
            summary.get("movingCardIds") or [],
            summary.get("hiddenSourceCardIds") or [],
            summary.get("hiddenTargetCardIds") or [],
            summary.get("recentUXEventCardIds") or [],
        )
        return any(drawn_card_id in card_ids for card_ids in card_sets)

    def start_capture_probe(self, label: str, snapshot: dict) -> None:
        self.finalize_capture_probe("next_turn_started")
        authoritative = self.latest_authoritative_state
        if authoritative is None:
            raise RuntimeError("Short multiplayer capture probe is missing authoritative state before play_card.")
        live = snapshot.get("live") or {}
        actor_player_id = live.get("localPlayerId")
        if not isinstance(actor_player_id, str) or not actor_player_id:
            raise RuntimeError("Live UI snapshot is missing localPlayerId before play_card.")
        baseline_authoritative = authoritative["capturedTotals"].get(actor_player_id, 0)
        self.active_capture_probe = {
            "actorLabel": label,
            "actorPlayerId": actor_player_id,
            "turnIndex": self.action_counts[label]["playCard"] + 1,
            "baselineAuthoritativeCaptured": baseline_authoritative,
            "expectedCapturedTotal": None,
            "authoritativeCaptureStateVersion": None,
            "renderedCaptureStateVersion": None,
            "turnPassedStateVersion": None,
        }

    def finalize_capture_probe(self, reason: str) -> None:
        probe = self.active_capture_probe
        if probe is None:
            return
        probe = {**probe, "finalizeReason": reason}
        if probe.get("expectedCapturedTotal") is not None and probe.get("renderedCaptureStateVersion") is not None:
            self.capture_probe_success_count += 1
        self.completed_capture_probes.append(probe)
        self.active_capture_probe = None

    def short_capture_probe_complete(self, host_snapshot: dict, guest_snapshot: dict) -> bool:
        if self.action_counts["host"]["playCard"] < 2 or self.action_counts["guest"]["playCard"] < 2:
            return False
        host_pending = ((host_snapshot.get("live") or {}).get("pendingChoice")) is not None
        guest_pending = ((guest_snapshot.get("live") or {}).get("pendingChoice")) is not None
        return not host_pending and not guest_pending

    def submit_choice(self, conn: BridgeConnection, pending_choice: dict, option_code: str) -> None:
        choice_kind = pending_choice.get("choiceKind")
        if choice_kind == "goStop":
            conn.send_action("respond_go_stop", {"isGo": option_code == "go"})
            return
        if choice_kind == "capture":
            conn.send_action("respond_to_capture", {"id": option_code})
            return
        if choice_kind == "shake":
            is_accept = option_code in {"shake", "shake_yes"}
            conn.send_action("respond_to_shake", {"didShake": is_accept})
            return
        if choice_kind == "chrysanthemumRole":
            conn.send_action("respond_to_chrysanthemum_choice", {"role": option_code})
            return
        raise RuntimeError(f"Unsupported choice kind: {choice_kind}")

    def pick_choice_option(self, pending_choice: dict) -> str | None:
        options = pending_choice.get("options") or []
        if not options:
            return None
        choice_kind = pending_choice.get("choiceKind")
        option_codes = [option.get("optionCode") for option in options if option.get("optionCode")]
        if choice_kind == "goStop":
            return self.pick_preferred_option(option_codes, ("go",))
        if choice_kind == "shake":
            return self.pick_preferred_option(option_codes, ("decline", "shake_no", "no"))
        if choice_kind == "chrysanthemumRole":
            return self.pick_preferred_option(option_codes, ("doublePi", "junk", "animal", "ribbon"))
        return option_codes[0] if option_codes else None

    @staticmethod
    def pick_preferred_option(option_codes: list[str], preferred_codes: tuple[str, ...]) -> str:
        for preferred in preferred_codes:
            for option_code in option_codes:
                if option_code == preferred or preferred in option_code:
                    return option_code
        return option_codes[0]

    @staticmethod
    def select_play_card(live: dict) -> dict | None:
        playable_ids = set(live.get("localPlayableCardIds") or [])
        hand_cards = [card for card in (live.get("localHandCards") or []) if card.get("cardId") in playable_ids]
        if not hand_cards:
            return None
        table_months = {card.get("month") for card in live.get("tableCards") or []}
        for card in hand_cards:
            if card.get("month") in table_months:
                return card
        return hand_cards[0]

    def ensure_authority_conn(self) -> AuthoritativeTransportClient:
        if self.authority_conn is None:
            self.authority_conn = AuthoritativeTransportClient(self.args.transport_url)
        return self.authority_conn

    def close_authority_conn(self) -> None:
        if self.authority_conn is None:
            return
        try:
            self.authority_conn.close()
        finally:
            self.authority_conn = None

    @staticmethod
    def rendered_captured_totals(snapshot: dict) -> dict[str, int]:
        live = snapshot.get("live") or {}
        totals: dict[str, int] = {}
        local_player_id = live.get("localPlayerId")
        opponent_player_id = live.get("opponentPlayerId")
        if isinstance(local_player_id, str):
            totals[local_player_id] = MultiplayerUIScenarioRunner.captured_zone_total(live.get("localCapturedZone") or {})
        if isinstance(opponent_player_id, str):
            totals[opponent_player_id] = MultiplayerUIScenarioRunner.captured_zone_total(
                live.get("opponentCapturedZone") or {}
            )
        return totals

    @staticmethod
    def captured_zone_total(zone: dict) -> int:
        return sum(len(group.get("cards") or []) for group in (zone.get("groups") or []) if isinstance(group, dict))

    @staticmethod
    def projection_state(snapshot: dict) -> dict:
        state = snapshot.get("state")
        if not isinstance(state, dict):
            raise RuntimeError("Projection snapshot state is missing.")
        return state

    @staticmethod
    def authoritative_captured_totals(snapshot: dict) -> dict[str, int]:
        totals: dict[str, int] = {}
        for player in MultiplayerUIScenarioRunner.projection_state(snapshot).get("players", []):
            if not isinstance(player, dict):
                continue
            player_id = player.get("playerId")
            captured = player.get("captured") or {}
            if not isinstance(player_id, str) or not isinstance(captured, dict):
                continue
            totals[player_id] = sum(
                len(captured.get(kind) or [])
                for kind in ("bright", "animal", "ribbon", "junk")
            )
        return totals

    def wait_for_snapshot(self, conn: BridgeConnection, predicate, timeout_seconds: float) -> dict:
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            snapshot = conn.get_state()
            self.track_transition(conn.label, snapshot)
            if predicate(snapshot):
                return snapshot
            time.sleep(self.args.poll_interval)
        raise RuntimeError(f"[{conn.label}] timed out waiting for expected simulator state.")

    def track_transition(self, label: str, snapshot: dict) -> None:
        prior = self.state_cache.get(label)
        current_signature = {
            "route": snapshot.get("route"),
            "roomState": (snapshot.get("room") or {}).get("roomState"),
            "inviteCode": (snapshot.get("room") or {}).get("inviteCode"),
            "phase": (snapshot.get("live") or {}).get("phase"),
            "stateVersion": (snapshot.get("live") or {}).get("stateVersion"),
            "choiceId": ((snapshot.get("live") or {}).get("pendingChoice") or {}).get("choiceId"),
            "leavePolicy": (snapshot.get("result") or {}).get("leavePolicy"),
            "endReasonCode": (snapshot.get("result") or {}).get("endReasonCode"),
        }
        if prior == current_signature:
            return
        self.state_cache[label] = current_signature
        payload = {"player": label, **{key: value for key, value in current_signature.items() if value is not None}}
        self.record_event("state.transition", payload)

    def capture_pair(self, suffix: str) -> None:
        self.capture_screenshot(self.args.host_udid, self.output_root / f"host_{suffix}.png")
        self.capture_screenshot(self.args.guest_udid, self.output_root / f"guest_{suffix}.png")

    def capture_screenshot(self, udid: str, path: Path) -> None:
        self.run_command(["xcrun", "simctl", "io", udid, "screenshot", str(path)], allow_failure=True)

    def record_event(self, event: str, payload: dict) -> None:
        row = {
            "attempt": self.current_attempt,
            "event": event,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "payload": payload,
        }
        with self.timeline_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    @property
    def total_gameplay_actions(self) -> int:
        return sum(
            counts["playCard"] + counts["choice"]
            for counts in self.action_counts.values()
        )

    def current_attempt_summary(
        self,
        invite_code: str | None,
        *,
        success: bool,
        error_message: str | None = None,
    ) -> dict:
        return {
            "attempt": self.current_attempt,
            "success": success,
            "inviteCode": invite_code,
            "actionCounts": self.action_counts,
            "totalGameplayActions": self.total_gameplay_actions,
            "terminalSeen": self.terminal_seen,
            "leaveSent": self.leave_sent,
            "screenCheckSuccessCount": len(self.completed_screen_checks),
            "screenCheckFailureCount": len(self.screen_check_failures),
            "captureProbeSuccessCount": self.capture_probe_success_count,
            "captureProbeFailures": self.capture_probe_failures,
            "selectedSeed": self.selected_seed,
            "drawCaptureProbeSuccessCount": self.draw_capture_probe_success_count,
            "drawCaptureProbeFailures": self.draw_capture_probe_failures,
            "error": error_message,
        }

    def write_summary(self, success: bool, invite_code: str | None, error_message: str | None = None) -> None:
        host_container = self.lookup_container(self.args.host_udid)
        guest_container = self.lookup_container(self.args.guest_udid)
        screen_checks = {
            "scenarioId": self.scenario_id,
            "attempt": self.current_attempt,
            "checks": self.completed_screen_checks,
            "failures": self.screen_check_failures,
        }
        self.screen_checks_path.write_text(json.dumps(screen_checks, indent=2) + "\n", encoding="utf-8")
        summary = {
            "scenarioId": self.scenario_id,
            "success": success,
            "selectedAttempt": self.current_attempt,
            "maxAttempts": self.args.max_attempts,
            "attempts": self.attempts,
            "inviteCode": invite_code,
            "transportURL": self.args.transport_url,
            "hostPort": self.args.host_port,
            "guestPort": self.args.guest_port,
            "actionCounts": self.action_counts,
            "totalGameplayActions": self.total_gameplay_actions,
            "hostContainer": host_container,
            "guestContainer": guest_container,
            "hostDebugLog": self.debug_log_path(host_container),
            "guestDebugLog": self.debug_log_path(guest_container),
            "terminalSeen": self.terminal_seen,
            "leaveSent": self.leave_sent,
            "captureProbeSuccessCount": self.capture_probe_success_count,
            "captureProbeFailures": self.capture_probe_failures,
            "selectedSeed": self.selected_seed,
            "drawCaptureProbeSuccessCount": self.draw_capture_probe_success_count,
            "drawCaptureProbeFailures": self.draw_capture_probe_failures,
            "drawCaptureProbes": self.completed_draw_capture_probes,
            "actionLogPath": str(self.action_log_path),
            "screenChecksPath": str(self.screen_checks_path),
            "screenCheckSuccessCount": len(self.completed_screen_checks),
            "screenCheckFailures": self.screen_check_failures,
            "captureProbes": self.completed_capture_probes,
            "error": error_message,
        }
        self.summary_json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

        lines = [
            f"# Multiplayer UI {self.scenario_title} Summary",
            "",
            f"- Scenario ID: {self.scenario_id}",
            f"- Success: {'PASS' if success else 'FAIL'}",
            f"- Selected Attempt: {self.current_attempt}/{self.args.max_attempts}",
            f"- Invite Code: {invite_code or 'unknown'}",
            f"- Transport URL: {self.args.transport_url}",
            f"- Host Bridge Port: {self.args.host_port}",
            f"- Guest Bridge Port: {self.args.guest_port}",
            f"- Total Gameplay Actions: {self.total_gameplay_actions}",
            f"- Host Terminal Seen: {self.terminal_seen['host']}",
            f"- Guest Terminal Seen: {self.terminal_seen['guest']}",
            f"- Host Leave Sent: {self.leave_sent['host']}",
            f"- Guest Leave Sent: {self.leave_sent['guest']}",
            f"- Host Action Counts: {self.action_counts['host']}",
            f"- Guest Action Counts: {self.action_counts['guest']}",
            f"- Host Debug Log: {self.debug_log_path(host_container) or 'unavailable'}",
            f"- Guest Debug Log: {self.debug_log_path(guest_container) or 'unavailable'}",
            f"- Action Log: {self.action_log_path}",
            f"- Screen Checks: {self.screen_checks_path}",
            f"- Screen Check Success Count: {len(self.completed_screen_checks)}",
            f"- Screen Check Failure Count: {len(self.screen_check_failures)}",
        ]
        if self.scenario_id == "MP-017":
            lines.extend(
                [
                    f"- Capture Probe Success Count: {self.capture_probe_success_count}",
                    f"- Capture Probe Failure Count: {len(self.capture_probe_failures)}",
                ]
            )
        if self.scenario_id == "MP-018":
            lines.extend(
                [
                    f"- Selected Seed: {self.selected_seed}",
                    f"- Draw-Capture Probe Success Count: {self.draw_capture_probe_success_count}",
                    f"- Draw-Capture Probe Failure Count: {len(self.draw_capture_probe_failures)}",
                ]
            )
        if error_message:
            lines.extend(["", "## Error", f"- {error_message}"])
        self.summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def lookup_container(self, udid: str) -> str | None:
        result = self.run_command(
            ["xcrun", "simctl", "get_app_container", udid, self.args.bundle_id, "data"],
            allow_failure=True,
        )
        path = result.stdout.strip()
        return path or None

    @staticmethod
    def debug_log_path(container_path: str | None) -> str | None:
        if not container_path:
            return None
        return str(Path(container_path) / "Library" / "Application Support" / "GoStop" / "debug_log_multiplayer.ndjson")

    @staticmethod
    def run_command(command: list[str], env: dict[str, str] | None = None, allow_failure: bool = False) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        if result.returncode != 0 and not allow_failure:
            raise RuntimeError(
                "Command failed:\n"
                f"command={' '.join(command)}\n"
                f"stdout={result.stdout}\n"
                f"stderr={result.stderr}"
            )
        return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Drive a two-simulator multiplayer UI scenario end-to-end.")
    parser.add_argument("--scenario-id", default="MP-016", choices=["MP-016", "MP-017", "MP-018"])
    parser.add_argument("--host-udid", default=DEFAULT_HOST_UDID)
    parser.add_argument("--guest-udid", default=DEFAULT_GUEST_UDID)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--host-port", type=int, default=8080)
    parser.add_argument("--guest-port", type=int, default=8081)
    parser.add_argument("--transport-url", default="ws://127.0.0.1:9092")
    parser.add_argument("--app-path", help="Optional GoStop.app path for simctl install.")
    parser.add_argument("--install-app", action="store_true")
    parser.add_argument("--fast-animation", action="store_true")
    parser.add_argument("--launch-timeout", type=float, default=40.0)
    parser.add_argument("--scenario-timeout", type=float, default=180.0)
    parser.add_argument("--poll-interval", type=float, default=0.7)
    parser.add_argument("--action-delay", type=float, default=1.1)
    parser.add_argument("--max-attempts", type=int, default=5)
    parser.add_argument("--seed-candidates", default="1,2,3,4,5")
    parser.add_argument("--per-seat-turn-limit", type=int, default=6)
    parser.add_argument("--success-hold-seconds", type=float, default=1.2)
    parser.add_argument("--output-root")
    parser.add_argument("--capture-final-screenshot", action="store_true")
    return parser.parse_args()


def main() -> int:
    runner = MultiplayerUIScenarioRunner(parse_args())
    return runner.run()


if __name__ == "__main__":
    sys.exit(main())
