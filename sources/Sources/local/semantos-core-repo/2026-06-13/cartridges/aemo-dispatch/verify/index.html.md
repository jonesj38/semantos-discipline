---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/verify/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.571525+00:00
---

# cartridges/aemo-dispatch/verify/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Anchored Battery Dispatch Verifier — Real Blockchain Solutions</title>
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
    font-size: 1.6rem;
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
    grid-template-columns: 160px 1fr;
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
  .panel-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    margin-bottom: 14px;
  }
  @media (max-width: 720px) {
    .panel-row { grid-template-columns: 1fr; }
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
  .stat {
    display: inline-block;
    padding: 4px 10px;
    background: rgba(45, 164, 78, 0.1);
    color: var(--accent);
    border-radius: 4px;
    font-weight: 600;
    font-size: 0.85rem;
    margin-right: 8px;
  }
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
</style>
</head>
<body>

<h1>Anchored Battery Dispatch Verifier</h1>
<p class="subtitle">Real Blockchain Solutions · AEMO dispatch backtest receipts on BSV mainnet</p>

<div class="lede">
  <p>Each row below is a battery-dispatch backtest run whose summary has been committed to <strong>BSV mainnet</strong> as a single SHA-256 hash, embedded in a real transaction output. The hash is:</p>
  <p style="text-align: center; margin: 14px 0;"><span class="formula">cell_hash = SHA-256( strategy_hex ‖ data_sha256 ‖ result_sha256 )</span></p>
  <p>Click <strong>Verify on chain</strong> on any exhibit. Your browser will fetch the transaction from the public WhatsOnChain API, search the output script for the committed hash, and confirm it matches the values shown here — no server involved on this side.</p>
</div>

<div class="hr-block">Exhibits</div>

<div id="exhibits"></div>

<footer>
  <p><strong>What this proves.</strong> If <span class="mini">Verify on chain</span> returns ✓ for an exhibit, the BSV mainnet transaction at that txid contains a 32-byte commitment exactly equal to <span class="formula">SHA-256(strategy_hex ‖ data_sha256 ‖ result_sha256)</span>. Since the transaction is timestamped by miners and immutable, the commitment <em>predates</em> any later claim about what the dispatch result was. Anyone can re-run the same 10-byte Bitcoin Script predicate against the same data file, hash the result, and confirm the same commitment lands on chain.</p>
  <p><strong>What this does not prove.</strong> Nothing about real-world battery operation, market settlement, or future strategy behaviour. The proof is narrow: the published strategy ran on the published data and produced the published result. That narrow proof is what the dispatch-trust story is built on.</p>
  <p style="margin-top: 18px;">Built by <a href="https://realblockchainsolutions.com">Real Blockchain Solutions</a> · Contact: <a href="mailto:todd@realblockchainsolutions.com">todd@realblockchainsolutions.com</a> · Source: <code class="mini">cartridges/aemo-dispatch/</code></p>
</footer>

<script>
const EXHIBITS = [
  {
    name: "NSW1 — H1 2024",
    description: "52,416 real 5-min dispatch prices, 1 MW / 1 MWh battery starting 50% full. Net P&L AU$54,536 after $75/MWh wear.",
    strategy_name: "scarcity_only",
    strategy_human: "discharge if priceCents >= 100000 AND socPct >= 20  (i.e. wait for $1000/MWh scarcity events, only if battery >= 20% full)",
    strategy_hex: "7c03a08601a2690114a2",
    data_sha256: "9738ec2288eb3712298d46f7eb974b81835952f515d21fa079d4b444315dfd9d",
    result_sha256: "4d299fabf5c6bfd4eb47a066932d9b6ab9baba96490712ebea2bc190e5d5fec3",
    cell_hash: "9aa5c251b20e74f5c9bbe94feed2349344536644d589bb1f4f8d551748994581",
    txid: "160e9a4390a7b0703da8244dc99092de7dc04c31acc5110371c2ea7c9665a593",
    pnl_aud: "54,536",
    discharges: 100,
    mwh_cycled: 17
  },
  {
    name: "QLD1 — May–Jul 2022 (gas crisis)",
    description: "26,496 intervals across the east-coast gas crisis. Same predicate, same battery model. Net P&L AU$43,432 — proves the strategy survives stress events, not just calm markets.",
    strategy_name: "scarcity_only",
    strategy_human: "discharge if priceCents >= 100000 AND socPct >= 20",
    strategy_hex: "7c03a08601a2690114a2",
    data_sha256: "ce4102258474cff91861b61262e4005459efa5710133396ad64d7c604314b6a0",
    result_sha256: "9bb6f0fe69eb263e8e5783b901ac25893b87588d485b024d5ccf5b225613bcbb",
    cell_hash: "7b9e848e7b0ebce9d13a7b3b21589bb2a11f51b05726f9e8b62c847b3ba1479d",
    txid: "a9ce2f401164fda09312e25a5186de20fe90f2021d152a3a6905af61779ccd8a",
    pnl_aud: "43,432",
    discharges: 131,
    mwh_cycled: 22
  }
];

const WOC_BASE = "https://api.whatsonchain.com/v1/bsv/main/tx/hash/";

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i*2, i*2+2), 16);
  }
  return out;
}

function bytesToHex(bytes) {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
}

async function computeCellHash(strategy_hex, data_sha256, result_sha256) {
  const a = hexToBytes(strategy_hex);
  const b = hexToBytes(data_sha256);
  const c = hexToBytes(result_sha256);
  const buf = new Uint8Array(a.length + b.length + c.length);
  buf.set(a, 0);
  buf.set(b, a.length);
  buf.set(c, a.length + b.length);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return bytesToHex(new Uint8Array(digest));
}

async function verifyOnChain(button, ex, verdictEl) {
  button.disabled = true;
  const original = button.textContent;
  button.textContent = "Verifying...";
  verdictEl.className = "verdict pending";
  verdictEl.textContent = "Fetching from WhatsOnChain...";

  try {
    // Step 1: independently re-compute cell_hash from the three inputs
    const computed = await computeCellHash(ex.strategy_hex, ex.data_sha256, ex.result_sha256);
    if (computed !== ex.cell_hash) {
      verdictEl.className = "verdict bad";
      verdictEl.textContent = "✗ Local hash mismatch — published cell_hash does not match SHA-256 of declared inputs";
      return;
    }

    // Step 2: fetch the tx from a public BSV explorer
    const resp = await fetch(WOC_BASE + ex.txid);
    if (!resp.ok) {
      verdictEl.className = "verdict bad";
      verdictEl.textContent = "✗ WhatsOnChain API error: " + resp.status;
      return;
    }
    const tx = await resp.json();

    // Step 3: scan each output script for the cell_hash bytes
    const target = ex.cell_hash.toLowerCase();
    let found = false;
    let foundOutputIdx = -1;
    for (let i = 0; i < (tx.vout || []).length; i++) {
      const scriptHex = (tx.vout[i].scriptPubKey && tx.vout[i].scriptPubKey.hex || "").toLowerCase();
      if (scriptHex.includes(target)) {
        found = true;
        foundOutputIdx = i;
        break;
      }
    }

    if (found) {
      verdictEl.className = "verdict ok";
      verdictEl.innerHTML = "✓ Verified — cell_hash present in output #" + foundOutputIdx + ", confirmed by " + (tx.confirmations || "?") + " block confirmations";
    } else {
      verdictEl.className = "verdict bad";
      verdictEl.textContent = "✗ cell_hash bytes not found in any output script — exhibit may be misconfigured";
    }
  } catch (err) {
    verdictEl.className = "verdict bad";
    verdictEl.textContent = "✗ Verification error: " + err.message;
  } finally {
    button.textContent = original;
    button.disabled = false;
  }
}

function renderExhibits() {
  const container = document.getElementById("exhibits");
  EXHIBITS.forEach((ex, idx) => {
    const div = document.createElement("div");
    div.className = "exhibit";
    const wocUrl = "https://whatsonchain.com/tx/" + ex.txid;
    div.innerHTML = `
      <h2>${ex.name}</h2>
      <p class="meta">${ex.description}</p>

      <div style="margin-bottom: 14px;">
        <span class="stat">Net AU$${ex.pnl_aud}</span>
        <span class="stat">${ex.discharges} discharges</span>
        <span class="stat">${ex.mwh_cycled} MWh cycled</span>
      </div>

      <div class="field">
        <div class="label">Strategy</div>
        <div class="value"><strong>${ex.strategy_name}</strong> — ${ex.strategy_human}</div>
      </div>
      <div class="field">
        <div class="label">Strategy hex</div>
        <div class="value">${ex.strategy_hex} <span class="mini">${ex.strategy_hex.length / 2} bytes</span></div>
      </div>
      <div class="field">
        <div class="label">Data SHA-256</div>
        <div class="value">${ex.data_sha256}</div>
      </div>
      <div class="field">
        <div class="label">Result SHA-256</div>
        <div class="value">${ex.result_sha256}</div>
      </div>
      <div class="field">
        <div class="label">cell_hash (on chain)</div>
        <div class="value">${ex.cell_hash}</div>
      </div>
      <div class="field">
        <div class="label">Transaction</div>
        <div class="value"><a href="${wocUrl}" target="_blank" rel="noopener">${ex.txid}</a> · <a href="${wocUrl}" target="_blank" rel="noopener">view raw on WhatsOnChain →</a></div>
      </div>

      <div class="actions">
        <button data-idx="${idx}">Verify on chain</button>
        <span class="verdict pending" id="verdict-${idx}">Not yet verified</span>
      </div>
    `;
    container.appendChild(div);
  });

  document.querySelectorAll("button[data-idx]").forEach(btn => {
    btn.addEventListener("click", () => {
      const idx = parseInt(btn.dataset.idx, 10);
      const verdictEl = document.getElementById("verdict-" + idx);
      verifyOnChain(btn, EXHIBITS[idx], verdictEl);
    });
  });
}

renderExhibits();
</script>

</body>
</html>

```
