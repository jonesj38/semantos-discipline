---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/cross-repo-path-dep-pattern.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.634834+00:00
---

# Cross-repo path-dep + pinned-rev pattern

**Status**: canonical pattern for cross-repo / cross-cartridge dependency wiring in the semantos ecosystem.
**Companion matrix**: [`docs/canon/cw-lift-matrix.yml`](cw-lift-matrix.yml) — L26
**Companion roadmap**: [`docs/prd/CW-LIFT-ROADMAP.md`](../prd/CW-LIFT-ROADMAP.md) — §2 Tier 1
**Origin**: lifted from prof-faustus/revocable-nft-tee (Craig Wright), 2026-06-02. Closes the parked `oss_substrate_carve_parked` decision.

---

## What this pattern is for

When a semantos extension (a cartridge, a sidecar, an external research project, a downstream consumer) needs a primitive from a stable semantos substrate package, there are three classical mechanics, and **two of them are wrong** for semantos:

| Mechanic | Effect | Verdict |
|---|---|---|
| **(a)** Fork the substrate into the extension's tree | Single source of truth lost; substrate diverges; bug fixes need three-way merges | ❌ wrong shape |
| **(b)** Carve the substrate out into its own repo, version-bump and `npm install` / `cargo add` | Loses the in-tree refactor invariant ("change a primitive and every caller updates atomically"); creates a "divergent mirrors" problem | ❌ wrong shape — see `oss_substrate_carve_parked` memory |
| **(c)** Path-dep with pinned revision + one-way governance | Substrate stays in semantos-core; extension references it by relative path with a pinned commit; substrate is upgradable, extension knows when it upgraded | ✅ **this pattern** |

Option (c) is what Craig's `revocable-nft-tee` does to consume `overlay-broadcast`. It is the answer to "how do I build on top of a stable substrate without forking and without version-bumping a separate repo."

---

## The pattern

### Mechanic

The extension's manifest (`Cargo.toml` / `package.json` / etc.) declares the dependency as a **relative path** with the substrate revision **pinned in lockfile / git submodule / commit-rev**:

**Rust (Cargo)**:
```toml
[dependencies]
semantos-cell-engine = { path = "../semantos-core/core/cell-engine" }
# Lockfile pins the commit. Update by bumping the lockfile, not the path.
```

**Node (pnpm workspaces)**:
```jsonc
{
  "dependencies": {
    "@semantos/protocol-types": "workspace:*"
    // Workspace-protocol resolves to the in-tree package; pin via pnpm-lock.yaml.
  }
}
```

**For a sibling-repo extension** (extension lives outside semantos-core):
```toml
# Cargo.toml in cartridges-rust/my-cartridge/
[dependencies]
semantos-cell-engine = { git = "https://github.com/semantos/semantos-core", rev = "abc123def456", path = "core/cell-engine" }
```
The git-rev pin gives the extension cryptographic certainty about which substrate snapshot it consumes.

### Governance line

One rule, expressed as workspace policy:

> **The extension MAY depend on the substrate. The substrate SHALL NOT depend on the extension.**

In Craig's repo this lives as `REQ-GOV-V2-002` in the requirements traceability matrix. For semantos, this line goes in each package's `CLAUDE.md` (or top-of-file comment) wherever the boundary is load-bearing — e.g. in `core/cell-engine/CLAUDE.md`:

```
# Cell-engine governance line
This package is a SUBSTRATE. Cartridges and downstream consumers MAY
depend on this package. This package SHALL NOT depend on any cartridge
or downstream consumer. CI rejects reverse-deps (see scripts/check-deps.sh).
```

CI enforcement is straightforward — grep the manifests for cycles, or use the language-native tooling (`cargo tree --invert` on the substrate package; `pnpm list -r --filter=substrate-package`).

### Mental model

The substrate is **stable address space**: callers reference it by stable path. The substrate version they pin is **a snapshot in time**: when they pin a newer rev, they consent to whatever changed. The substrate doesn't run their tests; they run the substrate's tests against their pinned rev.

This is the same shape as system headers + lockfile in a typical OS package manager — except the substrate ships in the same repo when convenient (path-dep) or a sibling repo when not (git-rev pin).

---

## When this pattern applies

Apply path-dep + pinned-rev when:

1. **An extension needs a primitive a substrate already provides** — e.g. a cartridge needs cell-engine's `CellMint` API, or an external research project needs `protocol-types`' BSV wire format.
2. **The extension might evolve faster than the substrate** — fine. The extension upgrades its pinned rev when ready; the substrate doesn't have to know it exists.
3. **Multiple extensions consume the same substrate** — also fine. Each extension pins independently. Substrate doesn't fan-out responsibility for any of them.
4. **The substrate is being OSS'd via one-way snapshot** (the wider carve from `oss_substrate_carve_parked`) — the one-way snapshot publishes the substrate under MIT/Apache-2.0; external consumers path-dep or git-rev pin against it; substrate stays single-source-in-semantos-core.

## When this pattern does NOT apply

1. **Bidirectional coupling** — if two packages genuinely need to call into each other, they're one package. Split if and only if dependency is one-way.
2. **Trivial dependencies** — a cartridge needing a small utility from another cartridge doesn't need workspace ceremony; just inline-copy or extract a tiny shared package.
3. **The "extension" is actually a different domain that happens to be in the same monorepo** — apps/semantos consuming `core/protocol-types` is just normal in-monorepo dep resolution; no special pattern needed. The pattern is for cross-tree (different cartridges, different repos) wiring.

---

## Reference templates

Worked-example templates live at:

- **In-repo cartridge → substrate** (Node/pnpm-workspace): [`docs/canon/templates/cartridge-package.json.template`](templates/cartridge-package.json.template)
- **Sibling-repo extension → semantos-core substrate** (Rust/Cargo): [`docs/canon/templates/sibling-cargo-dep.toml.template`](templates/sibling-cargo-dep.toml.template)
- **Substrate-package governance line** (drop into `core/<pkg>/CLAUDE.md`): [`docs/canon/templates/substrate-governance-line.md.template`](templates/substrate-governance-line.md.template)

Copy whichever applies, replace the `<placeholder>` / `REPLACE_WITH_*` markers, and commit. All templates carry the governance line in comments so the boundary doesn't get forgotten during onboarding.

## First application (matrix axis F)

The pattern lands its **first in-tree application** as a CI gate.
[`tests/gates/substrate-one-way-dep.test.ts`](../../tests/gates/substrate-one-way-dep.test.ts) mechanically enforces the governance line by scanning every `core/<pkg>/src/` (excluding `__tests__/` and `tests/` cross-validation fixtures) and rejecting any import that resolves into `cartridges/*` or `runtime/*` — neither via relative path nor via an `@semantos/<extension>` alias. The gate maintains an explicit deny-list of cartridge + runtime package names because the semantos monorepo uses the `@semantos/*` scope for both substrate and extensions, so a scope-prefix check alone is insufficient.

Governance-line sections + cross-link references applied to four substrate packages: `core/protocol-types`, `core/cell-engine`, `core/anchor-attestation`, `core/plexus-vendor-sdk`. Future substrate packages should copy the template above.

---

## What this closes / supersedes

### Closes: `oss_substrate_carve_parked` (parked decision from 2026-05-14)

The parked decision worried about "divergent mirrors" if semantos OSS'd parts of itself. Path-dep + pinned-rev resolves the worry: the wider substrate carve (pask + cell-engine + tools/release + cell-relay + content-store) gets a one-way snapshot publish at version boundaries, and external consumers reference it via `git = ..., rev = ...` in their manifest. Source-of-truth stays in semantos-core; no divergent maintenance burden.

Per the memory: "Acceptable mechanics: one-way snapshot publishing at version boundaries (filter-repo dump to public repo per release), or restructure semantos-core so the OSS dirs sit in a public top-level subtree pushed one-way." Path-dep + pinned-rev is the *consumer-side* answer; the publish mechanic is the *substrate-side* answer; together they unblock the OSS path.

### Supersedes nothing else

This is an additive canon pattern. It doesn't change how `apps/semantos` or `runtime/semantos-brain` consume `core/` — those continue to use in-monorepo path-deps that pnpm resolves transparently. The pattern is for cross-tree wiring specifically.

---

## Cross-references

- Memory: [`oss_substrate_carve_parked`](memory) — the parked decision this pattern closes.
- Memory: [`semantos_worktree_hygiene`](memory) — adjacent governance discipline (avoid auto-creating worktrees, prefer in-place branches).
- Matrix: [`docs/canon/cw-lift-matrix.yml`](cw-lift-matrix.yml) — L26.
- Source (Craig Wright, MIT): `prof-faustus/revocable-nft-tee`, particularly the Cargo.toml `path = "../overlay-broadcast/crates/*"` declarations and the REQ-GOV-V2-002 governance line.

---

## Worked example: how `revocable-nft-tee` consumes `overlay-broadcast`

```toml
# revocable-nft-tee/Cargo.toml (excerpt, anonymised)
[workspace.dependencies]
ob-bsv     = { path = "../overlay-broadcast/crates/bsv" }
ob-cipher  = { path = "../overlay-broadcast/crates/cipher", package = "cipher" }
ob-ckd     = { path = "../overlay-broadcast/crates/ckd" }
ob-keygraph = { path = "../overlay-broadcast/crates/keygraph" }
ob-overlay  = { path = "../overlay-broadcast/crates/overlay" }
ob-broadcast = { path = "../overlay-broadcast/crates/broadcast" }
ob-session   = { path = "../overlay-broadcast/crates/session" }
ob-custody   = { path = "../overlay-broadcast/crates/custody" }
# ... etc
```

The pin is the git commit of `overlay-broadcast` checked out at the time `revocable-nft-tee` was built (recorded in `Cargo.lock`). REQ-GOV-V2-002 forbids any crate in `overlay-broadcast` from declaring a path-dep back to `revocable-nft-tee`. Workspace policy enforces the one-way invariant.

Semantos's equivalent: when cartridges or extensions want substrate primitives, they path-dep or git-rev pin against the substrate package, and a CLAUDE.md governance line + a CI dep-check enforces the one-way rule.

---

## Appendix: why this is preferable to subtree splits or git submodules

**Subtree split** (`git subtree split` then publish): viable for one-way snapshot publishing of the substrate. Not viable as the *consumption mechanic* because consumers then need to bidirectionally sync.

**Git submodules**: works but adds operational burden (`git submodule update --init --recursive` everywhere; nested clone surprises in CI). Path-dep + lockfile-pin gives the same isolation with less ceremony.

**npm/cargo registry version pinning**: viable but requires publishing the substrate as a versioned package on a registry. Reasonable for the wider OSS carve; overkill for in-monorepo cartridges that can resolve via workspace-protocol.

Path-dep + pinned-rev is the sweet spot: works inside one monorepo (workspace-protocol or relative path), works across sibling repos (git + rev), works for OSS-via-snapshot (versioned dep against the published mirror) — all with the same one-way governance line.
