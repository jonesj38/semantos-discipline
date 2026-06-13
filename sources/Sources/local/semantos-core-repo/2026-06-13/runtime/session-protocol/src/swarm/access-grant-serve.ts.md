---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/access-grant-serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.050770+00:00
---

# runtime/session-protocol/src/swarm/access-grant-serve.ts

```ts
/**
 * access-grant serve gate — the engine-checked authorization leg of the swarm
 * (RTC matrix A4 axis A; the deferred "Transfer-serve integration" of the
 * Engine-Checked Data Access plan, cartridges/swarm/brain/DAM-HANDOFF.md §4).
 *
 * A seeder admits a leecher to a file by an engine-checked `access.grant`, NOT
 * by an app-layer cert check. The leecher attaches a `SwarmGrantProof` (the
 * grant's content-address + their signature over the canonical access-challenge
 * digest) to each request; the seeder runs the verify `.handler` on the real
 * 2-PDA and serves only on `ok`. This is the same apparatus RTC binds for A4
 * (broadcast/VOD subscription admission) and, with a SESSION_ACCESS sibling
 * capability, for S5 (group-call MLS membership).
 *
 * THE LOAD-BEARING INVARIANT: enforcement is in the cell engine (the 2-PDA),
 * never re-implemented here in TS. This module owns the *seam* — it builds the
 * `verify.intent`, calls an injected `AccessGrantVerifier` (whose real
 * implementation dispatches to the brain handler), and gates the serve on the
 * engine's verdict. Expiry, capability, and signature checks all live in the
 * engine (access_grant_context.zig builder + access_grant_handler.zig); the
 * gate only routes the right grant to the right file and trusts the verdict.
 *
 * Revocation is free: the grant is a LINEAR cell, so consuming/rotating it
 * makes the engine load fail → `ok=false` → serve refused. (The
 * `resolveGrant` resolver returning undefined models the same: the grant is
 * gone.)
 *
 * The live `BrainAccessGrantVerifier` (a real 2-PDA RPC round-trip) is a
 * follow-on slice — it needs the brain build. This module is the carrier-
 * agnostic structure, unit-tested against a faithful in-process verifier, the
 * way S1's signalling plane is tested against an in-memory channel.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml row A4, core/protocol-types/src/
 * bsv/access-grant.ts (the wire codecs + challenge digest), paid-seeder.ts (the
 * payment ServePolicy sibling).
 */

import {
  buildVerifyIntentCell,
  type AccessGrant,
} from '@semantos/protocol-types/bsv/access-grant';
import { bytesEqual } from '@semantos/protocol-types';
import type { ServePolicy, PayPolicy, RequestProof } from './swarm-session';
import type { SwarmRequest, SwarmGrantProof } from './swarm-wire';

// ── the 2-PDA verifier port ────────────────────────────────────────────
// The real implementation dispatches the verify.intent cell to the brain's
// access_grant_handler (the engine-checked 2-PDA) and decodes the emitted
// access.grant.verify.result. Kept as a port so the serve policy is unit-
// testable and so @bsv/sdk / brain-RPC stay out of this file.

export interface AccessGrantVerification {
  /** The engine's verdict: did the grantee's signed challenge verify? */
  ok: boolean;
  /** The content hash the engine bound the grant to (verify.result echo). */
  contentHash?: Uint8Array;
}

export interface AccessGrantVerifier {
  /**
   * Run the engine-checked verify on the real 2-PDA. `grantCell` is the LINEAR
   * `access.grant`; `intentCell` is the grantee's signed `verify.intent`.
   */
  verify(args: { grantCell: Uint8Array; intentCell: Uint8Array }): Promise<AccessGrantVerification>;
}

// ── seeder-side: the grant store + the serve policy ────────────────────

/** A grant the seeder issued: the LINEAR cell + its decoded fields. */
export interface GrantRecord {
  /** The 1024-byte `access.grant` cell. */
  cell: Uint8Array;
  /** The decoded grant (granteePubkey / contentHash / expiry). */
  grant: AccessGrant;
}

/** Resolve a grant the seeder issued, by its content-address. Undefined =
 *  unknown or revoked (the LINEAR cell was consumed/rotated). */
export type GrantResolver = (grantHash: Uint8Array) => GrantRecord | undefined | Promise<GrantRecord | undefined>;

export interface AccessGrantServePolicyOptions {
  /** The 2-PDA verifier (real impl dispatches to the brain handler). */
  verifier: AccessGrantVerifier;
  /** Resolve the seeder's issued grant by hash (revoked → undefined). */
  resolveGrant: GrantResolver;
  /** The content this seeder is gating — the grant must bind to it. */
  contentHash: Uint8Array;
}

/**
 * Seeder serve gate: require a `SwarmGrantProof` whose grant (a) is still live,
 * (b) binds to the content being served, and (c) passes the engine-checked
 * verify on the 2-PDA. Mirrors `PaidSeeder` (authorization, not payment) and
 * composes with it via {@link andServePolicies}.
 */
export class AccessGrantServePolicy implements ServePolicy {
  private readonly verifier: AccessGrantVerifier;
  private readonly resolveGrant: GrantResolver;
  private readonly contentHash: Uint8Array;

  constructor(opts: AccessGrantServePolicyOptions) {
    this.verifier = opts.verifier;
    this.resolveGrant = opts.resolveGrant;
    this.contentHash = opts.contentHash;
  }

  async authorizeServe(req: SwarmRequest): Promise<boolean> {
    const proof = req.grant;
    if (!proof) return false; // no authorization proof → refuse (fail-closed)

    const record = await this.resolveGrant(proof.grantHash);
    if (!record) return false; // unknown or revoked grant

    // Route check: this grant must be for the file we are serving. Not a
    // security check (the engine binds scope via the challenge digest) — it
    // picks the right grant and rejects a grant minted for another file.
    if (!bytesEqual(record.grant.contentHash, this.contentHash)) return false;

    const intentCell = buildVerifyIntentCell({ grantHash: proof.grantHash, signature: proof.signature });
    const verdict = await this.verifier.verify({ grantCell: record.cell, intentCell });
    if (!verdict.ok) return false;

    // If the engine echoed a content hash, it must match what we're serving.
    if (verdict.contentHash && !bytesEqual(verdict.contentHash, this.contentHash)) return false;
    return true;
  }
}

// ── leecher-side: the prover + a pay-policy adapter ────────────────────

/** Signs the access challenge for a held grant. The real impl lives with the
 *  wallet/edge keys (cartridges/wallet-headers); the swarm only consumes it. */
export interface AccessGrantProver {
  /** Sign the challenge for `grantHash`; null if no grant is held for it. */
  proveAccess(grantHash: Uint8Array): Promise<SwarmGrantProof | null>;
}

/**
 * Wrap a prover into a `PayPolicy` that attaches the grant proof to every
 * request (the authorization leg). Compose with a payment `PayPolicy` via
 * {@link andPayPolicies} when a file is both gated and metered.
 */
export function makeGrantPayPolicy(prover: AccessGrantProver, grantHash: Uint8Array): PayPolicy {
  return {
    async payFor(): Promise<RequestProof | null> {
      const grant = await prover.proveAccess(grantHash);
      return grant ? { grant } : null;
    },
  };
}

// ── policy combinators (SwarmSession has one slot each) ────────────────

/** AND several serve gates: serve only if ALL authorize. Receipts concatenate. */
export function andServePolicies(...policies: ServePolicy[]): ServePolicy {
  return {
    async authorizeServe(req: SwarmRequest): Promise<boolean> {
      for (const p of policies) {
        if (!(await p.authorizeServe(req))) return false;
      }
      return true;
    },
    drainReceipts() {
      return policies.flatMap((p) => p.drainReceipts?.() ?? []);
    },
  };
}

/** Merge several pay policies' proofs onto one request (e.g. grant + payment). */
export function andPayPolicies(...policies: PayPolicy[]): PayPolicy {
  return {
    async payFor(infohash, cellIndex, seederAddress): Promise<RequestProof | null> {
      let merged: RequestProof = {};
      let any = false;
      for (const p of policies) {
        const r = await p.payFor(infohash, cellIndex, seederAddress);
        if (r) {
          merged = { ...merged, ...r };
          any = true;
        }
      }
      return any ? merged : null;
    },
  };
}

```
