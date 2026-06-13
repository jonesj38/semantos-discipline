---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/EXTENSIONS-VS-TYPES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.328677+00:00
---

# Extensions vs Types: The Four-Tier Model

**Status:** Design note — resolves the conflation surfaced when Claude Code's type-classification pass tried to slot `trades-services`, `blockchain-risk-assessment`, etc. into the 1-3-5 pyramid.

**Date:** 2026-04-16

## The Muddle

The earlier classification pass treated extensions (`trades-services`, `blockchain-risk`, `commerce`) as if they were peers of types or candidates for pyramid slots. They aren't. An extension is a customised workflow that *composes* typed objects and instruments — it lives at a different altitude than both types and contexts.

## The Clean Model: Four Tiers

```
┌──────────────────────────────────────────────┐
│  Extensions (workspaces / verticals)         │  ← installable, shareable
│  trades-services | blockchain-risk |         │     composable, concurrent
│  commerce | academic | household             │
└──────────────────────────────────────────────┘
                    │ composes
                    ▼
┌──────────────────────────────────────────────┐
│  Types (primitives / nouns)                  │  ← atomic vocabulary
│  Document | Event | Invoice | Task |         │     shared across extensions
│  Message | Job | Quote | RiskAssessment ...  │
└──────────────────────────────────────────────┘
                    │ classify into (many-to-many)
                    ▼
┌──────────────────────────────────────────────┐
│  Contexts (the 15 — operational surfaces)    │  ← fixed grammar
│  Transact Manage Create Play Offer  (Do)     │     not installable
│  Self Direct Squad Agent Broadcast  (Talk)   │
│  Memory Market Network Value Truth  (Find)   │
└──────────────────────────────────────────────┘
                    │ focused through
                    ▼
┌──────────────────────────────────────────────┐
│  Helm (the 1 — attention surface)            │  ← single point of focus
└──────────────────────────────────────────────┘
```

## What Each Tier Is

### Extensions (workspaces)

Curated bundles — a set of types, a set of flows, a capability policy, default views, tier-3 popover weights, maybe branded hats. More like a WordPress theme + plugin bundle than a primitive.

`trades-services` isn't a type and it isn't a context. It's a workspace that says: *"when this is active, these are the types that matter, these are the common flows, these are the people I transact with."*

You can have `trades-services`, `blockchain-risk`, `commerce`, `academic`, `household` all installed and toggle between them **or run several concurrently**.

### Types (primitives)

The nouns — `Document`, `Event`, `Invoice`, `Task`, `Message`, `Job`, `Quote`, `Visit`, `RiskAssessment`, `Exposure`. Atomic vocabulary. A type like `Job` might be introduced by the trades extension but once it's in the system it's just a type; another extension can reference it. Types are what compose.

### Contexts (the 15)

Operational modes — verbs-in-a-place. They classify *what kind of action-surface you're on*, not what you're working with. Part of the Semantos grammar, not installable.

### Helm (the 1)

The attention surface. Single point of focus.

## Two Diagnostic Tests

**Test 1 — Concurrency:** Can you have two active simultaneously?
- Extensions: yes. Trades + commerce + household co-populate your type palette at the same time.
- Contexts: no. Transact is a fixed operational position; you can't have two Transacts.

**Test 2 — Shippability:** Is it installable / shareable / marketable?
- Extensions: yes. Someone ships you trades-services, you ship them household.
- Contexts: no. Nobody ships you a "Transact" because Transact is part of the word-stock.

## How They Interact

Types map **many-to-many** into contexts:

- `Invoice` surfaces in Transact, Market, Memory
- `Message` surfaces in Direct, Broadcast
- `Job` surfaces in Transact, Offer, Manage

Extensions don't map into contexts at all — they **re-weight** which types populate the tier-3 popovers.

- Install trades → Transact's popover surfaces `Job`, `Quote`, `Visit` alongside `Invoice`
- Install academic → Create's popover surfaces `Paper`, `Citation`, `Dataset`
- Install blockchain-risk → Value's popover surfaces `Exposure`, `RiskAssessment`

**The pyramid geometry doesn't change; its contents do.**

## Implication for the UI: Two Switchers

The UI probably needs two switchers that are NOT the same:

### Hat switcher (identity)

*Who am I being right now?*

- Work-Todd, Casual-Todd, Academic-Todd
- Determines which keys sign, which social graph is visible, which audit trail the action joins
- Tied to BRC-100 capability presentation

### Extension switcher (workspace)

*What am I doing?*

- Trades business, personal finance, research
- Determines which types and flows are weighted up in the UI
- Determines which tier-3 popover contents appear

They're **correlated** (Work-Todd usually runs the trades extension) but **not identical** — you can put on Work-Todd *and* open the personal-finance extension to approve a household invoice while in a work context.

Conflating them is what WordPress does with multi-site, and it's why WordPress multi-site is awful.

## Extension Manifest (sketch)

An extension declares:

| Field | Description |
|---|---|
| `types` | Which types the extension registers or references |
| `flows` | Common compositions (pipe-and-cat templates) |
| `hat_affinity` | Default hats this extension pairs well with |
| `capability_scopes` | What it's permitted to do under which hats |
| `tier_3_weights` | Which types to surface in each context's popover |
| `views` | Default dashboards / feeds |
| `dependencies` | Other extensions / types required |
| `publication_channels` | Multicast typehashes it subscribes/publishes to |

## Why This Matters Now

The earlier classification pass treated "elevate trades-services to the pyramid" as a valid proposal. It isn't — it's a category error, like asking which drawer in a filing cabinet holds the concept *office*. The office contains the cabinet.

Getting this right *before* the next shell/UI pass prevents a wave of downstream confusion:

- Type registry stays clean (primitives only; extensions are metadata around them)
- Pyramid stays stable (15 contexts, fixed grammar)
- Extensions become a marketplace dimension (installable, shareable, composable)
- UI has a clear switcher model (hat × extension, not one blob)
- Capability gating has two orthogonal axes to reason about

## Next Course of Action (proposed)

1. **Codify the four-tier model** as a first-class part of the core spec (this doc is the draft).
2. **Audit the current "extensions" folder** and confirm each is shaped as a composition, not sneaking in pyramid-level concepts.
3. **Define the extension manifest schema** formally, matching the sketch above.
4. **Add the extension switcher** to the Helm UI spec, distinct from the hat switcher.
5. **Re-run type classification** with extensions removed from the input — only classify primitives into contexts.
6. **Document the many-to-many type↔context mapping** and how tier-3 popover weights are computed from active extensions.

---

*This note captures a mid-brainstorm clarification and should be circulated before the next shell/UI design pass.*
