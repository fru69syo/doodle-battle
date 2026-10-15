/**
 * One server-authoritative match: drives the engine at 10 Hz and owns everything time-based
 * that the children experience (GAME_DESIGN_V2 §6.3, §6.7). Stackable gauge bars (spec v4):
 *
 *   さきどり    a picked move is kept and used in the tick enough bars are there (and it is off
 *              cooldown); a newer `select` replaces it. A move costing more than the side's max
 *              bars is refused (`unusable`). There is no decision timer: an idle child just caps
 *              at max bars.
 *   ghosts     the tiered AI ("normal", 1 s thinking time) plays the ghost
 *   おまかせ   the child's switch (`omakase` message): the server picks a random move the side
 *              can afford within its max bars, waits until the bars are there, uses it, picks
 *              again; switching it off gives the child full control again
 *   disconnect after 10 s away the AI ("normal") plays for the child; after 30 s the child loses
 *              (XP 0); if both sides are away for 30 s the match is aborted (no rating change)
 *
 * The match never touches the network or Firestore itself: it calls `send` callbacks and
 * reports its summary to the hub, which keeps it unit-testable tick by tick.
 */
import type { AiTier, BattleEvent, BattleSim, Side } from "./engine";
import { sideName, type FighterInfo, type ServerMsg } from "./protocol";
import type { EndReason, InputRecord, MatchSummary } from "./results";

export interface MatchTiming {
  aiThinkTicks: number;
  autoAfterDisconnectTicks: number;
  forfeitAfterDisconnectTicks: number;
  snapEveryTicks: number;
}

export const DEFAULT_TIMING: MatchTiming = {
  aiThinkTicks: 10,
  autoAfterDisconnectTicks: 100,
  forfeitAfterDisconnectTicks: 300,
  snapEveryTicks: 5,
};

export type Send = (msg: ServerMsg) => void;

export interface MatchSide {
  kind: "player" | "ghost";
  uid: string | null;
  snapshotId: string;
  level: number;
  rating: number;
  info: FighterInfo;
  aiTier?: AiTier;
}

interface SideState extends MatchSide {
  send: Send | null;
  queued: number | null;
  queuedSeq: number;
  lastSeq: number;
  /** The child's おまかせ switch (protocol rev 2). */
  omakase: boolean;
  /** Who chose for this side in the last tick (an AI plan is dropped when it changes). */
  control: InputRecord["src"] | null;
  disconnectedAt: number | null;
}

const MAX_TAIL_EVENTS = 40;

export class Match {
  private readonly s: [SideState, SideState];
  private readonly log: { seq: number; tick: number; events: BattleEvent[] }[] = [];
  private readonly inputs: InputRecord[] = [];
  private seq = 0;
  private endReason: EndReason | null = null;
  private forfeitSide: Side | null = null;
  private abortedWinner: Side | null = null;

  constructor(
    readonly matchId: string,
    readonly mode: "pvp" | "ghost",
    private readonly sim: BattleSim,
    private readonly engineMeta: { engineId: string; tickHz: number },
    sides: [MatchSide, MatchSide],
    readonly seed: number,
    readonly startedAtMs: number,
    private readonly timing: MatchTiming = DEFAULT_TIMING,
  ) {
    const mk = (x: MatchSide): SideState => ({ ...x, send: null, queued: null, queuedSeq: -1, lastSeq: -1, omakase: false, control: null, disconnectedAt: null });
    this.s = [mk(sides[0]), mk(sides[1])];
  }

  get tick(): number {
    return this.sim.tick;
  }

  get done(): boolean {
    return this.endReason !== null;
  }

  sideOf(uid: string): Side | null {
    if (this.s[0].uid === uid) return 0;
    if (this.s[1].uid === uid) return 1;
    return null;
  }

  humanUids(): string[] {
    return this.s.filter((x) => x.kind === "player" && x.uid !== null).map((x) => x.uid as string);
  }

  /** (Re)attaches a player's connection; sends `match`, the latest `snap` and missed events. */
  attach(side: Side, send: Send, lastSeq?: number): void {
    const st = this.s[side];
    const resumed = st.send !== null || st.disconnectedAt !== null || lastSeq !== undefined;
    st.send = send;
    st.disconnectedAt = null;
    send(this.matchMessage(side, resumed));
    if (lastSeq !== undefined) {
      for (const e of this.log) if (e.seq > lastSeq) send({ t: "ev", seq: e.seq, tick: e.tick, events: e.events });
    }
    send(this.snapMessage());
  }

  detach(side: Side): void {
    const st = this.s[side];
    if (st.kind !== "player") return;
    st.send = null;
    st.disconnectedAt ??= this.sim.tick;
    st.queued = null;
  }

  /** A child picked a move (slot). Returns the ack for that child only (the foe never sees it). */
  select(side: Side, seq: number, slot: number): ServerMsg {
    const st = this.s[side];
    if (this.done || seq <= st.lastSeq) return { t: "sel", seq, slot, accepted: false, queued: false, reason: "stale" };
    st.lastSeq = seq;
    // A move that can never be paid for (cost > max bars) or does not exist.
    if (!this.sim.canQueue(side, slot)) return { t: "sel", seq, slot, accepted: false, queued: false, reason: "unusable" };
    st.queued = slot;
    st.queuedSeq = seq;
    // queued=true: kept until enough bars are there (さきどり); false: used in the next tick.
    return { t: "sel", seq, slot, accepted: true, queued: !this.sim.canUse(side, slot) };
  }

  /**
   * The child's おまかせ switch. On: the server picks a random affordable move for this side
   * and uses it once its bars are there, then picks again; a pending さきどり is dropped.
   * Off: full control again. Private ack (the opponent never learns about it).
   */
  setOmakase(side: Side, on: boolean): ServerMsg {
    const st = this.s[side];
    if (st.kind === "player") {
      st.omakase = on;
      if (on) st.queued = null;
    }
    return { t: "omakase", on: st.omakase };
  }

  private aiControlled(st: SideState): boolean {
    if (st.kind === "ghost") return true;
    return st.disconnectedAt !== null && this.sim.tick - st.disconnectedAt >= this.timing.autoAfterDisconnectTicks;
  }

  /** Advances one tick (100 ms). */
  advance(): void {
    if (this.done) return;
    if (this.checkDisconnects()) return;

    const inputs: [number | null, number | null] = [null, null];
    const srcs: [InputRecord["src"] | null, InputRecord["src"] | null] = [null, null];
    for (const side of [0, 1] as const) {
      const st = this.s[side];
      const control: InputRecord["src"] = this.aiControlled(st) ? "ai" : st.omakase ? "omakase" : "player";
      if (control !== st.control) {
        this.sim.clearPlan(side);
        st.control = control;
      }
      if (control === "ai") {
        inputs[side] = this.sim.aiInput(side, st.aiTier ?? "normal", this.timing.aiThinkTicks);
      } else if (control === "omakase") {
        inputs[side] = this.sim.omakaseInput(side);
      } else {
        inputs[side] = st.queued;
      }
      if (inputs[side] !== null) srcs[side] = control;
    }

    const res = this.sim.step(inputs);
    const events = res.events;
    for (const side of [0, 1] as const) {
      const st = this.s[side];
      const src = srcs[side];
      const slot = inputs[side];
      if (res.acted[side] && src !== null && slot !== null) {
        this.inputs.push({ tick: this.sim.tick, side, slot, src });
        if (src === "player") st.queued = null;
      }
    }

    if (events.length > 0) {
      this.seq++;
      this.log.push({ seq: this.seq, tick: this.sim.tick, events });
      this.broadcast({ t: "ev", seq: this.seq, tick: this.sim.tick, events });
    }
    if (this.sim.finished) {
      this.endReason = this.sim.endReason ?? "ko";
      this.broadcast(this.snapMessage());
      return;
    }
    if (this.sim.tick % this.timing.snapEveryTicks === 0) this.broadcast(this.snapMessage());
  }

  /** Returns true when the match ended because of disconnections. */
  private checkDisconnects(): boolean {
    const away = (st: SideState) =>
      st.kind === "player" && st.disconnectedAt !== null && this.sim.tick - st.disconnectedAt >= this.timing.forfeitAfterDisconnectTicks;
    const a = away(this.s[0]);
    const b = away(this.s[1]);
    if (a && b) {
      this.endReason = "aborted";
      return true;
    }
    if (a || b) {
      const loser: Side = a ? 0 : 1;
      this.forfeitSide = loser;
      this.abortedWinner = loser === 0 ? 1 : 0;
      this.endReason = "forfeit";
      this.seq++;
      const ev: BattleEvent[] = [{ tick: this.sim.tick, type: "forfeit", side: loser }];
      this.log.push({ seq: this.seq, tick: this.sim.tick, events: ev });
      this.broadcast({ t: "ev", seq: this.seq, tick: this.sim.tick, events: ev });
      return true;
    }
    return false;
  }

  /** Ends the match without a result (server shutdown, ownership lost). */
  abort(): void {
    if (!this.done) this.endReason = "aborted";
  }

  get winner(): Side | null {
    if (this.endReason === "aborted") return null;
    if (this.endReason === "forfeit") return this.abortedWinner;
    return this.sim.winner;
  }

  summary(endedAtMs: number): MatchSummary {
    const sideSummary = (st: SideState) => ({ uid: st.uid, snapshotId: st.snapshotId, level: st.level, isGhost: st.kind === "ghost", ratingAtStart: st.rating });
    const tail: BattleEvent[] = [];
    for (let i = this.log.length - 1; i >= 0 && tail.length < MAX_TAIL_EVENTS; i--) tail.unshift(...(this.log[i]?.events ?? []));
    return {
      matchId: this.matchId,
      mode: this.mode,
      engineId: this.engineMeta.engineId,
      seed: this.seed,
      startedAtMs: this.startedAtMs,
      endedAtMs,
      ticks: this.sim.tick,
      sides: [sideSummary(this.s[0]), sideSummary(this.s[1])],
      winner: this.winner,
      reason: this.endReason ?? "aborted",
      forfeitSide: this.forfeitSide,
      inputs: [...this.inputs],
      finalHash: this.sim.stateHash(),
      tailEvents: tail.slice(-MAX_TAIL_EVENTS),
    };
  }

  sendTo(side: Side, msg: ServerMsg): void {
    this.s[side].send?.(msg);
  }

  private broadcast(msg: ServerMsg): void {
    for (const st of this.s) st.send?.(msg);
  }

  private matchMessage(side: Side, resumed: boolean): ServerMsg {
    return {
      t: "match",
      matchId: this.matchId,
      you: sideName(side),
      tickHz: this.engineMeta.tickHz,
      a: this.s[0].info,
      b: this.s[1].info,
      resumed,
    };
  }

  private snapMessage(): ServerMsg {
    return { t: "snap", tick: this.sim.tick, a: this.sim.view(0), b: this.sim.view(1), hash: this.sim.stateHash() };
  }
}
