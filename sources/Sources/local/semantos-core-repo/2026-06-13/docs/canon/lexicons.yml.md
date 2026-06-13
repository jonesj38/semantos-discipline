---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/lexicons.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.631359+00:00
---

# docs/canon/lexicons.yml

```yml
# The 8+ lexicons referenced in the doc plan §1.1.
# Source: proofs/lean/Semantos/Lexicons/* + extensions/<vertical>/.
# Schema: docs/canon/README.md#lexiconsyml.
#
# Stage: partial. Trades, jural, calendar, and brap entries added
# in Workstream T. Remaining backfill: CDM, circuit, project-mgmt,
# property-mgmt, risk-assessment, bills-of-lading, control-systems.

lexicons:
  - id: trades
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/Trades.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    extension_re_export: extensions/oddjobz/src/lexicon.ts
    description: |
      Trades / services discourse vocabulary for the oddjobz extension.
      Each category names a distinct discourse move that produces or
      transitions a typed cell in the trades vertical (the Job/Quote/
      Visit/Invoice/Customer/Site/Estimate/Message family per
      ODDJOBZ-EXTENSION-PLAN.md §O2). Categories track speech acts,
      not cells — same pattern as project-management.
    categories:
      - lead
      - estimate
      - quote
      - dispatch
      - visit
      - invoice
      - settle
      - message
    obligations:
      - obligation: headerInjective
        status: proven
        lean_ref: "Semantos.Lexicons.tradesHeader_injective"
        note: |
          The lexicon-level proof obligation per
          Semantos.Substrate.Lexicon. Substrate-level theorems
          (renderCard_deterministic, renderCard_depends_only_on_render_
          fields, renderCard_distinguishes_categories) apply at
          `Patch TradesCategory` by specialisation — no per-lexicon
          re-proof required. See Semantos/Substrate/Lexicon.lean.

  - id: jural
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/Jural.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    description: |
      Legal / Hohfeldian discourse vocabulary. The seven categories are the
      proven constructors of `Semantos.Lexicons.JuralCategory`
      (proofs/lean/Semantos/Lexicons/Jural.lean): declaration, obligation,
      permission, prohibition, power, condition, transfer — the set the
      `juralHeader_injective` theorem is discharged over. Used by the trades
      intent reducer as the SIR category axis for jural speech acts in the
      oddjobz extension. (CC0b 2026-05-17: this entry previously listed
      `immunity`/`null` — a stale parallel truth diverging from the Lean
      proof + TS `JuralLexicon`; corrected to render the proven source.)
    categories:
      - declaration
      - obligation
      - permission
      - prohibition
      - power
      - condition
      - transfer
    obligations:
      - obligation: headerInjective
        status: proven
        lean_ref: "Semantos.Lexicons.juralHeader_injective"

  - id: calendar
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/Calendar.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    extension_re_export: extensions/calendar-ext/src/lexicon.ts
    description: |
      Inter-hat scheduling primitive. Consumed by @semantos/calendar-ext.
      Four categories cover the complete scheduling model: a half-open
      time slot, a multi-slot search window, a conflict between overlapping
      commitments, and the identity hat that owns the slot. The calendar
      extension's API verbs (hold, book, release, cancel, reschedule) all
      reduce to these four category objects.
    categories:
      - slot
      - window
      - conflict
      - hat
    obligations:
      - obligation: headerInjective
        status: pending
        lean_ref: "Semantos.Lexicons.calendarHeader_injective"
        note: Lean file to be authored; TS authority already exists.

  - id: brap
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/BRAP.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    description: |
      Behavioural Risk Assessment Protocol vocabulary. Nine categories encode
      the risk-scoring postures in BRAP's cell-score chain: not-applicable
      (na), not-compliant (nc), not-started (ns), score-established (se),
      score-modified (sm), score-finalised (sf), level-set (ls),
      level-reviewed (lr), level-published (lp). Every patch carries
      lexicon='brap' so the receiver can route to this lexicon's validator,
      rejecting any verb or category outside the set to protect the
      cell-score chain from schema drift.
    categories:
      - na
      - nc
      - ns
      - se
      - sm
      - sf
      - ls
      - lr
      - lp
    verbs:
      - score
      - refine
      - probe
      - mitigate
      - escalate
      - classify
      - accept
      - reject
    obligations:
      - obligation: headerInjective
        status: pending
        lean_ref: "Semantos.Lexicons.brapHeader_injective"
        note: Lean file to be authored; TS authority already exists.

  - id: tessera
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/Tessera.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    extension_re_export: cartridges/tessera/brain/src/lexicon.ts
    description: |
      Care-chain provenance vocabulary for the tessera cartridge.
      Speech acts trace a physical object's journey from origin
      through composition (blend, label), custody transfers,
      environmental events (care-event, excursion), and consumer
      interaction (scan, tasting-note). Used by any vertical where
      the value of a delivered object depends on its handling history
      — wine, premium coffee, cold-chain pharma, art transit.
      Categories track speech acts, not cells — same convention as
      trades, jural, calendar, brap.
    categories:
      - harvest
      - ferment
      - rack
      - blend
      - addition
      - bottle
      - label
      - custody-transfer
      - care-event
      - excursion
      - tamper-event
      - scan
      - tasting-note
    obligations:
      - obligation: headerInjective
        status: proven
        lean_ref: "Semantos.Lexicons.tesseraHeader_injective"
        note: |
          Per-lexicon proof obligation per Semantos.Substrate.Lexicon.
          Discharged in V5.7 of Wave Tessera by exhaustive case analysis
          (analogue of tradesHeader_injective). Substrate-level theorems
          (renderCard_deterministic, renderCard_depends_only_on_render_
          fields, renderCard_distinguishes_categories) apply at
          `Patch TesseraCategory` by specialisation — no per-lexicon
          re-proof required. See Semantos/Substrate/Lexicon.lean.
  - id: self
    status: planned
    lean_file: ""
    ts_file: core/semantos-sir/src/lexicons.ts
    extension_re_export: cartridges/betterment/brain/src/lexicon.ts
    description: |
      Personal practice + Paskian narrative discourse vocabulary for the
      `self` cartridge (T6 / T7).  Each category names a discourse move
      that produces or transitions a self.* cell:
      release-writing, intention-setting, session start/close,
      insight capture, pattern noting, external-intelligence connect,
      QSE vacuum cycle, gold-seal completion, plus the daily-cadence
      accountability shapes (morning intention, evening review,
      dimension pulse, resistance/discernment inquiry).  Sourced from
      configs/extensions/consciousness.json (legacy, since deleted) +
      cherry-picked into cartridges/betterment/cartridge.json flows[] per
      the tick-20 cleanup.  Categories track speech acts, not cells —
      same convention as trades, jural, calendar.
    categories:
      - release
      - intention
      - session
      - insight
      - pattern
      - connect
      - vacuum
      - seal
      - morning
      - review
      - pulse
      - inquire
    obligations:
      - obligation: headerInjective
        status: planned
        lean_ref: ""
        note: |
          Lean obligation `selfHeader_injective` deferred until self
          cells ship in production usage.  Substrate-level theorems
          (renderCard_*) apply at `Patch SelfCategory` by specialisation
          once the per-lexicon proof lands.

```
