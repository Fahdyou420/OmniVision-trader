//+------------------------------------------------------------------+
//|                                     OmniVision_Visual_Mentor.mqh |
//|                                  Copyright 2026, OmniVision Ltd. |
//|                                             https://omnivision.io|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmniVision"
#property link      "https://omnivision.io"
#property strict

#include <Trade\Trade.mqh>

//--- Object Prefix
#define OBJ_PREFIX "OmniViz_"

//+------------------------------------------------------------------+
//| Base Visualizer Class                                            |
//+------------------------------------------------------------------+
class CVisualizer
{
protected:
   string m_prefix;
public:
   CVisualizer() { m_prefix = OBJ_PREFIX; }
   ~CVisualizer() {}
   
   void CleanChart() { ObjectsDeleteAll(0, m_prefix); }
   
   void DrawRect(string name, datetime t1, double p1, datetime t2, double p2, color clr, bool fill=true)
   {
      string full_name = m_prefix + name;
      ObjectCreate(0, full_name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, full_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, full_name, OBJPROP_FILL, fill);
      ObjectSetInteger(0, full_name, OBJPROP_BACK, true);
      ObjectSetInteger(0, full_name, OBJPROP_SELECTABLE, false);
   }

   void DrawLine(string name, double price, color clr, ENUM_LINE_STYLE style=STYLE_SOLID, int width=1)
   {
      string full_name = m_prefix + name;
      ObjectCreate(0, full_name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, full_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, full_name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, full_name, OBJPROP_WIDTH, width);
   }

   void DrawText(string name, datetime t, double p, string txt, color clr, int size=10)
   {
      string full_name = m_prefix + name;
      ObjectCreate(0, full_name, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, full_name, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, full_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, full_name, OBJPROP_FONTSIZE, size);
   }
};

//+------------------------------------------------------------------+
//| Confluence & Strategy Manager Class                              |
//+------------------------------------------------------------------+
class CStrategyManager : public CVisualizer
{
private:
   ENUM_TIMEFRAMES m_tf;
   int h_ema10, h_ema50, h_ema200;
   int h_ema50_htf1, h_ema200_htf1;
   int h_ema50_htf2, h_ema200_htf2;
   int h_ema50_m15, h_ema200_m15;
   int h_ema50_h1, h_ema200_h1;
   int h_ema50_h4, h_ema200_h4;
   int h_ema50_d1, h_ema200_d1;
   int h_rsi, h_atr;
   
   ENUM_TIMEFRAMES GetHTF1() {
      if(m_tf == PERIOD_M1) return PERIOD_M5;
      if(m_tf == PERIOD_M5) return PERIOD_M15;
      if(m_tf <= PERIOD_M15) return PERIOD_H1;
      if(m_tf <= PERIOD_H1) return PERIOD_H4;
      return PERIOD_D1;
   }
   
   ENUM_TIMEFRAMES GetHTF2() {
      if(m_tf == PERIOD_M1) return PERIOD_M15;
      if(m_tf == PERIOD_M5) return PERIOD_H1;
      if(m_tf <= PERIOD_M15) return PERIOD_H4;
      if(m_tf <= PERIOD_H1) return PERIOD_D1;
      return PERIOD_W1;
   }

   void InitIndicators() {
      if(h_ema10 == INVALID_HANDLE) h_ema10 = iMA(_Symbol, m_tf, 10, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50 == INVALID_HANDLE) h_ema50 = iMA(_Symbol, m_tf, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200 == INVALID_HANDLE) h_ema200 = iMA(_Symbol, m_tf, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_rsi == INVALID_HANDLE) h_rsi = iRSI(_Symbol, m_tf, 14, PRICE_CLOSE);
      if(h_atr == INVALID_HANDLE) h_atr = iATR(_Symbol, m_tf, 14);
      
      if(h_ema50_htf1 == INVALID_HANDLE) h_ema50_htf1 = iMA(_Symbol, GetHTF1(), 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_htf1 == INVALID_HANDLE) h_ema200_htf1 = iMA(_Symbol, GetHTF1(), 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_htf2 == INVALID_HANDLE) h_ema50_htf2 = iMA(_Symbol, GetHTF2(), 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_htf2 == INVALID_HANDLE) h_ema200_htf2 = iMA(_Symbol, GetHTF2(), 200, 0, MODE_EMA, PRICE_CLOSE);
      
      // Global Timeframes for the "All Timeframe" Filter
      if(h_ema50_m15 == INVALID_HANDLE) h_ema50_m15 = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_m15 == INVALID_HANDLE) h_ema200_m15 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_h1 == INVALID_HANDLE) h_ema50_h1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_h1 == INVALID_HANDLE) h_ema200_h1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_h4 == INVALID_HANDLE) h_ema50_h4 = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_h4 == INVALID_HANDLE) h_ema200_h4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_d1 == INVALID_HANDLE) h_ema50_d1 = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_d1 == INVALID_HANDLE) h_ema200_d1 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   }

   double GetVal(int handle) {
      if(handle == INVALID_HANDLE) return 0.0;
      double val[1];
      if(CopyBuffer(handle, 0, 0, 1, val) > 0) return val[0];
      return 0.0;
   }

public:
   CStrategyManager(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
      m_tf = (tf == PERIOD_CURRENT) ? _Period : tf;
      h_ema10 = INVALID_HANDLE; h_ema50 = INVALID_HANDLE; h_ema200 = INVALID_HANDLE;
      h_ema50_htf1 = INVALID_HANDLE; h_ema200_htf1 = INVALID_HANDLE;
      h_ema50_htf2 = INVALID_HANDLE; h_ema200_htf2 = INVALID_HANDLE;
      h_ema50_m15 = INVALID_HANDLE; h_ema200_m15 = INVALID_HANDLE;
      h_ema50_h1 = INVALID_HANDLE; h_ema200_h1 = INVALID_HANDLE;
      h_ema50_h4 = INVALID_HANDLE; h_ema200_h4 = INVALID_HANDLE;
      h_ema50_d1 = INVALID_HANDLE; h_ema200_d1 = INVALID_HANDLE;
      h_rsi = INVALID_HANDLE; h_atr = INVALID_HANDLE;
   }
   
   bool GlobalTrendIsBullish() {
      InitIndicators();
      return (GetVal(h_ema50_m15) > GetVal(h_ema200_m15) && 
              GetVal(h_ema50_h1) > GetVal(h_ema200_h1) && 
              GetVal(h_ema50_h4) > GetVal(h_ema200_h4) && 
              GetVal(h_ema50_d1) > GetVal(h_ema200_d1));
   }
   
   bool GlobalTrendIsBearish() {
      InitIndicators();
      return (GetVal(h_ema50_m15) < GetVal(h_ema200_m15) && 
              GetVal(h_ema50_h1) < GetVal(h_ema200_h1) && 
              GetVal(h_ema50_h4) < GetVal(h_ema200_h4) && 
              GetVal(h_ema50_d1) < GetVal(h_ema200_d1));
   }
   
   double GetEMA(int period) {
      InitIndicators();
      if(period == 10) return GetVal(h_ema10);
      if(period == 50) return GetVal(h_ema50);
      if(period == 200) return GetVal(h_ema200);
      return 0.0;
   }
   
   double GetEMA50_HTF1() { InitIndicators(); return GetVal(h_ema50_htf1); }
   double GetEMA200_HTF1() { InitIndicators(); return GetVal(h_ema200_htf1); }
   double GetEMA50_HTF2() { InitIndicators(); return GetVal(h_ema50_htf2); }
   double GetEMA200_HTF2() { InitIndicators(); return GetVal(h_ema200_htf2); }

   double GetRSI(int period=14) { InitIndicators(); return GetVal(h_rsi); }
   double GetATR(int period=14) { InitIndicators(); return GetVal(h_atr); }

   bool IsBullishEngulfing(int i = 1)
   {
      double open1 = iOpen(_Symbol, m_tf, i);
      double close1 = iClose(_Symbol, m_tf, i);
      double open2 = iOpen(_Symbol, m_tf, i+1);
      double close2 = iClose(_Symbol, m_tf, i+1);
      
      if(close2 < open2 && close1 > open1) // Previous bearish, current bullish
      {
         if(close1 >= open2 && open1 <= close2) return true;
      }
      return false;
   }

   bool IsBearishEngulfing(int i = 1)
   {
      double open1 = iOpen(_Symbol, m_tf, i);
      double close1 = iClose(_Symbol, m_tf, i);
      double open2 = iOpen(_Symbol, m_tf, i+1);
      double close2 = iClose(_Symbol, m_tf, i+1);
      
      if(close2 > open2 && close1 < open1) // Previous bullish, current bearish
      {
         if(close1 <= open2 && open1 >= close2) return true;
      }
      return false;
   }

   bool IsPinBar(int i = 1, bool bullish = true)
   {
      double open = iOpen(_Symbol, m_tf, i);
      double close = iClose(_Symbol, m_tf, i);
      double high = iHigh(_Symbol, m_tf, i);
      double low = iLow(_Symbol, m_tf, i);
      
      double body = MathAbs(open - close);
      double range = high - low;
      if(range == 0) return false;
      
      if(bullish) {
         double lowerWick = MathMin(open, close) - low;
         if(lowerWick > body * 2.0 && (high - MathMax(open, close)) < body * 1.5) return true;
      } else {
         double upperWick = high - MathMax(open, close);
         if(upperWick > body * 2.0 && (MathMin(open, close) - low) < body * 1.5) return true;
      }
      return false;
   }

   struct Setup {
      string name;
      int type; // 0=Buy, 1=Sell
      double entry;
      double sl;
      double tp;
      int confluence_score;
   };

   double GetDailyOpen() { return iOpen(_Symbol, PERIOD_D1, 0); }

   void RenderMarketContext()
   {
      double dOpen = GetDailyOpen();
      DrawLine("DailyOpen", dOpen, clrGold, STYLE_DASH, 1);
      DrawText("DailyOpen_Label", TimeCurrent(), dOpen, " Daily Open Threshold - Longs Below / Shorts Above", clrWhite, 8);
      
      // Plot Macro Structure
      ScanFVG();
      ScanLiquidity();
      ScanCandlePatterns();
      ScanBoxConsolidations();
      ScanSMCPremiumDiscount();
   }

   void ScanSMCPremiumDiscount()
   {
      // Simplification of LuxAlgo Smart Money Concepts for MT5 Scalping
      // Finds the 50-period trailing swing high and low to map Premium/Discount
      int highestIdx = iHighest(_Symbol, m_tf, MODE_HIGH, 50, 1);
      int lowestIdx = iLowest(_Symbol, m_tf, MODE_LOW, 50, 1);
      
      if(highestIdx > 0 && lowestIdx > 0)
      {
         double sHigh = iHigh(_Symbol, m_tf, highestIdx);
         double sLow = iLow(_Symbol, m_tf, lowestIdx);
         
         double equilibrium = sLow + ((sHigh - sLow) / 2.0);
         double discountTop = sLow + ((sHigh - sLow) / 4.0); // Bottom 25%
         double premiumBot = sHigh - ((sHigh - sLow) / 4.0); // Top 25%
         
         // Draw Premium Zone (Top 25%)
         DrawRect("SMC_PREMIUM", iTime(_Symbol, m_tf, 50), sHigh, TimeCurrent() + PeriodSeconds(m_tf)*10, premiumBot, C'60,20,20');
         DrawText("SMC_PREMIUM_LBL", TimeCurrent(), sHigh, "LuxAlgo Premium (Overbought Sell Zone)", clrRed, 8);
         
         // Draw Discount Zone (Bottom 25%)
         DrawRect("SMC_DISCOUNT", iTime(_Symbol, m_tf, 50), discountTop, TimeCurrent() + PeriodSeconds(m_tf)*10, sLow, C'20,60,20');
         DrawText("SMC_DISCOUNT_LBL", TimeCurrent(), sLow, "LuxAlgo Discount (Oversold Buy Zone)", clrLime, 8);
         
         // Draw Equilibrium
         DrawLine("SMC_EQ", equilibrium, clrGray, STYLE_DASH);
      }
   }

   void ScanCandlePatterns()
   {
      for(int i=1; i<50; i++)
      {
         if(IsBullishEngulfing(i)) {
            DrawText("BULL_ENG_"+(string)i, iTime(_Symbol, m_tf, i), iLow(_Symbol, m_tf, i) - 10*_Point, "Bullish Engulfing", clrLime, 8);
         }
         if(IsBearishEngulfing(i)) {
            DrawText("BEAR_ENG_"+(string)i, iTime(_Symbol, m_tf, i), iHigh(_Symbol, m_tf, i) + 10*_Point, "Bearish Engulfing", clrRed, 8);
         }
         if(IsPinBar(i, true)) {
            DrawText("BULL_PIN_"+(string)i, iTime(_Symbol, m_tf, i), iLow(_Symbol, m_tf, i) - 20*_Point, "Hammer PinBar", clrLime, 8);
         }
         if(IsPinBar(i, false)) {
            DrawText("BEAR_PIN_"+(string)i, iTime(_Symbol, m_tf, i), iHigh(_Symbol, m_tf, i) + 20*_Point, "Shooting Star", clrRed, 8);
         }
      }
   }

   void ScanBoxConsolidations()
   {
      for(int i=1; i<30; i+=10) 
      {
         double highest = iHigh(_Symbol, m_tf, iHighest(_Symbol, m_tf, MODE_HIGH, 10, i));
         double lowest = iLow(_Symbol, m_tf, iLowest(_Symbol, m_tf, MODE_LOW, 10, i));
         double boxRange = highest - lowest;
         double atr = GetATR(14);
         
         if(boxRange > 0 && boxRange < atr * 1.5) 
         {
            DrawRect("BOX_CONSOLIDATION_"+(string)i, iTime(_Symbol, m_tf, i+10), highest, iTime(_Symbol, m_tf, i), lowest, clrDimGray, false);
            DrawText("BOX_LBL_"+(string)i, iTime(_Symbol, m_tf, i+5), highest + 10*_Point, "Consolidation Box", clrGray, 8);
         }
      }
   }

   void ScanFVG()
   {
      for(int i=1; i<50; i++)
      {
         double h1 = iHigh(_Symbol, m_tf, i+1);
         double l3 = iLow(_Symbol, m_tf, i-1);
         if(h1 < l3) DrawRect("FVG_BULL_"+(string)i, iTime(_Symbol, m_tf, i+1), h1, iTime(_Symbol, m_tf, i-1), l3, C'20,60,20');
         
         double l1 = iLow(_Symbol, m_tf, i+1);
         double h3 = iHigh(_Symbol, m_tf, i-1);
         if(l1 > h3) DrawRect("FVG_BEAR_"+(string)i, iTime(_Symbol, m_tf, i+1), l1, iTime(_Symbol, m_tf, i-1), h3, C'60,20,20');
      }
   }

   void ScanLiquidity()
   {
      double dHigh = iHigh(_Symbol, PERIOD_D1, 1);
      double dLow = iLow(_Symbol, PERIOD_D1, 1);
      DrawLine("PrevDayHigh", dHigh, clrMagenta, STYLE_DOT);
      DrawLine("PrevDayLow", dLow, clrMagenta, STYLE_DOT);
   }

   bool CheckConfluence(Setup &out_setup)
   {
      double close = iClose(_Symbol, m_tf, 0);
      double dOpen = GetDailyOpen();
      double ema50 = GetEMA(50);
      double ema200 = GetEMA(200);
      
      // MTF (Multi-Timeframe) Broad Trend alignment filtering based on STFX Top-Down Logic
      bool htf1_bullish = GetEMA50_HTF1() > GetEMA200_HTF1();
      bool htf2_bullish = GetEMA50_HTF2() > GetEMA200_HTF2();
      bool broad_bull_trend = (htf1_bullish && htf2_bullish);
      bool broad_bear_trend = (!htf1_bullish && !htf2_bullish);
      
      bool is_fvg = (iHigh(_Symbol, m_tf, 2) < iLow(_Symbol, m_tf, 0));
      bool is_oversold = (GetRSI(14) < 30);
      
      // Strategy 1: FVG + Discount + RSI Oversold (ONLY if HTF implies Deep Pullback Uptrend)
      if(broad_bull_trend && is_fvg && close < dOpen && is_oversold)
      {
         out_setup.name = "FVG + Discount + RSI Oversold (Main Trend Sync)";
         out_setup.type = 0; // Buy
         out_setup.entry = close;
         out_setup.sl = iLow(_Symbol, m_tf, 1);
         out_setup.tp = close + MathAbs(close - out_setup.sl) * 2;
         out_setup.confluence_score = 4;
         return true;
      }

      // Strategy 2: Golden Scalp (EMA 50/200 Trend + Bullish Engulfing)
      if(broad_bull_trend && ema50 > ema200 && close > ema50 && IsBullishEngulfing(1))
      {
         out_setup.name = "Golden Uptrend + Bullish Engulfing (HTF Sync)";
         out_setup.type = 0; // Buy
         out_setup.entry = close;
         out_setup.sl = iLow(_Symbol, m_tf, 1);
         out_setup.tp = close + MathAbs(close - out_setup.sl) * 2.5;
         out_setup.confluence_score = 5;
         return true;
      }

      // Strategy 3: Bearish Trend + Shooting Star / Pin Bar
      if(broad_bear_trend && ema50 < ema200 && close < ema50 && IsPinBar(1, false))
      {
         out_setup.name = "Bearish Trend HTF + Shooting Star";
         out_setup.type = 1; // Sell
         out_setup.entry = close;
         out_setup.sl = iHigh(_Symbol, m_tf, 1);
         out_setup.tp = close - MathAbs(close - out_setup.sl) * 2.5;
         out_setup.confluence_score = 5;
         return true;
      }

      // Strategy 4: Consolidating Box Breakout
      double highest = iHigh(_Symbol, m_tf, iHighest(_Symbol, m_tf, MODE_HIGH, 10, 2));
      double lowest = iLow(_Symbol, m_tf, iLowest(_Symbol, m_tf, MODE_LOW, 10, 2));
      double boxRange = highest - lowest;
      double atr = GetATR(14);
      
      if(boxRange < atr * 1.5) // Tight consolidation phase
      {
         if(close > highest && iClose(_Symbol, m_tf, 1) <= highest) // Breakout Up
         {
            out_setup.name = "Box Trading Breakout + Momentum";
            out_setup.type = 0; // Buy
            out_setup.entry = close;
            out_setup.sl = lowest;
            out_setup.tp = close + MathAbs(close - out_setup.sl) * 2;
            out_setup.confluence_score = 3;
            return true;
         }
      }

      // Strategy 5 & 6: Lux Algo SMC (CHoCH + Premium/Discount)
      int swingHighIdx = iHighest(_Symbol, m_tf, MODE_HIGH, 50, 1);
      int swingLowIdx = iLowest(_Symbol, m_tf, MODE_LOW, 50, 1);
      
      if(swingHighIdx > 0 && swingLowIdx > 0)
      {
         double sHigh = iHigh(_Symbol, PERIOD_CURRENT, swingHighIdx);
         double sLow = iLow(_Symbol, PERIOD_CURRENT, swingLowIdx);
         double discountTop = sLow + ((sHigh - sLow) / 4.0); // Bottom 25% (Buy Zone)
         double premiumBot = sHigh - ((sHigh - sLow) / 4.0); // Top 25% (Selling Zone)
         
         // Strategy 5: Bullish CHoCH in Discount Zone
         // If price is in the Discount Zone, and recently broke a short-term resistance (5-candle high)
         double localHigh = iHigh(_Symbol, m_tf, iHighest(_Symbol, m_tf, MODE_HIGH, 5, 2));
         if(close < discountTop && close > localHigh && iClose(_Symbol, m_tf, 1) <= localHigh)
         {
            out_setup.name = "LuxAlgo SMC: Bullish CHoCH in Discount Zone";
            out_setup.type = 0; // Buy
            out_setup.entry = close;
            // Use Volatility to buffer the swing low against liquidity hunts
            out_setup.sl = sLow - (atr * 0.5); 
            out_setup.tp = close + MathAbs(close - out_setup.sl) * 3; // 1:3 R/R
            out_setup.confluence_score = 5;
            return true;
         }
         
         // Strategy 6: Bearish CHoCH in Premium Zone
         // If price is in the Premium Zone, and recently broke a short-term support (5-candle low)
         double localLow = iLow(_Symbol, m_tf, iLowest(_Symbol, m_tf, MODE_LOW, 5, 2));
         if(close > premiumBot && close < localLow && iClose(_Symbol, m_tf, 1) >= localLow)
         {
            out_setup.name = "LuxAlgo SMC: Bearish CHoCH in Premium Zone";
            out_setup.type = 1; // Sell
            out_setup.entry = close;
            // Use Volatility to buffer the swing high against liquidity hunts
            out_setup.sl = sHigh + (atr * 0.5);
            out_setup.tp = close - MathAbs(close - out_setup.sl) * 3; // 1:3 R/R
            out_setup.confluence_score = 5;
            return true;
         }
      }

      // Strategy 7 & 8: High-Frequency M1 SMC Liquidity Sweeps (For $500-$1K/Day Scale)
      if(m_tf == PERIOD_M1)
      {
         // Find local 15-minute liquidity pools (local highs/lows)
         double localSweepHigh = iHigh(_Symbol, m_tf, iHighest(_Symbol, m_tf, MODE_HIGH, 15, 2));
         double localSweepLow = iLow(_Symbol, m_tf, iLowest(_Symbol, m_tf, MODE_LOW, 15, 2));
         
         // Strategy 7: Bullish Sell-side Liquidity Sweep
         if (iLow(_Symbol, m_tf, 1) < localSweepLow && close > localSweepLow) {
            if (IsBullishEngulfing(1) || IsPinBar(1, true)) {
               out_setup.name = "M1 SMC: Sell-side Liquidity Sweep + Reclaim";
               out_setup.type = 0; // Buy
               out_setup.entry = close;
               out_setup.sl = iLow(_Symbol, m_tf, 1) - (atr * 0.2); // Tight volatility buffer
               out_setup.tp = close + MathAbs(close - out_setup.sl) * 3.0; // 1:3 R/R 
               out_setup.confluence_score = 5;
               return true;
            }
         }

         // Strategy 8: Bearish Buy-side Liquidity Sweep
         if (iHigh(_Symbol, m_tf, 1) > localSweepHigh && close < localSweepHigh) {
            if (IsBearishEngulfing(1) || IsPinBar(1, false)) {
               out_setup.name = "M1 SMC: Buy-side Liquidity Sweep + Reclaim";
               out_setup.type = 1; // Sell
               out_setup.entry = close;
               out_setup.sl = iHigh(_Symbol, m_tf, 1) + (atr * 0.2); // Tight volatility buffer
               out_setup.tp = close - MathAbs(close - out_setup.sl) * 3.0; // 1:3 R/R 
               out_setup.confluence_score = 5;
               return true;
            }
         }
      }

      // -------------------------------------------------------------
      // EXTREME HIGH WIN-RATE GLOBAL CONFLUENCE (All Timeframes Sync)
      // -------------------------------------------------------------
      bool is_global_bull = GlobalTrendIsBullish();
      bool is_global_bear = GlobalTrendIsBearish();

      // Strategy 9: Perfect Order Pullback (Global Alignment M15 -> D1)
      if(is_global_bull && close < ema50 && is_oversold && (IsBullishEngulfing(1) || IsPinBar(1, true)))
      {
         out_setup.name = "Ultimate Global Bullish Confluence + Oversold Bounce";
         out_setup.type = 0; // Buy
         out_setup.entry = close;
         out_setup.sl = iLow(_Symbol, m_tf, 1) - atr * 0.5; 
         out_setup.tp = close + MathAbs(close - out_setup.sl) * 2.0; 
         out_setup.confluence_score = 10;
         return true;
      }
      
      // Strategy 10: Perfect Order Bearish Continuation (Global Alignment M15 -> D1)
      if(is_global_bear && close > ema50 && GetRSI(14) > 70 && (IsBearishEngulfing(1) || IsPinBar(1, false)))
      {
         out_setup.name = "Ultimate Global Bearish Confluence + Overbought Rejection";
         out_setup.type = 1; // Sell
         out_setup.entry = close;
         out_setup.sl = iHigh(_Symbol, m_tf, 1) + atr * 0.5;
         out_setup.tp = close - MathAbs(close - out_setup.sl) * 2.0; 
         out_setup.confluence_score = 10;
         return true;
      }

      // -------------------------------------------------------------
      // GOLD SPECIFIC F&R NECKLINE BREAK/RETEST STRATEGY (1:3 RRR)
      // -------------------------------------------------------------
      if(_Symbol == "XAUUSD" || _Symbol == "GOLD")
      {
         // F&R zones rely heavily on identifying recent consolidation boxes 
         // and confirming entry via a 'Neckline' body break on lower timeframes like M15.
         
         double localHigh_M15 = iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, 8, 2));
         double localLow_M15 = iLow(_Symbol, PERIOD_M15, iLowest(_Symbol, PERIOD_M15, MODE_LOW, 8, 2));
         
         // Strategy 11: Gold Neckline Bullish Breakout (Box Strategy)
         // Context: H4/H1 Uptrend. M15 breaks above the local neckline consolidation with a full body candle.
         if (is_global_bull && close > localHigh_M15 && iClose(_Symbol, PERIOD_M15, 1) > localHigh_M15 && iOpen(_Symbol, PERIOD_M15, 1) <= localHigh_M15)
         {
             out_setup.name = "Gold F&R Box: Bullish Neckline Breakout";
             out_setup.type = 0; // Buy
             out_setup.entry = close;
             out_setup.sl = localLow_M15 - (atr * 0.3); // Stop loss below the neckline/box
             out_setup.tp = close + MathAbs(close - out_setup.sl) * 3.0; // Enforce Strict 1:3 RRR for prop firms
             out_setup.confluence_score = 8;
             return true;
         }
         
         // Strategy 12: Gold Neckline Bearish Breakout (Box Strategy)
         // Context: H4/H1 Downtrend. M15 breaks below the local neckline box with a full body candle.
         if (is_global_bear && close < localLow_M15 && iClose(_Symbol, PERIOD_M15, 1) < localLow_M15 && iOpen(_Symbol, PERIOD_M15, 1) >= localLow_M15)
         {
             out_setup.name = "Gold F&R Box: Bearish Neckline Breakout";
             out_setup.type = 1; // Sell
             out_setup.entry = close;
             out_setup.sl = localHigh_M15 + (atr * 0.3); // Stop loss above the neckline/box
             out_setup.tp = close - MathAbs(close - out_setup.sl) * 3.0; // Enforce Strict 1:3 RRR for prop firms
             out_setup.confluence_score = 8;
             return true;
         }

         // -------------------------------------------------------------
         // GOLD HIGH WIN-RATE M1/M5 FVG (Fair Value Gap) SCALPING
         // -------------------------------------------------------------
         if (m_tf == PERIOD_M1 || m_tf == PERIOD_M5)
         {
            double atr_m1 = iATR(_Symbol, m_tf, 14);
            
            // Strategy 13: Bullish Micro FVG Fill & Go
            // Detect a 3-candle gap: Low of Candle 1 > High of Candle 3.
            // Price retraces into this gap (between High 3 and Low 1) and structurally rejects to continue UP.
            if (is_global_bull) 
            {
               double low_1 = iLow(_Symbol, m_tf, 1);
               double high_3 = iHigh(_Symbol, m_tf, 3);
               
               if(low_1 > high_3) // FVG exists
               {
                  if(close <= low_1 && close >= high_3 && (IsBullishEngulfing(0) || IsPinBar(0, true))) // Filled and rejecting currently
                  {
                     out_setup.name = "Gold M1/M5: Bullish FVG Micro Scalp";
                     out_setup.type = 0; // Buy
                     out_setup.entry = close;
                     out_setup.sl = high_3 - (atr_m1 * 0.2); // SL tightly below the FVG structural imbalance
                     out_setup.tp = close + MathAbs(close - out_setup.sl) * 2.5; // 1:2.5 Rapid reward 
                     out_setup.confluence_score = 7;
                     return true; 
                  }
               }
            }

            // Strategy 14: Bearish Micro FVG Fill & Go
            // Detect a 3-candle gap: High of Candle 1 < Low of Candle 3
            if (is_global_bear) 
            {
               double high_1 = iHigh(_Symbol, m_tf, 1);
               double low_3 = iLow(_Symbol, m_tf, 3);
               
               if(high_1 < low_3) // FVG exists
               {
                  if(close >= high_1 && close <= low_3 && (IsBearishEngulfing(0) || IsPinBar(0, false)))
                  {
                     out_setup.name = "Gold M1/M5: Bearish FVG Micro Scalp";
                     out_setup.type = 1; // Sell
                     out_setup.entry = close;
                     out_setup.sl = low_3 + (atr_m1 * 0.2); // SL tightly above FVG structure
                     out_setup.tp = close - MathAbs(close - out_setup.sl) * 2.5; 
                     out_setup.confluence_score = 7;
                     return true;
                  }
               }
            }
         }

         // -------------------------------------------------------------
         // GOLD M5/M15/M30 EXPLOSIVE MOMENTUM SCALP (EMA Pullback)
         // -------------------------------------------------------------
         if (m_tf == PERIOD_M5 || m_tf == PERIOD_M15 || m_tf == PERIOD_M30)
         {
             // Momentum Check: is ATR expanding rapidly today?
             double atr_current = iATR(_Symbol, m_tf, 14);
             double atr_prev = GetVal(iATR(_Symbol, m_tf, 14)); // Simple hack wrapper to approximate recent volatility
             
             // Strategy 15: Bullish Explosive Momentum Scalp
             if(ema10 > ema200 && is_global_bull)
             {
                 // Pullback to fast EMA 10 followed by instant rejection
                 if(iLow(_Symbol, m_tf, 1) <= ema10 && close > ema10 && IsBullishEngulfing(1))
                 {
                     out_setup.name = "Gold Momentum: Exploding Pullback Scalp (LONG)";
                     out_setup.type = 0; // Buy
                     out_setup.entry = close;
                     out_setup.sl = iLow(_Symbol, m_tf, 1) - (atr_current * 0.5);
                     out_setup.tp = close + MathAbs(close - out_setup.sl) * 1.5; // Fast 1:1.5 scalp target
                     out_setup.confluence_score = 6;
                     return true;
                 }
             }

             // Strategy 16: Bearish Explosive Momentum Scalp
             if(ema10 < ema200 && is_global_bear)
             {
                 if(iHigh(_Symbol, m_tf, 1) >= ema10 && close < ema10 && IsBearishEngulfing(1))
                 {
                     out_setup.name = "Gold Momentum: Exploding Pullback Scalp (SHORT)";
                     out_setup.type = 1; // Sell
                     out_setup.entry = close;
                     out_setup.sl = iHigh(_Symbol, m_tf, 1) + (atr_current * 0.5);
                     out_setup.tp = close - MathAbs(close - out_setup.sl) * 1.5; 
                     out_setup.confluence_score = 6;
                     return true;
                 }
             }
         }
      }

      return false;
   }
};

//+------------------------------------------------------------------+
//| Heads-Up Display (HUD) Class                                     |
//+------------------------------------------------------------------+
class CHUD : public CVisualizer
{
public:
   void Render(double dailyDD, double absDD, string phase, string AI_Msg)
   {
      string p = "OV_HUD_";
      ObjectCreate(0, p+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, p+"BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, p+"BG", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, p+"BG", OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, p+"BG", OBJPROP_XSIZE, 400); // Expanded width for long strings
      ObjectSetInteger(0, p+"BG", OBJPROP_YSIZE, 135);
      ObjectSetInteger(0, p+"BG", OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, p+"BG", OBJPROP_BORDER_COLOR, clrDarkCyan);
      ObjectSetInteger(0, p+"BG", OBJPROP_WIDTH, 1);

      UpdateField(p+"Title", "PROJECT OMNIVISION PRO", 15, 15, clrCyan, 10, true);
      UpdateField(p+"Phase", "Phase: " + phase, 15, 40, clrWhite, 8);
      UpdateField(p+"DD", "Daily DD: " + DoubleToString(dailyDD, 2) + "%", 15, 55, dailyDD > 4 ? clrRed : clrLime, 8);
      UpdateField(p+"AbsDD", "Total Abs DD: " + DoubleToString(absDD, 2) + "%", 15, 70, absDD > 8 ? clrRed : clrYellow, 8);
      UpdateField(p+"Msg", "AI Tutor: " + AI_Msg, 15, 95, clrGold, 8);
   }

   void UpdateField(string name, string txt, int x, int y, color clr, int size, bool bold=false)
   {
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10 + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 10 + y);
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   }
};
