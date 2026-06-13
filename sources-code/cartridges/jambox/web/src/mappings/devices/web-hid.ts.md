---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/devices/web-hid.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.631690+00:00
---

# cartridges/jambox/web/src/mappings/devices/web-hid.ts

```ts
/**
 * D-C.2 Web HID device adapter.
 *
 * Used for devices that need HID access (e.g. Push 3 SysEx-style messages
 * that bypass Web MIDI, certain Launchpad Pro features).
 *
 * Hard rule: only emits DeviceEvent — never jam.* cells directly.
 *
 * Note: Web HID is gated behind a user gesture. Callers must invoke
 * requestWebHidAccess() from within a click handler.
 */

import type { DeviceEvent } from '../router';

export type WebHidDeviceListener = (event: DeviceEvent, deviceName: string) => void;

export interface WebHidAdapterOptions {
  /** HID usage filter (same format as navigator.hid.requestDevice). */
  filters?: HIDDeviceFilter[];
  onEvent: WebHidDeviceListener;
  onDeviceConnect?: (deviceName: string) => void;
  onDeviceDisconnect?: (deviceName: string) => void;
}

type HIDDeviceFilter = { vendorId?: number; productId?: number; usagePage?: number; usage?: number };

// Minimal local stubs for Web HID types (not yet in standard lib; runtime guards protect actual use)
interface HIDDevice {
  productName: string;
  productId: number;
  opened: boolean;
  open(): Promise<void>;
  addEventListener(type: string, listener: EventListener): void;
  removeEventListener(type: string, listener: EventListener): void;
}
interface HIDConnectionEvent extends Event {
  device: HIDDevice;
}
interface HIDInputReportEvent extends Event {
  reportId: number;
  data: DataView;
}

/**
 * Request HID access (requires a user gesture — call from a button click).
 * Returns null if Web HID is unavailable.
 */
export async function requestWebHidAccess(
  filters: HIDDeviceFilter[] = [],
): Promise<HIDDevice[] | null> {
  const nav = navigator as Navigator & { hid?: { requestDevice: (opts: { filters: HIDDeviceFilter[] }) => Promise<HIDDevice[]> } };
  if (!nav.hid) return null;
  try {
    return await nav.hid.requestDevice({ filters });
  } catch {
    return null;
  }
}

/**
 * Attach to already-granted HID devices and emit normalised DeviceEvents.
 * Returns a cleanup function.
 */
export async function attachWebHidAdapter(
  opts: WebHidAdapterOptions,
): Promise<{ devices: string[]; detach: () => void } | null> {
  const nav = navigator as Navigator & { hid?: { getDevices: () => Promise<HIDDevice[]>; addEventListener: (ev: string, cb: (e: HIDConnectionEvent) => void) => void; removeEventListener: (ev: string, cb: (e: HIDConnectionEvent) => void) => void } };
  if (!nav.hid) return null;

  const existingDevices = await nav.hid.getDevices();
  const devices: string[] = [];
  const detachFns: Array<() => void> = [];

  const wireDevice = async (device: HIDDevice) => {
    const name = device.productName || `HID-${device.productId}`;
    if (devices.includes(name)) return;
    devices.push(name);
    if (!device.opened) { await device.open(); }
    opts.onDeviceConnect?.(name);

    const inputHandler = (e: HIDInputReportEvent) => {
      // Generic HID: interpret first byte as selector, second byte as value
      const view = new DataView(e.data.buffer);
      const selector = e.reportId;
      const value = view.byteLength > 0 ? view.getUint8(0) / 255 : 0;
      opts.onEvent({
        kind: 'knob',
        selector,
        value,
        deviceName: name,
        ts: Date.now(),
      }, name);
    };

    device.addEventListener('inputreport', inputHandler as EventListener);
    detachFns.push(() => device.removeEventListener('inputreport', inputHandler as EventListener));
  };

  for (const device of existingDevices) { await wireDevice(device); }

  const connectHandler = async (e: HIDConnectionEvent) => {
    await wireDevice(e.device);
  };
  const disconnectHandler = (e: HIDConnectionEvent) => {
    const name = e.device.productName || `HID-${e.device.productId}`;
    opts.onDeviceDisconnect?.(name);
  };

  nav.hid.addEventListener('connect', connectHandler);
  nav.hid.addEventListener('disconnect', disconnectHandler);
  detachFns.push(() => {
    nav.hid!.removeEventListener('connect', connectHandler);
    nav.hid!.removeEventListener('disconnect', disconnectHandler);
  });

  return {
    devices,
    detach: () => { for (const fn of detachFns) fn(); },
  };
}

```
