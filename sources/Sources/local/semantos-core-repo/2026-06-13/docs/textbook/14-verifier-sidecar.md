---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/14-verifier-sidecar.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.649842+00:00
---

# The Verifier Sidecar

**Part IV — Verification (boot step 8)**

---

## Overview

The previous three chapters established the kernel invariants (chapter 12) and their mechanised proofs (chapter 13). Together those chapters defined what a conformant cell engine guarantees by construction. This chapter addresses a different question: what guarantees hold at the *boundary* between the cell engine and every adapter that calls into it?

The cell engine enforces linearity, authorisation, domain isolation, failure atomicity, and termination within its own bytecode gate. It does not, by itself, verify that the message arriving from a network socket is signed by the entity it claims to represent. It does not verify that the BRC-52 certificate in an incoming request is authentic, non-revoked, and bound to the correct signing key. It does not verify that a capability token cited in an incoming request is an unspent UTXO rather than a replay of an already-consumed one.

Those checks belong at the adapter boundary, not inside the kernel. The component that performs them is the Verifier Sidecar.

This chapter covers: what the Verifier Sidecar is and what it checks; how it relates to the kernel invariants, and specifically to K2; the three-phase verification pipeline it runs on every arriving envelope; the reference implementation shape (D-V1); and the three deployment topologies (D-V1, D-V2, D-V3) with their concrete trade-offs in latency, attack surface, and operator burden. The chapter closes by noting that boot-sequence step 8 — "Verifier Sidecar starts" — is now unlocked.

---

## The chokepoint problem

The unified architecture routes every cross-process and cross-node message as a `SignedBundle<T>` — a BRC-100 signed CBOR envelope carrying an identity key, a nonce, a timestamp, a signature, and a BRC-52 certificate. The Verifier Sidecar is the component that enforces the validity of those envelopes before any payload reaches a downstream adapter.

Without a dedicated verification chokepoint, enforcement is fragmented. Each adapter would need to independently implement BRC-100 signature checking, BRC-52 certificate authenticity checking, identity-binding verification, and capability UTXO SPV checks. The verification logic would be duplicated across every surface — World Host, Helm, the Md Editor, the calendar adapter, the voice adapter. Security patches would need to land simultaneously in each surface rather than at a single, independently deployable component. An adapter that lags a patch cycle leaves an unverified boundary open.

The Verifier Sidecar solves this by concentrating the four checks into one process. Adapters delegate to it rather than re-implementing the checks themselves. When a security update is required — for example, a change to certificate revocation semantics — the sidecar is patched and redeployed once.

### What the Verifier Sidecar checks

Every arriving `SignedBundle<T>` envelope must pass four checks before its payload is processed:

1. **BRC-100 signature verification.** The `x-brc100-signature` field is an ECDSA signature over the canonical preimage of the envelope headers. The sidecar verifies it against the `x-brc100-identitykey` field. A signature that does not verify MUST cause the envelope to be rejected. This check makes forgery detectable at the boundary regardless of what the payload claims.

2. **BRC-52 certificate authenticity.** The `x-brc52-certificate` field carries the sender's BRC-52 certificate (or a reference to one). The sidecar verifies that the certificate is structurally valid: the `cert_id` equals SHA-256 of the canonical preimage over all fields except the signature; the issuer signature over the preimage is valid; the `childIndex` is consistent with the identity DAG. An envelope carrying an improperly formed certificate MUST be rejected.

3. **Identity binding.** The signing key in `x-brc100-identitykey` MUST match `certificate.subject` — the 33-byte compressed public key encoded in the BRC-52 certificate. This check closes the gap between "I have a valid certificate" and "I am the entity named in that certificate." Without it, an attacker could present a legitimate certificate while signing with a different key. Kernel invariant K2 — "any state-changing transition requires successful identity verification" — depends on this binding being enforced at the boundary before the cell engine sees the request.

4. **Capability UTXO liveness via SPV.** When an incoming envelope cites a capability token, the sidecar performs an SPV check: BUMP (BRC-74) proves the minting transaction is in a block; atomic-BEEF (BRC-95) proves transaction ancestry. SPV establishes that the token was minted. The sidecar then applies a liveness check — querying a UTXO overlay, running the watchman pattern, or accepting a signed timestamp from the token holder — to establish that the token has not been consumed. An envelope citing a spent capability token MUST be rejected.

These four checks are the operational content of what it means for an adapter boundary to be BRC-compliant. None of them belong inside the cell engine kernel: the kernel's job is bounded, deterministic bytecode execution over a local PDA state. The sidecar's job is external-world verification — signatures, certificates, on-chain UTXOs — against the network and the BSV overlay.

---

## K2 and the boundary guarantee

Kernel invariant K2 states: any state-changing transition requires successful identity verification. The Lean proof (`AuthSoundnessK2.lean`) establishes this over the abstract 2-PDA model. However, the 2-PDA model assumes that identity bindings arriving at the kernel gate are already verified. If an unverified envelope reaches the cell engine, K2 holds over what the kernel sees — but what it sees is an identity claim that has not been checked against the certificate DAG or the signing key. The kernel-level proof does not substitute for boundary-level enforcement.

The Verifier Sidecar is the mechanism that makes K2's assumption true at the system level. Together, the two components form a layered guarantee: the sidecar verifies that the claimed identity is authentic and bound to the signing key; the kernel enforces that state-changing transitions carry that verified identity. Neither layer is sufficient alone.

This is not a gap in the Lean proof — the proof is complete and correct over its model. It is a statement about the scope of the model. K2 at the kernel gate, plus the Verifier Sidecar at the adapter boundary, together yield: no state-changing transition in the unified system can proceed without verified identity. That claim is not in any single proof file; it is a property of the deployment.

The Unification Roadmap records U5 (Verifier Sidecar) as a substrate component that is unified by construction for axes A (Identity), C (Transport), and D-cap (Capability). The matrix entry for U5 is:

| Axis | Status |
|---|---|
| A. Identity (BRC-52 verify) | ✓ |
| C. Transport (BRC-100 enforce) | ✓ |
| D-cap (SPV checks) | ✓ |

This reflects the design: the sidecar *is* the unification mechanism for those three axes simultaneously.

---

## The three-phase verification pipeline

The Verifier Sidecar runs a structured three-phase pipeline on every incoming envelope. The phases mirror the three-phase verification pipeline in the cell engine (BUMP → atomic-BEEF → state envelope), but at the transport layer rather than the bytecode layer.

```
Incoming SignedBundle<T>
        │
        ▼
Phase 1: BRC-100 signature check
  ─ extract x-brc100-identitykey, x-brc100-signature
  ─ verify ECDSA(identitykey, canonical_preimage) == signature
  ─ reject if mismatch (fail-fast)
        │
        ▼
Phase 2: BRC-52 certificate authenticity + identity binding
  ─ verify cert_id = SHA-256(canonical_preimage(cert fields))
  ─ verify issuer_signature over preimage
  ─ verify x-brc100-identitykey == certificate.subject
  ─ reject if any check fails
        │
        ▼
Phase 3: Capability UTXO liveness (if envelope cites a capability)
  ─ BUMP: verify minting transaction is in a block (BRC-74)
  ─ atomic-BEEF: verify transaction ancestry (BRC-95)
  ─ liveness: UTXO overlay query / watchman / signed timestamp
  ─ reject if token is spent or liveness check fails
        │
        ▼
Payload forwarded to adapter
```

[FIGURE — needs real graphic for layout pass]

**Fail-fast discipline.** Each phase fails immediately without proceeding to the next if its check does not pass. A signature that fails Phase 1 triggers a rejection before any certificate parsing occurs — this is intentional, because certificate parsing is more expensive and the signature check is the cheapest filter. The ordering is: cheapest first, most expensive last.

**Nonce and timestamp replay prevention.** The BRC-100 envelope carries an `x-brc100-nonce` (32-byte random value) and an `x-brc100-timestamp` (milliseconds since epoch). The sidecar MUST maintain a nonce cache with a time-bounded expiry window. An envelope whose nonce has already been seen MUST be rejected. An envelope whose timestamp falls outside the acceptable window MUST be rejected. These checks are not part of the Lean-proven kernel invariants — they are operational, stateful checks that belong at the transport boundary.

**Capability liveness semantics.** SPV (Simplified Payment Verification) proves that a capability token was minted in a block. It does not prove the token is unspent. The distinction matters: an attacker who records a capability token's BEEF envelope can replay it against SPV-only checks indefinitely after the token has been consumed. The Verifier Sidecar MUST NOT accept SPV alone as proof that a token is valid for the current request. One of three liveness mechanisms must also clear:

- **UTXO overlay query.** The sidecar queries a BSV overlay service or UTXO lookup node for the current spend status of the minting output. This is the most accurate mechanism but requires network availability.
- **Watchman pattern.** A designated node monitors the UTXO set for spends of known capability tokens and publishes revocation events to a local cache. The sidecar consults this cache. Accuracy depends on watchman propagation latency.
- **Signed timestamp.** The token holder periodically produces a signed timestamp proving continued possession of the spending key. This liveness proof has an expiry window; the sidecar rejects tokens whose most recent signed timestamp is outside the window.

The choice of liveness mechanism is deployment-specific. The protocol specification (§5.4) documents all three; the Verifier Sidecar MUST implement at least one. Deployments that require the strongest revocation guarantees SHOULD implement the UTXO overlay query.

---

## The reference implementation: D-V1

The Unification Roadmap Phase 0.5 ships three deliverables that together bring the Verifier Sidecar from specification to first operational integration. As of the Wave 1.5 closing, all three are merged on `main`:

- **D-V1** [#191] — VerifierStub interface and reference implementation.
- **D-V2** [#192] — Deployment topology decision (per-node sidecar process default).
- **D-V3** [#193] — First integration (World Host as the integration template).

D-V1 defines the BRC-100 verification protocol as a TypeScript interface. The canonical path is `runtime/verifier-sidecar/src/verifier.ts`; the four checks plus the nonce-replay check are the surface of the `VerifierSidecar` interface.

```typescript
// runtime/verifier-sidecar/src/verifier.ts
// (reference shape — production interface)

export interface VerificationResult {
  accepted: boolean;
  reason?: string;       // present only on rejection
  certId?: string;       // present on acceptance: verified cert_id
  identityKey?: string;  // present on acceptance: verified public key (hex)
}

export interface VerifierSidecar {
  /**
   * Verify a raw SignedBundle envelope.
   * Returns VerificationResult synchronously where possible;
   * async for liveness checks requiring network I/O.
   */
  verify(envelope: RawSignedBundle): Promise<VerificationResult>;
}
```

The reference implementation performs:
1. ECDSA verification using the `@bsv/sdk` signature primitives.
2. BRC-52 canonical preimage construction and SHA-256 comparison.
3. Subject-key binding comparison (constant-time).
4. BUMP and atomic-BEEF parsing via `@bsv/sdk`.
5. Liveness check via the configured mechanism (UTXO overlay by default in the reference implementation).

`VerifierStub` is the test-stub implementation of the same interface. It accepts all envelopes in unit-test contexts where real SPV checks are impractical. The canonical class name `VerifierStub` is the only name for the stub implementation; "verification daemon" or similar variants for either the production component or the stub are non-canonical.

The reference implementation is intentionally minimal. Its job is to exercise the full verification path end-to-end so that every subsequent adapter integration (D-V3 for World Host, then the remaining Phase 1b adapter integrations) can copy the same pattern without reimplementing the logic.

### Integration contract

The Verifier Sidecar sits between the network and the adapter's action handler. Every adapter that receives external messages MUST route them through a `verify()` call before dispatching to any handler that would mutate state. The integration pattern at World Host is illustrative:

```
Phoenix Channel message arrives
        │
        ▼
VerifierSidecar.verify(rawEnvelope)
        │
   rejected? ──────────────────────────────────────→ close socket / log
        │
   accepted (certId, identityKey extracted)
        │
        ▼
Region.apply_action(action, verifiedIdentity)
        │
        ▼
Cell engine gate (K1, K2, K3, K4, K5 enforcement)
```

[FIGURE — needs real graphic for layout pass]

The adapter passes the verified `certId` and `identityKey` into the cell engine call. The cell engine's K2 enforcement then operates over an identity that has already been verified at the boundary — the two-layer guarantee described in the previous section is satisfied.

The BCA (Blockchain Channel Address) is derived from the verified `cert_id` and exposed as a per-socket peer identifier. Adapters that track connected peers SHOULD use the BCA as the stable peer ID rather than the session token or socket ID, because the BCA is deterministic from the cert and survives reconnects from the same identity.

---

## Three deployment topologies

Protocol specification §9.5 defines three topologies in which a conformant deployment MUST run a Verifier Sidecar. The topology decision (D-V2) is resolved in Unification Roadmap §8 Q3: the default is the per-node sidecar process. The two exception topologies remain explicitly permitted for specific operational contexts.

The following table summarises the trade-offs:

| Topology | Latency | Attack surface | Operator burden |
|---|---|---|---|
| **D-V1: Per-surface in-process** | Lowest — function call | One process per adapter; a compromise in one process exposes its verification logic | Couples sidecar release cycle to each adapter's release cycle; security patches require per-adapter redeployment |
| **D-V2: Per-node sidecar process** | Moderate — IPC call (typically sub-millisecond on loopback) | One process per node; scope of exposure is bounded to the node | Independent deployment; one patch covers all adapters on the node; adds one process to the supervision tree |
| **D-V3: Edge gateway** | Highest — full network hop before any adapter sees the request | Single gateway process; all requests cross the same chokepoint | Simplest audit trail; fewest processes to monitor; single point of failure if the gateway is unavailable |

### D-V1: Per-surface in-process

In this topology, the Verifier Sidecar runs as a library linked directly into the adapter process. Verification calls are function calls within the same memory space.

**Latency.** This topology has the lowest verification latency: there is no inter-process communication (IPC), no serialisation boundary, no socket hop. For workloads where verification latency is part of a tight real-time loop — for example, World Host processing region ticks at 20 Hz with per-tick message verification — in-process verification avoids adding an IPC round-trip to the critical path.

**Attack surface.** Each adapter process carries its own copy of the verification code. If an adapter process is compromised, the attacker has access to the verification logic and potentially to the keys and certificates the sidecar holds in memory. The blast radius of a compromise is limited to one adapter but is total within that adapter.

**Operator burden.** The release coupling is the primary operational cost. When a security patch to the Verifier Sidecar is required — for example, a change to how certificate revocation is detected — every adapter that runs verification in-process must be rebuilt and redeployed simultaneously. In a deployment with many adapters, this creates a coordination problem that grows with the number of surfaces. The Unification Roadmap notes this explicitly as the reason the per-surface in-process option is not the recommended default.

**When to use it.** Per the Q3 resolution, this topology SHOULD be used for tightly-coupled pairs where byte-budget or latency demands are binding. The primary example is the cell engine co-deployed with World Host on the same node: in that configuration, the tight tick-processing loop makes the IPC latency of a separate sidecar process a measurable cost, and the in-process option is architecturally appropriate.

### D-V2: Per-node sidecar process (recommended default)

In this topology, the Verifier Sidecar runs as a separate OS process on the same node as the adapters it serves. Adapters communicate with it over a loopback socket or a Unix domain socket, passing raw envelope bytes and receiving a verification result.

**Latency.** The IPC round-trip over a loopback socket typically adds sub-millisecond latency in well-provisioned deployments. For most adapter workloads — including World Host region processing at non-peak-Hz rates, Helm backend calls, and calendar event sync — this overhead is operationally acceptable. The three-phase verification pipeline described earlier can be pipelined across adapter requests, so throughput under load is less affected than per-request latency.

**Attack surface.** The sidecar process has a well-defined, minimal API surface: it accepts raw envelope bytes, performs verification, returns a structured result. It does not execute arbitrary adapter logic. If an adapter process is compromised, the attacker can send forged envelopes to the sidecar but cannot execute code inside it. The sidecar's verification result comes back and the adapter must accept it — a compromised adapter that ignores a sidecar rejection is still constrained by the fact that subsequent cell engine calls carry an unverified identity, which K2 will reject at the bytecode gate. The two layers reinforce each other.

The sidecar process can be run under a dedicated OS user with minimal capabilities: it needs network access for UTXO overlay queries and BUMP verification but does not need filesystem access to any adapter data. Privilege separation at the OS level reduces the scope of a sidecar-process compromise.

**Operator burden.** The per-node sidecar process is independently deployable and independently restartable. A security patch to the sidecar is a single service restart on each node, not a coordinated redeployment of every adapter. The process appears in the node's supervision tree alongside the cell engine, World Host, and Helm; operators monitor it via the same tooling they use for those components.

The per-node sidecar is the recommended default because it matches the sovereign node deployment model. A sovereign node is a single deployment of all ten substrate components. Running the sidecar as a named process alongside those components is the smallest operational addition that achieves independent deployability. The Q3 resolution in the Unification Roadmap records this reasoning: "the per-node process is independently deployable, independently observable, independently replaceable, and matches the sovereign node deployment model architecturally."

### D-V3: Edge gateway

In this topology, the Verifier Sidecar runs as a network gateway through which all external traffic must pass before reaching any adapter. The gateway handles TLS termination, BRC-100 verification, and request routing in a single process. Adapters receive pre-verified requests from the gateway and do not perform their own verification.

**Latency.** Every request incurs a full network hop to the gateway before any adapter processes it. In a deployment where the gateway is on the same LAN as the adapters, this hop adds low but non-trivial latency — typically single-digit milliseconds. In a deployment where the gateway is geographically separated from the adapters (for example, in a centralised audit-focused deployment where the gateway is at the network edge), the latency can be substantially higher.

**Attack surface.** The edge gateway is both a strength and a structural characteristic. All external requests pass through a single process, which means there is one place to apply policy, one set of audit logs, and one process to patch. An auditor inspecting the system need only examine one component's logs to see every request and its verification outcome. However, the gateway is also a single chokepoint: if the gateway is unavailable — due to software failure, network partition, or resource exhaustion — no external requests reach any adapter on the node. Deployments that use the edge gateway topology MUST plan for gateway redundancy.

**Operator burden.** The edge gateway is operationally the cleanest deployment when considered in isolation: one process to operate, one set of certificates to manage, one log stream to analyse. The complexity is in the surrounding infrastructure. The gateway must be highly available, which typically means running multiple instances with load balancing. The routing rules that direct verified requests to the correct adapter must be maintained as the set of adapters changes. For deployments with a small, stable adapter set and a strong operational requirement for unified audit, the edge gateway is appropriate.

**When to use it.** Per the Q3 resolution, the edge-gateway topology MAY be used for centralised deployments where audit at a single point is the operational priority. The primary example is a deployment operated for a regulated environment where a regulator requires that a compliance officer can inspect every external request and its verification outcome from a single log source. The edge gateway makes that possible without requiring access to per-adapter logs across multiple processes.

### Topology comparison

```
[FIGURE — needs real graphic for layout pass]

D-V1 (in-process)
┌──────────────────────────────┐
│  Adapter Process              │
│  ┌────────────────────────┐  │
│  │  Verifier Sidecar (lib) │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │  Adapter Action Handler │  │
│  └────────────────────────┘  │
└──────────────────────────────┘

D-V2 (per-node sidecar, recommended default)
┌──────────────────────────────┐    loopback / unix socket
│  Verifier Sidecar Process     │ ◄──────────────────────────
└──────────────────────────────┘                            │
                                                            │
┌──────────────────────────────┐                           │
│  Adapter Process             │───────────────────────────┘
│  ┌────────────────────────┐  │
│  │  Adapter Action Handler │  │
│  └────────────────────────┘  │
└──────────────────────────────┘

D-V3 (edge gateway)
                               network hop
External request ──────────────────────────────────────────►
                                                             │
                                                   ┌─────────▼──────────┐
                                                   │  Edge Gateway /     │
                                                   │  Verifier Sidecar   │
                                                   └─────────┬──────────┘
                                                             │  verified request
                                                   ┌─────────▼──────────┐
                                                   │  Adapter Process    │
                                                   └────────────────────┘
```

### Selecting a topology in practice

The topology decision is made once per node configuration, not per request. The Unification Roadmap records the decision at D-V2 as a standing governance resolution, not a per-deployment variable. The steps are:

1. Determine whether any adapter on the node has a latency constraint that the IPC round-trip of a sidecar process would violate. If yes, use D-V1 for that adapter pair only; keep D-V2 for all other adapters on the node.
2. Determine whether the deployment has a centralised audit requirement that a single-gateway log stream would satisfy. If yes, evaluate D-V3 with the understanding that gateway redundancy must be planned and operated.
3. In all other cases, use D-V2.

Mixing topologies across adapters on the same node is permitted by the specification. A node that runs World Host (with cell engine co-deployment, using D-V1 for that pair) and Helm (using D-V2 for its backend calls) and an edge gateway for external REST clients (using D-V3) is a valid conformant deployment. The critical constraint is that every external request crosses at least one Verifier Sidecar check before reaching any adapter handler, regardless of which topology carries it.

---

## Security properties and honest limitations

### What the Verifier Sidecar contributes

The Verifier Sidecar makes three properties true at every adapter boundary:

1. **No unsigned envelope reaches an adapter handler.** Every accepted request has a verifiable ECDSA signature over the canonical preimage. Forgery is detectable — not probabilistically, but structurally.

2. **Every accepted request is bound to an authentic BRC-52 certificate.** The certificate's structural validity is verified; the signing key matches `certificate.subject`. The K2 assumption — that identity bindings arriving at the kernel gate are already verified — is satisfied.

3. **Every cited capability token is verified to have been minted in a block.** SPV plus a liveness check establishes that the token has not been consumed at the time of the request, within the precision of the chosen liveness mechanism.

### Honest limitations

**SPV does not guarantee instant revocation.** The watchman pattern and the signed-timestamp mechanism both have propagation latency windows. A capability token that is spent on-chain may remain apparent-valid to a sidecar using these mechanisms for the duration of the propagation window (watchman) or the signed-timestamp expiry window. Deployments that require the tightest revocation guarantees MUST use the UTXO overlay query mechanism; that mechanism is network-dependent and imposes availability requirements on the overlay service.

**The sidecar is not formally verified.** The cell engine's kernel invariants K1–K13 are proved in Lean 4 or TLA+. The Verifier Sidecar is a separately deployed process implementing a different class of check; its correctness rests on the correctness of the `@bsv/sdk` signature primitives and the UTXO overlay service, neither of which is formally verified in the current posture. The honest-assumptions register in §13.6 of the protocol specification records this: "Host imports: the WASM kernel imports `host_*` functions from a TS host; the host is not formally verified."

**Side-channel attacks are not addressed.** Constant-time comparison is used for subject-key binding and HMAC verification (per §13.3 of the protocol specification), but the broader execution environment — CPU caches, power analysis, timing under network congestion — is not modelled. The verification posture does not claim protection against physical or network-timing side-channel attacks.

**Liveness check availability.** If the UTXO overlay service is unavailable and no watchman cache is populated and no signed timestamp is available, the sidecar cannot complete Phase 3 of the verification pipeline for capability-cited requests. The correct behaviour in this case is rejection of the request with a retriable error, not acceptance without liveness check. Deployments that require availability during overlay-service outages MUST implement the watchman pattern or the signed-timestamp mechanism as a fallback.

**Binary-integrity boot assumption.** The Verifier Sidecar itself is a deployable binary. Its integrity at boot depends on the loader verifying the binary's hash against an on-chain anchor, per the mechanism described in §13.5 of the protocol specification for the WASM cell engine. The same principle applies to the sidecar process: the production binary's SHA-256 hash SHOULD be anchored on BSV at release time, and the deploying node SHOULD verify the hash before starting the sidecar. The sidecar is in production at the per-node default topology [D-V1 / #191, D-V2 / #192, D-V3 / #193]; the on-chain hash-anchor mechanism for the sidecar binary remains a separately-tracked deliverable outside Wave 1.5's scope.

---

## Operational note: the Phase 0.5 position

The Verifier Sidecar occupied Phase 0.5 in the Unification Roadmap — the sequential, blocking phase that preceded all per-surface identity work (Phase 1b). The roadmap is explicit: "The Verifier Sidecar is load-bearing for axes A, C, and D-cap simultaneously. It needs to exist (at minimum as a `VerifierStub`) before any deliverable that consumes it can complete."

This sequencing reflects the architectural dependency: no adapter could claim to participate in axes A (Identity), C (Transport), or D-cap (Capability) until it could route its incoming envelopes through a Verifier Sidecar. The `VerifierStub` reference implementation exists precisely so that adapter integration work can be exercised against an in-process double in tests. Production integrations call through to the deployed sidecar over loopback HTTP per the D-V2 topology — the integration template established by World Host's `WorldHost.VerifierClient` [D-V3 / #193, D-A1 / #200] and adopted unchanged by every subsequent Phase 1b adapter. Adapters acquire the `verify()` call discipline, handle rejection results correctly, and pass the verified `certId` into cell engine calls. Swapping the stub for the production implementation is a configuration change, not a code change.

The boot sequence records the Phase 0.5 position directly:

```
7. Cell engine boots; kernel_set_enforcement(1) is called
8. Verifier Sidecar starts (per topology decision; §9.5)   ← Phase 0.5
9. World Host (if installed) starts authoritative regions
```

Step 7 — the cell engine boot — was unlocked in chapter 11. The Verifier Sidecar is step 8.

---

## Deployment topologies: trade-off table

The following table consolidates the topology comparison for reference. Each topology satisfies the protocol specification requirement that a conformant deployment MUST run a Verifier Sidecar in one of these three forms.

| Topology | Default? | Latency | Attack surface | Operator burden | When to prefer |
|---|---|---|---|---|---|
| Per-surface in-process (D-V1) | No | Lowest (function call) | Compromise of one adapter exposes its verification logic | Sidecar release cycle coupled to each adapter; security patches require per-adapter redeploy | Tightly-coupled adapter pairs with binding latency requirements (e.g. cell engine + World Host on the same node) |
| Per-node sidecar process (D-V2) | **Yes** | Moderate (IPC, sub-ms on loopback) | Limited to sidecar process; privilege-separated from adapters | Independently deployable; one patch per node; one extra process in supervision tree | Default for all sovereign-node deployments; the architecturally natural choice |
| Edge gateway (D-V3) | No | Highest (full network hop) | Single chokepoint; single point of failure if gateway is unavailable | Cleanest audit trail; fewest log sources; requires high-availability infrastructure for the gateway | Centralised deployments with a regulatory or operational requirement for single-point audit |

The Q3 governance resolution (Unification Roadmap §8) is normative: the per-node sidecar process is the default. Deviations require explicit justification against one of the two exception criteria: latency constraint for D-V1, centralised audit requirement for D-V3.

---

## Boot-sequence step 8 is now unlocked

Chapters 11 through 14 of Part IV have progressively built the verification layer of a conformant sovereign node:

- Chapter 11 established the 2-PDA cell engine and called `kernel_set_enforcement(1)` (boot step 7).
- Chapter 12 stated the K1–K13 kernel invariants and what each rules out.
- Chapter 13 walked through the Lean 4 and TLA+ mechanised proofs.
- This chapter has specified the Verifier Sidecar: the four checks it performs at every adapter boundary; its relationship to K2; the three-phase verification pipeline; the reference implementation shape (D-V1); and the three deployment topologies with their concrete trade-offs.

The boot sequence can now advance to step 8. A sovereign node that completes the Verifier Sidecar startup — in any of the three conformant topologies, according to the D-V2 topology decision — has verified the following:

- The cell engine is running with kernel invariant enforcement active.
- Every incoming `SignedBundle<T>` will be checked for BRC-100 signature validity, BRC-52 certificate authenticity, identity binding, and capability UTXO liveness before any adapter handler processes the payload.
- K2's assumption — that identity bindings arriving at the kernel gate are verified — is satisfied at the system level.

```
Boot sequence status (after step 8):

 1. ✓ User supplies email + challenge set
 2. ✓ PBKDF2 100 000 iterations on device → root seed
 3. ✓ Derive BRC-52 cert → cert_id
 4. ✓ BCA(cert_id) computed via shared BCA library
 5. ✓ Plexus vendor SDK initialises tenant nodes locally
 6. ✓ Capability domain mints initial capability UTXOs
 7. ✓ Cell engine boots; kernel_set_enforcement(1) called
 8. ✓ Verifier Sidecar starts (per topology decision)    ← unlocked this chapter
 9.   World Host starts authoritative regions
10.   Mesh adapter joins multicast group
11.   UI server (Helm) binds localhost
12.   Adapters subscribe to region, identity, and capability streams
13.   Recovery payload backed up to Plexus Recovery Service
14.   Metered services open MFP cashlanes
15.   User is online, sovereign, federated
```

Steps 9–15 are addressed in Parts V and VI of this textbook. They require external services and network adapters beyond what the kernel and the Verifier Sidecar provide. The capability claims for those steps are gated by the Unification Matrix. As of the Wave 1.5 closing, axis A (Identity) is ✓ across every substrate row and every adapter row — World Host [D-A1 / #200], World Client [D-A2 / #201], Helm [D-A3 / #198], Md Editor [D-A4 / #197], Calendar [D-A5 / #202], Extensions / Policy Runtime [D-A6 / #199], and Voice [D-A7 / #196] all carry cert-bound identity at their session-establishment point. Full BRC enforcement on the remaining axes (B, C, D, E, F, G) for adapters across steps 9–15 is contingent on the corresponding Wave 2+ Matrix deliverables completing per the Phase 2–Phase 6 schedule.

Boot-sequence step 8 is now unlocked.
