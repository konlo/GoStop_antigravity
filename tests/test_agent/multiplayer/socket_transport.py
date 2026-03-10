from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import ScenarioDefinition, ScenarioStatus


def default_socket_derived_data() -> Path:
    return Path("/tmp/gostop_multiplayer_socket_build")


def resolve_socket_binary(
    repo_root: Path,
    binary_path: Path | None = None,
    derived_data: Path | None = None,
    skip_build: bool = False,
) -> Path:
    if binary_path is not None:
        return binary_path

    build_root = derived_data or default_socket_derived_data()
    candidate = build_root / "Build/Products/Debug/GoStopCLI"
    if skip_build and candidate.exists():
        return candidate

    command = [
        "xcodebuild",
        "-project",
        "GoStop.xcodeproj",
        "-scheme",
        "GoStopCLI",
        "-configuration",
        "Debug",
        "-derivedDataPath",
        str(build_root),
        "build",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    result = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Failed to build GoStopCLI for socket mode.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return candidate


class CLIProcessClient:
    def __init__(self, binary_path: Path) -> None:
        self.process = subprocess.Popen(
            [str(binary_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        self.process.terminate()
        self.process.wait(timeout=5)

    def send(self, action: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        if not self.process.stdin or not self.process.stdout:
            raise RuntimeError("CLI pipes are unavailable.")

        request: dict[str, Any] = {"action": action}
        if data is not None:
            request["data"] = data

        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()

        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("GoStopCLI closed before responding.")
            text = line.strip()
            if not text:
                continue
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict) and payload.get("action") == action:
                return payload


def _iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _stable_hash(payload: Any) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha1(encoded).hexdigest()


def _room_event_name(envelope: dict[str, Any]) -> str | None:
    payload = envelope.get("payload", {})
    if isinstance(payload, dict):
        nested = payload.get("payload")
        if isinstance(nested, dict) and "eventName" in nested:
            return nested.get("eventName")
        nested_nested = payload.get("payload", {})
        if isinstance(nested_nested, dict):
            nested_payload = nested_nested.get("payload")
            if isinstance(nested_payload, dict):
                return nested_payload.get("eventName")
    return None


def _room_event_field(envelope: dict[str, Any], key: str) -> Any:
    payload = envelope.get("payload", {})
    if isinstance(payload, dict):
        nested = payload.get("payload")
        if isinstance(nested, dict) and key in nested:
            return nested.get(key)
        nested_nested = payload.get("payload", {})
        if isinstance(nested_nested, dict):
            nested_payload = nested_nested.get("payload")
            if isinstance(nested_payload, dict):
                return nested_payload.get(key)
    return None


def _engine_event(envelope: dict[str, Any]) -> dict[str, Any] | None:
    payload = envelope.get("payload", {})
    if isinstance(payload, dict):
        direct = payload.get("engineEvent")
        if isinstance(direct, dict):
            return direct
        nested = payload.get("payload")
        if isinstance(nested, dict):
            nested_event = nested.get("engineEvent")
            if isinstance(nested_event, dict):
                return nested_event
    return None


def _find_engine_event(
    envelopes: list[dict[str, Any]],
    *,
    reason: str | None = None,
    snapshot_only: bool = False,
) -> dict[str, Any]:
    for envelope in envelopes:
        event = _engine_event(envelope)
        if not isinstance(event, dict):
            continue
        if snapshot_only and "state" not in event:
            continue
        if reason is not None and event.get("reason") != reason:
            continue
        return event
    raise RuntimeError(f"Missing engine event reason={reason!r} snapshot_only={snapshot_only!r}")


class SocketTransportHarness:
    def __init__(self, repo_root: Path, binary_path: Path) -> None:
        self.repo_root = repo_root
        self.client = CLIProcessClient(binary_path)
        self.command_rows: list[dict[str, Any]] = []
        self.frame_rows: list[dict[str, Any]] = []
        self.agent_log_lines: list[str] = []
        self.room_log_lines: list[str] = []
        self.engine_log_lines: list[str] = []
        self.transport_clients: dict[str, dict[str, Any]] = {}

    def close(self) -> None:
        self.client.close()

    def send(self, action: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        response = self.client.send(action, data)
        self.command_rows.append(
            {
                "timestamp": _iso_now(),
                "action": action,
                "request": data or {},
                "response": response,
            }
        )
        return response

    def require_ok(self, action: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        response = self.send(action, data)
        if response.get("status") != "ok":
            raise RuntimeError(f"{action} failed: {json.dumps(response, ensure_ascii=False, indent=2)}")
        return response["data"]

    def require_error(
        self,
        action: str,
        data: dict[str, Any],
        expected_code: str,
    ) -> dict[str, Any]:
        response = self.send(action, data)
        if response.get("status") != "error":
            raise RuntimeError(
                f"{action} expected error {expected_code}, got: {json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        if response.get("errorCode") != expected_code:
            raise RuntimeError(
                f"{action} expected errorCode={expected_code}, got: {json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        return response

    def bootstrap_two_player_room(self) -> dict[str, Any]:
        create = self.require_ok(
            "room_create",
            {
                "hostPlayerId": "p1",
                "deviceId": "dev1",
                "roomType": "invite",
                "joinPolicy": "inviteCode",
            },
        )
        join = self.require_ok(
            "room_join",
            {
                "roomId": create["room"]["roomId"],
                "playerId": "p2",
                "deviceId": "dev2",
            },
        )
        return {
            "room_id": create["room"]["roomId"],
            "host_session_id": create["session"]["sessionId"],
            "guest_session_id": join["session"]["sessionId"],
            "host_resume_token": create["session"]["resumeToken"],
            "guest_resume_token": join["session"]["resumeToken"],
        }

    def connect_transport_client(
        self,
        client_id: str,
        room_id: str,
        session_id: str,
        player_id: str,
        device_id: str,
        resume_token: str,
    ) -> dict[str, Any]:
        data = self.require_ok(
            "room_transport_connect",
            {
                "clientId": client_id,
                "roomId": room_id,
                "sessionId": session_id,
                "playerId": player_id,
                "deviceId": device_id,
                "resumeToken": resume_token,
            },
        )
        self.transport_clients[client_id] = {
            "clientId": client_id,
            "roomId": room_id,
            "sessionId": session_id,
            "playerId": player_id,
            "deviceId": device_id,
            "resumeToken": resume_token,
            "connectionId": None,
        }
        return data

    def transport_send_ok(self, client_id: str, transport_action: str, **kwargs: Any) -> dict[str, Any]:
        payload = {"clientId": client_id, "action": transport_action}
        payload.update(kwargs)
        data = self.require_ok("room_transport_send", payload)
        client = data.get("client")
        if isinstance(client, dict):
            self.transport_clients[client_id] = client
        return data

    def transport_send_error(
        self,
        client_id: str,
        transport_action: str,
        expected_code: str,
        **kwargs: Any,
    ) -> dict[str, Any]:
        payload = {"clientId": client_id, "action": transport_action}
        payload.update(kwargs)
        return self.require_error("room_transport_send", payload, expected_code=expected_code)

    def transport_receive(self, client_id: str) -> list[dict[str, Any]]:
        data = self.require_ok("room_transport_receive", {"clientId": client_id})
        envelopes = data["envelopes"]
        received_at = _iso_now()
        for index, envelope in enumerate(envelopes, start=1):
            row = {
                "clientId": client_id,
                "receivedAt": received_at,
                "receiveIndex": index,
                **envelope,
            }
            self.frame_rows.append(row)
            self.room_log_lines.append(
                f"[{received_at}] client={client_id} type={envelope.get('type')} roomSequence={envelope.get('roomSequence')}"
            )
            if envelope.get("type") == "gameEvent":
                self.engine_log_lines.append(
                    f"[{received_at}] client={client_id} gameEvent={json.dumps(envelope.get('payload', {}), ensure_ascii=False)}"
                )
        return envelopes

    def snapshot_room(self, room_id: str) -> dict[str, Any]:
        return self.require_ok("room_snapshot", {"roomId": room_id})["snapshot"]


def _snapshot_record(
    *,
    payload: dict[str, Any],
    snapshot_id: str,
    source: str,
    scope: str,
    player_id: str | None,
    state_version: int | None,
    event_id: str | None,
) -> dict[str, Any]:
    return {
        "snapshot_id": snapshot_id,
        "source": source,
        "scope": scope,
        "player_id": player_id,
        "state_version": state_version,
        "event_id": event_id,
        "state_hash": _stable_hash(payload),
        "payload": payload,
    }


def _collect_players(room_snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    players = []
    for member in room_snapshot["room"]["members"]:
        players.append(
            {
                "player_id": member["playerId"],
                "seat": member["seat"],
                "connection_state": member["presence"],
            }
        )
    return players


def _run_mp001_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    bootstrap = harness.bootstrap_two_player_room()
    room_id = bootstrap["room_id"]
    game_id = f"{room_id}_socket_game_001"

    harness.connect_transport_client(
        "host_client",
        room_id,
        bootstrap["host_session_id"],
        "p1",
        "dev1",
        bootstrap["host_resume_token"],
    )
    harness.connect_transport_client(
        "guest_client",
        room_id,
        bootstrap["guest_session_id"],
        "p2",
        "dev2",
        bootstrap["guest_resume_token"],
    )

    harness.transport_send_ok("host_client", "hello", connectionId="conn_host_socket_001")
    host_hello = harness.transport_receive("host_client")
    harness.transport_send_ok("guest_client", "hello", connectionId="conn_guest_socket_001")
    guest_hello = harness.transport_receive("guest_client")

    harness.transport_send_ok("host_client", "setReady", ready=True)
    host_after_host_ready = harness.transport_receive("host_client")
    guest_after_host_ready = harness.transport_receive("guest_client")

    harness.transport_send_ok("guest_client", "setReady", ready=True)
    host_after_guest_ready = harness.transport_receive("host_client")
    guest_after_guest_ready = harness.transport_receive("guest_client")

    harness.transport_send_ok("host_client", "recordGameStartedAndPrepareBootstrap", gameId=game_id)
    host_live = harness.transport_receive("host_client")
    guest_live = harness.transport_receive("guest_client")
    room_snapshot = harness.snapshot_room(room_id)

    if [envelope["type"] for envelope in host_hello[:2]] != ["helloAck", "roomSnapshot"]:
        raise RuntimeError("Host hello transport ordering diverged.")
    if [envelope["type"] for envelope in guest_hello[:2]] != ["helloAck", "roomSnapshot"]:
        raise RuntimeError("Guest hello transport ordering diverged.")
    if not any(
        _room_event_name(envelope) == "roomStateChanged" and _room_event_field(envelope, "toState") == "starting"
        for envelope in host_after_guest_ready + guest_after_guest_ready
    ):
        raise RuntimeError("Missing roomStateChanged(toState=starting) after both players ready.")
    if not any(
        _room_event_name(envelope) == "roomStateChanged" and _room_event_field(envelope, "toState") == "inGame"
        for envelope in host_live + guest_live
    ):
        raise RuntimeError("Missing roomStateChanged(toState=inGame) after transport game start.")

    host_snapshot = _find_engine_event(host_live, reason="gameStarted", snapshot_only=True)
    guest_snapshot = _find_engine_event(guest_live, reason="gameStarted", snapshot_only=True)
    room = room_snapshot["room"]
    if room["roomState"] != "inGame":
        raise RuntimeError(f"Expected roomState=inGame, got {room['roomState']!r}")
    if room["activeGameId"] != game_id:
        raise RuntimeError(f"Expected activeGameId={game_id!r}, got {room['activeGameId']!r}")

    return {
        "status": ScenarioStatus.PASS,
        "summary": "Socket transport spike validated hello/setReady/recordGameStartedAndPrepareBootstrap with paired bootstrap delivery.",
        "roomId": room_id,
        "gameId": game_id,
        "players": _collect_players(room_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _snapshot_record(
                payload=host_snapshot["state"],
                snapshot_id=host_snapshot["snapshotId"],
                source="initial",
                scope="player",
                player_id="p1",
                state_version=host_snapshot["snapshotStateVersion"],
                event_id=None,
            ),
            "player_b_initial": _snapshot_record(
                payload=guest_snapshot["state"],
                snapshot_id=guest_snapshot["snapshotId"],
                source="initial",
                scope="player",
                player_id="p2",
                state_version=guest_snapshot["snapshotStateVersion"],
                event_id=None,
            ),
            "latest_server": _snapshot_record(
                payload=room_snapshot,
                snapshot_id=f"{room_id}_socket_room_snapshot",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=room["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                "Socket mode executed through room_transport_* CLI spike.",
                "Validated paired bootstrap delivery after recordGameStartedAndPrepareBootstrap.",
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
    }


def _run_mp014_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    bootstrap = harness.bootstrap_two_player_room()
    room_id = bootstrap["room_id"]

    harness.connect_transport_client(
        "host_client",
        room_id,
        bootstrap["host_session_id"],
        "p1",
        "dev1",
        bootstrap["host_resume_token"],
    )
    harness.connect_transport_client(
        "guest_old",
        room_id,
        bootstrap["guest_session_id"],
        "p2",
        "dev2",
        bootstrap["guest_resume_token"],
    )

    harness.transport_send_ok("host_client", "hello", connectionId="conn_host_socket_001")
    harness.transport_receive("host_client")
    harness.transport_send_ok("guest_old", "hello", connectionId="conn_guest_socket_001")
    harness.transport_receive("guest_old")

    harness.require_ok("room_disconnect", {"roomId": room_id, "playerId": "p2"})
    disconnected_snapshot = harness.snapshot_room(room_id)
    last_sequence = disconnected_snapshot["room"]["lastRoomSequence"]

    disconnected_error = harness.transport_send_error(
        "guest_old",
        "ack",
        expected_code="invalidResumeState",
        lastSeen={"roomSequence": last_sequence},
    )

    rotated_resume_token = harness.transport_clients["guest_old"]["resumeToken"]
    harness.connect_transport_client(
        "guest_new",
        room_id,
        bootstrap["guest_session_id"],
        "p2",
        "dev2",
        rotated_resume_token,
    )
    harness.transport_send_ok(
        "guest_new",
        "hello",
        connectionId="conn_guest_socket_002",
        lastSeen={"roomSequence": last_sequence},
    )
    guest_resume_envelopes = harness.transport_receive("guest_new")

    stale_error = harness.transport_send_error(
        "guest_old",
        "ack",
        expected_code="staleConnectionId",
        lastSeen={"roomSequence": last_sequence},
    )
    accepted_ack = harness.transport_send_ok(
        "guest_new",
        "ack",
        lastSeen={"roomSequence": last_sequence},
    )
    latest_snapshot = harness.snapshot_room(room_id)

    if not any(envelope["type"] == "helloAck" for envelope in guest_resume_envelopes):
        raise RuntimeError("Resume mailbox is missing helloAck.")
    room = latest_snapshot["room"]
    guest_member = next(member for member in room["members"] if member["playerId"] == "p2")

    return {
        "status": ScenarioStatus.PASS,
        "summary": "Socket transport spike preserved stale heartbeat reject parity through room_transport_send(action=ack).",
        "roomId": room_id,
        "gameId": None,
        "players": _collect_players(latest_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _snapshot_record(
                payload=disconnected_snapshot,
                snapshot_id=f"{room_id}_before_resume",
                source="initial",
                scope="player",
                player_id="p1",
                state_version=disconnected_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
            "player_b_initial": _snapshot_record(
                payload=disconnected_snapshot,
                snapshot_id=f"{room_id}_before_resume",
                source="initial",
                scope="player",
                player_id="p2",
                state_version=disconnected_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
            "latest_server": _snapshot_record(
                payload=latest_snapshot,
                snapshot_id=f"{room_id}_after_resume",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=latest_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                "Socket mode exercised stale/disconnected heartbeat parity using room_transport_send(action=ack).",
                f"disconnectedError={disconnected_error['errorCode']} staleError={stale_error['errorCode']}",
                f"acceptedAction={accepted_ack['transportAction']}",
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
    }


def _run_mp008_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    bootstrap = harness.bootstrap_two_player_room()
    room_id = bootstrap["room_id"]
    game_id = f"{room_id}_socket_game_001"

    harness.connect_transport_client(
        "host_client",
        room_id,
        bootstrap["host_session_id"],
        "p1",
        "dev1",
        bootstrap["host_resume_token"],
    )
    harness.connect_transport_client(
        "guest_client",
        room_id,
        bootstrap["guest_session_id"],
        "p2",
        "dev2",
        bootstrap["guest_resume_token"],
    )
    harness.transport_send_ok("host_client", "hello", connectionId="conn_host_socket_001")
    harness.transport_receive("host_client")
    harness.transport_send_ok("guest_client", "hello", connectionId="conn_guest_socket_001")
    harness.transport_receive("guest_client")
    harness.transport_send_ok("host_client", "setReady", ready=True)
    harness.transport_receive("host_client")
    harness.transport_receive("guest_client")
    harness.transport_send_ok("guest_client", "setReady", ready=True)
    harness.transport_receive("host_client")
    harness.transport_receive("guest_client")
    harness.transport_send_ok("host_client", "recordGameStartedAndPrepareBootstrap", gameId=game_id)
    host_live = harness.transport_receive("host_client")
    guest_live = harness.transport_receive("guest_client")

    hook = harness.require_ok(
        "room_set_mp008_hook",
        {
            "targetSessionId": bootstrap["guest_session_id"],
            "overriddenExpectedStateVersion": 999,
        },
    )["hook"]
    hook_snapshot = harness.require_ok("room_get_mp008_hook", None)["hook"]
    latest_snapshot = harness.snapshot_room(room_id)
    harness.require_ok("room_clear_mp008_hook", None)

    host_snapshot = _find_engine_event(host_live, reason="gameStarted", snapshot_only=True)
    guest_snapshot = _find_engine_event(guest_live, reason="gameStarted", snapshot_only=True)
    if hook_snapshot != hook:
        raise RuntimeError("room_get_mp008_hook diverged from the hook returned by room_set_mp008_hook.")

    blocking_reasons = [
        "room_transport_send does not yet expose gameplay actions carrying expectedStateVersion, so live staleStateVersion reject + stateSnapshot(reason=resync) cannot run end-to-end.",
    ]
    return {
        "status": ScenarioStatus.BLOCKED,
        "summary": "Socket transport preflight attached the MP-008 hook after live bootstrap, but gameplay resync remains blocked on a transport gameplay command surface.",
        "roomId": room_id,
        "gameId": game_id,
        "players": _collect_players(latest_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _snapshot_record(
                payload=host_snapshot["state"],
                snapshot_id=host_snapshot["snapshotId"],
                source="initial",
                scope="player",
                player_id="p1",
                state_version=host_snapshot["snapshotStateVersion"],
                event_id=None,
            ),
            "player_b_initial": _snapshot_record(
                payload=guest_snapshot["state"],
                snapshot_id=guest_snapshot["snapshotId"],
                source="initial",
                scope="player",
                player_id="p2",
                state_version=guest_snapshot["snapshotStateVersion"],
                event_id=None,
            ),
            "latest_server": _snapshot_record(
                payload=latest_snapshot,
                snapshot_id=f"{room_id}_socket_preflight",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=latest_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                "Socket mode attached MP-008 staleExpectedStateVersionOverride hook after transport bootstrap.",
                f"hookTargetSessionId={hook_snapshot['targetSessionId']} overriddenExpectedStateVersion={hook_snapshot['overriddenExpectedStateVersion']}",
                "Gameplay resync remains blocked because room_transport_send has no gameplay action carrying expectedStateVersion.",
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "injectionPlan": {
            "executionReadiness": "socket-preflight-only",
            "injectedMismatchMode": "staleExpectedStateVersion",
            "clientStateVersion": None,
            "expectedStateVersion": hook["overriddenExpectedStateVersion"],
            "authoritativeStateVersion": None,
            "authoritativeEventId": None,
            "recoverySnapshotReason": "resync",
            "recoverySnapshotId": None,
            "targetSessionId": hook["targetSessionId"],
        },
        "mismatchFrames": [
            {
                "kind": "socket_preflight",
                "scenarioId": "MP-008",
                "status": ScenarioStatus.BLOCKED.value,
                "injectedMismatchMode": "staleExpectedStateVersion",
                "expectedStateVersion": hook["overriddenExpectedStateVersion"],
                "targetSessionId": hook["targetSessionId"],
                "message": blocking_reasons[0],
            }
        ],
    }


def run_socket_scenario(
    scenario: ScenarioDefinition,
    *,
    repo_root: Path,
    binary_path: Path,
) -> dict[str, Any]:
    harness = SocketTransportHarness(repo_root=repo_root, binary_path=binary_path)
    try:
        if scenario.scenario_id == "MP-001":
            return _run_mp001_socket(harness)
        if scenario.scenario_id == "MP-014":
            return _run_mp014_socket(harness)
        if scenario.scenario_id == "MP-008":
            return _run_mp008_socket(harness)
        return {
            "status": ScenarioStatus.BLOCKED,
            "summary": "Socket mode scaffold exists, but this scenario does not yet have a live transport implementation.",
            "roomId": None,
            "gameId": None,
            "players": [],
            "commands": list(harness.command_rows),
            "frames": list(harness.frame_rows),
            "snapshots": {},
            "logs": {
                "agent": [
                    "Socket mode is available, but this scenario is still scaffold-only.",
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [
                f"Socket mode is not implemented for {scenario.scenario_id} yet.",
            ],
        }
    except Exception as error:
        return {
            "status": ScenarioStatus.FAIL,
            "summary": f"Socket transport execution failed before completion: {error}",
            "roomId": None,
            "gameId": None,
            "players": [],
            "commands": list(harness.command_rows),
            "frames": list(harness.frame_rows),
            "snapshots": {},
            "logs": {
                "agent": [
                    f"Socket transport execution failed: {error}",
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [str(error)],
        }
    finally:
        harness.close()
