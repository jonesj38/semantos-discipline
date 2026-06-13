---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/test-doubles.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.795527+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/test-doubles.ts

```ts
/**
 * In-memory port doubles for tests. Each helper returns a recordable
 * stub plus the bag of state it accumulates so assertions can inspect
 * what callers passed.
 *
 * Use `bindAllTestDoubles()` to wire every port at once at the start
 * of a test; `unbindAll()` resets between cases.
 */

import {
  broadcasterPort,
  channelIdGeneratorPort,
  createWalletPort,
  loggerPort,
  signerPort,
  spvPort,
  utxoProviderPort,
  walletPort,
  type Broadcaster,
  type BroadcastResult,
  type ChannelIdGenerator,
  type Dispose,
  type Logger,
  type Signature,
  type Signer,
  type SpvVerifier,
  type Utxo,
  type UtxoProvider,
  type UtxoWatchCallback,
  type WalletPortClient,
  type WalletRole,
} from './index';

// ── Recordable broadcaster ────────────────────────────────────

export interface RecordedBroadcast {
  rawTx: string | number[];
}

export interface FakeBroadcaster extends Broadcaster {
  recorded: RecordedBroadcast[];
}

export function makeFakeBroadcaster(
  result: Partial<BroadcastResult> = {},
): FakeBroadcaster {
  const recorded: RecordedBroadcast[] = [];
  return {
    recorded,
    broadcast: async (rawTx) => {
      recorded.push({ rawTx });
      return {
        txid: result.txid ?? `fake-tx-${recorded.length}`,
        ok: result.ok ?? true,
        ...(result.status !== undefined ? { status: result.status } : {}),
        ...(result.error !== undefined ? { error: result.error } : {}),
      };
    },
  };
}

// ── In-memory UTXO provider ───────────────────────────────────

export interface FakeUtxoProvider extends UtxoProvider {
  /** Per-address UTXO map; tests mutate this then call notify. */
  utxos: Map<string, Utxo[]>;
  notify(address: string): void;
  watchers: Map<string, Set<UtxoWatchCallback>>;
}

export function makeFakeUtxoProvider(): FakeUtxoProvider {
  const utxos = new Map<string, Utxo[]>();
  const watchers = new Map<string, Set<UtxoWatchCallback>>();
  return {
    utxos,
    watchers,
    listUtxos: async (address) => utxos.get(address) ?? [],
    watch: (address, cb): Dispose => {
      let bucket = watchers.get(address);
      if (!bucket) {
        bucket = new Set();
        watchers.set(address, bucket);
      }
      bucket.add(cb);
      // Initial fire — mirrors real-world watcher contracts.
      cb(utxos.get(address) ?? []);
      return () => {
        bucket?.delete(cb);
      };
    },
    notify(address) {
      const list = utxos.get(address) ?? [];
      for (const cb of watchers.get(address) ?? []) cb(list);
    },
  };
}

// ── Recordable signer ─────────────────────────────────────────

export interface RecordedSign {
  message: Uint8Array;
  keyId: string;
}

export interface FakeSigner extends Signer {
  recorded: RecordedSign[];
  pubKeys: Map<string, string>;
}

export function makeFakeSigner(): FakeSigner {
  const recorded: RecordedSign[] = [];
  const pubKeys = new Map<string, string>();
  return {
    recorded,
    pubKeys,
    sign: async (message, keyId): Promise<Signature> => {
      recorded.push({ message, keyId });
      return { hex: `fake-sig:${keyId}:${message.length}`, sighashFlag: 0x41 };
    },
    derivePublicKey: async (keyId) => {
      let pk = pubKeys.get(keyId);
      if (!pk) {
        pk = '02' + keyId.padStart(64, '0').slice(0, 64);
        pubKeys.set(keyId, pk);
      }
      return pk;
    },
  };
}

// ── Always-pass SPV verifier ──────────────────────────────────

export interface FakeSpvVerifier extends SpvVerifier {
  beefCalls: Array<{ beef: string | number[]; txid: string }>;
  bumpCalls: Array<{ bump: string; txid: string }>;
  /** Set to false to make every verify call fail. */
  passes: boolean;
}

export function makeFakeSpvVerifier(passes = true): FakeSpvVerifier {
  const beefCalls: FakeSpvVerifier['beefCalls'] = [];
  const bumpCalls: FakeSpvVerifier['bumpCalls'] = [];
  return {
    passes,
    beefCalls,
    bumpCalls,
    verifyBeef: async (beef, txid) => {
      beefCalls.push({ beef, txid });
      return passes;
    },
    verifyBump: async (bump, txid) => {
      bumpCalls.push({ bump, txid });
      return passes;
    },
  };
}

// ── Recording logger ──────────────────────────────────────────

export interface RecordedLog {
  level: 'debug' | 'info' | 'warn' | 'error';
  message: string;
  rest: unknown[];
}

export interface FakeLogger extends Logger {
  records: RecordedLog[];
}

export function makeFakeLogger(): FakeLogger {
  const records: RecordedLog[] = [];
  const make = (level: RecordedLog['level']) =>
    (message: string, ...rest: unknown[]) => records.push({ level, message, rest });
  return {
    records,
    debug: make('debug'),
    info: make('info'),
    warn: make('warn'),
    error: make('error'),
  };
}

// ── Recordable wallet ─────────────────────────────────────────

export interface FakeWalletClient extends WalletPortClient {
  isAuthCalls: number;
  createActionCalls: Array<unknown>;
}

export function makeFakeWallet(): FakeWalletClient {
  const w: FakeWalletClient = {
    isAuthCalls: 0,
    createActionCalls: [],
    isAuthenticated: async () => {
      w.isAuthCalls++;
      return true;
    },
    createAction: async (req) => {
      w.createActionCalls.push(req);
      return { txid: 'fake-tx', tx: 'beef' };
    },
    getPublicKey: async () => '02' + 'ab'.repeat(32),
    listOutputs: async () => [],
    signAction: async () => ({ txid: 'fake-tx' }),
    internalizeAction: async () => ({ accepted: true }),
  };
  return w;
}

// ── Channel-id generator stub ─────────────────────────────────

export function makeFakeChannelIdGenerator(prefix = 'chan'): ChannelIdGenerator {
  let n = 0;
  return { next: () => `${prefix}-${++n}` };
}

// ── Bundled bind/unbind helpers ───────────────────────────────

export interface BoundDoubles {
  broadcaster: FakeBroadcaster;
  utxos: FakeUtxoProvider;
  signer: FakeSigner;
  spv: FakeSpvVerifier;
  logger: FakeLogger;
  walletProvider: FakeWalletClient;
  walletConsumer: FakeWalletClient;
  channelIdGenerator: ChannelIdGenerator;
}

/** Bind every payment-channel port to a fresh in-memory double. */
export function bindAllTestDoubles(): BoundDoubles {
  const out: BoundDoubles = {
    broadcaster: makeFakeBroadcaster(),
    utxos: makeFakeUtxoProvider(),
    signer: makeFakeSigner(),
    spv: makeFakeSpvVerifier(),
    logger: makeFakeLogger(),
    walletProvider: makeFakeWallet(),
    walletConsumer: makeFakeWallet(),
    channelIdGenerator: makeFakeChannelIdGenerator(),
  };
  broadcasterPort.bind(out.broadcaster);
  utxoProviderPort.bind(out.utxos);
  signerPort.bind(out.signer);
  spvPort.bind(out.spv);
  loggerPort.bind(out.logger);
  walletPort.bind(out.walletProvider);
  createWalletPort('provider' as WalletRole).bind(out.walletProvider);
  createWalletPort('consumer' as WalletRole).bind(out.walletConsumer);
  channelIdGeneratorPort.bind(out.channelIdGenerator);
  return out;
}

/** Unbind every port. Run from `afterEach()`. */
export function unbindAllTestDoubles(): void {
  broadcasterPort.unbind();
  utxoProviderPort.unbind();
  signerPort.unbind();
  spvPort.unbind();
  loggerPort.unbind();
  walletPort.unbind();
  createWalletPort('provider' as WalletRole).unbind();
  createWalletPort('consumer' as WalletRole).unbind();
  channelIdGeneratorPort.unbind();
}

```
