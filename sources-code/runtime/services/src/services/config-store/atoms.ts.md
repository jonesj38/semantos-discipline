---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.114794+00:00
---

# runtime/services/src/services/config-store/atoms.ts

```ts
/**
 * State atoms for the ConfigStore split. The facade reads/writes
 * these instead of holding instance fields, so tests can subscribe to
 * snapshots and inspect intermediate state.
 *
 * NOTE: these are module-level singletons — there is one ConfigStore
 * per process today; if multiple are ever needed, callers can
 * construct atoms locally and pass them through the facade.
 */

import { atom, type Atom } from '@semantos/state';

import type {
  ConfigOverlay,
  ExtensionConfig,
} from '../../config/extensionConfig';

export interface SeedNode {
  path: string;
  name: string;
  axis: 'what' | 'how' | 'why';
  metadata?: Record<string, unknown>;
  children?: SeedNode[];
}

export interface SeedAxis {
  name: string;
  rootPath: string;
  nodes: SeedNode[];
}

export const DEFAULT_EXTENSION = 'trades-services';

export const configAtom: Atom<ExtensionConfig | null> = atom<ExtensionConfig | null>(null);
export const coreConfigAtom: Atom<ExtensionConfig | null> = atom<ExtensionConfig | null>(null);
export const activeExtensionIdAtom: Atom<string> = atom<string>(DEFAULT_EXTENSION);
export const overlaysAtom: Atom<ConfigOverlay[]> = atom<ConfigOverlay[]>([]);
export const taxonomySeedAtom: Atom<Record<string, SeedAxis> | null> = atom<
  Record<string, SeedAxis> | null
>(null);
export const coreTaxonomyLoadedAtom: Atom<boolean> = atom<boolean>(false);
export const activeIntentTaxonomyExtensionAtom: Atom<string | null> = atom<string | null>(null);
export const loadingAtom: Atom<boolean> = atom<boolean>(false);
export const errorAtom: Atom<string | null> = atom<string | null>(null);

```
