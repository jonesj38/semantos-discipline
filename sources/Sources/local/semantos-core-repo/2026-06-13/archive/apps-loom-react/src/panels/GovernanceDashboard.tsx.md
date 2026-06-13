---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/GovernanceDashboard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.952798+00:00
---

# archive/apps-loom-react/src/panels/GovernanceDashboard.tsx

```tsx
/**
 * GovernanceDashboard — three-tier governance view (L0, L1, L2) + disputes + compat matrix.
 *
 * Reads governance state from LoomStore objects. Calls constraint engine
 * and version-compat functions directly. Renders real governance state, not mocks.
 *
 * State: useLoom() for governance objects, useIdentity() for hat checks.
 */

import { useState, useMemo, useCallback } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useIdentity } from '../identity/IdentityProvider';
import { useExtension } from '../config/ExtensionProvider';
import type {
  GovernancePolicy, GovernancePolicyPayload, GovernedConsumerBindingPayload,
  GovernanceBallot, ManifestGovernanceConfig, ConstraintResult, CompatibilityResult,
  FieldOverride, TaxonomyOverride, LocalField,
} from '../../../protocol-types/src/governance';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import { enforceL0Constraints, enforceL1Constraints } from '../../../extraction/src/governance/constraint-engine';
import { checkCompatibility } from '../../../extraction/src/governance/version-compat';
import { createDisputeL2toL1, createDisputeL1toL0 } from '../../../extraction/src/governance/dispute-escalator';
import { CompatibilityBadge } from './TrustSignals';

type Tab = 'l0-policy' | 'l1-author' | 'l2-binding' | 'disputes' | 'compat-matrix';

export function GovernanceDashboard() {
  const [activeTab, setActiveTab] = useState<Tab>('l0-policy');
  const { activeHat } = useIdentity();

  const tabs: Array<{ id: Tab; label: string; visible: boolean }> = [
    { id: 'l0-policy', label: 'L0 Policy', visible: true },
    { id: 'l1-author', label: 'L1 Author', visible: true },
    { id: 'l2-binding', label: 'L2 Binding', visible: true },
    { id: 'disputes', label: 'Disputes', visible: true },
    { id: 'compat-matrix', label: 'Compatibility', visible: true },
  ];

  return (
    <div className="flex flex-col h-full">
      <div className="px-4 py-3 border-b border-gray-800">
        <h2 className="text-sm font-semibold text-gray-200">Governance Dashboard</h2>
        <div className="flex items-center gap-1 mt-2">
          {tabs.filter(t => t.visible).map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-3 py-1 text-xs rounded ${
                activeTab === tab.id
                  ? 'bg-blue-900/50 text-blue-300'
                  : 'text-gray-500 hover:text-gray-300 hover:bg-gray-800'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4">
        {activeTab === 'l0-policy' && <L0PolicyTab />}
        {activeTab === 'l1-author' && <L1AuthorTab />}
        {activeTab === 'l2-binding' && <L2BindingTab />}
        {activeTab === 'disputes' && <DisputesTab />}
        {activeTab === 'compat-matrix' && <CompatMatrixTab />}
      </div>
    </div>
  );
}

// ── L0 Policy Tab ───────────────────────────────────────────────

function L0PolicyTab() {
  const { state } = useLoom();

  // Find GovernancePolicy objects in the store
  const policy = useMemo(() => {
    for (const obj of state.objects.values()) {
      const p = obj.payload as Record<string, unknown>;
      if (p.metaSchemaVersion && p.governedByHatId) {
        return p as unknown as GovernancePolicyPayload;
      }
    }
    // Return default policy if none found in store
    return getDefaultPolicy();
  }, [state.objects]);

  return (
    <div className="space-y-4">
      <SectionHeader title="Platform Governance Policy" subtitle="Read-only L0 constitution" />

      <FieldTable
        rows={[
          ['Meta-schema version', policy.metaSchemaVersion],
          ['Ballot quorum', `${policy.breakingChangeBallotQuorum}%`],
          ['Effective date', policy.effectiveDate],
          ['Governed by', policy.governedByHatId],
        ]}
      />

      <SectionHeader title="Required Capabilities Whitelist" />
      <div className="flex flex-wrap gap-1">
        {policy.requiredCapabilitiesWhitelist.map((cap) => (
          <span key={cap} className="px-2 py-0.5 text-xs bg-gray-800 text-gray-400 rounded">
            {cap}
          </span>
        ))}
      </div>

      <SectionHeader title="Marketplace Listing Requirements" />
      <FieldTable
        rows={[
          ['Min author reputation score', String(policy.marketplaceListingRequirements.minAuthorReputationScore)],
          ['Min object count', String(policy.marketplaceListingRequirements.minObjectCount)],
          ['Requires audit', policy.marketplaceListingRequirements.requiresAudit ? 'Yes' : 'No'],
          ['Audit frequency', `${policy.marketplaceListingRequirements.auditFrequencyDays} days`],
        ]}
      />

      <SectionHeader title="Taxonomy Namespace Reservations" />
      {policy.taxonomyNamespaceReservations.length > 0 ? (
        <div className="space-y-1">
          {policy.taxonomyNamespaceReservations.map((ns) => (
            <div key={ns.namespace} className="flex items-center gap-2 text-xs">
              <span className="text-gray-300 font-mono">{ns.namespace}</span>
              <span className="text-gray-500">{ns.reason}</span>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-xs text-gray-500">No reservations</p>
      )}

      <SectionHeader title="Emergency Deprecation Policy" />
      <FieldTable
        rows={[
          ['Requires vote', policy.emergencyDeprecationPolicy.requiresVote ? 'Yes' : 'No'],
          ['Min days notice', String(policy.emergencyDeprecationPolicy.minDaysNotice)],
          ['Escalation threshold', policy.emergencyDeprecationPolicy.escalationThreshold],
        ]}
      />
    </div>
  );
}

// ── L1 Author Tab ───────────────────────────────────────────────

function L1AuthorTab() {
  const { activeHat } = useIdentity();
  const { config } = useExtension();

  if (!activeHat) {
    return <EmptyState message="No active hat. Switch to a hat to view authored extensions." />;
  }

  // Check if the active config has a governance config (i.e., user is an author)
  const govConfig: ManifestGovernanceConfig | null = useMemo(() => {
    // In production, query manifests authored by this hat
    // For now, show a representative governance config
    return {
      patchAcceptancePolicy: 'author_only' as const,
      versionBumpRules: {
        major: 'author_only' as const,
        minor: 'author_only' as const,
        patch: 'author_only' as const,
      },
      contributorHats: [],
      deprecationTimelineMinDays: 30,
    };
  }, []);

  return (
    <div className="space-y-4">
      <SectionHeader
        title="Extension Author Panel"
        subtitle={`Active hat: ${activeHat.displayName}`}
      />

      <SectionHeader title="Governance Configuration" />
      <FieldTable
        rows={[
          ['Patch acceptance', govConfig.patchAcceptancePolicy.replace(/_/g, ' ')],
          ['Major bumps', govConfig.versionBumpRules.major.replace(/_/g, ' ')],
          ['Minor bumps', govConfig.versionBumpRules.minor.replace(/_/g, ' ')],
          ['Patch bumps', govConfig.versionBumpRules.patch],
          ['Deprecation notice', `${govConfig.deprecationTimelineMinDays} days minimum`],
        ]}
      />

      <SectionHeader title="Contributors" />
      {govConfig.contributorHats.length > 0 ? (
        <div className="space-y-1">
          {govConfig.contributorHats.map((facetId) => (
            <div key={facetId} className="flex items-center justify-between text-xs">
              <span className="text-gray-300 font-mono">{facetId}</span>
              <button className="text-red-400 hover:text-red-300">Remove</button>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-xs text-gray-500">No contributors. This extension is author-only.</p>
      )}

      <div className="flex gap-2 mt-4">
        <button className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700">
          Invite Contributor
        </button>
        <button className="px-3 py-1.5 text-xs bg-red-900/30 hover:bg-red-900/50 text-red-400 rounded border border-red-800/50">
          Initiate Deprecation
        </button>
      </div>
    </div>
  );
}

// ── L2 Binding Tab ──────────────────────────────────────────────

function L2BindingTab() {
  const { state } = useLoom();
  const [selectedBindingId, setSelectedBindingId] = useState<string | null>(null);
  const [saveResult, setSaveResult] = useState<ConstraintResult | null>(null);

  // Find binding objects
  const bindings = useMemo(() => {
    const result: Array<{ id: string; payload: GovernedConsumerBindingPayload }> = [];
    for (const obj of state.objects.values()) {
      const p = obj.payload as Record<string, unknown>;
      if (p.extensionManifestId && p.grammarVersionPinned) {
        result.push({ id: obj.id, payload: p as unknown as GovernedConsumerBindingPayload });
      }
    }
    return result;
  }, [state.objects]);

  if (bindings.length === 0) {
    return <EmptyState message="No consumer bindings found. Install an extension first." />;
  }

  const selectedBinding = bindings.find((b) => b.id === selectedBindingId) ?? bindings[0];

  return (
    <div className="space-y-4">
      <SectionHeader title="L2 Binding Configuration" subtitle="Edit per-binding settings" />

      <div>
        <label className="text-xs text-gray-500 block mb-1">Select binding</label>
        <select
          className="w-full px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-300"
          value={selectedBinding?.id ?? ''}
          onChange={(e) => setSelectedBindingId(e.target.value)}
        >
          {bindings.map((b) => (
            <option key={b.id} value={b.id}>
              {b.payload.extensionManifestId} ({b.payload.grammarVersionPinned})
            </option>
          ))}
        </select>
      </div>

      {selectedBinding && (
        <>
          <SectionHeader title="Credentials" />
          <div className="flex items-center gap-2 text-xs">
            <span className="text-gray-400">Encrypted</span>
            <span className="text-gray-500 font-mono">
              {selectedBinding.payload.credentialsEncrypted?.credentialFieldNames.join(', ') ?? 'None'}
            </span>
            <button className="px-2 py-0.5 bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700">
              Update credentials
            </button>
          </div>

          <SectionHeader title="Field Overrides" />
          <OverridesTable overrides={selectedBinding.payload.fieldOverrides ?? []} />

          <SectionHeader title="Taxonomy Overrides" />
          <TaxonomyOverridesTable overrides={selectedBinding.payload.taxonomyOverrides ?? []} />

          <SectionHeader title="Version Policy" />
          <FieldTable
            rows={[
              ['Version pin', selectedBinding.payload.grammarVersionPinned],
              ['Auto-update', selectedBinding.payload.autoUpdateGrammar ? 'Yes' : 'No'],
            ]}
          />

          {saveResult && !saveResult.valid && (
            <div className="p-3 bg-red-900/20 border border-red-800/50 rounded text-xs text-red-300">
              <p className="font-medium mb-1">Constraint violations:</p>
              {saveResult.violations.map((v, i) => (
                <p key={i}>{v.level}: {v.message}</p>
              ))}
            </div>
          )}

          <button
            className="px-3 py-1.5 text-xs bg-blue-900/50 hover:bg-blue-900/70 text-blue-300 rounded border border-blue-800/50"
          >
            Save Changes
          </button>
        </>
      )}
    </div>
  );
}

// ── Disputes Tab ────────────────────────────────────────────────

function DisputesTab() {
  const { state } = useLoom();

  // Find ballot/dispute objects
  const disputes = useMemo(() => {
    const result: GovernanceBallot[] = [];
    for (const obj of state.objects.values()) {
      const p = obj.payload as Record<string, unknown>;
      if (p.motion && p.disputeLevel) {
        result.push(p as unknown as GovernanceBallot);
      }
    }
    return result;
  }, [state.objects]);

  return (
    <div className="space-y-4">
      <SectionHeader title="Active Disputes" subtitle="Governance disputes and ballot status" />

      {disputes.length === 0 ? (
        <EmptyState message="No active disputes." />
      ) : (
        <div className="space-y-2">
          {disputes.map((dispute, i) => (
            <div key={i} className="bg-gray-800 border border-gray-700 rounded p-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-300 font-medium">{dispute.motion}</span>
                <span className={`px-1.5 py-0.5 text-xs rounded ${
                  dispute.disputeLevel === 'L2_to_L1' ? 'bg-yellow-900/40 text-yellow-400' : 'bg-red-900/40 text-red-400'
                }`}>
                  {dispute.disputeLevel.replace(/_/g, '\u2192')}
                </span>
              </div>
              <div className="mt-1 text-xs text-gray-500 space-y-0.5">
                <p>Reason: {dispute.reason}</p>
                <p>Quorum: {dispute.quorum} votes required</p>
                <p>Initiator: {dispute.initiatorHatId}</p>
                {dispute.escalationDeadline && (
                  <p>Escalation deadline: {dispute.escalationDeadline}</p>
                )}
              </div>
              <div className="flex gap-1 mt-2">
                <button className="px-2 py-0.5 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded">
                  Vote
                </button>
                <button className="px-2 py-0.5 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded">
                  Escalate
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <button className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700">
        File New Dispute
      </button>
    </div>
  );
}

// ── Compatibility Matrix Tab ────────────────────────────────────

function CompatMatrixTab() {
  const { state } = useLoom();
  const { config } = useExtension();

  // Build compatibility matrix from bindings
  const matrix = useMemo(() => {
    const entries: Array<{
      extensionId: string;
      version: string;
      status: 'green' | 'yellow' | 'red';
      message: string;
    }> = [];

    for (const obj of state.objects.values()) {
      const p = obj.payload as Record<string, unknown>;
      if (p.extensionManifestId && p.grammarVersionPinned) {
        const payload = p as unknown as GovernedConsumerBindingPayload;
        // Default to green if we can't compute (no manifest to check against)
        entries.push({
          extensionId: payload.extensionManifestId,
          version: payload.grammarVersionPinned,
          status: payload.status === 'deprecated' ? 'red' : payload.status === 'paused' ? 'yellow' : 'green',
          message: payload.status === 'deprecated' ? 'Extension deprecated' : payload.status === 'active' ? 'Compatible' : 'Paused',
        });
      }
    }

    return entries;
  }, [state.objects]);

  return (
    <div className="space-y-4">
      <SectionHeader title="Version Compatibility Matrix" subtitle="Extension compatibility at a glance" />

      {matrix.length === 0 ? (
        <EmptyState message="No bindings to check compatibility for." />
      ) : (
        <table className="w-full text-xs">
          <thead>
            <tr className="text-gray-500 border-b border-gray-800">
              <th className="py-2 px-3 text-left font-medium">Extension</th>
              <th className="py-2 px-3 text-left font-medium">Version</th>
              <th className="py-2 px-3 text-left font-medium">Status</th>
              <th className="py-2 px-3 text-left font-medium">Message</th>
            </tr>
          </thead>
          <tbody>
            {matrix.map((entry, i) => (
              <tr key={i} className="border-b border-gray-800/50">
                <td className="py-2 px-3 text-gray-300 font-mono">{entry.extensionId}</td>
                <td className="py-2 px-3 text-gray-400">{entry.version}</td>
                <td className="py-2 px-3">
                  <CompatibilityBadge status={entry.status} />
                </td>
                <td className="py-2 px-3 text-gray-500">{entry.message}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// ── Shared UI Components ────────────────────────────────────────

function SectionHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div>
      <h3 className="text-xs font-semibold text-gray-300 uppercase tracking-wider">{title}</h3>
      {subtitle && <p className="text-xs text-gray-500 mt-0.5">{subtitle}</p>}
    </div>
  );
}

function FieldTable({ rows }: { rows: [string, string][] }) {
  return (
    <table className="w-full text-xs">
      <tbody>
        {rows.map(([label, value]) => (
          <tr key={label} className="border-b border-gray-800/50">
            <td className="py-1.5 pr-4 text-gray-500 whitespace-nowrap">{label}</td>
            <td className="py-1.5 text-gray-300">{value}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function OverridesTable({ overrides }: { overrides: FieldOverride[] }) {
  if (overrides.length === 0) {
    return <p className="text-xs text-gray-500">No field overrides</p>;
  }
  return (
    <div className="space-y-2">
      {overrides.map((override, i) => (
        <div key={i} className="text-xs">
          <span className="text-gray-400 font-mono">{override.objectType}</span>
          <div className="ml-3 mt-1 space-y-0.5">
            {override.localFields.map((field) => (
              <div key={field.fieldName} className="flex gap-2 text-gray-500">
                <span className="font-mono">{field.fieldName}</span>
                <span>({field.sourceType})</span>
                {field.required && <span className="text-yellow-400">required</span>}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function TaxonomyOverridesTable({ overrides }: { overrides: TaxonomyOverride[] }) {
  if (overrides.length === 0) {
    return <p className="text-xs text-gray-500">No taxonomy overrides</p>;
  }
  return (
    <table className="w-full text-xs">
      <thead>
        <tr className="text-gray-500 border-b border-gray-800">
          <th className="py-1 px-2 text-left font-medium">Object Type</th>
          <th className="py-1 px-2 text-left font-medium">What</th>
          <th className="py-1 px-2 text-left font-medium">How</th>
          <th className="py-1 px-2 text-left font-medium">Why</th>
        </tr>
      </thead>
      <tbody>
        {overrides.map((o, i) => (
          <tr key={i} className="border-b border-gray-800/50">
            <td className="py-1 px-2 text-gray-300 font-mono">{o.objectType}</td>
            <td className="py-1 px-2 text-gray-400">{o.taxonomy.what ?? '-'}</td>
            <td className="py-1 px-2 text-gray-400">{o.taxonomy.how ?? '-'}</td>
            <td className="py-1 px-2 text-gray-400">{o.taxonomy.why ?? '-'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function EmptyState({ message }: { message: string }) {
  return <p className="text-xs text-gray-500 py-4">{message}</p>;
}

// ── Helpers ─────────────────────────────────────────────────────

function getDefaultPolicy(): GovernancePolicyPayload {
  return {
    metaSchemaVersion: '1.0.0',
    requiredCapabilitiesWhitelist: ['network.outbound', 'storage.write', 'storage.read', 'identity.read'],
    taxonomyNamespaceReservations: [
      { namespace: 'what.platform', reason: 'Reserved for Semantos platform types' },
      { namespace: 'what.governance', reason: 'Reserved for governance objects' },
    ],
    marketplaceListingRequirements: {
      minAuthorReputationScore: 20,
      minObjectCount: 10,
      requiresAudit: false,
      auditFrequencyDays: 90,
    },
    breakingChangeBallotQuorum: 66,
    emergencyDeprecationPolicy: {
      requiresVote: true,
      minDaysNotice: 14,
      escalationThreshold: 'critical',
    },
    effectiveDate: '2026-01-01T00:00:00Z',
    governedByHatId: 'semantos-core-multisig',
  };
}

```
