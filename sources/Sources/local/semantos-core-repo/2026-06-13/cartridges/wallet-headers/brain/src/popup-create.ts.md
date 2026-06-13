---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-create.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.654743+00:00
---

# cartridges/wallet-headers/brain/src/popup-create.ts

```ts
// Popup screen — first-time wallet creation (W9, design §7.6 v0.4 + UX hardening).
//
// Pure-state module + DOM hydration helper. The pure-state pieces are
// directly testable under bun without a real DOM; the DOM hydration is a
// thin shell that calls into them on `submit`.
//
// v0.4 architectural correction (per WALLET-TIER-CUSTODY.md §4.0):
//
// The recovery layer is built mandatorily at creation. Three challenge
// questions/answers + a contact email are required inputs — they are the
// user's offline recovery knowledge (replacing the legacy mnemonic-phrase
// recall). The seed itself is never shown.
//
// The dispatch envelope is constructed locally for every wallet, encrypted
// under PBKDF2 of the normalized challenge answers. Plexus enrollment
// (popup-plexus.ts) is just deciding to also transmit it.
//
// v0.4 UX hardening:
//   • Retype-to-confirm each challenge answer (typos at creation =
//     unrecoverable wallets). Mismatch surfaces an inline error and
//     blocks submission.
//   • "Will be stored as: …" affordance shows the user the normalized
//     form their wallet will hash + encrypt-under, so they can see what
//     they'll need to retype on recovery.
//   • Hard-block rules: empty-after-normalize, two answers normalize to
//     the same string, answer normalizes equal to the question text.
//   • Soft-warn rules: single-word answers (< 2 whitespace tokens after
//     normalize), all-numeric short answers (length < 8) — advisory only.
//   • Post-create banner now includes the WT-Transport picker so the
//     user can mirror the envelope to multiple targets.
//
// Flow:
//   1. User clicks "Create wallet".
//   2. User enters their three challenge questions + answers (twice each,
//      retype-to-confirm), contact email.
//   3. User enters a Tier-1 PIN, an optional Tier-2 factor, an optional
//      Tier-3 factor (the daily-use layer per §4.1).
//   4. wallet-ops.createWallet() generates a CSPRNG seed internally,
//      derives identity + tier base keys, builds the dispatch envelope,
//      persists everything, and wipes the seed.
//   5. Banner: value-cap explainer + "Back up your recovery envelope"
//      picker (Plexus / WT-Transport / Download / Copy).

import { createWallet, type CreateWalletResult, type WalletError, type Result } from './wallet-ops';
import type { PlexusOperator } from './plexus';
import { normalizeAnswer } from './plexus/envelope';
import {
  defaultTransports,
  serializeEnvelope,
  type EnvelopeTransport,
  type TransportResult,
} from './transport';

export interface CreateScreenInputs {
  /** Three challenge questions — the user picks or accepts canonical
   *  questions ("Mother's maiden name?", "City of birth?", "First pet?").
   *  Required. */
  challengeQuestions: [string, string, string];
  /** Three plaintext challenge answers, same order as the questions.
   *  The user MUST remember these. They never leave the device in
   *  plaintext (they're salt-hashed for the envelope and used to
   *  derive the seed-encryption KEK via PBKDF2-100k). Required. */
  challengeAnswers: [string, string, string];
  /** Optional: retype-to-confirm copies of the answers. When present,
   *  validateAnswers requires each pair to match before the create flow
   *  proceeds. The DOM shell always supplies these; pre-existing test
   *  callers omit them and skip the retype check. */
  challengeAnswersConfirm?: [string, string, string];
  /** Contact email — used as Plexus rate-limit key + OTP destination if
   *  the user later enrolls. Held locally regardless. Required. */
  contactEmail: string;
  /** UTF-8 PIN entered by the user (Tier-1 daily-use factor). Required. */
  tier1Pin: string;
  /** Optional Tier-2 factor — passphrase string in v0.1; in production a
   *  WebAuthn assertion's signature bytes are used instead. */
  tier2Factor?: string;
  /** Optional Tier-3 vault factor (passphrase ⊕ biometric). */
  tier3Factor?: string;
}

/** A canonical set the create screen offers if the user doesn't write their
 *  own. Sourced from common security-question conventions; the user is
 *  invited to override with their own questions for better unguessability. */
export const DEFAULT_CHALLENGE_QUESTIONS: [string, string, string] = [
  "Mother's maiden name?",
  'City of birth?',
  'First pet?',
];

// ──────────────────────────────────────────────────────────────────────
// Pure-state validation — retype-confirm, hard-blocks, soft-warns.
//
// Tested directly without a DOM. The DOM shell calls
// `validateChallengeAnswers` on every input event to live-update the
// inline status, and again on submit to gate the create call.
// ──────────────────────────────────────────────────────────────────────

export type AnswerHardError =
  | { kind: 'EMPTY' }
  | { kind: 'MISMATCH' }
  | { kind: 'DUPLICATE_OF'; otherIndex: number }
  | { kind: 'EQUALS_QUESTION' };

export type AnswerSoftWarning =
  | { kind: 'SINGLE_WORD' }
  | { kind: 'SHORT_NUMERIC' };

export interface AnswerCheck {
  /** The text the wallet will actually hash + encrypt-under, after
   *  Unicode/whitespace normalization. */
  normalized: string;
  /** Hard errors — the create button must stay disabled while any of
   *  these are non-empty. */
  errors: AnswerHardError[];
  /** Soft warnings — advisory only, render below the field. */
  warnings: AnswerSoftWarning[];
}

export interface ChallengeValidation {
  perAnswer: [AnswerCheck, AnswerCheck, AnswerCheck];
  /** Convenience: true iff every per-answer `errors` array is empty. */
  ok: boolean;
}

/**
 * Run the hard-block + soft-warn rules across all three challenge slots.
 * Pure: no DOM access, no network. Caller is responsible for rendering.
 *
 * Hard-block rules (each ⇒ AnswerHardError on the affected slot):
 *   1. Empty / whitespace-only after `normalizeAnswer`.
 *   2. retype-confirm copy doesn't match the primary entry.
 *   3. Two slots normalize to the same string (defeats per-answer entropy
 *      — hash and KEK become deterministically reducible).
 *   4. Answer normalizes equal to the question text (the most common
 *      "lazy" failure mode — user retypes the question).
 *
 * Soft-warn rules (advisory; do NOT block):
 *   • Single-token answer (< 2 whitespace-separated words after normalize).
 *   • All-numeric, length < 8 (short PIN-like answers).
 */
export function validateChallengeAnswers(
  questions: [string, string, string],
  answers: [string, string, string],
  confirms?: [string, string, string],
): ChallengeValidation {
  const norm = answers.map(normalizeAnswer) as [string, string, string];
  const normQuestions = questions.map(normalizeAnswer);

  const perAnswer: AnswerCheck[] = [];
  for (let i = 0; i < 3; i++) {
    const errors: AnswerHardError[] = [];
    const warnings: AnswerSoftWarning[] = [];

    // Hard 1 — empty after normalize.
    if (norm[i]!.length === 0) {
      errors.push({ kind: 'EMPTY' });
    }

    // Hard 2 — retype-confirm mismatch (only when confirms supplied).
    if (confirms && confirms[i] !== answers[i]) {
      errors.push({ kind: 'MISMATCH' });
    }

    // Hard 3 — duplicate-of-another-slot.
    if (norm[i]!.length > 0) {
      for (let j = 0; j < 3; j++) {
        if (j === i) continue;
        if (norm[j]!.length === 0) continue;
        if (norm[j] === norm[i]) {
          errors.push({ kind: 'DUPLICATE_OF', otherIndex: j });
          break;
        }
      }
    }

    // Hard 4 — equals the question itself.
    if (norm[i]!.length > 0 && norm[i] === normQuestions[i]) {
      errors.push({ kind: 'EQUALS_QUESTION' });
    }

    // Soft 1 — single token.
    if (norm[i]!.length > 0) {
      const tokenCount = norm[i]!.split(/\s+/).filter((s) => s.length > 0).length;
      if (tokenCount < 2) {
        warnings.push({ kind: 'SINGLE_WORD' });
      }
    }

    // Soft 2 — short all-numeric.
    if (norm[i]!.length > 0 && /^[0-9]+$/.test(norm[i]!) && norm[i]!.length < 8) {
      warnings.push({ kind: 'SHORT_NUMERIC' });
    }

    perAnswer.push({ normalized: norm[i]!, errors, warnings });
  }

  return {
    perAnswer: perAnswer as [AnswerCheck, AnswerCheck, AnswerCheck],
    ok: perAnswer.every((p) => p.errors.length === 0),
  };
}

/**
 * Render a single hard-error code to a short, human-friendly string.
 * Lives here (not in the DOM shell) so tests can assert the exact text.
 */
export function describeAnswerError(e: AnswerHardError): string {
  switch (e.kind) {
    case 'EMPTY':
      return 'Answer required.';
    case 'MISMATCH':
      return 'Doesn\'t match — please retype both fields.';
    case 'DUPLICATE_OF':
      return `Same as answer #${e.otherIndex + 1} — pick a different value.`;
    case 'EQUALS_QUESTION':
      return 'Answer is the same as the question — pick a different value.';
  }
}

export function describeAnswerWarning(w: AnswerSoftWarning): string {
  switch (w.kind) {
    case 'SINGLE_WORD':
      return 'Tip: short answers are easier to remember and easier to guess.';
    case 'SHORT_NUMERIC':
      return 'Tip: short numeric answers are easier to remember and easier to guess.';
  }
}

// ──────────────────────────────────────────────────────────────────────
// runCreateFlow — call into wallet-ops after the validation gate.
// ──────────────────────────────────────────────────────────────────────

/**
 * Run the create-wallet flow with the inputs the user typed. Returns the
 * createWallet Result verbatim — caller (DOM shell or test harness) renders
 * either the post-create banner or an error.
 *
 * The challenge answers are wiped from the inputs object after createWallet
 * returns. The caller should treat the inputs argument as consumed.
 *
 * v0.4 UX hardening: when `challengeAnswersConfirm` is supplied, the
 * retype-confirm + hard-block rules are enforced here in addition to
 * createWallet's own validation. Pre-existing callers without
 * `challengeAnswersConfirm` keep the prior behavior (retype check skipped;
 * wallet-ops still rejects empty / non-email / etc.).
 */
export async function runCreateFlow(
  inputs: CreateScreenInputs,
): Promise<Result<CreateWalletResult, WalletError>> {
  // Validate the challenge layer first — these are the most likely UI
  // mistakes (empty answers, missing email).
  if (
    inputs.challengeQuestions.length !== 3 ||
    inputs.challengeQuestions.some((q) => !q || q.trim().length === 0)
  ) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'Three challenge questions required' } };
  }
  if (
    inputs.challengeAnswers.length !== 3 ||
    inputs.challengeAnswers.some((a) => !a || a.trim().length === 0)
  ) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'Three challenge answers required' } };
  }
  if (!inputs.contactEmail || !inputs.contactEmail.includes('@')) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'Contact email required' } };
  }
  if (!inputs.tier1Pin || inputs.tier1Pin.length === 0) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'Tier-1 PIN required' } };
  }

  // v0.4 UX hardening: hard-block rules. Run only when the caller supplies
  // confirms (i.e., they've opted into the retype-confirm UX). Pre-existing
  // tests/callers without confirms keep the loose path — wallet-ops still
  // rejects empty inputs.
  if (inputs.challengeAnswersConfirm) {
    const v = validateChallengeAnswers(
      inputs.challengeQuestions,
      inputs.challengeAnswers,
      inputs.challengeAnswersConfirm,
    );
    if (!v.ok) {
      // Pick the first slot with an error and surface its first code as
      // the BAD_INPUT reason. The DOM layer renders the per-slot detail
      // separately via the same `validateChallengeAnswers` call.
      for (let i = 0; i < 3; i++) {
        const e = v.perAnswer[i]!.errors[0];
        if (e) {
          return {
            ok: false,
            error: { kind: 'BAD_INPUT', reason: `answer #${i + 1}: ${describeAnswerError(e)}` },
          };
        }
      }
    }
  }

  const enc = new TextEncoder();
  const result = await createWallet({
    challengeQuestions: inputs.challengeQuestions,
    challengeAnswers: inputs.challengeAnswers,
    contactEmail: inputs.contactEmail,
    tier1Pin: enc.encode(inputs.tier1Pin),
    tier2Factor: inputs.tier2Factor ? enc.encode(inputs.tier2Factor) : new Uint8Array(0),
    tier3Factor: inputs.tier3Factor ? enc.encode(inputs.tier3Factor) : new Uint8Array(0),
  });

  // Wipe the answers from the caller's reference. createWallet also wipes
  // its own copy; this is defense in depth so a stale UI reference can't
  // leak the recovery secret.
  inputs.challengeAnswers[0] = '';
  inputs.challengeAnswers[1] = '';
  inputs.challengeAnswers[2] = '';
  if (inputs.challengeAnswersConfirm) {
    inputs.challengeAnswersConfirm[0] = '';
    inputs.challengeAnswersConfirm[1] = '';
    inputs.challengeAnswersConfirm[2] = '';
  }

  return result;
}

/**
 * Pure-state: format the recovery banner price hint from a Plexus operator's
 * `/info` response. Falls back to "$X" if the operator is unreachable.
 *
 * Returns the human-readable string the create screen should put in the
 * "Enroll in recovery for X / year" CTA — no DOM access, fully testable.
 */
export async function fetchRecoveryPriceHint(operator: PlexusOperator | null): Promise<string> {
  if (!operator) return '$X / year';
  try {
    const resp = await operator.info();
    if (resp.status !== 200) return '$X / year';
    const body = resp.body as { annualPriceSats?: number } | null;
    const sats = body?.annualPriceSats ?? 0;
    if (sats === 0) return '$X / year';
    return `${sats.toLocaleString()} sats / year`;
  } catch {
    return '$X / year';
  }
}

/**
 * Hydrate the DOM-side create form. Idempotent — safe to call multiple
 * times. The form's inputs are read into `runCreateFlow`; on success, the
 * post-create banner is rendered (value-cap explainer + WT-Transport
 * picker) and the screen-router is told to advance to the status panel.
 */
export function mountCreateScreen(
  onCreated?: (result: CreateWalletResult) => void,
  onError?: (msg: string) => void,
): void {
  if (typeof document === 'undefined') return;
  const form = document.getElementById('create-form') as HTMLFormElement | null;
  if (!form) return;

  // Live validation: re-run validateChallengeAnswers on input/blur and
  // update the per-slot status div (#challenge-status-{i}). Skip silently
  // if the status spans aren't present (older HTML).
  const liveValidate = (): void => {
    const fd = new FormData(form);
    const qs: [string, string, string] = [
      ((fd.get('challengeQuestion0') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[0]).trim(),
      ((fd.get('challengeQuestion1') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[1]).trim(),
      ((fd.get('challengeQuestion2') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[2]).trim(),
    ];
    const as: [string, string, string] = [
      (fd.get('challengeAnswer0') as string) ?? '',
      (fd.get('challengeAnswer1') as string) ?? '',
      (fd.get('challengeAnswer2') as string) ?? '',
    ];
    const cs: [string, string, string] = [
      (fd.get('challengeAnswerConfirm0') as string) ?? '',
      (fd.get('challengeAnswerConfirm1') as string) ?? '',
      (fd.get('challengeAnswerConfirm2') as string) ?? '',
    ];
    const v = validateChallengeAnswers(qs, as, cs);
    for (let i = 0; i < 3; i++) {
      const status = document.getElementById(`challenge-status-${i}`);
      if (!status) continue;
      const slot = v.perAnswer[i]!;
      if (slot.errors.length > 0) {
        status.textContent = describeAnswerError(slot.errors[0]!);
        status.dataset.tone = 'error';
      } else if (as[i] !== '' && cs[i] !== '' && as[i] === cs[i]) {
        const tip = slot.warnings.length > 0 ? ` ${describeAnswerWarning(slot.warnings[0]!)}` : '';
        status.textContent = `Will be stored as: "${slot.normalized}" (lowercased, whitespace trimmed)${tip}`;
        status.dataset.tone = slot.warnings.length > 0 ? 'warn' : 'ok';
      } else {
        status.textContent = '';
        status.dataset.tone = '';
      }
    }
  };
  // Hook every challenge input to re-validate.
  for (let i = 0; i < 3; i++) {
    const a = form.elements.namedItem(`challengeAnswer${i}`) as HTMLInputElement | null;
    const c = form.elements.namedItem(`challengeAnswerConfirm${i}`) as HTMLInputElement | null;
    a?.addEventListener('input', liveValidate);
    c?.addEventListener('input', liveValidate);
  }

  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const fd = new FormData(form);

    // Three challenge questions + answers. The form has fields named
    // challengeQuestion0..2 and challengeAnswer0..2 plus the optional
    // retype-confirm pair challengeAnswerConfirm0..2.
    const challengeQuestions: [string, string, string] = [
      ((fd.get('challengeQuestion0') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[0]).trim(),
      ((fd.get('challengeQuestion1') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[1]).trim(),
      ((fd.get('challengeQuestion2') as string) ?? DEFAULT_CHALLENGE_QUESTIONS[2]).trim(),
    ];
    const challengeAnswers: [string, string, string] = [
      ((fd.get('challengeAnswer0') as string) ?? '').trim(),
      ((fd.get('challengeAnswer1') as string) ?? '').trim(),
      ((fd.get('challengeAnswer2') as string) ?? '').trim(),
    ];
    const challengeAnswersConfirm: [string, string, string] = [
      ((fd.get('challengeAnswerConfirm0') as string) ?? '').trim(),
      ((fd.get('challengeAnswerConfirm1') as string) ?? '').trim(),
      ((fd.get('challengeAnswerConfirm2') as string) ?? '').trim(),
    ];
    const contactEmail = ((fd.get('contactEmail') as string) ?? '').trim();
    const tier1Pin = (fd.get('tier1Pin') as string) ?? '';
    const tier2Factor = (fd.get('tier2Factor') as string) ?? '';
    const tier3Factor = (fd.get('tier3Factor') as string) ?? '';

    void (async () => {
      const r = await runCreateFlow({
        challengeQuestions,
        challengeAnswers,
        challengeAnswersConfirm,
        contactEmail,
        tier1Pin,
        tier2Factor,
        tier3Factor,
      });
      if (r.ok) {
        renderPostCreateBanner(r.value);
        onCreated?.(r.value);
      } else {
        onError?.(`Create failed: ${r.error.kind}`);
      }
    })();
  });
}

// ──────────────────────────────────────────────────────────────────────
// Post-create banner — value cap explainer + WT-Transport picker.
// ──────────────────────────────────────────────────────────────────────

/**
 * Security caveat shown beside the self-custody backup options (Download /
 * Copy / Share). A downloaded or copied recovery envelope restores the
 * wallet to ANYONE who obtains that file/text AND can answer the recovery
 * questions — there is no operator gate or rate limit on a local copy. We
 * surface the risk and steer toward Plexus Recovery-as-a-Service (the
 * managed, operator-gated path) as the recommended backup.
 */
export const LOCAL_BACKUP_WARNING =
  '⚠ Download and Copy save your recovery envelope locally. Anyone who gets ' +
  'that envelope and can answer your recovery questions can restore this ' +
  'wallet — keep local copies private and offline. For managed backup that ' +
  'only you can recover, enrol in Plexus Recovery (recommended).';

/**
 * Render the post-create banner into `#create-banner`. v0.4 layout:
 *
 *   Your wallet is ready.
 *
 *     ⚠ This wallet is for identity + ~$10 of micropayment budget.
 *       For larger amounts, create a vault later — same envelope
 *       pattern with stronger challenges + optional hardware keys.
 *
 *   Back up your recovery envelope:
 *     [ Save to Plexus ]  [ Share… ]  [ Download ]  [ Copy ]
 *
 * "Save to Plexus" is the existing W7 button (popup-plexus.ts owns it,
 * untouched). The remaining buttons are sourced from `defaultTransports()`,
 * each running independently when clicked — multi-select-friendly.
 *
 * Exported so tests / the popup harness can re-render against a custom
 * banner element without a full form submission.
 */
export function renderPostCreateBanner(
  result: CreateWalletResult,
  opts?: {
    /** Override the transport set (for tests). Defaults to defaultTransports(). */
    transports?: EnvelopeTransport[];
    /** Element to render into. Defaults to `#create-banner`. */
    element?: HTMLElement;
    /** Receives each transport's result so the host UI can flash a toast. */
    onTransportResult?: (transportId: string, r: TransportResult) => void;
  },
): void {
  if (typeof document === 'undefined') return;
  const pane = opts?.element ?? (document.getElementById('create-banner') as HTMLDivElement | null);
  if (!pane) return;

  const transports = opts?.transports ?? defaultTransports();

  // Build the inner DOM imperatively so we can attach handlers without
  // resorting to inline `onclick=` (CSP-friendly).
  pane.innerHTML = '';
  const header = document.createElement('p');
  header.className = 'banner-header';
  header.textContent = 'Your wallet is ready.';
  pane.appendChild(header);

  const cap = document.createElement('p');
  cap.className = 'value-cap-explainer';
  cap.innerHTML =
    '<strong>⚠ This wallet is for identity + ~$10 of micropayment budget.</strong><br>' +
    'For larger amounts, create a vault later — same envelope pattern ' +
    'with stronger challenges + optional hardware keys.';
  pane.appendChild(cap);

  const backupHeader = document.createElement('p');
  backupHeader.className = 'backup-header';
  backupHeader.textContent = 'Back up your recovery envelope:';
  pane.appendChild(backupHeader);

  const buttonRow = document.createElement('div');
  buttonRow.className = 'transport-row';

  // The Plexus button is a sibling that popup-plexus.ts owns; we leave
  // it untouched but render an inert anchor here so the layout matches
  // the spec. The host page wires the existing #plexus-enroll element.
  const plexus = document.createElement('button');
  plexus.id = 'plexus-enroll-cta';
  plexus.type = 'button';
  plexus.textContent = 'Save to Plexus';
  plexus.dataset.action = 'plexus-enroll';
  plexus.dataset.recommended = 'true';
  buttonRow.appendChild(plexus);

  // Build a transport button per available transport.
  const serialized = serializeEnvelope(result.recoveryEnvelope);
  for (const t of transports) {
    const btn = document.createElement('button');
    btn.id = `transport-${t.id}`;
    btn.type = 'button';
    btn.textContent = `${t.icon ? `${t.icon} ` : ''}${t.name}`;
    btn.dataset.transportId = t.id;
    btn.addEventListener('click', () => {
      btn.disabled = true;
      void (async () => {
        try {
          const r = await t.send(serialized);
          if (r.ok) {
            btn.dataset.tone = 'ok';
            btn.textContent = `${t.icon ? `${t.icon} ` : ''}${t.name} ✓`;
          } else {
            btn.dataset.tone = r.reason === 'cancelled' ? 'warn' : 'error';
            btn.textContent = `${t.icon ? `${t.icon} ` : ''}${t.name} (${r.reason})`;
          }
          opts?.onTransportResult?.(t.id, r);
        } finally {
          btn.disabled = false;
        }
      })();
    });
    buttonRow.appendChild(btn);
  }
  pane.appendChild(buttonRow);

  // Self-custody backup carries real risk: a local envelope restores the
  // wallet to anyone who also knows the recovery answers. Surface that next
  // to the local options; the Plexus button above is marked recommended.
  const risk = document.createElement('p');
  risk.className = 'backup-risk-note';
  risk.dataset.tone = 'warn';
  risk.textContent = LOCAL_BACKUP_WARNING;
  pane.appendChild(risk);

  pane.removeAttribute('hidden');
}

```
