import json
import os
from main import TestAgent

def print_card(card):
    suffix = "(2P)" if card['type'] == 'doubleJunk' else ""
    return f"[M:{card['month']:>2} | {card['type']:<10}{suffix}]"

def inspect_state(mode="cli"):
    # Try common build directories
    possible_paths = [
        "../../build_v3/Build/Products/Debug/GoStopCLI",
        "../../build/Build/Products/Debug/GoStopCLI",
        "../../build_v2/Build/Products/Debug/GoStopCLI"
    ]
    
    app_executable = next((p for p in possible_paths if os.path.exists(p)), possible_paths[0])
    agent = TestAgent(app_executable_path=app_executable, connection_mode=mode)
    
    try:
        if mode == "cli":
            agent.start_app()
            agent.set_condition({"rng_seed": 42})
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
                    "끗(Animal)": [c for c in captured if c['type'] == 'animal'],
                    "띠(Ribbon)": [c for c in captured if c['type'] == 'ribbon'],
                    "피(Junk)  ": [c for c in captured if c['type'] in ['junk', 'doubleJunk']]
                }
                
                for label, cards in groups.items():
                    if cards:
                        # Add (2P) marker for doubleJunk cards
                        card_list = []
                        for c in cards:
                            m_str = f"M{c['month']}"
                            if c['type'] == 'doubleJunk':
                                m_str += "(2P)"
                            card_list.append(m_str)
                        
                        card_str = " ".join(card_list)
                        print(f"    {label:<12}: {len(cards):>2} cards -> {card_str}")
                    else:
                        print(f"    {label:<12}:  0 cards")
            print("-" * 50)
            
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
