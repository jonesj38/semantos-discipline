---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/lib/legal-cards.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.383777+00:00
---

# scripts/lib/legal-cards.ts

```ts
/**
 * legal-cards.ts — TypeScript port of legal-cards.mjs, importing real types
 * from @semantos/semantos-sir. Compiling this file with `tsc --noEmit` is the
 * cheapest integrity check between the renderer and the canonical SIR shape:
 * any drift in `SIRNode`, `GovernanceContext`, or `DelegationChain` shows up
 * as a type error here.
 *
 * The .mjs sibling remains the hermetic demo runner (no build step required).
 * This .ts file is the source of truth for type conformance and unit tests.
 */

import type {
  SIRNode,
  JuralCategory,
  GovernanceContext,
  DelegationChain,
  TrustClass,
  ProofRequirement,
  IdentityRef,
  LinearityMode,
  SIRFulfillment,
} from '../../packages/semantos-sir/src/types';

// ── LegalPatch — the render-layer view of a proposal ──────────────────────
// Distinct from @semantos/loom's ObjectPatch: LegalPatch carries a nested
// SIRNode and uses `hatId` (post-rename). Transport-layer conversions live
// in `toObjectPatch` / `fromObjectPatch` below.

export type LegalPatchKind =
  | 'extraction'        // AI or human proposal
  | 'companion'         // auto-materialised from a primary (obligation → permission/transfer)
  | 'manual_override'   // direct curator edit
  | 'rejection'         // curator declined, reason recorded
  | 'state_transition'; // fulfilment / completion event

export interface LegalPatch {
  id: string;
  kind: LegalPatchKind;
  hatId: string;
  timestamp: number;
  /** The canonical SIR expression this patch carries. */
  sir: SIRNode;
  /** Human / AI delta payload for template rendering (amounts, descriptions). */
  delta: Record<string, unknown>;
  /** If this is a companion, which primary patch it was derived from. */
  companionOf?: string;
  /** If this is a rejection, which patch was rejected. */
  targetPatchId?: string;
  /** Recorded rejection reason, if kind === 'rejection'. */
  reason?: string;
  /** Curator signature on rejection, if applicable. */
  curatorSignature?: string;
}

// ── Bundle primitives (mirror @semantos/loom/helm/document-bundle) ───────
// Re-implemented with LegalPatch-compatible types. The logic is identical to
// the source module; the test suite has a round-trip test (§roundtrip) that
// verifies LegalPatch → ObjectPatch → LegalPatch preserves information.

export interface LegalBundle {
  version: 1;
  exportedAt: number;
  exportedBy: string;
  documentId: string;
  patches: LegalPatch[];
  linearity: number;
}

export const exportBundle = (
  documentId: string,
  patches: LegalPatch[],
  exportedBy: string,
): LegalBundle => ({
  version: 1,
  exportedAt: Date.now(),
  exportedBy,
  documentId,
  patches: patches.map((p) => ({ ...p, sir: { ...p.sir }, delta: { ...p.delta } })),
  linearity: patches.length,
});

export const diffPatches = (base: LegalPatch[], incoming: LegalPatch[]): LegalPatch[] => {
  const baseIds = new Set(base.map((p) => p.id));
  return incoming.filter((p) => !baseIds.has(p.id));
};

export const mergePatches = (
  existing: LegalPatch[],
  selected: LegalPatch[],
): LegalPatch[] => {
  const existingIds = new Set(existing.map((p) => p.id));
  const novel = selected.filter((p) => !existingIds.has(p.id));
  return [...existing, ...novel].sort((a, b) => a.timestamp - b.timestamp);
};

// ── Companion-patch materialisation ──────────────────────────────────────

export const materialiseCompanions = (obligation: LegalPatch): LegalPatch[] => {
  if (obligation.sir.category !== 'obligation') return [];
  const f: SIRFulfillment | undefined = obligation.sir.fulfillment;
  const target = obligation.sir.target ?? {};
  const deadline = f?.deadline ?? '2099-01-01T00:00:00Z';

  const permissionSir: SIRNode = {
    id: `${obligation.sir.id}--perm`,
    category: 'permission',
    action: 'enter_premises',
    taxonomy: obligation.sir.taxonomy,
    identity: obligation.sir.identity,
    target,
    governance: {
      trustClass: 'interpretive',
      proofRequirement: 'attestation',
      executionAuthority: 'hat_scoped',
      linearity: 'AFFINE',
    },
    constraint: {
      kind: 'composite',
      op: 'and',
      children: [
        { kind: 'temporal', op: 'before', iso: deadline },
        { kind: 'state', requiredPhase: 'works-in-progress' },
      ],
    },
    provenance: {
      source: 'inferred',
      confidence: 1.0,
      expressedAt: new Date(obligation.timestamp + 1).toISOString(),
      trustAtExpression: 'interpretive',
    },
  };

  const ownerIdentity: IdentityRef = { kind: 'hat', id: 'hat-owner' } as unknown as IdentityRef;
  const transferSir: SIRNode = {
    id: `${obligation.sir.id}--pay`,
    category: 'transfer',
    action: 'pay_contractor',
    taxonomy: obligation.sir.taxonomy,
    identity: { subject: ownerIdentity },
    target,
    transferTo: obligation.sir.identity,
    governance: {
      trustClass: 'interpretive',
      proofRequirement: 'attestation',
      executionAuthority: 'hat_scoped',
      linearity: 'LINEAR',
    },
    constraint: { kind: 'state', requiredPhase: 'fulfilled' },
    provenance: {
      source: 'inferred',
      confidence: 1.0,
      expressedAt: new Date(obligation.timestamp + 2).toISOString(),
      trustAtExpression: 'interpretive',
    },
  };

  return [
    {
      id: `${obligation.id}--perm`,
      kind: 'companion',
      hatId: obligation.hatId,
      timestamp: obligation.timestamp + 1,
      sir: permissionSir,
      delta: {
        action: 'grant_permission',
        companionOf: obligation.id,
        hours: 'weekdays 08:00–17:00',
        scope: target.objectId ?? 'premises',
      },
      companionOf: obligation.id,
    },
    {
      id: `${obligation.id}--pay`,
      kind: 'companion',
      hatId: 'hat-owner',
      timestamp: obligation.timestamp + 2,
      sir: transferSir,
      delta: {
        action: 'schedule_payment',
        amount: (obligation.delta.amount as number | undefined),
        currency: (obligation.delta.currency as string | undefined) ?? 'AUD',
        conditionalOn: `${obligation.id}.fulfilled`,
      },
      companionOf: obligation.id,
    },
  ];
};

// ── Card templates ───────────────────────────────────────────────────────

interface RenderedBody {
  header: string;
  plain: string;
  enables: string[];
  forecloses: string[];
}

const renderIdentity = (sir: SIRNode): string => {
  const i = sir.identity ?? ({} as SIRNode['identity']);
  const withFacet = i as unknown as { facetId?: string };
  const withHat = i as unknown as { hatId?: string };
  return (
    withHat.hatId ??
    withFacet.facetId ??
    (i.subject && (i.subject as unknown as { id?: string }).id) ??
    'unknown'
  );
};

const renderAttestation = (gov: GovernanceContext | undefined): string => {
  if (!gov) return 'unknown';
  const tc: TrustClass = gov.trustClass;
  const pr: ProofRequirement = gov.proofRequirement;
  if (tc === 'authoritative' && pr === 'formal')
    return 'authoritative → requires FORMAL attestation from hat-legal';
  if (tc === 'interpretive' && pr === 'attestation')
    return 'interpretive → requires attestation from hat-rea';
  if (tc === 'cosmetic' && pr === 'none')
    return 'cosmetic → no attestation required';
  return `${tc} → ${pr}`;
};

const fmtMoney = (amt: unknown, ccy: string = 'AUD'): string => {
  if (amt == null || typeof amt !== 'number') return '';
  return new Intl.NumberFormat('en-AU', {
    style: 'currency',
    currency: ccy,
    maximumFractionDigits: 0,
  }).format(amt);
};

const fmtDate = (iso: string | undefined): string => (iso ? iso.slice(0, 10) : '');

type Template = (p: LegalPatch) => RenderedBody;

const templates: Record<JuralCategory, Template> = {
  declaration: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const tgt = s.target?.objectId ?? '(target)';
    const d = p.delta as { statement?: string; enables?: string[]; forecloses?: string[] };
    return {
      header: `DECLARATION · ${s.action}`,
      plain: `${by} declares: ${d.statement ?? s.action} concerning ${tgt}.`,
      enables: d.enables ?? [],
      forecloses: d.forecloses ?? [],
    };
  },

  power: (p) => {
    const s = p.sir;
    const d: DelegationChain | undefined = s.governance?.domainBinding?.delegation;
    const grantor = (d?.delegator as unknown as { id?: string })?.id ?? renderIdentity(s);
    const grantee = (d?.delegate as unknown as { id?: string })?.id ?? '(delegate)';
    const powers: string[] = d?.delegatedPowers ?? [];
    const restrictions: string[] = d?.restrictions ?? [];
    const expiry = d?.expiry ? ` (expires ${fmtDate(d.expiry)})` : '';
    return {
      header: `POWER · ${s.action}`,
      plain: `${grantor} grants ${grantee} authority to: ${powers.join(', ')}${expiry}.`,
      enables: powers.map((x) => `${grantee} may ${x}`),
      forecloses: [
        ...restrictions.map((r) => `${grantee} ${r}`),
        ...(d?.canSubDelegate === false ? [`${grantee} cannot sub-delegate`] : []),
      ],
    };
  },

  obligation: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const d = p.delta as { description?: string; amount?: number; currency?: string };
    const desc = d.description ?? s.action;
    const amount = d.amount ? ` for ${fmtMoney(d.amount, d.currency)}` : '';
    const deadline = s.fulfillment?.deadline ? ` by ${fmtDate(s.fulfillment.deadline)}` : '';
    return {
      header: `OBLIGATION · ${s.action}`,
      plain: `${by} undertakes to ${desc}${deadline}${amount}.`,
      enables: d.amount ? [`Claim on ${fmtMoney(d.amount, d.currency)} upon fulfilment`] : [],
      forecloses: [
        `${by} cannot subcontract without owner consent`,
        `${by} cannot vary scope without approval patch`,
      ],
    };
  },

  permission: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const d = p.delta as { scope?: string; hours?: string };
    const scope = d.scope ?? s.target?.objectId ?? '(scope)';
    const hours = d.hours ?? 'as specified';
    const companion = p.companionOf ? ` (companion to ${p.companionOf})` : '';
    return {
      header: `PERMISSION · ${s.action}${companion}`,
      plain: `${by} is permitted to enter ${scope}, ${hours}.`,
      enables: [`Lawful entry during ${hours}`, `Use of designated areas only`],
      forecloses: [
        `No entry outside specified hours`,
        `No access beyond the declared scope`,
      ],
    };
  },

  prohibition: (p) => {
    const s = p.sir;
    const d = p.delta as {
      subject?: string;
      prohibitedAct?: string;
      enables?: string[];
      additionalForecloses?: string[];
    };
    const subject = d.subject ?? renderIdentity(s);
    const act = d.prohibitedAct ?? s.action;
    return {
      header: `PROHIBITION · ${s.action}`,
      plain: `${subject} is prohibited from: ${act}.`,
      enables: d.enables ?? [],
      forecloses: [act, ...(d.additionalForecloses ?? [])],
    };
  },

  condition: (p) => {
    const s = p.sir;
    const d = p.delta as { description?: string; requires?: string[] };
    const desc = d.description ?? s.action;
    const requires = d.requires ?? [];
    return {
      header: `CONDITION · ${s.action}`,
      plain: `${desc} is valid only when the following hold: ${
        requires.join('; ') || '(none specified)'
      }.`,
      enables: requires.map((r) => `Downstream action unlocked once: ${r}`),
      forecloses: [`Downstream action blocked while any prerequisite is unmet`],
    };
  },

  transfer: (p) => {
    const s = p.sir;
    const from = renderIdentity(s);
    const to =
      (s.transferTo?.subject as unknown as { id?: string })?.id ??
      (s.transferTo as unknown as { hatId?: string })?.hatId ??
      '(recipient)';
    const d = p.delta as { amount?: number; currency?: string; conditionalOn?: string };
    const amount = d.amount ? fmtMoney(d.amount, d.currency) : '(value)';
    const cond = d.conditionalOn ? ` conditional on ${d.conditionalOn}` : '';
    return {
      header: `TRANSFER · ${s.action}`,
      plain: `${from} transfers ${amount} to ${to}${cond}.`,
      enables: [`${to} receives ${amount} upon condition`],
      forecloses: [`${from} balance reduced by ${amount} once executed`],
    };
  },
};

// ── The renderer ─────────────────────────────────────────────────────────

export const renderCard = (patch: LegalPatch): string => {
  const tmpl = templates[patch.sir.category];
  if (!tmpl) throw new Error(`no template for category: ${patch.sir.category}`);
  const body = tmpl(patch);
  const prov = patch.sir.provenance;
  const conf = prov?.confidence != null ? `, confidence ${prov.confidence.toFixed(2)}` : '';
  const proposer = patch.hatId + (prov?.source === 'inferred' ? conf : '');
  const where = patch.sir.taxonomy?.where ?? '';
  const db = patch.sir.governance?.domainBinding;
  const domain = db ? `${db.domainType}${where ? ' · ' + where : ''}` : where;
  const attestation = renderAttestation(patch.sir.governance);
  const lines: string[] = [];
  lines.push(`PROPOSED: ${body.header}   (by ${proposer})`);
  lines.push(`  patch id: ${patch.id}   category: ${patch.sir.category}`);
  if (domain) lines.push(`  domain:   ${domain}`);
  lines.push(`  ${attestation}`);
  lines.push(``);
  lines.push(`  In plain terms:`);
  lines.push(`    ${body.plain}`);
  if (body.enables.length) {
    lines.push(``);
    lines.push(`  Enables:`);
    for (const e of body.enables) lines.push(`    · ${e}`);
  }
  if (body.forecloses.length) {
    lines.push(``);
    lines.push(`  Forecloses:`);
    for (const f of body.forecloses) lines.push(`    · ${f}`);
  }
  return lines.join('\n');
};

// ── Condition evaluator ──────────────────────────────────────────────────

export interface ChainState {
  satisfied: Set<string>;
}

export interface ConditionEvaluation {
  satisfied: boolean;
  unmet: string[];
}

export const evaluateCondition = (
  conditionPatch: LegalPatch,
  chainState: ChainState,
): ConditionEvaluation => {
  const d = conditionPatch.delta as { requires?: string[] };
  const requires = d.requires ?? [];
  const unmet = requires.filter((req) => !chainState.satisfied.has(req));
  return { satisfied: unmet.length === 0, unmet };
};

// ── Transport-layer conversion ───────────────────────────────────────────
// LegalPatch (render-layer) ↔ ObjectPatch (transport-layer).
// Round-trip tested in legal-cards.test.ts §roundtrip.

export interface ObjectPatchCompat {
  id: string;
  kind:
    | 'extraction'
    | 'rescore'
    | 'manual_override'
    | 'state_transition'
    | 'evidence_merge'
    | 'instrument_emit'
    | 'action'
    | 'conversation'
    | 'channel_transaction'
    | 'channel_settlement';
  timestamp: number;
  delta: Record<string, unknown>;
  facetId?: string;
  facetCapabilities?: number[];
}

const KIND_TO_OBJECT_PATCH: Record<LegalPatchKind, ObjectPatchCompat['kind']> = {
  extraction: 'extraction',
  companion: 'evidence_merge',
  manual_override: 'manual_override',
  rejection: 'manual_override',
  state_transition: 'state_transition',
};

export const toObjectPatch = (p: LegalPatch): ObjectPatchCompat => ({
  id: p.id,
  kind: KIND_TO_OBJECT_PATCH[p.kind],
  timestamp: p.timestamp,
  delta: {
    ...p.delta,
    __legalKind: p.kind,
    __sir: p.sir,
    __companionOf: p.companionOf,
    __targetPatchId: p.targetPatchId,
    __reason: p.reason,
    __curatorSignature: p.curatorSignature,
  },
  facetId: p.hatId,
});

export const fromObjectPatch = (op: ObjectPatchCompat): LegalPatch => {
  const d = op.delta as Record<string, unknown>;
  const {
    __legalKind,
    __sir,
    __companionOf,
    __targetPatchId,
    __reason,
    __curatorSignature,
    ...delta
  } = d;
  return {
    id: op.id,
    kind: (__legalKind as LegalPatchKind) ?? 'extraction',
    hatId: op.facetId ?? 'unknown',
    timestamp: op.timestamp,
    sir: __sir as SIRNode,
    delta,
    companionOf: __companionOf as string | undefined,
    targetPatchId: __targetPatchId as string | undefined,
    reason: __reason as string | undefined,
    curatorSignature: __curatorSignature as string | undefined,
  };
};

// ── Re-exports for convenience ───────────────────────────────────────────
export type {
  SIRNode,
  JuralCategory,
  GovernanceContext,
  DelegationChain,
  TrustClass,
  ProofRequirement,
  LinearityMode,
};

```
