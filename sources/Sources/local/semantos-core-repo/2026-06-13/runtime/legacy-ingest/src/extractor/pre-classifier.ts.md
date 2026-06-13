---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/pre-classifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.158730+00:00
---

# runtime/legacy-ingest/src/extractor/pre-classifier.ts

```ts
/**
 * Pre-classifier — drops obvious non-business content before invoking
 * the LLM. Conservative — better to send a borderline item to the
 * extractor than to silently drop a real lead.
 *
 * Pattern after `oddjobtodd/src/lib/ai/classifiers/estimateAcknowledgementClassifier.ts`
 * but generalised: a chain of cheap heuristics over the raw bytes +
 * metadata. Non-LLM. Tests assert the heuristics individually.
 *
 * D-RTC.7-followup — optional sender-allowlist mode. The OJT reingest
 * use case wants to filter the entire gmail corpus down to the THREE
 * known business sources (Clever Property, Robert James Realty, and
 * Todd's own forwards-of-Clever-bundles). When `senderAllowlist` is
 * supplied, anything outside that set is dropped BEFORE the
 * heuristics fire — same dropped-items log surface, just an earlier
 * gate. Backward-compatible: omit the option and behaviour is
 * unchanged.
 */

import type { RawItem } from '../types';

export interface PreClassification {
  /** True if the extractor should run. */
  readonly shouldExtract: boolean;
  /** Set when shouldExtract = false; surfaces in the dropped-items log. */
  readonly droppedReason?: string;
  /** Soft hint to the extractor — strong signals on what type of message this is. */
  readonly hints?: Readonly<Record<string, string>>;
}

/** Per-call options. Omit fields to keep their default behaviour. */
export interface PreClassifyOptions {
  /**
   * When supplied, the From header (or item.metadata.from / .sender)
   * MUST match at least one of these patterns OR
   * `selfForwardAddresses` for the item to be extracted. Anything
   * else drops with `sender not in allowlist` reason.
   *
   * Patterns match against the bare email-address tail when a
   * "Name <email@domain>" header is present, otherwise against the
   * whole sender string. Case-insensitive.
   */
  readonly senderAllowlist?: readonly RegExp[];
  /**
   * Self-forward addresses. These bypass the senderAllowlist (the
   * operator may forward third-party PM emails to themselves to
   * batch-process them; `email.ts` already fans-out per-PDF when it
   * recognises one of these in the From header).
   */
  readonly selfForwardAddresses?: readonly string[];
}

/**
 * OJT canonical allowlist. Mirrors what the reingest worker should
 * filter the gmail corpus down to. Exported so the host can pass it
 * verbatim, override with their own, or extend.
 *
 *   • Robert James Realty (robertjamesrealty.com.au, rjr.*)
 *   • Bricks + Agent dispatch (bricksandagent.com) — multi-PM
 *     dispatch platform; carries job tickets from multiple
 *     property-management agencies including Clever Property.
 *     The v0.6 prompt drops Bricks weekly-digest emails server-side
 *     via job_type=not_a_job classification; the LLM call still
 *     fires for each but produces a pre-filtered receipt.
 *   • Clever Property (cleverproperty.com.au, clever-property.com.au)
 *     — direct emails (rare; most route via Bricks)
 *   • Todd's gmail (forwarded Clever-Property bundles — covered by
 *     `selfForwardAddresses` argument, not by these patterns)
 */
export const OJT_SENDER_ALLOWLIST: readonly RegExp[] = [
  /@cleverproperty\.com\.au$/i,
  /@clever-property\.com\.au$/i,
  /@robertjamesrealty\.com\.au$/i,
  /@rjr\.(?:com\.au|com)$/i,
  /@bricksandagent\.com$/i,
];

/** Default self-forward addresses for the OJT operator. */
export const OJT_SELF_FORWARD_ADDRESSES: readonly string[] = [
  'todd.price.aus@gmail.com',
  'todd@oddjobtodd.com.au',
];

const NEWSLETTER_RE = /\b(unsubscribe|newsletter|email preferences|promotional)\b/i;
const NOREPLY_RE = /\bno-?reply@|do-?not-?reply@\b/i;
const RECEIPT_RE = /\b(receipt|order confirmation|payment confirmation|invoice paid)\b/i;
const NOTIFICATION_RE = /\b(security alert|sign-?in alert|verification code|2fa code|verify your)\b/i;

/**
 * Classify by inspecting the raw item's bytes + metadata. The
 * heuristics here are conservative — when in doubt we let the LLM
 * decide. Drops only what is unambiguously non-business.
 */
export function classifyForExtraction(
  item: RawItem,
  opts: PreClassifyOptions = {},
): PreClassification {
  const sender = extractSender(item);
  if (NOREPLY_RE.test(sender)) {
    return {
      shouldExtract: false,
      droppedReason: `noreply sender: ${sender}`,
    };
  }

  // Sender-allowlist gate — when configured, this fires BEFORE the
  // body-content heuristics so we don't burn cycles parsing 4 KiB of
  // headers from messages we'd reject anyway.
  if (opts.senderAllowlist && opts.senderAllowlist.length > 0) {
    if (!senderAllowed(sender, opts.senderAllowlist, opts.selfForwardAddresses ?? [])) {
      return {
        shouldExtract: false,
        droppedReason: `sender not in allowlist: ${sender || '(empty)'}`,
      };
    }
  }

  if (item.contentType === 'email/rfc822' && item.bytes.length > 0) {
    const head = decodeHead(item.bytes);
    if (NEWSLETTER_RE.test(head)) {
      return { shouldExtract: false, droppedReason: 'newsletter signal in headers' };
    }
    if (RECEIPT_RE.test(head)) {
      return { shouldExtract: false, droppedReason: 'machine-generated receipt' };
    }
    if (NOTIFICATION_RE.test(head)) {
      return { shouldExtract: false, droppedReason: 'platform notification' };
    }
    return { shouldExtract: true, hints: { surface: 'email' } };
  }

  return { shouldExtract: true };
}

/**
 * Pull the From / sender out of the item's metadata, falling back to
 * parsing the rfc822 From line out of the first 4 KiB when only the
 * raw bytes are present. Gmail provider populates `metadata.from`;
 * other providers may not.
 */
function extractSender(item: RawItem): string {
  const m = (item.metadata.from ?? item.metadata.sender ?? '').toString();
  if (m.length > 0) return m;
  if (item.contentType === 'email/rfc822' && item.bytes.length > 0) {
    const head = decodeHead(item.bytes);
    // Match `From:` header on its own line. RFC 5322 unfolding isn't
    // strictly needed here — the From line is rarely folded.
    const fromLine = /^from:\s*(.+)$/im.exec(head);
    if (fromLine && fromLine[1]) return fromLine[1].trim();
  }
  return '';
}

/**
 * `True` when the sender matches an allowlist regex OR equals one of
 * the self-forward addresses. The address extraction tolerates the
 * standard `Name <email@domain>` form.
 */
function senderAllowed(
  sender: string,
  allowlist: readonly RegExp[],
  selfForwards: readonly string[],
): boolean {
  const addr = extractAddress(sender);
  // Self-forward: equality on the bare address (case-insensitive).
  const lowered = addr.toLowerCase();
  for (const sf of selfForwards) {
    if (lowered === sf.toLowerCase()) return true;
  }
  // Allowlist patterns match against both the bare address and the
  // raw header string — operators sometimes write `From: Clever
  // Property <noreply@cleverproperty.com.au>` and we want either form
  // to fire the same allowlist entry.
  for (const rx of allowlist) {
    if (rx.test(addr) || rx.test(sender)) return true;
  }
  return false;
}

/** Extract the `email@domain` from `Name <email@domain>` or return as-is. */
function extractAddress(sender: string): string {
  const m = /<([^>]+)>/.exec(sender);
  if (m && m[1]) return m[1].trim();
  return sender.trim();
}

function decodeHead(bytes: Uint8Array): string {
  // Inspect headers + first 16 KiB. Original cap was 4 KiB but gmail
  // emails frequently exceed that in the Received / ARC-Seal /
  // DKIM-Signature header block before reaching the `From:` line —
  // 4 KiB silently missed the sender on ~65% of an OJT corpus
  // sample. 16 KiB is empirically sufficient for the worst real-world
  // header bloat we've observed without changing the body-scan
  // semantics of newsletter/receipt/notification detection.
  const slice = bytes.subarray(0, Math.min(bytes.length, 16384));
  return new TextDecoder('utf-8', { fatal: false }).decode(slice);
}

```
