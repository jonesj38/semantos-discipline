---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/cli/commands.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.470021+00:00
---

# packages/scada/scada/src/cli/commands.ts

```ts
/**
 * SCADA Shell Commands — Phase 29 (D29.7)
 *
 * Wire SCADA operations into the semantic shell via the `scada` verb.
 *
 * Commands dispatch to CommandAuthorizationEngine, SemanticHistorian,
 * and PlantModel — no direct cell manipulation in the CLI layer.
 */

import type { CommandAuthorizationEngine } from '../authorization';
import type { SemanticHistorian } from '../historian';
import type { PlantModel } from '../plant';
import type { Result } from '../types';

/** Context required by SCADA CLI commands. */
export interface SCADAContext {
  engine: CommandAuthorizationEngine;
  historian: SemanticHistorian;
  plant: PlantModel;
}

/** Parsed SCADA subcommand. */
export interface SCADACommand {
  domain: 'plant' | 'telemetry' | 'command' | 'alarm' | 'shift' | 'anomaly';
  action: string;
  target?: string;
  flags: Record<string, string | boolean>;
}

/**
 * Parse a SCADA subcommand from raw CLI args.
 *
 * Examples:
 *   scada plant status
 *   scada telemetry read TT-101
 *   scada command issue valve.open BV-101 --operator OP-001
 *   scada alarm list --unacknowledged
 */
export function parseSCADACommand(args: string[]): Result<SCADACommand, string> {
  if (args.length < 2) {
    return {
      ok: false,
      error: 'Usage: scada <domain> <action> [target] [--flags]',
    };
  }

  const domain = args[0] as SCADACommand['domain'];
  const validDomains = ['plant', 'telemetry', 'command', 'alarm', 'shift', 'anomaly'];
  if (!validDomains.includes(domain)) {
    return {
      ok: false,
      error: `Unknown domain '${domain}'. Valid: ${validDomains.join(', ')}`,
    };
  }

  const action = args[1];
  const flags: Record<string, string | boolean> = {};
  let target: string | undefined;

  let i = 2;
  // First non-flag arg after action is the target
  if (i < args.length && !args[i].startsWith('--')) {
    target = args[i];
    i++;
  }
  // Second non-flag arg (for commands like `command issue valve.open BV-101`)
  if (i < args.length && !args[i].startsWith('--') && domain === 'command') {
    flags['equipmentTarget'] = args[i];
    i++;
  }

  // Parse flags
  while (i < args.length) {
    const arg = args[i];
    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        flags[key] = args[i + 1];
        i += 2;
      } else {
        flags[key] = true;
        i++;
      }
    } else {
      i++;
    }
  }

  return { ok: true, value: { domain, action, target, flags } };
}

/**
 * Route a parsed SCADA command to the appropriate service.
 */
export async function routeSCADACommand(
  cmd: SCADACommand,
  ctx: SCADAContext,
): Promise<unknown> {
  switch (cmd.domain) {
    case 'plant':
      return routePlant(cmd, ctx);
    case 'telemetry':
      return routeTelemetry(cmd, ctx);
    case 'command':
      return routeCommand(cmd, ctx);
    case 'alarm':
      return routeAlarm(cmd, ctx);
    case 'shift':
      return routeShift(cmd, ctx);
    case 'anomaly':
      return routeAnomaly(cmd, ctx);
    default:
      return { error: `Unknown domain: ${cmd.domain}` };
  }
}

// ── Plant Commands ─────────────────────────────────────────────

function routePlant(cmd: SCADACommand, ctx: SCADAContext): unknown {
  switch (cmd.action) {
    case 'status':
      return ctx.plant.getPlantStatus();
    default:
      return { error: `Unknown plant action: ${cmd.action}` };
  }
}

// ── Telemetry Commands ─────────────────────────────────────────

async function routeTelemetry(cmd: SCADACommand, ctx: SCADAContext): Promise<unknown> {
  switch (cmd.action) {
    case 'read': {
      if (!cmd.target) return { error: 'Usage: scada telemetry read <sensorId>' };
      return ctx.historian.getLatest(cmd.target) ?? { error: `No readings for ${cmd.target}` };
    }
    case 'history': {
      if (!cmd.target) return { error: 'Usage: scada telemetry history <sensorId> --from --to' };
      const from = cmd.flags['from'] as string || '1970-01-01';
      const to = cmd.flags['to'] as string || new Date().toISOString();
      return ctx.historian.query(cmd.target, from, to);
    }
    case 'verify': {
      if (!cmd.target) return { error: 'Usage: scada telemetry verify <sensorId> --from --to' };
      const from = cmd.flags['from'] as string || '1970-01-01';
      const to = cmd.flags['to'] as string || new Date().toISOString();
      return ctx.historian.verifyIntegrity(cmd.target, from, to);
    }
    default:
      return { error: `Unknown telemetry action: ${cmd.action}` };
  }
}

// ── Command Commands ───────────────────────────────────────────

function routeCommand(cmd: SCADACommand, ctx: SCADAContext): unknown {
  switch (cmd.action) {
    case 'issue': {
      if (!cmd.target) return { error: 'Usage: scada command issue <commandType> <target> --operator' };
      const operatorId = cmd.flags['operator'] as string;
      if (!operatorId) return { error: 'Missing --operator flag' };
      const equipTarget = cmd.flags['equipmentTarget'] as string ?? cmd.target;

      // Get active capability for operator
      const caps = ctx.engine.getActiveCapabilities(operatorId);
      if (caps.length === 0) {
        return { error: `No active capability tokens for ${operatorId}` };
      }

      return ctx.engine.issueCommand(
        {
          commandType: cmd.target as any,
          targetEquipment: equipTarget,
          parameters: {},
          issuedBy: operatorId,
        },
        operatorId,
        caps[0],
      );
    }
    default:
      return { error: `Unknown command action: ${cmd.action}` };
  }
}

// ── Alarm Commands ─────────────────────────────────────────────

function routeAlarm(cmd: SCADACommand, ctx: SCADAContext): unknown {
  switch (cmd.action) {
    case 'list': {
      const unackOnly = cmd.flags['unacknowledged'] === true;
      const alarms = ctx.engine.getUnacknowledgedAlarms();
      if (unackOnly) return alarms;
      return alarms;
    }
    case 'acknowledge': {
      if (!cmd.target) return { error: 'Usage: scada alarm acknowledge <alarmId> --operator' };
      const operatorId = cmd.flags['operator'] as string;
      if (!operatorId) return { error: 'Missing --operator flag' };

      const caps = ctx.engine.getActiveCapabilities(operatorId);
      if (caps.length === 0) {
        return { error: `No active capability tokens for ${operatorId}` };
      }

      return ctx.engine.acknowledgeAlarm(cmd.target, operatorId, caps[0]);
    }
    default:
      return { error: `Unknown alarm action: ${cmd.action}` };
  }
}

// ── Shift Commands ─────────────────────────────────────────────

function routeShift(cmd: SCADACommand, ctx: SCADAContext): unknown {
  switch (cmd.action) {
    case 'handover': {
      const from = cmd.flags['from'] as string;
      const to = cmd.flags['to'] as string;
      const supervisor = cmd.flags['supervisor'] as string;

      if (!from || !to || !supervisor) {
        return { error: 'Usage: scada shift handover --from <op> --to <op> --supervisor <sup>' };
      }

      return ctx.engine.shiftHandover(from, to, supervisor);
    }
    default:
      return { error: `Unknown shift action: ${cmd.action}` };
  }
}

// ── Anomaly Commands ───────────────────────────────────────────

function routeAnomaly(cmd: SCADACommand, ctx: SCADAContext): unknown {
  switch (cmd.action) {
    case 'detect': {
      if (!cmd.target) return { error: 'Usage: scada anomaly detect <sensorId> --window --threshold' };
      const window = cmd.flags['window'] as string || '24h';
      const threshold = parseFloat(cmd.flags['threshold'] as string || '0.8');
      return ctx.historian.detectAnomalies(cmd.target, window, threshold);
    }
    default:
      return { error: `Unknown anomaly action: ${cmd.action}` };
  }
}

```
