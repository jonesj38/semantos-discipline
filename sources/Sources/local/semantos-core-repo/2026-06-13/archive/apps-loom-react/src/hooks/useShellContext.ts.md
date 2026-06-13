---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/hooks/useShellContext.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.962582+00:00
---

# archive/apps-loom-react/src/hooks/useShellContext.ts

```ts
/**
 * useShellContext — builds a ShellContext from browser-side loom services.
 *
 * This bridges the Helm UI to the shell pipeline. All UI actions that need
 * to go through the shell's route() function use this context.
 *
 * The context is constructed once and memoized. PlexusService runs in stub
 * mode in the browser (all capability checks pass). For production, switch
 * to 'local' or 'cloud' mode.
 */

import { useMemo, useRef, useEffect, useState } from 'react';
import {
  loomStore, identityStore, configStore, settingsStore, plexusService,
  FlowRunner,
} from '../services/index';
import type { ShellContext } from '@semantos/shell';
import { createAdapter } from '@semantos/protocol-types';
import type { StorageAdapter } from '@semantos/protocol-types';

export function useShellContext(): ShellContext | null {
  const [adapter, setAdapter] = useState<StorageAdapter | null>(null);
  const initRef = useRef(false);
  const flowRunnerRef = useRef(new FlowRunner());

  useEffect(() => {
    if (initRef.current) return;
    initRef.current = true;
    createAdapter().then(a => setAdapter(a));
  }, []);

  return useMemo(() => {
    if (!adapter) return null;

    const hat = identityStore.getActiveHat();

    return {
      store: loomStore,
      flowRunner: flowRunnerRef.current,
      identity: identityStore,
      config: configStore,
      settings: settingsStore,
      plexus: plexusService,
      adapter,
      activeExtension: configStore.getSnapshot().activeExtensionId || 'core',
      activeHatId: hat?.id ?? null,
      activeHatCertId: hat?.certId ?? null,
      defaultFormat: 'json' as const,
    };
  }, [adapter]);
}

```
