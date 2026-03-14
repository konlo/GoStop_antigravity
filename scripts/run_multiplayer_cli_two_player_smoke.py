#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import traceback
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional


KNOWN_CLI_BINARY_ROOTS = [
    Path("/tmp/gostop_cli_round16_agent2"),
    Path("/tmp/gostop_cli_round16_agent4"),
    Path("/tmp/gostop_cli_round15_agent2"),
    Path("/tmp/gostop_cli_round15_agent4"),
    Path("/tmp/gostop_cli_round14_agent2"),
    Path("/tmp/gostop_cli_round13_agent2"),
    Path("/tmp/gostop_cli_round12_agent2"),
    Path("/tmp/gostop_cli_round11_agent4"),
    Path("/tmp/gostop_cli_round10_agent4"),
    Path("/tmp/gostop_cli_two_player_smoke"),
    Path("/tmp/gostop_cli_agent4_round7_recheck"),
    Path("/tmp/gostop_cli_round7_review"),
    Path("/tmp/gostop_cli_round6_review"),
    Path("/tmp/gostop_cli_status_check"),
    Path("/tmp/gostop_cli_build"),
    Path("/tmp/gostop_cli_agent2_round5"),
    Path("/tmp/gostop_cli_final_review"),
]


def default_output_root(repo_root: Path, final_validation: bool = False) -> Path:
    root = repo_root / "test_artifacts" / "multiplayer_cli_smoke"
    if final_validation:
        return root / "round17_final_validation"
    return root


def binary_candidates(derived_data: Path) -> list[Path]:
    roots = [derived_data, *KNOWN_CLI_BINARY_ROOTS]
    candidates: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        candidate = root / "Build/Products/Debug/GoStopCLI"
        if candidate in seen:
            continue
        seen.add(candidate)
        candidates.append(candidate)
    return candidates


def resolve_binary(repo_root: Path, derived_data: Path, binary: Optional[str], skip_build: bool) -> Path:
    if binary:
        return Path(binary).resolve()

    for candidate in binary_candidates(derived_data):
        if candidate.exists():
            return candidate

    if skip_build:
        searched = "\n".join(f"- {candidate}" for candidate in binary_candidates(derived_data))
        raise SystemExit(
            "GoStopCLI binary not found while --skip-build is enabled.\n"
            f"Searched:\n{searched}"
        )

    print(f"[1/3] Building GoStopCLI into {derived_data}")
    return build_cli(repo_root, derived_data)


def build_cli(repo_root: Path, derived_data: Path) -> Path:
    command = [
        "xcodebuild",
        "-project",
        "GoStop.xcodeproj",
        "-scheme",
        "GoStopCLI",
        "-configuration",
        "Debug",
        "-derivedDataPath",
        str(derived_data),
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
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)

    return derived_data / "Build/Products/Debug/GoStopCLI"


class CLIClient:
    def __init__(self, binary_path: Path) -> None:
        self.history: list[Dict[str, Any]] = []
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

    def send(self, action: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        request = {"action": action}
        if data is not None:
            request["data"] = data

        if not self.process.stdin or not self.process.stdout:
            raise RuntimeError("GoStopCLI process pipes are not available.")

        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()

        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("GoStopCLI closed before sending a JSON response.")

            text = line.strip()
            if not text:
                continue

            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                continue

            if isinstance(payload, dict) and payload.get("action") == action:
                self.history.append(
                    {
                        "request": request,
                        "response": payload,
                    }
                )
                return payload

    def history_index(self) -> int:
        return len(self.history)

    def history_since(self, index: int) -> list[Dict[str, Any]]:
        return list(self.history[index:])


def require_ok(label: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    if payload.get("status") != "ok":
        raise RuntimeError(f"{label} failed: {json.dumps(payload, ensure_ascii=False, indent=2)}")
    return payload["data"]


def require_error(label: str, payload: Dict[str, Any], expected_code: str) -> Dict[str, Any]:
    if payload.get("status") != "error":
        raise RuntimeError(
            f"{label} expected error {expected_code}, got: {json.dumps(payload, ensure_ascii=False, indent=2)}"
        )
    if payload.get("errorCode") != expected_code:
        raise RuntimeError(
            f"{label} expected errorCode={expected_code}, got: {json.dumps(payload, ensure_ascii=False, indent=2)}"
        )
    return payload


def require_ok_response(label: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    if payload.get("status") != "ok":
        raise RuntimeError(f"{label} failed: {json.dumps(payload, ensure_ascii=False, indent=2)}")
    return payload


def require_equal(label: str, actual: Any, expected: Any) -> Any:
    if actual != expected:
        raise RuntimeError(f"{label} expected {expected!r}, got {actual!r}")
    return actual


def require_present(label: str, value: Any) -> Any:
    if value in (None, "", []):
        raise RuntimeError(f"{label} must be present, got {value!r}")
    return value


def bootstrap_recommended_next_actions(stage: str) -> list[str]:
    if stage == "createRoom":
        return ["room_transport_connect", "room_transport_send(action=hello)"]
    if stage == "lookupInvite":
        return ["room_bootstrap_join"]
    if stage == "joinRoom":
        return ["room_transport_connect", "room_transport_send(action=hello)", "room_set_ready"]
    if stage == "prepareGameStart":
        return ["room_transport_receive"]
    return []


def require_bootstrap_boundary(
    label: str,
    boundary: Any,
    *,
    stage: str,
    current_action: str,
    future_public_route: str,
) -> Dict[str, Any]:
    if not isinstance(boundary, dict):
        raise RuntimeError(f"{label} must be an object, got {boundary!r}")

    require_equal(f"{label}.surfaceKind", boundary.get("surfaceKind"), "publicBootstrapFacade")
    require_equal(f"{label}.boundaryVersion", boundary.get("boundaryVersion"), "room-bootstrap.v1")
    require_equal(f"{label}.stage", boundary.get("stage"), stage)
    current_boundary = require_present(f"{label}.currentBoundary", boundary.get("currentBoundary"))
    require_equal(f"{label}.currentBoundary.mode", current_boundary["mode"], "concreteCommandFacade")
    require_equal(f"{label}.currentBoundary.createAction", current_boundary["createAction"], "room_bootstrap_create")
    require_equal(
        f"{label}.currentBoundary.lookupInviteAction",
        current_boundary["lookupInviteAction"],
        "room_bootstrap_lookup_invite",
    )
    require_equal(f"{label}.currentBoundary.joinAction", current_boundary["joinAction"], "room_bootstrap_join")
    require_equal(
        f"{label}.currentBoundary.prepareGameStartAction",
        current_boundary["prepareGameStartAction"],
        "room_bootstrap_prepare_game_start",
    )
    require_equal(f"{label}.currentCommandAction", boundary.get("currentCommandAction"), current_action)
    future_public_split = require_present(f"{label}.futurePublicSplit", boundary.get("futurePublicSplit"))
    require_equal(f"{label}.futurePublicSplit.status", future_public_split["status"], "placeholder")
    require_equal(f"{label}.futurePublicSplit.route", future_public_split["route"], future_public_route)
    recommended_next_actions = require_present(f"{label}.recommendedNextActions", boundary.get("recommendedNextActions"))
    require_equal(
        f"{label}.recommendedNextActions",
        recommended_next_actions,
        bootstrap_recommended_next_actions(stage),
    )
    gameplay_boundary = require_present(f"{label}.gameplayTransportBoundary", boundary.get("gameplayTransportBoundary"))
    require_equal(f"{label}.gameplayTransportBoundary.connectAction", gameplay_boundary["connectAction"], "room_transport_connect")
    require_equal(f"{label}.gameplayTransportBoundary.sendAction", gameplay_boundary["sendAction"], "room_transport_send")
    require_equal(f"{label}.gameplayTransportBoundary.receiveAction", gameplay_boundary["receiveAction"], "room_transport_receive")
    require_equal(f"{label}.gameplayTransportBoundary.helloAction", gameplay_boundary["helloAction"], "hello")
    require_equal(f"{label}.gapRecoveryShapeAction", boundary.get("gapRecoveryShapeAction"), "room_gap_recovery_shape")
    gap_recovery = require_present(f"{label}.gapRecovery", boundary.get("gapRecovery"))
    require_equal(f"{label}.gapRecovery.shapeAction", gap_recovery["shapeAction"], "room_gap_recovery_shape")
    require_equal(f"{label}.gapRecovery.transportTriggerAction", gap_recovery["transportTriggerAction"], "triggerGapRecovery")
    return {
        "surfaceKind": boundary["surfaceKind"],
        "boundaryVersion": boundary["boundaryVersion"],
        "stage": boundary["stage"],
        "currentBoundary": dict(current_boundary),
        "currentCommandAction": boundary["currentCommandAction"],
        "futurePublicSplit": dict(future_public_split),
        "recommendedNextActions": list(recommended_next_actions),
        "gameplayTransportBoundary": dict(gameplay_boundary),
        "gapRecoveryShapeAction": boundary["gapRecoveryShapeAction"],
        "gapRecovery": dict(gap_recovery),
    }


def require_gap_recovery_shape(label: str, payload: Any) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError(f"{label} must be an object, got {payload!r}")
    require_equal(f"{label}.mode", payload.get("mode"), "artifactOnly")
    transport_flag = require_present(f"{label}.transportFlag", payload.get("transportFlag"))
    require_equal(f"{label}.transportFlag.name", transport_flag["name"], "gapDetected")
    require_equal(f"{label}.transportFlag.status", transport_flag["status"], "placeholder")
    require_equal(f"{label}.transportFlag.currentEmission", transport_flag["currentEmission"], False)
    require_equal(
        f"{label}.transportFlag.futureTrigger",
        transport_flag["futureTrigger"],
        "missingGameEventOrStateVersionGap",
    )
    artifact = require_present(f"{label}.artifact", payload.get("artifact"))
    require_equal(f"{label}.artifact.name", artifact["name"], "gapRecoveryHint")
    require_equal(f"{label}.artifact.inputLockRequired", artifact["inputLockRequired"], True)
    require_equal(f"{label}.artifact.snapshotReason", artifact["snapshotReason"], "gapDetected")
    require_equal(
        f"{label}.artifact.minimumFields",
        artifact["minimumFields"],
        [
            "roomId",
            "sessionId",
            "lastAckedGameEventId",
            "lastSeenStateVersion",
            "authoritativeEventId",
            "authoritativeStateVersion",
        ],
    )
    recovery_envelope = require_present(f"{label}.recoveryEnvelope", payload.get("recoveryEnvelope"))
    require_equal(f"{label}.recoveryEnvelope.type", recovery_envelope["type"], "gameEvent")
    require_equal(f"{label}.recoveryEnvelope.eventName", recovery_envelope["eventName"], "stateSnapshot")
    require_equal(f"{label}.recoveryEnvelope.reason", recovery_envelope["reason"], "gapDetected")
    related_actions = require_present(f"{label}.relatedActions", payload.get("relatedActions"))
    require_equal(
        f"{label}.relatedActions.bootstrapPrepareAction",
        related_actions["bootstrapPrepareAction"],
        "room_bootstrap_prepare_game_start",
    )
    require_equal(
        f"{label}.relatedActions.debugStaleHookAction",
        related_actions["debugStaleHookAction"],
        "room_set_mp008_hook",
    )
    live_hook = require_present(f"{label}.liveHook", payload.get("liveHook"))
    require_equal(
        f"{label}.liveHook.transportAction",
        live_hook["transportAction"],
        "room_transport_send(action=triggerGapRecovery)",
    )
    require_equal(
        f"{label}.liveHook.recoveryEnvelopeType",
        live_hook["recoveryEnvelopeType"],
        "gapRecoveryHint",
    )
    return {
        "mode": payload["mode"],
        "transportFlag": dict(transport_flag),
        "artifact": dict(artifact),
        "recoveryEnvelope": dict(recovery_envelope),
        "relatedActions": dict(related_actions),
        "liveHook": dict(live_hook),
    }


def require_gap_recovery_hint(
    label: str,
    payload: Any,
    *,
    room_id: str,
    session_id: str,
    target_client_id: str,
    last_acked_game_event_id: Any,
    last_seen_state_version: int,
) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        raise RuntimeError(f"{label} must be an object, got {payload!r}")
    require_equal(f"{label}.artifactVersion", payload.get("artifactVersion"), "gapRecoveryHint.v1")
    transport_flag = require_present(f"{label}.transportFlag", payload.get("transportFlag"))
    require_equal(f"{label}.transportFlag.name", transport_flag["name"], "gapDetected")
    require_equal(f"{label}.transportFlag.value", transport_flag["value"], True)
    require_equal(f"{label}.inputLockRequired", payload.get("inputLockRequired"), True)
    require_equal(f"{label}.roomId", payload.get("roomId"), room_id)
    require_equal(f"{label}.sessionId", payload.get("sessionId"), session_id)
    require_equal(f"{label}.targetClientId", payload.get("targetClientId"), target_client_id)
    require_equal(f"{label}.lastAckedGameEventId", payload.get("lastAckedGameEventId"), last_acked_game_event_id)
    require_equal(f"{label}.lastSeenStateVersion", payload.get("lastSeenStateVersion"), last_seen_state_version)
    require_present(f"{label}.authoritativeEventId", payload.get("authoritativeEventId"))
    require_present(f"{label}.authoritativeStateVersion", payload.get("authoritativeStateVersion"))
    require_equal(f"{label}.snapshotReason", payload.get("snapshotReason"), "gapDetected")
    recovery_envelope = require_present(f"{label}.recoveryEnvelope", payload.get("recoveryEnvelope"))
    require_equal(f"{label}.recoveryEnvelope.type", recovery_envelope["type"], "gameEvent")
    require_equal(f"{label}.recoveryEnvelope.eventName", recovery_envelope["eventName"], "stateSnapshot")
    require_equal(f"{label}.recoveryEnvelope.reason", recovery_envelope["reason"], "gapDetected")
    return {
        "artifactVersion": payload["artifactVersion"],
        "transportFlag": dict(transport_flag),
        "inputLockRequired": payload["inputLockRequired"],
        "roomId": payload["roomId"],
        "sessionId": payload["sessionId"],
        "targetClientId": payload["targetClientId"],
        "lastAckedGameEventId": payload.get("lastAckedGameEventId"),
        "lastSeenStateVersion": payload["lastSeenStateVersion"],
        "authoritativeEventId": payload["authoritativeEventId"],
        "authoritativeStateVersion": payload["authoritativeStateVersion"],
        "snapshotReason": payload["snapshotReason"],
        "recoveryEnvelope": dict(recovery_envelope),
    }


def require_action_executed(label: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    if payload.get("status") != "action executed":
        raise RuntimeError(f"{label} expected status=action executed, got {json.dumps(payload, ensure_ascii=False, indent=2)}")
    return payload


def transport_connect(
    client: CLIClient,
    *,
    client_id: str,
    room_id: str,
    session_id: str,
    player_id: str,
    device_id: str,
    resume_token: str,
) -> Dict[str, Any]:
    return require_ok(
        f"room_transport_connect({client_id})",
        client.send(
            "room_transport_connect",
            {
                "clientId": client_id,
                "roomId": room_id,
                "sessionId": session_id,
                "playerId": player_id,
                "deviceId": device_id,
                "resumeToken": resume_token,
            },
        ),
    )


def transport_send_ok(client: CLIClient, client_id: str, action: str, **kwargs: Any) -> Dict[str, Any]:
    payload: Dict[str, Any] = {"clientId": client_id, "action": action}
    payload.update(kwargs)
    return require_ok(
        f"room_transport_send({client_id}:{action})",
        client.send("room_transport_send", payload),
    )


def transport_receive(client: CLIClient, client_id: str) -> list[Dict[str, Any]]:
    data = require_ok(
        f"room_transport_receive({client_id})",
        client.send("room_transport_receive", {"clientId": client_id}),
    )
    envelopes = data["envelopes"]
    if not isinstance(envelopes, list):
        raise RuntimeError(f"room_transport_receive({client_id}) envelopes must be a list, got {envelopes!r}")
    return envelopes


def engine_event(envelope: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    if envelope.get("type") != "gameEvent":
        return None
    payload = envelope.get("payload")
    if not isinstance(payload, dict):
        return None
    event = payload.get("engineEvent")
    return event if isinstance(event, dict) else None


def engine_event_name(envelope: Dict[str, Any]) -> Optional[str]:
    event = engine_event(envelope)
    if isinstance(event, dict):
        name = event.get("eventName")
        return name if isinstance(name, str) else None
    return None


def frame_label(envelope: Dict[str, Any]) -> str:
    if envelope.get("type") == "roomEvent":
        payload = envelope.get("payload")
        if isinstance(payload, dict):
            event_payload = payload.get("payload") if isinstance(payload.get("payload"), dict) else payload
            event_name = event_payload.get("eventName")
            if isinstance(event_name, str):
                return event_name
        return "roomEvent"
    if envelope.get("type") == "gameEvent":
        return engine_event_name(envelope) or "gameEvent"
    return str(envelope.get("type"))


def contains_label_sequence(labels: list[str], required: list[str]) -> bool:
    required_index = 0
    for label in labels:
        if required_index >= len(required):
            break
        if label == required[required_index]:
            required_index += 1
    return required_index == len(required)


def find_engine_event(
    envelopes: list[Dict[str, Any]],
    *,
    event_name: Optional[str] = None,
    reason: Optional[str] = None,
    snapshot_only: bool = False,
) -> Dict[str, Any]:
    for envelope in envelopes:
        event = engine_event(envelope)
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


def snapshot_payload(event: Dict[str, Any]) -> Dict[str, Any]:
    payload = event.get("payload")
    if not isinstance(payload, dict):
        raise RuntimeError("Snapshot payload is missing.")
    return payload


def snapshot_state(event: Dict[str, Any]) -> Dict[str, Any]:
    state = snapshot_payload(event).get("state")
    if not isinstance(state, dict):
        raise RuntimeError("Snapshot state is missing.")
    return state


def snapshot_reason(event: Dict[str, Any]) -> Optional[str]:
    reason = snapshot_payload(event).get("reason")
    return reason if isinstance(reason, str) else None


def snapshot_state_version(event: Dict[str, Any]) -> int:
    payload = snapshot_payload(event)
    value = payload.get("snapshotStateVersion")
    if isinstance(value, int):
        return value
    state_version = snapshot_state(event).get("stateVersion")
    if isinstance(state_version, int):
        return state_version
    raise RuntimeError("Snapshot stateVersion is missing.")


def snapshot_id(event: Dict[str, Any]) -> str:
    value = snapshot_payload(event).get("snapshotId")
    if not isinstance(value, str):
        raise RuntimeError("Snapshot id is missing.")
    return value


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_json(path: Path, payload: Dict[str, Any] | list[Dict[str, Any]]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_ndjson(path: Path, rows: list[Dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def write_markdown(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def emit_summary(summary: Dict[str, Any]) -> None:
    print("[3/3] Flow completed")
    print()
    print("Summary")
    for key, value in summary.items():
        if key == "scenario":
            print(f"- scenario: {value}")
            continue
        if isinstance(value, list):
            print(f"- {key}:")
            for item in value:
                print(f"  {item}")
            continue
        print(f"- {key}: {value}")


def bootstrap_two_player_room(client: CLIClient) -> Dict[str, Any]:
    create_data = require_ok(
        "room_bootstrap_create",
        client.send(
            "room_bootstrap_create",
            {
                "hostPlayerId": "p1",
                "deviceId": "dev1",
                "roomType": "invite",
                "joinPolicy": "inviteCode",
            },
        ),
    )
    create_boundary = require_bootstrap_boundary(
        "room_bootstrap_create.bootstrapBoundary",
        create_data.get("bootstrapBoundary"),
        stage="createRoom",
        current_action="room_bootstrap_create",
        future_public_route="POST /api/multiplayer/rooms",
    )
    room_id = create_data["room"]["roomId"]
    host_session_id = create_data["session"]["sessionId"]
    invite_code = create_data["room"].get("inviteCode") or room_id

    lookup_data = require_ok(
        "room_bootstrap_lookup_invite",
        client.send(
            "room_bootstrap_lookup_invite",
            {
                "inviteCode": invite_code,
            },
        ),
    )
    lookup_boundary = require_bootstrap_boundary(
        "room_bootstrap_lookup_invite.bootstrapBoundary",
        lookup_data.get("bootstrapBoundary"),
        stage="lookupInvite",
        current_action="room_bootstrap_lookup_invite",
        future_public_route="GET /api/multiplayer/invites/{inviteCode}",
    )
    lookup_summary = require_present("room_bootstrap_lookup_invite.roomSummary", lookup_data.get("roomSummary"))
    require_equal("room_bootstrap_lookup_invite.roomSummary.roomId", lookup_summary["roomId"], room_id)
    require_equal("room_bootstrap_lookup_invite.roomSummary.inviteCode", lookup_summary["inviteCode"], invite_code)
    require_equal("room_bootstrap_lookup_invite.roomSummary.memberCount", lookup_summary["memberCount"], 1)
    require_equal("room_bootstrap_lookup_invite.roomSummary.availableSeatCount", lookup_summary["availableSeatCount"], 1)
    require_equal("room_bootstrap_lookup_invite.roomSummary.canJoin", lookup_summary["canJoin"], True)

    join_data = require_ok(
        "room_bootstrap_join",
        client.send(
            "room_bootstrap_join",
            {
                "roomId": room_id,
                "playerId": "p2",
                "deviceId": "dev2",
            },
        ),
    )
    join_boundary = require_bootstrap_boundary(
        "room_bootstrap_join.bootstrapBoundary",
        join_data.get("bootstrapBoundary"),
        stage="joinRoom",
        current_action="room_bootstrap_join",
        future_public_route="POST /api/multiplayer/rooms/{roomId}/join",
    )
    guest_session_id = join_data["session"]["sessionId"]

    host_hello = require_ok(
        "room_hello(host)",
        client.send(
            "room_hello",
            {
                "roomId": room_id,
                "sessionId": host_session_id,
                "playerId": "p1",
                "deviceId": "dev1",
                "connectionId": "conn_host_001",
                "resumeToken": create_data["session"]["resumeToken"],
            },
        ),
    )
    guest_hello = require_ok(
        "room_hello(guest)",
        client.send(
            "room_hello",
            {
                "roomId": room_id,
                "sessionId": guest_session_id,
                "playerId": "p2",
                "deviceId": "dev2",
                "connectionId": "conn_guest_001",
                "resumeToken": join_data["session"]["resumeToken"],
            },
        ),
    )

    return {
        "room_id": room_id,
        "host_session_id": host_session_id,
        "guest_session_id": guest_session_id,
        "host_hello": host_hello,
        "guest_hello": guest_hello,
        "host_resume_token": host_hello["helloAck"]["resumeToken"],
        "guest_resume_token": guest_hello["helloAck"]["resumeToken"],
        "invite_code": invite_code,
        "bootstrapBoundary": {
            "create": create_boundary,
            "lookupInvite": lookup_boundary,
            "join": join_boundary,
        },
        "lookupInviteSummary": lookup_summary,
    }


def probe_bootstrap_facade(client: CLIClient) -> Dict[str, Any]:
    create_data = require_ok(
        "room_bootstrap_create(probe)",
        client.send(
            "room_bootstrap_create",
            {
                "hostPlayerId": "p1",
                "deviceId": "probe_dev1",
                "roomType": "invite",
                "joinPolicy": "inviteCode",
            },
        ),
    )
    create_boundary = require_bootstrap_boundary(
        "room_bootstrap_create(probe).bootstrapBoundary",
        create_data.get("bootstrapBoundary"),
        stage="createRoom",
        current_action="room_bootstrap_create",
        future_public_route="POST /api/multiplayer/rooms",
    )
    room_id = create_data["room"]["roomId"]
    invite_code = create_data["room"].get("inviteCode") or room_id

    lookup_data = require_ok(
        "room_bootstrap_lookup_invite(probe)",
        client.send(
            "room_bootstrap_lookup_invite",
            {
                "inviteCode": invite_code,
            },
        ),
    )
    lookup_boundary = require_bootstrap_boundary(
        "room_bootstrap_lookup_invite(probe).bootstrapBoundary",
        lookup_data.get("bootstrapBoundary"),
        stage="lookupInvite",
        current_action="room_bootstrap_lookup_invite",
        future_public_route="GET /api/multiplayer/invites/{inviteCode}",
    )
    lookup_summary = require_present(
        "room_bootstrap_lookup_invite(probe).roomSummary",
        lookup_data.get("roomSummary"),
    )
    require_equal("room_bootstrap_lookup_invite(probe).roomId", lookup_summary["roomId"], room_id)
    require_equal("room_bootstrap_lookup_invite(probe).inviteCode", lookup_summary["inviteCode"], invite_code)
    require_equal("room_bootstrap_lookup_invite(probe).memberCount", lookup_summary["memberCount"], 1)
    require_equal(
        "room_bootstrap_lookup_invite(probe).availableSeatCount",
        lookup_summary["availableSeatCount"],
        1,
    )
    require_equal("room_bootstrap_lookup_invite(probe).canJoin", lookup_summary["canJoin"], True)

    join_data = require_ok(
        "room_bootstrap_join(probe)",
        client.send(
            "room_bootstrap_join",
            {
                "roomId": room_id,
                "playerId": "p2",
                "deviceId": "probe_dev2",
            },
        ),
    )
    join_boundary = require_bootstrap_boundary(
        "room_bootstrap_join(probe).bootstrapBoundary",
        join_data.get("bootstrapBoundary"),
        stage="joinRoom",
        current_action="room_bootstrap_join",
        future_public_route="POST /api/multiplayer/rooms/{roomId}/join",
    )

    require_ok(
        "room_set_ready(probe_host)",
        client.send("room_set_ready", {"roomId": room_id, "playerId": "p1", "ready": True}),
    )
    require_ok(
        "room_set_ready(probe_guest)",
        client.send("room_set_ready", {"roomId": room_id, "playerId": "p2", "ready": True}),
    )

    gap_recovery_shape = require_gap_recovery_shape(
        "room_gap_recovery_shape",
        require_ok("room_gap_recovery_shape", client.send("room_gap_recovery_shape")),
    )

    game_id = f"{room_id}_bootstrap_facade_game_001"
    prepare_data = require_ok(
        "room_bootstrap_prepare_game_start",
        client.send(
            "room_bootstrap_prepare_game_start",
            {
                "roomId": room_id,
                "gameId": game_id,
            },
        ),
    )
    prepare_boundary = require_bootstrap_boundary(
        "room_bootstrap_prepare_game_start.bootstrapBoundary",
        prepare_data.get("bootstrapBoundary"),
        stage="prepareGameStart",
        current_action="room_bootstrap_prepare_game_start",
        future_public_route="POST /api/multiplayer/rooms/{roomId}/bootstrap/game-start",
    )
    mutation = require_present("room_bootstrap_prepare_game_start.mutation", prepare_data.get("mutation"))
    mutation_room = require_present("room_bootstrap_prepare_game_start.mutation.snapshot.room", mutation["snapshot"]["room"])
    require_equal("room_bootstrap_prepare_game_start.roomState", mutation_room["roomState"], "inGame")
    require_equal("room_bootstrap_prepare_game_start.activeGameId", mutation_room["activeGameId"], game_id)

    bootstrap_by_player = require_present(
        "room_bootstrap_prepare_game_start.bootstrapByPlayerId",
        prepare_data.get("bootstrapByPlayerId"),
    )
    paired_bootstrap: Dict[str, Dict[str, Any]] = {}
    for room_player_id in ("p1", "p2"):
        bootstrap = require_present(f"bootstrapByPlayerId.{room_player_id}", bootstrap_by_player.get(room_player_id))
        game_started = require_present(f"bootstrapByPlayerId.{room_player_id}.gameStarted", bootstrap.get("gameStarted"))
        state_snapshot = require_present(f"bootstrapByPlayerId.{room_player_id}.stateSnapshot", bootstrap.get("stateSnapshot"))
        state = require_present(f"bootstrapByPlayerId.{room_player_id}.stateSnapshot.state", state_snapshot.get("state"))
        require_equal(f"bootstrapByPlayerId.{room_player_id}.snapshotReason", state_snapshot["reason"], "gameStarted")
        require_equal(
            f"bootstrapByPlayerId.{room_player_id}.snapshotIdPair",
            game_started["snapshotId"],
            state_snapshot["snapshotId"],
        )
        require_equal(
            f"bootstrapByPlayerId.{room_player_id}.snapshotStateVersionPair",
            game_started["snapshotStateVersion"],
            state_snapshot["snapshotStateVersion"],
        )
        require_equal(f"bootstrapByPlayerId.{room_player_id}.state.roomId", state["roomId"], room_id)
        require_equal(f"bootstrapByPlayerId.{room_player_id}.state.gameId", state["gameId"], game_id)
        paired_bootstrap[room_player_id] = {
            "viewerPlayerId": state["viewerPlayerId"],
            "snapshotId": state_snapshot["snapshotId"],
            "snapshotReason": state_snapshot["reason"],
            "snapshotStateVersion": state_snapshot["snapshotStateVersion"],
            "stateVersion": state.get("stateVersion"),
        }

    return {
        "roomId": room_id,
        "gameId": game_id,
        "createBoundary": create_boundary,
        "lookupInviteBoundary": lookup_boundary,
        "lookupInviteSummary": dict(lookup_summary),
        "joinBoundary": join_boundary,
        "prepareGameStartBoundary": prepare_boundary,
        "pairedBootstrap": paired_bootstrap,
        "gapRecoveryShape": gap_recovery_shape,
    }


def set_both_ready(client: CLIClient, room_id: str) -> Dict[str, Any]:
    host_ready = require_ok(
        "room_set_ready(host)",
        client.send(
            "room_set_ready",
            {
                "roomId": room_id,
                "playerId": "p1",
                "ready": True,
            },
        ),
    )
    guest_ready = require_ok(
        "room_set_ready(guest)",
        client.send(
            "room_set_ready",
            {
                "roomId": room_id,
                "playerId": "p2",
                "ready": True,
            },
        ),
    )
    snapshot_data = require_ok(
        "room_snapshot",
        client.send("room_snapshot", {"roomId": room_id}),
    )
    return {
        "host_ready": host_ready,
        "guest_ready": guest_ready,
        "snapshot": snapshot_data["snapshot"],
    }


def record_game_started_and_fetch_bootstrap(client: CLIClient, room_id: str) -> Dict[str, Any]:
    game_id = f"{room_id}_game_001"

    record_data = require_ok(
        "room_record_game_started",
        client.send(
            "room_record_game_started",
            {
                "roomId": room_id,
                "gameId": game_id,
            },
        ),
    )
    room_snapshot = require_ok(
        "room_snapshot(after_game_started)",
        client.send("room_snapshot", {"roomId": room_id}),
    )["snapshot"]
    metadata = record_data["metadata"]
    bootstrap_plan = require_present("gameStartedBootstrapPlan", metadata.get("gameStartedBootstrapPlan"))
    require_equal(
        "gameStartControlMode",
        metadata["gameStartControlMode"],
        "explicitRecordGameStarted",
    )
    require_equal(
        "gameStartedBootstrapPlan.controlMode",
        bootstrap_plan["controlMode"],
        "explicitRecordGameStarted",
    )
    require_equal(
        "gameStartedBootstrapPlan.fetchAction",
        bootstrap_plan["fetchAction"],
        "get_multiplayer_game_started_bootstrap",
    )
    requests_by_player = bootstrap_plan["requestsByPlayerId"]
    bootstrap_request = require_present("gameStartedBootstrapPlan.requestsByPlayerId.p1", requests_by_player.get("p1"))
    bootstrap = require_ok_response(
        bootstrap_plan["fetchAction"],
        client.send(
            bootstrap_plan["fetchAction"],
            bootstrap_request,
        ),
    )

    room = room_snapshot["room"]
    require_equal("room_record_game_started.action", record_data["action"], "recordGameStarted")
    require_equal("room_state_after_game_started", room["roomState"], "inGame")
    require_equal("active_game_id", room["activeGameId"], game_id)

    events = record_data["events"]
    if len(events) != 1:
        raise RuntimeError(f"room_record_game_started should emit exactly one room event, got {len(events)}")
    event_payload = events[0]["payload"]
    require_equal("record_game_started.eventName", event_payload["eventName"], "roomStateChanged")
    require_equal("record_game_started.toState", event_payload["toState"], "inGame")
    require_equal("record_game_started.reason", event_payload["reason"], "gameStarted")

    game_started = bootstrap["gameStarted"]
    state_snapshot = bootstrap["stateSnapshot"]
    state = state_snapshot["state"]

    require_equal("bootstrap.snapshot_reason", state_snapshot["reason"], "gameStarted")
    require_equal("bootstrap.snapshot_id_pair", game_started["snapshotId"], state_snapshot["snapshotId"])
    require_equal(
        "bootstrap.snapshot_state_version_pair",
        game_started["snapshotStateVersion"],
        state_snapshot["snapshotStateVersion"],
    )
    require_equal("bootstrap.state.roomId", state["roomId"], room_id)
    require_equal("bootstrap.state.gameId", state["gameId"], game_id)
    require_present("bootstrap.state.viewerPlayerId", state.get("viewerPlayerId"))
    require_equal("bootstrap.snapshot.scope", state_snapshot["scope"], bootstrap_request["projectionScope"])
    require_equal("bootstrap.state.stateVersion", state["stateVersion"], bootstrap_request["stateVersionHint"])
    require_present("bootstrap.state.currentPlayerId", state.get("currentPlayerId"))
    require_present("bootstrap.state.turnId", state.get("turnId"))

    return {
        "game_id": game_id,
        "bootstrapFetchAction": bootstrap_plan["fetchAction"],
        "bootstrapViewerPlayerId": bootstrap_request["viewerPlayerId"],
        "bootstrapProjectionScope": bootstrap_request["projectionScope"],
        "snapshot_id": state_snapshot["snapshotId"],
        "snapshot_reason": state_snapshot["reason"],
        "snapshot_state_version": state_snapshot["snapshotStateVersion"],
        "state_version": state["stateVersion"],
        "turn_id": state.get("turnId"),
        "current_player_id": state.get("currentPlayerId"),
        "room_state": room["roomState"],
        "active_game_id": room["activeGameId"],
        "last_room_sequence": room["lastRoomSequence"],
        "record_action": record_data["action"],
        "record_event_name": event_payload["eventName"],
        "record_reason": event_payload["reason"],
    }


def bootstrap_transport_live_match(client: CLIClient) -> Dict[str, Any]:
    bootstrap = bootstrap_two_player_room(client)
    room_id = bootstrap["room_id"]
    game_id = f"{room_id}_transport_game_001"
    require_action_executed("start_game", client.send("start_game"))

    transport_connect(
        client,
        client_id="host_client",
        room_id=room_id,
        session_id=bootstrap["host_session_id"],
        player_id="p1",
        device_id="dev1",
        resume_token=bootstrap["host_resume_token"],
    )
    transport_connect(
        client,
        client_id="guest_client",
        room_id=room_id,
        session_id=bootstrap["guest_session_id"],
        player_id="p2",
        device_id="dev2",
        resume_token=bootstrap["guest_resume_token"],
    )

    transport_send_ok(client, "host_client", "hello", connectionId="conn_host_transport_001")
    host_hello = transport_receive(client, "host_client")
    transport_send_ok(client, "guest_client", "hello", connectionId="conn_guest_transport_001")
    guest_hello = transport_receive(client, "guest_client")
    require_equal("host transport hello ordering", [frame["type"] for frame in host_hello[:2]], ["helloAck", "roomSnapshot"])
    require_equal("guest transport hello ordering", [frame["type"] for frame in guest_hello[:2]], ["helloAck", "roomSnapshot"])

    transport_send_ok(client, "host_client", "setReady", ready=True)
    host_after_host_ready = transport_receive(client, "host_client")
    guest_after_host_ready = transport_receive(client, "guest_client")
    transport_send_ok(client, "guest_client", "setReady", ready=True)
    host_after_guest_ready = transport_receive(client, "host_client")
    guest_after_guest_ready = transport_receive(client, "guest_client")
    ready_labels = [frame_label(frame) for frame in host_after_guest_ready + guest_after_guest_ready]
    if "roomStateChanged" not in ready_labels:
        raise RuntimeError(f"transport ready path is missing roomStateChanged after both players ready: {ready_labels!r}")

    gap_recovery_shape = require_gap_recovery_shape(
        "room_gap_recovery_shape(transport)",
        require_ok("room_gap_recovery_shape(transport)", client.send("room_gap_recovery_shape")),
    )
    start_data = transport_send_ok(
        client,
        "host_client",
        "recordGameStartedAndPrepareBootstrap",
        gameId=game_id,
    )
    host_live = transport_receive(client, "host_client")
    guest_live = transport_receive(client, "guest_client")
    host_state_snapshot = find_engine_event(
        host_live,
        event_name="stateSnapshot",
        reason="gameStarted",
        snapshot_only=True,
    )
    guest_state_snapshot = find_engine_event(
        guest_live,
        event_name="stateSnapshot",
        reason="gameStarted",
        snapshot_only=True,
    )

    if not contains_label_sequence([frame_label(frame) for frame in host_live], ["roomStateChanged", "gameStarted", "stateSnapshot"]):
        raise RuntimeError(f"host transport bootstrap ordering diverged: {[frame_label(frame) for frame in host_live]!r}")
    if not contains_label_sequence([frame_label(frame) for frame in guest_live], ["roomStateChanged", "gameStarted", "stateSnapshot"]):
        raise RuntimeError(f"guest transport bootstrap ordering diverged: {[frame_label(frame) for frame in guest_live]!r}")

    return {
        "bootstrap": bootstrap,
        "room_id": room_id,
        "game_id": game_id,
        "gapRecoveryShape": gap_recovery_shape,
        "host_hello": host_hello,
        "guest_hello": guest_hello,
        "host_live": host_live,
        "guest_live": guest_live,
        "host_state_snapshot": host_state_snapshot,
        "guest_state_snapshot": guest_state_snapshot,
        "authoritative_state_version": snapshot_state_version(host_state_snapshot),
        "authoritative_event_id": start_data["authoritativeEventId"],
        "last_room_sequence": require_ok("room_snapshot(after transport bootstrap)", client.send("room_snapshot", {"roomId": room_id}))["snapshot"]["room"]["lastRoomSequence"],
    }


def run_ready_start_scenario(client: CLIClient) -> Dict[str, Any]:
    facade_probe = probe_bootstrap_facade(client)
    bootstrap = bootstrap_two_player_room(client)
    ready_phase = set_both_ready(client, bootstrap["room_id"])
    room_snapshot = ready_phase["snapshot"]["room"]
    metadata = ready_phase["guest_ready"]["metadata"]
    game_started_phase = record_game_started_and_fetch_bootstrap(client, bootstrap["room_id"])
    summary = {
        "scenario": "ready-start",
        "roomId": bootstrap["room_id"],
        "hostSessionId": bootstrap["host_session_id"],
        "guestSessionId": bootstrap["guest_session_id"],
        "hostHelloResumeMode": bootstrap["host_hello"]["helloAck"]["resumeMode"],
        "guestHelloResumeMode": bootstrap["guest_hello"]["helloAck"]["resumeMode"],
        "roomStateAfterReady": room_snapshot["roomState"],
        "requiresGameBootstrap": metadata["requiresGameBootstrap"],
        "bootstrapFacadeProbe": "PASS",
        "bootstrapFacadeCreateStage": bootstrap["bootstrapBoundary"]["create"]["stage"],
        "bootstrapFacadeLookupStage": bootstrap["bootstrapBoundary"]["lookupInvite"]["stage"],
        "bootstrapFacadeJoinStage": bootstrap["bootstrapBoundary"]["join"]["stage"],
        "bootstrapFacadePrepareStage": facade_probe["prepareGameStartBoundary"]["stage"],
        "bootstrapFacadeSurfaceKind": bootstrap["bootstrapBoundary"]["create"]["surfaceKind"],
        "bootstrapFacadeBoundaryVersion": bootstrap["bootstrapBoundary"]["create"]["boundaryVersion"],
        "bootstrapFacadeCurrentBoundary": bootstrap["bootstrapBoundary"]["create"]["currentBoundary"],
        "bootstrapFacadeLookupInviteCode": bootstrap["invite_code"],
        "bootstrapFacadeLookupSummaryCanJoin": bootstrap["lookupInviteSummary"]["canJoin"],
        "bootstrapFacadeLookupRecommendedNext": bootstrap["bootstrapBoundary"]["lookupInvite"]["recommendedNextActions"],
        "bootstrapFacadeGapRecoveryShapeAction": bootstrap["bootstrapBoundary"]["create"]["gapRecoveryShapeAction"],
        "bootstrapFacadeGapRecovery": bootstrap["bootstrapBoundary"]["create"]["gapRecovery"],
        "bootstrapFacadeGameplayBoundary": bootstrap["bootstrapBoundary"]["create"]["gameplayTransportBoundary"],
        "bootstrapFacadePrepareSnapshotReason": facade_probe["pairedBootstrap"]["p1"]["snapshotReason"],
        "bootstrapFacadePrepareSnapshotId": facade_probe["pairedBootstrap"]["p1"]["snapshotId"],
        "bootstrapFacadePrepareRecommendedNext": facade_probe["prepareGameStartBoundary"]["recommendedNextActions"],
        "roomRecordGameStartedAction": game_started_phase["record_action"],
        "gameStartedRoomEventName": game_started_phase["record_event_name"],
        "gameStartedRoomEventReason": game_started_phase["record_reason"],
        "bootstrapFetchAction": game_started_phase["bootstrapFetchAction"],
        "bootstrapViewerPlayerId": game_started_phase["bootstrapViewerPlayerId"],
        "bootstrapProjectionScope": game_started_phase["bootstrapProjectionScope"],
        "roomStateAfterGameStarted": game_started_phase["room_state"],
        "activeGameId": game_started_phase["active_game_id"],
        "bootstrapSnapshotId": game_started_phase["snapshot_id"],
        "bootstrapSnapshotReason": game_started_phase["snapshot_reason"],
        "bootstrapSnapshotStateVersion": game_started_phase["snapshot_state_version"],
        "bootstrapStateVersion": game_started_phase["state_version"],
        "bootstrapTurnId": game_started_phase["turn_id"],
        "bootstrapCurrentPlayerId": game_started_phase["current_player_id"],
        "pairedBootstrapAssert": "PASS",
        "pairedBootstrapCoverage": (
            "Explicit CLI sequence: room_bootstrap_create/join facade -> room_record_game_started -> "
            "room_snapshot(inGame) -> metadata.gameStartedBootstrapPlan.fetchAction, plus "
            "room_bootstrap_prepare_game_start preflight boundary."
        ),
        "lastRoomSequence": game_started_phase["last_room_sequence"],
        "members": [
            f"{member['playerId']} seat={member['seat']} role={member['role']} ready={member['ready']} "
            f"presence={member['presence']} connectionId={member['connectedConnectionId']}"
            for member in room_snapshot["members"]
        ],
    }
    emit_summary(summary)
    return summary


def run_disconnect_resume_scenario(client: CLIClient) -> Dict[str, Any]:
    bootstrap = bootstrap_two_player_room(client)
    ready_phase = set_both_ready(client, bootstrap["room_id"])

    require_ok(
        "room_disconnect(guest)",
        client.send(
            "room_disconnect",
            {
                "roomId": bootstrap["room_id"],
                "playerId": "p2",
            },
        ),
    )
    disconnected_snapshot = require_ok(
        "room_snapshot(after_disconnect)",
        client.send("room_snapshot", {"roomId": bootstrap["room_id"]}),
    )["snapshot"]

    resume_data = require_ok(
        "room_hello(guest_resume)",
        client.send(
            "room_hello",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "playerId": "p2",
                "deviceId": "dev2",
                "connectionId": "conn_guest_002",
                "resumeToken": bootstrap["guest_resume_token"],
                "lastSeen": {
                    "roomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
                },
            },
        ),
    )

    heartbeat_data = require_ok(
        "room_heartbeat(guest_resumed)",
        client.send(
            "room_heartbeat",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "connectionId": "conn_guest_002",
                "lastAckedRoomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
            },
        ),
    )

    resumed_snapshot = require_ok(
        "room_snapshot(after_resume)",
        client.send("room_snapshot", {"roomId": bootstrap["room_id"]}),
    )["snapshot"]

    disconnected_member = next(
        member for member in disconnected_snapshot["room"]["members"] if member["playerId"] == "p2"
    )
    resumed_member = next(member for member in resumed_snapshot["room"]["members"] if member["playerId"] == "p2")

    summary = {
        "scenario": "disconnect-resume",
        "roomId": bootstrap["room_id"],
        "guestSessionId": bootstrap["guest_session_id"],
        "roomStateBeforeDisconnect": ready_phase["snapshot"]["room"]["roomState"],
        "guestPresenceAfterDisconnect": disconnected_member["presence"],
        "guestConnectionIdAfterDisconnect": disconnected_member["connectedConnectionId"],
        "guestResumeHelloMode": resume_data["helloAck"]["resumeMode"],
        "rotatedResumeTokenIssued": resume_data["helloAck"]["resumeToken"],
        "guestPresenceAfterResume": resumed_member["presence"],
        "guestConnectionIdAfterResume": resumed_member["connectedConnectionId"],
        "roomStateAfterResume": resumed_snapshot["room"]["roomState"],
        "heartbeatAcceptedAction": heartbeat_data["action"],
        "lastRoomSequenceAfterResume": resumed_snapshot["room"]["lastRoomSequence"],
    }
    emit_summary(summary)
    return summary


def run_heartbeat_guard_scenario(client: CLIClient) -> Dict[str, Any]:
    bootstrap = bootstrap_two_player_room(client)
    ready_phase = set_both_ready(client, bootstrap["room_id"])

    require_ok(
        "room_disconnect(guest)",
        client.send(
            "room_disconnect",
            {
                "roomId": bootstrap["room_id"],
                "playerId": "p2",
            },
        ),
    )
    disconnected_snapshot = require_ok(
        "room_snapshot(after_disconnect)",
        client.send("room_snapshot", {"roomId": bootstrap["room_id"]}),
    )["snapshot"]

    disconnected_heartbeat = require_error(
        "room_heartbeat(guest_disconnected)",
        client.send(
            "room_heartbeat",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "connectionId": "conn_guest_001",
                "lastAckedRoomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
            },
        ),
        expected_code="invalidResumeState",
    )

    resume_data = require_ok(
        "room_hello(guest_resume)",
        client.send(
            "room_hello",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "playerId": "p2",
                "deviceId": "dev2",
                "connectionId": "conn_guest_002",
                "resumeToken": bootstrap["guest_resume_token"],
                "lastSeen": {
                    "roomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
                },
            },
        ),
    )

    stale_heartbeat = require_error(
        "room_heartbeat(guest_stale_connection)",
        client.send(
            "room_heartbeat",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "connectionId": "conn_guest_001",
                "lastAckedRoomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
            },
        ),
        expected_code="staleConnectionId",
    )

    accepted_heartbeat = require_ok(
        "room_heartbeat(guest_current_connection)",
        client.send(
            "room_heartbeat",
            {
                "roomId": bootstrap["room_id"],
                "sessionId": bootstrap["guest_session_id"],
                "connectionId": "conn_guest_002",
                "lastAckedRoomSequence": disconnected_snapshot["room"]["lastRoomSequence"],
            },
        ),
    )

    resumed_snapshot = require_ok(
        "room_snapshot(after_heartbeat_guard)",
        client.send("room_snapshot", {"roomId": bootstrap["room_id"]}),
    )["snapshot"]
    resumed_member = next(member for member in resumed_snapshot["room"]["members"] if member["playerId"] == "p2")

    summary = {
        "scenario": "heartbeat-guard",
        "roomId": bootstrap["room_id"],
        "cliIngressBaselineCommand": "room_heartbeat",
        "roomStateBeforeDisconnect": ready_phase["snapshot"]["room"]["roomState"],
        "disconnectedHeartbeatErrorCode": disconnected_heartbeat["errorCode"],
        "resumeHelloMode": resume_data["helloAck"]["resumeMode"],
        "staleHeartbeatErrorCode": stale_heartbeat["errorCode"],
        "acceptedHeartbeatAction": accepted_heartbeat["action"],
        "guestCurrentConnectionId": resumed_member["connectedConnectionId"],
        "guestPresenceAfterGuardChecks": resumed_member["presence"],
        "lastRoomSequenceAfterGuardChecks": resumed_snapshot["room"]["lastRoomSequence"],
    }
    emit_summary(summary)
    return summary


def run_mp008_hook_surface_scenario(client: CLIClient) -> Dict[str, Any]:
    bootstrap = bootstrap_two_player_room(client)
    gap_recovery_shape = require_gap_recovery_shape(
        "room_gap_recovery_shape",
        require_ok("room_gap_recovery_shape", client.send("room_gap_recovery_shape")),
    )

    initial_hook = require_ok(
        "room_get_mp008_hook(initial)",
        client.send("room_get_mp008_hook"),
    )["hook"]
    if initial_hook is not None:
        raise RuntimeError(f"room_get_mp008_hook(initial) expected null hook, got {initial_hook!r}")

    set_data = require_ok(
        "room_set_mp008_hook",
        client.send(
            "room_set_mp008_hook",
            {
                "targetSessionId": bootstrap["guest_session_id"],
                "overriddenExpectedStateVersion": 14,
            },
        ),
    )
    hook = set_data["hook"]
    require_equal("mp008_hook.kind", hook["kind"], "staleExpectedStateVersionOverride")
    require_equal("mp008_hook.targetSessionId", hook["targetSessionId"], bootstrap["guest_session_id"])
    require_equal("mp008_hook.overriddenExpectedStateVersion", hook["overriddenExpectedStateVersion"], 14)

    get_data = require_ok(
        "room_get_mp008_hook(after_set)",
        client.send("room_get_mp008_hook"),
    )
    require_equal("room_get_mp008_hook.kind", get_data["hook"]["kind"], "staleExpectedStateVersionOverride")
    require_equal(
        "room_get_mp008_hook.targetSessionId",
        get_data["hook"]["targetSessionId"],
        bootstrap["guest_session_id"],
    )
    require_equal(
        "room_get_mp008_hook.overriddenExpectedStateVersion",
        get_data["hook"]["overriddenExpectedStateVersion"],
        14,
    )

    cleared = require_ok(
        "room_clear_mp008_hook",
        client.send("room_clear_mp008_hook"),
    )
    if cleared["hook"] is not None:
        raise RuntimeError(f"room_clear_mp008_hook expected null hook, got {cleared['hook']!r}")

    summary = {
        "scenario": "mp008-hook-surface",
        "roomId": bootstrap["room_id"],
        "targetSessionId": bootstrap["guest_session_id"],
        "hookKind": hook["kind"],
        "overriddenExpectedStateVersion": hook["overriddenExpectedStateVersion"],
        "gapRecoveryShapeMode": gap_recovery_shape["mode"],
        "gapRecoveryTransportFlag": gap_recovery_shape["transportFlag"]["name"],
        "gapRecoveryHintName": gap_recovery_shape["artifact"]["name"],
        "gapRecoveryHintMinimumFields": gap_recovery_shape["artifact"]["minimumFields"],
        "gapRecoverySnapshotReason": gap_recovery_shape["recoveryEnvelope"]["reason"],
        "hookLifecycle": "set -> get -> clear",
        "clearResult": "nil",
    }
    emit_summary(summary)
    return summary



def run_mp008_gameplay_resync_scenario(client: CLIClient) -> Dict[str, Any]:
    transport_boot = bootstrap_transport_live_match(client)
    room_id = transport_boot["room_id"]
    gap_recovery_shape = transport_boot["gapRecoveryShape"]
    client_state_version = max(0, transport_boot["authoritative_state_version"] - 1)
    gap_send = transport_send_ok(
        client,
        "host_client",
        "triggerGapRecovery",
        requestId="req_cli_mp008_gap_001",
        actionId="act_cli_mp008_gap_001",
        expectedStateVersion=client_state_version,
        lastEventId=transport_boot["authoritative_event_id"],
        lastSeen={
            "roomSequence": transport_boot["last_room_sequence"],
            "gameEventId": transport_boot["authoritative_event_id"],
            "stateVersion": client_state_version,
        },
    )
    host_gap_frames = transport_receive(client, "host_client")
    guest_gap_frames = transport_receive(client, "guest_client")
    host_gap_labels = [frame_label(frame) for frame in host_gap_frames]
    if not contains_label_sequence(host_gap_labels, ["gapRecoveryHint", "stateSnapshot"]):
        raise RuntimeError(
            "CLI live gap recovery ordering diverged. "
            f"expected gapRecoveryHint -> stateSnapshot, got {host_gap_labels!r}"
        )
    gap_hint_frame = next((frame for frame in host_gap_frames if frame.get("type") == "gapRecoveryHint"), None)
    if not isinstance(gap_hint_frame, dict):
        raise RuntimeError("CLI live gap recovery is missing a gapRecoveryHint envelope.")
    gap_hint = require_gap_recovery_hint(
        "gapRecoveryHint(envelope)",
        gap_hint_frame.get("payload"),
        room_id=room_id,
        session_id=transport_boot["bootstrap"]["host_session_id"],
        target_client_id="host_client",
        last_acked_game_event_id=transport_boot["authoritative_event_id"],
        last_seen_state_version=client_state_version,
    )
    returned_gap_hint = require_gap_recovery_hint(
        "gapRecoveryHint(response)",
        gap_send.get("gapRecoveryHint"),
        room_id=room_id,
        session_id=transport_boot["bootstrap"]["host_session_id"],
        target_client_id="host_client",
        last_acked_game_event_id=transport_boot["authoritative_event_id"],
        last_seen_state_version=client_state_version,
    )
    require_equal("gapRecoveryHint response/envelope parity", returned_gap_hint, gap_hint)
    gap_snapshot = find_engine_event(
        host_gap_frames,
        event_name="stateSnapshot",
        reason="gapDetected",
        snapshot_only=True,
    )
    require_equal("gap snapshot eventId", gap_snapshot.get("eventId"), gap_hint["authoritativeEventId"])
    require_equal(
        "gap snapshot stateVersion",
        snapshot_state_version(gap_snapshot),
        gap_hint["authoritativeStateVersion"],
    )
    guest_gap_labels = [frame_label(frame) for frame in guest_gap_frames]
    if "gapRecoveryHint" in guest_gap_labels:
        raise RuntimeError(f"CLI live gap recovery leaked gapRecoveryHint to guest transport frames: {guest_gap_labels!r}")

    summary = {
        "scenario": "mp008-gameplay-resync",
        "roomId": room_id,
        "gameId": transport_boot["game_id"],
        "transportBootstrap": "PASS",
        "transportBootstrapAuthoritativeEventId": transport_boot["authoritative_event_id"],
        "transportBootstrapStateVersion": transport_boot["authoritative_state_version"],
        "gapRecoveryTransportAction": gap_recovery_shape["liveHook"]["transportAction"],
        "gapRecoveryEnvelopeType": gap_recovery_shape["liveHook"]["recoveryEnvelopeType"],
        "gapRecoveryHintArtifactVersion": gap_hint["artifactVersion"],
        "gapRecoveryHintTargetClientId": gap_hint["targetClientId"],
        "gapRecoveryHintLastAckedGameEventId": gap_hint["lastAckedGameEventId"],
        "gapRecoveryHintLastSeenStateVersion": gap_hint["lastSeenStateVersion"],
        "gapRecoveryHintAuthoritativeEventId": gap_hint["authoritativeEventId"],
        "gapRecoveryHintAuthoritativeStateVersion": gap_hint["authoritativeStateVersion"],
        "gapRecoverySnapshotReason": snapshot_reason(gap_snapshot),
        "gapRecoverySnapshotId": snapshot_id(gap_snapshot),
        "gapRecoverySnapshotStateVersion": snapshot_state_version(gap_snapshot),
        "hostGapLabels": host_gap_labels,
        "guestGapLabels": guest_gap_labels,
        "note": "Live CLI transport now executes triggerGapRecovery and asserts gapRecoveryHint plus stateSnapshot(reason=gapDetected).",
    }
    emit_summary(summary)
    return summary


def write_scenario_artifacts(run_root: Path, summary: Dict[str, Any], transcript: list[Dict[str, Any]]) -> None:
    scenario_root = ensure_dir(run_root / str(summary["scenario"]))
    write_json(scenario_root / "summary.json", summary)
    write_ndjson(scenario_root / "transcript.ndjson", transcript)
    markdown_lines = [f"# {summary['scenario']}", ""]
    for key, value in summary.items():
        if key == "scenario":
            continue
        if isinstance(value, list):
            markdown_lines.append(f"## {key}")
            markdown_lines.extend([f"- {item}" for item in value])
            markdown_lines.append("")
            continue
        markdown_lines.append(f"- {key}: {value}")
    write_markdown(scenario_root / "summary.md", markdown_lines)


def write_failure_artifacts(run_root: Path, scenario_name: str, transcript: list[Dict[str, Any]], error: Exception) -> None:
    scenario_root = ensure_dir(run_root / scenario_name)
    write_ndjson(scenario_root / "transcript.ndjson", transcript)
    write_markdown(
        scenario_root / "anomaly_report.md",
        [
            f"# {scenario_name} CLI Smoke Failure",
            "",
            f"- error: {error}",
            "",
            "## Traceback",
            "```text",
            traceback.format_exc().rstrip(),
            "```",
        ],
    )


def write_run_summary(run_root: Path, results: list[Dict[str, Any]]) -> None:
    payload = {"results": results}
    write_json(run_root / "run_summary.json", payload)
    lines = ["# Multiplayer CLI Smoke", ""]
    for result in results:
        lines.append(f"## {result['scenario']}")
        for key, value in result.items():
            if key == "scenario":
                continue
            if isinstance(value, list):
                lines.extend([f"- {key}: {item}" for item in value])
                continue
            lines.append(f"- {key}: {value}")
        lines.append("")
    write_markdown(run_root / "run_summary.md", lines)


def run_suite(client: CLIClient, scenario: str, output_root: Path) -> list[Dict[str, Any]]:
    ordered = [
        ("ready-start", run_ready_start_scenario),
        ("disconnect-resume", run_disconnect_resume_scenario),
        ("heartbeat-guard", run_heartbeat_guard_scenario),
        ("mp008-hook-surface", run_mp008_hook_surface_scenario),
        ("mp008-gameplay-resync", run_mp008_gameplay_resync_scenario),
    ]
    run_id = datetime.now().astimezone().strftime("cli_smoke_%Y%m%d_%H%M%S")
    run_root = ensure_dir(output_root / run_id)
    results: list[Dict[str, Any]] = []
    if scenario != "all":
        for name, handler in ordered:
            if name == scenario:
                start_index = client.history_index()
                try:
                    summary = handler(client)
                except Exception as error:
                    write_failure_artifacts(run_root, name, client.history_since(start_index), error)
                    raise
                write_scenario_artifacts(run_root, summary, client.history_since(start_index))
                results.append(summary)
                write_run_summary(run_root, results)
                print(f"Artifacts: {run_root}")
                return results
        raise RuntimeError(f"Unknown scenario: {scenario}")

    for index, (name, handler) in enumerate(ordered, start=1):
        print()
        print(f"=== [{index}/{len(ordered)}] {name} ===")
        start_index = client.history_index()
        try:
            summary = handler(client)
        except Exception as error:
            write_failure_artifacts(run_root, name, client.history_since(start_index), error)
            raise
        write_scenario_artifacts(run_root, summary, client.history_since(start_index))
        results.append(summary)

    write_run_summary(run_root, results)
    print()
    print(f"Artifacts: {run_root}")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a two-player multiplayer CLI smoke flow.")
    parser.add_argument(
        "--derived-data",
        default="/tmp/gostop_cli_two_player_smoke",
        help="DerivedData path for the GoStopCLI build.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip xcodebuild and use the binary at --binary directly.",
    )
    parser.add_argument(
        "--binary",
        help="Path to a prebuilt GoStopCLI binary.",
    )
    parser.add_argument(
        "--output-root",
        help="Directory to store smoke summaries and transcripts.",
    )
    parser.add_argument(
        "--final-validation",
        action="store_true",
        help="Use the frozen Round 17 validation artifact bucket when --output-root is omitted.",
    )
    parser.add_argument(
        "--scenario",
        choices=[
            "ready-start",
            "disconnect-resume",
            "heartbeat-guard",
            "mp008-hook-surface",
            "mp008-gameplay-resync",
            "all",
        ],
        default="ready-start",
        help="Which multiplayer smoke scenario to run.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    derived_data = Path(args.derived_data)

    output_root = (
        Path(args.output_root).resolve()
        if args.output_root
        else default_output_root(repo_root, final_validation=args.final_validation)
    )

    binary_path = resolve_binary(repo_root, derived_data, args.binary, args.skip_build)

    if not binary_path.exists():
        raise SystemExit(f"GoStopCLI binary not found: {binary_path}")

    print(f"[2/3] Launching {binary_path}")
    client = CLIClient(binary_path)

    try:
        run_suite(client, args.scenario, output_root)
    finally:
        client.close()


if __name__ == "__main__":
    main()
