---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/bulk-bringup-pi.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.542467+00:00
---

# tools/u2-mesh/bulk-bringup-pi.sh

```sh
#!/usr/bin/env bash
# bulk-bringup-pi.sh — bring one freshly-flashed Armbian Orange Pi Prime
# from "first boot, password=1234" to "running mesh-node systemd service
# bound to end0, joined to the multicast group" — in ~30 seconds.
#
# Strategy: one expect session handles the Armbian first-boot dialog,
# then while still in the root shell installs the laptop's SSH pubkey
# into the new user's authorized_keys AND drops a NOPASSWD sudoers entry
# so subsequent ssh/scp + sudo all work without ever prompting again.
#
# Usage:
#   ./bulk-bringup-pi.sh <pi-ip> <node-config.json>
#
# Requires: only `expect` (built-in on macOS). No sshpass, no brew deps.
#
# Assumes:
#   - mesh-node binary at runtime/semantos-brain/zig-out/bin/mesh-node
#     (aarch64-linux-gnu, dynamic-glibc per build.zig link_libc=true)
#   - mesh-node.service + install-on-pi.sh as siblings in this dir
#   - Pi has Armbian first-boot dialog ready (never been logged in)
#   - Laptop has an SSH pubkey at ~/.ssh/id_ed25519.pub OR ~/.ssh/id_rsa.pub
#     (auto-generated if neither exists)

set -e
set -o pipefail

PI_IP=$1
NODE_CFG=$2

if [ -z "$PI_IP" ] || [ -z "$NODE_CFG" ]; then
    echo "usage: $0 <pi-ip> <node-config.json>" >&2
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN="$SCRIPT_DIR/../../runtime/semantos-brain/zig-out/bin/mesh-node"
UNIT="$SCRIPT_DIR/mesh-node.service"
INSTALL="$SCRIPT_DIR/install-on-pi.sh"

ROOT_PW="${MESH_ROOT_PW:-skymesh1}"
USER_NAME="${MESH_USER:-todriguez}"
USER_PW="${MESH_USER_PW:-skymesh1}"
REAL_NAME="${MESH_REAL_NAME:-Todd}"

# Sanity checks — auto-rebuild aarch64 if missing or native.
if [ ! -f "$BIN" ] || ! file "$BIN" 2>/dev/null | grep -q aarch64; then
    echo "==> aarch64 binary missing or stale; cross-compiling..."
    ( cd "$SCRIPT_DIR/../../runtime/semantos-brain" && zig build mesh-node -Dtarget=aarch64-linux-gnu )
fi
file "$BIN" 2>/dev/null | grep -q aarch64 || { echo "Error: $BIN cross-compile failed — still not aarch64." >&2; exit 2; }
[ -f "$NODE_CFG" ] || { echo "Error: $NODE_CFG missing." >&2; exit 2; }
command -v expect >/dev/null 2>&1 || { echo "Error: expect not installed." >&2; exit 2; }

# Find or generate an SSH key for keyless auth post-first-boot.
PUBKEY_FILE=""
for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
    [ -f "$k" ] && { PUBKEY_FILE="$k"; break; }
done
if [ -z "$PUBKEY_FILE" ]; then
    echo "==> no SSH key found; generating ~/.ssh/id_ed25519"
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "skyminer-bulk-bringup"
    PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"
fi
PUBKEY=$(cat "$PUBKEY_FILE")

# Forget any cached host key (Pi MAC changes on reflash → key mismatch).
ssh-keygen -R "$PI_IP" 2>/dev/null || true

echo ""
echo "============================================"
echo "==> [$PI_IP] config=$(basename "$NODE_CFG")"
echo "============================================"

# ── Phase 1 — first-boot dialog + keyless-auth bootstrap (expect) ────────
echo "==> [$PI_IP] phase 1: Armbian first-boot + SSH key + NOPASSWD sudo"

expect <<EXPECT_EOF
set timeout 90
log_user 1
spawn ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@$PI_IP

# Initial host-key + password prompt.
expect {
    -re "yes/no.*\\? " { send "yes\r"; exp_continue }
    "password: " { send "1234\r" }
    timeout { puts "TIMEOUT at initial password prompt"; exit 1 }
}

# Armbian's forced password change.
expect {
    "Create root password:" { send "$ROOT_PW\r" }
    timeout { puts "TIMEOUT waiting for Create root password"; exit 1 }
}
expect "Repeat root password:"
send "$ROOT_PW\r"

# User-creation prompts.
expect {
    "Please provide a username" { send "$USER_NAME\r" }
    timeout { puts "TIMEOUT waiting for username prompt"; exit 1 }
}
expect -re "user.*password:"
send "$USER_PW\r"
expect -re "Repeat user.*password:"
send "$USER_PW\r"
expect "Please provide your real name:"
send "$REAL_NAME\r"

# Optional wireless prompt — skip.
expect {
    "Connect via wireless" { send "n\r"; exp_continue }
    -re "[\\\$#] $" { }
    timeout { puts "TIMEOUT waiting for shell prompt after first-boot"; exit 1 }
}

# We're at a root shell on the Pi. Bootstrap keyless auth + passwordless sudo.
send "mkdir -p /home/$USER_NAME/.ssh && echo '$PUBKEY' > /home/$USER_NAME/.ssh/authorized_keys && chmod 700 /home/$USER_NAME/.ssh && chmod 600 /home/$USER_NAME/.ssh/authorized_keys && chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh\r"
expect -re "[\\\$#] $"

send "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/00-$USER_NAME && chmod 440 /etc/sudoers.d/00-$USER_NAME\r"
expect -re "[\\\$#] $"

send "exit\r"
expect eof
EXPECT_EOF

echo "==> [$PI_IP] phase 1 done — '$USER_NAME' has keyless ssh + NOPASSWD sudo"

# ── Phase 2 — upload artifacts via plain scp (key-based, no password) ────
echo "==> [$PI_IP] phase 2: uploading binary + config + unit + install script"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes)

scp "${SSH_OPTS[@]}" "$BIN" "$USER_NAME@$PI_IP:/tmp/"
scp "${SSH_OPTS[@]}" "$NODE_CFG" "$USER_NAME@$PI_IP:/tmp/mesh.json"
scp "${SSH_OPTS[@]}" "$UNIT" "$USER_NAME@$PI_IP:/tmp/"
scp "${SSH_OPTS[@]}" "$INSTALL" "$USER_NAME@$PI_IP:/tmp/"

# ── Phase 3 — install + iface override + start (all keyless, NOPASSWD sudo) ─
echo "==> [$PI_IP] phase 3: install + iface override + start"

ssh "${SSH_OPTS[@]}" "$USER_NAME@$PI_IP" 'bash -s' <<'REMOTE_SCRIPT'
set -e

# Run install (it tails the journal at the end so we run it in background
# and kill after a few seconds — service stays running, journal detaches).
sudo /tmp/install-on-pi.sh /tmp/mesh-node /tmp/mesh.json /tmp/mesh-node.service > /tmp/install.log 2>&1 &
INSTALL_PID=$!
sleep 4
sudo kill -- $INSTALL_PID 2>/dev/null || true
wait $INSTALL_PID 2>/dev/null || true

# Apply --iface end0 systemd drop-in.
sudo mkdir -p /etc/systemd/system/mesh-node.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/local/bin/mesh-node --config /etc/semantos/mesh.json --heartbeat-ms 2000 --iface end0\n' | sudo tee /etc/systemd/system/mesh-node.service.d/iface.conf > /dev/null
sudo systemctl daemon-reload
sudo systemctl restart mesh-node
sleep 1
sudo journalctl -u mesh-node -n 3 --no-pager
REMOTE_SCRIPT

echo "==> [$PI_IP] DONE"

```
