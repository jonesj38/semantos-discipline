---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-W6-W7-NEXT-PHASE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.729794+00:00
---

# Wallet Next Phase — W6 (Sovereign Node) + W7 (Plexus Dispatch)

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` §7.6 / §7.7 / §8 / §10.2 / §12

---

## 0. Where We Are

Engine + proof + storage layers are done:

| Phase | Status |
|---|---|
| W1 — `OP_SIGN` + `host_sign` + bsvz differential | ✅ |
| W2 — Lean Sign.lean + K11 / K12 | ✅ |
| W3 — Budget ops + K13 | ✅ |
| W3.5 — DerivationStateStore + BRC-42 derivation | ✅ |
| W4 — AES-GCM at-rest + host_unlock_tier / persist / load | ✅ |
| W8 — TLA+ KeyCustody / TierEscalation / ReplayPrevention extended | ✅ |
| WP1–WP9 — K4 substantive promotion + Lean coverage extension | ✅ |
| WT1–WT3 — TLA+ wallet model coverage | ✅ |

Engine has signing, budget, derivation, encrypted storage, and three layers of formal coverage. What's missing for a usable wallet: a deployment target (W5 browser / W6 node), the recovery story (W7), the UI (W9), and end-to-end validation (W10).

This plan covers the next two: **W6 and W7 in parallel**, mirroring the W4+W8 split that worked last session. They have no dependency on each other — W6 stands up the runtime, W7 builds the recovery dispatch as a library that any deployment target can use.

---

## 1. W6 — Sovereign-Node Target

### 1.1 Scope

A Zig binary (`runtime/node/`) that links the cell-engine + bsvz + plexus-zig (W7's library) and exposes BRC-100 over WSS to browser dApps. Caddy fronts it with TLS. lmdb provides the W4 storage backend's persistent layer (in place of IndexedDB).

Per `WALLET-TIER-CUSTODY.md` §10.2.

### 1.2 Deliverables

| # | File | Purpose |
|---|---|---|
| W6.1 | `runtime/node/src/main.zig` | Entry point: parse Caddyfile, init storage, init engine, bind WSS endpoint |
| W6.2 | `runtime/node/src/wss_server.zig` | WSS server speaking BRC-100 wire protocol — JSON-RPC-style request/response with the `x-brc100-*` envelope from Plexus Tech Reqs §3 |
| W6.3 | `runtime/node/src/brc100_dispatch.zig` | Maps BRC-100 method names (`createAction`, `signAction`, `getPublicKey`, `listOutputs`, `internalizeAction`, `isAuthenticated`) to engine + storage + derivation calls |
| W6.4 | `runtime/node/src/lmdb_slot_store.zig` | Implements `SlotStore` interface (W4) backed by lmdb — same vtable shape as `LocalSlotStore` |
| W6.5 | `runtime/node/src/lmdb_derivation_store.zig` | Implements `DerivationStateStore` interface (W3.5) backed by lmdb |
| W6.6 | `runtime/node/Caddyfile` | TLS + reverse proxy: `wss://node.semantos.{tld}/wallet → :8090`, `https://node.semantos.{tld}/ → static UI bundle`, `https://node.semantos.{tld}/p2p/* → mesh layer (placeholder)` |
| W6.7 | `runtime/node/tests/integration.zig` | Smoke test: spin up node, open WSS, call `getPublicKey`, get a 33-byte response, verify it matches the locally-derived identity pubkey |
| W6.8 | `runtime/node/README.md` | How to build, run, deploy; the BRC-100 method coverage matrix (which of the 28 spec methods are wired in v0.1 vs deferred) |

### 1.3 BRC-100 method coverage for v0.1

Per the methods table in §1 of the wallet design doc (and the BRC-100 review I did earlier), v0.1 covers the wallet's hot path. Defer the broader certificate / discovery surface to v0.2.

| Method | v0.1 | Notes |
|---|---|---|
| `getPublicKey` | ✅ | Read identity / derived pubkeys via BRC-42 |
| `isAuthenticated` | ✅ | True iff a wallet exists in storage |
| `waitForAuthentication` | ✅ | Blocks until first wallet creation completes |
| `createAction` | ✅ | Build + sign tx via the engine; uses tier appropriate for the spend amount |
| `signAction` | ✅ | Sign the partially-constructed tx |
| `internalizeAction` | ✅ | Accept incoming BEEF, parse outputs, credit hot budget for "wallet payment" outputs |
| `listOutputs` | ✅ | Query persisted budget cells |
| `listActions` | ✅ | Query tx history from lmdb |
| `getHeight` / `getHeaderForHeight` / `getNetwork` / `getVersion` | ✅ | Trivial stub from local config + bsvz broadcast client |
| `createSignature` / `verifySignature` / `createHmac` / `verifyHmac` / `encrypt` / `decrypt` | 🟦 v0.2 | Need BRC-42 + AES-GCM glue per protocol/keyID/counterparty |
| `acquireCertificate` / `listCertificates` / `proveCertificate` / `relinquishCertificate` / `discoverByIdentityKey` / `discoverByAttributes` | 🟦 v0.2 | Identity certificate surface — depends on cert issuer integration |
| `revealCounterpartyKeyLinkage` / `revealSpecificKeyLinkage` | 🟦 v0.2 | BRC-69 linkage |
| `abortAction` / `relinquishOutput` | 🟦 v0.2 | Tx lifecycle edge cases |

v0.1 ships the 13 methods that make a wallet usable for sending and receiving sats; v0.2 adds the cert + linkage surface that makes it BRC-100 *complete*.

### 1.4 Acceptance criteria

1. `cd runtime/node && zig build` produces a single binary.
2. `runtime/node/tests/integration.zig` passes — node boots, WSS accepts a `getPublicKey` request, returns a valid 33-byte secp256k1 pubkey.
3. The 13 v0.1 BRC-100 methods round-trip correctly under a manual smoke test (script in `runtime/node/scripts/smoke.sh` that uses `wscat` or `websocat`).
4. Caddyfile starts cleanly with `caddy run --config Caddyfile` and the TLS handshake works against a self-signed cert.
5. Storage backend correctly persists a tier blob across node restarts (kill node, restart, verify the encrypted blob loads and decrypts under the same factor).
6. `WALLET-TIER-CUSTODY.md` §10.2 topology diagram updated to mark W6 ✅.

### 1.5 Sizing

Estimate **2–3 days**. Most of the work is wire-protocol glue and lmdb integration; the engine + storage + derivation already exist as Zig libraries. Risk: WSS framing on Zig is less mature than HTTP — if `std.http` doesn't have WSS in 0.15.2, may need to vendor `websocket.zig` or similar.

---

## 2. W7 — Plexus Dispatch Module

### 2.1 Scope

A Zig library (`core/plexus-dispatch/`) that builds the recovery enrollment + recovery flows specified in `WALLET-TIER-CUSTODY.md` §7.7 and §8. Per §8 the wallet has zero runtime dependency on Plexus — this module is loaded only when the user explicitly opts into recovery enrollment or initiates recovery on a fresh device.

### 2.2 Deliverables

| # | File | Purpose |
|---|---|---|
| W7.1 | `core/plexus-dispatch/src/envelope.zig` | Build the JSON dispatch envelope per §8.2 schema. Five mechanically-checkable invariants enforced before serialization (no plaintext keys / mnemonics / answers; encrypted seed under PBKDF2-derived KEK; answer hashes use same normalized inputs as KEK derivation; envelope signed by identity key; certId matches BRC-52 cert) |
| W7.2 | `core/plexus-dispatch/src/brc100_envelope.zig` | Wrap the JSON in a BRC-100 signed request — `x-brc100-identitykey`, `x-brc100-nonce`, `x-brc100-timestamp`, `x-brc100-signature` headers. Reuses bsvz `crypto.sign` for the signature |
| W7.3 | `core/plexus-dispatch/src/transport.zig` | HTTPS POST to `plexus-keys.com/enrollment/dispatch` and `/enrollment/confirm`. Pluggable HTTP backend (mockable for tests) |
| W7.4 | `core/plexus-dispatch/src/otp_loop.zig` | OTP request/confirm state machine. Pure data-flow (no UI) — exposes a callback that the host (browser / node UI) implements to prompt the user |
| W7.5 | `core/plexus-dispatch/src/recovery.zig` | Recovery flow per §7.8: `POST /recovery/initiate`, OTP loop, present challenge questions, hash answers locally, `POST /recovery/complete`, decrypt seed using the same answer-derived KEK locally |
| W7.6 | `core/plexus-dispatch/tests/envelope_conformance.zig` | Round-trip test: build envelope from synthetic state, parse it back, verify all 5 invariants hold. Cross-check the encrypted-seed ciphertext is decryptable only with the correct KEK |
| W7.7 | `core/plexus-dispatch/tests/transport_conformance.zig` | Mock-HTTP test: dispatch envelope + OTP loop reaches "enrolled" state without ever transmitting plaintext private material |
| W7.8 | `core/plexus-dispatch/README.md` | Usage from the wallet's perspective; documents what Plexus operator API endpoints are expected to exist and what HTTP responses to handle |

### 2.3 What W7 does NOT include

- **Plexus operator's server-side implementation.** That's a separate Go service per Plexus Tech Reqs §1; W7 is the client-side wire protocol only.
- **UI for the OTP / challenge flow.** W7 exposes a callback API; the actual rendering is W9.
- **Subscription billing integration.** Plexus operator's concern.
- **BRC-103-style nonce handshake** (Plexus Network SDK §4 constraint #4) — defer to v0.2 unless the operator's API requires it on first dispatch.

### 2.4 Acceptance criteria

1. `cd core/plexus-dispatch && zig build test` — all envelope + transport tests pass.
2. **Static guarantee**: `grep -rE "priv_key|mnemonic|plaintext_answer" core/plexus-dispatch/src/` returns *only* references inside type signatures or comments — no actual values transmitted. (Belt-and-braces over the JSON schema invariants.)
3. Envelope round-trip: build envelope → serialize → parse → verify identity sig → assert structural equivalence with input.
4. Encrypted seed round-trip: encrypt under a known KEK → decrypt → matches input. Decrypt under wrong KEK → fails with auth tag error (AES-GCM property).
5. Mock HTTP test: dispatch envelope through a fake HTTP server, observe the OTP loop runs, fake server returns success, wallet state correctly marks recovery-enrolled.
6. README documents the exact 4 Plexus operator endpoints used: `POST /enrollment/dispatch`, `POST /enrollment/confirm`, `POST /recovery/initiate`, `POST /recovery/complete`. Each with request/response JSON shape.
7. `WALLET-TIER-CUSTODY.md` §8 marked ✅.

### 2.5 Sizing

Estimate **2 days**. The cryptographic primitives (PBKDF2, AES-GCM, BRC-42, ECDSA sign) all exist in bsvz. Most of the work is JSON serialization, HTTP plumbing, and conformance tests. Lower risk than W6 — no new system surface, all in-process.

---

## 3. Parallel Execution

Same pattern as W4+W8:

```
┌─── W6 (sovereign node) ───┐
│                            │
└─── W7 (plexus dispatch) ───┴─► W7 library is linkable from W6's binary
```

W7 ships as a standalone Zig package. W6 imports it at link time. The two can be built and tested independently; the integration point is W6.3 (`brc100_dispatch.zig`) calling into `core/plexus-dispatch` for the enrollment + recovery handlers.

Recommended dispatch:

- **One agent on W6** — runs in `runtime/node/`, focused on WSS server + lmdb + Caddyfile + the 13-method BRC-100 surface.
- **One agent on W7** — runs in `core/plexus-dispatch/`, focused on envelope + transport + OTP loop + recovery.

Each agent's acceptance criteria are local (their package builds, their tests pass). A short follow-up commit wires W7 into W6's `brc100_dispatch.zig` for the enrollment endpoint.

---

## 4. After W6 + W7

| Status | Workstream |
|---|---|
| ✅ Done after W6+W7 | W6 (sovereign node), W7 (Plexus dispatch) |
| 🔲 Next | W5 — browser bundle (trim bsvz, iframe + popup transport, IndexedDB-backed storage). Same W6 surface but compiled to WASM with a different storage adapter. |
| 🔲 Next | W9 — wallet UI (HTML+WASM, served by W6's Caddy or as a static bundle). Most user-visible work. |
| 🔲 Next | W10 — end-to-end recovery test: provision new device, walk recovery flow, spend at every tier. |
| 🔲 v0.2 | W11 — vault multisig + nSequence cooldown. |

After W6+W7 the wallet is *runnable end-to-end on a sovereign node* — you can sign sats, opt into recovery, and recover on a fresh node. The browser story (W5+W9) is a deployment-target swap, not new core code.

---

## 5. Recommendation Order

If you can dispatch both in parallel:

- **Day 1**: kick off W6 + W7 agents.
- **Day 2–3**: W6 finishes (longer due to wire protocol surface).
- **Day 2**: W7 finishes (smaller scope, no system surface).
- **Day 3 / Day 4**: integration commit wiring W7 into W6's enrollment handler.

If you can only do one:

- **W7 first** — smaller, lower-risk, covers the recovery story without requiring a runtime. Lets you ship the freemium pitch ("here's what enrollment looks like, here's what recovery looks like") in isolation.
- **W6 first** — bigger, but gets you a real running wallet. Needs W7 stub for enrollment to actually work, but the stub is a one-liner ("recovery not configured" hardcoded).

I'd start W6+W7 in parallel — same pattern that just delivered W4+W8 cleanly.

---

*Cross-references*

- `docs/design/WALLET-TIER-CUSTODY.md` §7.6 (creation), §7.7 (enrollment), §7.8 (recovery), §8 (Plexus boundary), §10.2 (sovereign node topology), §12 (implementation order)
- `core/cell-engine/src/host.zig` — host imports W6 must implement (sign, unlock_tier, persist_cell, load_cell, derive_leaf, state_next_index)
- `core/cell-engine/src/slot_store.zig` — W4 SlotStore vtable W6.4 implements
- `core/cell-engine/src/derivation_state.zig` — W3.5 DerivationStateStore vtable W6.5 implements
- bsvz `primitives.aesgcm`, `primitives.bip32`, `primitives.bip39`, `primitives.ec.deriveChild`, `crypto.hmacSha256`, `broadcast.*`
- Plexus Tech Reqs Draft v1.3 §1 (operator API), §3 (Plexus Contracts JSON shape)
- Plexus Client Reqs Draft v2.1 §1.1 (enrollment), §2 (recovery flow)
