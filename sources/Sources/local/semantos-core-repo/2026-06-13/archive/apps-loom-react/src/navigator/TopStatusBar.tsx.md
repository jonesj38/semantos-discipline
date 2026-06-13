---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/TopStatusBar.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.942747+00:00
---

# archive/apps-loom-react/src/navigator/TopStatusBar.tsx

```tsx
import { useKernel } from '../contexts/KernelProvider';

export function TopStatusBar() {
  const { kernel, isBooting } = useKernel();
  const kernelOn = !isBooting && kernel !== null;

  return (
    <div className="nav-status-bar">
      <span>Navigator</span>
      <span>
        <span className={`nav-dot ${kernelOn ? 'on' : ''}`} />kernel
        <span className="nav-dot" style={{ marginLeft: 8 }} />anchor
        <span className="nav-dot" style={{ marginLeft: 8 }} />network
        <span className="nav-dot" style={{ marginLeft: 8 }} />wallet
      </span>
    </div>
  );
}

```
