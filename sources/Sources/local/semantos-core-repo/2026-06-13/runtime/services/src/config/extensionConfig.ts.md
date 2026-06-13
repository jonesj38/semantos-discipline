---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/config/extensionConfig.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.089338+00:00
---

# runtime/services/src/config/extensionConfig.ts

```ts
/**
 * Extension configuration — re-exports from @semantos/protocol-types.
 *
 * These types were moved to protocol-types to break circular cross-package
 * dependencies. This file re-exports everything so existing loom code
 * continues to work without changes.
 */

export {
  type ExtensionConfig,
  type Archetype,
  type VisibilityConfig,
  type AccessPolicy,
  type ObjectTypeDefinition,
  type PolicyBinding,
  type LinearityTransition,
  type CapabilityDefinition,
  type ScriptTemplate,
  type FieldDefinition,
  type TaxonomyTree,
  type TaxonomyDimensionDef,
  type TaxonomyNode,
  type ConfigOverlay,
  type PolicyDefinition,
  type ThemeOverride,
  type ConversationFlow,
  type FlowStep,
  type FlowAction,
  validateExtensionConfig,
} from '@semantos/protocol-types';

```
