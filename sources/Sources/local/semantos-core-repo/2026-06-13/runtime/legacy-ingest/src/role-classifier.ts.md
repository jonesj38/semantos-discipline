---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/role-classifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.132942+00:00
---

# runtime/legacy-ingest/src/role-classifier.ts

```ts
/**
 * D-RTC.2 — Contact role classifier.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.2.
 *
 * Maps a contact (name + email + phone + surrounding email context) to
 * one of the role enum values the typed customer cell carries:
 *
 *   site_owner | tenant | property_manager | agent | contractor
 *   | witness | unknown
 *
 * Architecture: a heuristic ladder first, then an optional LLM fallback
 * for cases the heuristics can't confidently call. The heuristic side
 * is pure, deterministic, and fast — it covers the high-signal cases
 * (known PM domains, signature-block keywords, explicit body mentions)
 * and produces a structured confidence + reasons trace. The LLM hook
 * is a single async callback matching the existing `ExtractorBackend`
 * shape so the wiring at the worker layer is trivial.
 *
 * Scope (PRD acceptance gate): on 50 hand-labeled email contexts the
 * combined heuristic+LLM classifier must hit ≥80% precision per role
 * with `unknown` rate ≤15%. This file ships the heuristic layer +
 * the LLM seam; the LLM adapter wiring lands with D-RTC.3.
 */

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * The PRD's contact role taxonomy. Note this is BROADER than the
 * existing `ProposalContact.role` (`tenant | agent | owner | pm |
 * other`) — D-RTC.4 (cell encoding) is responsible for the mapping
 * when a legacy proposal flows through to the new customer cell.
 */
export type ContactRole =
  | 'site_owner'
  | 'tenant'
  | 'property_manager'
  | 'agent'
  | 'contractor'
  | 'witness'
  | 'unknown';

/** Input to the classifier — anything we know about the contact. */
export interface ClassifyArgs {
  /** Contact's full name, if extracted. */
  readonly name?: string | null;
  /** Email address, lowercased — domain is the strongest single signal. */
  readonly email?: string | null;
  /** Phone, if extracted. Currently unused but reserved. */
  readonly phone?: string | null;
  /**
   * The last ~5-10 lines of the email body containing job titles +
   * disclaimers. Looked at first because it's where "Property Manager"
   * / "Director" lines typically live.
   */
  readonly signatureBlock?: string | null;
  /**
   * Surrounding email body text. Looked at for "the tenant called",
   * "as the owner of...", "I'm contacting on behalf of..." patterns.
   */
  readonly bodyContext?: string | null;
  /** Where the contact appears in the thread. */
  readonly threadPosition?: 'sender' | 'recipient' | 'mentioned' | null;
  /**
   * Domain of the email's `From:` header, if different from `email`.
   * Useful when the contact is mentioned in body but the sender is a
   * PM forwarding the message.
   */
  readonly senderDomain?: string | null;
}

/** Classifier output — role + structured confidence trace. */
export interface ClassifyResult {
  readonly role: ContactRole;
  /** 0.0 (no signal) … 1.0 (strong, unambiguous). */
  readonly confidence: number;
  /** Human-readable reasons. Useful for ratification-UI tooltips. */
  readonly reasons: readonly string[];
}

/**
 * Async LLM fallback hook. The worker layer wires this to the same
 * `LLMAdapter` the extractor uses (Ollama → Anthropic → OpenRouter).
 *
 * Return `null` if the LLM can't decide (the classifier then returns
 * `unknown`). Never throw — the worker's at-edge error handling needs
 * the classifier to remain a pure function from its caller's POV.
 */
export type RoleLLMFallback = (args: ClassifyArgs) => Promise<ClassifyResult | null>;

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Confidence threshold above which the heuristic result is trusted
 * without consulting the LLM. Below this, the classifier consults the
 * LLM (if provided) and uses its result if higher-confidence.
 *
 * 0.7 chosen empirically: a domain match alone (0.6) is not strong
 * enough to skip the LLM; a domain match + signature keyword (0.85+)
 * is.
 */
const HEURISTIC_TRUST_FLOOR = 0.7;

/**
 * Pure-function heuristic classifier — no IO, no LLM. Returns the
 * best guess + confidence based on email domain, signature block,
 * and body context patterns.
 *
 * Designed to be cheap enough to run on every contact in the corpus
 * so the LLM fallback only fires on the ambiguous tail.
 */
export function classifyRoleHeuristic(args: ClassifyArgs): ClassifyResult {
  const reasons: string[] = [];
  const scores: Record<ContactRole, number> = {
    site_owner: 0,
    tenant: 0,
    property_manager: 0,
    agent: 0,
    contractor: 0,
    witness: 0,
    unknown: 0,
  };

  // ── Domain signal ──────────────────────────────────────────────────
  const domain = extractDomain(args.email);
  if (domain !== null) {
    const dr = classifyDomain(domain);
    if (dr !== null) {
      scores[dr.role] += dr.weight;
      reasons.push(`domain '${domain}' → ${dr.role} (${dr.weight.toFixed(2)})`);
    }
  }

  // ── Signature-block keywords ───────────────────────────────────────
  if (args.signatureBlock) {
    const sigHits = scanSignature(args.signatureBlock);
    for (const hit of sigHits) {
      scores[hit.role] += hit.weight;
      reasons.push(
        `signature '${hit.match}' → ${hit.role} (${hit.weight.toFixed(2)})`,
      );
    }
  }

  // ── Body context ───────────────────────────────────────────────────
  if (args.bodyContext) {
    const bodyHits = scanBody(args.bodyContext, args.name ?? null);
    for (const hit of bodyHits) {
      scores[hit.role] += hit.weight;
      reasons.push(
        `body '${hit.match}' → ${hit.role} (${hit.weight.toFixed(2)})`,
      );
    }
  }

  // ── Pick the best ──────────────────────────────────────────────────
  const ranked = (Object.keys(scores) as ContactRole[])
    .filter(r => r !== 'unknown')
    .sort((a, b) => scores[b] - scores[a]);
  const best = ranked[0];
  const bestScore = best ? scores[best] : 0;
  const secondBestScore = ranked[1] ? scores[ranked[1]] : 0;

  // If nothing scored, or the top score is very weak, return unknown.
  if (!best || bestScore < 0.4) {
    return {
      role: 'unknown',
      confidence: 0,
      reasons: reasons.length > 0 ? reasons : ['no role signals found'],
    };
  }

  // Confidence: scale by the gap between #1 and #2. A clear winner
  // (gap ≥ 0.4) gets full credit; close calls get penalised.
  const gap = bestScore - secondBestScore;
  const confidence = Math.min(1, bestScore * (0.7 + Math.min(0.3, gap)));

  return { role: best, confidence, reasons };
}

/**
 * Top-level classifier: heuristic first, LLM fallback if confidence
 * below the trust floor. Returns `unknown` if neither path is
 * confident — operators get those flagged for manual review at
 * ratification time.
 */
export async function classifyRole(
  args: ClassifyArgs,
  llmFallback?: RoleLLMFallback,
): Promise<ClassifyResult> {
  const heuristic = classifyRoleHeuristic(args);
  if (heuristic.confidence >= HEURISTIC_TRUST_FLOOR) return heuristic;
  if (!llmFallback) return heuristic;

  let llm: ClassifyResult | null = null;
  try {
    llm = await llmFallback(args);
  } catch {
    // Per RoleLLMFallback contract the callback should not throw, but
    // defensive: a thrown LLM error must not corrupt the classifier.
    llm = null;
  }
  if (llm === null) return heuristic;
  if (llm.confidence >= heuristic.confidence) return llm;
  return heuristic;
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals
 * ────────────────────────────────────────────────────────────────────── */

function extractDomain(email: string | null | undefined): string | null {
  if (!email) return null;
  const at = email.indexOf('@');
  if (at < 0 || at === email.length - 1) return null;
  return email.slice(at + 1).toLowerCase().trim();
}

interface DomainSignal { role: ContactRole; weight: number; }

/**
 * Map an email domain to a role + weight. Heavy domains (known PM
 * platforms) get 0.85; the personal-email "leans tenant/owner but
 * ambiguous" case gets a low 0.2 nudge that body context can override.
 */
function classifyDomain(domain: string): DomainSignal | null {
  // Known property-manager / real-estate platforms.
  if (/(?:cleverproperty|clever-property)\./i.test(domain)) {
    return { role: 'property_manager', weight: 0.85 };
  }
  if (/raywhite\./i.test(domain) ||
      /harcourts\./i.test(domain) ||
      /mcgrath\./i.test(domain) ||
      /lj\.com\.au/i.test(domain) ||
      /ljhooker\./i.test(domain) ||
      /belleproperty\./i.test(domain)) {
    return { role: 'property_manager', weight: 0.7 };
  }
  // Robert James Realty — operator's primary referrer per WALLET-LEGACY-INGEST
  if (/robertjames|rjr\./i.test(domain)) {
    return { role: 'agent', weight: 0.75 };
  }
  if (/\.realty(\.|$)/i.test(domain) ||
      /realestate\./i.test(domain) ||
      /\.realestate(\.|$)/i.test(domain)) {
    return { role: 'agent', weight: 0.6 };
  }
  // Contractor / trades indicators.
  if (/(?:plumbing|electrical|builder|roofing|tradies|construction)/i.test(domain)) {
    return { role: 'contractor', weight: 0.7 };
  }
  // Personal email providers — weak signal toward tenant/site_owner.
  // The body context will dominate.
  if (/^(?:gmail|outlook|hotmail|yahoo|icloud|bigpond|live|me)\.com/i.test(domain) ||
      /^gmail\.com$/i.test(domain) ||
      /^hotmail\.com$/i.test(domain) ||
      /^bigpond\.com$/i.test(domain) ||
      /^bigpond\.net\.au$/i.test(domain) ||
      /^yahoo\.com\.au$/i.test(domain)) {
    return { role: 'tenant', weight: 0.2 };
  }
  return null;
}

interface KeywordHit { role: ContactRole; weight: number; match: string; }

/**
 * Signature-block keyword scan. The signature is where job titles live
 * ("Property Manager", "Director", "Owner", "Tenant"). High weight
 * because the signature line is where someone declares their role
 * explicitly.
 */
function scanSignature(sig: string): KeywordHit[] {
  const text = sig.toLowerCase();
  const hits: KeywordHit[] = [];

  const patterns: Array<{ rx: RegExp; role: ContactRole; weight: number }> = [
    { rx: /\bproperty\s+manager\b/i, role: 'property_manager', weight: 0.9 },
    { rx: /\bleasing\s+(?:consultant|manager|officer)\b/i, role: 'property_manager', weight: 0.85 },
    { rx: /\bsenior\s+pm\b/i, role: 'property_manager', weight: 0.85 },
    { rx: /\breal\s+estate\s+agent\b/i, role: 'agent', weight: 0.85 },
    { rx: /\bsales\s+(?:consultant|agent|associate)\b/i, role: 'agent', weight: 0.7 },
    { rx: /\bprincipal\b/i, role: 'agent', weight: 0.55 },
    { rx: /\blandlord\b/i, role: 'site_owner', weight: 0.85 },
    { rx: /\bowner\b/i, role: 'site_owner', weight: 0.55 },
    { rx: /\binvestor\b/i, role: 'site_owner', weight: 0.5 },
    { rx: /\btenant\b/i, role: 'tenant', weight: 0.8 },
    { rx: /\b(?:plumber|electrician|carpenter|builder|tradesperson|tradie)\b/i, role: 'contractor', weight: 0.85 },
    { rx: /\b(?:plumbing|electrical|construction|roofing)\b/i, role: 'contractor', weight: 0.6 },
  ];

  for (const p of patterns) {
    const m = text.match(p.rx);
    if (m) hits.push({ role: p.role, weight: p.weight, match: m[0] });
  }
  return hits;
}

/**
 * Body-context scan. Lower individual weights than signatures —
 * "the tenant" might describe somebody else, not the contact in
 * question. The classifier combines body + signature signals.
 */
function scanBody(body: string, _name: string | null): KeywordHit[] {
  // _name is reserved for a future "match within N words of contact's
  // name" check — for now we treat every body mention as evidence the
  // role is in play for SOMEBODY in this thread, which still beats no
  // signal.
  const text = body.toLowerCase();
  const hits: KeywordHit[] = [];

  const patterns: Array<{ rx: RegExp; role: ContactRole; weight: number; label: string }> = [
    { rx: /\b(?:i'?m|i\s+am)\s+the\s+tenant\b/i, role: 'tenant', weight: 0.85, label: "i'm the tenant" },
    { rx: /\b(?:i'?m|i\s+am)\s+the\s+owner\b/i, role: 'site_owner', weight: 0.85, label: "i'm the owner" },
    { rx: /\b(?:i'?m|i\s+am)\s+the\s+landlord\b/i, role: 'site_owner', weight: 0.85, label: "i'm the landlord" },
    { rx: /\b(?:i'?m|i\s+am)\s+a\s+witness\b/i, role: 'witness', weight: 0.9, label: "i'm a witness" },
    { rx: /\bthe\s+tenant\s+(?:has|called|reported|advised|will)\b/i, role: 'tenant', weight: 0.5, label: 'the tenant (3p)' },
    { rx: /\bthe\s+owner\s+(?:has|wants|requested|advised|will)\b/i, role: 'site_owner', weight: 0.5, label: 'the owner (3p)' },
    { rx: /\bon\s+behalf\s+of\s+the\s+owner\b/i, role: 'agent', weight: 0.55, label: 'on behalf of the owner' },
    { rx: /\bas\s+(?:a\s+|the\s+)?witness\b/i, role: 'witness', weight: 0.8, label: 'as witness' },
    { rx: /\b(?:our|the)\s+plumber\b/i, role: 'contractor', weight: 0.6, label: 'the plumber' },
    { rx: /\b(?:our|the)\s+(?:electrician|builder|tradie|contractor)\b/i, role: 'contractor', weight: 0.6, label: 'the contractor' },
    { rx: /\b(?:property\s+manager|managing\s+agent)\b/i, role: 'property_manager', weight: 0.7, label: 'property manager (body)' },
  ];

  for (const p of patterns) {
    const m = text.match(p.rx);
    if (m) hits.push({ role: p.role, weight: p.weight, match: p.label });
  }
  return hits;
}

```
