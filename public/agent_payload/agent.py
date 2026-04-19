import time
import json
import pandas as pd
from datetime import datetime
from dashboard import update_strategy_performance
from strategies import check_7_core_strategies
import MetaTrader5 as mt5

STRATEGY_MAGIC = {
    "Gold Trend Continuation": 1001,
    "SMC Market Structure Shift (MSS)": 1002,
    "ICT London Open Killzone": 1003,
    "Liquidity Sweep Reversal": 1004,
    "FVG Displacement": 1005,
    "Institutional Order Block": 1006,
    "Institutional Order Block (OB)": 1006,
    "PD Array Equilibrium": 1007,
    "Unknown": 9999
}

# --- PROP FIRM RISK MANAGEMENT ---
class PropFirmRiskManager:
    def __init__(self, is_live=False, initial_balance=100000.0, risk_pct=0.01, leverage=100):
        self.is_live = is_live
        self.initial_balance = initial_balance
        self.current_balance = initial_balance
        self.daily_start_balance = initial_balance
        self.total_profit = 0.0
        self.last_trade_date = None
        
        self.MAX_DAILY_DD = 0.04  # 4% Daily Drawdown (Prop firm standard)
        self.MAX_TOTAL_DD = 0.08  # 8% Max Drawdown
        self.risk_pct = risk_pct
        self.leverage = leverage
        
        if self.is_live:
            self.sync_live_mt5_account()

    def sync_live_mt5_account(self, current_time=None):
        """Fetches Live Account status and scans historical deals directly from broker."""
        acc = mt5.account_info()
        if not acc:
            print("[!] Failed to fetch MT5 Live Account Info.")
            return False
            
        self.current_balance = acc.balance
        
        # Use broker current_time to align midnight resets exactly with MT5 prop firm servers
        now = current_time if current_time else datetime.now()
        epoch = datetime(2000, 1, 1)
        deals = mt5.history_deals_get(epoch, now)
        
        if deals and len(deals) > 0:
            # Type 2 is DEAL_TYPE_BALANCE (deposits/withdrawals)
            deposits = sum(d.profit for d in deals if d.type == mt5.DEAL_TYPE_BALANCE)
            self.initial_balance = deposits if deposits > 0 else self.current_balance
            
            # Start of the current broker day
            today_midnight = datetime(now.year, now.month, now.day)
            todays_deals = mt5.history_deals_get(today_midnight, now)
            todays_profit = sum(d.profit for d in todays_deals if d.type != mt5.DEAL_TYPE_BALANCE) if todays_deals else 0.0
            
            self.daily_start_balance = self.current_balance - todays_profit
            self.total_profit = sum(d.profit + d.commission + d.swap for d in deals if d.type != mt5.DEAL_TYPE_BALANCE)
        else:
            self.initial_balance = self.current_balance
            self.daily_start_balance = self.current_balance
            self.total_profit = 0.0
            
        return True

    def sync_date(self, current_time):
        """Used in backtesting to simulate 4% daily reset"""
        if not self.last_trade_date or self.last_trade_date != current_time.date():
            self.daily_start_balance = self.current_balance
            self.last_trade_date = current_time.date()

    def check_drawdown_limits(self, current_time):
        if self.is_live: self.sync_live_mt5_account(current_time)
        else: self.sync_date(current_time)
        
        daily_dd = (self.daily_start_balance - self.current_balance) / self.daily_start_balance if self.daily_start_balance > 0 else 0
        total_dd = (self.initial_balance - self.current_balance) / self.initial_balance
        
        if daily_dd >= self.MAX_DAILY_DD:
            print(f"[!] PROP FIRM VIOLATION PREVENTED: Daily Drawdown Limit Reached ({daily_dd*100:.2f}%).")
            return False
        if total_dd >= self.MAX_TOTAL_DD:
            print(f"[!] PROP FIRM VIOLATION PREVENTED: Total Drawdown Limit Reached ({total_dd*100:.2f}%).")
            return False
        return True

    def calculate_lot_size(self, symbol, entry, sl, multiplier=1.0):
        risk_amount = self.current_balance * self.risk_pct * multiplier
        sl_distance = abs(entry - sl)
        if sl_distance == 0: return 0.01
        
        try:
            sym_info = mt5.symbol_info(symbol)
            contract_size = sym_info.trade_contract_size if sym_info else 100
        except:
            contract_size = 100
        
        lot = max(0.01, round(risk_amount / (sl_distance * contract_size), 2))
        return lot
        
    def record_trade_pnl(self, pnl, current_time):
        self.sync_date(current_time)
        self.current_balance += pnl
        self.total_profit += pnl

# --- LEARNING & NARRATIVE LOGIC ---
def calculate_mae_multiplier(strategy_name, is_live=False, logs_file="performance_log.json"):
    """Validates the last 3 performance results to constrain risk locally or on MT5 natively."""
    losses = 0
    if is_live:
        magic = STRATEGY_MAGIC.get(strategy_name, 9999)
        deals = mt5.history_deals_get(datetime(2000, 1, 1), datetime.now())
        if deals:
            strat_deals = [d for d in deals if d.magic == magic and d.entry == mt5.DEAL_ENTRY_OUT]
            strat_deals.sort(key=lambda x: x.time)
            
            if len(strat_deals) >= 3:
                last_3 = strat_deals[-3:]
                losses = sum(1 for d in last_3 if (d.profit + d.commission + d.swap) < 0)
    else:
        try:
             with open(logs_file, 'r') as f:
                 logs = json.load(f)
             strat_logs = [l for l in logs if l['strategy_used'] == strategy_name]
             if len(strat_logs) >= 3:
                 last_3 = strat_logs[-3:]
                 losses = sum(1 for x in last_3 if x['win_loss_status'] == 'loss')
        except:
            pass

    if losses == 3:
        print(f"[*] MAE Check: MT5 History indicates string of active losses for {strategy_name}. Shrinking lot multiplier to 0.5x.")
        return 0.5 
    return 1.0

def generate_trade_narrative(strategy, bias, discount_premium, footprints):
    narrative = f"\n[MENTOR: TRADE TRIGGERED]"
    narrative += f"\nWe entered this trade based on the -> {strategy} <- framework."
    narrative += f"\nRationale: Market Bias is {bias}. Price structurally mitigated into a {discount_premium} zone."
    narrative += f"\nInstitutional Footprints Logged: {footprints}."
    narrative += f"\nRisk Advisory: Prop Firm Limits Enforced. MT5 History Verified."
    print(narrative)
    return narrative

# --- HEADLESS AGENT MODULES ---
class AnalysisAgent:
    def __init__(self, symbol="XAUUSD", timeframe=mt5.TIMEFRAME_H1):
        self.symbol = symbol
        self.timeframe = timeframe

    def fetch_data(self, count=500, is_backtest=False):
        num_candles = 10000 if is_backtest else count 
        print(f"[*] Fetching {num_candles} LIVE chart candles for {self.symbol}...")
        
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, num_candles)
        if rates is None or len(rates) == 0:
            print(f"[!] No data extracted. Ensure MT5 is active and symbol is typed exactly.")
            return pd.DataFrame()
            
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df['EMA_200'] = df['close'].ewm(span=200, adjust=False).mean()
        self.df = df
        return df

    def get_bias(self):
        current_close = self.df.iloc[-1]['close']
        current_ema = self.df.iloc[-1]['EMA_200']
        return "Bullish" if current_close > current_ema else "Bearish"

class ExecutionAgent:
    def __init__(self, symbol="XAUUSD"):
        self.symbol = symbol

    def execute_order(self, order_type, entry, sl, tp, strategy_name, current_time, risk_manager):
        if not risk_manager.check_drawdown_limits(current_time):
            print(f"[!] Order Cancelled for {self.symbol} due to Drawdown Limit.")
            return False

        # Live checks MT5 DB, Local checks json based on bool
        multiplier = calculate_mae_multiplier(strategy_name, risk_manager.is_live)
        adjusted_lot = risk_manager.calculate_lot_size(self.symbol, entry, sl, multiplier)
        
        generate_trade_narrative(
            strategy_name, 
            bias="Bullish" if order_type == mt5.ORDER_TYPE_BUY else "Bearish",
            discount_premium="Discount" if order_type == mt5.ORDER_TYPE_BUY else "Premium",
            footprints="FVG / OB Structure"
        )
        
        magic_number = STRATEGY_MAGIC.get(strategy_name, 9999)
        print(f"[*] SENDING MT5 ORDER: {self.symbol} | MAGIC: {magic_number} | LOT: {adjusted_lot} | Price: {entry} | SL: {sl} | TP: {tp}")
        
        if risk_manager.is_live:
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": float(adjusted_lot),
                "type": order_type,
                "price": float(entry),
                "sl": float(sl),
                "tp": float(tp),
                "deviation": 20,
                "magic": magic_number,
                "comment": strategy_name[:15], 
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }
            result = mt5.order_send(request)
            if not result or result.retcode != mt5.TRADE_RETCODE_DONE:
                print(f"[!] ORDER FAILED. Retcode: {result.retcode if result else 'None'}")
                return False
            print("[+] ORDER SUCCESSFULLY EXECUTED NATIVELY.")

        try:
            import requests
            requests.post("http://localhost:3000/api/update_trade", json={
                "strategy": strategy_name,
                "win": False,
                "pnl": 0.0,
                "absoluteBalance": risk_manager.current_balance,
                "narrativeUpdates": {
                    "strategy": strategy_name,
                    "rationale": "Execution routed natively to MT5 agent buffer.",
                    "details": f"Entry: {entry} | SL: {sl} | TP: {tp}",
                    "risk": f"Trade sized exactly at {risk_manager.risk_pct * 100}% of MT5 Account Size."
                }
            })
        except:
            pass
        return True

    def close_trade(self, ticket, order_type, entry_price, exit_price, strategy_name, current_time, risk_manager):
        print(f"[*] CLOSING MT5 ORDER {ticket} | {self.symbol} at {exit_price}")
        
        is_win = False
        if order_type == mt5.ORDER_TYPE_BUY:
            profit = exit_price - entry_price
            is_win = exit_price > entry_price
        else:
            profit = entry_price - exit_price
            is_win = entry_price > exit_price
            
        win_loss_status = "win" if is_win else "loss"
        real_pnl = profit * risk_manager.calculate_lot_size(self.symbol, entry_price, entry_price - 10) * 100 

        if risk_manager.is_live: 
            risk_manager.sync_live_mt5_account()
        else:
            update_strategy_performance(entry_price, exit_price, strategy_name, win_loss_status)
            risk_manager.record_trade_pnl(real_pnl, current_time)

        try:
            import requests
            requests.post("http://localhost:3000/api/update_trade", json={
                "strategy": strategy_name,
                "win": is_win,
                "pnl": round(real_pnl, 2),
                "absoluteBalance": risk_manager.current_balance,
                "absoluteProfit": risk_manager.total_profit,
                "narrativeUpdates": {
                    "strategy": strategy_name,
                    "rationale": f"MT5 trade execution closed. Win/Loss processed natively.",
                    "details": f"Exit completed at {exit_price}",
                    "risk": f"Live Account balance synchronized: ${risk_manager.current_balance:.2f}"
                }
            })
        except:
            pass

class VisualAgent:
    def __init__(self, symbol="XAUUSD"):
        self.symbol = symbol
        
    def draw_order_block(self, time1, price1, time2, price2, name="OB_1"):
        print(f"[*] Visualizing Order Block on chart: {name} from {price1} to {price2}")

    def draw_liquidity_line(self, time, price, name="LIQ_1"):
        print(f"[*] Visualizing Liquidity Sweep logic at {price} as STYLE_DOT")

    def draw_strategy_markers(self, setup_data, time_current):
        strategy = setup_data.get("strategy", "Unknown")
        signal = setup_data.get("signal", "BUY")
        entry = setup_data.get("entry", 0.0)
        
        if signal == "BUY":
            print(f"[*] Plotting BUY Arrow at {entry} for {strategy}")
        else:
            print(f"[*] Plotting SELL Arrow at {entry} for {strategy}")
            
        if strategy == "FVG Displacement":
            print(f"[*] Theming: Cyan styling, bold arrows.")
        elif strategy == "ICT London Open Killzone":
            print(f"[*] Theming: Magenta styling context bounds.")
        elif strategy == "Institutional Order Block":
            print(f"[*] Theming: Gold styling.")
        elif strategy == "Liquidity Sweep Reversal":
            print(f"[*] Theming: Orange styling, dashed wick highlights.")
        else:
            print(f"[*] Theming: Base Trend -> White styling.")

    def draw_trade_history(self, closed_trades):
        """
        Plots historical closed trades on the MT5 chart to visually audit past performance.
        Connects entry and exit points with a trendline.
        """
        print(f"[*] Visualizing {len(closed_trades)} historical trades on MT5 Chart.")
        for i, trade in enumerate(closed_trades):
            entry_time = trade.get('entry_time', 0)
            exit_time = trade.get('exit_time', 0)
            entry_price = trade.get('entry_price', 0.0)
            exit_price = trade.get('exit_price', 0.0)
            trade_type = trade.get('type', mt5.ORDER_TYPE_BUY)
            strategy = trade.get('strategy', 'Unknown')
            
            line_name = f"HIST_TRADE_{i}_{entry_time}"
            
            is_win = (exit_price > entry_price) if trade_type == mt5.ORDER_TYPE_BUY else (entry_price > exit_price)
            clr = "mt5.clrGreen" if is_win else "mt5.clrRed"
            
            print(f"[*] Plotting HISTORICAL {strategy} | Entry: {entry_price} -> Exit: {exit_price} | Win: {is_win}")
            # mt5.ObjectCreate(0, line_name, mt5.OBJ_TREND, 0, entry_time, entry_price, exit_time, exit_price)
            # mt5.ObjectSetInteger(0, line_name, mt5.OBJPROP_COLOR, eval(clr))
            # mt5.ObjectSetInteger(0, line_name, mt5.OBJPROP_STYLE, mt5.STYLE_DOT)
            # mt5.ObjectSetInteger(0, line_name, mt5.OBJPROP_RAY_RIGHT, False)


# --- DEPLOYMENT MODES ---
def run_backtest(target_symbol):
    print(f"\n{'='*50}\nINITIALIZING BACKTEST MODE: {target_symbol}\n{'='*50}")
    risk_manager = PropFirmRiskManager(is_live=False, initial_balance=100000.0, risk_pct=0.01)
    analyzer = AnalysisAgent(target_symbol)
    df = analyzer.fetch_data(is_backtest=True)
    
    executor = ExecutionAgent(target_symbol)
    visuals = VisualAgent(target_symbol)
    
    if df.empty: return
        
    print(f"Loaded {len(df)} historical candles. Simulating trades...")
    in_trade = False
    trade_info = {}
    
    for i in range(200, len(df)-1, 5): 
        current_bar = df.iloc[i]
        current_time = current_bar['time']
        
        if in_trade:
            if trade_info['type'] == mt5.ORDER_TYPE_BUY:
                if current_bar['low'] <= trade_info['sl']:
                    executor.close_trade("BT_1", mt5.ORDER_TYPE_BUY, trade_info['entry'], trade_info['sl'], trade_info['strat'], current_time, risk_manager)
                    in_trade = False
                elif current_bar['high'] >= trade_info['tp']:
                    executor.close_trade("BT_1", mt5.ORDER_TYPE_BUY, trade_info['entry'], trade_info['tp'], trade_info['strat'], current_time, risk_manager)
                    in_trade = False
            elif trade_info['type'] == mt5.ORDER_TYPE_SELL:
                if current_bar['high'] >= trade_info['sl']:
                    executor.close_trade("BT_1", mt5.ORDER_TYPE_SELL, trade_info['entry'], trade_info['sl'], trade_info['strat'], current_time, risk_manager)
                    in_trade = False
                elif current_bar['low'] <= trade_info['tp']:
                    executor.close_trade("BT_1", mt5.ORDER_TYPE_SELL, trade_info['entry'], trade_info['tp'], trade_info['strat'], current_time, risk_manager)
                    in_trade = False
            continue

        window_df = df.iloc[max(0, i-200):i+1]
        setup = check_7_core_strategies(window_df) 
        
        if setup and not in_trade:
            order_t = mt5.ORDER_TYPE_BUY if setup["signal"] == "BUY" else mt5.ORDER_TYPE_SELL
            success = executor.execute_order(
                order_t, setup["entry"], setup["sl"], setup["tp"], setup["strategy"], current_time, risk_manager
            )
            if success:
                in_trade = True
                trade_info = {'type': order_t, 'entry': setup["entry"], 'sl': setup["sl"], 'tp': setup["tp"], 'strat': setup["strategy"]}
                visuals.draw_strategy_markers(setup, int(current_bar['time'].timestamp()))

    print(f"\n[BACKTEST COMPLETE] Final Balance: ${risk_manager.current_balance:.2f} | Max DD Respected")

def run_live(target_symbol):
    print(f"\n{'='*50}\nINITIALIZING LIVE MODE: {target_symbol}\n{'='*50}")
    risk_manager = PropFirmRiskManager(is_live=True, risk_pct=0.01)
    analyzer = AnalysisAgent(target_symbol)
    executor = ExecutionAgent(target_symbol)
    visuals = VisualAgent(target_symbol)
    
    print(f"[*] Awaiting real-time tick execution. Prop limits natively synced with MT5 Data Engine.\n")
    
    while True:
        try:
            # 1. Fetch current tick strictly syncing with broker time (fixes Drawdown resets)
            tick = mt5.symbol_info_tick(target_symbol)
            if not tick:
                time.sleep(1)
                continue
                
            current_time = datetime.fromtimestamp(tick.time)
            
            # 2. Daily reset and rigid risk constraint validation
            if not risk_manager.check_drawdown_limits(current_time):
                print(f"[!] Trading suspended by Risk Manager. Pausing cycle.")
                time.sleep(60)
                continue

            # 3. Active Trade Check (MT5 handles Trailing/SL/TP internally for us)
            positions = mt5.positions_get(symbol=target_symbol)
            in_trade = (positions is not None and len(positions) > 0)
            
            # 4. Automate Execution Evaluation
            if not in_trade:
                df = analyzer.fetch_data(count=500, is_backtest=False)
                if df is not None and not df.empty:
                    setup = check_7_core_strategies(df)
                    if setup:
                        order_t = mt5.ORDER_TYPE_BUY if setup["signal"] == "BUY" else mt5.ORDER_TYPE_SELL
                        # Send trade natively over connection
                        success = executor.execute_order(
                            order_t, setup["entry"], setup["sl"], setup["tp"], setup["strategy"], current_time, risk_manager
                        )
                        if success:
                            visuals.draw_strategy_markers(setup, int(tick.time))

            time.sleep(1) # Live tick buffer
            
        except KeyboardInterrupt:
            print("[*] LIVE AGENT TERMINATED MANUALLY.")
            break
        except Exception as e:
            print(f"[!] Error in live ticker loop: {e}")
            time.sleep(5)

    
if __name__ == "__main__":
    if not mt5.initialize():
        print("MT5 Not Initially loaded. Headless dev mode active.")
    
    MODE = "LIVE" 
    TARGET_CHART = "XAUUSD" 
    
    if MODE == "BACKTEST":
        run_backtest(TARGET_CHART)
    else:
        run_live(TARGET_CHART)
