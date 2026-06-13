---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.847626+00:00
---

# core/protocol-types/src/extension-manifest.ts

```ts
/**
 * ExtensionManifest — metadata + pointer structure for a filesystem-based extension.
 *
 * Lives as config.json in the extension directory root.
 * Example: /var/semantos/extensions/trades/config.json
 *
 * Cross-references:
 *   extension-loader.ts   → ExtensionLoader reads and validates this
 *   extension-registry.ts → ExtensionRegistry activates extensions by manifest
 *   extensionConfig.ts    → ExtensionConfig is the runtime representation
 *   governance.ts         → ManifestGovernanceConfig, DeprecationStatus (Phase 36D)
 */

import type { ManifestGovernanceConfig, DeprecationStatus } from './governance';
import type { ExtensionGrammar } from './extension-grammar';

/**
 * ExtensionManifest — the on-disk shape of an extension's config.json.
 *
 * All paths are relative to the directory containing config.json.
 */
export interface ExtensionManifest {
  /** Unique identifier for this extension (e.g. "trades", "sovereignty"). */
  id: string;

  /** Human-readable name (e.g. "Trades & Services"). */
  name: string;

  /** Semantic version of this extension package (e.g. "1.0.0"). */
  version: string;

  // ── Canonical Cartridge Model (CC0a — RATIFIED C1/C3) ──────────────
  // docs/design/CANONICAL-CARTRIDGE-MODEL.md. This manifest IS the
  // canonical `cartridge.json`; "app"/"extension" are no longer
  // distinct concepts — a cartridge is role-classified, and its Brain
  // part and PWA-experience part are bound by ONE manifest.

  /**
   * Cartridge role (C1 — replaces the app/extension/world-app split):
   *  - `infra`            — provides adapter interfaces other cartridges
   *                          consume (MUST declare `provides`); e.g.
   *                          wallet/headers/anchor.
   *  - `experience`       — a user-facing vertical (oddjobz, jamroom,
   *                          tessera); typically has an `experience`
   *                          (Flutter) part.
   *  - `grammar-lexicon`  — pure vocabulary/grammar, no Brain handlers.
   * Optional during migration (CC4 backfills every cartridge); when
   * omitted the loader treats it as `experience` for back-compat.
   */
  role?: 'infra' | 'experience' | 'grammar-lexicon';

  /**
   * The Brain↔PWA binding (C3 — the linchpin that collapses
   * `extensions/<id>` ↔ `packages/<id>_experience`). Declares the
   * cartridge's PWA-experience part so the PWA shell loads the right
   * Flutter package with zero shell edits.
   */
  experience?: {
    /** Flutter package providing this cartridge's PWA surface
     *  (e.g. "packages/oddjobz_experience"). */
    flutterPackage: string;
  };

  /**
   * Lexicon section (C2 — one source). Either inline categories or a
   * ref to the in-tree lexicon module; the canon `lexicons.yml` +
   * Lean `Lexicons/*` become **generated** from this (CC0b), not a
   * parallel hand-kept truth. Optional during migration.
   */
  lexicon?: {
    /** Canonical lexicon id (matches `docs/canon/lexicons.yml` id). */
    id: string;
    /** In-tree source module (e.g. "src/lexicon.ts"); the generator
     *  reads this to (re)produce the canon registry entry. */
    sourcePath?: string;
  };

  /**
   * Brain-surface kind (C7 — CC4-M amendment). Classifies *how* the
   * Brain part is shaped (orthogonal to `role`, which classifies what
   * the cartridge is for):
   *  - `cells`   — declarative discourse surface; REQUIRES
   *                taxonomyPath/flowsDir/promptsDir (oddjobz).
   *  - `walkers` — imperative verb-registering module (`verbsModule`,
   *                the brain @import name; e.g. jambox's
   *                `jambox_walkers`); the declared `verbs[]` + that
   *                module ARE the Brain surface. Exempt from
   *                taxonomy/flows/prompts (mirrors `role:infra`).
   *  - `none`    — PWA-only experience, no Brain part; also exempt.
   * Absent ⇒ `cells` (back-compat: taxonomy/flows/prompts required).
   */
  brain?: {
    surface: 'cells' | 'walkers' | 'none';
    /** For surface:'walkers' — the verb-registering brain module's
     *  `@import` name (e.g. "jambox_walkers"). Required iff walkers. */
    verbsModule?: string;
  };

  /**
   * Path to the primary taxonomy JSON file, relative to manifest directory.
   * Example: "taxonomy/trades.json"
   */
  taxonomyPath: string;

  /**
   * Directory containing flow definitions (relative path).
   * Loader scans this directory for *.json files.
   */
  flowsDir: string;

  /**
   * Directory containing prompt script files (relative path).
   * Loader scans this directory for *.md files.
   */
  promptsDir: string;

  /** Directory containing object type definitions (optional, relative path). */
  objectsDir?: string;

  /**
   * List of capability tokens required to activate this extension.
   * Empty array or omitted = always available.
   */
  requiredCapabilities?: number[];

  /**
   * List of hat roles that can manage this extension.
   * Example: ["admin", "governor"]
   */
  hatRoles?: string[];

  /** Optional metadata for UI display. */
  metadata?: {
    icon?: string;
    description?: string;
    documentation?: string;
    author?: string;
  };

  // ── Phase 36D: Governance fields ──────────────────────────

  /** Governance configuration — controls how this extension evolves. */
  governanceConfig?: ManifestGovernanceConfig;

  /** Grammar linearity — AFFINE (draft) → RELEVANT (published). */
  manifestLinearity?: 'AFFINE' | 'RELEVANT';

  /** Grammar content (the actual JSON schema). */
  grammar?: ExtensionGrammar;

  /** Current deprecation status. */
  deprecationStatus?: DeprecationStatus;

  // ── Wave Cap-Substrate §6: cartridge ownership (RATIFIED) ──────────
  // docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md Decisions A/B.

  /**
   * The cartridge's affine PushDrop **license UTXO** outpoint
   * (`"<txid>:<vout>"`). Decision A: ownership is an affine PushDrop
   * license UTXO required at load; the authoritative owner/holder is
   * the key it is P2PK-locked to (`metadata.author` is display-only).
   * Verified by the proven K15 capability-UTXO path (the license IS a
   * capability UTXO whose domain is the cartridge's registered page —
   * no new crypto, no PushDrop decoder; `checkCapability` + the
   * SW2-concrete SPV verifier do the work). Absent ⇒ unlicensed ⇒
   * fails the load-check unless an explicit first-party/dev escape.
   */
  licenseOutpointRef?: string;

  /** Pinned: the license cell is affine (consume-at-most-once, no
   *  DUP) — `LINEARITY_AFFINE`. */
  licenseLinearity?: 'AFFINE';

  /**
   * Decision B: typed adapter-interface composition (never an
   * `extends`/cartridge-id edge). A cartridge builds on another only
   * by consuming the typed interface it provides, capability-gated.
   */
  extendsInterfaces?: {
    provides?: string[];
    consumes?: string[];
  };

  // ── C11 PR-C11-7e: substrate cell-type catalog ─────────────────────
  // Cartridges declare their cell types here; the brain registers each
  // entry's typeHash via `buildTypeHash(s1, s2, s3, s4)`. Optional
  // because not every cartridge has substrate-level cell types.
  cellTypes?: CellTypeDeclaration[];
}

// ─────────────────────────────────────────────────────────────────────
// C11 PR-C11-7e — Cell type catalog entries
// ─────────────────────────────────────────────────────────────────────

/**
 * A cell type's structured triple. The brain runs
 * `buildTypeHash(segment1, segment2, segment3, segment4)` to derive
 * the 32-byte typeHash that identifies cells of this type on the
 * wire and in the cell store.
 *
 * Segments are append-only. Changing a segment changes the
 * typeHash and breaks every cell ever minted under the old type.
 *
 * `segment4` may be the empty string `""` for cell types that don't
 * need a qualifier (matches the MNCA pattern in `mnca/cell-types.ts`).
 */
export interface CellTypeTriple {
  segment1: string;
  segment2: string;
  segment3: string;
  segment4: string;
}

/**
 * Cell linearity — how the cell-engine treats consumption.
 *
 * - **PERSISTENT** — Cell is read-only after mint; multiple
 *   references allowed. Snapshot-style.
 * - **LINEAR** — Cell is consumed by exactly one downstream
 *   transition; the cell-engine prevents double-spending. Linear-
 *   anchor + UTXO-bound cells use this.
 * - **AFFINE** — Cell may be consumed at most once; not consuming
 *   it is legal (the cell quietly expires). License UTXOs use this
 *   per Cap-Substrate §6.
 * - **EPHEMERAL** — Cell exists only as a transient request /
 *   result; never persists. Intent / result cells (e.g.
 *   `bsv.spv.verify.intent`) use this.
 *
 * RELEVANT is grammar-side, not cell-side; not valid here.
 */
export type CellTypeLinearity = 'PERSISTENT' | 'LINEAR' | 'AFFINE' | 'EPHEMERAL';

/**
 * Cell-engine bytecode handler declaration for a cell type.
 *
 * When a cellType entry carries a `handler`, the brain's mint
 * pipeline dispatches incoming mints of that type through
 * `PolicyRuntime.evaluateReal` with `handler.script` as the locking
 * script. The script executes on the cell-engine 2PDA (pda.zig +
 * executor.zig + opcodes/) and may invoke registered hostcalls via
 * `OP_CALLHOST` subject to the capability gating below.
 *
 * Cell types without a handler are pure data records — minted to
 * the cell store with no transition function.
 *
 * Reference: `docs/design/LINEAR-CELL-SPV-STATE.md` §3 (hostcall
 * ABI), §7 (capability gating).
 */
export interface HandlerDeclaration {
  /**
   * Hex-encoded cell-engine bytecode for the transition script.
   * Lowercase hex, even-length. Compiled from a higher-level
   * source-language by the cartridge build pipeline; this field
   * holds the canonical bytecode that hashes to `scriptHash`.
   */
  script: string;

  /**
   * SHA-256 of `script` bytes (decoded from hex), lowercase 64-char
   * hex. Pinned at manifest write time. The brain refuses to load
   * a handler whose computed hash doesn't match — supply-chain
   * integrity check.
   */
  scriptHash: string;

  /**
   * Hostcall capability tags the script may invoke via OP_CALLHOST.
   * Must be a subset of the registered tags in
   * `runtime/semantos-brain/src/host_capability_table.zig`. The
   * dispatcher refuses a script whose OP_CALLHOST targets a tag
   * outside this list.
   *
   * Cell types that need no hostcalls (pure stack computation +
   * OP_CELLCREATE) declare an empty array.
   */
  capabilities: string[];

  /**
   * Max opcount budget for one script invocation. Caps execution
   * time + memory growth. Defaults to the cell-engine executor's
   * `DEFAULT_MAX_OPS` (500000) if omitted; explicit values let
   * narrower budgets apply per cell type.
   */
  opcountBudget?: number;

  /**
   * Cell-type names this script is allowed to emit via OP_CELLCREATE.
   * The dispatcher refuses an OP_CELLCREATE whose target typeHash is
   * outside this allowlist — prevents privilege confusion where one
   * handler mints cells of unrelated types.
   *
   * Empty array = handler emits nothing (pure validator scripts that
   * just return truthy/falsy).
   */
  emits: string[];
}

/**
 * A cell type declared by a cartridge.
 *
 * Substrate state records (e.g. `bsv.linear.anchor`,
 * `bsv.beef.carriage.head`) describing the canonical cell shapes
 * a cartridge mints and consumes. Cell types with a `handler` are
 * dispatched through the cell-engine via PolicyRuntime; without one
 * they're pure data records.
 */
export interface CellTypeDeclaration {
  /**
   * Canonical cell-type name (e.g. `"bsv.spv.verify.intent"`,
   * `"mnca.snapshot"`). Mirrored in
   * `core/protocol-types/src/<ns>/cell-types.ts` as a string
   * constant for type-safe consumption.
   *
   * Append-only — changing the name changes the typeHash and
   * breaks every cell ever minted under the old name.
   */
  name: string;

  /** The structured triple that hashes to the cell-type's 32-byte typeHash. */
  triple: CellTypeTriple;

  /** Cell-engine consumption semantics. */
  linearity: CellTypeLinearity;

  /** Human-readable description (shown in admin / diagnostic surfaces). */
  description?: string;

  /**
   * Cell-engine bytecode handler. When present, the brain dispatches
   * incoming mints of this typeHash through the handler script via
   * `PolicyRuntime.evaluateReal`. When absent, the cellType is a pure
   * data record and mints persist with no transition.
   */
  handler?: HandlerDeclaration;
}

/**
 * Validate a parsed JSON object as an ExtensionManifest.
 *
 * Checks that all required fields are present and correctly typed.
 * Throws a descriptive Error on validation failure.
 *
 * @param data — parsed JSON object (unknown type for safety)
 * @returns validated ExtensionManifest
 * @throws Error with descriptive message if validation fails
 */
export function validateExtensionManifest(data: unknown): ExtensionManifest {
  if (!data || typeof data !== 'object') {
    throw new Error('Manifest must be a non-null object');
  }

  const obj = data as Record<string, unknown>;

  if (!obj.id || typeof obj.id !== 'string') {
    throw new Error('Missing or invalid manifest.id (must be a non-empty string)');
  }
  if (!obj.name || typeof obj.name !== 'string') {
    throw new Error('Missing or invalid manifest.name (must be a non-empty string)');
  }
  if (!obj.version || typeof obj.version !== 'string') {
    throw new Error('Missing or invalid manifest.version (must be a non-empty string)');
  }
  // CC1 refinement of CC0a: taxonomy/flows/prompts describe an
  // *experience* cartridge's discourse surface. A `role: 'infra'`
  // cartridge (wallet/headers/anchor) provides adapter interfaces and
  // has no taxonomy/flows/prompts — don't force them on it. (Legacy
  // manifests with no `role` still require them — back-compat.)
  // C7 (CC4-M): a `brain.surface` of 'walkers' (imperative verb
  // module, e.g. jambox) or 'none' (PWA-only) is likewise exempt —
  // its declared verbs[]+verbsModule ARE the Brain surface. Absent
  // brain ⇒ 'cells' ⇒ taxonomy/flows/prompts still required.
  const brainObj =
    obj.brain !== undefined && typeof obj.brain === 'object' && obj.brain !== null
      ? (obj.brain as Record<string, unknown>)
      : undefined;
  const brainSurface = (brainObj?.surface as string | undefined) ?? 'cells';
  const isInfra = obj.role === 'infra';
  const isNonCellBrain = brainSurface === 'walkers' || brainSurface === 'none';
  if (!isInfra && !isNonCellBrain) {
    if (!obj.taxonomyPath || typeof obj.taxonomyPath !== 'string') {
      throw new Error('Missing or invalid manifest.taxonomyPath (must be a non-empty string)');
    }
    if (!obj.flowsDir || typeof obj.flowsDir !== 'string') {
      throw new Error('Missing or invalid manifest.flowsDir (must be a non-empty string)');
    }
    if (!obj.promptsDir || typeof obj.promptsDir !== 'string') {
      throw new Error('Missing or invalid manifest.promptsDir (must be a non-empty string)');
    }
  } else {
    // An exempt cartridge (infra, or C7 walkers/none brain) MAY still
    // declare them; if so they must be valid strings.
    for (const k of ['taxonomyPath', 'flowsDir', 'promptsDir'] as const) {
      if (obj[k] !== undefined && typeof obj[k] !== 'string') {
        throw new Error(`manifest.${k} must be a string if provided`);
      }
    }
  }

  if (obj.objectsDir !== undefined && typeof obj.objectsDir !== 'string') {
    throw new Error('manifest.objectsDir must be a string if provided');
  }
  if (obj.requiredCapabilities !== undefined && !Array.isArray(obj.requiredCapabilities)) {
    throw new Error('manifest.requiredCapabilities must be an array if provided');
  }
  if (obj.hatRoles !== undefined && !Array.isArray(obj.hatRoles)) {
    throw new Error('manifest.hatRoles must be an array if provided');
  }

  // Wave Cap-Substrate §6 — cartridge ownership fields.
  if (
    obj.licenseOutpointRef !== undefined &&
    (typeof obj.licenseOutpointRef !== 'string' ||
      !/^[0-9a-fA-F]{64}:\d+$/.test(obj.licenseOutpointRef))
  ) {
    throw new Error(
      'manifest.licenseOutpointRef must be a "<64-hex-txid>:<vout>" string if provided',
    );
  }
  if (obj.licenseLinearity !== undefined && obj.licenseLinearity !== 'AFFINE') {
    throw new Error("manifest.licenseLinearity must be 'AFFINE' if provided");
  }
  if (
    obj.extendsInterfaces !== undefined &&
    (typeof obj.extendsInterfaces !== 'object' || obj.extendsInterfaces === null)
  ) {
    throw new Error('manifest.extendsInterfaces must be an object if provided');
  }

  // Canonical Cartridge Model (CC0a) — role / experience / lexicon.
  if (
    obj.role !== undefined &&
    obj.role !== 'infra' &&
    obj.role !== 'experience' &&
    obj.role !== 'grammar-lexicon'
  ) {
    throw new Error(
      "manifest.role must be 'infra' | 'experience' | 'grammar-lexicon' if provided",
    );
  }
  if (obj.role === 'infra' && obj.provides === undefined) {
    throw new Error(
      "manifest.role='infra' requires `provides` (an infra cartridge MUST declare what it provides — Decision B)",
    );
  }
  if (obj.experience !== undefined) {
    const exp = obj.experience as Record<string, unknown>;
    if (
      typeof exp !== 'object' ||
      exp === null ||
      typeof exp.flutterPackage !== 'string' ||
      exp.flutterPackage.length === 0
    ) {
      throw new Error(
        'manifest.experience must be { flutterPackage: string } if provided (the Brain↔PWA binding, C3)',
      );
    }
  }
  if (obj.lexicon !== undefined) {
    const lx = obj.lexicon as Record<string, unknown>;
    if (typeof lx !== 'object' || lx === null || typeof lx.id !== 'string' || lx.id.length === 0) {
      throw new Error('manifest.lexicon must be { id: string; sourcePath?: string } if provided');
    }
    if (lx.sourcePath !== undefined && typeof lx.sourcePath !== 'string') {
      throw new Error('manifest.lexicon.sourcePath must be a string if provided');
    }
  }
  // C7 (CC4-M) — brain-surface kind. Orthogonal to role; classifies
  // how the Brain part is shaped. 'walkers' MUST name its verbsModule
  // (the brain @import that registers the verbs — e.g. jambox).
  if (obj.brain !== undefined) {
    if (brainObj === undefined) {
      throw new Error('manifest.brain must be an object { surface, verbsModule? } if provided (C7)');
    }
    if (
      brainSurface !== 'cells' &&
      brainSurface !== 'walkers' &&
      brainSurface !== 'none'
    ) {
      throw new Error("manifest.brain.surface must be 'cells' | 'walkers' | 'none' (C7)");
    }
    if (brainSurface === 'walkers') {
      if (
        typeof brainObj.verbsModule !== 'string' ||
        (brainObj.verbsModule as string).length === 0
      ) {
        throw new Error(
          "manifest.brain.surface='walkers' requires `verbsModule` (the verb-registering brain module — C7)",
        );
      }
    } else if (
      brainObj.verbsModule !== undefined &&
      typeof brainObj.verbsModule !== 'string'
    ) {
      throw new Error('manifest.brain.verbsModule must be a string if provided (C7)');
    }
  }

  // ── C11 PR-C11-7e: cellTypes catalog ──────────────────────────────
  if (obj.cellTypes !== undefined) {
    if (!Array.isArray(obj.cellTypes)) {
      throw new Error('manifest.cellTypes must be an array if provided');
    }
    const seenNames = new Set<string>();
    (obj.cellTypes as unknown[]).forEach((entry, i) => {
      validateCellTypeDeclaration(entry, i, seenNames);
    });
  }

  return data as ExtensionManifest;
}

// ─────────────────────────────────────────────────────────────────────
// C11 PR-C11-7e-2b — CellType declaration validator
// ─────────────────────────────────────────────────────────────────────

const CELL_TYPE_LINEARITIES: ReadonlySet<string> = new Set([
  'PERSISTENT',
  'LINEAR',
  'AFFINE',
  'EPHEMERAL',
]);

/**
 * Validate one entry in `manifest.cellTypes[]`. Mutates `seenNames`
 * to enforce per-manifest uniqueness of the `name` field.
 *
 * Throws Error with a descriptive message on any malformed input.
 * Strict: protocol violations are rejected at load time so cells
 * minted against a malformed manifest never reach the cell store.
 */
export function validateCellTypeDeclaration(
  data: unknown,
  index: number,
  seenNames: Set<string>,
): CellTypeDeclaration {
  const prefix = `manifest.cellTypes[${index}]`;
  if (!data || typeof data !== 'object') {
    throw new Error(`${prefix} must be a non-null object`);
  }
  const obj = data as Record<string, unknown>;

  if (typeof obj.name !== 'string' || obj.name.length === 0) {
    throw new Error(`${prefix}.name must be a non-empty string`);
  }
  if (seenNames.has(obj.name)) {
    throw new Error(`${prefix}.name "${obj.name}" duplicates an earlier entry`);
  }
  seenNames.add(obj.name);

  if (!obj.triple || typeof obj.triple !== 'object') {
    throw new Error(`${prefix}.triple must be an object`);
  }
  const triple = obj.triple as Record<string, unknown>;
  for (const segKey of ['segment1', 'segment2', 'segment3', 'segment4'] as const) {
    if (typeof triple[segKey] !== 'string') {
      throw new Error(`${prefix}.triple.${segKey} must be a string (may be "")`);
    }
  }
  // segment4 = "" is valid (qualifier-free types); segment1..3 may not
  // be empty since they identify namespace/domain/sub-type respectively.
  for (const segKey of ['segment1', 'segment2', 'segment3'] as const) {
    if ((triple[segKey] as string).length === 0) {
      throw new Error(`${prefix}.triple.${segKey} must be a non-empty string`);
    }
  }

  if (typeof obj.linearity !== 'string' || !CELL_TYPE_LINEARITIES.has(obj.linearity)) {
    throw new Error(
      `${prefix}.linearity must be one of "PERSISTENT" | "LINEAR" | "AFFINE" | "EPHEMERAL"`,
    );
  }

  if (obj.description !== undefined && typeof obj.description !== 'string') {
    throw new Error(`${prefix}.description must be a string if provided`);
  }

  if (obj.handler !== undefined) {
    validateHandlerDeclaration(obj.handler, `${prefix}.handler`);
  }

  return obj as unknown as CellTypeDeclaration;
}

/** Regex for lowercase hex strings — any non-zero even length. */
const HEX_RE = /^([0-9a-f]{2})+$/;

/** Regex for a 32-byte hash: exactly 64 lowercase hex chars. */
const SCRIPT_HASH_RE = /^[0-9a-f]{64}$/;

/** Regex for a host-call capability tag (e.g. "cap.spv.verify"). */
const CAPABILITY_TAG_RE = /^[a-z][a-z0-9._-]*$/;

/**
 * Validate a `cellTypes[i].handler` declaration.
 *
 * Strict: protocol violations are rejected at load time so a handler
 * with malformed bytecode reference, bad hash, or invalid capability
 * declarations never reaches the dispatcher.
 *
 * Throws Error with a descriptive prefixed message on validation failure.
 */
export function validateHandlerDeclaration(data: unknown, prefix: string): void {
  if (!data || typeof data !== 'object') {
    throw new Error(`${prefix} must be a non-null object`);
  }
  const obj = data as Record<string, unknown>;

  if (typeof obj.script !== 'string' || obj.script.length === 0) {
    throw new Error(`${prefix}.script must be a non-empty hex string`);
  }
  if (!HEX_RE.test(obj.script)) {
    throw new Error(
      `${prefix}.script must be even-length lowercase hex (got ${(obj.script as string).slice(0, 16)}...)`,
    );
  }

  if (typeof obj.scriptHash !== 'string' || !SCRIPT_HASH_RE.test(obj.scriptHash)) {
    throw new Error(
      `${prefix}.scriptHash must be 64 lowercase hex chars (sha256 of the script bytes)`,
    );
  }

  if (!Array.isArray(obj.capabilities)) {
    throw new Error(`${prefix}.capabilities must be an array of capability tag strings`);
  }
  for (let i = 0; i < (obj.capabilities as unknown[]).length; i++) {
    const tag = (obj.capabilities as unknown[])[i];
    if (typeof tag !== 'string' || !CAPABILITY_TAG_RE.test(tag)) {
      throw new Error(
        `${prefix}.capabilities[${i}] must match /^[a-z][a-z0-9._-]*$/ (got "${String(tag)}")`,
      );
    }
  }

  if (obj.opcountBudget !== undefined) {
    if (
      typeof obj.opcountBudget !== 'number' ||
      !Number.isInteger(obj.opcountBudget) ||
      obj.opcountBudget <= 0
    ) {
      throw new Error(`${prefix}.opcountBudget must be a positive integer if provided`);
    }
  }

  if (!Array.isArray(obj.emits)) {
    throw new Error(`${prefix}.emits must be an array of cell-type name strings`);
  }
  for (let i = 0; i < (obj.emits as unknown[]).length; i++) {
    const name = (obj.emits as unknown[])[i];
    if (typeof name !== 'string' || name.length === 0) {
      throw new Error(`${prefix}.emits[${i}] must be a non-empty cell-type name string`);
    }
  }
}

```
