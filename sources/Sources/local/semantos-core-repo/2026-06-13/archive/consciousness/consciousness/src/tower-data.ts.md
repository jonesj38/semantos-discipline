---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/tower-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.721986+00:00
---

# archive/consciousness/consciousness/src/tower-data.ts

```ts
/**
 * Consciousness Tower: The layered process model data.
 *
 * Maps the visual diagram from bottom to top — specific to the
 * consciousness process extension. The navigator provides the
 * TowerLayer interface; this module provides the data.
 *
 * @module @semantos/consciousness/tower
 */

/**
 * A layer in the consciousness tower model.
 * Each layer represents a stage in the process, read bottom-to-top.
 */
export interface TowerLayer {
  id: string;
  name: string;
  description: string;
  dynamic: string;
  polarity?: { positive: string; negative: string };
  subProcesses: string[];
  objectTypes: string[];
  depth: number;
  color: string;
}

/**
 * The complete consciousness tower definition.
 * Read bottom-to-top (depth 0 is the foundation).
 */
export const CONSCIOUSNESS_TOWER: TowerLayer[] = [
  {
    id: 'growth',
    name: 'Growth',
    description: 'The foundation — intentional, directed growth beyond biological programming.',
    dynamic: 'foundation',
    subProcesses: [],
    objectTypes: ['ElevationState'],
    depth: 0,
    color: '#1a5276',
  },
  {
    id: 'attention',
    name: 'Attention',
    description: 'The concentration of consciousness into a singular point of focus.',
    dynamic: 'foundation',
    subProcesses: ['focus-timer', 'attention-reclamation'],
    objectTypes: ['Session'],
    depth: 1,
    color: '#2471a3',
  },
  {
    id: 'ease',
    name: 'Ease',
    description: 'The guiding principle. Not apathy — the ease in commanding attention and creating systems that perpetuate ease.',
    dynamic: 'foundation',
    polarity: { positive: 'Ease', negative: 'Forcing' },
    subProcesses: [],
    objectTypes: [],
    depth: 2,
    color: '#5dade2',
  },
  {
    id: 'acceptance-resistance',
    name: 'Acceptance / Resistance',
    description: 'The fundamental dynamic. Acceptance is the green light, resistance is the red.',
    dynamic: 'polarity',
    polarity: { positive: 'Acceptance', negative: 'Resistance' },
    subProcesses: ['resistance-inquiry'],
    objectTypes: ['Release'],
    depth: 3,
    color: '#82e0aa',
  },
  {
    id: 'qse-process',
    name: 'QSE Vacuum / Integrate',
    description: 'Quantum source energy invocation. Clear tube releases, opaque tube integrates.',
    dynamic: 'practice',
    polarity: { positive: 'QSE Integrate', negative: 'QSE Vacuum' },
    subProcesses: ['vacuum-session', 'qse-integrate'],
    objectTypes: ['VacuumSession'],
    depth: 4,
    color: '#566573',
  },
  {
    id: 'gold',
    name: 'Gold Seal',
    description: 'Seal with gold energy for permanence. Regal, royal, non-reactive.',
    dynamic: 'practice',
    subProcesses: ['gold-seal'],
    objectTypes: ['GoldSeal'],
    depth: 5,
    color: '#f4d03f',
  },
  {
    id: 'release-receive-lower',
    name: 'Release & Receive (Foundation)',
    description: 'First cycle: release through writing, receive through analysis.',
    dynamic: 'polarity',
    polarity: { positive: 'Receive (Analyse, Question, Clarify)', negative: 'Release (Awareness, Energy, Belief)' },
    subProcesses: ['daily-release', 'capture-journal'],
    objectTypes: ['Release', 'Insight'],
    depth: 6,
    color: '#aed6f1',
  },
  {
    id: 'connection',
    name: 'Connection',
    description: 'Connect to aspects of self and consciousness. Receive intelligence.',
    dynamic: 'expansion',
    subProcesses: ['connection-receive'],
    objectTypes: ['Connection', 'Insight'],
    depth: 7,
    color: '#85c1e9',
  },
  {
    id: 'release-receive-upper',
    name: 'Release & Receive (Expanded)',
    description: 'Second cycle at a higher resolution. Release and receive refined intelligence.',
    dynamic: 'polarity',
    polarity: { positive: 'Receive', negative: 'Release' },
    subProcesses: ['daily-release', 'connection-receive'],
    objectTypes: ['Release', 'Insight', 'Pattern'],
    depth: 8,
    color: '#d5dbdb',
  },
  {
    id: 'awareness',
    name: 'Awareness',
    description: 'Expanded awareness — the gateway between foundation practices and higher authenticity.',
    dynamic: 'expansion',
    subProcesses: [],
    objectTypes: ['Insight', 'Pattern'],
    depth: 9,
    color: '#d5d8dc',
  },
  {
    id: 'degrees-of-authenticity',
    name: 'Degrees of Authenticity',
    description: 'Ego realm: Belief vs Knowledge. We question inherited facts and assumed beliefs.',
    dynamic: 'polarity',
    polarity: { positive: 'Knowledge (what we know)', negative: 'Belief (what we assume)' },
    subProcesses: ['discernment-check'],
    objectTypes: ['Pattern', 'Insight'],
    depth: 10,
    color: '#f39c12',
  },
  {
    id: 'soul-understanding',
    name: 'Soul / Understanding',
    description: 'Soul realm: Discernment vs Wisdom. The soul navigates the unknown.',
    dynamic: 'expansion',
    polarity: { positive: 'Wisdom', negative: 'Discernment' },
    subProcesses: ['connection-receive', 'discernment-check'],
    objectTypes: ['Insight'],
    depth: 11,
    color: '#f9e79f',
  },
  {
    id: 'creation',
    name: 'Creation',
    description: 'Creation across 7 dimensions: Mental, Physical, Spiritual, Social, Vocational, Financial, Familial.',
    dynamic: 'creation',
    subProcesses: ['set-intention'],
    objectTypes: ['Intention', 'DimensionState'],
    depth: 12,
    color: '#58d68d',
  },
  {
    id: 'energetics',
    name: 'Energetics',
    description: 'Working with frequencies, harmonics, the geometry of creation.',
    dynamic: 'integration',
    subProcesses: [],
    objectTypes: [],
    depth: 13,
    color: '#48c9b0',
  },
  {
    id: 'organisation',
    name: 'Organisation',
    description: 'The spine of the whole structure. Organizing intelligence into coherent systems.',
    dynamic: 'integration',
    subProcesses: [],
    objectTypes: ['Pattern'],
    depth: 14,
    color: '#a9dfbf',
  },
  {
    id: 'structure',
    name: 'Structure',
    description: 'Giving form to the organized systems. The seed factory.',
    dynamic: 'integration',
    subProcesses: [],
    objectTypes: [],
    depth: 15,
    color: '#d5f5e3',
  },
  {
    id: 'completion',
    name: 'Completion',
    description: 'Letting go of creation. It stands on its own. Proud but not attached.',
    dynamic: 'integration',
    subProcesses: [],
    objectTypes: [],
    depth: 16,
    color: '#f7dc6f',
  },
];

/**
 * Map the 6 elevation levels to their primary tower layer ranges.
 */
export const ELEVATION_TO_LAYERS: Record<number, string[]> = {
  1: ['growth', 'attention', 'ease', 'acceptance-resistance'],
  2: ['qse-process', 'gold', 'release-receive-lower', 'connection', 'release-receive-upper'],
  3: ['awareness', 'degrees-of-authenticity', 'soul-understanding'],
  4: ['energetics'],
  5: ['organisation', 'structure'],
  6: ['completion'],
};

```
