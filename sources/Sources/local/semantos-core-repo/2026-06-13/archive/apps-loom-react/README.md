---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.694923+00:00
---

# ⚠ DEPRECATED — apps/loom-react

**This package is deprecated as of 2026-05-25 and will be removed in a future release.**

The operator helm surface has been ported to **`apps/loom-svelte`**, which is now the canonical shell. New feature work goes there; loom-react is frozen.

---

## Migration

| loom-react surface | loom-svelte equivalent | Status |
|---|---|---|
| Dock / bottom nav | `src/shell/Dock.svelte` | ✓ Shipped |
| Attention surface (home) | `src/shell/AttentionSurface.svelte` | ✓ Shipped |
| Hat switcher | `src/components/HatSwitcher.svelte` | ✓ Shipped |
| Extension / workspace switcher | `src/shell/ExtensionSwitcher.svelte` | ✓ Shipped |
| Talk → Self (intent classify) | `src/views/talk/TalkSelfView.svelte` | ✓ Shipped |
| Talk → Direct (1:1 thread) | `src/views/talk/TalkDirectView.svelte` | ✓ Shipped |
| Talk → Agent (task delegation) | `src/views/talk/TalkAgentView.svelte` | ✓ Shipped |
| Find → Network (contacts + persona) | `src/views/NetworkView.svelte` | ✓ Shipped |
| Contacts panel (add / edge / revoke) | `src/views/ContactPersonaPanel.svelte` | ✓ Shipped |

## What happens to the non-helm parts?

The directories below are workbench / dev surfaces, not operator surfaces. They are **not** being ported to loom-svelte. Each will be evaluated separately:

| Directory | Fate |
|---|---|
| `canvas/` | Move to a dedicated workbench app (TBD) or delete |
| `inspector/` | Move to workbench or delete |
| `panels/` | Move to workbench or delete |
| `swarm/` | Delete — swarm logic moves to `core/pask/` |
| `sidebar/` | Delete |
| `plexus/` | Evaluated separately — Plexus has its own surface roadmap |

## Removal timeline

loom-react will be **deleted from the monorepo** once:

1. `apps/loom-svelte` is deployed to production and operators have been migrated
2. No remaining CI jobs reference `apps/loom-react`
3. The non-helm surfaces listed above have been rehomed or confirmed for deletion

Tracked in `docs/canon/deliverables.yml` under `D-loom-react-remove` (scheduled post-production deploy).

---

*If you're looking for the operator shell, go to [`apps/loom-svelte`](../loom-svelte).*
