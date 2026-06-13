---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/brain-access-grant-verifier.integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.075833+00:00
---

# runtime/session-protocol/src/swarm/__tests__/brain-access-grant-verifier.integration.test.ts

```ts
/**
 * LIVE 2-PDA verification — BrainAccessGrantVerifier against a running brain.
 *
 * This is the end-to-end proof that the swarm serve gate's authorization is
 * really enforced by the cell engine (RTC matrix A4 axis A): a grantee signs the
 * access challenge with a real key, the brain runs the verify .handler on the
 * actual 2-PDA, and the verdict gates the serve.
 *
 * GATED ON `BRAIN_RPC_URL` — skipped (green) when no brain is available, so CI /
 * headless runs pass. To run it:
 *
 *   cd runtime/semantos-brain && zig build              # builds zig-out/bin/brain (full profile)
 *   # stage the swarm cartridge so registerInto registers the access.grant family
 *   # (gotcha #8 — table-registered, triggered by a manifest under <data_dir>/extensions/):
 *   mkdir -p ~/.semantos/data/extensions/swarm && cat > ~/.semantos/data/extensions/swarm/cartridge.json <<'J'
 *   { "id":"swarm","name":"Paid Swarm","version":"0.1.0","role":"substrate",
 *     "brain":{"handlers":[{"module":"registration"}]},"cellTypes":[] }
 *   J
 *   ./zig-out/bin/brain bearer issue --label dev        # capture the 64-hex token
 *   ./zig-out/bin/brain serve localhost --port 8080     # boot log: "access-grant DAM family registered"
 *   BRAIN_RPC_URL='ws://[::1]:8080/api/v1/rpc?bearer=<token>' \
 *     bun test src/swarm/__tests__/brain-access-grant-verifier.integration.test.ts
 *
 * No @bsv/sdk here — signing comes through the bsv-access-grant-signer adapter
 * (the @bsv/sdk choke point).
 */
import { describe, expect, test } from 'bun:test';
import { sha256 } from '@semantos/protocol-types';
import {
  encodeAccessGrantCell,
  buildVerifyIntentCell,
  type AccessGrant,
} from '@semantos/protocol-types/bsv/access-grant';
import { BrainRpcChannel } from '../brain-rpc-channel';
import { BrainAccessGrantVerifier } from '../brain-access-grant-verifier';
import { randomGranteeProver } from '../bsv-access-grant-signer';

const BRAIN_RPC_URL = process.env.BRAIN_RPC_URL;
const d = BRAIN_RPC_URL ? describe : describe.skip;

d('BrainAccessGrantVerifier — live 2-PDA', () => {
  const channel = new BrainRpcChannel(BRAIN_RPC_URL!, { timeoutMs: 15_000 });
  const verifier = new BrainAccessGrantVerifier({ channel });
  const contentHash = sha256(new TextEncoder().encode('a4/broadcast/content'));

  /** Grantor mints the grant; returns the cell + the brain's handle (cellId). */
  async function issue(granteePubkey: Uint8Array, expiry = 9_999_999_999n) {
    const grant: AccessGrant = { granteePubkey, contentHash, expiry };
    const cell = encodeAccessGrantCell(grant);
    const grantHash = await verifier.mintGrant(cell); // brain cellId = the handle
    return { cell, grantHash };
  }

  test('a valid grant + signature verifies on the real engine', async () => {
    const { prover, granteePubkey } = randomGranteeProver();
    const { cell, grantHash } = await issue(granteePubkey);
    const proof = await prover.proveAccess(grantHash); // sign over the brain handle
    const intentCell = buildVerifyIntentCell({ grantHash, signature: proof!.signature });

    const verdict = await verifier.verify({ grantCell: cell, intentCell });
    expect(verdict.ok).toBe(true);
  });

  test('a signature from the WRONG key is rejected by the engine', async () => {
    const { granteePubkey } = randomGranteeProver();           // grant issued to this key
    const wrong = randomGranteeProver();                        // a different key signs
    const { cell, grantHash } = await issue(granteePubkey);
    const badProof = await wrong.prover.proveAccess(grantHash);
    const intentCell = buildVerifyIntentCell({ grantHash, signature: badProof!.signature });

    const verdict = await verifier.verify({ grantCell: cell, intentCell });
    expect(verdict.ok).toBe(false);
  });

  test('an expired grant is rejected by the engine (builder expiry gate)', async () => {
    const { prover, granteePubkey } = randomGranteeProver();
    const { cell, grantHash } = await issue(granteePubkey, 1n); // expiry in 1970
    const proof = await prover.proveAccess(grantHash);
    const intentCell = buildVerifyIntentCell({ grantHash, signature: proof!.signature });

    const verdict = await verifier.verify({ grantCell: cell, intentCell });
    expect(verdict.ok).toBe(false);
  });
});

```
