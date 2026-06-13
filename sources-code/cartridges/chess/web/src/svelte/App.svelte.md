---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/svelte/App.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.429377+00:00
---

# cartridges/chess/web/src/svelte/App.svelte

```svelte
<script lang="ts">
  import Board from './components/Board.svelte';
  import CubePanel from './components/CubePanel.svelte';
  import { BrainRpc, defaultBrainWssUrl } from '../core/brain-rpc.js';
  import type { VerbResult } from '../core/brain-rpc.js';
  import { RelayClient, roomFromLocation, defaultRelayUrl } from '../core/relay.js';
  import { readDeepLink, clearDeepLinkHash } from '../core/deep-link.js';
  import { WalletBridge, defaultWalletOrigin } from '../core/wallet-bridge.js';
  import { detectWallet, type WalletAdapter, type WalletKind } from '../core/wallet-adapter.js';
  import { fundChessStake } from '../core/wallet-stake.js';
  import type { Color, GameRecord, WalkerResponse } from '../chess/types.js';
  import { isGameRecord, isTerminal, endReasonLabel } from '../chess/types.js';

  // ─── Settings (URL + localStorage) ────────────────────────────────────
  const ROOM = roomFromLocation();
  // currentRoom tracks the active relay room; it starts as ROOM but switches
  // to the game-specific room when a game record first arrives (fixes the
  // case where the creator is at doublemate.app with no invite param and
  // connects to 'lobby', then creates a game — without this switch they stay
  // in 'lobby' while the joiner is in 'chess-<id>', so sendLive never crosses).
  let currentRoom = ROOM;
  function loadFromLocal(key: string, fallback: string): string {
    if (typeof localStorage === 'undefined') return fallback;
    return localStorage.getItem(key) ?? fallback;
  }
  function saveToLocal(key: string, value: string): void {
    if (typeof localStorage === 'undefined') return;
    if (value) localStorage.setItem(key, value);
    else localStorage.removeItem(key);
  }
  const HANDLE_KEY = 'chess.handle';
  const BEARER_KEY = 'chess.bearer';
  const BRAIN_URL_KEY = 'chess.brainUrl';

  let handle = $state(loadFromLocal(HANDLE_KEY, ''));
  if (!handle) {
    handle = 'p-' + Math.random().toString(36).slice(2, 8);
    saveToLocal(HANDLE_KEY, handle);
  }

  // ─── BRC-100 wallet detection ────────────────────────────────────────
  //
  // On load we probe for a connected wallet in priority order:
  //   1. wasm iframe at wallet.semantos.me (when enabled)
  //   2. Metanet Desktop on http://localhost:3321
  //
  // Whichever responds first becomes the active identity provider —
  // its pubkey replaces the random `p-xxxxxx` handle so the two-player
  // join flow naturally yields distinct identities without a server-
  // side identity registry. Bearer auth to the brain stays separate
  // (operator-issued; T7 brain-auth alignment collapses these later).
  let walletAdapterName = $state<string>('');
  let walletAdapterKind = $state<WalletKind | ''>('');
  let walletIdentityKey = $state<string>('');
  let walletDetecting = $state(false);
  let walletAdapter: WalletAdapter | null = null;

  async function detectAndConnectWallet(): Promise<void> {
    if (walletDetecting) return; // one probe at a time
    walletDetecting = true;
    walletAdapter = null;
    walletAdapterName = '';
    walletAdapterKind = '';
    walletIdentityKey = '';
    try {
      const adapter = await detectWallet({
        tryWasmIframe: walletEnabled,
        wasmOrigin: walletOriginPref,
      });
      if (!adapter) {
        walletAdapterName = '';
        walletAdapterKind = '';
        walletIdentityKey = '';
        return;
      }
      walletAdapter = adapter;
      walletAdapterName = adapter.name;
      walletAdapterKind = adapter.kind;
      const pk = await adapter.getIdentityKey();
      walletIdentityKey = pk;
      // Use the wallet pubkey as the canonical handle — its first 12
      // chars are stable + plenty of entropy to disambiguate two
      // players against one brain. Persisted so refreshes don't
      // reroll. The user can still edit it manually.
      const newHandle = pk.slice(0, 12);
      if (handle !== newHandle) {
        handle = newHandle;
        saveToLocal(HANDLE_KEY, handle);
      }
    } catch (e) {
      pushLog(`✗ wallet detect: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      walletDetecting = false;
    }
  }
  // Bearer + brain URL are mutable from the lobby form — first-run users
  // paste their token here instead of opening DevTools.
  let bearer = $state(loadFromLocal(BEARER_KEY, ''));
  let brainUrl = $state(loadFromLocal(BRAIN_URL_KEY, '') || defaultBrainWssUrl());

  // Wallet → SPA handoff. wallet.html builds a URL like
  //   https://doublemate.app/?invite=<gameId>#bearer=<hex>&brain=<wss>
  // when the operator finishes funding a chess stake. We pull those
  // values in here BEFORE the lobby renders so the fields arrive
  // pre-filled, then strip the hash so the bearer doesn't survive in
  // history or copy-link.
  const __dl = readDeepLink();
  if (__dl.bearer) {
    bearer = __dl.bearer;
    saveToLocal(BEARER_KEY, bearer);
  }
  if (__dl.brainUrl) {
    brainUrl = __dl.brainUrl;
    saveToLocal(BRAIN_URL_KEY, brainUrl);
  }
  clearDeepLinkHash();

  // ─── Game state ───────────────────────────────────────────────────────
  let game = $state<GameRecord | null>(null);
  let relayStatus = $state<'connecting'|'open'|'closed'|'error'>('connecting');
  let presence = $state<string[]>([]);
  let myColor = $state<Color | null>(null);
  let status = $state<string>('');
  let log = $state<string[]>([]);

  // Form fields for the "create / join" lobby.
  let formGameId = $state(ROOM === 'lobby' ? `chess-${Math.random().toString(36).slice(2, 10)}` : ROOM);
  // Stake: when a BRC-100 wallet is connected, setting stake > 0 triggers a
  // real createAction call (Metanet Desktop permission dialog) before the
  // brain verb fires. Without a wallet, stake is recorded as notional only.
  let formStake = $state(0);
  let formClockMs = $state(600_000);
  let formColor = $state<Color>('white');

  // ─── Stake funding state ──────────────────────────────────────────────
  type StakePhase = 'idle' | 'pending' | 'funded' | 'error';
  let stakePhase = $state<StakePhase>('idle');
  let stakeError = $state<string>('');
  let stakeTxidHex = $state<string>('');

  // Rebuilt whenever bearer / brainUrl change so dispatches use the
  // latest token without a page reload. Cheap — BrainRpc is a thin
  // per-request socket wrapper.
  let rpc = $derived(new BrainRpc(brainUrl, bearer));

  // ─── Wallet bridge (opt-in transport) ────────────────────────────────
  //
  // When enabled, dispatches go through an embedded
  // wallet.semantos.me iframe instead of opening the brain WSS
  // directly. The wallet runs the WSS connection; the SPA never holds
  // a long-lived link. Gated behind localStorage.chess.walletEnabled
  // because the wallet has no public deployment yet — flipping the
  // flag without one means the iframe load fails. Once
  // wallet.semantos.me is live, we'll flip the default on.
  const WALLET_ENABLED_KEY = 'chess.walletEnabled';
  const WALLET_ORIGIN_KEY = 'chess.walletOrigin';
  let walletEnabled = $state(loadFromLocal(WALLET_ENABLED_KEY, '') === '1');
  let walletOriginPref = $state(loadFromLocal(WALLET_ORIGIN_KEY, '') || defaultWalletOrigin());
  let walletStatus = $state<'idle'|'connecting'|'open'|'error'>('idle');
  let walletBridge: WalletBridge | null = null;

  function ensureWalletBridge(): WalletBridge | null {
    if (!walletEnabled) return null;
    if (walletBridge) return walletBridge;
    walletBridge = new WalletBridge(walletOriginPref);
    walletBridge.onStatus((s) => { walletStatus = s; });
    walletBridge.connect().catch((e) => {
      status = `wallet bridge: ${e instanceof Error ? e.message : String(e)}`;
      pushLog(`✗ wallet bridge: ${status}`);
    });
    return walletBridge;
  }
  // Kick off connection eagerly on load when the flag is on, so the
  // iframe handshake is done by the time the user clicks Create/Join.
  if (walletEnabled) ensureWalletBridge();

  // Kick off BRC-100 wallet identity detection (Metanet Desktop on 3321,
  // or the wasm iframe when enabled). Fire-and-forget — the lobby UI
  // updates reactively when the adapter resolves.
  detectAndConnectWallet();

  /**
   * Route a chess verb dispatch through the configured transport.
   * Wallet mode: wallet.call('chess.dispatch', {verb, params, brainUrl, bearer})
   *              — the wallet runs the WSS; SPA awaits the result.
   * Direct mode: SPA opens its own WSS via BrainRpc.
   */
  async function dispatchChessVerb(verb: string, vparams: Record<string, unknown>): Promise<VerbResult> {
    if (walletEnabled) {
      const wb = ensureWalletBridge();
      if (!wb) return { error: { code: -32603, message: 'wallet bridge unavailable' } };
      try {
        const out = await wb.call('chess.dispatch', {
          verb,
          params: vparams,
          brainUrl,
          bearer,
        });
        // The wallet's chess.dispatch wraps the brain result in
        // `{brainResult}`; unwrap for the SPA's existing callers.
        const r = (out as { brainResult?: unknown })?.brainResult;
        return { result: r };
      } catch (e) {
        return { error: { code: -32603, message: e instanceof Error ? e.message : String(e) } };
      }
    }
    return rpc.dispatch(verb, vparams);
  }

  // ─── Cell-relay — presence + invite signalling only ───────────────────
  //
  // The cell-relay carries presence + light invite acks; authoritative
  // game state lives on the brain and is fetched after every move. The
  // relay never holds money or move legality.
  //
  // `relay` is a plain `let` so joinGameSafe() can swap it out when a
  // handle-collision fork changes our identity mid-session.  If we stayed
  // connected as the old handle the relay room would see both tabs as the
  // same peer, deduplicate them, and sendLive would never reach the joiner.
  const relayCallbacks = {
    onStatus(s: string) { relayStatus = s; },
    onSnapshot(_cells: unknown, _your: unknown, p: string[]) { presence = p; pushLog(`relay snapshot, peers=${p.length}`); },
    onCell(_cell: unknown, from: { identity: string }) { pushLog(`relay cell from ${from.identity}`); refreshGame(); },
    onPresence(ids: string[], change: { joined?: string; left?: string }) {
      presence = ids;
      if (change.joined) pushLog(`joined: ${change.joined}`);
      if (change.left)   pushLog(`left: ${change.left}`);
      // Auto-refresh — the other side may have just made a move.
      if (game) refreshGame();
    },
    onLive(payload: { track?: string } | null, from: { identity: string } | null) {
      // Chess uses transient `live` broadcasts (track: 'chess.tick') as a
      // wake-up signal: when the other player completes a verb on the
      // brain, they sendLive — peers then re-fetch authoritative state.
      // Filter to our own track so unrelated room traffic (e.g. a jam
      // session sharing this relay node) doesn't churn get_game.
      if (payload?.track !== 'chess.tick') return;
      // Ignore our own echo: the relay broadcasts back to the sender,
      // and we already setGame()'d on the dispatch result.
      if (from?.identity === handle) return;
      pushLog(`peer move tick from ${from?.identity ?? '?'}`);
      if (game) refreshGame();
    },
    onReset() { pushLog('relay reset'); },
  };

  function makeRelay(h: string): RelayClient {
    return new RelayClient(defaultRelayUrl(currentRoom, h), relayCallbacks);
  }

  let relay = makeRelay(handle);
  relay.connect();

  function pushLog(line: string): void {
    log = [...log.slice(-99), `${new Date().toISOString().slice(11,19)} ${line}`];
  }

  async function refreshGame(): Promise<void> {
    if (!game || !bearer) return;
    try {
      const res = await dispatchChessVerb('get_game', { gameId: game.gameId });
      if (res.error) {
        pushLog(`✗ get_game → ${res.error.message}`);
        return;
      }
      setGame(res.result as WalkerResponse);
    } catch (e) {
      pushLog(`✗ refresh threw: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  function setGame(r: WalkerResponse): void {
    if (isGameRecord(r)) {
      // Switch relay room when the game ID is first known.  The creator
      // starts in 'lobby' (no invite param in URL); without this switch
      // they stay in 'lobby' while the joiner is in 'chess-<id>', so
      // sendLive never crosses between players.
      if (r.gameId && r.gameId !== currentRoom) {
        currentRoom = r.gameId;
        const stale = relay;
        (stale as unknown as { connect: () => void }).connect = () => {}; // neuter auto-reconnect
        stale.disconnect();
        relay = makeRelay(handle);
        relay.connect();
        pushLog(`relay switched to room ${r.gameId}`);
      }

      const prevStatus = game?.status;
      const prevFen = game?.fen;
      const prevCubeOwner = game?.cubeOwner;
      const prevMultiplier = game?.multiplier;
      const wasNoGame = game === null;
      game = r;

      // Ask for browser notification permission the first time a game is
      // created (so the "opponent joined" alert can fire even if the tab
      // is in the background).
      if (wasNoGame && r.status === 'waiting' && typeof Notification !== 'undefined' && Notification.permission === 'default') {
        Notification.requestPermission().catch(() => {/* silently ignore */});
      }

      // Infer my colour the first time we see ourselves in the record.
      if (!myColor) {
        if (r.white === handle) myColor = 'white';
        else if (r.black === handle) myColor = 'black';
      }

      // ── Transition notifications ──────────────────────────────────────
      if (prevStatus === 'waiting' && r.status === 'active') {
        // Opponent just joined.
        const opponent = myColor === 'white' ? r.black : r.white;
        const first = r.white === handle ? 'Your move first (white).' : 'Opponent moves first (white).';
        status = `⚔ ${opponent ?? 'Opponent'} has joined — ${first}`;
        pushLog(`opponent joined: ${opponent ?? '?'}`);
        // Try browser notification (granted on first click → silently fails otherwise)
        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          new Notification('Chess — opponent joined', {
            body: `${opponent ?? 'Your opponent'} joined game ${r.gameId}. ${first}`,
            icon: '/favicon.ico',
          });
        }
      } else if (prevStatus === 'active' && isTerminal(r)) {
        // Game just ended.
        const wonLost = r.winner === myColor ? 'You won!' : r.winner ? `${r.winner} wins.` : 'Draw.';
        status = `🏁 ${wonLost} Final pot: ${r.stakeSats * r.multiplier} sats`;
      } else if (
        r.status === 'active' &&
        prevCubeOwner !== r.cubeOwner &&
        r.cubeOwner !== null &&
        r.cubeOwner !== myColor
      ) {
        // Opponent just took ownership of the cube (offer pending to us).
        const newPot = r.stakeSats * r.multiplier * 2;
        status = `🎲 Opponent offers the doubling cube — accept ×${r.multiplier * 2} (${newPot} sats) or decline?`;
      } else if (
        prevMultiplier !== undefined &&
        r.multiplier > prevMultiplier &&
        r.status === 'active'
      ) {
        // Cube was accepted — pot grew.
        status = `✓ Cube accepted — pot is now ${r.stakeSats * r.multiplier} sats (×${r.multiplier})`;
      } else {
        status = '';
      }

      // FEN changed (or this is the first record) — fetch the legal-move
      // set so the Board can highlight destinations. Fire-and-forget;
      // the highlight is a UI nicety, not load-bearing.
      if (r.fen !== prevFen) refreshLegalMoves();
    } else {
      status = `rejected: ${r.reason}`;
      pushLog(`✗ ${r.reason}`);
    }
  }

  let legalMoves = $state<string[]>([]);

  async function refreshLegalMoves(): Promise<void> {
    if (!game || !bearer) return;
    try {
      const res = await dispatchChessVerb('list_legal_moves', { gameId: game.gameId });
      if (res.error) return;
      const r = res.result as { ok?: boolean; moves?: string[] };
      legalMoves = r.ok && Array.isArray(r.moves) ? r.moves : [];
    } catch {
      legalMoves = [];
    }
  }

  async function dispatch(verb: string, params: Record<string, unknown>): Promise<void> {
    if (!bearer) {
      status = 'Paste your operator bearer token in the lobby first.';
      return;
    }
    try {
      const res = await dispatchChessVerb(verb, params);
      if (res.error) {
        status = `rpc error ${res.error.code}: ${res.error.message}`;
        pushLog(`✗ ${verb} → ${res.error.message}`);
        return;
      }
      setGame(res.result as WalkerResponse);
      pushLog(`✓ ${verb}`);
      // Notify the room — the relay just shuttles a presence-style ping;
      // the actual state always comes from the brain on each side.
      relay.sendLive({ kind: 'trigger', track: 'chess.tick', vel: 0, semitone: 0 });
    } catch (e) {
      status = `dispatch failed: ${e instanceof Error ? e.message : String(e)}`;
      pushLog(`✗ ${verb} threw: ${status}`);
    }
  }

  // Persist mutated config values to localStorage before each verb so
  // the form acts like a "save + go" — refresh keeps your settings.
  function persistConfig(): void {
    saveToLocal(HANDLE_KEY, handle);
    saveToLocal(BEARER_KEY, bearer);
    // Only persist a brain URL if the user changed it from the bake-time
    // default; otherwise leave the slot empty so future bundle updates
    // can ship a new default without being overridden.
    if (brainUrl && brainUrl !== defaultBrainWssUrl()) saveToLocal(BRAIN_URL_KEY, brainUrl);
    else saveToLocal(BRAIN_URL_KEY, '');
  }

  // ─── Verb actions ─────────────────────────────────────────────────────

  /**
   * Fund a chess stake via the active BRC-100 wallet adapter, then dispatch
   * the brain verb.
   *
   * - Wallet connected + stake > 0  → calls createAction (Metanet dialog),
   *   then dispatches the verb. Aborts if wallet rejects.
   * - No wallet + stake > 0         → prompts user to confirm notional play
   *   or abort and start Metanet Desktop.
   * - Stake = 0                     → dispatches immediately (free play).
   */
  async function fundAndDispatch(
    verb: string,
    verbParams: Record<string, unknown>,
    stakeSats: number,
    color: 'white' | 'black' | 'join',
  ): Promise<void> {
    stakeError = '';

    if (stakeSats > 0 && !walletAdapter) {
      // Wallet not detected. It may be running but blocked by a CORS preflight.
      // The "connect wallet" button in the header retries detection.
      const proceed = window.confirm(
        `Wallet not connected (${stakeSats} sats will be notional).\n\n` +
        `If Metanet Desktop is running, click Cancel, then use the "connect" button in the header and try again.\n\n` +
        `Click OK to play with a notional stake (no real sats move).`,
      );
      if (!proceed) return;
      stakePhase = 'idle';
    } else if (walletAdapter && stakeSats > 0) {
      stakePhase = 'pending';
      status = `Waiting for wallet approval (${stakeSats} sats)…`;
      try {
        const gameId = String(verbParams.gameId || formGameId);
        const result = await fundChessStake(walletAdapter, gameId, stakeSats, color);
        stakeTxidHex = result.txidHex;
        stakePhase = 'funded';
        status = '';
        pushLog(`✓ stake funded: ${stakeSats} sats → txid ${result.txidHex.slice(0, 16)}…`);
        // Seed Phase-2 wiring — brain currently ignores unknown fields.
        verbParams = { ...verbParams, stakeOutpointTxid: result.txidHex };
      } catch (e) {
        stakePhase = 'error';
        stakeError = e instanceof Error ? e.message : String(e);
        pushLog(`✗ stake funding failed: ${stakeError}`);
        status = `Wallet rejected stake — ${stakeError}`;
        return; // Don't create the game if the wallet rejected
      }
    } else {
      stakePhase = 'idle';
    }

    dispatch(verb, verbParams);
  }

  function createGame(): void {
    persistConfig();
    myColor = formColor;
    void fundAndDispatch('create_game', {
      gameId: formGameId,
      creator: handle,
      color: formColor,
      stakeSats: formStake,
      clockMs: formClockMs,
    }, formStake, formColor);
  }

  function joinGame(): void {
    persistConfig();
    void joinGameSafe();
  }

  /**
   * Two-tab/same-Metanet-Desktop testing reuses one wallet identity, so
   * pubkey-derived handles collide between Player A and Player B. The
   * brain doesn't reject the duplicate join — it stuffs the same string
   * into both white/black slots — and downstream UI gates (myColor,
   * isMyTurn) silently flip wrong. We peek the creator first; if it
   * matches our handle, fork with a short suffix so the brain's slots
   * stay distinct. The wallet identity continuity is preserved in the
   * pubkey prefix; the suffix is per-tab.
   */
  async function joinGameSafe(): Promise<void> {
    const peek = await dispatchChessVerb('get_game', { gameId: formGameId });
    const peeked = peek.result as {
      ok?: boolean; white?: string; black?: string;
      status?: string; stakeSats?: number;
    } | undefined;
    let joinStakeSats = formStake;
    if (peeked?.ok === true) {
      if (peeked.status !== 'waiting') {
        status = `cannot join: game is ${peeked.status}`;
        return;
      }
      // Use the game's recorded stake for the join (matches the creator's amount).
      if (typeof peeked.stakeSats === 'number' && peeked.stakeSats > 0) {
        joinStakeSats = peeked.stakeSats;
      }
      if (peeked.white === handle || peeked.black === handle) {
        const suffix = '-' + Math.random().toString(36).slice(2, 6);
        const forked = handle + suffix;
        pushLog(`creator handle collision; forking to ${forked}`);
        handle = forked;
        saveToLocal(HANDLE_KEY, handle);
        // Reconnect relay as the forked identity so the relay room sees
        // two distinct peers. Without this, both tabs share the same `as=`
        // identity and sendLive is not delivered to the joiner.
        const stale = relay;
        (stale as unknown as { connect: () => void }).connect = () => {}; // neuter auto-reconnect
        stale.disconnect();
        relay = makeRelay(handle);
        relay.connect();
        pushLog(`relay reconnected as ${handle}`);
      }
    }
    await fundAndDispatch('join_game', {
      gameId: formGameId,
      joiner: handle,
    }, joinStakeSats, 'join');
  }

  function submitMove(uci: string): void {
    if (!game) return;
    dispatch('submit_move', { gameId: game.gameId, player: handle, uci });
  }

  function offerDouble(): void {
    if (!game) return;
    const currentPot = game.stakeSats * game.multiplier;
    const newPot = currentPot * 2;
    const msg = walletAdapter
      ? `Offer the doubling cube?\n\nThis invites your opponent to double the pot from ${currentPot} sats to ${newPot} sats.\nIf they accept, your wallet will be asked to cover the difference (${currentPot} sats).`
      : `Offer the doubling cube?\n\nPot would grow from ${currentPot} sats to ${newPot} sats (notional — no wallet connected).`;
    if (!window.confirm(msg)) return;
    dispatch('offer_double', { gameId: game.gameId, player: handle });
  }

  async function acceptDouble(): Promise<void> {
    if (!game) return;
    const currentPot = game.stakeSats * game.multiplier;
    const newPot = currentPot * 2;
    const delta = currentPot; // the amount this player must commit to cover the doubled pot

    if (walletAdapter) {
      // Wallet connected — lock the additional stake on-chain.
      const ok = window.confirm(
        `Accept the doubling cube?\n\nYour wallet will be asked to lock ${delta} sats to cover the doubled pot (${newPot} sats total).\n\nClick OK to open the wallet approval dialog.`,
      );
      if (!ok) return;
      stakePhase = 'pending';
      status = `Waiting for wallet approval (${delta} sats for cube accept)…`;
      try {
        const result = await fundChessStake(walletAdapter, game.gameId, delta, myColor ?? 'join');
        stakePhase = 'funded';
        stakeTxidHex = result.txidHex;
        status = '';
        pushLog(`✓ cube stake locked: ${delta} sats → txid ${result.txidHex.slice(0, 16)}…`);
      } catch (e) {
        stakePhase = 'error';
        stakeError = e instanceof Error ? e.message : String(e);
        status = `Wallet rejected cube stake — ${stakeError}`;
        pushLog(`✗ cube accept wallet failed: ${stakeError}`);
        return;
      }
    } else {
      const ok = window.confirm(
        `Accept the doubling cube?\n\nPot doubles to ${newPot} sats (notional — no wallet connected).\n\nClick OK to accept.`,
      );
      if (!ok) return;
    }
    dispatch('accept_double', { gameId: game.gameId, player: handle });
  }

  function declineDouble(): void {
    if (!game) return;
    const currentPot = game.stakeSats * game.multiplier;
    if (!window.confirm(`Decline the cube and forfeit ${currentPot} sats?`)) return;
    dispatch('decline_double', { gameId: game.gameId, player: handle });
  }
  function cancelGame(): void {
    if (!game) return;
    if (!confirm('Cancel this game? Only allowed while waiting for an opponent.')) return;
    dispatch('cancel_game', { gameId: game.gameId, player: handle });
  }
  function resignGame(): void {
    if (!game) return;
    if (!confirm('Resign this game? Your opponent wins immediately.')) return;
    dispatch('resign_game', { gameId: game.gameId, player: handle });
  }

  // ─── UI-derived state ─────────────────────────────────────────────────

  // Invite URL embeds the brain bearer + brain URL in the #fragment so
  // the joining player's lobby auto-fills and they can Join directly.
  // Fragments don't hit server logs / Referer, but the *receiving party*
  // does see the bearer — by sharing the link you're explicitly giving
  // them operator-level access to the brain. That's correct for the
  // current single-bearer flow (two friends playing); a per-player BRC-
  // 100 identity model lands with the T7 brain-auth alignment.
  let inviteUrl = $derived.by(() => {
    if (!game) return '';
    const base = `${location.origin}/?invite=${encodeURIComponent(game.gameId)}`;
    if (!bearer) return base;
    const parts: string[] = [`bearer=${encodeURIComponent(bearer)}`];
    if (brainUrl && brainUrl !== defaultBrainWssUrl()) parts.push(`brain=${encodeURIComponent(brainUrl)}`);
    return `${base}#${parts.join('&')}`;
  });

  // True when we landed via an invite URL — affects lobby UX (skip the
  // colour picker, auto-suggest the Join action).
  let arrivedViaInvite = $derived(ROOM !== 'lobby');

  /**
   * Derive the wallet.html URL from the brain WSS URL.
   * wss://brain.oddjobtodd.info/api/v1/wallet → https://brain.oddjobtodd.info/wallet.html
   */
  function walletClaimUrl(): string {
    return brainUrl
      .replace(/^wss:\/\//, 'https://')
      .replace(/^ws:\/\//, 'http://')
      .replace(/\/api\/v1\/wallet$/, '/wallet.html');
  }

  // Copy-to-clipboard for the invite URL. Label flashes "copied!" then
  // resets so the user gets immediate feedback.
  let copyLabel = $state('Copy link');
  function copyInvite(): void {
    if (!inviteUrl) return;
    navigator.clipboard.writeText(inviteUrl)
      .then(() => {
        copyLabel = 'Copied!';
        setTimeout(() => { copyLabel = 'Copy link'; }, 1500);
      })
      .catch(() => { copyLabel = 'Copy failed'; });
  }

  let sideToMove = $derived.by<Color>(() => {
    if (!game) return 'white';
    // FEN side-to-move is more reliable than 'running' (clock might be paused).
    return game.fen.includes(' b ') ? 'black' : 'white';
  });

  // Only show the offer button when it's genuinely my turn to move (per
  // design §4: on your turn you either move or offer the cube).  The
  // brain enforces this too, but gating it here avoids confusing the UX
  // (button shows → user clicks → rejected "not_your_turn").
  let canOffer = $derived(
    !!game && game.status === 'active' && !game.pending && !!myColor &&
    sideToMove === myColor &&
    (game.cubeOwner === null || game.cubeOwner === myColor)
  );
  let canAccept = $derived(
    !!game && !!game.pending && !!myColor && game.pending.offerer !== myColor
  );
  let canDecline = $derived(canAccept);

  // Cancel is creator-only + only while the game is waiting. The brain
  // already enforces this; the SPA flag is purely UX so we don't show
  // the button to the wrong player. In a waiting game exactly one slot
  // is populated — the creator's.
  let canCancel = $derived(
    !!game && game.status === 'waiting' &&
    (game.white === handle || game.black === handle),
  );
  // Resign is for active games — either player can quit; opponent wins.
  let canResign = $derived(!!game && game.status === 'active' && !!myColor);
  let gameOver = $derived(!!game && isTerminal(game.status));

  // ── Captured pieces ────────────────────────────────────────────────────
  // Derived from the FEN: compare present material vs starting counts.
  // takenByWhite = black pieces white captured (glyphs to show by white's side)
  // takenByBlack = white pieces black captured (glyphs to show by black's side)
  const PIECE_GLYPH_MAP: Record<string, string> = {
    Q:'♕', R:'♖', B:'♗', N:'♘', P:'♙',
    q:'♛', r:'♜', b:'♝', n:'♞', p:'♟',
  };
  const START_COUNTS: Record<string, number> = { P:8,N:2,B:2,R:2,Q:1, p:8,n:2,b:2,r:2,q:1 };

  function computeCaptures(fen: string): { takenByWhite: string[], takenByBlack: string[] } {
    const counts: Record<string, number> = {};
    for (const ch of fen.split(' ')[0] ?? '') {
      if (ch in START_COUNTS) counts[ch] = (counts[ch] ?? 0) + 1;
    }
    const takenByWhite: string[] = []; // missing black pieces (lowercase)
    for (const p of ['q','r','b','n','p']) {
      const gone = (START_COUNTS[p] ?? 0) - (counts[p] ?? 0);
      for (let i = 0; i < gone; i++) takenByWhite.push(PIECE_GLYPH_MAP[p]!);
    }
    const takenByBlack: string[] = []; // missing white pieces (uppercase)
    for (const p of ['Q','R','B','N','P']) {
      const gone = (START_COUNTS[p] ?? 0) - (counts[p] ?? 0);
      for (let i = 0; i < gone; i++) takenByBlack.push(PIECE_GLYPH_MAP[p]!);
    }
    return { takenByWhite, takenByBlack };
  }

  // When board is flipped (playing black), flip which row is "top"
  let captures = $derived(game ? computeCaptures(game.fen) : { takenByWhite: [], takenByBlack: [] });
  // topCaptures = pieces at the top of the board (opponent's side from my view)
  let topCaptures    = $derived(myColor === 'black' ? captures.takenByWhite : captures.takenByBlack);
  let bottomCaptures = $derived(myColor === 'black' ? captures.takenByBlack : captures.takenByWhite);
</script>

<main>
  <header>
    <h1>chess · doubling cube</h1>
    <div class="conn">
      relay: <span class:ok={relayStatus === 'open'}>{relayStatus}</span> ·
      peers: {presence.length} ·
      handle: <code>{handle}</code>
      {#if walletAdapterName}
        · wallet: <span class="ok">{walletAdapterName}</span>
      {:else if walletDetecting}
        · wallet: <span>detecting…</span>
      {:else}
        · wallet: <span class="warn">none</span>
        <button type="button" class="link-btn" onclick={detectAndConnectWallet} title="Retry Metanet Desktop detection on localhost:3321">connect</button>
      {/if}
      {#if walletEnabled} · transport: <span class:ok={walletStatus === 'open'} class:warn={walletStatus === 'error'}>{walletStatus}</span>{/if}
    </div>
  </header>

  {#if !game}
    <section class="lobby">
      <h3>connect</h3>
      {#if walletAdapterName}
        <p class="hint">
          Connected to <strong>{walletAdapterName}</strong>. Your handle
          is bound to its identity pubkey
          (<code>{walletIdentityKey.slice(0, 12)}…</code>) so the brain
          tells you and your opponent apart.
        </p>
      {:else if walletDetecting}
        <p class="hint">Detecting a BRC-100 wallet (wasm iframe → Metanet Desktop on :3321)…</p>
      {:else}
        <p class="hint">
          No BRC-100 wallet found. Start
          <a href="https://metanet.bsvb.tech/" target="_blank" rel="noopener">Metanet Desktop</a>
          (it listens on <code>localhost:3321</code>) and
          <button type="button" class="link-btn" onclick={detectAndConnectWallet}>retry detection</button>
          — or proceed without a wallet and use a random handle.
        </p>
      {/if}
      <p class="hint">
        You also need an operator bearer token issued by the Semantos
        brain (with <code>brain bearer issue</code>). T7 brain-auth
        alignment removes this step — until then, paste it once below.
      </p>
      <label>handle <input bind:value={handle} placeholder="p-abc123" /></label>
      <label>bearer token <input bind:value={bearer} placeholder="64-char hex" autocomplete="off" /></label>
      <details>
        <summary>advanced: override brain URL</summary>
        <label>brain WSS <input bind:value={brainUrl} /></label>
      </details>

      {#if arrivedViaInvite}
        <h3>join game</h3>
        <p class="hint">
          You arrived via an invite link. The brain assigns you the
          opposite colour to the host automatically — no picker needed.
        </p>
        <label>game id <input bind:value={formGameId} readonly /></label>
        <div class="actions">
          <button class="primary" onclick={joinGame} disabled={!bearer}>Join as opponent</button>
        </div>
      {:else}
        <h3>create or join</h3>
        <label>game id <input bind:value={formGameId} /></label>
        <label>stake (sats) <input type="number" bind:value={formStake} min="0" /></label>
        {#if walletAdapterName && formStake > 0}
          <p class="hint" style="margin: 0;">
            <strong>{walletAdapterName}</strong> will prompt you to approve
            <strong>{formStake} sats</strong> when you click Create.
            {#if stakePhase === 'pending'}
              <span class="stake-pending">⏳ Waiting for wallet approval…</span>
            {:else if stakePhase === 'funded'}
              <span class="stake-ok">✓ Stake funded — txid {stakeTxidHex.slice(0, 16)}…</span>
            {:else if stakePhase === 'error'}
              <span class="stake-err">✗ {stakeError}</span>
            {/if}
          </p>
        {:else if !walletAdapterName}
          <p class="hint" style="margin: 0;">
            {#if walletDetecting}
              ⏳ Detecting wallet on <code>localhost:3321</code>…
            {:else}
              <strong>No wallet connected</strong> — stake will be notional.
              Start Metanet Desktop, then
              <button type="button" class="link-btn" onclick={detectAndConnectWallet}>connect wallet</button>
              to lock real sats.
            {/if}
          </p>
        {/if}
        <label>clock (ms) <input type="number" bind:value={formClockMs} min="10000" /></label>
        <label>my colour
          <select bind:value={formColor}>
            <option value="white">white</option>
            <option value="black">black</option>
          </select>
        </label>
        <div class="actions">
          <button class="primary" onclick={createGame} disabled={!bearer}>Create</button>
          <button onclick={joinGame} disabled={!bearer}>Join existing</button>
        </div>
      {/if}
      {#if status}<div class="status">{status}</div>{/if}
    </section>
  {:else}
    <section class="game">
      <div class="board-col" class:game-over={gameOver}>
        <!-- Opponent's captures sit above the board, mine sit below -->
        <div class="captures top-caps">
          {#each topCaptures as g}<span class="cap-glyph">{g}</span>{/each}
        </div>
        <Board fen={game.fen} sideToMove={sideToMove} myColor={myColor} legalMoves={legalMoves} onMove={submitMove} />
        <div class="captures bot-caps">
          {#each bottomCaptures as g}<span class="cap-glyph">{g}</span>{/each}
        </div>
        {#if gameOver}
          {@const pot = game.stakeSats * game.multiplier}
          {@const iWon = !!game.winner && game.winner === myColor}
          {@const iLost = !!game.winner && game.winner !== myColor}
          <div class="game-end" role="status">
            <div class="game-end-headline">
              {#if game.winner}
                {iWon ? '🏆 You won!' : `${game.winner === 'white' ? 'White' : 'Black'} wins.`}
              {:else if game.status === 'draw'}
                Draw.
              {:else}
                Game over.
              {/if}
            </div>
            <div class="game-end-reason">{endReasonLabel(game.endReason)}</div>

            <!-- Pot breakdown -->
            <div class="game-end-stake">
              {#if iWon}
                You collect <strong>{pot} sats</strong>
              {:else if iLost}
                You forfeit <strong>{pot} sats</strong>
              {:else if game.status === 'draw'}
                Pot split: <strong>{pot} sats</strong> returned
              {:else}
                Pot: <strong>{pot} sats</strong>
              {/if}
              {#if game.multiplier > 1}
                <span class="stake-detail">({game.stakeSats} × {game.multiplier})</span>
              {/if}
            </div>

            <!-- Stake txid (set when this session called createAction) -->
            {#if stakeTxidHex}
              <div class="game-end-txid">
                stake tx:
                <a
                  href="https://whatsonchain.com/tx/{stakeTxidHex}"
                  target="_blank"
                  rel="noopener"
                  class="txid-link"
                >{stakeTxidHex.slice(0, 24)}…</a>
              </div>
            {/if}

            <!-- Claim / settle -->
            <div class="game-end-claim">
              {#if stakeTxidHex}
                Settlement happens in
                <a href={walletClaimUrl()} target="_blank" rel="noopener">wallet.html</a>
                → enter game id <code>{game.gameId}</code> → Claim winnings.
              {:else}
                If this game was funded from wallet.html, open
                <a href={walletClaimUrl()} target="_blank" rel="noopener">wallet.html</a>
                to claim the pot.
              {/if}
            </div>

            <button type="button" class="game-end-action" onclick={() => location.href = location.origin}>New game</button>
          </div>
        {:else if game.status === 'waiting' && inviteUrl}
          <div class="invite-cta">
            <div class="invite-cta-row">
              <strong>Share this link to invite your opponent:</strong>
              <span class="invite-cta-buttons">
                <button type="button" class="copy" onclick={copyInvite}>{copyLabel}</button>
                {#if canCancel}
                  <button type="button" class="cancel" onclick={cancelGame}>Cancel game</button>
                {/if}
              </span>
            </div>
            <input class="invite-url" readonly value={inviteUrl} onfocus={(e) => (e.target as HTMLInputElement).select()} />
            <div class="invite-warn">
              ⚠ This link contains your brain bearer in the URL fragment. Only share it with someone you'd give operator-level access to your brain. Per-player identity (BRC-100 cert) lands with the brain-auth alignment.
            </div>
          </div>
        {/if}
        <div class="meta">
          <div>game <code>{game.gameId}</code> · status <strong>{game.status}</strong>{#if game.endReason !== 'none'} · {endReasonLabel(game.endReason)}{/if}</div>
          <div>white: <code>{game.white}</code> ({(game.whiteMs/1000).toFixed(1)}s)</div>
          <div>black: <code>{game.black}</code> ({(game.blackMs/1000).toFixed(1)}s)</div>
          <div>stake: <strong>{game.stakeSats} sats × {game.multiplier} = {game.stakeSats * game.multiplier} sats</strong>
            {#if stakeTxidHex}
              <span class="ok-inline">✓ funded on-chain</span>
            {:else}
              <span class="warn-inline">(notional — not yet funded on-chain)</span>
            {/if}
          </div>
          {#if game.winner}<div>winner: <strong>{game.winner}</strong></div>{/if}
          <div class="diag">
            you: <strong>{myColor ?? '?'}</strong> ·
            side-to-move: <strong>{sideToMove}</strong> ·
            your-turn: <strong>{myColor && sideToMove === myColor ? 'yes' : 'no'}</strong> ·
            legal-moves: <strong>{legalMoves.length}</strong>
          </div>
        </div>
      </div>
      <div class="side-col">
        <CubePanel
          multiplier={game.multiplier}
          stakeSats={game.stakeSats}
          cubeOwner={game.cubeOwner}
          pending={!!game.pending}
          myColor={myColor}
          canOffer={canOffer}
          canAccept={canAccept}
          canDecline={canDecline}
          onOffer={offerDouble}
          onAccept={acceptDouble}
          onDecline={declineDouble}
        />
        {#if canResign}
          <button type="button" class="resign-btn" onclick={resignGame}>Resign game</button>
        {/if}
        {#if status}<div class="status">{status}</div>{/if}
        <pre class="log">{log.join('\n')}</pre>
      </div>
    </section>
  {/if}
</main>

<style>
  :global(:root) {
    --bg: #0f1115;
    --fg: #e8eaed;
    --field-bg: #1a1d24;
    --field-border: #2a2f3a;
  }
  :global(html), :global(body) {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 14px system-ui, sans-serif;
  }
  main { padding: 1em; max-width: 1100px; margin: 0 auto; }
  header h1 { margin: 0 0 0.3em; font-size: 18px; }
  .conn { color: #9aa3b4; font: 12px ui-monospace, monospace; }
  .conn .ok { color: #2cb2a5; }
  .conn .warn { color: #d98e23; }
  .lobby {
    margin-top: 1em; max-width: 460px;
    display: flex; flex-direction: column; gap: 0.5em;
    padding: 1em; background: #14171d; border: 1px solid var(--field-border); border-radius: 6px;
  }
  .lobby h3 { margin: 0.6em 0 0.2em; font-size: 14px; color: #9aa3b4; text-transform: uppercase; letter-spacing: 0.05em; }
  .lobby h3:first-of-type { margin-top: 0; }
  .lobby .hint { margin: 0 0 0.6em; color: #9aa3b4; font-size: 13px; line-height: 1.45; }
  .lobby .hint a { color: #4f8cff; }
  .lobby .hint code { color: #c8cdd5; background: #0a0c11; padding: 0 0.3em; border-radius: 2px; }
  .link-btn {
    background: transparent; border: none; padding: 0;
    color: #4f8cff; text-decoration: underline;
    font: inherit; cursor: pointer;
  }
  .lobby label { display: flex; justify-content: space-between; gap: 0.6em; align-items: center; }
  .lobby details summary { cursor: pointer; color: #9aa3b4; font-size: 12px; margin: 0.2em 0; }
  .lobby details[open] { background: #0f1115; padding: 0.4em 0.6em; border-radius: 4px; margin-top: 0.2em; }
  input, select {
    background: var(--field-bg); color: var(--fg);
    border: 1px solid var(--field-border); border-radius: 3px;
    padding: 0.3em 0.5em; font: inherit; min-width: 220px;
  }
  .actions { display: flex; gap: 0.5em; margin-top: 0.4em; }
  button { padding: 0.5em 1em; font: inherit; border-radius: 4px; cursor: pointer; border: 1px solid var(--field-border); background: var(--field-bg); color: var(--fg); }
  button.primary { background: #4f8cff; color: white; border-color: #4f8cff; }
  button:disabled { opacity: 0.45; cursor: not-allowed; }
  .game { display: grid; grid-template-columns: minmax(300px, 1fr) 280px; gap: 1.5em; margin-top: 1em; align-items: start; }
  .board-col { display: flex; flex-direction: column; gap: 0; }
  .captures {
    display: flex;
    flex-wrap: wrap;
    gap: 1px;
    min-height: 22px;
    padding: 2px 0;
  }
  .cap-glyph {
    font-size: 15px;
    line-height: 1;
    opacity: 0.75;
  }
  .top-caps { margin-bottom: 2px; }
  .bot-caps { margin-top: 2px; margin-bottom: 0.8em; }
  .meta { font: 12px ui-monospace, monospace; color: #c8cdd5; display: flex; flex-direction: column; gap: 0.2em; margin-top: 0.4em; }
  .warn-inline  { color: #d98e23; font-size: 11px; margin-left: 0.5em; }
  .ok-inline    { color: #4caf50; font-size: 11px; margin-left: 0.5em; }
  .diag {
    margin-top: 0.3em; padding: 0.4em 0.6em;
    background: #0a0c11; border: 1px dashed var(--field-border); border-radius: 4px;
    color: #9aa3b4;
  }
  .diag strong { color: #c8cdd5; }
  .side-col { display: flex; flex-direction: column; gap: 0.8em; }
  .status { color: #e74c3c; font: 12px ui-monospace, monospace; }
  .invite-cta {
    background: #1a2440; border: 1px solid #4f8cff;
    border-radius: 6px; padding: 0.7em 0.9em;
    display: flex; flex-direction: column; gap: 0.4em;
  }
  .invite-cta-row {
    display: flex; justify-content: space-between; align-items: center; gap: 0.6em;
  }
  .invite-cta-row strong { color: #cfdcff; }
  .invite-cta-buttons { display: flex; gap: 0.4em; }
  .invite-cta .copy {
    padding: 0.35em 0.8em; font: inherit; border-radius: 4px;
    background: #4f8cff; color: white; border: 1px solid #4f8cff;
    cursor: pointer;
  }
  .invite-cta .cancel {
    padding: 0.35em 0.8em; font: inherit; border-radius: 4px;
    background: transparent; color: #e74c3c; border: 1px solid #e74c3c;
    cursor: pointer;
  }
  .game-end {
    background: #14171d; border: 2px solid #4f8cff;
    border-radius: 6px; padding: 1em 1.2em;
    display: flex; flex-direction: column; gap: 0.4em; align-items: flex-start;
  }
  .game-end-headline { font-size: 22px; font-weight: 600; color: var(--fg); }
  .game-end-reason { color: #c8cdd5; }
  .game-end-stake {
    font-size: 15px; font-weight: 500; color: #e8eaed;
  }
  .game-end-stake .stake-detail { font-size: 11px; color: #5a6275; margin-left: 0.4em; }
  .game-end-txid {
    font: 11px ui-monospace, monospace; color: #9aa3b4;
    background: #0a0c11; border: 1px solid #1e2330;
    border-radius: 3px; padding: 0.3em 0.6em; width: 100%;
  }
  .game-end-txid .txid-link { color: #4f8cff; text-decoration: none; }
  .game-end-txid .txid-link:hover { text-decoration: underline; }
  .game-end-claim {
    font-size: 12px; color: #9aa3b4;
    background: #0d1420; border: 1px solid #1e2c40;
    border-radius: 4px; padding: 0.5em 0.7em; width: 100%;
  }
  .game-end-claim a { color: #4f8cff; }
  .game-end-claim code { font-size: 10px; color: #c8cdd5; }
  .game-end-action {
    margin-top: 0.4em; padding: 0.5em 1em;
    background: #4f8cff; color: white; border: 1px solid #4f8cff;
    border-radius: 4px; cursor: pointer; font: inherit;
  }
  .board-col.game-over :global(.board) { opacity: 0.65; pointer-events: none; }
  .resign-btn {
    padding: 0.45em 0.8em; font: inherit; border-radius: 4px; cursor: pointer;
    background: transparent; color: #e74c3c; border: 1px solid #e74c3c;
    align-self: flex-start;
  }
  .resign-btn:hover { background: rgba(231, 76, 60, 0.1); }
  .invite-url {
    width: 100%; box-sizing: border-box;
    background: #0a0c11; color: #c8cdd5;
    border: 1px solid var(--field-border); border-radius: 3px;
    padding: 0.4em 0.6em; font: 11px ui-monospace, monospace;
  }
  .invite-warn {
    color: #f5c4c4; font-size: 11px; line-height: 1.45;
  }
  .log {
    background: #0a0c11; color: #c8cdd5; padding: 0.6em;
    margin: 0; font: 11px ui-monospace, monospace;
    max-height: 16em; overflow-y: auto; white-space: pre-wrap;
    border-radius: 4px; border: 1px solid var(--field-border);
  }
  @media (max-width: 760px) {
    .game { grid-template-columns: 1fr; }
  }
</style>

```
