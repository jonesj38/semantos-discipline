---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/recover-bringup-pi.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.543270+00:00
---

# tools/u2-mesh/recover-bringup-pi.sh

```sh
#!/usr/bin/env bash
# recover-bringup-pi.sh — for Pis where Armbian first-boot dialog is DONE
# but the rest of bulk-bringup-pi.sh's setup didn't run.
#
# Picks up at: root pw = $MESH_ROOT_PW (default skymesh1), todriguez user
# exists with pw $MESH_USER_PW (default skymesh1). Installs the laptop's
# SSH pubkey into todriguez's authorized_keys + NOPASSWD sudoers + then
# does the full mesh-node install.
#
# Usage:
#   ./recover-bringup-pi.sh <pi-ip> <node-config.json>

set -e
set -o pipefail

PI_IP=$1
NODE_CFG=$2

if [ -z "$PI_IP" ] || [ -z "$NODE_CFG" ]; then
    echo "usage: $0 <pi-ip> <node-config.json>" >&2
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN="$SCRIPT_DIR/../runtime/semantos-brain/zig-out/bin/mesh-node"
[ ! -f "$BIN" ] && BIN="$SCRIPT_DIR/../../runtime/semantos-brain/zig-out/bin/mesh-node"
UNIT="$SCRIPT_DIR/mesh-node.service"
INSTALL="$SCRIPT_DIR/install-on-pi.sh"

ROOT_PW="${MESH_ROOT_PW:-skymesh1}"
USER_NAME="${MESH_USER:-todriguez}"
USER_PW="${MESH_USER_PW:-skymesh1}"

# Auto-build aarch64 if missing.
if [ ! -f "$BIN" ] || ! file "$BIN" 2>/dev/null | grep -q aarch64; then
    echo "==> aarch64 binary missing or stale; cross-compiling..."
    ( cd "$SCRIPT_DIR/../../runtime/semantos-brain" && zig build mesh-node -Dtarget=aarch64-linux-gnu )
fi
file "$BIN" 2>/dev/null | grep -q aarch64 || { echo "Error: $BIN cross-compile failed." >&2; exit 2; }
[ -f "$NODE_CFG" ] || { echo "Error: $NODE_CFG missing." >&2; exit 2; }

# Find or generate SSH key.
PUBKEY_FILE=""
for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
    [ -f "$k" ] && { PUBKEY_FILE="$k"; break; }
done
if [ -z "$PUBKEY_FILE" ]; then
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "skyminer-recovery"
    PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"
fi
PUBKEY=$(cat "$PUBKEY_FILE")

# Forget old host key.
ssh-keygen -R "$PI_IP" 2>/dev/null || true

echo ""
echo "============================================"
echo "==> [$PI_IP] config=$(basename "$NODE_CFG") (recovery)"
echo "============================================"

# ── Phase A — ssh as root (post-dialog pw) + install key + NOPASSWD sudo ──
echo "==> [$PI_IP] phase A: install ssh key + NOPASSWD sudo as root"

expect <<EXPECT_EOF
set timeout 30
log_user 1
spawn ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@$PI_IP

expect {
    -re "yes/no.*\\? " { send "yes\r"; exp_continue }
    "password: " { send "$ROOT_PW\r" }
    timeout { puts "TIMEOUT at initial password"; exit 1 }
}

# Wait for the root shell prompt — match the literal "# " trailing string.
expect {
    "# " { }
    "Permission denied" {
        puts "ROOT PASSWORD WRONG — try MESH_ROOT_PW=1234 if Pi was never logged in"
        exit 1
    }
    timeout { puts "TIMEOUT waiting for root shell"; exit 1 }
}

send "mkdir -p /home/$USER_NAME/.ssh\r"
expect "# "
send "echo '$PUBKEY' > /home/$USER_NAME/.ssh/authorized_keys\r"
expect "# "
send "chmod 700 /home/$USER_NAME/.ssh && chmod 600 /home/$USER_NAME/.ssh/authorized_keys\r"
expect "# "
send "chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh\r"
expect "# "
send "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/00-$USER_NAME\r"
expect "# "
send "chmod 440 /etc/sudoers.d/00-$USER_NAME\r"
expect "# "
send "exit\r"
expect eof
EXPECT_EOF

echo "==> [$PI_IP] phase A done"

# ── Phase B — upload via plain scp (key auth) ─────────────────────────────
echo "==> [$PI_IP] phase B: uploading artifacts"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes)

scp "${SSH_OPTS[@]}" "$BIN" "$USER_NAME@$PI_IP:/tmp/"
scp "${SSH_OPTS[@]}" "$NODE_CFG" "$USER_NAME@$PI_IP:/tmp/mesh.json"
scp "${SSH_OPTS[@]}" "$UNIT" "$USER_NAME@$PI_IP:/tmp/"
scp "${SSH_OPTS[@]}" "$INSTALL" "$USER_NAME@$PI_IP:/tmp/"

# ── Phase C — install + iface override + start ────────────────────────────
echo "==> [$PI_IP] phase C: install + iface override + start"

ssh "${SSH_OPTS[@]}" "$USER_NAME@$PI_IP" 'bash -s' <<'REMOTE_SCRIPT'
set -e
sudo /tmp/install-on-pi.sh /tmp/mesh-node /tmp/mesh.json /tmp/mesh-node.service > /tmp/install.log 2>&1 &
INSTALL_PID=$!
sleep 4
sudo kill -- $INSTALL_PID 2>/dev/null || true
wait $INSTALL_PID 2>/dev/null || true

sudo mkdir -p /etc/systemd/system/mesh-node.service.d
printf '[Service]\nExecStart=\nExecStart=/usr/local/bin/mesh-node --config /etc/semantos/mesh.json --heartbeat-ms 2000 --iface end0\n' | sudo tee /etc/systemd/system/mesh-node.service.d/iface.conf > /dev/null
sudo systemctl daemon-reload
sudo systemctl restart mesh-node
sleep 1
sudo journalctl -u mesh-node -n 3 --no-pager
REMOTE_SCRIPT

echo "==> [$PI_IP] DONE"

```
