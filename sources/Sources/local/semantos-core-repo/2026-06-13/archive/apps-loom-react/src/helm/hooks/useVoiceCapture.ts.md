---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/hooks/useVoiceCapture.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.975987+00:00
---

# archive/apps-loom-react/src/helm/hooks/useVoiceCapture.ts

```ts
/**
 * useVoiceCapture — Web Speech API hook with interim/final split,
 * permission tracking, and clean abort-on-unmount.
 *
 * Wraps the browser's SpeechRecognition API. Feature-detects at call
 * time (never throws on import). Creates a fresh instance per start()
 * call — no eager allocation, no leaked mic sessions.
 *
 * Phase 38E — consumed by VoiceInput, wired to NL extractor in 38G.
 */

import { useCallback, useEffect, useRef, useState } from 'react';

export interface VoiceCaptureOptions {
  lang?: string;
  continuous?: boolean;
}

export interface VoiceCaptureState {
  supported: boolean;
  listening: boolean;
  permissionDenied: boolean;
  interim: string;
  transcript: string;
  error: string | null;
  start: () => void;
  stop: () => void;
  reset: () => void;
}

interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((event: any) => void) | null;
  onend: (() => void) | null;
  onerror: ((event: { error: string }) => void) | null;
}

type SpeechRecognitionCtor = new () => SpeechRecognitionLike;

function getRecognitionCtor(): SpeechRecognitionCtor | null {
  if (typeof window === 'undefined') return null;
  const w = window as any;
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export function useVoiceCapture(
  options: VoiceCaptureOptions = {},
): VoiceCaptureState {
  const Ctor = getRecognitionCtor();
  const supported = !!Ctor;

  const recRef = useRef<SpeechRecognitionLike | null>(null);
  const [listening, setListening] = useState(false);
  const [permissionDenied, setPermissionDenied] = useState(false);
  const [interim, setInterim] = useState('');
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);

  const start = useCallback(() => {
    if (!Ctor) {
      setError('Speech recognition not supported in this browser');
      return;
    }
    if (recRef.current) return;

    const rec = new Ctor();
    rec.lang = options.lang ?? 'en-US';
    rec.continuous = options.continuous ?? false;
    rec.interimResults = true;

    rec.onresult = (ev: any) => {
      let interimText = '';
      let finalText = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const chunk = ev.results[i][0].transcript;
        if (ev.results[i].isFinal) {
          finalText += chunk;
        } else {
          interimText += chunk;
        }
      }
      if (finalText) {
        setTranscript(prev => (prev ? prev + ' ' + finalText : finalText).trim());
        setInterim('');
      } else if (interimText) {
        setInterim(interimText);
      }
    };

    rec.onerror = (ev: { error: string }) => {
      if (ev.error === 'not-allowed' || ev.error === 'service-not-allowed') {
        setPermissionDenied(true);
      }
      setError(ev.error ?? 'recognition error');
      setListening(false);
      recRef.current = null;
    };

    rec.onend = () => {
      setListening(false);
      recRef.current = null;
    };

    rec.start();
    recRef.current = rec;
    setListening(true);
    setError(null);
  }, [Ctor, options.lang, options.continuous]);

  const stop = useCallback(() => {
    const rec = recRef.current;
    if (rec) {
      try { rec.stop(); } catch { /* ignore */ }
    }
  }, []);

  const reset = useCallback(() => {
    setTranscript('');
    setInterim('');
    setError(null);
    setPermissionDenied(false);
  }, []);

  // Abort on unmount — not stop. abort() kills immediately without firing onresult.
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
