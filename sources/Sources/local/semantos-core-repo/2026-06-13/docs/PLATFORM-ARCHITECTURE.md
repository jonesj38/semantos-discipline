---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PLATFORM-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.327640+00:00
---

# Semantos Platform Architecture — Three Verticals, One Kernel

## The three products

This isn't one product with three features. It's three standalone products that interoperate through shared semantic objects.

### Product 1: OddJobTodd (trades vertical)
*For sole-operator tradies and small crews.*

What it does today: conversational job intake, auto-ROM pricing, effort band inference, customer scoring, quote worthiness, admin dashboard, PDF import from agents. Runs on Vercel + Postgres.

Multi-tenant version: each tradie gets their own config (pricing policy, service area, trade categories, chat personality). Same platform, different settings. Tenant #1 is Todd.

### Product 2: Property management suite (property vertical)
*For REAs, property managers, strata managers.*

Standalone product. Works without a single tradie connected. Manages the full property lifecycle:

- **Properties** — address, title reference, zoning, insurance, compliance status
- **Leases** — tenant, term, rent, bond, break clauses, renewal dates
- **Tenants** — contact, history, payment record, references
- **Inspections** — routine, entry/exit, condition reports with photos
- **Maintenance requests** — tenant submits, PM triages, assigns to tradie OR handles internally
- **Compliance** — smoke alarms, electrical safety, pool fencing, building certs, insurance expiry
- **Documents** — lease agreements, condition reports, invoices, certificates, photos
- **Owners** — the landlord(s), their preferences, reporting

The conversational interface works differently here. A tenant messages about a dripping tap. The system creates a maintenance request, classifies urgency, checks if it's the landlord's responsibility or tenant's, checks the property's preferred tradie list, and either auto-dispatches or queues for PM approval.

### Product 3: The marketplace / sync layer
*The interop between verticals.*

Not a separate app — it's the protocol layer that connects products 1 and 2. When a PM dispatches a maintenance job to a tradie, a semantic object crosses the vertical boundary. The PM's maintenance request becomes the tradie's job lead. The tradie works it, the PM sees progress, the landlord gets the invoice.

This is where the semantos kernel earns its keep. Without it, you're building point-to-point integrations. With it, any vertical can publish objects that any other vertical can subscribe to, with facet provenance controlling who sees what.

---

## Property management vertical — object types

Following the same pattern as `trades-services.json`:

```
Property (RELEVANT — always accessible, shared across facets)
  - address, suburb, postcode, state
  - titleReference, lotPlan
  - propertyType: house | unit | townhouse | land | commercial
  - bedrooms, bathrooms, parking
  - zoning, landArea, buildArea
  - yearBuilt
  - insuranceProvider, insurancePolicyNo, insuranceExpiry
  - status: active | archived | under_management | pending_settlement
  - ownerIds[] — links to Owner objects
  - managerId — link to the PM user
  - preferredTradies: { categoryPath → tradieId }

Lease (LINEAR — exactly one active lease per property at a time)
  - propertyId
  - tenantIds[]
  - startDate, endDate, term
  - rentAmount, rentFrequency: weekly | fortnightly | monthly
  - bondAmount, bondLodgementRef
  - breakClause: boolean, breakNoticePeriod
  - renewalDate, renewalStatus: pending | renewed | expired | terminated
  - status: draft | active | expiring | expired | terminated | break_notice
  - specialConditions

Tenant (RELEVANT — referenced by leases, maintenance, inspections)
  - name, phone, email
  - emergencyContact
  - idVerified: boolean
  - paymentHistory: good | late_occasional | late_frequent | arrears
  - previousAddresses[]
  - pets: boolean, petDetails
  - status: prospective | active | vacating | former

Owner (RELEVANT — the landlord)
  - name, phone, email
  - entityType: individual | company | trust | smsf
  - abn, entityName
  - bankDetails (AFFINE — encrypted, PM-only)
  - communicationPreference: email | sms | phone
  - maintenanceApprovalThreshold: number (auto-approve below this $)
  - status: active | archived

MaintenanceRequest (AFFINE → RELEVANT on dispatch)
  - propertyId, leaseId, tenantId
  - description, photos[]
  - categoryPath (same taxonomy as trades: services.trades.plumbing etc.)
  - urgency: emergency | urgent | routine | cosmetic
  - reportedBy: tenant | inspection | owner | pm
  - responsibleParty: landlord | tenant | strata | insurance
  - estimatedCost
  - approvalStatus: pending_pm | pending_owner | approved | declined
  - assignedTradieId (→ links to OJT)
  - status: new | triaged | awaiting_approval | dispatched |
            in_progress | completed | invoiced | closed
  - tradieJobId (→ the semantic object ID in the tradie's vertical)
  - completionPhotos[], completionNotes
  - invoiceAmount, invoiceRef

Inspection (AFFINE — draft until published to owner)
  - propertyId, leaseId
  - inspectionType: routine | entry | exit | pre_sale | compliance
  - scheduledDate, completedDate
  - inspector: pm | third_party
  - rooms[]: { name, condition, notes, photos[] }
  - overallCondition: excellent | good | fair | poor
  - maintenanceItems[]: { description, urgency, photo }
  - status: scheduled | in_progress | draft_report | published | acknowledged

ComplianceItem (RELEVANT — always visible, alerts on expiry)
  - propertyId
  - complianceType: smoke_alarm | electrical_safety | pool_fence |
                    gas_certificate | building_cert | insurance |
                    pest_inspection | asbestos_register
  - lastChecked, expiryDate
  - certificateRef, attachmentId
  - status: current | expiring_soon | expired | not_applicable
  - renewalAction: auto_schedule | notify_owner | manual

Document (RELEVANT or AFFINE depending on type)
  - parentId, parentType (links to any object above)
  - documentType: lease | condition_report | invoice | certificate |
                  photo | correspondence | notice
  - filename, mimeType, storageRef (UHRP or blob URL)
  - uploadedBy (facet provenance)
  - status: draft | current | superseded | archived
```

### State machines

**MaintenanceRequest FSM** (the critical one — this is where verticals cross):
```
new → triaged → awaiting_approval → approved → dispatched →
  in_progress → completed → invoiced → closed

new → triaged → declined (owner says no)
new → triaged → tenant_responsibility (not landlord's problem)
dispatched → cancelled (tradie can't do it, reassign)
```

**Lease FSM**:
```
draft → active → expiring → renewed (new lease created)
active → break_notice → terminated
active → expiring → expired
```

**Inspection FSM**:
```
scheduled → in_progress → draft_report → published → acknowledged
```

**ComplianceItem** — no FSM, just date-based alerts.

---

## How verticals connect — the dispatch model

When a PM dispatches a maintenance request to a tradie, this is what happens at the semantic layer:

### PM side (property vertical):

1. Tenant messages: "tap's dripping in the kitchen"
2. System creates `MaintenanceRequest` (AFFINE — internal to PM)
3. PM reviews, sets `responsibleParty: landlord`
4. If `estimatedCost < owner.maintenanceApprovalThreshold`: auto-approve
5. Otherwise: notify owner, wait for approval
6. On approval: `status → dispatched`, `assignedTradieId` set

### Cross-vertical dispatch:

7. System creates a **dispatch envelope** — a RELEVANT semantic object visible to both verticals
8. The envelope contains: property address, description, photos, urgency, category, tenant contact (if tenant-present access needed), PM contact
9. It does NOT contain: lease details, rent amount, owner financials, tenant payment history — those stay AFFINE on the PM side

### Tradie side (trades vertical):

10. The dispatch envelope arrives as a new Job lead in OJT
11. OJT's chat pipeline picks it up — pre-populated with the PM's description and photos
12. Auto-ROM fires (if enough sizing info), or tradie chats to clarify
13. Tradie works the job, adds photos, completes
14. Completion + invoice published back (RELEVANT patches on the envelope)

### PM side again:

15. PM sees: job completed, photos, invoice amount
16. PM creates invoice to owner, attaches tradie's invoice
17. MaintenanceRequest → `invoiced` → `closed`

### What the owner sees:

18. Notification: "Maintenance completed at [property]. Tap replaced. $280 labour + parts."
19. Invoice attached. Approval if above threshold.

### What the tenant sees:

20. "Your maintenance request has been sorted. The plumber came on Thursday."

---

## The key insight: dispatch envelope = semantic object with faceted visibility

The dispatch envelope is not a copy of the data. It's a single semantic object that both verticals reference. Patches from either side are visible to the other (if RELEVANT) or private (if AFFINE).

```
Dispatch Envelope (semantic object)
│
├── PM facet patches (RELEVANT):
│   - property address, description, photos, urgency
│   - PM contact, tenant contact (for access)
│   - approval status
│
├── PM facet patches (AFFINE — PM-only):
│   - owner details, lease info, cost expectations
│   - internal PM notes ("this tenant complains a lot")
│
├── Tradie facet patches (RELEVANT):
│   - ROM estimate, quote, schedule
│   - completion photos, completion notes
│   - invoice amount
│
├── Tradie facet patches (AFFINE — tradie-only):
│   - internal cost calculations, supplier quotes
│   - margin notes, material markup
│   - "this place is a shithole" (private ramblings)
│
├── Tenant facet patches (RELEVANT — read-only):
│   - status updates only
│   - "your request is being handled"
│
└── Owner facet patches (RELEVANT — approval only):
    - approval/rejection of cost
    - "go ahead" / "get a second quote"
```

Each party sees exactly what they should. The append-only patch log with facet provenance means you can always audit who said what and when. Linear types enforce the boundaries — AFFINE patches literally cannot be decrypted by the wrong facet.

---

## What's already built — channel and policy infrastructure

OJT's semantos kernel already has the multi-party channel isolation model implemented in `channelService.ts` and `policyEvaluator.ts`. This isn't a design sketch — it's shipping code backed by Postgres tables.

### channelService.ts — what it provides

| Primitive | What it does | Maps to dispatch envelope concept |
|---|---|---|
| `participants` table | Identity tracking per object — customer, admin, operator, external, ai | Facet identity on the envelope |
| `participant_pair` channels | Isolated 1:1 conversations on the same object | Owner↔REA, Tradie↔REA, Tradie↔self (private notes) |
| `group` channels | Multi-party conversations with shared visibility | PM team discussion on a maintenance request |
| `system` channels | Automated notifications, status updates | Tenant-facing "your request is being handled" |
| `channelPolicies` | Per-participant policy assignment with field overrides | AFFINE vs RELEVANT boundary per facet |
| `addParticipantWithChannel()` | Atomic join — creates participant + AI channel in one op | New facet joins the envelope |
| `objectEdges` for channels | Graph relationship between channel and parent object | Envelope references from both verticals |

### policyEvaluator.ts — what it provides

| Primitive | What it does | Maps to dispatch envelope concept |
|---|---|---|
| `FieldVisibility` (visible/hidden/redacted_value/approval_required) | Per-field visibility control per role | AFFINE patches: hidden from wrong facet; RELEVANT patches: visible to all |
| `filterState()` | Strips hidden fields, redacts redacted fields | Facet-filtered view of the envelope |
| `filterStateForAi()` | Builds AI-scoped context per channel policy | Per-channel AI personality — PM's AI vs tradie's AI see different things |
| `checkContributionRight()` | Action gating per role (read_only/contribute/approve) | Who can patch the envelope |
| `selectionGates` | Gate access: participate/observe/blocked | Owner can approve cost but can't modify job details |
| `OverrideHierarchy` with `canOverride`/`requiresApproval` | Role-based escalation | PM overrides tradie schedule; owner approval required above threshold |

### What this means for Phase 4

The channel model doesn't need to be built — it needs to be **promoted to work across vertical boundaries**. The remaining new work is:

1. **Cross-vertical identity linking** — a MaintenanceRequest and a Job reference the same dispatch envelope via `objectEdges`, but today both objects live in the same Postgres schema. Cross-vertical means they might live in different operator databases, and the envelope object bridges them.

2. **Dispatch envelope object type** — a new semantic object type that carries the RELEVANT subset and links to both vertical-specific objects. The channel/policy primitives already handle multi-party visibility on this object.

3. **Cross-vertical API surface** — the API that lets PM's product create a dispatch that materialises as a Job lead in OJT. This is the "wire" between verticals; the policy enforcement at each end already works.

4. **Facet provenance on the patch log** — today, patches record who made them within a single vertical. For the envelope, patches need to record which vertical's identity facet authored them, for audit and dispute resolution.

Everything else — channel creation, participant management, policy evaluation, field filtering, AI context scoping, override hierarchy — is already implemented and tested in OJT.

---

## Vercel + sync: the pragmatic approach

Vercel can't do UDP multicast. Here's what actually works:

### V1: Direct API sync (ship this first)

```
PM Product (Vercel)  ←→  Shared Postgres  ←→  Tradie Product (Vercel)
```

Both products share a database (or use cross-database API calls). When PM dispatches:
1. PM writes MaintenanceRequest with `status: dispatched`
2. A Postgres trigger or webhook fires
3. OJT's API receives the dispatch, creates a Job lead
4. Status updates flow back the same way

This is boring and it works. Facet provenance is enforced at the application layer — the API checks which facet is writing and applies visibility rules before returning data.

### V2: Supabase Realtime

Replace the webhook with Supabase Realtime subscriptions. PM publishes, tradie subscribes. Real-time push, still serverless-compatible.

### V3: Overlay network (the endgame)

When you have 50 REAs and 200 tradies and the central database is a bottleneck:
- Each party runs a light relay (Fly.io, $5/month) that bridges their Vercel app to the BSV overlay
- Dispatch envelopes are cell-tokens published to `tm_semantos_objects`
- Shard multicast delivers them to subscribed tradies
- No central server — the overlay IS the marketplace

Phase 25D's infrastructure handles this. The `BsvOverlayAdapter` already implements `StorageAdapter`, so from the app's perspective, switching from Postgres to overlay is a config change, not a rewrite.

---

## Multi-product, multi-tenant architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Clients                                   │
│                                                                 │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐ │
│  │ Tradie App │  │ PM Portal  │  │ Tenant App │  │ Owner    │ │
│  │ (Flutter)  │  │ (Web/Fltr) │  │ (Flutter)  │  │ Portal   │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └────┬─────┘ │
└────────┼───────────────┼───────────────┼───────────────┼────────┘
         │               │               │               │
         └───────┬───────┴───────┬───────┴───────┬───────┘
                 │               │               │
┌────────────────┴───────────────┴───────────────┴────────────────┐
│                      API Gateway (Vercel)                        │
│                                                                 │
│  tenant_id + vertical routing                                    │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │ Trades Vertical  │  │ Property Vert.  │  │ Dispatch/Sync  │  │
│  │ (OJT pipeline)  │  │ (PM pipeline)   │  │ (cross-vert)   │  │
│  │                 │  │                 │  │                │  │
│  │ - Chat/extract  │  │ - Maint intake  │  │ - Envelope     │  │
│  │ - ROM/estimate  │  │ - Lease mgmt    │  │   creation     │  │
│  │ - Scoring       │  │ - Inspections   │  │ - Facet        │  │
│  │ - Job FSM       │  │ - Compliance    │  │   filtering    │  │
│  │ - Tradie config │  │ - PM config     │  │ - Status sync  │  │
│  └────────┬────────┘  └────────┬────────┘  └───────┬────────┘  │
│           │                    │                    │           │
│  ┌────────┴────────────────────┴────────────────────┴────────┐  │
│  │                   Semantos Kernel                         │  │
│  │                                                           │  │
│  │  Semantic objects · Facet provenance · Linear types        │  │
│  │  Policy engine · Vertical configs · Taxonomy              │  │
│  │  Append-only patch log · Capability tokens                │  │
│  └────────────────────────────┬──────────────────────────────┘  │
└───────────────────────────────┼─────────────────────────────────┘
                                │
┌───────────────────────────────┼─────────────────────────────────┐
│                         Storage                                  │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │ Postgres     │  │ Blob storage │  │ BSV Overlay        │    │
│  │ (Supabase)   │  │ (R2/Vercel)  │  │ (V3 — optional)    │    │
│  │ per-tenant   │  │ photos/PDFs  │  │ cell-tokens        │    │
│  │ RLS          │  │ UHRP refs    │  │ shard multicast    │    │
│  └──────────────┘  └──────────────┘  └────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Tenant model

Every row has `tenant_id`. But "tenant" here means platform tenant (the business using the product), not rental tenant. To avoid confusion:

- **Operator** = the business (a tradie, a PM agency, a strata company)
- **Rental tenant** = the person living in the property (only in property vertical)

Each operator gets:
- Their own vertical config (which object types, which policies, which taxonomy nodes)
- Their own pricing/scoring policies
- Their own service area / suburb groups
- Their own branding / chat personality
- Their own user accounts (PMs, inspectors, admin)

An operator can be on multiple verticals. A PM agency that also does handyman work internally would have both the property and trades verticals active.

### Shared taxonomy

The taxonomy is shared across verticals — `services.trades.plumbing` means the same thing whether the PM or the tradie uses it. This is what makes dispatch work. When the PM creates a maintenance request with `categoryPath: services.trades.plumbing`, OJT knows exactly what kind of job it is.

---

## What to build, in what order

### Phase 1: Ship multi-tenant OJT (you are here → 4-6 weeks)
- Add operator_id to OJT schema
- Per-operator config loading
- Your instance = operator #1
- Onboarding flow for new tradies

### Phase 2: Flutter tradie app (6-8 weeks)
- Mobile app for tradies calling OJT API
- Offline sync, camera, push notifications
- Web admin stays

### Phase 3: Property management MVP (8-12 weeks)
- New vertical config: property-management.json
- Core objects: Property, Lease, Tenant, Owner, MaintenanceRequest
- PM web portal (or Flutter)
- Maintenance request intake (tenant messages or PM creates)
- Compliance tracking (date-based alerts)
- No tradie integration yet — PM handles maintenance manually or notes a tradie's name

### Phase 4: Cross-vertical dispatch (2-3 weeks)

Channel isolation, policy evaluation, field filtering, and AI context scoping are already built (see "What's already built" section above). Remaining work:

- Dispatch envelope semantic object type definition
- Cross-vertical identity linking (MaintenanceRequest ↔ envelope ↔ Job via objectEdges)
- Cross-vertical API: PM dispatches maintenance → materialises as Job lead in OJT
- Facet provenance on patch log (which vertical authored each patch)
- Status sync back (completed, invoiced) via envelope's RELEVANT patches

### Phase 5: Overlay network (when scale demands it)
- Relay services bridging Vercel to BSV overlay
- Cell-token publication for dispatch envelopes
- Shard multicast for delivery
- Fully decentralised — no central marketplace server

### Phase 6: Inspections + compliance (4-6 weeks)
- Inspection workflow with photo capture
- Condition reports generated as PDFs
- Compliance calendar with auto-alerts
- Maintenance items from inspections flow into dispatch

### Phase 7: Owner portal (2-4 weeks)
- Owners see their properties, approve maintenance, view statements
- Read-only facet with approval capability on MaintenanceRequest
