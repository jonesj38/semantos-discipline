---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.660851+00:00
---

# cartridges/wallet-headers/brain/src/popup.ts

```ts
// Popup window — `wallet.semantos.{tld}/popup` (per WALLET-TIER-CUSTODY.md §10.1).
// Re-exports the Plexus enroll/recover UI module so it ships with the popup
// bundle (W7 — single-script popup target keeps gzipped delta minimal).
export * from './popup-plexus';

// W9: register all popup screens so the popup.html shell can mount any of
// them by data-screen attribute. The router lives at the bottom of this
// file and chooses the initial screen based on whether a wallet exists.
export {
  runCreateFlow,
  mountCreateScreen,
  fetchRecoveryPriceHint,
  validateChallengeAnswers,
  describeAnswerError,
  describeAnswerWarning,
  renderPostCreateBanner,
} from './popup-create';
export {
  defaultTransports,
  serializeEnvelope,
  WebShareTransport,
  DownloadTransport,
  ClipboardTransport,
} from './transport';
export { renderStatus, formatStatus } from './popup-status';
export {
  runSendFlow,
  deriveSpendDigest,
  mountSendScreen,
  receivingPublicKeyHex,
  formatSendSuccess,
  formatSendError,
} from './popup-send';
export {
  runPolicyUpdate,
  validatePolicy,
  readPolicyForm,
  buildNextPolicy,
  mountPolicyScreen,
} from './popup-policy';

import { loadWallet } from './wallet-ops';
import { getCachedRecoveryEnvelope, getIdentitySnapshot, setRecoveryStatus } from './wallet-ops';
import { mountCreateScreen as _mountCreate } from './popup-create';
import {
  browserAnswerPrompt,
  browserOtpPrompt,
  mountPlexusUi as _mountPlexus,
  renderPlexusUnavailable,
  setPlexusStatus,
} from './popup-plexus';
import { renderStatus as _renderStatus } from './popup-status';
import { mountSendScreen as _mountSend } from './popup-send';
import { mountPolicyScreen as _mountPolicy } from './popup-policy';
import { HttpPlexusOperator, type PlexusOperator, type PlexusOperatorConfig } from './plexus';

// ──────────────────────────────────────────────────────────────────────
// Screen router
// ──────────────────────────────────────────────────────────────────────

export type PopupScreen =
  | 'create'
  | 'status'
  | 'send'
  | 'policy'
  | 'plexus-enroll'
  | 'plexus-recover'
  | 'factor';

/** Show one screen, hide the others. */
export function showScreen(screen: PopupScreen): void {
  if (typeof document === 'undefined') return;
  const screens = document.querySelectorAll<HTMLElement>('[data-screen]');
  for (const el of Array.from(screens)) {
    el.hidden = el.dataset.screen !== screen;
  }
}

/** Decide the initial screen — `create` if no wallet, else `status`. */
export async function pickInitialScreen(): Promise<PopupScreen> {
  const r = await loadWallet();
  const requested = requestedScreenFromLocation(r.ok);
  if (requested) return requested;
  return r.ok ? 'status' : 'create';
}

export function requestedScreenFromLocation(walletExists: boolean): PopupScreen | null {
  if (typeof window === 'undefined') return null;
  const params = new URLSearchParams(window.location.search);
  const intent = params.get('intent');
  if (intent === 'plexus-signup') {
    return walletExists ? 'status' : 'create';
  }
  const raw =
    params.get('screen') ??
    (window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash);
  if (!raw) return null;
  if (!isPopupScreen(raw)) return null;
  if (!walletExists && raw !== 'create' && raw !== 'plexus-recover') return 'create';
  return raw;
}

function isPopupScreen(raw: string): raw is PopupScreen {
  return (
    raw === 'create' ||
    raw === 'status' ||
    raw === 'send' ||
    raw === 'policy' ||
    raw === 'plexus-enroll' ||
    raw === 'plexus-recover' ||
    raw === 'factor'
  );
}

//
// Opens whenever the bridge needs a UI factor:
//   • PIN entry            (Tier 1 unlock)
//   • biometric WebAuthn   (Tier 2 unlock — navigator.credentials.get)
//   • passphrase           (Tier 3 unlock)
//   • cooldown reveal      (Tier 3 vault — countdown UI)
//
// The popup is opened by `window.open('/popup', '_blank', 'popup=true')` from
// the bridge iframe. Once the user submits their factor, this script posts
// it back through `window.opener.postMessage` and closes itself.
//
// v0.1 deliberately minimal — full UI/UX lands in W9. The HTML shell wires
// inputs to the handlers below; tests cover the postMessage protocol only.

export type FactorKind = 'pin' | 'passphrase' | 'webauthn';

export interface FactorRequest {
  type: 'factor-request';
  kind: FactorKind;
  /**
   * The bridge's nonce for this prompt — echoed back so the bridge can
   * correlate the response with its outstanding unlock request.
   */
  nonce: string;
  /** WebAuthn challenge / credential ID, only populated when kind === 'webauthn'. */
  webauthn?: {
    rpId: string;
    challenge: ArrayBuffer;
    allowCredentialIds: ArrayBuffer[];
  };
}

export type FactorResponse =
  | { type: 'factor-response'; nonce: string; kind: 'pin' | 'passphrase'; factor: Uint8Array }
  | { type: 'factor-response'; nonce: string; kind: 'webauthn'; credentialId: ArrayBuffer; signature: ArrayBuffer; authenticatorData: ArrayBuffer; clientDataJSON: ArrayBuffer }
  | { type: 'factor-cancel'; nonce: string }
  | { type: 'factor-error'; nonce: string; reason: string };

let pending: FactorRequest | null = null;

/** Bridge calls into this when the popup boots. Stores the request and
 * surfaces it on the DOM so the rendered HTML can react. */
export function receiveRequest(req: FactorRequest): void {
  pending = req;
  if (typeof document !== 'undefined') {
    const root = document.getElementById('factor-root');
    if (root) {
      root.dataset.kind = req.kind;
    }
  }
}

/** Submit a PIN / passphrase factor. Marshals it as bytes via UTF-8. */
export function submitTextFactor(text: string): void {
  if (!pending || (pending.kind !== 'pin' && pending.kind !== 'passphrase')) {
    sendError('no pending text-factor request');
    return;
  }
  const factor = new TextEncoder().encode(text);
  postToOpener({ type: 'factor-response', nonce: pending.nonce, kind: pending.kind, factor });
  closeSelf();
}

/**
 * Drive a WebAuthn assertion — the user's biometric authenticator signs the
 * challenge, and the resulting (signature, authenticatorData, clientDataJSON)
 * triple is posted back. The bridge derives a tier-specific KEK from a stable
 * function of these (per design §4.1 v0.2 path) — for v0.1, the bridge uses
 * `signature` as the opaque factor input to PBKDF2.
 */
export async function submitWebAuthnFactor(): Promise<void> {
  if (!pending || pending.kind !== 'webauthn' || !pending.webauthn) {
    sendError('no pending webauthn request');
    return;
  }
  if (typeof navigator === 'undefined' || !navigator.credentials) {
    sendError('webauthn unavailable');
    return;
  }
  try {
    const cred = (await navigator.credentials.get({
      publicKey: {
        challenge: pending.webauthn.challenge,
        rpId: pending.webauthn.rpId,
        allowCredentials: pending.webauthn.allowCredentialIds.map((id) => ({
          id,
          type: 'public-key' as const,
          transports: ['internal' as const],
        })),
        userVerification: 'required',
        timeout: 60_000,
      },
    })) as PublicKeyCredential | null;
    if (!cred) {
      sendError('webauthn returned null');
      return;
    }
    const resp = cred.response as AuthenticatorAssertionResponse;
    postToOpener({
      type: 'factor-response',
      nonce: pending.nonce,
      kind: 'webauthn',
      credentialId: cred.rawId,
      signature: resp.signature,
      authenticatorData: resp.authenticatorData,
      clientDataJSON: resp.clientDataJSON,
    });
    closeSelf();
  } catch (e) {
    sendError(`webauthn: ${(e as Error).message}`);
  }
}

/** User dismissed the prompt — tell the bridge so it can fail the unlock cleanly. */
export function cancel(): void {
  if (!pending) return;
  postToOpener({ type: 'factor-cancel', nonce: pending.nonce });
  closeSelf();
}

function sendError(reason: string): void {
  if (!pending) return;
  postToOpener({ type: 'factor-error', nonce: pending.nonce, reason });
  closeSelf();
}

function postToOpener(msg: FactorResponse): void {
  if (typeof window === 'undefined') return;
  // The bridge opens the popup at the same origin (wallet.semantos.{tld}) —
  // post back to that origin only.
  if (!window.opener) return;
  window.opener.postMessage(msg, window.location.origin);
}

function closeSelf(): void {
  if (typeof window === 'undefined') return;
  pending = null;
  try {
    window.close();
  } catch {
    /* some browsers refuse to close a window not opened by script — fine */
  }
}

// ── DOM bootstrap (no-op outside a real browser) ──

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  // The bridge sends the request via postMessage with `targetOrigin =
  // window.location.origin`. Listen for it and stage.
  window.addEventListener('message', (ev: MessageEvent) => {
    if (ev.origin !== window.location.origin) return;
    const data = ev.data as { type?: string };
    if (data?.type === 'factor-request') {
      receiveRequest(data as FactorRequest);
    }
  });

  // Wire up the canonical buttons. The HTML shell exposes:
  //   #pin-form        with #pin-input         (submit handler)
  //   #passphrase-form with #passphrase-input  (submit handler)
  //   #webauthn-btn                            (click handler)
  //   #cancel-btn                              (click handler)
  const onLoad = (): void => {
    const pinForm = document.getElementById('pin-form') as HTMLFormElement | null;
    const pinInput = document.getElementById('pin-input') as HTMLInputElement | null;
    const passForm = document.getElementById('passphrase-form') as HTMLFormElement | null;
    const passInput = document.getElementById('passphrase-input') as HTMLInputElement | null;
    const webauthnBtn = document.getElementById('webauthn-btn');
    const cancelBtn = document.getElementById('cancel-btn');

    pinForm?.addEventListener('submit', (e) => {
      e.preventDefault();
      if (pinInput) submitTextFactor(pinInput.value);
    });
    passForm?.addEventListener('submit', (e) => {
      e.preventDefault();
      if (passInput) submitTextFactor(passInput.value);
    });
    webauthnBtn?.addEventListener('click', () => {
      void submitWebAuthnFactor();
    });
    cancelBtn?.addEventListener('click', () => {
      cancel();
    });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onLoad);
  } else {
    onLoad();
  }

  // W9: also mount the create / status / send / policy screens. Each is a
  // no-op when its DOM container is absent, so this is safe to call eagerly.
  const onLoadW9 = (): void => {
    _mountCreate(
      () => {
        showScreen('status');
        void _renderStatus();
      },
      (msg) => console.warn('[popup-create]', msg),
    );
    _mountSend(
      () => void _renderStatus(),
      (msg) => console.warn('[popup-send]', msg),
    );
    _mountPolicy(
      () => void _renderStatus(),
      (msg) => console.warn('[popup-policy]', msg),
    );
    if (!configuredPlexusOperator()) renderPlexusUnavailable();
    _mountPlexus(async () => {
      const operator = configuredPlexusOperator();
      if (!operator) {
        renderPlexusUnavailable();
        return null;
      }
      let identity: ReturnType<typeof getIdentitySnapshot>;
      try {
        identity = getIdentitySnapshot();
      } catch {
        identity = {
          identitySk: new Uint8Array(32),
          identityPk: new Uint8Array(33),
          certId: new Uint8Array(32),
        };
      }
      const envelope = await getCachedRecoveryEnvelope();
      return {
        operator,
        identitySk: identity.identitySk,
        identityPk: identity.identityPk,
        certId: identity.certId,
        recoveryEnvelope: envelope.ok ? envelope.value : undefined,
        derivationContexts: envelope.ok ? envelope.value.derivationContexts : [],
        derivationStateSnapshot: envelope.ok
          ? envelope.value.derivationStateSnapshot
          : { records: [], snapshotTimestamp: new Date().toISOString() },
        requestOtp: browserOtpPrompt(),
        requestAnswers: browserAnswerPrompt(),
        onEnrolled: (result) => {
          void setRecoveryStatus({
            state: 'ENROLLED',
            operatorDomain: result.operatorDomain,
            enrolledAt: result.enrolledAt,
          }).then(() => _renderStatus());
        },
        onError: (msg) => {
          setPlexusStatus('enroll-status', msg, 'error');
          setPlexusStatus('recover-status', msg, 'error');
        },
      };
    });
    void (async () => {
      const initial = await pickInitialScreen();
      showScreen(initial);
      if (initial === 'status') void _renderStatus();
    })();

    // Hook nav buttons (each is `<button data-goto="status">…`).
    const navButtons = document.querySelectorAll<HTMLElement>('[data-goto]');
    for (const btn of Array.from(navButtons)) {
      btn.addEventListener('click', () => {
        const target = btn.dataset.goto as PopupScreen | undefined;
        if (!target) return;
        showScreen(target);
        if (target === 'status') void _renderStatus();
      });
    }

    // Tell the bridge we're ready to receive a factor-request (used by
    // the bridge's promptFactor → window.open flow).
    if (window.opener) {
      try {
        window.opener.postMessage({ type: 'popup-ready' }, window.location.origin);
      } catch {
        /* cross-origin; bridge ignores */
      }
    }
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onLoadW9);
  } else {
    onLoadW9();
  }
}

function configuredPlexusOperator(): PlexusOperator | null {
  if (typeof window === 'undefined') return null;
  const cfg = (window as unknown as { SEMANTOS_PLEXUS_OPERATOR?: Partial<PlexusOperatorConfig> })
    .SEMANTOS_PLEXUS_OPERATOR;
  if (!cfg?.baseUrl || !cfg.displayDomain) return null;
  return new HttpPlexusOperator({
    baseUrl: cfg.baseUrl,
    displayDomain: cfg.displayDomain,
    ...(cfg.pinnedCertFingerprintSha256
      ? { pinnedCertFingerprintSha256: cfg.pinnedCertFingerprintSha256 }
      : {}),
  });
}

```
