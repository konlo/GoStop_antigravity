print("Main script starting...")
import json
import logging
import os
import subprocess
import time
import fcntl
import traceback
from datetime import datetime

# Configure Artifact Directories
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.abspath(os.path.join(script_dir, "../../"))
artifacts_dir = "/tmp/gostop_test_artifacts" # Use /tmp to avoid permission issues on macOS
log_dir = os.path.join(artifacts_dir, "logs")
crash_dir = os.path.join(artifacts_dir, "crash_dumps")
snapshot_dir = os.path.join(artifacts_dir, "state_snapshots")

for d in [artifacts_dir, log_dir, crash_dir, snapshot_dir]:
    if not os.path.isdir(d):
        try:
            os.makedirs(d, exist_ok=True)
        except OSError:
            if not os.path.isdir(d):
                pass # Silently continue if we can't create it, logger might just fail later

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
log_file = os.path.join(log_dir, f"test_agent_{timestamp}.log")
crash_file = os.path.join(crash_dir, f"crash_report_{timestamp}.json")
repro_file = os.path.join(artifacts_dir, f"repro_steps_{timestamp}.json")

logger = logging.getLogger("TestAgent")
logger.setLevel(logging.DEBUG)

# Console handler (Always available)
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

# File handler (Optional, with fallback)
try:
    fh = logging.FileHandler(log_file)
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(formatter)
    logger.addHandler(fh)
except (PermissionError, OSError) as e:
    print(f"Warning: Could not create log file at {log_file} due to permissions. Console logging only.")

DEBUG_SETUP_ACTIONS = {"start_game", "click_restart_button"}


def format_elapsed_duration(elapsed_sec: float) -> str:
    total_centiseconds = int(round(max(elapsed_sec, 0.0) * 100))
    hours, remainder = divmod(total_centiseconds, 360000)
    minutes, remainder = divmod(remainder, 6000)
    seconds, centiseconds = divmod(remainder, 100)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{centiseconds:02d}"


class ManualScenarioPause(RuntimeError):
    """Raised when debug_level 2 hands control over to the user."""
    pass

class TestAgent:
    def __init__(self, 
                 app_executable_path: str = None, 
                 connection_mode: str = "cli",
                 action_timeout_sec: float = 5.0,
                 max_steps_per_scenario: int = 100,
                 rng_seed: int = None,
                 debug_level: int = 0):
        """
        Initializes the Test Agent.
        :param app_executable_path: Path to the Apple App executable (e.g. built CLI tool)
        :param connection_mode: "cli", "http", or "socket" (default uses subprocess CLI)
        :param action_timeout_sec: Maximum time to wait for the app to respond to an action.
        :param max_steps_per_scenario: Safety guard against infinite testing loops.
        :param rng_seed: Fixed seed for deterministic testing across runs.
        :param debug_level:
            0 = normal run,
            1 = wait for Enter before each setup/user action,
            2 = run setup only, then hand off to manual simulator play.
        """
        self.app_executable_path = app_executable_path
        self.connection_mode = connection_mode
        self.action_timeout_sec = action_timeout_sec
        self.max_steps_per_scenario = max_steps_per_scenario
        self.rng_seed = rng_seed
        self.debug_level = debug_level
        self.process = None
        self.action_log = []
        self.last_state = {}
        self.results = [] # Track (Iteration, Index, Scenario, Status, Message)
        self.current_scenario_name = None
        self.current_scenario_index = None
        self._debug_setup_performed = False
        self._manual_handoff_done = False
        if self.debug_level == 2 and self.connection_mode != "socket":
            raise ValueError("--debug_level 2 requires --mode socket so you can interact with the simulator UI.")
        logger.info(f"TestAgent initialized with mode: {connection_mode}")
        if self.debug_level > 0:
            logger.info(f"Interactive debug mode enabled: level {self.debug_level}")

    def start_app(self):
        """Starts the Apple App process."""
        self.action_log = [] # Reset log per scenario/run
        self.last_state = {}
        self._debug_setup_performed = False
        self._manual_handoff_done = False
        
        if self.connection_mode == "cli":
            if not self.app_executable_path:
                raise ValueError("app_executable_path is required for CLI connection mode.")
            executable_path = self.app_executable_path
            if not os.path.isabs(executable_path):
                # Support both caller-cwd-relative and repo-root-relative paths.
                cwd_candidate = os.path.abspath(executable_path)
                repo_candidate = os.path.abspath(os.path.join(repo_root, executable_path))
                if os.path.exists(cwd_candidate):
                    executable_path = cwd_candidate
                elif os.path.exists(repo_candidate):
                    executable_path = repo_candidate
            self.app_executable_path = executable_path
            logger.info(f"Starting app at {self.app_executable_path}")
            self.process = subprocess.Popen(
                [self.app_executable_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=repo_root
            )
            time.sleep(1) # wait for startup
        else:
            logger.info(f"Connecting to app via {self.connection_mode}")
            if self.connection_mode == "socket":
                self._wait_for_socket_bridge_ready()
                self._reset_socket_app_state()
            # Implement HTTP connection here if needed

    def _scenario_label(self) -> str:
        if self.current_scenario_index is None or self.current_scenario_name is None:
            return "current scenario"
        return f"[{self.current_scenario_index}] {self.current_scenario_name}"

    def _format_debug_step(self, step_type: str, payload=None) -> str:
        if payload is None:
            return step_type
        try:
            rendered = json.dumps(payload, ensure_ascii=False)
        except TypeError:
            rendered = str(payload)
        return f"{step_type} {rendered}"

    def _await_debug_enter(self, message: str):
        try:
            response = input(message)
        except EOFError:
            logger.warning("Interactive debug prompt received EOF. Continuing automatically.")
            return
        if response.strip().lower() in {"q", "quit"}:
            raise KeyboardInterrupt("Debug run aborted by user.")

    def _enter_manual_handoff(self, upcoming_step: str):
        if self._manual_handoff_done:
            raise ManualScenarioPause(f"Manual handoff already active for {self._scenario_label()}.")
        self._manual_handoff_done = True

        state_summary = "state unavailable"
        try:
            state = self._send_command({"action": "get_state"}, record_action=False)
            state_summary = (
                f"gameState={state.get('gameState')}, "
                f"currentTurnIndex={state.get('currentTurnIndex')}, "
                f"deckCount={state.get('deckCount')}, "
                f"historyCount={state.get('historyCount')}"
            )
            self.save_snapshot(
                f"manual_handoff_{self.current_scenario_index if self.current_scenario_index is not None else 'scenario'}",
                state_data=state
            )
        except Exception as e:
            logger.warning(f"Failed to capture manual handoff snapshot: {e}")

        prompt = (
            f"\n[DEBUG2] Setup complete for {self._scenario_label()}.\n"
            f"Automation stopped before: {upcoming_step}\n"
            f"Current state: {state_summary}\n"
            "Interact with the simulator UI manually now.\n"
            "Press Enter here when you want to end this scenario and continue.\n> "
        )
        self._await_debug_enter(prompt)
        raise ManualScenarioPause(f"Manual handoff before {upcoming_step}")

    def _debug_gate_step(self, step_type: str, payload=None, is_setup: bool = False):
        if self.debug_level <= 0:
            return

        step_label = self._format_debug_step(step_type, payload)
        if self.debug_level == 1:
            self._await_debug_enter(
                f"\n[DEBUG1] {self._scenario_label()} next step: {step_label}\n"
                "Press Enter to execute this step.\n> "
            )
            return

        if is_setup:
            logger.info(f"[DEBUG2] Auto setup step: {step_label}")
            return

        self._enter_manual_handoff(step_label)

    def _debug_gate_state_read(self):
        if self.debug_level == 2 and self._debug_setup_performed and not self._manual_handoff_done:
            self._enter_manual_handoff("get_all_information")

    def stop_app(self):
        """Stops the Apple App."""
        logger.info("Stopping the app...")
        if self.process:
            self.process.terminate()
            self.process.wait()
            self.process = None

    def _wait_for_socket_bridge_ready(self, timeout_sec: float = 10.0):
        deadline = time.time() + timeout_sec
        last_error = None
        while time.time() < deadline:
            try:
                self._send_command({"action": "get_state"}, record_action=False)
                return
            except Exception as e:
                last_error = e
                time.sleep(0.25)
        raise RuntimeError(f"Socket bridge not ready within {timeout_sec}s: {last_error}")

    def _wait_for_socket_idle(self, timeout_sec: float = 8.0):
        deadline = time.time() + timeout_sec
        last_state = None
        stable_signature = None
        stable_since = None
        settle_window_sec = 0.18
        while time.time() < deadline:
            state = self._send_command({"action": "get_state"}, record_action=False)
            last_state = state
            # Older bridge payloads may not expose these fields; a successful state fetch is enough then.
            if "isAutomationBusy" not in state and "pendingAutomationDelays" not in state:
                return

            pending = int(state.get("pendingAutomationDelays", 0))
            busy = bool(state.get("isAutomationBusy", False))
            moving_ids = state.get("currentMovingCardIds", []) or []
            hidden_src = state.get("hiddenInSourceCardIds", []) or []
            hidden_tgt = state.get("hiddenInTargetCardIds", []) or []
            game_state = state.get("gameState")

            # Decision states can legitimately pause while waiting for input.
            decision_state = game_state in (
                "askingShake",
                "askingGoStop",
                "choosingCapture",
                "choosingChrysanthemumRole",
            )

            # Do not trust a single poll where pending=0. There can be transient gaps
            # between chained callbacks, so require a short stable idle window.
            idle_now = pending == 0 and (
                (not busy and not moving_ids and not hidden_src and not hidden_tgt) or decision_state
            )

            signature = (
                state.get("historyCount"),
                game_state,
                state.get("currentTurnIndex"),
                pending,
                busy,
                len(moving_ids),
                len(hidden_src),
                len(hidden_tgt),
            )

            if idle_now:
                if stable_signature != signature:
                    stable_signature = signature
                    stable_since = time.time()
                elif stable_since is not None and (time.time() - stable_since) >= settle_window_sec:
                    return
            else:
                stable_signature = None
                stable_since = None
            time.sleep(0.05)
        raise RuntimeError(
            f"Socket app did not become idle within {timeout_sec}s. "
            f"Last state flags: isAutomationBusy={None if last_state is None else last_state.get('isAutomationBusy')}, "
            f"pendingAutomationDelays={None if last_state is None else last_state.get('pendingAutomationDelays')}"
        )

    def _reset_socket_app_state(self):
        # Socket mode reuses the simulator app process across scenarios, so explicitly reset state here.
        # Initial deal can rarely end immediately (e.g., initial Nagari/Chongtong). Retry to start from
        # a controllable non-ended state.
        for _ in range(5):
            self._send_command({"action": "click_restart_button"}, record_action=False)
            self._wait_for_socket_idle()
            state = self._send_command({"action": "get_state"}, record_action=False)
            if state.get("gameState") != "ended":
                return
        raise RuntimeError("Socket reset repeatedly landed in ended state (initial special end).")

    def _save_repro_steps(self):
        """Saves current action sequence for deterministic replay."""
        if self.action_log:
            with open(repro_file, 'w') as f:
                json.dump({"seed": self.rng_seed, "sequence": self.action_log}, f, indent=2)

    def _send_command(self, command: dict, record_action: bool = True) -> dict:
        """Sends a JSON command to the app and returns the JSON response."""
        logger.debug(f"Sending command: {command}")
        
        # Keep track for replay / debugging
        if record_action and command.get("action") != "get_state":
            self.action_log.append(command)
        
        if self.connection_mode == "cli":
            if not self.process:
                raise RuntimeError("App is not running.")
            
            req_str = json.dumps(command) + "\n"
            self.process.stdin.write(req_str)
            self.process.stdin.flush()
            
            # Read response (Using naive readline here. In production, wrap in thread/poll with select for timeout)
            # A true timeout implementation would use select.select on self.process.stdout
            response_str = self.process.stdout.readline()
            if not response_str:
                stderr_output = self.process.stderr.read()
                raise RuntimeError(f"App closed unexpectedly. Stderr: {stderr_output}")
            
            try:
                resp = json.loads(response_str)
                logger.debug(f"Received response: {resp}")
                
                # Cache successful state for crash recovery
                if command.get("action") == "get_state" and resp.get("status") == "ok":
                    self.last_state = resp
                elif resp.get("status") == "ok" or resp.get("status") == "action executed":
                    # If action succeeded, try to keep a peek of state if returned, 
                    # but usually actions don't return full state. 
                    # We rely on explicit get_state calls for full snapshots.
                    pass
                
                return resp
            except json.JSONDecodeError as e:
                raise RuntimeError(f"Failed to parse JSON response: {response_str}") from e
        elif self.connection_mode == "socket":
            import socket
            try:
                # Simple one-off socket connection for each command
                # In production, keep a persistent socket if performance is key
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(self.action_timeout_sec)
                s.connect(("127.0.0.1", 8080))
                
                req_str = json.dumps(command) + "\n"
                s.sendall(req_str.encode('utf-8'))
                
                # Receive response
                response_data = b""
                while True:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    response_data += chunk
                    if b"\n" in response_data:
                        break
                
                s.close()
                
                if not response_data:
                    raise RuntimeError("No response from simulator socket.")
                
                resp = json.loads(response_data.decode('utf-8').strip())
                logger.debug(f"Received socket response: {resp}")
                
                if command.get("action") == "get_state" and resp.get("status") == "ok":
                    self.last_state = resp
                return resp
            except Exception as e:
                raise RuntimeError(f"Socket communication failed: {e}")
        else:
            # Implement HTTP request to the App's testing server (using self.action_timeout_sec)
            pass
        return {}

    def get_all_information(self, allow_manual_handoff: bool = True) -> dict:
        """
        6. Reads all state and information from the App.
        Returns the full current state for inspection.
        """
        if allow_manual_handoff:
            self._debug_gate_state_read()
        logger.info("Requesting all information from app.")
        return self._send_command({"action": "get_state"})

    def set_condition(self, condition_data: dict, is_setup: bool = True) -> dict:
        """
        7. Provides an interface to set specific mock scenarios or conditions.
        :param condition_data: Data defining the state to set (e.g. {"player_score": 100})
        """
        self._debug_gate_step("set_condition", condition_data, is_setup=is_setup)
        logger.info(f"Setting specific condition: {condition_data}")
        resp = self._send_command({
            "action": "set_condition",
            "data": condition_data
        })
        if is_setup:
            self._debug_setup_performed = True
        return resp
        
    def save_snapshot(self, tag: str, state_data: dict = None):
        """Saves a state snapshot to artifacts."""
        if not state_data:
            state_data = self.get_all_information(allow_manual_handoff=False)
        
        filename = os.path.join(snapshot_dir, f"snapshot_{tag}_{int(time.time()*1000)}.json")
        with open(filename, 'w') as f:
            json.dump(state_data, f, indent=2)
        logger.info(f"Snapshot saved: {filename}")

    def send_user_action(self, action_type: str, action_data: dict = None) -> dict:
        """Sends a simulated user interface interaction."""
        cmd = {"action": action_type}
        if action_data:
            cmd["data"] = action_data
        is_setup_action = action_type in DEBUG_SETUP_ACTIONS
        self._debug_gate_step(f"user_action:{action_type}", action_data, is_setup=is_setup_action)
        logger.info(f"Sending user action: {action_type} with data: {action_data}")
        resp = self._send_command(cmd)
        if is_setup_action:
            self._debug_setup_performed = True
        # In socket mode, the simulator app stays alive and animations may finish after the command ACK.
        # Wait for a stable post-action state so scenarios observe the same semantics as CLI mode.
        if self.connection_mode == "socket" and action_type != "get_state":
            self._wait_for_socket_idle()
        return resp

    def run_tests(self, scenarios: list, repeat_count: int = 1):
        """
        5. Runs a suite of scenarios, potentially repeating them.
        """
        run_started_at = datetime.now()
        run_start_perf = time.perf_counter()
        logger.info(f"Starting test run. Total scenarios: {len(scenarios)}, Repeat count: {repeat_count}")
        try:
            for iteration in range(repeat_count):
                logger.info(f"--- Starting Iteration {iteration + 1}/{repeat_count} ---")
                for idx, scenario_func in enumerate(scenarios):
                    scenario_name = scenario_func.__name__
                    scenario_idx = getattr(scenario_func, "scenario_index", idx)
                    self.current_scenario_name = scenario_name
                    self.current_scenario_index = scenario_idx
                    logger.info(f"Running Scenario [{scenario_idx}]: {scenario_name}")

                    try:
                        self.start_app()

                        # If deterministic replay is requested
                        if self.rng_seed is not None:
                            self.set_condition({"rng_seed": self.rng_seed}, is_setup=False)

                        # Run the actual test scenario logic
                        scenario_func(self)

                        # Save normal execution path
                        self._save_repro_steps()
                        logger.info(f"Scenario {scenario_name} completed successfully.")
                        self.results.append((iteration + 1, scenario_idx, scenario_name, "PASS", "Success"))
                    except ManualScenarioPause as e:
                        self._save_repro_steps()
                        logger.info(f"Scenario {scenario_name} handed off for manual play: {e}")
                        self.results.append((iteration + 1, scenario_idx, scenario_name, "MANUAL", str(e)))
                    except Exception as e:
                        # Check if the exception was expected (scenarios can signal this by raising specific errors or returning status)
                        # For now, we'll continue logging errors but scenarios will be updated to catch them.
                        logger.error(f"Scenario {scenario_name} failed with exception: {e}")
                        self.handle_crash(e, scenario_name)
                        self.results.append((iteration + 1, scenario_idx, scenario_name, "FAIL", str(e)))
                    finally:
                        self.stop_app()
                        self.current_scenario_name = None
                        self.current_scenario_index = None

                logger.info(f"--- Finished Iteration {iteration + 1}/{repeat_count} ---")
        finally:
            total_elapsed_sec = time.perf_counter() - run_start_perf
            logger.info(
                "Finished test run. Started at %s, elapsed %s (%.2fs).",
                run_started_at.strftime("%Y-%m-%d %H:%M:%S"),
                format_elapsed_duration(total_elapsed_sec),
                total_elapsed_sec
            )
            self.print_summary(total_duration_sec=total_elapsed_sec)

    def print_summary(self, total_duration_sec=None):
        """Prints a clear summary table of all test results."""
        pass_count = sum(1 for _, _, _, status, _ in self.results if status == "PASS")
        fail_count = sum(1 for _, _, _, status, _ in self.results if status == "FAIL")
        manual_count = sum(1 for _, _, _, status, _ in self.results if status == "MANUAL")
        print("\n" + "="*70)
        print(f"{'ITER':<5} | {'ID':<4} | {'SCENARIO':<35} | {'STATUS':<10}")
        print("-" * 70)
        for iter_num, s_idx, name, status, msg in self.results:
            print(f"{iter_num:<5} | {s_idx:<4} | {name:<35} | {status:<10}")
        print("="*70 + "\n")
        print(f"RESULT COUNTS: PASS={pass_count} FAIL={fail_count} MANUAL={manual_count}")
        if total_duration_sec is not None:
            print(f"TOTAL RUNTIME: {format_elapsed_duration(total_duration_sec)} ({total_duration_sec:.2f}s)")
        print()

    def handle_crash(self, exception: Exception, context: str):
        """
        4. Capture anomalies, exceptions, and crashes, saving them for debugging.
        """
        logger.critical(f"Handling crash/exception in {context}")
        
        crash_data = {
            "timestamp": datetime.now().isoformat(),
            "context": context,
            "error_type": type(exception).__name__,
            "error_message": str(exception),
            "traceback": traceback.format_exc(),
            "stderr": ""
        }
        
        # Try to capture stderr if available (non-blocking)
        if self.process and self.process.stderr:
            try:
                # Set non-blocking mode
                fd = self.process.stderr.fileno()
                fl = fcntl.fcntl(fd, fcntl.F_GETFL)
                fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
                
                try:
                    stderr_data = self.process.stderr.read()
                    if stderr_data:
                        crash_data["stderr"] = stderr_data
                except (IOError, TypeError):
                    # No data available in non-blocking mode
                    pass
            except Exception as stderr_exc:
                logger.warning(f"Could not prepare stderr capture: {stderr_exc}")
        
        # Try to capture last known state if possible
        try:
           # First try a fresh fetch (may fail if app crashed)
           current_state = self.get_all_information(allow_manual_handoff=False)
           crash_data["last_known_state"] = current_state
        except Exception as state_exc:
           logger.warning(f"Could not fetch fresh state after crash: {state_exc}. Using cached state.")
           crash_data["last_known_state"] = self.last_state if self.last_state else f"No state cached. Error: {state_exc}"
           
        # Generate unique filename for this specific crash
        crash_id = int(time.time() * 1000)
        specific_crash_file = os.path.join(crash_dir, f"crash_{context}_{crash_id}.json")
        
        with open(specific_crash_file, 'w') as f:
            json.dump(crash_data, f, indent=2)
            
        self._save_repro_steps()
            
        logger.critical(f"Crash report saved to: {specific_crash_file}")
