---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/map.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.408587+00:00
---

# packages/games/src/risk/map.ts

```ts
/**
 * Classic Risk Map — 42 territories, 6 continents.
 *
 * Territory IDs 0-41 map to the classic Risk board.
 * Adjacency is bidirectional (stored once, queried both ways).
 */

// ── Territory Definitions ───────────────────────────────────────

export interface TerritoryDef {
  id: number;
  name: string;
  continent: ContinentName;
  abbr: string; // 3-letter abbreviation for display
}

export type ContinentName =
  | 'North America'
  | 'South America'
  | 'Europe'
  | 'Africa'
  | 'Asia'
  | 'Australia';

export interface ContinentDef {
  name: ContinentName;
  bonus: number;
  territories: number[];
}

// ── Territory List (classic Risk board) ─────────────────────────

export const TERRITORIES: TerritoryDef[] = [
  // North America (0-8)
  { id: 0,  name: 'Alaska',              continent: 'North America', abbr: 'ALS' },
  { id: 1,  name: 'Northwest Territory', continent: 'North America', abbr: 'NWT' },
  { id: 2,  name: 'Greenland',           continent: 'North America', abbr: 'GRL' },
  { id: 3,  name: 'Alberta',             continent: 'North America', abbr: 'ALB' },
  { id: 4,  name: 'Ontario',             continent: 'North America', abbr: 'ONT' },
  { id: 5,  name: 'Quebec',              continent: 'North America', abbr: 'QUE' },
  { id: 6,  name: 'Western US',          continent: 'North America', abbr: 'WUS' },
  { id: 7,  name: 'Eastern US',          continent: 'North America', abbr: 'EUS' },
  { id: 8,  name: 'Central America',     continent: 'North America', abbr: 'CAM' },

  // South America (9-12)
  { id: 9,  name: 'Venezuela',           continent: 'South America', abbr: 'VEN' },
  { id: 10, name: 'Peru',                continent: 'South America', abbr: 'PER' },
  { id: 11, name: 'Brazil',              continent: 'South America', abbr: 'BRZ' },
  { id: 12, name: 'Argentina',           continent: 'South America', abbr: 'ARG' },

  // Europe (13-19)
  { id: 13, name: 'Iceland',             continent: 'Europe',        abbr: 'ICE' },
  { id: 14, name: 'Scandinavia',         continent: 'Europe',        abbr: 'SCN' },
  { id: 15, name: 'Great Britain',       continent: 'Europe',        abbr: 'GBR' },
  { id: 16, name: 'Northern Europe',     continent: 'Europe',        abbr: 'NEU' },
  { id: 17, name: 'Western Europe',      continent: 'Europe',        abbr: 'WEU' },
  { id: 18, name: 'Southern Europe',     continent: 'Europe',        abbr: 'SEU' },
  { id: 19, name: 'Ukraine',             continent: 'Europe',        abbr: 'UKR' },

  // Africa (20-25)
  { id: 20, name: 'North Africa',        continent: 'Africa',        abbr: 'NAF' },
  { id: 21, name: 'Egypt',               continent: 'Africa',        abbr: 'EGY' },
  { id: 22, name: 'East Africa',         continent: 'Africa',        abbr: 'EAF' },
  { id: 23, name: 'Congo',               continent: 'Africa',        abbr: 'CON' },
  { id: 24, name: 'South Africa',        continent: 'Africa',        abbr: 'SAF' },
  { id: 25, name: 'Madagascar',          continent: 'Africa',        abbr: 'MAD' },

  // Asia (26-37)
  { id: 26, name: 'Ural',                continent: 'Asia',          abbr: 'URL' },
  { id: 27, name: 'Siberia',             continent: 'Asia',          abbr: 'SIB' },
  { id: 28, name: 'Yakutsk',             continent: 'Asia',          abbr: 'YAK' },
  { id: 29, name: 'Kamchatka',           continent: 'Asia',          abbr: 'KAM' },
  { id: 30, name: 'Irkutsk',             continent: 'Asia',          abbr: 'IRK' },
  { id: 31, name: 'Mongolia',            continent: 'Asia',          abbr: 'MON' },
  { id: 32, name: 'Japan',               continent: 'Asia',          abbr: 'JPN' },
  { id: 33, name: 'Afghanistan',         continent: 'Asia',          abbr: 'AFG' },
  { id: 34, name: 'China',               continent: 'Asia',          abbr: 'CHN' },
  { id: 35, name: 'India',               continent: 'Asia',          abbr: 'IND' },
  { id: 36, name: 'Siam',                continent: 'Asia',          abbr: 'SIA' },
  { id: 37, name: 'Middle East',         continent: 'Asia',          abbr: 'MDE' },

  // Australia (38-41)
  { id: 38, name: 'Indonesia',           continent: 'Australia',     abbr: 'IND' },
  { id: 39, name: 'New Guinea',          continent: 'Australia',     abbr: 'NGU' },
  { id: 40, name: 'Western Australia',   continent: 'Australia',     abbr: 'WAU' },
  { id: 41, name: 'Eastern Australia',   continent: 'Australia',     abbr: 'EAU' },
];

// ── Continents ──────────────────────────────────────────────────

export const CONTINENTS: ContinentDef[] = [
  { name: 'North America', bonus: 5, territories: [0, 1, 2, 3, 4, 5, 6, 7, 8] },
  { name: 'South America', bonus: 2, territories: [9, 10, 11, 12] },
  { name: 'Europe',        bonus: 5, territories: [13, 14, 15, 16, 17, 18, 19] },
  { name: 'Africa',        bonus: 3, territories: [20, 21, 22, 23, 24, 25] },
  { name: 'Asia',          bonus: 7, territories: [26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37] },
  { name: 'Australia',     bonus: 2, territories: [38, 39, 40, 41] },
];

// ── Adjacency ───────────────────────────────────────────────────
// Stored as pairs [a, b] meaning a <-> b. Both directions are valid.

const ADJACENCY_PAIRS: [number, number][] = [
  // North America internal
  [0, 1], [0, 3],            // Alaska
  [1, 2], [1, 3], [1, 4],   // NW Territory
  [2, 4], [2, 5],           // Greenland
  [3, 4], [3, 6],           // Alberta
  [4, 5], [4, 6], [4, 7],   // Ontario
  [5, 7],                    // Quebec
  [6, 7], [6, 8],           // Western US
  [7, 8],                    // Eastern US

  // North America ↔ South America
  [8, 9],                    // Central America ↔ Venezuela

  // South America internal
  [9, 10], [9, 11],         // Venezuela
  [10, 11], [10, 12],       // Peru
  [11, 12],                  // Brazil

  // South America ↔ Africa
  [11, 20],                  // Brazil ↔ North Africa

  // North America ↔ Europe
  [2, 13],                   // Greenland ↔ Iceland

  // Europe internal
  [13, 14], [13, 15],       // Iceland
  [14, 15], [14, 16], [14, 19], // Scandinavia
  [15, 16], [15, 17],       // Great Britain
  [16, 17], [16, 18], [16, 19], // Northern Europe
  [17, 18], [17, 20],       // Western Europe ↔ N. Africa
  [18, 19], [18, 20], [18, 21], [18, 37], // Southern Europe

  // Europe ↔ Asia
  [19, 26], [19, 33], [19, 37], // Ukraine

  // Africa internal
  [20, 21], [20, 22], [20, 23], // North Africa
  [21, 22], [21, 37],       // Egypt ↔ Middle East
  [22, 23], [22, 24], [22, 25], // East Africa
  [23, 24],                  // Congo
  [24, 25],                  // South Africa

  // Asia internal
  [26, 27], [26, 33], [26, 34], // Ural
  [27, 28], [27, 30], [27, 31], [27, 34], // Siberia
  [28, 29], [28, 30],       // Yakutsk
  [29, 30], [29, 31], [29, 32], // Kamchatka
  [30, 31],                  // Irkutsk
  [31, 32], [31, 34],       // Mongolia
  [33, 34], [33, 35], [33, 37], // Afghanistan
  [34, 35], [34, 36],       // China
  [35, 36], [35, 37],       // India
  [36, 38],                  // Siam ↔ Indonesia

  // Asia ↔ North America
  [29, 0],                   // Kamchatka ↔ Alaska

  // Australia internal
  [38, 39], [38, 40],       // Indonesia
  [39, 41],                  // New Guinea
  [40, 41],                  // W. Australia ↔ E. Australia
];

// ── Precomputed adjacency map ───────────────────────────────────

const _adjacencyMap: Map<number, Set<number>> = new Map();

for (let i = 0; i < 42; i++) {
  _adjacencyMap.set(i, new Set());
}

for (const [a, b] of ADJACENCY_PAIRS) {
  _adjacencyMap.get(a)!.add(b);
  _adjacencyMap.get(b)!.add(a);
}

/** Get all territories adjacent to the given territory. */
export function getAdjacent(territory: number): ReadonlySet<number> {
  return _adjacencyMap.get(territory) ?? new Set();
}

/** Check if two territories are adjacent. */
export function areAdjacent(a: number, b: number): boolean {
  return _adjacencyMap.get(a)?.has(b) ?? false;
}

/** Check if there is a connected path between two territories owned by the same player. */
export function hasPath(
  from: number,
  to: number,
  owners: number[],
): boolean {
  const owner = owners[from];
  if (owners[to] !== owner) return false;

  const visited = new Set<number>();
  const queue = [from];
  visited.add(from);

  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current === to) return true;

    for (const neighbor of getAdjacent(current)) {
      if (!visited.has(neighbor) && owners[neighbor] === owner) {
        visited.add(neighbor);
        queue.push(neighbor);
      }
    }
  }

  return false;
}

```
