//+------------------------------------------------------------------+
//|                                     OmniVision_Visual_Mentor.mqh |
//|                              Copyright 2026, OmniVision Ltd. V3  |
//|                                             https://omnivision.io|
//+------------------------------------------------------------------+
//  CHANGELOG V3:
//  + CMacroEngine — real-time DXY / US10Y / VIX correlation engine
//    Each index resolves to an integer bias (+1 / 0 / -1) and sums
//    into a macroBias integer [-3 … +3] that gates Gold entries.
//  + CHUD updated — live Macro Bias Meter with colour-coded bars.
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmniVision"
#property link      "https://omnivision.io"
#property strict

#include <Trade\Trade.mqh>

#define OBJ_PREFIX "OmniViz_"

//+------------------------------------------------------------------+
//| BASE VISUALIZER                                                  |
//+------------------------------------------------------------------+
class CVisualizer
{
protected:
   string m_prefix;
public:
   CVisualizer() { m_prefix = OBJ_PREFIX; }
   ~CVisualizer() {}
   void CleanChart() { ObjectsDeleteAll(0, m_prefix); }

   void DrawRect(string name, datetime t1, double p1, datetime t2, double p2,
                 color clr, bool fill=true)
   {
      string n = m_prefix + name;
      ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_FILL, fill);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   }

   void DrawLine(string name, double price, color clr,
                 ENUM_LINE_STYLE style=STYLE_SOLID, int width=1)
   {
      string n = m_prefix + name;
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_STYLE, style);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   }

   void DrawText(string name, datetime t, double p, string txt, color clr, int size=10)
   {
      string n = m_prefix + name;
      ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, n, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   }
};

//+------------------------------------------------------------------+
//| MACRO CORRELATION ENGINE  (NEW — V3)                             |
//|                                                                  |
//| Evaluates three macro assets on the current Daily bar:           |
//|   DXY  (US Dollar Index)  — strong DXY = -1 bias for Gold       |
//|   US10Y (Treasury Yield)  — rising yield = -1 bias for Gold     |
//|   VIX  (Fear Index)       — spiking VIX = +1 bias for Gold     |
//|                                                                  |
//| macroBias = dxy_bias + us10y_bias + vix_bias  ∈ [-3 … +3]      |
//|   >= 0  → allow Gold Longs                                       |
//|   <= -2 → HARD BLOCK all Gold Longs (trap-filter)               |
//+------------------------------------------------------------------+
class CMacroEngine
{
private:
   string   m_dxy_sym;
   string   m_us10y_sym;
   string   m_vix_sym;
   bool     m_dxy_ok;
   bool     m_us10y_ok;
   bool     m_vix_ok;

   // Returns the daily close-vs-open bias for any symbol.
   // multiplier: +1 → "up is bullish", -1 → "up is bearish" for Gold.
   int DailyBias(string symbol, int multiplier)
   {
      if(!SymbolSelect(symbol, true)) return 0;
      double d_open  = iOpen(symbol, PERIOD_D1, 0);
      double d_close = iClose(symbol, PERIOD_D1, 0);
      if(d_open == 0.0) return 0;
      return (d_close > d_open) ? multiplier : -multiplier;
   }

   // EURUSD-based DXY proxy (inverse): EURUSD down ≈ DXY up ≈ bearish Gold.
   int EURUSDProxyBias()
   {
      double d_open  = iOpen("EURUSD", PERIOD_D1, 0);
      double d_close = iClose("EURUSD", PERIOD_D1, 0);
      if(d_open == 0.0) return 0;
      // EURUSD up → weak dollar → bullish Gold (+1)
      return (d_close > d_open) ? 1 : -1;
   }

public:
   // ── Public state ──────────────────────────────────────────────
   int  dxy_bias;      // -1 strong USD bearish, +1 weak USD bullish
   int  us10y_bias;    // -1 rising yield bearish, +1 falling bullish
   int  vix_bias;      // +1 fear/spike bullish, -1 calm/risk-on bearish
   int  macroBias;     // algebraic sum [-3 … +3]
   bool dxy_native;    // true = native symbol used; false = EURUSD proxy
   bool us10y_native;
   bool vix_native;

   CMacroEngine(string dxy  = "USDX",
                string us10y = "US10Y",
                string vix   = "VIX")
   {
      m_dxy_sym   = dxy;
      m_us10y_sym = us10y;
      m_vix_sym   = vix;
      m_dxy_ok = m_us10y_ok = m_vix_ok = false;
      dxy_bias = us10y_bias = vix_bias = macroBias = 0;
      dxy_native = us10y_native = vix_native = false;
   }

   // Call once in OnInit — probes symbol availability
   void Init()
   {
      m_dxy_ok   = SymbolSelect(m_dxy_sym,   true);
      m_us10y_ok = SymbolSelect(m_us10y_sym, true);
      m_vix_ok   = SymbolSelect(m_vix_sym,   true);
      dxy_native   = m_dxy_ok;
      us10y_native = m_us10y_ok;
      vix_native   = m_vix_ok;
      Print("CMacroEngine Init | DXY: ",   m_dxy_ok   ? "Native":"EURUSD Proxy",
            " | US10Y: ", m_us10y_ok ? "Native":"N/A",
            " | VIX: ",   m_vix_ok   ? "Native":"N/A");
   }

   // Call every OnTick — refreshes all three biases
   void Calculate()
   {
      // ── DXY: strong dollar = bad for Gold (-1) ──────────────────
      if(m_dxy_ok)
         dxy_bias = DailyBias(m_dxy_sym, -1);   // DXY up → -1
      else
         dxy_bias = EURUSDProxyBias();            // EURUSD up → +1

      // ── US10Y: rising yields = bad for Gold (-1) ─────────────────
      if(m_us10y_ok)
         us10y_bias = DailyBias(m_us10y_sym, -1); // yield up → -1
      else
         us10y_bias = 0;                           // neutral when unavailable

      // ── VIX: spiking fear = bullish safe-haven Gold (+1) ─────────
      if(m_vix_ok)
         vix_bias = DailyBias(m_vix_sym, +1);     // VIX up → +1
      else
         vix_bias = 0;

      macroBias = dxy_bias + us10y_bias + vix_bias;
   }

   // Gate check: allow Gold Long only if macro is neutral or bullish
   bool AllowGoldLong()  const { return (macroBias >= 0); }

   // Hard block: DXY + Yields both strongly against Gold
   bool BlockAllLongs()  const { return (macroBias <= -2); }

   // Human-readable label for the HUD
   string BiasLabel() const
   {
      if(macroBias >=  3) return "MACRO: EXTREME BULL (+3)";
      if(macroBias ==  2) return "MACRO: STRONG BULL  (+2)";
      if(macroBias ==  1) return "MACRO: MILD BULL    (+1)";
      if(macroBias ==  0) return "MACRO: NEUTRAL       (0)";
      if(macroBias == -1) return "MACRO: MILD BEAR    (-1)";
      if(macroBias == -2) return "MACRO: STRONG BEAR  (-2) *** LONGS BLOCKED ***";
      return                     "MACRO: EXTREME BEAR (-3) *** LONGS BLOCKED ***";
   }

   // Per-component strings for the expanded HUD panel
   string DXYLabel() const
   {
      string src = m_dxy_ok ? m_dxy_sym : "EURUSD proxy";
      if(dxy_bias == -1) return "DXY ["+ src +"]: STRONG  → Au Bearish (-1)";
      if(dxy_bias ==  1) return "DXY ["+ src +"]: WEAK    → Au Bullish (+1)";
      return                    "DXY ["+ src +"]: N/A     → Neutral    ( 0)";
   }

   string YieldLabel() const
   {
      if(!m_us10y_ok)    return "US10Y: Unavailable → Neutral (0)";
      if(us10y_bias ==-1) return "US10Y: RISING      → Au Bearish (-1)";
      return                     "US10Y: FALLING     → Au Bullish (+1)";
   }

   string VIXLabel() const
   {
      if(!m_vix_ok)     return "VIX: Unavailable → Neutral (0)";
      if(vix_bias == 1) return "VIX: SPIKING     → Au Haven  (+1)";
      return                   "VIX: CALM        → Risk-On  (-1)";
   }

   // JSON fragment for dashboard API payload
   string ToJSON() const
   {
      return StringFormat(
         "\"macro\":{\"macroBias\":%d,\"dxyBias\":%d,\"us10yBias\":%d,"
         "\"vixBias\":%d,\"dxyNative\":%s,\"us10yNative\":%s,\"vixNative\":%s,"
         "\"longsBlocked\":%s}",
         macroBias, dxy_bias, us10y_bias, vix_bias,
         dxy_native   ? "true" : "false",
         us10y_native ? "true" : "false",
         vix_native   ? "true" : "false",
         BlockAllLongs() ? "true" : "false"
      );
   }
};


//+------------------------------------------------------------------+
//| STRATEGY MANAGER  (unchanged core, V3 macro-aware wrapper added) |
//+------------------------------------------------------------------+
class CStrategyManager : public CVisualizer
{
private:
   ENUM_TIMEFRAMES m_tf;
   int h_ema10, h_ema50, h_ema200;
   int h_ema50_htf1, h_ema200_htf1;
   int h_ema50_htf2, h_ema200_htf2;
   int h_ema50_m15, h_ema200_m15;
   int h_ema50_h1,  h_ema200_h1;
   int h_ema50_h4,  h_ema200_h4;
   int h_ema50_d1,  h_ema200_d1;
   int h_rsi, h_atr;

   ENUM_TIMEFRAMES GetHTF1()
   {
      if(m_tf == PERIOD_M1)  return PERIOD_M5;
      if(m_tf == PERIOD_M5)  return PERIOD_M15;
      if(m_tf <= PERIOD_M15) return PERIOD_H1;
      if(m_tf <= PERIOD_H1)  return PERIOD_H4;
      return PERIOD_D1;
   }

   ENUM_TIMEFRAMES GetHTF2()
   {
      if(m_tf == PERIOD_M1)  return PERIOD_M15;
      if(m_tf == PERIOD_M5)  return PERIOD_H1;
      if(m_tf <= PERIOD_M15) return PERIOD_H4;
      if(m_tf <= PERIOD_H1)  return PERIOD_D1;
      return PERIOD_W1;
   }

   void InitIndicators()
   {
      if(h_ema10    == INVALID_HANDLE) h_ema10    = iMA(_Symbol, m_tf, 10,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50    == INVALID_HANDLE) h_ema50    = iMA(_Symbol, m_tf, 50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200   == INVALID_HANDLE) h_ema200   = iMA(_Symbol, m_tf, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_rsi      == INVALID_HANDLE) h_rsi      = iRSI(_Symbol, m_tf, 14, PRICE_CLOSE);
      if(h_atr      == INVALID_HANDLE) h_atr      = iATR(_Symbol, m_tf, 14);
      if(h_ema50_htf1  == INVALID_HANDLE) h_ema50_htf1  = iMA(_Symbol, GetHTF1(), 50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_htf1 == INVALID_HANDLE) h_ema200_htf1 = iMA(_Symbol, GetHTF1(), 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_htf2  == INVALID_HANDLE) h_ema50_htf2  = iMA(_Symbol, GetHTF2(), 50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_htf2 == INVALID_HANDLE) h_ema200_htf2 = iMA(_Symbol, GetHTF2(), 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_m15  == INVALID_HANDLE) h_ema50_m15  = iMA(_Symbol, PERIOD_M15, 50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_m15 == INVALID_HANDLE) h_ema200_m15 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_h1   == INVALID_HANDLE) h_ema50_h1   = iMA(_Symbol, PERIOD_H1,  50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_h1  == INVALID_HANDLE) h_ema200_h1  = iMA(_Symbol, PERIOD_H1,  200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_h4   == INVALID_HANDLE) h_ema50_h4   = iMA(_Symbol, PERIOD_H4,  50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_h4  == INVALID_HANDLE) h_ema200_h4  = iMA(_Symbol, PERIOD_H4,  200, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema50_d1   == INVALID_HANDLE) h_ema50_d1   = iMA(_Symbol, PERIOD_D1,  50,  0, MODE_EMA, PRICE_CLOSE);
      if(h_ema200_d1  == INVALID_HANDLE) h_ema200_d1  = iMA(_Symbol, PERIOD_D1,  200, 0, MODE_EMA, PRICE_CLOSE);
   }

   double GetVal(int handle)
   {
      if(handle == INVALID_HANDLE) return 0.0;
      double val[1];
      if(CopyBuffer(handle, 0, 0, 1, val) > 0) return val[0];
      return 0.0;
   }

public:
   CStrategyManager(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      m_tf = (tf == PERIOD_CURRENT) ? _Period : tf;
      h_ema10 = h_ema50 = h_ema200 = INVALID_HANDLE;
      h_ema50_htf1 = h_ema200_htf1 = INVALID_HANDLE;
      h_ema50_htf2 = h_ema200_htf2 = INVALID_HANDLE;
      h_ema50_m15 = h_ema200_m15   = INVALID_HANDLE;
      h_ema50_h1  = h_ema200_h1    = INVALID_HANDLE;
      h_ema50_h4  = h_ema200_h4    = INVALID_HANDLE;
      h_ema50_d1  = h_ema200_d1    = INVALID_HANDLE;
      h_rsi = h_atr = INVALID_HANDLE;
   }

   bool GlobalTrendIsBullish()
   {
      InitIndicators();
      return (GetVal(h_ema50_m15) > GetVal(h_ema200_m15) &&
              GetVal(h_ema50_h1)  > GetVal(h_ema200_h1)  &&
              GetVal(h_ema50_h4)  > GetVal(h_ema200_h4)  &&
              GetVal(h_ema50_d1)  > GetVal(h_ema200_d1));
   }

   bool GlobalTrendIsBearish()
   {
      InitIndicators();
      return (GetVal(h_ema50_m15) < GetVal(h_ema200_m15) &&
              GetVal(h_ema50_h1)  < GetVal(h_ema200_h1)  &&
              GetVal(h_ema50_h4)  < GetVal(h_ema200_h4)  &&
              GetVal(h_ema50_d1)  < GetVal(h_ema200_d1));
   }

   double GetEMA(int period)
   {
      InitIndicators();
      if(period == 10)  return GetVal(h_ema10);
      if(period == 50)  return GetVal(h_ema50);
      if(period == 200) return GetVal(h_ema200);
      return 0.0;
   }

   double GetEMA50_HTF1()  { InitIndicators(); return GetVal(h_ema50_htf1);  }
   double GetEMA200_HTF1() { InitIndicators(); return GetVal(h_ema200_htf1); }
   double GetEMA50_HTF2()  { InitIndicators(); return GetVal(h_ema50_htf2);  }
   double GetEMA200_HTF2() { InitIndicators(); return GetVal(h_ema200_htf2); }
   double GetRSI(int p=14) { InitIndicators(); return GetVal(h_rsi); }
   double GetATR(int p=14) { InitIndicators(); return GetVal(h_atr); }

   bool IsBullishEngulfing(int i=1)
   {
      double o1=iOpen(_Symbol,m_tf,i),   c1=iClose(_Symbol,m_tf,i);
      double o2=iOpen(_Symbol,m_tf,i+1), c2=iClose(_Symbol,m_tf,i+1);
      if(c2 < o2 && c1 > o1)
         if(c1 >= o2 && o1 <= c2) return true;
      return false;
   }

   bool IsBearishEngulfing(int i=1)
   {
      double o1=iOpen(_Symbol,m_tf,i),   c1=iClose(_Symbol,m_tf,i);
      double o2=iOpen(_Symbol,m_tf,i+1), c2=iClose(_Symbol,m_tf,i+1);
      if(c2 > o2 && c1 < o1)
         if(c1 <= o2 && o1 >= c2) return true;
      return false;
   }

   bool IsPinBar(int i=1, bool bullish=true)
   {
      double o=iOpen(_Symbol,m_tf,i), c=iClose(_Symbol,m_tf,i);
      double h=iHigh(_Symbol,m_tf,i), l=iLow(_Symbol,m_tf,i);
      double body=MathAbs(o-c), range=h-l;
      if(range==0) return false;
      if(bullish)  { double lw=MathMin(o,c)-l;  return (lw > body*2.0 && (h-MathMax(o,c)) < body*1.5); }
      else         { double uw=h-MathMax(o,c);   return (uw > body*2.0 && (MathMin(o,c)-l) < body*1.5); }
   }

   struct Setup {
      string name;
      int    type;            // 0=Buy, 1=Sell
      double entry, sl, tp;
      int    confluence_score;
      bool   macro_confirmed; // NEW V3: flagged true when macroBias >= 1
   };

   double GetDailyOpen() { return iOpen(_Symbol, PERIOD_D1, 0); }

   void RenderMarketContext()
   {
      double dOpen = GetDailyOpen();
      DrawLine("DailyOpen", dOpen, clrGold, STYLE_DASH, 1);
      DrawText("DailyOpen_Label", TimeCurrent(), dOpen,
               " Daily Open Threshold — Longs Below / Shorts Above", clrWhite, 8);
      ScanFVG();
      ScanLiquidity();
      ScanCandlePatterns();
      ScanBoxConsolidations();
      ScanSMCPremiumDiscount();
   }

   void ScanSMCPremiumDiscount()
   {
      int hiIdx = iHighest(_Symbol, m_tf, MODE_HIGH, 50, 1);
      int loIdx = iLowest(_Symbol,  m_tf, MODE_LOW,  50, 1);
      if(hiIdx<=0 || loIdx<=0) return;
      double sH = iHigh(_Symbol,m_tf,hiIdx), sL=iLow(_Symbol,m_tf,loIdx);
      double eq=sL+((sH-sL)/2.0), disc=sL+((sH-sL)/4.0), prem=sH-((sH-sL)/4.0);
      DrawRect("SMC_PREMIUM", iTime(_Symbol,m_tf,50), sH, TimeCurrent()+PeriodSeconds(m_tf)*10, prem, C'60,20,20');
      DrawText("SMC_PREMIUM_LBL", TimeCurrent(), sH, "LuxAlgo Premium (Overbought Sell Zone)", clrRed, 8);
      DrawRect("SMC_DISCOUNT", iTime(_Symbol,m_tf,50), disc, TimeCurrent()+PeriodSeconds(m_tf)*10, sL, C'20,60,20');
      DrawText("SMC_DISCOUNT_LBL", TimeCurrent(), sL, "LuxAlgo Discount (Oversold Buy Zone)", clrLime, 8);
      DrawLine("SMC_EQ", eq, clrGray, STYLE_DASH);
   }

   void ScanCandlePatterns()
   {
      for(int i=1; i<50; i++)
      {
         if(IsBullishEngulfing(i)) DrawText("BULL_ENG_"+(string)i, iTime(_Symbol,m_tf,i), iLow(_Symbol,m_tf,i)-10*_Point, "Bullish Engulfing", clrLime, 8);
         if(IsBearishEngulfing(i)) DrawText("BEAR_ENG_"+(string)i, iTime(_Symbol,m_tf,i), iHigh(_Symbol,m_tf,i)+10*_Point, "Bearish Engulfing", clrRed, 8);
         if(IsPinBar(i,true))      DrawText("BULL_PIN_"+(string)i, iTime(_Symbol,m_tf,i), iLow(_Symbol,m_tf,i)-20*_Point, "Hammer PinBar", clrLime, 8);
         if(IsPinBar(i,false))     DrawText("BEAR_PIN_"+(string)i, iTime(_Symbol,m_tf,i), iHigh(_Symbol,m_tf,i)+20*_Point, "Shooting Star", clrRed, 8);
      }
   }

   void ScanBoxConsolidations()
   {
      for(int i=1; i<30; i+=10)
      {
         double highest=iHigh(_Symbol,m_tf,iHighest(_Symbol,m_tf,MODE_HIGH,10,i));
         double lowest =iLow(_Symbol, m_tf,iLowest(_Symbol, m_tf,MODE_LOW, 10,i));
         double boxRange=highest-lowest, atr=GetATR(14);
         if(boxRange>0 && boxRange<atr*1.5)
         {
            DrawRect("BOX_CONSOLIDATION_"+(string)i, iTime(_Symbol,m_tf,i+10), highest, iTime(_Symbol,m_tf,i), lowest, clrDimGray, false);
            DrawText("BOX_LBL_"+(string)i, iTime(_Symbol,m_tf,i+5), highest+10*_Point, "Consolidation Box", clrGray, 8);
         }
      }
   }

   void ScanFVG()
   {
      for(int i=1; i<50; i++)
      {
         double h1=iHigh(_Symbol,m_tf,i+1), l3=iLow(_Symbol,m_tf,i-1);
         if(h1<l3) DrawRect("FVG_BULL_"+(string)i, iTime(_Symbol,m_tf,i+1), h1, iTime(_Symbol,m_tf,i-1), l3, C'20,60,20');
         double l1=iLow(_Symbol,m_tf,i+1), h3=iHigh(_Symbol,m_tf,i-1);
         if(l1>h3) DrawRect("FVG_BEAR_"+(string)i, iTime(_Symbol,m_tf,i+1), l1, iTime(_Symbol,m_tf,i-1), h3, C'60,20,20');
      }
   }

   void ScanLiquidity()
   {
      DrawLine("PrevDayHigh", iHigh(_Symbol,PERIOD_D1,1), clrMagenta, STYLE_DOT);
      DrawLine("PrevDayLow",  iLow(_Symbol, PERIOD_D1,1), clrMagenta, STYLE_DOT);
   }

   //+----------------------------------------------------------------+
   //| CheckConfluence — V3: now accepts CMacroEngine reference       |
   //| All Gold LONG strategies are gated through macro.AllowGoldLong |
   //| "(Macro Sync)" appended to name when macroBias >= +1           |
   //+----------------------------------------------------------------+
   bool CheckConfluence(Setup &out, const CMacroEngine &macro)
   {
      double close  = iClose(_Symbol, m_tf, 0);
      double dOpen  = GetDailyOpen();
      double ema50  = GetEMA(50);
      double ema200 = GetEMA(200);
      double ema10  = GetEMA(10);
      double atr    = GetATR(14);

      bool htf1_bull = GetEMA50_HTF1() > GetEMA200_HTF1();
      bool htf2_bull = GetEMA50_HTF2() > GetEMA200_HTF2();
      bool broad_bull = (htf1_bull && htf2_bull);
      bool broad_bear = (!htf1_bull && !htf2_bull);
      bool is_global_bull = GlobalTrendIsBullish();
      bool is_global_bear = GlobalTrendIsBearish();

      bool is_fvg     = (iHigh(_Symbol,m_tf,2) < iLow(_Symbol,m_tf,0));
      bool is_oversold = (GetRSI(14) < 30);

      // ── Helper lambda emulator: tag name with macro state ────────
      #define MACRO_TAG(n) (macro.macroBias >= 1 ? (n) + " (Macro Sync)" : (n))
      #define MACRO_CONFIRM (macro.macroBias >= 1)

      // ──────────────────────────────────────────────────────────────
      // STRATEGY 1: FVG + Discount + RSI Oversold
      // ──────────────────────────────────────────────────────────────
      if(broad_bull && is_fvg && close < dOpen && is_oversold)
      {
         if(!macro.AllowGoldLong() && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
         { Print("[MacroFilter] S1 Long BLOCKED. macroBias=", macro.macroBias); return false; }
         out.name             = MACRO_TAG("FVG + Discount + RSI Oversold (Main Trend Sync)");
         out.type             = 0; out.entry = close;
         out.sl               = iLow(_Symbol,m_tf,1);
         out.tp               = close + MathAbs(close-out.sl)*2;
         out.confluence_score = 4; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGY 2: Golden Scalp (EMA 50/200 + Bullish Engulfing)
      // ──────────────────────────────────────────────────────────────
      if(broad_bull && ema50>ema200 && close>ema50 && IsBullishEngulfing(1))
      {
         if(!macro.AllowGoldLong() && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
         { Print("[MacroFilter] S2 Long BLOCKED. macroBias=", macro.macroBias); return false; }
         out.name             = MACRO_TAG("Golden Uptrend + Bullish Engulfing (HTF Sync)");
         out.type             = 0; out.entry = close;
         out.sl               = iLow(_Symbol,m_tf,1);
         out.tp               = close + MathAbs(close-out.sl)*2.5;
         out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGY 3: Bearish Trend + Shooting Star (no macro block)
      // ──────────────────────────────────────────────────────────────
      if(broad_bear && ema50<ema200 && close<ema50 && IsPinBar(1,false))
      {
         out.name             = MACRO_TAG("Bearish Trend HTF + Shooting Star");
         out.type             = 1; out.entry = close;
         out.sl               = iHigh(_Symbol,m_tf,1);
         out.tp               = close - MathAbs(close-out.sl)*2.5;
         out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGY 4: Box Breakout
      // ──────────────────────────────────────────────────────────────
      double highest=iHigh(_Symbol,m_tf,iHighest(_Symbol,m_tf,MODE_HIGH,10,2));
      double lowest =iLow(_Symbol, m_tf,iLowest(_Symbol, m_tf,MODE_LOW, 10,2));
      double boxRange=highest-lowest;
      if(boxRange < atr*1.5 && close>highest && iClose(_Symbol,m_tf,1)<=highest)
      {
         if(!macro.AllowGoldLong() && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
         { Print("[MacroFilter] S4 Box Long BLOCKED. macroBias=", macro.macroBias); return false; }
         out.name             = MACRO_TAG("Box Trading Breakout + Momentum");
         out.type             = 0; out.entry = close;
         out.sl               = lowest; out.tp = close+MathAbs(close-out.sl)*2;
         out.confluence_score = 3; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGIES 5 & 6: LuxAlgo SMC CHoCH
      // ──────────────────────────────────────────────────────────────
      int swHiIdx = iHighest(_Symbol,m_tf,MODE_HIGH,50,1);
      int swLoIdx = iLowest(_Symbol, m_tf,MODE_LOW, 50,1);
      if(swHiIdx>0 && swLoIdx>0)
      {
         double sH=iHigh(_Symbol,PERIOD_CURRENT,swHiIdx), sL=iLow(_Symbol,PERIOD_CURRENT,swLoIdx);
         double discTop=sL+((sH-sL)/4.0), premBot=sH-((sH-sL)/4.0);
         double locHi=iHigh(_Symbol,m_tf,iHighest(_Symbol,m_tf,MODE_HIGH,5,2));
         double locLo=iLow(_Symbol, m_tf,iLowest(_Symbol, m_tf,MODE_LOW, 5,2));

         // S5 Bullish CHoCH in Discount
         if(close<discTop && close>locHi && iClose(_Symbol,m_tf,1)<=locHi)
         {
            if(!macro.AllowGoldLong() && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
            { Print("[MacroFilter] S5 CHoCH Long BLOCKED. macroBias=", macro.macroBias); return false; }
            out.name             = MACRO_TAG("LuxAlgo SMC: Bullish CHoCH in Discount Zone");
            out.type             = 0; out.entry = close;
            out.sl               = sL-(atr*0.5); out.tp = close+MathAbs(close-out.sl)*3;
            out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
         }

         // S6 Bearish CHoCH in Premium
         if(close>premBot && close<locLo && iClose(_Symbol,m_tf,1)>=locLo)
         {
            out.name             = MACRO_TAG("LuxAlgo SMC: Bearish CHoCH in Premium Zone");
            out.type             = 1; out.entry = close;
            out.sl               = sH+(atr*0.5); out.tp = close-MathAbs(close-out.sl)*3;
            out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
         }
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGIES 7 & 8: M1 Liquidity Sweep
      // ──────────────────────────────────────────────────────────────
      if(m_tf == PERIOD_M1)
      {
         double locSweepHi=iHigh(_Symbol,m_tf,iHighest(_Symbol,m_tf,MODE_HIGH,15,2));
         double locSweepLo=iLow(_Symbol, m_tf,iLowest(_Symbol, m_tf,MODE_LOW, 15,2));

         // S7 Bullish SSL Sweep
         if(iLow(_Symbol,m_tf,1)<locSweepLo && close>locSweepLo && (IsBullishEngulfing(1)||IsPinBar(1,true)))
         {
            // V3: Asian session block when macroBias < 0
            if(macro.macroBias < 0 && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
            { Print("[MacroFilter] S7 Asian SSL Sweep Long BLOCKED. macroBias=", macro.macroBias); return false; }
            out.name             = MACRO_TAG("M1 SMC: Sell-side Liquidity Sweep + Reclaim");
            out.type             = 0; out.entry = close;
            out.sl               = iLow(_Symbol,m_tf,1)-(atr*0.2);
            out.tp               = close+MathAbs(close-out.sl)*3.0;
            out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
         }

         // S8 Bearish BSL Sweep
         if(iHigh(_Symbol,m_tf,1)>locSweepHi && close<locSweepHi && (IsBearishEngulfing(1)||IsPinBar(1,false)))
         {
            out.name             = MACRO_TAG("M1 SMC: Buy-side Liquidity Sweep + Reclaim");
            out.type             = 1; out.entry = close;
            out.sl               = iHigh(_Symbol,m_tf,1)+(atr*0.2);
            out.tp               = close-MathAbs(close-out.sl)*3.0;
            out.confluence_score = 5; out.macro_confirmed = MACRO_CONFIRM; return true;
         }
      }

      // ──────────────────────────────────────────────────────────────
      // STRATEGIES 9 & 10: Ultimate Global Confluence
      // ──────────────────────────────────────────────────────────────
      if(is_global_bull && close<ema50 && is_oversold && (IsBullishEngulfing(1)||IsPinBar(1,true)))
      {
         if(!macro.AllowGoldLong() && (_Symbol=="XAUUSD"||_Symbol=="GOLD"))
         { Print("[MacroFilter] S9 Global Confluence Long BLOCKED. macroBias=", macro.macroBias); return false; }
         out.name             = MACRO_TAG("Ultimate Global Bullish Confluence + Oversold Bounce");
         out.type             = 0; out.entry = close;
         out.sl               = iLow(_Symbol,m_tf,1)-atr*0.5;
         out.tp               = close+MathAbs(close-out.sl)*2.0;
         out.confluence_score = 10; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      if(is_global_bear && close>ema50 && GetRSI(14)>70 && (IsBearishEngulfing(1)||IsPinBar(1,false)))
      {
         out.name             = MACRO_TAG("Ultimate Global Bearish Confluence + Overbought Rejection");
         out.type             = 1; out.entry = close;
         out.sl               = iHigh(_Symbol,m_tf,1)+atr*0.5;
         out.tp               = close-MathAbs(close-out.sl)*2.0;
         out.confluence_score = 10; out.macro_confirmed = MACRO_CONFIRM; return true;
      }

      // ──────────────────────────────────────────────────────────────
      // GOLD-SPECIFIC STRATEGIES 11-16
      // ──────────────────────────────────────────────────────────────
      if(_Symbol=="XAUUSD" || _Symbol=="GOLD")
      {
         double locHi_M15=iHigh(_Symbol,PERIOD_M15,iHighest(_Symbol,PERIOD_M15,MODE_HIGH,8,2));
         double locLo_M15=iLow(_Symbol, PERIOD_M15,iLowest(_Symbol, PERIOD_M15,MODE_LOW, 8,2));

         // S11: Gold F&R Bullish Neckline Break — HARD BLOCK on macro <= -2
         if(macro.BlockAllLongs())
         {
            Print("[MacroFilter] ALL Gold Longs HARD BLOCKED. macroBias=", macro.macroBias, " (-2 threshold)");
         }
         else if(is_global_bull && close>locHi_M15 &&
                 iClose(_Symbol,PERIOD_M15,1)>locHi_M15 && iOpen(_Symbol,PERIOD_M15,1)<=locHi_M15)
         {
            if(!macro.AllowGoldLong())
            { Print("[MacroFilter] S11 Gold Neckline Long BLOCKED. macroBias=", macro.macroBias); }
            else {
               out.name             = MACRO_TAG("Gold F&R Box: Bullish Neckline Breakout");
               out.type             = 0; out.entry = close;
               out.sl               = locLo_M15-(atr*0.3); out.tp = close+MathAbs(close-out.sl)*3.0;
               out.confluence_score = 8; out.macro_confirmed = MACRO_CONFIRM; return true;
            }
         }

         // S12: Gold F&R Bearish Neckline Break
         if(is_global_bear && close<locLo_M15 &&
            iClose(_Symbol,PERIOD_M15,1)<locLo_M15 && iOpen(_Symbol,PERIOD_M15,1)>=locLo_M15)
         {
            out.name             = MACRO_TAG("Gold F&R Box: Bearish Neckline Breakout");
            out.type             = 1; out.entry = close;
            out.sl               = locHi_M15+(atr*0.3); out.tp = close-MathAbs(close-out.sl)*3.0;
            out.confluence_score = 8; out.macro_confirmed = MACRO_CONFIRM; return true;
         }

         // S13 & 14: Micro FVG Scalp M1/M5
         if(m_tf==PERIOD_M1 || m_tf==PERIOD_M5)
         {
            double atr_m1=iATR(_Symbol,m_tf,14);
            // S13 Bullish FVG
            if(is_global_bull && !macro.BlockAllLongs())
            {
               double lo1=iLow(_Symbol,m_tf,1), hi3=iHigh(_Symbol,m_tf,3);
               if(lo1>hi3 && close<=lo1 && close>=hi3 && (IsBullishEngulfing(0)||IsPinBar(0,true)))
               {
                  if(!macro.AllowGoldLong())
                  { Print("[MacroFilter] S13 FVG Long BLOCKED. macroBias=", macro.macroBias); }
                  else {
                     out.name             = MACRO_TAG("Gold M1/M5: Bullish FVG Micro Scalp");
                     out.type             = 0; out.entry = close;
                     out.sl               = hi3-(atr_m1*0.2); out.tp = close+MathAbs(close-out.sl)*2.5;
                     out.confluence_score = 7; out.macro_confirmed = MACRO_CONFIRM; return true;
                  }
               }
            }
            // S14 Bearish FVG
            if(is_global_bear)
            {
               double hi1=iHigh(_Symbol,m_tf,1), lo3=iLow(_Symbol,m_tf,3);
               if(hi1<lo3 && close>=hi1 && close<=lo3 && (IsBearishEngulfing(0)||IsPinBar(0,false)))
               {
                  out.name             = MACRO_TAG("Gold M1/M5: Bearish FVG Micro Scalp");
                  out.type             = 1; out.entry = close;
                  out.sl               = lo3+(atr_m1*0.2); out.tp = close-MathAbs(close-out.sl)*2.5;
                  out.confluence_score = 7; out.macro_confirmed = MACRO_CONFIRM; return true;
               }
            }
         }

         // S15 & 16: Explosive Momentum Scalp M5/M15/M30
         if(m_tf==PERIOD_M5 || m_tf==PERIOD_M15 || m_tf==PERIOD_M30)
         {
            double atr_c=iATR(_Symbol,m_tf,14);
            // S15 Bullish Momentum
            if(ema10>ema200 && is_global_bull && !macro.BlockAllLongs())
            {
               if(iLow(_Symbol,m_tf,1)<=ema10 && close>ema10 && IsBullishEngulfing(1))
               {
                  if(!macro.AllowGoldLong())
                  { Print("[MacroFilter] S15 Momentum Long BLOCKED. macroBias=", macro.macroBias); }
                  else {
                     out.name             = MACRO_TAG("Gold Momentum: Exploding Pullback Scalp (LONG)");
                     out.type             = 0; out.entry = close;
                     out.sl               = iLow(_Symbol,m_tf,1)-(atr_c*0.5);
                     out.tp               = close+MathAbs(close-out.sl)*1.5;
                     out.confluence_score = 6; out.macro_confirmed = MACRO_CONFIRM; return true;
                  }
               }
            }
            // S16 Bearish Momentum
            if(ema10<ema200 && is_global_bear)
            {
               if(iHigh(_Symbol,m_tf,1)>=ema10 && close<ema10 && IsBearishEngulfing(1))
               {
                  out.name             = MACRO_TAG("Gold Momentum: Exploding Pullback Scalp (SHORT)");
                  out.type             = 1; out.entry = close;
                  out.sl               = iHigh(_Symbol,m_tf,1)+(atr_c*0.5);
                  out.tp               = close-MathAbs(close-out.sl)*1.5;
                  out.confluence_score = 6; out.macro_confirmed = MACRO_CONFIRM; return true;
               }
            }
         }
      }

      #undef MACRO_TAG
      #undef MACRO_CONFIRM
      return false;
   }
};

//+------------------------------------------------------------------+
//| HEADS-UP DISPLAY  V3  (adds Macro Correlation panel)            |
//+------------------------------------------------------------------+
class CHUD : public CVisualizer
{
public:
   //------------------------------------------------------------------
   // Main render — call every OnTimer() / OnTick()
   // Pass the full CMacroEngine so we can display live macro state.
   //------------------------------------------------------------------
   void Render(double dailyDD, double absDD, string phase,
               string aiMsg, const CMacroEngine &macro)
   {
      string p = "OV_HUD_";

      // ── Background panel ─────────────────────────────────────────
      CreateLabel(p+"BG", 10, 10, 440, 200, clrBlack, clrDarkCyan);

      // ── Header ───────────────────────────────────────────────────
      SetField(p+"Title",  15, 15, "PROJECT OMNIVISION SMC PRO V3",  clrCyan, 10);

      // ── Risk / Session info ──────────────────────────────────────
      SetField(p+"Phase",  15, 35, "Market Phase: " + phase,         clrWhite, 8);
      color ddColor  = (dailyDD > 4)  ? clrRed : clrLime;
      color absColor = (absDD   > 8)  ? clrRed : clrYellow;
      SetField(p+"DD",     15, 50, "Daily DD : " + DoubleToString(dailyDD,2) + "%", ddColor, 8);
      SetField(p+"AbsDD",  15, 65, "Total DD : " + DoubleToString(absDD,2)  + "%", absColor, 8);
      SetField(p+"Msg",    15, 80, "AI Tutor : " + aiMsg,            clrGold, 8);

      // ── Separator ────────────────────────────────────────────────
      SetField(p+"Sep",    15, 95, StringFormat("%-52s", "─── Macro Correlation Engine ───────────────────────"), clrDimGray, 7);

      // ── DXY row ──────────────────────────────────────────────────
      color dxyColor = (macro.dxy_bias ==  1) ? clrLime :
                       (macro.dxy_bias == -1) ? clrRed  : clrGray;
      SetField(p+"DXY",   15, 107, macro.DXYLabel(),   dxyColor, 8);

      // ── US10Y row ────────────────────────────────────────────────
      color yldColor = (macro.us10y_bias ==  1) ? clrLime :
                       (macro.us10y_bias == -1) ? clrRed  : clrGray;
      SetField(p+"US10Y", 15, 120, macro.YieldLabel(), yldColor, 8);

      // ── VIX row ──────────────────────────────────────────────────
      color vixColor = (macro.vix_bias ==  1) ? clrLime :
                       (macro.vix_bias == -1) ? clrRed  : clrGray;
      SetField(p+"VIX",   15, 133, macro.VIXLabel(),   vixColor, 8);

      // ── macroBias gauge ──────────────────────────────────────────
      color biasColor = (macro.macroBias >= 1)  ? clrLime :
                        (macro.macroBias == 0)  ? clrGold :
                        (macro.macroBias == -1) ? clrOrange : clrRed;
      SetField(p+"Bias",  15, 148, macro.BiasLabel(), biasColor, 9);

      // ── Long-gate status ─────────────────────────────────────────
      string gateStr = macro.BlockAllLongs()
                       ? "⛔ GOLD LONGS HARD BLOCKED (macroBias ≤ -2)"
                       : (macro.AllowGoldLong()
                          ? "✔  Gold Longs ALLOWED (macroBias ≥ 0)"
                          : "⚠  Gold Longs RESTRICTED (macroBias = -1)");
      color gateColor = macro.BlockAllLongs() ? clrRed :
                        (macro.AllowGoldLong() ? clrLime : clrOrange);
      SetField(p+"Gate", 15, 168, gateStr, gateColor, 8);
   }

private:
   void CreateLabel(string name, int x, int y, int w, int h,
                    color bg, color border)
   {
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,   CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,    w);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,    h);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,  bg);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,    1);
   }

   void SetField(string name, int x, int y, string txt, color clr, int size)
   {
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE, 10+x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE, 10+y);
      ObjectSetString(0, name,OBJPROP_TEXT,       txt);
      ObjectSetInteger(0,name,OBJPROP_COLOR,      clr);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,   size);
   }
};
