---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/TalkModeView.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.074830+00:00
---

# apps/loom-svelte/src/views/TalkModeView.svelte

```svelte
<script lang="ts">
  /**
   * TalkModeView — Talk intent top-level surface.
   *
   * The five Talk sub-contexts (self / direct / squad / agent / broadcast)
   * are sub-routes within this container.  Each dock tier-2 context click
   * navigates here via App.svelte's directContextNav map; the active
   * sub-context is passed as a prop.
   *
   * D-svelte-talk-mode:
   *   self      → TalkSelfView (intent classifier round-trip, V1)
   *   direct    → TalkDirectView (contact picker + queued-send thread, V1)
   *   squad     → TalkContextStub
   *   agent     → TalkContextStub
   *   broadcast → TalkContextStub
   */
  import TalkSelfView from './talk/TalkSelfView.svelte';
  import TalkDirectView from './talk/TalkDirectView.svelte';
  import TalkAgentView from './talk/TalkAgentView.svelte';
  import TalkContextStub from './talk/TalkContextStub.svelte';
  import type { TalkContextId } from '../shell/context-weights';

  let {
    context,
    brainBase,
    bearer,
    onGoHome,
  }: {
    context: TalkContextId;
    brainBase: string;
    bearer: string;
    onGoHome: () => void;
  } = $props();

  const CONTEXT_META: Record<TalkContextId, { icon: string; label: string; description: string; deliverable?: string }> = {
    self:      { icon: '◎', label: 'Self',      description: 'Reflection — goals, intentions, your Paskian graph' },
    direct:    { icon: '↔', label: 'Direct',    description: '1:1 encrypted connection with another identity' },
    squad:     { icon: '⌂', label: 'Squad',     description: 'Private group coordination — teams, study groups', deliverable: 'D-svelte-talk-squad' },
    agent:     { icon: '⌖', label: 'Agent',     description: 'LLM interaction — ask the system to execute tasks' },
    broadcast: { icon: '◉', label: 'Broadcast', description: 'The town square — governance, public taxonomy',    deliverable: 'D-svelte-talk-broadcast' },
  };

  const meta = $derived(CONTEXT_META[context]);
</script>

<div class="talk-mode">
  <!-- Header -->
  <div class="talk-header">
    <button class="home-btn" onclick={onGoHome} aria-label="Home">← Home</button>
    <div class="talk-title">
      <span class="talk-icon">{meta.icon}</span>
      Talk · {meta.label}
    </div>
    <div class="spacer"></div>
  </div>

  <!-- Sub-context content -->
  <div class="talk-body">
    {#if context === 'self'}
      <TalkSelfView {brainBase} {bearer} />
    {:else if context === 'direct'}
      <TalkDirectView {brainBase} {bearer} />
    {:else if context === 'agent'}
      <TalkAgentView {brainBase} {bearer} />
    {:else}
      <TalkContextStub
        contextId={context}
        icon={meta.icon}
        label={meta.label}
        description={meta.description}
        nextDeliverable={meta.deliverable}
      />
    {/if}
  </div>
</div>

<style>
  .talk-mode {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  .talk-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #1e293b;
    background: #111827;
    flex-shrink: 0;
  }

  .home-btn {
    background: transparent;
    border: none;
    color: #60a5fa;
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    transition: color 0.1s, background 0.1s;
  }

  .home-btn:hover {
    color: #93c5fd;
    background: rgba(96, 165, 250, 0.1);
  }

  .talk-title {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    font-size: 1rem;
    font-weight: 600;
    color: #f1f5f9;
  }

  .talk-icon { font-size: 1rem; }

  .spacer { width: 60px; } /* mirrors home-btn width for centering */

  .talk-body {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
</style>

```
