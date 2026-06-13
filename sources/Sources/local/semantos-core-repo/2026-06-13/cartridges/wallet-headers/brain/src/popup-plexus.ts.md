---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-plexus.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.658686+00:00
---

# cartridges/wallet-headers/brain/src/popup-plexus.ts

```ts
// Popup UI extensions for Plexus enrollment + recovery (W7).
//
// Lives alongside `popup.ts` (the per-tier-unlock factor handler) — both
// scripts run inside the same `wallet.semantos.{tld}/popup` window. This
// file owns the dialogs that drive `enroll()` / `recover()` from
// `./plexus/dispatch.ts`.
//
// The popup UI itself is intentionally minimal — full styling lands with
// the rest of the wallet UI in W9. What's here:
//   • the recovery banner toggle (RECOVERY NOT CONFIGURED ↔ enrolled),
//   • the enrollment dialog (email + questions + answers + OTP),
//   • the recovery dialog (email + OTP + answers + completion).
//
// Behavior is split between a pure-state module (this file) and the HTML
// shell `popup.html`, which is hand-authored and references these IDs.
// The pure-state pieces are fully testable under `bun test` without a
// browser — exposed as named exports below.
//
// Cross-references:
//   • design §7.7 (enrollment flow + UI cues)
//   • design §7.8 (recovery flow + cross-origin popup)
//   • design §10.3 (banner state + operator-domain display)

import {
  enroll,
  enrollCachedEnvelope,
  recover,
  type PlexusRecoveryEnvelope,
  type DerivationContext,
  type DerivationStateSnapshot,
  type EnrollError,
  type EnrollResult,
  type RecoverError,
  type RecoverResult,
  type Result,
  type PlexusOperator,
  type OtpPromptFn,
  type AnswerPromptFn,
} from './plexus';

// ──────────────────────────────────────────────────────────────────────
// Banner state
// ──────────────────────────────────────────────────────────────────────

export type RecoveryStatus =
  | { state: 'LOCAL_ONLY' }
  | { state: 'ENROLLED'; operatorDomain: string; enrolledAt: number }
  | { state: 'EXPIRED'; operatorDomain: string }; // subscription lapsed (§7.7 failure mode)

export const PLEXUS_UNAVAILABLE_MESSAGE =
  'Plexus recovery enrollment is not available in this build yet. Your encrypted recovery envelope is stored locally; use Download or Copy from the create screen for now.';

/** Pure helper: produce the banner string the popup chrome should render. */
export function bannerText(status: RecoveryStatus): string {
  switch (status.state) {
    case 'LOCAL_ONLY':
      return 'RECOVERY NOT CONFIGURED — if you lose this device, your keys are gone. Enroll in recovery for $X / year.';
    case 'ENROLLED':
      return `Recovery enrolled — managed by ${status.operatorDomain}`;
    case 'EXPIRED':
      return `Recovery enrollment expired — managed by ${status.operatorDomain}. Renew or your envelope may be archived.`;
  }
}

/** Update the popup chrome's recovery banner. Mutates the DOM if available. */
export function renderBanner(status: RecoveryStatus): void {
  if (typeof document === 'undefined') return;
  const el = document.getElementById('recovery-banner');
  if (!el) return;
  el.dataset.state = status.state;
  el.textContent = bannerText(status);
  // CTA is shown only in NOT_CONFIGURED state.
  const cta = document.getElementById('recovery-banner-cta') as HTMLButtonElement | null;
  if (cta) cta.hidden = status.state !== 'LOCAL_ONLY';
}

export function renderPlexusUnavailable(): void {
  if (typeof document === 'undefined') return;
  const root = document.getElementById('plexus-unavailable');
  if (root) {
    root.textContent = PLEXUS_UNAVAILABLE_MESSAGE;
    root.removeAttribute('hidden');
  }
  disableForm('enroll-form');
  disableForm('recover-form');
  const cta = document.getElementById('recovery-banner-cta') as HTMLButtonElement | null;
  if (cta) {
    cta.hidden = false;
    cta.disabled = true;
    cta.textContent = 'Recovery enrollment unavailable';
  }
  setPlexusStatus('enroll-status', PLEXUS_UNAVAILABLE_MESSAGE, 'warn');
  setPlexusStatus('recover-status', PLEXUS_UNAVAILABLE_MESSAGE, 'warn');
}

export function setPlexusStatus(id: 'enroll-status' | 'recover-status', message: string, tone: 'ok' | 'warn' | 'error'): void {
  if (typeof document === 'undefined') return;
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = message;
  el.setAttribute('data-tone', tone);
}

function disableForm(id: string): void {
  const form = document.getElementById(id) as HTMLFormElement | null;
  if (!form) return;
  for (const control of Array.from(form.querySelectorAll<HTMLInputElement | HTMLButtonElement>('input, button'))) {
    control.disabled = true;
  }
}

// ──────────────────────────────────────────────────────────────────────
// Enrollment dialog
// ──────────────────────────────────────────────────────────────────────

/** Inputs collected from the user via the enrollment dialog. */
export interface EnrollmentDialogValues {
  email: string;
  questions: string[];
  answers: string[];
}

/** Pure-state extraction so we can test the form-shape parser without a DOM. */
export function readEnrollmentForm(form: HTMLFormElement | null): EnrollmentDialogValues | null {
  if (!form) return null;
  const fd = new FormData(form);
  const email = (fd.get('email') as string) ?? '';
  const questions: string[] = [];
  const answers: string[] = [];
  for (let i = 0; i < 10; i++) {
    const q = fd.get(`question-${i}`);
    const a = fd.get(`answer-${i}`);
    if (typeof q === 'string' && typeof a === 'string' && q.length > 0 && a.length > 0) {
      questions.push(q);
      answers.push(a);
    }
  }
  if (!email) return null;
  return { email, questions, answers };
}

/**
 * Dependencies passed to the enrollment / recovery handlers — abstracted so
 * tests can inject mocks without spinning up a real DOM.
 */
export interface PlexusUiDeps {
  operator: PlexusOperator;
  /** Identity material the wallet has already created locally. */
  identitySk: Uint8Array;
  identityPk: Uint8Array;
  certId: Uint8Array;
  /** Recovery seed — the wallet's BIP39 64-byte seed. Wiped after enrollment. */
  recoverySeed?: Uint8Array;
  /** Preferred v0.4 path: the already-built, locally cached recovery
   *  envelope from createWallet(). When present, enrollment mirrors this
   *  envelope directly and does not require raw answers or seed material. */
  recoveryEnvelope?: PlexusRecoveryEnvelope;
  /** Local derivation contexts for tiers 1/2/3. */
  derivationContexts: DerivationContext[];
  /** Snapshot from the local DerivationStateStore. */
  derivationStateSnapshot: DerivationStateSnapshot;
  /** OTP prompt — surfaces a dialog that resolves with the typed code. */
  requestOtp: OtpPromptFn;
  /** Optional callback after a successful enrollment — e.g. update stored
   *  banner state, persist the envelope, dismiss the dialog. */
  onEnrolled?: (result: EnrollResult) => void;
  /** Optional callback after a successful recovery — caller re-establishes
   *  tier keys + auth factors using the returned seed + contexts. */
  onRecovered?: (result: RecoverResult) => void;
  /** Recovery dialog needs an answer prompt too. */
  requestAnswers: AnswerPromptFn;
  /** UI feedback for an explicit failure — by default writes to a `<output>` element. */
  onError?: (msg: string) => void;
}

/**
 * Handle an enrollment-dialog submission. Wipes the answer/seed buffers
 * after dispatch returns. Test-friendly: returns the dispatcher Result so
 * tests don't need to scrape the DOM.
 */
export async function handleEnrollSubmit(
  values: EnrollmentDialogValues,
  deps: PlexusUiDeps,
): Promise<Result<EnrollResult, EnrollError>> {
  let result: Result<EnrollResult, EnrollError>;
  if (deps.recoveryEnvelope) {
    if (values.email !== deps.recoveryEnvelope.contactEmail) {
      result = {
        ok: false,
        error: { kind: 'INVALID_INPUT', reason: 'email must match the cached recovery envelope' },
      };
    } else {
      result = await enrollCachedEnvelope(deps.operator, {
        identitySk: deps.identitySk,
        identityPk: deps.identityPk,
        envelope: deps.recoveryEnvelope,
        requestOtp: deps.requestOtp,
      });
    }
  } else if (deps.recoverySeed) {
    result = await enroll(deps.operator, {
      identitySk: deps.identitySk,
      identityPk: deps.identityPk,
      certId: deps.certId,
      contactEmail: values.email,
      questions: values.questions,
      // Slice (defensive copy) — we don't want to retain refs into the form.
      answers: values.answers.slice(),
      recoverySeed: deps.recoverySeed,
      derivationContexts: deps.derivationContexts,
      derivationStateSnapshot: deps.derivationStateSnapshot,
      requestOtp: deps.requestOtp,
    });
  } else {
    result = {
      ok: false,
      error: { kind: 'INVALID_INPUT', reason: 'no recovery envelope or recovery seed available' },
    };
  }

  // Wipe the answers we sliced into the dispatcher.
  for (let i = 0; i < values.answers.length; i++) values.answers[i] = '';

  if (result.ok) {
    renderBanner({
      state: 'ENROLLED',
      operatorDomain: result.value.operatorDomain,
      enrolledAt: result.value.enrolledAt,
    });
    deps.onEnrolled?.(result.value);
  } else {
    deps.onError?.(formatEnrollError(result.error));
  }
  return result;
}

// ──────────────────────────────────────────────────────────────────────
// Recovery dialog
// ──────────────────────────────────────────────────────────────────────

export interface RecoveryDialogValues {
  email: string;
}

export async function handleRecoverSubmit(
  values: RecoveryDialogValues,
  deps: PlexusUiDeps,
): Promise<Result<RecoverResult, RecoverError>> {
  const result = await recover(deps.operator, {
    contactEmail: values.email,
    requestOtp: deps.requestOtp,
    requestAnswers: deps.requestAnswers,
  });
  if (result.ok) {
    renderBanner({
      state: 'ENROLLED',
      operatorDomain: deps.operator.config.displayDomain,
      enrolledAt: Date.now(),
    });
    deps.onRecovered?.(result.value);
  } else {
    deps.onError?.(formatRecoverError(result.error));
  }
  return result;
}

// ──────────────────────────────────────────────────────────────────────
// Error → message mapping
// ──────────────────────────────────────────────────────────────────────

export function formatEnrollError(err: EnrollError): string {
  switch (err.kind) {
    case 'INVARIANT_FAILED':
      return `Envelope invariant ${err.check} failed: ${err.detail}. Refusing to dispatch.`;
    case 'INVALID_INPUT':
      return `Invalid input: ${err.reason}.`;
    case 'NETWORK_FAILURE':
      return `Network failure: ${err.detail}. Envelope cached locally — you can retry.`;
    case 'UNSUPPORTED_VERSION':
      return 'This wallet uses an algorithm version your operator does not support.';
    case 'RATE_LIMITED':
      return 'Too many enrollment attempts. Try again later.';
    case 'OTP_EXPIRED':
      return 'The OTP code expired. Restart enrollment.';
    case 'OTP_LOCKED':
      return 'Too many wrong OTP codes. Wait, then restart enrollment.';
    case 'OTP_WRONG':
      return `Wrong code. ${err.attemptsRemaining} attempt(s) remaining.`;
    case 'OTP_CANCELLED':
      return 'Enrollment cancelled by user.';
    case 'OPERATOR_REJECTED':
      return `Operator rejected enrollment (${err.status}): ${err.detail}.`;
  }
}

export function formatRecoverError(err: RecoverError): string {
  switch (err.kind) {
    case 'INVALID_INPUT':
      return `Invalid input: ${err.reason}.`;
    case 'NETWORK_FAILURE':
      return `Network failure: ${err.detail}. Try again.`;
    case 'NO_ENROLLMENT':
      return 'No recovery enrollment found for that email.';
    case 'RATE_LIMITED':
      return 'Too many recovery attempts. Wait and try again.';
    case 'OTP_EXPIRED':
      return 'The OTP code expired. Restart recovery.';
    case 'OTP_LOCKED':
      return 'Too many wrong OTP codes. Wait, then restart recovery.';
    case 'OTP_WRONG':
      return `Wrong code. ${err.attemptsRemaining} attempt(s) remaining.`;
    case 'OTP_CANCELLED':
      return 'Recovery cancelled by user.';
    case 'CHALLENGE_FAILED':
      return 'One or more challenge answers were incorrect.';
    case 'CHALLENGE_CANCELLED':
      return 'Recovery cancelled by user.';
    case 'DECRYPT_FAILED':
      return 'Could not decrypt your recovery seed. Check your answers and try again.';
    case 'OPERATOR_REJECTED':
      return `Operator rejected recovery (${err.status}): ${err.detail}.`;
  }
}

// ──────────────────────────────────────────────────────────────────────
// DOM-side prompt helpers — only run inside a real browser.
// ──────────────────────────────────────────────────────────────────────

/**
 * Default OTP prompt: shows a `<dialog id="otp-dialog">` with a single
 * `<input id="otp-input">`, resolves with the typed code or null on cancel.
 *
 * Tests don't exercise this path — the unit tests call `enroll()` /
 * `recover()` directly with their own mock prompt callbacks.
 */
export function browserOtpPrompt(): OtpPromptFn {
  return async ({ maskedEmail, expiresInSeconds }) => {
    if (typeof document === 'undefined') return null;
    const dlg = document.getElementById('otp-dialog') as HTMLDialogElement | null;
    const input = document.getElementById('otp-input') as HTMLInputElement | null;
    const detail = document.getElementById('otp-detail');
    if (!dlg || !input) return null;
    if (detail) {
      detail.textContent = `We emailed a 6-digit code to ${maskedEmail}. It expires in ${Math.floor(expiresInSeconds / 60)} minutes.`;
    }
    input.value = '';
    return await new Promise<string | null>((resolve) => {
      const onClose = (): void => {
        dlg.removeEventListener('close', onClose);
        resolve(dlg.returnValue === 'ok' ? input.value : null);
      };
      dlg.addEventListener('close', onClose);
      dlg.showModal();
    });
  };
}

/** Default challenge-answer prompt — renders the questions in `<dialog id="answers-dialog">`. */
export function browserAnswerPrompt(): AnswerPromptFn {
  return async (questions) => {
    if (typeof document === 'undefined') return null;
    const dlg = document.getElementById('answers-dialog') as HTMLDialogElement | null;
    const list = document.getElementById('answers-list') as HTMLOListElement | null;
    if (!dlg || !list) return null;
    list.innerHTML = '';
    const inputs: HTMLInputElement[] = [];
    for (const q of questions) {
      const li = document.createElement('li');
      const lab = document.createElement('label');
      lab.textContent = q;
      const inp = document.createElement('input');
      inp.type = 'text';
      inp.required = true;
      lab.appendChild(inp);
      li.appendChild(lab);
      list.appendChild(li);
      inputs.push(inp);
    }
    return await new Promise<string[] | null>((resolve) => {
      const onClose = (): void => {
        dlg.removeEventListener('close', onClose);
        if (dlg.returnValue !== 'ok') {
          resolve(null);
          return;
        }
        resolve(inputs.map((i) => i.value));
      };
      dlg.addEventListener('close', onClose);
      dlg.showModal();
    });
  };
}

// ──────────────────────────────────────────────────────────────────────
// Hydration: wire up the form/dialog elements when running in a browser.
// ──────────────────────────────────────────────────────────────────────

/** Attach the enroll/recover dialogs once the popup loads. Idempotent. */
export function mountPlexusUi(deps: () => PlexusUiDeps | null | Promise<PlexusUiDeps | null>): void {
  if (typeof document === 'undefined') return;

  const enrollForm = document.getElementById('enroll-form') as HTMLFormElement | null;
  enrollForm?.addEventListener('submit', (ev) => {
    ev.preventDefault();
    void (async () => {
      const values = readEnrollmentForm(enrollForm);
      const d = await deps();
      if (!values) {
        setPlexusStatus('enroll-status', 'Enter the email address from wallet creation.', 'error');
        return;
      }
      if (!d) {
        renderPlexusUnavailable();
        return;
      }
      const result = await handleEnrollSubmit(values, d);
      if (result.ok) {
        setPlexusStatus('enroll-status', `Recovery enrollment saved with ${result.value.operatorDomain}.`, 'ok');
      } else {
        setPlexusStatus('enroll-status', formatEnrollError(result.error), 'error');
      }
    })();
  });

  const recoverForm = document.getElementById('recover-form') as HTMLFormElement | null;
  recoverForm?.addEventListener('submit', (ev) => {
    ev.preventDefault();
    void (async () => {
      const fd = new FormData(recoverForm);
      const email = (fd.get('email') as string) ?? '';
      const d = await deps();
      if (!email) {
        setPlexusStatus('recover-status', 'Enter the email address used for recovery enrollment.', 'error');
        return;
      }
      if (!d) {
        renderPlexusUnavailable();
        return;
      }
      const result = await handleRecoverSubmit({ email }, d);
      if (result.ok) {
        setPlexusStatus('recover-status', 'Recovery envelope fetched. Continue setting local factors.', 'ok');
      } else {
        setPlexusStatus('recover-status', formatRecoverError(result.error), 'error');
      }
    })();
  });

  const cta = document.getElementById('recovery-banner-cta');
  cta?.addEventListener('click', () => {
    document.getElementById('enroll-dialog')?.removeAttribute('hidden');
  });
}

/**
 * Convenience: render a discarded-envelope hint on the UI when the
 * dispatcher returned `NETWORK_FAILURE`. The cached envelope can be
 * persisted by the caller (typically into IndexedDB under a `pendingEnroll`
 * key) and resubmitted later.
 */
export function persistCachedEnvelopeForRetry(envelope: PlexusRecoveryEnvelope): void {
  if (typeof document === 'undefined') return;
  const root = document.getElementById('retry-enrollment');
  if (!root) return;
  root.removeAttribute('hidden');
  // The actual persistence is the caller's responsibility (IndexedDB) —
  // we just surface it on the DOM so the UI can offer the affordance.
  root.dataset.envelopeIdentity = envelope.identityKey;
}

```
