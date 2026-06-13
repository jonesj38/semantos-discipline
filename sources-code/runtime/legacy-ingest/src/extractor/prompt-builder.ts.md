---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/prompt-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.159616+00:00
---

# runtime/legacy-ingest/src/extractor/prompt-builder.ts

```ts
/**
 * CC6.3b — Prompt builder for the LLM extraction template.
 *
 * Replaces the static `PROMPT_TEMPLATE` constant inside `email.ts` with
 * a function that composes the agency-specific zones from
 * `AdapterConfigMetadata`. The bulk of the prompt (schema, generic
 * instruction, phase routing) is a static raw template with placeholder
 * tokens; the placeholders get filled by helpers that consult the
 * config.
 *
 * Five zones are config-driven (CC6.3b acceptance: a fresh
 * adapter-config produces a prompt that names ONLY its declared
 * agencies):
 *
 *   {{BILLING_RULES_SECTION}}   — the per-agency billing rules block
 *                                 (previously email.ts:523–535).
 *   {{POC_HEURISTICS}}          — per-agency point-of-contact heuristics
 *                                 (previously email.ts:370–377).
 *   {{MAINTENANCE_AGENCIES}}    — agencies mentioned in the
 *                                 maintenance_order classification
 *                                 (previously email.ts:298–301).
 *   {{DISPATCHER_AGENCIES}}     — agencies mentioned in the POC
 *                                 dispatcher example list
 *                                 (previously email.ts:360).
 *   {{WORKED_EXAMPLE_AGENCIES}} — the parenthetical agency list before
 *                                 the worked example block
 *                                 (previously email.ts:399).
 *
 * One zone is intentionally NOT parameterized (a deliberate residual
 * coupling, documented):
 *
 *   The worked-example BLOCK itself (Clever Property canonical PDF
 *   text + expected JSON output, ~100 lines around email.ts:404–505)
 *   stays verbatim. The example is OJT-specific TRAINING DATA that
 *   teaches the LLM the STRUCTURE of a property-management PDF — it
 *   doesn't make claims about the LLM's recognition set, so a fresh
 *   config without Clever Property still benefits from this example
 *   structurally. If a future operator wants their own worked example,
 *   CC6.3c (or a follow-up) could add `worked_examples?` to
 *   `AdapterConfigMetadata`. For CC6.3b's scope this stays.
 *
 * See `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` v0.6 §6 row CC6.3b.
 */

import type { AdapterConfigMetadata, BillingRule } from '../adapter-config/types';

/**
 * Format an `AgencyName[]` as an inline English list:
 *
 *   []                              → ""
 *   ["X"]                           → "X"
 *   ["X", "Y"]                      → "X or Y"
 *   ["X", "Y", "Z"]                 → "X, Y, or Z"
 *   ["X", "Y", "Z", "W"]            → "X, Y, Z, or W"
 *
 * Empty array returns the empty string so callers can skip the
 * surrounding parenthetical or sentence entirely.
 */
export function formatAgencyList(names: readonly string[]): string {
  if (names.length === 0) return '';
  if (names.length === 1) return names[0];
  if (names.length === 2) return `${names[0]} or ${names[1]}`;
  return `${names.slice(0, -1).join(', ')}, or ${names[names.length - 1]}`;
}

/**
 * Synthesise a minimal rule-section entry when a `BillingRule` has no
 * `prompt_fragments.rules_section_text`. Captures the same semantics
 * the runtime uses (`outcome.kind`) so the LLM sees rule shape even
 * for a config that didn't supply prose pedagogy.
 */
function synthesiseRuleSectionText(rule: BillingRule): string {
  const domainHint = rule.domain_match.kind === 'ends_with'
    ? `(sender domain *.${rule.domain_match.suffix})`
    : `(sender domain matching /${rule.domain_match.pattern}/)`;
  const outcomeText = (() => {
    const name = rule.outcome.agency_name;
    switch (rule.outcome.kind) {
      case 'always_agency':
        return `ALWAYS bill the agency. ` +
          `billing_party = { "type": "agency", "name": "${name}" }.`;
      case 'owner_if_named_else_agency':
        return `VARIANCE — if the email/PDF names an owner, ` +
          `billing_party = { "type": "owner", "name": "<owner>" }; ` +
          `otherwise billing_party = { "type": "agency", "name": "${name}" }.`;
      case 'trust_llm_or_fallback_agency':
        return `trust your routing of the agency name; ` +
          `fall back to billing_party = { "type": "agency", "name": "${name}" }.`;
    }
  })();
  return `${domainHint}: ${outcomeText}`;
}

/**
 * Build the "BILLING party rules — apply per source:" block from the
 * config's `billing_rules[]`. Each rule produces one bullet; the
 * trailing "Ambiguous / unknown sources: billing_party = null" bullet
 * is appended unconditionally (it's the catch-all for everything
 * outside the config).
 */
export function buildBillingRulesSection(config: AdapterConfigMetadata): string {
  const header = 'BILLING party rules — apply per source:';
  if (config.billing_rules.length === 0) {
    return [
      header,
      '  - All sources: billing_party = null (no rules configured; ' +
        'operator will manually correct).',
    ].join('\n');
  }
  const lines: string[] = [header];
  for (const rule of config.billing_rules) {
    const body = rule.prompt_fragments?.rules_section_text
      ?? synthesiseRuleSectionText(rule);
    lines.push(`  - ${rule.agency_name} ${body}`);
  }
  lines.push(
    '  - Ambiguous / unknown sources: billing_party = null. ' +
    'The operator will manually correct.',
  );
  return lines.join('\n');
}

/**
 * Build the point-of-contact heuristics block from any
 * `prompt_fragments.heuristic_text` entries on configured rules. Rules
 * without a heuristic text are skipped. Returns an empty string when no
 * rule supplies one — caller should be prepared to omit the surrounding
 * "Heuristics:" header in that case (the static template handles this
 * via the placeholder shape).
 */
export function buildPocHeuristics(config: AdapterConfigMetadata): string {
  const lines = config.billing_rules
    .map(r => r.prompt_fragments?.heuristic_text)
    .filter((t): t is string => typeof t === 'string' && t.length > 0);
  return lines.join('\n');
}

/**
 * Inline parenthetical list of agency names; used in spots like
 * `(Clever Property, Robert James Realty, Bricks + Agent)` in
 * the worked-example intro. Empty config → empty string (caller omits).
 */
export function buildAgencyListInline(config: AdapterConfigMetadata): string {
  return formatAgencyList(config.billing_rules.map(r => r.agency_name));
}

/**
 * The static prompt template with placeholder tokens. The placeholders
 * are filled in `buildPromptTemplate()` below from a config. The body
 * of the worked example (Clever Property canonical PDF + expected
 * JSON output) is intentionally kept here, not moved into config —
 * see the file header for the rationale.
 *
 * Placeholders (resolved by buildPromptTemplate):
 *   {{HEAD}}                     — runtime: email headers (left as-is)
 *   {{BODY}}                     — runtime: email body (left as-is)
 *   {{MAINTENANCE_AGENCIES}}     — config: inline agency list
 *   {{DISPATCHER_AGENCIES}}      — config: inline agency list
 *   {{POC_HEURISTICS}}           — config: heuristic block (multi-line)
 *   {{WORKED_EXAMPLE_AGENCIES}}  — config: inline agency list
 *   {{BILLING_RULES_SECTION}}    — config: full rules section
 *   {{DATE_FORMAT_AGENCY_HINT}}  — config: inline agency list
 */
const PROMPT_TEMPLATE_RAW = `You are triaging a single email in a tradesperson's inbox. Operator
domain expertise: real customer-facing **jobs always arrive as exactly
one of three event types** — Quote Request, Work Order, or Maintenance
Order. Anything else is NOT a new job and must be filtered out — false
positives flood the review queue with platform notifications, billing
receipts, and newsletters.

Email headers and body:
---
{{HEAD}}
---
{{BODY}}
---

Respond with a JSON object matching the schema. Work in two phases.

==============================
Phase 1 — classify (required)
==============================

Set \`job_type\` to EXACTLY ONE of:

- \`quote_request\` — a customer is asking the operator to provide a
  quote / estimate / pricing for potential work. Common signals:
  "Could you quote", "What would it cost", "Looking for an estimate",
  subject contains "Quote Request" or "Request for Quote", an attached
  PDF is a tender / RFQ / quote document.

- \`work_order\` — the operator has been formally assigned / awarded
  work, or a property manager / dispatcher is dispatching a job to
  them. Common signals: "Work Order", "Job awarded", "Maintenance
  request approved", PDF attachments labelled "Work Order" or carrying
  a job number, a completion date specified, "please attend" /
  "please complete" wording from a property manager.

- \`maintenance_order\` — a maintenance / repair request from a
  property manager or tenant{{MAINTENANCE_AGENCIES}} with a property
  address + an issue description (e.g. "leaking tap at 13 Orealla Cr",
  "oven not heating").

- \`thread_followup\` — this email is a reply or continuation on an
  existing job thread. It is about an existing job (scheduling
  access, asking questions, confirming a completion date, sending an
  invoice or receipt for work already done), NOT a new job request.
  Common signals: "Re:" subject prefix; the body quotes / replies to
  a prior message; confirming or rescheduling dates for
  previously-discussed work; attaching an invoice for completed work.

- \`not_a_job\` — anything else. Examples that MUST be classified
  here, even when the email is "structured" or looks important:
    * Platform notifications — Google Cloud, Google Workspace, Google
      Ads, Facebook / Meta business updates, Microsoft / Outlook
      notices, dispatcher **weekly digest summaries** (a digest is
      NOT a work order — only individual dispatched jobs are).
    * Marketing emails, newsletters, advertising.
    * Billing receipts from the operator's own vendors — payment
      confirmations, subscription renewals, advertising spend
      receipts (e.g. Desire Industries advertising receipt, Google
      Ads invoice).
    * Account / security alerts — password changes, MFA setup
      reminders, account-permission changes, login alerts.
    * Cold-call sales pitches to the operator's business.
    * Personal correspondence with no job content.

When unsure between \`not_a_job\` and one of the three job-creating
values, choose \`not_a_job\`. False positives are far worse than false
negatives here — the operator would rather miss a borderline case than
be flooded with non-jobs.

For \`thread_followup\` and \`not_a_job\`, return ONLY \`job_type\`,
\`summary\` (one short sentence stating WHY you classified it that
way), and a \`rationale\` if helpful. Do NOT populate \`customer\`,
\`job\`, or \`point_of_contact\` — Phase 2 only runs for the three
job-creating values.

==============================
Phase 2 — extract (only for quote_request | work_order | maintenance_order)
==============================

If and only if \`job_type\` is one of the three job-creating values,
populate the rest of the payload.

If the email or any attachment mentions a work-order number, job number,
PO number, or platform reference (e.g. PropertyMe, BricksAndAgent order
numbers), extract it into job.referenceNumber exactly as it appears.

Identify the **point of contact** for this job and put it in
\`point_of_contact\` — the person or organisation actively in the loop
with the operator about THIS job, regardless of role. This is whoever
the operator would naturally text or call to talk about the work. It
is NOT the billing party (that is tracked separately), NOT the
property address, and NOT the property owner unless they're actually
the one communicating about the job.

The point of contact could be ANY of these — the role doesn't matter,
only who's actually in the loop:
  - The **agency / real estate / dispatcher** that routed the work
    order{{DISPATCHER_AGENCIES}}.
  - A named **property manager** at the agency (e.g. Matthew Pohlen).
  - The **tenant** living at the property — often the day-to-day
    liaison for access, scheduling, and questions about repairs.
  - The **landlord / owner** when they're directly emailing the
    operator with no agency in the chain.
  - A **sub-tradie or other coordinator** asking the operator to
    collab on someone else's job.

Heuristics:
{{POC_HEURISTICS}}  - Email forwarded to the operator from the agency that originated
    from a tenant ("Hi Todd, I'm Sarah, the tenant at 13 Orealla Cr…"),
    OR a tenant emailing the operator directly: use
    "<Tenant name> (tenant)" (e.g. "Sarah Liu (tenant)").
  - Direct email from a landlord with no agency intermediary: use
    "<Landlord name> (direct)" so the operator knows there is no
    agency in the loop (e.g. "Sarah Nguyen (direct)").
  - Email from another tradie wanting to collaborate: use
    "<Tradie name> (sub-tradie)" (e.g. "Dan Murphy (sub-tradie)").
  - Fallback when the role isn't clear from context: use the From-line
    sender name verbatim, optionally appending a role inferred from
    context in parentheses if any signal is present.

Keep \`point_of_contact\` short (under 80 chars) and human-readable —
it is shown verbatim as the job's display name in the operator's helm
and mobile job list.

==============================
Phase 2 (continued) — DEEP STRUCTURED FIELDS for PDF work orders / quote requests
==============================

Real estate PDFs{{WORKED_EXAMPLE_AGENCIES}} carry a CONSISTENT block of
fields the operator wants extracted into structured form. The canonical
example is a Clever Property quote request:

------- BEGIN canonical Clever Property quote request -------
8 Thomas St
Noosaville QLD 4566
(w) 07 5473 0508
www.cleverproperty.com.au
pm@cleverproperty.com.au
ABN: 33 816 651 256
Licence: 4076428

Quote Request

Odd Job Todd - Handyman
0475 303 187
todd.price.aus@gmail.com

Job number - 07487
Created: 17/03/2026
Due: 24/03/2026

Details

Property
29 Foedera Cres, Tewantin QLD 4565 (key #177)

For access contact the tenant/s on:
Jo-Anne Bisman                  ← FIRST tenant listed = PRIMARY (bold in PDF)
(m) 0450688322 (h) n/a (w) n/a
(e) josiesingh@bigpond.com

Sujit (Sunny) Singh             ← secondary tenant
(m) 0449988150 (h) n/a (w) n/a
(e) sunnymehmi2221@gmail.com

Work order issued on behalf of the owner - Adrian Levy

For queries contact the agent on:
Zoe Welch
(w) 0754730508
(e) zoe.welch@cleverproperty.com.au

Description
Summary
Paint Ceiling in areas where discoloured
Description
The ceiling has discolouration in areas of the kitchen / dining area...
------- END canonical Clever Property quote request -------

Expected JSON for the example above:
{
  "job_type": "quote_request",
  "summary": "Clever Property quote request — paint ceiling at 29 Foedera Cres, Tewantin.",
  "work_order_number": "07487",
  "issuance_date": "2026-03-17",
  "due_date": "2026-03-24",
  "property_address": "29 Foedera Cres, Tewantin QLD 4565",
  "property_key": "key #177",
  "primary_contact": {
    "name": "Jo-Anne Bisman",
    "role": "tenant",
    "phone": "0450688322",
    "email": "josiesingh@bigpond.com"
  },
  "secondary_contacts": [
    {
      "name": "Sujit (Sunny) Singh",
      "role": "tenant",
      "phone": "0449988150",
      "email": "sunnymehmi2221@gmail.com"
    },
    {
      "name": "Zoe Welch",
      "role": "agent",
      "phone": "0754730508",
      "email": "zoe.welch@cleverproperty.com.au"
    }
  ],
  "owner_name": "Adrian Levy",
  "billing_party": { "type": "agency", "name": "Clever Property" },
  "has_photos": false,
  "photo_count": 0
}

A second worked example — same Clever Property template, different job
(07628):

{
  "job_type": "quote_request",
  "summary": "Clever Property quote request — replace damaged screen door at 11 Riverside Dr, Noosaville.",
  "work_order_number": "07628",
  "issuance_date": "2026-04-02",
  "due_date": "2026-04-09",
  "property_address": "11 Riverside Dr, Noosaville QLD 4566",
  "property_key": "key #198",
  "primary_contact": { "name": "Sarah Liu", "role": "tenant", "phone": "0421555111", "email": "sarah.liu@example.com" },
  "secondary_contacts": [
    { "name": "Zoe Welch", "role": "agent", "phone": "0754730508", "email": "zoe.welch@cleverproperty.com.au" }
  ],
  "owner_name": "Marian Crowe",
  "billing_party": { "type": "agency", "name": "Clever Property" },
  "has_photos": true,
  "photo_count": 2
}

PRIMARY contact rule:
- The first tenant listed under "For access contact the tenant/s on:"
  is the PRIMARY contact (rendered bold in source PDFs). Use their
  MOBILE phone (m) as primary phone; fall back to home (h), then
  work (w). If all are "n/a" → phone: null.
- point_of_contact display string is "<primary tenant name> (tenant)".
  You MAY emit point_of_contact, but the server will derive it from
  primary_contact server-side as the canonical source of truth.

SECONDARY contacts rule:
- Additional tenants in the access section.
- The agent listed under "For queries contact the agent on:".
- Owner name from "Work order issued on behalf of the owner - <name>"
  line is captured as owner_name (separate field), NOT as a contact
  unless they have a phone/email listed elsewhere.

{{BILLING_RULES_SECTION}}

DATE format: convert Australian "DD/MM/YYYY" to ISO "YYYY-MM-DD".
NEVER swap the day/month — Australian agency PDFs{{DATE_FORMAT_AGENCY_HINT}} are always DD/MM/YYYY.

PHOTOS: PDFs with 2+ pages typically carry site photos on page 2+.
Set has_photos: true if Vision detected ≥1 photo on any page;
photo_count = best-effort count of distinct photos. When you cannot
tell, leave both fields out (do not invent zeros).

SERVICES (v0.6): emit short, lowercase, hyphenated tags identifying
the kind of work the email is about. The tags drive operator chat
resolution — when the operator later types "quote 500 for the
pergola job" the resolver matches on these tags. Examples:
"plumbing", "roof-repair", "pergola", "leak-investigation",
"fence-replacement", "tap-replacement", "hot-water-system",
"oven-repair", "electrical", "carpentry", "landscaping". One to
three tags is typical. Use the most specific tag the email
supports — "leak-investigation" beats "plumbing" when the body
mentions a leak. Omit the field (or pass an empty array) when
nothing identifiable is described.

For thread_followup and not_a_job: leave ALL of the new fields
(work_order_number, issuance_date, due_date, property_address,
property_key, primary_contact, secondary_contacts, owner_name,
billing_party, has_photos, photo_count, services) null, empty, or
omit them.`;

/**
 * Compose a prompt template from `AdapterConfigMetadata`. Returns the
 * template still containing the runtime `{{HEAD}}` / `{{BODY}}`
 * placeholders so the caller (EmailExtractor) can fill them per-message
 * — only the agency-pedagogy placeholders are resolved here.
 */
export function buildPromptTemplate(config: AdapterConfigMetadata): string {
  const inlineList = buildAgencyListInline(config);
  // The maintenance_order classification clause: previously "Often
  // comes through Bricks + Agent or Robert James Realty (RJR)".
  // Empty config → drop the parenthetical entirely.
  const maintenanceAgencies = inlineList
    ? ` (often routed via ${inlineList})`
    : '';
  // The dispatcher example list: previously "(e.g. Robert James
  // Realty, Bricks + Agent's auto-dispatch)". Empty config → drop.
  const dispatcherAgencies = inlineList
    ? ` (e.g. ${inlineList})`
    : '';
  // The worked-example intro parenthetical: previously "(Clever
  // Property, Robert James Realty / RJR, Bricks + Agent)". Empty
  // config → drop.
  const workedExampleAgencies = inlineList
    ? ` (${inlineList})`
    : '';
  // The DD/MM/YYYY note's agency qualifier: previously "Clever
  // Property and RJR PDFs". With config it lists actual configured
  // agencies; empty config → drop the qualifier.
  const dateAgencies = inlineList
    ? ` from ${inlineList}`
    : '';
  // POC heuristics block: only shows config-driven entries; the
  // generic tenant / direct / sub-tradie heuristics in the static
  // template remain unconditionally below the placeholder.
  const pocHeuristics = buildPocHeuristics(config);
  const pocHeuristicsBlock = pocHeuristics ? `${pocHeuristics}\n` : '';
  return PROMPT_TEMPLATE_RAW
    .replace('{{MAINTENANCE_AGENCIES}}', maintenanceAgencies)
    .replace('{{DISPATCHER_AGENCIES}}', dispatcherAgencies)
    .replace('{{WORKED_EXAMPLE_AGENCIES}}', workedExampleAgencies)
    .replace('{{DATE_FORMAT_AGENCY_HINT}}', dateAgencies)
    .replace('{{POC_HEURISTICS}}', pocHeuristicsBlock)
    .replace('{{BILLING_RULES_SECTION}}', buildBillingRulesSection(config));
}

```
