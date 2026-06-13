---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/mnca-srv6.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.853573+00:00
---

# core/protocol-types/__tests__/mnca-srv6.test.ts

```ts
/**
 * SNS multicast-group derivation conformance tests.
 *
 * Pins the known-answer IPv6 multicast group addresses derived from MNCA
 * type axes (Phase 34A formula). These addresses go in `multicast.group`
 * in mesh-node configs — a change here means a node on the old group
 * stops receiving cells from nodes on the new group (routing break).
 *
 * D-SRS deliverable: D-SRS-sns-multicast-wire.
 */
import { describe, expect, test } from 'bun:test';
import {
  deriveMulticastGroup,
  multicastGroupForMncaType,
  whatPrefixGroup,
  MNCA_TYPE_AXES,
  MNCA_MULTICAST_GROUPS,
  MNCA_TILE_WHAT_PREFIX_GROUP,
  MNCA_TILE_TICK_GROUP,
} from '../src/mnca/srv6';
import { MncaCellTypeName, MNCA_CELL_TYPE_NAMES } from '../src/mnca/cell-types';

// ── deriveMulticastGroup ──────────────────────────────────────────────────────

describe('deriveMulticastGroup', () => {
  test('produces a valid ff15 multicast address (8 colon-groups)', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    expect(g).toMatch(/^ff15:/);
    expect(g.split(':').length).toBe(8);
  });

  test('pinned: mnca.tile / tick → correct group', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    expect(g).toBe('ff15:4ed1:aabd:873d:e970:0000:0000:0000');
  });

  test('pinned: mnca.tile / v0 → correct group', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca.tile', how: 'v0' });
    expect(g).toBe('ff15:4ed1:aabd:e05d:07d2:0000:0000:0000');
  });

  test('pinned: mnca.tile / injection → correct group', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca.tile', how: 'injection' });
    expect(g).toBe('ff15:4ed1:aabd:52a2:420c:0000:0000:0000');
  });

  test('pinned: mnca / snapshot → correct group', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca', how: 'snapshot' });
    expect(g).toBe('ff15:60d4:edd5:7b2a:8222:0000:0000:0000');
  });

  test('pinned: mnca / perturb → correct group', async () => {
    const g = await deriveMulticastGroup({ what: 'mnca', how: 'perturb' });
    expect(g).toBe('ff15:60d4:edd5:1064:77f5:0000:0000:0000');
  });

  test('TILE_TICK, TILE, TILE_INJECTION share the same WHAT prefix', async () => {
    const [tick, v0, inj] = await Promise.all([
      deriveMulticastGroup({ what: 'mnca.tile', how: 'tick'      }),
      deriveMulticastGroup({ what: 'mnca.tile', how: 'v0'        }),
      deriveMulticastGroup({ what: 'mnca.tile', how: 'injection' }),
    ]);
    // First 3 colon-groups: "ff15:WHAT_HI:WHAT_LO"
    const whatPrefix = (g: string) => g.split(':').slice(0, 3).join(':');
    expect(whatPrefix(tick)).toBe(whatPrefix(v0));
    expect(whatPrefix(tick)).toBe(whatPrefix(inj));
  });

  test('SNAPSHOT and PERTURB share a different WHAT prefix (mnca vs mnca.tile)', async () => {
    const [snap, pert] = await Promise.all([
      deriveMulticastGroup({ what: 'mnca', how: 'snapshot' }),
      deriveMulticastGroup({ what: 'mnca', how: 'perturb'  }),
    ]);
    const whatPrefix = (g: string) => g.split(':').slice(0, 3).join(':');
    expect(whatPrefix(snap)).toBe(whatPrefix(pert));

    const tickWP = (await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' })).split(':').slice(0, 3).join(':');
    // mnca ≠ mnca.tile at the WHAT level
    expect(whatPrefix(snap)).not.toBe(tickWP);
  });

  test('distinct HOW slugs under the same WHAT produce distinct groups', async () => {
    const [tick, v0, inj] = await Promise.all([
      deriveMulticastGroup({ what: 'mnca.tile', how: 'tick'      }),
      deriveMulticastGroup({ what: 'mnca.tile', how: 'v0'        }),
      deriveMulticastGroup({ what: 'mnca.tile', how: 'injection' }),
    ]);
    expect(new Set([tick, v0, inj]).size).toBe(3);
  });

  test('scope byte 0x03 (realm-local) changes only the first byte-pair', async () => {
    const g15 = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' }, 0x15);
    const g03 = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' }, 0x03);
    expect(g15.startsWith('ff15:')).toBe(true);
    expect(g03.startsWith('ff03:')).toBe(true);
    // All bits after the scope byte are identical
    expect(g15.slice('ff15'.length)).toBe(g03.slice('ff03'.length));
  });

  test('INST absent → INST groups (indices 5,6) and trailing group (7) are 0000', async () => {
    // Address layout: ff<sc>:WHAT_HI:WHAT_LO:HOW_HI:HOW_LO:INST_HI:INST_LO:0000
    //                   [0]    [1]     [2]     [3]    [4]    [5]     [6]     [7]
    const g = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    const parts = g.split(':');
    // HOW_LO (parts[4]) is non-zero when HOW is set — that's expected.
    // Only INST and trailing are zero when INST is absent.
    expect(parts[5]).toBe('0000');
    expect(parts[6]).toBe('0000');
    expect(parts[7]).toBe('0000');
  });

  test('INST present → INST bits differ from zeros, WHAT+HOW bits unchanged', async () => {
    const noInst   = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    const withInst = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick', inst: 'demo.v1' });
    // Different overall
    expect(noInst).not.toBe(withInst);
    // WHAT+HOW prefix (groups 0-4: scope+WHAT_HI+WHAT_LO+HOW_HI+HOW_LO) must match
    const whatHowPrefix = (g: string) => g.split(':').slice(0, 5).join(':');
    expect(whatHowPrefix(noInst)).toBe(whatHowPrefix(withInst));
    // INST bits (groups 5,6) change when inst is set
    const instPart = (g: string) => g.split(':').slice(5, 7).join(':');
    expect(instPart(withInst)).not.toBe('0000:0000');
  });

  test('derivation is deterministic across calls', async () => {
    const a = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    const b = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
    expect(a).toBe(b);
  });
});

// ── multicastGroupForMncaType ─────────────────────────────────────────────────

describe('multicastGroupForMncaType', () => {
  test('all canonical MNCA types resolve to their pinned known-answer group', async () => {
    for (const name of MNCA_CELL_TYPE_NAMES) {
      const g = await multicastGroupForMncaType(name);
      expect(g).toBe(MNCA_MULTICAST_GROUPS[name]);
    }
  });

  test('TILE_TICK_GROUP constant matches live derivation', async () => {
    const live = await multicastGroupForMncaType(MncaCellTypeName.TILE_TICK);
    expect(live).toBe(MNCA_TILE_TICK_GROUP);
  });

  test('all five MNCA types produce distinct groups', async () => {
    const groups = await Promise.all(MNCA_CELL_TYPE_NAMES.map((n) => multicastGroupForMncaType(n)));
    expect(new Set(groups).size).toBe(MNCA_CELL_TYPE_NAMES.length);
  });
});

// ── whatPrefixGroup ───────────────────────────────────────────────────────────

describe('whatPrefixGroup', () => {
  test('mnca.tile prefix is the pinned MNCA_TILE_WHAT_PREFIX_GROUP constant', async () => {
    const g = await whatPrefixGroup('mnca.tile');
    expect(g).toBe(MNCA_TILE_WHAT_PREFIX_GROUP);
    expect(g).toBe('ff15:4ed1:aabd::');
  });

  test('mnca.tile WHAT prefix is a proper prefix of all three tile type groups', async () => {
    // "ff15:4ed1:aabd::" → the prefix up to HOW starts at "ff15:4ed1:aabd:"
    const tileGroups = [
      MNCA_MULTICAST_GROUPS[MncaCellTypeName.TILE_TICK],
      MNCA_MULTICAST_GROUPS[MncaCellTypeName.TILE],
      MNCA_MULTICAST_GROUPS[MncaCellTypeName.TILE_INJECTION],
    ];
    for (const g of tileGroups) {
      expect(g.startsWith('ff15:4ed1:aabd:')).toBe(true);
    }
  });

  test('mnca.tile and mnca WHAT prefixes are distinct', async () => {
    const tilePrefix = await whatPrefixGroup('mnca.tile');
    const mncaPrefix = await whatPrefixGroup('mnca');
    expect(tilePrefix).not.toBe(mncaPrefix);
  });

  test('prefix ends with :: (zero-compressed tail)', async () => {
    const g = await whatPrefixGroup('mnca.tile');
    expect(g).toMatch(/::$/);
  });
});

// ── MNCA_TYPE_AXES ────────────────────────────────────────────────────────────

describe('MNCA_TYPE_AXES', () => {
  test('every canonical MNCA type has a declared axis entry with non-empty what and how', () => {
    for (const name of MNCA_CELL_TYPE_NAMES) {
      const axes = MNCA_TYPE_AXES[name];
      expect(axes).toBeDefined();
      expect(axes!.what).toBeTruthy();
      expect(axes!.how).toBeTruthy();
    }
  });

  test('all three tile types declare what=mnca.tile (shared WHAT group)', () => {
    expect(MNCA_TYPE_AXES[MncaCellTypeName.TILE_TICK]!.what).toBe('mnca.tile');
    expect(MNCA_TYPE_AXES[MncaCellTypeName.TILE]!.what).toBe('mnca.tile');
    expect(MNCA_TYPE_AXES[MncaCellTypeName.TILE_INJECTION]!.what).toBe('mnca.tile');
  });

  test('top-level MNCA types (snapshot, perturb) declare what=mnca', () => {
    expect(MNCA_TYPE_AXES[MncaCellTypeName.SNAPSHOT]!.what).toBe('mnca');
    expect(MNCA_TYPE_AXES[MncaCellTypeName.PERTURB]!.what).toBe('mnca');
  });
});

```
