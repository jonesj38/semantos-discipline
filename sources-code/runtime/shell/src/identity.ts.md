---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/identity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.363006+00:00
---

# runtime/shell/src/identity.ts

```ts
/**
 * Identity command routing — register, derive, resolve, list, whoami, capabilities.
 *
 * All identity operations flow through PlexusService. No hardcoded hat IDs.
 * Works in stub mode (no real Plexus required).
 *
 * Phase 19.5: D19.5.2
 */

import type { ShellCommand } from './parser';
import type { ShellContext } from './types';
import { CAPABILITY_MAP, getCapabilityName } from './capabilities';
import { INVALID_REGISTER_USAGE, INVALID_DERIVE_USAGE, INVALID_RESOLVE_USAGE } from './error-codes';

/**
 * Route identity sub-commands: register, derive, resolve, list.
 * Sub-action comes from the first positional arg (stored in flags.action by parser).
 */
export async function routeIdentity(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const action = cmd.flags.action as string | undefined;

  if (!action) {
    return {
      error: "Verb 'identity' requires an action. Usage: semantos identity <register|derive|resolve|list> [args]",
    };
  }

  switch (action) {
    case 'register': {
      const email = cmd.objectId;
      if (!email) {
        return { error: "Usage: semantos identity register <email>", code: INVALID_REGISTER_USAGE };
      }
      const result = await ctx.plexus.registerIdentity(email);
      return {
        action: 'register',
        certId: result.certId,
        publicKey: result.publicKey,
        email,
      };
    }

    case 'derive': {
      const resourceId = cmd.objectId;
      if (!resourceId) {
        return { error: "Usage: semantos identity derive <resource-id>", code: INVALID_DERIVE_USAGE };
      }
      const parentCertId = ctx.activeHatCertId;
      if (!parentCertId) {
        return {
          error: 'Cannot derive without an active hat with a certId. Set SEMANTOS_HAT or register an identity first.',
        };
      }
      const result = await ctx.plexus.deriveChild(
        parentCertId,
        resourceId,
        0x00010001, // Client hat domain flag
      );
      return {
        action: 'derive',
        certId: result.certId,
        publicKey: result.publicKey,
        childIndex: result.childIndex,
        parentCertId,
        resourceId,
      };
    }

    case 'resolve': {
      const certId = cmd.objectId;
      if (!certId) {
        return { error: "Usage: semantos identity resolve <cert-id>", code: INVALID_RESOLVE_USAGE };
      }
      const result = await ctx.plexus.resolveIdentity(certId);
      return {
        action: 'resolve',
        ...result,
      };
    }

    case 'list': {
      const rootCertId = ctx.activeHatCertId;
      if (!rootCertId) {
        return {
          error: 'Cannot list hats without an active identity. Set SEMANTOS_HAT or register an identity first.',
        };
      }
      const result = await ctx.plexus.querySubtree(rootCertId, 2);
      return {
        action: 'list',
        ...result,
      };
    }

    default:
      return {
        error: `Unknown identity action '${action}'. Available: register, derive, resolve, list`,
      };
  }
}

/** Return current identity, hat, capabilities, and extension. */
export async function routeWhoami(ctx: ShellContext): Promise<unknown> {
  const hat = ctx.identity.getActiveHat();
  const capabilities = hat?.capabilities ?? [];

  return {
    hatId: ctx.activeHatId,
    certId: ctx.activeHatCertId ?? hat?.certId ?? null,
    capabilities,
    extension: ctx.activeExtension,
    timestamp: new Date().toISOString(),
  };
}

/** List active hat's capabilities with human-readable names. */
export async function routeCapabilities(ctx: ShellContext): Promise<unknown> {
  const hat = ctx.identity.getActiveHat();
  if (!hat) {
    return {
      error: 'No active hat. Set SEMANTOS_HAT or register an identity first.',
    };
  }

  const capabilities = hat.capabilities.map(cap => ({
    number: cap,
    domainFlag: CAPABILITY_MAP[
      Object.keys(CAPABILITY_MAP).find(
        k => CAPABILITY_MAP[k] === cap
      ) ?? ''
    ] ?? null,
    name: getCapabilityName(cap),
  }));

  return {
    hatId: ctx.activeHatId,
    certId: ctx.activeHatCertId ?? hat.certId ?? null,
    capabilities,
  };
}

```
