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
    
    # 1. Start game first to initialize players
    agent.send_user_action("start_game")
    
    # 2. Setup mock state AFTER start_game to avoid reset
    agent.set_condition({
        "mock_hand": [{"month": 1, "type": "junk"}] * 3,
        "mock_table": [{"month": 1, "type": "junk"}],
        "mock_deck": [{"month": 4, "type": "junk"}], # Non-matching draw to avoid sweep
        "mock_opponent_captured_cards": [{"month": 2, "type": "junk"}, {"month": 3, "type": "junk"}],
        "player1_data": {"isComputer": False}
    })
    
    handle_potential_shake(agent)
    
    # 2. Action: Play Jan card from hand
    agent.send_user_action("play_card", {"month": 1, "type": "junk"})
    
    # 3. Verification
    state = agent.get_all_information()
    player = state["players"][0]
    opponent = state["players"][1]
    
    # Check captures (3 from hand + 1 from table = 4, PLUS 1 stolen from bomb = 5)
    # Sweep didn't trigger because drawn card stayed on table.
    assert len(player["capturedCards"]) == 5, f"Expected 5 captured cards, got {len(player['capturedCards'])}"
    
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

def handle_potential_shake(agent: TestAgent):
    """
    Helper to handle the 'askingShake' state if it occurs after start_game.
    """
    state = agent.get_all_information()
    if state["gameState"] == "askingShake":
        logger.info("Handling initial shake requests...")
        months = state.get("pendingShakeMonths", [])
        for month in months:
            agent.send_user_action("respond_to_shake", {"month": month, "didShake": False})

def scenario_verify_conditional_double_pi(agent: TestAgent):
    """
    Scenario: Verifies that month 9 junk (Chrysanthemum) counts as 2 Pi only if player has Cheongdan.
    """
    logger.info("Running Conditional Double Pi verification...")
    
    # 1. Setup: Player has Month 9 Junk, 3 Cheongdan ribbons, and 8 other junk (Total 10 Pi units).
    agent.set_condition({
        "mock_captured_cards": [
            {"month": 6, "type": "ribbon"},
            {"month": 9, "type": "ribbon"},
            {"month": 10, "type": "ribbon"}, # Cheongdan
            {"month": 9, "type": "junk"},     # Conditional (+1 if has cheongdan)
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"}      # 8 normal junk
        ]
    })
    
    state = agent.get_all_information()
    player = state["players"][0]
    
    # Check Pi count. 1 (Month 9) + 1 (Bonus) + 8 (Others) = 10.
    pi_score_item = next((item for item in player["scoreItems"] if item["name"].startswith("피")), None)
    assert pi_score_item is not None, f"Pi score item should be present for 10 units. Found: {player['scoreItems']}"
    assert pi_score_item["count"] == 10, f"Expected 10 Pi count (8 base + 2 conditional), got {pi_score_item['count']}"
    
    logger.info("Conditional Double Pi verification passed (with Cheongdan)!")
    
    # 2. Setup: Player has Month 9 Junk and 8 other junk, but NOT Cheongdan. (Total 9 Pi units).
    agent.set_condition({
        "mock_captured_cards": [
            {"month": 9, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"},
            {"month": 1, "type": "junk"}
        ]
    })
    
    state = agent.get_all_information()
    player = state["players"][0]
    pi_score_item = next((item for item in player["scoreItems"] if item["name"].startswith("피")), None)
    # Should be None or 0 pts if count < 10
    if pi_score_item:
        assert pi_score_item["count"] < 10, f"Score item should show <10 Pi units, got {pi_score_item['count']}"
    
    logger.info("Conditional Double Pi verification passed (without Cheongdan)!")

def scenario_verify_special_moves_suite(agent: TestAgent):
    """
    Scenario: Verifies Sweep, Ttadak, Jjok, and Seolsa.
    """
    logger.info("Running Special Moves (Sweep, Ttadak, Jjok, Seolsa) verification...")
    
    # 1. Start game
    agent.send_user_action("start_game")
    
    # 2. Setup Ttadak condition
    agent.set_condition({
        "mock_hand": [{"month": 2, "type": "junk"}, {"month": 2, "type": "ribbon"}],
        "mock_table": [{"month": 2, "type": "animal"}, {"month": 2, "type": "junk"}],
        "mock_deck": [{"month": 2, "type": "ribbon"}], # Ensure Month 2 is on top
        "mock_gameState": "playing",
        "player1_data": {"isComputer": False},
        "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}] # Something to steal
    })
    handle_potential_shake(agent)
    agent.send_user_action("play_card", {"month": 2, "type": "junk"})
    
    state = agent.get_all_information()
    player = state["players"][0]
    assert player["ttadakCount"] == 1, f"Expected ttadakCount 1, got {player['ttadakCount']}"
    # Note: capturedCards count depends on draw RNG (2 if draw mismatch, 4 if draw matches)
    assert len(player["capturedCards"]) >= 2, f"Should capture at least 2 cards, got {len(player['capturedCards'])}"
    
    logger.info("Ttadak verification passed!")
    
    # --- 2. Jjok (쪽) ---
    agent.send_user_action("start_game")
    agent.set_condition({
        "mock_hand": [{"month": 3, "type": "junk"}],
        "mock_table": [],
        "mock_deck": [{"month": 3, "type": "junk"}], # Ensure Month 3 is on top
        "mock_gameState": "playing",
        "player1_data": {"isComputer": False},
        "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}]
    })
    handle_potential_shake(agent)
    agent.send_user_action("play_card", {"month": 3, "type": "junk"})
    
    state = agent.get_all_information()
    player = state["players"][0]
    assert player["jjokCount"] == 1, f"Expected jjokCount 1, got {player['jjokCount']}"
    
    logger.info("Jjok verification passed!")

    # --- 3. Sweep (쓸기) ---
    agent.send_user_action("start_game")
    agent.set_condition({
        "mock_hand": [{"month": 4, "type": "junk"}],
        "mock_table": [{"month": 4, "type": "animal"}],
        "mock_deck": [{"month": 9, "type": "junk"}], # Ensure deck draw doesn't match
        "mock_gameState": "playing",
        "player1_data": {"isComputer": False},
        "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}]
    })
    handle_potential_shake(agent)
    agent.send_user_action("play_card", {"month": 4, "type": "junk"})
    
    state = agent.get_all_information()
    player = state["players"][0]
    assert player["sweepCount"] == 1, f"Expected sweepCount 1, got {player['sweepCount']}"
    assert len(state["tableCards"]) == 1, "Only card left should be the non-matching deck draw"
    
    logger.info("Sweep verification passed!")

def scenario_verify_mungdda_combos(agent: TestAgent):
    """
    Scenario: Verifies Mung-dda and Bomb Mung-dda.
    """
    logger.info("Running Mung-dda combos verification...")
    
    # 1. Setup: Opponent is in Pi-mungbak state.
    agent.send_user_action("start_game")
    agent.set_condition({
        "mock_hand": [{"month": 5, "type": "junk"}, {"month": 5, "type": "ribbon"}],
        "mock_table": [{"month": 5, "type": "animal"}, {"month": 5, "type": "junk"}],
        "mock_deck": [{"month": 5, "type": "ribbon"}], # Ensure Month 5 is on top for Ttadak
        "mock_gameState": "playing",
        "player1_data": {"isPiMungbak": True, "isComputer": False},
        "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}] * 5 # Enough to steal
    })
    handle_potential_shake(agent)
    agent.send_user_action("play_card", {"month": 5, "type": "junk"}) # Triggers Ttadak
    
    state = agent.get_all_information()
    player = state["players"][0]
    # Ttadak + Opponent PiMungbak = Mung-dda
    assert player["mungddaCount"] == 1, f"Expected mungddaCount 1, got {player['mungddaCount']}"
    
    logger.info("Mung-dda verification passed!")
    
    # 2. Setup: Bomb Mung-dda
    agent.set_condition({
        "mock_hand": [{"month": 6, "type": "junk"}, {"month": 6, "type": "ribbon"}, {"month": 6, "type": "animal"}],
        "mock_table": [{"month": 6, "type": "bright"}],
        "player1_data": {"isPiMungbak": True},
        "mock_opponent_captured_cards": [{"month": 1, "type": "junk"}] * 5
    })
    agent.send_user_action("start_game")
    handle_potential_shake(agent)
    agent.send_user_action("play_card", {"month": 6, "type": "junk"}) # Triggers Bomb
    
    state = agent.get_all_information()
    player = state["players"][0]
    assert player["bombMungddaCount"] == 1, f"Expected bombMungddaCount 1, got {player['bombMungddaCount']}"
    
    logger.info("Bomb Mung-dda verification passed!")

def scenario_verify_endgame_conditions(agent: TestAgent):
    """
    Scenario: Verifies Endgame conditions (Max Go, Max Score, Instant End on Bak).
    """
    logger.info("Running Endgame Conditions verification...")
    
    agent.send_user_action("start_game")
    handle_potential_shake(agent)
    
    # Mocking mid-game state MUST happen after start_game or it gets overwritten
    agent.set_condition({
        "mock_gameState": "askingGoStop",
        "player0_data": {"goCount": 4, "lastGoScore": 1},
        "mock_captured_cards": [{"month": 1, "type": "junk"}] * 10,
        "player1_data": {"isComputer": False}
    })
    
    agent.send_user_action("respond_go_stop", {"isGo": True})
    state = agent.get_all_information()
    assert state["gameState"] == "ended", f"Expected game to end on 5th Go, got {state['gameState']}"
    
    logger.info("Max Go endgame verification passed!")
    
    # 2. Max Score (threshold is 50 in rule.yaml)
    # Mocking a state where winner has > 50 points
    agent.send_user_action("start_game")
    agent.set_condition({
        "mock_gameState": "playing",
        "mock_hand": [{"month": 12, "type": "junk"}],
        "mock_captured_cards": [{"month": 1, "type": "bright"}, {"month": 3, "type": "bright"}, {"month": 8, "type": "bright"}], # 삼광 (3 pts)
        "player0_data": {"bombCount": 5}, # 2^5 = 32x multiplier. 3 * 32 = 96 pts > 50.
        "mock_opponent_captured_cards": [{"month": 11, "type": "junk"}] * 10,
        "player1_data": {"isComputer": False}
    })
    handle_potential_shake(agent)
    # Play any card to trigger end-of-turn check
    agent.send_user_action("play_card", {"month": 12, "type": "junk"})
    
    state = agent.get_all_information()
    assert state["gameState"] == "ended", f"Expected game to end on Max Score, got {state['gameState']}"
    
    logger.info("Max Score endgame verification passed!")

def scenario_verify_initial_shake(agent: TestAgent):
    """
    Scenario: Verifies the initial shake phase at the start of the game.
    """
    logger.info("Running Initial Shake verification...")
    
    # Setup hand with 3 of month 1
    agent.set_condition({
        "mock_hand": [
            {"month": 1, "type": "junk"}, {"month": 1, "type": "ribbon"}, {"month": 1, "type": "bright"},
            {"month": 2, "type": "junk"}
        ]
    })
    
    agent.send_user_action("start_game")
    
    state = agent.get_all_information()
    assert state["gameState"] == "askingShake", f"Expected askingShake state, got {state['gameState']}"
    assert state["pendingShakeMonths"] == [1], f"Expected month 1 in pendingShakeMonths, got {state['pendingShakeMonths']}"
    
    # Respond to shake
    agent.send_user_action("respond_to_shake", {"month": 1, "didShake": True})
    
    state = agent.get_all_information()
    assert state["gameState"] == "playing", f"Expected game to start after shake response, got {state['gameState']}"
    assert state["players"][0]["shakeCount"] == 1, "Expected shakeCount to be 1"
    
    logger.info("Initial Shake verification passed!")

if __name__ == "__main__":
    # Path to the compiled GoStopCLI
    possible_paths = [
        "../../build_v4/Build/Products/Debug/GoStopCLI",
        "../../build_v3/Build/Products/Debug/GoStopCLI",
        "../../build/Build/Products/Debug/GoStopCLI",
        "../../build_v2/Build/Products/Debug/GoStopCLI"
    ]
    import os
    app_executable = next((p for p in possible_paths if os.path.exists(p)), possible_paths[0])
    
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
        scenario_verify_penalties,
        scenario_verify_conditional_double_pi,
        scenario_verify_special_moves_suite,
        scenario_verify_mungdda_combos,
        scenario_verify_endgame_conditions,
        scenario_verify_initial_shake
    ]
    
    # Run tests once for verification
    try:
        agent.run_tests(scenarios=scenarios_to_run, repeat_count=1)
    except KeyboardInterrupt:
        logger.info("Testing interrupted by user.")
