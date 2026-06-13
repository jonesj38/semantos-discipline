---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/identity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.381888+00:00
---

# runtime/shell/src/router/verb-handlers/identity.ts

```ts
/**
 * Identity verbs: `identity`, `whoami`, `capabilities`. The `identity`
 * verb is wrapped through `sendAuthenticated` for BRC-100-style
 * provenance stamping.
 */

import {
  routeCapabilities,
  routeIdentity,
  routeWhoami,
} from '../../identity';
import { isShellError } from '../../route-helpers';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import type { VerbHandler } from '../types';

const identityHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const result = await routeIdentity(cmd, ctx);
  if (isShellError(result)) return result;

  const senderCertId = ctx.activeHatCertId ?? 'anonymous';
  const action = cmd.flags.action as string | undefined;
  if (action && senderCertId !== 'anonymous') {
    await ctx.plexus.sendAuthenticated(senderCertId, senderCertId, {
      action: `identity.${action}`,
      hatCertId: senderCertId,
      timestamp: new Date().toISOString(),
      target: cmd.objectId ?? '',
    });
  }

  return result;
};

const whoamiHandler: VerbHandler = async (_cmd: ShellCommand, ctx: ShellContext) =>
  routeWhoami(ctx);

const capabilitiesHandler: VerbHandler = async (_cmd: ShellCommand, ctx: ShellContext) =>
  routeCapabilities(ctx);

export const identityHandlers = {
  identity: identityHandler,
  whoami: whoamiHandler,
  capabilities: capabilitiesHandler,
};

```
