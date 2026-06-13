---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.739928+00:00
---

# Site as Sovereign Node — WSITE1–WSITE6

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` (BRAIN foundation), `docs/design/WALLET-TIER-CUSTODY.md` (v0.4), `docs/design/WALLET-MOBILE-AUTH-FLOW.md`

---

## 0. Headline

> A site operator's Semantos sovereign node serves their website *and* runs their wallet *and* gates content via HTTP 402 / identity-cert challenges *and* receives BRC-29 micropayments — all from one Zig binary on a $5/mo VPS. Replaces the Vercel + Stripe + Auth0 + MetaMask stack with a single self-hosted process. Site visitors hit the site, get challenged, complete a BRC-100 wallet flow, return authenticated. Operator's wallet signs site config + receives revenue. Same node, same binary, two roles.

---

## 1. The Pattern

```
┌──────────────────────────────────────────────────────────┐
│  pokerapp.example.com  (1 VPS, semantos-shell binary)     │
│                                                             │
│  Browser request: GET /play                                 │
│      ↓                                                       │
│  Site config: /play requires identity_auth OR 1000 sats     │
│      ↓                                                       │
│  Response: 402 Payment Required, X-Semantos-Challenge: ...  │
│      OR    401 Unauthorized, X-Semantos-Challenge: ...      │
│      ↓                                                       │
│  Browser frontend redirects to wallet origin                 │
│      ↓                                                       │
│  User signs in / pays / both                                │
│      ↓                                                       │
│  Browser navigates back: /auth/callback?identityCert=...    │
│      ↓                                                       │
│  Site verifies cert + signature, sets session cookie        │
│      ↓                                                       │
│  Browser request: GET /play (with session cookie)           │
│      ↓                                                       │
│  Site responds: 200 OK with game content                    │
│                                                             │
│  Meanwhile, on the same node:                                │
│   - Site admin's wallet receives any payment txs            │
│   - Admin's identity key signs the site's config cells      │
│   - All site state persists to the node's lmdb              │
└──────────────────────────────────────────────────────────┘
```

The point: **site hosting + wallet + auth + payments are all one process**. The same BRAIN shell that runs the admin's wallet also runs the HTTP server that serves the site, the 402 handler that gates content, and the auth callback that converts BRC-100 signatures into session cookies. No separate web tier, no separate auth provider, no separate payment processor. One Zig binary.

---

## 2. Where We Are

BRAIN (Wallet Shell) provides the substrate: WASM modules, REPL, storage, host-import broker. It exposes a wallet over WSS for browser/mobile clients. What it doesn't yet do:

| Gap | Current | Needed |
|---|---|---|
| Static + dynamic web content serving | none | HTTP server for HTML/CSS/JS, optional templating |
| Site config / route declarations | none | DSL or schema for "this path requires X" |
| HTTP 402 challenge protocol | none | Issue + validate BRC-29 payment receipts |
| Identity-cert auth flow | none | Issue + validate BRC-100 identity signatures, set session cookies |
| Admin REPL commands for site ops | wallet only | `serve site`, `set price`, `view revenue`, etc. |
| (Optional) end-user wallet hosting | single-wallet-per-node | per-user scoped storage + endpoint |

WSITE adds these layers on top of BRAIN. The two are co-deployable but architecturally separate — a node operator can run BRAIN alone (just a wallet), or BRAIN + WSITE (a website + wallet + auth + payments).

---

## 3. Phases

### WSITE1 — Site config schema (~ 1 day)

**Goal**: a declarative way for the operator to say "these paths exist, these gates apply, this is the content."

**Deliverables**:

1. New `site.toml` (or `site.zon`) schema, lives in `~/.semantos/sites/<domain>/`. Operator-readable, hand-editable, auditable. Example:

```toml
[site]
domain = "pokerapp.example.com"
content_root = "./public"
admin_identity = "02a3b7...8f4c"           # admin's wallet pubkey
config_signature = "30440220..."             # admin signs the config

[routes."/"]
type = "static"
file = "index.html"
public = true                                # no auth required

[routes."/play"]
type = "dynamic"
handler = "game.wasm"                        # custom WASM handler module
auth = "identity_required"                   # need a valid BRC-100 cert
identity_issuers = ["pokerapp.example.com", "*"]   # accept any issuer

[routes."/premium"]
type = "static"
file = "premium.html"
auth = "payment_required"
price_sats = 5000
payment_recipient = "default"                # admin's default basket

[routes."/api/score"]
type = "dynamic"
handler = "scoreboard.wasm"
auth = "identity_required"
rate_limit = "60/minute"
```

2. Site-config cell — the operator's wallet signs the config (mirrors the POLICY cell pattern from §6.3 of the wallet design). Mutations require admin's identity key + tier-2 factor. Cells stored in lmdb under `~/.semantos/sites/<domain>/config-cells/`.

3. Schema validator — `semantos site validate <domain>` checks the config, surfaces typos, missing handler files, invalid pubkeys, etc.

4. Hot reload — config changes via `semantos site reload <domain>` apply without restarting the shell. Currently-active sessions retain their grants under the old config; new sessions use the new config.

**Success criterion**: `semantos site init pokerapp.example.com --content ./public` scaffolds a `site.toml` and signs the initial config. `semantos site validate` passes. Editing `site.toml` and `semantos site reload` applies changes without disrupting wallet operation.

### WSITE2 — Static + dynamic content serving (~ 2 days)

**Goal**: the shell serves HTTP content per the site config. Static files for static routes, WASM-handler dispatch for dynamic routes.

**Deliverables**:

1. `runtime/shell/src/site_server.zig`. Listens on `:80` and `:443` (TLS via Caddy or built-in via Zig's `std.crypto.tls`). Routes incoming requests to handlers per the site config.

2. Static handler: serves files from `content_root` with appropriate content types, caching headers, gzip compression, ETags. Standard web server fare.

3. Dynamic handler: loads a WASM module (per route's `handler` field) into the shell's wasmtime runtime. Handler module is hash-pinned same as the wallet engine and headers verifier. Handler exports a `handle_request(request_ptr, request_len, response_ptr, response_len_max) -> response_len: i32` function. Receives the request as a serialized struct (method, path, headers, body), returns a response struct.

4. Handler module isolation — each handler runs in its own wasmtime instance, can't read other handlers' memory or the wallet engine's state. Host imports for handlers are scoped (e.g., handlers can call `host_lookup_session(token)` to verify auth, but can't call `host_sign` directly).

5. **Caddy integration**: by default the shell binds to `:8080` and Caddy fronts it with TLS termination + Let's Encrypt. Operators can opt into the shell's built-in TLS for zero-dependency deployment.

6. Request log — every served request recorded to `~/.semantos/sites/<domain>/access.log` (with PII-aware redaction — never log auth tokens or session cookies in plaintext).

**Success criterion**: `semantos start` brings up the site; `curl https://pokerapp.example.com/` returns the static `index.html`; `curl https://pokerapp.example.com/play` returns 401 with the correct challenge header; access log accumulates entries.

### WSITE2.5 — Dynamic-route WASM-handler dispatch (~ 1.5 days) ✅ shipped (v0.1 ABI)

**Goal**: routes typed `"dynamic"` no longer return 501.  Each route's handler WASM is hash-pinned, pre-instantiated at `brain serve` boot, and invoked per-request via a minimal pure-function ABI.  Handlers are sandboxed alongside the wallet engine + headers verifier under the same broker policy gate.

**Shipped**:

1. **Handler ABI v0.1** — exports `memory` + `handle(method: i32, body_len: i32) -> i64`.  Host writes the request body to memory[0..body_len], calls `handle(method, body_len)`, reads the packed return: `(status: u16) << 32 | (response_len: u32)` with the response bytes at memory[0..response_len].  `method` is enum-encoded (`1=GET`, `2=POST`, … `0=other`).  Path is intentionally not passed; handlers are bound to a single route per `site.json`.

2. **Hash-pinned handlers** — `site.json` route gains `handler_sha256`; the validator + loader refuse on absence (mirrors `brain start`).  Operators run `brain hash <handler>.wasm` once, paste, drop the binary at `<sites>/<domain>/handlers/<file>`.

3. **`broker.Module.dynamic_handler`** — new module kind, treated as untrusted code.  Existing policy gates (`module != .wallet_engine` etc.) auto-deny `host_sign`, `host_persist_cell`, `host_state_next_index`, `host_verify_beef_root` etc.  Stateless hash + chain-context primitives stay allowed because they bypass the broker entirely.

4. **`runner_mod.callHandlerHandle(instance, allocator, method, body)`** — re-exported from the wasmtime backend; takes the request body, marshals it into instance memory, calls `handle`, reads the response back.  Caps: 4 MiB request, 4 MiB response (larger → 413).

5. **`site_server.attachRunner(runner)`** — pre-instantiates every dynamic route's handler at boot.  Failed loads (missing binary, hash mismatch, instantiate trap) are non-fatal: the slot is omitted, per-request dispatch returns 503 with the underlying error name.

6. **`cmdServe` DynamicRuntime** — only stands up the broker + slot/state/header stores + audit log + runner pipeline when at least one route is dynamic.  Static-only sites stay broker-free (no wasmtime cost, default-build-path stays minimal).

7. **Auth gates run BEFORE the handler** — a `payment_required + dynamic` route still demands the 402 callback before invoking `handle`; only authenticated requests reach the handler instance.

8. **Conformance**: a WAT fixture (`echo` handler that prefixes every body with `"echo: "` and returns status 200) round-trips bytes through `callHandlerHandle` end-to-end in the real backend.  A second 404 fixture exercises non-200 statuses.  Stub-mode tests assert the `wasmtime_not_enabled` error contract.

**What WSITE2.5 deliberately does NOT do**:

- **Custom response headers** — handlers can't yet emit Content-Type or Set-Cookie.  Host writes `Content-Type: <route extension sniff>` only.  ABI v2 will let handlers serialize a header block alongside the body.
- **Path / query / request-header passthrough** — handlers are bound to a single exact-match route; query strings + arbitrary request headers wait for ABI v2 (which lands alongside wildcard route matching in WSITE2.6).
- **Per-handler scratch storage** — handlers should be stateless; future `host_handler_kv_*` surface lands when there's a real use-case.  Today's instances are reused per request; nothing forces a memory reset, but operators should treat handler memory as scratch.

**Success criterion**: a hand-rolled "echo" handler binary scaffolded under `<sites>/<domain>/handlers/echo.wasm` with the right `handler_sha256` in `site.json` is invoked per request.  `curl -d "ping" http://localhost:8080/api/echo` returns `echo: ping` with status 200.  Static-only sites still serve without bringing up wasmtime.  In `-Denable-wasmtime=false` builds, dynamic routes return 503 with the rebuild hint.

### WSITE3 — HTTP 402 / identity-cert challenge protocol (~ 2 days)

**Goal**: the actual auth + payment gates that distinguish a Semantos-served site from a generic web server.

**Deliverables**:

1. `runtime/shell/src/auth_handler.zig`. Implements the challenge issuance + verification flow.

2. **Identity challenge (auth = "identity_required")**:
   ```
   Request:  GET /play
   Response: 401 Unauthorized
             X-Semantos-Challenge: type=identity_auth
             X-Semantos-Nonce: <16-byte random base64>
             X-Semantos-Expected-Issuers: pokerapp.example.com,*
             X-Semantos-Wallet-Origin-Hint: https://wallet.semantos.app
             X-Semantos-Return-To: /play
             Set-Cookie: __semantos_challenge=<nonce>; HttpOnly; Secure; Path=/auth
             Content-Type: text/html
             <html>... pretty error page with "Sign in with Semantos" button ...</html>
   ```

3. **Payment challenge (auth = "payment_required")**:
   ```
   Request:  GET /premium
   Response: 402 Payment Required
             X-Semantos-Challenge: type=payment
             X-Semantos-Nonce: <random>
             X-Semantos-Price-Sats: 5000
             X-Semantos-Recipient: 02e8...91
             X-Semantos-Recipient-Derivation: BRC-29(...)
             X-Semantos-Return-To: /premium
             Set-Cookie: __semantos_challenge=<nonce>; HttpOnly; Secure
             Content-Type: text/html
             <html>... "Pay 5,000 sats to access this content" ...</html>
   ```

4. **Auth callback handler** (`POST /auth/callback`):
   ```
   Body: {
     identityCert: <base64 BRC-52 cert>,
     signature: <DER ECDSA over the original nonce>,
     paymentTxid?: <if payment was required, the BEEF or txid>,
     paymentBeef?: <if internalized via the site's wallet, the full BEEF>
   }
   ```
   Verifies cert against trusted issuers, verifies signature against the nonce in the challenge cookie, validates the payment (if applicable) via the site's wallet's internalizeAction handler. On success: clears the challenge cookie, sets a session cookie (`__semantos_session=<JWT>`), redirects back to the original `Return-To` URL.

5. Session management: JWTs signed by the site admin's identity key. Stateless (claims include identity pubkey + expiry + originally-paid-for path if applicable). Site config can configure expiry (e.g., `session_ttl = "24h"` in `site.toml`).

6. Re-challenge logic: when a session is missing/expired, re-issue the appropriate challenge. Browsers should round-trip the auth flow seamlessly with redirects.

7. **The mobile flow specifically** — see `WALLET-MOBILE-AUTH-FLOW.md` for the full UX. WSITE3's role is the server side: issue challenges, accept callbacks, set session cookies. The wallet origin's role (covered in the wallet UX docs) is the client side: receive the challenge, complete the BRC-100 flow, redirect back.

**Success criterion**: `curl /play` returns 401 with the correct challenge headers. A test client that signs the nonce with a valid cert + posts to `/auth/callback` gets a `200 OK` redirect with a session cookie. Subsequent `curl /play` with the cookie returns `200 OK` with the game content. Tampered signature → `401 Unauthorized`. Expired session → re-challenge.

### WSITE4 — Payment receiver + revenue accounting (~ 1.5 days)

**Goal**: BRC-29 payments arriving at the site's `payment_recipient` are correctly received, internalized into the admin's wallet, and accounted to the originating session.

**Deliverables**:

1. The site's wallet (the BRAIN wallet engine running on the same node) is the recipient for `payment_required` routes. When a user's payment arrives via the auth callback's `paymentBeef`, the auth handler:
   - Calls `internalizeAction(beef)` on the admin's wallet (via the host broker)
   - The wallet validates the BEEF (W4 / WA2 + WH for SPV)
   - On success, the UTXO is added to the admin's OutputStore, basket = `default` or per-route configured
   - Auth handler links the payment to the session: stores `(session_id, payment_outpoint, satoshis, paid_for_path)` to lmdb

2. Revenue dashboard via REPL:
   ```
   > revenue --since "1 week ago"
     /premium          12 payments × 5,000 sats =  60,000 sats
     /api/premium-feed  3 payments × 1,000 sats =   3,000 sats
                                                ─────────────
                                                  63,000 sats (≈ $XX)
   
   > revenue --by-payer
     02e8...91 (alice)     45,000 sats across 9 payments
     03f1...4d (bob)       18,000 sats across 4 payments
   ```

3. Refunds — `semantos site refund <session_id>` constructs a refund tx using the original payment outpoint as input (paid back to the original payer's identity-derived address), signs with admin's wallet, broadcasts. Marks the session as refunded.

4. Per-route revenue limits (anti-DoS / abuse): `site.toml` can specify `daily_max_satoshis = 10000000` per route to cap exposure if a route is misconfigured.

5. Webhook integration — site config can declare `on_payment` webhooks that fire when a payment is received: `{ url: "https://my-other-service.com/payment", auth: "Bearer ..." }`. Useful for triggering downstream business logic.

**Success criterion**: end-to-end test — payer's wallet sends 5,000 sats to admin's site for `/premium`, admin's wallet internalizes, session granted, payer accesses `/premium`. `revenue` REPL command shows the payment.

### WSITE4.5 — On-chain SPV verification of payment claims (~ 0.5 days) ✅ shipped

**Goal**: close the WSITE4 v0.1 trust gap. WSITE4 records the payer's *signed claim* (signature commits to (nonce, txid, satoshis)) but doesn't verify the claim against the chain. WSITE4.5 takes the optional `payment.beef` field on the auth-callback and verifies on-chain that the cited tx exists, its merkle path validates against WH's PoW-verified header store, and one of its outputs pays ≥ the expected amount to the configured `payment_recipient`.

**Deliverables**:

1. **`payment_verifier.zig`** — `verify(beef_bytes, txid_hex, recipient_sec1, expected_satoshis, chain_tracker) → VerifyResult { spv_ok, output_ok, verified, matched_satoshis }`. bsvz parses the BEEF; `bsvz.spv.verifyBeef` walks every merkle path against `chain_tracker`; the cited tx's outputs are scanned for P2PKH or P2PK against the recipient. Mock-trackable in tests (`chain_tracker: anytype`); production wraps `header_store_fs.FsHeaderStore` via `HeaderStoreTracker`.

2. **`payment_verifier_stub.zig`** — same public surface, returns `error.bsvz_unavailable` on every call. The disabled-build path (`-Denable-wasmtime=false`) compiles + tests against this stub so it can't bit-rot.

3. **Auth callback extension** — `payment.beef` is now an optional hex field on the `/auth/callback` JSON body. When present:
   - Server persists raw bytes to `<data-dir>/sites/<domain>/beefs/<txid>.beef` (so a later sweep can re-verify if the header store hadn't caught up at claim time).
   - Server calls `payment_verifier.verify` inline; result appended to `<data-dir>/sites/<domain>/payments.log.verifications`.

4. **`PaymentLedger` join** — `readAll` now joins payments.log against payments.log.verifications by txid (last-write-wins so a previously-pending record can flip true after later sweep). `recordVerification(txid, verified, matched_sats)` writes the line.

5. **`brain sweep <domain>`** — walks the ledger, for each unverified record loads `beefs/<txid>.beef` and re-attempts `payment_verifier.verify` against the current header store. Reports `processed / newly verified / still pending / BEEF missing / failed`. Dedupes by txid.

6. **`brain revenue --verified-only`** — filters the per-route summary to confirmed payments. The existing `brain revenue` output gains a `verification:` block that shows `verified vs pending` totals regardless of the flag.

**What WSITE4.5 deliberately does NOT do** (handled by WSITE4.6):

- **`internalizeAction`** — verified UTXOs flow into the admin's `OutputStore` in WSITE4.6.
- **Double-spend tracking across replay attempts** — the same txid replayed across two routes is deduped at sweep-time (one verification per txid), but a more robust admin-facing diff lives in WSITE5.
- **Source-output ancestry** — `bsvz.spv.verifyBeef` walks the input ancestry inside the BEEF for us; the WSITE-level verifier only asks "did the tx reach the chain + does it pay me?".

**Success criterion**: an end-to-end fixture posts a callback carrying a valid BEEF for a tx that pays the configured recipient; `brain revenue` reports the record as verified. A second fixture posts a BEEF whose merkle path doesn't validate against the test header store; the record stays pending after `brain sweep`. Switching the build to `-Denable-wasmtime=false` keeps the binary compiling + ledger commands working — `brain sweep` reports every record as `failed` rather than crashing.

### WSITE4.6 — Internalize verified UTXOs into the admin's OutputStore (~ 0.5 days) ✅ shipped

**Goal**: the matched output from WSITE4.5's verifier becomes a tracked UTXO the admin's wallet can spend.  Closes the auth → verify → record loop.

**Deliverables**:

1. **Reuse the existing `core/cell-engine/src/output_store.zig`** vtable + `LocalOutputStore`.  The existing surface is already spec'd against WA2 (see `WALLET-ACTIVE-USE-ROADMAP` §2) with full BRC-46 basket + tag support, BEEF retention + pruning, BRC-42 derivation linkage, and snapshot/replay; WSITE4.6 doesn't redefine the abstraction.

2. **`runtime/semantos-brain/src/output_store_fs.zig`** — file-backed implementation conforming to the cell-engine vtable.  Append-only JSON-line event log at `<data-dir>/sites/<domain>/outputs.log`; replay on init reconstructs in-memory state.  Same shape as `payments.log` and `audit.log`.

3. **`payment_verifier.verify` extension** — `VerifyResult` now carries `matched_vout`, `matched_locking_script` (duped via an optional `out_locking_script_allocator`), and `matched_output_satoshis` so callers can take the matched output and write it to the OutputStore without re-walking the BEEF.  First-match-wins: even if a payer pays multiple matching outputs, we record one canonical UTXO per claim.

4. **Inline internalization** in `site_server.verifyPaymentInline` — when verification succeeds, the matched output is written to the per-site OutputStore.  The auth callback's BRC-100 pubkey is recorded as the `derivation_counterparty` field even though v0.1 doesn't yet derive per-payer leaves (per-route BRC-29 derivation contexts land in WSITE5).

5. **Sweep internalization** in `brain sweep` — when a previously-pending record sweeps to verified, its matched output is internalized the same way.  Re-internalizing the same outpoint is idempotent (`addOutput` returns `duplicate_outpoint` and the call site swallows it).

6. **`brain outputs <domain> [--basket NAME] [--include-spent]`** — list spendable UTXOs the admin's wallet owns.  Renders outpoint, satoshis, basket, route — enough for spot-checking that internalization fires on real verified payments.  v0.1 lists only `.unspent` records (vtable surface gates on status); WSITE5 admin REPL adds the all-status surface.

**What WSITE4.6 deliberately does NOT do**:

- **Spend the UTXOs** — `createAction` from the wallet-engine surface lands in WSITE5, alongside refunds and admin-initiated transfers.
- **BRC-29 derivation per payer** — site recipients are static SEC1 keys from `site.json` at v0.1.  Routes that opt into per-payer derivation (lower correlation across payments) populate the BRC-42 derivation fields properly in WSITE5.
- **Confirmation tracking** — `confirmations: 0` at internalize; the WSITE5 sweep flow advances this as the chain progresses (and triggers `prune_confirmed` once thresholds are met).

**Success criterion**: an end-to-end fixture posts a callback that verifies via WSITE4.5; `brain outputs <domain>` shows the matched UTXO with the correct satoshis + locking script.  A second `brain sweep <domain>` is a no-op (`duplicate_outpoint` is swallowed; the output count is unchanged).  Switching the build to `-Denable-wasmtime=false` keeps `brain outputs` working — it just lists nothing because `verifyPaymentInline` short-circuits before the script walk.

### WSITE5 — Admin surface: sessions, refunds, output baskets (~ 1 day) ✅ shipped (v0.1 scope)

**Goal**: wrap WSITE4.6 with the operator-facing pieces the v0.1 sovereign-node deployment needs — durable session tracking, refund accounting, per-route revenue baskets — without yet requiring the wallet-engine `createAction` flow.  WSITE5 is intentionally CLI-only; richer REPL wiring + interactive site management lands in WSITE5.5.

**Shipped at WSITE5 v0.1**:

1. **Durable sessions** — `SessionStore.init` now replays its append-only log so sessions survive `brain serve` restarts.  Closes the WSITE3 deferred TODO ("v0.2 swaps to lmdb-backed store" → for v0.1 the file-backed log is enough).  Revoke events get their own log line so a revoked session stays revoked across restarts even if its cookie hasn't hit TTL yet.  Replay is clock-agnostic: `lookupSession` already gates on `clock_fn()` at access time, so replay loads everything and access-time filtering handles expiry — avoids a race with tests that pin the clock after init.

2. **`brain sessions <domain> [--all]`** — list active sessions (`id-prefix`, `pk-prefix`, ttl, return_to).  **`brain sessions revoke <domain> <session_id_hex>`** invalidates a session immediately; the revoke event hits the log so subsequent processes see the removal.

3. **Refund-intent ledger** — `<data-dir>/sites/<domain>/payments.log.refunds` records one line per refund event: `{"ts":N,"txid":"<hex>","sats":N,"reason":"..."}`.  The shape mirrors the WSITE4.5 verifications log (last-write-wins on (txid → reason)).  `PaymentLedger.readAllJoined` folds refunds in alongside verifications; `PaymentRecord.refunded` + `refund_reason` reflect the join.  The legacy `readAll` skips the refund file to keep callers that don't care cheap.

4. **`brain refund <domain> <txid> [--reason TEXT]`** — looks up the txid in the payment ledger to confirm it exists, appends to the refund log, and marks every matching `OutputStore` UTXO spent with a sentinel `0xFF…FF` spending_txid (so `brain outputs` stops listing it as spendable).  Real refund-tx construction + broadcast is WSITE5.5 work — the operator builds + signs the refund manually until then.

5. **Per-route `output_basket`** — sites can declare `"output_basket": "premium-revenue"` per route in `site.json`.  Both inline `verifyPaymentInline` and `cmdSweep` route the internalized output into that basket.  `brain outputs <domain> --basket NAME` filters by basket.  Empty falls through to `"default"` (preserving WSITE4.6 behaviour).

6. **`brain revenue` refund breakdown** — when refunds are present, the dashboard shows a `refunds:` block: `refunded count / sats` and a `net = total − refunded` line.  Steady-state revenue dashboards (no refunds yet) stay quiet.

**What WSITE5 deliberately does NOT do**:

- **Refund tx construction + broadcast** — needs the wallet-engine `createAction` surface wired into the broker.  WSITE5.5.
- **Per-route revenue caps** (`route.daily_max_satoshis`) — WSITE5.5.
- **Webhooks on payment** — WSITE5.5.
- **REPL wiring** of `revenue/outputs/sessions/refund/sweep` — would duplicate substantial logic in `repl.zig`.  Operators wanting interactive site management run a sub-shell instead.  May land in Brain 3.5 if there's demand.
- **BRC-52 identity certs + trusted-issuer matching** — WSITE3.5.

**Success criterion**: an end-to-end fixture mints a session, restarts the process, and lookupSession still resolves it.  `brain sessions revoke` kills it; a third process start still sees the revoke.  `brain refund` records intent + marks the OutputStore record spent; `brain outputs` no longer lists it; `brain revenue` shows the refund in the breakdown block.  Routes with `"output_basket": "x"` route their internalized UTXOs into basket `x`.

### WSITE5.5 — Refund tx construction + ARC broadcast (~ 1 day) ✅ shipped (v0.1 scope)

**Goal**: complete WSITE5's deferred refund work.  `brain refund` upgrades from intent-only logging to actual transaction construction + signing + ARC broadcast.

**Shipped at WSITE5.5 v0.1**:

1. **`signing_key_wif` in `site.json`** — new optional field.  Operator declares their WIF-encoded signing key; commands that need it surface a clear "set signing_key_wif in site.json" hint when missing.  v0.1 trade-off: plaintext on disk; v0.2 encrypts at rest under a passphrase set at boot; v0.3 hands signing to the wallet-engine WASM module's tier-key custody flow so the key never leaves the WASM sandbox.

2. **`runtime/semantos-brain/src/refund_tx.zig`** — bsvz-backed refund-tx constructor.  Decodes WIF → `PrivateKey`, derives the payer's P2PKH address from the compressed SEC1 pubkey (recorded in WSITE4.6's `OutputRecord.derivation_counterparty`), builds a 1-input → 1-output transaction via `bsvz.transaction.Builder`, applies a sats/KB fee model via `applyFee(.equal)`, signs with `signAllP2pkh`, and serializes.  Same gating + stub mirror pattern as WSITE4.5's `payment_verifier`.

3. **ARC broadcast** — `broadcastViaArc(allocator, raw_tx, arc_url, api_key)` parses the raw bytes back via `bsvz.transaction.Transaction.parse` (Arc takes `*Transaction`, not bytes), POSTs to ARC, returns `BroadcastOutcome { ok, detail }` — `detail` is the broadcast txid on success or the ARC error code on failure.  Default endpoint: Taal's free public ARC at `https://arc.taal.com/v1/tx`; per-domain override lands in WSITE5.6.

4. **`brain refund` upgrade** — for each matching `OutputStore` UTXO, attempts broadcast when `signing_key_wif` is set:
   - Success → marks the UTXO spent with the *real* refund tx's id (instead of the WSITE5 sentinel `0xFF…FF`) so `brain outputs` stops listing it AND the spend chain is auditable.
   - Failure → falls back to the sentinel + logs the ARC error with the failing reason.
   - Either way the refund-intent record is appended to `payments.log.refunds` (WSITE5's audit trail intact).
   - When `signing_key_wif` is empty: behaviour stays exactly as WSITE5 (intent-only, sentinel spending_txid, no broadcast attempt).

**What WSITE5.5 deliberately does NOT ship** (deferred to WSITE5.6+):

- **Webhooks on payment** — `route.on_payment.url` POST after a payment records.
- **Per-route revenue caps** (`route.daily_max_satoshis`) — needs in-memory rate-tracking.
- **`brain send <domain>`** admin-initiated send — same broadcast path as refund, just with an arbitrary recipient.  Trivial port of the refund flow.
- **Encrypted-at-rest signing key** — operator's plaintext WIF in `site.json` is the v0.1 trust trade-off.
- **Wallet-engine-mediated signing** — long-term goal: signing key lives inside the wallet-engine WASM module's tier-key custody, with `brain refund` calling `host_sign` through the broker.  Lands when the broker's WSITE-side surface gets fleshed out.
- **Per-route output_basket-aware refunds** — refund currently consumes any matching outpoint; basket-scoped refunds (e.g., "refund only from the `premium-revenue` basket") wait for an admin-spend story.

**Success criterion**: an end-to-end fixture loads a site config with `signing_key_wif` set + a verified payment + an OutputStore record with `derivation_counterparty` populated.  `brain refund <domain> <txid>` reports `refund-tx broadcast → ok (detail=<txid>)` against ARC; subsequent `brain outputs` no longer lists the UTXO; `brain revenue` reflects the refund in its breakdown block.  Switching to `-Denable-wasmtime=false` falls back to WSITE5 intent-only behaviour cleanly.

### WSITE5.6 — Webhooks + revenue caps + admin send (~ 1 day, planned)

**Goal**: complete the rest of WSITE5's deferred operator-facing work that fell out of WSITE5.5's scope.

**Deliverables**:

1. New REPL commands (extend Brain 3's command set):
   ```
   site list                                  list configured sites
   site init <domain> --content <path>       scaffold a new site
   site config <domain>                       show current config
   site reload <domain>                       apply config changes
   site validate <domain>                     check config
   site remove <domain>                       take down a site
   
   route add /<path> <type> [options]        add a route
   route remove /<path>
   route list
   
   revenue [--since <duration>] [--site <d>] [--by-route|--by-payer]
   refund <session_id>
   sessions [--site <d>] [--active|--all]
   sessions revoke <session_id>
   
   webhook add <url> --on <event>
   webhook test <url>
   ```

2. Tab completion — domain names, route paths, session IDs all auto-complete from current state.

3. Bulk operations — `route add /api/v1/* --auth identity_required` accepts wildcards.

4. Audit trail — every site config mutation signed by admin's identity key, recorded as a Semantos cell, broadcast on-chain (low fee, OP_RETURN). Tamper-evident operational history.

**Success criterion**: admin can run `site init pokerapp.example.com --content ./public`, edit `site.toml`, run `site reload`, run `route add /vip --auth identity_required`, all via REPL. Each mutation produces a signed config cell.

### WSITE6 — End-user wallet hosting (optional advanced, ~ 2 days)

**Goal**: the site can offer to host wallets for its users — useful for sites that want a turnkey "no-install wallet" experience and whose users explicitly trust the operator.

**Deliverables**:

1. Per-user storage scoping in lmdb: `~/.semantos/sites/<domain>/users/<user_id>/`. Each user's wallet state (slot store, derivation state, output store, header store reference) scoped by user ID.

2. Per-user encryption: the site offers a wallet, but the user's keys are encrypted under their challenge-derived KEK (same v0.4 mechanism). The site operator cannot decrypt — only the user with their challenge answers can. Confirms the v0.4 trust model: site is custody of *encrypted blobs*, not custody of keys.

3. Per-user WSS endpoint: `wss://<domain>/wallet?user=<user_id>`. Authenticates via the user's session token. The shell loads the user's encrypted state, exposes a wallet API as if the user were running their own node.

4. Operator opt-in — `site.toml`:
   ```toml
   [site.wallet_hosting]
   enabled = false                          # default OFF
   max_users = 1000
   per_user_storage_quota = "10MB"
   pricing = "free"                          # or "tiered" or "subscription"
   ```

5. **Trust model UX surface**: when a user creates a wallet at a site that hosts wallets, the wallet origin (or the site's onboarding flow) makes it explicit:
   ```
   Where should your wallet live?
   
   ○ wallet.semantos.app   (operated by Semantos team — default, recommended)
   ● this site's server    (operated by pokerapp.example.com — you trust them)
   ○ your own VPS          (advanced — you self-host)
   
   ⓘ All three options use the same wallet code (hash-pinned).
     Your keys are encrypted under your challenge answers — even
     this site's operator cannot decrypt them. The choice is
     about *availability* and *uptime*, not key security.
   ```

6. Per-user SetupStatus, audit log, REPL access — all scoped per user. Site admin sees user counts and storage usage but not individual user state.

**Success criterion**: feature opt-in, end-user wallet creation flows through site's hosted endpoint, user's encrypted blobs persist on the node, user can recover their wallet on a different device by exporting their dispatch envelope. Site operator cannot extract the user's keys (verified by attempting to decrypt the user's blobs and observing failure without challenge answers).

---

## 4. Concrete Site Config Example

A complete `site.toml` for a hypothetical "Read articles, optionally pay for premium" site:

```toml
[site]
domain = "writes.example.com"
content_root = "./public"
admin_identity = "02a3b7...8f4c"
admin_email = "todd@example.com"
config_version = 3
config_signature = "30440220..."

[site.tls]
mode = "caddy"                                # or "builtin" or "none"

[site.wallet_hosting]
enabled = false

[routes."/"]
type = "static"
file = "index.html"

[routes."/articles/free/*"]
type = "static"
public = true

[routes."/articles/premium/*"]
type = "static"
auth = "payment_required"
price_sats = 1000
session_ttl = "24h"
payment_recipient = "default"

[routes."/comment"]
type = "dynamic"
handler = "comment.wasm"
auth = "identity_required"
rate_limit = "10/hour"
identity_issuers = ["*"]

[routes."/admin/*"]
type = "static"
auth = "identity_required"
identity_issuers = ["self"]                   # only the admin's own identity

[on_payment]
webhook = "https://my-analytics.example.com/payments"
webhook_auth = { type = "Bearer", token = "..." }
```

Site admin runs `semantos site reload writes.example.com` and the new config takes effect within milliseconds. Mutations beyond a configurable threshold (e.g., changes to `admin_identity`) require an extra confirmation step (Tier 2 biometric on the admin's wallet).

---

## 5. The Auth Protocol in Detail

### 5.1 Identity-cert auth (no payment)

**Server → client:**
```http
HTTP/1.1 401 Unauthorized
X-Semantos-Challenge-Version: 1
X-Semantos-Challenge-Type: identity_auth
X-Semantos-Nonce: q7H9aK2pXr8mN3vL5jZ1cT4eW6yU0iS=
X-Semantos-Expected-Issuers: writes.example.com,*
X-Semantos-Wallet-Origin-Hint: https://wallet.semantos.app
X-Semantos-Return-To: /articles/premium/x
Set-Cookie: __semantos_challenge=q7H9aK...=; HttpOnly; Secure; SameSite=Lax; Path=/auth
Content-Type: text/html
Content-Length: ...

<html><body>
  <h1>Sign in to read</h1>
  <a href="https://wallet.semantos.app/connect?dapp=writes.example.com&...">
    Sign in with Semantos
  </a>
</body></html>
```

**Wallet origin → client:**

Wallet completes the BRC-100 flow, redirects back to `https://writes.example.com/auth/callback?…` with the cert and signature.

**Client → server:**
```http
POST /auth/callback HTTP/1.1
Cookie: __semantos_challenge=q7H9aK...=
Content-Type: application/json

{
  "identityCert": "AQID...",
  "signature": "MEQCIA...",
  "returnTo": "/articles/premium/x"
}
```

**Server verification:**
1. Read `__semantos_challenge` cookie — get expected nonce.
2. Verify `signature` is valid ECDSA over the nonce, signed by the cert's pubkey.
3. Verify cert against `Expected-Issuers` — issuer signature, not revoked, not expired.
4. Issue session JWT: `{ identity: cert.subject_pubkey, expires: now + ttl, paid_for: null }`, signed by admin's identity key.
5. Clear challenge cookie, set session cookie, redirect to `Return-To`.

### 5.2 Payment-required auth

Same flow but with extra fields:

**Server → client:**
```http
HTTP/1.1 402 Payment Required
X-Semantos-Challenge-Version: 1
X-Semantos-Challenge-Type: payment
X-Semantos-Nonce: ...
X-Semantos-Price-Sats: 1000
X-Semantos-Recipient: 02a3b7...8f4c
X-Semantos-Recipient-Derivation: BRC29:protocol=writes,counterparty=02a3b7...,prefix=q7H9...
X-Semantos-Return-To: /articles/premium/x
Set-Cookie: __semantos_challenge=...; HttpOnly; Secure
Content-Type: text/html
```

**Client callback:**
```json
{
  "identityCert": "...",
  "signature": "...",
  "paymentBeef": "0100BEEF...",
  "returnTo": "/articles/premium/x"
}
```

**Server verification (additional steps):**
1. Verify the BEEF via the admin's wallet's `internalizeAction`.
2. Confirm one of the BEEF's outputs pays ≥ 1000 sats to the `Recipient-Derivation` address.
3. Add the UTXO to admin's OutputStore.
4. JWT now includes `paid_for: "/articles/premium/x"` so subsequent requests skip re-payment for the path the user already bought.

---

## 6. Dependency Graph

```
 BRAIN (foundation)
      │
      ▼
 WSITE1 (site config schema) ──┬─► WSITE2 (content serving) ──┐
                                │                                │
                                ▼                                ▼
                          WSITE3 (auth + 402 + cert) ──► WSITE4 (payment receiver)
                                │                                │
                                ▼                                ▼
                          WSITE5 (admin REPL commands) ──► WSITE6 (end-user wallet hosting, optional)
```

WSITE1 is foundational. WSITE2 + WSITE3 + WSITE4 are the core auth + payment flow. WSITE5 is admin UX. WSITE6 is opt-in advanced.

---

## 7. Sizing

| Phase | Effort | Risk |
|---|---|---|
| WSITE1 — Site config schema | 1 day | Low — TOML parsing, signature scheme already exists |
| WSITE2 — Content serving | 2 days | Medium — Zig HTTP server tuning, dynamic-handler isolation |
| WSITE3 — Auth + 402 protocol | 2 days | Medium — JWT + cookie + challenge state machine |
| WSITE4 — Payment receiver | 1.5 days | Medium — BEEF validation already exists; new code is the linkage to sessions |
| WSITE5 — Admin REPL | 1 day | Low — extends Brain 3 |
| WSITE6 — End-user wallet hosting (optional) | 2 days | Medium — per-user scoping, isolation, trust-model UX |

**Total**: ~7-8 days for core (skipping WSITE6), ~9-10 days with WSITE6.

---

## 8. Commit Boundary Plan

1. `feat(shell): WSITE1 — site config schema + signed config cells`
2. `feat(shell): WSITE2 — static + dynamic content serving with WASM handler isolation`
3. `feat(shell): WSITE3 — HTTP 402 + identity-cert challenge protocol + sessions`
4. `feat(shell): WSITE4 — payment receiver + revenue accounting + refund flow`
5. `feat(shell): WSITE5 — admin REPL commands for site operations`
6. `feat(shell): WSITE6 — optional end-user wallet hosting (opt-in)`

---

## 9. Acceptance Criteria

WSITE is done when:

1. `semantos site init writes.example.com --content ./public` scaffolds a working site config.
2. `curl https://writes.example.com/articles/free/x.html` returns the content (public route).
3. `curl https://writes.example.com/articles/premium/x.html` returns 402 with full challenge headers.
4. End-to-end auth test: a test wallet client completes the BRC-100 flow, posts to `/auth/callback`, receives a session cookie, accesses the gated route.
5. End-to-end payment test: a test client pays the required sats, BEEF is internalized into the admin's wallet, session granted, route accessed.
6. `revenue` REPL command correctly accounts payments per route and per payer.
7. Site config mutations require admin's identity-key signature + Tier 2 factor for sensitive changes (admin_identity rotation).
8. End-user wallet hosting (if enabled) correctly isolates per-user state; admin cannot extract user keys (verified by failure to decrypt without challenge answers).
9. Bundle / footprint: WSITE adds <2MB to the shell binary; no significant memory regression.
10. Documentation: end-to-end "deploy a paid blog in 30 minutes" walkthrough in `deploy/README.md`.

---

## 10. What WSITE Does Not Cover

- **Server-side rendering frameworks** (React-SSR, Next.js-style) — out of scope. WSITE serves static content + WASM dynamic handlers. Rich SSR can come later as a separate workstream if there's demand.
- **Database integration** beyond lmdb — out of scope. WSITE's storage is the shell's lmdb. SQL / Postgres / etc. is application-layer; can be implemented in a dynamic handler that connects out.
- **Multi-region failover / load balancing** — out of scope. One node, one VPS, one operator. Multi-region is a separate ops concern (DNS-level failover, replication via the future WF federation workstream).
- **Email sending / SMS / external messaging** — application-layer, out of scope. Webhooks (WSITE4) are the integration point for external services.
- **CDN integration** — operators wanting a CDN can put one in front of the node. WSITE's caching headers + ETags make this work cleanly.
- **Custom TLS termination beyond Caddy + builtin** — operators wanting Cloudflare / nginx / HAProxy in front are free to do it; WSITE's contract is "binds to a port and serves HTTP"; what fronts it is the operator's choice.
- **Visual site builder** — out of scope. WSITE is config-first; a graphical site builder is a separate workstream.

---

## 11. Inaugural Deployment — `oddjobtodd.info`

`oddjobtodd.info` is the canonical first WSITE deployment. It is an operating
handyman business (Sunshine Coast, Noosa-area service radius); it has live customer
SMS traffic via Twilio; it has a Next.js admin panel; it has 10 Drizzle migrations
of Postgres schema; its Anthropic-driven intake bot runs the system prompt at
`oddjobtodd/src/lib/ai/prompts/systemPrompt.ts`. It is also the production embodiment
of the textbook's running worked example — handyman intake → property-management
lexicon → cross-vertical dispatch — meaning every chapter from 2 through 29 has the
OJT cutover as its concrete reference. Naming OJT here forces WSITE phases to clear
a bar more demanding than "passes integration tests": each phase must continue to
leave OJT online, signing, taking SMS, and serving its admin panel, throughout the
cutover.

### 11.1 Current dual-deployment posture

OJT today runs in two places:

| Deployment | Stack | Role | Limitation |
|---|---|---|---|
| `oddjobtodd.info` (VPS) | Next.js + Postgres + Twilio + Anthropic, on a small Hetzner-class box | Production — receives customer SMS, runs the intake conversation, persists leads | No admin panel exposed; operator manages from the Vercel deployment |
| `*.vercel.app` (Vercel preview) | Same Next.js codebase, separate Postgres | Prototype — full admin panel (`/admin/leads`, `/admin/calendar`, `/admin/chat`, `/admin/import-job`) gated by Firebase auth | Not authoritative; data may be stale relative to VPS |

This split is the legacy of "ship the intake bot first, figure out admin later."
It is the first thing WSITE collapses.

The Postgres schema on the VPS may have drifted from the Drizzle migrations declared
in `oddjobtodd/drizzle/0000_military_supernaut.sql` through `0009_pale_loki.sql`;
confirming that drift is a one-hour audit (`pg_dump --schema-only` on both, diff
the result, decide which migration is canonical) and is a prerequisite to WSITE2's
content cutover, not to WSITE1's config schema.

### 11.2 The admin panel is v0 of Helm-as-tradie-portal

Of the four routes that ship in the Vercel preview, three are direct ancestors of
the convergence-surface panels in the textbook's chapter 18:

| Vercel admin route | Helm panel role | WSITE wire-up |
|---|---|---|
| `/admin/leads` + `/admin/leads/[id]` | Centre-panel work surface (the kanban / leads vertical) | Static page + a WASM dynamic handler that calls the substrate VFS |
| `/admin/chat` | Centre-panel signed-action bar with chat over the operator's own objects (cf. VOICE-SHELL-GRAMMAR doc) | Dynamic handler bridging to `runtime/shell/src/chat/` and the BRAIN REPL |
| `/admin/calendar` | Centre-panel calendar (also an attention-feed input — overdue jobs, weather-exposed slots) | Static page + dynamic handler against the calendar extension's `HatPayload` / `HatRecord` |
| `/admin/import-job` | Operator-driven seed-cell creator (the "create a job manually" affordance) | Dynamic handler producing signed cells via the BRAIN wallet |

What's *missing* from the Vercel admin and lands as part of WSITE for OJT:
the right-panel evidence/attention/capability stack from chapter 18. That arrives
as substrate cells become the source of truth (cf. §11.3 below). Not all of the
right panel is a WSITE concern — the attention-ranking model is an operator-side
inference component that runs inside BRAIN and renders into Helm — but the rendering
surface itself is a WSITE-served page.

### 11.3 Migration sequencing

The cutover runs in five phases over WSITE1–WSITE5, with the legacy-ingest
workstream (`docs/design/WALLET-LEGACY-INGEST.md`) running in parallel from
phase 2 onward:

1. **Phase 0 — schema audit.** `pg_dump --schema-only` against both Vercel and
   VPS Postgres; reconcile against the Drizzle migration log; declare the
   canonical schema. (Half a day.) Outcome: one Postgres schema; both
   deployments use the same migration set.
2. **Phase 1 — WSITE1 on the VPS, no traffic shift.** Author the initial
   `site.toml` declaring the existing Next.js routes as `type = "static"`
   passthrough (Caddy → Next.js binary unchanged). The site-config cell is
   signed by the operator's BRAIN-resident wallet. No customer-visible change.
3. **Phase 2 — WSITE2 + WSITE3, admin routes only.** Reproduce the four admin
   pages as WSITE-served routes (`type = "dynamic"`, dynamic handlers calling
   substrate VFS). Gate them with `auth = "identity_required"` +
   `identity_issuers = ["self"]`. Operator does the BRC-100 redirect once on
   his phone (cf. MOBILE-AUTH-FLOW §3) and the admin panel is now exposed on
   the VPS, gated by his own wallet, accessible from any device. Vercel preview
   stays online during this phase as a fallback.
4. **Phase 3 — substrate cutover for state-mutating routes.** Customer-facing
   intake (`/api/chat`, `/api/v2/messages`, `/api/v3/chat`) is rewired so the
   write path is: SIR build → cell pack → host_persist via BRAIN broker, then
   Postgres write happens as a denormalized projection. Postgres becomes a
   read-cache; cells become source of truth. Reads still serve from Postgres
   for performance; writes are a fan-out from the cell mutation. (This is the
   workstream where the legacy-ingest doc's ratification queue becomes
   load-bearing — operator confirms each migrated cell.)
5. **Phase 4 — WSITE4 payment receiver wired.** Open BRC-29 payment-required
   routes for paid features (priority booking, after-hours callout, ROM-as-
   binding-quote upgrades). Site admin's wallet receives the payments; revenue
   accounting visible in REPL via `revenue` (cf. WSITE5).
6. **Phase 5 — Vercel deprecation.** With every admin route on WSITE and every
   state mutation producing a substrate cell, the Vercel deployment is shut
   down. DNS still points at the VPS IP; the Zig binary is what's serving
   every byte. The Firebase project is closed. The seven external dependencies
   from before the migration (Vercel, Firebase, Postgres-as-source-of-truth,
   Upstash, Anthropic, Twilio, Vercel Blob) collapse to two retained as
   utility services (Anthropic for the intake LLM, Twilio for the SMS bearer)
   plus the substrate. Postgres remains as a read-cache.

The migration is reversible at every phase up to phase 5: the `site.toml` can
declare any individual route back to `type = "static" passthrough` and Caddy can
route around any WSITE problem until BRAIN's first incident-postmortem is past.

### 11.4 What this means for WSITE itself

Two refinements to the §3 phases that the OJT-as-test-bed framing demands:

- **WSITE2's dynamic-handler isolation policy** must permit a handler to call
  out to Twilio (for outbound SMS) and to Anthropic (for the intake-bot LLM),
  not just to the local cell-engine and broker. The host-import broker (Brain 2)
  exposes a scoped network surface — handlers declare which outbound hosts
  they need in their handler manifest, the operator approves the manifest at
  load time. OJT's intake handler declares `api.twilio.com` and
  `api.anthropic.com`; the broker enforces the allowlist. Other handlers
  cannot reach those hosts.
- **WSITE5's REPL commands** include OJT-specific verbs that mirror the
  existing admin panel actions: `lead list`, `lead claim <id>`,
  `lead close <id> --outcome <will_quote|need_inspection|decline>`,
  `calendar slot <day> <time> --customer <name>`. These are the same
  operator gestures the Next.js admin panel offers; exposing them in the REPL
  + WSS makes them voice-driven via VOICE-SHELL-GRAMMAR.

The cross-vertical dispatch envelope pattern (paper C4) becomes load-bearing
for OJT in phase 6+ — the moment the operator dispatches an envelope to a
trades sub-contractor (an electrician, a plumber, a roofer). That is out of
scope for the WSITE cutover but is the natural next workstream once WSITE is
shipped.

---

## 12. Cross-references

- `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` — BRAIN provides the runtime
- `docs/design/WALLET-TIER-CUSTODY.md` — admin's wallet uses the v0.4 architecture
- `docs/design/WALLET-ACTIVE-USE-ROADMAP.md` — internalizeAction (WA2) is what WSITE4 calls
- `docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md` — WH validates BEEFs WSITE4 receives
- `docs/design/WALLET-MOBILE-AUTH-FLOW.md` — mobile UX for the cross-origin auth flow
- `docs/design/WALLET-LEGACY-INGEST.md` — populates the substrate's cell store from Gmail / Meta / WhatsApp / Google Calendar / Xero so phase-3 cutover has historical state to converge on
- `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md` — operator's mic-driven `do | find | talk` UX surfaces over WSITE-served admin pages
- `oddjobtodd/src/app/admin/` — the four Next.js admin routes that become WSITE dynamic handlers in phase 2
- `oddjobtodd/src/lib/ai/prompts/systemPrompt.ts` — the intake bot system prompt; the conversation contract is preserved verbatim during the cutover
- `oddjobtodd/drizzle/0000_military_supernaut.sql`–`0009_pale_loki.sql` — Drizzle migration log used for phase-0 schema audit
- `oddjobtodd/systemd/semantos-ojt.service` — existing systemd unit on the VPS; lives alongside the new BRAIN unit during cutover
- `docs/canon/examples/pm-tradie-dispatch.md` — canonical worked example (paper C4) for the cross-vertical dispatch envelope pattern that lands after WSITE
- BRC-29 (payment derivation) — WSITE4 receives BRC-29 payments
- BRC-52 (identity certs) — WSITE3 verifies certs against trusted issuers
- BRC-100 (wallet wire protocol) — admin's wallet exposes BRC-100 over WSS
- Caddy + Let's Encrypt — default TLS termination
