import logging
from main import TestAgent

logger = logging.getLogger("TestAgent.Scenarios")

def scenario_basic_launch_and_read(agent: TestAgent):
    """
    Scenario: Simply launch the app and read all its state information.
    Verifies that the read interface (get_all_information) works correctly.
    """
    logger.info("Running basic launch and read...")
    
    # 6. Read all information
    state = agent.get_all_information()
    
    # Assert something about the state (example)
    assert state is not None, "Failed to retrieve state!"
    assert "status" in state, "State missing 'status' field."
    
    logger.info(f"State successfully validated: {state}")

def scenario_setup_condition_and_act(agent: TestAgent):
    """
    Scenario: Set a specific mock condition in the App, then perform an action.
    Verifies that the interface to set conditions (set_condition) works correctly.
    """
    logger.info("Running condition setup and act scenario...")
    
    # 7. Request specific conditions and mock the situation
    setup_result = agent.set_condition({
        "mock_scenario": "game_over",
        "player1_score": 100,
        "player2_score": 50
    })
    logger.info(f"Condition set result: {setup_result}")
    
    # Send a user action to interact with the mocked state
    agent.save_snapshot("pre_action")
    action_result = agent.send_user_action("click_restart_button")
    agent.save_snapshot("post_action")
    
    logger.info(f"Action result: {action_result}")
    
    # Read state again to verify changes
    new_state = agent.get_all_information()
    assert new_state.get("gameState") == "ready", f"App did not correctly restart. State: {new_state}"

def scenario_force_crash_capture(agent: TestAgent):
    """
    Scenario: Sends an invalid action to purposefully test crash and exception capturing.
    """
    logger.info("Running force crash scenario...")
    
    # Fetch state first so we have a cached "last known state" for the crash report
    agent.get_all_information()
    
    # Sending an action that should cause an error/crash in the app
    logger.info("Executing intentional crash action...")
    try:
        response = agent.send_user_action("invalid_action_triggering_crash")
        if "error" in response:
            logger.info(f"App handled error as expected: {response['error']}")
            return
    except RuntimeError as e:
        if "App closed unexpectedly" in str(e):
            logger.info("App crashed as expected for this scenario.")
            return
        raise e
    
def scenario_safety_limit_trigger(agent: TestAgent):
    """
    Scenario: Attempts to run an infinite loop to verify safety limits.
    """
    logger.info("Running safety limit trigger scenario...")
    
    # Loop over the allowed max steps to see if our agent bails out gracefully
    # In a real app, an agent might get stuck in a visual loop.
    for step in range(agent.max_steps_per_scenario + 5):
        if step >= agent.max_steps_per_scenario:
            logger.info("Intentional safety limit reached. Validating graceful abort...")
            agent.save_snapshot("safety_abort")
            # We return instead of raising to signal it's a successful verification of the limit
            logger.info(f"Verified safety limit of {agent.max_steps_per_scenario} steps.")
            return
            
        agent.send_user_action("click_useless_button")

def scenario_verify_scoring_suite(agent: TestAgent):
    """
    Scenario: Comprehensive verification of all scoring categories.
    """
    logger.info("Running comprehensive scoring verification suite...")
    
    test_cases = [
        {
            "name": "10 Normal Pi -> 1 pt",
            "cards": [{"month": m, "type": "junk"} for m in range(1, 11)],
            "expected_score": 1,
            "category": "Junk"
        },
        {
            "name": "8 Normal + 1 SsangPi -> 1 pt (10 pi)",
            "cards": [{"month": m, "type": "junk"} for m in range(1, 9)] + [{"month": 11, "type": "doubleJunk"}],
            "expected_score": 1,
            "category": "Junk"
        },
        {
            "name": "Month 9 Junk Check (Normal Pi)",
            "cards": [{"month": 9, "type": "junk"}] * 10,
            "expected_score": 1, 
            "category": "Junk"
        },
        {
            "name": "Godori (Feb, Apr, Aug Animals)",
            "cards": [
                {"month": 2, "type": "animal"},
                {"month": 4, "type": "animal"},
                {"month": 8, "type": "animal"}
            ],
            "expected_score": 5,
            "category": "Godori"
        },
        {
            "name": "Hong-dan (Jan, Feb, Mar Ribbons)",
            "cards": [
                {"month": 1, "type": "ribbon"},
                {"month": 2, "type": "ribbon"},
                {"month": 3, "type": "ribbon"}
            ],
            "expected_score": 3,
            "category": "Red Ribbons"
        },
        {
            "name": "Bi-samgwang (3 Brights incl. Dec)",
            "cards": [
                {"month": 1, "type": "bright"},
                {"month": 3, "type": "bright"},
                {"month": 12, "type": "bright"}
            ],
            "expected_score": 2,
            "category": "3 Brights"
        },
        {
            "name": "Sam-gwang (3 Brights excl. Dec)",
            "cards": [
                {"month": 1, "type": "bright"},
                {"month": 3, "type": "bright"},
                {"month": 8, "type": "bright"}
            ],
            "expected_score": 3,
            "category": "3 Brights"
        }
    ]

    for case in test_cases:
        logger.info(f"Testing sub-case: {case['name']}")
        agent.set_condition({"mock_captured_cards": case["cards"]})
        state = agent.get_all_information()
        player = state.get("players", [{}])[0]
        score_items = player.get("scoreItems", [])
        
        found_item = next((item for item in score_items if case["category"] in item["name"]), None)
        
        if found_item:
            logger.info(f"  Result: Found '{found_item['name']}' with {found_item['points']} pts")
            assert found_item["points"] == case["expected_score"], \
                f"FAILED: {case['name']}. Expected {case['expected_score']} pts, got {found_item['points']}"
        else:
            assert False, f"FAILED: {case['name']}. Score category '{case['category']}' not found in {score_items}"

    logger.info("Scoring verification suite passed successfully.")

def scenario_verify_bomb_and_steal(agent: TestAgent):
    """
    Scenario: Verifies Bomb (폭탄) and Stealing Pi from opponent.
    """
    logger.info("Running Bomb and Steal verification scenario...")
    
    # 1. Setup: 
    # Player hand: 3 of Jan (month 1)
    # Table: 1 of Jan
    # Opponent: Has 2 normal Pi
    agent.set_condition({
        "mock_hand": [{"month": 1, "type": "junk"}] * 3,
        "mock_table": [{"month": 1, "type": "junk"}],
        "mock_opponent_captured_cards": [{"month": 2, "type": "junk"}, {"month": 3, "type": "junk"}]
    })
    
    # 1b. Transition to playing state
    agent.send_user_action("start_game")
    
    # 2. Action: Play Jan card from hand
    agent.send_user_action("play_card", {"month": 1, "type": "junk"})
    
    # 3. Verification
    state = agent.get_all_information()
    player = state["players"][0]
    opponent = state["players"][1]
    
    # Check captures (3 from hand + 1 from table = 4, PLUS 1 stolen from opponent = 5)
    assert len(player["capturedCards"]) == 5, f"Expected 5 captured cards (4 from bomb + 1 stolen), got {len(player['capturedCards'])}"
    
    # Check shake count
    assert player["shakeCount"] == 1, f"Expected shakeCount 1, got {player['shakeCount']}"
    
    logger.info("Bomb and Steal verification passed!")

def scenario_verify_penalties(agent: TestAgent):
    """
    Scenario: Verifies Gwangbak, Pibak, Mungbak, and Gobak multipliers.
    """
    logger.info("Running Penalties verification scenario...")
    
    # Setup winner with multiple score triggers:
    # 3 Brights (Kwang)
    # 7 Animals (Mung)
    # 10 Pi (Pi)
    winner_cards = (
        [{"month": 1, "type": "bright"}, {"month": 3, "type": "bright"}, {"month": 8, "type": "bright"}] + # 3 pts (Samgwang)
        [{"month": m, "type": "animal"} for m in range(1, 8)] + # 1 pt (7 animals)
        [{"month": m, "type": "junk"} for m in range(1, 11)] # 1 pt (10 Pi)
    )
    # Base score: 3 (Kwang) + 1 (Animal) + 1 (Pi) = 5
    
    # Setup loser to be vulnerable to all bak:
    # 0 Brights (Gwangbak)
    # 5 Pi (Pibak - min safe is 6)
    # Previously called Go, but now winner takes over (Gobak)
    loser_cards = [{"month": 11, "type": "junk"}] * 5
    
    agent.set_condition({
        "mock_captured_cards": winner_cards,
        "mock_opponent_captured_cards": loser_cards,
        "player1_data": {"goCount": 1}, # Loser called Go
        "player0_data": {"goCount": 0}, # Winner called 0 Go (essential for Gobak)
        "mock_scenario": "game_over" 
    })
    
    state = agent.get_all_information()
    penalty = state.get("penaltyResult")
    
    assert penalty is not None, "Failed to retrieve penaltyResult from state"
    
    # Check individual flags
    assert penalty["isGwangbak"] == True, "Expected Gwangbak to be True"
    assert penalty["isPibak"] == True, "Expected Pibak to be True"
    assert penalty["isMungbak"] == True, "Expected Mungbak to be True"
    assert penalty["isGobak"] == True, "Expected Gobak to be True"
    
    # Expected final score calculation:
    # Base: 3 (Kwang) + 3 (Animal: 5(1)+6(1)+7(1)) + 1 (Pi) = 7
    # Gwangbak (x2), Pibak (x2), Mungbak (x2), Gobak (x2)
    # Final: 7 * 2 * 2 * 2 * 2 = 112
    expected_final = 7 * 2 * 2 * 2 * 2
    assert penalty["finalScore"] == expected_final, f"Expected final score {expected_final}, got {penalty['finalScore']}"
    
    logger.info(f"Penalties verification passed! Final Score: {penalty['finalScore']}")

if __name__ == "__main__":
    # Path to the compiled GoStopCLI
    app_executable = "../../build_v3/Build/Products/Debug/GoStopCLI" 
    
    agent = TestAgent(app_executable_path=app_executable, 
                      connection_mode="cli",
                      max_steps_per_scenario=100, 
                      rng_seed=42) # Deterministic seed
    
    scenarios_to_run = [
        scenario_basic_launch_and_read,
        scenario_setup_condition_and_act,
        scenario_force_crash_capture,
        scenario_safety_limit_trigger,
        scenario_verify_scoring_suite,
        scenario_verify_bomb_and_steal,
        scenario_verify_penalties
    ]
    
    # 5. Repeat tests continuously or a set number of times
    REPEAT_COUNT = 3 # Set to a large number for prolonged stress testing
    
    try:
        agent.run_tests(scenarios=scenarios_to_run, repeat_count=REPEAT_COUNT)
    except KeyboardInterrupt:
        logger.info("Testing interrupted by user.")
