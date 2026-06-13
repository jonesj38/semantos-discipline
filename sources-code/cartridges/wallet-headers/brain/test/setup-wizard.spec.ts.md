---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/setup-wizard.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.673855+00:00
---

# cartridges/wallet-headers/brain/test/setup-wizard.spec.ts

```ts
// WA1 — Onboarding wizard tests.
//
// Per WALLET-ACTIVE-USE-ROADMAP.md §2 / WA1 deliverable 6:
//   Unit tests for SetupStatus persistence, wizard navigation, contextual
//   nudge triggers.
//
// Coverage:
//   • SetupStatus cell defaults to PENDING for every default item.
//   • applyWizardChoice persists COMPLETE/SKIP/DISMISS correctly.
//   • skipAll marks every PENDING item DISMISSED.
//   • buildSetupView computes the right badge label + topPendingItem.
//   • Auto-open lifecycle: shouldAutoOpenWizard returns true once, then
//     false after markWizardAutoOpened until session reset.
//   • Contextual nudge: shows when hotBudget > min(2× tier1Ceiling, $10).
//   • Nudge respects the lower of the two thresholds.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  getSetupStatus,
  setSetupItemStatus,
  dismissAllSetupItems,
  summarizeSetup,
  shouldShowVaultNudge,
  SETUP_ITEM_IDS,
  NUDGE_USD_THRESHOLD_SATS,
  DEFAULT_POLICY,
  _resetRuntimeForTests,
} from '../src/wallet-ops';
import {
  buildSetupView,
  applyWizardChoice,
  skipAll,
  buildSetupPanel,
  shouldAutoOpenWizard,
  markWizardAutoOpened,
  buildNudgeBanner,
  _clearAutoOpenForTests,
} from '../src/popup-setup';
import { _resetDbForTests } from '../src/storage';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

function freshCreateInputs() {
  return {
    challengeQuestions: ["Mother's maiden name?", 'City of birth?', 'First pet?'] as [string, string, string],
    challengeAnswers: ['Smith', 'Sydney', 'Rover'] as [string, string, string],
    contactEmail: 'user@example.com',
    tier1Pin: new TextEncoder().encode('1234'),
    tier2Factor: new TextEncoder().encode('passphrase'),
    tier3Factor: new TextEncoder().encode('vault'),
  };
}

beforeEach(() => {
  _resetRuntimeForTests();
  _resetDbForTests();
  _clearAutoOpenForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

describe('WA1 — SetupStatus persistence', () => {
  test('initial state: every default item is PENDING', async () => {
    await createWallet(freshCreateInputs());
    const cell = await getSetupStatus();
    expect(cell.formatVersion).toBe(1);
    for (const id of Object.values(SETUP_ITEM_IDS)) {
      expect(cell.items[id]?.status).toBe('PENDING');
    }
    const summary = summarizeSetup(cell);
    expect(summary.completeCount).toBe(0);
    expect(summary.totalCount).toBe(5);
    expect(summary.allDone).toBe(false);
  });

  test('setSetupItemStatus persists the new status', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');
    const cell = await getSetupStatus();
    expect(cell.items[SETUP_ITEM_IDS.BACKUP_ENVELOPE]?.status).toBe('COMPLETE');
    const summary = summarizeSetup(cell);
    expect(summary.completeCount).toBe(1);
    expect(summary.pendingItems).not.toContain(SETUP_ITEM_IDS.BACKUP_ENVELOPE);
  });

  test('dismissAllSetupItems flips every PENDING → DISMISSED but leaves COMPLETE alone', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');

    await dismissAllSetupItems();

    const cell = await getSetupStatus();
    expect(cell.items[SETUP_ITEM_IDS.BACKUP_ENVELOPE]?.status).toBe('COMPLETE');
    expect(cell.items[SETUP_ITEM_IDS.SETUP_VAULT]?.status).toBe('DISMISSED');
    expect(cell.items[SETUP_ITEM_IDS.CONNECT_NODE]?.status).toBe('DISMISSED');
    expect(cell.items[SETUP_ITEM_IDS.ENROLL_PLEXUS]?.status).toBe('DISMISSED');
  });

  test('SetupStatus survives runtime reset (persists across reload)', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.SETUP_VAULT, 'COMPLETE');

    _resetRuntimeForTests();

    const cell = await getSetupStatus();
    expect(cell.items[SETUP_ITEM_IDS.SETUP_VAULT]?.status).toBe('COMPLETE');
  });
});

describe('WA1 — buildSetupView', () => {
  test('badge label reflects completed count', async () => {
    await createWallet(freshCreateInputs());
    const cell = await getSetupStatus();
    const view = buildSetupView({ cell, autoOpenedOnce: false });
    expect(view.badgeLabel).toBe('Setup: 0 of 5 complete');

    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.SETUP_VAULT, 'COMPLETE');
    const view2 = buildSetupView({ cell: await getSetupStatus(), autoOpenedOnce: true });
    expect(view2.badgeLabel).toBe('Setup: 2 of 5 complete');
  });

  test('topPendingItem prefers a recommended item over non-recommended', async () => {
    await createWallet(freshCreateInputs());
    const view = buildSetupView({ cell: await getSetupStatus(), autoOpenedOnce: true });
    // BACKUP_ENVELOPE is the only [recommended] item in v0.1.
    expect(view.topPendingItem).toBe(SETUP_ITEM_IDS.BACKUP_ENVELOPE);
  });

  test('autoOpenOnCreation is true on a fresh cell, false after first open', async () => {
    await createWallet(freshCreateInputs());
    const view1 = buildSetupView({
      cell: await getSetupStatus(),
      autoOpenedOnce: false,
    });
    expect(view1.autoOpenOnCreation).toBe(true);

    const view2 = buildSetupView({
      cell: await getSetupStatus(),
      autoOpenedOnce: true,
    });
    expect(view2.autoOpenOnCreation).toBe(false);
  });

  test('autoOpenOnCreation is false when every item is done', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.SETUP_VAULT, 'SKIPPED');
    await setSetupItemStatus(SETUP_ITEM_IDS.CONNECT_NODE, 'DISMISSED');
    await setSetupItemStatus(SETUP_ITEM_IDS.ENROLL_PLEXUS, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.HEADERS_SYNCED, 'DISMISSED');

    const view = buildSetupView({
      cell: await getSetupStatus(),
      autoOpenedOnce: false,
    });
    expect(view.autoOpenOnCreation).toBe(false);
  });
});

describe('WA1 — wizard navigation', () => {
  test('applyWizardChoice persists COMPLETE / SKIP / DISMISS', async () => {
    await createWallet(freshCreateInputs());

    const v1 = await applyWizardChoice({
      itemId: SETUP_ITEM_IDS.BACKUP_ENVELOPE,
      choice: 'COMPLETE',
    });
    expect(v1.summary.completeCount).toBe(1);

    const v2 = await applyWizardChoice({
      itemId: SETUP_ITEM_IDS.SETUP_VAULT,
      choice: 'SKIP',
    });
    expect(v2.summary.completeCount).toBe(1);

    const v3 = await applyWizardChoice({
      itemId: SETUP_ITEM_IDS.CONNECT_NODE,
      choice: 'DISMISS',
    });
    expect(v3.summary.pendingItems).not.toContain(SETUP_ITEM_IDS.CONNECT_NODE);

    const cell = await getSetupStatus();
    expect(cell.items[SETUP_ITEM_IDS.BACKUP_ENVELOPE]?.status).toBe('COMPLETE');
    expect(cell.items[SETUP_ITEM_IDS.SETUP_VAULT]?.status).toBe('SKIPPED');
    expect(cell.items[SETUP_ITEM_IDS.CONNECT_NODE]?.status).toBe('DISMISSED');
  });

  test('skipAll marks every pending DISMISSED in one call', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');

    const view = await skipAll();
    expect(view.summary.allDone).toBe(true);
    expect(view.summary.completeCount).toBe(1); // still 1 — DISMISSED isn't complete
    const cell = await getSetupStatus();
    expect(cell.items[SETUP_ITEM_IDS.SETUP_VAULT]?.status).toBe('DISMISSED');
  });
});

describe('WA1 — auto-open lifecycle', () => {
  test('shouldAutoOpenWizard is true on a fresh wallet, false after mark', async () => {
    await createWallet(freshCreateInputs());
    expect(await shouldAutoOpenWizard()).toBe(true);

    markWizardAutoOpened();
    expect(await shouldAutoOpenWizard()).toBe(false);
  });

  test('shouldAutoOpenWizard returns false once every item is done', async () => {
    await createWallet(freshCreateInputs());
    await setSetupItemStatus(SETUP_ITEM_IDS.BACKUP_ENVELOPE, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.SETUP_VAULT, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.CONNECT_NODE, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.ENROLL_PLEXUS, 'COMPLETE');
    await setSetupItemStatus(SETUP_ITEM_IDS.HEADERS_SYNCED, 'COMPLETE');

    expect(await shouldAutoOpenWizard()).toBe(false);
  });
});

describe('WA1 — contextual budget nudge', () => {
  test('no nudge below threshold', () => {
    const decision = shouldShowVaultNudge({
      hotBudgetSats: 100_000n,
      policy: DEFAULT_POLICY,
    });
    expect(decision.show).toBe(false);
    expect(decision.excessSats).toBe(0n);
  });

  test('nudge fires when budget exceeds 2× tier1 ceiling', () => {
    // DEFAULT_POLICY.tier1CeilingSats = 1_000_000 → 2× = 2_000_000
    // NUDGE_USD_THRESHOLD_SATS = 2_000_000 → both equal, threshold = 2_000_000
    const decision = shouldShowVaultNudge({
      hotBudgetSats: 2_500_000n,
      policy: DEFAULT_POLICY,
    });
    expect(decision.show).toBe(true);
    expect(decision.thresholdSats).toBe(2_000_000n);
    expect(decision.excessSats).toBe(500_000n);
  });

  test('threshold picks the lower of (2× tier1, $10-eq)', () => {
    // Lower tier1 → policy cap dominates.
    const lowPolicy = { ...DEFAULT_POLICY, tier1CeilingSats: 100_000 };
    const decision = shouldShowVaultNudge({
      hotBudgetSats: 250_000n,
      policy: lowPolicy,
    });
    expect(decision.show).toBe(true);
    expect(decision.thresholdSats).toBe(200_000n); // 2× 100_000

    // Higher tier1 → $10-eq dominates.
    const highPolicy = { ...DEFAULT_POLICY, tier1CeilingSats: 50_000_000 };
    const decision2 = shouldShowVaultNudge({
      hotBudgetSats: 3_000_000n,
      policy: highPolicy,
    });
    expect(decision2.show).toBe(true);
    expect(decision2.thresholdSats).toBe(NUDGE_USD_THRESHOLD_SATS);
  });

  test('buildNudgeBanner formats sats with thousand-separators', () => {
    const decision = shouldShowVaultNudge({
      hotBudgetSats: 5_000_000n,
      policy: DEFAULT_POLICY,
    });
    const view = buildNudgeBanner(decision, 5_000_000n);
    expect(view.show).toBe(true);
    expect(view.headline).toContain('5,000,000');
    expect(view.body).toContain('2,000,000');
    expect(view.ctaItem).toBe(SETUP_ITEM_IDS.SETUP_VAULT);
  });

  test('buildSetupPanel composes setup view + nudge in one call', async () => {
    await createWallet(freshCreateInputs());
    const panel = await buildSetupPanel({
      hotBudgetSats: 5_000_000n,
      policy: DEFAULT_POLICY,
    });
    expect(panel.setup.summary.totalCount).toBe(5);
    expect(panel.nudge.show).toBe(true);
  });
});

```
