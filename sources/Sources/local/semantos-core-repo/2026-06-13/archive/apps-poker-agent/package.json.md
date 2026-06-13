---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.689607+00:00
---

# archive/apps-poker-agent/package.json

```json
{
  "name": "@semantos/poker-agent",
  "version": "0.1.0",
  "description": "Claude-powered poker agents with BSV on-chain state anchoring",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": {
    "match": "bun run ../../scripts/poker-match.ts",
    "match:fast": "bun run ../../scripts/poker-match.ts --fast --no-anchor"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.39.0",
    "@semantos/cell-engine": "workspace:*",
    "@semantos/session-protocol": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13"
  },
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  }
}

```
