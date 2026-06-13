---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CARTRIDGE-PEER-VIEW.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.733638+00:00
---

# CartridgePeerView — How Cartridges Scope the Persona Surface

**Status:** Implemented. `D-cartridge-peer-view-contract` shipped 2026-05-25.
First consumers: `D-oddjobz-peer-view` (Customers) and `D-jambox-peer-view`
(Jammates) shipped in the same PR.

**Substrate dependency:** `D-SCG-persona-projection` (merged 2026-05-23) —
`projectPersona` is the underlying primitive this design composes over.

**Implementation note:** `CartridgePeerView` and `PersonaFace` are declared in
`core/experience-cartridge/src/types.ts` (not a separate `peer-view.ts` file
as originally sketched — kept in types.ts to avoid a fourth small file in the
package). `LoadedCartridge` and `CartridgeInput` both carry `peerView?`.
The brain echoes the field through `/api/v1/info`; the shell reads it from
`ExtensionInfo.peerView` and applies vocabulary to Find→Network.

---

## 1. Motivation in one sentence

> A peer is the same Contact + cells underneath, but the *vocabulary* the
> operator sees ("Customer" vs "Jammate" vs "Friend" vs "Handle") and the
> *face* (commercial / social / topical) depends on the cartridge they're
> looking at it through.

---

## 2. The problem this solves

`projectPersona` shipped as a substrate primitive that returns *all three
faces* of a handle (social / topical / commercial) plus group memberships
plus identity edges. It deliberately knows nothing about vocabulary — it
doesn't know what a "customer" is, doesn't know that jambox peers are
called "Jammates," doesn't know that bsvradar shows raw handles.

The shell-cartridges-hats canon (per `docs/SHELL-CARTRIDGES-HATS.md`) is
explicit: **cartridges consume substrate primitives; they don't redefine
them**. Vocabulary is the canonical example of "stuff that varies between
cartridges and shouldn't live in the substrate."

Without a contract, every cartridge that wants to show peers in its own
language ends up either:
- (a) Reimplementing `projectPersona` with vocabulary baked in (substrate
  violation), or
- (b) Asking the helm to special-case its cartridge (shell-coupling
  violation), or
- (c) Showing peers under their substrate names ("Contact #42 with
  REQUESTS_ACTION edge"), which is unusable.

`CartridgePeerView` is the seam: cartridges *declare* their vocabulary
and lens; the helm's Find→Network surface honours the active cartridge's
declaration. Substrate stays vocabulary-free.

---

## 3. Scope

**In scope.** Vocabulary + face-filter + edge-set scoping for the
Find→Network surface (the desktop Svelte helm + the PWA persona view).
Per-row primary-relation hint for compact rendering. Optional verb
list for "what can I do with this peer" affordances.

**Out of scope.**

- *Substrate behaviour.* `projectPersona` does not change. The peer-view
  is applied *on top* of its output, never inside it.
- *Cartridge-specific cell types.* Already covered by the existing
  cartridge grammar (Phase 36A). Peer-view doesn't redeclare entities.
- *Identity model.* Contact-book BRC-52 cert model stays as-is. A peer
  is always the same Contact across cartridges; only the *view* changes.
- *Cross-cartridge composition.* For v1, one active cartridge → one
  peer-view at a time. Multi-cartridge views (e.g. "show me peers I
  have *both* oddjobz and jambox edges with") are deferred.

---

## 4. Contract shape

### 4.1 TypeScript interface

Declared in `core/experience-cartridge/src/peer-view.ts` (proposed):

```ts
import type { Contact } from '@semantos/contact-book';
import type {
  PersonaFace,
  PersonaFaceFilter,
} from '@semantos/conversation-graph';
import type { RelationKind } from '@semantos/scg-relations';
import type { EdgeType } from '@semantos/contact-book';

export interface CartridgePeerView {
  /** Singular label. E.g. "Customer". */
  readonly label: string;

  /** Plural label for headings. Defaults to `label + "s"` if absent. */
  readonly pluralLabel?: string;

  /** Empty-state text. E.g. "No customers yet — they appear when you
   *  send your first quote." Optional; helm has a default. */
  readonly emptyState?: string;

  /** Include peers that have *any* of these SCG relation kinds where
   *  the peer is either source or target. Empty/absent = no filter on
   *  relation kinds. AND-combined with `filterEdgeTypes`. */
  readonly filterRelationKinds?: ReadonlyArray<RelationKind>;

  /** Include peers that have *any* of these contact-book edge types.
   *  Empty/absent = no filter on edge types. AND-combined with
   *  `filterRelationKinds`. */
  readonly filterEdgeTypes?: ReadonlyArray<EdgeType>;

  /** Which face of the persona projection to foreground when
   *  rendering this peer. */
  readonly defaultFace: PersonaFace;

  /** Optional kind→face filter override; merged with
   *  DEFAULT_PERSONA_FACE_FILTER. */
  readonly faceFilter?: Partial<PersonaFaceFilter>;

  /** Relation kinds to count + surface as per-row primary chips.
   *  E.g. ['REQUESTS_ACTION', 'FULFILLS'] → "3 jobs · 1 fulfilled". */
  readonly primaryRelationKinds?: ReadonlyArray<RelationKind>;

  /** Verb names available on each peer in this view. The helm
   *  renders these as actions in the peer's context menu / detail
   *  drawer. Verbs must be declared in the cartridge's grammar. */
  readonly verbs?: ReadonlyArray<string>;
}
```

### 4.2 cartridge.json field

Cartridges declare their peer view as a top-level optional field in
`cartridge.json`, evaluated by the cartridge loader at boot:

```jsonc
{
  "id": "oddjobz",
  "name": "Oddjobz",
  "role": "experience",
  /* ... existing fields ... */
  "peerView": {
    "label": "Customer",
    "pluralLabel": "Customers",
    "emptyState": "No customers yet — they appear when you send your first quote.",
    "filterRelationKinds": ["REQUESTS_ACTION", "FULFILLS"],
    "defaultFace": "commercial",
    "primaryRelationKinds": ["REQUESTS_ACTION", "FULFILLS", "PAYS"],
    "verbs": ["oddjobz.job.create", "oddjobz.quote.draft"]
  }
}
```

JSON schema slot is added to the Phase 36A grammar schema. Missing
`peerView` means *the cartridge doesn't contribute a peer view* — the
helm falls back to root view when this cartridge is active. (Some
cartridges legitimately have no peer concept; e.g. a games cartridge
might not.)

---

## 5. Filter semantics — declarative, brain-evaluable

Filters are **declarative arrays**, not functions, so the brain can
evaluate them server-side and ship only matching contacts to the helm.
This matches Pattern T (thin-client / brain-as-substrate) chosen in the
shell-port arc — the helm asks the brain "give me the contacts visible
under the oddjobz peer view," the brain runs the join, the helm renders.

The two filter axes are AND-combined when both present:

```
visibleContacts(cartridgeId, hatContext) =
  allContacts(hatContext)
    .filter(c => filterRelationKinds.length === 0 ||
                 c.relations.some(r => filterRelationKinds.includes(r.kind)))
    .filter(c => filterEdgeTypes.length === 0 ||
                 c.edges.some(e => filterEdgeTypes.includes(e.edgeType)))
```

Empty/absent arrays mean "no filter on this axis" — not "match nothing."

### 5.1 Why declarative not function?

A `filter: (Contact[]) => Contact[]` function is more expressive but
requires shipping all contacts to the client and running the filter in
the renderer. Three problems:

1. **Sovereignty.** Pattern T wants the brain to be the source of truth.
   The brain should know which contacts are visible without asking the UI.
2. **Performance.** A contacts list of N=1000 with 5 cartridges loaded
   means 5 full client-side filter passes per hat-switch. Declarative
   filters compile to one SQL/Zig query.
3. **Discoverability.** Tooling (audit reports, federation-peer
   directory, etc.) can inspect the cartridge.json and *predict* which
   peers a cartridge will surface. A function is opaque.

Future escape hatch: if a cartridge needs a filter that can't be
expressed declaratively, it can declare a brain-side walker via the
existing verb-dispatcher and reference it by name
(`filterWalker: "oddjobz.contacts.filter"`). Not in v1.

---

## 6. Wiring into Find→Network

### 6.1 Root view (no active cartridge)

When no cartridge is active (helm default state), Find→Network shows
**all contacts** with **default face filter** and **default vocabulary**:

- Label: "Peer" / "Peers"
- Filter: none — every contact in the active hat is visible
- Default face: `topical` (the most useful default for browsing)
- Face filter: `DEFAULT_PERSONA_FACE_FILTER` from rendering.ts
- Primary chips: none
- Verbs: only root verbs (e.g. `contact.add`, `contact.revoke`,
  `talk.direct.open`)

This is always reachable — either by switching to no-cartridge mode or
by hitting "Show all peers" / "Root view" within Find→Network.

### 6.2 Active cartridge view

When cartridge X is active:

- Helm reads `cartridges[X].peerView` (from cartridge.json, loaded once
  at boot and cached).
- If missing → fall back to root view.
- If present → apply filter (declaratively, via brain), render with the
  cartridge's vocabulary, default face, and per-row chips.

### 6.3 Hat interaction

Hats and cartridges are **orthogonal dimensions** per
`docs/SHELL-CARTRIDGES-HATS.md`:

- The active **hat** scopes which contacts are even visible (cells the
  hat owns + cells shared with this hat). Hat × ContactStore → visible
  contacts.
- The active **cartridge** scopes the vocabulary and face. Cartridge ×
  visible contacts → CartridgePeerView render.

Hat-switching always re-runs the filter chain. Cartridge-switching only
re-evaluates the cartridge layer (visible contacts are unchanged within
a hat).

### 6.4 Peer detail drawer

Tap a peer → drawer opens with:

1. Persona projection rendered with the cartridge's `defaultFace` +
   `faceFilter` (or root defaults).
2. Primary-relation chips (per `primaryRelationKinds`).
3. Verb actions (per `verbs`) dispatched via `verb.dispatch` against
   the brain.
4. "View as root" affordance — collapses the cartridge view and shows
   the persona projection in its raw, all-three-faces form.

---

## 7. Examples

### 7.1 Oddjobz (operational cartridge, commercial face)

```jsonc
"peerView": {
  "label": "Customer",
  "pluralLabel": "Customers",
  "filterRelationKinds": ["REQUESTS_ACTION", "FULFILLS"],
  "defaultFace": "commercial",
  "primaryRelationKinds": ["REQUESTS_ACTION", "FULFILLS", "PAYS"],
  "verbs": ["oddjobz.job.create", "oddjobz.quote.draft"]
}
```

Operator opens Find→Network while oddjobz is active → sees a list of
"Customers" — peers they've quoted, jobbed, or been paid by. Per-row:
"3 jobs · 2 quotes · 1 invoice". Tap a customer → commercial face
(quote history, payment ledger, fulfilment status), plus "Create job
for this customer" and "Draft quote" verbs.

### 7.2 Jambox (world-app cartridge, social face)

```jsonc
"peerView": {
  "label": "Jammate",
  "filterRelationKinds": ["SUBSCRIBES_TO"],
  "defaultFace": "social",
  "primaryRelationKinds": ["SUBSCRIBES_TO"],
  "verbs": ["jambox.invite", "jambox.session.start"]
}
```

Operator switches to jambox cartridge → same Find→Network surface, now
labelled "Jammates" — peers who subscribe to one of the operator's
shared jam-rooms (the SUBSCRIBES_TO target is a jam-room cell). Tap a
jammate → social face (recent jam sessions, set lists, recordings),
plus "Invite to session" verb.

### 7.3 bsvradar (future directory cartridge)

```jsonc
"peerView": {
  "label": "Handle",
  "filterRelationKinds": [],
  "filterEdgeTypes": [],
  "defaultFace": "topical",
  "primaryRelationKinds": ["CITES", "SUPPORTS", "DISPUTES"],
  "verbs": ["bsvradar.follow", "bsvradar.endorse"]
}
```

Directory app — no edge filter, all known handles. Topical face (their
contributions to the broader graph). Primary chips show citation/
support/dispute counts. Verbs let you follow or endorse.

### 7.4 No peer view — games cartridge

A games cartridge (e.g. `extensions/games/chess`) has no peer concept
beyond opponent. It simply omits `peerView` from `cartridge.json`.
When chess is active, Find→Network falls back to root view (per §6.2).

---

## 8. What this is NOT

- **Not a way to hide contacts from a hat.** Hat-level visibility is
  the substrate's job. Peer-view assumes contacts already visible
  under the active hat.
- **Not a replacement for the cartridge grammar.** The grammar declares
  entities and verbs; peer-view declares *vocabulary over peers* and
  *which existing relation/edge kinds to filter on*. They compose.
- **Not a security boundary.** A cartridge that lies in its peer-view
  declaration (e.g. claims `filterRelationKinds: ['ATTESTS']` but
  doesn't actually own ATTESTS-shaped flows) just renders a misleading
  list to its own operator. No substrate state is at risk. (Real
  capability gating is done by `dispatcher.zig` at verb dispatch.)

---

## 9. Open questions

1. **Locale / i18n on labels.** `label: "Customer"` is English. Should
   peerView carry `labels: { en: "Customer", de: "Kunde" }`? Probably
   yes eventually, but v1 is English-only with a clear path to extend
   (the field becomes a string-or-object union).
2. **Sort order.** Should peer-view declare a default sort (recency,
   alphabetical, edge-density)? Or is that a helm-level preference per
   user? v1: helm picks; cartridge may hint later via
   `sortBy?: 'recency' | 'alpha' | 'relationCount'`.
3. **Per-peer badge customisation.** A "VIP" customer or "active jam
   session" status badge? Out of v1 scope — cartridges can decorate
   the detail drawer via `verbs`, but the row itself stays clean.
4. **What about peers I haven't connected with yet?** Discovery
   (BRC-52 cert resolved via federation but no MESSAGING edge) — does
   the peer-view filter include them? Default: yes, with an
   "uncontracted" indicator. Configurable later via
   `includeUncontracted?: boolean`.

---

## 10. Migration plan

1. **No existing peer-view.** All cartridges in tree today (oddjobz,
   jambox, scg, wallet-headers, bsv-anchor-bundle, chess, tessera)
   currently have no `peerView` field. They will all fall back to
   root view until they opt in.
2. **Phase 4 deliverables.** `D-cartridge-peer-view-contract` ships the
   contract + schema; `D-oddjobz-peer-view` and `D-jambox-peer-view`
   ship the first two consumers.
3. **JSON schema.** Add `peerView` to the Phase 36A grammar JSON
   schema. Optional field — old cartridge.json files validate
   unchanged.
4. **Brain endpoint.** `D-brain-contacts-api` (Phase 1) gains a
   peer-view-aware query: `GET /api/v1/contacts?cartridge=oddjobz`
   returns the pre-filtered list. The brain reads the active
   cartridge's `peerView` and applies the declarative filter
   server-side.

---

## 11. References

- `docs/SHELL-CARTRIDGES-HATS.md` — overall shell model
- `docs/canon/deliverables.yml` — `D-cartridge-peer-view-contract` (shell-port-4),
  `D-oddjobz-peer-view`, `D-jambox-peer-view`, `D-svelte-find-network`,
  `D-SCG-persona-projection`
- `core/conversation-graph/src/rendering.ts` — `projectPersona`,
  `PersonaFace`, `PersonaFaceFilter`, `DEFAULT_PERSONA_FACE_FILTER`
- `core/scg-relations/src/types.ts` — `RelationKind` (incl. `SUBSCRIBES_TO`)
- `core/contact-book/src/types.ts` — `Contact`, `EdgeType`
- Memory: `shell_cartridges_hats_model` — cartridges don't redefine
  substrate primitives
