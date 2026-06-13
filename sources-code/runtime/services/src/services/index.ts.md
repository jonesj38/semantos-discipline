---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.092677+00:00
---

# runtime/services/src/services/index.ts

```ts
/**
 * Service layer singletons — renderer-agnostic stores and services.
 *
 * Import these directly in plain TypeScript (tests, CLI, game engine).
 * React providers wrap these via useSyncExternalStore.
 */

// ── Loom types (re-exported for external packages) ──
export type { LoomObject, ObjectPatch, LoomCard, CardConnection, LoomState, Identity, Hat, TypeCoordinate, ReputationScore, AttentionItem, AttentionReason } from '../types/loom';

export { TypedEventEmitter } from './TypedEventEmitter';
export { LoomStore } from './LoomStore';
export { IdentityStore } from './IdentityStore';
export type { HatCertSnapshot } from './IdentityStore';
export { ConfigStore } from './ConfigStore';
export { SettingsStore } from './SettingsStore';
export { FlowRunner } from './FlowRunner';
export type { FlowRunState } from './FlowRunner';
export { findFlow, listFlows, loadCoreTaxonomy, registerTaxonomy, unregisterTaxonomy, getTaxonomyAt, getFastPathIntents } from './FlowRegistry';
export { classifyIntent, buildContextFromConfig, setSettingsStoreRef } from './IntentClassifier';
export { IntentTaxonomy, intentTaxonomy } from './IntentTaxonomy';
export type { IntentTaxonomyNode, TaxonomyConfig, TaxonomyInjection, FastPathEntry } from './IntentTaxonomy';
export type { IntentClassification, ClassificationContext, ClassificationResult } from './intent-types';
export { UNKNOWN_INTENT, UNKNOWN_CLASSIFICATION } from './intent-types';
export { computeReputation, DEFAULT_REPUTATION_WEIGHTS } from './ReputationComputer';
export { computeTaxonomyWeights } from './TaxonomyWeightComputer';
export type { TaxonomyWeight } from './TaxonomyWeightComputer';
export { cosineSimilarity, cosineDistance } from './cosine';
export { treeDistance, lowestCommonAncestor } from './tree-distance';
export { EmbeddingService, embeddingService, collectTaxonomyNodes, computeContentHash } from './EmbeddingService';
export { TaxonomyCoherence, taxonomyCoherence } from './TaxonomyCoherence';
export type { CoherenceReport, Misalignment, CoherenceSuggestion } from './TaxonomyCoherence';
export { PlexusService, initializePlexusService, getPlexusService } from '../plexus/PlexusService';
export { AttentionEngine } from './AttentionEngine';
export type { AttentionSnapshot, AttentionEngineDeps } from './AttentionEngine';
export {
  AttentionTelemetry,
  attentionTelemetry,
} from './AttentionTelemetry';
export type {
  AttentionInteraction,
  AttentionInteractionRecord,
  AttentionTelemetryQueryOpts,
  AttentionContextTag,
  HatIdProvider,
  ContextTagProvider,
} from './AttentionTelemetry';
export {
  AttentionWeightLearner,
  attentionWeightLearner,
  BASELINE_WEIGHTS,
} from './AttentionWeightLearner';
export type {
  AttentionWeights,
  AttentionFactor,
  AttentionWeightProfile,
  AttentionWeightSnapshot,
} from './AttentionWeightLearner';
export {
  AttentionRules,
  attentionRules,
  compilePattern,
} from './AttentionRules';
export type {
  AttentionPinRule,
  AttentionMustShowRule,
  AttentionSuppressRule,
  AttentionClassBoostRule,
  AttentionRuleSet,
  AttentionRuleHistoryEntry,
} from './AttentionRules';
export {
  AttentionSignalRegistry,
  attentionSignals,
} from './AttentionSignals';
export type {
  AttentionSignal,
  AttentionSignalSource,
  AttentionSignalRegistryConfig,
} from './AttentionSignals';
export { createWeatherSource } from './signals/weather';
export type { WeatherForecast, WeatherProvider, WeatherSourceOptions } from './signals/weather';
export { createSurflineSource } from './signals/surfline';
export type { SurfForecast, SurflineProvider, SurflineSourceOptions } from './signals/surfline';
export { createLegacyIngestSource } from './signals/legacy-ingest';
export type {
  LegacyIngestProvider,
  LegacyIngestProposal,
  LegacyIngestSubscription,
  LegacyIngestSourceOptions,
} from './signals/legacy-ingest';
export { createCapabilitySource } from './signals/capability';
export type {
  CapabilityState,
  CapabilityProvider,
  CapabilitySourceOptions,
} from './signals/capability';
export { AttentionDelivery } from './AttentionDelivery';
export type {
  DeliveryChannel,
  PushTransport,
  SmsTransport,
  VoiceTransport,
  QuietHours,
  AttentionDeliveryOptions,
} from './AttentionDelivery';
export { routeAttention } from './attention-verb';
export { PaskGraph, paskGraph } from './PaskGraph';
export type { PaskStableThread, PaskInteractArgs } from './PaskGraph';
export { loadPaskSnapshot, savePaskSnapshot, clearPaskSnapshot } from './PaskSnapshot';
export {
  IntentLauncher, intentLauncher,
  ALL_SLOTS, SLOT_MODE, SLOT_LABEL,
  setLaunchDeps, getLaunchDeps,
} from './IntentLauncher';
export type { IntentContext, LauncherItem, LauncherResult, LauncherDeps } from './IntentLauncher';
export { routeLaunch } from './launch-verb';

import { LoomStore } from './LoomStore';
import { loomStateAtom } from './loom/loom-atoms';

// Re-export the loom atoms surface so consumers can pull it from the
// package root rather than the deep path. Prompt-03 wiring.
export {
  loomStateAtom,
  dispatch as loomDispatch,
  selectedObjectAtom,
  patchQueueAtom,
  objectsByHatAtom,
  channelsByStatusAtom,
  freshInitialState,
  type LoomState as LoomAtomState,
  type LoomAction as LoomAtomAction,
} from './loom/loom-atoms';
export { attachPatchRecorder } from './loom/effects/patch-recorder';
import { IdentityStore } from './IdentityStore';
import { ConfigStore } from './ConfigStore';
import { SettingsStore } from './SettingsStore';
import { setSettingsStoreRef } from './IntentClassifier';
import { initializePlexusService } from '../plexus/PlexusService';
import { embeddingService } from './EmbeddingService';
import { taxonomyCoherence } from './TaxonomyCoherence';
import { intentTaxonomy } from './IntentTaxonomy';
import { collectTaxonomyNodes } from './EmbeddingService';
import { createAdapter } from '@semantos/protocol-types';
import type { StorageAdapter } from '@semantos/protocol-types';

/**
 * Singleton store instances.
 * Created without adapter initially (localStorage fallback).
 * Call initStorage() to inject a StorageAdapter and load persisted state.
 */
// loom-react / loom-svelte / panel consumers read & write through the
// singleton `loomStateAtom` exposed from `loom/loom-atoms.ts`. Shell
// sessions still construct their own `new LoomStore()` for isolation.
export const loomStore = new LoomStore({ stateAtom: loomStateAtom });
export const identityStore = new IdentityStore();
export const configStore = new ConfigStore();
export const settingsStore = new SettingsStore();
export const plexusService = initializePlexusService({ mode: 'stub' });

// Wire up the SettingsStore reference for IntentClassifier (avoids circular import)
setSettingsStoreRef(settingsStore);

// AS1: telemetry decorates each record with the active hat id.
// AS2: each telemetry record is piped into the weight learner so weights
// drift toward the operator's demonstrated preferences.
// AS3: rules history is signed under the active hat id.
import { attentionTelemetry } from './AttentionTelemetry';
import { attentionWeightLearner } from './AttentionWeightLearner';
import { attentionRules } from './AttentionRules';
import type { AttentionFactor } from './AttentionWeightLearner';
import { paskGraph } from './PaskGraph';
attentionTelemetry.setHatIdProvider(() => identityStore.getActiveHat()?.id ?? null);
attentionRules.setHatIdProvider(() => identityStore.getActiveHat()?.id ?? null);

// Register REPL verbs at module load. Idempotent guards for hot-reload.
import { routeAttention } from './attention-verb';
import { routeLaunch } from './launch-verb';
import { setLaunchDeps } from './IntentLauncher';
import { registerVerb, getVerb } from '../verb-registry';
if (!getVerb('attention')) {
  registerVerb('attention', routeAttention);
}
if (!getVerb('launch')) {
  registerVerb('launch', routeLaunch);
}
setLaunchDeps({ loomStore, paskGraph });

import type { AttentionInteraction } from './AttentionTelemetry';
attentionTelemetry.on('record', (rec) => {
  const factor = interactionToFactor(rec.interaction);
  if (factor) attentionWeightLearner.observe(rec, factor);
  paskGraph.observeTelemetry(rec);
});

function interactionToFactor(interaction: AttentionInteraction): AttentionFactor | null {
  switch (interaction.kind) {
    case 'tapped':         return reasonTypeToFactor(interaction.primaryReason);
    case 'push-opened':    return 'external_signal';
    case 'push-delivered': return 'external_signal';
    default:               return null;
  }
}

function reasonTypeToFactor(reasonType: string | null): AttentionFactor | null {
  if (!reasonType) return null;
  switch (reasonType) {
    case 'active_work':         return 'active_work';
    case 'deadline_approaching': return 'deadline';
    case 'goal_misalignment':   return 'goal_alignment';
    case 'pending_action':      return 'pending_action';
    case 'new_update':          return 'recency';
    case 'streak_continuation': return 'recency';
    case 'scheduled':           return 'deadline';
    case 'extension_signal':    return 'external_signal';
    case 'graph_proximity':     return 'graph_proximity';
    default:                    return null;
  }
}

// Wire up embedding service references
embeddingService.setApiKeyProvider(() => settingsStore.getSettings().openRouterApiKey);
embeddingService.setNodeProvider(() => collectTaxonomyNodes(intentTaxonomy.getDomains()));
taxonomyCoherence.setEmbeddingService(embeddingService);

/**
 * Initialize storage for the loom.
 * Creates the appropriate adapter for the current runtime (browser: OPFS/IDB, Node: fs)
 * and loads persisted state into all stores.
 * Call this early in app startup (e.g., in EngineProvider or main.tsx).
 */
export async function initStorage(adapter?: StorageAdapter): Promise<void> {
  const storage = adapter ?? await createAdapter();

  // Inject into stores (they already have localStorage data loaded;
  // adapter data takes precedence once initFromAdapter resolves)
  (identityStore as any)._adapter = storage;
  (configStore as any)._adapter = storage;
  (settingsStore as any)._adapter = storage;
  embeddingService.setStorageAdapter(storage);

  await Promise.all([
    identityStore.initFromAdapter(),
    configStore.initFromAdapter(),
    settingsStore.initFromAdapter(),
  ]);
}

```
