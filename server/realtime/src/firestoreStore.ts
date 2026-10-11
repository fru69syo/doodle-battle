/**
 * Firestore implementation of Store (Admin SDK; security rules do not apply to the server).
 *
 * Documents (docs/BACKEND.md §4, §16):
 *   users/{uid}            consent.online, displayName.text, rated {rating, games, best, dayKey, dayMatches}
 *   snapshots/{id}         registered characters (written by registerCharacter); the server adds ghostRating
 *   rtMatches/{matchId}    match summary, readable by the players (no rating numbers)
 *   replays/{matchId}      seed + input log for audits/replays, server-only, TTL `expireAt` (30 days)
 *   config/costMode        written by the kill switch
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";
import { parseRated, type RatedState } from "./rating";
import type { MatchSummary, Settlement } from "./results";
import type { GhostPick, PlayerProfile, SnapshotRecord, Store } from "./store";

export const COL = {
  users: "users",
  snapshots: "snapshots",
  rtMatches: "rtMatches",
  replays: "replays",
  config: "config",
} as const;

const REPLAY_TTL_MS = 30 * 86_400_000;
const GHOST_WINDOW = 200;

function str(v: unknown, def = ""): string {
  return typeof v === "string" ? v : def;
}

function num(v: unknown, def: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : def;
}

export function snapshotFromDoc(id: string, d: Record<string, unknown>): SnapshotRecord {
  const ownerUid = typeof d.ownerUid === "string" ? d.ownerUid : null;
  return {
    snapshotId: id,
    ownerUid,
    status: str(d.status, "unknown"),
    level: Math.trunc(num(d.level, 1)),
    ownerDisplayName: str(d.ownerDisplayName),
    ghostRating: typeof d.ghostRating === "number" ? d.ghostRating : null,
    display: {
      characterName: str(d.name),
      imagePath: typeof d.imagePath === "string" ? d.imagePath : null,
      ...(d.rig !== undefined ? { rig: d.rig } : {}),
    },
    data: d,
  };
}

export class FirestoreStore implements Store {
  constructor(
    private readonly db: Firestore,
    private readonly random: () => number = Math.random,
  ) {}

  async loadPlayer(uid: string): Promise<PlayerProfile | null> {
    const snap = await this.db.collection(COL.users).doc(uid).get();
    if (!snap.exists) return null;
    const d = snap.data() ?? {};
    const consent = (d.consent ?? {}) as Record<string, unknown>;
    const dn = (d.displayName ?? {}) as Record<string, unknown>;
    return { uid, consentOnline: consent.online === true, displayName: str(dn.text), rated: parseRated(d.rated) };
  }

  async loadSnapshot(snapshotId: string): Promise<SnapshotRecord | null> {
    const s = await this.db.collection(COL.snapshots).doc(snapshotId).get();
    return s.exists ? snapshotFromDoc(s.id, s.data() ?? {}) : null;
  }

  async pickGhost(args: { rating: number; excludeUid: string; excludeSnapshotIds: readonly string[] }): Promise<GhostPick | null> {
    const exclude = new Set(args.excludeSnapshotIds);
    const usable = (docs: { id: string; data(): Record<string, unknown> }[]) =>
      docs.map((x) => snapshotFromDoc(x.id, x.data())).filter((s) => s.ownerUid !== args.excludeUid && !exclude.has(s.snapshotId) && s.status === "active");

    // 1) Characters whose owner's rating is close (index: status ASC, ghostRating ASC).
    const near = await this.db
      .collection(COL.snapshots)
      .where("status", "==", "active")
      .where("ghostRating", ">=", args.rating - GHOST_WINDOW)
      .where("ghostRating", "<=", args.rating + GHOST_WINDOW)
      .limit(30)
      .get();
    let pool = usable(near.docs);
    // 2) Otherwise any active character, at a random position (randomKey in [0,1)).
    if (pool.length === 0) {
      const start = this.random();
      const q = this.db.collection(COL.snapshots).where("status", "==", "active").orderBy("randomKey");
      pool = usable((await q.startAt(start).limit(10).get()).docs);
      if (pool.length === 0) pool = usable((await q.limit(10).get()).docs);
    }
    if (pool.length === 0) return null;
    const pick = pool[Math.floor(this.random() * pool.length)] ?? pool[0];
    if (!pick) return null;
    return { source: pick, rating: pick.ghostRating ?? 1000, displayName: pick.ownerDisplayName };
  }

  async settleMatch(summary: MatchSummary, settleFn: (rated: Map<string, RatedState>) => Settlement): Promise<Settlement> {
    const humans = summary.sides.filter((s) => !s.isGhost && s.uid !== null).map((s) => s.uid as string);
    return this.db.runTransaction(async (tx) => {
      const refs = humans.map((uid) => this.db.collection(COL.users).doc(uid));
      const docs = refs.length > 0 ? await tx.getAll(...refs) : [];
      const rated = new Map<string, RatedState>();
      docs.forEach((d, i) => {
        const uid = humans[i];
        if (uid !== undefined) rated.set(uid, parseRated(d.data()?.rated));
      });
      const result = settleFn(rated);

      for (const p of result.players) {
        if (!p.next) continue;
        tx.set(this.db.collection(COL.users).doc(p.uid), { rated: p.next, ratedUpdatedAtMs: summary.endedAtMs }, { merge: true });
        const snapId = summary.sides[p.side].snapshotId;
        // The child's character can now appear as a ghost for others of a similar rating.
        tx.set(this.db.collection(COL.snapshots).doc(snapId), { ghostRating: p.next.rating }, { merge: true });
      }

      const side = (i: 0 | 1) => {
        const s = summary.sides[i];
        const p = result.players.find((x) => x.side === i);
        return { snapshotId: s.snapshotId, isGhost: s.isGhost, outcome: p?.outcome ?? null, xp: p?.xp ?? 0 };
      };
      tx.set(this.db.collection(COL.rtMatches).doc(summary.matchId), {
        mode: summary.mode,
        playerUids: humans,
        // deleteMyData also removes matches where a deleted child's character was the ghost.
        snapshotIds: summary.sides.map((s) => s.snapshotId),
        sides: { a: side(0), b: side(1) },
        winner: summary.winner === null ? null : summary.winner === 0 ? "a" : "b",
        reason: summary.reason,
        ticks: summary.ticks,
        engineId: summary.engineId,
        startedAtMs: summary.startedAtMs,
        endedAtMs: summary.endedAtMs,
      });
      tx.set(this.db.collection(COL.replays).doc(summary.matchId), {
        matchId: summary.matchId,
        engineId: summary.engineId,
        seed: summary.seed,
        ticks: summary.ticks,
        sides: summary.sides,
        inputs: summary.inputs,
        finalHash: summary.finalHash,
        winner: summary.winner,
        reason: summary.reason,
        forfeitSide: summary.forfeitSide,
        ratingDeltas: Object.fromEntries(result.players.map((p) => [p.uid, p.ratingDelta])),
        createdAt: FieldValue.serverTimestamp(),
        expireAt: Timestamp.fromMillis(summary.endedAtMs + REPLAY_TTL_MS),
      });
      return result;
    });
  }

  async readCostMode(): Promise<unknown> {
    const s = await this.db.collection(COL.config).doc("costMode").get();
    return s.exists ? s.data()?.mode : undefined;
  }
}
