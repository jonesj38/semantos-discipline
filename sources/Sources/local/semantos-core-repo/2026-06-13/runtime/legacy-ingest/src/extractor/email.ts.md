---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/email.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.160199+00:00
---

# runtime/legacy-ingest/src/extractor/email.ts

```ts
/**
 * Email/rfc822 extractor — LI3.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI3 deliverable 1.
 *
 * Strategy:
 *   1. Pre-classifier filters obvious non-business content (deterministic
 *      header-only check — newsletters, list-unsubscribe, etc.).
 *   2. Parse rfc822 headers + body deterministically (no LLM).
 *   3. LLM call asks for a TWO-PHASE structured response:
 *        Phase 1 — classify `job_type` as one of five values:
 *          quote_request | work_order | maintenance_order |
 *          thread_followup | not_a_job
 *        Phase 2 — for the three job-creating values only, fill in
 *          customer / job / point_of_contact.
 *   4. Route on `job_type`:
 *        not_a_job        → pre-filtered (operator's vendor receipts,
 *                            platform notifications, marketing, etc.)
 *        thread_followup  → pre-filtered (continuation on an existing
 *                            thread; thread-fold pass already covers it)
 *        otherwise        → assemble a SIRProgram and return a Proposal.
 *
 * The five-way classification was added in v0.4 after operator data
 * showed ~90% false-positive proposals at 0.95+ confidence: the prior
 * `lead | quote_request | booking | inquiry | reply | other` schema
 * encouraged the LLM to map any structured email to "lead" rather than
 * filtering. Operator domain expertise: real jobs always come through
 * as exactly one of three event types.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { RawItem } from '../types';
import type {
  ContentExtractor,
  ExtractionOutcome,
  LLMAdapter,
  Proposal,
  ProposalContact,
  ProposalBillingParty,
} from './types';
import { classifyForExtraction } from './pre-classifier';
import type { VisionAdapter } from './attachment';
import {
  parseEmailMimeParts,
  extractAttachmentTexts,
  type EmailMimePart,
} from './attachment';
import type {
  AdapterConfigMetadata,
  BillingRule,
  BillingRuleOutcome,
} from '../adapter-config/types';
import { DEFAULT_ODDJOBZ_ADAPTER_CONFIG } from '../adapter-config/default-oddjobz-config';
import { buildPromptTemplate } from './prompt-builder';

/**
 * v0.6 — D-RTC.3 services elicitation.
 *
 * Adds a `services` field to the extraction payload (an array of short
 * service tags — "plumbing", "roof-repair", "pergola", "leak-investig-
 * ation") so chat resolution ("quote 500 for the pergola job") can
 * match an existing job cell by service hint. The bump from v0.5 →
 * v0.6 means `legacy ingest gmail --reextract` automatically super-
 * sedes prior v0.5 proposals.
 *
 * v0.5 — Tier 1.7 deep-PDF extraction.
 */
export const EMAIL_EXTRACTOR_VERSION = 'email-rfc822-v0.6';

// CC6.3a — Operator-owned email addresses (the bundle-fan-out
// allow-list) now live in adapter-config metadata
// (`AdapterConfigMetadata.fallback_operator_emails`). `OPERATOR_EMAIL`
// env still takes precedence; the config supplies the fallback list.
// See `../adapter-config/default-oddjobz-config.ts` for the seeded
// default that preserves prior behaviour.

/**
 * Five-way classification produced by Phase 1 of the prompt. Only the
 * three job-creating values (`quote_request`, `work_order`,
 * `maintenance_order`) trigger structured Phase 2 extraction; the other
 * two short-circuit to a `pre-filtered` outcome so we don't flood the
 * review queue with platform notifications, billing receipts, marketing
 * emails, and follow-ups on existing job threads.
 */
export type EmailJobType =
  | 'quote_request'
  | 'work_order'
  | 'maintenance_order'
  | 'thread_followup'
  | 'not_a_job';

/** Snake-case contact shape produced by the LLM. */
export interface EmailExtractionContact {
  name: string;
  role: 'tenant' | 'agent' | 'owner' | 'pm' | 'other';
  phone: string | null;
  email: string | null;
}

/** Snake-case billing-party shape produced by the LLM. */
export interface EmailExtractionBillingParty {
  type: 'agency' | 'owner';
  name: string;
}

/** What the LLM is asked to produce. Mirrors the OJT extraction shape. */
export interface EmailExtractionPayload {
  /**
   * Phase 1 classification — required, drives outcome routing. Only the
   * three job-creating values cause the rest of the payload to be
   * populated; `thread_followup` and `not_a_job` short-circuit to a
   * `pre-filtered` outcome upstream.
   */
  job_type: EmailJobType;
  /** Free-text summary in operator-voice. */
  summary: string;
  /**
   * Whoever is actively in the loop with the operator about THIS job —
   * the person or organisation the operator would naturally text or
   * call to talk about the work. Could be an agency, a property
   * manager, a tenant (often the day-to-day liaison for access and
   * scheduling), a landlord acting directly, or a sub-tradie
   * coordinating a collab. NOT the billing party. NOT the property
   * address. NOT the owner unless they're actually communicating.
   * Used as the job's display identity in the helm + mobile JobList.
   * See the prompt body for the heuristic.
   *
   * Note: starting with v0.5 this is OPTIONAL in the LLM output —
   * the server derives the display string from `primary_contact`
   * server-side. The field stays in the schema as a fallback for
   * thread_followup / not_a_job free-form summaries.
   */
  point_of_contact?: string;
  customer?: {
    name?: string;
    email?: string;
    phone?: string;
  };
  job?: {
    description?: string;
    location?: string;
    /** ISO date, set only if the message names one explicitly. */
    desiredDate?: string;
    /**
     * Work-order / PO / reference number if explicitly stated in the email
     * or an attached PDF (e.g. PropertyMe or BricksAndAgent order number).
     */
    referenceNumber?: string;
  };
  /**
   * Verbatim WO# from the source PDF (e.g. "07487",
   * "RJR-2025-0142"). Required when job_type is one of the three
   * job-creating values; null when the source doesn't carry one.
   */
  work_order_number?: string | null;
  /** ISO YYYY-MM-DD; converted from the PDF's "Created:" line. */
  issuance_date?: string | null;
  /** ISO YYYY-MM-DD; converted from the PDF's "Due:" line. */
  due_date?: string | null;
  /** Full property address line, verbatim. */
  property_address?: string | null;
  /** Access-key reference, e.g. "key #177". */
  property_key?: string | null;
  /**
   * The first/bold tenant in "For access contact the tenant/s on:".
   * Phone resolution m → h → w; null if all are "n/a".
   */
  primary_contact?: EmailExtractionContact | null;
  /** Other tenants + agent (and owner if directly contactable). */
  secondary_contacts?: EmailExtractionContact[];
  /** Owner from "issued on behalf of the owner - <name>". */
  owner_name?: string | null;
  /**
   * Billing party — see prompt for rules per source. The LLM may emit
   * its best guess; the server normalises against the source-domain
   * heuristic and overrides on conflict.
   */
  billing_party?: EmailExtractionBillingParty | null;
  /** Vision detected ≥1 distinct photo on any PDF page. */
  has_photos?: boolean;
  /** Best-effort distinct photo count. */
  photo_count?: number | null;
  /**
   * v0.6 — short service tags inferred from the email body + any
   * attached PDFs. Drives chat resolution ("quote the pergola job"
   * → match this cell by service). Use lowercase, hyphenated, no
   * spaces. Examples: "plumbing", "roof-repair", "pergola", "leak-
   * investigation", "fence-replacement", "tap-replacement". Empty
   * array when nothing identifiable.
   */
  services?: string[];
  /** Reasons or null. Free-form for the few-shot retriever. */
  rationale?: string;
}

const CONTACT_SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    role: { enum: ['tenant', 'agent', 'owner', 'pm', 'other'] },
    phone: { type: ['string', 'null'] },
    email: { type: ['string', 'null'] },
  },
  required: ['name', 'role'],
} as const;

const SCHEMA = {
  type: 'object',
  properties: {
    job_type: {
      enum: [
        'quote_request',
        'work_order',
        'maintenance_order',
        'thread_followup',
        'not_a_job',
      ],
    },
    summary: { type: 'string' },
    point_of_contact: { type: 'string' },
    customer: { type: 'object' },
    job: {
      type: 'object',
      properties: {
        description: { type: 'string' },
        location: { type: 'string' },
        desiredDate: { type: 'string' },
        referenceNumber: { type: 'string' },
      },
    },
    work_order_number: { type: ['string', 'null'] },
    issuance_date: { type: ['string', 'null'] },
    due_date: { type: ['string', 'null'] },
    property_address: { type: ['string', 'null'] },
    property_key: { type: ['string', 'null'] },
    primary_contact: { anyOf: [CONTACT_SCHEMA, { type: 'null' }] },
    secondary_contacts: { type: 'array', items: CONTACT_SCHEMA },
    owner_name: { type: ['string', 'null'] },
    billing_party: {
      anyOf: [
        {
          type: 'object',
          properties: {
            type: { enum: ['agency', 'owner'] },
            name: { type: 'string' },
          },
          required: ['type', 'name'],
        },
        { type: 'null' },
      ],
    },
    has_photos: { type: 'boolean' },
    photo_count: { type: ['number', 'null'] },
    services: {
      type: 'array',
      items: { type: 'string', minLength: 1 },
    },
    rationale: { type: 'string' },
  },
  required: ['job_type', 'summary'],
} as const;

// CC6.3b — PROMPT_TEMPLATE retired into a builder. The template +
// agency-specific zones are composed per-EmailExtractor-instance
// from the adapter-config metadata via
// `runtime/legacy-ingest/src/extractor/prompt-builder.ts`.
//
// `EmailExtractor` stores the rendered template + its hash on
// construction; runOnce() interpolates {{HEAD}} / {{BODY}} per
// message. PROMPT_HASH is now per-instance (config-dependent), so
// re-extraction triggers correctly when an operator changes the
// adapter-config (e.g. adds a new agency).
//
// The hardcoded prompt content + per-agency pedagogy zones that
// used to live here (lines 262–565 before this commit) now live in
// `prompt-builder.ts` (static template skeleton) and
// `adapter-config/default-oddjobz-config.ts`
// (`BillingRule.prompt_fragments` per agency).

export interface EmailExtractorOpts {
  /** ≥ this becomes a proposal; < 0.5 dropped per LI3 spec. */
  acceptThreshold?: number;
  /** ≥ this is auto-ratifiable. Operator-configurable in production. */
  highConfidenceThreshold?: number;
  /**
   * Optional vision LLM adapter for OCR of image/PDF attachments.
   * When provided, attachment text is appended to the email body before
   * the main extraction prompt. If absent, attachments are ignored.
   */
  vision?: VisionAdapter;
  /**
   * D-RTC.7-followup — when supplied, the pre-classifier drops any
   * message whose From doesn't match the allowlist or
   * `selfForwardAddresses`. Use `OJT_SENDER_ALLOWLIST` +
   * `OJT_SELF_FORWARD_ADDRESSES` exports for the canonical OJT filter
   * (Clever Property + Robert James Realty + Todd's gmail).
   */
  senderAllowlist?: readonly RegExp[];
  /** Self-forward addresses that bypass the senderAllowlist. */
  selfForwardAddresses?: readonly string[];
  /**
   * CC6.3a — Adapter-config metadata: per-source/per-operator data
   * (bundle-fan-out allow-list + billing-party rules). When omitted,
   * defaults to `DEFAULT_ODDJOBZ_ADAPTER_CONFIG`, which preserves the
   * pre-CC6.3a hardcoded behaviour. A test, a new operator, or a
   * future brain-side cell fetch can override.
   */
  adapterConfig?: AdapterConfigMetadata;
}

export class EmailExtractor implements ContentExtractor {
  readonly contentType = 'email/rfc822';
  readonly extractorVersion = EMAIL_EXTRACTOR_VERSION;
  private readonly acceptThreshold: number;
  private readonly highConfidenceThreshold: number;
  private readonly vision: VisionAdapter | null;
  private readonly senderAllowlist: readonly RegExp[] | null;
  private readonly selfForwardAddresses: readonly string[] | null;
  private readonly adapterConfig: AdapterConfigMetadata;
  /**
   * CC6.3b — Prompt template rendered from `adapterConfig` at
   * construction. Still carries the `{{HEAD}}` / `{{BODY}}` placeholders;
   * `runOnce()` fills those per-message. Deterministic per config — a
   * fresh adapter-config yields a deterministically-different template.
   */
  private readonly promptTemplate: string;
  /**
   * CC6.3b — Hash of `(promptTemplate + SCHEMA)` for re-extraction
   * detection. Changes when either the prompt builder OR the adapter
   * config changes, so a config update naturally invalidates prior
   * extraction outputs.
   */
  private readonly promptHash: string;

  constructor(opts: EmailExtractorOpts = {}) {
    this.acceptThreshold = opts.acceptThreshold ?? 0.5;
    this.highConfidenceThreshold = opts.highConfidenceThreshold ?? 0.85;
    this.vision = opts.vision ?? null;
    this.senderAllowlist = opts.senderAllowlist ?? null;
    this.selfForwardAddresses = opts.selfForwardAddresses ?? null;
    this.adapterConfig = opts.adapterConfig ?? DEFAULT_ODDJOBZ_ADAPTER_CONFIG;
    this.promptTemplate = buildPromptTemplate(this.adapterConfig);
    this.promptHash = hashString(this.promptTemplate + '\n' + JSON.stringify(SCHEMA));
    void this.highConfidenceThreshold; // surface in summary, used by LI4 auto-ratify
  }

  async extract(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome[]> {
    const pre = classifyForExtraction(item, {
      senderAllowlist: this.senderAllowlist ?? undefined,
      selfForwardAddresses: this.selfForwardAddresses ?? undefined,
    });
    if (!pre.shouldExtract) {
      return [{ kind: 'pre-filtered', reason: pre.droppedReason ?? 'pre-classifier' }];
    }

    const parsed = parseRfc822(item.bytes);
    const rootContentType = parsed.headers['content-type'] ?? '';

    // Tier 1.7 — bundle-fan-out. When the operator forwards a batch of
    // PDF work-orders to themselves, we fan out one extraction per PDF
    // so each gets its own structured proposal. Detection: From-header
    // is one of the operator's own addresses AND ≥2 PDF attachments are
    // present. Anything else falls through to the single-proposal path.
    let pdfAttachments: EmailMimePart[] = [];
    if (this.vision && rootContentType.toLowerCase().startsWith('multipart/')) {
      const parts = parseEmailMimeParts(parsed.body, rootContentType);
      pdfAttachments = parts.attachments.filter(a => a.kind === 'pdf');
    }

    if (
      pdfAttachments.length >= 2
      && isOperatorOwnEmail(extractEmailAddress(parsed.from), this.adapterConfig)
    ) {
      return this.extractBundleFanOut(item, parsed, pdfAttachments, llm);
    }

    return [await this.extractSingle(item, parsed, llm)];
  }

  /**
   * The original one-email-one-proposal path. Pre-Tier-1.7 callers
   * arrive here unchanged (their email either has no PDFs, has only
   * one, or comes from a non-operator sender).
   */
  private async extractSingle(
    item: RawItem,
    parsed: ParsedEmail,
    llm: LLMAdapter,
  ): Promise<ExtractionOutcome> {
    // OCR pass: extract text from image/PDF attachments when a vision adapter
    // is configured. The transcribed text is appended after the email body so
    // the LLM can mine job details from scanned forms or photos of notes.
    let attachmentContext = '';
    const rootContentType = parsed.headers['content-type'] ?? '';
    if (this.vision && rootContentType.toLowerCase().startsWith('multipart/')) {
      const parts = parseEmailMimeParts(parsed.body, rootContentType);
      if (parts.attachments.length > 0) {
        const texts = await extractAttachmentTexts(parts.attachments, this.vision);
        const nonEmpty = texts.filter(t => t.length > 0);
        if (nonEmpty.length > 0) {
          attachmentContext = '\n\n--- Attachment text (OCR) ---\n' + nonEmpty.join('\n---\n');
        }
      }
    }

    const bodyWithAttachments = (parsed.body.slice(0, 8000) + attachmentContext).slice(0, 12000);
    return this.runOnce(item, parsed, bodyWithAttachments, llm, defaultSourcePathFor(item));
  }

  /**
   * One LLM call per PDF attachment. Each call sees the original email
   * headers + body PLUS only that one PDF's OCR text, so the LLM can't
   * confuse fields across orders. Each outcome carries a distinct
   * `source_attachment_path` (server-side, immutable from the LLM)
   * pointing back to the specific PDF in the bundle.
   */
  private async extractBundleFanOut(
    item: RawItem,
    parsed: ParsedEmail,
    pdfs: EmailMimePart[],
    llm: LLMAdapter,
  ): Promise<ExtractionOutcome[]> {
    const outcomes: ExtractionOutcome[] = [];
    // Run sequentially — these are LLM calls, not local work, and a
    // bundle of 5 PDFs already costs as much as 5 normal proposals.
    // A small bundle * a vision-adapter-driven PDF parse is plenty for
    // the operator's review session.
    for (let i = 0; i < pdfs.length; i++) {
      const att = pdfs[i];
      const texts = await extractAttachmentTexts(
        [att],
        // SAFETY: extractBundleFanOut is only called when this.vision
        // was non-null at the entry to extract().
        this.vision!,
      );
      const ocr = texts[0] ?? '';
      const body =
        parsed.body.slice(0, 4000)
        + `\n\n--- Attachment PDF #${i + 1} of ${pdfs.length} (OCR) ---\n`
        + ocr;
      const trimmedBody = body.slice(0, 12000);
      const sourcePath = bundleSourcePathFor(item, i);
      outcomes.push(await this.runOnce(item, parsed, trimmedBody, llm, sourcePath));
    }
    return outcomes;
  }

  /**
   * Render the prompt + run the LLM + assemble (or short-circuit) the
   * outcome. Shared by both the single-shot path and the bundle
   * fan-out — the only difference between them is which body / source
   * path is threaded through.
   */
  private async runOnce(
    item: RawItem,
    parsed: ParsedEmail,
    body: string,
    llm: LLMAdapter,
    sourceAttachmentPath: string,
  ): Promise<ExtractionOutcome> {
    const prompt = this.promptTemplate
      .replace('{{HEAD}}', headerSummary(parsed))
      .replace('{{BODY}}', body);

    const llmResult = await llm.extract<EmailExtractionPayload>({ prompt, schema: SCHEMA });

    // Phase 1 outcome routing — if the LLM classified the email as a
    // non-job-creating type, short-circuit to a `pre-filtered` outcome
    // before the confidence gate. The two non-job-creating buckets:
    //   * `not_a_job` — platform notifications, billing receipts,
    //     marketing, account alerts, cold-call pitches.
    //   * `thread_followup` — replies on an existing job thread; the
    //     thread-fold pass on subsequent runs already keeps state
    //     coherent, so we don't want a duplicate proposal.
    // Both increment the `preFiltered` counter in the run summary
    // alongside the existing pre-classifier filtering.
    const jobType = llmResult.payload.job_type;
    if (jobType === 'not_a_job') {
      return {
        kind: 'pre-filtered',
        reason: `classified as not_a_job: ${llmResult.payload.summary ?? '(no summary)'}`,
      };
    }
    if (jobType === 'thread_followup') {
      return {
        kind: 'pre-filtered',
        reason: `thread_followup — existing thread: ${llmResult.payload.summary ?? '(no summary)'}`,
      };
    }

    if (llmResult.confidence < this.acceptThreshold) {
      return {
        kind: 'low-confidence',
        confidence: llmResult.confidence,
        reason: `confidence ${llmResult.confidence.toFixed(2)} < threshold ${this.acceptThreshold}`,
      };
    }

    const program = buildSIRProgramForEmail(llmResult.payload, parsed, llmResult.confidence);
    const primaryContact = normaliseContact(llmResult.payload.primary_contact ?? null);
    const secondaryContacts = (llmResult.payload.secondary_contacts ?? [])
      .map(c => normaliseContact(c))
      .filter((c): c is ProposalContact => c !== null);
    const ownerName = nullableString(llmResult.payload.owner_name);
    const billingParty = normaliseBillingParty(
      llmResult.payload.billing_party ?? null,
      parsed,
      ownerName,
      this.adapterConfig,
    );

    // Display alias — derive the legacy `pointOfContact` server-side
    // from the new `primary_contact` so older readers (helm, mobile,
    // brain handler, FS-fallback) keep working without schema changes.
    // Falls back to the LLM-emitted `point_of_contact` only when no
    // primary contact was extracted (e.g. plain email from a non-PDF
    // source where the new fields are still absent).
    const pointOfContact = primaryContact
      ? `${primaryContact.name} (${primaryContact.role})`.slice(0, 200)
      : normalisePointOfContact(llmResult.payload.point_of_contact);

    const proposal: Proposal = {
      proposalId: cryptoRandomId(),
      confidence: llmResult.confidence,
      status: 'pending',
      provenance: {
        providerId: item.providerId,
        providerItemId: item.providerItemId,
        fetchedAt: item.fetchedAt,
        extractorVersion: this.extractorVersion,
        promptHash: this.promptHash,
      },
      extractedAt: Date.now(),
      program,
      threadKey: parsed.inReplyTo ?? parsed.references ?? undefined,
      referenceNumber:
        normaliseWorkOrderNumber(llmResult.payload.work_order_number)
        ?? llmResult.payload.job?.referenceNumber,
      pointOfContact,
      // Tier 1.7 deep-PDF fields. Each is null/undefined-safe; the
      // helm + mobile renderers already null-guard; the Semantos Brain handler's
      // payload_hint envelope passes everything through.
      workOrderNumber: normaliseWorkOrderNumber(llmResult.payload.work_order_number),
      issuanceDate: normaliseIsoDate(llmResult.payload.issuance_date),
      dueDate: normaliseIsoDate(llmResult.payload.due_date),
      propertyAddress: nullableString(llmResult.payload.property_address),
      propertyKey: nullableString(llmResult.payload.property_key),
      primaryContact,
      secondaryContacts: secondaryContacts.length > 0 ? secondaryContacts : undefined,
      ownerName,
      billingParty,
      hasPhotos: typeof llmResult.payload.has_photos === 'boolean'
        ? llmResult.payload.has_photos
        : undefined,
      photoCount: typeof llmResult.payload.photo_count === 'number'
        ? llmResult.payload.photo_count
        : null,
      // Server-side, immutable from the LLM — defends against prompt
      // injection in PDF content trying to redirect the path.
      sourceAttachmentPath,
      services: normaliseServices(llmResult.payload.services),
      summary: llmResult.payload.summary,
    };
    return { kind: 'extracted', proposal };
  }
}

// ── rfc822 deterministic parsing ──

interface ParsedEmail {
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
  readonly messageId: string | null;
  readonly inReplyTo: string | null;
  readonly references: string | null;
  readonly subject: string;
  readonly from: string;
}

export function parseRfc822(bytes: Uint8Array): ParsedEmail {
  const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  const blank = text.indexOf('\r\n\r\n');
  const split = blank >= 0 ? blank : text.indexOf('\n\n');
  const headersText = split >= 0 ? text.slice(0, split) : text;
  const body = split >= 0 ? text.slice(split + (text[split] === '\r' ? 4 : 2)) : '';
  const headers: Record<string, string> = {};
  // RFC822 line continuations: a header continues on the next line if
  // it's whitespace-prefixed.
  const lines = headersText.split(/\r?\n/);
  let current: string | null = null;
  for (const line of lines) {
    if (line.length === 0) continue;
    if (/^\s/.test(line) && current) {
      headers[current] += ' ' + line.trim();
      continue;
    }
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const name = line.slice(0, colon).trim().toLowerCase();
    const value = line.slice(colon + 1).trim();
    headers[name] = value;
    current = name;
  }
  return {
    headers,
    body,
    messageId: pickAngled(headers['message-id'] ?? null),
    inReplyTo: pickAngled(headers['in-reply-to'] ?? null),
    references: pickAngled(headers['references'] ?? null),
    subject: headers['subject'] ?? '',
    from: headers['from'] ?? '',
  };
}

function pickAngled(value: string | null): string | null {
  if (!value) return null;
  const m = value.match(/<([^>]+)>/);
  return m ? m[1] : value;
}

function headerSummary(parsed: ParsedEmail): string {
  return [
    `From: ${parsed.from}`,
    `Subject: ${parsed.subject}`,
    parsed.inReplyTo ? `In-Reply-To: <${parsed.inReplyTo}>` : null,
  ].filter(Boolean).join('\n');
}

// ── SIRProgram synthesis ──

function buildSIRProgramForEmail(
  payload: EmailExtractionPayload,
  parsed: ParsedEmail,
  confidence: number,
): SIRProgram {
  // We synthesise a minimal SIRProgram. The eventual ratified cell
  // packs this through the existing intent pipeline; here we just
  // give it enough shape for the queue UI + the lowering-time check.
  const action = mapJobTypeToAction(payload.job_type);
  const expressedAt = new Date().toISOString();
  return {
    primaryNodeId: '$s0',
    programGovernance: {
      trustClass: 'cosmetic',
      domainBinding: { flag: 0, mode: 'declared' },
    } as any,
    nodes: [
      {
        id: '$s0',
        category: { lexicon: 'jural', category: 'declaration' } as any,
        taxonomy: {} as any,
        identity: {} as any,
        governance: { trustClass: 'cosmetic', domainBinding: { flag: 0, mode: 'declared' } } as any,
        action,
        constraint: { kind: 'literal', value: 'true' } as any,
        target: payload.customer?.email
          ? { kind: 'identity', id: payload.customer.email } as any
          : undefined,
        provenance: {
          source: 'inferred',
          confidence,
          inferenceRunId: parsed.messageId ?? undefined,
          expressedAt,
          trustAtExpression: 'cosmetic',
        },
      },
    ],
  };
}

/**
 * Map the Phase 1 classification onto the SIRProgram's declaration
 * action. Only the three job-creating values reach this function — the
 * `thread_followup` and `not_a_job` cases short-circuit to a
 * `pre-filtered` outcome upstream and never produce a SIRProgram.
 */
function mapJobTypeToAction(kind: EmailJobType): string {
  switch (kind) {
    case 'quote_request':     return 'create_quote_request';
    case 'work_order':        return 'create_work_order';
    case 'maintenance_order': return 'create_maintenance_order';
    case 'thread_followup':
    case 'not_a_job':
      // Defensive fallback — these branches should never reach
      // SIRProgram synthesis; the extract() caller pre-filters them.
      return 'noop';
  }
}

// ── Helpers ──

/**
 * Trim + length-cap the LLM-emitted `point_of_contact`. The prompt
 * asks for under-80-char strings; we cap at 200 defensively (matches
 * the cell-writer's customer_name 200-char cap so a too-long value
 * doesn't surprise the FS-fallback path). Returns undefined for empty
 * or whitespace-only values so downstream resolvers can fall through
 * cleanly to the next priority.
 */
function normalisePointOfContact(raw: string | undefined): string | undefined {
  if (typeof raw !== 'string') return undefined;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return undefined;
  return trimmed.slice(0, 200);
}

/**
 * Coerce a string-or-null-or-undefined into a string-or-null. Empty /
 * whitespace strings collapse to null so the downstream consumers can
 * treat "missing" and "blank" identically.
 */
function nullableString(raw: string | null | undefined): string | null {
  if (typeof raw !== 'string') return null;
  const t = raw.trim();
  return t.length === 0 ? null : t;
}

/**
 * Verbatim WO# from the source PDF. Trim whitespace; null on
 * empty/missing. Operator wants this preserved character-for-character
 * because it's the key the PM uses on their end.
 */
function normaliseWorkOrderNumber(
  raw: string | null | undefined,
): string | null {
  return nullableString(raw);
}

/**
 * Coerce a date string into ISO YYYY-MM-DD. Accepts already-ISO,
 * Australian DD/MM/YYYY, or DD-MM-YYYY. Returns null on anything
 * we can't safely interpret — the prompt instructs the LLM to emit
 * ISO directly so this is mostly a defence-in-depth pass.
 */
function normaliseIsoDate(raw: string | null | undefined): string | null {
  if (typeof raw !== 'string') return null;
  const t = raw.trim();
  if (t.length === 0) return null;
  // Already ISO?
  const iso = t.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return t;
  // DD/MM/YYYY or DD-MM-YYYY → YYYY-MM-DD.
  const au = t.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  if (au) {
    const dd = au[1].padStart(2, '0');
    const mm = au[2].padStart(2, '0');
    const yyyy = au[3];
    return `${yyyy}-${mm}-${dd}`;
  }
  return null;
}

const VALID_CONTACT_ROLES = new Set([
  'tenant', 'agent', 'owner', 'pm', 'other',
]);

/**
 * v0.6 — defensive parser for the LLM's `services` field.
 *
 * Coerces each tag to lowercase, hyphenates whitespace runs, strips
 * non-alphanumeric chars (except `-`), bounds tag length, drops empty
 * strings, and dedupes. Returns `undefined` if the result is empty so
 * the Proposal omits the field entirely (matches the type's optional
 * shape and keeps older readers null-safe).
 *
 * Cap of 8 tags is a defensive bound; the prompt asks for 1-3.
 */
function normaliseServices(raw: unknown): readonly string[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  const seen = new Set<string>();
  for (const t of raw) {
    if (typeof t !== 'string') continue;
    const tag = t
      .toLowerCase()
      .trim()
      .replace(/\s+/g, '-')
      .replace(/[^a-z0-9-]/g, '')
      .slice(0, 64);
    if (tag.length === 0) continue;
    seen.add(tag);
    if (seen.size >= 8) break;
  }
  if (seen.size === 0) return undefined;
  return [...seen];
}

/**
 * Convert the LLM's snake_case contact into the camelCase Proposal
 * shape. Unknown roles collapse to "other". A contact with no name is
 * dropped entirely (the operator can't act on a phone number with no
 * label).
 */
function normaliseContact(raw: EmailExtractionContact | null): ProposalContact | null {
  if (!raw || typeof raw !== 'object') return null;
  const name = nullableString(raw.name);
  if (!name) return null;
  const role = VALID_CONTACT_ROLES.has(raw.role) ? raw.role : 'other';
  return {
    name: name.slice(0, 200),
    role,
    phone: nullableString(raw.phone),
    email: nullableString(raw.email),
  };
}

/**
 * CC6.3a — Encode the operator's billing-party rules per source.
 *
 * The LLM may emit its own guess; we override on conflict with the
 * deterministic source-domain heuristic so the rule stays in one place.
 *
 * Match order:
 *
 *   Phase 1 — sender-domain match (`BillingRule.domain_match`).
 *             First rule whose `domain_match` matches the From-header's
 *             domain fires.
 *
 *   Phase 2 — body-substring fallback (`BillingRule.body_substrings`).
 *             Only reached when Phase 1 didn't match. Used by the
 *             bundle-fan-out case where the From-header is the
 *             operator's own address (so the sender-domain check
 *             produces no match). First rule with a substring match
 *             against the lower-cased body fires.
 *
 *   Phase 3 — trust the LLM's `billing_party` if it emitted a non-empty
 *             value; otherwise return null.
 *
 * All three pre-CC6.3a rules (Clever Property, Robert James Realty,
 * Bricks + Agent) and the body-text fallback they were paired with are
 * expressible as `BillingRule[]` entries in
 * `DEFAULT_ODDJOBZ_ADAPTER_CONFIG`. A new agency = a new entry in the
 * config; no edits to this function are required.
 */
function normaliseBillingParty(
  raw: EmailExtractionBillingParty | null,
  parsed: ParsedEmail,
  ownerName: string | null,
  config: AdapterConfigMetadata,
): ProposalBillingParty | null {
  const senderDomain = extractDomainFromAddress(parsed.from);

  // Phase 1 — sender-domain match.
  if (senderDomain) {
    for (const rule of config.billing_rules) {
      if (matchesDomain(rule.domain_match, senderDomain)) {
        return applyBillingOutcome(rule.outcome, raw, ownerName);
      }
    }
  }

  // Phase 2 — body-substring fallback (bundle-fan-out case).
  const haystack = parsed.body.toLowerCase();
  for (const rule of config.billing_rules) {
    if (!rule.body_substrings || rule.body_substrings.length === 0) continue;
    if (rule.body_substrings.some(s => haystack.includes(s))) {
      return applyBillingOutcome(rule.outcome, raw, ownerName);
    }
  }

  // Phase 3 — trust LLM.
  if (raw && typeof raw === 'object'
      && (raw.type === 'agency' || raw.type === 'owner')
      && nullableString(raw.name)) {
    return { type: raw.type, name: nullableString(raw.name)! };
  }
  return null;
}

function matchesDomain(m: BillingRule['domain_match'], domain: string): boolean {
  if (m.kind === 'ends_with') return domain.endsWith(m.suffix);
  // `regex` patterns are config-supplied — compile once per call (no
  // hot-path concern here; this function is called once per email).
  return new RegExp(m.pattern).test(domain);
}

function applyBillingOutcome(
  outcome: BillingRuleOutcome,
  raw: EmailExtractionBillingParty | null,
  ownerName: string | null,
): ProposalBillingParty {
  switch (outcome.kind) {
    case 'always_agency':
      return { type: 'agency', name: outcome.agency_name };
    case 'owner_if_named_else_agency':
      if (ownerName) return { type: 'owner', name: ownerName };
      return { type: 'agency', name: outcome.agency_name };
    case 'trust_llm_or_fallback_agency':
      if (raw && typeof raw === 'object' && raw.type === 'agency' && nullableString(raw.name)) {
        return { type: 'agency', name: nullableString(raw.name)! };
      }
      return { type: 'agency', name: outcome.agency_name };
  }
}

function extractDomainFromAddress(from: string): string | null {
  if (!from) return null;
  const m = from.match(/<?([^<>\s]+@[^<>\s]+)>?/);
  if (!m) return null;
  const at = m[1].lastIndexOf('@');
  if (at < 0) return null;
  return m[1].slice(at + 1).toLowerCase();
}

function extractEmailAddress(from: string): string | null {
  if (!from) return null;
  const m = from.match(/<?([^<>\s]+@[^<>\s]+)>?/);
  if (!m) return null;
  return m[1].trim().toLowerCase();
}

/**
 * CC6.3a — Bundle detection. Is this From-line one of the operator's
 * own addresses? `OPERATOR_EMAIL` env var takes precedence; the
 * adapter-config's `fallback_operator_emails` supplies the supplementary
 * allow-list (was the deleted `FALLBACK_OPERATOR_EMAILS` constant).
 */
function isOperatorOwnEmail(
  addr: string | null,
  config: AdapterConfigMetadata,
): boolean {
  if (!addr) return false;
  const lc = addr.toLowerCase();
  const env = (typeof process !== 'undefined' ? process.env?.OPERATOR_EMAIL : undefined);
  if (env && lc === env.toLowerCase()) return true;
  return config.fallback_operator_emails.includes(lc);
}

/**
 * Stable blob-store key for the source RawItem. Used as the
 * `sourceAttachmentPath` for the single-shot path. Mirrors the
 * blob-store layout (`legacy-ingest/<provider>/<provider-item-id>`).
 */
function defaultSourcePathFor(item: RawItem): string {
  return `legacy-ingest/${item.providerId}/${item.providerItemId}`;
}

/**
 * Bundle-fan-out source path — appends `#attachment-<n>` so the
 * operator can map back to the exact PDF in the bundle. The `#` form
 * preserves the parent path structure so a future
 * `legacy attachment <provider>:<item>:<n>` verb can split on it.
 */
function bundleSourcePathFor(item: RawItem, attachmentIndex: number): string {
  return `${defaultSourcePathFor(item)}#attachment-${attachmentIndex}`;
}

function cryptoRandomId(): string {
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

/** djb2-ish — deterministic, used only for promptHash; not a security primitive. */
function hashString(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h) + s.charCodeAt(i);
    h = h | 0;
  }
  return `h${(h >>> 0).toString(16)}`;
}

```
