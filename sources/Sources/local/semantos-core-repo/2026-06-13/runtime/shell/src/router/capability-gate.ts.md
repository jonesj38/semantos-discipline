---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/capability-gate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.377275+00:00
---

# runtime/shell/src/router/capability-gate.ts

```ts
/**
 * Pure capability gate — extracted from router.ts. Decides whether a
 * verb is allowed to execute given the active hat + cert plus the
 * Plexus presentCapability response.
 *
 * No I/O beyond the supplied `ctx.plexus.presentCapability()` call.
 */

import { getCapabilityName, getRequiredCapability } from '../capabilities';
import type { ShellContext } from '../types';
import type { CapabilityCheckResult } from './types';

export async function checkPlexusCapability(
  ctx: ShellContext,
  verb: string,
): Promise<CapabilityCheckResult> {
  const requiredCap = getRequiredCapability(verb);
  if (requiredCap === null) {
    return { allowed: true, requiredCapability: null };
  }

  const hat = ctx.identity.getActiveHat();
  if (!hat) {
    return {
      allowed: false,
      requiredCapability: requiredCap,
      message: `Cannot ${verb} without an active hat. Set SEMANTOS_HAT=<hat-id>.`,
    };
  }

  const certId = ctx.activeHatCertId ?? hat.certId;
  if (!certId) {
    return {
      allowed: false,
      requiredCapability: requiredCap,
      message: `Cannot ${verb} without a cert ID. Register an identity first.`,
    };
  }

  const result = await ctx.plexus.presentCapability(certId, String(requiredCap));
  if (!result.valid) {
    return {
      allowed: false,
      requiredCapability: requiredCap,
      message:
        `Missing capability ${getCapabilityName(requiredCap)} (0x${requiredCap.toString(16)}) to ${verb}.` +
        (result.reason ? ` Reason: ${result.reason}` : ''),
    };
  }

  const localCaps = hat.capabilities ?? [];
  const legacyNum = requiredCap & 0xff;
  if (!localCaps.includes(legacyNum) && !localCaps.includes(requiredCap)) {
    return {
      allowed: false,
      requiredCapability: requiredCap,
      message:
        `Missing capability ${getCapabilityName(requiredCap)} (0x${requiredCap.toString(16)}) to ${verb}. ` +
        `Active hat: ${hat.displayName}. Available: [${localCaps.join(', ')}]`,
    };
  }

  return { allowed: true, requiredCapability: requiredCap };
}

```
