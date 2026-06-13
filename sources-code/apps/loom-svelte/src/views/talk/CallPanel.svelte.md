---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/talk/CallPanel.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.087467+00:00
---

# apps/loom-svelte/src/views/talk/CallPanel.svelte

```svelte
<script lang="ts">
  /**
   * CallPanel — place / answer a real WebRTC audio call to the active contact,
   * over the brain signalling relay (D-helm-talk-call).
   *
   * Outgoing: tap Call → getUserMedia → place. Incoming: the shared plane's
   * onIncomingCall surfaces a ringing banner → Answer/Decline. Audio plays via a
   * hidden sink (rtc-call.playRemote).
   *
   * Signalling rides the brain MessageBox relay; media is real WebRTC; the
   * operator signature comes from the brain (POST /api/v1/bundle/sign) and the
   * recipient verifies inbound calls against the sender's pubkey. This component
   * is runtime-verified in a browser, not in CI.
   */
  import {
    makeHelmRtcPlane,
    getBrainIdentity,
    placeCall,
    answerCall,
    playRemote,
    type BrainInfoIdentity,
    type HelmRtcDeps,
  } from '../../lib/rtc-call';
  import type { BrainContact } from '../../lib/contacts-api';

  let {
    brainBase,
    bearer,
    contacts,
    activePeer,
  }: {
    brainBase: string;
    bearer: string;
    contacts: BrainContact[];
    activePeer: BrainContact | null;
  } = $props();

  type State = 'idle' | 'placing' | 'ringing' | 'in-call' | 'error';
  let state = $state<State>('idle');
  let statusText = $state('');
  let incomingFrom = $state<string | null>(null);

  let identity: BrainInfoIdentity | null = null;
  let plane: ReturnType<typeof makeHelmRtcPlane> | null = null;
  let active: { call: { hangup: () => Promise<void>; onConnected: (cb: () => void) => void; signal: { state: string } }; stopMic: () => void; stopAudio: () => void } | null = null;
  let pendingIncoming: any = null;

  const pubkeyOf = (certId: string) => contacts.find((c) => c.certId === certId)?.publicKey;

  async function ensurePlane(): Promise<NonNullable<typeof plane>> {
    if (plane) return plane;
    identity = await getBrainIdentity(brainBase, bearer);
    const deps: HelmRtcDeps = { brainBase, bearer, identity, contactPubkey: pubkeyOf };
    plane = makeHelmRtcPlane(deps);
    plane.onIncomingCall((incoming) => {
      pendingIncoming = incoming;
      incomingFrom = contacts.find((c) => c.certId === incoming.peerCertId)?.displayName ?? incoming.peerCertId;
      state = 'ringing';
    });
    return plane;
  }

  async function call() {
    if (!activePeer) return;
    try {
      state = 'placing';
      statusText = 'Connecting…';
      const p = await ensurePlane();
      const { call, stopMic } = await placeCall(p, activePeer.certId);
      const stopAudio = playRemote(call as never);
      active = { call: call as never, stopMic, stopAudio };
      call.onConnected(() => {
        state = 'in-call';
        statusText = 'Connected';
      });
    } catch (e) {
      state = 'error';
      statusText = e instanceof Error ? e.message : 'Call failed';
    }
  }

  async function answer() {
    try {
      const { call, stopMic } = await answerCall(pendingIncoming);
      const stopAudio = playRemote(call as never);
      active = { call: call as never, stopMic, stopAudio };
      call.onConnected(() => {
        state = 'in-call';
        statusText = 'Connected';
      });
      state = 'in-call';
      pendingIncoming = null;
    } catch (e) {
      state = 'error';
      statusText = e instanceof Error ? e.message : 'Answer failed';
    }
  }

  function decline() {
    pendingIncoming = null;
    incomingFrom = null;
    state = 'idle';
  }

  async function hangup() {
    try {
      await active?.call.hangup();
    } catch {
      /* already gone */
    }
    active?.stopMic();
    active?.stopAudio();
    active = null;
    state = 'idle';
    statusText = '';
  }
</script>

<div class="call-panel">
  {#if state === 'ringing'}
    <div class="ringing">
      <span>📞 {incomingFrom} is calling…</span>
      <button class="answer" onclick={answer}>Answer</button>
      <button class="decline" onclick={decline}>Decline</button>
    </div>
  {:else if state === 'in-call'}
    <div class="in-call">
      <span class="dot"></span><span>{statusText || 'In call'}</span>
      <button class="hangup" onclick={hangup}>Hang up</button>
    </div>
  {:else if state === 'placing'}
    <div class="placing"><span>{statusText}</span><button class="hangup" onclick={hangup}>Cancel</button></div>
  {:else}
    <button class="call" disabled={!activePeer} onclick={call} title="Audio call (beta)">📞 Call</button>
    {#if state === 'error'}<span class="err">{statusText}</span>{/if}
  {/if}
</div>

<style>
  .call-panel { display: flex; align-items: center; gap: 0.5rem; font-size: 0.85rem; }
  button { cursor: pointer; border-radius: 6px; border: 1px solid var(--border, #334); padding: 0.3rem 0.6rem; background: var(--surface, #1b2030); color: inherit; }
  button:disabled { opacity: 0.5; cursor: default; }
  .call { background: #1f6feb22; border-color: #1f6feb55; }
  .answer { background: #2ea04322; border-color: #2ea04355; }
  .decline, .hangup { background: #f8514922; border-color: #f8514955; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: #2ea043; display: inline-block; }
  .err { color: #f85149; }
</style>

```
