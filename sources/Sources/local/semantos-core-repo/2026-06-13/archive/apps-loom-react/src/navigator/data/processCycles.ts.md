---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/data/processCycles.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.973628+00:00
---

# archive/apps-loom-react/src/navigator/data/processCycles.ts

```ts
export interface ProcessStep {
  id: string;
  label: string;
  release: boolean;
  receive: boolean;
  desc: string;
}

export interface ProcessCycle {
  id: string;
  label: string;
  color: string;
  inquiry: string;
  description: string;
  recursive?: boolean;
  steps: ProcessStep[];
}

export const PROCESS_CYCLES: ProcessCycle[] = [
  {
    id: 'foundation', label: 'Foundation', color: '#3b82f6',
    inquiry: 'WHO am I?',
    description: 'Build the base: willingness to grow, command of attention, finding ease.',
    steps: [
      { id: 'growth', label: 'Growth', release: false, receive: false, desc: 'The willingness to grow. Everything begins here.' },
      { id: 'attention', label: 'Attention', release: false, receive: false, desc: 'Master the command of your attention.' },
      { id: 'ease', label: 'Ease', release: false, receive: false, desc: 'Find ease in the process.' },
    ],
  },
  {
    id: 'energetic_release', label: 'Energetic Release', color: '#ef4444',
    inquiry: 'WHAT am I holding?',
    description: 'Clear what doesn\'t serve you. Meet resistance, accept, integrate, seal.',
    steps: [
      { id: 'qse_vacuum', label: 'QSE Vacuum', release: true, receive: false, desc: 'Invoke quantum source energy. Release everything except your highest.' },
      { id: 'resistance', label: 'Resistance', release: false, receive: false, desc: 'Meet what resists the release.' },
      { id: 'acceptance', label: 'Acceptance', release: false, receive: false, desc: 'Accept what is.' },
      { id: 'qse_integrate', label: 'QSE Integrate', release: false, receive: true, desc: 'Integrate your highest expression.' },
      { id: 'gold', label: 'Gold', release: false, receive: false, desc: 'Seal with gold. Permanence.' },
    ],
  },
  {
    id: 'conscious_release', label: 'Conscious Release', color: '#8b5cf6',
    inquiry: 'WHEN do I release?',
    description: 'Deeper release through writing and awareness. Connect, release, receive.',
    recursive: true,
    steps: [
      { id: 'release_1', label: 'Release', release: true, receive: false, desc: 'Write, speak, move — let it flow out.' },
      { id: 'awareness', label: 'Awareness', release: false, receive: false, desc: 'What patterns emerge from what you released?' },
      { id: 'connection', label: 'Connection', release: false, receive: false, desc: 'Connect to highest expression, inner child, future self.' },
      { id: 'release_2', label: 'Release', release: true, receive: false, desc: 'Deeper release — informed by awareness.' },
      { id: 'receive', label: 'Receive', release: false, receive: true, desc: 'What intelligence is available?' },
    ],
  },
  {
    id: 'discernment', label: 'Discernment', color: '#f59e0b',
    inquiry: 'WHY do I believe this?',
    description: 'Distinguish ego from soul. Belief vs knowledge. Discernment vs wisdom.',
    steps: [
      { id: 'degrees_auth', label: 'Degrees of Authenticity', release: false, receive: false, desc: 'How authentic are you being right now?' },
      { id: 'ego', label: 'Ego: Belief ↔ Knowledge', release: false, receive: false, desc: 'Which is driving you?' },
      { id: 'soul', label: 'Soul: Discernment ↔ Wisdom', release: false, receive: false, desc: 'Trust the difference.' },
    ],
  },
  {
    id: 'application', label: 'Application', color: '#4ade80',
    inquiry: 'WHERE & HOW do I create?',
    description: 'Apply understanding across all seven dimensions. Create. Complete.',
    steps: [
      { id: 'understanding', label: 'Understanding', release: false, receive: true, desc: 'Integrate across all cycles.' },
      { id: 'creation', label: 'Creation', release: false, receive: false, desc: 'Create across 7 dimensions.' },
      { id: 'completion', label: 'Completion', release: false, receive: false, desc: 'Manifest and release into the world.' },
    ],
  },
];

```
