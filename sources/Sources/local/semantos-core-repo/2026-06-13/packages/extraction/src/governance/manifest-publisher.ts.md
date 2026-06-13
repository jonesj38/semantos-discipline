---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/manifest-publisher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.457485+00:00
---

# packages/extraction/src/governance/manifest-publisher.ts

```ts
/**
 * Manifest publisher — validates and publishes ExtensionManifests.
 *
 * Publication transitions a manifest from AFFINE (draft) to RELEVANT (published).
 * Before transition:
 *   1. Grammar passes validateExtensionGrammar()
 *   2. Manifest meets L0 constraints (enforceL0Constraints)
 *   3. Author hat has sufficient reputation score per marketplace rules
 *   4. Author has declared governance config
 *
 * Cross-references:
 *   governance.ts             → GovernancePolicy, PublicationResult
 *   constraint-engine.ts      → enforceL0Constraints
 *   extension-grammar-validator.ts → validateExtensionGrammar
 */

import type { ExtensionManifest } from '@semantos/protocol-types';
import type {
  GovernancePolicy,
  PublicationResult,
} from '@semantos/protocol-types';
import { validateExtensionGrammar } from '@semantos/protocol-types';
import { enforceL0Constraints } from './constraint-engine';

/**
 * Publish an ExtensionManifest — validate grammar, enforce L0 constraints,
 * check author qualifications, and transition AFFINE→RELEVANT.
 *
 * @param manifest - The manifest to publish (must be AFFINE)
 * @param policy - The current L0 GovernancePolicy
 * @param authorReputationScore - The author's current reputation score
 * @returns PublicationResult with success/failure and detailed errors
 */
export function publishExtensionManifest(
  manifest: ExtensionManifest,
  policy: GovernancePolicy,
  authorReputationScore: number = 0,
): PublicationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // 1. Must be in AFFINE (draft) state
  if (manifest.manifestLinearity === 'RELEVANT') {
    errors.push('Manifest is already published (RELEVANT). Cannot re-publish.');
    return { success: false, errors, warnings };
  }

  // 2. Must have governance config declared
  if (!manifest.governanceConfig) {
    errors.push('Manifest must declare governanceConfig before publication.');
  } else {
    // Phase 38 — trust-tier fields required at publication.
    // The type keeps them optional to avoid churning every fixture and
    // draft manifest in flight, but a manifest cannot leave AFFINE without
    // declaring its trust posture explicitly.
    if (!manifest.governanceConfig.trustClass) {
      errors.push('Manifest governanceConfig must declare trustClass before publication.');
    }
    if (!manifest.governanceConfig.proofRequirement) {
      errors.push('Manifest governanceConfig must declare proofRequirement before publication.');
    }
    if (!manifest.governanceConfig.executionAuthority) {
      errors.push('Manifest governanceConfig must declare executionAuthority before publication.');
    }
  }

  // 3. Must have a grammar
  if (!manifest.grammar) {
    errors.push('Manifest must include a grammar before publication.');
    return { success: false, errors, warnings };
  }

  // 4. Validate the grammar
  const grammarValidation = validateExtensionGrammar(manifest.grammar);
  if (!grammarValidation.valid) {
    for (const err of grammarValidation.errors) {
      if (err.severity === 'error') {
        errors.push(`Grammar validation: ${err.path} — ${err.message}`);
      } else {
        warnings.push(`Grammar warning: ${err.path} — ${err.message}`);
      }
    }
  }

  // 5. Enforce L0 constraints
  const l0Result = enforceL0Constraints(manifest, policy);
  if (!l0Result.valid) {
    for (const v of l0Result.violations) {
      errors.push(`L0 constraint [${v.rule}]: ${v.message}`);
    }
  }

  // 6. Check author reputation score
  const minScore = policy.payload.marketplaceListingRequirements.minAuthorReputationScore;
  if (authorReputationScore < minScore) {
    errors.push(
      `Author reputation score ${authorReputationScore} is below minimum ${minScore} required for marketplace listing.`,
    );
  }

  // If any errors, publication fails
  if (errors.length > 0) {
    return { success: false, errors, warnings };
  }

  // 7. Transition AFFINE → RELEVANT
  manifest.manifestLinearity = 'RELEVANT';

  return {
    success: true,
    manifestId: manifest.id,
    errors: [],
    warnings,
  };
}

```
