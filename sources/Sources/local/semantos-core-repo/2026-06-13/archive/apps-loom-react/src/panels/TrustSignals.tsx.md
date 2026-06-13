---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/TrustSignals.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.953672+00:00
---

# archive/apps-loom-react/src/panels/TrustSignals.tsx

```tsx
/**
 * TrustSignals — reusable badge components for extension trust evaluation.
 *
 * Every extension card must show these signals. Uses "reputation score"
 * terminology exclusively.
 *
 * Components accept ExtensionManifest and optionally GovernedConsumerBinding
 * to compute trust indicators.
 */

import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import type { GovernedConsumerBinding } from '../../../protocol-types/src/governance';

// ── Individual Badge Components ─────────────────────────────────

interface ReputationBadgeProps {
  score: number;
}

/** Colored badge showing author's reputation score (0-100). */
export function ReputationBadge({ score }: ReputationBadgeProps) {
  const { color, bg, label } = getReputationTier(score);
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${bg} ${color}`}
      title={`Author's reputation score: ${score}/100. Higher = more trusted.`}
    >
      <span className="w-2 h-2 rounded-full" style={{ backgroundColor: getDotColor(score) }} />
      {score} {label}
    </span>
  );
}

interface InstallCountBadgeProps {
  count: number;
}

/** Shows number of active installations across the network. */
export function InstallCountBadge({ count }: InstallCountBadgeProps) {
  return (
    <span
      className="inline-flex items-center gap-1 px-2 py-0.5 text-xs text-gray-400"
      title="Number of nodes actively using this extension"
    >
      {formatCount(count)} installs
    </span>
  );
}

interface ObjectCountBadgeProps {
  count: number;
}

/** Shows total semantic objects created through this extension. */
export function ObjectCountBadge({ count }: ObjectCountBadgeProps) {
  return (
    <span
      className="inline-flex items-center gap-1 px-2 py-0.5 text-xs text-gray-400"
      title="Cumulative semantic objects extracted by this extension"
    >
      {formatCount(count)} objects
    </span>
  );
}

interface VersionStabilityIndicatorProps {
  majorCount: number;
  minorCount: number;
  patchCount: number;
}

/** Analyzes version history: many majors = unstable, few = stable. */
export function VersionStabilityIndicator({ majorCount, minorCount, patchCount }: VersionStabilityIndicatorProps) {
  const isUnstable = majorCount > 3;
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 text-xs ${isUnstable ? 'text-yellow-400' : 'text-green-400'}`}
      title={`Release frequency: ${majorCount} major, ${minorCount} minor, ${patchCount} patch. Many majors = breaking changes.`}
    >
      {isUnstable ? '\u26A0' : '\u2713'} v{majorCount}.{minorCount}.{patchCount}
    </span>
  );
}

interface GovernanceHealthBadgeProps {
  activeDisputes: number;
  totalVersions: number;
}

/** Ratio of open disputes to total versions published. */
export function GovernanceHealthBadge({ activeDisputes, totalVersions }: GovernanceHealthBadgeProps) {
  const hasIssues = activeDisputes > 0;
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 text-xs ${hasIssues ? 'text-yellow-400' : 'text-green-400'}`}
      title={`${activeDisputes} active dispute${activeDisputes !== 1 ? 's' : ''}, ${totalVersions} version${totalVersions !== 1 ? 's' : ''} published`}
    >
      {hasIssues ? `${activeDisputes} dispute${activeDisputes !== 1 ? 's' : ''}` : 'No disputes'}
    </span>
  );
}

interface AuditBadgeProps {
  isFirstParty: boolean;
}

/** Shows audit status — first-party extensions are Semantos-audited. */
export function AuditBadge({ isFirstParty }: AuditBadgeProps) {
  if (!isFirstParty) return null;
  return (
    <span
      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-blue-900/50 text-blue-300"
      title="This extension is maintained by Semantos and subject to core governance."
    >
      \u2713 Audited
    </span>
  );
}

interface CompatibilityBadgeProps {
  status: 'green' | 'yellow' | 'red';
  message?: string;
}

/** Colored dot showing version compatibility status. */
export function CompatibilityBadge({ status, message }: CompatibilityBadgeProps) {
  const colors = {
    green: { dot: 'bg-green-400', text: 'text-green-400', label: 'Compatible' },
    yellow: { dot: 'bg-yellow-400', text: 'text-yellow-400', label: 'Update available' },
    red: { dot: 'bg-red-400', text: 'text-red-400', label: 'Incompatible' },
  };
  const c = colors[status];
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 text-xs ${c.text}`}
      title={message ?? c.label}
    >
      <span className={`w-2 h-2 rounded-full ${c.dot}`} />
      {c.label}
    </span>
  );
}

interface DeprecationWarningProps {
  sunsetDate?: string;
  replacementId?: string;
}

/** Warning banner for deprecated extensions. */
export function DeprecationWarning({ sunsetDate, replacementId }: DeprecationWarningProps) {
  return (
    <div className="flex items-center gap-2 px-3 py-2 rounded bg-red-900/30 border border-red-800/50 text-xs text-red-300">
      <span>\u26A0 Deprecated</span>
      {sunsetDate && <span>Sunset: {sunsetDate}</span>}
      {replacementId && <span>Replacement: {replacementId}</span>}
    </div>
  );
}

// ── Composite Component ─────────────────────────────────────────

interface TrustSignalBarProps {
  manifest: ExtensionManifest;
  binding?: GovernedConsumerBinding;
  reputationScore?: number;
  installCount?: number;
  objectCount?: number;
  activeDisputes?: number;
}

/** Composite trust signal bar showing all badges for an extension card. */
export function TrustSignalBar({
  manifest,
  reputationScore = 0,
  installCount = 0,
  objectCount = 0,
  activeDisputes = 0,
}: TrustSignalBarProps) {
  const isFirstParty = manifest.metadata?.author === 'Semantos' ||
    manifest.governanceConfig?.patchAcceptancePolicy === 'author_only';

  const version = parseVersion(manifest.version);

  return (
    <div className="flex flex-wrap items-center gap-1 mt-1">
      <ReputationBadge score={reputationScore} />
      <InstallCountBadge count={installCount} />
      <ObjectCountBadge count={objectCount} />
      <VersionStabilityIndicator
        majorCount={version.major}
        minorCount={version.minor}
        patchCount={version.patch}
      />
      <GovernanceHealthBadge activeDisputes={activeDisputes} totalVersions={1} />
      <AuditBadge isFirstParty={isFirstParty} />
    </div>
  );
}

// ── Helpers ─────────────────────────────────────────────────────

function getReputationTier(score: number) {
  if (score >= 80) return { color: 'text-yellow-300', bg: 'bg-yellow-900/40', label: 'Core' };
  if (score >= 50) return { color: 'text-green-300', bg: 'bg-green-900/40', label: 'Trusted' };
  if (score >= 20) return { color: 'text-blue-300', bg: 'bg-blue-900/40', label: 'Emerging' };
  return { color: 'text-gray-400', bg: 'bg-gray-800', label: 'Unverified' };
}

function getDotColor(score: number): string {
  if (score >= 80) return '#fbbf24'; // gold
  if (score >= 50) return '#4ade80'; // green
  if (score >= 20) return '#60a5fa'; // blue
  return '#9ca3af'; // gray
}

function formatCount(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function parseVersion(version: string): { major: number; minor: number; patch: number } {
  const parts = version.split('.').map(Number);
  return { major: parts[0] || 0, minor: parts[1] || 0, patch: parts[2] || 0 };
}

```
