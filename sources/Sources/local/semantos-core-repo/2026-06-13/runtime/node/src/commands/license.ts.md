---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/license.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.307703+00:00
---

# runtime/node/src/commands/license.ts

```ts
/**
 * `semantos license` — mint + show subcommands for License cells.
 *
 * Usage:
 *   semantos license mint --holder-pubkey <hex> [--services s1,s2]
 *                          [--expiry <unix-seconds>] [--out <path>]
 *
 *   semantos license show <path>
 *
 * Mint uses the well-known dev issuer keypair (gated by `SEMANTOS_DEV_MODE=1`
 * at boot time). Production licenses are minted by Plexus, not this command.
 */

import { writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { PrivateKey } from "@bsv/sdk";
import {
  encodeLicense,
  canonicalLicenseBodyForSigning,
  licenseCertId,
  type License,
} from "@semantos/protocol-types/license";
import { BsvSdkSigner } from "@semantos/session-protocol";
import {
  deriveDevIssuer,
  isDevIssuedLicense,
  loadLicenseFromDisk,
} from "../license-policy";

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export async function licenseCommand(args: string[]): Promise<void> {
  const sub = args[0];

  if (!sub || sub === "--help" || sub === "-h") {
    printUsage();
    return;
  }

  switch (sub) {
    case "mint":
      await mintCommand(args.slice(1));
      return;
    case "show":
      await showCommand(args.slice(1));
      return;
    default:
      console.error(`Unknown license subcommand: ${sub}`);
      printUsage();
      process.exit(1);
  }
}

function printUsage(): void {
  console.log(
    [
      "",
      "Usage: semantos license <subcommand> [options]",
      "",
      "Subcommands:",
      "  mint   Mint a dev-issued License cell",
      "  show   Inspect a License cell on disk",
      "",
      "Examples:",
      "  semantos license mint --holder-pubkey 02aa... --out node.license",
      "  semantos license show node.license",
      "",
    ].join("\n"),
  );
}

// ---------------------------------------------------------------------------
// mint
// ---------------------------------------------------------------------------

interface MintArgs {
  holderPubkey?: Uint8Array;
  services: string[];
  expiry?: number;
  outPath?: string;
  outPrivKeyPath?: string;
  generate: boolean;
}

function parseMintArgs(args: string[]): MintArgs {
  const out: MintArgs = { services: ["session"], generate: false };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const next = args[i + 1];
    switch (a) {
      case "--holder-pubkey":
        if (!next) throw new Error("--holder-pubkey requires a hex value");
        out.holderPubkey = hexToBytes(next);
        if (out.holderPubkey.length !== 33) {
          throw new Error(
            `--holder-pubkey must be 33 bytes (66 hex chars); got ${out.holderPubkey.length}`,
          );
        }
        i += 1;
        break;
      case "--generate":
        out.generate = true;
        break;
      case "--services":
        if (!next) throw new Error("--services requires a comma-separated list");
        out.services = next.split(",").map((s) => s.trim()).filter(Boolean);
        i += 1;
        break;
      case "--expiry":
        if (!next) throw new Error("--expiry requires a unix-seconds value");
        out.expiry = Number(next);
        if (!Number.isFinite(out.expiry)) {
          throw new Error(`--expiry must be a number; got "${next}"`);
        }
        i += 1;
        break;
      case "--out":
        if (!next) throw new Error("--out requires a path");
        out.outPath = next;
        i += 1;
        break;
      case "--out-privkey":
        if (!next) throw new Error("--out-privkey requires a path");
        out.outPrivKeyPath = next;
        i += 1;
        break;
      default:
        throw new Error(`Unknown option: ${a}`);
    }
  }
  return out;
}

async function mintCommand(args: string[]): Promise<void> {
  const parsed = parseMintArgs(args);

  // --generate mints a fresh holder keypair; writes the privkey to
  // --out-privkey (required in generate mode) + derives the pubkey for us.
  let holderPubkey = parsed.holderPubkey;
  let generatedPrivKeyHex: string | undefined;
  if (parsed.generate) {
    if (parsed.holderPubkey) {
      throw new Error(
        "mint: --generate and --holder-pubkey are mutually exclusive",
      );
    }
    if (!parsed.outPrivKeyPath) {
      throw new Error("mint: --generate requires --out-privkey <path>");
    }
    generatedPrivKeyHex = randomBytes(32).toString("hex");
    const pk = PrivateKey.fromHex(generatedPrivKeyHex);
    holderPubkey = Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
  }

  if (!holderPubkey) {
    throw new Error(
      "mint: either --holder-pubkey <hex> or --generate is required",
    );
  }

  const dev = deriveDevIssuer();

  const license: License = {
    pubkey: holderPubkey,
    issuer: dev.pubkey,
    services: parsed.services,
    expiry: parsed.expiry,
    issuerSig: new Uint8Array(0),
  };

  const body = canonicalLicenseBodyForSigning(license);
  const issuerSigner = new BsvSdkSigner(dev.privKey, async () => "dev-issuer");
  const issuerSig = await issuerSigner.sign(body);
  const signed: License = { ...license, issuerSig };
  const bytes = encodeLicense(signed);

  if (parsed.outPath) {
    await writeFile(parsed.outPath, bytes);
    console.log(`Wrote ${bytes.length} bytes to ${parsed.outPath}`);
    console.log(`  certId:  ${licenseCertId(signed)}`);
    console.log(`  holder:  ${bytesToHex(holderPubkey)}`);
    console.log(`  issuer:  dev-issuer (${bytesToHex(dev.pubkey)})`);
    console.log(`  services: ${parsed.services.join(", ") || "(none)"}`);
    console.log(
      `  expiry:  ${parsed.expiry ? new Date(parsed.expiry * 1000).toISOString() : "never"}`,
    );

    if (generatedPrivKeyHex && parsed.outPrivKeyPath) {
      // Write 0600-permission-style by convention (fs/promises doesn't
      // set mode cross-platform). Operators should chmod 600 themselves.
      await writeFile(parsed.outPrivKeyPath, generatedPrivKeyHex + "\n");
      console.log(`Wrote private key to ${parsed.outPrivKeyPath}`);
      console.log(`  IMPORTANT: chmod 600 this file before booting a node`);
    } else if (parsed.outPrivKeyPath && !generatedPrivKeyHex) {
      throw new Error(
        "mint: --out-privkey only makes sense with --generate; the holder " +
          "already has their own private key",
      );
    }
    return;
  }

  // No --out: write base64 to stdout so it's pipeable.
  process.stdout.write(Buffer.from(bytes).toString("base64") + "\n");
}

// ---------------------------------------------------------------------------
// show
// ---------------------------------------------------------------------------

async function showCommand(args: string[]): Promise<void> {
  const path = args[0];
  if (!path || path.startsWith("-")) {
    throw new Error("show: path to license file required");
  }

  const { license, bytes } = await loadLicenseFromDisk(path);
  const certId = licenseCertId(license);
  const devIssued = isDevIssuedLicense(license);
  const expiry = license.expiry
    ? new Date(license.expiry * 1000).toISOString()
    : "never";

  console.log(`License: ${path}`);
  console.log(`  certId:   ${certId}`);
  console.log(`  size:     ${bytes.length} bytes`);
  console.log(`  holder:   ${bytesToHex(license.pubkey)}`);
  console.log(
    `  issuer:   ${bytesToHex(license.issuer)}${devIssued ? "  (dev-issuer)" : ""}`,
  );
  console.log(`  services: ${license.services.join(", ") || "(none)"}`);
  console.log(`  expiry:   ${expiry}`);
  if (license.meta && Object.keys(license.meta).length > 0) {
    console.log(`  meta:     ${JSON.stringify(license.meta)}`);
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]*$/.test(clean) || clean.length % 2 !== 0) {
    throw new Error(`invalid hex: "${hex}"`);
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    out[i / 2] = parseInt(clean.slice(i, i + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

```
