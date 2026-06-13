---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/lib/legal-cards.mjs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.384074+00:00
---

# scripts/lib/legal-cards.mjs

```mjs
/**
 * legal-cards.mjs — deterministic legal-card renderer for SIR patches.
 *
 * Renders each SIRNode-wrapped patch into a human-legible "legal card"
 * with four sections: plain-English restatement, enables, forecloses,
 * trust/attestation requirements.
 *
 * Critical property: rendering is bit-for-bit deterministic.  No LLM in the
 * render path.  Templates are dispatched per jural category and read only
 * from the patch fields (action, taxonomy, governance, constraint, target,
 * transferTo, gate, fulfillment, provenance).
 *
 * The seven canonical categories (see packages/semantos-sir/src/types.ts):
 *   declaration, obligation, permission, prohibition, power, condition, transfer
 *
 * Terminology: `hatId` replaces `facetId` throughout.  When the upstream SIR
 * types complete the rename, drop the field-name shim in `renderIdentity`.
 */

// ── Patch primitives (mirror packages/loom/src/helm/document-bundle.ts) ──

export const exportBundle = (obj, exportedBy) => ({
  version: 1,
  exportedAt: Date.now(),
  exportedBy,
  documentId: obj.id,
  typeHash:   obj.typeDefinition.typeHash,
  typeName:   obj.typeDefinition.name,
  payload:    { ...obj.payload },
  patches:    obj.patches.map((p) => ({ ...p })),
  visibility: obj.visibility,
  linearity:  obj.header.linearity,
  createdAt:  obj.createdAt,
  updatedAt:  obj.updatedAt,
});

export const diffPatches = (base, incoming) => {
  const baseIds = new Set(base.map((p) => p.id));
  return incoming.filter((p) => !baseIds.has(p.id));
};

export const mergePatches = (existing, selected) => {
  const existingIds = new Set(existing.map((p) => p.id));
  const novel = selected.filter((p) => !existingIds.has(p.id));
  return [...existing, ...novel].sort((a, b) => a.timestamp - b.timestamp);
};

// ── Companion-patch materialisation ──────────────────────────────────────
// An Obligation implies a Permission (entry) and a conditional Transfer
// (payment on fulfilment).  These companions are mechanically derivable from
// the Obligation's fields — we emit them deterministically.
export const materialiseCompanions = (obligation) => {
  if (obligation.sir.category !== 'obligation') return [];
  const f = obligation.sir.fulfillment ?? {};
  const target = obligation.sir.target ?? {};
  const permission = {
    id: `${obligation.id}--perm`,
    kind: 'companion',
    companionOf: obligation.id,
    hatId: obligation.hatId,
    timestamp: obligation.timestamp + 1,
    sir: {
      id: `${obligation.sir.id}--perm`,
      category: 'permission',
      action: 'enter_premises',
      taxonomy: obligation.sir.taxonomy,
      identity: obligation.sir.identity,
      target,
      governance: {
        trustClass: 'interpretive',
        proofRequirement: 'attestation',
        executionAuthority: 'hat_scoped',
        linearity: 'affine',
      },
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'temporal', op: 'before', iso: f.deadline ?? '2099-01-01' },
          { kind: 'state', requiredPhase: 'works-in-progress' },
        ],
      },
      provenance: {
        source: 'inferred',
        confidence: 1.0,
        expressedAt: new Date(obligation.timestamp + 1).toISOString(),
        trustAtExpression: 'interpretive',
      },
    },
    delta: { action: 'grant_permission', companionOf: obligation.id,
             hours: 'weekdays 08:00–17:00', scope: target.objectId ?? 'premises' },
  };
  const transfer = {
    id: `${obligation.id}--pay`,
    kind: 'companion',
    companionOf: obligation.id,
    hatId: obligation.hatId,
    timestamp: obligation.timestamp + 2,
    sir: {
      id: `${obligation.sir.id}--pay`,
      category: 'transfer',
      action: 'pay_contractor',
      taxonomy: obligation.sir.taxonomy,
      identity: { subject: { kind: 'hat', id: 'hat-owner' }, hatId: 'hat-owner' },
      target,
      transferTo: obligation.sir.identity,
      governance: {
        trustClass: 'interpretive',
        proofRequirement: 'attestation',
        executionAuthority: 'hat_scoped',
        linearity: 'linear',
      },
      constraint: {
        kind: 'state', requiredPhase: 'fulfilled',
      },
      provenance: {
        source: 'inferred',
        confidence: 1.0,
        expressedAt: new Date(obligation.timestamp + 2).toISOString(),
        trustAtExpression: 'interpretive',
      },
    },
    delta: { action: 'schedule_payment', amount: obligation.delta.amount,
             currency: obligation.delta.currency ?? 'AUD',
             conditionalOn: `${obligation.id}.fulfilled` },
  };
  return [permission, transfer];
};

// ── Card templates (deterministic, per jural category) ──────────────────

const renderIdentity = (sir) => {
  // Shim: SIR types still expose facetId; accept either, emit hatId.
  const i = sir.identity ?? {};
  return i.hatId ?? i.facetId ?? (i.subject && i.subject.id) ?? 'unknown';
};

const renderAttestation = (gov) => {
  const tc = gov.trustClass;
  const pr = gov.proofRequirement;
  if (tc === 'authoritative' && pr === 'formal')
    return 'authoritative → requires FORMAL attestation from hat-legal';
  if (tc === 'interpretive' && pr === 'attestation')
    return 'interpretive → requires attestation from hat-rea';
  if (tc === 'cosmetic' && pr === 'none')
    return 'cosmetic → no attestation required';
  return `${tc} → ${pr}`;
};

const fmtMoney = (amt, ccy = 'AUD') => {
  if (amt == null) return '';
  const formatted = new Intl.NumberFormat('en-AU', {
    style: 'currency', currency: ccy, maximumFractionDigits: 0,
  }).format(amt);
  return formatted;
};

const fmtDate = (iso) => iso ? iso.slice(0, 10) : '';

const templates = {
  declaration: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const tgt = s.target?.objectId ?? '(target)';
    return {
      header: `DECLARATION · ${s.action}`,
      plain: `${by} declares: ${p.delta.statement ?? s.action} concerning ${tgt}.`,
      enables: p.delta.enables ?? [],
      forecloses: p.delta.forecloses ?? [],
    };
  },

  power: (p) => {
    const s = p.sir;
    const d = s.governance?.domainBinding?.delegation ?? {};
    const grantor = d.delegator?.id ?? renderIdentity(s);
    const grantee = d.delegate?.id ?? '(delegate)';
    const powers = d.delegatedPowers ?? [];
    const restrictions = d.restrictions ?? [];
    const expiry = d.expiry ? ` (expires ${fmtDate(d.expiry)})` : '';
    return {
      header: `POWER · ${s.action}`,
      plain: `${grantor} grants ${grantee} authority to: ${powers.join(', ')}${expiry}.`,
      enables: powers.map((x) => `${grantee} may ${x}`),
      forecloses: [
        ...restrictions.map((r) => `${grantee} ${r}`),
        ...(d.canSubDelegate === false ? [`${grantee} cannot sub-delegate`] : []),
      ],
    };
  },

  obligation: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const desc = p.delta.description ?? s.action;
    const amount = p.delta.amount ? ` for ${fmtMoney(p.delta.amount, p.delta.currency)}` : '';
    const deadline = s.fulfillment?.deadline
      ? ` by ${fmtDate(s.fulfillment.deadline)}` : '';
    return {
      header: `OBLIGATION · ${s.action}`,
      plain: `${by} undertakes to ${desc}${deadline}${amount}.`,
      enables: [
        `Claim on ${fmtMoney(p.delta.amount, p.delta.currency)} upon fulfilment`,
      ].filter((x) => !x.includes('null')),
      forecloses: [
        `${by} cannot subcontract without owner consent`,
        `${by} cannot vary scope without approval patch`,
      ],
    };
  },

  permission: (p) => {
    const s = p.sir;
    const by = renderIdentity(s);
    const scope = p.delta.scope ?? s.target?.objectId ?? '(scope)';
    const hours = p.delta.hours ?? 'as specified';
    const companion = p.companionOf ? ` (companion to ${p.companionOf})` : '';
    return {
      header: `PERMISSION · ${s.action}${companion}`,
      plain: `${by} is permitted to enter ${scope}, ${hours}.`,
      enables: [`Lawful entry during ${hours}`, `Use of designated areas only`],
      forecloses: [
        `No entry outside specified hours`,
        `No access beyond the declared scope`,
      ],
    };
  },

  prohibition: (p) => {
    const s = p.sir;
    const subject = p.delta.subject ?? renderIdentity(s);
    const act = p.delta.prohibitedAct ?? s.action;
    return {
      header: `PROHIBITION · ${s.action}`,
      plain: `${subject} is prohibited from: ${act}.`,
      enables: p.delta.enables ?? [],
      forecloses: [act, ...(p.delta.additionalForecloses ?? [])],
    };
  },

  condition: (p) => {
    const s = p.sir;
    const gate = s.gate ?? {};
    const desc = p.delta.description ?? s.action;
    const requires = p.delta.requires ?? [];
    return {
      header: `CONDITION · ${s.action}`,
      plain: `${desc} is valid only when the following hold: ${requires.join('; ') || '(none specified)'}.`,
      enables: requires.map((r) => `Downstream action unlocked once: ${r}`),
      forecloses: [`Downstream action blocked while any prerequisite is unmet`],
    };
  },

  transfer: (p) => {
    const s = p.sir;
    const from = renderIdentity(s);
    const to = s.transferTo?.subject?.id ?? s.transferTo?.hatId ?? '(recipient)';
    const amount = p.delta.amount ? fmtMoney(p.delta.amount, p.delta.currency) : '(value)';
    const cond = p.delta.conditionalOn ? ` conditional on ${p.delta.conditionalOn}` : '';
    return {
      header: `TRANSFER · ${s.action}`,
      plain: `${from} transfers ${amount} to ${to}${cond}.`,
      enables: [`${to} receives ${amount} upon condition`],
      forecloses: [`${from} balance reduced by ${amount} once executed`],
    };
  },
};

// ── The renderer ─────────────────────────────────────────────────────────
// Pure function: patch in, structured-string out.  Deterministic.
export const renderCard = (patch) => {
  const tmpl = templates[patch.sir.category];
  if (!tmpl) throw new Error(`no template for category: ${patch.sir.category}`);
  const body = tmpl(patch);
  const prov = patch.sir.provenance ?? {};
  const conf = prov.confidence != null
    ? `, confidence ${prov.confidence.toFixed(2)}` : '';
  const proposer = patch.hatId + (prov.source === 'inferred' ? conf : '');
  const where = patch.sir.taxonomy?.where ?? '';
  const domain = patch.sir.governance?.domainBinding
    ? `${patch.sir.governance.domainBinding.domainType}${where ? ' · ' + where : ''}`
    : where;
  const attestation = renderAttestation(patch.sir.governance ?? {});
  const lines = [];
  lines.push(`PROPOSED: ${body.header}   (by ${proposer})`);
  lines.push(`  patch id: ${patch.id}   category: ${patch.sir.category}`);
  if (domain) lines.push(`  domain:   ${domain}`);
  lines.push(`  ${attestation}`);
  lines.push(``);
  lines.push(`  In plain terms:`);
  lines.push(`    ${body.plain}`);
  if (body.enables.length) {
    lines.push(``);
    lines.push(`  Enables:`);
    for (const e of body.enables) lines.push(`    · ${e}`);
  }
  if (body.forecloses.length) {
    lines.push(``);
    lines.push(`  Forecloses:`);
    for (const f of body.forecloses) lines.push(`    · ${f}`);
  }
  return lines.join('\n');
};

// ── Condition evaluator ──────────────────────────────────────────────────
// A terminal Declaration gated by a Condition only folds successfully when
// every prerequisite is satisfied in the current chain state.
export const evaluateCondition = (conditionPatch, chainState) => {
  const requires = conditionPatch.delta.requires ?? [];
  const unmet = requires.filter((req) => !chainState.satisfied.has(req));
  return {
    satisfied: unmet.length === 0,
    unmet,
  };
};

// ── HTML Blueprint renderer ──────────────────────────────────────────────
// Produces a standalone, presentable blueprint.html from the final IR.
// Same determinism discipline: pure function over the patch chain, no LLM.

const escape = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const categoryBadge = (cat) => {
  const colours = {
    declaration: '#5b8def', obligation: '#f0a14a', permission: '#5cc79a',
    prohibition: '#e06666', power: '#a46ecb', condition: '#7a7a7a',
    transfer: '#4aa3d9',
  };
  return `<span class="badge" style="background:${colours[cat] ?? '#777'}">${cat.toUpperCase()}</span>`;
};

const trustBadge = (tc) => {
  const c = { cosmetic: '#ddd', interpretive: '#fbe', authoritative: '#fcc' };
  return `<span class="trust" style="background:${c[tc] ?? '#eee'}">${tc}</span>`;
};

const cardToHtml = (patch) => {
  const tmpl = templates[patch.sir.category];
  const body = tmpl(patch);
  const gov = patch.sir.governance ?? {};
  return `
    <article class="card cat-${patch.sir.category}">
      <header>
        ${categoryBadge(patch.sir.category)}
        ${trustBadge(gov.trustClass ?? 'interpretive')}
        <span class="action">${escape(patch.sir.action)}</span>
        <span class="pid">${escape(patch.id)}</span>
      </header>
      <div class="provenance">
        proposed by <b>${escape(patch.hatId)}</b>
        ${patch.sir.provenance?.confidence != null
          ? `<span class="conf">confidence ${patch.sir.provenance.confidence.toFixed(2)}</span>` : ''}
        ${patch.companionOf ? `<span class="comp">companion to ${escape(patch.companionOf)}</span>` : ''}
      </div>
      <p class="plain">${escape(body.plain)}</p>
      ${body.enables.length ? `
        <div class="section enables">
          <h4>Enables</h4>
          <ul>${body.enables.map((e) => `<li>${escape(e)}</li>`).join('')}</ul>
        </div>` : ''}
      ${body.forecloses.length ? `
        <div class="section forecloses">
          <h4>Forecloses</h4>
          <ul>${body.forecloses.map((f) => `<li>${escape(f)}</li>`).join('')}</ul>
        </div>` : ''}
      <footer>
        <span class="attest">${escape(renderAttestation(gov))}</span>
      </footer>
    </article>`;
};

export const renderBlueprintHtml = ({ title, subtitle, hats, patches, readiness }) => {
  const groups = {};
  for (const p of patches) {
    (groups[p.sir.category] ??= []).push(p);
  }
  const order = ['power', 'declaration', 'obligation', 'permission', 'transfer', 'prohibition', 'condition'];
  const sections = order
    .filter((c) => groups[c]?.length)
    .map((c) => `
      <section class="group group-${c}">
        <h2>${c[0].toUpperCase() + c.slice(1)}s <span class="count">(${groups[c].length})</span></h2>
        ${groups[c].map(cardToHtml).join('')}
      </section>`).join('');

  const readinessHtml = readiness ? `
    <section class="readiness ${readiness.satisfied ? 'ready' : 'blocked'}">
      <h2>${readiness.satisfied ? '✓ Ready for Auction' : '⚠ Not Ready'}</h2>
      <ul class="checklist">
        ${readiness.requires.map((r) => `
          <li class="${readiness.satisfied || !readiness.unmet.includes(r) ? 'done' : 'pending'}">
            ${readiness.satisfied || !readiness.unmet.includes(r) ? '✓' : '○'} ${escape(r)}
          </li>`).join('')}
      </ul>
    </section>` : '';

  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>${escape(title)}</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
         max-width: 920px; margin: 2em auto; padding: 0 1em; color: #222; line-height: 1.5; }
  h1 { margin-bottom: 0; } .subtitle { color: #666; margin-top: 0.3em; }
  .hats { background: #f5f5f5; padding: 1em 1.2em; border-radius: 6px; margin: 1.5em 0; }
  .hats h3 { margin: 0 0 0.4em 0; font-size: 0.9em; text-transform: uppercase;
             letter-spacing: 0.08em; color: #666; }
  .hats ul { margin: 0; padding: 0; list-style: none; column-count: 2; font-size: 0.93em; }
  .hats code { background: #fff; padding: 1px 5px; border-radius: 3px; font-size: 0.88em; }
  section.group { margin: 2em 0 1.5em; }
  section.group > h2 { border-bottom: 2px solid #eee; padding-bottom: 0.3em;
                        font-size: 1.15em; letter-spacing: 0.03em; }
  .count { color: #999; font-weight: normal; font-size: 0.85em; }
  .card { border: 1px solid #ddd; border-radius: 6px; padding: 0.9em 1.1em;
          margin: 0.7em 0; background: #fafafa; }
  .card header { display: flex; flex-wrap: wrap; gap: 0.6em; align-items: center;
                 margin-bottom: 0.5em; font-size: 0.85em; }
  .badge { color: #fff; padding: 2px 8px; border-radius: 3px; font-size: 0.72em;
           font-weight: 600; letter-spacing: 0.04em; }
  .trust { padding: 2px 7px; border-radius: 3px; font-size: 0.72em; color: #444; }
  .action { font-family: "SF Mono", Consolas, monospace; color: #333;
            background: #eef; padding: 1px 6px; border-radius: 3px; font-size: 0.85em; }
  .pid { color: #999; font-size: 0.78em; margin-left: auto; font-family: monospace; }
  .provenance { color: #666; font-size: 0.85em; margin-bottom: 0.6em; }
  .provenance .conf { color: #888; margin-left: 0.6em; }
  .provenance .comp { color: #5cc79a; margin-left: 0.6em; font-style: italic; }
  .plain { margin: 0.5em 0; font-size: 1em; }
  .section { margin: 0.7em 0 0; padding: 0.5em 0.9em; border-radius: 4px; font-size: 0.92em; }
  .enables { background: #e8f5e9; border-left: 3px solid #5cc79a; }
  .forecloses { background: #ffebee; border-left: 3px solid #e06666; }
  .section h4 { margin: 0 0 0.3em; font-size: 0.8em; text-transform: uppercase;
                letter-spacing: 0.05em; color: #444; }
  .section ul { margin: 0; padding-left: 1.2em; }
  .section li { margin: 0.15em 0; }
  footer { margin-top: 0.5em; font-size: 0.8em; color: #888; }
  .readiness { padding: 1em 1.3em; border-radius: 6px; margin: 2em 0; }
  .readiness.ready { background: #e8f5e9; border: 2px solid #5cc79a; }
  .readiness.blocked { background: #fff3e0; border: 2px solid #f0a14a; }
  .readiness h2 { margin: 0 0 0.5em; }
  .checklist { list-style: none; padding: 0; margin: 0; }
  .checklist li { padding: 0.2em 0; font-family: "SF Mono", Consolas, monospace; }
  .checklist li.done { color: #2e7d32; }
  .checklist li.pending { color: #c77; }
</style>
</head><body>
  <h1>${escape(title)}</h1>
  <p class="subtitle">${escape(subtitle ?? '')}</p>
  <div class="hats">
    <h3>Hat Roster</h3>
    <ul>${hats.map((h) => `<li><code>${escape(h.id)}</code> — ${escape(h.role)}</li>`).join('')}</ul>
  </div>
  ${readinessHtml}
  ${sections}
  <footer style="text-align:center; color:#999; font-size:0.8em; margin-top:3em;">
    Generated deterministically from the semantos SIR patch chain · no LLM in render path
  </footer>
</body></html>`;
};

```
