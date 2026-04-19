import express from "express";
import { createServer as createViteServer } from "vite";
import fs from "fs";
import path from "path";

async function startServer() {
  const app  = express();
  const PORT = 3000;

  app.use(express.json());

  const dbPath = path.join(process.cwd(), 'db.json');

  const defaultDb = {
    instruments: [
      { symbol: "XAUUSD", price: 2342.10, bias: "Bullish", up: true  },
      { symbol: "BTCUSD", price: 64231.50, bias: "Bearish", up: false },
    ],
    matrix: [
      { name: 'Gold Trend',  val: '1.15x', up: true  },
      { name: 'MSS Reversal',val: '1.00x', up: null  },
      { name: 'London Open', val: '0.82x', up: false },
      { name: 'Liq. Sweep',  val: '1.05x', up: true  },
      { name: 'FVG Gap',     val: '1.00x', up: null  },
      { name: 'Order Block', val: '1.20x', up: true  },
      { name: 'PD Array',    val: '1.00x', up: null  },
    ],
    narrative: {
      strategy: "Gold Trend Continuation",
      rationale: "We entered this Long because price swept SSL into a Discount zone and formed a high-probability Order Block.",
      details:   "The 200 EMA indicates a strong structural uptrend. Institutional footprint detected at 2338.50 level.",
      risk:      "Stop-loss is set below the recent sweep. Liquidity Trap detected in Asian session; lot size reduced by 15% via Learning Logic.",
    },
    pulse: [
      "[14:02:11] XAU FVG Identified",
      "[14:02:15] MAE Filter Applied: 0.85x",
      "[14:02:16] Execution Sent to MT5...",
    ],
    stats: {
      account:  242105.42,
      profit:   14204.11,
      winRate:  68.2,
      latency:  12,
    },
    // ── V3: Macro Correlation Engine state ──────────────────────
    macro: {
      macroBias:    0,     // -3 … +3
      dxyBias:      0,     // -1 | 0 | +1
      us10yBias:    0,
      vixBias:      0,
      dxyNative:    false, // true when broker has USDX symbol
      us10yNative:  false,
      vixNative:    false,
      longsBlocked: false, // true when macroBias <= -2
    },
  };

  if (!fs.existsSync(dbPath)) {
    fs.writeFileSync(dbPath, JSON.stringify(defaultDb, null, 2));
  } else {
    // Migrate: inject macro key if missing from existing db
    const existing = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
    if (!existing.macro) {
      existing.macro = defaultDb.macro;
      fs.writeFileSync(dbPath, JSON.stringify(existing, null, 2));
    }
  }

  // ── GET /api/state — serves live data with tick simulation ─────
  app.get("/api/state", (_req, res) => {
    try {
      const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
      // Simulate live price ticks
      data.instruments[0].price = +(data.instruments[0].price + (Math.random() - 0.5) * 0.5).toFixed(2);
      data.instruments[1].price = +(data.instruments[1].price + (Math.random() - 0.5) * 5).toFixed(2);
      data.stats.latency        = Math.floor(Math.random() * 8) + 10;
      fs.writeFileSync(dbPath, JSON.stringify(data, null, 2));
      res.json(data);
    } catch (err) {
      res.status(500).json({ error: "Failed to read database" });
    }
  });

  // ── POST /api/update_trade — receives MT5 agent payload ────────
  // V3: payload now optionally includes `macro` block from MQL5 EA
  app.post("/api/update_trade", (req, res) => {
    const {
      strategy, win, pnl, narrativeUpdates,
      absoluteBalance, absoluteProfit,
      macro,                      // ← NEW V3: from CMacroEngine.ToJSON()
    } = req.body;

    try {
      const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));

      // ── Narrative ──────────────────────────────────────────────
      if (narrativeUpdates) data.narrative = narrativeUpdates;

      // ── Financials ────────────────────────────────────────────
      if (absoluteBalance !== undefined) data.stats.account = absoluteBalance;
      else data.stats.account += (pnl ?? 0);

      if (absoluteProfit !== undefined) data.stats.profit = absoluteProfit;
      else data.stats.profit += (pnl ?? 0);

      // ── Pulse ─────────────────────────────────────────────────
      const ts = new Date().toISOString().split('T')[1].substring(0, 8);
      data.pulse.pop();
      data.pulse.unshift(`[${ts}] ${strategy} execution processed`);

      // ── V3: Macro state ───────────────────────────────────────
      if (macro && typeof macro === 'object') {
        data.macro = {
          macroBias:    macro.macroBias   ?? data.macro.macroBias,
          dxyBias:      macro.dxyBias     ?? data.macro.dxyBias,
          us10yBias:    macro.us10yBias   ?? data.macro.us10yBias,
          vixBias:      macro.vixBias     ?? data.macro.vixBias,
          dxyNative:    macro.dxyNative   ?? data.macro.dxyNative,
          us10yNative:  macro.us10yNative ?? data.macro.us10yNative,
          vixNative:    macro.vixNative   ?? data.macro.vixNative,
          longsBlocked: macro.longsBlocked ?? (macro.macroBias <= -2),
        };
      }

      fs.writeFileSync(dbPath, JSON.stringify(data, null, 2));
      res.json({ success: true, newAccountBal: data.stats.account, macro: data.macro });
    } catch (err) {
      res.status(500).json({ error: "Failed to update database" });
    }
  });

  // ── V3: GET /api/macro — lightweight macro-only polling endpoint
  app.get("/api/macro", (_req, res) => {
    try {
      const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
      res.json(data.macro ?? defaultDb.macro);
    } catch (err) {
      res.status(500).json({ error: "Failed to read macro state" });
    }
  });

  // Static files for python agent download
  app.use('/scripts', express.static(path.join(process.cwd(), 'agent_payload')));

  // Vite middleware
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req, res) => res.sendFile(path.join(distPath, 'index.html')));
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`OmniVision SMC PRO V3 Server running on http://localhost:${PORT}`);
  });
}

startServer();
