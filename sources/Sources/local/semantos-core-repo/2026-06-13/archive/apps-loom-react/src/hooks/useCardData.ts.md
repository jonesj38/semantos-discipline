---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/hooks/useCardData.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.962315+00:00
---

# archive/apps-loom-react/src/hooks/useCardData.ts

```ts
import { useState, useEffect, useCallback } from 'react';
import { useKernel } from '../contexts/KernelProvider';
import {
  DIMENSION_IDS,
  DIMENSION_ENUM_MAP,
  DIMENSION_GROUPS,
  type DimensionId,
} from './useDimensions';

interface DimensionData {
  score: number;
  recentEntries: Array<{ id: string; type: string; fields: Record<string, unknown>; createdAt: number }>;
}

interface GroupedDimensions {
  [groupName: string]: Array<{ dimId: DimensionId } & DimensionData>;
}

const TYPE_DEFAULTS: Record<string, DimensionId> = {
  Release: 'spirit',
  Insight: 'mind',
  Pattern: 'mind',
  Intention: 'craft',
  DailyReview: 'mind',
  MorningIntention: 'mind',
  Connection: 'tribe',
  Session: 'spirit',
  VacuumSession: 'spirit',
  GoldSeal: 'spirit',
};

function resolveDimension(obj: { type: string; fields: Record<string, unknown> }): DimensionId | null {
  const dimField = (obj.fields.dimension || obj.fields.primaryDimension) as string | undefined;
  if (dimField && DIMENSION_ENUM_MAP[dimField]) return DIMENSION_ENUM_MAP[dimField];

  if (obj.fields.dimensions) {
    const first = String(obj.fields.dimensions).split(',')[0].trim();
    if (DIMENSION_ENUM_MAP[first]) return DIMENSION_ENUM_MAP[first];
  }

  return TYPE_DEFAULTS[obj.type] || null;
}

function computeCardData(
  objects: Array<{ id: string; type: string; fields: Record<string, unknown>; createdAt: number }>,
): Record<DimensionId, DimensionData> {
  const data: Record<string, DimensionData> = {};
  for (const id of DIMENSION_IDS) {
    data[id] = { score: 50, recentEntries: [] };
  }

  const weekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

  for (const obj of objects) {
    const dimId = resolveDimension(obj);
    if (dimId && data[dimId] && obj.createdAt >= weekAgo) {
      data[dimId].recentEntries.push(obj);
    }

    if (obj.type === 'DimensionPulse' && obj.fields.dimension) {
      const pulseDimId = DIMENSION_ENUM_MAP[obj.fields.dimension as string];
      if (pulseDimId && data[pulseDimId]) {
        const score = typeof obj.fields.score === 'number' ? obj.fields.score * 10 : 50;
        data[pulseDimId].score = Math.min(100, Math.max(0, score));
      }
    }

    if (obj.type === 'DimensionState' && obj.fields.dimension) {
      const stateDimId = DIMENSION_ENUM_MAP[obj.fields.dimension as string];
      if (stateDimId && data[stateDimId]) {
        const score = typeof obj.fields.currentLevel === 'number' ? obj.fields.currentLevel : 50;
        data[stateDimId].score = Math.min(100, Math.max(0, score as number));
      }
    }
  }

  for (const id of DIMENSION_IDS) {
    data[id].recentEntries.sort((a, b) => b.createdAt - a.createdAt);
  }

  return data as Record<DimensionId, DimensionData>;
}

export function useCardData() {
  const { kernel } = useKernel();
  const [data, setData] = useState<Record<DimensionId, DimensionData>>(() => {
    const init: Record<string, DimensionData> = {};
    for (const id of DIMENSION_IDS) init[id] = { score: 50, recentEntries: [] };
    return init as Record<DimensionId, DimensionData>;
  });

  const sync = useCallback(() => {
    if (!kernel) return;
    const objects = kernel.listObjects();
    setData(computeCardData(objects));
  }, [kernel]);

  useEffect(() => {
    if (!kernel) return;
    sync();
    return kernel.subscribe(sync);
  }, [kernel, sync]);

  const getDimension = useCallback(
    (dimId: DimensionId): DimensionData => data[dimId] ?? { score: 50, recentEntries: [] },
    [data],
  );

  const getGrouped = useCallback((): GroupedDimensions => {
    const result: GroupedDimensions = {};
    for (const [groupName, dimIds] of Object.entries(DIMENSION_GROUPS)) {
      result[groupName] = dimIds.map(id => ({ dimId: id, ...data[id] }));
    }
    return result;
  }, [data]);

  return { data, getDimension, getGrouped, sync };
}

```
