---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/role-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.021537+00:00
---

# core/hrr/src/role-vectors.ts

```ts
/**
 * Deterministic role and filler vector generation for Plate (1995) HRR.
 *
 * Role vectors are seeded by `(domain_flag, role_name)` via SHA-256.
 * Filler vectors are seeded by `(domain_flag, filler_value)` via SHA-256.
 * Both are unit vectors in R^D (L2-normalised).
 *
 * The domain flag is baked into the seed so role vectors for distinct
 * domains are mutually orthogonal by construction — cross-domain cosines
 * are ≈ 0 regardless of structural overlap (WI-A4 empirically confirmed
 * |cos| < 0.1 for all trades↔SCADA pairs).
 *
 * See research/experiments/hrr-encoding-feasibility.ts for the measurement
 * methodology and research/experiments/hrr-encoding-feasibility.results.md
 * for the empirical numbers that validated this seeding scheme.
 */

import { createHash } from 'crypto';

/** Dimensionality. Must be a power of 2. */
export const D = 1024;

/**
 * Produce a deterministic L2-unit vector in R^D from `seed`.
 * Uses ceil(D/8) SHA-256 calls, each contributing 8 int32-normalised floats.
 */
export function seedVec(seed: string): Float64Array {
  const v = new Float64Array(D);
  const blocks = D / 8; // 128 for D=1024
  for (let block = 0; block < blocks; block++) {
    const h = createHash('sha256').update(`${seed}:${block}`).digest();
    for (let j = 0; j < 8; j++) {
      v[block * 8 + j] = h.readInt32BE(j * 4) / 0x80000000;
    }
  }
  return l2normalize(v);
}

/** Role vector for `(domainFlag, roleName)`. Memoised. */
const roleCache = new Map<string, Float64Array>();
export function roleVec(domainFlag: number, roleName: string): Float64Array {
  const key = `${domainFlag}:role:${roleName}`;
  let v = roleCache.get(key);
  if (!v) { v = seedVec(key); roleCache.set(key, v); }
  return v;
}

/** Filler vector for `(domainFlag, fillerValue)`. Memoised. */
const fillerCache = new Map<string, Float64Array>();
export function fillerVec(domainFlag: number, fillerValue: string): Float64Array {
  const key = `${domainFlag}:filler:${fillerValue}`;
  let v = fillerCache.get(key);
  if (!v) { v = seedVec(key); fillerCache.set(key, v); }
  return v;
}

// ── Vector math ───────────────────────────────────────────────────────────────

export function dot(a: Float64Array, b: Float64Array): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * b[i];
  return s;
}

export function l2norm(a: Float64Array): number {
  return Math.sqrt(dot(a, a));
}

export function l2normalize(a: Float64Array): Float64Array {
  const n = l2norm(a);
  if (n < 1e-15) return new Float64Array(a.length);
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = a[i] / n;
  return out;
}

// ── In-place radix-2 DIT FFT ─────────────────────────────────────────────────

/** In-place complex FFT. `re.length` must be a power of 2. */
export function fft(re: Float64Array, im: Float64Array): void {
  const n = re.length;
  // bit-reversal permutation
  let j = 0;
  for (let i = 1; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      let tmp = re[i]; re[i] = re[j]; re[j] = tmp;
      tmp = im[i]; im[i] = im[j]; im[j] = tmp;
    }
  }
  // butterfly stages
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    const wRe = Math.cos(ang);
    const wIm = Math.sin(ang);
    const half = len >> 1;
    for (let i = 0; i < n; i += len) {
      let curRe = 1, curIm = 0;
      for (let k = 0; k < half; k++) {
        const uRe = re[i + k], uIm = im[i + k];
        const vRe = re[i + k + half] * curRe - im[i + k + half] * curIm;
        const vIm = re[i + k + half] * curIm + im[i + k + half] * curRe;
        re[i + k] = uRe + vRe;   im[i + k] = uIm + vIm;
        re[i + k + half] = uRe - vRe; im[i + k + half] = uIm - vIm;
        const nRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = nRe;
      }
    }
  }
}

/** In-place IFFT via conjugate trick. */
export function ifft(re: Float64Array, im: Float64Array): void {
  for (let i = 0; i < im.length; i++) im[i] = -im[i];
  fft(re, im);
  const n = re.length;
  for (let i = 0; i < n; i++) { re[i] /= n; im[i] = (-im[i]) / n; }
}

// ── Circular convolution ──────────────────────────────────────────────────────

/** Circular convolution of two real D-vectors via FFT. Returns a new array. */
export function circConv(a: Float64Array, b: Float64Array): Float64Array {
  const n = a.length;
  const aRe = new Float64Array(a), aIm = new Float64Array(n);
  const bRe = new Float64Array(b), bIm = new Float64Array(n);
  fft(aRe, aIm);
  fft(bRe, bIm);
  for (let k = 0; k < n; k++) {
    const ar = aRe[k], ai = aIm[k], br = bRe[k], bi = bIm[k];
    aRe[k] = ar * br - ai * bi;
    aIm[k] = ar * bi + ai * br;
  }
  ifft(aRe, aIm);
  return aRe;
}

/**
 * Approximate inverse of circConv: `unbind(circConv(r, f), r) ≈ f`.
 * Uses the conjugate of r in the frequency domain (exact inverse for unit r).
 */
export function circCorr(a: Float64Array, b: Float64Array): Float64Array {
  const n = a.length;
  const aRe = new Float64Array(a), aIm = new Float64Array(n);
  const bRe = new Float64Array(b), bIm = new Float64Array(n);
  fft(aRe, aIm);
  fft(bRe, bIm);
  // correlation = conj(A) * B in frequency domain
  for (let k = 0; k < n; k++) {
    const ar = aRe[k], ai = aIm[k], br = bRe[k], bi = bIm[k];
    aRe[k] = ar * br + ai * bi;  // conj(a)*b real
    aIm[k] = ar * bi - ai * br;  // conj(a)*b imag
  }
  ifft(aRe, aIm);
  return aRe;
}

```
