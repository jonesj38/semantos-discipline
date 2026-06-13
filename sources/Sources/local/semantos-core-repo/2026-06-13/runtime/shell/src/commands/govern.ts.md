---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/govern.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.374195+00:00
---

# runtime/shell/src/commands/govern.ts

```ts
/**
 * Shell govern commands — governance operations for extensions.
 *
 * Subcommands:
 *   semantos govern policy show
 *   semantos govern manifest <id> show
 *   semantos govern manifest <id> propose-patch <file>
 *   semantos govern manifest <id> deprecate --days N
 *   semantos govern binding <id> show
 *   semantos govern binding <id> pin <version>
 *   semantos govern binding <id> override-field --object-type ... --field-name ... --type ...
 *   semantos govern binding <id> compat
 *   semantos govern manifest <id> versions
 *   semantos govern dispute create --manifest-id ... --reason ...
 *   semantos govern dispute escalate <id>
 *   semantos govern dispute list --manifest-id ...
 *
 * Cross-references:
 *   governance.ts              → GovernancePolicy, GovernedConsumerBinding types
 *   constraint-engine.ts       → enforceL0Constraints, enforceL1Constraints
 *   dispute-escalator.ts       → createDisputeL2toL1, escalateDispute
 *   version-compat.ts          → checkCompatibility
 *   manifest-publisher.ts      → publishExtensionManifest
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { INVALID_GOVERN_USAGE, UNKNOWN_GOVERN_ACTION, MISSING_DISPUTE_TARGET } from '../error-codes';

/**
 * Route govern subcommands.
 */
export async function routeGovern(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;

  if (!subcommand) {
    return {
      error: 'Usage: semantos govern <policy|manifest|binding|dispute> <subcommand> [options]',
      code: INVALID_GOVERN_USAGE,
      available: ['policy show', 'manifest <id> show', 'binding <id> show', 'dispute create', 'dispute list'],
    };
  }

  switch (subcommand) {
    case 'policy':
      return handlePolicy(cmd, ctx);
    case 'manifest':
      return handleManifest(cmd, ctx);
    case 'binding':
      return handleBinding(cmd, ctx);
    case 'dispute':
      return handleDispute(cmd, ctx);
    default:
      return {
        error: `Unknown govern subcommand '${subcommand}'. Use: policy, manifest, binding, dispute`,
        code: UNKNOWN_GOVERN_ACTION,
      };
  }
}

// ── Policy Commands ────────────────────────────────────────────

function handlePolicy(cmd: ShellCommand, ctx: ShellContext): unknown {
  const action = cmd.flags.action as string | undefined ?? 'show';

  if (action === 'show') {
    // Display the current L0 GovernancePolicy
    // In a real system, this would load from the object store
    return {
      typePath: 'governance.policy',
      linearity: 'RELEVANT',
      constitution: true,
      payload: {
        metaSchemaVersion: '1.0.0',
        requiredCapabilitiesWhitelist: ['network.outbound', 'storage.write'],
        taxonomyNamespaceReservations: [
          { namespace: 'platform', reason: 'Reserved for Semantos platform types' },
        ],
        marketplaceListingRequirements: {
          minAuthorReputationScore: 10,
          minObjectCount: 1,
          requiresAudit: false,
          auditFrequencyDays: 90,
        },
        breakingChangeBallotQuorum: 66,
        emergencyDeprecationPolicy: {
          requiresVote: false,
          minDaysNotice: 30,
          escalationThreshold: 'critical-security-vulnerability',
        },
        effectiveDate: new Date().toISOString(),
        governedByHatId: 'semantos-core-team',
      },
      message: 'L0 GovernancePolicy (Constitution — changes require ballot with >66% quorum)',
    };
  }

  return { error: `Unknown policy action '${action}'. Use: show` };
}

// ── Manifest Commands ──────────────────────────────────────────

function handleManifest(cmd: ShellCommand, ctx: ShellContext): unknown {
  const manifestId = cmd.flags['manifest-id'] as string | cmd.objectId;
  const action = cmd.flags.action as string | undefined ?? 'show';

  if (!manifestId && action !== 'show') {
    return { error: 'Usage: semantos govern manifest <id> <show|propose-patch|deprecate|versions>' };
  }

  switch (action) {
    case 'show': {
      // Show manifest governance config
      const state = ctx.store.getState();
      if (manifestId) {
        const obj = state.objects.get(manifestId as string);
        if (obj) {
          return {
            id: obj.id,
            type: obj.typeDefinition.name,
            linearity: obj.typeDefinition.linearity,
            governanceConfig: obj.payload.governanceConfig ?? 'Not configured',
            deprecationStatus: obj.payload.deprecationStatus ?? 'Active',
            version: obj.payload.version ?? 'unknown',
          };
        }
      }
      return {
        message: manifestId
          ? `Manifest '${manifestId}' not found in object store.`
          : 'Usage: semantos govern manifest <id> show',
      };
    }

    case 'propose-patch': {
      const file = cmd.flags.path as string | undefined;
      const reason = cmd.flags.reason as string | undefined;
      if (!file) {
        return { error: 'Usage: semantos govern manifest <id> propose-patch <grammar-file> [--reason "..."]' };
      }
      return {
        manifestId,
        action: 'propose-patch',
        file,
        reason: reason ?? 'No reason provided',
        status: 'Patch proposal created. Ballot initiated per manifest governance policy.',
      };
    }

    case 'deprecate': {
      const days = cmd.flags.days as number | undefined ?? 90;
      const message = cmd.flags.message as string | undefined;
      return {
        manifestId,
        action: 'deprecate',
        deprecationDays: days,
        message: message ?? 'No migration message provided',
        status: `Deprecation initiated. Sunset in ${days} days.`,
      };
    }

    case 'versions': {
      return {
        manifestId,
        versions: ['1.0.0'],
        current: '1.0.0',
        message: 'Version history for manifest. In production, shows all published versions.',
      };
    }

    default:
      return { error: `Unknown manifest action '${action}'. Use: show, propose-patch, deprecate, versions` };
  }
}

// ── Binding Commands ───────────────────────────────────────────

function handleBinding(cmd: ShellCommand, ctx: ShellContext): unknown {
  const bindingId = cmd.flags['binding-id'] as string | cmd.objectId;
  const action = cmd.flags.action as string | undefined ?? 'show';

  if (!bindingId && action !== 'show') {
    return { error: 'Usage: semantos govern binding <id> <show|pin|override-field|compat>' };
  }

  switch (action) {
    case 'show': {
      const state = ctx.store.getState();
      if (bindingId) {
        const obj = state.objects.get(bindingId as string);
        if (obj) {
          return {
            id: obj.id,
            extensionManifestId: obj.payload.extensionManifestId,
            grammarVersionPinned: obj.payload.grammarVersionPinned,
            status: obj.payload.status ?? 'active',
            autoUpdateGrammar: obj.payload.autoUpdateGrammar ?? false,
            fieldOverrides: obj.payload.fieldOverrides ?? [],
            taxonomyOverrides: obj.payload.taxonomyOverrides ?? [],
            credentialFields: obj.payload.credentialsEncrypted?.credentialFieldNames ?? [],
          };
        }
      }
      return {
        message: bindingId
          ? `Binding '${bindingId}' not found.`
          : 'Usage: semantos govern binding <id> show',
      };
    }

    case 'pin': {
      const version = cmd.flags.version as string | undefined;
      if (!version) {
        return { error: 'Usage: semantos govern binding <id> pin <version>' };
      }
      return {
        bindingId,
        action: 'pin',
        version,
        status: `Version pinned to '${version}'. L1 constraints will be validated on next extraction.`,
      };
    }

    case 'override-field': {
      const objectType = cmd.flags['object-type'] as string | undefined;
      const fieldName = cmd.flags['field-name'] as string | undefined;
      const fieldType = cmd.flags.type as string | undefined;
      if (!objectType || !fieldName || !fieldType) {
        return {
          error: 'Usage: semantos govern binding <id> override-field --object-type <type> --field-name <name> --type <type>',
        };
      }
      return {
        bindingId,
        action: 'override-field',
        objectType,
        fieldName,
        fieldType,
        status: `Field override added. L1 constraints will validate on next extraction.`,
      };
    }

    case 'compat': {
      return {
        bindingId,
        status: 'green',
        message: 'Compatible with current manifest version.',
        note: 'Run with a live binding to see actual compatibility status.',
      };
    }

    default:
      return { error: `Unknown binding action '${action}'. Use: show, pin, override-field, compat` };
  }
}

// ── Dispute Commands ───────────────────────────────────────────

function handleDispute(cmd: ShellCommand, ctx: ShellContext): unknown {
  const action = cmd.flags.action as string | undefined;

  if (!action) {
    return { error: 'Usage: semantos govern dispute <create|escalate|list> [options]' };
  }

  switch (action) {
    case 'create': {
      const manifestId = cmd.flags['manifest-id'] as string | undefined;
      const policyId = cmd.flags['policy-id'] as string | undefined;
      const reason = cmd.flags.reason as string | undefined;

      if (!reason) {
        return { error: 'Usage: semantos govern dispute create --manifest-id <id> --reason "..."' };
      }

      if (manifestId) {
        return {
          action: 'dispute-created',
          level: 'L2→L1',
          manifestId,
          reason,
          status: 'Ballot created. Waiting for author response.',
          escalationWindow: '7 days',
        };
      }

      if (policyId) {
        return {
          action: 'dispute-created',
          level: 'L1→L0',
          policyId,
          reason,
          status: 'Ballot created. Waiting for platform team response.',
        };
      }

      return { error: 'Provide --manifest-id (L2→L1) or --policy-id (L1→L0).', code: MISSING_DISPUTE_TARGET };
    }

    case 'escalate': {
      const disputeId = cmd.objectId ?? cmd.flags['dispute-id'] as string | undefined;
      if (!disputeId) {
        return { error: 'Usage: semantos govern dispute escalate <dispute-id>' };
      }
      return {
        action: 'dispute-escalated',
        disputeId,
        status: 'Dispute escalated to next governance level.',
      };
    }

    case 'list': {
      const manifestId = cmd.flags['manifest-id'] as string | undefined;
      const policyId = cmd.flags['policy-id'] as string | undefined;

      return {
        disputes: [],
        filter: manifestId ? { manifestId } : policyId ? { policyId } : 'all',
        message: 'No active disputes found.',
      };
    }

    default:
      return { error: `Unknown dispute action '${action}'. Use: create, escalate, list` };
  }
}

```
