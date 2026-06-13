---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SEMANTOS-SITES-1.0.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.715243+00:00
---

# Semantos Sites 1.0 — Operator Website Wizard

**Status:** design · parallel to brain W7.4–W7.9
**Reference implementations:**
- Consumer-facing operator site: `oddjobtodd.info` (Oddjobz / Sunshine Coast Handyman)
- Platform site: `semantos.me`

---

## What this is

A wizard that extracts a small business's identity (LBC, ICP, pricing) through an agent conversation, stores the output as versioned RELEVANT cells, and renders a live public website — with the intake chat widget pre-wired, BYOD domain, collaborative versioning for A/B testing, and a closed-loop analytics pipeline via Pask.

The website is not a separate product. It is a **rendering of the operator's cell store** through a typed ToFu/MoFu/BoFu template. When the operator updates their pricing in the Oddjobz app, the website updates. When enough analytics cells accumulate, the Pask kernel identifies which section variant converts — and the operator promotes it through the same D-DOG.1.0c mechanism used for any other cell-DAG promotion.

---

## Reference architecture

```
Operator onboarding wizard (Flutter, Oddjobz-flavoured)
        ↓ agent conversation (OpenRouter — BYOK)
Operator profile cells (strategy.lbc, strategy.icp, strategy.services, strategy.pricing)
  RELEVANT linearity — always accessible, versioned via cell-DAG
        ↓
Site renderer (brain HTTP surface, server-side HTML)
  Reads operator profile cells → renders typed ToFu/MoFu/BoFu sections
  Includes: intake chat widget (already built, D-O6a) with operator-specific config
  Includes: analytics snippet → LINEAR cells → Pask
        ↓
BYOD domain (W7.14 + W7.15 — already done)
  apex domain → site + intake widget
  brain.<domain> → WSS helm endpoint (existing)
```

```
Browser analytics event (pageview / chat_start / lead_captured / conversion)
        ↓ POST /api/v1/analytics — LINEAR cell
Brain receives → Pask kernel → entailments network
        ↓
A/B test policy cell: {split, variant_a_hash, variant_b_hash}
Winning variant → D-DOG.1.0c Layer 1 promotion → canonical cell updated
```

---

## Operator profile cell schema

All cells use the standard 1024-byte format. Cells live in the operator's cell store (op_pkh keyed). All are RELEVANT linearity — always accessible, versioned.

### `strategy.lbc`
Lean Business Canvas. One cell per operator, hash-chained on each wizard update.

```json
{
  "cell_type": "strategy.lbc",
  "linearity": "RELEVANT",
  "payload": {
    "problem":           "string  — the pain the business solves",
    "solution":          "string  — what they do about it",
    "uvp":               "string  — unique value proposition (hero headline source)",
    "customer_segments": ["string"],
    "channels":          ["string"],
    "revenue_streams":   ["string"],
    "key_metrics":       ["string"],
    "cost_structure":    "string  — internal only, not rendered on site"
  }
}
```

### `strategy.icp`
Ideal Customer Profile. Used for website copy tone + intake agent qualification.

```json
{
  "cell_type": "strategy.icp",
  "linearity": "RELEVANT",
  "payload": {
    "segment":       "homeowners | renters | landlords | smb | mixed",
    "geography":     "string  — suburb / region coverage",
    "pain_points":   ["string"],
    "objections":    ["string  — what they worry about before booking"],
    "trust_signals": ["string  — what builds credibility with this segment"],
    "tone":          "friendly | professional | expert | casual"
  }
}
```

### `strategy.services`
List of services offered. Source for the services grid and intake widget tags.

```json
{
  "cell_type": "strategy.services",
  "linearity": "RELEVANT",
  "payload": {
    "services": [
      {
        "slug":        "carpentry",
        "label":       "Carpentry",
        "icon":        "🔨",
        "description": "Decks, shelves, framing, cabinets, pergolas"
      }
    ]
  }
}
```

### `strategy.pricing`
Pricing schedule. Source for BoFu CTA and intake agent quote logic.

```json
{
  "cell_type": "strategy.pricing",
  "linearity": "RELEVANT",
  "payload": {
    "callout_fee":    { "amount": 120, "currency": "AUD", "label": "Service call" },
    "hourly_rate":    { "amount": 95,  "currency": "AUD", "label": "Per hour" },
    "quote_policy":   "free_onsite | paid_onsite | phone_only | chat_first",
    "minimum_charge": { "amount": 120, "currency": "AUD" },
    "emergency_rate": { "amount": 180, "currency": "AUD", "label": "After hours" }
  }
}
```

### `site.section.<slug>` (versioned, A/B-able)
Each rendered section is also a RELEVANT cell — this is what the cell-DAG versions.

```json
{
  "cell_type": "site.section.hero",
  "linearity": "RELEVANT",
  "payload": {
    "h1":          "string",
    "lede":        "string",
    "cta_label":   "string",
    "cta_href":    "string",
    "trust_items": ["string"]
  }
}
```

Section slugs: `hero`, `services`, `how_it_works`, `social_proof`, `pricing`, `footer`.

### `site.ab_policy.<section_slug>` (A/B test policy)
Policy cell declaring a live split test for a given section.

```json
{
  "cell_type": "site.ab_policy.hero",
  "linearity": "RELEVANT",
  "payload": {
    "test_id":       "uuid",
    "split_pct":     50,
    "variant_a":     "cell_hash_of_site.section.hero.variant_a",
    "variant_b":     "cell_hash_of_site.section.hero.variant_b",
    "started_at":    "iso8601",
    "ended_at":      null
  }
}
```

Promotion: set `ended_at`, promote winning variant hash as canonical `site.section.hero` — same D-DOG.1.0c mechanism.

### `analytics.event` (LINEAR — consumed, not duplicated)

```json
{
  "cell_type": "analytics.event",
  "linearity": "LINEAR",
  "payload": {
    "event":      "pageview | chat_start | lead_captured | booking_intent | conversion",
    "session_id": "uuid",
    "section":    "hero | services | pricing | ...",
    "variant":    "a | b | null",
    "referrer":   "string",
    "ts_ms":      1234567890
  }
}
```

---

## Site sections (ToFu / MoFu / BoFu)

### ToFu — awareness

**Hero** (rendered from `strategy.lbc.uvp` + `strategy.icp`)
- `h1`: derived from UVP + trade + location. E.g. "Get a plumbing quote in minutes"
- `lede`: problem statement from `strategy.lbc.problem` + geography
- Tag list: from `strategy.services[]`
- Trust items: from `strategy.icp.trust_signals`
- **Intake chat widget**: pre-wired, endpoint `/api/v1/chat`, greeting + placeholder generated from ICP

### MoFu — consideration

**Services grid** (from `strategy.services[]`)
Icon + label + description per service.

**How it works** (4-step, customized by `quote_policy`)
Step 4 varies: "Free on-site quote" vs "We'll send you a firm price" etc.

**Social proof** (optional — populated from future `strategy.testimonials` cell)
Not in v1.0; section slot reserved.

### BoFu — conversion

**Pricing** (from `strategy.pricing`)
Displayed if `quote_policy` is not `phone_only`. Shows callout fee + hourly + quote note.

**Footer** (from `operator` profile)
Business name, phone, ABN, copyright year.

---

## The wizard conversation

Agent uses OpenRouter (operator's own key — BYOK per Semantos commercial model). Oddjobz-flavoured system prompt surfaces the domain-specific questions.

**Phase 1 — Business identity** (fills `strategy.lbc` + `strategy.services`)
1. "What's your business name?"
2. "What trade(s) do you do? Pick all that apply or describe."
3. "Where do you work — what suburb or region?"
4. "What problem do your best customers have when they call you?"
5. "What do you do that other tradies don't?"

**Phase 2 — Customer profile** (fills `strategy.icp`)
1. "Who's your ideal customer — homeowners, renters, landlords, small business?"
2. "What do they worry about before they book a tradie?"
3. "What makes them trust you when they first hear about you?"

**Phase 3 — Pricing** (fills `strategy.pricing`)
1. "Do you charge a callout / service fee? How much?"
2. "What's your hourly rate?"
3. "Do you do free on-site quotes?"
4. "Do you take emergency / after-hours jobs? What's the rate?"

**Phase 4 — Contact + domain** (fills `operator` profile + triggers BYOD)
1. "What's your business phone number?"
2. "Do you have a domain name you want to use? (e.g. coastalplumbing.com.au)"

**Phase 5 — Review + publish**
Agent generates section drafts from the collected cells. Operator sees previews of each section. Approves or edits. Cells written to store. Site renderer active immediately at BYOD domain.

---

## Site renderer (brain HTTP surface)

The brain's HTTP handler for operator apex domains:

```
GET <apex_domain>/
  1. Resolve op_pkh from SNI map (W7.15 — already done)
  2. Fetch operator profile cells (strategy.lbc, strategy.icp, strategy.services, strategy.pricing)
  3. Check for site.ab_policy.* cells — if present, resolve variant by session cookie
  4. Render section cells → HTML using site template
  5. Inject analytics snippet (inline JS, no external dep)
  6. Return HTML

GET <apex_domain>/api/v1/chat
  → proxy to existing chat endpoint (D-O6a already handles)

POST <apex_domain>/api/v1/analytics
  → receive analytics event → write LINEAR analytics.event cell → Pask
```

Server-side render: clean HTML returned on first request. SEO works. No SPA.

The site template is a single parameterized HTML file (see `runtime/semantos-brain/src/site_template.html`). Section content is slot-filled from cell payloads. The intake widget JS/CSS are served from `/chat-widget/` as they are today.

---

## Analytics inline snippet

Injected into every rendered page. No external deps. Same-origin POST.

```html
<script>
(function(){
  const SESSION = (() => {
    try {
      const k = 'sm-session';
      return sessionStorage.getItem(k) || (() => {
        const v = crypto.randomUUID ? crypto.randomUUID() :
          ([...crypto.getRandomValues(new Uint8Array(16))].map(b=>b.toString(16).padStart(2,'0')).join(''));
        sessionStorage.setItem(k, v); return v;
      })();
    } catch(_) { return 'anon'; }
  })();
  function emit(event, extra) {
    fetch('/api/v1/analytics', {
      method: 'POST', keepalive: true,
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({event, session_id: SESSION,
        referrer: document.referrer, page: location.pathname,
        variant: document.documentElement.dataset.variant || null,
        ts_ms: Date.now(), ...extra})
    }).catch(()=>{});
  }
  emit('pageview');
  document.addEventListener('sm:chat_start',  () => emit('chat_start'));
  document.addEventListener('sm:lead',        () => emit('lead_captured'));
})();
</script>
```

The chat widget dispatches `sm:chat_start` on first user message and `sm:lead` on a completed intake. These events are already defined in D-O6a's event contract; the analytics snippet consumes them.

---

## BYOD flow (operator perspective)

1. Wizard phase 4: operator enters domain name.
2. Brain: `brain domain-allow <domain>` + `brain sni-map set <domain> <op_pkh>` (W7.14 + W7.15, already done).
3. Operator adds A record to their DNS: `<domain>` → brain IP.
4. First HTTPS request: Caddy on-demand TLS acquires cert from Let's Encrypt via the `ask` endpoint.
5. Site is live. No manual Caddyfile edits.

DNS change is the only step the operator does outside the wizard. The wizard UI shows:
```
"Point your domain at this IP address: 203.18.30.243
Add an A record for @ and www. This takes 5–60 minutes to propagate."
```

---

## What's already done

| Dependency | Status |
|---|---|
| BYOD domain + on-demand TLS | Done — W7.14 |
| SNI → op_pkh routing | Done — W7.15 |
| Collaborative versioning + L1 promotion | Done — D-DOG.1.0c |
| Cell-DAG graph materialisation | Done |
| Brain 100% HTTP surface | Done — PRs #411–#420 |
| Intake chat widget (D-O6a) | Done — oddjobtodd.info |
| Oddjobz 8-cell domain extension | Done |
| Pask learning kernel | Done |
| Reference site template | Done — semantos.me + oddjobtodd.info |
| Operator exit tarball | Done — W7.7 |

---

## What's net-new (parallel work, does not block on W7.4)

| Item | Description | Location |
|---|---|---|
| S1 | Operator profile cell schema (types + validation) | semantos-core / extensions |
| S2 | Site template HTML (parameterized from cells) | semantos-brain / site_template |
| S3 | Site renderer Zig module | semantos-brain / site_renderer.zig |
| S4 | Analytics cell handler (POST → LINEAR write → Pask) | semantos-brain / analytics_handler.zig |
| S5 | Wizard system prompt — Oddjobz flavour | semantos-core / wizard_prompts |
| S6 | Wizard agent conversation flow | Oddjobz Flutter app |
| S7 | A/B session resolution (cookie → variant) | site_renderer.zig |
| S8 | Operator profile Postgres migration | 020_operator_profile.sql |
| S9 | Dashboard: section editor + variant preview | Flutter / Oddjobz app |

**S1–S4 have no dependencies on W7.4.** They can start immediately.
**S5 has no dependencies.** Wizard system prompt is a text artifact.
**S6, S9** depend on W7.9 (provisioning endpoint, depends on W7.4).

---

## Commercial model

| Revenue | Mechanism |
|---|---|
| Platform ($500) | Wizard + site included. BYOD domain self-service. |
| Plexus Node (~$15-20/month) | "Always-on" site needs the node running; motivates upsell. |
| Extension marketplace | Domain-specific wizard packs (real estate, physio, accountant). |
| Analytics / Pask upsell | Richer learning = richer site intelligence. Same node revenue. |

The wizard is the most tangible early deliverable of the platform purchase — operator has a live site within 30 minutes of completing onboarding. That proof of value is the primary stickiness driver before first customer intake.

---

## Naming

- **Product**: Semantos Sites
- **Reference implementation**: Oddjobz Pages (or just "your website" in the Oddjobz onboarding flow — no need to brand it separately at the tradie level)
- **Wizard**: Business Identity Wizard (internal); "Set up your online presence" (consumer-facing)
- **Extension pack pattern**: `wizard.trades.oddjobz`, `wizard.realestate.*`, etc.

---

## Not in scope (v1.0)

- Drag-and-drop layout editor (not a website builder; the structure is fixed by the ToFu/MoFu/BoFu funnel)
- Blog / CMS arbitrary content (no free-form sections; everything is typed)
- Email capture / marketing automation (intake flows through messaging adapters; no separate email list)
- Multi-page sites (v1.0 is a single landing page per operator; sub-pages are v2)
- Social proof / testimonials section (cell type reserved; content collection is v2)
