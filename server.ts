import express from "express";
import { createServer as createViteServer } from "vite";
import fs from "fs";
import path from "path";

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json());

  // In-memory "database" to replace mock data for production readiness
  const dbPath = path.join(process.cwd(), 'db.json');
  
  const defaultDb = {
    instruments: [
        { symbol: "XAUUSD", price: 2342.10, bias: "Bullish", up: true },
        { symbol: "BTCUSD", price: 64231.50, bias: "Bearish", up: false }
    ],
    matrix: [
        { name: 'Gold Trend', val: '1.15x', up: true },
        { name: 'MSS Reversal', val: '1.00x', up: null },
        { name: 'London Open', val: '0.82x', up: false },
        { name: 'Liq. Sweep', val: '1.05x', up: true },
        { name: 'FVG Gap', val: '1.00x', up: null },
        { name: 'Order Block', val: '1.20x', up: true },
        { name: 'PD Array', val: '1.00x', up: null },
    ],
    narrative: {
        strategy: "Gold Trend Continuation",
        rationale: "We entered this Long because price swept SSL into a Discount zone and formed a high-probability Order Block.",
        details: "The 200 EMA indicates a strong structural uptrend. Institutional footprint detected at 2338.50 level.",
        risk: "Stop-loss is set below the recent sweep. Liquidity Trap detected in Asian session; lot size reduced by 15% via Learning Logic."
    },
    pulse: [
        "[14:02:11] XAU FVG Identified",
        "[14:02:15] MAE Filter Applied: 0.85x",
        "[14:02:16] Execution Sent to MT5..."
    ],
    stats: {
        account: 242105.42,
        profit: 14204.11,
        winRate: 68.2,
        latency: 12
    }
  };

  // Seed DB if it doesn't exist
  if (!fs.existsSync(dbPath)) {
      fs.writeFileSync(dbPath, JSON.stringify(defaultDb, null, 2));
  }

  // Application API Ends
  app.get("/api/state", (req, res) => {
    try {
        const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
        // Simulate live slight tick variations to show the dynamic system working
        data.instruments[0].price = +(data.instruments[0].price + (Math.random() - 0.5) * 0.5).toFixed(2);
        data.instruments[1].price = +(data.instruments[1].price + (Math.random() - 0.5) * 5).toFixed(2);
        data.stats.latency = Math.floor(Math.random() * 8) + 10;
        
        // Save back state
        fs.writeFileSync(dbPath, JSON.stringify(data, null, 2));
        
        res.json(data);
    } catch(err) {
        res.status(500).json({ error: "Failed to read database" });
    }
  });

  // Simulated endpoint for Python MT5 Agent to post new completed trades and trigger UI update
  app.post("/api/update_trade", (req, res) => {
    const { strategy, win, pnl, narrativeUpdates, absoluteBalance, absoluteProfit } = req.body;
    try {
        const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
        
        if (narrativeUpdates) data.narrative = narrativeUpdates;
        
        // Sync true MT5 account values if provided natively
        if (absoluteBalance !== undefined) data.stats.account = absoluteBalance;
        else data.stats.account += pnl;
        
        if (absoluteProfit !== undefined) data.stats.profit = absoluteProfit;
        else data.stats.profit += pnl;
        
        // Push to pulse
        data.pulse.pop();
        data.pulse.unshift(`[${new Date().toISOString().split('T')[1].substr(0,8)}] ${strategy} execution processed`);

        fs.writeFileSync(dbPath, JSON.stringify(data, null, 2));
        res.json({ success: true, newAccountBal: data.stats.account });
    } catch(err) {
        res.status(500).json({ error: "Failed to update database" });
    }
  });

  // Serve static files from python agents so the frontend can download them
  app.use('/scripts', express.static(path.join(process.cwd(), 'agent_payload')));

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Dynamic Execution Server running on http://localhost:${PORT}`);
  });
}

startServer();
