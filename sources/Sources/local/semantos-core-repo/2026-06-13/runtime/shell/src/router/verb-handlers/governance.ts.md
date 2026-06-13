---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/governance.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.387170+00:00
---

# runtime/shell/src/router/verb-handlers/governance.ts

```ts
/**
 * Governance verbs: `stake`, `vote`, `dispute`. Each starts a flow
 * via FlowRunner if a matching governance flow exists in the active
 * extension config.
 */

import { findFlow } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { NO_CONFIG, NO_GOVERNANCE_FLOW } from '../../error-codes';
import { getActiveHat } from '../shared/helpers';
import type { VerbHandler } from '../types';

function makeGovernanceHandler(govAction: 'stake' | 'vote' | 'dispute'): VerbHandler {
  return async (cmd: ShellCommand, ctx: ShellContext) => {
    const config = ctx.config.getConfig();
    if (!config) return { error: 'No extension config loaded', code: NO_CONFIG };

    const hat = getActiveHat(ctx);
    const hatCaps = hat?.capabilities ?? [];

    const flow = findFlow(govAction, hatCaps, config);
    if (!flow) {
      return {
        error:
          `No '${govAction}' flow available for current capabilities [${hatCaps.join(', ')}]. ` +
          `Check that a flow with triggerIntents including '${govAction}' exists in the extension config.`,
        code: NO_GOVERNANCE_FLOW,
      };
    }

    const step = ctx.flowRunner.startFlow(flow, cmd.objectId);
    return {
      action: govAction,
      flowId: flow.id,
      flowName: flow.name,
      currentStep: { id: step.id, prompt: step.prompt, field: step.field },
      status: 'flow_started',
    };
  };
}

export const governanceHandlers = {
  stake: makeGovernanceHandler('stake'),
  vote: makeGovernanceHandler('vote'),
  dispute: makeGovernanceHandler('dispute'),
};

```
