---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/customer-dedupe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.127828+00:00
---

# runtime/legacy-ingest/src/customer-dedupe.ts

```ts
/**
 * Customer dedupe — companion to `site-dedupe.ts` + `job-dedupe.ts`.
 *
 * Reference: docs/design/ODDJOBZ-CANONICALIZATION-HANDOFF.md §6.2
 *            (idempotent ingest); tools/oddjobz-canonicalize/canonicalize.py
 *            `ckey` (the offline canonicalizer's customer clustering key).
 *
 * Why this exists:
 *
 *   Customer cells bake `linked_site_id` into the payload, so the SAME
 *   person at N sites was minted N times — one Clever-Property agent
 *   across 130 sites, RJR ×13. The 2026-06-10 canonicalization pass
 *   collapsed 1214 customer cells → 152 on exactly this observation.
 *   But the ingest worker's `mintCustomer` always minted, so the 152
 *   would creep back toward 1214 on the next Gmail/PDF pass.
 *
 *   This module derives a stable, role-aware NATURAL KEY so duplicate
 *   contacts resolve to ONE customer cell. The keys mirror
 *   canonicalize.py's `ckey` exactly, so the live ingest dedupe and the
 *   offline canonicalizer agree on what "the same customer" means:
 *
 *     agent / property_manager → person:<email or name>   (ONE person
 *                                across ALL sites — site-INDEPENDENT,
 *                                because an agency contact recurs at
 *                                every property they manage)
 *     site_owner (landlord)    → landlord:<name>           (by name)
 *     everyone else            → <role>:<name>|<canonical-site-ref>
 *                                (a tenant is identity-bound to ONE site)
 *
 * Field normalisation mirrors canonicalize.py's `norm`: lowercase, trim,
 * collapse internal whitespace.
 *
 * Like jobs, a contact with no usable key (no name AND, for a person,
 * no email) yields the defensive `unkeyed:` sentinel — never deduped, so
 * a stray anonymous contact mints fresh rather than collapsing every
 * nameless contact onto one cell.
 */

import { createHash } from 'node:crypto';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Caller-supplied lookup against the brain's (or receipt-store's) view
 * of already-minted customers.
 *
 * V1 wirings:
 *   • Receipt-backed live index — built from the worker's per-run
 *     customer (lookupKey → cellId) receipts, seeded from prior runs and
 *     kept current within a run (the reingest verb wires this).
 *   • Brain-backed — a future `customer.lookup` brain verb, injected the
 *     way `SitesView` is, to dedupe against the authoritative 152.
 *   • In-memory — used by customer-dedupe.test.ts.
 */
export interface CustomersDedupeView {
  /**
   * Returns the existing customer_cell_id (lowercase 64-char hex) for
   * the given `lookupKey`, or `null` if no customer matches.
   */
  findCustomerByLookupKey(lookupKey: string): Promise<string | null>;
}

export interface CustomerProposal {
  kind: 'propose';
  /**
   * Deterministic 64-char hex id, a stable function of the dedupe key
   * only. NOTE: the reingest worker does NOT use this as the real cell
   * id — customer cells are content-addressed by the brain's
   * `entity.encode` (the dispatcher returns the authoritative id). It is
   * kept for parity with `job-dedupe`'s `proposeJobCell` + testability.
   */
  proposedCellId: string;
  /** The dedupe index entry. */
  lookupKey: string;
}

export interface CustomerMatch {
  kind: 'match';
  cellId: string;
  lookupKey: string;
}

export type CustomerDedupeResult = CustomerMatch | CustomerProposal;

export interface CustomerIdentityArgs {
  /**
   * The contact's resolved role (post `mapLegacyRole`): `site_owner |
   * tenant | property_manager | agent | contractor | witness | unknown`.
   * `agent`/`property_manager` key site-independently; `site_owner` keys
   * by name; everyone else keys by name + canonical site.
   */
  readonly role: string;
  /** Contact full name, or null. */
  readonly name: string | null | undefined;
  /** Contact email, or null. Only consulted for the `person:` roles. */
  readonly email: string | null | undefined;
  /**
   * The CANONICAL site cell id this contact is attached to (lowercase
   * 64-char hex), or null. The reingest worker resolves the site FIRST
   * (site-dedupe), so this is already the survivor site — matching
   * canonicalize.py's `canon_site`.
   */
  readonly siteRef: string | null;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Derive the stable, role-aware customer dedupe key. Mirrors
 * canonicalize.py's `ckey` so live ingest and the offline canonicalizer
 * agree.
 *
 *   agent | property_manager → `person:<email or name>`
 *   site_owner               → `landlord:<name>`
 *   else                     → `<role>:<name>|<siteRef-or-empty>`
 *   no usable key            → `unkeyed:` (defensive; never deduped)
 */
export function deriveCustomerLookupKey(args: CustomerIdentityArgs): string {
  const role = normaliseCustomerField(args.role);
  const name = normaliseCustomerField(args.name);
  const email = normaliseCustomerField(args.email);

  if (role === 'agent' || role === 'property_manager') {
    // ONE person across all sites — keyed by email (strongest) else name.
    const ident = email.length > 0 ? email : name;
    if (ident.length === 0) return 'unkeyed:';
    return `person:${ident}`;
  }

  if (role === 'site_owner') {
    if (name.length === 0) return 'unkeyed:';
    return `landlord:${name}`;
  }

  // tenant / contractor / witness / unknown / other — identity-bound to
  // one site. `role or "other"` matches canonicalize.py for empty roles.
  if (name.length === 0) return 'unkeyed:';
  const r = role.length > 0 ? role : 'other';
  return `${r}:${name}|${args.siteRef ?? ''}`;
}

/**
 * Pure-function half: derive the lookup key + the deterministic proposed
 * cell id. No storage IO.
 */
export function proposeCustomerCell(args: CustomerIdentityArgs): CustomerProposal {
  const lookupKey = deriveCustomerLookupKey(args);
  return {
    kind: 'propose',
    proposedCellId: computeCustomerCellId(lookupKey),
    lookupKey,
  };
}

/**
 * Composed entry point: derive key → query the view → branch. `match`
 * means an existing customer_cell already represents this person (reuse
 * its id, don't mint a duplicate); `propose` means net-new.
 *
 * `unkeyed:` contacts are never matched — they always return `propose`
 * because we can't confidently say two nameless contacts are the same
 * person.
 */
export async function findOrProposeCustomer(
  args: CustomerIdentityArgs,
  view: CustomersDedupeView,
): Promise<CustomerDedupeResult> {
  const proposal = proposeCustomerCell(args);
  if (proposal.lookupKey === 'unkeyed:') return proposal;
  const existing = await view.findCustomerByLookupKey(proposal.lookupKey);
  if (existing !== null) {
    return { kind: 'match', cellId: existing, lookupKey: proposal.lookupKey };
  }
  return proposal;
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals (exported for parity-oracle testing)
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Reingest-namespaced customer cell id formula. Stable function of the
 * dedupe key only.
 */
export function computeCustomerCellId(lookupKey: string): string {
  const h = createHash('sha256');
  h.update('reingest.customer.v1|', 'utf8');
  h.update(lookupKey, 'utf8');
  return h.digest('hex');
}

/**
 * Mirror canonicalize.py's `norm`: lowercase, trim, collapse internal
 * whitespace runs to a single space.
 */
export function normaliseCustomerField(raw: string | null | undefined): string {
  if (raw === null || raw === undefined) return '';
  return raw.trim().toLowerCase().replace(/\s+/g, ' ');
}

```
