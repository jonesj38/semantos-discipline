---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/test/useVoiceCapture.test.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.932955+00:00
---

# archive/apps-loom-react/test/useVoiceCapture.test.tsx

```tsx
/**
 * Phase 38E — Gate tests T1–T14 for useVoiceCapture hook and VoiceInput component.
 *
 * Mock SpeechRecognition simulates the browser API in jsdom.
 * Tests verify: feature detection, lazy creation, interim/final split,
 * permission denied, abort on unmount, and component UX.
 */

import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import { renderHook } from '@testing-library/react';
import '@testing-library/jest-dom';
import React from 'react';

// Import after mock setup — these will be created in D38E.2/D38E.3
import { useVoiceCapture } from '../src/helm/hooks/useVoiceCapture';
import { VoiceInput } from '../src/helm/VoiceInput';

// ── Mock SpeechRecognition ──

class MockSpeechRecognition {
  static instances: MockSpeechRecognition[] = [];

  continuous = false;
  interimResults = false;
  lang = '';
  onresult: ((event: any) => void) | null = null;
  onend: (() => void) | null = null;
  onerror: ((event: { error: string }) => void) | null = null;
  started = false;
  stopped = false;
  aborted = false;

  constructor() {
    MockSpeechRecognition.instances.push(this);
  }

  start() {
    this.started = true;
  }

  stop() {
    this.stopped = true;
  }

  abort() {
    this.aborted = true;
  }

  /** Simulate a speech result event. */
  simulateResult(transcript: string, isFinal: boolean) {
    this.onresult?.({
      resultIndex: 0,
      results: [{
        0: { transcript, confidence: 0.95 },
        length: 1,
        isFinal,
      }],
    });
  }

  simulateError(error: string) {
    this.onerror?.({ error });
  }

  simulateEnd() {
    this.onend?.();
  }

  static reset() {
    MockSpeechRecognition.instances = [];
  }
}

// ── Hook Tests (T1–T10) ──

describe('Phase 38E — useVoiceCapture hook', () => {
  beforeEach(() => {
    MockSpeechRecognition.reset();
    delete (window as any).SpeechRecognition;
    delete (window as any).webkitSpeechRecognition;
  });

  afterEach(() => {
    delete (window as any).SpeechRecognition;
    delete (window as any).webkitSpeechRecognition;
  });

  test('T1: supported is false when SpeechRecognition is absent', () => {
    const { result } = renderHook(() => useVoiceCapture());
    expect(result.current.supported).toBe(false);
    expect(result.current.listening).toBe(false);
  });

  test('T2: supported is true when SpeechRecognition exists', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());
    expect(result.current.supported).toBe(true);
  });

  test('T3: no instance created until start() is called (lazy creation)', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());
    expect(MockSpeechRecognition.instances).toHaveLength(0);

    act(() => result.current.start());
    expect(MockSpeechRecognition.instances).toHaveLength(1);
  });

  test('T4: start() applies lang and continuous from options', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() =>
      useVoiceCapture({ lang: 'fr-FR', continuous: true }),
    );

    act(() => result.current.start());
    const instance = MockSpeechRecognition.instances[0];
    expect(instance.lang).toBe('fr-FR');
    expect(instance.continuous).toBe(true);
    expect(instance.interimResults).toBe(true);
  });

  test('T5: interim result updates interim; final result updates transcript and clears interim', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    const instance = MockSpeechRecognition.instances[0];

    // Interim result
    act(() => instance.simulateResult('hello', false));
    expect(result.current.interim).toBe('hello');
    expect(result.current.transcript).toBe('');

    // Final result
    act(() => instance.simulateResult('hello world', true));
    expect(result.current.transcript).toBe('hello world');
    expect(result.current.interim).toBe('');
  });

  test('T6: stop() calls stop() on instance; onend sets listening to false', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    expect(result.current.listening).toBe(true);

    const instance = MockSpeechRecognition.instances[0];
    act(() => result.current.stop());
    expect(instance.stopped).toBe(true);

    act(() => instance.simulateEnd());
    expect(result.current.listening).toBe(false);
  });

  test('T7: unmount calls abort() not stop()', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result, unmount } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    const instance = MockSpeechRecognition.instances[0];

    unmount();
    expect(instance.aborted).toBe(true);
    expect(instance.stopped).toBe(false);
  });

  test('T8: error "not-allowed" sets permissionDenied and clears listening', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    const instance = MockSpeechRecognition.instances[0];

    act(() => instance.simulateError('not-allowed'));
    expect(result.current.permissionDenied).toBe(true);
    expect(result.current.error).toBe('not-allowed');
    expect(result.current.listening).toBe(false);
  });

  test('T9: reset() clears transcript, interim, error, and permissionDenied', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    const instance = MockSpeechRecognition.instances[0];

    act(() => instance.simulateResult('hello world', true));
    act(() => instance.simulateError('not-allowed'));

    expect(result.current.transcript).toBe('hello world');
    expect(result.current.permissionDenied).toBe(true);

    act(() => result.current.reset());
    expect(result.current.transcript).toBe('');
    expect(result.current.interim).toBe('');
    expect(result.current.error).toBeNull();
    expect(result.current.permissionDenied).toBe(false);
  });

  test('T10: start() after stop creates a fresh instance', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const { result } = renderHook(() => useVoiceCapture());

    act(() => result.current.start());
    expect(MockSpeechRecognition.instances).toHaveLength(1);

    const first = MockSpeechRecognition.instances[0];
    act(() => result.current.stop());
    act(() => first.simulateEnd());

    act(() => result.current.start());
    expect(MockSpeechRecognition.instances).toHaveLength(2);
  });
});

// ── Component Tests (T11–T14) ──

describe('Phase 38E — VoiceInput component', () => {
  beforeEach(() => {
    MockSpeechRecognition.reset();
    delete (window as any).SpeechRecognition;
    delete (window as any).webkitSpeechRecognition;
  });

  afterEach(() => {
    delete (window as any).SpeechRecognition;
    delete (window as any).webkitSpeechRecognition;
  });

  test('T11: renders "not supported" message when SpeechRecognition absent', () => {
    render(<VoiceInput onUtterance={vi.fn()} />);
    expect(screen.getByText(/not supported/i)).toBeInTheDocument();
  });

  test('T12: mic button toggles listening state', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    render(<VoiceInput onUtterance={vi.fn()} />);

    const micBtn = screen.getByRole('button', { name: /voice/i });
    act(() => fireEvent.click(micBtn));
    expect(MockSpeechRecognition.instances).toHaveLength(1);
    expect(MockSpeechRecognition.instances[0].started).toBe(true);
  });

  test('T13: submit calls onUtterance with transcript', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const onUtterance = vi.fn();
    render(<VoiceInput onUtterance={onUtterance} />);

    // Start and produce transcript
    const micBtn = screen.getByRole('button', { name: /voice/i });
    act(() => fireEvent.click(micBtn));
    act(() => MockSpeechRecognition.instances[0].simulateResult('kill port nine thousand', true));

    // Submit
    const submitBtn = screen.getByRole('button', { name: /send/i });
    act(() => fireEvent.click(submitBtn));
    expect(onUtterance).toHaveBeenCalledWith('kill port nine thousand');
  });

  test('T14: user can edit transcript before submitting', () => {
    (window as any).SpeechRecognition = MockSpeechRecognition;
    const onUtterance = vi.fn();
    render(<VoiceInput onUtterance={onUtterance} />);

    // Start and produce transcript
    const micBtn = screen.getByRole('button', { name: /voice/i });
    act(() => fireEvent.click(micBtn));
    act(() => MockSpeechRecognition.instances[0].simulateResult('hello wrold', true));

    // Edit the transcript
    const input = screen.getByRole('textbox');
    act(() => fireEvent.change(input, { target: { value: 'hello world' } }));

    // Submit corrected text
    const submitBtn = screen.getByRole('button', { name: /send/i });
    act(() => fireEvent.click(submitBtn));
    expect(onUtterance).toHaveBeenCalledWith('hello world');
  });
});

```
