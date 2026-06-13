---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mcast-relay.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.747327+00:00
---

# docs/demo/mcast-relay.py

```py
#!/usr/bin/env python3
"""
mcast-relay.py — bridge IPv6 multicast → localhost UDP for mesh-bridge.ts.

Bun/Node.js dgram addMembership() does not correctly join IPv6 multicast
on a named interface (it resolves to the default-route interface instead
of the specified one). This relay fixes the gap:
  • joins ff15::5e:1:47100 on the correct interface via if_nametoindex
  • re-emits every received datagram verbatim to RELAY_HOST:RELAY_PORT

mesh-bridge.ts reads from the relay port instead of the multicast socket.

Usage:
    python3 docs/demo/mcast-relay.py
    MCAST_IFACE=en8 RELAY_PORT=47101 python3 docs/demo/mcast-relay.py

Env:
    MCAST_GROUP   (ff15::5e:1)   IPv6 multicast group
    MCAST_PORT    (47100)        UDP port
    MCAST_IFACE   (en8)         Network interface for real Pi mesh
    RELAY_HOST    (127.0.0.1)   Where to forward packets
    RELAY_PORT    (47101)       Localhost port mesh-bridge.ts listens on
"""
import os, socket, struct, sys

GROUP      = os.environ.get('MCAST_GROUP',  'ff15::5e:1')
MCAST_PORT = int(os.environ.get('MCAST_PORT', 47100))
IFACE      = os.environ.get('MCAST_IFACE',  'en8')
RELAY_HOST = os.environ.get('RELAY_HOST',   '127.0.0.1')
RELAY_PORT = int(os.environ.get('RELAY_PORT', 47101))

# --- multicast receiver socket -----------------------------------------------
recv = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
recv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    recv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
except AttributeError:
    pass  # SO_REUSEPORT not on all platforms
recv.bind(('', MCAST_PORT))

iface_idx = socket.if_nametoindex(IFACE)
mreq = struct.pack('16sI', socket.inet_pton(socket.AF_INET6, GROUP), iface_idx)
recv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_JOIN_GROUP, mreq)
print(f'mcast-relay: joined {GROUP}:{MCAST_PORT} on {IFACE} (idx {iface_idx})', flush=True)

# --- relay sender socket (IPv4 localhost) ------------------------------------
fwd = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print(f'mcast-relay: forwarding to {RELAY_HOST}:{RELAY_PORT}', flush=True)

count = 0
while True:
    data, addr = recv.recvfrom(4096)
    fwd.sendto(data, (RELAY_HOST, RELAY_PORT))
    count += 1
    if count % 50 == 0:
        print(f'mcast-relay: {count} packets relayed', flush=True)

```
