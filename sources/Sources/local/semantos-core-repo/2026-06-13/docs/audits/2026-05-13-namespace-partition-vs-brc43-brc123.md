---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-13-namespace-partition-vs-brc43-brc123.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.751567+00:00
---

# GD9 Audit — Namespace Partition vs BRC-43 / BRC-123

**Date:** 2026-05-13
**Triggered by:** `docs/prd/UNIFICATION-ROADMAP.md` §11.6 GD9 — "namespace partition cross-check pending"
**Author:** Tier-C burst iter 5 (autonomous doc burst on `feat/unification-doc-burst-2026-05-13`)
**Inputs:** §8 Q2 of UNIFICATION-ROADMAP, `core/plexus-contracts/src/domain-flags.ts`, BRC-43, BRC-123

---

## TL;DR

**No alignment action required.** §8 Q2's uint32 partition and BRC-43 / BRC-123's text namespaces address **different concerns** that do not intersect:

- §8 Q2: uint32 flag-typed IDs (domain flags, lexicon ids, region types, msgTypes, tenant types)
- BRC-43: text-based protocol IDs in BRC-42 key-derivation invoice numbers
- BRC-123: text-based basket identifiers in BRC-46 output baskets

However the audit surfaced two **separate** real findings worth tracker entries:

1. **§8 Q2's central module is unimplemented.** The mandated `core/protocol-types/src/namespace.ts` with `isPlexusReserved` / `isExtendedPlexus` / `isOperatorSovereign` predicates does not exist. A two-tier subset is implemented in `core/plexus-contracts/src/domain-flags.ts` instead.
2. **Tier 2 of §8 Q2's three-tier scheme is currently empty.** All shipped Plexus flags fit Tier 1 (`0x00–0xFF`); all shipped client flags fit Tier 3 (`≥0x00010000`). The middle "extended Plexus" range is reserved but unused — possibly indicating the three-tier scheme is over-engineered for current needs, or possibly indicating Tier 2 is the right home for forthcoming Plexus extensions yet to ship.

---

## 1. The three specifications

### §8 Q2 (UNIFICATION-ROADMAP)

Decision verbatim from `docs/prd/UNIFICATION-ROADMAP.md` Q2:

> The same uint32 partition (Plexus reserved `0x00000001`–`0x000000FF`, extended Plexus `0x00000100`–`0x0000FFFF`, operator sovereignty `0x00010000`–`0xFFFFFFFF`) MUST apply to every flag-typed id type in the substrate: domain flags, lexicon ids, region types, world-frame `msgType`s, tenant types, and any future id type.
>
> The partition MUST be codified once in `core/protocol-types/src/namespace.ts` exporting (at minimum) the predicates `isPlexusReserved(flag) | isExtendedPlexus(flag) | isOperatorSovereign(flag)` and the named ranges.

**Scope:** uint32 integer IDs. Single source of truth via shared predicates. Applies to "any future id type" — explicitly extensible.

**Three tiers:**

| Tier | Range | Mnemonic |
|---|---|---|
| 1 | `0x00000001` – `0x000000FF` | Plexus reserved |
| 2 | `0x00000100` – `0x0000FFFF` | Extended Plexus |
| 3 | `0x00010000` – `0xFFFFFFFF` | Operator sovereignty |

### BRC-43 — Security Levels, Protocol IDs, Key IDs, Counterparties

**Scope:** Invoice number format for BRC-42 secure key derivation. Three components separated by hyphens: `<securityLevel>-<protocolID>-<keyID>`.

**Format choices:**

- **Security levels:** integers 0, 1, 2 (small enum, not a partition)
- **Protocol IDs:** **text strings**, not integers
  - normalization rules: lowercase, no multiple spaces, ≤280 chars, ≥5 chars, must not end with "protocol"
  - no explicit partition; references BRC-44 for reserved IDs but does not list a partition scheme
- **Key IDs:** strings, 1–1033 bytes
- **Counterparties:** `"self"` / `"anyone"` / pubkey

**Verdict:** BRC-43 governs *text identifiers in key-derivation invoice numbers*. No uint32 partition. No overlap with §8 Q2's domain — different alphabet (string vs uint32), different scope (key derivation vs flag-typed IDs).

### BRC-123 — Basket Identifier Namespace Framework

**Scope:** Wallet basket identifiers per BRC-46 output baskets. Hierarchical **text-based** namespace, explicitly limited to baskets.

**Five-tier scheme:**

| Tier | Pattern | Example |
|---|---|---|
| 0 (System) | `"default"`, `"admin *"` | `"admin tools"` |
| 1 (Module) | `"p <module-id> "` | `"p brc99-foo "` |
| 2 (Protocol) | single alphabetic word + `:` | `"pool:"` |
| 3 (Application) | domain-prefixed `<host>:<id>` | `"example.com:wallet"` |
| 4 (Unreserved) | simple names | `"my-basket"` |

**Explicit scope limit:** "This framework applies exclusively to basket identifiers in BRC-46 output baskets. The document contains no evidence of extension to other flag-typed IDs or non-basket contexts."

**Verdict:** BRC-123 governs *text identifiers in wallet baskets*. No uint32 partition. The five-tier text scheme is structurally similar to §8 Q2's three-tier integer scheme but operates in a different namespace.

---

## 2. The implementation reality

§8 Q2 mandates `core/protocol-types/src/namespace.ts`. That file **does not exist**.

What ships today instead:

### `core/plexus-contracts/src/domain-flags.ts`

```ts
/**
 * Domain flag namespace boundaries.
 *
 * Per Plexus Technical Requirements v1.3 — Contracts Library (component 3):
 * - 0x00000001–0x0000FFFF: Plexus standard/extended flags
 * - 0x00010000–0xFFFFFFFF: Client-defined sovereignty
 */
export const PLEXUS_RESERVED_MAX = 0x0000ffff;
export const CLIENT_BASE = 0x00010000;

export const PlexusStandardFlags = {
  EDGE_CREATION: 0x01,
  ATTESTATION:   0x05,
  METERING:      0x0a,
  ZONE_KEY:      0x0b,
  MESSAGING:     0x0c,
  HOST_EXEC:     0x0d,
} as const;

export const ClientDomainFlags = {
  VIEW:           0x00010001,
  CREATE:         0x00010002,
  EDIT:           0x00010003,
  // ...
  HOST_EXEC:      0x0001000b,
} as const;
```

**This is a two-tier collapse of §8 Q2's three-tier scheme:**
- §8 Q2 Tier 1 (Plexus reserved, `0x01–0xFF`) and Tier 2 (Extended Plexus, `0x100–0xFFFF`) are merged into a single "Plexus standard/extended" zone
- §8 Q2 Tier 3 (Operator sovereignty, `≥0x10000`) maps directly to `CLIENT_BASE`

**Where it sits architecturally:** in `core/plexus-contracts/`, not `core/protocol-types/`. §8 Q2 mandates the latter — single source of truth for *every* flag-typed ID in the substrate, including lexicon ids and region types that are not domain flags.

### What §8 Q2's predicates would catch that the current code does not

Search across `core/protocol-types/`, `core/plexus-contracts/`, `core/cell-engine/`:

```
grep -rn "isPlexusReserved|isExtendedPlexus|isOperatorSovereign" core/
→ (no results)
```

None of the predicates exist. Every flag-typed ID consumer that needs to ask "is this a Plexus flag?" either:

1. Imports `PLEXUS_RESERVED_MAX` / `CLIENT_BASE` from `domain-flags.ts` directly (couples to the two-tier collapse)
2. Open-codes the check against literal values
3. Doesn't check at all (relies on producer-side discipline)

This is exactly the bug class §8 Q2 was authored to prevent: "two id types independently re-derive the partition and disagree at the boundary."

### Tier 2 is currently empty

Among all flags shipped in `domain-flags.ts`:
- All `PlexusStandardFlags` values: `0x01, 0x05, 0x0a, 0x0b, 0x0c, 0x0d` — all in §8 Q2 Tier 1 (`0x01–0xFF`)
- All `ClientDomainFlags` values: `0x00010001`–`0x0001000b` — all in §8 Q2 Tier 3 (`≥0x00010000`)

The middle range (`0x00000100`–`0x0000FFFF`, §8 Q2 Tier 2 "Extended Plexus") is **reserved but unused**. Two possible interpretations:

- **(a) Three tiers are over-engineered.** Two tiers (Plexus + Client) suffice; §8 Q2's middle range is dead space and should be collapsed in a future revision.
- **(b) Three tiers anticipate future Plexus extensions.** Tier 1 is hard-reserved for the smallest, most-frequently-checked Plexus flags; Tier 2 is for Plexus extensions that don't merit a single-byte slot but still belong to Plexus rather than operator. The current code hasn't yet shipped a Tier 2 flag because Plexus hasn't outgrown the single-byte range.

Without more context, (b) is the charitable read — the partition design is forward-looking. But this should be a deliberate decision, not a forgotten accident.

---

## 3. Cross-spec compatibility matrix

| Concern | §8 Q2 | BRC-43 | BRC-123 |
|---|---|---|---|
| Identifier type | uint32 | text string | text string |
| Domain | flag-typed IDs (domain flags, lexicon ids, region types, msgTypes, tenant types) | protocol IDs in key-derivation invoice numbers | basket identifiers in output baskets |
| Tiers | 3 (Plexus / Extended Plexus / Operator) | none (normalization rules) | 5 (System / Module / Protocol / Application / Unreserved) |
| Reservation mechanism | numeric range | references BRC-44 for reserved | hierarchical text patterns |
| Extensibility scope | "every flag-typed id type ... and any future id type" | "some protocol IDs ... used internally" | "exclusively to basket identifiers ... no extension to other flag-typed IDs" |
| Cross-applicable? | Plexus-internal | BRC standard | BRC standard |

**Conclusion:** No conflict. §8 Q2 governs uint32 namespaces; BRC-43 and BRC-123 govern text namespaces with different scopes. They operate in non-intersecting domains.

If Semantos ever introduces:
- **BRC-42 key-derivation invoice numbers** with protocol IDs → adopt BRC-43 format and cross-check BRC-44 reserved list
- **BRC-46 wallet baskets** with text identifiers → adopt BRC-123 five-tier scheme

Neither requires changes to §8 Q2's uint32 partition. Neither is currently in scope.

---

## 4. GD9 recommendations

### Recommendation 1: Implement the §8 Q2 central module (priority: medium)

Create `core/protocol-types/src/namespace.ts` exporting:

```ts
/**
 * Per §8 Q2 of docs/prd/UNIFICATION-ROADMAP.md (resolved 2026-04-26):
 * Three-tier uint32 partition applying to every flag-typed ID in the substrate.
 */
export const PLEXUS_RESERVED_MAX  = 0x000000ff;
export const EXTENDED_PLEXUS_MAX  = 0x0000ffff;
export const OPERATOR_BASE        = 0x00010000;

export function isPlexusReserved(flag: number): boolean {
  return flag >= 0x00000001 && flag <= PLEXUS_RESERVED_MAX;
}

export function isExtendedPlexus(flag: number): boolean {
  return flag > PLEXUS_RESERVED_MAX && flag <= EXTENDED_PLEXUS_MAX;
}

export function isOperatorSovereign(flag: number): boolean {
  return flag >= OPERATOR_BASE && flag <= 0xffffffff;
}

export function namespaceTier(flag: number): "plexus" | "extended" | "operator" | "invalid" {
  if (isPlexusReserved(flag))    return "plexus";
  if (isExtendedPlexus(flag))    return "extended";
  if (isOperatorSovereign(flag)) return "operator";
  return "invalid";  // 0 or > 0xFFFFFFFF
}
```

This is a ~30 LOC file with unit tests. Path-scoped commit; no other code changes required at landing time.

### Recommendation 2: Migrate `domain-flags.ts` to import from `namespace.ts` (priority: low)

`core/plexus-contracts/src/domain-flags.ts` currently exports its own `PLEXUS_RESERVED_MAX` and `CLIENT_BASE`. After Recommendation 1 lands, deprecate those in favor of `EXTENDED_PLEXUS_MAX` and `OPERATOR_BASE` from `namespace.ts`. Update the boundary semantics:

- `PLEXUS_RESERVED_MAX` (`0x0000ffff`) currently means "max value for Plexus standard/extended flags" — the two-tier collapse. After migration this should be split:
  - `PLEXUS_RESERVED_MAX = 0x000000ff` (Tier 1 max)
  - `EXTENDED_PLEXUS_MAX = 0x0000ffff` (Tier 2 max)

This is a one-line breaking change to the constant's value. Audit every consumer of `PLEXUS_RESERVED_MAX` before migrating; some may be using the old (broader) range as an upper bound, which would still be correct as `EXTENDED_PLEXUS_MAX`.

### Recommendation 3: Resolve Tier 2 intent (priority: low, blocking nothing)

Decide whether the three-tier scheme is forward-looking (option b) or over-engineered (option a). If (b), document the conditions under which a flag should be assigned to Tier 2 vs Tier 1 (e.g. "Tier 1 for flags that need to fit in a 1-byte slot; Tier 2 for everything else Plexus-owned"). If (a), simplify to two tiers and update §8 Q2.

Recommend (b) — keep the three tiers and document the inclusion criteria. Single-byte flag slots appear in cell header offsets (`HeaderOffsets.linearity` is 4 bytes, but per-cell-bit pack formats elsewhere may want single-byte flags). Reserving Tier 1 for the smallest is forward-looking and cheap.

### Recommendation 4: Update §8 Q2 status (priority: trivial)

Append a note to §8 Q2 in `docs/prd/UNIFICATION-ROADMAP.md`:

> **Implementation status (audit 2026-05-13):** Partial. `core/plexus-contracts/src/domain-flags.ts` implements a two-tier collapse (Plexus / Client) of the three-tier scheme. The central module `core/protocol-types/src/namespace.ts` mandated by this decision does not yet exist; predicates `isPlexusReserved` / `isExtendedPlexus` / `isOperatorSovereign` are unimplemented. Tier 2 (Extended Plexus, `0x00000100`–`0x0000FFFF`) is currently empty. See `docs/audits/2026-05-13-namespace-partition-vs-brc43-brc123.md`.

---

## 5. GD9 resolution

§11.6 GD9 says:

> **GD9 — Namespace partition cross-check pending.** §8 Q2 codified our uint32 partition in `core/protocol-types/src/namespace.ts`. BRC-43 (Security Levels, Protocol IDs, Key IDs, Counterparties) and BRC-123 (Basket Identifier Namespace Framework) may already provide a compatible partition. Pre-implementation audit required: align or document intentional divergence. Not a new deliverable; a constraint on the next change to `namespace.ts`. (BRC sweep 2026-05-13.)

**Audit result: intentional divergence (no alignment).** §8 Q2's uint32 partition addresses a different concern than BRC-43 (text protocol IDs in key derivation) and BRC-123 (text basket identifiers in wallets). No conflict; no alignment work required.

**Side findings (not part of GD9's scope but surfaced by the audit):**

- `core/protocol-types/src/namespace.ts` does not exist; §8 Q2 is partially-implemented in `core/plexus-contracts/src/domain-flags.ts` as a two-tier collapse
- Tier 2 (Extended Plexus) is empty in shipped code

Recommendations 1–4 above address the side findings. None is blocking; all are tracker-worthy additions to the §11 supplement work.

GD9 can be marked **resolved** as a cross-check result. The side findings become a new sub-deliverable (recommend `D-NS-1` through `D-NS-3`) under the §11.2 deliverable list.

---

## 6. Sources referenced

- `docs/prd/UNIFICATION-ROADMAP.md` §8 Q2 (decision) and §11.6 GD9 (audit trigger)
- `core/plexus-contracts/src/domain-flags.ts` (current implementation)
- `core/protocol-types/src/identity.ts:560-563` (consumer using `domainFlag` values)
- `core/protocol-types/src/agent-context.ts:88` (default domain flag `0x00020001` — Tier 3)
- BRC-43 — Security Levels, Protocol IDs, Key IDs, Counterparties: <https://github.com/bitcoin-sv/BRCs/blob/master/key-derivation/0043.md>
- BRC-44 — Admin-reserved and Prohibited Key Derivation Protocols: <https://github.com/bitcoin-sv/BRCs/blob/master/key-derivation/0044.md>
- BRC-123 — Basket Identifier Namespace Framework: <https://github.com/bitcoin-sv/BRCs/blob/master/wallet/0123.md>
- BRC-46 — Wallet Transaction Output Tracking (Output Baskets): <https://github.com/bitcoin-sv/BRCs/blob/master/wallet/0046.md>
