---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/rpc-brain-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.053019+00:00
---

# runtime/session-protocol/src/swarm/rpc-brain-client.ts

```ts
/**
 * RpcSwarmBrainClient — the real SwarmBrainClient over the unified
 * /api/v1/rpc WSS channel (M8). It maps the four cold-path verbs onto
 * `verb.dispatch({extensionId:"swarm", verb, params})` and parses the Zig
 * walker responses back into the engine's types.
 *
 * The concrete WebSocket transport is injected as an `RpcChannel` so the
 * mapping logic is testable in isolation (and so a bearer-auth WSS channel,
 * an HTTP fallback, or an in-process brain bridge can all back it). The actual
 * socket wiring is a thin adapter the host supplies; an end-to-end run against
 * a booted brain is environment-dependent and not exercised by unit tests.
 *
 * Param/response contract (must match cartridges/swarm/brain/swarm_walkers.zig):
 *   publish  {infohash, manifestCellHex, semanticPath} → {infohash, stored, anchorStatus}
 *   locate   {infohash}            → {manifestKnown, manifestCellHex?, anchorStatus?, seeders[]}
 *   announce {infohash, address, bitfieldHex} → {ok}
 *   settle   {infohash, receipts[]} → {recorded}
 */

import { toHex, fromHex } from '@semantos/protocol-types';
import type { SwarmBrainClient, LocateResult, SwarmReceipt, SeederInfo } from './brain-client';

/** A minimal brain RPC transport: invoke a method, get the parsed `result`. */
export interface RpcChannel {
  call(method: string, params: unknown): Promise<any>;
}

export class RpcSwarmBrainClient implements SwarmBrainClient {
  private readonly extensionId: string;

  /**
   * @param channel  the brain RPC transport
   * @param extensionId  brain verb namespace. Defaults to "swarm" (legacy,
   *   back-compat); pass "transfer" for the canonical data-plane primitive.
   *   The brain registers BOTH over one shared tracker.
   */
  constructor(private readonly channel: RpcChannel, extensionId: string = 'swarm') {
    this.extensionId = extensionId;
  }

  private dispatch(verb: string, params: unknown): Promise<any> {
    return this.channel.call('verb.dispatch', { extensionId: this.extensionId, verb, params });
  }

  async publish(args: { infohash: Uint8Array; manifestCell: Uint8Array; semanticPath: string }): Promise<{ infohash: string }> {
    const r = await this.dispatch('publish', {
      infohash: toHex(args.infohash),
      manifestCellHex: toHex(args.manifestCell),
      semanticPath: args.semanticPath,
    });
    return { infohash: r?.infohash ?? toHex(args.infohash) };
  }

  async locate(infohash: Uint8Array): Promise<LocateResult> {
    const r = await this.dispatch('locate', { infohash: toHex(infohash) });
    if (!r?.manifestKnown) return { manifestCell: null, seeders: [] };
    const seeders: SeederInfo[] = (r.seeders ?? []).map((s: any) => ({
      address: s.address,
      bitfield: typeof s.bitfield === 'string' && s.bitfield.length > 0 ? fromHex(s.bitfield) : undefined,
      lastSeen: s.lastSeen,
    }));
    // The brain confirms the manifest cell (which hashes to this infohash) is
    // anchored; the trustless binding is stateHash === infohash.
    const anchorProof = r.anchorStatus === 'confirmed' ? { stateHash: toHex(infohash) } : undefined;
    return { manifestCell: fromHex(r.manifestCellHex), seeders, anchorProof };
  }

  async announce(args: { infohash: Uint8Array; address?: string; bca?: Uint8Array; bitfield: Uint8Array }): Promise<void> {
    await this.dispatch('announce', {
      infohash: toHex(args.infohash),
      address: args.address ?? (args.bca ? toHex(args.bca) : ''),
      bitfieldHex: toHex(args.bitfield),
    });
  }

  async settle(args: { infohash: Uint8Array; receipts: SwarmReceipt[] }): Promise<{ recorded: number }> {
    const r = await this.dispatch('settle', { infohash: toHex(args.infohash), receipts: args.receipts });
    return { recorded: r?.recorded ?? 0 };
  }
}

```
