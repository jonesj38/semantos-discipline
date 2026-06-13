---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.432691+00:00
---

# shared/wallet — BRC-100 wallet surface

**Track**: C6a (BRC-100 Wallet Adoption). Tick 3 (Q9 reshape) landed 2026-05-28.

## What's here

| File | Purpose |
|------|---------|
| `unified-wallet.ts` | Re-exports `@bsv/sdk` BRC-100 types (`WalletInterface`, `ProtoWallet`, `KeyDeriver`) + factory registry. |
| `headless-unified-wallet.ts` | Headless adapter — wraps `ProtoWallet` for crypto; stubs tx methods until C6a tick 4 wires existing headless-wallet.ts. |
| `unified-wallet.conformance.test.ts` | BRC-100 conformance suite. Asserts adapter behavior matches `ProtoWallet` reference for the crypto subset. |
| `headless-unified-wallet.test.ts` | Registers headless factory + runs `runBrc100Conformance('headless')`. |
| `README.md` | This file. |

## The Q9 course correction (2026-05-28)

Tick 1 (commit 975c760) shipped a bespoke `UnifiedWallet` interface with invented names (`signCellHash`, `pubkeyForHat`, `hatId`). Tick 2 (commit 5760f82) landed a headless adapter against it. Both are **superseded by tick 3** per Q9 decision: the canonical wallet contract is `@bsv/sdk`'s `WalletInterface` (full BRC-100 per https://bsv.brc.dev/wallet/0100).

The reshape is a net simplification — `ProtoWallet` from @bsv/sdk replaces ~140 lines of bespoke crypto with one delegate, gives us the entire BRC-100 surface for free, and inherits ecosystem interop.

## Crypto vs transaction split

The headless adapter currently implements:

| BRC-100 method | Status |
|----------------|--------|
| `getPublicKey` | ✅ via ProtoWallet |
| `createSignature` / `verifySignature` | ✅ via ProtoWallet |
| `encrypt` / `decrypt` | ✅ via ProtoWallet |
| `createHmac` / `verifyHmac` | ✅ via ProtoWallet |
| `revealCounterpartyKeyLinkage` / `revealSpecificKeyLinkage` | ✅ via ProtoWallet |
| `getNetwork`, `getVersion`, `isAuthenticated`, `waitForAuthentication` | ✅ minimal stubs |
| `createAction` / `signAction` / `abortAction` / `listActions` | ⚠ throws `NotImplementedYet` — tick 4 wraps existing headless-wallet.ts sendPushdrop |
| `listOutputs` / `relinquishOutput` / `internalizeAction` | ⚠ throws `NotImplementedYet` |
| `getHeight` / `getHeaderForHeight` | ⚠ throws `NotImplementedYet` |
| Certificate methods (acquire/list/prove/relinquish/discover) | ⚠ throws — out of scope for C6a; C6b plexus-recovery work |

The crypto subset is what the C7 V1 golden slice needs (layer 6: sign a cell-hash with operator's hat key). The transaction subset wires in for V2 slice (anchored cell).

## The "pay bridget 10000 sats" path — already first-class

```ts
import { getWalletFactory } from './unified-wallet';

const wallet = await getWalletFactory('headless')!.build({ privKey });

// Resolve Bridget's payment destination via BRC-42 counterparty derivation
const { publicKey: bridgetPaymentPubkey } = await wallet.getPublicKey({
  protocolID: [2, 'payment'],         // BRC-43 security level + protocol
  keyID: '1',
  counterparty: bridget.identityKeyHex,
});

// Construct + sign + broadcast the payment tx (once tick 4 wires createAction)
const { tx, txid } = await wallet.createAction({
  description: 'Pay Bridget 10000 sats',
  outputs: [
    { satoshis: 10000, lockingScript: p2pkhFromPubkey(bridgetPaymentPubkey) },
  ],
});
```

No bespoke "transfer verb handler." `counterparty` is a first-class BRC-100 argument. The same call works whether the underlying wallet is Metanet Desktop, headless ProtoWallet+txbuilder, or future plexus-recovery.

## Running the conformance suite

```bash
cd /Users/toddprice/projects/semantos-core/worktrees/canon-c6a-wallet
bun test cartridges/shared/wallet/headless-unified-wallet.test.ts
```

Expected: all crypto + sentinel tests green. `createAction` test asserts it throws `NotImplementedYet` (intentional placeholder).
