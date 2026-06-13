---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/03-sovereign-node-end-to-end.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.646682+00:00
---

# The sovereign node, end-to-end

Part I of this textbook is motivational. It does not require you to write code, read
proofs, or configure anything. Its job is to give you a mental model of what a sovereign
node is, what the 15-step boot sequence does, and where the engineering frontier sits
today. Later parts are the depth tour; this chapter is the picture on the box.

By the end of this book you will boot one yourself.

---

## What a sovereign node is

A sovereign node is a single deployable substrate that takes voice in, produces
cryptographically anchored economic effect out, and proves every intervening step. It
runs on the operator's hardware, signs with the operator's keys, persists to the
operator's storage, and federates over a transport the operator chooses. No intrinsic
dependency on any company, network, or third-party service is baked in. The sovereignty
claim is structural, not policy.

The substrate is not a blockchain project. It uses a blockchain as a timestamping and
settlement layer when it needs one, and not when it does not. The substrate is also not
an LLM integration framework. It treats language model output as one possible surface
input — uncertain, unauthenticated — and forces that input through a stack of typed
transformations before any opcode byte reaches the execution layer. The LLM is upstream
of the substrate, not part of it.

The glossary canonical for this unit is sovereign node. The unit of deployment is one
node; the architecture at scale is a federation of sovereign nodes, each owning its own
identity, each running the verticals its operator installs, each cryptographically
attesting every state transition it commits.

---

## Why one command

The target M3 milestone for the Sovereign Node Plan is:

```sh
curl -fsSL https://get.semantos.sh | sh
```

On a clean Ubuntu 22.04 instance at a $5-tier VPS, this command produces, in at most
five minutes wall-clock: a running Semantos node, a BRC-100 wallet on disk, a BRC-52
identity certificate, optional DNS publication, and a healthy node URL. The output is
the operator's identity key, the node URL, and an admin token. The node is then a
sovereign participant on the federated mesh.

That is M3. It is not yet in production. The current engineering frontier is boot step 7
(`kernel_set_enforcement(1)`); the remaining steps work in feasibility, but full BRC
enforcement across every adapter is the subject of the Unification Roadmap (tracked
by deliverables D-V1 through D-G3 in that document). The Sovereign Node Plan describes
the three engineering tracks — shared ContentStore interface and adapters, compact
NetworkAdapter for non-IP transports, and the one-command installer — whose composition
closes that gap.

The one-command installer matters for two reasons. First, it is the concrete proof that
the substrate is real: if the command runs without error and produces a live node, the
unification claim is not architectural speculation but demonstrated behaviour. Second, it
sets the complexity ceiling for operator adoption. A sovereign node that requires ten
pages of manual configuration is not, in practice, sovereign — operators will delegate
to a service that handles configuration for them, which restores the dependency the
architecture was designed to eliminate. One command removes that failure mode.

When M3 lands, the headline picture from this chapter becomes the production reality.
Until then, the architecture described here is complete at the design level; the
remaining work is integration.

---

## What happens before one command — the Three-Part Handoff

The one-command experience is built from three independent engineering tracks, each
shipping as its own deliverable:

**Part 1 — ContentStore interface and reference adapters.** There is no first-class
package-level storage abstraction across the substrate today. Each extension that needs
off-chain blob storage defines its own contract. The first track defines a shared
ContentStore interface in `core/protocol-types/` and ships three reference adapters:
a UHRP HTTP adapter (compatible with any UHRP host, including a self-hosted one on the
VPS), a local filesystem adapter, and a USB-mounted content-addressed layout adapter
for offline PAN distribution. Once this lands, the claim "point your storage adapter
at whatever you define" becomes a contract rather than an aspiration. Milestone M1.

**Part 2 — Compact NetworkAdapter for non-IP transports.** The existing session
protocol and WebSocket adapter assume full MTUs and connection-oriented transports. The
IoT row of the adapter matrix — LoRa, ESP-NOW, 6LoWPAN, BLE — requires a
connectionless, sign-per-frame variant with a target envelope of at most 200 bytes. The
second track ships this as a `runtime/compact-network-adapter/` package implementing
the same NetworkAdapter contract as the existing WebSocket adapter. The same
SessionRuntime state machine runs unchanged against both adapters; swapping the adapter
swaps the physical layer, not the protocol above it. Milestone M2.

**Part 3 — One-command sovereign node installer.** The third track composes the
preceding two into the `curl -fsSL https://get.semantos.sh | sh` experience. A Bash
installer detects the distro, installs Docker and Docker Compose if absent, runs a
TypeScript first-boot script that generates the `.env`, creates the BRC-100 wallet,
issues the BRC-52 identity certificate, optionally publishes the
`_semantos-node.<host>` DNS TXT record, and brings up the compose stack. The final
output is the identity key, the node URL, and the admin token. Milestone M3.

Parts 2 and 3 are independent of each other. Both build on Part 1. The recommended
sequencing is: Part 1 first, then Parts 2 and 3 in parallel.

The M3 milestone and the Unification Roadmap's "boot sequence runs end-to-end under
proper BRC enforcement" milestone are the same date by construction. Closing the
integration gaps in the adapter matrix and shipping the one-command installer are not
separate programmes; they are the same programme described at different levels.

---

## The adapter matrix

The same Zig/WASM kernel binary runs at three deployment scales. At each scale, four
pluggable adapter axes determine how the node interacts with the world.

| Adapter | IoT (esp32-class) | Edge / VPS (self-hosted) | Federated full node |
|---|---|---|---|
| **Storage** | USB, SD, LittleFS, PSRAM | Local FS, MinIO, UHRP host (self-hosted) | UHRP cluster, federated |
| **Identity** | Flash cert, BLE-provisioned | `wallet-toolbox` BRC-100 on disk | HSM, per-tenant issuance |
| **Anchor** | LoRa, ESP-NOW, gateway POST | Direct BSV node, bundled miner gateway | Own mining / overlay relay |
| **Network** | MQTT, ESP-NOW, BLE, mDNS | MessageBox WSS via `ws-node-adapter` | Federated peer registry, BRC-56 |

The kernel ships as two profiles compiled from the same Zig source: a full profile at
185 KB (with native crypto for standalone server and CLI use) and an embedded profile at
29 KB (which imports crypto from the host, enabling browser deployments, embedded
firmware, and any environment where the host has its own crypto stack).

There is no edge-cloud duality at the protocol layer. There is one substrate, three
deployment scales, four adapter axes, and a finite set of choices per cell. An operator
running a $5 VPS and an operator running a federated full node with hardware security
modules are running the same kernel, enforcing the same invariants, producing evidence
in the same format.

---

## The two invariants you need now

This chapter names two kernel invariants without going into proof depth. Both appear
throughout the rest of the textbook; introducing them here gives you vocabulary before
the technical material begins. Later chapters carry the Lean 4 proofs.

**K1 — Linearity.** A LINEAR cell is consumed exactly once. The cell engine enforces
this at the bytecode gate; no opcode may duplicate or silently discard a LINEAR cell.
K1 is what makes a capability token (a BRC-108 UTXO bound to a BRC-52 certificate)
behave like physical cash: spending it is its consumption, and double-spending is
structurally impossible at the execution layer. K1 is why the substrate can say
"economic effect" rather than "economic approximation." The proof is in
`proofs/lean/Semantos/Theorems/LinearityK1.lean`.

**K2 — Authorisation soundness.** Every state transition that advances a cell requires
a valid identity proof. The cell engine in combination with Plexus (the identity
substrate) enforces that the signing key matches the certificate subject of the actor
claiming the authority to act. K2 is why the boot sequence starts with identity: without
a BRC-52 certificate, no state transition can be authorised, and the node cannot
participate in anything. The proof is in
`proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean`.

K1 and K2 are the two invariants that motivate the architecture of the boot sequence.
Every step in the sequence either establishes the conditions under which K1 and K2 can
be enforced, or it exercises them for the first time on a new surface. The sequence is
the invariants made operational.

---

## The 15-step boot sequence

The boot sequence is the unification claim made concrete. When it runs without error,
the substrate is real. When it halts, the halt point is the current engineering
frontier. At the time of writing, the frontier is step 7.

The sequence below is the canonical form from the Unification Roadmap. Each step
identifies the Unification Roadmap phase that enables it. Steps 1–7 run end-to-end
under proper BRC enforcement today. Steps 8–15 run in feasibility, pending the
completion of the Unification Matrix deliverables noted.

| Step | Action | Status |
|---|---|---|
| 1 | User provides email and answers identity challenges | Production (P1a + Plexus existing) |
| 2 | PBKDF2 100,000 iterations on device → root seed (client-only) | Production (Plexus core) |
| 3 | Derive BRC-52 certificate from root seed → cert\_id (client-only) | Production (Plexus core) |
| 4 | BCA(cert\_id) computed via shared BCA library (deterministic) | Production (P1a, D-A0) |
| 5 | Vendor SDK initialises tenant\_nodes locally | Production (Plexus Vendor SDK) |
| 6 | Capability Domain mints initial UTXOs | Production (Plexus Capability Domain) |
| **7** | **Cell engine boots, kernel\_set\_enforcement(1)** | **Production — K1 and K2 are now enforced** |
| 8 | Verifier Sidecar starts (per topology decision) | Feasibility (P0.5, D-V1/V2/V3) |
| 9 | World Host (if needed) starts authoritative regions | Feasibility (P1b + P2 + P3-cap) |
| 10 | Mesh adapter joins multicast group derived from cert\_id | Feasibility (P1b + P2, D-C6) |
| 11 | UI server (Helm) binds localhost | Feasibility (P1b + P2 + P3) |
| 12 | Adapters subscribe to: region tick deltas (transport + time compose); Plexus identity events (cross-surface change feed); capability UTXO changes (auth state) | Feasibility (P2 + P3b) |
| 13 | Recovery payload backed up to Plexus Recovery service | Feasibility (P5) |
| 14 | Metered services open MFP cashlanes | Feasibility (P6) |
| 15 | User is online, sovereign, federated | Target state — reached when M3 ships |

Step 7 is the current enforcement frontier. It is the step at which
`kernel_set_enforcement(1)` is called, activating K1 and K2 for every subsequent
operation. Before step 7, the substrate has identity (BRC-52 certificate, deterministic
key derivation, initial capability UTXOs) but the kernel gate is not yet enforcing.
After step 7, no operation on a LINEAR cell can proceed without a valid authorisation
proof, and no LINEAR cell can be consumed more than once.

Step 8 is where the Verifier Sidecar comes in. The Sidecar is load-bearing for three
unification axes simultaneously — Identity (axis A), Transport (axis C), and Capability
(axis D-cap). Without it, the boot sequence stops at step 8: the kernel is enforcing
locally, but the BRC-100 envelope verification, BRC-52 certificate authenticity check,
and SPV checks for capability UTXOs are not yet enforced at the adapter boundary.

Step 12 is where transport (axis C) and time (axis E) compose. Every adapter subscribes
to the same set of streams — region tick deltas, Plexus identity events, capability
UTXO changes — via the same SignedBundle envelope format, carrying the same provenance
metadata (BCA, cert\_id, hash chain pointer). That is unification rendered concrete: not
a unified codebase, but a unified signal format crossing every adapter surface.

Steps 13 and 14 bring recovery and metering online. The recovery payload (approximately
3.4 KB of compressed canonical JSON) is backed up to the Plexus Recovery service; it
holds the deterministic metadata required to reconstruct any key, but is
cryptographically useless without the user's challenge answers. The Metered Flow
Protocol (MFP) cashlanes are 2-of-2 multisig payment channels whose 8-state FSM
produces HMAC-authenticated ticks; settlement uses Bitcoin's original nSequence
mechanism and is finalised on-chain via SPV.

Step 15 is not a technical step. It is a statement of the state the node is in. The
operator's identity is sovereign (client-derived, client-held root seed). The node is
online (Helm bound, adapters subscribed, Mesh joined). The node is federated (Mesh
adapter has joined the multicast group derived from cert\_id; recovery payload is backed
up; metered services are open).

---

## From the boot sequence to the architecture

The boot sequence is structured in four bands, corresponding to the architecture's four
main concerns:

**Identity (steps 1–6).** The operator's identity is established client-side before any
network traffic happens. The root seed never leaves the device; the BRC-52 certificate
is derived from it; the BCA is derived from the certificate. Steps 1–6 are entirely
deterministic from the operator's challenge answers. If the operator loses their device,
steps 1–3 reconstruct the same root seed from the same answers, and the rest of the
identity DAG is recoverable from the Plexus Recovery service.

**Execution (step 7).** The cell engine boots and enforcement is activated. This is the
architectural turning point: before step 7, the substrate has identity but no enforced
execution semantics; after step 7, K1 (linearity) and K2 (authorisation soundness) are
active. Every later step happens under kernel enforcement. Step 7 is the reason later
chapters can say "the substrate proves" rather than "the substrate claims."

**Network and surface (steps 8–12).** The node joins the world. The Verifier Sidecar
enforces BRC-100 envelope verification at every adapter boundary. The World Host starts
authoritative regions (if configured). The Mesh adapter joins the multicast group. Helm
binds its UI server. Each adapter subscribes to the canonical set of streams. By step
12, every adapter is receiving the same signal format from the same transport.

**Persistence (steps 13–15).** The node becomes durable and metered. The recovery
payload is backed up. Metered service channels are open. The operator is fully online.

The four bands map to the eight chapters that follow in the textbook: Parts II through V
cover identity, execution, verification, and network + surface respectively. Part VI
covers the time, recovery, and metering axes that underpin steps 12–14. Parts VII and
VIII cover the lexicon layer and the operational mechanics of actually running a node.

---

## The worked scenario

Every subsequent chapter uses the same worked scenario to make the architecture
concrete. A renter's avatar inside a shared 3D space — a World Host region — speaks:
"there's a leak under the kitchen sink, photos taking now." The system extracts the
intent, types it as a maintenance obligation under the seven jural categories, gates it
through a property-management lexicon (see chapter 25), dispatches an envelope to a
registered tradie's flat 2D inbox, the tradie books a visit, the work is done, and
payment settles on-chain via the Metered Flow Protocol.

Voice in. Economic effect out. Every step proved.

The scenario threads through every part of the substrate. Chapter 9 shows how the voice
transcript becomes a Semantic IR (SIR) program with a jural category and a governance
context. Chapter 11 shows how the SIR program lowers to opcode bytes and executes in
the 2-PDA cell engine under K1 and K2. Chapter 25 shows how the property-management
lexicon types the maintenance request and scopes visibility to the relevant hats.
Chapter 22 shows how the MFP cashlane advances when the tradie's invoice is approved.

The scenario is not a contrived textbook example. It is the architecture's own worked
example from the whitepaper, re-run through each chapter with increasing technical
depth. By the time you reach Part VIII, you will have seen every substrate component
operate on the same scenario, and you will understand which component is responsible for
which guarantee.

---

## The curl-one-URL reveal

The M3 milestone is one HTTP request:

```sh
curl -fsSL https://get.semantos.sh | sh
```

When this command runs reliably on a fresh Ubuntu 22.04 $5-tier VPS and produces a
sovereign node in at most five minutes, the whitepaper's headline is not an
architectural claim — it is a demonstrated fact. The node produced is not a demo
environment or a testnet node. It is a sovereign participant: it signs with its own
keys, it stores to its own storage, it federates over its own transport, and it is
recoverable from the operator's challenge answers without any assistance from Semantos
or any third party.

The three engineering tracks described earlier — ContentStore, compact NetworkAdapter,
and the installer — are the measurable engineering programme that produces this outcome.
The Unification Roadmap tracks progress cell by cell; M3 and the "boot sequence runs
end-to-end under proper BRC enforcement" milestone are the same date by construction.

A single HTTP request booting a sovereign node is an operationally boring milestone.
That is the point. The architecture's value is that sophisticated behaviour — typed
semantics, cryptographic linearity, provable identity, metered payment, federated mesh
participation — becomes the default, not the exception. The operator's job is to run
the command; the substrate's job is to ensure that what runs is actually sovereign.

---

## Reader exit

This chapter has given you the picture on the box: what a sovereign node is, why the
one-command experience matters, how the Three-Part Handoff produces it, what the adapter
matrix looks like across three deployment scales, and what the 15-step boot sequence
does at each step. You have seen K1 (linearity) and K2 (authorisation soundness) named,
with the statement of what each enforces. You have seen where the current engineering
frontier sits (step 7 today; M3 when the Unification Matrix completes).

The remaining parts of this textbook go deep. Part II covers identity: Plexus, the BRC-
52 certificate DAG, the BCA derivation, hats, capability tokens, and domain flags —
everything that happens in steps 1–6 and the Verifier Sidecar in step 8. Part III
covers cells and the pipeline: the cell wire format, linearity classes, the
Semantic IR, the Opcode IR in ANF, and the 2-PDA cell engine — everything that happens
in step 7. Parts IV through VI cover verification, adapters, and the time-recovery-
metering stack. Parts VII and VIII cover the lexicon layer and how to build on the
substrate yourself.

By the end of this book you will boot one yourself.
