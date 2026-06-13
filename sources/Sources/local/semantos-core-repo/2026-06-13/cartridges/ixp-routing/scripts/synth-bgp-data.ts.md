---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/scripts/synth-bgp-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.558931+00:00
---

# cartridges/ixp-routing/scripts/synth-bgp-data.ts

```ts
#!/usr/bin/env bun
// Synthetic BGP route-advertisement event generator for IXP routing backtest.
//
// Generates a realistic 24-hour stream of BGP route advertisement events
// at a busy internet exchange point, with:
//   - 5000-8000 events per day (one event every ~10 seconds on average)
//   - Peer tier distribution modelling a real IXP membership:
//       tier-3 (15%): major CDNs and clouds (Cloudflare, Fastly, AWS, Akamai)
//       tier-2 (35%): verified ISPs with bilateral peering agreements
//       tier-1 (40%): smaller registered ASNs (RIPE/ARIN/APNIC confirmed)
//       tier-0 (10%): unknown / unregistered peers (BGP hijack signal)
//   - Prefix distribution modelling real BGP RIB composition:
//       /24 backbone (most common, legitimate)
//       /20-/28 range (datacenter prefixes, CDN anycast)
//       /8-/15 (suspicious super-aggregates, only from known-bad-pattern peers)
//   - Three "incident windows" where tier-0 peers flood super-aggregates
//     (BGP hijack simulation), spaced through the day
//
// Output format: CSV with header
//   timestamp,eventId,asnTier,prefixLen,asn,prefix,peerLabel
//
// Usage:
//   bun synth-bgp-data.ts [--seed 42] [--events 6000] > bgp-events.csv
//   bun synth-bgp-data.ts --events 6000 --seed 99 > bgp-events.csv

// ─────────────────────────────────────────────────────────────────────
// Peer label pools per tier
// ─────────────────────────────────────────────────────────────────────

const TIER3_PEERS: Array<{ asn: string; label: string }> = [
  { asn: 'AS13335', label: 'Cloudflare' },
  { asn: 'AS16509', label: 'Amazon AWS' },
  { asn: 'AS15169', label: 'Google' },
  { asn: 'AS8075',  label: 'Microsoft Azure' },
  { asn: 'AS54113', label: 'Fastly' },
  { asn: 'AS20940', label: 'Akamai' },
  { asn: 'AS3320',  label: 'Deutsche Telekom' },
  { asn: 'AS1299',  label: 'Arelion (Telia)' },
];

const TIER2_PEERS: Array<{ asn: string; label: string }> = [
  { asn: 'AS1257', label: 'Tele2' },
  { asn: 'AS8468', label: 'Entanet' },
  { asn: 'AS2856', label: 'BT' },
  { asn: 'AS3549', label: 'GBLX' },
  { asn: 'AS6461', label: 'Zayo' },
  { asn: 'AS4637', label: 'Telstra' },
  { asn: 'AS7474', label: 'SingTel Optus' },
  { asn: 'AS9443', label: 'Internode' },
  { asn: 'AS4826', label: 'Vocus' },
  { asn: 'AS4739', label: 'iiNet' },
  { asn: 'AS7545', label: 'TPG' },
  { asn: 'AS38880', label: 'Murraycom' },
];

const TIER1_PEERS: Array<{ asn: string; label: string }> = [
  { asn: 'AS134944', label: 'SmallISP-AU' },
  { asn: 'AS55415',  label: 'NetConnect' },
  { asn: 'AS136557', label: 'Host-Networks' },
  { asn: 'AS45671',  label: 'PacificNet' },
  { asn: 'AS131072', label: 'CityFibre' },
  { asn: 'AS38193',  label: 'RedIX-ISP' },
  { asn: 'AS55430',  label: 'SkyDatacom' },
  { asn: 'AS137409', label: 'GreenCloud' },
  { asn: 'AS136891', label: 'WireFrame' },
  { asn: 'AS45671',  label: 'Archipelago' },
  { asn: 'AS131293', label: 'CorpNet-AU' },
  { asn: 'AS58952',  label: 'DataCenter-1' },
  { asn: 'AS59715',  label: 'UniNet' },
  { asn: 'AS134298', label: 'VicISP' },
];

const TIER0_PEERS: Array<{ asn: string; label: string }> = [
  { asn: 'AS65001', label: 'Unknown-ASN-1' },
  { asn: 'AS65002', label: 'Unknown-ASN-2' },
  { asn: 'AS65003', label: 'Ghost-Peer-A' },
  { asn: 'AS65004', label: 'Ghost-Peer-B' },
  { asn: 'AS65005', label: 'Unregistered-1' },
];

// ─────────────────────────────────────────────────────────────────────
// Prefix pools
// ─────────────────────────────────────────────────────────────────────

// Legitimate prefixes — /18 to /28, clustered around /24
function legit_prefix_len(rng: () => number): number {
  const r = rng();
  if (r < 0.05) return 18 + Math.floor(rng() * 3); // /18-/20 (broader but legit DC blocks)
  if (r < 0.10) return 28 + Math.floor(rng() * 5);  // /28-/32 (very specific, anycast)
  if (r < 0.40) return 20 + Math.floor(rng() * 4);  // /20-/23 (datacenter ranges)
  return 24 + Math.floor(rng() * 4);                  // /24-/27 (most common)
}

// Attack prefix — super-aggregate (/8-/15): takes over huge swaths
function attack_prefix_len(rng: () => number): number {
  return 8 + Math.floor(rng() * 8); // /8-/15
}

// Sample OCtet for prefix display
const OCTET1 = [10, 103, 104, 151, 152, 185, 188, 193, 195, 198, 203, 204, 212, 213, 217];

function rand_prefix(rng: () => number, prefixLen: number): string {
  const o1 = OCTET1[Math.floor(rng() * OCTET1.length)]!;
  const o2 = Math.floor(rng() * 256);
  const o3 = Math.floor(rng() * 256);
  const o4 = Math.floor(rng() * 256);
  return `${o1}.${o2}.${o3}.${o4}/${prefixLen}`;
}

// ─────────────────────────────────────────────────────────────────────
// PRNG (seeded, deterministic)
// ─────────────────────────────────────────────────────────────────────

function mulberry32(seed: number): () => number {
  let s = seed;
  return () => {
    s |= 0;
    s = s + 0x6d2b79f5 | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = t + Math.imul(t ^ (t >>> 7), 61 | t) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ─────────────────────────────────────────────────────────────────────
// Incident windows (three per day, spaced through the 24h period)
// Each incident: tier-0 peers flood super-aggregate routes for ~20 min
// ─────────────────────────────────────────────────────────────────────

const INCIDENT_WINDOWS = [
  { startFrac: 0.08, endFrac: 0.11 }, // ~2am UTC — low-traffic window (attacker's preferred)
  { startFrac: 0.38, endFrac: 0.41 }, // ~9am UTC — morning peak hijack attempt
  { startFrac: 0.74, endFrac: 0.77 }, // ~5:45pm UTC — end-of-day targeted disruption
];

function isIncident(timeFrac: number): boolean {
  return INCIDENT_WINDOWS.some(w => timeFrac >= w.startFrac && timeFrac < w.endFrac);
}

// ─────────────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────────────

interface Args {
  seed: number;
  events: number;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { seed: 42, events: 6200 };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--seed') a.seed = Number.parseInt(argv[++i] ?? '42', 10);
    else if (arg === '--events') a.events = Number.parseInt(argv[++i] ?? '6200', 10);
    else if (arg === '--help' || arg === '-h') {
      process.stderr.write('usage: bun synth-bgp-data.ts [--seed N] [--events N]\n');
      process.exit(0);
    }
  }
  return a;
}

// ─────────────────────────────────────────────────────────────────────
// Generate
// ─────────────────────────────────────────────────────────────────────

function main() {
  const args = parseArgs(process.argv.slice(2));
  const rng = mulberry32(args.seed);
  const totalEvents = args.events;

  // Base date: 2026-01-15T00:00:00Z (arbitrary; avoids leap-year edge cases)
  const dayStart = Date.UTC(2026, 0, 15, 0, 0, 0);
  const dayEnd = dayStart + 24 * 60 * 60 * 1000;
  const dayMs = dayEnd - dayStart;

  process.stdout.write('timestamp,eventId,asnTier,prefixLen,asn,prefix,peerLabel\n');

  for (let i = 0; i < totalEvents; i++) {
    // Distribute events uniformly through the day but with slight jitter
    const timeFrac = i / totalEvents + (rng() * 0.001 - 0.0005);
    const clampedFrac = Math.max(0, Math.min(0.9999, timeFrac));
    const tsMs = Math.floor(dayStart + clampedFrac * dayMs);
    const ts = new Date(tsMs).toISOString().replace('.000Z', 'Z');
    const eventId = `BGP-${(i + 1).toString().padStart(6, '0')}`;

    // During incident windows: 60% chance of a tier-0 attack event
    const incident = isIncident(clampedFrac);
    const attackRoll = rng();
    const isAttack = incident && attackRoll < 0.6;

    let asnTier: number;
    let peer: { asn: string; label: string };
    let prefixLen: number;

    if (isAttack) {
      asnTier = 0;
      peer = TIER0_PEERS[Math.floor(rng() * TIER0_PEERS.length)]!;
      prefixLen = attack_prefix_len(rng);
    } else {
      // Normal traffic — pick tier based on distribution
      const tierRoll = rng();
      if (tierRoll < 0.15) {
        asnTier = 3;
        peer = TIER3_PEERS[Math.floor(rng() * TIER3_PEERS.length)]!;
        // Tier-3 peers occasionally advertise broader prefixes (traffic engineering)
        prefixLen = rng() < 0.08 ? (11 + Math.floor(rng() * 5)) : legit_prefix_len(rng);
      } else if (tierRoll < 0.50) {
        asnTier = 2;
        peer = TIER2_PEERS[Math.floor(rng() * TIER2_PEERS.length)]!;
        prefixLen = legit_prefix_len(rng);
      } else if (tierRoll < 0.90) {
        asnTier = 1;
        peer = TIER1_PEERS[Math.floor(rng() * TIER1_PEERS.length)]!;
        prefixLen = legit_prefix_len(rng);
      } else {
        // Background tier-0 noise (non-incident, 10% of normal)
        asnTier = 0;
        peer = TIER0_PEERS[Math.floor(rng() * TIER0_PEERS.length)]!;
        // Background tier-0 tends to use more plausible (but still suspicious) prefixes
        prefixLen = rng() < 0.5 ? (14 + Math.floor(rng() * 4)) : legit_prefix_len(rng);
      }
    }

    const prefix = rand_prefix(rng, prefixLen);

    process.stdout.write(`${ts},${eventId},${asnTier},${prefixLen},${peer.asn},${prefix},${peer.label}\n`);
  }

  process.stderr.write(`[synth-bgp-data] generated ${totalEvents} events (seed=${args.seed})\n`);
  process.stderr.write(`[synth-bgp-data] incident windows: ${INCIDENT_WINDOWS.map(w => `${(w.startFrac * 24).toFixed(1)}h-${(w.endFrac * 24).toFixed(1)}h`).join(', ')}\n`);
}

main();

```
