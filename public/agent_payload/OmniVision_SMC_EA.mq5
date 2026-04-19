//+------------------------------------------------------------------+
//|                                         OmniVision_SMC_EA.mq5    |
//|                                  Copyright 2026, OmniVision Ltd. |
//|                                             https://omnivision.io|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmniVision Strategy Architect"
#property link      "https://omnivision.io"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include "OmniVision_Visual_Mentor.mqh"

//--- INPUT PARAMETERS
input group "=== PROP FIRM RISK SETTINGS ==="
input double InpStartingBalance = 100000.0;// Prop Firm Starting Balance
input double InpBaseRiskPct  = 0.5;      // Base Risk Per Trade (%) -> 0.5% of 100k = $500
input double InpMaxRiskPct   = 1.5;      // Max Dynamic Compounding Risk (%)
input double InpMaxDailyDD   = 4.0;      // Max Daily Drawdown (%)
input double InpMaxTotalDD   = 8.0;      // Max Total Drawdown (%)
input int    InpMaxTradesDay = 5;        // Max Trades Per Day Limit
input double InpMaxLotSize   = 3.0;      // Max Lot Size Limit

input group "=== DAILY MONETARY GOALS ==="
input double InpDailyProfitTargetUSD = 1000.0; // Hard Daily Profit Target ($)
input double InpDailyMaxLossUSD      = 500.0;  // Hard Daily Max Loss ($)

input group "=== DYNAMIC TRADE MANAGEMENT ==="
input double InpBreakEvenATR     = 1.5;  // Target ATR Dist to trigger Break-even
input double InpTrailStepATR     = 2.0;  // Reduced choking: Trail wider at 2.0 ATR
input double InpStopLossBufferATR= 0.5;  // Stop Loss Wiggle Room (ATR)
input bool   InpDynamicEarlyExit = false;// Disabled early close to let 1:3 targets breathe
input int    InpMaxConsecutiveDailyLoss = 2; // Daily Loss Limit

input group "=== SMART SESSION & TIME FILTERS ==="
input bool   InpUseSessionFilter = true;     // Enable Active Session Control
input string InpAsiaStart        = "00:00";  // Asian Session Start
input string InpAsiaEnd          = "06:00";  // Asian Session End (Allow highly filtered setups)
input string InpLondonStart      = "07:00";  // London Session Start
input string InpLondonEnd        = "15:00";  // London Session End
input string InpNyStart          = "13:00";  // NY Session Start
input string InpNyEnd            = "21:00";  // NY Session End
input bool   InpTradeThursdays   = false;    // Disable Heavy CPI/News Days completely

input group "=== DASHBOARD INTEGRATION ==="
input string InpServerUrl    = "http://localhost:3000/api/update_trade"; // Dashboard API URL

//--- GLOBAL COMPONENTS
CTrade           Trade;
CStrategyManager Strategy; // Default for current chart drawing & management
CStrategyManager* Scanners[]; // Multi-timeframe scanners
CHUD             Hud;

double InitialBalance;
double DailyStartBalance;
double HighestWatermarkEquity;
int    DailyTradesCount = 0;
int    DailyLossCount = 0;
int    CurrentDay = -1;
bool   IsTargetHitAnnounced = false; // Flag to prevent repeated dashboard spam after target is hit

//+------------------------------------------------------------------+
//| Helper: Time & Day Filters                                       |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
   if(!InpUseSessionFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Avoid Thursday News Chop
   if(!InpTradeThursdays && dt.day_of_week == 4) return false;
   
   // Avoid Dead zone / spread hour (21:00 - 00:00)
   string t = TimeToString(TimeCurrent(), TIME_MINUTES);
   
   bool isAsia   = (t >= InpAsiaStart && t <= InpAsiaEnd);
   bool isLondon = (t >= InpLondonStart && t <= InpLondonEnd);
   bool isNY     = (t >= InpNyStart && t <= InpNyEnd);
   
   // We allow Asia, London, and NY, but block the transition/Rollover hours
   return (isAsia || isLondon || isNY);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Dynamically fetch starting balance so the backtester behaves correctly
   InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   HighestWatermarkEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Initialize multi-timeframe scanners specifically for Gold/DayTrading setups
   ArrayResize(Scanners, 4);
   Scanners[0] = new CStrategyManager(PERIOD_M1);
   Scanners[1] = new CStrategyManager(PERIOD_M5);
   Scanners[2] = new CStrategyManager(PERIOD_M15);
   Scanners[3] = new CStrategyManager(PERIOD_M30);

   EventSetTimer(60); // Visual refresh every minute
   Strategy.CleanChart();
   Strategy.RenderMarketContext();
   
   Print("OmniVision Pro V2.0 Initialized with MTF Scanning.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Strategy.CleanChart();
   EventKillTimer();
   
   for(int i=0; i<ArraySize(Scanners); i++) {
      if(CheckPointer(Scanners[i]) != POINTER_INVALID) delete Scanners[i];
   }
}

//+------------------------------------------------------------------+
//| Timer events for visual updates                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   Strategy.RenderMarketContext();
}

//+------------------------------------------------------------------+
//| Helper: Close All Positions                                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      Trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Calculate Risk Realtime & Trade Count
   double currentBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEq = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Track High Watermark for Trailing DD
   if(currentEq > HighestWatermarkEquity) HighestWatermarkEquity = currentEq;
   
   // Drawdown Calculations (Prop Firm Math)
   double dailyDD = (DailyStartBalance - currentEq) / DailyStartBalance * 100.0;
   double absoluteDD = (InitialBalance - currentEq) / InitialBalance * 100.0;
   double trailingDD = (HighestWatermarkEquity - currentEq) / InitialBalance * 100.0; // Prop firms usually trail relative to starting balance %
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != CurrentDay) {
      CurrentDay = dt.day;
      DailyTradesCount = 0;
      DailyLossCount = 0;
      IsTargetHitAnnounced = false;
      DailyStartBalance = currentBal; // Reset daily start
   }

   // Additional Daily Absolute Profit and Loss Calculations
   double dailyMonetaryPnL = currentEq - DailyStartBalance;
   
   // 2. Update HUD
   string phase = (iClose(_Symbol, _Period, 0) > Strategy.GetEMA(200)) ? "Expansion (Bullish)" : "Retracement (Bearish)";
   string aiMsg = (PositionsTotal() > 0) ? "Active Trade Monitoring..." : "Scanning Confluence Matrix...";
   Hud.Render(dailyDD, absoluteDD, phase, aiMsg);

   // 3. Risk Guard (KILL SWITCH)
   // Total Account Failures (Prop Firm Breach)
   if(absoluteDD >= InpMaxTotalDD || trailingDD >= InpMaxTotalDD)
   {
      CloseAllPositions();
      Print("CRITICAL: MAX DRAWDOWN BREACHED. Prop firm account failed. Trading Halted Permanently.");
      NotifyDashboard("RISK KILL SWITCH", 0, 0, "Account locked: Max Total DD reached.");
      ExpertRemove(); // Shut down EA entirely
      return;
   }
   
   // Daily Limits (Stop trading for the rest of today)
   if(dailyDD >= InpMaxDailyDD || dailyMonetaryPnL <= -InpDailyMaxLossUSD)
   {
      if(PositionsTotal() > 0) CloseAllPositions(); // Stop the bleeding
      if(!IsTargetHitAnnounced) {
         Print("WARNING: Daily Loss Limit Hit. Halting trades until tomorrow.");
         NotifyDashboard("DAILY LOSS HIT", 0, dailyMonetaryPnL, "Locked daily loss, waiting for next day.");
         IsTargetHitAnnounced = true; // Use this flag to stop repeated spam
      }
      return; 
   }
   
   // Stop trading for the day if we hit our daily profit target of $1,000
   if(dailyMonetaryPnL >= InpDailyProfitTargetUSD)
   {
      if(PositionsTotal() > 0) CloseAllPositions(); // Secure the daily bag!
      if(!IsTargetHitAnnounced) {
         Print("SUCCESS: Daily Profit Target Reached! Halting new trades for today.");
         NotifyDashboard("DAILY TARGET HIT", 1, dailyMonetaryPnL, "Locked in $" + DoubleToString(dailyMonetaryPnL, 2) + " profit.");
         IsTargetHitAnnounced = true;
      }
      return;
   }
   
   if(DailyTradesCount >= InpMaxTradesDay) return;
   if(DailyLossCount >= InpMaxConsecutiveDailyLoss) return; // Prevent tilt/revenge logic streaks
   
   // 4. Dynamic Trade Management (BE, Trail, Early Exit)
   ManagePositions();

   // 5. Execution Logic
   if(PositionsTotal() == 0 && IsValidTradingSession()) // Ensure we strictly trade within verified sessions
   {
      CStrategyManager::Setup activeSetup;
      bool setupFound = false;
      
      // Target multiple timeframes at once (M1, M5, M15, M30)
      for(int i=0; i<ArraySize(Scanners); i++) {
         if(Scanners[i].CheckConfluence(activeSetup)) {
            setupFound = true;
            break;
         }
      }
      
      // Fallback to Current Chart Timeframe
      if(!setupFound) {
         if(Strategy.CheckConfluence(activeSetup)) {
            setupFound = true;
         }
      }
      
      if(setupFound)
      {
         double lot = CalculateLot(activeSetup.sl);
         ENUM_ORDER_TYPE order_type = (activeSetup.type == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         if(Trade.PositionOpen(_Symbol, order_type, lot, activeSetup.entry, activeSetup.sl, activeSetup.tp, activeSetup.name))
         {
            DailyTradesCount++;
            NotifyDashboard(activeSetup.name, 0, 0, activeSetup.name + " Validated. Daily Trade: " + (string)DailyTradesCount + "/" + (string)InpMaxTradesDay);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dynamic Position Management (BE, Trailing, Early Exit)           |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr = Strategy.GetATR(14);
   if(atr <= 0) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      double open_profit = PositionGetDouble(POSITION_PROFIT);
      double current_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Dynamic Early Exit: Close full profit if momentum turns sharply while heavily in the money
      if(InpDynamicEarlyExit && open_profit > 0)
      {
         double ema10 = Strategy.GetEMA(10);
         if(type == POSITION_TYPE_BUY && current_price < ema10 && Strategy.IsBearishEngulfing(1)) 
         {
            Trade.PositionClose(ticket);
            NotifyDashboard("Dynamic Early Exit", 1, open_profit, "Closed Long early - bearish reversal in profit.");
            continue;
         }
         else if(type == POSITION_TYPE_SELL && current_price > ema10 && Strategy.IsBullishEngulfing(1)) 
         {
            Trade.PositionClose(ticket);
            NotifyDashboard("Dynamic Early Exit", 1, open_profit, "Closed Short early - bullish reversal in profit.");
            continue;
         }
      }
      
      // Break-even and Trailing Stop
      double be_trigger_dist = atr * InpBreakEvenATR;
      double trail_dist = atr * InpTrailStepATR;
      
      if(type == POSITION_TYPE_BUY)
      {
         if(current_price - entry >= be_trigger_dist)
         {
            double new_sl = current_price - trail_dist;
            // Enforce minimum Break-even (+5 points to cover fees/spread)
            new_sl = MathMax(new_sl, entry + 5*_Point); 
            if(new_sl > current_sl || current_sl == 0)
            {
               Trade.PositionModify(ticket, new_sl, current_tp);
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(entry - current_price >= be_trigger_dist)
         {
            double new_sl = current_price + trail_dist;
            // Enforce minimum Break-even (-5 points to cover fees/spread)
            new_sl = MathMin(new_sl, entry - 5*_Point); 
            if(new_sl < current_sl || current_sl == 0)
            {
               Trade.PositionModify(ticket, new_sl, current_tp);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Dynamic Lot Sizing & Asymmetric Compounding              |
//+------------------------------------------------------------------+
double CalculateLot(double sl)
{
   double currentBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL = currentBal - DailyStartBalance;
   
   // Dynamic Risk Scaling: 
   // Scale up aggressively ONLY on house money (Winning streak limit: InpMaxRiskPct)
   // Scale down defensively to 0.5% during daily drawdowns to prevent bust
   double dynamicRisk = InpBaseRiskPct;
   if(dailyPnL > 0) dynamicRisk = MathMin(InpMaxRiskPct, InpBaseRiskPct + (dailyPnL / DailyStartBalance * 100.0));
   else if(dailyPnL < 0) dynamicRisk = MathMax(0.5, InpBaseRiskPct - 0.5);
   
   double riskMoney = currentBal * dynamicRisk / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (sl < bid) ? bid : ask;
   
   double slPoints = MathAbs(price - sl) / tickSize;
   if(slPoints == 0) return 0.1;
   
   double lotSize = riskMoney / (slPoints * tickValue);
   lotSize = MathMin(lotSize, InpMaxLotSize); // Enforce absolute ceiling
   
   // Ensure minimum lot size boundary (broker standard)
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lotSize = MathMax(lotSize, minLot);
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Trade Event Hook - Track Win/Loss States & Sync Dashboard        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
             double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
             double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
             double comm = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
             double net = pnl + swap + comm;
             string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
             if(comment == "") comment = "TRADE CLOSED";
             
             if(net < 0) {
                DailyLossCount++;
                NotifyDashboard(comment, 0, net, "Trade closed - Loss. Daily Streak: " + (string)DailyLossCount);
             }
             else {
                DailyLossCount = 0; // Reset consecutive losses on win
                NotifyDashboard(comment, 1, net, "Trade closed - Profit secured.");
             }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Web Integration - Sync with Node Backend                         |
//+------------------------------------------------------------------+
void NotifyDashboard(string strategy, int win, double pnl, string details)
{
   // Isolate EA from Python/Node during Strategy Testing to avoid WebRequest blocks/errors
   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Print("BACKTEST METRIC | Setup: ", strategy, " | PNL: ", pnl);
      return; // Skip WebRequest during backend simulation
   }

   char post_data[];
   char result_data[];
   string result_headers;
   
   string json = StringFormat("{\"strategy\":\"%s\", \"win\":%s, \"pnl\":%f, \"absoluteBalance\":%f, \"narrativeUpdates\":{\"strategy\":\"%s\", \"rationale\":\"MQL5 Pro V2 Engine\", \"details\":\"%s\"}}",
                              strategy, (win==1 ? "true" : "false"), pnl, AccountInfoDouble(ACCOUNT_BALANCE), strategy, details);
   
   StringToCharArray(json, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", InpServerUrl, "Content-Type: application/json\r\n", 5000, post_data, result_data, result_headers);
}
