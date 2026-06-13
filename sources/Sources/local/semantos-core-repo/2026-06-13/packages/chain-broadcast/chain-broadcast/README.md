---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.518305+00:00
---

# @semantos/chain-broadcast

Bulk on-chain anchoring services. Phase 35A deliverable.

Decomposed from the 1672-line monolithic hackathon `DirectBroadcastEngine`
into four focused, independently-usable services + a composition facade.
Reusable by any extension or app that needs to push cells to BSV at scale
— poker-agent today; CDM lifecycle, SCADA events, metering settlement,
media-protocol paywall commitments (35B) downstream.

```
                 ChainBroadcaster                (facade)
             ┌────────────┬──────────────┬──────────────┐
             │            │              │              │
    CellTxBuilder  MapiBroadcaster  ChainTipManager  BeefStore
    ─────────────  ───────────────  ───────────────  ─────────
    cell → signed tx  tx → miner    UTXO pool +      BRC-62 BEEF
    (@bsv/sdk)        (ARC/MAPI)    waitForArcSeen   persistence
                      ARC injected  disk snapshot
```

## Independent or composed

Each service is usable on its own (multipath subpath exports), or via
`ChainBroadcaster` which composes all four with the plumbing pre-wired:

```ts
// Use an individual service
import { BeefStore } from "@semantos/chain-broadcast/beef-store";
import { MapiBroadcaster } from "@semantos/chain-broadcast/mapi-broadcaster";

// ...or the facade
import { ChainBroadcaster } from "@semantos/chain-broadcast";

const broadcaster = new ChainBroadcaster({
  keySeed: "operator-node-01",
  streams: 4,
  mode: "arc",
  arcUrl: "https://arc.gorillapool.io",
  beefStore: { filePath: "/var/lib/semantos/chain.beef" },
  chainTipPath: "/var/lib/semantos/chaintip.json",
  auditLogPath: "/var/log/semantos/audit.csv",
});

await broadcaster.preSplit(fundingUtxo);
await broadcaster.createCellToken(0, cellBytes, "/foo/bar", contentHash);
await broadcaster.transitionCellToken({
  streamId: 0, prevCellTxid, prevCellVout, prevCellTx,
  newCellBytes, semanticPath: "/foo/bar", contentHash: newHash,
});
await broadcaster.flush();            // drain + persist + snapshot
```

## Services

| Service | File | Concern |
|---|---|---|
| [`CellTxBuilder`](src/cell-tx-builder.ts) | `cell-tx-builder.ts` | Pure BSV tx construction. 5 builders: `preSplit`, `cellToken`, `transition` (PushDrop custom sign), `opReturn`, `sweep`. No I/O. |
| [`MapiBroadcaster`](src/mapi-broadcaster.ts) | `mapi-broadcaster.ts` | ARC (bulk `/v1/txs` + WoC fallback) or MAPI (direct miner POST with 3-retry 429). ARC instance INJECTED — the hackathon version hardcoded `new ARC(...)` and was untestable. `fetchImpl` and `enableWocFallback: false` let unit tests run network-free. |
| [`ChainTipManager`](src/chain-tip-manager.ts) | `chain-tip-manager.ts` | Per-stream UTXO pools (no cross-stream double-spend), dust-floor filtering, disk-snapshot persistence + restart safety, `waitForArcSeen()` tip polling. |
| [`BeefStore`](src/beef-store.ts) | `beef-store.ts` | Durable BRC-62 BEEF envelope. `mergeTransaction`, `extractUtxos`, `getAtomicBEEF(txid)`, atomic disk persist on a timer. |

## @bsv/sdk policy

Chain-broadcast is the package where `@bsv/sdk` is expected — it's literally
building BSV transactions. The session-protocol single-chokepoint rule
(G35A.12) doesn't apply here. Callers that want to abstract over signing
for hardware-wallet use cases can pass a custom `PrivateKey` into
`ChainBroadcasterConfig` (via `privateKeyWif`, `privateKeyHex`, `keySeed`,
or direct `privateKey`).

## Tests

`src/__tests__/` — 18 tests covering BeefStore persistence/restore + UTXO
extraction (9) and ChainTipManager pool ops + disk round-trip (9).

Skipped: `beef-broadcast.test.ts` from the hackathon — exercises raw
`@bsv/sdk` `Beef` / `MerklePath` primitives rather than our own code.

## What's NOT here

- **Session-peer event delivery.** That's what
  [`@semantos/session-protocol`](../../runtime/session-protocol/) does.
  Anchoring is orthogonal — a session may or may not commit state on
  chain.
- **Funding discovery.** `discoverUtxos(address)` against WoC/Bitails and
  `waitForFunding(address, timeoutMs)` from the hackathon engine are
  deployment glue, not bulk-anchoring logic. Callers implement discovery
  in their match runner / node entrypoint.
- **Border-router aggregation.** Cross-host fleet funding lives in
  [`apps/settlement`](../../apps/settlement/).
