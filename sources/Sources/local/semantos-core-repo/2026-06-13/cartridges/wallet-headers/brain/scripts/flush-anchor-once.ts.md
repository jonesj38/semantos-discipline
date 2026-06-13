---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/scripts/flush-anchor-once.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.643768+00:00
---

# cartridges/wallet-headers/brain/scripts/flush-anchor-once.ts

```ts
#!/usr/bin/env bun
// flush-anchor-once.ts — one-shot anchor demo.
//
// Given a (cell_hash, type_hash) pair, build the BRC-42 anchor lock
// script via the wallet-headers cartridge subscriber, hand it to
// Metanet Desktop's BRC-100 createAction on :3321 for signing +
// broadcast, print the txid.
//
// This is Option A from the §11.10 order 3a step 3 discussion (Todd
// 2026-05-26): "we can use metanet desktop, or we can also use our
// wallet-headers cartridge. Go look, but yeah do A".  Metanet Desktop
// won this round because (1) it's already funded + has an identity
// loaded, (2) cartridges/wallet-headers/brain/src/metanet-client.ts
// already wraps its /createAction endpoint with the exact (lockingScript,
// satoshis) shape this script needs.
//
// What this script PROVES (when it returns a txid):
//   • The anchor lock script our subscriber emits is valid BSV Script
//     (Metanet Desktop's createAction parses it without rejecting).
//   • Metanet Desktop signs + broadcasts to ARC successfully.
//   • A real BSV mainnet txid lands in mempool for the anchor UTXO.
//
// What this script EXPLICITLY DOES NOT PROVE:
//   • That the broker → subscriber bridge works (this script bypasses
//     the broker — operator types the cell_hash + type_hash by hand).
//     PR-3a-bridge-2c lands the persistent runner that closes that gap.
//   • That the anchor UTXO is later spendable (deriveCellAnchorSk
//     recovery path).  The anchor key is ephemeral by default; pass
//     ANCHOR_IDENTITY_SK_HEX to use a persistent one.
//   • That Metanet Desktop's identity matches the anchor identity.
//     They're deliberately separate: Metanet Desktop is the FUNDING
//     source (provides input UTXOs + signs the spend); the anchor
//     lock pays a fresh address derived from a SEPARATE anchor key.
//     A future PR-3a-bridge-2c can either persist the anchor SK
//     alongside the operator's hat (so it has a recovery path) or
//     extend the subscriber to accept a Metanet-derived pubkey
//     instead of a local SK.
//
// Usage:
//   bun cartridges/wallet-headers/brain/scripts/flush-anchor-once.ts \
//     <cell_hash_hex> <type_hash_hex> [--cartridge-id <id>] [--entity-tag <decimal>]
//
//   Environment variables:
//     METANET_URL                  base URL for Metanet Desktop (default http://localhost:3321)
//     HAT_SEED                     operator hat seed string.  identitySk =
//                                  SHA-256(HAT_SEED), matching Zig
//                                  `bkds.privFromSeed` (runtime/semantos-brain/
//                                  src/bkds.zig:289).  This makes the anchor
//                                  identity scoped to the hat in effect (Todd
//                                  2026-05-26: "the anchor identity key is
//                                  scoped to the hat in effect") — different
//                                  hats produce different anchor key families.
//                                  Default: a clearly-demo seed (see WARNING
//                                  printed at runtime).  Production runs MUST
//                                  set this to the operator's actual hat seed.
//     ANCHOR_IDENTITY_SK_HEX       (legacy, deprecated) 64-char hex override.
//                                  If set, takes precedence over HAT_SEED.  For
//                                  one-off bypass paths; production wiring
//                                  goes through HAT_SEED.
//
// Example:
//   bun cartridges/wallet-headers/brain/scripts/flush-anchor-once.ts \
//     000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f \
//     202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f \
//     --cartridge-id flush-demo --entity-tag 16

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import {
  handleCellCreated,
  type CellCreatedEvent,
  type IdentityProvider,
  type CreateActionAdapter,
} from '../src/anchor-subscriber';

const DEMO_HAT_SEED = 'flush-anchor-once.ts demo hat (NOT FOR PRODUCTION)';

// ─────────────────────────────────────────────────────────────────────
// CLI parsing
// ─────────────────────────────────────────────────────────────────────

interface ParsedArgs {
  cellHash: string;
  typeHash: string;
  cartridgeId: string;
  entityTag: number;
}

function parseArgs(argv: string[]): ParsedArgs {
  // Positional: cellHash, typeHash.  Flags: --cartridge-id, --entity-tag.
  let cellHash: string | null = null;
  let typeHash: string | null = null;
  let cartridgeId = 'flush-demo';
  let entityTag = 0x10;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--cartridge-id') {
      cartridgeId = argv[++i] ?? '';
    } else if (a === '--entity-tag') {
      entityTag = Number.parseInt(argv[++i] ?? '0', 10);
    } else if (a.startsWith('--')) {
      die(`unknown flag: ${a}`);
    } else if (!cellHash) {
      cellHash = a;
    } else if (!typeHash) {
      typeHash = a;
    } else {
      die(`unexpected positional arg: ${a}`);
    }
  }

  if (!cellHash || !typeHash) {
    die('usage: bun flush-anchor-once.ts <cell_hash_hex> <type_hash_hex> [--cartridge-id <id>] [--entity-tag <decimal>]');
  }
  if (cellHash.length !== 64) die(`cell_hash must be 64 hex chars (got ${cellHash.length})`);
  if (typeHash.length !== 64) die(`type_hash must be 64 hex chars (got ${typeHash.length})`);

  return { cellHash, typeHash, cartridgeId, entityTag };
}

function die(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(2);
}

// ─────────────────────────────────────────────────────────────────────
// Identity
// ─────────────────────────────────────────────────────────────────────

function loadAnchorIdentitySk(): Uint8Array {
  // Legacy override path — explicit raw hex.  Used by one-off paths
  // that already hold the operator's identitySk in bytes form; not
  // the default.
  const envHex = process.env.ANCHOR_IDENTITY_SK_HEX;
  if (envHex && envHex.length === 64) {
    const out = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      out[i] = Number.parseInt(envHex.slice(i * 2, i * 2 + 2), 16);
    }
    console.error(`[flush] using ANCHOR_IDENTITY_SK_HEX (raw hex override; production should use HAT_SEED)`);
    return out;
  }

  // Hat-scoped path (preferred, per Todd 2026-05-26).  identitySk =
  // SHA-256(HAT_SEED) — exact same convention as Zig
  // bkds.privFromSeed at runtime/semantos-brain/src/bkds.zig:289.
  // Different hats → different identitySks → different anchor key
  // families per cartridge / per operator.
  const seed = process.env.HAT_SEED;
  if (seed && seed.length > 0) {
    console.error(`[flush] deriving anchor identitySk from HAT_SEED via SHA-256 (hat-scoped, ${seed.length} char seed)`);
    return new Uint8Array(nobleSha256(new TextEncoder().encode(seed)));
  }

  // Fallback: demo seed.  WARN loudly because production callers
  // MUST set HAT_SEED to the operator's actual hat seed.
  console.error(`[flush] WARNING: no HAT_SEED set — using built-in demo seed`);
  console.error(`[flush] WARNING: production runs MUST set HAT_SEED to the operator's actual hat seed`);
  console.error(`[flush] WARNING: anchor UTXOs created with the demo seed are spendable BY ANYONE WHO RUNS THIS SCRIPT (the seed string is in source)`);
  return new Uint8Array(nobleSha256(new TextEncoder().encode(DEMO_HAT_SEED)));
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers (display order for the final txid printout)
// ─────────────────────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  const metanetUrl = process.env.METANET_URL ?? 'http://localhost:3321';

  console.error(`[flush] cell_hash:    ${args.cellHash}`);
  console.error(`[flush] type_hash:    ${args.typeHash}`);
  console.error(`[flush] cartridge_id: ${args.cartridgeId}`);
  console.error(`[flush] entity_tag:   ${args.entityTag}`);
  console.error(`[flush] metanet_url:  ${metanetUrl}`);

  // Refuse to broadcast for the anchor-attestation sentinel — same
  // recursion break the brain + the subscriber library both enforce.
  if (args.entityTag === 0x20) {
    console.error(`[flush] entity_tag=0x20 is the ANCHOR_ATTESTATION sentinel; broadcasting it would loop forever`);
    return 3;
  }

  const anchorSk = loadAnchorIdentitySk();

  const identity: IdentityProvider = {
    getIdentitySk: () => anchorSk,
    // Single-shot: anchorIndex always 0.  A persistent runner (PR-3a-
    // bridge-2c) maintains a per-typeHash counter so each cell's
    // anchor key is distinct.
    nextAnchorIndex: () => 0,
  };

  // Origin header is required by Metanet Desktop's CORS check (per
  // smoke 2026-05-26: missing-Origin gets "Origin header is required").
  // Browser fetch auto-fills it; bun does not.  Default = http://localhost
  // matches core/protocol-types/src/wallet-client/types.ts comment.
  const origin = process.env.METANET_ORIGIN ?? 'http://localhost';

  const createAction: CreateActionAdapter = async params => {
    // Metanet Desktop's /createAction takes lockingScript as hex string,
    // satoshis as number, and optional outputDescription / tags / labels.
    // The tags + labels fields MUST be present (not just undefined) so
    // MD's peer-notification builder doesn't throw on Array.from(null)
    // — see metanet-client.ts comment for the same defensive shape.
    const o = params.outputs[0]!;
    const scriptHex = bytesToHex(o.lockingScript);
    const body = {
      description: params.description,
      outputs: [
        {
          lockingScript: scriptHex,
          satoshis: o.satoshis,
          outputDescription: params.description,
          tags: [] as string[],
        },
      ],
      labels: [] as string[],
    };
    try {
      const resp = await fetch(`${metanetUrl}/createAction`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Origin: origin,
        },
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const text = await resp.text();
        return { ok: false, reason: `createAction ${resp.status}: ${text}` };
      }
      const j = (await resp.json()) as {
        txid?: string;
        beef?: string;
        rawTx?: string;
        signedTransaction?: string;
        tx?: number[];
      };
      // Prefer explicit txid; MD typically returns it in display order
      // (already reversed from internal byte order).
      if (typeof j.txid === 'string' && /^[0-9a-fA-F]{64}$/.test(j.txid)) {
        return { ok: true, txid: j.txid.toLowerCase() };
      }
      return {
        ok: false,
        reason: `createAction: response missing txid (keys: ${Object.keys(j).join(',')})`,
      };
    } catch (e: any) {
      return { ok: false, reason: `fetch failed: ${e?.message ?? String(e)}` };
    }
  };

  const event: CellCreatedEvent = {
    cell_hash: args.cellHash,
    type_hash: args.typeHash,
    entity_tag: args.entityTag,
    cartridge_id: args.cartridgeId,
    correlation_id: `flush-${Date.now()}`,
  };

  console.error(`[flush] calling subscriber.handleCellCreated...`);
  const outcome = await handleCellCreated(event, identity, createAction);

  console.error(`[flush] outcome: status=${outcome.status}`);
  if (outcome.error_kind) console.error(`[flush] error_kind: ${outcome.error_kind}`);
  if (outcome.detail) console.error(`[flush] detail:     ${outcome.detail}`);

  if (outcome.status === 'broadcast' && outcome.txid) {
    // Print ONLY the txid on stdout so callers can pipe + capture.
    console.log(outcome.txid);
    console.error(`[flush] ✓ broadcast: https://whatsonchain.com/tx/${outcome.txid}`);
    return 0;
  }
  if (outcome.status === 'skipped') {
    console.error(`[flush] skipped (recursion break)`);
    return 0;
  }
  return 1;
}

const code = await main();
process.exit(code);

```
