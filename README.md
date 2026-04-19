
---

## What changed across each file

### `OmniVision_Visual_Mentor.mqh` — **CMacroEngine + updated HUD**
The new `CMacroEngine` class runs at every tick and resolves three daily-bar signals into a single integer:

| Signal | Direction | Gold bias |
|---|---|---|
| DXY close > open | Strong USD | −1 |
| US10Y close > open | Rising yield | −1 |
| VIX close > open | Fear spike | +1 |

`macroBias = sum` ∈ **[-3 … +3]**. If the broker doesn't carry `USDX`, it auto-falls back to an inverse EURUSD proxy. `US10Y` / `VIX` degrade gracefully to `0` (neutral) when unavailable.

`CHUD::Render()` now accepts the macro engine and renders a **5-row overlay** — one row per asset, a colour-coded animated gauge bar, and a green/red long-gate status pill.

### `OmniVision_SMC_EA.mq5` — **Macro-gated execution**
Three gate tiers applied inside every `CheckConfluence()` call before any Gold Long is sent to MT5:

- `macroBias >= 0` → **allowed**
- `macroBias == -1` → **blocked** (prints `[MacroFilter]` to journal)
- `macroBias <= -2` → **HARD BLOCK** — entire Gold Long branch is skipped, including the M1 Asian-session liquidity sweep setups

When `macroBias >= +1`, the string `" (Macro Sync)"` is appended to the setup name so it's visible in the trade history. The `NotifyDashboard()` call now appends the full `CMacroEngine.ToJSON()` fragment to every POST payload.

### `App.tsx` — **MacroPanel component**
A new sidebar section renders live DXY / US10Y / VIX rows with ▲/▼ arrows, a gradient gauge bar (red → gold → green), and the long-gate status pill. A compact 3-column macro summary also lives inside the Mentor narrative panel, and the footer adds a **MACRO BIAS** stat. When `longsBlocked = true`, a red banner overlays the chart area.

### `server.ts` — **Macro state persistence + new endpoint**
- `defaultDb.macro` seeds the initial neutral state
- `POST /api/update_trade` now merges the incoming `macro` JSON block into `db.json`
- New `GET /api/macro` endpoint for lightweight polling if you want to separate the macro refresh from the full state poll

### `db.json` — **Seeded macro block**
Added the `"macro"` key with all biases at `0` so the dashboard renders cleanly on first boot before the EA connects.

Here's the complete Windows 10 deployment guide for OmniVision SMC PRO V3, covering every step from scratch:

---

## 🖥️ OmniVision SMC PRO V3 — Windows 10 Deployment Guide

---

### PHASE 1 — Install Prerequisites

**Step 1 — Install Node.js**

1. Go to **https://nodejs.org** and download the **LTS** version (v22 or higher)
2. Run the installer — accept all defaults, make sure **"Add to PATH"** is checked
3. When done, open **Command Prompt** (`Win + R` → type `cmd` → Enter) and verify:
   ```
   node --version
   npm --version
   ```
   Both should print a version number. If they don't, restart your PC and try again.

**Step 2 — Install Python 3.10+** *(only needed for the Python headless agent)*

1. Go to **https://python.org/downloads** and download Python 3.10 or newer
2. Run the installer — **check "Add Python to PATH"** at the bottom before clicking Install
3. Verify in Command Prompt:
   ```
   python --version
   ```

**Step 3 — Install MetaTrader 5**

1. Download MT5 from your broker's website or **https://www.metatrader5.com**
2. Install and log in to your trading account

---

### PHASE 2 — Set Up the Dashboard (Node.js Server)

**Step 4 — Get the project files**

Place all your project files into a folder. For example:
```
C:\OmniVision\
```
Your folder should look like this when done:
```
C:\OmniVision\
├── src\
│   ├── App.tsx
│   ├── main.tsx
│   └── index.css
├── public\
│   └── agent_payload\
│       ├── OmniVision_SMC_EA.mq5
│       ├── OmniVision_Visual_Mentor.mqh
│       ├── agent.py
│       ├── strategies.py
│       ├── dashboard.py
│       └── DEPLOYMENT_GUIDE.md
├── package.json
├── server.ts
├── db.json
├── index.html
├── vite.config.ts
└── tsconfig.json
```

**Step 5 — Install Node dependencies**

Open Command Prompt, navigate to your project folder, and run:
```
cd C:\OmniVision
npm install
```
This will download all packages listed in `package.json`. It may take 1–3 minutes.

**Step 6 — Create your environment file**

In your project folder, create a new file called `.env.local` (no extension, just `.env.local`):

1. Open Notepad
2. Type:
   ```
   GEMINI_API_KEY=your_key_here
   APP_URL=http://localhost:3000
   ```
3. Save as **All Files** type with the filename `.env.local` inside `C:\OmniVision\`

**Step 7 — Start the dashboard server**

In Command Prompt (still inside `C:\OmniVision`), run:
```
npm run dev
```
You should see:
```
OmniVision SMC PRO V3 Server running on http://localhost:3000
```

Open your browser and go to **http://localhost:3000** — you should see the dashboard.

> 💡 **Keep this Command Prompt window open.** Closing it stops the server.

---

### PHASE 3 — Deploy the MQL5 Expert Advisor

**Step 8 — Copy the EA files to MetaTrader**

1. In MT5, go to the top menu: **File → Open Data Folder**
2. Navigate into: `MQL5\Experts\`
3. Copy these two files from `C:\OmniVision\public\agent_payload\` into that folder:
   - `OmniVision_SMC_EA.mq5`
   - `OmniVision_Visual_Mentor.mqh`

   Both files **must be in the same folder** — the EA `#include`s the mentor file.

**Step 9 — Allow WebRequests in MT5**

The EA posts live trade data to your dashboard. You must whitelist the URL:

1. In MT5, go to **Tools → Options**
2. Click the **Expert Advisors** tab
3. Check **"Allow WebRequests for listed URL"**
4. Click the **+** button and add:
   ```
   http://localhost:3000
   ```
5. Click **OK**

**Step 10 — Compile the EA**

1. In MT5, go to **Tools → MetaEditor** (or press `F4`)
2. In MetaEditor, press `Ctrl + O` and open `OmniVision_SMC_EA.mq5`
3. Press **F7** to compile
4. Check the **Errors** tab at the bottom — it should say **"0 error(s), 0 warning(s)"**

**Step 11 — Attach the EA to a chart**

1. Back in MT5, open a **XAUUSD** chart (right-click the symbol in Market Watch → Chart Window)
2. Set the chart to **M5** or **M15** timeframe
3. In the Navigator panel (press `Ctrl + N` to open it), find `OmniVision_SMC_EA` under Expert Advisors
4. Double-click it or drag it onto the chart
5. The EA settings dialog opens — configure the **Inputs** tab:

| Setting | Recommended Value |
|---|---|
| InpStartingBalance | Your prop firm starting balance (e.g. `100000`) |
| InpBaseRiskPct | `0.5` (0.5% per trade) |
| InpMaxRiskPct | `1.5` |
| InpMaxDailyDD | `4.0` |
| InpMaxTotalDD | `8.0` |
| InpDXYSymbol | `USDX` (or leave blank — falls back to EURUSD proxy) |
| InpUS10YSymbol | `US10Y` (check if your broker offers it) |
| InpVIXSymbol | `VIX` (check if your broker offers it) |
| InpServerUrl | `http://localhost:3000/api/update_trade` |

6. Under the **Common** tab: check **"Allow live trading"** and **"Allow DLL imports"**
7. Click **OK**

You should see a smiley face 🙂 in the top-right corner of the chart — this means the EA is running.

---

### PHASE 4 — Deploy the Python Agent *(Optional — for AI learning mode)*

**Step 12 — Install Python dependencies**

Open a **new** Command Prompt window and run:
```
pip install MetaTrader5 pandas requests
```

**Step 13 — Copy the Python files**

Copy these from `C:\OmniVision\public\agent_payload\` to anywhere on your PC (e.g. `C:\OmniVision\agent\`):
- `agent.py`
- `strategies.py`
- `dashboard.py`

**Step 14 — Configure and run the agent**

1. Open `agent.py` in Notepad or any text editor
2. At the bottom of the file, confirm these two settings:
   ```python
   MODE         = "LIVE"     # or "BACKTEST"
   TARGET_CHART = "XAUUSD"
   ```
3. Make sure MT5 is **open and logged in**, then run:
   ```
   cd C:\OmniVision\agent
   python agent.py
   ```

The agent will connect to MT5, scan for setups, and POST results to the dashboard automatically.

---

### PHASE 5 — Verify Everything Is Connected

**Step 15 — Connection checklist**

Open your browser to **http://localhost:3000** and confirm:

| Item | What to check |
|---|---|
| Dashboard loads | You see the Ω header and instrument prices |
| MACRO BIAS display | Shows `0 / 3` in the footer initially, updates when MT5 EA ticks |
| Macro panel (sidebar) | DXY / US10Y / VIX rows appear with ▲/▼ arrows |
| System Pulse | Updates with timestamps when the EA posts data |
| Account balance | Matches your MT5 account balance after first trade event |

**Step 16 — Check EA is posting data**

In MT5, open the **Journal** tab (bottom panel). You should see lines like:
```
OmniVision SMC PRO V3.0 Initialized with Macro Correlation Engine.
CMacroEngine Init | DXY: EURUSD Proxy | US10Y: N/A | VIX: N/A
```
If you see `[MacroFilter] Long BLOCKED`, that means the macro engine is working and filtering entries correctly.

---

### PHASE 6 — Running It Automatically on Startup *(Optional)*

If you want the dashboard to auto-start when Windows boots:

**Step 17 — Create a startup batch file**

1. Open Notepad and paste:
   ```batch
   @echo off
   cd C:\OmniVision
   npm run dev
   ```
2. Save as `start_omnivision.bat` on your Desktop

3. Press `Win + R`, type `shell:startup`, and press Enter
4. Copy `start_omnivision.bat` into that Startup folder

Now the server launches automatically every time Windows starts.

---

### Common Issues & Fixes

| Problem | Fix |
|---|---|
| `npm` not found | Restart PC after installing Node.js |
| EA shows ☹ (sad face) | Check **Allow live trading** is enabled in EA Common tab |
| Dashboard not updating | Confirm `InpServerUrl` in EA inputs matches exactly `http://localhost:3000/api/update_trade` |
| WebRequest failed in Journal | Go to Tools → Options → Expert Advisors and add the URL |
| `USDX` symbol not found | Leave `InpDXYSymbol` blank — EA auto-uses EURUSD proxy |
| `US10Y` / `VIX` not found | Normal for most brokers — biases default to `0` (neutral), EA continues |
| Port 3000 already in use | Run `netstat -ano \| findstr :3000` in CMD, then `taskkill /PID <number> /F` |
| Python `ModuleNotFoundError` | Run `pip install MetaTrader5 pandas requests` again |
