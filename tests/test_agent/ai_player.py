import json
import logging
import os
import random
import subprocess
import time
import traceback
from datetime import datetime
from main import TestAgent, logger, artifacts_dir

class AIPlayer(TestAgent):
    def __init__(self, **kwargs):
        self.debug_level = kwargs.pop("debug_level", "normal")
        super().__init__(**kwargs)
        self.max_go_count = 4 # Target go count (can be 4 or 5)
        self.paused = False
        self.state_history = []
        self.error_log_path = os.path.join(artifacts_dir, "error_report.log")

    def record_state(self, state):
        """Records the current state for post-game analysis."""
        self.state_history.append({
            "timestamp": datetime.now().isoformat(),
            "state": state
        })

    def check_duplicate_cards(self, state):
        """Checks if the exact same card (by ID) appears multiple times in the current state."""
        all_cards = []
        
        def add_cards(cards, location):
            for c in cards:
                if isinstance(c, dict):
                    c['_location'] = location
                    all_cards.append(c)
        
        add_cards(state.get('tableCards', []), 'Table')
        add_cards(state.get('outOfPlayCards', []), 'OutOfPlay')
        
        # pendingCapture* fields are aliases for choice UI, not independent zones.
        # The same card can legitimately also exist in tableCards while choosingCapture.
        
        # Check if full deck is exposed
        if 'deck' in state and isinstance(state['deck'], dict):
            add_cards(state['deck'].get('cards', []), 'Deck')
        elif 'deckCards' in state:
            add_cards(state.get('deckCards', []), 'Deck')
            
        for p_idx, p in enumerate(state.get('players', [])):
            name = p.get('name', f'Player_{p_idx}')
            add_cards(p.get('hand', []), f'{name}_Hand')
            add_cards(p.get('capturedCards', []), f'{name}_Captured')
            
        seen_ids = {}
        duplicates = []
        for c in all_cards:
            cid = c.get('id')
            if not cid:
                continue
            if cid in seen_ids:
                dup_msg = f"Duplicate Card ID {cid} (M:{c.get('month')} {c.get('type')}) found in '{c['_location']}' and '{seen_ids[cid]['_location']}'"
                if dup_msg not in duplicates:
                    duplicates.append(dup_msg)
            else:
                seen_ids[cid] = c

        if duplicates:
            logger.error(f"DUPLICATE CARDS DETECTED: {duplicates}")
            self.report_error(duplicates)

    def validate_monthly_pair_integrity(self, state):
        """Validates that for EVERY month (1-12), exactly 4 cards exist across all areas."""
        if state.get("gameState", "ready") in ["ready"]:
            return # Skip if game hasn't started
            
        all_cards = []
        
        def add_cards(cards):
            for c in cards:
                if isinstance(c, dict):
                    all_cards.append(c)
                    
        add_cards(state.get('tableCards', []))
        add_cards(state.get('outOfPlayCards', []))
        
        # pendingCapture* fields are informational aliases and should not be counted
        # as separate card ownership locations for integrity validation.
        
        if 'deck' in state and isinstance(state['deck'], dict):
            add_cards(state['deck'].get('cards', []))
        elif 'deckCards' in state:
            add_cards(state.get('deckCards', []))
            
        for p in state.get('players', []):
            add_cards(p.get('hand', []))
            add_cards(p.get('capturedCards', []))
            
        month_counts = {}
        for c in all_cards:
            m = c.get('month')
            if m is not None and m != 0: # Ignore dummy cards (month 0)
                month_counts[m] = month_counts.get(m, 0) + 1
                
        for m in range(1, 13):
            count = month_counts.get(m, 0)
            if count != 4:
                raise ValueError(f"Monthly integrity violation! Month {m} has {count} cards (Expected 4). Total valid cards checked: {len(all_cards)}")
                
        base_cards_count = sum(month_counts.values())
        if base_cards_count != 48:
            raise ValueError(f"Total base cards={base_cards_count} (Expected 48). Monthly pair integrity failed!")

    def validate_game_results(self):
        """Validates the game outcome against rules and endgame parameters."""
        if not self.state_history:
            return

        final_snapshot = self.state_history[-1]["state"]
        players = final_snapshot.get("players", [])
        end_reason = final_snapshot.get("gameEndReason")
        penalty_result = final_snapshot.get("penaltyResult", {})
        
        errors = []

        for p_idx, player in enumerate(players):
            reported_score = player.get("score", 0)
            score_items = player.get("scoreItems", [])
            calculated_score = sum(item.get("points") or item.get("score") or 0 for item in score_items)

            # Rule 1: Score Consistency (Base Score without multipliers)
            if reported_score != calculated_score:
                errors.append(f"Player {p_idx} ({player.get('name')}): Base Score mismatch. "
                              f"Reported={reported_score}, Sum of Items={calculated_score}")
            
            # Rule 2: Max Score Enforcement
            if end_reason == "maxScore":
                # A maxScore game end MUST mean someone reached the threshold or an instant end condition fired.
                # In testing, max_round_score is 50.
                if penalty_result:
                    # Check if finalScore >= 50 or if instant end conditions triggered
                    final_score = penalty_result.get("finalScore", 0)
                    has_instant_end = penalty_result.get("isGwangbak") or penalty_result.get("isPibak") or penalty_result.get("isMungbak")
                    go_count = player.get("goCount", 0)
                    if final_score < 50 and go_count < 5 and not has_instant_end:
                        # Log warning, not strict error, as rule.yaml config might change max_score
                        logger.warning(f"Player {p_idx} ended via maxScore but stats seem low (Score:{final_score}, Go:{go_count})")

        # Rule 3: Penalty Validation
        if penalty_result and end_reason != "nagari":
            winner = max(players, key=lambda x: x.get('score', 0))
            loser = min(players, key=lambda x: x.get('score', 0))
            
            # Very basic Pi counting heuristic check for Pibak
            def get_pi_count(p):
                return sum(1 for c in p.get("capturedCards", []) if c.get("type") == "junk") + \
                       sum(2 for c in p.get("capturedCards", []) if c.get("type") == "doubleJunk")
            
            winner_pi = get_pi_count(winner)
            loser_pi = get_pi_count(loser)
            
            # If winner has >= 10 pi and loser is < 6 pi, Pibak SHOULD be true (unless Jabak nullifies it)
            if winner_pi >= 10 and loser_pi < 6:
                if not penalty_result.get("isPibak") and not penalty_result.get("isJabak"):
                    # NOTE: Configuration could change PiSafe threshold, but 6 is standard.
                    logger.warning(f"Validation Note: Pibak was NOT applied despite WinnerPi={winner_pi} and LoserPi={loser_pi}.")

        if errors:
            self.report_error(errors)
        else:
            logger.info(f"Game validation passed. End Reason: {end_reason}. Scores consistent.")

    def format_card(self, card):
        suffix = "(2P)" if card.get('type') == 'doubleJunk' else ""
        return f"[M:{card['month']:>2} | {card.get('type', 'junk'):<10}{suffix}]"

    def format_state_inspection(self, state):
        """Formats the state into a readable string similar to inspect_state.py."""
        lines = []
        lines.append("\n" + "="*50)
        lines.append("           GO-STOP GAME STATE INSPECTION")
        lines.append("="*50)
        lines.append(f"Game State: {state.get('gameState', 'N/A').upper()}")
        lines.append(f"Deck Count: {state.get('deckCount', 0)}")
        lines.append("-" * 50)
        
        # Table Cards
        table_cards = state.get('tableCards', [])
        lines.append(f"TABLE CARDS ({len(table_cards)}):")
        for i, card in enumerate(table_cards):
            lines.append(f"  {i+1:>2}. {self.format_card(card)}")
        
        # Pending Choice Cards
        if state.get('pendingCapturePlayedCard'):
            lines.append(f"PENDING PLAYED CARD: {self.format_card(state['pendingCapturePlayedCard'])}")
        if state.get('pendingCaptureDrawnCard'):
            lines.append(f"PENDING DRAWN CARD : {self.format_card(state['pendingCaptureDrawnCard'])}")
        
        lines.append("-" * 50)
        
        # Players
        for player in state.get('players', []):
            name = player.get('name', 'Unknown')
            hand = player.get('hand', [])
            captured = player.get('capturedCards', [])
            score = player.get('score', 0)
            score_items = player.get('scoreItems', [])
            
            lines.append(f"PLAYER: {name}")
            lines.append(f"  TOTAL SCORE: {score} points")
            if score_items:
                lines.append("  SCORE BREAKDOWN:")
                for item in score_items:
                    # The CLI and SimulatorBridge might return slightly different fields
                    # Standardizing label/points check
                    label = item.get('label') or item.get('name') or "Unknown"
                    points = item.get('score') or item.get('points') or 0
                    lines.append(f"    - {label:<30}: {points:>2} pts")
            lines.append(f"  HAND ({len(hand)}):")
            for i, card in enumerate(hand):
                lines.append(f"    {i+1:>2}. {self.format_card(card)}")
            
            if captured:
                lines.append("  CAPTURED GROUPS:")
                groups = {
                    "광(Bright)": [c for c in captured if c.get('type') == 'bright'],
                    "끗(Animal)": [c for c in captured if c.get('type') == 'animal'],
                    "띠(Ribbon)": [c for c in captured if c.get('type') == 'ribbon'],
                    "피(Junk)  ": [c for c in captured if c.get('type') in ['junk', 'doubleJunk']]
                }
                
                for label, cards in groups.items():
                    if cards:
                        card_list = []
                        for c in cards:
                            m_str = f"M{c['month']}"
                            if c.get('type') == 'doubleJunk':
                                m_str += "(2P)"
                            if c.get('selectedRole'):
                                m_str += f"[{c['selectedRole']}]"
                            card_list.append(m_str)
                        card_str = " ".join(card_list)
                        lines.append(f"    {label:<12}: {len(cards):>2} cards -> {card_str}")
                    else:
                        lines.append(f"    {label:<12}:  0 cards")
            lines.append("-" * 50)
        return "\n".join(lines)

    def report_error(self, errors):
        """Generates a detailed error report for debugging."""
        with open(self.error_log_path, "a") as f:
            f.write(f"\n{'='*80}\n")
            f.write(f"ERROR REPORT - {datetime.now().isoformat()}\n")
            f.write(f"{'='*80}\n")
            for err in errors:
                f.write(f"ISSUE: {err}\n")
            
            f.write("\nACTION SEQUENCE SUMMARY:\n")
            for i, entry in enumerate(self.state_history):
                state = entry["state"]
                f.write(f"Step {i}: [{state.get('gameState')}] Turn: {state.get('currentTurnIndex')} "
                        f"Deck: {state.get('deckCount')}\n")
            
            f.write("\nFINAL STATE INSPECTION:\n")
            f.write(self.format_state_inspection(self.state_history[-1]["state"]))
            f.write(f"\n{'='*80}\n")
        
        logger.error(f"Validation failed! Report saved to {self.error_log_path}")

    def check_pause(self):
        """Checks if a pause/resume was requested via keyboard."""
        import select
        import sys
        # Check for any keyboard input
        rlist, _, _ = select.select([sys.stdin], [], [], 0)
        if rlist:
            input_val = sys.stdin.readline()
            # If the user pressed space then enter, or just enter
            self.paused = not self.paused
            status = "PAUSED" if self.paused else "RESUMED"
            logger.info(f"Simulation {status}. Press Enter (or Space+Enter) to toggle.")

    def select_best_card(self, hand, table_cards):
        """Simple matching heuristic."""
        table_months = {c.get('month') for c in table_cards}
        
        # 1. Look for matches
        for card in hand:
            m = card.get('month')
            if m != 0 and m in table_months:
                return card
        
        # 2. If no matches, check for dummy cards
        for card in hand:
            if card.get('month') == 0:
                return card
        
        # 3. Default to first card
        return hand[0]

    def decide_chrysanthemum_role(self, state):
        """Heuristic to decide role for September Animal."""
        players = state.get("players", [])
        current_turn = state.get("currentTurnIndex", 0)
        if current_turn >= len(players):
            return "animal"
        
        player = players[current_turn]
        captured = player.get("capturedCards", [])
        
        # Calculate current Pi count
        pi_count = sum(1 for c in captured if c.get('type') == 'junk') + \
                   sum(2 for c in captured if c.get('type') == 'doubleJunk')
        
        # Heuristic: If we have < 10 pi, doublePi is usually better to reach scoring.
        # If we already have 4 animals, picking animal might get us to the animal scoring bonus.
        animal_count = sum(1 for c in captured if c.get('type') == 'animal')
        
        if pi_count < 10:
            return "doublePi"
        if animal_count >= 4:
            return "animal"
            
        return "doublePi" # Default to doublePi as it's generally stronger

    def run_continuous_simulation(self, num_games: int = 0):
        """
        Runs the game in a loop using socket connection.
        :param num_games: Total number of games to play. 0 means infinite.
        """
        logger.info(f"Starting simulation in {self.connection_mode} mode...")
        if num_games > 0:
            logger.info(f"Target game count: {num_games}")
        else:
            logger.info("Running indefinitely (Press Ctrl+C to stop).")
            
        logger.info("Tip: Press Enter to Pause/Resume simulation.")
        
        games_completed = 0
        
        while True:
            try:
                self.check_pause()
                if self.paused:
                    time.sleep(0.5)
                    continue
                    
                state_resp = self.get_all_information()
                if state_resp.get("status") != "ok":
                    logger.error(f"Failed to get state or connection refused. Retrying... {state_resp}")
                    time.sleep(2)
                    continue

                self.record_state(state_resp)
                # `isAutomationBusy` may remain true in stable states due to UI-only hidden-card markers.
                # For automation pacing, delayed callbacks are the real source of stale reads/races.
                pending_delays = state_resp.get("pendingAutomationDelays", 0) or 0
                if pending_delays > 0:
                    time.sleep(0.2)
                    continue

                self.check_duplicate_cards(state_resp)
                
                if self.debug_level == "high":
                    try:
                        self.validate_monthly_pair_integrity(state_resp)
                        logger.debug("Play Tracing: Month-pair validation passed.")
                    except ValueError as e:
                        error_msg = f"Play Tracing Error: {str(e)}"
                        logger.error(error_msg)
                        self.report_error([error_msg])
                        import sys
                        sys.exit(1)
                
                game_state = state_resp.get("gameState")
                current_turn = state_resp.get("currentTurnIndex", 0)
                players = state_resp.get("players", [])
                
                if not game_state:
                    logger.error("Missing gameState in response")
                    time.sleep(1)
                    continue

                logger.info(f"Current Game State: {game_state}")

                if game_state == "ready":
                    self.state_history = [] # Reset for new game
                    self.send_user_action("start_game")
                
                elif game_state == "playing":
                    if not players:
                        logger.warning("No players found in state")
                        time.sleep(1)
                        continue
                        
                    player = players[current_turn]
                    if player.get("hand"):
                        # Select a card to play using matching heuristic
                        card = self.select_best_card(player["hand"], state_resp.get("tableCards", []))
                        month = card.get("month", 0) 
                        card_type = card.get("type", "junk")
                        
                        logger.info(f"Player {current_turn} ({player['name']}) playing {month} {card_type}")
                        self.send_user_action("play_card", {"month": month, "type": card_type})
                    else:
                        error_msg = f"INVARIANT VIOLATION: Player {current_turn} ({player.get('name')}) has an EMPTY hand but gameState is 'playing'. Hands and deck must exhaust exactly together."
                        logger.error(error_msg)
                        self.report_error([error_msg])
                        raise ValueError(error_msg)

                elif game_state == "askingGoStop":
                    player = players[current_turn]
                    go_count = player.get("goCount", 0)
                    
                    # 50/50 Randomized Choice (as requested)
                    is_go = random.random() < 0.5
                    logger.info(f"Player {current_turn} ({player['name']}) GoCount: {go_count}. [RANDOM] Decision: {'GO' if is_go else 'STOP'}")
                    self.send_user_action("respond_go_stop", {"isGo": is_go})

                elif game_state == "choosingCapture":
                    # When multiple cards of the same month are on the table, the user must choose one to capture
                    options = state_resp.get("pendingCaptureOptions", [])
                    if options:
                        # Auto-select the first option for the bot
                        chosen_card = options[0]
                        logger.info(f"Capture Choice required. Auto-selecting: M{chosen_card.get('month')} {chosen_card.get('type')}")
                        self.send_user_action("respond_to_capture", {
                            "id": chosen_card.get("id")
                        })
                    else:
                        logger.warning("In choosingCapture state but no pendingCaptureOptions found.")
                        time.sleep(1)

                elif game_state == "askingShake":
                    pending = state_resp.get("pendingShakeMonths", [])
                    if pending:
                        month = pending[0]
                        # 50/50 Randomized Choice (as requested)
                        did_shake = random.random() < 0.5
                        logger.info(f"Shake available for month {month}. [RANDOM] Decision: {'SHAKE' if did_shake else 'NORMAL'}")
                        self.send_user_action("respond_to_shake", {"month": month, "didShake": did_shake})
                    else:
                        logger.warning("In askingShake state but no pendingShakeMonths found.")
                        time.sleep(1)

                elif game_state == "choosingChrysanthemumRole":
                    # Choose role for September Chrysanthemum Animal card
                    role = self.decide_chrysanthemum_role(state_resp)
                    logger.info(f"Chrysanthemum role choice required. AI Decision: '{role}'")
                    self.send_user_action("respond_to_chrysanthemum_choice", {"role": role})

                elif game_state == "ended":
                    self.validate_game_results()
                    games_completed += 1
                    
                    if num_games > 0 and games_completed >= num_games:
                        logger.info(f"Target game count ({num_games}) reached. Simulation ending.")
                        return

                    logger.info(f"Game {games_completed} ended. Waiting 1 second for manual input (Enter) before auto-restarting...")
                    import select
                    import sys
                    # Non-blocking check for stdin with 1 second timeout
                    rlist, _, _ = select.select([sys.stdin], [], [], 1.0)
                    if rlist:
                        # Clear the buffer
                        sys.stdin.readline()
                        logger.info("Manual input detected. Auto-restart cancelled for this cycle.")
                    else:
                        logger.info("No input detected. Auto-restarting...")
                        self.state_history = [] # Reset for new game
                        self.send_user_action("click_restart_button")
                    time.sleep(1) # Small cooldown

                else:
                    logger.warning(f"Unknown game state: {game_state}")
                
                time.sleep(0.5) # Delay between actions for visibility

            except Exception as e:
                logger.error(f"Error in simulation loop: {e}")
                # We don't break here, just log and retry connection
                time.sleep(2)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Run AI Player Simulation")
    parser.add_argument("num_games", type=int, nargs="?", default=0, help="Number of games to play (0 for infinite)")
    parser.add_argument("--debug_level", type=str, default="normal", help="Set to 'high' to enable play tracing and month-pair validation.")
    args = parser.parse_args()

    # In socket mode, we don't need app_executable_path
    ai = AIPlayer(connection_mode="socket", debug_level=args.debug_level)
    # You can set max_go_count to 4 or 5
    ai.max_go_count = 4 
    ai.run_continuous_simulation(num_games=args.num_games)
