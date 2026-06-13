---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SEMANTOS-PLATFORM-VISION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.713354+00:00
---

# Semantos: One Brain, Every Domain

**A sovereign substrate for intelligent operations across any vertical**

*2026-05-11*

---

## The Insight

Every domain that involves human coordination — trades, SCADA, clinical care, scientific publication, content creation, agritech, insurance, education — has the same underlying structure: **entities, relationships, obligations, transitions, and conversations**.

The entities differ. The vocabulary differs. The regulatory environment differs. The FSMs differ. But the kernel is invariant: a brain that accumulates typed intelligence over time, reasons over it, converses with the operator, and takes action — scoped strictly to that operator's domain, under their control, on their infrastructure.

Semantos is not an app for trades. It is not a SCADA historian wrapper. It is the **substrate** on which any domain can be expressed as a typed extension grammar, and any operator can run one or many of those grammars inside a single sovereign brain instance.

---

## Substrate, Not Platform

This distinction matters.

A **platform** accumulates leverage over its users. The vendor holds the data, controls the schema, owns the network, and extracts rent. Exit is painful by design — your business intelligence stays behind when you leave. Salesforce is a platform. Shopify is a platform.

A **substrate** is infrastructure you build on and own. It runs under your operations; it doesn't capture them. TCP/IP is a substrate. Linux is a substrate. When you stop using AWS, your code comes with you.

Semantos is a substrate. Concretely:

- **Every cell is the operator's.** Full export, any time, no data hostage.
- **Every extension grammar is portable.** An operator can write their own, own it entirely, publish it independently, or never touch the Semantos marketplace at all.
- **The brain binary is the reference implementation of an open protocol.** An operator could fork it, self-host it, and owe Semantos nothing. The value Semantos provides is in the network — not the lock.
- **Identity is the operator's key, not a vendor-issued account.** BRC-42 derivation from the operator's own root key; the brain doesn't hold your identity, you do.

Semantos the **company** sits above the substrate and provides a network layer: the hosted brain option, the marketplace, the signing authority, the Plexus identity/recovery service. These are genuinely valuable — they make running a brain easier and more powerful — but they are not the dependency trap. An operator who outgrows them can leave without losing anything.

The company's moat is not lock-in. It is:
1. **Trust infrastructure** — signing authority, extension auditing, capability enforcement
2. **Network effects** — the marketplace gets more valuable as more grammars are published
3. **Grammar library** — a growing catalogue of vetted, composable domain extensions
4. **Hosted convenience** — managed brain instances for operators who don't want to run infra

The sovereignty guarantee is what makes operators trust the network in the first place. You cannot have one without the other.

---

## The Pattern (and Why It's Extractable)

### Every vertical reduces to the same stack

| Layer | What it does | Domain-agnostic? |
|---|---|---|
| **Cell store** | Immutable typed knowledge units, isolated per operator | Yes — pure LMDB prefix scheme |
| **Pask graph** | Cybernetic conversation accumulation; amplifies agreement, suppresses noise | Yes — graph is domain-agnostic |
| **Lexicon** | Typed category vocabulary for the domain (lead→quote→invoice; slot→conflict→hat) | **No — this is the extension** |
| **FSM** | Obligation lifecycle for domain entities | **No — this is the extension** |
| **Intake prompt** | LLM primer that maps natural language to the lexicon | **No — this is the extension** |
| **Ratification patterns** | How agreement is reached and recorded as cells | **No — this is the extension** |
| **Site renderer** | Operator-facing public presence | Yes — parameterised by profile |
| **Chat agent** | Conversational surface wired to the brain | Yes — prompted by extension |

The substrate layers (cell store, Pask, site renderer, chat agent, identity, crypto) are built once, maintained once, and never touch domain logic. The domain logic lives entirely in the **extension grammar** — a signed bundle that the brain loads at deploy time.

This is the extractable pattern. You write the grammar for a new vertical. The brain runs it. No new infrastructure.

---

## Extension Grammar: The Unit of Domain Knowledge

An extension grammar is a self-contained, signed bundle that declares:

```
ExtensionManifest
├── meta              (id, version, author, description)
├── lexicon           (typed category vocabulary)
├── cell_types        (typed cell schemas + storage hints)
├── fsm               (entity lifecycle FSMs)
├── intake_prompt     (LLM system prompt fragment)
├── ratification      (how agreement events are recorded)
├── capabilities      (what APIs/streams/permissions required)
├── site_section      (optional: operator site widget fragment)
└── wizard_prompt     (optional: onboarding conversation script)
```

Everything the brain needs to reason in a domain is in that bundle. It is versioned, signed, auditable, and can be installed, upgraded, or removed at runtime without touching the brain binary.

Critically: **the author owns it**. If you write a grammar for your firm's specific workflow, you own 100% of it. You can keep it private, share it with clients, or publish it on the marketplace. Semantos has no claim on the grammar you write any more than Linux has a claim on the software you run on it.

### Already built

| Extension | Domain | Status |
|---|---|---|
| `oddjobz` | Trades (leads → dispatch → invoice → settle) | done — pilot deployment |
| `scada` | Industrial (historian, plant, measurement, authorization) | done — 15/15 intent tests |
| `cdm` | Contract/document (draft, review, sign, obligate, transfer) | done |
| `calendar` | Scheduling (slots, windows, conflicts, hats) | done |
| `policy-runtime` | Capability evaluation (caps, grants, delegation) | done |
| `sites` | Operator site wizard | done |
| `games` | Turn-based game primitives | proof-of-concept |
| `navigation` | Geographic routing and waypoints | proof-of-concept |
| `metering` | Usage measurement and billing signals | proof-of-concept |
| `recovery` | Identity recovery and credential rotation | done |

### Grammar automation pipeline (G-1..G-9)

The grammar pipeline already exists. Given any API spec or domain description:

```
API spec / domain doc
  → G-1: API probe (extract entity verbs)
  → G-2: EntityGraph construction
  → G-3: Pask TaxonomyMapper (classify into lexicon candidates)
  → G-4: GrammarDiff (gap analysis against existing grammars)
  → G-5: auto-grammar.ts (emit ExtensionManifest draft)
  → G-6..G-9: refinement, test scaffold, ratification patterns
  → ExtensionManifest (ready for signing and publication)
```

A new vertical goes from API spec to runnable grammar in hours, not months. Human review validates the draft — the scaffolding is automated.

---

## Vertical Exemplars

### Trades — Oddjobz (pilot)

**Operator:** a plumber, electrician, tiler, or landscaper  
**What the brain does:** captures leads via the intake agent, tracks them through quote → job → invoice → settle, maintains the site, surfaces funnel analytics  
**What's live:** S1–S14 complete; S15 (oddjobtodd.info) pending

**Bootstrap path:**
1. Operator drops legacy site HTML + loose strategy files into the wizard
2. Wizard converses in 4 phases (business profile → ICP → services → call to action)
3. Wizard emits: new site (operator profile cells → HTML), intake agent config (Oddjobz grammar), brain pairing credentials
4. Field app (Flutter) pulls job list, dispatches, logs visit notes
5. Brain accumulates Pask graph over trades conversations — over time, surfaces job patterns, seasonal demand signals, quote-to-close rate

### SCADA / Industrial

**Operator:** a water authority, power station, process plant, agricultural irrigation system  
**What the brain does:** ingests historian time-series cells, maps plant topology, evaluates measurement thresholds against policy cells, surfaces anomalies via the intake agent  
**What's novel:** the SCADA extension grammar includes an `authorization` sublexicon (operator/area/device/measurement/action mapping) that enforces capability policies at the cell layer — operationally this means the brain can reject a valve-close command if the policy cell says the operator doesn't have that grant  
**Intent reducer:** 15 intent tests pass against the SCADA grammar; the intake prompt maps natural language questions ("what was booster pump 3 pressure at 2am?") to typed historian queries

### CDM — Contract and Document Management

**Operator:** a law firm, a commercial property manager, a procurement function  
**What the brain does:** stores contract cells (draft/review/sign/obligate states), tracks counterparty obligations, fires reminders on deadline cells  
**Jural lexicon:** declaration / obligation / power / immunity / condition / transfer / null — maps directly to Hohfeldian legal primitives; every contract state transition is a typed ratification event  
**What's notable:** the jural lexicon is domain-general; you can layer a healthcare consent grammar on top of the same jural primitives without rewriting anything

### Healthcare

**Operator:** a GP clinic, allied health practice, or telehealth provider  
**What the brain does:** patient encounter cells (intake → consult → prescribe → referral → follow-up), clinical obligation tracking (reminders, care plans), consent records (jural lexicon)  
**Privacy model:** patient cells are encrypted under the practice's wrapped DEK; the brain never sees plaintext — it reasons over typed metadata and structured ratification events; full clinical text stays in the encrypted cell  
**What needs to be built:** a healthcare extension grammar (G-1..G-9 pipeline can scaffold it from an HL7 FHIR spec in a few hours); HIPAA/AHPRA ratification patterns

### Agritech

**Operator:** a farm, a co-op, a precision agronomy service  
**What the brain does:** field cells (soil, crop, weather, irrigation, yield), job cells (planting, spray, harvest dispatch), market cells (commodity price signals → sell/hold obligation)  
**Existing leverage:** the SCADA grammar covers IoT sensor historian cells; the calendar grammar covers seasonal scheduling windows; the CDM grammar covers offtake contracts  
**What needs to be built:** an agritech grammar composing the above into a coherent intake prompt and FSM tailored to agronomic vocabulary

### Insurtech

**Operator:** an MGA, a captive insurer, or a broker  
**What the brain does:** policy cells (risk → quote → bind → premium → claim → settle), claims intake via conversation, ratification events as blockchain-verifiable audit cells  
**Jural leverage:** insurance is an obligation system; the jural lexicon (obligation/condition/power/transfer) maps directly to policy terms  
**What's notable:** the sovereign audit cell trail (every state transition is a signed cell) means the brain produces a compliance record as a byproduct of normal operation

### Scientific Publication

**Operator:** a researcher, a lab, a journal  
**What the brain does:** tracks manuscript cells (draft → peer-review → revision → accept/reject), citation cells, dataset version cells, reproducibility attestation cells  
**Pask value:** the brain accumulates researcher conversation over time — it knows which datasets are in play, which reviewers have been responsive, which journals are in scope; it surfaces this context in the intake agent without the researcher re-explaining it each time  
**What's distinctive:** the review process is a typed FSM; the brain can track reviewer obligations and fire reminders on deadline cells — something no existing journal submission system does natively

### Content Creation

**Operator:** a YouTuber, a newsletter writer, a podcast producer  
**What the brain does:** content cells (brief → draft → edit → publish → distribute), asset cells (media, transcripts, thumbnails), analytics cells (views, subs, revenue), sponsorship obligation cells  
**Side hustle framing:** a tradie who runs Oddjobz on their brain and wants to start a YouTube channel about their trade installs the `content-creation` extension grammar; one brain, two hats, no new infrastructure  
**Pask value:** the brain connects content performance cells to the trade's client acquisition funnel — "your tutorial on grout sealing drove 12 new inquiries this quarter"

### Coaching

**Operator:** a life coach, executive coach, sports coach, or educator  
**What the brain does:** client cells (intake → goal-setting → session → progress → outcome), commitment cells (coach and client obligations), insight cells (Pask graph captures what's working across clients, anonymised)  
**What's ethically interesting:** the brain never learns across operators; each coach's client cells are isolated by op_pkh; a coaching marketplace can exist without the brain vendor having any access to client content

---

## The Personal Brain: Your Operating System

The brain is not an app. It is the substrate you run apps on.

A single brain instance is capable of holding multiple **hats** — operator contexts that run different extension grammars simultaneously. A hat is a named context with its own:
- Active extension grammar (lexicon, FSMs, intake prompt)
- NATS stream (`op.<op_pkh16>.<hat>.fsm_transition`)
- Pask graph partition
- Cell namespace (same LMDB env, same op_pkh prefix, different hat tag in cell metadata)

This means the same brain can be:
- A tradie running Oddjobz (hat: `trades`)
- A content creator running a YouTube channel (hat: `content`)
- A researcher tracking a grant (hat: `research`)
- A property manager handling leases (hat: `cdm`)

No new brain to provision. No new identity to manage. No new billing. The operator discovers extensions in the marketplace, installs them, and a new hat activates. The brain routes incoming events to the right hat's intake handler.

The brain becomes the operator's **personal operating system for their working life** — not locked into one vertical, not dependent on any SaaS vendor, not ownable by any platform.

---

## The Bootstrap Flow (Any Vertical)

The same 7-step sequence works for any operator in any domain:

```
1. Operator has: legacy site HTML, strategy documents, pricing sheets, any existing 
   client data export

2. Drop into wizard
   → Wizard converses: business profile / ICP / service taxonomy / call to action
   → Wizard maps natural language to the extension grammar's lexicon

3. Wizard emits:
   → operator_profile cells (site: hero, services, pricing, analytics widget)
   → intake_agent_config cells (grammar-specific system prompt + ratification patterns)
   → brain_pairing_credentials (brain domain, WSS endpoint, BRC-42 key derivation path)

4. brain site-publish <domain> + brain deploy
   → Operator site goes live on their domain (BYOD TLS, SNI-routed)
   → Chat agent is live on operator site
   → Brain is receiving and routing events

5. Legacy ingest (if applicable)
   → Client CSV / legacy CRM export → typed cell migration
   → Existing business intelligence lands in the brain's Pask graph
   → First conversation with the brain is already informed by years of history

6. Field app pairing
   → Operator's mobile app (Flutter) pairs with the brain via WSS + BRC-42
   → Events flow: job updates, visit notes, photos → cells
   → Dispatch, invoicing, client comms routed through the brain

7. Accumulation begins
   → Every conversation, every job, every client interaction is a typed cell
   → Pask graph amplifies patterns over time
   → 90 days in: the brain knows the operator's business better than any CRM
```

The wizard is the onboarding UX. The grammar is the domain model. The brain is the runtime. The operator never writes code.

---

## The Extension Marketplace

The marketplace is a **network service** provided by Semantos, not a structural requirement of the substrate. An operator can install a grammar directly from a URL, a file, or a private registry. The marketplace is valuable because it provides trust infrastructure (signing, auditing, compatibility checks) and discovery — not because it's the only path.

### Economics

| Actor | Cut | Mechanism |
|---|---|---|
| Extension author | 70% | `extension_publish` → signed bundle; revenue attached to install count |
| Semantos network | 30% | Infrastructure, distribution, signing authority, fraud prevention |

Revenue flows are tracked as **metering cells** in the brain — every extension install is a cell event; billing is derived from cell accumulation, not from a separate billing system.

### Discovery

An operator with a brain instance can query the marketplace by:
- Domain keyword ("I want to manage rentals")
- Capability ("I need contract tracking")
- Compatibility (which extensions compose cleanly with installed hats)

The brain's intake agent can surface relevant extensions in conversation: "You mentioned you're starting to write tutorials — there's a content-creation grammar in the marketplace that wires into your existing trades Pask graph."

### Trust

Every extension bundle is:
- **Signed** by the author's BRC-42 identity
- **Audited** before listing (capability declarations must match actual cell access patterns)
- **Sandboxed** by the brain's capability policy system (policy-runtime extension enforces declared caps)
- **Revocable** without data loss (uninstall removes the grammar, the cells remain in the brain)

An extension author cannot access another operator's cells. The capability declarations in the manifest are enforced at the cell layer, not by convention.

---

## Why This Is Different From SaaS

| | SaaS | Semantos substrate |
|---|---|---|
| **Data ownership** | Vendor's database | Operator's LMDB + Postgres, their infrastructure |
| **Identity** | Vendor-issued account | BRC-42 derivation from operator's root key; portable |
| **Domain model** | Vendor's schema | Operator installs a grammar; can replace or write their own |
| **Accumulation** | Silo'd in vendor's platform | Pask graph is the operator's sovereign asset |
| **Exit** | Data export (partial, lossy) | Full cell dump; brain is self-contained |
| **Multi-domain** | Pay per SaaS, manage N logins | One brain, N hats, one identity |
| **Extension economics** | Vendor's app store (vendor decides what's allowed, takes 30%+) | Open signing authority; 70/30; operator chooses what to install |
| **Legacy ingest** | Manual import tool (if any) | Any structured export → cell migration; legacy intelligence preserved |
| **Vendor dependency** | Hard — data stays behind | Soft — substrate is open; exit with everything |

The fundamental shift: in SaaS, the vendor accumulates understanding of your business and you rent access to it. In Semantos, **the operator accumulates understanding in cells they own**, and the vendor provides the substrate and network to run it on — and earns its place in that relationship by being genuinely better than going it alone, not by being impossible to leave.

---

## What's Already Built

| Capability | Status |
|---|---|
| Sovereign cell store (LMDB, op_pkh isolation, W7.1) | done |
| Postgres RLS (multi-tenant data isolation, W7.2) | done |
| Pask graph per operator (snapshot store, W7.10) | done |
| WSS auth + identity (BRC-52/42, W7.4/W7.5) | done |
| BYOD TLS + SNI routing (W7.14/W7.15) | done |
| Operator site renderer (S1–S14) | done |
| Site-publish + site-preview CLI | done |
| Grammar automation pipeline (G-1..G-9) | done |
| Extension manifest format + signing | done |
| Extension publish + subscriber machinery | done |
| Oddjobz grammar (trades vertical) | done — pilot |
| SCADA grammar (industrial vertical) | done — 15/15 tests |
| CDM grammar (contracts vertical) | done |
| Calendar grammar (scheduling) | done |
| Policy-runtime (capability enforcement) | done |
| Lexicons (trades, jural, calendar) | done |

---

## What Needs to Be Built

### Near term (enables pilot → production)

| Item | What it unlocks |
|---|---|
| S15 — oddjobtodd.info live deploy | End-to-end validation; first real operator on brain renderer |
| W7.9 — Plexus provisioning endpoint | Operator onboarding automation; unblocks S6/S9 Flutter |
| W7.11 — Plexus faucet/recovery | Identity recovery for operators |
| S6/S9 — Flutter wizard + dashboard | Operator-facing UX; makes onboarding self-serve |

### Medium term (enables multi-vertical)

| Item | What it unlocks |
|---|---|
| Hat system (multi-grammar routing in one brain) | Multiple extensions per operator |
| Marketplace listing + discovery API | Extension authors can publish; operators can discover |
| Grammar scaffolds for 3–5 new verticals | Healthcare, agritech, content creation, coaching, insurtech |
| Cell migration tools (legacy → brain) | Legacy ingest for any vertical; critical for operator adoption |
| Metering cells + billing derivation | Extension marketplace economics |

### Long term (federation horizon)

| Item | What it unlocks |
|---|---|
| Brain-to-brain cell exchange (BSV) | Multi-party workflows across operator boundaries |
| Federated Pask graph | Collaborative learning without data pooling |
| Verifiable cell provenance (BSV anchoring) | Regulatory-grade audit trail for healthcare/insurance/legal |
| Open substrate specification | Third-party brain implementations; true protocol portability |

---

## The Coherent Vision

Semantos is building the **substrate for sovereign intelligent operations** — the equivalent of Linux for the business brain.

The cell is the atom. The Pask graph is the accumulator. The extension grammar is the domain vocabulary. The brain is the operator's node. The network is the trust layer that makes the marketplace work.

Any domain. One node. Owned by the operator.

The bet is simple: **the value in a business is the accumulated understanding of how it operates** — the patterns in the jobs, the clients, the contracts, the plant, the content, the students. That understanding currently lives in SaaS databases the operator doesn't control. Semantos moves it into a brain the operator runs, so that when they leave a SaaS product, the accumulated intelligence comes with them.

The extension marketplace is what makes the network effect work: each new grammar makes every brain more capable. The sovereignty guarantee is what makes operators trust the network in the first place. The open substrate is what keeps that trust honest — because an operator who can leave but chooses to stay is the only kind of operator worth having.

One brain. Every domain. Owned by the operator.
