---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/06-domain-flags-sovereign-boundaries.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.642972+00:00
---

# Domain flags as sovereign boundaries

A governance domain is a sovereign scope: a bounded region in which a coherent set of governance rules applies, backed by a domain flag namespace that the cell engine enforces at the bytecode level. This chapter defines what a domain flag is, how the namespace is partitioned, how the opcode `OP_CHECKDOMAINFLAG` enforces isolation, what the Lean K3 invariant proves about that enforcement, and how the five concrete kinds of governance domain — trust, estate, realm, corporate, and cooperative — are modelled as distinct shapes of the same primitive.

By the end of this chapter the reader will understand why a four-byte field in the cell header is the substrate's widest governance boundary, and will be able to map any governance structure onto the domain flag system.

---

## What a domain flag is

A domain flag is a 4-byte unsigned 32-bit integer, stored at header offset 24 in every cell (bytes 24–27, little-endian, per the wire format in protocol-v0.5.md §3.2). It is the cell's membership badge for a governance scope: every cell carrying the same flag value belongs to the same governance domain, and the cell engine checks this membership structurally, not as an application-layer policy decision.

The flag is written once, at pack time, and is read-only thereafter. Kernel invariant K7 (cell immutability) prohibits any opcode from modifying the linearity class, type hash, owner identifier, or hash-chain pointers of a cell on the stack. The domain flag falls under the same protection — a packed cell's governance domain is permanently fixed in its header.

### The namespace partition

The 32-bit space is partitioned into three non-overlapping ranges, codified in `core/protocol-types/src/namespace.ts` and normatively specified in protocol-v0.5.md §4.5:

| Range | Use |
|---|---|
| `0x00000001`–`0x000000FF` | Plexus reserved — well-known, well-defined flags |
| `0x00000100`–`0x0000FFFF` | Extended Plexus standards |
| `0x00010000`–`0xFFFFFFFF` | Operator sovereignty — client-defined |

The value `0x00000000` is not a domain flag; a cell with a zero `DomainFlag` field carries no domain binding.

The Plexus reserved range (`0x01`–`0xFF`) contains the well-known operational flags whose meaning the cell engine and the identity layer rely on. Implementations MUST NOT redefine these. The twelve currently defined are:

| Flag | Name | Use |
|---|---|---|
| `0x01` | `EDGE_CREATION` | Peer-to-peer ECDH edge derivation |
| `0x02` | `SIGNING` | Digital signature operations |
| `0x03` | `ENCRYPTION` | Field-level encryption |
| `0x04` | `MESSAGING` | Secure message channels |
| `0x05` | `ATTESTATION` | Third-party attestation |
| `0x06` | `CHILD_CREATION` | Certificate child issuance |
| `0x07` | `PERMISSION_GRANT` | Capability token minting |
| `0x08` | `DATA_SOVEREIGNTY` | Data export and portability |
| `0x09` | `SCHEMA_SIGNING` | Schema version attestation |
| `0x0A` | `METERING` | Payment channel operations |
| `0x0B` | `EXPERIENCE` | World Host region authority |
| `0x0C` | `HOST_EXEC` | Host command execution |

The operator-sovereignty range (`0x00010000`–`0xFFFFFFFF`) is structurally available for any operator to use without coordination with the Plexus substrate. This is the range from which governance domains acquire their flags. An operator allocating `0x00020001` to a family trust does so autonomously; the cell engine does not need to know the allocation exists until a cell carrying that flag is processed by `OP_CHECKDOMAINFLAG`.

### Domain flags in the BRC-52 certificate

A BRC-52 certificate carries an optional `domainFlags` field — a sequence of `uint32` values associating the certificate's identity with one or more governance domains (protocol-v0.5.md §4.2). When a hat signs an action under a particular governance domain, its certificate's `domainFlags` sequence must include that domain's flag, or the Verifier Sidecar will reject the signature as out-of-scope.

This means governance domain membership is asserted in the identity layer as well as enforced in the execution layer. An operator hat is not merely given access to domain `0x00020001` by application configuration; its BRC-52 certificate is issued with `0x00020001` in its `domainFlags` sequence, and that issuance is a signed, hash-chained, recoverable fact in the Plexus identity DAG.

Key universes for distinct governance domains are mathematically isolated via divergent BRC-42 derivation paths using domain flags. A key derived in one domain context is not mathematically related to a key derived in another, even if the root secret is the same. This provides cryptographic domain separation at the identity layer, independently of the bytecode-level enforcement described below.

---

## The enforcement opcode: OP_CHECKDOMAINFLAG

`OP_CHECKDOMAINFLAG` is opcode `0xC6` in the Plexus extension range (`0x4C`–`0xD0`). Its semantics are straightforward: read bytes 24–27 of the cell header as a `uint32`; compare against the expected flag value supplied by the script; push `TRUE` on match, or return an error on mismatch.

The opcode is specified in protocol-v0.5.md §8.2:

> `OP_CHECKDOMAINFLAG` — Read bytes 24–27 of cell header as uint32; compare against expected.

The cell engine context for this opcode is the 2-PDA: a deterministic, bounded two-stack pushdown automaton operating on the Plexus opcode range alongside standard Bitcoin Script. At the moment `OP_CHECKDOMAINFLAG` is evaluated, the stack holds the cell under scrutiny and the flag value to check against. The opcode compares the `domainFlag` field of the cell's header against the expected flag; if they match, the operation succeeds and the stack is updated; if they do not, the operation returns a domain flag mismatch error and the PDA state is left unchanged (K4 failure atomicity).

The enforcement path from cell header to executed check is therefore:

```
Cell header bytes 24–27         ← uint32 domain flag, packed at cell creation
        │
        ▼
OP_CHECKDOMAINFLAG (0xC6)       ← Zig 2-PDA opcode, Lean K3-proven
        │
        ▼
PlexusCert.domainFlags          ← optional uint32 sequence on BRC-52 identity certificates
        │
        ▼
domain flag namespace           ← 0x01–0xFFFF (Plexus); 0x00010000–0xFFFFFFFF (operator)
        │
        ▼
SIR constraint                  ← { kind: 'domain', flag: N } in the governance context
        │
        ▼
OIR binding                     ← { kind: 'domainCheck', domainFlag: N }
        │
        ▼
Emitted bytes                   ← [encodePushNumber(flag), 0xC6]
```

Every layer in this chain is implemented. The SIR carries the domain constraint as a typed structure (not a raw number), which lets the lower pass validate the flag against the governance context before emitting the opcode. The OIR carries it as an ANF binding. The cell engine evaluates the emitted bytes. The Lean proof layer supplies the correctness guarantee at the opcode level.

### What the opcode does not do

`OP_CHECKDOMAINFLAG` enforces that a cell carries the expected flag. It does not interpret what that flag means. Flag `0x00020001` is four bytes to the cell engine. The engine enforces that only operations presenting the matching flag can touch cells stamped with it. What the flag represents — a discretionary trust under Queensland law, a corporate charter, a realm under a specific regulatory jurisdiction — is a governance-layer concern that the SIR carries and the operator specifies.

This division of responsibility is deliberate. A kernel that understood governance semantics would need to be updated whenever governance structures change. A kernel that enforces structural isolation of flag namespaces can remain stable across any governance evolution the operator wishes to undertake.

---

## Kernel invariant K3: domain isolation

Kernel invariant K3 states: `OP_CHECKDOMAINFLAG` is total and correct.

The Lean 4 mechanised proof in `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` establishes this in three sub-theorems:

**K3a** (failure atomicity): if the domain flags do not match, the operation returns a `domain_flag_mismatch` error and the PDA state is unchanged.

**K3b** (match succeeds): if the domain flags match, and the pop and push operations on the 2-PDA stack succeed, the operation succeeds with the new PDA state.

**K3c** (totality): `OP_CHECKDOMAINFLAG` always returns either `ok` or `error`; it never diverges.

Together these three properties constitute the strongest isolation guarantee in the substrate. K3 does not depend on application logic, governance configuration, access control lists, or any runtime condition that could be misconfigured. It is a structural property of the opcode's implementation, proven over the abstract PDA model.

K3 interacts with the other kernel invariants in specific ways. K4 (failure atomicity) underpins K3a: when `OP_CHECKDOMAINFLAG` returns an error, the broader K4 guarantee ensures that the entire failed execution leaves the PDA state byte-for-byte unchanged. K7 (cell immutability) ensures that the domain flag in the cell header cannot be altered between packing and checking. K1 (linearity) ensures that consumption of a domain-flagged cell respects the linearity class stamped in the header alongside the domain flag. These invariants are individually proven but mutually reinforcing: together they ensure that a governance domain enforced by a domain flag is genuinely isolated, not merely nominally so.

### The Lean proof

The following is the complete content of `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`, which the reader may examine directly as the mechanised basis for K3:

```lean
-- Semantos Plane — Theorem K3: Domain Isolation
--
-- OP_CHECKDOMAINFLAG pushes TRUE iff the domain flags match.
-- No other code path produces a TRUE result for domain checking.
-- Failure case leaves stack unchanged.
--
-- Proof target: plexus.zig opCheckDomainFlag (lines 126-142)

import Semantos.Opcodes.Plexus

namespace Semantos.Theorems

open Semantos Semantos.Opcodes

-- ══════════════════════════════════════════════════════════════════════
-- K3a: Domain flag mismatch → error, stack unchanged
-- ══════════════════════════════════════════════════════════════════════

/-- K3a: If OP_CHECKDOMAINFLAG is called and the domain flags don't match,
    the operation returns domain_flag_mismatch error and the PDA state
    is unchanged (failure-atomic). -/
theorem k3a_domain_flag_mismatch (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_mismatch : cellItem.header.domainFlag ≠ flagItem.header.domainFlag) :
    opCheckDomainFlag pda = .error (.linearityError .domain_flag_mismatch) := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp [hd, h_peek0, h_peek1]
  -- After simp, the != on UInt32 (LawfulBEq) reduces. The goal becomes
  -- a = b → ..., which we contradict with h_mismatch.
  intro heq; exact absurd heq h_mismatch

-- ══════════════════════════════════════════════════════════════════════
-- K3b: Domain flag match → success (TRUE pushed)
-- ══════════════════════════════════════════════════════════════════════

/-- K3b: If OP_CHECKDOMAINFLAG is called and the domain flags match,
    and pop/push succeed, the operation succeeds with the new PDA. -/
theorem k3b_domain_flag_match (pda : PDA)
    (h_depth : pda.sdepth ≥ 2)
    (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_match : cellItem.header.domainFlag = flagItem.header.domainFlag)
    (cell0 : Cell) (pda1 : PDA)
    (h_pop : pda.spop = .ok (cell0, pda1))
    (pda2 : PDA)
    (h_push : pda1.spush trueCell = .ok pda2) :
    opCheckDomainFlag pda = .ok pda2 := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp only [hd, h_peek0, h_peek1, ite_false]
  -- Resolve the != (BNE) on UInt32 using LawfulBEq
  have hbeq : (cellItem.header.domainFlag != flagItem.header.domainFlag) = false := by
    simp [bne, h_match]
  simp [hbeq, h_pop, h_push]

-- ══════════════════════════════════════════════════════════════════════
-- K3c: Completeness — domain flag check is total
-- ══════════════════════════════════════════════════════════════════════

/-- K3c: OP_CHECKDOMAINFLAG always returns either ok or error.
    It never diverges. -/
theorem k3c_domain_check_total (pda : PDA) :
    (∃ pda', opCheckDomainFlag pda = .ok pda') ∨
    (∃ e, opCheckDomainFlag pda = .error e) := by
  cases h : opCheckDomainFlag pda with
  | error e => exact Or.inr ⟨e, rfl⟩
  | ok pda' => exact Or.inl ⟨pda', rfl⟩

end Semantos.Theorems
```

The proof is short because the property is simple. `opCheckDomainFlag` is a deterministic function over a finite set of cases: stack depth insufficient (error), flags mismatch (error, stack unchanged), flags match and stack operations succeed (ok with new PDA). K3c follows directly from the exhaustiveness of Lean 4's pattern matching — a function over an inductive type that is defined by cases over all constructors always returns one of the defined values.

Kernel invariants are easiest to prove when the opcode implementations are minimal. `OP_CHECKDOMAINFLAG` does one thing: compare two `uint32` values from the cell header. The proof effort scales with complexity; keeping the opcode simple keeps the proof small and the trust surface narrow.

---

## Domain flags in the SIR governance context

The Semantic IR (SIR) carries governance domain membership as a typed constraint on every SIR node that operates within a domain. The relevant field in the SIR's `GovernanceContext` is `domainBinding`, which extends the existing governance fields (`trustClass`, `proofRequirement`, `executionAuthority`, `linearity`, `allowedEmitOps`) with a structured description of the domain the node belongs to (SEMANTIC-IR-ARCHITECTURE.md §10.3):

```typescript
interface DomainBinding {
  flag: number;           // the uint32 domain flag (operator-sovereignty namespace)
  domainType: 'trust' | 'estate' | 'realm' | 'corporate' | 'cooperative' | 'personal';
  instrumentId?: string;  // cell ID of the governing instrument
  realm?: string;         // jurisdictional scope (e.g. 'au.qld', 'uk.ew')
  parentFlag?: number;    // parent domain flag for hierarchical domains
  delegation?: DelegationChain;
}
```

When the SIR lower pass encounters a node with a `domainBinding`, it emits `OP_CHECKDOMAINFLAG` for that domain's flag. If the domain has a `parentFlag`, the lower pass emits checks for both the child and parent domain flags, enforcing the hierarchy structurally — the same cell engine guarantee, applied twice, composed by `logical_and` in the OIR. Each individual check is independently covered by K3; the composition is the OIR's concern.

The `domainType` field tells the governance layer which kind of governance structure the domain represents. The five non-personal kinds correspond to the five concrete kinds of governance domain enumerated in SEMANTIC-IR-ARCHITECTURE.md §10: trust, estate, realm, corporate, and cooperative. These are not aliases of the umbrella concept of governance domain; they are distinct shapes, each with different governance structures, different jural decompositions, and different obligations on the parties within them.

---

## The five concrete kinds of governance domain

A governance domain is a sovereign scope under which capabilities are minted, lexicons are authoritative, hat identities sign, and trust class is asserted. The five concrete kinds enumerated in SEMANTIC-IR-ARCHITECTURE.md §10 are each a distinct way that sovereign scope is constituted and governed.

### Trust

A trust is a fiduciary arrangement: a trustee holds and manages property for the benefit of beneficiaries, subject to duties and restrictions. In terms of the substrate, a trust governance domain is a domain flag namespace where the trustee's hat identity carries the flag, all trust-scoped cells are stamped with it, and the governance rules encode fiduciary duties as obligations, trustee authorities as powers, and restrictions on trust property as prohibitions.

The jural decomposition of a trust governance domain:

- **Declaration** — the trust deed: asserts the terms, parties, and purpose. RELEVANT linearity (the deed cannot be destroyed, only varied by the proper exercise of power).
- **Obligation** — fiduciary duties: duty of care, loyalty, impartiality, accounting. LINEAR linearity (the obligation exists once and must be fulfilled or defaulted).
- **Permission** — trustee powers exercised as permissions: authority to invest, distribute, manage property.
- **Prohibition** — restrictions: no commingling of trust property with personal assets, no self-dealing, no ultra vires action.
- **Power** — trustee authority: power to manage, appoint or remove beneficiaries, vary trust terms.
- **Condition** — vesting conditions and distribution triggers: when beneficiaries take a distribution, what events bring forward vesting.
- **Transfer** — distributions to beneficiaries, settlement of trust obligations.

The flag is the kernel's contribution: structural isolation of trust property from any other governance domain, proven by K3, unchangeable after packing, independent of any application-layer policy.

### Estate

An estate is a bundle of rights over a collection of resources under unified governance. At the kernel level, this is what a domain flag namespace already constitutes — all cells carrying the same flag form an estate by definition. What distinguishes an estate governance domain from a bare namespace is the governance metadata: the declaration of what rights are bundled, who governs them, and what rules apply to their exercise.

The jural decomposition of an estate governance domain:

- **Declaration** — title registration: asserts ownership and encumbrances. RELEVANT linearity.
- **Obligation** — maintenance duties, tax obligations, reporting requirements.
- **Permission** — usage rights: easements, licences, access rights.
- **Prohibition** — restrictive covenants, zoning restrictions, planning constraints.
- **Power** — power to subdivide, mortgage, dispose of, or assign estate assets.
- **Condition** — planning approvals, regulatory prerequisites before disposal or development.
- **Transfer** — conveyance, assignment, sub-lease, or partition.

The estate kind is structurally the simplest of the five: any domain flag namespace, properly declared, is an estate. The declaration SIR node is what elevates a namespace from "four bytes in cell headers" to a governed scope with stated rights and obligations.

### Realm

A realm is a jurisdictional scope that determines which external legal framework applies to operations within the domain. A realm governance domain adds a `where` coordinate to the SIR taxonomy: operations in realm `au.qld` are subject to Queensland trust law; operations in realm `uk.ew` are subject to English and Welsh equity; operations in realm `sg` are subject to Singapore's governance frameworks.

The realm is not itself a governance authority — it is a selector for an external legal framework. The governance rules within a realm governance domain are the rules of that external framework as encoded in the SIR's constraint structures for the specific operations the domain supports.

The jural decomposition of a realm governance domain:

- **Declaration** — jurisdictional assertion: which law applies, what the nexus is.
- **Obligation** — regulatory compliance duties specific to the jurisdiction.
- **Permission** — licences to operate within the jurisdiction.
- **Prohibition** — jurisdictional restrictions: cross-border controls, sector-specific prohibitions.
- **Power** — regulatory authority, judicial authority, administrative power.
- **Condition** — jurisdictional triggers: nexus, situs, domicile conditions that determine when the realm's rules apply.
- **Transfer** — cross-realm movements, which require satisfaction of both the source and destination realm's governance rules.

Cross-realm operations require both realms' domain flag checks to pass. A transfer that moves assets from `au.qld` to `sg` carries both flags in its SIR node's constraint structure; the lower pass emits both `OP_CHECKDOMAINFLAG` instructions; both must succeed for the transfer to proceed.

### Corporate

A corporate governance domain is a domain where governance is exercised through constitutional documents — articles of incorporation, bylaws, or similar instruments — with officers acting under delegated authority. The governing instrument defines the scope of each officer's power, the procedures by which decisions are made, and the limits on corporate action.

In substrate terms, the corporate governance domain is the most structurally complex of the five, because it requires a delegation chain: the corporation as a legal entity is the domain authority, but individual hat identities act on behalf of the corporation under delegated power. The `DelegationChain` in the `DomainBinding` captures who delegated what to whom, what powers are delegated, and whether sub-delegation is permitted.

The jural decomposition of a corporate governance domain:

- **Declaration** — articles and constitutional instruments: asserts corporate existence, stated objects, and governance structure.
- **Obligation** — statutory duties on officers: duty of care, duty to avoid conflicts, reporting obligations.
- **Permission** — delegated authorities: what each officer class is authorised to do on behalf of the corporation.
- **Prohibition** — ultra vires restrictions: actions the corporation may not take under its stated objects.
- **Power** — corporate powers: power to contract, hire, acquire assets, issue shares or other instruments.
- **Condition** — board approval requirements, quorum conditions, regulatory prerequisites.
- **Transfer** — share transfers, asset disposals, contractual assignments.

The existing L1 governance configuration in the substrate (`patchAcceptancePolicy`, `versionBumpRules`, `contributorFacets`) is already a simplified corporate governance domain: a set of powers, permissions, and conditions that govern changes to a governed extension grammar. The corporate kind generalises this pattern.

### Cooperative

A cooperative governance domain is a domain where governance is exercised through collective decision-making: ballots, votes, proposals, and resolutions. Unlike the corporate kind, which delegates authority to specific officers, the cooperative kind distributes governance power across members.

The cooperative kind is closest to a DAO structure in practice: members hold equal or weighted governance rights, proposals require a minimum threshold of agreement, and changes to the domain's governance rules themselves require collective consent.

The jural decomposition of a cooperative governance domain:

- **Declaration** — founding instrument: asserts the cooperative's purpose, membership criteria, and governance structure.
- **Obligation** — member duties: participation requirements, contribution obligations.
- **Permission** — member rights: right to vote, right to propose, right to information.
- **Prohibition** — governance restrictions: supermajority requirements for certain changes, freeze periods.
- **Power** — collective powers: power to amend rules, admit or expel members, distribute surplus.
- **Condition** — quorum and threshold conditions for decisions to be valid.
- **Transfer** — distribution of surplus to members, transfer of membership interests.

The existing ballot, dispute, and resolution structures in the substrate support this kind. The cooperative kind scopes them to a domain flag, making the governance collective's decisions subject to the same bytecode-level isolation that any other governance domain enjoys.

---

## Worked example: five domains, one flag allocation each

The following example shows how each of the five kinds of governance domain receives a domain flag allocation, how that flag binds into the SIR governance context, and what the resulting `OP_CHECKDOMAINFLAG` enforcement looks like in practice. The flag values used are illustrative allocations from the operator-sovereignty namespace.

> **Setup**: an operator is running five distinct governance structures. Each is allocated a flag in the operator-sovereignty range. All cells belonging to each domain carry the corresponding flag at header offset 24.

> **Trust** — Smithfield Family Trust, discretionary, Queensland law.
> Domain flag: `0x00020001`.
> BRC-52 certificate for the trustee hat: `domainFlags: [0x00020001]`.
> Trust deed cell: header `DomainFlag = 0x00020001`, linearity `RELEVANT`.
> Fiduciary duty cells: header `DomainFlag = 0x00020001`, linearity `LINEAR`.
> Distribution cells: header `DomainFlag = 0x00020001`, linearity `LINEAR`.
> When the trustee executes a distribution, the SIR node carries `domainBinding: { flag: 0x00020001, domainType: 'trust', realm: 'au.qld' }`. The lower pass emits `[encodePushNumber(0x00020001), 0xC6]`. The cell engine evaluates `OP_CHECKDOMAINFLAG`. K3b: flags match, operation succeeds. K3a: if any cell in the execution lacks flag `0x00020001`, the operation fails and the PDA state is unchanged.

> **Estate** — Riverbank Industrial Estate, commercial property, New South Wales.
> Domain flag: `0x00030001`.
> Title declaration cell: `DomainFlag = 0x00030001`, linearity `RELEVANT`.
> Lease cells: `DomainFlag = 0x00030001`, linearity `LINEAR` (a lease is a transfer of usage rights, consumed when executed and replaced by the new lease state).
> Maintenance obligation cells: `DomainFlag = 0x00030001`, linearity `LINEAR`.
> When a new tenant is granted a lease, the SIR transfer node carries `domainBinding: { flag: 0x00030001, domainType: 'estate', realm: 'au.nsw' }`. K3 enforces that only cells carrying `0x00030001` participate in the estate's governance operations.

> **Realm** — Singapore regulatory scope for financial services operations.
> Domain flag: `0x00040001`.
> Jurisdictional assertion cell: `DomainFlag = 0x00040001`, linearity `RELEVANT`.
> Regulatory compliance obligation cells: `DomainFlag = 0x00040001`, linearity `LINEAR`.
> Cross-realm transfer (from `au.qld` trust to Singapore): SIR node carries `domainBinding: { flag: 0x00040001, domainType: 'realm', realm: 'sg' }` and a composite constraint that also checks flag `0x00020001` (the trust domain). The lower pass emits two `OP_CHECKDOMAINFLAG` instructions, composed in OIR as `logical_and`. Both must pass.

> **Corporate** — Riverbank Holdings Pty Ltd, property management company, Victoria.
> Domain flag: `0x00050001`.
> Articles of incorporation cell: `DomainFlag = 0x00050001`, linearity `RELEVANT`.
> Director delegation chain: the board's collective hat identity holds flag `0x00050001`; the managing director's hat carries a delegated subset. `DomainBinding.delegation` records the delegator (board), delegate (MD), delegated powers, and restrictions.
> Board resolution cells: `DomainFlag = 0x00050001`, linearity `RELEVANT` (resolutions are declarations and persist).
> When the managing director executes a contract on behalf of the company, the SIR power node carries `domainBinding: { flag: 0x00050001, domainType: 'corporate', delegation: { delegator: board-cert, delegate: md-cert, delegatedPowers: ['contract.sign'], restrictions: ['< $500k'], canSubDelegate: false } }`. K3 enforces that only cells carrying `0x00050001` participate in corporate governance operations.

> **Cooperative** — Riverbank Tenants Association, collective governance.
> Domain flag: `0x00060001`.
> Founding instrument cell: `DomainFlag = 0x00060001`, linearity `RELEVANT`.
> Member proposal cells: `DomainFlag = 0x00060001`, linearity `RELEVANT` (proposals persist until decided).
> Ballot cells: `DomainFlag = 0x00060001`, linearity `LINEAR` (a vote is consumed once cast).
> When a proposal passes a vote threshold, the SIR power node carries `domainBinding: { flag: 0x00060001, domainType: 'cooperative' }` and a condition constraint requiring a quorum count to have been satisfied. K3 enforces that only cells carrying `0x00060001` participate in the cooperative's governance decisions.

The five flag values are distinct. K3 guarantees that no operation on a trust cell can be performed using a corporate domain flag, and vice versa. The cell engine's enforcement is structurally complete: every path through `OP_CHECKDOMAINFLAG` returns either success or a failure-atomic error, with no divergence (K3c) and no possibility of leaving the PDA in a partially-modified state on failure (K3a, reinforced by K4).

---

## Cross-domain operations

When a governance operation crosses domain boundaries — a trust distributing to a beneficiary who also holds corporate assets, or a cooperative ballot ratifying an estate-level decision — the SIR node carries multiple domain constraints. The lower pass emits one `OP_CHECKDOMAINFLAG` per domain, composed in the OIR as `logical_and`. Each individual check is K3-proven; both must succeed for the operation to proceed.

A future K3 extension (SEMANTIC-IR-ARCHITECTURE.md §10.5) would prove hierarchical isolation: that a domain check at depth N in a delegation chain implies all ancestor checks also hold. That work is not part of the current proof set. The TLA+ model `ZoneBoundary.tla` (`proofs/tla/`) provides complementary model-checked evidence that domain-flag isolation holds under distributed interleavings.

---

## What domain flags unlock at boot steps 1–6

Domain flags are stamped on cells from the moment the identity layer comes online. Boot steps 1–3 (PBKDF2 root derivation, BRC-52 certificate creation, `cert_id` computation) establish the identity that will carry domain flag associations. Boot steps 4–5 (BCA derivation, Plexus vendor SDK initialisation) bring up the infrastructure through which domain-flagged certificates are enrolled. Boot step 6 (capability domain mints initial capability UTXOs) is the point at which the first domain-flagged capability tokens come into existence.

By the end of boot step 6, the node has:

- A root BRC-52 certificate with any operator-sovereignty domain flags it requires.
- A capability domain with `cap.permission` tokens scoped to those flags.
- Key universes derived via BRC-42 that are mathematically isolated per domain flag.

Boot step 7 (`kernel_set_enforcement(1)`) is what activates the cell engine's invariant enforcement — including K3. From that point, every cell that passes through `OP_CHECKDOMAINFLAG` is checked against the K3 guarantee. The governance domain boundaries are live.

The domain flag system is one of the few substrate mechanisms that is both statically assigned (at identity-layer cert issuance) and dynamically enforced (at every cell engine execution). This dual enforcement — in the identity DAG and in the bytecode execution — is the substrate's answer to governance boundary integrity: it is not possible to operate outside one's governance domain without both the cert issuance check and the bytecode check failing.

---

## Summary

A domain flag is a 4-byte `uint32` at header offset 24 of every cell. The namespace is partitioned into a Plexus-reserved range, an extended standards range, and an operator-sovereignty range from which governance domains allocate their flags. `OP_CHECKDOMAINFLAG` enforces domain membership structurally, with K3 providing a Lean-mechanised proof that the check is total, failure-atomic, and correct.

The five concrete kinds of governance domain — trust, estate, realm, corporate, and cooperative — are distinct shapes of sovereign scope, each decomposable into the seven jural categories, each enforced by the same domain flag mechanism. The governance layer carries the meaning; the kernel enforces the boundary.

---

## Appendix: the K3 proof and the five-kinds example

The Lean snippet and worked example that follow are the canonical close of this chapter as required by the Wave 1 commission brief.

### The K3 proof (excerpt)

The three sub-theorems from `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` — K3a (mismatch is failure-atomic), K3b (match succeeds), K3c (the check is total) — appear in full in the body of this chapter. The chapter body above is the authoritative presentation; the excerpt below reproduces the theorem statements alone for reference:

```lean
import Semantos.Opcodes.Plexus

namespace Semantos.Theorems
open Semantos Semantos.Opcodes

theorem k3a_domain_flag_mismatch (pda : PDA)
    (h_depth : pda.sdepth ≥ 2) (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_mismatch : cellItem.header.domainFlag ≠ flagItem.header.domainFlag) :
    opCheckDomainFlag pda = .error (.linearityError .domain_flag_mismatch) := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp [hd, h_peek0, h_peek1]
  intro heq; exact absurd heq h_mismatch

theorem k3b_domain_flag_match (pda : PDA)
    (h_depth : pda.sdepth ≥ 2) (flagItem cellItem : Cell)
    (h_peek0 : pda.speekAt 0 = .ok flagItem)
    (h_peek1 : pda.speekAt 1 = .ok cellItem)
    (h_match : cellItem.header.domainFlag = flagItem.header.domainFlag)
    (cell0 : Cell) (pda1 : PDA) (h_pop : pda.spop = .ok (cell0, pda1))
    (pda2 : PDA) (h_push : pda1.spush trueCell = .ok pda2) :
    opCheckDomainFlag pda = .ok pda2 := by
  unfold opCheckDomainFlag
  have hd : ¬(pda.sdepth < 2) := by omega
  simp only [hd, h_peek0, h_peek1, ite_false]
  have hbeq : (cellItem.header.domainFlag != flagItem.header.domainFlag) = false := by
    simp [bne, h_match]
  simp [hbeq, h_pop, h_push]

theorem k3c_domain_check_total (pda : PDA) :
    (∃ pda', opCheckDomainFlag pda = .ok pda') ∨
    (∃ e, opCheckDomainFlag pda = .error e) := by
  cases h : opCheckDomainFlag pda with
  | error e => exact Or.inr ⟨e, rfl⟩
  | ok pda' => exact Or.inl ⟨pda', rfl⟩

end Semantos.Theorems
```

### The five-kinds worked example

> The following traces all five concrete kinds of governance domain through a single allocating operator, showing the flag value, the governing instrument cell, and the `OP_CHECKDOMAINFLAG` enforcement that K3 guarantees for each.
>
> **Trust** (`domainType: 'trust'`, flag `0x00020001`):
> The trustee hat's BRC-52 certificate carries `domainFlags: [0x00020001]`. The trust deed cell has `DomainFlag = 0x00020001`, linearity `RELEVANT`. Fiduciary duty cells have `DomainFlag = 0x00020001`, linearity `LINEAR`. When the trustee executes a distribution, `OP_CHECKDOMAINFLAG` compares the distribution cell's header against `0x00020001`. K3b: match succeeds. K3a: any cell not carrying the trust domain flag causes a failure-atomic error.
>
> **Estate** (`domainType: 'estate'`, flag `0x00030001`):
> The estate title declaration cell has `DomainFlag = 0x00030001`, linearity `RELEVANT`. Lease and maintenance obligation cells carry the same flag. All estate operations — granting leases, recording maintenance obligations, conveying title — are checked against `0x00030001` by `OP_CHECKDOMAINFLAG`. K3 guarantees no estate operation can be performed on a cell stamped with a different domain flag.
>
> **Realm** (`domainType: 'realm'`, flag `0x00040001`):
> The jurisdictional assertion cell has `DomainFlag = 0x00040001`, linearity `RELEVANT`. Cross-realm operations (e.g. from the trust domain to the realm domain) carry a composite constraint in the SIR: `logical_and` of `OP_CHECKDOMAINFLAG(0x00020001)` and `OP_CHECKDOMAINFLAG(0x00040001)`. Both checks are individually K3-proven; both must pass for the cross-realm operation to succeed.
>
> **Corporate** (`domainType: 'corporate'`, flag `0x00050001`):
> The articles cell has `DomainFlag = 0x00050001`, linearity `RELEVANT`. Director delegation is recorded in the `DomainBinding.delegation` field of corporate action SIR nodes. Board resolutions and officer-authorised contracts are stamped `0x00050001`. `OP_CHECKDOMAINFLAG` enforces that no cell from outside the corporate domain participates in corporate governance operations.
>
> **Cooperative** (`domainType: 'cooperative'`, flag `0x00060001`):
> The founding instrument cell has `DomainFlag = 0x00060001`, linearity `RELEVANT`. Member proposals are `RELEVANT`; ballots are `LINEAR` (a vote is consumed once cast and cannot be recast — K1 enforces this alongside K3). Quorum conditions are condition-jural SIR nodes scoped to `0x00060001`. `OP_CHECKDOMAINFLAG` ensures that only members whose hat certificates carry `0x00060001` can participate in the cooperative's collective governance decisions.
>
> In all five cases, the enforcement is structural and bytecode-level. The governance meaning is carried by the SIR; the isolation is guaranteed by K3.
