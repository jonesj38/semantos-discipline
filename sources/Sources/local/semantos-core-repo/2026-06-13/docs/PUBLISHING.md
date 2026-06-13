---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PUBLISHING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.328170+00:00
---

# Publishing `@semantos/*` packages

`semantos-core` publishes nine packages to **GitHub Packages** under the `@semantos` scope, for consumption by `todriguez/ojt` and `todriguez/brap`. This doc covers the release flow, consumer setup, and rollback.

## Published packages

| Package | Source path |
|---|---|
| `@semantos/core` | repo root (`src/`) |
| `@semantos/cell-ops` | `core/cell-ops/` |
| `@semantos/protocol-types` | `core/protocol-types/` |
| `@semantos/semantos-ir` | `core/semantos-ir/` |
| `@semantos/semantos-sir` | `core/semantos-sir/` |
| `@semantos/intent` | `runtime/intent/` |
| `@semantos/session-protocol` | `runtime/session-protocol/` |
| `@semantos/semantic-objects` | `core/semantic-objects/` |
| `@semantos/calendar-ext` | `extensions/calendar/` |

All nine are version-locked via the `fixed` group in `.changeset/config.json` — a single changeset bumps all nine. Once any has a new release cut, they all advance together.

## Release flow (maintainer)

1. Land PR(s) to `main` with at least one changeset file. Author a changeset with:
   ```bash
   pnpm changeset
   ```
   Pick the packages affected, select the bump level (major/minor/patch), write a summary.
2. On merge to `main`, `.github/workflows/release.yml` fires. It either:
   - Opens a "Version Packages" PR that bumps `package.json` versions + writes changelog entries, OR
   - If such a PR already exists and was merged, runs `pnpm -r publish --access restricted` — publishing all packages with pending version bumps to GitHub Packages.
3. Verify at https://github.com/todriguez/semantos-core/packages.

## Consumer setup (bots, downstream repos)

Each consumer needs:

**`.npmrc`** in the repo root:
```
@semantos:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
always-auth=true
```

**Environment** — for local dev, set `GITHUB_TOKEN` to a classic PAT with `read:packages`:
- direnv: copy `.envrc.example` → `.envrc`, fill `GITHUB_TOKEN`, `direnv allow`
- Or export manually: `export GITHUB_TOKEN=$GITHUB_PAT_READ_PACKAGES`

**CI** (GitHub Actions) — `secrets.GITHUB_TOKEN` has `read:packages` on the same org's packages automatically. The consumer workflow passes it as `NODE_AUTH_TOKEN`:
```yaml
- run: pnpm install --frozen-lockfile
  env:
    NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Minting a PAT

For local development:
1. Visit https://github.com/settings/tokens/new?scopes=read:packages (or the `classic` token page).
2. Generate a classic PAT with `read:packages` scope.
3. Store in a password manager as `GITHUB_PAT_READ_PACKAGES`.
4. For publish-from-laptop (rare — CI should do it): `read:packages` + `write:packages`.

## Rollback

- **Unpublish (within 30 days of publish)**:
  ```bash
  npm unpublish @semantos/<pkg>@0.1.0 --registry=https://npm.pkg.github.com
  ```
- **After 30 days**: unpublishing a specific version isn't allowed. Bump to `0.1.1` with a changeset noting "revert X", publish the new version, and ensure consumers bump past the broken one.
- **Disable the release workflow**: comment out the `push: branches: [main]` trigger in `.github/workflows/release.yml`.

## Local verification before pushing

Before relying on the CI publish, dry-run locally:
```bash
source ~/.nvm/nvm.sh && nvm use 20
pnpm run build
pnpm -r --filter '@semantos/cell-ops' --filter '@semantos/protocol-types' \
       --filter '@semantos/semantos-ir' --filter '@semantos/semantos-sir' \
       --filter '@semantos/intent' --filter '@semantos/session-protocol' \
       run build
# Dry-run (does not actually publish):
pnpm -r publish --dry-run --access restricted --no-git-checks
```

## Open-source later

If `semantos-core` ever goes public on npmjs.org, change `.changeset/config.json` `access` to `public`, change each package's `publishConfig.registry` to `https://registry.npmjs.org/`, and update consumer `.npmrc` files. The rest of the flow is identical.
