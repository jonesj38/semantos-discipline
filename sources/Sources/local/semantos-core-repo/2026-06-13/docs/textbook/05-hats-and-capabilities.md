---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/05-hats-and-capabilities.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.653875+00:00
---

# Hats and Capability Tokens

**Part II — Identity (boot steps 1–6)**

Boot steps 1–3 established who a node is: a root seed derived from a challenge set, a BRC-52 certificate issued against that seed, a `cert_id` hashed from that certificate. Chapter 4 described how those three steps assemble the identity DAG. This chapter takes the next three steps — 4, 5, and 6 — and answers a harder question: once the substrate knows *who* a node is, how does it know *what that node is allowed to do, and in which capacity*?

The answer involves two constructs that work together. A hat is a role-or-capacity dimension that a user inhabits when signing an action: the same person may be "Alice-as-landlord" in one context and "Alice-as-trustee" in another, and the substrate treats those as structurally distinct signing principals with distinct scopes. A capability token is a BRC-108 (Identity-Linked Token Protocol) UTXO that grants time-bounded authority to perform a specific action class; spending the UTXO is the on-chain consumption proof. The two constructs are deliberately separate: a hat is an identity dimension, a capability token is a resource. This chapter defines both, explains why the separation is not optional, and shows how they interact through the four-tier model and the SIR governance context.

---

## 1. The two questions identity must answer

The protocol must answer two structurally different questions at every state transition:

1. **Principal question.** Who is the entity authorising this action? Can their signature be verified against a live BRC-52 certificate?
2. **Capacity question.** Is this entity authorised to perform this class of action in this context? Has an appropriate token been presented, and is that token still unspent?

Both questions are answered before any state delta is committed. K2 (any state-changing transition requires successful identity verification) covers the principal question. K1 (a LINEAR cell is consumed exactly once; never duplicated, never discarded) covers the capacity question once the capability token is in play — because the token is itself a LINEAR semantic resource, and attempting to use it twice is a linearity violation that the cell engine catches at the bytecode gate.

Neither question is optional. A valid BRC-52 signature without a corresponding token is not sufficient for a privileged action — the principal is known, but the capacity is absent. A token without a verified signature is not sufficient — the token may have been stolen from the expected holder. Boot steps 4–6 are the sequence in which the substrate resolves both questions: step 4 computes the BCA (Blockchain Channel Address) from the `cert_id`, step 5 initialises the tenant graph, and step 6 mints the initial capability UTXOs that make the capacity question answerable.

---

## 2. Hats

### 2.1 What a hat is

A hat is a role-or-capacity dimension under which a user signs actions. The canonical glossary definition is explicit: "distinguishing 'Bob-as-tenant' from 'Bob-as-friend' from 'Bob-as-trustee'." Each hat is associated with a distinct BRC-52 cert and a distinct capability scope. The Calendar extension's hat surface — `extensions/calendar/src/domain/hat.ts` — derives the hat's `cert_id` directly from a BRC-52 cert via `deriveHatCertId()` / `buildHatCert()` [D-A5 / #202], with `contextTag` threaded into the cert preimage so two hats in two contexts produce divergent `cert_id`s per §4.4.

The term replaced *facet* in the refactor PRD 00A-facet-to-hat-rename. The word *facet* is retired. Existing codebase paths still contain `facet` in many identifiers and will be migrated; documentation and any new code uses hat throughout.

A hat is not:

- A user account. One person may wear many hats simultaneously in distinct sessions.
- A role in the access-control-list sense. The hat is the signing principal, not a label attached to the principal.
- An extension. Extensions (workspaces / verticals) determine what types and flows are weighted in the UI; hats determine which keys sign and which capability scope is active. Both have switchers in Helm, and they are correlated but not identical. A user may put on their work hat and open a personal-finance extension concurrently — the keys signing belong to the work hat; the types surfaced belong to the extension.

The distinction between the hat switcher and the extension switcher is load-bearing for the four-tier model described in section 4.

### 2.2 Hat identity in the SIR layer

Every SIR node carries an identity field that binds the hat. The protocol spec §4.7 states: "The SIR layer carries a hat identity binding in every node's `identity` field; trust-tier enforcement at SIR refuses cross-role authoritative claims structurally."

This is not a runtime check. The SIR lowers to OIR (Opcode IR) via the `lowerSIR()` pass, and the lower pass refuses to produce OIR for cross-role authoritative claims. A renter cannot sign as a landlord even with a syntactically valid SIR program — the lower pass rejects it at compile time. The refusal is static: it produces a structured error carrying the failing node id, the failed predicate, and a remediation suggestion.

The trust tier of the governance context determines how strict the check is. A node with `trustClass: authoritative` must have `proofRequirement: formal`; any other combination causes `lowerSIR()` to refuse. This is what makes hat enforcement structural rather than advisory.

### 2.3 Hat identity and the identity DAG

Each hat corresponds to a node (or a sub-path) in the Plexus identity DAG. Per §4.4, a single identity MAY exist in multiple contexts within the DAG — the same person as customer and as employee, for example. Each context is uniquely identified by the tuple `(cert_id, appId, parentCertId, tenantPathSteps)`.

The key universes for distinct hats MUST be mathematically isolated via divergent BRC-42 derivation paths using domain flags. Keys derived under one hat MUST NOT be mathematically related to keys under another, even if the root secret is compromised. This is the substrate-level guarantee that wearing a different hat is not just a label switch — it is a key-space boundary that the derivation scheme enforces.

Domain flag `0x07` (PERMISSION_GRANT) in the well-known Plexus reserved range is the flag under which capability tokens are minted for a hat. Section 3 describes capability tokens in detail; section 4 shows how hats and capability tokens interact through the four-tier model.

### 2.4 What hats unlock in practice

The protocol spec §7.1 describes the governance context carried in every SIR node:

```
governance:
  trustClass:          cosmetic | interpretive | authoritative
  proofRequirement:    none | attestation | formal
  executionAuthority:  local_facet | hat_scoped | delegated
  linearity:           LINEAR | AFFINE | RELEVANT | FUNGIBLE
  allowedEmitOps:      (optional whitelist of OIR binding kinds)
  domainBinding:       (optional governance domain)
```

The `executionAuthority` field specifies whether a given action is signed by a local (low-trust) identity, by a hat-scoped signing principal, or delegated to another hat. The `hat_scoped` value means the SIR lower pass will verify that the hat referenced in the `identity` field is the expected signing principal for the action. If the wrong hat is presented — or no hat at all — the lower pass refuses.

This is the mechanism that gives hats their operational weight. A hat is not merely a label on a session; it is a verifiable signing principal whose scope the governance context encodes, and whose boundary the lower pass enforces at compile time rather than at runtime.

---

## 3. Capability tokens

### 3.1 What a capability token is

A capability token is a UTXO formatted per BRC-108 (the Identity-Linked Token Protocol). The token grants time-bounded authority to perform a specific action class. Spending the UTXO is the consumption proof. The token is a LINEAR semantic resource: it may be consumed exactly once, may not be duplicated, and may not be discarded.

The glossary is explicit about the terminology boundary: *permission* is retired as a synonym for the BRC-108 thing. "Permission" is acceptable only as one of the seven jural categories — specifically the Hohfeldian sense of "absence of duty to refrain." The BRC-108 construct is always capability token.

The six well-known capability classes defined by the substrate are:

| Class | Use |
|---|---|
| `cap.recovery` | Identity recovery authorisation |
| `cap.permission` | General permission grant |
| `cap.data_access` | Read access to encrypted fields |
| `cap.compute_delegation` | Delegated computation authority |
| `cap.metered_access` | Rate-limited resource access; gates MFP participation |
| `cap.transfer` | Ownership transfer authorisation |

Recovery capabilities MUST be segregated from operational capabilities in separate UTXOs to limit exposure. Operators may define additional classes in the operator-sovereign domain-flag range (`0x00010000`–`0xFFFFFFFF`).

### 3.2 Token format and lifecycle

A capability token MUST:

- Be bound to a BRC-52 certificate's subject (the 33-byte compressed secp256k1 public key at the cert's `subject` field).
- Be represented as a BSV UTXO with a locking script encoding the constraint structure.
- Be classified as a LINEAR semantic resource (linearity class 0 in the cell header).
- Be immutable after creation — the only permitted state transition is revocation via spending.

The lifecycle has four phases:

**Mint.** The parent context (the issuing hat, operating under domain flag `0x07` PERMISSION_GRANT) constructs a BRC-108 UTXO. The locking script encodes: `ownerCertId`, capability class, and constraints (expiry, geo bounds, max invocations, required domain flags). The output is locked to the recipient's `certificate.subject`.

**Verify.** Any party with the public key can verify the token via SPV: a BUMP (BRC-74) proof establishes the minting transaction is in a block; an atomic-BEEF (BRC-95) envelope proves transaction ancestry. SPV proves inclusion, not liveness. Determining whether the token has been consumed requires one of: a UTXO-set query to a BSV overlay service; an application-layer liveness protocol in which the token holder periodically provides a signed timestamp; or a watchman pattern in which a designated node monitors the UTXO set for spends of known capability tokens and broadcasts revocation events.

**Consume.** The token holder spends the UTXO. The spending transaction is the consumption proof. Spent once, permanently revoked.

**Revoke.** The issuer may force-revoke by spending from the issuer's side if the locking script permits. Revocation is instant and on-chain.

### 3.3 Locking script structure

Capability locking scripts encode constraints directly in Bitcoin Script on-chain:

- Time locks use `OP_CHECKLOCKTIMEVERIFY` for expiry enforcement.
- Identity binding uses `OP_CHECKSIG` against `certificate.subject`.

Additional Plexus-specific constraints — type enforcement, domain flag checks — are evaluated by the local cell engine, not on-chain. The on-chain script handles standard Bitcoin Script predicates; the cell engine handles semantic predicates (linearity, capability class, participant role, domain flag). This split is deliberate: the chain is the authority on whether a UTXO was spent; the cell engine is the authority on whether spending it was semantically valid in the current governance context.

### 3.4 The opcode gate: OP_CHECKCAPABILITY

The cell engine opcode that enforces capability presence is `OP_CHECKCAPABILITY` (`0xC3`). Its behaviour per the protocol spec §8.2: "Verify capability token UTXO is unspent via BUMP proof in Cell 1."

When the cell engine evaluates an action that requires a capability, the OIR program produced by `lowerSIR()` includes a `capability` binding — one of the OIR binding kinds. The `emit()` pass translates that binding to `OP_CHECKCAPABILITY` in the opcode byte stream. At execution time, the cell engine pops the capability token from the stack and verifies it via the BUMP proof carried in continuation cell type `0x01`.

If the token is absent, already consumed (K1 violation), or the BUMP proof fails to verify, execution halts immediately per K4 (failed Plexus opcodes leave the PDA state byte-for-byte unchanged). No state delta is applied. The failure mode is total.

K7 (the 256-byte cell header is read-only after packing) ensures that no opcode can retroactively reclassify a consumed capability token as unconsumed. The linearity class in the header at offset 16 is fixed at pack time and may not be modified by any instruction in the opcode set.

### 3.5 SPV validation in the three-phase pipeline

Capability token verification runs through the three-phase verification pipeline of the 2-PDA:

**Phase 1 (BUMP).** Is the anchor transaction mined? The cell engine calls `hostCheckBump` with the BRC-74 merkle path from the continuation cell. If the merkle root does not match the block header, execution halts immediately (fail-fast). This prevents wasting computation on tokens with invalid anchors.

**Phase 2 (atomic-BEEF).** Is the transaction ancestry valid? The cell engine delegates BRC-95 atomic-BEEF validation to the host, which recursively verifies the full transaction graph using the BSV SDK BEEF parser.

**Phase 3 (state envelope).** Which semantic states are under this merkle root? The cell engine deserialises the envelope and verifies selective disclosure proofs. Only then does payload evaluation continue.

A capability token that fails at any phase produces a halt with the failed phase number reported. The substrate does not distinguish "probably valid" from "verified valid."

---

## 4. The four-tier model and capability scoping

### 4.1 Why four tiers

The EXTENSIONS-VS-TYPES document establishes that the Semantos UI model has four tiers: extensions (workspaces / verticals), types (primitive nouns), contexts (the 15 operational surfaces), and Helm (the single attention point). These tiers are not a UI concept — they resolve a capability-scoping question that the hat / capability token model raises.

The question is: when a capability token authorises an action, does it authorise it globally across all extensions, or only within a particular workspace? The answer is neither. A capability token is scoped to a capability class and to the hat that holds it. The extension determines which types and flows are weighted in the current session; the hat determines which keys sign and which capability tokens are in scope.

The four-tier model makes explicit what "in scope" means:

```
Extensions (workspaces / verticals)         ← installable, composable, concurrent
      │ composes
      ▼
Types (primitives / nouns)                  ← atomic vocabulary, shared across extensions
      │ classify into (many-to-many)
      ▼
Contexts (the 15 — operational surfaces)    ← fixed grammar, not installable
      │ focused through
      ▼
Helm (the 1 — attention surface)            ← single point of focus
```

Extensions re-weight which types populate the tier-3 popovers in each context. The pyramid geometry does not change; its contents do. Install trades-services and the Transact context's popover surfaces Job, Quote, Visit alongside Invoice. Install a property-management extension and the Transact context surfaces Lease, MaintenanceRequest, Inspection. The contexts themselves remain fixed.

### 4.2 Two switchers, not one

The EXTENSIONS-VS-TYPES document identifies a critical design constraint: the hat switcher and the extension switcher are not the same control.

The hat switcher answers: *Who am I being right now?* It changes which keys sign, which social graph is visible, which audit trail the action joins, and which capability tokens are in scope. It is tied to BRC-100 capability presentation — the BRC-100 signed envelope carries `x-brc52-certificate`, and the Verifier Sidecar enforces validity at every adapter boundary.

The extension switcher answers: *What am I doing?* It changes which types and flows are weighted in the UI, which tier-3 popover contents appear, and which capability scopes are declared by the extension manifest.

The two are correlated — a user's work hat usually pairs with a trades-services extension — but not identical. A user can wear their work hat and open a personal-finance extension to approve a household invoice in a work context. The keys signing belong to the work hat; the types surfaced belong to the personal-finance extension. Conflating the two produces the class of UI confusion where changing roles accidentally changes what the user is working on.

The extension manifest declares `hat_affinity` (default hats the extension pairs well with), `capability_scopes` (what actions the extension is permitted to perform under which hats), and `flows` (common compositions). These declarations are constraints, not assignments — the user is always free to activate a different hat from the hat switcher, and the extension's capability scope is then evaluated against that hat's token set.

### 4.3 Capability scope and the extension manifest

The extension manifest field `capability_scopes` declares what the extension may do under which hats. A sketch:

```json
{
  "capability_scopes": {
    "hat.work": ["cap.transfer", "cap.compute_delegation"],
    "hat.personal": ["cap.data_access"]
  }
}
```

This declaration is not enforcement — it is a hint to the SIR compiler about what capability bindings the extension's flows are permitted to emit. The `allowedEmitOps` field in the SIR governance context is the enforcement surface. If an extension's SIR program attempts to emit a `capability` binding for `cap.transfer` but the governance context's `allowedEmitOps` does not include `capability`, the lower pass refuses with a structured error.

The net effect: capability scope is enforced structurally at compile time, not by a runtime permission check. An extension that oversteps its declared scope cannot produce valid OIR for the overstepping action. The cell engine never sees a bytecode that requests a capability the extension is not allowed to request.

---

## 5. How hats and capability tokens interact at runtime

### 5.1 The signing path

When an action is initiated from a hat-scoped context, the following sequence occurs:

1. The user's current hat is resolved from the hat switcher state in Helm.
2. The SIR compiler constructs a SIR node with the hat reference in the `identity` field and `executionAuthority: hat_scoped` in the governance context.
3. The lower pass validates: is the hat reference valid? Does the hat have an associated BRC-52 cert? Does the governance context permit this capability class?
4. The OIR program is emitted with the appropriate `capability` binding.
5. The `emit()` pass translates to opcode bytes including `OP_CHECKCAPABILITY`.
6. The cell engine executes. `OP_CHECKCAPABILITY` verifies the token. `OP_CHECKIDENTITY` (`0xC4`) verifies the cert binding. Both must succeed.
7. If both succeed, the state delta is applied. If either fails, K4 ensures the PDA state is byte-for-byte unchanged.

### 5.2 The verification path

The Verifier Sidecar sits at every adapter boundary. Per the protocol spec §9.5, it verifies BRC-100 signed envelopes, BRC-52 cert authenticity, identity binding (signing key matches `certificate.subject`), and capability UTXO state via SPV. The recommended default deployment topology is per-node sidecar process: one independent sidecar per sovereign node, with independent deployment and a moderate latency overhead.

The `x-brc100-identitykey` header on every SignedBundle (BRC-100 envelope) carries the sender's compressed secp256k1 public key. The `x-brc52-certificate` header carries the sender's BRC-52 cert. The Verifier Sidecar checks: does the signature verify against the key? Does the key match `certificate.subject`? Is the cert live (not revoked)? Does the cert scope permit the capability class being exercised?

Only after all four checks pass does the payload cross the adapter boundary into the substrate.

### 5.3 Linearity at the junction

A capability token is a LINEAR cell. It satisfies K1: consumed exactly once, never duplicated, never discarded. The opcode `OP_ASSERTLINEAR` (`0xC5`) asserts that the token is unconsumed before `OP_CHECKCAPABILITY` is called; it aborts if the token has already been consumed. `OP_CHECKLINEARTYPE` (`0xC0`) verifies the linearity class in the cell header at offset 16.

K7 ensures the header is read-only after packing. This means the linearity class of a capability token is fixed at mint time and cannot be altered by any subsequent opcode. A token that was minted as LINEAR will remain LINEAR until it is consumed.

The combination of K1 and K7 produces a capability model with no revocation ambiguity: a token is either present and unspent (and therefore LINEAR-valid), or it is absent or spent (and therefore the opcode check fails). There is no "suspended" or "temporarily disabled" state. The only way to revoke is to spend.

---

## 6. Connecting to boot steps 4–6

The previous chapter closed with boot steps 1–3 unlocked: root seed derived (step 1–2), BRC-52 cert issued (step 3). The remaining steps in the identity phase of the boot sequence are:

**Step 4 — BCA computation.** The BCA (Blockchain Channel Address) is derived from the `cert_id` via the deterministic function implemented in `core/cell-engine/src/bca.zig`. The BCA is the peer identifier in the mesh and the channel-funding key for MFP (Metered Flow Protocol) payment channels. This step is pure derivation: no network, no server, no external dependency. The BCA is available immediately after the cert is issued.

**Step 5 — Plexus vendor SDK initialises tenant nodes locally.** The Plexus vendor SDK traverses the tenant path steps from the recovery payload (if a prior recovery payload exists) or initialises a fresh tenant graph (on first boot). The tenant graph is the live structural DAG that records which hats are defined, which edges connect to which peers, and which capability classes are declared under each hat. Hat definitions are tenant-node metadata: they record the hat's BRC-52 cert reference, its capability scope declarations, and its domain flag bindings.

**Step 6 — Capability domain mints initial capability UTXOs.** The capability domain mints the initial set of capability UTXOs for the node. At minimum, a `cap.recovery` token is minted (to authorise future recovery flows) and a `cap.permission` token is minted (to authorise further minting). For deployments that configure specific extensions at boot time, the extension manifest's `capability_scopes` declarations drive which additional classes are minted during step 6.

After step 6 completes, the node has:
- A verified identity (BRC-52 cert, `cert_id`, BCA).
- A tenant graph (hat definitions, edge registrations).
- An initial capability UTXO set (at minimum `cap.recovery` and `cap.permission`).

The substrate is now capable of answering both the principal question and the capacity question for any action the node attempts. Step 7 (`kernel_set_enforcement(1)`) arms the cell engine's invariant enforcement. Steps 4–6 must complete successfully before step 7 can run.

> **From the boot log:** After step 6, a `semantos node status` call would report the capability domain as `initialised` with the count of live UTXOs. The exact output format depends on the adapter serving the status surface; the underlying data is the UTXO change feed that adapters subscribe to in step 12 of the full boot sequence. What matters here is that the capability domain is not populated lazily — it is populated as part of the boot sequence, so step 7 starts with a known-good UTXO set.

---

## 7. Worked example: kanban card movement as capability consumption

A kanban board is a simple model for demonstrating capability tokens because it has two obviously distinct roles (board owner and card mover), a clearly bounded action class (move a card from one column to another), and a natural question about what it means to consume the authority to move a card.

The sketch below works through a minimal kanban scenario. Because `docs/canon/examples/kanban-30min.md` is not yet present (the examples directory is currently a placeholder pending Stage 1 of the canon rig), this is a constructed illustration consistent with the substrate's capability model.

> **Scenario.** A software team runs a kanban board with three columns: Backlog, In Progress, Done. Two roles exist: `hat.owner` (can move cards to any column, can add new cards) and `hat.contributor` (can move cards from Backlog to In Progress only, cannot move to Done or add new cards).
>
> The board owner mints two capability tokens at board-creation time:
>
> - Token A: class `cap.transfer`, constraints `{ allowedColumns: [Backlog → InProgress, Backlog → Done, InProgress → Done], hat: hat.owner }`, locked to the owner's `certificate.subject`.
> - Token B: class `cap.transfer`, constraints `{ allowedColumns: [Backlog → InProgress], hat: hat.contributor }`, locked to the contributor's `certificate.subject`.
>
> Both tokens are BRC-108 UTXOs minted under domain flag `0x07` (PERMISSION_GRANT) by the owner hat.

> **Card creation.** The owner, wearing `hat.owner`, creates a card "Fix login bug" in the Backlog column. The card is a cell with linearity class AFFINE (can be moved at most once per transition; state can be updated). The SIR node has jural category `declaration` (an authoritative statement of the card's existence and initial state) with `executionAuthority: hat_scoped` and `hat.owner` in the identity field.
>
> The lower pass checks: is `hat.owner` the signing principal? Yes. Does the governance context permit `declaration` with `hat_scoped` execution authority? Yes. The OIR program is emitted; the cell engine processes it; the card cell is packed with the Backlog column reference in its payload.

> **Card movement — contributor move.** A contributor wearing `hat.contributor` attempts to move "Fix login bug" from Backlog to In Progress. The SIR node has jural category `transfer` (ownership of the card's column position transfers from Backlog to In Progress), with `executionAuthority: hat_scoped` and `hat.contributor` in the identity field.
>
> The OIR program includes a `capability` binding referencing Token B. The `emit()` pass produces opcode bytes: `OP_ASSERTLINEAR` (Token B is unconsumed), `OP_CHECKCAPABILITY` (Token B authorises Backlog → InProgress for `hat.contributor`), `OP_CHECKIDENTITY` (the signing key matches the contributor's `certificate.subject`).
>
> All three succeed. The card cell's column reference is updated from Backlog to InProgress. The `prevStateHash` advances. Token B is NOT consumed by this move — it is a `cap.transfer` token with an `allowedColumns` constraint, not a single-use token. The token holder retains it; the UTXO remains unspent. The constraint is enforced by the cell engine evaluating the locking script's semantic predicates; the on-chain UTXO state is unchanged.
>
> (A design variation would mint a single-use token per move; the choice between persistent-token and single-use-token is an application-layer decision reflected in the locking script's constraint structure. The LINEAR semantics apply once the token's locking script says the token is consumed; the substrate does not dictate which actions trigger spending.)

> **Card movement — contributor attempts Done.** The same contributor attempts to move the card from In Progress to Done. The SIR node has jural category `transfer` with `hat.contributor` in the identity field and `allowedColumns: [Backlog → InProgress]` as the declared constraint.
>
> The lower pass evaluates: does the governance context permit this move? The `allowedEmitOps` for `hat.contributor` do not include `cap.transfer` for the InProgress → Done transition. The lower pass refuses to produce OIR. The refusal is static — no opcode bytes are emitted, no cell engine execution occurs, no state is touched. The action fails at compile time with a structured error.
>
> Note: this refusal happens at the SIR layer, not on-chain. The on-chain Bitcoin Script locking the token's UTXO enforces only that the spending transaction has a valid signature from the token holder. The substrate adds the semantic constraint enforcement on top, at the cell engine layer.

> **Card movement — owner moves to Done.** The board owner, wearing `hat.owner`, moves the card from In Progress to Done. The SIR node has jural category `transfer` with `hat.owner` in the identity field. Token A authorises all column transitions for `hat.owner`.
>
> The OIR program includes a `capability` binding referencing Token A. All checks succeed. The card cell's column reference updates from InProgress to Done. The card cell is now in its terminal state.

> **Audit trail.** Every SIR node that was successfully lowered, compiled, and executed against the card cell has produced a cell with: a `prevStateHash` pointing to the preceding state, an `ownerID` encoding the acting hat's cert reference, a `timestamp`, and a type hash uniquely identifying the "kanban card movement" action class. The full sequence of states — creation in Backlog, move to InProgress, move to Done — is verifiable from the `prevStateHash` chain alone. Any verifier with the initial state hash and the sequence of patches can reconstruct and verify the entire history without network access.

This is capability consumption in the substrate's terms: not a permission check that succeeds or fails at runtime based on a list entry, but a compile-time structural refusal or a cell engine execution that consumes a LINEAR UTXO and leaves an auditable hash-chain record.

---

## 8. Synthesis

Hats and capability tokens address the two questions that every state-changing transition must answer:

- The principal question — answered by the hat: which BRC-52 cert is the signing principal? Enforced by `OP_CHECKIDENTITY`, K2, and the SIR trust-tier check at `lowerSIR()` time.
- The capacity question — answered by the capability token: does the principal hold an unspent BRC-108 UTXO authorising this action class? Enforced by `OP_CHECKCAPABILITY`, K1, and K7.

The four-tier model clarifies that capability scope is set by the combination of hat (which capability tokens are in scope) and extension manifest (`capability_scopes` declarations constraining `allowedEmitOps`). The hat switcher and extension switcher are separate controls with separate concerns.

The SIR governance context (`trustClass`, `proofRequirement`, `executionAuthority`, `linearity`, `allowedEmitOps`) is the compile-time surface where hat identity and capability scope are enforced structurally. Actions that violate the governance context do not produce OIR; they produce errors. Actions that produce OIR but fail at execution time are rolled back completely by K4. Actions that produce OIR, execute successfully, and spend a capability token leave a hash-chain record that is verifiable from the token's on-chain anchor through the cell's `prevStateHash` chain.

Boot steps 4–6 are now unlocked. Step 4 (BCA computation) derives the peer identifier from the `cert_id`. Step 5 (tenant initialisation) assembles the hat graph and edge registrations. Step 6 (capability UTXO minting) populates the initial token set. The node can answer both the principal question and the capacity question. Step 7 — `kernel_set_enforcement(1)` — arms the cell engine. That is the subject of Part III.
