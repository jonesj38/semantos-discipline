---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38E-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.663706+00:00
---

# Phase 38E Execution Prompt — Voice Capture Adapter

> Paste into a fresh session. **Parallel track** — can start day one. Pure browser UI. No blocks.

## Context

Helm needs an ear. This sub-phase builds the thin browser adapter that turns spoken audio into plain text — nothing more. It does NOT parse, dispatch, sign, or publish. That is 38F and 38C's job.

The adapter is a React hook + tiny UI control. It wraps the browser's Web Speech API, exposes start/stop, surfaces the transcript as state, and gracefully degrades when the API is unavailable.

This deliberately does NOT bundle Whisper.cpp wasm. Web Speech first; Whisper fallback lands in a 38.x errata if real-world usage shows the browser API is insufficient.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic
- `packages/loom/src/helm/TalkMode.tsx` — where the adapter will be consumed (in the Agent or Direct context)
- `packages/loom/src/helm/Helm.tsx` — how mode/context state flows
- Any existing custom hooks in `packages/loom/src/helm/hooks/` — follow the file layout and naming

---

## ANTI-BULLSHIT RULES

1. **Feature-detect, don't assume.** `window.SpeechRecognition ?? window.webkitSpeechRecognition` — if neither exists, the hook reports `supported: false` and renders a disabled mic with a tooltip. It does NOT throw on module load.
2. **No auto-start.** The mic never listens without an explicit user gesture. A click, keypress, or explicit call. Browsers will reject autoplay anyway, but the code should also respect the user.
3. **No transcript persistence here.** The hook holds the live transcript in React state. It does NOT write to LoomStore, localStorage, or IndexedDB. The consumer decides what to keep.
4. **No network.** The browser's speech recognition API may call out to a cloud service (Chrome does this). Document it in the README, but do NOT add your own network calls. Zero fetches from this module.
5. **No microphone without permission.** If `navigator.mediaDevices` is blocked, the hook reports `permissionDenied: true`. No silent failures.
6. **Dispose cleanly.** On unmount or stop, the `SpeechRecognition` instance is `.abort()`ed and references cleared. Leaked instances keep the mic hot — unacceptable.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
# This is a self-contained UI track. Commit directly on the phase branch, or cut a sub-branch if you prefer:
# git checkout -b phase-38-voice-to-execution/D38E
```

---

## Step 1: `useVoiceCapture()` Hook (D38E.1)

### 1.1 Create `packages/loom/src/helm/hooks/useVoiceCapture.ts`

```ts
import { useCallback, useEffect, useRef, useState } from 'react';

export interface VoiceCaptureState {
  supported: boolean;
  listening: boolean;
  permissionDenied: boolean;
  interim: string;       // partial transcript (live)
  transcript: string;    // finalized transcript
  error: string | null;
}

export interface VoiceCaptureControls {
  start: () => void;
  stop: () => void;
  reset: () => void;
}

export function useVoiceCapture(
  options: { lang?: string; continuous?: boolean } = {},
): VoiceCaptureState & VoiceCaptureControls {
  const SRCtor: any =
    (typeof window !== 'undefined' && (window as any).SpeechRecognition) ||
    (typeof window !== 'undefined' && (window as any).webkitSpeechRecognition) ||
    null;

  const supported = !!SRCtor;
  const recRef = useRef<any>(null);

  const [listening, setListening] = useState(false);
  const [permissionDenied, setPermissionDenied] = useState(false);
  const [interim, setInterim] = useState('');
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setInterim('');
    setTranscript('');
    setError(null);
  }, []);

  const start = useCallback(() => {
    if (!supported) {
      setError('Speech recognition not supported in this browser');
      return;
    }
    if (recRef.current) return; // already running
    const rec = new SRCtor();
    rec.lang = options.lang ?? 'en-US';
    rec.continuous = options.continuous ?? false;
    rec.interimResults = true;

    rec.onresult = (ev: any) => {
      let interimText = '';
      let finalText = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const chunk = ev.results[i][0].transcript;
        if (ev.results[i].isFinal) finalText += chunk;
        else interimText += chunk;
      }
      if (interimText) setInterim(interimText);
      if (finalText) {
        setTranscript(prev => (prev + ' ' + finalText).trim());
        setInterim('');
      }
    };
    rec.onerror = (ev: any) => {
      if (ev.error === 'not-allowed' || ev.error === 'service-not-allowed') {
        setPermissionDenied(true);
      }
      setError(String(ev.error ?? 'recognition error'));
      setListening(false);
    };
    rec.onend = () => {
      setListening(false);
      recRef.current = null;
    };
    rec.start();
    recRef.current = rec;
    setListening(true);
    setError(null);
  }, [supported, options.lang, options.continuous]);

  const stop = useCallback(() => {
    const rec = recRef.current;
    if (rec) {
      try { rec.stop(); } catch { /* ignore */ }
    }
  }, []);

  useEffect(() => () => {
    const rec = recRef.current;
    if (rec) {
      try { rec.abort(); } catch { /* ignore */ }
      recRef.current = null;
    }
  }, []);

  return { supported, listening, permissionDenied, interim, transcript, error, start, stop, reset };
}
```

### 1.2 Commit

```bash
git add packages/loom/src/helm/hooks/useVoiceCapture.ts
git commit -m "phase-38/D38E.1: useVoiceCapture hook — Web Speech API wrapper with graceful degradation"
```

---

## Step 2: Mic UI Control (D38E.2)

### 2.1 Create `packages/loom/src/helm/VoiceInput.tsx`

A small component that renders a mic button + live transcript preview. Props:

```ts
interface VoiceInputProps {
  onUtterance: (text: string) => void;  // fires when transcript finalizes and user submits
  placeholder?: string;
  autoSubmitOnFinal?: boolean;          // if true, fire onUtterance as soon as a final chunk arrives
}
```

Requirements:

- Mic icon toggles listening. Red pulse when live.
- Live interim text appears below the icon in a muted color.
- Final transcript appears in a readable box, editable by the user (they can correct).
- "Submit" button fires `onUtterance(transcript)` and resets state.
- If `supported === false`, render a greyed-out mic with a tooltip: "Voice not supported — try Chrome or Edge".
- If `permissionDenied === true`, show inline text: "Microphone permission denied. Enable it in browser settings."

### 2.2 Style

Use existing Helm design tokens. No new CSS files; reuse the Helm stylesheet. Keep it small — this lives inside an existing panel, it's not a page of its own.

### 2.3 Commit

```bash
git add packages/loom/src/helm/VoiceInput.tsx
git commit -m "phase-38/D38E.2: VoiceInput control — mic button, live transcript, edit-before-submit"
```

---

## Step 3: Mount Point in Talk Mode (D38E.3)

### 3.1 Update `packages/loom/src/helm/TalkMode.tsx`

Add `VoiceInput` to the **Agent** context pane (or Direct, whichever the project prefers — the map in `extension-config.ts` under Talk/Agent is the canonical target). The `onUtterance` handler is a **no-op stub** for now:

```tsx
<VoiceInput onUtterance={(text) => console.log('[helm:voice]', text)} />
```

38G wires this to the real NL extractor + approval card. 38E's job is only to make the mic appear and produce text.

### 3.2 Commit

```bash
git add packages/loom/src/helm/TalkMode.tsx
git commit -m "phase-38/D38E.3: mount VoiceInput in Talk/Agent (stub handler — wired in 38G)"
```

---

## Step 4: Gate Tests (D38E.4)

Add to `packages/__tests__/phase38-gate.test.ts` (or a sibling file if the UI is tested elsewhere — follow existing patterns):

1. `useVoiceCapture()` in a jsdom env where `SpeechRecognition` is undefined → `supported: false`, `listening: false`. Calling `start()` sets `error` but does not throw.
2. Mock `SpeechRecognition`, fire a synthetic `onresult` with an `isFinal: true` chunk → `transcript` contains the expected text.
3. `stop()` while listening → `.stop()` called on the recognition instance.
4. Unmount the hook while listening → `.abort()` called; no dangling ref.
5. `onerror` with `error: 'not-allowed'` → `permissionDenied: true`, `listening: false`.

Commit:

```bash
git commit -m "phase-38/D38E.4: gate tests for useVoiceCapture lifecycle and error paths"
```

---

## Exit Criteria

- [ ] `useVoiceCapture()` hook lands, feature-detects cleanly, disposes on unmount.
- [ ] `VoiceInput` UI renders mic + live transcript in Talk mode.
- [ ] Graceful degradation on unsupported browsers and denied permission.
- [ ] All gate tests pass.

Hand off: done. 38G will consume `VoiceInput.onUtterance` and route it through the NL extractor (38F) and `host.exec` (38C).
