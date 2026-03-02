#!/usr/bin/env python3
import argparse
import json
import os
import socket
import time
from datetime import datetime


def send_command(host: str, port: int, action: str, data=None, timeout: float = 5.0) -> dict:
    payload = {"action": action}
    if data is not None:
        payload["data"] = data

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect((host, port))
        sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))

        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
            if b"\n" in response:
                break

    if not response:
        raise RuntimeError(f"No response for action={action}")
    return json.loads(response.decode("utf-8").strip())


def find_duplicate_cards(state: dict) -> list[dict]:
    cards: list[tuple[str | None, str, int | None, str | None]] = []

    def add(items, location: str):
        for c in items or []:
            if isinstance(c, dict):
                cards.append((c.get("id"), location, c.get("month"), c.get("type")))

    add(state.get("tableCards"), "table")
    add(state.get("outOfPlayCards"), "outOfPlay")
    add(state.get("deckCards") or ((state.get("deck") or {}).get("cards")), "deck")
    for player in state.get("players", []):
        name = player.get("name", "player")
        add(player.get("hand"), f"{name}_hand")
        add(player.get("capturedCards"), f"{name}_captured")

    seen: dict[str, str] = {}
    duplicates: list[dict] = []
    for card_id, location, month, card_type in cards:
        if not card_id:
            continue
        if card_id in seen:
            duplicates.append(
                {
                    "id": card_id,
                    "month": month,
                    "type": card_type,
                    "loc1": seen[card_id],
                    "loc2": location,
                }
            )
        else:
            seen[card_id] = location
    return duplicates


def run_repro(host: str, port: int, poll_count: int, poll_interval: float, out_dir: str) -> dict:
    # Reset and configure deterministic steal-Pi animation case (Ttadak path).
    send_command(host, port, "click_restart_button")
    send_command(host, port, "start_game")
    send_command(
        host,
        port,
        "set_condition",
        {
            "currentTurnIndex": 0,
            "mock_hand": [{"month": 1, "type": "junk"}, {"month": 5, "type": "junk"}],
            "mock_table": [
                {"month": 1, "type": "junk"},
                {"month": 1, "type": "junk"},
                {"month": 9, "type": "animal"},
            ],
            "mock_deck": [{"month": 1, "type": "bright"}],
            "mock_gameState": "playing",
            "player0_data": {"isComputer": False},
            "player1_data": {"isComputer": False},
            "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}],
        },
    )

    send_command(host, port, "play_card", {"month": 1, "type": "junk"})

    snapshots = []
    start = time.time()
    for _ in range(poll_count):
        state = send_command(host, port, "get_state")
        snapshots.append(
            {
                "t": round(time.time() - start, 3),
                "gameState": state.get("gameState"),
                "move": f"{state.get('currentMoveSourceZone')}->{state.get('currentMoveTargetZone')}",
                "capturedMoveSourcePlayerId": state.get("capturedMoveSourcePlayerId"),
                "capturedMoveTargetPlayerId": state.get("capturedMoveTargetPlayerId"),
                "duplicates": find_duplicate_cards(state),
                "playerCapturedCounts": [
                    len(p.get("capturedCards", [])) for p in state.get("players", [])
                ],
            }
        )
        time.sleep(poll_interval)

    os.makedirs(out_dir, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = os.path.join(out_dir, f"transient_duplicate_pi_transfer_{ts}.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(snapshots, f, ensure_ascii=False, indent=2)

    dup_frames = [s for s in snapshots if s["duplicates"]]
    return {
        "output_path": output_path,
        "dup_frame_count": len(dup_frames),
        "first_dup": dup_frames[0] if dup_frames else None,
        "last_dup": dup_frames[-1] if dup_frames else None,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Reproduce transient duplicate card IDs during captured->captured Pi transfer animation."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--poll-count", type=int, default=140)
    parser.add_argument("--poll-interval", type=float, default=0.02)
    parser.add_argument("--out-dir", default="/tmp/gostop_case_extract_20260301")
    args = parser.parse_args()

    result = run_repro(
        host=args.host,
        port=args.port,
        poll_count=args.poll_count,
        poll_interval=args.poll_interval,
        out_dir=args.out_dir,
    )

    print(f"output_path={result['output_path']}")
    print(f"dup_frame_count={result['dup_frame_count']}")
    if result["first_dup"]:
        print(f"first_dup_t={result['first_dup']['t']}")
        print(f"first_dup_detail={result['first_dup']['duplicates']}")
        print(f"last_dup_t={result['last_dup']['t']}")
    else:
        print("first_dup_t=None")


if __name__ == "__main__":
    main()
