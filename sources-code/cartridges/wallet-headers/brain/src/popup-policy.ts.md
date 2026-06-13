---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.660562+00:00
---

# cartridges/wallet-headers/brain/src/popup-policy.ts

```ts
// Popup screen — policy editor (W9, design §6.3).
//
// Lets the user adjust per-tier sat ceilings, per-tier factor kinds, and
// the Tier-3 cooldown duration.  Saving the form triggers an identity-
// signed `OP_REPLACE_POLICY`-equivalent (wallet-ops.updatePolicy), which
// monotonically bumps the policy version. Stale-version submissions are
// rejected — the design's resolution path for the open question §11 Q3
// (POLICY conflicts) is "higher version wins on next load".

import {
  getPolicy,
  updatePolicy,
  type PolicyShape,
  type FactorKind,
  type WalletError,
  type Result,
} from './wallet-ops';

export type PolicyResult = Result<PolicyShape, WalletError>;

export interface PolicyFormValues {
  tier1CeilingSats: number;
  tier2CeilingSats: number;
  tier3CeilingSats: number;
  tier1FactorKind: FactorKind;
  tier2FactorKind: FactorKind;
  tier3FactorKind: FactorKind;
  tier3CooldownSeconds: number;
}

export function readPolicyForm(form: HTMLFormElement | null): PolicyFormValues | null {
  if (!form) return null;
  const fd = new FormData(form);
  const num = (k: string): number => {
    const v = fd.get(k);
    if (typeof v !== 'string') return 0;
    const n = parseInt(v, 10);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  };
  const kind = (k: string): FactorKind => {
    const v = fd.get(k);
    if (v === 'pin' || v === 'passphrase' || v === 'webauthn') return v;
    return 'pin';
  };
  return {
    tier1CeilingSats: num('tier1CeilingSats'),
    tier2CeilingSats: num('tier2CeilingSats'),
    tier3CeilingSats: num('tier3CeilingSats'),
    tier1FactorKind: kind('tier1FactorKind'),
    tier2FactorKind: kind('tier2FactorKind'),
    tier3FactorKind: kind('tier3FactorKind'),
    tier3CooldownSeconds: num('tier3CooldownSeconds'),
  };
}

/** Pure: validate ceilings are monotonic (T1 < T2 < T3 per design §3). */
export function validatePolicy(p: PolicyFormValues): { ok: true } | { ok: false; reason: string } {
  if (p.tier1CeilingSats <= 0) return { ok: false, reason: 'Tier 1 ceiling must be > 0' };
  if (p.tier2CeilingSats <= p.tier1CeilingSats) return { ok: false, reason: 'Tier 2 ceiling must exceed Tier 1' };
  if (p.tier3CeilingSats <= p.tier2CeilingSats) return { ok: false, reason: 'Tier 3 ceiling must exceed Tier 2' };
  if (p.tier3CooldownSeconds < 0) return { ok: false, reason: 'Cooldown must be ≥ 0' };
  return { ok: true };
}

/** Build the next PolicyShape from form values — bumps the version by 1. */
export function buildNextPolicy(values: PolicyFormValues, current: PolicyShape): PolicyShape {
  return {
    policyVersion: current.policyVersion + 1,
    tier1CeilingSats: values.tier1CeilingSats,
    tier2CeilingSats: values.tier2CeilingSats,
    tier3CeilingSats: values.tier3CeilingSats,
    tier1FactorKind: values.tier1FactorKind,
    tier2FactorKind: values.tier2FactorKind,
    tier3FactorKind: values.tier3FactorKind,
    tier3CooldownSeconds: values.tier3CooldownSeconds,
  };
}

/**
 * Submit the policy form. Returns the wallet-ops.updatePolicy Result. Pure
 * (no DOM access) so tests can drive it directly.
 */
export async function runPolicyUpdate(values: PolicyFormValues): Promise<PolicyResult> {
  const v = validatePolicy(values);
  if (!v.ok) return { ok: false, error: { kind: 'BAD_INPUT', reason: v.reason } };
  const cur = getPolicy();
  const next = buildNextPolicy(values, cur);
  return await updatePolicy({ next });
}

export function mountPolicyScreen(
  onUpdated?: (p: PolicyShape) => void,
  onError?: (msg: string) => void,
): void {
  if (typeof document === 'undefined') return;
  const form = document.getElementById('policy-form') as HTMLFormElement | null;
  if (!form) return;
  // Pre-fill from current policy.
  const cur = getPolicy();
  setVal(form, 'tier1CeilingSats', String(cur.tier1CeilingSats));
  setVal(form, 'tier2CeilingSats', String(cur.tier2CeilingSats));
  setVal(form, 'tier3CeilingSats', String(cur.tier3CeilingSats));
  setVal(form, 'tier1FactorKind', cur.tier1FactorKind);
  setVal(form, 'tier2FactorKind', cur.tier2FactorKind);
  setVal(form, 'tier3FactorKind', cur.tier3FactorKind);
  setVal(form, 'tier3CooldownSeconds', String(cur.tier3CooldownSeconds));
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const values = readPolicyForm(form);
    if (!values) return;
    void (async () => {
      const r = await runPolicyUpdate(values);
      if (r.ok) {
        onUpdated?.(r.value);
      } else {
        onError?.(`Policy update failed: ${r.error.kind}`);
      }
    })();
  });
}

function setVal(form: HTMLFormElement, name: string, value: string): void {
  const el = form.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement | null;
  if (el) el.value = value;
}

```
