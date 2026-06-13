---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.364922+00:00
---

# runtime/shell/src/types.ts

```ts
/**
 * Internal types for the semantic shell.
 *
 * References service types from the loom package but never imports React.
 */

import type { LoomStore, FlowRunner, IdentityStore, ConfigStore, SettingsStore, PlexusService } from '@semantos/runtime-services';
import type { StorageAdapter, SemanticFS } from '@semantos/protocol-types';
import type { PipelineDeps } from '@semantos/intent';
import type { OutputFormat } from './formatters';
import type { ConversationStore } from './conversation-store';
import type { TransferService } from './transfer-service';

/**
 * Optional intent-pipeline wiring. Populated by the shell bootstrap
 * when the caller wants mutation verbs to route through
 * `@semantos/intent`'s processIntent behind the `INTENT_PIPELINE=1`
 * env flag (Slice 3b). When absent — or when the env flag is off —
 * verbs fall through to their existing direct handlers.
 */
export interface IntentPipelineWiring {
  deps: PipelineDeps;
  extension: { extensionId: string; domainFlag: number };
  /** Generates the Intent.id. */
  generateId: () => string;
}

/** Runtime context carrying shared service instances. */
export interface ShellContext {
  store: LoomStore;
  flowRunner: FlowRunner;
  identity: IdentityStore;
  config: ConfigStore;
  settings: SettingsStore;
  plexus: PlexusService;
  /** StorageAdapter for cell persistence (Phase 25B). */
  adapter?: StorageAdapter;
  /** SemanticFS for taxonomy-aware filesystem operations (Phase 25C). */
  semanticFs?: SemanticFS;
  activeExtension: string;
  activeHatId: string | null;
  activeHatCertId: string | null;
  defaultFormat: OutputFormat;
  /** Phase 2: Multi-thread conversation store. */
  conversationStore?: ConversationStore;
  /** Metered Content Transfer primitive — shell substrate any cartridge invokes
   *  (share/fetch/sync content over the paid, verified data plane). */
  transfer?: TransferService;
  /** Slice 3b: optional intent-pipeline wiring. Absent → direct-path dispatch. */
  intentPipeline?: IntentPipelineWiring;
}

/** Persisted shell configuration loaded from file + env vars. */
export interface ShellConfig {
  adapterMode: 'stub' | 'local' | 'cloud';
  activeHatId: string | null;
  activeHatCertId: string | null;
  defaultExtension: string;
  defaultFormat: OutputFormat;
  apiEndpoint?: string;
  plexusMode: 'stub' | 'real' | 'cloud';
  plexusEndpoint: string;
}

```
