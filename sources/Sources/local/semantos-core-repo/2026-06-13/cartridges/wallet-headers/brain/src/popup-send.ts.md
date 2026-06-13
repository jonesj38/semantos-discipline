---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-send.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.658391+00:00
---

# cartridges/wallet-headers/brain/src/popup-send.ts

```ts
// Popup screen — send/receive (W9, design §7.1–7.4).
//
// Pure-state module + DOM hydration. The "send" form lets the user pay X
// sats to address Y; the popup classifies the spend tier from the policy,
// asks for the matching factor (PIN / biometric / vault) only when needed,
// then drives wallet-ops.signSpend.
//
// v0.1 produces an ECDSA signature over the (caller-supplied) digest. Full
// transaction construction lives in W11 + the tx-builder workstream — for
// the popup's purposes the user has typically already built the tx
// preimage in another app and is here only to authorize the signature.
//
// "Receive" is trivial in v0.1: it just shows the wallet's identity public
// key; users construct a P2PKH (or BRC-29 paymail) address from it
// externally.

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import {
  signSpend,
  classifyTier,
  getPolicy,
  getIdentitySnapshot,
  type SignSpendResult,
  type WalletError,
  type Result,
} from './wallet-ops';

export interface SendScreenInputs {
  /** Recipient address — free-form in v0.1 (we don't validate Bitcoin
   *  address shape). The address contributes to the digest below. */
  recipient: string;
  /** Sat amount as a decimal string. */
  amountSats: string;
  /** Optional caller-supplied digest. When omitted, we derive a stand-in
   *  digest = sha256("send" || recipient || amount) for v0.1. v0.2 wires
   *  the tx-builder to construct a real sighash preimage. */
  digestHex?: string;
  /** Tier-1+ factor, only required when amount crosses a tier ceiling. */
  factor?: string;
}

export type SendResult = Result<SignSpendResult, WalletError>;

export function formatSendSuccess(result: SignSpendResult): string {
  return `Signed a Tier-${result.tier} local authorization. Transaction construction and broadcast are not available in this browser build yet.`;
}

export function formatSendError(error: WalletError): string {
  switch (error.kind) {
    case 'BAD_INPUT':
      return `Send failed: ${error.reason}.`;
    case 'TIER_LOCKED':
      return `Send failed: Tier ${error.tier} requires its factor.`;
    case 'WRONG_FACTOR':
      return 'Send failed: the supplied factor was wrong.';
    case 'TIER3_COOLDOWN':
      return `Send failed: Tier 3 cooldown has ${error.secondsRemaining} second(s) remaining.`;
    case 'NOT_CREATED':
      return 'Create or recover a wallet before signing.';
    case 'ALREADY_CREATED':
      return 'Wallet already exists.';
    case 'STALE_POLICY':
      return 'Send failed: wallet policy changed. Refresh and try again.';
    case 'INTERNAL':
      return `Send failed: ${error.reason}.`;
  }
}

/** Pure-state: derive a v0.1 stand-in digest from (recipient, amount). */
export function deriveSpendDigest(recipient: string, amountSats: bigint): Uint8Array {
  const enc = new TextEncoder();
  const buf = new Uint8Array(4 + recipient.length + 8);
  buf.set(enc.encode('send'), 0);
  buf.set(enc.encode(recipient), 4);
  new DataView(buf.buffer).setBigUint64(4 + recipient.length, amountSats, true);
  return nobleSha256(buf);
}

/**
 * Drive a single send. Returns the signSpend Result verbatim — the caller
 * (DOM shell or test) renders either a "signed" confirmation or an error.
 * Pure logic, no DOM access.
 */
export async function runSendFlow(inputs: SendScreenInputs): Promise<SendResult> {
  if (!/^\d+$/.test(inputs.amountSats)) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'amountSats must be a decimal integer' } };
  }
  const amountSats = BigInt(inputs.amountSats);
  const policy = getPolicy();
  const tier = classifyTier(amountSats, policy);

  let digest: Uint8Array;
  if (inputs.digestHex) {
    digest = new Uint8Array(inputs.digestHex.length / 2);
    for (let i = 0; i < digest.length; i++) {
      digest[i] = parseInt(inputs.digestHex.slice(i * 2, i * 2 + 2), 16);
    }
    if (digest.length !== 32) {
      return { ok: false, error: { kind: 'BAD_INPUT', reason: 'digest must be 32 bytes' } };
    }
  } else {
    digest = deriveSpendDigest(inputs.recipient, amountSats);
  }

  const factor = tier > 0 && inputs.factor ? new TextEncoder().encode(inputs.factor) : undefined;
  return await signSpend({ digest, amountSats, factor });
}

/** Pure-state: the receiving address — v0.1 just exposes the identity key. */
export function receivingPublicKeyHex(): string | null {
  try {
    const id = getIdentitySnapshot();
    return Array.from(id.identityPk)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  } catch {
    return null;
  }
}

export function mountSendScreen(
  onSent?: (r: SignSpendResult) => void,
  onError?: (msg: string) => void,
): void {
  if (typeof document === 'undefined') return;
  const form = document.getElementById('send-form') as HTMLFormElement | null;
  if (!form) return;
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const fd = new FormData(form);
    const inputs: SendScreenInputs = {
      recipient: (fd.get('recipient') as string) ?? '',
      amountSats: (fd.get('amountSats') as string) ?? '0',
      factor: (fd.get('factor') as string) || undefined,
    };
    void (async () => {
      const r = await runSendFlow(inputs);
      if (r.ok) {
        setSendStatus(formatSendSuccess(r.value), 'ok');
        onSent?.(r.value);
      } else {
        const msg = formatSendError(r.error);
        setSendStatus(msg, 'error');
        onError?.(msg);
      }
    })();
  });
}

function setSendStatus(message: string, tone: 'ok' | 'warn' | 'error'): void {
  if (typeof document === 'undefined') return;
  const el = document.getElementById('send-status');
  if (!el) return;
  el.textContent = message;
  el.setAttribute('data-tone', tone);
}

```
