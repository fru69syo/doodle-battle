/**
 * In-memory matchmaking queue (GAME_DESIGN_V2 §8, V2_INFRA §3.4).
 *
 * - Pair two children whose hidden ratings are within a band that widens while they wait:
 *   ±100, +50 every 5 s, max ±400. Both players' bands must accept the pair.
 * - The closest rating wins; ties go to whoever waited longest.
 * - The same two children are not paired again within 60 minutes (anti win-trading).
 * - After `ghostAfterSec` (20 s normally, sooner when the cost mode says so) without a partner,
 *   the child plays a ghost. In cost mode "minimal" no PvP pairs are made at all.
 *
 * Everything lives in one process (Cloud Run max-instances = 1), so no locking is needed.
 */
import type { CostFlags } from "./costMode";
import { matchBand } from "./rating";

export const SAME_PAIR_COOLDOWN_MS = 60 * 60 * 1000;

export interface QueueEntry<T = unknown> {
  uid: string;
  rating: number;
  joinedAtMs: number;
  /** Anything the caller wants back when the entry is matched. */
  payload: T;
}

export type MatchAction<T> = { kind: "pvp"; a: QueueEntry<T>; b: QueueEntry<T> } | { kind: "ghost"; entry: QueueEntry<T> };

function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

export class Matchmaker<T = unknown> {
  private readonly entries = new Map<string, QueueEntry<T>>();
  private readonly recentPairs = new Map<string, number>();

  get size(): number {
    return this.entries.size;
  }

  has(uid: string): boolean {
    return this.entries.has(uid);
  }

  get(uid: string): QueueEntry<T> | undefined {
    return this.entries.get(uid);
  }

  add(entry: QueueEntry<T>): void {
    this.entries.set(entry.uid, entry);
  }

  remove(uid: string): QueueEntry<T> | undefined {
    const e = this.entries.get(uid);
    this.entries.delete(uid);
    return e;
  }

  notePair(a: string, b: string, nowMs: number): void {
    this.recentPairs.set(pairKey(a, b), nowMs);
  }

  pairedRecently(a: string, b: string, nowMs: number): boolean {
    const at = this.recentPairs.get(pairKey(a, b));
    return at !== undefined && nowMs - at < SAME_PAIR_COOLDOWN_MS;
  }

  /** Removes and returns the entries that should start a match now. */
  run(nowMs: number, flags: CostFlags): MatchAction<T>[] {
    for (const [k, at] of this.recentPairs) if (nowMs - at >= SAME_PAIR_COOLDOWN_MS) this.recentPairs.delete(k);

    const waiting = [...this.entries.values()].sort((x, y) => x.joinedAtMs - y.joinedAtMs || (x.uid < y.uid ? -1 : 1));
    const taken = new Set<string>();
    const actions: MatchAction<T>[] = [];

    if (flags.pvp) {
      for (const e of waiting) {
        if (taken.has(e.uid)) continue;
        const bandE = matchBand((nowMs - e.joinedAtMs) / 1000);
        let best: QueueEntry<T> | undefined;
        let bestDiff = Infinity;
        for (const c of waiting) {
          if (c.uid === e.uid || taken.has(c.uid)) continue;
          if (this.pairedRecently(e.uid, c.uid, nowMs)) continue;
          const diff = Math.abs(e.rating - c.rating);
          const band = Math.min(bandE, matchBand((nowMs - c.joinedAtMs) / 1000));
          if (diff > band) continue;
          if (diff < bestDiff) {
            best = c;
            bestDiff = diff;
          }
        }
        if (best) {
          taken.add(e.uid);
          taken.add(best.uid);
          actions.push({ kind: "pvp", a: e, b: best });
        }
      }
    }

    const ghostAfterMs = flags.ghostAfterSec * 1000;
    for (const e of waiting) {
      if (taken.has(e.uid)) continue;
      if (nowMs - e.joinedAtMs >= ghostAfterMs) {
        taken.add(e.uid);
        actions.push({ kind: "ghost", entry: e });
      }
    }

    for (const uid of taken) this.entries.delete(uid);
    return actions;
  }
}
