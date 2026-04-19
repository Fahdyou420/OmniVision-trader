//+------------------------------------------------------------------+
//|                                         OmniVision_SMC_EA.mq5   |
//|                              Copyright 2026, OmniVision Ltd. V3  |
//|                                             https://omnivision.io|
//+------------------------------------------------------------------+
//  CHANGELOG V3:
//  + CMacroEngine — DXY / US10Y / VIX correlation evaluated daily.
//  + macroBias integer gates ALL Gold Long executions:
//      >= 0  → allowed              (Neutral / Bullish macro)
//      == -1 → filtered (light)     (Mild bearish — restricted)
//      <= -2 → HARD BLOCK on longs  (Strong DXY + rising yields)
//  + "(Macro Sync)" label injected into setup name when bias >= +1.
//  + Dashboard payload now includes full macro JSON fragment.
//  + HUD extended with live Macro Correlation panel (3 rows + gauge).
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmniVision Strategy Architect"
#property link      "https://omnivision.io"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include "OmniVision_Visual_Mentor.mqh"

//=== INPUT GROUPS ===================================================

input group "=== PROP FIRM RISK SETTINGS ==="
input double InpStartingBalance      = 100000.0;
input double InpBaseRiskPct          = 0.5;
input double InpMaxRiskPct           = 1.5;
input double InpMaxDailyDD           = 4.0;
input double InpMaxTotalDD           = 8.0;
input int    InpMaxTradesDay         = 5;
input double InpMaxLotSize           = 3.0;

input group "=== DAILY MONETARY GOALS ==="
input double InpDailyProfitTargetUSD = 1000.0;
input double InpDailyMaxLossUSD      = 500.0;

input group "=== DYNAMIC TRADE MANAGEMENT ==="
input double InpBreakEvenATR         = 1.5;
input double InpTrailStepATR         = 2.0;
input double InpStopLossBufferATR    = 0.5;
input bool   InpDynamicEarlyExit     = false;
input int    InpMaxConsecutiveDailyLoss = 2;

input group "=== SMART SESSION & TIME FILTERS ==="
input bool   InpUseSessionFilter     = true;
input string InpAsiaStart            = "00:00";
input string InpAsiaEnd              = "06:00";
input string InpLondonStart          = "07:00";
input string InpLondonEnd            = "15:00";
input string InpNyStart              = "13:00";
input string InpNyEnd                = "21:00";
input bool   InpTradeThursdays       = false;

//+------ NEW V3: MACRO CORRELATION SETTINGS -------------------------
input group "=== MACRO CORRELATION ENGINE (V3) ==="
input string InpDXYSymbol    = "USDX";   // DXY symbol (or leave blank for EURUSD proxy)
input string InpUS10YSymbol  = "US10Y";  // 10-Year Treasury symbol (CFD on broker)
input string InpVIXSymbol    = "VIX";    // VIX symbol (CFD on broker)
//--------------------------------------------------------------------

input group "=== DASHBOARD INTEGRATION ==="
input string InpServerUrl    = "http://localhost:3000/api/update_trade";

//=== GLOBAL COMPONENTS ==============================================
CTrade            Trade;
CStrategyManager  Strategy;
CStrategyManager* Scanners[];
CMacroEngine      Macro;          // ← V3 Macro engine
CHUD              Hud;

double InitialBalance;
double DailyStartBalance;
double HighestWatermarkEquity;
int    DailyTradesCount = 0;
int    DailyLossCount   = 0;
int    CurrentDay       = -1;
bool   IsTargetHitAnnounced = false;

//+------------------------------------------------------------------+
//| Session filter                                                   |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(!InpTradeThursdays && dt.day_of_week == 4) return false;
   string t = TimeToString(TimeCurrent(), TIME_MINUTES);
   bool isAsia   = (t >= InpAsiaStart   && t <= InpAsiaEnd);
   bool isLondon = (t >= InpLondonStart && t <= InpLondonEnd);
   bool isNY     = (t >= InpNyStart     && t <= InpNyEnd);
   return (isAsia || isLondon || isNY);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   InitialBalance          = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyStartBalance       = AccountInfoDouble(ACCOUNT_BALANCE);
   HighestWatermarkEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

   // ── V3: Initialise macro engine ──────────────────────────────
   Macro = CMacroEngine(InpDXYSymbol, InpUS10YSymbol, InpVIXSymbol);
   Macro.Init();

   // ── Multi-timeframe scanners ─────────────────────────────────
   ArrayResize(Scanners, 4);
   Scanners[0] = new CStrategyManager(PERIOD_M1);
   Scanners[1] = new CStrategyManager(PERIOD_M5);
   Scanners[2] = new CStrategyManager(PERIOD_M15);
   Scanners[3] = new CStrategyManager(PERIOD_M30);

   EventSetTimer(60);
   Strategy.CleanChart();
   Strategy.RenderMarketContext();

   Print("OmniVision SMC PRO V3.0 Initialized with Macro Correlation Engine.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Strategy.CleanChart();
   EventKillTimer();
   for(int i=0; i<ArraySize(Scanners); i++)
      if(CheckPointer(Scanners[i]) != POINTER_INVALID) delete Scanners[i];
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   Macro.Calculate();                // refresh macro on every timer tick
   Strategy.RenderMarketContext();
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
      Trade.PositionClose(PositionGetTicket(i));
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Recalculate macro biases first (cheap — reads Daily bar)
   Macro.Calculate();

   double currentBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(currentEq > HighestWatermarkEquity) HighestWatermarkEquity = currentEq;

   double dailyDD    = (DailyStartBalance - currentEq) / DailyStartBalance * 100.0;
   double absoluteDD = (InitialBalance    - currentEq) / InitialBalance    * 100.0;
   double trailingDD = (HighestWatermarkEquity - currentEq) / InitialBalance * 100.0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != CurrentDay)
   {
      CurrentDay          = dt.day;
      DailyTradesCount    = 0;
      DailyLossCount      = 0;
      IsTargetHitAnnounced = false;
      DailyStartBalance   = currentBal;
   }

   double dailyMonetaryPnL = currentEq - DailyStartBalance;

   // 2. HUD — now includes macro panel
   string phase = (iClose(_Symbol,_Period,0) > Strategy.GetEMA(200))
                  ? "Expansion (Bullish)" : "Retracement (Bearish)";
   string aiMsg = (PositionsTotal() > 0)
                  ? "Active Trade Monitoring..."
                  : (Macro.BlockAllLongs() ? "Macro BLOCKED — Scanning Shorts Only..." : "Scanning Confluence Matrix...");

   Hud.Render(dailyDD, absoluteDD, phase, aiMsg, Macro);

   // 3. Kill switches
   if(absoluteDD >= InpMaxTotalDD || trailingDD >= InpMaxTotalDD)
   {
      CloseAllPositions();
      Print("CRITICAL: MAX DRAWDOWN BREACHED. Trading halted permanently.");
      NotifyDashboard("RISK KILL SWITCH", 0, 0, "Account locked: Max Total DD reached.");
      ExpertRemove();
      return;
   }

   if(dailyDD >= InpMaxDailyDD || dailyMonetaryPnL <= -InpDailyMaxLossUSD)
   {
      if(PositionsTotal()>0) CloseAllPositions();
      if(!IsTargetHitAnnounced)
      {
         Print("WARNING: Daily Loss Limit Hit. Halting until tomorrow.");
         NotifyDashboard("DAILY LOSS HIT", 0, dailyMonetaryPnL, "Locked daily loss.");
         IsTargetHitAnnounced = true;
      }
      return;
   }

   if(dailyMonetaryPnL >= InpDailyProfitTargetUSD)
   {
      if(PositionsTotal()>0) CloseAllPositions();
      if(!IsTargetHitAnnounced)
      {
         Print("SUCCESS: Daily Profit Target Reached!");
         NotifyDashboard("DAILY TARGET HIT", 1, dailyMonetaryPnL,
                         "Locked $" + DoubleToString(dailyMonetaryPnL,2) + " profit.");
         IsTargetHitAnnounced = true;
      }
      return;
   }

   if(DailyTradesCount   >= InpMaxTradesDay)         return;
   if(DailyLossCount     >= InpMaxConsecutiveDailyLoss) return;

   // 4. Dynamic position management
   ManagePositions();

   // 5. Execution logic
   if(PositionsTotal()==0 && IsValidTradingSession())
   {
      CStrategyManager::Setup activeSetup;
      bool setupFound = false;

      // MTF scan — each scanner now forwards the macro engine
      for(int i=0; i<ArraySize(Scanners); i++)
      {
         if(Scanners[i].CheckConfluence(activeSetup, Macro))
         {
            setupFound = true;
            break;
         }
      }

      // Fallback to current chart TF
      if(!setupFound)
         setupFound = Strategy.CheckConfluence(activeSetup, Macro);

      if(setupFound)
      {
         double lot       = CalculateLot(activeSetup.sl);
         ENUM_ORDER_TYPE orderType = (activeSetup.type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

         if(Trade.PositionOpen(_Symbol, orderType, lot, activeSetup.entry,
                               activeSetup.sl, activeSetup.tp, activeSetup.name))
         {
            DailyTradesCount++;
            string macroNote = activeSetup.macro_confirmed
                               ? StringFormat(" | Macro Sync ✔ (bias=%+d)", Macro.macroBias)
                               : StringFormat(" | Macro Neutral (bias=%+d)", Macro.macroBias);
            NotifyDashboard(
               activeSetup.name, 0, 0,
               activeSetup.name + " Validated. Trade " + (string)DailyTradesCount
               + "/" + (string)InpMaxTradesDay + macroNote
            );
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Position Management (BE / Trail / Early Exit)                   |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr = Strategy.GetATR(14);
   if(atr <= 0) return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long   type        = PositionGetInteger(POSITION_TYPE);
      double entry       = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl  = PositionGetDouble(POSITION_SL);
      double current_tp  = PositionGetDouble(POSITION_TP);
      double open_profit = PositionGetDouble(POSITION_PROFIT);
      double cur_price   = (type==POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Dynamic early exit
      if(InpDynamicEarlyExit && open_profit > 0)
      {
         double ema10 = Strategy.GetEMA(10);
         if(type==POSITION_TYPE_BUY && cur_price<ema10 && Strategy.IsBearishEngulfing(1))
         {
            Trade.PositionClose(ticket);
            NotifyDashboard("Dynamic Early Exit", 1, open_profit, "Closed Long early - bearish reversal.");
            continue;
         }
         else if(type==POSITION_TYPE_SELL && cur_price>ema10 && Strategy.IsBullishEngulfing(1))
         {
            Trade.PositionClose(ticket);
            NotifyDashboard("Dynamic Early Exit", 1, open_profit, "Closed Short early - bullish reversal.");
            continue;
         }
      }

      double be_dist   = atr * InpBreakEvenATR;
      double trail_dist = atr * InpTrailStepATR;

      if(type == POSITION_TYPE_BUY)
      {
         if(cur_price - entry >= be_dist)
         {
            double new_sl = MathMax(cur_price - trail_dist, entry + 5*_Point);
            if(new_sl > current_sl || current_sl == 0)
               Trade.PositionModify(ticket, new_sl, current_tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(entry - cur_price >= be_dist)
         {
            double new_sl = MathMin(cur_price + trail_dist, entry - 5*_Point);
            if(new_sl < current_sl || current_sl == 0)
               Trade.PositionModify(ticket, new_sl, current_tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dynamic Lot Sizing                                               |
//+------------------------------------------------------------------+
double CalculateLot(double sl)
{
   double currentBal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL    = currentBal - DailyStartBalance;
   double dynamicRisk = InpBaseRiskPct;
   if(dailyPnL > 0)  dynamicRisk = MathMin(InpMaxRiskPct, InpBaseRiskPct + (dailyPnL/DailyStartBalance*100.0));
   else if(dailyPnL < 0) dynamicRisk = MathMax(0.5, InpBaseRiskPct - 0.5);

   double riskMoney = currentBal * dynamicRisk / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price     = (sl < bid) ? bid : ask;
   double slPoints  = MathAbs(price - sl) / tickSize;
   if(slPoints == 0) return 0.1;
   double lotSize = riskMoney / (slPoints * tickValue);
   lotSize = MathMin(lotSize, InpMaxLotSize);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return NormalizeDouble(MathMax(lotSize, minLot), 2);
}

//+------------------------------------------------------------------+
//| Trade event — track wins/losses                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double pnl  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            double comm = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
            double net  = pnl + swap + comm;
            string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            if(comment == "") comment = "TRADE CLOSED";

            if(net < 0)
            {
               DailyLossCount++;
               NotifyDashboard(comment, 0, net, "Trade closed - Loss. Streak: " + (string)DailyLossCount);
            }
            else
            {
               DailyLossCount = 0;
               NotifyDashboard(comment, 1, net, "Trade closed - Profit secured.");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard sync — now includes macro JSON block (V3)             |
//+------------------------------------------------------------------+
void NotifyDashboard(string strategy, int win, double pnl, string details)
{
   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Print("BACKTEST | Setup: ", strategy, " | PNL: ", pnl,
            " | macroBias: ", Macro.macroBias);
      return;
   }

   char   post_data[];
   char   result_data[];
   string result_headers;

   // V3: embed full macro JSON fragment inside the payload
   string json = StringFormat(
      "{"
        "\"strategy\":\"%s\","
        "\"win\":%s,"
        "\"pnl\":%f,"
        "\"absoluteBalance\":%f,"
        "\"narrativeUpdates\":{"
          "\"strategy\":\"%s\","
          "\"rationale\":\"MQL5 Pro V3 Engine — Macro Validated\","
          "\"details\":\"%s\""
        "},"
        "%s"
      "}",
      strategy,
      (win==1 ? "true" : "false"),
      pnl,
      AccountInfoDouble(ACCOUNT_BALANCE),
      strategy,
      details,
      Macro.ToJSON()          // ← appended macro block
   );

   StringToCharArray(json, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", InpServerUrl, "Content-Type: application/json\r\n",
              5000, post_data, result_data, result_headers);
}
