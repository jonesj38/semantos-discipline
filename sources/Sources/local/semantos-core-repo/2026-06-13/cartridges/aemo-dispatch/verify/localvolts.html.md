---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/verify/localvolts.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.571223+00:00
---

# cartridges/aemo-dispatch/verify/localvolts.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Cryptographic Per-Trade Proofs for Localvolts — Real Blockchain Solutions</title>
<style>
  :root {
    --bg: #0e1116;
    --panel: #161b22;
    --panel-2: #1c2330;
    --fg: #e6edf3;
    --muted: #8b949e;
    --accent: #2da44e;
    --warn: #d29922;
    --bad: #f85149;
    --border: #30363d;
    --mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.55;
    padding: 24px;
    max-width: 980px;
    margin: 0 auto;
  }
  h1 {
    font-size: 1.65rem;
    margin: 0 0 8px;
    letter-spacing: -0.01em;
  }
  .subtitle {
    color: var(--muted);
    margin: 0 0 28px;
    font-size: 0.95rem;
  }
  .lede {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px 20px;
    margin-bottom: 32px;
  }
  .lede p { margin: 8px 0; }
  .lede p:first-child { margin-top: 0; }
  .lede p:last-child { margin-bottom: 0; }
  .lede strong { color: #79c0ff; }
  .exhibit {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 18px 20px;
    margin-bottom: 20px;
  }
  .exhibit h2 {
    font-size: 1.1rem;
    margin: 0 0 4px;
  }
  .exhibit .meta {
    color: var(--muted);
    font-size: 0.85rem;
    margin-bottom: 14px;
  }
  .field {
    display: grid;
    grid-template-columns: 170px 1fr;
    gap: 12px;
    padding: 6px 0;
    border-top: 1px solid var(--border);
    align-items: baseline;
  }
  .field:first-of-type { border-top: none; }
  .field .label {
    color: var(--muted);
    font-size: 0.82rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .field .value {
    font-family: var(--mono);
    font-size: 0.84rem;
    word-break: break-all;
    color: var(--fg);
  }
  .field .value a {
    color: #58a6ff;
    text-decoration: none;
  }
  .field .value a:hover { text-decoration: underline; }
  .actions {
    margin-top: 14px;
    display: flex;
    gap: 10px;
    align-items: center;
    flex-wrap: wrap;
  }
  button {
    background: var(--panel-2);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 8px 14px;
    font-size: 0.88rem;
    cursor: pointer;
    font-family: inherit;
  }
  button:hover { border-color: #6e7681; }
  button:disabled { opacity: 0.5; cursor: wait; }
  .verdict {
    font-size: 0.9rem;
    padding: 6px 12px;
    border-radius: 6px;
    font-weight: 600;
  }
  .verdict.ok { background: rgba(45, 164, 78, 0.15); color: var(--accent); border: 1px solid rgba(45,164,78,0.4); }
  .verdict.bad { background: rgba(248, 81, 73, 0.12); color: var(--bad); border: 1px solid rgba(248,81,73,0.4); }
  .verdict.pending { background: rgba(210, 153, 34, 0.12); color: var(--warn); border: 1px solid rgba(210,153,34,0.4); }
  @media (max-width: 720px) {
    .field { grid-template-columns: 1fr; gap: 2px; }
  }
  .mini {
    display: inline-block;
    padding: 3px 8px;
    background: var(--panel-2);
    border-radius: 4px;
    font-family: var(--mono);
    font-size: 0.78rem;
    border: 1px solid var(--border);
  }
  .badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 12px;
    font-size: 0.75rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    margin-left: 8px;
    vertical-align: middle;
  }
  .badge.live { background: rgba(45, 164, 78, 0.15); color: var(--accent); border: 1px solid rgba(45,164,78,0.4); }
  .badge.preview { background: rgba(88, 166, 255, 0.12); color: #79c0ff; border: 1px solid rgba(88,166,255,0.4); }
  footer {
    margin-top: 40px;
    padding-top: 24px;
    border-top: 1px solid var(--border);
    color: var(--muted);
    font-size: 0.85rem;
  }
  footer a { color: #58a6ff; text-decoration: none; }
  .formula {
    font-family: var(--mono);
    background: var(--panel-2);
    padding: 8px 12px;
    border-radius: 4px;
    display: inline-block;
    font-size: 0.85rem;
    border: 1px solid var(--border);
  }
  .hr-block {
    margin: 28px 0 18px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border);
    font-size: 0.95rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  pre {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 12px 14px;
    overflow-x: auto;
    font-family: var(--mono);
    font-size: 0.82rem;
    color: var(--fg);
    margin: 10px 0;
  }
  .roles {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    margin: 14px 0;
  }
  .role {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 12px 14px;
  }
  .role h4 {
    margin: 0 0 6px;
    font-size: 0.95rem;
    color: #79c0ff;
  }
  .role p { margin: 4px 0; font-size: 0.88rem; }
  .role .num { font-family: var(--mono); color: var(--fg); }
  @media (max-width: 720px) {
    .roles { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>

<h1>Cryptographic Per-Trade Proofs for Localvolts</h1>
<p class="subtitle">Real Blockchain Solutions · Anchor every matched trade on BSV mainnet · Both parties can verify independently</p>

<div class="lede">
  <p>Localvolts is the only retailer in Australia doing genuine peer-to-peer matching with an AEMO licence. That solves the hardest problem — the bureaucratic one — that has stopped every blockchain-first energy startup including Power Ledger.</p>
  <p>This page demonstrates a complementary layer: every matched trade is committed on chain as <span class="formula">cell_hash = SHA-256( matching_rule_hex ‖ trade_inputs_sha256 ‖ result_sha256 )</span>. The commitment is 32 bytes, costs <strong>under AU$0.01</strong> per anchor, and lets both Alice and Bob — and any auditor either of them brings — independently verify that the clearing they were billed for is the clearing Localvolts actually ran.</p>
  <p>The mechanism is identical to what's already running for battery dispatch (see live exhibit below). The Localvolts-shaped version is the second exhibit on this page.</p>
</div>

<div class="hr-block">Exhibit 1 — Live mechanism, anchored on mainnet today <span class="badge live">live</span></div>

<div class="exhibit">
  <h2>Battery dispatch backtest — QLD1 May–Jul 2022 (gas crisis)</h2>
  <p class="meta">Same envelope shape, applied here to battery dispatch instead of P2P trade matching. The cryptographic primitive is identical: a 32-byte commitment to (strategy_hex, input_data_sha256, result_sha256). Confirms the pipeline produces real on-chain anchors that any browser can verify.</p>

  <div class="field">
    <div class="label">Strategy hex</div>
    <div class="value">7c03a08601a2690114a2 <span class="mini">10 bytes</span></div>
  </div>
  <div class="field">
    <div class="label">Data SHA-256</div>
    <div class="value">ce4102258474cff91861b61262e4005459efa5710133396ad64d7c604314b6a0</div>
  </div>
  <div class="field">
    <div class="label">Result SHA-256</div>
    <div class="value">9bb6f0fe69eb263e8e5783b901ac25893b87588d485b024d5ccf5b225613bcbb</div>
  </div>
  <div class="field">
    <div class="label">cell_hash (on chain)</div>
    <div class="value">7b9e848e7b0ebce9d13a7b3b21589bb2a11f51b05726f9e8b62c847b3ba1479d</div>
  </div>
  <div class="field">
    <div class="label">Transaction</div>
    <div class="value"><a href="https://whatsonchain.com/tx/a9ce2f401164fda09312e25a5186de20fe90f2021d152a3a6905af61779ccd8a" target="_blank" rel="noopener">a9ce2f401164fda09312e25a5186de20fe90f2021d152a3a6905af61779ccd8a</a></div>
  </div>

  <div class="actions">
    <button id="verify-btn">Verify on chain</button>
    <span class="verdict pending" id="verdict">Not yet verified</span>
  </div>
</div>

<div class="hr-block">Exhibit 2 — Localvolts production shape (sample trade)</div>

<div class="exhibit">
  <h2>Sample matched trade — Alice → Bob, 5 kWh @ AU$0.20/kWh</h2>
  <p class="meta">A representative Localvolts-shaped trade with all commitment hashes computed below. In production deployment each matched trade is anchored automatically; both Alice and Bob see the txid in their account view alongside the trade record.</p>

  <pre>{
  "trade_id": "lv-demo-2026-05-26-001",
  "settlement_interval": "2026-05-26T13:45:00+10:00",
  "buyer":  { "alias": "Bob",   "bid_cents_per_kwh": 22, "max_kwh": 5.0 },
  "seller": { "alias": "Alice", "ask_cents_per_kwh": 18, "available_kwh": 5.0 },
  "matching_predicate_hex": "7ca2",
  "matching_rule": "OP_SWAP OP_GREATERTHANOREQUAL — truthy iff buyer bid >= seller ask"
}</pre>

  <div class="roles">
    <div class="role">
      <h4>What Bob sees in his account</h4>
      <p>Bought <span class="num">5.0 kWh</span> from Alice at <span class="num">AU$0.20/kWh</span></p>
      <p>Total paid: <span class="num">AU$1.00</span></p>
      <p>Anchor txid: <a href="https://whatsonchain.com/tx/6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4" target="_blank" rel="noopener" class="num">6d9d82fe…502e4 →</a></p>
    </div>
    <div class="role">
      <h4>What Alice sees in her account</h4>
      <p>Sold <span class="num">5.0 kWh</span> to Bob at <span class="num">AU$0.20/kWh</span></p>
      <p>Total received: <span class="num">AU$1.00</span></p>
      <p>Anchor txid: <a href="https://whatsonchain.com/tx/6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4" target="_blank" rel="noopener" class="num">6d9d82fe…502e4 →</a></p>
    </div>
  </div>

  <div class="field">
    <div class="label">Matching predicate hex</div>
    <div class="value">7ca2 <span class="mini">2 bytes</span></div>
  </div>
  <div class="field">
    <div class="label">Trade inputs SHA-256</div>
    <div class="value">d0f7f2c9d0a6be96f407442159cf93c4ff6fef0dbccf10d5c84d3dddb89d6fbf</div>
  </div>
  <div class="field">
    <div class="label">Clearing result SHA-256</div>
    <div class="value">73d6d3c4df8a9f90fbb5ae84ca0133be088ab0af1393c9588ac03b27b10b4740</div>
  </div>
  <div class="field">
    <div class="label">cell_hash (computed)</div>
    <div class="value">47855f492479fca71ddf46b3bbed761b19f87ad08161f1811eaedfbcdd24b625</div>
  </div>
  <div class="field">
    <div class="label">Transaction</div>
    <div class="value"><a href="https://whatsonchain.com/tx/6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4" target="_blank" rel="noopener">6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4</a> · <a href="https://whatsonchain.com/tx/6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4" target="_blank" rel="noopener">view raw on WhatsOnChain →</a></div>
  </div>

  <div class="actions">
    <button id="verify-btn-2">Verify on chain</button>
    <span class="verdict pending" id="verdict-2">Not yet verified</span>
  </div>
</div>

<div class="hr-block">What deployment would deliver</div>

<div class="exhibit">
  <p style="margin-top: 0;"><strong>Scope: AU$50,000, 4–6 weeks, fixed-price.</strong> Larger or smaller scope quoted separately if either fits better.</p>
  <ul style="line-height: 1.7;">
    <li>Wrap Localvolts' existing matching logic as a Rúnar predicate (the clearing rule compiled to 10–30 bytes of Bitcoin Script — exactly what your matching engine already does, expressed in a form any auditor can step through)</li>
    <li>Backtest against 12 months of Localvolts trade data; prove byte-equivalent matches across every interval</li>
    <li>Production anchor pipeline (Bun service, runs alongside the existing matching engine; touches nothing in matching logic itself)</li>
    <li>Per-trade txid surfaced in both buyer and seller account views, linked to a verification page either party can hit independently with their trade-id</li>
    <li>Operator runbook + 3 months of fix-it support</li>
    <li>MIT-licensed source, all of it yours</li>
  </ul>
</div>

<footer>
  <p><strong>What this proves.</strong> If <span class="mini">Verify on chain</span> on Exhibit 1 returns ✓, the BSV mainnet transaction at that txid contains a 32-byte commitment exactly equal to <span class="formula">SHA-256(strategy_hex ‖ data_sha256 ‖ result_sha256)</span>. Since the transaction is timestamped by miners and immutable, the commitment <em>predates</em> any later claim about what the underlying process produced.</p>
  <p><strong>Why Localvolts beats Power Ledger here.</strong> Power Ledger has spent nine years trying to convince AEMO to permit the market structure you already have a licence for. The chain layer is the much easier half of the problem; you're past the hard half. Adding cryptographic per-trade proofs turns "trust Localvolts' books" into "verify it yourself" — and that's a moat your P2P-trading competitors can't claim, because they're either not doing P2P or not licensed to settle it.</p>
  <p style="margin-top: 18px;">Built by <a href="https://realblockchainsolutions.com">Real Blockchain Solutions</a> · Contact: <a href="mailto:todd@realblockchainsolutions.com">todd@realblockchainsolutions.com</a></p>
</footer>

<script>
const EX = {
  strategy_hex: "7c03a08601a2690114a2",
  data_sha256:  "ce4102258474cff91861b61262e4005459efa5710133396ad64d7c604314b6a0",
  result_sha256:"9bb6f0fe69eb263e8e5783b901ac25893b87588d485b024d5ccf5b225613bcbb",
  cell_hash:    "7b9e848e7b0ebce9d13a7b3b21589bb2a11f51b05726f9e8b62c847b3ba1479d",
  txid:         "a9ce2f401164fda09312e25a5186de20fe90f2021d152a3a6905af61779ccd8a"
};

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i*2, i*2+2), 16);
  return out;
}
function bytesToHex(b) {
  return Array.from(b).map(x => x.toString(16).padStart(2,"0")).join("");
}

const EX2 = {
  predicate_hex: "7ca2",
  data_sha256:   "d0f7f2c9d0a6be96f407442159cf93c4ff6fef0dbccf10d5c84d3dddb89d6fbf",
  result_sha256: "73d6d3c4df8a9f90fbb5ae84ca0133be088ab0af1393c9588ac03b27b10b4740",
  cell_hash:     "47855f492479fca71ddf46b3bbed761b19f87ad08161f1811eaedfbcdd24b625",
  txid:          "6d9d82fe7e1396496f9942c24171ea4fc069f03ac8c9526614f69cfec25502e4"
};

async function runVerify(ex, btnId, verdictId, fields) {
  const btn = document.getElementById(btnId);
  const v   = document.getElementById(verdictId);
  btn.disabled = true; btn.textContent = "Verifying...";
  v.className = "verdict pending"; v.textContent = "Fetching from WhatsOnChain...";
  try {
    const parts = fields.map(f => hexToBytes(ex[f]));
    const total = parts.reduce((s, p) => s + p.length, 0);
    const buf = new Uint8Array(total);
    let off = 0;
    for (const p of parts) { buf.set(p, off); off += p.length; }
    const computed = bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", buf)));
    if (computed !== ex.cell_hash) {
      v.className = "verdict bad"; v.textContent = "✗ Local hash mismatch"; return;
    }
    const resp = await fetch("https://api.whatsonchain.com/v1/bsv/main/tx/hash/" + ex.txid);
    if (!resp.ok) { v.className = "verdict bad"; v.textContent = "✗ WoC " + resp.status; return; }
    const tx = await resp.json();
    let found = -1;
    for (let i = 0; i < (tx.vout || []).length; i++) {
      if ((tx.vout[i].scriptPubKey?.hex || "").toLowerCase().includes(ex.cell_hash)) { found = i; break; }
    }
    if (found >= 0) {
      v.className = "verdict ok";
      v.innerHTML = "✓ Verified — cell_hash in output #" + found + ", " + (tx.confirmations || "?") + " confirmations";
    } else {
      v.className = "verdict bad"; v.textContent = "✗ cell_hash not found in tx outputs";
    }
  } catch (e) {
    v.className = "verdict bad"; v.textContent = "✗ " + e.message;
  } finally {
    btn.textContent = "Verify on chain"; btn.disabled = false;
  }
}

document.getElementById("verify-btn-2").addEventListener("click", () =>
  runVerify(EX2, "verify-btn-2", "verdict-2", ["predicate_hex", "data_sha256", "result_sha256"])
);

document.getElementById("verify-btn").addEventListener("click", async () => {
  const btn = document.getElementById("verify-btn");
  const v = document.getElementById("verdict");
  btn.disabled = true; btn.textContent = "Verifying...";
  v.className = "verdict pending"; v.textContent = "Fetching from WhatsOnChain...";
  try {
    const a = hexToBytes(EX.strategy_hex);
    const b = hexToBytes(EX.data_sha256);
    const c = hexToBytes(EX.result_sha256);
    const buf = new Uint8Array(a.length + b.length + c.length);
    buf.set(a, 0); buf.set(b, a.length); buf.set(c, a.length + b.length);
    const computed = bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", buf)));
    if (computed !== EX.cell_hash) {
      v.className = "verdict bad"; v.textContent = "✗ Local hash mismatch";
      return;
    }
    const resp = await fetch("https://api.whatsonchain.com/v1/bsv/main/tx/hash/" + EX.txid);
    if (!resp.ok) { v.className = "verdict bad"; v.textContent = "✗ WoC " + resp.status; return; }
    const tx = await resp.json();
    let found = -1;
    for (let i = 0; i < (tx.vout || []).length; i++) {
      const h = (tx.vout[i].scriptPubKey?.hex || "").toLowerCase();
      if (h.includes(EX.cell_hash)) { found = i; break; }
    }
    if (found >= 0) {
      v.className = "verdict ok";
      v.innerHTML = "✓ Verified — cell_hash present in output #" + found + ", " + (tx.confirmations || "?") + " confirmations";
    } else {
      v.className = "verdict bad"; v.textContent = "✗ cell_hash not found in tx outputs";
    }
  } catch (e) {
    v.className = "verdict bad"; v.textContent = "✗ " + e.message;
  } finally {
    btn.textContent = "Verify on chain"; btn.disabled = false;
  }
});
</script>

</body>
</html>

```
