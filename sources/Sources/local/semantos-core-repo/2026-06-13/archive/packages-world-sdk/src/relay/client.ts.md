---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/src/relay/client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.704220+00:00
---

# archive/packages-world-sdk/src/relay/client.ts

```ts
/**
 * RelayClient — WebSocket client for the cell-relay (CellRelay.WSHandler).
 *
 * Connects to a single room on a cell-relay node, handles snapshot/commit/
 * presence/live/reset messages, and exposes broadcast/sendLive/resetAll.
 *
 * Extracted and generalised from apps/world-apps/jam-room/src/core/sync.ts
 * (was JamSync — JamSync is exported as a backward-compat alias below).
 */

import type { SerializedCell, LivePayload, RelayServerMsg, RelayCallbacks } from "./types.js";
import { CellState } from "../dag/index.js";

export type { SerializedCell, LivePayload, RelayCallbacks };
export type { RelayServerMsg };

export class RelayClient {
  private ws: WebSocket | null = null;

  constructor(
    private readonly url: string,
    private readonly cb: RelayCallbacks,
  ) {}

  connect(): void {
    this.cb.onStatus("connecting");
    try {
      this.ws = new WebSocket(this.url);
    } catch {
      this.cb.onStatus("error");
      return;
    }
    this.ws.onopen = () => this.cb.onStatus("open");
    this.ws.onmessage = (ev) => {
      let m: RelayServerMsg;
      try {
        m = JSON.parse(ev.data as string) as RelayServerMsg;
      } catch {
        return;
      }
      if (m.type === "snapshot")
        this.cb.onSnapshot(m.cells, m.your, m.presence ?? []);
      else if (m.type === "commit") this.cb.onCell(m.cell, m.from);
      else if (m.type === "presence")
        this.cb.onPresence(m.identities, { joined: m.joined, left: m.left });
      else if (m.type === "live") this.cb.onLive(m.payload, m.from);
      else if (m.type === "reset") this.cb.onReset();
      else this.cb.onRawMessage?.(m as Record<string, unknown>);
    };
    this.ws.onclose = () => {
      this.cb.onStatus("closed");
      setTimeout(() => this.connect(), 2000);
    };
    this.ws.onerror = () => this.cb.onStatus("error");
  }

  broadcast(cell: SerializedCell): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: "commit", cell }));
    }
  }

  sendLive(payload: LivePayload): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: "live", payload }));
    }
  }

  resetAll(): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: "reset" }));
    }
  }

  sendRaw(msg: unknown): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  disconnect(): void {
    this.ws?.close();
    this.ws = null;
  }
}

// ── Serialisation helpers ──────────────────────────────────────────────────

export function bytesToHex(b: Uint8Array): string {
  let s = "";
  for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, "0");
  return s;
}

export function hexToBytes(h: string): Uint8Array {
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++)
    out[i] = parseInt(h.substr(i * 2, 2), 16);
  return out;
}

export function serializeCell(c: CellState): SerializedCell {
  return {
    id: c.id,
    stateHashHex: bytesToHex(c.stateHash),
    parentHashes: c.parents.map((p) => bytesToHex(p.stateHash)),
    patch: c.patch,
    hat: c.hat,
    depth: c.depth,
    branch: c.branch,
    cherryPickedFromHash: c.cherryPickedFrom
      ? bytesToHex(c.cherryPickedFrom.stateHash)
      : null,
    tampered: c.tampered,
  };
}

export function deserializeCell(
  s: SerializedCell,
  byHashHex: Map<string, CellState>,
): CellState | null {
  const parents: CellState[] = [];
  for (const ph of s.parentHashes) {
    const p = byHashHex.get(ph);
    if (!p) return null;
    parents.push(p);
  }
  let cherryPickedFrom: CellState | null = null;
  if (s.cherryPickedFromHash) {
    cherryPickedFrom = byHashHex.get(s.cherryPickedFromHash) ?? null;
    if (!cherryPickedFrom) return null;
  }
  return {
    id: s.id,
    stateHash: hexToBytes(s.stateHashHex),
    parents,
    patch: s.patch,
    hat: s.hat,
    depth: s.depth,
    branch: s.branch,
    cherryPickedFrom,
    tampered: s.tampered,
  };
}

/** @deprecated Renamed to RelayClient — remove this alias after migrating consumers. */
export const JamSync = RelayClient;
export type JamSync = RelayClient;

```
