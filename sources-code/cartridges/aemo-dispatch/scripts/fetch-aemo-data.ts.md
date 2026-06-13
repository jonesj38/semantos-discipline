---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/fetch-aemo-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.572729+00:00
---

# cartridges/aemo-dispatch/scripts/fetch-aemo-data.ts

```ts
#!/usr/bin/env bun
// Real AEMO NEM dispatch-price scraper.
//
// AEMO publishes monthly CSVs at:
//   https://aemo.com.au/aemo/data/nem/priceanddemand/
//     PRICE_AND_DEMAND_<YYYYMM>_<REGION>.csv
//
// CSV columns: REGION,SETTLEMENTDATE,TOTALDEMAND,RRP,PERIODTYPE
//   • SETTLEMENTDATE — local NEM time (AEST, UTC+10, no DST)
//   • RRP            — Regional Reference Price in $/MWh
//   • TOTALDEMAND    — MW
//
// Output: stdout CSV in our backtest format:
//   timestamp,priceCents
//
// Cache: files land at ~/.cache/aemo-dispatch/ — second runs read from
// cache without re-fetching.
//
// Usage:
//   bun fetch-aemo-data.ts --region NSW1 --from 2024-01 --to 2024-06 > nsw1_h1_2024.csv
//   bun fetch-aemo-data.ts --region VIC1 --from 2023-07 --to 2024-06 --to-stdout > vic1_year.csv
//
// Regions:
//   NSW1 — New South Wales (and ACT)
//   VIC1 — Victoria
//   QLD1 — Queensland
//   SA1  — South Australia
//   TAS1 — Tasmania

import { promises as fs } from 'fs';
import * as path from 'path';
import * as os from 'os';

const REGIONS = ['NSW1', 'VIC1', 'QLD1', 'SA1', 'TAS1'] as const;
type Region = typeof REGIONS[number];

interface Args {
  region: Region;
  fromYm: { y: number; m: number };
  toYm: { y: number; m: number };
  cacheDir: string;
}

function parseArgs(argv: string[]): Args {
  let region: Region = 'NSW1';
  let fromYm = { y: 2024, m: 1 };
  let toYm = { y: 2024, m: 12 };
  const cacheDir = path.join(os.homedir(), '.cache', 'aemo-dispatch');

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--region') {
      const r = (argv[++i] ?? '').toUpperCase();
      if (!REGIONS.includes(r as Region)) {
        die(`unknown region: ${r}; valid = ${REGIONS.join(',')}`);
      }
      region = r as Region;
    } else if (a === '--from') {
      fromYm = parseYearMonth(argv[++i] ?? '');
    } else if (a === '--to') {
      toYm = parseYearMonth(argv[++i] ?? '');
    } else if (a === '--help' || a === '-h') {
      console.error('usage: bun fetch-aemo-data.ts --region NSW1 --from 2024-01 --to 2024-06');
      process.exit(0);
    } else {
      die(`unknown arg: ${a}`);
    }
  }
  return { region, fromYm, toYm, cacheDir };
}

function parseYearMonth(s: string): { y: number; m: number } {
  const m = /^(\d{4})-(\d{1,2})$/.exec(s);
  if (!m) die(`bad year-month: "${s}" (expected YYYY-MM)`);
  const year = Number.parseInt(m![1]!, 10);
  const month = Number.parseInt(m![2]!, 10);
  if (month < 1 || month > 12) die(`bad month: ${month}`);
  return { y: year, m: month };
}

function die(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(2);
}

function* iterMonths(from: { y: number; m: number }, to: { y: number; m: number }) {
  let y = from.y;
  let m = from.m;
  while (y < to.y || (y === to.y && m <= to.m)) {
    yield { y, m };
    m++;
    if (m > 12) { m = 1; y++; }
  }
}

function fileNameFor(region: Region, ym: { y: number; m: number }): string {
  const mm = ym.m.toString().padStart(2, '0');
  return `PRICE_AND_DEMAND_${ym.y}${mm}_${region}.csv`;
}

async function fetchMonth(
  region: Region,
  ym: { y: number; m: number },
  cacheDir: string,
): Promise<string> {
  const fileName = fileNameFor(region, ym);
  const cachePath = path.join(cacheDir, fileName);
  try {
    const cached = await fs.readFile(cachePath, 'utf-8');
    if (cached.length > 0) {
      console.error(`[aemo] cache hit: ${fileName} (${cached.length} bytes)`);
      return cached;
    }
  } catch {
    // miss
  }
  const url = `https://aemo.com.au/aemo/data/nem/priceanddemand/${fileName}`;
  console.error(`[aemo] fetching ${url}`);
  const resp = await fetch(url);
  if (!resp.ok) {
    throw new Error(`AEMO ${resp.status}: ${url}`);
  }
  const text = await resp.text();
  await fs.mkdir(cacheDir, { recursive: true });
  await fs.writeFile(cachePath, text, 'utf-8');
  console.error(`[aemo] cached ${fileName} (${text.length} bytes)`);
  return text;
}

interface NemRow {
  timestamp: string; // ISO UTC
  priceCents: number;
}

/** Parse AEMO CSV into normalized rows.  SETTLEMENTDATE is in NEM
 *  local time (AEST = UTC+10, no DST observed by AEMO since 2021).
 *  Convert to UTC ISO for backtest consistency. */
function parseAemoCsv(text: string): NemRow[] {
  const lines = text.split(/\r?\n/);
  const out: NemRow[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    if (line.length === 0 || line.startsWith('REGION,')) continue;
    const parts = line.split(',');
    if (parts.length < 5) continue;
    const settlementDate = parts[1]!; // e.g. "2024/03/01 00:05:00"
    const rrpDollars = Number.parseFloat(parts[3]!);
    if (!Number.isFinite(rrpDollars)) continue;
    // Convert NEM local time (UTC+10) to UTC.
    // settlementDate is in NEM time: "YYYY/MM/DD HH:MM:SS"
    const m = /^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(settlementDate);
    if (!m) continue;
    const ms = Date.UTC(
      Number.parseInt(m[1]!, 10),
      Number.parseInt(m[2]!, 10) - 1,
      Number.parseInt(m[3]!, 10),
      Number.parseInt(m[4]!, 10),
      Number.parseInt(m[5]!, 10),
      Number.parseInt(m[6]!, 10),
    ) - 10 * 3600 * 1000; // subtract AEST offset
    const iso = new Date(ms).toISOString();
    // Round to integer cents.  Real AEMO RRP supports cents precision.
    const priceCents = Math.round(rrpDollars * 100);
    out.push({ timestamp: iso, priceCents });
  }
  return out;
}

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  console.error(`[aemo] region: ${args.region}`);
  console.error(`[aemo] range:  ${args.fromYm.y}-${args.fromYm.m.toString().padStart(2, '0')} to ${args.toYm.y}-${args.toYm.m.toString().padStart(2, '0')}`);
  console.error(`[aemo] cache:  ${args.cacheDir}`);

  console.log('timestamp,priceCents');
  let total = 0;
  for (const ym of iterMonths(args.fromYm, args.toYm)) {
    const csv = await fetchMonth(args.region, ym, args.cacheDir);
    const rows = parseAemoCsv(csv);
    for (const r of rows) {
      console.log(`${r.timestamp},${r.priceCents}`);
    }
    total += rows.length;
  }
  console.error(`[aemo] wrote ${total} rows`);
  return 0;
}

const code = await main();
process.exit(code);

```
