---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/wss-encode-dispatcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.127539+00:00
---

# runtime/legacy-ingest/src/wss-encode-dispatcher.ts

```ts
/**
 * D-RTC.4-followup — WSS-backed implementation of `EncodeDispatcher`.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Resolved decisions /
 * DECISION-10; runtime/semantos-brain/src/entity_encode_walker.zig.
 *
 * Opens a fresh WSS connection per dispatch, sends a JSON-RPC
 * `verb.dispatch` frame with extensionId="substrate", verb="entity.
 * encode" and the EntityEncodeRequest as params, waits for the
 * response, returns the minted cell_id hex.
 *
 * Mirrors the connection-per-request shape used by
 * `cell-writer/brain-rpc.ts::BrainRpcCellWriter` so the failure
 * modes + transport semantics stay consistent across the two
 * dispatcher seams. Phase 2 may pool connections; Phase 1 keeps
 * the simpler one-shot shape.
 */

import type {
  EncodeDispatcher,
} from './reingest-worker';
import type { EntityEncodeRequest } from './cell-encoder';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

export interface WssEncodeDispatcherOpts {
  /**
   * WSS URL of the brain's wallet endpoint, e.g.
   *   ws://localhost:8080/api/v1/wallet
   *   ws://rbs:8080/api/v1/wallet
   */
  readonly wsRpcUrl: string;
  /** Default 60s. The brain encode + cell-store write is fast (<10ms typical). */
  readonly timeoutMsPerCall?: number;
  /**
   * WebSocket constructor override — tests inject a stub; production
   * uses `globalThis.WebSocket` (Bun ships it natively).
   */
  readonly webSocketCtor?: typeof WebSocket;
  /**
   * Optional bearer token. The brain's /api/v1/wallet endpoint
   * currently has the operator-auth gate; in V1 production this is
   * usually omitted and the wallet endpoint accepts unauth (per
   * memory `brain_auth_model_intent`). Reserved for V2 when the
   * full auth ladder lands.
   */
  readonly bearerToken?: string;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public class
 * ────────────────────────────────────────────────────────────────────── */

const DEFAULT_TIMEOUT_MS = 60_000;

export class WssEncodeDispatcher implements EncodeDispatcher {
  private rpcCounter = 0;
  private readonly opts: WssEncodeDispatcherOpts;

  constructor(opts: WssEncodeDispatcherOpts) {
    this.opts = opts;
  }

  async dispatch(req: EntityEncodeRequest): Promise<string> {
    const Ctor = this.opts.webSocketCtor ?? globalThis.WebSocket;
    if (typeof Ctor !== 'function') {
      throw new Error(
        'WssEncodeDispatcher: no WebSocket implementation available (set opts.webSocketCtor or run on Bun/Node ≥21)',
      );
    }
    const id = ++this.rpcCounter;
    const params = {
      extensionId: 'substrate',
      verb: 'entity.encode',
      params: {
        tag: req.spec.tag,
        linearity: req.linearity,
        owner_id_hex: req.ownerIdHex,
        payload_json: req.payloadJson,
      },
    };
    const request = JSON.stringify({
      jsonrpc: '2.0',
      method: 'verb.dispatch',
      params,
      id,
    });

    // The brain's /api/v1/wallet upgrade is bearer-gated in
    // single-operator mode. It accepts the token via the Authorization
    // header OR a `?bearer=<hex64>` query param (see
    // cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/reactor.zig
    // — `extractBearerFromParsed`). The browser/Bun WebSocket
    // constructor can't reliably set request headers, so when a token
    // is supplied we carry it as the query param. Without this every
    // upgrade is refused with 401 and the client sees a 1002
    // "Expected 101 status code" close — which is exactly why the
    // legacy reingest could never reach the live brain.
    const wsUrl = this.opts.bearerToken
      ? this.opts.wsRpcUrl +
        (this.opts.wsRpcUrl.includes('?') ? '&' : '?') +
        'bearer=' +
        encodeURIComponent(this.opts.bearerToken)
      : this.opts.wsRpcUrl;

    return await new Promise<string>((resolve, reject) => {
      let ws: WebSocket;
      try {
        ws = new Ctor(wsUrl);
      } catch (err) {
        reject(new Error(`WssEncodeDispatcher: WS construct failed: ${describe(err)}`));
        return;
      }

      let settled = false;
      const finish = (outcome: { ok: true; value: string } | { ok: false; err: Error }): void => {
        if (settled) return;
        settled = true;
        try { ws.close(); } catch { /* swallow */ }
        if (outcome.ok) resolve(outcome.value);
        else reject(outcome.err);
      };

      const timeoutMs = this.opts.timeoutMsPerCall ?? DEFAULT_TIMEOUT_MS;
      const timeout = setTimeout(() => {
        finish({
          ok: false,
          err: new Error(`WssEncodeDispatcher: entity.encode timed out after ${timeoutMs}ms`),
        });
      }, timeoutMs);
      if (typeof (timeout as { unref?: () => void }).unref === 'function') {
        (timeout as { unref: () => void }).unref();
      }

      ws.onopen = () => {
        try {
          ws.send(request);
        } catch (err) {
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: WS send failed: ${describe(err)}`),
          });
        }
      };

      ws.onmessage = (event: MessageEvent) => {
        let frame: unknown;
        try {
          frame =
            typeof event.data === 'string'
              ? JSON.parse(event.data)
              : JSON.parse(new TextDecoder().decode(event.data as ArrayBuffer));
        } catch (err) {
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: brain returned non-JSON: ${describe(err)}`),
          });
          return;
        }
        if (typeof frame !== 'object' || frame === null) {
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new Error('WssEncodeDispatcher: brain returned non-object frame'),
          });
          return;
        }
        const f = frame as Record<string, unknown>;
        if (f.id !== id) {
          // Some brains emit notifications (no id) before the response —
          // skip them. The brain in this protocol only sends ONE
          // response per request id, so anything mismatched IS a
          // skippable notification.
          if (f.id === undefined || f.id === null) return;
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: id mismatch (expected ${id}, got ${String(f.id)})`),
          });
          return;
        }
        clearTimeout(timeout);
        if (f.error !== undefined && f.error !== null) {
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: brain error: ${JSON.stringify(f.error)}`),
          });
          return;
        }
        const result = f.result;
        if (typeof result !== 'object' || result === null) {
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: missing result in response`),
          });
          return;
        }
        const cellId = (result as Record<string, unknown>).cell_id;
        if (typeof cellId !== 'string' || cellId.length !== 64) {
          finish({
            ok: false,
            err: new Error(`WssEncodeDispatcher: missing or malformed cell_id`),
          });
          return;
        }
        finish({ ok: true, value: cellId });
      };

      ws.onerror = (event: Event) => {
        clearTimeout(timeout);
        finish({
          ok: false,
          err: new Error(`WssEncodeDispatcher: ws error: ${describe(event)}`),
        });
      };

      ws.onclose = (event: CloseEvent) => {
        if (settled) return;
        clearTimeout(timeout);
        finish({
          ok: false,
          err: new Error(
            `WssEncodeDispatcher: ws closed before response (code=${event.code} reason="${event.reason}")`,
          ),
        });
      };
    });
  }
}

function describe(x: unknown): string {
  if (x instanceof Error) return x.message;
  if (typeof x === 'string') return x;
  try { return JSON.stringify(x); } catch { return String(x); }
}

```
