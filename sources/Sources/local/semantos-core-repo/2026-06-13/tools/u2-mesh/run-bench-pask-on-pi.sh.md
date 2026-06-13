---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/run-bench-pask-on-pi.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.543531+00:00
---

# tools/u2-mesh/run-bench-pask-on-pi.sh

```sh
#!/usr/bin/env bash
# run-bench-pask-on-pi.sh — build + SCP + run bench-pask on all reachable Pis.
#
# Pre-requisite: ssh-add ~/.ssh/id_ed25519   ← do this in your terminal first.
#
# Usage:
#   ./tools/u2-mesh/run-bench-pask-on-pi.sh [pi-ip]
#
# With no argument: ARP-scans 192.168.0.{2..8} and runs on the first reachable one.
# With an IP:       uses that IP directly.
#
# The aarch64 binary is always rebuilt from source (zig build bench-pask
# -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast) before upload.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$SCRIPT_DIR/../.."
BRAIN_DIR="$REPO_ROOT/runtime/semantos-brain"
BIN="$BRAIN_DIR/zig-out/bin/bench-pask"
USER="${MESH_USER:-todriguez}"
SSH_OPTS="-o ConnectTimeout=8 -o StrictHostKeyChecking=no -o BatchMode=yes"

# ── 1. (re)build aarch64 binary ───────────────────────────────────────────────
echo "==> Cross-compiling bench-pask for aarch64…"
(cd "$BRAIN_DIR" && zig build bench-pask -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast)
file "$BIN" | grep -q aarch64 || { echo "ERROR: binary is not aarch64 after build"; exit 2; }
echo "    OK — $(ls -lh "$BIN" | awk '{print $5}') ELF aarch64"

# ── 2. find a Pi ─────────────────────────────────────────────────────────────
PI_IP="${1:-}"
if [ -z "$PI_IP" ]; then
  echo "==> Scanning 192.168.0.{2..8} for first reachable Pi…"
  for ip in 192.168.0.{2..8}; do
    if ssh $SSH_OPTS "$USER@$ip" true 2>/dev/null; then
      PI_IP="$ip"
      echo "    Found: $PI_IP"
      break
    fi
  done
fi

[ -n "$PI_IP" ] || { echo "ERROR: no Pi reachable. Did you run ssh-add ~/.ssh/id_ed25519?"; exit 2; }

# ── 3. upload ─────────────────────────────────────────────────────────────────
echo "==> Uploading to $USER@$PI_IP:/tmp/bench-pask…"
scp $SSH_OPTS "$BIN" "$USER@$PI_IP:/tmp/bench-pask"
ssh $SSH_OPTS "$USER@$PI_IP" "chmod +x /tmp/bench-pask"

# ── 4. run ────────────────────────────────────────────────────────────────────
echo ""
echo "==> Running bench-pask on $PI_IP (H5 Cortex-A53 @ 1.368 GHz)"
echo "    (this takes ~30 s for the 1M-scale rows)"
echo ""
ssh $SSH_OPTS "$USER@$PI_IP" "/tmp/bench-pask"

```
