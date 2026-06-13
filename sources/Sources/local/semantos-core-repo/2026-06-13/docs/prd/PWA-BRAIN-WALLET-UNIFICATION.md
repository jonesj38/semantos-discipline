---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PWA-BRAIN-WALLET-UNIFICATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.698455+00:00
---

# PWA ↔ Brain wallet unification + operator/user trust model

Status: **spec** (L11 P6). Foundation landed (`deriveSegment` conversion,
commit `370478c`, branch `feat/plexus-l11-pwa-wallet`); the tree
re-architecture below is the remaining work.

Reference: `docs/prd/CW-LIFT-ROADMAP.md` §2.2 (CW Lift L11);
`docs/canon/cw-lift-matrix.yml` L11.

---

## 0. Context

The L11 reframe made `deriveSegment` (EP3259724B1, `child = parent +
SHA-256(segment)·…`) the canonical **unilateral** key-derivation primitive;
BRC-42 stays the **bilateral** (real-counterparty) primitive. Landed + merged
across: the Plexus SDK (`deriveNodeKey`), the brain hat keys (`hat_bkds`), the
TS wallet change/anchors (`ecdh42.ts` / `cell-anchor.ts`), the Zig wallet
anchors (`wallet_exports.zig` / `wallet_op_http.zig`), and the recovery-envelope
notation. The PWA (`apps/semantos`) is a **fourth** wallet implementation —
pure-Dart, pointycastle — whose self-derivation primitive is now converted to
`deriveSegment` (`brc42_derive.dart`, 111/111 wallet tests green).

What remains: the PWA derives keys through a **different tree** than the brain,
so the same operator identity produces *different* on-chain keys in the PWA vs
the brain. This spec unifies them.

---

## 1. Trust model — peers, with operator/admin vs. isolated user

The PWA and the brain are **peers**, but the relationship has two distinct
identity roles. The wallet unification only applies to one of them.

### Operator (admin)
- The operator owns the brain **and** runs the PWA as an admin console.
- The operator's PWA holds the **operator identity key** — i.e. the PWA's
  `cert_body` IS the brain's pinned operator identity key (`/api/v1/info`
  exposes the brain's operator cert id + pubkey).
- Because both sides hold the same identity key, **once the trees match**
  (§2), the PWA and brain derive **byte-identical** change/anchor keys — true
  unification. The operator can administrate the brain from the PWA.

### User (field-app, non-admin)
- A user of the app that the brain backs has their **own, distinct identity**
  — never the operator key. (A constrained device→operator binding exists via
  the *bilateral* BRC-42 device-pair path, e.g. `cartridges/oddjobz/.../
  device-pair-client.ts`; that binds a device to the operator without handing
  it the operator's private key.)
- Their PWA never loads the operator `cert_body`, so it **cannot derive the
  operator's wallet keys** — wallet isolation is *inherent* in identity-scoped
  derivation, not a bolt-on.

### Is the isolation achievable? Yes — two independent layers
1. **Key layer (already true).** Keys are identity-derived. A non-admin holds
   a different identity → derives a disjoint key universe → can never produce
   the operator's change/anchor/signing keys. The unification in §2 is scoped
   to the operator identity *by construction*.
2. **Access layer (needs T7).** Today the brain authenticates with a **single
   bearer token** (`brain_http_client.dart`; whoever holds it has full
   access) — there is no operator-vs-user distinction at the HTTP boundary
   yet. The intended model ([[brain_auth_model_intent]], tracker **T7**) is
   BRC-52 cert + capability: the operator cert carries an **admin capability**;
   user certs do not, so the brain rejects them on admin routes. The brain
   already has capability infrastructure (`host_capability_table.zig`) for
   host-function gating; extending it to gate HTTP routes by cert-capability
   is the access-isolation work.

**Net:** operator-administrates-from-PWA + user-isolated-from-brain is
achievable and is the natural shape. Wallet isolation holds today (identity
scoping). Access isolation is gated on closing T7 (replace the single bearer
token with cert+capability auth). This unification spec assumes the **operator
identity** throughout; a non-admin user's PWA simply never enters this path.

---

## 2. Re-architecture — make the operator PWA tree match the brain

Goal: for the operator identity, PWA `change`/`anchor` keys ==
brain `deriveChangeSk` / `deriveCellAnchorSk`.

Current PWA tree (4-layer): `cert_body → tier0 → {change, spend, anchor}`
(`tier0_cache.dart` parents *every* domain off `tier0Sk`; anchors keyed by a
**purpose string**). Brain: derives change/anchor **directly from
`identitySk`**, anchors keyed by **`typeHash`**.

### 2.1 Parent change + anchor on the identity key (not tier-0)
- Change/anchor must derive from `cert_body` (the identity key) directly, so
  `deriveSegment(cert_body, invoice)` == brain `deriveChangeSk(identitySk, …)`.
- `tier0` + `spend` stay tier-0-parented (PWA-only domains; no brain
  counterpart).
- **Security note:** the current design deliberately drops `cert_body` out of
  scope right after deriving `tier0`. Parenting change/anchor on the identity
  key reverses that hardening. **Preferred:** re-read `cert_body` from the
  store on demand for change/anchor derivation (keeps the "don't retain the
  root" posture) rather than caching it. (The brain *does* hold its identity
  key in memory, so caching would also be defensible — but on-demand re-read
  is the safer default unless profiling says otherwise.)

### 2.2 Re-key anchors: purpose-string → typeHash
- `DerivationDomain.anchor(purpose)` → `anchor(typeHash)` with
  `protocolHash = SHA-256(hex(typeHash))[0:16]` (byte-identical to
  `cell-anchor.ts` `anchorProtocolHash`). Invoice = `protocolHash(16) ‖
  anchorIndex_le8(8)` (the unified 24-byte segment).
- **Schema migration:** `recipe_store.dart` `DerivationRule` stores `purpose`
  for anchor scope → store `typeHash` instead. Update `wallet_bridge.dart`
  (`_domainFromRule`), `wallet_key_service.dart`, and every anchor call site,
  including the **mainnet MNCA path** (memory `mnca_anchor_onchain_mainnet`;
  the PWA `wallet.html` did the proven anchor). Decide read-compat for any
  existing `purpose`-keyed recipe rows (clean cutover acceptable — throwaway
  artefacts, no spend intent).

### 2.3 Recovery notation (mirror the TS P5 work, PR #876)
- `apps/semantos/lib/src/plexus/envelope.dart`: bump `kAlgorithmVersion`
  1 → 2 (envelope KDF-era counter; widen any literal type to allow reading
  legacy `1`).
- `recipe_store.dart` `DerivationRule`: add a per-domain `kdfVersion`
  (`plexus-kdf-v1` | `plexus-kdf-v2`) + `kdfVersionForScope(DerivationScope)`.
  In the PWA, **all** implemented domains are unilateral → `plexus-kdf-v2`;
  only the deferred `counterparty` scope is bilateral → `plexus-kdf-v1`.

### 2.4 Verification (must-have)
- **Cross-language KAT** proving real key-equality: for a fixed
  `(identityKey, index)` and `(identityKey, typeHash, index)`, PWA
  `change`/`anchor` priv+pub == TS `deriveChangeSk` / `deriveCellAnchorSk`.
  Generate the TS vectors with `bun` against
  `cartridges/wallet-headers/brain/src/{ecdh42,cell-anchor}.ts`; assert in a
  Dart test. (Same shape as the Zig anchor KAT proven in PR #873.)
  - Assumption to state explicitly: PWA `cert_body` == brain `identitySk`
    (same operator identity key). The KAT proves byte-equality *given* that.
- `flutter test test/wallet/` stays green (expect to update hardcoded
  expectations in `recipe_store_test.dart` / `wallet_bridge_test.dart` for the
  anchor schema change).

### 2.5 Scope
~8 files: `brc42_derive.dart` (done), `derivation_domain.dart`,
`tier0_cache.dart`, `recipe_store.dart`, `wallet_key_service.dart`,
`wallet_bridge.dart`, `plexus/envelope.dart`, plus tests + a new cross-lang KAT.
Security-posture + mainnet-path sensitive → land as its own focused PR with the
KAT as the gate.

---

## 3. Out of scope (tracked elsewhere)
- T7 cert+capability auth (the *access*-isolation half of §1). Separate work.
- The bilateral `peer/counterparty` derivation domain (PWA `edge_derive.dart`
  stays BRC-42; PR-C11-7 territory).
