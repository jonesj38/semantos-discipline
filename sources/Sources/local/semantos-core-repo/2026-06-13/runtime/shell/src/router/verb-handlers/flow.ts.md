---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.384576+00:00
---

# runtime/shell/src/router/verb-handlers/flow.ts

```ts
/**
 * `flow` verb dispatcher — list / start / advance / cancel
 * subcommands routed through FlowRunner.
 */

import { listFlows } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import {
  FLOW_NOT_FOUND,
  INVALID_FLOW_USAGE,
  MISSING_FLOW_CAPABILITIES,
  NO_CONFIG,
  UNKNOWN_FLOW_SUBCOMMAND,
} from '../../error-codes';
import { getCapabilities } from '../shared/helpers';
import type { VerbHandler } from '../types';

const flowHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const config = ctx.config.getConfig();
  if (!config) return { error: 'No extension config loaded', code: NO_CONFIG };

  const subcommand = cmd.flags.subcommand;
  const flowId = cmd.flags.flow;

  if (subcommand === 'list' || (!subcommand && !flowId)) {
    const flows = listFlows(config);
    return flows.map((f) => ({
      id: f.id,
      name: f.name,
      triggerIntents: f.triggerIntents,
      steps: f.steps.length,
      requiredCapabilities: f.requiredCapabilities,
    }));
  }

  if (subcommand === 'start' || typeof flowId === 'string') {
    const targetFlowId =
      typeof flowId === 'string'
        ? flowId
        : typeof subcommand === 'string'
          ? subcommand
          : undefined;
    if (!targetFlowId) {
      return { error: 'Usage: semantos flow start <flow-id>', code: INVALID_FLOW_USAGE };
    }

    const flows = listFlows(config);
    const flow = flows.find((f) => f.id === targetFlowId);
    if (!flow) {
      return {
        error: `Flow not found: ${targetFlowId}. Available: ${flows.map((f) => f.id).join(', ')}`,
        code: FLOW_NOT_FOUND,
      };
    }

    const hatCaps = getCapabilities(ctx);
    if (flow.requiredCapabilities) {
      const missing = flow.requiredCapabilities.filter((c) => !hatCaps.includes(c));
      if (missing.length > 0) {
        return {
          error: `Missing capabilities for flow '${flow.name}': [${missing.join(', ')}]`,
          code: MISSING_FLOW_CAPABILITIES,
        };
      }
    }

    const step = ctx.flowRunner.startFlow(flow, cmd.objectId);
    return {
      flowId: flow.id,
      flowName: flow.name,
      currentStep: { id: step.id, prompt: step.prompt, field: step.field },
      totalSteps: flow.steps.length,
      status: 'started',
    };
  }

  if (subcommand === 'advance') {
    const response = typeof cmd.flags.response === 'string' ? cmd.flags.response : '';
    const nextStep = ctx.flowRunner.advanceFlow(response);
    if (!nextStep) {
      const state = ctx.flowRunner.completeFlow();
      return {
        flowId: state.flowId,
        status: 'complete',
        collectedData: state.collectedData,
        onComplete: state.onComplete,
      };
    }
    return {
      flowId: ctx.flowRunner.getState().flowId,
      currentStep: { id: nextStep.id, prompt: nextStep.prompt, field: nextStep.field },
      status: 'running',
    };
  }

  if (subcommand === 'cancel') {
    ctx.flowRunner.cancelFlow();
    return { status: 'cancelled' };
  }

  return {
    error: `Unknown flow subcommand: '${subcommand}'. Use: start, advance, cancel, list`,
    code: UNKNOWN_FLOW_SUBCOMMAND,
  };
};

export const flowHandlers = { flow: flowHandler };

```
