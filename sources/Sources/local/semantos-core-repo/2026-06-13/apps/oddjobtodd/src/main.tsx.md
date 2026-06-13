---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/main.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.051314+00:00
---

# apps/oddjobtodd/src/main.tsx

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './styles/base.css';
import './styles/stages.css';
import './styles/flip.css';
import './styles/picker.css';
import './styles/day.css';
import './styles/doflip.css';
import './styles/capture.css';
import './styles/live.css';
import LiveApp from './components/LiveApp';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <LiveApp />
  </StrictMode>
);

```
