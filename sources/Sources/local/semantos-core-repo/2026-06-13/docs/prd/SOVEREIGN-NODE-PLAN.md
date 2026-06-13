---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SOVEREIGN-NODE-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.679120+00:00
---

# Semantos Sovereign Node — Three-Part Handoff Plan

> Status: planning document. Three independent engineering tracks that together take
> Semantos from "architecturally capable of sovereign nodes" to "curl one URL on a
> fresh VPS and get a running web3 OS." Each part ships as its own PR; each includes
> a self-contained drop-in prompt you can paste into a fresh Claude Code session.

## Background

Semantos is a sovereign-infra platform. The same Zig/WASM cell-engine kernel already
runs at two scales:

- **Embedded profile** — 29 KB, host-provided crypto, four adapter patterns
  (Storage, Identity, Anchor, Network). See `esp32-hackkit/README.md` and
  `core/cell-engine/src/main.zig`.
- **Full profile** — 185 KB, native crypto. See `core/cell-engine/zig-out/bin/`.

The product thesis is a **single adapter matrix** that spans IoT → VPS → full node:

| Adapter      | IoT (esp32-hackkit)         | Edge/VPS (self-hosted)                        | Full node                     |
|--------------|-----------------------------|-----------------------------------------------|-------------------------------|
| **Storage**  | USB, SD, LittleFS, PSRAM    | Local FS, MinIO, UHRP host (self-hosted)      | UHRP cluster, federated       |
| **Identity** | Flash cert, BLE-provisioned | `wallet-toolbox` BRC-100 on disk              | HSM, per-tenant issuance      |
| **Anchor**   | LoRa, ESP-NOW, gateway POST | Direct BSV node, bundled miner gateway        | Own mining/overlay relay      |
| **Network**  | MQTT, ESP-NOW, BLE, mDNS    | MessageBox WSS via `ws-node-adapter`          | Federated peer registry, BRC-56 |

Calhooon's three BSV-on-Cloudflare repos (`bsv-messagebox-cloudflare`,
`bsv-storage-cloudflare`, `dolphinmilk`) are high-quality reference implementations
of the **middle column**. They are not the product; they are one possible backend.
To make the matrix real and the VPS column shippable, three gaps need to close:

1. **ContentStore interface + reference adapters.** There is no first-class,
   package-level storage abstraction today. Each extension that needs off-chain
   blob storage re-invents the contract. Without this, "point your storage adapter
   at whatever you define" is aspirational.
2. **Compact NetworkAdapter for non-IP transports.** `session-protocol` and
   `ws-node-adapter` assume WSS, CBOR with handshake, and full MTUs. The IoT row
   of the matrix (LoRa, ESP-NOW, 6LoWPAN, BLE) needs a connectionless,
   sign-per-frame variant with a ~200-byte envelope.
3. **One-command node installer.** `docker-compose.yml` exists but there is no
   turnkey path from fresh VPS to running sovereign node with identity, wallet,
   storage, messaging, and agent all wired up.

## Scope notes for Claude Code

- **Respect the import-boundary gate.** `tests/gates/import-boundaries.test.ts`
  enforces that `core/` imports nothing outside `core/`, `runtime/` imports only
  `core/` + `runtime/`, `extensions/` imports `core/` + `runtime/` + `extensions/`,
  and `apps/` imports everything except another app. All three parts below respect
  these tiers — re-run the gate test after each change.
- **Use Bun + pnpm-workspaces.** New packages go under the correct tier
  (`core/*`, `runtime/*`, `extensions/*`, `apps/*`, or `packages/*`) and are added
  to `pnpm-workspace.yaml`.
- **Zig/WASM where applicable.** The compact network adapter and the USB-CDN tool
  will eventually want Zig implementations; start in TypeScript where the contracts
  live and Zig-port only the hot paths.
- **Recommended build order.** Part 1 first — it defines a contract the other two
  consume. Parts 2 and 3 are independent of each other.

---

## Part 1 — ContentStore interface + reference adapters

### What exists today

- `extensions/extraction/` contains a fetch/parse/typecheck/infer/commit pipeline
  that implicitly needs blob storage but inlines bespoke file handling.
- `extensions/recovery/src/export-payload.ts` produces export blobs with no
  durable off-chain home.
- `esp32-hackkit/docs/ADAPTERS.md` documents a Storage adapter for ESP32
  (NVS/SPIFFS/LittleFS/SD) but that contract is a C callback table, not a
  TypeScript interface the monorepo shares.
- `src/ffi/tx_builder.zig` and `scripts/anchor-demo.ts` already build BRC-48
  PushDrop advertisements that anchor a 32-byte content hash — the on-chain
  half of content-addressed storage is solved. The off-chain fetch path is not.
- Calhooon's `bsv-storage-cloudflare` is a Rust/WASM UHRP host (BRC-31 auth,
  BRC-29 payment, R2-backed, wire-compatible with `nanostore.babbage.systems`).
  It's the obvious first adapter target for the VPS tier.

### What to build

Create a shared `ContentStore` contract in `core/protocol-types/` and three
reference adapters under `packages/`:

```
core/protocol-types/src/content-store.ts      # interface + types (core-tier, pure)
packages/content-store-uhrp-http/              # UHRP client adapter
packages/content-store-local-fs/               # filesystem adapter
packages/content-store-usb-cdn/                # USB-mounted content-addressed layout
tests/gates/content-store-conformance.test.ts  # shared conformance suite
```

Interface sketch (refine during implementation, but these are the primitives):

```ts
export type Hash = Uint8Array & { readonly __brand: "sha256" }; // 32 bytes
export interface ContentRef {
  hash: Hash;
  sizeBytes: number;
  contentType?: string;
  advertisement?: Advertisement; // BRC-48 PushDrop ad if published on-chain
}
export interface ContentStore {
  put(bytes: Uint8Array, opts?: PutOptions): Promise<ContentRef>;
  get(hash: Hash): Promise<Uint8Array>;
  find(hash: Hash): Promise<ContentRef | null>;
  advertise?(ref: ContentRef, ttlSeconds?: number): Promise<Advertisement>;
}
```

Adapter notes:
- **uhrp-http**: delegate to `@bsv/sdk` + UHRP `/quote`, `/upload`, `/find`,
  `/renew`. Accept a base URL so the same adapter works against
  `nanostore.babbage.systems`, a Cloudflare deploy of `bsv-storage-cloudflare`,
  or a native binary on localhost.
- **local-fs**: store under `{root}/<hash[0:2]>/<hash>`. No advertising by
  default. Verify hash on read.
- **usb-cdn**: same on-disk layout as local-fs but with an optional
  `manifest.json` listing cached hashes, signed by a BRC-52 cert so devices
  on a PAN can verify provenance without internet.

Rewire one concrete consumer:
- `extensions/extraction` must gain a `ContentStore` dependency (injected at
  construction, not imported globally) and use it for at least the
  fetch-raw-document path.

### Acceptance criteria

- [ ] All three adapters implement the same `ContentStore` interface.
- [ ] `tests/gates/content-store-conformance.test.ts` runs the same test vectors
      (put, get-roundtrip, get-missing, hash-verification-on-read) against each
      adapter and passes.
- [ ] `tests/gates/import-boundaries.test.ts` still passes.
- [ ] `bun run check` and `bun run build` still pass.
- [ ] `extensions/extraction` has at least one flow that uses
      `ContentStore` end-to-end, with `content-store-uhrp-http` injected in the
      happy-path test.
- [ ] README for each new package (≤1 page) documents: interface implemented,
      when to choose this adapter, quickstart snippet.

### Drop-in prompt

```text
You are working in the semantos-core monorepo (Bun + pnpm workspaces, strict
import-boundary gate). Your task is to land Part 1 of docs/prd/SOVEREIGN-NODE-PLAN.md:
the shared ContentStore interface and three reference adapters.

Read first:
- docs/prd/SOVEREIGN-NODE-PLAN.md (full context)
- core/protocol-types/src/  (to understand how types are exposed from core)
- tests/gates/import-boundaries.test.ts  (tier rules you must not violate)
- extensions/extraction/src/  (the consumer you will rewire)
- esp32-hackkit/docs/ADAPTERS.md  (the ESP32 Storage adapter contract you should
  spiritually align with — same four operations: put/get/find/advertise)

Deliverable:
1. core/protocol-types/src/content-store.ts — ContentStore, ContentRef, Hash,
   PutOptions, Advertisement types. No runtime dependencies; pure types +
   narrow helpers (hash construction, hash verification). Export from the
   package barrel.
2. packages/content-store-uhrp-http/ — UHRP HTTP client adapter. Configurable
   base URL; supports Babbage's nanostore, a Cloudflare deploy of
   bsv-storage-cloudflare, and localhost. Uses @bsv/sdk for signing.
3. packages/content-store-local-fs/ — filesystem adapter, layout
   {root}/<hash[0:2]>/<hash>. Verify hash on read.
4. packages/content-store-usb-cdn/ — same layout as local-fs, plus optional
   manifest.json signed by a BRC-52 cert.
5. tests/gates/content-store-conformance.test.ts — one shared suite that runs
   put → get → find-missing → hash-tamper-detection against each adapter.
6. Rewire extensions/extraction to inject ContentStore for at least its
   fetch-raw-document path; update its existing tests.
7. One-page README per new package.

Respect:
- Import-boundary gate (tests/gates/import-boundaries.test.ts must stay green).
- pnpm-workspace.yaml must include the new packages.
- bun run check, bun run build, and bun test must all pass.
- Do not introduce a network dependency in conformance tests; the uhrp-http
  adapter is tested against a fake HTTP server or a mock.

Deliver as a single PR titled "feat(content-store): shared interface +
uhrp-http, local-fs, usb-cdn adapters." Include a short PR description that
names which extensions/* consumer was rewired and links to the conformance
test file.
```

---

## Part 2 — Compact NetworkAdapter for non-IP transports

### What exists today

- `runtime/session-protocol/` defines `SessionRuntime`, `MulticastAdapter`,
  `LoopbackAdapter`, `Signer`, `BCAProvider`. IP-native, CBOR envelopes, assumes
  a handshake phase before session traffic.
- `runtime/ws-node-adapter/` implements `NetworkAdapter` over WSS with a
  license-handshake envelope. Full-MTU, connection-oriented.
- `esp32-hackkit/README.md` lists Network backends as MQTT, ESP-NOW, BLE, mDNS
  — most are connectionless; some have byte budgets in the low hundreds.
- Physical constraints worth remembering:
  - 6LoWPAN MTU = 127 bytes on the air (≈80 after fragmentation overhead).
  - LoRa payloads are often 51–242 bytes depending on spreading factor.
  - ESP-NOW payload cap is 250 bytes.
  - BLE advertisement payload is 31 bytes (extended adv up to 255).

### What to build

A new package `runtime/compact-network-adapter/` (or similar) implementing
the same `NetworkAdapter` contract as `ws-node-adapter` but with:

- **Compact CBOR envelope.** Target ≤200 bytes for a signed single-frame
  message. Spec lives in `runtime/compact-network-adapter/docs/envelope.md`.
- **Sign-per-frame, not sign-per-channel.** Every frame carries its own
  BRC-52 cert signature (or a short cert-id reference to a cached cert). No
  session handshake; verification is purely per-message.
- **Fragment-aware.** Messages larger than the transport MTU are split into
  frames with a tiny `(msg_id, frag_idx, frag_count)` header. Reassembly with a
  small bounded buffer and a timeout.
- **Transport-agnostic.** The package itself does not speak LoRa/ESP-NOW/BLE.
  It exposes a `Transport` seam:
  ```ts
  interface Transport {
    mtu: number;
    send(frame: Uint8Array): Promise<void>;
    onFrame(cb: (frame: Uint8Array) => void): () => void;
  }
  ```
  Ship one reference `Transport` implementation (loopback with configurable
  MTU) and one mock 6LoWPAN transport (127-byte MTU) for tests.

The `SessionRuntime` state machine must work unchanged against this adapter.
This is the key property: swapping the adapter swaps the physical layer, not
the protocol above it.

### Acceptance criteria

- [ ] `runtime/compact-network-adapter/` package exists and builds.
- [ ] `runtime/compact-network-adapter/docs/envelope.md` documents the CBOR
      envelope schema with byte-budget breakdown.
- [ ] A single signed "ping" message fits in ≤200 bytes when serialised.
- [ ] Fragmentation test: a 1 KB message across a 127-byte-MTU transport is
      reassembled correctly, with a negative test for dropped/out-of-order
      fragments.
- [ ] `session-protocol`'s existing session tests pass when injected with the
      compact adapter (prove via a new test file that imports the existing
      session-protocol test vectors and runs them against both adapters).
- [ ] Every frame is independently verifiable — no state required across
      frames except the reassembly buffer.
- [ ] Import-boundary gate, `bun run check`, `bun run build`, and
      `bun test` all pass.

### Drop-in prompt

```text
You are working in the semantos-core monorepo. Your task is to land Part 2 of
docs/prd/SOVEREIGN-NODE-PLAN.md: a compact, connectionless NetworkAdapter for
non-IP transports (LoRa, ESP-NOW, 6LoWPAN, BLE).

Read first:
- docs/prd/SOVEREIGN-NODE-PLAN.md (full context)
- runtime/session-protocol/src/  (the contract you must satisfy)
- runtime/ws-node-adapter/  (the existing full-MTU reference; your new
  package is its non-IP sibling, not a replacement)
- esp32-hackkit/README.md and esp32-hackkit/docs/  (the IoT backends this
  adapter exists to serve)

Physical constraints to design against:
- 6LoWPAN ≈80-byte payload
- LoRa 51–242 bytes
- ESP-NOW 250 bytes
- BLE adv 31 bytes (extended 255)

Deliverable: a new package runtime/compact-network-adapter/ that:

1. Exports a NetworkAdapter implementation compatible with SessionRuntime.
2. Uses a compact CBOR envelope. Target: a signed single-frame message ≤200
   bytes. Document the schema in
   runtime/compact-network-adapter/docs/envelope.md, with a byte-budget table.
3. Signs every frame independently (BRC-52 cert signature or short cert-id
   reference to a cached cert). No handshake.
4. Implements fragmentation/reassembly over arbitrary-MTU transports using a
   (msg_id, frag_idx, frag_count) tiny header. Bounded reassembly buffer with
   timeout.
5. Exposes a Transport seam so the adapter is transport-agnostic:
     interface Transport {
       mtu: number;
       send(frame: Uint8Array): Promise<void>;
       onFrame(cb: (frame: Uint8Array) => void): () => void;
     }
   Ship two reference Transports:
     - loopback (configurable MTU)
     - mock-6lowpan (127-byte MTU)
6. Conformance test: run runtime/session-protocol's existing session vectors
   against BOTH ws-node-adapter (existing) and compact-network-adapter (new).
   The same state machine must pass on both.
7. Targeted tests:
     - envelope-size.test.ts — assert signed ping ≤200 bytes
     - fragmentation.test.ts — reassembly on 127-byte MTU, including
       out-of-order and lost fragments

Respect:
- Do not change session-protocol's public contract. If you need a new hook,
  propose it as a follow-up PR rather than bundling it here.
- Import-boundary gate, bun run check, bun run build, bun test must pass.
- TypeScript first. A Zig port of the envelope codec is a follow-up.

Deliver as a single PR titled "feat(compact-network-adapter): sign-per-frame
NetworkAdapter for non-IP transports." PR description must include the final
envelope size number for a signed ping and a link to envelope.md.
```

---

## Part 3 — One-command sovereign node installer

### What exists today

- `docker-compose.yml` and `docker-compose.hackathon.yml` at the repo root.
- `runtime/node/` — the Semantos node daemon with admin API and CLI.
- `runtime/shell/` — REPL + one-shot CLI with 30+ verbs.
- `runtime/peer-locator/` — `StaticPeerLocator` + `DnsPeerLocator`
  (`_semantos-node.<host>` TXT records with injectable resolver + TTL cache).
- `runtime/ws-node-adapter/` — WSS transport with license-handshake and
  `/.well-known/semantos-node` discovery.
- `runtime/services/` — renderer-agnostic stores (IdentityStore, ConfigStore,
  etc.) shared across UIs.

There is no end-to-end flow that goes from fresh VPS → working node with
identity, wallet, storage, messaging, and agent all wired up. That's what we
ship.

### What to build

Target UX: on a clean Ubuntu 22.04 $5-tier VPS (Hetzner, DigitalOcean, etc.):

```sh
curl -fsSL https://get.semantos.sh | sh
```

produces, in ≤5 minutes:
- Docker installed (if not present).
- All services pulled and running via `docker-compose.node.yml`.
- BRC-100 wallet created on disk.
- BRC-52 identity cert generated.
- `_semantos-node.<host>` DNS TXT record published if DNS creds provided
  (optional; skip silently otherwise).
- Health check passing at `http://<host>:<port>/.well-known/semantos-node`.
- Final output prints identity key + node URL.

Concrete deliverables:

1. **`docker-compose.node.yml`** — authoritative compose file for a Semantos
   node. Services:
   - `semantos-node` — `runtime/node` daemon.
   - `messagebox` — containerised build of `bsv-messagebox-cloudflare` via
     `wasmtime` (Workers WASM served behind an HTTP frontend) OR a native
     Rust build if upstream exposes one. Prefer native; fall back to WASM.
   - `uhrp` — same pattern for `bsv-storage-cloudflare`.
   - `wallet` — embedded BRC-100 wallet daemon (based on `wallet-toolbox`;
     spiritually modelled on dolphinmilk's embedded-wallet pattern).
   - `bsv-headers` — SPV header cache.
   - (Volumes for SQLite + blob storage; shared Docker network.)
2. **`scripts/install.sh`** — Bash installer. Detects distro, installs
   Docker + Docker Compose if missing, clones / pulls the `node-installer`
   package, runs `first-boot.ts`, starts compose, tails health check,
   prints summary. Idempotent: re-running is a no-op if already installed.
3. **`apps/node-installer/`** — new app under `apps/` tier. Contains
   `first-boot.ts` (TypeScript, runs via Bun) which:
   - Generates `.env` with strong random secrets.
   - Creates `~/.semantos/wallet.json` via `wallet-toolbox`.
   - Issues a BRC-52 identity cert and persists it.
   - Writes a `_semantos-node.<host>` TXT record via a pluggable DNS
     provider (Cloudflare API first; others are stubs).
   - Blocks until `docker compose` health checks pass.
   - Prints identity key, node URL, admin token.
4. **Health check endpoint** on `semantos-node` that pings each peer service
   and returns a JSON roll-up: `{ messagebox: "ok", uhrp: "ok", wallet: "ok",
   headers: "ok" }`. Surface it as `http://<host>:<port>/healthz`.
5. **`semantos node` shell verbs** in `runtime/shell/`:
   - `semantos node up` — wrapper around compose up, runs first-boot if
     needed.
   - `semantos node status` — pretty-prints the healthz roll-up.
   - `semantos node identity` — prints the BRC-52 cert + BRC-100 pub key.
6. **Integration test** that runs the full flow against a Docker-in-Docker
   CI runner and asserts healthz green within 3 minutes.

### Acceptance criteria

- [ ] `curl -fsSL https://get.semantos.sh | sh` on a fresh Ubuntu 22.04
      produces a working node in ≤5 minutes wall-clock.
- [ ] Final output contains: identity key (hex), node URL, admin token,
      healthz URL.
- [ ] `semantos node status` prints all four services green.
- [ ] DNS publishing is optional and silently skipped if no creds are given.
- [ ] `docker compose -f docker-compose.node.yml down` cleanly stops
      everything; `up` is idempotent.
- [ ] CI integration test passes reliably (3 runs, 0 flakes).
- [ ] Import-boundary gate, `bun run check`, `bun run build`, `bun test`
      all pass.

### Drop-in prompt

```text
You are working in the semantos-core monorepo. Your task is to land Part 3 of
docs/prd/SOVEREIGN-NODE-PLAN.md: a one-command installer that turns a fresh
Ubuntu 22.04 VPS into a running sovereign Semantos node.

Read first:
- docs/prd/SOVEREIGN-NODE-PLAN.md (full context, especially the service list)
- docker-compose.yml and docker-compose.hackathon.yml
- runtime/node/ (the daemon you will containerise)
- runtime/shell/ (where the new `semantos node *` verbs go)
- runtime/peer-locator/src/ (DnsPeerLocator — the _semantos-node.<host> TXT
  record format you must publish to)
- runtime/ws-node-adapter/ (/.well-known/semantos-node shape)

Target UX:
  curl -fsSL https://get.semantos.sh | sh
…on a clean Ubuntu 22.04 $5 VPS, produces in ≤5 minutes a running node with
identity, wallet, storage, messaging, and agent all wired up.

Deliverables:

1. docker-compose.node.yml at repo root. Services: semantos-node, messagebox,
   uhrp, wallet, bsv-headers. Shared network; named volumes for SQLite and
   blob storage. Healthchecks on every service. Upstream images:
     - messagebox: prefer a native Rust build of bsv-messagebox-cloudflare;
       fall back to a Worker-WASM running under wasmtime behind an HTTP
       frontend. Document the choice in a comment in the compose file.
     - uhrp: same pattern for bsv-storage-cloudflare.
     - wallet: wallet-toolbox-based BRC-100 daemon.
   If upstream images don't exist yet, publish minimal Dockerfiles under
   packages/docker/<service>/ and reference those.

2. scripts/install.sh — Bash, idempotent. Detects distro, installs Docker +
   Compose if missing, fetches or updates the installer, runs first-boot,
   brings up compose, blocks on healthz, prints summary. Test on a fresh
   Ubuntu 22.04 container.

3. apps/node-installer/ — new app tier package.
   - src/first-boot.ts: generates .env, creates wallet via wallet-toolbox,
     issues BRC-52 identity cert, optionally publishes DNS TXT record via
     Cloudflare (pluggable DNS provider), blocks until healthz green,
     prints summary.
   - bin/semantos-first-boot.ts: Bun entrypoint.

4. Healthz endpoint on semantos-node (runtime/node/): GET /healthz returns
   { messagebox, uhrp, wallet, headers: "ok"|"degraded"|"down" } with a top-
   level status. Surfaces downstream healthchecks by HTTP pinging each peer.

5. runtime/shell/ verbs:
   - `semantos node up` — wraps compose up, runs first-boot if state file
     absent.
   - `semantos node status` — pretty-prints /healthz.
   - `semantos node identity` — prints the BRC-52 cert + BRC-100 pub key.

6. Integration test apps/node-installer/__tests__/full-boot.test.ts that
   spins the stack up in Docker-in-Docker and asserts healthz green within
   3 minutes. Must pass 3 consecutive runs without flakes.

Respect:
- Tier rules: node-installer goes under apps/, never imports another app.
- DNS provider must be pluggable; Cloudflare is the first implementation but
  the interface accepts a `DnsProvider` seam.
- The installer must succeed end-to-end with NO DNS creds provided (DNS step
  is silently skipped, everything else works on the IP).
- Do not embed secrets in the repo or in any published image.
- bun run check, bun run build, bun test, and the import-boundary gate must
  all pass.

Deliver as a single PR titled "feat(node-installer): one-command sovereign
Semantos node." PR description must include:
  - Timed output of a fresh-VPS install from a CI job (≤5 min).
  - Screenshot or transcript of `semantos node status` showing all green.
  - Link to the healthz schema.
```

---

## Ordering and handoff notes

- **Build Part 1 first.** Parts 2 and 3 both benefit from having a shared
  `ContentStore` contract in place. Part 3's UHRP service, in particular, is
  wired into `semantos-node` through the `content-store-uhrp-http` adapter.
- **Parts 2 and 3 are independent.** Assign them in parallel once Part 1 is
  merged.
- **Each part is one PR.** Resist the urge to bundle. The review surfaces are
  different (types + adapters vs. protocol + codec vs. ops + installer).
- **Don't chase the IoT story yet.** 6LoWPAN/ESP-NOW/BLE *transports* are
  follow-ups after Part 2 lands the compact adapter. The esp32-hackkit repo
  is where those transport implementations will live, not here.
- **Don't chase x402 yet.** Pay-per-inference for outbound LLM calls is a
  natural fourth workstream (agent-tier) but sits cleanly on top of this
  foundation; it doesn't need to block shipping the VPS-tier node.

### Suggested milestone phrasing

- **M1 (Part 1 merged):** Semantos has a shared content-addressed storage
  contract with three adapters. Extractions round-trip through UHRP.
- **M2 (Part 2 merged):** The same session-protocol state machine runs over
  a 200-byte envelope on a 127-byte-MTU transport. IoT is no longer blocked
  on protocol.
- **M3 (Part 3 merged):** `curl get.semantos.sh | sh` produces a sovereign
  node. You can demo it on a $5 VPS in a pitch meeting.
