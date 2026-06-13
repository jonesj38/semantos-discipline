---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.477582+00:00
---

# cartridges/oddjobz/brain/src/capabilities.ts

```ts
/**
 * D-O3 — Oddjobz capability mints.
 *
 * See `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §O3 (capability mints), §3
 * Phase O3 (the table); `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` §3
 * (resource set, `capabilities` row), §2.5 (carpenter+musician hat
 * isolation invariant); `docs/spec/protocol-v0.5.md` §4.5 (domain flag
 * namespace), §5 (capability tokens); `core/cell-engine/src/opcodes/
 * plexus.zig` line ~198 (the `OP_CHECKDOMAINFLAG` opcode that enforces
 * domain-flag match on a presented cap UTXO).
 *
 * ── What this module ships ───────────────────────────────────────────
 *
 * Six capability declarations, each carrying:
 *   - a stable `name`           (cap.oddjobz.<verb> — used by the
 *                                dispatcher's CapabilitySet at the
 *                                operator-surface seam, and as the
 *                                allowlist entry on the operator-root
 *                                identity cert at first boot)
 *   - a stable `domain_flag`    (a uint32 in the operator-sovereignty
 *                                range per protocol-v0.5 §4.5; the
 *                                value the kernel-gate `OP_CHECKDOMAIN
 *                                FLAG` enforces on the presented cap
 *                                UTXO at FSM transition time per
 *                                §O4 — see D-O4)
 *   - a `description`           (operator-readable role)
 *   - a `role_in_fsm`           (which §O4 transition this cap gates)
 *   - a `gates: readonly string[]` (the §O4 transitions this cap is
 *                                spent at, e.g. "lead → quoted")
 *   - a `holder: 'operator-root' | 'node-service'`
 *                               (who carries the cap UTXO in the
 *                                steady-state cap set)
 *
 * Plus a deterministic `mintCapabilityCell(cap, contextTag, ownerId)`
 * helper that builds the canonical 1024-byte cell bytes for the cap
 * UTXO — header (magic / linearity / version / domain_flag / type_hash
 * / owner_id / context_tag) + payload (cap name as canonical-JSON).
 * This is the "on-chain" side of the capability-mint that
 * §O3 requires for OP_CHECKDOMAINFLAG enforcement and that K3
 * (DomainIsolationK3.lean) is proved against.
 *
 * ── Domain-flag scheme — page-aligned canonical low-bits assignment ─
 *
 * Per Plexus client-spec requirement 2.2.2 + tech-spec §30, the
 * `0x00010000`–`0xFFFFFFFF` range is the client-sovereignty tier.
 * We are setting up the primary shape of architecture which will be
 * deployed repeatedly; the canonical oddjobz cap suite claims the
 * low-bits page `0x000101xx` so any deployment of this extension uses
 * identical numbers. This lines up with `runtime/shell/src/
 * capabilities.ts`, which already claims `0x00010001..0x0001000B` for
 * loom-shell verb caps on the `0x000100xx` page.
 *
 * Page allocation (canonical, repo-wide):
 *
 *     0x000100xx — semantos loom-shell verbs
 *                  (already claimed at 0x00010001..0x0001000B)
 *     0x000101xx — oddjobz canonical caps      ← THIS EXTENSION
 *     0x000102xx — next canonical extension     (reserved, not minted)
 *     ...
 *     0x0001FFxx — 256th canonical extension page
 *     0x00020000+ — per-tenant local mints / custom caps invented per
 *                   deployment. Out of band of the canonical pages so
 *                   they cannot collide with a shipping extension.
 *
 * Oddjobz cap assignments (verbatim, frozen):
 *
 *     cap.oddjobz.quote             → 0x00010101
 *     cap.oddjobz.dispatch          → 0x00010102
 *     cap.oddjobz.invoice           → 0x00010103
 *     cap.oddjobz.close             → 0x00010104
 *     cap.oddjobz.write_customer    → 0x00010105
 *     cap.oddjobz.public_chat_serve → 0x00010106
 *
 * Why page-aligned low-bits (and not the earlier 0x4F4A_* ASCII high
 * bits, or a hash of the cap name):
 *
 *   1. **Canonical and repeatable.** Every deployment of the oddjobz
 *      extension uses identical numbers — there is no per-tenant
 *      drift, no registry lookup, no name-hash derivation. A
 *      different deployment on a different brain can audit-compare
 *      cap UTXOs by raw flag value.
 *   2. **Page-aligned with the loom-shell tier.** The shell verbs
 *      sit at `0x000100xx`; oddjobz at `0x000101xx`; future canonical
 *      extensions march along the next pages. A glance at a domain
 *      flag in an audit log identifies the extension by the page
 *      byte: `0x01` = shell, `0x02` = oddjobz, etc.
 *   3. **Mint-time-deterministic.** The §O3 acceptance requirement —
 *      same as the prior scheme. Stable across rebuilds, no clock,
 *      no random.
 *   4. **Out of all reserved Plexus ranges.** `0x00010101` sits well
 *      clear of the Plexus reserved tier (`<= 0xFF`) and the extended
 *      Plexus tier (`<= 0xFFFF`).
 *   5. **Per-tenant escape hatch preserved.** Deployments that need a
 *      custom cap unique to their brain can still mint above
 *      `0x00020000` without touching the canonical pages.
 *
 * The §O3 plan-table commentary mentioned an earlier ad-hoc range
 * (`0x20–0x25`); that was pre-v0.5. The first D-O3 commit shipped
 * `0x4F4A_<ordinal>` (ASCII 'OJ' high-bits, ordinal low-bits) — also
 * client-sovereign but not page-aligned with the loom-shell tier.
 * This module replaces it with the canonical low-bits page so
 * audit-log diffs across deployments are byte-identical.
 *
 * ── How this lands ──────────────────────────────────────────────────
 *
 *  - The operator-root cert at brain first-boot carries the FIVE
 *    operator-held caps below in its `capabilities: []` field
 *    (delegated to the Semantos Brain dispatcher's identity_certs.issue_root or
 *    via a subsequent capability-set update — exact seam in
 *    `runtime/semantos-brain/src/extensions.zig`).
 *  - The node-service principal carries `cap.oddjobz.public_chat_serve`
 *    (rate-limited per §O3 plan).
 *  - D-O4 (state machines) consumes this module: each FSM transition
 *    looks up the gating cap by name, asserts the cap UTXO is
 *    present, and emits `OP_CHECKDOMAINFLAG <flag>` against the
 *    presented cap cell at the kernel gate.
 */

import { createHash } from 'node:crypto';

import { encodeCanonicalJson } from './cell-types/canonical-json.js';
import {
  WireLinearity,
  type WireLinearityCode,
} from './cell-types/linearity.js';
import { computeTypeHash, typeHashHex } from './cell-types/type-hash.js';

/* ══════════════════════════════════════════════════════════════════════
 * Cap declarations
 * ══════════════════════════════════════════════════════════════════════ */

/** Stable canonical names for the sixteen oddjobz capabilities. */
export const ODDJOBZ_CAP_NAMES = [
  'cap.oddjobz.write_customer',
  'cap.oddjobz.quote',
  'cap.oddjobz.dispatch',
  'cap.oddjobz.invoice',
  'cap.oddjobz.close',
  'cap.oddjobz.public_chat_serve',
  'cap.oddjobz.read_jobs',
  'cap.oddjobz.read_customers',
  'cap.oddjobz.read_visits',
  'cap.oddjobz.write_visit',
  'cap.oddjobz.read_quotes',
  'cap.oddjobz.write_quote',
  'cap.oddjobz.read_invoices',
  'cap.oddjobz.write_invoice',
  'cap.oddjobz.read_attachments',
  'cap.oddjobz.write_attachment',
  'cap.oddjobz.write_policy',
] as const;

export type OddjobzCapName = (typeof ODDJOBZ_CAP_NAMES)[number];

/**
 * Holder of a cap UTXO in the steady-state oddjobz cap set:
 *   - `operator-root` — sits under the operator's BRC-52 root cert and
 *     is delegated to child certs at pairing time per the D-O5p plan
 *     allowlist;
 *   - `node-service`  — minted to the node daemon principal directly,
 *     never bound to a hat. Only the public-chat handler uses this so
 *     visitor chat works without operator capabilities.
 */
export type CapHolder = 'operator-root' | 'node-service';

export interface OddjobzCapability {
  /** Stable canonical name (`cap.oddjobz.<verb>`). */
  readonly name: OddjobzCapName;
  /**
   * Stable uint32 domain flag — the value `OP_CHECKDOMAINFLAG`
   * compares against at the kernel gate per §O4. See module head for
   * the namespacing scheme.
   */
  readonly domainFlag: number;
  /** Operator-readable description for audit logs / glossary. */
  readonly description: string;
  /** Plain-English placement of this cap in the §O4 FSM machinery. */
  readonly roleInFsm: string;
  /**
   * §O4 transitions this cap is spent at. Format `state_a → state_b`
   * mirrors the plan tables verbatim. Multiple entries when the same
   * cap gates more than one transition (none today; reserved for
   * future FSM extension).
   */
  readonly gates: readonly string[];
  /** Who holds the cap UTXO in steady state. */
  readonly holder: CapHolder;
}

/**
 * Build a single capability declaration. Domain flag is mint-time-
 * deterministic per the scheme in the module head — passed in
 * verbatim so the constants stay readable and the scheme is enforced
 * by the unique-flag test below rather than by a function over the
 * cap name.
 */
function defineCapability(spec: OddjobzCapability): OddjobzCapability {
  return Object.freeze(spec);
}

/* ── The six declarations — declaration order matches §O3 plan table ── */

export const capWriteCustomer: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_customer',
  domainFlag: 0x0001_0105,
  description:
    'Authorises customer create / merge writes against the oddjobz substrate. ' +
    'Held by the operator root cert; delegated to phone child certs by default ' +
    'via the D-O5p pairing allowlist.',
  roleInFsm:
    'Spent on Customer create / merge transitions — the genesis path for an ' +
    'oddjobz.customer.v1 PERSISTENT cell (and any contact-detail update via ' +
    'prevStateHash-chained successor cell).',
  gates: ['∅ → customer.created', 'customer → customer.updated'],
  holder: 'operator-root',
});

export const capQuote: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.quote',
  domainFlag: 0x0001_0101,
  description:
    'Authorises issuing a price for a Job — the operator exercises the ' +
    'jural power to offer. Held by the operator root cert.',
  roleInFsm:
    'Spent on the Job FSM `lead → quoted` transition; mints an ' +
    'oddjobz.quote.v1 LINEAR cell as the priced offer.',
  gates: ['lead → quoted'],
  holder: 'operator-root',
});

export const capDispatch: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.dispatch',
  domainFlag: 0x0001_0102,
  description:
    'Authorises committing the operator (or a delegated tradie) to a visit ' +
    'slot — the jural obligation acceptance for a quoted job. Held by the ' +
    'operator root cert.',
  roleInFsm:
    'Spent on the Job FSM `quoted → scheduled` transition; mints an ' +
    'oddjobz.visit.v1 LINEAR cell tied to a calendar slot.',
  gates: ['quoted → scheduled'],
  holder: 'operator-root',
});

export const capInvoice: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.invoice',
  domainFlag: 0x0001_0103,
  description:
    'Authorises issuing an invoice on a completed Job — the obligation to pay ' +
    'is created. Held by the operator root cert; NOT delegated to phone child ' +
    'certs by default per D-O5p risks-section (§10).',
  roleInFsm:
    'Spent on the Job FSM `completed → invoiced` transition; mints an ' +
    'oddjobz.invoice.v1 LINEAR cell.',
  gates: ['completed → invoiced'],
  holder: 'operator-root',
});

export const capClose: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.close',
  domainFlag: 0x0001_0104,
  description:
    'Authorises the terminal close transition on a Job — jural satisfaction. ' +
    'Held by the operator root cert; NOT delegated to phone child certs by ' +
    'default (D-O5p §10).',
  roleInFsm:
    'Spent on the Job FSM `paid → closed` transition; closes the work-unit ' +
    'and severs the Job\'s LINEAR successor chain (terminal state).',
  gates: ['paid → closed'],
  holder: 'operator-root',
});

export const capPublicChatServe: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.public_chat_serve',
  domainFlag: 0x0001_0106,
  description:
    'Authorises the node daemon to serve anonymous public-chat messages on a ' +
    'rate-limited basis. Service capability — held by the node service principal, ' +
    'NOT by any operator hat. Same shape as cap.social.draft (cheap-and-runtime).',
  roleInFsm:
    'Presented at the public-chat dynamic route per D-O6a; permits anonymous ' +
    'visitor turns through the LLM passthrough. D-O6b layers cell persistence ' +
    'on top via the ratification queue path.',
  gates: ['anonymous → chat.message.transient (D-O6a)'],
  holder: 'node-service',
});

/* ── D-O5.followup-1 / D-O5m.followup-4 — read_jobs ──
 *
 * The brain dispatcher's typed `find_jobs` resource gates `jobs.find` and
 * `jobs.find_by_id` on this cap (`runtime/semantos-brain/src/resources/jobs_
 * handler.zig`).  Held by the operator-root cert and delegated to phone
 * child certs by default via the D-O5p pairing allowlist — operators
 * read their own jobs from any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Job cells in their
 * current FSM state but does NOT permit any FSM transition (those gate
 * on `cap.oddjobz.quote`, `cap.oddjobz.dispatch`, `cap.oddjobz.invoice`,
 * `cap.oddjobz.close`).  Surface a separate read-cap so a future
 * read-only-helm role (e.g. an operator's accountant) can be issued a
 * cert that lists jobs without being able to mutate them.
 *
 * Domain flag `0x00010107` is the next slot on the canonical `0x000101xx`
 * page after `cap.oddjobz.public_chat_serve` (`0x00010106`); see the
 * page-allocation scheme in the module head.
 */
export const capReadJobs: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_jobs',
  domainFlag: 0x0001_0107,
  description:
    'Authorises read-only enumeration of Job cells across all FSM states. ' +
    'Held by the operator root cert; delegated to phone child certs by ' +
    'default via the D-O5p pairing allowlist. Required by the Semantos Brain ' +
    'dispatcher\'s typed `jobs.find` and `jobs.find_by_id` resource ' +
    'commands. Read-only — does NOT gate any FSM transition.',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `jobs` resource for the read ' +
    'commands; not consumed by any FSM transition (read-only cap).',
  gates: ['(read-only — not an FSM transition)'],
  holder: 'operator-root',
});

/* ── D-O5.followup-3 — read_customers ──
 *
 * The brain dispatcher's typed `customers` resource gates
 * `customers.find` and `customers.find_by_id` on this cap
 * (`runtime/semantos-brain/src/resources/customers_handler.zig`).  Held by the
 * operator-root cert and delegated to phone child certs by default via
 * the D-O5p pairing allowlist — operators read their own customers
 * from any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Customer cells but
 * does NOT permit creating, merging, or otherwise mutating them (those
 * gate on `cap.oddjobz.write_customer`).  Surfacing a separate read
 * cap mirrors the `cap.oddjobz.read_jobs` shape and lets a future
 * read-only-helm role (e.g. an operator's accountant) be issued a
 * cert that lists customers without being able to mutate them.
 *
 * Domain flag `0x00010108` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_jobs` (`0x00010107`); see
 * the page-allocation scheme in the module head.
 */
export const capReadCustomers: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_customers',
  domainFlag: 0x0001_0108,
  description:
    'Authorises read-only enumeration of Customer cells. ' +
    'Held by the operator root cert; delegated to phone child certs by ' +
    'default via the D-O5p pairing allowlist. Required by the Semantos Brain ' +
    'dispatcher\'s typed `customers.find` and `customers.find_by_id` ' +
    'resource commands. Read-only — does NOT gate any Customer write ' +
    '(that gates on `cap.oddjobz.write_customer`).',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `customers` resource for the ' +
    'read commands; not consumed by any FSM transition (read-only cap).',
  gates: ['(read-only — not an FSM transition)'],
  holder: 'operator-root',
});

/* ── D-O4.followup-2 — read_visits ──
 *
 * The brain dispatcher's typed `visits` resource gates `visits.find`,
 * `visits.find_by_id`, and `visits.transition` on this cap
 * (`runtime/semantos-brain/src/resources/visits_handler.zig`).  Held by the
 * operator-root cert and delegated to phone child certs by default via
 * the D-O5p pairing allowlist — operators read their own visits from
 * any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Visit cells but
 * does NOT permit creating new Visit records (those gate on
 * `cap.oddjobz.write_visit`).  The `visits.transition` cmd is
 * dispatcher-gated on this read cap — every Visit FSM row is ungated
 * at the FSM-row level today (gating is delegated to the parent Job
 * FSM per the canon), so the read cap is the only gate operators see.
 *
 * Domain flag `0x00010109` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_customers` (`0x00010108`);
 * see the page-allocation scheme in the module head.
 */
export const capReadVisits: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_visits',
  domainFlag: 0x0001_0109,
  description:
    'Authorises read-only enumeration of Visit cells across all Visit ' +
    'FSM states.  Held by the operator root cert; delegated to phone ' +
    'child certs by default via the D-O5p pairing allowlist.  Required ' +
    'by the Semantos Brain dispatcher\'s typed `visits.find`, `visits.find_by_id`, ' +
    'and `visits.transition` resource commands.  Read-only at the ' +
    'cap-mint layer — Visit FSM transitions themselves are ungated per ' +
    'the §O4 canon (gating is delegated to the parent Job FSM).',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `visits` resource for the read + ' +
    'transition commands; not consumed by any Visit FSM transition ' +
    '(every Visit row is ungated today).',
  gates: ['(read-only — gates the visits resource, not an FSM row)'],
  holder: 'operator-root',
});

/* ── D-O4.followup-2 — write_visit ──
 *
 * The brain dispatcher's typed `visits.create` cmd gates on this cap.
 * Held by the operator-root cert and delegated to phone child certs by
 * default via the D-O5p pairing allowlist — operators schedule visits
 * from any device they paired into.
 *
 * Domain flag `0x0001010A` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_visits` (`0x00010109`).
 */
export const capWriteVisit: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_visit',
  domainFlag: 0x0001_010a,
  description:
    'Authorises Visit create writes against the oddjobz substrate.  Held ' +
    'by the operator root cert; delegated to phone child certs by ' +
    'default via the D-O5p pairing allowlist.  Required by the Semantos Brain ' +
    'dispatcher\'s typed `visits.create` resource cmd.  Write-only — ' +
    'enumeration gates on `cap.oddjobz.read_visits`.',
  roleInFsm:
    'Spent on Visit create transitions — the genesis path for an ' +
    'oddjobz.visit.v1 LINEAR cell tied to a parent Job (FK to the Job ' +
    'cell).',
  gates: ['∅ → visit.scheduled'],
  holder: 'operator-root',
});

/* ── D-O4.followup-3 — read_quotes ──
 *
 * The brain dispatcher's typed `quotes` resource gates `quotes.find`,
 * `quotes.find_by_id`, and `quotes.transition` on this cap
 * (`runtime/semantos-brain/src/resources/quotes_handler.zig`).  Held by the
 * operator-root cert and delegated to phone child certs by default via
 * the D-O5p pairing allowlist — operators read their own quotes from
 * any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Quote cells but
 * does NOT permit creating new Quote records (those gate on
 * `cap.oddjobz.write_quote`).  The `quotes.transition` cmd is
 * dispatcher-gated on this read cap — every Quote FSM row is ungated
 * at the FSM-row level today (gating is delegated to the parent Job
 * FSM per the canon), so the read cap is the only gate operators see.
 *
 * Domain flag `0x0001010B` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.write_visit` (`0x0001010A`);
 * see the page-allocation scheme in the module head.
 */
export const capReadQuotes: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_quotes',
  domainFlag: 0x0001_010b,
  description:
    'Authorises read-only enumeration of Quote cells across all Quote ' +
    'FSM states.  Held by the operator root cert; delegated to phone ' +
    'child certs by default via the D-O5p pairing allowlist.  Required ' +
    'by the Semantos Brain dispatcher\'s typed `quotes.find`, `quotes.find_by_id`, ' +
    'and `quotes.transition` resource commands.  Read-only at the ' +
    'cap-mint layer — Quote FSM transitions themselves are ungated per ' +
    'the §O4 canon (gating is delegated to the parent Job FSM).',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `quotes` resource for the read + ' +
    'transition commands; not consumed by any Quote FSM transition ' +
    '(every Quote row is ungated today).',
  gates: ['(read-only — gates the quotes resource, not an FSM row)'],
  holder: 'operator-root',
});

/* ── D-O4.followup-3 — write_quote ──
 *
 * The brain dispatcher's typed `quotes.create` cmd gates on this cap.
 * Held by the operator-root cert and delegated to phone child certs by
 * default via the D-O5p pairing allowlist — operators draft quotes
 * from any device they paired into.
 *
 * Domain flag `0x0001010C` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_quotes` (`0x0001010B`).
 *
 * Note: `cap.oddjobz.quote` (`0x00010101`) is the §O3 canonical cap
 * spent on the parent Job FSM's `lead → quoted` transition (which mints
 * the Quote cell in `draft` state).  This `write_quote` cap is the
 * read-side mirror — the dispatcher gate that permits an operator
 * (or paired device) to create a Quote record in the helm-side store.
 * The two caps coexist by design; the §O3 cap drives the cell-DAG
 * mint, this cap drives the dispatcher-resource create cmd.
 */
export const capWriteQuote: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_quote',
  domainFlag: 0x0001_010c,
  description:
    'Authorises Quote create writes against the oddjobz substrate.  Held ' +
    'by the operator root cert; delegated to phone child certs by ' +
    'default via the D-O5p pairing allowlist.  Required by the Semantos Brain ' +
    'dispatcher\'s typed `quotes.create` resource cmd.  Write-only — ' +
    'enumeration gates on `cap.oddjobz.read_quotes`.',
  roleInFsm:
    'Spent on Quote create transitions — the genesis path for an ' +
    'oddjobz.quote.v1 LINEAR cell tied to a parent Job (FK to the Job ' +
    'cell).',
  gates: ['∅ → quote.draft'],
  holder: 'operator-root',
});

/* ── D-O4.followup-4 — read_invoices ──
 *
 * The brain dispatcher's typed `invoices` resource gates `invoices.find`,
 * `invoices.find_by_id`, and `invoices.transition` on this cap
 * (`runtime/semantos-brain/src/resources/invoices_handler.zig`).  Held by the
 * operator-root cert and delegated to phone child certs by default via
 * the D-O5p pairing allowlist — operators read their own invoices from
 * any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Invoice cells but
 * does NOT permit creating new Invoice records (those gate on
 * `cap.oddjobz.write_invoice`).  The `invoices.transition` cmd is
 * dispatcher-gated on this read cap — every Invoice FSM row is
 * ungated at the FSM-row level today (gating is delegated to the
 * parent Job FSM per the canon), so the read cap is the only gate
 * operators see.
 *
 * Domain flag `0x0001010D` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.write_quote` (`0x0001010C`);
 * see the page-allocation scheme in the module head.
 *
 * This is the FOURTH and FINAL FSM cap in the oddjobz canon — after
 * D-O4.followup-4 lands all 4 oddjobz FSMs are brain-side.
 */
export const capReadInvoices: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_invoices',
  domainFlag: 0x0001_010d,
  description:
    'Authorises read-only enumeration of Invoice cells across all ' +
    'Invoice FSM states.  Held by the operator root cert; delegated ' +
    'to phone child certs by default via the D-O5p pairing allowlist.  ' +
    'Required by the Semantos Brain dispatcher\'s typed `invoices.find`, ' +
    '`invoices.find_by_id`, and `invoices.transition` resource ' +
    'commands.  Read-only at the cap-mint layer — Invoice FSM ' +
    'transitions themselves are ungated per the §O4 canon (gating is ' +
    'delegated to the parent Job FSM).',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `invoices` resource for the ' +
    'read + transition commands; not consumed by any Invoice FSM ' +
    'transition (every Invoice row is ungated today).',
  gates: ['(read-only — gates the invoices resource, not an FSM row)'],
  holder: 'operator-root',
});

/* ── D-O4.followup-4 — write_invoice ──
 *
 * The brain dispatcher's typed `invoices.create` cmd gates on this cap.
 * Held by the operator-root cert and delegated to phone child certs by
 * default via the D-O5p pairing allowlist — operators draft invoices
 * from any device they paired into.
 *
 * Domain flag `0x0001010E` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_invoices` (`0x0001010D`).
 *
 * Note: `cap.oddjobz.invoice` (`0x00010104`) is the §O3 canonical cap
 * spent on the parent Job FSM's `completed → invoiced` transition
 * (which mints the Invoice cell in `draft` state).  This
 * `write_invoice` cap is the read-side mirror — the dispatcher gate
 * that permits an operator (or paired device) to create an Invoice
 * record in the helm-side store.  The two caps coexist by design;
 * the §O3 cap drives the cell-DAG mint, this cap drives the
 * dispatcher-resource create cmd.
 */
export const capWriteInvoice: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_invoice',
  domainFlag: 0x0001_010e,
  description:
    'Authorises Invoice create writes against the oddjobz substrate.  ' +
    'Held by the operator root cert; delegated to phone child certs ' +
    'by default via the D-O5p pairing allowlist.  Required by the Semantos Brain ' +
    'dispatcher\'s typed `invoices.create` resource cmd.  Write-only ' +
    '— enumeration gates on `cap.oddjobz.read_invoices`.',
  roleInFsm:
    'Spent on Invoice create transitions — the genesis path for an ' +
    'oddjobz.invoice.v1 LINEAR cell tied to a parent Job (FK to the ' +
    'Job cell).',
  gates: ['∅ → invoice.draft'],
  holder: 'operator-root',
});

/* ── D-O5m.followup-8 substrate — read_attachments ──
 *
 * The brain dispatcher's typed `attachments` resource gates
 * `attachments.find` and `attachments.find_by_id` on this cap
 * (`runtime/semantos-brain/src/resources/attachments_handler.zig`).  Held by the
 * operator-root cert and delegated to phone child certs by default
 * via the D-O5p pairing allowlist — operators read their own visit
 * attachments from any device they paired into.
 *
 * Read-only by design: the cap permits enumerating Attachment cells
 * (metadata records — the binary blob sits separately via the upload
 * channel that ships in the next PR) but does NOT permit creating
 * them (those gate on `cap.oddjobz.write_attachment`).  Mirrors the
 * read/write split established for jobs/customers/visits/quotes/
 * invoices.
 *
 * Domain flag `0x0001010F` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.write_invoice` (`0x0001010E`).
 */
export const capReadAttachments: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.read_attachments',
  domainFlag: 0x0001_010f,
  description:
    'Authorises read-only enumeration of Attachment metadata cells.  ' +
    'Held by the operator root cert; delegated to phone child certs ' +
    'by default via the D-O5p pairing allowlist.  Required by the Semantos Brain ' +
    'dispatcher\'s typed `attachments.find` and `attachments.find_by_id` ' +
    'resource commands.  Read-only — does NOT permit creating an ' +
    'Attachment cell (that gates on `cap.oddjobz.write_attachment`).',
  roleInFsm:
    'Presented at the Semantos Brain dispatcher\'s `attachments` resource for ' +
    'the read commands; not consumed by any FSM transition (the ' +
    'Attachment cell is AFFINE-ish — write-once, no transitions).',
  gates: ['(read-only — not an FSM transition)'],
  holder: 'operator-root',
});

/* ── D-O5m.followup-8 substrate — write_attachment ──
 *
 * The brain dispatcher's typed `attachments.create_metadata` cmd gates
 * on this cap.  Held by the operator-root cert and delegated to phone
 * child certs by default via the D-O5p pairing allowlist — operators
 * (and the device child certs they paired in) capture artifacts at
 * the visit site from the phone.
 *
 * Domain flag `0x00010110` is the next slot on the canonical
 * `0x000101xx` page after `cap.oddjobz.read_attachments` (`0x0001010F`).
 *
 * Note: this cap gates only the metadata-cell create.  The binary
 * blob upload is a separate concern — handled in the next PR via a
 * multipart HTTP endpoint (and a subsequent cap if access control
 * needs to differ).
 */
export const capWriteAttachment: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_attachment',
  domainFlag: 0x0001_0110,
  description:
    'Authorises Attachment metadata create writes against the oddjobz ' +
    'substrate.  Held by the operator root cert; delegated to phone ' +
    'child certs by default via the D-O5p pairing allowlist (operators ' +
    'capture artifacts at the visit site from the phone).  Required by ' +
    'the Semantos Brain dispatcher\'s typed `attachments.create_metadata` resource ' +
    'cmd.  Write-only — enumeration gates on ' +
    '`cap.oddjobz.read_attachments`.  The cap gates ONLY the metadata ' +
    'cell; the binary blob upload is a separate concern in the next PR.',
  roleInFsm:
    'Spent on Attachment metadata create — the genesis path for an ' +
    'oddjobz.attachment.v1 LINEAR cell tied to a parent Visit (FK to ' +
    'the Visit cell).',
  gates: ['∅ → attachment.created'],
  holder: 'operator-root',
});

/**
 * DECISION-A5 / A5.P2 — `cap.oddjobz.write_policy`.
 *
 * Authorises the operator-config `set_pricing_policy` mutating walker:
 * mint / amendment-chain successor of an `oddjobz.pricing_policy.v1`
 * cell (PERSISTENT, wire RELEVANT — accumulate, never consumed). The
 * Ricardian amendment history is the app-layer `version` /
 * `prevPolicyHash` / `signedByOperatorId` envelope; this cap is the
 * kernel-gate guarding who may append a new revision.
 *
 * Operator-root-held and delegated to operator child certs by the
 * D-O5p pairing allowlist — pricing is per-operator context, edited
 * from the field-app helm under the operator hat (the
 * `cap.oddjobz.write_customer` context-tag scheme, the
 * `lead.ratifiedBy` precedent). NOT a config-endpoint write (per
 * SHELL-CARTRIDGES-HATS.md) — it flows as a config-intent walked
 * under this cap. Next free domain flag after
 * `cap.oddjobz.write_attachment` (0x0001_0110).
 */
export const capWritePolicy: OddjobzCapability = defineCapability({
  name: 'cap.oddjobz.write_policy',
  domainFlag: 0x0001_0111,
  description:
    'Authorises operator pricing-policy config writes against the ' +
    'oddjobz substrate — the `set_pricing_policy` mutating walker that ' +
    'mints / amendment-chains an oddjobz.pricing_policy.v1 cell ' +
    '(PERSISTENT / wire RELEVANT). Held by the operator root cert; ' +
    'delegated to operator child certs via the D-O5p pairing ' +
    'allowlist (the operator tunes pricing from the field-app helm ' +
    'under the operator hat). Append-only: each revision is a new ' +
    'signed cell chained via version/prevPolicyHash; the kernel ' +
    'linearity (RELEVANT) governs that the cell is never consumed.',
  roleInFsm:
    'Spent on a pricing-policy genesis or amendment append — the ' +
    'config-intent path for an oddjobz.pricing_policy.v1 cell under ' +
    'the operator hat. Not a §O2 entity FSM transition; operator ' +
    'CONFIG, observed by Pask, interpreted+tuned by an edge agent.',
  gates: ['∅ → pricing_policy.minted', 'pricing_policy → pricing_policy.amended'],
  holder: 'operator-root',
});

/* ══════════════════════════════════════════════════════════════════════
 * Registry
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The sixteen caps in canonical declaration order — §O3 plan table
 * verbatim, then the D-O5.followup-1 read-only `cap.oddjobz.read_jobs`,
 * then the D-O5.followup-3 read-only `cap.oddjobz.read_customers`,
 * then the D-O4.followup-2 `cap.oddjobz.read_visits` +
 * `cap.oddjobz.write_visit` pair (Visit FSM cutover slice), then the
 * D-O4.followup-3 `cap.oddjobz.read_quotes` + `cap.oddjobz.write_quote`
 * pair (Quote FSM cutover slice), then the D-O4.followup-4
 * `cap.oddjobz.read_invoices` + `cap.oddjobz.write_invoice` pair
 * (Invoice FSM cutover slice — closed the Semantos Brain-side cutover of all 4
 * oddjobz FSMs), then the D-O5m.followup-8 substrate
 * `cap.oddjobz.read_attachments` + `cap.oddjobz.write_attachment`
 * pair (mobile sensor-capture substrate; mobile camera capture +
 * blob upload land in the subsequent PR), each appended at the end
 * so existing pre-followup fixtures (which iterate the first
 * six/seven/eight/ten/twelve/fourteen in order) keep their byte-
 * identical shape.  Tests, conformance vectors, glossary entries,
 * the Semantos Brain manifest, and the operator-root cert mint all iterate
 * this array.
 */
export const ODDJOBZ_CAPABILITIES: readonly OddjobzCapability[] = Object.freeze([
  capWriteCustomer,
  capQuote,
  capDispatch,
  capInvoice,
  capClose,
  capPublicChatServe,
  capReadJobs,
  capReadCustomers,
  capReadVisits,
  capWriteVisit,
  capReadQuotes,
  capWriteQuote,
  capReadInvoices,
  capWriteInvoice,
  capReadAttachments,
  capWriteAttachment,
  capWritePolicy,
]);

/** Lookup by canonical cap name. */
export const capabilityByName: Readonly<Record<OddjobzCapName, OddjobzCapability>> =
  Object.freeze(
    Object.fromEntries(
      ODDJOBZ_CAPABILITIES.map((c) => [c.name, c]),
    ) as Record<OddjobzCapName, OddjobzCapability>,
  );

/** Lookup by domain flag. */
export const capabilityByDomainFlag: Readonly<Record<number, OddjobzCapability>> =
  Object.freeze(
    Object.fromEntries(
      ODDJOBZ_CAPABILITIES.map((c) => [c.domainFlag, c]),
    ) as Record<number, OddjobzCapability>,
  );

/** All operator-root-held caps (delegated to child certs per D-O5p). */
export const OPERATOR_ROOT_CAPS: readonly OddjobzCapability[] = Object.freeze(
  ODDJOBZ_CAPABILITIES.filter((c) => c.holder === 'operator-root'),
);

/** All node-service-held caps. */
export const NODE_SERVICE_CAPS: readonly OddjobzCapability[] = Object.freeze(
  ODDJOBZ_CAPABILITIES.filter((c) => c.holder === 'node-service'),
);

/* ══════════════════════════════════════════════════════════════════════
 * Cell-mint payload — the on-chain side of the cap UTXO
 *
 * The §O4 enforcement story is structural:
 *
 *   1. Operator hat holds a cap UTXO (cell with domain_flag = X).
 *   2. FSM transition pushes (cell, X) onto the 2-PDA and runs
 *      OP_CHECKDOMAINFLAG (0xC6).
 *   3. Kernel reads cell.header.domainFlag at byte offset 24 and
 *      compares against X. Mismatch → kernel-gate failure (K3a per
 *      proofs/lean/Semantos/Theorems/DomainIsolationK3.lean).
 *
 * The function below builds the 1024-byte cell that step 1 holds. Cell
 * layout matches `core/cell-engine/src/constants.zig` lines 8/63-78
 * exactly (HEADER_SIZE = 256, PAYLOAD_SIZE = 768, CELL_SIZE = 1024,
 * with header offsets MAGIC=0, LINEARITY=16, VERSION=20, FLAGS=24,
 * REF_COUNT=28, TYPE_HASH=30, OWNER_ID=62).
 *
 * The §2.5 isolation invariant is encoded by writing the BKDS context
 * tag into the header. Two cap UTXOs with the same name + same
 * domain_flag but different context tags carry structurally different
 * cell bytes — and the kernel-gate's OP_CHECKDOMAINFLAG check passes
 * only if the spend-side flag matches; the context-tag check is the
 * dispatcher's, performed by deriving the active-hat key from the
 * stored context tag (per protocol-v0.5 §4.4 + identity_certs §2.5).
 *
 * Cell-engine constants from `core/cell-engine/src/constants.zig`:
 *   CELL_SIZE   = 1024
 *   HEADER_SIZE = 256
 *   PAYLOAD_SIZE = 768
 *   MAGIC_1..4  = 0xDEADBEEF, 0xCAFEBABE, 0x13371337, 0x42424242
 *   VERSION     = 1
 *   HEADER_OFFSET_LINEARITY = 16  (uint32 LE; LINEAR=1, AFFINE=2,
 *                                  RELEVANT=3, DEBUG=4)
 *   HEADER_OFFSET_VERSION   = 20
 *   HEADER_OFFSET_FLAGS     = 24
 *   HEADER_OFFSET_REF_COUNT = 28  (uint16 LE)
 *   HEADER_OFFSET_TYPE_HASH = 30  (32 bytes)
 *   HEADER_OFFSET_OWNER_ID  = 62  (16 bytes)
 *   HEADER_OFFSET_TIMESTAMP = 78  (uint64 LE)
 *
 * Capability cells are LINEAR per protocol-v0.5 §5.1 (the spend IS
 * the consumption proof; OP_ASSERTLINEAR + OP_CHECKDOMAINFLAG fire in
 * sequence at the §O4 gate). They sit at wire code 1.
 *
 * The context-tag byte is written into the OWNER_ID block at offset
 * 62 (first byte of the 16-byte block) — same byte the dispatcher's
 * cert-chain look-up keys on. This keeps the §2.5 isolation invariant
 * structurally visible in the cell bytes (a context-tag swap reshapes
 * the OWNER_ID and therefore the cell hash).
 * ══════════════════════════════════════════════════════════════════════ */

export const CELL_SIZE = 1024;
export const HEADER_SIZE = 256;
export const PAYLOAD_SIZE = 768;

const HEADER_OFFSET_MAGIC = 0;
const HEADER_OFFSET_LINEARITY = 16;
const HEADER_OFFSET_VERSION = 20;
const HEADER_OFFSET_FLAGS = 24;
const HEADER_OFFSET_REF_COUNT = 28;
const HEADER_OFFSET_TYPE_HASH = 30;
const HEADER_OFFSET_OWNER_ID = 62;

const MAGIC_1 = 0xdeadbeef;
const MAGIC_2 = 0xcafebabe;
const MAGIC_3 = 0x13371337;
const MAGIC_4 = 0x42424242;

const VERSION = 1;

/** Capability cells are LINEAR — the spend is the consumption proof. */
const CAP_WIRE_LINEARITY: WireLinearityCode = WireLinearity.LINEAR;

/**
 * Type hash of an oddjobz capability cell — common to all six caps;
 * what differs is the domain flag in the header. Matches the
 * `whatPath:howSlug:instPath` shape used by the §O2 cell-types.
 */
const CAP_TYPE_HASH_INPUT = {
  whatPath: 'oddjobz.capability',
  howSlug: 'capability-mint',
  instPath: 'inst.capability.cap-token',
} as const;

export const ODDJOBZ_CAP_TYPE_HASH: Uint8Array = computeTypeHash(CAP_TYPE_HASH_INPUT);
export const ODDJOBZ_CAP_TYPE_HASH_HEX: string = typeHashHex(ODDJOBZ_CAP_TYPE_HASH);

/**
 * Validate a 16-byte ownerId. The `OWNER_ID` block at header offset 62
 * is a 16-byte buffer per `core/cell-engine/src/constants.zig`. We
 * accept arbitrary 16-byte buffers; the convention is the operator
 * root cert id's first 16 bytes for operator-held caps and the
 * node-service principal id for service caps. The first byte of the
 * block is reserved for the BKDS context tag (§2.5) — see below.
 */
function assertOwnerId(ownerId: Uint8Array): void {
  if (!(ownerId instanceof Uint8Array)) {
    throw new TypeError('mintCapabilityCell: ownerId must be Uint8Array');
  }
  if (ownerId.length !== 16) {
    throw new RangeError(
      `mintCapabilityCell: ownerId must be 16 bytes (got ${ownerId.length})`,
    );
  }
}

/**
 * Validate a BKDS context tag — single byte per protocol-v0.5 §4.4
 * (identity DAG context isolation). Carpenter = 0x10, musician = 0x11,
 * etc. The brain may use 0x00 for "no specific hat / root context".
 */
function assertContextTag(contextTag: number): void {
  if (
    !Number.isInteger(contextTag) ||
    contextTag < 0 ||
    contextTag > 0xff
  ) {
    throw new RangeError(
      `mintCapabilityCell: contextTag must be uint8 (got ${contextTag})`,
    );
  }
}

/**
 * Build the canonical 1024-byte cap-UTXO cell bytes for `cap` under the
 * given `contextTag` and `ownerId`.
 *
 * The byte layout is verbatim per `core/cell-engine/src/constants.zig`:
 *
 *     [0..16]    magic (DEADBEEF CAFEBABE 13371337 42424242, LE)
 *     [16..20]   linearity = 1 (LINEAR), uint32 LE
 *     [20..24]   version = 1, uint32 LE
 *     [24..28]   domain_flag = cap.domainFlag, uint32 LE
 *     [28..30]   ref_count = 0, uint16 LE
 *     [30..62]   type_hash = ODDJOBZ_CAP_TYPE_HASH (32 bytes)
 *     [62..78]   owner_id (16 bytes; byte 0 is contextTag, bytes 1..16
 *                are caller-supplied)
 *     [78..256]  zero-padded reserved / binding region
 *     [256..]    payload = canonical-JSON encoding of
 *                {capName, contextTag, ownerIdHex, domainFlag,
 *                 holder, mintedAt: 0}, padded with zeros to 1024.
 *
 * `mintedAt` is **always 0** in the canonical mint payload — the
 * §O3 acceptance criteria require mint-time-determinism, so we don't
 * stamp the wall clock into the bytes. The brain's audit log records
 * the actual mint time separately via the dispatcher's audit pair.
 *
 * Returns a fresh `Uint8Array(1024)`.
 */
export function mintCapabilityCell(
  cap: OddjobzCapability,
  contextTag: number,
  ownerId: Uint8Array,
): Uint8Array {
  assertContextTag(contextTag);
  assertOwnerId(ownerId);

  const cell = new Uint8Array(CELL_SIZE);
  const view = new DataView(cell.buffer);

  // Magic bytes
  view.setUint32(HEADER_OFFSET_MAGIC + 0, MAGIC_1, true);
  view.setUint32(HEADER_OFFSET_MAGIC + 4, MAGIC_2, true);
  view.setUint32(HEADER_OFFSET_MAGIC + 8, MAGIC_3, true);
  view.setUint32(HEADER_OFFSET_MAGIC + 12, MAGIC_4, true);

  // Linearity (LINEAR = 1)
  view.setUint32(HEADER_OFFSET_LINEARITY, CAP_WIRE_LINEARITY, true);

  // Version
  view.setUint32(HEADER_OFFSET_VERSION, VERSION, true);

  // Domain flag — the §O4 gate's check value
  view.setUint32(HEADER_OFFSET_FLAGS, cap.domainFlag >>> 0, true);

  // Reference count
  view.setUint16(HEADER_OFFSET_REF_COUNT, 0, true);

  // Type hash (32 bytes)
  cell.set(ODDJOBZ_CAP_TYPE_HASH, HEADER_OFFSET_TYPE_HASH);

  // Owner ID — byte 0 = context tag, bytes 1..16 = caller-supplied
  cell[HEADER_OFFSET_OWNER_ID] = contextTag & 0xff;
  cell.set(ownerId.subarray(1, 16), HEADER_OFFSET_OWNER_ID + 1);

  // Payload — canonical JSON of the cap manifest, zero-padded
  const ownerIdHex = bytesToHex(ownerId);
  const payloadJson = encodeCanonicalJson({
    capName: cap.name,
    contextTag,
    ownerIdHex,
    domainFlag: cap.domainFlag,
    holder: cap.holder,
    mintedAt: 0, // mint-time-deterministic
  });
  if (payloadJson.length > PAYLOAD_SIZE) {
    throw new RangeError(
      `mintCapabilityCell: payload too large (${payloadJson.length} > ${PAYLOAD_SIZE})`,
    );
  }
  cell.set(payloadJson, HEADER_SIZE);

  return cell;
}

/**
 * Decode the canonical-JSON payload of a cap-UTXO cell — used by the
 * conformance round-trip tests. Strict: rejects cells whose magic /
 * linearity / version / type-hash do not match the §O3 mint shape.
 */
export interface DecodedCapabilityCell {
  readonly capName: string;
  readonly contextTag: number;
  readonly ownerIdHex: string;
  readonly domainFlag: number;
  readonly holder: CapHolder;
  readonly mintedAt: number;
}

export function decodeCapabilityCell(cell: Uint8Array): DecodedCapabilityCell {
  if (cell.length !== CELL_SIZE) {
    throw new RangeError(
      `decodeCapabilityCell: bad cell size (${cell.length} != ${CELL_SIZE})`,
    );
  }
  const view = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
  const m1 = view.getUint32(HEADER_OFFSET_MAGIC + 0, true);
  const m2 = view.getUint32(HEADER_OFFSET_MAGIC + 4, true);
  const m3 = view.getUint32(HEADER_OFFSET_MAGIC + 8, true);
  const m4 = view.getUint32(HEADER_OFFSET_MAGIC + 12, true);
  if (m1 !== MAGIC_1 || m2 !== MAGIC_2 || m3 !== MAGIC_3 || m4 !== MAGIC_4) {
    throw new Error('decodeCapabilityCell: magic bytes mismatch');
  }
  const linearity = view.getUint32(HEADER_OFFSET_LINEARITY, true);
  if (linearity !== CAP_WIRE_LINEARITY) {
    throw new Error(
      `decodeCapabilityCell: bad linearity (${linearity} != ${CAP_WIRE_LINEARITY})`,
    );
  }
  const version = view.getUint32(HEADER_OFFSET_VERSION, true);
  if (version !== VERSION) {
    throw new Error(`decodeCapabilityCell: bad version (${version} != ${VERSION})`);
  }
  // Type hash bytes
  for (let i = 0; i < 32; i++) {
    if (cell[HEADER_OFFSET_TYPE_HASH + i] !== ODDJOBZ_CAP_TYPE_HASH[i]) {
      throw new Error('decodeCapabilityCell: type-hash mismatch');
    }
  }
  // Decode payload — first run-length of canonical JSON terminated by 0x00
  let end = HEADER_SIZE;
  while (end < CELL_SIZE && cell[end] !== 0) end++;
  const payloadBytes = cell.subarray(HEADER_SIZE, end);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(payloadBytes);
  const parsed = JSON.parse(text) as Record<string, unknown>;
  if (
    typeof parsed.capName !== 'string' ||
    typeof parsed.contextTag !== 'number' ||
    typeof parsed.ownerIdHex !== 'string' ||
    typeof parsed.domainFlag !== 'number' ||
    (parsed.holder !== 'operator-root' && parsed.holder !== 'node-service') ||
    typeof parsed.mintedAt !== 'number'
  ) {
    throw new Error('decodeCapabilityCell: payload schema mismatch');
  }
  return {
    capName: parsed.capName,
    contextTag: parsed.contextTag,
    ownerIdHex: parsed.ownerIdHex,
    domainFlag: parsed.domainFlag,
    holder: parsed.holder,
    mintedAt: parsed.mintedAt,
  };
}

/**
 * Read the domain flag from a cap-UTXO cell at header offset 24
 * (uint32 LE) — the value `OP_CHECKDOMAINFLAG` reads at the kernel
 * gate per `core/cell-engine/src/linearity.zig:getDomainFlag`.
 */
export function readDomainFlag(cell: Uint8Array): number {
  if (cell.length < HEADER_OFFSET_FLAGS + 4) {
    throw new RangeError('readDomainFlag: cell too short');
  }
  const view = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
  return view.getUint32(HEADER_OFFSET_FLAGS, true);
}

/**
 * Read the context tag from a cap-UTXO cell — first byte of the
 * OWNER_ID block at offset 62. Used by tests to verify §2.5 isolation
 * is structurally encoded.
 */
export function readContextTag(cell: Uint8Array): number {
  if (cell.length < HEADER_OFFSET_OWNER_ID + 1) {
    throw new RangeError('readContextTag: cell too short');
  }
  return cell[HEADER_OFFSET_OWNER_ID] as number;
}

/**
 * Pure-function model of OP_CHECKDOMAINFLAG (`core/cell-engine/src/
 * opcodes/plexus.zig:opCheckDomainFlag`) — peek `[cell, expectedFlag]`,
 * read cell.header.domainFlag at offset 24, compare. Returns true on
 * match (kernel gate would push TRUE), false otherwise (kernel gate
 * would return domain_flag_mismatch).
 *
 * This is a pure model — it doesn't drive the actual Zig PDA — but
 * the K3 tests (DomainIsolationK3.lean) prove the Zig opcode behaves
 * exactly this way, so the model is faithful at the operational
 * altitude this PR cares about.
 */
export function opCheckDomainFlag(
  cell: Uint8Array,
  expectedFlag: number,
): boolean {
  const actualFlag = readDomainFlag(cell);
  return (actualFlag >>> 0) === (expectedFlag >>> 0);
}

/* ══════════════════════════════════════════════════════════════════════
 * Recovery payload — §9.4 acceptance gate
 *
 * The acceptance gate in `ODDJOBZ-EXTENSION-PLAN.md` §9.4 requires the
 * cap set survive recovery encode/decode bytewise. The shape mirrors
 * the existing recovery payload pattern (encrypt-under-root-seed,
 * length-prefixed concatenation, decode+decrypt back to bytes).
 *
 * For this PR we ship a deterministic, schema-light recovery wrapper:
 *
 *   payload = sha256(rootSeed || "oddjobz-cap-recovery-v1")[0..32]
 *             XOR
 *             concat(canonicalJson({caps: [{name, domainFlag, holder,
 *                                            cell: hex(...)}]}))
 *
 * The XOR step is the encrypt-under-root-seed primitive. It's a
 * placeholder shape for the real recovery flow (D-O5p / recovery-
 * extension territory), but it satisfies §9.4: encode → decode round-
 * trips byte-identically given the same root seed, and the bytes are
 * the cap set verbatim.
 *
 * NOT a security primitive on its own — the real recovery extension
 * uses authenticated encryption per `extensions/recovery/` (AES-GCM
 * with a key derived from rootSeed via BIP-32). This module is the
 * shape on the oddjobz side, not the crypto on the substrate side.
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Build the recovery payload for the canonical cap set under the
 * operator's root seed. Deterministic — same `rootSeed` + same
 * `contextTag` + same `ownerId` always produces the same bytes.
 */
export function encodeRecoveryPayload(
  rootSeed: Uint8Array,
  contextTag: number,
  ownerId: Uint8Array,
): Uint8Array {
  if (!(rootSeed instanceof Uint8Array) || rootSeed.length === 0) {
    throw new TypeError('encodeRecoveryPayload: rootSeed must be Uint8Array');
  }
  assertContextTag(contextTag);
  assertOwnerId(ownerId);

  const caps = ODDJOBZ_CAPABILITIES.map((c) => {
    const cell = mintCapabilityCell(c, contextTag, ownerId);
    return {
      name: c.name,
      domainFlag: c.domainFlag,
      holder: c.holder,
      cellHex: bytesToHex(cell),
    };
  });
  const plaintext = encodeCanonicalJson({
    v: 1,
    contextTag,
    ownerIdHex: bytesToHex(ownerId),
    caps,
  });
  return xorWithStreamKey(plaintext, rootSeed);
}

/**
 * Inverse of {@link encodeRecoveryPayload}. Given the same
 * `rootSeed`, decodes back to the canonical cap-set bytes.
 */
export interface RecoveredCapSet {
  readonly v: number;
  readonly contextTag: number;
  readonly ownerIdHex: string;
  readonly caps: ReadonlyArray<{
    readonly name: string;
    readonly domainFlag: number;
    readonly holder: CapHolder;
    readonly cellHex: string;
  }>;
}

export function decodeRecoveryPayload(
  ciphertext: Uint8Array,
  rootSeed: Uint8Array,
): RecoveredCapSet {
  const plaintext = xorWithStreamKey(ciphertext, rootSeed);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(plaintext);
  const parsed = JSON.parse(text) as RecoveredCapSet;
  return parsed;
}

function xorWithStreamKey(input: Uint8Array, rootSeed: Uint8Array): Uint8Array {
  const out = new Uint8Array(input.length);
  // Stream key = repeated sha256 chain seeded by rootSeed||domain.
  const tag = new TextEncoder().encode('oddjobz-cap-recovery-v1');
  let counter = 0;
  let block = nextBlock(rootSeed, tag, counter);
  let blockOff = 0;
  for (let i = 0; i < input.length; i++) {
    if (blockOff === 32) {
      counter++;
      block = nextBlock(rootSeed, tag, counter);
      blockOff = 0;
    }
    out[i] = ((input[i] as number) ^ (block[blockOff] as number)) & 0xff;
    blockOff++;
  }
  return out;
}

function nextBlock(rootSeed: Uint8Array, tag: Uint8Array, counter: number): Uint8Array {
  const counterBytes = new Uint8Array(4);
  new DataView(counterBytes.buffer).setUint32(0, counter >>> 0, true);
  const h = createHash('sha256');
  h.update(rootSeed);
  h.update(tag);
  h.update(counterBytes);
  return new Uint8Array(h.digest());
}

/* ══════════════════════════════════════════════════════════════════════
 * Helpers
 * ══════════════════════════════════════════════════════════════════════ */

export function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (let i = 0; i < b.length; i++) {
    out += (b[i] as number).toString(16).padStart(2, '0');
  }
  return out;
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/, '');
  if (clean.length % 2 !== 0) throw new Error(`odd-length hex string: ${hex}`);
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) throw new Error(`invalid hex byte at ${i}: ${hex}`);
    out[i] = byte;
  }
  return out;
}

```
