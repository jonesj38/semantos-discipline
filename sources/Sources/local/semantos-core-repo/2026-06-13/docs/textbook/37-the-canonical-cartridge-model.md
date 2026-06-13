---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/37-the-canonical-cartridge-model.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.646110+00:00
---

# The Canonical Cartridge Model

**Part X — The Apps Side, Unified**

The first nine parts of this book built the substrate and its grammar
layer. They also accumulated four words for "a thing you install on top
of the substrate": *app*, *extension*, *world-app*, and *adapter*.
Earlier chapters used them more or less interchangeably — Chapter 15
drew a substrate/adapter line, Chapter 28 built "your first adapter",
Chapter 31 described the "extension grammar". This chapter retires all
four words. There is one unit: the **cartridge**. Everything the
previous chapters called an app, an extension, a world-app, or an
adapter is a cartridge, distinguished only by its *role*.

This is not a renaming exercise. The cartridge model fixes a real
fragmentation — the same logical thing (oddjobz, jam-room, tessera,
wallet, the BSV anchor) was previously smeared across `extensions/`,
`apps/`, `apps/world-apps/`, and `packages/*_experience`, with five
parallel metadata systems and no single binding between a cartridge's
Brain half and its UI half. The model collapses that to one unit, one
manifest, one ownership primitive, two loaders.

Canonical sources: `docs/design/CANONICAL-CARTRIDGE-MODEL.md` (the
ratified model, decisions C1–C6), `docs/design/CARTRIDGE-MARKETPLACE-
OWNERSHIP.md` (Decisions A/B/C — ownership, composition, economics),
`docs/design/SELLABLE-NODE-LICENSE.md` (N1–N4 — the node is itself a
cartridge-shaped, license-gated, sovereign asset), and
`docs/canon/commissions/wave-canonical-cartridge.md` (the migration).

---

## One unit, one definition

A **cartridge** is the single canonical packaging, ownership, and
composition unit. Concretely it is:

- **One directory, one manifest.** A cartridge is described by exactly
  one `cartridge.json` (the evolved `ExtensionManifest`). It does not
  scatter its truth across `manifest.ts` + `capabilities.ts` +
  `lexicon.ts` + a Zig mirror + a separate Flutter package. The
  manifest is the source; canon registries (`lexicons.yml`, the §9 cap
  table, the unification matrix) are *rendered* from it, never a
  parallel truth.

- **Role-classified.** Every cartridge declares a `role`:
  - `infra` — provides adapter interfaces other cartridges consume
    (wallet, headers, BSV anchor). It MUST declare `provides`. *This is
    what Chapter 15 called the substrate/adapter boundary and Chapter
    28 called "an adapter".*
  - `experience` — a user-facing vertical (oddjobz, jam-room, tessera).
    It typically has a PWA surface. *This is what earlier chapters
    called an "app" or "world-app".*
  - `grammar-lexicon` — pure vocabulary/grammar, no Brain handlers.
    *This is the declarative core Chapter 31 called the "extension
    grammar".*

- **Two parts, bound by the manifest.** A cartridge has a *Brain part*
  (cells, FSM/flows, handlers) and a *PWA-experience part* (its Flutter
  surface). The manifest's `experience.flutterPackage` field is the
  single binding that collapses the old `extensions/<id>` ↔
  `packages/<id>_experience` split. There is no longer an unowned
  relationship between a cartridge's logic and its UI.

- **Owned by a license UTXO.** A cartridge's owner is the key its
  **affine PushDrop license UTXO** is P2PK-locked to (Marketplace
  Decision A). Acquisition is an atomic pay-for-rights transaction
  (Decision C); revocation is spending the UTXO. The Brain gates
  loading on that license via the proven K15/SW2 indexer-less BEEF SPV
  path — the same machinery Part II built for capabilities. Ownership
  is cryptographic, not a directory convention.

- **Composed, never inherited.** Cartridges build on each other only
  through typed `consumes`/`provides` adapter interfaces (Decision B).
  There is no cartridge-to-cartridge `extends` edge — that would couple
  two owners' revocation and royalty surfaces. (Grammar *version*
  inheritance, Chapter 31's `GrammarExtends`, is a different plane:
  grammars may version-extend grammars; cartridges never extend
  cartridges.)

## Two shells, one model

The cartridge is loaded by exactly two shells, both reading the *same*
`cartridge.json`:

- **The Brain shell** discovers cartridges on disk, resolves the
  `consumes`/`provides` graph (infra before experience), applies the
  license gate, registers each cartridge's verbs/handlers into the
  dispatcher and hat registry, and advertises the served set at
  `GET /api/v1/info`’s `cartridges[]`. Adding a cartridge is a
  filesystem operation, not a code change.

- **The PWA shell** (`semantos-shell`) reads that discovery list and
  renders each experience cartridge through a `CartridgeRegistry` that
  every experience package self-registers into (`cartridge_sdk`).
  Dart has no runtime package loading, so the experience package is a
  compile-time dependency — but the shell's *routing logic* is generic:
  it iterates the registry filtered by what the Brain serves. Adding a
  cartridge needs no edit to the router or shell logic.

The identity/discovery half of a cartridge is Flutter-free (it is what
`/api/v1/info` carries and what `semantos_core` exposes as
`CartridgeDescriptor`); the Flutter binding (`CartridgeEntry`,
`buildScreen`) lives in `cartridge_sdk`. The substrate stays pure.

## What this supersedes

| Earlier chapter / term | Now |
|---|---|
| Ch.15 "substrate vs adapter" | substrate is unchanged; "adapter" → an **infra cartridge** that `provides` |
| Ch.28 "build your first adapter" | build your first **cartridge** (role: infra or experience) |
| Ch.31 "extension grammar" | a cartridge's `grammar`/`lexicon` sections; "extension" → cartridge |
| "app" / "world-app" (Ch.16, jam-room) | an **experience cartridge** |
| lexicons as a parallel registry | `lexicons.yml` is *rendered* from the cartridge's lexicon source (the Lean/TS proof stays truth) |

Those chapters' *mechanics* (the substrate primitives, the grammar
formats, the kanban walkthrough) remain correct and are still worth
reading; only the packaging/ownership/vocabulary frame is replaced by
this chapter. Where they say "extension", "adapter", or "app", read
"cartridge of role X".

## The node is a cartridge-shaped asset too

`SELLABLE-NODE-LICENSE.md` (N1–N4) extends the same primitive to the
node itself: a node is provisioned against a buyer-minted BRC-52 cert,
the provisioner is cryptographically data-blind, and network
participation is gated by an affine node-license UTXO layered over the
Phase-35B signed-License identity (the kill-switch). Selling or moving
a node decomposes into spending an authority UTXO + replaying the
content-addressed cell-DAG — the cartridge ownership model, scoped to
the whole node.

---

The rest of this book's substrate chapters are unaffected. From here
on, "cartridge" is the only word for an installable unit; "app",
"extension", "world-app", and "adapter" survive only as informal
English for a cartridge of the matching role.
