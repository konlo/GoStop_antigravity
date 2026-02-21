import json
import logging
import os
import subprocess
import time
import fcntl
import traceback
from datetime import datetime

# Configure Artifact Directories
artifacts_dir = "artifacts"
log_dir = os.path.join(artifacts_dir, "logs")
crash_dir = os.path.join(artifacts_dir, "crash_dumps")
snapshot_dir = os.path.join(artifacts_dir, "state_snapshots")

for d in [artifacts_dir, log_dir, crash_dir, snapshot_dir]:
    os.makedirs(d, exist_ok=True)

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
log_file = os.path.join(log_dir, f"test_agent_{timestamp}.log")
crash_file = os.path.join(crash_dir, f"crash_report_{timestamp}.json")
repro_file = os.path.join(artifacts_dir, f"repro_steps_{timestamp}.json")

logger = logging.getLogger("TestAgent")
logger.setLevel(logging.DEBUG)

# File handler
fh = logging.FileHandler(log_file)
fh.setLevel(logging.DEBUG)
# Console handler
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)

formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
fh.setFormatter(formatter)
ch.setFormatter(formatter)
logger.addHandler(fh)
logger.addHandler(ch)

class TestAgent:
    def __init__(self, 
                 app_executable_path: str = None, 
                 connection_mode: str = "cli",
                 action_timeout_sec: float = 5.0,
                 max_steps_per_scenario: int = 100,
                 rng_seed: int = None):
        """
        Initializes the Test Agent.
        :param app_executable_path: Path to the Apple App executable (e.g. built CLI tool)
        :param connection_mode: "cli", "http", or "socket" (default uses subprocess CLI)
        :param action_timeout_sec: Maximum time to wait for the app to respond to an action.
        :param max_steps_per_scenario: Safety guard against infinite testing loops.
        :param rng_seed: Fixed seed for deterministic testing across runs.
        """
        self.app_executable_path = app_executable_path
        self.connection_mode = connection_mode
        self.action_timeout_sec = action_timeout_sec
        self.max_steps_per_scenario = max_steps_per_scenario
        self.rng_seed = rng_seed
        self.process = None
        self.action_log = []
        self.last_state = {}
        self.results = [] # Track (Iteration, Scenario, Status, Message)
        logger.info(f"TestAgent initialized with mode: {connection_mode}")

    def start_app(self):
        """Starts the Apple App process."""
        self.action_log = [] # Reset log per scenario/run
        self.last_state = {}
        
        if self.connection_mode == "cli":
            if not self.app_executable_path:
                raise ValueError("app_executable_path is required for CLI connection mode.")
            logger.info(f"Starting app at {self.app_executable_path}")
            self.process = subprocess.Popen(
                [self.app_executable_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            time.sleep(1) # wait for startup
        else:
            logger.info(f"Connecting to app via {self.connection_mode}")
            # Implement HTTP or Socket connection here
            pass

    def stop_app(self):
        """Stops the Apple App."""
        logger.info("Stopping the app...")
        if self.process:
            self.process.terminate()
            self.process.wait()
            self.process = None

    def _save_repro_steps(self):
        """Saves current action sequence for deterministic replay."""
        if self.action_log:
            with open(repro_file, 'w') as f:
                json.dump({"seed": self.rng_seed, "sequence": self.action_log}, f, indent=2)

    def _send_command(self, command: dict) -> dict:
        """Sends a JSON command to the app and returns the JSON response."""
        logger.debug(f"Sending command: {command}")
        
        # Keep track for replay / debugging
        if command.get("action") != "get_state":
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

    def get_all_information(self) -> dict:
        """
        6. Reads all state and information from the App.
        Returns the full current state for inspection.
        """
        logger.info("Requesting all information from app.")
        return self._send_command({"action": "get_state"})

    def set_condition(self, condition_data: dict) -> dict:
        """
        7. Provides an interface to set specific mock scenarios or conditions.
        :param condition_data: Data defining the state to set (e.g. {"player_score": 100})
        """
        logger.info(f"Setting specific condition: {condition_data}")
        return self._send_command({
            "action": "set_condition",
            "data": condition_data
        })
        
    def save_snapshot(self, tag: str, state_data: dict = None):
        """Saves a state snapshot to artifacts."""
        if not state_data:
            state_data = self.get_all_information()
        
        filename = os.path.join(snapshot_dir, f"snapshot_{tag}_{int(time.time()*1000)}.json")
        with open(filename, 'w') as f:
            json.dump(state_data, f, indent=2)
        logger.info(f"Snapshot saved: {filename}")

    def send_user_action(self, action_type: str, action_data: dict = None) -> dict:
        """Sends a simulated user interface interaction."""
        cmd = {"action": action_type}
        if action_data:
            cmd["data"] = action_data
        logger.info(f"Sending user action: {action_type} with data: {action_data}")
        return self._send_command(cmd)

    def run_tests(self, scenarios: list, repeat_count: int = 1):
        """
        5. Runs a suite of scenarios, potentially repeating them.
        """
        logger.info(f"Starting test run. Total scenarios: {len(scenarios)}, Repeat count: {repeat_count}")
        
        for iteration in range(repeat_count):
            logger.info(f"--- Starting Iteration {iteration + 1}/{repeat_count} ---")
            for idx, scenario_func in enumerate(scenarios):
                scenario_name = scenario_func.__name__
                logger.info(f"Running Scenario {idx + 1}: {scenario_name}")
                
                try:
                    self.start_app()
                    
                    # If deterministic replay is requested
                    if self.rng_seed is not None:
                        self.set_condition({"rng_seed": self.rng_seed})
                        
                    # Run the actual test scenario logic
                    scenario_func(self)
                    
                    # Save normal execution path
                    self._save_repro_steps()
                    logger.info(f"Scenario {scenario_name} completed successfully.")
                    self.results.append((iteration + 1, scenario_name, "PASS", "Success"))
                except Exception as e:
                    # Check if the exception was expected (scenarios can signal this by raising specific errors or returning status)
                    # For now, we'll continue logging errors but scenarios will be updated to catch them.
                    logger.error(f"Scenario {scenario_name} failed with exception: {e}")
                    self.handle_crash(e, scenario_name)
                    self.results.append((iteration + 1, scenario_name, "FAIL", str(e)))
                finally:
                    self.stop_app()
                    
            logger.info(f"--- Finished Iteration {iteration + 1}/{repeat_count} ---")
            
        self.print_summary()

    def print_summary(self):
        """Prints a clear summary table of all test results."""
        print("\n" + "="*60)
        print(f"{'ITER':<5} | {'SCENARIO':<30} | {'STATUS':<10}")
        print("-" * 60)
        for iter_num, name, status, msg in self.results:
            print(f"{iter_num:<5} | {name:<30} | {status:<10}")
        print("="*60 + "\n")

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
           current_state = self.get_all_information()
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
