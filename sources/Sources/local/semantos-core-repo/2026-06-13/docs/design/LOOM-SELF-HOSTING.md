---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/LOOM-SELF-HOSTING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.728890+00:00
---

# The Loom: Self-Hosting Architecture Sketch

## Why "Loom"

The service layer (currently called "workbench") isn't a brain, an engine,
or a bus. It's the frame that holds constraint threads under tension while
user intent weaves through them. The compression gradient — natural language
→ classified intent → Lisp axiom → scriptwords — is literally a threading
process: loose yarn tightens into fabric.

A loom doesn't think. It doesn't execute. It holds the warp (type system,
taxonomy, identity, governance) taut so the shuttle (user intent) can pass
through cleanly. The helm and shell are two different ways of throwing the
shuttle. The Paskian graph is the pattern that emerges in the cloth.

```
WARP THREADS (held by the Loom)          SHUTTLE (user intent)
────────────────────────────────         ─────────────────────
TypeSystem    (LINEAR/AFFINE/RELEVANT)   Conversation → Intent
Taxonomy      (extension grammar)        CLI command → Verb
Identity      (hats + capabilities)      Lisp form → Policy
Governance    (policies + flows)         Script → Cell execution
```

## The Rename

| Old              | New              | Why                                    |
|------------------|------------------|----------------------------------------|
| Workbench        | **Loom**         | It holds tension, doesn't think        |
| Facet            | **Hat**          | You put on your tradie hat             |
| LoomStore   | **LoomStore**    | Consistent                             |
| LoomObject  | **SemanticObject** (already exists) | The "workbench" prefix was always wrong |

The `Facet` → `Hat` rename is user-facing. "Switch hat" is something
anyone understands. "Switch facet" sounds like a diamond appraiser.
The interface stays the same — a hat is a capability-scoped presentation
of an identity, with its own cert, keys, and derivation path.

```typescript
/** A hat — a capability-scoped role of an identity (RELEVANT once issued). */
export interface Hat {
  id: string;
  name: string;
  displayName: string;
  capabilities: number[];
  derivationPath: string;
  certId?: string;
  publicKey?: string;
  object: LoomObject;  // ← this is the loop we're closing
}
```

## Closing the Loop: Everything Is an Object

The node self-object pattern (Phase 26E) already proved this works for
infrastructure. A Semantos node creates `sovereignty.node.{cert_id}` as
a RELEVANT object and manages itself through it. Now apply the same
pattern to the application layer.

### The Loom as RELEVANT Object

```
sovereignty.loom.{instance_id}   RELEVANT
├── payload:
│   ├── services: [ConfigStore, IdentityStore, FlowRunner, ...]
│   ├── extensions: [{id, version, registeredAt}, ...]
│   ├── taxonomy: {hash, nodeCount, lastRebuilt}
│   └── paskianConfig: {stabilityEpsilon, propagationDepth, ...}
├── patches:
│   ├── extension_registered    (hat: operator, cap: SCHEMA_SIGNING)
│   ├── taxonomy_rebuilt        (hat: system)
│   ├── config_changed          (hat: operator, cap: PERMISSION_GRANT)
│   └── paskian_tuned           (hat: operator)
└── policies:
    └── (defpolicy :subject operator
          :action register-extension
          :constraint (has-capability SCHEMA_SIGNING)
          :linearity RELEVANT)
```

**What this gives you:** every extension registration, config change, and
taxonomy rebuild is an auditable patch on a governed object. The loom's
own evolution is subject to its own policy system. You can
`semantos trace sovereignty.loom.main` and see every change that was
ever made to the platform's configuration, under which hat, with what
capabilities.

### Shell Sessions as LINEAR Objects

A shell session is consumed exactly once — when the session ends.

```
session.shell.{session_id}   LINEAR
├── payload:
│   ├── startedAt: 1713100800000
│   ├── hat: "tradie-3a2b"
│   ├── extension: "trades-services"
│   └── adapterMode: "local"
├── patches:
│   ├── command_executed   {verb: "new", typePath: "trades.job.plumbing", ...}
│   ├── command_executed   {verb: "inspect", objectId: "job-1774", ...}
│   ├── hat_switched       {from: "tradie-3a2b", to: "homeowner-7f1c"}
│   ├── command_executed   {verb: "eval", expression: "(check-policy ...)", ...}
│   └── command_executed   {verb: "sign", objectId: "job-1774", ...}
├── consumedBy:
│   └── null  (consumed on session.close → consumption proof written)
└── metadata:
    ├── commandCount: 5
    ├── hatsUsed: ["tradie-3a2b", "homeowner-7f1c"]
    └── objectsTouched: ["job-1774"]
```

**What this gives you:** `semantos inspect session.shell.yesterday` shows
exactly what you did, under which hats, touching which objects. The
session is LINEAR because it happens once and then it's done — the
consumption proof anchors it. You can't replay a session, but you can
trace it.

**The shell REPL prompt becomes self-describing:**

```
[tradie-3a2b@trades-services] >
```

This isn't just display — it's reading from the session object's current
hat and extension state. `switch homeowner` patches the session object,
which emits an event the prompt subscribes to.

### Helm Sessions as AFFINE Objects

The helm is AFFINE because you can acknowledge it (you're actively using
it) or discard it (you closed the tab, switched to shell). Both are valid.

```
session.helm.{session_id}   AFFINE
├── payload:
│   ├── activeMode: "do"
│   ├── hat: "tradie-3a2b"
│   ├── attentionSnapshot: {items: [...], computedAt: ...}
│   └── terminalOpen: false
├── patches:
│   ├── mode_switched       {from: "home", to: "do"}
│   ├── object_opened       {objectId: "job-1774", in: "do"}
│   ├── hat_switched        {from: "tradie-3a2b", to: "homeowner-7f1c"}
│   ├── terminal_toggled    {open: true}
│   └── attention_recomputed {topItem: "job-1774", urgency: "immediate"}
├── acknowledged: true   (you're using it right now)
└── discarded: false
```

**What this gives you:** the helm's attention state, mode switches, and
hat changes are all evidence-chain patches on a typed object. The
AttentionEngine (Phase 39) already computes relevance scores — those
scores are now patches on the helm session object, traceable and
auditable. When the Paskian integration lands (39B), the stability
metrics that tune attention weights are constraint edges pointing at the
helm session. The helm *learns what you care about* and the learning is
an object you can inspect.

### Hat Switches as Governance Events

Currently `switch homeowner` just sets `activeFacetId` on the shell
context. In the self-hosting model, it's a patch on the session object
that requires the hat to exist and be non-revoked:

```
semantos switch homeowner
  → verify hat "homeowner-7f1c" exists on active identity
  → verify hat's RELEVANT object is not revoked
  → patch session object: {kind: "hat_switched", delta: {to: "homeowner-7f1c"}}
  → session.activeFacetId updated
  → prompt re-renders from session object state
```

If the hat has been revoked (its RELEVANT object has a RevocationProof),
the switch fails. The governance system prevents you from acting under a
revoked identity without any special-case code — it's just the type
system doing its job.

## What Feeds the Paskian Graph

With sessions as objects, the Paskian adapter gets new interaction sources:

| Event                    | Interaction Kind    | Strength | Cell ID Pattern          |
|--------------------------|---------------------|----------|--------------------------|
| Shell command executed   | `shell.command`     | +0.3     | `session.shell.{id}`     |
| Hat switched             | `identity.switch`   | +0.5     | `con-dim-{DIMENSION}`    |
| Helm mode changed        | `helm.mode`         | +0.2     | `session.helm.{id}`      |
| Attention item actioned  | `attention.action`  | +0.8     | object's cell ID         |
| Attention item ignored   | `attention.ignore`  | -0.1     | object's cell ID         |
| Extension loaded         | `loom.extension`    | +0.4     | `sovereignty.loom.{id}`  |
| Policy compiled & bound  | `loom.policy`       | +1.0     | policy's cell ID         |

Over time, the graph stabilises around your actual usage patterns.
Objects you repeatedly touch get stronger constraint edges. Hats you
rarely wear become pruning candidates. Extensions you never use decay.
The loom *learns its own shape* through the same Paskian mechanism that
learns your exercise habits in the consciousness bridge.

## The Full Stack, Self-Hosted

```
┌─────────────────────────────────────────────────────────────┐
│                     RENDERERS                               │
│                                                             │
│   session.helm.{id}          session.shell.{id}             │
│   AFFINE                     LINEAR                         │
│   Do / Talk / Find / Home    REPL + CLI + Tmux              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                     THE LOOM                                │
│                                                             │
│   sovereignty.loom.{id}   RELEVANT                          │
│                                                             │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│   │ Identity │ │ Config   │ │ Flow     │ │ Attention│     │
│   │ Store    │ │ Store    │ │ Runner   │ │ Engine   │     │
│   │ (hats)   │ │ (exts)   │ │ (flows)  │ │ (focus)  │     │
│   └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘     │
│        │            │            │            │             │
│   ┌────▼────────────▼────────────▼────────────▼──────┐     │
│   │              IntentClassifier                     │     │
│   │       (the fuzziness resolver — any LLM)         │     │
│   └──────────────────┬───────────────────────────────┘     │
│                      │                                      │
│   ┌──────────────────▼───────────────────────────────┐     │
│   │           Lisp Compiler → Scriptwords             │     │
│   │       (deterministic — no LLM needed)             │     │
│   └──────────────────┬───────────────────────────────┘     │
│                      │                                      │
├──────────────────────┼──────────────────────────────────────┤
│                      ▼                                      │
│               CELL ENGINE (2-PDA)                           │
│   OP_CHECKLINEARTYPE · OP_ASSERTLINEAR · OP_CHECKDOMAINFLAG │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              PASKIAN CONSTRAINT GRAPH                        │
│                                                             │
│   Nodes: RELEVANT    Edges: RELEVANT    Pruning: LINEAR     │
│   Learns from ALL of the above — sessions, commands,        │
│   hat switches, attention actions, policy bindings           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│              NODE SELF-OBJECT (Phase 26E)                    │
│                                                             │
│   sovereignty.node.{cert_id}   RELEVANT                     │
│   Storage · Identity · Anchor · Network adapters             │
└─────────────────────────────────────────────────────────────┘
```

Every box in this diagram is a semantic object governed by the type system.
The loom holds the warp. The renderers throw the shuttle. The Paskian graph
is the pattern in the cloth. The cell engine is the mechanism that advances
the weave. And the node self-object is the physical loom frame itself.

## Resolved Decisions

### 1. Session Lineage — Yes, Chained

Shell sessions form a chain. Each new session's first patch references
the previous session's consumption proof, creating a linear history of
all operator activity.

**Lifecycle:** sessions are automatically logged and preserved for a
couple of days in hot storage, then pruned. Before pruning, the operator
can export any session to permanent store (anchored to BSV). This keeps
the hot path lean without losing anything that matters.

```
session.shell.001  LINEAR  ──consumed──►  session.shell.002  LINEAR  ──consumed──►  session.shell.003
  │                                         │                                         │
  └─ patches: [...]                         └─ patches: [...]                         └─ patches: [...]
  └─ consumptionProof: {txId: "ab12..."}    └─ consumptionProof: {txId: "cd34..."}    └─ active
  └─ previousSession: null                  └─ previousSession: "session.shell.001"   └─ previousSession: "session.shell.002"
```

**Auto-pruning:** after N days (configurable, default 2), consumed
sessions are pruned from hot storage. The pruning event is itself a
LINEAR cell anchored to BSV, so you always have proof that the session
*existed* even after the full evidence chain is gone.

**Export verb:**
```bash
semantos export session.shell.002 --to permanent
```
Copies the full session object (payload + all patches) to the permanent
StorageAdapter and anchors the export event. The session becomes a
RELEVANT archive object that persists indefinitely.

### 2. Hat Archival — Not Revocation, Cold Storage

Hats are never auto-revoked via Paskian pruning. Sometimes you want to
dust off an old hat and chuck it on — school reunion, one-off client
work, seasonal business. Revocation is a permanent, on-chain action
that means "this identity presentation is no longer valid." That's not
the same as "I haven't used this in a while."

Instead, hats that decay below the Paskian pruneThreshold get **archived**
— moved to cold storage, hidden from the hat switcher by default, but
instantly restorable.

```
Hat lifecycle:

  ACTIVE ───(Paskian decay)──► ARCHIVED ───(operator restore)──► ACTIVE
    │                              │
    │                              └─ hidden from switcher
    │                              └─ cert still valid
    │                              └─ capabilities still held
    │                              └─ cold storage (cheap)
    │
    └──(explicit revoke)──► REVOKED (permanent, on-chain, irreversible)
```

**Shell UX:**
```bash
semantos hat list                    # shows active hats only
semantos hat list --archived         # includes archived
semantos hat archive school-reunion  # manual archive
semantos hat restore school-reunion  # bring it back
semantos hat revoke compromised-key  # permanent, on-chain
```

The Paskian graph still tracks hat usage — archived hats have weakened
edges, and restoring a hat fires a positive interaction that
re-strengthens those edges. The graph remembers that you *used to* use
this hat, so restoring it doesn't start from zero.

### 3. Loom-to-Loom Dispatch — Yes, via Envelopes

Two Semantos nodes can share taxonomy and extension config via dispatch
envelopes. The `sovereignty.loom.*` object on each node is RELEVANT,
and dispatch envelopes are RELEVANT objects visible to multiple
verticals — so a loom dispatch envelope carries extension manifests,
taxonomy subtrees, and Paskian configs between nodes.

```
Node A (sovereignty.loom.a)                    Node B (sovereignty.loom.b)
  │                                              │
  ├─ extension: trades-services v2.1             │
  │                                              │
  └──► dispatch envelope ──────────────────────► │
       (RELEVANT, carries extension manifest)    ├─ extension: trades-services v2.1
                                                 │   (registered via envelope)
                                                 └─ patch: extension_registered
                                                     (provenance: loom.a via dispatch)
```

This means a fleet of Semantos nodes can converge on shared taxonomy
without manual config sync. The dispatch envelope carries the extension
manifest; the receiving loom's governance policy decides whether to
accept it (requires appropriate capability on the operator hat).

### 4. Loom Governance — Under the Governance Extension

Loom governance is not special-cased. It lives under the governance
extension, same as every other governed object. The policy governing
extension registration is a compiled Lisp policy bound to the
`sovereignty.loom.*` type path:

```lisp
(defpolicy loom-extension-registration
  :subject operator
  :action register-extension
  :constraint (has-capability SCHEMA_SIGNING)
  :linearity RELEVANT)
```

This compiles to scriptwords, gets evaluated by the cell engine, and
produces a cryptographic proof — same pipeline as a homeowner approving
a repair job. Full turtles-all-the-way-down.

The governance extension already handles ballots, disputes, and stakes.
Loom-level governance (extension registration, config changes, Paskian
tuning) is just another set of governed actions on a governed object.
No new machinery needed.

### 5. Hat Branching on Restore — Union of Old + Current

When an archived hat is restored, it branches: the new active hat
inherits its original capabilities *plus* any new capabilities the
identity has gained since archival. If the identity has *lost*
capabilities, those drop off — a hat can't claim what the identity
no longer holds.

```
archived hat (cold storage)              restored hat (active, branched)
capabilities: [SIGNING, MESSAGING]  ──►  capabilities: [SIGNING, MESSAGING, METERING]
certId: "abc123"                         certId: "abc123"  (same cert, same keys)
derivationPath: "m/1/3"                  derivationPath: "m/1/3"
                                         branchedFrom: archived-hat-id
                                         restoredAt: 1713100800000
```

The archived version stays in cold storage as provenance. The branch
is the new active RELEVANT object. This means the hat's history is
always traceable — you can see what it could do when it was archived
vs what it can do now.

**Implementation:** on restore, compute
`union(archived.capabilities, identity.currentCapabilities)` then
intersect with identity's *active* capability set (remove any the
identity has since lost). The result is: everything the hat knew +
everything the identity has learned, minus anything revoked.

### Hat ↔ Domain Flag ↔ Plexus Alignment

Hats are scoped under domain flags with Plexus. The architecture has
a deliberate abstraction boundary at the PlexusAdapter:

```
HAT LAYER (loom-native)
  Hat.capabilities: number[] (1-10)
  1=View  2=Create  3=Edit  4=Revoke  5=Publish
  6=Vote  7=Propose 8=Stake 9=Transfer 10=Admin
        │
        │  PlexusAdapter (translates at boundary)
        │
PROTOCOL LAYER (domain flags, uint32)
  0x00010001=View  0x00010002=Create  0x00010003=Edit ...
  These are CLIENT_SOVEREIGN flags (0x00010000+ range)
        │
        │  BRC-42 key derivation
        │  seed = hash(parentCertId + resourceId + domainFlag + childIndex)
        │
CRYPTO LAYER
  Different hats → different domain flags → different keys
  Domain flag isolation is real at the crypto level
```

Well-known Plexus flags (0x01–0x0A: SIGNING, ENCRYPTION, MESSAGING,
etc.) live in a separate namespace from loom capabilities. A hat
that needs SIGNING (0x02) and Create (0x00010002) holds both — the
well-known flag scopes the *crypto operation*, the client flag scopes
the *application permission*.

CapabilityTokens (LINEAR objects) reference domain flags directly in
`requiredDomainFlags`, not loom numbers. The protocol layer
speaks domain flags natively.

## Remaining Open Questions

1. **Helm session chaining.** Shell sessions chain naturally (LINEAR
   consumption). Should helm sessions also chain, or are they
   independent AFFINE snapshots? Helm sessions are more like "I had
   the app open" than "I did a sequence of operations" — chaining
   might be noise.

2. **Cross-session Paskian continuity.** When a session is pruned from
   hot storage, the Paskian interactions it generated still exist as
   constraint edges in the graph. But the source cell IDs now point
   at consumed/pruned sessions. Should the graph retain a summary
   node, or is the edge weight itself sufficient memory?
