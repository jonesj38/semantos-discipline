---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/cell-store/check-pis.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.435132+00:00
---

# cartridges/shared/cell-store/check-pis.sh

```sh
#!/usr/bin/env bash
# check-pis.sh — Skyminer Pi fleet reachability + SSH probe
#
# Scans 192.168.20.2–11, reports:
#   ✓ READY      — SSH key auth works, can deploy
#   ⚠ NEED KEY   — port 22 open but key auth fails; run ssh-copy-id
#   ⚠ SSH OFF    — host reachable but port 22 closed; run systemctl enable --now ssh
#   ✗ OFFLINE    — host not responding to ping
#
# Usage:
#   bash cartridges/shared/cell-store/check-pis.sh
#   PI_USER=todriguez PI_SUBNET=192.168.20 bash ...

set -uo pipefail

PI_USER="${PI_USER:-todriguez}"
PI_SUBNET="${PI_SUBNET:-192.168.20}"
LASTS="${PI_LASTS:-2 3 4 5 6 7 8 9 10 11}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo ""
echo "  Skyminer Pi fleet probe — ${PI_USER}@${PI_SUBNET}.x"
echo "  ─────────────────────────────────────────────────────"

READY=0; NEED_KEY=0; SSH_OFF=0; OFFLINE=0

for LAST in $LASTS; do
  IP="${PI_SUBNET}.${LAST}"

  # Ping probe (1 packet, 600ms timeout)
  if ! ping -c1 -W1 "$IP" >/dev/null 2>&1; then
    echo -e "  ${RED}✗ OFFLINE${NC}   $IP"
    ((OFFLINE++)) || true
    continue
  fi

  # Port 22 probe
  if ! nc -z -w1 "$IP" 22 >/dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠ SSH OFF${NC}   $IP  — ping OK, sshd not running"
    echo    "             → ssh ${PI_USER}@$IP 'sudo systemctl enable --now ssh'"
    ((SSH_OFF++)) || true
    continue
  fi

  # Key auth probe (no password, 3s timeout, no host-key prompt)
  if ssh -o BatchMode=yes \
         -o ConnectTimeout=3 \
         -o StrictHostKeyChecking=no \
         "${PI_USER}@${IP}" "exit" >/dev/null 2>&1; then
    # Check if bun is available
    BUN_OK=""
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
           "${PI_USER}@${IP}" "command -v bun >/dev/null 2>&1" >/dev/null 2>&1; then
      BUN_OK="  bun ✓"
    else
      BUN_OK="  bun ✗ (install needed)"
    fi
    echo -e "  ${GREEN}✓ READY${NC}     $IP${BUN_OK}"
    ((READY++)) || true
  else
    echo -e "  ${YELLOW}⚠ NEED KEY${NC}  $IP  — port 22 open, key auth failed"
    echo    "             → ssh-copy-id ${PI_USER}@$IP"
    ((NEED_KEY++)) || true
  fi
done

echo "  ─────────────────────────────────────────────────────"
echo -e "  ${GREEN}Ready: $READY${NC}   ${YELLOW}Need key: $NEED_KEY   SSH off: $SSH_OFF${NC}   ${RED}Offline: $OFFLINE${NC}"
echo ""

if [ "$READY" -eq 0 ]; then
  echo "  ⚠  No Pis are deploy-ready.  Fix SSH first, then:"
  echo "     bash cartridges/shared/cell-store/deploy-to-pis.sh"
  echo ""
elif [ "$READY" -gt 0 ]; then
  echo "  $READY Pi(s) ready — deploy with:"
  echo "     bash cartridges/shared/cell-store/deploy-to-pis.sh"
  echo ""
fi

```
