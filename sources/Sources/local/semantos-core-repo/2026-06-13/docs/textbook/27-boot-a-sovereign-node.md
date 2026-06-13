---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/27-boot-a-sovereign-node.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.644642+00:00
---

# Boot a Sovereign Node

Part VIII of this textbook has one purpose: the reader finishes with a running sovereign node on their own machine. This chapter works through every step required to get there. The chapter is deliberately long. It covers infrastructure, identity provisioning, kernel initialisation, and the adapter stack in the order the boot sequence demands them. Each step cites the protocol invariants it exercises and the Unification Matrix deliverables it depends on.

The boot sequence defined in `docs/spec/protocol-v0.5.md` §2.3 contains fifteen steps. Steps 1–7 are fully enforced in the current implementation. Steps 8–15 work end-to-end in feasibility but are not yet operating under complete BRC verification across every adapter surface; each such step is tagged with its governing Unification Matrix deliverable.

---

## Prerequisites

Before running any commands, confirm the following are present on the host machine:

| Requirement | Minimum version | Purpose |
|---|---|---|
| Docker | 24.x | Container runtime for all node services |
| Docker Compose v2 | 2.24.x | Orchestrates the multi-service stack |
| Bun | 1.1.x | Runs the installer and shell verbs |
| pnpm | 9.x | Workspace package manager (installer uses it) |
| Git | 2.40.x | Fetches the `semantos-core` repository |
| Internet access | — | Required for image pulls and BSV overlay during first boot |
| A port available on 4000 and 4001 | — | Node daemon and Helm bind these by default |

The installer (`scripts/install.sh`) will check each of these and print an actionable error message if any are absent. The steps below assume you are working inside a clone of `semantos-core` with the workspace dependencies installed (`pnpm install` at the root).

### Identity prerequisites

You will need:
- An email address that serves as the anchor for the Plexus challenge-set derivation.
- Answers to three or more challenge questions (the default set is prompted interactively during step 1).

No BSV wallet balance is required for steps 1–7. Steps requiring on-chain operations (capability token minting in step 6, and the metered cashlanes of step 14) require a funded wallet; the installer provisions a testnet wallet automatically during a local boot.

---

## The 15-Step Boot Sequence

The table below summarises the status of each step at the time of writing. Steps marked "enforced" run under full protocol verification in the current implementation. Steps marked "feasibility" work end-to-end but are gated on specific Unification Matrix deliverables before they reach production enforcement.

| Step | Description | Status |
|---|---|---|
| 1 | Email + challenge-set input | Enforced |
| 2 | PBKDF2 root-seed derivation | Enforced |
| 3 | BRC-52 cert derivation | Enforced |
| 4 | BCA computation via shared library | Enforced |
| 5 | Plexus vendor SDK initialises tenant nodes | Enforced |
| 6 | Capability domain mints initial UTXOs | Enforced |
| 7 | Cell engine boots; `kernel_set_enforcement(1)` | Enforced |
| 8 | Verifier Sidecar starts | Feasibility |
| 9 | World Host starts authoritative regions | Feasibility |
| 10 | Mesh adapter joins multicast group | Feasibility |
| 11 | Helm binds localhost | Feasibility |
| 12 | Adapters subscribe to tick, identity, and capability feeds | Feasibility |
| 13 | Recovery payload backed up | Feasibility |
| 14 | Metered services open MFP cashlanes | Feasibility |
| 15 | User online, sovereign, federated | Feasibility |

---

### Step 1 — Email and challenge-set input

The first action the boot sequence requires is the user supplying their email address and providing answers to a challenge set. The email is not transmitted to any server in the derivation path; it is used, together with a per-deployment salt, to construct the deterministic PBKDF2 salt that anchors the user's root seed. Neither the email nor the challenge answers leave the device.

The challenge set is a minimum of three question-answer pairs drawn from a pool defined by the deployment. The answers are normalised (lowercased, whitespace-collapsed) before any cryptographic operation. The Plexus recovery substrate stores only SHA-256 hashes of normalised challenge answers, never the answers themselves, and applies the same brute-force mitigations documented in `docs/spec/protocol-v0.5.md` §6.5: a maximum of ten recovery-initialisation attempts per hour, and an account lock after five consecutive incorrect challenge answers.

During `first-boot.ts`, the installer presents this prompt interactively:

```bash
semantos node up
```

If the node state file (`~/.semantos/state.json`) is absent, `node up` detects a fresh install and invokes `first-boot.ts` before bringing up the Docker Compose stack. The first-boot flow asks:

```text
Semantos first-boot
===================
Email address: <user types>
Challenge question 1 (What city were you born in?): <user types>
Challenge question 2 (What was the name of your first school?): <user types>
Challenge question 3 (What is the name of your oldest sibling?): <user types>
```

The answers are held in memory only. They are not written to disk at any point. The first-boot process uses them immediately in step 2 and discards them from memory when derivation is complete.

This step exercises no kernel invariants directly, but it establishes the only secret that can regenerate the entire identity DAG. The challenge-set quality directly governs the strength of the PBKDF2 salt entropy.

---

### Step 2 — PBKDF2 root-seed derivation

With the challenge answers in memory, the first-boot process runs PBKDF2:

- Hash function: SHA-256
- Iterations: 100 000 (the protocol minimum per `docs/spec/protocol-v0.5.md` §4.1)
- Salt: `SHA-256(email || deployment_salt)`, where `deployment_salt` is a 32-byte value shipped with the installer
- Output length: 32 bytes

The root seed never leaves the device. The PBKDF2 operation runs entirely in the Bun process. The output is a 256-bit secret that deterministically regenerates every key the identity DAG ever needs.

The 100 000-iteration floor exists to impose a computational cost on offline dictionary attacks. An attacker who compromises the recovery payload (which the server holds) and applies it to a brute-force search over challenge answers must spend approximately 100 000 SHA-256 operations per candidate. At modern GPU throughput that remains a meaningful obstacle for typical challenge-answer entropy.

The root seed is produced once per boot and held in a sealed memory buffer until step 3 completes. It is not serialised to disk at any point in the current implementation.

---

### Step 3 — BRC-52 cert derivation

From the root seed, the first-boot process derives the user's root BRC-52 certificate using the BRC-42 key derivation scheme (BSV Key Derivation Scheme, BKDS). The derivation is deterministic: the same root seed always produces the same root cert.

The BRC-52 certificate carries:

| Field | Value at this step |
|---|---|
| `subject` | 33-byte compressed secp256k1 public key derived from root seed |
| `issuerCertId` | null (this is the root cert) |
| `appId` | deployment-specific 32-byte namespace identifier |
| `childIndex` | 0 (root) |
| `createdAt` | current timestamp in milliseconds |
| `domainFlags` | empty at root issuance; populated when specific domain authority is needed |
| `signature` | self-signed at the root using the SIGNING domain flag (`0x02`) |

The `cert_id` is `SHA-256(canonical_preimage)` over all fields except `signature`. This 32-byte value is the durable identifier for this identity in the Plexus DAG. It is written to `~/.semantos/cert.json` as part of step 3, which is the first write to disk in the boot sequence.

Step 3 exercises kernel invariant K2: any state-changing transition requires successful identity verification. The cert issuance itself is a state transition on the identity DAG, and it must succeed before any downstream operation that carries the cert's authority can proceed.

---

### Step 4 — BCA computation via the shared BCA library

The BCA (Blockchain Channel Address) is a deterministic IPv6-shaped address derived from `cert_id`. It serves two roles: peer identifier in the mesh (step 10), and channel-funding key for MFP payment channels (step 14).

The derivation is implemented in `core/cell-engine/src/bca.zig` and mirrored in a TypeScript package by deliverable D-A0 of the Unification Matrix. The computation is:

```bash
# Illustrative — the BCA library is invoked internally by first-boot.ts
semantos identity bca
# → fd12:3456:789a:bc01:2345:6789:abcd:ef01 (example; your output will differ)
```

The BCA derivation MUST produce an IPv6 address byte-identical to the Zig reference implementation for all conformance vectors in `core/cell-engine/tests/vectors/bca_*.json`. This byte-identity requirement means the TypeScript mirror cannot diverge from the Zig implementation even in endianness handling. Both implementations are tested against the same vector set on every CI run.

At this step, the node's identity is fully determined:

- Root seed → (via PBKDF2) → challenge-set entropy
- Root seed → (via BRC-42) → `cert_id`
- `cert_id` → (via BCA library) → mesh peer address

None of these values require network access. All three are derivable offline, reproducibly, from the challenge answers alone.

---

### Step 5 — Plexus vendor SDK initialises tenant nodes locally

The Plexus vendor SDK (U2 in the substrate) initialises tenant nodes using the `cert_id` from step 3. This step:

1. Loads the cert from `~/.semantos/cert.json`.
2. Configures tenant-node records in the local SQLite store (`~/.semantos/plexus.db`).
3. Establishes the identity DAG structure for child cert issuance (which will be needed when the node issues capability tokens in step 6).
4. Sets the `childIndex` ceiling used by monotonic enforcement: child indices issued after this point must increment strictly and must never be reused.

The monotonic guarantee is one of the stronger safety properties in the substrate. `docs/spec/protocol-v0.5.md` §13.2 states the constraint: child indices, rotation indices, and state versions must be strictly monotonic, only increase, and must never be reused. Any attempt to use a previous `childIndex` or state version must be rejected as a cryptographic-integrity violation. The Plexus SDK enforces this at the database layer with an append-only constraint on the index column.

At the end of step 5 the local Plexus tenant-node record is initialised. The node is not yet connected to any external Plexus service; the SDK runs in offline mode using the local SQLite store as its state backend. External connectivity is added in step 12 when the adapters subscribe to the identity event stream.

---

### Step 6 — Capability domain mints initial UTXOs

The capability domain (U4) mints the node's initial set of capability tokens as BRC-108 UTXOs. These are the authorisation resources that gate every subsequent operation in the stack.

A capability token is a UTXO formatted per BRC-108, bound to the `cert_id`'s subject public key, and classified as a LINEAR semantic resource. Spending the UTXO is the consumption proof; the spending transaction is the on-chain record of revocation. The initial set minted during first boot includes:

| Capability class | Purpose |
|---|---|
| `cap.recovery` | Authorises recovery-session initiation |
| `cap.permission` | Authorises general permission grants to child identities |
| `cap.data_access` | Authorises read access to encrypted cell payloads |

This step exercises kernel invariant K1: a LINEAR cell is consumed exactly once, never duplicated, never discarded. Capability tokens are the concrete instantiation of K1 semantics at the on-chain layer. Each token can be spent (consumed) exactly once. If a capability token is presented to the cell engine as already consumed, the engine detects the violation via `OP_ASSERTLINEAR` (`0xC5`) and triggers an immediate state rollback — K4 (failed Plexus opcodes leave the PDA state byte-for-byte unchanged) ensures nothing is partially applied.

During local first boot, the installer provisions testnet UTXOs via a funded wallet bundled with the `apps/node-installer` package. The first-boot script creates `~/.semantos/wallet.json` using `wallet-toolbox` and records the UTXO set in the local SQLite store. The wallet file is encrypted at rest using a key derived from the root seed.

```bash
# first-boot.ts does this internally; you can inspect the result:
semantos node identity
# Outputs cert_id (hex) and initial capability UTXO set
```

Step 6 also exercises kernel invariant K3 — domain flag enforcement. The capability mint operation is permitted only within the domain-flag namespace authorised for the capability domain (U4). The cell engine evaluates `OP_CHECKDOMAINFLAG` (`0xC6`) against the minting transaction's domain flag before accepting the mint. A token whose domain flag falls outside the authorised range is rejected at the kernel gate. The Lean mechanised proof of K3 (`DomainIsolationK3.lean`) covers this total-and-correct property.

---

### Step 7 — Cell engine boots; `kernel_set_enforcement(1)`

This is the last fully-enforced step. When the cell engine boots and `kernel_set_enforcement(1)` is called, the kernel begins enforcing all active invariants at the bytecode gate. Before this call, opcodes that would trigger K1 or K4 are evaluated but violations are logged rather than halted. After this call, violations are hard failures that leave state byte-for-byte unchanged (K4).

The call sequence:

```bash
# From apps/node-installer/src/first-boot.ts:
# kernel.kernel_init()
# kernel.kernel_load_script(scriptBytes, len)
# kernel.kernel_set_enforcement(1)
# kernel.kernel_execute()
```

The WASM module exports `kernel_set_enforcement(enabled)` as part of the WASM interface contract defined in `docs/spec/protocol-v0.5.md` §8.3. The host — the Bun process running the node daemon — calls this after confirming that the BRC-52 cert, the BCA, and the capability UTXOs are all in a valid initial state. Calling `kernel_set_enforcement(1)` with any of those in an invalid state would cause every subsequent cell execution to fail immediately at the K1 or K2 gate.

Step 7 exercises all five of the kernel invariants this chapter must cite:

- K1: linearity enforcement is now active. LINEAR capability tokens cannot be double-spent.
- K2: identity verification is now enforced on every state-changing transition.
- K3: domain flag checks are now total and correct at the bytecode gate.
- K4: any opcode failure leaves PDA state byte-for-byte unchanged.
- K5: execution terminates within `opcountLimit` steps (default 1 000 000 opcodes). Unbounded loops cannot form because the 2-PDA has no loop or jump opcodes; termination is structural.

With step 7 complete, the node has a verified identity, a funded capability domain, and an enforcing kernel. The remaining steps extend the node into the network — attaching the Verifier Sidecar, the World Host, the mesh adapter, and Helm.

---

### Step 8 — Verifier Sidecar starts

(Currently in feasibility — full enforcement scheduled with deliverable D-V1 from the Unification Matrix.)

The Verifier Sidecar is the runtime gate that turns BRC-100 signed envelope verification, BRC-52 cert authenticity checks, identity binding, and capability UTXO SPV checks into a single chokepoint at every adapter boundary. Without the Verifier Sidecar, adapter boundaries are unverified; each adapter must implement its own checking independently, which is the condition the sidecar is designed to eliminate.

The recommended deployment topology is the per-node sidecar process (per the Unification Roadmap §8 Q3 resolution). The sidecar runs as an independent process on the same host, independently deployable and independently observable. This means a security patch to the sidecar can be applied without releasing any adapter.

When `docker compose up` is run (step described below in the happy path), the `semantos-node` container brings up the sidecar as a companion process:

```bash
docker compose -f docker-compose.node.yml up
```

The sidecar listens on a local Unix socket. Each adapter that performs a cross-process or cross-node operation routes the SignedBundle envelope through the sidecar before processing the payload. The sidecar performs:

1. BRC-100 signature verification against the sender's identity key.
2. BRC-52 cert authenticity check (cert is well-formed, not expired, signature valid).
3. Identity binding: the signing key matches `certificate.subject`.
4. SPV checks for any capability UTXOs referenced in the envelope.

At the feasibility stage, the sidecar performs all four checks but is not yet wired into every adapter surface. Deliverable D-V3 of the Unification Matrix wires the sidecar into the first adapter (World Host) as the integration template; subsequent deliverables extend it surface by surface per the Phase 1b parallel track.

---

### Step 9 — World Host starts authoritative regions

(Currently in feasibility — full enforcement scheduled with deliverables D-A1, D-C1, and D-Dcap-world from the Unification Matrix.)

World Host is the Plexus well-known domain for authoritative region management (domain flag `0x0B`, mnemonic `EXPERIENCE`, per the Unification Roadmap §8 Q1 resolution). If the node configuration includes a World Host component, it starts and begins accepting connections in step 9.

Each region within World Host represents an authoritative simulation or coordination space. Entities within a region exist as cells in the VFS; each WorldTick advances the region's hash chain, producing a new state snapshot. The region tick chain is one of the four named hash-chain scopes (cell, region, channel, domain) described in chapter 19.

At the feasibility stage, World Host starts and accepts WebSocket connections, but the BRC-52 cert requirement at connect time and the `cap.experience` UTXO gate at join time are not yet fully enforced under proper BRC verification. Deliverable D-Dcap-world gates the full capability enforcement.

For a minimal sovereign node installation — one that does not host a World Host region — step 9 is skipped. The installer's configuration file controls which services are included:

```bash
# docker-compose.node.yml excerpt (illustrative)
services:
  semantos-node:
    image: semantos/node:latest
    # World Host is optional; set WORLD_HOST_ENABLED=false to skip
    environment:
      - WORLD_HOST_ENABLED=false
```

---

### Step 10 — Mesh adapter joins the multicast group

(Currently in feasibility — full enforcement scheduled with deliverable D-C6 from the Unification Matrix.)

The mesh adapter uses the BCA computed in step 4 as the node's peer identifier. In step 10, the mesh adapter joins the IPv6 multicast group derived from `cert_id`. The default mapping is `ff02::1` (one group, software demux); the Phase 34 mapping derives a distinct group per type hash for transport-level filtering.

Every cross-node message is a SignedBundle envelope, encoded as CBOR, carrying the sender's `cert_id`, a BRC-100 signed payload, and a BRC-52 certificate reference. The Verifier Sidecar (step 8) verifies each envelope before it reaches the receiving adapter.

At the feasibility stage, the mesh adapter joins the multicast group and transmits frames, but the SignedBundle wrap on every mesh frame is not yet consistently enforced. Deliverable D-C6 is a five-line change inside the codec port introduced by the monolith-refactor Prompt 38; it wraps every multicast frame in SignedBundle format, closing the transport-axis gap for the mesh substrate component (U6).

The mesh's heartbeat mechanism uses the BCA as the peer identifier in the heartbeat payload. Peer discovery runs via heartbeats; once a remote node's BCA is resolved to an endpoint, the session-protocol layer can form a session. The six-piece session skeleton (discovery, formation, runtime, broadcast, transport, metering hook) is described in `docs/spec/protocol-v0.5.md` §12.3.

---

### Step 11 — Helm binds localhost

(Currently in feasibility — full enforcement scheduled with deliverables D-A3 and D-C3 from the Unification Matrix.)

Helm is the convergence surface: the three-panel workbench where all adapter outputs are visible in a unified view. In step 11, Helm's server-side process binds `localhost:4001` (configurable) and presents the workbench to the browser.

At the feasibility stage, Helm starts and renders correctly, but it does not yet route all backend calls through the Plexus Network SDK (deliverable D-C3), and it does not yet boot after the Plexus identity has issued a cert that it uses to authorise its own backend calls (deliverable D-A3). Both are Phase 1b and Phase 2 deliverables respectively.

The practical consequence: Helm works fully for users running a local node where all services are on the same host. Federation scenarios — where Helm connects to a remote node — require the SignedBundle envelope enforcement that D-C3 provides.

---

### Step 12 — Adapters subscribe to tick, identity, and capability feeds

(Currently in feasibility — full enforcement scheduled with deliverables in the Phase 2 and Phase 3b tracks of the Unification Matrix.)

Step 12 is where transport (unification axis C) and time (axis E) compose. Each adapter subscribes to three streams:

1. Its region's PubSub topic for tick deltas (transport + time compose here).
2. The Plexus identity and edge event stream (cross-surface change feed).
3. The capability UTXO change feed (auth state updates when capability tokens are spent or new ones are minted).

All three streams use the same SignedBundle envelope format carrying the same provenance metadata: BCA, `cert_id`, hash-chain sequence number. This uniformity is the operational definition of unification rendered concrete. An adapter that subscribes to all three streams with a consistent envelope format participates in axes A (identity), B (storage via hash chain), C (transport), D (type enforcement via linearity on tick cells), and E (time via hash chains advancing).

At the feasibility stage, adapters subscribe to the PubSub topics but the SignedBundle enforcement is not consistent across all surfaces. The Phase 2 deliverables (D-C1 through D-C8) close this gap surface by surface.

---

### Step 13 — Recovery payload backed up to the Plexus Recovery Service

(Currently in feasibility — full enforcement scheduled with deliverables D-F1 through D-F7 from the Unification Matrix Phase 5 track.)

The recovery payload is a BRC-100-signed JSON blob, approximately 3.4 KB compressed, that contains enough derivation-state information to reconstruct the full identity DAG on a new device, provided the user can supply their original challenge answers.

The payload contains: derivation states, domain ceilings, edge backup recipes (BRC-69 key linkage revelations), tenant path steps, and schema mappings. It does not contain raw private keys, root seeds, or plaintext challenge answers. An attacker with full server access and the recovery payload cannot impersonate the user — they would still need the challenge answers to derive the root seed (step 2) and reconstruct any key.

At the feasibility stage, the first-boot installer generates a recovery payload and writes it locally to `~/.semantos/recovery.json`. The upload to the Plexus Recovery Service requires network connectivity and an enrolled recovery endpoint; the installer includes a stub that prints the upload URL but does not block boot if the upload fails.

The four-phase recovery flow (email OTP, challenge-response, payload export, client-side reconstruction) is described in full in chapter 21. The threshold recovery path for high-security roots (Shamir Secret Sharing, t-of-n fragmentation) is also covered there.

---

### Step 14 — Metered services open MFP cashlanes

(Currently in feasibility — full enforcement scheduled with deliverables D-G1, D-G2, and D-G3 from the Unification Matrix Phase 6 track.)

Metered services use the Metered Flow Protocol (MFP) — a 2-of-2 multisig payment channel with `nSequence`-based state progression. Each channel is a cashlane: a bilateral financial relationship between the node and a service provider (or another node), settled in BSV. The channel-funding key is derived from the BCA computed in step 4.

At step 14, the node opens cashlanes for any services that declare metered access in their capability class (`cap.metered_access`). For a minimal local installation, no cashlanes are needed; the test configuration runs with `METERING_ENABLED=false`.

At the feasibility stage, the MFP 8-state FSM is implemented and the channel lifecycle (NEGOTIATING → FUNDED → ACTIVE → … → SETTLED) is operable, but the World Host region emission of MeteringTicks (deliverable D-G1, which requires Prompt 14's payment-channel ports) is not yet wired. Deliverable D-G2 adds the Helm UI for live metering state per region and service; D-G3 integrates the Settlement app (A6) with MFP channels for atomic on-chain finalisation.

---

### Step 15 — User online, sovereign, federated

(Currently in feasibility — full reach of this step is gated on the completion of the Unification Matrix.)

Step 15 is a state, not an action. When steps 1–14 have all completed successfully, the node is:

- Online: all services are running and responding to health checks.
- Sovereign: the identity DAG, the capability UTXO set, and the cell-engine state are all under the user's exclusive cryptographic control. The server holds a recovery payload that is cryptographically useless without the user's challenge answers.
- Federated: the mesh adapter has joined the multicast group; the node can form sessions with peers; the Plexus identity DAG is enrolled.

The path to this state today runs through steps 1–7 under full enforcement and steps 8–15 under feasibility. The Unification Matrix tracks the deliverables that close each remaining gap. When the Matrix completes, steps 8–15 will operate under the same level of enforcement as steps 1–7.

---

## The `docker compose up` Happy Path

The following commands illustrate the complete first-boot sequence on a clean machine. Commands are illustrative; the exact image tags and environment variable names are defined in `docker-compose.node.yml` and subject to change as the installer matures.

```bash
# 1. Clone the repository
git clone https://github.com/semantos/semantos-core.git
cd semantos-core

# 2. Install workspace dependencies
pnpm install

# 3. Run the one-command installer
#    (Equivalent to: curl -fsSL https://get.semantos.sh | sh on a remote VPS)
bash scripts/install.sh
```

The installer script:

1. Detects the local operating system and checks for Docker and Docker Compose.
2. Runs `apps/node-installer/src/first-boot.ts` via Bun.
3. First-boot prompts for email and challenge answers (steps 1–3).
4. First-boot derives the root seed, cert, BCA, and capability UTXOs (steps 4–6).
5. First-boot writes `~/.semantos/wallet.json`, `~/.semantos/cert.json`, `~/.semantos/state.json`, and `~/.semantos/.env`.
6. First-boot returns; the installer brings up the Docker Compose stack.

```bash
# After first-boot completes, the installer runs:
docker compose -f docker-compose.node.yml up -d
```

The stack that comes up contains the following services:

```text
semantos-node    — The node daemon (runtime/node/); binds :4000.
                   Includes the Verifier Sidecar as a companion process.
messagebox       — Containerised BSV MessageBox service; binds :4002.
uhrp             — Containerised UHRP storage host (BRC-31/BRC-29); binds :4003.
wallet           — BRC-100 wallet daemon (wallet-toolbox-based); binds :4004.
bsv-headers      — SPV header cache; binds :4005.
```

All services share a Docker network. Named volumes persist the SQLite databases and blob storage across restarts. Healthchecks are configured on every service; the installer blocks until all healthchecks pass before declaring the boot complete.

The `semantos-node` service exposes a health-check endpoint at `http://localhost:4000/healthz`. This endpoint pings each peer service and returns a JSON roll-up:

```bash
curl http://localhost:4000/healthz
```

```text
{
  "status": "ok",
  "messagebox": "ok",
  "uhrp": "ok",
  "wallet": "ok",
  "headers": "ok"
}
```

The installer's final output prints the node's identity key, node URL, and a reminder of how to inspect the node status:

```text
=========================================
Semantos sovereign node — first boot complete
=========================================
Identity key:  02a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef12345678ab
Node URL:      http://localhost:4000
Helm:          http://localhost:4001
Admin token:   (written to ~/.semantos/.env — do not share)

Run `semantos node status` to confirm all services are green.
=========================================
```

The node URL corresponds to the `/.well-known/semantos-node` discovery endpoint used by the WS-node-adapter and by `DnsPeerLocator`. Other nodes on the network can resolve your node's endpoint by querying this path.

---

## Verifying the Node

Once the boot sequence completes, the primary verification command is:

```bash
semantos node status
```

This shell verb (registered in `runtime/shell/`) calls `GET /healthz` on the running `semantos-node` daemon and pretty-prints the result. The expected output after a successful boot:

```text
Semantos node status
====================
semantos-node    [OK]   uptime: 00:02:14
messagebox       [OK]   uptime: 00:02:13
uhrp             [OK]   uptime: 00:02:12
wallet           [OK]   uptime: 00:02:14
bsv-headers      [OK]   uptime: 00:02:10

Identity:    cert_id = 8f3a2b1c4d5e6f...  (truncated for display)
BCA address: fd12:3456:789a:bc01:...       (truncated for display)
Kernel:      enforcement ON (kernel_set_enforcement = 1)
Recovery:    payload generated; upload pending

All services green. Sovereign node operational.
```

Each line in the `[OK]` block corresponds to a Docker Compose healthcheck. A service showing `[DEGRADED]` or `[DOWN]` indicates a problem in that service's container; the troubleshooting section below covers the common failure modes.

The `Kernel: enforcement ON` line is produced by calling `kernel_set_enforcement` status from the WASM interface. A value other than 1 here indicates that step 7 did not complete successfully and the kernel is not enforcing invariants — this should not be reachable via the normal boot path but would be the first thing to check in a debugging scenario.

Additional verification commands:

```bash
# Show the full BRC-52 certificate and BRC-100 public key
semantos node identity

# Inspect the capability UTXO set (steps 6-7)
semantos node caps

# Tail the node daemon logs (useful during step 8 feasibility debugging)
docker compose -f docker-compose.node.yml logs -f semantos-node
```

---

## Troubleshooting

### Service fails to start

If `docker compose -f docker-compose.node.yml up -d` exits with a container in an unhealthy state, inspect the container logs:

```bash
docker compose -f docker-compose.node.yml logs <service-name>
```

The most common causes during first boot:

| Symptom | Likely cause | Resolution |
|---|---|---|
| `wallet` unhealthy | `wallet.json` malformed or missing | Delete `~/.semantos/wallet.json` and re-run `semantos node up` |
| `bsv-headers` unhealthy | No internet access at boot | Confirm internet connectivity; headers pull from an ARC-compatible BSV header service |
| `messagebox` unhealthy | Port 4002 in use | Edit `~/.semantos/.env` to change `MESSAGEBOX_PORT` |
| `uhrp` unhealthy | Blob storage volume mount failed | Check Docker volume permissions on the host |

### `semantos node status` shows `[DEGRADED]`

A `DEGRADED` status means the service started but its own internal health check is returning a non-OK response. This typically occurs when:

- The service started but has not yet finished its internal initialisation (wait 30 seconds and re-run).
- A dependency is reachable but returning errors (inspect that service's logs).
- The capability UTXO set has not yet been populated from step 6 (re-run first-boot by deleting `~/.semantos/state.json`).

### `kernel_set_enforcement` reads 0

This condition means step 7 did not complete successfully. The most common cause is a failure during step 6 (capability domain mint) that was not surfaced during the boot. To diagnose:

```bash
# Check first-boot logs
cat ~/.semantos/first-boot.log

# Re-run first-boot in verbose mode
SEMANTOS_VERBOSE=1 semantos node up
```

First-boot writes a structured log to `~/.semantos/first-boot.log` that records each step's success or failure with timestamps. The relevant line for step 7 reads:

```text
[step 7] kernel_set_enforcement(1) — OK
```

If this line is absent or reads `FAILED`, the log will contain the preceding step's failure that caused step 7 to be skipped.

### Steps 8–15 are unreachable

If services beyond step 7 are not behaving as expected, verify that the feasibility-gated steps are noted in the `semantos node status` output. At the time of writing, the status output includes a `Feasibility steps active` line listing which steps are running under feasibility conditions rather than full BRC enforcement. This is expected behaviour; it is not a configuration error.

The Unification Matrix (tracked in `docs/prd/UNIFICATION-ROADMAP.md`) lists the specific deliverables that move each step from feasibility to full enforcement. Practitioners who need a specific step to be fully enforced before a given deployment should check the Matrix status before proceeding.

### Idempotency

The installer and first-boot process are designed to be idempotent. Re-running `semantos node up` on a machine where first-boot has already completed detects the presence of `~/.semantos/state.json` and skips first-boot, moving directly to the Docker Compose bring-up. This means running the command a second time after a partial failure is safe; it will not create a second identity or overwrite existing capability UTXOs.

To perform a clean re-install, remove the state directory and re-run:

```bash
rm -rf ~/.semantos
semantos node up
```

This is a destructive operation. The identity and capability tokens from the previous install are not recoverable unless a recovery payload was successfully uploaded in step 13.

---

## Bringing the Stack Down

Stopping the node is a single command:

```bash
docker compose -f docker-compose.node.yml down
```

This stops all services and removes the containers but leaves the named volumes intact. The next `docker compose up` restores state from the volumes without re-running first-boot.

To also remove all persistent data (volumes):

```bash
docker compose -f docker-compose.node.yml down --volumes
```

After removing volumes, the next `semantos node up` will treat the machine as a fresh install and run first-boot again.

---

The boot sequence is the unification rendered concrete. Every step exists because a protocol invariant requires it. Steps 1–7 are enforced today; the node you have just booted is kernel-conformant, identity-conformant, and capability-conformant per the conformance levels in `docs/spec/protocol-v0.5.md` §1.4. Steps 8–15 extend that conformance toward mesh-conformance as the Unification Matrix deliverables land. Chapter 28 walks through building the first adapter on top of this node.
