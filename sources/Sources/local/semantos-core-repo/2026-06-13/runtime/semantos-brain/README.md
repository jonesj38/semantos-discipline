---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.027667+00:00
---

# brain — Sovereign-node host shell

Phases **Brain 1 + Brain 2 + Brain 2.5 + Brain 2.6 + Brain 2.7 + Brain 3 + WSITE1–WSITE5.5 + WH-Producer phases 1+2** — hash-pinned WASM module discovery, file-backed storage stack, host-import broker with module-isolation policy + audit log, live wasmtime instantiation, full host-import surface for `cell-engine-embedded.wasm`, real secp256k1 signing + BRC-42 derivation via bsvz, interactive REPL, site-as-sovereign-node HTTP server, identity-required auth gates, payment-required auth gates (HTTP 402 challenge → signed payment claim → revenue ledger), on-chain SPV verification of cited payment txids via WH's PoW-verified header store, internalization of verified UTXOs into the admin's per-site OutputStore, the WSITE5 admin surface (durable sessions, per-route output baskets, refund intent ledger, refund-aware revenue dashboard), dynamic-route WASM-handler dispatch (WSITE2.5), Zig-native BSV P2P header sync (`brain headers sync`), long-running BHS-compatible HTTP server (`brain headers serve`), **and `brain refund` upgraded from intent-only to actual refund-tx construction + ARC broadcast (WSITE5.5)**.

Reference: [`docs/design/WALLET-SHELL-VPS-SUBSTRATE.md`](../../docs/design/WALLET-SHELL-VPS-SUBSTRATE.md) §3.

## What's shipping

**Brain 1** — trust-anchor enforcement + lifecycle CLI:

- Native Zig binary (`zig build` → `zig-out/bin/brain`) with subcommands:
  - `brain init [--config-path <path>]` — write a default config file
  - `brain status [--config-path <path>]` — verify each module's hash against its file
  - `brain hash <wasm_file>` — print SHA-256 to paste into config
  - `brain start [--config-path <path>]` — load + verify every module, stand up the broker + stores + audit log
  - `brain stop` — stub (Brain 2.5 adds the daemon-PID-file dance)
  - `brain help` / `brain version`
- `module_loader.zig` — SHA-256 + WASM-magic verification, refuses on mismatch.
- `instance_manager.zig` — `LOADED → RUNNING → STOPPED / CRASHED → restart()` FSM with chronic-failure counters.

**Brain 2** — host broker + storage stack + audit log:

- `audit_log.zig` — append-only JSON audit log at `<data-dir>/audit.log`. One line per host-import call: `{ts, module, op, result, detail}`. `tail -f` on this is the operator's main visibility surface for what each module is doing.
- `slot_store_fs.zig`, `state_store_fs.zig`, `header_store_fs.zig` — file-backed implementations of cell-engine's `SlotStore`, `DerivationStateStore`, `HeaderStore` vtables. Same vtable surface as the in-memory `Local*` impls; same vtable surface a future lmdb backing would expose. Atomic writes via tmp-then-rename or append-only with on-load consistency checks.
- `broker.zig` — central dispatcher. Every WASM-module-originated host call routes through here. Two enforcement axes:
  1. **Module-isolation policy** — wallet engine forbidden from `host_append_validated_header`; headers verifier forbidden from `host_sign` / `host_state_next_index`. Violations return `policy_denied` and emit a `denied` audit-log entry.
  2. **Audit** — every dispatch emits one structured line.
- `brain start` constructs the full pipeline: file-backed stores, audit log opened, broker bound. Reports ready before reaching the wasmtime hand-off (deferred to Brain 2.5).

**Brain 2.5** — wasmtime instantiation (opt-in via `-Denable-wasmtime=true`):

- `runner.zig` — public API: `Runner.init`, `Runner.instantiate(loaded, module_kind)`. Returns an opaque `Instance`. Compile-time dispatch on `build_options.enable_wasmtime`:
  - **Stub mode (default)** — every call returns `error.wasmtime_not_enabled`. Lets the binary build + ship without wasmtime installed; the disabled-build path is conformance-tested so it doesn't bit-rot.
  - **Real mode** (`-Denable-wasmtime=true`) — links `libwasmtime` (Homebrew on macOS at `/opt/homebrew`, `/usr/local` elsewhere; override with `-Dwasmtime-prefix=…`). Compiles modules, instantiates with host imports satisfied, looks up exported `memory`.
- `wasmtime_runner_real.zig` — wraps the wasmtime C API (`@cImport(@cInclude("wasmtime.h"))`). Engine + linker + store lifecycle. Three host-import callbacks shipped today: `host_log`, `host_persist_cell`, `host_load_cell`. Each decodes `(ptr, len)` WASM args into Zig slices over the instance's exported memory and forwards to `Broker.host*`. The remaining imports (`host_sign`, `host_derive_leaf`, `host_state_next_index`, etc.) follow the same pattern; landing them is mechanical once `bsvz` crypto + the BRC-42 derivation backings are wired.
- `wasmtime_runner_stub.zig` — empty-shape backend the disabled build links against. Same public surface, returns errors everywhere.
- `brain start` (real mode) prints `✓ instantiated wallet-engine as wallet_engine` for each module that successfully links its host imports. Modules with unresolved host imports report `✗ instantiate failed (instance_link_failed)` so the operator sees the gap.

End-to-end conformance: a minimal WAT fixture (compiled in-process via `wasmtime_wat2wasm`) imports `host.host_persist_cell`, exports `memory` + a `run` function. The test instantiates it, invokes `run` (which calls `host_persist_cell(7, ptr, 4)`), and asserts the broker stored "data" at slot 7 in the local slot store. Real wasmtime, real callback shim, real broker, real store.

**Brain 2.6** — full host-import surface for `cell-engine-embedded.wasm`:

The embedded cell-engine WASM imports 9 host functions (verified by parsing the import section of `cell-engine-embedded.wasm`). Brain 2.6 wires every one of them so `brain start` can fully instantiate the wallet engine + headers verifier:

| Host import | Implementation |
|---|---|
| `host_sha256(ptr, len, out)` | `std.crypto.hash.sha2.Sha256` |
| `host_sha1(ptr, len, out)` | `std.crypto.hash.Sha1` |
| `host_ripemd160(ptr, len, out)` | `core/cell-engine/src/ripemd160.zig` (pure-Zig) |
| `host_hash160(ptr, len, out)` | sha256 then ripemd160 |
| `host_hash256(ptr, len, out)` | sha256 of sha256 |
| `host_get_blocktime() -> u32` | `std.time.timestamp()` truncated to u32 |
| `host_get_sequence() -> u32` | `0` (no tx context bound at runtime; matches engine's `g_tx_ctx` initial state) |
| `host_call_by_name(ptr, len) -> u32` | stub returning `0xFFFFFFFF` (unknown function, the engine's documented sentinel); audit-logs `err: stub` |
| `host_fetch_cell(octave, slot, offset, out) -> u32` | stub returning `0` (failure); audit-logs `err: stub` |
| `host_sign(...) -> u32` | stub returning `0` — needs secp256k1, deferred to Brain 2.7 |
| `host_checksig(...) -> u32` | stub returning `0` — same |

Stateless cryptographic primitives (the 5 hash callbacks) bypass the broker's audit log: the engine calls them thousands of times per signing operation, and audit-logging every invocation would just be noise without policy value. Stubbed advanced calls (`host_call_by_name`, `host_fetch_cell`, `host_sign`, `host_checksig`) DO go through the audit log so an operator can see what's been called.

Per-instance linker: Brain 2.5 had a single shared linker on the engine; Brain 2.6 builds a fresh linker per instance so each module gets its own `CallbackEnv` with the correct `module_kind` for the broker policy gate. Required because wasmtime forbids redefining the same import twice on one linker.

End-to-end:

```
$ brain start --config-path /tmp/cfg.json
verified module: wallet-engine (36080 bytes)
verified module: headers-verifier (36080 bytes)

broker:           ready (data_dir=/tmp/data)
audit log:        /tmp/data/audit.log
modules loaded:   2
header store tip: empty

wasmtime:         enabled — instantiating modules
  ✓ instantiated wallet-engine as wallet_engine
  ✓ instantiated headers-verifier as headers_verifier

All modules instantiated.  REPL surface lands in Brain 3.
```

**Brain 2.7** — real crypto via bsvz:

bsvz (the same Zig dep `core/cell-engine/` and `runtime/node/` use) is now linked into the wasmtime backend. Four host imports replace Brain 2.6 stubs with real implementations:

| Host import | Implementation | Module gate | Audit |
|---|---|---|---|
| `host_sign(sk, msg, out, ...)` → i32 | `bsvz.primitives.ec.PrivateKey.fromBytes(sk).signDigest(msg)` → DER (≤72 bytes) | wallet-engine only | yes (every sign emits `ok` / `denied` / `err`) |
| `host_checksig(pk, msg, sig)` → i32 | `bsvz.crypto.verifyDigest256RelaxedSec1(pk, digest, der)` | both modules | no (called per-opcode during script eval — would be noise) |
| `host_derive_leaf(base_sk, ph, cp, idx, out)` → i32 | BRC-42 invoice = `protocol_hash ‖ counterparty ‖ index_le_u64`; `priv.deriveChild(other_pubkey, invoice)` | wallet-engine only | yes (logs `index=N`) |
| `host_state_next_index(ph, cp, out)` → i32 | broker's `hostStateNextIndex` (atomic increment + persist via `FsStateStore`) | wallet-engine only | yes (broker logs `index=N` on success) |

End-to-end signing round-trip is conformance-tested via a WAT fixture that imports `host_sign` + `host_checksig`, signs a SHA256 digest, then verifies the resulting DER against the matching public key — all happening across the wasmtime ↔ broker ↔ bsvz boundary.

**Brain 3** — interactive REPL (`brain repl`):

```
$ brain repl --config-path ~/.semantos/config.json
brain REPL — type `help` for commands, `exit` to leave.
> status
config:           /home/op/.semantos/data
audit log:        /home/op/.semantos/data/audit.log
modules loaded:   2
wasmtime:         enabled
header store tip: empty
> modules
name              state    sha256
-------------------------------------------------
wallet-engine     LOADED   a9988c124afc2cc9
headers-verifier  LOADED   a9988c124afc2cc9
> audit 5
{"ts":1745786412,"module":"wallet-engine","op":"host_persist_cell","result":"ok","detail":"slot=42 len=1024"}
...
> exit
bye.
```

v0.1 command set:
- **`help`** — list commands
- **`status`** — broker / module / wasmtime / header-tip state
- **`modules`** — list loaded modules with state + hash prefix
- **`audit [N]`** — tail last N audit-log lines (default 20)
- **`call <module> <export>`** — invoke a no-arg wasmtime export returning i32 (works on `-Denable-wasmtime=true` builds)
- **`hash <file>`** — SHA-256 of a WASM file
- **`history [N]`** — show last N commands from `<data-dir>/history`
- **`clear`** — ANSI clear screen
- **`exit` / `quit`** — leave the REPL

History persists to `<data-dir>/history` line-per-line; reload happens on every `brain repl` start.

The REPL is line-based (no raw-mode terminal handling). Operators wanting up-arrow recall + tab completion can wrap with `rlwrap`; richer line editing lands in Brain 3.5 alongside the engine-surface commands. The seven engine-surface commands (`identity`, `balance`, `send`, `anchor`, `policy`, `recover`, `sync`) are reserved — typing them prints a "Brain 3.5 roadmap" hint instead of failing silently.

**WSITE1 + WSITE2** — site-as-sovereign-node:

```
$ brain site init pokerapp.example.com
Scaffolded site pokerapp.example.com:
  config:  ~/.semantos/sites/pokerapp.example.com/site.json
  content: ~/.semantos/sites/pokerapp.example.com/public

Next: `brain serve pokerapp.example.com` to start the HTTP server on port 8080.

$ brain site validate pokerapp.example.com
✓ no problems

$ brain serve pokerapp.example.com
brain serve — pokerapp.example.com
  listening:    0.0.0.0:8080
  content_root: ./public
  routes:       1
  access log:   ~/.semantos/sites/pokerapp.example.com/access.log

Ctrl-C to stop.
```

The server speaks HTTP/1.1 on the configured port, routes static-file requests per `site.json`, returns 404 for unrouted paths and 501 for dynamic / auth-gated routes (those land in WSITE2.5 / WSITE3). Every request appends one JSON line to the per-site `access.log`:

```json
{"ts":1745786412,"method":"GET","path":"/","status":200}
{"ts":1745786413,"method":"GET","path":"/missing","status":404}
```

CLI surface added:
- **`brain site init <domain>`** — scaffold `<sites_dir>/<domain>/site.json` + `public/index.html` placeholder
- **`brain site validate <domain>`** — schema check + warnings for missing static files / deferred features
- **`brain site list`** — every domain configured under the sites dir
- **`brain serve <domain> [--port N]`** — start the HTTP server, blocking until Ctrl-C

Site config JSON shape (full TOML port deferred to WSITE1.5):

```jsonc
{
  "site": {
    "domain":       "pokerapp.example.com",
    "content_root": "./public",
    "listen_port":  8080
  },
  "routes": {
    "/":         { "type": "static",  "file": "index.html", "public": true },
    "/play":     { "type": "dynamic", "handler": "game.wasm",
                   "auth": "identity_required" },          // 501 until WSITE3
    "/premium":  { "type": "static",  "file": "premium.html",
                   "auth": "payment_required",             // 501 until WSITE3
                   "price_sats": 5000 }
  }
}
```

`<sites_dir>` defaults to `~/.semantos/sites`; override with `BRAIN_SITES_DIR=…`. Same pattern for `BRAIN_DATA_DIR` (controls where the access log lives).

**WSITE3** — identity-required auth gates:

Routes declared `auth: "identity_required"` now return real 401 challenges, accept POST `/auth/callback` with a signed nonce, mint a session, and let subsequent requests through:

```
$ curl -i http://localhost:8080/play
HTTP/1.1 401 Unauthorized
x-semantos-challenge: type=identity_auth
x-semantos-nonce: qudGvuFJGEqvuSbq8iYcxw==
x-semantos-return-to: /play
x-semantos-wallet-origin-hint: https://wallet.semantos.app
set-cookie: __semantos_challenge=qudGvuFJGEqvuSbq8iYcxw==; HttpOnly; Path=/auth; Max-Age=300
content-type: text/html; charset=utf-8

<h1>Authentication required</h1>...
```

The wallet origin (out of scope for this binary) signs the nonce with the user's identity key + POSTs JSON to `/auth/callback`:

```json
{
  "pubkey":    "<33-byte compressed SEC1, hex>",
  "signature": "<DER ECDSA, hex>",
  "nonce":     "<base64 from the challenge>",
  "return_to": "/play"
}
```

The server verifies the signature via bsvz secp256k1 (sha256 over the nonce as the message digest), mints a session record, sets a `__semantos_session=<id>.<hmac>` cookie, and 303-redirects back to `return_to`.

**Session cookie format**: `<session_id_hex>.<hmac_hex>` (129 bytes total). HMAC-SHA256 over `session_id ‖ pubkey ‖ expires_at` under the site's `signing_secret`. Tampering with either half fails constant-time comparison. `signing_secret` is generated fresh per `brain site init`.

**Sessions**: in-memory `AutoHashMap` keyed by 32-byte random ID, plus append-only persistence to `<data-dir>/sites/<domain>/sessions.log` for restart survival. Configurable `session_ttl_seconds` per site (default 24h).

**Build dependency**: signature verification requires bsvz (`-Denable-wasmtime=true`). When wasmtime is off, `/auth/callback` returns 503 with a rebuild hint. Challenge issuance + cookie handling + session lookup work in stub mode for tests.

**WSITE4** — payment-required auth gates + revenue ledger:

Routes declared `auth: "payment_required"` now return real 402 challenges with `X-Semantos-Price-Sats`, `X-Semantos-Recipient`, and the same nonce-cookie pattern WSITE3 uses for identity. The wallet origin signs `(nonce ‖ txid ‖ satoshis_le)` and POSTs to `/auth/callback` with an extra `payment` block; on verification the server records the claim to `<data-dir>/sites/<domain>/payments.log` and mints a session.

```
$ curl -i http://localhost:8080/premium
HTTP/1.1 402 Payment Required
x-semantos-challenge: type=payment
x-semantos-nonce: ue+HDZD0rvpbM7AvbAtDvg==
x-semantos-price-sats: 5000
x-semantos-recipient: 020202...0202
x-semantos-return-to: /premium
x-semantos-wallet-origin-hint: https://wallet.semantos.app
set-cookie: __semantos_challenge=ue+HDZD0rvpbM7AvbAtDvg==; HttpOnly; Path=/auth; Max-Age=300
content-type: text/html; charset=utf-8

<h1>Payment required</h1>
<p>This page costs <strong>5000 sats</strong>. Send to <code>0202...</code> ...</p>
```

Callback body for payments adds a `payment` block:

```jsonc
{
  "pubkey":    "...",
  "signature": "...",  // ECDSA over sha256(nonce ‖ txid_raw ‖ satoshis_le_8)
  "nonce":     "...",
  "return_to": "/premium",
  "payment": {
    "txid":     "<32-byte hex>",
    "satoshis": 5000
  }
}
```

The signature commits to the specific (nonce, txid, satoshis) tuple, so replaying it for a different txid won't pass.

**Revenue dashboard** — read the ledger via the `brain revenue` CLI:

```
$ brain revenue paid.local --since 1745786400
revenue — paid.local since ts=1745786400:

  /premium                      12 payments × avg   5000 sats =      60000 sats
  /api/premium-feed              3 payments × avg   1000 sats =       3000 sats
                                 ───────────────────────────────────────
  total                         15 payments                 =      63000 sats

Note: WSITE4 v0.1 records signed payment claims. On-chain SPV
verification of cited txids lands in WSITE4.5; spot-check via
`tail -f <data-dir>/sites/<domain>/payments.log` against your
indexer of choice.
```

**Trust model**: WSITE4 records the payer's *signed claim* (signature commits to (nonce, txid, satoshis)). WSITE4.5 closes the v0.1 trust gap by verifying the cited txid against the chain via WH's trustless-SPV header store before flipping the record to `verified:true`.

Site config additions:
- `site.payment_recipient` — default 33-byte SEC1 pubkey (hex)
- `routes.<path>.payment_recipient` — per-route override
- `brain site validate` errors if `payment_required` route has no recipient + no site-level fallback

**WSITE4.5** — on-chain SPV verification of payment claims:

The auth callback's `payment` block now accepts an optional `beef` hex field carrying the BRC-62 / BRC-95 / BRC-96 envelope for the cited tx. When present:

1. The server persists the raw BEEF to `<data-dir>/sites/<domain>/beefs/<txid>.beef` so a later sweep can re-attempt verification.
2. It calls `payment_verifier.verify` inline — bsvz parses the BEEF, walks every merkle path against WH's local `HeaderStore` (PoW-verified per the `WALLET-HEADERS-TRUSTLESS-SPV` doc), then scans the cited tx's outputs for one that pays ≥ the expected amount to either P2PKH or P2PK against the configured recipient.
3. The result is appended to `<data-dir>/sites/<domain>/payments.log.verifications`. `brain revenue` joins this log against the payment ledger so each record's `verified` flag reflects the latest sweep (last-write-wins — a previously-pending record can flip true after the header store catches up).

```jsonc
{
  "pubkey":    "...",
  "signature": "...",
  "nonce":     "...",
  "return_to": "/premium",
  "payment": {
    "txid":     "<32-byte hex>",
    "satoshis": 5000,
    "beef":     "<raw BEEF, hex>"   // ← WSITE4.5 — optional
  }
}
```

If the BEEF is absent (or the header store hasn't caught up to the tx's height), the record is still recorded with `verified:false`; the operator runs `brain sweep <domain>` later to re-attempt every pending record using the persisted BEEFs.

```
$ brain sweep paid.local
sweep — paid.local
  abababababababab  ✓ verified (5000 sats)
  cdcdcdcdcdcdcdcd  pending — no BEEF on disk
  efefefefefefefef  pending — spv_ok=true output_ok=false

  processed:        3
  newly verified:   1
  still pending:    2
  BEEF missing:     1
  failed:           0
```

`brain revenue` now prints a verified-vs-pending breakdown after the per-route summary, plus an opt-in `--verified-only` flag that filters to confirmed payments:

```
$ brain revenue paid.local
revenue — paid.local:

  /premium                      12 payments × avg   5000 sats =      60000 sats
  ...
  total                         15 payments                 =      63000 sats

verification:
  verified:    9 payments /      45000 sats
  pending:     6 payments /      18000 sats  (run `brain sweep paid.local`)
```

**Build dependency**: SPV verification needs bsvz (`-Denable-wasmtime=true`). When wasmtime is off, `payment_verifier.verify` returns `bsvz_unavailable` and the server records the claim as pending; `brain sweep` will report `failed` rather than crashing.

**WSITE4.6** — internalize verified UTXOs into the admin's OutputStore:

When WSITE4.5's verifier returns `verified=true`, the matched output (vout + locking script + satoshis) now flows into a per-site `OutputStore` so the admin's wallet sees the UTXO as spendable.  The store conforms to the same `core/cell-engine/src/output_store.zig` vtable that the browser IndexedDB and (future) sovereign-node lmdb mirrors implement, so a future WSITE5 spend flow that opens the same store can build a refund tx without any extra plumbing.

```
$ brain outputs paid.local
outputs — paid.local:

  ababab...:0       5000 sats  basket=default  route=/premium
  cdcdcd...:1       1000 sats  basket=default  route=/api/premium-feed

  total: 6000 sats across 2 output(s)
```

What WSITE4.6 records per UTXO (mirrors `WALLET-ACTIVE-USE-ROADMAP` §2 / WA2):

- **outpoint** — `(txid, vout)` from the verified output
- **satoshis** — sats paid by the matched output specifically
- **locking_script** — duped from the BEEF (caller frees); used by future spend signing
- **derived_key_hash** — SHA-256 of the recipient SEC1 pubkey at v0.1 (a stable fingerprint; future routes that derive per-payer leaves via BRC-29 will populate the real derivation context)
- **derivation_protocol_hash / counterparty / index** — zeros for site-config recipients; BRC-42-derived recipients will populate them
- **basket** — defaults to "default"; per-route `output_basket` overrides land in WSITE5
- **custom_instructions** — the route path that triggered the payment (so future spends can join "what did this UTXO pay for")
- **status** — `.unspent` at internalize time; flips to `.spent` when WSITE5's spend flow consumes it
- **confirmations** — 0 at internalize; not yet updated as the chain progresses (WSITE5 sweep)

The store lives at `<data-dir>/sites/<domain>/outputs.log` — append-only JSON-line event log (mirrors `payments.log` / `audit.log`).  Both inline verification (during the auth callback) and `brain sweep` write to the same file.  Re-internalizing the same outpoint is idempotent: the underlying vtable returns `duplicate_outpoint` and the call site swallows it.

```
$ brain sweep paid.local
sweep — paid.local
  abababababababab  ✓ verified (5000 sats)
  ...
  processed:        3
  newly verified:   1
  ...
```

What's deferred to WSITE5+:

- **Spending UTXOs** — the wallet-engine BRC-100 `createAction` flow that consumes outputs from this store.
- **Refunds** — `brain refund <session_id>` constructs a refund tx using the original payment outpoint.
- **Per-route basket overrides** — shipped as `route.output_basket` in WSITE5 (see below).
- **Real BRC-29 / BRC-42 derivation contexts** — today's site recipients are static SEC1 keys from `site.json`; per-payer derivation lands when routes opt into it.

**WSITE5** — admin surface (sessions, refunds, output baskets):

WSITE5 wraps WSITE4.6 with the operator-facing pieces the v0.1 sovereign-node deployment needs:

1. **Durable sessions** — `SessionStore` now replays its log on init, so sessions survive `brain serve` restarts.  Revokes are persisted as their own log event, so a revoked session stays revoked even though the cookie hasn't hit its TTL.

2. **`brain sessions <domain>`** — list active sessions; **`brain sessions revoke <domain> <session_id_hex>`** kills a session immediately (operator's tool for kicking abusers).

3. **Refund intent** — `<data-dir>/sites/<domain>/payments.log.refunds` records `(ts, txid, satoshis, reason)`.  **`brain refund <domain> <txid> [--reason TEXT]`** writes the intent + marks every matching `OutputStore` UTXO spent with a sentinel `0xFF…FF` spending_txid (so `brain outputs` stops listing it as spendable).  v0.1 records intent only — actual refund-tx construction + broadcast lands in WSITE5.5 alongside `brain send` and the wallet-engine spend flow.

4. **Per-route `output_basket`** — routes can declare `"output_basket": "name"` in `site.json`; WSITE4.6's internalize flow uses that bucket instead of `"default"`.  Useful for separating revenue streams ("premium", "tips", "comments-pool" …) so a future sweep can spend from one bucket without touching the others.

5. **`brain revenue` refund breakdown** — when refunds are present, the dashboard now shows a `refunds:` block with `refunded count / sats` and a `net = total − refunded` line.  Steady-state revenue dashboards (no refunds yet) stay quiet.

```
$ brain refund paid.local cdcdcdcdcdcd... --reason "service unavailable"
refund recorded for cdcdcdcdcdcd... (/premium-feed)  sats=1000
  reason="service unavailable"  marked-utxos=1

$ brain revenue paid.local
revenue — paid.local:

  /premium                      12 payments × avg   5000 sats =      60000 sats
  /api/premium-feed              3 payments × avg   1000 sats =       3000 sats
                                 ───────────────────────────────────────
  total                         15 payments                 =      63000 sats

verification:
  verified:    9 payments /      45000 sats
  pending:     6 payments /      18000 sats  (run `brain sweep paid.local`)

refunds:
  refunded:    1 payments /       1000 sats
  net:                            62000 sats (total − refunded)
```

What WSITE5 deliberately does NOT do (deferred to WSITE5.5+):

- **Refund tx construction + broadcast** — needs the wallet-engine `createAction` surface wired into the broker.  Until then, the refund intent is recorded; the operator builds + broadcasts the refund manually.
- **Per-route revenue caps** (`daily_max_satoshis`) — needs in-memory rate-tracking + custom 402 response.
- **Webhooks on payment** — `route.on_payment.url` POST after a payment records.
- **REPL wiring** — `revenue / outputs / sessions / refund / sweep` are CLI-only at v0.1; they'd duplicate substantial logic in `repl.zig` for marginal benefit.  Operators wanting interactive site management run a sub-shell.
- **BRC-52 identity certs** — WSITE3.5 work; today's identity gate is signature-only.

**WSITE2.5** — dynamic-route WASM-handler dispatch:

Routes typed `"dynamic"` no longer return 501.  Each route's `handler.wasm` is hash-pinned (mirrors `brain start`), pre-instantiated at `brain serve` boot, and invoked per request via a minimal pure-function ABI:

```wat
(module
  (memory (export "memory") 1)
  (func $handle (export "handle") (param $method i32) (param $body_len i32) (result i64)
    ;; method:    1=GET 2=POST 3=PUT 4=DELETE 5=PATCH 6=OPTIONS 7=HEAD 0=other
    ;; body_len:  bytes the host wrote at memory[0..body_len]
    ;; returns:   (status: u16) << 32 | (response_len: u32)
    ;;            response written by handler at memory[0..response_len]
    ...))
```

Site config gains `handler_sha256` (required for dynamic routes; refused otherwise — same trust-anchor pattern as `brain start`):

```jsonc
"/api/score": {
  "type": "dynamic",
  "handler": "score.wasm",
  "handler_sha256": "deadbeef...",
  "auth": "identity_required"
}
```

Auth gates fire BEFORE the handler runs — a `payment_required + dynamic` route still demands the 402 callback before invoking `handle()`.

Handlers are treated as untrusted code at the broker level: `dynamic_handler` is a new module kind that shares the wallet/headers policy denials (no `host_sign`, no `host_persist_cell`, no `host_state_next_index`).  Stateless primitives (sha256/hash160/etc.) are allowed because they bypass the broker entirely.  Future per-handler scratch storage can be added on top.

`brain serve` only stands up the broker + runner pipeline when at least one route is dynamic; static-only sites stay broker-free.  Dynamic-handler-using sites in the disabled-build path return 503 with a "rebuild with -Denable-wasmtime=true" hint.

Caps at v0.1: 4 MiB request body, 4 MiB response.  Larger payloads → 413.

What WSITE2.5 deliberately does NOT do (deferred):

- **Custom response headers** — handlers can't yet emit Content-Type or set-cookie; the host always writes `Content-Type: <route extension sniff>`.  ABI v2 will let handlers serialize a header block.
- **Path / query / request-header passthrough** — handlers are bound to a single route, so they don't need the path; query strings + arbitrary request headers wait for ABI v2.
- **Per-handler scratch storage** — handlers should be stateless or use a future `host_handler_kv_*` surface.  Today's memory is reset between requests is enforced by handler instance reuse: nothing forces a memory reset, but operators should treat handler memory as scratch.

**WH-Producer phase 1** — Zig-native BSV P2P header sync:

`brain headers sync` is the producer side of the trustless-SPV story.  WSITE4.5 + the browser's WH consumer both expect a populated header chain at `<data-dir>/headers.bin`; until now the operator had to point a separate process (Go's `b-open-io/block-headers-service`, Teranode's asset endpoint, …) at the file.  WH-Producer phase 1 closes that gap with a hand-rolled BSV P2P client in Zig:

- **`p2p_wire.zig`** — minimal BSV P2P wire protocol.  Encode/decode `version` / `verack` / `getheaders` / `headers` / `ping` / `pong`.  Reader/writer-agnostic so tests pass `std.Io.Reader.fixed` / `Writer.fixed` and production passes a TCP-stream adapter.  4 MiB max payload cap; sha256d checksum on every envelope.
- **`headers_sync.zig`** — handshake + locator builder + `getheaders → headers` loop.  Each received header gets PoW-validated via cell-engine's `Header.satisfiesProofOfWork` and prev-hash-chained against the store's tip.  Reorgs surface as `error.reorg_detected` for the operator to handle (auto-rollback lands in WH-Producer phase 2).
- **`brain headers tip`** — print the current store's tip height + display-form hash.
- **`brain headers sync [--peer host:port] [--max-rounds N]`** — connect, handshake, fetch up to N rounds of headers (`max-rounds × 2000` capped per peer round).  Default peer is `seed.bitcoinsv.io:8333`; brain resolves the DNS seed and tries each returned address before surfacing a connection failure.  Reports per-round counts + final tip.
- **`brain headers reset --yes`** — wipe `headers.bin` + `headers.idx` for a fresh re-sync (operator escape hatch when the chain state is corrupted or you're switching networks).

What WH-Producer phase 1 deliberately did NOT ship (handled in phase 2 below):

- **Tip subscription** — phase 2 polls every 60s. Push-driven `inv` is still phase 3.
- **HTTP serving** — phase 2 ships the BHS-compat surface; browser clients can now point at the operator's own Semantos Brain.
- **Auto-reorg** — still phase 3 (operator runs `brain headers reset` if needed).
- **DAA-vs-bits validation** — still deferred (phase-3 work alongside reorg).

**WH-Producer phase 2** — long-running tip subscription + BHS-compatible HTTP server:

`brain headers serve` is the long-running counterpart to phase-1's one-shot `brain headers sync`.  It wraps the same P2P + storage + validator stack with:

1. **A background tip-subscription thread** — every `--sync-interval-secs` (default 60) reconnects to `--peer` (default `seed.bitcoinsv.io:8333`), runs handshake + one round of `getheaders`/`headers`, validates, appends.  Logs `[headers serve] tip poll: +N headers` to stderr when fresh tips arrive.

2. **A foreground HTTP server** on `--http-port` (default 8334) exposing the four endpoints the browser bundle's `apps/wallet-browser/src/header-source-adapter.ts` already hits:

   | Endpoint | Returns |
   |---|---|
   | `GET /api/v1/chain/header/byHeight/tip` | `application/json`: `{"height":N,"hash":"<display-form hex>"}` |
   | `GET /api/v1/chain/header/byHeight/{N}` | `application/octet-stream`: 80 raw bytes |
   | `GET /api/v1/chain/header/byHash/{display-hex}` | `application/octet-stream`: 80 raw bytes |
   | `GET /api/v1/chain/header/range?from=N&to=M` | `application/octet-stream`: concatenated 80-byte headers (cap 2000 per request — same limit BSV P2P enforces) |

Live verification end-to-end:

```
$ BRAIN_DATA_DIR=/tmp/brain-smoke brain headers serve --http-port 8334 --sync-interval-secs 60
brain headers serve
  data_dir:           /tmp/brain-smoke
  http listen:        0.0.0.0:8334
  peer:               seed.bitcoinsv.io:8333
  sync interval:      60s
  starting tip:       height 1999

# in another shell:
$ curl -s http://localhost:8334/api/v1/chain/header/byHeight/tip
{"height":1999,"hash":"00000000dfd5d65c9d8561b4b8f60a63018fe3933ecb131fb37f905f87da951a"}

$ curl -s http://localhost:8334/api/v1/chain/header/byHeight/0 | xxd | head -1
00000000: 0100 0000 0000 0000 0000 0000 0000 0000  ................

$ curl -s -o range.bin "http://localhost:8334/api/v1/chain/header/range?from=0&to=2"
$ wc -c range.bin
240 range.bin   # 3 × 80 bytes
```

That tip hash matches the canonical block 1999 hash on every block explorer.  An operator's browser bundle can now configure its `header-source-adapter.ts` to point at `https://wallet.example.com:8334/` instead of BHS.  **The "no Go in the deployment" loop is closed for both the sovereign-node SPV path and the browser SPV path.**

What WH-Producer phase 2 deliberately does NOT ship (deferred to phase 3):

- **Push-driven tip subscription** (`inv` from peer instead of polling).  60-second poll is fine for BSV's ~10-min average block time.
- **Auto-reorg** — when peer's chain diverges, `runOneTipPoll` errors out (logged to stderr); the next interval retries.
- **TLS** — operator runs Caddy in front of `:8334` for HTTPS (same pattern as `brain serve`).
- **HEAD-only optimisations / range Etag headers** — the response is small enough that revalidation costs nothing meaningful.

**WSITE5.5** — refund tx construction + ARC broadcast:

`brain refund` upgrades from WSITE5's intent-only logging to actually building, signing, and broadcasting a refund transaction.  The shape:

1. **`signing_key_wif` in `site.json`** — operator declares their WIF-encoded private key.  When set, refunds broadcast; when empty, behaviour falls through to WSITE5 intent-only (the sentinel `0xFF…FF` spending_txid).  v0.1 plaintext-on-disk is the operator-trust trade-off; v0.2 encrypts at rest under a passphrase set at boot; v0.3 hands signing to the wallet-engine WASM module's tier-key custody flow so the key never leaves the WASM sandbox.
2. **`runtime/semantos-brain/src/refund_tx.zig`** — bsvz-backed: decodes the WIF, derives the payer's P2PKH address from their compressed SEC1 pubkey (recorded in WSITE4.6's OutputRecord.derivation_counterparty), builds a 1-input → 1-output transaction via `bsvz.transaction.Builder`, applies a sats/KB fee model, signs with `signAllP2pkh`, and serializes.  Stub mirror returns `bsvz_unavailable` so the disabled-build path stays compilable.
3. **ARC broadcast** — `bsvz.broadcast.arc.Arc` posts the signed bytes to a configurable ARC endpoint (default Taal's free public ARC at `https://arc.taal.com/v1/tx`).  Returns `BroadcastOutcome { ok, detail }` — `detail` is the broadcast txid on success or the ARC error code on failure.
4. **`brain refund` flow** — for each matching `OutputStore` UTXO, attempts broadcast; on success, marks the UTXO spent with the *real* refund tx's id (instead of the WSITE5 sentinel); on failure, falls back to the sentinel + logs the ARC error.  Refund-intent record still appended to `payments.log.refunds` either way (audit trail intact).

What WSITE5.5 deliberately does NOT ship (deferred to WSITE5.6+):

- **Webhooks on payment** — `route.on_payment.url` POST after a payment records.
- **Per-route revenue limits** (`route.daily_max_satoshis`) — needs in-memory rate-tracking + custom 402.
- **`brain send <domain>`** admin-initiated send — same broadcast path as refund, just with an arbitrary recipient instead of the original payer.
- **Encrypted-at-rest signing key** (passphrase-gated) — operator's plaintext WIF in `site.json` is the v0.1 trust trade-off.
- **Wallet-engine-mediated signing** — long-term goal is for the signing key to live inside the wallet-engine WASM module's tier-key custody, with `brain refund` calling `host_sign` through the broker instead of holding the key directly.  Lands when the broker's WSITE-side surface gets fleshed out.

## D-W1 Phase 1 Part 2 — Identity certs (`identity_certs` resource)

Phase 1 Part 1 (PR #270) shipped the dispatcher seam + the `bearer_tokens` resource handler + the Unix-socket transport.  Phase 1 Part 2 adds the **`identity_certs`** resource handler — the substrate D-O5p (child-cert pairing) lands on top of, and the storage layer for `brain device list|revoke`.

Reference: [`docs/design/BRAIN-DISPATCHER-UNIFICATION.md`](../../docs/design/BRAIN-DISPATCHER-UNIFICATION.md) §3, §7; [`docs/spec/protocol-v0.5.md`](../../docs/spec/protocol-v0.5.md) §4.4–§4.5; [`docs/design/ODDJOBZ-EXTENSION-PLAN.md`](../../docs/design/ODDJOBZ-EXTENSION-PLAN.md) §3 Phase O5p.

What's in this slice:

| File | Role |
|---|---|
| `src/bkds.zig` | Canonical **BRC-42** invoice-with-counterparty key derivation (secp256k1 scalar tweak via bsvz `PrivateKey.deriveChild`).  Same primitive `core/cell-engine/src/host.zig:deriveLeaf` calls for the wallet-engine WASM (`host_derive_leaf`).  Public surface: `deriveChildPubkey`, `deriveChildPubkeyFromDevice` (the device-side path; structural ECDH symmetry pins the verifier), `verifyDerivationProof` (the brain's recompute-and-compare). |
| `src/identity_certs.zig` | Append-only cert chain at `<data_dir>/identity-certs.log`; in-memory index rebuilt at startup; same shape + concurrency model as `bearer_tokens.zig`.  Pubkey shape on disk is 33-byte compressed SEC1. |
| `src/resources/identity_certs_handler.zig` | Dispatcher resource handler.  Commands: `issue_root`, `issue_child`, `list`, `revoke`, `get`.  All gated by `cap.brain.admin`.  Carries an in-memory `operator_root_priv` (installed via `setOperatorRootPriv`) needed for BRC-42 verification; `issue_child` fails closed (`derivation_context_mismatch`) if it isn't installed. |
| `tests/identity_certs_conformance.zig` | Full dispatcher → handler → store conformance + the security-critical assertions (forged-counterparty rejection, bit-flipped child rejection, context-tag-swap rejection, revoke-root rejection, log-replay round-trip, BRC-42 canonical-vector parity, ECDH-symmetry round-trip, fail-closed-no-priv). |
| `tests/fixtures/bkds_vectors.json` | BRC-42 canonical vectors generated by `tools/gen_bkds_vectors.zig` (driving bsvz directly).  Schema v2: `{root_seed, root_priv_hex, root_pub_hex, device_seed, device_priv_hex, device_pub_hex, context_tag, label, child_pub_hex}`. |
| `tools/gen_bkds_vectors.zig` | Zig fixture generator.  Run via `zig build gen-bkds-vectors`.  10 deterministic vectors covering basic derivation, context-tag variation, counterparty variation, parent variation, and edge cases (empty label, max-length label, context tags 0x00/0xFF). |

Commands the resource accepts (all JSON-shaped over the wire envelope):

| Command | Args | Result | Cap |
|---|---|---|---|
| `issue_root` | `{pubkey, label}` | cert record (idempotent on second call) | `cap.brain.admin` |
| `issue_child` | `{parent_cert_id, context_tag, capabilities, label, derivation_pubkey, derivation_proof}` | child cert record | `cap.brain.admin` |
| `list` | `{}` | `{certs: [...]}` (excludes revoked) | `cap.brain.admin` |
| `revoke` | `{cert_id}` | `{ok: true}` (root id → `cannot_revoke_root`) | `cap.brain.admin` |
| `get` | `{cert_id}` | cert record OR `cert_not_found` | `cap.brain.admin` |

Operator surface added in this slice:

```bash
$ brain device list
(via daemon at /home/op/.semantos/data/brain.sock)

1 cert(s) in chain:

  cert_id:     ab12cd34ef5678901234567890abcdef
  kind:        root
  label:       operator
  context_tag: 0x00
  issued_at:   1730000000

$ brain device revoke --id <child-cert-id>
revoked: <id> (via daemon at /home/op/.semantos/data/brain.sock)
```

`brain device pair` and `brain device claim` are **D-O5p** territory (the QR-payload + acceptor flow) and are deliberately out of scope for this PR — `brain device <unknown>` prints a hint pointing at the D-O5p deliverable.

Leaf derivation: every child cert is bound to its (operator_root, context_tag, label, device_counterparty) tuple via canonical BRC-42 — `child_priv = root_priv + HMAC-SHA-256(invoice, key=compressed_sec1(root_priv·device_pub))` mod n, with `invoice = "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label`.  The brain holds the operator's secp256k1 priv in-memory (installed at `cmdServe` startup); the device-side computes the same child via the symmetric path (`device_priv.deriveChild(root_pub, invoice)`).  ECDH symmetry guarantees both endpoints arrive at byte-identical child pubkeys without exchanging a private half.

Security argument the conformance tests bake in (per the brief's threat model):

- **cap forgery** — `issue_child` recomputes the BRC-42 child on the brain side from `(operator_root_priv, derivation_proof, context_tag, label)` and constant-time compares against the device-submitted `derivation_pubkey`.  An attacker without `device_priv` cannot supply a counterparty pubkey whose ECDH-derived child matches what they're claiming — the shared secret is keyed by both private halves.  Tests pinning this: `issue_child rejects forged derivation_proof` (submits a different counterparty pubkey for the same claimed child) and `issue_child rejects bit-flipped derivation_pubkey` (submits a tampered child pubkey for the same counterparty).  Both assert `derivation_context_mismatch`.
- **cross-device impersonation** — context_tag rides into the BRC-42 invoice as a single byte; a swap reshapes the HMAC tweak and therefore the child.  A proof minted for the carpenter context (`0x10`) does not verify under the musician context (`0x11`).  Test pinning this: `issue_child rejects context-tag swap`.  Structural K3 isolation per `BRAIN-DISPATCHER-UNIFICATION.md` §2.5.
- **revocation bypass** — once revoked, a child cert drops out of `list`, `get` returns `cert_not_found`, and `issue_child` against the revoked id surfaces `parent_not_found`.  Tests: `issue_child against a revoked parent returns parent_not_found`, `revoke child → list excludes`, `log replay` (post-state survives a daemon restart).
- **fail-closed verifier** — `issue_child` requires `operator_root_priv` to be installed on the handler; without it the brain cannot run BRC-42 verification, and silently accepting would be a structural cap-forgery hole.  Test: `BRC-42 verifier rejects when operator priv is missing (fail-closed)`.
- **ECDH symmetry** — the structural BRC-42 property the tests pin so a future regression that diverged on the symmetry would surface immediately.  Test: `BRC-42 ECDH-symmetry round-trip — device-side child equals operator-side child`.

What's still out (post-Phase-1-Part-2):

- **Pairing flow / QR / claim** — D-O5p.  This PR ships the BRC-42 substrate D-O5p builds on.
- **BRC-52 cert chain signatures** — D-O5p.  Today's chain is a flat root → child structure; BRC-52 multi-level signed chains land alongside the QR/claim flow.
- **TS-side `KeyDerivationService` BRC-42 convergence** — the TS prototype still speaks the HMAC-SHA-512 flavour.  Per the user's PR-275 review note, TS converges to bsvz BRC-42 in a follow-up; the canonical substrate is now the Zig BRC-42 surface, not the TS adapter.
- **Capability minting as UTXOs** — D-O3.

## What's NOT shipping yet (WSITE5.6+)

- **Webhooks on payment** — WSITE5.6. Per-route `on_payment` URLs that fire when a payment is recorded.
- **Per-route revenue limits** (`daily_max_satoshis`) — WSITE5.6.
- **`brain send <domain>`** — WSITE5.6 admin-initiated send.
- **Encrypted-at-rest signing key** — WSITE5.6 / WSITE5.7.
- **Wallet-engine-mediated signing** — WSITE5.7+.
- **Custom handler response headers + path/query passthrough** — WSITE2.6. ABI v2 lets handlers emit headers + read the request URL.
- **TLS termination** — operator runs Caddy in front of `:8080` for v0.1.
- **Dynamic-route WASM-handler dispatch** (`type: "dynamic"`) — WSITE2.5.
- **BRC-52 identity certs + trusted-issuer matching** — WSITE3.5. Today's identity gate is signature-only (any valid keypair passes).
- **Site-config cell signing** — WSITE1.5.
- **Hot reload** — WSITE2.5.
- Engine-surface REPL commands: `identity`, `balance`, `send`, `anchor`, `policy`, `recover`, `sync` — need wallet-engine BRC-100 method calls + identity material loaded into the broker.
- Tab completion + arrow-key history navigation — needs raw-mode terminal handling.
- `host_unlock_tier`, `host_persist_cell` / `host_load_cell` from the embedded engine path — the kernel exports don't currently call them, so they're not in `cell-engine-embedded.wasm`'s import section.
- `host_checkmultisig` — multisig variant; same pattern as host_checksig but iterates m-of-n.
- `host_fetch_header_range`, `host_broadcast_tx` — network adapters.
- Brain 4 remote surfaces (SSH / WSS / HTTP).
- Brain 5 LLM adapter (optional).
- Brain 6 deployment recipes (Docker, systemd, NixOS, Ansible).

## Why WASM-sandboxing on the server (vs. native linking)

Per §2 of the design doc:

| Property | Native link | WASM sandbox |
|---|---|---|
| Identical binary across browser + server | ❌ | ✅ |
| Memory isolation between modules | weak | strong |
| Future: load untrusted community modules | unsafe | safe |
| Auditable hash of "what's running" | per-platform builds | one hash, every deployment |
| Performance overhead | none | ~5-10% on hot paths |

The 5-10% perf hit is irrelevant for wallet workloads; the architectural properties matter more.

## Configuration

Default location: `~/.semantos/config.json`. Override with `--config-path <path>`.

```jsonc
{
  "shell": {
    "data_dir":    "~/.semantos/data",
    "modules_dir": "~/.semantos/wasm"
  },
  "modules": {}
}
```

Spec calls for TOML; v0.1 ships JSON to avoid a third-party TOML dep. A TOML port can land in Brain 1.5 without breaking config consumers.

The default config is native-first and does not reference `wallet-engine.wasm` or `headers-verifier.wasm`.  Those module entries are optional/future: when a WASM bundle exists, the operator adds it explicitly, runs `brain hash <wasm_file>`, and pins the resulting SHA-256 in `modules`.

## Quick walkthrough

```bash
$ brain init
Wrote default config to /home/op/.semantos/config.json
Next steps: ...

$ brain status
brain status — config /home/op/.semantos/config.json
  no WASM modules configured

$ brain serve --enable-repl
...
```

## Development

```bash
zig build                              # default — verifier-only build, no wasmtime dep
zig build -Denable-wasmtime=true       # links libwasmtime; `brain start` instantiates
                                       # macOS prereq: brew install wasmtime
                                       # Linux:        apt install libwasmtime-dev (or build from source)

zig build test                         # full unit suite (real-mode tests skip in stub mode)
zig build test -Denable-wasmtime=true  # full suite including the WAT-fixture round-trip
zig build run -- version               # forward args to the binary
```

Override the wasmtime install location with `-Dwasmtime-prefix=/path` (default: `/opt/homebrew` on Apple Silicon, `/usr/local` elsewhere).

## Crate layout

```
runtime/semantos-brain/
├── build.zig                  # native binary + tests
├── build.zig.zon              # no external deps; cell-engine vtables imported via path
├── src/
│   ├── main.zig               # argv → cli dispatch + exit code
│   ├── cli.zig                # subcommand handlers
│   ├── config.zig             # JSON config loader + default template
│   ├── module_loader.zig      # SHA-256 pin + WASM-magic validator
│   ├── instance_manager.zig   # LOADED/RUNNING/STOPPED/CRASHED FSM
│   ├── audit_log.zig          # append-only structured JSON log
│   ├── slot_store_fs.zig      # file-backed SlotStore vtable
│   ├── state_store_fs.zig     # file-backed DerivationStateStore vtable
│   ├── header_store_fs.zig    # file-backed HeaderStore vtable
│   ├── broker.zig             # host-import dispatcher + policy + audit
│   ├── runner.zig             # wasmtime-agnostic Runner facade
│   ├── wasmtime_runner_real.zig   # wasmtime C-API backend (built when -Denable-wasmtime=true)
│   ├── wasmtime_runner_stub.zig   # error-only backend (default; tests still run against it)
│   ├── repl.zig                   # Brain 3 — interactive REPL
│   ├── site_config.zig            # WSITE1 — per-domain site config + route table
│   ├── site_server.zig            # WSITE2/3/4/4.5 — HTTP listen loop, routes, auth, payment
│   ├── auth_handler.zig           # WSITE3/4 — identity + payment callbacks, sessions, signatures
│   ├── payment_ledger.zig         # WSITE4 — append-only payment log + WSITE4.5 verifications join
│   ├── payment_verifier.zig       # WSITE4.5 — BEEF → SPV check (built with bsvz)
│   ├── payment_verifier_stub.zig  # WSITE4.5 — stub mirror (built without bsvz)
│   └── output_store_fs.zig        # WSITE4.6 — file-backed OutputStore for verified UTXOs
└── tests/
    ├── config_conformance.zig
    ├── module_loader_conformance.zig
    ├── instance_manager_conformance.zig
    ├── cli_conformance.zig
    ├── audit_log_conformance.zig
    ├── slot_store_fs_conformance.zig
    ├── state_store_fs_conformance.zig
    ├── header_store_fs_conformance.zig
    ├── broker_conformance.zig
    ├── runner_conformance.zig         # WAT fixture → instantiate → run → broker round-trip
    ├── repl_conformance.zig
    ├── site_config_conformance.zig
    ├── site_server_conformance.zig
    ├── auth_handler_conformance.zig
    ├── payment_ledger_conformance.zig # WSITE4 + WSITE4.5 ledger join coverage
    ├── payment_verifier_conformance.zig # WSITE4.5 — surface contract in both modes
    └── output_store_fs_conformance.zig # WSITE4.6 — FsOutputStore round-trips
```
