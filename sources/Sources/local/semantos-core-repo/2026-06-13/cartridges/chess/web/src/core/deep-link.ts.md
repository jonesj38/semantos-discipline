---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/deep-link.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.430645+00:00
---

# cartridges/chess/web/src/core/deep-link.ts

```ts
/**
 * Deep-link handoff from wallet.html into the chess-game SPA.
 *
 * Wallet UIs (`headers.semantos.me/wallet.html` chess-stake panel)
 * produce a funded game id and an operator bearer token. Rather than
 * making the player copy-paste both, the wallet builds a URL like:
 *
 *   https://doublemate.app/?invite=<gameId>#bearer=<hex64>&brain=<wssUrl>
 *
 * The `#fragment` carries the bearer because URL fragments are NEVER
 * sent to servers (no access logs, no referrer-header leak), unlike
 * `?query` parameters. The gameId stays in the querystring because
 * `?invite=` is the public invite URL shape already exposed in the
 * game record (see App.svelte::inviteUrl) — that one is fine to log.
 *
 * After consuming the hash we clear it (`history.replaceState`) so the
 * back-button or a "copy URL" doesn't surface the bearer.
 */

export interface DeepLink {
  /** From `?invite=<id>` — same path roomFromLocation() uses. */
  gameId?: string;
  /** From `#bearer=<hex>` — operator token for the brain JSON-RPC. */
  bearer?: string;
  /** From `#brain=<wssUrl>` — optional brain override. */
  brainUrl?: string;
}

const BEARER_RE = /^[0-9a-f]{64}$/i;
const GAMEID_RE = /^[a-z0-9][a-z0-9_-]{1,48}[a-z0-9]$/i;

/**
 * Read deep-link params off `window.location`. The gameId comes from
 * `?invite=`; bearer + brain come from the hash. Returns an empty
 * object if `window` is unavailable (SSR-safe).
 */
export function readDeepLink(): DeepLink {
  if (typeof location === 'undefined') return {};
  const out: DeepLink = {};

  const invite = new URLSearchParams(location.search).get('invite') ?? '';
  if (GAMEID_RE.test(invite)) out.gameId = invite.toLowerCase();

  const hash = location.hash.startsWith('#') ? location.hash.slice(1) : location.hash;
  if (hash) {
    const params = new URLSearchParams(hash);
    const bearer = params.get('bearer');
    if (bearer && BEARER_RE.test(bearer)) out.bearer = bearer.toLowerCase();
    const brain = params.get('brain');
    if (brain) {
      // Only honour the override if it actually parses as a ws[s]:// URL.
      try {
        const u = new URL(brain);
        if (u.protocol === 'ws:' || u.protocol === 'wss:') out.brainUrl = u.toString();
      } catch { /* ignore malformed override */ }
    }
  }

  return out;
}

/**
 * Strip the bearer (and brain override) from the URL after we've read
 * them into the app state. The `?invite=` querystring stays — it's the
 * canonical invite URL shape. Uses `replaceState` so no history entry
 * is added.
 */
export function clearDeepLinkHash(): void {
  if (typeof history === 'undefined' || typeof location === 'undefined') return;
  if (!location.hash) return;
  history.replaceState(null, '', `${location.pathname}${location.search}`);
}

```
