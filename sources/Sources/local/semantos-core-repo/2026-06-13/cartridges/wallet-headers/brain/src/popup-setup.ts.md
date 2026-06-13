---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/popup-setup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.647262+00:00
---

# cartridges/wallet-headers/brain/src/popup-setup.ts

```ts
// WA1 — Popup screen: post-creation onboarding wizard.
//
// Shown automatically the first time after `createWallet` succeeds, and
// reopenable via the setup-status badge in the main wallet UI. Items the
// wizard surfaces (open-set; new ones can land without schema changes):
//
//   • BACKUP_ENVELOPE  — recommended; multi-target export (Plexus / Drive
//     / download / QR / clipboard / share-sheet)
//   • SETUP_VAULT      — create a Tier-3 vault for higher-value holdings
//   • CONNECT_NODE     — point the wallet at a sovereign node
//   • ENROLL_PLEXUS    — paid recovery mirror with a Plexus operator
//   • HEADERS_SYNCED   — configure BSV header sync / SPV source posture
//
// Skip-without-shame: every option has a clear "skip for now" path that
// doesn't degrade the wallet. Choices persist into the SetupStatus cell.
//
// The screen is rendered as a list of items, each reading one
// SetupStatusCell record and writing back via `setSetupItemStatus`.
// Pure render functions are exported so unit tests can assert the model
// without driving the DOM.

import {
  dismissAllSetupItems,
  getSetupStatus,
  setSetupItemStatus,
  shouldShowVaultNudge,
  summarizeSetup,
  SETUP_ITEM_IDS,
  SETUP_ITEMS_DEFAULT,
  type NudgeDecision,
  type SetupItemId,
  type SetupItemStatus,
  type SetupStatusCell,
  type SetupSummary,
  type PolicyShape,
} from './wallet-ops';

// ──────────────────────────────────────────────────────────────────────
// Model
// ──────────────────────────────────────────────────────────────────────

export interface SetupItemView {
  itemId: SetupItemId;
  title: string;
  description: string;
  ctaLabel: string;
  /** Action codes the popup binds buttons to. */
  primaryAction: SetupAction;
  /** True when the spec marks this as `[recommended]`. */
  recommended: boolean;
  /** Current status from the SetupStatusCell. */
  status: SetupItemStatus;
}

export type SetupAction =
  | 'open-backup-export'
  | 'open-vault-setup'
  | 'open-node-connect'
  | 'open-plexus-enroll';

export interface SetupView {
  /** "Setup: 2 of 4 complete" */
  badgeLabel: string;
  /** Exhaustive item list for the wizard body. */
  items: SetupItemView[];
  /** Highest-priority pending item id (for tooltip on the badge). */
  topPendingItem: SetupItemId | null;
  /** True if the wizard should auto-open after creation. */
  autoOpenOnCreation: boolean;
  /** Read-only summary, useful for the badge consumer. */
  summary: SetupSummary;
}

export interface SetupViewInputs {
  cell: SetupStatusCell;
  /** When true, the auto-open hook has already run once — don't re-open. */
  autoOpenedOnce: boolean;
}

const ITEM_TEMPLATES: Record<SetupItemId, Omit<SetupItemView, 'status'>> = {
  [SETUP_ITEM_IDS.BACKUP_ENVELOPE]: {
    itemId: SETUP_ITEM_IDS.BACKUP_ENVELOPE,
    title: 'Back up your recovery envelope',
    description:
      'Right now your envelope only exists on this device. If your device dies, you lose your identity.',
    ctaLabel: 'Save / Share / Download / QR',
    primaryAction: 'open-backup-export',
    recommended: true,
  },
  [SETUP_ITEM_IDS.SETUP_VAULT]: {
    itemId: SETUP_ITEM_IDS.SETUP_VAULT,
    title: 'Set up a vault for larger amounts',
    description:
      'Your current wallet is for identity + pocket change (~$10). A vault uses stronger challenges and optional hardware keys.',
    ctaLabel: 'Create vault',
    primaryAction: 'open-vault-setup',
    recommended: false,
  },
  [SETUP_ITEM_IDS.CONNECT_NODE]: {
    itemId: SETUP_ITEM_IDS.CONNECT_NODE,
    title: 'Connect a sovereign node',
    description:
      'Run your own backend instead of relying on this wallet origin.',
    ctaLabel: 'Connect',
    primaryAction: 'open-node-connect',
    recommended: false,
  },
  [SETUP_ITEM_IDS.ENROLL_PLEXUS]: {
    itemId: SETUP_ITEM_IDS.ENROLL_PLEXUS,
    title: 'Enroll with a Plexus operator',
    description:
      'A paid mirror keeps a copy of your recovery envelope so you can recover on a fresh device without the local file.',
    ctaLabel: 'Enroll',
    primaryAction: 'open-plexus-enroll',
    recommended: false,
  },
  [SETUP_ITEM_IDS.HEADERS_SYNCED]: {
    itemId: SETUP_ITEM_IDS.HEADERS_SYNCED,
    title: 'Sync BSV headers',
    description:
      'Keep local headers available so SPV checks can run without trusting a remote operator for every wallet action.',
    ctaLabel: 'Configure sync',
    primaryAction: 'open-node-connect',
    recommended: false,
  },
};

/** Pure-state: build the renderable wizard view from a cell + auto-open
 *  flag. Tests assert this view directly; the popup just maps to DOM. */
export function buildSetupView(input: SetupViewInputs): SetupView {
  const summary = summarizeSetup(input.cell);
  const items: SetupItemView[] = SETUP_ITEMS_DEFAULT.map((id) => ({
    ...ITEM_TEMPLATES[id],
    status: input.cell.items[id]?.status ?? 'PENDING',
  }));

  const topPending: SetupItemId | null =
    items.find((it) => it.recommended && it.status === 'PENDING')?.itemId ??
    items.find((it) => it.status === 'PENDING')?.itemId ??
    null;

  return {
    badgeLabel: `Setup: ${summary.completeCount} of ${summary.totalCount} complete`,
    items,
    topPendingItem: topPending,
    autoOpenOnCreation: !input.autoOpenedOnce && !summary.allDone,
    summary,
  };
}

// ──────────────────────────────────────────────────────────────────────
// Auto-open lifecycle
// ──────────────────────────────────────────────────────────────────────

const AUTO_OPENED_KEY = 'setup-wizard-auto-opened';

/** Module-local fallback for environments without sessionStorage (bun
 *  tests, sovereign-node JS). Behaves like sessionStorage within one
 *  process lifetime — exactly what the wizard's "open once per session"
 *  semantics require. */
let autoOpenedMemoryFlag = false;

function readAutoOpenedFlag(): boolean {
  if (typeof sessionStorage !== 'undefined') {
    return sessionStorage.getItem(AUTO_OPENED_KEY) === '1';
  }
  return autoOpenedMemoryFlag;
}

function writeAutoOpenedFlag(value: boolean): void {
  if (typeof sessionStorage !== 'undefined') {
    if (value) sessionStorage.setItem(AUTO_OPENED_KEY, '1');
    else sessionStorage.removeItem(AUTO_OPENED_KEY);
    return;
  }
  autoOpenedMemoryFlag = value;
}

export interface AutoOpenContext {
  /** True when the wallet is mid-`/connect` handshake (mobile redirect
   *  flow per WALLET-MOBILE-AUTH-FLOW.md). The wizard MUST stay closed —
   *  the user is focused on confirming a dApp grant, not onboarding. The
   *  WSITE/connect handler reopens the wizard via `markWizardPostConnect()`
   *  after the callback succeeds. */
  inConnectFlow?: boolean;
  /** True when the wallet is rendering inside an iframe (desktop popup
   *  pattern). Auto-open is fine in popups; this is here for symmetry
   *  + future tuning. */
  inPopup?: boolean;
}

/** Should the wizard auto-open right now? Returns true *exactly once*
 *  per session after wallet creation; subsequent calls are false until
 *  the flag is cleared. Falls back to a process-local flag when
 *  sessionStorage is absent (test environment, sovereign-node).
 *
 *  Pass `{ inConnectFlow: true }` from the `/connect` redirect handler so
 *  the wizard doesn't fire during a dApp auth handshake. */
export async function shouldAutoOpenWizard(
  context: AutoOpenContext = {},
): Promise<boolean> {
  if (context.inConnectFlow) return false;
  const cell = await getSetupStatus();
  const summary = summarizeSetup(cell);
  if (summary.allDone) return false;
  return !readAutoOpenedFlag();
}

/** Called by the connect-flow handler after the dApp callback completes
 *  successfully. Forces the next `shouldAutoOpenWizard()` call to fire
 *  (assuming the user's first wallet creation just happened). */
export function markWizardPostConnect(): void {
  // Implementation: clear the auto-opened flag so the next idle render
  // can show the wizard. The actual reopen is a UI decision — this just
  // unblocks `shouldAutoOpenWizard()`.
  writeAutoOpenedFlag(false);
}

export function markWizardAutoOpened(): void {
  writeAutoOpenedFlag(true);
}

export function _clearAutoOpenForTests(): void {
  writeAutoOpenedFlag(false);
}

// ──────────────────────────────────────────────────────────────────────
// Wizard click handlers
// ──────────────────────────────────────────────────────────────────────

export interface WizardChoiceInput {
  itemId: SetupItemId;
  choice: 'COMPLETE' | 'SKIP' | 'DISMISS';
}

/** Persist a single user click. Returns the refreshed view so the popup
 *  re-renders without an extra read. */
export async function applyWizardChoice(
  input: WizardChoiceInput,
): Promise<SetupView> {
  const status: SetupItemStatus =
    input.choice === 'COMPLETE'
      ? 'COMPLETE'
      : input.choice === 'SKIP'
        ? 'SKIPPED'
        : 'DISMISSED';
  const cell = await setSetupItemStatus(input.itemId, status);
  return buildSetupView({ cell, autoOpenedOnce: true });
}

/** "Skip all" path — every still-pending item becomes DISMISSED. The
 *  wallet keeps working; the badge shows "0 of 4 complete" but no
 *  contextual nudge fires unless budget exceeds the threshold. */
export async function skipAll(): Promise<SetupView> {
  const cell = await dismissAllSetupItems();
  return buildSetupView({ cell, autoOpenedOnce: true });
}

// ──────────────────────────────────────────────────────────────────────
// Contextual nudge banner
// ──────────────────────────────────────────────────────────────────────

export interface NudgeBannerView {
  show: boolean;
  /** Headline string, sat amount + threshold formatted. */
  headline: string;
  /** Sub-line describing what to do. */
  body: string;
  /** Items to flag for COMPLETE if the user follows the CTA. */
  ctaItem: SetupItemId;
}

export function buildNudgeBanner(
  decision: NudgeDecision,
  hotBudgetSats: bigint,
): NudgeBannerView {
  if (!decision.show) {
    return {
      show: false,
      headline: '',
      body: '',
      ctaItem: SETUP_ITEM_IDS.SETUP_VAULT,
    };
  }
  const formattedSats = formatSats(hotBudgetSats);
  const formattedThreshold = formatSats(decision.thresholdSats);
  return {
    show: true,
    headline: `You're holding ${formattedSats} sats in this wallet.`,
    body: `The identity wallet is designed for ~${formattedThreshold} sats of pocket change. Consider setting up a vault.`,
    ctaItem: SETUP_ITEM_IDS.SETUP_VAULT,
  };
}

function formatSats(s: bigint): string {
  const str = s.toString();
  // Insert thousands separators for legibility.
  return str.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** Compose nudge + view in one call for the popup; reuses the nudge
 *  decision so callers don't recompute. */
export interface SetupPanelView {
  setup: SetupView;
  nudge: NudgeBannerView;
}

export async function buildSetupPanel(input: {
  hotBudgetSats: bigint;
  policy: PolicyShape;
}): Promise<SetupPanelView> {
  const cell = await getSetupStatus();
  const setup = buildSetupView({ cell, autoOpenedOnce: true });
  const decision = shouldShowVaultNudge({
    hotBudgetSats: input.hotBudgetSats,
    policy: input.policy,
  });
  const nudge = buildNudgeBanner(decision, input.hotBudgetSats);
  return { setup, nudge };
}

// ──────────────────────────────────────────────────────────────────────
// DOM rendering (browser only — guarded by `typeof document`).
// ──────────────────────────────────────────────────────────────────────

export async function renderSetupPanel(input: {
  hotBudgetSats: bigint;
  policy: PolicyShape;
}): Promise<SetupPanelView> {
  const view = await buildSetupPanel(input);
  if (typeof document === 'undefined') return view;

  setText('setup-badge', view.setup.badgeLabel);

  const container = document.getElementById('setup-items');
  if (container) {
    container.innerHTML = '';
    for (const item of view.setup.items) {
      const row = document.createElement('div');
      row.className = `setup-item setup-item-${item.status.toLowerCase()}`;
      row.dataset.itemId = item.itemId;

      const title = document.createElement('div');
      title.className = 'setup-title';
      title.textContent = item.recommended
        ? `${item.title}  [recommended]`
        : item.title;

      const desc = document.createElement('div');
      desc.className = 'setup-description';
      desc.textContent = item.description;

      const cta = document.createElement('button');
      cta.className = 'setup-cta';
      cta.textContent = item.ctaLabel;
      cta.dataset.action = item.primaryAction;

      const skip = document.createElement('button');
      skip.className = 'setup-skip';
      skip.textContent = 'Skip for now';
      skip.dataset.action = `skip:${item.itemId}`;

      row.append(title, desc, cta, skip);
      container.append(row);
    }
  }

  const banner = document.getElementById('setup-nudge');
  if (banner) {
    banner.classList.toggle('hidden', !view.nudge.show);
    setText('setup-nudge-headline', view.nudge.headline);
    setText('setup-nudge-body', view.nudge.body);
  }

  return view;
}

function setText(id: string, value: string): void {
  if (typeof document === 'undefined') return;
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

```
