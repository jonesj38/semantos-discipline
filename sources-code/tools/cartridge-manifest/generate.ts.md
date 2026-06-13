---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/cartridge-manifest/generate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.548966+00:00
---

# tools/cartridge-manifest/generate.ts

```ts
#!/usr/bin/env bun
/**
 * Cartridge Manifest Generator — D-Manifest-canonical (tessera).
 *
 * Resolves the three-format manifest ambiguity by making the brain-side
 * on-disk manifest the SINGLE SOURCE OF TRUTH and GENERATING the Flutter
 * shell manifest + bundle envelope from it. Mirrors the determinism
 * contract of core/constants/generate.ts: same inputs → byte-identical
 * outputs; re-running is a no-op.
 *
 * Inputs (read-only):
 *   - cartridges/<id>/cartridge.json         — canonical cartridge manifest
 *   - core/constants/constants.json          — extensionPages domain-flag registry
 *   - docs/canon/lexicons.yml                — canonical lexicon categories
 *                                              (V0.4; guarded upstream by the
 *                                              tessera-lexicon L11 drift test)
 *
 * Outputs (generated, committed for the Flutter asset bundler):
 *   - packages/<id>_experience/assets/manifest.json
 *   - packages/<id>_experience/assets/bundle.json
 *
 * The shell domainFlag is DERIVED from constants.json extensionPages
 * (one allocation registry), not hand-allocated — this is the
 * resolution of the brain 0x00010400 vs interim shell 0x000105 drift.
 *
 * Usage:
 *   bun tools/cartridge-manifest/generate.ts            # generate tessera
 *   bun tools/cartridge-manifest/generate.ts --check    # fail if drifted
 */

import { readFileSync, writeFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Per-cartridge generation config ───────────────────────────────────
// One entry per cartridge whose shell experience is generated. Adding a
// cartridge here makes its shell assets generator-owned.
interface CartridgeGenConfig {
  /** Cartridge id — matches cartridges/<id>/ and packages/<id>_experience/. */
  id: string;
  /** Display name for the shell home picker + hat composition. */
  shellName: string;
  /** constants.json extensionPages key holding the canonical domain flag. */
  domainFlagConstant: string;
  /** docs/canon/lexicons.yml entry id for the canonical category list. */
  lexiconId: string;
  /** Shell-side asset directory under packages/. */
  experiencePackage: string;
  /** Author + documentation pointer for shell metadata. */
  author: string;
  documentation: string;
}

const CARTRIDGES: CartridgeGenConfig[] = [
  {
    id: "tessera",
    shellName: "Tessera — Care Chain",
    domainFlagConstant: "TESSERA_PAGE",
    lexiconId: "tessera",
    experiencePackage: "tessera_experience",
    author: "Semantos",
    documentation: "docs/prd/TESSERA-CARTRIDGE.md",
  },
];

// ── Canonical-source readers ──────────────────────────────────────────

function readBrainManifest(id: string): Record<string, unknown> {
  return JSON.parse(
    readFileSync(join(ROOT, `cartridges/${id}/cartridge.json`), "utf-8"),
  );
}

function readDomainFlag(constant: string): string {
  const constants = JSON.parse(
    readFileSync(join(ROOT, "core/constants/constants.json"), "utf-8"),
  );
  const pages = constants.extensionPages as Record<string, string> | undefined;
  const raw = pages?.[constant];
  if (typeof raw !== "string") {
    throw new Error(
      `constants.json extensionPages missing "${constant}" — domain flag is the ` +
        `single allocation registry; add it there, do not hand-allocate shell-side.`,
    );
  }
  return raw; // already in 0xNNNNNNNN form
}

/**
 * Minimal canonical-category extractor for docs/canon/lexicons.yml.
 *
 * Avoids a YAML runtime dependency (constants/generate.ts is likewise
 * dependency-free for determinism). The lexicons.yml `categories:` block
 * is a flat YAML sequence; this scans the `- id: <lexiconId>` entry and
 * collects its `categories:` list. Upstream drift between lexicons.yml,
 * ALL_LEXICONS and the cartridge is already gated by the V0.4
 * tessera-lexicon.test.ts L11 assertion — this reader trusts that gate.
 */
function readLexiconCategories(lexiconId: string): string[] {
  const yml = readFileSync(
    join(ROOT, "docs/canon/lexicons.yml"),
    "utf-8",
  ).split("\n");

  let inEntry = false;
  let inCategories = false;
  const categories: string[] = [];

  for (const line of yml) {
    const idMatch = line.match(/^\s{2}- id:\s*(\S+)\s*$/);
    if (idMatch) {
      // A new top-level lexicon entry begins.
      inEntry = idMatch[1] === lexiconId;
      inCategories = false;
      continue;
    }
    if (!inEntry) continue;

    if (/^\s{4}categories:\s*$/.test(line)) {
      inCategories = true;
      continue;
    }
    if (inCategories) {
      const catMatch = line.match(/^\s{6}-\s*(\S+)\s*$/);
      if (catMatch) {
        categories.push(catMatch[1].replace(/^['"]|['"]$/g, ""));
        continue;
      }
      // Any non-list line at shallower indent ends the categories block.
      if (line.trim().length > 0) inCategories = false;
    }
  }

  if (categories.length === 0) {
    throw new Error(
      `docs/canon/lexicons.yml has no categories for lexicon "${lexiconId}" — ` +
        `V0.4 lexicon canon must be registered before manifest generation.`,
    );
  }
  return categories;
}

// ── Shell-manifest synthesis ──────────────────────────────────────────

interface ShellManifest {
  id: string;
  name: string;
  version: string;
  domainFlag: string;
  metadata: { description: string; author: string; documentation: string };
  hatRoles: string[];
  requiredCapabilities: number[];
  grammar: {
    extensionId: string;
    trustClass: string;
    proofRequirement: string;
    defaultTaxonomyWhat: string;
    lexicon: { name: string; categories: string[] };
    objectTypes: { name: string; description: string }[];
    actions: {
      name: string;
      category: string;
      authoredBy: string[];
      description: string;
    }[];
  };
}

function synthShellManifest(
  cfg: CartridgeGenConfig,
  brain: Record<string, unknown>,
  domainFlag: string,
  categories: string[],
): ShellManifest {
  const verbs = (brain.verbs as Array<Record<string, unknown>>) ?? [];
  const cellTypes = (brain.cellTypes as Array<Record<string, unknown>>) ?? [];
  const shellGrammar =
    (brain.shellGrammar as Record<string, string>) ?? {};
  const hatRoles = (brain.hatRoles as string[]) ?? [];

  return {
    id: brain.id as string,
    name: cfg.shellName,
    version: brain.version as string,
    domainFlag,
    metadata: {
      description: brain.description as string,
      author: cfg.author,
      documentation: cfg.documentation,
    },
    hatRoles,
    requiredCapabilities: [],
    grammar: {
      extensionId: brain.id as string,
      trustClass: shellGrammar.trustClass ?? "interpretive",
      proofRequirement: shellGrammar.proofRequirement ?? "attestation",
      defaultTaxonomyWhat:
        shellGrammar.defaultTaxonomyWhat ?? `${brain.id as string}.cell`,
      lexicon: { name: cfg.lexiconId, categories },
      objectTypes: cellTypes.map((c) => ({
        name: c.name as string,
        description: c.description as string,
      })),
      // Shell `actions` are DERIVED from brain `verbs`: the verb's short
      // name (last dotted segment, underscored), its lexicon category,
      // its hat scope, and its description. No hand-maintained second
      // list — the brain manifest is the only place verbs are declared.
      actions: verbs.map((v) => {
        const fullName = v.name as string;
        const shortName = fullName
          .split(".")
          .slice(1)
          .join("_")
          .replace(/-/g, "_");
        return {
          name: shortName,
          category: v.category as string,
          authoredBy: (v.hats as string[]) ?? [],
          description: v.description as string,
        };
      }),
    },
  };
}

interface BundleEnvelope {
  schemaVersion: number;
  issuedBy: string;
  publishedAt: number;
  signature: { scheme: string; signedAt: number };
  manifest: ShellManifest;
}

function synthBundle(
  cfg: CartridgeGenConfig,
  manifest: ShellManifest,
): BundleEnvelope {
  // Fixed timestamps keep the output deterministic (the constants/
  // generate.ts contract). Real signing replaces scheme:"none" at
  // release time via tools/release/.
  return {
    schemaVersion: 1,
    issuedBy: `compile-time://semantos-core/packages/${cfg.experiencePackage}`,
    publishedAt: 1747100000,
    signature: { scheme: "none", signedAt: 1747100000 },
    manifest,
  };
}

// ── Emit ──────────────────────────────────────────────────────────────

function generate(cfg: CartridgeGenConfig): {
  manifestPath: string;
  bundlePath: string;
  manifest: string;
  bundle: string;
} {
  const brain = readBrainManifest(cfg.id);
  const domainFlag = readDomainFlag(cfg.domainFlagConstant);
  const categories = readLexiconCategories(cfg.lexiconId);

  const shellManifest = synthShellManifest(cfg, brain, domainFlag, categories);
  const bundle = synthBundle(cfg, shellManifest);

  const assetsDir = join(ROOT, `packages/${cfg.experiencePackage}/assets`);
  const manifestPath = join(assetsDir, "manifest.json");
  const bundlePath = join(assetsDir, "bundle.json");

  // Two-space indent + trailing newline — matches the hand-written
  // precedent so the first regenerate is a minimal, reviewable diff.
  const manifestStr = JSON.stringify(shellManifest, null, 2) + "\n";
  const bundleStr = JSON.stringify(bundle, null, 2) + "\n";

  return {
    manifestPath,
    bundlePath,
    manifest: manifestStr,
    bundle: bundleStr,
  };
}

const checkMode = process.argv.includes("--check");
let drifted = false;

for (const cfg of CARTRIDGES) {
  const out = generate(cfg);
  if (checkMode) {
    for (const [path, next] of [
      [out.manifestPath, out.manifest],
      [out.bundlePath, out.bundle],
    ] as const) {
      let current = "";
      try {
        current = readFileSync(path, "utf-8");
      } catch {
        current = "";
      }
      if (current !== next) {
        drifted = true;
        console.error(
          `DRIFT: ${path.replace(ROOT + "/", "")} is out of sync with ` +
            `cartridges/${cfg.id}/cartridge.json — run ` +
            `\`bun tools/cartridge-manifest/generate.ts\` and commit.`,
        );
      }
    }
  } else {
    writeFileSync(out.manifestPath, out.manifest, "utf-8");
    writeFileSync(out.bundlePath, out.bundle, "utf-8");
    console.log(`Generated: ${out.manifestPath.replace(ROOT + "/", "")}`);
    console.log(`Generated: ${out.bundlePath.replace(ROOT + "/", "")}`);
  }
}

if (checkMode && drifted) process.exit(1);
if (checkMode) console.log("cartridge manifests in sync — no drift");

```
