---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.157970+00:00
---

# runtime/legacy-ingest/src/extractor/types.ts

```ts
/**
 * Extractor types — LI3.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI3.
 *
 * The extractor walks the raw-blob store, runs each item through a
 * per-content-type extractor, and produces typed Proposal records that
 * the LI4 ratification queue surfaces to the operator.
 *
 * Proposals are NEVER cells — they are pending, signed-by-extractor
 * suggestions. Only operator ratification (LI4) turns one into a cell.
 * Provenance from the originating raw item is preserved end-to-end.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { ProviderId, RawItem } from '../types';

/**
 * Where this proposal came from. Carried into the eventual cell header
 * if the operator ratifies, so any cell is traceable back to its
 * Gmail thread / WhatsApp message / calendar entry.
 */
export interface ProposalProvenance {
  readonly providerId: ProviderId;
  readonly providerItemId: string;
  /** Unix ms when the raw item was fetched. */
  readonly fetchedAt: number;
  /** Hash of the extractor module version that produced this proposal. */
  readonly extractorVersion: string;
  /** Hash of the prompt template (or 'no-llm' when a structured extractor). */
  readonly promptHash: string;
}

export type ProposalStatus =
  | 'pending'        // awaiting operator review
  | 'ratified'       // operator confirmed, cell written
  | 'rejected'       // operator dropped (e.g. "newsletter")
  | 'corrected'      // operator edited then ratified — see correction-edge cells
  | 'superseded'     // re-extracted with a newer prompt; this version replaced
  | 'auto-ratified'; // confidence ≥ threshold + operator opt-in

export interface Proposal {
  /** Stable id; used by `legacy ratify <id>`. */
  readonly proposalId: string;
  /** Confidence in [0,1]. ≥ 0.85 may auto-ratify; < 0.5 dropped. */
  readonly confidence: number;
  /** Status — mutated by ratification. */
  readonly status: ProposalStatus;
  readonly provenance: ProposalProvenance;
  readonly extractedAt: number;
  /** The proposal payload — a SIRProgram ready to lower → kernel → cell. */
  readonly program: SIRProgram;
  /** Optional thread key — set after thread-collapsing pass. */
  readonly threadKey?: string;
  /** Other proposals merged into this thread; populated by collapse pass. */
  readonly siblingProposalIds?: string[];
  /**
   * Work-order / PO / reference number extracted from the email or its
   * attachments (e.g. PropertyMe order number). Used by the ref-dedup pass
   * in thread.ts to fold separate emails about the same job.
   */
  readonly referenceNumber?: string;
  /**
   * Display identity for the job — whoever is actively in the loop
   * with the operator about THIS job, regardless of role. Could be an
   * agency, a property manager, a tenant (often the day-to-day liaison
   * for access + scheduling), a landlord acting directly, or a
   * sub-tradie collaborating on someone else's job. NOT the billing
   * party. NOT the property address. NOT the owner unless they're
   * actually the one communicating. Threaded into the cell-writer's
   * `payload_hint.point_of_contact` so brain / FS-fallback writes show
   * sensible names in the helm + mobile JobList.
   *
   * Backward-compat display alias: starting with extractor v0.5 it is
   * derived server-side from `primaryContact` as
   * "<name> (<role>)" so older readers keep working.
   *
   * Optional because older proposals predate this field; cell-writer
   * falls back to the previous `customer_name` heuristic when absent.
   * The JSONL field name in `jobs.jsonl` stays `customer_name` for
   * backward compat — proper schema rename is Tier 1.6.
   */
  readonly pointOfContact?: string;
  // ── Tier 1.7 deep-PDF extraction fields ──────────────────────────────
  //
  // Populated for the three job-creating values
  // (`quote_request | work_order | maintenance_order`). Each is null /
  // omitted on `thread_followup` and `not_a_job`, and may be null when
  // the source doesn't expose the field. Operator's helm + mobile
  // surfaces will pick these up incrementally; the JSONL on-disk shape
  // doesn't change (Tier 1.6 owns that rename).
  /** Verbatim WO# from the source PDF, e.g. "07487", "RJR-2025-0142". */
  readonly workOrderNumber?: string | null;
  /** ISO YYYY-MM-DD from the "Created:" line in the PDF. */
  readonly issuanceDate?: string | null;
  /** ISO YYYY-MM-DD from the "Due:" line in the PDF. */
  readonly dueDate?: string | null;
  /** Full address line, e.g. "29 Foedera Cres, Tewantin QLD 4565". */
  readonly propertyAddress?: string | null;
  /** Access-key reference, e.g. "key #177". */
  readonly propertyKey?: string | null;
  /**
   * Primary contact = first/bold tenant in "For access contact the
   * tenant/s on:". Phone priority m → h → w; null if all "n/a".
   */
  readonly primaryContact?: ProposalContact | null;
  /** Other tenants + agent (and owner if directly contactable). */
  readonly secondaryContacts?: ProposalContact[];
  /** Owner name from "issued on behalf of the owner - <name>" line. */
  readonly ownerName?: string | null;
  /**
   * Server-side billing-party rules per source:
   *   - Clever Property: always agency=Clever Property
   *   - RJR: if "on behalf of" names owner → bill owner; else agency
   *   - Bricks + Agent: bill the routed agency / PM
   *   - unknown: null (operator manually corrects)
   */
  readonly billingParty?: ProposalBillingParty | null;
  /** Vision detected ≥1 distinct photo on any page of the PDF. */
  readonly hasPhotos?: boolean;
  /** Best-effort distinct photo count; null when unknown. */
  readonly photoCount?: number | null;
  /**
   * v0.6 — short service tags ("plumbing", "roof-repair", "pergola",
   * "leak-investigation"). Drives chat resolution — when the operator
   * types "quote 500 for the pergola job" the resolver matches by
   * service hint. Empty array / undefined when nothing identifiable.
   */
  readonly services?: readonly string[];
  /**
   * Blob-store key of the source PDF — server-side, immutable from the
   * LLM. For per-PDF fan-out from a bundle email this includes the
   * `#attachment-<n>` suffix so the operator can map back to the exact
   * PDF in the bundle.
   */
  readonly sourceAttachmentPath?: string;
  /** Free-form summary for queue display. */
  readonly summary: string;
  /** Operator-supplied reason on rejection. */
  readonly rejectReason?: string;
}

/**
 * One contact extracted from a Clever Property / RJR / Bricks PDF.
 * `phone` follows the m → h → w priority documented on Proposal.
 */
export interface ProposalContact {
  readonly name: string;
  readonly role: 'tenant' | 'agent' | 'owner' | 'pm' | 'other';
  readonly phone: string | null;
  readonly email: string | null;
}

/**
 * Billing party. `agency` = bill the routing PM / agency (e.g. always
 * Clever Property; Robert James Realty when no owner override).
 * `owner` = bill the named owner (RJR variance when "on behalf of"
 * names the owner). `null` on the proposal field means "operator must
 * decide" (unknown source / ambiguous "on behalf of" line).
 */
export interface ProposalBillingParty {
  readonly type: 'agency' | 'owner';
  readonly name: string;
}

/**
 * One run of the extractor — a Pre-classifier might short-circuit
 * before running the LLM. Tests assert on this for coverage.
 */
export type ExtractionOutcome =
  | { kind: 'extracted'; proposal: Proposal }
  | { kind: 'pre-filtered'; reason: string }
  | { kind: 'low-confidence'; confidence: number; reason: string };

/**
 * Pluggable LLM adapter port. Production wires Anthropic; tests
 * inject a deterministic stub. The port is intentionally minimal —
 * the extractor knows which prompt to render; the adapter only
 * runs the LLM call.
 */
export interface LLMAdapter {
  /**
   * Render the prompt + parse the response into a typed payload.
   * The extractor passes the schema; the adapter is responsible
   * for constraining the LLM's output to it.
   */
  extract<T>(opts: {
    prompt: string;
    /**
     * JSON-schema-like description of the expected output. The
     * adapter uses it to constrain decoding. Tests usually pass
     * `{}` and trust the stub's hardcoded response.
     */
    schema: object;
  }): Promise<{ payload: T; confidence: number; raw: string }>;
}

/**
 * One per content-type. The adapter knows how to:
 *   - decide whether to run (pre-classifier short-circuits non-business
 *     content like Google account notifications)
 *   - render the per-content-type prompt + schema
 *   - assemble a SIRProgram from the LLM payload
 *   - extract a thread key if the content carries one (Gmail
 *     In-Reply-To, WhatsApp conversation id, etc.)
 *
 * `extract` returns an array of outcomes so a single inbound item can
 * produce multiple proposals. The Tier 1.7 use case: an operator
 * forwarding a bundle email to themselves with N PDF work-orders
 * attached — fan out one outcome per attachment so each PDF gets its
 * own structured proposal. For the common one-email-one-proposal flow
 * the array always has length 1, preserving the prior contract.
 */
export interface ContentExtractor {
  /** MIME-style content type, matching `RawItem.contentType`. */
  readonly contentType: string;
  /** Hash of the extractor's source — bumped when the prompt or
   * schema changes. Used to drive re-extraction. */
  readonly extractorVersion: string;

  extract(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome[]>;
}

```
