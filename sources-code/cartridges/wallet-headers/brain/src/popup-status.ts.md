---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.652215+00:00
---

# cartridges/wallet-headers/brain/src/popup-status.ts

```ts
// Popup screen — wallet status panel (W9, design §10.3).
//
// Default landing screen when a wallet exists. Shows:
//   • current identity public key (truncated middle, full on hover)
//   • recovery enrollment status banner (delegates to popup-plexus.ts)
//   • per-tier ceilings + factor kinds (read from POLICY)
//   • last Tier-3 spend timestamp (cooldown indicator)
//   • hot-budget remaining sats
//   • whether each tier blob is enrolled (i.e., a tier blob exists on disk)

import { getStatus, type WalletStatus, type WalletError, type Result } from './wallet-ops';

export type StatusResult = Result<WalletStatus, WalletError>;

/**
 * Pure-state: produce the rendered status text fields. Pure because the
 * status panel is read-only — no user input flows through here, only into
 * the policy-editor / send screens. Tests assert the formatting.
 */
export interface StatusFields {
  identityKeyTruncated: string;
  identityKeyFull: string;
  recoveryLabel: string;
  tier1Label: string;
  tier2Label: string;
  tier3Label: string;
  hotBudgetLabel: string;
  tier0ExposureLabel: string;
  tier3LastSpendLabel: string;
  enrollmentLabel: string;
}

export function formatStatus(s: WalletStatus): StatusFields {
  const truncated =
    s.identityKeyHex.length > 16
      ? `${s.identityKeyHex.slice(0, 8)}…${s.identityKeyHex.slice(-8)}`
      : s.identityKeyHex;

  const recoveryLabel =
    s.recovery.state === 'LOCAL_ONLY'
      ? 'Recovery: not configured'
      : s.recovery.state === 'ENROLLED'
        ? `Recovery: enrolled (${s.recovery.operatorDomain})`
        : `Recovery: expired (${s.recovery.operatorDomain})`;

  const tierLine = (n: 1 | 2 | 3, ceiling: number, kind: string): string => {
    const enrolled = n === 1 ? s.tierEnrolled.tier1 : n === 2 ? s.tierEnrolled.tier2 : s.tierEnrolled.tier3;
    return `Tier ${n}: ≤ ${ceiling.toLocaleString()} sats (${kind})${enrolled ? '' : ' — not enrolled'}`;
  };

  const tier3Last = s.tier3LastSpendAt
    ? `Last Tier-3 spend: ${new Date(s.tier3LastSpendAt * 1000).toISOString()}`
    : 'Last Tier-3 spend: (none)';

  const enrollmentLabel = `Tier blobs: ${s.tierEnrolled.tier1 ? '1 ' : ''}${s.tierEnrolled.tier2 ? '2 ' : ''}${s.tierEnrolled.tier3 ? '3' : ''}`.trim();
  const exposure = s.tier0PlaintextExposure;
  const tier0ExposureLabel = exposure.sweepRequired
    ? `Tier-0 plaintext exposure: ${Number(exposure.balanceSats).toLocaleString()} sats (${Number(exposure.excessSats).toLocaleString()} over cap; sweep to Tier ${exposure.sweepTargetTier})`
    : `Tier-0 plaintext exposure: ${Number(exposure.balanceSats).toLocaleString()} / ${Number(exposure.limitSats).toLocaleString()} sats`;

  return {
    identityKeyTruncated: truncated,
    identityKeyFull: s.identityKeyHex,
    recoveryLabel,
    tier1Label: tierLine(1, s.policy.tier1CeilingSats, s.policy.tier1FactorKind),
    tier2Label: tierLine(2, s.policy.tier2CeilingSats, s.policy.tier2FactorKind),
    tier3Label: tierLine(3, s.policy.tier3CeilingSats, s.policy.tier3FactorKind),
    hotBudgetLabel: `Hot budget remaining: ${s.hotBudgetRemainingSats} sats`,
    tier0ExposureLabel,
    tier3LastSpendLabel: tier3Last,
    enrollmentLabel,
  };
}

/** Refresh the status DOM elements from the latest wallet state. Returns
 *  the StatusResult so the popup router can decide between "show status"
 *  and "show create wallet". */
export async function renderStatus(): Promise<StatusResult> {
  const r = await getStatus();
  if (typeof document === 'undefined') return r;
  if (!r.ok) return r;
  const f = formatStatus(r.value);
  setText('status-identity-truncated', f.identityKeyTruncated);
  setAttr('status-identity-full', 'title', f.identityKeyFull);
  setText('status-recovery', f.recoveryLabel);
  setText('status-tier1', f.tier1Label);
  setText('status-tier2', f.tier2Label);
  setText('status-tier3', f.tier3Label);
  setText('status-hot-budget', f.hotBudgetLabel);
  setText('status-tier0-exposure', f.tier0ExposureLabel);
  setText('status-tier3-last', f.tier3LastSpendLabel);
  setText('status-enrolled', f.enrollmentLabel);
  return r;
}

function setText(id: string, text: string): void {
  const el = document.getElementById(id);
  if (el) el.textContent = text;
}

function setAttr(id: string, attr: string, value: string): void {
  const el = document.getElementById(id);
  if (el) el.setAttribute(attr, value);
}

```
