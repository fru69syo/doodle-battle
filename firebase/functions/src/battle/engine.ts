/**
 * Battle engine adapter.
 *
 * The server never implements battle rules itself: it delegates to the shared
 * TypeScript engine (`shared/battle_engine_ts`, vendored into
 * `src/vendor/battle_engine/` by `scripts/sync-shared.mjs`), the same rules the
 * app runs for CPU battles. Everything else in functions (matches, ghosts,
 * timeouts) only depends on the `BattleEngine` interface below.
 *
 * Contract:
 * - States and events are plain JSON (stored in Firestore as-is).
 * - `resolveTurn` is pure and deterministic. Randomness comes from the shared
 *   mulberry32 PRNG whose 32-bit state is stored *in* the engine state
 *   (`rngState`, initialised from `deriveSeed(match seed, 0)`), so a match is
 *   fully reproducible from its seed and action log, a turn needs nothing but
 *   the stored state, and the shared golden vectors replay through this
 *   adapter unchanged (docs/BATTLE.md §9).
 */
import {
  chooseCpuAction,
  defaultSpec,
  deriveSeed,
  initBattle,
  Mulberry32,
  resolveTurn as sharedResolveTurn,
  type BattleSpec,
  type BattleState,
  type BattleEvent as SharedBattleEvent,
} from "../vendor/battle_engine";
import type { Element, Stats } from "../stats/statLimits";

export type Side = "a" | "b";
export const ACTION_IDS = ["tackle", "element", "guard", "special"] as const;
export type ActionId = (typeof ACTION_IDS)[number];

/** The shared battle spec (shared/battle_spec/battle_spec.json). */
export const SPEC: BattleSpec = defaultSpec;

/** Action used when a player does not act within the turn limit (SPEC §5). */
export const TIMEOUT_ACTION: ActionId = SPEC.timeoutAction === "timeout" ? "tackle" : SPEC.timeoutAction;

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

/** Shared-engine events (docs/BATTLE.md §5), stored in turn logs. */
export type BattleEvent = SharedBattleEvent;

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
  /** How the engine ended the battle (KO, or the turn cap by HP ratio). */
  endReason: "ko" | "turn_limit" | null;
  a: SideView;
  b: SideView;
}

export interface BattleEngine {
  readonly id: string;
  init(a: FighterInput, b: FighterInput, seed: number): EngineState;
  legalActions(state: EngineState, side: Side): ActionId[];
  /**
   * `timedOut[side]` marks a player who ran out of time: the engine resolves
   * it as `TIMEOUT_ACTION` and emits a `timeout` event for the UI.
   */
  resolveTurn(
    state: EngineState,
    actionA: ActionId,
    actionB: ActionId,
    timedOut?: Partial<Record<Side, boolean>>,
  ): { state: EngineState; events: BattleEvent[] };
  view(state: EngineState): BattleView;
}

/** Stored state of the shared-engine adapter. */
export interface SharedEngineState extends EngineState {
  /** mulberry32 state to use for the next turn. */
  rngState: number;
  inner: BattleState;
}

/** Adapter over the shared engine; `id` changes whenever the spec version does. */
export class SharedEngine implements BattleEngine {
  readonly id: string;

  constructor(private readonly spec: BattleSpec = SPEC) {
    this.id = `shared-${spec.specVersion}`;
  }

  init(a: FighterInput, b: FighterInput, seed: number): SharedEngineState {
    const s = seed >>> 0;
    return {
      engine: this.id,
      seed: s,
      turn: 0,
      rngState: deriveSeed(s, 0),
      inner: initBattle(
        this.spec,
        { element: a.element, level: a.level, stats: { ...a.stats } },
        { element: b.element, level: b.level, stats: { ...b.stats } },
      ),
    };
  }

  /** Wraps an existing shared state (tests / golden vectors). */
  fromInner(inner: BattleState, seed: number, rngState: number): SharedEngineState {
    return { engine: this.id, seed: seed >>> 0, turn: inner.turn, rngState: rngState >>> 0, inner };
  }

  legalActions(state: EngineState, side: Side): ActionId[] {
    const inner = this.inner(state);
    if (inner.winner !== null) return [];
    return inner[side].gauge >= this.spec.gauge.max ? [...ACTION_IDS] : ["tackle", "element", "guard"];
  }

  resolveTurn(
    state: EngineState,
    actionA: ActionId,
    actionB: ActionId,
    timedOut: Partial<Record<Side, boolean>> = {},
  ): { state: SharedEngineState; events: BattleEvent[] } {
    const inner = this.inner(state);
    const s = state as SharedEngineState;
    if (inner.winner !== null) return { state: s, events: [] };
    const rng = new Mulberry32(s.rngState);
    const r = sharedResolveTurn(
      this.spec,
      inner,
      timedOut.a ? "timeout" : actionA,
      timedOut.b ? "timeout" : actionB,
      rng,
    );
    const next: SharedEngineState = { ...s, turn: r.state.turn, rngState: rng.state, inner: r.state };
    return { state: next, events: r.events };
  }

  view(state: EngineState): BattleView {
    const inner = this.inner(state);
    const sv = (side: Side): SideView => ({ hp: inner[side].hp, maxHp: inner[side].maxHp, gauge: inner[side].gauge });
    return {
      turn: inner.turn,
      finished: inner.winner !== null,
      winner: inner.winner,
      endReason: inner.endReason === null ? null : inner.endReason === "ko" ? "ko" : "turn_limit",
      a: sv("a"),
      b: sv("b"),
    };
  }

  /**
   * Ghost AI ("ふつう", SPEC §4.3) via the shared CPU AI. `aiSeed` gives the
   * AI's own rng seed for (match seed, upcoming turn), so it is deterministic
   * and never consumes battle rolls.
   */
  chooseGhostAction(state: EngineState, side: Side, aiSeed: (seed: number, turn: number) => number): ActionId {
    const inner = this.inner(state);
    const rng = new Mulberry32(aiSeed(state.seed, inner.turn + 1));
    const action = chooseCpuAction(this.spec, inner, side, "normal", rng);
    return this.legalActions(state, side).includes(action) ? action : TIMEOUT_ACTION;
  }

  private inner(state: EngineState): BattleState {
    const s = state as SharedEngineState;
    if (s.engine !== this.id) throw new Error(`state of engine ${s.engine} given to ${this.id}`);
    return s.inner;
  }
}

// ---------------------------------------------------------------------------

let engine: SharedEngine = new SharedEngine();

/** The engine used for all new matches. */
export function getEngine(): SharedEngine {
  return engine;
}

/** Test/wiring hook (e.g. to simulate a deploy that changes the spec). */
export function setEngine(e: SharedEngine): void {
  engine = e;
}
