---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/player-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.842500+00:00
---

# archive/apps-mud/src/room-actor/player-registry.ts

```ts
/**
 * Player registry — atom-backed add/remove/lookup helpers for the
 * facade. Pulled out to keep `room-actor-facade.ts` under the 220-LOC
 * ceiling.
 *
 * Functions take a `RoomAtoms` and operate via the functional
 * `@semantos/state` API. They emit `player-entered` / `player-left`
 * events through the room's bus on add/remove.
 */

import { get, set } from '@semantos/state';

import type { RoomAtoms } from './atoms';
import type { MUDPlayer, PlayerId } from '../types';

export function addPlayer(atoms: RoomAtoms, player: MUDPlayer): void {
  const players = new Map<PlayerId, MUDPlayer>(get(atoms.playersAtom));
  players.set(player.id, player);
  set(atoms.playersAtom, players);

  const state = get(atoms.roomStateAtom);
  if (!state.occupants.includes(player.id)) {
    set(atoms.roomStateAtom, {
      ...state,
      occupants: [...state.occupants, player.id],
    });
  }
  atoms.eventsBus.emit({
    type: 'player-entered',
    roomId: atoms.roomId,
    playerId: player.id,
    message: `${player.name} enters the room.`,
  });
}

export function removePlayer(
  atoms: RoomAtoms,
  playerId: PlayerId,
): MUDPlayer | null {
  const players = new Map<PlayerId, MUDPlayer>(get(atoms.playersAtom));
  const player = players.get(playerId);
  if (!player) return null;
  players.delete(playerId);
  set(atoms.playersAtom, players);

  const state = get(atoms.roomStateAtom);
  set(atoms.roomStateAtom, {
    ...state,
    occupants: state.occupants.filter((id: PlayerId) => id !== playerId),
  });
  atoms.eventsBus.emit({
    type: 'player-left',
    roomId: atoms.roomId,
    playerId,
    message: `${player.name} leaves the room.`,
  });
  return player;
}

export function getPlayer(
  atoms: RoomAtoms,
  playerId: PlayerId,
): MUDPlayer | undefined {
  return get(atoms.playersAtom).get(playerId);
}

export function getPlayers(atoms: RoomAtoms): MUDPlayer[] {
  return [...get(atoms.playersAtom).values()];
}

export function otherPlayers(
  atoms: RoomAtoms,
  excludingId: PlayerId,
): MUDPlayer[] {
  return [...get(atoms.playersAtom).values()].filter((p) => p.id !== excludingId);
}

```
