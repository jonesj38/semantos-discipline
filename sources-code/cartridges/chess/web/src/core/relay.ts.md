---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/relay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.429764+00:00
---

# cartridges/chess/web/src/core/relay.ts

```ts
/**
 * Chess-game cell-relay wrapper.
 *
 * Re-exports `RelayClient` from `@semantos/world-sdk/relay` with the
 * room-id derivation tuned for chess: `/room/<id>` in the URL becomes the
 * room id (matches the jam-room convention so a single cell-relay node can
 * host both world-apps), and `?invite=<id>` populates the same field when
 * the link arrives as a query string (chess-create-game produces invite
 * URLs of the form `https://chess.semantos.me/?invite=chess-abc123`).
 */
export { RelayClient, type RelayCallbacks, type SerializedCell, type LivePayload } from '@semantos/world-sdk/relay';

export function roomFromLocation(): string {
  if (typeof location === 'undefined') return 'lobby';
  const path = location.pathname.match(/^\/room\/([a-z0-9][a-z0-9_-]{1,48}[a-z0-9])$/i);
  if (path) return path[1].toLowerCase();
  const invite = new URLSearchParams(location.search).get('invite');
  if (invite && /^[a-z0-9][a-z0-9_-]{1,48}[a-z0-9]$/i.test(invite)) {
    return invite.toLowerCase();
  }
  return 'lobby';
}

/**
 * Cell-relay WSS URL resolution order:
 *   1. `localStorage.chess.relayUrl` — operator override at runtime
 *   2. `import.meta.env.VITE_RELAY_WSS_URL` — set at build time per
 *      target (production points at relay.semantos.me)
 *   3. localhost fallback — `ws://<hostname>:5178/`
 *
 * Wire-format note: the cell-relay-beam BEAM listener (CellRelay.WSHandler
 * in runtime/world-beam/apps/cell_relay) routes WebSocket upgrades on the
 * BARE root path `/` with `?room=…&as=…` query params, NOT on `/relay/
 * socket` (which is Phoenix's convention, used by `world.semantos.me`).
 * The `as=` field carries the participant's identity; it maps to what
 * the client calls `handle`.
 */
export function defaultRelayUrl(roomId: string, handle: string): string {
  const params = new URLSearchParams({ room: roomId, as: handle });
  const base = resolveRelayBase();
  const sep = base.includes('?') ? '&' : '?';
  return `${base}${sep}${params.toString()}`;
}

function resolveRelayBase(): string {
  if (typeof localStorage !== 'undefined') {
    const override = localStorage.getItem('chess.relayUrl');
    if (override) return override;
  }
  const fromEnv = (import.meta as ImportMeta & { env?: Record<string, string> }).env?.VITE_RELAY_WSS_URL;
  if (fromEnv) return fromEnv;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  return `${proto}://${location.hostname || 'localhost'}:5178/`;
}

```
