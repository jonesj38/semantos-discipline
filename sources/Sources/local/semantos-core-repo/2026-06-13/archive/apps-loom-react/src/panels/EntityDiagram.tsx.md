---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/EntityDiagram.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.950767+00:00
---

# archive/apps-loom-react/src/panels/EntityDiagram.tsx

```tsx
/**
 * EntityDiagram — SVG-based entity relationship diagram.
 *
 * Renders source entities as rectangles with relationship lines.
 * Interactive: hover to highlight connected entities, click to focus.
 * No external diagram library — pure SVG.
 */

import { useState, useMemo } from 'react';
import type { SourceEntity, SourceRelationship } from '../../../protocol-types/src/extension-grammar';

interface EntityDiagramProps {
  entities: SourceEntity[];
  onEntityClick?: (entityId: string) => void;
}

interface EntityLayout {
  id: string;
  displayName: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fields: number;
  relationships: SourceRelationship[];
}

const NODE_WIDTH = 160;
const NODE_HEIGHT_BASE = 40;
const NODE_FIELD_HEIGHT = 16;
const NODE_PADDING = 30;
const COLS = 3;

export function EntityDiagram({ entities, onEntityClick }: EntityDiagramProps) {
  const [hoveredEntity, setHoveredEntity] = useState<string | null>(null);
  const [selectedEntity, setSelectedEntity] = useState<string | null>(null);

  const { nodes, edges, svgWidth, svgHeight } = useMemo(() => {
    // Layout entities in a grid
    const nodes: EntityLayout[] = entities.map((entity, i) => {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      const fieldCount = Math.min(entity.fields.length, 5);
      const height = NODE_HEIGHT_BASE + fieldCount * NODE_FIELD_HEIGHT;

      return {
        id: entity.entityId,
        displayName: entity.displayName,
        x: col * (NODE_WIDTH + NODE_PADDING * 2) + NODE_PADDING,
        y: row * (120 + NODE_PADDING) + NODE_PADDING,
        width: NODE_WIDTH,
        height,
        fields: entity.fields.length,
        relationships: entity.relationships ?? [],
      };
    });

    // Build edges from relationships
    const edges: Array<{
      from: string;
      to: string;
      type: string;
      label: string;
    }> = [];

    for (const entity of entities) {
      for (const rel of entity.relationships ?? []) {
        edges.push({
          from: entity.entityId,
          to: rel.targetEntityId,
          type: rel.type,
          label: `${rel.type} (${rel.foreignKey})`,
        });
      }
    }

    const maxCol = Math.min(entities.length, COLS);
    const maxRow = Math.ceil(entities.length / COLS);
    const svgWidth = maxCol * (NODE_WIDTH + NODE_PADDING * 2) + NODE_PADDING;
    const svgHeight = maxRow * (120 + NODE_PADDING) + NODE_PADDING;

    return { nodes, edges, svgWidth, svgHeight };
  }, [entities]);

  const getNodeCenter = (id: string): { x: number; y: number } | null => {
    const node = nodes.find((n) => n.id === id);
    if (!node) return null;
    return { x: node.x + node.width / 2, y: node.y + node.height / 2 };
  };

  const isHighlighted = (id: string): boolean => {
    if (!hoveredEntity) return false;
    if (id === hoveredEntity) return true;
    return edges.some(
      (e) =>
        (e.from === hoveredEntity && e.to === id) ||
        (e.to === hoveredEntity && e.from === id),
    );
  };

  if (entities.length === 0) {
    return <p className="text-xs text-gray-500">No source entities defined.</p>;
  }

  return (
    <div className="overflow-auto">
      <svg
        width={svgWidth}
        height={svgHeight}
        className="bg-gray-900 rounded border border-gray-800"
      >
        {/* Edges */}
        {edges.map((edge, i) => {
          const from = getNodeCenter(edge.from);
          const to = getNodeCenter(edge.to);
          if (!from || !to) return null;

          const isActive = hoveredEntity === edge.from || hoveredEntity === edge.to;

          return (
            <g key={i}>
              <line
                x1={from.x}
                y1={from.y}
                x2={to.x}
                y2={to.y}
                stroke={isActive ? '#60a5fa' : '#374151'}
                strokeWidth={isActive ? 2 : 1}
                strokeDasharray={edge.type === 'has_many' ? '4,2' : undefined}
              />
              {/* Relationship label at midpoint */}
              <text
                x={(from.x + to.x) / 2}
                y={(from.y + to.y) / 2 - 4}
                fill={isActive ? '#93c5fd' : '#6b7280'}
                fontSize={9}
                textAnchor="middle"
              >
                {edge.type}
              </text>
            </g>
          );
        })}

        {/* Nodes */}
        {nodes.map((node) => {
          const highlighted = isHighlighted(node.id);
          const selected = selectedEntity === node.id;

          return (
            <g
              key={node.id}
              onClick={() => {
                setSelectedEntity(node.id);
                onEntityClick?.(node.id);
              }}
              onMouseEnter={() => setHoveredEntity(node.id)}
              onMouseLeave={() => setHoveredEntity(null)}
              className="cursor-pointer"
            >
              <rect
                x={node.x}
                y={node.y}
                width={node.width}
                height={node.height}
                rx={4}
                fill={selected ? '#1e3a5f' : highlighted ? '#1a2332' : '#111827'}
                stroke={selected ? '#3b82f6' : highlighted ? '#4b5563' : '#374151'}
                strokeWidth={selected ? 2 : 1}
              />
              {/* Header */}
              <rect
                x={node.x}
                y={node.y}
                width={node.width}
                height={24}
                rx={4}
                fill={selected ? '#1e40af' : highlighted ? '#1f2937' : '#1f2937'}
              />
              <text
                x={node.x + 8}
                y={node.y + 16}
                fill={selected ? '#93c5fd' : '#d1d5db'}
                fontSize={11}
                fontWeight="bold"
              >
                {node.displayName}
              </text>
              {/* Field count */}
              <text
                x={node.x + 8}
                y={node.y + 36}
                fill="#9ca3af"
                fontSize={9}
              >
                {node.fields} fields
              </text>
              {/* Relationship count */}
              {node.relationships.length > 0 && (
                <text
                  x={node.x + NODE_WIDTH - 8}
                  y={node.y + 36}
                  fill="#6b7280"
                  fontSize={9}
                  textAnchor="end"
                >
                  {node.relationships.length} rel
                </text>
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

```
