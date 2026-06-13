---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/semantos-explainer-b.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.311469+00:00
---

# semantos-explainer-b.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos — Web3 is own</title>
<meta name="description" content="The layer below every platform. Build apps where customers own their data — with audit, identity, and policy as architectural guarantees, not code you write.">
<meta property="og:title" content="Semantos — Web3 is own">
<meta property="og:description" content="The substrate that returns the P2P internet. End-to-end digital sovereignty for the apps you build.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://semantos.me/b/">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0%25' y1='0%25' x2='100%25' y2='100%25'%3E%3Cstop offset='0%25' stop-color='%2322d3ee'/%3E%3Cstop offset='100%25' stop-color='%23a78bfa'/%3E%3C/linearGradient%3E%3C/defs%3E%3Ccircle cx='16' cy='16' r='14' fill='url(%23g)'/%3E%3C/svg%3E">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#07090f;--bg2:#0b0f1a;--bg3:#0e1421;--card:#111827;
  --border:#1a2540;--border2:#223050;
  --text:#dde7f4;          /* was #c8d8ec — bumped for AA */
  --muted:#9badc8;          /* was #4a6080 — body copy, now ~7:1 contrast */
  --muted-dim:#6b7f9c;      /* small labels only */
  --bright:#eef4ff;
  --cyan:#22d3ee;--violet:#a78bfa;--blue:#60a5fa;
  --green:#34d399;--amber:#fbbf24;--red:#f87171;--pink:#f472b6;
  --font:system-ui,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;
  --mono:'JetBrains Mono','Fira Code','Cascadia Code',monospace;
}
html{scroll-behavior:smooth}
body{font-family:var(--font);background:var(--bg);color:var(--text);line-height:1.65;overflow-x:hidden;-webkit-font-smoothing:antialiased}
h1,h2,h3{color:var(--bright);font-weight:800;letter-spacing:-.025em;line-height:1.1}
h1{font-size:clamp(2.6rem,7vw,5rem)}
h2{font-size:clamp(1.8rem,4vw,3rem)}
h3{font-size:1.15rem;font-weight:700}
p{max-width:62ch}
strong{color:var(--bright)}
code{font-family:var(--mono);font-size:.85em;background:rgba(255,255,255,.07);padding:1px 7px;border-radius:4px}
a{color:inherit}

.section{padding:clamp(72px,10vw,120px) clamp(24px,8vw,80px)}
.section-inner{max-width:1080px;margin:0 auto}
.eyebrow{display:inline-flex;align-items:center;gap:10px;font-size:.7rem;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--cyan);margin-bottom:24px}
.eyebrow::before{content:'';display:block;width:28px;height:1px;background:var(--cyan)}

.reveal{opacity:0;transform:translateY(20px);transition:opacity .55s ease,transform .55s ease}
.reveal.visible{opacity:1;transform:none}
.reveal-d1{transition-delay:.08s}.reveal-d2{transition-delay:.16s}
.reveal-d3{transition-delay:.24s}.reveal-d4{transition-delay:.32s}

/* ── NAV ── */
.topnav{position:fixed;top:0;left:0;right:0;z-index:200;padding:14px clamp(24px,8vw,80px);display:flex;align-items:center;justify-content:space-between;background:rgba(7,9,15,.85);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);border-bottom:1px solid transparent;transition:border-color .3s}
.topnav.scrolled{border-bottom-color:var(--border)}
.nav-logo{font-size:.95rem;font-weight:800;letter-spacing:.06em;background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;text-decoration:none}
.nav-links{display:flex;gap:24px;flex-wrap:wrap;align-items:center}
.nav-links a{font-size:.78rem;color:var(--muted);text-decoration:none;transition:color .15s;font-weight:500}
.nav-links a:hover{color:var(--bright)}
.nav-cta{padding:8px 16px;border-radius:8px;background:linear-gradient(90deg,var(--cyan),var(--violet));color:var(--bg)!important;font-weight:700!important;font-size:.78rem!important;letter-spacing:.02em}
@media(max-width:720px){.nav-links a:not(.nav-cta){display:none}}

/* ── BUTTONS ── */
.btn{display:inline-block;font-size:.95rem;font-weight:700;padding:14px 28px;border-radius:10px;text-decoration:none;transition:transform .15s,box-shadow .15s,filter .15s;cursor:pointer;border:0;font-family:inherit}
.btn-primary{background:linear-gradient(90deg,var(--cyan) 0%,var(--violet) 100%);color:var(--bg)}
.btn-primary:hover{transform:translateY(-1px);box-shadow:0 8px 24px rgba(34,211,238,.25);filter:brightness(1.08)}
.btn-ghost{border:1px solid var(--border2);color:var(--bright);background:transparent}
.btn-ghost:hover{border-color:var(--cyan);color:var(--cyan)}
.btn-row{display:flex;gap:14px;flex-wrap:wrap;margin-top:32px}

/* ── HERO ── */
.hero{min-height:100svh;display:flex;flex-direction:column;justify-content:center;padding:clamp(110px,14vw,150px) clamp(24px,8vw,80px) clamp(60px,8vw,90px);background:radial-gradient(ellipse 80% 60% at 50% -10%,rgba(34,211,238,.08) 0%,transparent 60%),radial-gradient(ellipse 60% 40% at 80% 80%,rgba(167,139,250,.06) 0%,transparent 60%),var(--bg);position:relative;overflow:hidden}
.hero::before{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,transparent,transparent 79px,rgba(255,255,255,.015) 80px),repeating-linear-gradient(90deg,transparent,transparent 79px,rgba(255,255,255,.015) 80px);pointer-events:none}
.hero-inner{max-width:880px;position:relative;width:100%}
.hero h1{margin-bottom:28px}
.hero h1 .own{background:linear-gradient(90deg,var(--cyan) 0%,var(--violet) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.hero-sub{font-size:clamp(1.05rem,1.6vw,1.25rem);color:var(--text);max-width:54ch;line-height:1.65}
.hero-sub strong{color:var(--bright)}
.scroll-hint{position:absolute;bottom:36px;left:50%;transform:translateX(-50%);display:flex;flex-direction:column;align-items:center;gap:6px;color:var(--muted-dim);font-size:.65rem;font-weight:600;letter-spacing:.12em;text-transform:uppercase;animation:bob 2s ease-in-out infinite;text-decoration:none}
.scroll-hint svg{opacity:.6}
@keyframes bob{0%,100%{transform:translate(-50%,0)}50%{transform:translate(-50%,6px)}}

/* ── PROBLEM ── */
.problem-section{background:var(--bg);position:relative;overflow:hidden}
.problem-section::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse 70% 50% at 50% 40%,rgba(248,113,113,.025) 0%,transparent 65%);pointer-events:none}
.problem-section .section-inner{position:relative}
.problem-lead{font-size:clamp(1.05rem,1.4vw,1.2rem);color:var(--text);line-height:1.8;max-width:64ch;margin-top:24px;padding-left:22px;border-left:2px solid rgba(248,113,113,.35)}
.problem-lead strong{color:var(--bright)}
.problem-tabs{margin-top:56px}
.problem-tab-row{display:flex;gap:8px;flex-wrap:wrap;border-bottom:1px solid var(--border);padding-bottom:0;margin-bottom:32px}
.problem-tab{padding:14px 20px;border:0;background:transparent;color:var(--muted);font-family:inherit;font-size:.82rem;font-weight:700;letter-spacing:.04em;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-1px;transition:color .15s,border-color .15s;text-align:left}
.problem-tab:hover{color:var(--text)}
.problem-tab.active{color:var(--bright);border-bottom-color:var(--cyan)}
.problem-panel{display:none;grid-template-columns:1fr 1fr;gap:48px;align-items:start}
.problem-panel.active{display:grid}
@media(max-width:760px){.problem-panel.active{grid-template-columns:1fr;gap:28px}}
.problem-panel h3{font-size:1.55rem;margin-bottom:16px;color:var(--bright)}
.problem-panel p{font-size:.95rem;color:var(--muted);line-height:1.8;margin-bottom:12px}
.problem-visual{background:var(--bg2);border:1px solid var(--border);border-radius:14px;padding:22px 20px}
.pv-title{font-size:.6rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--muted-dim);margin-bottom:14px}
.drift-grid{display:flex;flex-direction:column;gap:5px}
.drift-row{display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:6px;background:rgba(255,255,255,.02);border:1px solid var(--border);font-family:var(--mono);font-size:.68rem}
.drift-sys{color:var(--muted-dim);min-width:96px;flex-shrink:0;font-size:.62rem}
.drift-val{font-weight:600}
.drift-row.conflict{border-color:rgba(248,113,113,.25);background:rgba(248,113,113,.03)}
.drift-truth{margin-top:10px;padding:8px 10px;border-radius:6px;border:1px dashed rgba(248,113,113,.3);font-size:.68rem;color:var(--muted-dim);font-family:var(--mono)}
.lock-visual{display:flex;flex-direction:column;gap:10px}
.lock-row{display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:7px;background:rgba(255,255,255,.02);border:1px solid var(--border);font-size:.78rem}
.lock-row .name{flex:1;color:var(--text);font-weight:600}
.lock-row .grav{font-size:.62rem;color:var(--red);font-family:var(--mono);background:rgba(248,113,113,.08);padding:2px 7px;border-radius:4px;border:1px solid rgba(248,113,113,.2)}
.meaning-pipe{display:flex;flex-direction:column;gap:6px}
.meaning-box{padding:9px 11px;border-radius:7px;border:1px solid var(--border)}
.meaning-label{font-size:.55rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;margin-bottom:3px}
.meaning-content{font-family:var(--mono);font-size:.68rem;color:var(--muted);line-height:1.5}
.meaning-drop{color:var(--muted-dim);font-size:.7rem;text-align:center}

/* ── SPINE ── */
.spine-section{background:var(--bg2);text-align:center}
.spine-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--border);border-radius:18px;overflow:hidden;margin-top:56px}
@media(max-width:680px){.spine-grid{grid-template-columns:1fr}}
.spine-col{background:var(--bg);padding:36px 28px;text-align:center;position:relative}
.spine-col.hi{background:linear-gradient(180deg,rgba(34,211,238,.06) 0%,rgba(167,139,250,.04) 100%)}
.spine-era{font-size:.7rem;font-weight:700;letter-spacing:.2em;color:var(--muted-dim);text-transform:uppercase;margin-bottom:14px}
.spine-word{font-size:clamp(2rem,4vw,3rem);font-weight:800;letter-spacing:-.03em;margin-bottom:12px;color:var(--bright)}
.spine-col.hi .spine-word{background:linear-gradient(90deg,var(--cyan) 0%,var(--violet) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.spine-desc{font-size:.88rem;color:var(--muted);line-height:1.6;max-width:none}
.spine-note{margin-top:36px;font-size:1rem;color:var(--muted);line-height:1.75;max-width:60ch;margin-left:auto;margin-right:auto}

/* ── CELL ── */
.cell-section{background:var(--bg)}
.cell-intro{font-size:1.1rem;color:var(--text);line-height:1.8;margin-top:24px;max-width:62ch}
.cell-intro strong{color:var(--bright)}
.cell-grid{display:grid;grid-template-columns:1.1fr .9fr;gap:48px;margin-top:56px;align-items:center}
@media(max-width:820px){.cell-grid{grid-template-columns:1fr;gap:32px}}
.cell-prose p{font-size:.95rem;color:var(--muted);line-height:1.8;margin-bottom:16px}
.cell-prose .punch{font-size:1rem;color:var(--text);padding:14px 18px;border-radius:10px;background:rgba(34,211,238,.05);border:1px solid rgba(34,211,238,.18);font-style:normal;margin-top:8px}
.cell-diagram{background:var(--bg2);border:1px solid var(--border);border-radius:18px;padding:28px;font-family:var(--mono)}
.cell-card{border:1px solid rgba(34,211,238,.3);border-radius:12px;background:linear-gradient(135deg,rgba(34,211,238,.04),rgba(167,139,250,.04));padding:18px;margin-bottom:16px}
.cell-card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;padding-bottom:12px;border-bottom:1px solid var(--border)}
.cell-card-label{font-size:.6rem;color:var(--cyan);letter-spacing:.12em;font-weight:700;text-transform:uppercase}
.cell-card-hash{font-size:.65rem;color:var(--muted-dim)}
.cell-field{display:flex;justify-content:space-between;padding:5px 0;font-size:.72rem;border-bottom:1px dashed rgba(255,255,255,.04)}
.cell-field:last-child{border-bottom:0}
.cell-field .k{color:var(--muted-dim)}
.cell-field .v{color:var(--text)}
.cell-prev{display:flex;align-items:center;gap:8px;font-size:.7rem;color:var(--muted);justify-content:center;padding:8px 0}
.cell-prev svg{color:var(--violet)}

/* ── STATES ── */
.states-section{background:var(--bg2)}
.states-intro{font-size:1.1rem;color:var(--text);line-height:1.8;margin-top:24px;max-width:64ch}
.states-cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:48px}
@media(max-width:880px){.states-cards{grid-template-columns:1fr}}
.state-card{background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:24px;transition:border-color .2s,transform .2s}
.state-card:hover{border-color:var(--border2);transform:translateY(-2px)}
.state-icon{font-size:1.8rem;margin-bottom:14px}
.state-card h3{font-size:1.05rem;margin-bottom:6px}
.state-sub{font-size:.78rem;color:var(--muted-dim);margin-bottom:18px;font-weight:600;letter-spacing:.04em}
.state-pills{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.state-pill{padding:6px 11px;border-radius:6px;font-family:var(--mono);font-size:.7rem;font-weight:600;border:1px solid var(--border);background:rgba(255,255,255,.02);color:var(--muted);transition:all .15s;cursor:default}
.state-pill:hover{border-color:var(--cyan);color:var(--cyan);background:rgba(34,211,238,.06)}
.state-arrow{color:var(--muted-dim);font-size:.7rem}
.state-foot{margin-top:18px;padding-top:16px;border-top:1px solid var(--border);font-size:.75rem;color:var(--muted);line-height:1.5}
.state-foot code{font-size:.7rem}
.states-coda{margin-top:48px;padding:28px 32px;border-radius:16px;background:linear-gradient(135deg,rgba(34,211,238,.05),rgba(167,139,250,.05));border:1px solid rgba(34,211,238,.15);font-size:1.05rem;line-height:1.8;color:var(--text);max-width:72ch}

/* ── THREE THINGS (Vincent's loved-line) ── */
.three-section{background:var(--bg)}
.three-quote{font-size:clamp(1.3rem,2.4vw,1.75rem);color:var(--bright);line-height:1.5;font-weight:600;max-width:30ch;margin-top:24px;letter-spacing:-.01em}
.three-quote em{font-style:normal;background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.three-attr{font-size:.8rem;color:var(--muted-dim);margin-top:12px;letter-spacing:.04em}
.three-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:48px}
@media(max-width:760px){.three-grid{grid-template-columns:1fr}}
.three-card{background:var(--bg2);border:1px solid var(--border);border-radius:14px;padding:24px}
.three-num{font-family:var(--mono);font-size:.7rem;color:var(--muted-dim);font-weight:700;margin-bottom:14px;letter-spacing:.1em}
.three-card h3{font-size:1.05rem;margin-bottom:10px}
.three-card p{font-size:.88rem;color:var(--muted);line-height:1.7}
.three-bridge{margin-top:40px;font-size:1.05rem;color:var(--text);line-height:1.78;max-width:68ch}
.three-bridge strong{color:var(--bright)}

/* ── DEVELOPER INVERSION ── */
.dev-section{background:var(--bg2)}
.dev-grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border);border-radius:18px;overflow:hidden;margin-top:48px}
@media(max-width:760px){.dev-grid{grid-template-columns:1fr}}
.dev-col{background:var(--bg);padding:32px 28px}
.dev-col.before{background:var(--bg)}
.dev-col.after{background:linear-gradient(180deg,rgba(34,211,238,.04),rgba(167,139,250,.03))}
.dev-col-label{font-size:.7rem;font-weight:700;letter-spacing:.15em;text-transform:uppercase;margin-bottom:14px}
.dev-col.before .dev-col-label{color:var(--red)}
.dev-col.after .dev-col-label{color:var(--cyan)}
.dev-col h3{font-size:1.2rem;margin-bottom:18px}
.dev-list{list-style:none;display:flex;flex-direction:column;gap:10px}
.dev-list li{font-size:.88rem;color:var(--muted);padding-left:24px;position:relative;line-height:1.6}
.dev-list li::before{position:absolute;left:0;top:0;font-family:var(--mono);font-size:.85rem;font-weight:700}
.dev-col.before .dev-list li::before{content:'✗';color:var(--red)}
.dev-col.after .dev-list li::before{content:'✓';color:var(--green)}
.dev-coda{margin-top:36px;font-size:1.05rem;color:var(--text);line-height:1.78;max-width:68ch}
.dev-coda strong{color:var(--bright)}

/* ── PROOF ── */
.proof-section{background:var(--bg)}
.proof-grid{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:48px}
@media(max-width:760px){.proof-grid{grid-template-columns:1fr}}
.proof-card{background:var(--bg2);border:1px solid var(--border);border-radius:16px;padding:30px;transition:border-color .2s,transform .2s}
.proof-card:hover{transform:translateY(-3px);border-color:var(--border2)}
.proof-card-tag{font-size:.62rem;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--muted-dim);margin-bottom:14px}
.proof-card h3{font-size:1.3rem;margin-bottom:12px}
.proof-card p{font-size:.92rem;color:var(--muted);line-height:1.7;margin-bottom:20px}
.proof-link{display:inline-flex;align-items:center;gap:8px;font-size:.82rem;font-weight:700;color:var(--cyan);text-decoration:none;border-bottom:1px solid transparent;transition:border-color .15s}
.proof-link:hover{border-bottom-color:var(--cyan)}
.proof-card.ojt h3 span{background:linear-gradient(90deg,var(--green),var(--cyan));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.proof-card.plexus h3 span{background:linear-gradient(90deg,var(--pink),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}

/* ── CTA ── */
.cta-section{background:linear-gradient(180deg,var(--bg) 0%,var(--bg2) 100%);text-align:center}
.cta-inner{max-width:640px;margin:0 auto}
.cta-section h2{margin-bottom:20px}
.cta-section p{font-size:1.05rem;color:var(--muted);line-height:1.7;margin:0 auto 36px}
.cta-form{display:flex;gap:10px;max-width:480px;margin:0 auto;flex-wrap:wrap}
.cta-form input{flex:1;min-width:200px;padding:14px 18px;border-radius:10px;border:1px solid var(--border2);background:var(--bg);color:var(--text);font-family:inherit;font-size:.95rem;outline:none;transition:border-color .15s}
.cta-form input:focus{border-color:var(--cyan)}
.cta-form input::placeholder{color:var(--muted-dim)}
.cta-form button{flex-shrink:0}
.cta-foot{margin-top:18px;font-size:.78rem;color:var(--muted-dim)}

/* ── FOOTER ── */
.footer{padding:48px clamp(24px,8vw,80px);border-top:1px solid var(--border);background:var(--bg);text-align:center;font-size:.78rem;color:var(--muted-dim)}
.footer-links{display:flex;justify-content:center;gap:24px;margin-bottom:16px;flex-wrap:wrap}
.footer-links a{color:var(--muted);text-decoration:none;transition:color .15s}
.footer-links a:hover{color:var(--bright)}

/* ── VARIANT SWITCHER ── */
.variant-toggle{position:fixed;bottom:18px;right:18px;z-index:300;display:flex;align-items:center;gap:10px;padding:10px 14px;border-radius:24px;background:rgba(11,15,26,.92);border:1px solid var(--border2);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);font-size:.72rem;font-weight:600;color:var(--muted);box-shadow:0 4px 16px rgba(0,0,0,.4)}
.variant-toggle .badge{padding:3px 9px;border-radius:12px;background:linear-gradient(90deg,var(--cyan),var(--violet));color:var(--bg);font-weight:800;letter-spacing:.05em;font-size:.68rem}
.variant-toggle a{color:var(--cyan);text-decoration:none;font-weight:700}
.variant-toggle a:hover{text-decoration:underline}
@media(max-width:560px){.variant-toggle{font-size:.66rem;padding:8px 11px}}
</style>
</head>
<body>

<nav class="topnav" id="topnav">
  <a href="#" class="nav-logo">SEMANTOS</a>
  <div class="nav-links">
    <a href="#problem">Problem</a>
    <a href="#cell">The cell</a>
    <a href="#states">What it runs on</a>
    <a href="#dev">For builders</a>
    <a href="#contact" class="nav-cta">Get in touch</a>
  </div>
</nav>

<!-- ═══════ HERO ═══════ -->
<section class="hero">
  <div class="hero-inner">
    <div class="eyebrow">The layer below every platform</div>
    <h1>
      Web1 was read.<br>
      Web2 was write.<br>
      Web3 is <span class="own">own.</span>
    </h1>
    <p class="hero-sub">
      The platforms you depend on profit from your dependency. Semantos is the substrate that ends it — your data, your customers' records, and the audit trail of everything that happened, live in objects <strong>you control</strong>, not in databases someone else owns.
    </p>
    <div class="btn-row">
      <a href="#cell" class="btn btn-primary">See how a cell works →</a>
      <a href="#dev" class="btn btn-ghost">For developers</a>
    </div>
  </div>
  <a href="#problem" class="scroll-hint" aria-label="Scroll to problem">
    <span>Scroll</span>
    <svg width="14" height="20" viewBox="0 0 14 20" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="1" width="12" height="18" rx="6"/><line x1="7" y1="5" x2="7" y2="9" stroke-linecap="round"/></svg>
  </a>
</section>

<!-- ═══════ PROBLEM ═══════ -->
<section class="section problem-section" id="problem">
  <div class="section-inner">
    <div class="eyebrow reveal" style="color:var(--red)">The broken internet</div>
    <h2 class="reveal" style="max-width:20ch">The internet was built peer-to-peer.<br>The platforms made it theirs.</h2>
    <div class="problem-lead reveal reveal-d1">
      Right now, the truth about your business is <strong>distributed across systems that don't agree, owned by platforms that profit from your dependency.</strong> Every useful tool you adopted built its value by absorbing your data and your relationships, then became the chokepoint. The more you depend on it, the more it can charge.
    </div>

    <div class="problem-tabs reveal reveal-d2">
      <div class="problem-tab-row" role="tablist">
        <button class="problem-tab active" data-tab="t1" role="tab">1 · Nobody knows what's real</button>
        <button class="problem-tab" data-tab="t2" role="tab">2 · Meaning lost at every boundary</button>
        <button class="problem-tab" data-tab="t3" role="tab">3 · Your data lives in their house</button>
      </div>

      <div class="problem-panel active" id="t1">
        <div>
          <h3>One job. Five systems. Five versions of the truth.</h3>
          <p>Truth exists in multiple copies, each drifting from the others. A single job is a ticket here, a draft invoice there, an unread email somewhere else, and a push notification on a phone. None of them agree. None is canonical.</p>
          <p>Reconciliation is manual, expensive, and usually wrong by the time anyone looks. Every time two parties need to coordinate — business and contractor, landlord and tenant, company and regulator — the trust model gets rebuilt from scratch.</p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Work order #4821 — one job, five versions</div>
          <div class="drift-grid">
            <div class="drift-row"><span class="drift-sys">PM tool</span><span class="drift-val" style="color:var(--blue)">in progress</span></div>
            <div class="drift-row conflict"><span class="drift-sys">Accounting</span><span class="drift-val" style="color:var(--amber)">draft · awaiting PO</span></div>
            <div class="drift-row conflict"><span class="drift-sys">Owner's inbox</span><span class="drift-val" style="color:var(--muted-dim)">approval · unread</span></div>
            <div class="drift-row"><span class="drift-sys">Contractor app</span><span class="drift-val" style="color:var(--green)">en route</span></div>
            <div class="drift-row conflict"><span class="drift-sys">Compliance log</span><span class="drift-val" style="color:var(--red)">no record</span></div>
            <div class="drift-truth">source of truth: <span style="color:var(--red)">undefined</span></div>
          </div>
        </div>
      </div>

      <div class="problem-panel" id="t2">
        <div>
          <h3>Data crosses boundaries.<br>Meaning doesn't.</h3>
          <p>Every system boundary destroys context. "Urgent — tenant has no hot water, fix before 5pm" becomes a priority-3 ticket, becomes a work order code, becomes a row with a status integer. The urgency is gone. So is the causal chain — who said what, who agreed, who authorised.</p>
          <p>Audit trails are owned by the platforms that create them. When something goes wrong — a dispute, a liability, an audit — you can prove what the platform <em>recorded</em>. You cannot prove what actually <em>happened</em>.</p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Meaning lost in transit</div>
          <div class="meaning-pipe">
            <div class="meaning-box" style="border-color:rgba(52,211,153,.25);background:rgba(52,211,153,.04)">
              <div class="meaning-label" style="color:var(--green)">natural language</div>
              <div class="meaning-content" style="color:var(--text)">"Urgent — tap dripping, tenant has no hot water, fix before 5pm"</div>
            </div>
            <div class="meaning-drop">↓</div>
            <div class="meaning-box" style="border-color:rgba(251,191,36,.2)">
              <div class="meaning-label" style="color:var(--amber)">ticket system</div>
              <div class="meaning-content">type: MAINTENANCE · priority: 3 · status: OPEN</div>
            </div>
            <div class="meaning-drop">↓</div>
            <div class="meaning-box" style="border-color:rgba(248,113,113,.2)">
              <div class="meaning-label" style="color:var(--red)">db row</div>
              <div class="meaning-content">id: 4821 · code: 0x04 · status: 2</div>
            </div>
          </div>
        </div>
      </div>

      <div class="problem-panel" id="t3">
        <div>
          <h3>You can export a CSV.<br>You cannot take the meaning.</h3>
          <p>Your customers live in a CRM. Your finances live in an accounting platform. Your team lives in an HR tool. Your relationships live in a social graph someone else owns. Leaving costs more than staying — not because of the data, but because of the workflows, the history, and the muscle memory.</p>
          <p>The platform doesn't hold your data hostage. It holds your <strong>workflows</strong>, your <strong>history</strong>, and your team's <strong>habits</strong>. The only exit is a year-long migration into another platform with the same problem.</p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Data gravity — flows in, barely escapes</div>
          <div class="lock-visual">
            <div class="lock-row"><span class="name">CRM platform</span><span class="grav">↓ your relationships</span></div>
            <div class="lock-row"><span class="name">Accounting SaaS</span><span class="grav">↓ your money trail</span></div>
            <div class="lock-row"><span class="name">HR / payroll</span><span class="grav">↓ your org chart</span></div>
            <div class="lock-row"><span class="name">Social platform</span><span class="grav">↓ your network</span></div>
            <div class="lock-row" style="border-color:rgba(248,113,113,.35);background:rgba(248,113,113,.05)"><span class="name" style="color:var(--red)">Exit cost</span><span class="grav">12+ months · re-buy everything</span></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- ═══════ WEB 1/2/3 SPINE ═══════ -->
<section class="section spine-section">
  <div class="section-inner">
    <div class="eyebrow">The arc of the web</div>
    <h2 class="reveal">Three eras. Three verbs.</h2>
    <div class="spine-grid reveal reveal-d1">
      <div class="spine-col">
        <div class="spine-era">Web 1</div>
        <div class="spine-word">Read</div>
        <div class="spine-desc">Static documents. Linked, public, anyone could publish, anyone could read.</div>
      </div>
      <div class="spine-col">
        <div class="spine-era">Web 2</div>
        <div class="spine-word">Write</div>
        <div class="spine-desc">Anyone could post — but only inside platforms. The platforms kept what we wrote.</div>
      </div>
      <div class="spine-col hi">
        <div class="spine-era">Web 3</div>
        <div class="spine-word">Own</div>
        <div class="spine-desc">Records, identity, and history live in objects you hold — not in someone else's database.</div>
      </div>
    </div>
    <p class="spine-note reveal reveal-d2">
      Semantos is how you build apps that fit the third verb. <strong>End-to-end digital sovereignty</strong>, by default, in the substrate — not as a feature you have to remember to add.
    </p>
  </div>
</section>

<!-- ═══════ THE CELL ═══════ -->
<section class="section cell-section" id="cell">
  <div class="section-inner">
    <div class="eyebrow">The primitive</div>
    <h2 class="reveal">A row in a database<br>belongs to whoever runs the database.</h2>
    <p class="cell-intro reveal reveal-d1">
      <strong>A cell belongs to whoever holds it.</strong>
    </p>

    <div class="cell-grid reveal reveal-d2">
      <div class="cell-prose">
        <p>A cell is a self-contained object. It carries its own <strong>identity</strong> — who created it, who can change it, who can read it. It carries its own <strong>history</strong> — every change points back to the previous version, so the full chain of what happened can be replayed. And it carries its own <strong>rules</strong> — what it is, what it costs, where it can travel, who can consume it.</p>
        <p>If you've used Bitcoin, you've already seen one. A Bitcoin output is a lockbox: it exists once, can be spent once, and proves who unlocked it. Semantos generalises that pattern — to any business object, in any workflow, anywhere.</p>
        <p class="punch">Try to forge one and the chain breaks. The system catches the inauthentic object before anyone acts on it.</p>
      </div>
      <div class="cell-diagram">
        <div class="cell-card">
          <div class="cell-card-header">
            <span class="cell-card-label">CELL · job/4821</span>
            <span class="cell-card-hash">0xa7…f3</span>
          </div>
          <div class="cell-field"><span class="k">state</span><span class="v">on-site</span></div>
          <div class="cell-field"><span class="k">created by</span><span class="v">@dispatcher</span></div>
          <div class="cell-field"><span class="k">can change</span><span class="v">@tech / @owner</span></div>
          <div class="cell-field"><span class="k">policy</span><span class="v">approve > $500</span></div>
          <div class="cell-field"><span class="k">consumes</span><span class="v">one-of-a-kind</span></div>
        </div>
        <div class="cell-prev">
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M10 4L4 8l6 4M4 8h12" stroke-linecap="round" stroke-linejoin="round"/></svg>
          previous version: 0x83…c1
        </div>
        <div class="cell-card" style="opacity:.7;border-color:rgba(167,139,250,.25);background:linear-gradient(135deg,rgba(167,139,250,.03),rgba(34,211,238,.02))">
          <div class="cell-card-header">
            <span class="cell-card-label" style="color:var(--violet)">CELL · job/4821</span>
            <span class="cell-card-hash">0x83…c1</span>
          </div>
          <div class="cell-field"><span class="k">state</span><span class="v">scheduled</span></div>
          <div class="cell-field"><span class="k">created by</span><span class="v">@owner</span></div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- ═══════ ANYTHING WITH STATES ═══════ -->
<section class="section states-section" id="states">
  <div class="section-inner">
    <div class="eyebrow">Universality</div>
    <h2 class="reveal">If you can write down its states,<br>Semantos can run it.</h2>
    <p class="states-intro reveal reveal-d1">
      Anything with a finite set of states becomes a chain of cells — each transition signed, each version provable, every change auditable without anyone having to maintain a log. The audit trail <strong>is</strong> the data.
    </p>

    <div class="states-cards">
      <div class="state-card reveal reveal-d1">
        <div class="state-icon">🥤</div>
        <h3>Vending machine</h3>
        <div class="state-sub">A physical machine</div>
        <div class="state-pills">
          <span class="state-pill">unfunded</span><span class="state-arrow">→</span>
          <span class="state-pill">funded</span><span class="state-arrow">→</span>
          <span class="state-pill">serving</span><span class="state-arrow">→</span>
          <span class="state-pill">served</span>
        </div>
        <div class="state-foot">Each coin, each dispense, each refund — a cell. The machine's whole life in <code>~kb/year</code>.</div>
      </div>

      <div class="state-card reveal reveal-d2">
        <div class="state-icon">🔧</div>
        <h3>Trades job</h3>
        <div class="state-sub">A workflow</div>
        <div class="state-pills">
          <span class="state-pill">lead</span><span class="state-arrow">→</span>
          <span class="state-pill">quote</span><span class="state-arrow">→</span>
          <span class="state-pill">schedule</span><span class="state-arrow">→</span>
          <span class="state-pill">on-site</span><span class="state-arrow">→</span>
          <span class="state-pill">invoice</span><span class="state-arrow">→</span>
          <span class="state-pill">paid</span>
        </div>
        <div class="state-foot">Everyone — owner, tech, customer, accountant — sees the same record. Disputes vanish.</div>
      </div>

      <div class="state-card reveal reveal-d3">
        <div class="state-icon">🎹</div>
        <h3>Musical instrument</h3>
        <div class="state-sub">A device's runtime</div>
        <div class="state-pills">
          <span class="state-pill">key A on</span><span class="state-arrow">·</span>
          <span class="state-pill">dial 3 = 7</span><span class="state-arrow">·</span>
          <span class="state-pill">sustain</span>
        </div>
        <div class="state-foot">Every gesture is a signed event. Replay a performance bit-for-bit, prove provenance of a sound.</div>
      </div>
    </div>

    <div class="states-coda reveal reveal-d4">
      A Bitcoin output is one kind of cell — money. A trades job is another. So is a vending machine, a music performance, a regulatory filing, a vote. The substrate doesn't care what the states <em>mean</em>. It guarantees they <em>can't be quietly rewritten</em>.
    </div>
  </div>
</section>

<!-- ═══════ THREE THINGS (Vincent's loved line) ═══════ -->
<section class="section three-section">
  <div class="section-inner">
    <div class="eyebrow">The foundation</div>
    <h2 class="reveal" style="max-width:24ch">Every system that solves a real-world problem<br>ends up inventing the same three things.</h2>
    <div class="three-grid reveal reveal-d1">
      <div class="three-card">
        <div class="three-num">01 / MEANING</div>
        <h3>Understanding what someone means.</h3>
        <p>Turning natural language and human intent into something a system can reason about — without losing the urgency, the context, or the causal chain.</p>
      </div>
      <div class="three-card">
        <div class="three-num">02 / PROOF</div>
        <h3>Proving what happened, and when.</h3>
        <p>A record nobody can rewrite. Timestamped, signed, chained — so the audit trail isn't a feature, it's the data itself.</p>
      </div>
      <div class="three-card">
        <div class="three-num">03 / COMMITMENT</div>
        <h3>Making commitments that can't be repeated.</h3>
        <p>A one-of-a-kind thing — money, a signoff, a license, an approval — that can be consumed exactly once. The math, not the platform, enforces it.</p>
      </div>
    </div>
    <p class="three-bridge reveal reveal-d2">
      Most apps build these three things <strong>badly, every time</strong>, on top of databases that were never designed for them. Semantos gives you all three — as the floor, not as a feature.
    </p>
  </div>
</section>

<!-- ═══════ DEVELOPER INVERSION ═══════ -->
<section class="section dev-section" id="dev">
  <div class="section-inner">
    <div class="eyebrow">For builders</div>
    <h2 class="reveal" style="max-width:22ch">You spent two weeks on the prototype.<br>And six months on everything around it.</h2>
    <div class="dev-grid reveal reveal-d1">
      <div class="dev-col before">
        <div class="dev-col-label">Without Semantos</div>
        <h3>The work you didn't sign up for</h3>
        <ul class="dev-list">
          <li>Hand-rolled audit log nobody trusts</li>
          <li>Role and permissions soup — every endpoint a new edge case</li>
          <li>Integration adapters for every other system</li>
          <li>Compliance trail you re-derive at audit time</li>
          <li>Security guarantees that depend on you remembering to add them</li>
          <li>Migration plan the day you outgrow the platform you picked</li>
        </ul>
      </div>
      <div class="dev-col after">
        <div class="dev-col-label">With Semantos</div>
        <h3>You build the product. The substrate handles the rest.</h3>
        <ul class="dev-list">
          <li>Audit is in the cell — every change is the audit</li>
          <li>Identity is in the cell — who can do what is signed</li>
          <li>Policy is in the cell — rules travel with the object</li>
          <li>Interop by default — same format everywhere</li>
          <li>Cryptographic guarantees are the floor, not the ceiling</li>
          <li>Customers own their data — there is no migration</li>
        </ul>
      </div>
    </div>
    <p class="dev-coda reveal reveal-d2">
      Two weeks of value. Six months of plumbing. <strong>Semantos inverts that.</strong> Architectural guarantees in the substrate mean you spend your time on the thing that actually makes your product worth buying.
    </p>
  </div>
</section>

<!-- ═══════ PROOF / SISTER PRODUCTS ═══════ -->
<section class="section proof-section">
  <div class="section-inner">
    <div class="eyebrow">Built on it</div>
    <h2 class="reveal">Apps people already trust,<br>running on the substrate.</h2>
    <div class="proof-grid reveal reveal-d1">
      <div class="proof-card ojt">
        <div class="proof-card-tag">Case study</div>
        <h3><span>OddJobTodd</span></h3>
        <p>A real trades business running on Semantos. Every lead, quote, job, signoff and payment lives in a chain of cells the business owns. Customers see their job's full history. Disputes don't happen — there's one record, and it can't be rewritten.</p>
        <a href="https://oddjobtodd.info" class="proof-link" target="_blank" rel="noopener">See it in production →</a>
      </div>
      <div class="proof-card plexus">
        <div class="proof-card-tag">Sister product</div>
        <h3><span>Plexus</span></h3>
        <p>Your social graph is yours. Plexus lets you recover keys and relationships — leave any platform without leaving the people. Built on the same substrate. Because the friend you met overseas ten years ago shouldn't be locked inside someone else's app.</p>
        <a href="#" class="proof-link">Learn more →</a>
      </div>
    </div>
  </div>
</section>

<!-- ═══════ CTA ═══════ -->
<section class="section cta-section" id="contact">
  <div class="cta-inner">
    <div class="eyebrow" style="justify-content:center">Get on the pilot list</div>
    <h2>Build what you couldn't build before.</h2>
    <p>If you're a founder, developer, or operator who's tired of paying rent on your own data — leave your email. We'll show you what's possible, and how to get started.</p>
    <form class="cta-form" onsubmit="event.preventDefault();this.querySelector('button').textContent='Thanks — we\'ll be in touch';this.querySelector('input').value='';this.querySelector('input').placeholder='✓ added';">
      <input type="email" required placeholder="you@yourdomain.com" autocomplete="email">
      <button type="submit" class="btn btn-primary">Get in touch →</button>
    </form>
    <div class="cta-foot">Or email <a href="mailto:todd@semantos.me" style="color:var(--cyan);text-decoration:none">todd@semantos.me</a> directly.</div>
  </div>
</section>

<!-- ═══════ FOOTER ═══════ -->
<footer class="footer">
  <div class="footer-links">
    <a href="#problem">Problem</a>
    <a href="#cell">The cell</a>
    <a href="#states">Universality</a>
    <a href="#dev">For builders</a>
    <a href="#contact">Get in touch</a>
  </div>
  <div>Semantos · the layer below every platform · <span style="color:var(--muted-dim)">© 2026</span></div>
</footer>

<!-- Variant switcher -->
<div class="variant-toggle">
  <span class="badge">B</span>
  <span>variant</span>
  <a href="/">view A →</a>
</div>

<script>
// Reveal on scroll
const io = new IntersectionObserver((entries) => {
  entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); io.unobserve(e.target); } });
}, { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach(el => io.observe(el));

// Nav scroll state
const nav = document.getElementById('topnav');
window.addEventListener('scroll', () => { nav.classList.toggle('scrolled', window.scrollY > 20); });

// Problem tabs
document.querySelectorAll('.problem-tab').forEach(btn => {
  btn.addEventListener('click', () => {
    const id = btn.dataset.tab;
    document.querySelectorAll('.problem-tab').forEach(b => b.classList.toggle('active', b === btn));
    document.querySelectorAll('.problem-panel').forEach(p => p.classList.toggle('active', p.id === id));
  });
});
</script>
</body>
</html>

```
