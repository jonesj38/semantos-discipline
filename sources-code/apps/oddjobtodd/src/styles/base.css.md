---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/base.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.054053+00:00
---

# apps/oddjobtodd/src/styles/base.css

```css
/* Oddjobz helm wireframes v2 — retro-future cockpit
   Neutral, cool, "5th Element / Back to the Future" — analog readouts,
   ice-blue accents, vector grids, monospace tickers, brushed chrome.
*/

@font-face {
  /* fallback only — fonts loaded via Google */
  font-family: "Space Mono Fallback";
  src: local("Menlo");
}

:root {
  /* neutral cool base */
  --void: #0d1014;          /* deep ink-blue, near black */
  --shell: #14181e;          /* main panel ground */
  --shell-2: #1a1f27;        /* raised panel */
  --shell-3: #232932;        /* highest plane */
  --rule: #2a3340;
  --rule-bright: #3a4555;
  --grid: rgba(124, 174, 213, 0.06);

  --ink: #e7eef5;            /* primary readout */
  --ink-soft: #aab6c4;
  --ink-faint: #6b7889;
  --ink-dim: #455160;

  /* the activation accent — ice cyan, like a CRT cursor */
  --activation: #7fd9ff;
  --activation-soft: rgba(127, 217, 255, 0.16);
  --activation-glow: rgba(127, 217, 255, 0.45);

  /* hold/affine — calm cool green-blue */
  --hold: #6fd6b5;
  --hold-soft: rgba(111, 214, 181, 0.14);

  /* LINEAR — warm amber rather than red. Decisive but not panicked. */
  --linear: #ffb24a;
  --linear-soft: rgba(255, 178, 74, 0.14);
  --linear-glow: rgba(255, 178, 74, 0.5);

  --display: "Space Grotesk", "Inter", system-ui, sans-serif;
  --mono: "Space Mono", "JetBrains Mono", ui-monospace, Menlo, monospace;
  --hand: "Space Grotesk", "Inter", system-ui, sans-serif;
  --sans: "Space Grotesk", "Inter", system-ui, sans-serif;
}

* { box-sizing: border-box; }
html, body {
  margin: 0;
  background: var(--void);
  color: var(--ink);
  font-family: var(--sans);
  -webkit-font-smoothing: antialiased;
}

/* ============ canvas ============ */
.canvas {
  min-height: 100vh;
  padding: 56px 48px 160px;
  background:
    /* faint vertical scanlines */
    repeating-linear-gradient(
      to bottom,
      transparent 0 3px,
      rgba(255,255,255,0.012) 3px 4px
    ),
    /* corner glows */
    radial-gradient(circle at 8% -10%, rgba(127, 217, 255, 0.08), transparent 50%),
    radial-gradient(circle at 95% 20%, rgba(111, 214, 181, 0.04), transparent 60%),
    radial-gradient(circle at 50% 110%, rgba(127, 217, 255, 0.05), transparent 60%),
    var(--void);
  position: relative;
}
.canvas::before {
  /* vector grid floor */
  content: "";
  position: fixed;
  inset: 0;
  background-image:
    linear-gradient(var(--grid) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid) 1px, transparent 1px);
  background-size: 48px 48px;
  pointer-events: none;
  z-index: 0;
  mask-image: linear-gradient(180deg, transparent 0%, #000 30%, #000 70%, transparent 100%);
  -webkit-mask-image: linear-gradient(180deg, transparent 0%, #000 30%, #000 70%, transparent 100%);
}
.canvas > * { position: relative; z-index: 1; }

/* ============ header ============ */
.canvas-header {
  max-width: 1400px;
  margin: 0 auto 56px;
  border-bottom: 1px solid var(--rule);
  padding-bottom: 32px;
  position: relative;
}
.canvas-header::after {
  content: "";
  position: absolute;
  bottom: -1px; left: 0;
  width: 120px; height: 1px;
  background: var(--activation);
  box-shadow: 0 0 12px var(--activation-glow);
}
.canvas-header .meta {
  font-family: var(--mono);
  font-size: 10.5px;
  color: var(--activation);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 10px;
  display: flex;
  align-items: center;
  gap: 10px;
}
.canvas-header .meta::before {
  content: "";
  width: 8px; height: 8px;
  border-radius: 50%;
  background: var(--activation);
  box-shadow: 0 0 8px var(--activation-glow);
  animation: pulse 2.4s ease-in-out infinite;
}
.canvas-header h1 {
  font-family: var(--display);
  font-size: 56px;
  font-weight: 300;
  margin: 0 0 4px;
  letter-spacing: -1.2px;
  line-height: 1.05;
  color: var(--ink);
}
.canvas-header h1 b {
  font-weight: 500;
  color: var(--activation);
}
.canvas-header p {
  font-family: var(--sans);
  font-size: 14px;
  color: var(--ink-soft);
  max-width: 760px;
  margin: 18px 0 0;
  line-height: 1.6;
  font-weight: 300;
}
.canvas-header p em {
  color: var(--ink);
  font-style: normal;
  font-family: var(--mono);
  font-size: 12.5px;
  letter-spacing: 0.04em;
}
.canvas-header p span[style] {
  color: var(--activation);
  font-family: var(--mono);
  font-size: 12.5px;
}

/* ============ section ============ */
.section {
  max-width: 1400px;
  margin: 0 auto 80px;
  position: relative;
}
.section-title {
  font-family: var(--display);
  font-weight: 300;
  font-size: 32px;
  margin: 0 0 6px;
  letter-spacing: -0.4px;
  color: var(--ink);
}
.section-title::first-letter,
.section-title b { color: var(--activation); }
.section-meta {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  margin-bottom: 32px;
  padding-left: 14px;
  position: relative;
}
.section-meta::before {
  content: "";
  position: absolute;
  left: 0; top: 50%;
  transform: translateY(-50%);
  width: 6px; height: 6px;
  background: var(--activation);
  transform: translateY(-50%) rotate(45deg);
}
.section-row {
  display: flex;
  flex-wrap: wrap;
  gap: 48px 36px;
  align-items: flex-start;
}

/* ============ frame card ============ */
.frame-card {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: 320px;
}
.frame-label {
  font-family: var(--display);
  font-size: 20px;
  font-weight: 400;
  line-height: 1.1;
  letter-spacing: -0.2px;
  color: var(--ink);
}
.frame-sub {
  font-family: var(--mono);
  font-size: 9.5px;
  color: var(--ink-faint);
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

/* ============ device — cockpit module ============ */
.device {
  width: 320px;
  height: 660px;
  border: 1px solid var(--rule-bright);
  border-radius: 32px;
  background:
    radial-gradient(ellipse at 50% 0%, rgba(127, 217, 255, 0.04), transparent 60%),
    linear-gradient(180deg, var(--shell-2), var(--shell));
  position: relative;
  overflow: hidden;
  box-shadow:
    0 0 0 1px rgba(255,255,255,0.02) inset,
    0 1px 0 rgba(255,255,255,0.04) inset,
    0 30px 60px -20px rgba(0,0,0,0.7),
    0 0 0 6px rgba(127, 217, 255, 0.02);
}
.device::before {
  /* speaker-grill notch */
  content: "";
  position: absolute;
  top: 10px;
  left: 50%;
  transform: translateX(-50%);
  width: 100px;
  height: 16px;
  background: var(--void);
  border-radius: 10px;
  border: 1px solid var(--rule);
  box-shadow: inset 0 0 6px rgba(0,0,0,0.6);
}
.device::after {
  /* CRT vignette + scanline overlay */
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    repeating-linear-gradient(
      to bottom,
      transparent 0 2px,
      rgba(0,0,0,0.18) 2px 3px
    ),
    radial-gradient(ellipse at center, transparent 50%, rgba(0,0,0,0.4) 100%);
  border-radius: 32px;
  mix-blend-mode: multiply;
  opacity: 0.55;
  z-index: 5;
}
.device .status {
  position: absolute;
  top: 14px;
  left: 24px;
  right: 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-family: var(--mono);
  font-size: 9.5px;
  color: var(--ink-soft);
  letter-spacing: 0.12em;
  z-index: 4;
  text-transform: uppercase;
}
.device .status .right {
  display: flex;
  gap: 4px;
  align-items: center;
}
.device .status .right .bar {
  display: inline-block;
  width: 3px;
  background: var(--ink-soft);
}
.device .status .right .bar:nth-child(1) { height: 4px; }
.device .status .right .bar:nth-child(2) { height: 6px; }
.device .status .right .bar:nth-child(3) { height: 8px; }
.device .status .right .bar:nth-child(4) { height: 10px; }

.screen {
  position: absolute;
  inset: 38px 0 0 0;
  padding: 16px 18px 96px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  z-index: 1;
}
/* faint internal grid inside each screen */
.screen::before {
  content: "";
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgba(127, 217, 255, 0.025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(127, 217, 255, 0.025) 1px, transparent 1px);
  background-size: 24px 24px;
  pointer-events: none;
  z-index: -1;
}

/* ===== primitives ===== */
.label-mono {
  font-family: var(--mono);
  font-size: 9.5px;
  letter-spacing: 0.14em;
  color: var(--ink-faint);
  text-transform: uppercase;
}
.label-mono .accent { color: var(--activation); }

.box {
  border: 1px solid var(--rule-bright);
  border-radius: 4px;
  padding: 10px 12px;
  background: var(--shell-3);
}
.box.dashed { border-style: dashed; border-color: var(--rule); color: var(--ink-soft); }

/* ===== ribbon (top bar) ===== */
.ribbon {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 2px 12px;
  border-bottom: 1px solid var(--rule);
  margin-bottom: 14px;
  position: relative;
}
.ribbon::after {
  content: "";
  position: absolute;
  bottom: -1px; left: 0;
  width: 30%; height: 1px;
  background: var(--activation);
  box-shadow: 0 0 6px var(--activation-glow);
}
.ribbon .hat {
  font-family: var(--mono);
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--ink);
  text-transform: uppercase;
  display: flex;
  align-items: center;
  gap: 8px;
}
.ribbon .hat .dot {
  display: inline-block;
  width: 6px; height: 6px;
  background: var(--hold);
  box-shadow: 0 0 4px rgba(111, 214, 181, 0.6);
}
.ribbon .signal-state {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--ink-faint);
  letter-spacing: 0.16em;
  text-transform: uppercase;
}

/* ===== anchor empty (state 1) ===== */
.anchor-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  gap: 16px;
  color: var(--ink-soft);
  padding: 20px;
}
.anchor-empty .breath {
  width: 88px; height: 88px;
  border: 1px solid var(--activation);
  border-radius: 50%;
  position: relative;
  box-shadow:
    0 0 0 4px rgba(127, 217, 255, 0.05),
    0 0 18px rgba(127, 217, 255, 0.1);
}
.anchor-empty .breath::before {
  /* crosshair ticks */
  content: "";
  position: absolute;
  inset: -10px;
  background:
    linear-gradient(90deg, var(--ink-faint) 0 1px, transparent 1px) 0 50% / 6px 1px no-repeat,
    linear-gradient(90deg, var(--ink-faint) 0 1px, transparent 1px) 100% 50% / 6px 1px no-repeat,
    linear-gradient(0deg,  var(--ink-faint) 0 1px, transparent 1px) 50% 0   / 1px 6px no-repeat,
    linear-gradient(0deg,  var(--ink-faint) 0 1px, transparent 1px) 50% 100% / 1px 6px no-repeat;
}
.anchor-empty .breath::after {
  content: "";
  position: absolute;
  inset: 18px;
  border-radius: 50%;
  background: var(--activation);
  opacity: 0.25;
  animation: breathe 4s ease-in-out infinite;
  box-shadow: 0 0 20px var(--activation-glow);
}
@keyframes breathe {
  0%, 100% { transform: scale(0.7); opacity: 0.15; }
  50% { transform: scale(1.0); opacity: 0.35; }
}
.anchor-empty .line1 {
  font-family: var(--display);
  font-weight: 300;
  font-size: 19px;
  color: var(--ink);
  letter-spacing: 0.2px;
}
.anchor-empty .nothing {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--ink-faint);
  letter-spacing: 0.22em;
  text-transform: uppercase;
}

/* ===== activation card (state 2) ===== */
.activation-card {
  border: 1px solid var(--activation);
  border-radius: 6px;
  padding: 14px;
  background:
    linear-gradient(180deg, rgba(127, 217, 255, 0.08), rgba(127, 217, 255, 0.02)),
    var(--shell-3);
  position: relative;
  box-shadow:
    0 0 0 1px rgba(127, 217, 255, 0.08),
    0 0 24px -6px var(--activation-glow);
}
.activation-card::before {
  /* corner brackets — decisive frame */
  content: "";
  position: absolute;
  top: -1px; left: -1px;
  width: 14px; height: 14px;
  border-top: 2px solid var(--activation);
  border-left: 2px solid var(--activation);
}
.activation-card::after {
  content: "";
  position: absolute;
  bottom: -1px; right: -1px;
  width: 14px; height: 14px;
  border-bottom: 2px solid var(--activation);
  border-right: 2px solid var(--activation);
}
.activation-card .reason {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--activation);
  margin-bottom: 10px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.activation-card .reason::before {
  content: "";
  width: 6px; height: 6px;
  background: var(--activation);
  box-shadow: 0 0 6px var(--activation-glow);
  animation: pulse 2.4s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.45; transform: scale(0.7); }
}
.activation-card h3 {
  font-family: var(--display);
  font-weight: 400;
  font-size: 19px;
  margin: 0 0 6px;
  line-height: 1.2;
  letter-spacing: -0.2px;
  color: var(--ink);
}
.activation-card p {
  font-family: var(--sans);
  font-size: 12px;
  color: var(--ink-soft);
  line-height: 1.5;
  margin: 0;
  font-weight: 300;
}
.activation-card .actions {
  display: flex;
  gap: 8px;
  margin-top: 14px;
  font-family: var(--mono);
  font-size: 9.5px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}
.activation-card .actions .walk {
  flex: 1;
  text-align: center;
  border: 1px solid var(--activation);
  background: rgba(127, 217, 255, 0.1);
  color: var(--activation);
  border-radius: 4px;
  padding: 9px;
}
.activation-card .actions .dismiss {
  flex: 0 0 auto;
  padding: 9px 12px;
  color: var(--ink-faint);
  border: 1px solid var(--rule);
  border-radius: 4px;
}

/* ===== sentence grammar ===== */
.sentence {
  padding: 10px 4px;
  font-family: var(--display);
  font-weight: 300;
  font-size: 19px;
  line-height: 1.7;
  color: var(--ink-faint);
  letter-spacing: 0.1px;
}
.sentence .slot {
  display: inline-block;
  border-bottom: 1px solid var(--ink-dim);
  min-width: 70px;
  padding: 1px 6px 0;
  margin: 0 2px;
  color: var(--ink-dim);
  position: relative;
  font-family: var(--mono);
  font-size: 14px;
  letter-spacing: 0.02em;
}
.sentence .slot.filled {
  color: var(--ink);
  border-bottom: 1px solid var(--hold);
  background: var(--hold-soft);
}
.sentence .slot.live {
  color: var(--activation);
  border-bottom: 1px solid var(--activation);
  background: var(--activation-soft);
  box-shadow: 0 0 12px -2px var(--activation-glow);
  animation: live 1.6s ease-in-out infinite;
}
@keyframes live {
  0%, 100% { background: var(--activation-soft); }
  50% { background: rgba(127, 217, 255, 0.28); }
}
.sentence .slot .tag {
  display: block;
  font-family: var(--mono);
  font-size: 8px;
  color: var(--ink-faint);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-top: -3px;
  font-weight: 400;
}
.sentence .slot.filled .tag { color: var(--hold); }
.sentence .slot.live .tag { color: var(--activation); }

/* ===== transcript ===== */
.transcript {
  border: 1px solid var(--rule-bright);
  border-radius: 4px;
  padding: 12px;
  margin-top: 12px;
  background: rgba(13, 16, 20, 0.5);
  position: relative;
}
.transcript::before {
  /* CRT corner light */
  content: "";
  position: absolute;
  top: 8px; right: 10px;
  width: 6px; height: 6px;
  border-radius: 50%;
  background: var(--linear);
  box-shadow: 0 0 8px var(--linear-glow);
  animation: pulse 1.4s ease-in-out infinite;
}
.transcript .hdr {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.18em;
  color: var(--ink-faint);
  text-transform: uppercase;
  margin-bottom: 8px;
}
.transcript .body {
  font-family: var(--mono);
  font-size: 13px;
  line-height: 1.5;
  color: var(--ink);
}
.transcript .body .interim {
  color: var(--ink-faint);
}
.transcript .body .interim::after {
  content: "▍";
  color: var(--linear);
  animation: caret 0.8s steps(2) infinite;
  margin-left: 1px;
}
@keyframes caret { 50% { opacity: 0; } }

/* ===== mic FAB / variants ===== */
.mic-fab {
  position: absolute;
  right: 22px;
  bottom: 100px;
  width: 56px; height: 56px;
  border-radius: 50%;
  background:
    radial-gradient(circle at 30% 30%, var(--shell-3), var(--void));
  border: 1px solid var(--activation);
  color: var(--activation);
  display: grid;
  place-items: center;
  font-family: var(--mono);
  font-size: 18px;
  z-index: 4;
  box-shadow:
    0 0 0 1px rgba(127, 217, 255, 0.1),
    0 0 24px -6px var(--activation-glow),
    0 8px 16px -4px rgba(0,0,0,0.6);
}
.mic-fab.live {
  border-color: var(--linear);
  color: var(--linear);
  box-shadow:
    0 0 0 1px rgba(255, 178, 74, 0.2),
    0 0 28px -4px var(--linear-glow);
  animation: pulse 1.4s ease-in-out infinite;
}
.mic-fab.edge {
  right: 50%;
  transform: translateX(50%);
  bottom: 102px;
  width: 110px;
  height: 14px;
  border-radius: 7px;
  background: transparent;
  border: 1px dashed var(--ink-dim);
  color: var(--ink-faint);
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  box-shadow: none;
}
.mic-fab.hidden { display: none; }
.mic-fab.bar {
  right: 14px; left: 14px; bottom: 100px;
  width: auto;
  height: 40px;
  border-radius: 4px;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  background:
    linear-gradient(180deg, var(--shell-3), var(--shell-2));
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  color: var(--activation);
}
.mic-fab.bar::before {
  content: "◉";
  color: var(--linear);
}

/* ===== dock — 4-node ===== */
.dock {
  position: absolute;
  left: 14px;
  right: 14px;
  bottom: 18px;
  border: 1px solid var(--rule-bright);
  border-radius: 6px;
  background:
    linear-gradient(180deg, var(--shell-3), var(--shell-2));
  padding: 10px 6px;
  display: flex;
  justify-content: space-around;
  align-items: center;
  z-index: 3;
  box-shadow:
    0 0 0 1px rgba(255,255,255,0.02) inset,
    0 -10px 30px -10px rgba(0,0,0,0.6);
}
.dock::before {
  /* top edge highlight */
  content: "";
  position: absolute;
  top: 0; left: 10px; right: 10px;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--rule-bright), transparent);
}
.dock .node {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 5px;
  font-family: var(--mono);
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.16em;
  flex: 1;
  position: relative;
  padding: 3px 0;
  text-transform: uppercase;
}
.dock .node .glyph {
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 4px;
  border: 1px solid var(--ink-dim);
  font-family: var(--mono);
  font-size: 14px;
  color: var(--ink-soft);
  background: var(--void);
  transition: all 0.25s ease;
  position: relative;
}
.dock .node.active {
  color: var(--ink);
}
.dock .node.active .glyph {
  background: var(--ink);
  color: var(--void);
  border-color: var(--ink);
  box-shadow: 0 0 0 1px var(--ink) inset;
}
.dock .node.activated .glyph {
  border-color: var(--activation);
  background: var(--activation-soft);
  color: var(--activation);
  box-shadow:
    0 0 0 1px var(--activation) inset,
    0 0 14px -2px var(--activation-glow);
}
.dock .node.activated::before {
  content: "";
  position: absolute;
  top: -2px; right: 32%;
  width: 6px; height: 6px;
  background: var(--activation);
  border-radius: 50%;
  box-shadow: 0 0 8px var(--activation-glow);
}
.dock .node.activated { color: var(--activation); }

/* dock — 8-tab */
.dock.eight { padding: 8px 6px; }
.dock.eight .dock-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 6px 2px;
  width: 100%;
}
.dock.eight .node { font-size: 7.5px; }
.dock.eight .node .glyph { width: 24px; height: 24px; font-size: 12px; }

/* ===== attention list rows ===== */
.attn-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 12px;
}
.attn-list .row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border: 1px solid var(--rule);
  border-radius: 4px;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink-soft);
  background: var(--shell-3);
}
.attn-list .row .dot {
  width: 5px; height: 5px;
  background: var(--ink-dim);
  flex: 0 0 auto;
}
.attn-list .row.live .dot {
  background: var(--activation);
  box-shadow: 0 0 6px var(--activation-glow);
}
.attn-list .row .meta {
  margin-left: auto;
  font-family: var(--mono);
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

/* ===== thumb-mode option list ===== */
.node-options {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 10px;
}
.node-options .opt {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 11px 12px;
  border: 1px solid var(--rule);
  border-radius: 4px;
  font-family: var(--mono);
  font-size: 12px;
  color: var(--ink-soft);
  background: var(--shell-3);
}
.node-options .opt .check {
  width: 12px; height: 12px;
  border: 1px solid var(--ink-dim);
  flex: 0 0 auto;
}
.node-options .opt.selected {
  border-color: var(--activation);
  color: var(--ink);
  background: var(--activation-soft);
  box-shadow: 0 0 12px -4px var(--activation-glow);
}
.node-options .opt.selected .check {
  background: var(--activation);
  border-color: var(--activation);
  box-shadow: 0 0 6px var(--activation-glow);
}
.node-options .opt .meta {
  margin-left: auto;
  font-family: var(--mono);
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.14em;
}

/* ===== LINEAR gate ===== */
.gate {
  margin-top: auto;
  border: 1px solid var(--linear);
  border-radius: 6px;
  padding: 14px;
  background:
    linear-gradient(180deg, rgba(255, 178, 74, 0.06), rgba(255, 178, 74, 0.01)),
    var(--shell-2);
  position: relative;
  box-shadow:
    0 0 0 1px rgba(255, 178, 74, 0.08),
    0 0 20px -8px var(--linear-glow);
}
.gate::before, .gate::after {
  /* warning corner bracket */
  content: "";
  position: absolute;
  width: 14px; height: 14px;
}
.gate::before {
  top: -1px; left: -1px;
  border-top: 2px solid var(--linear);
  border-left: 2px solid var(--linear);
}
.gate::after {
  bottom: -1px; right: -1px;
  border-bottom: 2px solid var(--linear);
  border-right: 2px solid var(--linear);
}
.gate .gate-hdr {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--linear);
  text-transform: uppercase;
  margin-bottom: 10px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.gate .gate-hdr::before {
  content: "◆";
  color: var(--linear);
}
.gate .summary {
  font-family: var(--mono);
  font-size: 12px;
  line-height: 1.5;
  margin-bottom: 12px;
  color: var(--ink-soft);
}
.gate .summary b {
  color: var(--linear);
  font-weight: 500;
}

/* hold */
.gate-hold {
  position: relative;
  border: 1px solid var(--linear);
  border-radius: 4px;
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--linear);
  overflow: hidden;
  background: var(--void);
}
.gate-hold .ring {
  position: absolute;
  left: 0; top: 0; bottom: 0;
  width: 60%;
  background:
    linear-gradient(90deg, var(--linear-soft), rgba(255, 178, 74, 0.32));
  box-shadow: inset 0 0 16px var(--linear-glow);
}
.gate-hold .ring::after {
  /* leading edge */
  content: "";
  position: absolute;
  right: 0; top: 0; bottom: 0;
  width: 1px;
  background: var(--linear);
  box-shadow: 0 0 6px var(--linear-glow);
}
.gate-hold span { position: relative; z-index: 1; }

/* slide */
.gate-slide {
  position: relative;
  border: 1px solid var(--linear);
  border-radius: 4px;
  height: 56px;
  display: flex;
  align-items: center;
  padding: 0 6px;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--linear);
  background: var(--void);
}
.gate-slide .knob {
  width: 44px; height: 44px;
  border-radius: 4px;
  background: var(--linear);
  color: var(--void);
  display: grid; place-items: center;
  font-family: var(--mono);
  font-size: 18px;
  margin-right: 12px;
  box-shadow: 0 0 12px -2px var(--linear-glow);
}
.gate-slide .track-text { flex: 1; text-align: center; opacity: 0.7; padding-right: 44px; }

/* twostep */
.gate-twostep {
  display: flex;
  gap: 8px;
}
.gate-twostep .arm,
.gate-twostep .commit {
  flex: 1;
  border: 1px solid var(--linear);
  border-radius: 4px;
  height: 48px;
  display: grid; place-items: center;
  font-family: var(--mono);
  font-size: 9.5px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}
.gate-twostep .arm.on {
  background: var(--linear);
  color: var(--void);
  box-shadow: 0 0 14px -2px var(--linear-glow);
}
.gate-twostep .commit {
  color: var(--ink-dim);
  border-style: dashed;
}
.gate-twostep .arm.on + .commit {
  color: var(--linear);
  border-style: solid;
}

/* shift */
.gate-shift {
  border: 1px solid var(--linear);
  border-radius: 4px;
  padding: 16px;
  background:
    linear-gradient(180deg, var(--linear), rgb(220 145 50));
  color: var(--void);
  text-align: center;
  font-family: var(--display);
  font-weight: 500;
  font-size: 16px;
  letter-spacing: 0.02em;
  box-shadow: 0 0 18px -4px var(--linear-glow);
}
.gate-shift small {
  display: block;
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  opacity: 0.75;
  margin-top: 4px;
  font-weight: 400;
}

/* ===== artifact (state 6) ===== */
.artifact {
  border: 1px solid var(--rule-bright);
  border-radius: 6px;
  padding: 14px;
  background:
    linear-gradient(180deg, rgba(111, 214, 181, 0.04), transparent 30%),
    var(--shell-3);
  position: relative;
}
.artifact::before {
  content: "";
  position: absolute;
  top: -1px; left: -1px;
  width: 14px; height: 14px;
  border-top: 2px solid var(--hold);
  border-left: 2px solid var(--hold);
}
.artifact::after {
  content: "";
  position: absolute;
  bottom: -1px; right: -1px;
  width: 14px; height: 14px;
  border-bottom: 2px solid var(--hold);
  border-right: 2px solid var(--hold);
}
.artifact .stamp {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--hold);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.artifact .stamp::before {
  content: "✓";
  width: 14px; height: 14px;
  border: 1px solid var(--hold);
  border-radius: 50%;
  display: grid; place-items: center;
  font-size: 9px;
  color: var(--hold);
}
.artifact h4 {
  font-family: var(--display);
  font-weight: 400;
  font-size: 18px;
  margin: 0 0 8px;
  color: var(--ink);
  letter-spacing: -0.1px;
}
.artifact .row {
  display: flex;
  justify-content: space-between;
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  padding: 6px 0;
  border-top: 1px solid var(--rule);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.artifact .row:first-of-type { border-top: none; }
.artifact .row b {
  color: var(--ink);
  font-weight: 500;
}

/* FSM ladder */
.fsm {
  margin-top: 10px;
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 3px;
}
.fsm .step {
  height: 6px;
  background: var(--rule);
  border-radius: 1px;
}
.fsm .step.done { background: var(--hold); box-shadow: 0 0 4px rgba(111, 214, 181, 0.5); }
.fsm .step.now { background: var(--activation); box-shadow: 0 0 8px var(--activation-glow); animation: pulse 1.4s ease-in-out infinite; }
.fsm-label {
  font-family: var(--mono);
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-top: 6px;
  display: flex;
  justify-content: space-between;
}

/* ===== topo tag ===== */
.topo-tag {
  position: absolute;
  top: -10px;
  right: 14px;
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.2em;
  background: var(--void);
  color: var(--activation);
  padding: 3px 8px;
  border: 1px solid var(--activation);
  border-radius: 2px;
  text-transform: uppercase;
  z-index: 6;
  box-shadow: 0 0 10px -2px var(--activation-glow);
}

/* ===== annotation ===== */
.annot {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-family: var(--sans);
  font-weight: 300;
  font-size: 12.5px;
  color: var(--ink-soft);
  max-width: 280px;
  line-height: 1.55;
  padding-left: 14px;
  border-left: 1px solid var(--rule);
}
.annot .arrow {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--activation);
  letter-spacing: 0.2em;
  text-transform: uppercase;
}

/* ===== legend ===== */
.legend {
  max-width: 1400px;
  margin: 80px auto 0;
  padding: 32px;
  border: 1px solid var(--rule);
  border-radius: 6px;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 20px 36px;
  background:
    linear-gradient(180deg, var(--shell-2), var(--shell));
  position: relative;
}
.legend::before, .legend::after {
  content: "";
  position: absolute;
  width: 14px; height: 14px;
}
.legend::before {
  top: -1px; left: -1px;
  border-top: 1px solid var(--activation);
  border-left: 1px solid var(--activation);
}
.legend::after {
  bottom: -1px; right: -1px;
  border-bottom: 1px solid var(--activation);
  border-right: 1px solid var(--activation);
}
.legend h4 {
  font-family: var(--display);
  font-weight: 400;
  font-size: 18px;
  margin: 0 0 6px;
  color: var(--ink);
  grid-column: 1 / -1;
  border-bottom: 1px solid var(--rule);
  padding-bottom: 12px;
}
.legend .item {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  font-family: var(--sans);
  font-weight: 300;
  font-size: 12px;
  color: var(--ink-soft);
  line-height: 1.5;
}
.legend .item b {
  font-family: var(--mono);
  font-size: 10.5px;
  color: var(--ink);
  letter-spacing: 0.06em;
  font-weight: 500;
  text-transform: uppercase;
  display: block;
  margin-bottom: 2px;
}
.legend .swatch {
  flex: 0 0 auto;
  width: 18px; height: 18px;
  border-radius: 2px;
  border: 1px solid var(--rule-bright);
  margin-top: 1px;
}
.legend .swatch.activation {
  background: var(--activation-soft);
  border-color: var(--activation);
  box-shadow: 0 0 8px -2px var(--activation-glow);
}
.legend .swatch.linear {
  background: var(--linear-soft);
  border-color: var(--linear);
  box-shadow: 0 0 8px -2px var(--linear-glow);
}
.legend .swatch.hold {
  background: var(--hold-soft);
  border-color: var(--hold);
}
.legend .swatch.ink {
  background: var(--ink);
  border-color: var(--ink);
}
.legend .swatch.dashed {
  background: transparent;
  border-style: dashed;
  border-color: var(--ink-dim);
}

/* ===== footer ===== */
.footer-note {
  max-width: 1400px;
  margin: 48px auto 0;
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  text-align: center;
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 20px;
}
.footer-note span { display: flex; align-items: center; gap: 8px; }
.footer-note span::before {
  content: "";
  width: 4px; height: 4px;
  background: var(--activation);
  box-shadow: 0 0 4px var(--activation-glow);
}

/* hide on tweak */
.hide { display: none !important; }

```
