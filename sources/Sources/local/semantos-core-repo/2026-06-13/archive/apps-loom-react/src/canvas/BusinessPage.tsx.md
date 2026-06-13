---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/BusinessPage.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.933621+00:00
---

# archive/apps-loom-react/src/canvas/BusinessPage.tsx

```tsx
/**
 * BusinessPage — public-facing business profile component (Phase 3).
 *
 * Renders an ORGANIZATION node as a tabbed profile:
 *   - Services: listed Service objects with price + category
 *   - Reviews: paginated Review objects with star rating
 *   - Team: members from ROLE_ASSIGNMENT edges
 *   - Hours: business hours from org metadata
 *
 * Reuses existing hooks: useLoom(), useExtension().
 * Public access: no auth required; read-only via publicKey.
 */

import { useState, useMemo } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useExtension } from '../config/ExtensionProvider';

// ── Types ─────────────────────────────────────────────────────

interface BusinessPageProps {
  orgCertId: string;
}

type Tab = 'services' | 'reviews' | 'team' | 'hours';

// ── Star Rating Display ───────────────────────────────────────

function StarRating({ rating, count }: { rating: number; count?: number }) {
  const full = Math.floor(rating);
  const half = rating - full >= 0.5;
  const empty = 5 - full - (half ? 1 : 0);

  return (
    <span className="inline-flex items-center gap-1">
      {Array.from({ length: full }).map((_, i) => (
        <span key={`f${i}`} className="text-yellow-400">&#9733;</span>
      ))}
      {half && <span className="text-yellow-400">&#9734;</span>}
      {Array.from({ length: empty }).map((_, i) => (
        <span key={`e${i}`} className="text-gray-600">&#9734;</span>
      ))}
      <span className="text-sm text-gray-400 ml-1">
        {rating.toFixed(1)}{count !== undefined && ` (${count} reviews)`}
      </span>
    </span>
  );
}

// ── Star Histogram ────────────────────────────────────────────

function StarHistogram({ reviews }: { reviews: Array<{ rating: number }> }) {
  const histogram = [0, 0, 0, 0, 0]; // 1-5 stars
  for (const r of reviews) {
    if (r.rating >= 1 && r.rating <= 5) {
      histogram[r.rating - 1]++;
    }
  }
  const maxCount = Math.max(...histogram, 1);

  return (
    <div className="space-y-1">
      {[5, 4, 3, 2, 1].map(star => (
        <div key={star} className="flex items-center gap-2 text-xs">
          <span className="w-4 text-right text-gray-400">{star}</span>
          <span className="text-yellow-400">&#9733;</span>
          <div className="flex-1 h-2 bg-gray-800 rounded-full overflow-hidden">
            <div
              className="h-full bg-yellow-500 rounded-full"
              style={{ width: `${(histogram[star - 1] / maxCount) * 100}%` }}
            />
          </div>
          <span className="w-6 text-right text-gray-500">{histogram[star - 1]}</span>
        </div>
      ))}
    </div>
  );
}

// ── Services Tab ──────────────────────────────────────────────

function ServicesTab({ services }: { services: Array<Record<string, any>> }) {
  if (services.length === 0) {
    return <div className="text-gray-500 text-sm py-4">No services listed yet.</div>;
  }
  return (
    <div className="space-y-3">
      {services.map((svc, i) => (
        <div key={i} className="p-3 bg-gray-800/50 rounded-lg border border-gray-700">
          <div className="flex items-center justify-between">
            <div>
              <div className="font-medium text-white">{svc.name || 'Unnamed Service'}</div>
              <div className="text-xs text-gray-400 mt-1">{svc.categoryPath || svc.category || ''}</div>
            </div>
            <div className="text-right">
              {svc.basePrice && (
                <div className="text-green-400 font-semibold">${svc.basePrice}</div>
              )}
              <div className="text-[10px] text-gray-500">{svc.priceType || 'fixed'}</div>
            </div>
          </div>
          {svc.description && (
            <div className="text-xs text-gray-400 mt-2">{svc.description}</div>
          )}
          <button className="mt-2 px-3 py-1 text-xs bg-blue-600 hover:bg-blue-500 text-white rounded">
            Book
          </button>
        </div>
      ))}
    </div>
  );
}

// ── Reviews Tab ───────────────────────────────────────────────

function ReviewsTab({ reviews }: { reviews: Array<Record<string, any>> }) {
  if (reviews.length === 0) {
    return <div className="text-gray-500 text-sm py-4">No reviews yet.</div>;
  }
  return (
    <div className="space-y-4">
      <StarHistogram reviews={reviews} />
      <div className="space-y-3 mt-4">
        {reviews.slice(0, 10).map((rev, i) => (
          <div key={i} className="p-3 bg-gray-800/50 rounded-lg border border-gray-700">
            <div className="flex items-center justify-between">
              <StarRating rating={rev.rating || 0} />
              <span className="text-[10px] text-gray-500">
                {rev.createdAt ? new Date(rev.createdAt).toLocaleDateString() : ''}
              </span>
            </div>
            {rev.comment && (
              <div className="text-sm text-gray-300 mt-2">{rev.comment}</div>
            )}
            {rev.reviewerId && (
              <div className="text-[10px] text-gray-500 mt-1">
                {rev.verifiedPurchase && <span className="text-green-400 mr-1">Verified</span>}
                {rev.reviewerId.slice(0, 8)}...
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Team Tab ───────────────────────────────────────���──────────

function TeamTab({ members }: { members: Array<{ certId: string; role: string; joinedAt?: string }> }) {
  if (members.length === 0) {
    return <div className="text-gray-500 text-sm py-4">No team members.</div>;
  }
  const roleBadge: Record<string, string> = {
    admin: 'bg-purple-600 text-purple-100',
    tradie: 'bg-blue-600 text-blue-100',
    viewer: 'bg-gray-600 text-gray-100',
  };
  return (
    <div className="space-y-2">
      {members.map((m, i) => (
        <div key={i} className="flex items-center gap-3 p-2 bg-gray-800/50 rounded border border-gray-700">
          <div className="w-8 h-8 rounded-full bg-gray-700 flex items-center justify-center text-xs text-gray-300">
            {m.certId.slice(0, 2).toUpperCase()}
          </div>
          <div className="flex-1">
            <div className="text-sm text-white">{m.certId.slice(0, 12)}...</div>
            {m.joinedAt && (
              <div className="text-[10px] text-gray-500">Joined {new Date(m.joinedAt).toLocaleDateString()}</div>
            )}
          </div>
          <span className={`px-2 py-0.5 text-[10px] rounded-full ${roleBadge[m.role] || roleBadge.viewer}`}>
            {m.role}
          </span>
        </div>
      ))}
    </div>
  );
}

// ── Hours Tab ─────────────────────────────────────────────────

function HoursTab({ hours }: { hours: Record<string, [string, string]> | undefined }) {
  if (!hours || Object.keys(hours).length === 0) {
    return <div className="text-gray-500 text-sm py-4">Business hours not set.</div>;
  }
  const dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  const dayLabels: Record<string, string> = {
    mon: 'Monday', tue: 'Tuesday', wed: 'Wednesday', thu: 'Thursday',
    fri: 'Friday', sat: 'Saturday', sun: 'Sunday',
  };
  return (
    <div className="space-y-1">
      {dayOrder.map(day => {
        const h = hours[day];
        return (
          <div key={day} className="flex items-center justify-between text-sm py-1 border-b border-gray-800">
            <span className="text-gray-400">{dayLabels[day]}</span>
            <span className={h ? 'text-white' : 'text-gray-600'}>
              {h ? `${h[0]} - ${h[1]}` : 'Closed'}
            </span>
          </div>
        );
      })}
    </div>
  );
}

// ── Main Component ────────────────────────────────────────────

export function BusinessPage({ orgCertId }: BusinessPageProps) {
  const { state } = useLoom();
  const { config } = useExtension();
  const [activeTab, setActiveTab] = useState<Tab>('services');

  // Extract org data from loom state
  const orgData = useMemo(() => {
    // Find organization object
    let org: Record<string, any> | null = null;
    const services: Array<Record<string, any>> = [];
    const reviews: Array<Record<string, any>> = [];
    const members: Array<{ certId: string; role: string; joinedAt?: string }> = [];

    for (const obj of state.objects.values()) {
      const payload = obj.payload as Record<string, any>;
      if (obj.id === orgCertId || payload?.orgCertId === orgCertId) {
        if (obj.type === 'Organization' || payload?.type === 'ORGANIZATION') {
          org = payload;
        }
      }
      if (payload?.orgId === orgCertId) {
        if (obj.type === 'Service') services.push(payload);
        if (obj.type === 'Review') reviews.push({ ...payload, createdAt: obj.createdAt });
      }
    }

    // Compute aggregate rating
    const totalReviews = reviews.length;
    const avgRating = totalReviews > 0
      ? reviews.reduce((sum, r) => sum + (r.rating || 0), 0) / totalReviews
      : 0;

    return { org, services, reviews, members, totalReviews, avgRating };
  }, [state.objects, orgCertId]);

  const orgName = orgData.org?.orgName || orgData.org?.name || 'Business';
  const orgDescription = orgData.org?.metadata?.description || orgData.org?.description || '';
  const orgCategory = orgData.org?.metadata?.category || orgData.org?.category || '';
  const orgHours = orgData.org?.metadata?.hoursJson;

  const tabs: { id: Tab; label: string; count?: number }[] = [
    { id: 'services', label: 'Services', count: orgData.services.length },
    { id: 'reviews', label: 'Reviews', count: orgData.totalReviews },
    { id: 'team', label: 'Team', count: orgData.members.length },
    { id: 'hours', label: 'Hours' },
  ];

  return (
    <div className="max-w-2xl mx-auto p-4">
      {/* Header */}
      <div className="flex items-start gap-4 mb-6">
        <div className="w-16 h-16 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white text-2xl font-bold shrink-0">
          {orgName.charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold text-white truncate">{orgName}</h1>
          {orgCategory && (
            <div className="text-xs text-blue-400 mt-0.5">{orgCategory}</div>
          )}
          {orgDescription && (
            <div className="text-sm text-gray-400 mt-1">{orgDescription}</div>
          )}
          {orgData.totalReviews > 0 && (
            <div className="mt-2">
              <StarRating rating={orgData.avgRating} count={orgData.totalReviews} />
            </div>
          )}
          <div className="text-[10px] text-gray-600 mt-1">
            {orgCertId.slice(0, 16)}...
          </div>
        </div>
      </div>

      {/* Tab Bar */}
      <div className="flex border-b border-gray-700 mb-4">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`px-4 py-2 text-sm border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-blue-500 text-blue-400'
                : 'border-transparent text-gray-500 hover:text-gray-300'
            }`}
          >
            {tab.label}
            {tab.count !== undefined && tab.count > 0 && (
              <span className="ml-1 text-[10px] text-gray-500">({tab.count})</span>
            )}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      <div className="min-h-[200px]">
        {activeTab === 'services' && <ServicesTab services={orgData.services} />}
        {activeTab === 'reviews' && <ReviewsTab reviews={orgData.reviews} />}
        {activeTab === 'team' && <TeamTab members={orgData.members} />}
        {activeTab === 'hours' && <HoursTab hours={orgHours} />}
      </div>

      {/* OpenGraph meta hint (for SEO when SSR is added) */}
      <meta name="og:title" content={`${orgName} | Semantos Services`} />
      <meta name="og:description" content={`${orgDescription.slice(0, 160)}${orgData.totalReviews > 0 ? ` Rating: ${orgData.avgRating.toFixed(1)}` : ''}`} />
    </div>
  );
}

```
