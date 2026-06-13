---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mesh-tenant-gateway.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.749167+00:00
---

# docs/demo/mesh-tenant-gateway.py

```py
#!/usr/bin/env python3
"""
mesh-tenant-gateway.py — bidirectional IPv6 multicast relay between
the intra-Pi loopback tier and the inter-Pi LAN tier.

This is the SRv6 provider-edge router in miniature (D-SRS-tenant-gateway).
It makes N=~16 brain processes on ONE Pi appear as N distinct nodes to the
full mesh, scaling the federation from N=6 (one brain per Pi) to N≈100
(sixteen brains per Pi x 6 Pis).

Architecture on each Pi:
  ┌──────── Pi ────────────────────────────────────────┐
  │  brain-00  brain-01  …  brain-15                   │
  │       ↕            loopback (lo / lo0)             │
  │          mesh-tenant-gateway.py                    │
  │                   ↕  LAN (end0 / en8)              │
  └────────────────────────────────────────────────────┘
             ↕  ↕  ↕  other Pis on LAN

The gateway joins the SAME SNS-derived multicast group on BOTH interfaces.
Packets received on loopback (from local brains) are forwarded to LAN so
other Pis see them; packets received on LAN (from other Pis) are forwarded
to loopback so local brains see them.

Loop prevention: a time-keyed digest cache suppresses echoes of packets the
gateway just forwarded (a packet forwarded LAN-ward is heard back on the LAN
socket — the cache drops it before it's re-forwarded to loopback).

Default SNS group for mnca.tile.tick:
  ff15:4ed1:aabd:873d:e970:0000:0000:0000
  (see core/protocol-types/src/mnca/srv6.ts, MNCA_TILE_TICK_GROUP)

Usage on Pi:
    python3 docs/demo/mesh-tenant-gateway.py \\
        --local-iface lo --wan-iface end0

Usage on Mac (bridge lo0 ↔ en8 for Pi-mesh integration):
    python3 docs/demo/mesh-tenant-gateway.py \\
        --local-iface lo0 --wan-iface en8

Env overrides (all optional):
    MCAST_GROUP     multicast group  (default: ff15:4ed1:aabd:873d:e970:0000:0000:0000)
    MCAST_PORT      UDP port         (default: 47100)
    LOCAL_IFACE     loopback iface   (default: lo0 on macOS, lo on Linux)
    WAN_IFACE       LAN iface        (default: en8)
    GW_CACHE_TTL    loop suppression window in seconds (default: 2.0)
    GW_HOPS         IPv6 hop limit for forwarded packets (default: 1)

SAFETY: read-only observer for the demo — it relays existing multicast traffic
and does not inject new cells, sign transactions, or contact any external service.
"""

import argparse
import hashlib
import os
import select
import socket
import struct
import sys
import time
from collections import OrderedDict

# ── default multicast group (MNCA tile-tick SNS address) ─────────────────────

DEFAULT_GROUP = 'ff15:4ed1:aabd:873d:e970:0000:0000:0000'
DEFAULT_PORT  = 47100

# ── loop-prevention cache ─────────────────────────────────────────────────────

class RecentCache:
    """
    LRU-bounded set of packet digests, used to suppress gateway self-echoes.

    When the gateway forwards a packet from loopback → LAN, the forwarded
    packet shows up on the LAN receive socket moments later (the gateway's
    LAN address is the source). Without suppression this would be forwarded
    back to loopback, creating a flood loop.

    The cache fingerprints each forwarded packet (first 64 bytes, SHA-256
    truncated to 8 bytes for speed) and drops any packet matching a recent
    fingerprint. Entries expire after `ttl` seconds.
    """

    def __init__(self, ttl: float = 2.0, max_size: int = 512):
        self.ttl = ttl
        self.max_size = max_size
        self._store: OrderedDict = OrderedDict()  # digest → monotonic timestamp

    # Public API
    def mark_forwarded(self, data: bytes) -> None:
        """Record that we just forwarded this packet."""
        key = self._digest(data)
        self._store[key] = time.monotonic()
        self._store.move_to_end(key)
        # Evict oldest when over capacity
        while len(self._store) > self.max_size:
            self._store.popitem(last=False)

    def was_forwarded(self, data: bytes) -> bool:
        """Return True iff this packet was recently forwarded by us (→ drop it)."""
        key = self._digest(data)
        ts = self._store.get(key)
        if ts is None:
            return False
        if time.monotonic() - ts > self.ttl:
            # Expired — remove and allow through
            del self._store[key]
            return False
        return True

    @property
    def size(self) -> int:
        return len(self._store)

    # Private
    @staticmethod
    def _digest(data: bytes) -> bytes:
        # Hash first 64 bytes (cell header prefix) — fast and sufficient for dedup.
        return hashlib.sha256(data[:64]).digest()[:8]


# ── socket helpers ────────────────────────────────────────────────────────────

def make_recv_socket(group: str, port: int, iface_name: str) -> socket.socket:
    """Create a UDP receive socket joined to `group` on `iface_name`."""
    sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except AttributeError:
        pass  # Not available on all platforms
    sock.bind(('', port))

    iface_idx = socket.if_nametoindex(iface_name)
    mreq = struct.pack('16sI', socket.inet_pton(socket.AF_INET6, group), iface_idx)
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_JOIN_GROUP, mreq)
    return sock


def make_send_socket(iface_name: str, hops: int = 1) -> socket.socket:
    """Create a UDP send socket that transmits multicast on `iface_name`."""
    sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    iface_idx = socket.if_nametoindex(iface_name)
    sock.setsockopt(
        socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_IF,
        struct.pack('I', iface_idx),
    )
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_HOPS, hops)
    # Enable local loopback so processes on the same host also receive the packet.
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_LOOP, 1)
    return sock


# ── main gateway loop ─────────────────────────────────────────────────────────

def run_gateway(
    group: str,
    port: int,
    local_iface: str,
    wan_iface: str,
    hops: int,
    cache_ttl: float,
) -> None:
    cache = RecentCache(ttl=cache_ttl)
    dest = (group, port, 0, 0)  # (addr, port, flowinfo, scope_id)

    print(f'mesh-tenant-gateway: group={group}:{port}', flush=True)
    print(f'  loopback  (tenant brains) iface={local_iface}', flush=True)
    print(f'  LAN       (other Pis)     iface={wan_iface}', flush=True)
    print(f'  loop-prevention cache ttl={cache_ttl}s', flush=True)

    local_recv = make_recv_socket(group, port, local_iface)
    wan_recv   = make_recv_socket(group, port, wan_iface)
    local_send = make_send_socket(local_iface, hops)
    wan_send   = make_send_socket(wan_iface, hops)

    fwd_up   = 0   # local → wan
    fwd_down = 0   # wan → local
    dropped  = 0   # loop echoes suppressed

    print('mesh-tenant-gateway: ready\n', flush=True)

    while True:
        ready, _, _ = select.select([local_recv, wan_recv], [], [], 10.0)
        for sock in ready:
            data, _addr = sock.recvfrom(4096)

            if sock is local_recv:
                # Local brain tile → forward to LAN
                if cache.was_forwarded(data):
                    dropped += 1
                else:
                    cache.mark_forwarded(data)
                    wan_send.sendto(data, dest)
                    fwd_up += 1
                    if fwd_up % 100 == 1:
                        print(f'  ↑ lo→wan: {fwd_up}  ↓ wan→lo: {fwd_down}  dropped: {dropped}',
                              flush=True)
            else:
                # Remote Pi tile → forward to loopback
                if cache.was_forwarded(data):
                    dropped += 1
                else:
                    cache.mark_forwarded(data)
                    local_send.sendto(data, dest)
                    fwd_down += 1
                    if fwd_down % 100 == 1:
                        print(f'  ↑ lo→wan: {fwd_up}  ↓ wan→lo: {fwd_down}  dropped: {dropped}',
                              flush=True)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description='Bidirectional IPv6 multicast relay (D-SRS-tenant-gateway)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        '--group',
        default=os.environ.get('MCAST_GROUP', DEFAULT_GROUP),
        help=f'IPv6 multicast group (default: {DEFAULT_GROUP})',
    )
    p.add_argument(
        '--port',
        type=int,
        default=int(os.environ.get('MCAST_PORT', str(DEFAULT_PORT))),
        help=f'UDP port (default: {DEFAULT_PORT})',
    )
    p.add_argument(
        '--local-iface',
        default=os.environ.get('LOCAL_IFACE', 'lo0'),
        help='Loopback interface where tenant brains gossip (default: lo0)',
    )
    p.add_argument(
        '--wan-iface',
        default=os.environ.get('WAN_IFACE', 'en8'),
        help='LAN interface for inter-Pi traffic (default: en8)',
    )
    p.add_argument(
        '--hops',
        type=int,
        default=int(os.environ.get('GW_HOPS', '1')),
        help='IPv6 multicast hop limit for forwarded packets (default: 1)',
    )
    p.add_argument(
        '--cache-ttl',
        type=float,
        default=float(os.environ.get('GW_CACHE_TTL', '2.0')),
        help='Loop-prevention cache TTL in seconds (default: 2.0)',
    )
    return p.parse_args(argv)


if __name__ == '__main__':
    args = parse_args()
    try:
        run_gateway(
            group=args.group,
            port=args.port,
            local_iface=args.local_iface,
            wan_iface=args.wan_iface,
            hops=args.hops,
            cache_ttl=args.cache_ttl,
        )
    except KeyboardInterrupt:
        print('\nmesh-tenant-gateway: stopped', flush=True)
    except OSError as e:
        print(f'\nmesh-tenant-gateway: error — {e}', file=sys.stderr)
        print('  Check that both interfaces exist and the multicast group is valid.',
              file=sys.stderr)
        sys.exit(1)

```
