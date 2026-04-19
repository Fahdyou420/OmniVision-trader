/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 *
 * OmniVision SMC PRO V3 — React Dashboard
 * New in V3: MacroPanel component — live DXY / US10Y / VIX correlation
 * display with animated bias gauge and long-gate status indicator.
 */

import React, { useEffect, useState } from 'react';

// ─── Types ────────────────────────────────────────────────────────
interface MacroState {
  macroBias:    number;   // -3 … +3
  dxyBias:      number;   // -1 | 0 | +1
  us10yBias:    number;
  vixBias:      number;
  dxyNative:    boolean;
  us10yNative:  boolean;
  vixNative:    boolean;
  longsBlocked: boolean;
}

interface AppData {
  instruments: { symbol: string; price: number; bias: string; up: boolean }[];
  matrix:      { name: string; val: string; up: boolean | null }[];
  narrative:   { strategy: string; rationale: string; details: string; risk: string };
  pulse:       string[];
  stats:       { account: number; profit: number; winRate: number; latency: number };
  macro:       MacroState;
}

// ─── Macro Correlation Panel ──────────────────────────────────────
function MacroPanel({ macro }: { macro: MacroState }) {
  const biasColor =
    macro.macroBias >= 2  ? '#00ffa3' :
    macro.macroBias === 1 ? '#7fff00' :
    macro.macroBias === 0 ? '#ffcc00' :
    macro.macroBias === -1 ? '#ff9900' : '#ff3b6b';

  const biasLabel =
    macro.macroBias >= 3  ? 'EXTREME BULL' :
    macro.macroBias === 2 ? 'STRONG BULL'  :
    macro.macroBias === 1 ? 'MILD BULL'    :
    macro.macroBias === 0 ? 'NEUTRAL'      :
    macro.macroBias === -1 ? 'MILD BEAR'   :
    macro.macroBias === -2 ? 'STRONG BEAR' : 'EXTREME BEAR';

  const gaugeWidth = Math.round(((macro.macroBias + 3) / 6) * 100); // 0–100 %

  return (
    <div style={{ background: 'rgba(0,243,255,0.04)', border: '1px solid rgba(0,243,255,0.15)', borderRadius: 6, padding: '12px 14px' }}>
      <span style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.1em', color: '#80808a', display: 'block', marginBottom: 10 }}>
        Macro Correlation Engine
      </span>

      {/* DXY Row */}
      <MacroRow
        label="DXY"
        badge={macro.dxyNative ? 'NATIVE' : 'EURUSD PROXY'}
        bias={macro.dxyBias}
        bullText="WEAK USD → Au Bullish"
        bearText="STRONG USD → Au Bearish"
        neutText="Unavailable"
      />
      {/* US10Y Row */}
      <MacroRow
        label="US10Y"
        badge={macro.us10yNative ? 'NATIVE' : 'N/A'}
        bias={macro.us10yBias}
        bullText="FALLING Yields → Au Bullish"
        bearText="RISING Yields → Au Bearish"
        neutText="Unavailable — Neutral"
      />
      {/* VIX Row */}
      <MacroRow
        label="VIX"
        badge={macro.vixNative ? 'NATIVE' : 'N/A'}
        bias={macro.vixBias}
        bullText="SPIKING → Safe-Haven Au (+1)"
        bearText="CALM / Risk-On (-1)"
        neutText="Unavailable — Neutral"
      />

      {/* Bias Gauge */}
      <div style={{ marginTop: 12, marginBottom: 6 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 4 }}>
          <span style={{ fontSize: 11, color: '#80808a', fontFamily: 'monospace' }}>MACRO BIAS</span>
          <span style={{ fontSize: 14, fontWeight: 700, color: biasColor, fontFamily: 'monospace' }}>
            {macro.macroBias > 0 ? '+' : ''}{macro.macroBias} — {biasLabel}
          </span>
        </div>
        {/* Track */}
        <div style={{ background: '#1c1e24', borderRadius: 4, height: 8, overflow: 'hidden', border: '1px solid #2a2d35' }}>
          <div style={{
            height: '100%',
            width: `${gaugeWidth}%`,
            background: `linear-gradient(90deg, #ff3b6b 0%, #ffcc00 50%, #00ffa3 100%)`,
            borderRadius: 4,
            transition: 'width 0.4s ease',
          }} />
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, color: '#444', marginTop: 2, fontFamily: 'monospace' }}>
          <span>-3</span><span>-2</span><span>-1</span><span>0</span><span>+1</span><span>+2</span><span>+3</span>
        </div>
      </div>

      {/* Long Gate Status */}
      <div style={{
        marginTop: 8,
        padding: '6px 10px',
        borderRadius: 4,
        border: `1px solid ${macro.longsBlocked ? 'rgba(255,59,107,0.4)' : 'rgba(0,255,163,0.25)'}`,
        background: macro.longsBlocked ? 'rgba(255,59,107,0.08)' : 'rgba(0,255,163,0.06)',
        display: 'flex',
        alignItems: 'center',
        gap: 8,
      }}>
        <div style={{
          width: 8, height: 8, borderRadius: '50%',
          background: macro.longsBlocked ? '#ff3b6b' : (macro.macroBias >= 0 ? '#00ffa3' : '#ff9900'),
          boxShadow: `0 0 6px ${macro.longsBlocked ? '#ff3b6b' : '#00ffa3'}`,
          flexShrink: 0,
        }} />
        <span style={{ fontSize: 11, fontFamily: 'monospace', color: macro.longsBlocked ? '#ff3b6b' : (macro.macroBias >= 0 ? '#00ffa3' : '#ff9900') }}>
          {macro.longsBlocked
            ? '⛔ GOLD LONGS HARD BLOCKED  (bias ≤ −2)'
            : macro.macroBias >= 0
              ? '✔  Gold Longs ALLOWED  (bias ≥ 0)'
              : '⚠  Gold Longs RESTRICTED  (bias = −1)'}
        </span>
      </div>
    </div>
  );
}

function MacroRow({
  label, badge, bias, bullText, bearText, neutText,
}: {
  label: string; badge: string; bias: number;
  bullText: string; bearText: string; neutText: string;
}) {
  const isNeutral = bias === 0;
  const isBull    = bias > 0;
  const color     = isBull ? '#00ffa3' : isNeutral ? '#80808a' : '#ff3b6b';
  const arrow     = isBull ? '▲' : isNeutral ? '—' : '▼';
  const text      = isBull ? bullText : isNeutral ? neutText : bearText;

  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 7, fontSize: 11 }}>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        <span style={{ fontFamily: 'monospace', color: '#e0e0e0', fontWeight: 600, minWidth: 44 }}>{label}</span>
        <span style={{ fontSize: 9, background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 3, padding: '1px 5px', color: '#80808a', letterSpacing: '0.05em' }}>
          {badge}
        </span>
      </div>
      <span style={{ fontFamily: 'monospace', color, fontWeight: 600 }}>
        {arrow} {text}
      </span>
    </div>
  );
}

// ─── App ──────────────────────────────────────────────────────────
const DEFAULT_MACRO: MacroState = {
  macroBias: 0, dxyBias: 0, us10yBias: 0, vixBias: 0,
  dxyNative: false, us10yNative: false, vixNative: false,
  longsBlocked: false,
};

export default function App() {
  const [data, setData] = useState<AppData | null>(null);

  useEffect(() => {
    const fetchState = async () => {
      try {
        const res = await fetch('/api/state');
        if (res.ok) setData(await res.json());
      } catch (err) {
        console.error("Failed to fetch state:", err);
      }
    };
    fetchState();
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

  const macro: MacroState = data.macro ?? DEFAULT_MACRO;

  const handleDownload = () => window.open("/scripts/DEPLOYMENT_GUIDE.md", "_blank");

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-bg-deep text-text-primary font-sans w-full">

      {/* ── Top Nav ──────────────────────────────────────────────── */}
      <header className="h-16 bg-bg-surface border-b border-white/10 flex items-center justify-between px-6 shrink-0">
        <div className="flex flex-row items-center gap-3">
          <div className="w-8 h-8 border-2 border-accent-cyan flex items-center justify-center font-bold font-mono shadow-[0_0_10px_var(--color-accent-cyan)]">
            Ω
          </div>
          <h2 className="text-lg tracking-widest m-0">PROJECT OMNIVISION  <span style={{ color: '#00f3ff88', fontSize: 12 }}>SMC PRO V3</span></h2>
        </div>
        <div className="flex gap-4 items-center">
          {/* Live macro badge */}
          <span style={{
            fontSize: 11, fontFamily: 'monospace', padding: '2px 10px', borderRadius: 99,
            background: macro.longsBlocked ? 'rgba(255,59,107,0.12)' : 'rgba(0,255,163,0.1)',
            border: `1px solid ${macro.longsBlocked ? 'rgba(255,59,107,0.4)' : 'rgba(0,255,163,0.3)'}`,
            color: macro.longsBlocked ? '#ff3b6b' : '#00ffa3',
          }}>
            MACRO {macro.macroBias > 0 ? '+' : ''}{macro.macroBias} {macro.longsBlocked ? '⛔ AU LONGS OFF' : '✔ AU LONGS ON'}
          </span>
          <span className="text-xs text-text-secondary">SERVER: LDN-MT5-PRO</span>
          <div className="bg-[#00ffa31a] text-accent-green px-3 py-1 rounded-full text-[11px] uppercase tracking-widest border border-[#00ffa34d]">
            Autonomous: ON
          </div>
        </div>
      </header>

      {/* ── Main Grid ───────────────────────────────────────────── */}
      <main className="flex-1 grid grid-cols-1 md:grid-cols-[240px_1fr] lg:grid-cols-[260px_1fr_300px] overflow-hidden">

        {/* ── Sidebar ──────────────────────────────────────────── */}
        <aside className="bg-bg-surface border-r border-white/10 flex flex-col gap-5 p-5 overflow-y-auto hidden md:flex">

          {/* Instruments */}
          <div>
            <span className="text-[10px] uppercase text-text-secondary tracking-widest mb-3 block">Instruments</span>
            {data.instruments.map((inst, i) => (
              <div key={i} className={`p-3 border mb-2 rounded ${inst.up ? 'border-accent-cyan bg-[#00f3ff05]' : 'border-white/10 bg-white/5'}`}>
                <h4 className="text-base flex justify-between font-normal mb-0">
                  {inst.symbol}
                  <span className={inst.up ? 'text-accent-green' : 'text-accent-red'}>{inst.price.toFixed(2)}</span>
                </h4>
                <div className="mt-2 text-xs flex items-center gap-1.5">
                  <div className={`w-2 h-2 rounded-full ${inst.up ? 'bg-accent-green' : 'bg-accent-red'}`} />
                  H1 Bias: {inst.bias} ({inst.up ? '>' : '<'}200 EMA)
                </div>
              </div>
            ))}
          </div>

          {/* Macro Panel — NEW V3 */}
          <MacroPanel macro={macro} />

          {/* Strategy Learning Matrix */}
          <div>
            <span className="text-[10px] uppercase text-text-secondary tracking-widest mb-3 block">Strategy Learning Matrix</span>
            <div className="flex flex-col gap-2.5">
              {data.matrix.map((item, idx) => (
                <div key={idx} className="flex justify-between font-mono text-xs pb-2 border-b border-white/5">
                  <span>{item.name}</span>
                  <span className={item.up === true ? 'text-accent-green' : item.up === false ? 'text-accent-red' : 'text-text-primary'}>
                    {item.val}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </aside>

        {/* ── Chart View ───────────────────────────────────────── */}
        <section className="relative bg-[#08080a] chart-grid overflow-hidden min-h-[400px]">
          <div className="absolute w-full h-[2px] bg-accent-gold top-[35%] shadow-[0_0_15px_var(--color-accent-gold)] opacity-60" />
          <div className="absolute top-[35%] left-5 text-[10px] text-accent-gold mt-1">H1 200 EMA (DYNAMIC BIAS)</div>

          <div className="absolute w-full border-t border-dashed border-text-secondary top-[15%] z-10" />
          <span className="absolute right-2.5 text-[9px] text-text-secondary uppercase -mt-4 top-[15%] hidden sm:block">Buy-Side Liquidity (BSL) - Daily High</span>

          <div className="absolute w-full border-t border-dashed border-text-secondary top-[85%] z-10" />
          <span className="absolute right-2.5 text-[9px] text-text-secondary uppercase -mt-4 top-[85%] hidden sm:block">Sell-Side Liquidity (SSL) - H4 Swing Low</span>

          <div className="absolute bg-[#00f3ff26] border border-accent-cyan z-20 top-[60%] left-[10%] sm:left-[30%] w-[120px] h-[60px]" />
          <div className="absolute bg-bg-surface border border-white/10 px-2 py-1 text-[11px] text-accent-cyan font-mono shadow-[4px_4px_0_rgba(0,0,0,0.5)] z-30 top-[55%] left-[10%] sm:left-[30%]">
            Institutional OB (Bullish)
          </div>

          <div className="absolute bg-bg-surface border border-accent-gold px-2 py-1 text-[11px] text-white font-mono shadow-[4px_4px_0_rgba(0,0,0,0.5)] z-30 top-[75%] left-[40%] sm:left-[45%]">
            {data.narrative.strategy.toUpperCase()} CONFIRMED
          </div>

          <div className="absolute top-[62%] left-[35%] sm:left-[42%] w-2.5 h-2.5 bg-accent-green rounded-full shadow-[0_0_10px_var(--color-accent-green)] z-30" />

          {/* Macro block overlay — shows when longsBlocked */}
          {macro.longsBlocked && (
            <div style={{
              position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)',
              background: 'rgba(255,59,107,0.12)', border: '1px solid rgba(255,59,107,0.5)',
              borderRadius: 6, padding: '6px 18px', zIndex: 40,
              fontFamily: 'monospace', fontSize: 12, color: '#ff3b6b', letterSpacing: '0.05em',
            }}>
              ⛔ MACRO FILTER ACTIVE — ALL GOLD LONGS BLOCKED (bias {macro.macroBias})
            </div>
          )}
        </section>

        {/* ── Mentor Panel ─────────────────────────────────────── */}
        <aside className="bg-bg-surface border-l border-white/10 flex flex-col p-5 gap-5 overflow-y-auto lg:flex hidden">
          <span className="text-[10px] uppercase text-text-secondary tracking-widest">Live Agent Narrative</span>

          <div className="bg-[#14161cd9] border border-[#00f3ff33] p-4 rounded-lg flex-1 flex flex-col">
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Strategy:</strong> {data.narrative.strategy}
            </p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Rationale:</strong> {data.narrative.rationale}
            </p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">{data.narrative.details}</p>
            <p className="text-[13px] leading-relaxed text-[#ccc] mb-3">
              <strong className="text-white">Risk Advisory:</strong> {data.narrative.risk}
            </p>

            {/* Macro summary inside narrative */}
            <div style={{
              background: macro.longsBlocked ? 'rgba(255,59,107,0.06)' : 'rgba(0,243,255,0.04)',
              border: `1px solid ${macro.longsBlocked ? 'rgba(255,59,107,0.25)' : 'rgba(0,243,255,0.15)'}`,
              borderRadius: 4, padding: '8px 10px', marginBottom: 12,
            }}>
              <span style={{ display: 'block', fontSize: 9, textTransform: 'uppercase', color: '#80808a', letterSpacing: '0.1em', marginBottom: 4 }}>
                Macro Correlation
              </span>
              <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', fontFamily: 'monospace', fontSize: 11 }}>
                <span style={{ color: macro.dxyBias > 0 ? '#00ffa3' : macro.dxyBias < 0 ? '#ff3b6b' : '#80808a' }}>
                  DXY {macro.dxyBias > 0 ? '▲+1' : macro.dxyBias < 0 ? '▼-1' : '—'}
                </span>
                <span style={{ color: macro.us10yBias > 0 ? '#00ffa3' : macro.us10yBias < 0 ? '#ff3b6b' : '#80808a' }}>
                  US10Y {macro.us10yBias > 0 ? '▲+1' : macro.us10yBias < 0 ? '▼-1' : '—'}
                </span>
                <span style={{ color: macro.vixBias > 0 ? '#00ffa3' : macro.vixBias < 0 ? '#ff3b6b' : '#80808a' }}>
                  VIX {macro.vixBias > 0 ? '▲+1' : macro.vixBias < 0 ? '▼-1' : '—'}
                </span>
                <span style={{ marginLeft: 'auto', fontWeight: 700, color: macro.macroBias >= 1 ? '#00ffa3' : macro.macroBias < 0 ? '#ff3b6b' : '#ffcc00' }}>
                  Σ {macro.macroBias > 0 ? '+' : ''}{macro.macroBias}
                </span>
              </div>
            </div>

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
            <span className="text-[10px] uppercase text-accent-gold tracking-widest mb-2 block">System Pulse</span>
            <div className="text-[11px] font-mono leading-relaxed text-text-primary h-[60px] overflow-hidden">
              {data.pulse.map((line, i) => <div key={i}>{line}</div>)}
            </div>
          </div>
        </aside>
      </main>

      {/* ── Footer Stats ─────────────────────────────────────────── */}
      <footer className="h-12 bg-bg-surface border-t border-white/10 flex items-center px-6 gap-10 font-mono text-xs shrink-0 whitespace-nowrap overflow-x-auto">
        <div>
          <span className="text-text-secondary">ACCOUNT:</span>
          <b className="text-accent-cyan ml-2">
            ${data.stats.account.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
          </b>
        </div>
        <div>
          <span className="text-text-secondary">TOTAL PROFIT:</span>
          <b className={`ml-2 ${data.stats.profit >= 0 ? 'text-accent-green' : 'text-accent-red'}`}>
            {data.stats.profit >= 0 ? '+' : ''}${data.stats.profit.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
          </b>
        </div>
        <div>
          <span className="text-text-secondary">WIN RATE:</span>
          <b className="text-accent-cyan ml-2">{data.stats.winRate.toFixed(1)}%</b>
        </div>
        <div>
          <span className="text-text-secondary">MAE ADJUSTMENT:</span>
          <b className="text-accent-gold ml-2">ACTIVE</b>
        </div>
        {/* V3: macro bias in footer */}
        <div>
          <span className="text-text-secondary">MACRO BIAS:</span>
          <b style={{ color: macro.macroBias >= 1 ? '#00ffa3' : macro.macroBias < 0 ? '#ff3b6b' : '#ffcc00' }} className="ml-2">
            {macro.macroBias > 0 ? '+' : ''}{macro.macroBias} / 3
          </b>
        </div>
        <div className="ml-auto">
          <span className="text-text-secondary">LATENCY:</span>
          <b className="text-accent-cyan ml-2">{data.stats.latency}ms</b>
        </div>
      </footer>
    </div>
  );
}
