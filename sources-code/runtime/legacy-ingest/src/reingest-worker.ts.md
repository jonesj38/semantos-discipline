---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/reingest-worker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.134503+00:00
---

# runtime/legacy-ingest/src/reingest-worker.ts

```ts
/**
 * D-RTC.6 — Reingest worker.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.6.
 *
 * Composes D-RTC.1 (address-normalize + site-dedupe), D-RTC.2 (role
 * classifier — for legacy proposals that pre-date the broader-role
 * extractor schema we map via mapLegacyRole), D-RTC.4 (cell-encoder),
 * and D-RTC.5 (attachment-pipeline) into a per-email pipeline that
 * turns one extracted Proposal into a ratified graph of typed cells:
 *
 *   site → [customer, …] → job → [attachment, …]
 *
 * Each cell is encoded via brain's substrate_entity.encode through an
 * injected EncodeDispatcher seam (the brain-side `entity.encode` verb
 * registration lands in a separate brain-side carve commit).
 *
 * Idempotency + audit-log + cursor resumption: out of this commit's
 * scope. The PRD §D-RTC.6 acceptance gate is "1000-email dry-run
 * stable + ≥95% schema-conformant" — this module produces the
 * per-proposal compose; the operator-side CLI (D-RTC.7) does the
 * batch loop + receipt-store tracking.
 */

import type { Proposal, ProposalContact } from './extractor/types';
import {
  encodeSite,
  encodeCustomer,
  encodeJob,
  mapLegacyRole,
  type EntityEncodeRequest,
  type SiteCellPayload,
  type CustomerCellPayload,
  type JobCellPayload,
} from './cell-encoder';
import {
  proposeSiteCell,
  type SitesView,
  type SiteProposal,
} from './site-dedupe';
import {
  findOrProposeJob,
  type JobsDedupeView,
} from './job-dedupe';
import {
  findOrProposeCustomer,
  type CustomersDedupeView,
} from './customer-dedupe';
import {
  runAttachmentPipeline,
  type AttachmentBlobStore,
  type AttachmentParentSummary,
} from './attachment-pipeline';
import type { EmailMimePart } from './extractor/attachment';
import type { ContactRole } from './role-classifier';
import type { ReingestReceiptStore } from './reingest-receipt-store';

// ── Minimal inline type for the ConversationTurn submitted after reingest ──────
//
// We avoid a cross-package import by defining only the fields the reingest
// worker populates.  The full canonical shape lives in
// cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts;
// this subset is structurally compatible (a value of this type IS a valid
// OddjobzConversationTurnPayload with the optional fields absent).
export interface ReingestTurnPayload {
  readonly turnId: string;
  readonly conversationId: string;
  readonly entityRef?: { readonly kind: 'job' | 'site' | 'customer'; readonly cellHash: string };
  readonly participantRole: 'external' | 'agent' | 'operator' | 'unknown';
  readonly identityHandle?: { readonly kind: 'email' | 'phone' | 'free'; readonly value: string };
  readonly surface: 'email';
  readonly direction: 'inbound';
  readonly bodyText: string;
  readonly correlationId: string;
  readonly timestamp: number;
}

/**
 * Optional dep: write one canonical ConversationTurn per reingested job.
 * Called AFTER the job cell is minted with the minted jobCellId set as
 * entityRef.  Best-effort — a throw is logged and swallowed; it must NOT
 * fail the reingest outcome.
 *
 * Production: inject `makeOddjobzSinks(db).semObjectSink` (from
 * `cartridges/oddjobz/brain/src/conversation/db.ts`).  Tests inject a
 * recording stub.
 *
 * Architecture note (semantos_brain_single_threaded_reactor): this runs
 * at the CLI / worker-runner level (NOT inside the brain reactor), so
 * writing directly to Postgres via makeOddjobzSinks is safe — no
 * self-call deadlock.
 */
export type ReingestTurnSink = (turn: ReingestTurnPayload) => Promise<void> | void;

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Brain-dispatcher seam — sends one `entity.encode` request and
 * returns the 32-byte cell id (lowercase hex). Tests inject a
 * deterministic stub; production wires through brain-rpc.ts JSON-RPC.
 *
 * The dispatcher must not throw for routine drift — caller-level
 * resilience (retry, dead-letter) is the worker-runner's job. If
 * the brain genuinely rejects the cell (typehash mismatch, payload
 * overflow), the throw bubbles up and the worker abandons the
 * proposal with a structured error.
 */
export interface EncodeDispatcher {
  dispatch(req: EntityEncodeRequest): Promise<string>;
}

/** Result of reingesting one Proposal. */
export interface ReingestReceipt {
  /** The proposal we just reingested. */
  readonly proposalId: string;
  /** Site cell id — null if proposal had no extractable address. */
  readonly siteCellId: string | null;
  /** Whether the site was matched against an existing cell, or freshly minted. */
  readonly siteDisposition: 'matched' | 'minted' | 'absent';
  /** Customer cell ids in the order they appeared on the proposal. */
  readonly customerCellIds: readonly string[];
  /**
   * Customer dedupe keys, parallel-indexed with `customerCellIds` (§6.2).
   * `unkeyed:` for contacts with no usable natural key. The reingest verb
   * seeds its cross-run customer index from these (key → cellId).
   */
  readonly customerLookupKeys: readonly string[];
  /**
   * Per-contact disposition, parallel-indexed with `customerCellIds`:
   * `matched` = reused an existing customer_cell (dedupe hit); `minted`
   * = freshly encoded. Audit + the verb's `customersDeduped` tally.
   */
  readonly customerDispositions: readonly ('matched' | 'minted')[];
  /** Job cell id. */
  readonly jobCellId: string;
  /** Whether the job was matched to an existing cell, or freshly minted. */
  readonly jobDisposition: 'matched' | 'minted';
  /** The job dedupe key (wo:… / site:… / unkeyed:…) — audit + index. */
  readonly jobLookupKey: string;
  /** Attachment cell ids in the order processed. */
  readonly attachmentCellIds: readonly string[];
  /** Parent summary (has_pictures, etc.) — convenient for audit. */
  readonly parentSummary: AttachmentParentSummary;
}

export interface ReingestSkip {
  readonly proposalId: string;
  readonly skipped: true;
  readonly reason: string;
}

export type ReingestOutcome = ReingestReceipt | ReingestSkip;

export interface ReingestWorkerArgs {
  readonly proposal: Proposal;
  /**
   * Already-parsed MIME attachments from the source email. The
   * caller (D-RTC.7 CLI) decodes the raw blob from blob-store and
   * runs `parseEmailMimeParts` before invoking the worker. Empty
   * array when the proposal has no attachments.
   */
  readonly attachments: readonly EmailMimePart[];
  /** Used by site-dedupe to query the brain's view of sites_store. */
  readonly sitesView: SitesView;
  /**
   * Optional job-dedupe view. When provided, the worker checks for an
   * existing job_cell with the same dedupe key (WO# primary) BEFORE
   * minting; on a hit it reuses that cell id and skips the job
   * encode dispatch (attachments still parent to it). Collapses the
   * bundle-fanout / re-extract duplicates. When absent, every
   * proposal mints a fresh job (legacy behaviour).
   */
  readonly jobsDedupeView?: JobsDedupeView;
  /**
   * Optional customer-dedupe view (handoff §6.2). When provided, each
   * contact is resolved by NATURAL KEY (role-aware: agency contacts
   * site-independently, landlords by name, tenants by name+site) BEFORE
   * minting; on a hit the existing customer_cell id is reused so the
   * canonicalized 152 don't regrow. When absent, every contact mints a
   * fresh cell (legacy behaviour). Mirrors the `jobsDedupeView` posture.
   */
  readonly customersDedupeView?: CustomersDedupeView;
  /** Content-addressed blob store for PDF/image bytes. */
  readonly attachmentBlobStore: AttachmentBlobStore;
  /** Encoder dispatcher — calls into brain's `entity.encode` verb. */
  readonly dispatcher: EncodeDispatcher;
  /** Operator hat id (first 16 bytes as 32-hex). Zero-fill if absent. */
  readonly ownerIdHex: string;
  /**
   * Optional receipt store. When provided:
   *   • BEFORE reingest, the worker checks `store.has(providerId,
   *     proposalId)` — if true, it returns a skip outcome without
   *     dispatching any cells.
   *   • AFTER successful reingest, the worker writes a receipt
   *     capturing the full cell-id graph so re-runs are O(1) skips
   *     and the chat resolver / audit log can trace cells back to
   *     their source.
   *
   * When absent, the worker is non-idempotent — every call mints
   * fresh cells. Tests and dry-run paths typically omit it.
   */
  readonly receiptStore?: ReingestReceiptStore;
  /**
   * Upgrade-in-place mode (PRD §D-RTC.7 + What NOT to Do clause:
   * "Don't overwrite operator-edited cells — Upgrade-in-place
   * merges with operator data winning on conflict").
   *
   * When `true` AND `receiptStore` is wired:
   *   • The receipt-check skip is BYPASSED — the proposal re-runs
   *     the full pipeline producing fresh cells (with the upgraded
   *     extractor schema, the new substrate_entity typehash, etc.).
   *   • The NEW receipt captures `supersededReceiptId: <oldId>`
   *     pointing at the prior receipt so the audit trail is
   *     contiguous and the operator can see what got rebuilt.
   *
   * When `false` (default): receipt-check skip applies normally.
   *
   * Out of scope for this iter: operator-edited-field merge (PRD
   * "operator data winning on conflict") — needs a per-cell diff
   * machinery that lives one level up.
   */
  readonly upgradeExisting?: boolean;

  /**
   * P1a — optional turn sink. When provided, the worker writes one
   * canonical ConversationTurn (surface='email', direction='inbound')
   * AFTER the job cell is minted, anchoring it to the minted jobCellId
   * via entityRef.  This is the first turn for each reingested job,
   * making "Generate from conversation" useful for the 146+ existing jobs.
   *
   * bodyText = proposal.summary (subject + extracted summary).
   * participantRole: inferred from primaryContact.role:
   *   'pm' | 'agent' → 'agent'; 'tenant' | 'owner' | 'other' → 'external'.
   * identityHandle: { kind: 'email', value: primaryContact.email } when set.
   *
   * Best-effort: a throw is logged and swallowed; it never regresses
   * the reingest outcome.
   *
   * Architecture: safe to call from the CLI/worker-runner because it writes
   * directly to Postgres (not the brain reactor) — no self-call deadlock.
   */
  readonly turnSink?: ReingestTurnSink;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Reingest one extracted proposal into the typed-cell graph. Returns
 * a structured receipt with every minted cell id; the caller stores
 * receipts for idempotency + audit + chat-resolver indexing.
 *
 * Skip semantics: when the proposal was classified as
 * `thread_followup` or `not_a_job`, the worker emits a skip receipt
 * (no cells minted). When the proposal is missing the minimum data
 * needed to build a job cell (no summary), skip is also emitted.
 */
export async function reingestProposal(
  args: ReingestWorkerArgs,
): Promise<ReingestOutcome> {
  const { proposal } = args;

  // ── Skip filters ───────────────────────────────────────────────────
  // Proposals with no usable summary can't become a meaningful job.
  // Higher-level filters (job_type=thread_followup/not_a_job) typically
  // short-circuit at the extractor — defensive check here for sources
  // that emit a Proposal regardless.
  if (!proposal.summary || proposal.summary.trim().length === 0) {
    return {
      proposalId: proposal.proposalId,
      skipped: true,
      reason: 'no summary',
    };
  }

  // ── Non-job filter ─────────────────────────────────────────────────
  // A real property job always carries at least ONE durable anchor: a
  // work-order number, a PropertyMe/agency reference number, or a
  // property address. Proposals with none of these are correspondence
  // the extractor still emitted with a summary — invoice-query
  // replies, scheduling chatter, "Todd responds to…" follow-ups. They
  // must NOT each mint their own job (the source of the 376 explosion
  // + the "Todd Price ×67" / "Robert James Realty ×63" noise). Skip
  // them; the real job in the thread is anchored by one of the keys.
  const hasWo = (proposal.workOrderNumber ?? '').toString().trim().length > 0;
  const hasRef = (proposal.referenceNumber ?? '').toString().trim().length > 0;
  const hasAddr = (proposal.propertyAddress ?? '').toString().trim().length > 0;
  if (!hasWo && !hasRef && !hasAddr) {
    return {
      proposalId: proposal.proposalId,
      skipped: true,
      reason: 'not-a-job: no wo/ref/address anchor',
    };
  }

  // ── Idempotency: short-circuit if already reingested ──────────────
  // Bypassed when `upgradeExisting=true` — the operator explicitly
  // asked to rebuild the cell graph under the new extractor / encoder.
  let supersededReceiptId: string | null = null;
  if (args.receiptStore && !args.upgradeExisting) {
    if (await args.receiptStore.has(proposal.provenance.providerId, proposal.proposalId)) {
      return {
        proposalId: proposal.proposalId,
        skipped: true,
        reason: 'already-ingested',
      };
    }
  }
  if (args.receiptStore && args.upgradeExisting) {
    const existing = await args.receiptStore.get(
      proposal.provenance.providerId,
      proposal.proposalId,
    );
    if (existing) {
      supersededReceiptId = existing.receiptId;
    }
  }

  // ── Site dedupe ────────────────────────────────────────────────────
  let siteCellId: string | null = null;
  let siteDisposition: ReingestReceipt['siteDisposition'] = 'absent';
  let siteProposal: SiteProposal | null = null;

  const addressForDedupe = pickAddress(proposal);
  if (addressForDedupe !== null) {
    const propRes = proposeSiteCell({
      rawAddress: addressForDedupe,
      keyNumber: proposal.propertyKey ?? null,
    });
    if (propRes !== null) {
      siteProposal = propRes;
      const existing = await args.sitesView.findByLookupKey(propRes.lookupKey);
      if (existing !== null) {
        siteCellId = existing;
        siteDisposition = 'matched';
      } else {
        const sitePayload: SiteCellPayload = {
          lookup_key: propRes.lookupKey,
          normalized_address: propRes.normalizedAddress,
          key_number: propRes.keyNumber,
          raw_address: propRes.rawAddress,
          state: 'active',
        };
        siteCellId = await args.dispatcher.dispatch(
          encodeSite(sitePayload, args.ownerIdHex),
        );
        siteDisposition = 'minted';
      }
    }
  }

  // ── Customer cells ────────────────────────────────────────────────
  const customerCellIds: string[] = [];
  const customerLookupKeys: string[] = [];
  const customerDispositions: ('matched' | 'minted')[] = [];
  const customerRefsForJob: JobCellPayload['customer_refs'] = [];

  if (proposal.primaryContact) {
    const id = await mintCustomer({
      contact: proposal.primaryContact,
      siteCellId,
      dispatcher: args.dispatcher,
      ownerIdHex: args.ownerIdHex,
      primary: true,
      customersDedupeView: args.customersDedupeView,
    });
    customerCellIds.push(id.cellId);
    customerLookupKeys.push(id.lookupKey);
    customerDispositions.push(id.disposition);
    customerRefsForJob.push({ cell_id: id.cellId, role: id.role, primary: true });
  }
  if (proposal.secondaryContacts) {
    for (const c of proposal.secondaryContacts) {
      const id = await mintCustomer({
        contact: c,
        siteCellId,
        dispatcher: args.dispatcher,
        ownerIdHex: args.ownerIdHex,
        primary: false,
        customersDedupeView: args.customersDedupeView,
      });
      customerCellIds.push(id.cellId);
      customerLookupKeys.push(id.lookupKey);
      customerDispositions.push(id.disposition);
      customerRefsForJob.push({ cell_id: id.cellId, role: id.role, primary: false });
    }
  }

  // ── Attachment pipeline (parallel to job, needed for has_pictures) ─
  // We need the parent's hasPictures + primaryPdfSha256 BEFORE we mint
  // the job cell so the job's fields are correct, BUT the attachment
  // cells need the job's cell id as parent. Resolution: run the
  // attachment pipeline twice — first with a placeholder parent id
  // to derive the parent summary, then again with the real job id
  // to emit the attachment cells. Or: mint job first with summary-
  // only fields, then attachments. Choosing the latter — simpler, and
  // the attachment-pipeline result IS the parent summary regardless
  // of which parent id we feed it.

  const summaryProbe = await runAttachmentPipeline({
    attachments: args.attachments,
    parentJobCellId: '0'.repeat(64), // placeholder; we re-run after job mint
    ownerIdHex: args.ownerIdHex,
    blobStore: args.attachmentBlobStore,
  });
  const parentSummary = summaryProbe.parentSummary;

  // ── Job cell ──────────────────────────────────────────────────────
  const jobPayload: JobCellPayload = {
    site_ref: siteCellId,
    customer_refs: customerRefsForJob,
    work_order_number: proposal.workOrderNumber ?? null,
    services: proposal.services ?? [],
    issuance_date: proposal.issuanceDate ?? null,
    due_date: proposal.dueDate ?? null,
    intent: deriveIntent(proposal),
    summary: proposal.summary,
    display_name: proposal.pointOfContact ?? proposal.summary.slice(0, 80),
    raw_pdf_blob_sha256: parentSummary.primaryPdfSha256,
    has_pictures: parentSummary.hasPictures,
    picture_count:
      parentSummary.pictureCount > 0 ? parentSummary.pictureCount : null,
    state: 'lead', // newly-reingested jobs enter the lead state
  };
  // ── Job dedupe ─────────────────────────────────────────────────────
  // Derive the stable job identity (WO# primary). If a prior proposal
  // already minted this job (bundle-fanout / re-extract dupe), reuse
  // its cell id instead of minting a second job_cell. The attachment
  // pipeline below still parents to whichever id we end up with.
  let jobCellId: string;
  let jobDisposition: ReingestReceipt['jobDisposition'];
  let jobLookupKey: string;
  if (args.jobsDedupeView) {
    const jobRes = await findOrProposeJob(
      {
        workOrderNumber: proposal.workOrderNumber ?? null,
        referenceNumber: proposal.referenceNumber ?? null,
        propertyAddress: proposal.propertyAddress ?? null,
        siteRef: siteCellId,
        issuanceDate: proposal.issuanceDate ?? null,
      },
      args.jobsDedupeView,
    );
    jobLookupKey = jobRes.lookupKey;
    if (jobRes.kind === 'match') {
      jobCellId = jobRes.cellId;
      jobDisposition = 'matched';
    } else {
      jobCellId = await args.dispatcher.dispatch(
        encodeJob(jobPayload, args.ownerIdHex),
      );
      jobDisposition = 'minted';
    }
  } else {
    jobCellId = await args.dispatcher.dispatch(
      encodeJob(jobPayload, args.ownerIdHex),
    );
    jobDisposition = 'minted';
    jobLookupKey = '';
  }

  // ── P1a: write initial ConversationTurn anchored to the job cell ──────────
  // Best-effort — a failure here MUST NOT regress the reingest outcome.
  if (args.turnSink) {
    try {
      await writeTurnForProposal(proposal, jobCellId, args.turnSink);
    } catch (e) {
      // Swallow: turn write is additive; reingest is the primary outcome.
    }
  }

  // ── Attachments (re-run with real parent) ─────────────────────────
  // The blob store is content-addressed; re-running with the same bytes
  // is idempotent — no duplicate blob writes.
  const attResult = await runAttachmentPipeline({
    attachments: args.attachments,
    parentJobCellId: jobCellId,
    ownerIdHex: args.ownerIdHex,
    blobStore: args.attachmentBlobStore,
  });
  const attachmentCellIds: string[] = [];
  for (const req of attResult.requests) {
    const id = await args.dispatcher.dispatch(req);
    attachmentCellIds.push(id);
  }

  // Suppress the unused-binding warning for siteProposal — it's kept
  // in scope for future audit-log emission (the receipt-store work
  // will record the dedupe trace including the lookupKey).
  void siteProposal;

  const receipt: ReingestReceipt = {
    proposalId: proposal.proposalId,
    siteCellId,
    siteDisposition,
    customerCellIds,
    customerLookupKeys,
    customerDispositions,
    jobCellId,
    jobDisposition,
    jobLookupKey,
    attachmentCellIds,
    parentSummary: attResult.parentSummary,
  };

  // Persist the receipt so re-runs of `legacy reingest` skip this
  // proposal. Write AFTER all dispatch calls succeeded — a thrown
  // dispatcher bubbles up before we record success.
  if (args.receiptStore) {
    await args.receiptStore.put({
      receiptId: proposal.proposalId,
      providerId: proposal.provenance.providerId,
      proposalId: proposal.proposalId,
      sourceMsgId: proposal.provenance.providerItemId,
      reingestedAt: Date.now(),
      siteCellId,
      siteDisposition,
      customerCellIds,
      customerLookupKeys,
      jobCellId,
      jobDisposition,
      jobLookupKey,
      attachmentCellIds,
      parentSummary: attResult.parentSummary,
      extractorVersion: proposal.provenance.extractorVersion,
      supersededReceiptId,
    });
  }

  return receipt;
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Per PRD §Pipeline shape step 4: the address used for site dedupe
 * comes from `propertyAddress` (Tier 1.7 deep-PDF extraction) first;
 * legacy proposals without it fall back to `point_of_contact` — but
 * that's frequently a person/agency name, not an address. The
 * fallback is intentional: better a junk site key than no site at
 * all when the operator can still review at ratification time.
 */
function pickAddress(p: Proposal): string | null {
  if (p.propertyAddress && p.propertyAddress.trim().length > 0) {
    return p.propertyAddress;
  }
  if (p.pointOfContact && p.pointOfContact.trim().length > 0) {
    return p.pointOfContact;
  }
  return null;
}

async function mintCustomer(args: {
  contact: ProposalContact;
  siteCellId: string | null;
  dispatcher: EncodeDispatcher;
  ownerIdHex: string;
  primary: boolean;
  /** §6.2 — when present, resolve-or-create by natural key; else always mint. */
  customersDedupeView?: CustomersDedupeView;
}): Promise<{
  cellId: string;
  role: ContactRole;
  lookupKey: string;
  disposition: 'matched' | 'minted';
}> {
  const role = mapLegacyRole(args.contact.role);

  // §6.2 — resolve-or-create. The same agency contact recurs at every
  // property they manage; without this the canonicalized 152 regrow.
  if (args.customersDedupeView) {
    const res = await findOrProposeCustomer(
      {
        role,
        name: args.contact.name,
        email: args.contact.email,
        siteRef: args.siteCellId,
      },
      args.customersDedupeView,
    );
    if (res.kind === 'match') {
      return { cellId: res.cellId, role, lookupKey: res.lookupKey, disposition: 'matched' };
    }
    const cellId = await mintCustomerCell(args, role);
    return { cellId, role, lookupKey: res.lookupKey, disposition: 'minted' };
  }

  // Legacy path — no dedupe view wired; always mint.
  const cellId = await mintCustomerCell(args, role);
  return { cellId, role, lookupKey: '', disposition: 'minted' };
}

/** Encode + dispatch one customer cell. The brain content-addresses it. */
async function mintCustomerCell(
  args: {
    contact: ProposalContact;
    siteCellId: string | null;
    dispatcher: EncodeDispatcher;
    ownerIdHex: string;
  },
  role: ContactRole,
): Promise<string> {
  const payload: CustomerCellPayload = {
    name: args.contact.name,
    email: args.contact.email,
    phone: args.contact.phone,
    role,
    linked_site_id: args.siteCellId,
    notes: null,
    state: 'active',
  };
  return args.dispatcher.dispatch(encodeCustomer(payload, args.ownerIdHex));
}

// ── FNV-1a-64 deterministic id derivation ────────────────────────────────────
// Mirrors the approach in `legacy-ingest-bridge.ts` (`stableTurnId`).
// Same inputs → same turnId (determinism invariant so re-runs skip existing rows).

function stableTurnId(parts: unknown[]): string {
  const input = JSON.stringify(parts);
  const bytes = new TextEncoder().encode(input);
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `turn-reingest-${hash.toString(16).padStart(16, '0')}`;
}

/**
 * P1a — build and submit one inbound ConversationTurn for a reingested
 * proposal. Called after the job cell is minted so we can set entityRef.
 *
 * Participant role:
 *   pm/agent → 'agent' (property manager, real estate agent)
 *   tenant/owner/other → 'external'
 *   absent primary contact → 'unknown'
 */
async function writeTurnForProposal(
  proposal: Proposal,
  jobCellId: string,
  sink: ReingestTurnSink,
): Promise<void> {
  const contact = proposal.primaryContact ?? null;

  // Determine participant role from the primary contact's role.
  let participantRole: ReingestTurnPayload['participantRole'];
  if (!contact) {
    participantRole = 'unknown';
  } else if (contact.role === 'pm' || contact.role === 'agent') {
    participantRole = 'agent';
  } else {
    participantRole = 'external';
  }

  // Identity handle from the primary contact email (if available).
  const identityHandle: ReingestTurnPayload['identityHandle'] =
    contact?.email && contact.email.length > 0
      ? { kind: 'email', value: contact.email }
      : undefined;

  // Build the body text from summary (the extracted job description).
  // Prepend pointOfContact if it adds context.
  const poc = proposal.pointOfContact?.trim() ?? '';
  const summary = proposal.summary.trim();
  const bodyText = poc.length > 0 && !summary.startsWith(poc)
    ? `${poc}\n\n${summary}`
    : summary;

  // Stable id — same proposal always produces the same turnId.
  const turnId = stableTurnId(['reingest-turn', proposal.proposalId, jobCellId]);
  const correlationId = stableTurnId(['reingest-corr', proposal.proposalId]);

  const turn: ReingestTurnPayload = {
    turnId,
    conversationId: correlationId, // reingest turns: conversation = correlationId
    entityRef: { kind: 'job', cellHash: jobCellId },
    participantRole,
    ...(identityHandle ? { identityHandle } : {}),
    surface: 'email',
    direction: 'inbound',
    bodyText,
    correlationId,
    timestamp: Date.now(),
  };

  await sink(turn);
}

/**
 * Map the proposal's source signals to the JobCellPayload.intent enum.
 * The extractor's `job_type` lives inside the SIRProgram for now (Phase
 * 1 prompt) — we cannot reliably read it back from the typed Proposal
 * surface without an SIR walker. Heuristic: derive from the
 * `workOrderNumber` field — when present, the proposal carried a WO
 * PDF → `work_order`; otherwise default to `maintenance_order` which is
 * the dominant reingest case (Bricks/RJR dispatches).
 *
 * Future: D-RTC.3 v0.7 should add an explicit `intent` field on the
 * Proposal type so we don't have to infer.
 */
function deriveIntent(p: Proposal): JobCellPayload['intent'] {
  if (p.workOrderNumber !== null && p.workOrderNumber !== undefined) {
    return 'work_order';
  }
  return 'maintenance_order';
}

```
