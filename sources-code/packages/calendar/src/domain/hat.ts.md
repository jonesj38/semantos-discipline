---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/domain/hat.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.479028+00:00
---

# packages/calendar/src/domain/hat.ts

```ts
/**
 * Hats: identity facets. Stored as `sem_objects` rows with
 * `object_kind: 'hat'`. Hats attribute patches on the schedule but do
 * NOT own their own patch streams — the schedule is the one stream.
 *
 * The hat tree (parent/child via `parent_id`) is display metadata: it
 * lets a UI render "Todd › Handyman" hierarchies. Conflict detection is
 * agnostic to hat ancestry — ONE physical person has ONE schedule.
 *
 * D-A5 (Phase 1b): migrated to BRC-52 cert backing. The opaque `hatId`
 * is now a `cert_id` — the SHA-256 of a BRC-52 cert preimage per
 * docs/spec/protocol-v0.5.md §4.2. `HatPayload` is the BRC-52 payload
 * schema attached to that cert. Cross-context isolation per §4.4 is
 * enforced by deriveHatCertId(): two hats derived under different
 * contexts (`contextTag`) produce mathematically unrelated cert_ids,
 * because the contextTag participates in the BRC-52 preimage and the
 * subjectPublicKey is itself derived (BRC-42 BKDS) under a per-context
 * derivation path.
 *
 * Canon discipline (per docs/canon/glossary.yml id: hat): "hat" is the
 * canonical alias; "facet" is the drift pair retained for legacy
 * plumbing on the patch envelope (`facetId` field of appendPatch). Do
 * not rename to facet.
 *
 * Backward compatibility (engineering decision): `CreateHatInput.id`
 * still accepts an arbitrary string. When the caller supplies a string
 * id directly, it is treated as a self-issued cert_id (the hat acts as
 * its own cert). Callers who want context-isolated, cryptographically
 * provenance-bearing hats use `deriveHatCertId(...)` and pass the
 * resulting cert_id as `id`. This keeps every existing call site
 * working without a code change while providing the BRC-52 path
 * required by §4.4.
 *
 * Spec sources: docs/spec/protocol-v0.5.md §4.2 (BRC-52 cert format),
 *               §4.4 (cross-context isolation), §4.5 (domain flags).
 * BRC standards: BRC-52 (cert identity binding), BRC-42 (BKDS context
 *                separation in the derivation path; the subject pubkey
 *                is derived from a parent secret under a per-context
 *                domain flag).
 */
import { eq, and } from 'drizzle-orm';
import type { Database } from '@semantos/semantic-objects';
import {
  createObject,
  getObject,
  semObjects,
} from '@semantos/semantic-objects';
import {
  computeCertId,
  type Brc52Cert,
} from '@plexus/contracts';

// ── BRC-52 payload schema ────────────────────────────────────────────────────

/**
 * HatPayload — the BRC-52 application-payload schema attached to a hat's
 * cert. Stored verbatim in the `sem_objects.payload` column of the row
 * with `object_kind: 'hat'`.
 *
 * D-A5: the schema gains a `certBacking` discriminator. When present, it
 * documents the cert that backs this hat (subject/certifier keys, cert
 * type, contextTag for §4.4 isolation); when absent, the hat is the
 * legacy self-issued form (cert_id == arbitrary string id supplied at
 * creation time).
 */
export interface HatPayload {
  displayName: string;
  timezone: string;
  weekendsEnabled: boolean;
  ownerCertId: string;
  /**
   * BRC-52 cert backing for this hat. Optional for backward compat: hats
   * created via the legacy opaque-id path (see `CreateHatInput.id`)
   * carry no certBacking; hats created via `deriveHatCertId` + a
   * Brc52Cert-derived id carry the full record. Future migrations may
   * elevate this to required.
   */
  certBacking?: HatCertBacking;
}

/**
 * Subset of a `Brc52Cert` (D-A0b — `core/plexus-contracts/src/identity.ts`)
 * persisted alongside the hat for provenance. We do NOT persist the
 * issuer signature here — the source-of-truth cert lives in the Plexus
 * DAG; this is a snapshot for offline display + audit + cross-context
 * isolation invariants (§4.4).
 */
export interface HatCertBacking {
  /** 33-byte compressed secp256k1 pubkey, hex. The hat's signing key. */
  subjectPublicKey: string;
  /** Issuer pubkey (parent cert key, or self for root). */
  certifierPublicKey: string;
  /** Cert type, e.g. "calendar.hat". */
  type: string;
  /** Cert serial number (hex SHA-256 of derivation inputs). */
  serialNumber: string;
  /**
   * Context tag — opaque caller-defined string that participates in the
   * BRC-52 preimage's `fields`. Two hats with the same displayName but
   * different contextTags MUST yield different cert_ids; this is the
   * §4.4 cross-context isolation contract.
   */
  contextTag: string;
}

// ── Records returned to callers ──────────────────────────────────────────────

export interface HatRecord {
  /**
   * cert_id of the hat's BRC-52 cert (D-A5). Lowercase 64-char hex when
   * the hat was created via `deriveHatCertId`; arbitrary string for
   * legacy opaque-id hats. The `hatId` getter alias on this record is
   * an explicit deprecation target for one release.
   */
  id: string;
  parentHatId: string | null;
  displayName: string;
  timezone: string;
  weekendsEnabled: boolean;
  ownerCertId: string;
  /** Present iff the hat was created with a Brc52Cert backing. */
  certBacking: HatCertBacking | null;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Backward-compat alias on the record. Reads `record.id`. Callers
 * should migrate to `record.id` (which is now `cert_id`); kept for
 * one release to avoid a flag-day rename across the existing call sites
 * cited in `packages/calendar/src/__tests__`.
 *
 * @deprecated use `record.id` (now equal to cert_id when BRC-52-backed).
 */
export function hatIdOf(record: HatRecord): string {
  return record.id;
}

// ── Input shapes ─────────────────────────────────────────────────────────────

/**
 * CreateHatInput retains the original opaque-id surface for back-compat.
 * Two valid creation modes:
 *
 *   1. Legacy / self-issued: pass `id: <arbitrary string>`. The string
 *      is taken as the cert_id directly. No certBacking is recorded.
 *   2. BRC-52-backed: compute `id` via `deriveHatCertId({...})` and pass
 *      the matching `cert` to populate `certBacking`. The `id` MUST
 *      equal `computeCertId(cert)` — `createHat` enforces this.
 *
 * Callers in mode (2) get cross-context isolation per §4.4.
 */
export interface CreateHatInput {
  /**
   * cert_id of the hat. May be an arbitrary string (legacy mode) or
   * `deriveHatCertId(...)` output (BRC-52-backed mode).
   */
  id: string;
  parentHatId?: string;
  displayName: string;
  timezone: string;
  weekendsEnabled?: boolean;
  ownerCertId: string;
  /**
   * Optional BRC-52 cert that backs this hat. When supplied, the
   * persisted certBacking is derived from it AND we assert that
   * `input.id === computeCertId(cert)` to ensure the cert_id stored on
   * the row is the canonical hash of the cert. The contextTag is read
   * from `cert.fields.contextTag` if present, else defaults to "default".
   */
  cert?: Brc52Cert;
  /**
   * Override the contextTag captured in certBacking. Useful when callers
   * derive a cert_id via `deriveHatCertId(... contextTag)` but want the
   * persisted backing to reflect the same tag. If `cert` is supplied
   * AND its `fields.contextTag` differs from this value, createHat
   * throws (the two MUST agree — divergence would break §4.4 audit).
   */
  contextTag?: string;
}

// ── Cert-id derivation (BRC-52 + §4.4 cross-context isolation) ───────────────

/**
 * Spec for deriving a deterministic BRC-52 cert_id for a hat.
 *
 * subjectPublicKey: the hat's signing key. In a real flow this comes
 *   from a BRC-42 BKDS derivation under the operator's parent secret +
 *   a per-context domain flag (§4.5). For tests / offline derivation it
 *   may be supplied directly. The KEY discipline §4.4 requires is that
 *   two hats in two contexts do NOT share a subjectPublicKey unless
 *   they are mathematically the same hat — which the BRC-42 derivation
 *   path enforces (different domain flags ⇒ different keys ⇒ different
 *   cert_ids).
 *
 * certifierPublicKey: the issuer's pubkey (parent cert's subject key,
 *   or self for root certs).
 *
 * contextTag: scope identifier — "personal-calendar", "work-calendar",
 *   "tenant:42", etc. Participates in the cert preimage so the cert_id
 *   diverges across contexts even if the subjectPublicKey were
 *   accidentally reused. Defence in depth atop §4.4.
 */
export interface HatCertSpec {
  subjectPublicKey: string;
  certifierPublicKey: string;
  /** BRC-52 cert type. Defaults to "calendar.hat". */
  type?: string;
  /** Serial number. Defaults to a deterministic combination of (contextTag, displayName). */
  serialNumber?: string;
  /** Context label for §4.4 cross-context isolation. Required. */
  contextTag: string;
  /** Hat metadata to bind into the cert preimage's `fields`. */
  displayName: string;
  /** Optional extra fields stitched into the BRC-52 preimage. */
  extraFields?: Record<string, string>;
}

/**
 * Deterministically derive a hat's BRC-52 cert_id from a HatCertSpec.
 *
 * Algorithm:
 *   1. Build a Brc52Cert preimage with fields = {
 *        contextTag, displayName, ...extraFields
 *      }.
 *   2. computeCertId(cert) → 64-char lowercase hex SHA-256 of the
 *      canonical preimage (canonicalCertPreimage in
 *      core/plexus-contracts/src/identity.ts).
 *
 * §4.4 invariant: two specs that differ only in `contextTag` produce
 * different cert_ids; tested in
 * `packages/calendar/src/__tests__/hat.test.ts`.
 */
export function deriveHatCertId(spec: HatCertSpec): string {
  const fields: Record<string, string> = {
    contextTag: spec.contextTag,
    displayName: spec.displayName,
    ...(spec.extraFields ?? {}),
  };
  const cert: Pick<Brc52Cert, 'subjectPublicKey' | 'certifierPublicKey' | 'type' | 'serialNumber' | 'fields'> = {
    subjectPublicKey: spec.subjectPublicKey,
    certifierPublicKey: spec.certifierPublicKey,
    type: spec.type ?? 'calendar.hat',
    serialNumber:
      spec.serialNumber ?? defaultSerialNumber(spec.contextTag, spec.displayName),
    fields,
  };
  return computeCertId(cert);
}

/**
 * Build a fully-formed Brc52Cert from a spec (signature stubbed —
 * real signing happens in the cert issuance flow inside Plexus). The
 * returned cert's `certId` equals `deriveHatCertId(spec)`.
 *
 * Use this when you want to persist the full certBacking alongside the
 * hat. The signature field is empty — callers MUST replace it before
 * the cert leaves the local node.
 */
export function buildHatCert(spec: HatCertSpec): Brc52Cert {
  const fields: Record<string, string> = {
    contextTag: spec.contextTag,
    displayName: spec.displayName,
    ...(spec.extraFields ?? {}),
  };
  const partial = {
    subjectPublicKey: spec.subjectPublicKey,
    certifierPublicKey: spec.certifierPublicKey,
    type: spec.type ?? 'calendar.hat',
    serialNumber:
      spec.serialNumber ?? defaultSerialNumber(spec.contextTag, spec.displayName),
    fields,
  };
  return {
    ...partial,
    certId: computeCertId(partial),
    signature: '',
  };
}

/**
 * Default deterministic serial number — SHA-256 over (contextTag, displayName).
 * A real cert flow uses BRC-42 derivation outputs; this default is fine for
 * test fixtures and offline cert IDs.
 */
function defaultSerialNumber(contextTag: string, displayName: string): string {
  // Reuse the same canonicalisation discipline as cert preimages: sorted-key JSON.
  const obj = { contextTag, displayName };
  const json = JSON.stringify(obj, Object.keys(obj).sort());
  // Hash via @bsv/sdk Hash.sha256 — already a transitive dep through @plexus/contracts.
  // We avoid importing it directly here to keep this module's dep surface minimal;
  // computeCertId already pulls it. So we re-use computeCertId on a marker cert.
  return computeCertId({
    subjectPublicKey: '00'.repeat(33),
    certifierPublicKey: '00'.repeat(33),
    type: 'serial',
    serialNumber: '00'.repeat(32),
    fields: { canonical: json },
  });
}

// ── Mutators ─────────────────────────────────────────────────────────────────

export async function createHat(
  db: Database,
  input: CreateHatInput,
): Promise<HatRecord> {
  const certBacking = certBackingFromInput(input);
  const payload: HatPayload = {
    displayName: input.displayName,
    timezone: input.timezone,
    weekendsEnabled: input.weekendsEnabled ?? false,
    ownerCertId: input.ownerCertId,
    ...(certBacking ? { certBacking } : {}),
  };
  const obj = await createObject<HatPayload>(db, {
    id: input.id,
    objectKind: 'hat',
    parentId: input.parentHatId,
    payload,
    createdByCertId: input.ownerCertId,
  });
  return {
    id: obj.id,
    parentHatId: obj.parentId,
    displayName: obj.payload.displayName,
    timezone: obj.payload.timezone,
    weekendsEnabled: obj.payload.weekendsEnabled,
    ownerCertId: obj.payload.ownerCertId,
    certBacking: obj.payload.certBacking ?? null,
    createdAt: obj.createdAt,
    updatedAt: obj.updatedAt,
  };
}

/**
 * Build the persisted certBacking from CreateHatInput, enforcing the
 * cert_id ↔ input.id agreement when a Brc52Cert is supplied.
 */
function certBackingFromInput(input: CreateHatInput): HatCertBacking | undefined {
  if (!input.cert && input.contextTag === undefined) return undefined;

  if (input.cert) {
    const expectedId = computeCertId(input.cert);
    if (expectedId !== input.id) {
      throw new Error(
        `createHat: input.id (${input.id}) does not match computeCertId(cert) (${expectedId}). ` +
          'When a BRC-52 cert backing is supplied, input.id MUST be the cert_id of that cert.',
      );
    }
    const certContextTag = input.cert.fields.contextTag ?? 'default';
    if (input.contextTag !== undefined && input.contextTag !== certContextTag) {
      throw new Error(
        `createHat: contextTag mismatch — input.contextTag=${input.contextTag} but cert.fields.contextTag=${certContextTag}. ` +
          'These MUST agree to preserve §4.4 cross-context isolation audit.',
      );
    }
    return {
      subjectPublicKey: input.cert.subjectPublicKey,
      certifierPublicKey: input.cert.certifierPublicKey,
      type: input.cert.type,
      serialNumber: input.cert.serialNumber,
      contextTag: certContextTag,
    };
  }

  // contextTag-only path (no cert) is not supported — we need at minimum a
  // subjectPublicKey to record meaningful BRC-52 backing. Callers should
  // supply `cert`. Returning undefined here keeps the legacy path intact.
  return undefined;
}

// ── Queries ──────────────────────────────────────────────────────────────────

export async function getHat(db: Database, hatId: string): Promise<HatRecord | null> {
  const obj = await getObject<HatPayload>(db, hatId);
  if (!obj || obj.objectKind !== 'hat') return null;
  return {
    id: obj.id,
    parentHatId: obj.parentId,
    displayName: obj.payload.displayName,
    timezone: obj.payload.timezone,
    weekendsEnabled: obj.payload.weekendsEnabled,
    ownerCertId: obj.payload.ownerCertId,
    certBacking: obj.payload.certBacking ?? null,
    createdAt: obj.createdAt,
    updatedAt: obj.updatedAt,
  };
}

export async function listHats(db: Database): Promise<HatRecord[]> {
  const rows = await db
    .select()
    .from(semObjects)
    .where(eq(semObjects.objectKind, 'hat'));
  return rows.map((r) => {
    const payload = (r.payload ?? {}) as HatPayload;
    return {
      id: r.id,
      parentHatId: r.parentId,
      displayName: payload.displayName ?? r.id,
      timezone: payload.timezone ?? 'UTC',
      weekendsEnabled: payload.weekendsEnabled ?? false,
      ownerCertId: payload.ownerCertId ?? '',
      certBacking: payload.certBacking ?? null,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    };
  });
}

// Silence unused-import noise
void and;

```
