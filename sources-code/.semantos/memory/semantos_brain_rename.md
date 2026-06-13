---
name: semantos-brain rename
description: wsh was renamed to semantos-brain; binary is now `brain` not `wsh`; source at runtime/semantos-brain/
type: project
---

The Zig node runtime was renamed from `wsh` to `semantos-brain`.

- Source root: `runtime/semantos-brain/` (was `runtime/wsh/`)
- Binary: `brain` (was `wsh`)
- CLI verbs unchanged (e.g. `brain serve`, `brain export-operator`)
- `runtime/wsh/` still exists in the filesystem but is the stale/legacy copy — do NOT edit it

**Why:** product rename; wsh (wallet shell) was too narrow a name for the full brain runtime.

**How to apply:** Always work in `runtime/semantos-brain/`; ignore `runtime/wsh/`. Memory files and PRD references to "wsh" mean semantos-brain.
