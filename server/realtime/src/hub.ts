/**
 * The hub ties everything together inside the single Cloud Run instance:
 * live connections (one per uid), the matchmaking queue, running matches, settlement.
 *
 * It is driven by `tick()` every 100 ms (see loop.ts) and by the connection layer (server.ts).
 * Time and randomness are injected so that tests can run whole matches in milliseconds.
 */
import { randomBytes, randomInt } from "node:crypto";
import type { CostModeSource } from "./costMode";
import { UnsupportedFighterError, type BattleEngine, type FighterSetup, type Side } from "./engine";
import type { Logger } from "./log";
import { DEFAULT_TIMING, Match, type MatchSide, type MatchTiming, type Send } from "./match";
import { Matchmaker, type QueueEntry } from "./matchmaker";
import { PROTOCOL_REVISION, PROTOCOL_VERSION, type ErrorCode, type FighterInfo, type ServerMsg } from "./protocol";
import { badgeFor, RATED_SYNC_LEVEL, RATED_UNLOCK_LEVEL, initialRated, type RatedState } from "./rating";
import { settle, type MatchSummary, type Settlement } from "./results";
import type { PlayerProfile, SnapshotRecord, Store } from "./store";

export interface Conn {
  readonly id: number;
  send: Send;
  /** Closes the socket (the server calls hub.disconnect afterwards). */
  close(code: number, reason: string): void;
}

export class HubError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "HubError";
  }
}

export interface HubDeps {
  engine: BattleEngine;
  store: Store;
  costMode: CostModeSource;
  log: Logger;
  now?: () => number;
  seed?: () => number;
  newId?: () => string;
  timing?: MatchTiming;
  /** Run matchmaking every N ticks (5 = twice a second). */
  matchmakingEveryTicks?: number;
  statsEveryTicks?: number;
}

interface QueuePayload {
  conn: Conn;
  snapshot: SnapshotRecord;
  setup: FighterSetup;
}

const RECENT_GHOSTS = 10;
const END_REPLAY_MS = 5 * 60_000;
export const MIRROR_GHOST_NAME = "かがみ";

export class Hub {
  private readonly conns = new Map<string, Conn>();
  private readonly profiles = new Map<string, PlayerProfile>();
  private readonly mm = new Matchmaker<QueuePayload>();
  private readonly matches = new Map<string, Match>();
  private readonly matchOf = new Map<string, string>();
  private readonly pairing = new Set<string>();
  private readonly recentGhosts = new Map<string, string[]>();
  private readonly lastEnd = new Map<string, { msg: ServerMsg; atMs: number }>();
  private readonly inflight = new Set<Promise<unknown>>();
  /** Settlement still running for these uids: a new queue entry waits for it (fresh rating). */
  private readonly settling = new Map<string, Promise<void>>();
  private readonly now: () => number;
  private readonly seed: () => number;
  private readonly newId: () => string;
  private readonly timing: MatchTiming;
  private readonly mmEvery: number;
  private readonly statsEvery: number;
  private ticks = 0;
  private maxLagMs = 0;
  private endedSinceStats = 0;
  draining = false;

  constructor(private readonly d: HubDeps) {
    this.now = d.now ?? Date.now;
    this.seed = d.seed ?? (() => randomInt(0, 2 ** 32));
    this.newId = d.newId ?? (() => randomBytes(12).toString("base64url"));
    this.timing = d.timing ?? DEFAULT_TIMING;
    this.mmEvery = d.matchmakingEveryTicks ?? 5;
    this.statsEvery = d.statsEveryTicks ?? 600;
  }

  // --- connection lifecycle ---------------------------------------------------------------------

  /** Called after the hello handshake verified the tokens. Throws HubError (e.g. no consent). */
  async connect(uid: string, conn: Conn, lastSeq?: number): Promise<void> {
    if (this.draining) throw new HubError("DRAINING", "server is restarting");
    const profile = await this.d.store.loadPlayer(uid);
    if (!profile?.consentOnline) throw new HubError("CONSENT_REQUIRED", "online play not allowed by a parent");
    this.profiles.set(uid, profile);

    const old = this.conns.get(uid);
    this.conns.set(uid, conn);
    if (old && old.id !== conn.id) {
      // A queue entry belongs to the old socket; the app re-sends `queue` after reconnecting.
      this.mm.remove(uid);
      this.pairing.delete(uid);
      old.send({ t: "bye", reason: "replaced", reconnect: false });
      old.close(4409, "replaced");
    }
    const matchId = this.matchOf.get(uid);
    conn.send({ t: "welcome", proto: PROTOCOL_VERSION, rev: PROTOCOL_REVISION, serverTimeMs: this.now(), inMatch: matchId !== undefined });
    const match = matchId ? this.matches.get(matchId) : undefined;
    const side = match?.sideOf(uid);
    if (match && side !== null && side !== undefined) {
      match.attach(side, conn.send, lastSeq ?? 0);
      return;
    }
    // The match ended while the child was away: show the result they missed.
    const end = this.lastEnd.get(uid);
    if (end && lastSeq !== undefined && this.now() - end.atMs < END_REPLAY_MS) conn.send(end.msg);
  }

  disconnect(uid: string, conn: Conn): void {
    if (this.conns.get(uid)?.id !== conn.id) return; // already replaced by a newer connection
    this.conns.delete(uid);
    this.mm.remove(uid);
    this.pairing.delete(uid);
    const match = this.matchOf.get(uid);
    const m = match ? this.matches.get(match) : undefined;
    const side = m?.sideOf(uid);
    if (m && side !== null && side !== undefined) m.detach(side);
  }

  isBusy(uid: string): boolean {
    return this.matchOf.has(uid) || this.mm.has(uid) || this.pairing.has(uid);
  }

  // --- messages ---------------------------------------------------------------------------------

  async queue(uid: string, conn: Conn, snapshotId: string): Promise<void> {
    if (this.draining) throw new HubError("DRAINING", "server is restarting");
    if (this.matchOf.has(uid)) throw new HubError("ALREADY_IN_MATCH", "finish the current match first");
    if (this.mm.has(uid) || this.pairing.has(uid)) {
      conn.send({ t: "queued", snapshotId });
      return;
    }
    await this.settling.get(uid);
    const snap = await this.d.store.loadSnapshot(snapshotId);
    if (snap?.status !== "active") throw new HubError("NOT_FOUND", "snapshot not found or not active");
    if (snap.ownerUid !== uid) throw new HubError("NOT_OWNER", "not your character");
    if (snap.level < RATED_UNLOCK_LEVEL) throw new HubError("LEVEL_TOO_LOW", `rated play unlocks at Lv${RATED_UNLOCK_LEVEL}`);
    let setup: FighterSetup;
    try {
      setup = this.d.engine.ratedFighter(snap, RATED_SYNC_LEVEL);
    } catch (err) {
      // e.g. a v1 snapshot under Engine v3: the app registers the character again.
      if (err instanceof UnsupportedFighterError) throw new HubError("NOT_FOUND", err.message);
      throw err;
    }
    if (this.conns.get(uid)?.id !== conn.id || this.matchOf.has(uid)) return; // left while loading
    const profile = this.profiles.get(uid);
    this.mm.add({ uid, rating: profile?.rated.rating ?? initialRated().rating, joinedAtMs: this.now(), payload: { conn, snapshot: snap, setup } });
    conn.send({ t: "queued", snapshotId });
  }

  cancel(uid: string, conn: Conn): void {
    this.mm.remove(uid);
    this.pairing.delete(uid);
    conn.send({ t: "cancelled" });
  }

  select(uid: string, conn: Conn, seq: number, slot: number): void {
    const id = this.matchOf.get(uid);
    const m = id ? this.matches.get(id) : undefined;
    const side = m?.sideOf(uid);
    if (!m || side === null || side === undefined) {
      conn.send({ t: "error", code: "NOT_IN_MATCH" });
      return;
    }
    conn.send(m.select(side, seq, slot));
  }

  /** The child's おまかせ switch (protocol rev 2). */
  omakase(uid: string, conn: Conn, on: boolean): void {
    const id = this.matchOf.get(uid);
    const m = id ? this.matches.get(id) : undefined;
    const side = m?.sideOf(uid);
    if (!m || side === null || side === undefined) {
      conn.send({ t: "error", code: "NOT_IN_MATCH" });
      return;
    }
    conn.send(m.setOmakase(side, on));
  }

  // --- the 10 Hz heartbeat ------------------------------------------------------------------------

  tick(): void {
    this.ticks++;
    for (const m of [...this.matches.values()]) {
      try {
        m.advance();
      } catch (err) {
        this.d.log.error("match advance failed; aborting match", { matchId: m.matchId, err });
        m.abort();
      }
      if (m.done) this.finish(m);
    }
    if (this.ticks % this.mmEvery === 0) this.runMatchmaking();
    if (this.ticks % this.statsEvery === 0) this.logStats();
  }

  noteTickLag(ms: number): void {
    if (this.matches.size > 0 && ms > this.maxLagMs) this.maxLagMs = ms;
  }

  hasWork(): boolean {
    return this.conns.size > 0 || this.matches.size > 0 || this.inflight.size > 0;
  }

  stats(): { connections: number; queued: number; matches: number } {
    return { connections: this.conns.size, queued: this.mm.size + this.pairing.size, matches: this.matches.size };
  }

  private logStats(): void {
    const s = this.stats();
    if (s.connections === 0 && s.matches === 0 && this.endedSinceStats === 0) return;
    this.d.log.info("stats", { event: "stats", ...s, maxTickLagMs: this.maxLagMs, matchesEnded: this.endedSinceStats, costMode: this.d.costMode.current().mode });
    this.maxLagMs = 0;
    this.endedSinceStats = 0;
  }

  private runMatchmaking(): void {
    if (this.mm.size === 0) return;
    const flags = this.d.costMode.current().flags;
    for (const action of this.mm.run(this.now(), flags)) {
      if (action.kind === "pvp") this.startPvp(action.a, action.b);
      else this.track(this.startGhost(action.entry));
    }
  }

  private track(p: Promise<unknown>): void {
    this.inflight.add(p);
    void p.finally(() => this.inflight.delete(p));
  }

  // --- match creation -----------------------------------------------------------------------------

  private humanSide(entry: QueueEntry<QueuePayload>): { side: MatchSide; setup: FighterSetup } {
    const profile = this.profiles.get(entry.uid);
    const rated = profile?.rated ?? initialRated();
    const snap = entry.payload.snapshot;
    return {
      side: {
        kind: "player",
        uid: entry.uid,
        snapshotId: snap.snapshotId,
        level: snap.level,
        rating: rated.rating,
        info: this.info(snap, entry.payload.setup, profile?.displayName ?? "", badgeFor(rated.best), false),
      },
      setup: entry.payload.setup,
    };
  }

  private info(src: Pick<SnapshotRecord, "snapshotId" | "display">, setup: FighterSetup, displayName: string, badge: FighterInfo["badge"], isGhost: boolean): FighterInfo {
    return {
      // The public document id (reports, SPEC §9.4). Never anything derived from engine data.
      snapshotId: src.snapshotId,
      displayName,
      characterName: src.display.characterName,
      imagePath: src.display.imagePath,
      ...(src.display.rig !== undefined ? { rig: src.display.rig } : {}),
      attr: setup.attr,
      // Only the public part of each move (engines may carry more fields).
      moves: setup.moves.map((m) => ({ slot: m.slot, name: m.name, templateId: m.templateId, attr: m.attr, spCost: m.spCost })),
      maxHp: setup.maxHp,
      level: RATED_SYNC_LEVEL,
      badge,
      isGhost,
    };
  }

  private startPvp(a: QueueEntry<QueuePayload>, b: QueueEntry<QueuePayload>): void {
    const A = this.humanSide(a);
    const B = this.humanSide(b);
    this.mm.notePair(a.uid, b.uid, this.now());
    this.create("pvp", [A.side, B.side], [A.setup, B.setup]);
  }

  private async startGhost(entry: QueueEntry<QueuePayload>): Promise<void> {
    const uid = entry.uid;
    this.pairing.add(uid);
    const recent = this.recentGhosts.get(uid) ?? [];
    let ghost: MatchSide | null = null;
    let ghostSetup: FighterSetup | null = null;
    try {
      const pick = await this.d.store.pickGhost({ rating: entry.rating, excludeUid: uid, excludeSnapshotIds: [entry.payload.snapshot.snapshotId, ...recent] });
      if (pick) {
        ghostSetup = this.d.engine.ratedFighter(pick.source, RATED_SYNC_LEVEL);
        ghost = {
          kind: "ghost",
          uid: null,
          snapshotId: pick.source.snapshotId,
          level: pick.source.level,
          rating: pick.rating,
          aiTier: "normal",
          info: this.info(pick.source, ghostSetup, pick.displayName, badgeFor(pick.rating), true),
        };
      }
    } catch (err) {
      this.d.log.warn("ghost pick failed; using mirror", { err });
    }
    // Still waiting? (the child may have cancelled or disconnected meanwhile)
    if (!this.pairing.delete(uid) || this.conns.get(uid)?.id !== entry.payload.conn.id || this.draining) return;
    const me = this.humanSide(entry);
    if (!ghost || !ghostSetup) {
      // No other registered character yet (e.g. right after launch): fight a mirror image.
      ghostSetup = entry.payload.setup;
      ghost = { ...me.side, kind: "ghost", uid: null, aiTier: "normal", info: { ...me.side.info, displayName: MIRROR_GHOST_NAME, isGhost: true } };
    } else {
      this.recentGhosts.set(uid, [ghost.snapshotId, ...recent].slice(0, RECENT_GHOSTS));
    }
    this.create("ghost", [me.side, ghost], [me.setup, ghostSetup]);
  }

  private create(mode: "pvp" | "ghost", sides: [MatchSide, MatchSide], setups: [FighterSetup, FighterSetup]): void {
    const seed = this.seed() >>> 0;
    const matchId = this.newId();
    const sim = this.d.engine.createBattle(setups[0], setups[1], { seed });
    const m = new Match(matchId, mode, sim, { engineId: this.d.engine.engineId, tickHz: this.d.engine.tickHz }, sides, seed, this.now(), this.timing);
    this.matches.set(matchId, m);
    for (const side of [0, 1] as const) {
      const uid = sides[side].uid;
      if (sides[side].kind !== "player" || uid === null) continue;
      this.matchOf.set(uid, matchId);
      this.lastEnd.delete(uid);
      const conn = this.conns.get(uid);
      if (conn) m.attach(side, conn.send);
      else m.detach(side);
    }
    this.d.log.info("match started", { event: "match_start", matchId, mode, engineId: this.d.engine.engineId });
  }

  // --- settlement -----------------------------------------------------------------------------------

  private finish(m: Match): void {
    this.matches.delete(m.matchId);
    for (const uid of m.humanUids()) if (this.matchOf.get(uid) === m.matchId) this.matchOf.delete(uid);
    const summary = m.summary(this.now());
    this.endedSinceStats++;
    this.d.log.info("match ended", { event: "match_end", matchId: m.matchId, mode: summary.mode, reason: summary.reason, ticks: summary.ticks, inputs: summary.inputs.length });
    const p = this.settleAndNotify(m, summary);
    for (const uid of m.humanUids()) {
      const done = p.finally(() => {
        if (this.settling.get(uid) === done) this.settling.delete(uid);
      });
      this.settling.set(uid, done);
    }
    this.track(p);
  }

  private async settleAndNotify(m: Match, summary: MatchSummary): Promise<void> {
    let result: Settlement;
    try {
      result = await this.d.store.settleMatch(summary, (rated) => settle(summary, this.withDefaults(summary, rated)));
    } catch (err) {
      // Never leave a child without a result screen: compute it locally, persist nothing.
      this.d.log.error("settlement failed; result not saved", { matchId: summary.matchId, err });
      const local = new Map<string, RatedState>();
      for (const uid of m.humanUids()) local.set(uid, this.profiles.get(uid)?.rated ?? initialRated());
      result = settle(summary, local);
      for (const p of result.players) p.next = null;
    }
    for (const p of result.players) {
      const profile = this.profiles.get(p.uid);
      if (profile && p.next) profile.rated = p.next;
      const msg: ServerMsg = {
        t: "end",
        matchId: summary.matchId,
        winner: summary.winner === null ? null : summary.winner === 0 ? "a" : "b",
        reason: summary.reason,
        you: { outcome: p.outcome, xp: p.xp, badge: p.badge, badgeUp: p.badgeUp },
      };
      this.lastEnd.set(p.uid, { msg, atMs: this.now() });
      this.conns.get(p.uid)?.send(msg);
    }
  }

  private withDefaults(summary: MatchSummary, rated: Map<string, RatedState>): Map<string, RatedState> {
    const out = new Map(rated);
    for (const s of summary.sides) if (s.uid !== null && !s.isGhost && !out.has(s.uid)) out.set(s.uid, initialRated());
    return out;
  }

  // --- shutdown -----------------------------------------------------------------------------------

  /**
   * SIGTERM from Cloud Run (new revision, scale-in): stop taking work, abort running matches
   * without rating changes (they cannot move to another instance), tell clients to reconnect,
   * wait for Firestore writes, then let the process exit.
   */
  async shutdown(timeoutMs: number): Promise<void> {
    this.draining = true;
    for (const m of [...this.matches.values()]) {
      m.abort();
      this.finish(m);
    }
    const pending = Promise.allSettled([...this.inflight]);
    await Promise.race([pending, new Promise((r) => setTimeout(r, timeoutMs).unref())]);
    for (const [, conn] of this.conns) {
      conn.send({ t: "bye", reason: "shutdown", reconnect: true });
      conn.close(1012, "server restart");
    }
  }

  /** Test helper: wait until all async settlement/ghost work is done. */
  async idle(): Promise<void> {
    while (this.inflight.size > 0) await Promise.allSettled([...this.inflight]);
  }

  sideOfUid(uid: string): Side | null {
    const id = this.matchOf.get(uid);
    return id ? (this.matches.get(id)?.sideOf(uid) ?? null) : null;
  }
}
