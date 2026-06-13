---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/test_mesh_tenant_gateway.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.748902+00:00
---

# docs/demo/test_mesh_tenant_gateway.py

```py
#!/usr/bin/env python3
"""
Unit tests for mesh-tenant-gateway.py — specifically the RecentCache
loop-prevention logic (no network sockets needed).

Run:
    python3 docs/demo/test_mesh_tenant_gateway.py
    # or: python3 -m pytest docs/demo/test_mesh_tenant_gateway.py -v
"""

import importlib.util, sys, time, unittest
from pathlib import Path

# Load mesh-tenant-gateway.py by file path (hyphen in filename can't be a
# Python module identifier, so we use importlib rather than a bare import).
_gw_path = Path(__file__).parent / 'mesh-tenant-gateway.py'
_spec = importlib.util.spec_from_file_location('mesh_tenant_gateway', _gw_path)
_mod  = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(_mod)  # type: ignore[union-attr]
RecentCache = _mod.RecentCache


class TestRecentCache(unittest.TestCase):

    # ── basic mark / was_forwarded ─────────────────────────────────────────

    def test_empty_cache_returns_false(self):
        c = RecentCache(ttl=1.0)
        self.assertFalse(c.was_forwarded(b'hello'))

    def test_marked_packet_is_detected(self):
        c = RecentCache(ttl=1.0)
        data = b'mesh tile packet'
        c.mark_forwarded(data)
        self.assertTrue(c.was_forwarded(data))

    def test_different_packet_not_blocked(self):
        c = RecentCache(ttl=1.0)
        c.mark_forwarded(b'packet A content here')
        self.assertFalse(c.was_forwarded(b'packet B content here'))

    def test_size_increases_on_mark(self):
        c = RecentCache(ttl=1.0)
        self.assertEqual(c.size, 0)
        c.mark_forwarded(b'pkt1')
        self.assertEqual(c.size, 1)
        c.mark_forwarded(b'pkt2')
        self.assertEqual(c.size, 2)

    # ── TTL expiry ─────────────────────────────────────────────────────────

    def test_expired_entry_returns_false(self):
        c = RecentCache(ttl=0.05)  # 50 ms
        data = b'expiring packet'
        c.mark_forwarded(data)
        self.assertTrue(c.was_forwarded(data))
        time.sleep(0.1)
        self.assertFalse(c.was_forwarded(data))

    def test_fresh_entry_not_expired(self):
        c = RecentCache(ttl=1.0)
        data = b'fresh packet'
        c.mark_forwarded(data)
        time.sleep(0.01)  # much less than TTL
        self.assertTrue(c.was_forwarded(data))

    def test_expired_entry_removed_from_store(self):
        """was_forwarded(expired) should also evict the key."""
        c = RecentCache(ttl=0.05)
        c.mark_forwarded(b'soon gone')
        time.sleep(0.1)
        self.assertFalse(c.was_forwarded(b'soon gone'))
        self.assertEqual(c.size, 0)

    # ── capacity cap ───────────────────────────────────────────────────────

    def test_size_capped_at_max(self):
        c = RecentCache(ttl=60.0, max_size=10)
        for i in range(20):
            c.mark_forwarded(f'packet-{i:04d}'.encode())
        self.assertLessEqual(c.size, 10)

    def test_oldest_evicted_when_over_capacity(self):
        """After overflow, the earliest-inserted packet should be gone."""
        c = RecentCache(ttl=60.0, max_size=3)
        c.mark_forwarded(b'first')
        c.mark_forwarded(b'second')
        c.mark_forwarded(b'third')
        # All three in cache
        self.assertTrue(c.was_forwarded(b'first'))
        self.assertTrue(c.was_forwarded(b'second'))
        self.assertTrue(c.was_forwarded(b'third'))
        # Adding a fourth evicts 'first'
        c.mark_forwarded(b'fourth')
        self.assertFalse(c.was_forwarded(b'first'))
        self.assertTrue(c.was_forwarded(b'fourth'))

    # ── digest fingerprint stability ────────────────────────────────────────

    def test_digest_is_deterministic(self):
        """Same data → same fingerprint → cache hit across calls."""
        c = RecentCache(ttl=1.0)
        payload = b'\x00' * 64 + b'\xff' * 64
        c.mark_forwarded(payload)
        self.assertTrue(c.was_forwarded(payload))

    def test_prefix_only_matters(self):
        """Cache fingerprints only the first 64 bytes — two packets with the
        same first 64 bytes but different tails collide (this is by design:
        the 256-byte cell header prefix is unique for real MNCA cells)."""
        c = RecentCache(ttl=1.0)
        base = b'A' * 64
        pkt_a = base + b'tail_A' * 100
        pkt_b = base + b'tail_B' * 100
        c.mark_forwarded(pkt_a)
        # pkt_b shares the same 64-byte prefix → cache collision → detected
        self.assertTrue(c.was_forwarded(pkt_b))

    def test_1byte_difference_in_prefix_not_collide(self):
        """One byte changed in the first 64 → different digest → not blocked."""
        c = RecentCache(ttl=1.0)
        pkt_a = bytes(range(64))
        pkt_b = bytearray(range(64))
        pkt_b[32] ^= 0xFF  # flip one bit
        c.mark_forwarded(pkt_a)
        self.assertFalse(c.was_forwarded(bytes(pkt_b)))

    # ── idempotent mark ─────────────────────────────────────────────────────

    def test_double_mark_does_not_double_size(self):
        """Marking the same packet twice is idempotent (size stays 1)."""
        c = RecentCache(ttl=1.0)
        c.mark_forwarded(b'same packet')
        c.mark_forwarded(b'same packet')
        self.assertEqual(c.size, 1)

    def test_double_mark_refreshes_timestamp(self):
        """Re-marking a packet after half-TTL resets its expiry clock."""
        c = RecentCache(ttl=0.1)
        data = b'refreshing packet'
        c.mark_forwarded(data)
        time.sleep(0.07)           # past half-TTL
        c.mark_forwarded(data)     # re-mark (refreshes)
        time.sleep(0.07)           # would have expired if not refreshed
        self.assertTrue(c.was_forwarded(data))


class TestParseArgs(unittest.TestCase):
    """Smoke-test the CLI parser without touching sockets."""

    def setUp(self):
        self.parse_args = _mod.parse_args

    def test_defaults(self):
        args = self.parse_args([])
        self.assertEqual(args.group, 'ff15:4ed1:aabd:873d:e970:0000:0000:0000')
        self.assertEqual(args.port, 47100)
        self.assertEqual(args.local_iface, 'lo0')
        self.assertEqual(args.hops, 1)
        self.assertAlmostEqual(args.cache_ttl, 2.0)

    def test_overrides(self):
        args = self.parse_args([
            '--group', 'ff15:60d4:edd5:7b2a:8222:0000:0000:0000',
            '--port', '47200',
            '--local-iface', 'lo',
            '--wan-iface', 'end0',
            '--hops', '2',
            '--cache-ttl', '5.0',
        ])
        self.assertEqual(args.group, 'ff15:60d4:edd5:7b2a:8222:0000:0000:0000')
        self.assertEqual(args.port, 47200)
        self.assertEqual(args.local_iface, 'lo')
        self.assertEqual(args.wan_iface, 'end0')
        self.assertEqual(args.hops, 2)
        self.assertAlmostEqual(args.cache_ttl, 5.0)


if __name__ == '__main__':
    unittest.main(verbosity=2)

```
