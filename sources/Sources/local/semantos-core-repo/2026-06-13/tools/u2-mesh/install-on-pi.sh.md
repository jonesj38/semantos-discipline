---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/u2-mesh/install-on-pi.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.542197+00:00
---

# tools/u2-mesh/install-on-pi.sh

```sh
#!/usr/bin/env bash
# install-on-pi.sh — Phase U.2 first-Pi bring-up helper.
#
# Run this ON an already-booted Armbian-on-Orange-Pi-Prime SBC (NOT on
# your laptop). It installs the cross-compiled mesh-node binary + the
# systemd unit + the node-XX.json config and starts the service.
#
# Pre-flight on the SBC:
#   1. Fresh Armbian image flashed to its microSD, network plugged in,
#      DHCP from the skyminer's internal PL-DGMK300 working (you can ping
#      the SBC from another host on the 192.168.0.0/24 LAN).
#   2. You scp'd this script + the cross-compiled `mesh-node` binary +
#      the per-node JSON config + `mesh-node.service` onto the SBC.
#
# Usage on the SBC (as root, e.g. via `sudo -i` after first-boot):
#   ./install-on-pi.sh /path/to/mesh-node /path/to/node-01.json /path/to/mesh-node.service
#
# Side effects:
#   - copies the binary to /usr/local/bin/mesh-node (mode 755)
#   - copies the config to /etc/semantos/mesh.json (mode 600 — secret keys)
#   - copies the unit to /etc/systemd/system/mesh-node.service
#   - systemctl daemon-reload + enable + start
#   - tails the journal so you immediately see the gossip output

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root (try: sudo -i first)" >&2
    exit 1
fi

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <mesh-node-binary> <node-XX.json> <mesh-node.service>" >&2
    exit 2
fi

BIN=$1
CFG=$2
UNIT=$3

for f in "$BIN" "$CFG" "$UNIT"; do
    if [ ! -f "$f" ]; then
        echo "not found: $f" >&2
        exit 3
    fi
done

# Architecture sanity — refuse to install a non-aarch64 binary.
# We can't rely on `file(1)` (not in Armbian minimal CLI). Parse the ELF
# header directly: magic at bytes 0–3 = 7F 45 4C 46 (.ELF); e_machine at
# bytes 18–19 little-endian = B7 00 for EM_AARCH64 (183). od is in
# coreutils — present on every reasonable Linux.
elf_magic=$(od -An -c -N 4 "$BIN" | tr -d ' \n')
if [ "$elf_magic" != "177ELF" ]; then
    echo "not an ELF binary: $BIN (magic=$elf_magic)" >&2
    exit 4
fi
e_machine=$(od -An -t x1 -j 18 -N 2 "$BIN" | tr -d ' \n')
if [ "$e_machine" != "b700" ]; then
    echo "refusing to install non-aarch64 binary: $BIN (e_machine=0x$e_machine, expected 0xb700 for EM_AARCH64)" >&2
    exit 4
fi

echo "==> creating /etc/semantos/"
install -d -m 755 /etc/semantos

echo "==> installing binary → /usr/local/bin/mesh-node"
install -m 755 "$BIN" /usr/local/bin/mesh-node

echo "==> installing config → /etc/semantos/mesh.json (mode 600)"
install -m 600 "$CFG" /etc/semantos/mesh.json

echo "==> installing systemd unit → /etc/systemd/system/mesh-node.service"
install -m 644 "$UNIT" /etc/systemd/system/mesh-node.service

echo "==> reloading systemd + enabling unit"
systemctl daemon-reload
systemctl enable mesh-node.service

echo "==> starting mesh-node"
systemctl restart mesh-node.service
sleep 1
systemctl --no-pager status mesh-node.service | head -20 || true

echo ""
echo "==> tailing journal (Ctrl-C to detach; service keeps running)"
echo "    look for 'mesh-node up' + 'TX heartbeat' lines"
journalctl -u mesh-node.service -f -n 30

```
