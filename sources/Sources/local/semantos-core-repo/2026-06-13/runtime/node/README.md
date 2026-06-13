---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.029526+00:00
---

# `runtime/node` — Semantos sovereign wallet node

This directory hosts **W6** of the wallet tiered-custody design
(`docs/design/WALLET-TIER-CUSTODY.md` §10.2): a native Zig daemon
(`semantos-node`) fronted by Caddy that exposes a BRC-100 WSS endpoint
for browser dApps and serves the wallet UI from the same origin.

> NOTE: this directory historically also hosts a **TypeScript** package
> `@semantos/node` (federation node daemon, admin API, license policy
> — pre-W6 work). The two are independent: the TS code lives under
> `src/*.ts`, the Zig code under `src/*.zig` / `tests/*.zig`. The Zig
> daemon binary is built into `zig-out/bin/semantos-node`; the TS
> daemon is invoked via `bun src/daemon.ts`. They serve different
> concerns and can run on the same host without conflict.

## Build & test

Requires Zig 0.15.2 (the project pin — see `core/cell-engine/build.zig`).

```sh
cd runtime/node
zig build              # produces zig-out/bin/semantos-node
zig build test         # runs all tests under runtime/node/tests/
```

The build pulls `bsvz` via `build.zig.zon` (same pin as
`core/cell-engine/build.zig.zon`) and references the cell-engine
modules via relative paths — no global install step is needed.

## Dev loop

```sh
# Terminal 1 — daemon
cd runtime/node
zig build
./zig-out/bin/semantos-node \
    --listen 127.0.0.1:8421 \
    --data-dir /tmp/semantos-test

# Terminal 2 — Caddy (TLS termination + UI bundle, optional for unit tests)
caddy run --config Caddyfile.dev

# Terminal 3 — smoke test against the daemon directly
# (the daemon speaks plain WS; production setups go via Caddy WSS).
# A hand-rolled BRC-100 envelope test is `tests/wss_conformance.zig`.
zig build wss-conformance
```

The first run creates `/tmp/semantos-test/` and seeds an identity in
`identity.bin`. The daemon prints its identity public key on startup;
that's the same key returned by a successful BRC-100 `getPublicKey`
request.

## Data dir layout

```
<data-dir>/
├── identity.bin          # 32-byte secp256k1 secret (atomic write-rename)
├── state.bin             # DerivationStateStore: BRC-42 (protocol, counterparty) → index
├── state.bin.tmp         # rewrite scratch (deleted on success)
└── slots/
    ├── 00000001.blob     # SlotStore: tier-key envelopes (slot_id → AES-GCM blob)
    └── 00000002.blob
```

Acceptance criterion 4 (lmdb persistence end-to-end) is covered by
`tests/lmdb_round_trip.zig`: every store is opened, mutated, dropped,
and re-opened — the final read sees the previous write.

## Storage backend

Per `docs/design/WALLET-TIER-CUSTODY.md` §10.2, the design specifies
**lmdb**. v0.1 ships a pure-Zig directory-of-files implementation
(no system C library required) that satisfies the same `SlotStore` /
`DerivationStateStore` vtables defined in
`core/cell-engine/src/{slot_store.zig,derivation_state.zig}`.
Crash-safety comes from POSIX `rename()` atomicity: every mutation
writes a `.tmp` file, fsyncs, then renames over the canonical path.

A real lmdb backend (system `liblmdb` or `libmdbx`) is a v0.2 swap:
substitute `LmdbSlotStore` / `LmdbStateStore` for an `mdb_env_open` +
`mdb_put`/`mdb_get` impl behind the same vtable, no caller changes.
The on-disk format defined here is **not** lmdb's format; it is the
v0.1 daemon's format. Backups should be taken at the directory level.

## Caddy relationship

The daemon **never terminates TLS**. Production deploys put Caddy in
front:

```
browser ── wss:// ──▶ Caddy (TLS, port 443) ── ws:// (loopback / unix sock) ──▶ semantos-node
                              │
                              └── /        (static)        ──▶ wallet UI bundle (W5)
                              │
                              └── /p2p/*   (501)           ──▶ reserved for v0.3 mesh (§3.5.2)
```

`Caddyfile` is the production template (replace `node.semantos.example`
with your real DNS name and run `caddy validate Caddyfile`).
`Caddyfile.dev` is a localhost-only variant with `tls internal` for
offline work — it expects the daemon on `127.0.0.1:8421`.

## Service deployment

`systemd/semantos-node.service` ships the standard hardening flags
(NoNewPrivileges, ProtectSystem=strict, MemoryDenyWriteExecute,
@system-service syscall filter) plus `RuntimeDirectory=semantos` for
the Unix socket parent and `StateDirectory=semantos` for `/var/lib`
persistence.

Install:

```sh
install -m 0755 zig-out/bin/semantos-node /usr/local/bin/
install -m 0644 systemd/semantos-node.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now semantos-node
```

## Method coverage (v0.1)

| BRC-100 method   | Status        | Notes                                                  |
|------------------|---------------|--------------------------------------------------------|
| `getPublicKey`   | ✓             | Returns the daemon's identity SEC1-compressed pubkey. |
| `createAction`   | reject (-32601) | Pending W7 (Plexus dispatch flow).                  |
| `signAction`     | reject (-32601) | Pending W7.                                         |
| (everything else) | reject (-32601) | "method not implemented".                          |

The reject envelope shape is `{"id":<id>,"error":{"code":<int>,"message":<str>}}`
— a structured failure. The connection stays open after a reject so
clients can retry without re-handshaking.

## Out of scope

Per the W6 brief:

- TLS in the Zig daemon (Caddy's job).
- W5 wallet-UI bundle (`apps/wallet-browser/`).
- W7 Plexus dispatch / recovery (a separate path; the `createAction`
  reject above stands in for it).
- v0.3 federated p2p mesh (the `/p2p/*` 501 placeholder satisfies the
  route reservation per design §11 Q6).

## Cross-references

- `docs/design/WALLET-TIER-CUSTODY.md` §10.2 — sovereign-node topology
- `docs/design/WALLET-TIER-CUSTODY.md` §11 Q6 — Caddyfile structure
- `core/cell-engine/src/host.zig` — `setSlotStore`, `setDerivationStateStore`,
  signing primitives (full profile)
- `core/cell-engine/src/slot_store.zig` — `SlotStore` vtable + stub this directory replaces
- `core/cell-engine/src/derivation_state.zig` — `DerivationStateStore` vtable
