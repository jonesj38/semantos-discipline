---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask-and-cell/check_size.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.810497+00:00
---

# core/pask-and-cell/check_size.sh

```sh
#!/usr/bin/env bash
set -euo pipefail
WASM="zig-out/bin/pask-and-cell.wasm"
SIZE=$(wc -c < "$WASM")
echo "Binary size: $SIZE bytes"
[ "$SIZE" -le 81920 ] || { echo "FAIL: size $SIZE > 80KB limit"; exit 1; }

```
