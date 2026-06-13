---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.757276+00:00
---

# Multipane Viewer Testing

Temporary test harness for the Semantos console. Deploys a throwaway copy of semantos-core and serves a browser-based 4-pane console viewer using tmux + ttyd.

## Quick Start

```bash
./deploy_and_test_semantos_with_multipane.sh
```

Opens at `http://localhost:9090`. Press Ctrl+C to stop.

## What It Does

1. Copies semantos-core to `/tmp/semantos-test-XXXX` (no node_modules, .git, dist)
2. Runs `bun install` in the copy
3. Creates a tmux session `semantos-test-console` with 4 panes:
   - Object tree (left, 20%)
   - Shell REPL (center, 55%)
   - Inspector (right, 25%)
   - Event log (bottom, 6 lines)
4. Starts 4 ttyd instances (ports 9101-9104) each attached to one tmux pane
5. Serves a viewer HTML page (port 9090) that embeds all 4 ttyd iframes

## Ports

| Service | Port | Purpose |
|---------|------|---------|
| Viewer | 9090 | Browser UI |
| ttyd objects | 9101 | Object tree pane |
| ttyd shell | 9102 | Shell REPL pane |
| ttyd inspector | 9103 | Inspector pane |
| ttyd events | 9104 | Event log pane |

Override viewer port: `VIEWER_PORT=8888 ./deploy_and_test_semantos_with_multipane.sh`

## Files

- `deploy_and_test_semantos_with_multipane.sh` — deploy script
- `viewer_server.py` — HTTP server + ttyd/tmux manager
- `viewer.html` — browser UI (4-pane grid with embedded ttyd terminals)

## Cleanup

The deploy directory is preserved after stop for inspection. Remove manually:

```bash
rm -rf /tmp/semantos-test-XXXX
```
