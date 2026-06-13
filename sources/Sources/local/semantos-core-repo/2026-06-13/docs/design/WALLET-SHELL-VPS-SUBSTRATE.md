---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-SHELL-VPS-SUBSTRATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.731155+00:00
---

# Wallet Shell — Sovereign-Node VPS Substrate (Brain 1–Brain 6)

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` (v0.4), `docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md`, `docs/design/WALLET-W6-W7-NEXT-PHASE.md` (subsumed by this plan)

---

## 0. Headline

> A single Zig binary on a $5/mo VPS that loads two WASM-sandboxed 2-PDAs (the wallet engine and the headers verifier), exposes a REPL over TUI / SSH / WSS, mediates host imports for storage and network, and turns the user's conversation into signed Semantos cells anchored on-chain. The same WASM modules that run in every user's browser run inside this shell — bit-identical, hash-pinned. The browser is one client of the substrate; the shell is the substrate itself.

---

## 1. Where We Are

The wallet today exists in two deployment topologies:

| Topology | Today | Limitation |
|---|---|---|
| Browser bundle (W5) | WASM modules + IndexedDB at `wallet.semantos.app` | Tied to browser; user can't run wallet without a tab open |
| Sovereign node (W6) | Zig binary + Caddy, BRC-100 over WSS | Specced as "browser backend" — single-purpose; no REPL, no composition story |

W6 was useful but under-specified for what the deployment actually wants to be. BRAIN replaces W6 with a richer architecture: the same Zig binary becomes a **composition substrate** that loads multiple WASM-sandboxed modules, exposes an interactive shell, and serves as the foundation for sovereign-node-as-website (WSITE), sovereign-node-as-mesh-peer (future WF), and sovereign-node-as-anything-else.

The two key insights driving BRAIN:

1. **The same WASM modules used in the browser run on the server.** Bit-identical binaries, hash-pinned. Users can verify "the wallet engine binary I'm running has SHA-256 = c091c3..." regardless of whether it's in their mobile Safari or on their VPS. This is the WASM-MANIFEST property doing real architectural work.

2. **Hard module isolation enables future extensibility.** The wallet engine literally cannot read the headers verifier's memory and vice versa, enforced by WebAssembly's linear-memory boundary. This same boundary lets the substrate later load community-contributed modules, third-party signing protocols, custom cell types — without weakening the trust story for the core wallet.

---

## 2. The Composition Pattern

```
┌──────────────────────────────────────────────────────────┐
│ semantos-shell  (Zig native binary, ~5MB + ~10MB         │
│                  wasmtime runtime)                         │
│                                                             │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────────┐   │
│  │ REPL        │  │ wasmtime   │  │ Storage (lmdb)   │   │
│  │ Surfaces:   │  │ runtime    │  │  - SlotStore     │   │
│  │  - TUI      │  │            │  │  - DerivStore    │   │
│  │  - SSH      │  │            │  │  - OutputStore   │   │
│  │  - WSS      │  │            │  │  - HeaderStore   │   │
│  │  - HTTP     │  │            │  │  - SetupStatus   │   │
│  └─────────────┘  └─────┬──────┘  └──────────────────┘   │
│                          │                                 │
│         ┌────────────────┴─────────────────┐               │
│         ▼                                   ▼               │
│  ┌────────────────┐                 ┌──────────────────┐  │
│  │ WASM 2-PDA #1  │                 │ WASM 2-PDA #2    │  │
│  │ wallet engine  │                 │ headers verifier │  │
│  │  (cell-engine  │                 │  (WH module)     │  │
│  │   + OP_SIGN +  │                 │                  │  │
│  │   budget ops + │                 │ Holds:           │  │
│  │   vault ops)   │                 │  - tip header    │  │
│  │                │                 │  - PoW state     │  │
│  │ Holds:         │                 │                  │  │
│  │  - tier base   │                 │ Hash-pinned:     │  │
│  │    keys        │                 │   bf4e...c2a1    │  │
│  │  - leaf keys   │                 │                  │  │
│  │                │                 │                  │  │
│  │ Hash-pinned:   │                 │                  │  │
│  │   c091...713d  │                 │                  │  │
│  └────────────────┘                 └──────────────────┘  │
│         ▲                                   ▲               │
│         │ host imports (host_sign,           │               │
│         │  host_unlock_tier, host_persist…)  │               │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ Host-import broker — mediates every WASM call out:    │ │
│  │  - storage I/O routed to lmdb                          │ │
│  │  - network I/O routed to bsvz broadcast / WS clients   │ │
│  │  - REPL prompts / responses routed to active surface   │ │
│  │  - cross-module calls policed (wallet ↔ headers via    │ │
│  │    well-defined interface, never direct memory)        │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

**Why WASM sandboxing on the server (not just native linking):**

You could compile `cell-engine` to a native Zig library and link it directly into the shell binary. Faster (no wasmtime overhead), simpler (no embedding). The reason to keep the WASM boundary on the server:

| Property | Native link | WASM sandbox |
|---|---|---|
| Identical binary across browser + server | ❌ | ✅ |
| Memory isolation between modules | weak (shared address space) | strong (linear-memory boundary) |
| Future: load untrusted community modules | unsafe | safe |
| Auditable hash of "what's running" | per-platform builds | one hash, every deployment |
| Performance overhead | none | ~5-10% on hot paths |
| Operational cost | none | wasmtime ~10MB binary size |

The 5-10% perf hit is irrelevant for wallet workloads (tx/sec is in single digits, not thousands). The architectural properties matter more than the perf.

---

## 3. Phases

### Brain 1 — Zig host shell + wasmtime embedding (~ 2 days)

**Goal**: a Zig binary that embeds wasmtime, loads two WASM modules from hash-pinned local files, instantiates them in isolated linear-memory sandboxes, and exposes basic lifecycle commands.

**Deliverables**:

1. New crate `runtime/shell/` (Zig binary). Embeds wasmtime via its C API. ~5MB native binary + ~10MB wasmtime = ~15MB total before module loading.

2. Hash-pinned module loader:
   ```zig
   const WALLET_ENGINE_SHA256 = "c091c3adb2cd460159855a43dc5b5dc878107efb0a25b4aae3c61f9b603f713d";
   const HEADERS_VERIFIER_SHA256 = "bf4e...c2a1"; // populated when WH ships

   fn loadModule(path: []const u8, expected_sha256: []const u8) !Module;
   ```
   Refuses to load any binary whose SHA-256 doesn't match the expected hash. Updates require a config change *and* a hash update — no silent module substitution.

3. Module-instance manager: tracks which modules are loaded, their state, last-restart time. Provides `restart(module_name)` for crash recovery.

4. Configuration via `~/.semantos/config.toml`:
   ```toml
   [shell]
   data_dir = "/var/lib/semantos"
   modules_dir = "/usr/share/semantos/wasm"

   [modules.wallet-engine]
   path = "wallet-engine.wasm"
   sha256 = "c091c3..."
   max_memory = "128MB"

   [modules.headers-verifier]
   path = "headers-verifier.wasm"
   sha256 = "bf4e...c2a1"
   max_memory = "256MB"   # holds the chain in memory
   ```

5. Lifecycle CLI:
   ```bash
   semantos init                          # first-run setup
   semantos start                         # daemon mode
   semantos stop
   semantos status                        # show module health, hashes, uptime
   semantos hash <module_name>            # print hash of currently-loaded module
   ```

**Success criterion**: `semantos start` boots the shell, both modules load, `semantos status` reports "all modules healthy" with the correct hashes. Tampering with a WASM file → `semantos start` refuses to launch with explicit hash-mismatch error.

### Brain 2 — Host-import broker (~ 2 days)

**Goal**: the host-side dispatcher that mediates every WASM call out — storage I/O, network I/O, cross-module calls, REPL interactions.

**Deliverables**:

1. `runtime/shell/src/host_broker.zig`. Implements every host import the wallet engine and headers verifier declare:
   - Storage: `host_persist_cell`, `host_load_cell`, `host_unlock_tier` — route to lmdb-backed implementations
   - Crypto: `host_sign`, `host_checksig` — route to bsvz native (full profile)
   - Derivation: `host_derive_leaf`, `host_state_next_index` — route to lmdb-backed DerivationStateStore
   - Network: `host_broadcast_tx`, `host_fetch_header_range` — route to bsvz broadcast clients + multi-source HTTP fetcher
   - Cross-module: `host_verify_beef_root` — wallet engine asks headers verifier for SPV root; broker routes the call across the module boundary

2. Strict policy enforcement at the broker layer:
   - Wallet engine calling `host_fetch_header_range` → denied (not its concern)
   - Headers verifier calling `host_sign` → denied (not its concern)
   - Each module sees only the import surface its responsibilities allow
   - Violations surface in `semantos status` and a structured audit log

3. Storage backing — `runtime/shell/src/lmdb_stores.zig` implementing the `SlotStore` / `DerivationStateStore` / `OutputStore` / `HeaderStore` vtables against an lmdb environment scoped to `~/.semantos/data/`.

4. Audit log — every host import call recorded to `~/.semantos/audit.log` with module name, function, timestamp, args summary (no plaintext secrets). Operator can `tail -f` for real-time visibility into what each module is doing.

5. Conformance test — synthetic wallet-engine call to `host_persist_cell` writes to lmdb; subsequent `host_load_cell` returns the same bytes. Cross-module `host_verify_beef_root` exercises the wallet → broker → headers verifier path.

**Success criterion**: every host import the wallet engine and headers verifier declare has a working broker implementation. Broker correctly enforces module-isolation policy. Audit log accumulates expected entries.

### Brain 3 — TUI REPL (~ 2 days)

**Goal**: an interactive terminal shell where the operator types commands and gets responses. Basic command surface; designed for extensibility.

**Deliverables**:

1. `runtime/shell/src/repl_tui.zig` — line-based TUI built on Zig std (or a minimal `vaxis` / `libvaxis` integration if you want fancy). No mouse, no panels — just `>` prompt, command, response, repeat.

2. Initial command set (v0.1):
   ```
   help                                   list commands
   identity                               show identity pubkey + cert
   balance                                show pocket-change balance per tier
   send <satoshis> to <address>           Tier 0 / 1 / 2 / 3 spend
   anchor "<text>"                        record an arbitrary OP_RETURN cell
   ledger [--since <duration>]            list recent confirmed actions
   recover --device <name>                start recovery handshake for new device
   policy                                 show current policy cell
   policy set tier1_ceiling <sats>        update policy (signs new policy cell)
   sync headers                           force header chain sync
   status                                 module health + tip + sync state
   exit                                   leave REPL
   ```

3. Each command parses input, builds the appropriate BRC-100 method call, dispatches via the host broker into the wallet engine, formats the response. Errors surface as readable text with hints.

4. History persistence — last N commands stored to `~/.semantos/history` so operator gets up-arrow recall across sessions.

5. Tab completion for command names + identity addresses + recently-used recipients.

**Success criterion**: `semantos repl` opens a prompt; `identity` shows the pubkey; `send 1000 to <addr>` produces a Tier 0 spend with broadcast confirmation; `ledger --since "1 hour ago"` shows the spend; history persists across `exit` + re-entry.

### Brain 4 — Remote REPL surfaces (SSH / WSS / HTTP) (~ 1.5 days)

**Goal**: the same REPL accessible remotely — for users who SSH into their VPS, for browser/mobile clients connecting via WSS, for programmatic clients using HTTP.

**Deliverables**:

1. **SSH access**: the operator already gets SSH for free via the VPS. Just document `ssh user@vps semantos repl` as the supported entry point. No code change — the TUI from Brain 3 works over SSH.

2. **WSS endpoint**: `runtime/shell/src/repl_wss.zig`. Listens on `:8090/wallet` (or configurable). Wire format: JSON-RPC matching the BRC-100 spec for wallet-method calls, plus a small extension for shell-only commands (`anchor`, `policy set`, etc.). Authentication via Caddy-fronted TLS + bearer token from `~/.semantos/config.toml`.

3. **HTTP REPL endpoint**: `POST /api/v1/repl` accepts a single command, returns the response as JSON. Useful for scripting, monitoring, automation. Same auth as WSS.

4. **Multi-session safety**: WSS / HTTP sessions are first-class; multiple concurrent clients can query state. Mutating commands serialized through the broker (writes go through one queue). Status responses are read-replicas.

5. The wallet engine itself is single-instance — there's only one wallet on this node. Concurrent reads are fine; concurrent writes serialize. Per-session policies (rate limit, allowed commands) configurable in `config.toml`.

**Success criterion**: SSH-in REPL works (manual test). `wscat` against `wss://vps:8090/wallet` with bearer token gets `{"method": "getPublicKey"}` and returns a valid pubkey. `curl -X POST .../repl -d '{"cmd":"balance"}' -H 'Authorization: Bearer ...'` returns balance JSON.

### Brain 5 — LLM-conversation adapter (optional, ~ 1.5 days)

**Goal**: natural-language input → structured REPL command, sandboxed *outside* the cryptographic trust boundary so the wallet engine validates everything before signing.

**Deliverables**:

1. New `runtime/shell/src/llm_adapter.zig`. Layered above the REPL — LLM is a *translator*, not a privileged actor. The wallet engine's signing path is unchanged.

2. Configurable LLM backend — local llama.cpp endpoint, OpenAI-compatible API, Anthropic API, or none (default). Config in `~/.semantos/config.toml`:
   ```toml
   [llm]
   enabled = false                                # default OFF
   backend = "local"                              # or "openai" or "anthropic"
   endpoint = "http://localhost:8080/completion"
   model = "llama-3.1-8b-instruct"
   ```

3. Translation flow:
   ```
   User input:  "send alice 5 bucks for the pizza"
   LLM call:    parses intent → emits structured command
   Wallet eng:  validates command, prompts for confirmation showing:
                "About to send 7,200 sats (~$5) to alice (02e8...91)
                 with note 'pizza'. Confirm? [y/N]"
   User:        y
   Wallet eng:  Tier 1 unlock prompt → PIN → sign → broadcast
   ```

4. **The trust boundary is explicit**: LLM never signs anything. LLM never sees the user's keys. LLM only translates intent to structured command; the user (or operator) confirms before any cryptographic action. If the LLM hallucinates "send 5000 BTC instead of 5000 sats," the confirmation step catches it.

5. Cost / privacy mode: local backend means no data leaves the VPS; remote backends mean the user's commands transit a third party. Config defaults to OFF; opt-in to enable.

**Success criterion**: with LLM enabled, `> send alice 5 bucks` produces a structured-command preview matching what `> send <sats> to <addr> with note <text>` would produce. User confirms; spend proceeds normally. With LLM disabled, only structured commands work.

### Brain 6 — Deployment recipes (~ 1 day)

**Goal**: drop-in deployment guides for common VPS providers. The user shouldn't have to figure out systemd from scratch.

**Deliverables**:

1. `deploy/docker/` — Dockerfile + docker-compose.yml. Single-container deployment:
   ```yaml
   version: '3'
   services:
     semantos:
       image: semantos/shell:latest
       volumes:
         - ./data:/var/lib/semantos
       ports:
         - "8090:8090"     # WSS REPL
         - "443:443"       # Caddy TLS
       restart: unless-stopped
   ```

2. `deploy/systemd/` — `.service` files for systemd-based distros (Ubuntu, Debian, Arch). Includes Caddy integration for TLS termination.

3. `deploy/nixos/` — NixOS module declaration. Reproducible, atomic deploys.

4. `deploy/ansible/` — playbook for unattended VPS setup. Provisions a fresh Hetzner / Linode / Vultr / DigitalOcean box: installs Caddy, deploys the binary, configures systemd, opens firewall, sets up certbot. Idempotent.

5. `deploy/README.md` — provider-specific quickstarts:
   - "Hetzner CX11 (1 vCPU, 2GB RAM, $5/mo) — `ansible-playbook -i hetzner.ini setup.yml`"
   - Same for Vultr, Linode, DigitalOcean, AWS Lightsail
   - "Self-hosted on a Raspberry Pi 4 — apt-get install semantos, systemd enable, point your domain at the Pi"

6. Cost / sizing matrix:

   | VPS spec | Cost/mo | Headroom |
   |---|---|---|
   | 1 vCPU / 1 GB / 25 GB | $5 | Comfortable for one user, no chain |
   | 1 vCPU / 2 GB / 40 GB | $5-10 | Comfortable with full header chain (~70MB) |
   | 2 vCPU / 4 GB / 80 GB | $20 | Handles dozens of hosted-wallet sessions if you want to share |

**Success criterion**: a user with no Zig / Linux background can follow `deploy/README.md` step-by-step on a fresh Hetzner box and have a working sovereign node serving WSS in under 30 minutes.

---

## 4. Dependency Graph

```
   ┌─── Brain 1 (host shell) ───┐
   │                          │
   ├─── Brain 2 (broker) ────────┤
   │                          │
   ├─── Brain 3 (TUI REPL) ──────┼──► Brain 4 (remote surfaces)
   │                          │           │
   │                          │           ▼
   │                          │       Brain 5 (LLM adapter, optional)
   │                          │
   └─── Brain 6 (deployment recipes) ◄─ depends on Brain 4 for the WSS port
```

Brain 1 + Brain 2 are the foundation (must be done first). Brain 3 is the user surface. Brain 4 extends to remote. Brain 5 is optional. Brain 6 packages everything for deployment.

---

## 5. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| Brain 1 — Host shell + wasmtime | 2 days | Medium — wasmtime C-API embedding has some learning curve |
| Brain 2 — Host-import broker | 2 days | Medium — every host import needs an implementation; isolation policy enforcement |
| Brain 3 — TUI REPL | 2 days | Low — terminal I/O + command dispatch |
| Brain 4 — Remote surfaces | 1.5 days | Low — WebSocket framing on Zig is the only piece worth scoping |
| Brain 5 — LLM adapter (optional) | 1.5 days | Low — adapter pattern, easy to get right |
| Brain 6 — Deployment recipes | 1 day | Low — operations work, mostly YAML/systemd/Ansible boilerplate |

**Total**: ~10 days for one engineer (8 if Brain 5 deferred). Foundational work — every other deployment-side workstream depends on this.

---

## 6. Commit Boundary Plan

One PR per phase:

1. `feat(shell): Brain 1 — Zig host shell with wasmtime + hash-pinned module loader`
2. `feat(shell): Brain 2 — host-import broker + lmdb storage backings + audit log`
3. `feat(shell): Brain 3 — TUI REPL with v0.1 command set`
4. `feat(shell): Brain 4 — WSS + HTTP remote REPL surfaces`
5. `feat(shell): Brain 5 — LLM-conversation adapter (optional, opt-in)`
6. `chore(shell): Brain 6 — Docker / systemd / NixOS / Ansible deployment recipes`

Each is independently mergeable.

---

## 7. Acceptance Criteria

BRAIN is done when:

1. `semantos start` boots cleanly, both modules load with verified hashes, `semantos status` reports healthy.
2. Hash-pinning is enforced — tampering with a WASM file aborts startup with explicit error.
3. Host-import broker correctly mediates all WASM calls; module-isolation policy violations surface in audit log.
4. TUI REPL covers the v0.1 command set; tab completion + history work.
5. WSS endpoint accessible from a remote browser with bearer-token auth.
6. Audit log accumulates entries for every host import call.
7. Single-binary Docker image deploys in one command on Hetzner; `deploy/README.md` walkthrough works for a non-technical operator.
8. Bundle size: shell binary + both WASM modules + wasmtime ≤ 25MB total.
9. Memory footprint: idle wallet uses < 256MB RAM; under load (header sync) < 512MB.

---

## 8. What BRAIN Does Not Cover

- **Site hosting** — that's WSITE (`WALLET-SITE-AS-SOVEREIGN-NODE.md`). BRAIN provides the substrate; WSITE adds the HTTP serving layer.
- **End-user wallet hosting** (multiple users sharing one VPS) — out of scope for v0.1. BRAIN is single-wallet-per-node by default. Multi-tenant is a separate workstream if there's demand.
- **Federated mesh sync** — that's a future WF (Federation) workstream. BRAIN provides the per-node primitive; cross-node sync is its own design.
- **Cross-VPS migration** — backup/restore happens via the v0.4 envelope mechanism; live migration between VPSs is out of scope.
- **GUI** — BRAIN is shell-first by design. A web-based admin UI (browser → WSS → REPL) is in Brain 4; a native desktop GUI is out of scope.

---

## 9. Cross-references

- `core/cell-engine/src/host.zig` — host imports the broker implements
- `core/cell-engine/src/derivation_state.zig`, `slot_store.zig`, `output_store.zig`, `header_store.zig` — vtable interfaces the lmdb stores implement
- `core/cell-engine/WASM-MANIFEST.json` — source of the hash Brain 1 verifies
- `runtime/node/` (W6 placeholder) — superseded by `runtime/shell/`
- `docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md` — WH provides the second WASM module BRAIN loads
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` — WSITE depends on BRAIN as the runtime
- bsvz: `broadcast.WhatsOnChain` / `broadcast.Arc` (network adapter), `crypto.secp256k1` (crypto backings)
- wasmtime C API (the embedding interface)
- lmdb (the storage backend)
