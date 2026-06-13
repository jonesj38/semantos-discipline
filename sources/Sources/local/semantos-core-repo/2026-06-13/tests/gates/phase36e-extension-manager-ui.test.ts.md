---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36e-extension-manager-ui.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.583837+00:00
---

# tests/gates/phase36e-extension-manager-ui.test.ts

```ts
/**
 * Phase 36E Gate Tests — Extension Manager UI
 *
 * T1–T3:   Marketplace Panel
 * T4–T6:   My Extensions Panel
 * T7–T9:   Governance Dashboard
 * T10–T11: Extension Detail
 * T12–T13: Binding Configuration Wizard
 * T14–T15: Trust Signals
 * T16:     Shell Commands
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

import type {
  GovernancePolicy,
  GovernedConsumerBinding,
  GovernedConsumerBindingPayload,
  ConstraintResult,
  CompatibilityResult,
  GovernanceBallot,
  ManifestGovernanceConfig,
  EncryptedCredentials,
  FieldOverride,
  TaxonomyOverride,
} from '../../core/protocol-types/src/governance';
import type { ExtensionManifest } from '../../core/protocol-types/src/extension-manifest';
import type { ExtensionGrammar, EntityMapping, FieldMapping } from '../../core/protocol-types/src/extension-grammar';
import { enforceL0Constraints, enforceL1Constraints } from '../../packages/extraction/src/governance/constraint-engine';
import { checkCompatibility } from '../../packages/extraction/src/governance/version-compat';
import { encryptCredentials, decryptCredentials } from '../../packages/extraction/src/governance/credential-vault';
import {
  createDisputeL2toL1,
  createDisputeL1toL0,
  escalateDispute,
} from '../../packages/extraction/src/governance/dispute-escalator';

const ROOT = join(import.meta.dir, '../..');

// ── Test Fixtures ──────────────────────────────────────────────

function makeGrammar(overrides?: Partial<ExtensionGrammar>): ExtensionGrammar {
  return {
    metaSchemaVersion: '1.0.0',
    grammarId: 'com.test.fixture',
    grammarVersion: '1.0.0',
    displayName: 'Test Grammar',
    description: 'A test grammar fixture',
    author: { certId: 'test-author-cert', name: 'Test Author' },
    source: {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.test.com/v1',
      auth: { type: 'api-key', requiredCredentials: ['api_key'] },
      entities: [{
        entityId: 'item',
        displayName: 'Item',
        endpoint: { list: '/items', get: '/items/{id}' },
        responseShape: { dataPath: '$.data', idField: 'id' },
        fields: [
          { sourceFieldName: 'id', sourceType: 'string', required: true },
          { sourceFieldName: 'name', sourceType: 'string', required: true },
          { sourceFieldName: 'value', sourceType: 'number', required: false },
        ],
        relationships: [{
          targetEntityId: 'category',
          type: 'belongs_to',
          foreignKey: 'category_id',
          foreignKeyLocation: 'source',
        }],
      }, {
        entityId: 'category',
        displayName: 'Category',
        endpoint: { list: '/categories', get: '/categories/{id}' },
        responseShape: { dataPath: '$.data', idField: 'id' },
        fields: [
          { sourceFieldName: 'id', sourceType: 'string', required: true },
          { sourceFieldName: 'name', sourceType: 'string', required: true },
        ],
      }],
    },
    objectTypes: [{
      typePath: 'test.item',
      displayName: 'Test Item',
      description: 'A test item',
      linearity: 'AFFINE',
      phases: ['active'],
      initialPhase: 'active',
      payloadSchema: {
        name: { type: 'string' },
        value: { type: 'number' },
      },
      capabilities: { read: [1] },
    }],
    entityMappings: [{
      sourceEntityId: 'item',
      targetObjectType: 'test.item',
      fieldMappings: [
        { sourceField: 'name', targetField: 'name', required: true },
        { sourceField: 'value', targetField: 'value', required: false, transform: { type: 'compute', expression: 'source.value * 100' } },
      ],
      taxonomy: { what: 'what.test.item', how: 'how.digital.api', why: 'why.integration' },
    }],
    capabilities: [
      { capability: 'network.outbound', reason: 'Fetch data from API', required: true },
      { capability: 'storage.write', reason: 'Store extracted objects', required: true },
      { capability: 'storage.read', reason: 'Read stored objects', required: true },
    ],
    taxonomyNamespace: 'test',
    migrations: [
      {
        fromVersion: '0.9.0',
        toVersion: '1.0.0',
        fieldRenames: { 'old_name': 'name' },
        fieldsRemoved: ['legacy_field'],
        fieldsAdded: { value: 0 },
        breakingChanges: 'Renamed old_name to name, removed legacy_field',
      },
    ],
    ...overrides,
  };
}

function makePolicy(overrides?: Partial<GovernancePolicy>): GovernancePolicy {
  return {
    typePath: 'governance.policy',
    linearity: 'RELEVANT',
    constitution: true,
    payload: {
      metaSchemaVersion: '1.0.0',
      requiredCapabilitiesWhitelist: ['network.outbound', 'storage.write', 'storage.read'],
      taxonomyNamespaceReservations: [
        { namespace: 'what.platform', reason: 'Reserved for platform' },
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
    },
    ...overrides,
  };
}

function makeManifest(overrides?: Partial<ExtensionManifest>): ExtensionManifest {
  return {
    id: 'test-extension',
    name: 'Test Extension',
    version: '1.0.0',
    taxonomyPath: 'taxonomy/test.json',
    flowsDir: 'flows',
    promptsDir: 'prompts',
    metadata: {
      description: 'A test extension',
      author: 'Test Author',
    },
    governanceConfig: {
      patchAcceptancePolicy: 'author_only',
      versionBumpRules: { major: 'author_only', minor: 'author_only', patch: 'author_only' },
      contributorHats: [],
      deprecationTimelineMinDays: 30,
    },
    manifestLinearity: 'AFFINE',
    grammar: makeGrammar(),
    ...overrides,
  };
}

function makeBinding(overrides?: Partial<GovernedConsumerBindingPayload>): GovernedConsumerBinding {
  return {
    typePath: 'extension.consumer-binding',
    linearity: 'AFFINE',
    scope: 'node',
    payload: {
      extensionManifestId: 'test-extension',
      grammarVersionPinned: '^1.0.0',
      credentialsEncrypted: {
        encryptedBlob: 'STUB_ENCRYPTED:{"api_key":"test-key-123"}',
        encryptionKeyId: 'node-key-1',
        credentialFieldNames: ['api_key'],
      },
      autoUpdateGrammar: true,
      status: 'active',
      ...overrides,
    },
  };
}

// ── T1–T3: Marketplace Panel ────────────────────────────────────

describe('Marketplace Panel (T1–T3)', () => {
  test('T1: Marketplace panel component exists and exports correctly', () => {
    const panelPath = join(ROOT, 'apps/loom-react/src/panels/ExtensionMarketplace.tsx');
    expect(existsSync(panelPath)).toBe(true);

    const source = readFileSync(panelPath, 'utf8');
    // Must render extension name, version, author, trust signals
    expect(source).toContain('manifest.name');
    expect(source).toContain('manifest.version');
    expect(source).toContain('TrustSignalBar');
    expect(source).toContain('onInstall');
    // Must not show raw JSON of grammar
    expect(source).not.toContain('JSON.stringify');
  });

  test('T2: Search filters extensions by name/author/category', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/ExtensionMarketplace.tsx'), 'utf8');
    // Search filter implementation
    expect(source).toContain('searchQuery');
    expect(source).toContain('categoryFilter');
    expect(source).toContain('toLowerCase');
    expect(source).toContain('.filter(');
  });

  test('T3: Install button opens BindingWizard', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/ExtensionMarketplace.tsx'), 'utf8');
    expect(source).toContain('onInstall');
    // MarketSurface integration (Phase 39: extension panels moved to Support Drawer)
    const marketSource = readFileSync(join(ROOT, 'apps/loom-react/src/helm/MarketSurface.tsx'), 'utf8');
    expect(marketSource).toContain('BindingWizard');
    expect(marketSource).toContain('wizardManifest');
  });
});

// ── T4–T6: My Extensions Panel ─────────────────────────────────

describe('My Extensions Panel (T4–T6)', () => {
  test('T4: My Extensions shows installed bindings with status badges (active/paused/deprecated)', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/MyExtensions.tsx'), 'utf8');
    expect(source).toContain('StatusBadge');
    expect(source).toContain('active');
    expect(source).toContain('paused');
    expect(source).toContain('deprecated');
    expect(source).toContain('extensionManifestId');
  });

  test('T5: Extraction status shows last run, object count, errors', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/MyExtensions.tsx'), 'utf8');
    expect(source).toContain('lastExtractionTimestamp');
    expect(source).toContain('formatRelativeTime');
    expect(source).toContain('credentialFieldNames');
  });

  test('T6: Update button shows compatibility check', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/MyExtensions.tsx'), 'utf8');
    expect(source).toContain('checkCompatibility');
    expect(source).toContain('CompatibilityBadge');
    // Bindings can be removed
    expect(source).toContain('handleRemove');
    expect(source).toContain("'DELETE_OBJECT'");
  });
});

// ── T7–T9: Governance Dashboard ─────────────────────────────────

describe('Governance Dashboard (T7–T9)', () => {
  test('T7: L0 Policy tab shows GovernancePolicy as read-only', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/GovernanceDashboard.tsx'), 'utf8');
    expect(source).toContain('L0PolicyTab');
    expect(source).toContain('metaSchemaVersion');
    expect(source).toContain('requiredCapabilitiesWhitelist');
    expect(source).toContain('breakingChangeBallotQuorum');
    expect(source).toContain('emergencyDeprecationPolicy');
    expect(source).toContain('marketplaceListingRequirements');
  });

  test('T8: L1 Author Panel shows governance config and deprecation controls', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/GovernanceDashboard.tsx'), 'utf8');
    expect(source).toContain('L1AuthorTab');
    expect(source).toContain('patchAcceptancePolicy');
    expect(source).toContain('versionBumpRules');
    expect(source).toContain('deprecationTimelineMinDays');
    expect(source).toContain('Initiate Deprecation');
    expect(source).toContain('Invite Contributor');
  });

  test('T9: L2 Binding Config edits overrides and validates constraints', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/GovernanceDashboard.tsx'), 'utf8');
    expect(source).toContain('L2BindingTab');
    expect(source).toContain('fieldOverrides');
    expect(source).toContain('taxonomyOverrides');
    expect(source).toContain('enforceL1Constraints');
    expect(source).toContain('Save Changes');
  });
});

// ── T10–T11: Extension Detail ───────────────────────────────────

describe('Extension Detail (T10–T11)', () => {
  test('T10: Extension detail renders grammar inspector with field mapping table', () => {
    const detailSource = readFileSync(join(ROOT, 'apps/loom-react/src/panels/ExtensionDetail.tsx'), 'utf8');
    expect(detailSource).toContain('GrammarInspector');
    expect(detailSource).toContain('FieldMappingTable');
    expect(detailSource).toContain('EntityDiagram');

    // Grammar inspector renders tables, not raw JSON
    const grammarSource = readFileSync(join(ROOT, 'apps/loom-react/src/panels/GrammarInspector.tsx'), 'utf8');
    expect(grammarSource).not.toContain('JSON.stringify');
    expect(grammarSource).toContain('ObjectTypesSection');
    expect(grammarSource).toContain('CapabilitiesSection');
    expect(grammarSource).toContain('payloadSchema');

    // Entity diagram renders SVG
    const diagramSource = readFileSync(join(ROOT, 'apps/loom-react/src/panels/EntityDiagram.tsx'), 'utf8');
    expect(diagramSource).toContain('<svg');
    expect(diagramSource).toContain('<rect');
    expect(diagramSource).toContain('onEntityClick');
  });

  test('T11: Version timeline shows history; evidence chain viewer works', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/ExtensionDetail.tsx'), 'utf8');
    // Version timeline
    expect(source).toContain('VersionTimeline');
    expect(source).toContain('MigrationDetail');
    expect(source).toContain('compareVersions');
    expect(source).toContain('breakingChanges');
    // Evidence chain viewer
    expect(source).toContain('EvidenceChainView');
    expect(source).toContain('patches');
    // Extraction history
    expect(source).toContain('ExtractionHistory');
    expect(source).toContain('dateFilter');
  });
});

// ── T12–T13: Binding Wizard ─────────────────────────────────────

describe('Binding Configuration Wizard (T12–T13)', () => {
  test('T12: Wizard completes 6-step flow with validation', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/BindingWizard.tsx'), 'utf8');
    // 6 steps
    expect(source).toContain('Step1SelectExtension');
    expect(source).toContain('Step2Credentials');
    expect(source).toContain('Step3Overrides');
    expect(source).toContain('Step4VersionPolicy');
    expect(source).toContain('Step5TestConnection');
    expect(source).toContain('Step6Confirm');
    // Validation at each step
    expect(source).toContain('enforceL0Constraints');
    expect(source).toContain('enforceL1Constraints');
    expect(source).toContain('checkCompatibility');
    // Creates binding on confirm
    expect(source).toContain("type: 'ADD_OBJECT'");
    expect(source).toContain('ConsumerBinding');
  });

  test('T13: Test connection runs dry-run and blocks on failure; credentials encrypted', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/BindingWizard.tsx'), 'utf8');
    // Test connection
    expect(source).toContain('handleTestConnection');
    expect(source).toContain("testStatus === 'success'");
    // Credentials encrypted before storage
    expect(source).toContain('encryptCredentials');
    expect(source).toContain('setCredentialValues({})'); // Clear plaintext after encryption
    // No plaintext credential storage
    expect(source).not.toContain('credentialPlaintext');
  });

  test('T13b: Credential encryption roundtrip works', async () => {
    const credentials = { api_key: 'test-secret-key-123', token: 'bearer-token-xyz' };
    const encrypted = await encryptCredentials(credentials, 'node-key-1');

    expect(encrypted.encryptionKeyId).toBe('node-key-1');
    expect(encrypted.credentialFieldNames).toContain('api_key');
    expect(encrypted.credentialFieldNames).toContain('token');
    expect(encrypted.encryptedBlob).toBeTruthy();

    // Roundtrip
    const decrypted = await decryptCredentials(encrypted);
    expect(decrypted.api_key).toBe('test-secret-key-123');
    expect(decrypted.token).toBe('bearer-token-xyz');
  });
});

// ── T14–T15: Trust Signals ──────────────────────────────────────

describe('Trust Signals (T14–T15)', () => {
  test('T14: Reputation badge renders with color based on score', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/TrustSignals.tsx'), 'utf8');
    // Color ranges
    expect(source).toContain('getReputationTier');
    expect(source).toContain('score >= 80');
    expect(source).toContain('score >= 50');
    expect(source).toContain('score >= 20');
    // Uses "reputation score" terminology, not "Glow weight"
    expect(source).toContain('reputation score');
    expect(source).not.toContain('Glow weight');
    // Color coding
    expect(source).toContain("'Core'");
    expect(source).toContain("'Trusted'");
    expect(source).toContain("'Emerging'");
    expect(source).toContain("'Unverified'");
  });

  test('T15: All trust signal badges render with tooltips', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/TrustSignals.tsx'), 'utf8');
    // All badge components exported
    expect(source).toContain('export function ReputationBadge');
    expect(source).toContain('export function InstallCountBadge');
    expect(source).toContain('export function ObjectCountBadge');
    expect(source).toContain('export function VersionStabilityIndicator');
    expect(source).toContain('export function GovernanceHealthBadge');
    expect(source).toContain('export function AuditBadge');
    expect(source).toContain('export function CompatibilityBadge');
    expect(source).toContain('export function DeprecationWarning');
    expect(source).toContain('export function TrustSignalBar');
    // Tooltips via title attribute
    expect(source).toContain('title=');
  });
});

// ── T16: Shell Commands ─────────────────────────────────────────

describe('Shell Commands (T16)', () => {
  test('T16: Extension shell commands exist and route correctly', () => {
    // Router has extension verb
    const routerSource = readFileSync(join(ROOT, 'runtime/shell/src/router.ts'), 'utf8');
    expect(routerSource).toContain("case 'extension':");
    expect(routerSource).toContain('routeExtension');

    // Extension command file exists with subcommands
    const cmdSource = readFileSync(join(ROOT, 'packages/shell/src/commands/extension.ts'), 'utf8');
    expect(cmdSource).toContain('routeExtension');
    expect(cmdSource).toContain("case 'list':");
    expect(cmdSource).toContain("case 'status':");
    expect(cmdSource).toContain("case 'detail':");
    // Grammar info in output
    expect(cmdSource).toContain('grammarInfo');
    expect(cmdSource).toContain('objectTypes');
    // Version compatibility
    expect(cmdSource).toContain('checkCompatibility');
  });

  test('T16b: REPL help text updated with extension commands', () => {
    const replSource = readFileSync(join(ROOT, 'runtime/shell/src/repl.ts'), 'utf8');
    expect(replSource).toContain('EXTENSIONS (Phase 36E)');
    expect(replSource).toContain('extension list');
    expect(replSource).toContain('extension status');
    expect(replSource).toContain('extension detail');
  });
});

// ── Cross-cutting: Loom Integration ────────────────────────

describe('Loom Integration', () => {
  test('LoomApp integrates Extension Manager panels', () => {
    // Phase 39: extension panels moved from LoomApp to MarketSurface (Support Drawer)
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/helm/MarketSurface.tsx'), 'utf8');
    expect(source).toContain('ExtensionMarketplace');
    expect(source).toContain('MyExtensions');
    expect(source).toContain('GovernanceDashboard');
    expect(source).toContain('ExtensionDetail');
    expect(source).toContain('BindingWizard');
    // Panel navigation
    expect(source).toContain('activePanel');
    expect(source).toContain("'marketplace'");
    expect(source).toContain("'my-extensions'");
    expect(source).toContain("'governance'");
    // LoomApp renders Helm which contains SupportDrawer → MarketSurface
    const appSource = readFileSync(join(ROOT, 'apps/loom-react/src/LoomApp.tsx'), 'utf8');
    expect(appSource).toContain('Helm');
  });

  test('Panel barrel exports all components', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/index.ts'), 'utf8');
    expect(source).toContain('ExtensionMarketplace');
    expect(source).toContain('MyExtensions');
    expect(source).toContain('GovernanceDashboard');
    expect(source).toContain('ExtensionDetail');
    expect(source).toContain('BindingWizard');
    expect(source).toContain('TrustSignalBar');
    expect(source).toContain('GrammarInspector');
    expect(source).toContain('FieldMappingTable');
    expect(source).toContain('EntityDiagram');
    expect(source).toContain('Modal');
  });

  test('No raw JSON rendering of grammars in panel code', () => {
    const panelFiles = [
      'ExtensionMarketplace.tsx',
      'MyExtensions.tsx',
      'GovernanceDashboard.tsx',
      'ExtensionDetail.tsx',
      'BindingWizard.tsx',
      'GrammarInspector.tsx',
      'FieldMappingTable.tsx',
      'EntityDiagram.tsx',
    ];

    for (const file of panelFiles) {
      const source = readFileSync(join(ROOT, `packages/loom/src/panels/${file}`), 'utf8');
      // No JSON.stringify of grammar data
      expect(source).not.toContain('JSON.stringify');
    }
  });

  test('No plaintext credentials stored in component state', () => {
    const wizardSource = readFileSync(join(ROOT, 'apps/loom-react/src/panels/BindingWizard.tsx'), 'utf8');
    // Credentials are encrypted before being stored in binding
    expect(wizardSource).toContain('encryptCredentials');
    // Plaintext cleared after encryption
    expect(wizardSource).toContain('setCredentialValues({})');
    // No plaintext credential variable names
    expect(wizardSource).not.toContain('credentialPlaintext');
    expect(wizardSource).not.toMatch(/password\s*=\s*["']/);
  });

  test('Binding creation calls constraint enforcement', () => {
    const source = readFileSync(join(ROOT, 'apps/loom-react/src/panels/BindingWizard.tsx'), 'utf8');
    // L0 constraints checked
    expect(source).toContain('enforceL0Constraints');
    // L1 constraints checked
    expect(source).toContain('enforceL1Constraints');
    // Version compatibility checked
    expect(source).toContain('checkCompatibility');
    // Violations block progress
    expect(source).toContain('!l0Result.valid');
    expect(source).toContain('!l1Result.valid');
    expect(source).toContain('!result.compatible');
  });
});

// ── Constraint Integration Tests ────────────────────────────────

describe('Constraint Integration', () => {
  test('Binding with valid grammar passes L0 + L1 constraints', () => {
    const manifest = makeManifest();
    const policy = makePolicy();
    const binding = makeBinding();

    const l0 = enforceL0Constraints(manifest, policy);
    expect(l0.valid).toBe(true);
    expect(l0.violations).toHaveLength(0);

    const l1 = enforceL1Constraints(binding, manifest);
    expect(l1.valid).toBe(true);
    expect(l1.violations).toHaveLength(0);
  });

  test('Binding with incompatible version pin fails L1 constraints', () => {
    const manifest = makeManifest();
    const binding = makeBinding({ grammarVersionPinned: '^2.0.0' });

    const l1 = enforceL1Constraints(binding, manifest);
    expect(l1.valid).toBe(false);
    expect(l1.violations.length).toBeGreaterThan(0);
    expect(l1.violations[0].rule).toBe('version-pin-incompatible');
  });

  test('checkCompatibility returns green for compatible binding', () => {
    const manifest = makeManifest();
    const binding = makeBinding();

    const result = checkCompatibility(binding, manifest);
    expect(result.compatible).toBe(true);
    expect(result.status).toBe('green');
  });

  test('checkCompatibility returns red for deprecated manifest', () => {
    const manifest = makeManifest({
      deprecationStatus: {
        isDeprecated: true,
        deprecatedDate: '2026-01-01',
        sunsetDate: '2026-06-01',
      },
    });
    const binding = makeBinding();

    const result = checkCompatibility(binding, manifest);
    expect(result.status).toBe('red');
  });
});

```
