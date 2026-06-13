---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CARTRIDGE-SCHEMA-EXTENSION-MECHANISM.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.723589+00:00
---

# Cartridge Schema Extension Mechanism — Design

**Version**: 0.1
**Date**: 2026-05-20
**Status**: RATIFIED (Todd 2026-05-20 — "yeah as recommended"). Resolves the ambiguity surfaced while sketching plumber/cleaner mock cells against oddjobz's canonical schema: *"are they cartridges on cartridges, or just layers of type managers?"*
**Parent / composes with (RATIFIED — this resolves a gap, not re-decides):**
- `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` §4.1 (manifest-declared schema; `tier`)
- `docs/design/CANONICAL-CARTRIDGE-MODEL.md` C2 (manifest-as-source), C7 (`brain.surface`), §4 (Decision B `consumes`/`provides`)
- `docs/design/CC5-SCHEMA-SECTION-IMPL-SPEC.md` v0.3 (the `tier:'core'|'operator-extensible'` annotation landed via #469)
- `docs/design/CC7-SCHEMA-RENDERER-IMPL-SPEC.md` v0.3 §3.5 (per-cartridge `primaryAnchor`/`hierarchy`)
- `docs/SHELL-CARTRIDGES-HATS.md` §172–173 (configs-as-intents)

---

## 0. The question this resolves

CC5.B1 (#469) gave `PayloadSchemaField` a `tier: 'core' | 'operator-extensible'` annotation. That
fixes a field's *ownership tier* but does **not** say **where an operator-extensible field
gets declared**. Three architecturally distinct homes exist:

- **(a)** Static, in `cartridge.json` itself, tier-flagged.
- **(b)** Per-operator overlay declared at provisioning, delivered as a `verb.dispatch`
  config-as-intent.
- **(c)** Composition via `consumes`/`provides` — a derived cartridge that extends a base.

Without a principled split, every "where does this field live?" question is a re-derivation.
This doc settles it.

## 1. The natural line — the ratified resolution

The mechanism is determined by **what is being added**, not by who is adding it:

| Mechanism | Use case | Concrete example |
|---|---|---|
| **(a) Static declaration in `cartridge.json`, tier-flagged** | The cartridge's **own canonical vocabulary** acknowledges a field that may or may not be populated per operator | Todd's `workOrderNumber` / `billingParty` / `issuanceDate` / `propertyKey` / `keyNumber` — these are *oddjobz's* PM-shape acknowledgement; they live in `oddjobz/cartridge.json` with `tier:operator-extensible`. The cartridge *knows about* them; specific operators may or may not populate them. |
| **(b) Per-operator overlay via configs-as-intents** | A field is **truly operator-specific** — the cartridge has no opinion on it; the operator brings it | A plumber's `urgency` / `calloutFee` / `afterHoursMultiplier` for *their* oddjobz instance — oddjobz/cartridge.json doesn't acknowledge these; the operator declares them at provisioning via `verb.dispatch`. Mechanism specified by **CC6** (deferred to CC6's deliverables). |
| **(c) Composition via `consumes`/`provides`** | A trade adds **new objectTypes**, not just fields | A courier cartridge introduces `parcel`/`route` cells — new identity, new `EntityTypeSpec` triple, new `primaryAnchor` (§3.5). Uses the **already-ratified** C2/§4.3 composition machinery. |

**The line tracks the kind of extension:**
- *Acknowledged-optional field within a cartridge's vocabulary* → (a).
- *Truly-operator field outside the cartridge's vocabulary* → (b).
- *Whole new cell type* → (c).

A single cartridge MAY use all three simultaneously; they are orthogonal, not exclusive.

## 2. Why this is the right split

**(a) keeps `cartridge.json` honest** — it declares what the cartridge *acknowledges*
(its full vocabulary), tier-marking which parts are universal vs operator-acknowledged.
The vocabulary is bounded. Todd's PM fields are known to oddjobz (which was designed to
ingest PM work-orders); a plumber's `urgency` is not.

**(b) gives operators true extensibility** without forcing every conceivable trade's fields
into the base cartridge. It uses the *same `verb.dispatch` configs-as-intents pattern*
operators already use for trade-profile / source-adapter configs — no new mechanism class.

**(c) handles new verticals** via the existing ratified composition machinery — not a new
mechanism.

This avoids three failure modes:

1. **Balloon** — every conceivable trade's fields accreting into one `cartridge.json`. (a)-only fails this way.
2. **Fragment** — every trade as a separate cartridge re-declaring shared concepts. (c)-only fails this way.
3. **Code-not-data** — extending the cartridge by editing source files. Status quo today.

## 3. Implications for the in-flight stack

### CC5.B2a (immediate — unblocked by this doc)
Use **(a) only**. `cartridges/oddjobz/cartridge.json` declares oddjobz's full canonical schema
with tier markers — including its PM-shape operator-extensible fields it *acknowledges*
(`workOrderNumber`/`billingParty`/`issuanceDate`/`propertyKey`/`keyNumber`/etc.).
**No plumber/cleaner fields. No new mechanism.** Just the CC5.B1 `tier` annotation +
the §3.5 `primaryAnchor`/`hierarchy` declaration.

### CC6 (when run)
CC6 implements **(b)** as part of its source-adapter / configs-as-intents work. An operator's
provisioning config MAY include payload-schema extensions (additional fields declared on the
cartridge's existing objectTypes). The base cartridge stays unchanged; the operator overlay
composes onto it at load time. CC6 spec to be updated with a sub-row defining the overlay
wire format + the load-time composition rule. **Not in scope for CC5.B2a.**

### §3.5 (already canonical)
**(c)** is the existing composition machinery (`primaryAnchor` + `consumes`/`provides`).
Already shipped via #473.

### Plumber / cleaner fixtures (now defer-justified)
Per (1), they are NOT separate cartridges — they share oddjobz's canonical site/customer/job
schema and add only trade-specific *fields*, not *objectTypes*. They are best modeled as
**(b) per-operator overlays** of oddjobz. Authoring them as fixtures waits on CC6 shipping
the (b) overlay mechanism. Defer until then; producing them now would commit to an unratified
wire format.

## 4. Non-conflation

- **(a) ≠ (b):** (a)'s fields are declared in `cartridge.json` (the *cartridge* owns the
  vocabulary); (b)'s fields are declared at provisioning by the *operator* (the operator
  brings the vocabulary, never seen by the base cartridge).
- **(b) ≠ (c):** (b) extends an existing objectType's `payloadSchema` with additional fields;
  (c) adds a *new* objectType with its own SPEC triple.
- **Todd's framing maps cleanly:** "layers of type managers" = (b); "cartridges on cartridges"
  = (c). Both are valid; the spec now distinguishes them with a principled criterion (what is
  being added), not just style.

## 5. Acceptance (this doc)

1. The (a)/(b)/(c) split is **canon**. Future "where does this field live?" questions resolve
   via the §1 criterion (acknowledged-field / truly-operator-field / new-objectType).
2. CC5.B2a proceeds with **(a) only**; no plumber/cleaner field authoring.
3. CC6 spec to be updated (separately) with a sub-row defining (b)'s overlay wire format +
   load-time composition. Plumber/cleaner conformance fixtures land *after* CC6 ships (b).
4. §3.5 already covers (c). No further work needed for new-objectType cartridges (courier,
   vet, mechanic, etc.).
5. A cartridge MAY use all three mechanisms simultaneously; they compose, not conflict.
