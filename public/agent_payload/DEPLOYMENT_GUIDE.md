# Project OmniVision - Deployment Guide

## 1. Hosting the Web Dashboard (Docker)
Your dashboard is built using React + Express and can be deployed anywhere docker is supported.

### Dockerfile (For Dummies)
1. Create a `Dockerfile` in the root menu of your codebase containing:
```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "run", "start"]
```

2. Open your terminal and build it:
`docker build -t omnivision-dashboard .`

3. Run the container:
`docker run -p 3000:3000 omnivision-dashboard`
Your dynamic UI is now accessible on `localhost:3000`.

---

## 2. Deploying the Headless Python MT5 Agent OR MQL5 EA
OmniVision supports two execution engines: a **Headless Python Agent** (Best for AI learning) and a **Native MQL5 EA** (Best for low latency/stability).

### Option A: Python Agent (AI Learning)
1. Copy `agent.py`, `strategies.py`, and `dashboard.py` to your Windows VPS.
2. Install Python 3.10+: `pip install MetaTrader5 pandas requests`
3. Run: `python agent.py`

### Option B: Native MQL5 Expert Advisor (Production stability)
1. Copy `OmniVision_SMC_EA.mq5` from the dashboard to your MT5 `MQL5/Experts` folder.
2. In MT5 Terminal:
   - Go to `Tools -> Options -> Expert Advisors`.
   - Check **"Allow WebRequests for listed URL"**.
   - Add your Dashboard URL: `http://localhost:3000` (or your remote server IP).
3. Open the EA in the MetaEditor and press **'F7' to Compile**.
4. Drag the EA onto a Gold (XAUUSD) or Bitcoin (BTCUSD) chart.
5. In the Inputs tab:
   - `InpServerUrl`: Point this to your dashboard's `/api/update_trade` endpoint.
   - Set your `InpRiskPct` and `Drawdown Limits` according to your Prop Firm challenge rules.

### Performance Sync
Regardless of which engine you use, the Dashboard UI will automatically consolidate your Live Equity, PNL, and Strategy Learning Matrix by listening to the `/api/update_trade` POST requests coming from your MT5 terminal.

*Mentality is Key: Trust the Learning Matrix.*
