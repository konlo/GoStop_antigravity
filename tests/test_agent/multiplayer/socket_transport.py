from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import subprocess
import time
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import ScenarioDefinition, ScenarioStatus


KNOWN_SOCKET_DERIVED_DATA_ROOTS = [
    Path("/tmp/gostop_cli_round16_agent2"),
    Path("/tmp/gostop_cli_round16_agent4"),
    Path("/tmp/gostop_cli_round15_agent2"),
    Path("/tmp/gostop_cli_round15_agent4"),
    Path("/tmp/gostop_cli_round14_agent2"),
    Path("/tmp/gostop_cli_round13_agent2"),
    Path("/tmp/gostop_cli_round12_agent2"),
    Path("/tmp/gostop_cli_round11_agent4"),
    Path("/tmp/gostop_cli_round10_agent4"),
    Path("/tmp/gostop_cli_agent4_round7_recheck"),
    Path("/tmp/gostop_cli_round7_review"),
    Path("/tmp/gostop_multiplayer_socket_build"),
    Path("/tmp/gostop_cli_round6_review"),
    Path("/tmp/gostop_cli_status_check"),
    Path("/tmp/gostop_cli_build"),
    Path("/tmp/gostop_cli_agent2_round5"),
    Path("/tmp/gostop_cli_final_review"),
]


def default_socket_derived_data() -> Path:
    return Path("/tmp/gostop_multiplayer_socket_build")


def _binary_candidates(derived_data: Path | None = None) -> list[Path]:
    roots: list[Path] = []
    if derived_data is not None:
        roots.append(derived_data)
    roots.extend(KNOWN_SOCKET_DERIVED_DATA_ROOTS)

    candidates: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        candidate = root / "Build/Products/Debug/GoStopCLI"
        if candidate in seen:
            continue
        seen.add(candidate)
        candidates.append(candidate)
    return candidates


def resolve_socket_binary(
    repo_root: Path,
    binary_path: Path | None = None,
    derived_data: Path | None = None,
    skip_build: bool = False,
) -> Path:
    if binary_path is not None:
        if not binary_path.exists():
            raise RuntimeError(f"Provided GoStopCLI binary does not exist: {binary_path}")
        return binary_path

    for candidate in _binary_candidates(derived_data):
        if candidate.exists():
            return candidate

    if skip_build:
        searched = "\n".join(f"- {candidate}" for candidate in _binary_candidates(derived_data))
        raise RuntimeError(
            "No cached GoStopCLI binary was found for socket mode while --skip-build is enabled.\n"
            f"Searched:\n{searched}"
        )

    build_root = derived_data or default_socket_derived_data()
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
    candidate = build_root / "Build/Products/Debug/GoStopCLI"
    if not candidate.exists():
        raise RuntimeError(f"Build completed but GoStopCLI binary is missing: {candidate}")
    return candidate


class JSONLineSocketClient:
    def __init__(self, host: str, port: int) -> None:
        self.socket = socket.create_connection((host, port), timeout=5.0)
        self.socket.settimeout(5.0)
        self.reader = self.socket.makefile("r", encoding="utf-8", newline="\n")
        self.writer = self.socket.makefile("w", encoding="utf-8", newline="\n")

    def close(self) -> None:
        try:
            self.writer.close()
        finally:
            try:
                self.reader.close()
            finally:
                self.socket.close()

    def send(self, action: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        request: dict[str, Any] = {"action": action}
        if data is not None:
            request["data"] = data

        self.writer.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.writer.flush()

        while True:
            line = self.reader.readline()
            if not line:
                raise RuntimeError("Room transport TCP server closed before responding.")
            text = line.strip()
            if not text:
                continue
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                return payload


class WebSocketTextClient:
    MAGIC_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self.socket = socket.create_connection((host, port), timeout=5.0)
        self.socket.settimeout(5.0)
        self._perform_handshake()

    def close(self) -> None:
        try:
            self._send_frame(opcode=0x8, payload=b"")
        except OSError:
            pass
        finally:
            self.socket.close()

    def send(self, action: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        request: dict[str, Any] = {"action": action}
        if data is not None:
            request["data"] = data
        self._send_frame(opcode=0x1, payload=json.dumps(request, ensure_ascii=False).encode("utf-8"))

        while True:
            opcode, payload = self._recv_frame()
            if opcode == 0x9:
                self._send_frame(opcode=0xA, payload=payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                raise RuntimeError("Room transport websocket server closed before responding.")
            if opcode != 0x1:
                continue
            try:
                decoded = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(decoded, dict):
                return decoded

    def _perform_handshake(self) -> None:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET / HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        ).encode("ascii")
        self.socket.sendall(request)

        response = bytearray()
        while b"\r\n\r\n" not in response:
            chunk = self.socket.recv(4096)
            if not chunk:
                raise RuntimeError("Room transport websocket server closed during handshake.")
            response.extend(chunk)

        header_blob = response.decode("latin1")
        status_line = header_blob.split("\r\n", 1)[0]
        if "101" not in status_line:
            raise RuntimeError(f"Unexpected websocket handshake response: {status_line}")

        headers: dict[str, str] = {}
        for line in header_blob.split("\r\n")[1:]:
            if not line or ":" not in line:
                continue
            key_name, value = line.split(":", 1)
            headers[key_name.strip().lower()] = value.strip()

        expected_accept = base64.b64encode(
            hashlib.sha1((key + self.MAGIC_GUID).encode("ascii")).digest()
        ).decode("ascii")
        if headers.get("sec-websocket-accept") != expected_accept:
            raise RuntimeError("Room transport websocket handshake returned an invalid Sec-WebSocket-Accept.")

    def _send_frame(self, *, opcode: int, payload: bytes) -> None:
        frame = bytearray()
        frame.append(0x80 | (opcode & 0x0F))
        payload_length = len(payload)
        mask_key = os.urandom(4)
        if payload_length < 126:
            frame.append(0x80 | payload_length)
        elif payload_length <= 0xFFFF:
            frame.append(0x80 | 126)
            frame.extend(payload_length.to_bytes(2, "big"))
        else:
            frame.append(0x80 | 127)
            frame.extend(payload_length.to_bytes(8, "big"))
        frame.extend(mask_key)
        frame.extend(payload[index] ^ mask_key[index % 4] for index in range(payload_length))
        self.socket.sendall(frame)

    def _recv_exact(self, size: int) -> bytes:
        buffer = bytearray()
        while len(buffer) < size:
            chunk = self.socket.recv(size - len(buffer))
            if not chunk:
                raise RuntimeError("Room transport websocket server closed unexpectedly.")
            buffer.extend(chunk)
        return bytes(buffer)

    def _recv_frame(self) -> tuple[int, bytes]:
        header = self._recv_exact(2)
        first, second = header[0], header[1]
        opcode = first & 0x0F
        payload_length = second & 0x7F
        masked = bool(second & 0x80)
        if payload_length == 126:
            payload_length = int.from_bytes(self._recv_exact(2), "big")
        elif payload_length == 127:
            payload_length = int.from_bytes(self._recv_exact(8), "big")
        mask_key = self._recv_exact(4) if masked else b""
        payload = self._recv_exact(payload_length) if payload_length else b""
        if masked:
            payload = bytes(byte ^ mask_key[index % 4] for index, byte in enumerate(payload))
        return opcode, payload


class RoomTransportServerProcess:
    def __init__(self, binary_path: Path, transport: str = "tcp", port: int | None = None) -> None:
        self.binary_path = binary_path
        self.transport = transport
        self.port = port or self._pick_free_port()
        server_flag = (
            "--room-transport-websocket-server" if transport == "websocket" else "--room-transport-server"
        )
        self.process = subprocess.Popen(
            [str(binary_path), server_flag, "--port", str(self.port)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self.output_lines: list[str] = []
        self._wait_until_ready()

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.output_lines.extend(self._drain_output())

    def _wait_until_ready(self) -> None:
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                self.output_lines.extend(self._drain_output())
                raise RuntimeError(
                    f"GoStopCLI room transport {self.transport} server exited before becoming ready.\n"
                    + "\n".join(self.output_lines)
                )
            try:
                probe = socket.create_connection(("127.0.0.1", self.port), timeout=0.2)
            except OSError:
                time.sleep(0.05)
                continue
            probe.close()
            return

        self.output_lines.extend(self._drain_output())
        raise RuntimeError(
            f"Timed out waiting for GoStopCLI room transport {self.transport} server.\n"
            + "\n".join(self.output_lines)
        )

    def _drain_output(self) -> list[str]:
        if not self.process.stdout:
            return []
        lines: list[str] = []
        while True:
            line = self.process.stdout.readline()
            if not line:
                break
            lines.append(line.rstrip())
        return lines

    @staticmethod
    def _pick_free_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind(("127.0.0.1", 0))
            return int(probe.getsockname()[1])


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


def _engine_event_name(envelope: dict[str, Any]) -> str | None:
    event = _engine_event(envelope)
    if isinstance(event, dict):
        return event.get("eventName")
    return None


def _engine_event_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    event = _engine_event(envelope)
    payload = event.get("payload", {}) if isinstance(event, dict) else {}
    return payload if isinstance(payload, dict) else {}


def _find_engine_event(
    envelopes: list[dict[str, Any]],
    *,
    event_name: str | None = None,
    reason: str | None = None,
    snapshot_only: bool = False,
) -> dict[str, Any]:
    for envelope in envelopes:
        event = _engine_event(envelope)
        if not isinstance(event, dict):
            continue
        payload = event.get("payload", {})
        if not isinstance(payload, dict):
            payload = {}
        if event_name is not None and event.get("eventName") != event_name:
            continue
        if snapshot_only and "state" not in payload:
            continue
        if reason is not None and payload.get("reason") != reason:
            continue
        return event
    raise RuntimeError(
        f"Missing engine event event_name={event_name!r} reason={reason!r} snapshot_only={snapshot_only!r}"
    )


def _frame_label(envelope: dict[str, Any]) -> str:
    if envelope.get("type") == "roomEvent":
        return _room_event_name(envelope) or "roomEvent"
    if envelope.get("type") == "gameEvent":
        return _engine_event_name(envelope) or "gameEvent"
    return str(envelope.get("type"))


def _label_index(labels: list[str], label: str) -> int | None:
    try:
        return labels.index(label)
    except ValueError:
        return None


def _contains_label_sequence(labels: list[str], required: list[str]) -> bool:
    required_index = 0
    for label in labels:
        if required_index >= len(required):
            break
        if label == required[required_index]:
            required_index += 1
    return required_index == len(required)


def _game_event_id(envelope: dict[str, Any]) -> str | None:
    event = _engine_event(envelope)
    if isinstance(event, dict):
        event_id = event.get("eventId")
        if isinstance(event_id, str):
            return event_id
    return None


def _frame_signature(envelope: dict[str, Any]) -> dict[str, Any]:
    signature: dict[str, Any] = {
        "type": envelope.get("type"),
        "label": _frame_label(envelope),
        "roomSequence": envelope.get("roomSequence"),
    }
    event_id = _game_event_id(envelope)
    if event_id is not None:
        signature["eventId"] = event_id
    snapshot_reason = _snapshot_reason(_engine_event(envelope) or {}) if envelope.get("type") == "gameEvent" else None
    if snapshot_reason is not None:
        signature["snapshotReason"] = snapshot_reason
    return signature


def _terminal_summary_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    if envelope.get("type") != "terminalSummary":
        raise RuntimeError(f"Expected terminalSummary envelope, got {envelope.get('type')!r}")
    payload = envelope.get("payload", {})
    if not isinstance(payload, dict):
        raise RuntimeError("terminalSummary payload is missing.")
    return payload


def _snapshot_payload(event: dict[str, Any]) -> dict[str, Any]:
    payload = event.get("payload", {})
    if not isinstance(payload, dict):
        raise RuntimeError("Snapshot payload is missing.")
    return payload


def _snapshot_state(event: dict[str, Any]) -> dict[str, Any]:
    payload = _snapshot_payload(event)
    state = payload.get("state")
    if not isinstance(state, dict):
        raise RuntimeError("Snapshot state is missing.")
    return state


def _snapshot_state_version(event: dict[str, Any]) -> int:
    payload = _snapshot_payload(event)
    value = payload.get("snapshotStateVersion")
    if isinstance(value, int):
        return value
    state_value = _snapshot_state(event).get("stateVersion")
    if isinstance(state_value, int):
        return state_value
    raise RuntimeError("Snapshot stateVersion is missing.")


def _snapshot_id(event: dict[str, Any]) -> str:
    payload = _snapshot_payload(event)
    snapshot_id = payload.get("snapshotId")
    if not isinstance(snapshot_id, str):
        raise RuntimeError("Snapshot id is missing.")
    return snapshot_id


def _snapshot_reason(event: dict[str, Any]) -> str | None:
    payload = _snapshot_payload(event)
    reason = payload.get("reason")
    return reason if isinstance(reason, str) else None


def _projection_state(snapshot: dict[str, Any]) -> dict[str, Any]:
    state = snapshot.get("state")
    if not isinstance(state, dict):
        raise RuntimeError("Projection snapshot state is missing.")
    return state


def _projection_snapshot_id(snapshot: dict[str, Any]) -> str:
    snapshot_id = snapshot.get("snapshotId")
    if not isinstance(snapshot_id, str):
        raise RuntimeError("Projection snapshot id is missing.")
    return snapshot_id


def _projection_snapshot_reason(snapshot: dict[str, Any]) -> str | None:
    reason = snapshot.get("reason")
    return reason if isinstance(reason, str) else None


def _projection_snapshot_state_version(snapshot: dict[str, Any]) -> int:
    value = snapshot.get("snapshotStateVersion")
    if isinstance(value, int):
        return value
    state_value = _projection_state(snapshot).get("stateVersion")
    if isinstance(state_value, int):
        return state_value
    raise RuntimeError("Projection snapshot stateVersion is missing.")


def _normalize_injected_mismatch_mode(raw: Any) -> str | None:
    if raw == "staleExpectedStateVersionOverride":
        return "staleExpectedStateVersion"
    if isinstance(raw, str):
        return raw
    return None


def _transport_summary_label(transport: str) -> str:
    if transport == "websocket":
        return "websocket"
    return "TCP fallback"


def _bootstrap_recommended_next_actions(stage: str) -> list[str]:
    if stage == "createRoom":
        return ["room_transport_connect", "room_transport_send(action=hello)"]
    if stage == "lookupInvite":
        return ["room_bootstrap_join"]
    if stage == "joinRoom":
        return ["room_transport_connect", "room_transport_send(action=hello)", "room_set_ready"]
    if stage == "prepareGameStart":
        return ["room_transport_receive"]
    return []


def _assert_bootstrap_boundary(
    payload: Any,
    *,
    stage: str,
    current_action: str,
    future_public_route: str,
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError("bootstrapBoundary payload is missing.")

    if payload.get("surfaceKind") != "publicBootstrapFacade":
        raise RuntimeError(f"bootstrapBoundary.surfaceKind expected 'publicBootstrapFacade', got {payload.get('surfaceKind')!r}")
    if payload.get("boundaryVersion") != "room-bootstrap.v1":
        raise RuntimeError(
            f"bootstrapBoundary.boundaryVersion expected 'room-bootstrap.v1', got {payload.get('boundaryVersion')!r}"
        )
    if payload.get("stage") != stage:
        raise RuntimeError(f"bootstrapBoundary.stage expected {stage!r}, got {payload.get('stage')!r}")

    current_boundary = payload.get("currentBoundary")
    if not isinstance(current_boundary, dict):
        raise RuntimeError("bootstrapBoundary.currentBoundary is missing.")
    expected_current_boundary = {
        "mode": "concreteCommandFacade",
        "createAction": "room_bootstrap_create",
        "lookupInviteAction": "room_bootstrap_lookup_invite",
        "joinAction": "room_bootstrap_join",
        "prepareGameStartAction": "room_bootstrap_prepare_game_start",
    }
    if current_boundary != expected_current_boundary:
        raise RuntimeError(
            "bootstrapBoundary.currentBoundary diverged from the locked bootstrap facade.\n"
            f"expected={json.dumps(expected_current_boundary, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(current_boundary, ensure_ascii=False, sort_keys=True)}"
        )

    if payload.get("currentCommandAction") != current_action:
        raise RuntimeError(
            "bootstrapBoundary.currentCommandAction expected "
            f"{current_action!r}, got {payload.get('currentCommandAction')!r}"
        )

    future_public_split = payload.get("futurePublicSplit")
    if not isinstance(future_public_split, dict):
        raise RuntimeError("bootstrapBoundary.futurePublicSplit is missing.")
    if future_public_split.get("status") != "placeholder":
        raise RuntimeError(
            "bootstrapBoundary.futurePublicSplit.status expected 'placeholder', got "
            f"{future_public_split.get('status')!r}"
        )
    if future_public_split.get("route") != future_public_route:
        raise RuntimeError(
            "bootstrapBoundary.futurePublicSplit.route expected "
            f"{future_public_route!r}, got {future_public_split.get('route')!r}"
        )

    gameplay_boundary = payload.get("gameplayTransportBoundary")
    if not isinstance(gameplay_boundary, dict):
        raise RuntimeError("bootstrapBoundary.gameplayTransportBoundary is missing.")
    expected_gameplay_boundary = {
        "connectAction": "room_transport_connect",
        "sendAction": "room_transport_send",
        "receiveAction": "room_transport_receive",
        "helloAction": "hello",
    }
    if gameplay_boundary != expected_gameplay_boundary:
        raise RuntimeError(
            "bootstrapBoundary.gameplayTransportBoundary diverged from the locked transport surface.\n"
            f"expected={json.dumps(expected_gameplay_boundary, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(gameplay_boundary, ensure_ascii=False, sort_keys=True)}"
        )

    recommended_next_actions = payload.get("recommendedNextActions")
    expected_next_actions = _bootstrap_recommended_next_actions(stage)
    if recommended_next_actions != expected_next_actions:
        raise RuntimeError(
            "bootstrapBoundary.recommendedNextActions diverged from the locked stage guidance.\n"
            f"expected={json.dumps(expected_next_actions, ensure_ascii=False)}\n"
            f"actual={json.dumps(recommended_next_actions, ensure_ascii=False)}"
        )

    if payload.get("gapRecoveryShapeAction") != "room_gap_recovery_shape":
        raise RuntimeError(
            "bootstrapBoundary.gapRecoveryShapeAction expected 'room_gap_recovery_shape', got "
            f"{payload.get('gapRecoveryShapeAction')!r}"
        )
    gap_recovery = payload.get("gapRecovery")
    expected_gap_recovery = {
        "shapeAction": "room_gap_recovery_shape",
        "transportTriggerAction": "triggerGapRecovery",
    }
    if gap_recovery != expected_gap_recovery:
        raise RuntimeError(
            "bootstrapBoundary.gapRecovery diverged from the locked live gap hook surface.\n"
            f"expected={json.dumps(expected_gap_recovery, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(gap_recovery, ensure_ascii=False, sort_keys=True)}"
        )

    return {
        "surfaceKind": payload["surfaceKind"],
        "boundaryVersion": payload["boundaryVersion"],
        "stage": payload["stage"],
        "currentBoundary": dict(current_boundary),
        "currentCommandAction": payload["currentCommandAction"],
        "futurePublicSplit": dict(future_public_split),
        "recommendedNextActions": list(recommended_next_actions),
        "gameplayTransportBoundary": dict(gameplay_boundary),
        "gapRecoveryShapeAction": payload["gapRecoveryShapeAction"],
        "gapRecovery": dict(gap_recovery),
    }


def _assert_paired_bootstrap_by_player(
    payload: Any,
    *,
    room_id: str,
    game_id: str,
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError("bootstrapByPlayerId payload is missing.")

    viewer_bootstrap: dict[str, Any] = {}
    for room_player_id in ("p1", "p2"):
        bootstrap = payload.get(room_player_id)
        if not isinstance(bootstrap, dict):
            raise RuntimeError(f"bootstrapByPlayerId[{room_player_id!r}] is missing.")
        game_started = bootstrap.get("gameStarted")
        state_snapshot = bootstrap.get("stateSnapshot")
        if not isinstance(game_started, dict) or not isinstance(state_snapshot, dict):
            raise RuntimeError(f"bootstrapByPlayerId[{room_player_id!r}] is missing gameStarted/stateSnapshot pair.")
        snapshot_state = state_snapshot.get("state")
        if not isinstance(snapshot_state, dict):
            raise RuntimeError(f"bootstrapByPlayerId[{room_player_id!r}].stateSnapshot.state is missing.")
        if state_snapshot.get("reason") != "gameStarted":
            raise RuntimeError(
                f"bootstrapByPlayerId[{room_player_id!r}] snapshot reason expected 'gameStarted', got {state_snapshot.get('reason')!r}"
            )
        if game_started.get("snapshotId") != state_snapshot.get("snapshotId"):
            raise RuntimeError(
                f"bootstrapByPlayerId[{room_player_id!r}] snapshotId pair diverged: "
                f"{game_started.get('snapshotId')!r} vs {state_snapshot.get('snapshotId')!r}"
            )
        if game_started.get("snapshotStateVersion") != state_snapshot.get("snapshotStateVersion"):
            raise RuntimeError(
                f"bootstrapByPlayerId[{room_player_id!r}] snapshotStateVersion pair diverged: "
                f"{game_started.get('snapshotStateVersion')!r} vs {state_snapshot.get('snapshotStateVersion')!r}"
            )
        if snapshot_state.get("roomId") != room_id:
            raise RuntimeError(
                f"bootstrapByPlayerId[{room_player_id!r}] state.roomId expected {room_id!r}, got {snapshot_state.get('roomId')!r}"
            )
        if snapshot_state.get("gameId") != game_id:
            raise RuntimeError(
                f"bootstrapByPlayerId[{room_player_id!r}] state.gameId expected {game_id!r}, got {snapshot_state.get('gameId')!r}"
            )
        if not isinstance(snapshot_state.get("viewerPlayerId"), str):
            raise RuntimeError(f"bootstrapByPlayerId[{room_player_id!r}] viewerPlayerId is missing.")
        viewer_bootstrap[room_player_id] = {
            "viewerPlayerId": snapshot_state["viewerPlayerId"],
            "snapshotId": state_snapshot["snapshotId"],
            "snapshotReason": state_snapshot["reason"],
            "snapshotStateVersion": state_snapshot["snapshotStateVersion"],
            "stateVersion": snapshot_state.get("stateVersion"),
            "turnId": snapshot_state.get("turnId"),
            "currentPlayerId": snapshot_state.get("currentPlayerId"),
        }

    return {
        "roomPlayerIds": sorted(viewer_bootstrap),
        "byRoomPlayerId": viewer_bootstrap,
    }


def _assert_gap_recovery_shape(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError("gapRecoveryShape payload is missing.")
    if payload.get("mode") != "artifactOnly":
        raise RuntimeError(f"gapRecoveryShape.mode expected 'artifactOnly', got {payload.get('mode')!r}")

    transport_flag = payload.get("transportFlag")
    if not isinstance(transport_flag, dict):
        raise RuntimeError("gapRecoveryShape.transportFlag is missing.")
    expected_transport_flag = {
        "name": "gapDetected",
        "status": "placeholder",
        "currentEmission": False,
        "futureTrigger": "missingGameEventOrStateVersionGap",
    }
    if transport_flag != expected_transport_flag:
        raise RuntimeError(
            "gapRecoveryShape.transportFlag diverged from the locked preflight contract.\n"
            f"expected={json.dumps(expected_transport_flag, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(transport_flag, ensure_ascii=False, sort_keys=True)}"
        )

    artifact = payload.get("artifact")
    if not isinstance(artifact, dict):
        raise RuntimeError("gapRecoveryShape.artifact is missing.")
    expected_artifact = {
        "name": "gapRecoveryHint",
        "inputLockRequired": True,
        "snapshotReason": "gapDetected",
        "minimumFields": [
            "roomId",
            "sessionId",
            "lastAckedGameEventId",
            "lastSeenStateVersion",
            "authoritativeEventId",
            "authoritativeStateVersion",
        ],
    }
    if artifact != expected_artifact:
        raise RuntimeError(
            "gapRecoveryShape.artifact diverged from the locked preflight contract.\n"
            f"expected={json.dumps(expected_artifact, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(artifact, ensure_ascii=False, sort_keys=True)}"
        )

    recovery_envelope = payload.get("recoveryEnvelope")
    if not isinstance(recovery_envelope, dict):
        raise RuntimeError("gapRecoveryShape.recoveryEnvelope is missing.")
    expected_recovery_envelope = {
        "type": "gameEvent",
        "eventName": "stateSnapshot",
        "reason": "gapDetected",
    }
    if recovery_envelope != expected_recovery_envelope:
        raise RuntimeError(
            "gapRecoveryShape.recoveryEnvelope diverged from the locked preflight contract.\n"
            f"expected={json.dumps(expected_recovery_envelope, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(recovery_envelope, ensure_ascii=False, sort_keys=True)}"
        )

    related_actions = payload.get("relatedActions")
    if not isinstance(related_actions, dict):
        raise RuntimeError("gapRecoveryShape.relatedActions is missing.")
    expected_related_actions = {
        "bootstrapPrepareAction": "room_bootstrap_prepare_game_start",
        "debugStaleHookAction": "room_set_mp008_hook",
    }
    if related_actions != expected_related_actions:
        raise RuntimeError(
            "gapRecoveryShape.relatedActions diverged from the locked preflight contract.\n"
            f"expected={json.dumps(expected_related_actions, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(related_actions, ensure_ascii=False, sort_keys=True)}"
        )

    live_hook = payload.get("liveHook")
    expected_live_hook = {
        "transportAction": "room_transport_send(action=triggerGapRecovery)",
        "recoveryEnvelopeType": "gapRecoveryHint",
    }
    if live_hook != expected_live_hook:
        raise RuntimeError(
            "gapRecoveryShape.liveHook diverged from the locked live hook contract.\n"
            f"expected={json.dumps(expected_live_hook, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(live_hook, ensure_ascii=False, sort_keys=True)}"
        )

    return {
        "mode": payload["mode"],
        "transportFlag": dict(transport_flag),
        "artifact": dict(artifact),
        "recoveryEnvelope": dict(recovery_envelope),
        "relatedActions": dict(related_actions),
        "liveHook": dict(live_hook),
    }


def _assert_gap_recovery_hint(
    payload: Any,
    *,
    room_id: str,
    session_id: str,
    target_client_id: str,
    last_acked_game_event_id: str | None,
    last_seen_state_version: int,
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError("gapRecoveryHint payload is missing.")

    if payload.get("artifactVersion") != "gapRecoveryHint.v1":
        raise RuntimeError(
            f"gapRecoveryHint.artifactVersion expected 'gapRecoveryHint.v1', got {payload.get('artifactVersion')!r}"
        )
    transport_flag = payload.get("transportFlag")
    expected_transport_flag = {
        "name": "gapDetected",
        "value": True,
    }
    if transport_flag != expected_transport_flag:
        raise RuntimeError(
            "gapRecoveryHint.transportFlag diverged from the locked live payload.\n"
            f"expected={json.dumps(expected_transport_flag, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(transport_flag, ensure_ascii=False, sort_keys=True)}"
        )
    if payload.get("inputLockRequired") is not True:
        raise RuntimeError("gapRecoveryHint.inputLockRequired expected True.")
    if payload.get("roomId") != room_id:
        raise RuntimeError(f"gapRecoveryHint.roomId expected {room_id!r}, got {payload.get('roomId')!r}")
    if payload.get("sessionId") != session_id:
        raise RuntimeError(
            f"gapRecoveryHint.sessionId expected {session_id!r}, got {payload.get('sessionId')!r}"
        )
    if payload.get("targetClientId") != target_client_id:
        raise RuntimeError(
            f"gapRecoveryHint.targetClientId expected {target_client_id!r}, got {payload.get('targetClientId')!r}"
        )
    if payload.get("lastAckedGameEventId") != last_acked_game_event_id:
        raise RuntimeError(
            "gapRecoveryHint.lastAckedGameEventId diverged from the trigger payload.\n"
            f"expected={last_acked_game_event_id!r} actual={payload.get('lastAckedGameEventId')!r}"
        )
    if payload.get("lastSeenStateVersion") != last_seen_state_version:
        raise RuntimeError(
            "gapRecoveryHint.lastSeenStateVersion diverged from the trigger payload.\n"
            f"expected={last_seen_state_version!r} actual={payload.get('lastSeenStateVersion')!r}"
        )
    authoritative_event_id = payload.get("authoritativeEventId")
    if not isinstance(authoritative_event_id, str):
        raise RuntimeError("gapRecoveryHint.authoritativeEventId is missing.")
    authoritative_state_version = payload.get("authoritativeStateVersion")
    if not isinstance(authoritative_state_version, int):
        raise RuntimeError("gapRecoveryHint.authoritativeStateVersion is missing.")
    if payload.get("snapshotReason") != "gapDetected":
        raise RuntimeError(
            f"gapRecoveryHint.snapshotReason expected 'gapDetected', got {payload.get('snapshotReason')!r}"
        )
    recovery_envelope = payload.get("recoveryEnvelope")
    expected_recovery_envelope = {
        "type": "gameEvent",
        "eventName": "stateSnapshot",
        "reason": "gapDetected",
    }
    if recovery_envelope != expected_recovery_envelope:
        raise RuntimeError(
            "gapRecoveryHint.recoveryEnvelope diverged from the locked live payload.\n"
            f"expected={json.dumps(expected_recovery_envelope, ensure_ascii=False, sort_keys=True)}\n"
            f"actual={json.dumps(recovery_envelope, ensure_ascii=False, sort_keys=True)}"
        )

    return {
        "artifactVersion": payload["artifactVersion"],
        "transportFlag": dict(transport_flag),
        "inputLockRequired": payload["inputLockRequired"],
        "roomId": payload["roomId"],
        "sessionId": payload["sessionId"],
        "targetClientId": payload["targetClientId"],
        "lastAckedGameEventId": payload.get("lastAckedGameEventId"),
        "lastSeenStateVersion": payload["lastSeenStateVersion"],
        "authoritativeEventId": authoritative_event_id,
        "authoritativeStateVersion": authoritative_state_version,
        "snapshotReason": payload["snapshotReason"],
        "recoveryEnvelope": dict(recovery_envelope),
    }


class SocketTransportHarness:
    def __init__(self, repo_root: Path, binary_path: Path, transport: str = "tcp") -> None:
        self.repo_root = repo_root
        self.transport = transport
        self.server = RoomTransportServerProcess(binary_path, transport=transport)
        client_factory: Callable[[str, int], JSONLineSocketClient | WebSocketTextClient]
        if transport == "websocket":
            client_factory = WebSocketTextClient
        else:
            client_factory = JSONLineSocketClient
        self._client_factory = client_factory
        self.connection_clients: dict[str, JSONLineSocketClient | WebSocketTextClient] = {
            "control": client_factory("127.0.0.1", self.server.port)
        }
        self.client = self.connection_clients["control"]
        self.command_rows: list[dict[str, Any]] = []
        self.frame_rows: list[dict[str, Any]] = []
        self.agent_log_lines: list[str] = [
            f"transportBackend={self.transport}",
            f"transportServerPort={self.server.port}",
            f"binaryPath={binary_path}",
        ]
        self.room_log_lines: list[str] = []
        self.engine_log_lines: list[str] = []
        self.transport_clients: dict[str, dict[str, Any]] = {}

    def close(self) -> None:
        try:
            for alias in list(self.connection_clients):
                client = self.connection_clients.pop(alias)
                try:
                    client.close()
                finally:
                    self.agent_log_lines.append(f"connectionClosed={alias}")
        finally:
            self.server.close()
            for line in self.server.output_lines:
                self.agent_log_lines.append(f"server: {line}")

    def open_connection(self, alias: str) -> None:
        if alias in self.connection_clients:
            return
        self.connection_clients[alias] = self._client_factory("127.0.0.1", self.server.port)
        self.agent_log_lines.append(f"connectionOpened={alias}")

    def close_connection(self, alias: str) -> None:
        if alias == "control":
            raise RuntimeError("The control connection cannot be closed independently.")
        client = self.connection_clients.pop(alias, None)
        if client is None:
            raise RuntimeError(f"Transport connection alias is not open: {alias}")
        try:
            client.close()
        finally:
            self.agent_log_lines.append(f"connectionClosed={alias}")

    def _connection(self, alias: str) -> JSONLineSocketClient | WebSocketTextClient:
        client = self.connection_clients.get(alias)
        if client is None:
            raise RuntimeError(f"Transport connection alias is not open: {alias}")
        return client

    def send(
        self,
        action: str,
        data: dict[str, Any] | None = None,
        *,
        connection_alias: str = "control",
    ) -> dict[str, Any]:
        response = self._connection(connection_alias).send(action, data)
        self.command_rows.append(
            {
                "timestamp": _iso_now(),
                "transportBackend": self.transport,
                "connectionAlias": connection_alias,
                "action": action,
                "request": data or {},
                "response": response,
            }
        )
        return response

    def require_ok(
        self,
        action: str,
        data: dict[str, Any] | None = None,
        *,
        connection_alias: str = "control",
    ) -> dict[str, Any]:
        response = self.send(action, data, connection_alias=connection_alias)
        if response.get("status") != "ok":
            raise RuntimeError(f"{action} failed: {json.dumps(response, ensure_ascii=False, indent=2)}")
        return response["data"]

    def require_status(
        self,
        action: str,
        expected_status: str,
        data: dict[str, Any] | None = None,
        *,
        connection_alias: str = "control",
    ) -> dict[str, Any]:
        response = self.send(action, data, connection_alias=connection_alias)
        if response.get("status") != expected_status:
            raise RuntimeError(
                f"{action} expected status={expected_status}, got: "
                f"{json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        return response

    def require_action_executed(
        self,
        action: str,
        data: dict[str, Any] | None = None,
        *,
        connection_alias: str = "control",
    ) -> dict[str, Any]:
        response = self.send(action, data, connection_alias=connection_alias)
        if response.get("status") != "action executed":
            raise RuntimeError(
                f"{action} expected status=action executed, got: {json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        return response

    def require_error(
        self,
        action: str,
        data: dict[str, Any],
        expected_code: str,
        *,
        connection_alias: str = "control",
    ) -> dict[str, Any]:
        response = self.send(action, data, connection_alias=connection_alias)
        if response.get("status") != "error":
            raise RuntimeError(
                f"{action} expected error {expected_code}, got: {json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        if response.get("errorCode") != expected_code:
            raise RuntimeError(
                f"{action} expected errorCode={expected_code}, got: {json.dumps(response, ensure_ascii=False, indent=2)}"
            )
        return response

    def ensure_engine_started(self) -> None:
        self.require_action_executed("start_game")
        self.agent_log_lines.append("warmup=start_game")

    def bootstrap_two_player_room(self) -> dict[str, Any]:
        create = self.require_ok(
            "room_bootstrap_create",
            {
                "hostPlayerId": "p1",
                "deviceId": "dev1",
                "roomType": "invite",
                "joinPolicy": "inviteCode",
            },
        )
        create_boundary = _assert_bootstrap_boundary(
            create.get("bootstrapBoundary"),
            stage="createRoom",
            current_action="room_bootstrap_create",
            future_public_route="POST /api/multiplayer/rooms",
        )
        create_room = create.get("room", {})
        invite_code = create_room.get("inviteCode") if isinstance(create_room, dict) else None
        if not isinstance(invite_code, str):
            invite_code = create["room"]["roomId"]
        lookup = self.require_ok(
            "room_bootstrap_lookup_invite",
            {
                "inviteCode": invite_code,
            },
        )
        lookup_boundary = _assert_bootstrap_boundary(
            lookup.get("bootstrapBoundary"),
            stage="lookupInvite",
            current_action="room_bootstrap_lookup_invite",
            future_public_route="GET /api/multiplayer/invites/{inviteCode}",
        )
        lookup_summary = lookup.get("roomSummary")
        if not isinstance(lookup_summary, dict):
            raise RuntimeError("room_bootstrap_lookup_invite roomSummary is missing.")
        if lookup_summary.get("roomId") != create["room"]["roomId"]:
            raise RuntimeError(
                "room_bootstrap_lookup_invite roomId diverged from the created room.\n"
                f"expected={create['room']['roomId']!r} actual={lookup_summary.get('roomId')!r}"
            )
        if lookup_summary.get("inviteCode") != invite_code:
            raise RuntimeError(
                "room_bootstrap_lookup_invite inviteCode diverged from the bootstrap create response.\n"
                f"expected={invite_code!r} actual={lookup_summary.get('inviteCode')!r}"
            )
        if lookup_summary.get("canJoin") is not True:
            raise RuntimeError(f"room_bootstrap_lookup_invite canJoin expected True, got {lookup_summary.get('canJoin')!r}")
        if lookup_summary.get("memberCount") != 1:
            raise RuntimeError(
                f"room_bootstrap_lookup_invite memberCount expected 1, got {lookup_summary.get('memberCount')!r}"
            )
        if lookup_summary.get("availableSeatCount") != 1:
            raise RuntimeError(
                "room_bootstrap_lookup_invite availableSeatCount expected 1, got "
                f"{lookup_summary.get('availableSeatCount')!r}"
            )
        join = self.require_ok(
            "room_bootstrap_join",
            {
                "roomId": create["room"]["roomId"],
                "playerId": "p2",
                "deviceId": "dev2",
            },
        )
        join_boundary = _assert_bootstrap_boundary(
            join.get("bootstrapBoundary"),
            stage="joinRoom",
            current_action="room_bootstrap_join",
            future_public_route="POST /api/multiplayer/rooms/{roomId}/join",
        )
        return {
            "room_id": create["room"]["roomId"],
            "host_session_id": create["session"]["sessionId"],
            "guest_session_id": join["session"]["sessionId"],
            "host_resume_token": create["session"]["resumeToken"],
            "guest_resume_token": join["session"]["resumeToken"],
            "invite_code": invite_code,
            "bootstrapBoundary": {
                "create": create_boundary,
                "lookupInvite": lookup_boundary,
                "join": join_boundary,
            },
            "lookupInviteSummary": lookup_summary,
        }

    def connect_transport_client(
        self,
        client_id: str,
        room_id: str,
        session_id: str,
        player_id: str,
        device_id: str,
        resume_token: str,
        *,
        connection_alias: str = "control",
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
            connection_alias=connection_alias,
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

    def transport_send_ok(
        self,
        client_id: str,
        transport_action: str,
        *,
        connection_alias: str = "control",
        **kwargs: Any,
    ) -> dict[str, Any]:
        payload = {"clientId": client_id, "action": transport_action}
        payload.update(kwargs)
        data = self.require_ok("room_transport_send", payload, connection_alias=connection_alias)
        client = data.get("client")
        if isinstance(client, dict):
            self.transport_clients[client_id] = client
        return data

    def transport_send_error(
        self,
        client_id: str,
        transport_action: str,
        expected_code: str,
        *,
        connection_alias: str = "control",
        **kwargs: Any,
    ) -> dict[str, Any]:
        payload = {"clientId": client_id, "action": transport_action}
        payload.update(kwargs)
        return self.require_error(
            "room_transport_send",
            payload,
            expected_code=expected_code,
            connection_alias=connection_alias,
        )

    def transport_receive(self, client_id: str, *, connection_alias: str = "control") -> list[dict[str, Any]]:
        data = self.require_ok(
            "room_transport_receive",
            {"clientId": client_id},
            connection_alias=connection_alias,
        )
        envelopes = data["envelopes"]
        received_at = _iso_now()
        for index, envelope in enumerate(envelopes, start=1):
            row = {
                "clientId": client_id,
                "connectionAlias": connection_alias,
                "receivedAt": received_at,
                "receiveIndex": index,
                "transportBackend": self.transport,
                **envelope,
            }
            self.frame_rows.append(row)
            self.room_log_lines.append(
                f"[{received_at}] client={client_id} type={envelope.get('type')} "
                f"roomSequence={envelope.get('roomSequence')} label={_frame_label(envelope)}"
            )
            if envelope.get("type") == "gameEvent":
                self.engine_log_lines.append(
                    f"[{received_at}] client={client_id} "
                    f"gameEvent={json.dumps(envelope.get('payload', {}), ensure_ascii=False)}"
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


def _player_snapshot_record(event: dict[str, Any], player_id: str) -> dict[str, Any]:
    state = _snapshot_state(event)
    return _snapshot_record(
        payload=state,
        snapshot_id=_snapshot_id(event),
        source="initial",
        scope="player",
        player_id=player_id,
        state_version=_snapshot_state_version(event),
        event_id=event.get("eventId"),
    )


def _projection_snapshot_record(
    snapshot: dict[str, Any],
    *,
    source: str,
    scope: str,
    player_id: str | None,
) -> dict[str, Any]:
    state = _projection_state(snapshot)
    return _snapshot_record(
        payload=state,
        snapshot_id=_projection_snapshot_id(snapshot),
        source=source,
        scope=scope,
        player_id=player_id,
        state_version=_projection_snapshot_state_version(snapshot),
        event_id=state.get("lastEventId"),
    )


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


def _collect_projection_players(snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    players: list[dict[str, Any]] = []
    for player in _projection_state(snapshot).get("players", []):
        if not isinstance(player, dict):
            continue
        player_id = player.get("playerId")
        if not isinstance(player_id, str):
            continue
        seat = player.get("seatIndex")
        connection_state = "connected" if player.get("isConnected") is True else "unknown"
        players.append(
            {
                "player_id": player_id,
                "seat": seat if isinstance(seat, int) else None,
                "connection_state": connection_state,
            }
        )
    return players


def _fetch_room_projection(
    harness: SocketTransportHarness,
    room_id: str,
    viewer_player_id: str,
    *,
    snapshot_reason: str = "localPreview",
    state_version: int | None = None,
    last_event_id: str | None = None,
) -> dict[str, Any]:
    request: dict[str, Any] = {
        "roomId": room_id,
        "viewerPlayerId": viewer_player_id,
        "snapshotReason": snapshot_reason,
    }
    if state_version is not None:
        request["stateVersion"] = state_version
    if last_event_id is not None:
        request["lastEventId"] = last_event_id

    data = harness.require_ok(
        "room_projection_preview",
        request,
    )
    projection = data.get("projection")
    if not isinstance(projection, dict):
        raise RuntimeError(f"room_projection_preview is missing projection for viewer={viewer_player_id!r}.")
    snapshot = projection.get("snapshot")
    if isinstance(snapshot, dict):
        return snapshot
    return projection


def _viewer_projection_player(snapshot: dict[str, Any]) -> dict[str, Any]:
    for player in _projection_state(snapshot).get("players", []):
        if isinstance(player, dict) and player.get("isViewer") is True:
            return player
    raise RuntimeError("Projection is missing the viewer player payload.")


def _viewer_projection_authority_player_id(snapshot: dict[str, Any]) -> str:
    viewer_player_id = _projection_state(snapshot).get("viewerPlayerId")
    if not isinstance(viewer_player_id, str):
        raise RuntimeError("Projection viewerPlayerId is missing.")
    return viewer_player_id


def _projection_captured_totals(snapshot: dict[str, Any]) -> dict[str, int]:
    totals: dict[str, int] = {}
    for player in _projection_state(snapshot).get("players", []):
        if not isinstance(player, dict):
            continue
        player_id = player.get("playerId")
        captured = player.get("captured")
        if not isinstance(player_id, str) or not isinstance(captured, dict):
            continue
        totals[player_id] = sum(
            len(captured.get(kind) or [])
            for kind in ("bright", "animal", "ribbon", "junk")
        )
    return totals


def _select_deterministic_hand_card(snapshot: dict[str, Any]) -> dict[str, Any]:
    viewer_player = _viewer_projection_player(snapshot)
    hand = viewer_player.get("hand")
    if not isinstance(hand, list):
        raise RuntimeError("Viewer hand is missing from the projection.")

    candidates = [card for card in hand if isinstance(card, dict) and isinstance(card.get("cardId"), str)]
    if not candidates:
        raise RuntimeError("Viewer hand does not contain a playable card.")

    candidates.sort(
        key=lambda card: (
            card.get("month", 99),
            str(card.get("kind", "")),
            card.get("imageIndex", 99),
            str(card.get("cardId")),
        )
    )
    return candidates[0]


def _resolve_transport_actor(
    host_projection: dict[str, Any],
    guest_projection: dict[str, Any],
    authority_player_id: str,
) -> tuple[str, str, dict[str, Any]]:
    host_viewer_id = _viewer_projection_authority_player_id(host_projection)
    guest_viewer_id = _viewer_projection_authority_player_id(guest_projection)
    if authority_player_id == host_viewer_id:
        return "host_client", "p1", host_projection
    if authority_player_id == guest_viewer_id:
        return "guest_client", "p2", guest_projection
    raise RuntimeError(
        "Could not resolve the acting client from the current projections.\n"
        f"authority_player_id={authority_player_id!r} host_viewer_id={host_viewer_id!r} guest_viewer_id={guest_viewer_id!r}"
    )


def _resolve_pending_choice(
    host_projection: dict[str, Any],
    guest_projection: dict[str, Any],
) -> tuple[dict[str, Any], str, str, dict[str, Any]] | None:
    host_pending = _projection_state(host_projection).get("pendingChoice")
    guest_pending = _projection_state(guest_projection).get("pendingChoice")
    for pending_choice in (host_pending, guest_pending):
        if not isinstance(pending_choice, dict):
            continue
        actor_player_id = pending_choice.get("actorPlayerId")
        if not isinstance(actor_player_id, str):
            continue
        actor_client_id, actor_room_player_id, actor_projection = _resolve_transport_actor(
            host_projection,
            guest_projection,
            actor_player_id,
        )
        actor_pending_choice = _projection_state(actor_projection).get("pendingChoice")
        if isinstance(actor_pending_choice, dict):
            return actor_pending_choice, actor_client_id, actor_room_player_id, actor_projection
        return pending_choice, actor_client_id, actor_room_player_id, actor_projection
    return None


def _choose_pending_choice_option_code(pending_choice: dict[str, Any]) -> str:
    options = [
        option
        for option in pending_choice.get("options", [])
        if isinstance(option, dict) and isinstance(option.get("optionCode"), str)
    ]
    if not options:
        raise RuntimeError(f"Pending choice {pending_choice.get('choiceId')!r} does not expose any options.")

    choice_kind = pending_choice.get("choiceKind")
    if choice_kind == "goStop":
        preferred_code = "go"
    elif choice_kind == "shake":
        preferred_code = "shake_no"
    else:
        preferred_code = None

    if preferred_code is not None:
        for option in options:
            if option["optionCode"] == preferred_code:
                return preferred_code
        raise RuntimeError(
            f"Pending choice {pending_choice.get('choiceId')!r} is missing the preferred optionCode={preferred_code!r}."
        )

    return options[0]["optionCode"]


def _drain_live_mailboxes(harness: SocketTransportHarness) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    return (
        harness.transport_receive("host_client"),
        harness.transport_receive("guest_client"),
    )


def _close_room_after_terminal(
    harness: SocketTransportHarness,
    room_id: str,
) -> dict[str, Any]:
    host_leave = harness.transport_send_ok("host_client", "leaveRoom")
    host_after_host_leave, guest_after_host_leave = _drain_live_mailboxes(harness)

    guest_leave = harness.transport_send_ok("guest_client", "leaveRoom")
    host_after_guest_leave, guest_after_guest_leave = _drain_live_mailboxes(harness)
    closed_snapshot = harness.snapshot_room(room_id)

    close_labels = [_frame_label(frame) for frame in host_after_guest_leave + guest_after_guest_leave]
    room_closed_seen = "roomClosed" in close_labels
    if not room_closed_seen:
        raise RuntimeError("The final leaveRoom did not emit roomClosed.")
    if closed_snapshot["room"]["roomState"] != "closed":
        raise RuntimeError(
            f"Closed room snapshot diverged: expected roomState='closed', got {closed_snapshot['room']['roomState']!r}."
        )

    return {
        "hostLeaveResponse": host_leave,
        "guestLeaveResponse": guest_leave,
        "hostAfterHostLeaveLabels": [_frame_label(frame) for frame in host_after_host_leave],
        "guestAfterHostLeaveLabels": [_frame_label(frame) for frame in guest_after_host_leave],
        "hostAfterGuestLeaveLabels": [_frame_label(frame) for frame in host_after_guest_leave],
        "guestAfterGuestLeaveLabels": [_frame_label(frame) for frame in guest_after_guest_leave],
        "roomClosedSeen": room_closed_seen,
        "closedSnapshot": closed_snapshot,
    }


def _probe_bootstrap_facade(harness: SocketTransportHarness) -> dict[str, Any]:
    create = harness.require_ok(
        "room_bootstrap_create",
        {
            "hostPlayerId": "p1",
            "deviceId": "probe_dev1",
            "roomType": "invite",
            "joinPolicy": "inviteCode",
        },
    )
    create_boundary = _assert_bootstrap_boundary(
        create.get("bootstrapBoundary"),
        stage="createRoom",
        current_action="room_bootstrap_create",
        future_public_route="POST /api/multiplayer/rooms",
    )
    room_id = create["room"]["roomId"]
    invite_code = create["room"].get("inviteCode")
    if not isinstance(invite_code, str):
        invite_code = room_id

    lookup = harness.require_ok(
        "room_bootstrap_lookup_invite",
        {
            "inviteCode": invite_code,
        },
    )
    lookup_boundary = _assert_bootstrap_boundary(
        lookup.get("bootstrapBoundary"),
        stage="lookupInvite",
        current_action="room_bootstrap_lookup_invite",
        future_public_route="GET /api/multiplayer/invites/{inviteCode}",
    )
    lookup_summary = lookup.get("roomSummary")
    if not isinstance(lookup_summary, dict):
        raise RuntimeError("room_bootstrap_lookup_invite roomSummary is missing.")
    if lookup_summary.get("roomId") != room_id:
        raise RuntimeError(
            f"room_bootstrap_lookup_invite roomSummary.roomId expected {room_id!r}, got {lookup_summary.get('roomId')!r}"
        )
    if lookup_summary.get("inviteCode") != invite_code:
        raise RuntimeError(
            "room_bootstrap_lookup_invite roomSummary.inviteCode diverged from the created room.\n"
            f"expected={invite_code!r} actual={lookup_summary.get('inviteCode')!r}"
        )
    if lookup_summary.get("canJoin") is not True:
        raise RuntimeError(f"room_bootstrap_lookup_invite roomSummary.canJoin expected True, got {lookup_summary.get('canJoin')!r}")
    if lookup_summary.get("memberCount") != 1 or lookup_summary.get("availableSeatCount") != 1:
        raise RuntimeError(
            "room_bootstrap_lookup_invite roomSummary expected memberCount=1 and availableSeatCount=1, got "
            f"{lookup_summary.get('memberCount')!r}/{lookup_summary.get('availableSeatCount')!r}"
        )

    join = harness.require_ok(
        "room_bootstrap_join",
        {
            "roomId": room_id,
            "playerId": "p2",
            "deviceId": "probe_dev2",
        },
    )
    join_boundary = _assert_bootstrap_boundary(
        join.get("bootstrapBoundary"),
        stage="joinRoom",
        current_action="room_bootstrap_join",
        future_public_route="POST /api/multiplayer/rooms/{roomId}/join",
    )

    harness.require_ok("room_set_ready", {"roomId": room_id, "playerId": "p1", "ready": True})
    harness.require_ok("room_set_ready", {"roomId": room_id, "playerId": "p2", "ready": True})

    shape = _assert_gap_recovery_shape(harness.require_ok("room_gap_recovery_shape"))

    game_id = f"{room_id}_bootstrap_facade_game_001"
    prepare = harness.require_ok(
        "room_bootstrap_prepare_game_start",
        {
            "roomId": room_id,
            "gameId": game_id,
        },
    )
    prepare_boundary = _assert_bootstrap_boundary(
        prepare.get("bootstrapBoundary"),
        stage="prepareGameStart",
        current_action="room_bootstrap_prepare_game_start",
        future_public_route="POST /api/multiplayer/rooms/{roomId}/bootstrap/game-start",
    )
    mutation = prepare.get("mutation")
    if not isinstance(mutation, dict):
        raise RuntimeError("room_bootstrap_prepare_game_start mutation payload is missing.")
    mutation_snapshot = mutation.get("snapshot")
    if not isinstance(mutation_snapshot, dict):
        raise RuntimeError("room_bootstrap_prepare_game_start mutation snapshot is missing.")
    room = mutation_snapshot.get("room")
    if not isinstance(room, dict):
        raise RuntimeError("room_bootstrap_prepare_game_start mutation room snapshot is missing.")
    if room.get("roomState") != "inGame":
        raise RuntimeError(
            f"room_bootstrap_prepare_game_start expected roomState='inGame', got {room.get('roomState')!r}"
        )
    if room.get("activeGameId") != game_id:
        raise RuntimeError(
            "room_bootstrap_prepare_game_start activeGameId diverged from requested gameId: "
            f"{room.get('activeGameId')!r} vs {game_id!r}"
        )

    paired_bootstrap = _assert_paired_bootstrap_by_player(
        prepare.get("bootstrapByPlayerId"),
        room_id=room_id,
        game_id=game_id,
    )

    return {
        "roomId": room_id,
        "gameId": game_id,
        "createBoundary": create_boundary,
        "lookupInviteBoundary": lookup_boundary,
        "lookupInviteSummary": lookup_summary,
        "joinBoundary": join_boundary,
        "prepareGameStartBoundary": prepare_boundary,
        "pairedBootstrap": paired_bootstrap,
        "gapRecoveryShape": shape,
    }


def _bootstrap_transport_room(
    harness: SocketTransportHarness,
    *,
    warm_engine: bool = False,
    rng_seed: int | None = None,
    hello_connection_aliases: dict[str, str] | None = None,
    probe_bootstrap_facade: bool = False,
) -> dict[str, Any]:
    if rng_seed is not None:
        harness.require_status("set_condition", "ok", {"rng_seed": rng_seed})
        harness.agent_log_lines.append(f"rngSeed={rng_seed}")

    if warm_engine:
        harness.ensure_engine_started()

    facade_probe = _probe_bootstrap_facade(harness) if probe_bootstrap_facade else None
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
    guest_hello_alias = (hello_connection_aliases or {}).get("guest_client", "control")
    harness.transport_send_ok(
        "guest_client",
        "hello",
        connection_alias=guest_hello_alias,
        connectionId="conn_guest_socket_001",
    )
    guest_hello = harness.transport_receive("guest_client")

    harness.transport_send_ok("host_client", "setReady", ready=True)
    host_after_host_ready = harness.transport_receive("host_client")
    guest_after_host_ready = harness.transport_receive("guest_client")

    harness.transport_send_ok("guest_client", "setReady", ready=True)
    host_after_guest_ready = harness.transport_receive("host_client")
    guest_after_guest_ready = harness.transport_receive("guest_client")

    start_data = harness.transport_send_ok(
        "host_client",
        "recordGameStartedAndPrepareBootstrap",
        gameId=game_id,
    )
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

    host_state_snapshot = _find_engine_event(
        host_live,
        event_name="stateSnapshot",
        reason="gameStarted",
        snapshot_only=True,
    )
    guest_state_snapshot = _find_engine_event(
        guest_live,
        event_name="stateSnapshot",
        reason="gameStarted",
        snapshot_only=True,
    )

    return {
        "bootstrap": bootstrap,
        "room_id": room_id,
        "game_id": game_id,
        "room_snapshot": room_snapshot,
        "start_data": start_data,
        "host_hello": host_hello,
        "guest_hello": guest_hello,
        "host_live": host_live,
        "guest_live": guest_live,
        "host_state_snapshot": host_state_snapshot,
        "guest_state_snapshot": guest_state_snapshot,
        "authoritative_state_version": _snapshot_state_version(host_state_snapshot),
        "authoritative_event_id": start_data.get("authoritativeEventId"),
        "facade_probe": facade_probe,
    }


def _run_mp001_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=False, probe_bootstrap_facade=True)
    room_snapshot = boot["room_snapshot"]
    room = room_snapshot["room"]
    transport_label = _transport_summary_label(harness.transport)
    facade_probe = boot["facade_probe"]
    if not isinstance(facade_probe, dict):
        raise RuntimeError("MP-001 bootstrap facade probe is missing.")

    if room["roomState"] != "inGame":
        raise RuntimeError(f"Expected roomState=inGame, got {room['roomState']!r}")
    if room["activeGameId"] != boot["game_id"]:
        raise RuntimeError(f"Expected activeGameId={boot['game_id']!r}, got {room['activeGameId']!r}")

    return {
        "status": ScenarioStatus.PASS,
        "summary": (
            f"Socket {transport_label} smoke validated room_bootstrap facade boundaries for create/join/prepareGameStart "
            "while preserving live paired gameStarted/stateSnapshot bootstrap."
        ),
        "roomId": boot["room_id"],
        "gameId": boot["game_id"],
        "players": _collect_players(room_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(boot["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(boot["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload=room_snapshot,
                snapshot_id=f"{boot['room_id']}_socket_room_snapshot",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=room["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode executed through GoStopCLI {harness.transport} room transport facade.",
                "Validated paired bootstrap delivery after recordGameStartedAndPrepareBootstrap.",
                "Validated room_bootstrap_create/join plus room_bootstrap_prepare_game_start facade boundaries on the same transport backend.",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
        "bootstrapBoundaryProbe": {
            "liveCreateBoundary": boot["bootstrap"]["bootstrapBoundary"]["create"],
            "liveLookupInviteBoundary": boot["bootstrap"]["bootstrapBoundary"]["lookupInvite"],
            "liveLookupInviteSummary": boot["bootstrap"]["lookupInviteSummary"],
            "liveJoinBoundary": boot["bootstrap"]["bootstrapBoundary"]["join"],
            "prepareLookupInviteBoundary": facade_probe["lookupInviteBoundary"],
            "prepareLookupInviteSummary": facade_probe["lookupInviteSummary"],
            "prepareGameStartBoundary": facade_probe["prepareGameStartBoundary"],
            "pairedBootstrap": facade_probe["pairedBootstrap"],
            "gapRecoveryShape": facade_probe["gapRecoveryShape"],
        },
        "paritySignature": {
            "scenarioId": "MP-001",
            "roomState": room["roomState"],
            "hostHelloTypes": [envelope["type"] for envelope in boot["host_hello"][:2]],
            "guestHelloTypes": [envelope["type"] for envelope in boot["guest_hello"][:2]],
            "hostBootstrapLabels": [_frame_label(frame) for frame in boot["host_live"]],
            "guestBootstrapLabels": [_frame_label(frame) for frame in boot["guest_live"]],
            "hostSnapshotReason": _snapshot_reason(boot["host_state_snapshot"]),
            "guestSnapshotReason": _snapshot_reason(boot["guest_state_snapshot"]),
            "authoritativeStateVersion": boot["authoritative_state_version"],
            "liveCreateBoundary": boot["bootstrap"]["bootstrapBoundary"]["create"],
            "liveLookupInviteBoundary": boot["bootstrap"]["bootstrapBoundary"]["lookupInvite"],
            "liveJoinBoundary": boot["bootstrap"]["bootstrapBoundary"]["join"],
            "prepareGameStartBoundary": facade_probe["prepareGameStartBoundary"],
        },
    }


def _run_mp002_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=True)
    room_id = boot["room_id"]
    room_snapshot = boot["room_snapshot"]
    transport_label = _transport_summary_label(harness.transport)

    terminal_response = harness.send(
        "room_transport_send",
        {
            "clientId": "host_client",
            "action": "recordMatchEndedAndFetchTerminalSummary",
            "roundIndex": 1,
            "quitReason": "voluntaryExit",
            "forfeitingPlayerId": "p1",
            "summaryStateVersion": boot["authoritative_state_version"],
            "lastEventId": boot["authoritative_event_id"],
        },
    )
    host_after_terminal = harness.transport_receive("host_client")
    guest_after_terminal = harness.transport_receive("guest_client")

    host_leave = harness.transport_send_ok("host_client", "leaveRoom")
    host_after_host_leave = harness.transport_receive("host_client")
    guest_after_host_leave = harness.transport_receive("guest_client")

    guest_leave = harness.transport_send_ok("guest_client", "leaveRoom")
    host_after_guest_leave = harness.transport_receive("host_client")
    guest_after_guest_leave = harness.transport_receive("guest_client")
    closed_snapshot = harness.snapshot_room(room_id)

    observed_terminal_labels = [_frame_label(frame) for frame in host_after_terminal]
    observed_close_labels = [_frame_label(frame) for frame in host_after_guest_leave + guest_after_guest_leave]
    terminal_error_code = terminal_response.get("errorCode")
    room_closed_seen = "roomClosed" in observed_close_labels

    blocking_reasons: list[str] = []
    status = ScenarioStatus.PASS
    summary = (
        f"Socket {transport_label} transport validated match end relay, terminal summary fan-out, and leaveRoom -> roomClosed completion."
    )

    if terminal_response.get("status") != "ok":
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            "room_transport_send(action=recordMatchEndedAndFetchTerminalSummary) still fails before "
            "roundEnded/matchEnded/terminalSummary fan-out."
        )
        blocking_reasons.append(
            f"transport errorCode={terminal_error_code} message={terminal_response.get('message')}"
        )
        summary = (
            "Socket TCP transport reached ended -> leaveRoom -> roomClosed lifecycle, but terminal summary fan-out "
            "is still blocked before roundEnded/matchEnded envelopes."
        )
    elif not any(_engine_event_name(frame) == "roundEnded" for frame in host_after_terminal):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Terminal socket path did not emit gameEvent(roundEnded).")
    elif not any(_engine_event_name(frame) == "matchEnded" for frame in host_after_terminal):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Terminal socket path did not emit gameEvent(matchEnded).")
    elif not any(frame.get("type") == "terminalSummary" for frame in host_after_terminal):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Terminal socket path did not emit terminalSummary envelope.")

    if not room_closed_seen:
        raise RuntimeError("leaveRoom lifecycle did not produce roomClosed on final departure.")

    return {
        "status": status,
        "summary": summary,
        "roomId": room_id,
        "gameId": boot["game_id"],
        "players": _collect_players(closed_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(boot["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(boot["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload=closed_snapshot,
                snapshot_id=f"{room_id}_socket_terminal",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=closed_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode used {harness.transport} room transport plus start_game warmup for terminal lifecycle coverage.",
                f"terminalResponseStatus={terminal_response.get('status')} terminalErrorCode={terminal_error_code}",
                f"hostLeaveAction={host_leave['transportAction']} guestLeaveAction={guest_leave['transportAction']}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": harness.transport,
        "terminalProbe": {
            "transportResponse": terminal_response,
            "observedTerminalLabels": observed_terminal_labels,
            "observedCloseLabels": observed_close_labels,
            "roomClosedSeen": room_closed_seen,
            "currentGap": "terminalSummary relay payload is still unavailable on the transport end-match path."
            if blocking_reasons
            else None,
        },
        "paritySignature": {
            "scenarioId": "MP-002",
            "roundEndedSeen": any(_engine_event_name(frame) == "roundEnded" for frame in host_after_terminal),
            "matchEndedSeen": any(_engine_event_name(frame) == "matchEnded" for frame in host_after_terminal),
            "terminalSummarySeen": any(frame.get("type") == "terminalSummary" for frame in host_after_terminal),
            "roomClosedSeen": room_closed_seen,
            "hostTerminalLabels": observed_terminal_labels,
            "hostCloseLabels": observed_close_labels,
            "closedRoomState": closed_snapshot["room"]["roomState"],
        },
    }


def _run_mp004_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=True)
    room_id = boot["room_id"]
    room_snapshot = boot["room_snapshot"]
    transport_label = _transport_summary_label(harness.transport)

    first_response = harness.transport_send_ok(
        "host_client",
        "quit",
        requestId="req_mp004_quit_001",
        actionId="act_mp004_quit_001",
        expectedStateVersion=boot["authoritative_state_version"],
        commandPayload={"reason": "voluntaryExit"},
    )
    host_first_frames = harness.transport_receive("host_client")
    guest_first_frames = harness.transport_receive("guest_client")
    room_after_first = harness.snapshot_room(room_id)

    replay_response = harness.transport_send_ok(
        "host_client",
        "quit",
        requestId="req_mp004_quit_002",
        actionId="act_mp004_quit_001",
        expectedStateVersion=boot["authoritative_state_version"],
        commandPayload={"reason": "voluntaryExit"},
    )
    host_replay_frames = harness.transport_receive("host_client")
    guest_replay_frames = harness.transport_receive("guest_client")
    room_after_replay = harness.snapshot_room(room_id)

    conflict_response = harness.transport_send_ok(
        "host_client",
        "quit",
        requestId="req_mp004_quit_003",
        actionId="act_mp004_quit_001",
        expectedStateVersion=boot["authoritative_state_version"],
        commandPayload={"reason": "disconnectTimeout"},
    )
    host_conflict_frames = harness.transport_receive("host_client")
    guest_conflict_frames = harness.transport_receive("guest_client")
    room_after_conflict = harness.snapshot_room(room_id)

    status = ScenarioStatus.PASS
    blocking_reasons: list[str] = []

    replay_disposition = replay_response.get("duplicateActionIdDisposition")
    conflict_disposition = conflict_response.get("duplicateActionIdDisposition")
    if replay_disposition != "exactReplay":
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            f"Duplicate replay did not report duplicateActionIdDisposition=exactReplay (got {replay_disposition!r})."
        )
    if conflict_disposition != "conflictReject":
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            f"Duplicate conflict did not report duplicateActionIdDisposition=conflictReject (got {conflict_disposition!r})."
        )
    if replay_response.get("authoritativeEventId") != first_response.get("authoritativeEventId"):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Duplicate replay did not reuse the original authoritativeEventId.")
    if guest_replay_frames:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Exact duplicate replay leaked envelopes onto the untouched guest mailbox.")
    if guest_conflict_frames:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Conflict duplicate leaked reject envelopes onto the untouched guest mailbox.")
    if [_frame_signature(frame) for frame in host_first_frames] != [_frame_signature(frame) for frame in host_replay_frames]:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Exact duplicate replay diverged from the original host mailbox delta.")
    if room_after_first["room"]["lastRoomSequence"] != room_after_replay["room"]["lastRoomSequence"]:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Exact duplicate replay advanced roomSequence.")
    if room_after_first["room"]["lastRoomSequence"] != room_after_conflict["room"]["lastRoomSequence"]:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Conflicting duplicate advanced roomSequence.")

    conflict_reason_code: str | None = None
    try:
        conflict_reject = _find_engine_event(host_conflict_frames, event_name="actionRejected")
        conflict_payload = conflict_reject.get("payload", {})
        if not isinstance(conflict_payload, dict):
            raise RuntimeError("Duplicate conflict reject payload is missing.")
        conflict_reason = conflict_payload.get("rejectReason", {})
        if not isinstance(conflict_reason, dict):
            raise RuntimeError("Duplicate conflict reject reason is missing.")
        conflict_reason_code = conflict_reason.get("code")
    except RuntimeError as error:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(str(error))
    else:
        if conflict_reason_code != "actionIdConflict":
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                f"Conflicting duplicate did not emit actionRejected(code=actionIdConflict); got {conflict_reason_code!r}."
            )

    summary = (
        f"Socket {transport_label} duplicate smoke validated exactReplay for identical actionId reuse and "
        "conflictReject for mismatched payload reuse."
    )
    if status is ScenarioStatus.BLOCKED:
        summary = (
            f"Socket {transport_label} duplicate smoke reached the live duplicate-action path, "
            "but duplicate replay/conflict semantics still diverged from the locked contract."
        )

    return {
        "status": status,
        "summary": summary,
        "roomId": room_id,
        "gameId": boot["game_id"],
        "players": _collect_players(room_after_conflict),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(boot["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(boot["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload=room_after_conflict,
                snapshot_id=f"{room_id}_socket_duplicate",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=room_after_conflict["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode used {harness.transport} room transport plus start_game warmup before duplicate actionId smoke.",
                f"firstAuthoritativeEventId={first_response.get('authoritativeEventId')}",
                f"replayDisposition={replay_response.get('duplicateActionIdDisposition')}",
                f"conflictDisposition={conflict_response.get('duplicateActionIdDisposition')}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": harness.transport,
        "duplicateProbe": {
            "originalResponse": first_response,
            "exactReplayResponse": replay_response,
            "conflictResponse": conflict_response,
            "hostOriginalFrames": [_frame_signature(frame) for frame in host_first_frames],
            "hostReplayFrames": [_frame_signature(frame) for frame in host_replay_frames],
            "hostConflictFrames": [_frame_signature(frame) for frame in host_conflict_frames],
            "guestOriginalLabels": [_frame_label(frame) for frame in guest_first_frames],
            "guestReplayLabels": [_frame_label(frame) for frame in guest_replay_frames],
            "guestConflictLabels": [_frame_label(frame) for frame in guest_conflict_frames],
        },
        "paritySignature": {
            "scenarioId": "MP-004",
            "exactReplayDisposition": replay_disposition,
            "conflictDisposition": conflict_disposition,
            "conflictRejectCode": conflict_reason_code,
            "roomSequenceStable": (
                room_after_first["room"]["lastRoomSequence"],
                room_after_replay["room"]["lastRoomSequence"],
                room_after_conflict["room"]["lastRoomSequence"],
            ),
        },
    }


def _run_mp007_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    harness.open_connection("guest_socket")
    boot = _bootstrap_transport_room(
        harness,
        warm_engine=True,
        hello_connection_aliases={"guest_client": "guest_socket"},
    )
    room_id = boot["room_id"]
    transport_label = _transport_summary_label(harness.transport)

    passive_close_at = datetime.now().astimezone()
    harness.close_connection("guest_socket")

    def drain_mailboxes() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        return (
            harness.transport_receive("host_client"),
            harness.transport_receive("guest_client"),
        )

    disconnected_snapshot: dict[str, Any] | None = None
    host_after_disconnect: list[dict[str, Any]] = []
    guest_after_disconnect: list[dict[str, Any]] = []
    disconnect_observed_at: datetime | None = None
    disconnect_deadline = time.monotonic() + 5.0
    while time.monotonic() < disconnect_deadline:
        time.sleep(0.1)
        host_frames, guest_frames = drain_mailboxes()
        host_after_disconnect.extend(host_frames)
        guest_after_disconnect.extend(guest_frames)
        candidate_snapshot = harness.snapshot_room(room_id)
        guest_member = next(
            (member for member in candidate_snapshot["room"]["members"] if member["playerId"] == "p2"),
            None,
        )
        if isinstance(guest_member, dict) and guest_member.get("presence") == "disconnected":
            disconnected_snapshot = candidate_snapshot
        if disconnect_observed_at is None and any(
            frame.get("type") == "roomEvent" and _room_event_name(frame) == "playerDisconnected"
            for frame in host_after_disconnect
        ):
            disconnect_observed_at = datetime.now().astimezone()
        if disconnected_snapshot is not None and disconnect_observed_at is not None:
            break
    if disconnected_snapshot is None:
        disconnected_snapshot = harness.snapshot_room(room_id)

    player_disconnected = next(
        (
            frame
            for frame in host_after_disconnect
            if frame.get("type") == "roomEvent" and _room_event_name(frame) == "playerDisconnected"
        ),
        None,
    )
    if disconnect_observed_at is None:
        disconnect_observed_at = datetime.now().astimezone()

    host_after_timeout: list[dict[str, Any]] = []
    guest_after_timeout: list[dict[str, Any]] = []
    action_accepted: dict[str, Any] | None = None
    round_ended: dict[str, Any] | None = None
    match_ended: dict[str, Any] | None = None
    timeout_forfeit: dict[str, Any] | None = None
    terminal_summary_frame: dict[str, Any] | None = None
    terminal_observed_at: datetime | None = None
    automatic_timeout_deadline = time.monotonic() + 40.0
    while time.monotonic() < automatic_timeout_deadline:
        time.sleep(0.5)
        host_frames, guest_frames = drain_mailboxes()
        host_after_timeout.extend(host_frames)
        guest_after_timeout.extend(guest_frames)
        if action_accepted is None:
            try:
                action_accepted = _find_engine_event(host_after_timeout, event_name="actionAccepted")
            except RuntimeError:
                action_accepted = None
        if round_ended is None:
            try:
                round_ended = _find_engine_event(host_after_timeout, event_name="roundEnded")
            except RuntimeError:
                round_ended = None
        if match_ended is None:
            try:
                match_ended = _find_engine_event(host_after_timeout, event_name="matchEnded")
            except RuntimeError:
                match_ended = None
        if timeout_forfeit is None:
            timeout_forfeit = next(
                (
                    frame
                    for frame in host_after_timeout
                    if frame.get("type") == "roomEvent"
                    and _room_event_name(frame) == "playerForfeited"
                    and _room_event_field(frame, "reason") == "disconnectTimeout"
                ),
                None,
            )
        if terminal_summary_frame is None:
            terminal_summary_frame = next(
                (frame for frame in host_after_timeout if frame.get("type") == "terminalSummary"),
                None,
            )
        if all(
            item is not None
            for item in (action_accepted, round_ended, match_ended, timeout_forfeit, terminal_summary_frame)
        ):
            terminal_observed_at = datetime.now().astimezone()
            break

    timeout_snapshot = harness.snapshot_room(room_id)

    harness.connect_transport_client(
        "guest_resume",
        room_id,
        harness.transport_clients["guest_client"]["sessionId"],
        "p2",
        "dev2",
        harness.transport_clients["guest_client"]["resumeToken"],
    )
    resume_attempt = harness.transport_send_error(
        "guest_resume",
        "hello",
        expected_code="resumeExpired",
        connectionId="conn_guest_socket_003",
        lastSeen={"roomSequence": timeout_snapshot["room"]["lastRoomSequence"]},
    )
    resume_probe_frames = harness.transport_receive("guest_resume")

    host_after_close: list[dict[str, Any]] = []
    guest_after_close: list[dict[str, Any]] = []
    room_closed_frame: dict[str, Any] | None = None
    room_closed_observed_at: datetime | None = None
    closed_snapshot = timeout_snapshot
    automatic_close_deadline = time.monotonic() + 70.0
    while time.monotonic() < automatic_close_deadline:
        time.sleep(0.5)
        host_frames, guest_frames = drain_mailboxes()
        host_after_close.extend(host_frames)
        guest_after_close.extend(guest_frames)
        closed_snapshot = harness.snapshot_room(room_id)
        if room_closed_frame is None:
            room_closed_frame = next(
                (
                    frame
                    for frame in host_after_close
                    if frame.get("type") == "roomEvent" and _room_event_name(frame) == "roomClosed"
                ),
                None,
            )
        if room_closed_frame is not None and closed_snapshot["room"]["roomState"] == "closed":
            room_closed_observed_at = datetime.now().astimezone()
            break

    host_timeout_labels = [_frame_label(frame) for frame in host_after_timeout]
    guest_timeout_labels = [_frame_label(frame) for frame in guest_after_timeout]
    host_disconnect_labels = [_frame_label(frame) for frame in host_after_disconnect]
    guest_disconnect_labels = [_frame_label(frame) for frame in guest_after_disconnect]
    host_close_labels = [_frame_label(frame) for frame in host_after_close]
    guest_close_labels = [_frame_label(frame) for frame in guest_after_close]
    resume_probe_labels = [_frame_label(frame) for frame in resume_probe_frames]

    status = ScenarioStatus.PASS
    blocking_reasons: list[str] = []
    if timeout_forfeit is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Timeout path did not emit roomEvent(playerForfeited reason=disconnectTimeout).")
    if player_disconnected is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Passive close did not emit roomEvent(playerDisconnected).")
    if action_accepted is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Automatic timeout path did not emit gameEvent(actionAccepted).")
    if round_ended is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Automatic timeout path did not emit gameEvent(roundEnded).")
    if match_ended is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Automatic timeout path did not emit gameEvent(matchEnded).")
    if not _contains_label_sequence(host_timeout_labels, ["actionAccepted", "roundEnded", "matchEnded", "terminalSummary"]):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            "Automatic timeout host ordering diverged: expected actionAccepted -> roundEnded -> matchEnded -> terminalSummary."
        )
    player_forfeited_index = _label_index(host_timeout_labels, "playerForfeited")
    room_state_changed_index = _label_index(host_timeout_labels, "roomStateChanged")
    terminal_summary_index = _label_index(host_timeout_labels, "terminalSummary")
    if player_forfeited_index is None or room_state_changed_index is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            "Automatic timeout host timeline is missing roomEvent(playerForfeited) or roomEvent(roomStateChanged)."
        )
    elif terminal_summary_index is not None and (
        player_forfeited_index > terminal_summary_index or room_state_changed_index > terminal_summary_index
    ):
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(
            "Automatic timeout roomEvent(playerForfeited/roomStateChanged) must precede terminalSummary on the host timeline."
        )

    terminal_payload: dict[str, Any] | None = None
    if terminal_summary_frame is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Timeout path did not emit terminalSummary.")
    else:
        terminal_payload = _terminal_summary_payload(terminal_summary_frame)
        terminal_match_ended = terminal_payload.get("matchEnded", {})
        if not isinstance(terminal_match_ended, dict):
            terminal_match_ended = {}
        if terminal_match_ended.get("endReason") != "disconnectTimeout":
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                "terminalSummary matchEnded.endReason diverged: expected 'disconnectTimeout', "
                f"got {terminal_match_ended.get('endReason')!r}."
            )
        if not isinstance(terminal_match_ended.get("forfeitingPlayerId"), str):
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                "terminalSummary matchEnded.forfeitingPlayerId should carry the authoritative forfeiting playerId."
            )
        if terminal_match_ended.get("settlementSummary") is not None:
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append("disconnectTimeout terminalSummary should keep settlementSummary=null.")

    if action_accepted is not None:
        accepted_payload = action_accepted.get("payload", {})
        if not isinstance(accepted_payload, dict) or accepted_payload.get("commandName") != "quit":
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append("Timeout path did not relay actionAccepted(commandName=quit).")

    match_payload: dict[str, Any] = {}
    if match_ended is not None:
        payload = match_ended.get("payload", {})
        if isinstance(payload, dict):
            match_payload = payload
        if match_payload.get("endReason") != "disconnectTimeout":
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                f"matchEnded endReason diverged: expected 'disconnectTimeout', got {match_payload.get('endReason')!r}."
            )
        if not isinstance(match_payload.get("forfeitingPlayerId"), str):
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                "matchEnded forfeitingPlayerId should carry the authoritative forfeiting playerId."
            )
        if match_payload.get("settlementSummary") is not None:
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append("disconnectTimeout matchEnded should keep settlementSummary=null.")
        if (
            terminal_payload is not None
            and isinstance(terminal_payload.get("matchEnded"), dict)
            and terminal_payload["matchEnded"].get("forfeitingPlayerId") != match_payload.get("forfeitingPlayerId")
        ):
            status = ScenarioStatus.BLOCKED
            blocking_reasons.append(
                "matchEnded forfeitingPlayerId diverged from terminalSummary.matchEnded.forfeitingPlayerId."
            )

    if room_closed_frame is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Automatic result retention did not emit roomEvent(roomClosed).")

    closed_room_state = closed_snapshot["room"]["roomState"]
    if closed_room_state != "closed":
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(f"Room state after timeout close diverged: expected 'closed', got {closed_room_state!r}.")

    summary = (
        f"Socket {transport_label} automatic passive-close timeout smoke validated timer-driven disconnectTimeout "
        "forfeit relay, terminalSummary fan-out, and later roomClosed completion."
    )
    if status is ScenarioStatus.BLOCKED:
        summary = (
            f"Socket {transport_label} automatic passive-close timeout smoke reached disconnectTimeout expiry, "
            "but timer-driven terminal or close ordering still diverged from the locked contract."
        )

    return {
        "status": status,
        "summary": summary,
        "roomId": room_id,
        "gameId": boot["game_id"],
        "players": _collect_players(closed_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(boot["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(boot["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload=closed_snapshot,
                snapshot_id=f"{room_id}_socket_timeout",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=closed_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode used {harness.transport} room transport passive close + automatic expiry timer for timeout coverage.",
                f"passiveCloseAt={passive_close_at.isoformat(timespec='seconds')} disconnectObservedAt={disconnect_observed_at.isoformat(timespec='seconds') if disconnect_observed_at else 'n/a'}",
                f"resumeExpiredError={resume_attempt['errorCode']}",
                f"terminalObservedAt={terminal_observed_at.isoformat(timespec='seconds') if terminal_observed_at else 'n/a'} roomClosedObservedAt={room_closed_observed_at.isoformat(timespec='seconds') if room_closed_observed_at else 'n/a'}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": harness.transport,
        "timeoutProbe": {
            "policy": "disconnectTimeoutForfeit",
            "disconnectMode": "passiveClose",
            "progressionMode": "automaticExpirySweep",
            "manualReapUsed": False,
            "disconnectResponse": None,
            "resumeExpiredResponse": resume_attempt,
            "passiveCloseAt": passive_close_at.isoformat(timespec="seconds"),
            "disconnectObservedAt": disconnect_observed_at.isoformat(timespec="seconds") if disconnect_observed_at else None,
            "terminalObservedAt": terminal_observed_at.isoformat(timespec="seconds") if terminal_observed_at else None,
            "roomClosedObservedAt": room_closed_observed_at.isoformat(timespec="seconds") if room_closed_observed_at else None,
            "hostDisconnectLabels": host_disconnect_labels,
            "guestDisconnectLabels": guest_disconnect_labels,
            "hostTimeoutLabels": host_timeout_labels,
            "guestTimeoutLabels": guest_timeout_labels,
            "resumeProbeLabels": resume_probe_labels,
            "hostCloseLabels": host_close_labels,
            "guestCloseLabels": guest_close_labels,
            "closedRoomState": closed_room_state,
            "timeoutSnapshotRoomSequence": timeout_snapshot["room"]["lastRoomSequence"],
            "terminalSummaryPayload": terminal_payload,
        },
        "paritySignature": {
            "scenarioId": "MP-007",
            "disconnectMode": "passiveClose",
            "progressionMode": "automaticExpirySweep",
            "manualReapUsed": False,
            "playerDisconnectedSeen": player_disconnected is not None,
            "resumeExpiredError": resume_attempt["errorCode"],
            "actionAcceptedSeen": action_accepted is not None,
            "roundEndedSeen": round_ended is not None,
            "matchEndedSeen": match_ended is not None,
            "terminalSummarySeen": terminal_summary_frame is not None,
            "playerForfeitedSeen": timeout_forfeit is not None,
            "roomClosedSeen": room_closed_frame is not None,
            "matchEndedReason": match_payload.get("endReason"),
            "forfeitingPlayerIdPresent": isinstance(match_payload.get("forfeitingPlayerId"), str),
            "terminalSummaryMatches": (
                terminal_payload.get("matchEnded", {}).get("forfeitingPlayerId") == match_payload.get("forfeitingPlayerId")
                if isinstance(terminal_payload, dict) and isinstance(terminal_payload.get("matchEnded"), dict)
                else False
            ),
            "terminalOrderingStable": _contains_label_sequence(
                host_timeout_labels,
                ["actionAccepted", "roundEnded", "matchEnded", "terminalSummary"],
            ),
            "closedRoomState": closed_room_state,
        },
    }


def _run_mp013_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    trace_id = "trace_mp013_socket"
    room_id = "room_mp013_socket"
    game_id = "room_mp013_socket_game"
    turn_id = "turn_mp013_socket_001"
    condition_payload = {
        "rng_seed": 42,
        "mock_gameState": "askingShake",
        "currentTurnIndex": 0,
        "mock_pending_shake_month": 6,
        "mock_hand": [
            {"id": "mp013_hand_1", "month": 6, "type": "bright", "imageIndex": 0},
            {"id": "mp013_hand_2", "month": 6, "type": "animal", "imageIndex": 1},
            {"id": "mp013_hand_3", "month": 6, "type": "junk", "imageIndex": 2},
            {"id": "mp013_hand_4", "month": 1, "type": "junk", "imageIndex": 0},
        ],
    }
    set_condition_response = harness.require_status("set_condition", "ok", condition_payload)

    base_projection_request = {
        "traceId": trace_id,
        "roomId": room_id,
        "gameId": game_id,
        "turnId": turn_id,
        "stateVersion": 21,
        "reason": "localPreview",
        "scope": "player",
    }
    actor_projection_response = harness.require_status(
        "get_multiplayer_projection",
        "ok",
        {**base_projection_request, "viewerIndex": 0},
    )
    peer_projection_response = harness.require_status(
        "get_multiplayer_projection",
        "ok",
        {**base_projection_request, "viewerIndex": 1},
    )
    authority_projection_response = harness.require_status(
        "get_multiplayer_projection",
        "ok",
        {
            **base_projection_request,
            "viewerIndex": 0,
            "scope": "authority",
        },
    )

    actor_snapshot = actor_projection_response.get("snapshot")
    peer_snapshot = peer_projection_response.get("snapshot")
    authority_snapshot = authority_projection_response.get("snapshot")
    if not isinstance(actor_snapshot, dict) or not isinstance(peer_snapshot, dict) or not isinstance(authority_snapshot, dict):
        raise RuntimeError("MP-013 projection payload is missing a snapshot.")

    actor_state = _projection_state(actor_snapshot)
    peer_state = _projection_state(peer_snapshot)
    actor_choice = actor_state.get("pendingChoice")
    peer_choice = peer_state.get("pendingChoice")
    if not isinstance(actor_choice, dict) or not isinstance(peer_choice, dict):
        raise RuntimeError("MP-013 pendingChoice is missing from actor or peer projection.")

    actor_options = actor_choice.get("options")
    peer_options = peer_choice.get("options")
    if not isinstance(actor_options, list) or not isinstance(peer_options, list):
        raise RuntimeError("MP-013 choice options are missing.")
    if actor_choice.get("choiceKind") != "shake" or peer_choice.get("choiceKind") != "shake":
        raise RuntimeError("MP-013 did not reach a shake choice projection.")
    if actor_choice.get("visibility") != "actorOnly" or peer_choice.get("visibility") != "actorOnly":
        raise RuntimeError("MP-013 visibility diverged from actorOnly.")
    if actor_choice.get("choiceId") != peer_choice.get("choiceId"):
        raise RuntimeError("MP-013 actor/peer choiceId diverged.")

    actor_cards = sum(
        len(option.get("cards", []))
        for option in actor_options
        if isinstance(option, dict) and isinstance(option.get("cards"), list)
    )
    peer_cards = sum(
        len(option.get("cards", []))
        for option in peer_options
        if isinstance(option, dict) and isinstance(option.get("cards"), list)
    )
    if actor_cards == 0:
        raise RuntimeError("MP-013 actor projection is missing shake cards.")
    if peer_cards != 0:
        raise RuntimeError("MP-013 peer projection leaked shake cards.")
    if not any(isinstance(option.get("metadata"), dict) for option in actor_options if isinstance(option, dict)):
        raise RuntimeError("MP-013 actor projection is missing shake metadata.")
    if any(option.get("metadata") is not None for option in peer_options if isinstance(option, dict)):
        raise RuntimeError("MP-013 peer projection leaked shake metadata.")

    actor_viewer = actor_state.get("viewerPlayerId")
    peer_viewer = peer_state.get("viewerPlayerId")
    transport_label = _transport_summary_label(harness.transport)

    return {
        "status": ScenarioStatus.PASS,
        "summary": f"Socket {transport_label} projection smoke validated actorOnly shake choice redaction across actor and peer views.",
        "traceId": trace_id,
        "roomId": actor_state.get("roomId"),
        "gameId": actor_state.get("gameId"),
        "players": _collect_projection_players(actor_snapshot),
        "commands": list(harness.command_rows),
        "frames": [
            {
                "type": "projectionSnapshot",
                "transport": "tcp-direct",
                "label": "actorProjection",
                "viewerRole": "actor",
                "roomId": actor_state.get("roomId"),
                "gameId": actor_state.get("gameId"),
                "payload": actor_snapshot,
            },
            {
                "type": "projectionSnapshot",
                "transport": "tcp-direct",
                "label": "peerProjection",
                "viewerRole": "peer",
                "roomId": peer_state.get("roomId"),
                "gameId": peer_state.get("gameId"),
                "payload": peer_snapshot,
            },
            {
                "type": "projectionSnapshot",
                "transport": "tcp-direct",
                "label": "authorityProjection",
                "viewerRole": "authority",
                "roomId": _projection_state(authority_snapshot).get("roomId"),
                "gameId": _projection_state(authority_snapshot).get("gameId"),
                "payload": authority_snapshot,
            },
        ],
        "snapshots": {
            "player_a_initial": _projection_snapshot_record(
                actor_snapshot,
                source="initial",
                scope="player",
                player_id=actor_viewer if isinstance(actor_viewer, str) else None,
            ),
            "player_b_initial": _projection_snapshot_record(
                peer_snapshot,
                source="initial",
                scope="player",
                player_id=peer_viewer if isinstance(peer_viewer, str) else None,
            ),
            "latest_server": _projection_snapshot_record(
                authority_snapshot,
                source="terminal",
                scope="authority",
                player_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode used the {harness.transport} direct projection path for the shake privacy regression.",
                f"actorChoiceId={actor_choice.get('choiceId')} peerChoiceId={peer_choice.get('choiceId')}",
                f"actorCardCount={actor_cards} peerCardCount={peer_cards}",
                f"setConditionStatus={set_condition_response.get('status')}",
                *harness.agent_log_lines,
            ],
            "room": [
                "No room envelopes were required for MP-013.",
                "The regression uses TCP-served get_multiplayer_projection requests so the same actor/peer assertions can be reused when websocket snapshot delivery lands.",
            ],
            "engine": [
                f"actorPendingChoiceVisibility={actor_choice.get('visibility')}",
                f"peerPendingChoiceVisibility={peer_choice.get('visibility')}",
                f"authoritySnapshotReason={_projection_snapshot_reason(authority_snapshot)}",
            ],
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
        "paritySignature": {
            "scenarioId": "MP-013",
            "choiceIdsMatch": actor_choice.get("choiceId") == peer_choice.get("choiceId"),
            "actorVisibility": actor_choice.get("visibility"),
            "peerVisibility": peer_choice.get("visibility"),
            "actorCardCount": actor_cards,
            "peerCardCount": peer_cards,
        },
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
    transport_label = _transport_summary_label(harness.transport)
    stale_heartbeat_code_probe = {
        "probeName": "debugConnectHeartbeatEnvelope",
        "adapterPath": "MultiplayerWebSocketCommandNetworkingAdapter",
        "transportBackend": harness.transport,
        "commandSurface": "room_transport_send(action=ack)",
        "cliIngressBaseline": {
            "commandSurface": "room_heartbeat",
            "disconnectedErrorCode": "invalidResumeState",
            "staleErrorCode": "staleConnectionId",
        },
        "rawCommandResponses": {
            "disconnected": disconnected_error,
            "stale": stale_error,
            "accepted": accepted_ack,
        },
        "commandEnvelopeParity": {
            "disconnectedMatchesCliIngress": disconnected_error["errorCode"] == "invalidResumeState",
            "staleMatchesCliIngress": stale_error["errorCode"] == "staleConnectionId",
        },
    }

    return {
        "status": ScenarioStatus.PASS,
        "summary": f"Socket {transport_label} transport preserved stale heartbeat reject parity through room_transport_send(action=ack).",
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
                f"Socket mode exercised stale/disconnected heartbeat parity through the {harness.transport} transport server.",
                f"disconnectedError={disconnected_error['errorCode']} staleError={stale_error['errorCode']}",
                f"acceptedAction={accepted_ack['transportAction']}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
        "heartbeatProbe": {
            "policy": "explicitReject",
            "disconnectedErrorCode": disconnected_error["errorCode"],
            "staleErrorCode": stale_error["errorCode"],
            "acceptedAction": accepted_ack["transportAction"],
            "guestResumeLabels": [_frame_label(frame) for frame in guest_resume_envelopes],
            "currentConnectionId": guest_member.get("connectedConnectionId"),
            "lastRoomSequence": room["lastRoomSequence"],
        },
        "staleHeartbeatCodeProbe": stale_heartbeat_code_probe,
        "paritySignature": {
            "scenarioId": "MP-014",
            "heartbeatPolicy": "explicitReject",
            "disconnectedError": disconnected_error["errorCode"],
            "staleError": stale_error["errorCode"],
            "acceptedAction": accepted_ack["transportAction"],
            "connectedConnectionId": guest_member.get("connectedConnectionId"),
            "lastRoomSequence": room["lastRoomSequence"],
        },
    }


def _run_mp008_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=True)
    room_id = boot["room_id"]
    game_id = boot["game_id"]
    room_snapshot = boot["room_snapshot"]
    gap_recovery_shape = _assert_gap_recovery_shape(harness.require_ok("room_gap_recovery_shape"))
    hook = harness.require_ok(
        "room_set_mp008_hook",
        {
            "targetSessionId": boot["bootstrap"]["host_session_id"],
            "overriddenExpectedStateVersion": 999,
        },
    )["hook"]
    hook_snapshot = harness.require_ok("room_get_mp008_hook")["hook"]
    if hook_snapshot != hook:
        raise RuntimeError("room_get_mp008_hook diverged from the hook returned by room_set_mp008_hook.")

    send_result = harness.transport_send_ok(
        "host_client",
        "quit",
        requestId="req_mp008_socket_quit_001",
        actionId="act_mp008_socket_quit_001",
        expectedStateVersion=boot["authoritative_state_version"],
        commandPayload={"reason": "voluntaryExit"},
    )
    host_resync_frames = harness.transport_receive("host_client")
    guest_resync_frames = harness.transport_receive("guest_client")
    harness.require_ok("room_clear_mp008_hook")
    latest_snapshot = harness.snapshot_room(room_id)

    rejected = _find_engine_event(host_resync_frames, event_name="actionRejected")
    recovery = _find_engine_event(
        host_resync_frames,
        event_name="stateSnapshot",
        snapshot_only=True,
    )
    reject_payload = rejected.get("payload", {})
    if not isinstance(reject_payload, dict):
        raise RuntimeError("MP-008 reject payload is missing.")
    reject_reason = reject_payload.get("rejectReason", {})
    if not isinstance(reject_reason, dict):
        raise RuntimeError("MP-008 reject reason is missing.")
    if reject_reason.get("code") != "staleStateVersion":
        raise RuntimeError(f"Expected staleStateVersion reject, got {reject_reason.get('code')!r}")

    reject_details = reject_reason.get("details", {})
    if not isinstance(reject_details, dict):
        reject_details = {}
    resync_details = reject_details.get("resync", {})
    if not isinstance(resync_details, dict):
        resync_details = {}
    recovery_payload = _snapshot_payload(recovery)
    recovery_state = _snapshot_state(recovery)
    recovery_reason = _snapshot_reason(recovery)
    status = ScenarioStatus.PASS
    summary = (
        "Socket TCP gameplay smoke validated staleStateVersion reject/stateSnapshot(reason=resync) "
        "and triggerGapRecovery -> gapRecoveryHint -> stateSnapshot(reason=gapDetected) on live transport."
    )
    blocking_reasons: list[str] = []
    if recovery_reason != "resync":
        status = ScenarioStatus.BLOCKED
        summary = (
            "Socket TCP gameplay smoke reached live staleStateVersion reject and recovery snapshot delivery, "
            "but the recovery snapshot reason is still not locked to resync."
        )
        blocking_reasons.append(
            f"Recovery snapshot reason diverged: expected 'resync', got {recovery_reason!r}."
        )

    gap_client_state_version = max(0, boot["authoritative_state_version"] - 1)
    gap_send_result = harness.transport_send_ok(
        "host_client",
        "triggerGapRecovery",
        requestId="req_mp008_socket_gap_001",
        actionId="act_mp008_socket_gap_001",
        expectedStateVersion=gap_client_state_version,
        lastEventId=boot["authoritative_event_id"],
        lastSeen={
            "roomSequence": room_snapshot["room"]["lastRoomSequence"],
            "gameEventId": boot["authoritative_event_id"],
            "stateVersion": gap_client_state_version,
        },
    )
    host_gap_frames = harness.transport_receive("host_client")
    guest_gap_frames = harness.transport_receive("guest_client")
    host_gap_labels = [_frame_label(frame) for frame in host_gap_frames]
    if not _contains_label_sequence(host_gap_labels, ["gapRecoveryHint", "stateSnapshot"]):
        raise RuntimeError(
            "MP-008 live gap recovery ordering diverged. "
            f"expected gapRecoveryHint -> stateSnapshot, got labels={host_gap_labels!r}"
        )
    gap_hint_envelope = next(
        (frame for frame in host_gap_frames if frame.get("type") == "gapRecoveryHint"),
        None,
    )
    if not isinstance(gap_hint_envelope, dict):
        raise RuntimeError("MP-008 live gap recovery did not emit a gapRecoveryHint envelope.")
    gap_hint = _assert_gap_recovery_hint(
        gap_hint_envelope.get("payload"),
        room_id=room_id,
        session_id=boot["bootstrap"]["host_session_id"],
        target_client_id="host_client",
        last_acked_game_event_id=boot["authoritative_event_id"],
        last_seen_state_version=gap_client_state_version,
    )
    returned_gap_hint = _assert_gap_recovery_hint(
        gap_send_result.get("gapRecoveryHint"),
        room_id=room_id,
        session_id=boot["bootstrap"]["host_session_id"],
        target_client_id="host_client",
        last_acked_game_event_id=boot["authoritative_event_id"],
        last_seen_state_version=gap_client_state_version,
    )
    if returned_gap_hint != gap_hint:
        raise RuntimeError(
            "MP-008 live gap recovery response payload diverged from the queued gapRecoveryHint envelope.\n"
            f"response={json.dumps(returned_gap_hint, ensure_ascii=False, sort_keys=True)}\n"
            f"envelope={json.dumps(gap_hint, ensure_ascii=False, sort_keys=True)}"
        )
    gap_snapshot = _find_engine_event(
        host_gap_frames,
        event_name="stateSnapshot",
        reason="gapDetected",
        snapshot_only=True,
    )
    if gap_snapshot.get("eventId") != gap_hint["authoritativeEventId"]:
        raise RuntimeError(
            "MP-008 live gap recovery eventId diverged from gapRecoveryHint.authoritativeEventId.\n"
            f"expected={gap_hint['authoritativeEventId']!r} actual={gap_snapshot.get('eventId')!r}"
        )
    gap_snapshot_state = _snapshot_state(gap_snapshot)
    gap_snapshot_reason = _snapshot_reason(gap_snapshot)
    gap_snapshot_state_version = _snapshot_state_version(gap_snapshot)
    if gap_snapshot_state_version != gap_hint["authoritativeStateVersion"]:
        raise RuntimeError(
            "MP-008 live gap recovery snapshot stateVersion diverged from gapRecoveryHint.authoritativeStateVersion.\n"
            f"expected={gap_hint['authoritativeStateVersion']!r} actual={gap_snapshot_state_version!r}"
        )
    guest_gap_labels = [_frame_label(frame) for frame in guest_gap_frames]
    if any(label == "gapRecoveryHint" for label in guest_gap_labels):
        raise RuntimeError(f"MP-008 live gap recovery leaked gapRecoveryHint to guest frames: {guest_gap_labels!r}")

    authoritative_state_version = reject_details.get("authoritativeStateVersion")
    authoritative_event_id = reject_details.get("authoritativeEventId")
    expected_state_version = reject_details.get("expectedStateVersion")
    client_state_version = reject_details.get("clientStateVersion")
    normalized_mode = _normalize_injected_mismatch_mode(reject_details.get("injectedMismatchMode"))
    transport_label = _transport_summary_label(harness.transport)

    return {
        "status": status,
        "summary": summary.replace("Socket TCP", f"Socket {transport_label}"),
        "roomId": room_id,
        "gameId": game_id,
        "players": _collect_players(room_snapshot),
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(boot["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(boot["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload=latest_snapshot,
                snapshot_id=f"{room_id}_socket_resync",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=latest_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode used {harness.transport} room transport plus start_game warmup before live stale-version gameplay smoke.",
                "MP-008 uses the live quit command so the reject/resync pair is deterministic even while playCard still depends on room/authority playerId mapping.",
                f"authoritativeStateVersion={authoritative_state_version} authoritativeEventId={authoritative_event_id}",
                f"guestReceiveCountDuringResync={len(guest_resync_frames)}",
                f"gapRecoveryAuthoritativeEventId={gap_hint['authoritativeEventId']} "
                f"gapRecoveryAuthoritativeStateVersion={gap_hint['authoritativeStateVersion']}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": harness.transport,
        "gapRecoveryShape": gap_recovery_shape,
        "injectionPlan": {
            "executionReadiness": "live-socket-gameplay-and-gap-hook",
            "injectedMismatchMode": normalized_mode or "staleExpectedStateVersion",
            "clientStateVersion": client_state_version,
            "expectedStateVersion": expected_state_version,
            "authoritativeStateVersion": authoritative_state_version,
            "authoritativeEventId": authoritative_event_id,
            "recoverySnapshotReason": recovery_reason,
            "recoverySnapshotId": recovery_payload.get("snapshotId"),
            "targetSessionId": hook["targetSessionId"],
            "commandName": "quit",
            "debugWarmupActions": ["start_game"],
            "recoveryShouldLockInput": resync_details.get("shouldLockInput"),
            "gapRecoveryShapeAction": "room_gap_recovery_shape",
            "gapRecoveryHintMinimumFields": gap_recovery_shape["artifact"]["minimumFields"],
            "expectedGapRecoverySnapshotReason": gap_recovery_shape["recoveryEnvelope"]["reason"],
            "liveGapRecoveryTransportAction": gap_recovery_shape["liveHook"]["transportAction"],
            "liveGapRecoveryEnvelopeType": gap_recovery_shape["liveHook"]["recoveryEnvelopeType"],
            "gapTriggerClientStateVersion": gap_client_state_version,
            "gapTriggerLastDeliveredEventId": boot["authoritative_event_id"],
            "gapTriggeredAuthoritativeStateVersion": gap_hint["authoritativeStateVersion"],
            "gapTriggeredAuthoritativeEventId": gap_hint["authoritativeEventId"],
            "gapRecoverySnapshotReason": gap_snapshot_reason,
            "gapRecoverySnapshotId": _snapshot_id(gap_snapshot),
        },
        "mismatchFrames": [
            {
                "kind": "live_socket_reject",
                "scenarioId": "MP-008",
                "status": status.value,
                "commandName": "quit",
                "actionId": reject_payload.get("actionId"),
                "requestId": reject_payload.get("requestId"),
                "rejectCode": reject_reason.get("code"),
                "injectedMismatchMode": normalized_mode or "staleExpectedStateVersion",
                "clientStateVersion": client_state_version,
                "expectedStateVersion": expected_state_version,
                "authoritativeStateVersion": authoritative_state_version,
                "authoritativeEventId": authoritative_event_id,
                "recoverySnapshotReason": recovery_reason,
                "recoverySnapshotId": recovery_payload.get("snapshotId"),
                "sendAuthoritativeEventId": send_result.get("authoritativeEventId"),
                "expectedGapRecoverySnapshotReason": gap_recovery_shape["recoveryEnvelope"]["reason"],
            },
            {
                "kind": "live_socket_resync_snapshot",
                "scenarioId": "MP-008",
                "status": status.value,
                "commandName": "quit",
                "snapshotId": recovery_payload.get("snapshotId"),
                "stateVersion": _snapshot_state_version(recovery),
                "stateHash": _stable_hash(recovery_state),
                "viewerPlayerId": recovery_state.get("viewerPlayerId"),
                "currentPlayerId": recovery_state.get("currentPlayerId"),
                "gapRecoveryHintMinimumFields": gap_recovery_shape["artifact"]["minimumFields"],
            },
            {
                "kind": "live_socket_gap_hint",
                "scenarioId": "MP-008",
                "status": status.value,
                "commandName": "triggerGapRecovery",
                "actionId": "act_mp008_socket_gap_001",
                "requestId": "req_mp008_socket_gap_001",
                "artifactVersion": gap_hint["artifactVersion"],
                "transportFlagName": gap_hint["transportFlag"]["name"],
                "transportFlagValue": gap_hint["transportFlag"]["value"],
                "targetClientId": gap_hint["targetClientId"],
                "lastAckedGameEventId": gap_hint["lastAckedGameEventId"],
                "lastSeenStateVersion": gap_hint["lastSeenStateVersion"],
                "authoritativeEventId": gap_hint["authoritativeEventId"],
                "authoritativeStateVersion": gap_hint["authoritativeStateVersion"],
                "snapshotReason": gap_hint["snapshotReason"],
            },
            {
                "kind": "live_socket_gap_snapshot",
                "scenarioId": "MP-008",
                "status": status.value,
                "commandName": "triggerGapRecovery",
                "snapshotId": _snapshot_id(gap_snapshot),
                "eventId": gap_snapshot.get("eventId"),
                "stateVersion": gap_snapshot_state_version,
                "stateHash": _stable_hash(gap_snapshot_state),
                "snapshotReason": gap_snapshot_reason,
                "viewerPlayerId": gap_snapshot_state.get("viewerPlayerId"),
            },
        ],
        "gapRecoveryProbe": {
            "transportAction": "triggerGapRecovery",
            "liveHook": gap_recovery_shape["liveHook"],
            "gapHint": gap_hint,
            "snapshotEventId": gap_snapshot.get("eventId"),
            "snapshotId": _snapshot_id(gap_snapshot),
            "snapshotReason": gap_snapshot_reason,
            "snapshotStateVersion": gap_snapshot_state_version,
            "hostFrameLabels": host_gap_labels,
            "guestFrameLabels": guest_gap_labels,
            "queuedEnvelopeCount": gap_send_result.get("queuedEnvelopeCount"),
        },
        "resyncProbe": {
            "sendResult": send_result,
            "guestFrameLabels": [_frame_label(frame) for frame in guest_resync_frames],
            "playCardCurrentGap": "room playerId does not yet map to authority playerId in live projection, so playCard still rejects outOfTurn."
            if recovery_state.get("viewerPlayerId") not in {"p1", "p2"}
            else None,
        },
        "paritySignature": {
            "scenarioId": "MP-008",
            "rejectCode": reject_reason.get("code"),
            "injectedMismatchMode": normalized_mode or "staleExpectedStateVersion",
            "clientStateVersion": client_state_version,
            "expectedStateVersion": expected_state_version,
            "authoritativeStateVersion": authoritative_state_version,
            "recoverySnapshotReason": recovery_reason,
            "gapRecoveryShape": gap_recovery_shape,
            "gapRecoveryHintArtifactVersion": gap_hint["artifactVersion"],
            "gapRecoveryHintTransportFlag": gap_hint["transportFlag"],
            "gapRecoverySnapshotReason": gap_snapshot_reason,
        },
    }


def _run_mp016_socket_attempt(
    harness: SocketTransportHarness,
    *,
    seed: int,
    max_steps: int = 160,
) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=True, rng_seed=seed)
    room_id = boot["room_id"]
    game_id = boot["game_id"]
    transport_label = _transport_summary_label(harness.transport)
    authoritative_state_version = boot["authoritative_state_version"]
    authoritative_event_id = boot["authoritative_event_id"]
    host_projection = _fetch_room_projection(
        harness,
        room_id,
        "p1",
        state_version=authoritative_state_version,
        last_event_id=authoritative_event_id,
    )
    guest_projection = _fetch_room_projection(
        harness,
        room_id,
        "p2",
        state_version=authoritative_state_version,
        last_event_id=authoritative_event_id,
    )

    play_card_count = 0
    capture_choice_count = 0
    shake_choice_count = 0
    chrysanthemum_choice_count = 0
    go_stop_choice_count = 0
    go_stop_option_codes: list[str] = []
    step_summaries: list[dict[str, Any]] = []
    host_terminal_labels: list[str] = []
    guest_terminal_labels: list[str] = []
    terminal_summary_frame: dict[str, Any] | None = None
    terminal_summary_payload: dict[str, Any] | None = None
    final_state_version: int | None = None

    for step_index in range(1, max_steps + 1):
        choice_resolution = _resolve_pending_choice(host_projection, guest_projection)
        if choice_resolution is not None:
            pending_choice, actor_client_id, actor_room_player_id, actor_projection = choice_resolution
            choice_kind = pending_choice.get("choiceKind")
            if not isinstance(choice_kind, str):
                raise RuntimeError("Pending choiceKind is missing.")
            option_code = _choose_pending_choice_option_code(pending_choice)
            actor_state = _projection_state(actor_projection)
            expected_state_version = actor_state.get("stateVersion")
            if not isinstance(expected_state_version, int):
                expected_state_version = authoritative_state_version
            send_result = harness.transport_send_ok(
                actor_client_id,
                "submitChoice",
                requestId=f"req_mp016_seed{seed}_choice_{step_index}",
                actionId=f"act_mp016_seed{seed}_choice_{step_index}",
                expectedStateVersion=expected_state_version,
                commandPayload={
                    "choiceId": pending_choice.get("choiceId"),
                    "optionCode": option_code,
                },
            )
            next_state_version = send_result.get("authoritativeStateVersion")
            if isinstance(next_state_version, int):
                authoritative_state_version = next_state_version
            next_event_id = send_result.get("authoritativeEventId")
            if isinstance(next_event_id, str):
                authoritative_event_id = next_event_id
            if choice_kind == "capture":
                capture_choice_count += 1
            elif choice_kind == "shake":
                shake_choice_count += 1
            elif choice_kind == "chrysanthemumRole":
                chrysanthemum_choice_count += 1
            elif choice_kind == "goStop":
                go_stop_choice_count += 1
                go_stop_option_codes.append(option_code)

            step_summaries.append(
                {
                    "stepIndex": step_index,
                    "kind": "choice",
                    "choiceKind": choice_kind,
                    "choiceId": pending_choice.get("choiceId"),
                    "actorRoomPlayerId": actor_room_player_id,
                    "actorAuthorityPlayerId": pending_choice.get("actorPlayerId"),
                    "expectedStateVersion": expected_state_version,
                    "optionCode": option_code,
                }
            )
        else:
            host_state = _projection_state(host_projection)
            guest_state = _projection_state(guest_projection)
            phase = host_state.get("phase")
            if phase == "matchEnded":
                raise RuntimeError(
                    "Projection reached phase=matchEnded before terminalSummary was delivered on the transport mailbox."
                )
            current_player_id = host_state.get("currentPlayerId")
            if not isinstance(current_player_id, str):
                raise RuntimeError("Current playerId is missing from the host projection.")

            actor_client_id, actor_room_player_id, actor_projection = _resolve_transport_actor(
                host_projection,
                guest_projection,
                current_player_id,
            )
            actor_state = _projection_state(actor_projection)
            expected_state_version = actor_state.get("stateVersion")
            if not isinstance(expected_state_version, int):
                expected_state_version = authoritative_state_version
            card = _select_deterministic_hand_card(actor_projection)
            send_result = harness.transport_send_ok(
                actor_client_id,
                "playCard",
                requestId=f"req_mp016_seed{seed}_play_{step_index}",
                actionId=f"act_mp016_seed{seed}_play_{step_index}",
                expectedStateVersion=expected_state_version,
                commandPayload={
                    "cardId": card["cardId"],
                    "source": "hand",
                },
            )
            next_state_version = send_result.get("authoritativeStateVersion")
            if isinstance(next_state_version, int):
                authoritative_state_version = next_state_version
            next_event_id = send_result.get("authoritativeEventId")
            if isinstance(next_event_id, str):
                authoritative_event_id = next_event_id
            play_card_count += 1
            step_summaries.append(
                {
                    "stepIndex": step_index,
                    "kind": "playCard",
                    "actorRoomPlayerId": actor_room_player_id,
                    "actorAuthorityPlayerId": current_player_id,
                    "expectedStateVersion": expected_state_version,
                    "cardId": card["cardId"],
                    "cardMonth": card.get("month"),
                    "cardKind": card.get("kind"),
                }
            )

        host_frames, guest_frames = _drain_live_mailboxes(harness)
        host_terminal_labels.extend(_frame_label(frame) for frame in host_frames)
        guest_terminal_labels.extend(_frame_label(frame) for frame in guest_frames)
        final_state_version = max(
            [
                value
                for value in (
                    final_state_version,
                    _projection_state(host_projection).get("stateVersion"),
                    _projection_state(guest_projection).get("stateVersion"),
                )
                if isinstance(value, int)
            ],
            default=final_state_version,
        )

        terminal_summary_frame = next(
            (frame for frame in host_frames + guest_frames if frame.get("type") == "terminalSummary"),
            None,
        )
        if terminal_summary_frame is not None:
            terminal_summary_payload = _terminal_summary_payload(terminal_summary_frame)
            break

        host_projection = _fetch_room_projection(
            harness,
            room_id,
            "p1",
            state_version=authoritative_state_version,
            last_event_id=authoritative_event_id,
        )
        guest_projection = _fetch_room_projection(
            harness,
            room_id,
            "p2",
            state_version=authoritative_state_version,
            last_event_id=authoritative_event_id,
        )
        final_state_version = authoritative_state_version
    else:
        raise RuntimeError(
            f"MP-016 exceeded the gameplay loop limit without reaching terminalSummary (seed={seed}, transport={transport_label})."
        )

    if terminal_summary_payload is None:
        raise RuntimeError("MP-016 did not capture a terminalSummary payload.")

    close_result = _close_room_after_terminal(harness, room_id)
    closed_snapshot = close_result["closedSnapshot"]
    match_ended_payload = terminal_summary_payload.get("matchEnded", {})
    if not isinstance(match_ended_payload, dict):
        match_ended_payload = {}

    return {
        "boot": boot,
        "roomId": room_id,
        "gameId": game_id,
        "seed": seed,
        "transportLabel": transport_label,
        "stepsExecuted": len(step_summaries),
        "playCardCount": play_card_count,
        "captureChoiceCount": capture_choice_count,
        "shakeChoiceCount": shake_choice_count,
        "chrysanthemumChoiceCount": chrysanthemum_choice_count,
        "goStopChoiceCount": go_stop_choice_count,
        "goStopOptionCodes": go_stop_option_codes,
        "qualifiedAlwaysGo": go_stop_choice_count > 0,
        "stepSummaries": step_summaries,
        "terminalSummaryPayload": terminal_summary_payload,
        "terminalEndReason": match_ended_payload.get("endReason"),
        "terminalWinnerPlayerId": match_ended_payload.get("winnerPlayerId"),
        "roomClosedSeen": close_result["roomClosedSeen"],
        "closedRoomState": closed_snapshot["room"]["roomState"],
        "closeResult": close_result,
        "closedSnapshot": closed_snapshot,
        "hostTerminalLabels": host_terminal_labels,
        "guestTerminalLabels": guest_terminal_labels,
        "finalStateVersion": final_state_version,
    }


def _run_mp016_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    seed_candidates = (1, 2, 3, 4, 5, 6, 7, 8)
    attempt_summaries: list[dict[str, Any]] = []
    selected_attempt: dict[str, Any] | None = None
    transport_label = _transport_summary_label(harness.transport)

    for seed in seed_candidates:
        attempt = _run_mp016_socket_attempt(harness, seed=seed)
        attempt_summary = {
            "seed": seed,
            "roomId": attempt["roomId"],
            "gameId": attempt["gameId"],
            "stepsExecuted": attempt["stepsExecuted"],
            "playCardCount": attempt["playCardCount"],
            "captureChoiceCount": attempt["captureChoiceCount"],
            "shakeChoiceCount": attempt["shakeChoiceCount"],
            "chrysanthemumChoiceCount": attempt["chrysanthemumChoiceCount"],
            "goStopChoiceCount": attempt["goStopChoiceCount"],
            "goStopOptionCodes": list(attempt["goStopOptionCodes"]),
            "qualifiedAlwaysGo": attempt["qualifiedAlwaysGo"],
            "terminalEndReason": attempt["terminalEndReason"],
            "roomClosedSeen": attempt["roomClosedSeen"],
            "closedRoomState": attempt["closedRoomState"],
        }
        attempt_summaries.append(attempt_summary)
        if attempt["qualifiedAlwaysGo"]:
            selected_attempt = attempt
            break

    if selected_attempt is None:
        latest_attempt = attempt_summaries[-1] if attempt_summaries else {}
        summary = (
            f"Socket {transport_label} end-to-end gameplay reached terminal close, "
            "but none of the seeded runs surfaced a go-stop choice to exercise the always-go policy."
        )
        return {
            "status": ScenarioStatus.BLOCKED,
            "summary": summary,
            "roomId": latest_attempt.get("roomId"),
            "gameId": latest_attempt.get("gameId"),
            "players": _collect_players(
                selected_attempt["closedSnapshot"] if selected_attempt is not None else {}
            )
            if selected_attempt is not None
            else [],
            "commands": list(harness.command_rows),
            "frames": list(harness.frame_rows),
            "snapshots": {},
            "logs": {
                "agent": [
                    f"Socket mode attempted seeded end-to-end gameplay on the {harness.transport} transport backend.",
                    f"attemptedSeeds={list(seed_candidates)}",
                    *harness.agent_log_lines,
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [
                "No seeded run reached a live go-stop choice; the always-go policy was not exercised.",
            ],
            "transportBackend": harness.transport,
            "alwaysGoProbe": {
                "scenarioId": "MP-016",
                "transportBackend": harness.transport,
                "attemptedSeeds": list(seed_candidates),
                "selectedSeed": None,
                "seedAttempts": attempt_summaries,
                "qualifiedAlwaysGo": False,
            },
            "paritySignature": {
                "scenarioId": "MP-016",
                "selectedSeed": None,
                "qualifiedAlwaysGo": False,
                "attemptedSeeds": list(seed_candidates),
            },
        }

    closed_snapshot = selected_attempt["closedSnapshot"]
    players = _collect_players(closed_snapshot)
    always_go_probe = {
        "scenarioId": "MP-016",
        "transportBackend": harness.transport,
        "attemptedSeeds": list(seed_candidates),
        "selectedSeed": selected_attempt["seed"],
        "seedAttempts": attempt_summaries,
        "stepsExecuted": selected_attempt["stepsExecuted"],
        "playCardCount": selected_attempt["playCardCount"],
        "captureChoiceCount": selected_attempt["captureChoiceCount"],
        "shakeChoiceCount": selected_attempt["shakeChoiceCount"],
        "chrysanthemumChoiceCount": selected_attempt["chrysanthemumChoiceCount"],
        "goStopChoiceCount": selected_attempt["goStopChoiceCount"],
        "goStopOptionCodes": list(selected_attempt["goStopOptionCodes"]),
        "terminalSummaryPayload": selected_attempt["terminalSummaryPayload"],
        "terminalEndReason": selected_attempt["terminalEndReason"],
        "terminalWinnerPlayerId": selected_attempt["terminalWinnerPlayerId"],
        "roomClosedSeen": selected_attempt["roomClosedSeen"],
        "closedRoomState": selected_attempt["closedRoomState"],
        "hostTerminalLabels": selected_attempt["hostTerminalLabels"],
        "guestTerminalLabels": selected_attempt["guestTerminalLabels"],
        "closeLabels": {
            "hostAfterHostLeave": selected_attempt["closeResult"]["hostAfterHostLeaveLabels"],
            "guestAfterHostLeave": selected_attempt["closeResult"]["guestAfterHostLeaveLabels"],
            "hostAfterGuestLeave": selected_attempt["closeResult"]["hostAfterGuestLeaveLabels"],
            "guestAfterGuestLeave": selected_attempt["closeResult"]["guestAfterGuestLeaveLabels"],
        },
    }

    return {
        "status": ScenarioStatus.PASS,
        "summary": (
            f"Socket {transport_label} seeded end-to-end gameplay completed from room bootstrap to roomClosed "
            f"while always choosing go on every go-stop prompt (seed={selected_attempt['seed']})."
        ),
        "roomId": selected_attempt["roomId"],
        "gameId": selected_attempt["gameId"],
        "players": players,
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(selected_attempt["boot"]["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(selected_attempt["boot"]["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload={
                    "selectedSeed": selected_attempt["seed"],
                    "terminalSummary": selected_attempt["terminalSummaryPayload"],
                    "closedSnapshot": closed_snapshot,
                    "goStopOptionCodes": list(selected_attempt["goStopOptionCodes"]),
                    "goStopChoiceCount": selected_attempt["goStopChoiceCount"],
                    "roomClosedSeen": selected_attempt["roomClosedSeen"],
                },
                snapshot_id=f"{selected_attempt['roomId']}_socket_always_go",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=closed_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode executed seeded full-room gameplay on the {harness.transport} transport backend.",
                f"selectedSeed={selected_attempt['seed']} attemptedSeeds={list(seed_candidates)}",
                f"goStopChoiceCount={selected_attempt['goStopChoiceCount']} goStopOptionCodes={selected_attempt['goStopOptionCodes']}",
                f"stepsExecuted={selected_attempt['stepsExecuted']} playCardCount={selected_attempt['playCardCount']}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
        "alwaysGoProbe": always_go_probe,
        "paritySignature": {
            "scenarioId": "MP-016",
            "selectedSeed": selected_attempt["seed"],
            "goStopChoiceCount": selected_attempt["goStopChoiceCount"],
            "goStopOptionCodes": list(selected_attempt["goStopOptionCodes"]),
            "stepsExecuted": selected_attempt["stepsExecuted"],
            "playCardCount": selected_attempt["playCardCount"],
            "terminalEndReason": selected_attempt["terminalEndReason"],
            "roomClosedSeen": selected_attempt["roomClosedSeen"],
            "closedRoomState": selected_attempt["closedRoomState"],
        },
    }


def _run_mp017_socket_attempt(
    harness: SocketTransportHarness,
    *,
    seed: int,
    turn_limit_per_player: int = 2,
    max_steps: int = 40,
) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=True, rng_seed=seed)
    room_id = boot["room_id"]
    game_id = boot["game_id"]
    transport_label = _transport_summary_label(harness.transport)
    authoritative_state_version = boot["authoritative_state_version"]
    authoritative_event_id = boot["authoritative_event_id"]
    host_projection = _fetch_room_projection(
        harness,
        room_id,
        "p1",
        state_version=authoritative_state_version,
        last_event_id=authoritative_event_id,
    )
    guest_projection = _fetch_room_projection(
        harness,
        room_id,
        "p2",
        state_version=authoritative_state_version,
        last_event_id=authoritative_event_id,
    )

    turn_counts = {"host_client": 0, "guest_client": 0}
    step_summaries: list[dict[str, Any]] = []
    probe_rows: list[dict[str, Any]] = []
    capture_probe_success_count = 0
    active_probe: dict[str, Any] | None = None

    for step_index in range(1, max_steps + 1):
        choice_resolution = _resolve_pending_choice(host_projection, guest_projection)
        if choice_resolution is not None:
            pending_choice, actor_client_id, actor_room_player_id, actor_projection = choice_resolution
            choice_kind = pending_choice.get("choiceKind")
            if not isinstance(choice_kind, str):
                raise RuntimeError("Pending choiceKind is missing.")
            option_code = _choose_pending_choice_option_code(pending_choice)
            actor_state = _projection_state(actor_projection)
            expected_state_version = actor_state.get("stateVersion")
            if not isinstance(expected_state_version, int):
                expected_state_version = authoritative_state_version
            send_result = harness.transport_send_ok(
                actor_client_id,
                "submitChoice",
                requestId=f"req_mp017_seed{seed}_choice_{step_index}",
                actionId=f"act_mp017_seed{seed}_choice_{step_index}",
                expectedStateVersion=expected_state_version,
                commandPayload={
                    "choiceId": pending_choice.get("choiceId"),
                    "optionCode": option_code,
                },
            )
            next_state_version = send_result.get("authoritativeStateVersion")
            if isinstance(next_state_version, int):
                authoritative_state_version = next_state_version
            next_event_id = send_result.get("authoritativeEventId")
            if isinstance(next_event_id, str):
                authoritative_event_id = next_event_id
            step_summaries.append(
                {
                    "stepIndex": step_index,
                    "kind": "choice",
                    "choiceKind": choice_kind,
                    "choiceId": pending_choice.get("choiceId"),
                    "actorRoomPlayerId": actor_room_player_id,
                    "actorAuthorityPlayerId": pending_choice.get("actorPlayerId"),
                    "expectedStateVersion": expected_state_version,
                    "optionCode": option_code,
                }
            )
        else:
            host_state = _projection_state(host_projection)
            current_player_id = host_state.get("currentPlayerId")
            if not isinstance(current_player_id, str):
                raise RuntimeError("Current playerId is missing from the host projection.")

            actor_client_id, actor_room_player_id, actor_projection = _resolve_transport_actor(
                host_projection,
                guest_projection,
                current_player_id,
            )
            if turn_counts[actor_client_id] >= turn_limit_per_player:
                if all(count >= turn_limit_per_player for count in turn_counts.values()):
                    break
                raise RuntimeError(
                    f"MP-017 encountered an unexpected extra turn for {actor_client_id} before the short probe finished."
                )
            actor_state = _projection_state(actor_projection)
            expected_state_version = actor_state.get("stateVersion")
            if not isinstance(expected_state_version, int):
                expected_state_version = authoritative_state_version
            card = _select_deterministic_hand_card(actor_projection)
            active_probe = {
                "actorClientId": actor_client_id,
                "actorRoomPlayerId": actor_room_player_id,
                "actorAuthorityPlayerId": current_player_id,
                "turnIndex": turn_counts[actor_client_id] + 1,
                "baselineCapturedTotal": _projection_captured_totals(actor_projection).get(current_player_id, 0),
                "expectedCapturedTotal": None,
                "authoritativeCaptureStateVersion": None,
                "turnPassedStateVersion": None,
                "renderedCaptureStateVersion": None,
            }
            send_result = harness.transport_send_ok(
                actor_client_id,
                "playCard",
                requestId=f"req_mp017_seed{seed}_play_{step_index}",
                actionId=f"act_mp017_seed{seed}_play_{step_index}",
                expectedStateVersion=expected_state_version,
                commandPayload={
                    "cardId": card["cardId"],
                    "source": "hand",
                },
            )
            next_state_version = send_result.get("authoritativeStateVersion")
            if isinstance(next_state_version, int):
                authoritative_state_version = next_state_version
            next_event_id = send_result.get("authoritativeEventId")
            if isinstance(next_event_id, str):
                authoritative_event_id = next_event_id
            turn_counts[actor_client_id] += 1
            step_summaries.append(
                {
                    "stepIndex": step_index,
                    "kind": "playCard",
                    "actorClientId": actor_client_id,
                    "actorRoomPlayerId": actor_room_player_id,
                    "actorAuthorityPlayerId": current_player_id,
                    "expectedStateVersion": expected_state_version,
                    "cardId": card["cardId"],
                    "cardMonth": card.get("month"),
                    "cardKind": card.get("kind"),
                    "turnIndex": turn_counts[actor_client_id],
                }
            )

        _drain_live_mailboxes(harness)
        host_projection = _fetch_room_projection(
            harness,
            room_id,
            "p1",
            state_version=authoritative_state_version,
            last_event_id=authoritative_event_id,
        )
        guest_projection = _fetch_room_projection(
            harness,
            room_id,
            "p2",
            state_version=authoritative_state_version,
            last_event_id=authoritative_event_id,
        )

        if active_probe is not None:
            host_state = _projection_state(host_projection)
            actor_authority_id = active_probe["actorAuthorityPlayerId"]
            current_total = _projection_captured_totals(host_projection).get(
                actor_authority_id,
                active_probe["baselineCapturedTotal"],
            )
            if (
                current_total > active_probe["baselineCapturedTotal"]
                and active_probe["expectedCapturedTotal"] is None
            ):
                active_probe["expectedCapturedTotal"] = current_total
                active_probe["authoritativeCaptureStateVersion"] = host_state.get("stateVersion")
            if host_state.get("currentPlayerId") != actor_authority_id:
                active_probe["turnPassedStateVersion"] = host_state.get("stateVersion")
                if active_probe["expectedCapturedTotal"] is not None:
                    active_probe["renderedCaptureStateVersion"] = host_state.get("stateVersion")
                    capture_probe_success_count += 1
                probe_rows.append(active_probe)
                active_probe = None

        if (
            all(count >= turn_limit_per_player for count in turn_counts.values())
            and _projection_state(host_projection).get("pendingChoice") is None
            and _projection_state(guest_projection).get("pendingChoice") is None
            and active_probe is None
        ):
            break
    else:
        raise RuntimeError(
            f"MP-017 exceeded the gameplay loop limit without completing two turns per player (seed={seed}, transport={transport_label})."
        )

    if active_probe is not None:
        probe_rows.append(active_probe)

    room_snapshot = harness.snapshot_room(room_id)
    return {
        "boot": boot,
        "roomId": room_id,
        "gameId": game_id,
        "seed": seed,
        "transportLabel": transport_label,
        "turnCounts": dict(turn_counts),
        "stepSummaries": step_summaries,
        "probeRows": probe_rows,
        "captureProbeSuccessCount": capture_probe_success_count,
        "qualifiedCaptureVisibility": capture_probe_success_count > 0,
        "roomSnapshot": room_snapshot,
    }


def _run_mp017_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    seed_candidates = (1, 2, 3, 4, 5, 6, 7, 8)
    attempt_summaries: list[dict[str, Any]] = []
    selected_attempt: dict[str, Any] | None = None
    transport_label = _transport_summary_label(harness.transport)

    for seed in seed_candidates:
        attempt = _run_mp017_socket_attempt(harness, seed=seed)
        attempt_summary = {
            "seed": seed,
            "roomId": attempt["roomId"],
            "gameId": attempt["gameId"],
            "turnCounts": attempt["turnCounts"],
            "captureProbeSuccessCount": attempt["captureProbeSuccessCount"],
            "qualifiedCaptureVisibility": attempt["qualifiedCaptureVisibility"],
            "roomState": attempt["roomSnapshot"]["room"]["roomState"],
        }
        attempt_summaries.append(attempt_summary)
        if attempt["qualifiedCaptureVisibility"]:
            selected_attempt = attempt
            break

    if selected_attempt is None:
        latest_attempt = attempt_summaries[-1] if attempt_summaries else {}
        return {
            "status": ScenarioStatus.BLOCKED,
            "summary": (
                f"Socket {transport_label} short capture-visibility probe completed, "
                "but none of the seeded runs surfaced an authoritative capture inside the first two turns per player."
            ),
            "roomId": latest_attempt.get("roomId"),
            "gameId": latest_attempt.get("gameId"),
            "players": [],
            "commands": list(harness.command_rows),
            "frames": list(harness.frame_rows),
            "snapshots": {},
            "logs": {
                "agent": [
                    f"Socket mode attempted the short capture-visibility probe on the {harness.transport} transport backend.",
                    f"attemptedSeeds={list(seed_candidates)}",
                    *harness.agent_log_lines,
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [
                "No seeded run produced an authoritative capture during the four-turn probe window.",
            ],
            "transportBackend": harness.transport,
            "captureVisibilityProbe": {
                "scenarioId": "MP-017",
                "transportBackend": harness.transport,
                "attemptedSeeds": list(seed_candidates),
                "selectedSeed": None,
                "seedAttempts": attempt_summaries,
            },
            "paritySignature": {
                "scenarioId": "MP-017",
                "selectedSeed": None,
                "qualifiedCaptureVisibility": False,
                "attemptedSeeds": list(seed_candidates),
            },
        }

    room_snapshot = selected_attempt["roomSnapshot"]
    players = _collect_players(room_snapshot)
    capture_visibility_probe = {
        "scenarioId": "MP-017",
        "transportBackend": harness.transport,
        "attemptedSeeds": list(seed_candidates),
        "selectedSeed": selected_attempt["seed"],
        "seedAttempts": attempt_summaries,
        "turnCounts": selected_attempt["turnCounts"],
        "probeRows": selected_attempt["probeRows"],
        "captureProbeSuccessCount": selected_attempt["captureProbeSuccessCount"],
        "roomState": room_snapshot["room"]["roomState"],
    }

    return {
        "status": ScenarioStatus.PASS,
        "summary": (
            f"Socket {transport_label} short multiplayer capture probe completed two turns per player "
            f"without captured-zone lag in the authoritative baseline (seed={selected_attempt['seed']})."
        ),
        "roomId": selected_attempt["roomId"],
        "gameId": selected_attempt["gameId"],
        "players": players,
        "commands": list(harness.command_rows),
        "frames": list(harness.frame_rows),
        "snapshots": {
            "player_a_initial": _player_snapshot_record(selected_attempt["boot"]["host_state_snapshot"], "p1"),
            "player_b_initial": _player_snapshot_record(selected_attempt["boot"]["guest_state_snapshot"], "p2"),
            "latest_server": _snapshot_record(
                payload={
                    "selectedSeed": selected_attempt["seed"],
                    "turnCounts": selected_attempt["turnCounts"],
                    "captureProbeSuccessCount": selected_attempt["captureProbeSuccessCount"],
                    "probeRows": selected_attempt["probeRows"],
                    "roomState": room_snapshot["room"]["roomState"],
                },
                snapshot_id=f"{selected_attempt['roomId']}_socket_capture_visibility",
                source="terminal",
                scope="authority",
                player_id=None,
                state_version=room_snapshot["room"]["lastRoomSequence"],
                event_id=None,
            ),
        },
        "logs": {
            "agent": [
                f"Socket mode executed the short capture-visibility probe on the {harness.transport} transport backend.",
                f"selectedSeed={selected_attempt['seed']} attemptedSeeds={list(seed_candidates)}",
                f"turnCounts={selected_attempt['turnCounts']} captureProbeSuccessCount={selected_attempt['captureProbeSuccessCount']}",
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
        "captureVisibilityProbe": capture_visibility_probe,
        "paritySignature": {
            "scenarioId": "MP-017",
            "selectedSeed": selected_attempt["seed"],
            "turnCounts": selected_attempt["turnCounts"],
            "captureProbeSuccessCount": selected_attempt["captureProbeSuccessCount"],
            "roomState": room_snapshot["room"]["roomState"],
        },
    }


def _run_socket_scenario_once(
    scenario: ScenarioDefinition,
    *,
    repo_root: Path,
    binary_path: Path,
    transport: str,
) -> dict[str, Any]:
    harness = SocketTransportHarness(repo_root=repo_root, binary_path=binary_path, transport=transport)
    try:
        if scenario.scenario_id == "MP-001":
            return _run_mp001_socket(harness)
        if scenario.scenario_id == "MP-002":
            return _run_mp002_socket(harness)
        if scenario.scenario_id == "MP-004":
            return _run_mp004_socket(harness)
        if scenario.scenario_id == "MP-007":
            return _run_mp007_socket(harness)
        if scenario.scenario_id == "MP-013":
            return _run_mp013_socket(harness)
        if scenario.scenario_id == "MP-014":
            return _run_mp014_socket(harness)
        if scenario.scenario_id == "MP-008":
            return _run_mp008_socket(harness)
        if scenario.scenario_id == "MP-016":
            return _run_mp016_socket(harness)
        if scenario.scenario_id == "MP-017":
            return _run_mp017_socket(harness)
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
                    f"Socket mode is available for {transport}, but this scenario is still scaffold-only.",
                    *harness.agent_log_lines,
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [
                f"Socket mode is not implemented for {scenario.scenario_id} on transport={transport} yet.",
            ],
            "transportBackend": transport,
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
                    *harness.agent_log_lines,
                ],
                "room": harness.room_log_lines,
                "engine": harness.engine_log_lines,
            },
            "blockingReasons": [str(error)],
            "transportBackend": transport,
        }
    finally:
        harness.close()


def _compare_snapshot_records(
    name: str,
    tcp_snapshot: dict[str, Any] | None,
    websocket_snapshot: dict[str, Any] | None,
) -> dict[str, Any]:
    payload = {
        "transportCompare": {
            "name": name,
            "tcp": tcp_snapshot["payload"] if isinstance(tcp_snapshot, dict) else None,
            "websocket": websocket_snapshot["payload"] if isinstance(websocket_snapshot, dict) else None,
        }
    }
    return _snapshot_record(
        payload=payload,
        snapshot_id=f"{name}_transport_compare",
        source="compare",
        scope=tcp_snapshot.get("scope") if isinstance(tcp_snapshot, dict) else "authority",
        player_id=tcp_snapshot.get("player_id") if isinstance(tcp_snapshot, dict) else None,
        state_version=None,
        event_id=None,
    )


def _merge_transport_rows(rows: list[dict[str, Any]], transport: str) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for row in rows:
        next_row = dict(row)
        next_row.setdefault("transportBackend", transport)
        merged.append(next_row)
    return merged


def _compare_socket_results(
    scenario: ScenarioDefinition,
    tcp_result: dict[str, Any],
    websocket_result: dict[str, Any],
) -> dict[str, Any]:
    parity_issues: list[str] = []
    tcp_status = tcp_result["status"]
    websocket_status = websocket_result["status"]

    if tcp_status != websocket_status:
        parity_issues.append(
            f"Transport status diverged: tcp={tcp_status.value} websocket={websocket_status.value}."
        )

    tcp_signature = tcp_result.get("paritySignature")
    websocket_signature = websocket_result.get("paritySignature")
    if tcp_signature != websocket_signature:
        parity_issues.append(
            "Transport parity signature diverged between TCP fallback and websocket.\n"
            f"tcp={json.dumps(tcp_signature, ensure_ascii=False, sort_keys=True)}\n"
            f"websocket={json.dumps(websocket_signature, ensure_ascii=False, sort_keys=True)}"
        )

    if any(status is ScenarioStatus.FAIL for status in (tcp_status, websocket_status)):
        status = ScenarioStatus.FAIL
    elif any(status is ScenarioStatus.BLOCKED for status in (tcp_status, websocket_status)):
        status = ScenarioStatus.BLOCKED
    elif parity_issues:
        status = ScenarioStatus.FAIL
    else:
        status = ScenarioStatus.PASS

    if status is ScenarioStatus.PASS:
        summary = (
            "Socket transport parity matched between TCP fallback and websocket for the live scenario."
        )
    elif parity_issues:
        summary = (
            "Socket transport parity diverged between TCP fallback and websocket. "
            "Inspect transport_parity.json plus suffixed snapshots for the exact mismatch."
        )
    else:
        summary = (
            "TCP fallback and websocket both reached the same live blocker. "
            "Inspect transport_parity.json plus duplicate/resync artifacts for the exact transport gap."
        )

    combined_snapshots: dict[str, Any] = {}
    snapshot_names = set(tcp_result.get("snapshots", {})) | set(websocket_result.get("snapshots", {}))
    for name in sorted(snapshot_names):
        tcp_snapshot = tcp_result.get("snapshots", {}).get(name)
        websocket_snapshot = websocket_result.get("snapshots", {}).get(name)
        combined_snapshots[name] = _compare_snapshot_records(name, tcp_snapshot, websocket_snapshot)
        if isinstance(tcp_snapshot, dict):
            combined_snapshots[f"{name}_tcp"] = tcp_snapshot
        if isinstance(websocket_snapshot, dict):
            combined_snapshots[f"{name}_websocket"] = websocket_snapshot

    combined_commands = _merge_transport_rows(tcp_result.get("commands", []), "tcp")
    combined_commands.extend(_merge_transport_rows(websocket_result.get("commands", []), "websocket"))
    combined_frames = _merge_transport_rows(tcp_result.get("frames", []), "tcp")
    combined_frames.extend(_merge_transport_rows(websocket_result.get("frames", []), "websocket"))

    players = tcp_result.get("players") or websocket_result.get("players") or []

    blocking_reasons = list(
        dict.fromkeys(
            parity_issues
            + list(tcp_result.get("blockingReasons", []))
            + list(websocket_result.get("blockingReasons", []))
        )
    )

    result: dict[str, Any] = {
        "status": status,
        "summary": summary,
        "roomId": tcp_result.get("roomId"),
        "gameId": tcp_result.get("gameId"),
        "players": players,
        "commands": combined_commands,
        "frames": combined_frames,
        "snapshots": combined_snapshots,
        "logs": {
            "agent": [
                "compare mode executed both TCP fallback and websocket transport backends under the same artifact root.",
                "transport summaries:",
                f"tcp: {tcp_result.get('summary')}",
                f"websocket: {websocket_result.get('summary')}",
                "[tcp]",
                *[f"  {line}" for line in tcp_result.get("logs", {}).get("agent", [])],
                "[websocket]",
                *[f"  {line}" for line in websocket_result.get("logs", {}).get("agent", [])],
            ],
            "room": [
                "[tcp]",
                *[f"  {line}" for line in tcp_result.get("logs", {}).get("room", [])],
                "[websocket]",
                *[f"  {line}" for line in websocket_result.get("logs", {}).get("room", [])],
            ],
            "engine": [
                "[tcp]",
                *[f"  {line}" for line in tcp_result.get("logs", {}).get("engine", [])],
                "[websocket]",
                *[f"  {line}" for line in websocket_result.get("logs", {}).get("engine", [])],
            ],
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": "compare",
        "transportParity": {
            "scenarioId": scenario.scenario_id,
            "tcp": {
                "status": tcp_status.value,
                "summary": tcp_result.get("summary"),
                "roomId": tcp_result.get("roomId"),
                "gameId": tcp_result.get("gameId"),
                "paritySignature": tcp_signature,
            },
            "websocket": {
                "status": websocket_status.value,
                "summary": websocket_result.get("summary"),
                "roomId": websocket_result.get("roomId"),
                "gameId": websocket_result.get("gameId"),
                "paritySignature": websocket_signature,
            },
        },
    }

    if scenario.scenario_id == "MP-008":
        result["injectionPlan"] = {
            "executionReadiness": "transport-compare",
            "tcp": tcp_result.get("injectionPlan"),
            "websocket": websocket_result.get("injectionPlan"),
        }
        result["gapRecoveryShape"] = {
            "tcp": tcp_result.get("gapRecoveryShape"),
            "websocket": websocket_result.get("gapRecoveryShape"),
        }
        mismatch_frames = _merge_transport_rows(tcp_result.get("mismatchFrames", []), "tcp")
        mismatch_frames.extend(_merge_transport_rows(websocket_result.get("mismatchFrames", []), "websocket"))
        result["mismatchFrames"] = mismatch_frames
        result["gapRecoveryProbe"] = {
            "tcp": tcp_result.get("gapRecoveryProbe"),
            "websocket": websocket_result.get("gapRecoveryProbe"),
        }

    if scenario.scenario_id == "MP-001":
        result["bootstrapBoundaryProbe"] = {
            "tcp": tcp_result.get("bootstrapBoundaryProbe"),
            "websocket": websocket_result.get("bootstrapBoundaryProbe"),
        }

    if scenario.scenario_id == "MP-004":
        result["duplicateProbe"] = {
            "tcp": tcp_result.get("duplicateProbe"),
            "websocket": websocket_result.get("duplicateProbe"),
        }

    if scenario.scenario_id == "MP-007":
        result["timeoutProbe"] = {
            "tcp": tcp_result.get("timeoutProbe"),
            "websocket": websocket_result.get("timeoutProbe"),
        }

    if scenario.scenario_id == "MP-014":
        result["heartbeatProbe"] = {
            "tcp": tcp_result.get("heartbeatProbe"),
            "websocket": websocket_result.get("heartbeatProbe"),
        }
        result["staleHeartbeatCodeProbe"] = {
            "cliIngressBaseline": {
                "commandSurface": "room_heartbeat",
                "disconnectedErrorCode": "invalidResumeState",
                "staleErrorCode": "staleConnectionId",
            },
            "tcp": tcp_result.get("staleHeartbeatCodeProbe"),
            "websocket": websocket_result.get("staleHeartbeatCodeProbe"),
        }

    if scenario.scenario_id == "MP-016":
        result["alwaysGoProbe"] = {
            "tcp": tcp_result.get("alwaysGoProbe"),
            "websocket": websocket_result.get("alwaysGoProbe"),
        }

    if scenario.scenario_id == "MP-017":
        result["captureVisibilityProbe"] = {
            "tcp": tcp_result.get("captureVisibilityProbe"),
            "websocket": websocket_result.get("captureVisibilityProbe"),
        }

    return result


def run_socket_scenario(
    scenario: ScenarioDefinition,
    *,
    repo_root: Path,
    binary_path: Path,
    transport: str = "tcp",
) -> dict[str, Any]:
    if transport == "compare":
        tcp_result = _run_socket_scenario_once(
            scenario,
            repo_root=repo_root,
            binary_path=binary_path,
            transport="tcp",
        )
        websocket_result = _run_socket_scenario_once(
            scenario,
            repo_root=repo_root,
            binary_path=binary_path,
            transport="websocket",
        )
        return _compare_socket_results(scenario, tcp_result, websocket_result)

    return _run_socket_scenario_once(
        scenario,
        repo_root=repo_root,
        binary_path=binary_path,
        transport=transport,
    )
