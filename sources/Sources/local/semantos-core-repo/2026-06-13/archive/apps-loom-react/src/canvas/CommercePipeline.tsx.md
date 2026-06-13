---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/CommercePipeline.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.934509+00:00
---

# archive/apps-loom-react/src/canvas/CommercePipeline.tsx

```tsx
/**
 * CommercePipeline — Phase 3 business dashboard with metrics, team, and orders.
 *
 * Extends the Phase 1-2 phase pipeline visualization with:
 *   - Organization header (name, avatar, link to BusinessPage)
 *   - Metrics row: Revenue YTD, Active Orders, Avg Rating, Team count
 *   - Recent orders list
 *   - Phase pipeline bar (preserved from original)
 */

import { useMemo } from 'react';
import { useExtension } from '../config/ExtensionProvider';
import { useLoom } from '../state/LoomProvider';

const PHASE_NAME_TO_NUM: Record<string, number> = {
  SOURCE: 0, PARSE: 1, AST: 2, TYPECHECK: 3,
  OPTIMISE: 4, CODEGEN: 5, ACTION: 6, OUTCOME: 7,
};

const PHASE_COLORS: Record<string, string> = {
  SOURCE: 'border-purple-500',
  PARSE: 'border-blue-500',
  AST: 'border-cyan-500',
  TYPECHECK: 'border-green-500',
  OPTIMISE: 'border-lime-500',
  CODEGEN: 'border-yellow-500',
  ACTION: 'border-orange-500',
  OUTCOME: 'border-red-500',
};

const ACTIVE_COLORS: Record<string, string> = {
  SOURCE: 'bg-purple-900/50 border-purple-400',
  PARSE: 'bg-blue-900/50 border-blue-400',
  AST: 'bg-cyan-900/50 border-cyan-400',
  TYPECHECK: 'bg-green-900/50 border-green-400',
  OPTIMISE: 'bg-lime-900/50 border-lime-400',
  CODEGEN: 'bg-yellow-900/50 border-yellow-400',
  ACTION: 'bg-orange-900/50 border-orange-400',
  OUTCOME: 'bg-red-900/50 border-red-400',
};

// ── Organization Header ───────────────────────────────────────

function OrgHeader({ orgName, founderLabel, orgCertId }: {
  orgName: string;
  founderLabel: string;
  orgCertId: string;
}) {
  return (
    <div className="flex items-center gap-3 px-3 py-2 bg-gray-900/70 border-b border-gray-700">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white text-xs font-bold">
        {orgName.charAt(0).toUpperCase()}
      </div>
      <div className="flex-1 min-w-0">
        <div className="text-sm font-semibold text-white truncate">{orgName}</div>
        <div className="text-[10px] text-gray-400 truncate">
          {founderLabel} &middot; {orgCertId.slice(0, 12)}...
        </div>
      </div>
      <a
        href={`#/org/${orgCertId}`}
        className="text-[10px] text-blue-400 hover:text-blue-300 px-2 py-1 rounded border border-blue-800 hover:border-blue-600"
      >
        View Page
      </a>
    </div>
  );
}

// ── Metrics Row ───────────────────────────────────────────────

function MetricCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="flex-1 min-w-[80px] p-2 bg-gray-800/50 rounded border border-gray-700">
      <div className={`text-lg font-bold ${color}`}>{value}</div>
      <div className="text-[10px] text-gray-500">{label}</div>
    </div>
  );
}

function MetricsRow({ revenue, activeOrders, avgRating, teamCount }: {
  revenue: number;
  activeOrders: number;
  avgRating: number;
  teamCount: number;
}) {
  return (
    <div className="flex gap-2 px-3 py-2 overflow-x-auto">
      <MetricCard label="Revenue YTD" value={`$${revenue.toLocaleString()}`} color="text-green-400" />
      <MetricCard label="Active Orders" value={String(activeOrders)} color="text-blue-400" />
      <MetricCard label="Avg Rating" value={avgRating > 0 ? `${avgRating.toFixed(1)}★` : '--'} color="text-yellow-400" />
      <MetricCard label="Team" value={String(teamCount)} color="text-purple-400" />
    </div>
  );
}

// ── Recent Orders ─────────────────────────────────────────────

function RecentOrders({ orders }: { orders: Array<Record<string, any>> }) {
  if (orders.length === 0) return null;

  const statusColor: Record<string, string> = {
    pending: 'text-yellow-400',
    accepted: 'text-blue-400',
    in_progress: 'text-cyan-400',
    completed: 'text-green-400',
    reviewed: 'text-purple-400',
    cancelled: 'text-red-400',
    disputed: 'text-orange-400',
  };

  return (
    <div className="px-3 py-2">
      <div className="text-[10px] text-gray-500 mb-1 font-semibold uppercase">Recent Orders</div>
      <div className="space-y-1">
        {orders.slice(0, 5).map((order, i) => (
          <div key={i} className="flex items-center gap-2 text-xs py-1 border-b border-gray-800/50">
            <span className={`w-20 ${statusColor[order.status] || 'text-gray-400'}`}>
              {order.status}
            </span>
            <span className="flex-1 text-gray-400 truncate">{order.serviceId || 'Service'}</span>
            <span className="text-gray-500">{order.totalAmount ? `$${order.totalAmount}` : ''}</span>
            <span className="text-gray-600 text-[10px]">
              {order.scheduledAt ? new Date(order.scheduledAt).toLocaleDateString() : ''}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Team Members List ─────────────────────────────────────────

function TeamList({ members }: { members: Array<{ certId: string; role: string }> }) {
  if (members.length === 0) return null;

  const roleBadge: Record<string, string> = {
    admin: 'bg-purple-800 text-purple-200',
    tradie: 'bg-blue-800 text-blue-200',
    viewer: 'bg-gray-700 text-gray-300',
  };

  return (
    <div className="px-3 py-2">
      <div className="text-[10px] text-gray-500 mb-1 font-semibold uppercase">Team Members</div>
      <div className="flex gap-2 flex-wrap">
        {members.map((m, i) => (
          <div key={i} className="flex items-center gap-1 px-2 py-1 bg-gray-800/50 rounded text-xs border border-gray-700">
            <span className="text-gray-300">{m.certId.slice(0, 8)}...</span>
            <span className={`px-1 py-0.5 rounded text-[9px] ${roleBadge[m.role] || roleBadge.viewer}`}>
              {m.role}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Main Export ────────────────────────────────────────────────

export function CommercePipeline() {
  const { config } = useExtension();
  const { state } = useLoom();

  const phaseCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const obj of state.objects.values()) {
      const phaseName = Object.entries(PHASE_NAME_TO_NUM).find(([, v]) => v === obj.header.phase)?.[0] ?? 'UNKNOWN';
      counts.set(phaseName, (counts.get(phaseName) ?? 0) + 1);
    }
    return counts;
  }, [state.objects]);

  // Phase 3: Extract business dashboard data from state
  const dashboardData = useMemo(() => {
    let activeOrg: { orgName: string; founderLabel: string; orgCertId: string } | null = null;
    const orders: Array<Record<string, any>> = [];
    const reviews: Array<Record<string, any>> = [];
    const members: Array<{ certId: string; role: string }> = [];
    let revenue = 0;

    for (const obj of state.objects.values()) {
      const p = obj.payload as Record<string, any>;

      // Detect organization
      if (!activeOrg && (obj.header.typePath === 'commerce.org' || obj.type === 'Organization')) {
        activeOrg = {
          orgName: p?.orgName || p?.name || 'Business',
          founderLabel: p?.founderCertId?.slice(0, 8) || 'Founder',
          orgCertId: obj.id,
        };
      }

      // Collect orders
      if (obj.type === 'Order') {
        orders.push(p);
        if (['completed', 'reviewed'].includes(p?.status) && p?.totalAmount) {
          revenue += Number(p.totalAmount) || 0;
        }
      }

      // Collect reviews for avg rating
      if (obj.type === 'Review' && typeof p?.rating === 'number') {
        reviews.push(p);
      }
    }

    const activeOrders = orders.filter(o => ['pending', 'accepted', 'in_progress'].includes(o.status)).length;
    const avgRating = reviews.length > 0
      ? reviews.reduce((sum, r) => sum + r.rating, 0) / reviews.length
      : 0;

    return { activeOrg, orders, revenue, activeOrders, avgRating, members, teamCount: members.length };
  }, [state.objects]);

  if (!config) return null;

  return (
    <div>
      {dashboardData.activeOrg && (
        <OrgHeader
          orgName={dashboardData.activeOrg.orgName}
          founderLabel={dashboardData.activeOrg.founderLabel}
          orgCertId={dashboardData.activeOrg.orgCertId}
        />
      )}

      {/* Business Metrics Row */}
      {dashboardData.activeOrg && (
        <MetricsRow
          revenue={dashboardData.revenue}
          activeOrders={dashboardData.activeOrders}
          avgRating={dashboardData.avgRating}
          teamCount={dashboardData.teamCount}
        />
      )}

      {/* Phase Pipeline Bar */}
      <div className="flex items-center gap-1 px-3 py-2 bg-gray-900/50 border-b border-gray-800 overflow-x-auto">
        {config.commercePhases.map((phase, i) => {
          const count = phaseCounts.get(phase) ?? 0;
          const isActive = count > 0;
          const borderColor = isActive ? ACTIVE_COLORS[phase] : PHASE_COLORS[phase] ?? 'border-gray-700';

          return (
            <div key={phase} className="flex items-center gap-1">
              <div className={`px-2 py-1 rounded border text-[10px] font-mono ${borderColor} ${isActive ? '' : 'bg-gray-900'}`}>
                <span className={isActive ? 'text-white' : 'text-gray-500'}>{phase}</span>
                {count > 0 && (
                  <span className="ml-1 text-gray-400">({count})</span>
                )}
              </div>
              {i < config.commercePhases.length - 1 && (
                <span className="text-gray-700 text-[10px]">{'\u2192'}</span>
              )}
            </div>
          );
        })}
      </div>

      {/* Recent Orders */}
      <RecentOrders orders={dashboardData.orders} />

      {/* Team Members */}
      <TeamList members={dashboardData.members} />
    </div>
  );
}

```
