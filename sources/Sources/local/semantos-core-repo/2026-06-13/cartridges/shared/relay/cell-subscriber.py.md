---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/cell-subscriber.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.437518+00:00
---

# cartridges/shared/relay/cell-subscriber.py

```py
#!/usr/bin/env python3
"""
cell-subscriber.py — receives policy-verdict cells from the infra-demo relay
onto the Skyminer IPv6 multicast mesh.

Run on any Orange Pi Prime (or any Linux box on the same LAN):

    python3 cell-subscriber.py [--iface end0] [--udp-port 4242]

Requirements: Python 3.8+, no third-party libraries.

MULTICAST GROUPS (Phase 34A SRv6 formula, scope 0x15, pre-computed):
    ff15:4c8d:4906:bcc5:5005:0000:0000:0000  dark.fiber.commit
    ff15:4c8d:4906:65a8:c2d4:0000:0000:0000  dark.fiber.hold
    ff15:f927:c97d:a01f:2dee:0000:0000:0000  inference.access.grant
    ff15:f927:c97d:6acb:8af4:0000:0000:0000  inference.access.deny
    ff15:ad28:ac72:53d0:9d47:0000:0000:0000  ixp.route.accept
    ff15:ad28:ac72:c8f2:d98d:0000:0000:0000  ixp.route.reject

GROUP DERIVATION (for reference — same as srv6.ts):
    WHAT[0:4] = SHA-256("what." + whatPath)[0:4 bytes]
    HOW[0:4]  = SHA-256("how."  + howSlug)[0:4 bytes]
    group     = ff15:WHAT[0:2]WHAT[2:4]:HOW[0:2]HOW[2:4]:00000000:0000
"""

import argparse
import hashlib
import json
import signal
import socket
import struct
import sys
from datetime import datetime

# ── Multicast groups (pinned 2026-05-26) ──────────────────────────────────────

GROUPS: dict[str, str] = {
    'dark.fiber.commit':       'ff15:4c8d:4906:bcc5:5005:0000:0000:0000',
    'dark.fiber.hold':         'ff15:4c8d:4906:65a8:c2d4:0000:0000:0000',
    'inference.access.grant':  'ff15:f927:c97d:a01f:2dee:0000:0000:0000',
    'inference.access.deny':   'ff15:f927:c97d:6acb:8af4:0000:0000:0000',
    'ixp.route.accept':        'ff15:ad28:ac72:53d0:9d47:0000:0000:0000',
    'ixp.route.reject':        'ff15:ad28:ac72:c8f2:d98d:0000:0000:0000',
}

# ── Group derivation helper (verify against pinned table above) ────────────────

def axis_prefix(prefix: str, value: str) -> bytes:
    data = f'{prefix}.{value}'.encode()
    return hashlib.sha256(data).digest()[:4]

def derive_group(what: str, how: str, scope: int = 0x15) -> str:
    w = axis_prefix('what', what)
    h = axis_prefix('how',  how)
    z = bytes(4)
    def grp(b): return f'{b[0]:02x}{b[1]:02x}:{b[2]:02x}{b[3]:02x}'
    return f'ff{scope:02x}:{grp(w)}:{grp(h)}:{grp(z)}:0000'

# ── Colour helpers ─────────────────────────────────────────────────────────────

ESC = '\033['
def green(s):   return f'{ESC}32m{s}{ESC}0m'
def red(s):     return f'{ESC}31m{s}{ESC}0m'
def yellow(s):  return f'{ESC}33m{s}{ESC}0m'
def cyan(s):    return f'{ESC}36m{s}{ESC}0m'
def dim(s):     return f'{ESC}2m{s}{ESC}0m'
def bold(s):    return f'{ESC}1m{s}{ESC}0m'

# ── Verdict formatting ─────────────────────────────────────────────────────────

def fmt_verdict(cell: dict) -> str:
    t = cell.get('type', '?')
    v = cell.get('verdict', False)
    inp = cell.get('inputs', {})
    hat = cell.get('hat', '?')
    hat_fp = cell.get('hat_fp', '')
    plexus = cell.get('plexus')
    strategy = cell.get('strategy', '')
    ts = datetime.fromtimestamp(cell.get('ts', 0) / 1000).strftime('%H:%M:%S.%f')[:-3]

    verdict_str = green('● COMMIT/GRANT/ACCEPT') if v else red('○ HOLD/DENY/REJECT')

    lines = [
        f'{dim(ts)}  {bold(t)}',
        f'  verdict   {verdict_str}',
        f'  strategy  {cyan(strategy)}  hat={cyan(hat)}({dim(hat_fp)})',
    ]
    if inp:
        inp_str = '  '.join(f'{k}={v}' for k, v in inp.items())
        lines.append(f'  inputs    {inp_str}')
    if plexus:
        ct = plexus.get('certTier', '?')
        dc = plexus.get('dataClass', '?')
        tier_labels = {0: 'Anonymous', 1: 'Plexus-lite', 2: 'Plexus-enterprise', 3: 'Plexus-sovereign'}
        lines.append(f'  plexus    certTier={ct} ({tier_labels.get(ct, "?")})  dataClass={dc}')
    return '\n'.join(lines)

# ── UDP subscriber ────────────────────────────────────────────────────────────

def run(udp_port: int, iface: str, gpio_pin: int | None, verbose: bool):
    sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except AttributeError:
        pass  # not all platforms have SO_REUSEPORT

    sock.bind(('::', udp_port))

    # Resolve interface index
    iface_idx = 0
    if iface:
        try:
            iface_idx = socket.if_nametoindex(iface)
        except OSError as e:
            print(f'[sub] WARNING: cannot resolve iface {iface!r}: {e}')

    # Join all groups
    joined = []
    for type_path, group in GROUPS.items():
        try:
            group_bytes = socket.inet_pton(socket.AF_INET6, group)
            mreq = group_bytes + struct.pack('@I', iface_idx)
            sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_JOIN_GROUP, mreq)
            joined.append((type_path, group))
        except OSError as e:
            print(f'[sub] WARNING: cannot join {group} ({type_path}): {e}')

    print(bold('[sub] Skyminer cell subscriber ready'))
    print(f'[sub] UDP port  : {udp_port}')
    print(f'[sub] Interface : {iface or "(default)"}')
    print(f'[sub] GPIO pin  : {gpio_pin if gpio_pin is not None else "disabled"}')
    print(f'[sub] Groups joined ({len(joined)}):')
    for tp, g in joined:
        print(f'       {tp.ljust(30)} {dim(g)}')
    print()

    gpio_line = None
    if gpio_pin is not None:
        gpio_line = _open_gpio(gpio_pin)

    def _shutdown(sig, frame):
        print('\n[sub] shutting down')
        sock.close()
        if gpio_line:
            _gpio_set(gpio_line, 0)
        sys.exit(0)

    signal.signal(signal.SIGINT,  _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    while True:
        try:
            data, addr = sock.recvfrom(65535)
        except OSError:
            break

        try:
            cell = json.loads(data.decode('utf-8'))
        except Exception:
            if verbose:
                print(f'[sub] non-JSON packet from {addr[0]}: {data[:80]!r}')
            continue

        print(fmt_verdict(cell))

        # GPIO lightswitch
        if gpio_line is not None:
            _gpio_set(gpio_line, 1 if cell.get('verdict', False) else 0)

        print()

# ── GPIO helpers (sysfs, no gpiod dependency) ─────────────────────────────────

def _open_gpio(pin: int):
    """Export GPIO pin via sysfs. Returns pin number for use in _gpio_set."""
    try:
        with open('/sys/class/gpio/export', 'w') as f:
            f.write(str(pin))
    except OSError:
        pass  # already exported
    try:
        with open(f'/sys/class/gpio/gpio{pin}/direction', 'w') as f:
            f.write('out')
        print(f'[sub] GPIO pin {pin} opened via sysfs')
        return pin
    except OSError as e:
        print(f'[sub] WARNING: GPIO pin {pin} unavailable: {e}')
        return None

def _gpio_set(pin, value: int):
    try:
        with open(f'/sys/class/gpio/gpio{pin}/value', 'w') as f:
            f.write('1' if value else '0')
    except OSError:
        pass

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description='Skyminer infra-demo cell subscriber')
    p.add_argument('--iface',    default='',   help='Network interface name (e.g. end0)')
    p.add_argument('--udp-port', default=4242, type=int, help='UDP port (must match relay)')
    p.add_argument('--gpio-pin', default=None, type=int, help='GPIO pin to toggle on verdict (sysfs)')
    p.add_argument('--verbose',  action='store_true')
    p.add_argument('--verify-groups', action='store_true',
                   help='Re-derive groups dynamically and check against pinned table, then exit')
    args = p.parse_args()

    if args.verify_groups:
        print('Verifying pinned multicast groups...')
        ok = True
        for type_path, pinned in GROUPS.items():
            parts = type_path.rsplit('.', 1)
            if len(parts) != 2:
                print(f'  SKIP {type_path} (cannot split what/how)')
                continue
            what, how = parts[0], parts[1]
            # For 3-segment paths (ixp.route.accept) the last dot is the how
            # but 'dark.fiber.commit' splits to what='dark.fiber', how='commit' ✓
            derived = derive_group(what, how)
            match = derived == pinned
            status = green('OK') if match else red('MISMATCH')
            print(f'  {status}  {type_path}')
            if not match:
                print(f'       pinned : {pinned}')
                print(f'       derived: {derived}')
                ok = False
        sys.exit(0 if ok else 1)

    run(args.udp_port, args.iface, args.gpio_pin, args.verbose)

if __name__ == '__main__':
    main()

```
