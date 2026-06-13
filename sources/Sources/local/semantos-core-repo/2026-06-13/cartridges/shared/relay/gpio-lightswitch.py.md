---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/gpio-lightswitch.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.438070+00:00
---

# cartridges/shared/relay/gpio-lightswitch.py

```py
#!/usr/bin/env python3
"""
gpio-lightswitch.py — standalone GPIO actuator for the infra-demo lightswitch.

Subscribes to ALL infra-demo multicast groups and flips the target GPIO pin
when any COMMIT / GRANT / ACCEPT verdict arrives.  A separate script from
cell-subscriber.py so operators can choose: terminal display (subscriber)
or physical actuator (this script) or both.

Run on one designated Skyminer Pi (the one with the relay / LED wired up):

    python3 gpio-lightswitch.py --pin 7 [--iface end0]

Orange Pi Prime H5 GPIO pinout reference (sysfs numbers):
    Pin 7 = PA6  → sysfs gpio 6
    Pin 11 = PA0 → sysfs gpio 0
    Pin 13 = PA1 → sysfs gpio 1
    Pin 15 = PA3 → sysfs gpio 3
    (see: http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-Prime.html)

The "lightswitch" moment:
    Browser slider changes → predicate fires COMMIT → relay multicasts cell
    → this script receives cell → GPIO pin HIGH → relay/LED actuates.

    A 9-byte Bitcoin Script rule turned on a light.
"""

import argparse
import hashlib
import json
import signal
import socket
import struct
import sys
import time
from datetime import datetime

# ── Pinned multicast groups (2026-05-26, scope 0x15) ─────────────────────────

GROUPS = [
    'ff15:4c8d:4906:bcc5:5005:0000:0000:0000',  # dark.fiber.commit
    'ff15:f927:c97d:a01f:2dee:0000:0000:0000',  # inference.access.grant
    'ff15:ad28:ac72:53d0:9d47:0000:0000:0000',  # ixp.route.accept
    # Also subscribe to negative verdicts so we can turn the pin off
    'ff15:4c8d:4906:65a8:c2d4:0000:0000:0000',  # dark.fiber.hold
    'ff15:f927:c97d:6acb:8af4:0000:0000:0000',  # inference.access.deny
    'ff15:ad28:ac72:c8f2:d98d:0000:0000:0000',  # ixp.route.reject
]

# ── GPIO (sysfs) ──────────────────────────────────────────────────────────────

def gpio_export(pin: int):
    try:
        with open('/sys/class/gpio/export', 'w') as f:
            f.write(str(pin))
    except OSError:
        pass  # already exported

def gpio_direction(pin: int, direction: str = 'out'):
    with open(f'/sys/class/gpio/gpio{pin}/direction', 'w') as f:
        f.write(direction)

def gpio_set(pin: int, value: int):
    with open(f'/sys/class/gpio/gpio{pin}/value', 'w') as f:
        f.write('1' if value else '0')

def gpio_unexport(pin: int):
    try:
        with open('/sys/class/gpio/unexport', 'w') as f:
            f.write(str(pin))
    except OSError:
        pass

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description='Infra-demo GPIO lightswitch')
    p.add_argument('--pin',      required=True, type=int, help='GPIO sysfs pin number')
    p.add_argument('--iface',    default='',              help='Network interface (e.g. end0)')
    p.add_argument('--udp-port', default=4242,  type=int)
    p.add_argument('--hold-ms',  default=500,   type=int, help='ms to hold pin HIGH before checking next verdict')
    args = p.parse_args()

    pin = args.pin

    # Setup GPIO
    gpio_export(pin)
    try:
        gpio_direction(pin, 'out')
    except OSError as e:
        print(f'ERROR: cannot set GPIO pin {pin} direction: {e}')
        print('Hint: run as root or add yourself to the gpio group')
        sys.exit(1)
    gpio_set(pin, 0)
    print(f'[lightswitch] GPIO pin {pin} ready (sysfs)')

    # Setup UDP socket
    sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except AttributeError:
        pass
    sock.bind(('::', args.udp_port))

    iface_idx = 0
    if args.iface:
        try:
            iface_idx = socket.if_nametoindex(args.iface)
        except OSError as e:
            print(f'WARNING: cannot resolve iface {args.iface!r}: {e}')

    for group in GROUPS:
        group_bytes = socket.inet_pton(socket.AF_INET6, group)
        mreq = group_bytes + struct.pack('@I', iface_idx)
        try:
            sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_JOIN_GROUP, mreq)
        except OSError as e:
            print(f'WARNING: cannot join {group}: {e}')

    print(f'[lightswitch] Joined {len(GROUPS)} multicast groups on UDP :{args.udp_port}')
    print(f'[lightswitch] Waiting for verdict cells...')
    print()

    def _shutdown(sig, frame):
        gpio_set(pin, 0)
        gpio_unexport(pin)
        sock.close()
        print('\n[lightswitch] GPIO off, exiting')
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
            continue

        verdict  = cell.get('verdict', False)
        type_    = cell.get('type', '?')
        hat      = cell.get('hat', '?')
        ts       = datetime.fromtimestamp(cell.get('ts', 0) / 1000).strftime('%H:%M:%S')
        strategy = cell.get('strategy', '')

        if verdict:
            gpio_set(pin, 1)
            print(f'[{ts}] ⚡  PIN {pin} → HIGH   {type_}  strategy={strategy}  hat={hat}')
            time.sleep(args.hold_ms / 1000)
            gpio_set(pin, 0)
            print(f'[{ts}]    PIN {pin} → LOW    (hold complete)')
        else:
            print(f'[{ts}] ○   PIN {pin} stays LOW  {type_}  verdict=false')

if __name__ == '__main__':
    main()

```
