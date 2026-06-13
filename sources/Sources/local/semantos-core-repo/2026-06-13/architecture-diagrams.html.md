---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/architecture-diagrams.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.308540+00:00
---

# architecture-diagrams.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos Core — Architecture Diagrams</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.6.1/mermaid.min.js"></script>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#08101f;
  --bg-card:#0e1929;
  --bg-nav:#070e1c;
  --border:#172035;
  --border-hi:#1e2f4a;
  --text:#c4d4e8;
  --text-muted:#5a7294;
  --text-bright:#eef4ff;
  --core:#a78bfa;
  --runtime:#60a5fa;
  --ext:#34d399;
  --apps:#fbbf24;
  --plat:#f87171;
  --accent:#22d3ee;
  --accent2:#0891b2;
  --font:'Inter',-apple-system,'Segoe UI',sans-serif;
  --mono:'JetBrains Mono','Fira Code','Cascadia Code',monospace;
}
html{scroll-behavior:smooth}
body{font-family:var(--font);background:var(--bg);color:var(--text);display:flex;min-height:100vh;line-height:1.6}

/* ── SIDEBAR ── */
#sidebar{
  width:272px;min-width:272px;background:var(--bg-nav);
  border-right:1px solid var(--border);
  position:fixed;top:0;left:0;bottom:0;
  overflow-y:auto;z-index:100;
  display:flex;flex-direction:column;
}
.sb-header{
  padding:24px 20px 20px;
  border-bottom:1px solid var(--border);
  background:linear-gradient(160deg,#060d1c 0%,#0a1528 100%);
}
.sb-eyebrow{
  font-size:10px;font-weight:700;letter-spacing:.18em;
  text-transform:uppercase;color:var(--accent);margin-bottom:8px;
}
.sb-title{font-size:17px;font-weight:800;color:var(--text-bright);line-height:1.3;letter-spacing:-.01em}
.sb-sub{font-size:11px;color:var(--text-muted);margin-top:5px}

.sb-nav{padding:10px 0 24px;flex:1}
.sb-group-label{
  font-size:9.5px;font-weight:700;letter-spacing:.14em;
  text-transform:uppercase;color:var(--text-muted);
  padding:12px 18px 4px;
}
.nav-item{
  display:flex;align-items:center;gap:10px;
  padding:8px 18px;cursor:pointer;
  text-decoration:none;color:inherit;
  border-left:2px solid transparent;
  transition:all .15s ease;
}
.nav-item:hover{background:rgba(255,255,255,.035);color:var(--text-bright)}
.nav-item.active{background:rgba(34,211,238,.07);border-left-color:var(--accent);color:var(--text-bright)}
.nav-num{font-family:var(--mono);font-size:10.5px;color:var(--accent);font-weight:700;min-width:18px}
.nav-label{font-size:12px;font-weight:500;line-height:1.3;flex:1}
.ntag{
  font-size:9px;font-weight:700;padding:2px 6px;
  border-radius:3px;white-space:nowrap;margin-left:auto;
}
.nt-kernel{background:rgba(167,139,250,.15);color:var(--core)}
.nt-runtime{background:rgba(96,165,250,.15);color:var(--runtime)}
.nt-chain{background:rgba(251,191,36,.15);color:var(--apps)}
.nt-net{background:rgba(34,211,238,.15);color:var(--accent)}
.nt-app{background:rgba(52,211,153,.15);color:var(--ext)}
.nt-sys{background:rgba(248,113,113,.15);color:var(--plat)}

/* ── MAIN ── */
#main{margin-left:272px;flex:1;min-width:0}

/* ── HERO ── */
.hero{
  padding:56px 52px 48px;
  background:linear-gradient(135deg,#060d1c 0%,#08132a 60%,#05111e 100%);
  border-bottom:1px solid var(--border);
  position:relative;overflow:hidden;
}
.hero::before{
  content:'';position:absolute;top:-120px;right:-80px;
  width:560px;height:560px;
  background:radial-gradient(circle,rgba(167,139,250,.07) 0%,transparent 65%);
  pointer-events:none;
}
.hero::after{
  content:'';position:absolute;bottom:-100px;left:30%;
  width:400px;height:400px;
  background:radial-gradient(circle,rgba(34,211,238,.04) 0%,transparent 65%);
  pointer-events:none;
}
.hero-eyebrow{
  font-size:10.5px;font-weight:700;letter-spacing:.18em;
  text-transform:uppercase;color:var(--accent);margin-bottom:14px;
}
.hero-title{
  font-size:38px;font-weight:900;color:var(--text-bright);
  line-height:1.1;letter-spacing:-.025em;margin-bottom:14px;
}
.hero-title .grad{
  background:linear-gradient(90deg,var(--accent) 0%,var(--core) 100%);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;
}
.hero-desc{font-size:14.5px;color:var(--text-muted);max-width:620px;line-height:1.75}

.tier-legend{display:flex;gap:10px;margin-top:28px;flex-wrap:wrap}
.t-pill{
  display:flex;align-items:center;gap:7px;
  padding:5px 12px;border-radius:20px;
  font-size:11px;font-weight:600;border:1px solid;
}
.t-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}

.stats-bar{
  display:flex;border-bottom:1px solid var(--border);
  background:rgba(255,255,255,.015);
}
.stat-item{
  flex:1;padding:16px 20px;text-align:center;
  border-right:1px solid var(--border);
}
.stat-item:last-child{border-right:none}
.stat-val{font-family:var(--mono);font-size:22px;font-weight:700;color:var(--accent);line-height:1}
.stat-label{font-size:10.5px;color:var(--text-muted);margin-top:4px;letter-spacing:.04em}

/* ── DIAGRAM SECTIONS ── */
.diag-section{padding:44px 52px;border-bottom:1px solid var(--border)}
.diag-section:last-child{border-bottom:none}

.sec-header{display:flex;align-items:flex-start;gap:18px;margin-bottom:20px}
.sec-num{
  font-family:var(--mono);font-size:12px;font-weight:700;
  color:var(--accent);background:rgba(34,211,238,.08);
  border:1px solid rgba(34,211,238,.2);padding:4px 10px;
  border-radius:6px;white-space:nowrap;margin-top:2px;
}
.sec-title{font-size:22px;font-weight:800;color:var(--text-bright);letter-spacing:-.015em;margin-bottom:6px}
.sec-desc{font-size:13.5px;color:var(--text-muted);line-height:1.7;max-width:740px}
.sec-desc code{
  font-family:var(--mono);font-size:12px;
  background:rgba(255,255,255,.07);padding:1px 6px;border-radius:4px;color:var(--text);
}

.facts{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}
.fact{
  font-family:var(--mono);font-size:10.5px;
  padding:3px 10px;background:rgba(255,255,255,.04);
  border:1px solid var(--border-hi);border-radius:4px;color:var(--text-muted);
}
.fact b{color:var(--text)}

/* diagram card */
.dcard{
  background:var(--bg-card);border:1px solid var(--border);
  border-radius:12px;overflow:hidden;
}
.dcard-toolbar{
  display:flex;align-items:center;justify-content:space-between;
  padding:9px 14px;border-bottom:1px solid var(--border);
  background:rgba(255,255,255,.02);
}
.tb-dots{display:flex;gap:5px}
.tb-dot{width:9px;height:9px;border-radius:50%}
.dcard-type{font-family:var(--mono);font-size:9.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--text-muted)}
.dcard-inner{padding:28px 32px;overflow-x:auto}

/* mermaid reset */
.mermaid{display:flex;justify-content:center;width:100%}
.mermaid svg{max-width:100%;height:auto!important}

/* ── CELL MAP ── */
.cellmap{font-family:var(--mono);font-size:11px;width:100%}
.cm-label{
  font-size:9.5px;font-weight:700;letter-spacing:.12em;
  text-transform:uppercase;margin-bottom:5px;padding-left:2px;
}
.cm-row{display:flex;height:52px;border-radius:5px;overflow:hidden;border:1px solid rgba(255,255,255,.07);margin-bottom:10px}
.cm-field{
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  padding:4px 6px;text-align:center;cursor:default;
  border-right:1px solid rgba(0,0,0,.3);transition:filter .15s,transform .1s;
  position:relative;min-width:0;overflow:hidden;
}
.cm-field:last-child{border-right:none}
.cm-field:hover{filter:brightness(1.35);z-index:1}
.cm-field .fn{font-size:9.5px;font-weight:700;color:rgba(255,255,255,.92);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.cm-field .fs{font-size:8.5px;color:rgba(255,255,255,.45);margin-top:2px;white-space:nowrap}
.cm-row2{display:flex;height:40px;border-radius:5px;overflow:hidden;border:1px solid rgba(255,255,255,.07);margin-bottom:10px}
.cm-cont{display:flex;gap:6px;margin-top:6px}
.cm-citem{
  flex:1;height:42px;border-radius:5px;display:flex;flex-direction:column;
  align-items:center;justify-content:center;border:1px solid rgba(255,255,255,.07);
  font-family:var(--mono);font-size:9.5px;cursor:default;transition:filter .15s;
}
.cm-citem:hover{filter:brightness(1.4)}
.cm-citem .cfn{font-weight:700;color:rgba(255,255,255,.9)}
.cm-citem .cfs{font-size:8px;color:rgba(255,255,255,.45);margin-top:2px}

.cm-legend{display:flex;gap:10px;flex-wrap:wrap;margin-top:14px}
.cm-leg-item{display:flex;align-items:center;gap:6px;font-size:10.5px;color:var(--text-muted)}
.cm-leg-swatch{width:10px;height:10px;border-radius:2px;flex-shrink:0}

/* linearity cards */
.lin-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:24px}
.lin-card{
  padding:16px;border-radius:8px;border:1px solid;
  font-family:var(--mono);font-size:11.5px;
}
.lin-card .lc-head{font-size:13px;font-weight:700;margin-bottom:6px}
.lin-card .lc-ops{font-size:10px;margin-bottom:6px;opacity:.7}
.lin-card .lc-use{font-size:10.5px;opacity:.8;line-height:1.5}

/* scrollbar */
::-webkit-scrollbar{width:5px;height:5px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--border-hi);border-radius:3px}
::-webkit-scrollbar-thumb:hover{background:#253d5e}
</style>
</head>
<body>

<!-- ═══════════════════ SIDEBAR ═══════════════════ -->
<aside id="sidebar">
  <div class="sb-header">
    <div class="sb-eyebrow">Semantos Core</div>
    <div class="sb-title">Architecture<br>Reference</div>
    <div class="sb-sub">15 system diagrams · 5 tiers</div>
  </div>
  <nav class="sb-nav">
    <div class="sb-group-label">System Overview</div>
    <a class="nav-item" href="#s1"><span class="nav-num">01</span><span class="nav-label">System Layer Architecture</span><span class="ntag nt-sys">LAYERS</span></a>
    <a class="nav-item" href="#s2"><span class="nav-num">02</span><span class="nav-label">Cell Wire Format</span><span class="ntag nt-kernel">KERNEL</span></a>
    <div class="sb-group-label">Core Kernel</div>
    <a class="nav-item" href="#s3"><span class="nav-num">03</span><span class="nav-label">Linearity Type System</span><span class="ntag nt-kernel">KERNEL</span></a>
    <a class="nav-item" href="#s4"><span class="nav-num">04</span><span class="nav-label">Pipeline Phases &amp; Hash Chain</span><span class="ntag nt-kernel">KERNEL</span></a>
    <a class="nav-item" href="#s6"><span class="nav-num">06</span><span class="nav-label">2-PDA Cell Engine</span><span class="ntag nt-kernel">KERNEL</span></a>
    <a class="nav-item" href="#s7"><span class="nav-num">07</span><span class="nav-label">Pask Learning Kernel</span><span class="ntag nt-kernel">KERNEL</span></a>
    <div class="sb-group-label">Compilation &amp; Storage</div>
    <a class="nav-item" href="#s5"><span class="nav-num">05</span><span class="nav-label">Compilation Pipeline</span><span class="ntag nt-runtime">PIPELINE</span></a>
    <a class="nav-item" href="#s8"><span class="nav-num">08</span><span class="nav-label">Semantic Object &amp; Patches</span><span class="ntag nt-runtime">STORAGE</span></a>
    <a class="nav-item" href="#s13"><span class="nav-num">13</span><span class="nav-label">Content Store &amp; Release</span><span class="ntag nt-runtime">INFRA</span></a>
    <div class="sb-group-label">Identity &amp; Chain</div>
    <a class="nav-item" href="#s9"><span class="nav-num">09</span><span class="nav-label">Identity Architecture</span><span class="ntag nt-app">IDENTITY</span></a>
    <a class="nav-item" href="#s10"><span class="nav-num">10</span><span class="nav-label">BSV Blockchain Integration</span><span class="ntag nt-chain">CHAIN</span></a>
    <div class="sb-group-label">Runtime &amp; Applications</div>
    <a class="nav-item" href="#s14"><span class="nav-num">14</span><span class="nav-label">Runtime Services Layer</span><span class="ntag nt-runtime">RUNTIME</span></a>
    <a class="nav-item" href="#s11"><span class="nav-num">11</span><span class="nav-label">Cross-Vertical Dispatch</span><span class="ntag nt-app">APPS</span></a>
    <a class="nav-item" href="#s12"><span class="nav-num">12</span><span class="nav-label">Federation &amp; Relay Protocol</span><span class="ntag nt-net">NETWORK</span></a>
    <a class="nav-item" href="#s15"><span class="nav-num">15</span><span class="nav-label">End-to-End Flow</span><span class="ntag nt-app">E2E</span></a>
  </nav>
</aside>

<!-- ═══════════════════ MAIN ═══════════════════ -->
<main id="main">

  <!-- HERO -->
  <div class="hero">
    <div class="hero-eyebrow">Technical Architecture · May 2026</div>
    <h1 class="hero-title"><span class="grad">Semantos Core</span><br>Architecture Diagrams</h1>
    <p class="hero-desc">
      Fifteen architectural diagrams derived from codebase and textbook exploration.
      Covers the five-tier layer model, 1024-byte cell wire format, linearity type system,
      compilation pipeline, BSV blockchain integration, and end-to-end application flow.
    </p>
    <div class="tier-legend">
      <div class="t-pill" style="border-color:rgba(167,139,250,.35);background:rgba(167,139,250,.06)">
        <span class="t-dot" style="background:var(--core)"></span>
        <span style="color:var(--core)">Tier 0 · CORE</span>
      </div>
      <div class="t-pill" style="border-color:rgba(96,165,250,.35);background:rgba(96,165,250,.06)">
        <span class="t-dot" style="background:var(--runtime)"></span>
        <span style="color:var(--runtime)">Tier 1 · RUNTIME</span>
      </div>
      <div class="t-pill" style="border-color:rgba(52,211,153,.35);background:rgba(52,211,153,.06)">
        <span class="t-dot" style="background:var(--ext)"></span>
        <span style="color:var(--ext)">Tier 2 · EXTENSIONS</span>
      </div>
      <div class="t-pill" style="border-color:rgba(251,191,36,.35);background:rgba(251,191,36,.06)">
        <span class="t-dot" style="background:var(--apps)"></span>
        <span style="color:var(--apps)">Tier 3 · APPS</span>
      </div>
      <div class="t-pill" style="border-color:rgba(248,113,113,.35);background:rgba(248,113,113,.06)">
        <span class="t-dot" style="background:var(--plat)"></span>
        <span style="color:var(--plat)">Tier 4 · PLATFORMS</span>
      </div>
    </div>
  </div>

  <!-- STATS BAR -->
  <div class="stats-bar">
    <div class="stat-item"><div class="stat-val">5</div><div class="stat-label">Architecture Tiers</div></div>
    <div class="stat-item"><div class="stat-val">1024</div><div class="stat-label">Bytes per Cell</div></div>
    <div class="stat-item"><div class="stat-val">4</div><div class="stat-label">Linearity Classes</div></div>
    <div class="stat-item"><div class="stat-val">8</div><div class="stat-label">Pipeline Phases</div></div>
    <div class="stat-item"><div class="stat-val">29</div><div class="stat-label">WASM Exports</div></div>
    <div class="stat-item"><div class="stat-val">15</div><div class="stat-label">Diagrams</div></div>
  </div>

  <!-- ─────────────── DIAGRAM 1 ─────────────── -->
  <section class="diag-section" id="s1">
    <div class="sec-header">
      <span class="sec-num">01</span>
      <div>
        <h2 class="sec-title">System Layer Architecture</h2>
        <p class="sec-desc">Five tiers with strictly enforced unidirectional imports. Arrows flow downward only — APPS may import from EXT and RUNTIME, but never the reverse. The import boundary gate runs on every CI build at <code>tests/gates/import-boundaries.test.ts</code>.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>5</b> Tiers</span>
      <span class="fact"><b>Unidirectional</b> imports enforced</span>
      <span class="fact"><b>Import gate</b> on every build</span>
      <span class="fact"><b>14+</b> Core packages</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">graph TB · 5-tier dependency model</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','secondaryColor':'#1a2840','tertiaryColor':'#0d1631','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
graph TB
    subgraph APPS["⬡  APPS — Tier 3  ·  Standalone Products"]
        A1[oddjobtodd\nTrades vertical]
        A2[property-mgmt\nProperty vertical]
        A3[loom\nWorkbench shell]
        A4[demo-collab\nVersioning demo]
        A5[poker-agent\nGame app]
    end
    subgraph EXT["⬡  EXTENSIONS — Tier 2  ·  Domain Algorithms"]
        E1[policy-runtime\nOpcode evaluator]
        E2[cdm\nISDA CDM lifecycle]
        E3[extraction\n5-stage ETL pipeline]
        E4[chain-broadcast\nBSV tx builder]
        E5[metering\nPayment-channel FSM]
        E6[oddjobz\nJob/task domain]
        E7[navigator\nType-driven routing]
        E8[calendar\nBooking/scheduling]
    end
    subgraph RUNTIME["⬡  RUNTIME — Tier 1  ·  Entry Surfaces"]
        R1[shell\nCLI/REPL + Lisp compiler]
        R2[node\nDaemon + admin API]
        R3[services\nRenderer-agnostic stores]
        R4[session-protocol\nMulti-party FSM]
        R5[peer-locator\nBCA to endpoint]
        R6[ws-node-adapter\nFederation WSS]
        R7[intent\nNLU pipeline]
        R8[world-beam\nElixir bridge]
    end
    subgraph CORE["⬡  CORE — Tier 0  ·  Kernel Foundation"]
        C1[cell-engine\nZig WASM 2-PDA VM]
        C2[pask\nZig WASM learning kernel]
        C3[pask-and-cell\nCombined WASM build]
        C4[protocol-types\nBridge + storage interfaces]
        C5[cell-ops\nTS cell operations]
        C6[semantic-objects\nAppend-only patch substrate]
        C7[semantos-ir\nANF intermediate repr]
        C8[semantos-sir\nSemantic IR + jural types]
        C9[identity-ports\nPort-based DI surface]
        C10[plexus-contracts\nBRC-52/BRC-42 types]
        C11[plexus-vendor-sdk\nIdentity DAG + key derivation]
        C12[state\nReactive cell primitives]
        C13[constants\nProtocol constants codegen]
        C14[world-sdk\nRelay client + cell DAG]
    end
    subgraph PLAT["⬡  PLATFORMS — Tier 4  ·  Target Environments"]
        P1[browser\nWASM embedded profile]
        P2[node.js\nNative WASM profile]
        P3[esp32\nEmbedded hardware]
    end
    APPS --> EXT
    APPS --> RUNTIME
    EXT --> RUNTIME
    EXT --> CORE
    RUNTIME --> CORE
    CORE --> PLAT
    style APPS fill:#1c1508,stroke:#fbbf24,color:#fbbf24
    style EXT fill:#061510,stroke:#34d399,color:#34d399
    style RUNTIME fill:#07101e,stroke:#60a5fa,color:#60a5fa
    style CORE fill:#0f0a1c,stroke:#a78bfa,color:#a78bfa
    style PLAT fill:#1c0808,stroke:#f87171,color:#f87171
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 2 ─────────────── -->
  <section class="diag-section" id="s2">
    <div class="sec-header">
      <span class="sec-num">02</span>
      <div>
        <h2 class="sec-title">Cell Wire Format — 1024 bytes</h2>
        <p class="sec-desc">Every semantic object is ultimately a 1024-byte cell. The 256-byte header is the engine's enforcement surface — read-only after packing (K7). The 768-byte payload carries domain-specific content. Continuation cells extend the structure for SPV proofs, BEEF ancestry, and state snapshots.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>1024</b> bytes total</span>
      <span class="fact"><b>256</b> byte header</span>
      <span class="fact"><b>768</b> byte payload</span>
      <span class="fact"><b>K7</b> header immutable after pack</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">custom · byte-layout memory map</span>
      </div>
      <div class="dcard-inner">
        <div class="cellmap">
          <!-- Full 1024-byte proportional bar -->
          <div class="cm-label" style="color:#22d3ee">Cell 0 — 1024 bytes</div>
          <div class="cm-row" style="margin-bottom:16px">
            <div class="cm-field" style="flex:256;background:linear-gradient(135deg,#1a0f33,#271545)">
              <span class="fn" style="color:#a78bfa">HEADER</span>
              <span class="fs">256 bytes · offsets 0–255</span>
            </div>
            <div class="cm-field" style="flex:768;background:linear-gradient(135deg,#0d1f12,#102817)">
              <span class="fn" style="color:#34d399">SEMANTIC PAYLOAD</span>
              <span class="fs">768 bytes · offsets 256–1023</span>
            </div>
          </div>

          <!-- Header fields detail -->
          <div class="cm-label" style="color:#a78bfa">Header Fields (256 bytes)</div>
          <div class="cm-row">
            <div class="cm-field" title="Magic: DE AD BE EF CA FE BA BE 13 37 13 37 42 42 42 42" style="flex:16;background:#1a1030">
              <span class="fn">Magic</span><span class="fs">16 b</span>
            </div>
            <div class="cm-field" title="Linearity: 0=LINEAR 1=AFFINE 2=RELEVANT 3=UNRESTRICTED" style="flex:4;background:#0f1a2a">
              <span class="fn">Lin</span><span class="fs">4 b</span>
            </div>
            <div class="cm-field" title="Version: monotonic state counter" style="flex:4;background:#0f1a2a">
              <span class="fn">Ver</span><span class="fs">4 b</span>
            </div>
            <div class="cm-field" title="DomainFlag: §4.5 protocol domain" style="flex:4;background:#0f1a2a">
              <span class="fn">Dom</span><span class="fs">4 b</span>
            </div>
            <div class="cm-field" title="RefCount: uint16 LE reference count" style="flex:2;background:#0f1a2a">
              <span class="fn">RC</span><span class="fs">2 b</span>
            </div>
            <div class="cm-field" title="TypeHash: SHA-256(whatPath:howSlug:instPath)" style="flex:32;background:#1a2a0f">
              <span class="fn">TypeHash</span><span class="fs">32 b · SHA-256</span>
            </div>
            <div class="cm-field" title="OwnerID: BCA-derived identifier" style="flex:16;background:#1a2a0f">
              <span class="fn">OwnerID</span><span class="fs">16 b</span>
            </div>
            <div class="cm-field" title="Timestamp: ms since Unix epoch, uint64 LE" style="flex:8;background:#0f1a2a">
              <span class="fn">Time</span><span class="fs">8 b</span>
            </div>
            <div class="cm-field" title="CellCount: total cells incl. continuations" style="flex:4;background:#0f1a2a">
              <span class="fn">Cnt</span><span class="fs">4 b</span>
            </div>
            <div class="cm-field" title="PayloadSize: bytes in Cell 0 payload (max 768)" style="flex:4;background:#0f1a2a">
              <span class="fn">PSize</span><span class="fs">4 b</span>
            </div>
            <div class="cm-field" title="Phase: 0x00–0x07 pipeline stage" style="flex:1;background:#2a1a0f">
              <span class="fn">Ph</span><span class="fs">1 b</span>
            </div>
            <div class="cm-field" title="Dimension: 0x00=composite 0x01=WHAT 0x02=HOW 0x03=INST" style="flex:1;background:#2a1a0f">
              <span class="fn">Dim</span><span class="fs">1 b</span>
            </div>
            <div class="cm-field" title="ParentHash: SHA-256 of parent cell (structural — tree position)" style="flex:32;background:#1a2a0f">
              <span class="fn">ParentHash</span><span class="fs">32 b · SHA-256</span>
            </div>
            <div class="cm-field" title="PrevStateHash: SHA-256 of previous state (temporal — hash chain K6)" style="flex:32;background:#1a2a0f">
              <span class="fn">PrevStateHash</span><span class="fs">32 b · SHA-256</span>
            </div>
            <div class="cm-field" title="Reserved: zero-padded for forward compat" style="flex:96;background:#101518">
              <span class="fn" style="opacity:.6">Reserved</span><span class="fs" style="opacity:.5">96 b · zero-padded</span>
            </div>
          </div>

          <!-- Payload -->
          <div class="cm-label" style="color:#34d399;margin-top:12px">Payload (768 bytes)</div>
          <div class="cm-row2">
            <div class="cm-field" style="flex:1;background:linear-gradient(135deg,#061510,#0c1f14)">
              <span class="fn" style="color:#34d399">Domain-specific content</span>
              <span class="fs">zero-padded if shorter than 768 bytes</span>
            </div>
          </div>

          <!-- Continuation cells -->
          <div class="cm-label" style="color:#fbbf24;margin-top:12px">Continuation Cells (1024 bytes each · optional)</div>
          <div class="cm-cont">
            <div class="cm-citem" style="background:#1c1408">
              <span class="cfn" style="color:#fbbf24">BUMP · 0x01</span>
              <span class="cfs">Bitcoin UTXO merkle proof</span>
            </div>
            <div class="cm-citem" style="background:#1c1408">
              <span class="cfn" style="color:#fbbf24">ATOMIC_BEEF · 0x02</span>
              <span class="cfs">SPV ancestry proof</span>
            </div>
            <div class="cm-citem" style="background:#1c1408">
              <span class="cfn" style="color:#fbbf24">ENVELOPE · 0x03</span>
              <span class="cfs">Multi-cell container</span>
            </div>
            <div class="cm-citem" style="background:#1c1408">
              <span class="cfn" style="color:#fbbf24">STATE · 0x05</span>
              <span class="cfs">Mutable state snapshot</span>
            </div>
          </div>

          <!-- Legend -->
          <div class="cm-legend">
            <div class="cm-leg-item"><span class="cm-leg-swatch" style="background:#1a1030"></span>Identity / Magic</div>
            <div class="cm-leg-item"><span class="cm-leg-swatch" style="background:#0f1a2a"></span>Control / State</div>
            <div class="cm-leg-item"><span class="cm-leg-swatch" style="background:#1a2a0f"></span>Cryptographic hashes</div>
            <div class="cm-leg-item"><span class="cm-leg-swatch" style="background:#2a1a0f"></span>Phase / Dimension</div>
            <div class="cm-leg-item"><span class="cm-leg-swatch" style="background:#101518"></span>Reserved</div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 3 ─────────────── -->
  <section class="diag-section" id="s3">
    <div class="sec-header">
      <span class="sec-num">03</span>
      <div>
        <h2 class="sec-title">Linearity Type System &amp; Kernel Invariants</h2>
        <p class="sec-desc">Four linearity classes govern how values may be used: LINEAR enforces exactly-once consumption, AFFINE at-most-once, RELEVANT at-least-once, UNRESTRICTED unconstrained. These classes are enforced at the VM level through dedicated opcodes (0xC0–0xCF) and proved correct via Lean4 proofs.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>4</b> Linearity classes</span>
      <span class="fact"><b>K1–K7</b> Kernel invariants</span>
      <span class="fact"><b>5</b> Enforcement opcodes</span>
      <span class="fact"><b>Lean4</b> formal proofs</span>
    </div>
    <!-- Visual linearity cards -->
    <div class="lin-grid" style="margin-bottom:24px">
      <div class="lin-card" style="border-color:rgba(248,113,113,.4);background:rgba(248,113,113,.05)">
        <div class="lc-head" style="color:#f87171">LINEAR (0) — Exactly once</div>
        <div class="lc-ops" style="color:#f87171">DUP ✗  DROP ✗</div>
        <div class="lc-use">Use for: capability UTXOs, payment-channel states, action decisions</div>
      </div>
      <div class="lin-card" style="border-color:rgba(251,191,36,.4);background:rgba(251,191,36,.05)">
        <div class="lc-head" style="color:#fbbf24">AFFINE (1) — At most once</div>
        <div class="lc-ops" style="color:#fbbf24">DUP ✗  DROP ✓</div>
        <div class="lc-use">Use for: transfer records, proof-of-custody, draft inspection reports</div>
      </div>
      <div class="lin-card" style="border-color:rgba(52,211,153,.4);background:rgba(52,211,153,.05)">
        <div class="lc-head" style="color:#34d399">RELEVANT (2) — At least once</div>
        <div class="lc-ops" style="color:#34d399">DUP ✓  DROP ✗</div>
        <div class="lc-use">Use for: certificates, schema definitions, taxonomy nodes</div>
      </div>
      <div class="lin-card" style="border-color:rgba(148,163,184,.3);background:rgba(148,163,184,.04)">
        <div class="lc-head" style="color:#94a3b8">UNRESTRICTED (3) — No constraint</div>
        <div class="lc-ops" style="color:#94a3b8">DUP ✓  DROP ✓</div>
        <div class="lc-use">Use for: scratch data, temporary working values</div>
      </div>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">graph LR · invariants + opcode enforcement</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
graph LR
    subgraph Invariants["Kernel Invariants (K1–K9)"]
        K1["K1 — Linearity\nLINEAR cell consumed exactly once\nProof: LinearityK1.lean"]
        K4["K4 — Failure Atomicity\nOn any violation, full PDA state\nrolls back byte-for-byte"]
        K6["K6 — Hash-chain Integrity\nPrevStateHash is append-only\nTLA+ model-checked"]
        K7["K7 — Cell Immutability\n256-byte header read-only after pack\nProof: CellImmutabilityK7.lean"]
        K9["K9 — Temporal Morphism\nHash chains compose under projection\nEnables selective-disclosure proofs"]
    end
    subgraph Opcodes["Enforcement Opcodes (0xC0–0xCF)"]
        OP0["OP_CHECKLINEARTYPE\n0xC0  ·  reads header offset 16"]
        OP5["OP_ASSERTLINEAR\n0xC5  ·  aborts if already consumed"]
        OP6["OP_CHECKDOMAINFLAG\n0xC6  ·  reads header offset 24"]
        OP7["OP_VERIFYVERSION\n0xC7  ·  reads PrevStateHash offset 128"]
        OP9["OP_ASSERTPHASE\n0xC9  ·  reads Phase byte offset 94"]
    end
    K1 --> K4
    K7 --> K1
    K6 --> K9
    K1 --> OP0
    K1 --> OP5
    K7 --> OP6
    K6 --> OP7
    style Invariants fill:#0f0a1c,stroke:#a78bfa
    style Opcodes fill:#0d1631,stroke:#60a5fa
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 4 ─────────────── -->
  <section class="diag-section" id="s4">
    <div class="sec-header">
      <span class="sec-num">04</span>
      <div>
        <h2 class="sec-title">Pipeline Phases &amp; Hash Chain</h2>
        <p class="sec-desc">Eight pipeline phases form a compression gradient from raw evidence (0x00 source) through to verified outcome (0x07 outcome). Each state transition extends the append-only hash chain (Invariant K6): the new state hash is SHA-256 of the previous hash concatenated with the delta bytes.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>8</b> Phases: 0x00–0x07</span>
      <span class="fact"><b>K6</b> append-only hash chain</span>
      <span class="fact"><b>Phase byte</b> at header offset 94</span>
      <span class="fact"><b>TLA+</b> model-checked</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart LR · compression gradient + hash chain</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart LR
    subgraph Chain["K6 Hash Chain — append-only"]
        direction TB
        S0["State 0 — genesis\nprevStateHash = 0x00×32\nstateHash = SHA-256(cell_bytes)"]
        S1["State 1\nprevStateHash = stateHash_0\nstateHash = SHA-256(cell_v2)"]
        S2["State N\nprevStateHash = stateHash_N-1"]
        S0 -->|"SHA-256(state_0) == state_1.prev"| S1
        S1 -->|"SHA-256(state_1) == state_N.prev"| S2
    end
    subgraph Phases["Compression Gradient — Phase byte at header offset 94"]
        direction TB
        PH0["0x00  source\nRELEVANT  ·  raw evidence — audit log"]
        PH1["0x01  parse\nLINEAR  ·  extraction result — one consumer"]
        PH2["0x02  ast\nAFFINE  ·  accumulated state — may be dropped"]
        PH3["0x03  typecheck\nRELEVANT  ·  classification scores — many readers"]
        PH4["0x04  optimise\nLINEAR  ·  optimisation result — one consumer"]
        PH5["0x05  codegen\nRELEVANT  ·  instrument — inspectable post-emit"]
        PH6["0x06  action\nLINEAR  ·  operator decision — consumed once"]
        PH7["0x07  outcome\nRELEVANT  ·  diagnostic feedback — many readers"]
        PH0 --> PH1 --> PH2 --> PH3 --> PH4 --> PH5 --> PH6 --> PH7
    end
    style Chain fill:#0d1631,stroke:#22d3ee
    style Phases fill:#0f0a1c,stroke:#a78bfa
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 5 ─────────────── -->
  <section class="diag-section" id="s5">
    <div class="sec-header">
      <span class="sec-num">05</span>
      <div>
        <h2 class="sec-title">Compilation Pipeline: Natural Language → 2-PDA Bytecode</h2>
        <p class="sec-desc">Natural language traverses six layers: Intent (NLU embedding + taxonomy), Lisp surface (SExpression parser), optional Semantic IR (trust-tier enforcement), OIR/ANF lowering (eliminates evaluation-order ambiguity), bytecode emission, then execution in the Zig WASM kernel. The SIR path adds governance context and jural-category annotation.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>NLU → Bytecode</b> 6 pipeline stages</span>
      <span class="fact"><b>ANF</b> intermediate representation</span>
      <span class="fact"><b>Opcodes</b> 0x4C–0xD0</span>
      <span class="fact"><b>BRC-52</b> authority gate (SIR)</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TD · NL to kernel execution</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TD
    NL["Natural language input\ne.g. 'book a carpenter for next Tuesday'"]
    subgraph IntentLayer["Intent Layer  ·  runtime/intent/"]
        EMB["EmbeddingService\ntext → vector"]
        TAX["TaxonomyCoherence\nvector → taxonomy path"]
        CONF["Confidence Calibration\nthreshold + fallback"]
        EMB --> TAX --> CONF
    end
    subgraph LispLayer["Lisp Surface  ·  runtime/shell/src/lisp/"]
        PARSER["Parser\ntext → SExpression parse tree"]
        INTERP["interpretConstraint()\nSExpression → ConstraintExpr (AST)"]
        PARSER --> INTERP
    end
    subgraph SIRLayer["Semantic IR  ·  core/semantos-sir/"]
        CSIR["compileToSIR()\nwrap with neutral GovernanceContext\n(trustClass, proofRequirement,\nexecutionAuthority, linearity)"]
        LSIR["lowerSIR()\ntrust-tier enforcement\nD-A6 BRC-52-anchored authority gate\nJuralCategory annotation"]
        CSIR --> LSIR
    end
    subgraph OIRLayer["OIR / ANF  ·  core/semantos-ir/"]
        LOWER["lower()\nConstraintExpr → IRProgram\nAdministrative Normal Form —\neliminates evaluation-order ambiguity"]
        EMIT["emit()\nIRProgram → Uint8Array\nopcodes 0x4C–0xD0"]
        LOWER --> EMIT
    end
    subgraph KernelLayer["2-PDA Cell Engine  ·  core/cell-engine — Zig WASM"]
        LOAD["kernel_load_script(ptr, len)"]
        EXEC["kernel_execute()"]
        RESULT["PolicyResult\n{ ok, stack, error?, anchorEvents? }"]
        LOAD --> EXEC --> RESULT
    end
    NL --> IntentLayer
    IntentLayer --> LispLayer
    INTERP -->|"Phase 3 (future): SIR path"| CSIR
    INTERP -->|"Active today: direct path"| LOWER
    LSIR --> LOWER
    EMIT --> LOAD
    style IntentLayer fill:#061510,stroke:#34d399
    style LispLayer fill:#07101e,stroke:#60a5fa
    style SIRLayer fill:#1c1205,stroke:#fbbf24
    style OIRLayer fill:#1a0808,stroke:#f87171
    style KernelLayer fill:#0f0a1c,stroke:#a78bfa
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 6 ─────────────── -->
  <section class="diag-section" id="s6">
    <div class="sec-header">
      <span class="sec-num">06</span>
      <div>
        <h2 class="sec-title">2-PDA Cell Engine</h2>
        <p class="sec-desc">The kernel is a Two-Stack Push-Down Automaton compiled to WASM in Zig. It ships in two profiles: a full 185 KB build with native crypto, and a lean 29 KB embedded build for browser and IoT that uses host-provided crypto via WASM imports. Every cell entering the machine passes through the invariant gate (K1–K7) before reaching the stack.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>Zig → WASM</b></span>
      <span class="fact"><b>185 KB</b> full / <b>29 KB</b> embedded</span>
      <span class="fact"><b>29</b> WASM exports</span>
      <span class="fact"><b>Main stack</b> 1024 cells / <b>Aux stack</b> 256 cells</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TB · WASM profiles + PDA + enforcement</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TB
    subgraph WASM["Zig WASM — Two Profiles"]
        direction LR
        subgraph Full["Full (185 KB)"]
            F1["Native crypto\nSHA-256, RIPEMD-160\nsecp256k1"]
            F2["SPV verification"]
        end
        subgraph Embed["Embedded (29 KB)"]
            E1["Host-provided crypto\nvia WASM imports"]
            E2["Browser / IoT\nfriendly"]
        end
    end
    subgraph PDA["Two-Stack Push-Down Automaton"]
        direction TB
        MS["Main Stack\n1024 cells max\n(values being operated on)"]
        AS["Auxiliary Stack\n256 cells max\n(BUMP, BEEF, ENVELOPE continuations)"]
    end
    subgraph Gate["Invariant Gate (K1–K7)"]
        G1["Magic check  ·  bytes 0–15\nfast-path rejection"]
        G2["Linearity check  ·  offset 16\nK1 enforcement"]
        G3["Phase assert  ·  offset 94\nOP_ASSERTPHASE"]
        G4["Domain check  ·  offset 24\nOP_CHECKDOMAINFLAG"]
        G5["PrevStateHash  ·  offset 128\nOP_VERIFYVERSION"]
        G6["Consumption tracking\nmark consumed → K4 rollback on re-use"]
    end
    subgraph HC["OP_CALLHOST Dispatch"]
        HCR["HostCallRecord\n{ opcode, payload }\n→ domain handler\n(CDM lifecycle, SCADA valve,\noddjob workflow, ...)"]
    end
    subgraph Exports["29 WASM Exports"]
        EX1["kernel_load_script(ptr, len)"]
        EX2["kernel_execute()"]
        EX3["kernel_get_result(ptr)"]
        EX4["kernel_set_enforcement(flag)"]
        EX5["cell_pack(profile, ptr)"]
        EX6["bca_derive(ptr)"]
        EX7["spv_verify(ptr)"]
    end
    WASM --> PDA
    PDA --> Gate
    Gate --> HC
    WASM --> Exports
    style WASM fill:#0f0a1c,stroke:#a78bfa
    style PDA fill:#0d1631,stroke:#60a5fa
    style Gate fill:#061510,stroke:#34d399
    style HC fill:#07101e,stroke:#60a5fa
    style Exports fill:#0f0a1c,stroke:#a78bfa
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 7 ─────────────── -->
  <section class="diag-section" id="s7">
    <div class="sec-header">
      <span class="sec-num">07</span>
      <div>
        <h2 class="sec-title">Pask Learning Kernel</h2>
        <p class="sec-desc">A deterministic associative learning kernel compiled to WASM in Zig. Nodes and edges live in a ~18 MB static memory arena — no heap allocation. The determinism guarantee means identical input streams produce bit-identical snapshots, enabling audit, replay, and cross-node migration. In <code>pask-and-cell</code> mode, both kernels share a single 42 KB WASM with zero-copy inter-kernel calls.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>~18 MB</b> static memory</span>
      <span class="fact"><b>16k</b> nodes / <b>32k</b> edges</span>
      <span class="fact"><b>Deterministic</b> — no host clock reads</span>
      <span class="fact"><b>42 KB</b> combined pask-and-cell</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart LR · config → interaction → determinism → deploy</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart LR
    subgraph Config["Config  ·  src/config.zig"]
        CF1["propagation_depth: 1–3 hops"]
        CF2["stability_epsilon: 0.01"]
        CF3["stability_window_ms: 60,000"]
        CF4["min_interactions: 5"]
        CF5["learning_rate: 0.1"]
        CF6["prune_threshold: -0.3"]
    end
    subgraph Memory["Static Memory (~18 MB)"]
        M1["Nodes  ·  max 16k\n{ name, constraint_strength, delta_H }"]
        M2["Edges  ·  max 32k\n{ from, to, co_occurrence_weight }"]
        M3["Stable-threads  ·  { node_id, last_stable_at }"]
        M4["Delta-ring  ·  64k entries\nrolling stability window"]
    end
    subgraph Interact["interact(event) flow"]
        I1["Upsert node"]
        I2["Update edge weights\nedge.weight += learning_rate"]
        I3["Propagate ΔH\n1–3 hops depth-first"]
        I4["Accumulate ΔH\nin rolling delta-ring"]
        I5["Stability check\nif |ΔH| ≤ epsilon → mark stable"]
        I6["Prune pass\ncount < min_interactions\nor strength < threshold"]
        I1 --> I2 --> I3 --> I4 --> I5 --> I6
    end
    subgraph Det["Determinism Guarantee"]
        D1["WASM never reads host clock\nnow_ms is caller-supplied"]
        D2["Identical input stream\n→ bit-identical snapshots"]
        D3["Enables: audit, replay,\ncross-node migration"]
    end
    subgraph Modes["Deployment Modes"]
        MO1["Sibling mode\ntwo WASMs, two memories"]
        MO2["pask-and-cell\nsingle WASM, shared memory\nzero-copy inter-kernel calls  ·  42 KB"]
    end
    Config --> Interact
    Memory --> Interact
    Interact --> Det
    Det --> Modes
    style Config fill:#0d1631,stroke:#60a5fa
    style Memory fill:#0f0a1c,stroke:#a78bfa
    style Interact fill:#061510,stroke:#34d399
    style Det fill:#07101e,stroke:#22d3ee
    style Modes fill:#1c1205,stroke:#fbbf24
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 8 ─────────────── -->
  <section class="diag-section" id="s8">
    <div class="sec-header">
      <span class="sec-num">08</span>
      <div>
        <h2 class="sec-title">Semantic Object &amp; Patch Substrate</h2>
        <p class="sec-desc">The <code>core/semantic-objects</code> package implements an append-only event-sourced substrate via four Drizzle ORM tables. Patches are never updated or deleted — the hash chain (K6) makes any tampering detectable. Concurrent writes use optimistic locking on <code>current_state_hash</code>, returning a <code>StaleStateHashError</code> on conflict.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>4</b> Drizzle tables</span>
      <span class="fact"><b>Append-only</b> patch stream</span>
      <span class="fact"><b>Optimistic concurrency</b> via state hash</span>
      <span class="fact"><b>K6</b> tamper-evident chain</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TD · schema + ops + concurrency + hash chain</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TD
    subgraph Schema["Four Drizzle Tables"]
        T1["sem_objects\naggregates — one row per thing\n{ id, objectKind, current_state_hash,\ncurrent_version, payload, created_by_cert_id }"]
        T2["sem_object_patches\nappend-only changelog\n{ id, object_id, kind, delta,\nprev_state_hash, new_state_hash,\nlexicon, facet_id, facet_capabilities }"]
        T3["sem_object_states\noptional snapshots for expensive folds"]
        T4["sem_participants\naccess list\n{ cert_id, role, joined_at, left_at }"]
    end
    subgraph Ops["Key Operations"]
        OP1["createObject()\nassign genesis stateHash"]
        OP2["appendPatch(db, {\n  objectId, kind, delta,\n  expectedPrevStateHash,\n  lexicon, facetId\n})"]
        OP3["listPatches(objectId)"]
        OP4["foldState(objectId, reducer)"]
    end
    subgraph Conc["Optimistic Concurrency"]
        OC1["WHERE current_state_hash = expected"]
        OC2{"0 rows affected?"}
        OC3["StaleStateHashError → retry"]
        OC4["Success → update hash + version"]
        OC1 --> OC2
        OC2 -->|yes| OC3
        OC2 -->|no| OC4
    end
    subgraph SH["Hash Chain (K6)"]
        SH1["new_hash = SHA-256(prev_hash + delta_bytes)"]
        SH2["Append-only — no UPDATE, no DELETE"]
        SH3["Tamper-evident — any bit flip breaks chain"]
    end
    Schema --> Ops
    OP2 --> Conc
    Conc --> SH
    style Schema fill:#0d1631,stroke:#60a5fa
    style Ops fill:#061510,stroke:#34d399
    style Conc fill:#1c1205,stroke:#fbbf24
    style SH fill:#0f0a1c,stroke:#a78bfa
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 9 ─────────────── -->
  <section class="diag-section" id="s9">
    <div class="sec-header">
      <span class="sec-num">09</span>
      <div>
        <h2 class="sec-title">Identity Architecture (BRC-52 / BRC-42 / Plexus DAG)</h2>
        <p class="sec-desc">Identity is accessed exclusively through port-based dependency injection, enabling test doubles without touching production code. The Plexus Vendor SDK implements BRC-42 hierarchical key derivation and ECDH edge establishment — raw private keys are never stored. Certificates are content-addressed via SHA-256 of their JSON representation.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>BRC-52</b> certificates</span>
      <span class="fact"><b>BRC-42</b> key derivation</span>
      <span class="fact"><b>secp256k1</b> 33-byte compressed</span>
      <span class="fact"><b>ECDH</b> edge establishment</span>
      <span class="fact"><b>BRC-100</b> signed bundles</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TB · ports → SDK → certs → ECDH → bundles</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TB
    subgraph Ports["Port-Based DI  ·  core/identity-ports"]
        IP["identityPort\nregisterIdentity()  resolveIdentity()\nderiveChild()  createEdge()  querySubtree()"]
        RP["recoveryPort\ninitiateRecovery()  submitChallenge()"]
        AP["attestationPort\nattest SPV()  verifyAttestable()"]
        CP["capabilityPort\ncheckCapability()  tokenIsValid()"]
    end
    subgraph Bind["Binding (at boot)"]
        BIND["identityPort.bind(impl)\nTest: stub adapter\nProduction: VendorSDK adapter"]
    end
    subgraph SDK["core/plexus-vendor-sdk"]
        VS["VendorSDK\nbun:sqlite persistence\nBRC-42 hierarchical key derivation\nECDH edge establishment\nNEVER stores raw private keys"]
    end
    subgraph Cert["BRC-52 Certificate"]
        CERT["Brc52Cert\n  publicKey: 33-byte compressed secp256k1\n  email?: root identity\n  parentCertId?: BRC-42 parent\n  childIndex?: BKDS invoice number\n  resourceId?: semantic resource\n  domainFlag?: governance domain"]
        CERTID["certId = SHA-256(JSON.stringify(\n  { public_key, parent_cert_id,\n    child_index, email, resource_id }\n))"]
    end
    subgraph ECDH["Edge Establishment"]
        E1["Alice cert A + Bob cert B"]
        E2["shared = DH(Alice.private, Bob.public)"]
        E3["Store only signingKeyIndex\nNever store raw secret"]
        E4["Re-derive locally when needed"]
        E1 --> E2 --> E3 --> E4
    end
    subgraph SB["Signed Bundle (BRC-100)"]
        SBD["SignedBundle\n  headers: { IDENTITY_KEY, NONCE, TIMESTAMP, SIGNATURE }\n  payload: Uint8Array (CBOR)"]
    end
    Ports --> Bind
    Bind --> SDK
    SDK --> Cert
    Cert --> ECDH
    ECDH --> SB
    style Ports fill:#0d1631,stroke:#60a5fa
    style Bind fill:#061510,stroke:#34d399
    style SDK fill:#0f0a1c,stroke:#a78bfa
    style Cert fill:#07101e,stroke:#22d3ee
    style ECDH fill:#1c1205,stroke:#fbbf24
    style SB fill:#1a0808,stroke:#f87171
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 10 ─────────────── -->
  <section class="diag-section" id="s10">
    <div class="sec-header">
      <span class="sec-num">10</span>
      <div>
        <h2 class="sec-title">BSV Blockchain Integration</h2>
        <p class="sec-desc">Cells are anchored on BSV mainnet via the <code>chain-broadcast</code> extension. The UTXO model enables parallel transaction processing — a key scaling advantage over account-based chains. SPV verification requires only 80-byte block headers and a Merkle path, making it viable on IoT and low-power devices. Domain flags map directly to BRC-43 protocolIDs for SDK interop.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>UTXO</b> parallel processing</span>
      <span class="fact"><b>SPV</b> 80-byte block headers only</span>
      <span class="fact"><b>BEEF</b> format (continuation cells)</span>
      <span class="fact"><b>BRC-43</b> protocolID mapping</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart LR · cells → chain-broadcast → BEEF → SPV</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart LR
    subgraph Cells["Cells"]
        C1["Cell (1024 bytes)\nlinearity type\ndomain flag\ntype hash\npayload"]
    end
    subgraph CB["extensions/chain-broadcast"]
        CTB["CellTxBuilder\ncell → BSV transaction\nOP_RETURN or covenant output"]
        MAPI["MapiBroadcaster (injectable)\nMAP Protocol / ARC broadcast\nreturns txid + MAPI response"]
        CTM["ChainTipManager\ndedup against latest block"]
        BEEF_S["BeefStore\nBEEF format persistence\nSPV proof + tx ancestry"]
        CTB --> MAPI --> CTM --> BEEF_S
    end
    subgraph BSVArch["BSV Architecture"]
        UTXO["UTXO Model\nparallel tx processing\nvs account-based: sequential"]
        SPV["SPV Verification\n80-byte block headers only\nMerkle path for tx inclusion\nIoT / low-power compatible"]
        SCALE["Teranode\nterabyte-scale blocks\nmicroservices architecture\nIPv6 multicast propagation"]
    end
    subgraph BEEF["BEEF / SPV Proof"]
        B1["BUMP merkle proof\ncontinuation cell 0x01"]
        B2["Atomic BEEF\ntx ancestry\ncontinuation cell 0x02"]
        B3["State envelope\ncontinuation cell 0x03"]
        B1 -->|"verify first (fail-fast)"| B2
        B2 -->|"verify ancestry"| B3
    end
    subgraph DF["Domain Flags → BRC-43 protocolID"]
        DF1["0x01  EDGE_CREATION"]
        DF2["0x02  SIGNING"]
        DF3["0x03  ENCRYPTION"]
        DF4["0x04  MESSAGING"]
        DF5["0x05  ATTESTATION"]
        DF6["0x0B  HOST_EXEC"]
    end
    Cells --> CTB
    CB --> BEEF
    BEEF --> SPV
    BSVArch --> CB
    DF --> CTB
    style Cells fill:#0f0a1c,stroke:#a78bfa
    style CB fill:#1c1205,stroke:#fbbf24
    style BSVArch fill:#0d1631,stroke:#60a5fa
    style BEEF fill:#1a0808,stroke:#f87171
    style DF fill:#061510,stroke:#34d399
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 11 ─────────────── -->
  <section class="diag-section" id="s11">
    <div class="sec-header">
      <span class="sec-num">11</span>
      <div>
        <h2 class="sec-title">Cross-Vertical Dispatch Model</h2>
        <p class="sec-desc">The Trades (OddJobTodd) and Property Management verticals share a single semantic object as a dispatch envelope. Each party writes to their own facet — identified by BCA — and the Policy Engine enforces per-role visibility. AFFINE patches are hidden from wrong-facet readers; RELEVANT patches flow to all. Three storage evolution phases progress toward BSV overlay in V3.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>Trades + Property</b> verticals</span>
      <span class="fact"><b>Faceted</b> patch visibility</span>
      <span class="fact"><b>3-phase</b> storage evolution</span>
      <span class="fact"><b>BCA</b> facet provenance</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TD · shared envelope + policy + storage evolution</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TD
    subgraph Trades["Trades Vertical (OddJobTodd)"]
        T1["Job object\nLINEAR during work\nAFFINE on completion"]
        T2["ROM estimate\nauto-pricing policy"]
        T3["Completion photos + invoice"]
    end
    subgraph Prop["Property Vertical"]
        PM1["MaintenanceRequest\nAFFINE → RELEVANT on dispatch"]
        PM2["Owner approval\nbelow threshold: auto\nabove: notify + wait"]
        PM3["Tenant status view\nread-only RELEVANT patches"]
    end
    subgraph Env["Dispatch Envelope (Shared Semantic Object)"]
        ENV["RELEVANT object\nboth verticals reference\nsame objectId"]
        PMP1["PM Facet — RELEVANT: address, description,\nphotos, urgency, contacts"]
        PMP2["PM Facet — AFFINE (PM-only): owner details,\nlease info, cost expectations, internal notes"]
        TP1["Tradie Facet — RELEVANT: ROM estimate,\nquote, schedule, completion photos, invoice"]
        TP2["Tradie Facet — AFFINE (tradie-only):\ninternal cost calcs, margin notes"]
        TV1["Tenant Facet — RELEVANT read-only:\nstatus updates only"]
        OV1["Owner Facet — RELEVANT:\napprove/reject cost"]
    end
    subgraph PE["Policy Engine"]
        PE1["filterState(role)\nstrips hidden fields\nredacts AFFINE from wrong facet"]
        PE2["checkContributionRight(role)\nread_only | contribute | approve"]
        PE3["FieldVisibility\nvisible | hidden | redacted_value | approval_required"]
    end
    subgraph SV["Storage Evolution"]
        SV1["V1: Shared Postgres + webhook"]
        SV2["V2: Supabase Realtime push subscription"]
        SV3["V3: BSV Overlay\ncell-tokens on tm_semantos_objects\nshard multicast · no central server"]
        SV1 --> SV2 --> SV3
    end
    PM1 --> Env
    T1 --> Env
    Env --> PE
    PE --> SV
    PM2 -->|approval| OV1
    PM3 -->|status read| TV1
    style Trades fill:#1c1205,stroke:#fbbf24
    style Prop fill:#061510,stroke:#34d399
    style Env fill:#0d1631,stroke:#60a5fa
    style PE fill:#0f0a1c,stroke:#a78bfa
    style SV fill:#1a0808,stroke:#f87171
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 12 ─────────────── -->
  <section class="diag-section" id="s12">
    <div class="sec-header">
      <span class="sec-num">12</span>
      <div>
        <h2 class="sec-title">Federation &amp; Relay Protocol</h2>
        <p class="sec-desc">Nodes discover peers via DNS TXT records under <code>_semantos-node.&lt;host&gt;</code>. After a BRC-100 license handshake and CBOR codec establishment, cells broadcast via <code>ws-node-adapter</code> and patches land in the receiving node's semantic object store with the sender's BCA as <code>facetId</code>. The relay room system distributes WASM release manifests.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>DNS TXT</b> peer discovery</span>
      <span class="fact"><b>BRC-100</b> license handshake</span>
      <span class="fact"><b>CBOR</b> envelope codec</span>
      <span class="fact"><b>Relay rooms</b> for release distribution</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">sequenceDiagram · DNS discovery → federation → relay</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','activationBkgColor':'#1a2840','activationBorderColor':'#60a5fa','sequenceNumberColor':'#e2e8f0','actorBkg':'#0d1631','actorBorder':'#2d5a8e','actorTextColor':'#e2e8f0','noteBkgColor':'#1a1205','noteTextColor':'#e2e8f0','noteBorderColor':'#fbbf24'}}}%%
sequenceDiagram
    participant A as Node A
    participant DNS as DNS TXT Record
    participant B as Node B
    participant Relay as cell-relay (WebSocket)
    A->>DNS: lookup _semantos-node.host
    DNS-->>A: { endpoint: wss://..., bca: "..." }
    Note over A: DnsPeerLocator with TTL cache
    A->>B: WSS connect (ws-node-adapter)
    B->>A: license handshake (SignedBundle / BRC-100)
    A->>B: license handshake response
    Note over A,B: CBOR envelope codec established
    A->>B: broadcast cell (MulticastAdapter)
    Note over A,B: session-protocol state machine
    B->>B: appendPatch(db, { facetId: Node A BCA })
    B-->>A: acknowledgement
    A->>Relay: subscribe room=release.kernel.pask
    Relay-->>A: release manifest (SignedBundle)
    A->>A: validate parent chain + content hashes
    A->>A: fetch WASM artifact (ContentStore)
    Note over A: CellDag tracks versioned release history
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 13 ─────────────── -->
  <section class="diag-section" id="s13">
    <div class="sec-header">
      <span class="sec-num">13</span>
      <div>
        <h2 class="sec-title">Content Store &amp; Release Pipeline</h2>
        <p class="sec-desc">Content-addressed storage with six pluggable adapters: local filesystem, IndexedDB, Origin Private File System, UHRP HTTP, USB/CDN hybrid, and BSV overlay (phase V3). Releases are NOT published via npm — instead a JSONL manifest is broadcast to a relay room, and consumers validate the parent chain and content hashes before fetching WASM artifacts.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>6</b> Storage adapters</span>
      <span class="fact"><b>Content-addressed</b> by SHA-256</span>
      <span class="fact"><b>Relay room</b> release distribution</span>
      <span class="fact"><b>Not npm</b> — custom manifest pipeline</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart LR · content store → adapters → release pipeline</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart LR
    subgraph CS["ContentStore Interface  ·  core/protocol-types"]
        CS1["get(hash) → Uint8Array"]
        CS2["put(bytes) → Hash"]
        CS3["verify(hash, bytes) → bool"]
        CS4["exists(hash) → bool"]
    end
    subgraph Adapters["Storage Adapters"]
        A1["LocalFsAdapter\n{root}/(hex0:2)/(hex)\nnode.js"]
        A2["IndexedDbAdapter\nbrowser persistence"]
        A3["OpfsAdapter\nOrigin Private File System\nbrowser sandboxed"]
        A4["UhrpHttpAdapter\nHTTP + UHRP protocol\ncontent-addressed HTTP"]
        A5["UsbCdnAdapter\nUSB + CDN hybrid"]
        A6["OverlayAdapter\nBSV overlay network\nphase V3"]
    end
    subgraph Release["Release Pipeline (NOT npm)"]
        RP1["tools/release/ + release.config.ts per package"]
        RP2["Release manifest (JSONL)\n{ id, stateHashHex, parentHashes,\n  patch: { op: release.kernel.publish,\n    payload: { name, version,\n      artifacts: { sha256, sizeBytes, target },\n      build: { zigVersion, sourceCommit } } } }"]
        RP3["Published to relay room\nroom=release.kernel.name"]
        RP4["ConsumerFetcher\nvalidate parentChain\nvalidate content hashes\nfetch WASM via ContentStore"]
        RP1 --> RP2 --> RP3 --> RP4
    end
    CS --> Adapters
    Adapters --> Release
    style CS fill:#0d1631,stroke:#60a5fa
    style Adapters fill:#0f0a1c,stroke:#a78bfa
    style Release fill:#061510,stroke:#34d399
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 14 ─────────────── -->
  <section class="diag-section" id="s14">
    <div class="sec-header">
      <span class="sec-num">14</span>
      <div>
        <h2 class="sec-title">Runtime Services Layer</h2>
        <p class="sec-desc">The <code>runtime/services</code> package provides renderer-agnostic singleton stores, an NLU intelligence layer, extensible verb and host-exec registries, and the reactive primitive set. The reactive atoms (<code>atom</code>, <code>derived</code>, <code>effect</code>, <code>port</code>, <code>eventBus</code>, <code>slice</code>) are the shared composition vocabulary across all stores and extensions.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>Singleton stores</b></span>
      <span class="fact"><b>NLU pipeline</b> embedding + taxonomy + calibration</span>
      <span class="fact"><b>VerbHandler</b> + <b>HostExec</b> registries</span>
      <span class="fact"><b>Reactive atoms</b> + derived + effect</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">graph TB · stores + intelligence + registries + reactive</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
graph TB
    subgraph Stores["Singleton Stores — state machines"]
        LS["LoomStore\n3-panel workbench state\nsemantic object list + detail"]
        IS["IdentityStore\ncert + HAT snapshots"]
        CS["ConfigStore\nextension configuration"]
        SS["SettingsStore\nuser preferences"]
        FR["FlowRunner\nstate-machine runner"]
    end
    subgraph Intel["Intelligence Layer"]
        IC["IntentClassifier\nNLU pipeline\nembedding + taxonomy + calibration"]
        ES["EmbeddingService\nsemantic embeddings + cosine similarity"]
        TC["TaxonomyCoherence\nvalidates taxonomy structure"]
        AE["AttentionEngine\npriority + focus management"]
    end
    subgraph Reg["Extensible Registries"]
        VH["VerbHandler registry\nshell command dispatch\nextensions add verbs"]
        HE["HostExecHandler registry\nallowlist for OP_CALLHOST\nextensions register handlers"]
    end
    subgraph Plexus["Plexus Bridge"]
        PS["PlexusService\nidentity + recovery adapters\nbinds identityPort + recoveryPort"]
    end
    subgraph React["Reactive Primitives  ·  core/state"]
        AT["atom()\nreactive cell"]
        DV["derived()\nmemoized computed atom"]
        EF["effect()\nside-effect runner + teardown"]
        PT["port()\nbindable dependency slot"]
        EB["eventBus()\nfire-and-forget pub/sub"]
        SL["slice()\nreducer + atom + dispatch"]
    end
    Stores --> React
    Intel --> Stores
    Reg --> Stores
    Plexus --> Stores
    style Stores fill:#0d1631,stroke:#60a5fa
    style Intel fill:#061510,stroke:#34d399
    style Reg fill:#1c1205,stroke:#fbbf24
    style Plexus fill:#07101e,stroke:#22d3ee
    style React fill:#1a0808,stroke:#f87171
        </div>
      </div>
    </div>
  </section>

  <!-- ─────────────── DIAGRAM 15 ─────────────── -->
  <section class="diag-section" id="s15">
    <div class="sec-header">
      <span class="sec-num">15</span>
      <div>
        <h2 class="sec-title">End-to-End Flow: Tradie Job</h2>
        <p class="sec-desc">A concrete walkthrough from natural language tenant input to BSV on-chain anchoring. Intent classification routes to plumbing, a semantic object is created, policy is compiled and evaluated in the kernel, a cross-vertical dispatch envelope is written with optimistic concurrency, anchored on BSV mainnet, and the job completes with a full tamper-evident audit trail in the hash chain.</p>
      </div>
    </div>
    <div class="facts">
      <span class="fact"><b>NL → On-chain</b> full trace</span>
      <span class="fact"><b>6</b> pipeline stages</span>
      <span class="fact"><b>Optimistic locking</b> at dispatch</span>
      <span class="fact"><b>BSV mainnet</b> anchoring</span>
    </div>
    <div class="dcard">
      <div class="dcard-toolbar">
        <div class="tb-dots"><span class="tb-dot" style="background:#ef4444"></span><span class="tb-dot" style="background:#f59e0b"></span><span class="tb-dot" style="background:#22c55e"></span></div>
        <span class="dcard-type">flowchart TD · tenant NL → BSV anchor → job close</span>
      </div>
      <div class="dcard-inner">
        <div class="mermaid">
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor':'#1a2840','primaryTextColor':'#e2e8f0','primaryBorderColor':'#2d5a8e','lineColor':'#4a6fa5','clusterBkg':'#0d1631','clusterBorder':'#1e2d45','titleColor':'#f1f5f9','edgeLabelBackground':'#0d1631','fontFamily':'Inter,-apple-system,sans-serif','fontSize':'12px'}}}%%
flowchart TD
    A["Tenant: 'tap's dripping in the kitchen'\n(natural language input)"]
    subgraph NLU["Intent Classification"]
        B["EmbeddingService → vector"]
        C["Taxonomy: services.trades.plumbing"]
        D["Confidence >= threshold → intent confirmed"]
    end
    subgraph Extract["Extraction Pipeline  ·  extension/extraction"]
        E["RestFetchAdapter / FileFetchAdapter"]
        F["Parse → Typecheck → Infer"]
        G["Commit → sem_object_patches"]
    end
    subgraph SemObj["Semantic Object Created"]
        H["MaintenanceRequest (AFFINE)\nobjectKind = maintenance_request\ncreated_by_cert_id = PM certId\nstateHash_0 = SHA-256(genesis)"]
    end
    subgraph PolicyEval["Policy Evaluation"]
        I["Lisp: (check-cap ATTESTATION 0x05)"]
        J["lower() → IRProgram (ANF)"]
        K["emit() → Uint8Array opcodes"]
        L["kernel_load_script() + kernel_execute()"]
        M["PolicyResult: { ok: true }"]
    end
    subgraph Dispatch["Cross-Vertical Dispatch"]
        N["Dispatch Envelope (RELEVANT)\nfacetId = PM BCA"]
        O["appendPatch(db, {\n  kind: dispatch,\n  delta: { tradieId, property, urgency },\n  expectedPrevStateHash: stateHash_0\n})"]
        P["new_state_hash = SHA-256(stateHash_0 + delta)"]
    end
    subgraph Chain["On-Chain Anchoring"]
        Q["CellTxBuilder: cell → BSV tx"]
        R["MapiBroadcaster: broadcast → txid"]
        S["BeefStore: store BEEF proof"]
        T["Envelope cell anchored on BSV mainnet"]
    end
    subgraph Close["Job Completion"]
        U["Tradie patches: completion photos, invoice\nfacetId = Tradie BCA\nlinearity: RELEVANT"]
        V["Owner notified: approve/reject cost"]
        W["MaintenanceRequest → invoiced → closed\nfull audit trail in prevStateHash chain"]
    end
    A --> NLU --> Extract --> SemObj
    SemObj --> PolicyEval --> Dispatch
    Dispatch --> Chain --> Close
    style NLU fill:#061510,stroke:#34d399
    style Extract fill:#07101e,stroke:#60a5fa
    style SemObj fill:#0d1631,stroke:#60a5fa
    style PolicyEval fill:#0f0a1c,stroke:#a78bfa
    style Dispatch fill:#1c1205,stroke:#fbbf24
    style Chain fill:#1a0808,stroke:#f87171
    style Close fill:#061510,stroke:#34d399
        </div>
      </div>
    </div>
  </section>

  <!-- FOOTER -->
  <div style="padding:32px 52px;border-top:1px solid var(--border);background:var(--bg-card)">
    <div style="font-family:var(--mono);font-size:11px;color:var(--text-muted);line-height:1.8">
      <div>Derived from <code style="background:rgba(255,255,255,.06);padding:1px 6px;border-radius:3px">semantos-core</code> source code and <code style="background:rgba(255,255,255,.06);padding:1px 6px;border-radius:3px">docs/textbook/</code> chapters.</div>
      <div>Import boundary enforcement: <code style="background:rgba(255,255,255,.06);padding:1px 6px;border-radius:3px">tests/gates/import-boundaries.test.ts</code></div>
      <div>Formal proofs: <code style="background:rgba(255,255,255,.06);padding:1px 6px;border-radius:3px">proofs/lean/Semantos/Theorems/</code></div>
    </div>
  </div>

</main>

<script>
  // ── Mermaid init ──
  mermaid.initialize({
    startOnLoad: true,
    securityLevel: 'loose',
  });

  // ── Sidebar scroll-spy ──
  const navItems = document.querySelectorAll('.nav-item[href^="#"]');
  const sections = document.querySelectorAll('.diag-section[id]');

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const id = '#' + entry.target.id;
        navItems.forEach(n => {
          n.classList.toggle('active', n.getAttribute('href') === id);
        });
      }
    });
  }, { rootMargin: '-15% 0px -80% 0px', threshold: 0 });

  sections.forEach(s => observer.observe(s));

  // Highlight on click too
  navItems.forEach(item => {
    item.addEventListener('click', () => {
      navItems.forEach(n => n.classList.remove('active'));
      item.classList.add('active');
    });
  });
</script>
</body>
</html>

```
