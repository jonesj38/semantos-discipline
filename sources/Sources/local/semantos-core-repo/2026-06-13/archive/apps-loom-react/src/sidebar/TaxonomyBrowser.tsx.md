---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/TaxonomyBrowser.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.955169+00:00
---

# archive/apps-loom-react/src/sidebar/TaxonomyBrowser.tsx

```tsx
import { useState, useMemo } from 'react';
import { useExtension } from '../config/ExtensionProvider';
import { useLoom } from '../state/LoomProvider';
import type { TaxonomyNode, TaxonomyDimensionDef } from '../config/extensionConfig';
import { computeTaxonomyWeights, type TaxonomyWeight } from '../services/TaxonomyWeightComputer';

const AXIS_TABS: { id: 'what' | 'how' | 'why'; label: string }[] = [
  { id: 'what', label: 'WHAT' },
  { id: 'how', label: 'HOW' },
  { id: 'why', label: 'WHY' },
];

function TreeNode({ node, depth, onSelect, activePath, weights }: {
  node: TaxonomyNode;
  depth: number;
  onSelect: (path: string) => void;
  activePath: string | null;
  weights: Map<string, TaxonomyWeight>;
}) {
  const [expanded, setExpanded] = useState(depth < 2);
  const hasChildren = node.children && node.children.length > 0;
  const isActive = activePath === node.path;
  const weight = weights.get(node.path);
  const activityCount = weight?.activity ?? 0;

  // Sort children by activity (descending), then alphabetically
  const sortedChildren = useMemo(() => {
    if (!node.children) return [];
    return [...node.children].sort((a, b) => {
      const wa = weights.get(a.path)?.activity ?? 0;
      const wb = weights.get(b.path)?.activity ?? 0;
      if (wb !== wa) return wb - wa;
      return a.name.localeCompare(b.name);
    });
  }, [node.children, weights]);

  // Dim low-activity nodes (opacity based on whether there's any activity)
  const opacity = activityCount > 0 ? 1 : 0.5;

  return (
    <div style={{ opacity }}>
      <div
        className={`flex items-center gap-1 px-2 py-0.5 rounded cursor-pointer text-xs ${
          isActive ? 'bg-blue-900/50 text-blue-300' : 'hover:bg-gray-800 text-gray-400'
        }`}
        style={{ paddingLeft: `${8 + depth * 12}px` }}
        onClick={() => {
          if (hasChildren) setExpanded(!expanded);
          onSelect(node.path);
        }}
      >
        {hasChildren && (
          <span className="text-[10px] text-gray-600 w-3">
            {expanded ? '\u25BC' : '\u25B6'}
          </span>
        )}
        {!hasChildren && <span className="w-3" />}
        <span className="flex-1">{node.name}</span>
        {activityCount > 0 && (
          <span className="text-[9px] text-gray-500 bg-gray-800 px-1 rounded">
            {activityCount}
          </span>
        )}
      </div>
      {expanded && hasChildren && sortedChildren.map(child => (
        <TreeNode
          key={child.path}
          node={child}
          depth={depth + 1}
          onSelect={onSelect}
          activePath={activePath}
          weights={weights}
        />
      ))}
    </div>
  );
}

export function TaxonomyBrowser() {
  const { config } = useExtension();
  const { state, dispatch } = useLoom();
  const [activeAxis, setActiveAxis] = useState<'what' | 'how' | 'why'>('what');

  // Compute weights for the active axis
  const weights = useMemo(() => {
    return computeTaxonomyWeights(state.objects, activeAxis);
  }, [state.objects, activeAxis]);

  // Find dimensions matching the three canonical axes
  const axisDims = useMemo(() => {
    if (!config?.taxonomy) return new Map<string, TaxonomyDimensionDef>();
    return new Map(
      config.taxonomy.dimensions
        .filter(d => d.id === 'what' || d.id === 'how' || d.id === 'why')
        .map(d => [d.id, d] as const),
    );
  }, [config?.taxonomy]);

  // Also collect non-axis dimensions (e.g. "instrument")
  const extraDims = useMemo(() => {
    if (!config?.taxonomy) return [];
    return config.taxonomy.dimensions.filter(
      d => d.id !== 'what' && d.id !== 'how' && d.id !== 'why',
    );
  }, [config?.taxonomy]);

  const activeDim = axisDims.get(activeAxis);

  // Sort root nodes by activity
  const sortedRootNodes = useMemo(() => {
    if (!activeDim) return [];
    return [...activeDim.nodes].sort((a, b) => {
      const wa = weights.get(a.path)?.activity ?? 0;
      const wb = weights.get(b.path)?.activity ?? 0;
      if (wb !== wa) return wb - wa;
      return a.name.localeCompare(b.name);
    });
  }, [activeDim, weights]);

  if (!config?.taxonomy) return null;

  const handleSelect = (path: string) => {
    const newPath = state.categoryFilter === path ? null : path;
    dispatch({ type: 'FILTER_BY_CATEGORY', path: newPath });
  };

  return (
    <div className="px-1 py-2 border-t border-gray-800">
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1 px-2">Taxonomy</div>
      {state.categoryFilter && (
        <button
          className="text-[10px] text-blue-400 px-2 mb-1 hover:underline"
          onClick={() => dispatch({ type: 'FILTER_BY_CATEGORY', path: null })}
        >
          Clear filter
        </button>
      )}

      {/* Three-axis tab bar */}
      {axisDims.size > 0 && (
        <div className="flex gap-0.5 px-2 mb-1">
          {AXIS_TABS.filter(t => axisDims.has(t.id)).map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveAxis(tab.id)}
              className={`text-[10px] px-2 py-0.5 rounded ${
                activeAxis === tab.id
                  ? 'bg-blue-900/50 text-blue-300'
                  : 'text-gray-500 hover:text-gray-400 hover:bg-gray-800'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      )}

      {/* Active axis tree */}
      {activeDim && sortedRootNodes.map(node => (
        <TreeNode
          key={node.path}
          node={node}
          depth={0}
          onSelect={handleSelect}
          activePath={state.categoryFilter}
          weights={weights}
        />
      ))}

      {/* Extra dimensions (non-axis, e.g. "instrument") */}
      {extraDims.map(dim => (
        <div key={dim.id} className="mb-1 mt-2">
          <div className="text-[10px] text-gray-600 px-2 py-0.5 font-semibold">{dim.name}</div>
          {dim.nodes.map(node => (
            <TreeNode
              key={node.path}
              node={node}
              depth={0}
              onSelect={handleSelect}
              activePath={state.categoryFilter}
              weights={weights}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

```
