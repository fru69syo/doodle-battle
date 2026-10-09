/**
 * Battle engine adapter.
 *
 * The server never implements battle rules itself: it calls a `BattleEngine`.
 * Today `getEngine()` returns `StubEngine` (a small, SPEC §4.1-shaped
 * placeholder). When the Battle team's TypeScript engine lands in
 * `shared/battle_engine_ts/`, `scripts/sync-shared.mjs` copies it to
 * `src/vendor/battle_engine/` and the PM wires `createSharedEngineAdapter()`
 * (see docs/BACKEND.md "Wiring the shared battle engine"). Everything else in
 * functions (matches, ghosts, timeouts) only depends on this interface.
 *
 * Contract:
 * - States and events are plain JSON (stored in Firestore as-is).
 * - `resolveTurn` is pure and deterministic: the RNG is derived from
 *   (state.seed, state.turn), never from Math.random or the clock.
 */
import { mulberry32, turnSeed } from "./rng";
import type { Element, Stats } from "../stats/statLimits";

export type Side = "a" | "b";
export const ACTION_IDS = ["tackle", "element", "guard", "special"] as const;
export type ActionId = (typeof ACTION_IDS)[number];
/** Action used when a player does not act within the turn limit (SPEC §5). */
export const TIMEOUT_ACTION: ActionId = "tackle";

export interface FighterInput {
  element: Element;
  /** Effective stats at the fighter's level (server computed). */
  stats: Stats;
  level: number;
}

/** Opaque, JSON-serialisable engine state. */
export interface EngineState {
  engine: string;
  seed: number;
  turn: number;
  [key: string]: unknown;
}

export interface BattleEvent {
  type: string;
  side?: Side;
  [key: string]: unknown;
}

export interface SideView {
  hp: number;
  maxHp: number;
  gauge: number;
}

export interface BattleView {
  /** Number of turns already resolved. */
  turn: number;
  finished: boolean;
  winner: Side | "draw" | null;
  a: SideView;
  b: SideView;
}

export interface BattleEngine {
  readonly id: string;
  init(a: FighterInput, b: FighterInput, seed: number): EngineState;
  legalActions(state: EngineState, side: Side): ActionId[];
  resolveTurn(state: EngineState, actionA: ActionId, actionB: ActionId): { state: EngineState; events: BattleEvent[] };
  view(state: EngineState): BattleView;
}

// ---------------------------------------------------------------------------
// Stub engine (placeholder until shared/battle_engine_ts is wired).

const TYPE_ADVANTAGE: Readonly<Record<Element, readonly Element[]>> = {
  fire: ["leaf"],
  leaf: ["thunder"],
  thunder: ["water"],
  water: ["fire"],
  shadow: ["rainbow"],
  rainbow: ["shadow"],
};

export function typeMultiplier(attacker: Element, defender: Element): number {
  if (TYPE_ADVANTAGE[attacker].includes(defender)) return 1.5;
  if (TYPE_ADVANTAGE[defender].includes(attacker) && attacker !== "shadow" && attacker !== "rainbow") {
    return 0.75;
  }
  return 1;
}

interface StubFighter {
  element: Element;
  level: number;
  stats: Stats;
  hp: number;
  maxHp: number;
  gauge: number;
  guardStreak: number;
}

interface StubState extends EngineState {
  engine: "stub-1";
  a: StubFighter;
  b: StubFighter;
  winner: Side | null;
}

const POWER: Record<Exclude<ActionId, "guard">, number> = { tackle: 40, element: 60, special: 120 };

function other(side: Side): Side {
  return side === "a" ? "b" : "a";
}

export class StubEngine implements BattleEngine {
  readonly id = "stub-1";

  init(a: FighterInput, b: FighterInput, seed: number): EngineState {
    const mk = (f: FighterInput): StubFighter => ({
      element: f.element,
      level: f.level,
      stats: { ...f.stats },
      hp: f.stats.hp * 3,
      maxHp: f.stats.hp * 3,
      gauge: 0,
      guardStreak: 0,
    });
    const s: StubState = { engine: "stub-1", seed: seed >>> 0, turn: 0, a: mk(a), b: mk(b), winner: null };
    return s;
  }

  legalActions(state: EngineState, side: Side): ActionId[] {
    const f = (state as StubState)[side];
    return f.gauge >= 100 ? [...ACTION_IDS] : ["tackle", "element", "guard"];
  }

  resolveTurn(state: EngineState, actionA: ActionId, actionB: ActionId): { state: EngineState; events: BattleEvent[] } {
    const s = structuredClone(state) as StubState;
    if (s.winner) return { state: s, events: [] };
    s.turn += 1;
    const rng = mulberry32(turnSeed(s.seed, s.turn));
    const actions: Record<Side, ActionId> = {
      a: this.legalActions(s, "a").includes(actionA) ? actionA : "tackle",
      b: this.legalActions(s, "b").includes(actionB) ? actionB : "tackle",
    };
    const events: BattleEvent[] = [];
    const first: Side =
      s.a.stats.spd === s.b.stats.spd ? (rng() < 0.5 ? "a" : "b") : s.a.stats.spd > s.b.stats.spd ? "a" : "b";
    const guarding: Record<Side, number> = { a: 0, b: 0 };
    for (const side of ["a", "b"] as const) {
      if (actions[side] === "guard") {
        const f = s[side];
        guarding[side] = [0.5, 0.25][f.guardStreak] ?? 0;
        f.guardStreak += 1;
        events.push({ type: "guard", side, reduction: guarding[side] });
      } else {
        s[side].guardStreak = 0;
      }
    }
    for (const side of [first, other(first)]) {
      const act = actions[side];
      if (act === "guard") continue;
      const atk = s[side];
      const def = s[other(side)];
      if (atk.hp <= 0) continue;
      if (act === "element" && rng() >= 0.9) {
        events.push({ type: "miss", side, action: act });
        continue;
      }
      let power = POWER[act];
      if (act === "special") {
        atk.gauge = 0;
        if (atk.level >= 20) power += 20;
      }
      const mult = act === "tackle" ? 1 : typeMultiplier(atk.element, def.element);
      const ratio = atk.stats.atk / Math.max(1, atk.stats.atk + def.stats.def);
      const variance = 0.9 + rng() * 0.1;
      const dmg = Math.max(1, Math.floor(power * ratio * 1.2 * mult * variance * (1 - guarding[other(side)])));
      def.hp = Math.max(0, def.hp - dmg);
      if (act !== "special") atk.gauge = Math.min(100, atk.gauge + 20);
      def.gauge = Math.min(100, def.gauge + 15);
      events.push({ type: "attack", side, action: act, damage: dmg, effectiveness: mult });
      if (def.hp === 0) {
        s.winner = side;
        events.push({ type: "ko", side: other(side) });
        break;
      }
    }
    return { state: s, events };
  }

  view(state: EngineState): BattleView {
    const s = state as StubState;
    const sv = (f: StubFighter): SideView => ({ hp: f.hp, maxHp: f.maxHp, gauge: f.gauge });
    return { turn: s.turn, finished: s.winner !== null, winner: s.winner, a: sv(s.a), b: sv(s.b) };
  }
}

// ---------------------------------------------------------------------------

let engine: BattleEngine = new StubEngine();

/** The engine used for all new matches. */
export function getEngine(): BattleEngine {
  return engine;
}

/** Test/wiring hook. */
export function setEngine(e: BattleEngine): void {
  engine = e;
}
