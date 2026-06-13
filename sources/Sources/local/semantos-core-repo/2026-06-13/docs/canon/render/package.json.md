---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.758513+00:00
---

# docs/canon/render/package.json

```json
{
  "name": "@semantos/canon-render",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Renderers that turn docs/canon/*.yml into MD/LaTeX for the textbook, spec, and paper portfolio.",
  "scripts": {
    "glossary": "bun glossary-to-md.ts",
    "matrix": "bun matrix-to-roadmap.ts",
    "all": "bun glossary-to-md.ts && bun matrix-to-roadmap.ts"
  },
  "dependencies": {
    "yaml": "^2.6.0"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
