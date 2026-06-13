---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/headless-unified-wallet.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.433673+00:00
---

# cartridges/shared/wallet/headless-unified-wallet.test.ts

```ts
/**
 * headless-unified-wallet.test.ts — registers the headless adapter
 * and runs the canonical BRC-100 conformance suite against it.
 *
 * If this file's tests pass, the headless code path conforms to BRC-100
 * (per @bsv/sdk's WalletInterface, against ProtoWallet as reference).
 * Repeat for every adapter (Metanet Desktop client next).
 *
 * Per Q9 (2026-05-28), this supersedes the bespoke-conformance version
 * from C6a tick 2 (commit 5760f82).
 */

import { beforeAll, describe, it, expect } from 'bun:test';

import {
  _resetWalletRegistryForTests,
} from './unified-wallet';
import {
  registerHeadlessWallet,
  headlessWalletFactory,
} from './headless-unified-wallet';
import {
  runBrc100CryptoEquivalence,
  runBrc100InterfaceConformance,
  TEST_PRIVKEY,
} from './unified-wallet.conformance.test';

describe('headless-unified-wallet — registration + smoke', () => {
  beforeAll(() => {
    _resetWalletRegistryForTests();
    registerHeadlessWallet();
  });

  it('factory descriptor has id=headless and canTransact=false', () => {
    expect(headlessWalletFactory.id).toBe('headless');
    expect(headlessWalletFactory.canTransact).toBe(false);
  });

  it('build({privKey}) succeeds with valid 32-byte config', async () => {
    const w = await headlessWalletFactory.build({ privKey: TEST_PRIVKEY });
    expect(w).toBeDefined();
    expect(typeof w.getPublicKey).toBe('function');
    expect(typeof w.createSignature).toBe('function');
    expect(typeof w.createAction).toBe('function');
  });

  it('build({}) throws — privKey required', async () => {
    await expect(headlessWalletFactory.build({})).rejects.toThrow(/privKey/);
  });

  it('build with wrong-size privKey throws', async () => {
    await expect(
      headlessWalletFactory.build({ privKey: new Uint8Array(16) }),
    ).rejects.toThrow(/32 bytes/);
  });

  it('createAction throws NotImplementedYet (C6a tick 4 will wire it)', async () => {
    const w = await headlessWalletFactory.build({ privKey: TEST_PRIVKEY });
    await expect(
      w.createAction({
        description: 'test',
        outputs: [],
      }),
    ).rejects.toThrow(/createAction.*not yet implemented/);
  });
});

// ── Run BOTH BRC-100 conformance tiers ──────────────────────────────
// Headless adapter is ProtoWallet-backed, so it passes the strict
// crypto-equivalence suite AS WELL AS the shape-only interface suite.
// The wallet-headers adapter (lands in same PR) only runs the latter
// — it delegates to Metanet Desktop, whose key is operator-owned not
// the deterministic test key.
runBrc100CryptoEquivalence('headless', {
  buildConfig: {
    privKey: TEST_PRIVKEY,
  },
});

runBrc100InterfaceConformance('headless', {
  buildConfig: {
    privKey: TEST_PRIVKEY,
  },
});

```
