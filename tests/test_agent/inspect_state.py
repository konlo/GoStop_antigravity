import json
import os
from main import TestAgent

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../../"))

def print_card(card):
    suffix = "(2P)" if card['type'] == 'doubleJunk' else ""
    return f"[M:{card['month']:>2} | {card['type']:<10}{suffix}]"

def inspect_state(mode="cli"):
    # Resolve common build outputs to absolute paths so TestAgent subprocess cwd does not break them.
    possible_paths = [
        os.path.join(REPO_ROOT, "build/Build/Products/Debug/GoStopCLI"),
        os.path.join(REPO_ROOT, "build_v29/Build/Products/Debug/GoStopCLI"),
        os.path.join(REPO_ROOT, "build/Debug/GoStopCLI"),
        os.path.join(REPO_ROOT, "build_v26/Build/Products/Debug/GoStopCLI"),
        os.path.join(REPO_ROOT, "build_v25/Build/Products/Debug/GoStopCLI"),
    ]

    app_executable = next((p for p in possible_paths if os.path.exists(p)), possible_paths[0])
    agent = TestAgent(app_executable_path=app_executable, connection_mode=mode)
    
    try:
        if mode == "cli":
            agent.start_app()
            agent.set_condition({"rng_seed": 42})
            if os.environ.get("MOCK_ENDED") == "1":
                # Mock an ended state
                agent.set_condition({
                    "mock_gameState": "ended",
                    "player0_data": {"score": 56},
                    "player1_data": {"score": 0},
                    "mock_captured_cards": [{"month": 1, "type": "junk"}] * 10
                })
                # Trigger endgame check to set reason
                agent.send_user_action("mock_endgame_check")
            else:
                agent.send_user_action("start_game")
        else:
            print("Connecting to LIVE Simulator (Port 8080)...")
        
        state = agent.get_all_information()
        
        print("\n" + "="*50)
        print("           GO-STOP GAME STATE INSPECTOR")
        print("="*50)
        print(f"Game State: {state.get('gameState', 'N/A').upper()}")
        print(f"Deck Count: {state.get('deckCount', 0)}")
        print("-" * 50)
        
        # Table Cards
        table_cards = state.get('tableCards', [])
        print(f"TABLE CARDS ({len(table_cards)}):")
        for i, card in enumerate(table_cards):
            print(f"  {i+1:>2}. {print_card(card)}")
        print("-" * 50)
        
        # Players
        for player in state.get('players', []):
            name = player.get('name', 'Unknown')
            hand = player.get('hand', [])
            captured = player.get('capturedCards', [])
            score = player.get('score', 0)
            score_items = player.get('scoreItems', [])
            
            print(f"PLAYER: {name}")
            print(f"  TOTAL SCORE: {score} points")
            if score_items:
                print("  SCORE BREAKDOWN:")
                for item in score_items:
                    print(f"    - {item['name']:<30}: {item['points']:>2} pts")
            print(f"  HAND ({len(hand)}):")
            for i, card in enumerate(hand):
                print(f"    {i+1:>2}. {print_card(card)}")
            
            if captured:
                print("  CAPTURED GROUPS:")
                groups = {
                    "광(Bright)": [c for c in captured if c['type'] == 'bright'],
                    "끗(Animal)": [c for c in captured if (c['type'] == 'animal' and (c.get('month') != 9 or c.get('selectedRole', 'animal') == 'animal'))],
                    "띠(Ribbon)": [c for c in captured if c['type'] == 'ribbon'],
                    "피(Junk)  ": [c for c in captured if c['type'] in ['junk', 'doubleJunk'] or (c.get('month') == 9 and c.get('selectedRole') == 'doublePi')]
                }
                
                for label, cards in groups.items():
                    if cards:
                        # Add (2P) marker for doubleJunk cards
                        total_units = 0
                        card_list = []
                        for c in cards:
                            m_str = f"M{c['month']}"
                            is_double = False
                            if c['type'] == 'doubleJunk' or (c.get('month') == 9 and c.get('selectedRole') == 'doublePi'):
                                m_str += "(2P)"
                                is_double = True
                            card_list.append(m_str)
                            
                            # Simple unit calculation (matching ScoringSystem.calculatePiCount basics)
                            if label.startswith("피"):
                                total_units += 2 if is_double else 1
                            else:
                                total_units += 1
                        
                        card_str = " ".join(card_list)
                        unit_str = f" ({total_units} units)" if label.startswith("피") else ""
                        print(f"    {label:<12}: {len(cards):>2} cards{unit_str} -> {card_str}")
                    else:
                        print(f"    {label:<12}:  0 cards")
            print("-" * 50)
            
        # Deck Cards
        deck_cards = state.get('deckCards', [])
        print(f"DECK CARDS ({len(deck_cards)}):")
        # Print deck cards in a compact grid
        for i in range(0, len(deck_cards), 4):
            row = deck_cards[i:i+4]
            row_str = " ".join([print_card(c) for c in row])
            print(f"  {row_str}")
        print("-" * 50)

        # Out-of-play cards (terminal cleanup sink)
        out_cards = state.get('outOfPlayCards', [])
        print(f"OUT-OF-PLAY CARDS ({len(out_cards)}):")
        for i in range(0, len(out_cards), 4):
            row = out_cards[i:i+4]
            row_str = " ".join([print_card(c) for c in row])
            print(f"  {row_str}")
        print("-" * 50)
        
        # Month-Pair Validation Logic
        print("MONTH-PAIR VALIDATION (Accountability for all 48 cards):")
        all_cards = []
        dummy_cards = []
        # 1. Hands and Captured
        for p in state.get('players', []):
            for c in p.get('hand', []):
                (dummy_cards if c.get('type') == 'dummy' else all_cards).append(c)
            for c in p.get('capturedCards', []):
                (dummy_cards if c.get('type') == 'dummy' else all_cards).append(c)
        # 2. Table
        for c in state.get('tableCards', []):
            (dummy_cards if c.get('type') == 'dummy' else all_cards).append(c)
        # 3. Deck
        for c in state.get('deckCards', []):
            (dummy_cards if c.get('type') == 'dummy' else all_cards).append(c)
        # 4. Out-of-play sink
        for c in state.get('outOfPlayCards', []):
            (dummy_cards if c.get('type') == 'dummy' else all_cards).append(c)
        # 5. In-flight card during choosingCapture (played card not yet captured)
        pending = state.get('pendingCapturePlayedCard')
        if pending:
            (dummy_cards if pending.get('type') == 'dummy' else all_cards).append(pending)
            print(f"  [NOTE] pendingCapturePlayedCard ({pending.get('month')}월 {pending.get('type')}) included in count")

        
        if dummy_cards:
            print(f"  [NOTE] {len(dummy_cards)} dummy card(s) excluded from 48-card count")

        month_counts = {}
        for c in all_cards:
            m = c['month']
            month_counts[m] = month_counts.get(m, 0) + 1
            
        is_all_valid = True
        for m in range(1, 13):
            count = month_counts.get(m, 0)
            status = "OK" if count == 4 else "MISSING" if count < 4 else "EXTRA"
            if count != 4:
                is_all_valid = False
            print(f"  Month {m:>2}: {count} cards [{status}]")
            
        total_all = len(all_cards)
        print(f"  TOTAL CARDS: {total_all} / 48")
        if is_all_valid and total_all == 48:
            print("  STATUS: \U0001f7e2 ALL CARDS ACCOUNTED FOR")
        else:
            print(f"  STATUS: \U0001f534 INTEGRITY ERROR ({total_all} cards)")
        print("-" * 50)

        # Event Logs
        event_logs = state.get('eventLogs', [])
        if event_logs:
            print(f"RECENT EVENTS ({len(event_logs)}):")
            for log in event_logs:
                print(f"  > {log}")
            print("-" * 50)

        # Game Summary - always printed
        print("\n" + "=" * 50)
        print("!!! GAME SUMMARY !!!")
        print("=" * 50)
        reason = state.get('gameEndReason', 'N/A')
        game_state_str = state.get('gameState', 'N/A')
        print(f"  게임 상태  : {game_state_str.upper()}")
        print(f"  종료 원인  : {reason}")

        # Winner / Loser names
        winner_name = state.get('winnerName') or state.get('gameWinner', 'N/A')
        loser_name  = state.get('loserName')  or state.get('gameLoser',  'N/A')
        print(f"  승자       : {winner_name}")
        print(f"  패자       : {loser_name}")

        # Per-player in-game event stats
        print("-" * 50)
        print("  [게임 중 이벤트]")
        for player in state.get('players', []):
            pname = player.get('name', '?')
            go_cnt     = player.get('goCount', 0)
            shake_cnt  = player.get('shakeCount', 0)
            bomb_cnt   = player.get('bombCount', 0)
            sweep_cnt  = player.get('sweepCount', 0)
            ttadak_cnt = player.get('ttadakCount', 0)
            seolsa_cnt = player.get('seolsaCount', 0)
            jjok_cnt   = player.get('jjokCount', 0)

            events = [
                ("Go",          go_cnt,     "회"),
                ("흔들기(Shake)", shake_cnt, "회"),
                ("폭탄(Bomb)",   bomb_cnt,  "회"),
                ("싹쓸이(Sweep)",sweep_cnt, "회"),
                ("따닥(Ttadak)", ttadak_cnt,"회"),
                ("뻑(Seolsa)",   seolsa_cnt,"회"),
                ("쪽(Jjok)",     jjok_cnt,  "회"),
            ]
            has_any = any(cnt > 0 for _, cnt, _ in events)
            if has_any:
                for label, cnt, unit in events:
                    if cnt > 0:
                        print(f"    {pname:<12} | {label:<16} : {cnt}{unit}")
            else:
                print(f"    {pname:<12} | 없음")

        # Chongtong details
        if reason == "chongtong":
            chongtong_month  = state.get('chongtongMonth',  'N/A')
            chongtong_timing = state.get('chongtongTiming', 'N/A')
            print(f"  총통 월    : {chongtong_month}월")
            print(f"  총통 시점  : {'초기 총통' if chongtong_timing == 'initial' else '중반 총통'} ({chongtong_timing})")


        # Penalty report
        penalty = state.get('penaltyResult', {})
        if penalty:
            print("-" * 50)
            print("  [점수 산출 내역]")
            final_score = penalty.get('finalScore', 0)
            formula     = penalty.get('scoreFormula', '')
            print(f"  최종 점수  : {final_score} 점")
            if formula:
                print(f"  점수 공식  : {formula}")
            print("-" * 50)
            print("  [패널티 적용 여부]")
            flags = [
                ("광박(Gwangbak)", "isGwangbak"),
                ("피박(Pibak)",    "isPibak"),
                ("고박(Gobak)",    "isGobak"),
                ("멍박(Mungbak)",  "isMungbak"),
                ("자박(Jabak)",    "isJabak"),
                ("역박(Yeokbak)",  "isYeokbak"),
            ]
            for label, key in flags:
                val = penalty.get(key, False)
                mark = "✅ YES" if val else "❌ No"
                print(f"    {label:<16} : {mark}")
        print("=" * 50)

    except Exception as e:
        print(f"Error inspecting state: {e}")
    finally:
        agent.stop_app()

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Inspect GoStop Game State")
    parser.add_argument("--mode", choices=["cli", "socket"], default="cli", help="Connection mode (cli or socket)")
    args = parser.parse_args()
    
    inspect_state(mode=args.mode)
