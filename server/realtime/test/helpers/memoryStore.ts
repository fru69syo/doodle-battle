import { initialRated, type RatedState } from "../../src/rating";
import type { MatchSummary, Settlement } from "../../src/results";
import type { GhostPick, PlayerProfile, SnapshotRecord, Store } from "../../src/store";

/** In-memory Store with the same semantics as FirestoreStore (single-threaded "transactions"). */
export class MemoryStore implements Store {
  users = new Map<string, { consentOnline: boolean; displayName: string; rated?: RatedState }>();
  snapshots = new Map<string, SnapshotRecord>();
  rtMatches = new Map<string, Record<string, unknown>>();
  replays = new Map<string, MatchSummary & { ratingDeltas: Record<string, number> }>();
  costMode: unknown = undefined;
  failSettle = false;

  addUser(uid: string, opts: { consentOnline?: boolean; displayName?: string; rated?: Partial<RatedState> } = {}): void {
    this.users.set(uid, {
      consentOnline: opts.consentOnline ?? true,
      displayName: opts.displayName ?? `${uid}-name`,
      rated: { ...initialRated(), ...opts.rated },
    });
  }

  addSnapshot(id: string, ownerUid: string, opts: { level?: number; status?: string; ghostRating?: number | null; power?: number; agi?: number } = {}): void {
    const stat = (v: number) => ({ HP: v, SP: v, STR: v, VIT: v, DEF: v, INT: v, RES: v, DEX: v, AGI: opts.agi ?? v, LUK: v });
    this.snapshots.set(id, {
      snapshotId: id,
      ownerUid,
      status: opts.status ?? "active",
      level: opts.level ?? 20,
      ownerDisplayName: `${ownerUid}-name`,
      ghostRating: opts.ghostRating ?? null,
      display: { characterName: `${id}-chara`, imagePath: `snapshotImages/${id}/image.png` },
      data: {
        attr: "gu",
        statsLv1: stat(40),
        moves: [
          { name: "ぱんち", templateId: "strike", kind: "physical", power: opts.power ?? 150, bars: 1, castTicks: 0, cooldownTicks: 0 },
          { name: "びーむ", templateId: "blast", kind: "special", power: (opts.power ?? 150) + 20, bars: 2, castTicks: 3, cooldownTicks: 20 },
          { name: "げんき", templateId: "heal", kind: "heal", power: 200, bars: 2, castTicks: 0, cooldownTicks: 100 },
        ],
      },
    });
  }

  /**
   * A v2 (schema 2) snapshot as written by registerCharacter for Engine v3. `engine` is the
   * engine input (server-only); `trust` is the hidden verdict that must never reach clients.
   */
  addV2Snapshot(id: string, ownerUid: string, engine: Record<string, unknown>, opts: { level?: number; status?: string; ghostRating?: number | null } = {}): void {
    this.snapshots.set(id, {
      snapshotId: id,
      ownerUid,
      status: opts.status ?? "active",
      level: opts.level ?? 20,
      ownerDisplayName: `${ownerUid}-name`,
      ghostRating: opts.ghostRating ?? null,
      display: { characterName: `${id}-chara`, imagePath: `snapshotImages/${id}/image.png` },
      data: { schema: 2, name: `${id}-chara`, level: opts.level ?? 20, engine },
    });
  }

  loadPlayer(uid: string): Promise<PlayerProfile | null> {
    const u = this.users.get(uid);
    return Promise.resolve(u ? { uid, consentOnline: u.consentOnline, displayName: u.displayName, rated: { ...(u.rated ?? initialRated()) } } : null);
  }

  loadSnapshot(id: string): Promise<SnapshotRecord | null> {
    return Promise.resolve(this.snapshots.get(id) ?? null);
  }

  pickGhost(args: { rating: number; excludeUid: string; excludeSnapshotIds: readonly string[] }): Promise<GhostPick | null> {
    const pool = [...this.snapshots.values()].filter((s) => s.status === "active" && s.ownerUid !== args.excludeUid && !args.excludeSnapshotIds.includes(s.snapshotId));
    pool.sort((a, b) => Math.abs((a.ghostRating ?? 1000) - args.rating) - Math.abs((b.ghostRating ?? 1000) - args.rating));
    const p = pool[0];
    return Promise.resolve(p ? { source: p, rating: p.ghostRating ?? 1000, displayName: p.ownerDisplayName } : null);
  }

  async settleMatch(summary: MatchSummary, settle: (rated: Map<string, RatedState>) => Settlement): Promise<Settlement> {
    await Promise.resolve();
    if (this.failSettle) throw new Error("firestore unavailable");
    const rated = new Map<string, RatedState>();
    for (const s of summary.sides) if (s.uid && !s.isGhost) rated.set(s.uid, { ...(this.users.get(s.uid)?.rated ?? initialRated()) });
    const result = settle(rated);
    for (const p of result.players) {
      if (!p.next) continue;
      const u = this.users.get(p.uid);
      if (u) u.rated = p.next;
      const snap = this.snapshots.get(summary.sides[p.side].snapshotId);
      if (snap) snap.ghostRating = p.next.rating;
    }
    this.rtMatches.set(summary.matchId, { mode: summary.mode, reason: summary.reason, winner: summary.winner, players: result.players.map((p) => p.uid) });
    this.replays.set(summary.matchId, { ...summary, ratingDeltas: Object.fromEntries(result.players.map((p) => [p.uid, p.ratingDelta])) });
    return result;
  }

  readCostMode(): Promise<unknown> {
    return Promise.resolve(this.costMode);
  }
}
