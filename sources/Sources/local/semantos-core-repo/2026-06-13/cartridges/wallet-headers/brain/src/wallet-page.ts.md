---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/wallet-page.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.644746+00:00
---

# cartridges/wallet-headers/brain/src/wallet-page.ts

```ts
// Standalone BRC-100 browser wallet — no extension bridge.
//
// Entry point for wallet.html. Runs directly in a browser tab with no
// hidden iframe, no postMessage handshake, no extension API.
//
// Boot sequence:
//   1. Instantiate cell-engine-embedded.wasm with the JS host layer.
//   2. loadWallet() — hydrate identity from IndexedDB, or present the
//      one-time create flow.
//   3. unlockIdentityFromCache() — re-derive identity sk from the boot
//      cache without prompting the user on every tab reload.
//   4. Poll the local brain headers endpoint for the chain tip; fall back
//      to the hosted semantos.me endpoint.

import { createHost } from './host';
import {
  loadWallet,
  createWallet,
  unlockIdentityFromCache,
  getIdentitySnapshot,
  type CreateWalletInput,
} from './wallet-ops';
import { run2HopTest, type HopResult, type TwoHopResult } from './test-2hop';
import { runKeyRotationTest, type RotationHop, type KeyRotationResult } from './test-key-rotation';
import { runDeepRotationTest, type DeepHop, type DeepRotationResult } from './test-deep-rotation';
import { runChessStakeTest, type ChessStakeResult } from './test-chess-stake';
import { runMncaAnchor, type AnchorRunResult } from './test-mnca-anchor';
import { runCovenantGenesis, getLastGenesis, type CovenantGenesisResult } from './test-covenant-genesis';
import { runPushtxAuthTest, type PushtxAuthResult } from './test-pushtx-auth';
import { runCovenantSpend, type CovenantSpendResult } from './test-covenant-spend';
import { buildChessManifestJson } from './chess-manifest-export';
import { claimChessWinnings } from './chess-wallet-claim';

// Route ARC through the local dev-server proxy (/arc/v1/tx) so the API key
// stays server-side and browser extension blockers don't interfere.
// When the wallet is served by the Semantos Brain, /arc/v1/tx is proxied
// through. When served by a plain static server (local smoke), fall back
// to GorillaPool ARC — clean browser CORS, no key required for low volume.
// (Taal blocks browser CORS via duplicated Access-Control-Allow-Origin
// `*, *` header; only usable through a server-side proxy.)
const ARC_URL = window.location.origin.includes(':8080')
  ? `${window.location.origin}/arc`
  : 'https://arc.gorillapool.io';

// ── History persistence ───────────────────────────────────────────────

interface HistoryRun {
  id: string;
  ts: number;           // Unix ms
  result: TwoHopResult;
}

const HISTORY_KEY = 'wallet:beef-history';
const HISTORY_MAX = 50;

function loadHistory(): HistoryRun[] {
  try { return JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]'); }
  catch { return []; }
}

function pushHistory(result: TwoHopResult): void {
  const runs = loadHistory();
  runs.unshift({ id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, ts: Date.now(), result });
  if (runs.length > HISTORY_MAX) runs.length = HISTORY_MAX;
  localStorage.setItem(HISTORY_KEY, JSON.stringify(runs));
}

// ── WASM boot ─────────────────────────────────────────────────────────

interface EngineState {
  wasm: WebAssembly.Instance | null;
  memory: WebAssembly.Memory | null;
}

const engine: EngineState = { wasm: null, memory: null };

async function bootEngine(wasmUrl = './cell-engine-embedded.wasm'): Promise<void> {
  const memory = new WebAssembly.Memory({ initial: 128, maximum: 256 });
  const host = createHost(memory);
  let mod: WebAssembly.WebAssemblyInstantiatedSource;
  try {
    const resp = await fetch(wasmUrl);
    if (!resp.ok) throw new Error(`fetch ${wasmUrl}: ${resp.status}`);
    if (typeof WebAssembly.instantiateStreaming === 'function') {
      try {
        mod = await WebAssembly.instantiateStreaming(resp, { host, env: { memory } });
      } catch {
        const buf = await (await fetch(wasmUrl)).arrayBuffer();
        mod = await WebAssembly.instantiate(buf, { host, env: { memory } });
      }
    } else {
      const buf = await resp.arrayBuffer();
      mod = await WebAssembly.instantiate(buf, { host, env: { memory } });
    }
  } catch (e) {
    throw new Error(`bootEngine: ${(e as Error).message}`);
  }
  engine.wasm = mod.instance;
  const exportedMem = engine.wasm.exports.memory as WebAssembly.Memory | undefined;
  engine.memory = exportedMem ?? memory;
}

// ── Block-tip helper ──────────────────────────────────────────────────

interface TipInfo {
  height: number;
  hash: string;
}

const HEADER_SOURCES = [
  // Local Semantos Brain — available when the page is served by a Semantos Brain instance.
  `${typeof window !== 'undefined' ? window.location.origin : ''}/api/v1/chain/header`,
  // Hosted fallback.
  'https://headers.semantos.me/api/v1/chain/header',
];

async function fetchTip(): Promise<TipInfo | null> {
  for (const base of HEADER_SOURCES) {
    try {
      const resp = await fetch(`${base}/byHeight/tip`, { signal: AbortSignal.timeout(4000) });
      if (!resp.ok) continue;
      const data = await resp.json() as { height?: number; hash?: string };
      if (typeof data.height === 'number' && typeof data.hash === 'string') {
        return { height: data.height, hash: data.hash };
      }
    } catch {
      // try next source
    }
  }
  return null;
}

// ── Minimal DOM renderer ──────────────────────────────────────────────

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  if (text !== undefined) node.textContent = text;
  return node;
}

function mount(id: string, node: HTMLElement): void {
  const root = document.getElementById(id);
  if (!root) return;
  root.innerHTML = '';
  root.appendChild(node);
}

// ── Tab system ────────────────────────────────────────────────────────

type TabId = 'wallet' | 'history';

function renderTabs(active: TabId, onSwitch: (t: TabId) => void): HTMLElement {
  const bar = el('div', { class: 'tab-bar' });
  for (const [id, label] of [
    ['wallet', 'Wallet'],
    ['history', 'History'],
  ] as [TabId, string][]) {
    const tab = el('button', { class: `tab${id === active ? ' active' : ''}`, type: 'button' }, label);
    tab.addEventListener('click', () => onSwitch(id));
    bar.appendChild(tab);
  }
  return bar;
}

// ── Status panel ──────────────────────────────────────────────────────

function renderStatus(opts: {
  identityPkHex: string;
  tip: TipInfo | null;
  wasmLoaded: boolean;
  wasmError?: string;
}, activeTab: TabId = 'wallet'): HTMLElement {
  const wrap = el('div', { class: 'status' });

  const header = el('h2', {}, 'Semantos Wallet');
  wrap.appendChild(header);

  const tabBar = renderTabs(activeTab, (t) => {
    const updated = renderStatus(opts, t);
    wrap.replaceWith(updated);
  });
  wrap.appendChild(tabBar);

  if (activeTab === 'wallet') {
    const pkRow = el('div', { class: 'row' });
    pkRow.appendChild(el('span', { class: 'label' }, 'Identity key'));
    pkRow.appendChild(el('code', { class: 'pubkey' }, opts.identityPkHex));
    wrap.appendChild(pkRow);

    const wasmRow = el('div', { class: 'row' });
    wasmRow.appendChild(el('span', { class: 'label' }, 'WASM engine'));
    wasmRow.appendChild(el('span', {}, opts.wasmLoaded ? '✓ loaded (embedded, 29 KB)' : `✗ failed${opts.wasmError ? ': ' + opts.wasmError.slice(0, 80) : ''}`));
    wrap.appendChild(wasmRow);

    const tipRow = el('div', { class: 'row' });
    tipRow.appendChild(el('span', { class: 'label' }, 'Chain tip'));
    tipRow.appendChild(
      el('span', { 'data-tip': '' }, opts.tip ? `#${opts.tip.height}  ${opts.tip.hash.slice(0, 16)}…` : 'fetching…'),
    );
    wrap.appendChild(tipRow);

    wrap.appendChild(render2HopPanel(opts));
    wrap.appendChild(renderKeyRotationPanel());
    wrap.appendChild(renderDeepRotationPanel());
    wrap.appendChild(renderChessStakePanel());
    wrap.appendChild(renderMncaAnchorPanel());
    wrap.appendChild(renderPushtxAuthPanel());
    wrap.appendChild(renderCovenantGenesisPanel());
    wrap.appendChild(renderCovenantSpendPanel());
  } else {
    wrap.appendChild(renderHistoryTab());
  }

  return wrap;
}

// ── 2-hop BEEF proof panel ────────────────────────────────────────────

function render2HopPanel(statusOpts: { identityPkHex: string; tip: TipInfo | null; wasmLoaded: boolean }): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, '2-hop BEEF proof'));
  panel.appendChild(el('p', { class: 'hint' },
    'Funds from Metanet Desktop (port 3321) through 2 hops, ' +
    'each validated against local block headers.'));

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const btn = el('button', { type: 'button', class: 'run-btn' }, 'Run test (150 sats)');

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.textContent = 'Running…';
    log.removeAttribute('hidden');
    log.textContent = 'Connecting to Metanet Desktop on :3321…\n';

    try {
      const result = await run2HopTest({ satoshis: 150, arcUrl: ARC_URL });
      pushHistory(result);

      log.textContent = '';
      for (const hop of result.hops) {
        appendHopLine(log, hop);
      }
      log.textContent += '\n' + (result.allOk ? '✓ ' : '✗ ') + result.summary;
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Run test (150 sats)';
    }
  });

  panel.appendChild(btn);
  panel.appendChild(log);
  return panel;
}

// ── Key rotation test panel ───────────────────────────────────────────

function renderKeyRotationPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'Key rotation test'));
  panel.appendChild(el('p', { class: 'hint' },
    'Funds from Metanet Desktop through 3 BRC-42 edge rotations, ' +
    'each BEEF-validated then broadcast to ARC.'));

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const btn = el('button', { type: 'button', class: 'run-btn' }, 'Run test (10,000 sats)') as HTMLButtonElement;

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.textContent = 'Running…';
    log.removeAttribute('hidden');
    log.textContent = 'Funding from Metanet Desktop…\n';

    try {
      const result = await runKeyRotationTest({ satoshis: 10_000, arcUrl: ARC_URL });

      log.textContent = '';
      for (const hop of result.hops) {
        appendRotHopLine(log, hop);
        log.textContent += '\n';
      }
      log.textContent += (result.allOk ? '✓ ' : '✗ ') + result.summary;
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Run test (10,000 sats)';
    }
  });

  panel.appendChild(btn);
  panel.appendChild(log);
  return panel;
}

function appendHopLine(pre: HTMLPreElement, hop: HopResult): void {
  const spv = hop.spvOk ? '✓ SPV' : '✗ SPV';
  const scripts = hop.scriptOk ? '✓ scripts' : '✗ scripts';
  const bcast = hop.broadcastTxid ? '✓ ARC' : (hop.hop === 0 ? '✓ ARC' : '— ARC');
  pre.textContent += `hop-${hop.hop}  ${hop.txid}  ${hop.satoshis} sats  ${spv}  ${scripts}  ${bcast}\n`;
  pre.textContent += `       ${hop.spvDetail}\n`;
  if (hop.broadcastTxid && hop.broadcastTxid !== hop.txid)
    pre.textContent += `       ARC txid: ${hop.broadcastTxid}\n`;
  if (hop.error) pre.textContent += `       ⚠ ${hop.error}\n`;
}

function appendRotHopLine(pre: HTMLPreElement, hop: RotationHop): void {
  const spv = hop.spvOk ? '✓ SPV' : '✗ SPV';
  const bcast = hop.broadcastOk ? '✓ ARC' : '✗ ARC';
  pre.textContent += `${hop.label.padEnd(32)}  ${hop.satsOut} sats  ${spv}  ${bcast}\n`;
  pre.textContent += `  txid: ${hop.txid}\n`;
  pre.textContent += `  ${hop.spvDetail}\n`;
  if (hop.error) pre.textContent += `  ⚠ ${hop.error}\n`;
}

// ── MNCA snapshot anchor panel ────────────────────────────────────────
//
// Anchors a computed MNCA snapshot cell as a pushdrop UTXO on mainnet.
// Two buttons: a DRY-RUN (build + show the txid/EF, no broadcast) and an
// explicit BROADCAST (spends real sats). Owner = recoverable Tier-0 BRC-42
// edge leaf; funded from Metanet Desktop :3321 (same path as key rotation).

function renderMncaAnchorPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'MNCA snapshot anchor'));
  panel.appendChild(el('p', { class: 'hint' },
    'Anchors a computed MNCA snapshot cell as a BSV pushdrop UTXO. ' +
    'Funds from Metanet Desktop, owner = recoverable BRC-42 edge leaf. ' +
    'Dry-run builds + shows the tx; Broadcast spends ~1 sat + fee on mainnet.'));

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const dryBtn = el('button', { type: 'button', class: 'run-btn' }, 'Dry-run (no broadcast)') as HTMLButtonElement;
  const liveBtn = el('button', { type: 'button', class: 'run-btn' }, 'Broadcast anchor (1 sat, mainnet)') as HTMLButtonElement;

  const logResult = (r: AnchorRunResult): void => {
    log.textContent = '';
    log.textContent += `${r.ok ? '✓' : '✗'} ${r.dryRun ? 'DRY-RUN' : 'BROADCAST'}\n`;
    if (r.anchorTxid) log.textContent += `  anchor txid: ${r.anchorTxid}\n`;
    log.textContent += `  leaf: edge[${r.leafIndex}]${r.leafPubkeyHex ? ' = ' + r.leafPubkeyHex : ''}\n`;
    if (r.broadcastTxid) log.textContent += `  ARC txid: ${r.broadcastTxid}\n`;
    if (r.efTxHex) log.textContent += `  efTx (${r.efTxHex.length / 2} bytes): ${r.efTxHex.slice(0, 120)}…\n`;
    log.textContent += `\n${r.summary}\n`;
  };

  const run = async (btn: HTMLButtonElement, confirm: boolean, label: string) => {
    dryBtn.disabled = true; liveBtn.disabled = true;
    btn.textContent = confirm ? 'Broadcasting…' : 'Building…';
    log.removeAttribute('hidden');
    log.textContent = confirm ? 'Funding + broadcasting on mainnet…\n' : 'Funding + building (no broadcast)…\n';
    try {
      logResult(await runMncaAnchor({ confirm, anchorSats: 1, arcUrl: ARC_URL }));
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      dryBtn.disabled = false; liveBtn.disabled = false;
      btn.textContent = label;
    }
  };

  dryBtn.addEventListener('click', () => run(dryBtn, false, 'Dry-run (no broadcast)'));
  liveBtn.addEventListener('click', () => {
    if (!window.confirm('Broadcast a real mainnet anchor (~1 sat + fee)?')) return;
    run(liveBtn, true, 'Broadcast anchor (1 sat, mainnet)');
  });

  panel.appendChild(dryBtn);
  panel.appendChild(liveBtn);
  panel.appendChild(log);
  return panel;
}

// ── OP_PUSH_TX auth-isolation test panel ─────────────────────────────
// Cheapest on-chain crack: fund an AUTH-only lock (<OP_PUSH_TX> OP_CHECKSIG)
// and spend it with just the preimage. If the spend confirms, Brendogg's block
// works on a live node and the full covenant is high-confidence — for the fee,
// not 5k blind. No covenant funds at risk.

function renderPushtxAuthPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'OP_PUSH_TX auth test (de-risk)'));
  panel.appendChild(el('p', { class: 'hint' },
    'Isolates the one unproven clause: funds a tiny <OP_PUSH_TX> OP_CHECKSIG ' +
    'lock and spends it with only the BIP143 preimage. If this spend confirms, ' +
    'the AUTH clause validates on mainnet — do this BEFORE the full covenant. ' +
    'Dry-run builds the spend; Broadcast funds 2000 sats + sends (returns ~1000 to identity).'));

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const dryBtn = el('button', { type: 'button', class: 'run-btn' }, 'Dry-run (build spend)') as HTMLButtonElement;
  const liveBtn = el('button', { type: 'button', class: 'run-btn' }, 'Fund + broadcast (2000 sats, mainnet)') as HTMLButtonElement;

  const logResult = (r: PushtxAuthResult): void => {
    log.textContent = '';
    log.textContent += `${r.ok ? '✓' : '✗'} ${r.dryRun ? 'DRY-RUN' : 'BROADCAST'}\n`;
    log.textContent += `  auth-only lock: ${r.lockLen} bytes\n`;
    if (r.fundTxid) log.textContent += `  fund txid: ${r.fundTxid}:${r.fundVout}\n`;
    if (r.spendTxid) log.textContent += `  spend txid: ${r.spendTxid}\n`;
    if (r.broadcastTxid) log.textContent += `  ARC ack: ${r.broadcastTxid}\n`;
    if (r.efTxHex) log.textContent += `  efTx (${r.efTxHex.length / 2} B): ${r.efTxHex.slice(0, 100)}…\n`;
    log.textContent += `\n${r.summary}\n`;
  };

  const run = async (btn: HTMLButtonElement, confirm: boolean, label: string) => {
    dryBtn.disabled = true; liveBtn.disabled = true;
    btn.textContent = confirm ? 'Funding + sending…' : 'Building…';
    log.removeAttribute('hidden');
    log.textContent = confirm ? 'Funding auth-only lock + broadcasting spend on mainnet…\n' : 'Building auth-only lock + sample spend…\n';
    try {
      logResult(await runPushtxAuthTest({ confirm, fundSats: 2000, feeSats: 1000, arcUrl: ARC_URL }));
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      dryBtn.disabled = false; liveBtn.disabled = false;
      btn.textContent = label;
    }
  };

  dryBtn.addEventListener('click', () => run(dryBtn, false, 'Dry-run (build spend)'));
  liveBtn.addEventListener('click', () => {
    if (!window.confirm('Fund (2000 sats) + broadcast the OP_PUSH_TX auth test on mainnet?')) return;
    run(liveBtn, true, 'Fund + broadcast (2000 sats, mainnet)');
  });

  panel.appendChild(dryBtn);
  panel.appendChild(liveBtn);
  panel.appendChild(log);
  return panel;
}

// ── MNCA covenant genesis panel ──────────────────────────────────────
// Creates the first covenant UTXO (a self-perpetuating cell_N → cell_{N+1}
// MNCA lock) via Metanet Desktop. Creating it is safe; only a later SPEND
// executes the OP_PUSH_TX AUTH clause. The spend is built separately
// (covenant-deploy.ts buildCovenantSpend) once this UTXO confirms.

function renderCovenantGenesisPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'MNCA covenant genesis'));
  panel.appendChild(el('p', { class: 'hint' },
    'Creates the first cell_N → cell_{N+1} covenant UTXO: a Bitcoin Script lock ' +
    'whose only valid spend re-creates the same covenant with the MNCA-evolved ' +
    'state. Funds from Metanet Desktop. Creating it is SAFE (risks nothing until ' +
    'spent); the spend is built + broadcast separately and is the live test of ' +
    'the OP_PUSH_TX clause.'));

  const seedRow = el('div', { style: 'display:flex;gap:8px;align-items:center;margin-bottom:8px' });
  seedRow.appendChild(el('label', { for: 'cov-seed' }, 'Seed 3×3 (18 hex):'));
  const seedInput = el('input', {
    id: 'cov-seed', type: 'text', value: '82008200c800000000',
    style: 'width:180px;font-family:monospace',
  }) as HTMLInputElement;
  seedRow.appendChild(seedInput);
  panel.appendChild(seedRow);

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const dryBtn = el('button', { type: 'button', class: 'run-btn' }, 'Dry-run (build lock)') as HTMLButtonElement;
  const liveBtn = el('button', { type: 'button', class: 'run-btn' }, 'Create genesis (5000 sats, mainnet)') as HTMLButtonElement;

  const parseSeed = (): Uint8Array | null => {
    const h = seedInput.value.trim();
    if (!/^[0-9a-fA-F]{18}$/.test(h)) return null;
    const out = new Uint8Array(9);
    for (let i = 0; i < 9; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
    return out;
  };

  const logResult = (r: CovenantGenesisResult): void => {
    log.textContent = '';
    log.textContent += `${r.ok ? '✓' : '✗'} ${r.dryRun ? 'DRY-RUN' : 'GENESIS'}\n`;
    if (r.regionHex) log.textContent += `  seed region: ${r.regionHex}\n`;
    if (r.lockLen) log.textContent += `  covenant lock: ${r.lockLen} bytes\n`;
    if (r.genesisTxid) log.textContent += `  genesis txid: ${r.genesisTxid}  vout: ${r.vout}\n`;
    if (r.broadcastTxid) log.textContent += `  ARC ack: ${r.broadcastTxid}\n`;
    if (r.lockHex) log.textContent += `  lockHex: ${r.lockHex.slice(0, 80)}…\n`;
    log.textContent += `\n${r.summary}\n`;
  };

  const run = async (btn: HTMLButtonElement, confirm: boolean, label: string) => {
    const seed = parseSeed();
    if (!seed) { log.removeAttribute('hidden'); log.textContent = 'Seed must be exactly 18 hex chars (9 bytes).'; return; }
    dryBtn.disabled = true; liveBtn.disabled = true;
    btn.textContent = confirm ? 'Creating…' : 'Building…';
    log.removeAttribute('hidden');
    log.textContent = confirm ? 'Creating covenant genesis on mainnet via Metanet…\n' : 'Building covenant lock…\n';
    try {
      logResult(await runCovenantGenesis({ seedRegion: seed, satoshis: 5000, confirm, arcUrl: ARC_URL }));
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      dryBtn.disabled = false; liveBtn.disabled = false;
      btn.textContent = label;
    }
  };

  dryBtn.addEventListener('click', () => run(dryBtn, false, 'Dry-run (build lock)'));
  liveBtn.addEventListener('click', () => {
    if (!window.confirm('Create a real mainnet covenant genesis (5000 sats)?')) return;
    run(liveBtn, true, 'Create genesis (5000 sats, mainnet)');
  });

  panel.appendChild(dryBtn);
  panel.appendChild(liveBtn);
  panel.appendChild(log);
  return panel;
}

// ── MNCA covenant spend (advance one tick) panel ─────────────────────
// Spends a covenant UTXO into the MNCA-evolved covenant. THE live test of
// AUTH + TRANSITION + BIND on a real node. Prefilled with the first genesis
// UTXO; after each tick, paste the new spend txid + next region to chain.

function renderCovenantSpendPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'MNCA covenant spend (advance one tick)'));
  panel.appendChild(el('p', { class: 'hint' },
    'Spends an on-chain covenant UTXO into the evolved covenant — the live test ' +
    'of the full script (AUTH + TRANSITION + BIND). Broadcasts as Extended Format, ' +
    'so the genesis must already be on-chain (confirmed/mempool). Both inputs come ' +
    'from the genesis tx; value-preserving, so only the reserve fee is at stake.'));

  const mk = (label: string, id: string, value: string, w = '420px'): HTMLInputElement => {
    const row = el('div', { style: 'display:flex;gap:8px;align-items:center;margin-bottom:6px' });
    row.appendChild(el('label', { for: id, style: 'min-width:90px' }, label));
    const inp = el('input', { id, type: 'text', value, style: `width:${w};font-family:monospace` }) as HTMLInputElement;
    row.appendChild(inp);
    panel.appendChild(row);
    return inp;
  };
  const txidI = mk('cov txid:', 'cs-txid', '');
  const covVoutI = mk('cov vout:', 'cs-cv', '', '60px');
  const covSatsI = mk('cov sats:', 'cs-cs', '5000', '90px');
  const regionI = mk('region:', 'cs-rgn', '82008200c800000000', '180px');
  const feeVoutI = mk('fee vout:', 'cs-fv', '', '60px');
  const feeSatsI = mk('fee sats:', 'cs-fs', '3000', '90px');

  // Load the genesis created in THIS session — avoids re-spending a stale txid.
  const loadBtn = el('button', { type: 'button', class: 'run-btn' }, '↻ Load last genesis') as HTMLButtonElement;
  const log = el('pre', { class: 'hop-log', hidden: '' });
  loadBtn.addEventListener('click', () => {
    const g = getLastGenesis();
    log.removeAttribute('hidden');
    if (!g) { log.textContent = 'No genesis created in this session — run MNCA covenant genesis first.'; return; }
    txidI.value = g.txidDisplay; covVoutI.value = String(g.covVout); covSatsI.value = String(g.covSats);
    regionI.value = g.regionHex; feeVoutI.value = String(g.feeVout); feeSatsI.value = String(g.feeValue);
    log.textContent = `Loaded genesis ${g.txidDisplay} (cov vout ${g.covVout}=${g.covSats}, fee vout ${g.feeVout}=${g.feeValue}, region ${g.regionHex}). Now Dry-run / Broadcast.`;
  });
  panel.appendChild(loadBtn);
  const dryBtn = el('button', { type: 'button', class: 'run-btn' }, 'Dry-run (build tick)') as HTMLButtonElement;
  const liveBtn = el('button', { type: 'button', class: 'run-btn' }, 'Broadcast tick (mainnet)') as HTMLButtonElement;

  const logResult = (r: CovenantSpendResult): void => {
    log.textContent = '';
    log.textContent += `${r.ok ? '✓' : '✗'} ${r.dryRun ? 'DRY-RUN' : 'TICK'}\n`;
    if (r.regionHex) log.textContent += `  ${r.regionHex} → ${r.nextRegionHex}\n`;
    if (r.spendTxid) log.textContent += `  spend txid: ${r.spendTxid}\n`;
    if (r.broadcastTxid) log.textContent += `  ARC ack: ${r.broadcastTxid}\n`;
    if (r.efTxHex) log.textContent += `  efTx (${r.efTxHex.length / 2} B): ${r.efTxHex.slice(0, 100)}…\n`;
    log.textContent += `\n${r.summary}\n`;
  };

  const run = async (btn: HTMLButtonElement, confirm: boolean, label: string) => {
    dryBtn.disabled = true; liveBtn.disabled = true;
    btn.textContent = confirm ? 'Sending…' : 'Building…';
    log.removeAttribute('hidden');
    log.textContent = confirm ? 'Broadcasting the tick (EF) on mainnet…\n' : 'Building the tick…\n';
    try {
      logResult(await runCovenantSpend({
        covTxid: txidI.value.trim(),
        covVout: parseInt(covVoutI.value, 10),
        covSats: parseInt(covSatsI.value, 10),
        regionHex: regionI.value.trim(),
        feeVout: parseInt(feeVoutI.value, 10),
        feeSats: parseInt(feeSatsI.value, 10),
        confirm,
        arcUrl: ARC_URL,
      }));
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      dryBtn.disabled = false; liveBtn.disabled = false;
      btn.textContent = label;
    }
  };

  dryBtn.addEventListener('click', () => run(dryBtn, false, 'Dry-run (build tick)'));
  liveBtn.addEventListener('click', () => {
    if (!window.confirm('Broadcast the covenant tick on mainnet (the live AUTH test)?')) return;
    run(liveBtn, true, 'Broadcast tick (mainnet)');
  });

  panel.appendChild(dryBtn);
  panel.appendChild(liveBtn);
  panel.appendChild(log);
  return panel;
}

// ── Deep rotation + recovery test panel ──────────────────────────────

function appendDeepHopLine(pre: HTMLPreElement, hop: DeepHop): void {
  const spv = hop.spvOk ? '✓ SPV' : '✗ SPV';
  const bcast = hop.broadcastOk ? '✓ ARC' : '✗ ARC';
  pre.textContent += `${hop.label.padEnd(40)}  ${hop.satsOut} sats  ${spv}  ${bcast}\n`;
  pre.textContent += `  txid: ${hop.txid}\n`;
  pre.textContent += `  ${hop.spvDetail}\n`;
  if (hop.error) pre.textContent += `  ⚠ ${hop.error}\n`;
}

function renderDeepRotationPanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'Deep rotation + session recovery'));
  panel.appendChild(el('p', { class: 'hint' },
    'Runs N BRC-42 edge hops, then resets the runtime (simulates tab reload) and ' +
    'broadcasts the return spend from the reloaded wallet. Proves BEEF chains at depth ' +
    'and that rotated funds survive a session restart.'));

  const depthRow = el('div', { style: 'display:flex;gap:8px;align-items:center;margin-bottom:8px' });
  depthRow.appendChild(el('label', { for: 'deep-depth' }, 'Hops:'));
  const depthInput = el('input', { id: 'deep-depth', type: 'number', value: '8', min: '1', max: '32', style: 'width:60px' }) as HTMLInputElement;
  depthRow.appendChild(depthInput);
  panel.appendChild(depthRow);

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const btn = el('button', { type: 'button', class: 'run-btn' }, 'Run deep test (10,000 sats)') as HTMLButtonElement;

  btn.addEventListener('click', async () => {
    const depth = Math.max(1, Math.min(32, parseInt(depthInput.value, 10) || 8));
    btn.disabled = true;
    btn.textContent = `Running depth=${depth}…`;
    log.removeAttribute('hidden');
    log.textContent = `Funding from Metanet Desktop (depth=${depth})…\n`;

    try {
      const result = await runDeepRotationTest({ depth, satoshis: 10_000, arcUrl: ARC_URL });

      log.textContent = '';
      for (const hop of result.hops) {
        appendDeepHopLine(log, hop);
        log.textContent += '\n';
      }

      log.textContent += `\n── Session recovery (runtime wipe + IDB reload) ──\n`;
      if (result.sessionReturnHop) {
        appendDeepHopLine(log, result.sessionReturnHop);
        log.textContent += '\n';
      }
      log.textContent += (result.sessionRecoveryOk ? '✓' : '✗') + ' ' + result.sessionRecoveryDetail + '\n';

      log.textContent += `\n── Anchor UTXO recovery (cell-anchor → identity) ──\n`;
      if (result.anchorCreatedTxid) {
        log.textContent += `  anchor split txid: ${result.anchorCreatedTxid.slice(0, 16)}…\n`;
      }
      if (result.anchorReturnHop) {
        appendDeepHopLine(log, result.anchorReturnHop);
        log.textContent += '\n';
      }
      log.textContent += (result.anchorRecoveryOk ? '✓' : '✗') + ' ' + result.anchorRecoveryDetail + '\n';

      if (result.schemaMappings.length > 0) {
        log.textContent += `\n── Plexus schemaMappings export ──\n`;
        for (const m of result.schemaMappings) {
          log.textContent += `  0x${m.domainFlag.toString(16).padStart(8, '0')} → ${m.typeHashHex.slice(0, 16)}… (${m.label ?? 'unlabelled'})\n`;
        }
      }

      if (result.envelopeRecoveryDetail) {
        log.textContent += `\n── Envelope recovery (offline key check) ──\n`;
        log.textContent += (result.envelopeRecoveryOk ? '✓' : '·') + ' ' + result.envelopeRecoveryDetail + '\n';
      }

      log.textContent += '\n' + (result.allOk ? '✓ ' : '✗ ') + result.summary;
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Run deep test (10,000 sats)';
    }
  });

  panel.appendChild(btn);
  panel.appendChild(log);
  return panel;
}

// ── Chess stake-fund panel ────────────────────────────────────────────

function renderChessStakePanel(): HTMLElement {
  const panel = el('div', { class: 'hop-panel' });
  panel.appendChild(el('h3', {}, 'Chess stake — fund a game'));
  panel.appendChild(el('p', { class: 'hint' },
    'Funds Metanet Desktop → identity, then splits into two chess.stake.v1 ' +
    'cell-anchors (white + black) ready for the chess WalletPort to spend at ' +
    'resolution. Persists in the cell-anchors basket, tagged [chess, stake].'));

  const row = el('div', { class: 'hop-control-row' });
  const gameInput = el('input', { type: 'text', placeholder: 'gameId (auto if blank)', class: 'hop-input' }) as HTMLInputElement;
  const stakeInput = el('input', { type: 'number', value: '1000', min: '546', class: 'hop-input', style: 'width: 7em' }) as HTMLInputElement;
  row.appendChild(el('label', {}, 'gameId '));
  row.appendChild(gameInput);
  row.appendChild(el('label', {}, ' stake/side '));
  row.appendChild(stakeInput);
  panel.appendChild(row);

  // ARC API key — required when the wallet broadcasts directly to a
  // public ARC (Taal returns 401 without a Bearer). Stored only in this
  // page session.
  const arcKeyRow = el('div', { class: 'hop-control-row' });
  const arcKeyInput = el('input', {
    type: 'password',
    placeholder: 'ARC API key (Taal bearer; required for split broadcast)',
    class: 'hop-input',
    style: 'width: 28em',
  }) as HTMLInputElement;
  arcKeyRow.appendChild(el('label', {}, 'ARC key '));
  arcKeyRow.appendChild(arcKeyInput);
  panel.appendChild(arcKeyRow);

  const log = el('pre', { class: 'hop-log', hidden: '' });
  const btn = el('button', { type: 'button', class: 'run-btn' }, 'Fund chess game') as HTMLButtonElement;

  // ── Play deep-link — wallet → doublemate.app ──────────────────────────
  //
  // After a successful fund we know the gameId; together with an
  // operator-supplied bearer (issued via `brain bearer issue` on the
  // brain that funded the anchors) we can hand the player off into the
  // chess SPA with a single click. The bearer field is opaque to the
  // wallet — the wallet has no permission to mint brain tokens. It's
  // a paste-once-per-machine convenience, persisted to localStorage
  // under `chess.deepLink.bearer` so subsequent funds don't need to
  // re-paste it. The bearer rides in the URL fragment (#bearer=…) so
  // it never hits server logs or referer headers.
  const DEEP_LINK_BEARER_KEY = 'chess.deepLink.bearer';
  const DEEP_LINK_TARGET_KEY = 'chess.deepLink.target';
  const DEEP_LINK_BRAIN_KEY = 'chess.deepLink.brainUrl';
  const deepRow = el('div', { class: 'hop-control-row' });
  const deepBearer = el('input', {
    type: 'password',
    placeholder: 'operator bearer (64-char hex; brain-issued)',
    class: 'hop-input',
    style: 'width: 28em',
    value: (typeof localStorage !== 'undefined' ? localStorage.getItem(DEEP_LINK_BEARER_KEY) : null) ?? '',
  }) as HTMLInputElement;
  const deepTarget = el('input', {
    type: 'text',
    class: 'hop-input',
    style: 'width: 16em',
    value: (typeof localStorage !== 'undefined' ? localStorage.getItem(DEEP_LINK_TARGET_KEY) : null) ?? 'https://doublemate.app',
  }) as HTMLInputElement;
  const deepBrain = el('input', {
    type: 'text',
    class: 'hop-input',
    style: 'width: 22em',
    placeholder: 'optional brain WSS override',
    value: (typeof localStorage !== 'undefined' ? localStorage.getItem(DEEP_LINK_BRAIN_KEY) : null) ?? '',
  }) as HTMLInputElement;
  deepRow.appendChild(el('label', {}, 'bearer '));
  deepRow.appendChild(deepBearer);
  panel.appendChild(deepRow);
  const deepRow2 = el('div', { class: 'hop-control-row' });
  deepRow2.appendChild(el('label', {}, 'target '));
  deepRow2.appendChild(deepTarget);
  deepRow2.appendChild(el('label', { style: 'margin-left: 0.6em' }, ' brain '));
  deepRow2.appendChild(deepBrain);
  panel.appendChild(deepRow2);

  // The Play button is hidden until a fund succeeds — that way the
  // primary UX surface for "I just funded, now what?" is one click.
  const playBtn = el('button', {
    type: 'button',
    class: 'run-btn',
    style: 'margin-left: 0.5em',
    hidden: '',
  }, 'Play at doublemate.app →') as HTMLButtonElement;

  let lastFundedGameId: string | null = null;

  function persistDeepLinkInputs(): void {
    if (typeof localStorage === 'undefined') return;
    const b = deepBearer.value.trim();
    if (b) localStorage.setItem(DEEP_LINK_BEARER_KEY, b); else localStorage.removeItem(DEEP_LINK_BEARER_KEY);
    const t = deepTarget.value.trim();
    if (t && t !== 'https://doublemate.app') localStorage.setItem(DEEP_LINK_TARGET_KEY, t); else localStorage.removeItem(DEEP_LINK_TARGET_KEY);
    const br = deepBrain.value.trim();
    if (br) localStorage.setItem(DEEP_LINK_BRAIN_KEY, br); else localStorage.removeItem(DEEP_LINK_BRAIN_KEY);
  }

  function buildDeepLink(gameId: string): string {
    const target = (deepTarget.value.trim() || 'https://doublemate.app').replace(/\/$/, '');
    const search = `?invite=${encodeURIComponent(gameId)}`;
    const hashParts: string[] = [];
    const b = deepBearer.value.trim();
    if (b) hashParts.push(`bearer=${encodeURIComponent(b)}`);
    const br = deepBrain.value.trim();
    if (br) hashParts.push(`brain=${encodeURIComponent(br)}`);
    return `${target}/${search}${hashParts.length ? '#' + hashParts.join('&') : ''}`;
  }

  playBtn.addEventListener('click', () => {
    if (!lastFundedGameId) return;
    persistDeepLinkInputs();
    if (!deepBearer.value.trim()) {
      log.textContent += '\n⚠ paste an operator bearer first (issue with `brain bearer issue` on the brain that funded the anchors).';
      return;
    }
    const url = buildDeepLink(lastFundedGameId);
    window.open(url, '_blank', 'noopener,noreferrer');
  });

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.textContent = 'Funding…';
    log.removeAttribute('hidden');
    log.textContent = 'Requesting funds from Metanet Desktop…\n';
    playBtn.setAttribute('hidden', '');
    lastFundedGameId = null;

    try {
      const stakeSats = Math.max(546, Number(stakeInput.value) || 1000);
      const gameId = gameInput.value.trim() || undefined;
      const arcApiKey = arcKeyInput.value.trim() || undefined;
      const result: ChessStakeResult = await runChessStakeTest({ stakeSats, gameId, arcUrl: ARC_URL, arcApiKey });

      log.textContent = '';
      log.textContent += `identity: ${result.identityPkHex.slice(0, 16)}…\n`;
      log.textContent += `gameId:   ${result.gameId}\n`;
      if (result.fundTxid) log.textContent += `fund tx:  ${result.fundTxid}\n`;
      if (result.splitTxid) log.textContent += `split tx: ${result.splitTxid}\n`;
      for (const a of result.anchors) {
        log.textContent += `  anchor[${a.color}] idx=${a.anchorIndex} sats=${a.satoshis} → ${a.outpointTxid}:${a.outpointVout}\n`;
      }
      log.textContent += `domainFlag: 0x${result.schemaMapping.domainFlag.toString(16).padStart(8, '0')}  (typeHash chess.stake.v1)\n`;
      log.textContent += (result.ok ? '✓ ' : '✗ ') + (result.summary || result.error || '');

      if (result.ok) {
        lastFundedGameId = result.gameId;
        playBtn.removeAttribute('hidden');
        // Hint at the deep link so operators can copy it manually too.
        persistDeepLinkInputs();
        const url = buildDeepLink(result.gameId);
        const safeForLog = deepBearer.value.trim()
          ? url.replace(/bearer=[^&]+/, 'bearer=<hidden>')
          : url;
        log.textContent += `\n→ ${safeForLog}`;
      }
    } catch (e) {
      log.textContent += `Error: ${(e as Error).message}`;
    } finally {
      btn.disabled = false;
      btn.textContent = 'Fund chess game';
    }
  });

  // ── Export manifest — feeds the brain's chess_wallet_port ─────────
  const exportBtn = el(
    'button',
    { type: 'button', class: 'run-btn', style: 'margin-left: 0.5em' },
    'Export anchors manifest',
  ) as HTMLButtonElement;
  exportBtn.addEventListener('click', async () => {
    exportBtn.disabled = true;
    exportBtn.textContent = 'Building…';
    try {
      const filter = gameInput.value.trim() || undefined;
      const json = await buildChessManifestJson(filter);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `chess-anchors-manifest-${filter ?? 'all'}-${Date.now()}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      log.removeAttribute('hidden');
      log.textContent += `\n✓ exported manifest (${(json.length / 1024).toFixed(1)} KB)`;
      log.textContent += `\n   → SCP to rbs: scp <file> todd@rbs:/var/lib/semantos/chess/manifest.json`;
      log.textContent += `\n   → Then: sudo systemctl restart semantos-shell.service`;
    } catch (e) {
      log.removeAttribute('hidden');
      log.textContent += `\n✗ export failed: ${(e as Error).message}`;
    } finally {
      exportBtn.disabled = false;
      exportBtn.textContent = 'Export anchors manifest';
    }
  });

  // ── Claim winnings — browser-native payout (no key export) ───────────
  // Reads anchor UTXOs from outputStore (IndexedDB), queries the brain for
  // the game result, builds + signs the spend tx in this browser tab, and
  // broadcasts to ARC. The identity sk never leaves memory.
  const claimRow = el('div', { class: 'hop-control-row', style: 'margin-top: 0.6em' });
  const claimDryCheck = el('input', { type: 'checkbox', id: 'chess-claim-dry', checked: '' }) as HTMLInputElement;
  claimRow.appendChild(claimDryCheck);
  claimRow.appendChild(el('label', { for: 'chess-claim-dry', style: 'margin-left: 0.3em; margin-right: 0.8em' }, 'dry-run (build tx, don\'t broadcast)'));
  panel.appendChild(claimRow);

  const claimBtn = el(
    'button',
    { type: 'button', class: 'run-btn', style: 'margin-left: 0.5em' },
    'Claim winnings',
  ) as HTMLButtonElement;
  claimBtn.title = 'Builds (and optionally broadcasts) the payout tx entirely in this browser — no key export, no server needed.';
  claimBtn.addEventListener('click', async () => {
    const gId = gameInput.value.trim();
    if (!gId) {
      log.removeAttribute('hidden');
      log.textContent += '\n⚠ enter a gameId in the field above first';
      return;
    }
    const bearer = deepBearer.value.trim();
    if (!bearer) {
      log.removeAttribute('hidden');
      log.textContent += '\n⚠ paste an operator bearer in the bearer field above first';
      return;
    }
    let brainUrl = deepBrain.value.trim();
    if (!brainUrl) {
      brainUrl = 'wss://brain.oddjobtodd.info/api/v1/wallet';
    }
    // Accept http(s) URLs and convert them to ws(s)
    brainUrl = brainUrl.replace(/^https:\/\//, 'wss://').replace(/^http:\/\//, 'ws://');

    const dry = claimDryCheck.checked;
    claimBtn.disabled = true;
    claimBtn.textContent = dry ? 'Building (dry-run)…' : 'Claiming…';
    log.removeAttribute('hidden');
    log.textContent += `\n${dry ? '[dry-run] ' : ''}Claiming winnings for game ${gId}…\n`;

    try {
      const result = await claimChessWinnings({
        gameId: gId,
        brainUrl,
        bearer,
        arcUrl: ARC_URL,
        dryRun: dry,
      });

      if (result.ok) {
        log.textContent += `✓ ${result.summary}\n`;
        if (result.winner) log.textContent += `  winner: ${result.winner}\n`;
        if (result.isDraw) log.textContent += `  result: draw (pot split)\n`;
        if (result.payoutSats !== undefined) log.textContent += `  payout: ${result.payoutSats} sats\n`;
        if (result.txidBe) {
          log.textContent += `  txid: ${result.txidBe}\n`;
          if (!result.dryRun && result.arcTxid) {
            log.textContent += `  → https://whatsonchain.com/tx/${result.arcTxid}\n`;
          }
        }
        if (result.dryRun) log.textContent += '  (dry-run — uncheck "dry-run" and re-click to broadcast)\n';
      } else {
        log.textContent += `✗ claim failed: ${result.error}\n`;
      }
    } catch (e) {
      log.textContent += `✗ Error: ${(e as Error).message}\n`;
    } finally {
      claimBtn.disabled = false;
      claimBtn.textContent = 'Claim winnings';
    }
  });

  panel.appendChild(btn);
  panel.appendChild(exportBtn);
  panel.appendChild(claimBtn);
  panel.appendChild(playBtn);
  panel.appendChild(log);
  return panel;
}

// ── History tab ───────────────────────────────────────────────────────

function renderHistoryTab(): HTMLElement {
  const wrap = el('div', { class: 'history-tab' });
  const runs = loadHistory();

  if (runs.length === 0) {
    wrap.appendChild(el('p', { class: 'history-empty' },
      'No runs yet — press Run test on the Wallet tab to create a record.'));
    return wrap;
  }

  for (const run of runs) {
    const card = el('div', { class: `run-card${run.result.allOk ? ' ok' : ' fail'}` });

    const hdr = el('div', { class: 'run-header' });
    hdr.appendChild(el('span', { class: 'run-ts' }, formatTs(run.ts)));
    hdr.appendChild(el('span', { class: 'run-summary' },
      (run.result.allOk ? '✓ ' : '✗ ') + run.result.summary));
    card.appendChild(hdr);

    for (const hop of run.result.hops) {
      const row = el('div', { class: 'hop-row' });

      const meta = el('span', { class: 'hop-meta' });
      meta.textContent =
        `hop-${hop.hop}  ${hop.satoshis} sats` +
        (hop.blockHeight != null ? `  block ${hop.blockHeight}` : '') +
        `  ${hop.spvOk ? '✓ SPV' : '✗ SPV'}  ${hop.scriptOk ? '✓ scripts' : '✗ scripts'}`;
      row.appendChild(meta);

      const linkTxid = hop.broadcastTxid ?? (hop.hop === 0 ? hop.txid : null);
      if (linkTxid && !linkTxid.startsWith('(')) {
        const link = el('a', {
          class: 'txid-link',
          href: `https://whatsonchain.com/tx/${linkTxid}`,
          target: '_blank',
          rel: 'noopener noreferrer',
        }, linkTxid);
        row.appendChild(link);
      } else if (hop.txid && !hop.txid.startsWith('(')) {
        const txEl = el('span', { class: 'txid-link' }, hop.txid);
        const note = el('span', { class: 'hop-meta' }, ' (BEEF valid, not broadcast)');
        row.appendChild(txEl);
        row.appendChild(note);
      }

      card.appendChild(row);
    }

    wrap.appendChild(card);
  }

  return wrap;
}

function formatTs(ms: number): string {
  const d = new Date(ms);
  return d.toLocaleString(undefined, {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

// ── Create-wallet form ─────────────────────────────────────────────────

function renderCreateForm(onSubmit: (input: CreateWalletInput) => Promise<void>): HTMLElement {
  const form = el('form', { class: 'create-form' });
  form.appendChild(el('h2', {}, 'Create wallet'));
  form.appendChild(el('p', { class: 'hint' }, 'Your keys are generated locally and never leave this device.'));

  function field(id: string, label: string, type = 'text', placeholder = ''): HTMLInputElement {
    const wrap = el('div', { class: 'field' });
    const lbl = el('label', { for: id }, label);
    const inp = el('input', { id, name: id, type, placeholder, autocomplete: 'off' });
    wrap.appendChild(lbl);
    wrap.appendChild(inp);
    form.appendChild(wrap);
    return inp;
  }

  const emailInp = field('email', 'Contact email', 'email', 'you@example.com');
  const pinInp = field('pin', 'Tier-1 PIN (daily use)', 'password', '4–8 digits');
  const t2Inp = field('t2', 'Tier-2 passphrase', 'password', 'for larger amounts');
  const t3Inp = field('t3', 'Tier-3 vault passphrase', 'password', 'for vault holdings');

  form.appendChild(el('h3', {}, 'Recovery questions'));
  form.appendChild(el('p', { class: 'hint' }, 'Your answers encrypt the recovery seed — never share them.'));

  const q1Inp = field('q1', 'Question 1', 'text', 'e.g. First pet\'s name?');
  const a1Inp = field('a1', 'Answer 1', 'password');
  const q2Inp = field('q2', 'Question 2', 'text', 'e.g. Mother\'s maiden name?');
  const a2Inp = field('a2', 'Answer 2', 'password');
  const q3Inp = field('q3', 'Question 3', 'text', 'e.g. Childhood nickname?');
  const a3Inp = field('a3', 'Answer 3', 'password');

  const err = el('p', { class: 'error', hidden: '' });
  form.appendChild(err);

  const btn = el('button', { type: 'submit' }, 'Create wallet');
  form.appendChild(btn);

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    err.removeAttribute('hidden');
    err.textContent = '';

    const pin = pinInp.value.trim();
    const t2 = t2Inp.value;
    const t3 = t3Inp.value;
    const email = emailInp.value.trim();
    const q1 = q1Inp.value.trim();
    const a1 = a1Inp.value;
    const q2 = q2Inp.value.trim();
    const a2 = a2Inp.value;
    const q3 = q3Inp.value.trim();
    const a3 = a3Inp.value;

    if (!email || !pin || !t2 || !t3 || !q1 || !a1 || !q2 || !a2 || !q3 || !a3) {
      err.textContent = 'All fields are required.';
      return;
    }

    btn.disabled = true;
    btn.textContent = 'Creating…';
    try {
      await onSubmit({
        contactEmail: email,
        tier1Pin: new TextEncoder().encode(pin),
        tier2Factor: new TextEncoder().encode(t2),
        tier3Factor: new TextEncoder().encode(t3),
        challengeQuestions: [q1, q2, q3],
        challengeAnswers: [a1, a2, a3],
      });
    } catch (e) {
      err.textContent = (e as Error).message;
      btn.disabled = false;
      btn.textContent = 'Create wallet';
    }
  });

  return form;
}

// ── Main boot ─────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const root = document.getElementById('app');
  if (!root) return;

  root.textContent = 'Booting…';

  // 1. WASM
  let wasmLoaded = false;
  let wasmError = '';
  try {
    await bootEngine();
    wasmLoaded = true;
  } catch (e) {
    wasmError = (e as Error).message ?? String(e);
    console.error('WASM boot failed:', e);
  }

  // 2. Load wallet
  const loadResult = await loadWallet();

  if (!loadResult.ok && loadResult.error.kind === 'NOT_CREATED') {
    const form = renderCreateForm(async (input) => {
      const res = await createWallet(input);
      if (!res.ok) {
        throw new Error(res.error.kind);
      }
      await bootAndShowStatus(wasmLoaded, wasmError);
    });
    root.innerHTML = '';
    root.appendChild(form);
    return;
  }

  if (!loadResult.ok) {
    root.textContent = `Wallet error: ${loadResult.error.kind}`;
    return;
  }

  await bootAndShowStatus(wasmLoaded, wasmError);
}

async function bootAndShowStatus(wasmLoaded: boolean, wasmError = ''): Promise<void> {
  const root = document.getElementById('app');
  if (!root) return;

  await unlockIdentityFromCache();

  let identityPkHex = '(locked)';
  try {
    const snap = getIdentitySnapshot();
    identityPkHex = Array.from(snap.identityPk)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  } catch {
    // identity not yet unlocked — show placeholder
  }

  const panel = renderStatus({ identityPkHex, tip: null, wasmLoaded, wasmError });
  root.innerHTML = '';
  root.appendChild(panel);

  const tip = await fetchTip();
  if (tip) {
    const tipEl = root.querySelector<HTMLElement>('.row:last-of-type span:last-child');
    if (tipEl && tipEl.textContent === 'fetching…') {
      tipEl.textContent = `#${tip.height}  ${tip.hash.slice(0, 16)}…`;
    }
    setInterval(async () => {
      const latest = await fetchTip();
      if (latest) {
        const el = root.querySelector<HTMLElement>('[data-tip]');
        if (el) el.textContent = `#${latest.height}  ${latest.hash.slice(0, 16)}…`;
      }
    }, 30_000);
  }
}

// Kick off once DOM is ready.
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => main().catch(console.error));
  } else {
    main().catch(console.error);
  }
}

```
