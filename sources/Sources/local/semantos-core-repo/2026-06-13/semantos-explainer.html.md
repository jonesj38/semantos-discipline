---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/semantos-explainer.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.312996+00:00
---

# semantos-explainer.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos — Voice to Economic Execution</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#07090f;--bg2:#0b0f1a;--bg3:#0e1421;--card:#111827;
  --border:#1a2540;--border2:#223050;
  --text:#c8d8ec;--muted:#4a6080;--bright:#eef4ff;
  --cyan:#22d3ee;--violet:#a78bfa;--blue:#60a5fa;
  --green:#34d399;--amber:#fbbf24;--red:#f87171;--pink:#f472b6;
  --font:system-ui,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;
  --mono:'JetBrains Mono','Fira Code','Cascadia Code',monospace;
}
html{scroll-behavior:smooth}
body{font-family:var(--font);background:var(--bg);color:var(--text);line-height:1.6;overflow-x:hidden}
h1,h2,h3{color:var(--bright);font-weight:800;letter-spacing:-.025em;line-height:1.1}
h1{font-size:clamp(2.4rem,6vw,4.5rem)}
h2{font-size:clamp(1.8rem,4vw,3rem)}
h3{font-size:1.2rem;font-weight:700}
p{max-width:64ch}
code{font-family:var(--mono);font-size:.85em;background:rgba(255,255,255,.07);padding:1px 7px;border-radius:4px}
strong{color:var(--text)}

.section{padding:clamp(72px,10vw,120px) clamp(24px,8vw,80px)}
.section-inner{max-width:1100px;margin:0 auto}
.label{display:inline-flex;align-items:center;gap:10px;font-size:.7rem;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--cyan);margin-bottom:20px}
.label::before{content:'';display:block;width:28px;height:1px;background:var(--cyan)}

.reveal{opacity:0;transform:translateY(24px);transition:opacity .6s ease,transform .6s ease}
.reveal.visible{opacity:1;transform:none}
.reveal-d1{transition-delay:.1s}.reveal-d2{transition-delay:.2s}
.reveal-d3{transition-delay:.3s}.reveal-d4{transition-delay:.4s}

/* ── NAV ── */
.topnav{position:fixed;top:0;left:0;right:0;z-index:200;padding:14px clamp(24px,8vw,80px);display:flex;align-items:center;justify-content:space-between;background:rgba(7,9,15,.88);backdrop-filter:blur(16px);border-bottom:1px solid transparent;transition:border-color .3s}
.topnav.scrolled{border-bottom-color:var(--border)}
.nav-logo{font-size:.95rem;font-weight:800;letter-spacing:.06em;background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.nav-links{display:flex;gap:20px;flex-wrap:wrap}
.nav-links a{font-size:.78rem;color:var(--muted);text-decoration:none;transition:color .15s;font-weight:500}
.nav-links a:hover{color:var(--text)}
@media(max-width:600px){.nav-links{display:none}}

/* ── HERO ── */
.hero{min-height:100svh;display:flex;flex-direction:column;justify-content:center;padding:clamp(80px,12vw,140px) clamp(24px,8vw,80px);background:radial-gradient(ellipse 80% 60% at 50% -10%,rgba(34,211,238,.07) 0%,transparent 60%),radial-gradient(ellipse 60% 40% at 80% 80%,rgba(167,139,250,.05) 0%,transparent 60%),var(--bg);position:relative;overflow:hidden}
.hero::before{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,transparent,transparent 79px,rgba(255,255,255,.015) 80px),repeating-linear-gradient(90deg,transparent,transparent 79px,rgba(255,255,255,.015) 80px);pointer-events:none}
.hero-inner{max-width:960px;position:relative}
.hero-h1{margin-bottom:24px}
.hero-h1 .line1{display:block;color:var(--bright)}
.hero-h1 .line2{display:block;background:linear-gradient(90deg,var(--cyan) 0%,var(--violet) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.hero-lede{font-size:clamp(1rem,2vw,1.2rem);color:var(--muted);max-width:52ch;margin-bottom:52px;line-height:1.75}

.pipeline{display:flex;align-items:center;gap:0;flex-wrap:nowrap;overflow-x:auto;padding-bottom:4px;scrollbar-width:none}
.pipeline::-webkit-scrollbar{display:none}
.pipe-step{display:flex;flex-direction:column;align-items:center;animation:pipeIn .5s ease both}
.pipe-step:nth-child(1){animation-delay:.4s}.pipe-step:nth-child(2){animation-delay:.55s}.pipe-step:nth-child(3){animation-delay:.7s}.pipe-step:nth-child(4){animation-delay:.85s}.pipe-step:nth-child(5){animation-delay:1s}.pipe-step:nth-child(6){animation-delay:1.15s}.pipe-step:nth-child(7){animation-delay:1.3s}.pipe-step:nth-child(8){animation-delay:1.45s}.pipe-step:nth-child(9){animation-delay:1.6s}
@keyframes pipeIn{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
.pipe-node{padding:8px 14px;border-radius:8px;font-size:.78rem;font-weight:600;white-space:nowrap;border:1px solid;letter-spacing:.01em}
.pipe-tag{font-size:.58rem;color:var(--muted);margin-top:5px;font-weight:600;letter-spacing:.08em;text-transform:uppercase}
.pipe-arrow{display:flex;align-items:center;padding:0 5px;animation:arrowIn .4s ease both}
@keyframes arrowIn{from{opacity:0;transform:scaleX(.3)}to{opacity:1;transform:none}}
.pipe-arrow svg{color:var(--muted)}

/* ══ PROBLEM ══ */
.problem-section{background:var(--bg);position:relative;overflow:hidden}
.problem-section::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse 70% 50% at 50% 60%,rgba(248,113,113,.03) 0%,transparent 65%);pointer-events:none}
.problem-lede{font-size:1.05rem;color:var(--muted);line-height:1.85;max-width:64ch;margin-top:24px;padding-left:22px;border-left:2px solid rgba(248,113,113,.3)}
.problem-clusters{display:flex;flex-direction:column;gap:0;margin-top:52px}
.problem-cluster{display:grid;grid-template-columns:1fr 1fr;gap:44px;align-items:start;padding:44px 0;border-top:1px solid var(--border)}
@media(max-width:720px){.problem-cluster{grid-template-columns:1fr;gap:24px}}
.problem-cluster-tag{font-size:.6rem;font-weight:700;letter-spacing:.18em;text-transform:uppercase;margin-bottom:12px}
.problem-cluster h3{font-size:1.35rem;font-weight:800;margin-bottom:14px;line-height:1.15;color:var(--bright)}
.problem-cluster-text{font-size:.9rem;color:var(--muted);line-height:1.8}
.problem-visual{background:var(--bg2);border:1px solid var(--border);border-radius:14px;padding:22px 20px}
.pv-title{font-size:.6rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:14px}
.drift-grid{display:flex;flex-direction:column;gap:5px}
.drift-row{display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:6px;background:rgba(255,255,255,.02);border:1px solid var(--border);font-family:var(--mono);font-size:.67rem}
.drift-sys{color:var(--muted);min-width:96px;flex-shrink:0;font-size:.6rem}
.drift-val{font-weight:600}
.drift-row.conflict{border-color:rgba(248,113,113,.25);background:rgba(248,113,113,.03)}
.meaning-pipe{display:flex;flex-direction:column;gap:4px}
.meaning-step{display:flex;align-items:flex-start;gap:8px}
.meaning-drop{color:var(--muted);padding-top:3px;flex-shrink:0;font-size:.75rem;line-height:1}
.meaning-box{flex:1;padding:8px 10px;border-radius:7px;border:1px solid var(--border)}
.meaning-label{font-size:.55rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;margin-bottom:3px}
.meaning-content{font-family:var(--mono);font-size:.67rem;color:var(--muted);line-height:1.5}
.siren-diagram{display:flex;flex-direction:column;align-items:center;gap:12px}
.siren-actors{display:flex;gap:10px;justify-content:center;flex-wrap:wrap}
.siren-actor{display:flex;flex-direction:column;align-items:center;gap:4px}
.siren-actor-dot{width:32px;height:32px;border-radius:50%;border:1px solid var(--border2);display:flex;align-items:center;justify-content:center;font-size:.72rem;background:var(--bg)}
.siren-actor-label{font-size:.57rem;color:var(--muted);font-weight:600;letter-spacing:.04em}
.siren-arrows-row{display:flex;justify-content:center;gap:16px;width:100%}
.siren-arrow-in{display:flex;flex-direction:column;align-items:center;gap:2px;font-size:.56rem;color:rgba(248,113,113,.5)}
.siren-center{padding:14px 22px;border-radius:10px;border:1px solid rgba(248,113,113,.35);background:rgba(248,113,113,.05);text-align:center;font-family:var(--mono)}
.siren-center-name{font-size:.82rem;color:var(--red);font-weight:700;margin-bottom:2px}
.siren-center-sub{font-size:.58rem;color:var(--muted)}
.siren-out{display:flex;align-items:center;gap:8px;margin-top:4px;font-size:.62rem;color:var(--muted)}
.siren-out-line{flex:1;border-top:1px dashed rgba(255,255,255,.1)}
.problem-charge{margin-top:52px;padding:36px 40px;border-radius:20px;border:1px solid rgba(248,113,113,.18);background:linear-gradient(135deg,rgba(248,113,113,.03),rgba(251,191,36,.02))}
.problem-charge p{font-size:1.05rem;color:var(--text);line-height:1.85;max-width:66ch}
.problem-charge .coda{font-size:.9rem;color:var(--muted);margin-top:16px;line-height:1.8;max-width:66ch}

/* ── SUBSTRATE ── */
.not-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--border);border-radius:16px;overflow:hidden;margin-top:48px}
@media(max-width:680px){.not-grid{grid-template-columns:1fr}}
.not-col{background:var(--bg2);padding:28px 24px}
.not-col-label{font-size:.65rem;font-weight:700;letter-spacing:.15em;text-transform:uppercase;margin-bottom:10px}
.not-col h3{font-size:1.4rem;margin-bottom:14px}
.not-col ul{list-style:none;display:flex;flex-direction:column;gap:7px}
.not-col li{font-size:.85rem;color:var(--muted);padding-left:14px;position:relative}
.not-col li::before{content:'';position:absolute;left:0;top:.55em;width:5px;height:5px;border-radius:50%;background:currentColor}
.not-col.hi{background:var(--bg3)}
.not-col.hi h3{background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.not-col.hi li{color:var(--text)}.not-col.hi li::before{background:var(--cyan)}
.sub-insight{margin-top:44px;padding:28px 32px;border-radius:16px;background:linear-gradient(135deg,rgba(34,211,238,.05),rgba(167,139,250,.05));border:1px solid rgba(34,211,238,.15);font-size:1.05rem;line-height:1.8;color:var(--text);max-width:72ch}

/* ── PRIMITIVES ── */
.prim-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:18px;margin-top:44px}
@media(max-width:680px){.prim-grid{grid-template-columns:1fr}}
.prim-card{background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:28px;transition:border-color .2s,transform .2s;cursor:default}
.prim-card:hover{transform:translateY(-3px)}
.prim-num{font-family:var(--mono);font-size:.68rem;font-weight:700;letter-spacing:.1em;color:var(--muted);margin-bottom:16px}
.prim-icon{width:44px;height:44px;border-radius:10px;display:flex;align-items:center;justify-content:center;margin-bottom:16px;font-size:1.3rem}
.prim-card p{font-size:.88rem;color:var(--muted);line-height:1.7}
.prim-visual{margin-top:20px}
.cell-bar{display:flex;height:30px;border-radius:6px;overflow:hidden;border:1px solid rgba(255,255,255,.07);font-size:.6rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase}
.cell-hdr{background:linear-gradient(135deg,#1a1030,#271545);color:rgba(167,139,250,.8);display:flex;align-items:center;justify-content:center;width:25%;border-right:1px solid rgba(255,255,255,.05)}
.cell-pld{background:linear-gradient(135deg,#061510,#0b1e10);color:rgba(52,211,153,.8);display:flex;align-items:center;justify-content:center;width:75%}
.lin-row{display:flex;flex-direction:column;gap:5px;margin-top:4px}
.lin-item{display:flex;align-items:center;gap:8px;padding:5px 9px;border-radius:5px;border:1px solid;font-size:.72rem;font-weight:600}
.lin-badge{font-family:var(--mono);font-size:.63rem;font-weight:700;min-width:76px}
.lin-rule{font-size:.63rem;color:var(--muted);margin-left:auto;font-family:var(--mono)}
.patch-stack{display:flex;flex-direction:column;gap:3px}
.patch-item{display:flex;align-items:center;gap:7px;padding:5px 9px;background:rgba(255,255,255,.03);border-radius:5px;border:1px solid var(--border);font-family:var(--mono);font-size:.63rem}
.patch-hash{color:var(--green);flex-shrink:0}.patch-content{color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.policy-flow{display:flex;align-items:center;gap:7px;flex-wrap:wrap}
.policy-box{padding:5px 11px;border-radius:6px;font-family:var(--mono);font-size:.63rem;font-weight:600;border:1px solid;white-space:nowrap}

/* ══ PLEXUS / IDENTITY / HATS ══ */
.plexus-section{background:var(--bg2)}
.hat-intro{display:grid;grid-template-columns:1fr 1fr;gap:48px;align-items:start;margin-top:44px}
@media(max-width:720px){.hat-intro{grid-template-columns:1fr}}
.hat-tree{background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:28px;font-family:var(--mono)}
.hat-root{display:flex;align-items:center;gap:12px;padding:14px 18px;border-radius:10px;border:1px solid rgba(34,211,238,.35);background:rgba(34,211,238,.06);margin-bottom:20px;}
.hat-root-icon{width:36px;height:36px;border-radius:8px;background:rgba(34,211,238,.12);display:flex;align-items:center;justify-content:center;font-size:1.1rem;flex-shrink:0}
.hat-root-name{font-size:.8rem;font-weight:700;color:var(--cyan)}
.hat-root-sub{font-size:.62rem;color:var(--muted);margin-top:1px}
.hat-branches{display:flex;flex-direction:column;gap:8px;padding-left:20px;border-left:1px solid var(--border2)}
.hat-branch{display:flex;flex-direction:column;gap:5px;padding:12px 14px;border-radius:9px;border:1px solid;position:relative;transition:border-color .2s;cursor:default;}
.hat-branch:hover{filter:brightness(1.15)}
.hat-branch::before{content:'';position:absolute;left:-21px;top:22px;width:20px;height:1px;background:var(--border2)}
.hat-name{font-size:.78rem;font-weight:700;display:flex;align-items:center;gap:7px}
.hat-caps{display:flex;gap:4px;flex-wrap:wrap;margin-top:5px}
.hat-cap{font-size:.58rem;padding:2px 7px;border-radius:3px;background:rgba(255,255,255,.05);border:1px solid var(--border);color:var(--muted);font-weight:600}
.hat-props{display:flex;flex-direction:column;gap:16px}
.hat-prop{padding:20px 22px;background:var(--bg);border:1px solid var(--border);border-radius:12px}
.hat-prop-label{font-size:.65rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;margin-bottom:6px}
.hat-prop-text{font-size:.875rem;color:var(--muted);line-height:1.65}
.org-chart{margin-top:36px;background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:28px}
.org-title{font-size:.68rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:20px}
.org-row{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
.org-node{display:flex;flex-direction:column;align-items:center;gap:5px;padding:12px 14px;border-radius:9px;border:1px solid;font-family:var(--mono);font-size:.7rem;text-align:center;min-width:120px;cursor:default;transition:filter .15s;}
.org-node:hover{filter:brightness(1.2)}
.org-node-name{font-weight:700}
.org-node-caps{font-size:.6rem;color:var(--muted);line-height:1.5}
.org-connector{display:flex;justify-content:center;padding:6px 0}
.org-connector::after{content:'';display:block;width:1px;height:24px;background:var(--border2)}

/* ══ CELL SHIPPING CONTAINER ══ */
.container-section{background:var(--bg)}
.layer-collapse-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:var(--border);border-radius:16px;overflow:hidden;margin-top:44px;}
@media(max-width:720px){.layer-collapse-grid{grid-template-columns:repeat(2,1fr)}}
.lc-cell{background:var(--bg2);padding:24px 20px;text-align:center}
.lc-label{font-size:.65rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:12px}
.lc-box{border-radius:8px;border:1px solid;padding:12px 10px;font-family:var(--mono);font-size:.7rem;display:flex;flex-direction:column;gap:4px;}
.lc-box-field{display:flex;justify-content:space-between;align-items:center;padding:3px 6px;border-radius:4px;background:rgba(255,255,255,.04);font-size:.6rem;}
.lc-box-field .k{color:var(--muted)}.lc-box-field .v{color:var(--text)}
.lc-collapse-label{margin-top:12px;font-size:.62rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;}
.container-insight{margin-top:36px;padding:28px 32px;border-radius:16px;background:rgba(96,165,250,.05);border:1px solid rgba(96,165,250,.2);font-size:1rem;line-height:1.8;max-width:72ch;}
.chain-visual{margin-top:36px;display:flex;align-items:center;gap:0;overflow-x:auto;padding-bottom:4px;}
.chain-cell{flex-shrink:0;display:flex;flex-direction:column;border:1px solid var(--border);border-radius:10px;overflow:hidden;font-family:var(--mono);font-size:.65rem;background:var(--bg2);width:140px;}
.chain-cell-hdr{padding:6px 10px;border-bottom:1px solid var(--border);font-size:.6rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;}
.chain-cell-body{padding:8px 10px;display:flex;flex-direction:column;gap:3px}
.chain-cell-row{display:flex;justify-content:space-between}
.chain-cell-row .k{color:var(--muted)}.chain-cell-row .v{color:var(--text)}
.chain-arrow{flex-shrink:0;display:flex;align-items:center;padding:0 8px;color:var(--muted)}
.octave-scale{margin-top:36px;background:var(--bg2);border:1px solid var(--border);border-radius:16px;padding:28px;}
.octave-title{font-size:.68rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:20px}
.octave-rows{display:flex;flex-direction:column;gap:8px}
.octave-row{display:flex;align-items:center;gap:14px}
.octave-bar-wrap{flex:1;background:rgba(255,255,255,.03);border-radius:4px;height:22px;overflow:hidden;border:1px solid var(--border)}
.octave-bar{height:100%;border-radius:3px;display:flex;align-items:center;padding:0 10px}
.octave-bar span{font-family:var(--mono);font-size:.62rem;font-weight:700;color:rgba(255,255,255,.8);white-space:nowrap}
.octave-label{font-family:var(--mono);font-size:.68rem;color:var(--muted);min-width:100px;text-align:right}
.octave-desc{font-size:.68rem;color:var(--muted);min-width:80px}

/* ══ WALLET / PKI / BRC-100 ══ */
.wallet-section{background:var(--bg2)}
.wallet-grid{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:44px}
@media(max-width:720px){.wallet-grid{grid-template-columns:1fr}}
.wallet-card{background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:28px}
.wallet-card h3{font-size:1.15rem;margin-bottom:10px}
.wallet-card p{font-size:.875rem;color:var(--muted);line-height:1.7;margin-bottom:16px}
.pki-contacts{display:flex;flex-direction:column;gap:5px}
.pki-contact{display:flex;align-items:center;gap:10px;padding:8px 12px;border-radius:7px;background:rgba(255,255,255,.03);border:1px solid var(--border);font-size:.78rem}
.pki-avatar{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:.75rem;font-weight:700;flex-shrink:0}
.pki-name{color:var(--text);font-weight:600}
.pki-cert{font-family:var(--mono);font-size:.6rem;color:var(--muted);margin-top:1px}
.pki-edge{margin-left:auto;font-size:.6rem;padding:2px 6px;border-radius:3px;background:rgba(52,211,153,.1);border:1px solid rgba(52,211,153,.25);color:var(--green);font-weight:700}
.wasm-compare{display:flex;flex-direction:column;gap:8px;margin-top:8px}
.wasm-tier{border-radius:10px;border:1px solid;padding:14px 16px}
.wasm-tier-header{display:flex;align-items:center;gap:10px;margin-bottom:10px}
.wasm-size{font-family:var(--mono);font-size:.78rem;font-weight:700;padding:3px 9px;border-radius:5px}
.wasm-tier-name{font-size:.82rem;font-weight:700}
.wasm-tier-desc{font-size:.78rem;color:var(--muted);line-height:1.6;margin-bottom:8px}
.wasm-targets{display:flex;gap:5px;flex-wrap:wrap}
.wasm-target{font-size:.62rem;padding:2px 7px;border-radius:3px;background:rgba(255,255,255,.04);border:1px solid var(--border);color:var(--muted);font-weight:600}
.brc100-bundle{background:rgba(0,0,0,.4);border:1px solid var(--border);border-radius:10px;padding:14px 16px;font-family:var(--mono);font-size:.72rem;line-height:1.8;}
.brc100-bundle .k{color:var(--muted)}.brc100-bundle .v{color:var(--cyan)}
.brc100-bundle .c{color:var(--violet)}
.interop-row{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}
.interop-pill{padding:5px 12px;border-radius:20px;font-size:.72rem;font-weight:700;background:rgba(167,139,250,.08);border:1px solid rgba(167,139,250,.25);color:var(--violet);}

/* ══ NETWORK ══ */
.network-section{background:var(--bg)}
.network-compare{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border);border-radius:16px;overflow:hidden;margin-top:44px}
@media(max-width:680px){.network-compare{grid-template-columns:1fr}}
.nc-col{padding:28px 24px;background:var(--bg2)}
.nc-col.hi{background:var(--bg3)}
.nc-col-label{font-size:.65rem;font-weight:700;letter-spacing:.15em;text-transform:uppercase;margin-bottom:12px}
.nc-item{display:flex;align-items:flex-start;gap:10px;padding:10px 0;border-bottom:1px solid var(--border);font-size:.84rem}
.nc-item:last-child{border-bottom:none}
.nc-item-icon{flex-shrink:0;width:22px;height:22px;border-radius:5px;display:flex;align-items:center;justify-content:center;font-size:.7rem;margin-top:1px}
.nc-item-text{color:var(--muted);line-height:1.5}
.nc-item-text strong{color:var(--text)}

.mesh-visual{margin-top:36px;background:var(--bg2);border:1px solid var(--border);border-radius:16px;padding:28px}
.mesh-title{font-size:.68rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:20px}
.mesh-diagram{position:relative;height:180px;display:flex;align-items:center;justify-content:center}
.mesh-node{position:absolute;display:flex;flex-direction:column;align-items:center;gap:4px}
.mesh-dot{width:44px;height:44px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:.8rem;border:1px solid;font-family:var(--mono);font-weight:700;font-size:.72rem}
.mesh-label{font-size:.58rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
.mesh-line{position:absolute;background:var(--border2);transform-origin:left center}
.bca-card{margin-top:20px;padding:22px 24px;background:var(--bg);border:1px solid rgba(167,139,250,.2);border-radius:12px}
.bca-card h3{font-size:1rem;color:var(--violet);margin-bottom:8px}
.bca-card p{font-size:.875rem;color:var(--muted);line-height:1.7;max-width:none}

/* ══ BRAIN NODE / FIELD APPS ══ */
.nodes-section{background:var(--bg2)}
.deploy-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:44px}
@media(max-width:760px){.deploy-grid{grid-template-columns:1fr}}
.deploy-card{background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:24px;transition:border-color .2s,transform .2s;cursor:default}
.deploy-card:hover{transform:translateY(-3px)}
.deploy-icon{font-size:2rem;margin-bottom:14px}
.deploy-card h3{font-size:1rem;margin-bottom:8px}
.deploy-card p{font-size:.83rem;color:var(--muted);line-height:1.65;margin-bottom:14px}
.deploy-badge{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:6px;font-family:var(--mono);font-size:.68rem;font-weight:700;border:1px solid;margin-bottom:10px}
.deploy-targets{display:flex;gap:5px;flex-wrap:wrap}
.deploy-target{font-size:.6rem;padding:2px 7px;border-radius:3px;background:rgba(255,255,255,.04);border:1px solid var(--border);color:var(--muted);font-weight:600}
.brain-callout{margin-top:36px;padding:28px 32px;border-radius:16px;background:rgba(34,211,238,.04);border:1px solid rgba(34,211,238,.18);max-width:800px}
.brain-callout h3{color:var(--cyan);font-size:1.05rem;margin-bottom:10px}
.brain-callout p{font-size:.875rem;color:var(--muted);line-height:1.75;max-width:none}

/* ══ PASKIAN LEARNING ══ */
.learning-section{background:var(--bg)}
.entail-grid{display:grid;grid-template-columns:1fr 1fr;gap:36px;align-items:start;margin-top:44px}
@media(max-width:720px){.entail-grid{grid-template-columns:1fr}}
.entail-visual{background:var(--bg2);border:1px solid var(--border);border-radius:16px;padding:28px}
.entail-title{font-size:.68rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:20px}
.entail-network{position:relative;height:220px}
.en-node{position:absolute;display:flex;flex-direction:column;align-items:center;gap:3px}
.en-dot{width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:.58rem;font-weight:700;border:1px solid;font-family:var(--mono);text-align:center;line-height:1.2}
.en-label{font-size:.55rem;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.06em;text-align:center;max-width:60px}
.entail-props{display:flex;flex-direction:column;gap:16px}
.entail-prop{padding:20px 22px;background:var(--bg2);border:1px solid var(--border);border-radius:12px}
.entail-prop-label{font-size:.65rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;margin-bottom:6px}
.entail-prop-text{font-size:.875rem;color:var(--muted);line-height:1.65}
.pask-insight{margin-top:36px;padding:28px 32px;border-radius:16px;background:linear-gradient(135deg,rgba(244,114,182,.05),rgba(167,139,250,.05));border:1px solid rgba(244,114,182,.15);font-size:1rem;line-height:1.8;max-width:72ch}

/* ══ ENTITY GRID + GOVERNANCE ══ */
.entity-section-intro{font-size:1rem;color:var(--muted);line-height:1.78;max-width:64ch;margin-bottom:36px}
.entity-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:0}
@media(max-width:860px){.entity-grid{grid-template-columns:repeat(2,1fr)}}
@media(max-width:540px){.entity-grid{grid-template-columns:1fr}}
.entity-card{background:var(--bg2);border:1px solid var(--border);border-radius:14px;padding:20px;cursor:default;transition:border-color .2s,transform .2s}
.entity-card:hover{transform:translateY(-2px)}
.entity-type-label{font-size:.57rem;font-weight:700;letter-spacing:.16em;text-transform:uppercase;margin-bottom:7px}
.entity-card h3{font-size:.92rem;font-weight:800;margin-bottom:13px;color:var(--bright);line-height:1.2}
.entity-hats{display:flex;flex-direction:column;gap:4px}
.entity-hat{display:flex;align-items:center;gap:7px;padding:5px 8px;border-radius:5px;border:1px solid var(--border);font-size:.67rem;background:rgba(255,255,255,.02)}
.entity-hat-name{font-weight:700;flex-shrink:0;min-width:0}
.entity-hat-caps{font-size:.56rem;color:var(--muted);margin-left:auto;font-family:var(--mono);text-align:right;line-height:1.4}
.entity-hat.root{border-color:rgba(34,211,238,.3);background:rgba(34,211,238,.04)}
.entity-hat.root .entity-hat-name{color:var(--cyan)}

.gov-section-intro{font-size:1rem;color:var(--muted);line-height:1.78;max-width:64ch;margin-bottom:36px}
.gov-primitives-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
@media(max-width:680px){.gov-primitives-grid{grid-template-columns:repeat(2,1fr)}}
.gov-prim{background:var(--bg2);border:1px solid var(--border);border-radius:12px;padding:18px 16px}
.gov-prim-name{font-family:var(--mono);font-size:.82rem;font-weight:700;margin-bottom:8px}
.gov-prim-lin{font-size:.57rem;font-weight:700;letter-spacing:.1em;padding:2px 7px;border-radius:3px;border:1px solid;display:inline-block;margin-bottom:9px;text-transform:uppercase}
.gov-prim-desc{font-size:.78rem;color:var(--muted);line-height:1.62}
.gov-example{margin-top:32px;padding:24px 28px;border-radius:14px;background:var(--bg2);border:1px solid var(--border)}
.gov-example-title{font-size:.62rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:16px}
.gov-flow{display:flex;flex-direction:column;gap:6px}
.gov-flow-step{display:flex;align-items:flex-start;gap:10px;padding:8px 12px;border-radius:7px;font-size:.78rem;border:1px solid var(--border);background:rgba(255,255,255,.02)}
.gov-flow-step-num{font-family:var(--mono);font-size:.65rem;font-weight:700;flex-shrink:0;margin-top:1px}
.gov-flow-step-text{color:var(--muted);line-height:1.5}
.gov-flow-step-text strong{color:var(--text)}

/* ── EXTENSIBLE ── */
.layers-section{background:var(--bg2)}
.layer-stack{display:flex;flex-direction:column;gap:10px;margin-top:44px;max-width:760px}
.layer{border-radius:12px;border:1px solid;padding:0;overflow:hidden;transition:border-color .2s,box-shadow .2s;cursor:default}
.layer:hover{box-shadow:0 0 0 1px currentColor}
.layer-header{display:flex;align-items:center;gap:14px;padding:16px 22px}
.layer-badge{font-family:var(--mono);font-size:.62rem;font-weight:700;padding:3px 8px;border-radius:4px;letter-spacing:.06em;text-transform:uppercase;white-space:nowrap}
.layer-title{font-size:.95rem;font-weight:700}.layer-sub{font-size:.78rem;color:var(--muted);margin-top:1px}
.layer-pills{display:flex;gap:5px;flex-wrap:wrap;padding:0 22px 14px}
.layer-pill{font-size:.63rem;padding:2px 8px;border-radius:20px;background:rgba(255,255,255,.04);border:1px solid var(--border);color:var(--muted);font-weight:500}
.ext-callout{margin-top:32px;border-radius:16px;border:1px solid rgba(52,211,153,.2);background:rgba(52,211,153,.04);padding:26px 30px;max-width:640px}
.ext-callout h3{color:var(--green);font-size:1.05rem;margin-bottom:8px}
.ext-callout p{font-size:.875rem;color:var(--muted);line-height:1.7}

/* ══ CROSS-CHAIN ══ */
.xchain-section{background:var(--bg2)}
.xchain-role-grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border);border-radius:16px;overflow:hidden;margin-top:44px}
@media(max-width:680px){.xchain-role-grid{grid-template-columns:1fr}}
.xr-col{padding:28px 24px;background:var(--bg3)}
.xr-col-label{font-size:.65rem;font-weight:700;letter-spacing:.15em;text-transform:uppercase;margin-bottom:12px}
.xr-item{display:flex;align-items:flex-start;gap:10px;padding:10px 0;border-bottom:1px solid var(--border);font-size:.84rem}
.xr-item:last-child{border-bottom:none}
.xr-dot{flex-shrink:0;width:8px;height:8px;border-radius:50%;margin-top:6px}
.xr-item-text{color:var(--muted);line-height:1.55}
.xr-item-text strong{color:var(--text)}
.xchain-flow{margin-top:36px;background:var(--bg);border:1px solid var(--border);border-radius:16px;padding:28px}
.xchain-flow-title{font-size:.68rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:20px}
.xchain-diagram{display:flex;align-items:center;gap:0;overflow-x:auto;padding-bottom:4px}
.xc-chain{flex-shrink:0;border-radius:10px;border:1px solid;padding:14px 16px;font-family:var(--mono);font-size:.72rem;min-width:130px;text-align:center}
.xc-chain-label{font-size:.6rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;margin-bottom:6px;color:var(--muted)}
.xc-chain-name{font-weight:700;margin-bottom:4px}
.xc-chain-role{font-size:.62rem;color:var(--muted);line-height:1.5}
.xc-arrow{flex-shrink:0;display:flex;flex-direction:column;align-items:center;padding:0 10px;gap:3px}
.xc-arrow svg{color:var(--muted)}
.xc-arrow-label{font-size:.58rem;color:var(--muted);font-weight:600;letter-spacing:.06em;text-transform:uppercase;white-space:nowrap}
.xchain-anchor{margin-top:20px;display:flex;align-items:center;gap:16px;padding:20px 24px;border-radius:12px;background:rgba(251,191,36,.04);border:1px solid rgba(251,191,36,.2)}
.xchain-anchor-icon{font-size:1.6rem;flex-shrink:0}
.xchain-anchor p{font-size:.875rem;color:var(--muted);line-height:1.7;max-width:none}
.xchain-insight{margin-top:36px;padding:28px 32px;border-radius:16px;background:linear-gradient(135deg,rgba(251,191,36,.05),rgba(52,211,153,.04));border:1px solid rgba(251,191,36,.15);font-size:1rem;line-height:1.8;max-width:72ch}

/* ── ARC ── */
.arc-section{background:radial-gradient(ellipse 80% 50% at 50% 100%,rgba(167,139,250,.05) 0%,transparent 60%),var(--bg2)}
.arc-steps{display:flex;flex-direction:column;gap:0;margin-top:48px;position:relative}
.arc-steps::before{content:'';position:absolute;left:23px;top:0;bottom:0;width:1px;background:linear-gradient(to bottom,var(--cyan),var(--violet),transparent)}
.arc-step{display:flex;gap:22px;align-items:flex-start;padding:26px 0;border-bottom:1px solid var(--border);opacity:0;transform:translateX(-14px);transition:opacity .5s ease,transform .5s ease}
.arc-step.visible{opacity:1;transform:none}
.arc-step:last-child{border-bottom:none}
.step-num{width:48px;height:48px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-family:var(--mono);font-size:.78rem;font-weight:700;flex-shrink:0;position:relative;z-index:1;border:1px solid}
.step-layer{font-size:.62rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;margin-bottom:3px}
.step-title{font-size:1.02rem;font-weight:700;color:var(--bright);margin-bottom:5px}
.step-desc{font-size:.875rem;color:var(--muted);line-height:1.7;max-width:62ch}
.step-code{margin-top:10px;padding:10px 14px;background:rgba(0,0,0,.4);border-radius:8px;border:1px solid var(--border);font-family:var(--mono);font-size:.72rem;color:var(--cyan);line-height:1.7}

.claim-block{margin-top:60px;padding:44px;border-radius:20px;background:linear-gradient(135deg,rgba(34,211,238,.07),rgba(167,139,250,.07));border:1px solid rgba(167,139,250,.2);text-align:center}
.claim-block .cl{color:var(--muted);font-size:.75rem;letter-spacing:.1em;text-transform:uppercase;margin-bottom:14px}
.claim-block h2{font-size:clamp(1.5rem,3.5vw,2.6rem);background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;margin-bottom:14px}
.claim-block p{font-size:1rem;color:var(--muted);max-width:50ch;margin:0 auto;line-height:1.75}

footer{padding:36px clamp(24px,8vw,80px);border-top:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:16px}
.footer-mark{font-size:.8rem;font-weight:800;letter-spacing:.08em;background:linear-gradient(90deg,var(--cyan),var(--violet));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.footer-text{font-size:.72rem;color:var(--muted)}
</style>
</head>
<body>

<!-- NAV -->
<nav class="topnav" id="topnav">
  <div class="nav-logo">SEMANTOS</div>
  <div class="nav-links">
    <a href="#problem">The Problem</a>
    <a href="#arc">Full Arc</a>
    <a href="#primitives">Primitives</a>
    <a href="#identity">Identity</a>
    <a href="#nodes">Nodes</a>
    <a href="#contact">Get in touch</a>
  </div>
</nav>

<!-- ═══════════ HERO ═══════════ -->
<section class="hero">
  <div class="hero-inner">
    <div class="label">The layer below every platform</div>
    <h1 class="hero-h1">
      <span class="line1">From voice</span>
      <span class="line2">to economic execution.</span>
    </h1>
    <p class="hero-lede">
      Semantos is the infrastructure layer between intent and on-chain settlement — cell-based, identity-native, blockchain-settled. Right now, the truth about your business is distributed across systems that don't agree, owned by platforms that profit from your dependency, and too fragile to survive the next API change. Semantos is the <strong>substrate</strong> — the layer below every platform — that changes the ground state.
    </p>
    <div style="margin-top:26px">
      <a href="mailto:todd@semantos.me" style="display:inline-block;font-size:.95rem;font-weight:700;padding:12px 30px;border-radius:10px;border:1px solid rgba(34,211,238,.5);color:var(--cyan);text-decoration:none;background:rgba(34,211,238,.08);transition:background .15s" onmouseover="this.style.background='rgba(34,211,238,.18)'" onmouseout="this.style.background='rgba(34,211,238,.08)'">Get in touch →</a>
    </div>
    <div class="pipeline">
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(34,211,238,.08);border-color:rgba(34,211,238,.3);color:var(--cyan)">&ldquo;fix the tap&rdquo;</div>
        <div class="pipe-tag">Voice</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(167,139,250,.08);border-color:rgba(167,139,250,.3);color:var(--violet)">hat resolved</div>
        <div class="pipe-tag">Identity</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(96,165,250,.08);border-color:rgba(96,165,250,.3);color:var(--blue)">Intent</div>
        <div class="pipe-tag">NLU</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(52,211,153,.08);border-color:rgba(52,211,153,.3);color:var(--green)">Cell created</div>
        <div class="pipe-tag">Semantic object</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(251,191,36,.08);border-color:rgba(251,191,36,.3);color:var(--amber)">Policy eval</div>
        <div class="pipe-tag">VM kernel</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(248,113,113,.08);border-color:rgba(248,113,113,.3);color:var(--red)">Dispatch</div>
        <div class="pipe-tag">Cross-domain</div>
      </div>
      <div class="pipe-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="pipe-step">
        <div class="pipe-node" style="background:rgba(167,139,250,.08);border-color:rgba(167,139,250,.3);color:var(--violet)">⛓ Anchored</div>
        <div class="pipe-tag">BSV mainnet</div>
      </div>
    </div>
  </div>
</section>

<!-- ═══════════ THE PROBLEM ═══════════ -->
<section class="section problem-section" id="problem">
  <div class="section-inner">
    <div class="label" style="color:var(--red)">The status quo</div>
    <h2 class="reveal" style="max-width:18ch">The world runs on distributed chaos.</h2>
    <div class="problem-lede reveal reveal-d1">
      Every organisation you've worked with carries the same invisible tax. Somewhere between the meeting where a decision was made, the email chain that followed, the spreadsheet that became canonical, and the platform that got updated last — the truth got distributed. Not lost. <strong>Distributed</strong>. Spread across enough systems that nobody is quite sure where it lives, who owns it, or what it actually says.
    </div>

    <div class="problem-clusters">

      <!-- CLUSTER 1: DISTRIBUTED STATE -->
      <div class="problem-cluster reveal reveal-d1">
        <div>
          <div class="problem-cluster-tag" style="color:var(--red)">Distributed state · coordination burden</div>
          <h3>Nobody knows what's real.</h3>
          <p class="problem-cluster-text">
            Across any workflow involving more than one system, truth exists in multiple copies — each drifting from the others. A job dispatched to a contractor exists as a ticket in the PM tool, a draft in the accounting platform, an unread email in someone's inbox, and a push notification on a phone. Each is a different version of what happened. There is no canonical record. Reconciliation is manual, expensive, and usually wrong after enough time passes.
          </p>
          <p class="problem-cluster-text" style="margin-top:12px">
            And when two parties need to coordinate — a business and a contractor, a landlord and a tenant, a company and a regulator — the entire coordination infrastructure has to be rebuilt from scratch. Custom integration. Custom trust model. Custom reconciliation logic. Every time.
          </p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Work order #4821 — one job, five versions</div>
          <div class="drift-grid">
            <div class="drift-row">
              <span class="drift-sys">PM tool</span>
              <span class="drift-val" style="color:var(--blue)">dispatched → in progress</span>
            </div>
            <div class="drift-row conflict">
              <span class="drift-sys">Accounting</span>
              <span class="drift-val" style="color:var(--amber)">draft invoice — awaiting PO</span>
            </div>
            <div class="drift-row conflict">
              <span class="drift-sys">Owner's inbox</span>
              <span class="drift-val" style="color:var(--muted)">approval email — unread</span>
            </div>
            <div class="drift-row">
              <span class="drift-sys">Contractor app</span>
              <span class="drift-val" style="color:var(--green)">accepted · en route</span>
            </div>
            <div class="drift-row conflict">
              <span class="drift-sys">Compliance log</span>
              <span class="drift-val" style="color:var(--red)">no record</span>
            </div>
            <div style="margin-top:10px;padding:8px 10px;border-radius:6px;border:1px dashed rgba(248,113,113,.3);font-size:.68rem;color:var(--muted);font-family:var(--mono)">
              source of truth: <span style="color:var(--red)">undefined</span>
            </div>
          </div>
        </div>
      </div>

      <!-- CLUSTER 2: SEMANTIC MEANING / AUDITABILITY -->
      <div class="problem-cluster reveal reveal-d2">
        <div>
          <div class="problem-cluster-tag" style="color:var(--amber)">Semantic degradation · auditability gap</div>
          <h3>Data crosses boundaries.<br>Meaning doesn't.</h3>
          <p class="problem-cluster-text">
            Every system boundary destroys context. "Urgent — tenant has no hot water, please fix before 5pm" becomes a priority-3 ticket, becomes a work order type code, becomes a database row with a status integer. The urgency is gone. The causal chain — who said what, what was agreed, who authorised the spend — dissolves at every handoff.
          </p>
          <p class="problem-cluster-text" style="margin-top:12px">
            Audit trails are owned by the platforms that create them. Accessible only while your subscription is active. Siloed behind their data model. When something goes wrong — a dispute, a liability question, a compliance audit — you can prove what a platform recorded. You cannot prove what actually happened.
          </p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Meaning lost in transit</div>
          <div class="meaning-pipe">
            <div class="meaning-box" style="border-color:rgba(52,211,153,.25);background:rgba(52,211,153,.04)">
              <div class="meaning-label" style="color:var(--green)">natural language</div>
              <div class="meaning-content" style="color:var(--text)">"Urgent — tap dripping, tenant has no hot water, fix before 5pm"</div>
            </div>
            <div class="meaning-step">
              <div class="meaning-drop">↓</div>
              <div style="flex:1;font-size:.6rem;color:var(--muted);padding-top:2px">boundary: NLP → ticket schema</div>
            </div>
            <div class="meaning-box" style="border-color:rgba(251,191,36,.2)">
              <div class="meaning-label" style="color:var(--amber)">ticket system</div>
              <div class="meaning-content">type: MAINTENANCE<br>priority: 3 · status: OPEN<br><span style="text-decoration:line-through;opacity:.4">urgency · context · deadline</span></div>
            </div>
            <div class="meaning-step">
              <div class="meaning-drop">↓</div>
              <div style="flex:1;font-size:.6rem;color:var(--muted);padding-top:2px">boundary: ticket → work order</div>
            </div>
            <div class="meaning-box" style="border-color:rgba(248,113,113,.2)">
              <div class="meaning-label" style="color:var(--red)">work order DB row</div>
              <div class="meaning-content">id: 4821 · code: 0x04 · status: 2<br><span style="text-decoration:line-through;opacity:.4">who approved · why urgent · tenant</span></div>
            </div>
          </div>
        </div>
      </div>

      <!-- CLUSTER 3: SIREN SERVERS -->
      <div class="problem-cluster reveal reveal-d3">
        <div>
          <div class="problem-cluster-tag" style="color:var(--pink)">Platform lock-in · dependency · data silos</div>
          <h3>Your data lives in<br>someone else's house.</h3>
          <p class="problem-cluster-text">
            Every useful platform you adopt is a sticky platform. It builds value by accumulating your data, your relationships, your workflows — in its own model, not yours — and then becomes the chokepoint. The more you depend on it, the more it can charge. Your customers live in a CRM. Your finances live in an accounting platform. Your staff live in an HR tool. Your org structure lives in an identity provider.
          </p>
          <p class="problem-cluster-text" style="margin-top:12px">
            You can export a CSV. You cannot take the meaning. Leaving costs more than staying. The platform doesn't hold your data hostage — it holds your <em>workflows</em>, your <em>history</em>, and your team's <em>muscle memory</em>. Which is worse. And the only exit is a year-long migration into another platform with the same problem.
          </p>
        </div>
        <div class="problem-visual">
          <div class="pv-title">Data gravity — flows in, barely escapes</div>
          <div class="siren-diagram">
            <div class="siren-actors">
              <div class="siren-actor"><div class="siren-actor-dot" style="border-color:rgba(96,165,250,.3)">🏢</div><div class="siren-actor-label">your org</div></div>
              <div class="siren-actor"><div class="siren-actor-dot" style="border-color:rgba(52,211,153,.3)">👥</div><div class="siren-actor-label">your staff</div></div>
              <div class="siren-actor"><div class="siren-actor-dot" style="border-color:rgba(251,191,36,.3)">🤝</div><div class="siren-actor-label">customers</div></div>
              <div class="siren-actor"><div class="siren-actor-dot" style="border-color:rgba(167,139,250,.3)">🔧</div><div class="siren-actor-label">contractors</div></div>
            </div>
            <div style="display:flex;align-items:center;justify-content:center;gap:4px;width:80%;font-size:.62rem;color:rgba(248,113,113,.5)">
              <span style="flex:1;height:1px;background:linear-gradient(90deg,transparent,rgba(248,113,113,.4))"></span>
              <span>your data flows in</span>
              <span style="flex:1;height:1px;background:linear-gradient(90deg,rgba(248,113,113,.4),transparent)"></span>
            </div>
            <div class="siren-center">
              <div class="siren-center-name">⚠ platform</div>
              <div class="siren-center-sub">your data · their model · their terms</div>
            </div>
            <div class="siren-out" style="width:80%">
              <div class="siren-out-line"></div>
              <span style="font-size:.6rem;color:var(--muted);border:1px dashed rgba(255,255,255,.1);padding:2px 8px;border-radius:4px;white-space:nowrap">↓ export.csv (meaning not included)</span>
              <div class="siren-out-line"></div>
            </div>
            <div style="font-size:.62rem;color:rgba(248,113,113,.5);text-align:center;font-style:italic">API access can be revoked. Pricing can change. Migration is your problem.</div>
          </div>
        </div>
      </div>

    </div>

    <div class="problem-charge reveal reveal-d4">
      <p>These aren't software problems you can integration-test your way out of. They're <strong>ground state problems</strong>. The fundamental layers are missing: a shared representation of what things mean that no platform owns, an audit trail that belongs to every participant equally, identity that travels with you instead of living in someone else's database, and economic commitments that are executable rather than merely promised.</p>
      <p class="coda">Every integration you build, every audit you reconstruct after the fact, every platform migration you survive — these are symptoms of absent infrastructure. The question isn't which platform to trust. The question is: what does a layer below platforms look like?</p>
    </div>
  </div>
</section>

<!-- ═══════════ FULL ARC ═══════════ -->
<section class="section arc-section" id="arc">
  <div class="section-inner">
    <div class="label">The full arc</div>
    <h2 class="reveal">Voice to economic execution.<br><span style="color:var(--muted);font-size:.55em;font-weight:400">Step by step.</span></h2>
    <div class="reveal reveal-d1" style="margin-top:16px;max-width:56ch;font-size:1rem;color:var(--muted);line-height:1.75">
      A tenant says something. An invoice is anchored on BSV mainnet. Here is every step — with no custom integration code required.
    </div>

    <div class="arc-steps" id="arcSteps">
      <div class="arc-step">
        <div class="step-num" style="background:rgba(34,211,238,.08);border-color:rgba(34,211,238,.3);color:var(--cyan)">01</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--cyan)">Voice · natural language</div>
          <div class="step-title">"The tap in the kitchen is dripping"</div>
          <div class="step-desc">Any natural language input — typed, spoken, or sent via message. No structured form. No dropdown. Just the intent.</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(167,139,250,.08);border-color:rgba(167,139,250,.3);color:var(--violet)">02</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--violet)">Core · Plexus identity</div>
          <div class="step-title">The right hat is resolved</div>
          <div class="step-desc">The tenant is acting under their <strong>tenant hat</strong> — scoped to read-only status updates and submission. The property manager has a <strong>PM hat</strong> with dispatch and approval capabilities. Neither can act outside their hat's scope.</div>
          <div class="step-code">tenant hat  → capabilities: [submit, status-read]<br>PM hat      → capabilities: [dispatch, approve, full-read]</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(96,165,250,.08);border-color:rgba(96,165,250,.3);color:var(--blue)">03</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--blue)">Runtime · intent layer</div>
          <div class="step-title">Intent classified</div>
          <div class="step-desc">Embedded into a vector, matched against the taxonomy, confidence computed. The Pask entailments network sharpens the match. Routes to <strong>services.trades.plumbing</strong> without app-specific classifier code.</div>
          <div class="step-code">taxonomy: services.trades.plumbing  ·  confidence: 0.94</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(52,211,153,.08);border-color:rgba(52,211,153,.3);color:var(--green)">04</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--green)">Core · semantic objects</div>
          <div class="step-title">A cell is created</div>
          <div class="step-desc">The maintenance request becomes a <strong>1024-byte cell</strong> — the same format it will have in memory, on the wire, in storage, and on-chain. Genesis hash set. From this moment, every change is chained.</div>
          <div class="step-code">objectKind: maintenance_request  ·  linearity: AFFINE<br>stateHash_0: SHA-256(genesis)  ·  ownerHat: tenant cert</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(251,191,36,.08);border-color:rgba(251,191,36,.3);color:var(--amber)">05</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--amber)">Core · policy engine</div>
          <div class="step-title">Business rules evaluated</div>
          <div class="step-desc">The policy is compiled to ANF bytecode and executed in the 2-PDA kernel VM. It checks the PM's hat capability — <strong>the rules travel with the cell</strong>, not the server.</div>
          <div class="step-code">(check-cap DISPATCH 0x03)  →  kernel_execute()  →  { ok: true }</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(248,113,113,.08);border-color:rgba(248,113,113,.3);color:var(--red)">06</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--red)">Extensions · cross-domain dispatch</div>
          <div class="step-title">Tradie dispatched via hat-scoped envelope</div>
          <div class="step-desc">A dispatch envelope is written — one semantic object that both the property and trades domains reference. The PM's hat controls what the tradie can see. The owner's hat gates cost approval. The tenant's hat allows only status reads. <strong>Data access is hat access.</strong></div>
          <div class="step-code">appendPatch(db, { kind: "dispatch", delta: { tradieHat, property },<br>  expectedPrevStateHash: stateHash_0 })</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(34,211,238,.08);border-color:rgba(34,211,238,.3);color:var(--cyan)">07</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--cyan)">Core · WASM wallet + BRC-100</div>
          <div class="step-title">Payment authorisation inline</div>
          <div class="step-desc">The tradie's invoice is signed with their business hat key. The owner approves with their owner hat. The BRC-100 signed bundle carries the payment authorisation alongside the identity proof — <strong>no separate payment flow</strong>.</div>
          <div class="step-code">SignedBundle: { IDENTITY_KEY: tradieHat.certId,<br>  SIGNATURE: secp256k1(invoice_hash), payload: invoice_cell }</div>
        </div>
      </div>

      <div class="arc-step">
        <div class="step-num" style="background:rgba(167,139,250,.08);border-color:rgba(167,139,250,.3);color:var(--violet)">08</div>
        <div class="step-body">
          <div class="step-layer" style="color:var(--violet)">Extensions · chain-broadcast</div>
          <div class="step-title">Cell anchored. Audit trail sealed.</div>
          <div class="step-desc">The cell — unchanged from the format it held in memory — is broadcast as a BSV transaction. It lands as a <strong>spendable on-chain UTXO</strong>: the cell data lives in the locking script, the UTXO exists on-chain until consumed. A BEEF carriage chain carries the SPV proof. The full causal chain from "the tap is dripping" to an on-chain invoice is sealed — and the invoice cell's linearity is now enforced by Bitcoin's double spend protection, not just the policy VM.</div>
        </div>
      </div>
    </div>

    <div class="claim-block reveal">
      <div class="cl">The substrate claim</div>
      <h2>Voice to economic execution.</h2>
      <p>No data silos. No platform lock-in. No integration tax. Contextual identity that travels with you, an audit trail nobody owns, and economic commitments enforced by consensus — not promised in a PDF.</p>
      <div style="margin-top:28px">
        <a href="mailto:todd@semantos.me" style="display:inline-block;font-size:.9rem;font-weight:700;padding:12px 28px;border-radius:10px;border:1px solid rgba(34,211,238,.5);color:var(--cyan);text-decoration:none;background:rgba(34,211,238,.08);transition:background .15s" onmouseover="this.style.background='rgba(34,211,238,.16)'" onmouseout="this.style.background='rgba(34,211,238,.08)'">Get in touch →</a>
      </div>
    </div>
  </div>
</section>

<!-- ═══════════ SUBSTRATE ═══════════ -->
<section class="section" id="substrate">
  <div class="section-inner">
    <div class="label">What is a substrate?</div>
    <h2 class="reveal">Not another app.<br>Not another platform.<br>The layer below both.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:60ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      Apps solve problems by adding features. Platforms solve problems by adding APIs. Neither solves the ground state problem — because they <em>are</em> the ground state problem. A substrate is different: it provides <strong>primitives</strong> that every application is composed from, owned by no platform, available to every participant.
    </div>
    <div class="not-grid reveal reveal-d2">
      <div class="not-col">
        <div class="not-col-label" style="color:var(--muted)">An app</div>
        <h3 style="color:var(--text)">Has features</h3>
        <ul>
          <li>Solves a specific problem</li><li>Fixed domain logic</li>
          <li>You configure it</li><li>Someone else's model</li>
          <li>Opaque audit trail</li>
        </ul>
      </div>
      <div class="not-col">
        <div class="not-col-label" style="color:var(--muted)">A platform</div>
        <h3 style="color:var(--text)">Has APIs</h3>
        <ul>
          <li>General-purpose tooling</li><li>You integrate into it</li>
          <li>You still build the semantics</li><li>Vendor lock-in at the edges</li>
          <li>Identity bolted on</li>
        </ul>
      </div>
      <div class="not-col hi">
        <div class="not-col-label" style="color:var(--cyan)">A substrate</div>
        <h3>Has primitives</h3>
        <ul>
          <li>Atoms of meaning and economic action</li>
          <li>Semantics built in, not bolted on</li>
          <li>Contextual identity from day one</li>
          <li>Immutable audit trail always</li>
          <li>Extends without rebuilding core</li>
        </ul>
      </div>
    </div>
    <div class="sub-insight reveal reveal-d3">
      Every system that solves a real problem ends up reinventing the same three things: <strong>understanding what someone means</strong>, <strong>proving what happened and when</strong>, and <strong>making economic commitments that can't be repudiated</strong>. These aren't features. They're infrastructure — and they belong below the application layer, not inside it. Semantos provides all three as primitives. You bring the domain logic.
    </div>
  </div>
</section>

<!-- ═══════════ PRIMITIVES ═══════════ -->
<section class="section" id="primitives" style="background:var(--bg2)">
  <div class="section-inner">
    <div class="label">The primitives</div>
    <h2 class="reveal">Four atoms.<br>Everything else is built on top.</h2>
    <div class="prim-grid">
      <div class="prim-card reveal reveal-d1" style="border-color:rgba(96,165,250,.25)">
        <div class="prim-num">01</div>
        <div class="prim-icon" style="background:rgba(96,165,250,.1);color:var(--blue)">⬡</div>
        <h3 style="color:var(--blue)">The Cell</h3>
        <p>Every unit of meaning is a <strong>1024-byte cell</strong>. It knows its type, its author, its history. It can travel anywhere — browser, server, microcontroller — and be verified on arrival. Memory, runtime, and network all use the same format.</p>
        <div class="prim-visual">
          <div class="cell-bar">
            <div class="cell-hdr">Header · 256 b</div>
            <div class="cell-pld">Semantic Payload · 768 b</div>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:4px;font-size:.6rem;color:var(--muted)">
            <span>identity · linearity · type · history</span><span>domain content</span>
          </div>
        </div>
      </div>
      <div class="prim-card reveal reveal-d2" style="border-color:rgba(248,113,113,.25)">
        <div class="prim-num">02</div>
        <div class="prim-icon" style="background:rgba(248,113,113,.1);color:var(--red)">⇌</div>
        <h3 style="color:var(--red)">Linearity</h3>
        <p>Values have <strong>flow constraints</strong> baked in. A payment-channel state can only be consumed once, like cash. A certificate must always be used, never silently dropped. The policy VM enforces this before broadcast — and on-chain, BSV's UTXO double spend protection enforces it at consensus. Two independent guarantors of the same type system.</p>
        <div class="prim-visual">
          <div class="lin-row">
            <div class="lin-item" style="border-color:rgba(248,113,113,.3);background:rgba(248,113,113,.05)">
              <span class="lin-badge" style="color:var(--red)">LINEAR</span>
              <span style="font-size:.7rem;color:var(--muted)">Exactly once — cash, capability, decision</span>
              <span class="lin-rule">DUP✗ DROP✗</span>
            </div>
            <div class="lin-item" style="border-color:rgba(251,191,36,.3);background:rgba(251,191,36,.05)">
              <span class="lin-badge" style="color:var(--amber)">AFFINE</span>
              <span style="font-size:.7rem;color:var(--muted)">At most once — draft, transfer record</span>
              <span class="lin-rule">DUP✗ DROP✓</span>
            </div>
            <div class="lin-item" style="border-color:rgba(52,211,153,.3);background:rgba(52,211,153,.05)">
              <span class="lin-badge" style="color:var(--green)">RELEVANT</span>
              <span style="font-size:.7rem;color:var(--muted)">At least once — certificate, schema, fact</span>
              <span class="lin-rule">DUP✓ DROP✗</span>
            </div>
          </div>
        </div>
      </div>
      <div class="prim-card reveal reveal-d3" style="border-color:rgba(52,211,153,.25)">
        <div class="prim-num">03</div>
        <div class="prim-icon" style="background:rgba(52,211,153,.1);color:var(--green)">◈</div>
        <h3 style="color:var(--green)">Semantic Objects</h3>
        <p>Append-only records where <strong>every change is a cryptographic patch</strong>. Nothing is deleted. Every state is provable. The audit trail is a first-class structure secured by a hash chain — not a logging afterthought.</p>
        <div class="prim-visual">
          <div class="patch-stack">
            <div class="patch-item"><span class="patch-hash">0x000…</span><span style="color:var(--muted)">genesis</span><span class="patch-content" style="margin-left:auto">{ created: maintenance_request }</span></div>
            <div class="patch-item"><span class="patch-hash">0x3f8…</span><span style="color:var(--muted)">↳</span><span class="patch-content" style="margin-left:auto">{ dispatched: tradie, urgency }</span></div>
            <div class="patch-item"><span class="patch-hash">0x9c2…</span><span style="color:var(--muted)">↳</span><span class="patch-content" style="margin-left:auto">{ completed: invoice }</span></div>
          </div>
        </div>
      </div>
      <div class="prim-card reveal reveal-d4" style="border-color:rgba(251,191,36,.25)">
        <div class="prim-num">04</div>
        <div class="prim-icon" style="background:rgba(251,191,36,.1);color:var(--amber)">⚙</div>
        <h3 style="color:var(--amber)">The Policy Engine</h3>
        <p>Business rules expressed as code, <strong>compiled to bytecode, run inside the kernel VM</strong>. The rules travel with the data — not with the server. A Lisp surface makes rules readable; ANF normalisation makes them provably correct.</p>
        <div class="prim-visual">
          <div class="policy-flow">
            <div class="policy-box" style="border-color:rgba(251,191,36,.3);color:var(--amber)">(check-cap ATTEST)</div>
            <span style="color:var(--muted)">→</span>
            <div class="policy-box" style="border-color:rgba(96,165,250,.3);color:var(--blue)">ANF bytecode</div>
            <span style="color:var(--muted)">→</span>
            <div class="policy-box" style="border-color:rgba(52,211,153,.3);color:var(--green)">{ ok: true }</div>
          </div>
          <div style="margin-top:8px;font-size:.62rem;color:var(--muted)">Rules are data. They travel with the cell, not the server.</div>
        </div>
      </div>
    </div>
  </div>
</section>
<!-- ═══════════ CELL AS SHIPPING CONTAINER ═══════════ -->
<section class="section container-section" id="container">
  <div class="section-inner">
    <div class="label">The cell</div>
    <h2 class="reveal">One format.<br>Everywhere.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      Before the standard shipping container, every port had its own crates, pallets, and cranes. The container didn't change what you could ship — it <strong>eliminated the translation layer</strong> between every mode of transport. The 1024-byte cell does the same for computation.
    </div>

    <div class="layer-collapse-grid reveal reveal-d2">
      <div class="lc-cell">
        <div class="lc-label">In memory</div>
        <div class="lc-box" style="border-color:rgba(96,165,250,.3)">
          <div class="lc-box-field"><span class="k">header</span><span class="v">256 b</span></div>
          <div class="lc-box-field"><span class="k">payload</span><span class="v">768 b</span></div>
          <div class="lc-box-field"><span class="k">total</span><span class="v">1024 b</span></div>
        </div>
        <div class="lc-collapse-label" style="color:var(--blue)">WASM stack unit</div>
      </div>
      <div class="lc-cell">
        <div class="lc-label">On the wire</div>
        <div class="lc-box" style="border-color:rgba(52,211,153,.3)">
          <div class="lc-box-field"><span class="k">header</span><span class="v">256 b</span></div>
          <div class="lc-box-field"><span class="k">payload</span><span class="v">768 b</span></div>
          <div class="lc-box-field"><span class="k">total</span><span class="v">1024 b</span></div>
        </div>
        <div class="lc-collapse-label" style="color:var(--green)">Network packet</div>
      </div>
      <div class="lc-cell">
        <div class="lc-label">In storage</div>
        <div class="lc-box" style="border-color:rgba(251,191,36,.3)">
          <div class="lc-box-field"><span class="k">header</span><span class="v">256 b</span></div>
          <div class="lc-box-field"><span class="k">payload</span><span class="v">768 b</span></div>
          <div class="lc-box-field"><span class="k">total</span><span class="v">1024 b</span></div>
        </div>
        <div class="lc-collapse-label" style="color:var(--amber)">Database row</div>
      </div>
      <div class="lc-cell">
        <div class="lc-label">On-chain</div>
        <div class="lc-box" style="border-color:rgba(167,139,250,.3)">
          <div class="lc-box-field"><span class="k">header</span><span class="v">256 b</span></div>
          <div class="lc-box-field"><span class="k">payload</span><span class="v">768 b</span></div>
          <div class="lc-box-field"><span class="k">total</span><span class="v">1024 b</span></div>
        </div>
        <div class="lc-collapse-label" style="color:var(--violet)">On-chain anchor · 1sat</div>
      </div>
    </div>

    <div class="container-insight reveal reveal-d3">
      <strong style="color:var(--blue)">Layer collapse:</strong> the memory representation, the runtime representation, the network representation, and the storage representation are all the same 1024 bytes. There is no serialisation step between layers. No ORM. No codec. The cell <em>is</em> the canonical form everywhere.
    </div>

    <!-- UTXO linearity insight -->
    <div class="reveal reveal-d3" style="margin-top:28px;display:grid;grid-template-columns:1fr 1fr;gap:16px">
      <div style="padding:24px 26px;border-radius:16px;background:rgba(251,191,36,.04);border:1px solid rgba(251,191,36,.2)">
        <div style="font-size:.65rem;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--amber);margin-bottom:10px">On-chain anchor</div>
        <div style="font-size:.875rem;color:var(--muted);line-height:1.75">
          Cells anchor to BSV not as inert <code>OP_RETURN</code> data — but as <strong style="color:var(--text)">spendable on-chain UTXOs</strong>. The cell data is embedded in the locking script. The output exists on-chain, unspent, until the cell is consumed.
        </div>
      </div>
      <div style="padding:24px 26px;border-radius:16px;background:rgba(248,113,113,.04);border:1px solid rgba(248,113,113,.2)">
        <div style="font-size:.65rem;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--red);margin-bottom:10px">UTXO existence = linearity enforcement</div>
        <div style="font-size:.875rem;color:var(--muted);line-height:1.75">
          A LINEAR cell cannot be spent twice — not because the policy VM forbids it, but because <strong style="color:var(--text)">Bitcoin's double spend protection makes it physically impossible</strong>. The UTXO model enforces the type system at the consensus layer.
        </div>
      </div>
    </div>
    <div class="reveal reveal-d4" style="margin-top:16px;padding:22px 26px;border-radius:14px;background:linear-gradient(135deg,rgba(251,191,36,.05),rgba(248,113,113,.04));border:1px solid rgba(251,191,36,.15);font-size:.925rem;color:var(--muted);line-height:1.75;max-width:72ch">
      Linearity is enforced at <strong style="color:var(--text)">two independent layers</strong>: the substrate's policy VM checks linearity constraints before broadcast; the BSV consensus layer makes violation physically impossible after. A LINEAR cell that reaches the chain exists exactly as long as its UTXO exists — and can be consumed exactly once, by exactly one spender, provably, forever.
    </div>

    <div class="reveal reveal-d3" style="margin-top:40px">
      <div class="label" style="margin-bottom:12px">Cell chaining</div>
      <div style="font-size:.925rem;color:var(--muted);line-height:1.7;max-width:62ch;margin-bottom:20px">
        When a payload is larger than 768 bytes, the cell holds a <strong>deref pointer</strong> to the next cell. Cells chain like carriages — identical format, unlimited length. The same model as a BEEF carriage chain on BSV.
      </div>
      <div class="chain-visual">
        <div class="chain-cell">
          <div class="chain-cell-hdr" style="color:var(--blue)">Cell 0 · root</div>
          <div class="chain-cell-body">
            <div class="chain-cell-row"><span class="k">phase</span><span class="v">0x00</span></div>
            <div class="chain-cell-row"><span class="k">payload</span><span class="v">768 b</span></div>
            <div class="chain-cell-row"><span class="k" style="color:var(--cyan)">→ deref</span><span class="v" style="color:var(--cyan)">Cell 1</span></div>
          </div>
        </div>
        <div class="chain-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="chain-cell">
          <div class="chain-cell-hdr" style="color:var(--green)">Cell 1 · payload cont.</div>
          <div class="chain-cell-body">
            <div class="chain-cell-row"><span class="k">type</span><span class="v">ENVELOPE</span></div>
            <div class="chain-cell-row"><span class="k">payload</span><span class="v">768 b</span></div>
            <div class="chain-cell-row"><span class="k" style="color:var(--cyan)">→ deref</span><span class="v" style="color:var(--cyan)">Cell 2</span></div>
          </div>
        </div>
        <div class="chain-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="chain-cell">
          <div class="chain-cell-hdr" style="color:var(--amber)">Cell 2 · BEEF proof</div>
          <div class="chain-cell-body">
            <div class="chain-cell-row"><span class="k">type</span><span class="v">BUMP 0x01</span></div>
            <div class="chain-cell-row"><span class="k">payload</span><span class="v">Merkle path</span></div>
            <div class="chain-cell-row"><span class="k">deref</span><span class="v">—</span></div>
          </div>
        </div>
        <div class="chain-arrow"><svg width="20" height="10" viewBox="0 0 20 10" fill="none"><path d="M0 5h16M12 1l4 4-4 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="chain-cell" style="border-style:dashed;opacity:.45">
          <div class="chain-cell-hdr">Cell N · …</div>
          <div class="chain-cell-body">
            <div class="chain-cell-row"><span class="k">unlimited</span><span class="v">scale</span></div>
          </div>
        </div>
      </div>
    </div>

    <div class="octave-scale reveal reveal-d4">
      <div class="octave-title">Octave memory — 1024-byte cells, all the way up</div>
      <div class="octave-rows">
        <div class="octave-row">
          <div class="octave-label">1 cell</div>
          <div class="octave-bar-wrap"><div class="octave-bar" style="width:2%;background:linear-gradient(90deg,rgba(34,211,238,.6),rgba(34,211,238,.3))"><span>1 KB</span></div></div>
          <div class="octave-desc" style="color:var(--cyan)">single semantic unit</div>
        </div>
        <div class="octave-row">
          <div class="octave-label">1,000 cells</div>
          <div class="octave-bar-wrap"><div class="octave-bar" style="width:6%;background:linear-gradient(90deg,rgba(96,165,250,.6),rgba(96,165,250,.3))"><span>~1 MB</span></div></div>
          <div class="octave-desc" style="color:var(--blue)">small document</div>
        </div>
        <div class="octave-row">
          <div class="octave-label">1M cells</div>
          <div class="octave-bar-wrap"><div class="octave-bar" style="width:18%;background:linear-gradient(90deg,rgba(52,211,153,.6),rgba(52,211,153,.3))"><span>~1 GB</span></div></div>
          <div class="octave-desc" style="color:var(--green)">video, dataset</div>
        </div>
        <div class="octave-row">
          <div class="octave-label">1B cells</div>
          <div class="octave-bar-wrap"><div class="octave-bar" style="width:48%;background:linear-gradient(90deg,rgba(251,191,36,.6),rgba(251,191,36,.3))"><span>~1 TB</span></div></div>
          <div class="octave-desc" style="color:var(--amber)">full org archive</div>
        </div>
        <div class="octave-row">
          <div class="octave-label">1T cells</div>
          <div class="octave-bar-wrap"><div class="octave-bar" style="width:100%;background:linear-gradient(90deg,rgba(167,139,250,.6),rgba(167,139,250,.3))"><span>~1 PB</span></div></div>
          <div class="octave-desc" style="color:var(--violet)">planetary scale</div>
        </div>
      </div>
      <div style="margin-top:16px;font-size:.8rem;color:var(--muted)">
        At every scale, the format is identical. Any peer that can read one cell can read a petabyte chain — the protocol doesn't change.
      </div>
    </div>
  </div>
</section>


<!-- ═══════════ IDENTITY / PLEXUS / HATS ═══════════ -->
<section class="section plexus-section" id="identity">
  <div class="section-inner">
    <div class="label">Plexus &amp; Identity</div>
    <h2 class="reveal">You are not one thing.<br>Identity is contextual.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      You have a business hat. A social hat. A scientist hat. Each is a scoped identity — a child of your root key cert — with its own capabilities, its own domain, its own context. <strong>Plexus</strong> is the substrate layer that makes this real.
    </div>

    <div class="hat-intro reveal reveal-d2">
      <div>
        <div class="hat-tree">
          <div class="hat-root">
            <div class="hat-root-icon">🔑</div>
            <div>
              <div class="hat-root-name">Root Identity Cert</div>
              <div class="hat-root-sub">BRC-52 · secp256k1 · continuity + recovery</div>
            </div>
          </div>
          <div class="hat-branches">
            <div class="hat-branch" style="border-color:rgba(251,191,36,.3);background:rgba(251,191,36,.04)">
              <div class="hat-name" style="color:var(--amber)">🎩 business hat</div>
              <div class="hat-caps">
                <span class="hat-cap">invoice</span><span class="hat-cap">sign</span>
                <span class="hat-cap">dispatch</span><span class="hat-cap">approve-cost</span>
              </div>
            </div>
            <div class="hat-branch" style="border-color:rgba(96,165,250,.3);background:rgba(96,165,250,.04)">
              <div class="hat-name" style="color:var(--blue)">🎩 social hat</div>
              <div class="hat-caps">
                <span class="hat-cap">message</span><span class="hat-cap">share</span><span class="hat-cap">post</span>
              </div>
            </div>
            <div class="hat-branch" style="border-color:rgba(52,211,153,.3);background:rgba(52,211,153,.04)">
              <div class="hat-name" style="color:var(--green)">🎩 scientist hat</div>
              <div class="hat-caps">
                <span class="hat-cap">publish</span><span class="hat-cap">attest</span><span class="hat-cap">peer-review</span>
              </div>
            </div>
            <div class="hat-branch" style="border-color:rgba(248,113,113,.3);background:rgba(248,113,113,.04)">
              <div class="hat-name" style="color:var(--red)">🎩 employee hat · junior dev</div>
              <div class="hat-caps">
                <span class="hat-cap">read-only</span><span class="hat-cap">own-branch</span><span class="hat-cap">create-pr</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="hat-props">
        <div class="hat-prop" style="border-color:rgba(34,211,238,.2)">
          <div class="hat-prop-label" style="color:var(--cyan)">Contextual</div>
          <div class="hat-prop-text">Each hat is a <strong>child cert derived from your root key</strong> (BRC-42 hierarchical derivation). When you act in a context, you present the hat for that context. Other participants see only what that hat exposes — never your root identity.</div>
        </div>
        <div class="hat-prop" style="border-color:rgba(167,139,250,.2)">
          <div class="hat-prop-label" style="color:var(--violet)">Continuity</div>
          <div class="hat-prop-text">Hats are <strong>deterministic from your root key</strong>. They exist on every device without sync. Lose a device — your hats are re-derived. No separate identity database to maintain or backup.</div>
        </div>
        <div class="hat-prop" style="border-color:rgba(52,211,153,.2)">
          <div class="hat-prop-label" style="color:var(--green)">Recoverability</div>
          <div class="hat-prop-text">When you issue a hat, you can <strong>set a recovery challenge</strong>. If the key is lost, the challenge allows the hat to be re-established. Org hats can have multi-sig recovery so no single person holds the keys.</div>
        </div>
      </div>
    </div>

    <!-- Org chart -->
    <div class="org-chart reveal reveal-d3">
      <div class="org-title">Org chart = hat tree · data access = capabilities</div>
      <div class="org-row">
        <div class="org-node" style="border-color:rgba(34,211,238,.35);background:rgba(34,211,238,.06);color:var(--cyan)">
          <div class="org-node-name">Company Root</div>
          <div class="org-node-caps">all capabilities</div>
        </div>
      </div>
      <div class="org-connector"></div>
      <div class="org-row">
        <div class="org-node" style="border-color:rgba(167,139,250,.3);background:rgba(167,139,250,.05);color:var(--violet)">
          <div class="org-node-name">CTO hat</div>
          <div class="org-node-caps">deploy · sign release<br>all repos · budget</div>
        </div>
        <div class="org-node" style="border-color:rgba(251,191,36,.3);background:rgba(251,191,36,.05);color:var(--amber)">
          <div class="org-node-name">Finance hat</div>
          <div class="org-node-caps">invoice · approve<br>read-ledger</div>
        </div>
        <div class="org-node" style="border-color:rgba(96,165,250,.3);background:rgba(96,165,250,.05);color:var(--blue)">
          <div class="org-node-name">PM hat</div>
          <div class="org-node-caps">dispatch · read-all<br>create-request</div>
        </div>
      </div>
      <div class="org-connector"></div>
      <div class="org-row">
        <div class="org-node" style="border-color:rgba(52,211,153,.25);background:rgba(52,211,153,.04);color:var(--green)">
          <div class="org-node-name">Senior Dev hat</div>
          <div class="org-node-caps">deploy · sign release<br>all repos · merge</div>
        </div>
        <div class="org-node" style="border-color:rgba(248,113,113,.25);background:rgba(248,113,113,.04);color:var(--red)">
          <div class="org-node-name">Junior Dev hat</div>
          <div class="org-node-caps">read-only · own branch<br>create-pr</div>
        </div>
        <div class="org-node" style="border-color:rgba(244,114,182,.25);background:rgba(244,114,182,.04);color:var(--pink)">
          <div class="org-node-name">Contractor hat</div>
          <div class="org-node-caps">scoped repo · read-only<br>expires: 90 days</div>
        </div>
      </div>
      <div style="margin-top:16px;font-size:.8rem;color:var(--muted);text-align:center">
        Updating the org chart means <strong style="color:var(--text)">issuing, revoking, or re-scoping hats</strong> — not editing a database or rebuilding an IAM system.
      </div>
    </div>

    <div class="sub-insight reveal reveal-d4" style="margin-top:36px;border-color:rgba(167,139,250,.2);background:linear-gradient(135deg,rgba(167,139,250,.05),rgba(34,211,238,.04))">
      <strong>Hat lifecycle is a semantic object.</strong> A hat is a BRC-52 certificate — a defined structure of pubkey, parentCertId, childIndex, capabilities, and domain scope. That certificate is <em>carried as the payload of a cell</em>: same 1024-byte format, RELEVANT linearity (a cert must always be presentable, never silently dropped), hash-chained history of every issuance, grant, and revocation. The hat and the cell are distinct — the hat is the identity credential, the cell is the format in which it lives, travels, and is audited. Data access management is not a separate system. It is the same cell model applied to identity.
    </div>

    <!-- ── ENTITY TYPES ── -->
    <div style="margin-top:72px" class="reveal">
      <div class="label" style="margin-bottom:18px">Every entity type is a hat tree</div>
      <p class="entity-section-intro">
        Hats aren't just for individuals. Every entity that needs to act, delegate authority, receive assets, vote, or be held accountable maps to a hat tree. The root cert is the entity's identity. Every role, every right, every limit is a child hat with scoped capabilities. Constitutions, trust deeds, articles of incorporation — all become executable policy rather than documents people argue about later.
      </p>
      <div class="entity-grid" style="grid-template-columns:repeat(2,1fr);max-width:700px">

        <div class="entity-card reveal reveal-d1" style="border-color:rgba(96,165,250,.25)">
          <div class="entity-type-label" style="color:var(--blue)">Corporation</div>
          <h3>Company</h3>
          <div class="entity-hats">
            <div class="entity-hat root"><span class="entity-hat-name">Company root</span><span class="entity-hat-caps">all authority</span></div>
            <div class="entity-hat" style="border-color:rgba(167,139,250,.25)"><span class="entity-hat-name" style="color:var(--violet)">Director</span><span class="entity-hat-caps">sign · approve · appoint</span></div>
            <div class="entity-hat" style="border-color:rgba(251,191,36,.2)"><span class="entity-hat-name" style="color:var(--amber)">Shareholder</span><span class="entity-hat-caps">vote (weighted) · dividend</span></div>
            <div class="entity-hat" style="border-color:rgba(52,211,153,.2)"><span class="entity-hat-name" style="color:var(--green)">Secretary</span><span class="entity-hat-caps">file · record · certify</span></div>
            <div class="entity-hat"><span class="entity-hat-name" style="color:var(--muted)">Auditor</span><span class="entity-hat-caps">read-all · attest only</span></div>
          </div>
        </div>

        <div class="entity-card reveal reveal-d2" style="border-color:rgba(244,114,182,.25)">
          <div class="entity-type-label" style="color:var(--pink)">Cooperative</div>
          <h3>Member-Owned Cooperative</h3>
          <div class="entity-hats">
            <div class="entity-hat root"><span class="entity-hat-name">Coop root</span><span class="entity-hat-caps">governed by rules</span></div>
            <div class="entity-hat" style="border-color:rgba(244,114,182,.3)"><span class="entity-hat-name" style="color:var(--pink)">Member</span><span class="entity-hat-caps">vote (1 member = 1 vote)</span></div>
            <div class="entity-hat" style="border-color:rgba(251,191,36,.2)"><span class="entity-hat-name" style="color:var(--amber)">Board</span><span class="entity-hat-caps">execute · sign · manage</span></div>
            <div class="entity-hat" style="border-color:rgba(52,211,153,.2)"><span class="entity-hat-name" style="color:var(--green)">Worker-member</span><span class="entity-hat-caps">vote + labour rights</span></div>
            <div class="entity-hat"><span class="entity-hat-name" style="color:var(--muted)">Observer</span><span class="entity-hat-caps">read-all · no vote</span></div>
          </div>
        </div>

      </div>
      <div style="margin-top:14px;font-size:.8rem;color:var(--muted)">Same pattern applies to trusts, estates, DAOs, constitutional bodies — any entity whose authority structure can be expressed as a tree of scoped capabilities.</div>
    </div>

    <!-- ── GOVERNANCE PRIMITIVES ── -->
    <div style="margin-top:72px" class="reveal">
      <div class="label" style="margin-bottom:18px">Governance as typed cells</div>
      <p class="gov-section-intro">
        Governance is not bolted on — it is built into the type system. Proposals, ballots, votes, stakes, and vetoes are all typed cells with linearity constraints. A vote is LINEAR: cast exactly once. A ballot is AFFINE: can be abstained but never duplicated. The kernel enforces these constraints before anything reaches the chain; BSV's double-spend protection enforces them again at consensus. Two independent layers, same guarantee.
      </p>

      <!-- Three governance levels -->
      <div class="reveal reveal-d2" style="margin-top:36px;padding:28px 32px;background:var(--bg2);border:1px solid var(--border);border-radius:14px">
        <div style="font-size:.7rem;font-weight:700;letter-spacing:.12em;color:var(--cyan);margin-bottom:16px;text-transform:uppercase">Three governance levels — constraints flow down, disputes escalate up</div>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px">
          <div style="padding:16px;background:var(--bg3);border-radius:10px;border-left:3px solid var(--violet)">
            <div style="font-size:.7rem;font-weight:700;color:var(--violet);margin-bottom:6px">L0 — Platform</div>
            <div style="font-size:.78rem;color:var(--muted);line-height:1.6">The constitution — RELEVANT linearity, always accessible, never silently dropped. Changing these rules requires a formal breaking-change ballot meeting the platform quorum threshold. Governed by the Semantos core team multi-sig hat.</div>
          </div>
          <div style="padding:16px;background:var(--bg3);border-radius:10px;border-left:3px solid var(--blue)">
            <div style="font-size:.7rem;font-weight:700;color:var(--blue);margin-bottom:6px">L1 — Author</div>
            <div style="font-size:.78rem;color:var(--muted);line-height:1.6">Declares who can propose patches to a grammar — the author alone, a contributor ballot, or open vote. Also sets trust class, proof requirements, and who holds execution authority over grammar objects.</div>
          </div>
          <div style="padding:16px;background:var(--bg3);border-radius:10px;border-left:3px solid var(--green)">
            <div style="font-size:.7rem;font-weight:700;color:var(--green);margin-bottom:6px">L2 — Consumer</div>
            <div style="font-size:.78rem;color:var(--muted);line-height:1.6">Per-node binding — AFFINE, one per node. Pins the grammar version the node runs, holds encrypted credentials (never plain text), and can override taxonomy mappings locally without affecting other participants.</div>
          </div>
        </div>
      </div>

      <div class="gov-example reveal reveal-d4">
        <div class="gov-example-title">Example — cooperative budget approval</div>
        <div class="gov-flow">
          <div class="gov-flow-step" style="border-color:rgba(96,165,250,.2)">
            <span class="gov-flow-step-num" style="color:var(--blue)">01</span>
            <div class="gov-flow-step-text"><strong>Board hat</strong> submits a RELEVANT proposal cell: "Allocate $40,000 to equipment fund." Phase: DRAFT → OPEN. Proposal cell hash-chained to board's hat cert.</div>
          </div>
          <div class="gov-flow-step" style="border-color:rgba(251,191,36,.2)">
            <span class="gov-flow-step-num" style="color:var(--amber)">02</span>
            <div class="gov-flow-step-text">Each <strong>member hat</strong> receives one AFFINE ballot cell. 47 of 60 members cast theirs. 13 are dropped (abstain). No member can cast twice — AFFINE linearity enforced by the kernel before the ballot reaches the chain.</div>
          </div>
          <div class="gov-flow-step" style="border-color:rgba(248,113,113,.2)">
            <span class="gov-flow-step-num" style="color:var(--red)">03</span>
            <div class="gov-flow-step-text"><strong>Quorum policy</strong> evaluates: 47 votes ≥ threshold (50% of eligible = 30). Tally: 39 FOR, 8 AGAINST. Majority met. Proposal cell phase transitions: OPEN → ENACTED. Every vote, every hat, the full audit chain — on record.</div>
          </div>
          <div class="gov-flow-step" style="border-color:rgba(52,211,153,.2)">
            <span class="gov-flow-step-num" style="color:var(--green)">04</span>
            <div class="gov-flow-step-text"><strong>Treasury cell</strong> dispatched — a LINEAR economic cell representing the $40,000 allocation. Anchored on BSV. The decision and the money are bound together in a single hash chain. The audit trail is complete before anyone files a report.</div>
          </div>
        </div>
      </div>
    </div>

  </div>
</section>

<!-- ═══════════ WALLET / PKI / BRC-100 ═══════════ -->
<section class="section wallet-section" id="wallet">
  <div class="section-inner">
    <div class="label">Wallet &amp; Payments</div>
    <h2 class="reveal">Payments in any browser.<br>No plugin required.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      Two WASM profiles, one substrate. Every message is a signed, payment-capable bundle. Open a tab — you have a wallet.
    </div>

    <div class="wallet-grid">
      <!-- Contacts / PKI -->
      <div class="wallet-card reveal reveal-d1" style="border-color:rgba(52,211,153,.25)">
        <div class="prim-icon" style="background:rgba(52,211,153,.1);color:var(--green);margin-bottom:16px">📇</div>
        <h3 style="color:var(--green)">The Contacts Book is a PKI</h3>
        <p>Your contacts are their <strong>root certs</strong>. You establish an ECDH edge between your key and theirs once — a shared secret derived locally, never transmitted. From that point, every message between you is end-to-end signed and verifiable.</p>
        <div class="pki-contacts" style="margin-top:16px">
          <div class="pki-contact">
            <div class="pki-avatar" style="background:rgba(251,191,36,.15);color:var(--amber)">A</div>
            <div><div class="pki-name">Alice (PM)</div><div class="pki-cert">cert: 0x3a8f…b12 · BRC-52</div></div>
            <div class="pki-edge">ECDH ✓</div>
          </div>
          <div class="pki-contact">
            <div class="pki-avatar" style="background:rgba(96,165,250,.15);color:var(--blue)">B</div>
            <div><div class="pki-name">Bob (Tradie)</div><div class="pki-cert">cert: 0x7c2e…44a · BRC-52</div></div>
            <div class="pki-edge">ECDH ✓</div>
          </div>
          <div class="pki-contact" style="opacity:.5">
            <div class="pki-avatar" style="background:rgba(248,113,113,.15);color:var(--red)">C</div>
            <div><div class="pki-name">Carol (Owner)</div><div class="pki-cert">cert: 0x1d9b…e83 · BRC-52</div></div>
            <div class="pki-edge" style="opacity:.6">pending</div>
          </div>
        </div>
      </div>

      <!-- WASM wallet -->
      <div class="wallet-card reveal reveal-d2" style="border-color:rgba(34,211,238,.25)">
        <div class="prim-icon" style="background:rgba(34,211,238,.1);color:var(--cyan);margin-bottom:16px">💳</div>
        <h3 style="color:var(--cyan)">Two WASM Profiles</h3>
        <p>The cell-engine compiles to two WASM profiles optimised for different deployment targets — from a browser tab to a federation node.</p>
        <div class="wasm-compare">
          <div class="wasm-tier" style="border-color:rgba(34,211,238,.25);background:rgba(34,211,238,.03)">
            <div class="wasm-tier-header">
              <div class="wasm-size" style="background:rgba(34,211,238,.1);color:var(--cyan);border:1px solid rgba(34,211,238,.3)">29 KB</div>
              <div class="wasm-tier-name" style="color:var(--cyan)">Embedded — host crypto</div>
            </div>
            <div class="wasm-tier-desc">Uses the <strong>host platform's crypto</strong> via WASM imports — no cryptographic primitives compiled in. The host (browser SubtleCrypto, Flutter, ESP32 hardware) provides secp256k1, SHA-256, and RIPEMD-160. Ultra-compact.</div>
            <div class="wasm-targets">
              <span class="wasm-target">Chrome / Safari</span>
              <span class="wasm-target">Flutter mobile</span>
              <span class="wasm-target">ESP32 / IoT</span>
              <span class="wasm-target">Embedded MCU</span>
            </div>
          </div>
          <div class="wasm-tier" style="border-color:rgba(167,139,250,.25);background:rgba(167,139,250,.03)">
            <div class="wasm-tier-header">
              <div class="wasm-size" style="background:rgba(167,139,250,.1);color:var(--violet);border:1px solid rgba(167,139,250,.3)">183 KB</div>
              <div class="wasm-tier-name" style="color:var(--violet)">Full — native crypto</div>
            </div>
            <div class="wasm-tier-desc">Bundles <strong>native secp256k1, SHA-256, RIPEMD-160, and SPV verification</strong> compiled directly into the WASM binary. No external crypto dependency — runs anywhere a WASM runtime exists.</div>
            <div class="wasm-targets">
              <span class="wasm-target">brain node</span>
              <span class="wasm-target">Federation peer</span>
              <span class="wasm-target">Server-side</span>
              <span class="wasm-target">Full node</span>
            </div>
          </div>
        </div>
      </div>

      <!-- BRC-100 bundle -->
      <div class="wallet-card reveal reveal-d3" style="border-color:rgba(167,139,250,.25);grid-column:1 / -1">
        <div class="prim-icon" style="background:rgba(167,139,250,.1);color:var(--violet);margin-bottom:16px">🤝</div>
        <h3 style="color:var(--violet)">BRC-100 Interoperability</h3>
        <p style="max-width:none">Any system that speaks <strong>BRC-100</strong> can verify, sign, and accept payments from a Semantos client — and vice versa. It is an open standard, not a Semantos lock-in. Every message between nodes is a BRC-100 signed bundle: a CBOR payload wrapped in a verifiable envelope.</p>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:20px">
          <div>
            <div class="brc100-bundle">
              <div><span class="k">SignedBundle {</span></div>
              <div style="padding-left:14px"><span class="k">headers: </span><span class="v">{</span></div>
              <div style="padding-left:28px"><span class="c">IDENTITY_KEY</span><span class="k">: </span><span class="v">certId</span></div>
              <div style="padding-left:28px"><span class="c">NONCE</span><span class="k">: </span><span class="v">replay protection</span></div>
              <div style="padding-left:28px"><span class="c">TIMESTAMP</span><span class="k">: </span><span class="v">when signed</span></div>
              <div style="padding-left:28px"><span class="c">SIGNATURE</span><span class="k">: </span><span class="v">secp256k1</span></div>
              <div style="padding-left:14px"><span class="v">}</span></div>
              <div style="padding-left:14px"><span class="k">payload: </span><span class="v">Uint8Array (CBOR)</span></div>
              <div><span class="k">}</span></div>
            </div>
          </div>
          <div style="display:flex;flex-direction:column;gap:10px;justify-content:center">
            <div style="font-size:.875rem;color:var(--muted);line-height:1.65"><strong>Any port, any carrier.</strong> A BSV wallet, a Semantos node, a third-party service, or a browser tab can all participate in the same economic transaction — because they all agree on BRC-100.</div>
            <div>
              <div style="font-size:.68rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:8px">Compatible with</div>
              <div class="interop-row">
                <span class="interop-pill">BSV wallets</span>
                <span class="interop-pill">ARC broadcast</span>
                <span class="interop-pill">MAP Protocol</span>
                <span class="interop-pill">BEEF SPV</span>
                <span class="interop-pill">Any BRC-100 peer</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- ═══════════ THE NETWORK ═══════════ -->
<section class="section network-section" id="network">
  <div class="section-inner">
    <div class="label">The network layer</div>
    <h2 class="reveal">Cells don't need HTTPS.<br>They carry their own proof.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      HTTPS exists to solve trust, identity, and integrity for inherently untrustworthy payloads. A cell already has all three — so the transport layer can be anything, including the fastest protocols we have.
    </div>

    <div class="network-compare reveal reveal-d2">
      <div class="nc-col">
        <div class="nc-col-label" style="color:var(--muted)">Traditional HTTPS world</div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(248,113,113,.1);color:var(--red)">🔒</div>
          <div class="nc-item-text"><strong>TLS + CAs</strong> — trust delegated to a certificate authority. The payload is naked; the channel is trusted.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(248,113,113,.1);color:var(--red)">🌐</div>
          <div class="nc-item-text"><strong>DNS required</strong> — you address a server by name, and DNS resolves it. No DNS, no connection.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(248,113,113,.1);color:var(--red)">🔄</div>
          <div class="nc-item-text"><strong>TCP with retry</strong> — reliable delivery is handled by the transport. Lossy networks require retransmission logic.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(248,113,113,.1);color:var(--red)">🏠</div>
          <div class="nc-item-text"><strong>NAT + central relay</strong> — true peer-to-peer is impossible without NAT traversal hacks or a relay server.</div>
        </div>
      </div>
      <div class="nc-col hi">
        <div class="nc-col-label" style="color:var(--cyan)">Cell network</div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(34,211,238,.1);color:var(--cyan)">🔑</div>
          <div class="nc-item-text"><strong>Cell carries its own auth</strong> — BRC-52 cert in the header. No CA. No TLS. Verify the payload, not the channel.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(34,211,238,.1);color:var(--cyan)">🔗</div>
          <div class="nc-item-text"><strong>prevHash chain</strong> — each cell carries a hash of the previous state. Gaps in the chain reveal exactly which cells were dropped on a lossy wire.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(34,211,238,.1);color:var(--cyan)">📡</div>
          <div class="nc-item-text"><strong>UDP multicast mesh</strong> — fire one broadcast, all peers receive it. Missing cells are detected by prevHash gap; peers request "cells from hash X onward." No TCP retry logic needed.</div>
        </div>
        <div class="nc-item">
          <div class="nc-item-icon" style="background:rgba(34,211,238,.1);color:var(--cyan)">🌐</div>
          <div class="nc-item-text"><strong>BCA → IPv6 address</strong> — a Bitcoin Certified Address derived from the secp256k1 key maps to an IPv6 address. True peer-to-peer without NAT, with ECDH encryption from the contacts PKI.</div>
        </div>
      </div>
    </div>

    <div class="mesh-visual reveal reveal-d3">
      <div class="mesh-title">UDP multicast mesh — prevHash gap recovery</div>
      <div style="display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap">
        <div style="flex:1;min-width:240px">
          <div style="font-size:.875rem;color:var(--muted);line-height:1.75;margin-bottom:14px">
            Because every cell carries <code>prevStateHash</code>, peers can detect missing cells on arrival — even over UDP. There is no reliable connection to maintain.
          </div>
          <div style="display:flex;flex-direction:column;gap:6px">
            <div style="display:flex;align-items:center;gap:10px;padding:9px 13px;border-radius:8px;background:rgba(52,211,153,.05);border:1px solid rgba(52,211,153,.2);font-size:.8rem">
              <span style="color:var(--green);font-family:var(--mono);font-weight:700">cell arrives</span>
              <span style="color:var(--muted)">→ check prevHash matches last known state</span>
            </div>
            <div style="display:flex;align-items:center;gap:10px;padding:9px 13px;border-radius:8px;background:rgba(251,191,36,.05);border:1px solid rgba(251,191,36,.2);font-size:.8rem">
              <span style="color:var(--amber);font-family:var(--mono);font-weight:700">gap detected</span>
              <span style="color:var(--muted)">→ request "cells from hash 0x3f8… onward"</span>
            </div>
            <div style="display:flex;align-items:center;gap:10px;padding:9px 13px;border-radius:8px;background:rgba(34,211,238,.05);border:1px solid rgba(34,211,238,.2);font-size:.8rem">
              <span style="color:var(--cyan);font-family:var(--mono);font-weight:700">peer responds</span>
              <span style="color:var(--muted)">→ targeted backfill, chain intact</span>
            </div>
          </div>
        </div>
        <div style="flex:0 0 auto">
          <div style="font-size:.68rem;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:12px">BCA + IPv6 true p2p</div>
          <div style="background:rgba(0,0,0,.3);border:1px solid var(--border);border-radius:10px;padding:14px 16px;font-family:var(--mono);font-size:.72rem;line-height:1.8">
            <div style="color:var(--muted)">secp256k1 pubkey</div>
            <div style="color:var(--cyan);padding-left:12px">↓ BCA derivation</div>
            <div style="color:var(--violet)">IPv6 address (128 bit)</div>
            <div style="color:var(--cyan);padding-left:12px">↓ ECDH from contacts PKI</div>
            <div style="color:var(--green)">encrypted p2p channel</div>
            <div style="color:var(--muted);margin-top:4px;font-size:.65rem">no DNS · no NAT · no CA</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- ═══════════ BRAIN NODE & FIELD APPS ═══════════ -->
<section class="section nodes-section" id="nodes">
  <div class="section-inner">
    <div class="label">Brain node &amp; field apps</div>
    <h2 class="reveal">One substrate.<br>Every target from IoT to cloud.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      The same cell engine — compiled to two WASM profiles — runs on a $4 microcontroller, a Flutter mobile app, and a federation node. The protocol doesn't change. The deployment does.
    </div>

    <div class="deploy-grid">
      <!-- Brain node -->
      <div class="deploy-card reveal reveal-d1" style="border-color:rgba(34,211,238,.3)">
        <div class="deploy-icon">🧠</div>
        <div class="deploy-badge" style="border-color:rgba(167,139,250,.3);color:var(--violet);background:rgba(167,139,250,.06)">
          <span>183 KB WASM</span><span style="color:var(--muted)">native crypto</span>
        </div>
        <h3 style="color:var(--cyan)">Brain node</h3>
        <p>A federation node running the full Semantos stack — cell engine, Pask learning kernel, relay, and NLU pipeline. Acts as a <strong>peer, not a server</strong>. No central authority. Brain nodes form the backbone of the UDP multicast mesh.</p>
        <div class="deploy-targets">
          <span class="deploy-target">Linux server</span>
          <span class="deploy-target">VPS / cloud</span>
          <span class="deploy-target">Raspberry Pi</span>
          <span class="deploy-target">On-premise</span>
        </div>
      </div>

      <!-- Flutter field app -->
      <div class="deploy-card reveal reveal-d2" style="border-color:rgba(96,165,250,.3)">
        <div class="deploy-icon">📱</div>
        <div class="deploy-badge" style="border-color:rgba(34,211,238,.3);color:var(--cyan);background:rgba(34,211,238,.06)">
          <span>29 KB WASM</span><span style="color:var(--muted)">host crypto</span>
        </div>
        <h3 style="color:var(--blue)">Flutter / Dart field apps</h3>
        <p>Cross-platform Flutter apps for iOS, Android, and desktop use the 29 KB embedded WASM with <strong>host-provided crypto</strong>. The platform's own cryptographic APIs are injected via WASM imports — giving full signing and verification capability in a minimal footprint.</p>
        <div class="deploy-targets">
          <span class="deploy-target">iOS</span>
          <span class="deploy-target">Android</span>
          <span class="deploy-target">macOS / Windows</span>
          <span class="deploy-target">Dart native</span>
        </div>
      </div>

      <!-- Embedded -->
      <div class="deploy-card reveal reveal-d3" style="border-color:rgba(52,211,153,.3)">
        <div class="deploy-icon">🔌</div>
        <div class="deploy-badge" style="border-color:rgba(34,211,238,.3);color:var(--cyan);background:rgba(34,211,238,.06)">
          <span>29 KB WASM</span><span style="color:var(--muted)">host crypto</span>
        </div>
        <h3 style="color:var(--green)">Embedded targets</h3>
        <p>IoT devices and microcontrollers use the same 29 KB embedded WASM. Hardware crypto engines (ESP32, STM32, nRF52) provide secp256k1 and SHA-256 via the WASM import interface. A sensor in the field is a <strong>first-class Semantos peer</strong> — signing its own cells.</p>
        <div class="deploy-targets">
          <span class="deploy-target">ESP32</span>
          <span class="deploy-target">STM32</span>
          <span class="deploy-target">nRF52840</span>
          <span class="deploy-target">Any WASM-capable MCU</span>
        </div>
      </div>
    </div>

    <div class="brain-callout reveal reveal-d4">
      <h3>Federated by design — no central node</h3>
      <p>Brain nodes are peers. They relay cells between clients, anchor to BSV, run the Pask learning kernel, and serve as entry points to the mesh — but none of them is authoritative. If a node goes offline, the mesh routes around it. The contacts book PKI means nodes authenticate each other without any central registry. Add a node, and the network grows. Remove one, and nothing breaks.</p>
    </div>
  </div>
</section>

<!-- ═══════════ PASKIAN LEARNING ═══════════ -->
<section class="section learning-section" id="learning">
  <div class="section-inner">
    <div class="label">Adaptive learning</div>
    <h2 class="reveal">The system learns<br>about itself.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      Semantos includes a deterministic learning kernel — built on Gordon Pask's conversation theory — that runs on cells, not a separate ML pipeline. Every interaction is a cell. Every domain is a namespace. The system builds an <strong>entailments network</strong> — a live map of what things mean relative to each other — from the cells it processes.
    </div>

    <div class="entail-grid reveal reveal-d2">
      <div class="entail-visual">
        <div class="entail-title">Entailments network — cells under domains</div>
        <div style="display:flex;flex-direction:column;gap:8px">
          <div style="padding:12px 16px;border-radius:9px;border:1px solid rgba(244,114,182,.25);background:rgba(244,114,182,.04);font-size:.83rem;color:var(--muted);line-height:1.65">
            <strong style="color:var(--pink)">Domain: services.trades.plumbing</strong><br>
            Cells observed: maintenance_request, dispatch, invoice, completion<br>
            <span style="font-family:var(--mono);font-size:.7rem;color:var(--violet)">entails → urgency_classification, tradie_matching, cost_approval</span>
          </div>
          <div style="padding:12px 16px;border-radius:9px;border:1px solid rgba(96,165,250,.25);background:rgba(96,165,250,.04);font-size:.83rem;color:var(--muted);line-height:1.65">
            <strong style="color:var(--blue)">Domain: identity.hat.tenant</strong><br>
            Cells observed: submit, status-read, payment-auth<br>
            <span style="font-family:var(--mono);font-size:.7rem;color:var(--violet)">entails → capability_boundary, context_scope</span>
          </div>
          <div style="padding:12px 16px;border-radius:9px;border:1px solid rgba(52,211,153,.25);background:rgba(52,211,153,.04);font-size:.83rem;color:var(--muted);line-height:1.65">
            <strong style="color:var(--green)">Cross-domain entailment</strong><br>
            <span style="font-family:var(--mono);font-size:.7rem;color:var(--cyan)">services.trades ⟺ finance.invoice ⟺ identity.hat.owner</span><br>
            System learns: approval gate requires owner hat when cost &gt; threshold
          </div>
        </div>
      </div>

      <div class="entail-props">
        <div class="entail-prop" style="border-color:rgba(244,114,182,.2)">
          <div class="entail-prop-label" style="color:var(--pink)">Deterministic kernel</div>
          <div class="entail-prop-text">The Pask learning kernel makes <strong>no host clock reads and has no external side effects</strong>. Given the same sequence of cells, it always produces the same entailments network. Reproducible, auditable, verifiable — just like the cells it learns from.</div>
        </div>
        <div class="entail-prop" style="border-color:rgba(167,139,250,.2)">
          <div class="entail-prop-label" style="color:var(--violet)">Smarter intent routing</div>
          <div class="entail-prop-text">As the system accumulates cells, the intent classifier gets better at routing novel queries to the right domain. The entailments network acts as <strong>a continuously refined semantic map</strong> — no retraining cycle, no ML pipeline, just cells.</div>
        </div>
        <div class="entail-prop" style="border-color:rgba(34,211,238,.2)">
          <div class="entail-prop-label" style="color:var(--cyan)">Self-modelling</div>
          <div class="entail-prop-text">The entailments network runs <strong>on cells under domains</strong> — meaning the system's model of itself is stored using the same substrate it models. The learning state is inspectable, hash-chained, and can be anchored on-chain like any other cell.</div>
        </div>
      </div>
    </div>

    <div class="pask-insight reveal reveal-d3">
      Most AI systems treat learning as a separate pipeline that runs offline and produces a model you deploy. Semantos treats learning as a <strong>continuous substrate process</strong> — every cell that flows through the system contributes to the entailments network. The substrate teaches itself, in the same format it uses for everything else.
    </div>
  </div>
</section>

<!-- ═══════════ EXTENSIBLE ═══════════ -->
<section class="section layers-section" id="extensible">
  <div class="section-inner">
    <div class="label">Extensible by design</div>
    <h2 class="reveal">Add a domain.<br>Don't rebuild the substrate.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:60ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      The layer model is strict: each tier can only depend on the tiers below it. New domains slot into Extensions — they inherit all primitives, identity, and payments without touching the kernel.
    </div>
    <div class="layer-stack reveal reveal-d2">
      <div class="layer" style="border-color:rgba(251,191,36,.3);color:var(--amber)">
        <div class="layer-header">
          <div class="layer-badge" style="background:rgba(251,191,36,.1);color:var(--amber)">APPS · Tier 3</div>
          <div><div class="layer-title" style="color:var(--amber)">Standalone Products</div><div class="layer-sub">What users interact with</div></div>
        </div>
        <div class="layer-pills"><span class="layer-pill">Oddjobz (trades)</span><span class="layer-pill">Property Management</span><span class="layer-pill">Loom Workbench</span><span class="layer-pill">Your vertical here</span></div>
      </div>
      <div class="layer" style="border-color:rgba(52,211,153,.3);color:var(--green)">
        <div class="layer-header">
          <div class="layer-badge" style="background:rgba(52,211,153,.1);color:var(--green)">EXTENSIONS · Tier 2</div>
          <div><div class="layer-title" style="color:var(--green)">Domain Algorithms</div><div class="layer-sub">Where new verticals are added — the extension point</div></div>
        </div>
        <div class="layer-pills"><span class="layer-pill">trades / oddjobz</span><span class="layer-pill">property dispatch</span><span class="layer-pill">finance workflow</span><span class="layer-pill">metering + payments</span><span class="layer-pill">calendar + booking</span><span class="layer-pill">+ your domain</span></div>
      </div>
      <div class="layer" style="border-color:rgba(96,165,250,.3);color:var(--blue)">
        <div class="layer-header">
          <div class="layer-badge" style="background:rgba(96,165,250,.1);color:var(--blue)">RUNTIME · Tier 1</div>
          <div><div class="layer-title" style="color:var(--blue)">Entry Surfaces</div><div class="layer-sub">CLI, NLU pipeline, federation, node daemon</div></div>
        </div>
        <div class="layer-pills"><span class="layer-pill">shell / REPL / Lisp</span><span class="layer-pill">intent / NLU</span><span class="layer-pill">session-protocol</span></div>
      </div>
      <div class="layer" style="border-color:rgba(167,139,250,.3);color:var(--violet)">
        <div class="layer-header">
          <div class="layer-badge" style="background:rgba(167,139,250,.1);color:var(--violet)">CORE · Tier 0</div>
          <div><div class="layer-title" style="color:var(--violet)">Kernel Foundation</div><div class="layer-sub">Primitives, identity, wallet — you never change this</div></div>
        </div>
        <div class="layer-pills"><span class="layer-pill">cell-engine (Zig WASM)</span><span class="layer-pill">semantic-objects</span><span class="layer-pill">Plexus / hats</span><span class="layer-pill">WASM wallet</span><span class="layer-pill">Pask learning kernel</span></div>
      </div>
    </div>
    <div class="ext-callout reveal reveal-d3">
      <h3>A new vertical takes days, not months.</h3>
      <p>You write domain logic against the <strong>semantic object API</strong> and register handlers in the <strong>policy engine</strong>. The cell format, linearity, hash chain, hat-based identity, WASM wallet, and blockchain anchoring are already there. You don't rewrite the substrate — you extend it.</p>
    </div>
  </div>
</section>

<!-- ═══════════ CROSS-CHAIN EXECUTION ═══════════ -->
<section class="section xchain-section" id="crosschain">
  <div class="section-inner">
    <div class="label">Cross-chain execution</div>
    <h2 class="reveal">Chain-agnostic at execution.<br>BSV-anchored for finality.</h2>
    <div class="reveal reveal-d1" style="margin-top:18px;max-width:62ch;font-size:1.05rem;color:var(--muted);line-height:1.75">
      Semantos cells can encapsulate state from any blockchain VM. The policy kernel doesn't care which chain holds the assets — it evaluates conditions, dispatches actions, and coordinates execution across chains. BSV is not a limitation on what Semantos can touch. It is the neutral anchor layer that makes cross-chain atomicity possible.
    </div>

    <!-- BSV justification -->
    <div class="reveal reveal-d1" style="margin-top:36px;padding:28px 32px;border-radius:16px;background:rgba(251,191,36,.04);border:1px solid rgba(251,191,36,.2);max-width:800px">
      <div style="font-size:.65rem;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--amber);margin-bottom:14px">Why BSV as the anchor layer — not ETH, not Solana</div>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px">
        <div>
          <div style="font-size:.78rem;font-weight:700;color:var(--text);margin-bottom:6px">Fixed protocol</div>
          <div style="font-size:.8rem;color:var(--muted);line-height:1.65">EVM chains change consensus rules via governance votes. BSV's protocol is locked. There is no EIP that can alter the settlement semantics your cells depend on after you deploy.</div>
        </div>
        <div>
          <div style="font-size:.78rem;font-weight:700;color:var(--text);margin-bottom:6px">SPV resolves the CAP tradeoff</div>
          <div style="font-size:.8rem;color:var(--muted);line-height:1.65">The "pick two" framing of the CAP theorem is a threshold optimisation problem, not a hard constraint. SPV clients with Merkle-proof commitments enable partition-tolerant consistency — cells verify locally without a full node. Economic incentives produce convergent behaviour automatically.</div>
        </div>
        <div>
          <div style="font-size:.78rem;font-weight:700;color:var(--text);margin-bottom:6px">Script is a proof validator</div>
          <div style="font-size:.8rem;color:var(--muted);line-height:1.65">Bitcoin Script is a deterministic finite automaton. A correct EDI message can encode a lie — the protocol cannot prevent it. A correct BSV Script <em>cannot</em> execute if its conditions are not met. This is the difference between a document and a proof. The trilemma framing — security vs. scalability vs. decentralisation — is a category error. These properties exist in different analytical domains and do not trade off. BSV demonstrates they are simultaneously achievable when the protocol is fixed and economic incentives drive topology.</div>
        </div>
      </div>
      <div style="margin-top:14px;font-size:.72rem;color:var(--muted);border-top:1px solid var(--border);padding-top:12px">
        Further reading: Craig Wright — <a href="https://singulargrit.substack.com/p/scripted-supply-a-bitcoin-based-architecture" target="_blank" rel="noopener" style="color:var(--amber);text-decoration:none">Scripted Supply: EDI and On-Chain Commerce</a> · <a href="https://singulargrit.substack.com/p/the-collapse-of-the-blockchain-trilemma" target="_blank" rel="noopener" style="color:var(--amber);text-decoration:none">The Collapse of the Blockchain Trilemma</a>
      </div>
    </div>

    <div class="xchain-role-grid reveal reveal-d2">
      <div class="xr-col">
        <div class="xr-col-label" style="color:var(--muted)">Participant chains — execution targets</div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--violet)"></div>
          <div class="xr-item-text"><strong>Any chain can participate.</strong> Solana, SUI, EVM chains, other UTXO chains — Semantos cells encapsulate their state as payload. The kernel issues signed instructions; the target chain executes them.</div>
        </div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--blue)"></div>
          <div class="xr-item-text"><strong>VM-agnostic coordination.</strong> A cell holding Solana account state and a cell holding SUI object state are both just 1024-byte cells to the policy engine. The kernel evaluates conditions against them using the same policy engine regardless.</div>
        </div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--green)"></div>
          <div class="xr-item-text"><strong>State encapsulation.</strong> An EVM contract's state, a Solana account balance, a SUI object — all representable as typed semantic payloads inside cells, with linearity enforced at the substrate level rather than by the host chain's VM.</div>
        </div>
      </div>
      <div class="xr-col" style="background:rgba(251,191,36,.03)">
        <div class="xr-col-label" style="color:var(--amber)">BSV — the finality layer</div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--amber)"></div>
          <div class="xr-item-text"><strong>Neither chain can notarise the other.</strong> Solana can't tell SUI "this happened atomically." They're both state machines. You need a third party that both can verify — one with massive throughput, fixed protocol, and cheap immutable writes at scale.</div>
        </div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--amber)"></div>
          <div class="xr-item-text"><strong>The anchor cell seals atomicity.</strong> When cross-chain conditions are met, an anchor cell is written to BSV. That cell is the timestamped, hash-chained, cryptographically verifiable proof that the coordinated action occurred — or did not. This is what makes "atomic" mean something.</div>
        </div>
        <div class="xr-item">
          <div class="xr-dot" style="background:var(--amber)"></div>
          <div class="xr-item-text"><strong>BSV as physical layer.</strong> TCP/IP doesn't care if you're on fibre or wifi — it depends on <em>some</em> reliable physical layer. Semantos doesn't care which chains you're coordinating — it depends on BSV as the settlement surface that provides finality at the scale the semantic layer requires.</div>
        </div>
      </div>
    </div>

    <!-- Atomic swap diagram -->
    <div class="xchain-flow reveal reveal-d3">
      <div class="xchain-flow-title">Example — atomic swap: Solana ⟺ SUI, anchored on BSV</div>
      <div class="xchain-diagram">
        <div class="xc-chain" style="border-color:rgba(167,139,250,.35);color:var(--violet)">
          <div class="xc-chain-label">participant</div>
          <div class="xc-chain-name">Solana</div>
          <div class="xc-chain-role">holds asset A<br>signs release tx</div>
        </div>
        <div class="xc-arrow">
          <svg width="28" height="10" viewBox="0 0 28 10" fill="none"><path d="M0 5h24M19 1l5 4-5 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <div class="xc-arrow-label">cell state</div>
        </div>
        <div class="xc-chain" style="border-color:rgba(34,211,238,.4);background:rgba(34,211,238,.04);color:var(--cyan)">
          <div class="xc-chain-label">kernel</div>
          <div class="xc-chain-name">Semantos</div>
          <div class="xc-chain-role">policy eval<br>condition check<br>dispatch</div>
        </div>
        <div class="xc-arrow">
          <svg width="28" height="10" viewBox="0 0 28 10" fill="none"><path d="M0 5h24M19 1l5 4-5 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <div class="xc-arrow-label">cell state</div>
        </div>
        <div class="xc-chain" style="border-color:rgba(96,165,250,.35);color:var(--blue)">
          <div class="xc-chain-label">participant</div>
          <div class="xc-chain-name">SUI</div>
          <div class="xc-chain-role">holds asset B<br>signs release tx</div>
        </div>
        <div class="xc-arrow">
          <svg width="28" height="10" viewBox="0 0 28 10" fill="none"><path d="M0 5h24M19 1l5 4-5 4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>
          <div class="xc-arrow-label">anchor</div>
        </div>
        <div class="xc-chain" style="border-color:rgba(251,191,36,.5);background:rgba(251,191,36,.05);color:var(--amber)">
          <div class="xc-chain-label">finality layer</div>
          <div class="xc-chain-name">BSV</div>
          <div class="xc-chain-role">anchor cell<br>atomicity proof<br>immutable record</div>
        </div>
      </div>
      <div class="xchain-anchor">
        <div class="xchain-anchor-icon">⛓</div>
        <p>The anchor cell on BSV is what makes "atomic" true. It lands as a <strong>spendable on-chain UTXO</strong> — not inert data, but a live object whose existence and consumption are governed by Bitcoin's consensus rules. Both chains can independently verify that the swap occurred — or provably did not — by reading the UTXO state. No trusted intermediary. No oracle. The kernel writes the verdict; Bitcoin's double spend protection enforces it.</p>
      </div>
    </div>

    <div class="xchain-insight reveal reveal-d4">
      The substrate claim holds across chains: Semantos doesn't prescribe <em>which</em> chains you use. It prescribes <em>how</em> their state is represented, evaluated, and settled. You could run a Semantos application that never interacts with BSV directly — and the anchor cell that seals your cross-chain operation is just infrastructure running underneath.
    </div>
  </div>
</section>

<footer id="contact">
  <div class="footer-mark">SEMANTOS</div>
  <div style="display:flex;flex-direction:column;gap:6px;align-items:flex-end">
    <div class="footer-text">Cell-based · identity-native · blockchain-settled · cell engine + identity (Plexus/hats) + policy VM + adaptive learning</div>
    <div style="font-size:.68rem;color:var(--muted);text-align:right">
      <span style="color:var(--green);font-weight:700">Shipping:</span> cell engine · linearity · Plexus/hats · policy VM · BKDS signing · WASM wallet · brain node · oddjobz vertical · Gmail/Meta ingest · Flutter + Helm
      &nbsp;·&nbsp;
      <span style="color:var(--amber);font-weight:700">In flight:</span> UDP mesh · voice trigger · BSV anchoring production swap-in
      &nbsp;·&nbsp;
      <span style="color:var(--muted);font-weight:700">Roadmap:</span> cross-chain execution · execution proposal engine
    </div>
    <div style="margin-top:8px">
      <a href="mailto:todd@semantos.me" style="font-size:.8rem;font-weight:700;padding:8px 20px;border-radius:8px;border:1px solid rgba(34,211,238,.4);color:var(--cyan);text-decoration:none;background:rgba(34,211,238,.06);transition:background .15s" onmouseover="this.style.background='rgba(34,211,238,.12)'" onmouseout="this.style.background='rgba(34,211,238,.06)'">Get in touch →</a>
    </div>
  </div>
</footer>

<script>
const nav = document.getElementById('topnav');
window.addEventListener('scroll', () => nav.classList.toggle('scrolled', window.scrollY > 40), { passive:true });

const revealObs = new IntersectionObserver(entries => {
  entries.forEach(e => { if (e.isIntersecting) e.target.classList.add('visible') });
}, { threshold:0.07, rootMargin:'0px 0px -50px 0px' });
document.querySelectorAll('.reveal').forEach(el => revealObs.observe(el));

const arcObs = new IntersectionObserver(entries => {
  entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); arcObs.unobserve(e.target) } });
}, { threshold:0.12, rootMargin:'0px 0px -40px 0px' });
document.querySelectorAll('.arc-step').forEach((step, i) => {
  step.style.transitionDelay = `${i * 0.06}s`;
  arcObs.observe(step);
});
</script>
</body>
</html>

```
