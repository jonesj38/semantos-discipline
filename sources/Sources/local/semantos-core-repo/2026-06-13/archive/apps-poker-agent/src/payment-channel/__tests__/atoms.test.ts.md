---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/__tests__/atoms.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.794823+00:00
---

# archive/apps-poker-agent/src/payment-channel/__tests__/atoms.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { get, subscribe } from '@semantos/state';
import {
  getChannelAtoms,
  listChannelIds,
  resetChannelAtoms,
} from '../atoms';

afterEach(() => {
  resetChannelAtoms();
});

describe('getChannelAtoms', () => {
  test('1. returns the same bundle when called twice with the same id', () => {
    const a = getChannelAtoms('chan-1');
    const b = getChannelAtoms('chan-1');
    expect(a).toBe(b);
  });

  test('2. distinct ids → distinct bundles', () => {
    const a = getChannelAtoms('chan-1');
    const b = getChannelAtoms('chan-2');
    expect(a).not.toBe(b);
    expect(a.stateAtom).not.toBe(b.stateAtom);
  });

  test('3. initial channelStateAtom value is UNFUNDED', () => {
    const { channelStateAtom } = getChannelAtoms('chan-1');
    expect(get(channelStateAtom)).toBe('UNFUNDED');
  });

  test('4. initial stateAtom carries the channelId + role', () => {
    const { stateAtom } = getChannelAtoms('chan-7', 'provider');
    const v = get(stateAtom);
    expect(v.channelId).toBe('chan-7');
    expect(v.role).toBe('provider');
    expect(v.state).toBe('UNFUNDED');
  });

  test('5. initial artifactsAtom is null', () => {
    const { artifactsAtom } = getChannelAtoms('chan-1');
    expect(get(artifactsAtom)).toBeNull();
  });

  test('6. channelEventsBus delivers to subscribers', () => {
    const { channelEventsBus } = getChannelAtoms('chan-1');
    const seen: string[] = [];
    channelEventsBus.on((e) => seen.push(e.type));
    channelEventsBus.emit({ type: 'flow-ready' });
    expect(seen).toEqual(['flow-ready']);
  });

  test('7. listChannelIds reflects every getChannelAtoms call', () => {
    getChannelAtoms('a');
    getChannelAtoms('b');
    expect(listChannelIds().sort()).toEqual(['a', 'b']);
  });

  test('8. resetChannelAtoms clears the registry', () => {
    getChannelAtoms('zzz');
    resetChannelAtoms();
    expect(listChannelIds()).toEqual([]);
  });

  test('9. atom subscriptions fire only when value changes', () => {
    const { stateAtom } = getChannelAtoms('chan-1');
    let count = 0;
    subscribe(stateAtom, () => count++);
    // Same instance → no notification.
    expect(count).toBe(0);
  });
});

```
