import json
import os
import pandas as pd

LOG_FILE = 'performance_log.json'

def update_strategy_performance(entry_price, exit_price, strategy_used, win_loss_status):
    """
    Updates the persistent JSON performance log.
    Used for Machine Learning feedback and Dynamic SL/TP adjustments.
    """
    log_data = []
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, 'r') as f:
            try:
                log_data = json.load(f)
            except Exception:
                pass
    
    trade_profit = exit_price - entry_price if win_loss_status == 'win' else entry_price - exit_price
    
    trade = {
        "timestamp": pd.Timestamp.now().isoformat(),
        "entry_price": entry_price,
        "exit_price": exit_price,
        "strategy_used": strategy_used,
        "win_loss_status": win_loss_status,
        "profit": round(trade_profit, 2)
    }
    
    log_data.append(trade)
    
    with open(LOG_FILE, 'w') as f:
        json.dump(log_data, f, indent=4)
        
    print(f"\n[DASHBOARD UPDATE] Logged {win_loss_status.upper()} for {strategy_used}. PNL: {trade_profit}")

def display_dashboard():
    """Reads the JSON DB and prints a console dashboard summary."""
    if not os.path.exists(LOG_FILE):
        print("[!] No performance data found.")
        return

    with open(LOG_FILE, 'r') as f:
        log_data = json.load(f)

    strategies = {}
    for trade in log_data:
        strat = trade['strategy_used']
        if strat not in strategies:
            strategies[strat] = {'wins': 0, 'losses': 0, 'total': 0, 'profit': 0}
        
        strategies[strat]['total'] += 1
        strategies[strat]['profit'] += trade['profit']
        if trade['win_loss_status'] == 'win':
            strategies[strat]['wins'] += 1
        else:
            strategies[strat]['losses'] += 1

    print("\n" + "="*50)
    print("      OMNIVISION STRATEGY PERFORMANCE LOG")
    print("="*50)
    
    for strat, stats in strategies.items():
        win_rate = (stats['wins'] / stats['total']) * 100 if stats['total'] > 0 else 0
        pnl = stats['profit']
        print(f"Strategy : {strat.ljust(25)}")
        print(f"Win Rate : {win_rate:.2f}% ({stats['wins']}W / {stats['losses']}L)")
        print(f"Net PnL  : ${pnl:.2f}")
        print("-" * 50)
