---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/__fixtures__/scada-fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.359979+00:00
---

# runtime/intent/src/reducer/__fixtures__/scada-fixtures.ts

```ts
/**
 * Golden fixtures for the SCADA / process-automation vertical intent reducer.
 *
 * Same structure as trades-fixtures.ts. RED commits — fail until I-2..I-9
 * are implemented.
 *
 * Uses ControlSystemsLexicon categories:
 *   measurement, setpoint, actuation, interlock, alarm, acknowledgement, calibration
 *
 * Fixture naming convention: S-{n}-{scenario}
 */

import type { ReducerInputState, GrammarSpec } from '../types';
import type { Intent } from '../../types';

// ---------------------------------------------------------------------------
// Grammar stub (structural match for SCADA_GRAMMAR from packages/extraction)
// ---------------------------------------------------------------------------

export const SCADA_GRAMMAR_STUB: GrammarSpec = {
  extensionId: 'scada',
  domainFlag: 11,
  lexicon: {
    name: 'control-systems',
    categories: ['measurement', 'setpoint', 'actuation', 'interlock', 'alarm', 'acknowledgement', 'calibration'],
  },
  defaultTaxonomyWhat: 'scada.equipment',
  objectTypes: [
    { name: 'scada.equipment', description: 'A physical process-automation asset.' },
    { name: 'scada.alarm', description: 'An operator-visible alarm.' },
    { name: 'scada.loop', description: 'A named control loop.' },
    { name: 'scada.interlock', description: 'A safety interlock.' },
  ],
  actions: [
    { name: 'read_measurement', category: 'measurement', authoredBy: ['operator', 'engineer', 'sensor'], description: 'Record a measurement.' },
    { name: 'write_setpoint', category: 'setpoint', authoredBy: ['operator', 'engineer'], description: 'Set a new target value.' },
    { name: 'open_valve', category: 'actuation', authoredBy: ['operator'], description: 'Command a valve to open.' },
    { name: 'close_valve', category: 'actuation', authoredBy: ['operator'], description: 'Command a valve to close.' },
    { name: 'engage_interlock', category: 'interlock', authoredBy: ['engineer'], description: 'Enable or adjust a safety interlock.' },
    { name: 'raise_alarm', category: 'alarm', authoredBy: ['sensor', 'logic'], description: 'Surface an alarm condition.' },
    { name: 'acknowledge_alarm', category: 'acknowledgement', authoredBy: ['operator'], description: 'Acknowledge a standing alarm.' },
    { name: 'calibrate_sensor', category: 'calibration', authoredBy: ['engineer', 'technician'], description: 'Run a calibration procedure.' },
  ],
  trustClass: 'authoritative',
  proofRequirement: 'formal',
};

// ---------------------------------------------------------------------------
// S-1: Operator reads sensor measurement (measurement, cosmetic tier)
// ---------------------------------------------------------------------------

export const S1_READ_MEASUREMENT: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Tank TK-101 level sensor reads 3.4m (nominal range 2.0–4.5m).',
    taggedFacts: [
      { lexicon: 'control-systems', category: 'measurement', confidence: 0.97, fact: 'TK-101 level = 3.4m', source: 'sensor-telemetry' },
    ],
    jobType: 'scada.equipment',
    scopeDescription: 'Tank TK-101 level measurement',
  },
  grammar: SCADA_GRAMMAR_STUB,
  expected: {
    action: 'read_measurement',
    category: {
      lexicon: 'control-systems',
      category: 'measurement',
    },
    taxonomy: {
      what: 'scada.equipment',
      how: expect.stringContaining('how.'),
      why: expect.stringContaining('why.'),
    },
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// S-2: Operator writes setpoint (authoritative — proofRequirement: formal)
// ---------------------------------------------------------------------------

export const S2_WRITE_SETPOINT: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Engineer adjusts reactor temperature setpoint from 85°C to 90°C on loop TIC-201.',
    taggedFacts: [
      { lexicon: 'control-systems', category: 'setpoint', confidence: 0.91, fact: 'TIC-201 setpoint changed to 90°C', source: 'dcs-command' },
      { lexicon: 'control-systems', category: 'measurement', confidence: 0.82, fact: 'current TIC-201 temp 85°C', source: 'sensor-telemetry' },
    ],
    jobType: 'scada.loop',
    scopeDescription: 'TIC-201 temperature setpoint change 85→90°C',
  },
  grammar: SCADA_GRAMMAR_STUB,
  expected: {
    action: 'write_setpoint',
    category: {
      lexicon: 'control-systems',
      category: 'setpoint',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'value' }),
    ]),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// S-3: Safety interlock engaged (interlock, formal proof required)
// ---------------------------------------------------------------------------

export const S3_ENGAGE_INTERLOCK: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Engineer engages high-pressure interlock IL-301 blocking pump P-201 above 8.5 bar.',
    taggedFacts: [
      { lexicon: 'control-systems', category: 'interlock', confidence: 0.96, fact: 'IL-301 enabled: blocks P-201 above 8.5 bar', source: 'safety-plc' },
    ],
    jobType: 'scada.interlock',
    scopeDescription: 'IL-301 high-pressure interlock engagement',
  },
  grammar: SCADA_GRAMMAR_STUB,
  expected: {
    action: 'engage_interlock',
    category: {
      lexicon: 'control-systems',
      category: 'interlock',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'interlock' }),
    ]),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// S-4: Operator acknowledges alarm (acknowledgement, with temporal constraint)
// ---------------------------------------------------------------------------

export const S4_ACKNOWLEDGE_ALARM: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Operator acknowledges high-level alarm on TK-102 at 14:32 AEST.',
    taggedFacts: [
      { lexicon: 'control-systems', category: 'acknowledgement', confidence: 0.94, fact: 'alarm TK-102-HIGH acknowledged', source: 'hmi-event' },
      { lexicon: 'control-systems', category: 'alarm', confidence: 0.89, fact: 'TK-102 level exceeded 4.2m threshold', source: 'sensor-telemetry' },
    ],
    jobType: 'scada.alarm',
    preferredDatetime: '2026-05-09T14:32:00+10:00',
  },
  grammar: SCADA_GRAMMAR_STUB,
  expected: {
    action: 'acknowledge_alarm',
    category: {
      lexicon: 'control-systems',
      category: 'acknowledgement',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'temporal' }),
    ]),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// S-5: Valve actuation (actuation, trust-ceiling test)
// ---------------------------------------------------------------------------

export const S5_OPEN_VALVE: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Operator commands valve XV-101 to open to allow product transfer.',
    taggedFacts: [
      { lexicon: 'control-systems', category: 'actuation', confidence: 0.95, fact: 'XV-101 open command issued', source: 'dcs-command' },
    ],
    jobType: 'scada.equipment',
    scopeDescription: 'XV-101 open command',
  },
  grammar: SCADA_GRAMMAR_STUB,
  expected: {
    action: 'open_valve',
    category: {
      lexicon: 'control-systems',
      category: 'actuation',
    },
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

export const SCADA_FIXTURES = [S1_READ_MEASUREMENT, S2_WRITE_SETPOINT, S3_ENGAGE_INTERLOCK, S4_ACKNOWLEDGE_ALARM, S5_OPEN_VALVE];

```
