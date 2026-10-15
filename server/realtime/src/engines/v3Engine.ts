/**
 * Engine v3 adapter (docs/REALTIME_PROTOCOL.md §9): a thin pass-through from the shared,
 * bit-exact Engine v3 (`shared/battle_engine_v3_ts`, `RealtimeBattle`) to the server's
 * `BattleEngine` interface.
 *
 * Hidden state: a v2 snapshot's `engine.trust` (and everything derived from it, such as the
 * late-bloomer form) is engine INPUT only. It shapes the stats inside `engineData`, but nothing
 * here copies it into the public part of a `FighterSetup` (attr, public moves, maxHp), and the
 * battle events / side views come from the engine, which never mentions it. The hub only sends
 * the public part (test/unit/v3Engine.test.ts and test/integration/v3.test.ts check every
 * protocol message of a match).
 */
import {
  DEFAULT_SPEC,
  ENGINE_ID,
  RATED_SYNC_LEVEL,
  RealtimeBattle,
  publicMoves,
  ratedFighterFromSnapshot,
  type FighterSetup as V3Setup,
  type V3Spec,
} from "@doodle-battle/battle-engine-v3";
import {
  UnsupportedFighterError,
  type AiTier,
  type BattleEngine,
  type BattleSim,
  type FighterSetup,
  type FighterSource,
  type Side,
  type SideView,
  type StepResult,
} from "../engine";

/** The engine input of a v2 snapshot (`snapshots/{id}.engine`, written by registerCharacter). */
function engineInput(source: FighterSource): Record<string, unknown> {
  const d = source.data;
  const e = d.engine;
  if (d.schema !== 2 || typeof e !== "object" || e === null || Array.isArray(e)) {
    throw new UnsupportedFighterError(`snapshot ${source.snapshotId} is not a v2 (schema 2) character`);
  }
  return e as Record<string, unknown>;
}

class V3Sim implements BattleSim {
  private readonly rt: RealtimeBattle;

  constructor(a: V3Setup, b: V3Setup, seed: number, spec: V3Spec) {
    this.rt = new RealtimeBattle(a, b, seed, spec);
  }

  get tick(): number {
    return this.rt.tick;
  }

  get finished(): boolean {
    return this.rt.finished;
  }

  get winner(): Side | null {
    return this.rt.winner;
  }

  get endReason(): "ko" | "timeout" | null {
    return this.rt.endReason;
  }

  step(inputs: readonly [number | null, number | null]): StepResult {
    const r = this.rt.step(inputs);
    return { events: r.events, acted: r.acted };
  }

  canUse(side: Side, slot: number): boolean {
    return this.rt.canUse(side, slot);
  }

  canQueue(side: Side, slot: number): boolean {
    return this.rt.canQueue(side, slot);
  }

  aiInput(side: Side, tier: AiTier, thinkTicks: number): number | null {
    return this.rt.aiInput(side, tier, thinkTicks);
  }

  omakaseInput(side: Side): number | null {
    return this.rt.omakaseInput(side);
  }

  clearPlan(side: Side): void {
    this.rt.clearPlan(side);
  }

  view(side: Side): SideView {
    return this.rt.view(side);
  }

  stateHash(): string {
    return this.rt.stateHash();
  }
}

export class V3Engine implements BattleEngine {
  readonly engineId = ENGINE_ID;
  readonly tickHz: number;
  readonly hardCapTick: number;

  constructor(private readonly spec: V3Spec = DEFAULT_SPEC) {
    this.tickHz = spec.tickHz;
    this.hardCapTick = spec.hardCapTick;
  }

  /**
   * Rated fighter: v3 `ratedSetup` at the character's REAL level (own growth, Lv50 stat sync,
   * moves unlocked at the real level: 2 / 3 at Lv10 / 4 at Lv50).
   */
  ratedFighter(source: FighterSource, syncLevel: number): FighterSetup {
    if (syncLevel !== RATED_SYNC_LEVEL) throw new Error(`engine v3 syncs rated play to Lv${RATED_SYNC_LEVEL}, not Lv${syncLevel}`);
    const f = ratedFighterFromSnapshot(engineInput(source), source.level, this.spec);
    if (!f) throw new UnsupportedFighterError(`snapshot ${source.snapshotId} has invalid engine data`);
    return { attr: f.setup.attr, moves: publicMoves(f.setup), maxHp: f.maxHp, maxBars: f.setup.maxBars, engineData: f.setup };
  }

  createBattle(a: FighterSetup, b: FighterSetup, opts: { seed: number }): BattleSim {
    return new V3Sim(a.engineData as V3Setup, b.engineData as V3Setup, opts.seed >>> 0, this.spec);
  }
}
