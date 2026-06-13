---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/release.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.593203+00:00
---

# .github/workflows/release.yml

```yml
name: release

on:
  push:
    branches: [main]

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-22.04
    permissions:
      contents: write
      packages: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: pnpm/action-setup@v4
        with:
          version: 10.9.0

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          registry-url: 'https://npm.pkg.github.com'
          scope: '@semantos'
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Build publish targets
        run: |
          pnpm run build
          pnpm -r --filter @semantos/cell-ops \
                  --filter @semantos/protocol-types \
                  --filter @semantos/semantos-ir \
                  --filter @semantos/semantos-sir \
                  --filter @semantos/intent \
                  --filter @semantos/session-protocol \
                  run build

      - name: Create Release Pull Request or Publish
        uses: changesets/action@v1
        with:
          publish: pnpm -r publish --access restricted --no-git-checks
          version: pnpm changeset version
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

```
