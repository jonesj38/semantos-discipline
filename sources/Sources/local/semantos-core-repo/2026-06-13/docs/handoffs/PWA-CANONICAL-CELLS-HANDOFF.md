---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/handoffs/PWA-CANONICAL-CELLS-HANDOFF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.752684+00:00
---

# Oddjobz PWA — Canonical Cells Handoff

**Written:** 2026-05-24  
**Covers:** What the conversation architecture rollout delivered, what the operator PWA needs next, and the quote workflow end-to-end.

---

## 1. What was built (conversation architecture — COMPLETE)

All 9 conversation-architecture deliverables shipped on `main` as PRs #607–#615:

| PR | Deliverable ID | What it is |
|----|---------------|-----------|
| #607 | D-OJ-conv-turn-schema | Canonical `OddjobzConversationTurnPayload` type + `sem_objects` sink seam |
| #608 | D-OJ-conv-ai-participant | AI-authored turns get `participantRole:'ai'` + `outboundState:'proposed'` |
| #609 | D-OJ-conv-entity-anchoring | `entityRef:{kind,cellHash}` on every turn |
| #610 | D-OJ-conv-outbound-routing | Outbound state machine: drafted→proposed→approved→sent→delivered/failed |
| #611 | D-OJ-conv-propose-outbound | Brain endpoint `POST /api/v1/conversation/turn/propose` (operator/agent compose) |
| #612 | D-OJ-conv-approve | Brain endpoint `POST /api/v1/conversation/turn/:id/approve` (send via Twilio/SMTP) |
| #613 | D-OJ-conv-identity-merge | Brain endpoint `POST /api/v1/identity/merge` |
| #614 | D-OJ-conv-gmail-canonical-bridge | `mapMessagePatchToCanonical()` + `messages-backfill-script.ts` |
| #615 | D-OJ-conv-messages-backfill | Raw-SQL fix for prod schema incompatibility (added `vertical` + `type_hash`) |

**Backfill ran on rbs 2026-05-23:** 822 email turns inserted, 0 errors. Prod DB now has 825 `oddjobz.conversation.turn` rows.

---

## 2. The canonical data model

### 2a. Where it lives

```sql
-- Prod Postgres on rbs (accessible via DATABASE_URL in brain environment)
SELECT id, payload
FROM sem_objects
WHERE object_kind = 'oddjobz.conversation.turn'
ORDER BY (payload->>'timestamp')::bigint DESC;
```

Critical prod-schema constants (differ from the Drizzle ORM schema — do NOT use `createObject()` from `@semantos/semantic-objects`):

```typescript
const ODDJOBZ_VERTICAL = 'oddjobz';
const ODDJOBZ_TURN_OBJECT_KIND = 'oddjobz.conversation.turn';
const ODDJOBZ_TURN_TYPE_HASH = '3e98317d411eadb967a738007a4e5fe9b2e2d0b41670c0f21e81cc10d2fcda1d';
// sha256('oddjobz.conversation.turn')
// The prod DB also has: created_by text (not created_by_cert_id), vertical varchar(50) NOT NULL
```

### 2b. `OddjobzConversationTurnPayload` shape

Defined in:
`cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts`

```typescript
interface OddjobzConversationTurnPayload {
  turnId: string;              // e.g. "turn-in-abc123" or "turn-out-def456"
  conversationId: string;      // groups turns into a thread
  participantRole: 'external' | 'operator' | 'ai' | 'subcontractor';
  direction: 'inbound' | 'outbound';
  surface: 'email' | 'gmail' | 'sms' | 'meta-inbox' | 'widget';
  bodyText: string;            // the canonical message text
  timestamp: number;           // ms epoch
  correlationId: string;       // mirrors turnId; used for idempotency

  // Identity
  actorCertId?: string;        // operator/ai cert; absent for external
  identityHandle?: {           // L0/L1 for external parties
    kind: 'email' | 'phone' | 'cookie' | 'instagram' | 'facebook';
    value: string;
  };
  externalKind?: string;       // e.g. 'utility-provider', 'insurer'

  // Entity binding
  entityRef?: {
    kind: 'job' | 'site' | 'customer' | 'lead';
    cellHash: string;          // LMDB key of the entity cell
  };

  // Outbound-specific
  outboundState?: 'drafted' | 'proposed' | 'approved' | 'sent' | 'delivered' | 'failed' | 'rejected';
  recipientHandle?: { kind: string; value: string };
  includeCustomerLink?: boolean;
  quotedTurnId?: string;       // REPLIES_TO threading

  // Structured body parts (intake metadata, attachments, etc.)
  bodyParts?: OddjobzTurnBodyPart[];
}
```

### 2c. Querying turns by entity

```sql
-- All turns for a specific job (by cellHash)
SELECT id, payload
FROM sem_objects
WHERE object_kind = 'oddjobz.conversation.turn'
  AND payload->'entityRef'->>'cellHash' = '<job_cell_hash>'
ORDER BY (payload->>'timestamp')::bigint ASC;

-- Inbound turns only
  AND payload->>'direction' = 'inbound'

-- Turns for a conversation thread
  AND payload->>'conversationId' = '<conversationId>'

-- Undelivered outbound (operator inbox)
  AND payload->>'direction' = 'outbound'
  AND payload->>'outboundState' = 'proposed'
```

---

## 3. Brain endpoints live on rbs

Base URL: `https://oddjobtodd.info` (port 8080 proxied via Caddy)  
Auth: `Authorization: Bearer <token>` (all except the customer-facing `/c/` route)

| Method | Path | What it does |
|--------|------|-------------|
| `POST` | `/api/v1/repl` | Operator REPL — typed commands, see §5 |
| `POST` | `/api/v1/conversation/turn/propose` | Store a proposed outbound turn |
| `POST` | `/api/v1/conversation/turn/:id/approve` | Approve + send a proposed turn (Twilio/SMTP) |
| `POST` | `/api/v1/conversation/turn/:id/re-anchor` | Re-anchor a turn to a different entity |
| `POST` | `/api/v1/identity/merge` | Merge two participant identities |
| `GET`  | `/api/v1/c/:token` | Resolve customer link token → conversationId + title |
| `GET`  | `/api/v1/sem-objects?kind=oddjobz.conversation.turn` | Query sem_objects by kind (cell_query_handler) |

### 3a. Propose-turn wire format

```json
// POST /api/v1/conversation/turn/propose
{
  "conversationId": "conv-abc123",
  "surface": "sms",
  "bodyText": "Hi Sarah, your quote is ready...",
  "participantRole": "operator",
  "recipientHandle": { "kind": "phone", "value": "+61412345678" },
  "entityRef": { "kind": "job", "cellHash": "<job_cell_hash>" },
  "includeCustomerLink": true
}
// Response: { ok: true, turnId: "turn-out-...", state: "proposed" }
```

### 3b. Approve-turn wire format

```json
// POST /api/v1/conversation/turn/<turnId>/approve
{ "approved": true }
// Response: { ok: true, turnId, state: "sent" }
// Side-effect: Twilio SMS or SMTP email, customer_link sem_object created if includeCustomerLink
```

---

## 4. Current PWA state (the gap)

### 4a. What is deployed

`apps/oddjobtodd/` — a **visual design mock** (helm states, not a live data app). It has no brain connection; it renders static hardcoded data to demonstrate the UI concept. Deployed at `oddjobtodd.info` via Caddy serving the `dist/` folder.

### 4b. What has the right structure but wrong data model

`apps/loom-react/` — a more capable shell (Navigator, helm, Talk, REPL terminal) but:
- `canvas/ConversationPanel.tsx` — reads `sem_object_patches` (old patch log), NOT canonical `oddjobz.conversation.turn` sem_objects
- `canvas/ChatView.tsx` — same old patch model
- No oddjobz entity views (jobs list, job detail, customer detail, site detail)
- Talk/REPL panel (`helm/TerminalPanel.tsx`) can already POST `/api/v1/repl` — this is the working path today

### 4c. What doesn't exist yet

- **Conversation inbox** — a view of all `oddjobz.conversation.turn` rows grouped by `conversationId` or `entityRef`, with pending-outbound approval queue
- **Job detail with conversation history** — tap a job → see all turns associated with `entityRef.kind='job' AND entityRef.cellHash=<this job>`
- **Customer detail with conversation history** — same for `entityRef.kind='customer'`
- **Quote compose UI** — a view that shows seeded line items from conversation turns and lets the operator edit + submit
- **Quote workflow triggered by voice/REPL command** (see §6)

---

## 5. REPL command reference (what works today)

The REPL at `POST /api/v1/repl` body: `{ "cmd": "<line>" }` understands:

```
find jobs                       → list all jobs with state
find job <id>                   → job detail
add job <customer_name>         → create lead
quote job <id>                  → transition job → 'quoted', seeds quote from ROM estimate if any
schedule job <id> [<date>]      → transition → 'scheduled'
start job <id>                  → transition → 'in_progress'
complete job <id>               → transition → 'completed'
invoice job <id>                → create invoice from quote
mark job <id> paid              → transition invoice → 'paid'
close job <id>                  → transition → 'closed'

find quotes                     → list all draft/presented quotes
find quote <id>                 → quote detail
add quote job:<id> min:<n> max:<n>  → create quote for job

find customers                  → list customers
add customer <name>             → create customer

find visits                     → list visits
find invoices                   → list invoices
find intent-cells               → list submitted intent cells
```

The `quote job <id>` command fires the `quote` action → `intent_action_router.zig` → `jobs.transition(qualified→quoted OR visited→quoted)` → `quote_seed_router.zig` auto-creates a draft quote seeded from the accepted ROM estimate if one exists.

**What doesn't exist yet:** A REPL command that reads conversation turns from Postgres and extracts line items from them. That's the "quote from conversation" gap described in §6.

---

## 6. The quote workflow Todd wants

> "quote 500 for the roof job on hendry street — if we'd conversed multiple patches on the hendry st job pre-quote, it would extract line items from those convos"

### 6a. What needs building

A new brain bun script (or REPL extension) — call it `quote-from-conversation-script.ts` — that:

1. **Receives a REPL command** like `quote job <name_or_id> [--amount 500]`
2. **Resolves the entity** by name using the existing `intent_action_router.zig` heuristic (substring match on `customer_name` in LMDB jobs store). The LMDB `cellHash` is the key to query `sem_objects`.
3. **Fetches conversation turns** from Postgres:
   ```sql
   SELECT payload FROM sem_objects
   WHERE object_kind = 'oddjobz.conversation.turn'
     AND payload->'entityRef'->>'cellHash' = '<job_cellHash>'
   ORDER BY (payload->>'timestamp')::bigint ASC;
   ```
4. **Extracts line items** from the turn `bodyText` values. Because `semantos_no_ai_in_substrate`, this extraction must happen **at the operator's phone/edge** — the turns go up to the AI (Claude) as context, and the AI returns structured line items. The brain script is NOT the right place for LLM calls; the right shape is:
   - Brain script returns turns JSON to the REPL caller
   - The PWA (or a dedicated voice-extract-style bun script at the edge) calls Claude with those turns as context
   - Claude returns: `{ lineItems: [{description, quantity, unit, unitCost}], totalEstimate }`
5. **Generates a markdown quote** from the line items + override amount:
   ```markdown
   ## Quote — Roof repair, 42 Hendry Street
   
   | Item | Qty | Unit | Cost |
   |------|-----|------|------|
   | Roof tiles (replacement) | 24 | ea | $18.50 |
   | Ridge capping | 3 | m | $22.00 |
   | Labour — roof access + repair | 4 | hr | $95.00 |
   
   **Subtotal:** $482.00  
   **Total (quoted):** $500.00
   
   Valid 30 days. Payment on completion.
   ```
6. **Creates a quote sem_object** (via the existing `quotes.create` REPL path, or a direct DB insert) and **transitions the job** to `quoted` state via `jobs.transition`.

### 6b. Architecture constraints

- The brain script itself MUST NOT call Claude/LLM (see `semantos_no_ai_in_substrate` memory).
- The extraction step belongs either:
  - In a **voice-extract-style bun edge script** run from the operator phone/PWA, OR
  - In the PWA's AI layer (Talk → REPL → AI → returns structured data → PWA calls brain to persist)
- The clean seam: the brain provides a `GET /api/v1/conversation/turns?entityRef=<cellHash>` endpoint (or REPL `find turns job <id>`) that returns the raw turns. The AI/edge does the extraction. The result comes back to the brain as a structured `add quote` call.

### 6c. Suggested REPL extension (new)

Add to `repl.zig`:
```
find turns job <id_or_name>    → query sem_objects WHERE entityRef.cellHash=<job> → return JSON turns array
```
This gives the PWA Talk panel the raw material for the AI extraction step. The Talk panel already has a chat UI; the AI can read the turns, extract line items, and the operator confirms before `add quote` is issued.

### 6d. Existing plumbing to reuse

- `quote_seed_router.zig` — already creates a draft quote from an estimate when `qualified→quoted`. The same `quotes.create` dispatcher verb accepts `cost_min`, `cost_max`, `notes`.
- `quote_fsm.zig` — state machine: draft→presented→accepted/rejected/expired.
- `quotes_store_lmdb.zig` — persists the quote cell.
- The quote cell hash from `quotes.create` response can be included in the markdown quote header for traceability.

---

## 7. PWA migration — file-by-file guide

The target: every entity view (job, customer, site) surfaces its canonical conversation history from `oddjobz.conversation.turn` sem_objects.

### 7a. New brain endpoint needed

Add `GET /api/v1/sem-objects` with query param filtering if not already fully wired, OR add a dedicated:

```
GET /api/v1/conversation/turns?entityRef=<cellHash>&limit=50&before=<timestamp>
```

Wire it in `reactor.zig` (pattern: add a new path match block → `reactorHandleConversationTurns` → spawns a bun script that queries Postgres → returns JSON array of payloads).

The bun script (`conversation-turns-query-script.ts`) is trivial:
```typescript
// stdin: { entityRef?: string, conversationId?: string, limit?: number, before?: number }
// stdout: { ok: true, turns: OddjobzConversationTurnPayload[] }
const result = await db.execute(sql`
  SELECT payload FROM sem_objects
  WHERE object_kind = 'oddjobz.conversation.turn'
    AND (${entityRef} IS NULL OR payload->'entityRef'->>'cellHash' = ${entityRef})
    AND (${before} IS NULL OR (payload->>'timestamp')::bigint < ${before})
  ORDER BY (payload->>'timestamp')::bigint DESC
  LIMIT ${limit ?? 50}
`);
// ... return rows mapped to OddjobzConversationTurnPayload[]
```

### 7b. `canvas/ConversationPanel.tsx` (534 lines)

Current: reads `sem_object_patches` via `loomStateAtom`.  
Target: call `GET /api/v1/conversation/turns?entityRef=<cellHash>` → render turns.

Replace the patch-fetching hook with:
```typescript
function useConversationTurns(entityRef: string | undefined) {
  const [turns, setTurns] = useState<OddjobzConversationTurnPayload[]>([]);
  useEffect(() => {
    if (!entityRef) return;
    fetch(`/api/v1/conversation/turns?entityRef=${entityRef}`, {
      headers: { Authorization: `Bearer ${bearerToken}` },
    })
      .then(r => r.json())
      .then(({ turns }) => setTurns(turns));
  }, [entityRef]);
  return turns;
}
```

Turn rendering: use `turn.direction`, `turn.participantRole`, `turn.bodyText`, `turn.surface`, `turn.outboundState` for bubble style + status badges.

### 7c. New: `JobDetailView.tsx`

A new view (add to the nav alongside jobs list) that shows:
1. Job metadata (customer name, state, cellHash)
2. `<ConversationPanel entityRef={job.cellHash} />` — the full email/SMS/widget thread
3. A "Quote from conversation" button that:
   - POSTs the turns to Talk/AI for extraction
   - Shows a draft quote table the operator can edit
   - On confirm: `add quote job:<id> min:<n> max:<n>` via REPL + transition job to `quoted`

### 7d. Job list (currently static in `apps/oddjobtodd`)

The `apps/oddjobtodd/src/components/HelmScreens.tsx` `S2_Activation` component renders hardcoded jobs. Replace with:
```typescript
function useJobs() {
  const [jobs, setJobs] = useState([]);
  useEffect(() => {
    fetch('/api/v1/repl', {
      method: 'POST',
      body: JSON.stringify({ cmd: 'find jobs' }),
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
    }).then(r => r.json()).then(d => setJobs(JSON.parse(d.output)));
  }, []);
  return jobs;
}
```
The REPL `find jobs` command returns JSON: `[{ id, customer_name, state, cell_hash, updated_at }]`.

### 7e. Pending outbound inbox (operator approve queue)

```sql
-- These are turns waiting for operator to approve + send
SELECT id, payload
FROM sem_objects
WHERE object_kind = 'oddjobz.conversation.turn'
  AND payload->>'direction' = 'outbound'
  AND payload->>'outboundState' = 'proposed'
ORDER BY (payload->>'timestamp')::bigint DESC;
```

Render each as an approval card: show `bodyText`, recipient, entity. Approve button → `POST /api/v1/conversation/turn/:id/approve`.

---

## 8. Deploy notes (critical)

### 8a. Brain rebuild on rbs

The rbs VM CPU misdetects as `athlon-xp` (unknown to LLVM 19). **Always use:**
```bash
ssh rbs
cd /opt/semantos-core/runtime/semantos-brain
git pull
zig build -Dcpu=baseline   # Debug mode — NOT -Doptimize=ReleaseFast
```

Zig's global cache (`~/.cache/zig`) can serve stale artifacts. After a significant source change, verify the built binary contains the expected strings before deploying:
```bash
strings zig-out/bin/brain | grep 'Propose turn'
```

Deploy:
```bash
sudo systemctl stop semantos-shell
sudo install -m 0755 zig-out/bin/brain /opt/semantos/brain
sudo systemctl start semantos-shell
curl -s http://localhost:8080/api/v1/info | jq .version
```

### 8b. Systemd drop-in (authoritative ExecStart)

`/etc/systemd/system/semantos-shell.service.d/zz-oddjobz-scripts.conf`

All 5 oddjobz conversation flags are in this drop-in. When adding new script flags, extend this file. Run `sudo systemctl daemon-reload` after editing.

### 8c. PWA rebuild + deploy

```bash
# In apps/oddjobtodd (or whichever app becomes the real operator PWA)
pnpm build
# Caddy serves from the dist/ directory configured in Caddyfile on rbs
```

---

## 9. The full "quote 500 for the hendry st roof job" sequence

When this is fully wired, here is what happens:

1. **Operator says** (via voice or REPL Talk panel): `"quote 500 for the roof job on hendry st"`

2. **AI (edge/phone)** parses intent:
   ```json
   { "action": "quote", "entity": "job", "searchTerm": "hendry st", "amount": 500 }
   ```

3. **PWA calls brain REPL**: `find job hendry st` → brain returns job with `cellHash`

4. **PWA calls brain** (new endpoint): `GET /api/v1/conversation/turns?entityRef=<job_cellHash>` → returns all conversation turns for that job

5. **AI (edge/phone) reads turns** — looks for prior messages mentioning materials, measurements, scope:
   - "Need 24 roof tiles replaced on the south face, ridge capping needs doing too, about 3 metres"
   - "Also noted the gutter brackets need replacing — maybe 6 of them"
   → Returns structured line items

6. **PWA renders quote draft** for operator confirmation:
   ```
   Roof tiles × 24   $18.50ea  = $444.00
   Ridge capping 3m  $22.00/m  = $66.00
   Gutter brackets×6 $8.00ea   = $48.00
   [Labour]          override  = ?
   ────────────────────────────────────
   Override total: $500.00  ← operator-confirmed
   ```

7. **Operator taps confirm** → PWA issues:
   - `add quote job:<id> min:500 max:500` via REPL
   - `quote job <id>` via REPL → transitions job to `quoted` state
   - `quote_seed_router.zig` auto-wires the draft quote cell

8. **PWA renders** the markdown quote document with line items + total = $500

9. **Job state flips to `quoted`** — visible in the job list

---

## 10. What's blocked / deferred

| Item | Blocker |
|------|---------|
| Meta outbound (§13.5) | Todd's Meta Business account unrestricted |
| Conversation turns query endpoint | New bun script + reactor wiring (small, no dependency) |
| Quote-from-conversation AI extraction | Needs conversation turns endpoint first, then edge AI integration |
| PWA job detail view with conversation history | Needs conversation turns endpoint |
| Operator approve-queue inbox | Needs a front-end; brain side already works |

---

## 11. Quick-start for a fresh session

```bash
# What's on prod right now
ssh rbs
psql $DATABASE_URL -c "SELECT count(*), payload->>'surface', payload->>'direction', payload->>'participantRole' FROM sem_objects WHERE object_kind='oddjobz.conversation.turn' GROUP BY 2,3,4 ORDER BY 1 DESC;"

# Test the endpoints
curl -s -X POST https://oddjobtodd.info/api/v1/repl \
  -H "Authorization: Bearer $(cat ~/.semantos/rbs-bearer)" \
  -H "Content-Type: application/json" \
  -d '{"cmd":"find jobs"}' | jq .

# Query a job's conversation turns (manual until the endpoint exists)
psql $DATABASE_URL -c "SELECT payload->>'turnId', payload->>'direction', payload->>'bodyText' FROM sem_objects WHERE object_kind='oddjobz.conversation.turn' AND payload->'entityRef'->>'kind'='job' LIMIT 5;"
```

Key files to read first:
- `cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts` — canonical types
- `cartridges/oddjobz/brain/src/conversation/propose-turn-script.ts` — pattern for any new bun script
- `runtime/semantos-brain/src/site_server/reactor.zig` — how to add a new endpoint (lines 569–637 show the pattern for conversation endpoints)
- `runtime/semantos-brain/src/repl.zig` — how to add REPL commands (lines 335–382 show the pattern)
- `cartridges/oddjobz/brain/zig/src/quote_seed_router.zig` — the existing quote seeding from ROM estimates
