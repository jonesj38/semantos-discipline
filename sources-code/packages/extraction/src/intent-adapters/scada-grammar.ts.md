---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/scada-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.456579+00:00
---

# packages/extraction/src/intent-adapters/scada-grammar.ts

```ts
/**
 * SCADA / process-automation grammar — the non-jural proof of
 * lexicon polymorphism.
 *
 * The trades grammar (trades-grammar.ts) binds to the JuralLexicon;
 * this one binds to the ControlSystemsLexicon. Same pipeline, same
 * classifier factory, same tool-use machinery — just a different
 * (lexicon, actions) pair.
 *
 * Categories come from ControlSystemsLexicon:
 *   measurement, setpoint, actuation, interlock, alarm,
 *   acknowledgement, calibration.
 *
 * A plant operator isn't making jural declarations and transfers;
 * they're reading measurements, writing setpoints, issuing valve
 * commands, acknowledging alarms, and enforcing interlocks. The
 * grammar below encodes those actions at the right category tier so
 * trust-tier enforcement (authoritative for safety-critical actions)
 * and lowerSIR routing stay semantically meaningful.
 *
 * This is currently a fixture — packages/scada/ doesn't yet
 * register these through the verb registry. When it migrates, it
 * imports this grammar and passes it to `createAnthropicClassifier`.
 */

import { ControlSystemsLexicon } from '@semantos/semantos-sir';
import type { ExtensionGrammarSpec } from './trades-grammar';

export const SCADA_GRAMMAR: ExtensionGrammarSpec = {
  extensionId: 'scada',
  // Distinct from the trades domain so cross-domain routing doesn't
  // conflate a tenant's "approve" with an operator's "acknowledge".
  domainFlag: 11,
  lexicon: ControlSystemsLexicon,
  defaultTaxonomyWhat: 'scada.equipment',

  objectTypes: [
    { name: 'scada.equipment', description: 'A physical process-automation asset (valve, pump, sensor, PLC).' },
    { name: 'scada.alarm', description: 'An operator-visible alarm raised by a sensor/logic block.' },
    { name: 'scada.loop', description: 'A named control loop (PID or equivalent).' },
    { name: 'scada.interlock', description: 'A safety interlock that blocks a set of actions under a condition.' },
  ],

  actions: [
    {
      name: 'read_measurement',
      category: 'measurement',
      authoredBy: ['operator', 'engineer', 'sensor'],
      description: 'Record a measurement from a sensor or telemetry source.',
    },
    {
      name: 'write_setpoint',
      category: 'setpoint',
      authoredBy: ['operator', 'engineer'],
      description:
        'Set a new target value on a control loop (safety-critical when ' +
        'outside commissioning bounds).',
    },
    {
      name: 'open_valve',
      category: 'actuation',
      authoredBy: ['operator'],
      description: 'Command a valve to open (direct actuation).',
    },
    {
      name: 'close_valve',
      category: 'actuation',
      authoredBy: ['operator'],
      description: 'Command a valve to close (direct actuation).',
    },
    {
      name: 'engage_interlock',
      category: 'interlock',
      authoredBy: ['engineer'],
      description: 'Enable or adjust a safety interlock.',
    },
    {
      name: 'raise_alarm',
      category: 'alarm',
      authoredBy: ['sensor', 'logic'],
      description: 'Surface an alarm condition to operators (from a sensor or logic block).',
    },
    {
      name: 'acknowledge_alarm',
      category: 'acknowledgement',
      authoredBy: ['operator'],
      description: 'Acknowledge a standing alarm, silencing visible/audible notification.',
    },
    {
      name: 'calibrate_sensor',
      category: 'calibration',
      authoredBy: ['engineer', 'technician'],
      description: 'Run a calibration procedure on a sensor.',
    },
  ],
};

```
