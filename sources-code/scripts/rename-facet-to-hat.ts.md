---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/rename-facet-to-hat.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.320536+00:00
---

# scripts/rename-facet-to-hat.ts

```ts
/**
 * scripts/rename-facet-to-hat.ts
 *
 * Codemod for PRD docs/prd/refactor-monoliths/00A-facet-to-hat-rename.md.
 *
 * Symbol-aware rename of the runtime-level identity concept:
 *   interface  Facet             → Hat
 *   interface  FacetLike         → HatLike
 *   property   Identity.facets   → hats
 *   property   Identity.activeFacetId → activeHatId
 *   property   IdentityLike.facets, IdentityLike.activeFacetId (runtime/intent) — same
 *   property   ConversationMessage.facetId → hatId
 *   property   ObjectPatch.facetId → hatId
 *   property   ObjectPatch.facetCapabilities → hatCapabilities
 *   methods    IdentityStore.{getActiveFacet, switchFacet, addFacet, addFacetImpl} → …Hat
 *   methods    IdentityServiceLike.getActiveFacet → getActiveHat
 *   fn         createFacetObject → createHatObject
 *   local var  FACET_TYPE → HAT_TYPE (variable name only; typeHash + .name wire-level, left as 'Facet')
 *
 * Wire-level strings left intact:
 *   - FACET_TYPE.typeHash (SHA256("semantos.system.Facet"))
 *   - FACET_TYPE.name = 'Facet'
 *   - FACET_TYPE.fields[].name = 'activeFacetId'
 *   - localStorage key 'workbench-identity'
 *   - Serialised JSON keys in SerializedIdentity (handled in a separate hydration shim pass).
 *
 * File renames handled outside this script via `git mv` in a follow-up step.
 *
 * Run: `bun scripts/rename-facet-to-hat.ts [--dry-run]`
 */

import { Project, SyntaxKind, Node } from 'ts-morph';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { glob } from 'glob';

const ROOT = path.resolve(__dirname, '..');
const DRY = process.argv.includes('--dry-run');

const SOURCE_GLOBS = [
  'core/*/src/**/*.{ts,tsx}',
  'runtime/*/src/**/*.{ts,tsx}',
  'runtime/*/tests/**/*.{ts,tsx}',
  'extensions/*/src/**/*.{ts,tsx}',
  'apps/*/src/**/*.{ts,tsx}',
  'apps/loom-react/src/**/*.{js,jsx}',
  'apps/loom-react/src/**/*.d.ts',
  'tests/gates/**/*.ts',
  'scripts/**/*.ts',
];

const IGNORE = [
  '**/node_modules/**',
  '**/dist/**',
  '**/.cowork-backups/**',
  '**/archive/**',
  '**/.claude/**',
  // Don't rewrite the codemod itself.
  'scripts/rename-facet-to-hat.ts',
];

function log(msg: string) {
  console.log(`[rename] ${msg}`);
}

async function collectSourceFiles(): Promise<string[]> {
  const out = new Set<string>();
  for (const pattern of SOURCE_GLOBS) {
    const matches = await glob(pattern, { cwd: ROOT, ignore: IGNORE, absolute: true });
    for (const m of matches) out.add(m);
  }
  return Array.from(out).sort();
}

async function main() {
  const files = await collectSourceFiles();
  log(`loading ${files.length} source files`);

  const project = new Project({
    skipAddingFilesFromTsConfig: true,
    compilerOptions: {
      target: 99,           // ESNext
      module: 99,           // ESNext
      moduleResolution: 100, // Bundler
      jsx: 4,                // ReactJSX
      allowJs: true,
      strict: false,
      noEmit: true,
      skipLibCheck: true,
      esModuleInterop: true,
      isolatedModules: true,
    },
  });

  for (const f of files) project.addSourceFileAtPath(f);
  log('files loaded. resolving symbols…');

  // ── 1. Rename the canonical `Facet` interface ────────────────
  // Idempotent: if already renamed, skip.
  const loomTypesPath = path.join(ROOT, 'runtime/services/src/types/loom.ts');
  const loomTypesFile = project.getSourceFileOrThrow(loomTypesPath);
  const facetInterface = loomTypesFile.getInterface('Facet');
  if (facetInterface) {
    log('rename interface Facet → Hat');
    facetInterface.rename('Hat');
  } else if (!loomTypesFile.getInterface('Hat')) {
    throw new Error('Neither `Facet` nor `Hat` interface found in runtime/services/src/types/loom.ts');
  }

  // ── 2. Rename `Identity` properties ──────────────────────────
  const identityInterface = loomTypesFile.getInterfaceOrThrow('Identity');
  const facetsProp = identityInterface.getProperty('facets');
  if (facetsProp) {
    log('rename Identity.facets → hats');
    facetsProp.rename('hats');
  }
  const activeFacetIdProp = identityInterface.getProperty('activeFacetId');
  if (activeFacetIdProp) {
    log('rename Identity.activeFacetId → activeHatId');
    activeFacetIdProp.rename('activeHatId');
  }

  // ── 3. Rename ConversationMessage.facetId → hatId ───────────
  const convoMsg = loomTypesFile.getInterface('ConversationMessage');
  if (convoMsg) {
    const facetIdProp = convoMsg.getProperty('facetId');
    if (facetIdProp) {
      log('rename ConversationMessage.facetId → hatId');
      facetIdProp.rename('hatId');
    }
  }

  // ── 4. Rename ObjectPatch.facetId and .facetCapabilities ────
  const objectPatch = loomTypesFile.getInterface('ObjectPatch');
  if (objectPatch) {
    const pFid = objectPatch.getProperty('facetId');
    if (pFid) {
      log('rename ObjectPatch.facetId → hatId');
      pFid.rename('hatId');
    }
    const pFc = objectPatch.getProperty('facetCapabilities');
    if (pFc) {
      log('rename ObjectPatch.facetCapabilities → hatCapabilities');
      pFc.rename('hatCapabilities');
    }
  }

  // ── 5. Rename FacetLike + IdentityLike/IdentityServiceLike ───
  const hatContextPath = path.join(ROOT, 'runtime/intent/src/hat-context.ts');
  const hatContextFile = project.getSourceFile(hatContextPath);
  if (hatContextFile) {
    const facetLike = hatContextFile.getInterface('FacetLike');
    if (facetLike) {
      log('rename interface FacetLike → HatLike');
      facetLike.rename('HatLike');
    }
    const identityLike = hatContextFile.getInterface('IdentityLike');
    if (identityLike) {
      const p1 = identityLike.getProperty('facets');
      if (p1) { log('rename IdentityLike.facets → hats'); p1.rename('hats'); }
      const p2 = identityLike.getProperty('activeFacetId');
      if (p2) { log('rename IdentityLike.activeFacetId → activeHatId'); p2.rename('activeHatId'); }
    }
    const idSvcLike = hatContextFile.getInterface('IdentityServiceLike');
    if (idSvcLike) {
      const m = idSvcLike.getMethod('getActiveFacet');
      if (m) {
        log('rename IdentityServiceLike.getActiveFacet → getActiveHat');
        m.rename('getActiveHat');
      }
    }
  }

  // ── 6. Rename HatContext.facetId (drop the duplicate) ───────
  const intentTypesPath = path.join(ROOT, 'runtime/intent/src/types.ts');
  const intentTypesFile = project.getSourceFile(intentTypesPath);
  if (intentTypesFile) {
    const hatContext = intentTypesFile.getInterface('HatContext');
    if (hatContext) {
      // HatContext already has `hatId` — rename the duplicate `facetId` to
      // something that won't collide, then remove it in a second pass
      // (ts-morph can't directly rename-to-delete). We'll simply remove the
      // property here; references elsewhere in the codebase need to be
      // updated manually but there shouldn't be any (it's been live only
      // since the intent pipeline landed).
      const dup = hatContext.getProperty('facetId');
      if (dup) {
        log('remove HatContext.facetId (duplicate of hatId)');
        dup.remove();
      }
    }
  }

  // ── 7. Rename IdentityStore methods ──────────────────────────
  const identityStorePath = path.join(ROOT, 'runtime/services/src/services/IdentityStore.ts');
  const identityStoreFile = project.getSourceFile(identityStorePath);
  if (identityStoreFile) {
    const cls = identityStoreFile.getClassOrThrow('IdentityStore');
    const renames: Array<[string, string]> = [
      ['getActiveFacet', 'getActiveHat'],
      ['switchFacet', 'switchHat'],
      ['addFacet', 'addHat'],
      ['addFacetImpl', 'addHatImpl'],
    ];
    for (const [from, to] of renames) {
      const m = cls.getMethod(from);
      if (m) {
        log(`rename IdentityStore.${from} → ${to}`);
        m.rename(to);
      }
    }
    // ── Free functions in the same file ───────────────────────
    const createFn = identityStoreFile.getFunction('createFacetObject');
    if (createFn) {
      log('rename createFacetObject → createHatObject');
      createFn.rename('createHatObject');
    }
    // ── Local const FACET_TYPE → HAT_TYPE (variable only) ─────
    const facetTypeDecl = identityStoreFile.getVariableDeclaration('FACET_TYPE');
    if (facetTypeDecl) {
      log('rename local const FACET_TYPE → HAT_TYPE (wire strings preserved)');
      facetTypeDecl.rename('HAT_TYPE');
    }
  }

  // ── 7a. runtime/shell types ShellContext + ShellConfig ──────
  // These interfaces declare `activeFacetId` / `activeFacetCertId` — internal
  // field names only. TOML `shell.active_facet` and SEMANTOS_FACET env var
  // (wire) keep their legacy names; the load path sets the renamed field.
  const shellTypesPath = path.join(ROOT, 'runtime/shell/src/types.ts');
  const shellTypesFile = project.getSourceFile(shellTypesPath);
  if (shellTypesFile) {
    for (const ifaceName of ['ShellContext', 'ShellConfig']) {
      const iface = shellTypesFile.getInterface(ifaceName);
      if (!iface) continue;
      for (const [from, to] of [
        ['activeFacetId', 'activeHatId'],
        ['activeFacetCertId', 'activeHatCertId'],
      ] as const) {
        const p = iface.getProperty(from);
        if (p) {
          log(`rename ${ifaceName}.${from} → ${to}`);
          p.rename(to);
        }
      }
    }
  }

  // ── 7b. loom-react IdentityProvider context interface ───────
  const idProviderPath = path.join(ROOT, 'apps/loom-react/src/identity/IdentityProvider.tsx');
  const idProviderFile = project.getSourceFile(idProviderPath);
  if (idProviderFile) {
    const ctxIface = idProviderFile.getInterface('IdentityContextValue');
    if (ctxIface) {
      const activeFacet = ctxIface.getProperty('activeFacet');
      if (activeFacet) {
        log('rename IdentityContextValue.activeFacet → activeHat');
        activeFacet.rename('activeHat');
      }
      for (const [from, to] of [
        ['addFacet', 'addHat'],
        ['switchFacet', 'switchHat'],
      ] as const) {
        const prop = ctxIface.getProperty(from);
        if (prop) {
          log(`rename IdentityContextValue.${from} → ${to}`);
          prop.rename(to);
        }
      }
    }
  }

  // ── 7c. Local helpers in runtime/shell/src/router*.ts ──────
  for (const relPath of ['runtime/shell/src/router.ts', 'runtime/shell/src/router-browser.ts']) {
    const sf = project.getSourceFile(path.join(ROOT, relPath));
    if (!sf) continue;
    const fn = sf.getFunction('getActiveFacet');
    if (fn) {
      log(`rename ${relPath} getActiveFacet → getActiveHat`);
      fn.rename('getActiveHat');
    }
  }

  // ── 7d. chat.ts local interfaces ChatMessage/ChatState ─────
  const chatPath = path.join(ROOT, 'runtime/shell/src/chat.ts');
  const chatFile = project.getSourceFile(chatPath);
  if (chatFile) {
    for (const ifaceName of chatFile.getInterfaces().map((i) => i.getName())) {
      const iface = chatFile.getInterfaceOrThrow(ifaceName);
      for (const [from, to] of [
        ['facet', 'hat'],
        ['activeFacet', 'activeHat'],
      ] as const) {
        const prop = iface.getProperty(from);
        if (prop) {
          log(`rename ${ifaceName}.${from} → ${to}`);
          prop.rename(to);
        }
      }
    }
  }

  // ── 8. buildHatContext return-shape cleanup ──────────────────
  // buildHatContext currently returns `{ hatId, facetId, …}` — the
  // facetId duplicate has already been removed from HatContext, but the
  // literal still exists in the function body and will no longer
  // compile. We rewrite it here.
  const hatCtxBuilderPath = path.join(ROOT, 'runtime/intent/src/hat-context.ts');
  const hatCtxBuilder = project.getSourceFile(hatCtxBuilderPath);
  if (hatCtxBuilder) {
    hatCtxBuilder.forEachDescendant((n) => {
      if (Node.isPropertyAssignment(n) && n.getName() === 'facetId') {
        const parent = n.getParent();
        // Only remove inside object literals that look like a HatContext
        // return — the simplest signal is a sibling `hatId` assignment.
        if (Node.isObjectLiteralExpression(parent)) {
          const hasHatId = parent.getProperties().some(
            (p) => Node.isPropertyAssignment(p) && p.getName() === 'hatId',
          );
          if (hasHatId) {
            log(`remove duplicate facetId property at ${hatCtxBuilder.getFilePath()}:${n.getStartLineNumber()}`);
            n.remove();
          }
        }
      }
    });
  }

  // ── Persist ──────────────────────────────────────────────────
  if (DRY) {
    log('dry-run — not saving');
    const touched = project.getSourceFiles().filter((sf) => !sf.isSaved());
    log(`would touch ${touched.length} files:`);
    for (const f of touched) console.log('  ' + path.relative(ROOT, f.getFilePath()));
  } else {
    log('saving…');
    await project.save();
    log('done.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

```
