---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/LoomApp.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.932253+00:00
---

# archive/apps-loom-react/src/LoomApp.tsx

```tsx
/**
 * LoomApp — Semantos Helm: attention-driven object surface.
 *
 * Provider stack:
 *   EngineProvider → ExtensionProvider → IdentityProvider → KernelProvider → Helm
 *
 * Attention Surface (anchor) → Active Modes (Do/Talk/Find) → Support Surfaces
 */

import { useState } from 'react';
import { EngineProvider } from './engine/EngineProvider';
import { ExtensionProvider } from './config/ExtensionProvider';
import { IdentityProvider, useIdentity } from './identity/IdentityProvider';
import { KernelProvider } from './contexts/KernelProvider';
import { LoomProvider } from './state/LoomProvider';
import { IdentitySetup } from './identity/IdentitySetup';
import { Helm } from './helm/Helm';

/** Gate: show identity setup if not dismissed, otherwise show the Helm. */
function AppContent() {
  const { isSetupComplete } = useIdentity();
  const [setupDismissed, setSetupDismissed] = useState(() => isSetupComplete);

  if (!setupDismissed) {
    return <IdentitySetup onComplete={() => setSetupDismissed(true)} />;
  }

  return (
    <KernelProvider>
      <LoomProvider>
        <Helm />
      </LoomProvider>
    </KernelProvider>
  );
}

export default function LoomApp() {
  return (
    <EngineProvider>
      <ExtensionProvider>
        <IdentityProvider>
          <AppContent />
        </IdentityProvider>
      </ExtensionProvider>
    </EngineProvider>
  );
}

```
