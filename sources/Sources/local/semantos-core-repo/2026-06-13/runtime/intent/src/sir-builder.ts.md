---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/sir-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.343293+00:00
---

# runtime/intent/src/sir-builder.ts

```ts
/**
 * buildSIR — Intent + HatContext → SIRProgram.
 *
 * Pure function. No IO, no time, no randomness. Given the same
 * Intent and HatContext, produces the same SIRProgram every time.
 *
 * Populates governance from two sources:
 *   - Intent.confidence + Intent.source → trustClass (capped by
 *     HatContext.maxTrustClass — the hat cannot claim higher than
 *     its ceiling, even if the LLM scores the extraction highly)
 *   - HatContext → identity.hatId, identity.certId, domainBinding.flag
 *
 * Constraints flow through untouched — they already share the shape
 * lowerSIR consumes.
 *
 * See docs/INTENT-PIPELINE.md §"Design decisions" #2 and #3.
 */

import type {
  SIRProgram,
  SIRNode,
  SIRConstraint,
  GovernanceContext,
  TrustClass,
  SIRIdentity,
  SIRProvenance,
  TaxonomyCoordinates,
} from '@semantos/semantos-sir';
import type { Intent, HatContext, IntentSource } from './types';

// Trust-class ordering. Used to cap Intent-requested tier by
// HatContext.maxTrustClass ceiling.
const TRUST_ORDER: Record<TrustClass, number> = {
  cosmetic: 0,
  interpretive: 1,
  authoritative: 2,
};

function minTrustClass(a: TrustClass, b: TrustClass): TrustClass {
  return TRUST_ORDER[a] <= TRUST_ORDER[b] ? a : b;
}

/**
 * Map Intent.confidence → candidate TrustClass. Thresholds match
 * doc Decision #2. Deterministic sources (shell, host-exec, network,
 * scheduler) don't go through confidence scoring and always get
 * 'interpretive' as their candidate — the hat's ceiling still applies.
 */
function candidateTrustClass(intent: Intent): TrustClass {
  const deterministic: IntentSource[] = [
    'shell',
    'host-exec',
    'network',
    'scheduler',
  ];
  if (deterministic.includes(intent.source)) return 'interpretive';
  // NL / voice / UI / governance go through confidence-based gating
  if (intent.confidence >= 0.9) return 'interpretive';
  if (intent.confidence >= 0.6) return 'cosmetic';
  // Sub-0.6 intents should have been rejected at the producer; if one
  // slips through, cap it at cosmetic so lowerSIR's enforcement bites.
  return 'cosmetic';
}

function sourceToProvenance(source: IntentSource): SIRProvenance['source'] {
  switch (source) {
    case 'nl':
    case 'ui':
      return 'manual';
    case 'voice':
      return 'voice';
    case 'shell':
    case 'host-exec':
      return 'api';
    case 'network':
    case 'governance':
      return 'monitor';
    case 'scheduler':
      return 'scheduler';
  }
}

function consolidateConstraints(constraints: SIRConstraint[]): SIRConstraint {
  if (constraints.length === 0) {
    // A SIR node requires a constraint; a "no-op" intent becomes a
    // trivial always-true composite. Downstream: lower() turns this
    // into a no-op gate that the kernel short-circuits.
    return { kind: 'composite', op: 'and', children: [] };
  }
  if (constraints.length === 1) return constraints[0]!;
  return { kind: 'composite', op: 'and', children: constraints };
}

export function buildSIR(intent: Intent, hat: HatContext): SIRProgram {
  const trustClass = minTrustClass(candidateTrustClass(intent), hat.maxTrustClass);

  const governance: GovernanceContext = {
    trustClass,
    // Authoritative claims always require formal proof; anything else
    // starts at 'none' and can be tightened by extension policy later.
    proofRequirement: trustClass === 'authoritative' ? 'formal' : 'none',
    // Hat-scoped by default. Delegation is explicit opt-in via the
    // Intent's constraints (capability checks with delegator context).
    executionAuthority: 'hat_scoped',
    // Linearity is a per-target concern; leave the default and let
    // lowerSIR's type check fire if the target's cell header disagrees.
    linearity: 'AFFINE',
    domainBinding: {
      flag: hat.domainFlag,
      domainType: 'personal',
    },
  };

  // IdentityRef uses 'role' for named-subject bindings; the hat id is
  // threaded through as the role name, with the actual hat/cert
  // travelling alongside in SIRIdentity's optional fields.
  const identity: SIRIdentity = {
    subject: { type: 'role', name: hat.hatId },
    hatId: hat.hatId,
    certId: hat.certId ?? undefined,
  };

  const provenance: SIRProvenance = {
    source: sourceToProvenance(intent.source),
    confidence: intent.confidence,
    expressedAt: new Date().toISOString(),
    trustAtExpression: trustClass,
  };

  const taxonomy: TaxonomyCoordinates = intent.taxonomy;

  const node: SIRNode = {
    id: '$s0',
    category: intent.category,
    taxonomy,
    identity,
    governance,
    action: intent.action,
    constraint: consolidateConstraints(intent.constraints),
    target: intent.target,
    transferTo: intent.transferTo,
    fulfillment: intent.fulfillment,
    provenance,
  };

  return {
    nodes: [node],
    primaryNodeId: '$s0',
    programGovernance: governance,
  };
}

```
