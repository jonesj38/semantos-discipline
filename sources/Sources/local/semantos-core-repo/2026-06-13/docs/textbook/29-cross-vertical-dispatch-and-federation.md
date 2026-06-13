---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/29-cross-vertical-dispatch-and-federation.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.642143+00:00
---

# Cross-vertical dispatch and federation

Part VIII of this textbook is about building — taking the substrate primitives described in Parts II through VII and assembling them into products that interoperate. This chapter addresses the hardest integration problem in a multi-vertical platform: how do two independent business domains exchange semantic objects without collapsing into point-to-point integration, shared schema, or a central broker?

The answer is the dispatch envelope, a single semantic object that carries per-hat visibility rules, enforces linearity across organisational boundaries, and leaves a regulator-grade evidence chain behind it. This chapter explains how dispatch envelopes work, how they compose with the mesh's session-protocol skeleton, and how to reason about when federation is warranted and when it is not.

---

## Why vertical boundaries exist

A vertical is an operator-scoped deployment of the Semantos kernel configured for a specific economic domain: the trades vertical serves sole-operator tradies and small crews; the property management vertical serves REAs and strata managers. The two verticals run on the same substrate but with different object type registries, different policy trees, and different governance domains.

The vertical boundary is not an accident of product packaging. It is a deliberate separation of governance context. A tradie's job costing, margin notes, and supplier relationships are AFFINE to the trades vertical. A property manager's owner financials, lease terms, and tenant payment history are AFFINE to the property vertical. Neither party should see the other's sensitive operational data by default; neither should be able to inject patches into the other's objects without explicit grant.

Without a substrate-level separation primitive, the integration would collapse into one of two bad patterns:

1. A central database with complex row-level security rules mediating visibility — fragile, unauditable, prone to over-sharing.
2. Point-to-point API calls with bespoke authentication — correct on day one, divergent by month three.

The dispatch envelope replaces both patterns with a shared semantic object that both verticals read and write through their own hat, with visibility enforced structurally by the policy evaluator, not programmatically at each call site.

---

## The dispatch envelope

A dispatch envelope is a single cell that both verticals reference. The cell carries RELEVANT patches — those visible to all hat-holders — and AFFINE patches — those encrypted to the authoring hat's key and invisible to every other participant.

The canonical definition from the glossary: a dispatch envelope is a single semantic object referenced by multiple organisations, on which each participant attaches per-hat RELEVANT or AFFINE patches. Faceted visibility is enforced by the policy evaluator at field level; AFFINE patches are encrypted to the authoring hat's key. The envelope replaces point-to-point integration with a single auditable object whose cross-organisational evidence chain is regulator-grade by construction.

The dispatch envelope has a specific object type in the kernel's type-hash registry. Its creation is a jural act — a power exercised by the initiating hat (in the property vertical, the property manager's hat) that creates a new obligation on the receiving vertical (the tradie's hat accepts the job lead). Both the power and the obligation are typed at the SIR layer; the cell engine enforces their linearity constraints structurally.

### Linearity of the envelope itself

The envelope is a RELEVANT cell. RELEVANT means it must be consumed at least once: a dispatch envelope that is created but never read by the tradie's vertical is a kernel-invariant violation. This structural rule eliminates ghost dispatches — maintenance requests that are issued and silently dropped. If the tradie's vertical cannot accept the envelope (capacity, policy, geography), the dispatch is rejected at creation time, not discovered in a status audit days later.

The cell engine's linearity enforcement (kernel invariant K1) makes this structural rather than advisory. There is no application-layer retry loop that recovers from a silently dropped dispatch; the kernel refuses the transition. Operators building on the dispatch envelope pattern inherit this guarantee without writing a single line of guard code.

Once accepted, the envelope remains live until a terminal state is reached: either closed (work completed, invoiced, and acknowledged) or cancelled (tradie reassigned or job withdrawn). Both terminal transitions are typed power patches on the envelope, auditable on the append-only patch log.

---

## Hats and the patch log

Every patch on a dispatch envelope is authored by a specific hat. The property manager's hat, the tradie's hat, the owner's hat, the tenant's hat — each is a role-or-capacity dimension backed by a BRC-52 cert and a distinct capability scope. The patch log records not just what was written but which hat wrote it and when, giving every participant a reconstructible history of who made each claim.

The policy evaluator enforces visibility at query time. When the tradie's vertical queries the envelope, `filterState()` strips every AFFINE patch whose authoring hat is not the tradie's hat. The tradie sees the RELEVANT fields — property address, maintenance description, urgency, photographs, PM contact — and their own AFFINE fields (cost calculations, margin notes, supplier quotes) but nothing from the PM's AFFINE partition (owner details, lease terms, cost ceiling, internal PM notes). This is not a runtime access-control check layered on top of data that exists in a shared table; the AFFINE patches are encrypted at write time. There is no decryption path available to the wrong hat.

The `checkContributionRight()` function gates which hats can write which patches. The owner's hat can approve a cost estimate but cannot modify the job scope. The tenant's hat receives status updates but writes nothing. The tradie's hat can post completion photos and an invoice but cannot modify the urgency the PM set. These contribution rights are configured in the vertical's policy tree, not negotiated at runtime.

---

## The state machine for cross-vertical flow

The `MaintenanceRequest` cell on the property management side has its own FSM, and the dispatch envelope that bridges verticals is a separate object with its own state. Understanding how these two state machines compose is the practical key to building cross-vertical workflows.

On the property side, the MaintenanceRequest FSM proceeds: `new → triaged → awaiting_approval → approved → dispatched → in_progress → completed → invoiced → closed`. The `dispatched` transition is the moment the dispatch envelope is created.

On the dispatch envelope itself, the FSM is simpler: `created → accepted → in_progress → completed → cancelled`. The envelope's `in_progress` state is entered when the tradie's vertical acknowledges the job lead; `completed` when the tradie posts completion patches; `cancelled` if the assignment is withdrawn.

The property vertical's `MaintenanceRequest` FSM listens for RELEVANT patches on the envelope. When the tradie posts `completed` with a `completionPhotos` RELEVANT patch and an `invoiceAmount` RELEVANT patch, the property vertical's sync handler reads those patches and advances the `MaintenanceRequest` to `invoiced`. The causal link is the envelope: both objects reference it via `objectEdges`, and both verticals process it through their own rendering of the same policy evaluator logic.

[FIGURE — needs real graphic for layout pass]

```
Property Vertical                    Dispatch Envelope                   Trades Vertical
────────────────                    ─────────────────                   ───────────────
MaintenanceRequest                  (RELEVANT cell)                     Job lead
  new                                                                    (not yet created)
  triaged
  awaiting_approval
  approved
  dispatched ──────────────────→  created (PM hat writes:)             materialises as
                                    address, description,               Job lead in OJT
                                    urgency, categoryPath               accepted ←──────────
                                    photos, PM contact
                                    tenant contact
                                    [AFFINE: owner info,
                                     cost ceiling, notes]
                                  accepted ──────────────────────────→ in_progress
  in_progress ←───────────────── tradie posts ROM estimate
                                    schedule, quote
                                    [AFFINE: cost calc,
                                     margin notes]
  completed ←───────────────────  completed
                                    completion photos (RELEVANT)
                                    invoice amount (RELEVANT)
                                    [AFFINE: supplier receipts]
  invoiced
  closed ─────────────────────→  closed (final acknowledgement)        job closed
```

The ASCII above shows the causal flow. Each arrow is a RELEVANT patch on the envelope, visible to both verticals. The bracketed AFFINE entries are per-hat encrypted fields — they appear on the patch log but are opaque to other hats.

---

## The session-protocol skeleton and cross-vertical transport

The dispatch envelope defines what is shared. The mesh defines how it travels.

Chapter 17 describes the six-piece session-protocol skeleton: Discovery, Formation, Runtime, Broadcast Engine, Transport, and Metering Hook, composed over a `NetworkAdapter` interface. The key point for cross-vertical dispatch is that the session-protocol skeleton is domain-neutral. The `StateMachine<Event, State>` plug-in is the only vertical-specific piece.

Cross-vertical dispatch is, at the transport layer, a session between two domain state machines operating over the same dispatch envelope cell. The property vertical's session runtime drives the `MaintenanceRequest` FSM; the trades vertical's session runtime drives the `Job` FSM. The envelope is the shared state object both runtimes synchronise over.

In the current V1 architecture (a shared Postgres instance with cross-database API calls), the transport is a direct API call: the property vertical writes a `dispatched` patch and a webhook fires; the trades vertical's API receives it and materialises the job lead. The policy evaluator and patch-log enforcement run at each end's application layer.

In the V2 architecture, Supabase Realtime replaces the webhook. The property vertical publishes a patch; the trades vertical's subscription fires. The envelope remains the single shared semantic object; the transport is push rather than pull.

In the V3 overlay architecture, each operator runs a relay process (a lightweight process on a low-cost host) that bridges their application to the mesh. Dispatch envelopes are published as cell-tokens to the overlay's type-hash-addressed multicast groups. Subscribed tradies receive delivery via the shard multicast mechanism. No central broker exists; the mesh is the marketplace. This is what Phase 25D's `BsvOverlayAdapter` implements. Switching from Postgres-backed to overlay-backed dispatch is a configuration change, not a code change, because the `StorageAdapter` interface is the only seam both implementations satisfy.

### Identity linking across verticals

The remaining new work for cross-vertical dispatch — beyond what `channelService.ts` and `policyEvaluator.ts` already provide — is cross-vertical identity linking. A `MaintenanceRequest` and a `Job` reference the same dispatch envelope via `objectEdges`. In a single-vertical deployment, both objects live in the same Postgres schema and the edge is a foreign key. Cross-vertical deployment means those objects may live in different operator databases, different governance domains, different deployment geographies.

The envelope bridges them. Both objects carry a reference to the envelope's cell hash; the envelope's patch log is the authoritative record of every contribution made by either vertical. Cross-vertical identity linking is the work of establishing that the `tradieJobId` field on the `MaintenanceRequest` and the envelope's `objectEdges` consistently point to the same cell, verified by both verticals' policy evaluators independently.

This work is scoped in Phase 4 of the platform build plan.

---

## Worked example: property-management dispatch to a SCADA-vertical maintenance node

The following traces a cross-vertical dispatch from a property management operator to a SCADA-instrumented maintenance contractor — a trades vertical augmented with telemetry, asset tracking, and interlock reporting. This is a more demanding case than the simple PM-to-tradie flow because the receiving vertical has structured completion data (sensor readings, asset serial numbers, interlock confirmations) in addition to the standard completion photograph and invoice.

> **Setup:** A commercial property manager has received a tenant report of HVAC failure in a multi-tenancy office building. The HVAC system is instrumented: each unit has a temperature sensor, a compressor-state telemetry feed, and an interlock that prevents restart while a technician is declared on-site. The maintenance contractor operates a SCADA-vertical Semantos node that receives dispatch envelopes and publishes structured telemetry patches in response.

> **Step 1 — Intake (property vertical, PM hat).**
> The property manager creates a `MaintenanceRequest` with `categoryPath: services.trades.hvac.commercial`, `urgency: urgent`, `responsibleParty: landlord`. The system confirms the estimated cost is below the owner's `maintenanceApprovalThreshold`; approval is automatic. The `MaintenanceRequest` advances to `approved`.

> **Step 2 — Dispatch (property vertical creates the envelope).**
> The property vertical's dispatch handler exercises a power: it creates a dispatch envelope cell (RELEVANT, type `dispatch-envelope.maintenance`). The PM hat writes the following RELEVANT patches: property address, building floor and HVAC zone identifier, tenant contact for access, urgency, category, description, and photographs of the failed unit. The PM hat writes the following AFFINE patches: owner name and contact (encrypted to PM hat — the contractor does not see the landlord's identity), cost ceiling, and an internal note that the tenant is under a commercial lease with an SLA for HVAC uptime. The `MaintenanceRequest` advances to `dispatched`.

> **Step 3 — Materialisation (SCADA vertical receives the envelope).**
> The SCADA contractor's vertical subscribes to the `dispatch-envelope.maintenance` type hash on the mesh. The envelope arrives. The session-protocol's `AgentDiscovery` confirms the PM's hat's cert is valid and the envelope's signature chain is intact. The policy evaluator on the SCADA vertical filters the envelope: it sees all RELEVANT patches and none of the PM's AFFINE patches. A job lead is created in the SCADA vertical's system. The SCADA vertical's runtime posts an `accepted` patch to the envelope (RELEVANT). The `MaintenanceRequest` on the PM's side receives this patch via its realtime subscription and advances to `in_progress`.

> **Step 4 — On-site work (SCADA vertical, technician hat).**
> The technician's hat writes a series of RELEVANT patches to the envelope: asset serial number of the failed compressor unit, on-site arrival timestamp, and an interlock-engaged flag (indicating the technician has declared presence, preventing remote restart of the HVAC system). The technician hat also writes AFFINE patches for internal work notes and parts procurement (encrypted to the SCADA vertical — the PM does not see the contractor's margin or supplier invoices). The PM's policy evaluator subscribes to RELEVANT patches only; it receives the arrival timestamp and interlock status in near-real time.

> **Step 5 — Completion (SCADA vertical posts structured telemetry).**
> On repair completion, the technician's hat writes a RELEVANT `completion` patch containing: completion photographs, a post-repair sensor reading (temperature delta confirming the unit is operational), and the interlock-disengaged flag. The SCADA vertical's invoice module writes a RELEVANT `invoiceAmount` patch. The AFFINE partition carries the full sensor log and parts breakdown (not visible to the PM's vertical in structured form, but available for the SCADA vertical's own compliance records).

> **Step 6 — Close (property vertical, PM hat).**
> The PM receives the RELEVANT completion patches. The `MaintenanceRequest` FSM advances to `completed`. The PM creates an owner invoice referencing the tradie's `invoiceAmount` patch. The owner's hat is notified with a structured summary: unit repaired, post-repair sensor reading confirms operational status, invoice amount, technician's certification (from the SCADA vertical's hat's cert chain). The `MaintenanceRequest` advances to `invoiced`, then `closed`. The PM's hat posts a `closed` patch to the envelope. The envelope's FSM terminates.

> **What each party sees:**
> - **Property manager**: full RELEVANT patch history, their own AFFINE partition, no access to SCADA contractor's costs or sensor log details.
> - **SCADA contractor**: full RELEVANT patch history, their own AFFINE partition, no access to owner financials or tenant SLA details.
> - **Owner**: a filtered RELEVANT view — completion status, post-repair sensor reading, invoice amount. No operational details.
> - **Tenant**: status-only RELEVANT patches — "your request is being handled" at dispatch, "work completed" at completion.
> - **Regulator (if audited)**: the complete patch log with provenance. Every patch is signed by the authoring hat's BRC-52 cert. The evidence chain is reconstructible from the append-only log without any party's cooperation.

This example makes concrete what the dispatch envelope provides architecturally: not a data-sharing mechanism but an evidence-producing mechanism. The value to the regulator is not that the data was shared — it is that the data cannot be selectively redacted after the fact, because each patch is hash-chained and the authoring hat's signature is non-repudiable.

---

## Phase 35B federation — future under the Unification Matrix

The dispatch envelope and session-protocol skeleton described in this chapter operate within a single governance domain or across directly linked governance domains. The PM's node and the tradie's node share a common identity infrastructure — both are Plexus-issued BRC-52 cert holders; both are reachable via the same mesh's peer-discovery mechanism.

Phase 35B (Node as Service) extends the session-protocol skeleton to federated topologies. In a federated deployment, operator nodes that do not share a common identity infrastructure — and may not trust each other by default — need a mediated discovery mechanism, a peer-locator service, and a WebSocket-backed `NetworkAdapter` (the `WsNodeAdapter`) that bridges nodes without requiring IPv6 multicast transport.

Phase 35B is a consumer of Phase 35A's session-protocol skeleton. It adds:

- A call-protocol `CallStateMachine` that drives cross-node session formation without poker-specific vocabulary.
- A `WsNodeAdapter` implementing the `NetworkAdapter` interface over a WebSocket transport, replacing the multicast default for internet-deployed nodes.
- A peer-locator service that answers "given a governance domain, what are the reachable nodes?", enabling discovery across disjoint mesh partitions.

Under Phase 35B, the dispatch envelope pattern extends naturally: a PM's node in one governance domain can dispatch to a SCADA contractor's node in a distinct governance domain, mediated by the peer-locator and bridged by the `WsNodeAdapter`. The envelope semantics — RELEVANT patches visible to all participants, AFFINE patches encrypted to the authoring hat — carry over unchanged. The session-protocol skeleton is domain-neutral; the only difference in a federated session is that the `NetworkAdapter` is a WebSocket bridge rather than a multicast group.

Phase 35B federation is currently under the Unification Matrix. Operators building on Phase 35A's session-protocol skeleton today can adopt the 35B federated topology when it ships without changing their dispatch envelope code or their hat-based policy trees. The `NetworkAdapter` interface is the isolation seam: switching from `MulticastAdapter` to `WsNodeAdapter` is a configuration change.

---

## When to anchor, when not to

Not every cross-vertical data exchange requires a dispatch envelope. The envelope is the right primitive when several conditions hold simultaneously; it is overhead when they do not. The following heuristics are drawn from the dispatch model's architecture. They are not exhaustive; domain-specific circumstances will present edge cases. The intention is to give a practitioner a fast first filter, not a decision tree that handles every case.

### Anchor when: cross-organisational evidence is required

If the data exchange will later be subject to dispute, audit, or compliance review, the dispatch envelope's append-only patch log with hat-signed provenance is load-bearing. The evidence chain is produced as a side-effect of the dispatch mechanism; there is no cheaper way to produce equivalent auditability after the fact.

An insurance claim, a compliance inspection, a maintenance cost dispute between a landlord and a strata manager — all of these are better served by a dispatch envelope than by a record in one party's database with a PDF attachment from the other party.

### Anchor when: visibility rules cross organisational lines

If information that must be shared is a strict subset of information that must be withheld, and the boundary between those sets is enforced by organisational role rather than by a shared policy administrator, the dispatch envelope's per-hat AFFINE/RELEVANT split is the right model.

A tradie's margin is AFFINE to the trades vertical even when the invoice amount is RELEVANT to both verticals. A tenant's payment history is AFFINE to the property vertical even when the tenant's contact details are RELEVANT for access coordination. These are not row-level security problems; they are structural linearity problems. The dispatch envelope makes them structural.

### Anchor when: the workflow spans more than two vertical state machines

When three or more independent systems contribute to a single business outcome — a property manager, a trades contractor, an insurer, and a compliance certifier all working a single remediation — the dispatch envelope gives each party a consistent view of the shared state without any party becoming the authoritative host of the others' data.

A shared database cannot serve this case without one party becoming the schema owner and the others becoming second-class contributors. A dispatch envelope makes all parties first-class contributors to the same object, each within their own hat's authority.

### Do not anchor when: the exchange is within a single governance domain

If both parties are within the same governance domain — same operator, same Plexus cert tree, same policy evaluator configuration — the overhead of a dispatch envelope is unjustified. Use the kernel's standard channel-and-participant model directly. The dispatch envelope is a cross-organisational primitive; within a single operator's domain, the existing channel isolation is sufficient.

A useful diagnostic: if there is no ambiguity about which party's policy evaluator is authoritative for a given field, the parties share a governance domain. The dispatch envelope's value lies precisely in resolving that ambiguity structurally — each hat's authority is written into the envelope's policy tree, not asserted by convention.

### Do not anchor when: the data is ephemeral and non-disputable

Telemetry streams, health-check pings, realtime position updates in the World Host — these are high-frequency, low-durability data flows. The hash-chained append-only patch log is expensive per-event for this class of data. Use the mesh's `SignedBundle<T>` transport directly, without materialising a long-lived envelope object. The session-protocol's `BroadcastEngine` handles high-frequency event flows without per-event cell creation.

### Do not anchor when: the workflow is synchronous and fully reversible

Some cross-vertical queries are lookups, not commitments. A PM's system querying the trades vertical for a tradie's availability calendar, a marketplace search for qualified contractors in a geographic area — these are read operations with no state mutation on either side. They require authentication (the querying hat must present a valid cert and the appropriate capability token) but not a long-lived shared object. Issue a direct API call with BRC-100 authentication; the Verifier Sidecar enforces identity at the boundary.

### Do not anchor when: the Phase 35B federation infrastructure is not yet in place

Cross-governance-domain dispatch depends on Phase 35B's peer-locator service and `WsNodeAdapter`. Operators deploying today on Phase 35A's session-protocol skeleton should confine cross-vertical dispatch to governance domains that share the same mesh partition (same IPv6 multicast reachability). Attempting cross-internet federation before Phase 35B lands requires bespoke transport code that will be replaced when 35B ships. The architecture is designed for this evolution — the `NetworkAdapter` interface is the seam — but the timing is governed by the Unification Matrix.

---

## Summary

Cross-vertical dispatch is the mechanism by which independent Semantos verticals exchange semantic objects without collapsing into point-to-point integration or shared schema. The dispatch envelope is the substrate primitive that makes this work: a single RELEVANT cell, jointly authored by multiple hats, with per-hat AFFINE partitions enforced by the policy evaluator at field level and encrypted at write time.

The session-protocol skeleton from Phase 35A provides the transport substrate: domain-neutral Discovery, Formation, Runtime, Broadcast Engine, Transport, and optional Metering Hook, composed over a `NetworkAdapter` interface. A dispatch envelope session is two domain state machines — the property vertical's `MaintenanceRequest` FSM and the trades vertical's `Job` FSM — synchronising over a shared cell via RELEVANT patches.

The SCADA-vertical worked example traces this end-to-end: from a tenant HVAC report, through PM dispatch, tradie acceptance, on-site telemetry patches, and structured completion data, to a closed envelope with a regulator-grade audit trail. Each party sees exactly what their hat is permitted to see; each patch is non-repudiably signed; the evidence chain is reconstructible without any party's cooperation.

Phase 35B federation, currently under the Unification Matrix, extends this pattern to disjoint governance domains by adding a peer-locator service and a WebSocket-backed `NetworkAdapter`. Operators building on Phase 35A today inherit Phase 35B support when it ships by swapping a single configuration value.

The decision to use a dispatch envelope should be grounded in whether the exchange requires cross-organisational evidence, crosses hat-based visibility lines, or spans multiple independent state machines. Where these conditions do not hold — same governance domain, ephemeral data, synchronous read queries — the lighter-weight substrate primitives (channel isolation, direct BRC-100-authenticated API calls, mesh broadcast) are the correct tools.

A vertical is a state machine over a shared session skeleton. A dispatch envelope is the cell that lets two such state machines share state without surrendering their separate governance domains.
