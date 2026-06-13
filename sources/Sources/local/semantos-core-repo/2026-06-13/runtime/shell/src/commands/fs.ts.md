---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/fs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.373623+00:00
---

# runtime/shell/src/commands/fs.ts

```ts
/**
 * `semantos fs` subcommands — taxonomy-aware filesystem operations.
 *
 * All commands delegate to SemanticFS. Output is formatted for terminal
 * by default; use --json for structured JSON output.
 *
 * Cross-references:
 *   protocol-types/src/semantic-fs.ts   → SemanticFS class
 *   protocol-types/src/cell-store.ts    → CellRef, CellValue
 *   shell/src/index.ts                  → wires SemanticFS into ShellContext
 */

import type { SemanticFS } from '@semantos/protocol-types';
import type { CellRef } from '@semantos/protocol-types';

/**
 * Route `semantos fs <subcommand>` to the appropriate SemanticFS method.
 */
export async function handleFs(
  args: string[],
  semanticFs: SemanticFS | undefined,
): Promise<string> {
  if (!semanticFs) {
    return 'Error: SemanticFS not initialized. Storage adapter may not be available.';
  }

  const subcommand = args[0];
  const isJson = args.includes('--json');
  const filteredArgs = args.filter(a => a !== '--json');

  switch (subcommand) {
    case 'ls':
      return handleLs(filteredArgs.slice(1), semanticFs, isJson);
    case 'cat':
      return handleCat(filteredArgs.slice(1), semanticFs, isJson);
    case 'stat':
      return handleStat(filteredArgs.slice(1), semanticFs, isJson);
    case 'history':
      return handleHistory(filteredArgs.slice(1), semanticFs, isJson);
    case 'find':
      return handleFind(filteredArgs.slice(1), semanticFs, isJson);
    case 'verify':
      return handleVerify(filteredArgs.slice(1), semanticFs, isJson);
    case 'search':
      return handleSearch(filteredArgs.slice(1), semanticFs, isJson);
    default:
      return [
        'Usage: semantos fs <subcommand> [options]',
        '',
        'Subcommands:',
        '  ls <path>             List objects under path',
        '  cat <path>            Display latest version payload',
        '  stat <path>           Show cell metadata',
        '  history <path>        Show version chain',
        '  find --content <hash> Find by content hash',
        '  find --type <type>    Find by taxonomy type',
        '  verify <path>         Verify Merkle chain integrity',
        '  search <query>        Semantic search (embedding-enhanced)',
        '',
        'Options:',
        '  --json                Output as JSON',
      ].join('\n');
  }
}

async function handleLs(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const path = args[0] ?? 'objects';
  const depthFlag = args.indexOf('--depth');
  const depth = depthFlag !== -1 ? parseInt(args[depthFlag + 1], 10) : undefined;

  const refs = await fs.list(path, depth !== undefined ? { depth } : undefined);

  if (json) return JSON.stringify(refs, null, 2);

  if (refs.length === 0) return `(empty) ${path}`;

  const lines = refs.map(r => {
    const name = r.key.split('/').pop() ?? r.key;
    return `${name}  v${r.version}  ${r.contentHash.slice(0, 12)}...  ${new Date(r.timestamp).toISOString()}`;
  });
  return lines.join('\n');
}

async function handleCat(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Usage: semantos fs cat <path>';

  const cell = await fs.get(path);
  if (!cell) return `Not found: ${path}`;

  const text = new TextDecoder().decode(cell.payload);

  if (json) {
    return JSON.stringify({ path, version: cell.version, contentHash: cell.contentHash, payload: text }, null, 2);
  }
  return text;
}

async function handleStat(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Usage: semantos fs stat <path>';

  const cell = await fs.get(path);
  if (!cell) return `Not found: ${path}`;

  const stat = {
    path,
    cellHash: cell.cellHash,
    contentHash: cell.contentHash,
    version: cell.version,
    timestamp: cell.timestamp,
    linearity: cell.linearity,
    size: cell.payload.length,
    flags: cell.header.flags,
    cellCount: cell.header.cellCount,
    totalSize: cell.header.totalSize,
  };

  if (json) return JSON.stringify(stat, null, 2);

  return [
    `Path:        ${path}`,
    `Cell Hash:   ${stat.cellHash}`,
    `Content:     ${stat.contentHash}`,
    `Version:     ${stat.version}`,
    `Timestamp:   ${new Date(stat.timestamp).toISOString()}`,
    `Linearity:   ${stat.linearity}`,
    `Size:        ${stat.size} bytes`,
    `Flags:       0x${stat.flags.toString(16).padStart(4, '0')}`,
    `Cell Count:  ${stat.cellCount}`,
    `Total Size:  ${stat.totalSize}`,
  ].join('\n');
}

async function handleHistory(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Usage: semantos fs history <path>';

  const refs = await fs.history(path);
  if (refs.length === 0) return `No history: ${path}`;

  if (json) return JSON.stringify(refs, null, 2);

  const lines = refs.map(r =>
    `v${r.version}  ${r.cellHash.slice(0, 12)}...  ${r.contentHash.slice(0, 12)}...  ${new Date(r.timestamp).toISOString()}`,
  );
  return lines.join('\n');
}

async function handleFind(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const contentIdx = args.indexOf('--content');
  const typeIdx = args.indexOf('--type');

  let refs: CellRef[];

  if (contentIdx !== -1 && args[contentIdx + 1]) {
    refs = await fs.findByContent(args[contentIdx + 1]);
  } else if (typeIdx !== -1 && args[typeIdx + 1]) {
    refs = await fs.queryByType(args[typeIdx + 1]);
  } else {
    return 'Usage: semantos fs find --content <hash> | --type <taxonomy-path>';
  }

  if (json) return JSON.stringify(refs, null, 2);

  if (refs.length === 0) return '(no results)';
  return refs.map(r => `${r.key}  v${r.version}  ${r.contentHash.slice(0, 12)}...`).join('\n');
}

async function handleVerify(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Usage: semantos fs verify <path>';

  const result = await fs.verify(path);

  if (json) return JSON.stringify(result, null, 2);

  if (result.valid) return `✓ Merkle chain intact for ${path}`;
  return [`✗ Verification failed for ${path}:`, ...result.errors.map(e => `  - ${e}`)].join('\n');
}

async function handleSearch(
  args: string[],
  fs: SemanticFS,
  json: boolean,
): Promise<string> {
  // Collect query (everything except --limit N)
  const limitIdx = args.indexOf('--limit');
  let limit: number | undefined;
  const queryParts: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--limit' && args[i + 1]) {
      limit = parseInt(args[i + 1], 10);
      i++; // skip value
    } else {
      queryParts.push(args[i]);
    }
  }

  const query = queryParts.join(' ');
  if (!query) return 'Usage: semantos fs search <query> [--limit N]';

  const results = await fs.semanticSearch(query, limit ? { limit } : undefined);

  if (json) return JSON.stringify(results, null, 2);

  if (results.length === 0) return '(no results — embeddings may not be ready)';
  return results.map(r =>
    `${r.matchedPath} (${(r.score * 100).toFixed(1)}%)  ${r.key}  v${r.version}`,
  ).join('\n');
}

```
