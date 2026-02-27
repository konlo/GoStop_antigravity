import json
import logging
import os
import sys
import time
import socket
import select
from datetime import datetime

# Configure Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger("UXMonitor")

class UXMonitor:
    def __init__(self, host="127.0.0.1", port=8080):
        self.host = host
        self.port = port
        self.is_paused = False
        self.history_index = -1
        self.history_count = 0
        self.processed_events = set()
        self.busy_since = time.time()
        self.pending_moves = {}

    def send_command(self, command):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2.0)
            s.connect((self.host, self.port))
            
            req_str = json.dumps(command) + "\n"
            s.sendall(req_str.encode('utf-8'))
            
            response_data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b"\n" in response_data:
                    break
            
            s.close()
            return json.loads(response_data.decode('utf-8').strip())
        except Exception as e:
            # Silent fail for regular polls to avoid terminal spam
            return None

    def get_state(self):
        return self.send_command({"action": "get_state"})

    def restore_state(self, index):
        return self.send_command({"action": "restore_state", "data": {"index": index}})

    def start_game(self):
        return self.send_command({"action": "click_start_button"})

    def reset_busy_state(self):
        return self.send_command({"action": "reset_busy_state"})

    def get_history_entry(self, index):
        resp = self.send_command({"action": "get_history_entry", "data": {"index": index}})
        return resp.get("data") if resp else None

    def enable_automation(self, enabled=True):
        # We need an explicit 'set_automation' or just use toggle logic
        # For now, let's assume we can get current state and check
        state = self.get_state()
        if state and state.get("internalComputerAutomationEnabled") != enabled:
            self.send_command({"action": "toggle_automation"})

    def step_next_turn(self):
        return self.send_command({"action": "step_next_turn"})

    def detect_anomalies(self, state):
        if not state: return
        
        # 1. Detect Ghosting
        hidden_src = set(state.get("hiddenInSourceCardIds", []))
        hidden_tgt = set(state.get("hiddenInTargetCardIds", []))
        moving_ids = set(state.get("currentMovingCardIds", []))
        
        ghost_source = hidden_src - moving_ids
        ghost_target = hidden_tgt - moving_ids
        
        if ghost_source:
            logger.warning(f"[ANOMALY] Potential Ghosting (Source): Cards hidden but not moving: {list(ghost_source)}")
        if ghost_target:
            logger.warning(f"[ANOMALY] Potential Ghosting (Target): Cards hidden but not moving: {list(ghost_target)}")

        # 2. Detect Animation Hangs
        is_busy = state.get("isAutomationBusy", False)
        pending_delays = state.get("pendingAutomationDelays", 0)
        
        if is_busy and pending_delays > 0:
            duration = time.time() - self.busy_since
            if duration > 5.0:
                logger.error(f"[ANOMALY] Animation Hang! Busy for {duration:.1f}s with {pending_delays} delays")
        else:
            self.busy_since = time.time()

        # 3. Sequence Validation
        ux_logs = state.get("uxEventLogs", [])
        for event in ux_logs:
            event_id = event.get("id")
            if event_id not in self.processed_events:
                self.processed_events.add(event_id)
                self.validate_sequence(event)

    def validate_sequence(self, event):
        etype = event.get("type")
        data = event.get("data", {})
        if etype == "moveStart":
            card_id = data.get("cardId") or data.get("cardIds")
            self.pending_moves[card_id] = event
        elif etype == "moveEnd":
            card_id = data.get("cardId") or data.get("cardIds")
            if card_id in self.pending_moves:
                del self.pending_moves[card_id]
            else:
                logger.warning(f"[ANOMALY] Orphaned moveEnd for {card_id}")
        logger.info(f"[UX EVENT] {etype}: {data}")

    def print_status(self, state):
        os.system('clear')
        print("=== AI UX Player Monitor ===")
        print(f"Monitor Mode: {'PAUSED (Reviewing History)' if self.is_paused else 'LIVE (Observing)'}")
        if self.is_paused:
            print(f"Viewing history entry: {self.history_index} / {self.history_count - 1}")
        
        if state:
            print(f"Game State: {state.get('gameState') or 'N/A'}")
            is_auto = state.get('internalComputerAutomationEnabled', False)
            print(f"Simulator Automation: {'ON (Auto Play)' if is_auto else 'OFF (Manual Play)'}")
            print(f"UX Status: {'BUSY' if state.get('isAutomationBusy') else 'IDLE'} (Delays: {state.get('pendingAutomationDelays', 0)})")
            
            ux_logs = state.get("uxEventLogs", [])
            print("\nRecent UX Events (Monitor finds anomalies automatically):")
            for e in ux_logs[-8:]:
                print(f" - {e.get('type')}: {e.get('data')}")
        
        print("\nControls:")
        print(" [Enter] Pause Monitor (History Review) | [Q] Quit")
        print(" [Left] Step Back History               | [Right] Step Forward / Force Next Turn")

    def run(self):
        import termios
        import tty

        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)

        try:
            tty.setcbreak(fd)
            # PASSIVE: Do NOT force automation on. Let the user decide in-game.

            while True:
                if self.is_paused:
                    state = self.get_history_entry(self.history_index)
                else:
                    state = self.get_state()

                if state:
                    self.history_count = state.get("historyCount", 0)
                    if not self.is_paused:
                        self.detect_anomalies(state)
                        self.history_index = self.history_count - 1
                    self.print_status(state)

                rlist, _, _ = select.select([sys.stdin], [], [], 0.3)
                if rlist:
                    key = sys.stdin.read(1)
                    if key == '\n' or key == '\r':
                        self.is_paused = not self.is_paused
                        # PASSIVE: Monitor pause only affects the monitor's display, not the game.
                        print(f"\n[Monitor] {'Reviewing History...' if self.is_paused else 'Back to Live Observation'}")
                        if self.is_paused:
                            self.history_index = self.history_count - 1
                    elif key == '\x1b':
                        next1 = sys.stdin.read(1)
                        next2 = sys.stdin.read(1)
                        if next1 == '[':
                            if next2 == 'D': # Left
                                if self.is_paused and self.history_index > 0:
                                    self.history_index -= 1
                                    print(f"\n[Monitor] Showing history index {self.history_index}")
                            elif next2 == 'C': # Right
                                if self.is_paused:
                                    if self.history_index < self.history_count - 1:
                                        self.history_index += 1
                                    else:
                                        print("\n[Monitor] Forcing next turn in simulator...")
                                        self.step_next_turn()
                                        time.sleep(0.5)
                                        # Update history count after step
                                        new_state = self.get_state()
                                        if new_state:
                                            self.history_count = new_state.get("historyCount", 0)
                                            self.history_index = self.history_count - 1
                    elif key.lower() == 'q':
                        break
                time.sleep(0.1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

if __name__ == "__main__":
    monitor = UXMonitor()
    monitor.run()
