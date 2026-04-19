/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useEffect, useState } from 'react';

export default function App() {
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    const fetchState = async () => {
      try {
        const res = await fetch('/api/state');
        if (res.ok) {
          const json = await res.json();
          setData(json);
        }
      } catch (err) {
        console.error("Failed to fetch state:", err);
      }
    };
    
    // Initial fetch
    fetchState();
    
    // Poll for dynamic updates from the MT5 Python Agent backend
    const interval = setInterval(fetchState, 3000);
    return () => clearInterval(interval);
  }, []);

  if (!data) {
    return (
      <div className="flex flex-col h-screen overflow-hidden bg-bg-deep text-accent-cyan items-center justify-center font-mono text-sm">
        <div className="animate-pulse flex flex-col items-center">
            <div className="text-4xl mb-4">Ω</div>
            Initializing Live Agent Database...
        </div>
      </div>
    );
  }

  const handleDownload = () => {
      // Directs user to the deployment guide which instructs them how to use the python files
      window.open("/scripts/DEPLOYMENT_GUIDE.md", "_blank");
  };

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-bg-deep text-text-primary font-sans w-full">
      {/* Top Navigation Bar */}
      <header className="h-16 bg-bg-surface border-b border-white/10 flex items-center justify-between px-6 shrink-0">
        <div className="flex flex-row items-center gap-3">
          <div className="w-8 h-8 border-2 border-accent-cyan flex items-center justify-center font-bold font-mono shadow-[0_0_10px_var(--color-accent-cyan)]">
            Ω
          </div>
          <h2 className="text-lg tracking-widest m-0">PROJECT OMNIVISION</h2>
        </div>
        <div className="flex gap-4 items-center">
          <span className="text-xs text-text-secondary">SERVER: LDN-MT5-PRO</span>
          <div className="bg-[#00ffa31a] text-accent-green px-3 py-1 rounded-full text-[11px] uppercase tracking-widest border border-[#00ffa34d]">
            Autonomous: ON
          </div>
        </div>
      </header>

      {/* Main Layout Grid */}
      <main className="flex-1 grid grid-cols-1 md:grid-cols-[240px_1fr] lg:grid-cols-[240px_1fr_280px] overflow-hidden">
        {/* Sidebar */}
        <aside className="bg-bg-surface border-r border-white/10 flex flex-col gap-6 p-5 overflow-y-auto hidden md:flex">
          <div>
            <span className="text-[10px] uppercase text-text-secondary tracking-widest mb-3 block">
              Instruments
            </span>
            {data.instruments.map((inst: any, i: number) => (
                <div key={i} className={`p-3 border mb-2 rounded ${inst.up ? 'border-accent-cyan bg-[#00f3ff05]' : 'border-white/10 bg-white/5'}`}>
                <h4 className="text-base flex justify-between font-normal mb-0">
                    {inst.symbol} <span className={inst.up ? "text-accent-green" : "text-accent-red"}>{inst.price.toFixed(2)}</span>
                </h4>
                <div className="mt-2 text-xs flex items-center gap-1.5">
                    <div className={`w-2 h-2 rounded-full ${inst.up ? 'bg-accent-green' : 'bg-accent-red'}`}></div>
                    H1 Bias: {inst.bias} ({inst.up ? '>' : '<'}200 EMA)
                </div>
                </div>
            ))}
          </div>

          <div>
            <span className="text-[10px] uppercase text-text-secondary tracking-widest mb-3 block">
              Strategy Learning Matrix
            </span>
            <div className="flex flex-col gap-2.5">
              {data.matrix.map((item: any, idx: number) => (
                <div
                  key={idx}
                  className="flex justify-between font-mono text-xs pb-2 border-b border-white/5"
                >
                  <span>{item.name}</span>
                  <span
                    className={
                      item.up === true
                        ? 'text-accent-green'
                        : item.up === false
                        ? 'text-accent-red'
                        : 'text-text-primary'
                    }
                  >
                    {item.val}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </aside>

        {/* Chart View */}
        <section className="relative bg-[#08080a] chart-grid overflow-hidden min-h-[400px]">
          {/* EMA Indicator */}
          <div className="absolute w-full h-[2px] bg-accent-gold top-[35%] shadow-[0_0_15px_var(--color-accent-gold)] opacity-60"></div>
          <div className="absolute top-[35%] left-5 text-[10px] text-accent-gold mt-1">
            H1 200 EMA (DYNAMIC BIAS)
          </div>

          {/* Buy Side Liquidity */}
          <div className="absolute w-full border-t border-dashed border-text-secondary top-[15%] z-10"></div>
          <span className="absolute right-2.5 text-[9px] text-text-secondary uppercase -mt-4 top-[15%] hidden sm:block">
            Buy-Side Liquidity (BSL) - Daily High
          </span>

          {/* Sell Side Liquidity */}
          <div className="absolute w-full border-t border-dashed border-text-secondary top-[85%] z-10"></div>
          <span className="absolute right-2.5 text-[9px] text-text-secondary uppercase -mt-4 top-[85%] hidden sm:block">
            Sell-Side Liquidity (SSL) - H4 Swing Low
          </span>

          {/* Order Block */}
          <div className="absolute bg-[#00f3ff26] border border-accent-cyan z-20 top-[60%] left-[10%] sm:left-[30%] w-[120px] h-[60px]"></div>
          <div className="absolute bg-bg-surface border border-white/10 px-2 py-1 text-[11px] text-accent-cyan font-mono shadow-[4px_4px_0_rgba(0,0,0,0.5)] z-30 top-[55%] left-[10%] sm:left-[30%]">
            Institutional OB (Bullish)
          </div>

          {/* Mentorship Label */}
          <div className="absolute bg-bg-surface border border-accent-gold px-2 py-1 text-[11px] text-white font-mono shadow-[4px_4px_0_rgba(0,0,0,0.5)] z-30 top-[75%] left-[40%] sm:left-[45%]">
            {data.narrative.strategy.toUpperCase()} CONFIRMED
          </div>

          {/* Visual feedback for active trade */}
          <div className="absolute top-[62%] left-[35%] sm:left-[42%] w-2.5 h-2.5 bg-accent-green rounded-full shadow-[0_0_10px_var(--color-accent-green)] z-30"></div>
        </section>

        {/* Mentor Panel */}
        <aside className="bg-bg-surface border-l border-white/10 flex flex-col p-5 gap-5 overflow-y-auto lg:flex hidden">
          <span className="text-[10px] uppercase text-text-secondary tracking-widest">
            Live Agent Narrative
          </span>
          <div className="bg-[#14161cd9] border border-[#00f3ff33] p-4 rounded-lg flex-1 flex flex-col">
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Strategy:</strong> {data.narrative.strategy}
            </p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Rationale:</strong> {data.narrative.rationale}
            </p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              {data.narrative.details}
            </p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Risk Advisory:</strong> {data.narrative.risk}
            </p>
            <div className="mt-auto pt-4 flex flex-col gap-2">
                <p className="text-[10px] text-text-secondary text-center mb-1">Downloads Headless Agent (.py)</p>
              <button 
                className="w-full p-2.5 bg-accent-cyan border-none font-bold cursor-pointer rounded text-black text-xs hover:bg-[#00d0db] transition-colors"
                onClick={handleDownload}
              >
                ACCESS MT5 FILES & DEPLOYMENT GUIDE
              </button>
            </div>
          </div>

          <div className="bg-[#ffb8000d] border border-[#ffb80033] p-3 rounded">
            <span className="text-[10px] uppercase text-accent-gold tracking-widest mb-2 block">
              System Pulse
            </span>
            <div className="text-[11px] font-mono leading-relaxed text-text-primary h-[60px] overflow-hidden">
              {data.pulse.map((line: string, i: number) => (
                  <div key={i}>{line}</div>
              ))}
            </div>
          </div>
        </aside>
      </main>

      {/* Footer Stats */}
      <footer className="h-12 bg-bg-surface border-t border-white/10 flex items-center px-6 gap-10 font-mono text-xs shrink-0 whitespace-nowrap overflow-x-auto">
        <div>
          <span className="text-text-secondary">ACCOUNT:</span>{' '}
          <b className="text-accent-cyan ml-2">${data.stats.account.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</b>
        </div>
        <div>
          <span className="text-text-secondary">TOTAL PROFIT:</span>{' '}
          <b className={data.stats.profit >= 0 ? "text-accent-green ml-2" : "text-accent-red ml-2"}>
              {data.stats.profit >= 0 ? '+' : ''}${data.stats.profit.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</b>
        </div>
        <div>
          <span className="text-text-secondary">WIN RATE:</span>{' '}
          <b className="text-accent-cyan ml-2">{data.stats.winRate.toFixed(1)}%</b>
        </div>
        <div>
          <span className="text-text-secondary">MAE ADJUSTMENT:</span>{' '}
          <b className="text-accent-gold ml-2">ACTIVE</b>
        </div>
        <div className="ml-auto">
          <span className="text-text-secondary">LATENCY:</span>{' '}
          <b className="text-accent-cyan ml-2">{data.stats.latency}ms</b>
        </div>
      </footer>
    </div>
  );
}
