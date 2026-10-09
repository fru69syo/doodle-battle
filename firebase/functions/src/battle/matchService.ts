import { FieldValue, type DocumentReference, type Transaction } from "firebase-admin/firestore";
import { LIMITS } from "../config";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { COL, db } from "../lib/firebase";
import type { UserProfile } from "../lib/auth";
import type { EndReason, MatchDoc, PendingActions, SideInfo, TurnDoc } from "../model";
import { chooseGhostAction } from "./ghostAi";
import { computeResults, RATING } from "./results";
import { getEngine, TIMEOUT_ACTION, type ActionId, type BattleEngine, type Side } from "./engine";

const SIDES: readonly Side[] = ["a", "b"];

export function matchRef(matchId: string): DocumentReference {
  return db().collection(COL.matches).doc(matchId);
}
function actionsRef(matchId: string): DocumentReference {
  return matchRef(matchId).collection(COL.matchPrivate).doc("actions");
}

function engineFor(match: MatchDoc): BattleEngine {
  const engine = getEngine();
  if (engine.id !== match.engineId) {
    // A deploy changed the engine while this match was running. Refuse rather
    // than resolve with different rules; the sweep will abort it.
    fail(ErrorCode.MATCH_NOT_ACTIVE, `engine changed (${match.engineId} -> ${engine.id})`);
  }
  return engine;
}

export function sideOf(match: Pick<MatchDoc, "sides">, uid: string): Side | null {
  if (match.sides.a.uid === uid) return "a";
  if (match.sides.b.uid === uid) return "b";
  return null;
}

/** Creates a new match (inside the caller's transaction, after all reads). */
export function createMatchInTx(tx: Transaction, a: SideInfo, b: SideInfo, mode: MatchDoc["mode"]): string {
  const engine = getEngine();
  const ref = db().collection(COL.matches).doc();
  const seed = Math.floor(Math.random() * 0xffffffff) >>> 0;
  const state = engine.init(
    { element: a.element, stats: a.stats, level: a.level },
    { element: b.element, stats: b.stats, level: b.level },
    seed,
  );
  const now = clock.now();
  const doc: MatchDoc = {
    mode,
    playerUids: [a.uid, b.uid].filter((u): u is string => u !== null),
    snapshotIds: [a.snapshotId, b.snapshotId],
    sides: { a, b },
    engineId: engine.id,
    seed,
    turn: 1,
    state,
    view: engine.view(state),
    submitted: { a: false, b: false },
    turnDeadlineMs: now + LIMITS.turnMs,
    timeouts: { a: 0, b: 0 },
    status: "active",
    winner: null,
    endReason: null,
    result: null,
    createdAtMs: now,
    updatedAtMs: now,
    finishedAtMs: null,
  };
  tx.set(ref, doc);
  const pending: PendingActions = { turn: 1, a: null, b: null };
  tx.set(ref.collection(COL.matchPrivate).doc("actions"), pending);
  for (const side of [a, b]) {
    if (side.uid) tx.set(db().collection(COL.users).doc(side.uid), { activeMatchId: ref.id }, { merge: true });
  }
  return ref.id;
}

interface Resolution {
  updates: Partial<MatchDoc>;
  turnDoc: TurnDoc;
  finished: boolean;
  winner: Side | "draw" | null;
}

/** Pure: resolves the current turn with the given actions. */
function resolve(
  engine: BattleEngine,
  match: MatchDoc,
  actions: Record<Side, ActionId>,
  timedOut: Record<Side, boolean>,
  now: number,
): Resolution {
  const { state, events } = engine.resolveTurn(match.state, actions.a, actions.b);
  const view = engine.view(state);
  const timeouts = {
    a: timedOut.a ? match.timeouts.a + 1 : 0,
    b: timedOut.b ? match.timeouts.b + 1 : 0,
  };
  let winner: Side | "draw" | null = view.finished ? view.winner : null;
  let endReason: EndReason | null = view.finished ? "ko" : null;

  if (!view.finished) {
    const forfeits = SIDES.filter(
      (s) => !match.sides[s].isGhost && timeouts[s] >= LIMITS.forfeitAfterTimeouts,
    );
    if (forfeits.length === 2) {
      winner = null;
      endReason = "aborted";
    } else if (forfeits.length === 1 && forfeits[0]) {
      winner = forfeits[0] === "a" ? "b" : "a";
      endReason = "forfeit_timeout";
    } else if (match.turn >= LIMITS.maxTurns) {
      const ra = view.a.hp / Math.max(1, view.a.maxHp);
      const rb = view.b.hp / Math.max(1, view.b.maxHp);
      winner = ra === rb ? "draw" : ra > rb ? "a" : "b";
      endReason = "turn_limit";
    }
  }
  const finished = endReason !== null;
  const turnDoc: TurnDoc = { turn: match.turn, actions, timedOut, events, view, resolvedAtMs: now };
  const updates: Partial<MatchDoc> = {
    state,
    view,
    timeouts,
    submitted: { a: false, b: false },
    updatedAtMs: now,
  };
  if (finished) {
    Object.assign(updates, {
      status: endReason === "aborted" ? "aborted" : "finished",
      winner,
      endReason,
      finishedAtMs: now,
    } satisfies Partial<MatchDoc>);
  } else {
    updates.turn = match.turn + 1;
    updates.turnDeadlineMs = now + LIMITS.turnMs;
  }
  return { updates, turnDoc, finished, winner };
}

/**
 * Applies a resolution inside a transaction. All reads (including the user
 * docs needed to finalise ratings) happen before any write.
 */
async function applyResolution(
  tx: Transaction,
  matchId: string,
  match: MatchDoc,
  res: Resolution,
): Promise<void> {
  const ref = matchRef(matchId);
  const humans = SIDES.filter((s) => match.sides[s].uid !== null);
  const userSnaps = res.finished
    ? await Promise.all(
        humans.map((s) => tx.get(db().collection(COL.users).doc(match.sides[s].uid ?? "-"))),
      )
    : [];

  tx.set(ref.collection(COL.turns).doc(String(match.turn)), res.turnDoc);
  const pending: PendingActions = { turn: match.turn + 1, a: null, b: null };
  tx.set(actionsRef(matchId), pending);

  if (res.finished) {
    const result = computeResults(match, res.updates.status === "aborted" ? null : res.winner);
    res.updates.result = result;
    humans.forEach((side, i) => {
      const uid = match.sides[side].uid;
      const snap = userSnaps[i];
      if (!uid || !snap) return;
      const profile = (snap.data() ?? {}) as UserProfile;
      const r = result[side];
      const upd: Record<string, unknown> = {
        rating: Math.max(RATING.floor, (profile.rating ?? RATING.initial) + r.ratingDelta),
      };
      if (r.outcome === "win") upd["onlineStats.wins"] = FieldValue.increment(1);
      if (r.outcome === "lose") upd["onlineStats.losses"] = FieldValue.increment(1);
      if (r.outcome === "draw") upd["onlineStats.draws"] = FieldValue.increment(1);
      if (profile.activeMatchId === matchId) upd.activeMatchId = null;
      if (snap.exists) tx.update(snap.ref, upd);
    });
  }
  tx.update(ref, res.updates);
}

export interface SubmitResult {
  resolved: boolean;
  status: MatchDoc["status"];
  turn: number;
}

/** Records a player's action; resolves the turn when both actions are in. */
export async function submitAction(
  matchId: string,
  uid: string,
  turn: number,
  action: ActionId,
): Promise<SubmitResult> {
  return db().runTransaction(async (tx) => {
    const mSnap = await tx.get(matchRef(matchId));
    if (!mSnap.exists) fail(ErrorCode.NOT_FOUND, "match not found");
    const match = mSnap.data() as MatchDoc;
    const side = sideOf(match, uid);
    if (!side) fail(ErrorCode.NOT_IN_MATCH, "not a player of this match");
    if (match.status !== "active") fail(ErrorCode.MATCH_NOT_ACTIVE, "match is over");
    if (turn !== match.turn) fail(ErrorCode.WRONG_TURN, `current turn is ${match.turn}`);
    const engine = engineFor(match);
    if (!engine.legalActions(match.state, side).includes(action)) {
      fail(ErrorCode.ILLEGAL_ACTION, `${action} is not available now`);
    }
    const pSnap = await tx.get(actionsRef(matchId));
    const pending = (pSnap.data() ?? { turn: match.turn, a: null, b: null }) as PendingActions;
    if (pending.turn !== match.turn) {
      pending.turn = match.turn;
      pending.a = null;
      pending.b = null;
    }
    if (pending[side] !== null) {
      // Idempotent retry of an already-recorded action.
      return { resolved: false, status: match.status, turn: match.turn };
    }
    pending[side] = action;
    const opp: Side = side === "a" ? "b" : "a";
    if (match.sides[opp].isGhost && pending[opp] === null) {
      pending[opp] = chooseGhostAction(engine, match.state, opp, {
        a: match.sides.a.element,
        b: match.sides.b.element,
      });
    }
    if (pending.a !== null && pending.b !== null) {
      const now = clock.now();
      const res = resolve(engine, match, { a: pending.a, b: pending.b }, { a: false, b: false }, now);
      await applyResolution(tx, matchId, match, res);
      return {
        resolved: true,
        status: res.updates.status ?? "active",
        turn: res.updates.turn ?? match.turn,
      };
    }
    tx.set(actionsRef(matchId), pending);
    tx.update(mSnap.ref, { [`submitted.${side}`]: true, updatedAtMs: clock.now() });
    return { resolved: false, status: match.status, turn: match.turn };
  });
}

/**
 * Lazy deadline enforcement: if the current turn's deadline (+grace) has
 * passed, fills missing actions with the timeout action and resolves.
 * Called by pollMatch (clients), submitAction callers and the minute sweep.
 * Returns true if a turn was resolved or the match was closed.
 */
export async function enforceDeadline(matchId: string): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const mSnap = await tx.get(matchRef(matchId));
    if (!mSnap.exists) return false;
    const match = mSnap.data() as MatchDoc;
    const now = clock.now();
    if (match.status !== "active" || now < match.turnDeadlineMs + LIMITS.turnGraceMs) return false;
    const engine = getEngine();
    if (engine.id !== match.engineId) {
      tx.update(mSnap.ref, {
        status: "aborted",
        endReason: "aborted",
        winner: null,
        result: computeResults(match, null),
        finishedAtMs: now,
        updatedAtMs: now,
      } satisfies Partial<MatchDoc>);
      for (const s of SIDES) {
        const uid = match.sides[s].uid;
        if (uid) tx.set(db().collection(COL.users).doc(uid), { activeMatchId: null }, { merge: true });
      }
      return true;
    }
    const pSnap = await tx.get(actionsRef(matchId));
    const pending = (pSnap.data() ?? { turn: match.turn, a: null, b: null }) as PendingActions;
    const current = pending.turn === match.turn ? pending : { turn: match.turn, a: null, b: null };
    const elements = { a: match.sides.a.element, b: match.sides.b.element };
    const pick = (s: Side): { action: ActionId; timedOut: boolean } => {
      const a = current[s];
      if (a) return { action: a, timedOut: false };
      if (match.sides[s].isGhost) return { action: chooseGhostAction(engine, match.state, s, elements), timedOut: false };
      const legal = engine.legalActions(match.state, s);
      return { action: legal.includes(TIMEOUT_ACTION) ? TIMEOUT_ACTION : (legal[0] ?? TIMEOUT_ACTION), timedOut: true };
    };
    const pa = pick("a");
    const pb = pick("b");
    const res = resolve(engine, match, { a: pa.action, b: pb.action }, { a: pa.timedOut, b: pb.timedOut }, now);
    await applyResolution(tx, matchId, match, res);
    return true;
  });
}
