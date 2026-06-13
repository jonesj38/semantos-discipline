---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/tmux/bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.379004+00:00
---

# runtime/shell/src/tmux/bridge.ts

```ts
/**
 * StoreBridge — IPC layer for sharing LoomStore state across tmux panes.
 *
 * The server (started by the REPL pane) serializes store change events over a
 * Unix domain socket. Client panes connect and receive state snapshots plus
 * selection sync messages.
 *
 * Protocol: newline-delimited JSON messages.
 * Message types:
 *   { type: 'state',  data: SerializedLoomState }
 *   { type: 'select', objectId: string | null }
 *   { type: 'event',  category: string, description: string, timestamp: number }
 */

import { createServer, createConnection, type Server, type Socket } from 'net';
import { unlinkSync, existsSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { TypedEventEmitter } from '@semantos/runtime-services';
import type { LoomStore } from '@semantos/runtime-services';
import type { LoomState, LoomObject, ObjectPatch } from '@semantos/runtime-services';

// ── Serialization helpers ────────────────────────────────────

/** Serialize LoomState for IPC (Maps → arrays, Uint8Array → hex). */
export function serializeState(state: LoomState): unknown {
  const objects: Record<string, unknown> = {};
  for (const [id, obj] of state.objects) {
    objects[id] = serializeObject(obj);
  }
  return {
    objects,
    selectedObjectId: state.selectedObjectId,
    selectedCardId: state.selectedCardId,
    categoryFilter: state.categoryFilter,
  };
}

function serializeObject(obj: LoomObject): unknown {
  return {
    id: obj.id,
    typeDefinition: obj.typeDefinition,
    header: {
      linearity: obj.header.linearity,
      version: obj.header.version,
      flags: obj.header.flags,
      refCount: obj.header.refCount,
      // RM-032b: commerce taxonomy (phase, dimension) moved to the
      // cell payload under commerceSchemaV1; the IPC payload no
      // longer surfaces them. Chain semantics (parentHash,
      // prevStateHash) remain on CellHeader and ship here unchanged.
      cellCount: obj.header.cellCount,
      totalSize: obj.header.totalSize,
      typeHash: uint8ToHex(obj.header.typeHash),
      ownerId: uint8ToHex(obj.header.ownerId),
      timestamp: obj.header.timestamp.toString(),
      magic: uint8ToHex(obj.header.magic),
      parentHash: uint8ToHex(obj.header.parentHash),
      prevStateHash: uint8ToHex(obj.header.prevStateHash),
      domainPayloadRoot: uint8ToHex(obj.header.domainPayloadRoot),
    },
    payload: obj.payload,
    patches: obj.patches,
    visibility: obj.visibility,
    typeCoordinate: obj.typeCoordinate,
    createdAt: obj.createdAt,
    updatedAt: obj.updatedAt,
  };
}

function uint8ToHex(arr: Uint8Array): string {
  return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
}

/** Deserialize IPC state back into LoomState-like structure. */
export function deserializeState(data: unknown): DeserializedState {
  const raw = data as {
    objects: Record<string, unknown>;
    selectedObjectId: string | null;
    selectedCardId: string | null;
    categoryFilter: string | null;
  };
  const objects = new Map<string, LoomObject>();
  for (const [id, objData] of Object.entries(raw.objects)) {
    objects.set(id, deserializeObject(objData));
  }
  return {
    objects,
    cards: new Map(),
    selectedObjectId: raw.selectedObjectId,
    selectedCardId: raw.selectedCardId,
    categoryFilter: raw.categoryFilter,
  };
}

function deserializeObject(data: unknown): LoomObject {
  const raw = data as Record<string, unknown>;
  const headerRaw = raw.header as Record<string, unknown>;
  return {
    id: raw.id as string,
    typeDefinition: raw.typeDefinition as LoomObject['typeDefinition'],
    header: {
      linearity: headerRaw.linearity as number,
      version: headerRaw.version as number,
      flags: headerRaw.flags as number,
      refCount: headerRaw.refCount as number,
      phase: headerRaw.phase as number,
      dimension: headerRaw.dimension as number,
      cellCount: headerRaw.cellCount as number,
      totalSize: headerRaw.totalSize as number,
      typeHash: hexToUint8(headerRaw.typeHash as string),
      ownerId: hexToUint8(headerRaw.ownerId as string),
      timestamp: BigInt(headerRaw.timestamp as string),
      magic: hexToUint8(headerRaw.magic as string),
      parentHash: hexToUint8(headerRaw.parentHash as string),
      prevStateHash: hexToUint8(headerRaw.prevStateHash as string),
    },
    payload: raw.payload as Record<string, unknown>,
    patches: raw.patches as ObjectPatch[],
    visibility: raw.visibility as LoomObject['visibility'],
    typeCoordinate: raw.typeCoordinate as LoomObject['typeCoordinate'],
    createdAt: raw.createdAt as number,
    updatedAt: raw.updatedAt as number,
  };
}

function hexToUint8(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}

export type DeserializedState = LoomState;

// ── Bridge message types ─────────────────────────────────────

export interface BridgeMessageState {
  type: 'state';
  data: unknown;
}

export interface BridgeMessageSelect {
  type: 'select';
  objectId: string | null;
}

export interface BridgeMessageEvent {
  type: 'event';
  category: string;
  description: string;
  timestamp: number;
}

/** Phase 2: Message delivery between conversation panes. */
export interface BridgeMessageDeliver {
  type: 'message';
  conversationId: string;
  messageId: string;
  senderId: string;
  preview: string;
  contextType: string;
  timestamp: number;
}

export type BridgeMessage = BridgeMessageState | BridgeMessageSelect | BridgeMessageEvent | BridgeMessageDeliver;

// ── Server ───────────────────────────────────────────────────

export class StoreBridgeServer {
  private server: Server | null = null;
  private clients = new Set<Socket>();
  private unsubscribe: (() => void) | null = null;
  private prevState: LoomState | null = null;

  constructor(
    private store: LoomStore,
    private socketPath: string,
  ) {}

  /** Start listening and broadcasting store changes. */
  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      // Clean up stale socket
      if (existsSync(this.socketPath)) {
        try { unlinkSync(this.socketPath); } catch { /* ignore */ }
      }

      this.server = createServer((socket: Socket) => {
        this.clients.add(socket);

        // Send current state immediately on connect
        const stateMsg: BridgeMessageState = {
          type: 'state',
          data: serializeState(this.store.getState()),
        };
        this.sendToSocket(socket, stateMsg);

        socket.on('data', (buf: Buffer) => {
          // Handle messages from panes (e.g., select)
          const lines = buf.toString().split('\n').filter(Boolean);
          for (const line of lines) {
            try {
              const msg = JSON.parse(line) as BridgeMessage;
              if (msg.type === 'select') {
                // Forward select to all other clients
                this.store.dispatch({ type: 'SELECT_OBJECT', id: (msg as BridgeMessageSelect).objectId });
              }
            } catch { /* ignore malformed */ }
          }
        });

        socket.on('close', () => this.clients.delete(socket));
        socket.on('error', () => this.clients.delete(socket));
      });

      this.server.on('error', reject);
      this.server.listen(this.socketPath, () => {
        // Subscribe to store changes
        this.prevState = this.store.getState();
        this.unsubscribe = this.store.on('change', (state: LoomState) => {
          this.detectAndBroadcastEvents(state);
          const msg: BridgeMessageState = { type: 'state', data: serializeState(state) };
          this.broadcast(msg);
          this.prevState = state;
        });
        resolve();
      });
    });
  }

  /** Broadcast an event message to all connected panes. */
  broadcastEvent(category: string, description: string): void {
    const msg: BridgeMessageEvent = {
      type: 'event',
      category,
      description,
      timestamp: Date.now(),
    };
    this.broadcast(msg);
  }

  /** Detect state changes and emit corresponding events. */
  private detectAndBroadcastEvents(newState: LoomState): void {
    if (!this.prevState) return;

    // Detect new objects
    for (const [id, obj] of newState.objects) {
      if (!this.prevState.objects.has(id)) {
        const typeName = obj.typeDefinition.name;
        const lin = linearityName(obj.header.linearity);
        this.broadcastEvent('create', `${id} type=${typeName} linearity=${lin}`);
      }
    }

    // Detect patches and transitions on existing objects
    for (const [id, obj] of newState.objects) {
      const prev = this.prevState.objects.get(id);
      if (!prev) continue;

      // New patches
      if (obj.patches.length > prev.patches.length) {
        for (let i = prev.patches.length; i < obj.patches.length; i++) {
          const p = obj.patches[i];
          if (p.kind === 'state_transition') {
            this.broadcastEvent('transition', `${id} ${describeTransitionPatch(p)}`);
          } else {
            this.broadcastEvent('patch', `${id} kind=${p.kind} by=${p.hatId ?? 'system'}`);
          }
        }
      }

      // Visibility change
      if (obj.visibility !== prev.visibility) {
        this.broadcastEvent('transition', `${id} visibility: ${prev.visibility}\u2192${obj.visibility}`);
      }
    }

    // Selection change
    if (newState.selectedObjectId !== this.prevState.selectedObjectId) {
      const selMsg: BridgeMessageSelect = {
        type: 'select',
        objectId: newState.selectedObjectId,
      };
      this.broadcast(selMsg);
    }
  }

  /** Stop the bridge server. */
  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
    for (const client of this.clients) {
      client.destroy();
    }
    this.clients.clear();
    this.server?.close();
    this.server = null;
    try { unlinkSync(this.socketPath); } catch { /* ignore */ }
  }

  private broadcast(msg: BridgeMessage): void {
    const payload = JSON.stringify(msg) + '\n';
    for (const client of this.clients) {
      try { client.write(payload); } catch { /* client gone */ }
    }
  }

  private sendToSocket(socket: Socket, msg: BridgeMessage): void {
    try { socket.write(JSON.stringify(msg) + '\n'); } catch { /* ignore */ }
  }
}

// ── Client ───────────────────────────────────────────────────

type ClientEvents = {
  state: [DeserializedState];
  select: [string | null];
  event: [BridgeMessageEvent];
  message: [BridgeMessageDeliver];
};

export class StoreBridgeClient extends TypedEventEmitter<ClientEvents> {
  private socket: Socket | null = null;
  private buffer = '';
  private currentState: DeserializedState | null = null;

  constructor(private socketPath: string) {
    super();
  }

  /** Connect to the bridge server. */
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.socket = createConnection(this.socketPath, () => resolve());
      this.socket.on('error', reject);
      this.socket.on('data', (buf: Buffer) => {
        this.buffer += buf.toString();
        const lines = this.buffer.split('\n');
        this.buffer = lines.pop() ?? '';
        for (const line of lines) {
          if (!line) continue;
          try {
            const msg = JSON.parse(line) as BridgeMessage;
            this.handleMessage(msg);
          } catch { /* ignore malformed */ }
        }
      });
      this.socket.on('close', () => { this.socket = null; });
    });
  }

  /** Get the last received state. */
  getState(): DeserializedState | null {
    return this.currentState;
  }

  /** Send a select message to the bridge. */
  sendSelect(objectId: string | null): void {
    const msg: BridgeMessageSelect = { type: 'select', objectId };
    this.socket?.write(JSON.stringify(msg) + '\n');
  }

  /** Disconnect from the bridge. */
  disconnect(): void {
    this.socket?.destroy();
    this.socket = null;
  }

  private handleMessage(msg: BridgeMessage): void {
    switch (msg.type) {
      case 'state': {
        this.currentState = deserializeState((msg as BridgeMessageState).data);
        this.emit('state', this.currentState);
        break;
      }
      case 'select': {
        this.emit('select', (msg as BridgeMessageSelect).objectId);
        break;
      }
      case 'event': {
        this.emit('event', msg as BridgeMessageEvent);
        break;
      }
      case 'message': {
        this.emit('message', msg as BridgeMessageDeliver);
        break;
      }
    }
  }
}

// ── Utility ──────────────────────────────────────────────────

/** Generate a default socket path for a session. */
export function defaultSocketPath(sessionName: string): string {
  return join(tmpdir(), `semantos-${sessionName}-${process.pid}.sock`);
}

function linearityName(n: number): string {
  switch (n) {
    case 1: return 'LINEAR';
    case 2: return 'AFFINE';
    case 3: return 'RELEVANT';
    case 4: return 'DEBUG';
    default: return `UNKNOWN(${n})`;
  }
}

function describeTransitionPatch(p: ObjectPatch): string {
  const d = p.delta;
  if (d.action === 'reclassification') return `reclassified by dispute ${d.disputeObjectId}`;
  return `${p.kind} by=${p.hatId ?? 'system'}`;
}

```
