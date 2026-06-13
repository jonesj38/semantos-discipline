---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-headers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.659884+00:00
---

# cartridges/wallet-headers/brain/src/popup-headers.ts

```ts
// Phase WH6 — Trustless SPV: wizard / settings / badge UI surface.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH6).
//
// Pure formatting + state-shape module. Renders three things:
//
//   1. The trust-model badge — one line, one click → opens the settings panel.
//
//          ✓ SPV: verified locally · tip 894,231 · source: headers.semantos.app
//
//   2. The settings panel — SPV mode picker, source list editor, sync state
//      summary, "Download full chain" CTA. The panel is data-only here;
//      DOM mounting lives in popup.ts when the user opens the panel.
//
//   3. The wizard nudge — "You've made N spends. Download the full chain
//      (≈35 MB) for offline use?" gated behind spend count + opt-out.
//
// All wizard state persists via the existing KV layer (storage.ts) under
// `headers/*` keys. The trust-model is the most important UI surface — never
// hidden by default, always hover-explainable.

import { kvGet, kvPut } from './storage';
import { LocalHeaderStore } from './header-store';
import type { SpvMode } from './header-spv';
import type { HeaderSource, SourceKind } from './header-source-adapter';

// ─────────────────────────────────────────────────────────────────────
// Persisted state
// ─────────────────────────────────────────────────────────────────────

const KV_KEYS = {
  SOURCE_LIST: 'headers/source_list',
  SPV_MODE: 'headers/spv_mode',
  SPENDS_SINCE_NUDGE: 'headers/spends_since_nudge',
  NUDGE_DISMISSED_AT: 'headers/nudge_dismissed_at',
} as const;

/** Header-fetch state; tracked so the wizard can decide whether to nudge. */
export type HeadersSyncState = 'NEVER_SYNCED' | 'PARTIAL' | 'UP_TO_DATE';

/**
 * Default source list. `headers.semantos.app` is the recommended primary;
 * fallbacks are stable third-party operators that publish public endpoints.
 * Users can edit this freely; a hostile dApp's suggested source can be
 * appended without compromising trust because PoW validation runs locally.
 */
export const DEFAULT_SOURCES: HeaderSource[] = [
  { kind: 'bhs', baseUrl: 'https://headers.semantos.app', label: 'headers.semantos.app' },
];

export async function getSourceList(): Promise<HeaderSource[]> {
  const cached = await kvGet<HeaderSource[]>(KV_KEYS.SOURCE_LIST);
  if (cached && Array.isArray(cached) && cached.length > 0) return cached;
  return [...DEFAULT_SOURCES];
}

export async function setSourceList(sources: HeaderSource[]): Promise<void> {
  if (sources.length === 0) {
    throw new Error('source list must contain at least one entry');
  }
  await kvPut(KV_KEYS.SOURCE_LIST, sources);
}

export async function addSource(source: HeaderSource): Promise<void> {
  const list = await getSourceList();
  // De-duplicate by base URL — operators can't accidentally double-add.
  if (list.some((s) => s.baseUrl === source.baseUrl)) return;
  list.push(source);
  await setSourceList(list);
}

export async function removeSource(baseUrl: string): Promise<void> {
  const list = await getSourceList();
  const next = list.filter((s) => s.baseUrl !== baseUrl);
  if (next.length === 0) {
    throw new Error('cannot remove the last source — add a replacement first');
  }
  await setSourceList(next);
}

export async function getSpvMode(): Promise<SpvMode> {
  const v = await kvGet<SpvMode>(KV_KEYS.SPV_MODE);
  return v ?? 'hybrid';
}

export async function setSpvMode(mode: SpvMode): Promise<void> {
  await kvPut(KV_KEYS.SPV_MODE, mode);
}

// ─────────────────────────────────────────────────────────────────────
// Sync-state heuristic
// ─────────────────────────────────────────────────────────────────────

/**
 * Classify the wallet's current header-store state against an estimate of
 * the chain tip. We don't try to be precise about what "tip" means here —
 * any tip the wallet has *seen* via the WH4 subscriber counts. The wizard
 * uses this purely as a UX nudge gate.
 *
 *   • NEVER_SYNCED — store empty
 *   • PARTIAL      — store has a tip, but it's > 144 blocks behind the
 *                    estimated tip (≈ 1 day's worth of headers)
 *   • UP_TO_DATE   — store tip is within 144 blocks of estimated tip
 *
 * If `estimatedTipHeight` is null (we've never seen one), missing-but-
 * non-empty store is treated as UP_TO_DATE (the wallet has done at least
 * one hybrid lookup).
 */
export async function getHeadersSyncState(
  store: LocalHeaderStore,
  estimatedTipHeight: number | null,
): Promise<{ state: HeadersSyncState; localTipHeight: number | null }> {
  const tip = await store.tip();
  if (!tip) return { state: 'NEVER_SYNCED', localTipHeight: null };
  if (estimatedTipHeight == null) {
    return { state: 'UP_TO_DATE', localTipHeight: tip.height };
  }
  const lag = estimatedTipHeight - tip.height;
  return {
    state: lag > 144 ? 'PARTIAL' : 'UP_TO_DATE',
    localTipHeight: tip.height,
  };
}

// ─────────────────────────────────────────────────────────────────────
// Badge formatting (the most important UI surface — pure data)
// ─────────────────────────────────────────────────────────────────────

export interface BadgeFields {
  /** Single-line visible label, e.g.,
   *  "✓ SPV: verified locally · tip 894,231 · source: headers.semantos.app" */
  label: string;
  /** Tooltip / aria-label expanding "verified locally". */
  tooltip: string;
  /** A11y class hint: "ok" | "partial" | "warning". The popup styles each. */
  status: 'ok' | 'partial' | 'warning';
}

export interface BadgeInputs {
  mode: SpvMode;
  syncState: HeadersSyncState;
  localTipHeight: number | null;
  primarySource: HeaderSource;
}

export function formatBadge(inputs: BadgeInputs): BadgeFields {
  const { mode, syncState, localTipHeight, primarySource } = inputs;
  const sourceLabel = primarySource.label ?? primarySource.baseUrl.replace(/^https?:\/\//, '');
  let prefix: string;
  let status: BadgeFields['status'];
  let tooltip: string;
  switch (mode) {
    case 'strict':
      prefix = '✓ SPV: verified locally';
      status = syncState === 'NEVER_SYNCED' ? 'warning' : syncState === 'PARTIAL' ? 'partial' : 'ok';
      tooltip = 'Every BEEF this wallet accepts is verified against PoW-validated headers stored locally. No external indexer is trusted.';
      break;
    case 'hybrid':
      prefix = '✓ SPV: verified locally';
      status = syncState === 'NEVER_SYNCED' ? 'partial' : 'ok';
      tooltip = 'Headers are verified locally via PoW. Missing heights are lazy-fetched on demand.';
      break;
    case 'gullible':
      prefix = '⚠ SPV: gullible (DEBUG)';
      status = 'warning';
      tooltip = 'WARNING: gullible mode skips merkle-root verification. Use only in tests.';
      break;
  }
  const tipPart = localTipHeight != null ? ` · tip ${formatHeight(localTipHeight)}` : '';
  return {
    label: `${prefix}${tipPart} · source: ${sourceLabel}`,
    tooltip,
    status,
  };
}

function formatHeight(h: number): string {
  return h.toLocaleString();
}

// ─────────────────────────────────────────────────────────────────────
// Settings panel (data shape — DOM lives in popup.ts)
// ─────────────────────────────────────────────────────────────────────

export interface SettingsPanelState {
  mode: SpvMode;
  sources: HeaderSource[];
  syncState: HeadersSyncState;
  localTipHeight: number | null;
  /** Last update time as wall-clock seconds (for "12s ago" formatting). */
  lastUpdateAtSeconds: number | null;
}

export async function loadSettingsPanelState(
  store: LocalHeaderStore,
  estimatedTipHeight: number | null,
): Promise<SettingsPanelState> {
  const [mode, sources, sync] = await Promise.all([
    getSpvMode(),
    getSourceList(),
    getHeadersSyncState(store, estimatedTipHeight),
  ]);
  return {
    mode,
    sources,
    syncState: sync.state,
    localTipHeight: sync.localTipHeight,
    lastUpdateAtSeconds: sync.localTipHeight != null ? Math.floor(Date.now() / 1000) : null,
  };
}

// ─────────────────────────────────────────────────────────────────────
// Wizard nudge
// ─────────────────────────────────────────────────────────────────────

/** Bumped every time the wallet records a successful spend that consumed
 *  one or more BEEFs. Reset whenever the user dismisses the nudge or
 *  triggers a bulk sync. */
export async function bumpSpendCounter(): Promise<number> {
  const cur = (await kvGet<number>(KV_KEYS.SPENDS_SINCE_NUDGE)) ?? 0;
  const next = cur + 1;
  await kvPut(KV_KEYS.SPENDS_SINCE_NUDGE, next);
  return next;
}

export async function dismissNudge(): Promise<void> {
  await kvPut(KV_KEYS.NUDGE_DISMISSED_AT, Math.floor(Date.now() / 1000));
  await kvPut(KV_KEYS.SPENDS_SINCE_NUDGE, 0);
}

export interface NudgeDecision {
  show: boolean;
  reason?: string;
}

const NUDGE_AFTER_SPENDS = 5;
const NUDGE_AFTER_DAYS = 7;

/** Decide whether to surface the "download full chain" wizard nudge. */
export async function shouldNudgeFullSync(
  store: LocalHeaderStore,
): Promise<NudgeDecision> {
  const tip = await store.tip();
  if (!tip) {
    // Pre-first-spend: don't pester. The wizard surface for NEVER_SYNCED
    // lives elsewhere (the wallet-create flow optionally offers it).
    return { show: false, reason: 'never_synced' };
  }
  const dismissedAt = (await kvGet<number>(KV_KEYS.NUDGE_DISMISSED_AT)) ?? 0;
  if (dismissedAt > 0) {
    const ageDays = (Math.floor(Date.now() / 1000) - dismissedAt) / (24 * 60 * 60);
    if (ageDays < NUDGE_AFTER_DAYS) {
      return { show: false, reason: 'recently_dismissed' };
    }
  }
  const spends = (await kvGet<number>(KV_KEYS.SPENDS_SINCE_NUDGE)) ?? 0;
  if (spends < NUDGE_AFTER_SPENDS) {
    return { show: false, reason: 'below_threshold' };
  }
  return { show: true };
}

// ─────────────────────────────────────────────────────────────────────
// Source-kind probe (helper for "Add custom source" UX)
// ─────────────────────────────────────────────────────────────────────

/**
 * Tries to determine whether a base URL exposes the BHS or Teranode API
 * shape. v0.1 probes BHS's tip endpoint first since it's cheaper to detect
 * (single GET to a well-known path); on 404 falls back to Teranode's
 * `/best-block-header`.
 *
 * Returns null on inconclusive responses — caller asks the user to pick
 * the kind explicitly.
 */
export async function probeSourceKind(baseUrl: string): Promise<SourceKind | null> {
  try {
    const r = await fetch(`${baseUrl}/api/v1/chain/header/byHeight/tip`, {
      method: 'HEAD',
      // 5-second timeout via AbortController.
      signal: AbortSignal.timeout(5_000),
    });
    if (r.status === 200 || r.status === 204) return 'bhs';
  } catch {
    /* fall through */
  }
  try {
    const r = await fetch(`${baseUrl}/best-block-header`, {
      method: 'HEAD',
      signal: AbortSignal.timeout(5_000),
    });
    if (r.status === 200 || r.status === 204) return 'teranode';
  } catch {
    /* fall through */
  }
  return null;
}

```
