---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CONTACTS-BOOK-PKI-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.699514+00:00
---

# Phase U.3 — contacts-book PKI (implementation brief)

**Status**: paste-ready agent brief.
**Depends on**: U.2 (brain UDP dispatch landed).
**Subagent type**: bsv-blockchain-wallet-toolbox-expert (covers both Dart-mobile and Zig-brain + the BSV identity primitives).
**Estimated effort**: 4-6 days, splits into 3 sub-phases.

---

## Background

`UDP-MESH-DIRECTION.md` §2.2 lays out the contacts-book-as-PKI vision. The contacts book stores BRC-52 public keys of trusted peers; ECDH between local-priv × peer-pub yields a per-peer shared secret used to authenticate UDP datagrams via HMAC.

The existing customers store (`runtime/semantos-brain/src/customers_store_fs.zig`) is the closest pattern to copy. The new `oddjobz.peer.v1` cell type is a sibling — different schema, same FS-backed JSONL store + in-memory cache shape.

This brief splits into U.3a/b/c so each sub-PR is reviewable in isolation.

---

## Sub-phase U.3a — `oddjobz.peer.v1` cell type + view store

**File scope**:
- `runtime/semantos-brain/src/peer_store_fs.zig` (new) — JSONL store + in-memory cache. Mirror `customers_store_fs.zig` line-by-line, swap `Customer` → `Peer`.
- `runtime/semantos-brain/src/oddjobz_query_handler.zig` (modify) — add three RPC verbs: `oddjobz.list_peers`, `oddjobz.get_peer`, `oddjobz.add_peer`.
- Schema definition shipped alongside D-DOG.1.0c cell-types in whatever the canonical location is (search for `oddjobz.customer.v2` definition).

**Schema sketch**:
```
oddjobz.peer.v1 {
  cellId: <content-hash>          // 64-hex
  typeHash: <oddjobz.peer.v1>     // 64-hex
  displayName: string             // operator-friendly label
  brc52PubKey: <hex>              // 65-byte uncompressed or 33-byte compressed
  brc52CertChain: optional [<root-cert>, <child-cert>]
  lastSeenAddr: optional string   // "host:port" — populated by HEARTBEAT datagrams
  trustEstablishedAt: i64         // unix-seconds
  trustEstablishedVia: enum       // "qr-scan" | "bca-handshake" | "transitive"
  introducedBy: optional <peer-cellId>  // for transitive trust
  createdAt: i64
}
```

**Lookup key**: BRC-52 pubkey (deduplication). Add a `findByPubKey(...)` method.

**Tests**: 8-10 conformance cases — empty store, add 3 peers, find by pubkey, find by cellId, dedup on duplicate add (returns existing), v2-shape parse + write, missing optional fields.

---

## Sub-phase U.3b — ECDH adapter (both sides)

**Brain side** (Zig):
- `runtime/semantos-brain/src/ecdh_adapter.zig` (new) — wraps libsecp256k1 for `ecdh(local_priv, peer_pub) -> shared_secret`. Cache derived secrets per-peer in memory; invalidate on `oddjobz.peer.v1` re-mint.
- Wire into `udp_dispatcher.zig` (from U.2) so datagram HMAC verification looks up shared secret via this adapter.

**Mobile side** (Dart):
- `apps/oddjobz-mobile/lib/src/contacts/peer_repository.dart` (new) — wrapper over `oddjobz.list_peers` / `oddjobz.add_peer` RPC verbs (mirroring `JobsRepository` shape).
- `apps/oddjobz-mobile/lib/src/contacts/ecdh_adapter.dart` (new) — Dart ECDH using `pointycastle` (already in deps; SecureSigningKey.swift falls back to it). Same input/output shape as the Zig adapter.
- Cache derived secrets in `PeerRepository` keyed by peer cellId.

**Constraints**:
- ECDH derivation MUST be deterministic (same priv × same pub = same secret across runs). No randomness.
- The shared secret is 32 bytes (SHA-256 of the ECDH point's x-coordinate, per BRC-52 convention).
- Never log or persist the derived secret to disk — held in RAM only, re-derive on restart.

**Tests**:
- Round-trip: alice_priv × bob_pub == bob_priv × alice_pub
- Determinism: same inputs always yield same output
- Cross-platform parity: Dart and Zig adapters MUST yield identical bytes for the same inputs (test fixture: 5 known input pairs with expected output bytes; both sides verify).

---

## Sub-phase U.3c — Mobile UI: add peer + peer list + peer-tier indicators

**File scope** (Flutter):
- `apps/oddjobz-mobile/lib/src/contacts/peer_list_screen.dart` (new) — list of peers with display name + trust tier badge + last-seen indicator.
- `apps/oddjobz-mobile/lib/src/contacts/add_peer_screen.dart` (new) — QR-scan flow (uses `mobile_scanner` package — verify already in deps; if not, ADD it because there's no clean alternative).
- `apps/oddjobz-mobile/lib/src/helm/job_list_row.dart` (modify) — when a job has a customer who is also a peer, show a small "trusted peer" indicator. Cross-references the peer cellId.
- `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` (modify) — add peer-list entry to settings menu OR a new dock node (operator decision; default: settings menu entry).

**QR code format**:
```
oddjobz://peer?pubkey=<hex>&name=<urlencoded>&cert=<base64-bca-chain>
```

When operator scans peer's QR → constructs the `oddjobz.peer.v1` cell → calls `oddjobz.add_peer` → cell minted on brain → mobile re-fetches peer list.

**Tests**:
- Widget tests for peer list (empty + populated + tier badges)
- QR parse → peer construction round-trip
- Add-peer flow: scan → cell minted → list updates

---

## Verification (all sub-phases)

```
cd /Users/toddprice/projects/semantos-core
cd runtime/semantos-brain && zig build test          # peer store + ECDH adapter conformance
cd ../../apps/oddjobz-mobile && flutter analyze && flutter test
cd ../.. && bun test                      # full TS suite (cross-platform parity tests)
cd proofs/lean && lake build              # defensive cross-check
cd ../tla && make check                   # defensive cross-check
```

# PR strategy

Three PRs, one per sub-phase. Each independently reviewable:
- `feat/u3a-peer-store` — schema + store + RPC verbs
- `feat/u3b-ecdh-adapter` — Dart + Zig adapters with cross-platform parity tests
- `feat/u3c-mobile-peer-ui` — UI flows

Auto-merge authority on green tests for each.

Report back per sub-phase: PR URL + which existing patterns were copied (e.g., "mirrored customers_store_fs.zig structure" or "extended JobsRepository pattern in peer_repository.dart").

---

## Open questions for operator (defer if unclear)

1. **Should peer cells be operator-only or shared?** The customers store (post-D-DOG.1.0c) holds shared customer cells. Should peers be local-only to the operator's brain, or syncable across paired devices? Recommend local-only initially — peers are personal trust assertions.
2. **QR vs BCA handshake for first-meet**: QR scan is the simplest UX but requires both phones present. BCA handshake (sub-phase U.3.future) lets you add a peer remotely if you have their BCA cert. Recommend ship QR first, BCA later.
3. **Trust-tier UI surface depth**: Just a badge, or should the attention surface use trust tier as a confidence bump (per UDP-MESH-DIRECTION §2.3)? Recommend badge only in U.3c; attention-surface integration is a Tier 2P follow-up.
