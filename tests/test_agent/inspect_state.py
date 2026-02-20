import json
from main import TestAgent

def print_card(card):
    # Mapping months to Korean/English names could be helpful
    # Simple representation: [M:3, T:animal, ID:...short]
    return f"[M:{card['month']:>2} | {card['type']:<10}]"

def inspect_state(mode="cli"):
    app_executable = "../../build/Build/Products/Debug/GoStopCLI"
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
            
            print(f"PLAYER: {name} (Score: {score})")
            print(f"  HAND ({len(hand)}):")
            for i, card in enumerate(hand):
                print(f"    {i+1:>2}. {print_card(card)}")
            
            if captured:
                print(f"  CAPTURED ({len(captured)}):")
                for i, card in enumerate(captured):
                    print(f"    {i+1:>2}. {print_card(card)}")
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
