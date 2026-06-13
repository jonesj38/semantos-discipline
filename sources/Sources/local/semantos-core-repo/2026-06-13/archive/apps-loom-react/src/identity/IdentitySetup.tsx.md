---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/identity/IdentitySetup.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.947794+00:00
---

# archive/apps-loom-react/src/identity/IdentitySetup.tsx

```tsx
import { useState } from 'react';
import { identityStore } from '../services/index';

/**
 * IdentitySetup — simplified onboarding. Just ask for a name.
 *
 * Creates the identity with a Developer hat (full caps) plus
 * Professional and Personal hats for sharing demos.
 * No multi-step wizard — just type and go.
 */

const DEFAULT_HATS = [
  {
    name: 'Professional',
    displayName: '',
    capabilities: [1, 2, 5, 9, 10],
    derivationPath: 'm/brc52/professional/0',
  },
  {
    name: 'Personal',
    displayName: '',
    capabilities: [4, 1],
    derivationPath: 'm/brc52/personal/0',
  },
];

export function IdentitySetup({ onComplete }: { onComplete: () => void }) {
  const [name, setName] = useState('');
  const [creating, setCreating] = useState(false);

  const handleCreate = async () => {
    if (!name.trim() || creating) return;
    setCreating(true);

    // Create identity (creates Developer hat automatically)
    await identityStore.createIdentity(name.trim());

    // Auto-create standard hats for demo — catch errors from Plexus cert derivation
    for (const hat of DEFAULT_HATS) {
      try {
        await identityStore.addHat(
          hat.name,
          hat.displayName || `${name.trim()} (${hat.name})`,
          hat.capabilities,
          hat.derivationPath,
        );
      } catch {
        // Plexus cert derivation fails in stub mode — inject directly
        injectHatIntoStore(hat.name, `${name.trim()} (${hat.name})`, hat.capabilities, hat.derivationPath);
      }
    }

    onComplete();
  };

  return (
    <div className="h-full flex items-center justify-center bg-gray-950">
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-8 max-w-md w-full space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-xl font-semibold text-gray-100">Welcome to Semantos</h1>
          <p className="text-sm text-gray-400">
            Your identity is a semantic object. Everything you create, share, and sign
            flows through it.
          </p>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-xs text-gray-400 mb-1">What should we call you?</label>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleCreate()}
              placeholder="Todd"
              className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm text-gray-100 focus:outline-none focus:border-blue-500"
              autoFocus
              disabled={creating}
            />
          </div>
          <button
            onClick={handleCreate}
            disabled={!name.trim() || creating}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-500 text-white text-sm rounded px-4 py-2 transition-colors"
          >
            {creating ? 'Setting up...' : 'Get Started'}
          </button>
          <p className="text-[10px] text-gray-600 text-center">
            Creates your identity with Developer, Professional, and Personal hats.
            You can add more later.
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * Fallback: inject a hat directly into the store's localStorage state
 * when Plexus cert derivation fails (stub mode).
 * Also poke the in-memory identity so React picks it up.
 *
 * Persistence-compat: the serialised shape uses the legacy key `facets`
 * (see SerializedIdentity). Writing `hats` here would orphan the entry
 * on re-hydrate, so we stay on the legacy key by design.
 */
function injectHatIntoStore(name: string, displayName: string, capabilities: number[], derivationPath: string): void {
  try {
    const key = 'workbench-identity';
    const stored = localStorage.getItem(key);
    if (!stored) return;
    const identity = JSON.parse(stored);
    if (identity.facets.some((f: { name: string }) => f.name === name)) return;
    const hat = {
      id: `hat-${name.toLowerCase()}-${Date.now()}`,
      name,
      displayName,
      capabilities,
      derivationPath,
      createdAt: Date.now(),
    };
    identity.facets.push(hat);
    localStorage.setItem(key, JSON.stringify(identity));

    // Also update the in-memory store so React state is consistent
    const memIdentity = identityStore.getIdentity();
    if (memIdentity && !memIdentity.hats.some(f => f.name === name)) {
      memIdentity.hats.push(hat as any);
    }
  } catch {
    // Best-effort
  }
}

```
