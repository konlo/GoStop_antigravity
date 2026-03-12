from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import subprocess
import time
from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from .models import ScenarioDefinition, ScenarioStatus


KNOWN_SOCKET_DERIVED_DATA_ROOTS = [
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


def _bootstrap_transport_room(
    harness: SocketTransportHarness,
    *,
    warm_engine: bool = False,
    hello_connection_aliases: dict[str, str] | None = None,
) -> dict[str, Any]:
    if warm_engine:
        harness.ensure_engine_started()

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
    }


def _run_mp001_socket(harness: SocketTransportHarness) -> dict[str, Any]:
    boot = _bootstrap_transport_room(harness, warm_engine=False)
    room_snapshot = boot["room_snapshot"]
    room = room_snapshot["room"]
    transport_label = _transport_summary_label(harness.transport)

    if room["roomState"] != "inGame":
        raise RuntimeError(f"Expected roomState=inGame, got {room['roomState']!r}")
    if room["activeGameId"] != boot["game_id"]:
        raise RuntimeError(f"Expected activeGameId={boot['game_id']!r}, got {room['activeGameId']!r}")

    return {
        "status": ScenarioStatus.PASS,
        "summary": f"Socket {transport_label} smoke validated hello/setReady/recordGameStarted with paired gameStarted/stateSnapshot bootstrap.",
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
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": [],
        "transportBackend": harness.transport,
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

    disconnected_snapshot: dict[str, Any] | None = None
    for _ in range(20):
        time.sleep(0.05)
        candidate_snapshot = harness.snapshot_room(room_id)
        guest_member = next(
            (member for member in candidate_snapshot["room"]["members"] if member["playerId"] == "p2"),
            None,
        )
        if isinstance(guest_member, dict) and guest_member.get("presence") == "disconnected":
            disconnected_snapshot = candidate_snapshot
            break
    if disconnected_snapshot is None:
        disconnected_snapshot = harness.snapshot_room(room_id)

    host_after_disconnect = harness.transport_receive("host_client")
    guest_after_disconnect = harness.transport_receive("guest_client")

    player_disconnected = next(
        (
            frame
            for frame in host_after_disconnect
            if frame.get("type") == "roomEvent" and _room_event_name(frame) == "playerDisconnected"
        ),
        None,
    )
    disconnect_at = datetime.now().astimezone()
    first_reap_at = disconnect_at + timedelta(seconds=31)
    first_reap_response = harness.transport_send_ok(
        "host_client",
        "reapExpiredState",
        traceId=f"trace_mp007_{harness.transport}",
        asOf=first_reap_at.isoformat(timespec="seconds"),
    )
    host_after_timeout = harness.transport_receive("host_client")
    guest_after_timeout = harness.transport_receive("guest_client")

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
        lastSeen={"roomSequence": disconnected_snapshot["room"]["lastRoomSequence"]},
    )
    resume_probe_frames = harness.transport_receive("guest_resume")

    second_reap_at = first_reap_at + timedelta(seconds=61)
    second_reap_response = harness.transport_send_ok(
        "host_client",
        "reapExpiredState",
        traceId=f"trace_mp007_close_{harness.transport}",
        asOf=second_reap_at.isoformat(timespec="seconds"),
    )
    host_after_close = harness.transport_receive("host_client")
    guest_after_close = harness.transport_receive("guest_client")
    closed_snapshot = harness.snapshot_room(room_id)

    host_timeout_labels = [_frame_label(frame) for frame in host_after_timeout]
    guest_timeout_labels = [_frame_label(frame) for frame in guest_after_timeout]
    host_disconnect_labels = [_frame_label(frame) for frame in host_after_disconnect]
    guest_disconnect_labels = [_frame_label(frame) for frame in guest_after_disconnect]
    host_close_labels = [_frame_label(frame) for frame in host_after_close]
    guest_close_labels = [_frame_label(frame) for frame in guest_after_close]
    resume_probe_labels = [_frame_label(frame) for frame in resume_probe_frames]

    status = ScenarioStatus.PASS
    blocking_reasons: list[str] = []

    try:
        action_accepted = _find_engine_event(host_after_timeout, event_name="actionAccepted")
        round_ended = _find_engine_event(host_after_timeout, event_name="roundEnded")
        match_ended = _find_engine_event(host_after_timeout, event_name="matchEnded")
    except RuntimeError as error:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(str(error))
        action_accepted = None
        round_ended = None
        match_ended = None

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
    if timeout_forfeit is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Timeout path did not emit roomEvent(playerForfeited reason=disconnectTimeout).")
    if player_disconnected is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Passive close did not emit roomEvent(playerDisconnected).")

    terminal_summary_frame = next(
        (frame for frame in host_after_timeout if frame.get("type") == "terminalSummary"),
        None,
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

    room_closed_frame = next(
        (
            frame
            for frame in host_after_close
            if frame.get("type") == "roomEvent" and _room_event_name(frame) == "roomClosed"
        ),
        None,
    )
    if room_closed_frame is None:
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append("Second timeout reap did not emit roomEvent(roomClosed).")

    closed_room_state = closed_snapshot["room"]["roomState"]
    if closed_room_state != "closed":
        status = ScenarioStatus.BLOCKED
        blocking_reasons.append(f"Room state after timeout close diverged: expected 'closed', got {closed_room_state!r}.")

    summary = (
        f"Socket {transport_label} passive-close timeout smoke validated disconnectTimeout forfeit relay, "
        "terminalSummary fan-out, and later roomClosed completion."
    )
    if status is ScenarioStatus.BLOCKED:
        summary = (
            f"Socket {transport_label} passive-close timeout smoke reached disconnectTimeout expiry, "
            "but terminal or close ordering still diverged from the locked contract."
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
                f"Socket mode used {harness.transport} room transport passive close + reapExpiredState for timeout coverage.",
                f"passiveCloseAt={passive_close_at.isoformat(timespec='seconds')} firstReapQueued={first_reap_response.get('queuedEnvelopeCount')}",
                f"resumeExpiredError={resume_attempt['errorCode']}",
                f"secondReapQueued={second_reap_response.get('queuedEnvelopeCount')}",
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
            "disconnectResponse": None,
            "firstReapResponse": first_reap_response,
            "resumeExpiredResponse": resume_attempt,
            "secondReapResponse": second_reap_response,
            "passiveCloseAt": passive_close_at.isoformat(timespec="seconds"),
            "hostDisconnectLabels": host_disconnect_labels,
            "guestDisconnectLabels": guest_disconnect_labels,
            "hostTimeoutLabels": host_timeout_labels,
            "guestTimeoutLabels": guest_timeout_labels,
            "resumeProbeLabels": resume_probe_labels,
            "hostCloseLabels": host_close_labels,
            "guestCloseLabels": guest_close_labels,
            "closedRoomState": closed_room_state,
            "firstReapAt": first_reap_at.isoformat(timespec="seconds"),
            "secondReapAt": second_reap_at.isoformat(timespec="seconds"),
            "terminalSummaryPayload": terminal_payload,
        },
        "paritySignature": {
            "scenarioId": "MP-007",
            "disconnectMode": "passiveClose",
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
    summary = "Socket TCP gameplay smoke validated staleStateVersion reject plus stateSnapshot(reason=resync) on a live transport command."
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
                *harness.agent_log_lines,
            ],
            "room": harness.room_log_lines,
            "engine": harness.engine_log_lines,
        },
        "blockingReasons": blocking_reasons,
        "transportBackend": harness.transport,
        "injectionPlan": {
            "executionReadiness": "live-socket-gameplay",
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
            },
        ],
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
        mismatch_frames = _merge_transport_rows(tcp_result.get("mismatchFrames", []), "tcp")
        mismatch_frames.extend(_merge_transport_rows(websocket_result.get("mismatchFrames", []), "websocket"))
        result["mismatchFrames"] = mismatch_frames

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
