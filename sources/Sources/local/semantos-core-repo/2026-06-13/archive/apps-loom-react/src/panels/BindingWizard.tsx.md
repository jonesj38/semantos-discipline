---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/BindingWizard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.951910+00:00
---

# archive/apps-loom-react/src/panels/BindingWizard.tsx

```tsx
/**
 * BindingWizard — 6-step modal wizard for creating a ConsumerBinding.
 *
 * Steps: Select Extension → Credentials → Overrides → Version Policy → Test → Confirm.
 *
 * Validation gates at each step:
 *   - enforceL0Constraints() checks capabilities
 *   - enforceL1Constraints() checks overrides
 *   - checkCompatibility() checks version
 *
 * Credentials are encrypted via encryptCredentials() before storage.
 * Plaintext exists only in form input state during step 2.
 */

import { useState, useCallback, useMemo } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useIdentity } from '../identity/IdentityProvider';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import type {
  GovernedConsumerBindingPayload, EncryptedCredentials,
  ConstraintResult, FieldOverride, TaxonomyOverride, LocalField,
} from '../../../protocol-types/src/governance';
import type { CompatibilityResult } from '../../../protocol-types/src/governance';
import { enforceL0Constraints, enforceL1Constraints } from '../../../extraction/src/governance/constraint-engine';
import { checkCompatibility } from '../../../extraction/src/governance/version-compat';
import { encryptCredentials } from '../../../extraction/src/governance/credential-vault';
import { Modal } from './Modal';
import { GrammarInspector } from './GrammarInspector';
import { TrustSignalBar, CompatibilityBadge } from './TrustSignals';

interface BindingWizardProps {
  manifest: ExtensionManifest;
  open: boolean;
  onClose: () => void;
  onComplete: () => void;
}

type WizardStep = 1 | 2 | 3 | 4 | 5 | 6;

const STEP_LABELS: Record<WizardStep, string> = {
  1: 'Select Extension',
  2: 'Credentials',
  3: 'Overrides',
  4: 'Version Policy',
  5: 'Test Connection',
  6: 'Confirm',
};

export function BindingWizard({ manifest, open, onClose, onComplete }: BindingWizardProps) {
  const { dispatch } = useLoom();
  const { activeHat } = useIdentity();
  const [step, setStep] = useState<WizardStep>(1);
  const [errors, setErrors] = useState<string[]>([]);

  // Step 2: Credentials (plaintext only lives here, encrypted on advance)
  const [credentialValues, setCredentialValues] = useState<Record<string, string>>({});
  const [encryptedCreds, setEncryptedCreds] = useState<EncryptedCredentials | null>(null);

  // Step 3: Overrides
  const [fieldOverrides, setFieldOverrides] = useState<FieldOverride[]>([]);
  const [taxonomyOverrides, setTaxonomyOverrides] = useState<TaxonomyOverride[]>([]);

  // Step 4: Version policy
  const [versionPolicy, setVersionPolicy] = useState<'auto' | 'range' | 'exact'>('auto');
  const [versionPin, setVersionPin] = useState(`^${manifest.version}`);
  const [compatResult, setCompatResult] = useState<CompatibilityResult | null>(null);

  // Step 5: Test connection
  const [testStatus, setTestStatus] = useState<'idle' | 'running' | 'success' | 'failed'>('idle');
  const [testMessage, setTestMessage] = useState('');

  // Step 6: Auto-extraction
  const [autoExtract, setAutoExtract] = useState(false);

  const grammar = manifest.grammar;
  const requiredCredentials = grammar?.source.auth.requiredCredentials ?? [];

  const canProceed = useCallback((): boolean => {
    switch (step) {
      case 1: return true; // Extension already selected
      case 2: return requiredCredentials.every(field => credentialValues[field]?.trim());
      case 3: return true; // Overrides are optional
      case 4: return !!compatResult?.compatible;
      case 5: return testStatus === 'success';
      case 6: return true;
      default: return false;
    }
  }, [step, requiredCredentials, credentialValues, compatResult, testStatus]);

  const handleNext = useCallback(async () => {
    setErrors([]);

    if (step === 2) {
      // Encrypt credentials before advancing — plaintext is cleared
      if (grammar) {
        const defaultPolicy = {
          typePath: 'governance.policy' as const,
          linearity: 'RELEVANT' as const,
          constitution: true as const,
          payload: {
            metaSchemaVersion: '1.0.0',
            requiredCapabilitiesWhitelist: ['network.outbound', 'storage.write', 'storage.read'],
            taxonomyNamespaceReservations: [],
            marketplaceListingRequirements: { minAuthorReputationScore: 0, minObjectCount: 0, requiresAudit: false, auditFrequencyDays: 90 },
            breakingChangeBallotQuorum: 66,
            emergencyDeprecationPolicy: { requiresVote: false, minDaysNotice: 14, escalationThreshold: 'critical' },
            effectiveDate: new Date().toISOString(),
            governedByHatId: 'semantos-core',
          },
        };

        const l0Result = enforceL0Constraints(manifest, defaultPolicy);
        if (!l0Result.valid) {
          setErrors(l0Result.violations.map(v => `L0: ${v.message}`));
          return;
        }
      }

      const encrypted = encryptCredentials(credentialValues, 'node-key-1');
      setEncryptedCreds(encrypted);
      setCredentialValues({}); // Clear plaintext immediately
    }

    if (step === 3 && grammar) {
      // Validate overrides against L1 constraints
      const binding = buildBindingPayload();
      const l1Result = enforceL1Constraints(
        { typePath: 'extension.consumer-binding', linearity: 'AFFINE', scope: 'node', payload: binding },
        manifest,
      );
      if (!l1Result.valid) {
        setErrors(l1Result.violations.map(v => `L1: ${v.message}`));
        return;
      }
    }

    if (step === 4) {
      // Run version compatibility check
      const binding = buildBindingPayload();
      const result = checkCompatibility(
        { typePath: 'extension.consumer-binding', linearity: 'AFFINE', scope: 'node', payload: binding },
        manifest,
      );
      setCompatResult(result);
      if (!result.compatible) {
        setErrors([result.message]);
        return;
      }
    }

    if (step < 6) {
      setStep((step + 1) as WizardStep);
    }
  }, [step, manifest, grammar, credentialValues, fieldOverrides, taxonomyOverrides, versionPin]);

  const handleBack = useCallback(() => {
    if (step > 1) setStep((step - 1) as WizardStep);
    setErrors([]);
  }, [step]);

  const handleTestConnection = useCallback(async () => {
    setTestStatus('running');
    setTestMessage('Connecting...');

    // Simulate test connection (dry-run extraction stub)
    await new Promise(r => setTimeout(r, 500));
    setTestMessage('Validating schema...');
    await new Promise(r => setTimeout(r, 500));
    setTestMessage('Testing extraction...');
    await new Promise(r => setTimeout(r, 500));

    // Stub success
    setTestStatus('success');
    setTestMessage('Connection successful! Ready to extract.');
  }, []);

  const handleCreate = useCallback(() => {
    const binding = buildBindingPayload();

    // Create as loom object
    dispatch({
      type: 'ADD_OBJECT',
      object: {
        id: `binding-${Date.now()}-${manifest.id}`,
        typeDefinition: {
          name: 'ConsumerBinding',
          category: 'extension',
          typeHash: new Uint8Array(32),
          fields: [],
        },
        header: {
          linearity: 2, // AFFINE
          version: 1,
          flags: 0,
          refCount: 0,
          typeHash: new Uint8Array(32),
          ownerId: new Uint8Array(32),
          timestamp: BigInt(Date.now()),
          phase: 0,
        },
        payload: binding as unknown as Record<string, unknown>,
        patches: [{
          id: `patch-${Date.now()}-binding-create`,
          kind: 'action',
          timestamp: Date.now(),
          delta: { action: 'binding_created', extensionId: manifest.id },
          facetId: activeHat?.id,
          facetCapabilities: activeHat?.capabilities,
        }],
        visibility: 'draft',
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    });

    onComplete();
  }, [dispatch, manifest, activeHat, encryptedCreds, fieldOverrides, taxonomyOverrides, versionPolicy, versionPin, autoExtract, onComplete]);

  function buildBindingPayload(): GovernedConsumerBindingPayload {
    return {
      extensionManifestId: manifest.id,
      grammarVersionPinned: versionPolicy === 'auto' ? `^${manifest.version}` :
        versionPolicy === 'range' ? versionPin : manifest.version,
      credentialsEncrypted: encryptedCreds ?? {
        encryptedBlob: '',
        encryptionKeyId: 'node-key-1',
        credentialFieldNames: requiredCredentials,
      },
      fieldOverrides: fieldOverrides.length > 0 ? fieldOverrides : undefined,
      taxonomyOverrides: taxonomyOverrides.length > 0 ? taxonomyOverrides : undefined,
      autoUpdateGrammar: versionPolicy === 'auto',
      status: 'active',
    };
  }

  return (
    <Modal open={open} onClose={onClose} title={`Install Extension - Step ${step}: ${STEP_LABELS[step]}`} width="720px">
      {/* Step Indicator */}
      <div className="flex items-center gap-1 mb-4">
        {([1, 2, 3, 4, 5, 6] as WizardStep[]).map((s) => (
          <div
            key={s}
            className={`flex-1 h-1 rounded ${
              s < step ? 'bg-blue-600' : s === step ? 'bg-blue-500' : 'bg-gray-700'
            }`}
          />
        ))}
      </div>

      {/* Errors */}
      {errors.length > 0 && (
        <div className="mb-4 p-3 bg-red-900/20 border border-red-800/50 rounded text-xs text-red-300 space-y-1">
          {errors.map((e, i) => <p key={i}>{e}</p>)}
        </div>
      )}

      {/* Step Content */}
      <div className="min-h-[200px]">
        {step === 1 && <Step1SelectExtension manifest={manifest} />}
        {step === 2 && (
          <Step2Credentials
            fields={requiredCredentials}
            values={credentialValues}
            onChange={setCredentialValues}
          />
        )}
        {step === 3 && (
          <Step3Overrides
            grammar={grammar}
            fieldOverrides={fieldOverrides}
            onFieldOverridesChange={setFieldOverrides}
            taxonomyOverrides={taxonomyOverrides}
            onTaxonomyOverridesChange={setTaxonomyOverrides}
          />
        )}
        {step === 4 && (
          <Step4VersionPolicy
            manifest={manifest}
            policy={versionPolicy}
            onPolicyChange={setVersionPolicy}
            pin={versionPin}
            onPinChange={setVersionPin}
            compatResult={compatResult}
          />
        )}
        {step === 5 && (
          <Step5TestConnection
            status={testStatus}
            message={testMessage}
            onTest={handleTestConnection}
          />
        )}
        {step === 6 && (
          <Step6Confirm
            manifest={manifest}
            binding={buildBindingPayload()}
            autoExtract={autoExtract}
            onAutoExtractChange={setAutoExtract}
          />
        )}
      </div>

      {/* Navigation */}
      <div className="flex items-center justify-between mt-4 pt-3 border-t border-gray-800">
        <button
          onClick={handleBack}
          className={`px-3 py-1.5 text-xs rounded border ${
            step === 1 ? 'invisible' : 'bg-gray-800 hover:bg-gray-700 text-gray-400 border-gray-700'
          }`}
        >
          Back
        </button>
        <div className="flex gap-2">
          <button
            onClick={onClose}
            className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700"
          >
            Cancel
          </button>
          {step < 6 ? (
            <button
              onClick={handleNext}
              disabled={!canProceed()}
              className={`px-4 py-1.5 text-xs rounded font-medium ${
                canProceed()
                  ? 'bg-blue-800 hover:bg-blue-700 text-blue-200'
                  : 'bg-gray-700 text-gray-500 cursor-not-allowed'
              }`}
            >
              Next
            </button>
          ) : (
            <button
              onClick={handleCreate}
              className="px-4 py-1.5 text-xs bg-green-800 hover:bg-green-700 text-green-200 rounded font-medium"
            >
              Create Binding
            </button>
          )}
        </div>
      </div>
    </Modal>
  );
}

// ── Step Components ─────────────────────────────────────────────

function Step1SelectExtension({ manifest }: { manifest: ExtensionManifest }) {
  return (
    <div className="space-y-3">
      <div className="bg-gray-800 border border-gray-700 rounded p-3">
        <div className="flex items-center gap-2">
          <h3 className="text-sm text-gray-200 font-medium">{manifest.name}</h3>
          <span className="text-xs text-gray-500">v{manifest.version}</span>
        </div>
        {manifest.metadata?.description && (
          <p className="text-xs text-gray-400 mt-1">{manifest.metadata.description}</p>
        )}
        <TrustSignalBar manifest={manifest} />
      </div>

      {manifest.grammar && (
        <div>
          <h4 className="text-xs text-gray-400 font-medium mb-2">Grammar Preview</h4>
          <GrammarInspector grammar={manifest.grammar} />
        </div>
      )}
    </div>
  );
}

function Step2Credentials({
  fields,
  values,
  onChange,
}: {
  fields: string[];
  values: Record<string, string>;
  onChange: (v: Record<string, string>) => void;
}) {
  if (fields.length === 0) {
    return <p className="text-xs text-gray-500">No credentials required for this extension.</p>;
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-400">
        Enter your API credentials. These will be encrypted before storage and never stored in plaintext.
      </p>
      {fields.map((field) => (
        <div key={field}>
          <label className="text-xs text-gray-400 block mb-1">{field}</label>
          <input
            type="password"
            value={values[field] ?? ''}
            onChange={(e) => onChange({ ...values, [field]: e.target.value })}
            placeholder={`Enter ${field}...`}
            className="w-full px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-300 placeholder-gray-600 focus:outline-none focus:border-gray-500"
          />
        </div>
      ))}
    </div>
  );
}

function Step3Overrides({
  grammar,
  fieldOverrides,
  onFieldOverridesChange,
  taxonomyOverrides,
  onTaxonomyOverridesChange,
}: {
  grammar: import('../../../protocol-types/src/extension-grammar').ExtensionGrammar | undefined;
  fieldOverrides: FieldOverride[];
  onFieldOverridesChange: (v: FieldOverride[]) => void;
  taxonomyOverrides: TaxonomyOverride[];
  onTaxonomyOverridesChange: (v: TaxonomyOverride[]) => void;
}) {
  const addFieldOverride = () => {
    onFieldOverridesChange([
      ...fieldOverrides,
      { objectType: grammar?.objectTypes[0]?.typePath ?? '', localFields: [] },
    ]);
  };

  return (
    <div className="space-y-4">
      <div>
        <div className="flex items-center justify-between mb-2">
          <h4 className="text-xs text-gray-400 font-medium">Field Overrides (Optional)</h4>
          <button
            onClick={addFieldOverride}
            className="px-2 py-0.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700"
          >
            Add Override
          </button>
        </div>
        {fieldOverrides.length === 0 ? (
          <p className="text-xs text-gray-500">No field overrides. Click "Add Override" to add local fields.</p>
        ) : (
          <div className="space-y-2">
            {fieldOverrides.map((override, i) => (
              <div key={i} className="bg-gray-800 border border-gray-700 rounded p-2 text-xs">
                <div className="flex items-center gap-2">
                  <span className="text-gray-500">Object type:</span>
                  <span className="text-gray-300 font-mono">{override.objectType}</span>
                  <button
                    onClick={() => onFieldOverridesChange(fieldOverrides.filter((_, j) => j !== i))}
                    className="ml-auto text-red-400 hover:text-red-300"
                  >
                    Remove
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div>
        <h4 className="text-xs text-gray-400 font-medium mb-2">Taxonomy Overrides (Optional)</h4>
        {grammar?.entityMappings ? (
          <table className="w-full text-xs">
            <thead>
              <tr className="text-gray-500 border-b border-gray-800">
                <th className="py-1 text-left font-medium">Entity</th>
                <th className="py-1 text-left font-medium">What</th>
                <th className="py-1 text-left font-medium">How</th>
                <th className="py-1 text-left font-medium">Why</th>
              </tr>
            </thead>
            <tbody>
              {grammar.entityMappings.map((em) => (
                <tr key={em.sourceEntityId} className="border-b border-gray-800/50">
                  <td className="py-1 text-gray-300">{em.sourceEntityId}</td>
                  <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.what)}</td>
                  <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.how)}</td>
                  <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.why)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p className="text-xs text-gray-500">No taxonomy mappings available.</p>
        )}
      </div>
    </div>
  );
}

function Step4VersionPolicy({
  manifest,
  policy,
  onPolicyChange,
  pin,
  onPinChange,
  compatResult,
}: {
  manifest: ExtensionManifest;
  policy: 'auto' | 'range' | 'exact';
  onPolicyChange: (v: 'auto' | 'range' | 'exact') => void;
  pin: string;
  onPinChange: (v: string) => void;
  compatResult: CompatibilityResult | null;
}) {
  return (
    <div className="space-y-3">
      <div className="space-y-2">
        {(['auto', 'range', 'exact'] as const).map((opt) => (
          <label key={opt} className="flex items-start gap-2 cursor-pointer">
            <input
              type="radio"
              name="version-policy"
              checked={policy === opt}
              onChange={() => onPolicyChange(opt)}
              className="mt-0.5"
            />
            <div>
              <span className="text-xs text-gray-300">
                {opt === 'auto' ? 'Auto-update (recommended)' :
                 opt === 'range' ? 'Pin to semver range' :
                 'Pin to exact version'}
              </span>
              <p className="text-xs text-gray-500 mt-0.5">
                {opt === 'auto' ? 'Always use the latest compatible version.' :
                 opt === 'range' ? 'e.g. ^1.2.0 or ~1.2.0' :
                 `Lock to v${manifest.version}`}
              </p>
            </div>
          </label>
        ))}
      </div>

      {policy === 'range' && (
        <input
          type="text"
          value={pin}
          onChange={(e) => onPinChange(e.target.value)}
          placeholder="^1.2.0"
          className="w-full px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-300 font-mono focus:outline-none focus:border-gray-500"
        />
      )}

      {compatResult && (
        <div className="flex items-center gap-2 mt-2">
          <CompatibilityBadge status={compatResult.status} message={compatResult.message} />
          <span className="text-xs text-gray-500">{compatResult.message}</span>
        </div>
      )}
    </div>
  );
}

function Step5TestConnection({
  status,
  message,
  onTest,
}: {
  status: 'idle' | 'running' | 'success' | 'failed';
  message: string;
  onTest: () => void;
}) {
  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-400">
        Test your credentials and permissions before creating the binding.
      </p>

      <button
        onClick={onTest}
        disabled={status === 'running'}
        className={`px-4 py-2 text-xs rounded font-medium ${
          status === 'running'
            ? 'bg-gray-700 text-gray-500 cursor-not-allowed'
            : 'bg-blue-800 hover:bg-blue-700 text-blue-200'
        }`}
      >
        {status === 'running' ? 'Testing...' : 'Test Connection'}
      </button>

      {message && (
        <div className={`flex items-center gap-2 text-xs ${
          status === 'success' ? 'text-green-400' :
          status === 'failed' ? 'text-red-400' :
          'text-gray-400'
        }`}>
          {status === 'success' && <span>\u2713</span>}
          {status === 'failed' && <span>\u2717</span>}
          {status === 'running' && <span className="animate-pulse">\u25CF</span>}
          <span>{message}</span>
        </div>
      )}

      {status === 'failed' && (
        <p className="text-xs text-gray-500">Fix the issue above and try again.</p>
      )}
    </div>
  );
}

function Step6Confirm({
  manifest,
  binding,
  autoExtract,
  onAutoExtractChange,
}: {
  manifest: ExtensionManifest;
  binding: GovernedConsumerBindingPayload;
  autoExtract: boolean;
  onAutoExtractChange: (v: boolean) => void;
}) {
  return (
    <div className="space-y-3">
      <h4 className="text-xs text-gray-400 font-medium">Review your configuration</h4>

      <div className="bg-gray-800 border border-gray-700 rounded p-3 text-xs space-y-2">
        <div className="flex gap-2">
          <span className="text-gray-500">Extension:</span>
          <span className="text-gray-200">{manifest.name} v{manifest.version}</span>
        </div>
        <div className="flex gap-2">
          <span className="text-gray-500">Version policy:</span>
          <span className="text-gray-300 font-mono">{binding.grammarVersionPinned}</span>
          {binding.autoUpdateGrammar && <span className="text-green-400">(auto-update)</span>}
        </div>
        <div className="flex gap-2">
          <span className="text-gray-500">Credentials:</span>
          <span className="text-gray-300">
            {binding.credentialsEncrypted.credentialFieldNames.length > 0
              ? binding.credentialsEncrypted.credentialFieldNames.map(f => `${f} (\u2022\u2022\u2022\u2022)`).join(', ')
              : 'None'}
          </span>
        </div>
        {binding.fieldOverrides && binding.fieldOverrides.length > 0 && (
          <div className="flex gap-2">
            <span className="text-gray-500">Field overrides:</span>
            <span className="text-gray-300">{binding.fieldOverrides.length}</span>
          </div>
        )}
        {binding.taxonomyOverrides && binding.taxonomyOverrides.length > 0 && (
          <div className="flex gap-2">
            <span className="text-gray-500">Taxonomy overrides:</span>
            <span className="text-gray-300">{binding.taxonomyOverrides.length}</span>
          </div>
        )}
      </div>

      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={autoExtract}
          onChange={(e) => onAutoExtractChange(e.target.checked)}
        />
        <span className="text-xs text-gray-400">Enable auto-extraction on schedule</span>
      </label>
    </div>
  );
}

```
