---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/brain-access-grant-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.056967+00:00
---

# runtime/session-protocol/src/swarm/brain-access-grant-verifier.ts

```ts
/**
 * BrainAccessGrantVerifier — the LIVE 2-PDA implementation of the
 * `AccessGrantVerifier` port (RTC matrix A4 axis A, real enforcement).
 *
 * #987 built the serve gate against an injected verifier port; the unit tests
 * use a stand-in for the 2-PDA. This is the real thing: it submits the grant +
 * the grantee's signed `verify.intent` to a running brain over the WSS RPC
 * `cells.mint` surface, where the engine-checked verify `.handler`
 * (cartridges/swarm/brain/access_grant_handler.zig) runs on the actual cell
 * engine. Enforcement lives in the engine, exactly as DAM requires — this class
 * is only the transport.
 *
 * THE VERDICT IS THE MINT OUTCOME. Minting an `access.grant.verify.intent`
 * auto-runs the 2-PDA pipeline (the DAM-1 ScriptContextBuilder loads the grant,
 * checks DATA_ACCESS + expiry, computes the challenge digest; the DAM-2 handler
 * runs `host_verify_partial_sig` and traps on a bad/absent signature). So:
 *   - valid grant + signature   → mint succeeds            → { ok: true }
 *   - bad sig / expired / wrong-cap / missing grant → handler traps → the mint
 *     is REJECTED (RPC error `handler_rejected` / `verify_failed`) → { ok: false }
 * The emitted `access.grant.verify.result` cell is persisted but NOT returned by
 * mint, so the verdict comes from mint success/failure (the result's contentHash
 * echo would need a follow-up cell.query; the serve policy already binds content
 * itself, so we don't need it here).
 *
 * THE GRANT HANDLE IS THE BRAIN'S cellId. The brain content-addresses a minted
 * cell over its own re-encoded header with a mint-time component, so the cellId
 * is (a) NOT equal to the TS `accessGrantCellHash`, and (b) assigned at mint.
 * The grantor therefore mints the grant ONCE (`mintGrant` → cellId), and that
 * cellId is the durable handle the grantee signs the challenge over and the
 * `verify.intent` references. `verify()` mints ONLY the intent — the grant is
 * already persisted (the seeder/grantor put it there). This matches the real
 * flow: the seeder runs the gate on its own brain, where it minted the grant.
 *
 * Wire: `cells.mint({ typeHashHex, payloadBytesHex })` — payload BYTES (not the
 * 1024-byte cell); the brain re-encodes the header. We round-trip the cell
 * through the access-grant codec to recover the exact payload bytes.
 *
 * Cross-reference: access-grant-serve.ts (the port + serve policy),
 * core/protocol-types/src/bsv/access-grant.ts (the codecs),
 * runtime/semantos-brain/src/cells_mint_handler.zig (the mint RPC),
 * cartridges/swarm/brain/registration.zig (DAM-4 registration).
 */

import { HEADER_SIZE, toHex, fromHex } from '@semantos/protocol-types';
import {
  ACCESS_GRANT_TYPE_HASH,
  VERIFY_INTENT_TYPE_HASH,
  decodeAccessGrantPayload,
  encodeAccessGrantPayload,
  decodeVerifyIntentPayload,
  encodeVerifyIntentPayload,
} from '@semantos/protocol-types/bsv/access-grant';
import type { RpcChannel } from './rpc-brain-client';
import type { AccessGrantVerifier, AccessGrantVerification } from './access-grant-serve';

export interface BrainAccessGrantVerifierOptions {
  /** A connected brain RPC channel (e.g. WssRpcChannel to /api/v1/rpc). */
  channel: RpcChannel;
  /** Mint verb (default 'cells.mint'). */
  mintMethod?: string;
}

export class BrainAccessGrantVerifier implements AccessGrantVerifier {
  private readonly channel: RpcChannel;
  private readonly mintMethod: string;

  constructor(opts: BrainAccessGrantVerifierOptions) {
    this.channel = opts.channel;
    this.mintMethod = opts.mintMethod ?? 'cells.mint';
  }

  /**
   * Grantor: persist a LINEAR `access.grant` cell and return the brain's cellId
   * — the durable grant handle. The grantee signs the access challenge over this
   * hash and the `verify.intent` references it. (No handler runs on a grant
   * mint; it is just stored.)
   */
  async mintGrant(grantCell: Uint8Array): Promise<Uint8Array> {
    const grantPayload = encodeAccessGrantPayload(decodeAccessGrantPayload(grantCell.slice(HEADER_SIZE)));
    const res = (await this.channel.call(this.mintMethod, {
      typeHashHex: toHex(ACCESS_GRANT_TYPE_HASH),
      payloadBytesHex: toHex(grantPayload),
    })) as { cellId: string };
    return fromHex(res.cellId);
  }

  /**
   * Seeder: run the engine-checked verify. Mints the grantee's signed
   * `verify.intent` (whose `grant_hash` must reference a grant already persisted
   * on this brain). Mint success = the 2-PDA accepted = { ok: true }; a handler
   * trap surfaces as an RPC error = { ok: false }.
   */
  async verify(args: { grantCell: Uint8Array; intentCell: Uint8Array }): Promise<AccessGrantVerification> {
    const intentPayload = encodeVerifyIntentPayload(decodeVerifyIntentPayload(args.intentCell.slice(HEADER_SIZE)));
    try {
      await this.channel.call(this.mintMethod, {
        typeHashHex: toHex(VERIFY_INTENT_TYPE_HASH),
        payloadBytesHex: toHex(intentPayload),
      });
      return { ok: true };
    } catch {
      return { ok: false };
    }
  }
}

```
